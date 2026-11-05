import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:atmos_trs_system/config/ae_register_schema.dart';
import 'package:atmos_trs_system/config/dae_residence_catalog.dart';
import 'package:atmos_trs_system/models/ae_register.dart';
import 'package:atmos_trs_system/services/ae_room_inventory_service.dart';
import 'package:atmos_trs_system/utils/ae_guest_count_validation.dart';
import 'package:atmos_trs_system/utils/ae_register_calculator.dart';
import 'package:atmos_trs_system/utils/php_currency_input.dart';
import 'package:atmos_trs_system/widgets/ae_register/ae_sheet_kit.dart';
import 'package:atmos_trs_system/widgets/establishment_dash_tokens.dart';

enum AeRowDialogMode { stay, single, edit }

/// Entry form for the Daily Register. "Stay" expands guests × nights into
/// nightly rows (first night = checked-in day), mirroring the client formula.
///
/// Shared by **Add Stay** and **Add Single Night** (and Edit).
class AeRegisterRowDialog extends StatefulWidget {
  const AeRegisterRowDialog({
    super.key,
    required this.mode,
    required this.schema,
    required this.year,
    required this.month,
    required this.totalRooms,
    required this.showCharges,
    this.initial,
    this.lastRate = 0,
    this.blankDefaults = false,
    this.establishmentId = '',
    this.roomLabels = const [],
    this.onInventoryChanged,
  });

  final AeRowDialogMode mode;
  final AeRegisterSchema schema;
  final int year;
  final int month;
  final int totalRooms;
  final bool showCharges;
  final AeRegisterRow? initial;
  final double lastRate;

  /// When true (Add Single Night), ignore lastRate / stay convenience defaults.
  final bool blankDefaults;

  /// Authenticated AE id — required to persist "+ Add New Room".
  final String establishmentId;

  /// Explicit room identifiers from the establishment inventory (optional).
  final List<String> roomLabels;

  /// Fired after a room is saved so Profile / Register capacity can sync.
  final ValueChanged<AeRoomInventory>? onInventoryChanged;

  static Future<List<AeRegisterRow>?> show(
    BuildContext context, {
    required AeRowDialogMode mode,
    required AeRegisterSchema schema,
    required int year,
    required int month,
    required int totalRooms,
    required bool showCharges,
    AeRegisterRow? initial,
    double lastRate = 0,
    bool blankDefaults = false,
    String establishmentId = '',
    List<String> roomLabels = const [],
    ValueChanged<AeRoomInventory>? onInventoryChanged,
  }) =>
      showDialog<List<AeRegisterRow>>(
        context: context,
        barrierColor: const Color(0xFF0F172A).withValues(alpha: 0.45),
        // Fresh State every open — never reuse a previous form's controllers.
        builder: (_) => AeRegisterRowDialog(
          key: UniqueKey(),
          mode: mode,
          schema: schema,
          year: year,
          month: month,
          totalRooms: totalRooms,
          showCharges: showCharges,
          initial: initial,
          lastRate: lastRate,
          // New Stay and Single Night both open blank (Edit still uses [initial]).
          blankDefaults: blankDefaults || initial == null,
          establishmentId: establishmentId,
          roomLabels: roomLabels,
          onInventoryChanged: onInventoryChanged,
        ),
      );

  @override
  State<AeRegisterRowDialog> createState() => _AeRegisterRowDialogState();
}

class _AeRegisterRowDialogState extends State<AeRegisterRowDialog> {
  late DateTime _date;
  late String _room;
  late String _residence;
  late String _phRegion;
  late bool _checkedIn;
  late final TextEditingController _residenceCtrl;
  final _guests = TextEditingController();
  final _female = TextEditingController();
  final _male = TextEditingController();
  final _nights = TextEditingController(text: '1');
  final _rate = TextEditingController();
  final _chargesA = TextEditingController();
  final _chargesB = TextEditingController();
  final _rateFocus = FocusNode();
  final _chargesAFocus = FocusNode();
  final _chargesBFocus = FocusNode();

  String? _error;
  String? _guestsError;
  String? _femaleError;
  String? _maleError;
  String? _guestSectionError;
  String? _rateError;
  late int _capacity;
  late List<String> _labels;
  bool _addingRoom = false;
  bool _guestTouched = false;

  /// Last gender field the user edited — used when Total Guests changes.
  /// 0 = none, 1 = female, 2 = male.
  int _lastGenderEdited = 0;
  bool _applyingGuestComplement = false;

  bool get _isStay =>
      widget.mode == AeRowDialogMode.stay && widget.schema.tracksNights;
  bool get _canAddRoom =>
      widget.schema.tracksRooms &&
      widget.establishmentId.trim().isNotEmpty &&
      widget.mode != AeRowDialogMode.edit;

  DateTime get _defaultRegisterDate {
    final now = DateTime.now();
    final inMonth = now.year == widget.year && now.month == widget.month;
    return DateTime(widget.year, widget.month, inMonth ? now.day : 1);
  }

  @override
  void initState() {
    super.initState();
    _residenceCtrl = TextEditingController();
    _capacity = widget.totalRooms;
    _labels = AeRoomInventoryService.parseLabels(
      widget.roomLabels,
      fallbackCount: widget.totalRooms,
    );
    _rateFocus.addListener(_onRateFocus);
    _chargesAFocus.addListener(_onChargesAFocus);
    _chargesBFocus.addListener(_onChargesBFocus);

    final i = widget.initial;
    if (i != null) {
      _applyEditRow(i);
    } else if (widget.mode == AeRowDialogMode.stay) {
      resetAddStayForm();
    } else {
      resetAddSingleNightForm();
    }
  }

  /// Clean NEW Add Stay — no Philippines / last-rate / guest convenience prefills.
  void resetAddStayForm() {
    _resetNewEntryCommon(checkedInDay: true);
    _nights.text = '1';
  }

  /// Clean NEW Add Single Night — same blanks; Checked-in Day starts unchecked.
  void resetAddSingleNightForm() {
    _resetNewEntryCommon(checkedInDay: false);
    _nights.text = '1';
  }

  void _resetNewEntryCommon({required bool checkedInDay}) {
    _date = _defaultRegisterDate;
    _room = '';
    _residence = '';
    _residenceCtrl
      ..text = ''
      ..selection = const TextSelection.collapsed(offset: 0);
    _phRegion = '';
    _checkedIn = checkedInDay;
    _guests.text = '0';
    _female.text = '0';
    _male.text = '0';
    _rate.clear();
    _chargesA.clear();
    _chargesB.clear();
    _guestTouched = false;
    _lastGenderEdited = 0;
    _applyingGuestComplement = false;
    _error = null;
    _guestsError = null;
    _femaleError = null;
    _maleError = null;
    _guestSectionError = null;
    _rateError = null;
  }

  void _applyEditRow(AeRegisterRow i) {
    _date = i.date;
    _room = i.roomNo;
    _residence = i.residence;
    _residenceCtrl.text = i.residence;
    _phRegion = i.phRegion;
    _checkedIn = i.checkedInDay;
    _guests.text = '${i.guests}';
    _female.text = '${i.female}';
    _male.text = '${i.male}';
    _rate.text = i.rate <= 0 ? '' : PhpCurrencyInput.format(i.rate);
    _chargesA.text =
        i.chargesA <= 0 ? '' : PhpCurrencyInput.format(i.chargesA);
    _chargesB.text =
        i.chargesB <= 0 ? '' : PhpCurrencyInput.format(i.chargesB);
    _guestTouched = true;
    _revalidateGuests();
  }

  void _onRateFocus() {
    if (_rateFocus.hasFocus) {
      final v = PhpCurrencyInput.tryParse(_rate.text);
      if (v != null && v > 0) {
        _rate.text = v == v.roundToDouble()
            ? v.toInt().toString()
            : v.toStringAsFixed(2);
        _rate.selection = TextSelection.collapsed(offset: _rate.text.length);
      }
    } else {
      _formatMoneyField(_rate);
      _revalidateRate();
    }
  }

  void _onChargesAFocus() {
    if (_chargesAFocus.hasFocus) {
      final v = PhpCurrencyInput.tryParse(_chargesA.text);
      if (v != null && v > 0) {
        _chargesA.text = v == v.roundToDouble()
            ? v.toInt().toString()
            : v.toStringAsFixed(2);
      }
    } else {
      _formatMoneyField(_chargesA);
    }
  }

  void _onChargesBFocus() {
    if (_chargesBFocus.hasFocus) {
      final v = PhpCurrencyInput.tryParse(_chargesB.text);
      if (v != null && v > 0) {
        _chargesB.text = v == v.roundToDouble()
            ? v.toInt().toString()
            : v.toStringAsFixed(2);
      }
    } else {
      _formatMoneyField(_chargesB);
    }
  }

  void _formatMoneyField(TextEditingController c) {
    final v = PhpCurrencyInput.tryParse(c.text);
    if (v == null) return;
    if (v == 0 && c.text.trim().isEmpty) return;
    c.text = PhpCurrencyInput.format(v);
  }

  List<String> get _roomOptions {
    final base = _labels.isNotEmpty
        ? List<String>.from(_labels)
        : [
            for (var r = 1; r <= (_capacity < 0 ? 0 : _capacity); r++) '$r',
          ];
    final cur = _room.trim();
    if (cur.isNotEmpty &&
        !base.any((e) => e.toLowerCase() == cur.toLowerCase())) {
      base.add(cur);
    }
    return base;
  }

  bool _roomOptionValid(String room) {
    final t = room.trim();
    if (t.isEmpty) return false;
    return _roomOptions.any((e) => e.toLowerCase() == t.toLowerCase());
  }

  Future<void> _addNewRoom() async {
    if (!_canAddRoom || _addingRoom) return;
    final inventory =
        AeRoomInventory(roomCount: _capacity, roomLabels: _labels);
    final suggested = AeRoomInventoryService.suggestNext(inventory);
    final entered = await showDialog<String>(
      context: context,
      builder: (ctx) => _AddRoomDialog(suggested: suggested),
    );
    if (entered == null || !mounted) return;
    setState(() {
      _addingRoom = true;
      _error = null;
    });
    try {
      final next = await AeRoomInventoryService.addRoom(
        establishmentId: widget.establishmentId,
        roomId: entered,
      );
      if (!mounted) return;
      setState(() {
        _capacity = next.roomCount;
        _labels = List<String>.from(next.roomLabels);
        _room = entered.trim();
        _addingRoom = false;
      });
      widget.onInventoryChanged?.call(next);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _addingRoom = false;
        _error = e.toString().replaceFirst('StateError: ', '');
      });
    }
  }

  @override
  void dispose() {
    _rateFocus.removeListener(_onRateFocus);
    _chargesAFocus.removeListener(_onChargesAFocus);
    _chargesBFocus.removeListener(_onChargesBFocus);
    _rateFocus.dispose();
    _chargesAFocus.dispose();
    _chargesBFocus.dispose();
    _residenceCtrl.dispose();
    for (final c in [
      _guests,
      _female,
      _male,
      _nights,
      _rate,
      _chargesA,
      _chargesB,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  void _revalidateGuests() {
    final guests = AeGuestCountValidation.parseWhole(_guests.text);
    final female = AeGuestCountValidation.parseWhole(_female.text);
    final male = AeGuestCountValidation.parseWhole(_male.text);
    // Fresh zero state: no inline errors until the user interacts / submits.
    if (!_guestTouched &&
        guests == 0 &&
        female == 0 &&
        male == 0) {
      _guestsError = null;
      _femaleError = null;
      _maleError = null;
      _guestSectionError = null;
      return;
    }
    final err = AeGuestCountValidation.validate(
      guests: guests,
      female: female,
      male: male,
      requireParsed: _guestTouched,
    );
    // One section message — avoid duplicating the same text under Female + Male.
    _guestSectionError = err?.summary;
    _guestsError = err?.guests;
    _femaleError = err?.female;
    _maleError = err?.male;
    if (err?.summaryOnly != null) {
      _femaleError = null;
      _maleError = null;
    }
  }

  void _revalidateRate() {
    if (_rate.text.trim().isEmpty) {
      _rateError = null;
      return;
    }
    _rateError = PhpCurrencyInput.isValidNonNegative(_rate.text)
        ? null
        : 'Enter a valid non-negative amount.';
  }

  /// Auto-fill the opposite gender without writing into the field being typed.
  void _applyGuestComplement({
    required bool fromFemale,
    required bool fromMale,
    required bool fromTotal,
  }) {
    if (_applyingGuestComplement) return;
    final total = AeGuestCountValidation.parseWhole(_guests.text);
    if (total == null) return;

    void setOpposite(TextEditingController target, int value) {
      _applyingGuestComplement = true;
      final next = '$value';
      if (target.text != next) target.text = next;
      _applyingGuestComplement = false;
    }

    if (fromFemale || (fromTotal && _lastGenderEdited == 1)) {
      final female = AeGuestCountValidation.parseWhole(_female.text);
      if (female == null) return;
      final male = AeGuestCountValidation.complement(
        total: total,
        known: female,
      );
      if (male == null) return; // exceeds total — leave male; validation shows error
      setOpposite(_male, male);
      return;
    }

    if (fromMale || (fromTotal && _lastGenderEdited == 2)) {
      final male = AeGuestCountValidation.parseWhole(_male.text);
      if (male == null) return;
      final female = AeGuestCountValidation.complement(
        total: total,
        known: male,
      );
      if (female == null) return;
      setOpposite(_female, female);
      return;
    }

    // Total changed but neither gender has been edited yet — do not assign all
    // guests to Male/Female automatically.
  }

  void _onTotalGuestsChanged() {
    if (_applyingGuestComplement) return;
    _guestTouched = true;
    _applyGuestComplement(
      fromFemale: false,
      fromMale: false,
      fromTotal: true,
    );
    setState(_revalidateGuests);
  }

  void _onFemaleChanged() {
    if (_applyingGuestComplement) return;
    _guestTouched = true;
    _lastGenderEdited = 1;
    _applyGuestComplement(
      fromFemale: true,
      fromMale: false,
      fromTotal: false,
    );
    setState(_revalidateGuests);
  }

  void _onMaleChanged() {
    if (_applyingGuestComplement) return;
    _guestTouched = true;
    _lastGenderEdited = 2;
    _applyGuestComplement(
      fromFemale: false,
      fromMale: true,
      fromTotal: false,
    );
    setState(_revalidateGuests);
  }

  bool get _guestCountsValid =>
      AeGuestCountValidation.validate(
        guests: AeGuestCountValidation.parseWhole(_guests.text),
        female: AeGuestCountValidation.parseWhole(_female.text),
        male: AeGuestCountValidation.parseWhole(_male.text),
      ) ==
      null;

  bool get _moneyValid {
    if (_rate.text.trim().isNotEmpty &&
        !PhpCurrencyInput.isValidNonNegative(_rate.text)) {
      return false;
    }
    if (widget.showCharges) {
      if (_chargesA.text.trim().isNotEmpty &&
          !PhpCurrencyInput.isValidNonNegative(_chargesA.text)) {
        return false;
      }
      if (_chargesB.text.trim().isNotEmpty &&
          !PhpCurrencyInput.isValidNonNegative(_chargesB.text)) {
        return false;
      }
    }
    return true;
  }

  bool get _residenceChosen {
    final text = _residenceCtrl.text.trim().isNotEmpty
        ? _residenceCtrl.text.trim()
        : _residence.trim();
    return text.isNotEmpty && text != DaeResidenceCatalog.unspecified;
  }

  bool get _roomChosen =>
      !widget.schema.tracksRooms || _roomOptionValid(_room);

  bool get _nightsValid {
    if (!_isStay) return true;
    final n = int.tryParse(_nights.text.trim());
    return n != null && n >= 1 && n <= 60;
  }

  bool get _canSubmit =>
      _guestCountsValid &&
      _moneyValid &&
      _nightsValid &&
      _residenceChosen &&
      _roomChosen &&
      !_addingRoom;

  Future<void> _pickDate() async {
    final first = _isStay
        ? DateTime(widget.year, widget.month - 1, 1)
        : DateTime(widget.year, widget.month, 1);
    final last = _isStay
        ? DateTime(widget.year, widget.month + 1, 0)
        : DateTime(widget.year, widget.month + 1, 0);
    final picked = await showDatePicker(
      context: context,
      initialDate:
          _date.isBefore(first) || _date.isAfter(last) ? first : _date,
      firstDate: first,
      lastDate: last,
    );
    if (picked != null) setState(() => _date = picked);
  }

  void _submit() {
    setState(() {
      _guestTouched = true;
      _error = null;
      _revalidateGuests();
      _revalidateRate();
    });
    if (!_canSubmit) {
      setState(() {
        _error = _guestSectionError ??
            _guestsError ??
            _femaleError ??
            _maleError ??
            _rateError ??
            'Please fix the highlighted fields.';
      });
      return;
    }

    final s = widget.schema;
    final guests = AeGuestCountValidation.parseWhole(_guests.text)!;
    final female = AeGuestCountValidation.parseWhole(_female.text)!;
    final male = AeGuestCountValidation.parseWhole(_male.text)!;

    final residenceText = _residenceCtrl.text.trim().isNotEmpty
        ? _residenceCtrl.text.trim()
        : _residence.trim();
    if (residenceText.isEmpty ||
        residenceText == DaeResidenceCatalog.unspecified) {
      return setState(
        () => _error = 'Choose a residence / nationality.',
      );
    }
    final residence = residenceText;

    if (s.tracksRooms) {
      if (_room.trim().isEmpty) {
        return setState(() => _error = 'Pick a room number.');
      }
      final editingExisting = widget.initial != null;
      if (!editingExisting && !_roomOptionValid(_room)) {
        return setState(
          () => _error =
              'Room ${_room.trim()} is not in the current $_capacity available rooms. '
              'Use + Add New Room first.',
        );
      }
    }
    final phRegion =
        DaeResidenceCatalog.bucketFor(residence) ==
                DaeResidenceBucket.philippineResident
            ? _phRegion
            : '';
    final rate = PhpCurrencyInput.tryParse(_rate.text) ?? 0;
    final a = widget.showCharges
        ? (PhpCurrencyInput.tryParse(_chargesA.text) ?? 0)
        : (widget.initial?.chargesA ?? 0);
    final b = widget.showCharges
        ? (PhpCurrencyInput.tryParse(_chargesB.text) ?? 0)
        : (widget.initial?.chargesB ?? 0);

    if (_isStay) {
      final nights = int.tryParse(_nights.text.trim()) ?? 0;
      if (nights < 1 || nights > 60) {
        return setState(() => _error = 'Nights must be 1–60.');
      }
      Navigator.pop(
        context,
        AeRegisterCalculator.expandStay(
          checkIn: _date,
          nights: nights,
          roomNo: _room.trim(),
          residence: residence,
          phRegion: phRegion,
          guests: guests,
          female: female,
          male: male,
          rate: rate,
          chargesA: a,
          chargesB: b,
        ),
      );
      return;
    }
    Navigator.pop(context, [
      AeRegisterRow(
        id: widget.initial?.id ?? '',
        date: _date,
        roomNo: s.tracksRooms ? _room.trim() : '',
        residence: residence,
        phRegion: phRegion,
        guests: guests,
        female: female,
        male: male,
        checkedInDay: s.tracksNights ? _checkedIn : true,
        rate: rate,
        chargesA: a,
        chargesB: b,
        isDemo: widget.initial?.isDemo ?? false,
      ),
    ]);
  }

  String get _title {
    final s = widget.schema;
    return switch (widget.mode) {
      AeRowDialogMode.stay => s.tracksNights ? 'Add Stay' : 'Add Record',
      AeRowDialogMode.single => 'Add Single Night',
      AeRowDialogMode.edit => 'Edit Record',
    };
  }

  String get _subtitle {
    final s = widget.schema;
    return switch (widget.mode) {
      AeRowDialogMode.stay => s.tracksNights
          ? 'Add an occupied room record (guests × nights).'
          : 'Add an occupied room record.',
      AeRowDialogMode.single =>
        'Add one occupied room-night to the daily register.',
      AeRowDialogMode.edit => 'Update this daily register row.',
    };
  }

  IconData get _headerIcon {
    return switch (widget.mode) {
      AeRowDialogMode.single => Icons.nightlight_round,
      AeRowDialogMode.edit => Icons.edit_rounded,
      AeRowDialogMode.stay => Icons.bed_rounded,
    };
  }

  String get _primaryLabel {
    return switch (widget.mode) {
      AeRowDialogMode.edit => 'Save',
      AeRowDialogMode.single => 'Add Night',
      AeRowDialogMode.stay => 'Add Stay',
    };
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.schema;
    final isPh = DaeResidenceCatalog.bucketFor(_residence) ==
        DaeResidenceBucket.philippineResident;
    final roomOpts = _roomOptions;
    final digits = [FilteringTextInputFormatter.digitsOnly];
    final money = [
      FilteringTextInputFormatter.allow(RegExp(r'[0-9.,₱]')),
    ];
    final media = MediaQuery.sizeOf(context);
    final wide = media.width >= 640;
    final modalWidth = media.width < 640
        ? (media.width * 0.94).clamp(320.0, 640.0)
        : 620.0;
    final maxBodyHeight = media.height * 0.72;

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: EdgeInsets.symmetric(
        horizontal: media.width < 480 ? 12 : 24,
        vertical: 18,
      ),
      child: Material(
        color: Colors.white,
        elevation: 18,
        shadowColor: const Color(0xFF0F172A).withValues(alpha: 0.22),
        borderRadius: BorderRadius.circular(18),
        clipBehavior: Clip.antiAlias,
        child: SizedBox(
          width: modalWidth,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildHeader(context),
              ConstrainedBox(
                constraints: BoxConstraints(maxHeight: maxBodyHeight),
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(18, 14, 18, 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _sectionCard(
                        icon: Icons.event_available_rounded,
                        title: 'Stay Details',
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            _responsiveRow(
                              wide: wide,
                              children: [
                                _field(
                                  label: _isStay ? 'Check-in Date' : 'Date',
                                  required: true,
                                  child: InkWell(
                                    onTap: _pickDate,
                                    borderRadius: BorderRadius.circular(10),
                                    child: InputDecorator(
                                      decoration: _dec(
                                        suffix: const Icon(
                                          Icons.calendar_month_rounded,
                                          size: 18,
                                          color: AeDashTokens.accent,
                                        ),
                                      ),
                                      child: Text(
                                        AeSheetKit.shortDate(_date),
                                        style: AeDashTokens.body(
                                          size: 13.5,
                                          weight: FontWeight.w600,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                                if (_isStay)
                                  _field(
                                    label: 'Nights',
                                    required: true,
                                    child: TextField(
                                      controller: _nights,
                                      keyboardType: TextInputType.number,
                                      inputFormatters: digits,
                                      decoration: _dec(),
                                    ),
                                  ),
                                if (s.tracksRooms)
                                  _field(
                                    label: 'Room No.',
                                    required: true,
                                    child: roomOpts.isNotEmpty
                                        ? DropdownButtonFormField<String>(
                                            key: ValueKey(
                                              'room-dd-$_capacity-${roomOpts.length}-$_room',
                                            ),
                                            initialValue: _roomOptionValid(_room)
                                                ? _room
                                                : null,
                                            isExpanded: true,
                                            menuMaxHeight: 280,
                                            hint: Text(
                                              'Select room',
                                              style: AeDashTokens.body(
                                                size: 13,
                                                color: AeDashTokens.muted,
                                              ),
                                            ),
                                            decoration: _dec(
                                              hint: 'Select room',
                                            ),
                                            items: [
                                              for (final r in roomOpts)
                                                DropdownMenuItem(
                                                  value: r,
                                                  child: Text(
                                                    r,
                                                    style: TextStyle(
                                                      fontWeight: r == _room
                                                          ? FontWeight.w800
                                                          : FontWeight.w500,
                                                      color: r == _room
                                                          ? AeDashTokens.accent
                                                          : AeDashTokens.text,
                                                    ),
                                                  ),
                                                ),
                                            ],
                                            onChanged: (v) => setState(
                                              () => _room = v ?? '',
                                            ),
                                          )
                                        : TextFormField(
                                            initialValue: _room,
                                            decoration: _dec(
                                              hint: 'Select room',
                                            ),
                                            onChanged: (v) => _room = v,
                                          ),
                                  ),
                              ],
                            ),
                            if (_canAddRoom)
                              Align(
                                alignment: Alignment.centerRight,
                                child: TextButton.icon(
                                  onPressed:
                                      _addingRoom ? null : _addNewRoom,
                                  icon: _addingRoom
                                      ? const SizedBox(
                                          width: 14,
                                          height: 14,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                          ),
                                        )
                                      : const Icon(
                                          Icons.add_rounded,
                                          size: 16,
                                        ),
                                  label: Text(
                                    _addingRoom
                                        ? 'Saving room…'
                                        : '+ Add New Room',
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w700,
                                      fontSize: 12.5,
                                    ),
                                  ),
                                  style: TextButton.styleFrom(
                                    foregroundColor: AeDashTokens.accent,
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 4,
                                    ),
                                    visualDensity: VisualDensity.compact,
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),
                      _sectionCard(
                        icon: Icons.public_rounded,
                        title: 'Nationality',
                        child: _responsiveRow(
                          wide: wide &&
                              isPh &&
                              s.has(AeRegisterColumn.phRegion),
                          children: [
                            _field(
                              label: 'Residence / Nationality',
                              required: true,
                              child: LayoutBuilder(
                                builder: (context, constraints) {
                                  final hasSelection = _residence.isNotEmpty &&
                                      DaeResidenceCatalog.pickerOptions
                                          .contains(_residence);
                                  return DropdownMenu<String>(
                                    key: ValueKey(
                                      'residence-${hasSelection ? _residence : 'empty'}',
                                    ),
                                    controller: _residenceCtrl,
                                    initialSelection:
                                        hasSelection ? _residence : null,
                                    enableFilter: true,
                                    requestFocusOnTap: true,
                                    width: constraints.maxWidth,
                                    menuHeight: 300,
                                    hintText: 'Choose your nationality',
                                    leadingIcon: const Icon(
                                      Icons.flag_rounded,
                                      size: 18,
                                      color: AeDashTokens.accent,
                                    ),
                                    trailingIcon: const Icon(
                                      Icons.arrow_drop_down_rounded,
                                      color: AeDashTokens.muted,
                                    ),
                                    inputDecorationTheme:
                                        _dropdownDecorationTheme(),
                                    dropdownMenuEntries: [
                                      for (final o
                                          in DaeResidenceCatalog.pickerOptions)
                                        DropdownMenuEntry<String>(
                                          value: o,
                                          label: o,
                                        ),
                                    ],
                                    onSelected: (v) {
                                      if (v == null) return;
                                      setState(() {
                                        _residence = v;
                                        _residenceCtrl.value =
                                            TextEditingValue(
                                          text: v,
                                          selection: TextSelection.collapsed(
                                            offset: v.length,
                                          ),
                                        );
                                        if (DaeResidenceCatalog.bucketFor(v) !=
                                            DaeResidenceBucket
                                                .philippineResident) {
                                          _phRegion = '';
                                        }
                                      });
                                    },
                                  );
                                },
                              ),
                            ),
                            if (isPh && s.has(AeRegisterColumn.phRegion))
                              _field(
                                label: 'PH Origin Region (Optional)',
                                child: DropdownButtonFormField<String>(
                                  initialValue:
                                      _phRegion.isEmpty ? null : _phRegion,
                                  isExpanded: true,
                                  hint: Text(
                                    'Select PH region (optional)',
                                    style: AeDashTokens.body(
                                      size: 13,
                                      color: AeDashTokens.muted,
                                    ),
                                  ),
                                  decoration: _dec(
                                    hint: 'Select PH region (optional)',
                                  ),
                                  items: [
                                    const DropdownMenuItem(
                                      value: '',
                                      child: Text('Not specified'),
                                    ),
                                    for (final r
                                        in DaeResidenceCatalog
                                            .philippineRegions)
                                      DropdownMenuItem(
                                        value: r,
                                        child: Text(r),
                                      ),
                                  ],
                                  onChanged: (v) =>
                                      setState(() => _phRegion = v ?? ''),
                                ),
                              ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),
                      _sectionCard(
                        icon: Icons.groups_rounded,
                        title: 'Guest Count',
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 8,
                              ),
                              decoration: BoxDecoration(
                                color: AeDashTokens.softAccent,
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(
                                  color: AeDashTokens.accent
                                      .withValues(alpha: 0.22),
                                ),
                              ),
                              child: Row(
                                children: [
                                  const Icon(
                                    Icons.info_outline_rounded,
                                    size: 16,
                                    color: AeDashTokens.accent,
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      'Enter Total Guests, then Female or Male — the other count fills in automatically.',
                                      style: AeDashTokens.body(
                                        size: 12,
                                        color: const Color(0xFF9A3412),
                                        weight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 12),
                            _responsiveRow(
                              wide: wide,
                              children: [
                                _field(
                                  label: s.guestsLabel,
                                  required: true,
                                  child: TextField(
                                    controller: _guests,
                                    keyboardType: TextInputType.number,
                                    inputFormatters: digits,
                                    decoration: _dec(
                                      error: _guestsError != null ||
                                          (_guestSectionError != null &&
                                              _guestsError != null),
                                      prefixIcon: Icons.groups_rounded,
                                    ),
                                    onChanged: (_) => _onTotalGuestsChanged(),
                                  ),
                                ),
                                _field(
                                  label: 'Female',
                                  required: true,
                                  child: TextField(
                                    controller: _female,
                                    keyboardType: TextInputType.number,
                                    inputFormatters: digits,
                                    decoration: _dec(
                                      error: _femaleError != null,
                                      prefixIcon: Icons.woman_rounded,
                                      hint: _lastGenderEdited == 2
                                          ? 'Auto'
                                          : null,
                                    ),
                                    onChanged: (_) => _onFemaleChanged(),
                                  ),
                                ),
                                _field(
                                  label: 'Male',
                                  required: true,
                                  child: TextField(
                                    controller: _male,
                                    keyboardType: TextInputType.number,
                                    inputFormatters: digits,
                                    decoration: _dec(
                                      error: _maleError != null,
                                      prefixIcon: Icons.man_rounded,
                                      hint: _lastGenderEdited == 1
                                          ? 'Auto'
                                          : null,
                                    ),
                                    onChanged: (_) => _onMaleChanged(),
                                  ),
                                ),
                              ],
                            ),
                            if (_guestSectionError != null) ...[
                              const SizedBox(height: 8),
                              Text(
                                _guestSectionError!,
                                style: AeDashTokens.body(
                                  size: 11.5,
                                  color: AeDashTokens.danger,
                                  weight: FontWeight.w700,
                                ),
                              ),
                            ],
                            if (s.tracksNights && !_isStay)
                              CheckboxListTile(
                                value: _checkedIn,
                                contentPadding: EdgeInsets.zero,
                                dense: true,
                                controlAffinity:
                                    ListTileControlAffinity.leading,
                                title: const Text(
                                  'Checked-in day (guests arrived on this date)',
                                ),
                                onChanged: (v) =>
                                    setState(() => _checkedIn = v ?? false),
                              ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),
                      _sectionCard(
                        icon: Icons.account_balance_wallet_outlined,
                        title: 'Rate',
                        child: _responsiveRow(
                          wide: wide &&
                              widget.showCharges &&
                              s.has(AeRegisterColumn.chargesA),
                          children: [
                            _field(
                              label: s.rateLabel,
                              errorText: _rateError,
                              child: TextField(
                                controller: _rate,
                                focusNode: _rateFocus,
                                keyboardType:
                                    const TextInputType.numberWithOptions(
                                  decimal: true,
                                ),
                                inputFormatters: money,
                                decoration: _dec(
                                  hint: 'Enter daily rate',
                                  prefix: '₱ ',
                                  error: _rateError != null,
                                ),
                                onChanged: (_) {
                                  setState(_revalidateRate);
                                },
                              ),
                            ),
                            if (widget.showCharges &&
                                s.has(AeRegisterColumn.chargesA)) ...[
                              _field(
                                label: 'Charges (A)',
                                child: TextField(
                                  controller: _chargesA,
                                  focusNode: _chargesAFocus,
                                  keyboardType:
                                      const TextInputType.numberWithOptions(
                                    decimal: true,
                                  ),
                                  inputFormatters: money,
                                  decoration: _dec(
                                    hint: '0.00',
                                    prefix: '₱ ',
                                  ),
                                ),
                              ),
                              _field(
                                label: 'Charges (B)',
                                child: TextField(
                                  controller: _chargesB,
                                  focusNode: _chargesBFocus,
                                  keyboardType:
                                      const TextInputType.numberWithOptions(
                                    decimal: true,
                                  ),
                                  inputFormatters: money,
                                  decoration: _dec(
                                    hint: '0.00',
                                    prefix: '₱ ',
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                      if (_error != null) ...[
                        const SizedBox(height: 10),
                        Text(
                          _error!,
                          style: AeDashTokens.body(
                            size: 12.5,
                            color: AeDashTokens.danger,
                            weight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              _buildFooter(context),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(18, 16, 10, 16),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color(0xFFFFF7ED),
            Color(0xFFFFEDD5),
            Color(0xFFFFFBF5),
          ],
        ),
      ),
      child: Stack(
        children: [
          Positioned(
            right: 28,
            bottom: -6,
            child: Icon(
              Icons.apartment_rounded,
              size: 72,
              color: AeDashTokens.accent.withValues(alpha: 0.08),
            ),
          ),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: const Color(0xFFFFEDD5),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: AeDashTokens.accent.withValues(alpha: 0.28),
                  ),
                ),
                child: Icon(
                  _headerIcon,
                  color: AeDashTokens.accent,
                  size: 22,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _title,
                      style: AeDashTokens.heading(size: 20),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      _subtitle,
                      style: AeDashTokens.body(
                        size: 12.5,
                        color: AeDashTokens.muted,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: 'Close',
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.close_rounded),
                color: AeDashTokens.muted,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildFooter(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(18, 12, 18, 16),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: Color(0xFFEEF2F6))),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          OutlinedButton(
            onPressed: () => Navigator.pop(context),
            style: OutlinedButton.styleFrom(
              foregroundColor: AeDashTokens.accent,
              side: const BorderSide(color: AeDashTokens.accent, width: 1.4),
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(11),
              ),
            ),
            child: const Text(
              'Cancel',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
          const SizedBox(width: 10),
          FilledButton.icon(
            style: FilledButton.styleFrom(
              backgroundColor: AeDashTokens.accent,
              disabledBackgroundColor:
                  AeDashTokens.accent.withValues(alpha: 0.35),
              foregroundColor: Colors.white,
              padding:
                  const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(11),
              ),
            ),
            onPressed: _canSubmit ? _submit : null,
            icon: const Icon(Icons.check_rounded, size: 18),
            label: Text(
              _primaryLabel,
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
          ),
        ],
      ),
    );
  }

  Widget _sectionCard({
    required IconData icon,
    required String title,
    required Widget child,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(icon, size: 16, color: AeDashTokens.accent),
              const SizedBox(width: 8),
              Text(
                title,
                style: AeDashTokens.body(
                  size: 13.5,
                  weight: FontWeight.w800,
                  color: AeDashTokens.text,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }

  Widget _responsiveRow({
    required bool wide,
    required List<Widget> children,
  }) {
    if (!wide || children.length == 1) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < children.length; i++) ...[
            if (i > 0) const SizedBox(height: 10),
            children[i],
          ],
        ],
      );
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < children.length; i++) ...[
          if (i > 0) const SizedBox(width: 10),
          Expanded(child: children[i]),
        ],
      ],
    );
  }

  Widget _field({
    required String label,
    required Widget child,
    String? errorText,
    bool required = false,
  }) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 2),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            RichText(
              text: TextSpan(
                text: label,
                style: AeDashTokens.body(
                  size: 11.5,
                  weight: FontWeight.w700,
                  color: AeDashTokens.text,
                ),
                children: [
                  if (required)
                    const TextSpan(
                      text: ' *',
                      style: TextStyle(
                        color: AeDashTokens.danger,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 5),
            child,
            if (errorText != null && errorText.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(
                errorText,
                style: AeDashTokens.body(
                  size: 11,
                  color: AeDashTokens.danger,
                  weight: FontWeight.w600,
                ),
              ),
            ],
          ],
        ),
      );

  InputDecorationTheme _dropdownDecorationTheme() => InputDecorationTheme(
        isDense: true,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 10, vertical: 11),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: Color(0xFFD1D5DB)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: AeDashTokens.accent, width: 1.4),
        ),
      );

  InputDecoration _dec({
    String? hint,
    Widget? suffix,
    String? prefix,
    IconData? prefixIcon,
    bool error = false,
  }) =>
      InputDecoration(
        isDense: true,
        hintText: hint,
        prefixText: prefix,
        prefixIcon: prefixIcon == null
            ? null
            : Icon(prefixIcon, size: 18, color: AeDashTokens.accent),
        suffixIcon: suffix,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(
            color: error ? AeDashTokens.danger : const Color(0xFFD1D5DB),
          ),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(
            color: error ? AeDashTokens.danger : AeDashTokens.accent,
            width: 1.4,
          ),
        ),
      );
}

class _AddRoomDialog extends StatefulWidget {
  const _AddRoomDialog({required this.suggested});

  final String suggested;

  @override
  State<_AddRoomDialog> createState() => _AddRoomDialogState();
}

class _AddRoomDialogState extends State<_AddRoomDialog> {
  late final TextEditingController _ctrl;
  String? _error;

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(text: widget.suggested);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _save() {
    final err = AeRoomInventoryService.validateRoomId(_ctrl.text);
    if (err != null) {
      setState(() => _error = err);
      return;
    }
    Navigator.pop(context, _ctrl.text.trim());
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    return AlertDialog(
      title: const Text('Add New Room'),
      content: SizedBox(
        width: width < 480 ? width * 0.9 : 320,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Saves permanently to your establishment inventory and updates '
              'Total Available Rooms.',
              style: AeDashTokens.body(size: 12.5),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _ctrl,
              autofocus: true,
              decoration: InputDecoration(
                labelText: 'New Room Number',
                hintText: widget.suggested,
                errorText: _error,
                filled: true,
                fillColor: const Color(0xFFFFF7ED),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(
                    color: AeDashTokens.accent,
                    width: 1.4,
                  ),
                ),
              ),
              onChanged: (_) {
                if (_error != null) setState(() => _error = null);
              },
              onSubmitted: (_) => _save(),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: AeDashTokens.accent),
          onPressed: _save,
          child: const Text('Save Room'),
        ),
      ],
    );
  }
}

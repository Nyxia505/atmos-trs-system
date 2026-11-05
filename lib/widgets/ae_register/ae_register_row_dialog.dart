import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:atmos_trs_system/config/ae_register_schema.dart';
import 'package:atmos_trs_system/config/dae_residence_catalog.dart';
import 'package:atmos_trs_system/models/ae_register.dart';
import 'package:atmos_trs_system/services/ae_room_inventory_service.dart';
import 'package:atmos_trs_system/utils/ae_register_calculator.dart';
import 'package:atmos_trs_system/widgets/ae_register/ae_sheet_kit.dart';
import 'package:atmos_trs_system/widgets/establishment_dash_tokens.dart';

enum AeRowDialogMode { stay, single, edit }

/// Entry form for the Daily Register. "Stay" expands guests × nights into
/// nightly rows (first night = checked-in day), mirroring the client formula.
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
    String establishmentId = '',
    List<String> roomLabels = const [],
    ValueChanged<AeRoomInventory>? onInventoryChanged,
  }) =>
      showDialog<List<AeRegisterRow>>(
        context: context,
        builder: (_) => AeRegisterRowDialog(
          mode: mode,
          schema: schema,
          year: year,
          month: month,
          totalRooms: totalRooms,
          showCharges: showCharges,
          initial: initial,
          lastRate: lastRate,
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
  final _guests = TextEditingController();
  final _female = TextEditingController();
  final _male = TextEditingController();
  final _nights = TextEditingController(text: '1');
  final _rate = TextEditingController();
  final _chargesA = TextEditingController();
  final _chargesB = TextEditingController();
  String? _error;
  late int _capacity;
  late List<String> _labels;
  bool _addingRoom = false;

  bool get _isStay => widget.mode == AeRowDialogMode.stay && widget.schema.tracksNights;
  bool get _canAddRoom =>
      widget.schema.tracksRooms &&
      widget.establishmentId.trim().isNotEmpty &&
      widget.mode != AeRowDialogMode.edit;

  @override
  void initState() {
    super.initState();
    final i = widget.initial;
    final now = DateTime.now();
    final inMonth = now.year == widget.year && now.month == widget.month;
    _date = i?.date ?? DateTime(widget.year, widget.month, inMonth ? now.day : 1);
    _room = i?.roomNo ?? '';
    _residence = i?.residence ?? DaeResidenceCatalog.phFilipino;
    _phRegion = i?.phRegion ?? '';
    _checkedIn = i?.checkedInDay ?? (widget.mode != AeRowDialogMode.single || !widget.schema.tracksNights);
    _guests.text = '${i?.guests ?? 1}';
    _female.text = '${i?.female ?? 0}';
    _male.text = '${i?.male ?? (i == null ? 1 : 0)}';
    final rate = i?.rate ?? widget.lastRate;
    _rate.text = rate == 0 ? '' : _fmt(rate);
    _chargesA.text = (i?.chargesA ?? 0) == 0 ? '' : _fmt(i!.chargesA);
    _chargesB.text = (i?.chargesB ?? 0) == 0 ? '' : _fmt(i!.chargesB);
    _capacity = widget.totalRooms;
    _labels = AeRoomInventoryService.parseLabels(
      widget.roomLabels,
      fallbackCount: widget.totalRooms,
    );
  }

  static String _fmt(double v) => v == v.roundToDouble() ? v.toInt().toString() : v.toString();

  List<String> get _roomOptions {
    final base = _labels.isNotEmpty
        ? List<String>.from(_labels)
        : [for (var r = 1; r <= (_capacity < 0 ? 0 : _capacity); r++) '$r'];
    final cur = _room.trim();
    if (cur.isNotEmpty && !base.any((e) => e.toLowerCase() == cur.toLowerCase())) {
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
    final inventory = AeRoomInventory(roomCount: _capacity, roomLabels: _labels);
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
    for (final c in [_guests, _female, _male, _nights, _rate, _chargesA, _chargesB]) {
      c.dispose();
    }
    super.dispose();
  }

  int _int(TextEditingController c) => int.tryParse(c.text.trim()) ?? 0;
  double _dbl(TextEditingController c) => double.tryParse(c.text.trim().replaceAll(',', '')) ?? 0;

  void _complement({required bool fromFemale}) {
    final g = _int(_guests);
    if (fromFemale) {
      final f = _int(_female).clamp(0, g);
      _male.text = '${g - f}';
    } else {
      final m = _int(_male).clamp(0, g);
      _female.text = '${g - m}';
    }
  }

  Future<void> _pickDate() async {
    final first = _isStay ? DateTime(widget.year, widget.month - 1, 1) : DateTime(widget.year, widget.month, 1);
    final last = _isStay
        ? DateTime(widget.year, widget.month + 1, 0)
        : DateTime(widget.year, widget.month + 1, 0);
    final picked = await showDatePicker(
      context: context,
      initialDate: _date.isBefore(first) || _date.isAfter(last) ? first : _date,
      firstDate: first,
      lastDate: last,
    );
    if (picked != null) setState(() => _date = picked);
  }

  void _submit() {
    final s = widget.schema;
    final guests = _int(_guests);
    final female = _int(_female);
    final male = _int(_male);
    if (guests < 1) return setState(() => _error = 'Guests must be at least 1.');
    if (female + male != guests) {
      return setState(() => _error = 'Female + Male must equal $guests.');
    }
    final residence = _residence.trim().isEmpty ? DaeResidenceCatalog.unspecified : _residence.trim();
    if (s.tracksRooms) {
      if (_room.trim().isEmpty) return setState(() => _error = 'Pick a room number.');
      final editingExisting = widget.initial != null;
      // New stays must use a currently available room; edits may keep a
      // historical room number that is no longer in the active inventory.
      if (!editingExisting && !_roomOptionValid(_room)) {
        return setState(
          () => _error =
              'Room ${_room.trim()} is not in the current $_capacity available rooms. '
              'Use + Add New Room first.',
        );
      }
    }
    final phRegion = DaeResidenceCatalog.bucketFor(residence) == DaeResidenceBucket.philippineResident
        ? _phRegion
        : '';
    final rate = _dbl(_rate);
    final a = widget.showCharges ? _dbl(_chargesA) : (widget.initial?.chargesA ?? 0);
    final b = widget.showCharges ? _dbl(_chargesB) : (widget.initial?.chargesB ?? 0);

    if (_isStay) {
      final nights = _int(_nights);
      if (nights < 1 || nights > 60) return setState(() => _error = 'Nights must be 1–60.');
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

  @override
  Widget build(BuildContext context) {
    final s = widget.schema;
    final title = switch (widget.mode) {
      AeRowDialogMode.stay => s.tracksNights ? 'Add stay' : 'Add record',
      AeRowDialogMode.single => 'Add single night',
      AeRowDialogMode.edit => 'Edit record',
    };
    final isPh = DaeResidenceCatalog.bucketFor(_residence) == DaeResidenceBucket.philippineResident;
    final roomOpts = _roomOptions;
    final digits = [FilteringTextInputFormatter.digitsOnly];
    final money = [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))];

    return AlertDialog(
      title: Text(title, style: AeDashTokens.heading(size: 18)),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (_isStay)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Text(
                    'One row is created per night (guests × nights = guest-nights). '
                    'Only the first night counts as the checked-in day.',
                    style: AeDashTokens.body(size: 12),
                  ),
                ),
              Row(children: [
                Expanded(
                  child: _field(
                    label: _isStay ? 'Check-in date' : 'Date',
                    child: InkWell(
                      onTap: _pickDate,
                      child: InputDecorator(
                        decoration: _dec(suffix: const Icon(Icons.calendar_month_rounded, size: 18)),
                        child: Text(AeSheetKit.shortDate(_date)),
                      ),
                    ),
                  ),
                ),
                if (_isStay) ...[
                  const SizedBox(width: 10),
                  SizedBox(
                    width: 110,
                    child: _field(
                      label: 'Nights',
                      child: TextField(controller: _nights, keyboardType: TextInputType.number, inputFormatters: digits, decoration: _dec()),
                    ),
                  ),
                ],
                if (s.tracksRooms) ...[
                  const SizedBox(width: 10),
                  SizedBox(
                    width: 128,
                    child: _field(
                      label: 'Room No.',
                      child: roomOpts.isNotEmpty
                          ? DropdownButtonFormField<String>(
                              key: ValueKey('room-dd-$_capacity-${roomOpts.length}-$_room'),
                              initialValue: _roomOptionValid(_room) ? _room : null,
                              isExpanded: true,
                              menuMaxHeight: 280,
                              decoration: _dec(),
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
                              onChanged: (v) => setState(() => _room = v ?? ''),
                            )
                          : TextFormField(
                              initialValue: _room,
                              decoration: _dec(),
                              onChanged: (v) => _room = v,
                            ),
                    ),
                  ),
                ],
              ]),
              if (_canAddRoom)
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    onPressed: _addingRoom ? null : _addNewRoom,
                    icon: _addingRoom
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.add_rounded, size: 18),
                    label: Text(_addingRoom ? 'Saving room…' : '+ Add New Room'),
                    style: TextButton.styleFrom(
                      foregroundColor: AeDashTokens.accent,
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                    ),
                  ),
                ),
              _field(
                label: 'Residence / Nationality',
                child: Autocomplete<String>(
                  initialValue: TextEditingValue(text: _residence),
                  optionsBuilder: (v) {
                    final q = v.text.trim().toLowerCase();
                    final all = DaeResidenceCatalog.pickerOptions;
                    if (q.isEmpty) return all;
                    return all.where((o) => o.toLowerCase().contains(q));
                  },
                  onSelected: (v) => setState(() => _residence = v),
                  fieldViewBuilder: (ctx, ctrl, focus, onSubmit) => TextField(
                    controller: ctrl,
                    focusNode: focus,
                    decoration: _dec(hint: 'Type a country…', suffix: const Icon(Icons.public_rounded, size: 18)),
                    onChanged: (v) => setState(() => _residence = v),
                  ),
                ),
              ),
              if (isPh && s.has(AeRegisterColumn.phRegion))
                _field(
                  label: 'PH origin region (optional — for DAE 1B.2 / 3B.2 Domestic)',
                  child: DropdownButtonFormField<String>(
                    initialValue: _phRegion.isEmpty ? null : _phRegion,
                    isExpanded: true,
                    decoration: _dec(hint: 'Not specified'),
                    items: [
                      const DropdownMenuItem(value: '', child: Text('Not specified')),
                      for (final r in DaeResidenceCatalog.philippineRegions) DropdownMenuItem(value: r, child: Text(r)),
                    ],
                    onChanged: (v) => setState(() => _phRegion = v ?? ''),
                  ),
                ),
              Row(children: [
                Expanded(
                  child: _field(
                    label: s.guestsLabel,
                    child: TextField(
                      controller: _guests,
                      keyboardType: TextInputType.number,
                      inputFormatters: digits,
                      decoration: _dec(),
                      onChanged: (_) => _complement(fromFemale: true),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _field(
                    label: 'Female',
                    child: TextField(
                      controller: _female,
                      keyboardType: TextInputType.number,
                      inputFormatters: digits,
                      decoration: _dec(),
                      onChanged: (_) => _complement(fromFemale: true),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _field(
                    label: 'Male',
                    child: TextField(
                      controller: _male,
                      keyboardType: TextInputType.number,
                      inputFormatters: digits,
                      decoration: _dec(),
                      onChanged: (_) => _complement(fromFemale: false),
                    ),
                  ),
                ),
              ]),
              if (s.tracksNights && !_isStay)
                CheckboxListTile(
                  value: _checkedIn,
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  controlAffinity: ListTileControlAffinity.leading,
                  title: const Text("Checked-in day (guests arrived on this date)"),
                  onChanged: (v) => setState(() => _checkedIn = v ?? false),
                ),
              Row(children: [
                Expanded(
                  child: _field(
                    label: s.rateLabel,
                    child: TextField(controller: _rate, keyboardType: TextInputType.number, inputFormatters: money, decoration: _dec(prefix: '₱ ')),
                  ),
                ),
                if (widget.showCharges && s.has(AeRegisterColumn.chargesA)) ...[
                  const SizedBox(width: 10),
                  Expanded(
                    child: _field(
                      label: 'Charges (A)',
                      child: TextField(controller: _chargesA, keyboardType: TextInputType.number, inputFormatters: money, decoration: _dec(prefix: '₱ ')),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _field(
                      label: 'Charges (B)',
                      child: TextField(controller: _chargesB, keyboardType: TextInputType.number, inputFormatters: money, decoration: _dec(prefix: '₱ ')),
                    ),
                  ),
                ],
              ]),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(_error!, style: AeDashTokens.body(size: 12.5, color: AeDashTokens.danger, weight: FontWeight.w700)),
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton.icon(
          style: FilledButton.styleFrom(backgroundColor: AeDashTokens.accent),
          onPressed: _submit,
          icon: const Icon(Icons.check_rounded, size: 18),
          label: Text(widget.mode == AeRowDialogMode.edit ? 'Save' : 'Add'),
        ),
      ],
    );
  }

  Widget _field({required String label, required Widget child}) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: AeDashTokens.body(size: 11.5, weight: FontWeight.w700, color: AeDashTokens.text)),
            const SizedBox(height: 4),
            child,
          ],
        ),
      );

  InputDecoration _dec({String? hint, Widget? suffix, String? prefix}) => InputDecoration(
        isDense: true,
        hintText: hint,
        prefixText: prefix,
        suffixIcon: suffix,
        contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
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
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: AeDashTokens.accent, width: 1.4),
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

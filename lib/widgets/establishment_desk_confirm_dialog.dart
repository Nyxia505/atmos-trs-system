import 'package:flutter/material.dart';

import 'package:atmos_trs_system/config/app_theme.dart';
import 'package:atmos_trs_system/features/governor/theme/governor_dashboard_tokens.dart';
import 'package:atmos_trs_system/services/establishment_stay_service.dart';
import 'package:atmos_trs_system/utils/establishment_capability.dart';
import 'package:atmos_trs_system/utils/establishment_lodging_hours.dart';
import 'package:atmos_trs_system/utils/establishment_room_grid.dart';
import 'package:atmos_trs_system/utils/party_count_complements.dart';
import 'package:atmos_trs_system/widgets/establishment_rooms_panel.dart';
import 'package:atmos_trs_system/widgets/party_demographic_fields.dart';

class DeskConfirmStayResult {
  const DeskConfirmStayResult({
    required this.demographics,
    required this.nightsStayed,
    required this.roomsOccupied,
    required this.notes,
    required this.roomNumbers,
    this.checkOutAt,
  });

  final PartyDemographicValue demographics;
  final int nightsStayed;
  final int roomsOccupied;
  final String notes;
  final List<String> roomNumbers;
  final DateTime? checkOutAt;
}

/// Multi-step desk confirm: guests → preferences → pick matching rooms.
class EstablishmentDeskConfirmDialog extends StatefulWidget {
  const EstablishmentDeskConfirmDialog({
    super.key,
    required this.stay,
    required this.lodging,
    required this.copy,
    required this.establishmentCategory,
    required this.allSlots,
    this.checkInTime = '',
    this.checkOutTime = '',
  });

  final EstablishmentStayRequest stay;
  final bool lodging;
  final EstablishmentPackCopy copy;
  final String establishmentCategory;
  final List<EstablishmentRoomSlot> allSlots;
  /// AE standard check-in clock (`HH:mm`).
  final String checkInTime;
  /// AE standard check-out clock (`HH:mm`).
  final String checkOutTime;

  @override
  State<EstablishmentDeskConfirmDialog> createState() =>
      _EstablishmentDeskConfirmDialogState();
}

class _EstablishmentDeskConfirmDialogState
    extends State<EstablishmentDeskConfirmDialog> {
  final _demoKey = GlobalKey<PartyDemographicFieldsState>();
  late final TextEditingController _nightsCtrl;
  late final TextEditingController _roomsCtrl;
  late final TextEditingController _notesCtrl;
  late final TextEditingController _maxPriceCtrl;
  late final TextEditingController _customPrefInclCtrl;

  int _step = 0; // 0 guests, 1 prefs, 2 rooms
  String? _error;
  String _prefType = '';
  int _prefCapMin = 0;
  int _prefCapMax = 0;
  final Set<String> _prefInclusions = {};
  final Set<String> _selectedSlots = {};
  /// Snapshot of demographics when leaving Guests — widget unmounts after step 0.
  PartyDemographicValue? _savedDemo;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    final nights = widget.lodging
        ? EstablishmentLodgingHours.defaultNightsForArrival(
            now: now,
            checkInTime: widget.checkInTime,
          )
        : 0;
    _nightsCtrl = TextEditingController(text: '$nights');
    _roomsCtrl = TextEditingController(text: widget.lodging ? '1' : '0');
    _notesCtrl = TextEditingController();
    _maxPriceCtrl = TextEditingController();
    _customPrefInclCtrl = TextEditingController();
  }

  bool get _earlyArrival =>
      widget.lodging &&
      EstablishmentLodgingHours.isEarlyArrival(
        now: DateTime.now(),
        checkInTime: widget.checkInTime,
      );

  String? get _earlyArrivalHint {
    if (!_earlyArrival) {
      final cin = EstablishmentLodgingHours.tryParse(widget.checkInTime);
      final cout = EstablishmentLodgingHours.tryParse(widget.checkOutTime);
      if (cin == null && cout == null) return null;
      final parts = <String>[];
      if (cin != null) {
        parts.add('Check-in ${EstablishmentLodgingHours.displayLabel(cin)}');
      }
      if (cout != null) {
        parts.add('check-out ${EstablishmentLodgingHours.displayLabel(cout)}');
      }
      return parts.join(' · ');
    }
    final cin = EstablishmentLodgingHours.tryParse(widget.checkInTime);
    final label = cin == null
        ? 'check-in'
        : EstablishmentLodgingHours.displayLabel(cin);
    return 'Before check-in ($label) — early arrival counts as an extra night '
        '(default nights set to 2; you can edit).';
  }

  @override
  void dispose() {
    _nightsCtrl.dispose();
    _roomsCtrl.dispose();
    _notesCtrl.dispose();
    _maxPriceCtrl.dispose();
    _customPrefInclCtrl.dispose();
    super.dispose();
  }

  void _addCustomPrefInclusion() {
    final raw = _customPrefInclCtrl.text.trim();
    if (raw.isEmpty) return;
    final exists = _prefInclusions.any(
      (e) => e.toLowerCase() == raw.toLowerCase(),
    );
    if (!exists) {
      setState(() => _prefInclusions.add(raw));
    }
    _customPrefInclCtrl.clear();
  }

  /// Preset chips + custom inclusions already used on this property's rooms.
  List<String> get _inclusionChoices {
    final seen = <String>{};
    final out = <String>[];
    void add(String s) {
      final t = s.trim();
      if (t.isEmpty) return;
      final key = t.toLowerCase();
      if (seen.contains(key)) return;
      seen.add(key);
      out.add(t);
    }

    for (final c in EstablishmentRoomCatalog.inclusions) {
      add(c);
    }
    for (final slot in widget.allSlots) {
      for (final i in slot.info.inclusions) {
        add(i);
      }
    }
    for (final i in _prefInclusions) {
      add(i);
    }
    return out;
  }

  int get _partySeed {
    final p = widget.stay.partySize;
    return p < 1 ? 1 : p;
  }

  ({int male, int female}) get _sexSeed {
    final party = _partySeed;
    final m = widget.stay.maleCount;
    final f = widget.stay.femaleCount;
    if (PartyCountComplements.sumsToTotal(party, m, f)) {
      return (male: m, female: f);
    }
    if (m + f > 0) {
      final male = PartyCountComplements.clampKnown(party, m);
      return (
        male: male,
        female: PartyCountComplements.complement(party, male),
      );
    }
    final one = PartyCountComplements.sexPairFromLabel(widget.stay.touristSex);
    if (party == 1) return one;
    if (one.male == 1) {
      return (male: 1, female: PartyCountComplements.complement(party, 1));
    }
    if (one.female == 1) {
      return (female: 1, male: PartyCountComplements.complement(party, 1));
    }
    return (male: 0, female: 0);
  }

  ({int filipino, int foreign}) get _residencySeed {
    final party = _partySeed;
    final fi = widget.stay.filipinoCount;
    final fo = widget.stay.foreignCount;
    if (PartyCountComplements.sumsToTotal(party, fi, fo)) {
      return (filipino: fi, foreign: fo);
    }
    if (fi + fo > 0) {
      final fil = PartyCountComplements.clampKnown(party, fi);
      return (
        filipino: fil,
        foreign: PartyCountComplements.complement(party, fil),
      );
    }
    final one = PartyCountComplements.residencyPair(
      isLocal: widget.stay.touristIsLocal,
      localOrForeign: widget.stay.touristLocalOrForeign,
      country: widget.stay.touristCountry,
      nationality: widget.stay.touristNationality,
    );
    if (party == 1) return one;
    if (one.filipino == 1) return (filipino: party, foreign: 0);
    if (one.foreign == 1) return (filipino: 0, foreign: party);
    return (filipino: 0, foreign: 0);
  }

  EstablishmentRoomPreferences get _prefs => EstablishmentRoomPreferences(
        type: _prefType,
        capacityMin: _prefCapMin,
        capacityMax: _prefCapMax,
        maxPricePerNight: double.tryParse(_maxPriceCtrl.text.trim()) ?? 0,
        requiredInclusions: _prefInclusions.toList(),
      );

  List<EstablishmentRoomSlot> get _matchedFree {
    return EstablishmentRoomGrid.filterByPreferences(widget.allSlots, _prefs);
  }

  PartyDemographicValue? get _activeDemo =>
      _demoKey.currentState?.value ?? _savedDemo;

  bool _validateGuests() {
    final demo = _activeDemo;
    if (demo == null || !demo.isValid) {
      setState(() {
        _error = demo?.validationMessage ??
            'Enter party size with Male/Female and Filipino/Foreign counts.';
      });
      return false;
    }
    // Keep a copy while Guests fields are still mounted.
    if (_demoKey.currentState != null) {
      _savedDemo = demo;
    }
    if (widget.lodging) {
      final nights = int.tryParse(_nightsCtrl.text.trim()) ?? 0;
      final rooms = int.tryParse(_roomsCtrl.text.trim()) ?? 0;
      if (nights < 1) {
        setState(() => _error = 'Nights stayed must be at least 1.');
        return false;
      }
      if (rooms < 1) {
        setState(() => _error = 'Rooms occupied must be at least 1.');
        return false;
      }
    }
    setState(() => _error = null);
    return true;
  }

  void _next() {
    if (_step == 0) {
      if (!_validateGuests()) return;
      if (!widget.lodging) {
        _submit();
        return;
      }
      setState(() {
        _step = 1;
        _error = null;
      });
      return;
    }
    if (_step == 1) {
      setState(() {
        _step = 2;
        _error = null;
        // Drop selections that no longer match.
        final matchedIds = {for (final s in _matchedFree) s.id};
        _selectedSlots.removeWhere((id) => !matchedIds.contains(id));
      });
      return;
    }
    _submit();
  }

  void _back() {
    if (_step <= 0) {
      Navigator.pop(context);
      return;
    }
    setState(() {
      _step -= 1;
      _error = null;
    });
  }

  void _toggleSlot(String id) {
    final rooms = int.tryParse(_roomsCtrl.text.trim()) ?? 0;
    setState(() {
      if (_selectedSlots.contains(id)) {
        _selectedSlots.remove(id);
        _error = null;
      } else {
        if (rooms < 1) {
          _error = 'Set rooms occupied on step 1.';
          return;
        }
        if (_selectedSlots.length >= rooms) {
          _error = 'Select exactly $rooms room(s).';
          return;
        }
        _selectedSlots.add(id);
        _error = null;
      }
    });
  }

  void _submit() {
    if (!_validateGuests()) return;
    final demo = _activeDemo!;
    final nights = int.tryParse(_nightsCtrl.text.trim()) ?? 0;
    final rooms = int.tryParse(_roomsCtrl.text.trim()) ?? 0;

    if (widget.lodging) {
      if (_matchedFree.isEmpty && _prefs.isEmpty == false) {
        // allow picking after clearing prefs — still need slots
      }
      final freeAll = EstablishmentRoomGrid.freeSlots(widget.allSlots);
      if (freeAll.isEmpty) {
        setState(() => _error = 'No free rooms available to assign.');
        return;
      }
      if (_selectedSlots.length != rooms) {
        setState(() {
          _step = 2;
          _error =
              'Select exactly $rooms matching room(s). (Selected ${_selectedSlots.length}.)';
        });
        return;
      }
    }

    final roomNumbers = _selectedSlots.toList()
      ..sort((a, b) => (int.tryParse(a) ?? 0).compareTo(int.tryParse(b) ?? 0));

    final checkInAt = DateTime.now();
    final plannedOut = widget.lodging && nights > 0
        ? EstablishmentLodgingHours.plannedCheckOutAt(
            checkInAt: checkInAt,
            nights: nights,
            checkOutTime: widget.checkOutTime,
          )
        : null;

    Navigator.pop(
      context,
      DeskConfirmStayResult(
        demographics: demo,
        nightsStayed: widget.lodging ? nights : 0,
        roomsOccupied: widget.lodging ? rooms : 0,
        notes: _notesCtrl.text,
        roomNumbers: roomNumbers,
        checkOutAt: plannedOut,
      ),
    );
  }

  List<String> get _stepTitles => widget.lodging
      ? const ['Guests', 'Preferences', 'Pick rooms']
      : const ['Guests'];

  bool get _isFinalStep => !widget.lodging || _step == 2;

  void _clearPreferences() {
    setState(() {
      _prefType = '';
      _prefCapMin = 0;
      _prefCapMax = 0;
      _maxPriceCtrl.clear();
      _prefInclusions.clear();
      _error = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final stay = widget.stay;
    final sex = _sexSeed;
    final res = _residencySeed;
    final maxHeight = MediaQuery.sizeOf(context).height * 0.9;

    return Dialog(
      backgroundColor: _T.background,
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      clipBehavior: Clip.antiAlias,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: 540, maxHeight: maxHeight),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildHeader(),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _buildGuestCard(stay),
                    const SizedBox(height: 14),
                    AnimatedSwitcher(
                      duration: const Duration(milliseconds: 220),
                      transitionBuilder: (child, anim) => FadeTransition(
                        opacity: anim,
                        child: SlideTransition(
                          position: Tween<Offset>(
                            begin: const Offset(0.04, 0),
                            end: Offset.zero,
                          ).animate(anim),
                          child: child,
                        ),
                      ),
                      child: KeyedSubtree(
                        key: ValueKey(_step),
                        child: switch (_step) {
                          1 => _buildPrefsStep(),
                          2 => _buildRoomsStep(),
                          _ => _buildGuestsStep(sex, res),
                        },
                      ),
                    ),
                    if (_error != null) ...[
                      const SizedBox(height: 12),
                      _banner(
                        icon: Icons.error_outline_rounded,
                        text: _error!,
                        fg: const Color(0xFFB91C1C),
                        bg: const Color(0xFFFEF2F2),
                        border: const Color(0xFFFECACA),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            _buildFooter(),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    final titles = _stepTitles;
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 16, 8, 16),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFFFF7ED), Colors.white],
        ),
        border: Border(bottom: BorderSide(color: _T.border)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [_T.primarySecondary, _T.primaryDark],
                  ),
                  borderRadius: BorderRadius.circular(14),
                  boxShadow: [
                    BoxShadow(
                      color: _T.primary.withValues(alpha: 0.3),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: const Icon(
                  Icons.how_to_reg_rounded,
                  color: Colors.white,
                  size: 24,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.copy.confirmTitle,
                      style: _T.heading(size: 19),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      titles.length > 1
                          ? 'Step ${_step + 1} of ${titles.length} · '
                              '${titles[_step]}'
                          : 'Enter guest details, then confirm',
                      style: _T.body(size: 12.5, color: _T.subtitle),
                    ),
                  ],
                ),
              ),
              IconButton(
                onPressed: () => Navigator.pop(context),
                tooltip: 'Close',
                icon: const Icon(Icons.close_rounded, color: _T.subtitle),
              ),
            ],
          ),
          if (titles.length > 1) ...[
            const SizedBox(height: 14),
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: Row(
                children: [
                  for (var i = 0; i < titles.length; i++) ...[
                    if (i > 0)
                      Expanded(
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 250),
                          height: 2,
                          margin: const EdgeInsets.symmetric(horizontal: 8),
                          decoration: BoxDecoration(
                            color: i <= _step ? _T.primary : _T.border,
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                      ),
                    _StepIndicator(
                      index: i,
                      label: titles[i],
                      state: i < _step
                          ? _StepVisual.done
                          : i == _step
                              ? _StepVisual.active
                              : _StepVisual.upcoming,
                      onTap: i < _step
                          ? () => setState(() {
                                _step = i;
                                _error = null;
                              })
                          : null,
                    ),
                  ],
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildGuestCard(EstablishmentStayRequest stay) {
    final name = stay.touristName.isNotEmpty ? stay.touristName : 'Tourist';
    final parts = name.trim().split(RegExp(r'\s+'));
    final initials = parts
        .take(2)
        .map((p) => p.isEmpty ? '' : p[0].toUpperCase())
        .join();
    final party = stay.partySize < 1 ? 1 : stay.partySize;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _T.border),
      ),
      child: Row(
        children: [
          Container(
            width: 46,
            height: 46,
            alignment: Alignment.center,
            decoration: const BoxDecoration(
              color: _T.softOrange,
              shape: BoxShape.circle,
            ),
            child: Text(
              initials.isEmpty ? 'T' : initials,
              style: _T.sectionTitle(size: 16, color: _T.primaryDark),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: _T.sectionTitle(size: 15),
                ),
                if (stay.touristEmail.isNotEmpty)
                  Text(
                    stay.touristEmail,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: _T.body(size: 12.5, color: _T.subtitle),
                  ),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    _miniChip(
                      Icons.groups_rounded,
                      '$party ${party == 1 ? 'guest' : 'guests'}',
                    ),
                    if (stay.touristNationality.isNotEmpty)
                      _miniChip(Icons.flag_rounded, stay.touristNationality),
                    _miniChip(
                      Icons.hourglass_top_rounded,
                      'Pending',
                      fg: const Color(0xFF92400E),
                      bg: const Color(0xFFFEF3C7),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFooter() {
    final isFirst = _step == 0;
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: _T.border)),
      ),
      child: Row(
        children: [
          OutlinedButton.icon(
            onPressed: _back,
            icon: Icon(
              isFirst ? Icons.close_rounded : Icons.arrow_back_rounded,
              size: 18,
            ),
            label: Text(isFirst ? 'Cancel' : 'Back'),
            style: OutlinedButton.styleFrom(
              foregroundColor: _T.text,
              side: const BorderSide(color: _T.border),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
          const Spacer(),
          FilledButton.icon(
            onPressed: _next,
            icon: Icon(
              _isFinalStep ? Icons.check_circle_rounded : Icons.arrow_forward_rounded,
              size: 18,
            ),
            label: Text(_isFinalStep ? 'Confirm stay' : 'Next'),
            style: FilledButton.styleFrom(
              backgroundColor: AppTheme.brandOrange,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              textStyle: const TextStyle(fontWeight: FontWeight.w800),
            ),
          ),
        ],
      ),
    );
  }

  Widget _section({
    required IconData icon,
    required String title,
    String? subtitle,
    Widget? trailing,
    required Widget child,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _T.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(7),
                decoration: BoxDecoration(
                  color: _T.softOrange,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, size: 17, color: _T.primaryDark),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: _T.sectionTitle(size: 14)),
                    if (subtitle != null)
                      Text(
                        subtitle,
                        style: _T.body(size: 12, color: _T.subtitle),
                      ),
                  ],
                ),
              ),
              if (trailing != null) trailing,
            ],
          ),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }

  Widget _banner({
    required IconData icon,
    required String text,
    required Color fg,
    required Color bg,
    required Color border,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: border),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: fg),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: _T.body(size: 12.5, color: fg).copyWith(height: 1.4),
            ),
          ),
        ],
      ),
    );
  }

  Widget _miniChip(
    IconData icon,
    String label, {
    Color fg = _T.subtitle,
    Color bg = _T.mutedSurface,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: fg),
          const SizedBox(width: 4),
          Text(
            label,
            style: _T.body(size: 11.5, color: fg).copyWith(
                  fontWeight: FontWeight.w700,
                ),
          ),
        ],
      ),
    );
  }

  InputDecoration _input(
    String label, {
    String? hint,
    IconData? icon,
    String? prefixText,
  }) {
    OutlineInputBorder border(Color c, [double w = 1]) => OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: c, width: w),
        );
    return InputDecoration(
      labelText: label,
      hintText: hint,
      prefixIcon: icon == null ? null : Icon(icon, size: 20),
      prefixText: prefixText,
      isDense: true,
      filled: true,
      fillColor: Colors.white,
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
      border: border(_T.border),
      enabledBorder: border(_T.border),
      focusedBorder: border(_T.primary, 1.6),
    );
  }

  Widget _choiceChip({
    required String label,
    required bool selected,
    required ValueChanged<bool> onSelected,
  }) {
    return FilterChip(
      label: Text(label),
      selected: selected,
      onSelected: onSelected,
      showCheckmark: true,
      checkmarkColor: _T.primaryDark,
      backgroundColor: Colors.white,
      selectedColor: _T.softOrange,
      side: BorderSide(
        color: selected ? _T.primary : _T.border,
        width: selected ? 1.4 : 1,
      ),
      shape: const StadiumBorder(),
      labelStyle: _T.body(
        size: 13,
        color: selected ? _T.primaryDark : _T.text,
      ).copyWith(fontWeight: selected ? FontWeight.w700 : FontWeight.w500),
    );
  }

  Widget _buildGuestsStep(
    ({int male, int female}) sex,
    ({int filipino, int foreign}) res,
  ) {
    final hint = _earlyArrivalHint;
    final freeNow = EstablishmentRoomGrid.freeSlots(widget.allSlots).length;
    final noneFree = freeNow == 0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _section(
          icon: Icons.groups_rounded,
          title: 'Who is checking in?',
          subtitle: 'Ask how many guests — gender and nationality go to DOT forms.',
          child: PartyDemographicFields(
            key: _demoKey,
            initialPartySize: _savedDemo?.partySize ?? _partySeed,
            initialMale: _savedDemo?.maleCount ?? sex.male,
            initialFemale: _savedDemo?.femaleCount ?? sex.female,
            initialFilipino: _savedDemo?.filipinoCount ?? res.filipino,
            initialForeign: _savedDemo?.foreignCount ?? res.foreign,
          ),
        ),
        if (widget.lodging)
          _section(
            icon: Icons.nights_stay_rounded,
            title: 'Stay details',
            trailing: _miniChip(
              Icons.meeting_room_rounded,
              '$freeNow free now',
              fg: noneFree ? const Color(0xFFB91C1C) : const Color(0xFF15803D),
              bg: noneFree ? const Color(0xFFFEE2E2) : const Color(0xFFDCFCE7),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _nightsCtrl,
                        keyboardType: TextInputType.number,
                        decoration: _input(
                          'Nights',
                          icon: Icons.bedtime_outlined,
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: TextField(
                        controller: _roomsCtrl,
                        keyboardType: TextInputType.number,
                        decoration: _input(
                          'Rooms needed',
                          icon: Icons.king_bed_outlined,
                        ),
                      ),
                    ),
                  ],
                ),
                if (hint != null) ...[
                  const SizedBox(height: 10),
                  _earlyArrival
                      ? _banner(
                          icon: Icons.wb_twilight_rounded,
                          text: hint,
                          fg: const Color(0xFF9A3412),
                          bg: const Color(0xFFFFF7ED),
                          border: const Color(0xFFFED7AA),
                        )
                      : _banner(
                          icon: Icons.schedule_rounded,
                          text: hint,
                          fg: _T.subtitle,
                          bg: _T.mutedSurface,
                          border: _T.border,
                        ),
                ],
                if (noneFree) ...[
                  const SizedBox(height: 8),
                  _banner(
                    icon: Icons.no_meeting_room_rounded,
                    text: 'No free rooms right now. Check out a guest or '
                        'add rooms in the Rooms tab before confirming.',
                    fg: const Color(0xFFB91C1C),
                    bg: const Color(0xFFFEF2F2),
                    border: const Color(0xFFFECACA),
                  ),
                ],
              ],
            ),
          )
        else
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: _banner(
              icon: Icons.info_outline_rounded,
              text: widget.copy.confirmNonLodgingNote.isNotEmpty
                  ? widget.copy.confirmNonLodgingNote
                  : 'Visit confirm — no room assignment.',
              fg: _T.subtitle,
              bg: _T.mutedSurface,
              border: _T.border,
            ),
          ),
        _section(
          icon: Icons.sticky_note_2_outlined,
          title: 'Notes',
          subtitle: 'Optional — anything the front desk should remember.',
          child: TextField(
            controller: _notesCtrl,
            maxLines: 2,
            decoration: _input(
              'Notes (optional)',
              hint: 'e.g. late check-in, extra bed, special request',
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildPrefsStep() {
    final matchCount = _matchedFree.length;
    final hasMatches = matchCount > 0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Text(
            'Ask the guest what they prefer. All filters are optional — '
            'matching free rooms show on the next step.',
            style: _T.body(size: 12.5, color: _T.subtitle),
          ),
        ),
        _section(
          icon: Icons.bed_rounded,
          title: 'Room type & budget',
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: DropdownButtonFormField<String>(
                  // ignore: deprecated_member_use
                  value: _prefType.isEmpty ? null : _prefType,
                  isExpanded: true,
                  borderRadius: BorderRadius.circular(12),
                  decoration: _input('Room type'),
                  items: [
                    const DropdownMenuItem(value: '', child: Text('Any type')),
                    for (final t in EstablishmentRoomCatalog.roomTypes)
                      DropdownMenuItem(value: t, child: Text(t)),
                  ],
                  onChanged: (v) => setState(() => _prefType = v ?? ''),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: TextField(
                  controller: _maxPriceCtrl,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  onChanged: (_) => setState(() {}),
                  decoration: _input(
                    'Max / night',
                    hint: 'Any',
                    prefixText: '₱ ',
                  ),
                ),
              ),
            ],
          ),
        ),
        _section(
          icon: Icons.people_alt_rounded,
          title: 'Good for',
          subtitle: 'How many people the room should fit.',
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _choiceChip(
                label: 'Any',
                selected: _prefCapMin <= 0 && _prefCapMax <= 0,
                onSelected: (_) => setState(() {
                  _prefCapMin = 0;
                  _prefCapMax = 0;
                }),
              ),
              for (final p in EstablishmentRoomCatalog.capacityPresets)
                _choiceChip(
                  label: p.$3,
                  selected: _prefCapMin == p.$1 && _prefCapMax == p.$2,
                  onSelected: (_) => setState(() {
                    _prefCapMin = p.$1;
                    _prefCapMax = p.$2;
                  }),
                ),
            ],
          ),
        ),
        _section(
          icon: Icons.checklist_rounded,
          title: 'Must include',
          subtitle: _prefInclusions.isEmpty
              ? 'Tap amenities the room must have.'
              : '${_prefInclusions.length} selected',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final inc in _inclusionChoices)
                    _choiceChip(
                      label: inc,
                      selected: _prefInclusions.any(
                        (e) => e.toLowerCase() == inc.toLowerCase(),
                      ),
                      onSelected: (on) => setState(() {
                        _prefInclusions.removeWhere(
                          (e) => e.toLowerCase() == inc.toLowerCase(),
                        );
                        if (on) _prefInclusions.add(inc);
                      }),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _customPrefInclCtrl,
                      textInputAction: TextInputAction.done,
                      onSubmitted: (_) => _addCustomPrefInclusion(),
                      decoration: _input(
                        'Other amenity',
                        hint: 'Not in the list? Type it here',
                        icon: Icons.add_circle_outline_rounded,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  FilledButton.tonal(
                    onPressed: _addCustomPrefInclusion,
                    style: FilledButton.styleFrom(
                      backgroundColor: _T.softOrange,
                      foregroundColor: _T.primaryDark,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 18,
                        vertical: 16,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: const Text(
                      'Add',
                      style: TextStyle(fontWeight: FontWeight.w800),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        _banner(
          icon: hasMatches
              ? Icons.check_circle_outline_rounded
              : Icons.search_off_rounded,
          text: hasMatches
              ? '$matchCount free ${matchCount == 1 ? 'room matches' : 'rooms match'} '
                  'these preferences.'
              : 'No free rooms match yet. Remove some filters to see more rooms.',
          fg: hasMatches ? const Color(0xFF15803D) : const Color(0xFF9A3412),
          bg: hasMatches ? const Color(0xFFF0FDF4) : const Color(0xFFFFF7ED),
          border:
              hasMatches ? const Color(0xFFBBF7D0) : const Color(0xFFFED7AA),
        ),
        if (!_prefs.isEmpty) ...[
          const SizedBox(height: 4),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              onPressed: _clearPreferences,
              icon: const Icon(Icons.filter_alt_off_rounded, size: 18),
              label: const Text('Clear all filters'),
              style: TextButton.styleFrom(foregroundColor: _T.primaryDark),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildRoomsStep() {
    final matched = _matchedFree;
    final roomsNeeded = int.tryParse(_roomsCtrl.text.trim()) ?? 0;

    final selected = _selectedSlots.length;
    final complete = roomsNeeded > 0 && selected == roomsNeeded;
    final progress =
        roomsNeeded <= 0 ? 0.0 : (selected / roomsNeeded).clamp(0.0, 1.0);

    return _section(
      icon: Icons.meeting_room_rounded,
      title: 'Assign ${roomsNeeded == 1 ? 'a room' : '$roomsNeeded rooms'}',
      subtitle: 'Tap a room to select it. Tap Info to see its details.',
      trailing: _miniChip(
        complete ? Icons.check_circle_rounded : Icons.touch_app_rounded,
        '$selected / $roomsNeeded',
        fg: complete ? const Color(0xFF15803D) : _T.primaryDark,
        bg: complete ? const Color(0xFFDCFCE7) : _T.softOrange,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: TweenAnimationBuilder<double>(
              tween: Tween(end: progress),
              duration: const Duration(milliseconds: 250),
              builder: (context, v, _) => LinearProgressIndicator(
                value: v,
                minHeight: 6,
                backgroundColor: _T.mutedSurface,
                valueColor: AlwaysStoppedAnimation(
                  complete ? _T.success : _T.primary,
                ),
              ),
            ),
          ),
          const SizedBox(height: 14),
          if (matched.isEmpty)
            _buildNoRoomsState()
          else
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                for (final slot in matched)
                  _MiniRoomCube(
                    slot: slot,
                    selected: _selectedSlots.contains(slot.id),
                    onSelect: () => _toggleSlot(slot.id),
                    onInfo: () => showRoomInfoEditor(
                      context: context,
                      slot: slot,
                      editable: false,
                    ),
                  ),
              ],
            ),
        ],
      ),
    );
  }

  Widget _buildNoRoomsState() {
    final noneFree = EstablishmentRoomGrid.freeSlots(widget.allSlots).isEmpty;
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 16),
      decoration: BoxDecoration(
        color: _T.background,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _T.border),
      ),
      child: Column(
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: noneFree ? const Color(0xFFFEE2E2) : _T.softOrange,
              shape: BoxShape.circle,
            ),
            child: Icon(
              noneFree ? Icons.no_meeting_room_rounded : Icons.search_off_rounded,
              size: 28,
              color: noneFree ? const Color(0xFFB91C1C) : _T.primaryDark,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            noneFree ? 'All rooms are occupied' : 'No free rooms match',
            style: _T.sectionTitle(size: 15),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 4),
          Text(
            noneFree
                ? 'Check out a guest or add rooms in the Rooms tab '
                    '(Edit rooms), then try again.'
                : 'Loosen the guest’s preferences to see more free rooms.',
            style: _T.body(size: 12.5, color: _T.subtitle),
            textAlign: TextAlign.center,
          ),
          if (!noneFree) ...[
            const SizedBox(height: 14),
            Wrap(
              alignment: WrapAlignment.center,
              spacing: 8,
              runSpacing: 8,
              children: [
                OutlinedButton.icon(
                  onPressed: () => setState(() {
                    _step = 1;
                    _error = null;
                  }),
                  icon: const Icon(Icons.tune_rounded, size: 18),
                  label: const Text('Edit preferences'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: _T.text,
                    side: const BorderSide(color: _T.border),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
                FilledButton.icon(
                  onPressed: _clearPreferences,
                  icon: const Icon(Icons.filter_alt_off_rounded, size: 18),
                  label: const Text('Show all free rooms'),
                  style: FilledButton.styleFrom(
                    backgroundColor: AppTheme.brandOrange,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

typedef _T = GovernorDashboardTokens;

enum _StepVisual { done, active, upcoming }

class _StepIndicator extends StatelessWidget {
  const _StepIndicator({
    required this.index,
    required this.label,
    required this.state,
    this.onTap,
  });

  final int index;
  final String label;
  final _StepVisual state;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final active = state == _StepVisual.active;
    final done = state == _StepVisual.done;
    final fill = done || active ? _T.primary : Colors.white;
    final fg = done || active ? Colors.white : _T.subtitle;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 220),
              width: 26,
              height: 26,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: fill,
                shape: BoxShape.circle,
                border: Border.all(
                  color: done || active ? _T.primary : _T.border,
                  width: 1.5,
                ),
                boxShadow: active
                    ? [
                        BoxShadow(
                          color: _T.primary.withValues(alpha: 0.35),
                          blurRadius: 8,
                          offset: const Offset(0, 2),
                        ),
                      ]
                    : null,
              ),
              child: done
                  ? const Icon(Icons.check_rounded, size: 15, color: Colors.white)
                  : Text(
                      '${index + 1}',
                      style: _T.body(size: 12, color: fg)
                          .copyWith(fontWeight: FontWeight.w800),
                    ),
            ),
            const SizedBox(width: 6),
            Text(
              label,
              style: _T.body(
                size: 12.5,
                color: active
                    ? _T.primaryDark
                    : done
                        ? _T.text
                        : _T.subtitle,
              ).copyWith(
                fontWeight: active ? FontWeight.w800 : FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MiniRoomCube extends StatefulWidget {
  const _MiniRoomCube({
    required this.slot,
    required this.selected,
    required this.onSelect,
    required this.onInfo,
  });

  final EstablishmentRoomSlot slot;
  final bool selected;
  final VoidCallback onSelect;
  final VoidCallback onInfo;

  @override
  State<_MiniRoomCube> createState() => _MiniRoomCubeState();
}

class _MiniRoomCubeState extends State<_MiniRoomCube> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final selected = widget.selected;
    final color = selected ? AppTheme.brandOrange : const Color(0xFF16A34A);
    final info = widget.slot.info;
    final lifted = _hover || selected;
    final capacity = info.capacityMax <= 0
        ? ''
        : info.capacityMin > 0 && info.capacityMin != info.capacityMax
            ? '${info.capacityMin}–${info.capacityMax} pax'
            : '${info.capacityMax} pax';
    final price = info.pricePerNight > 0
        ? '₱${info.pricePerNight.toStringAsFixed(0)}'
        : '';

    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        width: 116,
        height: 132,
        transform: Matrix4.translationValues(0, _hover ? -3 : 0, 0),
        decoration: BoxDecoration(
          color: selected ? const Color(0xFFFFF7ED) : Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: lifted ? color : _T.border,
            width: selected ? 2 : 1.2,
          ),
          boxShadow: [
            BoxShadow(
              color: color.withValues(alpha: lifted ? 0.22 : 0.06),
              blurRadius: lifted ? 14 : 6,
              offset: Offset(0, lifted ? 6 : 2),
            ),
          ],
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: widget.onSelect,
            onLongPress: widget.onInfo,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(10, 8, 6, 4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.king_bed_rounded, size: 18, color: color),
                      const Spacer(),
                      AnimatedSwitcher(
                        duration: const Duration(milliseconds: 160),
                        child: selected
                            ? Icon(
                                Icons.check_circle_rounded,
                                key: const ValueKey('on'),
                                size: 20,
                                color: color,
                              )
                            : const Icon(
                                Icons.radio_button_unchecked_rounded,
                                key: ValueKey('off'),
                                size: 20,
                                color: _T.border,
                              ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    widget.slot.id,
                    style: _T.number(size: 22, color: _T.text),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    info.type.isEmpty ? 'Room' : info.type,
                    style: _T.body(size: 11, color: _T.subtitle),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (capacity.isNotEmpty || price.isNotEmpty)
                    Text(
                      [capacity, price].where((s) => s.isNotEmpty).join(' · '),
                      style: _T.body(size: 10.5, color: color)
                          .copyWith(fontWeight: FontWeight.w700),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  const Spacer(),
                  InkWell(
                    onTap: widget.onInfo,
                    borderRadius: BorderRadius.circular(8),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 2),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            Icons.info_outline_rounded,
                            size: 13,
                            color: _T.subtitle,
                          ),
                          const SizedBox(width: 3),
                          Text(
                            'Info',
                            style: _T.body(size: 11, color: _T.subtitle)
                                .copyWith(fontWeight: FontWeight.w600),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

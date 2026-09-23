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

  @override
  Widget build(BuildContext context) {
    final stay = widget.stay;
    final sex = _sexSeed;
    final res = _residencySeed;
    final titles = widget.lodging
        ? const ['Guests', 'Preferences', 'Pick rooms']
        : const ['Guests'];

    return AlertDialog(
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(widget.copy.confirmTitle),
          const SizedBox(height: 8),
          Row(
            children: [
              for (var i = 0; i < titles.length; i++) ...[
                if (i > 0)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 6),
                    child: Icon(
                      Icons.chevron_right_rounded,
                      size: 16,
                      color: GovernorDashboardTokens.subtitle,
                    ),
                  ),
                Text(
                  titles[i],
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight:
                        _step == i ? FontWeight.w800 : FontWeight.w500,
                    color: _step == i
                        ? AppTheme.brandOrangeDark
                        : GovernorDashboardTokens.subtitle,
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
      content: SizedBox(
        width: 480,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                stay.touristName.isNotEmpty ? stay.touristName : 'Tourist',
                style: GovernorDashboardTokens.sectionTitle(),
              ),
              if (stay.touristEmail.isNotEmpty)
                Text(stay.touristEmail, style: GovernorDashboardTokens.body()),
              const SizedBox(height: 12),
              if (_step == 0) _buildGuestsStep(sex, res),
              if (_step == 1) _buildPrefsStep(),
              if (_step == 2) _buildRoomsStep(),
              if (_error != null) ...[
                const SizedBox(height: 10),
                Text(
                  _error!,
                  style: TextStyle(
                    color: Colors.red.shade700,
                    fontSize: 12.5,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _back,
          child: Text(_step == 0 ? 'Cancel' : 'Back'),
        ),
        FilledButton(
          onPressed: _next,
          style: FilledButton.styleFrom(
            backgroundColor: AppTheme.brandOrange,
          ),
          child: Text(
            !widget.lodging || _step == 2 ? 'Confirm' : 'Next',
          ),
        ),
      ],
    );
  }

  Widget _buildGuestsStep(
    ({int male, int female}) sex,
    ({int filipino, int foreign}) res,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          '1. Ask how many guests and mark gender / nationality for DOT forms.',
          style: GovernorDashboardTokens.body(size: 12.5),
        ),
        const SizedBox(height: 12),
        PartyDemographicFields(
          key: _demoKey,
          initialPartySize: _savedDemo?.partySize ?? _partySeed,
          initialMale: _savedDemo?.maleCount ?? sex.male,
          initialFemale: _savedDemo?.femaleCount ?? sex.female,
          initialFilipino: _savedDemo?.filipinoCount ?? res.filipino,
          initialForeign: _savedDemo?.foreignCount ?? res.foreign,
        ),
        if (widget.lodging) ...[
          const SizedBox(height: 12),
          TextField(
            controller: _nightsCtrl,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(
              labelText: 'Nights stayed',
              border: const OutlineInputBorder(),
              isDense: true,
              helperText: _earlyArrivalHint,
              helperMaxLines: 3,
              helperStyle: _earlyArrival
                  ? TextStyle(color: Colors.orange.shade800, fontSize: 11.5)
                  : null,
            ),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _roomsCtrl,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(
              labelText: 'Rooms needed',
              border: const OutlineInputBorder(),
              isDense: true,
              helperText:
                  'Free rooms now: ${EstablishmentRoomGrid.freeSlots(widget.allSlots).length}',
            ),
          ),
        ] else ...[
          const SizedBox(height: 8),
          Text(
            widget.copy.confirmNonLodgingNote.isNotEmpty
                ? widget.copy.confirmNonLodgingNote
                : 'Visit confirm — no room assignment.',
            style: GovernorDashboardTokens.body(size: 12),
          ),
        ],
        const SizedBox(height: 10),
        TextField(
          controller: _notesCtrl,
          maxLines: 2,
          decoration: const InputDecoration(
            labelText: 'Notes (optional)',
            border: OutlineInputBorder(),
            isDense: true,
          ),
        ),
      ],
    );
  }

  Widget _buildPrefsStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          '2. Ask for room preferences. Matching free rooms appear on the next step.',
          style: GovernorDashboardTokens.body(size: 12.5),
        ),
        const SizedBox(height: 12),
        DropdownButtonFormField<String>(
          // ignore: deprecated_member_use
          value: _prefType.isEmpty ? null : _prefType,
          decoration: const InputDecoration(
            labelText: 'Room type (optional)',
            border: OutlineInputBorder(),
            isDense: true,
          ),
          items: [
            const DropdownMenuItem(value: '', child: Text('Any type')),
            for (final t in EstablishmentRoomCatalog.roomTypes)
              DropdownMenuItem(value: t, child: Text(t)),
          ],
          onChanged: (v) => setState(() => _prefType = v ?? ''),
        ),
        const SizedBox(height: 12),
        Text(
          'Good for (capacity)',
          style: GovernorDashboardTokens.sectionTitle(size: 13),
        ),
        const SizedBox(height: 6),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            FilterChip(
              label: const Text('Any'),
              selected: _prefCapMin <= 0 && _prefCapMax <= 0,
              onSelected: (_) => setState(() {
                _prefCapMin = 0;
                _prefCapMax = 0;
              }),
              selectedColor: GovernorDashboardTokens.softOrange,
            ),
            for (final p in EstablishmentRoomCatalog.capacityPresets)
              FilterChip(
                label: Text(p.$3),
                selected: _prefCapMin == p.$1 && _prefCapMax == p.$2,
                onSelected: (_) => setState(() {
                  _prefCapMin = p.$1;
                  _prefCapMax = p.$2;
                }),
                selectedColor: GovernorDashboardTokens.softOrange,
              ),
          ],
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _maxPriceCtrl,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(
            labelText: 'Max price / night (₱, optional)',
            border: OutlineInputBorder(),
            isDense: true,
          ),
        ),
        const SizedBox(height: 12),
        Text(
          'Must include',
          style: GovernorDashboardTokens.sectionTitle(size: 13),
        ),
        const SizedBox(height: 6),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final inc in _inclusionChoices)
              FilterChip(
                label: Text(inc),
                selected: _prefInclusions.any(
                  (e) => e.toLowerCase() == inc.toLowerCase(),
                ),
                onSelected: (on) => setState(() {
                  _prefInclusions.removeWhere(
                    (e) => e.toLowerCase() == inc.toLowerCase(),
                  );
                  if (on) _prefInclusions.add(inc);
                }),
                selectedColor: GovernorDashboardTokens.softOrange,
              ),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _customPrefInclCtrl,
                textInputAction: TextInputAction.done,
                onSubmitted: (_) => _addCustomPrefInclusion(),
                decoration: const InputDecoration(
                  labelText: 'Add inclusion filter',
                  hintText: 'Not in the list? Type it here',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
              ),
            ),
            const SizedBox(width: 8),
            FilledButton(
              onPressed: _addCustomPrefInclusion,
              style: FilledButton.styleFrom(
                backgroundColor: AppTheme.brandOrange,
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 14,
                ),
              ),
              child: const Text('Add'),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Text(
          '${_matchedFree.length} free room(s) match these preferences.',
          style: GovernorDashboardTokens.body(size: 13),
        ),
      ],
    );
  }

  Widget _buildRoomsStep() {
    final matched = _matchedFree;
    final roomsNeeded = int.tryParse(_roomsCtrl.text.trim()) ?? 0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          '3. Offer matching free rooms. Tap a cube for details; select '
          '$roomsNeeded room(s) to assign.',
          style: GovernorDashboardTokens.body(size: 12.5),
        ),
        const SizedBox(height: 8),
        Text(
          'Selected ${_selectedSlots.length} / $roomsNeeded',
          style: GovernorDashboardTokens.sectionTitle(size: 13),
        ),
        const SizedBox(height: 10),
        if (matched.isEmpty)
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: GovernorDashboardTokens.mutedSurface,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Text(
              'No free rooms match. Go back and loosen preferences, '
              'or add room details in the Rooms tab (Edit rooms).',
              style: GovernorDashboardTokens.body(size: 13),
            ),
          )
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
    final color = widget.selected
        ? AppTheme.brandOrange
        : const Color(0xFF16A34A);
    final info = widget.slot.info;

    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        width: 108,
        height: 108,
        transform: Matrix4.translationValues(0, _hover ? -4 : 0, 0),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: color.withValues(alpha: _hover || widget.selected ? 0.95 : 0.5),
            width: widget.selected || _hover ? 2.2 : 1.4,
          ),
          boxShadow: [
            BoxShadow(
              color: color.withValues(alpha: _hover ? 0.28 : 0.12),
              blurRadius: _hover ? 16 : 8,
              offset: Offset(0, _hover ? 8 : 4),
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
              padding: const EdgeInsets.all(8),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    widget.slot.id,
                    style: GovernorDashboardTokens.number(
                      size: 20,
                      color: color,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    info.type.isEmpty ? 'Room' : info.type,
                    style: GovernorDashboardTokens.body(size: 10, color: color),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  TextButton(
                    onPressed: widget.onInfo,
                    style: TextButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                      padding: EdgeInsets.zero,
                      minimumSize: const Size(0, 24),
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    child: const Text('Info', style: TextStyle(fontSize: 11)),
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

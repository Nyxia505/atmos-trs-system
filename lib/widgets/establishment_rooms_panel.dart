import 'dart:async';
import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/material.dart';

import 'package:atmos_trs_system/config/app_theme.dart';
import 'package:atmos_trs_system/utils/establishment_room_grid.dart';
import 'package:atmos_trs_system/widgets/establishment_dash_tokens.dart';

enum _RoomFilter { all, occupied, free, disabled }

/// Lodging Rooms tab: filterable Room 1Ã¢â‚¬Â¦N grid with hover / hold / edit UX.
class EstablishmentRoomsPanel extends StatefulWidget {
  const EstablishmentRoomsPanel({
    super.key,
    required this.slots,
    required this.onToggleDisabled,
    required this.onSaveRoomInfo,
  });

  final List<EstablishmentRoomSlot> slots;
  final Future<bool> Function(EstablishmentRoomSlot slot, bool disable)
      onToggleDisabled;
  final Future<void> Function(String slotId, EstablishmentRoomInfo info)
      onSaveRoomInfo;

  @override
  State<EstablishmentRoomsPanel> createState() =>
      _EstablishmentRoomsPanelState();
}

class _EstablishmentRoomsPanelState extends State<EstablishmentRoomsPanel> {
  static const int _pageSize = 24;

  _RoomFilter _filter = _RoomFilter.all;
  final _searchCtrl = TextEditingController();
  int _page = 0;
  bool _editMode = false;

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant EstablishmentRoomsPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    final filtered = _filtered.length;
    final maxPage = filtered == 0 ? 0 : (filtered - 1) ~/ _pageSize;
    if (_page > maxPage) {
      _page = maxPage;
    }
  }

  List<EstablishmentRoomSlot> get _filtered {
    final q = _searchCtrl.text.trim().toLowerCase();
    return [
      for (final s in widget.slots)
        if (_matchesFilter(s) &&
            (q.isEmpty ||
                s.id.contains(q) ||
                s.label.toLowerCase().contains(q) ||
                s.info.type.toLowerCase().contains(q)))
          s,
    ];
  }

  bool _matchesFilter(EstablishmentRoomSlot s) {
    switch (_filter) {
      case _RoomFilter.all:
        return true;
      case _RoomFilter.occupied:
        return s.isOccupied;
      case _RoomFilter.free:
        return s.isFree;
      case _RoomFilter.disabled:
        return s.isDisabled;
    }
  }

  Future<void> _openRoom(EstablishmentRoomSlot slot) async {
    if (_editMode) {
      final saved = await showRoomInfoEditor(
        context: context,
        slot: slot,
        editable: true,
      );
      if (saved != null) {
        await widget.onSaveRoomInfo(slot.id, saved);
      }
      return;
    }
    if (slot.isOccupied && slot.stay != null) {
      await showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.white,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        builder: (ctx) => _OccupiedRoomSheet(slot: slot),
      );
      return;
    }
    await showRoomInfoEditor(
      context: context,
      slot: slot,
      editable: false,
    );
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _filtered;
    final total = filtered.length;
    final maxPage = total == 0 ? 0 : (total - 1) ~/ _pageSize;
    final page = _page.clamp(0, maxPage);
    final start = total == 0 ? 0 : page * _pageSize;
    final end = total == 0 ? 0 : (start + _pageSize).clamp(0, total);
    final pageSlots =
        total == 0 ? const <EstablishmentRoomSlot>[] : filtered.sublist(start, end);
    final stats = EstablishmentRoomGrid.statsFor(widget.slots);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                'Rooms',
                style: AeDashTokens.heading(size: 18),
              ),
            ),
            FilledButton.tonalIcon(
              onPressed: () => setState(() => _editMode = !_editMode),
              icon: Icon(
                _editMode ? Icons.check_rounded : Icons.edit_rounded,
                size: 18,
              ),
              label: Text(_editMode ? 'Done editing' : 'Edit rooms'),
              style: FilledButton.styleFrom(
                foregroundColor: _editMode
                    ? AppTheme.brandOrangeDark
                    : AeDashTokens.text,
                backgroundColor: _editMode
                    ? AeDashTokens.softOrange
                    : AeDashTokens.mutedSurface,
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          _editMode
              ? 'Edit mode on Ã¢â‚¬â€ click a cube to edit type, capacity, price, and inclusions. '
                  'Hold-to-disable is paused while editing.'
              : 'Room 1Ã¢â‚¬â€œ${widget.slots.length}. Green = free, red = occupied, orange = disabled. '
                  'Hold a free/disabled box for 3 seconds to toggle. Hover occupied for checkout days.',
          style: AeDashTokens.body(size: 13),
        ),
        const SizedBox(height: 14),
        _statsRow(stats),
        const SizedBox(height: 14),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final f in _RoomFilter.values)
              FilterChip(
                selected: _filter == f,
                label: Text(_filterLabel(f)),
                onSelected: (_) => setState(() {
                  _filter = f;
                  _page = 0;
                }),
                selectedColor: AeDashTokens.softOrange,
                checkmarkColor: AppTheme.brandOrangeDark,
              ),
          ],
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _searchCtrl,
          onChanged: (_) => setState(() => _page = 0),
          decoration: InputDecoration(
            hintText: 'Search room number or typeÃ¢â‚¬Â¦',
            prefixIcon: const Icon(Icons.search_rounded),
            isDense: true,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
            ),
            filled: true,
            fillColor: Colors.white,
          ),
        ),
        const SizedBox(height: 12),
        if (widget.slots.isEmpty)
          _messageCard(
            'Set total rooms in QR & profile to open the room grid.',
          )
        else if (pageSlots.isEmpty)
          _messageCard('No rooms match this filter / search.')
        else
          LayoutBuilder(
            builder: (context, constraints) {
              final width = constraints.maxWidth;
              final cross = width >= 900
                  ? 6
                  : width >= 640
                      ? 4
                      : width >= 400
                          ? 3
                          : 2;
              return GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: pageSlots.length,
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: cross,
                  mainAxisSpacing: 14,
                  crossAxisSpacing: 14,
                  childAspectRatio: 1.05,
                ),
                itemBuilder: (context, i) {
                  final slot = pageSlots[i];
                  return _RoomCube(
                    slot: slot,
                    editMode: _editMode,
                    onTap: () => _openRoom(slot),
                    onToggleDisabled: widget.onToggleDisabled,
                  );
                },
              );
            },
          ),
        if (total > _pageSize) ...[
          const SizedBox(height: 16),
          Row(
            children: [
              IconButton(
                tooltip: 'Previous',
                onPressed:
                    page <= 0 ? null : () => setState(() => _page = page - 1),
                icon: const Icon(Icons.chevron_left_rounded),
              ),
              Expanded(
                child: Text(
                  total == 0
                      ? 'No rooms'
                      : 'Showing ${start + 1}Ã¢â‚¬â€œ$end of $total',
                  textAlign: TextAlign.center,
                  style: AeDashTokens.body(size: 13),
                ),
              ),
              IconButton(
                tooltip: 'Next',
                onPressed: page >= maxPage
                    ? null
                    : () => setState(() => _page = page + 1),
                icon: const Icon(Icons.chevron_right_rounded),
              ),
            ],
          ),
        ],
      ],
    );
  }

  Widget _messageCard(String message) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(AeDashTokens.radiusCard),
        border: Border.all(color: AeDashTokens.border),
      ),
      child: Text(message, style: AeDashTokens.body()),
    );
  }

  String _filterLabel(_RoomFilter f) {
    switch (f) {
      case _RoomFilter.all:
        return 'All';
      case _RoomFilter.occupied:
        return 'Occupied';
      case _RoomFilter.free:
        return 'Free';
      case _RoomFilter.disabled:
        return 'Disabled';
    }
  }

  Widget _statsRow(EstablishmentRoomStats stats) {
    Widget chip(String label, String value, Color color) {
      return Expanded(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius:
                BorderRadius.circular(AeDashTokens.radiusMd),
            border: Border.all(color: color.withValues(alpha: 0.35)),
            boxShadow: AeDashTokens.cardShadow,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                value,
                style: AeDashTokens.number(size: 20, color: color),
              ),
              const SizedBox(height: 4),
              Text(label, style: AeDashTokens.body(size: 11)),
            ],
          ),
        ),
      );
    }

    return Row(
      children: [
        chip('Total', '${stats.total}', AppTheme.brandOrange),
        const SizedBox(width: 8),
        chip('Occupied', '${stats.occupied}', const Color(0xFFDC2626)),
        const SizedBox(width: 8),
        chip('Free', '${stats.free}', const Color(0xFF16A34A)),
        const SizedBox(width: 8),
        chip('Disabled', '${stats.disabled}', const Color(0xFFEA580C)),
      ],
    );
  }
}

/// View or edit room catalog details. Returns saved [EstablishmentRoomInfo] when editable + Save.
Future<EstablishmentRoomInfo?> showRoomInfoEditor({
  required BuildContext context,
  required EstablishmentRoomSlot slot,
  required bool editable,
}) {
  return showDialog<EstablishmentRoomInfo>(
    context: context,
    builder: (ctx) => _RoomInfoDialog(slot: slot, editable: editable),
  );
}

class _RoomInfoDialog extends StatefulWidget {
  const _RoomInfoDialog({required this.slot, required this.editable});

  final EstablishmentRoomSlot slot;
  final bool editable;

  @override
  State<_RoomInfoDialog> createState() => _RoomInfoDialogState();
}

class _RoomInfoDialogState extends State<_RoomInfoDialog> {
  late String _type;
  late final TextEditingController _capMinCtrl;
  late final TextEditingController _capMaxCtrl;
  late final TextEditingController _priceCtrl;
  late final TextEditingController _notesCtrl;
  late final TextEditingController _customInclCtrl;
  late Set<String> _inclusions;

  @override
  void initState() {
    super.initState();
    final info = widget.slot.info;
    _type = info.type;
    _capMinCtrl = TextEditingController(
      text: info.capacityMin > 0 ? '${info.capacityMin}' : '',
    );
    _capMaxCtrl = TextEditingController(
      text: info.capacityMax > 0 ? '${info.capacityMax}' : '',
    );
    _priceCtrl = TextEditingController(
      text: info.pricePerNight > 0
          ? (info.pricePerNight == info.pricePerNight.roundToDouble()
              ? info.pricePerNight.toStringAsFixed(0)
              : info.pricePerNight.toStringAsFixed(2))
          : '',
    );
    _notesCtrl = TextEditingController(text: info.notes);
    _customInclCtrl = TextEditingController();
    _inclusions = {...info.inclusions};
  }

  @override
  void dispose() {
    _capMinCtrl.dispose();
    _capMaxCtrl.dispose();
    _priceCtrl.dispose();
    _notesCtrl.dispose();
    _customInclCtrl.dispose();
    super.dispose();
  }

  void _addCustomInclusion() {
    final raw = _customInclCtrl.text.trim();
    if (raw.isEmpty) return;
    // Case-insensitive dedupe against existing.
    final exists = _inclusions.any(
      (e) => e.toLowerCase() == raw.toLowerCase(),
    );
    if (exists) {
      _customInclCtrl.clear();
      return;
    }
    setState(() {
      _inclusions.add(raw);
      _customInclCtrl.clear();
    });
  }

  List<String> get _customSelected {
    final catalog = {
      for (final c in EstablishmentRoomCatalog.inclusions) c.toLowerCase(),
    };
    return [
      for (final i in _inclusions)
        if (!catalog.contains(i.toLowerCase())) i,
    ]..sort();
  }

  void _save() {
    final min = int.tryParse(_capMinCtrl.text.trim()) ?? 0;
    final max = int.tryParse(_capMaxCtrl.text.trim()) ?? 0;
    final price = double.tryParse(_priceCtrl.text.trim()) ?? 0;
    Navigator.pop(
      context,
      EstablishmentRoomInfo(
        type: _type,
        capacityMin: min,
        capacityMax: max < min && min > 0 ? min : max,
        pricePerNight: price,
        inclusions: _inclusions.toList()..sort(),
        notes: _notesCtrl.text,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final info = widget.slot.info;
    return AlertDialog(
      title: Text(
        widget.editable
            ? 'Edit ${widget.slot.label}'
            : widget.slot.label,
      ),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: widget.editable
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    DropdownButtonFormField<String>(
                      // ignore: deprecated_member_use
                      value: _type.isEmpty ? null : _type,
                      decoration: const InputDecoration(
                        labelText: 'Room type',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                      items: [
                        for (final t in EstablishmentRoomCatalog.roomTypes)
                          DropdownMenuItem(value: t, child: Text(t)),
                      ],
                      onChanged: (v) => setState(() => _type = v ?? ''),
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _capMinCtrl,
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(
                              labelText: 'Good for (min)',
                              border: OutlineInputBorder(),
                              isDense: true,
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: TextField(
                            controller: _capMaxCtrl,
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(
                              labelText: 'Good for (max)',
                              border: OutlineInputBorder(),
                              isDense: true,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: _priceCtrl,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: const InputDecoration(
                        labelText: 'Price per night (Ã¢â€šÂ±)',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Inclusions',
                      style: AeDashTokens.sectionTitle(size: 13),
                    ),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final inc in EstablishmentRoomCatalog.inclusions)
                          FilterChip(
                            label: Text(inc),
                            selected: _inclusions.any(
                              (e) => e.toLowerCase() == inc.toLowerCase(),
                            ),
                            onSelected: (on) => setState(() {
                              _inclusions.removeWhere(
                                (e) => e.toLowerCase() == inc.toLowerCase(),
                              );
                              if (on) _inclusions.add(inc);
                            }),
                            selectedColor: AeDashTokens.softOrange,
                          ),
                        for (final custom in _customSelected)
                          InputChip(
                            label: Text(custom),
                            onDeleted: () => setState(() {
                              _inclusions.removeWhere(
                                (e) =>
                                    e.toLowerCase() == custom.toLowerCase(),
                              );
                            }),
                            backgroundColor: AeDashTokens.softOrange,
                          ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _customInclCtrl,
                            textInputAction: TextInputAction.done,
                            onSubmitted: (_) => _addCustomInclusion(),
                            decoration: const InputDecoration(
                              labelText: 'Add custom inclusion',
                              hintText: 'e.g. Jacuzzi, crib, parking',
                              border: OutlineInputBorder(),
                              isDense: true,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        FilledButton(
                          onPressed: _addCustomInclusion,
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
                    const SizedBox(height: 10),
                    TextField(
                      controller: _notesCtrl,
                      maxLines: 2,
                      decoration: const InputDecoration(
                        labelText: 'Notes',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                    ),
                  ],
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _readRow('Status', widget.slot.isOccupied
                        ? 'Occupied'
                        : widget.slot.isDisabled
                            ? 'Disabled'
                            : 'Free'),
                    _readRow(
                      'Type',
                      info.type.isEmpty ? 'Not set' : info.type,
                    ),
                    _readRow('Capacity', info.capacityLabel),
                    _readRow('Price', info.priceLabel),
                    _readRow(
                      'Inclusions',
                      info.inclusions.isEmpty
                          ? 'None listed'
                          : info.inclusions.join(', '),
                    ),
                    if (info.notes.trim().isNotEmpty)
                      _readRow('Notes', info.notes.trim()),
                    if (!info.hasDetails)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Text(
                          'No catalog details yet. Use Edit rooms on the Rooms tab.',
                          style: AeDashTokens.body(size: 12),
                        ),
                      ),
                  ],
                ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(widget.editable ? 'Cancel' : 'Close'),
        ),
        if (widget.editable)
          FilledButton(
            onPressed: _save,
            style: FilledButton.styleFrom(
              backgroundColor: AppTheme.brandOrange,
            ),
            child: const Text('Save'),
          ),
      ],
    );
  }

  Widget _readRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 100,
            child: Text(label, style: AeDashTokens.body(size: 13)),
          ),
          Expanded(
            child: Text(
              value,
              style: AeDashTokens.sectionTitle(size: 14),
            ),
          ),
        ],
      ),
    );
  }
}

class _RoomCube extends StatefulWidget {
  const _RoomCube({
    required this.slot,
    required this.editMode,
    required this.onTap,
    required this.onToggleDisabled,
  });

  final EstablishmentRoomSlot slot;
  final bool editMode;
  final VoidCallback onTap;
  final Future<bool> Function(EstablishmentRoomSlot slot, bool disable)
      onToggleDisabled;

  @override
  State<_RoomCube> createState() => _RoomCubeState();
}

class _RoomCubeState extends State<_RoomCube> with TickerProviderStateMixin {
  bool _hover = false;
  late final AnimationController _floatCtrl;
  late final AnimationController _holdCtrl;
  late final AnimationController _splashCtrl;
  late final AnimationController _fadeCtrl;
  Timer? _holdTimer;
  bool _holding = false;
  bool _busy = false;
  bool _wrapping = true;

  static const _free = Color(0xFF16A34A);
  static const _occupied = Color(0xFFDC2626);
  static const _disabled = Color(0xFFEA580C);

  @override
  void initState() {
    super.initState();
    _floatCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 180),
    );
    _holdCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 3000),
    );
    _splashCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 420),
    );
    _fadeCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 220),
      value: 1,
    );
    _holdCtrl.addStatusListener(_onHoldStatus);
  }

  @override
  void dispose() {
    _holdTimer?.cancel();
    _holdCtrl.removeStatusListener(_onHoldStatus);
    _floatCtrl.dispose();
    _holdCtrl.dispose();
    _splashCtrl.dispose();
    _fadeCtrl.dispose();
    super.dispose();
  }

  void _onHoldStatus(AnimationStatus status) {
    if (status != AnimationStatus.dismissed) return;
    if (_holding || _busy) return;
    if (_wrapping) return;
    // Unwrap cancelled: tape is fully wound again Ã¢â‚¬â€ fade it off.
    _fadeCtrl.reverse().whenComplete(() {
      if (!mounted || _holding || _busy) return;
      setState(() => _wrapping = true);
      _fadeCtrl.value = 1;
    });
  }

  Color get _baseColor {
    if (widget.editMode) return AppTheme.brandOrange;
    switch (widget.slot.status) {
      case EstablishmentRoomStatus.free:
        return _free;
      case EstablishmentRoomStatus.occupied:
        return _occupied;
      case EstablishmentRoomStatus.disabled:
        return _disabled;
    }
  }

  /// 0 = no tape, 1 = fully wrapped X across the cube.
  double get _tapeProgress {
    final v = _holdCtrl.value;
    return _wrapping ? v : (1 - v);
  }

  void _onEnter(PointerEvent _) {
    setState(() => _hover = true);
    _floatCtrl.forward();
  }

  void _onExit(PointerEvent _) {
    setState(() => _hover = false);
    if (!_holding) _floatCtrl.reverse();
  }

  void _startHold() {
    if (widget.editMode || _busy) return;
    if (widget.slot.isOccupied) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Cannot disable an occupied room. Wait until checkout.',
          ),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }
    setState(() {
      _holding = true;
      _wrapping = !widget.slot.isDisabled;
    });
    _fadeCtrl.value = 1;
    _holdCtrl.forward(from: 0);
    _holdTimer?.cancel();
    _holdTimer = Timer(const Duration(milliseconds: 3000), _completeHold);
  }

  void _cancelHold() {
    _holdTimer?.cancel();
    if (!_holding || _busy) return;
    setState(() => _holding = false);
    final ms = (420 * _holdCtrl.value).round().clamp(140, 420);
    _holdCtrl.animateTo(
      0,
      duration: Duration(milliseconds: ms),
      curve: Curves.easeOutCubic,
    );
    if (!_hover) _floatCtrl.reverse();
  }

  Future<void> _completeHold() async {
    if (!_holding || _busy) return;
    final disable = !widget.slot.isDisabled;
    setState(() {
      _holding = false;
      _busy = true;
    });
    final ok = await widget.onToggleDisabled(widget.slot, disable);
    if (!mounted) return;
    final reduce = MediaQuery.disableAnimationsOf(context);
    if (ok && !reduce) {
      await _splashCtrl.forward(from: 0);
    } else if (!ok) {
      await _holdCtrl.animateTo(
        0,
        duration: const Duration(milliseconds: 280),
        curve: Curves.easeOutCubic,
      );
    }
    if (!mounted) return;
    setState(() {
      _busy = false;
      _wrapping = true;
    });
    _holdCtrl.value = 0;
    _splashCtrl.value = 0;
    _fadeCtrl.value = 1;
    if (!_hover) _floatCtrl.reverse();
  }

  @override
  Widget build(BuildContext context) {
    final days = EstablishmentRoomGrid.daysUntilCheckout(widget.slot.stay);
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    final type = widget.slot.info.type;

    return MouseRegion(
      onEnter: _onEnter,
      onExit: _onExit,
      child: GestureDetector(
        onTap: () {
          if (_holding || _busy) return;
          widget.onTap();
        },
        onLongPressStart: widget.editMode ? null : (_) => _startHold(),
        onLongPressEnd: widget.editMode ? null : (_) => _cancelHold(),
        onLongPressCancel: widget.editMode ? null : _cancelHold,
        child: AnimatedBuilder(
          animation: Listenable.merge([
            _floatCtrl,
            _holdCtrl,
            _splashCtrl,
            _fadeCtrl,
          ]),
          builder: (context, child) {
            final color = _baseColor;
            final lift = reduceMotion ? 0.0 : 6.0 * _floatCtrl.value;
            final hoverScale =
                reduceMotion ? 1.0 : 1.0 + (0.04 * _floatCtrl.value);
            final settle = reduceMotion
                ? 1.0
                : 1 + 0.045 * math.sin(_splashCtrl.value * math.pi);
            final glow = _hover || _holding || widget.editMode;
            final restingDisabled = widget.slot.isDisabled &&
                !_holding &&
                !_busy &&
                _holdCtrl.value < 0.001;
            final tapeT = restingDisabled
                ? 1.0
                : (reduceMotion ? 0.0 : _tapeProgress);
            final tapeOpacity = restingDisabled ? 1.0 : _fadeCtrl.value;
            final showTape = tapeT > 0.001 && tapeOpacity > 0.01;
            final splashT = _splashCtrl.value;
            final splashColor = _wrapping ? _disabled : _free;
            final fill = widget.editMode
                ? color.withValues(alpha: 0.12)
                : widget.slot.isDisabled
                    ? const Color(0xFFFFF1E8)
                    : widget.slot.isOccupied
                        ? const Color(0xFFFEE2E2)
                        : const Color(0xFFECFDF5);
            final ink = widget.slot.isDisabled && !widget.editMode
                ? const Color(0xFFC2410C)
                : color;

            return Transform.translate(
              offset: Offset(0, -lift),
              child: Transform.scale(
                scale: hoverScale * settle,
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 160),
                      decoration: BoxDecoration(
                        color: fill,
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(
                          color: color.withValues(alpha: glow ? 0.95 : 0.7),
                          width: glow ? 2.2 : 1.6,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: color.withValues(alpha: glow ? 0.28 : 0.12),
                            blurRadius: glow ? 18 : 10,
                            offset: Offset(0, glow ? 8 : 4),
                          ),
                        ],
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(16),
                        child: Stack(
                        children: [
                          if (showTape)
                            Positioned.fill(
                              child: CustomPaint(
                                painter: _RoomTapePainter(
                                  progress: tapeT,
                                  opacity: tapeOpacity,
                                ),
                              ),
                            ),
                          Center(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Transform.translate(
                                  offset: Offset(0, -22 * tapeT),
                                  child: Text(
                                    widget.slot.id,
                                    style: AeDashTokens.number(
                                      size: 22,
                                      color: ink,
                                    ),
                                  ),
                                ),
                                SizedBox(height: 4 + 18 * tapeT),
                                Transform.translate(
                                  offset: Offset(0, 18 * tapeT),
                                  child: Text(
                                    widget.editMode
                                        ? (type.isEmpty
                                            ? 'Edit details'
                                            : type)
                                        : widget.slot.isDisabled ||
                                                (_wrapping && tapeT > 0.35)
                                            ? 'Disabled'
                                            : widget.slot.isOccupied
                                                ? 'Occupied'
                                                : 'Free',
                                    style: AeDashTokens.body(
                                      size: 11,
                                      color: ink,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          if (_hover &&
                              !widget.editMode &&
                              widget.slot.isOccupied &&
                              days != null &&
                              !_holding)
                            Positioned(
                              left: 8,
                              right: 8,
                              bottom: 8,
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 5,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.white.withValues(alpha: 0.95),
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(
                                    color: color.withValues(alpha: 0.35),
                                  ),
                                ),
                                child: Text(
                                  days <= 0
                                      ? 'Checkout today'
                                      : days == 1
                                          ? 'Checkout in 1 day'
                                          : 'Checkout in $days days',
                                  textAlign: TextAlign.center,
                                  style: AeDashTokens.body(
                                    size: 10,
                                    color: AeDashTokens.text,
                                  ),
                                ),
                              ),
                            ),
                          if (widget.editMode)
                            const Positioned(
                              top: 8,
                              right: 8,
                              child: Icon(
                                Icons.edit_rounded,
                                size: 14,
                                color: AppTheme.brandOrange,
                              ),
                            ),
                          if (_holding)
                            Positioned(
                              top: 8,
                              right: 8,
                              child: Text(
                                '${(3 - (_holdCtrl.value * 3)).ceil().clamp(1, 3)}s',
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w800,
                                  color: color,
                                ),
                              ),
                            ),
                        ],
                        ),
                      ),
                    ),
                    if (!reduceMotion && splashT > 0)
                      Positioned.fill(
                        child: IgnorePointer(
                          child: CustomPaint(
                            painter: _RoomSplashPainter(
                              t: splashT,
                              color: splashColor,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _RoomTapePainter extends CustomPainter {
  const _RoomTapePainter({
    required this.progress,
    required this.opacity,
  });

  final double progress;
  final double opacity;

  @override
  void paint(Canvas canvas, Size size) {
    if (progress <= 0.001 || opacity <= 0.01 || size.isEmpty) return;
    canvas.save();
    canvas.clipRRect(
      RRect.fromRectAndRadius(
        Offset.zero & size,
        const Radius.circular(16),
      ),
    );
    final first = (progress / 0.55).clamp(0.0, 1.0);
    final second = ((progress - 0.42) / 0.58).clamp(0.0, 1.0);
    if (first > 0) {
      _band(
        canvas,
        Offset(-6, -4),
        Offset(size.width + 6, size.height + 4),
        first,
      );
    }
    if (second > 0) {
      _band(
        canvas,
        Offset(size.width + 6, -4),
        Offset(-6, size.height + 4),
        second,
      );
    }
    canvas.restore();
  }

  void _band(Canvas canvas, Offset from, Offset to, double t) {
    final end = Offset.lerp(from, to, t)!;
    final delta = end - from;
    final len = delta.distance;
    if (len < 4) return;
    const width = 18.0;
    final angle = math.atan2(delta.dy, delta.dx);
    canvas.save();
    canvas.translate(from.dx, from.dy);
    canvas.rotate(angle);

    const stripe = 11.0;
    var x = 0.0;
    var i = 0;
    while (x < len) {
      final paint = Paint()
        ..color = (i.isEven ? const Color(0xFFE11D48) : const Color(0xFFFFF7F7))
            .withValues(alpha: opacity);
      canvas.drawRect(Rect.fromLTWH(x, -width / 2, stripe + 0.6, width), paint);
      x += stripe;
      i++;
    }
    final edge = Paint()
      ..color = const Color(0xFF9F1239).withValues(alpha: 0.35 * opacity)
      ..strokeWidth = 1;
    canvas.drawLine(Offset(0, -width / 2), Offset(len, -width / 2), edge);
    canvas.drawLine(Offset(0, width / 2), Offset(len, width / 2), edge);

    const label = 'DO NOT USE';
    final tp = TextPainter(
      text: TextSpan(
        text: label,
        style: TextStyle(
          color: const Color(0xFF1F2937).withValues(alpha: opacity),
          fontSize: 8,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.4,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    var lx = 8.0;
    while (lx + tp.width < len - 4) {
      tp.paint(canvas, Offset(lx, -tp.height / 2));
      lx += tp.width + 18;
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _RoomTapePainter oldDelegate) {
    return oldDelegate.progress != progress || oldDelegate.opacity != opacity;
  }
}


class _RoomSplashPainter extends CustomPainter {
  const _RoomSplashPainter({required this.t, required this.color});

  final double t;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    if (t <= 0 || size.isEmpty) return;
    final center = size.center(Offset.zero);
    final maxR = size.shortestSide * 0.78;
    void ring(double local, double delay) {
      final u = ((local - delay) / (1 - delay)).clamp(0.0, 1.0);
      if (local < delay) return;
      final radius = 6 + maxR * Curves.easeOutCubic.transform(u);
      final paint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = (5.5 * (1 - u)).clamp(0.6, 5.5)
        ..color = color.withValues(alpha: (1 - u) * 0.8);
      canvas.drawCircle(center, radius, paint);
    }

    ring(t, 0);
    ring(t, 0.18);
  }

  @override
  bool shouldRepaint(covariant _RoomSplashPainter oldDelegate) {
    return oldDelegate.t != t || oldDelegate.color != color;
  }
}


class _OccupiedRoomSheet extends StatefulWidget {
  const _OccupiedRoomSheet({required this.slot});

  final EstablishmentRoomSlot slot;

  @override
  State<_OccupiedRoomSheet> createState() => _OccupiedRoomSheetState();
}

class _OccupiedRoomSheetState extends State<_OccupiedRoomSheet> {
  bool _revealed = false;

  Future<void> _askReveal() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Reveal guest name?'),
        content: const Text(
          'Guest names are hidden by default. Reveal this bookingÃ¢â‚¬â„¢s guest name?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('No'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(
              backgroundColor: AppTheme.brandOrange,
            ),
            child: const Text('Yes'),
          ),
        ],
      ),
    );
    if (ok == true && mounted) setState(() => _revealed = true);
  }

  @override
  Widget build(BuildContext context) {
    final stay = widget.slot.stay!;
    final name = stay.touristName.isNotEmpty ? stay.touristName : 'Tourist';
    final days = EstablishmentRoomGrid.daysUntilCheckout(stay);
    final checkout = EstablishmentRoomGrid.effectiveCheckOut(stay);
    final info = widget.slot.info;

    return Padding(
      padding: EdgeInsets.fromLTRB(
        20,
        16,
        20,
        20 + MediaQuery.paddingOf(context).bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: AeDashTokens.border,
                borderRadius: BorderRadius.circular(99),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            widget.slot.label,
            style: AeDashTokens.heading(size: 20),
          ),
          if (info.hasDetails) ...[
            const SizedBox(height: 6),
            Text(
              [
                if (info.type.isNotEmpty) info.type,
                info.capacityLabel,
                info.priceLabel,
              ].join(' Ã‚Â· '),
              style: AeDashTokens.body(size: 13),
            ),
          ],
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: Text(
                  'Guest',
                  style: AeDashTokens.body(size: 12),
                ),
              ),
              if (!_revealed)
                TextButton(
                  onPressed: _askReveal,
                  child: const Text('Reveal name'),
                ),
            ],
          ),
          const SizedBox(height: 4),
          if (_revealed)
            Text(name, style: AeDashTokens.sectionTitle())
          else
            ClipRect(
              child: ImageFiltered(
                imageFilter: ImageFilter.blur(sigmaX: 7, sigmaY: 7),
                child: Text(
                  name,
                  style: AeDashTokens.sectionTitle(),
                ),
              ),
            ),
          const SizedBox(height: 16),
          _detailRow('Party size', '${stay.partySize}'),
          _detailRow('Nights', '${stay.nightsStayed ?? 'Ã¢â‚¬â€'}'),
          _detailRow(
            'Checkout',
            checkout == null
                ? 'Ã¢â‚¬â€'
                : '${checkout.year}-${checkout.month.toString().padLeft(2, '0')}-${checkout.day.toString().padLeft(2, '0')}'
                    '${days == null ? '' : days <= 0 ? ' Ã‚Â· today' : ' Ã‚Â· in $days day(s)'}',
          ),
          if (stay.notes.trim().isNotEmpty)
            _detailRow('Notes', stay.notes.trim()),
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  Widget _detailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 100,
            child: Text(label, style: AeDashTokens.body(size: 13)),
          ),
          Expanded(
            child: Text(
              value,
              style: AeDashTokens.sectionTitle(size: 14),
            ),
          ),
        ],
      ),
    );
  }
}

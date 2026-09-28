import 'dart:async';
import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/material.dart';

import 'package:atmos_trs_system/config/app_theme.dart';
import 'package:atmos_trs_system/utils/establishment_room_grid.dart';
import 'package:atmos_trs_system/widgets/establishment_dash_tokens.dart';
import 'package:atmos_trs_system/widgets/establishment_dashboard_components.dart';

enum _RoomFilter { all, occupied, free, disabled }

/// Lodging Rooms tab: filterable Room 1…N grid with hover / hold / edit UX.
class EstablishmentRoomsPanel extends StatefulWidget {
  const EstablishmentRoomsPanel({
    super.key,
    required this.slots,
    required this.onToggleDisabled,
    required this.onSaveRoomInfo,
    this.setupCard,
    this.flushHero = false,
    this.contentPadding = const EdgeInsets.only(top: 18),
  });

  final List<EstablishmentRoomSlot> slots;
  final Future<bool> Function(EstablishmentRoomSlot slot, bool disable)
  onToggleDisabled;
  final Future<void> Function(String slotId, EstablishmentRoomInfo info)
  onSaveRoomInfo;

  /// Total-rooms editor; shown first until rooms exist, then after the list.
  final Widget? setupCard;

  /// Hero touches the top / sidebar edges; [contentPadding] pads the rest.
  final bool flushHero;
  final EdgeInsets contentPadding;

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
  bool _gridView = true;

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
      await showDialog<void>(
        context: context,
        builder: (ctx) => _OccupiedRoomSheet(slot: slot),
      );
      return;
    }
    await showRoomInfoEditor(context: context, slot: slot, editable: false);
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _filtered;
    final total = filtered.length;
    final maxPage = total == 0 ? 0 : (total - 1) ~/ _pageSize;
    final page = _page.clamp(0, maxPage);
    final start = total == 0 ? 0 : page * _pageSize;
    final end = total == 0 ? 0 : (start + _pageSize).clamp(0, total);
    final pageSlots = total == 0
        ? const <EstablishmentRoomSlot>[]
        : filtered.sublist(start, end);
    final stats = EstablishmentRoomGrid.statsFor(widget.slots);
    final roomRange = widget.slots.isEmpty ? '1–N' : '1–${widget.slots.length}';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AePageHero(
          icon: Icons.bed_rounded,
          title: 'Rooms',
          subtitle: 'Manage your hotel rooms',
          note: _editMode
              ? 'Edit mode on — click a room to edit type, capacity, price, and inclusions. '
                    'Hold-to-disable is paused while editing.'
              : 'Room $roomRange. Green = free, red = occupied, orange = disabled. '
                    'Hold a free/disabled box for 3 seconds to toggle. Hover occupied for checkout days.',
          trailing: AeHeroButton(
            label: _editMode ? 'Done editing' : 'Edit rooms',
            icon: _editMode ? Icons.check_rounded : Icons.edit_rounded,
            onPressed: () => setState(() => _editMode = !_editMode),
          ),
          flush: widget.flushHero,
        ),
        Padding(
          padding: widget.contentPadding,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (widget.slots.isEmpty && widget.setupCard != null) ...[
                widget.setupCard!,
                const SizedBox(height: 18),
              ],
              _statsRow(stats),
              const SizedBox(height: 18),
              LayoutBuilder(
                builder: (context, c) {
                  final pills = Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: [
                      for (final f in _RoomFilter.values)
                        AeFilterPill(
                          label: _filterLabel(f),
                          dotColor: _filterColor(f),
                          selected: _filter == f,
                          onTap: () => setState(() {
                            _filter = f;
                            _page = 0;
                          }),
                        ),
                    ],
                  );
                  final search = AeSearchBar(
                    controller: _searchCtrl,
                    hint: 'Search room number or type...',
                    onChanged: (_) => setState(() => _page = 0),
                  );
                  if (c.maxWidth < 860) {
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [pills, const SizedBox(height: 12), search],
                    );
                  }
                  return Row(
                    children: [
                      pills,
                      const SizedBox(width: 16),
                      Expanded(child: search),
                    ],
                  );
                },
              ),
              const SizedBox(height: 18),
              AePanelCard(
                title: 'Room List',
                subtitle: widget.slots.isEmpty
                    ? 'Set total rooms to open the room grid.'
                    : 'Room $roomRange · tap a room for details',
                icon: Icons.meeting_room_rounded,
                trailing: AeViewToggle(
                  gridSelected: _gridView,
                  onChanged: (v) => setState(() => _gridView = v),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (widget.slots.isEmpty)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        child: AeIllustratedEmpty(
                          imageAsset: _emptyArtAsset,
                          imageHeight: 170,
                          art: AeEmptyArt.bed,
                          title: 'No rooms to display yet.',
                          message:
                              'Enter your total rooms in the card above to open the room grid.',
                        ),
                      )
                    else if (pageSlots.isEmpty)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 12),
                        child: AeIllustratedEmpty(
                          art: AeEmptyArt.bed,
                          title: 'No rooms match this filter.',
                          message: 'Try another status or clear the search.',
                        ),
                      )
                    else if (_gridView)
                      _roomGrid(pageSlots)
                    else
                      _roomList(pageSlots),
                    if (total > _pageSize) ...[
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          IconButton(
                            tooltip: 'Previous',
                            onPressed: page <= 0
                                ? null
                                : () => setState(() => _page = page - 1),
                            icon: const Icon(Icons.chevron_left_rounded),
                          ),
                          Expanded(
                            child: Text(
                              'Showing ${start + 1}–$end of $total',
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
                ),
              ),
              if (widget.slots.isNotEmpty && widget.setupCard != null) ...[
                const SizedBox(height: 18),
                widget.setupCard!,
              ],
            ],
          ),
        ),
      ],
    );
  }

  static const String _emptyArtAsset = 'assets/images/ae_empty_rooms_bed.png';

  Widget _roomGrid(List<EstablishmentRoomSlot> pageSlots) {
    return LayoutBuilder(
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
    );
  }

  Widget _roomList(List<EstablishmentRoomSlot> pageSlots) {
    return Column(
      children: [
        for (var i = 0; i < pageSlots.length; i++) ...[
          if (i > 0) const Divider(height: 1, color: AeDashTokens.softBorder),
          _roomListRow(pageSlots[i]),
        ],
      ],
    );
  }

  Widget _roomListRow(EstablishmentRoomSlot slot) {
    final (label, color) = slot.isOccupied
        ? ('Occupied', const Color(0xFFDC2626))
        : slot.isDisabled
        ? ('Disabled', const Color(0xFFEA580C))
        : ('Free', const Color(0xFF16A34A));
    final type = slot.info.type.trim();
    final detail = slot.isOccupied && slot.stay != null
        ? slot.stay!.touristName
        : [
            if (type.isNotEmpty) type,
            if (slot.info.hasDetails) slot.info.capacityLabel,
          ].join(' · ');
    return InkWell(
      onTap: () => _openRoom(slot),
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 12),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(11),
              ),
              child: Icon(Icons.bed_rounded, color: color, size: 20),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(slot.label, style: AeDashTokens.section(size: 14)),
                  Text(
                    detail.isEmpty ? 'No details yet' : detail,
                    style: AeDashTokens.body(size: 12),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                label,
                style: AeDashTokens.body(
                  size: 11.5,
                  color: color,
                  weight: FontWeight.w700,
                ),
              ),
            ),
            if (!_editMode && !slot.isOccupied) ...[
              const SizedBox(width: 6),
              TextButton(
                onPressed: () =>
                    widget.onToggleDisabled(slot, !slot.isDisabled),
                child: Text(slot.isDisabled ? 'Enable' : 'Disable'),
              ),
            ] else
              const Icon(
                Icons.chevron_right_rounded,
                color: AeDashTokens.muted,
              ),
          ],
        ),
      ),
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

  Color? _filterColor(_RoomFilter f) {
    switch (f) {
      case _RoomFilter.all:
        return null;
      case _RoomFilter.occupied:
        return const Color(0xFFDC2626);
      case _RoomFilter.free:
        return const Color(0xFF16A34A);
      case _RoomFilter.disabled:
        return const Color(0xFFEA580C);
    }
  }

  Widget _statsRow(EstablishmentRoomStats stats) {
    return AeResponsiveGrid(
      minItemWidth: 150,
      children: [
        AeStatCard(
          label: 'Total',
          value: '${stats.total}',
          icon: Icons.bed_rounded,
          cornerIcon: Icons.grid_view_rounded,
          color: AeDashTokens.accent,
        ),
        AeStatCard(
          label: 'Occupied',
          value: '${stats.occupied}',
          icon: Icons.person_rounded,
          cornerIcon: Icons.lock_rounded,
          color: const Color(0xFFE11D48),
        ),
        AeStatCard(
          label: 'Free',
          value: '${stats.free}',
          icon: Icons.check_circle_rounded,
          cornerIcon: Icons.lock_open_rounded,
          color: AeDashTokens.success,
        ),
        AeStatCard(
          label: 'Disabled',
          value: '${stats.disabled}',
          icon: Icons.block_rounded,
          cornerIcon: Icons.do_not_disturb_on_rounded,
          color: AeDashTokens.warning,
        ),
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
    final exists = _inclusions.any((e) => e.toLowerCase() == raw.toLowerCase());
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
    if (!widget.editable) return _buildReadOnly(context);
    return AlertDialog(
      title: Text(
        widget.editable ? 'Edit ${widget.slot.label}' : widget.slot.label,
      ),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(
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
                        labelText: 'Price per night (₱)',
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
                                (e) => e.toLowerCase() == custom.toLowerCase(),
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

  Widget _buildReadOnly(BuildContext context) {
    final slot = widget.slot;
    final info = slot.info;
    final notes = info.notes.trim();
    final hasCapacity = info.capacityMin > 0 || info.capacityMax > 0;
    final hasPrice = info.pricePerNight > 0;
    final (statusLabel, statusColor, headerIcon) = slot.isOccupied
        ? ('Occupied', AeDashTokens.danger, Icons.hotel_rounded)
        : slot.isDisabled
        ? ('Disabled', const Color(0xFFEA580C), Icons.block_rounded)
        : ('Free', AeDashTokens.success, Icons.king_bed_rounded);

    return Dialog(
      backgroundColor: AeDashTokens.background,
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      clipBehavior: Clip.antiAlias,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 440),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _RoomDialogHeader(
                label: slot.label,
                info: info,
                statusLabel: statusLabel,
                statusColor: statusColor,
                icon: headerIcon,
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 16, 18, 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (slot.isDisabled) ...[
                      _banner(
                        icon: Icons.back_hand_outlined,
                        text: 'This room is disabled and won’t be offered to '
                            'guests. Hold its tile for 3 seconds to enable it.',
                        fg: const Color(0xFF9A3412),
                        bg: const Color(0xFFFFF7ED),
                        border: const Color(0xFFFED7AA),
                      ),
                      const SizedBox(height: 10),
                    ] else if (slot.isFree) ...[
                      _banner(
                        icon: Icons.check_circle_outline_rounded,
                        text: 'Ready for guests — it can be assigned when '
                            'confirming a stay.',
                        fg: const Color(0xFF15803D),
                        bg: const Color(0xFFF0FDF4),
                        border: const Color(0xFFBBF7D0),
                      ),
                      const SizedBox(height: 10),
                    ],
                    Row(
                      children: [
                        Expanded(
                          child: _RoomInfoTile(
                            icon: Icons.bed_rounded,
                            label: 'Type',
                            value: info.type.isEmpty ? 'Not set' : info.type,
                            missing: info.type.isEmpty,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: _RoomInfoTile(
                            icon: Icons.groups_rounded,
                            label: 'Capacity',
                            value: hasCapacity
                                ? info.capacityLabel.replaceFirst('Good for ', '')
                                : 'Not set',
                            missing: !hasCapacity,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    _RoomInfoTile(
                      icon: Icons.payments_outlined,
                      label: 'Price',
                      value: hasPrice ? info.priceLabel : 'Not set',
                      missing: !hasPrice,
                    ),
                    const SizedBox(height: 10),
                    _buildInclusionsCard(info.inclusions),
                    if (notes.isNotEmpty) ...[
                      const SizedBox(height: 10),
                      _RoomInfoTile(
                        icon: Icons.sticky_note_2_outlined,
                        label: 'Notes',
                        value: notes,
                      ),
                    ],
                    if (!info.hasDetails) ...[
                      const SizedBox(height: 10),
                      _banner(
                        icon: Icons.lightbulb_outline_rounded,
                        text: 'No room details yet. Tap Edit rooms on the '
                            'Rooms tab to add type, capacity, price and '
                            'inclusions.',
                        fg: AeDashTokens.info,
                        bg: const Color(0xFFF0F9FF),
                        border: const Color(0xFFBAE6FD),
                      ),
                    ],
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 16, 18, 18),
                child: FilledButton(
                  onPressed: () => Navigator.pop(context),
                  style: FilledButton.styleFrom(
                    backgroundColor: AppTheme.brandOrange,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    textStyle: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                  child: const Text('Done'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildInclusionsCard(List<String> inclusions) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: AeDashTokens.cardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: inclusions.isEmpty
                      ? AeDashTokens.mutedSurface
                      : AeDashTokens.softOrange,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  Icons.checklist_rounded,
                  size: 18,
                  color: inclusions.isEmpty
                      ? AeDashTokens.muted
                      : AppTheme.brandOrangeDark,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Inclusions',
                  style: AeDashTokens.body(size: 11.5, color: AeDashTokens.muted),
                ),
              ),
              if (inclusions.isNotEmpty)
                Text(
                  '${inclusions.length}',
                  style: AeDashTokens.sectionTitle(
                    size: 13,
                    color: AppTheme.brandOrangeDark,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 10),
          if (inclusions.isEmpty)
            Text(
              'None listed',
              style: AeDashTokens.body(size: 14, color: AeDashTokens.muted)
                  .copyWith(fontStyle: FontStyle.italic),
            )
          else
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final inc in inclusions)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 5,
                    ),
                    decoration: BoxDecoration(
                      color: AeDashTokens.cream,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: const Color(0xFFFED7AA)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.check_rounded,
                          size: 13,
                          color: AppTheme.brandOrangeDark,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          inc,
                          style: AeDashTokens.body(
                            size: 12,
                            color: AeDashTokens.text,
                          ).copyWith(fontWeight: FontWeight.w600),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
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
              style: AeDashTokens.body(size: 12.5, color: fg)
                  .copyWith(height: 1.4),
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
    // Unwrap cancelled: tape is fully wound again — fade it off.
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

  (IconData, String, Color?)? _footerText(int? days) {
    final slot = widget.slot;
    final info = slot.info;
    if (widget.editMode) return (Icons.touch_app_outlined, 'Tap to edit', null);
    if (slot.isDisabled) return (Icons.back_hand_outlined, 'Hold to enable', null);
    if (slot.isOccupied) {
      if (days == null) return (Icons.person_outline_rounded, 'In use', null);
      if (days <= 0) {
        return (Icons.logout_rounded, 'Out today', const Color(0xFFB45309));
      }
      return (
        Icons.logout_rounded,
        days == 1 ? 'Out tomorrow' : 'Out in $days days',
        null,
      );
    }
    if (info.pricePerNight > 0) {
      final whole = info.pricePerNight == info.pricePerNight.roundToDouble();
      final n = info.pricePerNight.toStringAsFixed(whole ? 0 : 2);
      return (Icons.sell_outlined, '₱$n / night', null);
    }
    if (info.capacityMin > 0 || info.capacityMax > 0) {
      return (Icons.people_outline_rounded, info.capacityLabel, null);
    }
    return (Icons.check_rounded, 'Ready', null);
  }

  Widget _pill(String label, Color color, {IconData? icon}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null)
            Icon(icon, size: 11, color: color)
          else
            Container(
              width: 6,
              height: 6,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            ),
          const SizedBox(width: 4),
          Text(
            label,
            style: AeDashTokens.body(size: 10.5, color: color)
                .copyWith(fontWeight: FontWeight.w800),
          ),
        ],
      ),
    );
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
            final hoverScale = reduceMotion
                ? 1.0
                : 1.0 + (0.04 * _floatCtrl.value);
            final settle = reduceMotion
                ? 1.0
                : 1 + 0.045 * math.sin(_splashCtrl.value * math.pi);
            final glow = _hover || _holding || widget.editMode;
            final restingDisabled =
                widget.slot.isDisabled &&
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
            final showsDisabled = !widget.editMode &&
                (widget.slot.isDisabled || (_wrapping && tapeT > 0.35));
            final ink = widget.slot.isDisabled && !widget.editMode
                ? const Color(0xFFC2410C)
                : color;
            final tint = widget.editMode
                ? const Color(0xFFFFF7ED)
                : widget.slot.isDisabled
                ? const Color(0xFFFFF1E8)
                : widget.slot.isOccupied
                ? const Color(0xFFFEF2F2)
                : const Color(0xFFF0FDF4);
            final statusLabel = widget.editMode
                ? 'Edit'
                : showsDisabled
                ? 'Disabled'
                : widget.slot.isOccupied
                ? 'Occupied'
                : 'Free';
            final roomIcon = widget.editMode
                ? Icons.edit_note_rounded
                : showsDisabled
                ? Icons.block_rounded
                : widget.slot.isOccupied
                ? Icons.hotel_rounded
                : Icons.king_bed_outlined;
            final footer = _footerText(days);
            final detailsOpacity = (1 - tapeT * 1.6).clamp(0.0, 1.0);

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
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: widget.slot.isDisabled && !widget.editMode
                              ? [tint, tint]
                              : [tint, Colors.white],
                        ),
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(
                          color: color.withValues(alpha: glow ? 0.9 : 0.28),
                          width: glow ? 2 : 1.2,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: glow
                                ? color.withValues(alpha: 0.25)
                                : const Color(0xFF0F172A)
                                    .withValues(alpha: 0.05),
                            blurRadius: glow ? 18 : 12,
                            offset: Offset(0, glow ? 8 : 4),
                          ),
                        ],
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(16),
                        child: Stack(
                          children: [
                            Positioned(
                              top: 0,
                              left: 0,
                              right: 0,
                              child: Container(height: 4, color: color),
                            ),
                            if (showTape)
                              Positioned.fill(
                                child: CustomPaint(
                                  painter: _RoomTapePainter(
                                    progress: tapeT,
                                    opacity: tapeOpacity,
                                  ),
                                ),
                              ),
                            LayoutBuilder(
                              builder: (context, box) {
                                final h = box.maxHeight;
                                final showRoomLabel = h >= 140;
                                final showType = h >= 120 &&
                                    type.isNotEmpty &&
                                    !widget.editMode;
                                final showFooter = h >= 104 && footer != null;
                                return Padding(
                                  padding: const EdgeInsets.fromLTRB(
                                    10,
                                    12,
                                    10,
                                    10,
                                  ),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.stretch,
                                    children: [
                                      Row(
                                        children: [
                                          Container(
                                            width: 28,
                                            height: 28,
                                            decoration: BoxDecoration(
                                              color: color.withValues(
                                                alpha: 0.12,
                                              ),
                                              borderRadius:
                                                  BorderRadius.circular(9),
                                            ),
                                            child: Icon(
                                              roomIcon,
                                              size: 16,
                                              color: ink,
                                            ),
                                          ),
                                          const Spacer(),
                                          _holding
                                              ? _pill(
                                                  '${(3 - (_holdCtrl.value * 3)).ceil().clamp(1, 3)}s',
                                                  ink,
                                                  icon: Icons.timer_outlined,
                                                )
                                              : _pill(statusLabel, ink),
                                        ],
                                      ),
                                      Expanded(
                                        child: Center(
                                          child: FittedBox(
                                            fit: BoxFit.scaleDown,
                                            child: Column(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                if (showRoomLabel)
                                                  Opacity(
                                                    opacity: detailsOpacity,
                                                    child: Text(
                                                      'ROOM',
                                                      style: AeDashTokens.body(
                                                        size: 9.5,
                                                        color:
                                                            AeDashTokens.muted,
                                                      ).copyWith(
                                                        fontWeight:
                                                            FontWeight.w700,
                                                        letterSpacing: 1.2,
                                                      ),
                                                    ),
                                                  ),
                                                Transform.translate(
                                                  offset: Offset(
                                                    0,
                                                    -14 * tapeT,
                                                  ),
                                                  child: Text(
                                                    widget.slot.id,
                                                    style: AeDashTokens.number(
                                                      size: 28,
                                                      color: showsDisabled
                                                          ? ink
                                                          : AeDashTokens.text,
                                                    ),
                                                  ),
                                                ),
                                                if (showType)
                                                  Opacity(
                                                    opacity: detailsOpacity,
                                                    child: ConstrainedBox(
                                                      constraints:
                                                          BoxConstraints(
                                                        maxWidth:
                                                            box.maxWidth - 20,
                                                      ),
                                                      child: Text(
                                                        type,
                                                        maxLines: 1,
                                                        overflow: TextOverflow
                                                            .ellipsis,
                                                        style:
                                                            AeDashTokens.body(
                                                          size: 11,
                                                          color: AeDashTokens
                                                              .muted,
                                                        ),
                                                      ),
                                                    ),
                                                  ),
                                              ],
                                            ),
                                          ),
                                        ),
                                      ),
                                      if (showFooter)
                                        Opacity(
                                          opacity: detailsOpacity,
                                          child: Row(
                                            mainAxisAlignment:
                                                MainAxisAlignment.center,
                                            children: [
                                              Icon(
                                                footer.$1,
                                                size: 13,
                                                color: footer.$3 ?? ink,
                                              ),
                                              const SizedBox(width: 4),
                                              Flexible(
                                                child: Text(
                                                  footer.$2,
                                                  maxLines: 1,
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                  style: AeDashTokens.body(
                                                    size: 11,
                                                    color: footer.$3 ?? ink,
                                                  ).copyWith(
                                                    fontWeight:
                                                        FontWeight.w700,
                                                  ),
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                    ],
                                  ),
                                );
                              },
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
  const _RoomTapePainter({required this.progress, required this.opacity});

  final double progress;
  final double opacity;

  @override
  void paint(Canvas canvas, Size size) {
    if (progress <= 0.001 || opacity <= 0.01 || size.isEmpty) return;
    canvas.save();
    canvas.clipRRect(
      RRect.fromRectAndRadius(Offset.zero & size, const Radius.circular(16)),
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
          'Guest names are hidden by default. Reveal this booking’s guest name?',
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
    final nights = stay.nightsStayed;
    final dueToday = days != null && days <= 0;
    final notes = stay.notes.trim();
    final initials = name
        .trim()
        .split(RegExp(r'\s+'))
        .take(2)
        .map((p) => p.isEmpty ? '' : p[0].toUpperCase())
        .join();

    return Dialog(
      backgroundColor: AeDashTokens.background,
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      clipBehavior: Clip.antiAlias,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 440),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildHeader(info),
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 16, 18, 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _buildGuestCard(name, initials),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: _statTile(
                            icon: Icons.groups_rounded,
                            label: 'Party size',
                            value: '${stay.partySize}',
                            caption: stay.partySize == 1 ? 'guest' : 'guests',
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: _statTile(
                            icon: Icons.bedtime_rounded,
                            label: 'Nights',
                            value: nights == null ? '—' : '$nights',
                            caption: nights == 1 ? 'night' : 'nights',
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    _buildCheckoutTile(checkout, days, dueToday),
                    if (notes.isNotEmpty) ...[
                      const SizedBox(height: 10),
                      _buildNotes(notes),
                    ],
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 16, 18, 18),
                child: FilledButton(
                  onPressed: () => Navigator.pop(context),
                  style: FilledButton.styleFrom(
                    backgroundColor: AppTheme.brandOrange,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    textStyle: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                  child: const Text('Done'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(EstablishmentRoomInfo info) {
    return _RoomDialogHeader(
      label: widget.slot.label,
      info: info,
      statusLabel: 'Occupied',
      statusColor: AeDashTokens.danger,
    );
  }

  Widget _buildGuestCard(String name, String initials) {
    final nameStyle = AeDashTokens.sectionTitle(size: 16);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: AeDashTokens.cardDecoration(),
      child: Row(
        children: [
          Container(
            width: 46,
            height: 46,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: _revealed
                  ? AeDashTokens.softOrange
                  : AeDashTokens.mutedSurface,
              shape: BoxShape.circle,
            ),
            child: _revealed
                ? Text(
                    initials.isEmpty ? 'T' : initials,
                    style: AeDashTokens.sectionTitle(
                      size: 16,
                      color: AppTheme.brandOrangeDark,
                    ),
                  )
                : const Icon(
                    Icons.lock_outline_rounded,
                    size: 22,
                    color: AeDashTokens.muted,
                  ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'GUEST',
                  style: AeDashTokens.body(size: 11, color: AeDashTokens.muted)
                      .copyWith(
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.8,
                      ),
                ),
                const SizedBox(height: 2),
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 250),
                  child: _revealed
                      ? Text(
                          name,
                          key: const ValueKey('shown'),
                          style: nameStyle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        )
                      : ClipRect(
                          key: const ValueKey('hidden'),
                          child: ImageFiltered(
                            imageFilter: ImageFilter.blur(sigmaX: 7, sigmaY: 7),
                            child: Text(
                              name,
                              style: nameStyle,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ),
                ),
              ],
            ),
          ),
          if (!_revealed)
            OutlinedButton.icon(
              onPressed: _askReveal,
              icon: const Icon(Icons.visibility_outlined, size: 17),
              label: const Text('Reveal'),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppTheme.brandOrangeDark,
                side: BorderSide(
                  color: AppTheme.brandOrange.withValues(alpha: 0.5),
                ),
                visualDensity: VisualDensity.compact,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
            )
          else
            const Icon(
              Icons.verified_user_outlined,
              size: 20,
              color: AeDashTokens.success,
            ),
        ],
      ),
    );
  }

  Widget _statTile({
    required IconData icon,
    required String label,
    required String value,
    required String caption,
  }) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: AeDashTokens.cardDecoration(),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: AeDashTokens.softOrange,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, size: 18, color: AppTheme.brandOrangeDark),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: AeDashTokens.body(size: 11.5, color: AeDashTokens.muted),
                ),
                Text.rich(
                  TextSpan(
                    children: [
                      TextSpan(
                        text: value,
                        style: AeDashTokens.heading(size: 20),
                      ),
                      TextSpan(
                        text: ' $caption',
                        style: AeDashTokens.body(
                          size: 12,
                          color: AeDashTokens.muted,
                        ),
                      ),
                    ],
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCheckoutTile(DateTime? checkout, int? days, bool dueToday) {
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    final dateLabel = checkout == null
        ? 'Not set'
        : '${months[checkout.month - 1]} ${checkout.day}, ${checkout.year}';
    final badge = days == null
        ? null
        : dueToday
            ? 'Due today'
            : days == 1
                ? 'Tomorrow'
                : 'In $days days';
    final badgeFg = dueToday ? const Color(0xFFB45309) : AeDashTokens.info;
    final badgeBg = dueToday ? const Color(0xFFFEF3C7) : const Color(0xFFE0F2FE);

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: AeDashTokens.cardDecoration(),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: AeDashTokens.softOrange,
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(
              Icons.event_available_rounded,
              size: 18,
              color: AppTheme.brandOrangeDark,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Checkout',
                  style: AeDashTokens.body(size: 11.5, color: AeDashTokens.muted),
                ),
                Text(dateLabel, style: AeDashTokens.sectionTitle(size: 15)),
              ],
            ),
          ),
          if (badge != null)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: badgeBg,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                badge,
                style: AeDashTokens.body(size: 12, color: badgeFg)
                    .copyWith(fontWeight: FontWeight.w800),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildNotes(String notes) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AeDashTokens.cream,
        borderRadius: BorderRadius.circular(AeDashTokens.radius),
        border: Border.all(color: const Color(0xFFFED7AA)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(
            Icons.sticky_note_2_outlined,
            size: 18,
            color: AppTheme.brandOrangeDark,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Notes',
                  style: AeDashTokens.body(size: 11.5, color: AeDashTokens.muted),
                ),
                const SizedBox(height: 2),
                Text(
                  notes,
                  style: AeDashTokens.body(size: 13.5, color: AeDashTokens.text)
                      .copyWith(height: 1.4),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Orange gradient header shared by the room detail dialogs.
class _RoomDialogHeader extends StatelessWidget {
  const _RoomDialogHeader({
    required this.label,
    required this.info,
    required this.statusLabel,
    required this.statusColor,
    this.icon = Icons.king_bed_rounded,
  });

  final String label;
  final EstablishmentRoomInfo info;
  final String statusLabel;
  final Color statusColor;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final details = [
      if (info.type.isNotEmpty) info.type,
      if (info.capacityMin > 0 || info.capacityMax > 0) info.capacityLabel,
      if (info.pricePerNight > 0) info.priceLabel,
    ].join(' · ');

    return Container(
      padding: const EdgeInsets.fromLTRB(18, 18, 8, 18),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFFB923C), Color(0xFFEA580C)],
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 50,
            height: 50,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.white.withValues(alpha: 0.35)),
            ),
            child: Icon(icon, color: Colors.white, size: 28),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: AeDashTokens.heading(size: 22, color: Colors.white),
                ),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 9,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 7,
                            height: 7,
                            decoration: BoxDecoration(
                              color: statusColor,
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 5),
                          Text(
                            statusLabel,
                            style: AeDashTokens.body(
                              size: 11.5,
                              color: statusColor,
                            ).copyWith(fontWeight: FontWeight.w800),
                          ),
                        ],
                      ),
                    ),
                    if (details.isNotEmpty)
                      Text(
                        details,
                        style: AeDashTokens.body(
                          size: 12.5,
                          color: Colors.white.withValues(alpha: 0.92),
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: () => Navigator.pop(context),
            tooltip: 'Close',
            icon: const Icon(Icons.close_rounded, color: Colors.white),
          ),
        ],
      ),
    );
  }
}

/// White card: tinted icon, small label, value (muted when not set).
class _RoomInfoTile extends StatelessWidget {
  const _RoomInfoTile({
    required this.icon,
    required this.label,
    required this.value,
    this.missing = false,
  });

  final IconData icon;
  final String label;
  final String value;
  final bool missing;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: AeDashTokens.cardDecoration(),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: missing ? AeDashTokens.mutedSurface : AeDashTokens.softOrange,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              icon,
              size: 18,
              color: missing ? AeDashTokens.muted : AppTheme.brandOrangeDark,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: AeDashTokens.body(size: 11.5, color: AeDashTokens.muted),
                ),
                Text(
                  value,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: missing
                      ? AeDashTokens.body(size: 14, color: AeDashTokens.muted)
                          .copyWith(fontStyle: FontStyle.italic)
                      : AeDashTokens.sectionTitle(size: 15),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

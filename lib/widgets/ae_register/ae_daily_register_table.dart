import 'package:flutter/material.dart';

import 'package:atmos_trs_system/config/ae_register_schema.dart';
import 'package:atmos_trs_system/models/ae_register.dart';
import 'package:atmos_trs_system/utils/ae_register_calculator.dart';
import 'package:atmos_trs_system/widgets/ae_register/ae_sheet_kit.dart';
import 'package:atmos_trs_system/widgets/establishment_dash_tokens.dart';

/// DailyRecord sheet: one line per register row with sales + sex validation.
class AeDailyRegisterTable extends StatefulWidget {
  const AeDailyRegisterTable({
    super.key,
    required this.rows,
    required this.schema,
    required this.issues,
    required this.showCharges,
    required this.readOnly,
    this.onEdit,
    this.onDelete,
    this.onDuplicateNext,
  });

  final List<AeRegisterRow> rows;
  final AeRegisterSchema schema;
  final List<AeRegisterIssue> issues;
  final bool showCharges;
  final bool readOnly;
  final ValueChanged<AeRegisterRow>? onEdit;
  final ValueChanged<AeRegisterRow>? onDelete;
  final ValueChanged<AeRegisterRow>? onDuplicateNext;

  @override
  State<AeDailyRegisterTable> createState() => _AeDailyRegisterTableState();
}

class _AeDailyRegisterTableState extends State<AeDailyRegisterTable> {
  int? _dayFilter;
  AeDailyRegisterSort _sort = AeDailyRegisterSort.newestDate;
  final _hScroll = ScrollController();
  final _vScroll = ScrollController();

  static const _peachHeader = Color(0xFFFFF1E7);
  static const _rowAlt = Color(0xFFF8FAFC);
  static const _totalFill = Color(0xFFFFF7ED);

  @override
  void dispose() {
    _hScroll.dispose();
    _vScroll.dispose();
    super.dispose();
  }

  String _peso(double v) {
    final m = AeSheetKit.money(v);
    if (m == '-') return '₱0.00';
    return '₱$m';
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.schema;
    final issuesByRow = <String, List<String>>{};
    for (final i in widget.issues) {
      if (i.rowId.isEmpty) continue;
      issuesByRow.putIfAbsent(i.rowId, () => []).add(i.message);
    }
    final days = {for (final r in widget.rows) r.day}.toList()
      ..sort((a, b) => b.compareTo(a));
    final filtered = _dayFilter == null
        ? widget.rows
        : widget.rows.where((r) => r.day == _dayFilter).toList();
    final visible = AeRegisterCalculator.sortDailyRegisterRows(
      filtered,
      sort: _sort,
    );

    final cols = <(String, double, TextAlign)>[
      ('#', 44, TextAlign.center),
      ('Date', 100, TextAlign.center),
      if (s.tracksRooms) ('Room', 72, TextAlign.center),
      ('Residence / Nationality', 210, TextAlign.left),
      if (s.has(AeRegisterColumn.phRegion)) ('PH origin', 160, TextAlign.left),
      (s.guestsLabel, 96, TextAlign.center),
      if (s.tracksNights) ('Checked-in day', 108, TextAlign.center),
      (s.rateLabel, 112, TextAlign.center),
      if (widget.showCharges && s.has(AeRegisterColumn.chargesA))
        ('Charges (A)', 100, TextAlign.center),
      if (widget.showCharges && s.has(AeRegisterColumn.chargesB))
        ('Charges (B)', 100, TextAlign.center),
      if (widget.showCharges) ('Subtotal', 108, TextAlign.center),
      ('Female', 68, TextAlign.center),
      ('Male', 68, TextAlign.center),
      ('Validation', 110, TextAlign.center),
      ('Encoded by', 170, TextAlign.left),
      if (!widget.readOnly) ('Actions', 118, TextAlign.center),
    ];
    final tableWidth = cols.fold<double>(0, (w, c) => w + c.$2);
    final head = AeSheetKit.cell(size: 11.5, weight: FontWeight.w800);

    double sum(double Function(AeRegisterRow r) f) =>
        visible.fold<double>(0, (t, r) => t + f(r));

    final screenH = MediaQuery.sizeOf(context).height;
    final tableBodyMaxH = (screenH * 0.48).clamp(280.0, 520.0);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AeDashTokens.border),
            boxShadow: AeDashTokens.cardShadow,
          ),
          child: Wrap(
            spacing: 10,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(
                '${visible.length} of ${widget.rows.length} rows',
                style: AeDashTokens.body(size: 12.5, weight: FontWeight.w700, color: AeDashTokens.text),
              ),
              _filterChip(
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<int?>(
                    value: _dayFilter,
                    isDense: true,
                    hint: const Text('All days'),
                    items: [
                      const DropdownMenuItem<int?>(value: null, child: Text('All days')),
                      for (final d in days)
                        DropdownMenuItem<int?>(value: d, child: Text('Day $d')),
                    ],
                    onChanged: (v) => setState(() => _dayFilter = v),
                  ),
                ),
              ),
              _filterChip(
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<AeDailyRegisterSort>(
                    value: _sort,
                    isDense: true,
                    items: const [
                      DropdownMenuItem(
                        value: AeDailyRegisterSort.newestDate,
                        child: Text('Newest date first'),
                      ),
                      DropdownMenuItem(
                        value: AeDailyRegisterSort.oldestDate,
                        child: Text('Oldest date first'),
                      ),
                      DropdownMenuItem(
                        value: AeDailyRegisterSort.recentlyAdded,
                        child: Text('Recently added'),
                      ),
                      DropdownMenuItem(
                        value: AeDailyRegisterSort.recentlyUpdated,
                        child: Text('Recently updated'),
                      ),
                    ],
                    onChanged: (v) {
                      if (v == null) return;
                      setState(() => _sort = v);
                    },
                  ),
                ),
              ),
              if (widget.issues.isNotEmpty)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFEF2F2),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: const Color(0xFFFECACA)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.error_outline_rounded, size: 15, color: AeDashTokens.danger),
                      const SizedBox(width: 5),
                      Text(
                        '${widget.issues.length} validation issue(s)',
                        style: AeDashTokens.body(
                          size: 12,
                          color: AeDashTokens.danger,
                          weight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            boxShadow: AeDashTokens.softShadow,
          ),
          child: Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0xFFE2E8F0)),
            ),
            clipBehavior: Clip.antiAlias,
            child: Scrollbar(
              controller: _hScroll,
              thumbVisibility: true,
              notificationPredicate: (n) => n.metrics.axis == Axis.horizontal,
              child: SingleChildScrollView(
                controller: _hScroll,
                scrollDirection: Axis.horizontal,
                child: SizedBox(
                  width: tableWidth,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Sticky header (fixed while body scrolls vertically).
                      Row(children: [
                        for (final c in cols)
                          AeCell(
                            c.$1 == 'Actions' ? 'Actions' : c.$1,
                            width: c.$2,
                            align: TextAlign.center,
                            fill: _peachHeader,
                            style: head,
                            height: 40,
                          ),
                      ]),
                      ConstrainedBox(
                        constraints: BoxConstraints(maxHeight: tableBodyMaxH),
                        child: Scrollbar(
                          controller: _vScroll,
                          thumbVisibility: visible.length > 8,
                          child: SingleChildScrollView(
                            controller: _vScroll,
                            child: Column(
                              children: [
                                if (visible.isEmpty)
                                  SizedBox(
                                    width: tableWidth,
                                    height: 88,
                                    child: Center(
                                      child: Text(
                                        widget.readOnly
                                            ? 'No register rows for this month.'
                                            : 'No rows yet — use "Add Stay" to record guests (${s.rowNoun} per row).',
                                        style: AeDashTokens.body(size: 12.5),
                                      ),
                                    ),
                                  ),
                                for (var i = 0; i < visible.length; i++)
                                  _row(i, visible[i], issuesByRow[visible[i].id], cols),
                                if (visible.isNotEmpty)
                                  Row(children: [
                                    for (final c in cols)
                                      switch (c.$1) {
                                        '#' => AeCell('', width: c.$2, fill: _totalFill, height: 36),
                                        'Date' => AeCell(
                                            'TOTAL',
                                            width: c.$2,
                                            align: TextAlign.center,
                                            fill: _totalFill,
                                            style: head,
                                            height: 36,
                                          ),
                                        final l when l == s.guestsLabel => AeCell(
                                            '${sum((r) => r.guests.toDouble()).round()}',
                                            width: c.$2,
                                            align: TextAlign.center,
                                            fill: _totalFill,
                                            style: head,
                                            height: 36,
                                          ),
                                        final l when l == s.rateLabel => AeCell(
                                            _peso(sum((r) => r.rate)),
                                            width: c.$2,
                                            align: TextAlign.center,
                                            fill: _totalFill,
                                            style: head,
                                            height: 36,
                                          ),
                                        'Charges (A)' => AeCell(
                                            _peso(sum((r) => r.chargesA)),
                                            width: c.$2,
                                            align: TextAlign.center,
                                            fill: _totalFill,
                                            style: head,
                                            height: 36,
                                          ),
                                        'Charges (B)' => AeCell(
                                            _peso(sum((r) => r.chargesB)),
                                            width: c.$2,
                                            align: TextAlign.center,
                                            fill: _totalFill,
                                            style: head,
                                            height: 36,
                                          ),
                                        'Subtotal' => AeCell(
                                            _peso(sum((r) => r.subtotal)),
                                            width: c.$2,
                                            align: TextAlign.center,
                                            fill: _totalFill,
                                            style: head,
                                            height: 36,
                                          ),
                                        'Female' => AeCell(
                                            '${sum((r) => r.female.toDouble()).round()}',
                                            width: c.$2,
                                            align: TextAlign.center,
                                            fill: _totalFill,
                                            style: head,
                                            height: 36,
                                          ),
                                        'Male' => AeCell(
                                            '${sum((r) => r.male.toDouble()).round()}',
                                            width: c.$2,
                                            align: TextAlign.center,
                                            fill: _totalFill,
                                            style: head,
                                            height: 36,
                                          ),
                                        _ => AeCell('', width: c.$2, fill: _totalFill, height: 36),
                                      },
                                  ]),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _filterChip({required Widget child}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AeDashTokens.border),
      ),
      child: child,
    );
  }

  Widget _row(
    int index,
    AeRegisterRow r,
    List<String>? issues,
    List<(String, double, TextAlign)> cols,
  ) {
    final s = widget.schema;
    final ok = r.female + r.male == r.guests;
    final hasIssue = issues != null && issues.isNotEmpty;
    final fill = hasIssue
        ? const Color(0xFFFEF2F2)
        : (index.isEven ? Colors.white : _rowAlt);
    final cells = <Widget>[];
    for (final c in cols) {
      final w = c.$2;
      final a = c.$3;
      switch (c.$1) {
        case '#':
          cells.add(AeCell(
            '${index + 1}',
            width: w,
            align: a,
            fill: fill,
            height: 38,
            style: AeSheetKit.cell(color: AeDashTokens.muted),
          ));
        case 'Date':
          cells.add(AeCell(
            AeSheetKit.shortDate(r.date),
            width: w,
            align: TextAlign.center,
            fill: fill,
            height: 38,
          ));
        case 'Room':
          cells.add(AeCell(r.roomNo, width: w, align: a, fill: fill, height: 38));
        case 'Residence / Nationality':
          cells.add(AeCell(r.residence, width: w, fill: fill, height: 38));
        case 'PH origin':
          cells.add(AeCell(
            r.phRegion,
            width: w,
            fill: fill,
            height: 38,
            style: AeSheetKit.cell(color: AeDashTokens.muted),
          ));
        case 'Checked-in day':
          cells.add(AeCell(
            r.checkedInDay ? 'Yes' : 'No',
            width: w,
            align: a,
            fill: fill,
            height: 38,
            style: AeSheetKit.cell(
              weight: r.checkedInDay ? FontWeight.w800 : FontWeight.w500,
              color: r.checkedInDay ? AeDashTokens.success : AeDashTokens.text,
            ),
          ));
        case 'Charges (A)':
          cells.add(AeCell(_peso(r.chargesA), width: w, align: a, fill: fill, height: 38));
        case 'Charges (B)':
          cells.add(AeCell(_peso(r.chargesB), width: w, align: a, fill: fill, height: 38));
        case 'Subtotal':
          cells.add(AeCell(_peso(r.subtotal), width: w, align: a, fill: fill, height: 38));
        case 'Female':
          cells.add(AeCell('${r.female}', width: w, align: a, fill: fill, height: 38));
        case 'Male':
          cells.add(AeCell('${r.male}', width: w, align: a, fill: fill, height: 38));
        case 'Validation':
          cells.add(AeCell(
            '',
            width: w,
            align: a,
            fill: fill,
            height: 38,
            child: Tooltip(
              message: hasIssue ? issues.join('\n') : 'OK',
              child: _validationBadge(hasIssue: hasIssue, ok: ok),
            ),
          ));
        case 'Encoded by':
          final au = r.audit;
          cells.add(AeCell(
            '',
            width: w,
            fill: fill,
            height: 38,
            child: Tooltip(
              message: au.isEmpty
                  ? 'Saved before sign-offs were required'
                  : [
                      '${au.encodedBy} · ${au.encodedPosition}',
                      if (au.createdBy.isNotEmpty && au.createdBy != au.encodedBy)
                        'First entered by ${au.createdBy}',
                    ].join('\n'),
              child: Text(
                au.isEmpty ? '—' : au.encodedBy,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AeSheetKit.cell(
                  color: au.isEmpty ? AeDashTokens.muted : AeDashTokens.text,
                ),
              ),
            ),
          ));
        case 'Actions':
          cells.add(AeCell(
            '',
            width: w,
            align: a,
            fill: fill,
            height: 38,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _icon(Icons.edit_rounded, 'Edit', () => widget.onEdit?.call(r), color: AeDashTokens.accent),
                if (s.tracksNights)
                  _icon(Icons.redo_rounded, 'Copy to next night', () => widget.onDuplicateNext?.call(r)),
                _icon(
                  Icons.delete_outline_rounded,
                  'Delete',
                  () => widget.onDelete?.call(r),
                  color: AeDashTokens.danger,
                ),
              ],
            ),
          ));
        default:
          if (c.$1 == s.guestsLabel) {
            cells.add(AeCell(
              '${r.guests}',
              width: w,
              align: a,
              fill: fill,
              height: 38,
              style: AeSheetKit.cell(weight: FontWeight.w700),
            ));
          } else if (c.$1 == s.rateLabel) {
            cells.add(AeCell(_peso(r.rate), width: w, align: a, fill: fill, height: 38));
          } else {
            cells.add(AeCell('', width: w, fill: fill, height: 38));
          }
      }
    }
    return AeHoverRow(
      child: InkWell(
        onTap: widget.readOnly ? null : () => widget.onEdit?.call(r),
        child: Row(children: cells),
      ),
    );
  }

  Widget _validationBadge({required bool hasIssue, required bool ok}) {
    final bad = hasIssue;
    final bg = bad ? const Color(0xFFFEE2E2) : const Color(0xFFDCFCE7);
    final fg = bad ? const Color(0xFFB91C1C) : const Color(0xFF15803D);
    final label = bad ? (ok ? 'Check' : 'Error') : 'OK';
    final icon = bad ? Icons.error_rounded : Icons.check_circle_rounded;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: fg.withValues(alpha: 0.22)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: fg),
          const SizedBox(width: 4),
          Text(
            label,
            style: AeSheetKit.cell(size: 11, color: fg, weight: FontWeight.w800),
          ),
        ],
      ),
    );
  }

  Widget _icon(
    IconData icon,
    String tip,
    VoidCallback onTap, {
    Color color = AeDashTokens.muted,
  }) =>
      IconButton(
        tooltip: tip,
        visualDensity: VisualDensity.compact,
        padding: EdgeInsets.zero,
        constraints: const BoxConstraints(minWidth: 30, minHeight: 30),
        iconSize: 17,
        color: color,
        onPressed: onTap,
        icon: Icon(icon),
      );
}

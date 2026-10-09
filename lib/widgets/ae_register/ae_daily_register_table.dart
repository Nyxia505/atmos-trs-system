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

  @override
  Widget build(BuildContext context) {
    final s = widget.schema;
    final issuesByRow = <String, List<String>>{};
    for (final i in widget.issues) {
      if (i.rowId.isEmpty) continue;
      issuesByRow.putIfAbsent(i.rowId, () => []).add(i.message);
    }
    final days = {for (final r in widget.rows) r.day}.toList()..sort();
    final visible = _dayFilter == null
        ? widget.rows
        : widget.rows.where((r) => r.day == _dayFilter).toList();

    final cols = <(String, double, TextAlign)>[
      ('#', 44, TextAlign.center),
      ('Date', 96, TextAlign.left),
      if (s.tracksRooms) ('Room', 64, TextAlign.center),
      ('Residence / Nationality', 200, TextAlign.left),
      if (s.has(AeRegisterColumn.phRegion)) ('PH origin', 150, TextAlign.left),
      (s.guestsLabel, 84, TextAlign.center),
      if (s.tracksNights) ('Checked-in day', 100, TextAlign.center),
      (s.rateLabel, 100, TextAlign.right),
      if (widget.showCharges && s.has(AeRegisterColumn.chargesA)) ('Charges (A)', 96, TextAlign.right),
      if (widget.showCharges && s.has(AeRegisterColumn.chargesB)) ('Charges (B)', 96, TextAlign.right),
      if (widget.showCharges) ('Subtotal', 100, TextAlign.right),
      ('Female', 64, TextAlign.center),
      ('Male', 64, TextAlign.center),
      ('Validation', 92, TextAlign.center),
      ('Encoded by', 170, TextAlign.left),
      if (!widget.readOnly) ('', 112, TextAlign.center),
    ];
    final tableWidth = cols.fold<double>(0, (w, c) => w + c.$2);

    double sum(double Function(AeRegisterRow r) f) => visible.fold<double>(0, (t, r) => t + f(r));
    final head = AeSheetKit.cell(size: 11.5, weight: FontWeight.w800);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text('${visible.length} of ${widget.rows.length} rows', style: AeDashTokens.body(size: 12)),
            DropdownButton<int?>(
              value: _dayFilter,
              underline: const SizedBox.shrink(),
              hint: const Text('All days'),
              items: [
                const DropdownMenuItem<int?>(value: null, child: Text('All days')),
                for (final d in days) DropdownMenuItem<int?>(value: d, child: Text('Day $d')),
              ],
              onChanged: (v) => setState(() => _dayFilter = v),
            ),
            if (widget.issues.isNotEmpty)
              Chip(
                avatar: const Icon(Icons.error_outline_rounded, size: 16, color: AeDashTokens.danger),
                label: Text('${widget.issues.length} validation issue(s)'),
                backgroundColor: const Color(0xFFFEF2F2),
                side: const BorderSide(color: Color(0xFFFECACA)),
              ),
          ],
        ),
        const SizedBox(height: 8),
        AeSheetFrame(
          minWidth: tableWidth,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                for (final c in cols) AeCell(c.$1, width: c.$2, align: c.$3, fill: AeSheetKit.headerFill, style: head, height: 36),
              ]),
              if (visible.isEmpty)
                SizedBox(
                  width: tableWidth,
                  height: 72,
                  child: Center(
                    child: Text(
                      widget.readOnly
                          ? 'No register rows for this month.'
                          : 'No rows yet — use "Add stay" to record guests (${s.rowNoun} per row).',
                      style: AeDashTokens.body(size: 12.5),
                    ),
                  ),
                ),
              for (var i = 0; i < visible.length; i++) _row(i, visible[i], issuesByRow[visible[i].id], cols),
              if (visible.isNotEmpty)
                Row(children: [
                  for (final c in cols)
                    switch (c.$1) {
                      '#' => AeCell('', width: c.$2, fill: AeSheetKit.headerFill),
                      'Date' => AeCell('TOTAL', width: c.$2, fill: AeSheetKit.headerFill, style: head),
                      final l when l == s.guestsLabel =>
                        AeCell('${sum((r) => r.guests.toDouble()).round()}', width: c.$2, align: c.$3, fill: AeSheetKit.headerFill, style: head),
                      final l when l == s.rateLabel =>
                        AeCell(AeSheetKit.money(sum((r) => r.rate)), width: c.$2, align: c.$3, fill: AeSheetKit.headerFill, style: head),
                      'Charges (A)' =>
                        AeCell(AeSheetKit.money(sum((r) => r.chargesA)), width: c.$2, align: c.$3, fill: AeSheetKit.headerFill, style: head),
                      'Charges (B)' =>
                        AeCell(AeSheetKit.money(sum((r) => r.chargesB)), width: c.$2, align: c.$3, fill: AeSheetKit.headerFill, style: head),
                      'Subtotal' =>
                        AeCell(AeSheetKit.money(sum((r) => r.subtotal)), width: c.$2, align: c.$3, fill: AeSheetKit.headerFill, style: head),
                      'Female' => AeCell('${sum((r) => r.female.toDouble()).round()}', width: c.$2, align: c.$3, fill: AeSheetKit.headerFill, style: head),
                      'Male' => AeCell('${sum((r) => r.male.toDouble()).round()}', width: c.$2, align: c.$3, fill: AeSheetKit.headerFill, style: head),
                      _ => AeCell('', width: c.$2, fill: AeSheetKit.headerFill),
                    },
                ]),
            ],
          ),
        ),
      ],
    );
  }

  Widget _row(int index, AeRegisterRow r, List<String>? issues, List<(String, double, TextAlign)> cols) {
    final s = widget.schema;
    final ok = r.female + r.male == r.guests;
    final hasIssue = issues != null && issues.isNotEmpty;
    final fill = hasIssue ? const Color(0xFFFEF2F2) : (index.isEven ? Colors.white : const Color(0xFFF8FAFC));
    final cells = <Widget>[];
    for (final c in cols) {
      final w = c.$2;
      final a = c.$3;
      switch (c.$1) {
        case '#':
          cells.add(AeCell('${index + 1}', width: w, align: a, fill: fill, style: AeSheetKit.cell(color: AeDashTokens.muted)));
        case 'Date':
          cells.add(AeCell(AeSheetKit.shortDate(r.date), width: w, fill: fill));
        case 'Room':
          cells.add(AeCell(r.roomNo, width: w, align: a, fill: fill));
        case 'Residence / Nationality':
          cells.add(AeCell(r.residence, width: w, fill: fill));
        case 'PH origin':
          cells.add(AeCell(r.phRegion, width: w, fill: fill, style: AeSheetKit.cell(color: AeDashTokens.muted)));
        case 'Checked-in day':
          cells.add(AeCell(
            r.checkedInDay ? 'Yes' : 'No',
            width: w,
            align: a,
            fill: fill,
            style: AeSheetKit.cell(weight: r.checkedInDay ? FontWeight.w800 : FontWeight.w500, color: r.checkedInDay ? AeDashTokens.success : AeDashTokens.text),
          ));
        case 'Charges (A)':
          cells.add(AeCell(AeSheetKit.money(r.chargesA), width: w, align: a, fill: fill));
        case 'Charges (B)':
          cells.add(AeCell(AeSheetKit.money(r.chargesB), width: w, align: a, fill: fill));
        case 'Subtotal':
          cells.add(AeCell(AeSheetKit.money(r.subtotal), width: w, align: a, fill: fill));
        case 'Female':
          cells.add(AeCell('${r.female}', width: w, align: a, fill: fill));
        case 'Male':
          cells.add(AeCell('${r.male}', width: w, align: a, fill: fill));
        case 'Validation':
          cells.add(AeCell(
            '',
            width: w,
            align: a,
            fill: fill,
            child: Tooltip(
              message: hasIssue ? issues.join('\n') : 'OK',
              child: Text(
                hasIssue ? (ok ? 'Check' : 'Error') : 'OK',
                style: AeSheetKit.cell(weight: FontWeight.w800, color: hasIssue ? AeDashTokens.danger : AeDashTokens.success),
              ),
            ),
          ));
        case 'Encoded by':
          final au = r.audit;
          cells.add(AeCell(
            '',
            width: w,
            fill: fill,
            child: Tooltip(
              message: au.isEmpty
                  ? 'Saved before sign-offs were required'
                  : [
                      '${au.encodedBy} · ${au.encodedPosition}',
                      if (au.createdBy.isNotEmpty && au.createdBy != au.encodedBy) 'First entered by ${au.createdBy}',
                    ].join('\n'),
              child: Text(
                au.isEmpty ? '—' : au.encodedBy,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AeSheetKit.cell(color: au.isEmpty ? AeDashTokens.muted : AeDashTokens.text),
              ),
            ),
          ));
        case '':
          cells.add(AeCell(
            '',
            width: w,
            align: a,
            fill: fill,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _icon(Icons.edit_rounded, 'Edit', () => widget.onEdit?.call(r)),
                if (s.tracksNights) _icon(Icons.redo_rounded, 'Copy to next night', () => widget.onDuplicateNext?.call(r)),
                _icon(Icons.delete_outline_rounded, 'Delete', () => widget.onDelete?.call(r), color: AeDashTokens.danger),
              ],
            ),
          ));
        default:
          if (c.$1 == s.guestsLabel) {
            cells.add(AeCell('${r.guests}', width: w, align: a, fill: fill, style: AeSheetKit.cell(weight: FontWeight.w700)));
          } else if (c.$1 == s.rateLabel) {
            cells.add(AeCell(AeSheetKit.money(r.rate), width: w, align: a, fill: fill));
          } else {
            cells.add(AeCell('', width: w, fill: fill));
          }
      }
    }
    return InkWell(
      onTap: widget.readOnly ? null : () => widget.onEdit?.call(r),
      child: Row(children: cells),
    );
  }

  Widget _icon(IconData icon, String tip, VoidCallback onTap, {Color color = AeDashTokens.muted}) => IconButton(
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

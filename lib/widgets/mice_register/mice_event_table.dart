import 'package:flutter/material.dart';

import 'package:atmos_trs_system/models/mice_register.dart';
import 'package:atmos_trs_system/utils/mice_register_calculator.dart';
import 'package:atmos_trs_system/widgets/ae_register/ae_sheet_kit.dart';
import 'package:atmos_trs_system/widgets/establishment_dash_tokens.dart';

/// CUS BY EST sheet: one line per event, CN by date, TOTAL footer.
class MiceEventTable extends StatelessWidget {
  const MiceEventTable({
    super.key,
    required this.events,
    required this.controlNumbers,
    required this.readOnly,
    this.totalCount,
    this.showMonth = false,
    this.onEdit,
    this.onDuplicate,
    this.onDelete,
    this.onOpenMonth,
  });

  /// Visible (filtered + sorted) events.
  final List<MiceEvent> events;

  /// Event id → CN (per venue-month, date order).
  final Map<String, int> controlNumbers;
  final bool readOnly;

  /// Events before filtering (for the "x of y" line).
  final int? totalCount;

  /// Quarter / year roll-ups: rows open their month instead of editing.
  final bool showMonth;
  final ValueChanged<MiceEvent>? onEdit;
  final ValueChanged<MiceEvent>? onDuplicate;
  final ValueChanged<MiceEvent>? onDelete;
  final ValueChanged<MiceEvent>? onOpenMonth;

  @override
  Widget build(BuildContext context) {
    final editable = !readOnly && !showMonth;
    final cols = <(String, double, TextAlign)>[
      ('CN', 48, TextAlign.center),
      ('Date', 118, TextAlign.left),
      ('Event name', 220, TextAlign.left),
      ('Hours', 60, TextAlign.center),
      ('Type of event', 170, TextAlign.left),
      ('Foreign', 66, TextAlign.center),
      ('Local', 66, TextAlign.center),
      ('Total', 66, TextAlign.center),
      ('Male', 60, TextAlign.center),
      ('Female', 64, TextAlign.center),
      ('Exhibitors', 80, TextAlign.center),
      ('Visitors', 72, TextAlign.center),
      ('Organizer, contact & tel. no.', 260, TextAlign.left),
      ('Remarks', 160, TextAlign.left),
      ('Validation', 86, TextAlign.center),
      ('Encoded by', 150, TextAlign.left),
      if (editable) ('', 112, TextAlign.center),
      if (showMonth) ('', 92, TextAlign.center),
    ];
    final width = cols.fold<double>(0, (w, c) => w + c.$2);
    final head = AeSheetKit.cell(size: 11.5, weight: FontWeight.w800);
    final t = MiceRegisterCalculator.totals(events);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (totalCount != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Text('${events.length} of $totalCount event(s)', style: AeDashTokens.body(size: 12)),
          ),
        AeSheetFrame(
          minWidth: width,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                for (final c in cols) AeCell(c.$1, width: c.$2, align: c.$3, fill: AeSheetKit.headerFill, style: head, height: 38),
              ]),
              if (events.isEmpty)
                SizedBox(
                  width: width,
                  height: 72,
                  child: Center(
                    child: Text(
                      readOnly || showMonth
                          ? 'No events in this period.'
                          : 'No events yet — use "Add event" (meetings, weddings, conventions, exhibits…).',
                      style: AeDashTokens.body(size: 12.5),
                    ),
                  ),
                ),
              for (var i = 0; i < events.length; i++) _row(i, events[i], cols),
              if (events.isNotEmpty)
                Row(children: [
                  for (final c in cols)
                    switch (c.$1) {
                      'Date' => AeCell('TOTAL', width: c.$2, fill: AeSheetKit.headerFill, style: head),
                      'Event name' => AeCell('${t.events} event(s)', width: c.$2, fill: AeSheetKit.headerFill, style: head),
                      'Hours' => _foot(MiceRegisterCalculator.hoursLabel(t.hours), c, head),
                      'Foreign' => _foot('${t.foreign}', c, head),
                      'Local' => _foot('${t.local}', c, head),
                      'Total' => _foot('${t.attendees}', c, head),
                      'Male' => _foot('${t.male}', c, head),
                      'Female' => _foot('${t.female}', c, head),
                      'Exhibitors' => _foot(AeSheetKit.int0(t.exhibitors), c, head),
                      'Visitors' => _foot(AeSheetKit.int0(t.exhibitVisitors), c, head),
                      _ => AeCell('', width: c.$2, fill: AeSheetKit.headerFill),
                    },
                ]),
            ],
          ),
        ),
      ],
    );
  }

  Widget _foot(String v, (String, double, TextAlign) c, TextStyle s) =>
      AeCell(v, width: c.$2, align: c.$3, fill: AeSheetKit.headerFill, style: s);

  Widget _row(int index, MiceEvent e, List<(String, double, TextAlign)> cols) {
    final issues = MiceRegisterCalculator.validate(e);
    final warnings = MiceRegisterCalculator.warnings(e);
    final hasIssue = issues.isNotEmpty;
    final fill = hasIssue ? const Color(0xFFFEF2F2) : (index.isEven ? Colors.white : const Color(0xFFF8FAFC));
    final cells = <Widget>[];
    for (final c in cols) {
      final w = c.$2;
      final a = c.$3;
      switch (c.$1) {
        case 'CN':
          cells.add(AeCell('${controlNumbers[e.id] ?? index + 1}', width: w, align: a, fill: fill, style: AeSheetKit.cell(color: AeDashTokens.muted)));
        case 'Date':
          cells.add(AeCell(MiceRegisterCalculator.dateLabel(e), width: w, fill: fill));
        case 'Event name':
          cells.add(AeCell(e.eventName, width: w, fill: fill, style: AeSheetKit.cell(weight: FontWeight.w700)));
        case 'Hours':
          cells.add(AeCell(MiceRegisterCalculator.hoursLabel(e.hours), width: w, align: a, fill: fill));
        case 'Type of event':
          cells.add(AeCell(
            '',
            width: w,
            fill: fill,
            child: Tooltip(
              message: e.category.label,
              child: Row(children: [
                Icon(e.category.icon, size: 14, color: AeDashTokens.accent),
                const SizedBox(width: 5),
                Expanded(child: Text(e.eventType, maxLines: 1, overflow: TextOverflow.ellipsis, style: AeSheetKit.cell())),
              ]),
            ),
          ));
        case 'Foreign':
          cells.add(AeCell(
            '${e.foreign}',
            width: w,
            align: a,
            fill: fill,
            child: e.foreignCountries.isEmpty
                ? null
                : Tooltip(
                    message: e.foreignCountries.entries.map((x) => '${x.key}: ${x.value}').join('\n'),
                    child: Text('${e.foreign}*', style: AeSheetKit.cell(color: AeDashTokens.info, weight: FontWeight.w700)),
                  ),
          ));
        case 'Local':
          cells.add(AeCell('${e.local}', width: w, align: a, fill: fill));
        case 'Total':
          cells.add(AeCell('${e.total}', width: w, align: a, fill: fill, style: AeSheetKit.cell(weight: FontWeight.w800)));
        case 'Male':
          cells.add(AeCell('${e.male}', width: w, align: a, fill: fill));
        case 'Female':
          cells.add(AeCell('${e.female}', width: w, align: a, fill: fill));
        case 'Exhibitors':
          cells.add(AeCell(e.hasExhibit ? '${e.exhibitors}' : '-', width: w, align: a, fill: fill));
        case 'Visitors':
          cells.add(AeCell(e.hasExhibit ? '${e.exhibitVisitors}' : '-', width: w, align: a, fill: fill));
        case 'Organizer, contact & tel. no.':
          cells.add(AeCell(
            '',
            width: w,
            fill: fill,
            child: Tooltip(
              message: e.organizerCell.isEmpty ? 'No organizer details' : e.organizerCell,
              child: Text(
                e.organizerCell.isEmpty ? '—' : e.organizerCell,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AeSheetKit.cell(color: e.organizerCell.isEmpty ? AeDashTokens.muted : AeDashTokens.text),
              ),
            ),
          ));
        case 'Remarks':
          cells.add(AeCell(e.remarks, width: w, fill: fill, style: AeSheetKit.cell(color: AeDashTokens.muted)));
        case 'Validation':
          cells.add(AeCell(
            '',
            width: w,
            align: a,
            fill: fill,
            child: Tooltip(
              message: [...issues, ...warnings].isEmpty ? 'OK' : [...issues, ...warnings].join('\n'),
              child: Text(
                hasIssue ? 'Error' : (warnings.isNotEmpty ? 'Check' : 'OK'),
                style: AeSheetKit.cell(
                  weight: FontWeight.w800,
                  color: hasIssue ? AeDashTokens.danger : (warnings.isNotEmpty ? AeDashTokens.warning : AeDashTokens.success),
                ),
              ),
            ),
          ));
        case 'Encoded by':
          final au = e.audit;
          cells.add(AeCell(
            '',
            width: w,
            fill: fill,
            child: Tooltip(
              message: au.isEmpty
                  ? (e.isDemo ? 'Demo / seed data' : 'No signature recorded')
                  : [
                      '${au.encodedBy} · ${au.encodedPosition}',
                      if (au.createdBy.isNotEmpty && au.createdBy != au.encodedBy) 'First entered by ${au.createdBy}',
                    ].join('\n'),
              child: Text(
                au.isEmpty ? (e.isDemo ? 'Demo' : '—') : au.encodedBy,
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
            child: showMonth
                ? TextButton(
                    onPressed: () => onOpenMonth?.call(e),
                    child: Text(AeSheetKit.monthName(e.dateStart.month).substring(0, 3)),
                  )
                : Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                    _icon(Icons.edit_rounded, 'Edit', () => onEdit?.call(e)),
                    _icon(Icons.copy_rounded, 'Duplicate', () => onDuplicate?.call(e)),
                    _icon(Icons.delete_outline_rounded, 'Delete', () => onDelete?.call(e), color: AeDashTokens.danger),
                  ]),
          ));
        default:
          cells.add(AeCell('', width: w, fill: fill));
      }
    }
    final editable = !readOnly && !showMonth;
    return InkWell(
      onTap: editable ? () => onEdit?.call(e) : (showMonth ? () => onOpenMonth?.call(e) : null),
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

import 'package:flutter/material.dart';

import 'package:atmos_trs_system/config/ae_register_schema.dart';
import 'package:atmos_trs_system/models/ae_register.dart';
import 'package:atmos_trs_system/utils/ae_register_calculator.dart';
import 'package:atmos_trs_system/widgets/ae_register/ae_sheet_kit.dart';
import 'package:atmos_trs_system/widgets/establishment_dash_tokens.dart';

/// MonthlyRecord sheet: per-day check-in / check-out / guest-nights / occupancy.
class AeMonthlyRecordTable extends StatelessWidget {
  const AeMonthlyRecordTable({
    super.key,
    required this.report,
    required this.daily,
    required this.totals,
    required this.schema,
    required this.readOnly,
    this.onToggleZeroDay,
  });

  final AeMonthlyReport report;
  final List<AeDailyRecordLine> daily;
  final AeMonthTotals totals;
  final AeRegisterSchema schema;
  final bool readOnly;
  final void Function(int day, bool zero)? onToggleZeroDay;

  @override
  Widget build(BuildContext context) {
    final head = AeSheetKit.cell(size: 11.5, weight: FontWeight.w800);
    final rooms = schema.tracksRooms;
    final cols = <(String, double)>[
      ('Date', 54),
      ('Day', 60),
      ('Check in', 84),
      if (schema.tracksNights) ('Check out', 84),
      (schema.tracksNights ? 'Guest nights' : 'Guests', 100),
      if (rooms) ('Rooms occupied', 110),
      if (rooms) ('Occupancy', 96),
      if (rooms) ('Guests / room', 100),
      ('Status', 140),
    ];
    final width = cols.fold<double>(0, (w, c) => w + c.$2);
    final filled = daily.where((d) => d.isFilled).length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 24,
          runSpacing: 4,
          children: [
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              AeSheetField(label: 'Name of Province / HUC / ICC:', value: report.province),
              AeSheetField(label: 'Name of Municipality:', value: report.municipality),
              AeSheetField(label: 'Name of Establishment:', value: report.aeName, bold: true),
            ]),
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              if (rooms) AeSheetField(label: 'Total Number of Rooms:', value: '${report.totalRooms}', valueWidth: 120, valueAlign: TextAlign.center),
              AeSheetField(label: 'AE Type:', value: report.aeType, valueWidth: 120, valueAlign: TextAlign.center),
              if (schema.tracksNights)
                AeSheetField(
                  label: 'Guests on last day of previous month:',
                  value: '${report.prevMonthLastDayGuests}',
                  valueWidth: 120,
                  valueAlign: TextAlign.center,
                ),
            ]),
          ],
        ),
        const SizedBox(height: 10),
        Text(
          'Days filled: $filled / ${daily.length}'
          '${readOnly ? '' : ' — tap an empty day to mark it as "no guests" (counts toward completeness).'}',
          style: AeDashTokens.body(size: 12),
        ),
        const SizedBox(height: 8),
        AeSheetFrame(
          minWidth: width,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [for (final c in cols) AeCell(c.$1, width: c.$2, align: TextAlign.center, fill: AeSheetKit.headerFill, style: head, height: 36)]),
              for (final d in daily) _dayRow(d, cols),
              Row(children: [
                for (final c in cols)
                  AeCell(
                    switch (c.$1) {
                      'Date' => 'Total',
                      'Check in' => '${totals.checkIns}',
                      'Check out' => '${totals.checkOuts}',
                      'Guest nights' || 'Guests' => '${totals.guestNights}',
                      'Rooms occupied' => '${totals.roomsOccupied}',
                      'Occupancy' => AeRegisterCalculator.pct(totals.occupancyRate),
                      'Guests / room' => AeRegisterCalculator.dec(totals.avgPersonsPerRoom),
                      _ => '',
                    },
                    width: c.$2,
                    align: TextAlign.center,
                    fill: AeSheetKit.totalFill,
                    style: head,
                  ),
              ]),
            ],
          ),
        ),
        const SizedBox(height: 14),
        AeSheetFrame(
          minWidth: 420,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                AeCell('Residence', width: 200, fill: AeSheetKit.headerFill, style: head),
                AeCell('Check in', width: 110, align: TextAlign.center, fill: AeSheetKit.headerFill, style: head),
                AeCell(schema.tracksNights ? 'Guest nights' : 'Guests', width: 110, align: TextAlign.center, fill: AeSheetKit.headerFill, style: head),
              ]),
              _split('Domestic Guest', totals.domesticArrivals, totals.domesticNights),
              _split('International Guest', totals.foreignArrivals, totals.foreignNights),
              _split('Overseas Filipinos', totals.overseasFilipinoArrivals, totals.overseasFilipinoNights),
              _split('Unknown', totals.unknownArrivals, totals.unknownNights),
              if (schema.tracksNights) ...[
                Row(children: [
                  AeCell('Average Length of Stay', width: 310, fill: AeSheetKit.bandFill, style: head),
                  AeCell('${AeRegisterCalculator.dec(totals.alos)} nights', width: 110, align: TextAlign.center, fill: AeSheetKit.kpiFill, style: head),
                ]),
                Row(children: [
                  AeCell('Average Visitor Days', width: 310, fill: AeSheetKit.bandFill, style: head),
                  AeCell(
                    totals.alos == null ? '—' : '${(totals.alos! + 1).toStringAsFixed(2)} days',
                    width: 110,
                    align: TextAlign.center,
                    fill: AeSheetKit.kpiFill,
                    style: head,
                  ),
                ]),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _split(String label, int a, int n) => Row(children: [
        AeCell(label, width: 200),
        AeCell('$a', width: 110, align: TextAlign.center),
        AeCell('$n', width: 110, align: TextAlign.center),
      ]);

  Widget _dayRow(AeDailyRecordLine d, List<(String, double)> cols) {
    final weekend = d.date.weekday >= 6;
    final fill = d.hasRows ? Colors.white : (d.markedZero ? const Color(0xFFF0FDF4) : const Color(0xFFFAFAFA));
    final status = d.hasRows ? 'Recorded' : (d.markedZero ? 'No guests' : 'Not filled');
    final statusColor = d.hasRows
        ? AeDashTokens.success
        : (d.markedZero ? AeDashTokens.info : AeDashTokens.muted);
    final canToggle = !readOnly && !d.hasRows && onToggleZeroDay != null;
    return InkWell(
      onTap: canToggle ? () => onToggleZeroDay!(d.day, !d.markedZero) : null,
      child: Row(children: [
        for (final c in cols)
          switch (c.$1) {
            'Date' => AeCell('${d.day}', width: c.$2, align: TextAlign.center, fill: fill),
            'Day' => AeCell(AeSheetKit.weekdays[d.date.weekday - 1], width: c.$2, align: TextAlign.center, fill: fill,
                style: AeSheetKit.cell(color: weekend ? AeDashTokens.accent : AeDashTokens.text, weight: weekend ? FontWeight.w700 : FontWeight.w500)),
            'Check in' => AeCell('${d.checkIns}', width: c.$2, align: TextAlign.center, fill: fill),
            'Check out' => AeCell(
                '${d.checkOuts}',
                width: c.$2,
                align: TextAlign.center,
                fill: d.checkOuts < 0 ? const Color(0xFFFEE2E2) : fill,
                style: AeSheetKit.cell(color: d.checkOuts < 0 ? AeDashTokens.danger : AeDashTokens.text),
              ),
            'Guest nights' || 'Guests' => AeCell('${d.guestNights}', width: c.$2, align: TextAlign.center, fill: fill),
            'Rooms occupied' => AeCell('${d.roomsOccupied}', width: c.$2, align: TextAlign.center, fill: fill),
            'Occupancy' => AeCell(AeRegisterCalculator.pct(d.occupancyRate), width: c.$2, align: TextAlign.center, fill: fill),
            'Guests / room' => AeCell(d.guestsPerRoom.toStringAsFixed(2), width: c.$2, align: TextAlign.center, fill: fill),
            _ => AeCell(
                '',
                width: c.$2,
                fill: fill,
                child: Row(children: [
                  Icon(
                    d.hasRows ? Icons.check_circle_rounded : (d.markedZero ? Icons.do_not_disturb_on_rounded : Icons.radio_button_unchecked),
                    size: 14,
                    color: statusColor,
                  ),
                  const SizedBox(width: 6),
                  Text(status, style: AeSheetKit.cell(size: 11.5, color: statusColor, weight: FontWeight.w700)),
                ]),
              ),
          },
      ]),
    );
  }
}

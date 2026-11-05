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

  static const _peachHeader = Color(0xFFFFF1E7);
  static const _rowAlt = Color(0xFFF8FAFC);
  static const _totalFill = Color(0xFFECFDF5);
  static const _totalBorder = Color(0xFF86EFAC);
  static const _mintBar = Color(0xFFECFDF5);
  static const _mintBorder = Color(0xFFA7F3D0);
  static const _mintInk = Color(0xFF047857);

  @override
  Widget build(BuildContext context) {
    final head = AeSheetKit.cell(size: 11.5, weight: FontWeight.w800, color: AeDashTokens.text);
    final rooms = schema.tracksRooms;
    final cols = <(String, double, IconData?)>[
      ('Date', 54, Icons.event_rounded),
      ('Day', 60, null),
      ('Check in', 84, Icons.login_rounded),
      if (schema.tracksNights) ('Check out', 84, Icons.logout_rounded),
      (schema.tracksNights ? 'Guest nights' : 'Guests', 100, Icons.bedtime_rounded),
      if (rooms) ('Rooms occupied', 118, Icons.meeting_room_rounded),
      if (rooms) ('Occupancy', 96, Icons.pie_chart_rounded),
      if (rooms) ('Guests / room', 100, Icons.groups_rounded),
      ('Status', 132, null),
    ];
    final width = cols.fold<double>(0, (w, c) => w + c.$2);
    final filled = daily.where((d) => d.isFilled).length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _metaCard(rooms),
        const SizedBox(height: 12),
        _daysFilledBar(filled, daily.length),
        const SizedBox(height: 12),
        DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            boxShadow: AeDashTokens.softShadow,
          ),
          child: AeSheetFrame(
            minWidth: width,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  for (final c in cols)
                    AeCell(
                      '',
                      width: c.$2,
                      align: TextAlign.center,
                      fill: _peachHeader,
                      height: 40,
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          if (c.$3 != null) ...[
                            Icon(c.$3, size: 12, color: AeDashTokens.accent),
                            const SizedBox(width: 4),
                          ],
                          Flexible(
                            child: Text(
                              c.$1,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              textAlign: TextAlign.center,
                              style: head,
                            ),
                          ),
                        ],
                      ),
                    ),
                ]),
                for (var i = 0; i < daily.length; i++)
                  _dayRow(daily[i], cols, zebra: i.isOdd),
                Container(
                  decoration: const BoxDecoration(
                    border: Border(top: BorderSide(color: _totalBorder, width: 1.5)),
                  ),
                  child: Row(children: [
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
                        fill: _totalFill,
                        style: head,
                        height: 36,
                      ),
                  ]),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        LayoutBuilder(
          builder: (context, constraints) {
            final sideBySide = constraints.maxWidth >= 860 && schema.tracksNights;
            final residence = _residenceCard(head);
            final averages = schema.tracksNights ? _averagesCard() : const SizedBox.shrink();
            if (!sideBySide) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  residence,
                  if (schema.tracksNights) ...[
                    const SizedBox(height: 12),
                    averages,
                  ],
                ],
              );
            }
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(flex: 3, child: residence),
                const SizedBox(width: 12),
                Expanded(flex: 2, child: averages),
              ],
            );
          },
        ),
      ],
    );
  }

  Widget _metaCard(bool rooms) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AeDashTokens.border),
        boxShadow: AeDashTokens.cardShadow,
      ),
      child: Wrap(
        spacing: 28,
        runSpacing: 8,
        children: [
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            AeSheetField(label: 'Name of Province / HUC / ICC:', value: report.province),
            AeSheetField(label: 'Name of Municipality:', value: report.municipality),
            AeSheetField(label: 'Name of Establishment:', value: report.aeName, bold: true),
          ]),
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            if (rooms)
              AeSheetField(
                label: 'Total Number of Rooms:',
                value: '${report.totalRooms}',
                valueWidth: 120,
                valueAlign: TextAlign.center,
              ),
            AeSheetField(
              label: 'AE Type:',
              value: report.aeType,
              valueWidth: 120,
              valueAlign: TextAlign.center,
            ),
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
    );
  }

  Widget _daysFilledBar(int filled, int total) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: _mintBar,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _mintBorder),
      ),
      child: Row(
        children: [
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.85),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(Icons.calendar_month_rounded, size: 16, color: _mintInk),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: RichText(
              text: TextSpan(
                style: AeDashTokens.body(size: 12.5, color: _mintInk, weight: FontWeight.w600),
                children: [
                  TextSpan(
                    text: 'Days filled: $filled / $total',
                    style: AeDashTokens.body(size: 12.5, color: _mintInk, weight: FontWeight.w800),
                  ),
                  if (!readOnly)
                    TextSpan(
                      text:
                          '  — tap an empty day to mark it as "No Guests" (counts toward completeness).',
                      style: AeDashTokens.body(size: 12, color: const Color(0xFF065F46)),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _residenceCard(TextStyle head) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AeDashTokens.border),
        boxShadow: AeDashTokens.softShadow,
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
            child: Row(
              children: [
                AeDashTokens.iconChip(Icons.home_work_rounded, AeDashTokens.accent, size: 28),
                const SizedBox(width: 8),
                Text('Residence statistics', style: AeDashTokens.section(size: 13.5)),
              ],
            ),
          ),
          AeSheetFrame(
            minWidth: 420,
            child: Column(
              children: [
                Row(children: [
                  AeCell('Residence', width: 200, fill: _peachHeader, style: head, height: 36),
                  AeCell('Check in', width: 110, align: TextAlign.center, fill: _peachHeader, style: head, height: 36),
                  AeCell(
                    schema.tracksNights ? 'Guest nights' : 'Guests',
                    width: 110,
                    align: TextAlign.center,
                    fill: _peachHeader,
                    style: head,
                    height: 36,
                  ),
                ]),
                _split('Domestic Guests', totals.domesticArrivals, totals.domesticNights, Icons.flag_rounded, const Color(0xFFEA580C)),
                _split('International Guests', totals.foreignArrivals, totals.foreignNights, Icons.public_rounded, const Color(0xFF0284C7)),
                _split('Overseas Filipinos', totals.overseasFilipinoArrivals, totals.overseasFilipinoNights, Icons.flight_takeoff_rounded, const Color(0xFF7C3AED)),
                _split('Unknown', totals.unknownArrivals, totals.unknownNights, Icons.help_outline_rounded, AeDashTokens.muted),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _averagesCard() {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
      decoration: BoxDecoration(
        color: const Color(0xFFF0FDF4),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFBBF7D0)),
        boxShadow: AeDashTokens.cardShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              AeDashTokens.iconChip(Icons.analytics_rounded, AeDashTokens.success, size: 28),
              const SizedBox(width: 8),
              Text('Report averages', style: AeDashTokens.section(size: 13.5)),
            ],
          ),
          const SizedBox(height: 12),
          _averageMetric(
            icon: Icons.nights_stay_rounded,
            title: 'Average Length of Stay',
            value: '${AeRegisterCalculator.dec(totals.alos)} nights',
          ),
          const SizedBox(height: 10),
          _averageMetric(
            icon: Icons.timelapse_rounded,
            title: 'Average Visitor Days',
            value: totals.alos == null ? '—' : '${(totals.alos! + 1).toStringAsFixed(2)} days',
          ),
        ],
      ),
    );
  }

  Widget _averageMetric({
    required IconData icon,
    required String title,
    required String value,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.72),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFD1FAE5)),
      ),
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: const Color(0xFFDCFCE7),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, size: 18, color: AeDashTokens.success),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: AeDashTokens.body(size: 11.5, color: AeDashTokens.muted)),
                const SizedBox(height: 2),
                Text(value, style: AeDashTokens.number(size: 16)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _split(String label, int a, int n, IconData icon, Color color) => AeHoverRow(
        child: Container(
          color: Colors.white,
          child: Row(children: [
            AeCell(
              '',
              width: 200,
              child: Row(
                children: [
                  Icon(icon, size: 14, color: color),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AeSheetKit.cell(weight: FontWeight.w600),
                    ),
                  ),
                ],
              ),
            ),
            AeCell('$a', width: 110, align: TextAlign.center),
            AeCell('$n', width: 110, align: TextAlign.center),
          ]),
        ),
      );

  Widget _dayRow(
    AeDailyRecordLine d,
    List<(String, double, IconData?)> cols, {
    required bool zebra,
  }) {
    final weekend = d.date.weekday >= 6;
    final baseFill = d.hasRows
        ? (zebra ? _rowAlt : Colors.white)
        : (d.markedZero ? const Color(0xFFF0FDF4) : (zebra ? _rowAlt : const Color(0xFFFAFAFA)));
    final canToggle = !readOnly && !d.hasRows && onToggleZeroDay != null;
    return AeHoverRow(
      child: InkWell(
        onTap: canToggle ? () => onToggleZeroDay!(d.day, !d.markedZero) : null,
        child: Row(children: [
          for (final c in cols)
            switch (c.$1) {
              'Date' => AeCell('${d.day}', width: c.$2, align: TextAlign.center, fill: baseFill),
              'Day' => AeCell(
                  AeSheetKit.weekdays[d.date.weekday - 1],
                  width: c.$2,
                  align: TextAlign.center,
                  fill: baseFill,
                  style: AeSheetKit.cell(
                    color: weekend ? AeDashTokens.accent : AeDashTokens.text,
                    weight: weekend ? FontWeight.w700 : FontWeight.w500,
                  ),
                ),
              'Check in' => AeCell('${d.checkIns}', width: c.$2, align: TextAlign.center, fill: baseFill),
              'Check out' => AeCell(
                  '${d.checkOuts}',
                  width: c.$2,
                  align: TextAlign.center,
                  fill: d.checkOuts < 0 ? const Color(0xFFFEE2E2) : baseFill,
                  style: AeSheetKit.cell(
                    color: d.checkOuts < 0 ? AeDashTokens.danger : AeDashTokens.text,
                  ),
                ),
              'Guest nights' || 'Guests' =>
                AeCell('${d.guestNights}', width: c.$2, align: TextAlign.center, fill: baseFill),
              'Rooms occupied' =>
                AeCell('${d.roomsOccupied}', width: c.$2, align: TextAlign.center, fill: baseFill),
              'Occupancy' => AeCell(
                  AeRegisterCalculator.pct(d.occupancyRate),
                  width: c.$2,
                  align: TextAlign.center,
                  fill: baseFill,
                ),
              'Guests / room' => AeCell(
                  d.guestsPerRoom.toStringAsFixed(2),
                  width: c.$2,
                  align: TextAlign.center,
                  fill: baseFill,
                ),
              _ => AeCell(
                  '',
                  width: c.$2,
                  fill: baseFill,
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: _statusBadge(d),
                  ),
                ),
            },
        ]),
      ),
    );
  }

  Widget _statusBadge(AeDailyRecordLine d) {
    late final Color bg;
    late final Color fg;
    late final IconData icon;
    late final String label;
    if (d.hasRows) {
      bg = const Color(0xFFDCFCE7);
      fg = const Color(0xFF15803D);
      icon = Icons.check_circle_rounded;
      label = 'Recorded';
    } else if (d.markedZero) {
      bg = const Color(0xFFE0F2FE);
      fg = const Color(0xFF0369A1);
      icon = Icons.do_not_disturb_on_rounded;
      label = 'No Guests';
    } else {
      bg = const Color(0xFFF1F5F9);
      fg = const Color(0xFF64748B);
      icon = Icons.radio_button_unchecked;
      label = 'Not Filled';
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: fg.withValues(alpha: 0.22)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: fg),
          const SizedBox(width: 4),
          Text(
            label,
            style: AeSheetKit.cell(size: 11, color: fg, weight: FontWeight.w800),
          ),
        ],
      ),
    );
  }
}

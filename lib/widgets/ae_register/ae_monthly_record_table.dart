import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

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

  static const _primary = Color(0xFFF97316);
  static const _lightOrange = Color(0xFFFFF7ED);
  static const _border = Color(0xFFE5E7EB);
  static const _darkText = Color(0xFF1F2937);
  static const _mutedText = Color(0xFF64748B);
  static const _rowAlt = Color(0xFFF8FAFC);
  static const _mintBar = Color(0xFFECFDF5);
  static const _mintBorder = Color(0xFFA7F3D0);
  static const _mintInk = Color(0xFF047857);
  static const _totalFill = Color(0xFFECFDF5);

  @override
  Widget build(BuildContext context) {
    final rooms = schema.tracksRooms;
    final filled = daily.where((d) => d.isFilled).length;
    final screenH = MediaQuery.sizeOf(context).height;
    final tableBodyMaxH = (screenH * 0.42).clamp(260.0, 520.0);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _metaCard(rooms),
        const SizedBox(height: 12),
        _daysFilledBar(filled, daily.length),
        const SizedBox(height: 12),
        LayoutBuilder(
          builder: (context, constraints) {
            final cols = _fitColumns(_baseColumns(rooms), constraints.maxWidth);
            final tableWidth = cols.fold<double>(0, (w, c) => w + c.$2);
            final available = constraints.maxWidth;

            return Container(
              width: double.infinity,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: _border),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF0F172A).withValues(alpha: 0.04),
                    blurRadius: 16,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              clipBehavior: Clip.antiAlias,
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: SizedBox(
                  width: tableWidth < available ? available : tableWidth,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _headerRow(cols),
                      ConstrainedBox(
                        constraints: BoxConstraints(maxHeight: tableBodyMaxH),
                        child: SingleChildScrollView(
                          child: Column(
                            children: [
                              for (var i = 0; i < daily.length; i++)
                                _dayRow(daily[i], cols, zebra: i.isOdd),
                              _totalsRow(cols),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
        const SizedBox(height: 16),
        LayoutBuilder(
          builder: (context, constraints) {
            final sideBySide = constraints.maxWidth >= 860 && schema.tracksNights;
            final residence = _residenceCard();
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

  List<(String, double, IconData?, bool)> _baseColumns(bool rooms) {
    return [
      ('Date', 56, Icons.event_rounded, false),
      ('Day', 64, null, false),
      ('Check in', 90, Icons.login_rounded, true),
      if (schema.tracksNights) ('Check out', 90, Icons.logout_rounded, true),
      (schema.tracksNights ? 'Guest nights' : 'Guests', 110, Icons.bedtime_rounded, true),
      if (rooms) ('Rooms occupied', 124, Icons.meeting_room_rounded, true),
      if (rooms) ('Occupancy', 100, Icons.pie_chart_rounded, true),
      if (rooms) ('Guests / room', 108, Icons.groups_rounded, true),
      ('Status', 140, Icons.verified_outlined, true),
    ];
  }

  List<(String, double, IconData?)> _fitColumns(
    List<(String, double, IconData?, bool)> base,
    double available,
  ) {
    final minTotal = base.fold<double>(0, (w, c) => w + c.$2);
    if (!available.isFinite || available <= minTotal) {
      return [for (final c in base) (c.$1, c.$2, c.$3)];
    }
    final extra = available - minTotal;
    final flexTotal = base.where((c) => c.$4).fold<double>(0, (w, c) => w + c.$2);
    if (flexTotal <= 0) {
      final scale = available / minTotal;
      return [for (final c in base) (c.$1, c.$2 * scale, c.$3)];
    }
    return [
      for (final c in base)
        (
          c.$1,
          c.$4 ? c.$2 + extra * (c.$2 / flexTotal) : c.$2,
          c.$3,
        ),
    ];
  }

  Widget _metaCard(bool rooms) {
    final fields = <(IconData, String, String)>[
      (Icons.map_outlined, 'Province / HUC / ICC', report.province.trim().isEmpty ? '—' : report.province),
      (Icons.location_city_outlined, 'Municipality / City',
          report.municipality.trim().isEmpty ? '—' : report.municipality),
      (Icons.hotel_rounded, 'Establishment', report.aeName.trim().isEmpty ? '—' : report.aeName),
      if (rooms) (Icons.bed_rounded, 'Total Number of Rooms', '${report.totalRooms}'),
      (Icons.category_outlined, 'AE Type', report.aeType.trim().isEmpty ? '—' : report.aeType),
      if (schema.tracksNights)
        (
          Icons.groups_outlined,
          'Guests on last day of previous month',
          '${report.prevMonthLastDayGuests}',
        ),
    ];

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _border),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF0F172A).withValues(alpha: 0.03),
            blurRadius: 12,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: LayoutBuilder(
        builder: (context, c) {
          final wide = c.maxWidth >= 980;
          final mid = c.maxWidth >= 640;
          if (wide) {
            return Row(
              children: [
                for (var i = 0; i < fields.length; i++) ...[
                  if (i > 0)
                    Container(width: 1, height: 44, color: _border, margin: const EdgeInsets.symmetric(horizontal: 4)),
                  Expanded(child: _metaField(fields[i])),
                ],
              ],
            );
          }
          if (mid) {
            return Wrap(
              spacing: 0,
              runSpacing: 8,
              children: [
                for (final f in fields)
                  SizedBox(
                    width: (c.maxWidth - 8) / 2,
                    child: _metaField(f),
                  ),
              ],
            );
          }
          return Column(
            children: [
              for (var i = 0; i < fields.length; i++) ...[
                if (i > 0) const Divider(height: 1, color: _border),
                _metaField(fields[i]),
              ],
            ],
          );
        },
      ),
    );
  }

  Widget _metaField((IconData, String, String) field) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: _lightOrange,
              borderRadius: BorderRadius.circular(9),
            ),
            child: Icon(field.$1, size: 16, color: _primary),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  field.$2,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.inter(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: _mutedText,
                    height: 1.2,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  field.$3,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.inter(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w800,
                    color: _darkText,
                    height: 1.2,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _daysFilledBar(int filled, int total) {
    final complete = total > 0 && filled >= total;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: complete ? _mintBar : _lightOrange,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: complete ? _mintBorder : const Color(0xFFFED7AA)),
      ),
      child: Row(
        children: [
          Icon(
            Icons.event_available_rounded,
            size: 18,
            color: complete ? _mintInk : _primary,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text.rich(
              TextSpan(
                style: GoogleFonts.inter(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  color: complete ? _mintInk : const Color(0xFF9A3412),
                ),
                children: [
                  TextSpan(
                    text: 'Days filled: $filled / $total',
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                  if (!readOnly)
                    TextSpan(
                      text: complete
                          ? ''
                          : '  — tap an empty day to mark it as "No Guests" (counts toward completeness).',
                      style: TextStyle(
                        fontWeight: FontWeight.w500,
                        color: complete ? _mintInk : const Color(0xFF9A3412),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _headerRow(List<(String, double, IconData?)> cols) {
    final head = GoogleFonts.inter(
      fontSize: 11.5,
      fontWeight: FontWeight.w800,
      color: _darkText,
    );
    return Row(
      children: [
        for (final c in cols)
          _cell(
            '',
            width: c.$2,
            align: TextAlign.center,
            fill: _lightOrange,
            height: 42,
            boldBorder: true,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (c.$3 != null) ...[
                  Icon(c.$3, size: 13, color: _primary),
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
      ],
    );
  }

  Widget _totalsRow(List<(String, double, IconData?)> cols) {
    final head = GoogleFonts.inter(
      fontSize: 12,
      fontWeight: FontWeight.w800,
      color: _darkText,
    );
    return Container(
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: Color(0xFF86EFAC), width: 1.5)),
      ),
      child: Row(
        children: [
          for (final c in cols)
            _cell(
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
              height: 38,
            ),
        ],
      ),
    );
  }

  Widget _residenceCard() {
    final head = GoogleFonts.inter(fontSize: 11.5, fontWeight: FontWeight.w800, color: _darkText);
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _border),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF0F172A).withValues(alpha: 0.04),
            blurRadius: 14,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
            child: Row(
              children: [
                Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    color: _lightOrange,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(Icons.home_work_rounded, size: 15, color: _primary),
                ),
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
                  AeCell('Residence', width: 200, fill: _lightOrange, style: head, height: 36),
                  AeCell('Check in', width: 110, align: TextAlign.center, fill: _lightOrange, style: head, height: 36),
                  AeCell(
                    schema.tracksNights ? 'Guest nights' : 'Guests',
                    width: 110,
                    align: TextAlign.center,
                    fill: _lightOrange,
                    style: head,
                    height: 36,
                  ),
                ]),
                _split('Domestic Guests', totals.domesticArrivals, totals.domesticNights, Icons.flag_rounded, _primary),
                _split('International Guests', totals.foreignArrivals, totals.foreignNights, Icons.public_rounded, AeDashTokens.brandDeep),
                _split('Overseas Filipinos', totals.overseasFilipinoArrivals, totals.overseasFilipinoNights, Icons.flight_takeoff_rounded, AeDashTokens.brandDark),
                _split('Unknown', totals.unknownArrivals, totals.unknownNights, Icons.help_outline_rounded, _mutedText),
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
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _border),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF0F172A).withValues(alpha: 0.04),
            blurRadius: 14,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: _lightOrange,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.analytics_rounded, size: 15, color: _primary),
              ),
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
        color: _lightOrange,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFFED7AA)),
      ),
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, size: 18, color: _primary),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: AeDashTokens.body(size: 11.5, color: _mutedText)),
                const SizedBox(height: 2),
                Text(value, style: AeDashTokens.number(size: 16, color: _darkText)),
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
        : (d.markedZero ? const Color(0xFFF0FDF4) : (zebra ? _rowAlt : Colors.white));
    final canToggle = !readOnly && !d.hasRows && onToggleZeroDay != null;
    final body = GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w500, color: _darkText);

    return AeHoverRow(
      child: InkWell(
        onTap: canToggle ? () => onToggleZeroDay!(d.day, !d.markedZero) : null,
        child: Row(children: [
          for (final c in cols)
            switch (c.$1) {
              'Date' => _cell('${d.day}', width: c.$2, align: TextAlign.center, fill: baseFill, style: body, height: 38),
              'Day' => _cell(
                  AeSheetKit.weekdays[d.date.weekday - 1],
                  width: c.$2,
                  align: TextAlign.center,
                  fill: baseFill,
                  height: 38,
                  style: GoogleFonts.inter(
                    fontSize: 12,
                    color: weekend ? _primary : _darkText,
                    fontWeight: weekend ? FontWeight.w800 : FontWeight.w500,
                  ),
                ),
              'Check in' => _cell('${d.checkIns}', width: c.$2, align: TextAlign.center, fill: baseFill, style: body, height: 38),
              'Check out' => _cell(
                  '${d.checkOuts}',
                  width: c.$2,
                  align: TextAlign.center,
                  fill: d.checkOuts < 0 ? const Color(0xFFFEE2E2) : baseFill,
                  height: 38,
                  style: GoogleFonts.inter(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: d.checkOuts < 0 ? AeDashTokens.danger : _darkText,
                  ),
                ),
              'Guest nights' || 'Guests' =>
                _cell('${d.guestNights}', width: c.$2, align: TextAlign.center, fill: baseFill, style: body, height: 38),
              'Rooms occupied' =>
                _cell('${d.roomsOccupied}', width: c.$2, align: TextAlign.center, fill: baseFill, style: body, height: 38),
              'Occupancy' => _cell(
                  AeRegisterCalculator.pct(d.occupancyRate),
                  width: c.$2,
                  align: TextAlign.center,
                  fill: baseFill,
                  style: body,
                  height: 38,
                ),
              'Guests / room' => _cell(
                  d.guestsPerRoom.toStringAsFixed(2),
                  width: c.$2,
                  align: TextAlign.center,
                  fill: baseFill,
                  style: body,
                  height: 38,
                ),
              _ => _cell(
                  '',
                  width: c.$2,
                  fill: baseFill,
                  height: 38,
                  child: Center(child: _statusBadge(d)),
                ),
            },
        ]),
      ),
    );
  }

  Widget _cell(
    String text, {
    required double width,
    TextAlign align = TextAlign.left,
    Color? fill,
    TextStyle? style,
    double height = 38,
    Widget? child,
    bool boldBorder = false,
  }) {
    return Container(
      width: width,
      height: height,
      padding: const EdgeInsets.symmetric(horizontal: 6),
      alignment: switch (align) {
        TextAlign.right || TextAlign.end => Alignment.centerRight,
        TextAlign.center => Alignment.center,
        _ => Alignment.centerLeft,
      },
      decoration: BoxDecoration(
        color: fill,
        border: Border(
          right: BorderSide(color: _border, width: boldBorder ? 1 : 0.8),
          bottom: BorderSide(color: _border, width: boldBorder ? 1.2 : 0.8),
        ),
      ),
      child: child ??
          Text(
            text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: align,
            style: style ??
                GoogleFonts.inter(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: _darkText,
                ),
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
      fg = _mutedText;
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
            style: GoogleFonts.inter(fontSize: 11, color: fg, fontWeight: FontWeight.w800),
          ),
        ],
      ),
    );
  }
}

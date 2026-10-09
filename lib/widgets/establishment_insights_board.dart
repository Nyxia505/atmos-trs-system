import 'package:flutter/material.dart';

import 'package:atmos_trs_system/config/ae_register_schema.dart';
import 'package:atmos_trs_system/models/ae_register.dart';
import 'package:atmos_trs_system/services/ae_register_service.dart';
import 'package:atmos_trs_system/utils/ae_register_insights.dart';
import 'package:atmos_trs_system/widgets/ae_register/ae_sheet_kit.dart';
import 'package:atmos_trs_system/widgets/chart_transition.dart';
import 'package:atmos_trs_system/widgets/establishment_dash_tokens.dart';
import 'package:atmos_trs_system/widgets/establishment_dashboard_components.dart';
import 'package:atmos_trs_system/widgets/establishment_dss_charts.dart';

/// Insights (decision support) from the hotel's DOT DAE-1B register.
///
/// Also used read-only by Governor / LGU drill-downs ([embedded] swaps the hero
/// for a compact title row).
class EstablishmentInsightsBoard extends StatefulWidget {
  const EstablishmentInsightsBoard({
    super.key,
    required this.profile,
    required this.schema,
    this.embedded = false,
  });

  final AeRegisterProfile profile;
  final AeRegisterSchema schema;
  final bool embedded;

  @override
  State<EstablishmentInsightsBoard> createState() => _EstablishmentInsightsBoardState();
}

class _EstablishmentInsightsBoardState extends State<EstablishmentInsightsBoard> {
  static const double _chartHeight = 210;
  static const Color _female = Color(0xFFEC4899);

  late int _year;
  late int _month;
  late Stream<List<AeMonthlyReport>> _reports;
  Stream<List<AeRegisterRow>>? _rows;
  String _rowsKey = '';

  bool get _rooms => widget.schema.tracksRooms;

  static String _peso(double v) => v == 0 ? '—' : '₱${AeSheetKit.money(v)}';

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _year = now.year;
    _month = now.month;
    _reports = AeRegisterService.watchForAe(widget.profile.aeId);
  }

  @override
  void didUpdateWidget(covariant EstablishmentInsightsBoard old) {
    super.didUpdateWidget(old);
    if (old.profile.aeId != widget.profile.aeId) {
      _reports = AeRegisterService.watchForAe(widget.profile.aeId);
      _rowsKey = '';
    }
  }

  Stream<List<AeRegisterRow>> _rowsStream() {
    final key = '${widget.profile.aeId}|$_year|$_month';
    if (_rows == null || key != _rowsKey) {
      _rowsKey = key;
      _rows = AeRegisterService.watchRows(widget.profile.aeId, _year, _month);
    }
    return _rows!;
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<AeMonthlyReport>>(
      stream: _reports,
      builder: (context, repSnap) {
        final reports = repSnap.data ?? const <AeMonthlyReport>[];
        return StreamBuilder<List<AeRegisterRow>>(
          stream: _rowsStream(),
          builder: (context, rowSnap) {
            final loading = !repSnap.hasData || !rowSnap.hasData;
            final insights = AeRegisterInsightsBuilder.build(
              reports: reports,
              rows: rowSnap.data ?? const [],
              year: _year,
              month: _month,
              totalRooms: widget.profile.totalRooms,
              tracksRooms: _rooms,
            );
            return _layout(context, reports, insights, loading: loading, error: repSnap.error ?? rowSnap.error);
          },
        );
      },
    );
  }

  Widget _monthPicker(List<AeMonthlyReport> reports) {
    final now = DateTime.now();
    final keys = <int>{
      now.year * 100 + now.month,
      _year * 100 + _month,
      for (final r in reports) r.year * 100 + r.month,
    }.toList()
      ..sort((a, b) => b.compareTo(a));
    return AeDropdownAction<int>(
      value: _year * 100 + _month,
      leading: Icons.calendar_month_rounded,
      options: {
        for (final k in keys) k: '${AeSheetKit.monthName(k % 100)} ${k ~/ 100}',
      },
      onChanged: (k) => setState(() {
        _year = k ~/ 100;
        _month = k % 100;
      }),
    );
  }

  Widget _layout(
    BuildContext context,
    List<AeMonthlyReport> reports,
    AeRegisterInsights a, {
    required bool loading,
    Object? error,
  }) {
    return LayoutBuilder(
      builder: (context, c) {
        final w = c.maxWidth;
        final pad = w < 600 ? 14.0 : (w < 1000 ? 18.0 : 24.0);
        final gap = w < 600 ? 12.0 : 18.0;
        final wide = w - pad * 2 >= 820;

        Widget pair(Widget x, Widget y) => wide
            ? Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [Expanded(child: x), SizedBox(width: gap), Expanded(child: y)],
              )
            : Column(children: [x, SizedBox(height: gap), y]);

        final period = '${AeSheetKit.monthName(a.month)} ${a.year}';
        final children = <Widget>[
          if (widget.embedded)
            Row(
              children: [
                Expanded(child: Text('Register insights · $period', style: AeDashTokens.section(size: 15))),
                _monthPicker(reports),
              ],
            ),
          if (error != null)
            AeAlertBanner(
              title: 'Could not load register',
              message: '$error',
              icon: Icons.error_outline_rounded,
              color: AeDashTokens.danger,
              background: const Color(0xFFFEF2F2),
              borderColor: const Color(0xFFFECACA),
            ),
          if (loading) const LinearProgressIndicator(minHeight: 2, color: AeDashTokens.accent),
          _kpiGrid(a),
          _completenessCard(a),
          pair(_dailyCard(a), _weekdayCard(a)),
          pair(_monthlyCard(a), _rooms ? _alosCard(a) : _monthlyGuestsCard(a)),
          pair(_residenceCard(a), _sexCard(a)),
          pair(_originsCard('Top foreign markets', Icons.flight_land_rounded, a.topForeign, a.totals.foreignArrivals),
              _originsCard('Top domestic regions', Icons.map_rounded, a.topRegions, a.totals.domesticArrivals)),
          if (_rooms && a.totalRooms > 0) _roomsCard(a, wide),
          pair(_revenueCard(a), _rooms ? _adrCard(a) : _spendCard(a)),
          _comparisonCard(a),
          _recommendations(a),
        ];

        return ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: EdgeInsets.only(bottom: pad + 12),
          children: [
            if (!widget.embedded)
              AePageHero(
                icon: Icons.insights_rounded,
                title: 'Insights',
                subtitle: 'From your DOT register — occupancy, length of stay, guest '
                    'markets, rooms and revenue. Recommendations unlock after '
                    '${AeRegisterInsightsBuilder.softDays} filled days.',
                trailing: _monthPicker(reports),
                flush: true,
              ),
            Padding(
              padding: EdgeInsets.fromLTRB(pad, gap, pad, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (var i = 0; i < children.length; i++) ...[
                    if (i > 0) SizedBox(height: gap),
                    children[i],
                  ],
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  // --------------------------------------------------------------- KPIs

  String? _delta(double? now, double? before, {bool points = false, int digits = 1}) {
    if (now == null || before == null) return null;
    if (points) {
      final d = now - before;
      return '${d >= 0 ? '+' : ''}${d.toStringAsFixed(digits)} pts';
    }
    if (before == 0) return null;
    final p = (now - before) / before * 100;
    return '${p >= 0 ? '+' : ''}${p.toStringAsFixed(0)}%';
  }

  Widget _kpiGrid(AeRegisterInsights a) {
    final t = a.totals;
    final p = a.previous;
    final mtd = a.isCurrentMonth ? ' (MTD)' : '';
    final items = <Widget>[
      if (_rooms) ...[
        _Kpi(
          'Occupancy$mtd',
          a.occupancyPct == null ? '—' : '${a.occupancyPct!.toStringAsFixed(1)}%',
          Icons.donut_large_rounded,
          AeDashTokens.purple,
          delta: _delta(a.occupancyPct, p?.occupancyPct, points: true),
          hint: a.totalRooms > 0 ? '${t.roomsOccupied} of ${a.totalRooms * a.daysElapsed} room-nights' : 'Set total rooms',
        ),
        _Kpi(
          'ALOS (nights)',
          t.alos == null ? '—' : t.alos!.toStringAsFixed(2),
          Icons.hotel_rounded,
          AeDashTokens.success,
          delta: _delta(t.alos, p?.totals.alos),
          hint: 'Guest-nights ÷ check-ins',
        ),
        _Kpi(
          'Guest-nights',
          '${t.guestNights}',
          Icons.nights_stay_rounded,
          AeDashTokens.accent,
          delta: _delta(t.guestNights.toDouble(), p?.totals.guestNights.toDouble()),
        ),
      ],
      _Kpi(
        _rooms ? 'Check-ins' : 'Guests served',
        '${t.checkIns}',
        Icons.login_rounded,
        AeDashTokens.info,
        delta: _delta(t.checkIns.toDouble(), p?.totals.checkIns.toDouble()),
      ),
      if (_rooms)
        _Kpi(
          'Persons / room',
          t.avgPersonsPerRoom == null ? '—' : t.avgPersonsPerRoom!.toStringAsFixed(2),
          Icons.group_rounded,
          AeDashTokens.chartSecondary,
        ),
      if (_rooms) ...[
        _Kpi(
          'ADR',
          a.adr == null ? '—' : _peso(a.adr!),
          Icons.sell_rounded,
          AeDashTokens.chartTertiary,
          delta: _delta(a.adr, p?.adr),
          hint: 'Room revenue ÷ rooms sold',
        ),
        _Kpi(
          'RevPAR',
          a.revpar == null ? '—' : _peso(a.revpar!),
          Icons.trending_up_rounded,
          AeDashTokens.blue,
          delta: _delta(a.revpar, p?.revpar),
          hint: 'Room revenue ÷ available rooms',
        ),
      ] else
        _Kpi(
          'Spend / guest',
          a.spendPerGuest == null ? '—' : _peso(a.spendPerGuest!),
          Icons.sell_rounded,
          AeDashTokens.chartTertiary,
        ),
      _Kpi(
        'Total sales',
        _peso(t.grandTotalSales),
        Icons.payments_rounded,
        AeDashTokens.warning,
        delta: _delta(t.grandTotalSales, p?.totals.grandTotalSales),
      ),
    ];
    return AeResponsiveGrid(minItemWidth: 170, maxColumns: 4, spacing: 12, children: items);
  }

  Widget _completenessCard(AeRegisterInsights a) {
    final pct = a.completeness;
    final color = pct >= 0.95
        ? AeDashTokens.success
        : pct >= 0.6
            ? AeDashTokens.warning
            : AeDashTokens.danger;
    final (dssLabel, dssColor) = switch (a.dss) {
      AeInsightsDssLevel.locked => ('Recommendations locked', AeDashTokens.muted),
      AeInsightsDssLevel.soft => ('Soft recommendations', AeDashTokens.warning),
      AeInsightsDssLevel.full => ('Full recommendations', AeDashTokens.success),
    };
    return Container(
      decoration: AeDashTokens.cardDecoration(),
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Icon(Icons.fact_check_rounded, size: 18, color: AeDashTokens.accent),
              const SizedBox(width: 8),
              Expanded(child: Text('Register completeness', style: AeDashTokens.section(size: 14))),
              AeStatusPill(label: dssLabel, color: dssColor),
            ],
          ),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: a.daysElapsed == 0 ? 0 : pct,
              minHeight: 10,
              backgroundColor: AeDashTokens.border,
              color: color,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            a.daysElapsed == 0
                ? 'This month has not started yet.'
                : '${a.filledDays} of ${a.daysElapsed} day(s) filled '
                    '${a.isCurrentMonth ? 'so far ' : ''}(rows or "no guests"). '
                    '${a.historyFilledDays} filled day(s) on record overall — '
                    'tips unlock at ${AeRegisterInsightsBuilder.softDays}, full at '
                    '${AeRegisterInsightsBuilder.fullDays}.',
            style: AeDashTokens.body(size: 12),
          ),
        ],
      ),
    );
  }

  // --------------------------------------------------------------- charts

  Widget _dailyCard(AeRegisterInsights a) {
    final elapsed = a.daily.take(a.daysElapsed).toList();
    final labels = [for (final d in elapsed) '${d.day}'];
    final hasRooms = _rooms && a.totalRooms > 0;
    return AeAnalyticsCard(
      title: hasRooms ? 'Daily occupancy' : 'Daily guests',
      subtitle: hasRooms
          ? 'Rooms occupied ÷ total rooms, per day'
          : 'Guests recorded per day',
      icon: Icons.show_chart_rounded,
      iconColor: AeDashTokens.info,
      height: _chartHeight,
      child: ChartTransition(
        swapKey: ('daily', a.year, a.month, a.totals.rowCount),
        builder: (context, progress) => hasRooms
            ? EstablishmentDssCharts.occupancyPctTrend(
                pctValues: [for (final d in elapsed) (d.occupancyRate ?? 0) * 100],
                labels: labels,
                progress: progress,
              )
            : EstablishmentDssCharts.valueBars(
                values: [for (final d in elapsed) d.guestNights.toDouble()],
                labels: labels,
                emptyMessage: 'No guests recorded this month yet.',
                progress: progress,
              ),
      ),
    );
  }

  Widget _weekdayCard(AeRegisterInsights a) {
    final hasRooms = _rooms && a.totalRooms > 0;
    final values = hasRooms ? a.weekdayOccupancyPct : a.weekdayGuests;
    var best = 0;
    for (var i = 1; i < 7; i++) {
      if (values[i] > values[best]) best = i;
    }
    return AeAnalyticsCard(
      title: 'Weekday pattern',
      subtitle: hasRooms ? 'Average occupancy by day of week' : 'Average guests by day of week',
      icon: Icons.calendar_view_week_rounded,
      iconColor: AeDashTokens.chartSecondary,
      height: _chartHeight,
      child: ChartTransition(
        swapKey: ('wd', a.year, a.month, a.totals.rowCount),
        builder: (context, progress) => EstablishmentDssCharts.valueBars(
          values: values,
          labels: AeRegisterInsightsBuilder.weekdayShort,
          suffix: hasRooms ? '%' : '',
          maxY: hasRooms ? 100 : null,
          color: AeDashTokens.chartSecondary,
          highlightIndex: values.every((v) => v <= 0) ? null : best,
          emptyMessage: 'No guest load recorded this month yet.',
          progress: progress,
        ),
      ),
    );
  }

  Widget _monthlyCard(AeRegisterInsights a) {
    final h = a.history;
    final labels = [for (final p in h) p.label];
    final hasRooms = _rooms && a.totalRooms > 0;
    return AeAnalyticsCard(
      title: hasRooms ? 'Occupancy by month' : 'Guests by month',
      subtitle: 'Last ${h.length} month(s) with register data',
      icon: Icons.stacked_line_chart_rounded,
      iconColor: AeDashTokens.purple,
      height: _chartHeight,
      child: ChartTransition(
        swapKey: ('m', a.year, a.month, h.length),
        builder: (context, progress) => hasRooms
            ? EstablishmentDssCharts.multiLine(
                series: [
                  (label: 'Occupancy %', values: [for (final p in h) p.occupancyPct], color: AeDashTokens.purple),
                ],
                labels: labels,
                suffix: '%',
                maxY: 100,
                emptyMessage: 'No monthly occupancy yet.',
                progress: progress,
              )
            : EstablishmentDssCharts.valueBars(
                values: [for (final p in h) p.totals.checkIns.toDouble()],
                labels: labels,
                color: AeDashTokens.purple,
                emptyMessage: 'No monthly guests yet.',
                progress: progress,
              ),
      ),
    );
  }

  Widget _alosCard(AeRegisterInsights a) {
    final h = a.history;
    return AeAnalyticsCard(
      title: 'Length of stay & party size',
      subtitle: 'ALOS vs persons per room by month',
      icon: Icons.timeline_rounded,
      iconColor: AeDashTokens.success,
      height: _chartHeight,
      child: ChartTransition(
        swapKey: ('alos', a.year, a.month, h.length),
        builder: (context, progress) => EstablishmentDssCharts.multiLine(
          series: [
            (label: 'ALOS (nights)', values: [for (final p in h) p.totals.alos], color: AeDashTokens.success),
            (
              label: 'Persons / room',
              values: [for (final p in h) p.totals.avgPersonsPerRoom],
              color: AeDashTokens.chartSecondary,
            ),
          ],
          labels: [for (final p in h) p.label],
          emptyMessage: 'No stays recorded yet.',
          progress: progress,
        ),
      ),
    );
  }

  Widget _monthlyGuestsCard(AeRegisterInsights a) {
    final h = a.history;
    return AeAnalyticsCard(
      title: 'Guests by residence',
      subtitle: 'Domestic vs foreign by month',
      icon: Icons.timeline_rounded,
      iconColor: AeDashTokens.success,
      height: _chartHeight,
      child: ChartTransition(
        swapKey: ('res-m', a.year, a.month, h.length),
        builder: (context, progress) => EstablishmentDssCharts.multiLine(
          series: [
            (
              label: 'Domestic',
              values: [for (final p in h) p.totals.domesticArrivals.toDouble()],
              color: AeDashTokens.accent,
            ),
            (
              label: 'Foreign',
              values: [for (final p in h) p.totals.foreignArrivals.toDouble()],
              color: AeDashTokens.chartSecondary,
            ),
          ],
          labels: [for (final p in h) p.label],
          emptyMessage: 'No guests recorded yet.',
          progress: progress,
        ),
      ),
    );
  }

  Widget _residenceCard(AeRegisterInsights a) {
    final t = a.totals;
    return AeAnalyticsCard(
      title: 'Residence mix',
      subtitle: '${_rooms ? 'Check-ins' : 'Guests'} by DOT residence group',
      icon: Icons.public_rounded,
      iconColor: AeDashTokens.blue,
      height: _chartHeight,
      child: EstablishmentDssCharts.multiPie(
        slices: [
          (label: 'PH residents', value: t.domesticArrivals, color: AeDashTokens.accent),
          (label: 'Foreign', value: t.foreignArrivals, color: AeDashTokens.chartSecondary),
          (label: 'Overseas Filipinos', value: t.overseasFilipinoArrivals, color: AeDashTokens.chartTertiary),
          (label: 'Unspecified', value: t.unknownArrivals, color: AeDashTokens.slate),
        ],
        emptyMessage: 'No check-ins recorded this month yet.',
      ),
    );
  }

  Widget _sexCard(AeRegisterInsights a) {
    final t = a.totals;
    return AeAnalyticsCard(
      title: 'Guest sex mix',
      subtitle: 'Female / male on check-in rows',
      icon: Icons.wc_rounded,
      iconColor: AeDashTokens.chartSecondary,
      height: _chartHeight,
      child: EstablishmentDssCharts.mixPie(
        aLabel: 'Male',
        aValue: t.maleArrivals,
        aColor: AeDashTokens.info,
        bLabel: 'Female',
        bValue: t.femaleArrivals,
        bColor: _female,
      ),
    );
  }

  Widget _originsCard(String title, IconData icon, List<AeRankedOrigin> list, int total) {
    final top = list.take(8).toList();
    final max = top.isEmpty ? 1 : top.first.totals.arrivals;
    return Container(
      decoration: AeDashTokens.cardDecoration(),
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AeSectionHeader(title: title, hint: '$total arrival(s) · nights in brackets', icon: icon, color: AeDashTokens.blue),
          const SizedBox(height: 12),
          if (top.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 24),
              child: Text('None recorded this month.', textAlign: TextAlign.center, style: AeDashTokens.body(size: 12.5)),
            )
          else
            for (final o in top)
              Padding(
                padding: const EdgeInsets.only(bottom: 9),
                child: Row(
                  children: [
                    SizedBox(
                      width: 130,
                      child: Text(
                        o.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AeDashTokens.body(size: 12.5, weight: FontWeight.w600, color: AeDashTokens.text),
                      ),
                    ),
                    Expanded(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: LinearProgressIndicator(
                          value: o.totals.arrivals / max,
                          minHeight: 8,
                          backgroundColor: AeDashTokens.border,
                          color: AeDashTokens.blue,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    SizedBox(
                      width: 64,
                      child: Text(
                        '${o.totals.arrivals} (${o.totals.nights})',
                        textAlign: TextAlign.right,
                        style: AeDashTokens.body(size: 11.5),
                      ),
                    ),
                  ],
                ),
              ),
        ],
      ),
    );
  }

  Widget _roomsCard(AeRegisterInsights a, bool wide) {
    final ranked = a.rooms;
    final total = a.roomNightsTotal;
    final detail = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Room detail', style: AeDashTokens.section(size: 13.5)),
        const SizedBox(height: 2),
        Text('Nights sold · share · ADR', style: AeDashTokens.body(size: 11.5)),
        const SizedBox(height: 10),
        for (final r in ranked.take(10))
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              children: [
                SizedBox(
                  width: 64,
                  child: Text('Room ${r.roomNo}',
                      style: AeDashTokens.body(size: 12.5, weight: FontWeight.w700, color: AeDashTokens.text)),
                ),
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: total == 0 ? 0 : r.nights / total,
                      minHeight: 8,
                      backgroundColor: AeDashTokens.border,
                      color: AeDashTokens.accent,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                SizedBox(
                  width: 120,
                  child: Text(
                    '${r.nights} n${r.adr == null ? '' : ' · ${_peso(r.adr!)}'}',
                    textAlign: TextAlign.right,
                    style: AeDashTokens.body(size: 11.5),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
    final chart = SizedBox(
      height: 220,
      child: ChartTransition(
        swapKey: ('rooms', a.year, a.month, total),
        builder: (context, progress) => EstablishmentDssCharts.roomRankingBars(
          labels: [for (final r in ranked) 'R${r.roomNo}'],
          values: [for (final r in ranked) r.nights],
          progress: progress,
        ),
      ),
    );
    return Container(
      decoration: AeDashTokens.cardDecoration(),
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AeSectionHeader(
            title: 'Room ranking',
            hint: '$total room-night(s) across ${a.totalRooms} rooms · most used → least',
            icon: Icons.meeting_room_rounded,
            color: AeDashTokens.accent,
          ),
          const SizedBox(height: 12),
          if (wide)
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [Expanded(flex: 3, child: chart), const SizedBox(width: 18), Expanded(flex: 2, child: detail)],
            )
          else ...[
            chart,
            const SizedBox(height: 14),
            detail,
          ],
        ],
      ),
    );
  }

  Widget _revenueCard(AeRegisterInsights a) {
    final h = a.history;
    return AeAnalyticsCard(
      title: 'Sales by month',
      subtitle: 'Rate + charges from the register',
      icon: Icons.payments_rounded,
      iconColor: AeDashTokens.warning,
      height: _chartHeight,
      child: ChartTransition(
        swapKey: ('rev', a.year, a.month, h.length),
        builder: (context, progress) => EstablishmentDssCharts.valueBars(
          values: [for (final p in h) p.totals.grandTotalSales],
          labels: [for (final p in h) p.label],
          prefix: '₱',
          color: AeDashTokens.warning,
          highlightIndex: h.isEmpty ? null : h.length - 1,
          emptyMessage: 'No rates entered yet.',
          progress: progress,
        ),
      ),
    );
  }

  Widget _adrCard(AeRegisterInsights a) {
    final h = a.history;
    return AeAnalyticsCard(
      title: 'ADR & RevPAR (₱)',
      subtitle: 'Average daily rate vs revenue per available room',
      icon: Icons.trending_up_rounded,
      iconColor: AeDashTokens.chartTertiary,
      height: _chartHeight,
      child: ChartTransition(
        swapKey: ('adr', a.year, a.month, h.length),
        builder: (context, progress) => EstablishmentDssCharts.multiLine(
          series: [
            (label: 'ADR', values: [for (final p in h) p.adr], color: AeDashTokens.chartTertiary),
            (label: 'RevPAR', values: [for (final p in h) p.revpar], color: AeDashTokens.blue),
          ],
          labels: [for (final p in h) p.label],
          emptyMessage: 'Enter room rates to see ADR and RevPAR.',
          progress: progress,
        ),
      ),
    );
  }

  Widget _spendCard(AeRegisterInsights a) {
    final h = a.history;
    return AeAnalyticsCard(
      title: 'Spend per guest (₱)',
      subtitle: 'Sales ÷ guests by month',
      icon: Icons.trending_up_rounded,
      iconColor: AeDashTokens.chartTertiary,
      height: _chartHeight,
      child: ChartTransition(
        swapKey: ('spend', a.year, a.month, h.length),
        builder: (context, progress) => EstablishmentDssCharts.multiLine(
          series: [
            (
              label: 'Spend / guest',
              values: [
                for (final p in h)
                  p.totals.checkIns > 0 ? p.totals.grandTotalSales / p.totals.checkIns : null,
              ],
              color: AeDashTokens.chartTertiary,
            ),
          ],
          labels: [for (final p in h) p.label],
          emptyMessage: 'Enter amounts to see spend per guest.',
          progress: progress,
        ),
      ),
    );
  }

  // --------------------------------------------------------------- comparison

  Widget _comparisonCard(AeRegisterInsights a) {
    final p = a.previous;
    final ly = a.lastYear;
    final t = a.totals;
    String n(num? v, {int d = 0}) => v == null ? '—' : v.toStringAsFixed(d);
    String pc(double? v) => v == null ? '—' : '${v.toStringAsFixed(1)}%';
    String money(double? v) => v == null || v <= 0 ? '—' : _peso(v);
    final rows = <(String, String, String, String)>[
      if (_rooms) ('Occupancy', pc(a.occupancyPct), pc(p?.occupancyPct), pc(ly?.occupancyPct)),
      (_rooms ? 'Check-ins' : 'Guests', n(t.checkIns), n(p?.totals.checkIns), n(ly?.totals.checkIns)),
      if (_rooms) ...[
        ('Guest-nights', n(t.guestNights), n(p?.totals.guestNights), n(ly?.totals.guestNights)),
        ('Rooms sold', n(t.roomsOccupied), n(p?.totals.roomsOccupied), n(ly?.totals.roomsOccupied)),
        ('ALOS', n(t.alos, d: 2), n(p?.totals.alos, d: 2), n(ly?.totals.alos, d: 2)),
        ('ADR', money(a.adr), money(p?.adr), money(ly?.adr)),
        ('RevPAR', money(a.revpar), money(p?.revpar), money(ly?.revpar)),
      ],
      ('Foreign arrivals', n(t.foreignArrivals), n(p?.totals.foreignArrivals), n(ly?.totals.foreignArrivals)),
      ('Total sales', money(t.grandTotalSales), money(p?.totals.grandTotalSales), money(ly?.totals.grandTotalSales)),
    ];
    Widget cell(String s, {bool head = false, bool first = false}) => Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          child: Text(
            s,
            textAlign: first ? TextAlign.left : TextAlign.right,
            style: head
                ? AeDashTokens.body(size: 11.5, weight: FontWeight.w800, color: AeDashTokens.text)
                : AeDashTokens.body(size: 12.5, color: first ? AeDashTokens.text : AeDashTokens.muted),
          ),
        );
    final thisLabel = '${AeSheetKit.monthName(a.month).substring(0, 3)} ${a.year}${a.isCurrentMonth ? ' (MTD)' : ''}';
    return Container(
      decoration: AeDashTokens.cardDecoration(),
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const AeSectionHeader(
            title: 'Month-over-month & year-over-year',
            hint: 'Compare with the previous month and the same month last year',
            icon: Icons.compare_arrows_rounded,
            color: AeDashTokens.purple,
          ),
          const SizedBox(height: 10),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: ConstrainedBox(
              constraints: const BoxConstraints(minWidth: 520),
              child: Table(
                columnWidths: const {0: FlexColumnWidth(1.4)},
                border: TableBorder(horizontalInside: BorderSide(color: AeDashTokens.softBorder)),
                children: [
                  TableRow(
                    decoration: const BoxDecoration(color: AeDashTokens.mutedSurface),
                    children: [
                      cell('Metric', head: true, first: true),
                      cell(thisLabel, head: true),
                      cell(p == null ? 'Prev. month' : p.longLabel, head: true),
                      cell(ly == null ? 'Last year' : ly.longLabel, head: true),
                    ],
                  ),
                  for (final r in rows)
                    TableRow(children: [cell(r.$1, first: true), cell(r.$2), cell(r.$3), cell(r.$4)]),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // --------------------------------------------------------------- DSS

  Widget _recommendations(AeRegisterInsights a) {
    final locked = a.dss == AeInsightsDssLevel.locked;
    (Color, IconData) tone(AeInsightTone t) => switch (t) {
          AeInsightTone.positive => (AeDashTokens.success, Icons.trending_up_rounded),
          AeInsightTone.info => (AeDashTokens.info, Icons.lightbulb_outline_rounded),
          AeInsightTone.warning => (AeDashTokens.warning, Icons.warning_amber_rounded),
          AeInsightTone.action => (AeDashTokens.accent, Icons.edit_note_rounded),
        };
    return Container(
      decoration: BoxDecoration(
        color: AeDashTokens.cream,
        borderRadius: BorderRadius.circular(AeDashTokens.radius),
        border: Border.all(color: const Color(0xFFFED7AA)),
      ),
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(locked ? Icons.lock_outline_rounded : Icons.auto_awesome_rounded, size: 18, color: AeDashTokens.accent),
              const SizedBox(width: 8),
              Expanded(child: Text('Recommendations', style: AeDashTokens.section(size: 14))),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            switch (a.dss) {
              AeInsightsDssLevel.locked =>
                'Business tips unlock after ${AeRegisterInsightsBuilder.softDays} filled days '
                    '(now ${a.historyFilledDays}). A few days of data are too noisy to trust.',
              AeInsightsDssLevel.soft => 'Early tips from about a week of data — refine as more days are filled.',
              AeInsightsDssLevel.full => 'Based on a month or more of register data. Decision support, not fact.',
            },
            style: AeDashTokens.body(size: 12),
          ),
          const SizedBox(height: 10),
          if (a.hints.isEmpty)
            Text(
              locked ? 'Keep filling in the register daily.' : 'Nothing stands out this month — steady performance.',
              style: AeDashTokens.body(size: 12.5),
            )
          else
            for (final h in a.hints)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 30,
                      height: 30,
                      decoration: BoxDecoration(
                        color: tone(h.tone).$1.withValues(alpha: 0.14),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Icon(tone(h.tone).$2, size: 17, color: tone(h.tone).$1),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(h.title,
                              style: AeDashTokens.body(size: 13, weight: FontWeight.w700, color: AeDashTokens.text)),
                          const SizedBox(height: 2),
                          Text(h.body, style: AeDashTokens.body(size: 12.5)),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
        ],
      ),
    );
  }
}

class _Kpi extends StatelessWidget {
  const _Kpi(this.label, this.value, this.icon, this.color, {this.delta, this.hint});

  final String label;
  final String value;
  final IconData icon;
  final Color color;
  final String? delta;
  final String? hint;

  @override
  Widget build(BuildContext context) {
    final d = delta;
    final up = d != null && d.startsWith('+');
    final flat = d != null && RegExp(r'^\+?0(\.0+)?( pts|%)$').hasMatch(d);
    final dColor = flat ? AeDashTokens.muted : (up ? AeDashTokens.success : AeDashTokens.danger);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AeDashTokens.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AeDashTokens.border),
      ),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(10)),
            child: Icon(icon, color: color, size: 20),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: AeDashTokens.body(size: 11)),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: [
                    Flexible(
                      child: Text(value,
                          maxLines: 1, overflow: TextOverflow.ellipsis, style: AeDashTokens.number(size: 18)),
                    ),
                    if (d != null) ...[
                      const SizedBox(width: 6),
                      Text(d, style: AeDashTokens.body(size: 11, weight: FontWeight.w700, color: dColor)),
                    ],
                  ],
                ),
                if (hint != null)
                  Text(hint!, maxLines: 1, overflow: TextOverflow.ellipsis, style: AeDashTokens.body(size: 10.5)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

import 'package:flutter/material.dart';

import 'package:atmos_trs_system/models/establishment_stay_review.dart';
import 'package:atmos_trs_system/services/establishment_stay_review_service.dart';
import 'package:atmos_trs_system/services/establishment_stay_service.dart';
import 'package:atmos_trs_system/utils/establishment_capability.dart';
import 'package:atmos_trs_system/utils/establishment_dss_aggregates.dart';
import 'package:atmos_trs_system/utils/establishment_room_analytics.dart';
import 'package:atmos_trs_system/utils/establishment_room_grid.dart';
import 'package:atmos_trs_system/widgets/chart_transition.dart';
import 'package:atmos_trs_system/widgets/establishment_dash_tokens.dart';
import 'package:atmos_trs_system/widgets/establishment_dashboard_components.dart';
import 'package:atmos_trs_system/widgets/establishment_dss_charts.dart';

/// Insights DSS board: trends, guest mix, busy days, room analytics.
/// Live room status lives on Rooms; guest reviews on Reviews.
class EstablishmentInsightsBoard extends StatefulWidget {
  const EstablishmentInsightsBoard({
    super.key,
    required this.establishmentId,
    required this.copy,
    required this.isLodging,
    required this.dss,
    this.allStays = const [],
    this.roomCount = 0,
    this.roomInventory = const {},
  });

  final String establishmentId;
  final EstablishmentPackCopy copy;
  final bool isLodging;
  final EstablishmentDssSnapshot dss;
  final List<EstablishmentStayRequest> allStays;
  final int roomCount;
  final Map<String, EstablishmentRoomInfo> roomInventory;

  @override
  State<EstablishmentInsightsBoard> createState() =>
      _EstablishmentInsightsBoardState();
}

class _EstablishmentInsightsBoardState
    extends State<EstablishmentInsightsBoard> {
  static const double _chartHeight = 210;
  static const Color _female = Color(0xFFEC4899);

  EstablishmentInsightsWindow _window = EstablishmentInsightsWindow.days30;
  TrendRange _trendRange = TrendRange.days14;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, c) {
        final w = c.maxWidth;
        final pad = w < 600 ? 14.0 : (w < 1000 ? 18.0 : 24.0);
        final gap = w < 600 ? 12.0 : 18.0;
        final wide = w - pad * 2 >= 820;
        final demo = widget.dss.demographics;

        Widget pair(Widget a, Widget b) {
          if (!wide) {
            return Column(
              children: [
                a,
                SizedBox(height: gap),
                b,
              ],
            );
          }
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: a),
              SizedBox(width: gap),
              Expanded(child: b),
            ],
          );
        }

        return ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: EdgeInsets.only(bottom: pad + 12),
          children: [
            AePageHero(
              icon: Icons.insights_rounded,
              title: 'Decision support',
              subtitle: widget.isLodging
                  ? 'Confirmed stays, guest mix, busy days, and room analytics '
                        '(room tips unlock within ~1 week of data).'
                  : 'Confirmed ${widget.copy.opsNoun}s, guest mix, and busy days.',
              art: const _HeroBarsArt(),
              flush: true,
            ),
            Padding(
              padding: EdgeInsets.fromLTRB(pad, gap, pad, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  pair(_trendCard(), _partySizeCard(demo)),
                  if (widget.isLodging && widget.roomCount > 0) ...[
                    SizedBox(height: gap),
                    _roomAnalyticsSection(wide),
                  ],
                  SizedBox(height: gap),
                  pair(
                    _mixCard(
                      title: 'Guest sex mix',
                      icon: Icons.wc_rounded,
                      iconColor: AeDashTokens.chartSecondary,
                      art: AeEmptyArt.people,
                      aLabel: 'Male',
                      aValue: demo.male,
                      aColor: AeDashTokens.info,
                      bLabel: 'Female',
                      bValue: demo.female,
                      bColor: _female,
                    ),
                    _mixCard(
                      title: 'Residency mix',
                      icon: Icons.public_rounded,
                      iconColor: AeDashTokens.blue,
                      art: AeEmptyArt.globe,
                      aLabel: 'Filipino',
                      aValue: demo.filipino,
                      aColor: AeDashTokens.accent,
                      bLabel: 'Foreign',
                      bValue: demo.foreign,
                      bColor: AeDashTokens.chartSecondary,
                    ),
                  ),
                  SizedBox(height: gap),
                  pair(_weekdayCard(), _calendarCard()),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _trendCard() {
    final series = EstablishmentDssAggregates.trend(widget.allStays, _trendRange);
    final total = series.total;
    return AeAnalyticsCard(
      title: widget.copy.chartTitle,
      subtitle: '$total confirmed ${widget.copy.opsNoun}${total == 1 ? '' : 's'}',
      icon: _trendRange.isCalendar
          ? Icons.bar_chart_rounded
          : Icons.show_chart_rounded,
      height: _chartHeight,
      trailing: AeDropdownAction<TrendRange>(
        value: _trendRange,
        leading: Icons.calendar_today_outlined,
        options: {
          for (final r in TrendRange.values) r: r.label,
        },
        onChanged: (r) => setState(() => _trendRange = r),
      ),
      child: ChartTransition(
        swapKey: (_trendRange, total == 0),
        builder: (context, progress) => total == 0
            ? AeIllustratedEmpty(
                art: AeEmptyArt.chart,
                title:
                    'No confirmed ${widget.copy.opsNoun}s in this period yet.',
                message:
                    'Once guests confirm their ${widget.copy.opsNoun}, '
                    'the chart will appear here.',
              )
            : _trendRange.isCalendar
                ? EstablishmentDssCharts.staysTrendBars(
                    values: series.values,
                    labels: series.labels,
                    progress: progress,
                  )
                : EstablishmentDssCharts.staysTrendLine(
                    values: series.values,
                    labels: series.labels,
                    progress: progress,
                  ),
      ),
    );
  }

  Widget _partySizeCard(EstablishmentDssDemographics demo) {
    final avg = demo.avgParty;
    return AeAnalyticsCard(
      title: 'Avg party size',
      subtitle: 'Confirmed this month',
      icon: Icons.groups_rounded,
      height: _chartHeight,
      child: avg == 0
          ? AeIllustratedEmpty(
              art: AeEmptyArt.people,
              title: 'No confirmed ${widget.copy.opsNoun}s this month yet.',
              message: 'Party size appears once guests are confirmed.',
            )
          : Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  avg.toStringAsFixed(avg == avg.roundToDouble() ? 0 : 1),
                  style: AeDashTokens.number(
                    size: 48,
                    color: AeDashTokens.accent,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  '${demo.parties} ${widget.copy.opsNoun}'
                  '${demo.parties == 1 ? '' : 's'} · ${demo.guests} guests',
                  textAlign: TextAlign.center,
                  style: AeDashTokens.body(size: 12.5),
                ),
              ],
            ),
    );
  }

  Widget _mixCard({
    required String title,
    required IconData icon,
    required Color iconColor,
    required AeEmptyArt art,
    required String aLabel,
    required int aValue,
    required Color aColor,
    required String bLabel,
    required int bValue,
    required Color bColor,
  }) {
    return AeAnalyticsCard(
      title: title,
      subtitle: 'Confirmed this month · DAE demographics',
      icon: icon,
      iconColor: iconColor,
      height: _chartHeight,
      child: aValue + bValue <= 0
          ? AeIllustratedEmpty(
              art: art,
              title: 'No demographic data for this month yet.',
              message: 'The mix appears once guests confirm their stay.',
            )
          : EstablishmentDssCharts.mixPie(
              aLabel: aLabel,
              aValue: aValue,
              aColor: aColor,
              bLabel: bLabel,
              bValue: bValue,
              bColor: bColor,
            ),
    );
  }

  Widget _weekdayCard() {
    final values = widget.dss.weekdayGuests;
    return AeAnalyticsCard(
      title: 'Peak load by weekday',
      subtitle: 'Guests this month',
      icon: Icons.bar_chart_rounded,
      iconColor: AeDashTokens.warning,
      height: _chartHeight,
      child: values.every((v) => v == 0)
          ? const AeIllustratedEmpty(
              art: AeEmptyArt.weekday,
              title: 'No guest load recorded this month yet.',
              message: 'Busy weekdays show up after confirmed stays.',
            )
          : ChartTransition(
              swapKey: 'weekday',
              builder: (context, progress) =>
                  EstablishmentDssCharts.weekdayBars(values, progress: progress),
            ),
    );
  }

  Widget _calendarCard() {
    final now = DateTime.now();
    final daysInMonth = DateTime(now.year, now.month + 1, 0).day;
    final active = widget.dss.calendarDays;
    return AeAnalyticsCard(
      title: 'Active days',
      subtitle: widget.copy.calendarSubtitle,
      icon: Icons.calendar_month_rounded,
      iconColor: AeDashTokens.success,
      height: _chartHeight,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: SingleChildScrollView(
              child: Wrap(
                spacing: 7,
                runSpacing: 7,
                children: [
                  for (var d = 1; d <= daysInMonth; d++)
                    Container(
                      width: 32,
                      height: 32,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: active.contains(d)
                            ? AeDashTokens.accent
                            : const Color(0xFFF1F5F9),
                        borderRadius: BorderRadius.circular(9),
                        border: Border.all(
                          color: active.contains(d)
                              ? AeDashTokens.accent
                              : AeDashTokens.softBorder,
                        ),
                      ),
                      child: Text(
                        '$d',
                        style: AeDashTokens.body(
                          size: 11,
                          color: active.contains(d)
                              ? Colors.white
                              : AeDashTokens.muted,
                          weight: FontWeight.w700,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              const Icon(
                Icons.event_available_rounded,
                size: 16,
                color: AeDashTokens.accent,
              ),
              const SizedBox(width: 6),
              Text(
                '${active.length} day(s) with confirmed '
                '${widget.copy.opsNoun}s',
                style: AeDashTokens.body(
                  size: 12,
                  color: AeDashTokens.text,
                  weight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _roomAnalyticsSection(bool wide) {
    return StreamBuilder<EstablishmentStayReviewSummary>(
      stream: widget.establishmentId.isEmpty
          ? Stream.value(EstablishmentStayReviewSummary.empty)
          : EstablishmentStayReviewService.watchForEstablishment(
              widget.establishmentId,
            ),
      builder: (context, snap) {
        final reviews = snap.data?.reviews ?? const <EstablishmentStayReview>[];
        final analytics = EstablishmentRoomAnalyticsBuilder.build(
          stays: widget.allStays,
          roomCount: widget.roomCount,
          inventory: widget.roomInventory,
          reviews: reviews,
          window: _window,
        );

        final rankingTop = analytics.ranking.take(12).toList();
        final occLabel = analytics.periodOccupancyPct == null
            ? '—'
            : '${analytics.periodOccupancyPct!.round()}%';

        final ranking = _subChart(
          title: 'Rooms used most → least',
          subtitle: 'Room-nights · ${_window.label}',
          child: ChartTransition(
            swapKey: ('ranking', _window, rankingTop.length),
            builder: (context, progress) =>
                EstablishmentDssCharts.roomRankingBars(
              labels: [for (final r in rankingTop) 'R${r.roomId}'],
              values: [for (final r in rankingTop) r.roomNights],
              progress: progress,
            ),
          ),
        );
        final occupancy = _subChart(
          title: 'Daily occupancy %',
          subtitle: 'Room-nights ÷ rooms available',
          child: ChartTransition(
            swapKey: ('occupancy', _window),
            builder: (context, progress) =>
                EstablishmentDssCharts.occupancyPctTrend(
              pctValues: analytics.occupancyPctByDay,
              labels: analytics.dayLabels,
              progress: progress,
            ),
          ),
        );

        return AePanelCard(
          title: 'Room analytics',
          subtitle:
              'Room-nights feed DAE guest-nights / rooms occupied. '
              'DSS tips stay locked until you have ~1 week of confirmed stays.',
          icon: Icons.meeting_room_rounded,
          trailing: AeDropdownAction<EstablishmentInsightsWindow>(
            value: _window,
            leading: Icons.calendar_today_outlined,
            options: {
              for (final w in EstablishmentInsightsWindow.values) w: w.label,
            },
            onChanged: (w) => setState(() => _window = w),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _kpiRow(analytics, occLabel),
              const SizedBox(height: 18),
              if (wide)
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: ranking),
                    const SizedBox(width: 18),
                    Expanded(child: occupancy),
                  ],
                )
              else ...[
                ranking,
                const SizedBox(height: 18),
                occupancy,
              ],
              const SizedBox(height: 18),
              _rankingList(analytics),
              const SizedBox(height: 12),
              _dssSection(analytics),
            ],
          ),
        );
      },
    );
  }

  Widget _subChart({
    required String title,
    required String subtitle,
    required Widget child,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(title, style: AeDashTokens.section(size: 13.5)),
        const SizedBox(height: 2),
        Text(subtitle, style: AeDashTokens.body(size: 11.5)),
        const SizedBox(height: 10),
        SizedBox(height: 200, child: child),
      ],
    );
  }

  Widget _kpiRow(EstablishmentRoomAnalytics a, String occLabel) {
    return AeResponsiveGrid(
      minItemWidth: 150,
      spacing: 12,
      children: [
        _MiniKpi(
          'Room-nights',
          '${a.totalRoomNights}',
          Icons.nights_stay_rounded,
          AeDashTokens.accent,
        ),
        _MiniKpi(
          'Guest-nights',
          '${a.guestNights}',
          Icons.people_alt_rounded,
          AeDashTokens.chartSecondary,
        ),
        _MiniKpi(
          'Avg stay',
          a.avgLengthOfStay == 0
              ? '—'
              : '${a.avgLengthOfStay.toStringAsFixed(1)} n',
          Icons.hotel_rounded,
          AeDashTokens.success,
        ),
        _MiniKpi(
          'Occ. rate',
          occLabel,
          Icons.donut_large_rounded,
          AeDashTokens.purple,
        ),
      ],
    );
  }

  Widget _rankingList(EstablishmentRoomAnalytics analytics) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AeDashTokens.softBorder),
      ),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Room ranking detail', style: AeDashTokens.section(size: 14)),
          const SizedBox(height: 2),
          Text(
            'Most used → least · share of room-nights',
            style: AeDashTokens.body(size: 11.5),
          ),
          const SizedBox(height: 10),
          if (analytics.ranking.every((r) => r.roomNights == 0))
            Text(
              'No room numbers on confirmed stays yet — assign rooms at desk.',
              style: AeDashTokens.body(size: 12.5),
            )
          else
            for (final r in analytics.ranking.take(10))
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  children: [
                    SizedBox(
                      width: 72,
                      child: Text(
                        'Room ${r.roomId}',
                        style: AeDashTokens.body(
                          size: 12.5,
                          weight: FontWeight.w700,
                          color: AeDashTokens.text,
                        ),
                      ),
                    ),
                    Expanded(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: LinearProgressIndicator(
                          value: r.shareOf(analytics.totalRoomNights),
                          minHeight: 8,
                          backgroundColor: AeDashTokens.border,
                          color: AeDashTokens.accent,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '${r.roomNights} rn',
                      style: AeDashTokens.body(size: 11.5),
                    ),
                  ],
                ),
              ),
        ],
      ),
    );
  }

  Widget _dssSection(EstablishmentRoomAnalytics analytics) {
    final locked = analytics.dssLevel == EstablishmentRoomDssLevel.locked;
    return Container(
      decoration: BoxDecoration(
        color: locked ? const Color(0xFFF8FAFC) : AeDashTokens.cream,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: locked ? AeDashTokens.softBorder : const Color(0xFFFED7AA),
        ),
      ),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(
                locked ? Icons.lock_outline : Icons.lightbulb_outline,
                size: 18,
                color: locked ? AeDashTokens.muted : AeDashTokens.accent,
              ),
              const SizedBox(width: 8),
              Text(
                'Room recommendations',
                style: AeDashTokens.section(size: 14),
              ),
            ],
          ),
          const SizedBox(height: 6),
          if (locked)
            Text(
              'Need about 7 days with stays and 15+ room-nights before DSS '
              'tips unlock (now: ${analytics.distinctStayDays} active day'
              '${analytics.distinctStayDays == 1 ? '' : 's'}, '
              '${analytics.totalRoomNights} room-nights). '
              'One day of data is too noisy to trust.',
              style: AeDashTokens.body(size: 12.5),
            )
          else ...[
            Text(
              analytics.dssLevel == EstablishmentRoomDssLevel.full
                  ? 'Based on ~1 month of activity — treat as decision support, not fact.'
                  : 'Soft tips from ~1 week of activity — refine as more stays land.',
              style: AeDashTokens.body(size: 12),
            ),
            const SizedBox(height: 10),
            if (analytics.underusedHints.isEmpty)
              Text(
                'No strongly underused rooms vs peers in this window.',
                style: AeDashTokens.body(size: 12.5),
              )
            else
              for (final h in analytics.underusedHints) ...[
                Text(
                  h.roomLabel,
                  style: AeDashTokens.body(
                    size: 13,
                    weight: FontWeight.w700,
                    color: AeDashTokens.text,
                  ),
                ),
                const SizedBox(height: 4),
                for (final reason in h.reasons)
                  Padding(
                    padding: const EdgeInsets.only(left: 8, bottom: 6),
                    child: Text(
                      '• $reason',
                      style: AeDashTokens.body(size: 12.5),
                    ),
                  ),
                const SizedBox(height: 6),
              ],
          ],
        ],
      ),
    );
  }
}

class _HeroBarsArt extends StatelessWidget {
  const _HeroBarsArt();

  @override
  Widget build(BuildContext context) {
    Widget bar(double h, double a) => Container(
      width: 16,
      height: h,
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: a),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(5)),
      ),
    );
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        bar(28, 0.55),
        const SizedBox(width: 7),
        bar(46, 0.7),
        const SizedBox(width: 7),
        bar(36, 0.6),
        const SizedBox(width: 7),
        bar(62, 0.85),
      ],
    );
  }
}

class _MiniKpi extends StatelessWidget {
  const _MiniKpi(this.label, this.value, this.icon, this.color);

  final String label;
  final String value;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: color, size: 19),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(value, style: AeDashTokens.number(size: 18)),
                Text(
                  label,
                  style: AeDashTokens.body(size: 11),
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
}

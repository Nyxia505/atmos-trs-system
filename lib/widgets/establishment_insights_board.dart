import 'package:flutter/material.dart';

import 'package:atmos_trs_system/models/establishment_stay_review.dart';
import 'package:atmos_trs_system/services/establishment_stay_review_service.dart';
import 'package:atmos_trs_system/services/establishment_stay_service.dart';
import 'package:atmos_trs_system/utils/establishment_capability.dart';
import 'package:atmos_trs_system/utils/establishment_dss_aggregates.dart';
import 'package:atmos_trs_system/utils/establishment_room_analytics.dart';
import 'package:atmos_trs_system/utils/establishment_room_grid.dart';
import 'package:atmos_trs_system/widgets/establishment_dash_tokens.dart';
import 'package:atmos_trs_system/widgets/establishment_dss_charts.dart';

/// Insights DSS board: trends, room analytics, demographics, gated room DSS.
class EstablishmentInsightsBoard extends StatefulWidget {
  const EstablishmentInsightsBoard({
    super.key,
    required this.establishmentId,
    required this.copy,
    required this.isLodging,
    required this.dss,
    this.roomStats,
    this.allStays = const [],
    this.roomCount = 0,
    this.roomInventory = const {},
  });

  final String establishmentId;
  final EstablishmentPackCopy copy;
  final bool isLodging;
  final EstablishmentDssSnapshot dss;
  final EstablishmentRoomStats? roomStats;
  final List<EstablishmentStayRequest> allStays;
  final int roomCount;
  final Map<String, EstablishmentRoomInfo> roomInventory;

  @override
  State<EstablishmentInsightsBoard> createState() =>
      _EstablishmentInsightsBoardState();
}

class _EstablishmentInsightsBoardState extends State<EstablishmentInsightsBoard> {
  EstablishmentInsightsWindow _window = EstablishmentInsightsWindow.days30;

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= 960;
    final demo = widget.dss.demographics;

    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
      children: [
        Text('Decision support', style: AeDashTokens.heading(size: 18)),
        const SizedBox(height: 4),
        Text(
          widget.isLodging
              ? 'Confirmed stays, room-nights, guest mix, and gated room tips '
                  '(unlocks with ~1 week of data).'
              : 'Live view of confirmed ${widget.copy.opsNoun}s, guest mix, and reviews.',
          style: AeDashTokens.body(size: 12.5),
        ),
        const SizedBox(height: 14),
        if (wide)
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                flex: 3,
                child: EstablishmentDssCharts.panel(
                  title: widget.copy.chartTitle,
                  subtitle: 'Last 14 days',
                  height: 220,
                  child: EstablishmentDssCharts.staysTrendLine(
                    values: widget.dss.staysTrend,
                    labels: widget.dss.dayLabels,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                flex: 2,
                child: _occupancyOrPartyPanel(demo),
              ),
            ],
          )
        else ...[
          EstablishmentDssCharts.panel(
            title: widget.copy.chartTitle,
            subtitle: 'Last 14 days',
            height: 200,
            child: EstablishmentDssCharts.staysTrendLine(
              values: widget.dss.staysTrend,
              labels: widget.dss.dayLabels,
            ),
          ),
          const SizedBox(height: 12),
          _occupancyOrPartyPanel(demo),
        ],
        if (widget.isLodging && widget.roomCount > 0) ...[
          const SizedBox(height: 20),
          _roomAnalyticsSection(wide),
        ],
        const SizedBox(height: 12),
        if (wide)
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: EstablishmentDssCharts.panel(
                  title: 'Guest sex mix',
                  subtitle: 'Confirmed this month · DAE demographics',
                  height: 180,
                  child: EstablishmentDssCharts.mixPie(
                    aLabel: 'Male',
                    aValue: demo.male,
                    aColor: AeDashTokens.info,
                    bLabel: 'Female',
                    bValue: demo.female,
                    bColor: const Color(0xFFEC4899),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: EstablishmentDssCharts.panel(
                  title: 'Residency mix',
                  subtitle: 'Confirmed this month · DAE demographics',
                  height: 180,
                  child: EstablishmentDssCharts.mixPie(
                    aLabel: 'Filipino',
                    aValue: demo.filipino,
                    aColor: AeDashTokens.accent,
                    bLabel: 'Foreign',
                    bValue: demo.foreign,
                    bColor: AeDashTokens.chartSecondary,
                  ),
                ),
              ),
            ],
          )
        else ...[
          EstablishmentDssCharts.panel(
            title: 'Guest sex mix',
            subtitle: 'Confirmed this month · DAE demographics',
            height: 180,
            child: EstablishmentDssCharts.mixPie(
              aLabel: 'Male',
              aValue: demo.male,
              aColor: AeDashTokens.info,
              bLabel: 'Female',
              bValue: demo.female,
              bColor: const Color(0xFFEC4899),
            ),
          ),
          const SizedBox(height: 12),
          EstablishmentDssCharts.panel(
            title: 'Residency mix',
            subtitle: 'Confirmed this month · DAE demographics',
            height: 180,
            child: EstablishmentDssCharts.mixPie(
              aLabel: 'Filipino',
              aValue: demo.filipino,
              aColor: AeDashTokens.accent,
              bLabel: 'Foreign',
              bValue: demo.foreign,
              bColor: AeDashTokens.chartSecondary,
            ),
          ),
        ],
        const SizedBox(height: 12),
        if (wide)
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: EstablishmentDssCharts.panel(
                  title: 'Peak load by weekday',
                  subtitle: 'Guests this month',
                  height: 180,
                  child: EstablishmentDssCharts.weekdayBars(
                    widget.dss.weekdayGuests,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(child: _calendarCard()),
            ],
          )
        else ...[
          EstablishmentDssCharts.panel(
            title: 'Peak load by weekday',
            subtitle: 'Guests this month',
            height: 180,
            child: EstablishmentDssCharts.weekdayBars(widget.dss.weekdayGuests),
          ),
          const SizedBox(height: 12),
          _calendarCard(),
        ],
        const SizedBox(height: 12),
        _reviewsSection(),
      ],
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

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Room analytics', style: AeDashTokens.heading(size: 16)),
            const SizedBox(height: 4),
            Text(
              'Room-nights feed DAE guest-nights / rooms occupied. '
              'DSS tips stay locked until you have ~1 week of confirmed stays.',
              style: AeDashTokens.body(size: 12),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final w in EstablishmentInsightsWindow.values)
                  ChoiceChip(
                    label: Text(w.label),
                    selected: _window == w,
                    selectedColor: AeDashTokens.accent.withValues(alpha: 0.2),
                    onSelected: (_) => setState(() => _window = w),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            _kpiRow(analytics, occLabel),
            const SizedBox(height: 12),
            if (wide)
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: EstablishmentDssCharts.panel(
                      title: 'Rooms used most → least',
                      subtitle: 'Room-nights · ${_window.label}',
                      height: 220,
                      child: EstablishmentDssCharts.roomRankingBars(
                        labels: [
                          for (final r in rankingTop) 'R${r.roomId}',
                        ],
                        values: [
                          for (final r in rankingTop) r.roomNights,
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: EstablishmentDssCharts.panel(
                      title: 'Daily occupancy %',
                      subtitle: 'Room-nights ÷ rooms available',
                      height: 220,
                      child: EstablishmentDssCharts.occupancyPctTrend(
                        pctValues: analytics.occupancyPctByDay,
                        labels: analytics.dayLabels,
                      ),
                    ),
                  ),
                ],
              )
            else ...[
              EstablishmentDssCharts.panel(
                title: 'Rooms used most → least',
                subtitle: 'Room-nights · ${_window.label}',
                height: 200,
                child: EstablishmentDssCharts.roomRankingBars(
                  labels: [for (final r in rankingTop) 'R${r.roomId}'],
                  values: [for (final r in rankingTop) r.roomNights],
                ),
              ),
              const SizedBox(height: 12),
              EstablishmentDssCharts.panel(
                title: 'Daily occupancy %',
                subtitle: 'Room-nights ÷ rooms available',
                height: 200,
                child: EstablishmentDssCharts.occupancyPctTrend(
                  pctValues: analytics.occupancyPctByDay,
                  labels: analytics.dayLabels,
                ),
              ),
            ],
            const SizedBox(height: 12),
            _rankingList(analytics),
            const SizedBox(height: 12),
            _dssSection(analytics),
          ],
        );
      },
    );
  }

  Widget _kpiRow(EstablishmentRoomAnalytics a, String occLabel) {
    return LayoutBuilder(
      builder: (context, c) {
        final items = [
          _MiniKpi('Room-nights', '${a.totalRoomNights}'),
          _MiniKpi('Guest-nights', '${a.guestNights}'),
          _MiniKpi('Avg stay', a.avgLengthOfStay == 0
              ? '—'
              : '${a.avgLengthOfStay.toStringAsFixed(1)} n'),
          _MiniKpi('Occ. rate', occLabel),
        ];
        if (c.maxWidth > 640) {
          return Row(
            children: [
              for (var i = 0; i < items.length; i++) ...[
                if (i > 0) const SizedBox(width: 8),
                Expanded(child: items[i]),
              ],
            ],
          );
        }
        return Column(
          children: [
            Row(
              children: [
                Expanded(child: items[0]),
                const SizedBox(width: 8),
                Expanded(child: items[1]),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(child: items[2]),
                const SizedBox(width: 8),
                Expanded(child: items[3]),
              ],
            ),
          ],
        );
      },
    );
  }

  Widget _rankingList(EstablishmentRoomAnalytics analytics) {
    return Container(
      decoration: AeDashTokens.cardDecoration(),
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
    final locked =
        analytics.dssLevel == EstablishmentRoomDssLevel.locked;
    return Container(
      decoration: AeDashTokens.cardDecoration(),
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

  Widget _occupancyOrPartyPanel(EstablishmentDssDemographics demo) {
    if (widget.isLodging && widget.roomStats != null) {
      return EstablishmentDssCharts.panel(
        title: 'Live occupancy',
        subtitle: 'Free vs occupied rooms',
        height: 220,
        child: EstablishmentDssCharts.occupancyGauge(
          occupied: widget.roomStats!.occupied,
          free: widget.roomStats!.free,
          total: widget.roomStats!.total,
        ),
      );
    }
    final avg = demo.avgParty;
    return Container(
      decoration: AeDashTokens.cardDecoration(),
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Avg party size', style: AeDashTokens.section(size: 14)),
          const SizedBox(height: 2),
          Text('Confirmed this month', style: AeDashTokens.body(size: 11.5)),
          const SizedBox(height: 24),
          Text(
            avg == 0
                ? '—'
                : avg.toStringAsFixed(avg == avg.roundToDouble() ? 0 : 1),
            textAlign: TextAlign.center,
            style: AeDashTokens.number(size: 48, color: AeDashTokens.accent),
          ),
          const SizedBox(height: 8),
          Text(
            '${demo.parties} ${widget.copy.opsNoun}'
            '${demo.parties == 1 ? '' : 's'} · ${demo.guests} guests',
            textAlign: TextAlign.center,
            style: AeDashTokens.body(size: 12.5),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _calendarCard() {
    final now = DateTime.now();
    final daysInMonth = DateTime(now.year, now.month + 1, 0).day;
    return Container(
      decoration: AeDashTokens.cardDecoration(),
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Active days', style: AeDashTokens.section(size: 14)),
          const SizedBox(height: 2),
          Text(
            widget.copy.calendarSubtitle,
            style: AeDashTokens.body(size: 11.5),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (var d = 1; d <= daysInMonth; d++)
                Container(
                  width: 28,
                  height: 28,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: widget.dss.calendarDays.contains(d)
                        ? AeDashTokens.accent
                        : AeDashTokens.background,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: widget.dss.calendarDays.contains(d)
                          ? AeDashTokens.accent
                          : AeDashTokens.border,
                    ),
                  ),
                  child: Text(
                    '$d',
                    style: AeDashTokens.body(
                      size: 10,
                      color: widget.dss.calendarDays.contains(d)
                          ? Colors.white
                          : AeDashTokens.muted,
                      weight: FontWeight.w700,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            '${widget.dss.calendarDays.length} day(s) with confirmed '
            '${widget.copy.opsNoun}s',
            style: AeDashTokens.body(size: 11.5),
          ),
        ],
      ),
    );
  }

  Widget _reviewsSection() {
    if (widget.establishmentId.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: AeDashTokens.cardDecoration(),
        child: Text('Sign in to load reviews.', style: AeDashTokens.body()),
      );
    }
    return StreamBuilder<EstablishmentStayReviewSummary>(
      stream: EstablishmentStayReviewService.watchForEstablishment(
        widget.establishmentId,
      ),
      builder: (context, snap) {
        final summary = snap.data ?? EstablishmentStayReviewSummary.empty;
        final reviews = summary.reviews;
        final buckets =
            EstablishmentDssAggregates.reviewStarBuckets(reviews);

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            EstablishmentDssCharts.panel(
              title: 'Review ratings',
              subtitle: summary.reviewCount == 0
                  ? 'No reviews yet'
                  : 'Avg ${(summary.averageOverall).toStringAsFixed(1)} · '
                      '${summary.reviewCount} review'
                      '${summary.reviewCount == 1 ? '' : 's'}',
              height: 160,
              child: EstablishmentDssCharts.reviewStarsBars(buckets),
            ),
            if (reviews.isNotEmpty) ...[
              const SizedBox(height: 12),
              Container(
                decoration: AeDashTokens.cardDecoration(),
                padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text('Recent comments', style: AeDashTokens.section()),
                    const SizedBox(height: 8),
                    for (final r in reviews.take(6)) ...[
                      Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Text(
                                  r.authorName,
                                  style: AeDashTokens.body(
                                    size: 12.5,
                                    color: AeDashTokens.text,
                                    weight: FontWeight.w700,
                                  ),
                                ),
                                const Spacer(),
                                Text(
                                  '${r.averageRating.toStringAsFixed(1)}★',
                                  style: AeDashTokens.body(
                                    size: 12,
                                    color: AeDashTokens.accent,
                                    weight: FontWeight.w700,
                                  ),
                                ),
                              ],
                            ),
                            if (r.roomNumbers.isNotEmpty) ...[
                              const SizedBox(height: 2),
                              Text(
                                'Room ${r.roomNumbers.join(', ')} · '
                                'hotel ${r.hotelRating.toStringAsFixed(0)}★ · '
                                'room ${r.roomRating.toStringAsFixed(0)}★',
                                style: AeDashTokens.body(size: 11.5),
                              ),
                            ],
                            if (r.comment.isNotEmpty) ...[
                              const SizedBox(height: 2),
                              Text(
                                r.comment,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: AeDashTokens.body(size: 12.5),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ],
        );
      },
    );
  }
}

class _MiniKpi extends StatelessWidget {
  const _MiniKpi(this.label, this.value);

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      decoration: AeDashTokens.cardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(value, style: AeDashTokens.number(size: 20)),
          const SizedBox(height: 2),
          Text(label, style: AeDashTokens.body(size: 11)),
        ],
      ),
    );
  }
}

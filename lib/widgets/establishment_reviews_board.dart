import 'package:flutter/material.dart';

import 'package:atmos_trs_system/models/establishment_stay_review.dart';
import 'package:atmos_trs_system/services/establishment_stay_review_service.dart';
import 'package:atmos_trs_system/utils/establishment_dss_aggregates.dart';
import 'package:atmos_trs_system/widgets/chart_transition.dart';
import 'package:atmos_trs_system/widgets/establishment_dash_tokens.dart';
import 'package:atmos_trs_system/widgets/establishment_dashboard_components.dart';
import 'package:atmos_trs_system/widgets/establishment_dss_charts.dart';
import 'package:atmos_trs_system/widgets/establishment_stay_tables.dart';

/// Reviews tab: rating summary, star distribution, per-room ratings, and the
/// full guest comment feed with star filter.
class EstablishmentReviewsBoard extends StatefulWidget {
  const EstablishmentReviewsBoard({
    super.key,
    required this.establishmentId,
    required this.isLodging,
  });

  final String establishmentId;
  final bool isLodging;

  @override
  State<EstablishmentReviewsBoard> createState() =>
      _EstablishmentReviewsBoardState();
}

class _EstablishmentReviewsBoardState extends State<EstablishmentReviewsBoard> {
  static const int _pageSize = 10;
  static const int _loadLimit = 300;

  /// 0 = all, otherwise rounded average star rating.
  int _stars = 0;
  int _visible = _pageSize;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<EstablishmentStayReviewSummary>(
      stream: widget.establishmentId.isEmpty
          ? Stream.value(EstablishmentStayReviewSummary.empty)
          : EstablishmentStayReviewService.watchForEstablishment(
              widget.establishmentId,
              limit: _loadLimit,
            ),
      builder: (context, snap) {
        final summary = snap.data ?? EstablishmentStayReviewSummary.empty;
        return LayoutBuilder(
          builder: (context, c) {
            final w = c.maxWidth;
            final pad = w < 600 ? 14.0 : (w < 1000 ? 18.0 : 24.0);
            final gap = w < 600 ? 12.0 : 18.0;
            final wide = w - pad * 2 >= 820;
            return ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: EdgeInsets.only(bottom: pad + 12),
              children: [
                AePageHero(
                  icon: Icons.star_rounded,
                  title: 'Reviews',
                  subtitle: 'What guests say after they check out.',
                  flush: true,
                ),
                Padding(
                  padding: EdgeInsets.fromLTRB(pad, gap, pad, 0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _stats(summary, gap),
                      SizedBox(height: gap),
                      if (summary.reviewCount == 0)
                        _emptyCard()
                      else ...[
                        _charts(summary, gap, wide),
                        SizedBox(height: gap),
                        _feed(summary.reviews),
                      ],
                    ],
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  String _avg(double v, int count) => count == 0 ? '—' : v.toStringAsFixed(1);

  Widget _stats(EstablishmentStayReviewSummary s, double gap) {
    return AeResponsiveGrid(
      minItemWidth: 150,
      spacing: gap,
      children: [
        AeStatCard(
          label: 'Overall rating',
          value: _avg(s.averageOverall, s.reviewCount),
          icon: Icons.star_rounded,
          color: AeDashTokens.warning,
        ),
        AeStatCard(
          label: widget.isLodging ? 'Hotel rating' : 'Place rating',
          value: _avg(s.averageHotelRating, s.reviewCount),
          icon: Icons.apartment_rounded,
          color: AeDashTokens.accent,
        ),
        AeStatCard(
          label: widget.isLodging ? 'Room rating' : 'Service rating',
          value: _avg(s.averageRoomRating, s.reviewCount),
          icon: Icons.king_bed_rounded,
          color: AeDashTokens.purple,
        ),
        AeStatCard(
          label: 'Total reviews',
          value: '${s.reviewCount}',
          icon: Icons.forum_rounded,
          color: AeDashTokens.blue,
        ),
      ],
    );
  }

  Widget _emptyCard() {
    return const AePanelCard(
      title: 'Guest reviews',
      icon: Icons.forum_rounded,
      iconColor: AeDashTokens.warning,
      child: SizedBox(
        height: 220,
        child: AeIllustratedEmpty(
          art: AeEmptyArt.review,
          title: 'No guest reviews yet.',
          message: 'Guests are asked for a review after checkout. '
              'Their ratings and comments will appear here.',
        ),
      ),
    );
  }

  Widget _charts(EstablishmentStayReviewSummary s, double gap, bool wide) {
    final distribution = AeAnalyticsCard(
      title: 'Star distribution',
      subtitle: 'Average of hotel + room rating per review',
      icon: Icons.bar_chart_rounded,
      iconColor: AeDashTokens.warning,
      child: ChartTransition(
        swapKey: 'stars',
        builder: (context, progress) => EstablishmentDssCharts.reviewStarsBars(
          EstablishmentDssAggregates.reviewStarBuckets(s.reviews),
          progress: progress,
        ),
      ),
    );
    if (!widget.isLodging) return distribution;
    final rooms = _roomRatings(s.reviews);
    final perRoom = AePanelCard(
      title: 'Ratings by room',
      subtitle: 'Average room rating from guest reviews',
      icon: Icons.meeting_room_rounded,
      child: SizedBox(
        height: 210,
        child: rooms.isEmpty
            ? const AeIllustratedEmpty(
                art: AeEmptyArt.bed,
                title: 'No room numbers on reviews yet.',
                message: 'Assign rooms at the desk so reviews link to rooms.',
              )
            : ListView(
                children: [for (final r in rooms) _roomRatingRow(r)],
              ),
      ),
    );
    if (!wide) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [distribution, SizedBox(height: gap), perRoom],
      );
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(child: distribution),
        SizedBox(width: gap),
        Expanded(child: perRoom),
      ],
    );
  }

  List<({String room, double avg, int count})> _roomRatings(
    List<EstablishmentStayReview> reviews,
  ) {
    final sum = <String, double>{};
    final count = <String, int>{};
    for (final r in reviews) {
      for (final room in r.roomNumbers) {
        sum[room] = (sum[room] ?? 0) + r.roomRating;
        count[room] = (count[room] ?? 0) + 1;
      }
    }
    final rows = [
      for (final room in sum.keys)
        (room: room, avg: sum[room]! / count[room]!, count: count[room]!),
    ]..sort((a, b) {
        final byAvg = b.avg.compareTo(a.avg);
        return byAvg != 0 ? byAvg : b.count.compareTo(a.count);
      });
    return rows;
  }

  Widget _roomRatingRow(({String room, double avg, int count}) r) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          SizedBox(
            width: 70,
            child: Text(
              'Room ${r.room}',
              style: AeDashTokens.body(
                size: 12.5,
                color: AeDashTokens.text,
                weight: FontWeight.w700,
              ),
            ),
          ),
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: r.avg / 5,
                minHeight: 8,
                backgroundColor: AeDashTokens.border,
                color: AeDashTokens.warning,
              ),
            ),
          ),
          const SizedBox(width: 10),
          const Icon(Icons.star_rounded, size: 15, color: AeDashTokens.warning),
          const SizedBox(width: 2),
          SizedBox(
            width: 64,
            child: Text(
              '${r.avg.toStringAsFixed(1)} (${r.count})',
              style: AeDashTokens.body(size: 12, color: AeDashTokens.text),
            ),
          ),
        ],
      ),
    );
  }

  Widget _feed(List<EstablishmentStayReview> reviews) {
    final filtered = _stars == 0
        ? reviews
        : [
            for (final r in reviews)
              if (r.averageRating.round().clamp(1, 5) == _stars) r,
          ];
    final shown = filtered.take(_visible).toList();

    int countFor(int stars) => stars == 0
        ? reviews.length
        : reviews.where((r) => r.averageRating.round().clamp(1, 5) == stars).length;

    return AePanelCard(
      title: 'Guest comments',
      subtitle: 'Newest first',
      icon: Icons.forum_rounded,
      iconColor: AeDashTokens.warning,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final s in const [0, 5, 4, 3, 2, 1])
                AeFilterPill(
                  label: s == 0 ? 'All (${countFor(0)})' : '$s★ (${countFor(s)})',
                  selected: _stars == s,
                  onTap: () => setState(() {
                    _stars = s;
                    _visible = _pageSize;
                  }),
                ),
            ],
          ),
          const SizedBox(height: 16),
          if (shown.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: AeIllustratedEmpty(
                art: AeEmptyArt.review,
                title: 'No reviews with this rating.',
                message: 'Pick another star filter.',
              ),
            )
          else
            for (var i = 0; i < shown.length; i++) ...[
              if (i > 0)
                const Divider(height: 1, color: AeDashTokens.softBorder),
              _reviewTile(shown[i]),
            ],
          if (filtered.length > shown.length)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Center(
                child: TextButton(
                  onPressed: () => setState(() => _visible += _pageSize),
                  style: TextButton.styleFrom(
                    foregroundColor: AeDashTokens.accent,
                  ),
                  child: Text(
                    'Show more (${filtered.length - shown.length} left)',
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _stars5(double rating) {
    final full = rating.round().clamp(0, 5);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < 5; i++)
          Icon(
            i < full ? Icons.star_rounded : Icons.star_outline_rounded,
            size: 15,
            color: AeDashTokens.warning,
          ),
      ],
    );
  }

  Widget _reviewTile(EstablishmentStayReview r) {
    final meta = [
      formatStayDateTime(r.createdAt).replaceAll('\n', ' · '),
      if (r.roomNumbers.isNotEmpty) 'Room ${r.roomNumbers.join(', ')}',
      '${widget.isLodging ? 'Hotel' : 'Place'} ${r.hotelRating.toStringAsFixed(0)}★',
      '${widget.isLodging ? 'Room' : 'Service'} ${r.roomRating.toStringAsFixed(0)}★',
    ].join(' · ');
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          GuestInitialsAvatar(name: r.authorName, color: AeDashTokens.accent),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        r.authorName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AeDashTokens.section(size: 13.5),
                      ),
                    ),
                    _stars5(r.averageRating),
                    const SizedBox(width: 6),
                    Text(
                      r.averageRating.toStringAsFixed(1),
                      style: AeDashTokens.body(
                        size: 12.5,
                        color: AeDashTokens.text,
                        weight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 3),
                Text(meta, style: AeDashTokens.body(size: 11.5)),
                if (r.comment.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text(
                    r.comment,
                    style: AeDashTokens.body(
                      size: 13,
                      color: AeDashTokens.text,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

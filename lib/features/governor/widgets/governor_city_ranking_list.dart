import 'package:atmos_trs_system/features/governor/theme/governor_dashboard_tokens.dart';
import 'package:flutter/material.dart';

/// Horizontal ranked progress list for city / LGU tourist volume.
class GovernorCityRankingList extends StatelessWidget {
  const GovernorCityRankingList({
    super.key,
    required this.cities,
    this.dense = false,
  });

  final List<({String name, int count})> cities;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    if (cities.isEmpty) {
      return Center(
        child: Text(
          'Check-ins will rank cities here',
          style: GovernorDashboardTokens.body(size: dense ? 11 : 12.5),
          textAlign: TextAlign.center,
        ),
      );
    }

    final maxCount =
        cities.map((e) => e.count).reduce((a, b) => a > b ? a : b).clamp(1, 1 << 30);
    final visible = cities.take(dense ? 5 : 8).toList();

    return ListView.separated(
      physics: const BouncingScrollPhysics(),
      itemCount: visible.length,
      separatorBuilder: (_, __) => SizedBox(height: dense ? 8 : 10),
      itemBuilder: (context, index) {
        final city = visible[index];
        final progress = city.count / maxCount;
        return _RankRow(
          rank: index + 1,
          name: city.name,
          count: city.count,
          progress: progress,
          dense: dense,
        );
      },
    );
  }
}

class _RankRow extends StatelessWidget {
  const _RankRow({
    required this.rank,
    required this.name,
    required this.count,
    required this.progress,
    required this.dense,
  });

  final int rank;
  final String name;
  final int count;
  final double progress;
  final bool dense;

  Color get _badgeColor {
    switch (rank) {
      case 1:
        return const Color(0xFFF59E0B);
      case 2:
        return const Color(0xFF94A3B8);
      case 3:
        return const Color(0xFFD97706);
      default:
        return GovernorDashboardTokens.primary;
    }
  }

  String get _badgeLabel {
    if (rank == 1) return '1';
    if (rank == 2) return '2';
    if (rank == 3) return '3';
    return '$rank';
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: dense ? 26 : 30,
          height: dense ? 26 : 30,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: _badgeColor.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(9),
            border: Border.all(color: _badgeColor.withValues(alpha: 0.35)),
          ),
          child: Text(
            _badgeLabel,
            style: TextStyle(
              color: _badgeColor,
              fontWeight: FontWeight.w800,
              fontSize: dense ? 11 : 12,
            ),
          ),
        ),
        SizedBox(width: dense ? 8 : 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GovernorDashboardTokens.sectionTitle(
                        size: dense ? 12 : 13,
                      ),
                    ),
                  ),
                  Text(
                    '$count',
                    style: GovernorDashboardTokens.sectionTitle(
                      size: dense ? 11.5 : 12.5,
                      color: GovernorDashboardTokens.primary,
                    ),
                  ),
                ],
              ),
              SizedBox(height: dense ? 4 : 6),
              ClipRRect(
                borderRadius: BorderRadius.circular(999),
                child: LinearProgressIndicator(
                  value: progress.clamp(0.05, 1.0),
                  minHeight: dense ? 6 : 8,
                  backgroundColor: GovernorDashboardTokens.mutedSurface,
                  color: GovernorDashboardTokens.primary,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

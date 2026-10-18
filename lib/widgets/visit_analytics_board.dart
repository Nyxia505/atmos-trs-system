import 'package:atmos_trs_system/features/governor/theme/governor_dashboard_tokens.dart';
import 'package:atmos_trs_system/features/governor/widgets/charts/governor_age_bar_chart.dart';
import 'package:atmos_trs_system/features/governor/widgets/charts/governor_arrivals_area_chart.dart';
import 'package:atmos_trs_system/features/governor/widgets/charts/governor_donut_chart.dart';
import 'package:atmos_trs_system/features/governor/widgets/governor_chart_card.dart';
import 'package:atmos_trs_system/features/governor/widgets/governor_city_ranking_list.dart';
import 'package:atmos_trs_system/utils/visit_analytics.dart';
import 'package:flutter/material.dart';

/// Arrivals, categories, gender, age, residency, and rankings from check-ins.
class VisitAnalyticsBoard extends StatefulWidget {
  const VisitAnalyticsBoard({
    super.key,
    required this.checkIns,
    this.tourists = const [],
    this.parseTime,
    this.rankSpots = false,
    this.rankingTitle,
  });

  final List<Map<String, dynamic>> checkIns;
  final List<Map<String, dynamic>> tourists;
  final DateTime? Function(Map<String, dynamic> checkIn)? parseTime;

  /// Rank tourist spots. Otherwise rank municipalities by visitors.
  final bool rankSpots;
  final String? rankingTitle;

  @override
  State<VisitAnalyticsBoard> createState() => _VisitAnalyticsBoardState();
}

class _VisitAnalyticsBoardState extends State<VisitAnalyticsBoard> {
  String _range = 'This Month';

  @override
  Widget build(BuildContext context) {
    final snapshot = VisitAnalyticsSnapshot.build(
      checkIns: widget.checkIns,
      tourists: widget.tourists,
      range: _range,
      parseTime: widget.parseTime,
    );
    final rankingTitle = widget.rankingTitle ??
        (widget.rankSpots ? 'Top spots' : 'City ranking');
    final ranking =
        widget.rankSpots ? snapshot.spots : snapshot.municipalities;

    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= 980;
        final arrivals = _arrivalsCard(snapshot);
        final categories = _categoriesCard(snapshot);
        final gender = _genderCard(snapshot);
        final age = _ageCard(snapshot);
        final residency = _residencyCard(snapshot);
        final ranks = _rankingCard(rankingTitle, ranking);

        if (!wide) {
          return Column(
            children: [
              SizedBox(height: 280, child: arrivals),
              const SizedBox(height: 12),
              SizedBox(height: 280, child: categories),
              const SizedBox(height: 12),
              SizedBox(height: 280, child: gender),
              const SizedBox(height: 12),
              SizedBox(height: 280, child: age),
              const SizedBox(height: 12),
              SizedBox(height: 280, child: residency),
              const SizedBox(height: 12),
              SizedBox(height: 300, child: ranks),
            ],
          );
        }

        return Column(
          children: [
            SizedBox(
              height: 300,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(flex: 3, child: arrivals),
                  const SizedBox(width: 12),
                  Expanded(flex: 2, child: categories),
                ],
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              height: 280,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(child: gender),
                  const SizedBox(width: 12),
                  Expanded(child: age),
                  const SizedBox(width: 12),
                  Expanded(child: residency),
                  const SizedBox(width: 12),
                  Expanded(child: ranks),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _arrivalsCard(VisitAnalyticsSnapshot snapshot) {
    return GovernorChartCard(
      title: 'Tourist arrivals',
      icon: Icons.show_chart_rounded,
      trailing: PopupMenuButton<String>(
        initialValue: _range,
        onSelected: (value) => setState(() => _range = value),
        itemBuilder: (context) => [
          for (final filter in ['This Week', 'This Month', 'This Year'])
            PopupMenuItem(value: filter, child: Text(filter)),
        ],
        child: Text(
          _range,
          style: const TextStyle(
            color: GovernorDashboardTokens.primary,
            fontWeight: FontWeight.w700,
            fontSize: 12,
          ),
        ),
      ),
      child: GovernorArrivalsAreaChart(
        values: snapshot.arrivals,
        valueNoun: 'visitors',
        showAllBottomLabels: _range == 'This Month',
      ),
    );
  }

  Widget _categoriesCard(VisitAnalyticsSnapshot snapshot) {
    return GovernorChartCard(
      title: 'Top categories',
      icon: Icons.donut_large_rounded,
      child: GovernorDonutChart(
        emptyMessage: 'No category check-ins yet',
        segments: [
          for (var i = 0; i < snapshot.categories.length; i++)
            GovernorDonutSegment(
              label: snapshot.categories[i].name,
              value: snapshot.categories[i].count.toDouble(),
              color: GovernorDashboardTokens.categoryPalette[
                  i % GovernorDashboardTokens.categoryPalette.length],
            ),
        ],
      ),
    );
  }

  Widget _genderCard(VisitAnalyticsSnapshot snapshot) {
    final total = snapshot.male + snapshot.female + snapshot.otherGender;
    return GovernorChartCard(
      title: 'Gender',
      icon: Icons.people_alt_rounded,
      child: GovernorDonutChart(
        centerLabel: total > 0 ? '$total' : null,
        emptyMessage: 'No gender counts on check-ins yet',
        segments: [
          GovernorDonutSegment(
            label: 'Male',
            value: snapshot.male.toDouble(),
            color: GovernorDashboardTokens.genderMale,
          ),
          GovernorDonutSegment(
            label: 'Female',
            value: snapshot.female.toDouble(),
            color: GovernorDashboardTokens.genderFemale,
          ),
          GovernorDonutSegment(
            label: 'Others',
            value: snapshot.otherGender.toDouble(),
            color: GovernorDashboardTokens.genderOther,
          ),
        ],
      ),
    );
  }

  Widget _ageCard(VisitAnalyticsSnapshot snapshot) {
    return GovernorChartCard(
      title: 'Age range',
      icon: Icons.calendar_view_month_rounded,
      child: GovernorAgeBarChart(
        series: snapshot.ageSeries,
        emptyMessage: 'Age appears when a visitor profile has a birth date',
      ),
    );
  }

  Widget _residencyCard(VisitAnalyticsSnapshot snapshot) {
    final total = snapshot.local + snapshot.foreign;
    return GovernorChartCard(
      title: 'Local vs foreign',
      icon: Icons.public_rounded,
      child: GovernorDonutChart(
        centerLabel: total > 0 ? '$total' : null,
        emptyMessage: 'No residence counts on check-ins yet',
        segments: [
          GovernorDonutSegment(
            label: 'Local',
            value: snapshot.local.toDouble(),
            color: GovernorDashboardTokens.localVisitor,
          ),
          GovernorDonutSegment(
            label: 'Foreign',
            value: snapshot.foreign.toDouble(),
            color: GovernorDashboardTokens.foreignVisitor,
          ),
        ],
      ),
    );
  }

  Widget _rankingCard(
    String title,
    List<({String name, int count})> rows,
  ) {
    return GovernorChartCard(
      title: title,
      icon: Icons.emoji_events_rounded,
      child: GovernorCityRankingList(cities: rows),
    );
  }
}

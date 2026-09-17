import 'package:atmos_trs_system/features/governor/theme/governor_dashboard_tokens.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

class GovernorAgeBarChart extends StatelessWidget {
  const GovernorAgeBarChart({
    super.key,
    required this.series,
    this.dense = false,
    this.emptyMessage = 'Add date of birth on registration',
  });

  final List<({String label, int male, int female, int others})> series;
  final bool dense;
  final String emptyMessage;

  @override
  Widget build(BuildContext context) {
    final totals = series
        .map((r) => r.male + r.female + r.others)
        .toList(growable: false);
    final sum = totals.fold<int>(0, (a, b) => a + b);
    if (sum == 0) {
      return Center(
        child: Text(
          emptyMessage,
          style: GovernorDashboardTokens.body(size: dense ? 11 : 12.5),
          textAlign: TextAlign.center,
        ),
      );
    }

    final maxY =
        totals.reduce((a, b) => a > b ? a : b).toDouble().clamp(1.0, 1e9);

    return BarChart(
      BarChartData(
        maxY: maxY * 1.2,
        gridData: FlGridData(
          show: true,
          drawVerticalLine: false,
          getDrawingHorizontalLine: (_) => FlLine(
            color: GovernorDashboardTokens.border,
            strokeWidth: 1,
          ),
        ),
        borderData: FlBorderData(show: false),
        titlesData: FlTitlesData(
          topTitles:
              const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles:
              const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          leftTitles:
              const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: dense ? 22 : 28,
              getTitlesWidget: (value, meta) {
                final i = value.toInt();
                if (i < 0 || i >= series.length) {
                  return const SizedBox.shrink();
                }
                return Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    series[i].label,
                    style: GovernorDashboardTokens.body(size: dense ? 9 : 10),
                  ),
                );
              },
            ),
          ),
        ),
        barTouchData: BarTouchData(
          touchTooltipData: BarTouchTooltipData(
            getTooltipColor: (_) => GovernorDashboardTokens.text,
            getTooltipItem: (group, groupIndex, rod, rodIndex) {
              return BarTooltipItem(
                '${rod.toY.toStringAsFixed(0)}',
                const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                  fontSize: 12,
                ),
              );
            },
          ),
        ),
        barGroups: [
          for (var i = 0; i < series.length; i++)
            BarChartGroupData(
              x: i,
              barRods: [
                BarChartRodData(
                  toY: totals[i].toDouble(),
                  width: dense ? 14 : 18,
                  borderRadius: BorderRadius.circular(8),
                  gradient: LinearGradient(
                    begin: Alignment.bottomCenter,
                    end: Alignment.topCenter,
                    colors: [
                      GovernorDashboardTokens.primaryDark,
                      GovernorDashboardTokens.primarySecondary,
                    ],
                  ),
                ),
              ],
            ),
        ],
      ),
      duration: const Duration(milliseconds: 500),
    );
  }
}

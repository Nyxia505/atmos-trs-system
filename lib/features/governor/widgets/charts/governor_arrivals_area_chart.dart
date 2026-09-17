import 'package:atmos_trs_system/features/governor/theme/governor_dashboard_tokens.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

class GovernorArrivalsAreaChart extends StatelessWidget {
  const GovernorArrivalsAreaChart({
    super.key,
    required this.values,
    this.labels = const [],
    this.tooltipLabels = const [],
    this.emptyMessage = 'No arrivals in this period',
    this.valueNoun = 'tourists',
    this.rotateBottomLabels = false,
    this.showAllBottomLabels = false,
  });

  final List<double> values;
  final List<String> labels;

  /// Optional longer labels for touch tooltips (falls back to [labels]).
  final List<String> tooltipLabels;
  final String emptyMessage;

  /// Tooltip suffix, e.g. "tourists" or "unique visitors".
  final String valueNoun;

  /// Rotate X labels (useful for many municipality names).
  final bool rotateBottomLabels;

  /// Show every bottom label instead of skipping every other when crowded.
  final bool showAllBottomLabels;

  static const _monthShort = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];

  @override
  Widget build(BuildContext context) {
    final hasData = values.any((v) => v > 0);
    if (!hasData || values.isEmpty) {
      return Center(
        child: Text(
          emptyMessage,
          style: GovernorDashboardTokens.body(size: 12.5),
        ),
      );
    }

    final maxV =
        values.reduce((a, b) => a > b ? a : b).clamp(1.0, double.infinity);
    final spots = <FlSpot>[
      for (var i = 0; i < values.length; i++) FlSpot(i.toDouble(), values[i]),
    ];

    String labelAt(int i) {
      if (i < labels.length && labels[i].isNotEmpty) return labels[i];
      if (values.length == 12) return _monthShort[i % 12];
      if (values.length <= 7) return 'D${i + 1}';
      return '${i + 1}';
    }

    String tooltipAt(int i) {
      if (i < tooltipLabels.length && tooltipLabels[i].isNotEmpty) {
        return tooltipLabels[i];
      }
      return labelAt(i);
    }

    final bottomReserved = rotateBottomLabels ? 46.0 : 22.0;

    return LineChart(
      LineChartData(
        minY: 0,
        maxY: maxV * 1.15,
        gridData: FlGridData(
          show: true,
          drawVerticalLine: false,
          horizontalInterval: maxV / 4,
          getDrawingHorizontalLine: (value) => FlLine(
            color: GovernorDashboardTokens.border,
            strokeWidth: 1,
          ),
        ),
        titlesData: FlTitlesData(
          topTitles:
              const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles:
              const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 28,
              interval: maxV / 4,
              getTitlesWidget: (value, meta) {
                if (value <= 0 || value >= maxV * 1.14) {
                  return const SizedBox.shrink();
                }
                return Text(
                  value.toInt().toString(),
                  style: GovernorDashboardTokens.body(size: 10),
                );
              },
            ),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: bottomReserved,
              interval: 1,
              getTitlesWidget: (value, meta) {
                final i = value.round();
                if (i < 0 || i >= values.length) {
                  return const SizedBox.shrink();
                }
                if (!showAllBottomLabels &&
                    !rotateBottomLabels &&
                    values.length > 8 &&
                    i % 2 != 0) {
                  return const SizedBox.shrink();
                }
                final text = Text(
                  labelAt(i),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GovernorDashboardTokens.body(
                    size: rotateBottomLabels ? 9 : 10,
                  ),
                );
                if (!rotateBottomLabels) {
                  return Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: text,
                  );
                }
                return Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Transform.rotate(
                    angle: -0.75,
                    alignment: Alignment.topCenter,
                    child: SizedBox(
                      width: 56,
                      child: text,
                    ),
                  ),
                );
              },
            ),
          ),
        ),
        borderData: FlBorderData(show: false),
        lineTouchData: LineTouchData(
          handleBuiltInTouches: true,
          touchTooltipData: LineTouchTooltipData(
            getTooltipColor: (_) => GovernorDashboardTokens.text,
            getTooltipItems: (touched) => touched.map((t) {
              final i = t.x.round();
              final label = tooltipAt(i);
              return LineTooltipItem(
                '$label\n${t.y.toStringAsFixed(0)} $valueNoun',
                const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                  fontSize: 12,
                ),
              );
            }).toList(),
          ),
        ),
        lineBarsData: [
          LineChartBarData(
            spots: spots,
            isCurved: true,
            curveSmoothness: 0.32,
            color: GovernorDashboardTokens.primary,
            barWidth: 3,
            isStrokeCapRound: true,
            dotData: FlDotData(
              show: true,
              getDotPainter: (spot, percent, bar, index) => FlDotCirclePainter(
                radius: 3.5,
                color: Colors.white,
                strokeWidth: 2.2,
                strokeColor: GovernorDashboardTokens.primary,
              ),
            ),
            belowBarData: BarAreaData(
              show: true,
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  GovernorDashboardTokens.primary.withValues(alpha: 0.35),
                  GovernorDashboardTokens.primarySecondary
                      .withValues(alpha: 0.05),
                ],
              ),
            ),
          ),
        ],
      ),
      duration: const Duration(milliseconds: 550),
    );
  }
}

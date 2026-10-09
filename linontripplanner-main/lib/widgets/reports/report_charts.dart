import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../../data.dart';
import '../../services/reports/report_models.dart';
import '../tourism_plan_ui.dart';

/// Chart palette, starting with the portal orange so single-series charts stay
/// on brand.
const List<Color> kReportSeriesColors = [
  AppColors.primary,
  Color(0xFF42A5F5),
  Color(0xFF66BB6A),
  Color(0xFFAB47BC),
  Color(0xFF78909C),
  Color(0xFFFFA726),
  Color(0xFF26C6DA),
];

/// Renders a [ReportChart] inside the standard white analytics card.
class ReportChartCard extends StatelessWidget {
  final ReportChart chart;

  /// Height of the plot area. Preview and dashboard use different heights.
  final double height;

  const ReportChartCard({super.key, required this.chart, this.height = 240});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: TourismPlanUi.planCardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            chart.title,
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.bold,
              color: AppColors.textDark,
            ),
          ),
          const SizedBox(height: 14),
          SizedBox(height: height, child: _plot()),
        ],
      ),
    );
  }

  Widget _plot() {
    if (!chart.hasData) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Text(
            'No data for this chart under the selected filters.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 13,
              color: AppColors.textGrey.withValues(alpha: 0.9),
            ),
          ),
        ),
      );
    }
    return switch (chart.type) {
      ReportChartType.line => _ReportLineChart(chart: chart),
      ReportChartType.bar => _ReportBarChart(chart: chart),
      ReportChartType.donut => _ReportDonutChart(chart: chart),
    };
  }
}

/// Rounds a series peak up to a readable axis maximum.
double _axisMax(List<double> values) {
  final peak = values.fold<double>(0, (a, b) => b > a ? b : a);
  if (peak <= 0) return 5;
  final padded = peak * 1.2;
  final magnitude = _pow10(padded);
  for (final step in const [1, 2, 2.5, 5, 10]) {
    final candidate = step * magnitude;
    if (candidate >= padded) return candidate;
  }
  return 10 * magnitude;
}

double _pow10(double v) {
  var m = 1.0;
  while (m * 10 <= v) {
    m *= 10;
  }
  while (m > v && m > 1) {
    m /= 10;
  }
  return m;
}

String _axisNumber(double v) {
  if (v >= 1000000) return '${(v / 1000000).toStringAsFixed(1)}M';
  if (v >= 1000) return '${(v / 1000).toStringAsFixed(v % 1000 == 0 ? 0 : 1)}k';
  return v == v.roundToDouble() ? v.round().toString() : v.toStringAsFixed(1);
}

String _shortLabel(String raw, {int max = 12}) {
  final s = raw.trim();
  if (s.length <= max) return s;
  return '${s.substring(0, max - 1)}…';
}

class _ReportLineChart extends StatelessWidget {
  final ReportChart chart;

  const _ReportLineChart({required this.chart});

  @override
  Widget build(BuildContext context) {
    final maxY = _axisMax(chart.values);
    // Keep the x-axis readable when a wide date range produces many months.
    final labelStep = (chart.labels.length / 8).ceil().clamp(1, 999);
    return LineChart(
      LineChartData(
        minX: 0,
        maxX: (chart.labels.length - 1).clamp(1, 999).toDouble(),
        minY: 0,
        maxY: maxY,
        gridData: FlGridData(
          show: true,
          drawVerticalLine: false,
          horizontalInterval: maxY / 4,
          getDrawingHorizontalLine: (_) =>
              const FlLine(color: Color(0xFFEEEEEE), strokeWidth: 1),
        ),
        titlesData: FlTitlesData(
          topTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
          rightTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 30,
              interval: 1,
              getTitlesWidget: (v, meta) {
                final i = v.toInt();
                if (i < 0 || i >= chart.labels.length) {
                  return const SizedBox.shrink();
                }
                if (i % labelStep != 0) return const SizedBox.shrink();
                return Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    _shortLabel(chart.labels[i], max: 8),
                    style: const TextStyle(
                      fontSize: 10,
                      color: AppColors.textGrey,
                    ),
                  ),
                );
              },
            ),
          ),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 36,
              interval: maxY / 4,
              getTitlesWidget: (v, meta) => Text(
                _axisNumber(v),
                style: const TextStyle(
                  fontSize: 10,
                  color: AppColors.textGrey,
                ),
              ),
            ),
          ),
        ),
        borderData: FlBorderData(show: false),
        lineBarsData: [
          LineChartBarData(
            spots: [
              for (var i = 0; i < chart.values.length; i++)
                FlSpot(i.toDouble(), chart.values[i]),
            ],
            isCurved: true,
            curveSmoothness: 0.25,
            preventCurveOverShooting: true,
            color: AppColors.primary,
            barWidth: 3,
            isStrokeCapRound: true,
            dotData: FlDotData(show: chart.values.length <= 14),
            belowBarData: BarAreaData(
              show: true,
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  AppColors.primary.withValues(alpha: 0.32),
                  AppColors.primary.withValues(alpha: 0.02),
                ],
              ),
            ),
          ),
        ],
        lineTouchData: const LineTouchData(enabled: true),
      ),
    );
  }
}

class _ReportBarChart extends StatelessWidget {
  final ReportChart chart;

  const _ReportBarChart({required this.chart});

  @override
  Widget build(BuildContext context) {
    final maxY = _axisMax(chart.values);
    final many = chart.labels.length > 6;
    return BarChart(
      BarChartData(
        maxY: maxY,
        minY: 0,
        alignment: BarChartAlignment.spaceAround,
        gridData: FlGridData(
          show: true,
          drawVerticalLine: false,
          horizontalInterval: maxY / 4,
          getDrawingHorizontalLine: (_) =>
              const FlLine(color: Color(0xFFEEEEEE), strokeWidth: 1),
        ),
        titlesData: FlTitlesData(
          topTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
          rightTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: many ? 68 : 34,
              getTitlesWidget: (v, meta) {
                final i = v.toInt();
                if (i < 0 || i >= chart.labels.length) {
                  return const SizedBox.shrink();
                }
                final text = Text(
                  _shortLabel(chart.labels[i], max: many ? 14 : 12),
                  maxLines: 1,
                  style: const TextStyle(
                    fontSize: 10,
                    color: AppColors.textGrey,
                  ),
                );
                return SideTitleWidget(
                  axisSide: meta.axisSide,
                  space: 6,
                  angle: many ? -0.62 : 0,
                  child: text,
                );
              },
            ),
          ),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 36,
              interval: maxY / 4,
              getTitlesWidget: (v, meta) => Text(
                _axisNumber(v),
                style: const TextStyle(
                  fontSize: 10,
                  color: AppColors.textGrey,
                ),
              ),
            ),
          ),
        ),
        borderData: FlBorderData(show: false),
        barTouchData: BarTouchData(
          enabled: true,
          touchTooltipData: BarTouchTooltipData(
            getTooltipItem: (group, groupIndex, rod, rodIndex) {
              final i = group.x;
              final label = i >= 0 && i < chart.labels.length
                  ? chart.labels[i]
                  : '';
              return BarTooltipItem(
                '$label\n',
                const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 12,
                ),
                children: [
                  TextSpan(
                    text:
                        '${_axisNumber(rod.toY)}'
                        '${chart.valueSuffix.isEmpty ? '' : ' ${chart.valueSuffix}'}',
                    style: const TextStyle(color: Colors.white, fontSize: 11),
                  ),
                ],
              );
            },
          ),
        ),
        barGroups: [
          for (var i = 0; i < chart.values.length; i++)
            BarChartGroupData(
              x: i,
              barRods: [
                BarChartRodData(
                  toY: chart.values[i],
                  width: chart.values.length > 9 ? 14 : 20,
                  color: AppColors.primary,
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(6),
                  ),
                  backDrawRodData: BackgroundBarChartRodData(
                    show: true,
                    toY: maxY,
                    color: AppColors.listTilePeach,
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }
}

class _ReportDonutChart extends StatelessWidget {
  final ReportChart chart;

  const _ReportDonutChart({required this.chart});

  @override
  Widget build(BuildContext context) {
    final total = chart.values.fold<double>(0, (a, b) => a + b);
    final slices = <int>[
      for (var i = 0; i < chart.values.length; i++)
        if (chart.values[i] > 0) i,
    ];

    final pie = PieChart(
      PieChartData(
        sectionsSpace: 2,
        centerSpaceRadius: 44,
        sections: [
          for (final i in slices)
            PieChartSectionData(
              color: kReportSeriesColors[i % kReportSeriesColors.length],
              value: chart.values[i],
              title: chart.values[i] / total >= 0.08
                  ? '${(chart.values[i] / total * 100).round()}%'
                  : '',
              radius: 30,
              titleStyle: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
        ],
      ),
    );

    final legend = Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final i in slices.take(7))
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              children: [
                Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(
                    color:
                        kReportSeriesColors[i % kReportSeriesColors.length],
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    chart.labels[i],
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 12.5,
                      color: AppColors.textDark,
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  _axisNumber(chart.values[i]),
                  style: const TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textGrey,
                  ),
                ),
              ],
            ),
          ),
      ],
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        // Stack the legend under the donut when the card is too narrow to fit
        // both side by side.
        if (constraints.maxWidth < 330) {
          return Column(
            children: [
              Expanded(child: pie),
              const SizedBox(height: 10),
              Flexible(child: SingleChildScrollView(child: legend)),
            ],
          );
        }
        return Row(
          children: [
            SizedBox(width: 170, child: pie),
            const SizedBox(width: 12),
            Expanded(child: SingleChildScrollView(child: legend)),
          ],
        );
      },
    );
  }
}

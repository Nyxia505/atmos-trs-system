import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import 'package:atmos_trs_system/widgets/establishment_dash_tokens.dart';

/// Shared fl_chart panels for establishment DSS / Home glance charts.
abstract final class EstablishmentDssCharts {
  static Widget panel({
    required String title,
    required String subtitle,
    required Widget child,
    double height = 200,
    EdgeInsetsGeometry padding = const EdgeInsets.fromLTRB(16, 14, 16, 14),
  }) {
    return Container(
      decoration: AeDashTokens.cardDecoration(),
      padding: padding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(title, style: AeDashTokens.section(size: 14)),
          const SizedBox(height: 2),
          Text(subtitle, style: AeDashTokens.body(size: 11.5)),
          const SizedBox(height: 12),
          SizedBox(height: height, child: child),
        ],
      ),
    );
  }

  static Widget emptyChart(String message) {
    return Center(
      child: Text(
        message,
        textAlign: TextAlign.center,
        style: AeDashTokens.body(size: 13),
      ),
    );
  }

  static Widget staysTrendLine({
    required List<int> values,
    required List<String> labels,
    Color color = AeDashTokens.accent,
  }) {
    if (values.isEmpty || values.every((v) => v == 0)) {
      return emptyChart('No confirmed stays in this period yet.');
    }
    final maxY = values.reduce((a, b) => a > b ? a : b).toDouble();
    final spots = <FlSpot>[
      for (var i = 0; i < values.length; i++)
        FlSpot(i.toDouble(), values[i].toDouble()),
    ];
    return LineChart(
      LineChartData(
        minY: 0,
        maxY: maxY < 2 ? 2 : maxY * 1.15,
        gridData: FlGridData(
          show: true,
          drawVerticalLine: false,
          horizontalInterval: 1,
          getDrawingHorizontalLine: (_) => FlLine(
            color: AeDashTokens.border,
            strokeWidth: 1,
          ),
        ),
        borderData: FlBorderData(show: false),
        titlesData: FlTitlesData(
          topTitles:
              const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles:
              const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 28,
              getTitlesWidget: (v, _) => Text(
                v.toInt().toString(),
                style: AeDashTokens.body(size: 10),
              ),
            ),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              interval: values.length > 10 ? 2 : 1,
              getTitlesWidget: (v, _) {
                final i = v.toInt();
                if (i < 0 || i >= labels.length) return const SizedBox.shrink();
                if (values.length > 10 && i % 2 != 0) {
                  return const SizedBox.shrink();
                }
                return Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(labels[i], style: AeDashTokens.body(size: 9)),
                );
              },
            ),
          ),
        ),
        lineBarsData: [
          LineChartBarData(
            spots: spots,
            isCurved: true,
            color: color,
            barWidth: 2.5,
            isStrokeCapRound: true,
            dotData: FlDotData(
              show: values.length <= 8,
              getDotPainter: (s, p, b, i) => FlDotCirclePainter(
                radius: 3,
                color: color,
                strokeWidth: 0,
              ),
            ),
            belowBarData: BarAreaData(
              show: true,
              color: color.withValues(alpha: 0.12),
            ),
          ),
        ],
      ),
    );
  }

  static Widget staysTrendBars({
    required List<int> values,
    required List<String> labels,
  }) {
    if (values.isEmpty || values.every((v) => v == 0)) {
      return emptyChart('No confirmed stays in this period yet.');
    }
    final maxY = values.reduce((a, b) => a > b ? a : b).toDouble();
    return BarChart(
      BarChartData(
        maxY: maxY < 2 ? 2 : maxY * 1.2,
        gridData: FlGridData(
          show: true,
          drawVerticalLine: false,
          getDrawingHorizontalLine: (_) => FlLine(
            color: AeDashTokens.border,
            strokeWidth: 1,
          ),
        ),
        borderData: FlBorderData(show: false),
        titlesData: FlTitlesData(
          topTitles:
              const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles:
              const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 26,
              getTitlesWidget: (v, _) => Text(
                v.toInt().toString(),
                style: AeDashTokens.body(size: 10),
              ),
            ),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              getTitlesWidget: (v, _) {
                final i = v.toInt();
                if (i < 0 || i >= labels.length) return const SizedBox.shrink();
                return Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(labels[i], style: AeDashTokens.body(size: 9)),
                );
              },
            ),
          ),
        ),
        barGroups: [
          for (var i = 0; i < values.length; i++)
            BarChartGroupData(
              x: i,
              barRods: [
                BarChartRodData(
                  toY: values[i].toDouble(),
                  width: values.length > 10 ? 8 : 12,
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(4),
                  ),
                  color: AeDashTokens.accent,
                ),
              ],
            ),
        ],
      ),
    );
  }

  static Widget mixPie({
    required String aLabel,
    required int aValue,
    required Color aColor,
    required String bLabel,
    required int bValue,
    required Color bColor,
  }) {
    final total = aValue + bValue;
    if (total <= 0) {
      return emptyChart('No demographic data for this month yet.');
    }
    return Row(
      children: [
        Expanded(
          child: PieChart(
            PieChartData(
              sectionsSpace: 2,
              centerSpaceRadius: 36,
              sections: [
                PieChartSectionData(
                  value: aValue.toDouble(),
                  color: aColor,
                  title: total == 0
                      ? ''
                      : '${((aValue / total) * 100).round()}%',
                  titleStyle: AeDashTokens.body(
                    size: 11,
                    color: Colors.white,
                    weight: FontWeight.w700,
                  ),
                  radius: 42,
                ),
                PieChartSectionData(
                  value: bValue.toDouble(),
                  color: bColor,
                  title: total == 0
                      ? ''
                      : '${((bValue / total) * 100).round()}%',
                  titleStyle: AeDashTokens.body(
                    size: 11,
                    color: Colors.white,
                    weight: FontWeight.w700,
                  ),
                  radius: 42,
                ),
              ],
            ),
          ),
        ),
        const SizedBox(width: 8),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _legendDot(aColor, '$aLabel · $aValue'),
            const SizedBox(height: 8),
            _legendDot(bColor, '$bLabel · $bValue'),
          ],
        ),
      ],
    );
  }

  static Widget occupancyGauge({
    required int occupied,
    required int free,
    required int total,
  }) {
    if (total <= 0) {
      return emptyChart('Set your room count in QR & profile.');
    }
    final pct = (occupied / total).clamp(0.0, 1.0);
    return Column(
      children: [
        Expanded(
          child: Stack(
            alignment: Alignment.center,
            children: [
              PieChart(
                PieChartData(
                  startDegreeOffset: 270,
                  sectionsSpace: 0,
                  centerSpaceRadius: 48,
                  sections: [
                    PieChartSectionData(
                      value: occupied.toDouble().clamp(0, total.toDouble()),
                      color: AeDashTokens.danger,
                      title: '',
                      radius: 18,
                    ),
                    PieChartSectionData(
                      value: free.toDouble().clamp(0, total.toDouble()),
                      color: AeDashTokens.success.withValues(alpha: 0.85),
                      title: '',
                      radius: 18,
                    ),
                    if (occupied + free < total)
                      PieChartSectionData(
                        value: (total - occupied - free).toDouble(),
                        color: AeDashTokens.border,
                        title: '',
                        radius: 18,
                      ),
                  ],
                ),
              ),
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '${(pct * 100).round()}%',
                    style: AeDashTokens.number(size: 26),
                  ),
                  Text('occupied', style: AeDashTokens.body(size: 11)),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 4),
        Text(
          '$occupied occupied · $free free · $total total',
          textAlign: TextAlign.center,
          style: AeDashTokens.body(size: 11.5),
        ),
      ],
    );
  }

  static Widget weekdayBars(List<int> weekdayGuests) {
    const labels = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];
    if (weekdayGuests.every((v) => v == 0)) {
      return emptyChart('No guest load recorded this month yet.');
    }
    return staysTrendBars(values: weekdayGuests, labels: labels);
  }

  static Widget reviewStarsBars(List<int> buckets) {
    if (buckets.every((v) => v == 0)) {
      return emptyChart('No guest reviews yet.');
    }
    final maxY = buckets.reduce((a, b) => a > b ? a : b).toDouble();
    return BarChart(
      BarChartData(
        maxY: maxY < 2 ? 2 : maxY * 1.2,
        gridData: const FlGridData(show: false),
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
              getTitlesWidget: (v, _) {
                final i = v.toInt();
                if (i < 0 || i > 4) return const SizedBox.shrink();
                return Text('${i + 1}★', style: AeDashTokens.body(size: 10));
              },
            ),
          ),
        ),
        barGroups: [
          for (var i = 0; i < 5; i++)
            BarChartGroupData(
              x: i,
              barRods: [
                BarChartRodData(
                  toY: (i < buckets.length ? buckets[i] : 0).toDouble(),
                  width: 16,
                  borderRadius:
                      const BorderRadius.vertical(top: Radius.circular(4)),
                  color: AeDashTokens.accent,
                ),
              ],
            ),
        ],
      ),
    );
  }

  /// Horizontal-style ranking via vertical bars (most → least). Labels = room ids.
  static Widget roomRankingBars({
    required List<String> labels,
    required List<int> values,
  }) {
    if (labels.isEmpty || values.every((v) => v == 0)) {
      return emptyChart('No room assignments in this period yet.');
    }
    final maxY = values.reduce((a, b) => a > b ? a : b).toDouble();
    final show = labels.length > 12 ? 12 : labels.length;
    return BarChart(
      BarChartData(
        maxY: maxY < 2 ? 2 : maxY * 1.2,
        gridData: FlGridData(
          show: true,
          drawVerticalLine: false,
          getDrawingHorizontalLine: (_) => FlLine(
            color: AeDashTokens.border,
            strokeWidth: 1,
          ),
        ),
        borderData: FlBorderData(show: false),
        titlesData: FlTitlesData(
          topTitles:
              const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles:
              const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 28,
              getTitlesWidget: (v, _) => Text(
                v.toInt().toString(),
                style: AeDashTokens.body(size: 10),
              ),
            ),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 36,
              getTitlesWidget: (v, _) {
                final i = v.toInt();
                if (i < 0 || i >= show) return const SizedBox.shrink();
                final raw = labels[i];
                final short = raw.length > 10 ? '${raw.substring(0, 8)}…' : raw;
                return Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(short, style: AeDashTokens.body(size: 9)),
                );
              },
            ),
          ),
        ),
        barGroups: [
          for (var i = 0; i < show; i++)
            BarChartGroupData(
              x: i,
              barRods: [
                BarChartRodData(
                  toY: values[i].toDouble(),
                  width: show > 8 ? 10 : 14,
                  borderRadius:
                      const BorderRadius.vertical(top: Radius.circular(4)),
                  color: i == 0
                      ? AeDashTokens.accent
                      : AeDashTokens.chartSecondary,
                ),
              ],
            ),
        ],
      ),
    );
  }

  static Widget occupancyPctTrend({
    required List<double> pctValues,
    required List<String> labels,
  }) {
    if (pctValues.isEmpty || pctValues.every((v) => v <= 0)) {
      return emptyChart('No occupancy signal in this period yet.');
    }
    final spots = <FlSpot>[
      for (var i = 0; i < pctValues.length; i++)
        FlSpot(i.toDouble(), pctValues[i]),
    ];
    return LineChart(
      LineChartData(
        minY: 0,
        maxY: 100,
        gridData: FlGridData(
          show: true,
          drawVerticalLine: false,
          horizontalInterval: 25,
          getDrawingHorizontalLine: (_) => FlLine(
            color: AeDashTokens.border,
            strokeWidth: 1,
          ),
        ),
        borderData: FlBorderData(show: false),
        titlesData: FlTitlesData(
          topTitles:
              const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles:
              const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 32,
              interval: 25,
              getTitlesWidget: (v, _) => Text(
                '${v.toInt()}%',
                style: AeDashTokens.body(size: 9),
              ),
            ),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              interval: pctValues.length > 14
                  ? (pctValues.length / 6).ceilToDouble()
                  : 1,
              getTitlesWidget: (v, _) {
                final i = v.toInt();
                if (i < 0 || i >= labels.length) return const SizedBox.shrink();
                return Text(labels[i], style: AeDashTokens.body(size: 9));
              },
            ),
          ),
        ),
        lineBarsData: [
          LineChartBarData(
            spots: spots,
            isCurved: true,
            color: AeDashTokens.info,
            barWidth: 2.5,
            dotData: FlDotData(show: pctValues.length <= 14),
            belowBarData: BarAreaData(
              show: true,
              color: AeDashTokens.info.withValues(alpha: 0.12),
            ),
          ),
        ],
      ),
    );
  }

  static Widget _legendDot(Color color, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 6),
        Text(label, style: AeDashTokens.body(size: 12, color: AeDashTokens.text)),
      ],
    );
  }
}

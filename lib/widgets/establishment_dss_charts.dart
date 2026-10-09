import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import 'package:atmos_trs_system/widgets/chart_transition.dart';
import 'package:atmos_trs_system/widgets/establishment_dash_tokens.dart';

/// Shared fl_chart panels for establishment DSS / Home glance charts.
abstract final class EstablishmentDssCharts {
  static Widget panel({
    required String title,
    required String subtitle,
    required Widget child,
    double height = 200,
    EdgeInsetsGeometry padding = const EdgeInsets.fromLTRB(16, 14, 16, 14),
    IconData? icon,
    Color iconColor = AeDashTokens.accent,
  }) {
    return Container(
      decoration: AeDashTokens.cardDecoration(),
      padding: padding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (icon != null)
            AeSectionHeader(
              title: title,
              hint: subtitle,
              icon: icon,
              color: iconColor,
            )
          else ...[
            Text(title, style: AeDashTokens.section(size: 14)),
            const SizedBox(height: 2),
            Text(subtitle, style: AeDashTokens.body(size: 11.5)),
          ],
          const SizedBox(height: 12),
          SizedBox(height: height, child: child),
        ],
      ),
    );
  }

  static Widget emptyChart(String message) {
    return AeEmptyState(
      message: message,
      icon: Icons.insert_chart_outlined_rounded,
      boxed: false,
    );
  }

  static Widget staysTrendLine({
    required List<int> values,
    required List<String> labels,
    Color color = AeDashTokens.accent,
    double progress = 1,
  }) {
    if (values.isEmpty || values.every((v) => v == 0)) {
      return emptyChart('No register entries in this period yet.');
    }
    final maxY = values.reduce((a, b) => a > b ? a : b).toDouble();
    final spots = <FlSpot>[
      for (var i = 0; i < values.length; i++)
        FlSpot(i.toDouble(), values[i] * progress),
    ];
    return LineChart(
      duration: ChartTransition.chartDuration(progress),
      curve: Curves.easeOutCubic,
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
              interval: maxY <= 6 ? 1 : null,
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
    double progress = 1,
  }) {
    if (values.isEmpty || values.every((v) => v == 0)) {
      return emptyChart('No register entries in this period yet.');
    }
    final maxY = values.reduce((a, b) => a > b ? a : b).toDouble();
    final labelStep = values.length <= 12 ? 1 : (values.length / 8).ceil();
    final barWidth = values.length > 20
        ? 6.0
        : values.length > 10
            ? 8.0
            : 12.0;
    return BarChart(
      duration: ChartTransition.chartDuration(progress),
      curve: Curves.easeOutCubic,
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
              interval: maxY <= 6 ? 1 : null,
              getTitlesWidget: (v, _) => v != v.roundToDouble()
                  ? const SizedBox.shrink()
                  : Text(
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
                if (i % labelStep != 0) return const SizedBox.shrink();
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
                  toY: values[i] * progress,
                  width: barWidth,
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
            duration: const Duration(milliseconds: 450),
            curve: Curves.easeOutCubic,
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
      return emptyChart('Set your total rooms in Profile.');
    }
    final pct = (occupied / total).clamp(0.0, 1.0);
    return Column(
      children: [
        Expanded(
          child: Stack(
            alignment: Alignment.center,
            children: [
              PieChart(
                duration: const Duration(milliseconds: 450),
                curve: Curves.easeOutCubic,
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

  static Widget weekdayBars(List<int> weekdayGuests, {double progress = 1}) {
    const labels = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];
    if (weekdayGuests.every((v) => v == 0)) {
      return emptyChart('No guest load recorded this month yet.');
    }
    return staysTrendBars(
      values: weekdayGuests,
      labels: labels,
      progress: progress,
    );
  }

  /// Decimal bars (percent, pesos, averages) with a value suffix/prefix on the axis.
  static Widget valueBars({
    required List<double> values,
    required List<String> labels,
    Color color = AeDashTokens.accent,
    String prefix = '',
    String suffix = '',
    double? maxY,
    String emptyMessage = 'No data in this period yet.',
    double progress = 1,
    int? highlightIndex,
  }) {
    if (values.isEmpty || values.every((v) => v <= 0)) {
      return emptyChart(emptyMessage);
    }
    final peak = values.reduce((a, b) => a > b ? a : b);
    final top = maxY ?? (peak <= 0 ? 1 : peak * 1.2);
    final labelStep = values.length <= 12 ? 1 : (values.length / 8).ceil();
    final barWidth = values.length > 20 ? 6.0 : (values.length > 10 ? 9.0 : 14.0);
    String axis(double v) {
      final s = v >= 1000 ? '${(v / 1000).toStringAsFixed(v >= 10000 ? 0 : 1)}k' : v.toStringAsFixed(0);
      return '$prefix$s$suffix';
    }

    return BarChart(
      duration: ChartTransition.chartDuration(progress),
      curve: Curves.easeOutCubic,
      BarChartData(
        maxY: top,
        minY: 0,
        gridData: FlGridData(
          show: true,
          drawVerticalLine: false,
          getDrawingHorizontalLine: (_) => FlLine(color: AeDashTokens.border, strokeWidth: 1),
        ),
        borderData: FlBorderData(show: false),
        barTouchData: BarTouchData(
          touchTooltipData: BarTouchTooltipData(
            getTooltipItem: (group, _, rod, __) => BarTooltipItem(
              '${labels[group.x]}\n$prefix${values[group.x].toStringAsFixed(values[group.x] >= 100 ? 0 : 1)}$suffix',
              AeDashTokens.body(size: 11, color: Colors.white, weight: FontWeight.w700),
            ),
          ),
        ),
        titlesData: FlTitlesData(
          topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 40,
              getTitlesWidget: (v, meta) => v == meta.max
                  ? const SizedBox.shrink()
                  : Text(axis(v), style: AeDashTokens.body(size: 9)),
            ),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 24,
              getTitlesWidget: (v, _) {
                final i = v.toInt();
                if (i < 0 || i >= labels.length || i % labelStep != 0) {
                  return const SizedBox.shrink();
                }
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
                  toY: values[i].clamp(0, top) * progress,
                  width: barWidth,
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
                  color: highlightIndex == null || highlightIndex == i
                      ? color
                      : color.withValues(alpha: 0.45),
                ),
              ],
            ),
        ],
      ),
    );
  }

  /// Several decimal series on one axis (e.g. ALOS vs persons per room).
  static Widget multiLine({
    required List<({String label, List<double?> values, Color color})> series,
    required List<String> labels,
    String suffix = '',
    double? maxY,
    String emptyMessage = 'No data in this period yet.',
    double progress = 1,
  }) {
    final all = [
      for (final s in series)
        for (final v in s.values)
          if (v != null) v,
    ];
    if (all.isEmpty || all.every((v) => v <= 0)) return emptyChart(emptyMessage);
    final peak = all.reduce((a, b) => a > b ? a : b);
    final top = maxY ?? (peak <= 0 ? 1 : peak * 1.2);
    return Column(
      children: [
        Expanded(
          child: LineChart(
            duration: ChartTransition.chartDuration(progress),
            curve: Curves.easeOutCubic,
            LineChartData(
              minY: 0,
              maxY: top,
              gridData: FlGridData(
                show: true,
                drawVerticalLine: false,
                getDrawingHorizontalLine: (_) => FlLine(color: AeDashTokens.border, strokeWidth: 1),
              ),
              borderData: FlBorderData(show: false),
              titlesData: FlTitlesData(
                topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                leftTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 34,
                    getTitlesWidget: (v, meta) => v == meta.max
                        ? const SizedBox.shrink()
                        : Text(
                            '${v.toStringAsFixed(top <= 5 ? 1 : 0)}$suffix',
                            style: AeDashTokens.body(size: 9),
                          ),
                  ),
                ),
                bottomTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    interval: labels.length > 14 ? (labels.length / 7).ceilToDouble() : 1,
                    getTitlesWidget: (v, _) {
                      final i = v.toInt();
                      if (i < 0 || i >= labels.length) return const SizedBox.shrink();
                      return Text(labels[i], style: AeDashTokens.body(size: 9));
                    },
                  ),
                ),
              ),
              lineBarsData: [
                for (final s in series)
                  LineChartBarData(
                    spots: [
                      for (var i = 0; i < s.values.length; i++)
                        if (s.values[i] != null) FlSpot(i.toDouble(), s.values[i]! * progress),
                    ],
                    isCurved: true,
                    preventCurveOverShooting: true,
                    color: s.color,
                    barWidth: 2.5,
                    dotData: FlDotData(show: labels.length <= 14),
                    belowBarData: BarAreaData(
                      show: series.length == 1,
                      color: s.color.withValues(alpha: 0.12),
                    ),
                  ),
              ],
            ),
          ),
        ),
        if (series.length > 1) ...[
          const SizedBox(height: 8),
          Wrap(
            spacing: 14,
            runSpacing: 4,
            alignment: WrapAlignment.center,
            children: [for (final s in series) _legendDot(s.color, s.label)],
          ),
        ],
      ],
    );
  }

  /// Donut with any number of slices plus a legend.
  static Widget multiPie({
    required List<({String label, int value, Color color})> slices,
    String emptyMessage = 'No data for this month yet.',
  }) {
    final shown = slices.where((s) => s.value > 0).toList();
    final total = shown.fold<int>(0, (a, s) => a + s.value);
    if (total <= 0) return emptyChart(emptyMessage);
    return Row(
      children: [
        Expanded(
          child: PieChart(
            duration: const Duration(milliseconds: 450),
            curve: Curves.easeOutCubic,
            PieChartData(
              sectionsSpace: 2,
              centerSpaceRadius: 34,
              sections: [
                for (final s in shown)
                  PieChartSectionData(
                    value: s.value.toDouble(),
                    color: s.color,
                    title: s.value / total >= 0.07 ? '${(s.value / total * 100).round()}%' : '',
                    titleStyle: AeDashTokens.body(size: 11, color: Colors.white, weight: FontWeight.w700),
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
            for (final s in slices) ...[
              _legendDot(s.color, '${s.label} · ${s.value}'),
              const SizedBox(height: 7),
            ],
          ],
        ),
      ],
    );
  }

  /// Horizontal-style ranking via vertical bars (most → least). Labels = room ids.
  static Widget roomRankingBars({
    required List<String> labels,
    required List<int> values,
    double progress = 1,
  }) {
    if (labels.isEmpty || values.every((v) => v == 0)) {
      return emptyChart('No room numbers in the register for this period yet.');
    }
    final maxY = values.reduce((a, b) => a > b ? a : b).toDouble();
    final show = labels.length > 12 ? 12 : labels.length;
    return BarChart(
      duration: ChartTransition.chartDuration(progress),
      curve: Curves.easeOutCubic,
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
                  toY: values[i] * progress,
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
    double progress = 1,
  }) {
    if (pctValues.isEmpty || pctValues.every((v) => v <= 0)) {
      return emptyChart('No occupancy signal in this period yet.');
    }
    final spots = <FlSpot>[
      for (var i = 0; i < pctValues.length; i++)
        FlSpot(i.toDouble(), pctValues[i] * progress),
    ];
    return LineChart(
      duration: ChartTransition.chartDuration(progress),
      curve: Curves.easeOutCubic,
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

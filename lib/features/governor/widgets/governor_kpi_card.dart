import 'package:atmos_trs_system/features/governor/theme/governor_dashboard_tokens.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

/// KPI card matching the concept: icon | title/value/trend | sparkline.
class GovernorKpiCard extends StatefulWidget {
  const GovernorKpiCard({
    super.key,
    required this.title,
    required this.value,
    required this.icon,
    required this.accent,
    this.changeText,
    this.isPositive,
    this.trendHint,
    this.sparkline = const [],
    this.compact = false,
  });

  final String title;
  final String value;
  final IconData icon;
  final Color accent;
  final String? changeText;
  final bool? isPositive;
  final String? trendHint;
  final List<double> sparkline;
  final bool compact;

  @override
  State<GovernorKpiCard> createState() => _GovernorKpiCardState();
}

class _GovernorKpiCardState extends State<GovernorKpiCard> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final compact = widget.compact;
    final change = widget.changeText;
    final positive = widget.isPositive ?? true;
    final flat =
        change == null || change.isEmpty || change == '—' || change == '0%';

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOutCubic,
        padding: EdgeInsets.fromLTRB(
          compact ? 12 : 16,
          compact ? 12 : 16,
          compact ? 12 : 16,
          compact ? 10 : 14,
        ),
        decoration: BoxDecoration(
          color: GovernorDashboardTokens.card,
          borderRadius:
              BorderRadius.circular(GovernorDashboardTokens.radiusCard),
          border: Border.all(color: GovernorDashboardTokens.border),
          boxShadow: _hovered
              ? GovernorDashboardTokens.cardShadowHover
              : GovernorDashboardTokens.cardShadow,
        ),
        child: Row(
          children: [
            Container(
              width: compact ? 40 : 48,
              height: compact ? 40 : 48,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(14),
                color: widget.accent,
              ),
              child: Icon(
                widget.icon,
                size: compact ? 20 : 22,
                color: Colors.white,
              ),
            ),
            SizedBox(width: compact ? 10 : 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    widget.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GovernorDashboardTokens.body(
                      size: compact ? 11 : 12,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    widget.value,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GovernorDashboardTokens.number(
                      size: compact ? 24 : 28,
                    ),
                  ),
                  if (change != null && change.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    _TrendLabel(
                      text: change,
                      hint: widget.trendHint,
                      positive: positive,
                      flat: flat,
                      compact: compact,
                    ),
                  ],
                ],
              ),
            ),
            SizedBox(
              width: compact ? 56 : 72,
              height: compact ? 36 : 44,
              child: _MiniSparkline(
                values: widget.sparkline,
                color: widget.accent,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TrendLabel extends StatelessWidget {
  const _TrendLabel({
    required this.text,
    required this.positive,
    required this.flat,
    required this.compact,
    this.hint,
  });

  final String text;
  final String? hint;
  final bool positive;
  final bool flat;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final color = flat
        ? const Color(0xFF3B82F6)
        : (positive
            ? GovernorDashboardTokens.success
            : GovernorDashboardTokens.danger);
    final arrow = flat ? '→' : (positive ? '↑' : '↓');
    final hintPart = hint == null ? '' : ' $hint';
    return Text(
      '$arrow $text$hintPart',
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
        color: color,
        fontSize: compact ? 10.5 : 11.5,
        fontWeight: FontWeight.w600,
      ),
    );
  }
}

class _MiniSparkline extends StatelessWidget {
  const _MiniSparkline({required this.values, required this.color});
  final List<double> values;
  final Color color;

  @override
  Widget build(BuildContext context) {
    if (values.isEmpty) return const SizedBox.shrink();
    final maxV =
        values.reduce((a, b) => a > b ? a : b).clamp(1.0, double.infinity);
    final spots = <FlSpot>[
      for (var i = 0; i < values.length; i++)
        FlSpot(i.toDouble(), values[i] / maxV),
    ];
    return LineChart(
      LineChartData(
        minY: 0,
        maxY: 1.2,
        gridData: const FlGridData(show: false),
        titlesData: const FlTitlesData(show: false),
        borderData: FlBorderData(show: false),
        lineTouchData: const LineTouchData(enabled: false),
        lineBarsData: [
          LineChartBarData(
            spots: spots,
            isCurved: true,
            curveSmoothness: 0.35,
            color: color,
            barWidth: 2.2,
            isStrokeCapRound: true,
            dotData: const FlDotData(show: false),
            belowBarData: BarAreaData(
              show: true,
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  color.withValues(alpha: 0.28),
                  color.withValues(alpha: 0.02),
                ],
              ),
            ),
          ),
        ],
      ),
      duration: const Duration(milliseconds: 450),
    );
  }
}

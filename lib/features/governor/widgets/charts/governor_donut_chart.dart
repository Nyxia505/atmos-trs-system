import 'package:atmos_trs_system/features/governor/theme/governor_dashboard_tokens.dart';
import 'package:atmos_trs_system/widgets/chart_transition.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

class GovernorDonutSegment {
  const GovernorDonutSegment({
    required this.label,
    required this.value,
    required this.color,
  });

  final String label;
  final double value;
  final Color color;
}

class GovernorDonutChart extends StatefulWidget {
  const GovernorDonutChart({
    super.key,
    required this.segments,
    this.centerLabel,
    this.emptyMessage = 'No data yet',
    this.showLegend = true,
    this.dense = false,
    this.showCounts = false,
  });

  final List<GovernorDonutSegment> segments;
  final String? centerLabel;
  final String emptyMessage;
  final bool showLegend;
  final bool dense;
  final bool showCounts;

  @override
  State<GovernorDonutChart> createState() => _GovernorDonutChartState();
}

class _GovernorDonutChartState extends State<GovernorDonutChart> {
  int? _touched;

  @override
  Widget build(BuildContext context) {
    final total =
        widget.segments.fold<double>(0, (a, s) => a + s.value);
    if (total <= 0) {
      return Center(
        child: Text(
          widget.emptyMessage,
          style: GovernorDashboardTokens.body(size: widget.dense ? 11 : 12.5),
          textAlign: TextAlign.center,
        ),
      );
    }

    final touched = _touched != null && _touched! < widget.segments.length
        ? widget.segments[_touched!]
        : null;

    return Row(
      children: [
        Expanded(
          flex: widget.showLegend ? 5 : 1,
          child: Stack(
            alignment: Alignment.center,
            children: [
              ChartTransition(
                swapKey: Object.hashAll([
                  for (final s in widget.segments) s.label,
                ]),
                builder: (context, progress) => _pie(total, progress),
              ),
              if (widget.centerLabel != null)
                IgnorePointer(
                  child: Text(
                    widget.centerLabel!,
                    textAlign: TextAlign.center,
                    style: GovernorDashboardTokens.sectionTitle(
                      size: widget.dense ? 11 : 13,
                    ),
                  ),
                ),
              if (touched != null && widget.showCounts)
                Positioned(
                  top: 0,
                  left: 4,
                  right: 4,
                  child: IgnorePointer(child: _tooltip(touched, total)),
                ),
            ],
          ),
        ),
        if (widget.showLegend) ...[
          const SizedBox(width: 8),
          Expanded(
            flex: widget.showCounts ? 6 : 4,
            child: _legend(total),
          ),
        ],
      ],
    );
  }

  /// [progress] < 1 sweeps the ring in via a transparent remainder slice.
  Widget _pie(double total, double progress) {
    final sweeping = progress < 1;
    final radius = widget.dense ? 18.0 : 22.0;
    return PieChart(
      PieChartData(
        sectionsSpace: sweeping ? 0 : 2,
        centerSpaceRadius: widget.dense ? 28 : 36,
        pieTouchData: PieTouchData(
          enabled: !sweeping,
          touchCallback: (event, response) {
            setState(() {
              if (!event.isInterestedForInteractions ||
                  response == null ||
                  response.touchedSection == null) {
                _touched = null;
                return;
              }
              _touched = response.touchedSection!.touchedSectionIndex;
            });
          },
        ),
        sections: [
          for (var i = 0; i < widget.segments.length; i++)
            PieChartSectionData(
              value: widget.segments[i].value * progress,
              color: widget.segments[i].color,
              radius: _touched == i ? (widget.dense ? 22 : 28) : radius,
              title: !sweeping && widget.segments[i].value / total >= 0.08
                  ? '${((widget.segments[i].value / total) * 100).round()}%'
                  : '',
              titleStyle: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w800,
                fontSize: widget.dense ? 9 : 11,
              ),
            ),
          if (sweeping)
            PieChartSectionData(
              value: total * (1 - progress),
              color: Colors.transparent,
              radius: radius,
              title: '',
            ),
        ],
      ),
      duration: ChartTransition.chartDuration(
        progress,
        const Duration(milliseconds: 450),
      ),
      curve: Curves.easeOutCubic,
    );
  }

  Widget _tooltip(GovernorDonutSegment segment, double total) {
    final pct = total <= 0 ? 0 : (segment.value / total) * 100;
    final visits = segment.value.round();
    return Align(
      alignment: Alignment.topCenter,
      child: Material(
        color: const Color(0xFF1F2937),
        elevation: 2,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
          child: Text(
            '${segment.label}\n$visits visit${visits == 1 ? '' : 's'} · ${pct.toStringAsFixed(pct >= 10 || pct == 0 ? 0 : 1)}%',
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 11,
              fontWeight: FontWeight.w700,
              height: 1.25,
            ),
          ),
        ),
      ),
    );
  }

  Widget _legend(double total) {
    final rows = Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final s in widget.segments)
          Padding(
            padding: EdgeInsets.only(bottom: widget.dense ? 4 : 6),
            child: Row(
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: s.color,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    widget.showCounts
                        ? '${s.label} · ${s.value.round()}'
                        : s.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GovernorDashboardTokens.body(
                      size: widget.dense ? 10.5 : 12,
                      color: GovernorDashboardTokens.text,
                    ),
                  ),
                ),
                const SizedBox(width: 4),
                Text(
                  '${((s.value / total) * 100).round()}%',
                  style: GovernorDashboardTokens.sectionTitle(
                    size: widget.dense ? 10.5 : 12,
                  ),
                ),
              ],
            ),
          ),
      ],
    );
    if (!widget.showCounts) return rows;
    return SingleChildScrollView(child: rows);
  }
}

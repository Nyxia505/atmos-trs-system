import 'package:atmos_trs_system/features/governor/theme/governor_dashboard_tokens.dart';
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
  });

  final List<GovernorDonutSegment> segments;
  final String? centerLabel;
  final String emptyMessage;
  final bool showLegend;
  final bool dense;

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

    return Row(
      children: [
        Expanded(
          flex: widget.showLegend ? 5 : 1,
          child: Stack(
            alignment: Alignment.center,
            children: [
              PieChart(
                PieChartData(
                  sectionsSpace: 2,
                  centerSpaceRadius: widget.dense ? 28 : 36,
                  pieTouchData: PieTouchData(
                    touchCallback: (event, response) {
                      setState(() {
                        if (!event.isInterestedForInteractions ||
                            response == null ||
                            response.touchedSection == null) {
                          _touched = null;
                          return;
                        }
                        _touched =
                            response.touchedSection!.touchedSectionIndex;
                      });
                    },
                  ),
                  sections: [
                    for (var i = 0; i < widget.segments.length; i++)
                      PieChartSectionData(
                        value: widget.segments[i].value,
                        color: widget.segments[i].color,
                        radius: _touched == i
                            ? (widget.dense ? 22 : 28)
                            : (widget.dense ? 18 : 22),
                        title: widget.segments[i].value / total >= 0.08
                            ? '${((widget.segments[i].value / total) * 100).round()}%'
                            : '',
                        titleStyle: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w800,
                          fontSize: widget.dense ? 9 : 11,
                        ),
                      ),
                  ],
                ),
                duration: const Duration(milliseconds: 450),
              ),
              if (widget.centerLabel != null)
                Text(
                  widget.centerLabel!,
                  textAlign: TextAlign.center,
                  style: GovernorDashboardTokens.sectionTitle(
                    size: widget.dense ? 11 : 13,
                  ),
                ),
            ],
          ),
        ),
        if (widget.showLegend) ...[
          const SizedBox(width: 8),
          Expanded(
            flex: 4,
            child: Column(
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
                            s.label,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: GovernorDashboardTokens.body(
                              size: widget.dense ? 10.5 : 12,
                              color: GovernorDashboardTokens.text,
                            ),
                          ),
                        ),
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
            ),
          ),
        ],
      ],
    );
  }
}

import 'package:flutter/material.dart';

import '../../data.dart';
import '../../services/reports/report_format.dart';
import '../../services/reports/report_models.dart';
import '../tourism_plan_ui.dart';
import 'report_charts.dart';

/// On-screen rendering of a [ReportDataset]: KPI tiles, charts, detail tables.
///
/// Shared by the Reports tab and the report preview so the preview always shows
/// what the tab shows, and both match the exported file.

/// Rows shown per table on screen; exports always contain every row.
const int kReportTableRowLimit = 50;

class ReportMetricTile extends StatelessWidget {
  final ReportMetric metric;

  const ReportMetricTile({super.key, required this.metric});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: TourismPlanUi.planCardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Row(
            children: [
              Container(
                width: 30,
                height: 30,
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(9),
                ),
                child: Icon(metric.icon, size: 17, color: AppColors.primary),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  metric.label,
                  style: const TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textGrey,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            metric.value,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 19,
              fontWeight: FontWeight.bold,
              color: AppColors.textDark,
              height: 1.15,
            ),
          ),
          if (metric.caption != null) ...[
            const SizedBox(height: 3),
            Text(
              metric.caption!,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 11, color: AppColors.textGrey),
            ),
          ],
        ],
      ),
    );
  }
}

/// Responsive KPI grid: 4 columns on wide screens down to 1 on phones.
class ReportMetricGrid extends StatelessWidget {
  final List<ReportMetric> metrics;

  const ReportMetricGrid({super.key, required this.metrics});

  @override
  Widget build(BuildContext context) {
    if (metrics.isEmpty) return const SizedBox.shrink();
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final columns = width >= 1180
            ? 4
            : width >= 860
            ? 3
            : width >= 560
            ? 2
            : 1;
        const gap = 14.0;
        final tileWidth =
            (width - gap * (columns - 1)) / columns;
        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: [
            for (final m in metrics)
              SizedBox(
                width: tileWidth,
                height: 132,
                child: ReportMetricTile(metric: m),
              ),
          ],
        );
      },
    );
  }
}

/// Responsive chart grid: two per row when there is room, one otherwise.
class ReportChartsGrid extends StatelessWidget {
  final List<ReportChart> charts;
  final double chartHeight;

  const ReportChartsGrid({
    super.key,
    required this.charts,
    this.chartHeight = 240,
  });

  @override
  Widget build(BuildContext context) {
    if (charts.isEmpty) return const SizedBox.shrink();
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        const gap = 14.0;
        final twoUp = width >= 900;
        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: [
            for (final chart in charts)
              SizedBox(
                // Line charts read better full width; the rest pair up.
                width: twoUp && chart.type != ReportChartType.line
                    ? (width - gap) / 2
                    : width,
                child: ReportChartCard(chart: chart, height: chartHeight),
              ),
          ],
        );
      },
    );
  }
}

/// A detail table in a white card, horizontally scrollable on narrow screens.
class ReportTableCard extends StatelessWidget {
  final ReportTable table;

  /// Cap on rows rendered; the full set still reaches the export.
  final int rowLimit;

  const ReportTableCard({
    super.key,
    required this.table,
    this.rowLimit = kReportTableRowLimit,
  });

  @override
  Widget build(BuildContext context) {
    final shown = table.rows.length > rowLimit
        ? table.rows.take(rowLimit).toList()
        : table.rows;

    return Container(
      decoration: TourismPlanUi.planCardDecoration(),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 16, 18, 10),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    table.title,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                      color: AppColors.textDark,
                    ),
                  ),
                ),
                Text(
                  '${formatCount(table.rows.length)} '
                  '${table.rows.length == 1 ? 'row' : 'rows'}',
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.textGrey,
                  ),
                ),
              ],
            ),
          ),
          if (table.isEmpty)
            const Padding(
              padding: EdgeInsets.fromLTRB(18, 4, 18, 22),
              child: Text(
                'No records matched the selected filters.',
                style: TextStyle(fontSize: 13, color: AppColors.textGrey),
              ),
            )
          else
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: DataTable(
                headingRowHeight: 42,
                dataRowMinHeight: 40,
                dataRowMaxHeight: 52,
                horizontalMargin: 18,
                columnSpacing: 26,
                headingRowColor: WidgetStatePropertyAll(
                  AppColors.listTilePeach,
                ),
                headingTextStyle: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: AppColors.textDark,
                ),
                dataTextStyle: const TextStyle(
                  fontSize: 12.5,
                  color: AppColors.textDark,
                ),
                columns: [
                  for (var i = 0; i < table.columns.length; i++)
                    DataColumn(
                      label: Text(table.columns[i]),
                      numeric: table.numericColumns.contains(i),
                    ),
                ],
                rows: [
                  for (final row in shown)
                    DataRow(
                      cells: [
                        for (var i = 0; i < table.columns.length; i++)
                          DataCell(
                            ConstrainedBox(
                              constraints: const BoxConstraints(maxWidth: 260),
                              child: Text(
                                i < row.length ? row[i] : '',
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ),
                      ],
                    ),
                ],
              ),
            ),
          if (table.rows.length > shown.length)
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 10, 18, 16),
              child: Text(
                'Showing the first ${formatCount(shown.length)} of '
                '${formatCount(table.rows.length)} rows. '
                'The exported file includes every row.',
                style: TextStyle(
                  fontSize: 11.5,
                  color: AppColors.textGrey.withValues(alpha: 0.95),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Amber notice for partial data (e.g. undated check-ins).
class ReportWarningBanner extends StatelessWidget {
  final String message;

  const ReportWarningBanner({super.key, required this.message});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF8E1),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFFFE082)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(
            Icons.info_outline,
            size: 18,
            color: Color(0xFF8D6E00),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(
                fontSize: 12.5,
                color: Color(0xFF6D5200),
                height: 1.35,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Small pill listing an applied filter, used in the preview header.
class ReportFilterChipsRow extends StatelessWidget {
  final List<(String, String)> filters;

  const ReportFilterChipsRow({super.key, required this.filters});

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final f in filters)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
            decoration: BoxDecoration(
              color: AppColors.listTilePeach,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: AppColors.primary.withValues(alpha: 0.18),
              ),
            ),
            child: Text.rich(
              TextSpan(
                children: [
                  TextSpan(
                    text: '${f.$1}: ',
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppColors.textGrey,
                    ),
                  ),
                  TextSpan(
                    text: f.$2,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textDark,
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

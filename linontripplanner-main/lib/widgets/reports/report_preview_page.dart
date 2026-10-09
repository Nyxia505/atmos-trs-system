import 'package:flutter/material.dart';

import '../../data.dart';
import '../../services/reports/report_format.dart';
import '../../services/reports/report_models.dart';
import '../tourism_plan_ui.dart';
import 'report_analytics_view.dart';

/// Full-page preview shown before export: title, generated date, applied
/// filters, summary statistics, charts, and the detailed data tables.
class ReportPreviewPage extends StatelessWidget {
  final ReportDataset dataset;

  /// Runs the export flow (format dialog, refresh, download).
  final Future<void> Function() onExport;

  /// True while an export is in flight, so the button can show progress.
  final bool exporting;

  const ReportPreviewPage({
    super.key,
    required this.dataset,
    required this.onExport,
    this.exporting = false,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.planPageBg,
      appBar: AppBar(
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        title: const Text(
          'Report preview',
          style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: TextButton.icon(
              onPressed: exporting ? null : onExport,
              style: TextButton.styleFrom(foregroundColor: Colors.white),
              icon: exporting
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.download_outlined, size: 18),
              label: Text(exporting ? 'Exporting…' : 'Export'),
            ),
          ),
        ],
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final pad = constraints.maxWidth < 640 ? 16.0 : 24.0;
          return SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(pad, pad, pad, 40),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _header(),
                if (dataset.warning != null) ...[
                  const SizedBox(height: 16),
                  ReportWarningBanner(message: dataset.warning!),
                ],
                const SizedBox(height: 22),
                _sectionTitle('Summary statistics'),
                const SizedBox(height: 12),
                ReportMetricGrid(metrics: dataset.metrics),
                if (dataset.charts.isNotEmpty) ...[
                  const SizedBox(height: 24),
                  _sectionTitle('Analytics'),
                  const SizedBox(height: 12),
                  ReportChartsGrid(charts: dataset.charts, chartHeight: 230),
                ],
                const SizedBox(height: 24),
                _sectionTitle('Detailed data'),
                const SizedBox(height: 12),
                for (final table in dataset.tables) ...[
                  ReportTableCard(table: table),
                  const SizedBox(height: 14),
                ],
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _header() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: TourismPlanUi.planCardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'ATMOS TRS / OPTACA PORTAL',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.bold,
              color: AppColors.primary,
              letterSpacing: 0.8,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            dataset.title,
            style: const TextStyle(
              fontSize: 23,
              fontWeight: FontWeight.bold,
              color: AppColors.textDark,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Period: ${dataset.periodLabel}',
            style: const TextStyle(fontSize: 13.5, color: AppColors.textGrey),
          ),
          Text(
            'Date generated: ${formatReportDateTime(dataset.generatedAt)}',
            style: const TextStyle(fontSize: 13.5, color: AppColors.textGrey),
          ),
          if (dataset.filterSummary.isNotEmpty) ...[
            const SizedBox(height: 14),
            const Text(
              'Selected filters',
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.bold,
                color: AppColors.textGrey,
                letterSpacing: 0.5,
              ),
            ),
            const SizedBox(height: 8),
            ReportFilterChipsRow(filters: dataset.filterSummary),
          ],
        ],
      ),
    );
  }

  Widget _sectionTitle(String text) => Text(
    text.toUpperCase(),
    style: const TextStyle(
      fontSize: 12.5,
      fontWeight: FontWeight.bold,
      color: AppColors.textGrey,
      letterSpacing: 0.6,
    ),
  );
}

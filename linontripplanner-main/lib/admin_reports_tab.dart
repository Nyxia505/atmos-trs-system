import 'package:flutter/material.dart';

import 'data.dart';
import 'services/reports/report_models.dart';
import 'trip_plan_host_bridge.dart';

/// Supplies the province-wide DOT Excel / PDF panel. The trip planner package
/// cannot import that panel, so the host app sets this before the portal opens.
typedef AdminDotReportsBuilder = Widget Function(
  BuildContext context,
  ReportFilters filters,
);

/// Admin DOT Reports tab: Official DOT forms only.
///
/// Legacy Exports & Summaries / Analytics UI was removed from this tab.
/// Report generation services remain available for other callers.
class AdminReportsTab extends StatelessWidget {
  /// Kept for call-site compatibility with the dashboard; unused after the
  /// Analytics / Exports toolbar was removed.
  final VoidCallback? onOpenMatrixFares;

  /// Host-app DOT forms (Excel and PDF).
  static AdminDotReportsBuilder? dotReportsBuilder;

  const AdminReportsTab({super.key, this.onOpenMatrixFares});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final pad = constraints.maxWidth < 620 ? 14.0 : 20.0;
        final dotReports = AdminReportsTab.dotReportsBuilder;
        final hostDotReports = TripPlanHostBridge.officialDotReports;
        final officialDotPanel = dotReports != null
            ? dotReports(context, ReportFilters.none)
            : hostDotReports?.call(context);

        if (officialDotPanel == null) {
          return Padding(
            padding: EdgeInsets.fromLTRB(pad, 20, pad, 36),
            child: const Text(
              'Official DOT forms are not available in this build.',
              style: TextStyle(fontSize: 14, color: AppColors.textGrey),
            ),
          );
        }

        return SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(pad, 20, pad, 36),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'OFFICIAL DOT FORMS',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                  color: AppColors.textGrey,
                  letterSpacing: 0.6,
                ),
              ),
              const SizedBox(height: 6),
              const Text(
                'Same forms as ATMOS TRS tourism@gmail.com: preview, then Excel or PDF.',
                style: TextStyle(
                  fontSize: 13,
                  height: 1.35,
                  color: AppColors.textGrey,
                ),
              ),
              const SizedBox(height: 12),
              officialDotPanel,
            ],
          ),
        );
      },
    );
  }
}

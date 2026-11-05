import 'package:flutter/material.dart';

import 'data.dart';
import 'services/admin_accounts_service.dart';
import 'services/auth_roles.dart';
import 'services/reports/report_export_service.dart';
import 'services/reports/report_models.dart';
import 'services/reports/reports_service.dart';
import 'widgets/reports/report_analytics_view.dart';
import 'widgets/reports/report_export_dialog.dart';
import 'widgets/reports/report_preview_page.dart';
import 'widgets/tourism_plan_ui.dart';
import 'trip_plan_host_bridge.dart';

/// Supplies the province-wide DOT Excel / PDF panel. The trip planner package
/// cannot import that panel, so the host app sets this before the portal opens.
typedef AdminDotReportsBuilder = Widget Function(
  BuildContext context,
  ReportFilters filters,
);

/// Admin Reports tab: report cards, filters, analytics, preview, and export.
///
/// Report data and analytics come from [ReportsService]; file generation and
/// download come from [ReportExportService]. This widget only orchestrates.
class AdminReportsTab extends StatefulWidget {
  /// Opens the Matrix Fares management tab, when the dashboard provides it.
  final VoidCallback? onOpenMatrixFares;

  /// Host-app DOT forms (Excel and PDF). Null keeps the existing reports only.
  static AdminDotReportsBuilder? dotReportsBuilder;

  const AdminReportsTab({super.key, this.onOpenMatrixFares});

  @override
  State<AdminReportsTab> createState() => _AdminReportsTabState();
}

class _AdminReportsTabState extends State<AdminReportsTab> {
  ReportKind _kind = ReportKind.touristArrivals;
  ReportFilters _filters = ReportFilters.none;

  ReportDataset? _dataset;
  String? _error;
  bool _loading = true;
  bool _exporting = false;

  /// Token guarding against a slow earlier load overwriting a newer one.
  int _loadToken = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load({bool refresh = false}) async {
    final token = ++_loadToken;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final dataset = await ReportsService.build(
        kind: _kind,
        filters: _filters,
        refresh: refresh,
      );
      if (!mounted || token != _loadToken) return;
      setState(() {
        _dataset = dataset;
        _loading = false;
      });
    } on ReportDataException catch (e) {
      if (!mounted || token != _loadToken) return;
      setState(() {
        _error = e.message;
        _dataset = null;
        _loading = false;
      });
    } catch (e) {
      if (!mounted || token != _loadToken) return;
      setState(() {
        _error =
            'Something went wrong while building this report. Please try again.';
        _dataset = null;
        _loading = false;
      });
    }
  }

  Future<bool> _isAuthorizedToExport() async {
    if (AuthRoles.canAccessAdminDashboard()) return true;
    try {
      return await AdminAccountsService.isCurrentUserAdminAccount();
    } catch (_) {
      return false;
    }
  }

  /// Full export flow: authorize, pick a format, re-read Firestore, generate,
  /// download, then report the outcome.
  Future<void> _export(BuildContext context, ReportKind kind) async {
    if (_exporting) return;
    final messenger = ScaffoldMessenger.of(context);

    if (!await _isAuthorizedToExport()) {
      messenger.showSnackBar(
        const SnackBar(
          content: Text(
            'Only authorized administrators can export reports.',
          ),
        ),
      );
      return;
    }
    if (!context.mounted) return;

    final scopedTitle = reportTitleFor(kind, _filters.effectiveMunicipality);
    final format = await showReportExportDialog(
      context,
      kind: kind,
      generatedAt: DateTime.now(),
      municipality: _filters.effectiveMunicipality,
    );
    if (format == null) return;
    if (!mounted) return;

    setState(() => _exporting = true);
    messenger.showSnackBar(
      SnackBar(
        duration: const Duration(seconds: 30),
        content: Text('Preparing $scopedTitle (${format.label})…'),
      ),
    );

    try {
      // Re-read so the file reflects the newest data, not a stale tab load.
      final dataset = await ReportsService.build(
        kind: kind,
        filters: _filters,
        refresh: true,
      );
      if (dataset.hasNoRows) {
        final lgu = _filters.effectiveMunicipality;
        messenger
          ..hideCurrentSnackBar()
          ..showSnackBar(
            SnackBar(
              content: Text(
                lgu == null
                    ? 'No records matched the selected filters, so there is '
                          'nothing to export. Adjust the filters and try again.'
                    : 'No records for $lgu matched the selected filters, so '
                          'there is nothing to export. Widen the date range or '
                          'switch to the overall report.',
              ),
            ),
          );
        return;
      }

      final result = await ReportExportService.export(
        dataset: dataset,
        format: format,
      );

      // Keep the tab in sync with what was just exported.
      if (mounted && kind == _kind) {
        setState(() => _dataset = dataset);
      }

      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            backgroundColor: const Color(0xFF2E7D32),
            duration: const Duration(seconds: 5),
            content: Text(
              '${dataset.title} exported successfully. '
              'Saved ${result.fileName} to ${result.destination}.',
            ),
          ),
        );
    } on ReportDataException catch (e) {
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(e.message)));
    } on ReportExportException catch (e) {
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            backgroundColor: const Color(0xFFC62828),
            content: Text(e.message),
          ),
        );
    } catch (_) {
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(
            backgroundColor: Color(0xFFC62828),
            content: Text('Unable to export report. Please try again.'),
          ),
        );
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  Future<void> _openPreview(ReportKind kind) async {
    // The preview must show this report even if another one is selected.
    var dataset = kind == _kind ? _dataset : null;
    if (dataset == null) {
      final messenger = ScaffoldMessenger.of(context);
      messenger.showSnackBar(
        SnackBar(
          duration: const Duration(seconds: 20),
          content: Text('Building ${kind.title} preview…'),
        ),
      );
      try {
        dataset = await ReportsService.build(kind: kind, filters: _filters);
        messenger.hideCurrentSnackBar();
      } on ReportDataException catch (e) {
        messenger
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(content: Text(e.message)));
        return;
      } catch (_) {
        messenger
          ..hideCurrentSnackBar()
          ..showSnackBar(
            const SnackBar(
              content: Text('Could not build the preview. Please try again.'),
            ),
          );
        return;
      }
    }
    if (!mounted) return;
    final built = dataset;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => _PreviewHost(
          dataset: built,
          onExport: (previewContext) => _export(previewContext, kind),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final pad = constraints.maxWidth < 620 ? 14.0 : 20.0;
        final dotReports = AdminReportsTab.dotReportsBuilder;
        final hostDotReports = TripPlanHostBridge.officialDotReports;
        final officialDotPanel = dotReports != null
            ? dotReports(context, _filters)
            : hostDotReports?.call(context);
        return SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(pad, 20, pad, 36),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (officialDotPanel != null) ...[
                _sectionTitle('Official DOT forms'),
                const SizedBox(height: 12),
                officialDotPanel,
                const SizedBox(height: 24),
              ],
              _sectionTitle('Analytics'),
              const SizedBox(height: 12),
              _analytics(),
            ],
          ),
        );
      },
    );
  }

  Widget _analytics() {
    if (_loading) {
      return Container(
        height: 220,
        alignment: Alignment.center,
        decoration: TourismPlanUi.planCardDecoration(),
        child: const Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(color: AppColors.primary),
            SizedBox(height: 14),
            Text(
              'Calculating analytics…',
              style: TextStyle(fontSize: 13, color: AppColors.textGrey),
            ),
          ],
        ),
      );
    }

    final error = _error;
    if (error != null) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(24),
        decoration: TourismPlanUi.planCardDecoration(),
        child: Column(
          children: [
            const Icon(
              Icons.error_outline,
              size: 40,
              color: Color(0xFFC62828),
            ),
            const SizedBox(height: 12),
            Text(
              error,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 13.5,
                color: AppColors.textDark,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: () => _load(refresh: true),
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
              ),
              icon: const Icon(Icons.refresh, size: 18),
              label: const Text('Try again'),
            ),
          ],
        ),
      );
    }

    final dataset = _dataset;
    if (dataset == null) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _analyticsHeader(dataset),
        if (dataset.warning != null) ...[
          const SizedBox(height: 14),
          ReportWarningBanner(message: dataset.warning!),
        ],
        const SizedBox(height: 16),
        if (dataset.hasNoRows)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(28),
            decoration: TourismPlanUi.planCardDecoration(),
            child: Column(
              children: [
                Icon(
                  Icons.search_off_outlined,
                  size: 44,
                  color: AppColors.primary.withValues(alpha: 0.45),
                ),
                const SizedBox(height: 14),
                const Text(
                  'No results for these filters',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: AppColors.textDark,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  _filters.effectiveMunicipality == null
                      ? 'Nothing in the database matched the selected filters. '
                            'Widen the date range or reset the filters.'
                      : 'No records for ${_filters.effectiveMunicipality} matched the '
                            'selected filters. Widen the date range, or switch '
                            'the scope back to the overall report.',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 13,
                    color: AppColors.textGrey,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          )
        else ...[
          ReportMetricGrid(metrics: dataset.metrics),
          const SizedBox(height: 14),
          _chartsLiveInTheReportNote(),
        ],
      ],
    );
  }

  Widget _chartsLiveInTheReportNote() {
    return Align(
      alignment: Alignment.centerRight,
      child: OutlinedButton.icon(
        onPressed: _exporting ? null : () => _openPreview(_kind),
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.textDark,
          side: BorderSide(
            color: AppColors.primary.withValues(alpha: 0.35),
          ),
          padding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 13,
          ),
        ),
        icon: const Icon(Icons.visibility_outlined, size: 18),
        label: const Text('Open preview'),
      ),
    );
  }

  Widget _analyticsHeader(ReportDataset dataset) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: TourismPlanUi.planCardDecoration(
        color: AppColors.listTilePeach,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(dataset.kind.icon, size: 20, color: AppColors.primary),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  dataset.title,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: AppColors.textDark,
                  ),
                ),
              ),
              IconButton(
                tooltip: 'Refresh from the database',
                onPressed: _exporting ? null : () => _load(refresh: true),
                icon: const Icon(Icons.refresh, size: 19),
                color: AppColors.primary,
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'Period: ${dataset.periodLabel}',
            style: const TextStyle(fontSize: 12.5, color: AppColors.textGrey),
          ),
          const SizedBox(height: 10),
          ReportFilterChipsRow(filters: dataset.filterSummary),
        ],
      ),
    );
  }

  Widget _sectionTitle(String text) => Text(
    text.toUpperCase(),
    style: const TextStyle(
      fontSize: 13,
      fontWeight: FontWeight.bold,
      color: AppColors.textGrey,
      letterSpacing: 0.6,
    ),
  );
}

/// Hosts [ReportPreviewPage] so the Export button there can show its own
/// progress state and post messages on the preview's scaffold.
class _PreviewHost extends StatefulWidget {
  final ReportDataset dataset;
  final Future<void> Function(BuildContext context) onExport;

  const _PreviewHost({required this.dataset, required this.onExport});

  @override
  State<_PreviewHost> createState() => _PreviewHostState();
}

class _PreviewHostState extends State<_PreviewHost> {
  bool _exporting = false;

  @override
  Widget build(BuildContext context) {
    return ReportPreviewPage(
      dataset: widget.dataset,
      exporting: _exporting,
      onExport: () async {
        setState(() => _exporting = true);
        try {
          await widget.onExport(context);
        } finally {
          if (mounted) setState(() => _exporting = false);
        }
      },
    );
  }
}

import 'package:flutter/material.dart';

import 'data.dart';
import 'services/admin_accounts_service.dart';
import 'services/auth_roles.dart';
import 'services/reports/report_export_service.dart';
import 'services/reports/report_models.dart';
import 'services/reports/reports_service.dart';
import 'widgets/reports/report_analytics_view.dart';
import 'widgets/reports/report_export_dialog.dart';
import 'widgets/reports/report_filter_bar.dart';
import 'widgets/reports/report_preview_page.dart';
import 'widgets/tourism_plan_ui.dart';

/// Admin Reports tab: report cards, filters, analytics, preview, and export.
///
/// Report data and analytics come from [ReportsService]; file generation and
/// download come from [ReportExportService]. This widget only orchestrates.
class AdminReportsTab extends StatefulWidget {
  /// Opens the Matrix Fares management tab, when the dashboard provides it.
  final VoidCallback? onOpenMatrixFares;

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

  /// Cached so build() does not re-sort the catalog on every frame.
  ReportFilterOptions _options = ReportsService.filterOptions();

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
        // A refresh may have added spots, events, or fares.
        _options = ReportsService.filterOptions(
          municipality: _filters.effectiveMunicipality,
        );
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

  void _selectKind(ReportKind kind) {
    if (kind == _kind) return;
    setState(() {
      _kind = kind;
      // Drop filters the new report does not support so results stay honest.
      _filters = _prune(_filters, kind);
    });
    _load();
  }

  static ReportFilters _prune(ReportFilters filters, ReportKind kind) {
    final supported = kind.supportedFilters;
    return ReportFilters(
      scope: supported.contains(ReportFilterField.municipality)
          ? filters.scope
          : ReportScope.overall,
      dateRange: supported.contains(ReportFilterField.dateRange)
          ? filters.dateRange
          : null,
      municipality: supported.contains(ReportFilterField.municipality)
          ? filters.municipality
          : null,
      touristSpot: supported.contains(ReportFilterField.touristSpot)
          ? filters.touristSpot
          : null,
      eventId: supported.contains(ReportFilterField.event)
          ? filters.eventId
          : null,
      transportType: supported.contains(ReportFilterField.transportType)
          ? filters.transportType
          : null,
    );
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
        return SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(pad, 20, pad, 36),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _sectionTitle('Exports & summaries'),
              const SizedBox(height: 12),
              _reportCards(),
              const SizedBox(height: 24),
              _sectionTitle('Analytics'),
              const SizedBox(height: 12),
              ReportFilterBar(
                kind: _kind,
                applied: _filters,
                options: _options,
                busy: _loading || _exporting,
                onApply: (next) {
                  setState(() {
                    _filters = next;
                    _options = ReportsService.filterOptions(
                      municipality: next.effectiveMunicipality,
                    );
                  });
                  _load();
                },
                onReset: () {
                  setState(() {
                    _filters = ReportFilters.none;
                    _options = ReportsService.filterOptions();
                  });
                  _load();
                },
              ),
              const SizedBox(height: 16),
              _analytics(),
            ],
          ),
        );
      },
    );
  }

  Widget _reportCards() {
    return Container(
      decoration: TourismPlanUi.planCardDecoration(),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          for (final kind in ReportKind.values) ...[
            _ReportTile(
              kind: kind,
              selected: kind == _kind,
              busy: _exporting,
              // Every report honours the LGU scope, so each card states the
              // one it will download.
              scope: _filters.scopeLabel,
              scopedToOneLgu: !_filters.isOverall,
              onSelect: () => _selectKind(kind),
              onPreview: () => _openPreview(kind),
              onExport: () => _export(context, kind),
              onManage: kind == ReportKind.matrixFares
                  ? widget.onOpenMatrixFares
                  : null,
            ),
            if (kind != ReportKind.values.last) const Divider(height: 1),
          ],
        ],
      ),
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
          _chartsLiveInTheReportNote(dataset),
        ],
      ],
    );
  }

  /// The tab shows headline numbers only; charts and detail tables belong to
  /// the preview and the downloaded file. Say where they went.
  Widget _chartsLiveInTheReportNote(ReportDataset dataset) {
    final chartCount = dataset.charts.where((c) => c.hasData).length;
    final tableCount = dataset.tables.where((t) => !t.isEmpty).length;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: TourismPlanUi.planCardDecoration(),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final narrow = constraints.maxWidth < 520;
          final message = Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(
                Icons.insert_chart_outlined,
                size: 20,
                color: AppColors.primary,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Charts and detailed tables are in the report',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textDark,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      '$chartCount ${chartCount == 1 ? 'chart' : 'charts'} and '
                      '$tableCount detailed '
                      '${tableCount == 1 ? 'table' : 'tables'} are included in '
                      'the preview and in every exported PDF, CSV, and Excel '
                      'file, using these same filters.',
                      style: const TextStyle(
                        fontSize: 12.5,
                        color: AppColors.textGrey,
                        height: 1.4,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          );

          final action = OutlinedButton.icon(
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
          );

          if (narrow) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [message, const SizedBox(height: 12), action],
            );
          }
          return Row(
            children: [
              Expanded(child: message),
              const SizedBox(width: 14),
              action,
            ],
          );
        },
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

class _ReportTile extends StatelessWidget {
  final ReportKind kind;
  final bool selected;
  final bool busy;

  /// The LGU scope this card will preview and export.
  final String scope;
  final bool scopedToOneLgu;
  final VoidCallback onSelect;
  final VoidCallback onPreview;
  final VoidCallback onExport;

  /// Matrix Fares only: opens the existing fare management tab.
  final VoidCallback? onManage;

  const _ReportTile({
    required this.kind,
    required this.selected,
    required this.busy,
    required this.scope,
    required this.scopedToOneLgu,
    required this.onSelect,
    required this.onPreview,
    required this.onExport,
    this.onManage,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onSelect,
      child: Container(
        color: selected ? AppColors.listTilePeach : Colors.transparent,
        padding: const EdgeInsets.fromLTRB(18, 14, 18, 14),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final narrow = constraints.maxWidth < 560;
            final label = Row(
              children: [
                CircleAvatar(
                  backgroundColor: AppColors.primary.withValues(alpha: 0.1),
                  child: Icon(kind.icon, color: AppColors.primary),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        kind.title,
                        style: const TextStyle(
                          fontWeight: FontWeight.w600,
                          color: AppColors.textDark,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        kind.subtitle,
                        style: const TextStyle(
                          fontSize: 13,
                          color: AppColors.textGrey,
                        ),
                      ),
                      const SizedBox(height: 6),
                      _scopePill(),
                    ],
                  ),
                ),
              ],
            );

            final actions = Wrap(
              spacing: 8,
              runSpacing: 8,
              alignment: narrow ? WrapAlignment.start : WrapAlignment.end,
              children: [
                if (onManage != null)
                  TextButton(
                    onPressed: busy ? null : onManage,
                    style: TextButton.styleFrom(
                      foregroundColor: AppColors.primary,
                    ),
                    child: const Text('Manage'),
                  ),
                OutlinedButton(
                  onPressed: busy ? null : onPreview,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.textDark,
                    side: BorderSide(
                      color: AppColors.primary.withValues(alpha: 0.35),
                    ),
                  ),
                  child: const Text('Preview'),
                ),
                FilledButton.tonal(
                  onPressed: busy ? null : onExport,
                  child: const Text('Export'),
                ),
              ],
            );

            if (narrow) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [label, const SizedBox(height: 12), actions],
              );
            }
            return Row(
              children: [
                Expanded(child: label),
                const SizedBox(width: 12),
                actions,
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _scopePill() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
      decoration: BoxDecoration(
        color: scopedToOneLgu
            ? AppColors.primary.withValues(alpha: 0.12)
            : Colors.black.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            scopedToOneLgu
                ? Icons.location_city_outlined
                : Icons.public_outlined,
            size: 13,
            color: scopedToOneLgu ? AppColors.primary : AppColors.textGrey,
          ),
          const SizedBox(width: 5),
          Text(
            scope,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: scopedToOneLgu ? AppColors.primary : AppColors.textGrey,
            ),
          ),
        ],
      ),
    );
  }
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

import 'package:flutter/material.dart';

import '../../data.dart';
import '../../services/admin_accounts_service.dart';
import '../../services/auth_roles.dart';
import '../../services/reports/report_export_service.dart';
import '../../services/reports/report_models.dart';
import '../../services/reports/reports_service.dart';
import '../../trip_plan_host_bridge.dart';
import 'report_export_dialog.dart';
import 'report_preview_page.dart';

/// Events & Announcements / Matrix Fares inside Official DOT forms
/// "Fill forms for". Reuses the existing report preview/export pipeline.
class AdminFillFormsExtraPanel extends StatefulWidget {
  const AdminFillFormsExtraPanel({
    super.key,
    required this.kind,
    this.onManage,
  });

  final ReportKind kind;
  final VoidCallback? onManage;

  @override
  State<AdminFillFormsExtraPanel> createState() =>
      _AdminFillFormsExtraPanelState();
}

class _AdminFillFormsExtraPanelState extends State<AdminFillFormsExtraPanel> {
  bool _exporting = false;

  @override
  void didUpdateWidget(AdminFillFormsExtraPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.kind != widget.kind && _exporting) {
      _exporting = false;
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

  Future<void> _openPreview() async {
    final messenger = ScaffoldMessenger.of(context);
    messenger.showSnackBar(
      SnackBar(
        duration: const Duration(seconds: 20),
        content: Text('Building ${widget.kind.title} preview…'),
      ),
    );
    try {
      final dataset = await ReportsService.build(
        kind: widget.kind,
        filters: ReportFilters.none,
      );
      messenger.hideCurrentSnackBar();
      if (!mounted) return;
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => _ExtraPreviewHost(
            dataset: dataset,
            onExport: _export,
          ),
        ),
      );
    } on ReportDataException catch (e) {
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(e.message)));
    } catch (_) {
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(
            content: Text('Could not build the preview. Please try again.'),
          ),
        );
    }
  }

  Future<void> _export(BuildContext context) async {
    if (_exporting) return;
    final messenger = ScaffoldMessenger.of(context);

    if (!await _isAuthorizedToExport()) {
      messenger.showSnackBar(
        const SnackBar(
          content: Text('Only authorized administrators can export reports.'),
        ),
      );
      return;
    }
    if (!context.mounted) return;

    final format = await showReportExportDialog(
      context,
      kind: widget.kind,
      generatedAt: DateTime.now(),
    );
    if (format == null) return;
    if (!mounted) return;

    setState(() => _exporting = true);
    messenger.showSnackBar(
      SnackBar(
        duration: const Duration(seconds: 30),
        content: Text('Preparing ${widget.kind.title} (${format.label})…'),
      ),
    );

    try {
      final dataset = await ReportsService.build(
        kind: widget.kind,
        filters: ReportFilters.none,
        refresh: true,
      );
      if (dataset.hasNoRows) {
        messenger
          ..hideCurrentSnackBar()
          ..showSnackBar(
            const SnackBar(
              content: Text(
                'No records matched, so there is nothing to export.',
              ),
            ),
          );
        return;
      }

      final result = await ReportExportService.export(
        dataset: dataset,
        format: format,
      );

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

  @override
  Widget build(BuildContext context) {
    final kind = widget.kind;
    final manage = widget.onManage ??
        (kind == ReportKind.matrixFares
            ? TripPlanHostBridge.openMatrixFaresTab
            : null);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
      decoration: BoxDecoration(
        color: AppColors.listTilePeach.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.18)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          LayoutBuilder(
            builder: (context, constraints) {
              final stack = constraints.maxWidth < 560;
              final identity = Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha: 0.12),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(kind.icon, color: AppColors.primary, size: 22),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          kind.title,
                          style: const TextStyle(
                            fontSize: 15.5,
                            fontWeight: FontWeight.w800,
                            color: AppColors.textDark,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                              color: Colors.black.withValues(alpha: 0.08),
                            ),
                          ),
                          child: const Text(
                            kOverallScopeLabel,
                            style: TextStyle(
                              fontSize: 11.5,
                              fontWeight: FontWeight.w600,
                              color: AppColors.textGrey,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              );

              final actions = Wrap(
                spacing: 8,
                runSpacing: 8,
                alignment: stack ? WrapAlignment.start : WrapAlignment.end,
                children: [
                  if (manage != null)
                    TextButton(
                      onPressed: _exporting ? null : manage,
                      style: TextButton.styleFrom(
                        foregroundColor: AppColors.primary,
                        textStyle: const TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 14,
                        ),
                      ),
                      child: const Text('Manage'),
                    ),
                  OutlinedButton(
                    onPressed: _exporting ? null : _openPreview,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.textDark,
                      side: BorderSide(
                        color: AppColors.primary.withValues(alpha: 0.45),
                      ),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                    ),
                    child: const Text('Preview'),
                  ),
                  FilledButton.icon(
                    onPressed: _exporting
                        ? null
                        : () => _export(context),
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                    ),
                    icon: _exporting
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(Icons.download_rounded, size: 18),
                    label: Text(_exporting ? 'Exporting…' : 'Export'),
                  ),
                ],
              );

              if (stack) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [identity, const SizedBox(height: 12), actions],
                );
              }
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: identity),
                  const SizedBox(width: 12),
                  actions,
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

class _ExtraPreviewHost extends StatefulWidget {
  const _ExtraPreviewHost({
    required this.dataset,
    required this.onExport,
  });

  final ReportDataset dataset;
  final Future<void> Function(BuildContext context) onExport;

  @override
  State<_ExtraPreviewHost> createState() => _ExtraPreviewHostState();
}

class _ExtraPreviewHostState extends State<_ExtraPreviewHost> {
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

import 'package:flutter/material.dart';

import '../../data.dart';
import '../../services/reports/report_format.dart';
import '../../services/reports/report_models.dart';

/// Asks which file format to download. Returns null when cancelled.
Future<ReportFormat?> showReportExportDialog(
  BuildContext context, {
  required ReportKind kind,
  required DateTime generatedAt,

  /// The LGU the report is scoped to, or null for the overall report.
  String? municipality,
}) {
  return showDialog<ReportFormat>(
    context: context,
    builder: (_) => _ReportExportDialog(
      kind: kind,
      generatedAt: generatedAt,
      municipality: municipality,
    ),
  );
}

class _ReportExportDialog extends StatefulWidget {
  final ReportKind kind;
  final DateTime generatedAt;
  final String? municipality;

  const _ReportExportDialog({
    required this.kind,
    required this.generatedAt,
    this.municipality,
  });

  @override
  State<_ReportExportDialog> createState() => _ReportExportDialogState();
}

class _ReportExportDialogState extends State<_ReportExportDialog> {
  ReportFormat _selected = ReportFormat.pdf;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      titlePadding: const EdgeInsets.fromLTRB(24, 22, 24, 0),
      contentPadding: const EdgeInsets.fromLTRB(24, 14, 24, 0),
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Export report',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: AppColors.textDark,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            widget.kind.title,
            style: const TextStyle(fontSize: 13, color: AppColors.textGrey),
          ),
        ],
      ),
      content: SizedBox(
        width: 380,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _scopeBanner(),
            const SizedBox(height: 12),
            const Text(
              'Choose a file format. The download uses the filters currently '
              'applied on the Reports page.',
              style: TextStyle(
                fontSize: 12.5,
                color: AppColors.textGrey,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 14),
            for (final format in ReportFormat.values) ...[
              _FormatOption(
                format: format,
                fileName: reportFileName(
                  widget.kind,
                  format,
                  widget.generatedAt,
                  municipality: widget.municipality,
                ),
                selected: _selected == format,
                onTap: () => setState(() => _selected = format),
              ),
              if (format != ReportFormat.values.last)
                const SizedBox(height: 8),
            ],
          ],
        ),
      ),
      actionsPadding: const EdgeInsets.fromLTRB(18, 10, 18, 16),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          style: TextButton.styleFrom(foregroundColor: AppColors.textGrey),
          child: const Text('Cancel'),
        ),
        FilledButton.icon(
          onPressed: () => Navigator.of(context).pop(_selected),
          style: FilledButton.styleFrom(
            backgroundColor: AppColors.primary,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 13),
          ),
          icon: const Icon(Icons.download_outlined, size: 18),
          label: Text('Download ${_selected.label}'),
        ),
      ],
    );
  }

  /// States plainly whether the file will cover one LGU or the whole province,
  /// since that is the easiest thing to get wrong before hitting Download.
  Widget _scopeBanner() {
    final lgu = widget.municipality;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.listTilePeach,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(
            lgu == null ? Icons.public_outlined : Icons.location_city_outlined,
            size: 18,
            color: AppColors.primary,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Scope',
                  style: TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textGrey,
                    letterSpacing: 0.4,
                  ),
                ),
                Text(
                  lgu ?? kOverallScopeLabel,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textDark,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _FormatOption extends StatelessWidget {
  final ReportFormat format;
  final String fileName;
  final bool selected;
  final VoidCallback onTap;

  const _FormatOption({
    required this.format,
    required this.fileName,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: selected ? AppColors.listTilePeach : AppColors.insetSurface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: selected
                ? AppColors.primary
                : Colors.black.withValues(alpha: 0.08),
            width: selected ? 1.6 : 1,
          ),
        ),
        child: Row(
          children: [
            Icon(
              format.icon,
              size: 22,
              color: selected ? AppColors.primary : AppColors.textGrey,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    format.label,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textDark,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    format.description,
                    style: const TextStyle(
                      fontSize: 11.5,
                      color: AppColors.textGrey,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    fileName,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 11,
                      fontFamily: 'monospace',
                      color: AppColors.textGrey.withValues(alpha: 0.95),
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              selected
                  ? Icons.radio_button_checked
                  : Icons.radio_button_unchecked,
              size: 19,
              color: selected ? AppColors.primary : AppColors.textGrey,
            ),
          ],
        ),
      ),
    );
  }
}

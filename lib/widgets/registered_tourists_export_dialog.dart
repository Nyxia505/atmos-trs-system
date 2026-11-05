import 'package:atmos_trs_system/utils/lgu_registered_tourists_xlsx.dart';
import 'package:atmos_trs_system/utils/pdf_file_download.dart';
import 'package:atmos_trs_system/utils/registered_tourists_pdf.dart';
import 'package:atmos_trs_system/utils/xlsx_file_download.dart';
import 'package:atmos_trs_system/widgets/atmos_table_kit.dart';
import 'package:flutter/material.dart';

const _kPreviewLimit = 40;

/// Preview first, then build Excel/PDF only when the Governor/LGU clicks download.
Future<void> showRegisteredTouristsExportDialog({
  required BuildContext context,
  required List<LguRegisteredTouristExportRow> rows,
  required String officeLabel,
  required String location,
  required String privacyLabel,
  required String subtitle,
  Color accent = const Color(0xFFF97316),
  Color cardBg = Colors.white,
  Color textDark = const Color(0xFF111827),
  Color textMuted = const Color(0xFF6B7280),
}) {
  return showDialog<void>(
    context: context,
    builder: (ctx) => RegisteredTouristsExportDialog(
      rows: rows,
      officeLabel: officeLabel,
      location: location,
      privacyLabel: privacyLabel,
      subtitle: subtitle,
      accent: accent,
      cardBg: cardBg,
      textDark: textDark,
      textMuted: textMuted,
    ),
  );
}

class RegisteredTouristsExportDialog extends StatefulWidget {
  const RegisteredTouristsExportDialog({
    super.key,
    required this.rows,
    required this.officeLabel,
    required this.location,
    required this.privacyLabel,
    required this.subtitle,
    required this.accent,
    required this.cardBg,
    required this.textDark,
    required this.textMuted,
  });

  final List<LguRegisteredTouristExportRow> rows;
  final String officeLabel;
  final String location;
  final String privacyLabel;
  final String subtitle;
  final Color accent;
  final Color cardBg;
  final Color textDark;
  final Color textMuted;

  @override
  State<RegisteredTouristsExportDialog> createState() =>
      _RegisteredTouristsExportDialogState();
}

class _RegisteredTouristsExportDialogState
    extends State<RegisteredTouristsExportDialog> {
  String? _busy;
  String? _error;

  Future<void> _save(String kind) async {
    if (_busy != null) return;
    setState(() {
      _busy = kind;
      _error = null;
    });
    await Future<void>.delayed(Duration.zero);
    final generatedAt = DateTime.now();
    try {
      if (kind == 'pdf') {
        final bytes = await buildRegisteredTouristsPdf(
          officeLabel: widget.officeLabel,
          location: widget.location,
          rows: widget.rows,
          generatedAt: generatedAt,
          privacyLabel: widget.privacyLabel,
        );
        if (!mounted) return;
        await downloadPdfFile(
          registeredTouristsPdfFilename(
            location: widget.location,
            generatedAt: generatedAt,
          ),
          bytes,
          openAfterDownload: true,
        );
      } else {
        final bytes = LguRegisteredTouristsXlsx(
          lguLocation: widget.location,
          rows: widget.rows,
          generatedAt: generatedAt,
          includeRestrictedPersonalInfo: false,
          officeLabel: widget.officeLabel,
          privacyLabel: widget.privacyLabel,
        ).buildBytes();
        if (!mounted) return;
        await downloadXlsxFile(
          lguRegisteredTouristsXlsxFilename(
            lguLocation: widget.location,
            generatedAt: generatedAt,
          ),
          bytes,
          openAfterDownload: true,
        );
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = null;
        _error = 'Could not prepare the $kind file. Try again.';
      });
      return;
    }
    if (!mounted) return;
    final messenger = ScaffoldMessenger.maybeOf(context);
    Navigator.pop(context);
    messenger?.showSnackBar(
      SnackBar(
        content: Text(
          kind == 'pdf'
              ? (pdfDownloadUsesShareSheet
                  ? 'PDF ready to save or open'
                  : 'PDF download started — opening file')
              : (xlsxDownloadUsesShareSheet
                  ? 'Excel workbook ready to save or open'
                  : 'Excel download started — opening file'),
        ),
        backgroundColor: widget.accent,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final w = MediaQuery.of(context).size.width;
    final h = MediaQuery.of(context).size.height;
    final preview = widget.rows.take(_kPreviewLimit).toList();
    final textStyle = TextStyle(color: widget.textDark, fontSize: 13);
    final extra = widget.rows.length > _kPreviewLimit
        ? ' Preview shows $_kPreviewLimit of ${widget.rows.length}; download includes every record.'
        : '';

    Widget action({
      required String kind,
      required IconData icon,
      required String label,
    }) {
      final busy = _busy == kind;
      return TextButton.icon(
        onPressed: _busy == null ? () => _save(kind) : null,
        icon: busy
            ? SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: widget.accent,
                ),
              )
            : Icon(icon, color: widget.accent, size: 20),
        label: Text(
          busy ? 'Preparing…' : label,
          style: TextStyle(color: widget.accent, fontWeight: FontWeight.w600),
        ),
      );
    }

    return AlertDialog(
      backgroundColor: widget.cardBg,
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      title: Row(
        children: [
          Icon(Icons.table_chart_rounded, color: widget.accent, size: 26),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Registered Tourists export',
              style: TextStyle(
                color: widget.textDark,
                fontSize: 20,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
      content: SizedBox(
        width: w > 900 ? 880 : w * 0.92,
        height: h * 0.62,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              '${widget.subtitle}$extra',
              style: TextStyle(color: widget.textMuted, fontSize: 13),
            ),
            if (_error != null) ...[
              const SizedBox(height: 8),
              Text(_error!, style: const TextStyle(color: Color(0xFFB91C1C), fontSize: 13)),
            ],
            const SizedBox(height: 12),
            Expanded(
              child: widget.rows.isEmpty
                  ? Center(
                      child: Text(
                        'No registered tourists to export.',
                        style: TextStyle(color: widget.textMuted, fontSize: 16),
                      ),
                    )
                  : SingleChildScrollView(
                      child: AtmosResponsiveTable(
                        columns: const [
                          AtmosTableColumn('Tourist ID', minWidth: 120),
                          AtmosTableColumn('Type', minWidth: 90),
                          AtmosTableColumn('Origin', flex: 2, minWidth: 140),
                          AtmosTableColumn(
                            'Visits',
                            minWidth: 72,
                            align: Alignment.centerRight,
                          ),
                          AtmosTableColumn('Status', minWidth: 90),
                          AtmosTableColumn('Date', minWidth: 110),
                          AtmosTableColumn('Time', minWidth: 90),
                        ],
                        rows: [
                          for (final t in preview)
                            [
                              Text(t.touristId, maxLines: 1, overflow: TextOverflow.ellipsis, style: textStyle),
                              Text(t.type, maxLines: 1, overflow: TextOverflow.ellipsis, style: textStyle),
                              Text(t.origin, maxLines: 1, overflow: TextOverflow.ellipsis, style: textStyle),
                              Text('${t.visits}', maxLines: 1, overflow: TextOverflow.ellipsis, style: textStyle),
                              Text(t.status, maxLines: 1, overflow: TextOverflow.ellipsis, style: textStyle),
                              Text(t.registeredDate, maxLines: 1, overflow: TextOverflow.ellipsis, style: textStyle),
                              Text(t.registeredTime, maxLines: 1, overflow: TextOverflow.ellipsis, style: textStyle),
                            ],
                        ],
                      ),
                    ),
            ),
          ],
        ),
      ),
      actions: [
        action(
          kind: 'xlsx',
          icon: Icons.download_rounded,
          label: 'Download Excel',
        ),
        action(
          kind: 'pdf',
          icon: Icons.picture_as_pdf_rounded,
          label: 'Download PDF',
        ),
        TextButton(
          onPressed: _busy == null ? () => Navigator.pop(context) : null,
          child: Text('Close', style: TextStyle(color: widget.accent)),
        ),
      ],
    );
  }
}

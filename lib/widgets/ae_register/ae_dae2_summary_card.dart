import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import 'package:atmos_trs_system/models/ae_register.dart';
import 'package:atmos_trs_system/utils/ae_register_calculator.dart';
import 'package:atmos_trs_system/widgets/ae_register/ae_sheet_kit.dart';
import 'package:atmos_trs_system/widgets/establishment_dash_tokens.dart';

/// DAE2_Auto sheet: "Monthly Reporting Format for Accommodation Establishment".
/// Visual layout only — values still come from [AeRegisterCalculator.dae2Summary].
class AeDae2SummaryCard extends StatelessWidget {
  const AeDae2SummaryCard({
    super.key,
    required this.report,
    required this.totals,
    required this.readOnly,
    this.issueCount = 0,
    this.busy = false,
    this.onSubmit,
    this.onWithdraw,
    this.onOpenReports,
  });

  final AeMonthlyReport report;
  final AeMonthTotals totals;
  final bool readOnly;
  final int issueCount;
  final bool busy;
  final VoidCallback? onSubmit;
  final VoidCallback? onWithdraw;

  /// Opens the official DOT Reports tab (unchanged export templates).
  final VoidCallback? onOpenReports;

  static const Color _primary = Color(0xFFF97316);
  static const Color _darkOrange = Color(0xFFEA580C);
  static const Color _lightOrange = Color(0xFFFFF7ED);
  static const Color _darkText = Color(0xFF1F2937);
  static const Color _secondaryText = Color(0xFF64748B);
  static const Color _border = Color(0xFFE5E7EB);

  @override
  Widget build(BuildContext context) {
    final items = AeRegisterCalculator.dae2Summary(report, totals);
    final submitted = report.isSubmitted;
    final byNo = {for (final i in items) i.no: i};

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: double.infinity,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: _border),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF0F172A).withValues(alpha: 0.04),
                blurRadius: 16,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 16, 18, 12),
                child: LayoutBuilder(
                  builder: (context, c) {
                    final narrow = c.maxWidth < 720;
                    final titleBlock = Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          width: 36,
                          height: 36,
                          decoration: BoxDecoration(
                            color: _lightOrange,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: const Icon(Icons.apartment_rounded, color: _primary, size: 20),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Monthly Reporting Format for Accommodation Establishment',
                                style: GoogleFonts.inter(
                                  fontSize: 15.5,
                                  fontWeight: FontWeight.w700,
                                  color: _darkText,
                                  height: 1.25,
                                  letterSpacing: -0.2,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                'DOT DAE-2 · Monthly Tourist Establishment Report',
                                style: GoogleFonts.inter(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w500,
                                  color: _secondaryText,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    );
                    void openOfficialReports() {
                      if (onOpenReports != null) {
                        onOpenReports!();
                        return;
                      }
                      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
                        const SnackBar(
                          content: Text(
                            'Official DOT PDF/Excel downloads are in the Reports tab (or LGU Analytics).',
                          ),
                          behavior: SnackBarBehavior.floating,
                        ),
                      );
                    }

                    final actions = Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        _exportChip(
                          icon: Icons.picture_as_pdf_outlined,
                          label: 'Export PDF',
                          onTap: openOfficialReports,
                        ),
                        _exportChip(
                          icon: Icons.grid_on_rounded,
                          label: 'Export Excel',
                          onTap: openOfficialReports,
                        ),
                        _exportChip(
                          icon: Icons.print_outlined,
                          label: 'Print Report',
                          onTap: () => _printSummary(context, items),
                        ),
                      ],
                    );
                    if (narrow) {
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          titleBlock,
                          const SizedBox(height: 12),
                          actions,
                        ],
                      );
                    }
                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(child: titleBlock),
                        const SizedBox(width: 12),
                        actions,
                      ],
                    );
                  },
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(
                    color: _lightOrange,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFFFED7AA)),
                  ),
                  child: Wrap(
                    spacing: 14,
                    runSpacing: 8,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      _metaChip(Icons.map_outlined, 'Province', report.province),
                      _metaChip(Icons.location_city_outlined, 'Municipality/City', report.municipality),
                      _metaChip(Icons.calendar_month_outlined, 'Month/Year',
                          '${AeSheetKit.monthName(report.month)} ${report.year}'),
                      _metaChip(Icons.event_available_outlined, 'Days', '${report.days}'),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                          color: submitted ? _primary : Colors.white,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: submitted ? _darkOrange : const Color(0xFFFDBA74)),
                        ),
                        child: Text(
                          'Report Status: ${submitted ? 'Submitted' : 'Draft'}',
                          style: GoogleFonts.inter(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w700,
                            color: submitted ? Colors.white : _darkOrange,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 0, 14, 8),
                child: LayoutBuilder(
                  builder: (context, c) {
                    final twoCol = c.maxWidth >= 780;
                    final left = Column(
                      children: [
                        _section(
                          letter: 'A',
                          title: 'Establishment Information',
                          rows: [1, 2, 3, 4].map((n) => byNo[n]!).toList(),
                        ),
                        const SizedBox(height: 12),
                        _section(
                          letter: 'B',
                          title: 'Occupancy and Guest Statistics',
                          rows: [5, 6, 7, 8].map((n) => byNo[n]!).toList(),
                        ),
                      ],
                    );
                    final right = Column(
                      children: [
                        _section(
                          letter: 'C',
                          title: 'Guest Classification',
                          rows: [9, 10, 11, 12, 13, 14, 15, 16].map((n) => byNo[n]!).toList(),
                        ),
                        const SizedBox(height: 12),
                        _section(
                          letter: 'D',
                          title: 'Performance Indicators',
                          rows: [17, 18].map((n) => byNo[n]!).toList(),
                        ),
                      ],
                    );
                    if (!twoCol) {
                      return Column(children: [left, const SizedBox(height: 12), right]);
                    }
                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(child: left),
                        const SizedBox(width: 14),
                        Expanded(child: right),
                      ],
                    );
                  },
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 4, 18, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _footnote(
                      '* (1) It is not necessary to disclose the name of the AE in the report if the AE does not want to disclose its name.',
                    ),
                    _footnote(
                      '** (8), (17) and (18) are important business performance indicators.',
                    ),
                    _footnote(
                      '*** When guest arrivals and guest nights are segregated according to residence [(9) to (16)], '
                      'these numbers should be the ones reported and not just the total volume.',
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: submitted ? const Color(0xFFF0FDF4) : _lightOrange,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: submitted ? const Color(0xFFBBF7D0) : const Color(0xFFFED7AA),
            ),
          ),
          child: Row(
            children: [
              Icon(
                submitted ? Icons.verified_rounded : Icons.pending_actions_rounded,
                color: submitted ? AeDashTokens.success : _primary,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      submitted ? 'Submitted to LGU' : 'Draft — not yet submitted',
                      style: AeDashTokens.section(size: 14),
                    ),
                    Text(
                      submitted
                          ? 'Your LGU tourism office, OPTACA and the Governor can see this month'
                              '${report.lastSignOff == null ? '' : ' (signed by ${report.lastSignOff!.name}, ${report.lastSignOff!.position})'}. '
                              'Later edits need a signature and a reason.'
                          : 'Your LGU sees drafts as "in progress". Submit when the month is complete — '
                              'you will sign with your name and position.'
                              '${issueCount > 0 ? ' Fix $issueCount validation issue(s) first.' : ''}',
                      style: AeDashTokens.body(size: 12),
                    ),
                  ],
                ),
              ),
              if (!readOnly) ...[
                const SizedBox(width: 12),
                if (busy)
                  const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2))
                else if (submitted)
                  OutlinedButton(onPressed: onWithdraw, child: const Text('Back to draft'))
                else
                  FilledButton.icon(
                    style: FilledButton.styleFrom(backgroundColor: _primary),
                    onPressed: issueCount > 0 ? null : onSubmit,
                    icon: const Icon(Icons.send_rounded, size: 18),
                    label: const Text('Submit to LGU'),
                  ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _section({
    required String letter,
    required String title,
    required List<AeDae2Item> rows,
  }) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
            decoration: const BoxDecoration(
              color: _lightOrange,
              borderRadius: BorderRadius.vertical(top: Radius.circular(11)),
            ),
            child: Text(
              '$letter. $title',
              style: GoogleFonts.inter(
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
                color: _darkOrange,
              ),
            ),
          ),
          for (var i = 0; i < rows.length; i++) ...[
            if (i > 0) const Divider(height: 1, thickness: 1, color: _border),
            _row(rows[i]),
          ],
        ],
      ),
    );
  }

  Widget _row(AeDae2Item i) {
    final highlight = i.kpi;
    return Container(
      color: highlight ? _lightOrange : Colors.white,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          SizedBox(
            width: 34,
            child: Text(
              '(${i.no})',
              style: GoogleFonts.inter(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: _secondaryText,
              ),
            ),
          ),
          Expanded(
            child: Text(
              i.label,
              style: GoogleFonts.inter(
                fontSize: 12.5,
                fontWeight: highlight ? FontWeight.w700 : FontWeight.w500,
                fontStyle: highlight ? FontStyle.italic : FontStyle.normal,
                color: _darkText,
                height: 1.3,
              ),
            ),
          ),
          const SizedBox(width: 10),
          ConstrainedBox(
            constraints: const BoxConstraints(minWidth: 72, maxWidth: 160),
            child: Text(
              i.value.isEmpty ? '—' : i.value,
              textAlign: TextAlign.right,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.inter(
                fontSize: 13,
                fontWeight: FontWeight.w800,
                color: _darkText,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _metaChip(IconData icon, String label, String value) {
    final display = value.trim().isEmpty ? '—' : value;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: _primary),
        const SizedBox(width: 5),
        Text(
          '$label: ',
          style: GoogleFonts.inter(fontSize: 11.5, fontWeight: FontWeight.w600, color: _secondaryText),
        ),
        Text(
          display,
          style: GoogleFonts.inter(fontSize: 11.5, fontWeight: FontWeight.w700, color: _darkText),
        ),
      ],
    );
  }

  Widget _footnote(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.only(top: 5),
            child: Icon(Icons.circle, size: 5, color: _primary),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: GoogleFonts.inter(fontSize: 11, height: 1.35, color: _secondaryText),
            ),
          ),
        ],
      ),
    );
  }

  Widget _exportChip({
    required IconData icon,
    required String label,
    VoidCallback? onTap,
  }) {
    return OutlinedButton.icon(
      onPressed: onTap,
      style: OutlinedButton.styleFrom(
        foregroundColor: _primary,
        side: const BorderSide(color: Color(0xFFFDBA74)),
        backgroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        minimumSize: const Size(0, 36),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
      icon: Icon(icon, size: 16),
      label: Text(
        label,
        style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w700),
      ),
    );
  }

  Future<void> _printSummary(BuildContext context, List<AeDae2Item> items) async {
    final title = 'DAE-2 · ${report.aeName} · ${AeSheetKit.monthName(report.month)} ${report.year}';
    try {
      await Printing.layoutPdf(
        name: title,
        onLayout: (format) async {
          final doc = pw.Document();
          doc.addPage(
            pw.MultiPage(
              pageFormat: format,
              build: (ctx) => [
                pw.Text(
                  'Monthly Reporting Format for Accommodation Establishment',
                  style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold),
                ),
                pw.SizedBox(height: 4),
                pw.Text(
                  'DOT DAE-2 summary (on-screen values). Official DOT templates: Reports tab.',
                  style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey700),
                ),
                pw.SizedBox(height: 10),
                pw.Text(
                  '${report.aeName} · ${report.municipality} · ${AeSheetKit.monthName(report.month)} ${report.year}',
                  style: const pw.TextStyle(fontSize: 10),
                ),
                pw.SizedBox(height: 12),
                pw.Table(
                  border: pw.TableBorder.all(color: PdfColors.grey400, width: 0.5),
                  columnWidths: {
                    0: const pw.FixedColumnWidth(36),
                    1: const pw.FlexColumnWidth(3),
                    2: const pw.FlexColumnWidth(1.4),
                  },
                  children: [
                    for (final i in items)
                      pw.TableRow(
                        children: [
                          pw.Padding(
                            padding: const pw.EdgeInsets.all(4),
                            child: pw.Text('(${i.no})', style: const pw.TextStyle(fontSize: 9)),
                          ),
                          pw.Padding(
                            padding: const pw.EdgeInsets.all(4),
                            child: pw.Text(i.label, style: const pw.TextStyle(fontSize: 9)),
                          ),
                          pw.Padding(
                            padding: const pw.EdgeInsets.all(4),
                            child: pw.Text(
                              i.value.isEmpty ? '—' : i.value,
                              textAlign: pw.TextAlign.right,
                              style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold),
                            ),
                          ),
                        ],
                      ),
                  ],
                ),
              ],
            ),
          );
          return doc.save();
        },
      );
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        SnackBar(content: Text('Could not print: $e'), behavior: SnackBarBehavior.floating),
      );
    }
  }
}

import 'dart:convert';
import 'dart:typed_data';

import 'package:csv/csv.dart' show Csv;
import 'package:excel/excel.dart' hide Border;
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import 'report_file_saver.dart';
import 'report_format.dart';
import 'report_models.dart';

/// Raised when a report file cannot be produced or saved.
class ReportExportException implements Exception {
  final String message;
  const ReportExportException(this.message);

  @override
  String toString() => message;
}

/// Result of a successful export.
class ReportExportResult {
  final String fileName;

  /// Where the file landed — a path on desktop, or a phrase like
  /// "your browser downloads" on web.
  final String destination;

  const ReportExportResult({required this.fileName, required this.destination});
}

/// Turns a [ReportDataset] into a PDF, CSV, or XLSX file and saves it.
///
/// Every format is generated from the same [ReportDataset], so a downloaded
/// file always matches the filtered analytics shown on screen.
class ReportExportService {
  ReportExportService._();

  static const String _brand = 'ATMoS TRS / OPTACA Portal';

  static Future<ReportExportResult> export({
    required ReportDataset dataset,
    required ReportFormat format,
  }) async {
    final fileName = reportFileName(
      dataset.kind,
      format,
      dataset.generatedAt,
      municipality: dataset.filters.effectiveMunicipality,
    );
    final Uint8List bytes;
    try {
      bytes = await generateBytes(dataset: dataset, format: format);
    } catch (e, st) {
      debugPrint('ReportExportService.generateBytes($format): $e\n$st');
      throw const ReportExportException(
        'Unable to export report. Please try again.',
      );
    }
    if (bytes.isEmpty) {
      throw const ReportExportException(
        'Unable to export report. Please try again.',
      );
    }
    try {
      final destination = await saveReportFile(
        fileName: fileName,
        bytes: bytes,
        mimeType: format.mimeType,
      );
      return ReportExportResult(fileName: fileName, destination: destination);
    } catch (e, st) {
      debugPrint('ReportExportService.save($fileName): $e\n$st');
      throw const ReportExportException(
        'The report was generated but could not be saved. '
        'Check your download permissions and try again.',
      );
    }
  }

  static Future<Uint8List> generateBytes({
    required ReportDataset dataset,
    required ReportFormat format,
  }) async {
    return switch (format) {
      ReportFormat.csv => _buildCsv(dataset),
      ReportFormat.xlsx => _buildXlsx(dataset),
      ReportFormat.pdf => _buildPdf(dataset),
    };
  }

  // ─── CSV ─────────────────────────────────────────────────────────────

  static Uint8List _buildCsv(ReportDataset dataset) {
    final rows = <List<Object?>>[
      [_brand],
      [dataset.title],
      ['Generated', formatReportDateTime(dataset.generatedAt)],
      ['Period', dataset.periodLabel],
      for (final f in dataset.filterSummary) [f.$1, f.$2],
      if (dataset.warning != null) ['Note', dataset.warning],
      [],
      ['SUMMARY'],
      ['Metric', 'Value', 'Detail'],
      for (final m in dataset.metrics) [m.label, m.value, m.caption ?? ''],
    ];

    for (final chart in dataset.charts) {
      rows
        ..add([])
        ..add([chart.title.toUpperCase()])
        ..add(['Label', chart.valueSuffix.isEmpty ? 'Value' : chart.valueSuffix]);
      for (var i = 0; i < chart.labels.length; i++) {
        rows.add([chart.labels[i], _trimNumber(chart.values[i])]);
      }
      if (chart.labels.isEmpty) rows.add(['No data']);
    }

    for (final table in dataset.tables) {
      rows
        ..add([])
        ..add([table.title.toUpperCase()])
        ..add(table.columns);
      if (table.isEmpty) {
        rows.add(['No records matched the selected filters']);
      } else {
        rows.addAll(table.rows);
      }
    }

    // addBom so Excel opens the UTF-8 file with the right encoding.
    final text = Csv(addBom: true).encode(rows);
    return Uint8List.fromList(utf8.encode(text));
  }

  // ─── XLSX ────────────────────────────────────────────────────────────

  static Uint8List _buildXlsx(ReportDataset dataset) {
    final book = Excel.createExcel();
    final defaultSheet = book.getDefaultSheet();

    const summaryName = 'Summary';
    final summary = book[summaryName];
    summary
      ..appendRow([TextCellValue(_brand)])
      ..appendRow([TextCellValue(dataset.title)])
      ..appendRow([
        TextCellValue('Generated'),
        TextCellValue(formatReportDateTime(dataset.generatedAt)),
      ])
      ..appendRow([
        TextCellValue('Period'),
        TextCellValue(dataset.periodLabel),
      ]);
    for (final f in dataset.filterSummary) {
      summary.appendRow([TextCellValue(f.$1), TextCellValue(f.$2)]);
    }
    final warning = dataset.warning;
    if (warning != null) {
      summary.appendRow([TextCellValue('Note'), TextCellValue(warning)]);
    }
    summary
      ..appendRow([])
      ..appendRow([
        TextCellValue('Metric'),
        TextCellValue('Value'),
        TextCellValue('Detail'),
      ]);
    for (final m in dataset.metrics) {
      summary.appendRow([
        TextCellValue(m.label),
        TextCellValue(m.value),
        TextCellValue(m.caption ?? ''),
      ]);
    }

    for (final chart in dataset.charts) {
      summary
        ..appendRow([])
        ..appendRow([TextCellValue(chart.title)])
        ..appendRow([
          TextCellValue('Label'),
          TextCellValue(chart.valueSuffix.isEmpty ? 'Value' : chart.valueSuffix),
        ]);
      for (var i = 0; i < chart.labels.length; i++) {
        summary.appendRow([
          TextCellValue(chart.labels[i]),
          DoubleCellValue(chart.values[i]),
        ]);
      }
    }

    final usedNames = <String>{summaryName.toLowerCase()};
    for (final table in dataset.tables) {
      final name = _uniqueSheetName(table.title, usedNames);
      final sheet = book[name];
      sheet.appendRow([for (final c in table.columns) TextCellValue(c)]);
      if (table.isEmpty) {
        sheet.appendRow([
          TextCellValue('No records matched the selected filters'),
        ]);
        continue;
      }
      for (final row in table.rows) {
        sheet.appendRow([
          for (var i = 0; i < row.length; i++)
            if (table.numericColumns.contains(i))
              _numericCell(row[i])
            else
              TextCellValue(row[i]),
        ]);
      }
    }

    // Drop the empty sheet Excel.createExcel() starts with.
    if (defaultSheet != null && defaultSheet != summaryName) {
      try {
        book.delete(defaultSheet);
      } catch (e) {
        debugPrint('ReportExportService: could not drop $defaultSheet: $e');
      }
    }

    final encoded = book.encode();
    if (encoded == null) {
      throw const ReportExportException(
        'Unable to export report. Please try again.',
      );
    }
    return Uint8List.fromList(encoded);
  }

  static CellValue _numericCell(String raw) {
    final cleaned = raw.replaceAll(',', '').trim();
    final asInt = int.tryParse(cleaned);
    if (asInt != null) return IntCellValue(asInt);
    final asDouble = double.tryParse(cleaned);
    if (asDouble != null) return DoubleCellValue(asDouble);
    return TextCellValue(raw);
  }

  /// Excel sheet names cap at 31 characters and forbid `[]:*?/\`.
  static String _uniqueSheetName(String title, Set<String> used) {
    var base = title.replaceAll(RegExp(r'[\[\]:\*\?\/\\]'), ' ').trim();
    if (base.isEmpty) base = 'Sheet';
    if (base.length > 31) base = base.substring(0, 31).trim();
    var candidate = base;
    var n = 2;
    while (used.contains(candidate.toLowerCase())) {
      final suffix = ' $n';
      final room = 31 - suffix.length;
      candidate = '${base.length > room ? base.substring(0, room) : base}$suffix';
      n++;
    }
    used.add(candidate.toLowerCase());
    return candidate;
  }

  // ─── PDF ─────────────────────────────────────────────────────────────

  static const _pdfOrange = PdfColor.fromInt(0xFFFF7A00);
  static const _pdfInk = PdfColor.fromInt(0xFF1C1C1C);
  static const _pdfGrey = PdfColor.fromInt(0xFF666666);
  static const _pdfTint = PdfColor.fromInt(0xFFFFF2EB);

  static Future<Uint8List> _buildPdf(ReportDataset dataset) async {
    final doc = pw.Document(title: dataset.title, author: _brand);

    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4.landscape,
        margin: const pw.EdgeInsets.fromLTRB(28, 28, 28, 36),
        header: (context) => context.pageNumber == 1
            ? pw.SizedBox()
            : pw.Padding(
                padding: const pw.EdgeInsets.only(bottom: 12),
                child: pw.Text(
                  _pdfSafe(dataset.title),
                  style: pw.TextStyle(
                    fontSize: 9,
                    color: _pdfGrey,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
              ),
        footer: (context) => pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Text(
              _pdfSafe(_brand),
              style: const pw.TextStyle(fontSize: 8, color: _pdfGrey),
            ),
            pw.Text(
              'Page ${context.pageNumber} of ${context.pagesCount}',
              style: const pw.TextStyle(fontSize: 8, color: _pdfGrey),
            ),
          ],
        ),
        build: (context) => [
          _pdfTitleBlock(dataset),
          pw.SizedBox(height: 16),
          _pdfSectionLabel('Summary statistics'),
          pw.SizedBox(height: 8),
          _pdfMetricGrid(dataset.metrics),
          for (final table in dataset.tables) ...[
            pw.SizedBox(height: 18),
            _pdfSectionLabel(table.title),
            pw.SizedBox(height: 8),
            _pdfTable(table),
          ],
        ],
      ),
    );

    return doc.save();
  }

  static pw.Widget _pdfTitleBlock(ReportDataset dataset) {
    return pw.Container(
      padding: const pw.EdgeInsets.all(16),
      decoration: const pw.BoxDecoration(color: _pdfTint),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(
            _pdfSafe(_brand),
            style: pw.TextStyle(
              fontSize: 9,
              color: _pdfOrange,
              fontWeight: pw.FontWeight.bold,
            ),
          ),
          pw.SizedBox(height: 4),
          pw.Text(
            _pdfSafe(dataset.title),
            style: pw.TextStyle(
              fontSize: 20,
              color: _pdfInk,
              fontWeight: pw.FontWeight.bold,
            ),
          ),
          pw.SizedBox(height: 2),
          pw.Text(
            'Period: ${_pdfSafe(dataset.periodLabel)}',
            style: const pw.TextStyle(fontSize: 10, color: _pdfGrey),
          ),
          pw.Text(
            'Date generated: ${_pdfSafe(formatReportDateTime(dataset.generatedAt))}',
            style: const pw.TextStyle(fontSize: 10, color: _pdfGrey),
          ),
          pw.SizedBox(height: 8),
          pw.Wrap(
            spacing: 16,
            runSpacing: 3,
            children: [
              for (final f in dataset.filterSummary)
                pw.Text(
                  '${_pdfSafe(f.$1)}: ${_pdfSafe(f.$2)}',
                  style: const pw.TextStyle(fontSize: 9, color: _pdfInk),
                ),
            ],
          ),
          if (dataset.warning != null) ...[
            pw.SizedBox(height: 6),
            pw.Text(
              'Note: ${_pdfSafe(dataset.warning!)}',
              style: const pw.TextStyle(fontSize: 8, color: _pdfGrey),
            ),
          ],
        ],
      ),
    );
  }

  static pw.Widget _pdfSectionLabel(String text) => pw.Text(
    _pdfSafe(text).toUpperCase(),
    style: pw.TextStyle(
      fontSize: 10,
      color: _pdfGrey,
      fontWeight: pw.FontWeight.bold,
      letterSpacing: 0.6,
    ),
  );

  static pw.Widget _pdfMetricGrid(List<ReportMetric> metrics) {
    if (metrics.isEmpty) return pw.SizedBox();
    return pw.Wrap(
      spacing: 10,
      runSpacing: 10,
      children: [
        for (final m in metrics)
          pw.Container(
            width: 170,
            padding: const pw.EdgeInsets.all(10),
            decoration: pw.BoxDecoration(
              border: pw.Border.all(color: _pdfOrange, width: 0.5),
            ),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(
                  _pdfSafe(m.label),
                  style: const pw.TextStyle(fontSize: 8, color: _pdfGrey),
                ),
                pw.SizedBox(height: 3),
                pw.Text(
                  _pdfSafe(m.value),
                  style: pw.TextStyle(
                    fontSize: 13,
                    color: _pdfInk,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
                if (m.caption != null)
                  pw.Text(
                    _pdfSafe(m.caption!),
                    style: const pw.TextStyle(fontSize: 7, color: _pdfGrey),
                  ),
              ],
            ),
          ),
      ],
    );
  }

  static pw.Widget _pdfTable(ReportTable table) {
    if (table.isEmpty) {
      return pw.Text(
        'No records matched the selected filters.',
        style: const pw.TextStyle(fontSize: 9, color: _pdfGrey),
      );
    }
    return pw.TableHelper.fromTextArray(
      headers: [for (final c in table.columns) _pdfSafe(c)],
      data: [
        for (final row in table.rows) [for (final cell in row) _pdfSafe(cell)],
      ],
      headerStyle: pw.TextStyle(
        fontSize: 8,
        color: PdfColors.white,
        fontWeight: pw.FontWeight.bold,
      ),
      headerDecoration: const pw.BoxDecoration(color: _pdfOrange),
      cellStyle: const pw.TextStyle(fontSize: 8, color: _pdfInk),
      oddRowDecoration: const pw.BoxDecoration(color: _pdfTint),
      cellHeight: 14,
      headerAlignment: pw.Alignment.centerLeft,
      cellAlignment: pw.Alignment.centerLeft,
      border: pw.TableBorder.all(color: _pdfGrey, width: 0.2),
    );
  }

  /// The PDF built-in fonts cover WinAnsi only, so glyphs like `↔` and `★`
  /// would render as blanks. Map the ones this app uses and drop the rest.
  static String _pdfSafe(String input) {
    const replacements = {
      '↔': '<->',
      '→': '->',
      '←': '<-',
      '★': '*',
      '₱': 'PHP ',
      '–': '-',
      '—': '-',
      '…': '...',
      '“': '"',
      '”': '"',
      '‘': "'",
      '’': "'",
      '·': '-',
      '\u00A0': ' ',
    };
    var out = input;
    replacements.forEach((from, to) => out = out.replaceAll(from, to));
    return out.runes
        .map((r) => r <= 0xFF ? String.fromCharCode(r) : '?')
        .join();
  }

  /// `12.0` → `12`, `12.34` → `12.3`.
  static String _trimNumber(double v) =>
      v == v.roundToDouble() ? v.round().toString() : v.toStringAsFixed(1);
}

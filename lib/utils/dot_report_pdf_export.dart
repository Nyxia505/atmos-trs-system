import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import 'package:atmos_trs_system/config/supabase_report_templates_config.dart';
import 'package:atmos_trs_system/utils/dot_report_preview.dart';

const _kFontRegularAsset = 'assets/fonts/noto_sans/NotoSans-Regular.ttf';
const _kFontBoldAsset = 'assets/fonts/noto_sans/NotoSans-Bold.ttf';
const _kLogoAsset = 'assets/images/asenso_misamis_occidental_circular_logo.png';

final _kAccent = PdfColor.fromHex('#EA580C');
final _kAccentSoft = PdfColor.fromHex('#FFF7ED');
final _kAccentLine = PdfColor.fromHex('#FDBA74');
final _kInk = PdfColor.fromHex('#0F172A');
final _kMuted = PdfColor.fromHex('#64748B');
final _kBorder = PdfColor.fromHex('#E2E8F0');
final _kZebra = PdfColor.fromHex('#F8FAFC');
final _kGapBg = PdfColor.fromHex('#FFFBEB');
final _kGapLine = PdfColor.fromHex('#F59E0B');

/// Bond paper sizes LGU offices print on (PH short = US Letter, long = 8.5 × 13 in).
enum DotPdfPaperSize { a4, short, long }

extension DotPdfPaperSizeX on DotPdfPaperSize {
  String get label => switch (this) {
        DotPdfPaperSize.a4 => 'A4',
        DotPdfPaperSize.short => 'Short',
        DotPdfPaperSize.long => 'Long',
      };

  String get dimensionsLabel => switch (this) {
        DotPdfPaperSize.a4 => '210 × 297 mm',
        DotPdfPaperSize.short => '8.5 × 11 in',
        DotPdfPaperSize.long => '8.5 × 13 in',
      };

  PdfPageFormat get pageFormat => switch (this) {
        DotPdfPaperSize.a4 => PdfPageFormat.a4,
        DotPdfPaperSize.short => PdfPageFormat.letter,
        DotPdfPaperSize.long =>
          const PdfPageFormat(8.5 * PdfPageFormat.inch, 13 * PdfPageFormat.inch),
      };

  static DotPdfPaperSize fromName(String? name) => DotPdfPaperSize.values
      .firstWhere((p) => p.name == name, orElse: () => DotPdfPaperSize.a4);
}

/// Latest establishment sign-off printed under DAE-family PDFs.
class DotPdfSignOff {
  const DotPdfSignOff({
    required this.label,
    required this.name,
    required this.position,
    required this.action,
    this.signedAt,
    this.signaturePng,
  });

  /// e.g. "Hotel Name · October 2026".
  final String label;
  final String name;
  final String position;
  final String action;
  final DateTime? signedAt;
  final Uint8List? signaturePng;
}

/// Printed signatory line (e.g. CUS "Name of Tourism Officer" / "Mayor").
class DotPdfSignatory {
  const DotPdfSignatory({required this.role, this.name = ''});

  final String role;

  /// Blank prints an empty line to sign by hand.
  final String name;
}

pw.Font? _cachedRegular;
pw.Font? _cachedBold;
pw.MemoryImage? _cachedLogo;

Future<(pw.Font, pw.Font)?> _loadFonts() async {
  if (_cachedRegular != null && _cachedBold != null) {
    return (_cachedRegular!, _cachedBold!);
  }
  try {
    final regular = await rootBundle.load(_kFontRegularAsset);
    final bold = await rootBundle.load(_kFontBoldAsset);
    _cachedRegular = pw.Font.ttf(regular);
    _cachedBold = pw.Font.ttf(bold);
    return (_cachedRegular!, _cachedBold!);
  } catch (_) {
    return null;
  }
}

Future<pw.MemoryImage?> _loadLogo() async {
  if (_cachedLogo != null) return _cachedLogo;
  try {
    final data = await rootBundle.load(_kLogoAsset);
    _cachedLogo = pw.MemoryImage(data.buffer.asUint8List());
    return _cachedLogo;
  } catch (_) {
    return null;
  }
}

/// Built-in Helvetica only covers Latin-1; used when the embedded font is unavailable.
String _asciiSafe(String s) {
  const map = {
    '—': '-',
    '–': '-',
    '‒': '-',
    '−': '-',
    '’': "'",
    '‘': "'",
    '“': '"',
    '”': '"',
    '•': '-',
    '→': '->',
    '…': '...',
    '₱': 'PHP ',
    '\u00A0': ' ',
  };
  final b = StringBuffer();
  for (final rune in s.runes) {
    final ch = String.fromCharCode(rune);
    final mapped = map[ch];
    if (mapped != null) {
      b.write(mapped);
    } else if (rune <= 0xFF) {
      b.write(ch);
    } else {
      b.write('?');
    }
  }
  return b.toString();
}

/// Noto Sans has no arrow / dingbat / emoji glyphs; swap the ones report text uses.
String _notoSafe(String s) {
  const map = {
    '→': '->',
    '←': '<-',
    '⇒': '=>',
    '↑': '^',
    '↓': 'v',
    '✓': 'Yes',
    '✔': 'Yes',
    '✗': 'No',
    '✕': 'x',
    '★': '*',
  };
  final b = StringBuffer();
  for (final rune in s.runes) {
    final ch = String.fromCharCode(rune);
    final mapped = map[ch];
    if (mapped != null) {
      b.write(mapped);
    } else if (rune > 0xFFFF || (rune >= 0x2190 && rune <= 0x27BF)) {
      continue;
    } else {
      b.write(ch);
    }
  }
  return b.toString();
}

const _kMonths = [
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
];

String _fmtDate(DateTime d) => '${_kMonths[d.month - 1]} ${d.day}, ${d.year}';

String _fmtDateTime(DateTime d) {
  final h12 = d.hour % 12 == 0 ? 12 : d.hour % 12;
  final mm = d.minute.toString().padLeft(2, '0');
  return '${_fmtDate(d)}, $h12:$mm ${d.hour < 12 ? 'AM' : 'PM'}';
}

final _numericCell = RegExp(r'^[-+]?[\d,]+(\.\d+)?%?$');

bool _isPlaceholder(String v) {
  final t = v.trim();
  return t.isEmpty || t == '—' || t == '–' || t == '-' || t == 'n/a';
}

/// Builds a printable PDF from the same preview table used in Analytics.
Future<Uint8List> buildDotReportPdfBytes({
  required DotFormCatalogEntry form,
  required DotReportPreviewTable preview,
  required String scopeLabel,
  required DateTime startDate,
  required DateTime endDate,
  DotPdfPaperSize paperSize = DotPdfPaperSize.a4,
  List<DotPdfSignOff> signOffs = const [],
  List<String> unsignedLabels = const [],
  List<DotPdfSignatory> signatories = const [],
}) async {
  final fonts = await _loadFonts();
  final logo = await _loadLogo();
  final t = fonts == null ? _asciiSafe : _notoSafe;

  final doc = pw.Document(
    title: t(form.displayLabel),
    author: 'ATMOS TRS',
    subject: t('$scopeLabel — DOT report'),
    theme: fonts == null
        ? null
        : pw.ThemeData.withFont(base: fonts.$1, bold: fonts.$2),
  );

  final generatedAt = DateTime.now();
  final periodLine = '${_fmtDate(startDate)} – ${_fmtDate(endDate)}';

  final colCount = preview.headers.length;
  final allRows = [
    ...preview.rows,
    if (preview.footer != null) preview.footer!,
  ];
  final numericCols = <int>{};
  final emptyCols = <int>{};
  for (var c = 0; c < colCount; c++) {
    var hasValue = false;
    var allNumeric = true;
    for (final r in allRows) {
      final v = c < r.length ? r[c] : '';
      if (_isPlaceholder(v)) continue;
      hasValue = true;
      if (!_numericCell.hasMatch(v.trim())) {
        allNumeric = false;
        break;
      }
    }
    if (!hasValue) {
      emptyCols.add(c);
    } else if (allNumeric && c > 0) {
      numericCols.add(c);
    }
  }

  final bodySize = colCount > 14
      ? 6.5
      : colCount > 10
          ? 7.5
          : 8.5;
  final headSize = bodySize + 0.3;

  pw.Widget cell(
    String text, {
    required int col,
    bool header = false,
    bool bold = false,
    PdfColor? color,
  }) {
    final alignRight = numericCols.contains(col);
    final alignCenter = emptyCols.contains(col);
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(horizontal: 5, vertical: 4),
      child: pw.Text(
        t(text),
        textAlign: alignRight
            ? pw.TextAlign.right
            : alignCenter
                ? pw.TextAlign.center
                : pw.TextAlign.left,
        style: pw.TextStyle(
          fontSize: header ? headSize : bodySize,
          fontWeight:
              header || bold ? pw.FontWeight.bold : pw.FontWeight.normal,
          color: color ?? _kInk,
        ),
      ),
    );
  }

  List<String> padRow(List<String> r) => [
        for (var c = 0; c < colCount; c++) c < r.length ? r[c] : '',
      ];

  pw.Widget buildTable() {
    return pw.Table(
      border: pw.TableBorder(
        horizontalInside: pw.BorderSide(color: _kBorder, width: 0.5),
        bottom: pw.BorderSide(color: _kBorder, width: 0.5),
      ),
      defaultVerticalAlignment: pw.TableCellVerticalAlignment.middle,
      columnWidths: {
        for (var c = 0; c < colCount; c++)
          c: pw.FlexColumnWidth(
            numericCols.contains(c) || emptyCols.contains(c)
                ? 1
                : c == 0
                    ? 3.2
                    : 1.8,
          ),
      },
      children: [
        pw.TableRow(
          repeat: true,
          decoration: pw.BoxDecoration(color: _kAccent),
          children: [
            for (var c = 0; c < colCount; c++)
              cell(
                preview.headers[c],
                col: c,
                header: true,
                color: PdfColors.white,
              ),
          ],
        ),
        for (var i = 0; i < preview.rows.length; i++)
          pw.TableRow(
            decoration: i.isOdd ? pw.BoxDecoration(color: _kZebra) : null,
            children: [
              for (final (c, v) in padRow(preview.rows[i]).indexed)
                cell(v, col: c),
            ],
          ),
        if (preview.footer != null)
          pw.TableRow(
            decoration: pw.BoxDecoration(
              color: _kAccentSoft,
              border: pw.Border(
                top: pw.BorderSide(color: _kAccentLine, width: 1),
              ),
            ),
            children: [
              for (final (c, v) in padRow(preview.footer!).indexed)
                cell(v, col: c, bold: true),
            ],
          ),
      ],
    );
  }

  pw.Widget metaItem(String label, String value) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text(
          t(label.toUpperCase()),
          style: pw.TextStyle(
            fontSize: 6.5,
            color: _kMuted,
            fontWeight: pw.FontWeight.bold,
            letterSpacing: 0.6,
          ),
        ),
        pw.SizedBox(height: 2),
        pw.Text(
          t(value),
          style: pw.TextStyle(
            fontSize: 9,
            color: _kInk,
            fontWeight: pw.FontWeight.bold,
          ),
        ),
      ],
    );
  }

  pw.Widget firstPageHeader() {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.stretch,
      children: [
        pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.center,
          children: [
            if (logo != null) ...[
              pw.Container(
                width: 42,
                height: 42,
                child: pw.Image(logo, fit: pw.BoxFit.contain),
              ),
              pw.SizedBox(width: 10),
            ],
            pw.Expanded(
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text(
                    t('ATMOS TRS  ·  DOT REPORT'),
                    style: pw.TextStyle(
                      fontSize: 7.5,
                      color: _kAccent,
                      fontWeight: pw.FontWeight.bold,
                      letterSpacing: 1.2,
                    ),
                  ),
                  pw.SizedBox(height: 2),
                  pw.Text(
                    t(form.displayLabel),
                    style: pw.TextStyle(
                      fontSize: 17,
                      color: _kInk,
                      fontWeight: pw.FontWeight.bold,
                    ),
                  ),
                  if (form.subtitle.trim().isNotEmpty)
                    pw.Text(
                      t(form.subtitle),
                      style: pw.TextStyle(fontSize: 8.5, color: _kMuted),
                    ),
                ],
              ),
            ),
            pw.Container(
              padding:
                  const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: pw.BoxDecoration(
                color: _kAccentSoft,
                borderRadius: pw.BorderRadius.circular(10),
                border: pw.Border.all(color: _kAccentLine, width: 0.6),
              ),
              child: pw.Text(
                t(form.capabilityLabel),
                style: pw.TextStyle(
                  fontSize: 7.5,
                  color: _kAccent,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
        pw.SizedBox(height: 10),
        pw.Container(height: 2, color: _kAccent),
        pw.SizedBox(height: 10),
        pw.Container(
          padding: const pw.EdgeInsets.symmetric(horizontal: 12, vertical: 9),
          decoration: pw.BoxDecoration(
            color: _kZebra,
            borderRadius: pw.BorderRadius.circular(6),
            border: pw.Border.all(color: _kBorder, width: 0.6),
          ),
          child: pw.Row(
            children: [
              pw.Expanded(flex: 3, child: metaItem('Reporting unit', scopeLabel)),
              pw.Expanded(flex: 3, child: metaItem('Reporting period', periodLine)),
              pw.Expanded(
                flex: 2,
                child: metaItem('Generated', _fmtDateTime(generatedAt)),
              ),
            ],
          ),
        ),
        pw.SizedBox(height: 8),
        pw.Text(
          t(preview.summaryLine),
          style: pw.TextStyle(fontSize: 9, color: _kMuted),
        ),
        pw.SizedBox(height: 10),
      ],
    );
  }

  pw.Widget continuationHeader() {
    return pw.Container(
      margin: const pw.EdgeInsets.only(bottom: 10),
      padding: const pw.EdgeInsets.only(bottom: 4),
      decoration: pw.BoxDecoration(
        border: pw.Border(bottom: pw.BorderSide(color: _kAccent, width: 1)),
      ),
      child: pw.Row(
        children: [
          pw.Expanded(
            child: pw.Text(
              t(form.displayLabel),
              style: pw.TextStyle(
                fontSize: 9,
                color: _kInk,
                fontWeight: pw.FontWeight.bold,
              ),
            ),
          ),
          pw.Text(
            t('$scopeLabel  ·  $periodLine'),
            style: pw.TextStyle(fontSize: 8, color: _kMuted),
          ),
        ],
      ),
    );
  }

  doc.addPage(
    pw.MultiPage(
      pageFormat: paperSize.pageFormat.landscape,
      margin: const pw.EdgeInsets.fromLTRB(30, 26, 30, 22),
      header: (context) =>
          context.pageNumber == 1 ? firstPageHeader() : continuationHeader(),
      footer: (context) => pw.Container(
        margin: const pw.EdgeInsets.only(top: 10),
        padding: const pw.EdgeInsets.only(top: 5),
        decoration: pw.BoxDecoration(
          border: pw.Border(top: pw.BorderSide(color: _kBorder, width: 0.6)),
        ),
        child: pw.Row(
          children: [
            pw.Expanded(
              child: pw.Text(
                t(
                  'Generated by ATMOS TRS — best-effort fill from current data. '
                  'Not a blank official template.',
                ),
                style: pw.TextStyle(fontSize: 7, color: _kMuted),
              ),
            ),
            pw.Text(
              t('Page ${context.pageNumber} of ${context.pagesCount}'),
              style: pw.TextStyle(
                fontSize: 7,
                color: _kMuted,
                fontWeight: pw.FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
      build: (context) => [
        if (preview.rows.isEmpty)
          pw.Container(
            padding: const pw.EdgeInsets.all(16),
            decoration: pw.BoxDecoration(
              color: _kZebra,
              borderRadius: pw.BorderRadius.circular(6),
              border: pw.Border.all(color: _kBorder, width: 0.6),
            ),
            child: pw.Text(
              t(
                'No data rows for this range. Gaps below explain what ATMOS still needs.',
              ),
              style: pw.TextStyle(fontSize: 10, color: _kMuted),
            ),
          )
        else
          buildTable(),
        if (preview.gaps.isNotEmpty) ...[
          pw.SizedBox(height: 16),
          pw.Container(
            padding: const pw.EdgeInsets.fromLTRB(12, 10, 12, 8),
            decoration: pw.BoxDecoration(
              color: _kGapBg,
              border: pw.Border(
                left: pw.BorderSide(color: _kGapLine, width: 3),
              ),
            ),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(
                  t('ATMOS gaps — not yet derivable from current data'),
                  style: pw.TextStyle(
                    fontSize: 9.5,
                    color: _kInk,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
                pw.SizedBox(height: 6),
                for (final g in preview.gaps)
                  pw.Padding(
                    padding: const pw.EdgeInsets.only(bottom: 3),
                    child: pw.Row(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Container(
                          width: 3.5,
                          height: 3.5,
                          margin: const pw.EdgeInsets.only(top: 4, right: 7),
                          decoration: pw.BoxDecoration(
                            color: _kGapLine,
                            shape: pw.BoxShape.circle,
                          ),
                        ),
                        pw.Expanded(
                          child: pw.Text(
                            t(g),
                            style: pw.TextStyle(fontSize: 8.5, color: _kInk),
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ],
        if (signOffs.isNotEmpty || unsignedLabels.isNotEmpty) ...[
          pw.SizedBox(height: 18),
          pw.Text(
            t(signOffs.length > 1
                ? 'Prepared and certified by (latest establishment sign-offs)'
                : 'Prepared and certified by (latest establishment sign-off)'),
            style: pw.TextStyle(fontSize: 9.5, color: _kInk, fontWeight: pw.FontWeight.bold),
          ),
          pw.SizedBox(height: 8),
          pw.Wrap(
            spacing: 14,
            runSpacing: 12,
            children: [for (final s in signOffs) _signOffBlock(s, t)],
          ),
          if (unsignedLabels.isNotEmpty) ...[
            pw.SizedBox(height: 8),
            pw.Text(
              t('No signature on file: ${unsignedLabels.join('; ')}'),
              style: pw.TextStyle(fontSize: 8, color: _kMuted),
            ),
          ],
        ],
        if (signatories.isNotEmpty) ...[
          pw.SizedBox(height: 28),
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceAround,
            children: [
              for (final s in signatories)
                pw.SizedBox(
                  width: 200,
                  child: pw.Column(
                    children: [
                      pw.SizedBox(
                        height: 14,
                        child: pw.Text(
                          t(s.name.trim().toUpperCase()),
                          style: pw.TextStyle(fontSize: 9.5, color: _kInk, fontWeight: pw.FontWeight.bold),
                        ),
                      ),
                      pw.Container(height: 0.8, color: _kInk),
                      pw.SizedBox(height: 3),
                      pw.Text(t(s.role), style: pw.TextStyle(fontSize: 8.5, color: _kInk)),
                    ],
                  ),
                ),
            ],
          ),
        ],
      ],
    ),
  );

  return doc.save();
}

pw.Widget _signOffBlock(DotPdfSignOff s, String Function(String) t) {
  final png = s.signaturePng;
  return pw.Container(
    width: 230,
    padding: const pw.EdgeInsets.fromLTRB(10, 8, 10, 8),
    decoration: pw.BoxDecoration(
      border: pw.Border.all(color: _kBorder, width: 0.6),
      borderRadius: pw.BorderRadius.circular(6),
    ),
    child: pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Container(
          height: 46,
          width: double.infinity,
          alignment: pw.Alignment.bottomLeft,
          child: png == null ? pw.SizedBox() : pw.Image(pw.MemoryImage(png), fit: pw.BoxFit.contain),
        ),
        pw.Container(height: 0.8, color: _kInk),
        pw.SizedBox(height: 3),
        pw.Text(
          t(s.name),
          style: pw.TextStyle(fontSize: 9.5, color: _kInk, fontWeight: pw.FontWeight.bold),
        ),
        pw.Text(t(s.position), style: pw.TextStyle(fontSize: 8, color: _kInk)),
        pw.SizedBox(height: 2),
        pw.Text(t(s.label), style: pw.TextStyle(fontSize: 7.5, color: _kMuted)),
        pw.Text(
          t('${s.action} · ${s.signedAt == null ? '' : _fmtDateTime(s.signedAt!)}'),
          style: pw.TextStyle(fontSize: 7.5, color: _kMuted),
        ),
      ],
    ),
  );
}

String dotReportPdfFilename({
  required DotFormCatalogEntry form,
  required String scopeSlug,
  required DateTime startDate,
  required DateTime endDate,
  DotPdfPaperSize? paperSize,
}) {
  final s =
      '${startDate.year}${startDate.month.toString().padLeft(2, '0')}${startDate.day.toString().padLeft(2, '0')}';
  final e =
      '${endDate.year}${endDate.month.toString().padLeft(2, '0')}${endDate.day.toString().padLeft(2, '0')}';
  final slug = scopeSlug.trim().isEmpty ? 'report' : scopeSlug.trim();
  final paper = paperSize == null ? '' : '_${paperSize.name}';
  return 'ATMOS_${form.id}_${slug}_${s}_$e$paper.pdf';
}

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;
import 'package:image/image.dart' as img;
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
///
/// [additionalTables] is for multi-section OPTACA summaries (Events,
/// Announcements, Matrix Fares). Official VAR / DAE exports leave it empty
/// so their page layout is unchanged.
Future<Uint8List> buildDotReportPdfBytes({
  required DotFormCatalogEntry form,
  required DotReportPreviewTable preview,
  required String scopeLabel,
  required DateTime startDate,
  required DateTime endDate,
  DotPdfPaperSize paperSize = DotPdfPaperSize.a4,
  List<DotReportPreviewTable> additionalTables = const [],
  List<DotPdfSignOff> signOffs = const [],
  List<String> unsignedLabels = const [],
  List<DotPdfSignatory> signatories = const [],
  bool landscape = false,
  bool? paginateTables,
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
  final sections = [preview, ...additionalTables];
  final showSectionTitles = additionalTables.isNotEmpty;
  // Portal summaries must split inside MultiPage. VAR / DAE keep the original
  // Column-of-Tables layout when [paginateTables] is left unset.
  final splitTables = paginateTables ?? showSectionTitles;
  final isVar2 = form.reportType == DotReportType.var2VisitorRecord;

  String headerLines(String text) {
    final parts = text.trim().split(RegExp(r'\s+'));
    if (parts.length <= 1 || text.trim().length <= 8) return text;
    return parts.join('\n');
  }

  /// Portal tables wrap headers onto two lines so 7-column event / fare
  /// headers stay readable without stacking every word.
  String headerLinesSoft(String text) {
    final value = text.trim();
    if (value.length <= 16) return value;
    final slash = value.indexOf(' / ');
    if (slash > 0) {
      return '${value.substring(0, slash)}\n${value.substring(slash + 3)}';
    }
    final amp = value.indexOf(' & ');
    if (amp > 0) {
      return '${value.substring(0, amp)}\n${value.substring(amp + 3)}';
    }
    final parts = value.split(RegExp(r'\s+'));
    if (parts.length <= 2) return parts.join('\n');
    if (parts.length == 3) return '${parts[0]} ${parts[1]}\n${parts[2]}';
    final mid = (parts.length / 2).ceil();
    return '${parts.take(mid).join(' ')}\n${parts.skip(mid).join(' ')}';
  }

  int longestWord(String text) {
    var longest = 0;
    for (final word in text.split(RegExp(r'\s+'))) {
      if (word.length > longest) longest = word.length;
    }
    return longest;
  }

  pw.Widget buildTable(DotReportPreviewTable table) {
    final colCount = table.headers.length;
    if (colCount == 0) return pw.SizedBox();
    final allRows = [
      ...table.rows,
      if (table.footer != null) table.footer!,
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

    // Portrait pages are narrower than the old landscape layout, so wide
    // forms use a smaller type size and tighter cell padding.
    final bodySize = colCount > 14
        ? 6.0
        : colCount > 10
            ? 6.5
            : colCount > 7
                ? 7.5
                : 8.5;
    final headSize = bodySize + 0.3;
    final cellPadH = colCount > 10 ? 2.0 : 4.0;

    pw.Widget cell(
      String text, {
      required int col,
      bool header = false,
      bool bold = false,
      PdfColor? color,
    }) {
      final alignCenter =
          header || numericCols.contains(col) || emptyCols.contains(col);
      final shown = header
          ? (splitTables ? headerLinesSoft(text) : headerLines(text))
          : text;
      return pw.Padding(
        padding: pw.EdgeInsets.symmetric(
          horizontal: cellPadH,
          vertical: header ? 6 : 3,
        ),
        child: pw.Text(
          t(shown),
          textAlign: alignCenter ? pw.TextAlign.center : pw.TextAlign.left,
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

    double flexFor(int c) {
      final h = table.headers[c].toLowerCase();
      if (h.contains('destination') ||
          h.contains('announcement') ||
          h.contains('details')) {
        return 2.8;
      }
      if (h == 'event' || h.contains('starting')) return 2.2;
      if (h.contains('municipality') || h.contains('venue')) return 2.1;
      if (h.contains('transportation') || h.contains('date')) return 1.6;
      if (h.contains('estimated') || h.contains('travel time')) return 1.5;
      if (c == 0) return 2.6;
      if (numericCols.contains(c) || emptyCols.contains(c)) {
        return longestWord(table.headers[c]) >= 8 ? 1.7 : 1.15;
      }
      return 1.7;
    }

    final columnWidths = <int, pw.TableColumnWidth>{
      for (var c = 0; c < colCount; c++)
        c: pw.FlexColumnWidth(
          splitTables
              ? flexFor(c)
              : (c == 0
                  ? 2.6
                  : numericCols.contains(c) || emptyCols.contains(c)
                      ? (longestWord(table.headers[c]) >= 8 ? 1.7 : 1.15)
                      : 1.7),
        ),
    };

    if (table.rows.isEmpty) {
      return pw.Container(
        width: double.infinity,
        padding: const pw.EdgeInsets.all(12),
        decoration: pw.BoxDecoration(
          color: _kZebra,
          borderRadius: pw.BorderRadius.circular(6),
          border: pw.Border.all(color: _kBorder, width: 0.6),
        ),
        child: pw.Text(
          t('No data rows for this range.'),
          style: pw.TextStyle(fontSize: 9, color: _kMuted),
        ),
      );
    }

    // One Table (not a Column of Tables) so MultiPage can split rows and
    // repeat the orange header. TableHelper uses verticalAlignment.full,
    // which overflows 7-column fare rows off the page.
    if (splitTables) {
      return pw.Table(
        tableWidth: pw.TableWidth.max,
        defaultVerticalAlignment: pw.TableCellVerticalAlignment.middle,
        columnWidths: columnWidths,
        border: pw.TableBorder(
          horizontalInside: pw.BorderSide(color: _kBorder, width: 0.5),
          bottom: pw.BorderSide(color: _kBorder, width: 0.5),
          verticalInside: const pw.BorderSide(color: PdfColors.white, width: 0.9),
        ),
        children: [
          pw.TableRow(
            repeat: true,
            decoration: pw.BoxDecoration(color: _kAccent),
            children: [
              for (var c = 0; c < colCount; c++)
                cell(
                  table.headers[c],
                  col: c,
                  header: true,
                  color: PdfColors.white,
                ),
            ],
          ),
          for (var i = 0; i < table.rows.length; i++)
            pw.TableRow(
              decoration: i.isOdd ? pw.BoxDecoration(color: _kZebra) : null,
              children: [
                for (final (c, v) in padRow(table.rows[i]).indexed)
                  cell(v, col: c),
              ],
            ),
          if (table.footer != null)
            pw.TableRow(
              decoration: pw.BoxDecoration(
                color: _kAccentSoft,
                border: pw.Border(
                  top: pw.BorderSide(color: _kAccentLine, width: 1),
                ),
              ),
              children: [
                for (final (c, v) in padRow(table.footer!).indexed)
                  cell(v, col: c, bold: true),
              ],
            ),
        ],
      );
    }

    return pw.Column(
      children: [
        pw.Table(
          border: const pw.TableBorder(
            verticalInside: pw.BorderSide(color: PdfColors.white, width: 0.9),
          ),
          defaultVerticalAlignment: pw.TableCellVerticalAlignment.middle,
          columnWidths: columnWidths,
          children: [
            pw.TableRow(
              decoration: pw.BoxDecoration(color: _kAccent),
              children: [
                for (var c = 0; c < colCount; c++)
                  cell(
                    table.headers[c],
                    col: c,
                    header: true,
                    color: PdfColors.white,
                  ),
              ],
            ),
          ],
        ),
        pw.Table(
          border: pw.TableBorder(
            horizontalInside: pw.BorderSide(color: _kBorder, width: 0.5),
            verticalInside: isVar2
                ? pw.BorderSide(color: _kBorder, width: 0.5)
                : pw.BorderSide.none,
            bottom: pw.BorderSide(color: _kBorder, width: 0.5),
          ),
          defaultVerticalAlignment: pw.TableCellVerticalAlignment.middle,
          columnWidths: columnWidths,
          children: [
            for (var i = 0; i < table.rows.length; i++)
              pw.TableRow(
                decoration: i.isOdd ? pw.BoxDecoration(color: _kZebra) : null,
                children: [
                  for (final (c, v) in padRow(table.rows[i]).indexed)
                    cell(v, col: c),
                ],
              ),
            if (table.footer != null)
              pw.TableRow(
                decoration: pw.BoxDecoration(
                  color: _kAccentSoft,
                  border: pw.Border(
                    top: pw.BorderSide(color: _kAccentLine, width: 1),
                  ),
                ),
                children: [
                  for (final (c, v) in padRow(table.footer!).indexed)
                    cell(v, col: c, bold: true),
                ],
              ),
          ],
        ),
      ],
    );
  }

  pw.Widget sectionHeading(String title) {
    return pw.Padding(
      padding: const pw.EdgeInsets.only(bottom: 8),
      child: pw.Text(
        t(title.toUpperCase()),
        style: pw.TextStyle(
          fontSize: 9,
          color: _kMuted,
          fontWeight: pw.FontWeight.bold,
          letterSpacing: 0.6,
        ),
      ),
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

  // DAE-1A Manual Tally: clean manager block bottom-left on the last page.
  final isDae1aManual =
      form.id == 'dae1a_manual' || form.code.toUpperCase().contains('DAE-1A');
  final showDae1aSignOff =
      isDae1aManual && (signOffs.isNotEmpty || unsignedLabels.isNotEmpty);

  pw.Widget pageChromeFooter(pw.Context context) {
    return pw.Container(
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
    );
  }

  pw.Widget preparedAndCertifiedSection() {
    return pw.Align(
      alignment: pw.Alignment.centerLeft,
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          if (signOffs.isNotEmpty) ...[
            pw.Text(
              t('Prepared and certified by'),
              style: pw.TextStyle(
                fontSize: 9,
                color: _kInk,
                fontWeight: pw.FontWeight.bold,
              ),
            ),
            pw.SizedBox(height: 10),
            pw.Wrap(
              spacing: 36,
              runSpacing: 14,
              children: [for (final s in signOffs) _managerSignOffBlock(s, t)],
            ),
          ],
          if (unsignedLabels.isNotEmpty) ...[
            if (signOffs.isNotEmpty) pw.SizedBox(height: 8),
            pw.Text(
              t('No signature on file: ${unsignedLabels.join('; ')}'),
              style: pw.TextStyle(fontSize: 8, color: _kMuted),
            ),
          ],
        ],
      ),
    );
  }

  doc.addPage(
    pw.MultiPage(
      pageFormat: landscape
          ? paperSize.pageFormat.landscape
          : paperSize.pageFormat,
      margin: const pw.EdgeInsets.fromLTRB(30, 26, 30, 22),
      header: (context) =>
          context.pageNumber == 1 ? firstPageHeader() : continuationHeader(),
      footer: (context) {
        // Pin DAE-1A signatures to the bottom-left of the last page.
        if (showDae1aSignOff && context.pageNumber == context.pagesCount) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              preparedAndCertifiedSection(),
              pageChromeFooter(context),
            ],
          );
        }
        return pageChromeFooter(context);
      },
      build: (context) => [
        if (!showSectionTitles && preview.rows.isEmpty)
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
          ),
        if (showSectionTitles || preview.rows.isNotEmpty) ...[
          for (var i = 0; i < sections.length; i++) ...[
            if (i > 0 && splitTables)
              pw.NewPage()
            else if (i > 0)
              pw.SizedBox(height: 16),
            if (showSectionTitles && sections[i].title.trim().isNotEmpty)
              sectionHeading(sections[i].title),
            buildTable(sections[i]),
          ],
        ],
        if (!isVar2 && preview.gaps.isNotEmpty) ...[
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
        // Non–DAE-1A forms keep sign-offs in the body (same formal layout).
        if (!isDae1aManual &&
            (signOffs.isNotEmpty || unsignedLabels.isNotEmpty)) ...[
          pw.SizedBox(height: 20),
          preparedAndCertifiedSection(),
        ],
        if (signatories.isNotEmpty) ...[
          pw.SizedBox(height: 24),
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceAround,
            children: [
              for (final s in signatories)
                pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.center,
                  children: [
                    pw.Container(
                      decoration: pw.BoxDecoration(
                        border: pw.Border(
                          bottom: pw.BorderSide(color: _kInk, width: 0.8),
                        ),
                      ),
                      padding: const pw.EdgeInsets.only(bottom: 2),
                      child: pw.Text(
                        t(s.name.trim().isEmpty ? ' ' : s.name.trim().toUpperCase()),
                        style: pw.TextStyle(
                          fontSize: 9.5,
                          color: _kInk,
                          fontWeight: pw.FontWeight.bold,
                        ),
                      ),
                    ),
                    pw.SizedBox(height: 3),
                    pw.Text(t(s.role), style: pw.TextStyle(fontSize: 8.5, color: _kInk)),
                  ],
                ),
            ],
          ),
        ],
      ],
    ),
  );

  return doc.save();
}

/// Crops transparent / near-white margins from a signature PNG for PDF layout only.
/// Does not alter the stored sign-off image.
Uint8List _trimSignaturePngForPdf(Uint8List png) {
  try {
    final decoded = img.decodeImage(png);
    if (decoded == null || decoded.width < 2 || decoded.height < 2) return png;

    var minX = decoded.width;
    var minY = decoded.height;
    var maxX = -1;
    var maxY = -1;

    // Treat near-white / fully transparent pixels as empty pad space.
    bool isInk(img.Pixel p) {
      if (p.a < 24) return false;
      final r = p.r.toInt();
      final g = p.g.toInt();
      final b = p.b.toInt();
      // Light paper / anti-alias fog around strokes.
      if (r > 245 && g > 245 && b > 245) return false;
      return true;
    }

    for (final p in decoded) {
      if (!isInk(p)) continue;
      final x = p.x;
      final y = p.y;
      if (x < minX) minX = x;
      if (y < minY) minY = y;
      if (x > maxX) maxX = x;
      if (y > maxY) maxY = y;
    }

    if (maxX < minX || maxY < minY) return png;

    // Tiny 1px pad so anti-aliased stroke edges aren't clipped.
    minX = math.max(0, minX - 1);
    minY = math.max(0, minY - 1);
    maxX = math.min(decoded.width - 1, maxX + 1);
    maxY = math.min(decoded.height - 1, maxY + 1);

    final w = maxX - minX + 1;
    final h = maxY - minY + 1;
    if (w >= decoded.width - 2 && h >= decoded.height - 2) return png;

    final cropped = img.copyCrop(decoded, x: minX, y: minY, width: w, height: h);
    return Uint8List.fromList(img.encodePng(cropped));
  } catch (_) {
    return png;
  }
}

/// Formal sign-off: trimmed signature centered on name → bold name → underline → Manager.
pw.Widget _managerSignOffBlock(DotPdfSignOff s, String Function(String) t) {
  final rawPng = s.signaturePng;
  final png = rawPng == null ? null : _trimSignaturePngForPdf(rawPng);
  final name = s.name.trim().isEmpty ? ' ' : s.name.trim();
  const nameSize = 10.0;

  return pw.Column(
    // Center signature strokes over the printed name (and Manager under it).
    crossAxisAlignment: pw.CrossAxisAlignment.center,
    mainAxisSize: pw.MainAxisSize.min,
    children: [
      if (png != null)
        pw.ConstrainedBox(
          // ~25% larger than prior 130×28 cap.
          constraints: const pw.BoxConstraints(
            maxWidth: 162,
            maxHeight: 35,
          ),
          child: pw.Image(
            pw.MemoryImage(png),
            fit: pw.BoxFit.contain,
            alignment: pw.Alignment.bottomCenter,
          ),
        ),
      // ~2–4pt gap between visible strokes and the bold name.
      if (png != null) pw.SizedBox(height: 3),
      // Underline width follows the printed name only.
      pw.Container(
        decoration: pw.BoxDecoration(
          border: pw.Border(
            bottom: pw.BorderSide(color: _kInk, width: 0.8),
          ),
        ),
        padding: const pw.EdgeInsets.only(bottom: 2),
        child: pw.Text(
          t(name),
          style: pw.TextStyle(
            fontSize: nameSize,
            color: _kInk,
            fontWeight: pw.FontWeight.bold,
          ),
        ),
      ),
      pw.SizedBox(height: 3),
      pw.Text(
        t('Manager'),
        style: pw.TextStyle(fontSize: 8.5, color: _kInk),
      ),
    ],
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

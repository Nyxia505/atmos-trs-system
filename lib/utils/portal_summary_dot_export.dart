import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:excel/excel.dart';

import 'package:atmos_trs_system/config/supabase_report_templates_config.dart';
import 'package:atmos_trs_system/utils/dot_report_pdf_export.dart';
import 'package:atmos_trs_system/utils/portal_summary_dot_report.dart';
import 'package:trip_plan/services/reports/report_format.dart';
import 'package:trip_plan/services/reports/report_models.dart';

/// Excel / PDF bytes for OPTACA Events, Announcements, and Matrix Fares.
///
/// PDF reuses [buildDotReportPdfBytes] (the VAR / DAE page layout). Excel uses
/// the same orange header, meta block, and table treatment because those
/// forms have no official DOT workbook to fill.
abstract final class PortalSummaryDotExport {
  static const _brand = 'ATMOS TRS  ·  DOT REPORT';

  static const _accentHex = 'FFEA580C';
  static const _accentSoftHex = 'FFFFF7ED';
  static const _inkHex = 'FF0F172A';
  static const _mutedHex = 'FF64748B';
  static const _borderHex = 'FFE2E8F0';
  static const _zebraHex = 'FFF8FAFC';
  static const _whiteHex = 'FFFFFFFF';

  static Future<Uint8List> buildPdf({
    required DotFormCatalogEntry form,
    required ReportDataset dataset,
    required String scopeLabel,
    required DateTime startDate,
    required DateTime endDate,
    DotPdfPaperSize paperSize = DotPdfPaperSize.a4,
  }) {
    final tables = PortalSummaryDotReport.previewTables(
      dataset,
      form: form,
      matrixFares: dataset.kind == ReportKind.matrixFares,
    );
    final wide = tables.any((t) => t.headers.length >= 6);
    return buildDotReportPdfBytes(
      form: form,
      preview: tables.first,
      additionalTables:
          tables.length > 1 ? tables.sublist(1) : const [],
      scopeLabel: scopeLabel,
      startDate: startDate,
      endDate: endDate,
      paperSize: paperSize,
      landscape: wide,
      paginateTables: true,
    );
  }

  static Uint8List buildXlsx({
    required DotFormCatalogEntry form,
    required ReportDataset dataset,
    required String scopeLabel,
  }) {
    final tables = dataset.tables;
    final book = Excel.createExcel();
    final defaultSheet = book.getDefaultSheet();
    final usedNames = <String>{};

    final coverName = _uniqueSheetName(form.code, usedNames);
    final cover = book[coverName];
    final coverRow = _writeCover(
      sheet: cover,
      form: form,
      dataset: dataset,
      scopeLabel: scopeLabel,
    );
    if (form.id == PortalSummaryDotReport.evt1Id) {
      ReportTable? events;
      for (final table in tables) {
        if (table.title == 'Tourism event records') {
          events = table;
          break;
        }
      }
      if (events != null) {
        _writeTableGrid(
          sheet: cover,
          table: events,
          startRow: coverRow + 2,
          mergeEmpty: false,
          sectionTitle: 'TOURISM EVENT RECORDS',
          applyColumnWidths: false,
        );
        _applyEvt1CoverColumnWidths(cover);
      }
    }
    _applyPrint(cover, form, dataset);

    for (final table in tables) {
      final name = _uniqueSheetName(table.title, usedNames);
      final sheet = book[name];
      _writeDataSheet(
        sheet: sheet,
        form: form,
        dataset: dataset,
        scopeLabel: scopeLabel,
        table: table,
      );
      _applyPrint(sheet, form, dataset);
    }

    if (defaultSheet != null &&
        !usedNames.contains(defaultSheet.toLowerCase())) {
      try {
        book.delete(defaultSheet);
      } catch (_) {}
    }

    final encoded = book.encode();
    if (encoded == null || encoded.isEmpty) {
      throw StateError('Unable to encode ${form.code} workbook.');
    }
    final bytes = Uint8List.fromList(encoded);
    if (form.id == PortalSummaryDotReport.evt1Id) {
      return _repairEvt1Workbook(bytes);
    }
    return bytes;
  }

  static int _writeCover({
    required Sheet sheet,
    required DotFormCatalogEntry form,
    required ReportDataset dataset,
    required String scopeLabel,
  }) {
    final lastCol = form.id == PortalSummaryDotReport.evt1Id ? 6 : 5;
    var row = 0;
    _mergeRow(sheet, row, lastCol, _brand, _brandStyle);
    sheet.setRowHeight(row, 18);
    row++;
    _mergeRow(sheet, row, lastCol, form.displayLabel, _titleStyle);
    sheet.setRowHeight(row, 26);
    row++;
    if (form.subtitle.trim().isNotEmpty) {
      _mergeRow(sheet, row, lastCol, form.subtitle, _subtitleStyle);
      row++;
    }
    _mergeRow(sheet, row, lastCol, '', _barStyle);
    sheet.setRowHeight(row, 6);
    row += 2;

    final meta = <(String, String)>[
      ('Template', form.code),
      ('Reporting unit', scopeLabel.trim().isEmpty ? '—' : scopeLabel),
      ('Reporting period', dataset.periodLabel),
      ('Generated', formatReportDateTime(dataset.generatedAt)),
      for (final f in dataset.filterSummary)
        if (f.$1 != 'Template' && f.$1 != 'Form type') f,
    ];
    _put(sheet, row, 0, 'REPORT INFORMATION', _sectionStyle);
    _merge(sheet, row, 0, lastCol);
    row += 2;
    _put(sheet, row, 0, 'Field', _tableHeaderStyle);
    _put(sheet, row, 1, 'Value', _tableHeaderStyle);
    sheet.setRowHeight(row, 20);
    row++;
    for (var i = 0; i < meta.length; i++) {
      _put(sheet, row, 0, meta[i].$1, _labelStyle);
      _put(sheet, row, 1, meta[i].$2, _bodyStyle);
      if (i.isOdd) _fillRow(sheet, row, 1, _zebraHex);
      row++;
    }

    final warning = dataset.warning;
    if (warning != null && warning.trim().isNotEmpty) {
      row++;
      _put(sheet, row, 0, 'Note', _labelStyle);
      _put(sheet, row, 1, warning, _bodyStyle);
      row++;
    }

    row += 2;
    _put(sheet, row, 0, 'SUMMARY STATISTICS', _sectionStyle);
    _merge(sheet, row, 0, lastCol);
    row += 2;
    _put(sheet, row, 0, 'Metric', _tableHeaderStyle);
    _put(sheet, row, 1, 'Value', _tableHeaderStyle);
    _put(sheet, row, 2, 'Detail', _tableHeaderStyle);
    sheet.setRowHeight(row, 20);
    row++;
    final metrics = dataset.metrics;
    if (metrics.isEmpty) {
      _put(sheet, row, 0, 'No summary metrics for this template.', _mutedStyle);
    } else {
      for (var i = 0; i < metrics.length; i++) {
        final m = metrics[i];
        _put(sheet, row, 0, m.label, _bodyStyle);
        _put(sheet, row, 1, m.value, _bodyBoldStyle);
        _put(sheet, row, 2, m.caption ?? '', _mutedStyle);
        if (i.isOdd) _fillRow(sheet, row, 2, _zebraHex);
        sheet.setRowHeight(row, 18);
        row++;
      }
    }

    if (form.id != PortalSummaryDotReport.evt1Id) {
      sheet.setColumnWidth(0, 28);
      sheet.setColumnWidth(1, 44);
      sheet.setColumnWidth(2, 40);
      for (var c = 3; c <= lastCol; c++) {
        sheet.setColumnWidth(c, 16);
      }
    }
    return row;
  }

  static void _writeDataSheet({
    required Sheet sheet,
    required DotFormCatalogEntry form,
    required ReportDataset dataset,
    required String scopeLabel,
    required ReportTable table,
  }) {
    final colCount = table.columns.isEmpty ? 1 : table.columns.length;
    final lastCol = colCount - 1;
    final evt1Records = form.id == PortalSummaryDotReport.evt1Id &&
        table.title == 'Tourism event records';
    var row = 0;
    if (evt1Records) {
      // Merged A1:G banners leave <dimension ref="A1"/>, which Microsoft Excel
      // treats as an empty used range and can hide the event table on open.
      _put(sheet, row, 0, table.title.toUpperCase(), _sectionStyle);
      sheet.setRowHeight(row, 18);
      row++;
      _put(
        sheet,
        row,
        0,
        '$scopeLabel  ·  ${dataset.periodLabel}',
        _mutedStyle,
      );
      row += 2;
      _writeTableGrid(
        sheet: sheet,
        table: table,
        startRow: row,
        mergeEmpty: false,
      );
      return;
    }

    _mergeRow(sheet, row, lastCol, _brand, _brandStyle);
    sheet.setRowHeight(row, 18);
    row++;
    _mergeRow(sheet, row, lastCol, form.displayLabel, _titleStyle);
    sheet.setRowHeight(row, 24);
    row++;
    _mergeRow(
      sheet,
      row,
      lastCol,
      '${table.title}  ·  $scopeLabel  ·  ${dataset.periodLabel}',
      _subtitleStyle,
    );
    row++;
    _mergeRow(sheet, row, lastCol, '', _barStyle);
    sheet.setRowHeight(row, 6);
    row += 2;

    _put(sheet, row, 0, table.title.toUpperCase(), _sectionStyle);
    _merge(sheet, row, 0, lastCol);
    row += 2;

    _writeTableGrid(
      sheet: sheet,
      table: table,
      startRow: row,
      mergeEmpty: true,
    );
  }

  static int _writeTableGrid({
    required Sheet sheet,
    required ReportTable table,
    required int startRow,
    required bool mergeEmpty,
    String? sectionTitle,
    bool applyColumnWidths = true,
  }) {
    final colCount = table.columns.isEmpty ? 1 : table.columns.length;
    final lastCol = colCount - 1;
    var row = startRow;
    if (sectionTitle != null && sectionTitle.isNotEmpty) {
      _put(sheet, row, 0, sectionTitle, _sectionStyle);
      sheet.setRowHeight(row, 18);
      row += 2;
    }

    for (var c = 0; c < colCount; c++) {
      _put(sheet, row, c, table.columns[c], _tableHeaderStyle);
    }
    sheet.setRowHeight(row, 22);
    final headerRow = row;
    row++;

    if (table.isEmpty) {
      if (mergeEmpty) {
        _mergeRow(
          sheet,
          row,
          lastCol,
          'No records matched the selected filters.',
          _mutedStyle,
        );
      } else {
        _put(
          sheet,
          row,
          0,
          'No records matched the selected filters.',
          _mutedStyle,
        );
      }
      row++;
    } else {
      for (var i = 0; i < table.rows.length; i++) {
        final data = table.rows[i];
        final zebra = i.isOdd;
        var tallest = 18.0;
        for (var c = 0; c < colCount; c++) {
          final raw = c < data.length ? data[c] : '';
          final numeric = table.numericColumns.contains(c);
          final style = _dataStyle(
            right: numeric || _looksNumeric(table.columns[c], raw),
            zebra: zebra,
            bold: false,
          );
          if (numeric) {
            _putValue(sheet, row, c, _numericValue(raw), style);
          } else {
            _put(sheet, row, c, raw, style);
          }
          final lines = (raw.length / 42).ceil().clamp(1, 6);
          final h = 16.0 + (lines - 1) * 12;
          if (h > tallest) tallest = h;
        }
        sheet.setRowHeight(row, tallest);
        row++;
      }
      final footer = PortalSummaryDotReport.footerFor(table);
      if (footer != null) {
        for (var c = 0; c < colCount; c++) {
          final raw = c < footer.length ? footer[c] : '';
          final numeric = table.numericColumns.contains(c);
          final style = _dataStyle(
            right: numeric || c > 0 && raw.isNotEmpty,
            zebra: false,
            bold: true,
            fillHex: _accentSoftHex,
          );
          if (numeric && raw.isNotEmpty && raw != 'Total') {
            _putValue(sheet, row, c, _numericValue(raw), style);
          } else {
            _put(sheet, row, c, raw, style);
          }
        }
        sheet.setRowHeight(row, 20);
        row++;
      }
    }

    if (applyColumnWidths) {
      final sample = [
        for (var c = 0; c < colCount; c++)
          [
            table.columns[c],
            ...table.rows.take(80).map((r) => c < r.length ? r[c] : ''),
          ],
      ];
      for (var c = 0; c < colCount; c++) {
        var width = _columnWidth(sample[c]);
        final header = table.columns[c].toLowerCase();
        if (header.contains('destination') && width < 36) width = 36;
        if ((header.contains('announcement') || header.contains('details')) &&
            width < 36) {
          width = 36;
        }
        if ((header == 'event' ||
                header.contains('starting') ||
                header.contains('municipality') ||
                header.contains('venue')) &&
            width < 28) {
          width = 28;
        }
        if ((header.contains('estimated') ||
                header.contains('travel time') ||
                header.contains('date')) &&
            width < 18) {
          width = 18;
        }
        sheet.setColumnWidth(c, width);
      }
    }
    sheet.setRowHeight(headerRow, 22);
    return row;
  }

  static void _applyEvt1CoverColumnWidths(Sheet sheet) {
    sheet.setColumnWidth(0, 28);
    sheet.setColumnWidth(1, 52);
    sheet.setColumnWidth(2, 24);
    sheet.setColumnWidth(3, 30);
    sheet.setColumnWidth(4, 22);
    sheet.setColumnWidth(5, 14);
    sheet.setColumnWidth(6, 20);
  }

  static void _applyPrint(
    Sheet sheet,
    DotFormCatalogEntry form,
    ReportDataset dataset,
  ) {
    // The excel package XML-escapes header/footer text, so Excel `&L` / `&P`
    // codes would double-encode. Print the title in plain text instead; the
    // in-sheet header already carries the full DOT report identity.
    var header = form.displayLabel.replaceAll('&', 'and');
    var footer =
        '${_brand.replaceAll('&', 'and')}  ·  ${dataset.periodLabel.replaceAll('&', 'and')}';
    if (form.id == PortalSummaryDotReport.evt1Id) {
      header = header.replaceAll('—', '-');
      footer = footer.replaceAll('—', '-').replaceAll('–', '-');
    }
    sheet.headerFooter = HeaderFooter(
      oddHeader: header,
      oddFooter: footer,
    );
  }

  static double _columnWidth(List<String> values) {
    var maxLen = 0;
    for (final v in values) {
      if (v.length > maxLen) maxLen = v.length;
    }
    if (maxLen > 55) return 46;
    if (maxLen > 36) return 38;
    return (maxLen * 1.15 + 3).clamp(14.0, 34.0);
  }

  static bool _looksNumeric(String header, String value) {
    final h = header.toLowerCase();
    if (h.contains('fare') ||
        h.contains('lowest') ||
        h.contains('highest') ||
        h.contains('average') ||
        h.contains('routes') ||
        h.contains('check-in') ||
        h == 'events') {
      return true;
    }
    final t = value.trim();
    return t.startsWith('PHP ') || _intLike.hasMatch(t);
  }

  static final _intLike = RegExp(r'^[-+]?\d[\d,]*$');

  static CellValue _numericValue(String raw) {
    final cleaned = raw.replaceAll(',', '').trim();
    final asInt = int.tryParse(cleaned);
    if (asInt != null) return IntCellValue(asInt);
    final asDouble = double.tryParse(cleaned);
    if (asDouble != null) return DoubleCellValue(asDouble);
    return TextCellValue(raw);
  }

  static String _uniqueSheetName(String title, Set<String> used) {
    var base = title.replaceAll(RegExp(r'[\[\]:\*\?\/\\]'), ' ').trim();
    if (base.isEmpty) base = 'Sheet';
    if (base.length > 31) base = base.substring(0, 31).trim();
    var candidate = base;
    var n = 2;
    while (used.contains(candidate.toLowerCase())) {
      final suffix = ' $n';
      final room = 31 - suffix.length;
      candidate =
          '${base.length > room ? base.substring(0, room) : base}$suffix';
      n++;
    }
    used.add(candidate.toLowerCase());
    return candidate;
  }

  static void _mergeRow(
    Sheet sheet,
    int row,
    int lastCol,
    String text,
    CellStyle style,
  ) {
    _put(sheet, row, 0, text, style);
    if (lastCol > 0) {
      _merge(sheet, row, 0, lastCol);
      sheet.setMergedCellStyle(
        CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: row),
        style,
      );
    }
  }

  static void _merge(Sheet sheet, int row, int from, int to) {
    if (to <= from) return;
    sheet.merge(
      CellIndex.indexByColumnRow(columnIndex: from, rowIndex: row),
      CellIndex.indexByColumnRow(columnIndex: to, rowIndex: row),
    );
  }

  static void _put(Sheet sheet, int row, int col, String text, CellStyle style) {
    _putValue(sheet, row, col, TextCellValue(text), style);
  }

  static void _putValue(
    Sheet sheet,
    int row,
    int col,
    CellValue value,
    CellStyle style,
  ) {
    final cell = sheet.cell(
      CellIndex.indexByColumnRow(columnIndex: col, rowIndex: row),
    );
    cell.value = value;
    cell.cellStyle = style;
  }

  static void _fillRow(Sheet sheet, int row, int lastCol, String hex) {
    for (var c = 0; c <= lastCol; c++) {
      final cell = sheet.cell(
        CellIndex.indexByColumnRow(columnIndex: c, rowIndex: row),
      );
      final current = cell.cellStyle ?? _bodyStyle;
      cell.cellStyle = current.copyWith(
        backgroundColorHexVal: ExcelColor.fromHexString(hex),
      );
    }
  }

  static CellStyle get _brandStyle => CellStyle(
        fontSize: 9,
        bold: true,
        fontColorHex: ExcelColor.fromHexString(_accentHex),
        backgroundColorHex: ExcelColor.fromHexString(_accentSoftHex),
        verticalAlign: VerticalAlign.Center,
        textWrapping: TextWrapping.WrapText,
      );

  static CellStyle get _titleStyle => CellStyle(
        fontSize: 16,
        bold: true,
        fontColorHex: ExcelColor.fromHexString(_inkHex),
        backgroundColorHex: ExcelColor.fromHexString(_accentSoftHex),
        verticalAlign: VerticalAlign.Center,
        textWrapping: TextWrapping.WrapText,
      );

  static CellStyle get _subtitleStyle => CellStyle(
        fontSize: 10,
        fontColorHex: ExcelColor.fromHexString(_mutedHex),
        backgroundColorHex: ExcelColor.fromHexString(_accentSoftHex),
        verticalAlign: VerticalAlign.Center,
        textWrapping: TextWrapping.WrapText,
      );

  static CellStyle get _barStyle => CellStyle(
        backgroundColorHex: ExcelColor.fromHexString(_accentHex),
      );

  static CellStyle get _sectionStyle => CellStyle(
        fontSize: 10,
        bold: true,
        fontColorHex: ExcelColor.fromHexString(_mutedHex),
        verticalAlign: VerticalAlign.Center,
      );

  static CellStyle get _labelStyle => CellStyle(
        fontSize: 10,
        bold: true,
        fontColorHex: ExcelColor.fromHexString(_inkHex),
        verticalAlign: VerticalAlign.Center,
        leftBorder: _thin,
        rightBorder: _thin,
        topBorder: _thin,
        bottomBorder: _thin,
        textWrapping: TextWrapping.WrapText,
      );

  static CellStyle get _bodyStyle => _dataStyle(right: false, zebra: false);

  static CellStyle get _bodyBoldStyle =>
      _dataStyle(right: false, zebra: false, bold: true);

  static CellStyle get _mutedStyle => CellStyle(
        fontSize: 10,
        fontColorHex: ExcelColor.fromHexString(_mutedHex),
        verticalAlign: VerticalAlign.Center,
        textWrapping: TextWrapping.WrapText,
        leftBorder: _thin,
        rightBorder: _thin,
        topBorder: _thin,
        bottomBorder: _thin,
      );

  static CellStyle get _tableHeaderStyle => CellStyle(
        fontSize: 10,
        bold: true,
        fontColorHex: ExcelColor.fromHexString(_whiteHex),
        backgroundColorHex: ExcelColor.fromHexString(_accentHex),
        horizontalAlign: HorizontalAlign.Center,
        verticalAlign: VerticalAlign.Center,
        textWrapping: TextWrapping.WrapText,
        leftBorder: _thin,
        rightBorder: _thin,
        topBorder: _thin,
        bottomBorder: _thin,
      );

  static CellStyle _dataStyle({
    required bool right,
    required bool zebra,
    bool bold = false,
    String? fillHex,
  }) {
    return CellStyle(
      fontSize: 10,
      bold: bold,
      fontColorHex: ExcelColor.fromHexString(_inkHex),
      backgroundColorHex: ExcelColor.fromHexString(
        fillHex ?? (zebra ? _zebraHex : _whiteHex),
      ),
      horizontalAlign: right ? HorizontalAlign.Right : HorizontalAlign.Left,
      verticalAlign: VerticalAlign.Center,
      textWrapping: TextWrapping.WrapText,
      leftBorder: _thin,
      rightBorder: _thin,
      topBorder: _thin,
      bottomBorder: _thin,
    );
  }

  static Border get _thin => Border(
        borderStyle: BorderStyle.Thin,
        borderColorHex: ExcelColor.fromHexString(_borderHex),
      );

  /// The excel package leaves `<dimension ref="A1"/>` and an empty drawing on
  /// Sheet1. Microsoft Excel then treats the used range as A1 and can hide the
  /// Tourism event records table even though the cells exist in sheet XML.
  static Uint8List _repairEvt1Workbook(Uint8List bytes) {
    final archive = ZipDecoder().decodeBytes(bytes);
    final skip = <String>{};
    for (final file in archive) {
      if (!file.isFile) continue;
      final name = file.name.replaceAll('\\', '/');
      if (!name.contains('drawings/drawing') || !name.endsWith('.xml')) {
        continue;
      }
      final xml = utf8.decode(file.content as List<int>);
      if (!xml.contains('twoCellAnchor') &&
          !xml.contains('oneCellAnchor') &&
          !xml.contains('absoluteAnchor')) {
        skip.add(name);
      }
    }

    final out = Archive();
    for (final file in archive) {
      if (!file.isFile) continue;
      final name = file.name.replaceAll('\\', '/');
      if (skip.contains(name)) continue;

      var body = file.content as List<int>;
      if (name.startsWith('xl/worksheets/sheet') &&
          name.endsWith('.xml') &&
          !name.contains('_rels')) {
        body = utf8.encode(_fixWorksheetDimension(utf8.decode(body)));
      } else if (name.startsWith('xl/worksheets/_rels/') &&
          name.endsWith('.rels')) {
        var xml = utf8.decode(body);
        xml = xml.replaceAll(
          RegExp(r'<Relationship[^>]*drawings/drawing[^>]*/>'),
          '',
        );
        if (!RegExp(r'<Relationship\b').hasMatch(xml)) continue;
        body = utf8.encode(xml);
      } else if (name == '[Content_Types].xml' && skip.isNotEmpty) {
        var xml = utf8.decode(body);
        for (final drawing in skip) {
          final part = drawing.startsWith('/') ? drawing : '/$drawing';
          xml = xml.replaceAll(
            RegExp(
              '<Override[^>]*PartName="${RegExp.escape(part)}"[^>]*/>',
            ),
            '',
          );
        }
        body = utf8.encode(xml);
      }

      out.addFile(ArchiveFile(name, body.length, body));
    }

    final encoded = ZipEncoder().encode(out);
    if (encoded == null || encoded.isEmpty) return bytes;
    return Uint8List.fromList(encoded);
  }

  static String _fixWorksheetDimension(String xml) {
    var minCol = 1 << 20;
    var minRow = 1 << 20;
    var maxCol = 0;
    var maxRow = 0;

    void consider(String ref) {
      final parsed = _parseA1(ref);
      if (parsed == null) return;
      if (parsed.$1 < minCol) minCol = parsed.$1;
      if (parsed.$1 > maxCol) maxCol = parsed.$1;
      if (parsed.$2 < minRow) minRow = parsed.$2;
      if (parsed.$2 > maxRow) maxRow = parsed.$2;
    }

    for (final match in RegExp(r'\br="([A-Z]+[0-9]+)"').allMatches(xml)) {
      consider(match.group(1)!);
    }
    for (final match
        in RegExp(r'\bref="([A-Z]+[0-9]+):([A-Z]+[0-9]+)"').allMatches(xml)) {
      consider(match.group(1)!);
      consider(match.group(2)!);
    }
    if (maxCol == 0 || maxRow == 0) return xml;

    final dimension =
        '${_toA1(minCol, minRow)}:${_toA1(maxCol, maxRow)}';
    if (xml.contains('<dimension ')) {
      return xml.replaceFirst(
        RegExp(r'<dimension ref="[^"]*"\s*/>'),
        '<dimension ref="$dimension"/>',
      );
    }
    return xml.replaceFirst(
      '<sheetData>',
      '<dimension ref="$dimension"/><sheetData>',
    );
  }

  static (int, int)? _parseA1(String ref) {
    final match = RegExp(r'^([A-Z]+)([0-9]+)$').firstMatch(ref);
    if (match == null) return null;
    var col = 0;
    for (final unit in match.group(1)!.codeUnits) {
      col = col * 26 + (unit - 64);
    }
    return (col, int.parse(match.group(2)!));
  }

  static String _toA1(int col, int row) {
    final letters = StringBuffer();
    var n = col;
    while (n > 0) {
      final rem = (n - 1) % 26;
      letters.writeCharCode(65 + rem);
      n = (n - 1) ~/ 26;
    }
    return '${letters.toString().split('').reversed.join()}$row';
  }
}

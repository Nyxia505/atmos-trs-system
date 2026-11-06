import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:excel/excel.dart';

import 'package:atmos_trs_system/config/supabase_report_templates_config.dart';
import 'package:atmos_trs_system/utils/dot_report_preview.dart';

/// Professional orange-and-white ATMOS XLSX for AE DAE-1A / DAE-1B exports.
///
/// Formatting / print layout only — values come from [DotReportPreviewTable].
class DaeAeStyledXlsx {
  DaeAeStyledXlsx._();

  static const reportSheetName = 'Report';
  static const gapsSheetName = 'ATMOS_GAPS';
  static const dataSheetName = 'ATMOS_DATA';

  static const _ink = 'FF0F172A';
  static const _muted = 'FF64748B';
  static const _white = 'FFFFFFFF';
  static const _orange = 'FFEA580C';
  static const _orangeSoft = 'FFFFF7ED';
  static const _orangeBand = 'FFFFF1E7';
  static const _orangeTotal = 'FFFFEDD5';
  static const _border = 'FFE2E8F0';
  static const _accentLine = 'FFFDBA74';

  static List<int> build({
    required DotFormCatalogEntry form,
    required DotReportPreviewTable preview,
    required String scopeLabel,
    required DateTime startDate,
    required DateTime endDate,
  }) {
    final excel = Excel.createExcel();
    final defaultName = excel.getDefaultSheet() ?? 'Sheet1';
    if (defaultName != reportSheetName) {
      excel.rename(defaultName, reportSheetName);
    }
    excel[reportSheetName];
    excel[gapsSheetName];
    excel[dataSheetName];
    for (final name in excel.sheets.keys.toList()) {
      if (name != reportSheetName &&
          name != gapsSheetName &&
          name != dataSheetName) {
        excel.delete(name);
      }
    }

    final isManual = form.id == 'dae1a_manual';
    final lastCol = preview.headers.isEmpty ? 0 : preview.headers.length - 1;
    final headerRow = _writeReportSheet(
      excel[reportSheetName],
      form: form,
      preview: preview,
      scopeLabel: scopeLabel,
      startDate: startDate,
      endDate: endDate,
      isManual: isManual,
      lastCol: lastCol,
    );
    _writeGaps(excel[gapsSheetName], preview.gaps);
    _writeAuditData(
      excel[dataSheetName],
      form: form,
      preview: preview,
      scopeLabel: scopeLabel,
      startDate: startDate,
      endDate: endDate,
    );
    excel.setDefaultSheet(reportSheetName);

    final encoded = excel.encode();
    if (encoded == null || encoded.isEmpty) return const <int>[];

    final lastDataRow = headerRow +
        preview.rows.length +
        (preview.footer != null ? 1 : 0);
    return _attachPrintLayout(
      Uint8List.fromList(encoded),
      sheetName: reportSheetName,
      lastCol: lastCol,
      lastRow: lastDataRow.clamp(headerRow, 1 << 20),
      headerRow: headerRow,
      landscape: isManual && preview.headers.length >= 7,
    );
  }

  static int _writeReportSheet(
    Sheet sheet, {
    required DotFormCatalogEntry form,
    required DotReportPreviewTable preview,
    required String scopeLabel,
    required DateTime startDate,
    required DateTime endDate,
    required bool isManual,
    required int lastCol,
  }) {
    sheet.setDefaultRowHeight(18);

    // —— Header band ——
    _mergeWrite(
      sheet,
      row: 0,
      lastCol: lastCol,
      text: 'ATMOS TRS | DOT REPORT',
      style: _style(
        bold: true,
        size: 11,
        color: _white,
        fill: _orange,
        align: HorizontalAlign.Center,
      ),
      height: 22,
    );
    _mergeWrite(
      sheet,
      row: 1,
      lastCol: lastCol,
      text: _reportTitle(form),
      style: _style(
        bold: true,
        size: 16,
        color: _ink,
        fill: _white,
        align: HorizontalAlign.Center,
      ),
      height: 26,
    );
    // Orange accent rule under the title.
    for (var c = 0; c <= lastCol; c++) {
      final cell = sheet.cell(
        CellIndex.indexByColumnRow(columnIndex: c, rowIndex: 2),
      );
      cell.value = TextCellValue('');
      cell.cellStyle = _style(
        fill: _accentLine,
        bottomBorderColor: _orange,
        bottomBorderStyle: BorderStyle.Medium,
      );
    }
    sheet.setRowHeight(2, 4);

    final meta = _metaBlock(
      form: form,
      preview: preview,
      scopeLabel: scopeLabel,
      startDate: startDate,
      endDate: endDate,
      isManual: isManual,
    );

    var row = 4;
    for (final line in meta.infoLines) {
      _setText(sheet, row, 0, line.$1, style: _style(bold: true, color: _muted, size: 9));
      if (lastCol >= 1) {
        sheet.merge(
          CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: row),
          CellIndex.indexByColumnRow(columnIndex: lastCol, rowIndex: row),
        );
        _setText(
          sheet,
          row,
          1,
          line.$2,
          style: _style(bold: true, color: _ink, size: 10),
        );
      }
      sheet.setRowHeight(row, 18);
      row++;
    }

    row++;
    // Compact summary chips across the table width.
    final summaryBits = meta.summaryBits;
    if (summaryBits.isNotEmpty) {
      _mergeWrite(
        sheet,
        row: row,
        lastCol: lastCol,
        text: summaryBits.join('   ·   '),
        style: _style(
          bold: true,
          size: 9,
          color: _ink,
          fill: _orangeSoft,
          align: HorizontalAlign.Center,
        ),
        height: 20,
      );
      row++;
    }

    row++;
    final headerRow = row;

    // —— Table header ——
    for (var c = 0; c < preview.headers.length; c++) {
      _setText(
        sheet,
        headerRow,
        c,
        preview.headers[c],
        style: _style(
          bold: true,
          size: 10,
          color: _white,
          fill: _orange,
          align: HorizontalAlign.Center,
          border: true,
        ),
      );
    }
    sheet.setRowHeight(headerRow, 22);

    // —— Body ——
    for (var i = 0; i < preview.rows.length; i++) {
      final excelRow = headerRow + 1 + i;
      sheet.setRowHeight(excelRow, 18);
      final band = i.isOdd ? _orangeBand : _white;
      final cells = preview.rows[i];
      final emphasize = isManual
          ? false
          : _isDae1bEmphasized(cells.isNotEmpty ? cells.first : '');
      for (var c = 0; c < preview.headers.length; c++) {
        final raw = c < cells.length ? cells[c] : '';
        _writeTypedCell(
          sheet,
          excelRow,
          c,
          raw,
          header: preview.headers[c],
          isManual: isManual,
          band: band,
          emphasize: emphasize,
        );
      }
    }

    // —— TOTAL ——
    if (preview.footer != null) {
      final footerRow = headerRow + 1 + preview.rows.length;
      sheet.setRowHeight(footerRow, 20);
      for (var c = 0; c < preview.headers.length; c++) {
        final raw = c < preview.footer!.length ? preview.footer![c] : '';
        _writeTypedCell(
          sheet,
          footerRow,
          c,
          raw,
          header: preview.headers[c],
          isManual: isManual,
          band: _orangeTotal,
          emphasize: true,
          total: true,
        );
      }
    }

    _applyColumnWidths(sheet, preview.headers, isManual: isManual);
    return headerRow;
  }

  static void _writeTypedCell(
    Sheet sheet,
    int row,
    int col,
    String raw, {
    required String header,
    required bool isManual,
    required String band,
    bool emphasize = false,
    bool total = false,
  }) {
    final h = header.toLowerCase();
    final align = _alignFor(header, isManual: isManual);
    final edge = Border(
      borderStyle: total ? BorderStyle.Medium : BorderStyle.Thin,
      borderColorHex: ExcelColor.fromHexString(total ? _orange : _border),
    );
    final topEdge = total
        ? Border(
            borderStyle: BorderStyle.Medium,
            borderColorHex: ExcelColor.fromHexString(_orange),
          )
        : edge;

    CellStyle base({NumFormat? numberFormat}) => CellStyle(
          bold: emphasize || total,
          fontSize: 10,
          fontColorHex: ExcelColor.fromHexString(_ink),
          backgroundColorHex: ExcelColor.fromHexString(band),
          horizontalAlign: align,
          verticalAlign: VerticalAlign.Center,
          textWrapping: (!isManual && h.contains('description'))
              ? TextWrapping.WrapText
              : TextWrapping.Clip,
          leftBorder: edge,
          rightBorder: edge,
          topBorder: topEdge,
          bottomBorder: edge,
          numberFormat: numberFormat ?? NumFormat.standard_0,
        );

    final trimmed = raw.trim();
    if (trimmed.isEmpty || trimmed == '—' || trimmed == '-') {
      _setText(sheet, row, col, trimmed.isEmpty ? '' : trimmed, style: base());
      return;
    }

    // Occupancy / rate strings like "62.5%".
    if (h.contains('occupancy') ||
        (trimmed.endsWith('%') && _looksPercent(trimmed))) {
      final pct = _parsePercent(trimmed);
      if (pct != null) {
        final cell = sheet.cell(
          CellIndex.indexByColumnRow(columnIndex: col, rowIndex: row),
        );
        cell.value = DoubleCellValue(pct);
        cell.cellStyle = base(numberFormat: NumFormat.standard_10);
        return;
      }
    }

    // Whole-number count columns.
    if (_isCountHeader(header) || (!isManual && h == 'value' && _isIntString(trimmed))) {
      final n = int.tryParse(trimmed.replaceAll(',', ''));
      if (n != null) {
        final cell = sheet.cell(
          CellIndex.indexByColumnRow(columnIndex: col, rowIndex: row),
        );
        cell.value = IntCellValue(n);
        cell.cellStyle = base(numberFormat: NumFormat.standard_1);
        return;
      }
    }

    // Decimals (ALOS / persons per room).
    if (!isManual && h == 'value') {
      final d = double.tryParse(trimmed.replaceAll(',', ''));
      if (d != null && trimmed.contains('.')) {
        final cell = sheet.cell(
          CellIndex.indexByColumnRow(columnIndex: col, rowIndex: row),
        );
        cell.value = DoubleCellValue(d);
        cell.cellStyle = base(numberFormat: NumFormat.standard_2);
        return;
      }
    }

    _setText(sheet, row, col, trimmed, style: base());
  }

  static HorizontalAlign _alignFor(String header, {required bool isManual}) {
    final h = header.toLowerCase();
    if (!isManual) {
      if (h == 'item') return HorizontalAlign.Center;
      if (h == 'value') return HorizontalAlign.Center;
      return HorizontalAlign.Left;
    }
    if (h == 'ae') return HorizontalAlign.Left;
    return HorizontalAlign.Center;
  }

  static bool _isCountHeader(String header) {
    final h = header.toLowerCase();
    return h.contains('check-in') ||
        h.contains('check-out') ||
        h.contains('guest night') ||
        h.contains('rooms occupied') ||
        h == 'rooms' ||
        h.contains('arrival');
  }

  static bool _isIntString(String s) =>
      RegExp(r'^-?\d+$').hasMatch(s.replaceAll(',', ''));

  static bool _looksPercent(String s) =>
      RegExp(r'^-?\d+(\.\d+)?\s*%$').hasMatch(s.trim());

  /// Converts display "62.50%" → Excel fraction 0.625 (for 0.00% format).
  static double? _parsePercent(String s) {
    final m = RegExp(r'^(-?\d+(?:\.\d+)?)\s*%$').firstMatch(s.trim());
    if (m == null) return null;
    final n = double.tryParse(m.group(1)!);
    if (n == null) return null;
    return n / 100.0;
  }

  static bool _isDae1bEmphasized(String itemCell) {
    // KPI / totals: items 4–8 and 17–18.
    final m = RegExp(r'\((\d+)\)').firstMatch(itemCell);
    if (m == null) return false;
    final n = int.tryParse(m.group(1)!) ?? -1;
    return n == 4 ||
        n == 5 ||
        n == 6 ||
        n == 7 ||
        n == 8 ||
        n == 17 ||
        n == 18;
  }

  static String _reportTitle(DotFormCatalogEntry form) {
    if (form.id == 'dae1a_manual') return 'DAE-1A — MANUAL TALLY';
    if (form.id == 'dae1b_macro') return 'DOT ET DAE-1B — MACRO REGISTER';
    return form.title.toUpperCase();
  }

  static ({List<(String, String)> infoLines, List<String> summaryBits}) _metaBlock({
    required DotFormCatalogEntry form,
    required DotReportPreviewTable preview,
    required String scopeLabel,
    required DateTime startDate,
    required DateTime endDate,
    required bool isManual,
  }) {
    final period = _periodLabel(startDate, endDate);
    if (isManual) {
      final aeNames = <String>{};
      for (final r in preview.rows) {
        if (r.isNotEmpty && r.first.trim().isNotEmpty) aeNames.add(r.first.trim());
      }
      final establishment = aeNames.length == 1
          ? aeNames.first
          : (aeNames.isEmpty ? scopeLabel : '${aeNames.length} establishments');
      final filled = preview.rows.length;
      var checkIns = 0;
      var guestNights = 0;
      var rooms = 0;
      if (preview.footer != null && preview.footer!.length >= 6) {
        checkIns = int.tryParse(preview.footer![2]) ?? 0;
        guestNights = int.tryParse(preview.footer![4]) ?? 0;
        rooms = int.tryParse(preview.footer![5]) ?? 0;
      }
      return (
        infoLines: [
          ('Establishment', establishment.isEmpty ? '—' : establishment),
          ('Municipality / City', scopeLabel.isEmpty ? '—' : scopeLabel),
          ('Reporting Period', period),
        ],
        summaryBits: [
          'Filled Days: $filled',
          'Total Check-ins: $checkIns',
          'Total Guest Nights: $guestNights',
          'Total Room Nights: $rooms',
        ],
      );
    }

    // DAE-1B macro: pull AE name + rooms from Item rows when present.
    String establishment = scopeLabel;
    String rooms = '—';
    String month = period;
    for (final r in preview.rows) {
      if (r.length < 3) continue;
      final item = r[0];
      final value = r[2];
      if (item.contains('(1)') && value.trim().isNotEmpty && value != '—') {
        establishment = value.trim();
      }
      if (item.contains('(4)') && value.trim().isNotEmpty) {
        rooms = value.trim();
      }
    }
    final ym = RegExp(r'(\d{4}-\d{2})').firstMatch(preview.summaryLine);
    if (ym != null) month = ym.group(1)!;

    return (
      infoLines: [
        ('Establishment', establishment.isEmpty ? '—' : establishment),
        ('Municipality / City', scopeLabel.isEmpty ? '—' : scopeLabel),
        ('Reporting Period', month),
      ],
      summaryBits: [
        'Establishment: $establishment',
        'Reporting Month: $month',
        'Total Available Rooms: $rooms',
      ],
    );
  }

  static String _periodLabel(DateTime start, DateTime end) {
    String fmt(DateTime d) =>
        '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
    if (start.year == end.year && start.month == end.month && start.day == end.day) {
      return fmt(start);
    }
    return '${fmt(start)} → ${fmt(end)}';
  }

  static void _applyColumnWidths(
    Sheet sheet,
    List<String> headers, {
    required bool isManual,
  }) {
    if (isManual) {
      // ~A4 landscape content width across 7 columns.
      // Col F ("Rooms occupied") needs extra width so the orange header
      // is not clipped beside Occupancy.
      const widths = <String, double>{
        'ae': 26,
        'date': 12,
        'check-ins': 11,
        'check-outs': 11,
        'guest nights': 13,
        'rooms occupied': 18,
        'occupancy': 12,
      };
      for (var c = 0; c < headers.length; c++) {
        final key = headers[c].toLowerCase();
        sheet.setColumnWidth(c, widths[key] ?? 12);
      }
      return;
    }
    for (var c = 0; c < headers.length; c++) {
      final h = headers[c].toLowerCase();
      if (h == 'item') {
        sheet.setColumnWidth(c, 10);
      } else if (h == 'description') {
        sheet.setColumnWidth(c, 52);
      } else if (h == 'value') {
        sheet.setColumnWidth(c, 22);
      } else {
        sheet.setColumnWidth(c, 16);
      }
    }
  }

  static void _writeGaps(Sheet sheet, List<String> gaps) {
    _setText(
      sheet,
      0,
      0,
      'ATMOS field gaps vs official DOT form',
      style: _style(bold: true, size: 11, color: _ink),
    );
    final list = gaps.isEmpty
        ? <String>[
            'Best-effort ATMOS workbook — official cell layout not fully mapped yet.',
          ]
        : gaps;
    for (var i = 0; i < list.length; i++) {
      _setText(sheet, i + 2, 0, '${i + 1}', style: _style(color: _muted, size: 9));
      _setText(sheet, i + 2, 1, list[i], style: _style(color: _ink, size: 9));
    }
    sheet.setColumnWidth(0, 6);
    sheet.setColumnWidth(1, 90);
  }

  static void _writeAuditData(
    Sheet sheet, {
    required DotFormCatalogEntry form,
    required DotReportPreviewTable preview,
    required String scopeLabel,
    required DateTime startDate,
    required DateTime endDate,
  }) {
    _setText(sheet, 0, 0, form.code, style: _style(bold: true));
    _setText(sheet, 0, 1, form.title);
    _setText(sheet, 0, 2, scopeLabel);
    _setText(
      sheet,
      0,
      3,
      '${startDate.toIso8601String().split('T').first} → ${endDate.toIso8601String().split('T').first}',
    );
    _setText(sheet, 1, 0, preview.summaryLine);
    for (var c = 0; c < preview.headers.length; c++) {
      _setText(sheet, 3, c, preview.headers[c], style: _style(bold: true));
    }
    for (var i = 0; i < preview.rows.length; i++) {
      for (var c = 0; c < preview.rows[i].length; c++) {
        _setText(sheet, 4 + i, c, preview.rows[i][c]);
      }
    }
    if (preview.footer != null) {
      final r = 4 + preview.rows.length;
      for (var c = 0; c < preview.footer!.length; c++) {
        _setText(sheet, r, c, preview.footer![c], style: _style(bold: true));
      }
    }
  }

  static void _mergeWrite(
    Sheet sheet, {
    required int row,
    required int lastCol,
    required String text,
    required CellStyle style,
    double? height,
  }) {
    for (var c = 0; c <= lastCol; c++) {
      final cell = sheet.cell(
        CellIndex.indexByColumnRow(columnIndex: c, rowIndex: row),
      );
      cell.value = TextCellValue(c == 0 ? text : '');
      cell.cellStyle = style;
    }
    if (lastCol > 0) {
      sheet.merge(
        CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: row),
        CellIndex.indexByColumnRow(columnIndex: lastCol, rowIndex: row),
      );
      sheet.setMergedCellStyle(
        CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: row),
        style,
      );
    }
    if (height != null) sheet.setRowHeight(row, height);
  }

  static void _setText(Sheet sheet, int row, int col, String value, {CellStyle? style}) {
    final cell = sheet.cell(
      CellIndex.indexByColumnRow(columnIndex: col, rowIndex: row),
    );
    cell.value = TextCellValue(value);
    if (style != null) cell.cellStyle = style;
  }

  static CellStyle _style({
    bool bold = false,
    bool italic = false,
    String color = _ink,
    String fill = _white,
    int size = 10,
    HorizontalAlign align = HorizontalAlign.Left,
    bool border = false,
    String? bottomBorderColor,
    BorderStyle? bottomBorderStyle,
  }) {
    final edge = Border(
      borderStyle: BorderStyle.Thin,
      borderColorHex: ExcelColor.fromHexString(_border),
    );
    return CellStyle(
      bold: bold,
      italic: italic,
      fontSize: size,
      fontColorHex: ExcelColor.fromHexString(color),
      backgroundColorHex: ExcelColor.fromHexString(fill),
      horizontalAlign: align,
      verticalAlign: VerticalAlign.Center,
      leftBorder: border ? edge : null,
      rightBorder: border ? edge : null,
      topBorder: border ? edge : null,
      bottomBorder: bottomBorderStyle != null
          ? Border(
              borderStyle: bottomBorderStyle,
              borderColorHex: ExcelColor.fromHexString(bottomBorderColor ?? _orange),
            )
          : (border ? edge : null),
    );
  }

  /// A4 + horizontal center + fit-to-width + repeating header + print area.
  static List<int> _attachPrintLayout(
    Uint8List bytes, {
    required String sheetName,
    required int lastCol,
    required int lastRow,
    required int headerRow,
    required bool landscape,
  }) {
    try {
      final archive = ZipDecoder().decodeBytes(bytes);
      final files = <String, List<int>>{};
      for (final f in archive) {
        if (!f.isFile) continue;
        files[f.name.replaceAll('\\', '/')] = f.content as List<int>;
      }

      final workbookXml = utf8.decode(files['xl/workbook.xml'] ?? const []);
      final relsXml = utf8.decode(files['xl/_rels/workbook.xml.rels'] ?? const []);
      final rid = _sheetRidFor(workbookXml, sheetName);
      if (rid == null) return bytes;
      final target = _relTarget(relsXml, rid);
      if (target == null) return bytes;
      final sheetPath = target.startsWith('/')
          ? target.substring(1)
          : (target.startsWith('xl/') ? target : 'xl/$target');
      var sheetXml = utf8.decode(files[sheetPath] ?? const []);
      if (sheetXml.isEmpty) return bytes;

      final endCol = _colLetter(lastCol);
      final printAreaRef = "'$sheetName'!\$A\$1:\$$endCol\$$lastRow";
      // Repeat the orange header row on each printed page.
      final titlesRef = "'$sheetName'!\$${headerRow + 1}:\$${headerRow + 1}";

      sheetXml = _injectPageSetup(
        sheetXml,
        landscape: landscape,
        freezeAt: headerRow + 1,
      );
      files[sheetPath] = utf8.encode(sheetXml);

      files['xl/workbook.xml'] = utf8.encode(
        _injectDefinedNames(
          workbookXml,
          printArea: printAreaRef,
          printTitles: titlesRef,
          sheetName: sheetName,
        ),
      );

      final out = Archive();
      for (final entry in files.entries) {
        out.addFile(ArchiveFile(entry.key, entry.value.length, entry.value));
      }
      return ZipEncoder().encode(out) ?? bytes;
    } catch (_) {
      return bytes;
    }
  }

  static String _injectPageSetup(
    String sheetXml, {
    required bool landscape,
    required int freezeAt,
  }) {
    final orientation = landscape ? 'landscape' : 'portrait';
    final margins =
        '<pageMargins left="0.5" right="0.5" top="0.5" bottom="0.5" header="0.3" footer="0.3"/>';
    final setup =
        '<pageSetup paperSize="9" orientation="$orientation" fitToWidth="1" fitToHeight="0" horizontalCentered="1"/>';
    final printOpts = '<printOptions horizontalCentered="1"/>';

    var xml = sheetXml;
    if (!xml.contains('<pageSetup')) {
      // excel package often emits self-closing <pageMargins .../>.
      if (xml.contains('</pageMargins>')) {
        xml = xml.replaceFirst('</pageMargins>', '</pageMargins>$setup$printOpts');
      } else if (RegExp(r'<pageMargins[^>]*/>').hasMatch(xml)) {
        xml = xml.replaceFirstMapped(
          RegExp(r'<pageMargins[^>]*/>'),
          (m) => '$margins$setup$printOpts',
        );
      } else if (xml.contains('</worksheet>')) {
        xml = xml.replaceFirst('</worksheet>', '$margins$setup$printOpts</worksheet>');
      } else {
        xml = '$xml$margins$setup$printOpts';
      }
    } else if (!xml.contains('horizontalCentered')) {
      xml = xml.replaceFirst('<pageSetup ', '<pageSetup horizontalCentered="1" ');
    }

    // Freeze below the table header so titles stay visible while scrolling.
    if (!xml.contains('state="frozen"')) {
      final pane =
          '<pane ySplit="$freezeAt" topLeftCell="A${freezeAt + 1}" activePane="bottomLeft" state="frozen"/>';
      final selfClosing = RegExp(r'<sheetView([^>]*)/>');
      if (selfClosing.hasMatch(xml)) {
        xml = xml.replaceFirstMapped(
          selfClosing,
          (m) => '<sheetView${m.group(1)}>$pane</sheetView>',
        );
      } else if (xml.contains('</sheetView>')) {
        xml = xml.replaceFirst('</sheetView>', '$pane</sheetView>');
      }
    }
    return xml;
  }

  static String _injectDefinedNames(
    String workbookXml, {
    required String printArea,
    required String printTitles,
    required String sheetName,
  }) {
    // Resolve localSheetId from sheet order.
    final sheets = RegExp(r'<sheet[^>]*name="([^"]+)"')
        .allMatches(workbookXml)
        .map((m) => m.group(1)!)
        .toList();
    final localId = sheets.indexOf(sheetName);
    if (localId < 0) return workbookXml;

    final block = '<definedNames>'
        '<definedName name="_xlnm.Print_Area" localSheetId="$localId">$printArea</definedName>'
        '<definedName name="_xlnm.Print_Titles" localSheetId="$localId">$printTitles</definedName>'
        '</definedNames>';

    if (workbookXml.contains('<definedNames>')) {
      // Replace existing print names lightly — append if missing.
      if (workbookXml.contains('_xlnm.Print_Area')) return workbookXml;
      return workbookXml.replaceFirst(
        '</definedNames>',
        '<definedName name="_xlnm.Print_Area" localSheetId="$localId">$printArea</definedName>'
            '<definedName name="_xlnm.Print_Titles" localSheetId="$localId">$printTitles</definedName>'
            '</definedNames>',
      );
    }
    if (workbookXml.contains('<sheets>')) {
      // Insert after </sheets>.
      return workbookXml.replaceFirst('</sheets>', '</sheets>$block');
    }
    return workbookXml;
  }

  static String? _sheetRidFor(String workbookXml, String sheetName) {
    final re = RegExp(
      'name="${RegExp.escape(sheetName)}"[^>]*r:id="(rId\\d+)"'
      '|r:id="(rId\\d+)"[^>]*name="${RegExp.escape(sheetName)}"',
    );
    final m = re.firstMatch(workbookXml);
    return m?.group(1) ?? m?.group(2);
  }

  static String? _relTarget(String relsXml, String rid) {
    final re = RegExp('Id="$rid"[^>]*Target="([^"]+)"');
    final m = re.firstMatch(relsXml);
    if (m != null) return m.group(1);
    final re2 = RegExp('Target="([^"]+)"[^>]*Id="$rid"');
    return re2.firstMatch(relsXml)?.group(1);
  }

  static String _colLetter(int index) {
    var n = index + 1;
    final buf = StringBuffer();
    while (n > 0) {
      final rem = (n - 1) % 26;
      buf.writeCharCode(65 + rem);
      n = (n - 1) ~/ 26;
    }
    return buf.toString().split('').reversed.join();
  }
}

import 'package:excel/excel.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:http/http.dart' as http;

import 'package:atmos_trs_system/config/supabase_report_templates_config.dart';
import 'package:atmos_trs_system/models/mice_register.dart';
import 'package:atmos_trs_system/utils/mice_register_calculator.dart';
import 'package:atmos_trs_system/utils/mice_report_query.dart';
import 'package:atmos_trs_system/utils/checkin_report_summary_csv.dart';
import 'package:atmos_trs_system/utils/checkin_visitor_expansion.dart';
import 'package:atmos_trs_system/utils/dae3_aggregates.dart';
import 'package:atmos_trs_system/utils/dot_report_preview.dart';
import 'package:atmos_trs_system/utils/ae_register_report_query.dart';
import 'package:atmos_trs_system/utils/dot_var2_visitor_record_report.dart';

/// Result of a filled (or blank) DOT template export.
class DotReportExportResult {
  const DotReportExportResult({
    required this.bytes,
    required this.filename,
    required this.gaps,
    required this.summary,
    required this.checkInsProcessed,
  });

  final List<int> bytes;
  final String filename;
  final List<String> gaps;
  final String summary;
  final int checkInsProcessed;
}

class DotReportTemplateFetchException implements Exception {
  DotReportTemplateFetchException(this.message);
  final String message;

  @override
  String toString() => message;
}

/// Fetches official DOT templates from Supabase and appends ATMOS data sheets.
class DotReportExportService {
  final http.Client _client;
  final bool _ownsClient;

  DotReportExportService({http.Client? client})
      : _client = client ?? http.Client(),
        _ownsClient = client == null;

  void dispose() {
    if (_ownsClient) _client.close();
  }

  Future<List<int>> fetchTemplateBytes(String publicUrl) async {
    late http.Response response;
    try {
      response = await _client.get(Uri.parse(publicUrl)).timeout(
            const Duration(seconds: 45),
          );
    } catch (e) {
      throw DotReportTemplateFetchException(
        'Could not reach Supabase template URL. Check your connection.\n$e',
      );
    }
    if (response.statusCode != 200) {
      throw DotReportTemplateFetchException(
        'Template download failed (HTTP ${response.statusCode}). '
        'Confirm the file exists in the "${SupabaseReportTemplatesConfig.bucket}" bucket.\n'
        'URL: $publicUrl',
      );
    }
    if (response.bodyBytes.isEmpty) {
      throw DotReportTemplateFetchException(
        'Template file was empty. Re-upload it in Supabase Storage.',
      );
    }
    return response.bodyBytes;
  }

  Future<List<int>> downloadBlankTemplate(DotBlankTemplate template) {
    return fetchTemplateBytes(template.publicUrl);
  }

  Future<List<int>> downloadCatalogBlank(DotFormCatalogEntry form) {
    return fetchTemplateBytes(form.publicUrl);
  }

  /// Primary Excel path for Analytics — filled / best-effort for every catalog form.
  Future<DotReportExportResult> exportCatalog({
    required DotFormCatalogEntry form,
    required DateTime startDate,
    required DateTime endDate,
    required List<Map<String, dynamic>> checkIns,
    required List<Map<String, dynamic>> tourists,
    required List<DotVar2SpotCatalogEntry> catalogSpots,
    required String scopeLabel,
    required String scopeSlug,
    DateTime? Function(Map<String, dynamic> checkIn)? parseTimestamp,
    AeRegisterReportData aeRegister = AeRegisterReportData.empty,
    MiceReportData mice = MiceReportData.empty,
    CusExportOptions cusOptions = const CusExportOptions(),
  }) async {
    final type = form.reportType;
    if (type != null && form.fillMode == DotFormFillMode.atmosFill) {
      return exportFilled(
        type: type,
        startDate: startDate,
        endDate: endDate,
        checkIns: checkIns,
        tourists: tourists,
        catalogSpots: catalogSpots,
        scopeLabel: scopeLabel,
        scopeSlug: scopeSlug,
        parseTimestamp: parseTimestamp,
        aeRegister: aeRegister,
        mice: mice,
        cusOptions: cusOptions,
      );
    }

    final preview = buildDotReportPreview(
      form: form,
      startDate: startDate,
      endDate: endDate,
      checkIns: checkIns,
      tourists: tourists,
      catalogSpots: catalogSpots,
      scopeLabel: scopeLabel,
      parseTimestamp: parseTimestamp,
      aeRegister: aeRegister,
    );
    return _workbookFromPreview(
      form: form,
      preview: preview,
      scopeLabel: scopeLabel,
      scopeSlug: scopeSlug,
      startDate: startDate,
      endDate: endDate,
    );
  }

  Future<DotReportExportResult> exportFilled({
    required DotReportType type,
    required DateTime startDate,
    required DateTime endDate,
    required List<Map<String, dynamic>> checkIns,
    required List<Map<String, dynamic>> tourists,
    required List<DotVar2SpotCatalogEntry> catalogSpots,
    required String scopeLabel,
    required String scopeSlug,
    DateTime? Function(Map<String, dynamic> checkIn)? parseTimestamp,
    AeRegisterReportData aeRegister = AeRegisterReportData.empty,
    MiceReportData mice = MiceReportData.empty,
    CusExportOptions cusOptions = const CusExportOptions(),
  }) async {
    if (type == DotReportType.cusMice) {
      final template = await _cusTemplateBytes(type.catalogEntry);
      return buildCusWorkbook(
        templateBytes: template.$1,
        templateSource: template.$2,
        mice: mice,
        options: cusOptions,
        scopeLabel: scopeLabel,
        scopeSlug: scopeSlug,
        startDate: startDate,
        endDate: endDate,
      );
    }
    final filtered = _checkInsInRange(
      checkIns,
      startDate,
      endDate,
      parseTimestamp: parseTimestamp,
    ).where((c) => !isExcludedFromOfficialReports(c)).toList();
    final touristById = _indexTourists(tourists);
    // Join signup profiles onto check-ins so sex / residence / origin fill.
    final enriched = _attachTouristProfiles(filtered, touristById);

    switch (type) {
      case DotReportType.var2VisitorRecord:
        final templateBytes = await fetchTemplateBytes(type.publicUrl);
        return _fillVar2(
          templateBytes: templateBytes,
          filtered: enriched,
          catalogSpots: catalogSpots,
          scopeLabel: scopeLabel,
          scopeSlug: scopeSlug,
          startDate: startDate,
          endDate: endDate,
        );
      case DotReportType.dae3FormA:
        final templateBytes = await fetchTemplateBytes(type.publicUrl);
        return _fillDae3FormA(
          templateBytes: templateBytes,
          filtered: enriched,
          register: aeRegister,
          scopeLabel: scopeLabel,
          scopeSlug: scopeSlug,
          startDate: startDate,
          endDate: endDate,
        );
      case DotReportType.dae3b2Domestic when aeRegister.isEmpty:
        final templateBytes = await fetchTemplateBytes(type.publicUrl);
        return _fillDae3b2Domestic(
          templateBytes: templateBytes,
          filtered: enriched,
          touristById: touristById,
          scopeLabel: scopeLabel,
          scopeSlug: scopeSlug,
          startDate: startDate,
          endDate: endDate,
        );
      case DotReportType.dae3b2Domestic:
      case DotReportType.var4DomesticTravelers:
      case DotReportType.var5InternationalVisitors:
      case DotReportType.dae3bFormAInternational:
        final form = type.catalogEntry;
        final preview = buildDotReportPreview(
          form: form,
          startDate: startDate,
          endDate: endDate,
          checkIns: checkIns,
          tourists: tourists,
          catalogSpots: catalogSpots,
          scopeLabel: scopeLabel,
          parseTimestamp: parseTimestamp,
          aeRegister: aeRegister,
        );
        return _workbookFromPreview(
          form: form,
          preview: preview,
          scopeLabel: scopeLabel,
          scopeSlug: scopeSlug,
          startDate: startDate,
          endDate: endDate,
        );
      case DotReportType.cusMice:
        throw StateError('unreachable');
    }
  }

  // ------------------------------------------------------------ CUS MICE

  /// Official CUS template: Supabase bucket first, bundled copy second.
  Future<(List<int>?, String)> _cusTemplateBytes(DotFormCatalogEntry form) async {
    try {
      return (await fetchTemplateBytes(form.publicUrl), 'Supabase bucket "${SupabaseReportTemplatesConfig.bucket}"');
    } catch (_) {}
    try {
      final data = await rootBundle.load('forms_format/${form.localFilename}');
      return (data.buffer.asUint8List().toList(), 'bundled forms_format copy');
    } catch (_) {}
    return (null, '');
  }

  static const _cusSummarySheet = 'CUS SUMMARY';
  static const _cusByEstSheet = 'CUS BY EST';

  /// Fills the official CUS workbook: CUS SUMMARY (all venues) and/or one
  /// CUS BY EST copy per venue, plus ATMOS_DATA / ATMOS_GAPS. Without a
  /// template, an equivalent workbook with the same columns is built.
  DotReportExportResult buildCusWorkbook({
    required List<int>? templateBytes,
    required MiceReportData mice,
    required String scopeLabel,
    required String scopeSlug,
    required DateTime startDate,
    required DateTime endDate,
    CusExportOptions options = const CusExportOptions(),
    String templateSource = '',
  }) {
    final form = DotReportType.cusMice.catalogEntry;
    final preview = buildCusMicePreview(form: form, mice: mice, scopeLabel: scopeLabel);
    var official = false;
    var excel = Excel.createExcel();
    if (templateBytes != null) {
      try {
        excel = Excel.decodeBytes(templateBytes);
        official = excel.tables.containsKey(_cusSummarySheet) && excel.tables.containsKey(_cusByEstSheet);
      } catch (_) {}
    }
    if (!official) {
      excel = Excel.createExcel();
      _cusScratchSheets(excel);
    }

    final allVenues = mice.venues;
    final withEvents = allVenues.where((v) => v.events.isNotEmpty).toList();
    final single = allVenues.length <= 1;
    final layout = single ? CusLayout.venuesOnly : options.layout;
    final venueSheets = layout == CusLayout.summaryOnly ? <MiceVenueBlock>[] : (single ? allVenues : withEvents);
    final keepByEst = single && venueSheets.isEmpty;

    final used = <String>{...excel.tables.keys};
    final names = <String>[];
    for (final v in venueSheets) {
      final name = _cusSheetName(v.aeName, used);
      used.add(name);
      names.add(name);
      excel.copy(_cusByEstSheet, name);
    }
    excel['ATMOS_DATA'];
    excel['ATMOS_GAPS'];
    // excel 4.0.6 writes new sheets at encode time to sheet{first free
    // sheetId}.xml; the template's CUS SUMMARY is sheetId 17 in sheet1.xml, so
    // new sheets must be materialized before any template sheet is deleted.
    excel = Excel.decodeBytes(excel.encode()!);
    for (final name in excel.tables.keys.toList()) {
      final keep = names.contains(name) ||
          name == 'ATMOS_DATA' ||
          name == 'ATMOS_GAPS' ||
          (name == _cusSummarySheet && layout != CusLayout.venuesOnly) ||
          (name == _cusByEstSheet && keepByEst);
      if (!keep) excel.delete(name);
    }

    for (var i = 0; i < venueSheets.length; i++) {
      _fillCusByEst(excel[names[i]], venueSheets[i], mice, options);
    }
    if (keepByEst) {
      names.add(_cusByEstSheet);
      _fillCusByEst(excel[_cusByEstSheet], null, mice, options, scopeLabel: scopeLabel);
    }
    if (layout != CusLayout.venuesOnly) _fillCusSummary(excel[_cusSummarySheet], mice, scopeLabel);

    final data = excel['ATMOS_DATA'];
    _writeHeaderRow(data, 0, [form.code, form.title, scopeLabel, mice.periodLabel]);
    _writeHeaderRow(data, 1, [preview.summaryLine]);
    _writeHeaderRow(data, 3, preview.headers);
    for (var i = 0; i < preview.rows.length; i++) {
      _writeRow(data, 4 + i, preview.rows[i]);
    }
    if (preview.footer != null) _writeRow(data, 4 + preview.rows.length, preview.footer!);
    var r = 6 + preview.rows.length;
    _writeHeaderRow(data, r++, ['By category', 'Events', 'Attendees', 'Hours']);
    for (final (c, ct) in MiceRegisterCalculator.categoryBreakdown(mice.combined)) {
      _writeRow(data, r++, [c.label, ct.events, ct.attendees, MiceRegisterCalculator.hoursLabel(ct.hours)]);
    }
    final countries = mice.combined.byCountry.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    if (countries.isNotEmpty) {
      r++;
      _writeHeaderRow(data, r++, ['Foreign attendees by country (optional)', 'Attendees']);
      for (final e in countries) {
        _writeRow(data, r++, [e.key, e.value]);
      }
    }

    final gapList = <String>[
      ...preview.gaps,
      official
          ? 'Official CUS template from $templateSource: '
              '${layout == CusLayout.venuesOnly ? '' : '"$_cusSummarySheet" (all venues)'}'
              '${layout == CusLayout.summaryAndVenues ? ' + ' : ''}'
              '${venueSheets.isEmpty ? '' : '${venueSheets.length} "$_cusByEstSheet" sheet(s) (one per venue)'}.'
          : 'Official CUS template unavailable — equivalent workbook built with the same columns.',
      if (!single && layout != CusLayout.summaryOnly && withEvents.length < allVenues.length)
        '${allVenues.length - withEvents.length} venue(s) with no events in range have no BY EST sheet.',
      if (options.officerName.trim().isEmpty || options.mayorName.trim().isEmpty)
        'Tourism Officer / Mayor names left blank — type them in the export panel to print them.',
    ];
    _writeGapsSheet(excel['ATMOS_GAPS'], gapList);
    final first = layout == CusLayout.venuesOnly ? names.first : _cusSummarySheet;
    excel.setDefaultSheet(first);

    final filename = 'dot_cus_mice_${scopeSlug.trim().isEmpty ? 'report' : scopeSlug.trim()}_'
        '${_ym(startDate)}_to_${_ym(endDate)}.xlsx';
    return DotReportExportResult(
      bytes: excel.encode() ?? <int>[],
      filename: filename,
      gaps: gapList,
      summary: preview.summaryLine,
      checkInsProcessed: mice.combined.events,
    );
  }

  /// Excel sheet names: ≤ 31 chars, no []:*?/\ and unique.
  static String _cusSheetName(String venue, Set<String> used) {
    var base = venue.replaceAll(RegExp(r'[\[\]:*?/\\]'), ' ').replaceAll(RegExp(r'\s+'), ' ').trim();
    if (base.isEmpty) base = 'Venue';
    if (base.length > 28) base = base.substring(0, 28).trim();
    var name = base;
    var i = 2;
    while (used.any((u) => u.toLowerCase() == name.toLowerCase())) {
      name = '${base.length > 25 ? base.substring(0, 25) : base} ($i)';
      i++;
    }
    return name;
  }

  static String _cusMonthYear(MiceReportData mice) {
    final s = mice.startDate, e = mice.endDate;
    if (s == null || e == null) return '';
    String m(int x) => _monthNames[x - 1].toUpperCase();
    if (s.year == e.year && s.month == e.month) return 'MONTH : ${m(s.month)}   YEAR : ${s.year}';
    if (s.year == e.year) return 'MONTH : ${m(s.month)} – ${m(e.month)}   YEAR : ${s.year}';
    return 'MONTH : ${m(s.month)} ${s.year} – ${m(e.month)} ${e.year}';
  }

  static const _monthNames = [
    'January', 'February', 'March', 'April', 'May', 'June', 'July',
    'August', 'September', 'October', 'November', 'December',
  ];

  /// CUS SUMMARY: data rows 8–27 (A–O); establishment in column D.
  void _fillCusSummary(Sheet sheet, MiceReportData mice, String scopeLabel) {
    const first = 7;
    const capacity = 20;
    final rows = mice.summaryRows;
    _cusEnsureRows(sheet, first, capacity, rows.length + 1, 15);
    _cusSet(sheet, 1, 2, _cusMonthYear(mice));
    _cusSet(sheet, 1, 12, 'CITY/PROVINCE : $scopeLabel');
    for (var i = 0; i < rows.length; i++) {
      final (v, e) = rows[i];
      _cusEventRow(sheet, first + i, e, v.controlNumbers[e.id], venue: v.aeName);
    }
    if (rows.isNotEmpty) _cusTotalRow(sheet, first + rows.length, mice.combined, summary: true);
  }

  /// CUS BY EST: establishment A4, city L4, data rows 10–29 (A–N),
  /// Tourism Officer / Mayor names on row 33.
  void _fillCusByEst(
    Sheet sheet,
    MiceVenueBlock? v,
    MiceReportData mice,
    CusExportOptions options, {
    String scopeLabel = '',
  }) {
    const first = 9;
    const capacity = 20;
    final events = v?.events ?? const <MiceEvent>[];
    final extra = _cusEnsureRows(sheet, first, capacity, events.length + 1, 14);
    final period = mice.periodLabel.toUpperCase();
    _cusSet(sheet, 1, 0, period.isEmpty ? 'BY ESTABLISHMENT' : 'BY ESTABLISHMENT · $period');
    _cusSet(sheet, 3, 0, 'NAME OF ESTABLISHMENT: ${v?.aeName ?? ''}');
    final city = v?.municipality.isNotEmpty == true ? v!.municipality : scopeLabel;
    _cusSet(sheet, 3, 11, 'CITY/PROVINCE : ${city.isEmpty ? 'Misamis Occidental' : '$city, Misamis Occidental'}');
    for (var i = 0; i < events.length; i++) {
      _cusEventRow(sheet, first + i, events[i], v?.controlNumbers[events[i].id]);
    }
    if (events.isNotEmpty) _cusTotalRow(sheet, first + events.length, MiceRegisterCalculator.totals(events));
    final footer = 32 + extra;
    if (options.officerName.trim().isNotEmpty) _cusSet(sheet, footer, 2, options.officerName.trim().toUpperCase());
    if (options.mayorName.trim().isNotEmpty) _cusSet(sheet, footer, 10, options.mayorName.trim().toUpperCase());
  }

  /// Inserts styled rows when [needed] exceeds the template's [capacity].
  /// Returns how many rows were inserted (footer rows shift by that much).
  int _cusEnsureRows(Sheet sheet, int first, int capacity, int needed, int cols) {
    final extra = needed > capacity ? needed - capacity : 0;
    for (var k = 0; k < extra; k++) {
      final at = first + capacity + k;
      sheet.insertRow(at);
      for (var c = 0; c < cols; c++) {
        final style = sheet.cell(CellIndex.indexByColumnRow(columnIndex: c, rowIndex: at - 1)).cellStyle;
        if (style != null) sheet.cell(CellIndex.indexByColumnRow(columnIndex: c, rowIndex: at)).cellStyle = style;
      }
    }
    return extra;
  }

  /// One event: SUMMARY has the establishment in D (shifts later columns).
  void _cusEventRow(Sheet sheet, int row, MiceEvent e, int? cn, {String? venue}) {
    var c = 0;
    _cusSet(sheet, row, c++, cn);
    _cusSet(sheet, row, c++, MiceRegisterCalculator.dateLabel(e));
    _cusSet(sheet, row, c++, e.eventName);
    if (venue != null) _cusSet(sheet, row, c++, venue);
    _cusSet(sheet, row, c++, e.hours);
    _cusSet(sheet, row, c++, e.eventType);
    _cusSet(sheet, row, c++, e.foreign);
    _cusSet(sheet, row, c++, e.local);
    _cusSet(sheet, row, c++, e.total);
    _cusSet(sheet, row, c++, e.male);
    _cusSet(sheet, row, c++, e.female);
    _cusSet(sheet, row, c++, e.hasExhibit ? e.exhibitors : null);
    _cusSet(sheet, row, c++, e.hasExhibit ? e.exhibitVisitors : null);
    _cusSet(sheet, row, c++, e.organizerCell);
    _cusSet(sheet, row, c++, e.remarks);
  }

  void _cusTotalRow(Sheet sheet, int row, MiceMonthTotals t, {bool summary = false}) {
    final o = summary ? 1 : 0;
    _cusSet(sheet, row, 1, 'TOTAL');
    _cusSet(sheet, row, 2, '${t.events} event(s)');
    _cusSet(sheet, row, 3 + o, t.hours);
    _cusSet(sheet, row, 5 + o, t.foreign);
    _cusSet(sheet, row, 6 + o, t.local);
    _cusSet(sheet, row, 7 + o, t.attendees);
    _cusSet(sheet, row, 8 + o, t.male);
    _cusSet(sheet, row, 9 + o, t.female);
    _cusSet(sheet, row, 10 + o, t.exhibitors == 0 ? null : t.exhibitors);
    _cusSet(sheet, row, 11 + o, t.exhibitVisitors == 0 ? null : t.exhibitVisitors);
  }

  /// Like [_setCellValue] but keeps fractional numbers (2.5 hours).
  void _cusSet(Sheet sheet, int row, int col, Object? value) {
    final cell = sheet.cell(CellIndex.indexByColumnRow(columnIndex: col, rowIndex: row));
    if (value == null || (value is String && value.isEmpty)) {
      cell.value = null;
    } else if (value is int) {
      cell.value = IntCellValue(value);
    } else if (value is double) {
      cell.value = value == value.roundToDouble() ? IntCellValue(value.round()) : DoubleCellValue(value);
    } else {
      cell.value = TextCellValue(value.toString());
    }
  }

  /// Template-free fallback with the official labels at the same cells.
  void _cusScratchSheets(Excel excel) {
    final defaultName = excel.getDefaultSheet();
    if (defaultName != null) excel.rename(defaultName, _cusSummarySheet);
    final s = excel[_cusSummarySheet];
    _writeRow(s, 0, ['MONTHLY SUMMARY OF MICE UTILIZATION SURVEY FORM']);
    _writeRow(s, 6, [
      'CN', 'DATE', 'EVENT NAME', 'NAME OF ESTABLISHMENT', 'No. of Hour', 'TYPE OF EVENT',
      'Foreign', 'Local', 'Total Number', 'Male', 'Female',
      'Number of Exhibitor', 'Number of Visitors', 'Name and Address of Organizer, Contact Person & Tel. No.', 'REMARKS',
    ]);
    _writeRow(s, 27, ['NOTE:  PLEASE FILL UP ONLY COLUMNS WITH QUESTION MARK (?).']);
    final b = excel[_cusByEstSheet];
    _writeRow(b, 0, ['MICE UTILIZATION SURVEY FORM']);
    _writeRow(b, 1, ['BY ESTABLISHMENT']);
    _writeRow(b, 8, [
      'CN', 'DATE', 'EVENT NAME', 'No. of Hour', 'TYPE OF EVENT',
      'Foreign', 'Local', 'Total Number', 'Male', 'Female',
      'Number of Exhibitor', 'Number of Visitors', 'Name and Address of Organizer, Contact Person & Tel. No.', 'REMARKS',
    ]);
    _writeRow(b, 29, ['NOTE:  PLEASE FILL UP ONLY COLUMNS WITH QUESTION MARK (?).']);
    _writeRow(b, 33, ['', '', 'Name of Tourism Officer', '', '', '', '', '', '', '', 'Mayor']);
  }

  DotReportExportResult _workbookFromPreview({
    required DotFormCatalogEntry form,
    required DotReportPreviewTable preview,
    required String scopeLabel,
    required String scopeSlug,
    required DateTime startDate,
    required DateTime endDate,
  }) {
    final excel = Excel.createExcel();
    final data = excel['ATMOS_DATA'];
    _removeSheetIfExists(excel, 'Sheet1');
    _writeHeaderRow(data, 0, [
      form.code,
      form.title,
      scopeLabel,
      '${startDate.toIso8601String().split('T').first} → ${endDate.toIso8601String().split('T').first}',
    ]);
    _writeHeaderRow(data, 1, [preview.summaryLine]);
    _writeHeaderRow(data, 3, preview.headers);
    for (var i = 0; i < preview.rows.length; i++) {
      _writeRow(data, 4 + i, preview.rows[i]);
    }
    if (preview.footer != null) {
      _writeRow(data, 4 + preview.rows.length, preview.footer!);
    }
    final gaps = excel['ATMOS_GAPS'];
    final gapList = preview.gaps.isEmpty
        ? <String>[
            'Best-effort ATMOS workbook — official cell layout not fully mapped yet.',
          ]
        : List<String>.from(preview.gaps);
    _writeGapsSheet(gaps, gapList);

    final s =
        '${startDate.year}${startDate.month.toString().padLeft(2, '0')}${startDate.day.toString().padLeft(2, '0')}';
    final e =
        '${endDate.year}${endDate.month.toString().padLeft(2, '0')}${endDate.day.toString().padLeft(2, '0')}';
    final slug = scopeSlug.trim().isEmpty ? 'report' : scopeSlug.trim();
    final filename = 'ATMOS_${form.id}_${slug}_${s}_$e.xlsx';
    final bytes = excel.encode() ?? <int>[];

    return DotReportExportResult(
      bytes: bytes,
      filename: filename,
      gaps: gapList,
      summary: preview.summaryLine,
      checkInsProcessed: preview.rows.length,
    );
  }

  DotReportExportResult _fillVar2({
    required List<int> templateBytes,
    required List<Map<String, dynamic>> filtered,
    required List<DotVar2SpotCatalogEntry> catalogSpots,
    required String scopeLabel,
    required String scopeSlug,
    required DateTime startDate,
    required DateTime endDate,
  }) {
    final var2 = buildDotVar2VisitorRecordReport(
      checkIns: filtered,
      catalogSpots: catalogSpots,
      municipalityName: scopeLabel,
      startDate: startDate,
      endDate: endDate,
    );

    final excel = _decodeOrEmpty(templateBytes);
    final filledRows = _writeOfficialVar2Sheet(excel, var2);

    _removeSheetIfExists(excel, 'ATMOS_GAPS');
    final gaps = excel['ATMOS_GAPS'];
    final gapList = <String>[
      'Official "${_var2SheetName(excel)}" sheet filled from QR check-ins in the selected period.',
      'Sex and residence come from tourist signup profiles linked to each check-in.',
      'Missing profiles: visit counted in Grand Total only (residence columns left blank).',
      'DOT attraction codes blank when not set on tourist spots.',
      if (var2.rows.where((r) => r.grandTotal.total > 0).length > filledRows)
        'More attractions with visits than template rows ($filledRows) — overflow listed in gaps only.',
      var2.note,
    ];
    _writeGapsSheet(gaps, gapList);

    // Keep a compact ATMOS_DATA mirror for audit / copy-paste.
    _removeSheetIfExists(excel, 'ATMOS_DATA');
    final data = excel['ATMOS_DATA'];
    _writeHeaderRow(data, 0, ['Check-in based VAR 2 values written to official sheet']);
    _writeHeaderRow(data, 1, ['Month/Year', var2.monthYearLabel]);
    _writeHeaderRow(data, 2, ['Scope', var2.municipalityName]);
    _writeHeaderRow(data, 3, ['Check-ins', '${var2.checkInsProcessed}']);
    _writeHeaderRow(data, 5, [
      'Name',
      'Code',
      'ThisMun M',
      'ThisMun F',
      'ThisMun T',
      'ThisProv M',
      'ThisProv F',
      'ThisProv T',
      'OtherProv M',
      'OtherProv F',
      'OtherProv T',
      'Foreign M',
      'Foreign F',
      'Foreign T',
      'Grand M',
      'Grand F',
      'Grand T',
    ]);
    var auditRow = 6;
    for (final r in var2.rows.where((r) => r.grandTotal.total > 0)) {
      _writeRow(data, auditRow++, [
        r.name,
        r.attractionCode,
        r.thisMunicipality.male,
        r.thisMunicipality.female,
        r.thisMunicipality.total,
        r.thisProvince.male,
        r.thisProvince.female,
        r.thisProvince.total,
        r.otherProvince.male,
        r.otherProvince.female,
        r.otherProvince.total,
        r.foreign.male,
        r.foreign.female,
        r.foreign.total,
        r.grandTotal.male,
        r.grandTotal.female,
        r.grandTotal.total,
      ]);
    }

    final bytes = excel.encode() ?? templateBytes;
    final filename = var2XlsxFilename(
      municipalitySlug: scopeSlug,
      startDate: startDate,
      endDate: endDate,
    ).replaceFirst('dot_var2_visitor_record_', 'dot_var2_filled_');

    return DotReportExportResult(
      bytes: bytes,
      filename: filename,
      gaps: gapList,
      summary:
          'VAR 2 official sheet filled from ${var2.checkInsProcessed} check-ins '
          '($filledRows attraction rows)',
      checkInsProcessed: var2.checkInsProcessed,
    );
  }

  String _var2SheetName(Excel excel) {
    for (final name in excel.tables.keys) {
      if (name.toLowerCase().contains('var')) return name;
    }
    return excel.tables.keys.isNotEmpty ? excel.tables.keys.first : 'VAR 2';
  }

  /// Writes check-in aggregates into the official VAR 2M layout.
  /// Returns how many attraction data rows were written.
  int _writeOfficialVar2Sheet(Excel excel, DotVar2VisitorRecordResult var2) {
    final sheetName = _var2SheetName(excel);
    final sheet = excel[sheetName];

    // Header fields (label at col 4 → value at col 5).
    _setCellValue(sheet, 4, 5, var2.monthYearLabel);
    _setCellValue(sheet, 5, 5, var2.municipalityName);

    // Template data body: Excel rows 12–25 → indices 11–24 (14 slots).
    const firstDataRow = 11;
    const lastDataRow = 24;
    const capacity = lastDataRow - firstDataRow + 1;

    // Male/Female input cols; totals also written so export works if formulas drop.
    const maleFemaleCols = <(int male, int female, int total)>[
      (3, 4, 5), // This Municipality
      (6, 7, 8), // This Province
      (9, 10, 11), // Other Province
      (12, 13, 14), // Foreign
      (15, 16, 17), // Grand Total
    ];

    for (var r = firstDataRow; r <= lastDataRow; r++) {
      _setCellValue(sheet, r, 1, '');
      _setCellValue(sheet, r, 2, '');
      for (final cols in maleFemaleCols) {
        _setCellValue(sheet, r, cols.$1, null);
        _setCellValue(sheet, r, cols.$2, null);
        _setCellValue(sheet, r, cols.$3, null);
      }
    }

    final ordered = [
      ...var2.rows.where((r) => r.grandTotal.total > 0),
      // Keep empty catalog rows only if there is spare capacity.
    ];
    final withVisits = ordered.take(capacity).toList();
    final remaining = capacity - withVisits.length;
    if (remaining > 0) {
      withVisits.addAll(
        var2.rows
            .where((r) => r.grandTotal.total == 0)
            .take(remaining),
      );
    }

    for (var i = 0; i < withVisits.length; i++) {
      final row = withVisits[i];
      final r = firstDataRow + i;
      _setCellValue(sheet, r, 1, row.name);
      _setCellValue(sheet, r, 2, row.attractionCode);
      final buckets = [
        row.thisMunicipality,
        row.thisProvince,
        row.otherProvince,
        row.foreign,
        row.grandTotal,
      ];
      for (var b = 0; b < buckets.length; b++) {
        final counts = buckets[b];
        final cols = maleFemaleCols[b];
        _setCellValue(sheet, r, cols.$1, counts.male);
        _setCellValue(sheet, r, cols.$2, counts.female);
        _setCellValue(sheet, r, cols.$3, counts.total);
      }
    }

    // Footer totals (row index 25).
    const footerRow = 25;
    final f = var2.footerTotals;
    final footerBuckets = [
      f.thisMunicipality,
      f.thisProvince,
      f.otherProvince,
      f.foreign,
      f.grandTotal,
    ];
    for (var b = 0; b < footerBuckets.length; b++) {
      final counts = footerBuckets[b];
      final cols = maleFemaleCols[b];
      _setCellValue(sheet, footerRow, cols.$1, counts.male);
      _setCellValue(sheet, footerRow, cols.$2, counts.female);
      _setCellValue(sheet, footerRow, cols.$3, counts.total);
    }

    return withVisits.length;
  }

  DotReportExportResult _fillDae3FormA({
    required List<int> templateBytes,
    required List<Map<String, dynamic>> filtered,
    required AeRegisterReportData register,
    required String scopeLabel,
    required String scopeSlug,
    required DateTime startDate,
    required DateTime endDate,
  }) {
    // Official DAE-3 template is AE monthly record.
    // Prefer hotel DOT registers; fall back to attraction/LGU check-in proxy.
    final excel = _decodeOrEmpty(templateBytes);
    final targetName = excel.tables.keys.contains('DAE3')
        ? 'DAE3'
        : (excel.tables.keys.isNotEmpty ? excel.tables.keys.first : 'DAE3');
    final sheet = excel[targetName];

    // Clear sample demo rows (indices 3..43).
    for (var r = 3; r <= 43; r++) {
      for (var c = 1; c <= 10; c++) {
        _setCellValue(sheet, r, c, null);
      }
    }

    final fromRegister = register.isNotEmpty;
    final rows = aggregateDae3PreferringRegister(
      reports: register.reports,
      checkIns: filtered,
      scopeLabel: scopeLabel,
    );

    const first = 3;
    const last = 43;
    final capacity = last - first + 1;
    final written = rows.take(capacity).toList();
    for (var i = 0; i < written.length; i++) {
      final row = written[i];
      final r = first + i;
      _setCellValue(sheet, r, 1, row.province);
      _setCellValue(sheet, r, 2, row.municipality);
      _setCellValue(sheet, r, 3, row.year);
      _setCellValue(sheet, r, 4, _monthName(row.month));
      _setCellValue(sheet, r, 5, row.aeId);
      _setCellValue(sheet, r, 6, row.typeClass);
      _setCellValue(sheet, r, 7, row.roomsAvailable);
      _setCellValue(sheet, r, 8, row.guestsCheckedIn);
      _setCellValue(sheet, r, 9, row.guestNights);
      _setCellValue(sheet, r, 10, row.roomsOccupied);
    }

    _removeSheetIfExists(excel, 'ATMOS_GAPS');
    final gaps = excel['ATMOS_GAPS'];
    final gapList = <String>[
      if (fromRegister) ...[
        ...register.sourceGaps('DAE-3'),
        'Type/class = register classification code (else AE type); rooms available = AE total rooms.',
        'Guests = check-ins; guest nights = Σ register guests; rooms occupied = register rows.',
      ] else ...[
        'No hotel DOT register months in range — filled from QR check-ins as labeled proxy.',
        'AE-ID uses tourist spot name as proxy — not accommodation_establishments registry.',
        'Google Form / http(s) spot labels are excluded from AE-ID rows.',
        'Total rooms available left blank (no hotel register in range).',
      ],
      'Base file: ${DotReportType.dae3FormA.objectFilename} (Supabase bucket "${SupabaseReportTemplatesConfig.bucket}").',
      if (rows.length > capacity)
        'Overflow: ${rows.length - capacity} AE-month rows omitted (template capacity $capacity).',
    ];
    _writeGapsSheet(gaps, gapList);

    final bytes = excel.encode() ?? templateBytes;
    final filename =
        'dot_dae3_filled_${scopeSlug}_${_ym(startDate)}_to_${_ym(endDate)}.xlsx';

    return DotReportExportResult(
      bytes: bytes,
      filename: filename,
      gaps: gapList,
      summary: fromRegister
          ? 'DAE-3 filled from ${register.reports.length} hotel register month(s) (${written.length} rows)'
          : 'DAE-3 filled from ${filtered.length} check-ins (${written.length} rows)',
      checkInsProcessed: fromRegister ? register.combined.checkIns : filtered.length,
    );
  }

  DotReportExportResult _fillDae3b2Domestic({
    required List<int> templateBytes,
    required List<Map<String, dynamic>> filtered,
    required Map<String, Map<String, dynamic>> touristById,
    required String scopeLabel,
    required String scopeSlug,
    required DateTime startDate,
    required DateTime endDate,
  }) {
    // Official DAE3B.2 uses styles the excel package cannot decode — build a
    // filled workbook with the same sheet titles instead.
    final fetchedOfficialBytes = templateBytes.length;
    final byOriginMonth = <String, Map<String, int>>{};
    final bySex = <String, int>{'Male': 0, 'Female': 0, 'Unknown': 0};
    var missingProfile = 0;
    var foreignSkipped = 0;
    var missingOrigin = 0;

    var hasProxy = false;
    for (final entry in expandCheckInsToVisitors(
      filtered,
      profileFor: (c) {
        if (c['touristProfile'] is Map) {
          return Map<String, dynamic>.from(c['touristProfile'] as Map);
        }
        final uid = _userIdFromCheckIn(c);
        return uid == null ? null : touristById[uid];
      },
    )) {
      final c = entry.checkIn;
      final unit = entry.unit;
      if (unit.isProxy) hasProxy = true;
      final tourist = (!unit.hasProfile ||
              (unit.isProxy && !visitorHasResidencyInfo(unit.profile)))
          ? null
          : unit.profile;

      if (tourist == null) {
        missingProfile++;
        continue;
      }
      if (!_isDomesticTourist(tourist)) {
        foreignSkipped++;
        continue;
      }
      final origin = _domesticOriginLabel(tourist);
      if (origin.isEmpty) {
        missingOrigin++;
        continue;
      }
      const weight = 1;
      var addMale = 0;
      var addFemale = 0;
      final sex = (tourist['sex']?.toString() ?? '').trim().toLowerCase();
      if (sex.startsWith('m')) {
        addMale = 1;
      } else if (sex.startsWith('f')) {
        addFemale = 1;
      } else {
        bySex['Unknown'] = bySex['Unknown']! + 1;
      }

      final monthKey = _monthKeyFromCheckIn(c);
      byOriginMonth.putIfAbsent(origin, () => <String, int>{});
      byOriginMonth[origin]![monthKey] =
          (byOriginMonth[origin]![monthKey] ?? 0) + weight;
      bySex['Male'] = bySex['Male']! + addMale;
      bySex['Female'] = bySex['Female']! + addFemale;
    }

    final months = _monthKeysBetween(startDate, endDate);
    final excel = Excel.createExcel();
    final defaultName = excel.getDefaultSheet()!;
    excel.rename(defaultName, 'DAE3B.2 (Monthly)');
    final sheet = excel['DAE3B.2 (Monthly)'];

    _writeHeaderRow(sheet, 0, [
      'FORM: DAE 3B.2 Domestic — filled from ATMOS check-ins (proxy)',
    ]);
    _writeHeaderRow(sheet, 1, ['Scope', scopeLabel]);
    _writeHeaderRow(sheet, 2, [
      'Period',
      '${_ymd(startDate)} to ${_ymd(endDate)}',
    ]);
    _writeHeaderRow(sheet, 3, [
      'Sex totals',
      'Male ${bySex['Male']}',
      'Female ${bySex['Female']}',
      'Unknown ${bySex['Unknown']}',
    ]);
    _writeHeaderRow(sheet, 5, [
      'Province / City of origin',
      ...months,
      'Total',
    ]);

    var row = 6;
    final origins = byOriginMonth.keys.toList()..sort();
    for (final origin in origins) {
      final monthMap = byOriginMonth[origin]!;
      var total = 0;
      final cells = <dynamic>[origin];
      for (final m in months) {
        final n = monthMap[m] ?? 0;
        total += n;
        cells.add(n);
      }
      cells.add(total);
      _writeRow(sheet, row++, cells);
    }
    if (origins.isEmpty) {
      _writeRow(sheet, row, [
        '(no domestic-origin check-ins in period)',
        ...List.filled(months.length, 0),
        0,
      ]);
    }

    final gapsSheet = excel['ATMOS_GAPS'];
    final gapList = <String>[
      'No hotel DOT register months in range — filled from attraction/LGU check-ins as proxy.',
      'Official DAE3B.2 template ($fetchedOfficialBytes bytes) could not be merged '
          'by the Excel library — this file is filled with equivalent columns.',
      'Download the blank official template separately if you need the exact DOT layout.',
      'PSA region not collected.',
      'Missing tourist profile / unknown residence: $missingProfile',
      'Foreign / non-domestic skipped: $foreignSkipped',
      'Domestic with empty province/city: $missingOrigin',
      if (hasProxy) kCompanionProxyGapNote,
    ];
    _writeGapsSheet(gapsSheet, gapList);

    final bytes = excel.encode() ?? <int>[];
    final filename =
        'dot_dae3b2_domestic_filled_${scopeSlug}_${_ym(startDate)}_to_${_ym(endDate)}.xlsx';

    return DotReportExportResult(
      bytes: bytes,
      filename: filename,
      gaps: gapList,
      summary:
          'DAE 3B.2 filled from check-ins (${origins.length} origins, ${filtered.length} visits)',
      checkInsProcessed: filtered.length,
    );
  }

  List<Map<String, dynamic>> _attachTouristProfiles(
    List<Map<String, dynamic>> checkIns,
    Map<String, Map<String, dynamic>> touristById,
  ) {
    return checkIns.map((c) {
      if (c['touristProfile'] is Map) return c;
      final uid = _userIdFromCheckIn(c);
      if (uid == null) return c;
      final profile = touristById[uid];
      if (profile == null) return c;
      return <String, dynamic>{...c, 'touristProfile': profile};
    }).toList();
  }

  void _setCellValue(Sheet sheet, int row, int col, dynamic value) {
    final cell = sheet.cell(
      CellIndex.indexByColumnRow(columnIndex: col, rowIndex: row),
    );
    if (value == null || (value is String && value.isEmpty)) {
      cell.value = null;
      return;
    }
    if (value is int) {
      cell.value = IntCellValue(value);
    } else if (value is num) {
      cell.value = IntCellValue(value.toInt());
    } else {
      cell.value = TextCellValue(value.toString());
    }
  }

  String _monthName(int month) {
    const names = [
      'January',
      'February',
      'March',
      'April',
      'May',
      'June',
      'July',
      'August',
      'September',
      'October',
      'November',
      'December',
    ];
    if (month < 1 || month > 12) return '$month';
    return names[month - 1];
  }

  // --- helpers ---

  Excel _decodeOrEmpty(List<int> bytes) {
    try {
      return Excel.decodeBytes(bytes);
    } catch (_) {
      // Corrupt or unsupported workbook — start fresh but still deliver data.
      return Excel.createExcel();
    }
  }

  void _removeSheetIfExists(Excel excel, String name) {
    if (excel.sheets.containsKey(name)) {
      excel.delete(name);
    }
  }

  void _writeGapsSheet(Sheet sheet, List<String> gaps) {
    _writeHeaderRow(sheet, 0, ['ATMOS field gaps vs official DOT form']);
    _writeHeaderRow(sheet, 1, [
      'See also docs/DOT_REPORT_ATMOS_FIELD_AUDIT.md in the repo',
    ]);
    for (var i = 0; i < gaps.length; i++) {
      _writeRow(sheet, i + 3, ['${i + 1}', gaps[i]]);
    }
  }

  void _writeHeaderRow(Sheet sheet, int row, List<dynamic> values) {
    _writeRow(sheet, row, values);
  }

  void _writeRow(Sheet sheet, int row, List<dynamic> values) {
    for (var c = 0; c < values.length; c++) {
      final v = values[c];
      final cell = sheet.cell(
        CellIndex.indexByColumnRow(columnIndex: c, rowIndex: row),
      );
      if (v == null) continue;
      if (v is int) {
        cell.value = IntCellValue(v);
      } else if (v is num) {
        cell.value = IntCellValue(v.toInt());
      } else {
        cell.value = TextCellValue(v.toString());
      }
    }
  }

  List<Map<String, dynamic>> _checkInsInRange(
    List<Map<String, dynamic>> checkIns,
    DateTime start,
    DateTime end, {
    DateTime? Function(Map<String, dynamic> checkIn)? parseTimestamp,
  }) {
    final startNorm = DateTime(start.year, start.month, start.day);
    final endNorm = DateTime(end.year, end.month, end.day, 23, 59, 59, 999);
    return checkIns.where((c) {
      final t = parseTimestamp?.call(c) ?? parseCheckInTimestampFromMap(c);
      if (t == null) return false;
      return !t.isBefore(startNorm) && !t.isAfter(endNorm);
    }).toList();
  }

  String _monthKeyFromCheckIn(Map<String, dynamic> c) {
    final t = parseCheckInTimestampFromMap(c) ?? DateTime.now();
    return _ym(t);
  }

  Map<String, Map<String, dynamic>> _indexTourists(
    List<Map<String, dynamic>> tourists,
  ) {
    final map = <String, Map<String, dynamic>>{};
    for (final t in tourists) {
      final id = t['id']?.toString() ??
          t['uid']?.toString() ??
          t['userId']?.toString() ??
          t['firebaseUid']?.toString() ??
          '';
      if (id.isNotEmpty) map[id] = t;
      final touristId = t['tourist_id']?.toString() ?? t['touristId']?.toString();
      if (touristId != null && touristId.isNotEmpty) map[touristId] = t;
      final firebaseUid = t['firebaseUid']?.toString();
      if (firebaseUid != null && firebaseUid.isNotEmpty) map[firebaseUid] = t;
    }
    return map;
  }

  String? _userIdFromCheckIn(Map<String, dynamic> c) {
    final uid = c['userId']?.toString() ??
        c['user_id']?.toString() ??
        c['tourist_id']?.toString() ??
        c['touristId']?.toString();
    if (uid == null || uid.trim().isEmpty) return null;
    return uid.trim();
  }

  bool _isDomesticTourist(Map<String, dynamic> t) {
    if (t['isLocal'] == true) return true;
    final localOrForeign = (t['localOrForeign']?.toString() ?? '').toLowerCase();
    if (localOrForeign.contains('local') || localOrForeign.contains('domestic')) {
      return true;
    }
    if (localOrForeign.contains('foreign')) return false;
    final country = (t['country']?.toString() ?? '').toLowerCase();
    if (country.contains('philippin') || country == 'ph' || country == 'phl') {
      return true;
    }
    final nationality = (t['nationality']?.toString() ?? '').toLowerCase();
    if (nationality.contains('filipino') || nationality.contains('philippin')) {
      return true;
    }
    // Unknown — treat as domestic only if explicitly local flags above.
    return false;
  }

  String _domesticOriginLabel(Map<String, dynamic> t) {
    final province = (t['province']?.toString() ?? '').trim();
    final city = (t['city']?.toString() ?? t['municipality']?.toString() ?? '')
        .trim();
    if (province.isNotEmpty && city.isNotEmpty) return '$province / $city';
    if (province.isNotEmpty) return province;
    if (city.isNotEmpty) return city;
    return '';
  }

  List<String> _monthKeysBetween(DateTime start, DateTime end) {
    final keys = <String>[];
    var cursor = DateTime(start.year, start.month, 1);
    final last = DateTime(end.year, end.month, 1);
    while (!cursor.isAfter(last)) {
      keys.add(_ym(cursor));
      cursor = DateTime(cursor.year, cursor.month + 1, 1);
    }
    return keys;
  }

  String _ym(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}';

  String _ymd(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
}

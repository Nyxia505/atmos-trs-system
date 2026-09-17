import 'package:excel/excel.dart';
import 'package:http/http.dart' as http;

import 'package:atmos_trs_system/config/supabase_report_templates_config.dart';
import 'package:atmos_trs_system/utils/checkin_report_summary_csv.dart';
import 'package:atmos_trs_system/utils/dae3_aggregates.dart';
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
  }) async {
    final templateBytes = await fetchTemplateBytes(type.publicUrl);

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
        return _fillDae3FormA(
          templateBytes: templateBytes,
          filtered: enriched,
          touristById: touristById,
          scopeLabel: scopeLabel,
          scopeSlug: scopeSlug,
          startDate: startDate,
          endDate: endDate,
        );
      case DotReportType.dae3b2Domestic:
        return _fillDae3b2Domestic(
          templateBytes: templateBytes,
          filtered: enriched,
          touristById: touristById,
          scopeLabel: scopeLabel,
          scopeSlug: scopeSlug,
          startDate: startDate,
          endDate: endDate,
        );
    }
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
    required Map<String, Map<String, dynamic>> touristById,
    required String scopeLabel,
    required String scopeSlug,
    required DateTime startDate,
    required DateTime endDate,
  }) {
    // Official DAE-3 template is AE monthly record (not country Form A).
    // Fill from check-ins: guests checked-in per spot × month; nights/rooms blank.
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

    // Group: municipality|year|month|spot → count (official AE monthly record).
    final rows = aggregateDae3FromCheckIns(
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
      // Rooms / nights / occupancy not collected — leave blank.
      _setCellValue(sheet, r, 7, null);
      _setCellValue(sheet, r, 8, row.guestsCheckedIn);
      _setCellValue(sheet, r, 9, null);
      _setCellValue(sheet, r, 10, null);
    }

    _removeSheetIfExists(excel, 'ATMOS_GAPS');
    final gaps = excel['ATMOS_GAPS'];
    final gapList = <String>[
      'DAE-3 sheet filled from QR check-ins (Total Guest Checked-In = check-in count).',
      'AE-ID uses tourist spot name as proxy — not accommodation_establishments registry.',
      'Google Form / http(s) spot labels are excluded from AE-ID rows.',
      'Total Rooms, Guest Nights, Rooms Occupied left blank (not collected in ATMOS).',
      'Overnight vs day-trip not collected.',
      'Base file: ${DotReportType.dae3FormA.objectFilename} (Supabase bucket "${SupabaseReportTemplatesConfig.bucket}").',
      if (rows.length > capacity)
        'Overflow: ${rows.length - capacity} spot-month rows omitted (template capacity $capacity).',
    ];
    _writeGapsSheet(gaps, gapList);

    final bytes = excel.encode() ?? templateBytes;
    final filename =
        'dot_dae3_filled_${scopeSlug}_${_ym(startDate)}_to_${_ym(endDate)}.xlsx';

    return DotReportExportResult(
      bytes: bytes,
      filename: filename,
      gaps: gapList,
      summary:
          'DAE-3 filled from ${filtered.length} check-ins (${written.length} rows)',
      checkInsProcessed: filtered.length,
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
    // check-in-filled workbook with the same sheet titles instead.
    final fetchedOfficialBytes = templateBytes.length;
    final byOriginMonth = <String, Map<String, int>>{};
    final bySex = <String, int>{'Male': 0, 'Female': 0, 'Unknown': 0};
    var missingProfile = 0;
    var foreignSkipped = 0;
    var missingOrigin = 0;

    for (final c in filtered) {
      final profile = c['touristProfile'] is Map
          ? Map<String, dynamic>.from(c['touristProfile'] as Map)
          : null;
      final tourist = profile ??
          (() {
            final uid = _userIdFromCheckIn(c);
            return uid == null ? null : touristById[uid];
          })();
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
      final monthKey = _monthKeyFromCheckIn(c);
      byOriginMonth.putIfAbsent(origin, () => <String, int>{});
      byOriginMonth[origin]![monthKey] =
          (byOriginMonth[origin]![monthKey] ?? 0) + 1;

      final sex = (tourist['sex']?.toString() ?? '').trim();
      if (sex.toLowerCase().startsWith('m')) {
        bySex['Male'] = bySex['Male']! + 1;
      } else if (sex.toLowerCase().startsWith('f')) {
        bySex['Female'] = bySex['Female']! + 1;
      } else {
        bySex['Unknown'] = bySex['Unknown']! + 1;
      }
    }

    final months = _monthKeysBetween(startDate, endDate);
    final excel = Excel.createExcel();
    final defaultName = excel.getDefaultSheet()!;
    excel.rename(defaultName, 'DAE3B.2 (Monthly)');
    final sheet = excel['DAE3B.2 (Monthly)'];

    _writeHeaderRow(sheet, 0, ['FORM: DAE 3B.2 Domestic — filled from ATMOS check-ins']);
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
      'Official DAE3B.2 template ($fetchedOfficialBytes bytes) could not be merged '
          'by the Excel library — this file is filled from check-ins with equivalent columns.',
      'Download the blank official template separately if you need the exact DOT layout.',
      'PSA region not collected.',
      'Overnight vs day-trip not collected.',
      'Missing tourist profile: $missingProfile',
      'Foreign profiles skipped: $foreignSkipped',
      'Domestic with empty province/city: $missingOrigin',
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

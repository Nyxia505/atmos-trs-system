import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:atmos_trs_system/config/supabase_report_templates_config.dart';
import 'package:atmos_trs_system/services/lgu_checkin_report_query.dart';
import 'package:atmos_trs_system/utils/dae3_aggregates.dart';
import 'package:atmos_trs_system/utils/dot_report_export_service.dart';
import 'package:atmos_trs_system/utils/dot_var2_visitor_record_report.dart';
import 'package:atmos_trs_system/utils/municipality_helper.dart';

/// Persisted / in-memory status of the current-month DAE-3 draft for an LGU.
class Dae3DraftMeta {
  const Dae3DraftMeta({
    required this.municipalityId,
    required this.year,
    required this.month,
    required this.checkInsInMonth,
    required this.aeRows,
    required this.totalGuests,
    required this.updatedAt,
    this.lastCheckInId,
    this.summary = '',
  });

  final String municipalityId;
  final int year;
  final int month;
  final int checkInsInMonth;
  final int aeRows;
  final int totalGuests;
  final DateTime updatedAt;
  final String? lastCheckInId;
  final String summary;

  String get monthLabel {
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
    final m = month >= 1 && month <= 12 ? names[month - 1] : '$month';
    return '$m $year';
  }

  Map<String, dynamic> toJson() => {
        'municipalityId': municipalityId,
        'year': year,
        'month': month,
        'checkInsInMonth': checkInsInMonth,
        'aeRows': aeRows,
        'totalGuests': totalGuests,
        'updatedAtMs': updatedAt.millisecondsSinceEpoch,
        if (lastCheckInId != null) 'lastCheckInId': lastCheckInId,
        'summary': summary,
      };

  static Dae3DraftMeta? fromJson(Map<String, dynamic>? json) {
    if (json == null) return null;
    final updatedMs = (json['updatedAtMs'] as num?)?.toInt();
    if (updatedMs == null) return null;
    return Dae3DraftMeta(
      municipalityId: json['municipalityId']?.toString() ?? '',
      year: (json['year'] as num?)?.toInt() ?? 0,
      month: (json['month'] as num?)?.toInt() ?? 0,
      checkInsInMonth: (json['checkInsInMonth'] as num?)?.toInt() ?? 0,
      aeRows: (json['aeRows'] as num?)?.toInt() ?? 0,
      totalGuests: (json['totalGuests'] as num?)?.toInt() ?? 0,
      updatedAt: DateTime.fromMillisecondsSinceEpoch(updatedMs),
      lastCheckInId: json['lastCheckInId']?.toString(),
      summary: json['summary']?.toString() ?? '',
    );
  }
}

/// Debounced current-month DAE-3 draft updater for LGU dashboards.
///
/// Check-ins auto-count toward DAE-3; Excel bytes are generated on download from
/// the official Supabase `DAE-3 FORM.xlsx` template + live month data.
class Dae3AutoReportService {
  Dae3AutoReportService._();
  static final Dae3AutoReportService instance = Dae3AutoReportService._();

  final ValueNotifier<Dae3DraftMeta?> draftMeta = ValueNotifier<Dae3DraftMeta?>(null);
  final ValueNotifier<bool> reportJustUpdated = ValueNotifier<bool>(false);

  Timer? _debounce;
  int _refreshGeneration = 0;
  bool _loadedPrefs = false;

  static String _prefsKey(String municipalityId) =>
      'dae3_draft_meta_${normalizeMunicipalityId(municipalityId)}';

  Future<void> ensureLoaded(String? municipalityId) async {
    if (_loadedPrefs) return;
    _loadedPrefs = true;
    final mid = normalizeMunicipalityId(municipalityId);
    if (mid.isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_prefsKey(mid));
    if (raw == null || raw.isEmpty) return;
    try {
      final meta = Dae3DraftMeta.fromJson(
        jsonDecode(raw) as Map<String, dynamic>,
      );
      if (meta == null) return;
      final now = DateTime.now();
      if (meta.municipalityId == mid &&
          meta.year == now.year &&
          meta.month == now.month) {
        draftMeta.value = meta;
      }
    } catch (e) {
      debugPrint('[Dae3AutoReport] load prefs: $e');
    }
  }

  /// Debounce refresh after live check-in stream updates.
  void scheduleRefresh({
    required String? municipalityId,
    required String scopeLabel,
    required String scopeSlug,
    required List<Map<String, dynamic>> localCheckIns,
    required List<Map<String, dynamic>> tourists,
    String? newestCheckInId,
    DateTime? Function(Map<String, dynamic> checkIn)? parseTimestamp,
  }) {
    final mid = normalizeMunicipalityId(municipalityId);
    if (mid.isEmpty) return;

    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 1800), () {
      unawaited(
        refreshDraft(
          municipalityId: mid,
          scopeLabel: scopeLabel,
          scopeSlug: scopeSlug,
          localCheckIns: localCheckIns,
          tourists: tourists,
          newestCheckInId: newestCheckInId,
          parseTimestamp: parseTimestamp,
        ),
      );
    });
  }

  Future<Dae3DraftMeta?> refreshDraft({
    required String municipalityId,
    required String scopeLabel,
    required String scopeSlug,
    required List<Map<String, dynamic>> localCheckIns,
    required List<Map<String, dynamic>> tourists,
    String? newestCheckInId,
    DateTime? Function(Map<String, dynamic> checkIn)? parseTimestamp,
  }) async {
    final mid = normalizeMunicipalityId(municipalityId);
    if (mid.isEmpty) return null;
    final gen = ++_refreshGeneration;

    final now = DateTime.now();
    final start = DateTime(now.year, now.month, 1);
    final end = DateTime(now.year, now.month, now.day, 23, 59, 59, 999);

    final queryIds = municipalityIdsForQuery(mid);
    List<Map<String, dynamic>> monthCheckIns;
    try {
      monthCheckIns = await LguCheckInReportQuery.fetchRange(
        municipalityQueryIds: queryIds,
        start: start,
        end: end,
      );
    } catch (e) {
      debugPrint('[Dae3AutoReport] month fetch failed, using local: $e');
      monthCheckIns = const [];
    }

    // Prefer Firestore month window; fall back / merge local dashboard rows.
    final byId = <String, Map<String, dynamic>>{
      for (final c in monthCheckIns)
        if ((c['id']?.toString() ?? '').isNotEmpty) c['id'].toString(): c,
    };
    for (final c in localCheckIns) {
      final id = c['id']?.toString() ?? '';
      if (id.isEmpty) continue;
      byId.putIfAbsent(id, () => c);
    }

    if (gen != _refreshGeneration) return draftMeta.value;

    final rows = aggregateDae3FromCheckIns(
      checkIns: byId.values.toList(),
      scopeLabel: scopeLabel,
      parseTimestamp: parseTimestamp,
    );
    final monthRows = rows
        .where((r) => r.year == now.year && r.month == now.month)
        .toList();
    final guests = monthRows.fold<int>(0, (s, r) => s + r.guestsCheckedIn);
    final checkInCount = byId.length;

    final meta = Dae3DraftMeta(
      municipalityId: mid,
      year: now.year,
      month: now.month,
      checkInsInMonth: checkInCount,
      aeRows: monthRows.length,
      totalGuests: guests,
      updatedAt: DateTime.now(),
      lastCheckInId: newestCheckInId,
      summary:
          'DAE-3 $scopeSlug ${now.year}-${now.month.toString().padLeft(2, '0')}: '
          '$checkInCount check-ins → ${monthRows.length} AE rows '
          '($guests guests). Template: ${DotReportType.dae3FormA.objectFilename}',
    );

    draftMeta.value = meta;
    reportJustUpdated.value = true;
    await _persist(meta);
    return meta;
  }

  Future<void> _persist(Dae3DraftMeta meta) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefsKey(meta.municipalityId), jsonEncode(meta.toJson()));
    } catch (e) {
      debugPrint('[Dae3AutoReport] persist: $e');
    }
  }

  void clearJustUpdatedFlag() {
    reportJustUpdated.value = false;
  }

  /// Builds filled DAE-3 for the current calendar month from Supabase template + live data.
  Future<DotReportExportResult> generateCurrentMonthExcel({
    required String municipalityId,
    required String scopeLabel,
    required String scopeSlug,
    required List<Map<String, dynamic>> localCheckIns,
    required List<Map<String, dynamic>> tourists,
    required List<DotVar2SpotCatalogEntry> catalogSpots,
    DateTime? Function(Map<String, dynamic> checkIn)? parseTimestamp,
    DotReportExportService? exportService,
  }) async {
    final mid = normalizeMunicipalityId(municipalityId);
    final now = DateTime.now();
    final start = DateTime(now.year, now.month, 1);
    final end = DateTime(now.year, now.month, now.day, 23, 59, 59, 999);

    final queryIds = municipalityIdsForQuery(mid);
    final fetched = await LguCheckInReportQuery.fetchRange(
      municipalityQueryIds: queryIds,
      start: start,
      end: end,
    );
    final byId = <String, Map<String, dynamic>>{
      for (final c in fetched)
        if ((c['id']?.toString() ?? '').isNotEmpty) c['id'].toString(): c,
      for (final c in localCheckIns)
        if ((c['id']?.toString() ?? '').isNotEmpty) c['id'].toString(): c,
    };

    final owns = exportService == null;
    final service = exportService ?? DotReportExportService();
    try {
      final result = await service.exportFilled(
        type: DotReportType.dae3FormA,
        startDate: start,
        endDate: end,
        checkIns: byId.values.toList(),
        tourists: tourists,
        catalogSpots: catalogSpots,
        scopeLabel: scopeLabel,
        scopeSlug: scopeSlug.isEmpty ? mid : scopeSlug,
        parseTimestamp: parseTimestamp,
      );

      final rows = aggregateDae3FromCheckIns(
        checkIns: byId.values.toList(),
        scopeLabel: scopeLabel,
        parseTimestamp: parseTimestamp,
      );
      final monthRows =
          rows.where((r) => r.year == now.year && r.month == now.month);
      final guests =
          monthRows.fold<int>(0, (s, r) => s + r.guestsCheckedIn);
      final meta = Dae3DraftMeta(
        municipalityId: mid,
        year: now.year,
        month: now.month,
        checkInsInMonth: byId.length,
        aeRows: monthRows.length,
        totalGuests: guests,
        updatedAt: DateTime.now(),
        summary: result.summary,
      );
      draftMeta.value = meta;
      await _persist(meta);
      return result;
    } finally {
      if (owns) service.dispose();
    }
  }

  void dispose() {
    _debounce?.cancel();
  }
}

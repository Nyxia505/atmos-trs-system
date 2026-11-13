import 'package:flutter/foundation.dart' show debugPrint;

import 'package:atmos_trs_system/models/ae_register.dart';
import 'package:atmos_trs_system/services/ae_register_service.dart';
import 'package:atmos_trs_system/utils/ae_register_calculator.dart';
import 'package:atmos_trs_system/utils/municipality_helper.dart';

/// Hotel DOT register data (DAE-1B monthly reports) for DAE-family forms.
///
/// DAE forms are monthly: a date range selects every AE-month it overlaps.
class AeRegisterReportData {
  const AeRegisterReportData({
    this.reports = const [],
    this.rowsByReport = const {},
    this.startDate,
    this.endDate,
    this.fetchError,
  });

  static const empty = AeRegisterReportData();

  /// AE-month headers with at least one row or a "no guests" day.
  final List<AeMonthlyReport> reports;

  /// Report id → daily register rows (empty when rows were not fetched).
  final Map<String, List<AeRegisterRow>> rowsByReport;
  final DateTime? startDate;
  final DateTime? endDate;

  /// Set when Firestore fetch failed — never treat as a confirmed empty period.
  final String? fetchError;

  bool get isEmpty => reports.isEmpty && fetchError == null;
  bool get isNotEmpty => reports.isNotEmpty;
  bool get hasRows => rowsByReport.values.any((r) => r.isNotEmpty);
  bool get fetchFailed => fetchError != null && fetchError!.trim().isNotEmpty;

  int get draftCount => reports.where((r) => !r.isSubmitted).length;
  int get demoCount => reports.where((r) => r.isDemo).length;
  int get aeCount => reports.map((r) => r.aeId).toSet().length;

  AeMonthTotals get combined =>
      AeRegisterCalculator.combine(reports.map((r) => r.totals));

  List<AeRegisterRow> rowsFor(AeMonthlyReport r) =>
      rowsByReport[r.id] ?? const [];

  /// True when the range starts / ends mid-month (whole months are still used).
  bool get partialMonths {
    final s = startDate, e = endDate;
    if (s == null || e == null) return false;
    final lastDay = DateTime(e.year, e.month + 1, 0).day;
    return s.day != 1 || e.day != lastDay;
  }

  /// Standard ATMOS_GAPS lines describing the register source.
  List<String> sourceGaps(String formCode) => [
        if (fetchFailed)
          'Could not load hotel DOT registers ($fetchError). Totals are unknown — not zero.',
        if (!fetchFailed)
          '$formCode filled from hotel DOT registers (DAE-1B monthly reports): '
              '${reports.length} AE-month report(s) from $aeCount establishment(s).',
        if (draftCount > 0)
          '$draftCount report(s) still in draft (not yet submitted to LGU) — figures may change.',
        if (demoCount > 0) '$demoCount report(s) contain demo/seed data.',
        if (partialMonths)
          'DAE forms are monthly — the selected range covers whole calendar months '
              '(start and end dates inclusive for month selection).',
      ];
}

/// Inclusive calendar-day filter (time stripped). Used when a form needs only
/// the days inside [start]–[end]; monthly DAE forms still keep full months.
List<AeRegisterRow> filterAeRowsInclusive(
  Iterable<AeRegisterRow> rows,
  DateTime start,
  DateTime end,
) {
  final s = DateTime(start.year, start.month, start.day);
  final e = DateTime(end.year, end.month, end.day);
  return [
    for (final r in rows)
      if (!r.date.isBefore(s) && !r.date.isAfter(e)) r,
  ];
}

/// Fetches AE monthly reports (and optionally daily rows) for DOT export.
///
/// Scope: [aeId] (one establishment) › [municipalityId] (LGU) › province-wide.
Future<AeRegisterReportData> fetchAeRegisterReportData({
  required DateTime startDate,
  required DateTime endDate,
  String? municipalityId,
  String? aeId,
  bool includeRows = false,
}) async {
  final mid = normalizeMunicipalityId(municipalityId ?? '');
  final aid = (aeId ?? '').trim();
  try {
    final listed = await AeRegisterService.listInRange(
      start: startDate,
      end: endDate,
      municipalityId: mid.isEmpty ? null : mid,
      aeId: aid.isEmpty ? null : aid,
    );

    // When rows are requested (or a single AE), verify eligibility from live
    // rows so a stale header with rowCount=0 cannot hide real register data.
    if (includeRows || aid.isNotEmpty) {
      final rowsByReport = <String, List<AeRegisterRow>>{};
      final kept = <AeMonthlyReport>[];
      for (final r in listed) {
        final monthRows = AeRegisterCalculator.rowsInMonth(
          await AeRegisterService.fetchRows(r.aeId, r.year, r.month),
          r.year,
          r.month,
        );
        final hasLive = monthRows.isNotEmpty || r.zeroDays.isNotEmpty;
        final headerSaysData = r.totals.rowCount > 0 || r.zeroDays.isNotEmpty;
        if (!hasLive && !headerSaysData) continue;
        kept.add(r);
        if (includeRows) {
          // DAE monthly forms need the full month; inclusive day filter is
          // available via [filterAeRowsInclusive] for day-scoped consumers.
          rowsByReport[r.id] = monthRows;
        }
      }
      return AeRegisterReportData(
        reports: kept,
        rowsByReport: rowsByReport,
        startDate: startDate,
        endDate: endDate,
      );
    }

    final reports = listed
        .where((r) => r.totals.rowCount > 0 || r.zeroDays.isNotEmpty)
        .toList();
    return AeRegisterReportData(
      reports: reports,
      startDate: startDate,
      endDate: endDate,
    );
  } catch (e, st) {
    debugPrint('[AeRegisterReport] fetch failed: $e\n$st');
    return AeRegisterReportData(
      startDate: startDate,
      endDate: endDate,
      fetchError: e.toString(),
    );
  }
}

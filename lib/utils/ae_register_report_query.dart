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
  });

  static const empty = AeRegisterReportData();

  /// AE-month headers with at least one row or a "no guests" day.
  final List<AeMonthlyReport> reports;

  /// Report id → daily register rows (empty when rows were not fetched).
  final Map<String, List<AeRegisterRow>> rowsByReport;
  final DateTime? startDate;
  final DateTime? endDate;

  bool get isEmpty => reports.isEmpty;
  bool get isNotEmpty => reports.isNotEmpty;
  bool get hasRows => rowsByReport.isNotEmpty;

  int get draftCount => reports.where((r) => !r.isSubmitted).length;
  int get demoCount => reports.where((r) => r.isDemo).length;
  int get aeCount => reports.map((r) => r.aeId).toSet().length;

  AeMonthTotals get combined => AeRegisterCalculator.combine(reports.map((r) => r.totals));

  List<AeRegisterRow> rowsFor(AeMonthlyReport r) => rowsByReport[r.id] ?? const [];

  /// True when the range starts / ends mid-month (whole months are still used).
  bool get partialMonths {
    final s = startDate, e = endDate;
    if (s == null || e == null) return false;
    final lastDay = DateTime(e.year, e.month + 1, 0).day;
    return s.day != 1 || e.day != lastDay;
  }

  /// Standard ATMOS_GAPS lines describing the register source.
  List<String> sourceGaps(String formCode) => [
        '$formCode filled from hotel DOT registers (DAE-1B monthly reports): '
            '${reports.length} AE-month report(s) from $aeCount establishment(s).',
        if (draftCount > 0)
          '$draftCount report(s) still in draft (not yet submitted to LGU) — figures may change.',
        if (demoCount > 0) '$demoCount report(s) contain demo/seed data.',
        if (partialMonths)
          'DAE forms are monthly — the selected range covers whole calendar months.',
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
  final reports = (await AeRegisterService.listInRange(
    start: startDate,
    end: endDate,
    municipalityId: mid.isEmpty ? null : mid,
    aeId: aeId,
  ))
      .where((r) => r.totals.rowCount > 0 || r.zeroDays.isNotEmpty)
      .toList();
  if (!includeRows || reports.isEmpty) {
    return AeRegisterReportData(reports: reports, startDate: startDate, endDate: endDate);
  }
  final rows = <String, List<AeRegisterRow>>{};
  for (final r in reports) {
    rows[r.id] = AeRegisterCalculator.rowsInMonth(
      await AeRegisterService.fetchRows(r.aeId, r.year, r.month),
      r.year,
      r.month,
    );
  }
  return AeRegisterReportData(
    reports: reports,
    rowsByReport: rows,
    startDate: startDate,
    endDate: endDate,
  );
}

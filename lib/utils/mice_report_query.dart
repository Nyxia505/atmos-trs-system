import 'package:atmos_trs_system/config/mice_event_types.dart';
import 'package:atmos_trs_system/models/mice_register.dart';
import 'package:atmos_trs_system/services/mice_register_service.dart';
import 'package:atmos_trs_system/utils/mice_register_calculator.dart';
import 'package:atmos_trs_system/utils/municipality_helper.dart';

/// CUS workbook layout (panel option).
enum CusLayout {
  /// CUS SUMMARY (all venues) + one CUS BY EST sheet per venue.
  summaryAndVenues,
  summaryOnly,
  venuesOnly;

  String get label => switch (this) {
        CusLayout.summaryAndVenues => 'Summary + one sheet per venue',
        CusLayout.summaryOnly => 'Summary only (all venues, one sheet)',
        CusLayout.venuesOnly => 'One sheet per venue only',
      };
}

/// Export options printed on the CUS form (footer names, layout).
class CusExportOptions {
  const CusExportOptions({
    this.layout = CusLayout.summaryAndVenues,
    this.officerName = '',
    this.mayorName = '',
  });

  final CusLayout layout;

  /// "Name of Tourism Officer" footer line (CUS BY EST).
  final String officerName;

  /// "Mayor" footer line (CUS BY EST).
  final String mayorName;
}

/// One venue's events in the export range (one CUS BY EST block).
class MiceVenueBlock {
  const MiceVenueBlock({
    required this.aeId,
    required this.aeName,
    required this.municipality,
    required this.events,
    required this.controlNumbers,
    required this.reports,
  });

  final String aeId;
  final String aeName;
  final String municipality;

  /// Events in CUS order (date, name).
  final List<MiceEvent> events;

  /// Event id → CN (per venue-month, date order — same as the venue sees).
  final Map<String, int> controlNumbers;
  final List<MiceMonthlyReport> reports;

  MiceMonthTotals get totals => MiceRegisterCalculator.totals(events);
  bool get allSubmitted => reports.isNotEmpty && reports.every((r) => r.isSubmitted);
}

/// Venue MICE logs (CUS MICE) for the shared DOT pipeline.
class MiceReportData {
  const MiceReportData({
    this.reports = const [],
    this.eventsByReport = const {},
    this.startDate,
    this.endDate,
    this.includeDrafts = true,
    this.categories = const {},
  });

  static const empty = MiceReportData();

  /// Venue-month headers in range (after the drafts filter).
  final List<MiceMonthlyReport> reports;

  /// Report id → events of that month (CUS order).
  final Map<String, List<MiceEvent>> eventsByReport;
  final DateTime? startDate;
  final DateTime? endDate;
  final bool includeDrafts;

  /// Empty = all categories.
  final Set<MiceCategory> categories;

  bool get isEmpty => reports.isEmpty;
  bool get isNotEmpty => reports.isNotEmpty;

  bool _inRange(MiceEvent e) {
    final s = startDate, en = endDate;
    if (s != null && e.dateStart.isBefore(DateTime(s.year, s.month, s.day))) return false;
    if (en != null && e.dateStart.isAfter(DateTime(en.year, en.month, en.day, 23, 59, 59))) return false;
    return categories.isEmpty || categories.contains(e.category);
  }

  /// Venues with at least one header in range, A–Z.
  List<MiceVenueBlock> get venues {
    final byAe = <String, List<MiceMonthlyReport>>{};
    for (final r in reports) {
      byAe.putIfAbsent(r.aeId, () => []).add(r);
    }
    final out = <MiceVenueBlock>[];
    for (final e in byAe.entries) {
      final reps = e.value;
      final cn = <String, int>{};
      final events = <MiceEvent>[];
      for (final r in reps) {
        final monthEvents = eventsByReport[r.id] ?? const <MiceEvent>[];
        cn.addAll(MiceRegisterCalculator.controlNumbers(monthEvents));
        events.addAll(monthEvents.where(_inRange));
      }
      out.add(MiceVenueBlock(
        aeId: e.key,
        aeName: reps.first.aeName.isEmpty ? e.key : reps.first.aeName,
        municipality: reps.first.municipality,
        events: MiceRegisterCalculator.sorted(events),
        controlNumbers: cn,
        reports: reps,
      ));
    }
    out.sort((a, b) => a.aeName.toLowerCase().compareTo(b.aeName.toLowerCase()));
    return out;
  }

  /// All events in range across venues (CUS SUMMARY order: date, venue).
  List<(MiceVenueBlock, MiceEvent)> get summaryRows {
    final rows = [
      for (final v in venues)
        for (final e in v.events) (v, e),
    ];
    rows.sort((a, b) {
      final c = a.$2.dateStart.compareTo(b.$2.dateStart);
      if (c != 0) return c;
      final n = a.$1.aeName.toLowerCase().compareTo(b.$1.aeName.toLowerCase());
      return n != 0 ? n : (a.$1.controlNumbers[a.$2.id] ?? 0).compareTo(b.$1.controlNumbers[b.$2.id] ?? 0);
    });
    return rows;
  }

  MiceMonthTotals get combined => MiceRegisterCalculator.totals(summaryRows.map((r) => r.$2));

  int get draftCount => reports.where((r) => !r.isSubmitted).length;
  int get nilCount => reports.where((r) => r.isNilReport).length;
  int get demoCount => reports.where((r) => r.isDemo).length;
  int get venueCount => reports.map((r) => r.aeId).toSet().length;

  bool get partialMonths {
    final s = startDate, e = endDate;
    if (s == null || e == null) return false;
    return s.day != 1 || e.day != DateTime(e.year, e.month + 1, 0).day;
  }

  /// "October 2026" or "Oct 2026 – Dec 2026".
  String get periodLabel {
    final s = startDate, e = endDate;
    if (s == null || e == null) return '';
    const m = ['January', 'February', 'March', 'April', 'May', 'June', 'July', 'August', 'September', 'October', 'November', 'December'];
    if (s.year == e.year && s.month == e.month) return '${m[s.month - 1]} ${s.year}';
    return '${m[s.month - 1].substring(0, 3)} ${s.year} – ${m[e.month - 1].substring(0, 3)} ${e.year}';
  }

  /// Standard ATMOS_GAPS lines describing the MICE source.
  List<String> sourceGaps(String formCode) => [
        '$formCode filled from venue MICE event logs: ${reports.length} venue-month report(s) '
            'from $venueCount venue(s), ${combined.events} event(s).',
        if (!includeDrafts) 'Draft months excluded — submitted months only.',
        if (includeDrafts && draftCount > 0)
          '$draftCount venue-month(s) still in draft (not yet submitted to LGU) — figures may change.',
        if (nilCount > 0) '$nilCount venue-month(s) submitted as "no events".',
        if (demoCount > 0) '$demoCount report(s) contain demo/seed data.',
        if (categories.isNotEmpty)
          'Filtered to: ${categories.map((c) => c.label).join(', ')}.',
        if (partialMonths) 'Range starts / ends mid-month — events counted by start date within the range.',
        'CN = control number per venue-month in date order. Multi-day events are one row (date range, total hours).',
        'Foreign-country breakdown is optional on the venue log and not part of the official CUS sheet.',
      ];
}

/// Fetches venue MICE months (and their events) for CUS export.
///
/// Scope: [aeId] (one venue) › [municipalityId] (LGU) › province-wide.
Future<MiceReportData> fetchMiceReportData({
  required DateTime startDate,
  required DateTime endDate,
  String? municipalityId,
  String? aeId,
  bool includeDrafts = true,
  Set<MiceCategory> categories = const {},
}) async {
  final mid = normalizeMunicipalityId(municipalityId ?? '');
  final reports = (await MiceRegisterService.listInRange(
    start: startDate,
    end: endDate,
    municipalityId: mid.isEmpty ? null : mid,
    aeId: aeId,
  ))
      .where((r) => includeDrafts || r.isSubmitted)
      .where((r) => r.totals.events > 0 || r.isSubmitted)
      .toList();
  final events = await MiceRegisterService.fetchEventsForReports(reports.where((r) => r.totals.events > 0));
  return MiceReportData(
    reports: reports,
    eventsByReport: events,
    startDate: startDate,
    endDate: endDate,
    includeDrafts: includeDrafts,
    categories: categories,
  );
}

import 'package:atmos_trs_system/data/misamis_occidental_municipalities.dart';
import 'package:atmos_trs_system/services/governor_firestore_service.dart';
import 'package:atmos_trs_system/utils/checkin_report_summary_csv.dart';

/// Filters check-ins to [start]?[end] inclusive (local calendar day).
List<Map<String, dynamic>> filterCheckInsInDateRange(
  List<Map<String, dynamic>> checkIns,
  DateTime start,
  DateTime end,
) {
  final startNorm = DateTime(start.year, start.month, start.day);
  final endNorm = DateTime(end.year, end.month, end.day, 23, 59, 59, 999);
  return checkIns.where((c) {
    if (isExcludedFromOfficialReports(c)) return false;
    final t = GovernorFirestoreService.parseCheckInTime(c);
    if (t == null) return false;
    return !t.isBefore(startNorm) && !t.isAfter(endNorm);
  }).toList();
}

String formatReportDate(DateTime date) {
  const months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];
  return '${months[date.month - 1]} ${date.day}, ${date.year}';
}

String _municipalityLabelForCheckIn(Map<String, dynamic> c) {
  final mid = c['municipalityId']?.toString().trim() ?? '';
  if (mid.isNotEmpty) {
    for (final m in getMisamisOccidentalMunicipalities()) {
      if (m.id == mid || mid.contains(m.id)) return m.name;
    }
  }
  final mun = c['municipality']?.toString().trim();
  if (mun != null && mun.isNotEmpty) return mun;
  final city = c['city']?.toString().trim();
  if (city != null && city.isNotEmpty) return city;
  return 'Unassigned';
}

/// Text + CSV rows for provincial check-ins grouped by LGU/municipality.
({String textSummary, String csv}) buildMunicipalityCheckInSummary({
  required List<Map<String, dynamic>> checkIns,
}) {
  final counts = <String, int>{};
  final uniqueByMuni = <String, Set<String>>{};

  for (final c in checkIns) {
    final label = _municipalityLabelForCheckIn(c);
    counts[label] = (counts[label] ?? 0) + 1;
    final uid = GovernorFirestoreService.checkInUserId(c);
    if (uid.isNotEmpty) {
      uniqueByMuni.putIfAbsent(label, () => <String>{}).add(uid);
    }
  }

  final sorted = counts.entries.toList()
    ..sort((a, b) => b.value.compareTo(a.value));

  final textBuf = StringBuffer()
    ..writeln('Municipality/City | Check-ins | Unique visitors')
    ..writeln('${'-' * 48}');

  final csvBuf = StringBuffer()
    ..writeln('Municipality/City,Check-ins,Unique visitors');

  var grandTotal = 0;
  final allUsers = <String>{};

  for (final e in sorted) {
    grandTotal += e.value;
    final users = uniqueByMuni[e.key] ?? const <String>{};
    allUsers.addAll(users);
    textBuf.writeln('${e.key} | ${e.value} | ${users.length}');
    csvBuf.writeln('"${e.key.replaceAll('"', '""')}",${e.value},${users.length}');
  }

  textBuf
    ..writeln('${'-' * 48}')
    ..writeln(
      'GRAND TOTAL: $grandTotal check-ins, ${allUsers.length} unique visitors',
    );

  csvBuf.writeln('"GRAND TOTAL",$grandTotal,${allUsers.length}');

  return (textSummary: textBuf.toString(), csv: csvBuf.toString());
}

String buildCheckInsDetailCsv(List<Map<String, dynamic>> rows) {
  final buf = StringBuffer(
    'Timestamp,Spot ID,Spot Name,User ID,Municipality,Municipality ID\n',
  );
  for (final c in rows) {
    final t = GovernorFirestoreService.parseCheckInTime(c);
    final when = t != null ? t.toIso8601String() : '';
    final spotId = c['spotId']?.toString() ?? c['spot_id']?.toString() ?? '';
    final spotName = (c['spot_name']?.toString() ?? '').replaceAll('"', '""');
    final uid = GovernorFirestoreService.checkInUserId(c);
    final mun = _municipalityLabelForCheckIn(c).replaceAll('"', '""');
    final mid = c['municipalityId']?.toString() ?? '';
    buf.write('"$when","$spotId","$spotName","$uid","$mun","$mid"\n');
  }
  return buf.toString();
}

class ProvincialReportBuildResult {
  const ProvincialReportBuildResult({
    required this.reportText,
    this.summaryCsv,
    this.municipalityCsv,
    this.detailCsv,
    required this.checkInsInPeriod,
  });

  final String reportText;
  final String? summaryCsv;
  final String? municipalityCsv;
  final String? detailCsv;
  final int checkInsInPeriod;
}

/// Builds a provincial ATMOS-TRS report for all Misamis Occidental LGUs.
ProvincialReportBuildResult buildProvincialAtmosReport({
  required List<Map<String, dynamic>> allCheckIns,
  required List<Map<String, dynamic>> tourists,
  required List<Map<String, dynamic>> spots,
  required int activeSpots,
  required DateTime startDate,
  required DateTime endDate,
  required String reportType,
  required String period,
}) {
  final filtered = filterCheckInsInDateRange(allCheckIns, startDate, endDate);

  final buf = StringBuffer()
    ..writeln('=== ATMOS-TRS PROVINCIAL REPORT ===')
    ..writeln('Generated: ${DateTime.now()}')
    ..writeln(
      'Scope: Misamis Occidental (all municipalities and cities)',
    )
    ..writeln(
      'Period (check-ins filtered): ${formatReportDate(startDate)} to ${formatReportDate(endDate)}',
    )
    ..writeln('Report type: $reportType')
    ..writeln(
      'Note: Check-in counts include ONLY records in this date range across the province.',
    )
    ..writeln();

  final includeVisits = reportType == 'All Data' ||
      reportType == 'Visits only' ||
      reportType == 'DOT Visitor to Attraction Report' ||
      reportType == 'Summary by Municipality';
  final includeTourists = reportType == 'All Data' ||
      reportType == 'Tourists Only' ||
      reportType == 'DOT Visitor to Attraction Report';
  final includeSpots = reportType == 'All Data' ||
      reportType == 'Tourist Spots Only' ||
      reportType == 'DOT Visitor to Attraction Report';
  final municipalityOnly = reportType == 'Summary by Municipality';

  String? summaryCsv;
  String? municipalityCsv;
  String? detailCsv;

  if (includeVisits || municipalityOnly) {
    buf.writeln('--- CHECK-INS (within period, provincial) ---');
    buf.writeln('Count in period: ${filtered.length}');
    final verified =
        filtered.where((c) => c['status']?.toString() == 'Verified').length;
    final pending =
        filtered.where((c) => c['status']?.toString() == 'Pending').length;
    buf.writeln('Verified (with status field): $verified');
    buf.writeln('Pending (with status field): $pending');
    buf.writeln();

    if (!municipalityOnly) {
      final summary = buildCheckInSummaryReport(
        checkIns: filtered,
        startDate: startDate,
        endDate: endDate,
        period: period,
        parseTimestamp: GovernorFirestoreService.parseCheckInTime,
      );
      buf.writeln('--- SUMMARY BY SPOT (province-wide) ---');
      buf.writeln(summary.textSummary);
      buf.writeln();
      summaryCsv = summary.csv;
    }

    final muniSummary = buildMunicipalityCheckInSummary(checkIns: filtered);
    buf.writeln('--- SUMMARY BY MUNICIPALITY / CITY ---');
    buf.writeln(muniSummary.textSummary);
    buf.writeln();
    municipalityCsv = muniSummary.csv;

    if (!municipalityOnly) {
      if (filtered.isEmpty) {
        buf.writeln('No check-ins in this period.');
        buf.writeln();
      } else {
        buf.writeln('Detail (sorted newest first):');
        final sorted = List<Map<String, dynamic>>.from(filtered);
        sorted.sort((a, b) {
          final ta = GovernorFirestoreService.parseCheckInTime(a);
          final tb = GovernorFirestoreService.parseCheckInTime(b);
          if (ta == null && tb == null) return 0;
          if (ta == null) return 1;
          if (tb == null) return -1;
          return tb.compareTo(ta);
        });
        final limit = sorted.length > 200 ? 200 : sorted.length;
        for (var i = 0; i < limit; i++) {
          final c = sorted[i];
          final t = GovernorFirestoreService.parseCheckInTime(c);
          final when = t != null ? t.toIso8601String() : '?';
          final spotName = c['spot_name']?.toString() ?? '';
          final spotId =
              c['spotId']?.toString() ?? c['spot_id']?.toString() ?? '?';
          final spotLabel = spotName.isNotEmpty ? spotName : spotId;
          final uid = GovernorFirestoreService.checkInUserId(c);
          final muni = _municipalityLabelForCheckIn(c);
          buf.writeln('  $when | $muni | $spotLabel | user=$uid');
        }
        if (sorted.length > limit) {
          buf.writeln('  ... and ${sorted.length - limit} more (see detail CSV)');
        }
        buf.writeln();
      }
      detailCsv = buildCheckInsDetailCsv(filtered);
    }
  }

  if (includeTourists) {
    buf.writeln('--- TOURISTS (provincial registry) ---');
    buf.writeln('Count: ${tourists.length}');
    var visitSum = 0;
    for (final t in tourists) {
      final v = t['visits'] ?? t['totalVisits'];
      if (v is int) {
        visitSum += v;
      } else if (v is num) {
        visitSum += v.toInt();
      }
    }
    buf.writeln('Total visits (profile field): $visitSum');
    buf.writeln();
  }

  if (includeSpots) {
    buf.writeln('--- TOURIST SPOTS (province-wide; not filtered by date) ---');
    buf.writeln('Total spots: ${spots.length}');
    buf.writeln('Active: $activeSpots');
    buf.writeln('Inactive: ${spots.length - activeSpots}');
    buf.writeln();
  }

  if (reportType == 'DOT Visitor to Attraction Report') {
    buf.writeln('--- DOT VISITOR TO ATTRACTION REPORT (provincial) ---');
    buf.writeln(
      'Attraction,Municipality,Total Visits,Unique Visitors,Latest Visit',
    );
    final byAttraction = <String, Map<String, dynamic>>{};
    for (final c in filtered) {
      final spotId = (c['spotId'] ?? c['spot_id'] ?? 'Unknown').toString();
      final spotName = (c['spot_name'] ?? '').toString().trim();
      final key = spotName.isNotEmpty ? spotName : spotId;
      final userId = GovernorFirestoreService.checkInUserId(c);
      final ts = GovernorFirestoreService.parseCheckInTime(c);
      final muni = _municipalityLabelForCheckIn(c);
      final row = byAttraction.putIfAbsent(
        key,
        () => <String, dynamic>{
          'visits': 0,
          'users': <String>{},
          'latest': null,
          'municipality': muni,
        },
      );
      row['visits'] = (row['visits'] as int) + 1;
      if (userId.isNotEmpty) (row['users'] as Set<String>).add(userId);
      final latest = row['latest'] as DateTime?;
      if (ts != null && (latest == null || ts.isAfter(latest))) {
        row['latest'] = ts;
      }
    }
    final sortedRows = byAttraction.entries.toList()
      ..sort((a, b) =>
          (b.value['visits'] as int).compareTo(a.value['visits'] as int));
    for (final e in sortedRows) {
      final visits = e.value['visits'] as int;
      final uniqueUsers = (e.value['users'] as Set<String>).length;
      final latest = e.value['latest'] as DateTime?;
      final muni = e.value['municipality'] as String;
      buf.writeln(
        '${e.key},$muni,$visits,$uniqueUsers,${latest?.toIso8601String() ?? '?'}',
      );
    }
    buf.writeln();
  }

  return ProvincialReportBuildResult(
    reportText: buf.toString(),
    summaryCsv: summaryCsv,
    municipalityCsv: municipalityCsv,
    detailCsv: detailCsv,
    checkInsInPeriod: filtered.length,
  );
}

String provincialReportCsvFilename({
  required String period,
  required DateTime startDate,
  required DateTime endDate,
  required String suffix,
}) {
  final start =
      '${startDate.year}-${startDate.month.toString().padLeft(2, '0')}-${startDate.day.toString().padLeft(2, '0')}';
  final end =
      '${endDate.year}-${endDate.month.toString().padLeft(2, '0')}-${endDate.day.toString().padLeft(2, '0')}';
  return 'misamis_occidental_${suffix}_${period}_${start}_to_$end.csv';
}

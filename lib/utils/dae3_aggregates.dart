import 'package:atmos_trs_system/utils/checkin_report_summary_csv.dart';

/// One DAE-3 data row: AE × municipality × calendar month.
class Dae3AggregateRow {
  const Dae3AggregateRow({
    required this.province,
    required this.municipality,
    required this.year,
    required this.month,
    required this.aeId,
    required this.guestsCheckedIn,
    this.typeClass = '',
  });

  final String province;
  final String municipality;
  final int year;
  final int month;
  final String aeId;
  final String typeClass;
  final int guestsCheckedIn;

  Dae3AggregateRow copyWithGuests(int guests) => Dae3AggregateRow(
        province: province,
        municipality: municipality,
        year: year,
        month: month,
        aeId: aeId,
        typeClass: typeClass,
        guestsCheckedIn: guests,
      );
}

/// Groups check-ins into DAE-3 AE-ID rows (excludes Google Form / URL labels).
List<Dae3AggregateRow> aggregateDae3FromCheckIns({
  required List<Map<String, dynamic>> checkIns,
  required String scopeLabel,
  DateTime? Function(Map<String, dynamic> checkIn)? parseTimestamp,
}) {
  final parse = parseTimestamp ?? parseCheckInTimestampFromMap;
  final groups = <String, Dae3AggregateRow>{};

  for (final c in checkIns) {
    if (isExcludedFromOfficialReports(c)) continue;
    final ts = parse(c);
    if (ts == null) continue;
    final mun = (c['municipality']?.toString().trim().isNotEmpty == true)
        ? c['municipality'].toString().trim()
        : scopeLabel;
    final spot = (c['spot_name']?.toString().trim().isNotEmpty == true)
        ? c['spot_name'].toString().trim()
        : (c['spotId']?.toString().trim().isNotEmpty == true
            ? c['spotId'].toString().trim()
            : (c['spot_id']?.toString().trim().isNotEmpty == true
                ? c['spot_id'].toString().trim()
                : 'Unknown spot'));
    if (isExcludedReportSpotLabel(spot)) continue;

    final key = '$mun|${ts.year}|${ts.month}|$spot';
    final existing = groups[key];
    if (existing == null) {
      groups[key] = Dae3AggregateRow(
        province: 'Misamis Occidental',
        municipality: mun,
        year: ts.year,
        month: ts.month,
        aeId: spot,
        guestsCheckedIn: 1,
      );
    } else {
      groups[key] = existing.copyWithGuests(existing.guestsCheckedIn + 1);
    }
  }

  final rows = groups.values.toList()
    ..sort((a, b) {
      final byMonth = a.year != b.year
          ? a.year.compareTo(b.year)
          : a.month.compareTo(b.month);
      if (byMonth != 0) return byMonth;
      return a.aeId.compareTo(b.aeId);
    });
  return rows;
}

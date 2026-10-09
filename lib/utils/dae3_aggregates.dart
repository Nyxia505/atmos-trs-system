import 'package:atmos_trs_system/models/ae_register.dart';
import 'package:atmos_trs_system/utils/checkin_report_summary_csv.dart';
import 'package:atmos_trs_system/utils/establishment_capability.dart';

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
    this.guestNights,
    this.roomsOccupied,
    this.roomsAvailable,
    this.roomNights,
    this.fromRegister = false,
  });

  final String province;
  final String municipality;
  final int year;
  final int month;
  final String aeId;
  final String typeClass;
  final int guestsCheckedIn;
  final int? guestNights;
  final int? roomsOccupied;
  final int? roomsAvailable;
  /// Occupied room-nights (register rows) — numerator of occupancy.
  final int? roomNights;
  final bool fromRegister;

  /// Room-nights ÷ (rooms available × days in month), when both known.
  double? get occupancyPct {
    final avail = roomsAvailable;
    final rn = roomNights;
    if (avail == null || avail < 1 || rn == null) return null;
    final days = DateTime(year, month + 1, 0).day;
    if (days < 1) return null;
    return (rn / (avail * days) * 100).clamp(0, 100);
  }

  Dae3AggregateRow copyWith({
    int? guestsCheckedIn,
    int? guestNights,
    int? roomsOccupied,
    int? roomsAvailable,
    int? roomNights,
    String? typeClass,
  }) =>
      Dae3AggregateRow(
        province: province,
        municipality: municipality,
        year: year,
        month: month,
        aeId: aeId,
        typeClass: typeClass ?? this.typeClass,
        guestsCheckedIn: guestsCheckedIn ?? this.guestsCheckedIn,
        guestNights: guestNights ?? this.guestNights,
        roomsOccupied: roomsOccupied ?? this.roomsOccupied,
        roomsAvailable: roomsAvailable ?? this.roomsAvailable,
        roomNights: roomNights ?? this.roomNights,
        fromRegister: fromRegister,
      );

  /// Legacy helper used by older call sites.
  Dae3AggregateRow copyWithGuests(int guests) =>
      copyWith(guestsCheckedIn: guests);
}

/// Groups check-ins into DAE-3 AE-ID rows (excludes Google Form / URL labels).
/// Prefer [aggregateDae3FromAeReports] when hotel register data exists.
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
        fromRegister: false,
      );
    } else {
      groups[key] = existing.copyWithGuests(existing.guestsCheckedIn + 1);
    }
  }

  return _sortedRows(groups.values.toList());
}

/// One DAE-3 row per AE-month from hotel DOT registers (DAE-1B monthly reports).
///
/// Guests = check-ins, guest nights = sum of register guests, rooms occupied =
/// register rows (one occupied room per night), rooms available = total rooms.
List<Dae3AggregateRow> aggregateDae3FromAeReports(Iterable<AeMonthlyReport> reports) {
  final rows = <Dae3AggregateRow>[
    for (final r in reports)
      if (r.totals.rowCount > 0 || r.zeroDays.isNotEmpty)
        Dae3AggregateRow(
          province: r.province.isEmpty ? 'Misamis Occidental' : r.province,
          municipality: r.municipality,
          year: r.year,
          month: r.month,
          aeId: r.aeName.isEmpty ? r.aeId : r.aeName,
          typeClass: r.classificationCode.isNotEmpty
              ? r.classificationCode
              : (r.aeType.isNotEmpty ? r.aeType : EstablishmentCapability.typeClassFor(r.category)),
          guestsCheckedIn: r.totals.checkIns,
          guestNights: r.totals.guestNights,
          roomsOccupied: r.totals.roomsOccupied,
          roomsAvailable: r.totalRooms > 0 ? r.totalRooms : null,
          roomNights: r.totals.roomsOccupied,
          fromRegister: true,
        ),
  ];
  return _sortedRows(rows);
}

/// Prefer hotel registers; fall back to labeled attraction/LGU check-in proxy.
List<Dae3AggregateRow> aggregateDae3PreferringRegister({
  required Iterable<AeMonthlyReport> reports,
  required List<Map<String, dynamic>> checkIns,
  required String scopeLabel,
  DateTime? Function(Map<String, dynamic> checkIn)? parseCheckInTimestamp,
}) {
  final fromRegister = aggregateDae3FromAeReports(reports);
  if (fromRegister.isNotEmpty) return fromRegister;
  return aggregateDae3FromCheckIns(
    checkIns: checkIns,
    scopeLabel: scopeLabel,
    parseTimestamp: parseCheckInTimestamp,
  );
}

List<Dae3AggregateRow> _sortedRows(List<Dae3AggregateRow> rows) {
  rows.sort((a, b) {
    final byMonth = a.year != b.year
        ? a.year.compareTo(b.year)
        : a.month.compareTo(b.month);
    if (byMonth != 0) return byMonth;
    return a.aeId.compareTo(b.aeId);
  });
  return rows;
}

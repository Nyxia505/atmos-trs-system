import 'package:atmos_trs_system/utils/checkin_report_summary_csv.dart';
import 'package:atmos_trs_system/utils/establishment_capability.dart';
import 'package:atmos_trs_system/utils/establishment_stay_report_query.dart';

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
    this.fromConfirmedStays = false,
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
  /// Sum of (rooms × nights) — aligns with AE Insights room-nights.
  final int? roomNights;
  final bool fromConfirmedStays;

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
        fromConfirmedStays: fromConfirmedStays,
      );

  /// Legacy helper used by older call sites.
  Dae3AggregateRow copyWithGuests(int guests) =>
      copyWith(guestsCheckedIn: guests);
}

/// Groups check-ins into DAE-3 AE-ID rows (excludes Google Form / URL labels).
/// Prefer [aggregateDae3FromConfirmedStays] when AE stay data exists.
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
        fromConfirmedStays: false,
      );
    } else {
      groups[key] = existing.copyWithGuests(existing.guestsCheckedIn + 1);
    }
  }

  return _sortedRows(groups.values.toList());
}

/// Groups **confirmed** establishment stay events into DAE-3 AE rows.
///
/// Guests use `partySize`; guest-nights = partySize × nights when nights known.
/// [typeClass] and [roomsAvailable] come from the stay / AE registry snapshot.
List<Dae3AggregateRow> aggregateDae3FromConfirmedStays({
  required List<Map<String, dynamic>> stayEvents,
  required String scopeLabel,
  DateTime? Function(Map<String, dynamic> event)? parseTimestamp,
}) {
  final parse = parseTimestamp ?? parseStayEventTimestamp;
  final groups = <String, Dae3AggregateRow>{};

  for (final e in stayEvents) {
    final status = (e['status'] ?? '').toString().toLowerCase();
    if (status.isNotEmpty &&
        status != 'confirmed' &&
        status != 'checked_out') {
      continue;
    }
    final ts = parse(e);
    if (ts == null) continue;

    final mun = (e['municipality']?.toString().trim().isNotEmpty == true)
        ? e['municipality'].toString().trim()
        : scopeLabel;
    final ae = (e['establishmentName']?.toString().trim().isNotEmpty == true)
        ? e['establishmentName'].toString().trim()
        : (e['spot_name']?.toString().trim().isNotEmpty == true
            ? e['spot_name'].toString().trim()
            : 'Unknown AE');

    final guests = _asPositiveInt(e['partySize'], fallback: 1);
    final nights = _asIntOrNull(e['nightsStayed']);
    final rooms = _asIntOrNull(e['roomsOccupied']);
    final guestNights = nights == null ? null : guests * nights;
    final roomNums = e['roomNumbers'];
    final roomCountFromList = roomNums is List
        ? roomNums.where((x) => x.toString().trim().isNotEmpty).length
        : 0;
    final roomsForNights = rooms ?? (roomCountFromList > 0 ? roomCountFromList : null);
    final roomNights = (roomsForNights != null && nights != null)
        ? roomsForNights * nights
        : roomsForNights;
    final typeClass = (e['typeClass']?.toString().trim().isNotEmpty == true)
        ? e['typeClass'].toString().trim()
        : EstablishmentCapability.typeClassFor(
            e['establishmentCategory']?.toString(),
          );
    final roomsAvailable = _asIntOrNull(e['roomsAvailable']);

    final key = '$mun|${ts.year}|${ts.month}|$ae';
    final existing = groups[key];
    if (existing == null) {
      groups[key] = Dae3AggregateRow(
        province: 'Misamis Occidental',
        municipality: mun,
        year: ts.year,
        month: ts.month,
        aeId: ae,
        typeClass: typeClass,
        guestsCheckedIn: guests,
        guestNights: guestNights,
        roomsOccupied: rooms,
        roomsAvailable: roomsAvailable,
        roomNights: roomNights,
        fromConfirmedStays: true,
      );
    } else {
      groups[key] = existing.copyWith(
        guestsCheckedIn: existing.guestsCheckedIn + guests,
        guestNights: _sumNullable(existing.guestNights, guestNights),
        roomsOccupied: _sumNullable(existing.roomsOccupied, rooms),
        // Keep a known inventory snapshot (max if both set).
        roomsAvailable: _maxNullable(existing.roomsAvailable, roomsAvailable),
        roomNights: _sumNullable(existing.roomNights, roomNights),
        typeClass: existing.typeClass.isNotEmpty ? existing.typeClass : typeClass,
      );
    }
  }

  return _sortedRows(groups.values.toList());
}

/// Prefer confirmed stays; fall back to labeled attraction/LGU check-in proxy.
List<Dae3AggregateRow> aggregateDae3PreferringStays({
  required List<Map<String, dynamic>> stayEvents,
  required List<Map<String, dynamic>> checkIns,
  required String scopeLabel,
  DateTime? Function(Map<String, dynamic> checkIn)? parseCheckInTimestamp,
}) {
  final fromStays = aggregateDae3FromConfirmedStays(
    stayEvents: stayEvents,
    scopeLabel: scopeLabel,
  );
  if (fromStays.isNotEmpty) return fromStays;
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

int _asPositiveInt(dynamic v, {int fallback = 1}) {
  final n = _asIntOrNull(v);
  if (n == null || n < 1) return fallback;
  return n;
}

int? _asIntOrNull(dynamic v) {
  if (v == null) return null;
  if (v is int) return v;
  if (v is num) return v.toInt();
  return int.tryParse(v.toString());
}

int? _sumNullable(int? a, int? b) {
  if (a == null && b == null) return null;
  return (a ?? 0) + (b ?? 0);
}

int? _maxNullable(int? a, int? b) {
  if (a == null) return b;
  if (b == null) return a;
  return a > b ? a : b;
}

import 'package:cloud_firestore/cloud_firestore.dart';

/// Philippines has no DST. Reporting periods use this offset from UTC.
const Duration kManilaOffset = Duration(hours: 8);

/// Instant → Asia/Manila wall clock (naive local DateTime with Manila Y-M-D h:m).
DateTime manilaWallClock(DateTime value) {
  final utc = value.isUtc ? value : value.toUtc();
  final shifted = utc.add(kManilaOffset);
  return DateTime(
    shifted.year,
    shifted.month,
    shifted.day,
    shifted.hour,
    shifted.minute,
    shifted.second,
    shifted.millisecond,
  );
}

DateTime manilaCalendarDate(DateTime value) {
  final wall = manilaWallClock(value);
  return DateTime(wall.year, wall.month, wall.day);
}

DateTime manilaNow([DateTime? clock]) {
  return manilaWallClock(clock ?? DateTime.now());
}

/// Treat a naive Y-M-D (and optional time) as Asia/Manila wall clock → UTC instant.
DateTime manilaUtcInstant(DateTime manilaWall) {
  return DateTime.utc(
    manilaWall.year,
    manilaWall.month,
    manilaWall.day,
    manilaWall.hour,
    manilaWall.minute,
    manilaWall.second,
    manilaWall.millisecond,
  ).subtract(kManilaOffset);
}

/// Half-open [startUtc, endExclusiveUtc) reporting window in Asia/Manila.
class ManilaRange {
  const ManilaRange({
    required this.startUtc,
    required this.endExclusiveUtc,
    required this.startDate,
    required this.endDateInclusive,
    required this.label,
  });

  final DateTime startUtc;
  final DateTime endExclusiveUtc;
  final DateTime startDate;
  final DateTime endDateInclusive;
  final String label;

  bool containsInstant(DateTime instant) {
    final utc = instant.isUtc ? instant : instant.toUtc();
    return !utc.isBefore(startUtc) && utc.isBefore(endExclusiveUtc);
  }
}

const _monthShort = [
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

String manilaDayLabel(DateTime day) =>
    '${day.day} ${_monthShort[day.month - 1]} ${day.year}';

ManilaRange manilaThisMonth(DateTime now) {
  final today = manilaCalendarDate(now);
  final start = DateTime(today.year, today.month, 1);
  final next = DateTime(today.year, today.month + 1, 1);
  final last = next.subtract(const Duration(days: 1));
  return ManilaRange(
    startUtc: manilaUtcInstant(start),
    endExclusiveUtc: manilaUtcInstant(next),
    startDate: start,
    endDateInclusive: last,
    label: '1-${last.day} ${_monthShort[today.month - 1]} ${today.year}',
  );
}

ManilaRange manilaThisWeek(DateTime now) {
  final today = manilaCalendarDate(now);
  final start = today.subtract(const Duration(days: 6));
  final tomorrow = today.add(const Duration(days: 1));
  return ManilaRange(
    startUtc: manilaUtcInstant(start),
    endExclusiveUtc: manilaUtcInstant(tomorrow),
    startDate: start,
    endDateInclusive: today,
    label: '${start.day} ${_monthShort[start.month - 1]}-${today.day} ${_monthShort[today.month - 1]} ${today.year}',
  );
}

ManilaRange manilaThisYear(DateTime now) {
  final today = manilaCalendarDate(now);
  final start = DateTime(today.year, today.month - 11, 1);
  final next = DateTime(today.year, today.month + 1, 1);
  final last = next.subtract(const Duration(days: 1));
  return ManilaRange(
    startUtc: manilaUtcInstant(start),
    endExclusiveUtc: manilaUtcInstant(next),
    startDate: start,
    endDateInclusive: last,
    label:
        '${_monthShort[start.month - 1]} ${start.year}-${_monthShort[today.month - 1]} ${today.year}',
  );
}

ManilaRange manilaRangeForFilter(String range, DateTime now) {
  switch (range) {
    case 'This Year':
      return manilaThisYear(now);
    case 'This Week':
      return manilaThisWeek(now);
    case 'This Month':
    default:
      return manilaThisMonth(now);
  }
}

/// Half-open window immediately before [manilaRangeForFilter].
ManilaRange manilaPreviousRangeForFilter(String range, DateTime now) {
  final current = manilaRangeForFilter(range, now);
  switch (range) {
    case 'This Year':
      final start =
          DateTime(current.startDate.year, current.startDate.month - 12, 1);
      final last = current.startDate.subtract(const Duration(days: 1));
      return ManilaRange(
        startUtc: manilaUtcInstant(start),
        endExclusiveUtc: current.startUtc,
        startDate: start,
        endDateInclusive: last,
        label: 'prior 12 months',
      );
    case 'This Week':
      final start = current.startDate.subtract(const Duration(days: 7));
      final last = current.startDate.subtract(const Duration(days: 1));
      return ManilaRange(
        startUtc: manilaUtcInstant(start),
        endExclusiveUtc: current.startUtc,
        startDate: start,
        endDateInclusive: last,
        label: 'prior 7 days',
      );
    case 'This Month':
    default:
      final start =
          DateTime(current.startDate.year, current.startDate.month - 1, 1);
      final last = current.startDate.subtract(const Duration(days: 1));
      return ManilaRange(
        startUtc: manilaUtcInstant(start),
        endExclusiveUtc: current.startUtc,
        startDate: start,
        endDateInclusive: last,
        label: 'prior month',
      );
  }
}

bool checkInInManilaRange(
  Map<String, dynamic> checkIn,
  ManilaRange range, {
  DateTime? Function(Map<String, dynamic>)? parseTime,
}) {
  final when = (parseTime ?? parseCheckInTimestamp)(checkIn);
  if (when == null) return false;
  return range.containsInstant(when);
}

List<Map<String, dynamic>> checkInsInManilaFilter(
  List<Map<String, dynamic>> checkIns,
  String filter, {
  DateTime? now,
  DateTime? Function(Map<String, dynamic>)? parseTime,
}) {
  final range = manilaRangeForFilter(filter, now ?? DateTime.now());
  return [
    for (final checkIn in checkIns)
      if (checkInInManilaRange(checkIn, range, parseTime: parseTime)) checkIn,
  ];
}

/// Visit/check-in instant from a QR check-in row.
///
/// Accepts Firestore [Timestamp], [DateTime], epoch ints, ISO strings, and
/// REST/map encodings. Does not use tourist registration dates.
DateTime? parseCheckInTimestamp(Map<String, dynamic> checkIn) {
  const keys = [
    'timestamp',
    'checkin_time',
    'checkedInAt',
    'checked_in_at',
    'checkInAt',
    'checkinAt',
    'scannedAt',
    'visitDate',
    'visitedAt',
    'createdAt',
    'created_at',
    'date',
  ];
  for (final key in keys) {
    final parsed = parseCheckInTimestampValue(checkIn[key]);
    if (parsed != null) return parsed;
  }
  return null;
}

DateTime? parseCheckInTimestampValue(Object? raw) {
  if (raw == null) return null;
  if (raw is DateTime) return raw;
  if (raw is Timestamp) return raw.toDate();
  if (raw is int) {
    return DateTime.fromMillisecondsSinceEpoch(
      raw > 9999999999 ? raw : raw * 1000,
      isUtc: true,
    );
  }
  if (raw is double) {
    return parseCheckInTimestampValue(raw.round());
  }
  if (raw is Map) {
    final seconds = raw['seconds'] ??
        raw['_seconds'] ??
        raw['secondsSinceEpoch'] ??
        raw['se'];
    if (seconds is num) {
      final nanos = raw['nanoseconds'] ?? raw['_nanoseconds'] ?? 0;
      final ns = nanos is num ? nanos.round() : 0;
      return DateTime.fromMillisecondsSinceEpoch(
        seconds.round() * 1000 + ns ~/ 1000000,
        isUtc: true,
      );
    }
  }
  try {
    final seconds = (raw as dynamic).seconds;
    if (seconds is int) {
      final nanos = (raw as dynamic).nanoseconds;
      final ns = nanos is int ? nanos : 0;
      return DateTime.fromMillisecondsSinceEpoch(
        seconds * 1000 + ns ~/ 1000000,
        isUtc: true,
      );
    }
  } catch (_) {}

  final text = raw.toString().trim();
  if (text.isEmpty || text == 'null') return null;
  final iso = DateTime.tryParse(text);
  if (iso != null) return iso;
  final timestampMatch = RegExp(
    r'seconds[=:]?\s*(-?\d+).*nanoseconds[=:]?\s*(-?\d+)',
    caseSensitive: false,
  ).firstMatch(text);
  if (timestampMatch != null) {
    final seconds = int.tryParse(timestampMatch.group(1) ?? '');
    final nanos = int.tryParse(timestampMatch.group(2) ?? '') ?? 0;
    if (seconds != null) {
      return DateTime.fromMillisecondsSinceEpoch(
        seconds * 1000 + nanos ~/ 1000000,
        isUtc: true,
      );
    }
  }
  return null;
}

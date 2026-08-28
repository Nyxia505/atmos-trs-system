import 'package:cloud_firestore/cloud_firestore.dart';

typedef CheckInTimestampParser = DateTime? Function(
  Map<String, dynamic> checkIn,
);

/// Layout for time-bucketed check-in summary exports.
enum CheckInSummaryLayoutKind {
  daily,
  weekly,
  monthlyDays,
  annualMonths,
  rangedMonths,
}

class CheckInSummaryLayout {
  const CheckInSummaryLayout({
    required this.kind,
    required this.columnHeaders,
    required this.bucketIndex,
    this.rangeStart,
    this.rangeEnd,
  });

  final CheckInSummaryLayoutKind kind;
  final List<String> columnHeaders;
  final int Function(DateTime timestamp) bucketIndex;
  final DateTime? rangeStart;
  final DateTime? rangeEnd;
}

class CheckInSummaryBuildResult {
  const CheckInSummaryBuildResult({
    required this.csv,
    required this.textSummary,
    required this.layoutKind,
    required this.columnHeaders,
    required this.grandTotalCheckIns,
  });

  final String csv;
  final String textSummary;
  final CheckInSummaryLayoutKind layoutKind;
  final List<String> columnHeaders;
  final int grandTotalCheckIns;
}

const _monthNames = [
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

DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

DateTime? parseCheckInTimestampFromMap(Map<String, dynamic> c) {
  final ts = c['timestamp'] ?? c['checkin_time'];
  if (ts is Timestamp) return ts.toDate();
  if (ts is DateTime) return ts;
  return null;
}

/// Resolves export layout from quick-report period or custom date range.
CheckInSummaryLayout resolveCheckInSummaryLayout({
  required String period,
  required DateTime startDate,
  required DateTime endDate,
}) {
  final start = _dateOnly(startDate);
  final end = _dateOnly(endDate);

  switch (period) {
    case 'daily':
      return const CheckInSummaryLayout(
        kind: CheckInSummaryLayoutKind.daily,
        columnHeaders: ['Check-ins', 'Unique visitors'],
        bucketIndex: _dailyBucketUnused,
      );
    case 'weekly':
      return _weeklyLayout(start, end);
    case 'monthly':
      return _monthlyDaysLayout(start, end);
    case 'annual':
      return _annualMonthsLayout(start.year);
    default:
      final spanDays = end.difference(start).inDays;
      if (spanDays == 0) {
        return const CheckInSummaryLayout(
          kind: CheckInSummaryLayoutKind.daily,
          columnHeaders: ['Check-ins', 'Unique visitors'],
          bucketIndex: _dailyBucketUnused,
        );
      }
      if (spanDays <= 6) {
        return _weeklyLayout(start, end);
      }
      if (start.year == end.year && start.month == end.month) {
        return _monthlyDaysLayout(start, end);
      }
      return _rangedMonthsLayout(start, end);
  }
}

int _dailyBucketUnused(DateTime _) => 0;

CheckInSummaryLayout _weeklyLayout(DateTime start, DateTime end) {
  final days = <DateTime>[];
  var cursor = start;
  while (!cursor.isAfter(end)) {
    days.add(cursor);
    cursor = cursor.add(const Duration(days: 1));
  }
  final headers = days
      .map((d) => '${_monthNames[d.month - 1].substring(0, 3)} ${d.day}')
      .toList();
  return CheckInSummaryLayout(
    kind: CheckInSummaryLayoutKind.weekly,
    columnHeaders: headers,
    rangeStart: start,
    rangeEnd: end,
    bucketIndex: (DateTime ts) {
      final day = _dateOnly(ts);
      for (var i = 0; i < days.length; i++) {
        if (days[i] == day) return i;
      }
      return -1;
    },
  );
}

CheckInSummaryLayout _monthlyDaysLayout(DateTime start, DateTime end) {
  final days = <DateTime>[];
  var cursor = start;
  while (!cursor.isAfter(end)) {
    days.add(cursor);
    cursor = cursor.add(const Duration(days: 1));
  }
  final headers = days.map((d) => '${d.day}').toList();
  return CheckInSummaryLayout(
    kind: CheckInSummaryLayoutKind.monthlyDays,
    columnHeaders: headers,
    rangeStart: start,
    rangeEnd: end,
    bucketIndex: (DateTime ts) {
      final day = _dateOnly(ts);
      for (var i = 0; i < days.length; i++) {
        if (days[i] == day) return i;
      }
      return -1;
    },
  );
}

CheckInSummaryLayout _annualMonthsLayout(int year) {
  return CheckInSummaryLayout(
    kind: CheckInSummaryLayoutKind.annualMonths,
    columnHeaders: List<String>.from(_monthNames),
    bucketIndex: (DateTime ts) {
      if (ts.year != year) return -1;
      return ts.month - 1;
    },
  );
}

CheckInSummaryLayout _rangedMonthsLayout(DateTime start, DateTime end) {
  final headers = <String>[];
  var y = start.year;
  var m = start.month;
  while (y < end.year || (y == end.year && m <= end.month)) {
    headers.add('${_monthNames[m - 1]} $y');
    m++;
    if (m > 12) {
      m = 1;
      y++;
    }
  }
  return CheckInSummaryLayout(
    kind: CheckInSummaryLayoutKind.rangedMonths,
    columnHeaders: headers,
    rangeStart: start,
    rangeEnd: end,
    bucketIndex: (DateTime ts) {
      final t = _dateOnly(ts);
      if (t.isBefore(start) || t.isAfter(end)) return -1;
      var idx = 0;
      var yy = start.year;
      var mm = start.month;
      while (yy < t.year || (yy == t.year && mm < t.month)) {
        idx++;
        mm++;
        if (mm > 12) {
          mm = 1;
          yy++;
        }
      }
      return idx;
    },
  );
}

class _SpotAggregate {
  _SpotAggregate({
    required this.spotId,
    required this.spotName,
    required this.municipality,
    required this.bucketCount,
  });

  final String spotId;
  final String spotName;
  final String municipality;
  final List<int> bucketCount;
  final Set<String> uniqueUserIds = {};
}

String _csvCell(String value) => '"${value.replaceAll('"', '""')}"';

String _spotKey(Map<String, dynamic> c) {
  final spotId =
      c['spotId']?.toString().trim() ?? c['spot_id']?.toString().trim() ?? '';
  final spotName = c['spot_name']?.toString().trim() ?? '';
  if (spotId.isNotEmpty) return spotId;
  if (spotName.isNotEmpty) return spotName;
  return 'unknown';
}

CheckInSummaryBuildResult buildCheckInSummaryReport({
  required List<Map<String, dynamic>> checkIns,
  required DateTime startDate,
  required DateTime endDate,
  required String period,
  CheckInTimestampParser? parseTimestamp,
}) {
  final parse = parseTimestamp ?? parseCheckInTimestampFromMap;
  final layout = resolveCheckInSummaryLayout(
    period: period,
    startDate: startDate,
    endDate: endDate,
  );
  final isDaily = layout.kind == CheckInSummaryLayoutKind.daily;
  final bucketCount = isDaily ? 1 : layout.columnHeaders.length;

  final bySpot = <String, _SpotAggregate>{};

  for (final c in checkIns) {
    final ts = parse(c);
    if (ts == null) continue;

    final key = _spotKey(c);
    final spotId =
        c['spotId']?.toString().trim() ??
        c['spot_id']?.toString().trim() ??
        key;
    final spotName = c['spot_name']?.toString().trim() ?? spotId;
    final municipality = c['municipality']?.toString().trim() ?? '';
    final uid =
        c['userId']?.toString().trim() ??
        c['tourist_id']?.toString().trim() ??
        c['user_id']?.toString().trim() ??
        '';

    final agg = bySpot.putIfAbsent(
      key,
      () => _SpotAggregate(
        spotId: spotId,
        spotName: spotName,
        municipality: municipality,
        bucketCount: List<int>.filled(bucketCount, 0),
      ),
    );

    if (uid.isNotEmpty) agg.uniqueUserIds.add(uid);

    if (isDaily) {
      agg.bucketCount[0]++;
    } else {
      final idx = layout.bucketIndex(ts);
      if (idx >= 0 && idx < bucketCount) {
        agg.bucketCount[idx]++;
      }
    }
  }

  final sortedSpots = bySpot.values.toList()
    ..sort((a, b) {
      final totalA = a.bucketCount.fold<int>(0, (s, n) => s + n);
      final totalB = b.bucketCount.fold<int>(0, (s, n) => s + n);
      final byTotal = totalB.compareTo(totalA);
      if (byTotal != 0) return byTotal;
      return a.spotName.compareTo(b.spotName);
    });

  final columnTotals = List<int>.filled(bucketCount, 0);
  var grandTotal = 0;
  final allUniqueUsers = <String>{};

  final csvBuf = StringBuffer();
  final textBuf = StringBuffer();

  if (isDaily) {
    csvBuf.writeln(
      'Spot ID,Spot Name,Municipality,Check-ins,Unique visitors',
    );
    textBuf.writeln('Spot | Check-ins | Unique visitors');
    textBuf.writeln('${'-' * 40}');
  } else {
    csvBuf.write('Spot ID,Spot Name,Municipality');
    for (final h in layout.columnHeaders) {
      csvBuf.write(',${_csvCell(h)}');
    }
    csvBuf.writeln(',TOTAL');
  }

  for (final spot in sortedSpots) {
    final rowTotal = spot.bucketCount.fold<int>(0, (s, n) => s + n);
    grandTotal += rowTotal;
    allUniqueUsers.addAll(spot.uniqueUserIds);

    if (isDaily) {
      csvBuf.writeln(
        '${_csvCell(spot.spotId)},${_csvCell(spot.spotName)},'
        '${_csvCell(spot.municipality)},$rowTotal,${spot.uniqueUserIds.length}',
      );
      textBuf.writeln(
        '${spot.spotName} | $rowTotal | ${spot.uniqueUserIds.length}',
      );
      columnTotals[0] += rowTotal;
    } else {
      csvBuf.write(
        '${_csvCell(spot.spotId)},${_csvCell(spot.spotName)},'
        '${_csvCell(spot.municipality)}',
      );
      for (var i = 0; i < bucketCount; i++) {
        csvBuf.write(',${spot.bucketCount[i]}');
        columnTotals[i] += spot.bucketCount[i];
      }
      csvBuf.writeln(',$rowTotal');
      textBuf.writeln('${spot.spotName}: $rowTotal total');
    }
  }

  if (isDaily) {
    csvBuf.writeln(
      'GRAND TOTAL,,,$grandTotal,${allUniqueUsers.length}',
    );
    textBuf.writeln('${'-' * 40}');
    textBuf.writeln(
      'GRAND TOTAL: $grandTotal check-ins, '
      '${allUniqueUsers.length} unique visitors',
    );
  } else {
    csvBuf.write('GRAND TOTAL,,');
    for (final t in columnTotals) {
      csvBuf.write(',$t');
    }
    csvBuf.writeln(',$grandTotal');
    textBuf.writeln('${'-' * 40}');
    textBuf.writeln('GRAND TOTAL: $grandTotal check-ins');
  }

  return CheckInSummaryBuildResult(
    csv: csvBuf.toString(),
    textSummary: textBuf.toString(),
    layoutKind: layout.kind,
    columnHeaders: layout.columnHeaders,
    grandTotalCheckIns: grandTotal,
  );
}

String checkInSummaryCsvFilename({
  required String period,
  required DateTime startDate,
  required DateTime endDate,
}) {
  String fmt(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
  final p = period == 'custom' ? 'custom' : period;
  return 'checkins_summary_${p}_${fmt(startDate)}_to_${fmt(endDate)}.csv';
}

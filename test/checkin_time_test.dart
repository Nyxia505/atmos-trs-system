import 'package:atmos_trs_system/utils/checkin_time.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Manila calendar date keeps late-evening visits on the same local day', () {
    final visit = DateTime.utc(2026, 10, 31, 16, 30);
    expect(manilaCalendarDate(visit), DateTime(2026, 11, 1));
    expect(manilaCalendarDate(DateTime.utc(2026, 10, 31, 15, 59)), DateTime(2026, 10, 31));
  });

  test('parses ISO, epoch, and REST timestamp maps', () {
    expect(
      parseCheckInTimestamp({'timestamp': '2026-11-01T02:00:00.000Z'}),
      DateTime.parse('2026-11-01T02:00:00.000Z'),
    );
    final epoch = DateTime.utc(2026, 11, 1, 2).millisecondsSinceEpoch;
    expect(
      parseCheckInTimestamp({'checkin_time': epoch ~/ 1000}),
      DateTime.fromMillisecondsSinceEpoch(epoch, isUtc: true),
    );
    final fromMap = parseCheckInTimestamp({
      'createdAt': {'_seconds': epoch ~/ 1000, '_nanoseconds': 0},
    });
    expect(fromMap, DateTime.fromMillisecondsSinceEpoch(epoch, isUtc: true));
  });

  test('This Month is a half-open Manila window that keeps the 1st and last day', () {
    final range = manilaThisMonth(DateTime.utc(2026, 11, 1, 12));
    expect(range.startDate, DateTime(2026, 11, 1));
    expect(range.endDateInclusive, DateTime(2026, 11, 30));
    expect(range.containsInstant(DateTime.utc(2026, 10, 31, 16)), isTrue); // 1 Nov 00:00
    expect(range.containsInstant(DateTime.utc(2026, 10, 31, 15, 59)), isFalse);
    expect(range.containsInstant(DateTime.utc(2026, 11, 30, 15, 59)), isTrue); // 30 Nov 23:59
    expect(range.containsInstant(DateTime.utc(2026, 11, 30, 16)), isFalse); // 1 Dec 00:00
  });
}

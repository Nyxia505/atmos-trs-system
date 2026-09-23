import 'package:flutter/material.dart';

/// Standard lodging check-in / check-out clock times (`HH:mm` on AE profile).
abstract final class EstablishmentLodgingHours {
  static const defaultCheckIn = '14:00';
  static const defaultCheckOut = '12:00';

  static TimeOfDay? tryParse(String? raw) {
    final s = (raw ?? '').trim();
    if (s.isEmpty) return null;
    final parts = s.split(':');
    if (parts.length < 2) return null;
    final h = int.tryParse(parts[0].trim());
    final m = int.tryParse(parts[1].trim());
    if (h == null || m == null) return null;
    if (h < 0 || h > 23 || m < 0 || m > 59) return null;
    return TimeOfDay(hour: h, minute: m);
  }

  static String format(TimeOfDay t) {
    final h = t.hour.toString().padLeft(2, '0');
    final m = t.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }

  static String displayLabel(TimeOfDay t) {
    final h24 = t.hour;
    final period = h24 >= 12 ? 'PM' : 'AM';
    var h12 = h24 % 12;
    if (h12 == 0) h12 = 12;
    final m = t.minute.toString().padLeft(2, '0');
    return '$h12:$m $period';
  }

  static int minutesSinceMidnight(TimeOfDay t) => t.hour * 60 + t.minute;

  /// True when [now]'s clock is strictly before the AE's standard check-in time.
  static bool isEarlyArrival({
    required DateTime now,
    required String? checkInTime,
  }) {
    final cin = tryParse(checkInTime);
    if (cin == null) return false;
    final nowTod = TimeOfDay(hour: now.hour, minute: now.minute);
    return minutesSinceMidnight(nowTod) < minutesSinceMidnight(cin);
  }

  /// Default nights: early arrival before check-in ⇒ at least 2.
  static int defaultNightsForArrival({
    required DateTime now,
    required String? checkInTime,
    int baseNights = 1,
  }) {
    final base = baseNights < 1 ? 1 : baseNights;
    if (isEarlyArrival(now: now, checkInTime: checkInTime)) {
      return base < 2 ? 2 : base;
    }
    return base;
  }

  /// Planned checkout = check-in calendar day + [nights], at AE check-out clock.
  static DateTime plannedCheckOutAt({
    required DateTime checkInAt,
    required int nights,
    required String? checkOutTime,
  }) {
    final n = nights < 1 ? 0 : nights;
    final day = DateTime(checkInAt.year, checkInAt.month, checkInAt.day)
        .add(Duration(days: n));
    final cout = tryParse(checkOutTime) ?? tryParse(defaultCheckOut)!;
    return DateTime(day.year, day.month, day.day, cout.hour, cout.minute);
  }
}

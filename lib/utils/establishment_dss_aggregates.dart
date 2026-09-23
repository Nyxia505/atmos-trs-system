import 'package:atmos_trs_system/models/establishment_stay_review.dart';
import 'package:atmos_trs_system/services/establishment_stay_service.dart';

/// Pure DSS aggregates from establishment stay / review lists (no I/O).
abstract final class EstablishmentDssAggregates {
  static DateTime? stayDay(EstablishmentStayRequest s) {
    final d = s.confirmedAt ?? s.checkInAt ?? s.createdAt;
    if (d == null) return null;
    return DateTime(d.year, d.month, d.day);
  }

  /// Confirmed stays per day for the last [days] calendar days (oldest → newest).
  static List<int> staysByDay(
    List<EstablishmentStayRequest> all, {
    int days = 14,
  }) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final start = today.subtract(Duration(days: days - 1));
    final counts = List<int>.filled(days, 0);
    for (final s in all) {
      if (!s.countsForDae) continue;
      final day = stayDay(s);
      if (day == null) continue;
      if (day.isBefore(start) || day.isAfter(today)) continue;
      final idx = day.difference(start).inDays;
      if (idx >= 0 && idx < days) counts[idx]++;
    }
    return counts;
  }

  /// Short weekday labels aligned with [staysByDay] (length = days).
  static List<String> dayLabels({int days = 14}) {
    const names = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final start = today.subtract(Duration(days: days - 1));
    return List.generate(days, (i) {
      final d = start.add(Duration(days: i));
      return names[(d.weekday - 1) % 7];
    });
  }

  /// Guests by weekday (Mon=0 … Sun=6) for confirmed stays this month.
  static List<int> guestsByWeekdayThisMonth(List<EstablishmentStayRequest> all) {
    final now = DateTime.now();
    final counts = List<int>.filled(7, 0);
    for (final s in all) {
      if (!s.countsForDae) continue;
      final day = stayDay(s);
      if (day == null) continue;
      if (day.year != now.year || day.month != now.month) continue;
      counts[day.weekday - 1] += s.partySize;
    }
    return counts;
  }

  static Set<int> confirmedDaysThisMonth(List<EstablishmentStayRequest> all) {
    final now = DateTime.now();
    final days = <int>{};
    for (final s in all) {
      if (!s.countsForDae) continue;
      final day = stayDay(s);
      if (day == null) continue;
      if (day.year == now.year && day.month == now.month) {
        days.add(day.day);
      }
    }
    return days;
  }

  /// Sex + residency totals for confirmed stays in the current month.
  static EstablishmentDssDemographics demographicsThisMonth(
    List<EstablishmentStayRequest> all,
  ) {
    var male = 0;
    var female = 0;
    var filipino = 0;
    var foreign = 0;
    var parties = 0;
    var guests = 0;
    final now = DateTime.now();
    final monthStart = DateTime(now.year, now.month, 1);

    for (final s in all) {
      if (!s.countsForDae) continue;
      final day = stayDay(s);
      if (day == null || day.isBefore(monthStart)) continue;
      male += s.maleCount;
      female += s.femaleCount;
      filipino += s.filipinoCount;
      foreign += s.foreignCount;
      parties++;
      guests += s.partySize;
    }

    return EstablishmentDssDemographics(
      male: male,
      female: female,
      filipino: filipino,
      foreign: foreign,
      parties: parties,
      guests: guests,
    );
  }

  /// Star buckets 1–5 from average (hotel+room)/2 per review.
  static List<int> reviewStarBuckets(List<EstablishmentStayReview> reviews) {
    final buckets = List<int>.filled(5, 0);
    for (final r in reviews) {
      final avg = r.averageRating.round().clamp(1, 5);
      buckets[avg - 1]++;
    }
    return buckets;
  }

  static EstablishmentDssSnapshot build(
    List<EstablishmentStayRequest> all, {
    int trendDays = 14,
  }) {
    return EstablishmentDssSnapshot(
      staysTrend: staysByDay(all, days: trendDays),
      staysTrend7: staysByDay(all, days: 7),
      dayLabels: dayLabels(days: trendDays),
      dayLabels7: dayLabels(days: 7),
      weekdayGuests: guestsByWeekdayThisMonth(all),
      calendarDays: confirmedDaysThisMonth(all),
      demographics: demographicsThisMonth(all),
    );
  }
}

class EstablishmentDssDemographics {
  const EstablishmentDssDemographics({
    required this.male,
    required this.female,
    required this.filipino,
    required this.foreign,
    required this.parties,
    required this.guests,
  });

  final int male;
  final int female;
  final int filipino;
  final int foreign;
  final int parties;
  final int guests;

  double get avgParty => parties == 0 ? 0 : guests / parties;

  bool get hasSexData => male + female > 0;
  bool get hasResidencyData => filipino + foreign > 0;
}

class EstablishmentDssSnapshot {
  const EstablishmentDssSnapshot({
    required this.staysTrend,
    required this.staysTrend7,
    required this.dayLabels,
    required this.dayLabels7,
    required this.weekdayGuests,
    required this.calendarDays,
    required this.demographics,
  });

  final List<int> staysTrend;
  final List<int> staysTrend7;
  final List<String> dayLabels;
  final List<String> dayLabels7;
  final List<int> weekdayGuests;
  final Set<int> calendarDays;
  final EstablishmentDssDemographics demographics;
}

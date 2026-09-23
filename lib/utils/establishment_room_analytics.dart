import 'package:atmos_trs_system/models/establishment_stay_review.dart';
import 'package:atmos_trs_system/services/establishment_stay_service.dart';
import 'package:atmos_trs_system/utils/establishment_dss_aggregates.dart';
import 'package:atmos_trs_system/utils/establishment_room_grid.dart';

/// Insights timeframe for lodging room analytics.
enum EstablishmentInsightsWindow {
  days7,
  days30,
  thisMonth,
}

extension EstablishmentInsightsWindowX on EstablishmentInsightsWindow {
  String get label {
    switch (this) {
      case EstablishmentInsightsWindow.days7:
        return '7 days';
      case EstablishmentInsightsWindow.days30:
        return '30 days';
      case EstablishmentInsightsWindow.thisMonth:
        return 'This month';
    }
  }

  String get shortLabel {
    switch (this) {
      case EstablishmentInsightsWindow.days7:
        return '7d';
      case EstablishmentInsightsWindow.days30:
        return '30d';
      case EstablishmentInsightsWindow.thisMonth:
        return 'Month';
    }
  }
}

/// How much room DSS advice to show.
enum EstablishmentRoomDssLevel {
  /// Not enough history — hide recommendations.
  locked,

  /// Soft heuristics (≥ ~1 week).
  soft,

  /// Fuller heuristics (≥ ~1 month of activity).
  full,
}

class EstablishmentRoomUsageRow {
  const EstablishmentRoomUsageRow({
    required this.roomId,
    required this.label,
    required this.roomNights,
    required this.stayCount,
    this.lastUsed,
    this.info = EstablishmentRoomInfo.empty,
  });

  final String roomId;
  final String label;
  final int roomNights;
  final int stayCount;
  final DateTime? lastUsed;
  final EstablishmentRoomInfo info;

  double shareOf(int totalRoomNights) =>
      totalRoomNights <= 0 ? 0 : roomNights / totalRoomNights;
}

class EstablishmentRoomDssHint {
  const EstablishmentRoomDssHint({
    required this.roomId,
    required this.roomLabel,
    required this.reasons,
  });

  final String roomId;
  final String roomLabel;
  final List<String> reasons;
}

/// Lodging room-nights, occupancy trend, ranking, gated DSS hints.
class EstablishmentRoomAnalytics {
  const EstablishmentRoomAnalytics({
    required this.window,
    required this.dayCount,
    required this.distinctStayDays,
    required this.totalRoomNights,
    required this.guestNights,
    required this.stayCount,
    required this.avgLengthOfStay,
    required this.occupancyPctByDay,
    required this.dayLabels,
    required this.ranking,
    required this.dssLevel,
    required this.underusedHints,
    this.roomsAvailable = 0,
  });

  final EstablishmentInsightsWindow window;
  final int dayCount;
  final int distinctStayDays;
  final int totalRoomNights;
  final int guestNights;
  final int stayCount;
  final double avgLengthOfStay;
  final List<double> occupancyPctByDay;
  final List<String> dayLabels;
  final List<EstablishmentRoomUsageRow> ranking;
  final EstablishmentRoomDssLevel dssLevel;
  final List<EstablishmentRoomDssHint> underusedHints;
  final int roomsAvailable;

  /// Room-nights ÷ (rooms × days) when inventory known.
  double? get periodOccupancyPct {
    if (roomsAvailable < 1 || dayCount < 1) return null;
    final capacity = roomsAvailable * dayCount;
    if (capacity <= 0) return null;
    return (totalRoomNights / capacity * 100).clamp(0, 100);
  }

  static const empty = EstablishmentRoomAnalytics(
    window: EstablishmentInsightsWindow.days7,
    dayCount: 7,
    distinctStayDays: 0,
    totalRoomNights: 0,
    guestNights: 0,
    stayCount: 0,
    avgLengthOfStay: 0,
    occupancyPctByDay: [],
    dayLabels: [],
    ranking: [],
    dssLevel: EstablishmentRoomDssLevel.locked,
    underusedHints: [],
  );
}

/// Builds lodging room analytics from confirmed stays + room catalog.
abstract final class EstablishmentRoomAnalyticsBuilder {
  static ({DateTime start, DateTime end, int dayCount}) windowBounds(
    EstablishmentInsightsWindow window, {
    DateTime? now,
  }) {
    final n = now ?? DateTime.now();
    final today = DateTime(n.year, n.month, n.day);
    switch (window) {
      case EstablishmentInsightsWindow.days7:
        return (
          start: today.subtract(const Duration(days: 6)),
          end: today,
          dayCount: 7,
        );
      case EstablishmentInsightsWindow.days30:
        return (
          start: today.subtract(const Duration(days: 29)),
          end: today,
          dayCount: 30,
        );
      case EstablishmentInsightsWindow.thisMonth:
        final start = DateTime(n.year, n.month, 1);
        final dayCount = today.difference(start).inDays + 1;
        return (start: start, end: today, dayCount: dayCount < 1 ? 1 : dayCount);
    }
  }

  static EstablishmentRoomAnalytics build({
    required List<EstablishmentStayRequest> stays,
    required int roomCount,
    required Map<String, EstablishmentRoomInfo> inventory,
    List<EstablishmentStayReview> reviews = const [],
    EstablishmentInsightsWindow window = EstablishmentInsightsWindow.days30,
    DateTime? now,
  }) {
    if (roomCount < 1) return EstablishmentRoomAnalytics.empty;

    final bounds = windowBounds(window, now: now);
    final start = bounds.start;
    final end = bounds.end;
    final dayCount = bounds.dayCount;

    final nightsByRoom = <String, int>{};
    final staysByRoom = <String, int>{};
    final lastUsedByRoom = <String, DateTime>{};
    final partySizes = <int>[];
    final distinctDays = <DateTime>{};
    var totalRoomNights = 0;
    var guestNights = 0;
    var stayCount = 0;
    var nightsSum = 0;

    final occRoomNightsByDay = List<int>.filled(dayCount, 0);

    for (final s in stays) {
      if (!s.countsForDae) continue;
      final day = EstablishmentDssAggregates.stayDay(s);
      if (day == null) continue;
      if (day.isBefore(start) || day.isAfter(end)) continue;

      stayCount++;
      distinctDays.add(day);
      final nights = (s.nightsStayed != null && s.nightsStayed! > 0)
          ? s.nightsStayed!
          : 1;
      nightsSum += nights;
      guestNights += s.partySize * nights;
      partySizes.add(s.partySize);

      final slots = <String>{};
      for (final raw in s.roomNumbers) {
        final id = EstablishmentRoomGrid.normalizeSlotId(raw, roomCount);
        if (id != null) slots.add(id);
      }
      if (slots.isEmpty &&
          s.roomsOccupied != null &&
          s.roomsOccupied! > 0) {
        // No slot ids — still count toward period occupancy capacity use.
        totalRoomNights += s.roomsOccupied! * nights;
        final idx = day.difference(start).inDays;
        if (idx >= 0 && idx < dayCount) {
          occRoomNightsByDay[idx] += s.roomsOccupied! * nights;
        }
        continue;
      }

      for (final id in slots) {
        final rn = nights;
        nightsByRoom[id] = (nightsByRoom[id] ?? 0) + rn;
        staysByRoom[id] = (staysByRoom[id] ?? 0) + 1;
        totalRoomNights += rn;
        final prev = lastUsedByRoom[id];
        if (prev == null || day.isAfter(prev)) lastUsedByRoom[id] = day;
        final idx = day.difference(start).inDays;
        if (idx >= 0 && idx < dayCount) {
          occRoomNightsByDay[idx] += rn;
        }
      }
    }

    final ranking = <EstablishmentRoomUsageRow>[];
    for (var i = 1; i <= roomCount; i++) {
      final id = '$i';
      final info = inventory[id] ?? EstablishmentRoomInfo.empty;
      final type = info.type.trim();
      ranking.add(
        EstablishmentRoomUsageRow(
          roomId: id,
          label: type.isEmpty ? 'Room $id' : 'Room $id · $type',
          roomNights: nightsByRoom[id] ?? 0,
          stayCount: staysByRoom[id] ?? 0,
          lastUsed: lastUsedByRoom[id],
          info: info,
        ),
      );
    }
    ranking.sort((a, b) {
      final byNights = b.roomNights.compareTo(a.roomNights);
      if (byNights != 0) return byNights;
      return (int.tryParse(a.roomId) ?? 0).compareTo(int.tryParse(b.roomId) ?? 0);
    });

    final capacityPerDay = roomCount;
    final occupancyPctByDay = [
      for (final rn in occRoomNightsByDay)
        capacityPerDay <= 0
            ? 0.0
            : (rn / capacityPerDay * 100).clamp(0.0, 100.0),
    ];

    final dayLabels = _labelsForRange(start, dayCount);

    final dssLevel = _dssLevel(
      distinctDays: distinctDays.length,
      totalRoomNights: totalRoomNights,
    );

    final avgLos = stayCount == 0 ? 0.0 : nightsSum / stayCount;

    final hints = dssLevel == EstablishmentRoomDssLevel.locked
        ? const <EstablishmentRoomDssHint>[]
        : _buildHints(
            ranking: ranking,
            totalRoomNights: totalRoomNights,
            partySizes: partySizes,
            reviews: reviews,
            level: dssLevel,
          );

    return EstablishmentRoomAnalytics(
      window: window,
      dayCount: dayCount,
      distinctStayDays: distinctDays.length,
      totalRoomNights: totalRoomNights,
      guestNights: guestNights,
      stayCount: stayCount,
      avgLengthOfStay: avgLos,
      occupancyPctByDay: occupancyPctByDay,
      dayLabels: dayLabels,
      ranking: ranking,
      dssLevel: dssLevel,
      underusedHints: hints,
      roomsAvailable: roomCount,
    );
  }

  static List<String> _labelsForRange(DateTime start, int dayCount) {
    const names = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    return List.generate(dayCount, (i) {
      final d = start.add(Duration(days: i));
      if (dayCount > 14) return '${d.month}/${d.day}';
      return names[(d.weekday - 1) % 7];
    });
  }

  static EstablishmentRoomDssLevel _dssLevel({
    required int distinctDays,
    required int totalRoomNights,
  }) {
    if (distinctDays < 7 || totalRoomNights < 15) {
      return EstablishmentRoomDssLevel.locked;
    }
    if (distinctDays >= 28 || totalRoomNights >= 60) {
      return EstablishmentRoomDssLevel.full;
    }
    return EstablishmentRoomDssLevel.soft;
  }

  static List<EstablishmentRoomDssHint> _buildHints({
    required List<EstablishmentRoomUsageRow> ranking,
    required int totalRoomNights,
    required List<int> partySizes,
    required List<EstablishmentStayReview> reviews,
    required EstablishmentRoomDssLevel level,
  }) {
    if (ranking.isEmpty || totalRoomNights <= 0) return const [];

    final avgNights = totalRoomNights / ranking.length;
    final avgParty = partySizes.isEmpty
        ? 0.0
        : partySizes.reduce((a, b) => a + b) / partySizes.length;

    final priced = ranking
        .where((r) => r.info.pricePerNight > 0)
        .map((r) => r.info.pricePerNight)
        .toList();
    final avgPrice = priced.isEmpty
        ? 0.0
        : priced.reduce((a, b) => a + b) / priced.length;

    final highPerformers = ranking.where((r) => r.roomNights > avgNights).toList();
    final highInclAvg = highPerformers.isEmpty
        ? 0.0
        : highPerformers
                .map((r) => r.info.inclusions.length)
                .fold<int>(0, (a, b) => a + b) /
            highPerformers.length;

    final reviewAvgByRoom = <String, List<double>>{};
    for (final rev in reviews) {
      for (final raw in rev.roomNumbers) {
        final id = raw.trim();
        if (id.isEmpty) continue;
        reviewAvgByRoom.putIfAbsent(id, () => []).add(rev.roomRating);
      }
    }

    final maxHints = level == EstablishmentRoomDssLevel.full ? 5 : 3;
    final underused = ranking
        .where((r) => r.roomNights < avgNights * 0.55)
        .toList();
    // Prefer zero-use first.
    underused.sort((a, b) => a.roomNights.compareTo(b.roomNights));

    final out = <EstablishmentRoomDssHint>[];
    for (final room in underused) {
      if (out.length >= maxHints) break;
      final reasons = <String>[];

      if (room.roomNights == 0) {
        reasons.add(
          'Not assigned in this window while other rooms took stays — '
          'check desk assignment habits or disabled status.',
        );
      }

      final capMin = room.info.capacityMin;
      final capMax = room.info.capacityMax;
      if (avgParty > 0 && (capMin > 0 || capMax > 0)) {
        final lo = capMin > 0 ? capMin : 1;
        final hi = capMax > 0 ? capMax : lo;
        if (avgParty < lo - 0.4) {
          reasons.add(
            'Typical party size is ~${avgParty.toStringAsFixed(1)}; '
            'this room is cataloged for $lo${capMax > lo ? '–$hi' : ''} — '
            'capacity may be oversized for current demand.',
          );
        } else if (avgParty > hi + 0.4) {
          reasons.add(
            'Typical party size is ~${avgParty.toStringAsFixed(1)}; '
            'this room tops out at $hi — guests may need larger rooms.',
          );
        }
      }

      if (avgPrice > 0 &&
          room.info.pricePerNight > 0 &&
          room.info.pricePerNight >= avgPrice * 1.25) {
        reasons.add(
          'Priced ₱${room.info.pricePerNight.toStringAsFixed(0)}/night vs '
          'avg ₱${avgPrice.toStringAsFixed(0)} among cataloged rooms — '
          'price may be deterring bookings.',
        );
      }

      if (highInclAvg >= 2 &&
          room.info.inclusions.length + 1 < highInclAvg) {
        reasons.add(
          'Fewer listed inclusions than your busier rooms — '
          'amenities list may under-sell this unit.',
        );
      }

      final ratings = reviewAvgByRoom[room.roomId];
      if (ratings != null && ratings.isNotEmpty) {
        final avgR = ratings.reduce((a, b) => a + b) / ratings.length;
        if (avgR <= 3.0) {
          reasons.add(
            'Room rating averages ${avgR.toStringAsFixed(1)}★ from guests '
            'who stayed here — quality feedback may explain low reuse.',
          );
        }
      }

      if (reasons.isEmpty && room.roomNights > 0) {
        reasons.add(
          'Below-average room-nights in this window — monitor after more stays.',
        );
      }
      if (reasons.isEmpty) continue;

      out.add(
        EstablishmentRoomDssHint(
          roomId: room.roomId,
          roomLabel: room.label,
          reasons: reasons.take(level == EstablishmentRoomDssLevel.full ? 3 : 2)
              .toList(),
        ),
      );
    }
    return out;
  }
}

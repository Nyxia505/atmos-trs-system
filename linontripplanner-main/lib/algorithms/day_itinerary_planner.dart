import '../data.dart';
import '../municipality_coordinates.dart' show getMunicipalityCoordinates;
import '../trip_planner_utils.dart';
import 'content_based_filtering.dart';
import 'greedy_itinerary.dart';
import 'on_device_trip_planner.dart';
import 'trip_algorithm_models.dart';
import 'weighted_scoring.dart';

/// Result of packing user-selected spots into trip days.
class DayItineraryPlan {
  final List<List<TouristSpot>> days;
  final List<TouristSpot> orderedSpots;
  final String insight;
  final List<String> algorithmsUsed;

  const DayItineraryPlan({
    required this.days,
    required this.orderedSpots,
    required this.insight,
    this.algorithmsUsed = DayItineraryPlanner.algorithmsUsed,
  });
}

/// Builds a per-day itinerary from spots the tourist already chose.
///
/// Pipeline (same stages as [OnDeviceTripPlanner], kept in `algorithms/`):
/// 1. Content-Based Filtering
/// 2. Weighted Scoring Algorithm
/// 3. Greedy Algorithm (visit order along the route)
/// then packs the ordered stops into day buckets by transport limit.
class DayItineraryPlanner {
  DayItineraryPlanner._();

  static const algorithmsUsed = [
    'Content-Based Filtering',
    'Weighted Scoring Algorithm',
    'Greedy Algorithm',
  ];

  /// Orders [selectedSpots] with CBF → Weighted Scoring → Greedy, then
  /// distributes them across [tripDays]. Never drops a user-selected spot.
  static DayItineraryPlan build({
    required List<TouristSpot> selectedSpots,
    required Set<String> interests,
    required Map<String, double> interestWeights,
    required Map<String, int> ratedTypes,
    required double budget,
    required String transportMode,
    required int tripDays,
    required Municipality start,
    required List<Municipality> municipalitiesOnRoute,
    Set<String>? routeAliases,
  }) {
    final days = tripDays < 1 ? 1 : tripDays;
    final empty = List.generate(days, (_) => <TouristSpot>[]);
    if (selectedSpots.isEmpty) {
      return DayItineraryPlan(
        days: empty,
        orderedSpots: const [],
        insight: 'No spots selected yet.',
      );
    }

    final aliases = routeAliases ?? _aliasesFor(municipalitiesOnRoute);
    final maxPerDay = OnDeviceTripPlanner.maxSpotsPerDay(transportMode);
    final maxTotal = (days * maxPerDay).clamp(selectedSpots.length, 999);

    // 1) Content-Based Filtering (soft — re-attach any dropped picks)
    var filtered = ContentBasedFiltering.filter(
      spots: selectedSpots,
      selectedInterests: interests,
      interestWeights: interestWeights,
      minSimilarity: 0.0,
    );
    filtered = _ensureAllSelected(selectedSpots, filtered);

    // 2) Weighted Scoring Algorithm (soft — keep budget/interest misses)
    var scored = WeightedScoring.scoreAll(
      candidates: filtered,
      selectedInterests: interests,
      budget: budget,
      transportMode: transportMode,
      ratedTypes: ratedTypes,
    );
    scored = _ensureAllScored(filtered, scored);

    // 3) Greedy Algorithm — visit order along start → end corridor
    final startCoord = getMunicipalityCoordinates(start);
    final startPair = (
      lat: startCoord?.latitude ?? 8.45,
      lng: startCoord?.longitude ?? 123.75,
    );
    final coords = GreedyItinerary.coordsFromMunicipalities(
      municipalitiesOnRoute.isNotEmpty
          ? municipalitiesOnRoute
          : municipalities,
    );

    final greedyPick = GreedyItinerary.build(
      scored: scored,
      municipalitiesRoute:
          municipalitiesOnRoute.map((m) => m.name).toList(),
      routeAliases: aliases,
      maxTotal: maxTotal,
      start: startPair,
      municipalityCoords: coords,
    );

    // Preserve every user pick: greedy order first, then leftovers by score.
    final ordered = _mergeOrdered(selectedSpots, greedyPick, scored);

    final buckets = _packIntoDays(
      ordered: ordered,
      days: days,
      maxPerDay: maxPerDay,
    );

    final topReasons = scored
        .take(3)
        .expand((s) => s.matchReasons)
        .take(4)
        .toList();

    final insight = StringBuffer()
      ..write(
        'Auto-plan: Content-Based Filtering → Weighted Scoring → Greedy. ',
      )
      ..write('${ordered.length} stops across $days day')
      ..write(days == 1 ? '' : 's')
      ..write(' (max $maxPerDay/day for $transportMode)');
    if (interests.isNotEmpty) {
      insight.write(', prioritizing ${interests.take(3).join(', ')}');
    }
    insight.write('.');
    if (topReasons.isNotEmpty) {
      insight.write(' Top picks: ${topReasons.join('; ')}.');
    }

    return DayItineraryPlan(
      days: buckets,
      orderedSpots: ordered,
      insight: insight.toString(),
    );
  }

  static Set<String> _aliasesFor(List<Municipality> onRoute) {
    final aliases = <String>{};
    for (final m in onRoute) {
      aliases.addAll(municipalityAliases(m));
    }
    return aliases;
  }

  static List<ScoredSpotData> _ensureAllSelected(
    List<TouristSpot> selected,
    List<ScoredSpotData> filtered,
  ) {
    final keys = filtered.map((s) => s.key).toSet();
    final out = List<ScoredSpotData>.from(filtered);
    for (final spot in selected) {
      final key = '${spot.name}|${spot.location}';
      if (!keys.contains(key)) {
        out.add(ScoredSpotData(spot: spot, contentSimilarity: 0));
        keys.add(key);
      }
    }
    return out;
  }

  static List<ScoredSpotData> _ensureAllScored(
    List<ScoredSpotData> candidates,
    List<ScoredSpotData> scored,
  ) {
    final keys = scored.map((s) => s.key).toSet();
    final out = List<ScoredSpotData>.from(scored);
    for (final c in candidates) {
      if (keys.contains(c.key)) continue;
      // Soft fallback so explicitly chosen spots are never dropped.
      final soft = (40 + c.contentSimilarity * 40 + c.spot.rating * 4)
          .clamp(1.0, 99.0);
      out.add(
        c.copyWith(
          weightedScore: double.parse(soft.toStringAsFixed(2)),
          matchReasons: const ['On your selected list'],
        ),
      );
      keys.add(c.key);
    }
    out.sort((a, b) => b.weightedScore.compareTo(a.weightedScore));
    return out;
  }

  static List<TouristSpot> _mergeOrdered(
    List<TouristSpot> selected,
    List<ScoredSpotData> greedyPick,
    List<ScoredSpotData> scored,
  ) {
    final selectedKeys = {
      for (final s in selected) '${s.name}|${s.location}',
    };
    final byKey = {
      for (final s in selected) '${s.name}|${s.location}': s,
    };
    final ordered = <TouristSpot>[];
    final used = <String>{};

    for (final g in greedyPick) {
      if (!selectedKeys.contains(g.key) || used.contains(g.key)) continue;
      ordered.add(byKey[g.key]!);
      used.add(g.key);
    }

    final leftovers = scored
        .where((s) => selectedKeys.contains(s.key) && !used.contains(s.key))
        .toList()
      ..sort((a, b) => b.weightedScore.compareTo(a.weightedScore));
    for (final s in leftovers) {
      ordered.add(byKey[s.key]!);
      used.add(s.key);
    }

    for (final s in selected) {
      final key = '${s.name}|${s.location}';
      if (!used.contains(key)) {
        ordered.add(s);
        used.add(key);
      }
    }
    return ordered;
  }

  static List<List<TouristSpot>> _packIntoDays({
    required List<TouristSpot> ordered,
    required int days,
    required int maxPerDay,
  }) {
    final buckets = List.generate(days, (_) => <TouristSpot>[]);
    if (ordered.isEmpty) return buckets;
    var day = 0;
    for (final spot in ordered) {
      while (day < days - 1 && buckets[day].length >= maxPerDay) {
        day++;
      }
      buckets[day].add(spot);
    }
    return buckets;
  }
}

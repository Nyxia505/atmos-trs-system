import '../data.dart';
import '../municipality_coordinates.dart' show getMunicipalityCoordinates;
import '../trip_planner_utils.dart';
import '../trip_recommendation_engine.dart';
import 'content_based_filtering.dart';
import 'greedy_itinerary.dart';
import 'trip_algorithm_models.dart';
import 'weighted_scoring.dart';

/// Full on-device pipeline — no server required.
class OnDeviceTripPlanner {
  OnDeviceTripPlanner._();
  static final OnDeviceTripPlanner instance = OnDeviceTripPlanner._();

  static const algorithmsUsed = [
    'Content-Based Filtering',
    'Weighted Scoring Algorithm',
    'Greedy Algorithm',
  ];

  static int maxSpotsPerDay(String transport) {
    // Each itinerary day is capped at 4 stops regardless of transport.
    return 4;
  }

  LatLngPair _coordForMunicipality(Municipality m) {
    final c = getMunicipalityCoordinates(m);
    if (c != null) return (lat: c.latitude, lng: c.longitude);
    return (lat: 8.45, lng: 123.75);
  }

  Map<String, LatLngPair> _allMunicipalityCoords() {
    final map = <String, LatLngPair>{};
    for (final m in municipalities) {
      final c = getMunicipalityCoordinates(m);
      if (c != null) {
        map[m.name] = (lat: c.latitude, lng: c.longitude);
        map[m.shortName] = (lat: c.latitude, lng: c.longitude);
      }
    }
    return map;
  }

  ({
    List<TouristSpot> itinerary,
    List<ScoredRecommendation> scored,
    Set<String> exactNames,
    int maxPerDay,
    String insight,
  }) plan({
    required TripRecommendationRequest request,
    required Map<String, double> interestWeights,
    required Map<String, int> ratedTypes,
  }) {
    final maxPerDay = maxSpotsPerDay(request.transportMode);
    final maxTotal = request.tripDays * maxPerDay;
    final coords = _allMunicipalityCoords();

    final routeSpots = allSpots.where((spot) {
      final loc = normalizeMunicipalityName(spot.location);
      return request.routeLocationAliases.contains(loc);
    }).toList();

    // 1) Content-Based Filtering
    final filtered = ContentBasedFiltering.filter(
      spots: routeSpots,
      selectedInterests: request.interests,
      interestWeights: interestWeights,
    );

    // 2) Weighted Scoring Algorithm
    final scoredData = WeightedScoring.scoreAll(
      candidates: filtered,
      selectedInterests: request.interests,
      budget: request.budget,
      transportMode: request.transportMode,
      ratedTypes: ratedTypes,
    );

    final start = _coordForMunicipality(request.start);

    // 3) Greedy Algorithm
    final greedyPick = GreedyItinerary.build(
      scored: scoredData,
      municipalitiesRoute:
          request.municipalitiesOnRoute.map((m) => m.name).toList(),
      routeAliases: request.routeLocationAliases,
      maxTotal: maxTotal,
      start: start,
      municipalityCoords: coords,
    );

    // Visit order follows Greedy selection (along your start → end route).
    final itinerary = greedyPick.map((s) => s.spot).toList();
    final exactNames = greedyPick
        .where((s) => s.exactBudgetMatch)
        .map((s) => s.spot.name)
        .toSet();

    final scored = scoredData
        .take(50)
        .map(
          (s) => ScoredRecommendation(
            spot: s.spot,
            score: s.weightedScore,
            matchReasons: s.matchReasons,
          ),
        )
        .toList();

    final insight = _insight(
      request: request,
      stopCount: itinerary.length,
      topReasons: scored.take(3).expand((s) => s.matchReasons).take(4),
    );

    return (
      itinerary: itinerary,
      scored: scored,
      exactNames: exactNames,
      maxPerDay: maxPerDay,
      insight: insight,
    );
  }

  String _insight({
    required TripRecommendationRequest request,
    required int stopCount,
    required Iterable<String> topReasons,
  }) {
    final parts = <String>[
      'Personalized plan: Content-Based Filtering → Weighted Scoring → Greedy itinerary.',
      '${stopCount} stops for ${request.transportMode.toLowerCase()} travel',
      if (request.interests.isNotEmpty)
        ', prioritizing ${request.interests.take(3).join(', ')}',
      if (request.budget > 0)
        ', budget ₱${request.budget.toStringAsFixed(0)}',
      '.',
    ];
    final reasons = topReasons.toList();
    if (reasons.isNotEmpty) {
      parts.add(' Top picks: ${reasons.join('; ')}.');
    }
    return parts.join();
  }
}

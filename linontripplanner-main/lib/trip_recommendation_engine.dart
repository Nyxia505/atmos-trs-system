import 'package:flutter/material.dart';

import 'algorithms/on_device_trip_planner.dart';
import 'data.dart';
import 'trip_planner_utils.dart';
import 'trip_preferences_store.dart';

/// Inputs for generating a personalized trip plan.
class TripRecommendationRequest {
  final DateTimeRange dateRange;
  final Municipality start;
  final Municipality end;
  final int numberOfTourists;
  final String transportMode;
  final Set<String> interests;
  final double budget;
  final TripBudgetTier budgetTier;
  final List<Municipality> municipalitiesOnRoute;
  final Set<String> routeLocationAliases;

  const TripRecommendationRequest({
    required this.dateRange,
    required this.start,
    required this.end,
    this.numberOfTourists = 1,
    required this.transportMode,
    required this.interests,
    required this.budget,
    required this.budgetTier,
    required this.municipalitiesOnRoute,
    required this.routeLocationAliases,
  });

  int get tripDays =>
      dateRange.end.difference(dateRange.start).inDays + 1;
}

/// One ranked candidate with explainable scoring.
class ScoredRecommendation {
  final TouristSpot spot;
  final double score;
  final List<String> matchReasons;

  const ScoredRecommendation({
    required this.spot,
    required this.score,
    required this.matchReasons,
  });
}

/// Output of the recommendation engine.
class TripRecommendationResult {
  final List<TouristSpot> itinerarySpots;
  final List<ScoredRecommendation> scoredCandidates;
  final List<TourismEvent> routeEvents;
  final List<TourismEvent> trackedEvents;
  final String insightSummary;
  final Set<String> exactBudgetSpotNames;
  final int maxSpotsPerDay;

  const TripRecommendationResult({
    required this.itinerarySpots,
    required this.scoredCandidates,
    required this.routeEvents,
    required this.trackedEvents,
    required this.insightSummary,
    required this.exactBudgetSpotNames,
    required this.maxSpotsPerDay,
  });
}

/// Trip recommendations — runs entirely on the device (no server).
class TripRecommendationEngine {
  TripRecommendationEngine._();
  static final TripRecommendationEngine instance = TripRecommendationEngine._();

  static const Map<String, String> _eventTypeToInterest = {
    'Festival': 'Festivals',
    'Cultural': 'Culture',
    'Food & Drink': 'Food',
    'Music': 'Nightlife',
    'Sports': 'Adventure',
    'Religious': 'Culture',
    'Community': 'Festivals',
  };

  Future<TripRecommendationResult> generate(
    TripRecommendationRequest request,
  ) async {
    final prefs = TripPreferencesStore.instance;
    final interestWeights = await prefs.loadInterestWeights();
    final ratedTypes = await prefs.loadRatedSpotTypeCounts();
    final trackedIds = await prefs.loadTrackedEventIds();

    await prefs.recordTripInputs(
      transportMode: request.transportMode,
      interests: request.interests.toList(),
      budgetTierName: request.budgetTier.name,
    );

    final routeEvents = _eventsAlongTrip(request);
    final trackedEvents =
        routeEvents.where((e) => trackedIds.contains(e.id)).toList();

    final plan = OnDeviceTripPlanner.instance.plan(
      request: request,
      interestWeights: interestWeights,
      ratedTypes: ratedTypes,
    );

    return TripRecommendationResult(
      itinerarySpots: plan.itinerary,
      scoredCandidates: plan.scored,
      routeEvents: routeEvents,
      trackedEvents: trackedEvents,
      insightSummary: plan.insight,
      exactBudgetSpotNames: plan.exactNames,
      maxSpotsPerDay: plan.maxPerDay,
    );
  }

  List<TourismEvent> _eventsAlongTrip(TripRecommendationRequest request) {
    final start = DateTime(
      request.dateRange.start.year,
      request.dateRange.start.month,
      request.dateRange.start.day,
    );
    final end = DateTime(
      request.dateRange.end.year,
      request.dateRange.end.month,
      request.dateRange.end.day,
      23,
      59,
      59,
    );

    final routeNames = <String>{};
    for (final m in request.municipalitiesOnRoute) {
      routeNames.addAll(municipalityAliases(m));
    }

    return tourismEvents.where((event) {
      if (event.dateTime.isBefore(start) || event.dateTime.isAfter(end)) {
        return false;
      }
      final munNorm = normalizeMunicipalityName(event.municipality);
      final venueNorm = normalizeMunicipalityName(event.venue);
      final onRoute = routeNames.any(
        (alias) =>
            alias.isNotEmpty &&
            (munNorm.contains(alias) || venueNorm.contains(alias)),
      );
      if (!onRoute && venueNorm.isNotEmpty) {
        final hint = matchMunicipalityByLocalityHint(event.venue);
        if (hint != null) {
          return request.municipalitiesOnRoute.any(
            (m) => m.name == hint.name,
          );
        }
      }
      if (onRoute) return true;

      final mapped = _eventTypeToInterest[event.eventType];
      if (mapped != null && request.interests.contains(mapped)) return true;
      if (request.interests.contains('Festivals') &&
          event.eventType == 'Festival') {
        return true;
      }
      return venueNorm.isEmpty;
    }).toList()
      ..sort((a, b) => a.dateTime.compareTo(b.dateTime));
  }

  List<TourismEvent> eventsForDate(
    List<TourismEvent> events,
    DateTime day,
  ) {
    return events.where((e) {
      return e.dateTime.year == day.year &&
          e.dateTime.month == day.month &&
          e.dateTime.day == day.day;
    }).toList();
  }
}

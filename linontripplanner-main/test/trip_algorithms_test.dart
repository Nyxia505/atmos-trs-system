import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trip_plan/algorithms/content_based_filtering.dart';
import 'package:trip_plan/algorithms/greedy_itinerary.dart';
import 'package:trip_plan/algorithms/on_device_trip_planner.dart';
import 'package:trip_plan/algorithms/trip_algorithm_models.dart';
import 'package:trip_plan/algorithms/weighted_scoring.dart';
import 'package:trip_plan/data.dart';
import 'package:trip_plan/trip_planner_utils.dart';
import 'package:trip_plan/trip_recommendation_engine.dart';

TouristSpot _spot({
  required String name,
  required String location,
  String type = 'Nature',
  double rating = 4.5,
  String priceRange = '100-500',
  String description = 'waterfall eco park',
  double? lat,
  double? lng,
  int? walkMin,
}) {
  return TouristSpot(
    name: name,
    priceRange: priceRange,
    imagePath: '',
    location: location,
    rating: rating,
    description: description,
    type: type,
    latitude: lat,
    longitude: lng,
    walkingDistanceMinutes: walkMin,
  );
}

void main() {
  group('1. Content-Based Filtering', () {
    test('keeps Nature spots when Nature is selected', () {
      final spots = [
        _spot(name: 'Falls', location: 'Ozamiz City', type: 'Nature'),
        _spot(name: 'Night Bar', location: 'Ozamiz City', type: 'Food', description: 'bar nightlife'),
      ];
      final out = ContentBasedFiltering.filter(
        spots: spots,
        selectedInterests: {'Nature'},
        interestWeights: {},
      );
      expect(out.length, 1);
      expect(out.first.spot.name, 'Falls');
      expect(out.first.contentSimilarity, greaterThan(0));
    });

    test('ranks higher similarity first', () {
      final spots = [
        _spot(name: 'Beach', location: 'Baliangao', type: 'Relaxation', description: 'sandy beach'),
        _spot(name: 'Trail', location: 'Baliangao', type: 'Nature'),
      ];
      final out = ContentBasedFiltering.filter(
        spots: spots,
        selectedInterests: {'Nature', 'Beaches'},
        interestWeights: {},
      );
      expect(out.length, 2);
      expect(
        out.first.contentSimilarity,
        greaterThanOrEqualTo(out.last.contentSimilarity),
      );
    });
  });

  group('2. Weighted Scoring Algorithm', () {
    test('assigns positive score when budget and interest match', () {
      final candidate = ScoredSpotData(
        spot: _spot(name: 'Park', location: 'Ozamiz City', type: 'Nature'),
        contentSimilarity: 0.5,
      );
      final scored = WeightedScoring.score(
        input: candidate,
        selectedInterests: {'Nature'},
        budget: 5000,
        transportMode: 'Car',
        ratedTypes: {},
      );
      expect(scored, isNotNull);
      expect(scored!.weightedScore, greaterThan(0));
      expect(scored.matchReasons, isNotEmpty);
    });

    test('rejects spot over budget', () {
      final candidate = ScoredSpotData(
        spot: _spot(
          name: 'Luxury',
          location: 'Ozamiz City',
          priceRange: '10000-20000',
        ),
        contentSimilarity: 0.4,
      );
      final scored = WeightedScoring.score(
        input: candidate,
        selectedInterests: {'Nature'},
        budget: 500,
        transportMode: 'Car',
        ratedTypes: {},
      );
      expect(scored, isNull);
    });
  });

  group('3. Greedy Algorithm', () {
    test('selects up to maxTotal with score/distance heuristic', () {
      final scored = [
        ScoredSpotData(
          spot: _spot(name: 'A', location: 'Ozamiz City', lat: 8.15, lng: 123.84),
          weightedScore: 80,
        ),
        ScoredSpotData(
          spot: _spot(name: 'B', location: 'Oroquieta City', lat: 8.49, lng: 123.80),
          weightedScore: 70,
        ),
        ScoredSpotData(
          spot: _spot(name: 'C', location: 'Ozamiz City', lat: 8.16, lng: 123.85),
          weightedScore: 60,
        ),
      ];
      final coords = {
        'Ozamiz City': (lat: 8.1481, lng: 123.8405),
        'Oroquieta City': (lat: 8.4859, lng: 123.8048),
      };
      final itinerary = GreedyItinerary.build(
        scored: scored,
        municipalitiesRoute: ['Ozamiz City', 'Oroquieta City'],
        routeAliases: {'ozamiz city', 'oroquieta city'},
        maxTotal: 2,
        start: (lat: 8.1481, lng: 123.8405),
        municipalityCoords: coords,
      );
      expect(itinerary.length, lessThanOrEqualTo(2));
      expect(itinerary.isNotEmpty, true);
    });
  });

  group('Full pipeline (OnDeviceTripPlanner)', () {
    setUp(() {
      allSpots.clear();
      allSpots.addAll([
        _spot(name: 'Eco Park', location: 'Ozamiz City', type: 'Nature', lat: 8.15, lng: 123.84),
        _spot(name: 'Heritage Site', location: 'Oroquieta City', type: 'Culture', lat: 8.49, lng: 123.80),
        _spot(name: 'Beach Cove', location: 'Baliangao', type: 'Relaxation', description: 'beach', lat: 8.67, lng: 123.60),
      ]);
    });

    test('runs three stages and returns itinerary', () {
      final oz = municipalities.firstWhere((m) => m.shortName.contains('Ozamiz'));
      final oro =
          municipalities.firstWhere((m) => m.shortName.contains('Oroquieta'));
      final aliases = {
        ...municipalityAliases(oz),
        ...municipalityAliases(oro),
      };

      final request = TripRecommendationRequest(
        dateRange: DateTimeRange(
          start: DateTime(2026, 6, 1),
          end: DateTime(2026, 6, 3),
        ),
        start: oz,
        end: oro,
        transportMode: 'Car',
        interests: {'Nature', 'Culture'},
        budget: 5000,
        budgetTier: TripBudgetTier.moderate,
        municipalitiesOnRoute: [oz, oro],
        routeLocationAliases: aliases,
      );

      final result = OnDeviceTripPlanner.instance.plan(
        request: request,
        interestWeights: {},
        ratedTypes: {},
      );

      expect(OnDeviceTripPlanner.algorithmsUsed.length, 3);
      expect(OnDeviceTripPlanner.algorithmsUsed, isNot(contains('A* Algorithm')));
      expect(result.itinerary, isNotEmpty);
      expect(result.scored, isNotEmpty);
      expect(result.insight, contains('Content-Based'));
    });
  });
}

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../algorithms/day_itinerary_planner.dart';
import '../algorithms/nearest_neighbor_itinerary.dart';
import '../algorithms/on_device_trip_planner.dart';
import '../data.dart';
import '../municipal_road_distances.dart';
import '../municipality_bus_terminals.dart';
import '../municipality_coordinates.dart';
import '../road_route_service.dart';
import '../services/spot_interaction_history.dart';
import '../trip_planner_utils.dart';
import '../trip_preferences_store.dart';
import 'tourist_travel_estimates.dart';

enum TripWizardStep {
  tripInfo,
  itinerary,
  review,
}

/// A point in the itinerary: [place] is a municipality name or spot location
/// (for road-table distances), [point] its coordinates, [label] what to show.
typedef TripPlace = ({String place, LatLng? point, String label});

/// Suggested spot near the user's start→end route.
class RouteSpotSuggestion {
  final TouristSpot spot;
  final double distanceFromRouteKm;
  final Municipality? municipality;

  const RouteSpotSuggestion({
    required this.spot,
    required this.distanceFromRouteKm,
    this.municipality,
  });
}

/// Guided trip-planning state. Itinerary is created only after Review → Generate.
class TripWizardController extends ChangeNotifier {
  TripWizardStep step = TripWizardStep.tripInfo;

  Municipality? start;
  Municipality? end;
  DateTime? arrivalDate;
  DateTime? departureDate;
  int? explicitDayCount;
  double budgetPhp = 5000;
  int travelers = 1;
  String transportMode = 'Public Transport';
  final Set<String> interests = {};

  List<Municipality> municipalitiesOnRoute = [];
  List<LatLng> routePoints = [];

  /// Start → end road route (towns in driving order, polyline, km, minutes).
  RoadRoute? roadRoute;
  double? get routeDistanceKm => roadRoute?.distanceKm;
  int? get routeDrivingMinutes => roadRoute?.drivingMinutes;
  List<RouteSpotSuggestion> routeSuggestions = [];
  final List<TouristSpot> selectedSpots = [];

  bool loadingRoute = false;
  String? routeError;
  bool showAllNearby = false;
  String? categoryFilter;
  String spotSearch = '';

  /// Insight from CBF → Weighted Scoring → Greedy day plan.
  String? algorithmInsight;
  bool loadingDayPlan = false;

  /// Inclusive calendar days. Aug 27–30 → 4 days (27, 28, 29, 30).
  int get tripDays {
    if (arrivalDate != null && departureDate != null) {
      final d = departureDate!.difference(arrivalDate!).inDays + 1;
      return d < 1 ? 1 : d;
    }
    if (explicitDayCount != null && explicitDayCount! > 0) {
      return explicitDayCount!;
    }
    return 1;
  }

  /// Nights between inclusive dates. Aug 27–30 → 3 nights.
  int get nights {
    if (arrivalDate != null && departureDate != null) {
      final n = departureDate!.difference(arrivalDate!).inDays;
      return n < 0 ? 0 : n;
    }
    if (explicitDayCount != null && explicitDayCount! > 0) {
      return (explicitDayCount! - 1).clamp(0, 365);
    }
    return 0;
  }

  /// Keep [explicitDayCount] aligned with inclusive arrival→departure.
  void syncDayCountFromDates() {
    if (arrivalDate == null || departureDate == null) return;
    explicitDayCount = tripDays.clamp(1, 30);
  }

  bool get needsAccommodation => nights >= 1;

  bool get canContinueFromTripInfo {
    if (start == null || end == null) return false;
    if (start!.name == end!.name) return false;
    if (arrivalDate == null) return false;
    if (departureDate == null && (explicitDayCount == null || explicitDayCount! < 1)) {
      return false;
    }
    if (budgetPhp <= 0) return false;
    if (travelers < 1) return false;
    if (interests.isEmpty) return false;
    return true;
  }

  String? tripInfoValidationError() {
    if (start == null) return 'Choose a starting point.';
    if (end == null) return 'Choose an endpoint / final destination.';
    if (start!.name == end!.name) {
      return 'Starting point and endpoint must be different.';
    }
    if (arrivalDate == null) return 'Choose your travel / arrival date.';
    if (departureDate == null &&
        (explicitDayCount == null || explicitDayCount! < 1)) {
      return 'Set an end date or number of days.';
    }
    if (budgetPhp <= 0) return 'Enter a total budget greater than PHP 0.';
    if (travelers < 1) return 'Enter at least 1 traveler.';
    if (interests.isEmpty) return 'Select at least one interest / category.';
    return null;
  }

  void setStart(Municipality? m) {
    start = m;
    routeDirection = null;
    notifyListeners();
  }

  void setEnd(Municipality? m) {
    end = m;
    routeDirection = null;
    notifyListeners();
  }

  /// Coastal / highland choices for the current start → end (empty when only one
  /// way makes sense).
  List<RoadRouteOption> get routeOptions {
    final s = start;
    final e = end;
    if (s == null || e == null || s.name == e.name) return const [];
    return roadRouteOptionsBetween(s, e);
  }

  /// Direction picked by the user; null = shortest road.
  RoadRouteDirection? routeDirection;

  /// [routeDirection] when it is one of [routeOptions], else the shortest
  /// road (null).
  RoadRouteDirection? get effectiveRouteDirection {
    final d = routeDirection;
    if (d == null) return null;
    return routeOptions.any((o) => o.direction == d) ? d : null;
  }

  /// The option currently in use (user's pick, else the shortest).
  RoadRouteDirection? get selectedRouteDirection {
    final options = routeOptions;
    if (options.isEmpty) return null;
    return effectiveRouteDirection ?? options.first.direction;
  }

  void setRouteDirection(RoadRouteDirection d) {
    routeDirection = d;
    notifyListeners();
  }

  void setArrival(DateTime d) {
    arrivalDate = DateTime(d.year, d.month, d.day);
    if (departureDate != null && departureDate!.isBefore(arrivalDate!)) {
      // Keep trip length if we already know days; else at least 1 day.
      final keep = (explicitDayCount ?? tripDays).clamp(1, 30);
      departureDate = arrivalDate!.add(Duration(days: keep - 1));
    } else if (departureDate == null &&
        explicitDayCount != null &&
        explicitDayCount! > 0) {
      departureDate =
          arrivalDate!.add(Duration(days: explicitDayCount! - 1));
    } else if (departureDate != null) {
      syncDayCountFromDates();
    }
    notifyListeners();
  }

  void setDeparture(DateTime d) {
    departureDate = DateTime(d.year, d.month, d.day);
    if (arrivalDate != null && departureDate!.isBefore(arrivalDate!)) {
      arrivalDate = departureDate;
    }
    // Inclusive range drives day count (e.g. Aug 27–30 → 4).
    syncDayCountFromDates();
    notifyListeners();
  }

  /// Sets trip length and end date from an inclusive day count.
  /// Example: arrival Aug 27 + 4 days → end Aug 30.
  void setDayCount(int days) {
    explicitDayCount = days.clamp(1, 30);
    if (arrivalDate != null) {
      departureDate =
          arrivalDate!.add(Duration(days: explicitDayCount! - 1));
    }
    notifyListeners();
  }

  /// Inclusive date range (start and end both count as explore days).
  void setDateRange(DateTime start, DateTime end) {
    arrivalDate = DateTime(start.year, start.month, start.day);
    departureDate = DateTime(end.year, end.month, end.day);
    if (departureDate!.isBefore(arrivalDate!)) {
      final tmp = arrivalDate;
      arrivalDate = departureDate;
      departureDate = tmp;
    }
    syncDayCountFromDates();
    notifyListeners();
  }

  void setBudget(double v) {
    budgetPhp = v < 0 ? 0 : v;
    notifyListeners();
  }

  void setTravelers(int n) {
    travelers = n.clamp(1, 99);
    notifyListeners();
  }

  void setTransport(String mode) {
    if (kTransportModes.contains(mode)) {
      transportMode = mode;
      notifyListeners();
    }
  }

  void toggleInterest(String interest) {
    if (interests.contains(interest)) {
      if (interests.length > 1) interests.remove(interest);
    } else {
      interests.add(interest);
    }
    notifyListeners();
  }

  void setCategoryFilter(String? type) {
    categoryFilter = type;
    notifyListeners();
  }

  void setSpotSearch(String q) {
    spotSearch = q;
    notifyListeners();
  }

  void setShowAllNearby(bool v) {
    showAllNearby = v;
    notifyListeners();
  }

  bool isSelected(TouristSpot spot) =>
      selectedSpots.any((s) => s.name == spot.name);

  String? addSpot(TouristSpot spot) {
    if (isSelected(spot)) return 'Already on your trip';
    selectedSpots.add(spot);
    notifyListeners();
    return null;
  }

  void removeSpot(TouristSpot spot) {
    selectedSpots.removeWhere((s) => s.name == spot.name);
    _removeSpotFromAllDays(spot);
    notifyListeners();
  }

  void replaceSpot(TouristSpot oldSpot, TouristSpot newSpot) {
    final i = selectedSpots.indexWhere((s) => s.name == oldSpot.name);
    if (i < 0) return;
    if (isSelected(newSpot) && newSpot.name != oldSpot.name) return;
    selectedSpots[i] = newSpot;
    for (final day in daySpotAssignments) {
      final di = day.indexWhere((s) => s.name == oldSpot.name);
      if (di >= 0) day[di] = newSpot;
    }
    notifyListeners();
  }

  void reorderSpots(int oldIndex, int newIndex) {
    if (newIndex > oldIndex) newIndex -= 1;
    final item = selectedSpots.removeAt(oldIndex);
    selectedSpots.insert(newIndex, item);
    notifyListeners();
  }

  void clearSelected() {
    selectedSpots.clear();
    daySpotAssignments = [];
    notifyListeners();
  }

  /// Per-day spot picks (user-editable on itinerary).
  List<List<TouristSpot>> daySpotAssignments = [];

  List<TouristSpot> get unassignedSpots {
    final assigned = <String>{};
    for (final day in daySpotAssignments) {
      for (final s in day) {
        assigned.add(s.name);
      }
    }
    return selectedSpots.where((s) => !assigned.contains(s.name)).toList();
  }

  /// Spot names already placed on any itinerary day.
  Set<String> get assignedSpotNames {
    final names = <String>{};
    for (final day in daySpotAssignments) {
      for (final s in day) {
        names.add(s.name);
      }
    }
    return names;
  }

  /// Spots the user may add to [dayIndex]:
  /// - never shows spots already used on another day
  /// - Day 1 only shows places near the trip start
  List<TouristSpot> spotsAvailableForDay(int dayIndex) {
    final used = assignedSpotNames;
    final pool = <String, TouristSpot>{};
    for (final s in selectedSpots) {
      pool[s.name] = s;
    }
    for (final r in routeSuggestions) {
      pool.putIfAbsent(r.spot.name, () => r.spot);
    }

    var list = pool.values.where((s) => !used.contains(s.name)).toList();

    if (dayIndex == 0) {
      list = list.where(_isNearTripStart).toList();
    }
    final from = dayCurrentPlace(dayIndex);
    if (from != null) {
      return _nearestNeighbor.rankUnvisited(
        from: from,
        candidates: list,
        visited: used,
      );
    }
    list.sort((a, b) {
      final da = _routeProgressKm(a) ?? 999;
      final db = _routeProgressKm(b) ?? 999;
      final c = da.compareTo(db);
      if (c != 0) return c;
      return b.rating.compareTo(a.rating);
    });
    return list;
  }

  // ---------------------------------------------------------------------------
  // Nearest Neighbor itinerary: each day starts where the previous day ended
  // and keeps moving to the closest unvisited spot.
  // ---------------------------------------------------------------------------

  late final NearestNeighborItinerary<TouristSpot, TripPlace>
      _nearestNeighbor = NearestNeighborItinerary(
    keyOf: (s) => s.name,
    distanceKm: _travelKm,
    locationOf: _placeOfSpot,
  );

  /// Every spot the itinerary can visit: route spots plus the user's picks.
  List<TouristSpot> get routeSpotPool {
    final pool = <String, TouristSpot>{};
    for (final s in selectedSpots) {
      pool[s.name] = s;
    }
    for (final r in routeSuggestions) {
      pool.putIfAbsent(r.spot.name, () => r.spot);
    }
    return pool.values.toList();
  }

  /// Global visited list across all days: every spot already on a day.
  Set<String> get visitedSpotNames => assignedSpotNames;

  int get unvisitedSpotCount {
    final visited = visitedSpotNames;
    return routeSpotPool.where((s) => !visited.contains(s.name)).length;
  }

  TripPlace _placeOfSpot(TouristSpot spot) =>
      (place: spot.location, point: _spotRoutePoint(spot), label: spot.name);

  TripPlace? get _startPlace {
    final s = start;
    if (s == null) return null;
    return (
      place: s.name,
      point: getMunicipalityCoordinates(s),
      label: s.shortName.isNotEmpty ? s.shortName : s.name,
    );
  }

  /// Road km from [from] to [spot]: the road table between towns, never less
  /// than the straight line (+25% for road bends).
  double? _travelKm(TripPlace from, TouristSpot spot) {
    final road = roadDistanceKmBetween(from.place, spot.location);
    final a = from.point;
    final b = _spotRoutePoint(spot);
    if (a == null || b == null) return road;
    final straight =
        haversineDistanceKm(a.latitude, a.longitude, b.latitude, b.longitude) *
            1.25;
    return road == null ? straight : math.max(straight, road);
  }

  /// Where [dayIndex] starts: the trip start on Day 1, else the last spot of
  /// the closest earlier day that has spots.
  TripPlace? dayStartPlace(int dayIndex) {
    final days = spotsByDay;
    for (var d = math.min(dayIndex, days.length) - 1; d >= 0; d--) {
      if (days[d].isNotEmpty) return _placeOfSpot(days[d].last);
    }
    return _startPlace;
  }

  /// Current location while building [dayIndex]: its last spot, else where
  /// the day starts.
  TripPlace? dayCurrentPlace(int dayIndex) {
    final days = spotsByDay;
    if (dayIndex >= 0 && dayIndex < days.length && days[dayIndex].isNotEmpty) {
      return _placeOfSpot(days[dayIndex].last);
    }
    return dayStartPlace(dayIndex);
  }

  String dayStartLabel(int dayIndex) => dayStartPlace(dayIndex)?.label ?? '';

  String dayCurrentLabel(int dayIndex) =>
      dayCurrentPlace(dayIndex)?.label ?? '';

  /// Km from the current location of [dayIndex] to [spot].
  double? kmFromDayPosition(int dayIndex, TouristSpot spot) {
    final from = dayCurrentPlace(dayIndex);
    return from == null ? null : _travelKm(from, spot);
  }

  /// Closest unvisited spot from where [dayIndex] currently is.
  TouristSpot? nearestUnvisitedForDay(int dayIndex) {
    final list = spotsAvailableForDay(dayIndex);
    return list.isEmpty ? null : list.first;
  }

  /// Adds the nearest unvisited spot to [dayIndex]; returns an error message
  /// when nothing can be added.
  String? addNearestSpotToDay(int dayIndex) {
    final next = nearestUnvisitedForDay(dayIndex);
    if (next == null) {
      if (unvisitedSpotCount == 0) {
        return 'Every spot on your route is already planned.';
      }
      return dayIndex == 0
          ? 'No unvisited spots near your starting point. '
              'End Day 1 to continue on Day 2.'
          : 'No unvisited spots left for this day.';
    }
    return assignSpotToDay(next, dayIndex);
  }

  final Set<int> _endedDays = {};

  /// True after the user picked the final spot of [dayIndex].
  bool isDayEnded(int dayIndex) =>
      _endedDays.contains(dayIndex) &&
      dayIndex < daySpotAssignments.length &&
      daySpotAssignments[dayIndex].isNotEmpty;

  /// The user picks [last] as the final spot of [dayIndex]: it moves to the
  /// end of the day and the next day starts from it. When this was the last
  /// day and unvisited spots remain, a new day is added (no day limit).
  void endDayAt(int dayIndex, TouristSpot last) {
    _ensureDayBuckets();
    if (dayIndex < 0 || dayIndex >= daySpotAssignments.length) return;
    final day = daySpotAssignments[dayIndex];
    final i = day.indexWhere((s) => s.name == last.name);
    if (i < 0) return;
    day.add(day.removeAt(i));
    _endedDays.add(dayIndex);
    if (dayIndex == daySpotAssignments.length - 1 && unvisitedSpotCount > 0) {
      daySpotAssignments.add(<TouristSpot>[]);
      _setDayCount(daySpotAssignments.length);
    }
    notifyListeners();
  }

  /// Moves the end date so the trip has exactly [days] days.
  void _setDayCount(int days) {
    final a = arrivalDate;
    if (a != null) departureDate = a.add(Duration(days: days - 1));
    explicitDayCount = days;
    _plannedRouteKey = _routeKey;
  }

  /// Drops empty days at the end that the Nearest Neighbor flow added and
  /// that no ended day leads into any more.
  void _trimAddedEmptyDays() {
    if (_userDayCount < 1) return;
    var changed = false;
    while (daySpotAssignments.length > 1 &&
        daySpotAssignments.length > _userDayCount &&
        daySpotAssignments.last.isEmpty &&
        !isDayEnded(daySpotAssignments.length - 2)) {
      _endedDays.remove(daySpotAssignments.length - 1);
      daySpotAssignments.removeLast();
      changed = true;
    }
    if (changed) _setDayCount(daySpotAssignments.length);
  }

  bool _isNearTripStart(TouristSpot spot) {
    final s = start;
    if (s == null) return true;
    final spotIdx = roadTableIndexFor(spot.location);
    if (spotIdx != null && spotIdx == _roadIndexOf(s)) return true;
    final loc = spot.location.trim().toLowerCase();
    final aliases = municipalityAliases(s).map((a) => a.toLowerCase());
    for (final a in aliases) {
      if (a.isEmpty) continue;
      if (loc == a || loc.contains(a) || a.contains(loc)) return true;
    }
    final km = _routeProgressKm(spot);
    if (km == null) {
      // No coords: keep if on corridor municipalities near the start of the list.
      final onRoute = municipalitiesOnRoute;
      if (onRoute.isEmpty) return true;
      final startHalf = (onRoute.length / 2).ceil().clamp(1, onRoute.length);
      for (var i = 0; i < startHalf; i++) {
        final aliasesM = municipalityAliases(onRoute[i]).map((a) => a.toLowerCase());
        for (final a in aliasesM) {
          if (a.isNotEmpty && (loc == a || loc.contains(a) || a.contains(loc))) {
            return true;
          }
        }
      }
      return false;
    }
    return km <= _day1MaxKmFromStart;
  }

  static const double _day1MaxKmFromStart = 25;

  /// Km from the trip start along the road route, so spots sort in driving
  /// order. Falls back to road km from the start when there is no route.
  double? _routeProgressKm(TouristSpot spot) {
    final r = roadRoute;
    if (r == null) return _distanceFromStartKm(spot);
    final p = _spotRoutePoint(spot);
    if (r.followsRoads && p != null) return r.progressKmAt(p);
    final i = r.indexOfMunicipality(spot.location);
    if (i < 0) return _distanceFromStartKm(spot);
    var km = 0.0;
    for (var j = 0; j < i; j++) {
      km += roadDistanceKmBetween(
            r.municipalities[j].name,
            r.municipalities[j + 1].name,
          ) ??
          0;
    }
    return km;
  }

  double? _distanceFromStartKm(TouristSpot spot) {
    final s = start;
    if (s == null) return null;
    final road = roadDistanceKmBetween(s.name, spot.location);
    final c = getMunicipalityCoordinates(s);
    final p = _spotRoutePoint(spot);
    if (c == null || p == null) return road;
    final straight = haversineDistanceKm(
          c.latitude,
          c.longitude,
          p.latitude,
          p.longitude,
        ) *
        1.25;
    return road == null ? straight : math.max(straight, road);
  }

  /// Farther than this from its own town center, a spot's saved pin is
  /// treated as wrong and the town center is used for routing instead.
  static const double _maxSpotPinOffsetKm = 20;

  int? _roadIndexOf(Municipality m) =>
      roadTableIndexFor(m.name) ?? roadTableIndexFor(m.shortName);

  /// Point used to place [spot] on the route: its pin when that lies in its
  /// municipality, else the municipality's town center.
  LatLng? _spotRoutePoint(TouristSpot spot) {
    final center = roadTownCenterFor(spot.location);
    final lat = spot.latitude;
    final lng = spot.longitude;
    if (lat != null && lng != null) {
      if (center == null ||
          haversineDistanceKm(lat, lng, center.$1, center.$2) <=
              _maxSpotPinOffsetKm) {
        return LatLng(lat, lng);
      }
    }
    return center == null ? null : LatLng(center.$1, center.$2);
  }

  int get maxSpotsPerDay => absoluteMaxSpotsPerDay;

  /// Comfortable pace suggestion (same as the hard day cap).
  int get suggestedSpotsPerDay => absoluteMaxSpotsPerDay;

  /// Hard cap: each day can have at most 4 tourist spots.
  static const int absoluteMaxSpotsPerDay = 4;

  /// Load route spots, then open day assignment (step 2). Days start empty for
  /// a new route; the user adds spots (or taps Suggest plan) themselves.
  Future<void> goToItinerary() async {
    final err = tripInfoValidationError();
    if (err != null) throw StateError(err);
    step = TripWizardStep.itinerary;
    notifyListeners();
    await calculateRouteAndSuggestions();
    final routeKey = _routeKey;
    if (routeKey != _plannedRouteKey) {
      final onRoute = {for (final r in routeSuggestions) r.spot.name};
      selectedSpots.removeWhere((s) => !onRoute.contains(s.name));
      daySpotAssignments = List.generate(tripDays, (_) => <TouristSpot>[]);
      spotStartMinutesOverride.clear();
      _endedDays.clear();
      _userDayCount = tripDays;
      algorithmInsight = null;
      _plannedRouteKey = routeKey;
    } else {
      _ensureDayBuckets();
      _pruneDaysToSelected();
    }
    notifyListeners();
  }

  String? _plannedRouteKey;

  String get _routeKey =>
      '${start?.name}|${end?.name}|$tripDays|${selectedRouteDirection?.name}';

  /// Day count the user chose in step 1; days past it were added by the
  /// Nearest Neighbor flow and are removed again when no longer needed.
  int _userDayCount = 0;

  void goToReview() {
    final assigned = assignedSpotNames;
    if (assigned.isEmpty) {
      throw StateError('Add at least one spot to a day before reviewing.');
    }
    _pruneDaysToSelected();
    step = TripWizardStep.review;
    notifyListeners();
  }

  void goBack() {
    switch (step) {
      case TripWizardStep.tripInfo:
        break;
      case TripWizardStep.itinerary:
        step = TripWizardStep.tripInfo;
        break;
      case TripWizardStep.review:
        step = TripWizardStep.itinerary;
        break;
    }
    notifyListeners();
  }

  /// Default day start (minutes from midnight). Editable per day.
  final Map<int, int> dayStartMinutes = {};

  /// Optional user override for when a spot starts: key = `$dayIndex|${spot.name}`.
  final Map<String, int> spotStartMinutesOverride = {};

  int dayStartMinutesFor(int dayIndex) =>
      dayStartMinutes[dayIndex] ?? (8 * 60); // 8:00 AM

  void setDayStartMinutes(int dayIndex, int minutes) {
    dayStartMinutes[dayIndex] = minutes.clamp(0, 23 * 60 + 59);
    notifyListeners();
  }

  void setSpotStartOverride(int dayIndex, TouristSpot spot, int? minutes) {
    final key = '$dayIndex|${spot.name}';
    if (minutes == null) {
      spotStartMinutesOverride.remove(key);
    } else {
      spotStartMinutesOverride[key] = minutes.clamp(0, 23 * 60 + 59);
    }
    notifyListeners();
  }

  int? spotStartOverride(int dayIndex, TouristSpot spot) =>
      spotStartMinutesOverride['$dayIndex|${spot.name}'];

  /// Builds day buckets with [DayItineraryPlanner] (algorithms folder):
  /// Content-Based Filtering → Weighted Scoring → Greedy.
  Future<void> seedDayAssignments({bool forceRedistribute = false}) async {
    final days = tripDays;
    if (days < 1) {
      daySpotAssignments = [];
      algorithmInsight = null;
      return;
    }
    if (!forceRedistribute &&
        daySpotAssignments.length == days &&
        _dayAssignmentsOnlyContainSelected() &&
        daySpotAssignments.any((d) => d.isNotEmpty)) {
      _pruneDaysToSelected();
      return;
    }
    await _runAlgorithmDayPlan();
  }

  Future<void> _runAlgorithmDayPlan() async {
    final s = start;
    if (s == null || selectedSpots.isEmpty) {
      daySpotAssignments = List.generate(tripDays, (_) => <TouristSpot>[]);
      return;
    }

    loadingDayPlan = true;
    notifyListeners();
    try {
      final prefs = TripPreferencesStore.instance;
      final interestWeights = await prefs.loadInterestWeights();
      final ratedTypes = await prefs.loadRatedSpotTypeCounts();

      final routeMunis = municipalitiesOnRoute.isNotEmpty
          ? municipalitiesOnRoute
          : [
              ?start,
              ?end,
            ];
      final aliases = <String>{};
      for (final m in routeMunis) {
        aliases.addAll(municipalityAliases(m));
      }

      final plan = DayItineraryPlanner.build(
        selectedSpots: List<TouristSpot>.from(selectedSpots),
        interests: Set<String>.from(interests),
        interestWeights: interestWeights,
        ratedTypes: ratedTypes,
        budget: budgetPhp,
        transportMode: transportMode,
        tripDays: tripDays,
        start: s,
        municipalitiesOnRoute: routeMunis,
        routeAliases: aliases,
      );

      daySpotAssignments = [
        for (final day in plan.days) List<TouristSpot>.from(day),
      ];
      algorithmInsight = plan.insight;

      await prefs.recordTripInputs(
        transportMode: transportMode,
        interests: interests.toList(),
        budgetTierName: 'custom',
      );
    } catch (e, st) {
      debugPrint('DayItineraryPlanner failed: $e\n$st');
      daySpotAssignments = _fallbackDistribute(tripDays);
      algorithmInsight =
          'Algorithm unavailable - used a simple day split. You can still edit.';
    } finally {
      loadingDayPlan = false;
      notifyListeners();
    }
  }

  bool _dayAssignmentsOnlyContainSelected() {
    final names = selectedSpots.map((s) => s.name).toSet();
    for (final day in daySpotAssignments) {
      for (final s in day) {
        if (!names.contains(s.name)) return false;
      }
    }
    return true;
  }

  void _pruneDaysToSelected() {
    final names = selectedSpots.map((s) => s.name).toSet();
    for (final day in daySpotAssignments) {
      day.removeWhere((s) => !names.contains(s.name));
    }
  }

  /// Fallback only if the algorithm throws — keeps the UI usable.
  List<List<TouristSpot>> _fallbackDistribute(int days) {
    final buckets = List.generate(days, (_) => <TouristSpot>[]);
    if (selectedSpots.isEmpty) return buckets;
    final perDay = maxSpotsPerDay;
    var day = 0;
    for (final spot in selectedSpots) {
      while (day < days - 1 && buckets[day].length >= perDay) {
        day++;
      }
      buckets[day].add(spot);
    }
    return buckets;
  }

  void _removeSpotFromAllDays(TouristSpot spot) {
    for (final day in daySpotAssignments) {
      day.removeWhere((s) => s.name == spot.name);
    }
  }

  void _ensureDayBuckets() {
    final days = tripDays;
    if (daySpotAssignments.length == days) return;
    if (daySpotAssignments.isEmpty) {
      daySpotAssignments = List.generate(days, (_) => <TouristSpot>[]);
      return;
    }
    if (daySpotAssignments.length < days) {
      while (daySpotAssignments.length < days) {
        daySpotAssignments.add(<TouristSpot>[]);
      }
    } else {
      // Merge overflow days into earlier days without exceeding the per-day cap.
      final keep = daySpotAssignments.sublist(0, days);
      final overflow = <TouristSpot>[];
      for (var i = days; i < daySpotAssignments.length; i++) {
        overflow.addAll(daySpotAssignments[i]);
      }
      for (final spot in overflow) {
        var placed = false;
        for (final day in keep) {
          if (day.length >= absoluteMaxSpotsPerDay) continue;
          if (day.any((s) => s.name == spot.name)) {
            placed = true;
            break;
          }
          day.add(spot);
          placed = true;
          break;
        }
        // Unplaced spots stay in selectedSpots only (unassigned).
        if (!placed) {
          // already in selectedSpots
        }
      }
      daySpotAssignments = keep;
    }
  }

  /// Add [spot] to [dayIndex]. Moves it if it was on another day.
  /// Hard-stops at [absoluteMaxSpotsPerDay] (4) per day.
  String? assignSpotToDay(TouristSpot spot, int dayIndex) {
    _ensureDayBuckets();
    if (dayIndex < 0 || dayIndex >= daySpotAssignments.length) {
      return 'Invalid day.';
    }
    if (!isSelected(spot)) {
      selectedSpots.add(spot);
    }
    final day = daySpotAssignments[dayIndex];
    if (day.any((s) => s.name == spot.name)) {
      return 'Already on this day.';
    }
    if (day.length >= absoluteMaxSpotsPerDay) {
      return 'Day ${dayIndex + 1} already has $absoluteMaxSpotsPerDay spots. '
          'Move some to another day first.';
    }
    _removeSpotFromAllDays(spot);
    // An ended day keeps the user's chosen last spot at the end.
    if (isDayEnded(dayIndex) && day.isNotEmpty) {
      day.insert(day.length - 1, spot);
    } else {
      day.add(spot);
    }
    notifyListeners();
    return null;
  }

  /// Add a route / catalog spot onto a day (also adds to [selectedSpots] if needed).
  String? addCatalogSpotToDay(TouristSpot spot, int dayIndex) =>
      assignSpotToDay(spot, dayIndex);

  /// Move [spot] from its current day to [toDayIndex].
  String? moveSpotToDay(TouristSpot spot, int toDayIndex) =>
      assignSpotToDay(spot, toDayIndex);

  void removeSpotFromDay(TouristSpot spot, int dayIndex) {
    _ensureDayBuckets();
    if (dayIndex < 0 || dayIndex >= daySpotAssignments.length) return;
    daySpotAssignments[dayIndex].removeWhere((s) => s.name == spot.name);
    spotStartMinutesOverride.remove('$dayIndex|${spot.name}');
    if (daySpotAssignments[dayIndex].isEmpty) {
      _endedDays.remove(dayIndex);
      _trimAddedEmptyDays();
    }
    notifyListeners();
  }

  void moveSpotWithinDay(int dayIndex, int oldIndex, int newIndex) {
    _ensureDayBuckets();
    if (dayIndex < 0 || dayIndex >= daySpotAssignments.length) return;
    final day = daySpotAssignments[dayIndex];
    if (oldIndex < 0 || oldIndex >= day.length) return;
    var target = newIndex;
    if (target > oldIndex) target -= 1;
    if (target < 0 || target >= day.length) return;
    final item = day.removeAt(oldIndex);
    day.insert(target, item);
    notifyListeners();
  }

  Future<void> redistributeEvenly() => suggestRouteDayPlan();

  /// Nearest Neighbor plan over every route spot: Day 1 starts at the trip
  /// start, each day takes the closest unvisited spot until it holds
  /// [absoluteMaxSpotsPerDay], and the next day starts from its last spot.
  /// Days are added until every spot is visited.
  Future<void> suggestRouteDayPlan() async {
    loadingDayPlan = true;
    notifyListeners();
    try {
      if (routeSuggestions.isEmpty && start != null && end != null) {
        await calculateRouteAndSuggestions();
      }
      final from = _startPlace;
      if (from == null) return;

      final planned = _nearestNeighbor.planDays(
        start: from,
        spots: routeSpotPool,
        maxSpotsPerDay: absoluteMaxSpotsPerDay,
      );

      final userDays = _userDayCount > 0 ? _userDayCount : tripDays;
      final dayCount = math.max(planned.length, math.max(1, userDays));
      daySpotAssignments = [
        for (var d = 0; d < dayCount; d++)
          d < planned.length ? planned[d] : <TouristSpot>[],
      ];
      _endedDays
        ..clear()
        ..addAll([for (var d = 0; d < planned.length; d++) d]);
      spotStartMinutesOverride.clear();
      _setDayCount(dayCount);

      // Keep selectedSpots in sync with what's on the days.
      selectedSpots
        ..clear()
        ..addAll([for (final d in planned) ...d]);

      final total = selectedSpots.length;
      final added = planned.length - userDays;
      algorithmInsight = total == 0
          ? null
          : 'Planned all $total spots by nearest next stop over '
              '${planned.length} day${planned.length == 1 ? '' : 's'}. '
              'Each day starts where the previous day ended'
              '${added > 0 ? '; $added day${added == 1 ? ' was' : 's were'} added so every spot fits' : ''}.';
    } finally {
      loadingDayPlan = false;
      notifyListeners();
    }
  }

  void clearAllDayAssignments() {
    _ensureDayBuckets();
    for (final day in daySpotAssignments) {
      day.clear();
    }
    _endedDays.clear();
    _trimAddedEmptyDays();
    algorithmInsight = null;
    notifyListeners();
  }

  Future<void> calculateRouteAndSuggestions() async {
    final s = start;
    final e = end;
    if (s == null || e == null) return;

    loadingRoute = true;
    routeError = null;
    notifyListeners();

    final requestId = ++_routeRequestId;
    try {
      final route = await fetchRoadRoute(
        s,
        e,
        direction: selectedRouteDirection,
      );
      // A newer request (other start / end / direction) owns the results.
      if (requestId != _routeRequestId) return;
      roadRoute = route;
      // Only a real road polyline may filter spots by distance; a straight
      // fallback line cuts through the mountains and drops valid towns.
      final roadPoints = route != null && route.followsRoads
          ? route.polyline
          : const <LatLng>[];
      routePoints = route?.polyline ?? const [];
      if (route != null && !route.followsRoads) {
        debugPrint('calculateRouteAndSuggestions: no road polyline');
      }

      if (municipalitiesOnRoadBetween(s, e) == null && roadPoints.isNotEmpty) {
        municipalitiesOnRoute = municipalitiesAlongRoute(
          start: s,
          end: e,
          routePoints: roadPoints,
        );
      } else {
        municipalitiesOnRoute = route?.municipalities ?? [s, e];
      }

      routeSuggestions = _buildSuggestions(
        municipalitiesOnRoute,
        roadPoints,
      );
      _logRouteSpots(roadPoints.length);
    } catch (err, st) {
      debugPrint('calculateRouteAndSuggestions: $err\n$st');
      if (requestId != _routeRequestId) return;
      roadRoute = null;
      final byRoadTable = municipalitiesOnRoadBetween(
        s,
        e,
        direction: selectedRouteDirection,
      );
      if (byRoadTable == null) {
        routeError = 'Could not calculate the full road route. '
            'Showing spots near your start and end points.';
      }
      municipalitiesOnRoute = byRoadTable ?? [s, e];
      routeSuggestions = _buildSuggestions(municipalitiesOnRoute, const []);
      _logRouteSpots(0);
    } finally {
      if (requestId == _routeRequestId) {
        loadingRoute = false;
        notifyListeners();
        final along = municipalitiesOnRoute.map((m) => m.name).toList();
        unawaited(
          TripPreferencesStore.instance.recordRouteContext(
            startMunicipality: s.name,
            endMunicipality: e.name,
            alongMunicipalities: along,
          ),
        );
        if (selectedSpots.isNotEmpty) {
          unawaited(
            SpotInteractionHistoryStore.instance
                .recordItinerarySpots(selectedSpots),
          );
        }
      }
    }
  }

  int _routeRequestId = 0;

  void _logRouteSpots(int roadPointCount) {
    if (!kDebugMode) return;
    final shown = routeSuggestions.map((r) => r.spot.name).toSet();
    final skipped = [
      for (final spot in allSpots)
        if (!shown.contains(spot.name))
          '${spot.name} [${spot.location}]',
    ];
    debugPrint(
      'Route spots ${start?.name} -> ${end?.name}: ${shown.length} of '
      '${allSpots.length} loaded, road points: $roadPointCount, towns: '
      '${municipalitiesOnRoute.map((m) => m.shortName).join(', ')}\n'
      '  on route: ${shown.join('; ')}\n'
      '  not on route: ${skipped.join('; ')}',
    );
  }

  List<RouteSpotSuggestion> _buildSuggestions(
    List<Municipality> onRoute,
    List<LatLng> points,
  ) {
    final aliases = <String>{};
    for (final m in onRoute) {
      aliases.addAll(municipalityAliases(m));
    }

    final out = <RouteSpotSuggestion>[];
    for (final spot in allSpots) {
      final loc = normalizeMunicipalityName(spot.location);
      if (loc.isEmpty) continue;

      Municipality? muni;
      final spotIdx = roadTableIndexFor(spot.location);
      if (spotIdx != null) {
        for (final m in onRoute) {
          if (_roadIndexOf(m) == spotIdx) {
            muni = m;
            break;
          }
        }
      } else {
        final onCorridor = aliases.any(
          (a) =>
              a.isNotEmpty && (loc == a || loc.contains(a) || a.contains(loc)),
        );
        if (!onCorridor) continue;
        for (final m in onRoute) {
          if (municipalityAliases(m).any(
            (a) => loc == a || loc.contains(a) || a.contains(loc),
          )) {
            muni = m;
            break;
          }
        }
      }
      if (muni == null) continue;

      double distKm = 0;
      final p = _spotRoutePoint(spot);
      if (points.isNotEmpty && p != null) {
        distKm = _minDistanceToPolylineKm(p, points);
        if (distKm > 22) continue;
      }

      out.add(
        RouteSpotSuggestion(
          spot: spot,
          distanceFromRouteKm: distKm,
          municipality: muni,
        ),
      );
    }

    out.sort((a, b) {
      final interestA = _interestScore(a.spot);
      final interestB = _interestScore(b.spot);
      if (interestA != interestB) return interestB.compareTo(interestA);
      final d = a.distanceFromRouteKm.compareTo(b.distanceFromRouteKm);
      if (d != 0) return d;
      return b.spot.rating.compareTo(a.spot.rating);
    });
    return out;
  }

  int _interestScore(TouristSpot spot) {
    var score = 0;
    final type = spot.type.toLowerCase();
    final category = spot.category.toLowerCase();
    final desc = spot.description.toLowerCase();
    for (final i in interests) {
      final t = i.toLowerCase();
      if (category == t || category.contains(t) || t.contains(category)) {
        score += 4;
      }
      if (type.contains(t) || desc.contains(t) || t.contains(type)) {
        score += 3;
      }
      // Map common interest → spot type
      if (t == 'beaches' &&
          (type.contains('beach') || category.contains('beach'))) {
        score += 3;
      }
      if (t == 'nature' &&
          (type.contains('nature') ||
              type.contains('adventure') ||
              category.contains('nature'))) {
        score += 2;
      }
      if (t == 'food' &&
          (type.contains('food') ||
              type.contains('relaxation') ||
              category.contains('food'))) {
        score += 2;
      }
      if (t == 'historical places' &&
          (type.contains('histor') || category.contains('histor'))) {
        score += 3;
      }
      if (t == 'culture' &&
          (type.contains('cultur') || category.contains('cultur'))) {
        score += 2;
      }
    }
    return score;
  }

  List<RouteSpotSuggestion> get visibleSuggestions {
    var list = List<RouteSpotSuggestion>.from(routeSuggestions);

    // Prefer interest matches first; "show more" reveals the rest.
    if (!showAllNearby) {
      final preferred = list.where((s) => _interestScore(s.spot) > 0).toList();
      if (preferred.isNotEmpty) list = preferred;
    }

    return list;
  }

  /// Spots not on corridor - for manual "Add another stop".
  List<TouristSpot> get offRouteSpotsForPicker {
    final selectedNames = selectedSpots.map((s) => s.name).toSet();
    final onRouteNames = routeSuggestions.map((s) => s.spot.name).toSet();
    return allSpots
        .where(
          (s) =>
              !selectedNames.contains(s.name) && !onRouteNames.contains(s.name),
        )
        .toList()
      ..sort((a, b) => a.name.compareTo(b.name));
  }

  TouristRouteEstimate get routeEstimate => buildRouteEstimate(
        orderedStops: selectedSpots,
        mode: transportMode,
        tourists: travelers,
      );

  int get entranceFeesTotal {
    final per = selectedSpots.fold<int>(
      0,
      (sum, s) => sum + parseSpotEntranceFee(s),
    );
    return per * travelers;
  }

  int get foodEstimatePhp {
    // Soft estimate from spot food fields or ₱250/person/day as fallback.
    var fromSpots = 0;
    for (final s in selectedSpots) {
      final v = parsePesoAmountFromText(s.foodAndDrinksPrice);
      if (v != null) fromSpots += v.round();
    }
    if (fromSpots > 0) return fromSpots * travelers;
    return 250 * travelers * tripDays;
  }

  int get activityEstimatePhp {
    var fromSpots = 0;
    for (final s in selectedSpots) {
      final v = parsePesoAmountFromText(s.otherSouvenirsPrice);
      if (v != null) fromSpots += v.round();
    }
    return fromSpots * travelers;
  }

  int get accommodationEstimatePhp {
    if (!needsAccommodation) return 0;
    // Soft provincial mid-range estimate when hotels not selected.
    final hasHotel = selectedSpots.any((s) => s.isHotel);
    if (hasHotel) {
      return selectedSpots
              .where((s) => s.isHotel)
              .fold<int>(0, (sum, s) {
            final v = parsePesoAmountFromText(s.priceRange) ?? 1500;
            return sum + v.round();
          }) *
          nights;
    }
    return (1200 * nights * ((travelers + 1) ~/ 2));
  }

  int get transportTotalPhp => routeEstimate.totalTransportFeePhp;

  int get estimatedTotalPhp =>
      transportTotalPhp +
      entranceFeesTotal +
      foodEstimatePhp +
      activityEstimatePhp +
      accommodationEstimatePhp;

  bool get overBudget => estimatedTotalPhp > budgetPhp.round();

  double get budgetUsageRatio {
    if (budgetPhp <= 0) return 1;
    return estimatedTotalPhp / budgetPhp;
  }

  /// Spots the user assigned to each day.
  List<List<TouristSpot>> get spotsByDay {
    final days = tripDays;
    if (days < 1) return const [];
    if (daySpotAssignments.length == days) {
      return [
        for (final day in daySpotAssignments) List<TouristSpot>.from(day),
      ];
    }
    // Length mismatch (e.g. dates changed mid-flow) — show a safe view.
    if (daySpotAssignments.isEmpty) {
      return List.generate(days, (_) => <TouristSpot>[]);
    }
    final copy = [
      for (final day in daySpotAssignments) List<TouristSpot>.from(day),
    ];
    while (copy.length < days) {
      copy.add(<TouristSpot>[]);
    }
    if (copy.length > days) {
      for (var i = days; i < copy.length; i++) {
        copy[days - 1].addAll(copy[i]);
      }
      return copy.sublist(0, days);
    }
    return copy;
  }

  int dayTotalMinutes(int dayIndex) {
    final spots = spotsByDay[dayIndex];
    var total = 0;
    for (final s in spots) {
      total += estimatedStayMinutes(s);
    }
    if (spots.length >= 2) {
      total += buildRouteEstimate(
        orderedStops: spots,
        mode: transportMode,
        tourists: travelers,
      ).totalTravelMinutes;
    }
    return total;
  }

  TouristRouteEstimate dayRouteEstimate(int dayIndex) {
    final spots = spotsByDay[dayIndex];
    if (spots.isEmpty) {
      return buildRouteEstimate(
        orderedStops: const [],
        mode: transportMode,
        tourists: travelers,
      );
    }
    return buildRouteEstimate(
      orderedStops: spots,
      mode: transportMode,
      tourists: travelers,
    );
  }

  int dayActivityMinutes(int dayIndex) {
    var total = 0;
    for (final s in spotsByDay[dayIndex]) {
      total += estimatedStayMinutes(s);
    }
    return total;
  }

  int dayEntranceFeesPhp(int dayIndex) {
    final per = spotsByDay[dayIndex].fold<int>(
      0,
      (sum, s) => sum + parseSpotEntranceFee(s),
    );
    return per * travelers;
  }

  int dayEstimatedExpensePhp(int dayIndex) {
    final route = dayRouteEstimate(dayIndex);
    final foodShare = tripDays > 0 ? (foodEstimatePhp / tripDays).round() : 0;
    return route.totalTransportFeePhp +
        dayEntranceFeesPhp(dayIndex) +
        foodShare;
  }

  int get assignedSpotCount {
    var n = 0;
    for (final d in daySpotAssignments) {
      n += d.length;
    }
    return n;
  }

  int get totalAssignedTravelMinutes {
    var n = 0;
    for (var i = 0; i < tripDays; i++) {
      n += dayRouteEstimate(i).totalTravelMinutes;
    }
    return n;
  }

  double get totalAssignedDistanceKm {
    var n = 0.0;
    for (var i = 0; i < tripDays; i++) {
      n += dayRouteEstimate(i).totalDistanceKm;
    }
    return n;
  }

  int get totalAssignedTransportPhp {
    var n = 0;
    for (var i = 0; i < tripDays; i++) {
      n += dayRouteEstimate(i).totalTransportFeePhp;
    }
    return n;
  }

  /// Suggested visit start times for a day (minutes from midnight).
  /// Uses overrides when set; otherwise chains stay + travel from day start.
  List<int> suggestedStartMinutesForDay(int dayIndex) {
    final spots = spotsByDay[dayIndex];
    final out = <int>[];
    var cursor = dayStartMinutesFor(dayIndex);
    for (var i = 0; i < spots.length; i++) {
      final override = spotStartOverride(dayIndex, spots[i]);
      final start = override ?? cursor;
      out.add(start);
      final stay = estimatedStayMinutes(spots[i]);
      var next = start + stay;
      if (i < spots.length - 1) {
        final leg = buildRouteEstimate(
          orderedStops: [spots[i], spots[i + 1]],
          mode: transportMode,
          tourists: travelers,
        );
        if (leg.legs.isNotEmpty) {
          next += leg.legs.first.travelMinutes;
        }
        // Soft 15-min buffer between stops when no override on next.
        next += 15;
      }
      cursor = next;
    }
    return out;
  }

  static double _minDistanceToPolylineKm(LatLng p, List<LatLng> line) {
    var best = double.infinity;
    for (final q in line) {
      final km = haversineDistanceKm(
        p.latitude,
        p.longitude,
        q.latitude,
        q.longitude,
      );
      if (km < best) best = km;
    }
    return best;
  }
}

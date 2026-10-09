/// Nearest Neighbor Algorithm — builds an itinerary by always moving to the
/// closest spot that has not been visited yet.
///
/// Days chain together: Day 1 starts at the trip's starting point, and every
/// later day starts at the last spot of the day before it. There is no limit
/// on the number of days; planning stops only when every spot is visited.
///
/// Generic over the spot type [T] and the location type [L] so it can use the
/// app's own distance calculation (see [distanceKm]).
class NearestNeighborItinerary<T, L> {
  /// Unique key of a spot (used for the global visited list).
  final String Function(T spot) keyOf;

  /// Travel distance in km from [from] to [spot], or null when unknown.
  /// Unknown distances rank after every known one but are still visited.
  final double? Function(L from, T spot) distanceKm;

  /// The location of [spot], used as the next "current location".
  final L Function(T spot) locationOf;

  const NearestNeighborItinerary({
    required this.keyOf,
    required this.distanceKm,
    required this.locationOf,
  });

  /// Unvisited [candidates] ordered nearest-first from [from]. Spots whose key
  /// is in [visited] are never returned.
  List<T> rankUnvisited({
    required L from,
    required Iterable<T> candidates,
    required Set<String> visited,
  }) {
    final seen = <String>{};
    final ranked = <({T spot, double km})>[];
    for (final s in candidates) {
      final key = keyOf(s);
      if (visited.contains(key) || !seen.add(key)) continue;
      ranked.add((spot: s, km: distanceKm(from, s) ?? double.infinity));
    }
    ranked.sort((a, b) => a.km.compareTo(b.km));
    return [for (final r in ranked) r.spot];
  }

  /// Closest unvisited spot from [from], or null when all are visited.
  T? nearestUnvisited({
    required L from,
    required Iterable<T> candidates,
    required Set<String> visited,
  }) {
    final ranked =
        rankUnvisited(from: from, candidates: candidates, visited: visited);
    return ranked.isEmpty ? null : ranked.first;
  }

  /// Plans every day until all [spots] are visited.
  ///
  /// ```
  /// currentLocation = start; visited = {}
  /// while unvisited spots remain:
  ///   new day
  ///   while the day is not ended and unvisited spots remain:
  ///     add the nearest unvisited spot, mark it visited, move there
  ///   currentLocation = the day's last spot   (next day starts here)
  /// ```
  ///
  /// [endDay] decides when a day ends, given the spots chosen so far that
  /// day; by default a day ends after [maxSpotsPerDay] spots. [visited] holds
  /// spots already planned elsewhere, which are skipped.
  List<List<T>> planDays({
    required L start,
    required List<T> spots,
    int maxSpotsPerDay = 4,
    bool Function(List<T> day)? endDay,
    Set<String>? visited,
  }) {
    final done = <String>{...?visited};
    final shouldEnd = endDay ??
        (List<T> day) => maxSpotsPerDay > 0 && day.length >= maxSpotsPerDay;
    bool hasUnvisited() => spots.any((s) => !done.contains(keyOf(s)));

    final days = <List<T>>[];
    var current = start;
    while (hasUnvisited()) {
      final day = <T>[];
      while (!shouldEnd(day) && hasUnvisited()) {
        final next =
            nearestUnvisited(from: current, candidates: spots, visited: done);
        if (next == null) break;
        day.add(next);
        done.add(keyOf(next));
        current = locationOf(next);
      }
      if (day.isEmpty) break;
      days.add(day);
    }
    return days;
  }
}

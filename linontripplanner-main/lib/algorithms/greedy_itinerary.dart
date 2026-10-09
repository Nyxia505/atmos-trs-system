import 'dart:math' as math;

import '../data.dart';
import '../municipality_coordinates.dart' show getMunicipalityCoordinates;
import 'trip_algorithm_models.dart';

/// Greedy Algorithm — locally optimal stop selection along the route.
class GreedyItinerary {
  static double _haversineKm(double lat1, double lon1, double lat2, double lon2) {
    const r = 6371.0;
    final dLat = _deg(lat2 - lat1);
    final dLon = _deg(lon2 - lon1);
    final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(_deg(lat1)) *
            math.cos(_deg(lat2)) *
            math.sin(dLon / 2) *
            math.sin(dLon / 2);
    return 2 * r * math.asin(math.sqrt(a.clamp(0.0, 1.0)));
  }

  static double _deg(double d) => d * 0.017453292519943295;

  static LatLngPair? _spotPos(
    ScoredSpotData item,
    Map<String, LatLngPair> coords,
  ) {
    final s = item.spot;
    if (s.latitude != null && s.longitude != null) {
      return (lat: s.latitude!, lng: s.longitude!);
    }
    final loc = s.location.toLowerCase();
    for (final e in coords.entries) {
      if (e.key.toLowerCase().contains(loc) ||
          loc.contains(e.key.toLowerCase())) {
        return e.value;
      }
    }
    return null;
  }

  static bool _inMuni(String location, List<String> aliases) {
    final loc = location.toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
    return aliases.any((a) => loc.contains(a) || a.contains(loc));
  }

  static List<ScoredSpotData> build({
    required List<ScoredSpotData> scored,
    required List<String> municipalitiesRoute,
    required Set<String> routeAliases,
    required int maxTotal,
    required LatLngPair start,
    required Map<String, LatLngPair> municipalityCoords,
  }) {
    if (maxTotal <= 0 || scored.isEmpty) return [];

    final used = <String>{};
    final itinerary = <ScoredSpotData>[];
    final aliasList = routeAliases.map((a) => a.toLowerCase()).toList();

    for (final muni in municipalitiesRoute) {
      if (itinerary.length >= maxTotal) break;
      var aliases = aliasList
          .where((a) => muni.toLowerCase().contains(a) || a.contains(muni.toLowerCase()))
          .toList();
      if (aliases.isEmpty) aliases = [muni.toLowerCase()];

      final local = scored
          .where(
            (s) =>
                !used.contains(s.key) &&
                _inMuni(s.spot.location, aliases),
          )
          .toList()
        ..sort((a, b) => b.weightedScore.compareTo(a.weightedScore));

      if (local.isEmpty) continue;
      used.add(local.first.key);
      itinerary.add(local.first);
    }

    var current = start;
    var remaining =
        scored.where((s) => !used.contains(s.key)).toList();

    while (itinerary.length < maxTotal && remaining.isNotEmpty) {
      ScoredSpotData? best;
      var bestValue = -1.0;
      for (final s in remaining) {
        final pos = _spotPos(s, municipalityCoords);
        final dist = pos != null
            ? _haversineKm(current.lat, current.lng, pos.lat, pos.lng)
            : 25.0;
        final value = s.weightedScore / dist.clamp(0.5, double.infinity);
        if (value > bestValue) {
          bestValue = value;
          best = s;
        }
      }
      if (best == null) break;
      used.add(best.key);
      itinerary.add(best);
      remaining = remaining.where((s) => !used.contains(s.key)).toList();
      final pos = _spotPos(best, municipalityCoords);
      if (pos != null) current = pos;
    }

    return itinerary.take(maxTotal).toList();
  }

  static Map<String, LatLngPair> coordsFromMunicipalities(
    List<Municipality> municipalities,
  ) {
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
}

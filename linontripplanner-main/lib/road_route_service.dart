import 'package:google_maps_flutter/google_maps_flutter.dart' show LatLng;

import 'data.dart';
import 'directions_service.dart';
import 'municipal_road_distances.dart';
import 'municipality_bus_terminals.dart' show haversineDistanceKm;
import 'municipality_coordinates.dart';

/// A stop on a road route: [place] is a municipality name or spot location
/// (used to find the towns in between), [point] is where the stop is.
typedef RoadStop = ({String place, LatLng point});

/// Start → end trip route on the road network: towns in driving order, the
/// road polyline through them, and the routing service's distance / time.
class RoadRoute {
  final List<Municipality> municipalities;
  final List<LatLng> polyline;

  /// False when the routing service failed and [polyline] only joins the
  /// town centers.
  final bool followsRoads;
  final double distanceKm;
  final int drivingMinutes;
  final List<double> _cumulativeKm;

  RoadRoute._({
    required this.municipalities,
    required this.polyline,
    required this.followsRoads,
    required this.distanceKm,
    required this.drivingMinutes,
  }) : _cumulativeKm = _cumulative(polyline);

  static List<double> _cumulative(List<LatLng> line) {
    final out = List<double>.filled(line.length, 0);
    for (var i = 1; i < line.length; i++) {
      out[i] = out[i - 1] +
          haversineDistanceKm(
            line[i - 1].latitude,
            line[i - 1].longitude,
            line[i].latitude,
            line[i].longitude,
          );
    }
    return out;
  }

  /// Km along the polyline from the start to the point closest to [p], scaled
  /// to [distanceKm] so it matches the reported road distance.
  double progressKmAt(LatLng p) {
    if (polyline.isEmpty) return 0;
    var best = 0;
    var bestD = double.infinity;
    for (var i = 0; i < polyline.length; i++) {
      final d = haversineDistanceKm(
        p.latitude,
        p.longitude,
        polyline[i].latitude,
        polyline[i].longitude,
      );
      if (d < bestD) {
        bestD = d;
        best = i;
      }
    }
    final lineKm = _cumulativeKm.last;
    if (lineKm <= 0) return 0;
    return _cumulativeKm[best] / lineKm * distanceKm;
  }

  /// Index in [municipalities] of the town matching [nameOrLocation], or -1.
  int indexOfMunicipality(String nameOrLocation) {
    final idx = roadTableIndexFor(nameOrLocation);
    if (idx == null) return -1;
    for (var i = 0; i < municipalities.length; i++) {
      final m = municipalities[i];
      if ((roadTableIndexFor(m.name) ?? roadTableIndexFor(m.shortName)) ==
          idx) {
        return i;
      }
    }
    return -1;
  }
}

LatLng? _townPoint(String nameOrLocation) {
  final c = roadTownCenterFor(nameOrLocation);
  return c == null ? null : LatLng(c.$1, c.$2);
}

/// [stops] with the center of every town the road passes between consecutive
/// stops inserted, so a routing request follows the road network through
/// those towns instead of taking a shortcut. [direction] picks which way
/// around the provincial loop to go.
List<LatLng> roadWaypointsForStops(
  List<RoadStop> stops, {
  RoadRouteDirection? direction,
}) {
  if (stops.isEmpty) return const [];
  final out = <LatLng>[stops.first.point];
  for (var i = 1; i < stops.length; i++) {
    final towns = roadTownsBetween(
      stops[i - 1].place,
      stops[i].place,
      direction: direction,
    );
    for (final town in towns) {
      final p = _townPoint(town);
      if (p != null) out.add(p);
    }
    out.add(stops[i].point);
  }
  return out;
}

final Map<String, DirectionsResult> _roadRouteCache = {};
final Map<String, Future<DirectionsResult>> _roadRouteInFlight = {};

String _roadRouteCacheKey(List<LatLng> waypoints) => waypoints
    .map((p) => '${p.latitude.toStringAsFixed(5)},${p.longitude.toStringAsFixed(5)}')
    .join(';');

void _rememberRoadRoute(String key, DirectionsResult result) {
  if (result.polyline == null || result.polyline!.length < 2) return;
  if (_roadRouteCache.length >= 80 && !_roadRouteCache.containsKey(key)) {
    _roadRouteCache.remove(_roadRouteCache.keys.first);
  }
  _roadRouteCache[key] = result;
}

/// Road polyline (plus distance / time) through [stops] and every town between
/// them on the road network.
Future<DirectionsResult> getRoadRouteThroughStops(
  List<RoadStop> stops, {
  RoadRouteDirection? direction,
}) async {
  final waypoints = roadWaypointsForStops(stops, direction: direction);
  final key = _roadRouteCacheKey(waypoints);
  final cached = _roadRouteCache[key];
  if (cached != null) return cached;
  final pending = _roadRouteInFlight[key];
  if (pending != null) return pending;
  final future = getDirectionsRoute(waypoints);
  _roadRouteInFlight[key] = future;
  try {
    final result = await future;
    _rememberRoadRoute(key, result);
    return result;
  } finally {
    if (identical(_roadRouteInFlight[key], future)) {
      _roadRouteInFlight.remove(key);
    }
  }
}

/// Shortest valid road path between each consecutive pair in [stops], joined
/// into one line. A chosen [direction] is required for every leg; this never
/// substitutes the other way around the province, and it never returns a
/// straight line when a leg has no road geometry.
Future<DirectionsResult> getOrderedRoadRoute(
  List<RoadStop> stops, {
  RoadRouteDirection? direction,
}) async {
  if (stops.length < 2) {
    return const DirectionsResult(
      errorStatus: 'NO_ROUTE',
      errorMessage: 'Not enough stops for a road route.',
    );
  }
  final merged = <LatLng>[];
  var meters = 0.0;
  var seconds = 0.0;
  var haveMeters = true;
  var haveSeconds = true;
  for (var i = 0; i < stops.length - 1; i++) {
    final from = stops[i];
    final to = stops[i + 1];
    final fromIdx = roadTableIndexFor(from.place);
    final toIdx = roadTableIndexFor(to.place);
    if (direction != null &&
        fromIdx != null &&
        toIdx != null &&
        fromIdx != toIdx &&
        !hasRoadPathBetween(from.place, to.place, direction: direction)) {
      final way = direction.name;
      return DirectionsResult(
        errorStatus: 'NO_ROUTE',
        errorMessage:
            'No valid $way road route from ${from.place} to ${to.place}.',
      );
    }
    final leg = await getRoadRouteThroughStops(
      [from, to],
      direction: direction,
    );
    final segment = leg.polyline;
    if (segment == null || segment.length < 2) {
      return DirectionsResult(
        errorStatus: leg.errorStatus ?? 'NO_ROUTE',
        errorMessage: leg.errorMessage ??
            'No valid road route from ${from.place} to ${to.place}.',
      );
    }
    if (merged.isEmpty) {
      merged.addAll(segment);
    } else {
      merged.addAll(segment.skip(1));
    }
    if (leg.distanceMeters == null) {
      haveMeters = false;
    } else {
      meters += leg.distanceMeters!;
    }
    if (leg.durationSeconds == null) {
      haveSeconds = false;
    } else {
      seconds += leg.durationSeconds!;
    }
  }
  return DirectionsResult(
    polyline: merged,
    distanceMeters: haveMeters ? meters : null,
    durationSeconds: haveSeconds ? seconds : null,
  );
}

/// Computes the road route from [start] to [end], going [direction] around
/// the provincial loop when given. Returns null when either municipality has
/// no coordinates.
Future<RoadRoute?> fetchRoadRoute(
  Municipality start,
  Municipality end, {
  RoadRouteDirection? direction,
}) async {
  final startPoint = getMunicipalityCoordinates(start);
  final endPoint = getMunicipalityCoordinates(end);
  if (startPoint == null || endPoint == null) return null;

  final towns =
      municipalitiesOnRoadBetween(start, end, direction: direction) ??
      [start, end];
  final waypoints = <LatLng>[
    startPoint,
    for (final m in towns.sublist(1, towns.length - 1))
      ?(_townPoint(m.name) ?? getMunicipalityCoordinates(m)),
    endPoint,
  ];

  final directions = await getDirectionsRoute(waypoints);
  final line = directions.polyline;
  final followsRoads = line != null && line.length >= 2;

  double? tableKm;
  int? tableMin;
  for (var i = 0; i < towns.length - 1; i++) {
    final km = roadDistanceKmBetween(towns[i].name, towns[i + 1].name);
    final min = roadDrivingMinutesBetween(towns[i].name, towns[i + 1].name);
    if (km == null || min == null) {
      tableKm = null;
      tableMin = null;
      break;
    }
    tableKm = (tableKm ?? 0) + km;
    tableMin = (tableMin ?? 0) + min;
  }
  final polyline = followsRoads ? line : waypoints;
  final km = directions.distanceMeters != null
      ? directions.distanceMeters! / 1000
      : tableKm ?? RoadRoute._cumulative(polyline).last;
  final minutes = directions.durationSeconds != null
      ? (directions.durationSeconds! / 60).round()
      : tableMin ?? (km / 40 * 60).round();

  return RoadRoute._(
    municipalities: towns,
    polyline: polyline,
    followsRoads: followsRoads,
    distanceKm: km,
    drivingMinutes: minutes,
  );
}

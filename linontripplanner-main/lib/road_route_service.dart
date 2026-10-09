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

/// Road polyline (plus distance / time) through [stops] and every town between
/// them on the road network.
Future<DirectionsResult> getRoadRouteThroughStops(
  List<RoadStop> stops, {
  RoadRouteDirection? direction,
}) {
  return getDirectionsRoute(
    roadWaypointsForStops(stops, direction: direction),
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

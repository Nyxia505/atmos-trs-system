import 'dart:convert';

import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:http/http.dart' as http;

import '../data.dart';
import '../municipal_road_distances.dart';
import '../municipality_coordinates.dart';
import '../road_route_service.dart';

/// Day visit orders produced by nearest-neighbor search on road distance.
class RoadItineraryOrder {
  final List<List<TouristSpot>> days;

  /// Empty when every unlocked day was ordered from a valid road distance.
  final String? error;

  const RoadItineraryOrder({required this.days, this.error});
}

/// Orders each day's selected spots by the nearest unvisited stop, measured
/// with the routing service (road distance), not straight-line distance.
///
/// Day 1 starts at [start]. Each later day starts at the previous day's last
/// spot. Days in [lockedDays] keep the user's order. A name in
/// [lockedEndSpotNames] stays the last stop of that day. Spots are never
/// moved onto a different day.
Future<RoadItineraryOrder> orderDaysByRoadNearestNeighbor({
  required Municipality start,
  required List<List<TouristSpot>> days,
  Set<int> lockedDays = const {},
  Map<int, String> lockedEndSpotNames = const {},
  RoadRouteDirection? direction,
}) async {
  final startPoint = getMunicipalityCoordinates(start);
  if (startPoint == null) {
    return RoadItineraryOrder(
      days: [for (final day in days) List<TouristSpot>.from(day)],
      error: 'No coordinates are saved for ${start.name}.',
    );
  }

  final orderedDays = <List<TouristSpot>>[];
  final errors = <String>[];
  var cursor = (
    place: start.name,
    point: startPoint,
    label: start.shortName.isNotEmpty ? start.shortName : start.name,
  );

  for (var dayIndex = 0; dayIndex < days.length; dayIndex++) {
    final day = List<TouristSpot>.from(days[dayIndex]);
    if (day.isEmpty) {
      orderedDays.add(day);
      continue;
    }
    if (lockedDays.contains(dayIndex)) {
      orderedDays.add(day);
      cursor = _cursorAfter(day, cursor);
      continue;
    }

    final lockedEndName = lockedEndSpotNames[dayIndex];
    TouristSpot? lockedEnd;
    final free = <TouristSpot>[];
    for (final spot in day) {
      if (lockedEnd == null &&
          lockedEndName != null &&
          spot.name == lockedEndName) {
        lockedEnd = spot;
      } else {
        free.add(spot);
      }
    }

    final located = <TouristSpot>[];
    final missing = <TouristSpot>[];
    for (final spot in free) {
      if (_spotPoint(spot) == null) {
        missing.add(spot);
      } else {
        located.add(spot);
      }
    }

    final orderedFree = <TouristSpot>[];
    if (located.isNotEmpty) {
      final step = await _orderByRoad(
        fromPlace: cursor.place,
        fromPoint: cursor.point,
        spots: located,
        direction: direction,
      );
      orderedFree.addAll(step.ordered);
      if (step.unreachable.isNotEmpty) {
        orderedFree.addAll(step.unreachable);
        errors.add(_dayRouteError(direction, dayIndex));
      }
    }
    orderedFree.addAll(missing);
    if (missing.isNotEmpty) {
      final names = missing.map((s) => s.name).join(', ');
      errors.add('No coordinates are saved for $names.');
    }

    final ordered = <TouristSpot>[...orderedFree];
    if (lockedEnd != null) {
      ordered.add(lockedEnd);
      if (_spotPoint(lockedEnd) == null) {
        errors.add('No coordinates are saved for ${lockedEnd.name}.');
      }
    }
    for (final spot in day) {
      if (!ordered.any((s) => s.name == spot.name)) ordered.add(spot);
    }
    orderedDays.add(ordered);
    cursor = _cursorAfter(ordered, cursor);
  }

  return RoadItineraryOrder(
    days: orderedDays,
    error: errors.isEmpty ? null : errors.join(' '),
  );
}

class _RoadOrderStep {
  final List<TouristSpot> ordered;
  final List<TouristSpot> unreachable;
  const _RoadOrderStep({required this.ordered, required this.unreachable});
}

Future<_RoadOrderStep> _orderByRoad({
  required String fromPlace,
  required LatLng fromPoint,
  required List<TouristSpot> spots,
  required RoadRouteDirection? direction,
}) async {
  final points = <LatLng>[
    fromPoint,
    for (final spot in spots) _spotPoint(spot)!,
  ];
  List<List<double?>>? matrix;
  if (direction == null) {
    matrix = await _osrmDistanceMatrix(points);
  }

  final remaining = <int>{for (var i = 0; i < spots.length; i++) i};
  final ordered = <TouristSpot>[];
  final unreachable = <TouristSpot>[];
  var fromIndex = 0;
  var place = fromPlace;

  while (remaining.isNotEmpty) {
    int? best;
    var bestMeters = double.infinity;
    for (final i in remaining) {
      final meters = matrix != null
          ? _matrixMeters(matrix, fromIndex, i + 1)
          : await roadMetersBetween(
              fromPlace: place,
              fromPoint: points[fromIndex],
              toPlace: spots[i].location,
              toPoint: points[i + 1],
              direction: direction,
            );
      if (meters == null) continue;
      if (best == null || meters < bestMeters) {
        best = i;
        bestMeters = meters;
      }
    }
    if (best == null) {
      final leftover = remaining.toList()..sort();
      unreachable.addAll(leftover.map((i) => spots[i]));
      break;
    }
    remaining.remove(best);
    ordered.add(spots[best]);
    fromIndex = best + 1;
    place = spots[best].location;
  }
  return _RoadOrderStep(ordered: ordered, unreachable: unreachable);
}

double? _matrixMeters(List<List<double?>> matrix, int from, int to) {
  if (from < 0 || from >= matrix.length) return null;
  final row = matrix[from];
  if (to < 0 || to >= row.length) return null;
  final meters = row[to];
  if (meters == null || meters.isNaN || meters.isInfinite) return null;
  return meters;
}

/// Road distance from the routing service. Null when that service has no
/// valid road path, including when [direction] cannot connect the two places.
Future<double?> roadMetersBetween({
  required String fromPlace,
  required LatLng fromPoint,
  required String toPlace,
  required LatLng toPoint,
  required RoadRouteDirection? direction,
}) async {
  final fromIdx = roadTableIndexFor(fromPlace);
  final toIdx = roadTableIndexFor(toPlace);
  if (direction != null &&
      fromIdx != null &&
      toIdx != null &&
      fromIdx != toIdx &&
      !hasRoadPathBetween(fromPlace, toPlace, direction: direction)) {
    return null;
  }
  final result = await getRoadRouteThroughStops(
    [
      (place: fromPlace, point: fromPoint),
      (place: toPlace, point: toPoint),
    ],
    direction: direction,
  );
  final meters = result.distanceMeters;
  if (result.polyline == null ||
      result.polyline!.length < 2 ||
      meters == null ||
      meters.isNaN ||
      meters.isInfinite) {
    return null;
  }
  return meters;
}

Future<List<List<double?>>?> _osrmDistanceMatrix(List<LatLng> points) async {
  if (points.length < 2) return null;
  final coords = points.map((p) => '${p.longitude},${p.latitude}').join(';');
  final uri = Uri.parse(
    'https://router.project-osrm.org/table/v1/driving/$coords?annotations=distance',
  );
  try {
    final response = await http.get(uri).timeout(const Duration(seconds: 20));
    final map = jsonDecode(response.body);
    if (map is! Map || map['code'] != 'Ok') return null;
    final rows = map['distances'];
    if (rows is! List || rows.length != points.length) return null;
    final matrix = <List<double?>>[];
    for (final row in rows) {
      if (row is! List || row.length != points.length) return null;
      matrix.add([
        for (final cell in row)
          cell == null ? null : (cell as num).toDouble(),
      ]);
    }
    return matrix;
  } catch (_) {
    return null;
  }
}

LatLng? _spotPoint(TouristSpot spot) {
  final lat = spot.latitude;
  final lng = spot.longitude;
  if (lat == null || lng == null) return null;
  return LatLng(lat, lng);
}

({String place, LatLng point, String label}) _cursorAfter(
  List<TouristSpot> day,
  ({String place, LatLng point, String label}) cursor,
) {
  for (final spot in day.reversed) {
    final point = _spotPoint(spot);
    if (point == null) continue;
    return (place: spot.location, point: point, label: spot.name);
  }
  return cursor;
}

String _dayRouteError(RoadRouteDirection? direction, int dayIndex) {
  final which = direction == null ? '' : '${direction.name} ';
  return 'No valid ${which}road route was found for Day ${dayIndex + 1}.';
}

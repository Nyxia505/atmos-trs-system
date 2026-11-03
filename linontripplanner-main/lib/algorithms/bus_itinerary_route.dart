import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../data.dart';
import '../itinerary_transport_service.dart';
import '../municipal_road_distances.dart';
import '../municipality_coordinates.dart';
import '../services/bus_location_store.dart';
import 'road_nearest_neighbor.dart';

/// One point on the itinerary map: the day's start, a bus stop/terminal, or a spot.
class ItineraryRouteNode {
  final LatLng point;
  final String place;
  final String label;
  final String detail;

  /// `stop` or `terminal` when this node is a bus location.
  final String? busKind;
  final TouristSpot? spot;

  /// False after a missing bus connection. Those points stay on the map but
  /// are not joined by a road line.
  final bool onRoad;

  const ItineraryRouteNode({
    required this.point,
    required this.place,
    required this.label,
    required this.detail,
    this.busKind,
    this.spot,
    this.onRoad = true,
  });

  bool get isBus => busKind != null;
}

class BusDayRoute {
  final List<ItineraryRouteNode> nodes;
  final List<TouristSpot> spots;

  const BusDayRoute({required this.nodes, required this.spots});
}

class BusItineraryPlan {
  final List<BusDayRoute> days;
  final String? error;

  const BusItineraryPlan({required this.days, this.error});
}

/// Builds each day's tourist road sequence (start → spots by nearest road).
///
/// Bus stops/terminals may still appear as [ItineraryRouteNode]s for map
/// guidance and fare/timeline context, but they use [ItineraryRouteNode.onRoad]
/// `false` so they are **not** mandatory polyline waypoints.
/// Spot order inside a municipality uses nearest neighbor. Locked days keep
/// the user's spot order.
Future<BusItineraryPlan> buildBusItineraryPlan({
  required Municipality start,
  required List<List<TouristSpot>> days,
  Set<int> lockedDays = const {},
  Map<int, String> lockedEndSpotNames = const {},
  RoadRouteDirection? direction,
}) async {
  await BusLocationStore.instance.ensureLoaded();
  final origin = getMunicipalityCoordinates(start);
  if (origin == null) {
    return BusItineraryPlan(
      days: [
        for (final day in days)
          BusDayRoute(nodes: const [], spots: List<TouristSpot>.from(day)),
      ],
      error: 'No coordinates are saved for ${start.name}.',
    );
  }

  final errors = <String>[];
  final built = <BusDayRoute>[];
  var cursor = ItineraryRouteNode(
    point: origin,
    place: start.name,
    label: start.shortName.isNotEmpty ? start.shortName : start.name,
    detail: start.shortName.isNotEmpty ? start.shortName : start.name,
  );
  var cursorIsBus = false;
  var roadOpen = true;

  for (var dayIndex = 0; dayIndex < days.length; dayIndex++) {
    final day = List<TouristSpot>.from(days[dayIndex]);
    final nodes = <ItineraryRouteNode>[cursor];
    if (day.isEmpty) {
      built.add(BusDayRoute(nodes: nodes, spots: day));
      continue;
    }

    final lockedEndName = lockedDays.contains(dayIndex)
        ? null
        : lockedEndSpotNames[dayIndex];
    TouristSpot? lockedEnd;
    final pool = <TouristSpot>[];
    for (final spot in day) {
      if (lockedEnd == null &&
          lockedEndName != null &&
          spot.name == lockedEndName) {
        lockedEnd = spot;
      } else {
        pool.add(spot);
      }
    }

    final List<TouristSpot> ordered;
    if (lockedDays.contains(dayIndex) || !roadOpen) {
      ordered = List<TouristSpot>.from(day);
    } else {
      final step = await _orderWithinMunicipalities(
        spots: pool,
        fromPlace: cursor.place,
        fromPoint: cursor.point,
        fromMunicipality: cursor.place,
        direction: direction,
        errors: errors,
        dayIndex: dayIndex,
      );
      ordered = step;
      if (lockedEnd != null) ordered.add(lockedEnd);
    }

    var index = 0;
    while (index < ordered.length && roadOpen) {
      final spot = ordered[index];
      final muni = _municipalityName(spot);
      if (muni == null) {
        errors.add('No municipality is saved for ${spot.name}.');
        index++;
        continue;
      }
      if (!_sameMuni(muni, cursor.place) ||
          (cursorIsBus && !_sameMuni(muni, cursor.place))) {
        final linked = await _linkToward(
          fromMunicipality: cursor.place,
          toMunicipality: muni,
          fromPoint: cursor.point,
          fromPlace: cursor.place,
          direction: direction,
        );
        if (linked == null) {
          // Transport guidance only — missing hubs must not break tourist routing.
          errors.add(
            'No verified bus hub from ${cursor.place} to $muni'
            '${direction == null ? '' : ' on the ${direction.name} route'} '
            '(tourist road route continues without it).',
          );
        } else {
          if (!_samePoint(cursor.point, linked.departPoint)) {
            nodes.add(linked.depart);
          }
          if (!_samePoint(nodes.last.point, linked.arrive.point)) {
            nodes.add(linked.arrive);
          }
          // Keep road cursor on tourist points; hubs are display-only.
          cursorIsBus = false;
        }
      } else if (!cursorIsBus && _isBareStart(nodes)) {
        final nearest = await _nearestStop(
          municipality: muni,
          fromPoint: cursor.point,
          fromPlace: cursor.place,
          direction: direction,
        );
        if (nearest == null) {
          errors.add(
            'No bus stop or terminal is saved for $muni '
            '(shown as a transport guide only when available).',
          );
        } else {
          final node = _busNode(nearest);
          if (!_samePoint(cursor.point, node.point)) nodes.add(node);
        }
      }

      while (index < ordered.length) {
        final next = ordered[index];
        final nextMuni = _municipalityName(next);
        if (nextMuni == null || !_sameMuni(nextMuni, muni)) break;
        final point = _spotPoint(next);
        if (point == null) {
          errors.add('No coordinates are saved for ${next.name}.');
          index++;
          continue;
        }
        final node = ItineraryRouteNode(
          point: point,
          place: nextMuni,
          label: next.name,
          detail: '${next.name}, ${next.location}',
          spot: next,
          onRoad: roadOpen,
        );
        if (!_samePoint(nodes.last.point, node.point)) nodes.add(node);
        cursor = node;
        cursorIsBus = false;
        index++;
      }
    }

    while (index < ordered.length) {
      final spot = ordered[index++];
      final point = _spotPoint(spot);
      final place = _municipalityName(spot) ?? spot.location;
      if (point == null) continue;
      nodes.add(
        ItineraryRouteNode(
          point: point,
          place: place,
          label: spot.name,
          detail: '${spot.name}, ${spot.location}',
          spot: spot,
          onRoad: false,
        ),
      );
    }

    if (roadOpen && !cursorIsBus) {
      final later = _nextOtherMunicipality(days, dayIndex, cursor.place);
      if (later != null) {
        final depart = await _nearestStop(
          municipality: cursor.place,
          fromPoint: cursor.point,
          fromPlace: cursor.place,
          direction: direction,
          connectToMunicipality: later,
        );
        if (depart == null) {
          errors.add(
            'No verified bus hub from ${cursor.place} to $later'
            '${direction == null ? '' : ' on the ${direction.name} route'} '
            '(tourist road route continues without it).',
          );
        } else {
          // Display-only hub: do not move the road cursor onto the bus so
          // Day N+1 still starts from this day's last tourist spot.
          final node = _busNode(depart);
          if (!_samePoint(cursor.point, node.point)) nodes.add(node);
        }
      }
    }

    built.add(BusDayRoute(nodes: nodes, spots: ordered));
  }

  return BusItineraryPlan(
    days: built,
    error: errors.isEmpty ? null : errors.toSet().join(' '),
  );
}

bool _isBareStart(List<ItineraryRouteNode> nodes) =>
    nodes.length == 1 && !nodes.first.isBus && nodes.first.spot == null;

String? _nextOtherMunicipality(
  List<List<TouristSpot>> days,
  int dayIndex,
  String currentMunicipality,
) {
  for (var d = dayIndex + 1; d < days.length; d++) {
    for (final spot in days[d]) {
      final name = _municipalityName(spot);
      if (name == null) continue;
      if (_sameMuni(name, currentMunicipality)) return null;
      return name;
    }
  }
  return null;
}

Future<List<TouristSpot>> _orderWithinMunicipalities({
  required List<TouristSpot> spots,
  required String fromPlace,
  required LatLng fromPoint,
  required String fromMunicipality,
  required RoadRouteDirection? direction,
  required List<String> errors,
  required int dayIndex,
}) async {
  final remaining = List<TouristSpot>.from(spots);
  final ordered = <TouristSpot>[];
  var place = fromPlace;
  var point = fromPoint;
  var muni = fromMunicipality;

  while (remaining.isNotEmpty) {
    final here = remaining.where((s) {
      final name = _municipalityName(s);
      return name != null && _sameMuni(name, muni);
    }).toList();
    if (here.isEmpty) {
      TouristSpot? best;
      var bestMeters = double.infinity;
      for (final spot in remaining) {
        final name = _municipalityName(spot);
        final spotPoint = _spotPoint(spot);
        if (name == null || spotPoint == null) continue;
        if (!_municipalitiesCanConnect(muni, name, direction)) continue;
        final meters = await roadMetersBetween(
          fromPlace: place,
          fromPoint: point,
          toPlace: name,
          toPoint: spotPoint,
          direction: direction,
        );
        if (meters == null || meters >= bestMeters) continue;
        best = spot;
        bestMeters = meters;
      }
      if (best == null) {
        errors.add(
          'No valid ${direction == null ? '' : '${direction.name} '}road route was found for Day ${dayIndex + 1}.',
        );
        ordered.addAll(remaining);
        break;
      }
      muni = _municipalityName(best)!;
      continue;
    }

    final located = <TouristSpot>[];
    for (final spot in here) {
      if (_spotPoint(spot) == null) {
        errors.add('No coordinates are saved for ${spot.name}.');
        ordered.add(spot);
        remaining.remove(spot);
      } else {
        located.add(spot);
      }
    }
    var from = point;
    var fromName = place;
    final pending = List<TouristSpot>.from(located);
    while (pending.isNotEmpty) {
      TouristSpot? best;
      var bestMeters = double.infinity;
      for (final spot in pending) {
        final meters = await roadMetersBetween(
          fromPlace: fromName,
          fromPoint: from,
          toPlace: _municipalityName(spot) ?? spot.location,
          toPoint: _spotPoint(spot)!,
          direction: direction,
        );
        if (meters == null || meters >= bestMeters) continue;
        best = spot;
        bestMeters = meters;
      }
      if (best == null) {
        errors.add(
          'No valid ${direction == null ? '' : '${direction.name} '}road route was found for Day ${dayIndex + 1}.',
        );
        ordered.addAll(pending);
        remaining.removeWhere(pending.contains);
        pending.clear();
        break;
      }
      pending.remove(best);
      remaining.remove(best);
      ordered.add(best);
      from = _spotPoint(best)!;
      fromName = _municipalityName(best) ?? best.location;
      place = fromName;
      point = from;
    }
  }
  return ordered;
}

class _BusLink {
  final ItineraryRouteNode depart;
  final ItineraryRouteNode arrive;
  LatLng get departPoint => depart.point;
  const _BusLink(this.depart, this.arrive);
}

Future<_BusLink?> _linkToward({
  required String fromMunicipality,
  required String toMunicipality,
  required LatLng fromPoint,
  required String fromPlace,
  required RoadRouteDirection? direction,
}) async {
  final depart = await _nearestStop(
    municipality: fromMunicipality,
    fromPoint: fromPoint,
    fromPlace: fromPlace,
    direction: direction,
    connectToMunicipality: toMunicipality,
  );
  if (depart == null) return null;
  final arrive = await _nearestArrival(
    depart: depart,
    toMunicipality: toMunicipality,
    direction: direction,
  );
  if (arrive == null) return null;
  return _BusLink(_busNode(depart), _busNode(arrive));
}

Future<BusLocation?> _nearestArrival({
  required BusLocation depart,
  required String toMunicipality,
  required RoadRouteDirection? direction,
}) async {
  final arrivals = _stopsFor(toMunicipality, direction)
      .where((stop) => _connects(depart, stop, direction))
      .toList();
  BusLocation? best;
  var bestMeters = double.infinity;
  for (final stop in arrivals) {
    final meters = await roadMetersBetween(
      fromPlace: depart.municipality,
      fromPoint: LatLng(depart.latitude, depart.longitude),
      toPlace: stop.municipality,
      toPoint: LatLng(stop.latitude, stop.longitude),
      direction: direction,
    );
    if (meters == null || meters >= bestMeters) continue;
    best = stop;
    bestMeters = meters;
  }
  return best;
}

Future<BusLocation?> _nearestStop({
  required String municipality,
  required LatLng fromPoint,
  required String fromPlace,
  required RoadRouteDirection? direction,
  String? connectToMunicipality,
}) async {
  var stops = _stopsFor(municipality, direction);
  if (connectToMunicipality != null) {
    final nextStops = _stopsFor(connectToMunicipality, direction);
    stops = stops
        .where(
          (stop) => nextStops.any((next) => _connects(stop, next, direction)),
        )
        .toList();
  }
  BusLocation? best;
  var bestMeters = double.infinity;
  for (final stop in stops) {
    final meters = await roadMetersBetween(
      fromPlace: fromPlace,
      fromPoint: fromPoint,
      toPlace: stop.municipality,
      toPoint: LatLng(stop.latitude, stop.longitude),
      direction: direction,
    );
    if (meters == null || meters >= bestMeters) continue;
    best = stop;
    bestMeters = meters;
  }
  return best;
}

List<BusLocation> _stopsFor(String municipality, RoadRouteDirection? direction) {
  return BusLocationStore.instance.active.where((stop) {
    if (!_sameMuni(stop.municipality, municipality)) return false;
    if (direction != null && !stop.serves(direction)) return false;
    return true;
  }).toList();
}

bool _municipalitiesCanConnect(
  String from,
  String to,
  RoadRouteDirection? direction,
) {
  if (_sameMuni(from, to)) return true;
  final fromStops = _stopsFor(from, direction);
  final toStops = _stopsFor(to, direction);
  for (final a in fromStops) {
    for (final b in toStops) {
      if (_connects(a, b, direction)) return true;
    }
  }
  return false;
}

/// A ride is valid when both stops serve the selected route, a road exists on
/// that route, and an explicit [BusLocation.connectsTo] list (when stored)
/// includes the other stop. Stops are not treated as connected just because
/// they exist.
bool _connects(
  BusLocation from,
  BusLocation to,
  RoadRouteDirection? direction,
) {
  if (!from.isActive || !to.isActive) return false;
  if (!from.hasValidCoordinates || !to.hasValidCoordinates) return false;
  if (direction != null && (!from.serves(direction) || !to.serves(direction))) {
    return false;
  }
  if (from.connectsTo.isNotEmpty && !from.connectsTo.contains(to.id)) {
    return false;
  }
  if (_sameMuni(from.municipality, to.municipality)) return true;
  return hasRoadPathBetween(
    from.municipality,
    to.municipality,
    direction: direction,
  );
}

ItineraryRouteNode _busNode(BusLocation stop) {
  final kind = stop.locationType == 'terminal' ? 'terminal' : 'stop';
  final title = kind == 'terminal' ? 'Bus terminal' : 'Bus stop';
  // Display-only: keep hubs on the map / timeline, never as road waypoints.
  return ItineraryRouteNode(
    point: LatLng(stop.latitude, stop.longitude),
    place: stop.municipality,
    label: stop.name,
    detail: '$title · ${stop.name}, ${stop.municipality}',
    busKind: kind,
    onRoad: false,
  );
}

String? _municipalityName(TouristSpot spot) {
  final match = municipalityForItinerarySpot(spot);
  if (match != null) return match.name;
  final hint = spot.location.trim();
  return hint.isEmpty ? null : hint;
}

bool _sameMuni(String a, String b) {
  if (busLocationMunicipalityKey(a) == busLocationMunicipalityKey(b)) {
    return true;
  }
  final ia = roadTableIndexFor(a);
  final ib = roadTableIndexFor(b);
  return ia != null && ia == ib;
}

LatLng? _spotPoint(TouristSpot spot) {
  if (spot.latitude == null || spot.longitude == null) return null;
  return LatLng(spot.latitude!, spot.longitude!);
}

bool _samePoint(LatLng a, LatLng b) {
  return (a.latitude - b.latitude).abs() < 1e-5 &&
      (a.longitude - b.longitude).abs() < 1e-5;
}

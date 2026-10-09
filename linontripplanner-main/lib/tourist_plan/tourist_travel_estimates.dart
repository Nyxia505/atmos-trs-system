import 'dart:math' as math;

import '../data.dart';
import '../municipal_road_distances.dart';
import '../municipality_bus_terminals.dart';
import '../trip_route_fare_service.dart';

/// Max attractions a tourist may put on one trip plan.
const int kMaxTouristAttractions = 5;

/// Display labels for transport modes (tourist-friendly).
String transportModeLabel(String mode) {
  switch (mode) {
    case 'Public Transport':
      return 'Public Transport';
    default:
      return mode;
  }
}

/// Estimated stay at an attraction (minutes).
int estimatedStayMinutes(TouristSpot spot) {
  if (spot.isHotel) return 180;
  if (spot.type == 'Nature' || spot.type == 'Adventure') return 150;
  if (spot.walkingDistanceMinutes != null && spot.walkingDistanceMinutes! > 0) {
    return math.max(90, spot.walkingDistanceMinutes! * 3);
  }
  return 120;
}

/// Road km between two spots. Spots in different municipalities use the
/// town-to-town road table; same-town hops use straight line × 1.25.
double? spotDistanceKm(TouristSpot a, TouristSpot b) {
  final lat1 = a.latitude;
  final lon1 = a.longitude;
  final lat2 = b.latitude;
  final lon2 = b.longitude;
  final straight =
      (lat1 == null || lon1 == null || lat2 == null || lon2 == null)
          ? null
          : haversineDistanceKm(lat1, lon1, lat2, lon2) * 1.25;
  final road = roadDistanceKmBetween(a.location, b.location);
  if (road == null) return straight;
  if (straight == null) return road;
  return math.max(straight, road);
}

/// Average speed km/h by mode (for time estimates).
double _speedKmh(String mode) {
  switch (mode) {
    case 'Motorcycle':
      return 35;
    case 'Public Transport':
      return 22;
    case 'Car':
    default:
      return 40;
  }
}

/// Fuel / private vehicle cost per km (PHP).
double _costPerKm(String mode) {
  switch (mode) {
    case 'Motorcycle':
      return 3.5;
    case 'Car':
      return 9.0;
    case 'Public Transport':
      return 0; // use official fare matrix instead
    default:
      return 0;
  }
}

int travelMinutesForKm(double km, String mode) {
  if (km <= 0) return 0;
  final hours = km / _speedKmh(mode);
  var minutes = (hours * 60).round();
  if (mode == 'Public Transport') {
    minutes += 12; // wait / transfer buffer
  }
  return math.max(5, minutes);
}

int privateTransportCostPhp(double km, String mode, {int tourists = 1}) {
  if (mode == 'Public Transport') return 0;
  final perVehicle = (km * _costPerKm(mode)).round();
  if (mode == 'Car' || mode == 'Motorcycle') {
    // Vehicle cost shared among group (one vehicle).
    return perVehicle;
  }
  return perVehicle * math.max(1, tourists);
}

class TouristLegEstimate {
  final TouristSpot from;
  final TouristSpot to;
  final double distanceKm;
  final int travelMinutes;
  final int transportFeePhp;
  final String mode;
  final String? boardAt;
  final String? getOffAt;
  final String? routeHint;

  const TouristLegEstimate({
    required this.from,
    required this.to,
    required this.distanceKm,
    required this.travelMinutes,
    required this.transportFeePhp,
    required this.mode,
    this.boardAt,
    this.getOffAt,
    this.routeHint,
  });

  String get distanceLabel =>
      distanceKm > 0 ? '~${distanceKm.toStringAsFixed(1)} km' : '-';

  String get timeLabel {
    if (travelMinutes < 60) return '$travelMinutes min';
    final h = travelMinutes ~/ 60;
    final m = travelMinutes % 60;
    return m == 0 ? '${h}h' : '${h}h ${m}m';
  }
}

class TouristRouteEstimate {
  final List<TouristLegEstimate> legs;
  final String mode;
  final int tourists;

  const TouristRouteEstimate({
    required this.legs,
    required this.mode,
    this.tourists = 1,
  });

  double get totalDistanceKm =>
      legs.fold(0.0, (s, l) => s + l.distanceKm);

  int get totalTravelMinutes =>
      legs.fold(0, (s, l) => s + l.travelMinutes);

  int get totalTransportFeePhp =>
      legs.fold(0, (s, l) => s + l.transportFeePhp);

  bool get isEmpty => legs.isEmpty;
}

/// Builds leg estimates for ordered selected stops only.
TouristRouteEstimate buildRouteEstimate({
  required List<TouristSpot> orderedStops,
  required String mode,
  int tourists = 1,
  TripRouteFareBreakdown? publicTransportFares,
}) {
  if (orderedStops.length < 2) {
    return TouristRouteEstimate(legs: const [], mode: mode, tourists: tourists);
  }

  final legs = <TouristLegEstimate>[];
  for (var i = 0; i < orderedStops.length - 1; i++) {
    final from = orderedStops[i];
    final to = orderedStops[i + 1];
    final km = spotDistanceKm(from, to) ?? 8.0; // fallback when coords missing
    final minutes = travelMinutesForKm(km, mode);

    var fee = 0;
    String? boardAt;
    String? getOffAt;
    String? hint;

    if (mode == 'Public Transport') {
      fee = _publicFareBetweenSpots(
        from,
        to,
        publicTransportFares,
        tourists: tourists,
      );
      boardAt = _hubNameForSpot(from);
      getOffAt = _hubNameForSpot(to);
      hint = fee > 0
          ? 'Take a jeepney/bus between hubs, then tricycle to the attraction.'
          : 'Ask locally for jeepney/bus routes between these LGUs.';
    } else {
      fee = privateTransportCostPhp(km, mode, tourists: tourists);
      hint = 'Drive the connecting roads between attractions.';
    }

    legs.add(
      TouristLegEstimate(
        from: from,
        to: to,
        distanceKm: km,
        travelMinutes: minutes,
        transportFeePhp: fee,
        mode: mode,
        boardAt: boardAt,
        getOffAt: getOffAt,
        routeHint: hint,
      ),
    );
  }

  return TouristRouteEstimate(legs: legs, mode: mode, tourists: tourists);
}

int _publicFareBetweenSpots(
  TouristSpot from,
  TouristSpot to,
  TripRouteFareBreakdown? fares, {
  int tourists = 1,
}) {
  if (fares != null && fares.segments.isNotEmpty) {
    final fromLoc = from.location.trim().toLowerCase();
    final toLoc = to.location.trim().toLowerCase();
    for (final seg in fares.segments) {
      final a = seg.from.name.trim().toLowerCase();
      final b = seg.to.name.trim().toLowerCase();
      if ((a.contains(fromLoc) || fromLoc.contains(a)) &&
          (b.contains(toLoc) || toLoc.contains(b))) {
        return scaleTransportFareForTourists(seg.farePhp, tourists);
      }
    }
  }
  // Soft estimate when matrix miss: ~₱2.5/km jeepney-style, min ₱15.
  final km = spotDistanceKm(from, to) ?? 10;
  final perPerson = math.max(15, (km * 2.5).round());
  return scaleTransportFareForTourists(perPerson, tourists);
}

String? _hubNameForSpot(TouristSpot spot) {
  for (final m in municipalities) {
    if (m.name == spot.location || m.shortName == spot.location) {
      return transportEndpointFor(m).name;
    }
  }
  return null;
}

String formatHoursMinutes(int totalMinutes) {
  if (totalMinutes <= 0) return '0 min';
  if (totalMinutes < 60) return '$totalMinutes min';
  final h = totalMinutes ~/ 60;
  final m = totalMinutes % 60;
  if (m == 0) return '$h hr';
  return '$h hr $m min';
}

/// Parse entrance fee string to int when possible.
int parseSpotEntranceFee(TouristSpot spot) {
  final raw = spot.entranceFee.trim();
  if (raw.isEmpty) return 0;
  final digits = raw.replaceAll(RegExp(r'[^\d]'), '');
  return int.tryParse(digits) ?? 0;
}

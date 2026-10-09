import 'data.dart';
import 'hub_spot_transport_fee.dart';
import 'municipality_bus_terminals.dart';
import 'transportation_fees_loader.dart';

/// One LGU-to-LGU leg using the official fare matrix / Firestore fee.
class TripRouteFareSegment {
  final Municipality from;
  final Municipality to;
  final int farePhp;
  final String endpointType;
  final String endpointName;
  final String routeType;
  final double estimatedDistanceKm;

  const TripRouteFareSegment({
    required this.from,
    required this.to,
    required this.farePhp,
    required this.endpointType,
    required this.endpointName,
    required this.routeType,
    required this.estimatedDistanceKm,
  });

  String get label => '${from.shortName} → ${to.shortName}';
}

/// Bus hub ↔ tourist spot (last-mile) within one LGU.
class TripHubSpotFareSegment {
  final String endpointName;
  final String endpointType;
  final Municipality municipality;
  final TouristSpot spot;
  final int farePhp;
  final int fareMin;
  final int fareMax;
  final HubSpotLegDirection direction;

  const TripHubSpotFareSegment({
    required this.endpointName,
    required this.endpointType,
    required this.municipality,
    required this.spot,
    required this.farePhp,
    required this.fareMin,
    required this.fareMax,
    required this.direction,
  });

  String get label {
    switch (direction) {
      case HubSpotLegDirection.hubToSpot:
        return '$endpointName → ${spot.name}';
      case HubSpotLegDirection.spotToHub:
        return '${spot.name} → $endpointName';
    }
  }
}

/// Inter-LGU legs plus hub → spot access fares for an itinerary.
class TripRouteFareBreakdown {
  final List<TripRouteFareSegment> segments;
  final List<TripHubSpotFareSegment> hubSpotSegments;

  const TripRouteFareBreakdown({
    this.segments = const [],
    this.hubSpotSegments = const [],
  });

  bool get isEmpty => segments.isEmpty && hubSpotSegments.isEmpty;

  int get totalFarePhp =>
      segments.fold<int>(0, (sum, s) => sum + s.farePhp) +
      hubSpotSegments.fold<int>(0, (sum, s) => sum + s.farePhp);

  /// Per-person total × [numberOfTourists] (group transport cost).
  int totalFarePhpForTourists(int numberOfTourists) =>
      scaleTransportFareForTourists(totalFarePhp, numberOfTourists);

  /// Direct start → end fare when exactly one inter-LGU segment and no hub legs.
  int? get directFarePhp {
    if (hubSpotSegments.isNotEmpty) return null;
    return segments.length == 1 ? segments.first.farePhp : null;
  }

  TripRouteFareSegment? get directSegment =>
      segments.length == 1 && hubSpotSegments.isEmpty ? segments.first : null;
}

String formatFarePhp(int amount) => '₱$amount';

/// Hub at the trip destination (matches End Point), not the last itinerary leg.
String hubSummaryLineForMunicipality(Municipality municipality) {
  final hub = transportEndpointFor(municipality);
  final kind = hub.kind == 'terminal' ? 'Bus terminal' : 'Bus stop';
  return 'Ends at $kind: ${hub.name}';
}

/// Multiplies a per-person fare by traveler count (minimum 1).
int scaleTransportFareForTourists(int perPersonFarePhp, int numberOfTourists) {
  final n = numberOfTourists < 1 ? 1 : numberOfTourists;
  return perPersonFarePhp * n;
}

String formatDistanceKm(double km) {
  if (km <= 0) return '';
  return '~${km.toStringAsFixed(1)} km';
}

/// Instant fare for selected start → end (official matrix; no network).
TripRouteFareBreakdown? buildDirectTripFareBreakdownSync(
  Municipality start,
  Municipality end,
) {
  if (start.name.trim() == end.name.trim()) return null;

  final fare = estimatedFarePhp(start.name, end.name);
  if (fare == null) return null;

  final hub = transportEndpointFor(end);
  if (!_isBusHubEndpoint(hub.kind)) return null;

  return TripRouteFareBreakdown(
    segments: [
      TripRouteFareSegment(
        from: start,
        to: end,
        farePhp: fare,
        endpointType: hub.kind,
        endpointName: hub.name,
        routeType: 'jeepney',
        estimatedDistanceKm: 0,
      ),
    ],
  );
}

/// Direct fare between selected municipalities (Firestore fee, then matrix).
Future<TripRouteFareBreakdown?> buildDirectTripFareBreakdown(
  Municipality start,
  Municipality end,
) {
  return buildTripRouteFareBreakdown([start, end]);
}

/// Resolves consecutive municipal fares for [route] (uses cache, then Firestore, then matrix).
Future<TripRouteFareBreakdown?> buildTripRouteFareBreakdown(
  List<Municipality> route,
) async {
  if (route.length < 2) return null;

  final segments = <TripRouteFareSegment>[];
  for (var i = 0; i < route.length - 1; i++) {
    final from = route[i];
    final to = route[i + 1];
    if (from.name == to.name) continue;

    final segment = await _resolveSegment(from, to);
    if (segment != null) segments.add(segment);
  }

  if (segments.isEmpty) return null;
  return TripRouteFareBreakdown(segments: segments);
}

Future<TripRouteFareSegment?> _resolveSegment(
  Municipality from,
  Municipality to,
) async {
  final fee = await fetchTransportationFee(
    fromMunicipality: from.name,
    toMunicipality: to.name,
  );

  if (fee != null && _isBusHubEndpoint(fee.endpointType)) {
    return TripRouteFareSegment(
      from: from,
      to: to,
      farePhp: fee.fare,
      endpointType: fee.endpointType,
      endpointName: fee.endpointName,
      routeType: fee.routeType,
      estimatedDistanceKm: fee.estimatedDistance,
    );
  }

  final matrixFare = estimatedFarePhp(from.name, to.name);
  if (matrixFare == null) return null;

  final hub = transportEndpointFor(to);
  if (!_isBusHubEndpoint(hub.kind)) return null;

  return TripRouteFareSegment(
    from: from,
    to: to,
    farePhp: matrixFare,
    endpointType: hub.kind,
    endpointName: hub.name,
    routeType: 'jeepney',
    estimatedDistanceKm: 0,
  );
}

/// Transportation fees apply only when the user picks public transport.
bool shouldShowTransportationFees(String transportMode) {
  return transportMode.trim().toLowerCase() == 'public transport';
}

/// @deprecated Use [shouldShowTransportationFees].
bool transportModeUsesOfficialFares(String transportMode) =>
    shouldShowTransportationFees(transportMode);

bool _isBusHubEndpoint(String endpointType) {
  final kind = endpointType.trim().toLowerCase();
  return kind == 'terminal' || kind == 'stop';
}

String fareBreakdownTitle(Municipality start, Municipality end) {
  return 'Transportation fees · ${start.shortName} → ${end.shortName}';
}

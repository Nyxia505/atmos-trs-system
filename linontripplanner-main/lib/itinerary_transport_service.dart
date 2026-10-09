import 'algorithms/municipality_fare_dijkstra.dart';
import 'data.dart';
import 'misamis_occidental_fare_matrix.dart';
import 'municipality_bus_terminals.dart';
import 'transportation_fee.dart';
import 'firestore_loader.dart';
import 'hub_spot_transport_fare_matrix.dart';
import 'hub_spot_transport_fee.dart';
import 'hub_spot_transport_fees_loader.dart';
import 'transportation_fees_loader.dart';
import 'trip_planner_utils.dart';
import 'trip_route_fare_service.dart';

/// Resolves which LGU a [TouristSpot] belongs to (same rules as municipality detail).
Municipality? municipalityForItinerarySpot(TouristSpot spot) {
  for (final m in municipalities) {
    if (touristSpotBelongsToMunicipality(spot, m)) return m;
  }
  final byLocation = matchMunicipalityByLocalityHint(spot.location);
  if (byLocation != null) return byLocation;
  return null;
}

/// Municipalities that have at least one itinerary spot, in visit order (deduped).
List<Municipality> orderedMunicipalitiesWithItinerarySpots(
  List<TouristSpot> itinerarySpots,
) {
  final ordered = <Municipality>[];
  final seen = <String>{};
  for (final spot in itinerarySpots) {
    final m = municipalityForItinerarySpot(spot);
    if (m == null) continue;
    final key = normalizeMunicipalityName(m.name);
    if (seen.add(key)) ordered.add(m);
  }
  return ordered;
}

/// Consecutive municipality pairs along the itinerary (only where spots exist).
List<({Municipality from, Municipality to})> itineraryTransportLegs(
  List<Municipality> itineraryMunicipalities,
) {
  if (itineraryMunicipalities.length < 2) return const [];
  final legs = <({Municipality from, Municipality to})>[];
  for (var i = 0; i < itineraryMunicipalities.length - 1; i++) {
    legs.add((
      from: itineraryMunicipalities[i],
      to: itineraryMunicipalities[i + 1],
    ));
  }
  return legs;
}

List<String> _docIdsForLegs(
  List<({Municipality from, Municipality to})> legs,
) {
  return legs
      .map(
        (leg) => transportationFeeDocId(leg.from.name, leg.to.name),
      )
      .toList();
}

/// Fetches only Firestore docs needed for itinerary legs (batched `whereIn`).
Future<void> prefetchItineraryTransportFees(
  List<Municipality> itineraryMunicipalities,
) async {
  final legs = itineraryTransportLegs(itineraryMunicipalities);
  if (legs.isEmpty) return;
  await fetchTransportationFeesByDocIds(_docIdsForLegs(legs));
}

TripRouteFareSegment? _segmentFromFee(
  Municipality from,
  Municipality to,
  TransportationFee fee,
) {
  if (!_isBusHubEndpoint(fee.endpointType)) return null;
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

TripRouteFareSegment? _segmentFromDijkstra(Municipality from, Municipality to) {
  final fromKey = fareMatrixKeyForMunicipalityName(from.name);
  final toKey = fareMatrixKeyForMunicipalityName(to.name);
  final path = MunicipalityFareDijkstra.shortestPathKeys(fromKey, toKey);
  final fare = MunicipalityFareDijkstra.totalFareAlongPath(path);
  if (fare == null) return null;

  final hub = transportEndpointFor(to);
  if (!_isBusHubEndpoint(hub.kind)) return null;

  return TripRouteFareSegment(
    from: from,
    to: to,
    farePhp: fare,
    endpointType: hub.kind,
    endpointName: hub.name,
    routeType: 'jeepney',
    estimatedDistanceKm: 0,
  );
}

bool _isBusHubEndpoint(String endpointType) {
  final kind = endpointType.trim().toLowerCase();
  return kind == 'terminal' || kind == 'stop';
}

/// One itinerary leg: Firestore doc → matrix direct → Dijkstra minimum fare on LGU graph.
TripRouteFareSegment? resolveItineraryLegSegment({
  required Municipality from,
  required Municipality to,
  TransportationFee? prefetchedFee,
}) {
  if (from.name.trim() == to.name.trim()) return null;

  if (prefetchedFee != null) {
    final fromFee = _segmentFromFee(from, to, prefetchedFee);
    if (fromFee != null) return fromFee;
  }

  final cached = transportationFeesByDocId[
      transportationFeeDocId(from.name, to.name)];
  if (cached != null) {
    final fromCache = _segmentFromFee(from, to, cached);
    if (fromCache != null) return fromCache;
  }

  final matrixFare = estimatedFarePhp(from.name, to.name);
  if (matrixFare != null) {
    final hub = transportEndpointFor(to);
    if (_isBusHubEndpoint(hub.kind)) {
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
  }

  return _segmentFromDijkstra(from, to);
}

String _spotSlugForLookup(TouristSpot spot) =>
    touristSpotProfileStorageSlug(spot.name);

List<String> _hubSpotDocIdsForItinerary(List<TouristSpot> spots) {
  final ids = <String>[];
  for (final spot in spots) {
    final muni = municipalityForItinerarySpot(spot);
    if (muni == null) continue;
    final hub = transportEndpointFor(muni);
    final endpointSlug = municipalitySlug(hub.name);
    final spotSlug = _spotSlugForLookup(spot);
    for (final direction in HubSpotLegDirection.values) {
      ids.add(hubSpotTransportFeeDocId(endpointSlug, spotSlug, direction));
    }
  }
  return ids;
}

TripHubSpotFareSegment _hubSpotSegmentFromFee(
  TouristSpot spot,
  Municipality municipality,
  HubSpotTransportFee fee,
) {
  return TripHubSpotFareSegment(
    endpointName: fee.fromEndpointName,
    endpointType: fee.fromEndpointType,
    municipality: municipality,
    spot: spot,
    farePhp: fee.fare,
    fareMin: fee.fareMin,
    fareMax: fee.fareMax,
    direction: fee.direction,
  );
}

List<TripHubSpotFareSegment> _hubSpotSegmentsForSpot({
  required TouristSpot spot,
  required Map<String, HubSpotTransportFee> prefetchedFees,
}) {
  final muni = municipalityForItinerarySpot(spot);
  if (muni == null) return const [];

  final hub = transportEndpointFor(muni);
  final endpointSlug = municipalitySlug(hub.name);
  final spotSlug = _spotSlugForLookup(spot);
  final segments = <TripHubSpotFareSegment>[];

  for (final direction in HubSpotLegDirection.values) {
    final id = hubSpotTransportFeeDocId(endpointSlug, spotSlug, direction);
    var fee = prefetchedFees[id] ??
        hubSpotTransportFeesByDocId[id] ??
        hubSpotFeeFromMatrixForSpot(spot, direction);
    if (fee == null &&
        direction == HubSpotLegDirection.hubToSpot) {
      final legacyId = '${endpointSlug}__${spotSlug}';
      fee = prefetchedFees[legacyId] ?? hubSpotTransportFeesByDocId[legacyId];
    }
    if (fee == null) continue;
    segments.add(_hubSpotSegmentFromFee(spot, muni, fee));
  }
  return segments;
}

Future<List<TripHubSpotFareSegment>> buildHubSpotFareSegments(
  List<TouristSpot> itinerarySpots,
) async {
  final fees =
      await fetchHubSpotTransportFeesByDocIds(_hubSpotDocIdsForItinerary(itinerarySpots));
  final segments = <TripHubSpotFareSegment>[];
  for (final spot in itinerarySpots) {
    segments.addAll(_hubSpotSegmentsForSpot(spot: spot, prefetchedFees: fees));
  }
  return segments;
}

List<TripHubSpotFareSegment> buildHubSpotFareSegmentsSync(
  List<TouristSpot> itinerarySpots,
) {
  final segments = <TripHubSpotFareSegment>[];
  for (final spot in itinerarySpots) {
    segments.addAll(_hubSpotSegmentsForSpot(spot: spot, prefetchedFees: hubSpotTransportFeesByDocId));
  }
  return segments;
}

/// Transportation fees: consecutive itinerary LGUs + hub → each tourist spot.
Future<TripRouteFareBreakdown?> buildItineraryTransportFareBreakdown(
  List<TouristSpot> itinerarySpots,
) async {
  final route = orderedMunicipalitiesWithItinerarySpots(itinerarySpots);
  final legs = itineraryTransportLegs(route);

  final interFees = legs.isEmpty
      ? <String, TransportationFee>{}
      : await fetchTransportationFeesByDocIds(_docIdsForLegs(legs));
  final hubSpotFees =
      await fetchHubSpotTransportFeesByDocIds(_hubSpotDocIdsForItinerary(itinerarySpots));

  final segments = <TripRouteFareSegment>[];
  for (final leg in legs) {
    final id = transportationFeeDocId(leg.from.name, leg.to.name);
    final segment = resolveItineraryLegSegment(
      from: leg.from,
      to: leg.to,
      prefetchedFee: interFees[id],
    );
    if (segment != null) segments.add(segment);
  }

  final hubSpotSegments = <TripHubSpotFareSegment>[];
  for (final spot in itinerarySpots) {
    hubSpotSegments.addAll(
      _hubSpotSegmentsForSpot(spot: spot, prefetchedFees: hubSpotFees),
    );
  }

  if (segments.isEmpty && hubSpotSegments.isEmpty) return null;
  return TripRouteFareBreakdown(
    segments: segments,
    hubSpotSegments: hubSpotSegments,
  );
}

/// Sync fallback (embedded matrices; no Firestore).
TripRouteFareBreakdown? buildItineraryTransportFareBreakdownSync(
  List<TouristSpot> itinerarySpots,
) {
  final route = orderedMunicipalitiesWithItinerarySpots(itinerarySpots);
  final legs = itineraryTransportLegs(route);

  final segments = <TripRouteFareSegment>[];
  for (final leg in legs) {
    final segment = resolveItineraryLegSegment(
      from: leg.from,
      to: leg.to,
    );
    if (segment != null) segments.add(segment);
  }

  final hubSpotSegments = buildHubSpotFareSegmentsSync(itinerarySpots);
  if (segments.isEmpty && hubSpotSegments.isEmpty) return null;
  return TripRouteFareBreakdown(
    segments: segments,
    hubSpotSegments: hubSpotSegments,
  );
}

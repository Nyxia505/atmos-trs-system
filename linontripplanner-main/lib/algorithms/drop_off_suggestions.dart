import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../data.dart';
import '../hub_spot_transport_fare_matrix.dart';
import '../itinerary_transport_service.dart' show municipalityForItinerarySpot;
import '../municipality_bus_terminals.dart' show haversineDistanceKm;
import '../road_route_direction.dart';
import '../services/bus_location_store.dart';
import '../widgets/trip_route_osm_map_view.dart' show TripBusMarker;

/// Nearby known bus hub for a tourist destination (display / guidance only).
class DropOffSuggestion {
  const DropOffSuggestion({
    required this.stop,
    required this.spot,
    required this.distanceKm,
    required this.isRecommended,
    required this.note,
  });

  final BusLocation stop;
  final TouristSpot spot;
  final double distanceKm;
  final bool isRecommended;
  final String note;
}

String _spotSlug(TouristSpot spot) => touristSpotProfileStorageSlug(spot.name);

String? _spotMunicipality(TouristSpot spot) {
  final match = municipalityForItinerarySpot(spot);
  if (match != null) return match.name;
  final hint = spot.location.trim();
  return hint.isEmpty ? null : hint;
}

/// Finds nearby Firestore bus hubs for [spot]. Does not invent stops.
///
/// A hub is **recommended** only when verified transport data supports it:
/// hub→spot matrix row for that municipality/slug, or an active hub in the
/// same municipality that serves the selected coastal/highland direction.
List<DropOffSuggestion> suggestDropOffsForSpot({
  required TouristSpot spot,
  RoadRouteDirection? direction,
  double maxKm = 8.0,
}) {
  if (spot.latitude == null || spot.longitude == null) return const [];
  final spotLat = spot.latitude!;
  final spotLng = spot.longitude!;
  final muni = _spotMunicipality(spot);
  final slug = _spotSlug(spot);
  final matrixRow = matrixRowForSpotSlug(slug);

  final candidates = <DropOffSuggestion>[];
  for (final stop in BusLocationStore.instance.active) {
    if (direction != null && !stop.serves(direction)) continue;
    final km = haversineDistanceKm(
      spotLat,
      spotLng,
      stop.latitude,
      stop.longitude,
    );
    if (km > maxKm) continue;

    final sameMuni = muni != null &&
        busLocationMunicipalityKey(stop.municipality) ==
            busLocationMunicipalityKey(muni);
    final matrixSupports = matrixRow != null &&
        busLocationMunicipalityKey(matrixRow.municipalityName) ==
            busLocationMunicipalityKey(stop.municipality);

    final recommended = matrixSupports ||
        (sameMuni && (direction == null || stop.serves(direction)));

    final note = recommended
        ? (matrixSupports
            ? 'Verified hub→spot transport fare on file'
                ' (₱${matrixRow.fareMin}–₱${matrixRow.fareMax}).'
            : 'Active hub in the destination municipality'
                '${direction == null ? '' : ' on the ${direction.name} route'}.')
        : 'Nearby hub — not labeled as a verified drop-off for this destination.';

    candidates.add(
      DropOffSuggestion(
        stop: stop,
        spot: spot,
        distanceKm: km,
        isRecommended: recommended,
        note: note,
      ),
    );
  }

  candidates.sort((a, b) {
    final byRec = (b.isRecommended ? 1 : 0).compareTo(a.isRecommended ? 1 : 0);
    if (byRec != 0) return byRec;
    return a.distanceKm.compareTo(b.distanceKm);
  });
  return candidates;
}

/// Compact summary for one destination shown under the map.
String dropOffSummaryForSpot({
  required TouristSpot spot,
  RoadRouteDirection? direction,
}) {
  final list = suggestDropOffsForSpot(spot: spot, direction: direction);
  if (list.isEmpty) return 'No verified drop-off point available.';
  final recommended = list.where((s) => s.isRecommended).toList();
  if (recommended.isEmpty) {
    final nearest = list.first;
    return 'Nearest hub: ${nearest.stop.name} '
        '(${nearest.distanceKm.toStringAsFixed(1)} km) — '
        'not verified as a drop-off for this destination.';
  }
  final best = recommended.first;
  return 'Recommended drop-off: ${best.stop.name} '
      '(${best.distanceKm.toStringAsFixed(1)} km) · ${best.stop.municipality}';
}

/// Map markers for hubs relevant to [spots] (municipality + nearby).
/// Does not invent locations — Firestore [BusLocationStore] only.
List<TripBusMarker> transportMarkersNearSpots({
  required List<TouristSpot> spots,
  RoadRouteDirection? direction,
  double maxKm = 8.0,
}) {
  final byId = <String, TripBusMarker>{};

  void addStop(
    BusLocation stop, {
    double? distanceKm,
    String? nearSpotName,
    bool recommended = false,
    String dropOffNote = '',
  }) {
    final kind = stop.locationType == 'terminal' ? 'terminal' : 'stop';
    final existing = byId[stop.id];
    if (existing != null && existing.isRecommendedDropOff && !recommended) {
      return;
    }
    final routeLabel = stop.routeType == 'both'
        ? 'Coastal & Highland'
        : '${stop.routeType[0].toUpperCase()}${stop.routeType.substring(1)} route';
    byId[stop.id] = TripBusMarker(
      point: LatLng(stop.latitude, stop.longitude),
      kind: kind,
      label: stop.name,
      name: stop.name,
      municipality: stop.municipality,
      routeTypeLabel: routeLabel,
      distanceKmFromRoute: distanceKm,
      nearSpotName: nearSpotName,
      isRecommendedDropOff: recommended,
      dropOffNote: dropOffNote.isNotEmpty
          ? dropOffNote
          : (recommended
              ? 'Recommended drop-off for nearby tourist destination.'
              : ''),
    );
  }

  for (final spot in spots) {
    final suggestions = suggestDropOffsForSpot(
      spot: spot,
      direction: direction,
      maxKm: maxKm,
    );
    for (final s in suggestions) {
      addStop(
        s.stop,
        distanceKm: s.distanceKm,
        nearSpotName: spot.name,
        recommended: s.isRecommended,
        dropOffNote: s.note,
      );
    }
  }

  // Also include any active hubs in the spot municipalities even if > maxKm
  // from the pin (still useful boarding reference when coords are far apart).
  final munis = <String>{
    for (final s in spots)
      if (_spotMunicipality(s) != null)
        busLocationMunicipalityKey(_spotMunicipality(s)!),
  };
  for (final stop in BusLocationStore.instance.active) {
    if (byId.containsKey(stop.id)) continue;
    if (direction != null && !stop.serves(direction)) continue;
    if (!munis.contains(busLocationMunicipalityKey(stop.municipality))) {
      continue;
    }
    addStop(stop);
  }

  return byId.values.toList();
}

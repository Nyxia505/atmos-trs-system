import 'package:atmos_trs_system/data/featured_destinations.dart';
import 'package:atmos_trs_system/data/tourist_spots_default_seed.dart';
import 'package:atmos_trs_system/features/explore/explore_data.dart'
    as explore;
import 'package:atmos_trs_system/models/tourist_spot_firestore.dart';
import 'package:atmos_trs_system/services/qr_checkin_service.dart';
import 'package:atmos_trs_system/services/spot_location_cache.dart';
import 'package:atmos_trs_system/services/tourist_spots_repository.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart' show LatLng;
import 'package:trip_plan/data.dart' as trip;
import 'package:trip_plan/municipal_road_distances.dart'
    show municipalitiesOnRoadBetween;
import 'package:trip_plan/municipality_coordinates.dart';
import 'package:trip_plan/trip_planner_utils.dart';

/// Destination pin for in-app Trip Planner routing (never a hardcoded town).
class SpotMapPoint {
  const SpotMapPoint({
    required this.spotId,
    required this.name,
    required this.latitude,
    required this.longitude,
    required this.municipality,
  });

  final String spotId;
  final String name;
  final double latitude;
  final double longitude;
  final String municipality;

  LatLng get latLng => LatLng(latitude, longitude);
}

/// True when [lat]/[lng] can be sent to the Trip Planner map.
bool isUsableMapCoordinate(double? lat, double? lng) {
  if (lat == null || lng == null) return false;
  if (!lat.isFinite || !lng.isFinite) return false;
  return lat.abs() > 1e-6 || lng.abs() > 1e-6;
}

String _normId(String value) =>
    value.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '');

/// Local catalogs only — used by tests and as a fallback when Firestore is
/// unreachable. Each spot keeps its own coordinates.
SpotMapPoint? spotMapPointFromLocalCatalogs({
  required String spotId,
  required String name,
  String municipality = '',
}) {
  final id = _normId(spotId);
  final nameKey = _normId(name);

  SpotMapPoint? fromFeatured(Map<String, dynamic> data) {
    final lat = (data['latitude'] as num?)?.toDouble();
    final lng = (data['longitude'] as num?)?.toDouble();
    if (!isUsableMapCoordinate(lat, lng)) return null;
    return SpotMapPoint(
      spotId: (data['spotId'] ?? spotId).toString(),
      name: (data['name'] ?? name).toString(),
      latitude: lat!,
      longitude: lng!,
      municipality: municipality.isNotEmpty
          ? municipality
          : (data['location']?.toString() ?? ''),
    );
  }

  if (id.isNotEmpty) {
    for (final data in kFeaturedDestinations) {
      if (_normId(data['spotId']?.toString() ?? '') == id) {
        final match = fromFeatured(data);
        if (match != null) return match;
      }
    }
    for (final seed in kDefaultTouristSpotSeeds) {
      if (_normId(seed.docId) == id &&
          isUsableMapCoordinate(seed.latitude, seed.longitude)) {
        return SpotMapPoint(
          spotId: seed.docId,
          name: seed.name,
          latitude: seed.latitude,
          longitude: seed.longitude,
          municipality: seed.municipality,
        );
      }
    }
    for (final spot in [...explore.kVRTourSpots, ...explore.kMockSpots]) {
      if (_normId(spot.id) == id &&
          isUsableMapCoordinate(spot.latitude, spot.longitude)) {
        return SpotMapPoint(
          spotId: spot.id,
          name: spot.name,
          latitude: spot.latitude,
          longitude: spot.longitude,
          municipality: spot.city,
        );
      }
    }
  }

  if (nameKey.isNotEmpty) {
    for (final data in kFeaturedDestinations) {
      if (_normId(data['name']?.toString() ?? '') == nameKey) {
        final match = fromFeatured(data);
        if (match != null) return match;
      }
    }
    for (final seed in kDefaultTouristSpotSeeds) {
      if (_normId(seed.name) == nameKey &&
          isUsableMapCoordinate(seed.latitude, seed.longitude)) {
        return SpotMapPoint(
          spotId: seed.docId,
          name: seed.name,
          latitude: seed.latitude,
          longitude: seed.longitude,
          municipality: seed.municipality,
        );
      }
    }
    for (final spot in [...explore.kVRTourSpots, ...explore.kMockSpots]) {
      if (_normId(spot.name) == nameKey &&
          isUsableMapCoordinate(spot.latitude, spot.longitude)) {
        return SpotMapPoint(
          spotId: spot.id,
          name: spot.name,
          latitude: spot.latitude,
          longitude: spot.longitude,
          municipality: spot.city,
        );
      }
    }
  }
  return null;
}

SpotMapPoint? _pointFromPair({
  required String spotId,
  required String name,
  required String municipality,
  required String id,
  required String label,
  required double lat,
  required double lng,
  required String town,
}) {
  if (!isUsableMapCoordinate(lat, lng)) return null;
  return SpotMapPoint(
    spotId: id.isNotEmpty ? id : spotId,
    name: label.isNotEmpty ? label : name,
    latitude: lat,
    longitude: lng,
    municipality: town.isNotEmpty ? town : municipality,
  );
}

/// Coordinates already on the details screen or in local catalogs — no network.
SpotMapPoint? spotMapPointFromKnownSources({
  required String spotId,
  required String name,
  String municipality = '',
  double latitude = 0,
  double longitude = 0,
  TouristSpotFirestore? firestoreSpot,
}) {
  try {
    final cached = SpotLocationCache.spotById(spotId);
    if (cached != null) {
      final fromCache = _pointFromPair(
        spotId: spotId,
        name: name,
        municipality: municipality,
        id: cached.id,
        label: cached.name,
        lat: cached.latitude,
        lng: cached.longitude,
        town: cached.municipality,
      );
      if (fromCache != null) return fromCache;
    }
  } catch (_) {}

  if (firestoreSpot != null) {
    final fromPassed = _pointFromPair(
      spotId: spotId,
      name: name,
      municipality: municipality,
      id: firestoreSpot.id,
      label: firestoreSpot.name,
      lat: firestoreSpot.latitude,
      lng: firestoreSpot.longitude,
      town: firestoreSpot.municipality,
    );
    if (fromPassed != null) return fromPassed;
  }

  final fromArgs = _pointFromPair(
    spotId: spotId,
    name: name,
    municipality: municipality,
    id: spotId,
    label: name,
    lat: latitude,
    lng: longitude,
    town: municipality,
  );
  if (fromArgs != null) return fromArgs;

  try {
    for (final spot in TouristSpotsRepository.peekCachedSpots()) {
      if (spot.id != spotId) continue;
      final fromRepo = _pointFromPair(
        spotId: spotId,
        name: name,
        municipality: municipality,
        id: spot.id,
        label: spot.name,
        lat: spot.latitude,
        lng: spot.longitude,
        town: spot.municipality,
      );
      if (fromRepo != null) return fromRepo;
    }
  } catch (_) {}

  return spotMapPointFromLocalCatalogs(
    spotId: spotId,
    name: name,
    municipality: municipality,
  );
}

/// Prefers coordinates already on the spot, then a short cache/DB lookup.
/// Never waits on Firestore long enough to freeze Get Directions.
Future<SpotMapPoint?> resolveSpotMapPoint({
  required String spotId,
  required String name,
  String municipality = '',
  double latitude = 0,
  double longitude = 0,
  TouristSpotFirestore? firestoreSpot,
}) async {
  final local = spotMapPointFromKnownSources(
    spotId: spotId,
    name: name,
    municipality: municipality,
    latitude: latitude,
    longitude: longitude,
    firestoreSpot: firestoreSpot,
  );

  try {
    await SpotLocationCache.ensureLoaded()
        .timeout(const Duration(milliseconds: 800));
    final cached = SpotLocationCache.spotById(spotId);
    if (cached != null) {
      final fromCache = _pointFromPair(
        spotId: spotId,
        name: name,
        municipality: municipality,
        id: cached.id,
        label: cached.name,
        lat: cached.latitude,
        lng: cached.longitude,
        town: cached.municipality,
      );
      if (fromCache != null) return fromCache;
    }
  } catch (_) {}

  if (local != null) return local;

  try {
    final info = await QRCheckInService.getSpotById(spotId)
        .timeout(const Duration(seconds: 4));
    final fromQr = info == null
        ? null
        : _pointFromPair(
            spotId: spotId,
            name: name,
            municipality: municipality,
            id: info.spotId,
            label: info.spotName,
            lat: info.latitude ?? 0,
            lng: info.longitude ?? 0,
            town: info.municipality,
          );
    if (fromQr != null) return fromQr;
  } catch (_) {}

  return local;
}

/// Trip Planner municipality for a spot or GPS point. Falls back to the
/// nearest town center — never a hardcoded destination.
trip.Municipality tripMunicipalityFor({
  String name = '',
  double? latitude,
  double? longitude,
}) {
  final match = matchMunicipalityByLocalityHint(name);
  if (match != null) return match;
  if (isUsableMapCoordinate(latitude, longitude)) {
    return nearestTripMunicipality(LatLng(latitude!, longitude!));
  }
  return trip.municipalities.first;
}

trip.Municipality nearestTripMunicipality(LatLng point) {
  trip.Municipality? best;
  var bestDistance = double.infinity;
  for (final m in trip.municipalities) {
    final coord = getMunicipalityCoordinates(m);
    if (coord == null) continue;
    final dLat = coord.latitude - point.latitude;
    final dLng = coord.longitude - point.longitude;
    final distance = dLat * dLat + dLng * dLng;
    if (distance < bestDistance) {
      bestDistance = distance;
      best = m;
    }
  }
  return best ?? trip.municipalities.first;
}

/// Display name for a Trip Planner municipality.
String tripMunicipalityLabel(trip.Municipality m) {
  final short = m.shortName.trim();
  return short.isNotEmpty ? short : m.name;
}

/// Start, towns along the provincial road, and destination for Get Directions.
class SpotRoutePlaces {
  const SpotRoutePlaces({
    required this.startLabel,
    required this.startTown,
    required this.endLabel,
    required this.endTown,
    required this.viaTowns,
    required this.allTowns,
  });

  final String startLabel;
  final String startTown;
  final String endLabel;
  final String endTown;
  final List<String> viaTowns;
  final List<String> allTowns;

  bool get hasViaTowns => viaTowns.isNotEmpty;
}

/// Towns the tourist passes on the existing Trip Planner road network.
SpotRoutePlaces placesAlongSpotRoute({
  required String originLabel,
  required LatLng origin,
  required SpotMapPoint dest,
}) {
  final start = nearestTripMunicipality(origin);
  final end = tripMunicipalityFor(
    name: dest.municipality,
    latitude: dest.latitude,
    longitude: dest.longitude,
  );
  final path = municipalitiesOnRoadBetween(start, end);
  final towns = <String>[];
  final seen = <String>{};
  void addTown(String name) {
    final label = name.trim();
    if (label.isEmpty) return;
    final key = _normId(label);
    if (key.isEmpty || seen.contains(key)) return;
    seen.add(key);
    towns.add(label);
  }

  if (path != null && path.isNotEmpty) {
    for (final m in path) {
      addTown(tripMunicipalityLabel(m));
    }
  } else {
    addTown(tripMunicipalityLabel(start));
    addTown(tripMunicipalityLabel(end));
  }

  final via = towns.length <= 2
      ? const <String>[]
      : towns.sublist(1, towns.length - 1);

  return SpotRoutePlaces(
    startLabel: originLabel.trim().isEmpty ? 'Your location' : originLabel,
    startTown: towns.isNotEmpty ? towns.first : tripMunicipalityLabel(start),
    endLabel: dest.name.trim().isEmpty ? 'Destination' : dest.name.trim(),
    endTown: dest.municipality.trim().isNotEmpty
        ? dest.municipality.trim()
        : (towns.isNotEmpty ? towns.last : tripMunicipalityLabel(end)),
    viaTowns: via,
    allTowns: towns,
  );
}

trip.TouristSpot tripSpotFor(SpotMapPoint point) {
  return trip.TouristSpot(
    name: point.name,
    priceRange: '',
    imagePath: '',
    location: point.municipality.isNotEmpty
        ? point.municipality
        : point.name,
    rating: 0,
    description: '',
    type: 'spot',
    latitude: point.latitude,
    longitude: point.longitude,
    firestoreDocId: point.spotId,
  );
}

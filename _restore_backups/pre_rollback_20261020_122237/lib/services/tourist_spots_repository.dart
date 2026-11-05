import 'dart:math' as math;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:atmos_trs_system/data/tourist_spot_image_catalog.dart';
import 'package:atmos_trs_system/features/explore/explore_data.dart'
    show TouristSpot;
import 'package:atmos_trs_system/models/tourist_spot_firestore.dart';
import 'package:atmos_trs_system/utils/municipality_helper.dart';

const String _collectionId = 'tourist_spots';

/// Fetches tourist spots from Firestore `tourist_spots`.
/// Spot images come from each document's `image_url` (typically Supabase Storage).
class TouristSpotsRepository {
  TouristSpotsRepository._();

  static bool get _isFirebaseInitialized {
    try {
      return Firebase.apps.isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  static FirebaseFirestore get _firestore => FirebaseFirestore.instance;

  static List<TouristSpotFirestore>? _cachedSpots;
  static Future<List<TouristSpotFirestore>>? _spotsInFlight;

  /// Spots already fetched this session. Empty until the first successful read.
  static List<TouristSpotFirestore> peekCachedSpots() =>
      List<TouristSpotFirestore>.unmodifiable(_cachedSpots ?? const []);

  /// Clears the in-memory cache (e.g. after LGU edits).
  static void clearCache() {
    _cachedSpots = null;
    _spotsInFlight = null;
  }

  /// True when the spot should appear in the tourist app.
  static bool isEligible(TouristSpotFirestore spot) {
    final s = spot.status.trim().toLowerCase();
    if (s.isEmpty) return true;
    if (s == 'active' || s == 'approved' || s == 'published') return true;
    if (s == 'inactive' ||
        s == 'deleted' ||
        s == 'rejected' ||
        s == 'draft' ||
        s == 'pending' ||
        s == 'unapproved') {
      return false;
    }
    return true;
  }

  static bool hasValidCoordinates(TouristSpotFirestore spot) {
    if (spot.latitude == 0 && spot.longitude == 0) return false;
    if (spot.latitude < -90 || spot.latitude > 90) return false;
    if (spot.longitude < -180 || spot.longitude > 180) return false;
    return true;
  }

  /// Canonical municipality id for filtering.
  static String municipalityKeyFor(TouristSpotFirestore spot) {
    var mid = normalizeMunicipalityId(spot.municipalityId);
    if (mid.isEmpty) mid = getMunicipalityIdFromName(spot.municipality);
    if (mid.isEmpty) mid = getMunicipalityIdFromName(spot.name);
    return mid;
  }

  static bool belongsToMunicipality(
    TouristSpotFirestore spot, {
    required String municipalityIdOrName,
  }) {
    final want = normalizeMunicipalityId(municipalityIdOrName);
    final wantFromName = getMunicipalityIdFromName(municipalityIdOrName);
    final key = municipalityKeyFor(spot);
    if (key.isEmpty) {
      final loc = spot.municipality.trim().toLowerCase();
      final raw = municipalityIdOrName.trim().toLowerCase();
      if (loc.isEmpty || raw.isEmpty) return false;
      return loc == raw ||
          loc.contains(raw) ||
          raw.contains(loc.split(' ').first);
    }
    final allowed = <String>{
      want,
      wantFromName,
      ...municipalityIdsForQuery(want),
      ...municipalityIdsForQuery(wantFromName),
      ...municipalityIdsForQuery(key),
    }..remove('');
    return allowed.contains(key);
  }

  static List<TouristSpotFirestore> eligibleOnly(List<TouristSpotFirestore> spots) =>
      spots.where(isEligible).toList(growable: false);

  static List<TouristSpotFirestore> forMunicipality(
    List<TouristSpotFirestore> spots, {
    required String municipalityIdOrName,
    bool requireCoordinates = false,
  }) {
    return eligibleOnly(spots)
        .where(
          (s) =>
              belongsToMunicipality(
                s,
                municipalityIdOrName: municipalityIdOrName,
              ) &&
              (!requireCoordinates || hasValidCoordinates(s)),
        )
        .toList(growable: false);
  }

  /// Other spots in the same municipality, nearest-first when coords exist.
  static List<TouristSpotFirestore> nearbyInSameMunicipality({
    required TouristSpotFirestore current,
    required List<TouristSpotFirestore> all,
    int limit = 12,
  }) {
    final peers = forMunicipality(
      all,
      municipalityIdOrName: current.municipalityId.isNotEmpty
          ? current.municipalityId
          : current.municipality,
    ).where((s) => s.id != current.id).toList();

    final hasOrigin = hasValidCoordinates(current);
    if (hasOrigin) {
      peers.sort((a, b) {
        final da = hasValidCoordinates(a)
            ? _haversineKm(
                current.latitude,
                current.longitude,
                a.latitude,
                a.longitude,
              )
            : double.infinity;
        final db = hasValidCoordinates(b)
            ? _haversineKm(
                current.latitude,
                current.longitude,
                b.latitude,
                b.longitude,
              )
            : double.infinity;
        return da.compareTo(db);
      });
    } else {
      peers.sort((a, b) => a.name.compareTo(b.name));
    }
    if (peers.length <= limit) return peers;
    return peers.take(limit).toList(growable: false);
  }

  static double distanceKm(TouristSpotFirestore a, TouristSpotFirestore b) {
    if (!hasValidCoordinates(a) || !hasValidCoordinates(b)) return -1;
    return _haversineKm(a.latitude, a.longitude, b.latitude, b.longitude);
  }

  static double _haversineKm(
    double lat1,
    double lng1,
    double lat2,
    double lng2,
  ) {
    const earthKm = 6371.0;
    final dLat = (lat2 - lat1) * math.pi / 180;
    final dLng = (lng2 - lng1) * math.pi / 180;
    final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(lat1 * math.pi / 180) *
            math.cos(lat2 * math.pi / 180) *
            math.sin(dLng / 2) *
            math.sin(dLng / 2);
    return earthKm * 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
  }

  /// Explore-map / list card model from a Firestore spot.
  static TouristSpot toExploreSpot(TouristSpotFirestore spot) {
    final image = TouristSpotImageCatalog.displayUrlForSpot(spot);
    return TouristSpot(
      id: spot.id,
      name: spot.name,
      category: spot.category.isNotEmpty ? spot.category : 'Spot',
      imageUrl: image,
      distance: 0,
      rating: spot.rating > 0 ? spot.rating : 4.5,
      description: spot.description,
      city: spot.municipality,
      vrLink: spot.vrLink,
      latitude: spot.latitude,
      longitude: spot.longitude,
      hasVR: (spot.vrLink ?? '').trim().isNotEmpty,
    );
  }

  /// Stream of all tourist spots (for map markers and home).
  static Stream<List<TouristSpotFirestore>> streamTouristSpots() {
    if (!_isFirebaseInitialized) {
      return Stream.value(<TouristSpotFirestore>[]);
    }
    try {
      return _firestore.collection(_collectionId).snapshots().map((snap) {
        final spots = snap.docs
            .map((d) => TouristSpotFirestore.fromFirestore(d.data(), d.id))
            .toList();
        _cachedSpots = spots;
        return spots;
      }).handleError((_) => <TouristSpotFirestore>[]);
    } catch (_) {
      return Stream.value(<TouristSpotFirestore>[]);
    }
  }

  /// Stream of eligible (active/approved) spots only.
  static Stream<List<TouristSpotFirestore>> streamEligibleTouristSpots() {
    return streamTouristSpots().map(eligibleOnly);
  }

  /// One-time fetch (e.g. for initial load).
  static Future<List<TouristSpotFirestore>> getTouristSpots({
    bool forceRefresh = false,
  }) async {
    if (!forceRefresh && _cachedSpots != null) return _cachedSpots!;
    final pending = _spotsInFlight;
    if (pending != null) return pending;
    final run = _fetchTouristSpots();
    _spotsInFlight = run;
    try {
      return await run;
    } finally {
      if (identical(_spotsInFlight, run)) _spotsInFlight = null;
    }
  }

  static Future<List<TouristSpotFirestore>> getEligibleTouristSpots({
    bool forceRefresh = false,
  }) async {
    final all = await getTouristSpots(forceRefresh: forceRefresh);
    return eligibleOnly(all);
  }

  static Future<List<TouristSpotFirestore>> _fetchTouristSpots() async {
    if (!_isFirebaseInitialized) {
      return _cachedSpots ?? <TouristSpotFirestore>[];
    }
    try {
      final snap = await _firestore.collection(_collectionId).get();
      final spots = snap.docs
          .map((d) => TouristSpotFirestore.fromFirestore(d.data(), d.id))
          .toList();
      _cachedSpots = spots;
      return spots;
    } catch (_) {
      return _cachedSpots ?? <TouristSpotFirestore>[];
    }
  }

  /// Filter by category (Beach, Falls, Historical, Mountain, Resorts).
  static List<TouristSpotFirestore> filterByCategory(
    List<TouristSpotFirestore> spots,
    String? category,
  ) {
    if (category == null || category.isEmpty || category == 'All') return spots;
    return spots
        .where((s) => s.category.toLowerCase() == category.toLowerCase())
        .toList();
  }
}

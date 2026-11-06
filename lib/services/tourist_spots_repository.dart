import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:atmos_trs_system/models/tourist_spot_firestore.dart';
import 'package:atmos_trs_system/utils/municipality_helper.dart';
import 'package:atmos_trs_system/utils/tourist_spot_visibility.dart';

const String _collectionId = 'tourist_spots';

/// Fetches tourist spots from Firestore "tourist_spots" collection.
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
  static StreamSubscription<List<TouristSpotFirestore>>? _liveSub;

  /// Bumped whenever the live snapshot (or a fresh get) updates the cache.
  static final ValueNotifier<int> revision = ValueNotifier<int>(0);

  /// Keeps the session cache warm so Home / maps update without opening Explore.
  static void ensureRealtimeSync() {
    if (_liveSub != null || !_isFirebaseInitialized) return;
    _liveSub = streamTouristSpots().listen(
      (_) {},
      onError: (Object e) => debugPrint('[TouristSpots] live sync: $e'),
    );
  }

  /// Spots already fetched this session. Empty until the first successful read.
  static List<TouristSpotFirestore> peekCachedSpots() =>
      List<TouristSpotFirestore>.unmodifiable(_cachedSpots ?? const []);

  static void invalidateCache() {
    _cachedSpots = null;
    _spotsInFlight = null;
  }

  static List<TouristSpotFirestore> _activeOnly(
    Iterable<TouristSpotFirestore> spots,
  ) {
    final byId = <String, TouristSpotFirestore>{};
    for (final s in spots) {
      if (!isTouristSpotActiveStatus(s.status)) continue;
      if (s.id.trim().isEmpty) continue;
      byId[s.id] = s;
    }
    return byId.values.toList();
  }

  static void _setCache(List<TouristSpotFirestore> spots) {
    _cachedSpots = spots;
    revision.value++;
  }

  /// Live Active tourist spots (for map markers, home, municipality lists).
  static Stream<List<TouristSpotFirestore>> streamTouristSpots() {
    if (!_isFirebaseInitialized) {
      return Stream.value(<TouristSpotFirestore>[]);
    }
    try {
      return _firestore.collection(_collectionId).snapshots().map((snap) {
        final spots = _activeOnly(
          snap.docs.map((d) => TouristSpotFirestore.fromFirestore(d.data(), d.id)),
        );
        _setCache(spots);
        return spots;
      }).handleError((_) => _cachedSpots ?? <TouristSpotFirestore>[]);
    } catch (_) {
      return Stream.value(<TouristSpotFirestore>[]);
    }
  }

  /// Active spots for one municipality (by id / display name).
  static Stream<List<TouristSpotFirestore>> streamTouristSpotsForMunicipality(
    String municipalityIdOrName,
  ) {
    final want = normalizeMunicipalityId(municipalityIdOrName);
    final wantName = municipalityIdOrName.trim().toLowerCase();
    return streamTouristSpots().map((all) {
      return all.where((s) {
        final mid = normalizeMunicipalityId(
          s.municipalityId.isNotEmpty
              ? s.municipalityId
              : getMunicipalityIdFromName(s.municipality),
        );
        if (want.isNotEmpty && mid == want) return true;
        final mun = s.municipality.trim().toLowerCase();
        if (wantName.isEmpty) return false;
        return mun == wantName ||
            mun.contains(wantName) ||
            wantName.contains(mun.split(' ').first);
      }).toList();
    });
  }

  /// One-time fetch (e.g. for initial load). Returns Active spots only.
  static Future<List<TouristSpotFirestore>> getTouristSpots() async {
    if (_cachedSpots != null) return _cachedSpots!;
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

  static Future<List<TouristSpotFirestore>> _fetchTouristSpots() async {
    if (!_isFirebaseInitialized) {
      return _cachedSpots ?? <TouristSpotFirestore>[];
    }
    try {
      final snap = await _firestore.collection(_collectionId).get();
      final spots = _activeOnly(
        snap.docs.map((d) => TouristSpotFirestore.fromFirestore(d.data(), d.id)),
      );
      _setCache(spots);
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

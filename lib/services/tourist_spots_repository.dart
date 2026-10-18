import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:atmos_trs_system/models/tourist_spot_firestore.dart';

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

  /// Spots already fetched this session. Empty until the first successful read.
  static List<TouristSpotFirestore> peekCachedSpots() =>
      List<TouristSpotFirestore>.unmodifiable(_cachedSpots ?? const []);

  /// Stream of all tourist spots (for map markers and home).
  /// Returns empty stream if Firebase is not initialized.
  static Stream<List<TouristSpotFirestore>> streamTouristSpots() {
    if (!_isFirebaseInitialized) {
      return Stream.value(<TouristSpotFirestore>[]);
    }
    try {
      return _firestore
          .collection(_collectionId)
          .snapshots()
          .map((snap) => snap.docs
              .map((d) => TouristSpotFirestore.fromFirestore(d.data(), d.id))
              .toList())
          .handleError((_) => <TouristSpotFirestore>[]);
    } catch (_) {
      return Stream.value(<TouristSpotFirestore>[]);
    }
  }

  /// One-time fetch (e.g. for initial load).
  /// Returns empty list if Firebase is not initialized.
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

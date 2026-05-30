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

  /// Loads a single spot by Firestore document id (QR check-in spot id).
  static Future<TouristSpotFirestore?> getSpotById(String spotId) async {
    if (!_isFirebaseInitialized || spotId.trim().isEmpty) return null;
    try {
      final doc = await _firestore.collection(_collectionId).doc(spotId).get();
      final data = doc.data();
      if (!doc.exists || data == null) return null;
      return TouristSpotFirestore.fromFirestore(data, doc.id);
    } catch (_) {
      return null;
    }
  }

  /// One-time fetch (e.g. for initial load).
  /// Returns empty list if Firebase is not initialized.
  static Future<List<TouristSpotFirestore>> getTouristSpots() async {
    if (!_isFirebaseInitialized) {
      return <TouristSpotFirestore>[];
    }
    try {
      final snap = await _firestore.collection(_collectionId).get();
      return snap.docs
          .map((d) => TouristSpotFirestore.fromFirestore(d.data(), d.id))
          .toList();
    } catch (_) {
      return <TouristSpotFirestore>[];
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

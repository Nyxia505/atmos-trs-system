import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:atmos_trs_system/models/tourist_spot.dart';

const String _collectionId = 'tourist_spots';

/// Firestore service for tourist_spots collection.
/// Use StreamBuilder or FutureBuilder for reactive or one-time data.
class TouristSpotsFirestoreService {
  TouristSpotsFirestoreService._();

  static bool get _isFirebaseInitialized {
    try {
      return Firebase.apps.isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  static FirebaseFirestore get _firestore => FirebaseFirestore.instance;

  /// Stream of all tourist spots. Filter by municipality in the caller if needed.
  static Stream<List<TouristSpot>> streamTouristSpots() {
    if (!_isFirebaseInitialized) {
      return Stream.value(<TouristSpot>[]);
    }
    try {
      return _firestore
          .collection(_collectionId)
          .snapshots()
          .map((snap) => snap.docs
              .map((d) => TouristSpot.fromFirestore(d.data(), d.id))
              .toList())
          .handleError((_) => <TouristSpot>[]);
    } catch (_) {
      return Stream.value(<TouristSpot>[]);
    }
  }

  /// One-time fetch.
  static Future<List<TouristSpot>> getTouristSpots() async {
    if (!_isFirebaseInitialized) {
      return <TouristSpot>[];
    }
    try {
      final snap = await _firestore.collection(_collectionId).get();
      return snap.docs
          .map((d) => TouristSpot.fromFirestore(d.data(), d.id))
          .toList();
    } catch (_) {
      return <TouristSpot>[];
    }
  }

  /// Add a new spot. Returns the document id.
  static Future<String?> addSpot(TouristSpot spot) async {
    if (!_isFirebaseInitialized) return null;
    try {
      final ref = await _firestore
          .collection(_collectionId)
          .add(spot.toFirestore());
      return ref.id;
    } catch (_) {
      return null;
    }
  }

  /// Update an existing spot by id.
  static Future<bool> updateSpot(String id, Map<String, dynamic> fields) async {
    if (!_isFirebaseInitialized || id.isEmpty) return false;
    try {
      await _firestore.collection(_collectionId).doc(id).update(fields);
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Delete a spot by id.
  static Future<bool> deleteSpot(String id) async {
    if (!_isFirebaseInitialized || id.isEmpty) return false;
    try {
      await _firestore.collection(_collectionId).doc(id).delete();
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Toggle status between Active and Inactive.
  static Future<bool> updateSpotStatus(String id, String status) async {
    return updateSpot(id, {'status': status});
  }
}

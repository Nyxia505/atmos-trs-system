import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:atmos_trs_system/data/tourist_spots_default_seed.dart';
import 'package:atmos_trs_system/models/tourist_spot.dart';
import 'package:atmos_trs_system/utils/municipality_helper.dart';
import 'package:atmos_trs_system/utils/spot_qr_helper.dart';

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

  static String _bestMunicipalityId(Map<String, dynamic> data) {
    final rawId = normalizeMunicipalityId(data['municipalityId'] as String?);
    if (rawId.isNotEmpty) return rawId;
    final fromMunicipality = getMunicipalityIdFromName(
      data['municipality'] as String?,
    );
    if (fromMunicipality.isNotEmpty) return fromMunicipality;
    final fromLocation = getMunicipalityIdFromName(data['location'] as String?);
    if (fromLocation.isNotEmpty) return fromLocation;
    final fromCity = getMunicipalityIdFromName(data['city'] as String?);
    if (fromCity.isNotEmpty) return fromCity;
    return '';
  }

  static Map<String, dynamic> _seedToFirestoreMap(
    DefaultTouristSpotSeed seed,
    String mid, {
    required bool template,
  }) {
    return {
      'name': seed.name,
      'category': seed.category,
      'municipality': seed.municipality,
      'municipalityId': mid,
      'description': seed.description,
      'rating': seed.rating,
      'latitude': seed.latitude,
      'longitude': seed.longitude,
      if (seed.imageUrl != null && seed.imageUrl!.trim().isNotEmpty)
        'image_url': seed.imageUrl,
      if (seed.vrLink != null && seed.vrLink!.trim().isNotEmpty)
        'vr_link': seed.vrLink,
      'status': 'Active',
      'visitors': 0,
      'qrValue': seed.docId,
      'qr_payload': spotQrData(mid, seed.docId),
      'seeded': true,
      if (template) 'template': true,
    };
  }

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
  /// Writes [qrValue] (= new doc id), [qr_payload] (check-in URL), [createdAt] (server time).
  static Future<String?> addSpot(TouristSpot spot) async {
    if (!_isFirebaseInitialized) return null;
    try {
      final ref = _firestore.collection(_collectionId).doc();
      final data = spot.toFirestore();
      data['qrValue'] = ref.id;
      data['qr_payload'] = spotQrData(
        spot.municipalityId,
        ref.id,
        latitude: spot.latitude,
        longitude: spot.longitude,
      );
      data['createdAt'] = FieldValue.serverTimestamp();
      await ref.set(data);
      return ref.id;
    } catch (_) {
      return null;
    }
  }

  /// One-time / admin: fills [qrValue], [qr_payload], [createdAt] on old docs that lack them.
  static Future<int> backfillQrMetadata() async {
    if (!_isFirebaseInitialized) return 0;
    var n = 0;
    try {
      final snap = await _firestore.collection(_collectionId).get();
      for (final d in snap.docs) {
        final data = d.data();
        final hasQr = (data['qrValue'] ?? data['qr_value']) != null &&
            '${data['qrValue'] ?? data['qr_value']}'.trim().isNotEmpty;
        if (hasQr && data['qr_payload'] != null && data['createdAt'] != null) {
          continue;
        }
        final mid = _bestMunicipalityId(data);
        await d.reference.set({
          'qrValue': d.id,
          'qr_payload': spotQrData(
            mid,
            d.id,
            latitude: (d.data()['latitude'] as num?)?.toDouble(),
            longitude: (d.data()['longitude'] as num?)?.toDouble(),
          ),
          if (mid.isNotEmpty) 'municipalityId': mid,
          if (data['createdAt'] == null && data['created_at'] == null)
            'createdAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
        n++;
      }
    } catch (_) {}
    return n;
  }

  /// Creates any missing documents from [kDefaultTouristSpotSeeds] (by doc id).
  static Future<int> seedMissingCanonicalSpots() async {
    if (!_isFirebaseInitialized) return 0;
    var created = 0;
    try {
      for (final seed in kDefaultTouristSpotSeeds) {
        final ref = _firestore.collection(_collectionId).doc(seed.docId);
        final snap = await ref.get();
        if (snap.exists) continue;
        final mid = normalizeMunicipalityId(seed.municipalityId);
        if (mid.isEmpty) continue;
        await ref.set({
          ..._seedToFirestoreMap(seed, mid, template: false),
          'createdAt': FieldValue.serverTimestamp(),
        });
        created++;
      }
    } catch (_) {}
    return created;
  }

  /// Full maintenance sync:
  /// 1) create missing canonical spot docs, 2) backfill QR metadata.
  static Future<({int created, int backfilled})> syncAllSpotQrData() async {
    final created = await seedMissingCanonicalSpots();
    final backfilled = await backfillQrMetadata();
    return (created: created, backfilled: backfilled);
  }

  /// Strict mode: enforce exactly the 17 canonical spot documents (slug ids).
  ///
  /// - Upserts rows from [kDefaultTouristSpotSeeds] with document id == spot slug
  /// - Deletes any other documents in `tourist_spots`
  /// - Backfills QR metadata after enforcement
  static Future<({int upserted, int removed, int backfilled})>
      enforceCanonicalSpotDocuments() async {
    if (!_isFirebaseInitialized) {
      return (upserted: 0, removed: 0, backfilled: 0);
    }
    var upserted = 0;
    var removed = 0;
    final seeds = kDefaultTouristSpotSeeds;
    final canonicalIds = {for (final s in seeds) s.docId};

    final batch = _firestore.batch();
    for (final seed in seeds) {
      final mid = normalizeMunicipalityId(seed.municipalityId);
      if (mid.isEmpty) continue;
      final ref = _firestore.collection(_collectionId).doc(seed.docId);
      batch.set(
        ref,
        _seedToFirestoreMap(seed, mid, template: true),
        SetOptions(merge: true),
      );
      upserted++;
    }
    await batch.commit();

    final existing = await _firestore.collection(_collectionId).get();
    var deleteBatch = _firestore.batch();
    var ops = 0;
    for (final d in existing.docs) {
      if (canonicalIds.contains(d.id)) continue;
      deleteBatch.delete(d.reference);
      removed++;
      ops++;
      if (ops >= 450) {
        await deleteBatch.commit();
        deleteBatch = _firestore.batch();
        ops = 0;
      }
    }
    if (ops > 0) {
      await deleteBatch.commit();
    }

    final backfilled = await backfillQrMetadata();
    return (upserted: upserted, removed: removed, backfilled: backfilled);
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

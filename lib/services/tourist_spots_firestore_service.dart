import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:atmos_trs_system/data/tourist_spots_default_seed.dart';
import 'package:atmos_trs_system/data/tourist_spot_image_catalog.dart';
import 'package:atmos_trs_system/models/tourist_spot.dart';
import 'package:atmos_trs_system/utils/municipality_helper.dart';
import 'package:atmos_trs_system/utils/spot_qr_helper.dart';

const String _collectionId = 'tourist_spots';

/// Result of [TouristSpotsFirestoreService.addSpot].
class AddTouristSpotResult {
  const AddTouristSpotResult({this.id, this.error});

  final String? id;
  final String? error;

  bool get ok => id != null && id!.isNotEmpty;
}

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
      if (seed.imageUrl != null && seed.imageUrl!.trim().isNotEmpty) ...{
        'image_url': seed.imageUrl,
        'image': seed.imageUrl,
      },
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

  /// Add a new spot. Returns the document id in [AddTouristSpotResult.id].
  /// Writes [qrValue] (= new doc id), [qr_payload] (check-in URL), [createdAt].
  static Future<String?> addSpot(TouristSpot spot) async {
    final result = await addSpotDetailed(spot);
    return result.id;
  }

  /// Same as [addSpot] but surfaces a user-facing [AddTouristSpotResult.error].
  static Future<AddTouristSpotResult> addSpotDetailed(TouristSpot spot) async {
    if (!_isFirebaseInitialized) {
      return const AddTouristSpotResult(
        error: 'Firebase is not initialized. Restart the app and try again.',
      );
    }

    final mid = normalizeMunicipalityId(spot.municipalityId);
    if (mid.isEmpty) {
      return const AddTouristSpotResult(
        error: 'Missing municipality for this LGU. Sign in again with your tourism account.',
      );
    }
    final name = spot.name.trim();
    if (name.isEmpty) {
      return const AddTouristSpotResult(
        error: 'Tourist Spot Name is required.',
      );
    }

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      return const AddTouristSpotResult(
        error: 'Your session expired. Please sign in again.',
      );
    }

    try {
      await user.getIdToken(true);
    } catch (e) {
      debugPrint('[TouristSpots] getIdToken failed: $e');
      return const AddTouristSpotResult(
        error: 'Could not refresh your login. Please sign in again.',
      );
    }

    Future<AddTouristSpotResult> writeOnce() async {
      final ref = _firestore.collection(_collectionId).doc();
      final payload = <String, dynamic>{
        'name': name,
        'category': spot.category.trim().isEmpty ? 'Spot' : spot.category.trim(),
        'municipality': spot.municipality.trim().isEmpty
            ? mid
            : spot.municipality.trim(),
        'municipalityId': mid,
        'description': spot.description.trim(),
        'rating': spot.rating,
        'latitude': spot.latitude,
        'longitude': spot.longitude,
        'status': spot.status.trim().isEmpty ? 'Active' : spot.status.trim(),
        'visitors': spot.visitors,
        'qrValue': ref.id,
        'qr_payload': spotQrData(
          mid,
          ref.id,
          latitude: spot.latitude,
          longitude: spot.longitude,
        ),
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
        'createdByUid': user.uid,
        if (user.email != null && user.email!.trim().isNotEmpty)
          'createdByEmail': user.email!.trim(),
      };
      if (spot.imageUrl != null && spot.imageUrl!.trim().isNotEmpty) {
        payload['image_url'] = spot.imageUrl!.trim();
        payload['image'] = spot.imageUrl!.trim();
      }
      if (spot.vrLink != null && spot.vrLink!.trim().isNotEmpty) {
        payload['vr_link'] = spot.vrLink!.trim();
        payload['hasVR'] = true;
      }
      if (spot.dotAttractionCode.trim().isNotEmpty) {
        payload['dotAttractionCode'] = spot.dotAttractionCode.trim();
      }

      await ref.set(payload);
      return AddTouristSpotResult(id: ref.id);
    }

    try {
      return await writeOnce();
    } on FirebaseException catch (e) {
      debugPrint('[TouristSpots] addSpot FirebaseException: ${e.code} ${e.message}');
      if (e.code == 'permission-denied') {
        try {
          await user.reload();
          await FirebaseAuth.instance.currentUser?.getIdToken(true);
          return await writeOnce();
        } on FirebaseException catch (e2) {
          debugPrint(
            '[TouristSpots] addSpot retry failed: ${e2.code} ${e2.message}',
          );
          final viaCf = await _addSpotViaCloudFunction(spot, mid, name, user);
          if (viaCf.ok) return viaCf;
          return AddTouristSpotResult(
            error: viaCf.error ?? _friendlyFirestoreWriteError(e2),
          );
        } catch (e2) {
          debugPrint('[TouristSpots] addSpot retry failed: $e2');
          final viaCf = await _addSpotViaCloudFunction(spot, mid, name, user);
          if (viaCf.ok) return viaCf;
          return AddTouristSpotResult(
            error: viaCf.error ?? _friendlyFirestoreWriteError(e),
          );
        }
      }
      return AddTouristSpotResult(error: _friendlyFirestoreWriteError(e));
    } catch (e) {
      debugPrint('[TouristSpots] addSpot failed: $e');
      final viaCf = await _addSpotViaCloudFunction(spot, mid, name, user);
      if (viaCf.ok) return viaCf;
      return AddTouristSpotResult(
        error: viaCf.error ?? 'Could not save tourist spot. $e',
      );
    }
  }

  static Future<AddTouristSpotResult> _addSpotViaCloudFunction(
    TouristSpot spot,
    String mid,
    String name,
    User user,
  ) async {
    try {
      final functions = FirebaseFunctions.instanceFor(region: 'asia-southeast1');
      final callable = functions.httpsCallable(
        'createLguTouristSpot',
        options: HttpsCallableOptions(timeout: const Duration(seconds: 30)),
      );
      final response = await callable.call<Map<String, dynamic>>({
        'name': name,
        'category': spot.category,
        'municipality': spot.municipality,
        'municipalityId': mid,
        'description': spot.description,
        'rating': spot.rating,
        'latitude': spot.latitude,
        'longitude': spot.longitude,
        'status': spot.status,
        'visitors': spot.visitors,
        'image_url': spot.imageUrl,
        'vr_link': spot.vrLink,
        'dotAttractionCode': spot.dotAttractionCode,
      });
      final data = response.data;
      final id = data['id']?.toString();
      if (id != null && id.isNotEmpty) {
        return AddTouristSpotResult(id: id);
      }
      return const AddTouristSpotResult(
        error: 'Cloud Function did not return a spot id.',
      );
    } on FirebaseFunctionsException catch (e) {
      debugPrint('[TouristSpots] createLguTouristSpot CF: ${e.code} ${e.message}');
      return AddTouristSpotResult(
        error: e.message?.trim().isNotEmpty == true
            ? e.message!.trim()
            : 'Cloud Function error [${e.code}]. Deploy functions if missing.',
      );
    } catch (e) {
      debugPrint('[TouristSpots] createLguTouristSpot CF failed: $e');
      return AddTouristSpotResult(
        error:
            'Permission denied and Cloud Function fallback failed. Deploy createLguTouristSpot / firestore.rules. ($e)',
      );
    }
  }

  static String _friendlyFirestoreWriteError(FirebaseException e) {
    switch (e.code) {
      case 'permission-denied':
        return 'Permission denied writing tourist_spots. Re-login with your LGU tourism account, or publish the latest firestore.rules.';
      case 'unauthenticated':
        return 'Not authenticated. Please sign in again.';
      case 'unavailable':
        return 'Firestore is temporarily unavailable. Check your connection and try again.';
      default:
        final msg = (e.message ?? '').trim();
        if (msg.isNotEmpty) return 'Firestore [${e.code}]: $msg';
        return 'Firestore error [${e.code}].';
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

  /// Writes [image_url] and [image] on every `tourist_spots` doc from the local catalog.
  static Future<({int updated, int skipped, int missing})>
      backfillSpotImagesInFirestore({bool overwriteExisting = false}) async {
    if (!_isFirebaseInitialized) {
      return (updated: 0, skipped: 0, missing: 0);
    }
    var updated = 0;
    var skipped = 0;
    var missing = 0;
    try {
      final snap = await _firestore.collection(_collectionId).get();
      for (final d in snap.docs) {
        final data = d.data();
        final existing =
            (data['image_url'] as String? ?? data['image'] as String? ?? '')
                .trim();
        final resolved = TouristSpotImageCatalog.resolveForFirestoreDoc(
          docId: d.id,
          data: data,
        );
        if (resolved == null || resolved.isEmpty) {
          missing++;
          continue;
        }
        if (!overwriteExisting && existing.isNotEmpty) {
          skipped++;
          continue;
        }
        if (existing == resolved) {
          skipped++;
          continue;
        }
        await d.reference.set({
          'image_url': resolved,
          'image': resolved,
        }, SetOptions(merge: true));
        updated++;
      }
    } catch (_) {}
    return (updated: updated, skipped: skipped, missing: missing);
  }

  /// Full maintenance sync:
  /// 1) create missing canonical spot docs, 2) backfill QR metadata, 3) images.
  static Future<({int created, int backfilled, int imagesUpdated})>
      syncAllSpotQrData() async {
    final created = await seedMissingCanonicalSpots();
    final backfilled = await backfillQrMetadata();
    final images = await backfillSpotImagesInFirestore();
    return (
      created: created,
      backfilled: backfilled,
      imagesUpdated: images.updated,
    );
  }

  /// Upserts the 17 canonical seed spot documents (slug ids).
  ///
  /// - Merges rows from [kDefaultTouristSpotSeeds] with document id == spot slug
  /// - Never deletes LGU-created / custom spots (docs with [createdByUid], or
  ///   any non-seed id) — those must remain after Add QR Code / Add Spot
  /// - Backfills QR metadata after upsert
  static Future<
      ({
        int upserted,
        int removed,
        int backfilled,
        int imagesUpdated,
      })> enforceCanonicalSpotDocuments() async {
    if (!_isFirebaseInitialized) {
      return (
        upserted: 0,
        removed: 0,
        backfilled: 0,
        imagesUpdated: 0,
      );
    }
    var upserted = 0;
    const removed = 0;
    final seeds = kDefaultTouristSpotSeeds;

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

    // Intentionally do not delete non-canonical docs. LGU tourism officers
    // create additional spots (e.g. Ambak-Ambak Falls) that must persist.

    final backfilled = await backfillQrMetadata();
    final images = await backfillSpotImagesInFirestore(overwriteExisting: true);
    return (
      upserted: upserted,
      removed: removed,
      backfilled: backfilled,
      imagesUpdated: images.updated,
    );
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

  /// Persists unique per-spot QR fields on an existing `tourist_spots` doc.
  /// Uses [spotQrData] with [spotId] so payloads stay unique per spot.
  static Future<bool> ensureSpotQrMetadata({
    required String spotId,
    required String municipalityId,
    double? latitude,
    double? longitude,
  }) async {
    if (!_isFirebaseInitialized || spotId.trim().isEmpty) return false;
    final mid = normalizeMunicipalityId(municipalityId);
    if (mid.isEmpty) return false;
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return false;
    try {
      await user.getIdToken(true);
      final ref = _firestore.collection(_collectionId).doc(spotId.trim());
      final snap = await ref.get();
      if (!snap.exists) return false;
      final data = snap.data() ?? <String, dynamic>{};
      final lat = latitude ?? (data['latitude'] as num?)?.toDouble();
      final lng = longitude ?? (data['longitude'] as num?)?.toDouble();
      await ref.set({
        'qrValue': spotId.trim(),
        'qr_payload': spotQrData(
          mid,
          spotId.trim(),
          latitude: lat,
          longitude: lng,
        ),
        'municipalityId': mid,
        'updatedAt': FieldValue.serverTimestamp(),
        if (data['createdAt'] == null && data['created_at'] == null)
          'createdAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      return true;
    } catch (e) {
      debugPrint('[TouristSpots] ensureSpotQrMetadata failed: $e');
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

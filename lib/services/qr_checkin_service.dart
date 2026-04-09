import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:atmos_trs_system/config/auth_config.dart';
import 'package:atmos_trs_system/config/session_storage.dart';
import 'package:atmos_trs_system/utils/municipality_helper.dart';

/// Result of a QR check-in save attempt.
sealed class QRCheckInResult {
  const QRCheckInResult();
}

class QRCheckInSuccess extends QRCheckInResult {
  const QRCheckInSuccess({this.checkInId});
  final String? checkInId;
}

class QRCheckInFailure extends QRCheckInResult {
  const QRCheckInFailure(this.message);
  final String message;
}

/// Lightweight spot info for check-in (name, municipality).
class SpotInfo {
  const SpotInfo({
    required this.spotId,
    required this.spotName,
    required this.municipality,
    required this.municipalityId,
    this.latitude,
    this.longitude,
  });
  final String spotId;
  final String spotName;
  final String municipality;
  final String municipalityId;

  /// From Firestore `tourist_spots` (used for proximity check).
  final double? latitude;
  final double? longitude;
}

/// Saves QR check-ins to Firestore "qr_checkins" collection for municipality-based dashboards.
///
/// **tourist_spots** (per spot): name, municipality (e.g. "Oroquieta City"), category, description;
/// optional municipalityId (canonical id e.g. oroquieta). Document id = spot_id (in QR).
///
/// **qr_checkins** (per check-in): tourist_id, spot_id, spot_name, municipality, municipalityId, timestamp.
/// Each LGU dashboard fetches only check-ins where municipalityId matches its municipality.
class QRCheckInService {
  QRCheckInService._();

  static const String _collectionId = 'qr_checkins';
  static const String _spotsCollectionId = 'tourist_spots';

  static bool get _isFirebaseInitialized {
    try {
      return Firebase.apps.isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  static FirebaseFirestore get _firestore => FirebaseFirestore.instance;

  /// Returns the current user ID (in-memory or from session). Null if not logged in.
  static Future<String?> getCurrentUserId() async {
    if (AuthConfig.currentUserUid != null && AuthConfig.currentUserUid!.isNotEmpty) {
      return AuthConfig.currentUserUid;
    }
    final authUid = FirebaseAuth.instance.currentUser?.uid;
    if (authUid != null && authUid.isNotEmpty) {
      return authUid;
    }
    return SessionStorage.getStoredUser();
  }

  /// Fetches a tourist spot from Firestore by document id (spot_id).
  /// Uses fields: name, municipality, municipalityId (optional).
  /// If municipalityId is missing, derives it from municipality so check-ins
  /// match the correct LGU dashboard (e.g. "Oroquieta City" → oroquieta).
  static Future<SpotInfo?> getSpotById(String spotId, {String? municipalityId}) async {
    if (!_isFirebaseInitialized || spotId.isEmpty) return null;
    try {
      final doc = await _firestore.collection(_spotsCollectionId).doc(spotId.trim()).get();
      if (!doc.exists || doc.data() == null) return null;
      final d = doc.data()!;
      final name = d['name'] as String? ?? '';
      final municipality = d['municipality'] as String? ?? '';
      final docMunId = (d['municipalityId'] as String? ?? '').trim();
      final munId = docMunId.isNotEmpty
          ? normalizeMunicipalityId(docMunId)
          : getMunicipalityIdFromName(municipality);
      if (municipalityId != null && municipalityId.isNotEmpty && munId.isNotEmpty) {
        final normalized = normalizeMunicipalityId(municipalityId);
        if (normalized.isNotEmpty && munId != normalized) {
          final queryIds = municipalityIdsForQuery(municipalityId);
          if (!queryIds.contains(munId)) return null;
        }
      }
      final latRaw = d['latitude'];
      final lngRaw = d['longitude'];
      final double? lat = latRaw is num ? latRaw.toDouble() : null;
      final double? lng = lngRaw is num ? lngRaw.toDouble() : null;
      return SpotInfo(
        spotId: doc.id,
        spotName: name,
        municipality: municipality,
        municipalityId: munId.isNotEmpty ? munId : getMunicipalityIdFromName(municipality),
        latitude: lat,
        longitude: lng,
      );
    } catch (_) {
      return null;
    }
  }

  /// Saves a check-in document to "qr_checkins" for municipality-based dashboards.
  ///
  /// Each LGU dashboard fetches only check-ins where [municipalityId] matches its
  /// stored municipality (e.g. oroquieta, tangub). Stored fields:
  /// - tourist_id, spot_id, spot_name, municipality (display e.g. "Oroquieta City"), timestamp
  /// - municipalityId (canonical id for filtering), userId, spotId (same as spot_id).
  /// [spotName] and [municipality] should be set from the tourist_spots document so
  /// the correct municipality dashboard shows the right data.
  static Future<QRCheckInResult> saveCheckIn({
    required String municipalityId,
    required String spotId,
    String? userId,
    String? spotName,
    String? municipality,
  }) async {
    String? uid = userId;
    if (uid == null || uid.isEmpty) {
      uid = await getCurrentUserId();
    }
    if (uid == null || uid.isEmpty) {
      return const QRCheckInFailure('You must be logged in to check in.');
    }

    if (!_isFirebaseInitialized) {
      return const QRCheckInFailure('Firebase is not configured. Check-in saved locally.');
    }

    final normalizedMunicipalityId = normalizeMunicipalityId(municipalityId);
    if (normalizedMunicipalityId.isEmpty) {
      return const QRCheckInFailure('Invalid municipality.');
    }

    try {
      final docRef = await _firestore.collection(_collectionId).add({
        'userId': uid,
        'tourist_id': uid,
        'municipalityId': normalizedMunicipalityId,
        'spotId': spotId.trim(),
        'spot_id': spotId.trim(),
        'spot_name': spotName?.trim() ?? '',
        'municipality': municipality?.trim() ?? '',
        'timestamp': FieldValue.serverTimestamp(),
      });
      return QRCheckInSuccess(checkInId: docRef.id);
    } on FirebaseException catch (e) {
      return QRCheckInFailure(e.message ?? 'Firestore error: ${e.code}');
    } catch (e) {
      return QRCheckInFailure(e.toString());
    }
  }
}

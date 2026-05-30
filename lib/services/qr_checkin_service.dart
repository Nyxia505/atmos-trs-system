import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:atmos_trs_system/config/auth_config.dart';
import 'package:atmos_trs_system/config/qr_scan_geofence_config.dart';
import 'package:atmos_trs_system/config/session_storage.dart';
import 'package:atmos_trs_system/services/qr_scan_demo_guard.dart';
import 'package:atmos_trs_system/services/qr_scan_location_guard.dart';
import 'package:atmos_trs_system/services/user_activity_service.dart';
import 'package:atmos_trs_system/services/user_directory_service.dart';
import 'package:atmos_trs_system/utils/municipality_helper.dart';

/// Result of a QR check-in save attempt.
sealed class QRCheckInResult {
  const QRCheckInResult();
}

class QRCheckInSuccess extends QRCheckInResult {
  const QRCheckInSuccess({
    this.checkInId,
    this.checkinsDocId,
    required this.welcomeMessage,
  });
  final String? checkInId;
  final String? checkinsDocId;
  final String welcomeMessage;
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

  /// Canonical audit table: one document per scan (user_id, location_id, checkin_time).
  static const String _checkinsCollectionId = 'checkins';
  static const String _spotsCollectionId = 'tourist_spots';

  static bool get _isFirebaseInitialized {
    try {
      return Firebase.apps.isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  static FirebaseFirestore get _firestore => FirebaseFirestore.instance;

  static bool _isSameLocalDay(DateTime a, DateTime b) {
    return a.year == b.year && a.month == b.month && a.day == b.day;
  }

  static Future<String> _displayNameForUid(String uid) async {
    try {
      final profile = await UserDirectoryService.getProfileByUid(uid);
      final n = profile?.fullName?.trim();
      if (n != null && n.isNotEmpty) return n;
    } catch (_) {}
    final email = FirebaseAuth.instance.currentUser?.email ?? '';
    if (email.isNotEmpty) return email.split('@').first;
    return 'Guest';
  }

  /// Builds welcome copy after [priorCheckins] at this location (excluding the insert about to happen).
  static String _welcomeMessage({
    required String displayName,
    required String locationLabel,
    required bool alreadyCheckedInToday,
    required bool hasPriorVisitsAtLocation,
  }) {
    if (alreadyCheckedInToday) {
      return 'Welcome Back, $displayName! You already checked in today at $locationLabel.';
    }
    if (hasPriorVisitsAtLocation) {
      return 'Welcome Back, $displayName! Thank you for visiting again at $locationLabel.';
    }
    return 'Welcome, $displayName! Enjoy your visit at $locationLabel.';
  }

  /// Loads prior `checkins` for [userId] + [locationId] to classify the welcome message.
  static Future<({bool alreadyToday, bool visitedBefore})> _priorScanState({
    required String userId,
    required String locationId,
  }) async {
    if (!_isFirebaseInitialized || userId.isEmpty || locationId.isEmpty) {
      return (alreadyToday: false, visitedBefore: false);
    }
    try {
      QuerySnapshot<Map<String, dynamic>> snap;
      try {
        snap = await _firestore
            .collection(_checkinsCollectionId)
            .where('user_id', isEqualTo: userId)
            .where('location_id', isEqualTo: locationId)
            .limit(200)
            .get();
      } catch (_) {
        final all = await _firestore
            .collection(_checkinsCollectionId)
            .where('user_id', isEqualTo: userId)
            .limit(500)
            .get();
        snap = all;
      }
      final now = DateTime.now();
      var visitedBefore = false;
      var alreadyToday = false;
      for (final d in snap.docs) {
        final data = d.data();
        if (data['location_id']?.toString() != locationId) continue;
        final t = data['checkin_time'];
        if (t is! Timestamp) continue;
        visitedBefore = true;
        if (_isSameLocalDay(t.toDate(), now)) {
          alreadyToday = true;
        }
      }
      return (alreadyToday: alreadyToday, visitedBefore: visitedBefore);
    } catch (_) {
      return (alreadyToday: false, visitedBefore: false);
    }
  }

  /// Returns the current user ID (in-memory or from session). Null if not logged in.
  static Future<String?> getCurrentUserId() async {
    if (AuthConfig.currentUserUid != null &&
        AuthConfig.currentUserUid!.isNotEmpty) {
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
  static Future<SpotInfo?> getSpotById(
    String spotId, {
    String? municipalityId,
  }) async {
    if (!_isFirebaseInitialized || spotId.isEmpty) return null;
    try {
      final doc = await _firestore
          .collection(_spotsCollectionId)
          .doc(spotId.trim())
          .get();
      if (!doc.exists || doc.data() == null) return null;
      final d = doc.data()!;
      final name = d['name'] as String? ?? '';
      final municipality = d['municipality'] as String? ?? '';
      final docMunId = (d['municipalityId'] as String? ?? '').trim();
      final munId = docMunId.isNotEmpty
          ? normalizeMunicipalityId(docMunId)
          : getMunicipalityIdFromName(municipality);
      if (municipalityId != null &&
          municipalityId.isNotEmpty &&
          munId.isNotEmpty) {
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
        municipalityId: munId.isNotEmpty
            ? munId
            : getMunicipalityIdFromName(municipality),
        latitude: lat,
        longitude: lng,
      );
    } catch (_) {
      return null;
    }
  }

  /// Records every scan: writes [checkins] (user_id, location_id, checkin_time) and
  /// [qr_checkins] for LGU dashboards. Welcome message reflects prior visits today / ever.
  ///
  /// [spotId] is stored as `location_id` in `checkins`. Each LGU dashboard still uses
  /// [qr_checkins] where [municipalityId] matches (e.g. oroquieta, tangub).
  static Future<QRCheckInResult> saveCheckIn({
    required String municipalityId,
    required String spotId,
    String? userId,
    String? spotName,
    String? municipality,
  }) async {
    if (!_isFirebaseInitialized) {
      return const QRCheckInFailure(
        'Firebase is not configured. Check-in saved locally.',
      );
    }

    final authUser = FirebaseAuth.instance.currentUser;
    if (authUser == null) {
      return const QRCheckInFailure('You must be logged in to check in.');
    }
    // Firestore rules require user_id / tourist_id == request.auth.uid.
    final uid = authUser.uid;
    if (userId != null &&
        userId.isNotEmpty &&
        userId != uid) {
      debugPrint(
        '[CheckIn] Ignoring passed userId ($userId); using Auth uid=$uid',
      );
    }
    try {
      await authUser.getIdToken(true);
    } catch (_) {}

    final locationId = spotId.trim();
    if (locationId.isEmpty) {
      return const QRCheckInFailure('Invalid tourist spot.');
    }

    // Spot document is authoritative: which LGU dashboard sees this check-in.
    var resolvedSpotName = spotName?.trim() ?? '';
    var resolvedMunicipality = municipality?.trim() ?? '';
    var normalizedMunicipalityId = normalizeMunicipalityId(municipalityId);
    final spotDoc = await getSpotById(locationId);
    if (spotDoc != null) {
      if (spotDoc.municipalityId.isNotEmpty) {
        normalizedMunicipalityId = spotDoc.municipalityId;
      }
      if (resolvedSpotName.isEmpty && spotDoc.spotName.isNotEmpty) {
        resolvedSpotName = spotDoc.spotName;
      }
      if (resolvedMunicipality.isEmpty && spotDoc.municipality.isNotEmpty) {
        resolvedMunicipality = spotDoc.municipality;
      }
    }
    if (normalizedMunicipalityId.isEmpty) {
      return const QRCheckInFailure(
        'This spot has no municipality set. Ask the tourism office to update the spot in Firestore.',
      );
    }

    final demoRestriction = QrScanDemoGuard.municipalityRestrictionMessage(
      normalizedMunicipalityId,
    );
    if (demoRestriction != null) {
      return QRCheckInFailure(demoRestriction);
    }

    if (spotDoc != null &&
        spotDoc.latitude != null &&
        spotDoc.longitude != null &&
        spotDoc.latitude!.abs() > 1e-7 &&
        spotDoc.longitude!.abs() > 1e-7) {
      final proximityError = await verifyProximityToTouristSpot(
        latitude: spotDoc.latitude!,
        longitude: spotDoc.longitude!,
        spotLabel: resolvedSpotName.isNotEmpty
            ? resolvedSpotName
            : locationId,
      );
      if (proximityError != null) {
        return QRCheckInFailure(proximityError);
      }
    }

    try {
      final prior = await _priorScanState(userId: uid, locationId: locationId);
      final displayName = await _displayNameForUid(uid);
      final locationLabel =
          resolvedSpotName.isNotEmpty ? resolvedSpotName : locationId;
      final welcome = _welcomeMessage(
        displayName: displayName,
        locationLabel: locationLabel,
        alreadyCheckedInToday: prior.alreadyToday,
        hasPriorVisitsAtLocation: prior.visitedBefore,
      );

      final qrRef = _firestore.collection(_collectionId).doc();
      final checkinRef = _firestore.collection(_checkinsCollectionId).doc();

      // Tourism dashboards read qr_checkins filtered by municipalityId — write first.
      await qrRef.set({
        'userId': uid,
        'user_id': uid,
        'tourist_id': uid,
        'touristName': displayName,
        'tourist_name': displayName,
        'municipalityId': normalizedMunicipalityId,
        'spotId': locationId,
        'spot_id': locationId,
        'spot_name': resolvedSpotName,
        'municipality': resolvedMunicipality,
        'timestamp': FieldValue.serverTimestamp(),
        'checkins_ref': checkinRef.id,
      });

      // Audit row for welcome-back logic (non-fatal if rules/index lag).
      try {
        await checkinRef.set({
          'user_id': uid,
          'location_id': locationId,
          'checkin_time': FieldValue.serverTimestamp(),
        });
      } catch (e) {
        debugPrint('[CheckIn] checkins audit write skipped: $e');
      }

      // Keep a durable per-user visit counter on the tourist profile.
      // Non-fatal: check-in should still succeed even if this profile update is denied/missing.
      try {
        final patch = <String, dynamic>{
          'lastCheckInAt': FieldValue.serverTimestamp(),
        };
        if (!prior.visitedBefore) {
          patch['totalVisits'] = FieldValue.increment(1);
        }
        await _firestore
            .collection('tourists')
            .doc(uid)
            .set(patch, SetOptions(merge: true));
      } catch (_) {}

      // Mirror visit into tourist_activity so Visited Places works even if a
      // collection query is blocked before rules are redeployed.
      try {
        await UserActivityService.addVisit(
          spotId: locationId,
          spotName: locationLabel,
          category: resolvedMunicipality.isNotEmpty
              ? resolvedMunicipality
              : 'Spot',
        );
        await UserActivityService.pushVisitAndBadgeSnapshotToCloud(uid);
      } catch (e) {
        debugPrint('[CheckIn] tourist_activity mirror: $e');
      }

      return QRCheckInSuccess(
        checkInId: qrRef.id,
        checkinsDocId: checkinRef.id,
        welcomeMessage: welcome,
      );
    } on FirebaseException catch (e) {
      return QRCheckInFailure(e.message ?? 'Firestore error: ${e.code}');
    } catch (e) {
      return QRCheckInFailure(e.toString());
    }
  }

  /// Resolves canonical municipality id for a tourist spot document.
  static String resolveMunicipalityIdForSpot({
    required String spotDocId,
    String municipality = '',
    String municipalityId = '',
    String displayName = '',
  }) {
    final docMun = municipalityId.trim();
    if (docMun.isNotEmpty) {
      final n = normalizeMunicipalityId(docMun);
      if (n.isNotEmpty) return n;
    }
    final munName = municipality.trim().isNotEmpty
        ? municipality
        : displayName;
    final fromName = getMunicipalityIdFromName(munName);
    if (fromName.isNotEmpty) return fromName;
    return normalizeMunicipalityId(spotDocId);
  }

  /// Requires the device to be within [kQrScanSpotMaxDistanceMeters] of the spot anchor.
  /// Returns a user-facing error, or `null` if the location check passed.
  static Future<String?> verifyProximityToTouristSpot({
    required double latitude,
    required double longitude,
    required String spotLabel,
  }) async {
    if (latitude.abs() < 1e-6 && longitude.abs() < 1e-6) {
      return 'You must be at $spotLabel to check in. '
          'This destination has no GPS coordinates on file — scan the on-site QR code '
          'or ask the tourism office to add latitude and longitude for this spot.';
    }
    return QrScanLocationGuard.verifyNearAnchor(
      anchorLat: latitude,
      anchorLng: longitude,
      maxDistanceMeters: kQrScanSpotMaxDistanceMeters,
      spotLabel: spotLabel,
    );
  }

  /// If the QR URL embeds lat/lng, they must match the Firestore spot (anti forged print).
  static String? verifyQrCoordinatesMatchFirestore({
    required double? qrLat,
    required double? qrLng,
    required double firestoreLat,
    required double firestoreLng,
  }) {
    if (QrScanDemoGuard.shouldBypassGeofence) return null;
    if (qrLat == null || qrLng == null) return null;
    if (qrLat.abs() <= 1e-7 || qrLng.abs() <= 1e-7) return null;
    final mismatch = QrScanLocationGuard.distanceMeters(
      qrLat,
      qrLng,
      firestoreLat,
      firestoreLng,
    );
    if (mismatch > kQrScanQrVsFirestoreMaxMismatchMeters) {
      return 'This QR code does not match our records for this tourist spot. '
          'Please use the official poster from the tourism office or scan the code on site.';
    }
    return null;
  }
}

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:atmos_trs_system/config/auth_config.dart';
import 'package:atmos_trs_system/config/beta_testing_config.dart';
import 'package:atmos_trs_system/config/user_profile_storage.dart';
import 'package:atmos_trs_system/config/qr_scan_geofence_config.dart';
import 'package:atmos_trs_system/config/session_storage.dart';
import 'package:atmos_trs_system/services/qr_scan_demo_guard.dart';
import 'package:atmos_trs_system/services/qr_scan_location_guard.dart';
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
    this.dialogTitle,
  });
  final String? checkInId;
  final String? checkinsDocId;
  final String welcomeMessage;

  /// When set (e.g. repeat scan today), overrides the default "Visit registered" title.
  final String? dialogTitle;
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
  static const String _kAllowedMunicipalityId = 'oroquieta';

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
    final cached = UserProfileStorage.cachedProfile;
    if (cached != null && cached.fullName.trim().isNotEmpty) {
      return cached.fullName.trim();
    }
    try {
      final stored = await UserProfileStorage.getUserProfile();
      if (stored != null && stored.fullName.trim().isNotEmpty) {
        return stored.fullName.trim();
      }
    } catch (_) {}
    try {
      final profile = await UserDirectoryService.getProfileByUid(uid);
      final n = profile?.fullName?.trim();
      if (n != null && n.isNotEmpty) return n;
    } catch (_) {}
    try {
      final snap = await _firestore.collection('tourists').doc(uid).get();
      if (snap.exists && snap.data() != null) {
        final t = snap.data()!;
        final full = t['fullName']?.toString().trim() ?? '';
        if (full.isNotEmpty) return full;
        final parts = [
          t['firstName']?.toString().trim() ?? '',
          t['lastName']?.toString().trim() ?? '',
        ].where((s) => s.isNotEmpty);
        if (parts.isNotEmpty) return parts.join(' ');
      }
    } catch (_) {}
    final email = FirebaseAuth.instance.currentUser?.email ?? '';
    if (email.isNotEmpty) return email.split('@').first;
    return 'Guest';
  }

  static Future<Map<String, dynamic>> _touristSnapshotForCheckIn(
    String uid,
  ) async {
    if (uid.isEmpty) return {};
    try {
      final snap = await _firestore.collection('tourists').doc(uid).get();
      if (!snap.exists || snap.data() == null) return {};
      final t = snap.data()!;
      final fullName = t['fullName']?.toString().trim() ?? '';
      final first = t['firstName']?.toString().trim() ?? '';
      final last = t['lastName']?.toString().trim() ?? '';
      final composed = fullName.isNotEmpty
          ? fullName
          : [first, last].where((s) => s.isNotEmpty).join(' ');
      final email =
          (t['email'] ?? t['authEmail'] ?? '').toString().trim().toLowerCase();
      final mobile = (t['mobile'] ?? '').toString().trim();
      final nationality =
          (t['nationality'] ?? t['country'] ?? '').toString().trim();
      return {
        if (composed.isNotEmpty) ...{
          'touristFullName': composed,
          'fullName': composed,
        },
        if (email.isNotEmpty) ...{
          'touristEmail': email,
          'email': email,
        },
        if (mobile.isNotEmpty) 'touristMobile': mobile,
        if (nationality.isNotEmpty) 'touristNationality': nationality,
      };
    } catch (e) {
      debugPrint('[CheckIn] tourist profile read skipped: $e');
      return {};
    }
  }

  /// Builds thank-you copy from prior scans today at this location (before this insert).
  static ({String message, String? dialogTitle}) _welcomeMessage({
    required String displayName,
    required String locationLabel,
    required int todayScanCount,
    required bool hasPriorVisitsAtLocation,
  }) {
    if (todayScanCount >= 1) {
      return (
        message:
            'Thank you, $displayName! for scanning $locationLabel again today.',
        dialogTitle: 'Welcome back again!',
      );
    }
    if (hasPriorVisitsAtLocation) {
      return (
        message:
            'Thank you, $displayName! for scanning $locationLabel again.',
        dialogTitle: 'Thank you!',
      );
    }
    return (
      message: 'Thank you, $displayName! for scanning $locationLabel.',
      dialogTitle: 'Thank you!',
    );
  }

  /// Loads prior `checkins` for [userId] + [locationId] to classify the welcome message.
  static Future<({int todayScanCount, bool visitedBefore})> _priorScanState({
    required String userId,
    required String locationId,
  }) async {
    if (!_isFirebaseInitialized || userId.isEmpty || locationId.isEmpty) {
      return (todayScanCount: 0, visitedBefore: false);
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
      var todayScanCount = 0;
      for (final d in snap.docs) {
        final data = d.data();
        if (data['location_id']?.toString() != locationId) continue;
        final t = data['checkin_time'];
        if (t is! Timestamp) continue;
        visitedBefore = true;
        if (_isSameLocalDay(t.toDate(), now)) {
          todayScanCount++;
        }
      }
      return (todayScanCount: todayScanCount, visitedBefore: visitedBefore);
    } catch (_) {
      return (todayScanCount: 0, visitedBefore: false);
    }
  }

  /// Returns the newest `qr_checkins` doc for this user+spot within [within], if any.
  static Future<QueryDocumentSnapshot<Map<String, dynamic>>?> _recentQrCheckIn({
    required String userId,
    required String locationId,
    required Duration within,
  }) async {
    if (!_isFirebaseInitialized || userId.isEmpty || locationId.isEmpty) {
      return null;
    }
    final cutoff = DateTime.now().subtract(within);
    try {
      QuerySnapshot<Map<String, dynamic>> snap;
      try {
        snap = await _firestore
            .collection(_collectionId)
            .where('userId', isEqualTo: userId)
            .where('spotId', isEqualTo: locationId)
            .limit(20)
            .get();
      } catch (_) {
        snap = await _firestore
            .collection(_collectionId)
            .where('userId', isEqualTo: userId)
            .limit(40)
            .get();
      }
      QueryDocumentSnapshot<Map<String, dynamic>>? newest;
      DateTime? newestTime;
      for (final d in snap.docs) {
        final data = d.data();
        final spot = data['spotId']?.toString() ??
            data['spot_id']?.toString() ??
            data['touristSpotId']?.toString() ??
            '';
        if (spot != locationId) continue;
        final raw = data['timestamp'] ?? data['createdAt'];
        if (raw is! Timestamp) continue;
        final t = raw.toDate();
        if (t.isBefore(cutoff)) continue;
        if (newestTime == null || t.isAfter(newestTime)) {
          newestTime = t;
          newest = d;
        }
      }
      return newest;
    } catch (e) {
      debugPrint('[CheckIn] recent qr_checkins lookup skipped: $e');
      return null;
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
    /// True after QR registration (pending scan) — no on-site GPS required.
    bool skipProximityForRegistration = false,
    /// Total visitors for this scan (pila kabook). Clamped to ≥ 1.
    int partySize = 1,
    int femaleCount = 0,
    int maleCount = 0,
  }) async {
    final resolvedPartySize = partySize < 1 ? 1 : partySize;
    final resolvedFemales = femaleCount < 0 ? 0 : femaleCount;
    final resolvedMales = maleCount < 0 ? 0 : maleCount;
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

    if (!BetaTestingGuard.bypassValidation &&
        !isMisamisOccidentalMunicipalityId(normalizedMunicipalityId)) {
      return const QRCheckInFailure(
        'QR check-in is only available for tourist spots in Misamis Occidental.',
      );
    }

    final demoRestriction = QrScanDemoGuard.municipalityRestrictionMessage(
      normalizedMunicipalityId,
    );
    if (demoRestriction != null) {
      return QRCheckInFailure(demoRestriction);
    }

    if (!skipProximityForRegistration &&
        !BetaTestingGuard.bypassValidation &&
        spotDoc != null &&
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

    final routed = BetaTestingGuard.applyCheckInRouting(
      municipalityId: normalizedMunicipalityId,
      municipality: resolvedMunicipality,
      spotId: locationId,
      spotName: resolvedSpotName.isNotEmpty ? resolvedSpotName : locationId,
    );
    normalizedMunicipalityId = routed.municipalityId;
    resolvedMunicipality = routed.municipality;
    final routedLocationId = routed.spotId;
    if (resolvedSpotName.isEmpty) {
      resolvedSpotName = routed.spotName;
    }

    try {
      final prior = await _priorScanState(
        userId: uid,
        locationId: routedLocationId,
      );
      final touristSnap = await _touristSnapshotForCheckIn(uid);
      var displayName = await _displayNameForUid(uid);
      final profileName = touristSnap['touristFullName']?.toString().trim() ?? '';
      if (profileName.isNotEmpty) {
        displayName = profileName;
      }
      final locationLabel = resolvedSpotName.isNotEmpty
          ? resolvedSpotName
          : routedLocationId.replaceAll('_', ' ');
      final welcome = _welcomeMessage(
        displayName: displayName,
        locationLabel: locationLabel,
        todayScanCount: prior.todayScanCount,
        hasPriorVisitsAtLocation: prior.visitedBefore,
      );

      // Avoid duplicate Visit log rows from double-tap / pending+manual within minutes.
      final recent = await _recentQrCheckIn(
        userId: uid,
        locationId: routedLocationId,
        within: const Duration(minutes: 5),
      );
      if (recent != null) {
        debugPrint(
          '[CheckIn] reuse recent qr_checkins/${recent.id} '
          '(same user+spot within 5m)',
        );
        return QRCheckInSuccess(
          checkInId: recent.id,
          checkinsDocId: recent.data()['checkins_ref']?.toString(),
          welcomeMessage: welcome.message,
          dialogTitle: welcome.dialogTitle,
        );
      }

      final qrRef = _firestore.collection(_collectionId).doc();
      final checkinRef = _firestore.collection(_checkinsCollectionId).doc();

      // Tourism dashboards read qr_checkins filtered by municipalityId / lguId.
      // partySize / visitorCount = companions + 1 (one scan session → one party visit).
      await qrRef.set({
        'userId': uid,
        'user_id': uid,
        'tourist_id': uid,
        'touristName': displayName,
        'tourist_name': displayName,
        'municipalityId': normalizedMunicipalityId,
        'lguId': normalizedMunicipalityId,
        'spotId': routedLocationId,
        'spot_id': routedLocationId,
        'touristSpotId': routedLocationId,
        'spot_name': resolvedSpotName,
        'spotName': resolvedSpotName,
        'location': locationLabel,
        'municipality': resolvedMunicipality,
        'status': 'Verified',
        'source': 'qr_scan',
        'partySize': resolvedPartySize,
        'visitorCount': resolvedPartySize,
        'femaleCount': resolvedFemales,
        'maleCount': resolvedMales,
        'timestamp': FieldValue.serverTimestamp(),
        'createdAt': FieldValue.serverTimestamp(),
        'checkins_ref': checkinRef.id,
        ...touristSnap,
      });

      final saved = await qrRef.get(const GetOptions(source: Source.server));
      if (!saved.exists) {
        return const QRCheckInFailure(
          'Visit could not be saved to Firestore. Check your connection and try again.',
        );
      }

      // Audit row for welcome-back logic (non-fatal if rules/index lag).
      try {
        await checkinRef.set({
          'user_id': uid,
          'location_id': routedLocationId,
          'touristSpotId': routedLocationId,
          'lguId': normalizedMunicipalityId,
          'partySize': resolvedPartySize,
          'visitorCount': resolvedPartySize,
          'femaleCount': resolvedFemales,
          'maleCount': resolvedMales,
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
          'lastCheckInLguId': normalizedMunicipalityId,
          'lastCheckInSpotId': routedLocationId,
        };
        if (!prior.visitedBefore) {
          patch['totalVisits'] = FieldValue.increment(1);
        }
        await _firestore
            .collection('tourists')
            .doc(uid)
            .set(patch, SetOptions(merge: true));
      } catch (_) {}

      debugPrint(
        '[CheckIn] saved qr_checkins/${qrRef.id} '
        'municipalityId=$normalizedMunicipalityId spot=$routedLocationId',
      );

      return QRCheckInSuccess(
        checkInId: qrRef.id,
        checkinsDocId: checkinRef.id,
        welcomeMessage: welcome.message,
        dialogTitle: welcome.dialogTitle,
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
    if (BetaTestingGuard.bypassValidation) return null;

    if (latitude.abs() < 1e-6 && longitude.abs() < 1e-6) {
      return 'Sorry — we need you at $spotLabel to check in, but this destination '
          'has no GPS coordinates yet. Please scan the official on-site QR, or ask '
          'the tourism office to add latitude and longitude. 😊';
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
    if (BetaTestingGuard.bypassValidation) return null;

    if (qrLat == null || qrLng == null) return null;
    if (qrLat.abs() <= 1e-7 || qrLng.abs() <= 1e-7) return null;
    final mismatch = QrScanLocationGuard.distanceMeters(
      qrLat,
      qrLng,
      firestoreLat,
      firestoreLng,
    );
    if (mismatch > kQrScanQrVsFirestoreMaxMismatchMeters) {
      return 'This QR does not match our records for this tourist spot. '
          'Please use the official poster from the tourism office and scan it on site. 😊';
    }
    return null;
  }
}

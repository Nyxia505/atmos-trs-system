import 'dart:async' show unawaited;

import 'package:atmos_trs_system/config/qr_scan_geofence_config.dart';
import 'package:atmos_trs_system/services/notification_firestore_service.dart';
import 'package:atmos_trs_system/services/pending_lgu_checkin_storage.dart';
import 'package:atmos_trs_system/services/pending_spot_checkin_storage.dart';
import 'package:atmos_trs_system/services/push_notification_service.dart';
import 'package:atmos_trs_system/services/qr_checkin_service.dart';
import 'package:atmos_trs_system/services/qr_scan_location_guard.dart';
import 'package:atmos_trs_system/services/user_activity_service.dart';
import 'package:atmos_trs_system/utils/visit_record_image_resolver.dart';
import 'package:atmos_trs_system/utils/municipality_helper.dart';
import 'package:flutter/foundation.dart' show debugPrint;

/// Result of completing a QR scan made before the visitor had an account.
class PendingCheckInOutcome {
  const PendingCheckInOutcome.saved(String this.welcomeMessage)
    : failureMessage = null;
  const PendingCheckInOutcome.failed(String this.failureMessage)
    : welcomeMessage = null;

  final String? welcomeMessage;
  final String? failureMessage;

  bool get isSaved => welcomeMessage != null;
}

/// After sign-up / OTP, saves the QR scan the visitor made before they had an account.
///
/// Registration works from anywhere, but the check-in itself is only saved
/// when the device is near the scanned QR (dummy QRs excepted).
class PendingCheckinCompletionService {
  PendingCheckinCompletionService._();

  /// Clears any pending scan without saving it.
  static Future<void> discardPending() async {
    await PendingSpotCheckInStorage.clear();
    await PendingLguCheckInStorage.clear();
  }

  /// Completes a pending spot or LGU QR after verifying the device location.
  /// Returns `null` when nothing is pending.
  static Future<PendingCheckInOutcome?> completePendingAfterAuth() async {
    final spot = await PendingSpotCheckInStorage.peek();
    if (spot != null) return _completeSpot(spot);

    final lgu = await PendingLguCheckInStorage.peek();
    if (lgu != null) return _completeLgu(lgu);

    return null;
  }

  static Future<PendingCheckInOutcome> _completeSpot(
    PendingSpotCheckIn spot,
  ) async {
    var locationChecked = false;
    if (!spot.isDemoQr && !QrScanLocationGuard.isBypassed) {
      final doc = await QRCheckInService.getSpotById(
        spot.spotId,
        municipalityId: spot.municipalityId,
      );
      final lat = doc?.latitude;
      final lng = doc?.longitude;
      if (lat != null && lng != null && lat.abs() > 1e-7 && lng.abs() > 1e-7) {
        final label = (spot.spotName ?? '').trim().isNotEmpty
            ? spot.spotName!.trim()
            : (doc!.spotName.isNotEmpty ? doc.spotName : spot.spotId);
        final error = await QRCheckInService.verifyProximityToTouristSpot(
          latitude: lat,
          longitude: lng,
          spotLabel: label,
        );
        if (error != null) {
          debugPrint('[PendingCheckin] spot location rejected: $error');
          await discardPending();
          return PendingCheckInOutcome.failed(error);
        }
        locationChecked = true;
      }
    }

    final result = await QRCheckInService.saveCheckIn(
      municipalityId: spot.municipalityId,
      spotId: spot.spotId,
      spotName: spot.spotName,
      municipality: spot.municipality,
      proximityAlreadyVerified: locationChecked,
      isDemoQr: spot.isDemoQr,
      partySize: spot.partySize,
      femaleCount: spot.femaleCount,
      maleCount: spot.maleCount,
      filipinoCount: spot.filipinoCount,
      foreignCount: spot.foreignCount,
    );
    switch (result) {
      case QRCheckInSuccess(:final welcomeMessage):
        await discardPending();
        final label = (spot.spotName ?? spot.spotId).trim();
        final muni = spot.municipality?.trim() ?? '';
        final visitCategory = muni.isNotEmpty ? muni : 'Spot';
        await UserActivityService.addVisit(
          spotId: spot.spotId,
          spotName: label,
          category: visitCategory,
          imageUrl: VisitRecordImageResolver.imageForCheckIn(
            spotId: spot.spotId,
            spotName: label,
            category: visitCategory,
            municipalityId: spot.municipalityId,
          ),
        );
        await UserActivityService.syncVisitedSpotsFromQrCheckins();
        final uid = await QRCheckInService.getCurrentUserId();
        if (uid != null && uid.isNotEmpty) {
          unawaited(
            NotificationFirestoreService.createCheckInNotification(uid, label),
          );
        }
        unawaited(showCheckInLocalNotification(label));
        debugPrint(
          '[PendingCheckin] spot check-in saved: ${spot.spotId} '
          'partySize=${spot.partySize}',
        );
        return PendingCheckInOutcome.saved(welcomeMessage);
      case QRCheckInFailure(:final message):
        debugPrint('[PendingCheckin] spot check-in failed: $message');
        return PendingCheckInOutcome.failed(message);
    }
  }

  static Future<PendingCheckInOutcome> _completeLgu(
    PendingLguCheckIn lgu,
  ) async {
    final mid = normalizeMunicipalityId(lgu.municipalityId);

    if (!lgu.isDemoQr && !QrScanLocationGuard.isBypassed) {
      final center = getMunicipalityAnchorCoordinates(mid);
      final anchor = lgu.hasAnchor
          ? (lat: lgu.anchorLat!, lng: lgu.anchorLng!)
          : center;
      if (anchor != null) {
        final error = await QrScanLocationGuard.verifyNearAnchor(
          anchorLat: anchor.lat,
          anchorLng: anchor.lng,
          maxDistanceMeters: lgu.hasAnchor
              ? kQrScanLguAnchoredMaxDistanceMeters
              : kQrScanLguCenterMaxDistanceMeters,
          spotLabel: lgu.displayName,
        );
        if (error != null) {
          debugPrint('[PendingCheckin] LGU location rejected: $error');
          await discardPending();
          return PendingCheckInOutcome.failed(error);
        }
      }
    }

    final spotId = 'lgu_$mid';
    final result = await QRCheckInService.saveCheckIn(
      municipalityId: mid,
      spotId: spotId,
      spotName: 'LGU visit — ${lgu.displayName}',
      municipality: lgu.displayName,
      isDemoQr: lgu.isDemoQr,
      partySize: lgu.partySize,
      femaleCount: lgu.femaleCount,
      maleCount: lgu.maleCount,
      filipinoCount: lgu.filipinoCount,
      foreignCount: lgu.foreignCount,
    );
    switch (result) {
      case QRCheckInSuccess(:final welcomeMessage):
        await discardPending();
        final lguLabel = 'LGU visit — ${lgu.displayName}';
        await UserActivityService.addVisit(
          spotId: spotId,
          spotName: lguLabel,
          category: 'LGU',
          imageUrl: VisitRecordImageResolver.imageForMunicipalityId(mid),
        );
        final uid = await QRCheckInService.getCurrentUserId();
        if (uid != null && uid.isNotEmpty) {
          unawaited(
            NotificationFirestoreService.createCheckInNotification(
              uid,
              lguLabel,
            ),
          );
        }
        unawaited(showCheckInLocalNotification(lguLabel));
        debugPrint(
          '[PendingCheckin] LGU check-in saved: $mid '
          'partySize=${lgu.partySize}',
        );
        return PendingCheckInOutcome.saved(welcomeMessage);
      case QRCheckInFailure(:final message):
        debugPrint('[PendingCheckin] LGU check-in failed: $message');
        return PendingCheckInOutcome.failed(message);
    }
  }
}

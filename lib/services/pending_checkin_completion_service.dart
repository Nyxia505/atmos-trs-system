import 'package:atmos_trs_system/services/pending_lgu_checkin_storage.dart';
import 'package:atmos_trs_system/services/pending_spot_checkin_storage.dart';
import 'package:atmos_trs_system/services/qr_checkin_service.dart';
import 'package:atmos_trs_system/services/user_activity_service.dart';
import 'package:atmos_trs_system/utils/visit_record_image_resolver.dart';
import 'package:atmos_trs_system/utils/municipality_helper.dart';
import 'package:flutter/foundation.dart' show debugPrint;

/// After sign-up / OTP, saves the QR scan the visitor made before they had an account.
class PendingCheckinCompletionService {
  PendingCheckinCompletionService._();

  /// Completes a pending spot or LGU QR check-in. Skips GPS (registration path).
  /// Returns a welcome message on success, or null if nothing pending / failed.
  static Future<String?> completePendingAfterAuth() async {
    final spot = await PendingSpotCheckInStorage.peek();
    if (spot != null) {
      final result = await QRCheckInService.saveCheckIn(
        municipalityId: spot.municipalityId,
        spotId: spot.spotId,
        spotName: spot.spotName,
        municipality: spot.municipality,
        skipProximityForRegistration: true,
      );
      switch (result) {
        case QRCheckInSuccess(:final welcomeMessage):
          await PendingSpotCheckInStorage.clear();
          await PendingLguCheckInStorage.clear();
          final label = (spot.spotName ?? spot.spotId).trim();
          await UserActivityService.addVisit(
            spotId: spot.spotId,
            spotName: label,
            category: 'Spot',
            imageUrl: VisitRecordImageResolver.imageForCheckIn(
              spotId: spot.spotId,
              spotName: label,
              category: 'Spot',
              municipalityId: spot.municipalityId,
            ),
          );
          debugPrint('[PendingCheckin] spot check-in saved: ${spot.spotId}');
          return welcomeMessage;
        case QRCheckInFailure(:final message):
          debugPrint('[PendingCheckin] spot check-in failed: $message');
          return null;
      }
    }

    final lgu = await PendingLguCheckInStorage.peek();
    if (lgu != null) {
      final mid = normalizeMunicipalityId(lgu.municipalityId);
      final spotId = 'lgu_$mid';
      final result = await QRCheckInService.saveCheckIn(
        municipalityId: mid,
        spotId: spotId,
        spotName: 'LGU visit — ${lgu.displayName}',
        municipality: lgu.displayName,
        skipProximityForRegistration: true,
      );
      switch (result) {
        case QRCheckInSuccess(:final welcomeMessage):
          await PendingLguCheckInStorage.clear();
          await PendingSpotCheckInStorage.clear();
          await UserActivityService.addVisit(
            spotId: spotId,
            spotName: 'LGU visit — ${lgu.displayName}',
            category: 'LGU',
            imageUrl: VisitRecordImageResolver.imageForMunicipalityId(mid),
          );
          debugPrint('[PendingCheckin] LGU check-in saved: $mid');
          return welcomeMessage;
        case QRCheckInFailure(:final message):
          debugPrint('[PendingCheckin] LGU check-in failed: $message');
          return null;
      }
    }

    return null;
  }
}

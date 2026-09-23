import 'dart:async' show unawaited;

import 'package:atmos_trs_system/services/establishment_stay_service.dart';
import 'package:atmos_trs_system/services/notification_firestore_service.dart';
import 'package:atmos_trs_system/services/pending_establishment_stay_storage.dart';
import 'package:atmos_trs_system/services/pending_lgu_checkin_storage.dart';
import 'package:atmos_trs_system/services/pending_spot_checkin_storage.dart';
import 'package:atmos_trs_system/services/push_notification_service.dart';
import 'package:atmos_trs_system/services/qr_checkin_service.dart';
import 'package:atmos_trs_system/services/user_activity_service.dart';
import 'package:atmos_trs_system/utils/visit_record_image_resolver.dart';
import 'package:atmos_trs_system/utils/municipality_helper.dart';
import 'package:flutter/foundation.dart' show debugPrint;

/// After sign-up / OTP, saves the QR scan the visitor made before they had an account.
class PendingCheckinCompletionService {
  PendingCheckinCompletionService._();

  /// Last establishment stay id created during [completePendingAfterAuth], if any.
  static String? lastCompletedEstablishmentStayId;

  /// Completes a pending spot, LGU, or establishment QR. Skips GPS (registration path).
  /// Returns a welcome message on success, or null if nothing pending / failed.
  static Future<String?> completePendingAfterAuth() async {
    lastCompletedEstablishmentStayId = null;

    final est = await PendingEstablishmentStayStorage.peek();
    if (est != null) {
      try {
        final stay = await EstablishmentStayService.createPendingStay(
          establishmentId: est.establishmentId,
          municipalityId: est.municipalityId,
          businessNameHint: est.businessName,
          municipalityHint: est.municipality,
          partySize: est.partySize,
          femaleCount: est.femaleCount,
          maleCount: est.maleCount,
          filipinoCount: est.filipinoCount,
          foreignCount: est.foreignCount,
        );
        await PendingEstablishmentStayStorage.clear();
        await PendingSpotCheckInStorage.clear();
        await PendingLguCheckInStorage.clear();
        lastCompletedEstablishmentStayId = stay.id;
        final label = stay.establishmentName;
        final uid = await QRCheckInService.getCurrentUserId();
        if (uid != null && uid.isNotEmpty) {
          unawaited(
            NotificationFirestoreService.createCheckInNotification(
              uid,
              'Stay request at $label — waiting for front desk',
            ),
          );
        }
        debugPrint('[PendingCheckin] establishment stay pending: ${stay.id}');
        return 'Stay request sent to $label. Waiting for front desk confirmation.';
      } catch (e) {
        debugPrint('[PendingCheckin] establishment stay failed: $e');
        return null;
      }
    }

    final spot = await PendingSpotCheckInStorage.peek();
    if (spot != null) {
      final result = await QRCheckInService.saveCheckIn(
        municipalityId: spot.municipalityId,
        spotId: spot.spotId,
        spotName: spot.spotName,
        municipality: spot.municipality,
        skipProximityForRegistration: true,
        partySize: spot.partySize,
        femaleCount: spot.femaleCount,
        maleCount: spot.maleCount,
      );
      switch (result) {
        case QRCheckInSuccess(:final welcomeMessage):
          await PendingSpotCheckInStorage.clear();
          await PendingLguCheckInStorage.clear();
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
        partySize: lgu.partySize,
        femaleCount: lgu.femaleCount,
        maleCount: lgu.maleCount,
      );
      switch (result) {
        case QRCheckInSuccess(:final welcomeMessage):
          await PendingLguCheckInStorage.clear();
          await PendingSpotCheckInStorage.clear();
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
          return welcomeMessage;
        case QRCheckInFailure(:final message):
          debugPrint('[PendingCheckin] LGU check-in failed: $message');
          return null;
      }
    }

    return null;
  }
}

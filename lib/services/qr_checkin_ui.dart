import 'dart:async' show TimeoutException, unawaited;

import 'package:atmos_trs_system/features/navigation/tourist_web_layout.dart';
import 'package:firebase_core/firebase_core.dart' show FirebaseException;
import 'package:flutter/material.dart';
import 'package:atmos_trs_system/config/app_theme.dart';
import 'package:atmos_trs_system/config/app_theme_controller.dart';
import 'package:atmos_trs_system/services/qr_checkin_service.dart';
import 'package:atmos_trs_system/services/notification_firestore_service.dart';
import 'package:atmos_trs_system/services/push_notification_service.dart';
import 'package:atmos_trs_system/services/user_activity_service.dart';
import 'package:atmos_trs_system/utils/visit_record_image_resolver.dart';

/// Tourist-facing message for a failed scan / check-in step (no raw exceptions).
String friendlyQrScanError(Object error) {
  if (error is TimeoutException) {
    return 'The connection is slow. Check your internet and scan again.';
  }
  if (error is FirebaseException) {
    switch (error.code) {
      case 'unavailable':
      case 'network-request-failed':
      case 'deadline-exceeded':
        return 'No internet connection. Connect to Wi-Fi or mobile data, '
            'then scan again.';
      case 'permission-denied':
      case 'unauthenticated':
        return 'Your session could not be verified. Sign in again, then scan.';
    }
  }
  final text = error.toString().toLowerCase();
  if (text.contains('network') ||
      text.contains('socket') ||
      text.contains('failed host lookup') ||
      text.contains('offline')) {
    return 'No internet connection. Connect to Wi-Fi or mobile data, '
        'then scan again.';
  }
  if (error is StateError && error.message.trim().isNotEmpty) {
    return error.message;
  }
  return 'Something went wrong while reading this QR. Please scan again.';
}

/// Shows a success dialog after a QR check-in is saved.
/// Call after [QRCheckInService.saveCheckIn] returns [QRCheckInSuccess].
Future<void> showQRCheckInSuccessDialog(
  BuildContext context, {
  String? message,
  String? title,
}) {
  final body = message?.trim().isNotEmpty == true
      ? message!.trim()
      : 'Your visit has been recorded. Thank you for checking in!';
  final heading = title?.trim().isNotEmpty == true
      ? title!.trim()
      : 'Thank you!';

  return showTouristDialog<void>(
    context: context,
    barrierDismissible: false,
    barrierColor: Colors.black.withValues(alpha: 0.45),
    builder: (dialogContext) {
      return ListenableBuilder(
        listenable: AppThemeController.instance,
        builder: (context, _) {
          final accent = AppTheme.primary;
          final onAccent = AppTheme.onPrimary;

          return Dialog(
            backgroundColor: Colors.transparent,
            elevation: 0,
            insetPadding: const EdgeInsets.symmetric(horizontal: 28),
            child: Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(24),
                boxShadow: [
                  BoxShadow(
                    color: accent.withValues(alpha: 0.18),
                    blurRadius: 32,
                    offset: const Offset(0, 12),
                  ),
                ],
              ),
              padding: const EdgeInsets.fromLTRB(24, 28, 24, 20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 72,
                    height: 72,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          const Color(0xFF34D399),
                          const Color(0xFF059669),
                        ],
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFF059669).withValues(alpha: 0.35),
                          blurRadius: 16,
                          offset: const Offset(0, 6),
                        ),
                      ],
                    ),
                    child: const Icon(
                      Icons.check_rounded,
                      color: Colors.white,
                      size: 40,
                    ),
                  ),
                  const SizedBox(height: 20),
                  Text(
                    heading,
                    style: const TextStyle(
                      color: Color(0xFF111827),
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.3,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    body,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Color(0xFF6B7280),
                      fontSize: 15,
                      height: 1.5,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 24),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: () => Navigator.of(dialogContext).pop(),
                      style: FilledButton.styleFrom(
                        backgroundColor: accent,
                        foregroundColor: onAccent,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                        elevation: 0,
                      ),
                      child: const Text(
                        'OK',
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 15,
                          letterSpacing: 0.3,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      );
    },
  );
}

String _errorDialogTitle(String message) {
  final m = message.toLowerCase();
  if (m.contains('sorry') ||
      m.contains('almost there') ||
      m.contains('location') ||
      m.contains('gps') ||
      m.contains('meters') ||
      m.contains('within about') ||
      m.contains('digital') ||
      m.contains('printed') ||
      m.contains('tourist spot') ||
      m.contains('on site') ||
      m.contains('on-site')) {
    return 'Almost there';
  }
  return 'Check-in failed';
}

/// Shows an error dialog when QR check-in save fails.
void showQRCheckInErrorDialog(BuildContext context, String message) {
  showTouristDialog<void>(
    context: context,
    barrierColor: Colors.black.withValues(alpha: 0.45),
    builder: (dialogContext) {
      return ListenableBuilder(
        listenable: AppThemeController.instance,
        builder: (context, _) {
          final accent = AppTheme.primary;
          final onAccent = AppTheme.onPrimary;

          return Dialog(
            backgroundColor: Colors.transparent,
            elevation: 0,
            insetPadding: const EdgeInsets.symmetric(horizontal: 28),
            child: Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(24),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.12),
                    blurRadius: 24,
                    offset: const Offset(0, 10),
                  ),
                ],
              ),
              padding: const EdgeInsets.fromLTRB(24, 28, 24, 20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 72,
                    height: 72,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: const Color(0xFFFEE2E2),
                      border: Border.all(
                        color: const Color(0xFFFCA5A5),
                        width: 2,
                      ),
                    ),
                    child: const Icon(
                      Icons.error_outline_rounded,
                      color: Color(0xFFDC2626),
                      size: 38,
                    ),
                  ),
                  const SizedBox(height: 20),
                  Text(
                    _errorDialogTitle(message),
                    style: const TextStyle(
                      color: Color(0xFF111827),
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.3,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    message,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Color(0xFF6B7280),
                      fontSize: 15,
                      height: 1.5,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 24),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: () => Navigator.of(dialogContext).pop(),
                      style: FilledButton.styleFrom(
                        backgroundColor: accent,
                        foregroundColor: onAccent,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                        elevation: 0,
                      ),
                      child: const Text(
                        'OK',
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 15,
                          letterSpacing: 0.3,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      );
    },
  );
}

/// Performs QR check-in (save to Firestore) and shows success or error dialog.
/// Call this after a successful QR scan with the decoded [municipalityId] and [spotId].
/// Optionally pass [spotName] and [municipality] (e.g. from Firestore) to store in qr_checkins.
///
/// [onBeforeDialog] runs after the save finishes and before any dialog is shown,
/// so callers can clear loading UI while the dialog is visible.
///
/// Returns `true` if check-in was saved, `false` otherwise.
Future<bool> performQRCheckIn(
  BuildContext context, {
  required String municipalityId,
  required String spotId,
  String? userId,
  String? spotName,
  String? municipality,
  String? category,
  int partySize = 1,
  int femaleCount = 0,
  int maleCount = 0,
  VoidCallback? onBeforeDialog,
}) async {
  final result = await QRCheckInService.saveCheckIn(
    municipalityId: municipalityId,
    spotId: spotId,
    userId: userId,
    spotName: spotName,
    municipality: municipality,
    partySize: partySize,
    femaleCount: femaleCount,
    maleCount: maleCount,
  );

  if (!context.mounted) return false;
  onBeforeDialog?.call();
  if (!context.mounted) return false;

  switch (result) {
    case QRCheckInSuccess(
        :final welcomeMessage,
        :final dialogTitle,
        spotId: final savedSpotId,
        spotName: final savedSpotName,
        municipality: final savedMunicipality,
        municipalityId: final savedMunicipalityId,
      ):
      final uid = await QRCheckInService.getCurrentUserId();
      if (uid != null && uid.isNotEmpty) {
        await UserActivityService.bindToUser(uid);
      }
      final visitSpotId = () {
        final fromSave = savedSpotId?.trim() ?? '';
        if (fromSave.isNotEmpty) return fromSave;
        return spotId.trim();
      }();
      final displayName = () {
        final fromSave = savedSpotName?.trim() ?? '';
        if (fromSave.isNotEmpty) return fromSave;
        final fromArg = spotName?.trim() ?? '';
        if (fromArg.isNotEmpty) return fromArg;
        return visitSpotId.replaceAll('_', ' ');
      }();
      final muniLabel = (savedMunicipality ?? municipality)?.trim() ?? '';
      final visitCategory = (category != null && category.trim().isNotEmpty)
          ? category.trim()
          : (muniLabel.isNotEmpty ? muniLabel : 'Spot');
      final visitMunicipalityId =
          (savedMunicipalityId ?? municipalityId).trim();

      // Persist Visited BEFORE the dialog so Home sees it as soon as we navigate.
      await UserActivityService.addVisit(
        spotId: visitSpotId,
        spotName: displayName,
        category: visitCategory,
        imageUrl: VisitRecordImageResolver.imageForCheckIn(
          spotId: visitSpotId,
          spotName: displayName,
          category: visitCategory,
          municipalityId: visitMunicipalityId,
        ),
      );
      // Force a second local write path: sync from Firestore so Home Visited
      // matches qr_checkins even if prefs were read with a stale uid scope.
      final synced = await UserActivityService.syncVisitedSpotsFromQrCheckins();
      if (synced.every((v) => v.spotId != visitSpotId) && visitSpotId.isNotEmpty) {
        await UserActivityService.addVisit(
          spotId: visitSpotId,
          spotName: displayName,
          category: visitCategory,
          imageUrl: VisitRecordImageResolver.imageForCheckIn(
            spotId: visitSpotId,
            spotName: displayName,
            category: visitCategory,
            municipalityId: visitMunicipalityId,
          ),
        );
      }

      if (!context.mounted) return true;
      await showQRCheckInSuccessDialog(
        context,
        message: welcomeMessage,
        title: dialogTitle,
      );
      if (uid != null && uid.isNotEmpty) {
        unawaited(
          NotificationFirestoreService.createCheckInNotification(
            uid,
            displayName,
          ),
        );
      }
      unawaited(showCheckInLocalNotification(displayName));
      return true;
    case QRCheckInFailure(:final message):
      showQRCheckInErrorDialog(context, message);
      return false;
  }
}

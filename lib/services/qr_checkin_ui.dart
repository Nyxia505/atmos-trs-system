import 'package:flutter/material.dart';
import 'package:atmos_trs_system/config/app_theme.dart';
import 'package:atmos_trs_system/config/app_theme_controller.dart';
import 'package:atmos_trs_system/services/qr_checkin_service.dart';
import 'package:atmos_trs_system/services/notification_firestore_service.dart';
import 'package:atmos_trs_system/services/user_activity_service.dart';

/// Shows a success dialog after a QR check-in is saved.
/// Call after [QRCheckInService.saveCheckIn] returns [QRCheckInSuccess].
Future<void> showQRCheckInSuccessDialog(BuildContext context, {String? message}) {
  final body = message?.trim().isNotEmpty == true
      ? message!.trim()
      : 'Your visit has been recorded. Thank you for checking in!';

  return showDialog<void>(
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
                  const Text(
                    'Visit registered',
                    style: TextStyle(
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
      m.contains('location') ||
      m.contains('gps') ||
      m.contains('meters') ||
      m.contains('within about')) {
    return 'Almost there';
  }
  return 'Check-in failed';
}

/// Shows an error dialog when QR check-in save fails.
void showQRCheckInErrorDialog(BuildContext context, String message) {
  showDialog<void>(
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
/// Returns `true` if check-in was saved, `false` otherwise.
Future<bool> performQRCheckIn(
  BuildContext context, {
  required String municipalityId,
  required String spotId,
  String? userId,
  String? spotName,
  String? municipality,
}) async {
  final result = await QRCheckInService.saveCheckIn(
    municipalityId: municipalityId,
    spotId: spotId,
    userId: userId,
    spotName: spotName,
    municipality: municipality,
  );

  if (!context.mounted) return false;

  switch (result) {
    case QRCheckInSuccess(:final welcomeMessage):
      await showQRCheckInSuccessDialog(context, message: welcomeMessage);
      final uid = await QRCheckInService.getCurrentUserId();
      final displayName = (spotName ?? spotId).trim();
      await UserActivityService.addVisit(
        spotId: spotId,
        spotName: displayName,
        category: (municipality ?? '').trim().isNotEmpty
            ? municipality!.trim()
            : 'Spot',
      );
      if (uid != null && uid.isNotEmpty) {
        NotificationFirestoreService.createCheckInNotification(uid, displayName);
      }
      return true;
    case QRCheckInFailure(:final message):
      showQRCheckInErrorDialog(context, message);
      return false;
  }
}

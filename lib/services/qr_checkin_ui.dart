import 'package:flutter/material.dart';
import 'package:atmos_trs_system/config/app_theme.dart';
import 'package:atmos_trs_system/services/qr_checkin_service.dart';
import 'package:atmos_trs_system/services/notification_firestore_service.dart';

/// Shows a success dialog after a QR check-in is saved.
/// Call after [QRCheckInService.saveCheckIn] returns [QRCheckInSuccess].
void showQRCheckInSuccessDialog(BuildContext context) {
  showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (context) => AlertDialog(
      backgroundColor: AppTheme.cardBackground,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Row(
        children: [
          Icon(Icons.check_circle, color: AppTheme.primary, size: 28),
          const SizedBox(width: 12),
          const Text(
            'Check-in saved',
            style: TextStyle(color: Colors.white, fontSize: 20),
          ),
        ],
      ),
      content: Text(
        'Your visit has been recorded. Thank you for checking in!',
        style: TextStyle(color: AppTheme.unselectedMuted, fontSize: 15),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text('OK', style: TextStyle(color: AppTheme.primary, fontWeight: FontWeight.w600)),
        ),
      ],
    ),
  );
}

/// Shows an error dialog when QR check-in save fails.
void showQRCheckInErrorDialog(BuildContext context, String message) {
  showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      backgroundColor: AppTheme.cardBackground,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Row(
        children: [
          Icon(Icons.error_outline, color: Colors.red.shade300, size: 28),
          const SizedBox(width: 12),
          const Text(
            'Check-in failed',
            style: TextStyle(color: Colors.white, fontSize: 20),
          ),
        ],
      ),
      content: Text(
        message,
        style: TextStyle(color: AppTheme.unselectedMuted, fontSize: 15),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text('OK', style: TextStyle(color: AppTheme.primary, fontWeight: FontWeight.w600)),
        ),
      ],
    ),
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
    case QRCheckInSuccess():
      showQRCheckInSuccessDialog(context);
      final uid = await QRCheckInService.getCurrentUserId();
      if (uid != null && uid.isNotEmpty) {
        final spotDisplay = (spotName ?? spotId).trim();
        NotificationFirestoreService.createCheckInNotification(uid, spotDisplay);
      }
      return true;
    case QRCheckInFailure(:final message):
      showQRCheckInErrorDialog(context, message);
      return false;
  }
}

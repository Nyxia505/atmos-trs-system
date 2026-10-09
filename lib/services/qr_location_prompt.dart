import 'dart:async';

import 'package:atmos_trs_system/config/app_theme.dart';
import 'package:atmos_trs_system/features/navigation/tourist_web_layout.dart';
import 'package:atmos_trs_system/services/qr_scan_location_guard.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';

/// Makes sure Location is on and allowed before a QR check-in GPS check.
///
/// Shows a dialog with a fix action (turn on Location / allow access / open
/// settings) and re-checks after the tourist returns. Returns `true` when the
/// device can provide a location, or when location rules do not apply
/// (bypass mode, non-phone devices — the guard reports those itself).
Future<bool> ensureQrLocationReady(
  BuildContext context, {
  String? spotLabel,
}) async {
  if (QrScanLocationGuard.isBypassed || !QrScanLocationGuard.isPhone) {
    return true;
  }
  for (var attempt = 0; attempt < 4; attempt++) {
    final issue = await QrScanLocationGuard.checkReadiness();
    if (issue == null) return true;
    if (!context.mounted) return false;
    final proceed = await _showLocationDialog(context, issue, spotLabel);
    if (proceed != true) return false;
    if (kIsWeb) continue;
    switch (issue) {
      case QrLocationIssue.serviceOff:
        if (await Geolocator.openLocationSettings()) await _waitForResume();
      case QrLocationIssue.permissionBlocked:
        if (await Geolocator.openAppSettings()) await _waitForResume();
      case QrLocationIssue.permissionDenied:
        break;
    }
  }
  return false;
}

Future<void> _waitForResume() {
  final done = Completer<void>();
  late final AppLifecycleListener listener;
  listener = AppLifecycleListener(
    onResume: () {
      if (!done.isCompleted) done.complete();
    },
  );
  return done.future
      .timeout(const Duration(minutes: 2), onTimeout: () {})
      .whenComplete(listener.dispose);
}

Future<bool?> _showLocationDialog(
  BuildContext context,
  QrLocationIssue issue,
  String? spotLabel,
) {
  final message = kIsWeb && issue != QrLocationIssue.serviceOff
      ? 'Location access is needed to check in. Please allow it in your '
            'browser, then tap Try again.'
      : QrScanLocationGuard.messageForIssue(issue, spotLabel: spotLabel);
  final actionLabel = kIsWeb
      ? 'Try again'
      : switch (issue) {
          QrLocationIssue.serviceOff => 'Turn on Location',
          QrLocationIssue.permissionDenied => 'Allow Location',
          QrLocationIssue.permissionBlocked => 'Open Settings',
        };

  return showTouristDialog<bool>(
    context: context,
    barrierDismissible: false,
    barrierColor: Colors.black.withValues(alpha: 0.45),
    builder: (dialogContext) => Dialog(
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
        padding: const EdgeInsets.fromLTRB(24, 28, 24, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppTheme.primary.withValues(alpha: 0.12),
              ),
              child: Icon(
                Icons.location_on_rounded,
                color: AppTheme.primary,
                size: 38,
              ),
            ),
            const SizedBox(height: 20),
            const Text(
              'Location needed',
              style: TextStyle(
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
                onPressed: () => Navigator.of(dialogContext).pop(true),
                style: FilledButton.styleFrom(
                  backgroundColor: AppTheme.primary,
                  foregroundColor: AppTheme.onPrimary,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                  elevation: 0,
                ),
                child: Text(
                  actionLabel,
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 15,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 4),
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text(
                'Not now',
                style: TextStyle(
                  color: Color(0xFF6B7280),
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

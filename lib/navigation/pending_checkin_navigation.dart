import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:atmos_trs_system/services/pending_checkin_completion_service.dart';
import 'package:atmos_trs_system/services/pending_lgu_checkin_storage.dart';
import 'package:atmos_trs_system/services/pending_spot_checkin_storage.dart';
import 'package:atmos_trs_system/services/qr_checkin_ui.dart';
import 'package:atmos_trs_system/services/qr_location_prompt.dart';

String? landingWelcomeMessageForPending({
  PendingSpotCheckIn? spot,
  PendingLguCheckIn? lgu,
}) {
  const next = kIsWeb
      ? 'Continue on the website, download the app for VR tours, or plan your itinerary.'
      : 'Open a VR tour or plan your itinerary from your dashboard.';
  if (spot != null) {
    final place = spot.spotName?.trim().isNotEmpty == true
        ? spot.spotName!.trim()
        : 'your scanned spot';
    final mun = spot.municipality?.trim();
    if (mun != null && mun.isNotEmpty) {
      return 'Welcome to $mun! Your check-in at $place is saved. $next';
    }
    return 'Your check-in at $place is saved. $next';
  }
  if (lgu != null) {
    return 'Welcome to ${lgu.displayName}! Your municipality visit is saved. $next';
  }
  return null;
}

/// Shown when the account was created but the pending scan was not saved.
const String _kAccountReadyTitle = 'Your account is ready';

/// After tourist login or OTP verification, completes a pending QR scan (registration)
/// then opens the dashboard or landing page.
///
/// Registration itself works from anywhere; before the pending check-in is
/// saved, Location must be on and the device must be near the scanned QR.
Future<void> navigateToPendingSpotCheckInOrDashboard(
  BuildContext context, {
  required String defaultRoute,
  required bool isTouristDestination,
  bool preferLandingAfterPendingCheckIn = false,
}) async {
  if (!isTouristDestination) {
    await PendingCheckinCompletionService.discardPending();
    if (context.mounted) {
      Navigator.pushNamedAndRemoveUntil(context, defaultRoute, (route) => false);
    }
    return;
  }

  final pendingSpot = await PendingSpotCheckInStorage.peek();
  final pendingLgu = await PendingLguCheckInStorage.peek();

  if (pendingSpot == null && pendingLgu == null) {
    if (context.mounted) {
      Navigator.pushNamedAndRemoveUntil(context, defaultRoute, (route) => false);
    }
    return;
  }

  final isDemoQr = pendingSpot?.isDemoQr ?? pendingLgu?.isDemoQr ?? false;
  final spotLabel = pendingSpot != null
      ? pendingSpot.spotName
      : pendingLgu?.displayName;

  PendingCheckInOutcome? outcome;
  if (!isDemoQr) {
    if (!context.mounted) return;
    final ready = await ensureQrLocationReady(context, spotLabel: spotLabel);
    if (!ready) {
      await PendingCheckinCompletionService.discardPending();
      outcome = PendingCheckInOutcome.failed(
        'To check in at ${_placeLabel(spotLabel)}, turn on Location and '
        'scan the QR code again while you\'re there.',
      );
    }
  }
  outcome ??= await PendingCheckinCompletionService.completePendingAfterAuth();

  if (!context.mounted) return;

  final failure = outcome?.failureMessage;
  if (failure != null) {
    await showQRCheckInErrorDialog(
      context,
      failure,
      title: _kAccountReadyTitle,
    );
    if (!context.mounted) return;
  }

  final saved = outcome?.isSaved == true;

  if (preferLandingAfterPendingCheckIn && kIsWeb) {
    final landingMessage = saved
        ? landingWelcomeMessageForPending(spot: pendingSpot, lgu: pendingLgu) ??
              outcome?.welcomeMessage
        : null;
    Navigator.pushNamedAndRemoveUntil(
      context,
      '/landing',
      (route) => false,
      arguments: <String, dynamic>{
        if (saved) 'fromQrRegistration': true,
        'welcomeMessage': landingMessage ?? 'Welcome to ATMOS-TRS!',
      },
    );
    return;
  }

  final welcome = outcome?.welcomeMessage;
  if (welcome != null) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(welcome),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 5),
      ),
    );
  }
  Navigator.pushNamedAndRemoveUntil(context, defaultRoute, (route) => false);
}

String _placeLabel(String? label) {
  final l = (label ?? '').trim();
  return l.isNotEmpty ? l : 'the tourist spot';
}

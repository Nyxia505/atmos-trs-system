import 'package:flutter/material.dart';
import 'package:atmos_trs_system/services/pending_checkin_completion_service.dart';
import 'package:atmos_trs_system/services/pending_lgu_checkin_storage.dart';
import 'package:atmos_trs_system/services/pending_spot_checkin_storage.dart';

String? _landingWelcomeMessage({
  PendingSpotCheckIn? spot,
  PendingLguCheckIn? lgu,
}) {
  if (spot != null) {
    final place = spot.spotName?.trim().isNotEmpty == true
        ? spot.spotName!.trim()
        : 'your scanned spot';
    final mun = spot.municipality?.trim();
    if (mun != null && mun.isNotEmpty) {
      return 'Welcome to $mun! Your check-in at $place is saved. '
          'Explore VR tours, plan your itinerary, or open the app when you\'re ready.';
    }
    return 'Your check-in at $place is saved. '
        'Explore VR tours, plan your itinerary, or open the app when you\'re ready.';
  }
  if (lgu != null) {
    return 'Welcome to ${lgu.displayName}! Your municipality visit is saved. '
        'Explore VR tours, plan your itinerary, or open the app when you\'re ready.';
  }
  return null;
}

/// After tourist login or OTP verification, completes a pending QR scan (registration)
/// then opens the dashboard or landing page.
Future<void> navigateToPendingSpotCheckInOrDashboard(
  BuildContext context, {
  required String defaultRoute,
  required bool isTouristDestination,
  /// When true and a pending QR exists, land on [/landing] with welcome args
  /// instead of [defaultRoute] (used after new-tourist OTP verification).
  bool preferLandingAfterPendingCheckIn = false,
}) async {
  if (!isTouristDestination) {
    await PendingSpotCheckInStorage.clear();
    await PendingLguCheckInStorage.clear();
    if (context.mounted) {
      Navigator.pushNamedAndRemoveUntil(context, defaultRoute, (route) => false);
    }
    return;
  }

  final pendingSpot = await PendingSpotCheckInStorage.peek();
  final pendingLgu = await PendingLguCheckInStorage.peek();

  if (pendingSpot != null || pendingLgu != null) {
    final landingMessage = preferLandingAfterPendingCheckIn
        ? _landingWelcomeMessage(spot: pendingSpot, lgu: pendingLgu)
        : null;

    final welcome =
        await PendingCheckinCompletionService.completePendingAfterAuth();

    if (!context.mounted) return;

    if (preferLandingAfterPendingCheckIn) {
      Navigator.pushNamedAndRemoveUntil(
        context,
        '/landing',
        (route) => false,
        arguments: <String, dynamic>{
          'fromQrRegistration': true,
          'welcomeMessage': landingMessage ?? welcome ?? 'Welcome to ATMOS-TRS!',
        },
      );
      return;
    }

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
    return;
  }

  if (context.mounted) {
    Navigator.pushNamedAndRemoveUntil(context, defaultRoute, (route) => false);
  }
}

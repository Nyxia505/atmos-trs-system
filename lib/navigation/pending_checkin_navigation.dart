import 'package:flutter/material.dart';
import 'package:atmos_trs_system/screens/establishment_stay_pending_screen.dart';
import 'package:atmos_trs_system/services/pending_checkin_completion_service.dart';
import 'package:atmos_trs_system/services/pending_establishment_stay_storage.dart';
import 'package:atmos_trs_system/services/pending_lgu_checkin_storage.dart';
import 'package:atmos_trs_system/services/pending_spot_checkin_storage.dart';

String? landingWelcomeMessageForPending({
  PendingSpotCheckIn? spot,
  PendingLguCheckIn? lgu,
  PendingEstablishmentStay? establishment,
}) {
  if (establishment != null) {
    final place = establishment.businessName?.trim().isNotEmpty == true
        ? establishment.businessName!.trim()
        : 'the establishment';
    return 'Your stay request at $place was sent. '
        'Front desk will confirm details — open Stays to watch for your receipt.';
  }
  if (spot != null) {
    final place = spot.spotName?.trim().isNotEmpty == true
        ? spot.spotName!.trim()
        : 'your scanned spot';
    final mun = spot.municipality?.trim();
    if (mun != null && mun.isNotEmpty) {
      return 'Welcome to $mun! Your check-in at $place is saved. '
          'Continue on the website, download the app for VR tours, or plan your itinerary.';
    }
    return 'Your check-in at $place is saved. '
        'Continue on the website, download the app for VR tours, or plan your itinerary.';
  }
  if (lgu != null) {
    return 'Welcome to ${lgu.displayName}! Your municipality visit is saved. '
        'Continue on the website, download the app for VR tours, or plan your itinerary.';
  }
  return null;
}

String? _landingWelcomeMessage({
  PendingSpotCheckIn? spot,
  PendingLguCheckIn? lgu,
  PendingEstablishmentStay? establishment,
}) =>
    landingWelcomeMessageForPending(
      spot: spot,
      lgu: lgu,
      establishment: establishment,
    );

/// After tourist login or OTP verification, completes a pending QR scan (registration)
/// then opens the dashboard, stay pending screen, or landing page.
Future<void> navigateToPendingSpotCheckInOrDashboard(
  BuildContext context, {
  required String defaultRoute,
  required bool isTouristDestination,
  bool preferLandingAfterPendingCheckIn = false,
}) async {
  if (!isTouristDestination) {
    await PendingSpotCheckInStorage.clear();
    await PendingLguCheckInStorage.clear();
    await PendingEstablishmentStayStorage.clear();
    if (context.mounted) {
      Navigator.pushNamedAndRemoveUntil(context, defaultRoute, (route) => false);
    }
    return;
  }

  final pendingSpot = await PendingSpotCheckInStorage.peek();
  final pendingLgu = await PendingLguCheckInStorage.peek();
  final pendingEst = await PendingEstablishmentStayStorage.peek();

  if (pendingSpot != null || pendingLgu != null || pendingEst != null) {
    final landingMessage = preferLandingAfterPendingCheckIn
        ? _landingWelcomeMessage(
            spot: pendingSpot,
            lgu: pendingLgu,
            establishment: pendingEst,
          )
        : null;

    final welcome =
        await PendingCheckinCompletionService.completePendingAfterAuth();

    if (!context.mounted) return;

    final stayId =
        PendingCheckinCompletionService.lastCompletedEstablishmentStayId;

    if (preferLandingAfterPendingCheckIn) {
      Navigator.pushNamedAndRemoveUntil(
        context,
        '/landing',
        (route) => false,
        arguments: <String, dynamic>{
          'fromQrRegistration': true,
          'welcomeMessage': landingMessage ?? welcome ?? 'Welcome to ATMOS-TRS!',
          if (stayId != null) 'establishmentStayId': stayId,
        },
      );
      return;
    }

    if (stayId != null && stayId.isNotEmpty) {
      Navigator.pushNamedAndRemoveUntil(context, defaultRoute, (route) => false);
      if (!context.mounted) return;
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => EstablishmentStayPendingScreen(stayId: stayId),
        ),
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

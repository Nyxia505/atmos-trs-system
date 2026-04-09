import 'package:flutter/material.dart';
import 'package:atmos_trs_system/screens/lgu_checkin_screen.dart';
import 'package:atmos_trs_system/screens/spot_checkin_screen.dart';
import 'package:atmos_trs_system/services/pending_lgu_checkin_storage.dart';
import 'package:atmos_trs_system/services/pending_spot_checkin_storage.dart';
import 'package:atmos_trs_system/services/qr_checkin_service.dart';

/// After tourist login or OTP verification, opens [SpotCheckInScreen] or [LguCheckInScreen]
/// if a scan was deferred.
Future<void> navigateToPendingSpotCheckInOrDashboard(
  BuildContext context, {
  required String defaultRoute,
  required bool isTouristDestination,
}) async {
  if (!isTouristDestination) {
    await PendingSpotCheckInStorage.clear();
    await PendingLguCheckInStorage.clear();
    if (context.mounted) {
      Navigator.pushReplacementNamed(context, defaultRoute);
    }
    return;
  }

  final pendingSpot = await PendingSpotCheckInStorage.peek();
  if (pendingSpot != null) {
    final spot = await QRCheckInService.getSpotById(
      pendingSpot.spotId,
      municipalityId: pendingSpot.municipalityId,
    );
    if (spot == null) {
      await PendingSpotCheckInStorage.clear();
    } else {
      await PendingSpotCheckInStorage.clear();
      if (!context.mounted) return;
      Navigator.pushReplacement(
        context,
        MaterialPageRoute<void>(
          builder: (_) => SpotCheckInScreen(spotInfo: spot),
        ),
      );
      return;
    }
  }

  final pendingLgu = await PendingLguCheckInStorage.peek();
  if (pendingLgu != null) {
    await PendingLguCheckInStorage.clear();
    if (!context.mounted) return;
    Navigator.pushReplacement(
      context,
      MaterialPageRoute<void>(
        builder: (_) => LguCheckInScreen(
          municipalityId: pendingLgu.municipalityId,
          displayName: pendingLgu.displayName,
        ),
      ),
    );
    return;
  }

  if (context.mounted) {
    Navigator.pushReplacementNamed(context, defaultRoute);
  }
}

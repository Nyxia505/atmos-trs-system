import 'dart:math' as math;

import 'package:flutter/foundation.dart' show kIsWeb, kDebugMode;
import 'package:geolocator/geolocator.dart';
import 'package:atmos_trs_system/config/qr_scan_geofence_config.dart';

/// Verifies the device is near the expected coordinates before honoring a QR scan.
class QrScanLocationGuard {
  QrScanLocationGuard._();

  /// Returns `null` if OK, or a user-facing error message.
  static Future<String?> verifyNearAnchor({
    required double anchorLat,
    required double anchorLng,
    required double maxDistanceMeters,
  }) async {
    if (kDebugMode && kQrScanBypassGeofenceInDebug) {
      return null;
    }

    if (anchorLat.abs() < 1e-6 && anchorLng.abs() < 1e-6) {
      return 'This QR code has no valid location. Ask the tourism office to update coordinates.';
    }

    if (kIsWeb) {
      return 'QR proximity check runs in the mobile app with GPS. Please use the ATMOS TRS app on your phone.';
    }

    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      return 'Turn on location services so we can confirm you are at the site.';
    }

    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied) {
      return 'Location permission is required to verify you are near this QR code.';
    }
    if (permission == LocationPermission.deniedForever) {
      return 'Location is blocked for this app. Open Settings and allow location to check in.';
    }

    final Position pos = await Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 0,
      ),
    );

    final double distance = _haversineMeters(
      anchorLat,
      anchorLng,
      pos.latitude,
      pos.longitude,
    );

    if (distance > maxDistanceMeters) {
      final int dRound = distance.round();
      final int maxRound = maxDistanceMeters.round();
      return 'Sorry, you must scan this QR within about $maxRound meters of the site. '
          'You appear to be about $dRound m away — go to the location and try again.';
    }

    return null;
  }

  static double _haversineMeters(
    double lat1,
    double lon1,
    double lat2,
    double lon2,
  ) {
    const earthRadiusM = 6371000.0;
    final dLat = _rad(lat2 - lat1);
    final dLon = _rad(lon2 - lon1);
    final a =
        math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(_rad(lat1)) *
            math.cos(_rad(lat2)) *
            math.sin(dLon / 2) *
            math.sin(dLon / 2);
    final c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
    return earthRadiusM * c;
  }

  static double _rad(double deg) => deg * math.pi / 180.0;
}

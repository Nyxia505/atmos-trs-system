import 'dart:math' as math;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:geolocator/geolocator.dart';
import 'package:atmos_trs_system/config/qr_scan_geofence_config.dart';
import 'package:atmos_trs_system/services/qr_scan_demo_guard.dart';

/// Verifies the device is near the expected coordinates before honoring a QR scan.
class QrScanLocationGuard {
  QrScanLocationGuard._();

  /// Haversine distance in meters (also used to compare QR vs Firestore anchors).
  static double distanceMeters(
    double lat1,
    double lon1,
    double lat2,
    double lon2,
  ) =>
      _haversineMeters(lat1, lon1, lat2, lon2);

  /// Returns `null` if OK, or a user-facing error message.
  static Future<String?> verifyNearAnchor({
    required double anchorLat,
    required double anchorLng,
    required double maxDistanceMeters,
    String? spotLabel,
  }) async {
    if (QrScanDemoGuard.shouldBypassGeofence) {
      return null;
    }

    if (anchorLat.abs() < 1e-6 && anchorLng.abs() < 1e-6) {
      return 'This QR code has no valid location. Ask the tourism office to update coordinates.';
    }

    if (kIsWeb) {
      return 'QR check-in with GPS works in the ATMOS TRS mobile app. '
          'Please open the app on your phone at the tourist spot.';
    }

    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      return 'Please turn on Location (GPS) in your phone settings, then try scanning again. '
          'We use your location only to confirm you are at the site — printed QR codes work when you are there.';
    }

    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied) {
      return 'We need location permission to confirm you are at the tourist spot. '
          'Allow location when prompted, then scan again.';
    }
    if (permission == LocationPermission.deniedForever) {
      return 'Location is turned off for ATMOS TRS. Open your phone Settings → Apps → ATMOS TRS → Permissions → allow Location, then try again.';
    }

    Position pos;
    try {
      pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.best,
          distanceFilter: 0,
          timeLimit: Duration(seconds: 18),
        ),
      );
    } catch (_) {
      return 'We could not get your GPS position. Step outside for a clearer signal, wait a few seconds, and scan again.';
    }

    final accuracy = pos.accuracy;
    if (accuracy > kQrScanRejectIfAccuracyWorseThanMeters) {
      return 'Your GPS signal is still settling. Wait a moment outdoors, then scan again.';
    }

    final double distance = distanceMeters(
      anchorLat,
      anchorLng,
      pos.latitude,
      pos.longitude,
    );

    final buffer = math.min(
      accuracy > 0 ? accuracy : kQrScanSpotGpsAccuracyBufferMeters,
      kQrScanSpotGpsAccuracyBufferMeters,
    );
    final effectiveMax = maxDistanceMeters + buffer;

    if (distance > effectiveMax) {
      final label = (spotLabel ?? '').trim();
      final place = label.isNotEmpty ? label : 'this tourist spot';
      final int shownTarget = maxDistanceMeters.round();
      if (distance > 500) {
        return 'Sorry — you need to be at $place to check in (within about $shownTarget meters of the site). '
            'This code is registered for that location; scanning a photo or print from somewhere else will not work. '
            'Visit the spot and try again.';
      }
      return 'Sorry — you need to be within about $shownTarget meters of $place to scan this QR. '
          'Printed codes work when you are on site. Move closer and try again.';
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

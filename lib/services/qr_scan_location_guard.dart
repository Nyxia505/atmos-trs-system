import 'dart:math' as math;

import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:geolocator/geolocator.dart';
import 'package:atmos_trs_system/config/beta_testing_config.dart';
import 'package:atmos_trs_system/config/qr_scan_geofence_config.dart';

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
    if (BetaTestingGuard.bypassValidation) {
      return null;
    }

    if (kDebugMode && kQrScanBypassGeofenceInDebug) {
      return null;
    }

    if (anchorLat.abs() < 1e-6 && anchorLng.abs() < 1e-6) {
      return 'This QR is missing location details. Please ask the tourism office to '
          'add coordinates for this spot, then scan again on site. 😊';
    }

    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      return 'Please turn on Location so we can confirm you are at the tourist spot. '
          'We only use GPS for check-in — digital or printed QR codes work when you are there. 😊';
    }

    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied) {
      return 'Please allow Location so we can confirm you are at the tourist spot. '
          'Then scan the official QR on site. 😊';
    }
    if (permission == LocationPermission.deniedForever) {
      return 'Location is off for ATMOS-TRS. Open your device settings, allow Location, '
          'then scan again when you are at the tourist spot. 😊';
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
      return 'We could not get your location yet. Step outdoors for a clearer signal, '
          'wait a few seconds, then scan again. 😊';
    }

    final accuracy = pos.accuracy;
    if (accuracy > kQrScanRejectIfAccuracyWorseThanMeters) {
      return 'Your location signal is still settling. Wait a moment outdoors, '
          'then scan again. 😊';
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
        return 'Sorry — digital or printed QR codes only work when you\'re actually '
            'at the tourist spot. Please visit $place, turn on Location, then scan '
            'the official QR there. We\'re glad you\'re exploring Misamis Occidental! 😊';
      }
      return 'Almost there! Move a little closer to $place (within about '
          '$shownTarget meters of the site QR), then scan again. '
          'Printed or digital codes work — you just need to be on site. 😊';
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

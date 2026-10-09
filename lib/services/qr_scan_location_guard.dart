import 'dart:math' as math;

import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform, kDebugMode;
import 'package:geolocator/geolocator.dart';
import 'package:atmos_trs_system/config/beta_testing_config.dart';
import 'package:atmos_trs_system/config/qr_scan_geofence_config.dart';

/// Tourist-facing copy for QR check-in location rules.
abstract final class QrScanMessages {
  static String _place(String? label) {
    final l = (label ?? '').trim();
    return l.isNotEmpty ? l : 'this tourist spot';
  }

  static String notAtSpot(String? spotLabel) =>
      'Sorry, check-in is only available at ${_place(spotLabel)}. '
      'Please scan the official QR code when you\'re there.';

  static String moveCloser(String? spotLabel) =>
      'You\'re close! Please move closer to the official QR code at '
      '${_place(spotLabel)}, then scan again.';

  static const String screenQr =
      'This QR code is shown on a screen and can\'t be used for check-in. '
      'Please scan the official printed QR code on site.';

  static const String phoneOnly =
      'QR check-in works on mobile phones only. Please open ATMOS-TRS on your '
      'phone at the tourist spot.';

  static String locationOff(String? spotLabel) =>
      'Please turn on Location so we can confirm you\'re at '
      '${_place(spotLabel)}.';

  static const String permissionDenied =
      'Location access is needed to check in. Please allow it when asked.';

  static const String permissionBlocked =
      'Location access is needed to check in. Please allow it in your phone '
      'settings.';

  static const String weakSignal =
      'We\'re still finding your location. Please wait a moment and try again.';

  static const String noFix =
      'We couldn\'t get your location. Please make sure Location is on, then '
      'try again.';

  static String missingCoordinates(String? spotLabel) =>
      '${_place(spotLabel)} isn\'t set up for check-in yet. Please ask the '
      'tourism office for help.';

  static const String qrMismatch =
      'This QR code doesn\'t match our records. Please scan the official QR '
      'code posted on site.';

  static const String notCheckInQr =
      'This isn\'t an ATMOS check-in QR code. Please scan the official QR code '
      'posted at the tourist spot or tourism office.';
}

/// Why the device cannot provide a location for a check-in yet.
enum QrLocationIssue { serviceOff, permissionDenied, permissionBlocked }

/// Verifies the device is near the expected coordinates before honoring a QR scan.
class QrScanLocationGuard {
  QrScanLocationGuard._();

  static Position? _lastFix;
  static DateTime? _lastFixAt;
  static Future<Position>? _inFlightFix;

  /// Haversine distance in meters (also used to compare QR vs Firestore anchors).
  static double distanceMeters(
    double lat1,
    double lon1,
    double lat2,
    double lon2,
  ) => _haversineMeters(lat1, lon1, lat2, lon2);

  /// True when location rules are skipped (beta mode / debug bypass).
  static bool get isBypassed =>
      BetaTestingGuard.bypassValidation ||
      (kDebugMode && kQrScanBypassGeofenceInDebug);

  /// Laptops / PCs cannot prove they are at the spot (no real GPS).
  static bool get isPhone =>
      defaultTargetPlatform == TargetPlatform.android ||
      defaultTargetPlatform == TargetPlatform.iOS;

  /// Checks Location is on and allowed, requesting permission if needed.
  /// Returns `null` when a position can be read.
  static Future<QrLocationIssue?> checkReadiness() async {
    if (!await Geolocator.isLocationServiceEnabled()) {
      return QrLocationIssue.serviceOff;
    }
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.deniedForever) {
      return QrLocationIssue.permissionBlocked;
    }
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.unableToDetermine) {
      return QrLocationIssue.permissionDenied;
    }
    return null;
  }

  static String messageForIssue(QrLocationIssue issue, {String? spotLabel}) =>
      switch (issue) {
        QrLocationIssue.serviceOff => QrScanMessages.locationOff(spotLabel),
        QrLocationIssue.permissionDenied => QrScanMessages.permissionDenied,
        QrLocationIssue.permissionBlocked => QrScanMessages.permissionBlocked,
      };

  /// Returns `null` if OK, or a user-facing error message.
  static Future<String?> verifyNearAnchor({
    required double anchorLat,
    required double anchorLng,
    required double maxDistanceMeters,
    String? spotLabel,
  }) async {
    if (isBypassed) return null;

    if (!isPhone) return QrScanMessages.phoneOnly;

    if (anchorLat.abs() < 1e-6 && anchorLng.abs() < 1e-6) {
      return QrScanMessages.missingCoordinates(spotLabel);
    }

    final issue = await checkReadiness();
    if (issue != null) return messageForIssue(issue, spotLabel: spotLabel);

    String? evaluate(Position pos) => _evaluate(
      pos,
      anchorLat: anchorLat,
      anchorLng: anchorLng,
      maxDistanceMeters: maxDistanceMeters,
      spotLabel: spotLabel,
    );

    try {
      final cached = _recentFix();
      if (cached != null && evaluate(cached) == null) return null;
      // Never refuse on a reused fix — the tourist may have walked closer.
      final error = evaluate(await currentPosition(fresh: cached != null));
      if (error != null) _lastFix = null;
      return error;
    } catch (_) {
      return QrScanMessages.noFix;
    }
  }

  static String? _evaluate(
    Position pos, {
    required double anchorLat,
    required double anchorLng,
    required double maxDistanceMeters,
    String? spotLabel,
  }) {
    final distance = distanceMeters(
      anchorLat,
      anchorLng,
      pos.latitude,
      pos.longitude,
    );
    final accuracy = pos.accuracy > 0
        ? pos.accuracy
        : kQrScanSpotGpsAccuracyBufferMeters;
    final buffer = math.min(accuracy, kQrScanSpotGpsAccuracyBufferMeters);

    if (distance <= maxDistanceMeters + buffer) return null;

    // A coarse fix that could still place the device inside the radius.
    if (accuracy > kQrScanRejectIfAccuracyWorseThanMeters &&
        distance - accuracy <= maxDistanceMeters) {
      return QrScanMessages.weakSignal;
    }
    if (distance <= kNearbySpotNotifyRadiusMeters) {
      return QrScanMessages.moveCloser(spotLabel);
    }
    return QrScanMessages.notAtSpot(spotLabel);
  }

  static Position? _recentFix() {
    final cached = _lastFix;
    final at = _lastFixAt;
    if (cached == null || at == null) return null;
    return DateTime.now().difference(at) <= kQrScanPositionReuseWindow
        ? cached
        : null;
  }

  /// Current GPS fix, reusing a recent one unless [fresh]. Concurrent callers
  /// share one GPS request. Callers must ensure Location is ready first.
  static Future<Position> currentPosition({bool fresh = false}) {
    if (!fresh) {
      final recent = _recentFix();
      if (recent != null) return Future.value(recent);
    }
    return _inFlightFix ??= () async {
      try {
        final pos = await Geolocator.getCurrentPosition(
          locationSettings: const LocationSettings(
            accuracy: LocationAccuracy.high,
            distanceFilter: 0,
            timeLimit: Duration(seconds: 15),
          ),
        );
        _lastFix = pos;
        _lastFixAt = DateTime.now();
        return pos;
      } finally {
        _inFlightFix = null;
      }
    }();
  }

  /// True when Location is on and already allowed (never shows a prompt).
  static Future<bool> isReadySilently() async {
    try {
      if (!await Geolocator.isLocationServiceEnabled()) return false;
      final permission = await Geolocator.checkPermission();
      return permission == LocationPermission.whileInUse ||
          permission == LocationPermission.always;
    } catch (_) {
      return false;
    }
  }

  /// Starts a GPS fix in the background so the next scan doesn't wait for it.
  static Future<void> prewarm() async {
    if (isBypassed || !isPhone) return;
    if (!await isReadySilently()) return;
    try {
      await currentPosition();
    } catch (_) {}
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

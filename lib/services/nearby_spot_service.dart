import 'dart:convert';

import 'package:atmos_trs_system/config/qr_scan_geofence_config.dart';
import 'package:atmos_trs_system/services/push_notification_service.dart';
import 'package:atmos_trs_system/services/qr_scan_location_guard.dart';
import 'package:atmos_trs_system/services/spot_location_cache.dart';
import 'package:flutter/foundation.dart' show debugPrint, kIsWeb;
import 'package:shared_preferences/shared_preferences.dart';

/// A cached tourist spot and how far the device is from it.
class NearbySpot {
  const NearbySpot({required this.spot, required this.distanceMeters});

  final CachedSpot spot;
  final double distanceMeters;
}

/// On app open / resume: refreshes the device spot cache, reads GPS once
/// (without prompting), remembers which spots are within
/// [kNearbySpotNotifyRadiusMeters], and notifies "{spot} QR near you!".
///
/// The GPS fix is shared with [QrScanLocationGuard], so a scan soon after
/// usually doesn't wait for GPS or the network.
class NearbySpotService {
  NearbySpotService._();

  static const _kNotifiedAt = 'nearby_spot_notified_at_v1';

  static DateTime? _lastCheckAt;
  static Future<void>? _running;
  static List<NearbySpot> _nearby = const [];

  /// Spots within the nearby radius from the last check, nearest first.
  static List<NearbySpot> get nearby => _nearby;

  /// Runs at most once per [kNearbySpotCheckInterval] unless [force].
  static Future<void> checkNow({bool force = false}) {
    if (kIsWeb || QrScanLocationGuard.isBypassed || !QrScanLocationGuard.isPhone) {
      return Future.value();
    }
    final last = _lastCheckAt;
    if (!force &&
        last != null &&
        DateTime.now().difference(last) < kNearbySpotCheckInterval) {
      return Future.value();
    }
    return _running ??= _check().whenComplete(() => _running = null);
  }

  static Future<void> _check() async {
    _lastCheckAt = DateTime.now();
    try {
      await SpotLocationCache.ensureLoaded();
      if (SpotLocationCache.isEmpty) {
        await SpotLocationCache.refresh();
      } else {
        // Coordinates already on the device; update quietly for next time.
        SpotLocationCache.refresh().ignore();
      }
      if (SpotLocationCache.isEmpty) return;
      if (!await QrScanLocationGuard.isReadySilently()) return;

      final pos = await QrScanLocationGuard.currentPosition();
      final found = <NearbySpot>[
        for (final s in SpotLocationCache.all)
          NearbySpot(
            spot: s,
            distanceMeters: QrScanLocationGuard.distanceMeters(
              s.latitude,
              s.longitude,
              pos.latitude,
              pos.longitude,
            ),
          ),
      ].where((n) => n.distanceMeters <= kNearbySpotNotifyRadiusMeters).toList()
        ..sort((a, b) => a.distanceMeters.compareTo(b.distanceMeters));
      _nearby = List.unmodifiable(found);
      if (found.isEmpty) return;

      debugPrint(
        '[Nearby] ${found.length} spot(s) within '
        '${kNearbySpotNotifyRadiusMeters.round()} m; nearest '
        '${found.first.spot.id} at ${found.first.distanceMeters.round()} m',
      );
      await _notifyNearest(found.first.spot);
    } catch (e) {
      debugPrint('[Nearby] check skipped: $e');
    }
  }

  static Future<void> _notifyNearest(CachedSpot spot) async {
    final prefs = await SharedPreferences.getInstance();
    final notified = _readNotified(prefs);
    final now = DateTime.now().millisecondsSinceEpoch;
    final last = notified[spot.id];
    if (last != null &&
        now - last < kNearbySpotNotifyCooldown.inMilliseconds) {
      return;
    }
    notified[spot.id] = now;
    notified.removeWhere(
      (_, at) => now - at > kNearbySpotNotifyCooldown.inMilliseconds * 4,
    );
    await prefs.setString(_kNotifiedAt, jsonEncode(notified));
    await showNearbySpotLocalNotification(
      spotId: spot.id,
      spotName: spot.name,
    );
  }

  static Map<String, int> _readNotified(SharedPreferences prefs) {
    try {
      final raw = prefs.getString(_kNotifiedAt);
      if (raw == null || raw.isEmpty) return {};
      final map = jsonDecode(raw);
      if (map is! Map) return {};
      return {
        for (final e in map.entries)
          if (e.value is int) e.key.toString(): e.value as int,
      };
    } catch (_) {
      return {};
    }
  }
}

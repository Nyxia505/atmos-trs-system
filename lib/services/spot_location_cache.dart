import 'dart:convert';

import 'package:atmos_trs_system/config/qr_scan_geofence_config.dart';
import 'package:atmos_trs_system/services/tourist_spots_firestore_service.dart';
import 'package:atmos_trs_system/utils/municipality_helper.dart';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:shared_preferences/shared_preferences.dart';

/// Tourist spot with check-in coordinates, stored on the device.
class CachedSpot {
  const CachedSpot({
    required this.id,
    required this.name,
    required this.municipality,
    required this.municipalityId,
    required this.latitude,
    required this.longitude,
    this.imageUrl,
    this.category,
  });

  final String id;
  final String name;
  final String municipality;
  final String municipalityId;
  final double latitude;
  final double longitude;
  final String? imageUrl;
  final String? category;

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'municipality': municipality,
    'municipalityId': municipalityId,
    'lat': latitude,
    'lng': longitude,
    if (imageUrl != null) 'imageUrl': imageUrl,
    if (category != null) 'category': category,
  };

  static CachedSpot? fromJson(Map<String, dynamic> j) {
    final id = (j['id'] as String? ?? '').trim();
    final lat = j['lat'];
    final lng = j['lng'];
    if (id.isEmpty || lat is! num || lng is! num) return null;
    return CachedSpot(
      id: id,
      name: j['name'] as String? ?? '',
      municipality: j['municipality'] as String? ?? '',
      municipalityId: j['municipalityId'] as String? ?? '',
      latitude: lat.toDouble(),
      longitude: lng.toDouble(),
      imageUrl: j['imageUrl'] as String?,
      category: j['category'] as String?,
    );
  }
}

/// Device copy of active tourist spots with coordinates, so QR scans and the
/// "QR near you" check work without waiting on a slow connection.
class SpotLocationCache {
  SpotLocationCache._();

  static const _kSpots = 'spot_location_cache_v1';
  static const _kSavedAt = 'spot_location_cache_saved_at_v1';

  static Map<String, CachedSpot> _byId = {};
  static DateTime? _savedAt;
  static bool _loaded = false;
  static Future<void>? _refreshing;

  static Iterable<CachedSpot> get all => _byId.values;

  static bool get isEmpty => _byId.isEmpty;

  /// Spot from the device cache (call [ensureLoaded] first).
  static CachedSpot? spotById(String spotId) => _byId[spotId.trim()];

  static Future<void> ensureLoaded() async {
    if (_loaded) return;
    _loaded = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_kSpots);
      final at = prefs.getInt(_kSavedAt);
      _savedAt = at == null ? null : DateTime.fromMillisecondsSinceEpoch(at);
      if (raw == null || raw.isEmpty) return;
      final list = jsonDecode(raw);
      if (list is! List) return;
      _byId = {
        for (final e in list.whereType<Map>())
          if (CachedSpot.fromJson(Map<String, dynamic>.from(e))
              case final spot?)
            spot.id: spot,
      };
    } catch (e) {
      debugPrint('[SpotCache] load failed: $e');
    }
  }

  /// Stores one spot read from Firestore (e.g. a scan before the cache had it).
  static Future<void> remember(CachedSpot spot) async {
    await ensureLoaded();
    _byId = {..._byId, spot.id: spot};
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        _kSpots,
        jsonEncode([for (final s in _byId.values) s.toJson()]),
      );
    } catch (e) {
      debugPrint('[SpotCache] remember failed: $e');
    }
  }

  static bool get isStale =>
      _savedAt == null ||
      DateTime.now().difference(_savedAt!) > kSpotLocationCacheMaxAge;

  /// Refreshes from Firestore when stale (or [force]). Concurrent calls share
  /// one request. Keeps the old cache if the fetch fails or returns nothing.
  static Future<void> refresh({bool force = false}) async {
    await ensureLoaded();
    if (!force && !isStale && _byId.isNotEmpty) return;
    return _refreshing ??= _fetch().whenComplete(() => _refreshing = null);
  }

  static Future<void> _fetch() async {
    final spots = await TouristSpotsFirestoreService.getTouristSpots();
    final next = <String, CachedSpot>{};
    for (final s in spots) {
      if (s.status.trim().toLowerCase() == 'inactive') continue;
      if (s.latitude.abs() < 1e-7 || s.longitude.abs() < 1e-7) continue;
      final mid = normalizeMunicipalityId(s.municipalityId).isNotEmpty
          ? normalizeMunicipalityId(s.municipalityId)
          : getMunicipalityIdFromName(s.municipality);
      next[s.id] = CachedSpot(
        id: s.id,
        name: s.name,
        municipality: s.municipality,
        municipalityId: mid,
        latitude: s.latitude,
        longitude: s.longitude,
        imageUrl: s.imageUrl,
        category: s.category,
      );
    }
    if (next.isEmpty) return;
    _byId = next;
    _savedAt = DateTime.now();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        _kSpots,
        jsonEncode([for (final s in next.values) s.toJson()]),
      );
      await prefs.setInt(_kSavedAt, _savedAt!.millisecondsSinceEpoch);
    } catch (e) {
      debugPrint('[SpotCache] save failed: $e');
    }
    debugPrint('[SpotCache] cached ${next.length} spots with coordinates');
  }
}

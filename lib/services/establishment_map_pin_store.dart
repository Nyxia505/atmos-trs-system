import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:http/http.dart' as http;

import 'package:atmos_trs_system/config/supabase_storage_config.dart';
import 'package:atmos_trs_system/services/supabase_storage_upload.dart';

/// Establishment map pins on free-tier-friendly Supabase Storage (not Firebase).
///
/// Object: `establishments/{uid}/map_pin.json`
abstract final class EstablishmentMapPinStore {
  static String objectKeyFor(String establishmentId) =>
      'establishments/${establishmentId.trim()}/map_pin.json';

  static String publicUrlFor(String establishmentId) =>
      SupabaseStorageConfig.publicUrlForObjectKey(objectKeyFor(establishmentId));

  static Future<void> save({
    required String establishmentId,
    required double latitude,
    required double longitude,
  }) async {
    final id = establishmentId.trim();
    if (id.isEmpty) throw StateError('Missing establishment id.');
    final payload = utf8.encode(
      jsonEncode({
        'latitude': latitude,
        'longitude': longitude,
        'updatedAt': DateTime.now().toUtc().toIso8601String(),
      }),
    );
    await SupabaseStorageUpload.uploadBytes(
      objectKey: objectKeyFor(id),
      bytes: Uint8List.fromList(payload),
      contentType: 'application/json',
    );
  }

  static Future<({double latitude, double longitude})?> load(
    String establishmentId,
  ) async {
    final id = establishmentId.trim();
    if (id.isEmpty) return null;
    try {
      final response = await http
          .get(Uri.parse(publicUrlFor(id)))
          .timeout(const Duration(seconds: 4));
      if (response.statusCode != 200) return null;
      final decoded = jsonDecode(response.body);
      if (decoded is! Map) return null;
      final lat = _asDouble(decoded['latitude']);
      final lng = _asDouble(decoded['longitude']);
      if (lat.abs() < 1e-6 && lng.abs() < 1e-6) return null;
      return (latitude: lat, longitude: lng);
    } catch (e) {
      debugPrint('[EstMapPinStore] load $id: $e');
      return null;
    }
  }

  static double _asDouble(dynamic raw) {
    if (raw is double) return raw;
    if (raw is num) return raw.toDouble();
    return double.tryParse(raw?.toString() ?? '') ?? 0;
  }
}

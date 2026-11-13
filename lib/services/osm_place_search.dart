import 'dart:convert';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:http/http.dart' as http;

/// One OpenStreetMap place suggestion. No API key.
class OsmPlaceHit {
  const OsmPlaceHit({
    required this.label,
    required this.latitude,
    required this.longitude,
    this.name = '',
    this.address = '',
    this.state = '',
  });

  final String label;
  final double latitude;
  final double longitude;

  /// Business / place name when available.
  final String name;

  /// Street / city line without the name.
  final String address;

  /// OSM `state` (e.g. Misamis Occidental).
  final String state;
}

/// Approximate Misamis Occidental center for search bias.
const double kMisamisOccidentalBiasLat = 8.35;
const double kMisamisOccidentalBiasLng = 123.84;

/// Nominatim viewbox: left,top,right,bottom (Misamis Occidental).
const String kMisamisOccidentalViewbox = '123.40,8.75,124.05,8.05';

/// Searches places near an LGU using OpenStreetMap Nominatim.
///
/// Photon (`photon.komoot.io`) was timing out, which left the map search on
/// "Location search is unavailable" and never moved the pin.
class OsmPlaceSearch {
  OsmPlaceSearch._();

  static Future<List<OsmPlaceHit>> search({
    required String query,
    double? biasLatitude,
    double? biasLongitude,
    String? nearPlace,
    bool preferMisamisOccidental = true,
  }) async {
    final typed = query.trim();
    if (typed.length < 2) return const [];

    var q = typed;
    final near = nearPlace?.trim() ?? '';
    if (near.isNotEmpty && !typed.toLowerCase().contains(near.toLowerCase())) {
      q = '$typed, $near, Misamis Occidental';
    } else if (preferMisamisOccidental &&
        !typed.toLowerCase().contains('misamis')) {
      q = '$typed, Misamis Occidental';
    }

    final params = <String, String>{
      'q': q,
      'format': 'jsonv2',
      'limit': '6',
      'addressdetails': '1',
      'countrycodes': 'ph',
      'accept-language': 'en',
    };
    if (preferMisamisOccidental) {
      params['viewbox'] = kMisamisOccidentalViewbox;
      params['bounded'] = '0';
    }

    final headers = <String, String>{
      'Accept': 'application/json',
      if (!kIsWeb)
        'User-Agent': 'ATMOS-TRS Misamis Occidental tourism office',
    };

    final uri = Uri.https('nominatim.openstreetmap.org', '/search', params);
    final response = await http
        .get(uri, headers: headers)
        .timeout(const Duration(seconds: 10));
    if (response.statusCode != 200) {
      throw StateError('Place search failed (${response.statusCode}).');
    }
    final decoded = jsonDecode(response.body);
    if (decoded is! List) return const [];

    final hits = <OsmPlaceHit>[];
    for (final feature in decoded) {
      if (feature is! Map) continue;
      final lat = double.tryParse(feature['lat']?.toString() ?? '');
      final lng = double.tryParse(feature['lon']?.toString() ?? '');
      if (lat == null || lng == null) continue;

      final address = feature['address'];
      final addressMap = address is Map ? address : const <String, dynamic>{};
      final country =
          addressMap['country']?.toString().toLowerCase() ?? 'philippines';
      if (country.isNotEmpty && country != 'philippines') continue;

      final name = (feature['name']?.toString() ?? '').trim();
      final display = (feature['display_name']?.toString() ?? '').trim();
      final city = (addressMap['city']?.toString() ??
              addressMap['town']?.toString() ??
              addressMap['municipality']?.toString() ??
              addressMap['village']?.toString() ??
              '')
          .trim();
      final state = (addressMap['state']?.toString() ?? '').trim();
      final label = display.isNotEmpty
          ? display
          : [name, city, state].where((p) => p.isNotEmpty).join(', ');
      if (label.isEmpty) continue;

      hits.add(
        OsmPlaceHit(
          label: label,
          name: name.isNotEmpty ? name : label.split(',').first.trim(),
          address: [city, state].where((p) => p.isNotEmpty).join(', '),
          state: state,
          latitude: lat,
          longitude: lng,
        ),
      );
    }

    if (preferMisamisOccidental && hits.length > 1) {
      hits.sort((a, b) {
        final aLocal = _isMisocc(a);
        final bLocal = _isMisocc(b);
        if (aLocal != bLocal) return aLocal ? -1 : 1;
        final anchorLat = biasLatitude ?? kMisamisOccidentalBiasLat;
        final anchorLng = biasLongitude ?? kMisamisOccidentalBiasLng;
        return _roughDistance(a, anchorLat, anchorLng)
            .compareTo(_roughDistance(b, anchorLat, anchorLng));
      });
    }
    return hits;
  }

  static double _roughDistance(OsmPlaceHit hit, double lat, double lng) {
    final dLat = hit.latitude - lat;
    final dLng = hit.longitude - lng;
    return dLat * dLat + dLng * dLng;
  }

  static bool _isMisocc(OsmPlaceHit hit) {
    final s = hit.state.toLowerCase();
    final l = hit.label.toLowerCase();
    return s.contains('misamis occidental') ||
        l.contains('misamis occidental') ||
        s.contains('mis. occ') ||
        l.contains('mis. occ');
  }
}

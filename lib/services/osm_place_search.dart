import 'dart:convert';

import 'package:http/http.dart' as http;

/// One OpenStreetMap place suggestion. No API key; Photon uses OSM data.
class OsmPlaceHit {
  const OsmPlaceHit({
    required this.label,
    required this.latitude,
    required this.longitude,
  });

  final String label;
  final double latitude;
  final double longitude;
}

/// Searches places near an LGU anchor using the OSM Photon index.
class OsmPlaceSearch {
  OsmPlaceSearch._();

  static Future<List<OsmPlaceHit>> search({
    required String query,
    double? biasLatitude,
    double? biasLongitude,
  }) async {
    final q = query.trim();
    if (q.length < 2) return const [];
    final params = <String, String>{
      'q': q,
      'limit': '6',
      'lang': 'en',
    };
    if (biasLatitude != null && biasLongitude != null) {
      params['lat'] = biasLatitude.toString();
      params['lon'] = biasLongitude.toString();
    }
    final uri = Uri.https('photon.komoot.io', '/api/', params);
    final response = await http
        .get(
          uri,
          headers: const {
            'User-Agent': 'ATMOS-TRS Misamis Occidental tourism office',
            'Accept': 'application/json',
          },
        )
        .timeout(const Duration(seconds: 8));
    if (response.statusCode != 200) {
      throw StateError('Place search failed (${response.statusCode}).');
    }
    final decoded = jsonDecode(response.body);
    if (decoded is! Map) return const [];
    final features = decoded['features'];
    if (features is! List) return const [];
    final hits = <OsmPlaceHit>[];
    for (final feature in features) {
      if (feature is! Map) continue;
      final geometry = feature['geometry'];
      final properties = feature['properties'];
      if (geometry is! Map || properties is! Map) continue;
      final coords = geometry['coordinates'];
      if (coords is! List || coords.length < 2) continue;
      final lng = (coords[0] as num?)?.toDouble();
      final lat = (coords[1] as num?)?.toDouble();
      if (lat == null || lng == null) continue;
      final country = properties['country']?.toString().toLowerCase() ?? '';
      if (country.isNotEmpty && country != 'philippines') continue;
      final parts = <String>[
        properties['name']?.toString() ?? '',
        properties['street']?.toString() ?? '',
        properties['city']?.toString() ?? properties['county']?.toString() ?? '',
        properties['state']?.toString() ?? '',
      ].where((part) => part.trim().isNotEmpty).toList();
      if (parts.isEmpty) continue;
      hits.add(OsmPlaceHit(label: parts.join(', '), latitude: lat, longitude: lng));
    }
    return hits;
  }
}

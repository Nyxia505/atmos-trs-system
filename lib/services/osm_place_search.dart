import 'dart:convert';

import 'package:http/http.dart' as http;

/// One OpenStreetMap place suggestion. No API key; Photon uses OSM data.
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

/// Photon bbox: minLon,minLat,maxLon,maxLat (Misamis Occidental province).
const String kMisamisOccidentalPhotonBbox = '123.40,8.05,124.05,8.75';

/// Searches places near an LGU / province anchor using the OSM Photon index.
///
/// Uses Komoot Photon (OSM data) — not the public Nominatim autocomplete API.
class OsmPlaceSearch {
  OsmPlaceSearch._();

  static Future<List<OsmPlaceHit>> search({
    required String query,
    double? biasLatitude,
    double? biasLongitude,
    bool preferMisamisOccidental = true,
  }) async {
    final q = query.trim();
    if (q.length < 2) return const [];

    final biasLat = biasLatitude ??
        (preferMisamisOccidental ? kMisamisOccidentalBiasLat : null);
    final biasLng = biasLongitude ??
        (preferMisamisOccidental ? kMisamisOccidentalBiasLng : null);

    final params = <String, String>{
      'q': q,
      'limit': '8',
      'lang': 'en',
    };
    if (biasLat != null && biasLng != null) {
      params['lat'] = biasLat.toString();
      params['lon'] = biasLng.toString();
    }
    if (preferMisamisOccidental) {
      params['bbox'] = kMisamisOccidentalPhotonBbox;
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

      final name = (properties['name']?.toString() ?? '').trim();
      final street = (properties['street']?.toString() ?? '').trim();
      final city = (properties['city']?.toString() ??
              properties['county']?.toString() ??
              '')
          .trim();
      final state = (properties['state']?.toString() ?? '').trim();
      final addressParts =
          [street, city, state].where((p) => p.isNotEmpty).toList();
      final labelParts = [
        if (name.isNotEmpty) name,
        ...addressParts,
      ];
      if (labelParts.isEmpty) continue;

      hits.add(
        OsmPlaceHit(
          label: labelParts.join(', '),
          name: name.isNotEmpty ? name : labelParts.first,
          address: addressParts.join(', '),
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
        return 0;
      });
    }
    return hits;
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

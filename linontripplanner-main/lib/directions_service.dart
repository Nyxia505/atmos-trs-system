import 'dart:convert';

import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:http/http.dart' as http;

import 'config.dart';
import 'directions_google_maps_js_stub.dart'
    if (dart.library.html) 'directions_google_maps_js.dart';

/// Result of requesting a road route: either the polyline or an error message.
class DirectionsResult {
  final List<LatLng>? polyline;
  final String? errorStatus; // e.g. REQUEST_DENIED, OVER_QUERY_LIMIT
  final String? errorMessage; // from Google API error_message
  /// Total road distance / driving time reported by the routing service.
  final double? distanceMeters;
  final double? durationSeconds;
  const DirectionsResult({
    this.polyline,
    this.errorStatus,
    this.errorMessage,
    this.distanceMeters,
    this.durationSeconds,
  });
}

/// Fetches a driving road route.
///
/// Order: **OpenRouteService via Cloudflare Worker** (primary) → public OSRM
/// → Google (JS / Cloud Function / REST) as last-resort fallbacks.
Future<DirectionsResult> getDirectionsRoute(List<LatLng> waypoints) async {
  if (waypoints.length < 2) {
    return const DirectionsResult(
      errorStatus: 'TOO_FEW_POINTS',
      errorMessage: 'Need at least two waypoints for a road route.',
    );
  }

  DirectionsResult last = const DirectionsResult(errorStatus: 'NO_RESPONSE');

  if (kHasOrsDirectionsProxy) {
    last = await _getDirectionsViaOrsProxy(waypoints);
    if (last.polyline != null && last.polyline!.length >= 2) return last;
  }

  final osrm = await _getDirectionsViaOsrm(waypoints);
  if (osrm.polyline != null && osrm.polyline!.length >= 2) return osrm;
  last = osrm;

  final keys = googleMapsApiKeysForDirections;
  if (keys.isEmpty) return last;

  if (kIsWeb) {
    last = await getDirectionsViaGoogleMapsJs(waypoints);
    if (last.polyline != null && last.polyline!.length >= 2) return last;
  }

  for (final key in keys) {
    if (!kIsWeb) {
      last = await _getGoogleRoadRoute(waypoints, key);
      if (last.polyline != null && last.polyline!.length >= 2) return last;
    }

    if (kIsWeb && directionsUseDeployedCloudFunction) {
      final cf = await _getDirectionsViaCloudFunction(waypoints, key);
      if (cf.polyline != null && cf.polyline!.length >= 2) return cf;
      last = cf;
    }

    if (kIsWeb) {
      last = await _getGoogleRoadRoute(waypoints, key);
      if (last.polyline != null && last.polyline!.length >= 2) return last;
    }
  }
  return last;
}

void _logDirections({
  required String provider,
  required int? httpStatus,
  required String? error,
  required int pointCount,
}) {
  // ignore: avoid_print
  print(
    '[directions] provider=$provider httpStatus=${httpStatus ?? '-'} '
    'error=${error ?? '-'} points=$pointCount',
  );
}

/// Primary: Cloudflare Worker → OpenRouteService GeoJSON LineString.
/// Two attempts with delay. API key never leaves the Worker.
Future<DirectionsResult> _getDirectionsViaOrsProxy(
  List<LatLng> waypoints,
) async {
  DirectionsResult last = const DirectionsResult(
    errorStatus: 'ORS_NO_RESPONSE',
    errorMessage: 'OpenRouteService proxy did not respond.',
  );
  for (var attempt = 0; attempt < 2; attempt++) {
    last = await _getDirectionsViaOrsProxyOnce(waypoints, attempt: attempt);
    if (last.polyline != null && last.polyline!.length >= 2) return last;
    if (attempt == 0) {
      await Future<void>.delayed(const Duration(milliseconds: 500));
    }
  }
  return last;
}

Future<DirectionsResult> _getDirectionsViaOrsProxyOnce(
  List<LatLng> waypoints, {
  required int attempt,
}) async {
  final url = kOrsDirectionsProxyUrl.trim();
  if (url.isEmpty) {
    return const DirectionsResult(
      errorStatus: 'ORS_NOT_CONFIGURED',
      errorMessage: 'ORS_DIRECTIONS_PROXY_URL is empty.',
    );
  }

  // Deduplicate consecutive equal points (ORS rejects zero-length segments).
  final coords = <List<double>>[];
  for (final p in waypoints) {
    final pair = <double>[p.longitude, p.latitude];
    if (coords.isEmpty ||
        (coords.last[0] - pair[0]).abs() > 1e-7 ||
        (coords.last[1] - pair[1]).abs() > 1e-7) {
      coords.add(pair);
    }
  }
  if (coords.length < 2) {
    _logDirections(
      provider: 'openrouteservice',
      httpStatus: null,
      error: 'TOO_FEW_POINTS',
      pointCount: 0,
    );
    return const DirectionsResult(
      errorStatus: 'TOO_FEW_POINTS',
      errorMessage: 'Need at least two distinct waypoints.',
    );
  }

  try {
    final response = await http
        .post(
          Uri.parse(url),
          headers: const {
            'Content-Type': 'application/json',
            'Accept': 'application/json',
          },
          body: jsonEncode({'coordinates': coords}),
        )
        .timeout(const Duration(seconds: 25));

    final status = response.statusCode;
    Map<String, dynamic>? map;
    try {
      map = jsonDecode(response.body) as Map<String, dynamic>?;
    } catch (_) {
      map = null;
    }

    if (map == null) {
      _logDirections(
        provider: 'openrouteservice',
        httpStatus: status,
        error: 'NO_RESPONSE',
        pointCount: 0,
      );
      return DirectionsResult(
        errorStatus: 'ORS_NO_RESPONSE',
        errorMessage: 'HTTP $status with empty/invalid JSON (attempt ${attempt + 1})',
      );
    }

    final err = (map['error'] ?? '').toString().trim();
    if (err.isNotEmpty) {
      final msg = (map['errorMessage'] ?? map['message'] ?? err).toString();
      _logDirections(
        provider: 'openrouteservice',
        httpStatus: status,
        error: err,
        pointCount: 0,
      );
      return DirectionsResult(errorStatus: err, errorMessage: msg);
    }

    final pointsList = map['points'] as List<dynamic>?;
    final polyline = <LatLng>[];
    if (pointsList != null) {
      for (final e in pointsList) {
        if (e is! Map) continue;
        final lat = (e['lat'] as num?)?.toDouble();
        final lng = (e['lng'] as num?)?.toDouble();
        if (lat == null || lng == null) continue;
        if (lat.abs() > 90 || lng.abs() > 180) continue;
        polyline.add(LatLng(lat, lng));
      }
    }

    if (polyline.length < 2) {
      _logDirections(
        provider: 'openrouteservice',
        httpStatus: status,
        error: 'NO_POLYLINE',
        pointCount: polyline.length,
      );
      return DirectionsResult(
        errorStatus: 'NO_POLYLINE',
        errorMessage:
            'ORS returned ${polyline.length} point(s); need at least 2.',
      );
    }

    _logDirections(
      provider: 'openrouteservice',
      httpStatus: status,
      error: null,
      pointCount: polyline.length,
    );
    return DirectionsResult(
      polyline: polyline,
      distanceMeters: (map['distanceMeters'] as num?)?.toDouble(),
      durationSeconds: (map['durationSeconds'] as num?)?.toDouble(),
    );
  } catch (e) {
    _logDirections(
      provider: 'openrouteservice',
      httpStatus: null,
      error: e.toString(),
      pointCount: 0,
    );
    return DirectionsResult(
      errorStatus: 'ORS_ERROR',
      errorMessage: e.toString(),
    );
  }
}

/// Public OSRM demo server; allows browser CORS and needs no API key.
/// Retries once — the demo host is flaky on mobile networks.
Future<DirectionsResult> _getDirectionsViaOsrm(List<LatLng> waypoints) async {
  DirectionsResult last = const DirectionsResult(errorStatus: 'NO_RESPONSE');
  for (var attempt = 0; attempt < 2; attempt++) {
    last = await _getDirectionsViaOsrmOnce(waypoints);
    if (last.polyline != null && last.polyline!.length >= 2) return last;
    if (attempt == 0) {
      await Future<void>.delayed(const Duration(milliseconds: 400));
    }
  }
  return last;
}

Future<DirectionsResult> _getDirectionsViaOsrmOnce(
  List<LatLng> waypoints,
) async {
  final coords = waypoints
      .map((p) => '${p.longitude},${p.latitude}')
      .join(';');
  final uri = Uri.parse(
    'https://router.project-osrm.org/route/v1/driving/$coords'
    '?overview=full&geometries=polyline',
  );
  try {
    final response = await http.get(uri).timeout(const Duration(seconds: 20));
    final map = jsonDecode(response.body) as Map<String, dynamic>?;
    if (map == null) return const DirectionsResult(errorStatus: 'NO_RESPONSE');
    if (map['code'] != 'Ok') {
      return DirectionsResult(
        errorStatus: map['code'] as String? ?? 'OSRM_ERROR',
        errorMessage: map['message'] as String?,
      );
    }
    final routes = map['routes'] as List<dynamic>?;
    final route = routes == null || routes.isEmpty
        ? null
        : routes.first as Map<String, dynamic>;
    final encoded = route?['geometry'] as String?;
    if (encoded == null || encoded.isEmpty) {
      return const DirectionsResult(errorStatus: 'NO_POLYLINE');
    }
    final points = decodePolyline(encoded);
    if (points.length < 2) {
      _logDirections(
        provider: 'osrm',
        httpStatus: response.statusCode,
        error: 'NO_POLYLINE',
        pointCount: points.length,
      );
      return const DirectionsResult(errorStatus: 'NO_POLYLINE');
    }
    _logDirections(
      provider: 'osrm',
      httpStatus: response.statusCode,
      error: null,
      pointCount: points.length,
    );
    return DirectionsResult(
      polyline: points,
      distanceMeters: (route?['distance'] as num?)?.toDouble(),
      durationSeconds: (route?['duration'] as num?)?.toDouble(),
    );
  } catch (e) {
    _logDirections(
      provider: 'osrm',
      httpStatus: null,
      error: e.toString(),
      pointCount: 0,
    );
    return DirectionsResult(errorStatus: 'OSRM_ERROR', errorMessage: e.toString());
  }
}

/// One multi-stop request, then each leg — reliable for many markers in Mindanao.
Future<DirectionsResult> _getGoogleRoadRoute(
  List<LatLng> waypoints,
  String apiKey,
) async {
  final allAtOnce = await _getDirectionsViaGoogleApi(waypoints, apiKey);
  if (allAtOnce.polyline != null) return allAtOnce;

  return _getDirectionsLegByLeg(waypoints, apiKey);
}

Future<DirectionsResult> _getDirectionsLegByLeg(
  List<LatLng> waypoints,
  String apiKey,
) async {
  final merged = <LatLng>[];
  double? meters = 0;
  double? seconds = 0;

  for (var i = 0; i < waypoints.length - 1; i++) {
    final leg = await _getDirectionsViaGoogleApi(
      [waypoints[i], waypoints[i + 1]],
      apiKey,
    );
    final segment = leg.polyline;
    if (segment == null || segment.length < 2) {
      return DirectionsResult(
        errorStatus: leg.errorStatus ?? 'LEG_FAILED',
        errorMessage: leg.errorMessage,
      );
    }
    if (merged.isEmpty) {
      merged.addAll(segment);
    } else {
      merged.addAll(segment.skip(1));
    }
    meters = leg.distanceMeters == null || meters == null
        ? null
        : meters + leg.distanceMeters!;
    seconds = leg.durationSeconds == null || seconds == null
        ? null
        : seconds + leg.durationSeconds!;
  }

  return DirectionsResult(
    polyline: merged,
    distanceMeters: meters,
    durationSeconds: seconds,
  );
}

/// Web: call HTTP Cloud Function with CORS (works from localhost and production).
Future<DirectionsResult> _getDirectionsViaCloudFunction(
  List<LatLng> waypoints,
  String apiKey,
) async {
  final origin = waypoints.first;
  final destination = waypoints.last;
  final middle = waypoints.length > 2
      ? waypoints.sublist(1, waypoints.length - 1)
      : <LatLng>[];
  final waypointsParam =
      middle.take(25).map((p) => '${p.latitude},${p.longitude}').join('|');

  final projectId = Firebase.app().options.projectId;
  final url =
      'https://us-central1-$projectId.cloudfunctions.net/getDirectionsHttp';

  try {
    final response = await http.post(
      Uri.parse(url),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'origin': '${origin.latitude},${origin.longitude}',
        'destination': '${destination.latitude},${destination.longitude}',
        'waypoints': waypointsParam,
        'apiKey': apiKey,
      }),
    );
    final map = jsonDecode(response.body) as Map<String, dynamic>?;
    if (map == null) return const DirectionsResult(errorStatus: 'NO_RESPONSE');
    if (map['error'] != null) {
      return DirectionsResult(
        errorStatus: map['error'] as String?,
        errorMessage: map['errorMessage'] as String?,
      );
    }
    final pointsList = map['points'] as List<dynamic>?;
    if (pointsList != null && pointsList.isNotEmpty) {
      final polyline = pointsList
          .map((e) => (e as Map<String, dynamic>))
          .map(
            (p) => LatLng(
              (p['lat'] as num).toDouble(),
              (p['lng'] as num).toDouble(),
            ),
          )
          .toList();
      return DirectionsResult(polyline: polyline);
    }
    final encoded = map['encodedPolyline'] as String?;
    if (encoded == null || encoded.isEmpty) {
      return const DirectionsResult(errorStatus: 'NO_POLYLINE');
    }
    return DirectionsResult(polyline: decodePolyline(encoded));
  } catch (e) {
    return DirectionsResult(errorStatus: 'ERROR', errorMessage: e.toString());
  }
}

/// Android/iOS: direct Directions API (no CORS on native).
Future<DirectionsResult> _getDirectionsViaGoogleApi(
  List<LatLng> waypoints,
  String apiKey,
) async {
  final origin = waypoints.first;
  final destination = waypoints.last;
  final middle = waypoints.length > 2
      ? waypoints.sublist(1, waypoints.length - 1)
      : <LatLng>[];
  final waypointsParam =
      middle.take(25).map((p) => '${p.latitude},${p.longitude}').join('|');

  final query = <String, String>{
    'origin': '${origin.latitude},${origin.longitude}',
    'destination': '${destination.latitude},${destination.longitude}',
    'mode': 'driving',
    'key': apiKey,
  };
  if (waypointsParam.isNotEmpty) {
    query['waypoints'] = waypointsParam;
  }

  final uri = Uri.https(
    'maps.googleapis.com',
    '/maps/api/directions/json',
    query,
  );

  try {
    final response = await http.get(uri);
    final map = jsonDecode(response.body) as Map<String, dynamic>?;
    if (map == null) return const DirectionsResult(errorStatus: 'NO_RESPONSE');

    final status = map['status'] as String?;
    if (status != 'OK') {
      return DirectionsResult(
        errorStatus: status,
        errorMessage: map['error_message'] as String?,
      );
    }

    final routes = map['routes'] as List<dynamic>?;
    if (routes == null || routes.isEmpty) {
      return const DirectionsResult(errorStatus: 'ZERO_RESULTS');
    }

    final route = routes.first as Map<String, dynamic>;
    double meters = 0;
    double seconds = 0;
    for (final leg in (route['legs'] as List<dynamic>? ?? const [])) {
      final l = leg as Map<String, dynamic>;
      meters += ((l['distance'] as Map?)?['value'] as num? ?? 0).toDouble();
      seconds += ((l['duration'] as Map?)?['value'] as num? ?? 0).toDouble();
    }
    final detailed = _polylineFromDirectionsRoute(route);
    if (detailed != null && detailed.length >= 2) {
      return DirectionsResult(
        polyline: detailed,
        distanceMeters: meters > 0 ? meters : null,
        durationSeconds: seconds > 0 ? seconds : null,
      );
    }
    final overview = route['overview_polyline'] as Map<String, dynamic>?;
    final encoded = overview?['points'] as String?;
    if (encoded == null || encoded.isEmpty) {
      return const DirectionsResult(errorStatus: 'NO_POLYLINE');
    }
    return DirectionsResult(
      polyline: decodePolyline(encoded),
      distanceMeters: meters > 0 ? meters : null,
      durationSeconds: seconds > 0 ? seconds : null,
    );
  } catch (e) {
    return DirectionsResult(errorStatus: 'ERROR', errorMessage: e.toString());
  }
}

/// Step polylines along roads (denser than overview_polyline alone).
List<LatLng>? _polylineFromDirectionsRoute(Map<String, dynamic> route) {
  final legs = route['legs'] as List<dynamic>?;
  if (legs == null || legs.isEmpty) return null;

  final points = <LatLng>[];
  for (final leg in legs) {
    final steps = (leg as Map<String, dynamic>)['steps'] as List<dynamic>?;
    if (steps == null) continue;
    for (final step in steps) {
      final enc =
          (step as Map<String, dynamic>)['polyline']?['points'] as String?;
      if (enc == null || enc.isEmpty) continue;
      final decoded = decodePolyline(enc);
      if (points.isEmpty) {
        points.addAll(decoded);
      } else if (decoded.isNotEmpty) {
        final first = decoded.first;
        if (points.last.latitude != first.latitude ||
            points.last.longitude != first.longitude) {
          points.add(first);
        }
        if (decoded.length > 1) {
          points.addAll(decoded.sublist(1));
        }
      }
    }
  }
  return points.length >= 2 ? points : null;
}

/// Decode Google's encoded polyline into list of LatLng.
List<LatLng> decodePolyline(String encoded) {
  final points = <LatLng>[];
  int index = 0;
  int lat = 0;
  int lng = 0;

  while (index < encoded.length) {
    int b;
    int shift = 0;
    int result = 0;
    do {
      b = encoded.codeUnitAt(index++) - 63;
      result |= (b & 0x1f) << shift;
      shift += 5;
    } while (b >= 0x20);
    // Not `~(result >> 1)`: on web `~` yields an unsigned 32-bit value.
    final dlat = (result & 1) != 0 ? -(result >> 1) - 1 : (result >> 1);
    lat += dlat;

    shift = 0;
    result = 0;
    do {
      b = encoded.codeUnitAt(index++) - 63;
      result |= (b & 0x1f) << shift;
      shift += 5;
    } while (b >= 0x20);
    final dlng = (result & 1) != 0 ? -(result >> 1) - 1 : (result >> 1);
    lng += dlng;

    points.add(LatLng(lat / 1e5, lng / 1e5));
  }
  return points;
}

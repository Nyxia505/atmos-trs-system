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

/// Fetches a driving road route: OSRM (OpenStreetMap, no key) first, then
/// Google Directions as a fallback.
Future<DirectionsResult> getDirectionsRoute(List<LatLng> waypoints) async {
  if (waypoints.length < 2) return const DirectionsResult();

  final osrm = await _getDirectionsViaOsrm(waypoints);
  if (osrm.polyline != null) return osrm;

  final keys = googleMapsApiKeysForDirections;
  if (keys.isEmpty) return osrm;

  DirectionsResult last = osrm;

  if (kIsWeb) {
    last = await getDirectionsViaGoogleMapsJs(waypoints);
    if (last.polyline != null) return last;
  }

  for (final key in keys) {
    if (!kIsWeb) {
      last = await _getGoogleRoadRoute(waypoints, key);
      if (last.polyline != null) return last;
    }

    if (kIsWeb && directionsUseDeployedCloudFunction) {
      final cf = await _getDirectionsViaCloudFunction(waypoints, key);
      if (cf.polyline != null) return cf;
      last = cf;
    }

    if (kIsWeb) {
      last = await _getGoogleRoadRoute(waypoints, key);
      if (last.polyline != null) return last;
    }
  }
  return last;
}

/// Public OSRM demo server; allows browser CORS and needs no API key.
Future<DirectionsResult> _getDirectionsViaOsrm(List<LatLng> waypoints) async {
  final coords = waypoints
      .map((p) => '${p.longitude},${p.latitude}')
      .join(';');
  final uri = Uri.parse(
    'https://router.project-osrm.org/route/v1/driving/$coords'
    '?overview=full&geometries=polyline',
  );
  try {
    final response = await http.get(uri).timeout(const Duration(seconds: 15));
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
      return const DirectionsResult(errorStatus: 'NO_POLYLINE');
    }
    return DirectionsResult(
      polyline: points,
      distanceMeters: (route?['distance'] as num?)?.toDouble(),
      durationSeconds: (route?['duration'] as num?)?.toDouble(),
    );
  } catch (e) {
    return DirectionsResult(errorStatus: 'ERROR', errorMessage: e.toString());
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

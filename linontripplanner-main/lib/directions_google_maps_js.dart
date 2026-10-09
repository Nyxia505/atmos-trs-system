import 'dart:convert';
import 'dart:js_interop';

import 'package:google_maps_flutter/google_maps_flutter.dart';

import 'directions_service.dart';

@JS('tripPlanGetDirectionsRoute')
external JSPromise<JSString> _tripPlanGetDirectionsRoute(JSString waypointsJson);

Future<DirectionsResult> getDirectionsViaGoogleMapsJs(
  List<LatLng> waypoints,
) async {
  if (waypoints.length < 2) return const DirectionsResult();

  final payload = waypoints
      .map((p) => {'lat': p.latitude, 'lng': p.longitude})
      .toList();

  try {
    final jsonStr =
        (await _tripPlanGetDirectionsRoute(jsonEncode(payload).toJS).toDart)
            .toDart;
    final map = jsonDecode(jsonStr) as Map<String, dynamic>;
    final status = map['errorStatus'] as String?;
    if (status != null) {
      return DirectionsResult(
        errorStatus: status,
        errorMessage: map['errorMessage'] as String?,
      );
    }
    final pointsList = map['points'] as List<dynamic>?;
    if (pointsList == null || pointsList.isEmpty) {
      return const DirectionsResult(errorStatus: 'NO_POLYLINE');
    }
    final polyline = pointsList
        .map((e) => (e as Map<String, dynamic>))
        .map(
          (p) => LatLng(
            (p['lat'] as num).toDouble(),
            (p['lng'] as num).toDouble(),
          ),
        )
        .toList();
    if (polyline.length < 2) {
      return const DirectionsResult(errorStatus: 'NO_POLYLINE');
    }
    return DirectionsResult(polyline: polyline);
  } catch (e) {
    return DirectionsResult(errorStatus: 'ERROR', errorMessage: e.toString());
  }
}

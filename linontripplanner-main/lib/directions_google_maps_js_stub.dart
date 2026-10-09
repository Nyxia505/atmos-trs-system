import 'package:google_maps_flutter/google_maps_flutter.dart';

import 'directions_service.dart';

Future<DirectionsResult> getDirectionsViaGoogleMapsJs(
  List<LatLng> waypoints,
) async {
  return const DirectionsResult(errorStatus: 'NOT_WEB');
}

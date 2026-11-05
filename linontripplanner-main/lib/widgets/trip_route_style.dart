import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

/// Google Maps–style trip route line (solid blue, rounded joins).
abstract final class TripRouteStyle {
  static const Color routeBlue = Color(0xFF4285F4);
  static const Color routeBlueDark = Color(0xFF1A73E8);

  static int routeWidth({required bool compact, required bool roadLine}) {
    if (roadLine) return compact ? 5 : 7;
    return compact ? 4 : 6;
  }

  static int routeCasingWidth({required bool compact}) =>
      compact ? 7 : 9;

  /// Road-following route (Directions API) — thick solid blue like Google Maps.
  static Set<Polyline> googleRoadPolylines(
    List<LatLng> points, {
    required bool compact,
  }) {
    if (points.length < 2) return const {};
    return {
      Polyline(
        polylineId: const PolylineId('trip_route_roads_casing'),
        points: points,
        color: routeBlueDark,
        width: routeCasingWidth(compact: compact),
        geodesic: false,
        startCap: Cap.roundCap,
        endCap: Cap.roundCap,
        jointType: JointType.round,
        zIndex: 0,
      ),
      Polyline(
        polylineId: const PolylineId('trip_route_roads'),
        points: points,
        color: routeBlue,
        width: routeWidth(compact: compact, roadLine: true),
        geodesic: false,
        startCap: Cap.roundCap,
        endCap: Cap.roundCap,
        jointType: JointType.round,
        zIndex: 1,
      ),
    };
  }

  /// Straight-line fallback while directions load or if API fails.
  static Set<Polyline> googleDirectPolylines(
    List<LatLng> points, {
    required bool compact,
  }) {
    if (points.length < 2) return const {};
    return {
      Polyline(
        polylineId: const PolylineId('trip_route_direct'),
        points: points,
        color: routeBlue,
        width: routeWidth(compact: compact, roadLine: false),
        geodesic: true,
        startCap: Cap.roundCap,
        endCap: Cap.roundCap,
        jointType: JointType.round,
        zIndex: 1,
      ),
    };
  }
}

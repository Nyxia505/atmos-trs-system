import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart' show LatLng;

import '../data.dart';
import '../directions_service.dart';
import '../municipal_road_distances.dart'
    show
        RoadRouteDirection,
        municipalitiesOnRoadBetween,
        roadTableIndexFor;
import '../municipality_bus_terminals.dart' show haversineDistanceKm;
import '../municipality_coordinates.dart' show getMunicipalityCoordinates;
import '../road_route_service.dart';
import '../tourist_plan/tourist_travel_estimates.dart' show formatHoursMinutes;
import 'trip_route_osm_map_view.dart';

/// Snapshot of the in-map road route (distance, time, errors).
class TripRouteUpdate {
  final bool loading;
  final bool failed;
  final double? distanceKm;
  final int? durationMinutes;
  final String? errorMessage;

  const TripRouteUpdate({
    required this.loading,
    required this.failed,
    this.distanceKm,
    this.durationMinutes,
    this.errorMessage,
  });
}

typedef TripRouteUpdateCallback = void Function(TripRouteUpdate update);

/// Trip route map (flutter_map) with start/end pins, spots, and road polyline.
class TripRouteMapView extends StatefulWidget {
  final Municipality start;
  final Municipality end;
  final List<TouristSpot> spots;
  final double budget;
  final Set<String> exactBudgetSpotNames;
  /// When true, map is non-interactive (for embedding in scroll views).
  final bool compact;

  /// Which way around the provincial loop to draw (null = shortest road).
  final RoadRouteDirection? direction;

  /// Visit order for the line currently on screen. When set, the polyline
  /// follows these stops only (one day, or the whole itinerary).
  final List<RoadStop>? visitStops;

  final LatLng? startPinPoint;
  final String startPinTitle;
  final String startPinDetail;
  final LatLng? endPinPoint;
  final String endPinTitle;
  final String endPinDetail;
  final List<TripBusMarker> busMarkers;
  final bool showTouristSpots;
  final bool showBusStops;
  final bool showBusTerminals;

  /// Called whenever route loading, geometry, or estimates change.
  final TripRouteUpdateCallback? onRouteUpdate;

  /// Zoom, pan, and pinch. Defaults to on when [compact] is false.
  final bool? interactive;

  /// `Walking`, `Motorcycle`, or `Car`. Walking draws a dotted route.
  final String travelMode;

  /// Origin circle + red destination pin, matching Google Maps directions.
  final bool googleStyleEndpoints;

  const TripRouteMapView({
    super.key,
    required this.start,
    required this.end,
    required this.spots,
    this.budget = 0,
    this.exactBudgetSpotNames = const <String>{},
    this.compact = false,
    this.direction,
    this.visitStops,
    this.startPinPoint,
    this.startPinTitle = 'Starting Point',
    this.startPinDetail = '',
    this.endPinPoint,
    this.endPinTitle = 'End Point',
    this.endPinDetail = '',
    this.busMarkers = const [],
    this.showTouristSpots = true,
    this.showBusStops = true,
    this.showBusTerminals = true,
    this.onRouteUpdate,
    this.interactive,
    this.travelMode = 'Motorcycle',
    this.googleStyleEndpoints = false,
  });

  @override
  State<TripRouteMapView> createState() => TripRouteMapViewState();
}

class TripRouteMapViewState extends State<TripRouteMapView> {
  final GlobalKey<TripRouteOsmMapViewState> _osmMapKey =
      GlobalKey<TripRouteOsmMapViewState>();
  List<LatLng>? _roadRoutePoints;
  bool _loadingDirections = false;
  bool _directionsFailed = false;
  String? _directionsErrorStatus;
  String? _directionsErrorMessage;
  double? _routeKm;
  int? _routeMinutes;
  int _fetchGeneration = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(_fetchDirections());
    });
  }

  @override
  void didUpdateWidget(TripRouteMapView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.direction != widget.direction ||
        oldWidget.start.name != widget.start.name ||
        oldWidget.end.name != widget.end.name ||
        _stopKey(oldWidget.visitStops) != _stopKey(widget.visitStops) ||
        !_sameSpotNames(oldWidget.spots, widget.spots) ||
        !_samePoint(oldWidget.startPinPoint, widget.startPinPoint) ||
        !_samePoint(oldWidget.endPinPoint, widget.endPinPoint)) {
      _fetchDirections();
    }
  }

  bool _samePoint(LatLng? a, LatLng? b) {
    if (identical(a, b)) return true;
    if (a == null || b == null) return false;
    return (a.latitude - b.latitude).abs() < 1e-5 &&
        (a.longitude - b.longitude).abs() < 1e-5;
  }

  bool get _interactive => widget.interactive ?? !widget.compact;

  /// Re-runs the existing road router (OSRM / Directions).
  void retryDirections() => _fetchDirections();

  void zoomBy(double delta) => _osmMapKey.currentState?.zoomBy(delta);

  void _emitRouteUpdate() {
    final callback = widget.onRouteUpdate;
    if (callback == null) return;
    final update = TripRouteUpdate(
      loading: _loadingDirections,
      failed: _directionsFailed,
      distanceKm: _routeKm,
      durationMinutes: _routeMinutes,
      errorMessage: _directionsErrorMessage ?? _directionsErrorStatus,
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      callback(update);
    });
  }

  String _stopKey(List<RoadStop>? stops) {
    if (stops == null) return '';
    return stops
        .map(
          (s) =>
              '${s.place}:${s.point.latitude.toStringAsFixed(5)},${s.point.longitude.toStringAsFixed(5)}',
        )
        .join('|');
  }

  bool _sameSpotNames(List<TouristSpot> a, List<TouristSpot> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i].name != b[i].name) return false;
    }
    return true;
  }

  Future<void> _fetchDirections() async {
    final generation = ++_fetchGeneration;
    final direction = widget.direction;
    final stops = _routeStops;
    if (widget.visitStops == null && direction != null) {
      final towns = municipalitiesOnRoadBetween(
        widget.start,
        widget.end,
        direction: direction,
      );
      if (towns == null || towns.length < 2) {
        if (!mounted || generation != _fetchGeneration) return;
        setState(() {
          _loadingDirections = false;
          _roadRoutePoints = null;
          _routeKm = null;
          _routeMinutes = null;
          _directionsFailed = true;
          _directionsErrorStatus = 'NO_ROUTE';
          _directionsErrorMessage =
              'No ${direction.name} route from ${widget.start.name} to ${widget.end.name}.';
        });
        _emitRouteUpdate();
        return;
      }
    }
    if (stops.length < 2) {
      if (!mounted || generation != _fetchGeneration) return;
      setState(() {
        _loadingDirections = false;
        _directionsFailed = false;
        _directionsErrorStatus = null;
        _directionsErrorMessage = null;
      });
      _emitRouteUpdate();
      return;
    }
    final previewKm = _estimatePreviewKm();
    setState(() {
      // Never block the map. Preview pins show immediately; OSRM swaps in.
      _loadingDirections = false;
      _directionsFailed = false;
      _directionsErrorStatus = null;
      _directionsErrorMessage = null;
      _routeKm ??= previewKm;
      _routeMinutes ??= previewKm == null
          ? null
          : (previewKm / 40 * 60).round().clamp(1, 24 * 60);
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) fitRouteBounds();
    });
    _emitRouteUpdate();
    DirectionsResult result;
    try {
      // Tourist Get Directions (explicit start/end pins): two-point OSRM only.
      // Trip Planner still routes through every town on the provincial loop.
      final pinToPin = widget.visitStops != null && stops.length >= 2;
      result = pinToPin
          ? await getDirectionsRoute(
              [stops.first.point, stops.last.point],
              osrmOnly: true,
              osrmTimeout: const Duration(seconds: 8),
            ).timeout(
              const Duration(seconds: 8),
              onTimeout: () => const DirectionsResult(
                errorStatus: 'TIMEOUT',
                errorMessage: 'Unable to load directions. Please try again.',
              ),
            )
          : await getOrderedRoadRoute(
              stops,
              direction: widget.direction,
            ).timeout(
              const Duration(seconds: 12),
              onTimeout: () => const DirectionsResult(
                errorStatus: 'TIMEOUT',
                errorMessage: 'Unable to load directions. Please try again.',
              ),
            );
    } catch (_) {
      result = const DirectionsResult(
        errorStatus: 'ERROR',
        errorMessage: 'Unable to load directions. Please try again.',
      );
    }
    if (!mounted || generation != _fetchGeneration) return;
    final hasPolyline = result.polyline != null && result.polyline!.length >= 2;
    setState(() {
      _loadingDirections = false;
      if (hasPolyline) {
        _roadRoutePoints = result.polyline;
        _routeKm = result.distanceMeters == null
            ? _routeKm
            : result.distanceMeters! / 1000;
        _routeMinutes = result.durationSeconds == null
            ? _routeMinutes
            : (result.durationSeconds! / 60).round();
        _directionsFailed = false;
        _directionsErrorStatus = null;
        _directionsErrorMessage = null;
      } else if (_displayRouteLine.length < 2) {
        _directionsErrorStatus = result.errorStatus;
        _directionsErrorMessage = result.errorMessage;
        _directionsFailed = true;
      }
    });
    _emitRouteUpdate();
    if (result.polyline != null && result.polyline!.length >= 2) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) fitRouteBounds();
      });
    }
  }

  LatLng? get _startPosition => getMunicipalityCoordinates(widget.start);

  LatLng? get _endPosition => getMunicipalityCoordinates(widget.end);

  List<LatLng> get _spotPoints {
    final points = <LatLng>[];
    for (final s in widget.spots) {
      if (s.latitude != null && s.longitude != null) {
        points.add(LatLng(s.latitude!, s.longitude!));
      }
    }
    return points;
  }

  /// Start → spots → end, each tagged with its municipality so the routing
  /// request passes through every town between consecutive stops.
  ///
  /// When a coastal or highland route is selected, stops come only from that
  /// path: town centers (road network), then tourist spots on the path.
  /// Bus stops/terminals are map markers only — never polyline waypoints.
  List<RoadStop> get _routeStops {
    final visit = widget.visitStops;
    if (visit != null) return _orderedStops(visit);
    final direction = widget.direction;
    if (direction != null) return _stopsOnSelectedRoute(direction);
    return _orderedStops(_allStops);
  }

  List<RoadStop> _stopsOnSelectedRoute(RoadRouteDirection direction) {
    final towns = municipalitiesOnRoadBetween(
      widget.start,
      widget.end,
      direction: direction,
    );
    if (towns == null || towns.length < 2) return const [];
    final onPath = <int>{
      for (final m in towns)
        if (roadTableIndexFor(m.name) != null) roadTableIndexFor(m.name)!,
    };
    final spotsByTown = <int, List<LatLng>>{};
    for (final s in widget.spots) {
      final idx = roadTableIndexFor(s.location);
      if (idx == null || !onPath.contains(idx)) continue;
      if (s.latitude == null || s.longitude == null) continue;
      (spotsByTown[idx] ??= []).add(LatLng(s.latitude!, s.longitude!));
    }
    final raw = <RoadStop>[];
    for (final town in towns) {
      final idx = roadTableIndexFor(town.name);
      final center = getMunicipalityCoordinates(town);
      if (center != null) raw.add((place: town.name, point: center));
      if (idx != null) {
        for (final point in spotsByTown[idx] ?? const <LatLng>[]) {
          raw.add((place: town.name, point: point));
        }
      }
    }
    return _orderedStops(raw);
  }

  List<RoadStop> get _allStops {
    final raw = <RoadStop>[];
    final start = _startPosition;
    final end = _endPosition;
    if (start != null) raw.add((place: widget.start.name, point: start));
    for (final s in widget.spots) {
      if (s.latitude != null && s.longitude != null) {
        raw.add((place: s.location, point: LatLng(s.latitude!, s.longitude!)));
      }
    }
    if (end != null) raw.add((place: widget.end.name, point: end));
    return raw;
  }

  List<RoadStop> _orderedStops(List<RoadStop> raw) {
    final deduped = <RoadStop>[];
    for (final stop in raw) {
      if (deduped.isEmpty || !_samePosition(stop.point, deduped.last.point)) {
        deduped.add(stop);
      }
    }
    return deduped;
  }

  List<LatLng> get _fullRoutePoints {
    final start = _startPosition;
    final end = _endPosition;
    final spots = _spotPoints;
    if (start != null && end != null) {
      if (spots.isEmpty) return [start, end];
      return [start, ...spots, end];
    }
    if (start != null && spots.isNotEmpty) return [start, ...spots];
    if (end != null && spots.isNotEmpty) return [...spots, end];
    return spots;
  }

  bool _samePosition(LatLng a, LatLng b) {
    return (a.latitude - b.latitude).abs() < 1e-5 &&
        (a.longitude - b.longitude).abs() < 1e-5;
  }

  void fitRouteBounds() {
    _osmMapKey.currentState?.fitRouteBounds();
  }

  List<LatLng> _previewRouteLine() {
    final origin = widget.startPinPoint ?? _startPosition;
    final dest = widget.endPinPoint ?? _endPosition;
    if (origin != null && dest != null) {
      if (_samePosition(origin, dest)) return [origin];
      return [origin, dest];
    }
    if (origin != null) return [origin];
    if (dest != null) return [dest];
    return const [];
  }

  List<LatLng> get _displayRouteLine {
    if (_roadRoutePoints != null && _roadRoutePoints!.length >= 2) {
      return _roadRoutePoints!;
    }
    return _previewRouteLine();
  }

  double? _estimatePreviewKm() {
    final line = _previewRouteLine();
    if (line.length < 2) return null;
    var total = 0.0;
    for (var i = 1; i < line.length; i++) {
      total += haversineDistanceKm(
        line[i - 1].latitude,
        line[i - 1].longitude,
        line[i].latitude,
        line[i].longitude,
      );
    }
    return total > 0 ? total : null;
  }

  Widget _buildMapWidget() {
    final line = _displayRouteLine;
    final map = TripRouteOsmMapView(
      key: _osmMapKey,
      start: widget.start,
      end: widget.end,
      spots: widget.spots,
      budget: widget.budget,
      exactBudgetSpotNames: widget.exactBudgetSpotNames,
      compact: widget.compact,
      interactive: _interactive,
      routeLinePoints: line,
      roadFollowing:
          _roadRoutePoints != null && _roadRoutePoints!.length >= 2,
      startPinPoint: widget.visitStops != null
          ? widget.startPinPoint
          : (widget.startPinPoint ?? _startPosition),
      startPinTitle: widget.startPinTitle,
      startPinDetail: widget.startPinDetail,
      endPinPoint: widget.visitStops != null
          ? widget.endPinPoint
          : (widget.endPinPoint ?? _endPosition),
      endPinTitle: widget.endPinTitle,
      endPinDetail: widget.endPinDetail,
      busMarkers: widget.busMarkers,
      showTouristSpots: widget.showTouristSpots,
      showBusStops: widget.showBusStops,
      showBusTerminals: widget.showBusTerminals,
      dottedRoute: widget.travelMode == 'Walking',
      googleStyleEndpoints: widget.googleStyleEndpoints,
    );
    return _interactive ? map : IgnorePointer(child: map);
  }

  Widget _zoomButton(IconData icon, double delta) {
    return Material(
      color: Colors.white,
      elevation: 2,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        onTap: () => zoomBy(delta),
        borderRadius: BorderRadius.circular(10),
        child: SizedBox(
          width: 36,
          height: 36,
          child: Icon(icon, size: 20, color: const Color(0xFF1E293B)),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final points = _fullRoutePoints;
    final hasRoute = points.length >= 2;
    final hasStartEnd = _startPosition != null && _endPosition != null;

    return Stack(
      fit: StackFit.expand,
      children: [
        _buildMapWidget(),
        if (_interactive)
          Positioned(
            right: 8,
            bottom: widget.compact ? 28 : 16,
            child: Column(
              children: [
                _zoomButton(Icons.add_rounded, 1),
                const SizedBox(height: 6),
                _zoomButton(Icons.remove_rounded, -1),
              ],
            ),
          ),
        if (!widget.compact &&
            !widget.googleStyleEndpoints &&
            _routeKm != null)
          Positioned(
            left: 12,
            top: 12,
            child: Card(
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                child: Text(
                  '${_routeKm!.toStringAsFixed(1)} km by road'
                  '${_routeMinutes != null ? ' - ~${formatHoursMinutes(_routeMinutes!)} driving' : ''}',
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          ),
        if (_directionsFailed &&
            (_roadRoutePoints == null || _roadRoutePoints!.length < 2) &&
            _displayRouteLine.length < 2)
          Positioned(
            left: 16,
            right: 16,
            bottom: 24,
            child: GestureDetector(
              onTap: _fetchDirections,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 14,
                ),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.1),
                      blurRadius: 10,
                      offset: const Offset(0, 3),
                    ),
                  ],
                ),
                child: Text(
                  _directionsErrorMessage != null &&
                          _directionsErrorMessage!.isNotEmpty
                      ? _directionsErrorMessage!
                      : _directionsErrorStatus == 'REQUEST_DENIED'
                      ? 'Enable Directions API on this key in Google Cloud, then tap to retry.'
                      : _directionsErrorStatus == 'NO_GOOGLE_MAPS'
                      ? 'Route service is still loading. Tap to retry.'
                      : _directionsErrorStatus == 'NO_ROUTE'
                      ? 'No valid road route was found. Tap to retry.'
                      : 'Road route: ${_directionsErrorStatus ?? "tap to retry"}',
                  style: const TextStyle(
                    color: AppColors.textGrey,
                    fontSize: 13,
                    height: 1.4,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
            ),
          ),
        if (!hasRoute && !_directionsFailed && !widget.compact)
          Positioned(
            left: 16,
            right: 16,
            bottom: 24,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.1),
                    blurRadius: 10,
                    offset: const Offset(0, 3),
                  ),
                ],
              ),
              child: Text(
                hasStartEnd
                    ? 'Start and end are pinned. Add spots with coordinates to see the route line.'
                    : points.isEmpty
                    ? 'Start and end municipalities are shown when coordinates are available.'
                    : 'Only one point on the map.',
                style: const TextStyle(
                  color: AppColors.textGrey,
                  fontSize: 13,
                  height: 1.4,
                ),
                textAlign: TextAlign.center,
              ),
            ),
          ),
      ],
    );
  }
}

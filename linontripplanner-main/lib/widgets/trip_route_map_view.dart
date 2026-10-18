import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart' show LatLng;

import '../data.dart';
import '../municipal_road_distances.dart'
    show
        RoadRouteDirection,
        municipalitiesOnRoadBetween,
        roadTableIndexFor;
import '../municipality_coordinates.dart' show getMunicipalityCoordinates;
import '../road_route_service.dart';
import '../services/bus_location_store.dart';
import '../tourist_plan/tourist_travel_estimates.dart' show formatHoursMinutes;
import 'trip_route_osm_map_view.dart';

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

  @override
  void initState() {
    super.initState();
    _fetchDirections();
  }

  @override
  void didUpdateWidget(TripRouteMapView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.direction != widget.direction ||
        oldWidget.start.name != widget.start.name ||
        oldWidget.end.name != widget.end.name ||
        _stopKey(oldWidget.visitStops) != _stopKey(widget.visitStops) ||
        !_sameSpotNames(oldWidget.spots, widget.spots)) {
      _fetchDirections();
    }
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
    final direction = widget.direction;
    final stops = _routeStops;
    if (widget.visitStops == null && direction != null) {
      final towns = municipalitiesOnRoadBetween(
        widget.start,
        widget.end,
        direction: direction,
      );
      if (towns == null || towns.length < 2) {
        if (!mounted) return;
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
        return;
      }
    }
    if (stops.length < 2) {
      if (!mounted) return;
      setState(() {
        _loadingDirections = false;
        _roadRoutePoints = null;
        _routeKm = null;
        _routeMinutes = null;
        _directionsFailed = false;
        _directionsErrorStatus = null;
        _directionsErrorMessage = null;
      });
      return;
    }
    setState(() {
      _loadingDirections = true;
      _roadRoutePoints = null;
      _directionsFailed = false;
      _directionsErrorStatus = null;
      _directionsErrorMessage = null;
    });
    final result = await getOrderedRoadRoute(
      stops,
      direction: widget.direction,
    );
    if (!mounted) return;
    setState(() {
      _loadingDirections = false;
      _roadRoutePoints = result.polyline;
      _routeKm = result.distanceMeters == null
          ? null
          : result.distanceMeters! / 1000;
      _routeMinutes = result.durationSeconds == null
          ? null
          : (result.durationSeconds! / 60).round();
      _directionsErrorStatus = result.errorStatus;
      _directionsErrorMessage = result.errorMessage;
      _directionsFailed = result.polyline == null;
    });
    if (result.polyline != null && result.polyline!.length >= 2) {
      Future.delayed(const Duration(milliseconds: 200), () {
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
  /// path: bus terminals in route order, then spots whose municipality is on
  /// the path. Spots on the other route are left off so the line cannot jump
  /// onto it.
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
      final buses = BusLocationStore.instance.alongMunicipalities(
        [town.name],
        direction,
      );
      if (buses.isEmpty) {
        final center = getMunicipalityCoordinates(town);
        if (center != null) raw.add((place: town.name, point: center));
      } else {
        for (final bus in buses) {
          raw.add((
            place: town.name,
            point: LatLng(bus.latitude, bus.longitude),
          ));
        }
      }
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

  Widget _buildMapWidget() {
    // Only the road geometry from the routing service is drawn.
    final line = _roadRoutePoints ?? const <LatLng>[];
    final map = TripRouteOsmMapView(
      key: _osmMapKey,
      start: widget.start,
      end: widget.end,
      spots: widget.spots,
      budget: widget.budget,
      exactBudgetSpotNames: widget.exactBudgetSpotNames,
      compact: widget.compact,
      routeLinePoints: line,
      roadFollowing: line.length >= 2,
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
    );
    return widget.compact ? IgnorePointer(child: map) : map;
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
        if (_loadingDirections)
          Positioned(
            top: widget.compact ? 8 : 16,
            left: 0,
            right: 0,
            child: Center(
              child: Card(
                child: Padding(
                  padding: EdgeInsets.symmetric(
                    horizontal: widget.compact ? 10 : 16,
                    vertical: widget.compact ? 6 : 10,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SizedBox(
                        width: widget.compact ? 16 : 20,
                        height: widget.compact ? 16 : 20,
                        child: const CircularProgressIndicator(strokeWidth: 2),
                      ),
                      const SizedBox(width: 10),
                      Text(
                        widget.compact
                            ? 'Loading route...'
                            : 'Loading route along roads...',
                        style: TextStyle(fontSize: widget.compact ? 11 : 14),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        if (!widget.compact && !_loadingDirections && _routeKm != null)
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
        if (_directionsFailed && _roadRoutePoints == null)
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

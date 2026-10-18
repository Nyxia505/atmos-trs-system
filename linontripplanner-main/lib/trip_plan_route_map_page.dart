import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import 'algorithms/bus_itinerary_route.dart';
import 'algorithms/road_nearest_neighbor.dart';
import 'data.dart';
import 'municipal_road_distances.dart' show RoadRouteDirection;
import 'municipality_coordinates.dart' show getMunicipalityCoordinates;
import 'road_route_service.dart';
import 'trip_route_fare_service.dart';
import 'widgets/trip_route_map_view.dart';
import 'widgets/trip_route_osm_map_view.dart';

/// Full-screen map: nearest-road itinerary with a blue start pin and a red
/// end pin. [spotDays] is the user's per-day selection; visit order inside an
/// unlocked day is calculated here and reported through [onOrderSaved].
class TripPlanRouteMapPage extends StatefulWidget {
  final Municipality start;
  final Municipality end;
  final List<TouristSpot> spots;
  final double budget;
  final Set<String> exactBudgetSpotNames;
  final TripRouteFareBreakdown? routeFareBreakdown;
  final String transportMode;
  final RoadRouteDirection? direction;

  /// Spots already assigned to each day, in the user's day buckets.
  /// When null, [spots] is treated as a single day.
  final List<List<TouristSpot>>? spotDays;

  /// Days whose visit order the user confirmed. Those days are not reordered.
  final Set<int> lockedDayIndexes;

  /// Spot name that must stay last on that day (the user ended the day there).
  final Map<int, String> lockedEndSpotNames;

  /// Called with the road nearest-neighbor order so it can be saved.
  final void Function(List<List<TouristSpot>> orderedDays)? onOrderSaved;

  const TripPlanRouteMapPage({
    super.key,
    required this.start,
    required this.end,
    required this.spots,
    this.budget = 0,
    this.exactBudgetSpotNames = const <String>{},
    this.routeFareBreakdown,
    this.transportMode = 'Car',
    this.direction,
    this.spotDays,
    this.lockedDayIndexes = const {},
    this.lockedEndSpotNames = const {},
    this.onOrderSaved,
  });

  @override
  State<TripPlanRouteMapPage> createState() => _TripPlanRouteMapPageState();
}

class _DisplayedRoute {
  final List<RoadStop> stops;
  final LatLng? startPoint;
  final String startDetail;
  final LatLng? endPoint;
  final String endDetail;
  final List<TouristSpot> spots;
  final List<TripBusMarker> buses;

  const _DisplayedRoute({
    required this.stops,
    required this.startPoint,
    required this.startDetail,
    required this.endPoint,
    required this.endDetail,
    required this.spots,
    required this.buses,
  });
}

class _TripPlanRouteMapPageState extends State<TripPlanRouteMapPage> {
  final _mapKey = GlobalKey<TripRouteMapViewState>();

  /// Null shows the whole itinerary. Otherwise a day index.
  int? _day;
  BusItineraryPlan? _plan;
  String? _orderError;
  bool _ordering = true;

  /// Missing-coordinate notes are not shown. Other route errors still are.
  String? get _visibleOrderError {
    final raw = _orderError;
    if (raw == null || raw.trim().isEmpty) return null;
    final kept = raw
        .split(RegExp(r'(?<=\.)\s+'))
        .where((part) => !part.startsWith('No coordinates are saved'))
        .join(' ')
        .trim();
    return kept.isEmpty ? null : kept;
  }

  @override
  void initState() {
    super.initState();
    _orderDays();
  }

  List<List<TouristSpot>> get _inputDays {
    final given = widget.spotDays;
    if (given != null && given.isNotEmpty) {
      return [for (final day in given) List<TouristSpot>.from(day)];
    }
    if (widget.spots.isEmpty) return const [<TouristSpot>[]];
    return [List<TouristSpot>.from(widget.spots)];
  }

  bool get _usesPublicTransport =>
      shouldShowTransportationFees(widget.transportMode);

  Future<void> _orderDays() async {
    final BusItineraryPlan result;
    if (_usesPublicTransport) {
      result = await buildBusItineraryPlan(
        start: widget.start,
        days: _inputDays,
        lockedDays: widget.lockedDayIndexes,
        lockedEndSpotNames: widget.lockedEndSpotNames,
        direction: widget.direction,
      );
    } else {
      final ordered = await orderDaysByRoadNearestNeighbor(
        start: widget.start,
        days: _inputDays,
        lockedDays: widget.lockedDayIndexes,
        lockedEndSpotNames: widget.lockedEndSpotNames,
        direction: widget.direction,
      );
      result = _drivingPlan(ordered);
    }
    if (!mounted) return;
    setState(() {
      _plan = result;
      _orderError = result.error;
      _ordering = false;
    });
    widget.onOrderSaved?.call([
      for (final day in result.days) day.spots,
    ]);
  }

  /// Car and motorcycle follow the spots by road, with no bus stops.
  BusItineraryPlan _drivingPlan(RoadItineraryOrder ordered) {
    final origin = getMunicipalityCoordinates(widget.start);
    if (origin == null) {
      return BusItineraryPlan(
        days: [
          for (final day in ordered.days)
            BusDayRoute(nodes: const [], spots: day),
        ],
        error: ordered.error ?? 'No coordinates are saved for ${widget.start.name}.',
      );
    }
    final startName = widget.start.shortName.isNotEmpty
        ? widget.start.shortName
        : widget.start.name;
    var cursor = ItineraryRouteNode(
      point: origin,
      place: widget.start.name,
      label: startName,
      detail: startName,
    );
    final days = <BusDayRoute>[];
    for (final spots in ordered.days) {
      final nodes = <ItineraryRouteNode>[cursor];
      for (final spot in spots) {
        if (spot.latitude == null || spot.longitude == null) continue;
        final node = ItineraryRouteNode(
          point: LatLng(spot.latitude!, spot.longitude!),
          place: spot.location,
          label: spot.name,
          detail: '${spot.name}, ${spot.location}',
          spot: spot,
        );
        if (_samePoint(nodes.last.point, node.point)) continue;
        nodes.add(node);
        cursor = node;
      }
      days.add(BusDayRoute(nodes: nodes, spots: spots));
    }
    return BusItineraryPlan(days: days, error: ordered.error);
  }

  List<BusDayRoute> get _routes =>
      _plan?.days ??
      [
        for (final day in _inputDays)
          BusDayRoute(nodes: const [], spots: day),
      ];

  List<ItineraryRouteNode> _nodesFor(int? dayIndex) {
    final routes = _routes;
    if (dayIndex != null) {
      if (dayIndex < 0 || dayIndex >= routes.length) return const [];
      return routes[dayIndex].nodes;
    }
    final all = <ItineraryRouteNode>[];
    for (final day in routes) {
      for (final node in day.nodes) {
        if (all.isNotEmpty && _samePoint(all.last.point, node.point)) continue;
        all.add(node);
      }
    }
    return all;
  }

  _DisplayedRoute _routeFor(int? dayIndex) {
    final nodes = _nodesFor(dayIndex);
    final roadNodes = nodes.where((node) => node.onRoad).toList();
    final start = nodes.isEmpty ? null : nodes.first;
    final end = nodes.length < 2 ? null : nodes.last;
    final stops = <RoadStop>[
      for (final node in roadNodes) (place: node.place, point: node.point),
    ];
    final spots = <TouristSpot>[];
    final seenSpots = <String>{};
    final buses = <TripBusMarker>[];
    final seenBuses = <String>{};
    for (final node in nodes) {
      final spot = node.spot;
      if (spot != null && seenSpots.add(spot.name)) spots.add(spot);
      if (!node.isBus) continue;
      final key =
          '${node.point.latitude.toStringAsFixed(5)},${node.point.longitude.toStringAsFixed(5)}';
      if (!seenBuses.add(key)) continue;
      buses.add(
        TripBusMarker(
          point: node.point,
          kind: node.busKind!,
          label: node.detail,
        ),
      );
    }
    return _DisplayedRoute(
      stops: stops,
      startPoint: start?.point,
      startDetail: start?.detail ?? '',
      endPoint: end?.point,
      endDetail: end?.detail ?? '',
      spots: spots,
      buses: buses,
    );
  }

  bool _samePoint(LatLng a, LatLng b) {
    return (a.latitude - b.latitude).abs() < 1e-5 &&
        (a.longitude - b.longitude).abs() < 1e-5;
  }

  @override
  Widget build(BuildContext context) {
    final days = _routes;
    final showDayPicker = days.length > 1;
    final displayed = _ordering ? null : _routeFor(_day);
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        foregroundColor: Colors.black,
        title: const Text(
          'Trip Route',
          style: TextStyle(
            color: Colors.black87,
            fontWeight: FontWeight.w600,
            fontSize: 18,
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.fit_screen),
            tooltip: 'Fit route',
            onPressed: () => _mapKey.currentState?.fitRouteBounds(),
          ),
        ],
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (showDayPicker)
            SizedBox(
              height: 52,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                children: [
                  ChoiceChip(
                    label: const Text('Entire itinerary'),
                    selected: _day == null,
                    onSelected: _ordering
                        ? null
                        : (_) => setState(() => _day = null),
                  ),
                  for (var i = 0; i < days.length; i++) ...[
                    const SizedBox(width: 8),
                    ChoiceChip(
                      label: Text('Day ${i + 1}'),
                      selected: _day == i,
                      onSelected: _ordering
                          ? null
                          : (_) => setState(() => _day = i),
                    ),
                  ],
                ],
              ),
            ),
          if (_visibleOrderError != null)
            Material(
              color: const Color(0xFFFFF3E0),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                child: Text(
                  _visibleOrderError!,
                  style: const TextStyle(fontSize: 13, height: 1.35),
                ),
              ),
            ),
          Expanded(
            child: _ordering || displayed == null
                ? const Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        CircularProgressIndicator(),
                        SizedBox(height: 12),
                        Text('Finding the nearest road route...'),
                      ],
                    ),
                  )
                : TripRouteMapView(
                    key: _mapKey,
                    start: widget.start,
                    end: widget.end,
                    spots: displayed.spots,
                    budget: widget.budget,
                    exactBudgetSpotNames: widget.exactBudgetSpotNames,
                    direction: widget.direction,
                    visitStops: displayed.stops,
                    startPinPoint: displayed.startPoint,
                    startPinDetail: displayed.startDetail,
                    endPinPoint: displayed.endPoint,
                    endPinDetail: displayed.endDetail,
                    busMarkers: displayed.buses,
                  ),
          ),
        ],
      ),
    );
  }
}

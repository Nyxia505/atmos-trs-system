import 'package:flutter/material.dart';

import 'data.dart';
import 'municipal_road_distances.dart' show RoadRouteDirection;
import 'trip_route_fare_service.dart';
import 'widgets/trip_route_map_view.dart';

/// Full-screen map: start → spots → end with road polyline (flutter_map).
class TripPlanRouteMapPage extends StatefulWidget {
  final Municipality start;
  final Municipality end;
  final List<TouristSpot> spots;
  final double budget;
  final Set<String> exactBudgetSpotNames;
  final TripRouteFareBreakdown? routeFareBreakdown;
  final String transportMode;
  final RoadRouteDirection? direction;

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
  });

  @override
  State<TripPlanRouteMapPage> createState() => _TripPlanRouteMapPageState();
}

class _TripPlanRouteMapPageState extends State<TripPlanRouteMapPage> {
  final _mapKey = GlobalKey<TripRouteMapViewState>();

  @override
  Widget build(BuildContext context) {
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
          Expanded(
            child: TripRouteMapView(
              key: _mapKey,
              start: widget.start,
              end: widget.end,
              spots: widget.spots,
              budget: widget.budget,
              exactBudgetSpotNames: widget.exactBudgetSpotNames,
              direction: widget.direction,
            ),
          ),
        ],
      ),
    );
  }
}

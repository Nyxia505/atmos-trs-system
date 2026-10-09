import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart' show LatLng;
import 'package:latlong2/latlong.dart' as ll;

import '../data.dart';
import '../municipality_coordinates.dart'
    show getMunicipalityCoordinates, misamisOccidentalCenter;
import '../spot_detail_screen.dart';
import '../trip_planner_utils.dart';
import 'bus_terminal_map_markers.dart';
import 'osm_map_tiles.dart';
import 'trip_route_style.dart';

ll.LatLng _toOsm(LatLng p) => ll.LatLng(p.latitude, p.longitude);

/// OpenStreetMap trip route (web fallback — no Google Maps API key / billing).
class TripRouteOsmMapView extends StatefulWidget {
  final Municipality start;
  final Municipality end;
  final List<TouristSpot> spots;
  final double budget;
  final Set<String> exactBudgetSpotNames;
  final bool compact;
  final List<LatLng> routeLinePoints;
  /// True when line follows roads (Directions API); thicker solid blue like Google Maps.
  final bool roadFollowing;

  const TripRouteOsmMapView({
    super.key,
    required this.start,
    required this.end,
    required this.spots,
    required this.budget,
    required this.exactBudgetSpotNames,
    required this.compact,
    required this.routeLinePoints,
    this.roadFollowing = false,
  });

  @override
  State<TripRouteOsmMapView> createState() => TripRouteOsmMapViewState();
}

class TripRouteOsmMapViewState extends State<TripRouteOsmMapView> {
  final MapController _controller = MapController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) fitRouteBounds();
    });
  }

  LatLng? get _startPosition => getMunicipalityCoordinates(widget.start);

  LatLng? get _endPosition => getMunicipalityCoordinates(widget.end);

  List<Marker> _buildMarkers() {
    final markers = <Marker>[];
    final start = _startPosition;
    final end = _endPosition;

    if (start != null) {
      final bus = busTerminalForMap(widget.start);
      markers.add(
        _busHubMarker(
          _toOsm(start),
          widget.start,
          bus,
          fallbackLabel: widget.start.shortName.isNotEmpty
              ? widget.start.shortName
              : widget.start.name,
        ),
      );
    }
    if (end != null) {
      final bus = busTerminalForMap(widget.end);
      markers.add(
        _busHubMarker(
          _toOsm(end),
          widget.end,
          bus,
          fallbackLabel: widget.end.shortName.isNotEmpty
              ? widget.end.shortName
              : widget.end.name,
        ),
      );
    }

    for (final spot in widget.spots) {
      if (spot.latitude == null || spot.longitude == null) continue;
      final pos = LatLng(spot.latitude!, spot.longitude!);
      if (start != null && _same(pos, start)) continue;
      if (end != null && _same(pos, end)) continue;
      final fit = evaluateBudgetFit(spot, widget.budget);
      final exactMatch =
          widget.exactBudgetSpotNames.contains(spot.name) ||
          fit.exactBudgetMatch;
      markers.add(
        _pinMarker(
          _toOsm(pos),
          exactMatch ? Colors.green : Colors.orange,
          spot.name,
          onTap: widget.compact
              ? null
              : () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => SpotDetailScreen(spot: spot),
                    ),
                  );
                },
        ),
      );
    }
    return markers;
  }

  bool _same(LatLng a, LatLng b) {
    return (a.latitude - b.latitude).abs() < 1e-5 &&
        (a.longitude - b.longitude).abs() < 1e-5;
  }

  Marker _busHubMarker(
    ll.LatLng point,
    Municipality municipality,
    MunicipalityBusTerminal? bus, {
    required String fallbackLabel,
  }) {
    if (bus != null) {
      return Marker(
        point: point,
        width: 44,
        height: 44,
        child: Tooltip(
          message:
              '${busTerminalMarkerTitle(bus)}\n${busTerminalMarkerSnippet(municipality, bus)}',
          child: Icon(
            bus.kind == 'stop'
                ? Icons.directions_bus
                : Icons.directions_bus_filled,
            color: bus.kind == 'stop'
                ? const Color(0xFF7B1FA2)
                : const Color(0xFF1565C0),
            size: 38,
            shadows: const [
              Shadow(blurRadius: 4, color: Colors.black38),
            ],
          ),
        ),
      );
    }
    return _pinMarker(point, Colors.red, fallbackLabel);
  }

  Marker _pinMarker(
    ll.LatLng point,
    Color color,
    String label, {
    VoidCallback? onTap,
  }) {
    return Marker(
      point: point,
      width: 40,
      height: 40,
      child: GestureDetector(
        onTap: onTap,
        child: Tooltip(
          message: label,
          child: Icon(Icons.location_on, color: color, size: 36),
        ),
      ),
    );
  }

  void fitRouteBounds() {
    final line = widget.routeLinePoints;
    if (line.length < 2) {
      if (line.length == 1) {
        _controller.move(_toOsm(line.first), 13);
      } else {
        _controller.move(_toOsm(misamisOccidentalCenter), 10.5);
      }
      return;
    }
    final osm = line.map(_toOsm).toList();
    _controller.fitCamera(
      CameraFit.bounds(
        bounds: LatLngBounds.fromPoints(osm),
        padding: EdgeInsets.all(widget.compact ? 24 : 48),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final routeOsm = widget.routeLinePoints.map(_toOsm).toList();
    final polylines = <Polyline>[];
    if (routeOsm.length >= 2) {
      final w = TripRouteStyle.routeWidth(
        compact: widget.compact,
        roadLine: widget.roadFollowing,
      );
      if (widget.roadFollowing) {
        polylines.add(
          Polyline(
            points: routeOsm,
            color: TripRouteStyle.routeBlueDark,
            strokeWidth:
                TripRouteStyle.routeCasingWidth(compact: widget.compact)
                    .toDouble(),
          ),
        );
      }
      polylines.add(
        Polyline(
          points: routeOsm,
          color: TripRouteStyle.routeBlue,
          strokeWidth: w.toDouble(),
          strokeCap: StrokeCap.round,
          strokeJoin: StrokeJoin.round,
        ),
      );
    }

    final map = FlutterMap(
      mapController: _controller,
      options: MapOptions(
        initialCenter: _toOsm(misamisOccidentalCenter),
        initialZoom: 10.5,
        minZoom: 8,
        maxZoom: 18,
        backgroundColor: const Color(0xFFE8EEF2),
        onMapReady: fitRouteBounds,
        interactionOptions: InteractionOptions(
          flags: widget.compact
              ? InteractiveFlag.none
              : InteractiveFlag.all,
        ),
      ),
      children: [
        osmBasemapTileLayer(),
        if (polylines.isNotEmpty) PolylineLayer(polylines: polylines),
        MarkerLayer(markers: _buildMarkers()),
        osmMapAttribution(),
      ],
    );

    return SizedBox.expand(
      child: widget.compact ? IgnorePointer(child: map) : map,
    );
  }
}

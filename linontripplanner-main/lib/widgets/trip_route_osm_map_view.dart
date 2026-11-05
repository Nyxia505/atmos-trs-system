import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart' show LatLng;
import 'package:latlong2/latlong.dart' as ll;

import '../data.dart';
import '../municipality_coordinates.dart'
    show getMunicipalityCoordinates, misamisOccidentalCenter;
import '../spot_detail_screen.dart';
import '../trip_planner_utils.dart';
import 'osm_map_glyph.dart';
import 'osm_map_tiles.dart';
import 'trip_route_style.dart';

ll.LatLng _toOsm(LatLng p) => ll.LatLng(p.latitude, p.longitude);

/// Bus stop or terminal shown on the trip map. [kind] is `stop` or `terminal`.
class TripBusMarker {
  final LatLng point;
  final String kind;
  final String label;
  final String name;
  final String municipality;
  final String routeTypeLabel;
  final double? distanceKmFromRoute;
  final String? nearSpotName;
  final bool isRecommendedDropOff;
  final String dropOffNote;

  const TripBusMarker({
    required this.point,
    required this.kind,
    required this.label,
    this.name = '',
    this.municipality = '',
    this.routeTypeLabel = '',
    this.distanceKmFromRoute,
    this.nearSpotName,
    this.isRecommendedDropOff = false,
    this.dropOffNote = '',
  });

  String get displayName =>
      name.trim().isNotEmpty ? name.trim() : label.trim();
}

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
  /// Walking mode: dotted blue route like Google Maps.
  final bool dottedRoute;
  /// Origin as a white circle, destination as a red pin (no name banners).
  final bool googleStyleEndpoints;
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
  /// When true, pinch/double-tap/scroll zoom and pan are enabled even if
  /// [compact] is true (for embedding in Tourist Spot Details).
  final bool interactive;

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
    this.dottedRoute = false,
    this.googleStyleEndpoints = false,
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
    this.interactive = false,
  });

  @override
  State<TripRouteOsmMapView> createState() => TripRouteOsmMapViewState();
}

class TripRouteOsmMapViewState extends State<TripRouteOsmMapView> {
  final MapController _controller = MapController();
  Size? _lastSize;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) fitRouteBounds();
    });
  }

  @override
  void didUpdateWidget(TripRouteOsmMapView oldWidget) {
    super.didUpdateWidget(oldWidget);
    final lineChanged = !_sameLine(
          oldWidget.routeLinePoints,
          widget.routeLinePoints,
        ) ||
        !_sameLatLng(oldWidget.startPinPoint, widget.startPinPoint) ||
        !_sameLatLng(oldWidget.endPinPoint, widget.endPinPoint);
    if (lineChanged) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) fitRouteBounds();
      });
    }
  }

  bool _sameLatLng(LatLng? a, LatLng? b) {
    if (a == null && b == null) return true;
    if (a == null || b == null) return false;
    return (a.latitude - b.latitude).abs() < 1e-5 &&
        (a.longitude - b.longitude).abs() < 1e-5;
  }

  bool _sameLine(List<LatLng> a, List<LatLng> b) {
    if (a.length != b.length) return false;
    if (a.isEmpty) return true;
    return _sameLatLng(a.first, b.first) && _sameLatLng(a.last, b.last);
  }

  ll.LatLng get _initialCenter {
    final pts = widget.routeLinePoints;
    if (pts.length >= 2) {
      var lat = 0.0;
      var lng = 0.0;
      for (final p in pts) {
        lat += p.latitude;
        lng += p.longitude;
      }
      return ll.LatLng(lat / pts.length, lng / pts.length);
    }
    final end = widget.endPinPoint;
    if (end != null) return _toOsm(end);
    final start = widget.startPinPoint ?? getMunicipalityCoordinates(widget.start);
    if (start != null) return _toOsm(start);
    return _toOsm(misamisOccidentalCenter);
  }

  double get _initialZoom {
    final pts = widget.routeLinePoints;
    if (pts.length < 2) return widget.endPinPoint != null ? 14 : 11;
    var minLat = pts.first.latitude;
    var maxLat = minLat;
    var minLng = pts.first.longitude;
    var maxLng = minLng;
    for (final p in pts) {
      if (p.latitude < minLat) minLat = p.latitude;
      if (p.latitude > maxLat) maxLat = p.latitude;
      if (p.longitude < minLng) minLng = p.longitude;
      if (p.longitude > maxLng) maxLng = p.longitude;
    }
    final span = (maxLat - minLat).abs() + (maxLng - minLng).abs();
    if (span < 0.04) return 14;
    if (span < 0.12) return 13;
    if (span < 0.3) return 12;
    return 11;
  }

  LatLng? get _startPosition =>
      widget.startPinPoint ?? getMunicipalityCoordinates(widget.start);

  LatLng? get _endPosition => widget.endPinPoint;

  List<Marker> _buildMarkers() {
    final markers = <Marker>[];
    final start = _startPosition;
    final end = _endPosition;

    if (start != null) {
      final detail = widget.startPinDetail.trim().isEmpty
          ? (widget.start.shortName.isNotEmpty
              ? widget.start.shortName
              : widget.start.name)
          : widget.startPinDetail.trim();
      markers.add(
        widget.googleStyleEndpoints
            ? _googleOriginMarker(
                _toOsm(start),
                title: widget.startPinTitle,
                detail: detail,
              )
            : _namedEndpointMarker(
                _toOsm(start),
                color: const Color(0xFF1565C0),
                title: widget.startPinTitle,
                detail: detail,
              ),
      );
    }
    if (end != null) {
      final detail = widget.endPinDetail.trim().isEmpty
          ? (widget.end.shortName.isNotEmpty
              ? widget.end.shortName
              : widget.end.name)
          : widget.endPinDetail.trim();
      markers.add(
        widget.googleStyleEndpoints
            ? _googleDestinationMarker(
                _toOsm(end),
                title: widget.endPinTitle,
                detail: detail,
              )
            : _namedEndpointMarker(
                _toOsm(end),
                color: const Color(0xFFE53935),
                title: widget.endPinTitle,
                detail: detail,
              ),
      );
    }

    for (final bus in widget.busMarkers) {
      final isStop = bus.kind == 'stop';
      if (isStop && !widget.showBusStops) continue;
      if (!isStop && !widget.showBusTerminals) continue;
      if (start != null && _same(bus.point, start)) continue;
      if (end != null && _same(bus.point, end)) continue;
      markers.add(
        _busMarker(
          _toOsm(bus.point),
          color: bus.isRecommendedDropOff
              ? const Color(0xFF2E7D32)
              : (isStop ? const Color(0xFF7B1FA2) : const Color(0xFF1565C0)),
          icon: isStop ? Icons.directions_bus : Icons.directions_bus_filled,
          title: isStop ? 'Bus stop' : 'Bus terminal',
          bus: bus,
        ),
      );
    }

    if (widget.showTouristSpots) {
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
    }
    return markers;
  }

  bool _same(LatLng a, LatLng b) {
    return (a.latitude - b.latitude).abs() < 1e-5 &&
        (a.longitude - b.longitude).abs() < 1e-5;
  }

  Marker _googleOriginMarker(
    ll.LatLng point, {
    required String title,
    required String detail,
  }) {
    final message =
        detail.isEmpty || detail == title ? title : '$title\n$detail';
    return Marker(
      point: point,
      width: 22,
      height: 22,
      child: Tooltip(
        message: message,
        child: Container(
          decoration: BoxDecoration(
            color: Colors.white,
            shape: BoxShape.circle,
            border: Border.all(color: const Color(0xFF202124), width: 3),
            boxShadow: const [
              BoxShadow(
                color: Color(0x66000000),
                blurRadius: 4,
                offset: Offset(0, 1),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Marker _googleDestinationMarker(
    ll.LatLng point, {
    required String title,
    required String detail,
  }) {
    final message =
        detail.isEmpty || detail == title ? title : '$title\n$detail';
    return Marker(
      point: point,
      width: 40,
      height: 40,
      alignment: Alignment.topCenter,
      child: Tooltip(
        message: message,
        child: const OsmMapGlyph(
          icon: Icons.location_on,
          color: Color(0xFFEA4335),
          size: 40,
        ),
      ),
    );
  }

  Marker _namedEndpointMarker(
    ll.LatLng point, {
    required Color color,
    required String title,
    required String detail,
  }) {
    final message = detail.isEmpty || detail == title ? title : '$title\n$detail';
    return Marker(
      point: point,
      width: 168,
      height: 96,
      alignment: Alignment.bottomCenter,
      child: Align(
        alignment: Alignment.bottomCenter,
        child: GestureDetector(
        onTap: widget.compact
            ? null
            : () {
                showDialog<void>(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    title: Text(title),
                    content: Text(detail.isEmpty ? title : detail),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(ctx),
                        child: const Text('Close'),
                      ),
                    ],
                  ),
                );
              },
        child: Tooltip(
          message: message,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                constraints: const BoxConstraints(maxWidth: 160),
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: color, width: 1.6),
                  boxShadow: const [
                    BoxShadow(blurRadius: 4, color: Colors.black26),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: color,
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    if (detail.isNotEmpty && detail != title)
                      Text(
                        detail,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.black87,
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                  ],
                ),
              ),
              OsmMapGlyph(
                icon: Icons.location_on,
                color: color,
                size: 40,
              ),
            ],
          ),
        ),
        ),
      ),
    );
  }

  Marker _busMarker(
    ll.LatLng point, {
    required Color color,
    required IconData icon,
    required String title,
    required TripBusMarker bus,
  }) {
    final lines = <String>[
      bus.displayName,
      if (bus.municipality.trim().isNotEmpty) 'Municipality: ${bus.municipality}',
      'Location: ${bus.point.latitude.toStringAsFixed(5)}, '
          '${bus.point.longitude.toStringAsFixed(5)}',
      if (bus.routeTypeLabel.trim().isNotEmpty)
        'Transport: ${bus.routeTypeLabel}',
      if (bus.distanceKmFromRoute != null)
        'Distance to ${bus.nearSpotName ?? 'destination'}: '
            '${bus.distanceKmFromRoute!.toStringAsFixed(1)} km',
      if (bus.isRecommendedDropOff)
        'Recommended drop-off point'
      else if (bus.dropOffNote.trim().isNotEmpty)
        bus.dropOffNote.trim(),
    ];
    final detail = lines.join('\n');
    return Marker(
      point: point,
      width: 44,
      height: 44,
      child: GestureDetector(
        onTap: widget.compact
            ? null
            : () {
                showDialog<void>(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    title: Text(title),
                    content: Text(detail),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(ctx),
                        child: const Text('Close'),
                      ),
                    ],
                  ),
                );
              },
        child: Tooltip(
          message: '$title\n$detail',
          child: OsmMapGlyph(
            icon: icon,
            color: color,
            size: 36,
          ),
        ),
      ),
    );
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
          child: OsmMapGlyph(
            icon: Icons.location_on,
            color: color,
            size: 36,
          ),
        ),
      ),
    );
  }

  void fitRouteBounds() {
    try {
      final line = <LatLng>[
        ...widget.routeLinePoints,
        if (_startPosition != null) _startPosition!,
        if (_endPosition != null) _endPosition!,
        for (final spot in widget.spots)
          if (spot.latitude != null && spot.longitude != null)
            LatLng(spot.latitude!, spot.longitude!),
      ];
      if (line.length < 2) {
        if (line.length == 1) {
          _controller.move(_toOsm(line.first), 14);
        }
        return;
      }
      _controller.fitCamera(
        CameraFit.bounds(
          bounds: LatLngBounds.fromPoints(line.map(_toOsm).toList()),
          padding: EdgeInsets.all(widget.compact ? 36 : 56),
        ),
      );
    } catch (_) {}
  }

  void zoomBy(double delta) {
    try {
      final cam = _controller.camera;
      final next = (cam.zoom + delta).clamp(8.0, 18.0);
      _controller.move(cam.center, next);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final routeOsm = widget.routeLinePoints.map(_toOsm).toList();
    final polylines = <Polyline>[];
    if (routeOsm.length >= 2) {
      if (widget.dottedRoute) {
        polylines.add(
          Polyline(
            points: routeOsm,
            color: TripRouteStyle.routeBlue,
            strokeWidth: TripRouteStyle.walkingDotWidth(
              compact: widget.compact,
            ).toDouble(),
            // flutter_map 7+: dotted strokes use StrokePattern (isDotted removed).
            pattern: const StrokePattern.dotted(),
            strokeCap: StrokeCap.round,
            strokeJoin: StrokeJoin.round,
          ),
        );
      } else {
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
    }

    final map = FlutterMap(
      mapController: _controller,
      options: MapOptions(
        initialCenter: _initialCenter,
        initialZoom: _initialZoom,
        minZoom: 7,
        maxZoom: 18,
        backgroundColor: const Color(0xFFE8EEF2),
        onMapReady: fitRouteBounds,
        interactionOptions: InteractionOptions(
          flags: widget.interactive
              ? InteractiveFlag.all & ~InteractiveFlag.rotate
              : InteractiveFlag.none,
        ),
      ),
      children: [
        osmBasemapTileLayer(),
        if (polylines.isNotEmpty) PolylineLayer(polylines: polylines),
        MarkerLayer(markers: _buildMarkers()),
        osmMapAttribution(),
      ],
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        final size = Size(constraints.maxWidth, constraints.maxHeight);
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          final last = _lastSize;
          if (last != null &&
              (size.width - last.width).abs() < 8 &&
              (size.height - last.height).abs() < 8) {
            return;
          }
          _lastSize = size;
          fitRouteBounds();
        });
        return SizedBox.expand(
          child: RepaintBoundary(
            child: widget.interactive ? map : IgnorePointer(child: map),
          ),
        );
      },
    );
  }
}

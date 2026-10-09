import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart' as ll;

import '../data.dart';
import 'osm_map_tiles.dart';

/// Admin overview map of high-rated spots (flutter_map / OpenStreetMap).
class AdminHighRatingSpotsMap extends StatelessWidget {
  const AdminHighRatingSpotsMap({super.key, required this.spots});

  final List<TouristSpot> spots;

  @override
  Widget build(BuildContext context) {
    return _OsmHighRatingSpotsMap(spots: spots);
  }
}

class _OsmHighRatingSpotsMap extends StatefulWidget {
  const _OsmHighRatingSpotsMap({required this.spots});

  final List<TouristSpot> spots;

  @override
  State<_OsmHighRatingSpotsMap> createState() => _OsmHighRatingSpotsMapState();
}

class _OsmHighRatingSpotsMapState extends State<_OsmHighRatingSpotsMap> {
  final MapController _controller = MapController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _fitBounds();
    });
  }

  @override
  void didUpdateWidget(covariant _OsmHighRatingSpotsMap oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.spots != widget.spots) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _fitBounds();
      });
    }
  }

  void _fitBounds() {
    final points = <ll.LatLng>[];
    for (final spot in widget.spots) {
      if (spot.latitude != null && spot.longitude != null) {
        points.add(ll.LatLng(spot.latitude!, spot.longitude!));
      }
    }
    if (points.isEmpty) {
      _controller.move(const ll.LatLng(8.2, 123.7), 8);
      return;
    }
    if (points.length == 1) {
      _controller.move(points.first, 11);
      return;
    }
    _controller.fitCamera(
      CameraFit.bounds(
        bounds: LatLngBounds.fromPoints(points),
        padding: const EdgeInsets.all(40),
      ),
    );
  }

  List<Marker> _buildMarkers() {
    final markers = <Marker>[];
    for (final spot in widget.spots) {
      if (spot.latitude == null || spot.longitude == null) continue;
      final point = ll.LatLng(spot.latitude!, spot.longitude!);
      final label =
          '${spot.name}\n${spot.rating.toStringAsFixed(1)}★ · ${spot.location}';
      markers.add(
        Marker(
          point: point,
          width: 40,
          height: 40,
          child: Tooltip(
            message: label,
            child: const Icon(
              Icons.location_on,
              color: Color(0xFFE65100),
              size: 36,
              shadows: [Shadow(blurRadius: 4, color: Colors.black38)],
            ),
          ),
        ),
      );
    }
    return markers;
  }

  @override
  Widget build(BuildContext context) {
    return FlutterMap(
      mapController: _controller,
      options: MapOptions(
        initialCenter: const ll.LatLng(8.2, 123.7),
        initialZoom: widget.spots.isEmpty ? 8 : 9,
        minZoom: 7,
        maxZoom: 18,
        backgroundColor: const Color(0xFFE8EEF2),
        onMapReady: _fitBounds,
      ),
      children: [
        osmBasemapTileLayer(),
        MarkerLayer(markers: _buildMarkers()),
        osmMapAttribution(),
      ],
    );
  }
}

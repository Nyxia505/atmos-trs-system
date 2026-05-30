import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart' as gmaps;
import 'package:latlong2/latlong.dart' as osm;
import 'package:atmos_trs_system/config/app_theme.dart';
import 'package:atmos_trs_system/config/google_maps_config.dart';
import 'package:atmos_trs_system/models/tourist_spot_firestore.dart';
import 'package:atmos_trs_system/utils/google_maps_js_ready.dart';
import 'package:atmos_trs_system/widgets/map_zoom_controls.dart';

/// Misamis Occidental map defaults.
const double kMisamisMapCenterLat = 8.3377;
const double kMisamisMapCenterLng = 123.7072;
const double kMisamisMapDefaultZoom = 9.5;

final gmaps.LatLngBounds kMisamisGoogleBounds = gmaps.LatLngBounds(
  southwest: const gmaps.LatLng(7.95, 123.45),
  northeast: const gmaps.LatLng(8.70, 124.00),
);

/// Responsive map height for Explore embedded province map.
double misamisEmbeddedMapHeight(BuildContext context) {
  final size = MediaQuery.sizeOf(context);
  if (size.width >= 1100) return 500;
  if (size.width >= 600) {
    return (size.height * 0.44).clamp(380.0, 540.0);
  }
  return (size.height * 0.42).clamp(360.0, 500.0);
}

/// Taller map when drilling into a municipality (e.g. Oroquieta City).
double municipalityDetailMapHeight(BuildContext context) {
  final size = MediaQuery.sizeOf(context);
  if (size.width >= 1100) {
    return (size.height * 0.58).clamp(480.0, 680.0);
  }
  if (size.width >= 600) {
    return (size.height * 0.52).clamp(400.0, 580.0);
  }
  return (size.height * 0.48).clamp(360.0, 520.0);
}

/// Moves the map camera to a lat/lng.
typedef MisamisMapMoveTo = void Function(
  double latitude,
  double longitude, {
  double zoom,
});

/// Web uses Google Maps when [GoogleMapsConfig.webApiKey] is set in `web/index.html`.
/// Set `USE_GOOGLE_MAPS_WEB=false` to fall back to OpenStreetMap on web.
const bool kUseGoogleMapsOnWeb = bool.fromEnvironment(
  'USE_GOOGLE_MAPS_WEB',
  defaultValue: true,
);

/// Province map: **Google Maps** on mobile; **OpenStreetMap** on web (or Google when enabled).
class MisamisOccidentalExploreMap extends StatelessWidget {
  const MisamisOccidentalExploreMap({
    super.key,
    required this.spots,
    this.onSpotTap,
    this.onMapReady,
    this.initialZoom = kMisamisMapDefaultZoom,
    this.showZoomControls = true,
    this.centerLat,
    this.centerLng,
  });

  final List<TouristSpotFirestore> spots;
  final ValueChanged<TouristSpotFirestore>? onSpotTap;
  final ValueChanged<MisamisMapMoveTo>? onMapReady;
  final double initialZoom;
  final bool showZoomControls;
  final double? centerLat;
  final double? centerLng;

  @override
  Widget build(BuildContext context) {
    final useGoogle = !kIsWeb || (kUseGoogleMapsOnWeb && GoogleMapsConfig.hasWebApiKey);

    if (useGoogle) {
      return _MisamisGoogleExploreMap(
        spots: spots,
        onSpotTap: onSpotTap,
        onMapReady: onMapReady,
        initialZoom: initialZoom,
        showZoomControls: showZoomControls,
        centerLat: centerLat,
        centerLng: centerLng,
      );
    }

    return _MisamisOsmExploreMap(
      spots: spots,
      onSpotTap: onSpotTap,
      onMapReady: onMapReady,
      initialZoom: initialZoom,
      showZoomControls: showZoomControls,
      centerLat: centerLat,
      centerLng: centerLng,
    );
  }
}

// -----------------------------------------------------------------------------
// Web — OpenStreetMap (no ApiTargetBlockedMapError; works without Browser API key)
// -----------------------------------------------------------------------------

final LatLngBounds kMisamisOsmBounds = LatLngBounds(
  const osm.LatLng(7.92, 123.38),
  const osm.LatLng(8.72, 124.02),
);

class _MisamisOsmExploreMap extends StatefulWidget {
  const _MisamisOsmExploreMap({
    required this.spots,
    this.onSpotTap,
    this.onMapReady,
    required this.initialZoom,
    required this.showZoomControls,
    this.centerLat,
    this.centerLng,
  });

  final List<TouristSpotFirestore> spots;
  final ValueChanged<TouristSpotFirestore>? onSpotTap;
  final ValueChanged<MisamisMapMoveTo>? onMapReady;
  final double initialZoom;
  final bool showZoomControls;
  final double? centerLat;
  final double? centerLng;

  @override
  State<_MisamisOsmExploreMap> createState() => _MisamisOsmExploreMapState();
}

class _MisamisOsmExploreMapState extends State<_MisamisOsmExploreMap> {
  final MapController _mapController = MapController();

  osm.LatLng get _initialCenter {
    final lat = widget.centerLat;
    final lng = widget.centerLng;
    if (lat != null && lng != null) {
      return osm.LatLng(lat, lng);
    }
    return const osm.LatLng(kMisamisMapCenterLat, kMisamisMapCenterLng);
  }

  double get _osmZoom => widget.initialZoom.clamp(6.0, 18.0);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      widget.onMapReady?.call(_moveTo);
    });
  }

  void _moveTo(
    double latitude,
    double longitude, {
    double zoom = 13,
  }) {
    _mapController.move(
      osm.LatLng(latitude, longitude),
      zoom.clamp(6.0, 18.0),
    );
  }

  void _recenter() {
    _moveTo(
      _initialCenter.latitude,
      _initialCenter.longitude,
      zoom: _osmZoom,
    );
  }

  List<Marker> _buildMarkers() {
    return widget.spots
        .where((s) => s.latitude != 0 || s.longitude != 0)
        .map(
          (s) => Marker(
            point: osm.LatLng(s.latitude, s.longitude),
            width: 40,
            height: 40,
            child: GestureDetector(
              onTap: () => widget.onSpotTap?.call(s),
              child: Container(
                decoration: BoxDecoration(
                  color: AppTheme.brandOrange,
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 2),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.25),
                      blurRadius: 4,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: const Icon(Icons.place, color: Colors.white, size: 22),
              ),
            ),
          ),
        )
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        FlutterMap(
          mapController: _mapController,
          options: MapOptions(
            initialCenter: _initialCenter,
            initialZoom: _osmZoom,
            minZoom: 6,
            maxZoom: 18,
            cameraConstraint: CameraConstraint.contain(bounds: kMisamisOsmBounds),
            interactionOptions: const InteractionOptions(
              flags: InteractiveFlag.all & ~InteractiveFlag.rotate,
            ),
          ),
          children: [
            TileLayer(
              urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
              userAgentPackageName: 'com.atmos.trs',
            ),
            MarkerLayer(markers: _buildMarkers()),
          ],
        ),
        if (widget.showZoomControls)
          OsmMapZoomControls(
            mapController: _mapController,
            minZoom: 6,
            maxZoom: 18,
            onRecenter: _recenter,
            bottom: 12,
            right: 12,
          ),
      ],
    );
  }
}

class _MisamisGoogleExploreMap extends StatefulWidget {
  const _MisamisGoogleExploreMap({
    required this.spots,
    this.onSpotTap,
    this.onMapReady,
    required this.initialZoom,
    required this.showZoomControls,
    this.centerLat,
    this.centerLng,
  });

  final List<TouristSpotFirestore> spots;
  final ValueChanged<TouristSpotFirestore>? onSpotTap;
  final ValueChanged<MisamisMapMoveTo>? onMapReady;
  final double initialZoom;
  final bool showZoomControls;
  final double? centerLat;
  final double? centerLng;

  @override
  State<_MisamisGoogleExploreMap> createState() =>
      _MisamisGoogleExploreMapState();
}

class _MisamisGoogleExploreMapState extends State<_MisamisGoogleExploreMap> {
  gmaps.GoogleMapController? _googleController;
  Set<gmaps.Marker> _markers = {};
  double _markerHue = AppTheme.brandMapMarkerHue;
  bool _webMapsJsReady = !kIsWeb;
  bool _webMapsJsFailed = false;

  static final Set<Factory<OneSequenceGestureRecognizer>> _mapGestures = {
    Factory<OneSequenceGestureRecognizer>(() => EagerGestureRecognizer()),
  };

  @override
  void initState() {
    super.initState();
    _markerHue = AppTheme.brandMapMarkerHue;
    _markers = _buildMarkers(widget.spots);
    if (kIsWeb) {
      _waitForGoogleMapsJs();
    } else {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        widget.onMapReady?.call(_moveTo);
      });
    }
  }

  Future<void> _waitForGoogleMapsJs() async {
    for (var i = 0; i < 150; i++) {
      if (!mounted) return;
      if (isGoogleMapsJsReady()) {
        setState(() {
          _webMapsJsReady = true;
          _webMapsJsFailed = false;
        });
        return;
      }
      await Future.delayed(const Duration(milliseconds: 100));
    }
    if (mounted) {
      setState(() {
        _webMapsJsFailed = true;
        _webMapsJsReady = false;
      });
    }
  }

  @override
  void didUpdateWidget(_MisamisGoogleExploreMap oldWidget) {
    super.didUpdateWidget(oldWidget);
    final hue = AppTheme.brandMapMarkerHue;
    final spotsChanged = !_sameSpots(oldWidget.spots, widget.spots);
    if (spotsChanged || hue != _markerHue) {
      _markerHue = hue;
      _markers = _buildMarkers(widget.spots);
    }
  }

  bool _sameSpots(List<TouristSpotFirestore> a, List<TouristSpotFirestore> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i].id != b[i].id ||
          a[i].latitude != b[i].latitude ||
          a[i].longitude != b[i].longitude) {
        return false;
      }
    }
    return true;
  }

  Set<gmaps.Marker> _buildMarkers(List<TouristSpotFirestore> spots) {
    return spots
        .where((s) => s.latitude != 0 || s.longitude != 0)
        .map(
          (s) => gmaps.Marker(
            markerId: gmaps.MarkerId(s.id),
            position: gmaps.LatLng(s.latitude, s.longitude),
            onTap: () => widget.onSpotTap?.call(s),
            icon: gmaps.BitmapDescriptor.defaultMarkerWithHue(_markerHue),
          ),
        )
        .toSet();
  }

  void _moveTo(
    double latitude,
    double longitude, {
    double zoom = 13,
  }) {
    _googleController?.animateCamera(
      gmaps.CameraUpdate.newCameraPosition(
        gmaps.CameraPosition(
          target: gmaps.LatLng(latitude, longitude),
          zoom: zoom,
        ),
      ),
    );
  }

  Future<void> _zoomBy(double delta) async {
    final controller = _googleController;
    if (controller == null) return;
    final zoom = await controller.getZoomLevel();
    final next = (zoom + delta).clamp(6.0, 20.0);
    await controller.animateCamera(gmaps.CameraUpdate.zoomTo(next));
  }

  gmaps.LatLng get _initialTarget {
    final lat = widget.centerLat;
    final lng = widget.centerLng;
    if (lat != null && lng != null) {
      return gmaps.LatLng(lat, lng);
    }
    return const gmaps.LatLng(kMisamisMapCenterLat, kMisamisMapCenterLng);
  }

  void _recenter() {
    _moveTo(
      _initialTarget.latitude,
      _initialTarget.longitude,
      zoom: widget.initialZoom,
    );
  }

  @override
  Widget build(BuildContext context) {
    if (kIsWeb && _webMapsJsFailed) {
      return _MisamisOsmExploreMap(
        spots: widget.spots,
        onSpotTap: widget.onSpotTap,
        onMapReady: widget.onMapReady,
        initialZoom: widget.initialZoom,
        showZoomControls: widget.showZoomControls,
        centerLat: widget.centerLat,
        centerLng: widget.centerLng,
      );
    }

    if (kIsWeb && !_webMapsJsReady) {
      return const ColoredBox(
        color: Color(0xFFE5E7EB),
        child: Center(
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      );
    }

    if (kIsWeb && !isGoogleMapsJsReady()) {
      return const ColoredBox(
        color: Color(0xFFE5E7EB),
        child: Center(
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      );
    }

    return Stack(
      fit: StackFit.expand,
      children: [
        gmaps.GoogleMap(
          gestureRecognizers: _mapGestures,
          initialCameraPosition: gmaps.CameraPosition(
            target: _initialTarget,
            zoom: widget.initialZoom,
          ),
          minMaxZoomPreference: const gmaps.MinMaxZoomPreference(6, 20),
          onMapCreated: (controller) {
            _googleController = controller;
            widget.onMapReady?.call(_moveTo);
          },
          markers: _markers,
          myLocationButtonEnabled: false,
          zoomControlsEnabled: false,
          zoomGesturesEnabled: true,
          scrollGesturesEnabled: true,
          rotateGesturesEnabled: false,
          tiltGesturesEnabled: false,
          compassEnabled: false,
          mapToolbarEnabled: false,
          buildingsEnabled: true,
          trafficEnabled: false,
        ),
        if (widget.showZoomControls)
          Positioned(
            bottom: 12,
            right: 12,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _GoogleZoomButton(
                  icon: Icons.add,
                  onTap: () => _zoomBy(1),
                ),
                const SizedBox(height: 8),
                _GoogleZoomButton(
                  icon: Icons.remove,
                  onTap: () => _zoomBy(-1),
                ),
                const SizedBox(height: 8),
                _GoogleZoomButton(
                  icon: Icons.my_location,
                  onTap: _recenter,
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _GoogleZoomButton extends StatelessWidget {
  const _GoogleZoomButton({required this.icon, required this.onTap});

  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(10),
      elevation: 2,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: SizedBox(
          width: 40,
          height: 40,
          child: Icon(icon, size: 22, color: const Color(0xFF1F2937)),
        ),
      ),
    );
  }
}

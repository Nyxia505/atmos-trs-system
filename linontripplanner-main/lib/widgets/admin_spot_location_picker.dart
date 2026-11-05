import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../theme/tourism_app_theme.dart';
import '../utils/spot_coordinates.dart';
import 'osm_map_tiles.dart';

Future<LatLng?> showAdminSpotLocationPicker(
  BuildContext context, {
  double? latitude,
  double? longitude,
  String? municipalityName,
}) async {
  if (!context.mounted) return null;
  final size = MediaQuery.sizeOf(context);
  return showDialog<LatLng>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: SizedBox(
        width: size.width < 720 ? size.width : 720,
        height: size.height * 0.9,
        child: AdminSpotLocationPickerPage(
          latitude: latitude,
          longitude: longitude,
          municipalityName: municipalityName,
        ),
      ),
    ),
  );
}

class AdminSpotLocationPickerPage extends StatefulWidget {
  const AdminSpotLocationPickerPage({
    super.key,
    this.latitude,
    this.longitude,
    this.municipalityName,
  });

  final double? latitude;
  final double? longitude;
  final String? municipalityName;

  @override
  State<AdminSpotLocationPickerPage> createState() =>
      _AdminSpotLocationPickerPageState();
}

class _AdminSpotLocationPickerPageState
    extends State<AdminSpotLocationPickerPage> {
  final MapController _controller = MapController();
  late LatLng _center;
  late double _zoom;
  LatLng? _pin;
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    _center = initialSpotPickerCenter(
      latitude: widget.latitude,
      longitude: widget.longitude,
      municipalityName: widget.municipalityName,
    );
    _zoom = initialSpotPickerZoom(
      latitude: widget.latitude,
      longitude: widget.longitude,
      municipalityName: widget.municipalityName,
    );
    if (isValidSpotCoordinate(widget.latitude, widget.longitude)) {
      _pin = LatLng(widget.latitude!, widget.longitude!);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _placePin(LatLng point) {
    if (!isValidSpotCoordinate(point.latitude, point.longitude)) return;
    setState(() => _pin = point);
  }

  void _dragPin(DragUpdateDetails details) {
    final pin = _pin;
    if (!_ready || pin == null) return;
    try {
      final screen = _controller.camera.latLngToScreenPoint(pin);
      final next = _controller.camera.pointToLatLng(
        math.Point<double>(
          screen.x + details.delta.dx,
          screen.y + details.delta.dy,
        ),
      );
      _placePin(next);
    } catch (_) {}
  }

  void _zoomBy(double delta) {
    if (!_ready) return;
    try {
      final camera = _controller.camera;
      _controller.move(camera.center, camera.zoom + delta);
    } catch (_) {}
  }

  void _confirm() {
    final pin = _pin;
    if (pin == null ||
        !isValidSpotCoordinate(pin.latitude, pin.longitude)) {
      return;
    }
    Navigator.pop(context, pin);
  }

  @override
  Widget build(BuildContext context) {
    final pin = _pin;
    final canConfirm =
        pin != null && isValidSpotCoordinate(pin.latitude, pin.longitude);
    return Scaffold(
      backgroundColor: OptacaAdminTheme.background,
      appBar: AppBar(
        backgroundColor: OptacaAdminTheme.primary,
        foregroundColor: Colors.white,
        title: const Text('Set location on map'),
      ),
      body: Column(
        children: [
          Expanded(
            child: Stack(
              children: [
                FlutterMap(
                  mapController: _controller,
                  options: MapOptions(
                    initialCenter: _center,
                    initialZoom: _zoom,
                    minZoom: 7,
                    maxZoom: 18,
                    backgroundColor: const Color(0xFFE8EEF2),
                    onMapReady: () => _ready = true,
                    onTap: (tap, point) => _placePin(point),
                    interactionOptions: const InteractionOptions(
                      flags: InteractiveFlag.drag |
                          InteractiveFlag.flingAnimation |
                          InteractiveFlag.pinchMove |
                          InteractiveFlag.pinchZoom |
                          InteractiveFlag.doubleTapZoom |
                          InteractiveFlag.scrollWheelZoom,
                    ),
                  ),
                  children: [
                    osmBasemapTileLayer(),
                    if (pin != null)
                      MarkerLayer(
                        markers: [
                          Marker(
                            point: pin,
                            width: 44,
                            height: 52,
                            alignment: Alignment.topCenter,
                            child: GestureDetector(
                              behavior: HitTestBehavior.opaque,
                              onPanUpdate: _dragPin,
                              child: const Icon(
                                Icons.location_on,
                                color: OptacaAdminTheme.primary,
                                size: 44,
                                shadows: [
                                  Shadow(blurRadius: 4, color: Colors.black38),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    osmMapAttribution(),
                  ],
                ),
                Positioned(
                  right: 12,
                  bottom: 16,
                  child: Column(
                    children: [
                      _ZoomButton(
                        icon: Icons.add,
                        tooltip: 'Zoom in',
                        onPressed: () => _zoomBy(1),
                      ),
                      const SizedBox(height: 8),
                      _ZoomButton(
                        icon: Icons.remove,
                        tooltip: 'Zoom out',
                        onPressed: () => _zoomBy(-1),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Material(
            color: Colors.white,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    pin == null
                        ? 'Tap the map to place the pin, then drag to adjust.'
                        : 'Latitude: ${pin.latitude.toStringAsFixed(4)}\n'
                            'Longitude: ${pin.longitude.toStringAsFixed(4)}',
                    style: const TextStyle(
                      fontSize: 13,
                      height: 1.35,
                      color: OptacaAdminTheme.text,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () => Navigator.pop(context),
                          child: const Text('Cancel'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: FilledButton(
                          onPressed: canConfirm ? _confirm : null,
                          style: FilledButton.styleFrom(
                            backgroundColor: OptacaAdminTheme.primary,
                            foregroundColor: Colors.white,
                            disabledBackgroundColor: OptacaAdminTheme.primary
                                .withValues(alpha: 0.4),
                          ),
                          child: const Text('Confirm Location'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ZoomButton extends StatelessWidget {
  const _ZoomButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      elevation: 2,
      borderRadius: BorderRadius.circular(8),
      child: IconButton(
        tooltip: tooltip,
        onPressed: onPressed,
        icon: Icon(icon, color: OptacaAdminTheme.text),
      ),
    );
  }
}

class AdminSpotLocationPreview extends StatelessWidget {
  const AdminSpotLocationPreview({
    super.key,
    required this.latitude,
    required this.longitude,
  });

  final double latitude;
  final double longitude;

  @override
  Widget build(BuildContext context) {
    final point = LatLng(latitude, longitude);
    return RepaintBoundary(
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: SizedBox(
          height: 140,
          child: IgnorePointer(
            child: FlutterMap(
              options: MapOptions(
                initialCenter: point,
                initialZoom: 14,
                minZoom: 7,
                maxZoom: 18,
                backgroundColor: const Color(0xFFE8EEF2),
                interactionOptions: const InteractionOptions(
                  flags: InteractiveFlag.none,
                ),
              ),
              children: [
                osmBasemapTileLayer(),
                MarkerLayer(
                  markers: [
                    Marker(
                      point: point,
                      width: 36,
                      height: 44,
                      alignment: Alignment.topCenter,
                      child: const Icon(
                        Icons.location_on,
                        color: OptacaAdminTheme.primary,
                        size: 36,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

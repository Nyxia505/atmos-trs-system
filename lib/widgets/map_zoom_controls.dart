import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';

/// +/- (and optional recenter) buttons for [FlutterMap].
class OsmMapZoomControls extends StatelessWidget {
  const OsmMapZoomControls({
    super.key,
    required this.mapController,
    this.minZoom = 7,
    this.maxZoom = 18,
    this.onRecenter,
    this.bottom = 24,
    this.right = 12,
    this.iconColor,
  });

  final MapController mapController;
  final double minZoom;
  final double maxZoom;
  final VoidCallback? onRecenter;
  final double bottom;
  final double right;
  final Color? iconColor;

  void _zoomBy(double delta) {
    final cam = mapController.camera;
    final next = (cam.zoom + delta).clamp(minZoom, maxZoom).toDouble();
    mapController.move(cam.center, next);
  }

  @override
  Widget build(BuildContext context) {
    final color = iconColor ?? const Color(0xFF1F2937);
    return Positioned(
      bottom: bottom,
      right: right,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _MapZoomButton(
            icon: Icons.add,
            iconColor: color,
            onTap: () => _zoomBy(1),
            tooltip: 'Zoom in',
          ),
          const SizedBox(height: 8),
          _MapZoomButton(
            icon: Icons.remove,
            iconColor: color,
            onTap: () => _zoomBy(-1),
            tooltip: 'Zoom out',
          ),
          if (onRecenter != null) ...[
            const SizedBox(height: 8),
            _MapZoomButton(
              icon: Icons.my_location,
              iconColor: color,
              onTap: onRecenter!,
              tooltip: 'Reset view',
            ),
          ],
        ],
      ),
    );
  }
}

class _MapZoomButton extends StatelessWidget {
  const _MapZoomButton({
    required this.icon,
    required this.onTap,
    required this.iconColor,
    this.tooltip,
  });

  final IconData icon;
  final VoidCallback onTap;
  final Color iconColor;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip ?? '',
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        elevation: 2,
        shadowColor: Colors.black26,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(10),
          child: SizedBox(
            width: 36,
            height: 36,
            child: Icon(icon, color: iconColor, size: 20),
          ),
        ),
      ),
    );
  }
}

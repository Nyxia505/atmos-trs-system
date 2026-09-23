import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

import 'package:atmos_trs_system/config/app_theme.dart';
import 'package:atmos_trs_system/widgets/atmos_osm_tile_layer.dart';

/// Captures establishment map pin via device GPS ("Get location")
/// and lets staff open a map preview to verify the pin.
class EstablishmentLocationCapture extends StatelessWidget {
  const EstablishmentLocationCapture({
    super.key,
    required this.latitude,
    required this.longitude,
    required this.onChanged,
    this.busy = false,
    this.onBusyChanged,
    this.required = true,
    this.accentColor,
  });

  final double? latitude;
  final double? longitude;
  final ValueChanged<({double latitude, double longitude})> onChanged;
  final bool busy;
  final ValueChanged<bool>? onBusyChanged;
  final bool required;
  final Color? accentColor;

  bool get _hasPin {
    final lat = latitude;
    final lng = longitude;
    if (lat == null || lng == null) return false;
    return lat.abs() > 1e-6 || lng.abs() > 1e-6;
  }

  Future<void> _capture(BuildContext context) async {
    onBusyChanged?.call(true);
    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Turn on Location services, then try Get location again.',
              ),
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
        return;
      }
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Allow Location so tourists can find your establishment on the map.',
              ),
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
        return;
      }

      // Medium accuracy + short timeout — laptop GPS is approximate; Adjust pin fine-tunes.
      final pos = await Geolocator.getCurrentPosition(
        locationSettings: LocationSettings(
          accuracy: kIsWeb ? LocationAccuracy.medium : LocationAccuracy.high,
          timeLimit: const Duration(seconds: 8),
        ),
      );
      // Do not save yet — only persist when user taps Save pin here (avoids double writes / 429).
      onBusyChanged?.call(false);
      if (context.mounted) {
        await _openMapPreview(
          context,
          latitude: pos.latitude,
          longitude: pos.longitude,
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Could not get GPS quickly. Use Adjust pin and drag the map instead.',
            ),
            backgroundColor: Colors.red.shade700,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      onBusyChanged?.call(false);
    }
  }

  Future<void> _openMapPreview(
    BuildContext context, {
    required double latitude,
    required double longitude,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        final height = MediaQuery.sizeOf(ctx).height * 0.78;
        final accent = accentColor ?? AppTheme.brandOrange;
        return SizedBox(
          height: height,
          child: _AdjustPinSheet(
            initialLatitude: latitude,
            initialLongitude: longitude,
            accent: accent,
            onSave: (pin) {
              onChanged(pin);
              Navigator.pop(ctx);
            },
            onClose: () => Navigator.pop(ctx),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final accent = accentColor ?? AppTheme.brandOrange;
    final lat = latitude;
    final lng = longitude;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          _hasPin
              ? 'Pin: ${lat!.toStringAsFixed(5)}, ${lng!.toStringAsFixed(5)}'
              : required
                  ? 'Map pin required — tourists will see you on Explore.'
                  : 'No map pin yet.',
          style: TextStyle(
            fontSize: 13,
            height: 1.35,
            color: _hasPin ? const Color(0xFF334155) : Colors.red.shade700,
            fontWeight: FontWeight.w600,
          ),
        ),
        if (_hasPin) ...[
          const SizedBox(height: 10),
          GestureDetector(
            onTap: () => _openMapPreview(
              context,
              latitude: lat!,
              longitude: lng!,
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: SizedBox(
                height: 160,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    IgnorePointer(
                      child: _EstablishmentPinMap(
                        latitude: lat!,
                        longitude: lng!,
                        accent: accent,
                        interactive: false,
                      ),
                    ),
                    Positioned(
                      right: 8,
                      bottom: 8,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.95),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: accent.withValues(alpha: 0.35),
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.open_in_full_rounded,
                                size: 14, color: accent),
                            const SizedBox(width: 4),
                            Text(
                              'Adjust pin',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: accent,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: busy ? null : () => _capture(context),
                icon: busy
                    ? SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: accent,
                        ),
                      )
                    : Icon(Icons.my_location_rounded, color: accent),
                label: Text(busy ? 'Getting location…' : 'Get location'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: accent,
                  side: BorderSide(color: accent.withValues(alpha: 0.55)),
                  padding:
                      const EdgeInsets.symmetric(vertical: 14, horizontal: 12),
                ),
              ),
            ),
            if (_hasPin) ...[
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => _openMapPreview(
                    context,
                    latitude: lat!,
                    longitude: lng!,
                  ),
                  icon: Icon(Icons.tune_rounded, color: accent),
                  label: const Text('Adjust pin'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: accent,
                    side: BorderSide(color: accent.withValues(alpha: 0.55)),
                    padding: const EdgeInsets.symmetric(
                      vertical: 14,
                      horizontal: 12,
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ],
    );
  }
}

class _AdjustPinSheet extends StatefulWidget {
  const _AdjustPinSheet({
    required this.initialLatitude,
    required this.initialLongitude,
    required this.accent,
    required this.onSave,
    required this.onClose,
  });

  final double initialLatitude;
  final double initialLongitude;
  final Color accent;
  final ValueChanged<({double latitude, double longitude})> onSave;
  final VoidCallback onClose;

  @override
  State<_AdjustPinSheet> createState() => _AdjustPinSheetState();
}

class _AdjustPinSheetState extends State<_AdjustPinSheet> {
  late double _lat = widget.initialLatitude;
  late double _lng = widget.initialLongitude;
  final _mapController = MapController();

  @override
  void dispose() {
    _mapController.dispose();
    super.dispose();
  }

  void _onMapEvent(MapEvent event) {
    // Update coords when the user finishes panning / zooming.
    if (event is! MapEventMoveEnd &&
        event is! MapEventFlingAnimationEnd &&
        event is! MapEventDoubleTapZoomEnd) {
      return;
    }
    final c = _mapController.camera.center;
    setState(() {
      _lat = c.latitude;
      _lng = c.longitude;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 10),
        Center(
          child: Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.grey.shade300,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 8, 8),
          child: Row(
            children: [
              Icon(Icons.open_with_rounded, color: widget.accent),
              const SizedBox(width: 10),
              const Expanded(
                child: Text(
                  'Adjust map pin',
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF111827),
                  ),
                ),
              ),
              IconButton(
                onPressed: widget.onClose,
                icon: const Icon(Icons.close_rounded),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
          child: Text(
            'Drag the map so your entrance sits under the pin, then save.\n'
            'Pin: ${_lat.toStringAsFixed(5)}, ${_lng.toStringAsFixed(5)}',
            style: TextStyle(
              fontSize: 13,
              height: 1.35,
              color: Colors.grey.shade700,
            ),
          ),
        ),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  FlutterMap(
                    mapController: _mapController,
                    options: MapOptions(
                      initialCenter: LatLng(
                        widget.initialLatitude,
                        widget.initialLongitude,
                      ),
                      initialZoom: 17,
                      minZoom: 12,
                      maxZoom: 19,
                      onMapEvent: _onMapEvent,
                      interactionOptions: const InteractionOptions(
                        flags: InteractiveFlag.all & ~InteractiveFlag.rotate,
                      ),
                    ),
                    children: [
                      buildAtmosOsmTileLayer(),
                    ],
                  ),
                  // Fixed center pin — map moves underneath.
                  IgnorePointer(
                    child: Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 48,
                            height: 48,
                            decoration: BoxDecoration(
                              color: widget.accent,
                              shape: BoxShape.circle,
                              border:
                                  Border.all(color: Colors.white, width: 2.5),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.3),
                                  blurRadius: 8,
                                  offset: const Offset(0, 3),
                                ),
                              ],
                            ),
                            child: const Icon(
                              Icons.hotel_rounded,
                              color: Colors.white,
                              size: 24,
                            ),
                          ),
                          Container(
                            width: 3,
                            height: 10,
                            color: widget.accent,
                          ),
                        ],
                      ),
                    ),
                  ),
                  Positioned(
                    right: 10,
                    bottom: 10,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _MiniZoomBtn(
                          icon: Icons.add,
                          onTap: () {
                            final z = (_mapController.camera.zoom + 1)
                                .clamp(12.0, 19.0);
                            _mapController.move(
                              _mapController.camera.center,
                              z,
                            );
                          },
                        ),
                        const SizedBox(height: 6),
                        _MiniZoomBtn(
                          icon: Icons.remove,
                          onTap: () {
                            final z = (_mapController.camera.zoom - 1)
                                .clamp(12.0, 19.0);
                            _mapController.move(
                              _mapController.camera.center,
                              z,
                            );
                          },
                        ),
                        const SizedBox(height: 6),
                        _MiniZoomBtn(
                          icon: Icons.my_location,
                          onTap: () {
                            _mapController.move(
                              LatLng(
                                widget.initialLatitude,
                                widget.initialLongitude,
                              ),
                              17,
                            );
                            setState(() {
                              _lat = widget.initialLatitude;
                              _lng = widget.initialLongitude;
                            });
                          },
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: FilledButton.icon(
            onPressed: () => widget.onSave(
              (latitude: _lat, longitude: _lng),
            ),
            icon: const Icon(Icons.check_rounded),
            label: const Text('Save pin here'),
            style: FilledButton.styleFrom(
              backgroundColor: widget.accent,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
          ),
        ),
      ],
    );
  }
}

class _EstablishmentPinMap extends StatefulWidget {
  const _EstablishmentPinMap({
    required this.latitude,
    required this.longitude,
    required this.accent,
    this.interactive = true,
    this.showZoomControls = false,
  });

  final double latitude;
  final double longitude;
  final Color accent;
  final bool interactive;
  final bool showZoomControls;

  @override
  State<_EstablishmentPinMap> createState() => _EstablishmentPinMapState();
}

class _EstablishmentPinMapState extends State<_EstablishmentPinMap> {
  late final MapController _controller = MapController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final center = LatLng(widget.latitude, widget.longitude);
    return Stack(
      fit: StackFit.expand,
      children: [
        FlutterMap(
          mapController: _controller,
          options: MapOptions(
            initialCenter: center,
            initialZoom: 16.5,
            minZoom: 10,
            maxZoom: 19,
            interactionOptions: InteractionOptions(
              flags: widget.interactive
                  ? (InteractiveFlag.all & ~InteractiveFlag.rotate)
                  : InteractiveFlag.none,
            ),
          ),
          children: [
            buildAtmosOsmTileLayer(),
            MarkerLayer(
              markers: [
                Marker(
                  point: center,
                  width: 44,
                  height: 44,
                  child: Container(
                    decoration: BoxDecoration(
                      color: widget.accent,
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 2.5),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.28),
                          blurRadius: 6,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: const Icon(
                      Icons.hotel_rounded,
                      color: Colors.white,
                      size: 22,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
        if (widget.showZoomControls)
          Positioned(
            right: 10,
            bottom: 10,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _MiniZoomBtn(
                  icon: Icons.add,
                  onTap: () {
                    final z =
                        (_controller.camera.zoom + 1).clamp(10.0, 19.0);
                    _controller.move(_controller.camera.center, z);
                  },
                ),
                const SizedBox(height: 6),
                _MiniZoomBtn(
                  icon: Icons.remove,
                  onTap: () {
                    final z =
                        (_controller.camera.zoom - 1).clamp(10.0, 19.0);
                    _controller.move(_controller.camera.center, z);
                  },
                ),
                const SizedBox(height: 6),
                _MiniZoomBtn(
                  icon: Icons.my_location,
                  onTap: () => _controller.move(center, 16.5),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _MiniZoomBtn extends StatelessWidget {
  const _MiniZoomBtn({required this.icon, required this.onTap});

  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(8),
      elevation: 2,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: SizedBox(
          width: 36,
          height: 36,
          child: Icon(icon, size: 20, color: const Color(0xFF1F2937)),
        ),
      ),
    );
  }
}

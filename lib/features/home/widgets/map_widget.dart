import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:atmos_trs_system/config/app_theme.dart';
import 'package:atmos_trs_system/models/tourist_spot_firestore.dart';
import 'package:atmos_trs_system/screens/simple_image_vr_screen.dart';
import 'package:atmos_trs_system/screens/vr_webview_screen.dart';

/// Misamis Occidental map center and zoom (per requirements).
const double _kMapCenterLat = 8.3375;
const double _kMapCenterLng = 123.7071;
const double _kMapZoom = 9.0;

/// Bounds covering Misamis Occidental province only (southwest and northeast corners).
/// Camera target is restricted to this area so users cannot scroll outside the province.
final LatLngBounds _kMisamisOccidentalBounds = LatLngBounds(
  const LatLng(7.92, 123.38),
  const LatLng(8.72, 124.02),
);

/// OpenStreetMap focused on Misamis Occidental with custom markers.
/// On marker tap shows bottom modal: name, category, distance, rating, Launch VR Tour.
class MapWidget extends StatefulWidget {
  const MapWidget({
    super.key,
    required this.spots,
    this.onSpotTap,
  });

  final List<TouristSpotFirestore> spots;
  final ValueChanged<TouristSpotFirestore>? onSpotTap;

  @override
  State<MapWidget> createState() => _MapWidgetState();
}

class _MapWidgetState extends State<MapWidget> {
  final MapController _mapController = MapController();

  List<Marker> get _markers {
    return widget.spots.map((s) {
      return Marker(
        point: LatLng(s.latitude, s.longitude),
        width: 40,
        height: 40,
        child: GestureDetector(
          onTap: () => _onMarkerTap(s),
          child: Container(
            decoration: BoxDecoration(
              color: AppTheme.primary,
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white, width: 2),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.3),
                  blurRadius: 4,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: const Icon(
              Icons.place,
              color: Colors.white,
              size: 24,
            ),
          ),
        ),
      );
    }).toList();
  }

  void _onMarkerTap(TouristSpotFirestore spot) {
    widget.onSpotTap?.call(spot);
    _showSpotBottomSheet(spot);
  }

  void _showSpotBottomSheet(TouristSpotFirestore spot) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => _SpotModalSheet(
        spot: spot,
        onLaunchVrTour: () {
          Navigator.pop(context);
          final link = spot.vrLink?.trim();
          if (link != null && link.isNotEmpty) {
            openVrTour(context, url: link, title: spot.name);
            return;
          }
          final img = spot.image?.trim();
          if (img != null && img.isNotEmpty) {
            Navigator.of(context).push<void>(
              MaterialPageRoute<void>(
                builder: (_) =>
                    SimpleImageVrScreen(title: spot.name, imageUrl: img),
              ),
            );
            return;
          }
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('No VR tour is available for this destination yet.'),
            ),
          );
        },
      ),
    );
  }

  @override
  void dispose() {
    _mapController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: SizedBox(
        height: 260,
        width: double.infinity,
        child: Stack(
          children: [
            FlutterMap(
              mapController: _mapController,
              options: MapOptions(
                initialCenter: const LatLng(_kMapCenterLat, _kMapCenterLng),
                initialZoom: _kMapZoom,
                minZoom: 8,
                maxZoom: 17,
                cameraConstraint: CameraConstraint.contain(
                  bounds: _kMisamisOccidentalBounds,
                ),
                interactionOptions: const InteractionOptions(
                  flags: InteractiveFlag.all & ~InteractiveFlag.rotate,
                ),
              ),
              children: [
                TileLayer(
                  urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                  userAgentPackageName: 'com.atmos.trs',
                  maxZoom: 19,
                ),
                MarkerLayer(
                  markers: _markers,
                ),
              ],
            ),
            // Map attribution
            Positioned(
              bottom: 4,
              right: 8,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.8),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  '© OpenStreetMap',
                  style: TextStyle(
                    fontSize: 10,
                    color: Colors.grey.shade700,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SpotModalSheet extends StatelessWidget {
  const _SpotModalSheet({
    required this.spot,
    required this.onLaunchVrTour,
  });

  final TouristSpotFirestore spot;
  final VoidCallback onLaunchVrTour;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppTheme.cardBackground,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        border: Border.all(color: Colors.white.withOpacity(0.06)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: AppTheme.unselectedMuted.withOpacity(0.5),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            spot.name,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              _Chip(label: spot.category),
              const SizedBox(width: 8),
              Icon(Icons.straighten, size: 14, color: AppTheme.unselectedMuted),
              const SizedBox(width: 4),
              Text(
                '— km',
                style: TextStyle(color: AppTheme.unselectedMuted, fontSize: 13),
              ),
              const SizedBox(width: 16),
              Icon(Icons.star, size: 16, color: Colors.amber.shade400),
              const SizedBox(width: 4),
              Text(
                spot.rating > 0 ? spot.rating.toStringAsFixed(1) : '—',
                style: TextStyle(
                  color: Colors.amber.shade400,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          if (spot.vrLink?.trim().isNotEmpty == true ||
              (spot.image?.trim().isNotEmpty ?? false))
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: onLaunchVrTour,
                icon: const Icon(Icons.vrpano_rounded, size: 20),
                label: Text(
                  spot.vrLink?.trim().isNotEmpty == true
                      ? 'Launch VR tour'
                      : 'View VR preview',
                ),
                style: FilledButton.styleFrom(
                  backgroundColor: AppTheme.primary,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(24),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: AppTheme.primary.withOpacity(0.25),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.primary.withOpacity(0.5)),
      ),
      child: Text(
        label,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

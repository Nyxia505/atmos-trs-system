import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:atmos_trs_system/config/app_theme.dart';
import 'package:atmos_trs_system/data/misamis_occidental_municipalities.dart';
import 'package:atmos_trs_system/models/municipality.dart';
import 'package:atmos_trs_system/features/explore/explore_screen.dart' show TouristSpot, kMockSpots;
import 'package:atmos_trs_system/features/tourism/tourist_spot_detail_screen.dart';
import 'package:atmos_trs_system/services/user_activity_service.dart';

/// Screen showing map centered on a municipality and its tourist spots (image + details).
/// Opened from landing page destination cards or from map screens.
class MunicipalityMapAndSpotsScreen extends StatefulWidget {
  const MunicipalityMapAndSpotsScreen({
    super.key,
    required this.municipalityIdOrName,
  });

  /// Municipality id (e.g. 'oroquieta') or display name (e.g. 'Oroquieta City').
  final String municipalityIdOrName;

  @override
  State<MunicipalityMapAndSpotsScreen> createState() => _MunicipalityMapAndSpotsScreenState();
}

class _MunicipalityMapAndSpotsScreenState extends State<MunicipalityMapAndSpotsScreen> {
  GoogleMapController? _mapController;
  Municipality? _municipality;
  List<TouristSpot> _spots = [];
  bool _recordedRecentlyViewed = false;

  static const double _kMapZoom = 12.5;

  /// Optional hero image for recently viewed (aligned with Home featured assets where possible).
  static String? _previewImageForMunicipality(String id) {
    switch (id) {
      case 'oroquieta':
        return 'assets/images/City PLaza Oroquieta.png';
      case 'sapangdalaga':
        return 'assets/images/Sapang Dalaga.png';
      default:
        return null;
    }
  }

  Widget _buildMapControl(IconData icon, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(10),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.15),
              blurRadius: 4,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Icon(icon, color: AppTheme.primary, size: 20),
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    _resolveMunicipality();
  }

  @override
  void dispose() {
    _mapController = null;
    super.dispose();
  }

  Set<Marker> _buildMarkers(Municipality m) {
    final Set<Marker> markers = {};
    markers.add(
      Marker(
        markerId: const MarkerId('municipality_center'),
        position: LatLng(m.lat, m.lng),
        icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueOrange),
      ),
    );
    const String plazaSpotId = 'oro-4'; // Oroquieta City Plaza — highlight on map
    for (final s in _spots) {
      if (s.latitude == 0 && s.longitude == 0) continue;
      final isPlazaHighlight = s.id == plazaSpotId;
      markers.add(
        Marker(
          markerId: MarkerId(s.id),
          position: LatLng(s.latitude, s.longitude),
          icon: BitmapDescriptor.defaultMarkerWithHue(
            isPlazaHighlight ? BitmapDescriptor.hueViolet : BitmapDescriptor.hueOrange,
          ),
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => TouristSpotDetailScreen(spot: s),
              ),
            );
          },
        ),
      );
    }
    return markers;
  }

  void _resolveMunicipality() {
    final list = getMisamisOccidentalMunicipalities();
    final idOrName = widget.municipalityIdOrName.trim().toLowerCase();
    Municipality? m;
    for (final x in list) {
      if (x.id.toLowerCase() == idOrName || x.name.toLowerCase() == idOrName) {
        m = x;
        break;
      }
      if (x.name.toLowerCase().contains(idOrName) || idOrName.contains(x.name.toLowerCase().split(' ').first)) {
        m = x;
        break;
      }
    }
    if (m == null && list.isNotEmpty) {
      final nameParts = widget.municipalityIdOrName.trim();
      for (final x in list) {
        if (x.name.toLowerCase().contains(nameParts.toLowerCase()) ||
            nameParts.toLowerCase().contains(x.name.toLowerCase().split(' ').first)) {
          m = x;
          break;
        }
      }
    }
    if (!mounted) return;
    setState(() {
      _municipality = m;
      if (m != null) {
        final all = List<TouristSpot>.from(kMockSpots);
        _spots = all.where((s) => _spotBelongsToMunicipality(s, m!)).toList();
      } else {
        _spots = [];
      }
    });
    if (m != null && !_recordedRecentlyViewed) {
      _recordedRecentlyViewed = true;
      UserActivityService.recordRecentlyViewed(
        spotId: m.id,
        spotName: m.name,
        category: m.isCity ? 'City' : 'Municipality',
        imageUrl: _previewImageForMunicipality(m.id),
      );
    }
  }

  @override
  void didUpdateWidget(covariant MunicipalityMapAndSpotsScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.municipalityIdOrName != widget.municipalityIdOrName) {
      _recordedRecentlyViewed = false;
      _resolveMunicipality();
    }
  }

  bool _spotBelongsToMunicipality(TouristSpot spot, Municipality m) {
    final city = spot.city.trim().toLowerCase();
    final name = m.name.toLowerCase();
    if (city == name) return true;
    if (name.startsWith(city) || city.startsWith(name.split(' ').first)) return true;
    if (name.contains(city) || city.contains(name.split(' ').first)) return true;
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final m = _municipality;
    if (m == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Municipality')),
        body: const Center(child: Text('Municipality not found')),
      );
    }

    return Scaffold(
      backgroundColor: AppTheme.scaffoldBackground,
      appBar: AppBar(
        title: Text(m.name),
        backgroundColor: AppTheme.primary,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: Column(
        children: [
          SizedBox(
            height: 220,
            child: ClipRRect(
              borderRadius: const BorderRadius.only(
                bottomLeft: Radius.circular(12),
                bottomRight: Radius.circular(12),
              ),
              child: Stack(
                children: [
                  GoogleMap(
                    initialCameraPosition: CameraPosition(
                      target: LatLng(m.lat, m.lng),
                      zoom: _kMapZoom,
                    ),
                    minMaxZoomPreference: const MinMaxZoomPreference(9, 18),
                    markers: _buildMarkers(m),
                    onMapCreated: (GoogleMapController controller) {
                      _mapController = controller;
                    },
                    mapType: MapType.normal,
                  ),
                  Positioned(
                    right: 10,
                    bottom: 10,
                    child: Column(
                      children: [
                        _buildMapControl(Icons.add, () {
                          _mapController?.animateCamera(CameraUpdate.zoomIn());
                        }),
                        const SizedBox(height: 8),
                        _buildMapControl(Icons.remove, () {
                          _mapController?.animateCamera(CameraUpdate.zoomOut());
                        }),
                        const SizedBox(height: 8),
                        _buildMapControl(Icons.my_location, () {
                          _mapController?.animateCamera(
                            CameraUpdate.newCameraPosition(
                              CameraPosition(
                                target: LatLng(m.lat, m.lng),
                                zoom: _kMapZoom,
                              ),
                            ),
                          );
                        }),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                const Text(
                  'Tourist spots',
                  style: TextStyle(
                    color: Color(0xFF111827),
                    fontWeight: FontWeight.w700,
                    fontSize: 18,
                  ),
                ),
                const SizedBox(height: 12),
                if (_spots.isEmpty)
                  Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(
                      'No tourist spots listed yet for ${m.name}.',
                      style: TextStyle(color: AppTheme.unselectedMuted, fontSize: 14),
                    ),
                  )
                else
                  ..._spots.map(
                    (spot) => _SpotCard(
                      spot: spot,
                      onOpenDetails: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => TouristSpotDetailScreen(spot: spot),
                          ),
                        );
                      },
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SpotCard extends StatelessWidget {
  const _SpotCard({
    required this.spot,
    this.onOpenDetails,
  });

  final TouristSpot spot;
  final VoidCallback? onOpenDetails;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      color: AppTheme.cardBackground,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: InkWell(
        onTap: onOpenDetails,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: spot.imageUrl.startsWith('http')
                    ? Image.network(
                        spot.imageUrl,
                        width: 72,
                        height: 72,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => _placeholder(72),
                      )
                    : Image.asset(
                        spot.imageUrl,
                        width: 72,
                        height: 72,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => _placeholder(72),
                      ),
              ),
              const SizedBox(width: 16),
              Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                    Text(
                      spot.name,
                      style: const TextStyle(
                        color: Color(0xFF111827),
                        fontWeight: FontWeight.w600,
                        fontSize: 15,
                      ),
                    ),
                    Text(
                      spot.category,
                      style: TextStyle(color: AppTheme.primary.withOpacity(0.9), fontSize: 12),
                    ),
                    if (spot.description.isNotEmpty)
                      Text(
                        spot.description,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: AppTheme.unselectedMuted, fontSize: 13),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _placeholder(double size) {
    return Container(
      width: size,
      height: size,
      color: AppTheme.unselectedMuted.withOpacity(0.2),
      child: Icon(Icons.place, color: AppTheme.unselectedMuted, size: 32),
    );
  }
}

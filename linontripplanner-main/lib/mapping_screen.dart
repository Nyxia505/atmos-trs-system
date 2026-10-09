import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart' as ll;

import 'data.dart';
import 'municipality_coordinates.dart' show misamisOccidentalCenter;
import 'services/tourism_session.dart';
import 'spot_detail_screen.dart';
import 'widgets/bus_terminal_map_markers.dart';
import 'widgets/google_map_pin_icons.dart';
import 'widgets/osm_map_tiles.dart';

class MappingScreen extends StatefulWidget {
  const MappingScreen({super.key});

  @override
  State<MappingScreen> createState() => _MappingScreenState();
}

class _MappingScreenState extends State<MappingScreen> {
  final MapController _controller = MapController();
  List<Marker> _markers = const [];
  bool _loadingMarkers = true;

  static final ll.LatLng _center = ll.LatLng(
    misamisOccidentalCenter.latitude,
    misamisOccidentalCenter.longitude,
  );

  @override
  void initState() {
    super.initState();
    tourismCatalogRevision.addListener(_onCatalogRevision);
    _loadMarkers();
  }

  @override
  void dispose() {
    tourismCatalogRevision.removeListener(_onCatalogRevision);
    super.dispose();
  }

  void _onCatalogRevision() {
    if (mounted) _loadMarkers();
  }

  Future<void> _loadMarkers() async {
    setState(() => _loadingMarkers = true);
    await bootstrapAppFirestoreOnce();
    if (!mounted) return;

    final markers = <Marker>[
      ...buildOsmBusTerminalMarkers(sortedMunicipalities),
    ];

    for (final s in allSpots) {
      final lat = s.latitude;
      final lng = s.longitude;
      if (lat == null || lng == null) continue;
      final spot = s;
      markers.add(
        Marker(
          point: ll.LatLng(lat, lng),
          width: 40,
          height: 40,
          child: GestureDetector(
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => SpotDetailScreen(spot: spot)),
              );
            },
            child: Tooltip(
              message: spot.location.isEmpty
                  ? spot.name
                  : '${spot.name}\n${spot.location}',
              child: Icon(
                Icons.location_on,
                color: GoogleMapPinIcons.touristSpotColor,
                size: 36,
                shadows: const [
                  Shadow(blurRadius: 4, color: Colors.black38),
                ],
              ),
            ),
          ),
        ),
      );
    }

    if (!mounted) return;
    setState(() {
      _markers = markers;
      _loadingMarkers = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        title: const Text(
          'Map & Routes',
          style: TextStyle(
            color: AppColors.textDark,
            fontWeight: FontWeight.bold,
            fontSize: 18,
          ),
        ),
      ),
      body: Stack(
        children: [
          FlutterMap(
            mapController: _controller,
            options: MapOptions(
              initialCenter: _center,
              initialZoom: 10.5,
              minZoom: 8.5,
              maxZoom: 18,
              backgroundColor: const Color(0xFFE8EEF2),
            ),
            children: [
              osmBasemapTileLayer(),
              MarkerLayer(markers: _markers),
              osmMapAttribution(),
            ],
          ),
          Positioned(
            top: 12,
            right: 12,
            child: buildBusTerminalMapLegend(),
          ),
          if (_loadingMarkers)
            const Center(
              child: CircularProgressIndicator(color: AppColors.primary),
            ),
          if (!_loadingMarkers && _markers.isEmpty)
            Align(
              alignment: Alignment.bottomCenter,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Container(
                  constraints: const BoxConstraints(maxWidth: 720),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.08),
                        blurRadius: 10,
                        offset: const Offset(0, 3),
                      ),
                    ],
                  ),
                  child: const Text(
                    'No mapped spots yet. Add latitude/longitude to your Firestore `tourist_spots` documents to show markers.',
                    style: TextStyle(
                      color: AppColors.textGrey,
                      fontSize: 13,
                      height: 1.3,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

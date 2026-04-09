import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:atmos_trs_system/models/tourist_spot_firestore.dart';
import 'package:atmos_trs_system/services/tourist_spots_repository.dart';
import 'package:atmos_trs_system/screens/municipality_map_and_spots_screen.dart';
import 'package:atmos_trs_system/features/explore/explore_screen.dart'
    show TouristSpot, kMockSpots, kTextMuted;
import 'package:atmos_trs_system/services/user_activity_service.dart'
    as activity;
import 'package:intl/intl.dart';

/// Misamis Occidental map center coordinates (centered on the province)
const double _kMapCenterLat = 8.3377;
const double _kMapCenterLng = 123.7072;
const double _kMapZoom = 9.5;

// Bounds covering Misamis Occidental province (used to constrain the map).
final LatLngBounds _kMisamisOccidentalBounds = LatLngBounds(
  southwest: const LatLng(7.95, 123.45),
  northeast: const LatLng(8.70, 124.00),
);

const Color _kPrimaryOrange = Color(0xFFF97316);
const Color _kDarkText = Color(0xFF1F2937);

/// 17 municipalities/cities in Misamis Occidental — used for map pins.
final List<TouristSpotFirestore> _sampleSpots = [
  TouristSpotFirestore(
    id: 'oroquieta_city',
    name: 'Oroquieta City',
    category: 'Historical',
    latitude: 8.4854,
    longitude: 123.8058,
    rating: 4.8,
    image: 'assets/images/City PLaza Oroquieta.png',
    vrLink: 'https://apricot-danica-42.tiiny.site/',
  ),
  TouristSpotFirestore(id: 'ozamis_city', name: 'Ozamis City', category: 'Historical', latitude: 8.1481, longitude: 123.8444, rating: 4.7, image: 'https://images.unsplash.com/photo-1449824913935-59a10b8d2000?w=400', vrLink: ''),
  TouristSpotFirestore(id: 'tangub_city', name: 'Tangub City', category: 'Historical', latitude: 8.0656, longitude: 123.7547, rating: 4.6, image: 'https://images.unsplash.com/photo-1480714378408-67cf0d13bc1b?w=400', vrLink: ''),
  TouristSpotFirestore(id: 'aloran', name: 'Aloran', category: 'Beach', latitude: 8.4167, longitude: 123.8333, rating: 4.5, image: 'https://images.unsplash.com/photo-1507525428034-b723cf961d3e?w=400', vrLink: ''),
  TouristSpotFirestore(id: 'baliangao', name: 'Baliangao', category: 'Beach', latitude: 8.6167, longitude: 123.5667, rating: 4.6, image: 'https://images.unsplash.com/photo-1519046904884-53103b34b206?w=400', vrLink: ''),
  TouristSpotFirestore(id: 'bonifacio', name: 'Bonifacio', category: 'Mountain', latitude: 8.0667, longitude: 123.6167, rating: 4.4, image: 'https://images.unsplash.com/photo-1464822759023-fed622ff2c3b?w=400', vrLink: ''),
  TouristSpotFirestore(id: 'calamba', name: 'Calamba', category: 'Mountain', latitude: 8.1667, longitude: 123.7167, rating: 4.3, image: 'assets/images/CALAMBA.jpg', vrLink: ''),
  TouristSpotFirestore(id: 'clarin', name: 'Clarin', category: 'Beach', latitude: 8.2167, longitude: 123.8500, rating: 4.5, image: 'https://images.unsplash.com/photo-1471922694854-ff1b63b20054?w=400', vrLink: ''),
  TouristSpotFirestore(id: 'concepcion', name: 'Concepcion', category: 'Falls', latitude: 8.1500, longitude: 123.5833, rating: 4.4, image: 'assets/images/conception.png', vrLink: ''),
  TouristSpotFirestore(id: 'don_victoriano', name: 'Don Victoriano Chiongbian', category: 'Mountain', latitude: 7.9167, longitude: 123.4667, rating: 4.5, image: 'https://images.unsplash.com/photo-1454496522488-7a8e488e8606?w=400', vrLink: ''),
  TouristSpotFirestore(id: 'jimenez', name: 'Jimenez', category: 'Beach', latitude: 8.3333, longitude: 123.8333, rating: 4.6, image: 'https://images.unsplash.com/photo-1520942702018-0862200e6873?w=400', vrLink: ''),
  TouristSpotFirestore(id: 'lopez_jaena', name: 'Lopez Jaena', category: 'Beach', latitude: 8.5500, longitude: 123.7667, rating: 4.5, image: 'https://images.unsplash.com/photo-1473116763249-2faaef81ccda?w=400', vrLink: ''),
  TouristSpotFirestore(id: 'panaon', name: 'Panaon', category: 'Beach', latitude: 8.6833, longitude: 123.7167, rating: 4.7, image: 'https://images.unsplash.com/photo-1510414842594-a61c69b5ae57?w=400', vrLink: ''),
  TouristSpotFirestore(id: 'plaridel', name: 'Plaridel', category: 'Beach', latitude: 8.6167, longitude: 123.7000, rating: 4.4, image: 'assets/images/PLARIDEL.jpg', vrLink: ''),
  TouristSpotFirestore(
    id: 'sapang_dalaga',
    name: 'Sapang Dalaga',
    category: 'Falls',
    latitude: 8.5333,
    longitude: 123.5500,
    rating: 4.6,
    image: 'assets/images/Sapang Dalaga.png',
    vrLink: '',
  ),
  TouristSpotFirestore(id: 'sinacaban', name: 'Sinacaban', category: 'Resorts', latitude: 8.2833, longitude: 123.8500, rating: 4.5, image: 'assets/images/sinacaban.jpg', vrLink: ''),
  TouristSpotFirestore(id: 'tudela', name: 'Tudela', category: 'Beach', latitude: 8.5333, longitude: 123.8500, rating: 4.5, image: 'assets/images/Tudela Village.webp', vrLink: ''),
];

/// Explore tab screen: full Explore Map (Misamis Occidental with 17 municipality pins).
/// Moved from Home screen; same behavior, styling, markers, zoom controls, and Full Map modal.
class ExploreScreen extends StatefulWidget {
  const ExploreScreen({super.key});

  @override
  State<ExploreScreen> createState() => _ExploreScreenState();
}

class _ExploreScreenState extends State<ExploreScreen> {
  GoogleMapController? _googleMapController;
  List<TouristSpotFirestore> _municipalitySpots = _sampleSpots;

  final TextEditingController _searchController = TextEditingController();

  // Sections under the map
  bool _isLoadingSections = true;
  List<TouristSpot> _recommendedSpots = [];
  List<activity.VisitRecord> _recentVisits = [];

  @override
  void initState() {
    super.initState();
    _loadExploreSections();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _onSearchSubmitted(String query) {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) {
      _googleMapController?.animateCamera(
        CameraUpdate.newCameraPosition(
          const CameraPosition(
            target: LatLng(_kMapCenterLat, _kMapCenterLng),
            zoom: _kMapZoom,
          ),
        ),
      );
      return;
    }

    final spots =
        _municipalitySpots.isNotEmpty ? _municipalitySpots : _sampleSpots;

    TouristSpotFirestore? match;
    for (final s in spots) {
      final name = s.name.toLowerCase();
      final muni = s.municipality.toLowerCase();
      if (name.contains(q) || muni.contains(q)) {
        match = s;
        break;
      }
    }

    if (match == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('No place found for "$query".'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    _googleMapController?.animateCamera(
      CameraUpdate.newCameraPosition(
        CameraPosition(
          target: LatLng(match.latitude, match.longitude),
          zoom: 13.0,
        ),
      ),
    );
  }

  Future<void> _loadExploreSections() async {
    // Load visit history
    final visits = await activity.UserActivityService.getVisitedSpots();
    final recent = visits.take(3).toList();

    // Determine recommended spots
    List<TouristSpot> recommended;
    if (visits.isNotEmpty) {
      // Count categories from visit history
      final Map<String, int> counts = {};
      for (final v in visits) {
        final key = v.category.toLowerCase();
        if (key.isEmpty) continue;
        counts[key] = (counts[key] ?? 0) + 1;
      }
      final topCategories = counts.entries.toList()
        ..sort((a, b) => b.value.compareTo(a.value));
      final Set<String> top =
          topCategories.take(2).map((e) => e.key).toSet();

      final sortedByRating = List<TouristSpot>.from(kMockSpots)
        ..sort((a, b) => b.rating.compareTo(a.rating));
      recommended = sortedByRating
          .where((s) => top.contains(s.category.toLowerCase()))
          .toList();
      if (recommended.isEmpty) {
        recommended = sortedByRating;
      }
    } else {
      // No history yet: show top‑rated spots
      recommended = kMockSpots
          .where((s) => s.rating >= 4.5)
          .toList()
        ..sort((a, b) => b.rating.compareTo(a.rating));
    }

    // Limit to 8 cards
    recommended = recommended.take(8).toList();

    if (!mounted) return;
    setState(() {
      _recommendedSpots = recommended;
      _recentVisits = recent;
      _isLoadingSections = false;
    });
  }

  List<TouristSpotFirestore> _mergeSampleWithFirestore(List<TouristSpotFirestore> firestoreSpots) {
    if (firestoreSpots.isEmpty) return _sampleSpots;
    final byId = {for (final s in firestoreSpots) s.id: s};
    return _sampleSpots.map((sample) {
      final remote = byId[sample.id];
      if (remote == null) return sample;
      return TouristSpotFirestore(
        id: sample.id,
        name: remote.name.isNotEmpty ? remote.name : sample.name,
        category: remote.category.isNotEmpty ? remote.category : sample.category,
        latitude: sample.latitude,
        longitude: sample.longitude,
        image: remote.image ?? sample.image,
        rating: remote.rating != 0.0 ? remote.rating : sample.rating,
        description: remote.description.isNotEmpty ? remote.description : sample.description,
        vrLink: (remote.vrLink != null && remote.vrLink!.trim().isNotEmpty)
            ? remote.vrLink
            : sample.vrLink,
        municipality: remote.municipality.isNotEmpty ? remote.municipality : sample.municipality,
      );
    }).toList();
  }

  Set<Marker> _buildMarkers(List<TouristSpotFirestore> spots) {
    return spots.map((s) {
      return Marker(
        markerId: MarkerId(s.id),
        position: LatLng(s.latitude, s.longitude),
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => MunicipalityMapAndSpotsScreen(
                municipalityIdOrName: s.name,
              ),
            ),
          );
        },
        icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueOrange),
      );
    }).toSet();
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
        child: Icon(icon, color: _kDarkText, size: 20),
      ),
    );
  }

  void _showFullMap() {
    final spots = _municipalitySpots.isNotEmpty ? _municipalitySpots : _sampleSpots;
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        final height = MediaQuery.of(context).size.height * 0.9;
        GoogleMapController? fullMapController;
        return Container(
          height: height,
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: Column(
            children: [
              const SizedBox(height: 8),
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 12),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'Misamis Occidental Map',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: _kDarkText),
                    ),
                    Text('${spots.length} spots', style: TextStyle(fontSize: 13, color: Colors.grey.shade600)),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(20),
                    child: Stack(
                      children: [
                        GoogleMap(
                          initialCameraPosition: const CameraPosition(
                            target: LatLng(_kMapCenterLat, _kMapCenterLng),
                            zoom: _kMapZoom,
                          ),
                          cameraTargetBounds: CameraTargetBounds(
                            _kMisamisOccidentalBounds,
                          ),
                          minMaxZoomPreference:
                              const MinMaxZoomPreference(9, 17),
                          onMapCreated: (controller) {
                            fullMapController = controller;
                          },
                          markers: _buildMarkers(spots),
                          myLocationButtonEnabled: false,
                          zoomControlsEnabled: false,
                        ),
                        Positioned(
                          bottom: 24,
                          right: 12,
                          child: Column(
                            children: [
                              _buildMapControl(Icons.add, () {
                                fullMapController
                                    ?.animateCamera(CameraUpdate.zoomIn());
                              }),
                              const SizedBox(height: 8),
                              _buildMapControl(Icons.remove, () {
                                fullMapController
                                    ?.animateCamera(CameraUpdate.zoomOut());
                              }),
                              const SizedBox(height: 8),
                              _buildMapControl(Icons.my_location, () {
                                fullMapController?.animateCamera(
                                  CameraUpdate.newCameraPosition(
                                    const CameraPosition(
                                      target: LatLng(
                                          _kMapCenterLat, _kMapCenterLng),
                                      zoom: _kMapZoom,
                                    ),
                                  ),
                                );
                              }),
                            ],
                          ),
                        ),
                        // Google Maps branding & attribution are handled by the SDK.
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      body: SafeArea(
        child: CustomScrollView(
          slivers: [
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 12),
                    Container(
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(24),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.04),
                            blurRadius: 12,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: TextField(
                        controller: _searchController,
                        textInputAction: TextInputAction.search,
                        onSubmitted: _onSearchSubmitted,
                        style: const TextStyle(
                          fontSize: 14,
                          color: _kDarkText,
                        ),
                        decoration: InputDecoration(
                          hintText: 'Search municipality or city',
                          hintStyle: const TextStyle(
                            color: kTextMuted,
                            fontSize: 14,
                          ),
                          prefixIcon: const Icon(
                            Icons.search_rounded,
                            color: kTextMuted,
                          ),
                          suffixIcon: _searchController.text.isNotEmpty
                              ? IconButton(
                                  icon: const Icon(
                                    Icons.close_rounded,
                                    color: kTextMuted,
                                  ),
                                  onPressed: () {
                                    _searchController.clear();
                                    _onSearchSubmitted('');
                                  },
                                )
                              : null,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(24),
                            borderSide: BorderSide.none,
                          ),
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 0,
                            vertical: 12,
                          ),
                          filled: true,
                          fillColor: Colors.white,
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'Explore Map',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            color: _kDarkText,
                          ),
                        ),
                        TextButton.icon(
                          onPressed: _showFullMap,
                          icon: const Icon(Icons.fullscreen, size: 18),
                          label: const Text('Full Map'),
                          style: TextButton.styleFrom(
                            foregroundColor: _kPrimaryOrange,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      height: 260,
                      child: StreamBuilder<List<TouristSpotFirestore>>(
                        stream: TouristSpotsRepository.streamTouristSpots(),
                        builder: (context, snapshot) {
                          final firestoreSpots = snapshot.data ?? [];
                          final baseSpots = firestoreSpots.isEmpty
                              ? _sampleSpots
                              : _mergeSampleWithFirestore(firestoreSpots);
                          _municipalitySpots = baseSpots;
                          final visibleCount = baseSpots.length;

                          return ClipRRect(
                            borderRadius: BorderRadius.circular(20),
                            child: Stack(
                              children: [
                                GoogleMap(
                                  initialCameraPosition: const CameraPosition(
                                    target: LatLng(
                                        _kMapCenterLat, _kMapCenterLng),
                                    zoom: _kMapZoom,
                                  ),
                          cameraTargetBounds: CameraTargetBounds(
                            _kMisamisOccidentalBounds,
                          ),
                                  minMaxZoomPreference:
                                      const MinMaxZoomPreference(9, 17),
                                  onMapCreated: (controller) {
                                    _googleMapController = controller;
                                  },
                                  markers:
                                      _buildMarkers(_municipalitySpots),
                                  myLocationButtonEnabled: false,
                                  zoomControlsEnabled: false,
                                ),
                                Positioned(
                                  top: 12,
                                  left: 12,
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 12, vertical: 8),
                                    decoration: BoxDecoration(
                                      color: Colors.white,
                                      borderRadius: BorderRadius.circular(12),
                                      boxShadow: [
                                        BoxShadow(
                                          color: Colors.black.withOpacity(0.1),
                                          blurRadius: 8,
                                        ),
                                      ],
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        const Icon(
                                          Icons.location_on,
                                          color: _kPrimaryOrange,
                                          size: 16,
                                        ),
                                        const SizedBox(width: 6),
                                        Text(
                                          '$visibleCount spots',
                                          style: const TextStyle(
                                            fontWeight: FontWeight.w600,
                                            fontSize: 13,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                                Positioned(
                                  bottom: 40,
                                  right: 10,
                                  child: Column(
                                    children: [
                                      _buildMapControl(Icons.add, () {
                                        _googleMapController?.animateCamera(
                                          CameraUpdate.zoomIn(),
                                        );
                                      }),
                                      const SizedBox(height: 8),
                                      _buildMapControl(Icons.remove, () {
                                        _googleMapController?.animateCamera(
                                          CameraUpdate.zoomOut(),
                                        );
                                      }),
                                      const SizedBox(height: 8),
                                      _buildMapControl(Icons.my_location, () {
                                        _googleMapController?.animateCamera(
                                          CameraUpdate.newCameraPosition(
                                            const CameraPosition(
                                              target: LatLng(_kMapCenterLat,
                                                  _kMapCenterLng),
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
                          );
                        },
                      ),
                    ),
                    const SizedBox(height: 24),
                  ],
                ),
              ),
            ),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: _buildRecommendedSection(),
              ),
            ),
            SliverToBoxAdapter(
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
                child: _buildRecentVisitsSection(),
              ),
            ),
            const SliverToBoxAdapter(
              child: SizedBox(height: 32),
            ),
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Sections under the map
  // ---------------------------------------------------------------------------

  Widget _buildSectionTitle(String title) {
    return Text(
      title,
      style: const TextStyle(
        color: _kDarkText,
        fontSize: 18,
        fontWeight: FontWeight.w700,
      ),
    );
  }

  Widget _buildRecommendedSection() {
    if (_isLoadingSections) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.symmetric(vertical: 16),
          child: CircularProgressIndicator(color: _kPrimaryOrange),
        ),
      );
    }
    if (_recommendedSpots.isEmpty) {
      return const SizedBox.shrink();
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionTitle('Recommended for You'),
        const SizedBox(height: 8),
        SizedBox(
          height: 200,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: _recommendedSpots.length,
            separatorBuilder: (_, __) => const SizedBox(width: 12),
            itemBuilder: (context, index) {
              final spot = _recommendedSpots[index];
              return _buildHorizontalSpotCard(spot);
            },
          ),
        ),
      ],
    );
  }

  Widget _buildHorizontalSpotCard(TouristSpot spot) {
    return Container(
      width: 220,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.06),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              height: 100,
              width: double.infinity,
              child: _buildSpotImage(spot.imageUrl),
            ),
            Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: _kPrimaryOrange.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      spot.category,
                      style: const TextStyle(
                        color: _kPrimaryOrange,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    spot.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: _kDarkText,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      const Icon(Icons.star,
                          size: 14, color: Colors.amber),
                      const SizedBox(width: 4),
                      Text(
                        spot.rating.toStringAsFixed(1),
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRecentVisitsSection() {
    if (_isLoadingSections) {
      return const SizedBox.shrink();
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            _buildSectionTitle('My Recent Visits'),
            if (_recentVisits.isNotEmpty)
              TextButton(
                onPressed: () {
                  // Placeholder: could navigate to full history screen.
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: const Text(
                          'Full visits history is available in your Profile.'),
                      behavior: SnackBarBehavior.floating,
                      backgroundColor: _kPrimaryOrange,
                    ),
                  );
                },
                child: const Text(
                  'View all',
                  style: TextStyle(
                    color: _kPrimaryOrange,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 8),
        if (_recentVisits.isEmpty)
          Text(
            'You haven\'t checked in to any destinations yet. Start exploring Misamis Occidental!',
            style: TextStyle(
              color: kTextMuted,
              fontSize: 13,
            ),
          )
        else
          Column(
            children: _recentVisits
                .map((v) => _buildRecentVisitTile(v))
                .toList(),
          ),
      ],
    );
  }

  Widget _buildRecentVisitTile(activity.VisitRecord visit) {
    final formatter = DateFormat('MMM d, yyyy');
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: _kPrimaryOrange.withOpacity(0.12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(
              Icons.place_rounded,
              color: _kPrimaryOrange,
              size: 22,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  visit.spotName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: _kDarkText,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '${visit.category} • ${formatter.format(visit.visitedAt)}',
                  style: TextStyle(
                    color: kTextMuted,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------------

  Widget _buildSpotImage(String imageUrl) {
    if (imageUrl.isEmpty) {
      return Container(
        color: Colors.grey.shade200,
        child: const Icon(Icons.place, color: Colors.grey),
      );
    }
    if (imageUrl.startsWith('assets/')) {
      return Image.asset(
        imageUrl,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => Container(
          color: Colors.grey.shade200,
          child: const Icon(Icons.place, color: Colors.grey),
        ),
      );
    }
    return Image.network(
      imageUrl,
      fit: BoxFit.cover,
      errorBuilder: (_, __, ___) => Container(
        color: Colors.grey.shade200,
        child: const Icon(Icons.place, color: Colors.grey),
      ),
    );
  }

}

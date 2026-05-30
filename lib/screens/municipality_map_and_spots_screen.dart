import 'package:flutter/material.dart';
import 'package:atmos_trs_system/config/app_theme.dart';
import 'package:atmos_trs_system/data/misamis_occidental_municipalities.dart';
import 'package:atmos_trs_system/data/tourist_spots_by_municipality.dart';
import 'package:atmos_trs_system/models/municipality.dart';
import 'package:atmos_trs_system/models/tourist_spot_firestore.dart';
import 'package:atmos_trs_system/features/explore/explore_data.dart' show TouristSpot;
import 'package:atmos_trs_system/features/tourism/tourist_spot_detail_screen.dart';
import 'package:atmos_trs_system/services/user_activity_service.dart';
import 'package:atmos_trs_system/widgets/misamis_occidental_explore_map.dart';
import 'package:atmos_trs_system/widgets/tourist_spot_thumbnail.dart';

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
  State<MunicipalityMapAndSpotsScreen> createState() =>
      _MunicipalityMapAndSpotsScreenState();
}

class _MunicipalityMapAndSpotsScreenState extends State<MunicipalityMapAndSpotsScreen> {
  Municipality? _municipality;
  List<TouristSpot> _spots = [];
  bool _recordedRecentlyViewed = false;

  static const double _kMapZoom = 13.5;

  static String? _previewImageForMunicipality(String id) {
    switch (id) {
      case 'oroquieta':
        return 'assets/images/oroquieta City plaza.jpeg';
      case 'ozamiz':
        return 'assets/images/ozamis city.webp';
      case 'tangub':
        return 'assets/images/Asenso Global Garden 1.png';
      case 'baliangao':
        return 'assets/images/Baliangao - Cabgan Island.jpg';
      case 'calamba':
        return 'assets/images/CALAMBA.jpg';
      case 'clarin':
        return 'assets/images/clarin.jpg';
      case 'concepcion':
        return 'assets/images/conception.png';
      case 'dvc':
        return 'assets/images/Piduan Falls Donvic.jpg';
      case 'jimenez':
        return 'assets/images/Jimenez - St. John the Baptist Church.jpg';
      case 'panaon':
        return 'assets/images/Panaon.webp';
      case 'plaridel':
        return 'assets/images/PLARIDEL.jpg';
      case 'sapangdalaga':
        return 'assets/images/Sapang Dalaga.png';
      case 'sinacaban':
        return 'assets/images/AMORAP.jpg';
      case 'tudela':
        return 'assets/images/Tudela Village.webp';
      default:
        return null;
    }
  }

  List<TouristSpotFirestore> _mapSpots(Municipality m) {
    return _spots
        .where((s) => s.latitude != 0 || s.longitude != 0)
        .map(
          (s) => TouristSpotFirestore(
            id: s.id,
            name: s.name,
            category: s.category,
            latitude: s.latitude,
            longitude: s.longitude,
            image: s.imageUrl,
            rating: s.rating,
            description: s.description,
            vrLink: s.vrLink,
            municipality: m.name,
            municipalityId: m.id,
          ),
        )
        .toList();
  }

  TouristSpot? _spotForFirestore(TouristSpotFirestore fs) {
    for (final s in _spots) {
      if (s.id == fs.id) return s;
    }
    return null;
  }

  @override
  void initState() {
    super.initState();
    _resolveMunicipality();
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
      if (x.name.toLowerCase().contains(idOrName) ||
          idOrName.contains(x.name.toLowerCase().split(' ').first)) {
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
      _spots = m != null ? getTouristSpotsForMunicipality(m) : [];
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

  @override
  Widget build(BuildContext context) {
    final m = _municipality;
    if (m == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Municipality')),
        body: const Center(child: Text('Municipality not found')),
      );
    }

    final mapSpots = _mapSpots(m);

    return Scaffold(
      backgroundColor: AppTheme.scaffoldBackground,
      appBar: AppBar(
        title: Text(m.name),
        backgroundColor: AppTheme.brandOrange,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: Column(
        children: [
          SizedBox(
            height: municipalityDetailMapHeight(context),
            width: double.infinity,
            child: ClipRRect(
              borderRadius: const BorderRadius.only(
                bottomLeft: Radius.circular(12),
                bottomRight: Radius.circular(12),
              ),
              child: MisamisOccidentalExploreMap(
                key: ValueKey('municipality-map-${m.id}'),
                spots: mapSpots,
                centerLat: m.lat,
                centerLng: m.lng,
                initialZoom: _kMapZoom,
                onMapReady: (move) => move(m.lat, m.lng, zoom: _kMapZoom),
                onSpotTap: (fs) {
                  final spot = _spotForFirestore(fs);
                  if (spot == null) return;
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => TouristSpotDetailScreen(spot: spot),
                    ),
                  );
                },
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
                      style: TextStyle(
                        color: AppTheme.unselectedMuted,
                        fontSize: 14,
                      ),
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
                            builder: (context) =>
                                TouristSpotDetailScreen(spot: spot),
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
              Builder(
                builder: (context) {
                  final thumb = MediaQuery.sizeOf(context).width < 600
                      ? 72.0
                      : 88.0;
                  return touristSpotThumbnail(
                    spot.imageUrl,
                    size: thumb,
                  );
                },
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
                      style: TextStyle(
                        color: AppTheme.brandOrange.withValues(alpha: 0.9),
                        fontSize: 12,
                      ),
                    ),
                    if (spot.description.isNotEmpty)
                      Text(
                        spot.description,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: AppTheme.unselectedMuted,
                          fontSize: 13,
                        ),
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

}

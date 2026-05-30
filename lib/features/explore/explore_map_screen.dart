import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:atmos_trs_system/config/auth_config.dart';
import 'package:atmos_trs_system/services/tourist_activity_firestore_sync.dart';
import 'package:atmos_trs_system/widgets/misamis_occidental_explore_map.dart';
import 'package:atmos_trs_system/models/tourist_spot_firestore.dart';
import 'package:atmos_trs_system/services/tourist_spots_repository.dart';
import 'package:atmos_trs_system/screens/municipality_map_and_spots_screen.dart';
import 'package:atmos_trs_system/features/explore/explore_data.dart'
    show TouristSpot, kMockSpots;
import 'package:atmos_trs_system/services/user_activity_service.dart'
    as activity;
import 'package:intl/intl.dart';
import 'package:atmos_trs_system/config/app_theme.dart';
import 'package:atmos_trs_system/config/app_theme_controller.dart';
import 'package:atmos_trs_system/config/vr_tour_config.dart';
import 'package:atmos_trs_system/features/tourism/tourist_spot_detail_screen.dart';

const Color _kDarkText = Color(0xFF111827);
const Color _kMuted = Color(0xFF6B7280);

/// 17 municipalities/cities in Misamis Occidental — used for map pins.
final List<TouristSpotFirestore> _sampleSpots = [
  TouristSpotFirestore(
    id: 'oroquieta_city',
    name: 'Oroquieta City',
    category: 'Historical',
    latitude: 8.4854,
    longitude: 123.8058,
    rating: 4.8,
    image: 'assets/images/oroquieta City plaza.jpeg',
    vrLink: kOroquietaCityPlazaVrUrl,
  ),
  TouristSpotFirestore(
    id: 'ozamis_city',
    name: 'Ozamis City',
    category: 'Historical',
    latitude: 8.1481,
    longitude: 123.8444,
    rating: 4.7,
    image: 'https://images.unsplash.com/photo-1449824913935-59a10b8d2000?w=400',
    vrLink: '',
  ),
  TouristSpotFirestore(
    id: 'tangub_city',
    name: 'Tangub City',
    category: 'Historical',
    latitude: 8.0656,
    longitude: 123.7547,
    rating: 4.6,
    image: 'https://images.unsplash.com/photo-1480714378408-67cf0d13bc1b?w=400',
    vrLink: '',
  ),
  TouristSpotFirestore(
    id: 'aloran',
    name: 'Aloran',
    category: 'Beach',
    latitude: 8.4167,
    longitude: 123.8333,
    rating: 4.5,
    image: 'https://images.unsplash.com/photo-1507525428034-b723cf961d3e?w=400',
    vrLink: '',
  ),
  TouristSpotFirestore(
    id: 'baliangao',
    name: 'Baliangao',
    category: 'Beach',
    latitude: 8.6167,
    longitude: 123.5667,
    rating: 4.6,
    image: 'https://images.unsplash.com/photo-1519046904884-53103b34b206?w=400',
    vrLink: '',
  ),
  TouristSpotFirestore(
    id: 'bonifacio',
    name: 'Bonifacio',
    category: 'Mountain',
    latitude: 8.0667,
    longitude: 123.6167,
    rating: 4.4,
    image: 'https://images.unsplash.com/photo-1464822759023-fed622ff2c3b?w=400',
    vrLink: '',
  ),
  TouristSpotFirestore(
    id: 'calamba',
    name: 'Calamba',
    category: 'Mountain',
    latitude: 8.1667,
    longitude: 123.7167,
    rating: 4.3,
    image: 'assets/images/CALAMBA.jpg',
    vrLink: '',
  ),
  TouristSpotFirestore(
    id: 'clarin',
    name: 'Clarin',
    category: 'Beach',
    latitude: 8.2167,
    longitude: 123.8500,
    rating: 4.5,
    image: 'https://images.unsplash.com/photo-1471922694854-ff1b63b20054?w=400',
    vrLink: '',
  ),
  TouristSpotFirestore(
    id: 'concepcion',
    name: 'Concepcion',
    category: 'Falls',
    latitude: 8.1500,
    longitude: 123.5833,
    rating: 4.4,
    image: 'assets/images/conception.png',
    vrLink: '',
  ),
  TouristSpotFirestore(
    id: 'don_victoriano',
    name: 'Don Victoriano Chiongbian',
    category: 'Mountain',
    latitude: 7.9167,
    longitude: 123.4667,
    rating: 4.5,
    image: 'https://images.unsplash.com/photo-1454496522488-7a8e488e8606?w=400',
    vrLink: '',
  ),
  TouristSpotFirestore(
    id: 'jimenez',
    name: 'Jimenez',
    category: 'Beach',
    latitude: 8.3333,
    longitude: 123.8333,
    rating: 4.6,
    image: 'https://images.unsplash.com/photo-1520942702018-0862200e6873?w=400',
    vrLink: '',
  ),
  TouristSpotFirestore(
    id: 'lopez_jaena',
    name: 'Lopez Jaena',
    category: 'Beach',
    latitude: 8.5500,
    longitude: 123.7667,
    rating: 4.5,
    image: 'https://images.unsplash.com/photo-1473116763249-2faaef81ccda?w=400',
    vrLink: '',
  ),
  TouristSpotFirestore(
    id: 'panaon',
    name: 'Panaon',
    category: 'Beach',
    latitude: 8.6833,
    longitude: 123.7167,
    rating: 4.7,
    image: 'https://images.unsplash.com/photo-1510414842594-a61c69b5ae57?w=400',
    vrLink: '',
  ),
  TouristSpotFirestore(
    id: 'plaridel',
    name: 'Plaridel',
    category: 'Beach',
    latitude: 8.6167,
    longitude: 123.7000,
    rating: 4.4,
    image: 'assets/images/PLARIDEL.jpg',
    vrLink: '',
  ),
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
  TouristSpotFirestore(
    id: 'sinacaban',
    name: 'Sinacaban',
    category: 'Resorts',
    latitude: 8.2833,
    longitude: 123.8500,
    rating: 4.5,
    image: 'assets/images/AMORAP.jpg',
    vrLink: '',
  ),
  TouristSpotFirestore(
    id: 'tudela',
    name: 'Tudela',
    category: 'Beach',
    latitude: 8.5333,
    longitude: 123.8500,
    rating: 4.5,
    image: 'assets/images/Tudela Village.webp',
    vrLink: '',
  ),
];

/// Explore tab screen: full Explore Map (Misamis Occidental with 17 municipality pins).
/// Moved from Home screen; same behavior, styling, markers, zoom controls, and Full Map modal.
class ExploreScreen extends StatefulWidget {
  const ExploreScreen({super.key});

  @override
  State<ExploreScreen> createState() => _ExploreScreenState();
}

class _ExploreScreenState extends State<ExploreScreen> {
  MisamisMapMoveTo? _mapMoveTo;
  List<TouristSpotFirestore> _municipalitySpots = _sampleSpots;
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  // Sections under the map
  bool _isLoadingSections = true;
  List<TouristSpot> _recommendedSpots = [];
  List<activity.VisitRecord> _recentVisits = [];
  List<activity.VisitRecord> _allVisits = [];

  bool get _isMobileLayout => MediaQuery.sizeOf(context).width < 600;

  @override
  void initState() {
    super.initState();
    _searchController.addListener(() {
      if (mounted) setState(() {});
    });
    _loadExploreSections();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<TouristSpotFirestore> _filterSpots(List<TouristSpotFirestore> spots) {
    final q = _searchQuery.trim().toLowerCase();
    if (q.isEmpty) return spots;
    return spots
        .where(
          (s) =>
              s.name.toLowerCase().contains(q) ||
              s.category.toLowerCase().contains(q) ||
              s.municipality.toLowerCase().contains(q) ||
              s.id.toLowerCase().replaceAll('_', ' ').contains(q),
        )
        .toList();
  }

  void _onSearchSubmitted(String value) {
    setState(() => _searchQuery = value.trim());
    final matches = _filterSpots(_municipalitySpots);
    if (matches.length == 1) {
      final s = matches.first;
      _mapMoveTo?.call(s.latitude, s.longitude, zoom: 12);
    }
  }

  void _openMunicipality(TouristSpotFirestore spot) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) =>
            MunicipalityMapAndSpotsScreen(municipalityIdOrName: spot.name),
      ),
    );
  }

  Future<void> _loadExploreSections() async {
    final uid =
        AuthConfig.currentUserUid ?? FirebaseAuth.instance.currentUser?.uid;
    if (uid != null && uid.isNotEmpty) {
      await TouristActivityFirestoreSync.mergeFromCloud(uid);
    }
    final visits =
        await activity.UserActivityService.syncVisitedSpotsFromQrCheckins();
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
      final Set<String> top = topCategories.take(2).map((e) => e.key).toSet();

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
      recommended = kMockSpots.where((s) => s.rating >= 4.5).toList()
        ..sort((a, b) => b.rating.compareTo(a.rating));
    }

    // Limit to 8 cards
    recommended = recommended.take(8).toList();

    if (!mounted) return;
    setState(() {
      _recommendedSpots = recommended;
      _allVisits = visits;
      _recentVisits = recent;
      _isLoadingSections = false;
    });
  }

  void _showAllVisits() {
    if (_isMobileLayout) {
      Navigator.of(context).push<void>(
        MaterialPageRoute<void>(
          fullscreenDialog: true,
          builder: (ctx) => Scaffold(
            backgroundColor: Colors.white,
            appBar: AppBar(
              backgroundColor: Colors.white,
              elevation: 0,
              scrolledUnderElevation: 0,
              leadingWidth: 80,
              leading: Padding(
                padding: const EdgeInsets.only(left: 12),
                child: Center(
                  child: FilledButton(
                    onPressed: () => Navigator.pop(ctx),
                    style: FilledButton.styleFrom(
                      backgroundColor: AppTheme.brandOrange,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 8,
                      ),
                      minimumSize: const Size(0, 36),
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    child: const Text(
                      'Back',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ),
              title: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'My Recent Visits',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      color: _kDarkText,
                    ),
                  ),
                  Text(
                    _allVisits.isEmpty
                        ? 'No check-ins yet'
                        : '${_allVisits.length} place${_allVisits.length == 1 ? '' : 's'}',
                    style: TextStyle(
                      fontSize: 13,
                      color: Colors.grey.shade600,
                    ),
                  ),
                ],
              ),
            ),
            body: _allVisits.isEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(
                        'Scan a destination QR code to record your visit.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: _kMuted, fontSize: 14),
                      ),
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                    itemCount: _allVisits.length,
                    itemBuilder: (_, i) => _buildRecentVisitTile(_allVisits[i]),
                  ),
          ),
        ),
      );
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Full visit history is in your Profile tab.'),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  List<TouristSpotFirestore> _mergeSampleWithFirestore(
    List<TouristSpotFirestore> firestoreSpots,
  ) {
    if (firestoreSpots.isEmpty) return _sampleSpots;
    final byId = {for (final s in firestoreSpots) s.id: s};
    return _sampleSpots.map((sample) {
      final remote = byId[sample.id];
      if (remote == null) return sample;
      return TouristSpotFirestore(
        id: sample.id,
        name: remote.name.isNotEmpty ? remote.name : sample.name,
        category: remote.category.isNotEmpty
            ? remote.category
            : sample.category,
        latitude: sample.latitude,
        longitude: sample.longitude,
        image: remote.image ?? sample.image,
        rating: remote.rating != 0.0 ? remote.rating : sample.rating,
        description: remote.description.isNotEmpty
            ? remote.description
            : sample.description,
        vrLink: resolveVrTourUrl(
              vrLink: (remote.vrLink != null && remote.vrLink!.trim().isNotEmpty)
                  ? remote.vrLink
                  : sample.vrLink,
              spotId: sample.id,
              spotName: remote.name.isNotEmpty ? remote.name : sample.name,
            ) ??
            sample.vrLink,
        municipality: remote.municipality.isNotEmpty
            ? remote.municipality
            : sample.municipality,
        municipalityId: remote.municipalityId.isNotEmpty
            ? remote.municipalityId
            : sample.municipalityId,
        qrValue: remote.qrValue.isNotEmpty ? remote.qrValue : sample.qrValue,
        qrPayload: remote.qrPayload ?? sample.qrPayload,
      );
    }).toList();
  }

  void _showFullMap() {
    final spots = _municipalitySpots.isNotEmpty
        ? _municipalitySpots
        : _sampleSpots;
    final isMobile = MediaQuery.sizeOf(context).width < 600;

    if (isMobile) {
      Navigator.of(context).push<void>(
        MaterialPageRoute<void>(
          fullscreenDialog: true,
          builder: (ctx) => Scaffold(
            backgroundColor: Colors.white,
            appBar: AppBar(
              backgroundColor: Colors.white,
              elevation: 0,
              scrolledUnderElevation: 0,
              leadingWidth: 80,
              leading: Padding(
                padding: const EdgeInsets.only(left: 12),
                child: Center(
                  child: FilledButton(
                    onPressed: () => Navigator.pop(ctx),
                    style: FilledButton.styleFrom(
                      backgroundColor: AppTheme.brandOrange,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 8,
                      ),
                      minimumSize: const Size(0, 36),
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    child: const Text(
                      'Back',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ),
              title: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Misamis Occidental Map',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      color: _kDarkText,
                    ),
                  ),
                  Text(
                    '${spots.length} municipalities & cities',
                    style: TextStyle(
                      fontSize: 13,
                      color: Colors.grey.shade600,
                    ),
                  ),
                ],
              ),
            ),
            body: MisamisOccidentalExploreMap(
              key: const ValueKey('explore-fullscreen-map'),
              spots: spots,
              onSpotTap: (spot) {
                Navigator.pop(ctx);
                _openMunicipality(spot);
              },
            ),
          ),
        ),
      );
      return;
    }

    final accent = AppTheme.primary;
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        final height = MediaQuery.of(context).size.height * 0.9;
        return Container(
          height: height,
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          clipBehavior: Clip.antiAlias,
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
              Container(
                width: double.infinity,
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      accent.withValues(alpha: 0.14),
                      accent.withValues(alpha: 0.04),
                    ],
                  ),
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Icon(Icons.map_rounded, color: accent, size: 24),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Misamis Occidental Map',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w800,
                              color: _kDarkText,
                            ),
                          ),
                          Text(
                            '${spots.length} municipalities & cities',
                            style: TextStyle(
                              fontSize: 13,
                              color: _kMuted,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.close_rounded),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(20),
                    child: MisamisOccidentalExploreMap(
                      key: const ValueKey('explore-fullscreen-map'),
                      spots: spots,
                      onSpotTap: (spot) {
                        Navigator.pop(context);
                        _openMunicipality(spot);
                      },
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

  Widget _buildExploreHeader() {
    final accent = AppTheme.primary;
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: accent.withValues(alpha: 0.28)),
        boxShadow: [
          BoxShadow(
            color: accent.withValues(alpha: 0.1),
            blurRadius: 18,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.fromLTRB(18, 18, 18, 16),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  accent.withValues(alpha: 0.18),
                  accent.withValues(alpha: 0.05),
                ],
              ),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(
                        color: accent.withValues(alpha: 0.12),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Icon(Icons.explore_rounded, color: accent, size: 28),
                ),
                const SizedBox(width: 14),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Explore Misamis Occidental',
                        style: TextStyle(
                          color: _kDarkText,
                          fontSize: 22,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.3,
                          height: 1.15,
                        ),
                      ),
                      SizedBox(height: 4),
                      Text(
                        '17 municipalities • tourist spots & check-ins',
                        style: TextStyle(
                          color: _kMuted,
                          fontSize: 13,
                          height: 1.35,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
            child: TextField(
              controller: _searchController,
              textInputAction: TextInputAction.search,
              onSubmitted: (v) => _onSearchSubmitted(v),
              onChanged: (v) => setState(() => _searchQuery = v.trim()),
              style: const TextStyle(fontSize: 15, color: _kDarkText),
              decoration: InputDecoration(
                hintText: 'Search municipality or city…',
                hintStyle: TextStyle(color: _kMuted.withValues(alpha: 0.9)),
                prefixIcon: Icon(Icons.search_rounded, color: accent),
                suffixIcon: _searchController.text.isNotEmpty
                    ? IconButton(
                        icon: Icon(Icons.close_rounded, color: _kMuted),
                        onPressed: () {
                          _searchController.clear();
                          _onSearchSubmitted('');
                        },
                      )
                    : null,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: BorderSide(color: accent.withValues(alpha: 0.2)),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: BorderSide(color: accent.withValues(alpha: 0.2)),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: BorderSide(color: accent, width: 2),
                ),
                filled: true,
                fillColor: const Color(0xFFF9FAFB),
                contentPadding: const EdgeInsets.symmetric(vertical: 14),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMapCard() {
    final accent = AppTheme.primary;
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: accent.withValues(alpha: 0.25)),
        boxShadow: [
          BoxShadow(
            color: accent.withValues(alpha: 0.08),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 12, 10),
            child: Row(
              children: [
                Icon(Icons.map_outlined, size: 20, color: accent),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    'Explore Map',
                    style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w800,
                      color: _kDarkText,
                    ),
                  ),
                ),
                FilledButton.tonalIcon(
                  onPressed: _showFullMap,
                  icon: const Icon(Icons.fullscreen_rounded, size: 18),
                  label: const Text('Full map'),
                  style: FilledButton.styleFrom(
                    backgroundColor: accent.withValues(alpha: 0.12),
                    foregroundColor: accent,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    visualDensity: VisualDensity.compact,
                  ),
                ),
              ],
            ),
          ),
          SizedBox(
            height: misamisEmbeddedMapHeight(context),
            child: StreamBuilder<List<TouristSpotFirestore>>(
              stream: TouristSpotsRepository.streamTouristSpots(),
              builder: (context, snapshot) {
                final firestoreSpots = snapshot.data ?? [];
                final baseSpots = firestoreSpots.isEmpty
                    ? _sampleSpots
                    : _mergeSampleWithFirestore(firestoreSpots);
                _municipalitySpots = baseSpots;
                final displaySpots = _filterSpots(baseSpots);
                final visibleCount = displaySpots.length;

                return Stack(
                  children: [
                    MisamisOccidentalExploreMap(
                      key: ValueKey(
                        'explore-embedded-map-${_searchQuery.hashCode}',
                      ),
                      spots: displaySpots.isEmpty ? baseSpots : displaySpots,
                      onMapReady: (moveTo) => _mapMoveTo = moveTo,
                      onSpotTap: _openMunicipality,
                    ),
                    Positioned(
                      top: 12,
                      left: 12,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color: accent.withValues(alpha: 0.25),
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.08),
                              blurRadius: 10,
                            ),
                          ],
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.place_rounded,
                              color: accent,
                              size: 18,
                            ),
                            const SizedBox(width: 6),
                            Text(
                              '$visibleCount destinations',
                              style: TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 13,
                                color: accent,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    Positioned(
                      bottom: 10,
                      right: 10,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.95),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          'Tap a pin to explore',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: _kMuted,
                          ),
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionHeader({
    required String title,
    String? subtitle,
    required IconData icon,
    Widget? trailing,
  }) {
    final accent = AppTheme.primary;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 4,
          height: 40,
          decoration: BoxDecoration(
            color: accent,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 12),
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: accent.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(icon, size: 20, color: accent),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  color: _kDarkText,
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.2,
                ),
              ),
              if (subtitle != null) ...[
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: const TextStyle(color: _kMuted, fontSize: 12.5),
                ),
              ],
            ],
          ),
        ),
        if (trailing != null) trailing,
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: AppThemeController.instance,
      builder: (context, _) {
        final accent = AppTheme.primary;
        return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              accent.withValues(alpha: 0.05),
              const Color(0xFFF8FAFC),
            ],
          ),
        ),
        child: SafeArea(
        child: RefreshIndicator(
          color: accent,
          onRefresh: _loadExploreSections,
          child: CustomScrollView(
          slivers: [
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildExploreHeader(),
                    const SizedBox(height: 16),
                    _buildMapCard(),
                    const SizedBox(height: 20),
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
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 24,
                ),
                child: _buildRecentVisitsSection(),
              ),
            ),
            const SliverToBoxAdapter(child: SizedBox(height: 32)),
          ],
        ),
        ),
      ),
    ),
        );
      },
    );
  }

  // ---------------------------------------------------------------------------
  // Sections under the map
  // ---------------------------------------------------------------------------

  Widget _buildRecommendedSection() {
    if (_isLoadingSections) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 16),
          child: CircularProgressIndicator(color: AppTheme.primary),
        ),
      );
    }
    if (_recommendedSpots.isEmpty) {
      return const SizedBox.shrink();
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionHeader(
          title: 'Recommended for You',
          subtitle: 'Based on your visits and top-rated spots',
          icon: Icons.recommend_rounded,
        ),
        const SizedBox(height: 14),
        SizedBox(
          height: MediaQuery.sizeOf(context).width < 600 ? 188 : 228,
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
    final accent = AppTheme.primary;
    final compact = MediaQuery.sizeOf(context).width < 600;
    final cardSize = compact ? 188.0 : 228.0;
    final imageH = compact ? 80.0 : 100.0;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => MunicipalityMapAndSpotsScreen(
                municipalityIdOrName:
                    spot.city.isNotEmpty ? spot.city : spot.name,
              ),
            ),
          );
        },
        borderRadius: BorderRadius.circular(20),
        child: SizedBox(
          width: cardSize,
          height: cardSize,
          child: Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: accent.withValues(alpha: 0.12)),
              boxShadow: [
                BoxShadow(
                  color: accent.withValues(alpha: 0.06),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            clipBehavior: Clip.antiAlias,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Stack(
                  children: [
                    SizedBox(
                      height: imageH,
                      width: double.infinity,
                      child: _buildSpotImage(spot.imageUrl),
                    ),
                    Positioned(
                      left: 0,
                      top: 0,
                      bottom: 0,
                      child: Container(width: 4, color: accent),
                    ),
                  ],
                ),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: accent.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(
                            spot.category,
                            style: TextStyle(
                              color: accent,
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        const SizedBox(height: 6),
                        Expanded(
                          child: Text(
                            spot.name,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: _kDarkText,
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              height: 1.2,
                            ),
                          ),
                        ),
                        Row(
                          children: [
                            const Icon(
                              Icons.star_rounded,
                              size: 16,
                              color: Color(0xFFF59E0B),
                            ),
                            const SizedBox(width: 4),
                            Text(
                              spot.rating.toStringAsFixed(1),
                              style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                                color: _kDarkText,
                              ),
                            ),
                            const Spacer(),
                            Icon(
                              Icons.arrow_forward_rounded,
                              size: 16,
                              color: accent,
                            ),
                          ],
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
    );
  }

  Widget _buildRecentVisitsSection() {
    if (_isLoadingSections) {
      return const SizedBox.shrink();
    }
    final accent = AppTheme.primary;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionHeader(
          title: 'My Recent Visits',
          subtitle: _recentVisits.isEmpty
              ? 'Check in at destinations to see them here'
              : 'Your latest QR check-ins',
          icon: Icons.history_rounded,
          trailing: _allVisits.isNotEmpty
              ? TextButton(
                  onPressed: _showAllVisits,
                  child: Text(
                    'View all',
                    style: TextStyle(
                      color: AppTheme.brandOrange,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                )
              : null,
        ),
        const SizedBox(height: 12),
        if (_allVisits.isEmpty)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: accent.withValues(alpha: 0.15)),
            ),
            child: Column(
              children: [
                Icon(
                  Icons.qr_code_scanner_rounded,
                  size: 40,
                  color: accent.withValues(alpha: 0.5),
                ),
                const SizedBox(height: 10),
                const Text(
                  'No visits yet',
                  style: TextStyle(
                    color: _kDarkText,
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Scan a destination QR code to record your visit and unlock personalized recommendations.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: _kMuted,
                    fontSize: 13,
                    height: 1.4,
                  ),
                ),
              ],
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

  Future<void> _openVisitedSpot(activity.VisitRecord visit) async {
    final mockMatches =
        kMockSpots.where((s) => s.id == visit.spotId).toList();
    if (mockMatches.isNotEmpty) {
      if (!mounted) return;
      await Navigator.of(context).push<void>(
        MaterialPageRoute<void>(
          builder: (_) => TouristSpotDetailScreen(spot: mockMatches.first),
        ),
      );
      return;
    }

    for (final s in _municipalitySpots) {
      if (s.id == visit.spotId) {
        if (!mounted) return;
        await Navigator.of(context).push<void>(
          MaterialPageRoute<void>(
            builder: (_) => MunicipalityMapAndSpotsScreen(
              municipalityIdOrName: s.name,
            ),
          ),
        );
        return;
      }
    }

    final fromFirestore =
        await TouristSpotsRepository.getSpotById(visit.spotId);
    if (fromFirestore != null && mounted) {
      await Navigator.of(context).push<void>(
        MaterialPageRoute<void>(
          builder: (_) => MunicipalityMapAndSpotsScreen(
            municipalityIdOrName: fromFirestore.name,
          ),
        ),
      );
      return;
    }

    if (!mounted) return;
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => MunicipalityMapAndSpotsScreen(
          municipalityIdOrName: visit.spotName,
        ),
      ),
    );
  }

  Widget _buildRecentVisitTile(activity.VisitRecord visit) {
    final formatter = DateFormat('MMM d, yyyy');
    final accent = AppTheme.primary;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: () => _openVisitedSpot(visit),
        child: Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: accent.withValues(alpha: 0.12)),
        boxShadow: [
          BoxShadow(
            color: accent.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              width: 5,
              decoration: BoxDecoration(
                color: accent,
                borderRadius: const BorderRadius.horizontal(
                  left: Radius.circular(18),
                ),
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 12,
                ),
                child: Row(
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: accent.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Icon(
                        Icons.place_rounded,
                        color: accent,
                        size: 24,
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
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Wrap(
                            spacing: 6,
                            runSpacing: 4,
                            children: [
                              _buildVisitChip(
                                visit.category,
                                accent,
                              ),
                              _buildVisitChip(
                                formatter.format(visit.visitedAt),
                                _kMuted,
                                filled: false,
                              ),
                            ],
                          ),
                        ],
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
    );
  }

  Widget _buildVisitChip(String label, Color color, {bool filled = true}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: filled ? color.withValues(alpha: 0.12) : const Color(0xFFF3F4F6),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: filled ? color : _kMuted,
          fontSize: 11,
          fontWeight: FontWeight.w600,
        ),
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

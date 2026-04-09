import 'package:flutter/material.dart';
import 'dart:convert';
import 'package:atmos_trs_system/config/user_profile_storage.dart';
import 'package:atmos_trs_system/services/profile_photo_hydration.dart';
import 'package:atmos_trs_system/models/tourist_spot_firestore.dart';
import 'package:atmos_trs_system/services/tourist_spots_repository.dart';
import 'package:atmos_trs_system/services/user_activity_service.dart'
    as activity;
import 'package:atmos_trs_system/screens/vr_webview_screen.dart';
import 'package:atmos_trs_system/screens/municipality_map_and_spots_screen.dart';
import 'package:atmos_trs_system/features/explore/explore_map_screen.dart'
    show ExploreScreen;
import 'package:atmos_trs_system/features/explore/explore_screen.dart'
    show kMockSpots;
import 'package:atmos_trs_system/features/tourism/tourist_spot_detail_screen.dart';

/// Primary color - Orange theme
const Color _kPrimaryOrange = Color(0xFFF97316);
const Color _kPrimaryOrangeDeep = Color(0xFFEA580C);
const Color _kDarkText = Color(0xFF1F2937);
const Color _kSurfaceWarm = Color(0xFFFFF7F0);
const Color _kAccentCream = Color(0xFFFFEDD5);

/// Misamis Occidental center (used e.g. for VR preview location)
const double _kMapCenterLat = 8.3377;
const double _kMapCenterLng = 123.7072;

/// Featured destinations data (actual destination images)
final List<Map<String, dynamic>> _featuredDestinations = [
  {
    'name': 'Baliangao Beach',
    'description': 'Pristine white sand beaches with crystal clear waters',
    'image': 'assets/images/Baliangao - Cabgan Island.jpg',
    'rating': 4.8,
    'category': 'Beach',
  },
  {
    'name': 'Mount Malindang',
    'description': 'Home to diverse wildlife and breathtaking hiking trails',
    'image': 'assets/images/Piduan Falls Donvic.jpg',
    'rating': 4.9,
    'category': 'Mountain',
  },
  {
    'name': 'Oroquieta City',
    'description': 'The provincial capital known as the "City of Good Life"',
    'image': 'assets/images/oroquieta city.jpg',
    'rating': 4.7,
    'category': 'Historical',
  },
  {
    'name': 'Sapang Dalaga Nature Bay',
    'description': 'Nature escape with stunning coastal and mountain views.',
    'image': 'assets/images/SaPang Dalaga - Caluya Bay with Floating Playground.jpg',
    'rating': 4.6,
    'category': 'Nature',
  },
];

/// Categories for Featured Destinations filter.
const List<String> _featuredCategories = [
  'All',
  'Beach',
  'Historical',
  'Mountain',
  'Park',
  'Nature',
];

/// Misamis Occidental Cities and Municipalities (17). Use local attraction images where available.
const Map<String, String> _kAttractionAssetImages = {
  'oroquieta_city': 'assets/images/City PLaza Oroquieta.png',
  'ozamis_city': 'assets/images/ozamis city.webp',
  'tangub_city': 'assets/images/Asenso Global Garden 1.png',
  'clarin': 'assets/images/clarin.jpg',
  'baliangao': 'assets/images/Baliangao - Cabgan Island.jpg',
  'sapang_dalaga': 'assets/images/Sapang Dalaga.png',
  'don_victoriano': 'assets/images/Piduan Falls Donvic.jpg',
  'jimenez': 'assets/images/Jimenez - St. John the Baptist Church.jpg',
  'calamba': 'assets/images/CALAMBA.jpg',
  'concepcion': 'assets/images/conception.png',
  'plaridel': 'assets/images/PLARIDEL.jpg',
  'sinacaban': 'assets/images/sinacaban.jpg',
  'tudela': 'assets/images/Tudela Village.webp',
  'panaon': 'assets/images/Panaon.webp',
};

String _spotImage(TouristSpotFirestore spot) {
  final asset = _kAttractionAssetImages[spot.id];
  if (asset != null) return asset;
  return spot.image ?? '';
}

/// Misamis Occidental Cities and Municipalities
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
    image: 'assets/images/sinacaban.jpg',
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

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  UserProfile? _userProfile;
  final PageController _featuredController = PageController(
    viewportFraction: 0.85,
  );
  int _currentFeaturedIndex = 0;

  // User stats from storage
  activity.UserStats _userStats = activity.UserStats(
    placesVisited: 0,
    badgesEarned: 0,
    daysAsTourist: 1,
    savedSpots: 0,
  );
  List<activity.VisitRecord> _recentVisits = [];
  List<activity.VisitRecord> _recentlyViewed = [];
  List<activity.AppNotification> _notifications = [];
  Set<String> _savedSpotIds = {};
  int _unreadNotifications = 0;
  bool _isLoading = true;

  // Featured Destinations category filter
  int _selectedFeaturedCategoryIndex = 0;

  @override
  void initState() {
    super.initState();
    _loadAllData();
  }

  List<Map<String, dynamic>> get _filteredFeaturedDestinations {
    final selected = _featuredCategories[_selectedFeaturedCategoryIndex];
    if (selected == 'All') return _featuredDestinations;
    final selectedLower = selected.toLowerCase();
    return _featuredDestinations
        .where((d) =>
            (d['category'] as String?)?.toLowerCase() == selectedLower)
        .toList();
  }

  Future<void> _loadAllData() async {
    setState(() => _isLoading = true);
    await Future.wait([
      _loadUserProfile(),
      _loadUserStats(),
      _loadRecentVisits(),
      _loadRecentlyViewed(),
      _loadNotifications(),
      _loadSavedSpots(),
    ]);
    setState(() => _isLoading = false);
  }

  Future<void> _loadUserProfile() async {
    var profile = await UserProfileStorage.getUserProfile();
    profile = await ProfilePhotoHydration.mergeFirestorePhotoUrl(profile);
    if (mounted) {
      setState(() => _userProfile = profile);
    }
  }

  Future<void> _loadUserStats() async {
    final stats = await activity.UserActivityService.getUserStats();
    if (mounted) {
      setState(() => _userStats = stats);
    }
  }

  Future<void> _loadRecentVisits() async {
    final visits = await activity.UserActivityService.getVisitedSpots();
    if (mounted) {
      setState(() => _recentVisits = visits);
    }
  }

  Future<void> _loadRecentlyViewed() async {
    final list = await activity.UserActivityService.getRecentlyViewed();
    if (mounted) {
      setState(() => _recentlyViewed = list);
    }
  }

  Future<void> _loadNotifications() async {
    final notifications = await activity.UserActivityService.getNotifications();
    final unread =
        await activity.UserActivityService.getUnreadNotificationsCount();
    if (mounted) {
      setState(() {
        _notifications = notifications;
        _unreadNotifications = unread;
      });
    }
  }

  Future<void> _loadSavedSpots() async {
    final savedIds = await activity.UserActivityService.getSavedSpotIds();
    if (mounted) {
      setState(() => _savedSpotIds = savedIds.toSet());
    }
  }

  /// Builds image widget for spot or visit: supports assets (assets/...) and network URLs.
  Widget _buildSpotImage(
    String? imageUrl, {
    required double width,
    required double height,
  }) {
    if (imageUrl == null || imageUrl.isEmpty) {
      return Container(
        width: width,
        height: height,
        color: Colors.grey.shade200,
        child: const Icon(Icons.place),
      );
    }
    if (imageUrl.startsWith('assets/')) {
      return Image.asset(
        imageUrl,
        width: width,
        height: height,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => Container(
          width: width,
          height: height,
          color: Colors.grey.shade200,
          child: const Icon(Icons.place),
        ),
      );
    }
    return Image.network(
      imageUrl,
      width: width,
      height: height,
      fit: BoxFit.cover,
      errorBuilder: (_, __, ___) => Container(
        width: width,
        height: height,
        color: Colors.grey.shade200,
        child: const Icon(Icons.place),
      ),
    );
  }

  Future<void> _toggleSaveSpot(TouristSpotFirestore spot) async {
    final isSaved = await activity.UserActivityService.toggleSaveSpot(spot.id);
    if (mounted) {
      setState(() {
        if (isSaved) {
          _savedSpotIds.add(spot.id);
        } else {
          _savedSpotIds.remove(spot.id);
        }
        _userStats = activity.UserStats(
          placesVisited: _userStats.placesVisited,
          badgesEarned: _userStats.badgesEarned,
          daysAsTourist: _userStats.daysAsTourist,
          savedSpots: _savedSpotIds.length,
        );
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            isSaved ? '${spot.name} saved!' : '${spot.name} removed from saved',
          ),
          behavior: SnackBarBehavior.floating,
          backgroundColor: isSaved ? _kPrimaryOrange : Colors.grey.shade700,
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  Future<void> _checkInToSpot(TouristSpotFirestore spot) async {
    await activity.UserActivityService.addVisit(
      spotId: spot.id,
      spotName: spot.name,
      category: spot.category,
      imageUrl: spot.image,
    );

    await _loadUserStats();
    await _loadRecentVisits();

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.check_circle, color: Colors.white),
              const SizedBox(width: 8),
              Text('Checked in to ${spot.name}!'),
            ],
          ),
          behavior: SnackBarBehavior.floating,
          backgroundColor: _kPrimaryOrange,
          duration: const Duration(seconds: 3),
        ),
      );
    }
  }

  void _showQRGuide(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => _QRGuideBottomSheet(userProfile: _userProfile),
    );
  }

  @override
  void dispose() {
    _featuredController.dispose();
    super.dispose();
  }

  String _timeBasedGreeting() {
    final h = DateTime.now().hour;
    if (h < 12) return 'Good morning';
    if (h < 17) return 'Good afternoon';
    return 'Good evening';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _kSurfaceWarm,
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Color(0xFFFFF9F5),
              Color(0xFFF3F4F6),
            ],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              _buildHeader(context),
              Expanded(
                child: RefreshIndicator(
                  color: _kPrimaryOrange,
                  onRefresh: _loadAllData,
                  child: _isLoading
                      ? const Center(
                          child: CircularProgressIndicator(
                            color: _kPrimaryOrange,
                          ),
                        )
                      : SingleChildScrollView(
                          physics: const AlwaysScrollableScrollPhysics(),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const SizedBox(height: 12),
                              _buildWeatherWidget(),
                              const SizedBox(height: 16),
                              _buildQuickActionsRow(context),
                              const SizedBox(height: 20),
                              _buildQuickStats(),
                              const SizedBox(height: 22),
                              _buildFeaturedCategoryChips(),
                              const SizedBox(height: 12),
                            _buildFeaturedSection(),
                            const SizedBox(height: 24),
                            _buildRecentlyViewedSection(),
                            const SizedBox(height: 24),
                            _buildRecentVisitsSection(context),
                              const SizedBox(height: 40),
                            ],
                          ),
                        ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeaderProfileAvatar() {
    final url = _userProfile?.profilePhotoUrl?.trim();
    if (url != null && url.isNotEmpty) {
      return ClipOval(
        child: Image.network(
          url,
          width: 48,
          height: 48,
          fit: BoxFit.cover,
          loadingBuilder: (context, child, progress) {
            if (progress == null) return child;
            return SizedBox(
              width: 48,
              height: 48,
              child: Center(
                child: SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: _kPrimaryOrange,
                    value: progress.expectedTotalBytes != null
                        ? progress.cumulativeBytesLoaded /
                            progress.expectedTotalBytes!
                        : null,
                  ),
                ),
              ),
            );
          },
          errorBuilder: (_, __, ___) {
            final b64 = _userProfile?.profileImageBase64;
            if (b64 != null && b64.isNotEmpty) {
              return Image.memory(
                base64Decode(b64),
                width: 48,
                height: 48,
                fit: BoxFit.cover,
              );
            }
            return Icon(Icons.person, color: Colors.grey.shade400, size: 28);
          },
        ),
      );
    }
    final b64 = _userProfile?.profileImageBase64;
    if (b64 != null && b64.isNotEmpty) {
      return ClipOval(
        child: Image.memory(
          base64Decode(b64),
          width: 48,
          height: 48,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) =>
              Icon(Icons.person, color: Colors.grey.shade400, size: 28),
        ),
      );
    }
    return Icon(Icons.person, color: Colors.grey.shade400, size: 28);
  }

  Widget _buildHeader(BuildContext context) {
    final userName = _userProfile?.firstName ?? 'Guest';

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Container(
        padding: const EdgeInsets.fromLTRB(18, 18, 14, 18),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Colors.white,
              _kAccentCream.withOpacity(0.85),
            ],
          ),
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: Colors.white.withOpacity(0.9)),
          boxShadow: [
            BoxShadow(
              color: _kPrimaryOrange.withOpacity(0.12),
              blurRadius: 24,
              offset: const Offset(0, 10),
            ),
            BoxShadow(
              color: Colors.black.withOpacity(0.04),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          children: [
            GestureDetector(
              onTap: () {},
              child: Container(
                width: 54,
                height: 54,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      _kPrimaryOrange.withOpacity(0.15),
                      _kPrimaryOrange.withOpacity(0.05),
                    ],
                  ),
                  border: Border.all(
                    color: _kPrimaryOrange.withOpacity(0.35),
                    width: 2,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: _kPrimaryOrange.withOpacity(0.2),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Center(child: _buildHeaderProfileAvatar()),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _timeBasedGreeting(),
                    style: TextStyle(
                      color: Colors.grey.shade600,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.2,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    userName,
                    style: const TextStyle(
                      color: _kDarkText,
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.5,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Discover Misamis Occidental today',
                    style: TextStyle(
                      color: _kPrimaryOrangeDeep.withOpacity(0.9),
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
            Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: () => _showQRGuide(context),
                borderRadius: BorderRadius.circular(14),
                child: Ink(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [_kPrimaryOrange, _kPrimaryOrangeDeep],
                    ),
                    borderRadius: BorderRadius.circular(14),
                    boxShadow: [
                      BoxShadow(
                        color: _kPrimaryOrange.withOpacity(0.4),
                        blurRadius: 10,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: const Icon(
                    Icons.qr_code_2_rounded,
                    color: Colors.white,
                    size: 26,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildQuickActionsRow(BuildContext context) {
    Widget action({
      required IconData icon,
      required String label,
      required List<Color> gradient,
      required VoidCallback onTap,
    }) {
      return Expanded(
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(16),
            child: Ink(
              padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.grey.shade200),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.04),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: gradient,
                      ),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(icon, color: Colors.white, size: 22),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    label,
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: _kDarkText,
                      height: 1.05,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Jump back in',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: Colors.grey.shade700,
              letterSpacing: 0.3,
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              action(
                icon: Icons.map_rounded,
                label: 'Province\nmap',
                gradient: const [
                  Color(0xFF2563EB),
                  Color(0xFF1D4ED8),
                ],
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute<void>(
                      builder: (_) => const ExploreScreen(),
                    ),
                  );
                },
              ),
              const SizedBox(width: 10),
              action(
                icon: Icons.explore_rounded,
                label: 'All\nspots',
                gradient: const [_kPrimaryOrange, _kPrimaryOrangeDeep],
                onTap: _showAllDestinationsDialog,
              ),
              const SizedBox(width: 10),
              action(
                icon: Icons.qr_code_scanner_rounded,
                label: 'QR\nguide',
                gradient: const [
                  Color(0xFF059669),
                  Color(0xFF047857),
                ],
                onTap: () => _showQRGuide(context),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildHeaderIcon(
    IconData icon,
    VoidCallback onTap, {
    bool hasNotification = false,
    int notificationCount = 0,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: _kPrimaryOrange.withOpacity(0.12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: _kPrimaryOrange, size: 24),
          ),
          if (hasNotification)
            Positioned(
              top: -4,
              right: -4,
              child: Container(
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: _kPrimaryOrange,
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 2),
                ),
                constraints: const BoxConstraints(minWidth: 20, minHeight: 20),
                child: Text(
                  notificationCount > 9 ? '9+' : notificationCount.toString(),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
            ),
        ],
      ),
    );
  }

  void _showNotifications(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => StatefulBuilder(
        builder: (context, setModalState) => Container(
          height: MediaQuery.of(context).size.height * 0.6,
          padding: const EdgeInsets.all(20),
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
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
              const SizedBox(height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Notifications',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: _kDarkText,
                    ),
                  ),
                  if (_notifications.isNotEmpty)
                    TextButton(
                      onPressed: () async {
                        await activity.UserActivityService.clearNotifications();
                        setModalState(() {});
                        await _loadNotifications();
                        if (mounted) setState(() {});
                      },
                      child: const Text(
                        'Clear All',
                        style: TextStyle(color: _kPrimaryOrange),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 16),
              Expanded(
                child: _notifications.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.notifications_off_outlined,
                              size: 64,
                              color: Colors.grey.shade300,
                            ),
                            const SizedBox(height: 16),
                            Text(
                              'No notifications',
                              style: TextStyle(
                                color: Colors.grey.shade500,
                                fontSize: 16,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'You\'re all caught up!',
                              style: TextStyle(
                                color: Colors.grey.shade400,
                                fontSize: 14,
                              ),
                            ),
                          ],
                        ),
                      )
                    : ListView.builder(
                        itemCount: _notifications.length,
                        itemBuilder: (context, index) {
                          final notification = _notifications[index];
                          return _buildNotificationItemFromData(
                            notification,
                            () async {
                              if (!notification.isRead) {
                                await activity
                                    .UserActivityService.markNotificationAsRead(
                                  notification.id,
                                );
                                await _loadNotifications();
                                setModalState(() {});
                                if (mounted) setState(() {});
                              }
                            },
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildNotificationItemFromData(
    activity.AppNotification notification,
    VoidCallback onTap,
  ) {
    IconData icon;
    Color color;

    switch (notification.type) {
      case activity.NotificationType.badge:
        icon = Icons.emoji_events_rounded;
        color = _kPrimaryOrange;
        break;
      case activity.NotificationType.event:
        icon = Icons.event_rounded;
        color = _kPrimaryOrange;
        break;
      case activity.NotificationType.weather:
        icon = Icons.wb_sunny_rounded;
        color = _kPrimaryOrange;
        break;
      case activity.NotificationType.checkin:
        icon = Icons.check_circle_rounded;
        color = _kPrimaryOrange;
        break;
      case activity.NotificationType.system:
        icon = Icons.info_rounded;
        color = _kPrimaryOrange;
        break;
    }

    final timeAgo = _getTimeAgo(notification.createdAt);

    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: notification.isRead
              ? Colors.grey.shade50
              : _kPrimaryOrange.withOpacity(0.05),
          borderRadius: BorderRadius.circular(12),
          border: notification.isRead
              ? null
              : Border.all(color: _kPrimaryOrange.withOpacity(0.2)),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: color.withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: color, size: 24),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          notification.title,
                          style: TextStyle(
                            fontWeight: notification.isRead
                                ? FontWeight.w500
                                : FontWeight.w600,
                            color: _kDarkText,
                          ),
                        ),
                      ),
                      if (!notification.isRead)
                        Container(
                          width: 8,
                          height: 8,
                          decoration: const BoxDecoration(
                            color: _kPrimaryOrange,
                            shape: BoxShape.circle,
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    notification.message,
                    style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    timeAgo,
                    style: TextStyle(fontSize: 11, color: Colors.grey.shade400),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _getTimeAgo(DateTime dateTime) {
    final diff = DateTime.now().difference(dateTime);
    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    return '${dateTime.day}/${dateTime.month}/${dateTime.year}';
  }

  Widget _buildQuickStats() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Your progress',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: Colors.grey.shade700,
              letterSpacing: 0.2,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _buildStatCard(
                  'Places Visited',
                  _userStats.placesVisited.toString(),
                  Icons.place_rounded,
                  Colors.deepOrange,
                  onTap: () => _showVisitedPlacesDialog(),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildStatCard(
                  'Badges Earned',
                  _userStats.badgesEarned.toString(),
                  Icons.emoji_events_rounded,
                  Colors.purple,
                  onTap: () => _showBadgesDialog(),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _buildStatCard(
                  'Days as Tourist',
                  _userStats.daysAsTourist.toString(),
                  Icons.calendar_today_rounded,
                  Colors.teal,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildStatCard(
                  'Saved Spots',
                  _userStats.savedSpots.toString(),
                  Icons.bookmark_rounded,
                  Colors.indigo,
                  onTap: () => _showSavedSpotsDialog(),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _showVisitedPlacesDialog() async {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => Container(
        height: MediaQuery.of(context).size.height * 0.6,
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          children: [
            Container(
              margin: const EdgeInsets.only(top: 12),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(20),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: _kPrimaryOrange.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(
                      Icons.place_rounded,
                      color: _kPrimaryOrange,
                      size: 24,
                    ),
                  ),
                  const SizedBox(width: 12),
                  const Text(
                    'Visited Places',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: _kDarkText,
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: _recentVisits.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.explore_off,
                            size: 64,
                            color: Colors.grey.shade300,
                          ),
                          const SizedBox(height: 16),
                          Text(
                            'No places visited yet',
                            style: TextStyle(
                              color: Colors.grey.shade500,
                              fontSize: 16,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Start exploring Misamis Occidental!',
                            style: TextStyle(
                              color: Colors.grey.shade400,
                              fontSize: 14,
                            ),
                          ),
                        ],
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      itemCount: _recentVisits.length,
                      itemBuilder: (context, index) {
                        final visit = _recentVisits[index];
                        return _buildVisitListItem(visit);
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildVisitListItem(activity.VisitRecord visit) {
    final daysAgo = DateTime.now().difference(visit.visitedAt).inDays;
    final timeLabel = daysAgo == 0
        ? 'Today'
        : daysAgo == 1
        ? 'Yesterday'
        : '$daysAgo days ago';

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: visit.imageUrl != null
                ? _buildSpotImage(visit.imageUrl, width: 50, height: 50)
                : Container(
                    width: 50,
                    height: 50,
                    color: Colors.grey.shade200,
                    child: const Icon(Icons.place),
                  ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  visit.spotName,
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    color: _kDarkText,
                  ),
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: _kPrimaryOrange.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        visit.category,
                        style: const TextStyle(
                          color: _kPrimaryOrange,
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Icon(
                      Icons.access_time,
                      size: 12,
                      color: Colors.grey.shade500,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      timeLabel,
                      style: TextStyle(
                        color: Colors.grey.shade500,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const Icon(Icons.check_circle, color: _kPrimaryOrange, size: 20),
        ],
      ),
    );
  }

  void _showBadgesDialog() async {
    final badges = await activity.UserActivityService.getEarnedBadges();
    if (!mounted) return;

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => Container(
        height: MediaQuery.of(context).size.height * 0.5,
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          children: [
            Container(
              margin: const EdgeInsets.only(top: 12),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(20),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: _kPrimaryOrange.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(
                      Icons.emoji_events_rounded,
                      color: _kPrimaryOrange,
                      size: 24,
                    ),
                  ),
                  const SizedBox(width: 12),
                  const Text(
                    'Earned Badges',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: _kDarkText,
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: badges.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.emoji_events_outlined,
                            size: 64,
                            color: Colors.grey.shade300,
                          ),
                          const SizedBox(height: 16),
                          Text(
                            'No badges yet',
                            style: TextStyle(
                              color: Colors.grey.shade500,
                              fontSize: 16,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Visit tourist spots to earn badges!',
                            style: TextStyle(
                              color: Colors.grey.shade400,
                              fontSize: 14,
                            ),
                          ),
                        ],
                      ),
                    )
                  : GridView.builder(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      gridDelegate:
                          const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 2,
                            childAspectRatio: 1.2,
                            crossAxisSpacing: 12,
                            mainAxisSpacing: 12,
                          ),
                      itemCount: badges.length,
                      itemBuilder: (context, index) {
                        final badge = badges[index];
                        return _buildBadgeCard(badge);
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBadgeCard(activity.Badge badge) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            _kPrimaryOrange.withOpacity(0.2),
            _kPrimaryOrange.withOpacity(0.08),
          ],
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _kPrimaryOrange.withOpacity(0.4)),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(
            Icons.emoji_events_rounded,
            color: _kPrimaryOrange,
            size: 32,
          ),
          const SizedBox(height: 8),
          Text(
            badge.name,
            style: const TextStyle(
              fontWeight: FontWeight.bold,
              color: _kDarkText,
              fontSize: 14,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 4),
          Text(
            badge.description,
            style: TextStyle(color: Colors.grey.shade600, fontSize: 10),
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  void _showSavedSpotsDialog() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => Container(
        height: MediaQuery.of(context).size.height * 0.6,
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          children: [
            Container(
              margin: const EdgeInsets.only(top: 12),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(20),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: _kPrimaryOrange.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(
                      Icons.bookmark_rounded,
                      color: _kPrimaryOrange,
                      size: 24,
                    ),
                  ),
                  const SizedBox(width: 12),
                  const Text(
                    'Saved Spots',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: _kDarkText,
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: StreamBuilder<List<TouristSpotFirestore>>(
                stream: TouristSpotsRepository.streamTouristSpots(),
                builder: (context, snapshot) {
                  final firestoreSpots = snapshot.data ?? [];
                  final spots = firestoreSpots.isEmpty
                      ? _sampleSpots
                      : firestoreSpots;
                  final savedSpots = spots
                      .where((s) => _savedSpotIds.contains(s.id))
                      .toList();

                  if (savedSpots.isEmpty) {
                    return Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.bookmark_border,
                            size: 64,
                            color: Colors.grey.shade300,
                          ),
                          const SizedBox(height: 16),
                          Text(
                            'No saved spots',
                            style: TextStyle(
                              color: Colors.grey.shade500,
                              fontSize: 16,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Tap the bookmark icon to save spots!',
                            style: TextStyle(
                              color: Colors.grey.shade400,
                              fontSize: 14,
                            ),
                          ),
                        ],
                      ),
                    );
                  }

                  return ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    itemCount: savedSpots.length,
                    itemBuilder: (context, index) {
                      final spot = savedSpots[index];
                      return _buildSavedSpotItem(spot);
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSavedSpotItem(TouristSpotFirestore spot) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      child: GestureDetector(
        onTap: () {
          Navigator.pop(context);
          _showSpotBottomSheet(spot);
        },
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.grey.shade50,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: _buildSpotImage(_spotImage(spot), width: 50, height: 50),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      spot.name,
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        color: _kDarkText,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: _kPrimaryOrange.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            spot.category,
                            style: const TextStyle(
                              color: _kPrimaryOrange,
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Icon(Icons.star, size: 12, color: _kPrimaryOrange),
                        const SizedBox(width: 2),
                        Text(
                          spot.rating.toStringAsFixed(1),
                          style: TextStyle(
                            color: Colors.grey.shade600,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              IconButton(
                icon: const Icon(Icons.bookmark, color: _kPrimaryOrange),
                onPressed: () async {
                  await _toggleSaveSpot(spot);
                  if (mounted) setState(() {});
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStatCard(
    String label,
    String value,
    IconData icon,
    Color color, {
    VoidCallback? onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Ink(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: color.withOpacity(0.15)),
            boxShadow: [
              BoxShadow(
                color: color.withOpacity(0.08),
                blurRadius: 16,
                offset: const Offset(0, 6),
              ),
              BoxShadow(
                color: Colors.black.withOpacity(0.03),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(11),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      color.withOpacity(0.2),
                      color.withOpacity(0.08),
                    ],
                  ),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(icon, color: color, size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: Colors.grey.shade600,
                        letterSpacing: 0.2,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      value,
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                        color: color,
                        letterSpacing: -0.5,
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

  Widget _buildFeaturedCategoryChips() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Text(
            'Filter by vibe',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: Colors.grey.shade700,
              letterSpacing: 0.2,
            ),
          ),
        ),
        const SizedBox(height: 10),
        SizedBox(
          height: 42,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 20),
            itemCount: _featuredCategories.length,
            itemBuilder: (context, index) {
              final label = _featuredCategories[index];
              final isSelected = index == _selectedFeaturedCategoryIndex;
              return Padding(
                padding: const EdgeInsets.only(right: 8),
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: () {
                      setState(() {
                        _selectedFeaturedCategoryIndex = index;
                        _currentFeaturedIndex = 0;
                      });
                    },
                    borderRadius: BorderRadius.circular(20),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 220),
                      curve: Curves.easeOutCubic,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 9,
                      ),
                      decoration: BoxDecoration(
                        gradient: isSelected
                            ? const LinearGradient(
                                colors: [_kPrimaryOrange, _kPrimaryOrangeDeep],
                              )
                            : null,
                        color: isSelected ? null : Colors.white,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: isSelected
                              ? Colors.transparent
                              : Colors.grey.shade300,
                        ),
                        boxShadow: isSelected
                            ? [
                                BoxShadow(
                                  color: _kPrimaryOrange.withOpacity(0.35),
                                  blurRadius: 12,
                                  offset: const Offset(0, 4),
                                ),
                              ]
                            : [
                                BoxShadow(
                                  color: Colors.black.withOpacity(0.04),
                                  blurRadius: 6,
                                  offset: const Offset(0, 2),
                                ),
                              ],
                      ),
                      child: Text(
                        label,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: isSelected
                              ? Colors.white
                              : Colors.grey.shade700,
                        ),
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildFeaturedSection() {
    final items = _filteredFeaturedDestinations;
    if (items.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.05),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Row(
            children: [
              Icon(Icons.info_outline,
                  color: _kPrimaryOrange.withOpacity(0.9), size: 20),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'No featured destinations for this category yet.',
                  style: TextStyle(
                    color: Colors.grey.shade700,
                    fontSize: 13,
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(6),
                            decoration: BoxDecoration(
                              color: _kPrimaryOrange.withOpacity(0.12),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: const Icon(
                              Icons.auto_awesome,
                              color: _kPrimaryOrange,
                              size: 18,
                            ),
                          ),
                          const SizedBox(width: 10),
                          const Text(
                            'Featured destinations',
                            style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.w800,
                              color: _kDarkText,
                              letterSpacing: -0.3,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Padding(
                        padding: const EdgeInsets.only(left: 4),
                        child: Text(
                          'Hand-picked spots across the province',
                          style: TextStyle(
                            fontSize: 13,
                            color: Colors.grey.shade600,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ],
                  ),
                  TextButton(
                    onPressed: _showAllDestinationsDialog,
                    style: TextButton.styleFrom(
                      foregroundColor: _kPrimaryOrange,
                    ),
                    child: const Text(
                      'See all',
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 14,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        SizedBox(
          height: 228,
          child: PageView.builder(
            controller: _featuredController,
            onPageChanged: (index) =>
                setState(() => _currentFeaturedIndex = index),
            itemCount: items.length,
            itemBuilder: (context, index) =>
                _buildFeaturedCard(items[index]),
          ),
        ),
        const SizedBox(height: 12),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: List.generate(
            items.length,
            (index) => AnimatedContainer(
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeOutCubic,
              margin: const EdgeInsets.symmetric(horizontal: 4),
              width: _currentFeaturedIndex == index ? 28 : 8,
              height: 8,
              decoration: BoxDecoration(
                gradient: _currentFeaturedIndex == index
                    ? const LinearGradient(
                        colors: [_kPrimaryOrange, _kPrimaryOrangeDeep],
                      )
                    : null,
                color: _currentFeaturedIndex == index ? null : Colors.grey.shade300,
                borderRadius: BorderRadius.circular(4),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildFeaturedCardImage(String imageUrl) {
    if (imageUrl.startsWith('assets/')) {
      return Image.asset(
        imageUrl,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => Container(color: Colors.grey.shade300),
      );
    }
    return Image.network(
      imageUrl,
      fit: BoxFit.cover,
      errorBuilder: (_, __, ___) => Container(color: Colors.grey.shade300),
    );
  }

  Widget _buildFeaturedCard(Map<String, dynamic> destination) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        boxShadow: [
          BoxShadow(
            color: _kPrimaryOrange.withOpacity(0.15),
            blurRadius: 16,
            offset: const Offset(0, 8),
          ),
          BoxShadow(
            color: Colors.black.withOpacity(0.08),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(22),
        child: Stack(
          fit: StackFit.expand,
          children: [
            _buildFeaturedCardImage(destination['image'] as String),
            Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.black.withOpacity(0.15),
                    Colors.black.withOpacity(0.75),
                  ],
                ),
              ),
            ),
            Positioned(
              top: 16,
              left: 16,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: _kPrimaryOrange,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  destination['category'] as String,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
            Positioned(
              bottom: 16,
              left: 16,
              right: 16,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    destination['name'] as String,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Icon(Icons.star, color: _kPrimaryOrange, size: 16),
                      const SizedBox(width: 4),
                      Text(
                        '${destination['rating']}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          destination['description'] as String,
                          style: TextStyle(
                            color: Colors.white.withOpacity(0.8),
                            fontSize: 12,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
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

  Widget _buildWeatherWidget() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Container(
        padding: const EdgeInsets.fromLTRB(18, 18, 18, 18),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              _kPrimaryOrange,
              _kPrimaryOrangeDeep,
              const Color(0xFFC2410C),
            ],
          ),
          borderRadius: BorderRadius.circular(22),
          boxShadow: [
            BoxShadow(
              color: _kPrimaryOrange.withOpacity(0.35),
              blurRadius: 20,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: Stack(
          children: [
            Positioned(
              right: -20,
              top: -20,
              child: Icon(
                Icons.wb_sunny_rounded,
                size: 120,
                color: Colors.white.withOpacity(0.08),
              ),
            ),
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.22),
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(
                      color: Colors.white.withOpacity(0.25),
                    ),
                  ),
                  child: const Icon(
                    Icons.wb_sunny_rounded,
                    color: Colors.white,
                    size: 36,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Misamis Occidental',
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.88),
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 0.4,
                        ),
                      ),
                      const SizedBox(height: 4),
                      const Text(
                        '28°C',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 36,
                          fontWeight: FontWeight.w800,
                          height: 1,
                          letterSpacing: -1,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Sunny · Great day to explore',
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.9),
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    _weatherMini(Icons.water_drop, '65%'),
                    const SizedBox(height: 8),
                    _weatherMini(Icons.air, '12 km/h'),
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _weatherMini(IconData icon, String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.18),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: Colors.white.withOpacity(0.9), size: 14),
          const SizedBox(width: 6),
          Text(
            text,
            style: TextStyle(
              color: Colors.white.withOpacity(0.95),
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  void _showSpotBottomSheet(TouristSpotFirestore spot) {
    activity.UserActivityService.recordRecentlyViewed(
      spotId: spot.id,
      spotName: spot.name,
      category: spot.category,
      imageUrl: spot.image,
    ).then((_) async {
      if (!mounted) return;
      final list = await activity.UserActivityService.getRecentlyViewed();
      if (mounted) setState(() => _recentlyViewed = list);
    });

    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => StatefulBuilder(
        builder: (context, setModalState) {
          final currentlySaved = _savedSpotIds.contains(spot.id);
          final maxWidth = 400.0;

          return Center(
            child: Container(
              margin: const EdgeInsets.fromLTRB(24, 0, 24, 24),
              constraints: BoxConstraints(maxWidth: maxWidth),
              padding: const EdgeInsets.all(20),
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.all(Radius.circular(20)),
                boxShadow: [
                  BoxShadow(
                    color: Color(0x1A000000),
                    blurRadius: 20,
                    offset: Offset(0, 8),
                  ),
                ],
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
                        color: Colors.grey.shade300,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: _buildSpotImage(
                          _spotImage(spot),
                          width: 80,
                          height: 80,
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
                                color: _kDarkText,
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 4,
                                  ),
                                  decoration: BoxDecoration(
                                    color: _kPrimaryOrange.withOpacity(0.15),
                                    borderRadius: BorderRadius.circular(8),
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
                                const SizedBox(width: 8),
                                Icon(
                                  Icons.star,
                                  size: 14,
                                  color: _kPrimaryOrange,
                                ),
                                const SizedBox(width: 2),
                                Text(
                                  spot.rating > 0
                                      ? spot.rating.toStringAsFixed(1)
                                      : '—',
                                  style: TextStyle(
                                    color: _kPrimaryOrange,
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
                  const SizedBox(height: 20),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () async {
                            await _toggleSaveSpot(spot);
                            setModalState(() {});
                          },
                          icon: Icon(
                            currentlySaved
                                ? Icons.bookmark
                                : Icons.bookmark_border,
                            size: 18,
                          ),
                          label: Text(currentlySaved ? 'Saved' : 'Save'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: currentlySaved
                                ? Colors.white
                                : _kPrimaryOrange,
                            backgroundColor: currentlySaved
                                ? _kPrimaryOrange
                                : null,
                            side: const BorderSide(color: _kPrimaryOrange),
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: FilledButton.icon(
                          onPressed: () async {
                            Navigator.pop(context);
                            await _checkInToSpot(spot);
                          },
                          icon: const Icon(
                            Icons.qr_code_scanner_rounded,
                            size: 18,
                          ),
                          label: const Text('Check In'),
                          style: FilledButton.styleFrom(
                            backgroundColor: _kPrimaryOrange,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: () {
                        Navigator.pop(context);
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => MunicipalityMapAndSpotsScreen(
                              municipalityIdOrName: spot.name,
                            ),
                          ),
                        );
                      },
                      icon: const Icon(Icons.map_rounded, size: 18),
                      label: Text('Open map · ${spot.name}'),
                      style: FilledButton.styleFrom(
                        backgroundColor: _kPrimaryOrange,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  if (spot.vrLink?.isNotEmpty == true)
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: () {
                          Navigator.pop(context);
                          openVrTour(
                            context,
                            url: spot.vrLink ?? '',
                            title: spot.name,
                          );
                        },
                        icon: const Icon(Icons.vrpano_rounded, size: 18),
                        label: const Text('Launch VR Tour'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: _kPrimaryOrange,
                          side: const BorderSide(color: _kPrimaryOrange),
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  void _showAllDestinationsDialog() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.85,
        minChildSize: 0.5,
        maxChildSize: 0.95,
        builder: (context, scrollController) => Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: Column(
            children: [
              Container(
                margin: const EdgeInsets.only(top: 12),
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(20),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: _kPrimaryOrange.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(
                        Icons.explore_rounded,
                        color: _kPrimaryOrange,
                        size: 24,
                      ),
                    ),
                    const SizedBox(width: 12),
                    const Expanded(
                      child: Text(
                        'All Destinations',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: _kDarkText,
                        ),
                      ),
                    ),
                    Text(
                      '${_sampleSpots.length} spots',
                      style: TextStyle(color: Colors.grey.shade500),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: ListView.builder(
                  controller: scrollController,
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  itemCount: _sampleSpots.length,
                  itemBuilder: (context, index) {
                    final spot = _sampleSpots[index];
                    return _buildDestinationListItem(spot);
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDestinationListItem(TouristSpotFirestore spot) {
    final isSaved = _savedSpotIds.contains(spot.id);

    return GestureDetector(
      onTap: () {
        Navigator.pop(context);
        _showSpotBottomSheet(spot);
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.grey.shade50,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: _buildSpotImage(_spotImage(spot), width: 70, height: 70),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    spot.name,
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      color: _kDarkText,
                      fontSize: 15,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: _kPrimaryOrange.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(6),
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
                      const SizedBox(width: 8),
                      Icon(Icons.star, size: 14, color: _kPrimaryOrange),
                      const SizedBox(width: 2),
                      Text(
                        spot.rating.toStringAsFixed(1),
                        style: TextStyle(
                          color: Colors.grey.shade600,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            IconButton(
              icon: Icon(
                isSaved ? Icons.bookmark : Icons.bookmark_border,
                color: isSaved ? _kPrimaryOrange : Colors.grey.shade400,
              ),
              onPressed: () async {
                await _toggleSaveSpot(spot);
                setState(() {});
              },
            ),
          ],
        ),
      ),
    );
  }

  String _viewedTimeLabel(DateTime at) {
    final diff = DateTime.now().difference(at);
    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inHours < 1) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    return '${at.day}/${at.month}/${at.year}';
  }

  Widget _buildRecentlyViewedSection() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: const Color(0xFF6366F1).withOpacity(0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  Icons.visibility_rounded,
                  color: Color(0xFF4F46E5),
                  size: 18,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Recently viewed',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                        color: _kDarkText,
                        letterSpacing: -0.3,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Places you opened from Home',
                      style: TextStyle(
                        fontSize: 13,
                        color: Colors.grey.shade600,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          SizedBox(
            height: _recentlyViewed.isEmpty ? 132 : 168,
            child: _recentlyViewed.isEmpty
                ? Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 20,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: Colors.grey.shade200),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.04),
                          blurRadius: 12,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.travel_explore_rounded,
                          size: 40,
                          color: _kPrimaryOrange.withOpacity(0.65),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Text(
                            'Open any spot from All destinations or your lists — it will show up here.',
                            style: TextStyle(
                              color: Colors.grey.shade700,
                              fontSize: 13,
                              height: 1.35,
                            ),
                          ),
                        ),
                      ],
                    ),
                  )
                : ListView.builder(
                    scrollDirection: Axis.horizontal,
                    itemCount: _recentlyViewed.length.clamp(0, 12),
                    itemBuilder: (context, index) {
                      return _buildRecentlyViewedCard(_recentlyViewed[index]);
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildRecentlyViewedCard(activity.VisitRecord entry) {
    final timeLabel = _viewedTimeLabel(entry.visitedAt);

    return GestureDetector(
      onTap: () {
        final mockMatches =
            kMockSpots.where((s) => s.id == entry.spotId);
        if (mockMatches.isNotEmpty) {
          Navigator.of(context).push<void>(
            MaterialPageRoute<void>(
              builder: (_) =>
                  TouristSpotDetailScreen(spot: mockMatches.first),
            ),
          );
          return;
        }
        TouristSpotFirestore? homeSpot;
        for (final s in _sampleSpots) {
          if (s.id == entry.spotId) {
            homeSpot = s;
            break;
          }
        }
        if (homeSpot != null) {
          _showSpotBottomSheet(homeSpot);
          return;
        }
        Navigator.of(context).push<void>(
          MaterialPageRoute<void>(
            builder: (_) => MunicipalityMapAndSpotsScreen(
              municipalityIdOrName: entry.spotName,
            ),
          ),
        );
      },
      child: Container(
        width: 148,
        margin: const EdgeInsets.only(right: 12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFF4F46E5).withOpacity(0.12)),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF4F46E5).withOpacity(0.06),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Stack(
              children: [
                ClipRRect(
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(15),
                  ),
                  child: entry.imageUrl != null && entry.imageUrl!.isNotEmpty
                      ? _buildSpotImage(
                          entry.imageUrl,
                          width: 148,
                          height: 96,
                        )
                      : Container(
                          width: 148,
                          height: 96,
                          color: Colors.grey.shade200,
                          child: Icon(
                            Icons.place_rounded,
                            size: 36,
                            color: Colors.grey.shade500,
                          ),
                        ),
                ),
                Positioned(
                  top: 8,
                  right: 8,
                  child: Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.12),
                          blurRadius: 4,
                        ),
                      ],
                    ),
                    child: Icon(
                      Icons.visibility_rounded,
                      color: const Color(0xFF4F46E5).withOpacity(0.9),
                      size: 14,
                    ),
                  ),
                ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    entry.spotName,
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 12,
                      color: _kDarkText,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Icon(
                        Icons.schedule_rounded,
                        size: 11,
                        color: Colors.grey.shade500,
                      ),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          timeLabel,
                          style: TextStyle(
                            color: Colors.grey.shade600,
                            fontSize: 10,
                            fontWeight: FontWeight.w500,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
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

  Widget _buildRecentVisitsSection(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          color: const Color(0xFF10B981).withOpacity(0.12),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Icon(
                          Icons.route_rounded,
                          color: Color(0xFF059669),
                          size: 18,
                        ),
                      ),
                      const SizedBox(width: 10),
                      const Text(
                        'Your trail',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w800,
                          color: _kDarkText,
                          letterSpacing: -0.3,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Padding(
                    padding: const EdgeInsets.only(left: 4),
                    child: Text(
                      'Places you have checked in to recently',
                      style: TextStyle(
                        fontSize: 13,
                        color: Colors.grey.shade600,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
              TextButton(
                onPressed: _showVisitedPlacesDialog,
                style: TextButton.styleFrom(
                  foregroundColor: _kPrimaryOrange,
                ),
                child: const Text(
                  'See all',
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Container(
            height: 208,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: Colors.grey.shade200),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.04),
                  blurRadius: 16,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            clipBehavior: Clip.antiAlias,
            child: _recentVisits.isEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 24),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Container(
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: _kPrimaryOrange.withOpacity(0.08),
                              shape: BoxShape.circle,
                            ),
                            child: Icon(
                              Icons.terrain_rounded,
                              size: 40,
                              color: _kPrimaryOrange.withOpacity(0.7),
                            ),
                          ),
                          const SizedBox(height: 14),
                          Text(
                            'Start your journey',
                            style: TextStyle(
                              color: Colors.grey.shade800,
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            'Scan a spot QR or pick a destination to build your travel trail.',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: Colors.grey.shade600,
                              fontSize: 13,
                              height: 1.35,
                            ),
                          ),
                        ],
                      ),
                    ),
                  )
                : ListView.builder(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
                    itemCount: _recentVisits.take(6).length,
                    itemBuilder: (context, index) =>
                        _buildRecentVisitCard(_recentVisits[index]),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildRecentVisitCard(activity.VisitRecord visit) {
    final daysAgo = DateTime.now().difference(visit.visitedAt).inDays;
    final timeLabel = daysAgo == 0
        ? 'Today'
        : daysAgo == 1
        ? 'Yesterday'
        : '$daysAgo days ago';

    return GestureDetector(
      onTap: () {
        // Find the spot in sample spots
        final spot = _sampleSpots.firstWhere(
          (s) => s.id == visit.spotId,
          orElse: () => TouristSpotFirestore(
            id: visit.spotId,
            name: visit.spotName,
            category: visit.category,
            latitude: _kMapCenterLat,
            longitude: _kMapCenterLng,
            rating: 4.5,
            image: visit.imageUrl,
            vrLink: '',
          ),
        );
        _showSpotBottomSheet(spot);
      },
      child: Container(
        width: 150,
        margin: const EdgeInsets.only(right: 12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.06),
              blurRadius: 10,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Stack(
              children: [
                ClipRRect(
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(16),
                  ),
                  child: visit.imageUrl != null
                      ? _buildSpotImage(visit.imageUrl, width: 150, height: 100)
                      : Container(
                          width: 150,
                          height: 100,
                          color: Colors.grey.shade200,
                          child: const Icon(Icons.place, size: 40),
                        ),
                ),
                Positioned(
                  top: 8,
                  right: 8,
                  child: Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.1),
                          blurRadius: 4,
                        ),
                      ],
                    ),
                    child: const Icon(
                      Icons.check_circle,
                      color: _kPrimaryOrange,
                      size: 16,
                    ),
                  ),
                ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.all(10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    visit.spotName,
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                      color: _kDarkText,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Icon(
                        Icons.access_time,
                        size: 12,
                        color: Colors.grey.shade500,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        timeLabel,
                        style: TextStyle(
                          color: Colors.grey.shade500,
                          fontSize: 11,
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
}

class _QRGuideBottomSheet extends StatefulWidget {
  final UserProfile? userProfile;
  const _QRGuideBottomSheet({this.userProfile});
  @override
  State<_QRGuideBottomSheet> createState() => _QRGuideBottomSheetState();
}

class _QRGuideBottomSheetState extends State<_QRGuideBottomSheet> {
  int _currentStep = 0;
  final PageController _pageController = PageController();

  final List<Map<String, dynamic>> _guideSteps = [
    {
      'title': 'Your Tourist QR Code',
      'description':
          'This is your unique digital tourist ID. Show this QR code at any tourist spot for quick check-in.',
      'icon': Icons.qr_code_2_rounded,
      'color': _kPrimaryOrange,
    },
    {
      'title': 'Visit Tourist Spots',
      'description':
          'Explore beautiful destinations across Misamis Occidental. From beaches to mountains!',
      'icon': Icons.explore_rounded,
      'color': const Color(0xFF3B82F6),
    },
    {
      'title': 'Scan at Entrance',
      'description':
          'Look for the QR scanner at entrances. Present your QR code to staff for scanning.',
      'icon': Icons.qr_code_scanner_rounded,
      'color': const Color(0xFF8B5CF6),
    },
    {
      'title': 'Check-in Complete!',
      'description':
          'Your visit is recorded automatically. View history in your profile and collect badges!',
      'icon': Icons.check_circle_rounded,
      'color': const Color(0xFFF59E0B),
    },
  ];

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: MediaQuery.of(context).size.height * 0.75,
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        children: [
          Container(
            margin: const EdgeInsets.only(top: 12),
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.grey.shade300,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 20, 24, 0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'How to Use Your QR',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: _kDarkText,
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: Icon(Icons.close, color: Colors.grey.shade600),
                ),
              ],
            ),
          ),
          Expanded(
            child: PageView.builder(
              controller: _pageController,
              onPageChanged: (index) => setState(() => _currentStep = index),
              itemCount: _guideSteps.length,
              itemBuilder: (context, index) {
                final step = _guideSteps[index];
                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: SingleChildScrollView(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        if (index == 0) ...[
                          Container(
                            padding: const EdgeInsets.all(20),
                            decoration: BoxDecoration(
                              color: Colors.grey.shade100,
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Column(
                              children: [
                                Container(
                                  width: 160,
                                  height: 160,
                                  decoration: BoxDecoration(
                                    color: Colors.white,
                                    borderRadius: BorderRadius.circular(16),
                                    boxShadow: [
                                      BoxShadow(
                                        color: Colors.black.withOpacity(0.1),
                                        blurRadius: 10,
                                      ),
                                    ],
                                  ),
                                  child: Icon(
                                    Icons.qr_code_2_rounded,
                                    size: 120,
                                    color: Colors.grey.shade800,
                                  ),
                                ),
                                const SizedBox(height: 12),
                                Text(
                                  widget.userProfile?.firstName ?? 'Tourist ID',
                                  style: const TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w600,
                                    color: _kDarkText,
                                  ),
                                ),
                                Text(
                                  'Misamis Occidental Tourist',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.grey.shade600,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ] else ...[
                          Container(
                            width: 100,
                            height: 100,
                            decoration: BoxDecoration(
                              color: (step['color'] as Color).withOpacity(0.1),
                              shape: BoxShape.circle,
                            ),
                            child: Icon(
                              step['icon'] as IconData,
                              color: step['color'] as Color,
                              size: 50,
                            ),
                          ),
                        ],
                        const SizedBox(height: 32),
                        Text(
                          step['title'] as String,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.bold,
                            color: _kDarkText,
                          ),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          step['description'] as String,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 15,
                            color: Colors.grey.shade600,
                            height: 1.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(
                _guideSteps.length,
                (index) => AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  margin: const EdgeInsets.symmetric(horizontal: 4),
                  width: _currentStep == index ? 24 : 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: _currentStep == index
                        ? _kPrimaryOrange
                        : Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 32),
            child: Row(
              children: [
                if (_currentStep > 0)
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => _pageController.previousPage(
                        duration: const Duration(milliseconds: 300),
                        curve: Curves.easeInOut,
                      ),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: _kPrimaryOrange,
                        side: const BorderSide(color: _kPrimaryOrange),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: const Text(
                        'Previous',
                        style: TextStyle(fontWeight: FontWeight.w600),
                      ),
                    ),
                  ),
                if (_currentStep > 0) const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    onPressed: () {
                      if (_currentStep < _guideSteps.length - 1) {
                        _pageController.nextPage(
                          duration: const Duration(milliseconds: 300),
                          curve: Curves.easeInOut,
                        );
                      } else {
                        Navigator.pop(context);
                      }
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _kPrimaryOrange,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      elevation: 0,
                    ),
                    child: Text(
                      _currentStep == _guideSteps.length - 1
                          ? 'Got It!'
                          : 'Next',
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 16,
                      ),
                    ),
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

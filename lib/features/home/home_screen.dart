import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'dart:convert';
import 'package:atmos_trs_system/config/user_profile_storage.dart';
import 'package:atmos_trs_system/config/auth_config.dart';
import 'package:atmos_trs_system/services/announcement_notification_sync.dart';
import 'package:atmos_trs_system/services/notification_badge_notifier.dart';
import 'package:atmos_trs_system/services/notification_firestore_service.dart';
import 'package:atmos_trs_system/services/profile_photo_hydration.dart';
import 'package:atmos_trs_system/services/tourist_profile_hydration.dart';
import 'package:atmos_trs_system/models/tourist_spot_firestore.dart';
import 'package:atmos_trs_system/services/tourist_spots_repository.dart';
import 'package:atmos_trs_system/services/tourist_activity_firestore_sync.dart';
import 'package:atmos_trs_system/services/user_activity_service.dart'
    as activity;
import 'package:atmos_trs_system/screens/vr_webview_screen.dart';
import 'package:atmos_trs_system/screens/municipality_map_and_spots_screen.dart';
import 'package:atmos_trs_system/features/explore/explore_screen.dart'
    show kMockSpots;
import 'package:atmos_trs_system/features/tourism/tourist_spot_detail_screen.dart';
import 'package:atmos_trs_system/config/app_theme.dart';
import 'package:atmos_trs_system/config/app_theme_controller.dart';
import 'package:atmos_trs_system/config/vr_tour_config.dart';
import 'package:atmos_trs_system/config/atmos_brand_typography.dart';
import 'package:atmos_trs_system/services/weather_service.dart';
import 'package:atmos_trs_system/services/qr_checkin_service.dart';
import 'package:atmos_trs_system/services/qr_checkin_ui.dart';

const Color _kDarkText = Color(0xFF111827);
const Color _kMuted = Color(0xFF6B7280);
const Color _kPageBg = Color(0xFFF8FAFC);

/// Misamis Occidental center (used e.g. for VR preview location)
const double _kMapCenterLat = 8.3377;
const double _kMapCenterLng = 123.7072;

/// Lets [PageView] respond to mouse drag / trackpad on web and desktop.
class _FeaturedCarouselScrollBehavior extends MaterialScrollBehavior {
  const _FeaturedCarouselScrollBehavior();

  @override
  Set<PointerDeviceKind> get dragDevices => {
    PointerDeviceKind.touch,
    PointerDeviceKind.mouse,
    PointerDeviceKind.stylus,
    PointerDeviceKind.trackpad,
  };
}

/// Seven priority VR / featured destinations on the home Discover carousel.
final List<Map<String, dynamic>> _featuredDestinations = [
  {
    'name': 'Baliangao Beach',
    'description': 'Pristine white-sand beaches and rich marine sanctuaries',
    'detail':
        'Baliangao is a coastal, 5th-class municipality in Misamis Occidental, Philippines. Home to around 18,500 residents, it is celebrated for its pristine white-sand beaches, rich marine sanctuaries, and eco-tourism.',
    'image': 'assets/images/Baliangao - Cabgan Island.jpg',
    'rating': 4.8,
    'category': 'Beach',
  },
  {
    'name': 'Don Victoriano',
    'description': 'Summer Capital with cool climate and scenic nature trails',
    'detail':
        'Don Victoriano Chiongbian (often simply called Don Victoriano) is a landlocked, mountainous 4th-class municipality in Misamis Occidental, Philippines. Known as the "Summer Capital" or "Hidden Paradise" of the province, it sits at the foot of Mount Malindang at a high elevation, offering a cool climate, strawberry farms, and scenic nature trails.',
    'image': 'assets/images/Piduan Falls Donvic.jpg',
    'rating': 4.9,
    'category': 'Mountain',
  },
  {
    'name': 'Ozamiz Wellness Park',
    'description': 'Gem of the Panguil Bay and gateway to Northwestern Mindanao',
    'detail':
        'Ozamiz is a bustling 3rd-class coastal component city in Misamis Occidental, Philippines. Known as the "Gem of the Panguil Bay" and the "Gateway to Northwestern Mindanao," it is the largest and most populous city in the province. It serves as a major regional hub for commerce, education, and transportation.',
    'image': 'assets/images/ozamis city.webp',
    'rating': 4.7,
    'category': 'Park',
  },
  {
    'name': 'Tangub City',
    'description': 'Christmas Symbols Capital and Asenso Global Gardens',
    'detail':
        'Tangub City, famously known as the "Christmas Symbols Capital of the Philippines," is a 4th-class component city in Misamis Occidental. Nestled between the majestic Mt. Malindang Range and the serene Panguil Bay, it is a peaceful, mostly agricultural city with an approximate population of 68,000 residents.',
    'image': 'assets/images/Asenso Global Garden 1.png',
    'rating': 4.8,
    'category': 'Park',
  },
  {
    'name': 'Jimenez Church',
    'description': 'National Cultural Treasure, Baroque Roman Catholic church',
    'detail':
        'Saint John the Baptist Parish Church, commonly known as Jimenez Church, is a late-19th century, Baroque Roman Catholic church located at Barangay Nacional, Jimenez, Misamis Occidental, Philippines. The parish church, under the patronage of Saint John the Baptist, is under the jurisdiction of the Archdiocese of Ozamis. The church was declared a National Cultural Treasure of the Philippines in 2001.',
    'image': 'assets/images/Jimenez - St. John the Baptist Church.jpg',
    'rating': 4.9,
    'category': 'Historical',
  },
  {
    'name': 'Oroquieta City Plaza',
    'description': 'Heart of the City of Good Life and provincial capital',
    'detail':
        'Oroquieta City is the coastal capital of Misamis Occidental, Philippines, known as the "City of Good Life". It serves as the provincial government and agricultural trading hub. Home to over 72,000 residents, the city seamlessly blends urban progress with rich history and natural landscapes.',
    'image': 'assets/images/oroquieta City plaza.jpeg',
    'rating': 4.7,
    'category': 'Historical',
  },
  {
    'name': 'AMORAP',
    'description': 'Maldives-inspired eco-luxury adventure park in Sinacaban',
    'detail':
        'AMORAP—or the Asenso Misamis Occidental Recreation and Adventure Park—is a massive, Maldives-inspired eco-luxury destination in Sinacaban, Misamis Occidental. Located just 30 minutes from Ozamiz City Airport, it features coastal overwater villas, a 9-hole golf course, a bird sanctuary, and extensive leisure facilities.',
    'image': 'assets/images/AMORAP.jpg',
    'rating': 4.8,
    'category': 'Park',
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
  'oroquieta': 'assets/images/oroquieta City plaza.jpeg',
  'oroquieta_city': 'assets/images/oroquieta City plaza.jpeg',
  'ozamiz': 'assets/images/ozamis city.webp',
  'ozamis_city': 'assets/images/ozamis city.webp',
  'tangub': 'assets/images/Asenso Global Garden 1.png',
  'tangub_city': 'assets/images/Asenso Global Garden 1.png',
  'clarin': 'assets/images/clarin.jpg',
  'baliangao': 'assets/images/Baliangao - Cabgan Island.jpg',
  'sapang_dalaga': 'assets/images/Sapang Dalaga.png',
  'sapangdalaga': 'assets/images/Sapang Dalaga.png',
  'dvc': 'assets/images/Piduan Falls Donvic.jpg',
  'don_victoriano': 'assets/images/Piduan Falls Donvic.jpg',
  'jimenez': 'assets/images/Jimenez - St. John the Baptist Church.jpg',
  'calamba': 'assets/images/CALAMBA.jpg',
  'concepcion': 'assets/images/conception.png',
  'plaridel': 'assets/images/PLARIDEL.jpg',
  'sinacaban': 'assets/images/AMORAP.jpg',
  'amorap': 'assets/images/AMORAP.jpg',
  'tudela': 'assets/images/Tudela Village.webp',
  'panaon': 'assets/images/Panaon.webp',
};

String _spotImage(TouristSpotFirestore spot) {
  final asset = _kAttractionAssetImages[spot.id];
  if (asset != null && asset.isNotEmpty) return asset;
  return spot.image?.trim() ?? '';
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
    image: 'assets/images/ozamis city.webp',
    vrLink: '',
  ),
  TouristSpotFirestore(
    id: 'tangub_city',
    name: 'Tangub City',
    category: 'Historical',
    latitude: 8.0656,
    longitude: 123.7547,
    rating: 4.6,
    image: 'assets/images/Asenso Global Garden 1.png',
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

/// Image URL for persisted visits / recently viewed: prefer bundled assets for known spots.
String? _resolveImageForVisitRecord(activity.VisitRecord entry) {
  for (final s in _sampleSpots) {
    if (s.id == entry.spotId) {
      final r = _spotImage(s);
      if (r.isNotEmpty) return r;
    }
  }
  final mapped = _kAttractionAssetImages[entry.spotId];
  if (mapped != null && mapped.isNotEmpty) return mapped;
  final u = entry.imageUrl?.trim();
  return (u != null && u.isNotEmpty) ? u : null;
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  UserProfile? _userProfile = UserProfileStorage.cachedProfile;
  bool _profileLoaded = UserProfileStorage.cachedProfile != null;
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

  bool get _isMobileLayout => MediaQuery.sizeOf(context).width < 600;

  PreferredSizeWidget _mobileSheetAppBar(
    BuildContext context, {
    required String title,
    String? subtitle,
    List<Widget>? actions,
  }) {
    return AppBar(
      backgroundColor: Colors.white,
      elevation: 0,
      scrolledUnderElevation: 0,
      leadingWidth: 80,
      leading: Padding(
        padding: const EdgeInsets.only(left: 12),
        child: Center(
          child: FilledButton(
            onPressed: () => Navigator.pop(context),
            style: FilledButton.styleFrom(
              backgroundColor: AppTheme.brandOrange,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              minimumSize: const Size(0, 36),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            child: const Text(
              'Back',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
            ),
          ),
        ),
      ),
      title: subtitle == null
          ? Text(
              title,
              style: const TextStyle(
                color: _kDarkText,
                fontSize: 18,
                fontWeight: FontWeight.w700,
              ),
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: _kDarkText,
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Text(
                  subtitle,
                  style: TextStyle(
                    color: Colors.grey.shade600,
                    fontSize: 13,
                  ),
                ),
              ],
            ),
      actions: actions,
    );
  }

  MisamisOccidentalWeather? _weather;
  bool _weatherLoading = true;

  // Featured Destinations category filter
  int _selectedFeaturedCategoryIndex = 0;

  @override
  void initState() {
    super.initState();
    if (_userProfile == null) {
      _restoreProfileFromDisk();
    }
    _loadAllData();
    _fetchWeather();
  }

  Future<void> _restoreProfileFromDisk() async {
    final cached = await UserProfileStorage.getUserProfile();
    if (cached != null && mounted) {
      setState(() {
        _userProfile = cached;
        _profileLoaded = cached.firstName.trim().isNotEmpty;
      });
    }
  }

  Future<void> _fetchWeather() async {
    setState(() => _weatherLoading = true);
    try {
      final w = await MisamisOccidentalWeather.fetch();
      if (mounted) {
        setState(() {
          _weather = w;
          _weatherLoading = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _weather ??= MisamisOccidentalWeather.fallback();
          _weatherLoading = false;
        });
      }
    }
  }

  IconData _weatherIconForCode(int code) {
    if (code == 0 || code == 1) return Icons.wb_sunny_rounded;
    if (code == 2 || code == 3) return Icons.cloud_rounded;
    if (code >= 45 && code <= 48) return Icons.blur_on;
    if (code >= 51 && code <= 67) return Icons.grain;
    if (code >= 71 && code <= 77) return Icons.ac_unit;
    if (code >= 80 && code <= 82) return Icons.beach_access;
    if (code >= 95) return Icons.flash_on;
    return Icons.wb_cloudy_rounded;
  }

  List<Map<String, dynamic>> get _filteredFeaturedDestinations {
    final selected = _featuredCategories[_selectedFeaturedCategoryIndex];
    if (selected == 'All') return _featuredDestinations;
    final selectedLower = selected.toLowerCase();
    return _featuredDestinations
        .where(
          (d) => (d['category'] as String?)?.toLowerCase() == selectedLower,
        )
        .toList();
  }

  void _goToFeaturedPage(int delta) {
    final count = _filteredFeaturedDestinations.length;
    if (count <= 1 || !_featuredController.hasClients) return;
    final next = (_currentFeaturedIndex + delta).clamp(0, count - 1);
    if (next == _currentFeaturedIndex) return;
    _featuredController.animateToPage(
      next,
      duration: const Duration(milliseconds: 320),
      curve: Curves.easeOutCubic,
    );
  }

  Widget _featuredCarouselNavButton({
    required IconData icon,
    required VoidCallback onPressed,
    required bool enabled,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: enabled ? onPressed : null,
        borderRadius: BorderRadius.circular(24),
        child: Ink(
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: enabled ? 0.95 : 0.5),
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.12),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: Icon(
              icon,
              size: 26,
              color: enabled ? AppTheme.primary : Colors.grey.shade400,
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _loadAllData() async {
    setState(() => _isLoading = true);
    await _loadUserProfile();
    await Future.wait([
      _loadUserStats(),
      _loadRecentVisits(),
      _loadRecentlyViewed(),
      _loadNotifications(),
      _loadSavedSpots(),
    ]);
    if (mounted) {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _loadUserProfile() async {
    final authUser = FirebaseAuth.instance.currentUser;
    var profile = await TouristProfileHydration.loadProfile(
      email: authUser?.email,
    );
    profile = await ProfilePhotoHydration.mergeFirestorePhotoUrl(profile);
    if (mounted) {
      setState(() {
        _userProfile = profile ?? UserProfileStorage.cachedProfile;
        _profileLoaded = true;
      });
    }
  }

  String _headerFirstName() {
    final cached = _userProfile?.firstName.trim();
    if (cached != null && cached.isNotEmpty) return cached;

    final auth = FirebaseAuth.instance.currentUser;
    final display = auth?.displayName?.trim();
    if (display != null && display.isNotEmpty) {
      return display.split(RegExp(r'\s+')).first;
    }
    final email = auth?.email?.trim();
    if (email != null && email.contains('@')) {
      final local = email.split('@').first;
      if (local.isNotEmpty) {
        return local[0].toUpperCase() + local.substring(1);
      }
    }

    if (!_profileLoaded) return '';
    return 'Guest';
  }

  Future<void> _loadUserStats() async {
    final stats = await activity.UserActivityService.getUserStats();
    if (mounted) {
      setState(() => _userStats = stats);
    }
  }

  Future<void> _loadRecentVisits() async {
    final uid =
        AuthConfig.currentUserUid ?? FirebaseAuth.instance.currentUser?.uid;
    if (uid != null && uid.isNotEmpty) {
      await TouristActivityFirestoreSync.mergeFromCloud(uid);
    }
    final visits =
        await activity.UserActivityService.syncVisitedSpotsFromQrCheckins();
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
    final uid =
        AuthConfig.currentUserUid ?? FirebaseAuth.instance.currentUser?.uid;
    final notifications =
        await AnnouncementNotificationSync.loadMergedForHome(userId: uid);
    final unread = notifications.where((n) => !n.isRead).length;
    if (mounted) {
      setState(() {
        _notifications = notifications;
        _unreadNotifications = unread;
      });
    }
    await NotificationBadgeNotifier.instance.refresh(userId: uid);
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
          backgroundColor: isSaved ? AppTheme.primary : Colors.grey.shade700,
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  Future<void> _checkInToSpot(TouristSpotFirestore spot) async {
    final firestoreSpot = await QRCheckInService.getSpotById(spot.id);
    final lat = firestoreSpot?.latitude ?? spot.latitude;
    final lng = firestoreSpot?.longitude ?? spot.longitude;

    final locationError = await QRCheckInService.verifyProximityToTouristSpot(
      latitude: lat,
      longitude: lng,
      spotLabel: spot.name,
    );
    if (!mounted) return;
    if (locationError != null) {
      showQRCheckInErrorDialog(context, locationError);
      return;
    }

    final municipalityId = firestoreSpot != null &&
            firestoreSpot.municipalityId.isNotEmpty
        ? firestoreSpot.municipalityId
        : QRCheckInService.resolveMunicipalityIdForSpot(
            spotDocId: spot.id,
            municipality: spot.municipality,
            municipalityId: spot.municipalityId,
            displayName: spot.name,
          );

    final ok = await performQRCheckIn(
      context,
      municipalityId: municipalityId,
      spotId: spot.id,
      spotName: spot.name,
      municipality: spot.municipality.isNotEmpty
          ? spot.municipality
          : spot.name,
    );
    if (!ok || !mounted) return;

    await activity.UserActivityService.addVisit(
      spotId: spot.id,
      spotName: spot.name,
      category: spot.category,
      imageUrl: _spotImage(spot),
    );

    await _loadUserStats();
    await _loadRecentVisits();
  }

  void _showQRGuide(BuildContext context) {
    final sheet = _QRGuideBottomSheet(
      userProfile: _userProfile,
      fullScreen: _isMobileLayout,
    );
    if (_isMobileLayout) {
      Navigator.of(context).push<void>(
        MaterialPageRoute<void>(
          fullscreenDialog: true,
          builder: (_) => sheet,
        ),
      );
      return;
    }
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => sheet,
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

  Widget _buildSectionHeader({
    required String title,
    String? subtitle,
    required IconData icon,
    Widget? trailing,
    bool showAccentBar = true,
  }) {
    final accent = AppTheme.primary;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (showAccentBar) ...[
          Container(
            width: 4,
            height: 40,
            decoration: BoxDecoration(
              color: accent,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 12),
        ],
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

  Widget _buildQuickActionsRow() {
    final accent = AppTheme.primary;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          Expanded(
            child: _quickActionTile(
              icon: Icons.qr_code_scanner_rounded,
              label: 'How to scan?',
              accent: accent,
              onTap: () => _showQRGuide(context),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: _quickActionTile(
              icon: Icons.map_rounded,
              label: 'All places',
              accent: accent,
              onTap: _showAllDestinationsDialog,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: _quickActionTile(
              icon: Icons.bookmark_rounded,
              label: 'Saved',
              accent: accent,
              onTap: _showSavedSpotsDialog,
            ),
          ),
        ],
      ),
    );
  }

  Widget _quickActionTile({
    required IconData icon,
    required String label,
    required Color accent,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Ink(
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: accent.withValues(alpha: 0.15)),
            boxShadow: [
              BoxShadow(
                color: accent.withValues(alpha: 0.06),
                blurRadius: 10,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: Column(
            children: [
              Icon(icon, color: accent, size: 26),
              const SizedBox(height: 6),
              Text(
                label,
                style: TextStyle(
                  color: accent,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }

  bool get _compactSpotImages => MediaQuery.sizeOf(context).width < 600;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: AppThemeController.instance,
      builder: (context, _) {
        final accent = AppTheme.primary;

        return Scaffold(
          backgroundColor: _kPageBg,
          body: Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  accent.withValues(alpha: 0.06),
                  _kPageBg,
                ],
              ),
            ),
            child: SafeArea(
              child: Column(
                children: [
                  _buildHeader(context),
                  Expanded(
                    child: RefreshIndicator(
                      color: accent,
                      onRefresh: _loadAllData,
                      child: _isLoading
                          ? Center(
                              child: CircularProgressIndicator(color: accent),
                            )
                          : SingleChildScrollView(
                              physics: const AlwaysScrollableScrollPhysics(),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const SizedBox(height: 8),
                                  _buildWeatherWidget(),
                                  const SizedBox(height: 16),
                                  _buildQuickActionsRow(),
                                  const SizedBox(height: 20),
                                  _buildProgressSection(),
                                  const SizedBox(height: 24),
                                  _buildDiscoverSection(),
                                  const SizedBox(height: 24),
                                  _buildRecentlyViewedSection(),
                                  const SizedBox(height: 20),
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
      },
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
                    color: AppTheme.primary,
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
    final userName = _headerFirstName();
    final accent = AppTheme.primary;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 16, 14, 16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: accent.withValues(alpha: 0.2)),
          boxShadow: [
            BoxShadow(
              color: accent.withValues(alpha: 0.1),
              blurRadius: 18,
              offset: const Offset(0, 6),
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
                      AppTheme.primary.withOpacity(0.15),
                      AppTheme.primary.withOpacity(0.05),
                    ],
                  ),
                  border: Border.all(
                    color: AppTheme.primary.withOpacity(0.35),
                    width: 2,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: AppTheme.primary.withOpacity(0.2),
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
                  if (userName.isEmpty)
                    Container(
                      height: 28,
                      width: 120,
                      decoration: BoxDecoration(
                        color: Colors.grey.shade200,
                        borderRadius: BorderRadius.circular(6),
                      ),
                    )
                  else
                    Text(
                      userName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AtmosBrandTypography.displayTitle(
                        color: _kDarkText,
                        fontSize: 30,
                        letterSpacing: 0.5,
                      ),
                    ),
                  const SizedBox(height: 4),
                  Text(
                    'Welcome to Asenso Misamis Occidental',
                    style: const TextStyle(
                      color: _kMuted,
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
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
              color: AppTheme.primary.withOpacity(0.12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: AppTheme.primary, size: 24),
          ),
          if (hasNotification)
            Positioned(
              top: -4,
              right: -4,
              child: Container(
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: AppTheme.primary,
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
                        await NotificationBadgeNotifier.instance.refresh();
                        if (mounted) setState(() {});
                      },
                      child: Text(
                        'Clear All',
                        style: TextStyle(color: AppTheme.primary),
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
                                final id = notification.id;
                                if (id.startsWith('ann_')) {
                                  await activity
                                      .UserActivityService.markNotificationAsRead(
                                    id,
                                  );
                                } else {
                                  await NotificationFirestoreService.markAsRead(
                                    id,
                                  );
                                  await activity
                                      .UserActivityService.markNotificationAsRead(
                                    id,
                                  );
                                }
                                await _loadNotifications();
                                await NotificationBadgeNotifier.instance
                                    .refresh();
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
        color = AppTheme.primary;
        break;
      case activity.NotificationType.event:
        icon = Icons.event_rounded;
        color = AppTheme.primary;
        break;
      case activity.NotificationType.weather:
        icon = Icons.wb_sunny_rounded;
        color = AppTheme.primary;
        break;
      case activity.NotificationType.checkin:
        icon = Icons.check_circle_rounded;
        color = AppTheme.primary;
        break;
      case activity.NotificationType.system:
        icon = Icons.info_rounded;
        color = AppTheme.primary;
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
              : AppTheme.primary.withOpacity(0.05),
          borderRadius: BorderRadius.circular(12),
          border: notification.isRead
              ? null
              : Border.all(color: AppTheme.primary.withOpacity(0.2)),
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
                          decoration: BoxDecoration(
                            color: AppTheme.primary,
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

  Widget _buildProgressSection() {
    final accent = AppTheme.primary;
    final accentDark = AppTheme.primaryDark;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: accent.withValues(alpha: 0.12)),
          boxShadow: [
            BoxShadow(
              color: accent.withValues(alpha: 0.06),
              blurRadius: 14,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildSectionHeader(
              title: 'Your journey',
              subtitle: 'Visits, badges, and saved spots',
              icon: Icons.insights_rounded,
              showAccentBar: false,
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: _buildStatCard(
                    'Visited',
                    _userStats.placesVisited.toString(),
                    Icons.place_rounded,
                    accent,
                    onTap: _showVisitedPlacesDialog,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _buildStatCard(
                    'Badges',
                    _userStats.badgesEarned.toString(),
                    Icons.emoji_events_rounded,
                    accentDark,
                    onTap: _showBadgesDialog,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: _buildStatCard(
                    'Days',
                    _userStats.daysAsTourist.toString(),
                    Icons.calendar_today_rounded,
                    accent,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _buildStatCard(
                    'Saved',
                    _userStats.savedSpots.toString(),
                    Icons.bookmark_rounded,
                    accentDark,
                    onTap: _showSavedSpotsDialog,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDiscoverSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: _buildSectionHeader(
            title: 'Discover',
            subtitle: 'Seven priority destinations for virtual tours',
            icon: Icons.auto_awesome_rounded,
            trailing: TextButton(
              onPressed: _showAllDestinationsDialog,
              child: Text(
                'See all',
                style: TextStyle(
                  color: AppTheme.primary,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 12),
        _buildFeaturedCategoryChips(),
        const SizedBox(height: 12),
        _buildFeaturedSection(),
      ],
    );
  }

  Widget _buildVisitedPlacesBody() {
    if (_recentVisits.isEmpty) {
      return Center(
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
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
      itemCount: _recentVisits.length,
      itemBuilder: (context, index) {
        return _buildVisitListItem(_recentVisits[index]);
      },
    );
  }

  void _showVisitedPlacesDialog() async {
    if (!mounted) return;
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => const Center(
        child: Card(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircularProgressIndicator(),
                SizedBox(height: 16),
                Text('Loading your visits from the database…'),
              ],
            ),
          ),
        ),
      ),
    );

    final uid =
        AuthConfig.currentUserUid ?? FirebaseAuth.instance.currentUser?.uid;
    if (uid != null && uid.isNotEmpty) {
      await TouristActivityFirestoreSync.mergeFromCloud(uid);
    }
    final visits =
        await activity.UserActivityService.syncVisitedSpotsFromQrCheckins();
    await _loadUserStats();
    if (!mounted) return;
    Navigator.of(context, rootNavigator: true).pop();
    setState(() => _recentVisits = visits);

    if (_isMobileLayout) {
      Navigator.of(context).push<void>(
        MaterialPageRoute<void>(
          fullscreenDialog: true,
          builder: (ctx) => Scaffold(
            backgroundColor: Colors.white,
            appBar: _mobileSheetAppBar(
              ctx,
              title: 'Visited Places',
              subtitle: visits.isEmpty
                  ? null
                  : '${visits.length} place${visits.length == 1 ? '' : 's'}',
            ),
            body: _buildVisitedPlacesBody(),
          ),
        ),
      );
      return;
    }

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
                      color: AppTheme.brandOrange.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(
                      Icons.place_rounded,
                      color: AppTheme.brandOrange,
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
            Expanded(child: _buildVisitedPlacesBody()),
          ],
        ),
      ),
    );
  }

  /// Opens spot details for a QR check-in / visited record.
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

    for (final s in _sampleSpots) {
      if (s.id == visit.spotId) {
        _showSpotBottomSheet(s);
        return;
      }
    }

    final fromFirestore =
        await TouristSpotsRepository.getSpotById(visit.spotId);
    if (fromFirestore != null && mounted) {
      _showSpotBottomSheet(fromFirestore);
      return;
    }

    if (!mounted) return;
    final image = _resolveImageForVisitRecord(visit);
    _showSpotBottomSheet(
      TouristSpotFirestore(
        id: visit.spotId,
        name: visit.spotName,
        category: visit.category,
        latitude: _kMapCenterLat,
        longitude: _kMapCenterLng,
        rating: 4.5,
        image: image,
        municipality: visit.category,
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
      child: Material(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () => _openVisitedSpot(visit),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: _buildSpotImage(
              _resolveImageForVisitRecord(visit),
              width: 50,
              height: 50,
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
                        color: AppTheme.primary.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        visit.category,
                        style: TextStyle(
                          color: AppTheme.primary,
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
          Icon(Icons.check_circle, color: AppTheme.primary, size: 20),
          Icon(Icons.chevron_right, color: Colors.grey.shade400, size: 22),
            ],
          ),
        ),
      ),
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
                      color: AppTheme.primary.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(
                      Icons.emoji_events_rounded,
                      color: AppTheme.primary,
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
            AppTheme.primary.withOpacity(0.2),
            AppTheme.primary.withOpacity(0.08),
          ],
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.primary.withOpacity(0.4)),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.emoji_events_rounded,
            color: AppTheme.primary,
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

  Widget _buildSavedSpotsBody() {
    return StreamBuilder<List<TouristSpotFirestore>>(
      stream: TouristSpotsRepository.streamTouristSpots(),
      builder: (context, snapshot) {
        final firestoreSpots = snapshot.data ?? [];
        final spots = firestoreSpots.isEmpty ? _sampleSpots : firestoreSpots;
        final savedSpots =
            spots.where((s) => _savedSpotIds.contains(s.id)).toList();

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
            return _buildSavedSpotItem(savedSpots[index]);
          },
        );
      },
    );
  }

  void _showSavedSpotsDialog() {
    if (_isMobileLayout) {
      Navigator.of(context).push<void>(
        MaterialPageRoute<void>(
          fullscreenDialog: true,
          builder: (ctx) => Scaffold(
            backgroundColor: Colors.white,
            appBar: _mobileSheetAppBar(ctx, title: 'Saved Spots'),
            body: _buildSavedSpotsBody(),
          ),
        ),
      );
      return;
    }

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
                      color: AppTheme.brandOrange.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(
                      Icons.bookmark_rounded,
                      color: AppTheme.brandOrange,
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
            Expanded(child: _buildSavedSpotsBody()),
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
                            color: AppTheme.primary.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            spot.category,
                            style: TextStyle(
                              color: AppTheme.primary,
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Icon(Icons.star, size: 12, color: AppTheme.primary),
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
                icon: Icon(Icons.bookmark, color: AppTheme.primary),
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
        borderRadius: BorderRadius.circular(14),
        child: Ink(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.06),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: color.withValues(alpha: 0.18)),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, color: color, size: 20),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: _kMuted,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      value,
                      style: TextStyle(
                        fontSize: 20,
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
    return SizedBox(
      height: 42,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
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
                      if (_featuredController.hasClients) {
                        _featuredController.jumpToPage(0);
                      }
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
                            ? LinearGradient(
                                colors: [AppTheme.primary, AppTheme.primaryDark],
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
                                  color: AppTheme.primary.withOpacity(0.35),
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
    );
  }

  Widget _buildFeaturedSection() {
    final items = _filteredFeaturedDestinations;
    if (items.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.05),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Row(
            children: [
              Icon(
                Icons.info_outline,
                color: AppTheme.primary.withOpacity(0.9),
                size: 20,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'No featured destinations for this category yet.',
                  style: TextStyle(color: Colors.grey.shade700, fontSize: 13),
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
        SizedBox(
          height: _compactSpotImages ? 168 : 228,
          child: LayoutBuilder(
            builder: (context, constraints) {
              final showNav = constraints.maxWidth >= 520 && items.length > 1;
              return Stack(
                alignment: Alignment.center,
                clipBehavior: Clip.none,
                children: [
                  ScrollConfiguration(
                    behavior: const _FeaturedCarouselScrollBehavior(),
                    child: PageView.builder(
                      controller: _featuredController,
                      scrollDirection: Axis.horizontal,
                      allowImplicitScrolling: true,
                      onPageChanged: (index) =>
                          setState(() => _currentFeaturedIndex = index),
                      itemCount: items.length,
                      itemBuilder: (context, index) =>
                          _buildFeaturedCard(items[index]),
                    ),
                  ),
                  if (showNav) ...[
                    Positioned(
                      left: 4,
                      child: _featuredCarouselNavButton(
                        icon: Icons.chevron_left_rounded,
                        enabled: _currentFeaturedIndex > 0,
                        onPressed: () => _goToFeaturedPage(-1),
                      ),
                    ),
                    Positioned(
                      right: 4,
                      child: _featuredCarouselNavButton(
                        icon: Icons.chevron_right_rounded,
                        enabled: _currentFeaturedIndex < items.length - 1,
                        onPressed: () => _goToFeaturedPage(1),
                      ),
                    ),
                  ],
                ],
              );
            },
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
                    ? LinearGradient(
                        colors: [AppTheme.primary, AppTheme.primaryDark],
                      )
                    : null,
                color: _currentFeaturedIndex == index
                    ? null
                    : Colors.grey.shade300,
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

  void _showFeaturedDestinationDetail(Map<String, dynamic> destination) {
    final isMobile = MediaQuery.sizeOf(context).width < 600;
    if (isMobile) {
      Navigator.of(context).push<void>(
        MaterialPageRoute<void>(
          builder: (context) => _FeaturedDestinationFullScreenPage(
            destination: destination,
            buildImage: _buildFeaturedCardImage,
          ),
        ),
      );
      return;
    }

    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.55,
        minChildSize: 0.35,
        maxChildSize: 0.92,
        builder: (context, scrollController) => Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: ListView(
            controller: scrollController,
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
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
              _FeaturedDestinationDetailBody(
                name: destination['name'] as String,
                category: destination['category'] as String,
                rating: destination['rating'],
                detail: destination['detail'] as String? ??
                    destination['description'] as String,
                image: destination['image'] as String,
                buildImage: _buildFeaturedCardImage,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFeaturedCard(Map<String, dynamic> destination) {
    return GestureDetector(
      onTap: () => _showFeaturedDestinationDetail(destination),
      child: Container(
      margin: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        boxShadow: [
          BoxShadow(
            color: AppTheme.primary.withOpacity(0.15),
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
                  color: AppTheme.primary,
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
                      Icon(Icons.star, color: AppTheme.primary, size: 16),
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
    ),
    );
  }

  Widget _buildWeatherWidget() {
    final showInitialLoading = _weatherLoading && _weather == null;
    final w = _weather ?? MisamisOccidentalWeather.fallback();
    final mainIcon = _weatherIconForCode(w.weatherCode);
    final bgIcon = w.weatherCode >= 95
        ? Icons.flash_on
        : (w.weatherCode >= 3 ? Icons.cloud_rounded : Icons.wb_sunny_rounded);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(22),
          onTap: _fetchWeather,
          child: Ink(
            padding: const EdgeInsets.fromLTRB(18, 18, 18, 18),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  AppTheme.primary,
                  AppTheme.primaryDark,
                  AppTheme.primaryDark,
                ],
              ),
              borderRadius: BorderRadius.circular(22),
              boxShadow: [
                BoxShadow(
                  color: AppTheme.primary.withOpacity(0.35),
                  blurRadius: 20,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
            child: Opacity(
              opacity: _weatherLoading && _weather != null ? 0.88 : 1,
              child: Stack(
                children: [
                  Positioned(
                    right: -20,
                    top: -20,
                    child: Icon(
                      bgIcon,
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
                        child: Icon(
                          showInitialLoading
                              ? Icons.wb_sunny_rounded
                              : mainIcon,
                          color: Colors.white,
                          size: 36,
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
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
                                if (_weatherLoading) ...[
                                  const SizedBox(width: 8),
                                  SizedBox(
                                    width: 12,
                                    height: 12,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Colors.white.withOpacity(0.9),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                            const SizedBox(height: 4),
                            showInitialLoading
                                ? SizedBox(
                                    height: 40,
                                    width: 40,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2.5,
                                      color: Colors.white.withOpacity(0.95),
                                    ),
                                  )
                                : Text(
                                    w.temperatureDisplay,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 36,
                                      fontWeight: FontWeight.w800,
                                      height: 1,
                                      letterSpacing: -1,
                                    ),
                                  ),
                            const SizedBox(height: 6),
                            Text(
                              showInitialLoading
                                  ? 'Loading current conditions…'
                                  : w.subtitle,
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
                          _weatherMini(
                            Icons.water_drop,
                            showInitialLoading ? '—' : w.humidityDisplay,
                          ),
                          const SizedBox(height: 8),
                          _weatherMini(
                            Icons.air,
                            showInitialLoading ? '—' : w.windDisplay,
                          ),
                        ],
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
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
      imageUrl: _spotImage(spot),
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
                                    color: AppTheme.primary.withOpacity(0.15),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Text(
                                    spot.category,
                                    style: TextStyle(
                                      color: AppTheme.primary,
                                      fontSize: 11,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Icon(
                                  Icons.star,
                                  size: 14,
                                  color: AppTheme.primary,
                                ),
                                const SizedBox(width: 2),
                                Text(
                                  spot.rating > 0
                                      ? spot.rating.toStringAsFixed(1)
                                      : '—',
                                  style: TextStyle(
                                    color: AppTheme.primary,
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
                                : AppTheme.primary,
                            backgroundColor: currentlySaved
                                ? AppTheme.primary
                                : null,
                            side: BorderSide(color: AppTheme.primary),
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
                          label: const Text('Register'),
                          style: FilledButton.styleFrom(
                            backgroundColor: AppTheme.primary,
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
                        backgroundColor: AppTheme.primary,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  if (resolveVrTourUrl(
                        vrLink: spot.vrLink,
                        spotId: spot.id,
                        spotName: spot.name,
                      ) !=
                      null)
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: () {
                          Navigator.pop(context);
                          openVrForTouristSpot(
                            context,
                            spotId: spot.id,
                            spotName: spot.name,
                            vrLink: spot.vrLink,
                          );
                        },
                        icon: const Icon(Icons.vrpano_rounded, size: 18),
                        label: const Text('Launch VR Tour'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppTheme.primary,
                          side: BorderSide(color: AppTheme.primary),
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
    if (_isMobileLayout) {
      Navigator.of(context).push<void>(
        MaterialPageRoute<void>(
          fullscreenDialog: true,
          builder: (ctx) => Scaffold(
            backgroundColor: Colors.white,
            appBar: _mobileSheetAppBar(
              ctx,
              title: 'All Destinations',
              subtitle: '${_sampleSpots.length} spots',
            ),
            body: ListView.builder(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
              itemCount: _sampleSpots.length,
              itemBuilder: (context, index) {
                return _buildDestinationListItem(
                  _sampleSpots[index],
                  listContext: ctx,
                );
              },
            ),
          ),
        ),
      );
      return;
    }

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
                        color: AppTheme.primary.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(
                        Icons.explore_rounded,
                        color: AppTheme.primary,
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

  Widget _buildDestinationListItem(
    TouristSpotFirestore spot, {
    BuildContext? listContext,
  }) {
    final isSaved = _savedSpotIds.contains(spot.id);
    final navContext = listContext ?? context;

    return GestureDetector(
      onTap: () {
        Navigator.pop(navContext);
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
                          color: AppTheme.primary.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          spot.category,
                          style: TextStyle(
                            color: AppTheme.primary,
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Icon(Icons.star, size: 14, color: AppTheme.primary),
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
                color: isSaved ? AppTheme.primary : Colors.grey.shade400,
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
    final accent = AppTheme.primary;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSectionHeader(
            title: 'Recently viewed',
            subtitle: 'Spots you opened from Home',
            icon: Icons.visibility_rounded,
          ),
          const SizedBox(height: 14),
          SizedBox(
            height: _recentlyViewed.isEmpty
                ? 132
                : (_compactSpotImages ? 148 : 168),
            child: _recentlyViewed.isEmpty
                ? Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 20,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(color: accent.withValues(alpha: 0.12)),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.travel_explore_rounded,
                          size: 40,
                          color: accent.withValues(alpha: 0.55),
                        ),
                        const SizedBox(width: 16),
                        const Expanded(
                          child: Text(
                            'Open any spot from All places or your lists — it will show up here.',
                            style: TextStyle(
                              color: _kMuted,
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
    final heroImage = _resolveImageForVisitRecord(entry);
    final cardW = _compactSpotImages ? 124.0 : 148.0;
    final imageH = _compactSpotImages ? 72.0 : 96.0;

    return GestureDetector(
      onTap: () => _openVisitedSpot(entry),
      child: Container(
        width: cardW,
        margin: const EdgeInsets.only(right: 12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: AppTheme.primary.withValues(alpha: 0.12),
          ),
          boxShadow: [
            BoxShadow(
              color: AppTheme.primary.withValues(alpha: 0.05),
              blurRadius: 10,
              offset: const Offset(0, 3),
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
                  child: heroImage != null && heroImage.isNotEmpty
                      ? _buildSpotImage(
                          heroImage,
                          width: cardW,
                          height: imageH,
                        )
                      : Container(
                          width: cardW,
                          height: imageH,
                          color: Colors.grey.shade200,
                          child: Icon(
                            Icons.place_rounded,
                            size: 36,
                            color: Colors.grey.shade500,
                          ),
                        ),
                ),
                Positioned(
                  left: 0,
                  top: 0,
                  bottom: 0,
                  child: Container(
                    width: 3,
                    color: AppTheme.primary,
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
    final accent = AppTheme.primary;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSectionHeader(
            title: 'Your trail',
            subtitle: 'Recent QR check-ins',
            icon: Icons.route_rounded,
            trailing: TextButton(
              onPressed: _showVisitedPlacesDialog,
              child: Text(
                'See all',
                style: TextStyle(
                  color: accent,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
          const SizedBox(height: 14),
          Container(
            height: _compactSpotImages ? 172 : 208,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: accent.withValues(alpha: 0.12)),
              boxShadow: [
                BoxShadow(
                  color: accent.withValues(alpha: 0.05),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
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
                              color: AppTheme.primary.withOpacity(0.08),
                              shape: BoxShape.circle,
                            ),
                            child: Icon(
                              Icons.terrain_rounded,
                              size: 40,
                              color: AppTheme.primary.withOpacity(0.7),
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
    final heroImage = _resolveImageForVisitRecord(visit);
    final cardW = _compactSpotImages ? 128.0 : 150.0;
    final imageH = _compactSpotImages ? 76.0 : 100.0;

    return GestureDetector(
      onTap: () => _openVisitedSpot(visit),
      child: Container(
        width: cardW,
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
                  child: heroImage != null && heroImage.isNotEmpty
                      ? _buildSpotImage(
                          heroImage,
                          width: cardW,
                          height: imageH,
                        )
                      : Container(
                          width: cardW,
                          height: imageH,
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
                    child: Icon(
                      Icons.check_circle,
                      color: AppTheme.primary,
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

/// Full-screen featured destination detail on mobile (e.g. Baliangao Beach).
class _FeaturedDestinationFullScreenPage extends StatelessWidget {
  const _FeaturedDestinationFullScreenPage({
    required this.destination,
    required this.buildImage,
  });

  final Map<String, dynamic> destination;
  final Widget Function(String imageUrl) buildImage;

  @override
  Widget build(BuildContext context) {
    final detail = destination['detail'] as String? ??
        destination['description'] as String;
    final image = destination['image'] as String;
    final name = destination['name'] as String;
    final category = destination['category'] as String;
    final rating = destination['rating'];
    final screenH = MediaQuery.sizeOf(context).height;

    return Scaffold(
      backgroundColor: Colors.white,
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            pinned: true,
            expandedHeight: screenH * 0.42,
            backgroundColor: Colors.white,
            foregroundColor: Colors.black87,
            leadingWidth: 80,
            leading: Padding(
              padding: const EdgeInsets.only(left: 12),
              child: Center(
                child: FilledButton(
                  onPressed: () => Navigator.pop(context),
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
            flexibleSpace: FlexibleSpaceBar(
              background: buildImage(image),
            ),
          ),
          SliverPadding(
            padding: EdgeInsets.fromLTRB(
              20,
              16,
              20,
              24 + MediaQuery.paddingOf(context).bottom,
            ),
            sliver: SliverToBoxAdapter(
              child: _FeaturedDestinationDetailBody(
                name: name,
                category: category,
                rating: rating,
                detail: detail,
                image: image,
                buildImage: buildImage,
                showHeroImage: false,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _FeaturedDestinationDetailBody extends StatelessWidget {
  const _FeaturedDestinationDetailBody({
    required this.name,
    required this.category,
    required this.rating,
    required this.detail,
    required this.image,
    required this.buildImage,
    this.showHeroImage = true,
  });

  final String name;
  final String category;
  final dynamic rating;
  final String detail;
  final String image;
  final Widget Function(String imageUrl) buildImage;
  final bool showHeroImage;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (showHeroImage) ...[
          ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: AspectRatio(
              aspectRatio: 16 / 9,
              child: buildImage(image),
            ),
          ),
          const SizedBox(height: 16),
        ],
        Row(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: AppTheme.brandOrange.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                category,
                style: const TextStyle(
                  color: AppTheme.brandOrange,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            const SizedBox(width: 8),
            const Icon(Icons.star, size: 16, color: AppTheme.brandOrange),
            const SizedBox(width: 4),
            Text(
              '$rating',
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Text(
          name,
          style: const TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.bold,
            color: _kDarkText,
          ),
        ),
        const SizedBox(height: 12),
        Text(
          detail,
          style: TextStyle(
            fontSize: 15,
            height: 1.5,
            color: Colors.grey.shade800,
          ),
        ),
      ],
    );
  }
}

class _QRGuideBottomSheet extends StatefulWidget {
  const _QRGuideBottomSheet({
    this.userProfile,
    this.fullScreen = false,
  });

  final UserProfile? userProfile;
  final bool fullScreen;

  @override
  State<_QRGuideBottomSheet> createState() => _QRGuideBottomSheetState();
}

class _QRGuideBottomSheetState extends State<_QRGuideBottomSheet> {
  int _currentStep = 0;
  final PageController _pageController = PageController();

  List<Map<String, dynamic>> _guideSteps() => [
        {
          'title': 'Your Tourist QR Code',
          'description':
              'This is your unique digital tourist ID. Show this QR code at any tourist spot for quick check-in.',
          'icon': Icons.qr_code_2_rounded,
          'color': AppTheme.primary,
        },
        {
          'title': 'Visit Tourist Spots',
          'description':
              'Explore beautiful destinations across Misamis Occidental. From beaches to mountains!',
          'icon': Icons.explore_rounded,
          'color': AppTheme.primaryLight,
        },
        {
          'title': 'Scan at Entrance',
          'description':
              'Look for the QR scanner at entrances. Present your QR code to staff for scanning.',
          'icon': Icons.qr_code_scanner_rounded,
          'color': AppTheme.primaryDark,
        },
        {
          'title': 'Check-in Complete!',
          'description':
              'Your visit is recorded automatically. View history in your profile and collect badges!',
          'icon': Icons.check_circle_rounded,
          'color': AppTheme.primary,
        },
      ];

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  Widget _guideBody(BuildContext context) {
    return Column(
      children: [
        if (!widget.fullScreen) ...[
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
        ],
        Expanded(
            child: PageView.builder(
              controller: _pageController,
              onPageChanged: (index) => setState(() => _currentStep = index),
              itemCount: _guideSteps().length,
              itemBuilder: (context, index) {
                final step = _guideSteps()[index];
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
                _guideSteps().length,
                (index) => AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  margin: const EdgeInsets.symmetric(horizontal: 4),
                  width: _currentStep == index ? 24 : 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: _currentStep == index
                        ? AppTheme.brandOrange
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
                        foregroundColor: AppTheme.brandOrange,
                        side: const BorderSide(color: AppTheme.brandOrange),
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
                      if (_currentStep < _guideSteps().length - 1) {
                        _pageController.nextPage(
                          duration: const Duration(milliseconds: 300),
                          curve: Curves.easeInOut,
                        );
                      } else {
                        Navigator.pop(context);
                      }
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.brandOrange,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      elevation: 0,
                    ),
                    child: Text(
                      _currentStep == _guideSteps().length - 1
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
    );
  }

  @override
  Widget build(BuildContext context) {
    final body = _guideBody(context);

    if (widget.fullScreen) {
      return Scaffold(
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
                onPressed: () => Navigator.pop(context),
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
          title: const Text(
            'How to Use Your QR',
            style: TextStyle(
              color: _kDarkText,
              fontSize: 18,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        body: SafeArea(child: body),
      );
    }

    return Container(
      height: MediaQuery.of(context).size.height * 0.75,
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: body,
    );
  }
}

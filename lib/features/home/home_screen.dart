import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'dart:async' show unawaited;
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
import 'package:atmos_trs_system/services/user_activity_service.dart'
    as activity;
import 'package:atmos_trs_system/screens/vr_webview_screen.dart';
import 'package:atmos_trs_system/screens/municipality_map_and_spots_screen.dart';
import 'package:atmos_trs_system/features/explore/explore_screen.dart'
    show kMockSpots;
import 'package:atmos_trs_system/models/tourist_destination_detail.dart';
import 'package:atmos_trs_system/screens/tourist_destination_detail_screen.dart';
import 'package:atmos_trs_system/config/app_theme.dart';
import 'package:atmos_trs_system/config/app_theme_controller.dart';
import 'package:atmos_trs_system/config/vr_tour_config.dart';
import 'package:atmos_trs_system/config/atmos_brand_typography.dart';
import 'package:atmos_trs_system/services/weather_service.dart';
import 'package:atmos_trs_system/services/qr_checkin_service.dart';
import 'package:atmos_trs_system/services/qr_checkin_ui.dart';
import 'package:atmos_trs_system/data/featured_destinations.dart';
import 'package:atmos_trs_system/data/misamis_occidental_display_spots.dart';
import 'package:atmos_trs_system/data/tourist_spot_image_catalog.dart';
import 'package:atmos_trs_system/widgets/spot_image.dart';
import 'package:atmos_trs_system/utils/visit_record_image_resolver.dart';
import 'package:atmos_trs_system/services/tourist_activity_firestore_sync.dart';
import 'package:atmos_trs_system/features/home/widgets/app_faq_sheet.dart';
import 'package:atmos_trs_system/utils/maps_directions_launcher.dart';

const Color _kDarkText = Color(0xFF111827);
const Color _kMuted = Color(0xFF6B7280);
const Color _kPageBg = Color(0xFFF8FAFC);
const double _kHomeCenterPanelMaxWidth = 480;

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
/// Categories for Featured Destinations filter.
const List<String> _featuredCategories = [
  'All',
  'Beach',
  'Historical',
  'Mountain',
  'Park',
  'Nature',
];

String _spotImage(TouristSpotFirestore spot) {
  return TouristSpotImageCatalog.displayUrlForSpot(spot);
}

String _humanizeSpotId(String id) {
  return id
      .replaceAll('_', ' ')
      .split(' ')
      .where((w) => w.isNotEmpty)
      .map(
        (w) => w.length == 1
            ? w.toUpperCase()
            : '${w[0].toUpperCase()}${w.substring(1)}',
      )
      .join(' ');
}

TouristSpotFirestore _spotFromFeatured(Map<String, dynamic> destination) {
  final spotId = destination['spotId']?.toString() ?? '';
  final known = MisamisOccidentalDisplaySpots.findByAnyId(
    spotId,
    featuredDestinations: kFeaturedDestinations,
  );
  if (known != null) {
    return known;
  }
  return TouristSpotFirestore(
    id: spotId,
    name: destination['name']?.toString() ?? _humanizeSpotId(spotId),
    category: destination['category']?.toString() ?? 'Spot',
    latitude: (destination['latitude'] as num?)?.toDouble() ?? _kMapCenterLat,
    longitude: (destination['longitude'] as num?)?.toDouble() ?? _kMapCenterLng,
    rating: (destination['rating'] as num?)?.toDouble() ?? 4.5,
    image: TouristSpotImageCatalog.displayUrl(
      preferred: destination['image']?.toString(),
      spotId: spotId,
      category: destination['category']?.toString(),
    ),
    municipality: destination['location']?.toString() ?? '',
    vrLink: '',
  );
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
  List<TouristSpotFirestore> _cachedFirestoreSpots = [];
  List<activity.VisitRecord> _recentlyViewed = [];
  List<activity.AppNotification> _notifications = [];
  Set<String> _savedSpotIds = {};
  int _unreadNotifications = 0;

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
              backgroundColor: AppTheme.primary,
              foregroundColor: AppTheme.onPrimary,
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
                  style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
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
    unawaited(_loadCachedStats());
    _loadAllData();
    _fetchWeather();
  }

  /// Instantly paints Visited / Badges / Days from on-device cache.
  Future<void> _loadCachedStats() async {
    final stats = await activity.UserActivityService.getUserStatsCached();
    if (!mounted) return;
    setState(() => _userStats = stats);
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
    if (selected == 'All') return kFeaturedDestinations;
    final selectedLower = selected.toLowerCase();
    return kFeaturedDestinations
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
    unawaited(_loadCachedStats());
    unawaited(_loadUserProfile());
    final uid =
        AuthConfig.currentUserUid ?? FirebaseAuth.instance.currentUser?.uid;

    unawaited(_loadFirestoreSpotsCache());
    unawaited(_loadSavedSpots());
    unawaited(_loadNotifications());

    if (uid != null && uid.isNotEmpty) {
      unawaited(_refreshJourneyFromCloud(uid));
    } else {
      unawaited(_loadRecentVisits());
      unawaited(_loadRecentlyViewed());
    }
  }

  /// Cloud merge + check-in sync — updates stats when done, without blocking first paint.
  Future<void> _refreshJourneyFromCloud(String uid) async {
    TouristActivityFirestoreSync.resetMergeCache();
    await TouristActivityFirestoreSync.mergeFromCloud(uid);
    if (!mounted) return;
    await activity.UserActivityService.syncVisitedSpotsFromQrCheckins();
    if (!mounted) return;
    await Future.wait([
      _loadUserStats(),
      _loadRecentVisits(skipSync: true),
      _loadRecentlyViewed(),
    ]);
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
    final stats = await activity.UserActivityService.getUserStatsCached();
    if (mounted) {
      setState(() => _userStats = stats);
    }
  }

  Map<String, TouristSpotFirestore> get _knownSpotsById =>
      MisamisOccidentalDisplaySpots.buildKnownSpotsMap(
        firestoreSpots: _cachedFirestoreSpots,
        featuredDestinations: kFeaturedDestinations,
      );

  List<TouristSpotFirestore> get _allDestinationSpots =>
      MisamisOccidentalDisplaySpots.mergeWithFirestore(_cachedFirestoreSpots);

  String _featuredImageForDestination(Map<String, dynamic> destination) {
    final explicit = destination['image']?.toString().trim();
    if (explicit != null && explicit.isNotEmpty) {
      return TouristSpotImageCatalog.normalizeAssetPath(explicit);
    }
    final spotId = destination['spotId']?.toString() ?? '';
    final known = MisamisOccidentalDisplaySpots.findByAnyId(
      spotId,
      firestoreSpots: _cachedFirestoreSpots,
      featuredDestinations: kFeaturedDestinations,
    );
    if (known != null) {
      return TouristSpotImageCatalog.displayUrlForSpot(known);
    }
    return TouristSpotImageCatalog.displayUrl(
      spotId: spotId,
      spotName: destination['name']?.toString(),
      category: destination['category']?.toString(),
    );
  }

  TouristSpotFirestore? _findSpotById(String spotId) =>
      MisamisOccidentalDisplaySpots.findByAnyId(
        spotId,
        firestoreSpots: _cachedFirestoreSpots,
        featuredDestinations: kFeaturedDestinations,
      );

  TouristSpotFirestore _spotForSavedId(String spotId) {
    return _findSpotById(spotId) ??
        TouristSpotFirestore(
          id: spotId,
          name: _humanizeSpotId(spotId),
          category: 'Spot',
          latitude: _kMapCenterLat,
          longitude: _kMapCenterLng,
          rating: 4.5,
          image: null,
          vrLink: '',
        );
  }

  void _openVisitRecord(activity.VisitRecord entry) {
    final mockMatches = kMockSpots.where((s) => s.id == entry.spotId);
    if (mockMatches.isNotEmpty) {
      _openDestinationDetail(
        detail: TouristDestinationDetail.fromExploreSpot(mockMatches.first),
      );
      return;
    }
    final known = _findSpotById(entry.spotId);
    if (known != null) {
      _openSpotDestinationDetail(known);
      return;
    }
    Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => MunicipalityMapAndSpotsScreen(
          municipalityIdOrName: entry.spotName,
        ),
      ),
    );
  }

  List<TouristSpotFirestore> get _spotsForVisitImages => _allDestinationSpots;

  Future<void> _loadFirestoreSpotsCache() async {
    final spots = await TouristSpotsRepository.getTouristSpots();
    if (mounted) {
      setState(() => _cachedFirestoreSpots = spots);
    }
  }

  String? _resolveImageForVisitRecord(activity.VisitRecord entry) {
    return VisitRecordImageResolver.resolve(entry, spots: _spotsForVisitImages);
  }

  Future<List<activity.VisitRecord>> _syncAndEnrichVisits({bool skipSync = false}) async {
    var visits = skipSync
        ? await activity.UserActivityService.getVisitedSpots()
        : await activity.UserActivityService.syncVisitedSpotsFromQrCheckins();
    if (_cachedFirestoreSpots.isEmpty) {
      _cachedFirestoreSpots = await TouristSpotsRepository.getTouristSpots();
    }
    visits = await VisitRecordImageResolver.enrichAndPersist(
      visits,
      spots: _spotsForVisitImages,
    );
    return visits;
  }

  Future<void> _loadRecentVisits({bool skipSync = false}) async {
    final visits = await _syncAndEnrichVisits(skipSync: skipSync);
    if (mounted) {
      setState(() => _recentVisits = visits);
    }
  }

  Future<void> _loadRecentlyViewed() async {
    var list = await activity.UserActivityService.getRecentlyViewed();
    if (_cachedFirestoreSpots.isEmpty) {
      _cachedFirestoreSpots = await TouristSpotsRepository.getTouristSpots();
    }
    list = await VisitRecordImageResolver.enrichAndPersist(
      list,
      spots: _spotsForVisitImages,
    );
    if (mounted) {
      setState(() => _recentlyViewed = list);
    }
  }

  Future<void> _loadNotifications() async {
    final uid =
        AuthConfig.currentUserUid ?? FirebaseAuth.instance.currentUser?.uid;
    final notifications = await AnnouncementNotificationSync.loadMergedForHome(
      userId: uid,
    );
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
    String? spotId,
    String? municipalityId,
    String? spotName,
    String? category,
  }) {
    return SpotImage(
      imageUrl: imageUrl,
      spotId: spotId,
      municipalityId: municipalityId,
      spotName: spotName,
      category: category,
      width: width,
      height: height,
      fit: BoxFit.cover,
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

    final municipalityId =
        firestoreSpot != null && firestoreSpot.municipalityId.isNotEmpty
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
      category: spot.category,
    );
    if (!ok || !mounted) return;

    await _loadUserStats();
    await _loadRecentVisits();
  }

  void _showFaq(BuildContext context) {
    openAppFaq(
      context,
      fullScreen: _isMobileLayout,
      centeredPanel: !_isMobileLayout,
      maxPanelWidth: _kHomeCenterPanelMaxWidth,
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
  }) {
    final accent = AppTheme.primary;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
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

  BoxDecoration _homeMiniCardDecoration(Color accent) {
    return BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: accent.withValues(alpha: 0.15)),
      boxShadow: [
        BoxShadow(
          color: accent.withValues(alpha: 0.05),
          blurRadius: 6,
          offset: const Offset(0, 2),
        ),
      ],
    );
  }

  Widget _buildCenteredPanelShell({
    required String title,
    required IconData icon,
    required Widget body,
    String? trailingLabel,
    double heightFraction = 0.72,
  }) {
    final accent = AppTheme.primary;
    final maxH = MediaQuery.sizeOf(context).height * heightFraction;

    return Center(
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 24, vertical: 28),
        constraints: BoxConstraints(
          maxWidth: _kHomeCenterPanelMaxWidth,
          maxHeight: maxH,
        ),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(24),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.12),
              blurRadius: 24,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 8, 0),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: accent.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(icon, color: accent, size: 24),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      title,
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: _kDarkText,
                      ),
                    ),
                  ),
                  if (trailingLabel != null) ...[
                    Text(
                      trailingLabel,
                      style: TextStyle(color: Colors.grey.shade500),
                    ),
                    const SizedBox(width: 4),
                  ],
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: Icon(Icons.close, color: Colors.grey.shade600),
                    tooltip: 'Close',
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Expanded(child: body),
          ],
        ),
      ),
    );
  }

  Future<void> _showCenteredHomePanel({
    required String title,
    required IconData icon,
    required Widget body,
    String? trailingLabel,
    double heightFraction = 0.72,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      barrierColor: Colors.black.withValues(alpha: 0.45),
      builder: (context) => _buildCenteredPanelShell(
        title: title,
        icon: icon,
        body: body,
        trailingLabel: trailingLabel,
        heightFraction: heightFraction,
      ),
    );
  }

  Widget _buildQuickActionsRow() {
    final accent = AppTheme.primary;
    return Align(
      alignment: Alignment.center,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: _kHomeCenterPanelMaxWidth),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Column(
            children: [
              Row(
                children: [
                  Expanded(
                    child: _quickActionTile(
                      icon: Icons.help_outline_rounded,
                      label: 'FAQ',
                      accent: accent,
                      onTap: () => _showFaq(context),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _quickActionTile(
                      icon: Icons.map_rounded,
                      label: 'All places',
                      accent: accent,
                      onTap: _showAllDestinationsDialog,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _quickActionTile(
                      icon: Icons.bookmark_rounded,
                      label: _savedSpotIds.isEmpty
                          ? 'Saved'
                          : 'Saved (${_savedSpotIds.length})',
                      accent: accent,
                      onTap: _showSavedSpotsDialog,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
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
                  const SizedBox(width: 8),
                  Expanded(
                    child: _buildStatCard(
                      'Badges',
                      _userStats.badgesEarned.toString(),
                      Icons.emoji_events_rounded,
                      accent,
                      onTap: _showBadgesDialog,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _buildStatCard(
                      'Days',
                      _userStats.daysAsTourist.toString(),
                      Icons.calendar_today_rounded,
                      accent,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _quickActionTile({
    required IconData icon,
    required String label,
    required Color accent,
    required VoidCallback onTap,
  }) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Container(
          constraints: const BoxConstraints(minHeight: 72),
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 6),
          decoration: _homeMiniCardDecoration(accent),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: accent, size: 20),
              const SizedBox(height: 4),
              Text(
                label,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: accent,
                  fontSize: 10.5,
                  fontWeight: FontWeight.w700,
                  height: 1.15,
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
          body: Column(
            children: [
              _buildHeader(context, accent),
              Expanded(
                child: SafeArea(
                  top: false,
                  child: RefreshIndicator(
                    color: accent,
                    onRefresh: _loadAllData,
                    child: SingleChildScrollView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const SizedBox(height: 8),
                          _buildQuickActionsRow(),
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
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildHeaderProfileAvatar(Color ringColor) {
    final url = _userProfile?.profilePhotoUrl?.trim();
    if (url != null && url.isNotEmpty) {
      return ClipOval(
        child: Image.network(
          url,
          width: 48,
          height: 48,
          fit: BoxFit.cover,
          gaplessPlayback: true,
          loadingBuilder: (context, child, progress) {
            // Avoid showing a progress spinner that makes the avatar blink
            // on every rebuild/tap.
            return child;
          },
          errorBuilder: (_, __, ___) {
            final b64 = _userProfile?.profileImageBase64;
            if (b64 != null && b64.isNotEmpty) {
              return Image.memory(
                base64Decode(b64),
                width: 48,
                height: 48,
                fit: BoxFit.cover,
                gaplessPlayback: true,
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
          gaplessPlayback: true,
          errorBuilder: (_, __, ___) =>
              Icon(Icons.person, color: Colors.grey.shade400, size: 28),
        ),
      );
    }
    return Icon(Icons.person, color: Colors.grey.shade400, size: 28);
  }

  Widget _buildHeader(BuildContext context, Color accent) {
    final userName = _headerFirstName();
    final onHeader = AppTheme.onPrimary;
    final topInset = MediaQuery.paddingOf(context).top;
    final screenWidth = MediaQuery.sizeOf(context).width;
    final nameFontSize = screenWidth < 360 ? 24.0 : 30.0;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(height: topInset),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
          decoration: BoxDecoration(
            color: accent,
            borderRadius: const BorderRadius.only(
              bottomLeft: Radius.circular(28),
              bottomRight: Radius.circular(28),
            ),
            boxShadow: [
              BoxShadow(
                color: accent.withValues(alpha: 0.35),
                blurRadius: 16,
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
                color: onHeader.withValues(alpha: 0.14),
                border: Border.all(
                  color: onHeader.withValues(alpha: 0.55),
                  width: 2,
                ),
              ),
              child: Center(child: _buildHeaderProfileAvatar(onHeader)),
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
                    color: onHeader.withValues(alpha: 0.9),
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.2,
                  ),
                ),
                const SizedBox(height: 2),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Expanded(
                      child: userName.isEmpty
                          ? Container(
                              height: 28,
                              width: 120,
                              decoration: BoxDecoration(
                                color: onHeader.withValues(alpha: 0.25),
                                borderRadius: BorderRadius.circular(6),
                              ),
                            )
                          : Text(
                              userName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: AtmosBrandTypography.displayTitle(
                                color: onHeader,
                                fontSize: nameFontSize,
                                letterSpacing: 0.5,
                              ),
                            ),
                    ),
                    const SizedBox(width: 8),
                    Flexible(
                      fit: FlexFit.loose,
                      child: _buildHeaderWeatherChip(onHeader),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  'Welcome to Asenso Misamis Occidental',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: onHeader.withValues(alpha: 0.88),
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
      ],
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
      case activity.NotificationType.welcome:
        icon = Icons.waving_hand_rounded;
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

  Widget _buildVisitedPlacesBody(List<activity.VisitRecord> visits) {
    if (visits.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.explore_off, size: 64, color: Colors.grey.shade300),
            const SizedBox(height: 16),
            Text(
              'No places visited yet',
              style: TextStyle(color: Colors.grey.shade500, fontSize: 16),
            ),
            const SizedBox(height: 8),
            Text(
              'Scan a destination QR code at the tourist spot to add it here.',
              style: TextStyle(color: Colors.grey.shade400, fontSize: 14),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
      itemCount: visits.length,
      itemBuilder: (context, index) {
        return _buildVisitListItem(visits[index]);
      },
    );
  }

  Future<void> _showVisitedPlacesDialog() async {
    if (!mounted) return;

    Future<List<activity.VisitRecord>> loadVisits() async {
      final visits = await _syncAndEnrichVisits();
      if (!mounted) return visits;
      final stats = await activity.UserActivityService.getUserStats();
      if (!mounted) return visits;
      setState(() {
        _recentVisits = visits;
        _userStats = stats;
      });
      return visits;
    }

    Widget visitedBody(Future<List<activity.VisitRecord>> future) {
      return FutureBuilder<List<activity.VisitRecord>>(
        future: future,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          final visits = snapshot.data ?? const <activity.VisitRecord>[];
          return _buildVisitedPlacesBody(visits);
        },
      );
    }

    final visitsFuture = loadVisits();

    if (_isMobileLayout) {
      await Navigator.of(context).push<void>(
        MaterialPageRoute<void>(
          fullscreenDialog: true,
          builder: (ctx) => Scaffold(
            backgroundColor: Colors.white,
            appBar: _mobileSheetAppBar(ctx, title: 'Visited Places'),
            body: visitedBody(visitsFuture),
          ),
        ),
      );
      return;
    }

    await _showCenteredHomePanel(
      title: 'Visited Places',
      icon: Icons.place_rounded,
      body: visitedBody(visitsFuture),
    );
  }

  Widget _buildVisitListItem(activity.VisitRecord visit) {
    final daysAgo = DateTime.now().difference(visit.visitedAt).inDays;
    final timeLabel = daysAgo == 0
        ? 'Today'
        : daysAgo == 1
        ? 'Yesterday'
        : '$daysAgo days ago';

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => _openVisitRecord(visit),
        borderRadius: BorderRadius.circular(12),
        child: Container(
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
            ],
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
          Icon(Icons.emoji_events_rounded, color: AppTheme.primary, size: 32),
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

  Widget _buildSavedSpotsBody({VoidCallback? onListChanged}) {
    final savedSpots = _savedSpotIds.map(_spotForSavedId).toList()
      ..sort((a, b) => a.name.compareTo(b.name));

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
              style: TextStyle(color: Colors.grey.shade500, fontSize: 16),
            ),
            const SizedBox(height: 8),
            Text(
              'Tap the bookmark icon to save spots!',
              style: TextStyle(color: Colors.grey.shade400, fontSize: 14),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      itemCount: savedSpots.length,
      itemBuilder: (context, index) {
        return _buildSavedSpotItem(
          savedSpots[index],
          onListChanged: onListChanged,
        );
      },
    );
  }

  Future<void> _showSavedSpotsDialog() async {
    if (!mounted) return;

    Future<void> prepareSavedList() async {
      await Future.wait([
        _loadSavedSpots(),
        _loadFirestoreSpotsCache(),
      ]);
    }

    Widget savedBody({
      required VoidCallback onListChanged,
      required Future<void> future,
    }) {
      return FutureBuilder<void>(
        future: future,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          return _buildSavedSpotsBody(onListChanged: onListChanged);
        },
      );
    }

    final prepareFuture = prepareSavedList();

    if (_isMobileLayout) {
      await Navigator.of(context).push<void>(
        MaterialPageRoute<void>(
          fullscreenDialog: true,
          builder: (ctx) => StatefulBuilder(
            builder: (ctx, setSheetState) => Scaffold(
              backgroundColor: Colors.white,
              appBar: _mobileSheetAppBar(ctx, title: 'Saved Spots'),
              body: savedBody(
                future: prepareFuture,
                onListChanged: () => setSheetState(() {}),
              ),
            ),
          ),
        ),
      );
      if (mounted) await _loadSavedSpots();
      return;
    }

    await _showCenteredHomePanel(
      title: 'Saved Spots',
      icon: Icons.bookmark_rounded,
      body: StatefulBuilder(
        builder: (context, setSheetState) => savedBody(
          future: prepareFuture,
          onListChanged: () => setSheetState(() {}),
        ),
      ),
    );
    if (mounted) await _loadSavedSpots();
  }

  Widget _buildSavedSpotItem(
    TouristSpotFirestore spot, {
    VoidCallback? onListChanged,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      child: GestureDetector(
        onTap: () {
          Navigator.pop(context);
          _openSpotDestinationDetail(spot);
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
                  onListChanged?.call();
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
    final child = Container(
      constraints: const BoxConstraints(minHeight: 72),
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 6),
      decoration: _homeMiniCardDecoration(color),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(height: 4),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: color,
              fontSize: 10.5,
              fontWeight: FontWeight.w700,
              height: 1.15,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 2),
          Text(
            value,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w800,
              color: _kDarkText,
              letterSpacing: -0.5,
              height: 1,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );

    if (onTap == null) return child;

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: child,
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
                      color: isSelected ? Colors.white : Colors.grey.shade700,
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
    return SpotImage(
      imageUrl: imageUrl,
      fit: BoxFit.cover,
      width: double.infinity,
      height: double.infinity,
    );
  }

  void _openDestinationDetail({
    required TouristDestinationDetail detail,
    TouristSpotFirestore? firestoreSpot,
  }) {
    Navigator.of(context)
        .push<void>(
      MaterialPageRoute<void>(
        builder: (_) => TouristDestinationDetailScreen(
          destination: detail,
          firestoreSpot: firestoreSpot,
        ),
      ),
    )
        .then((_) {
      if (mounted) _loadSavedSpots();
    });
  }

  void _showFeaturedDestinationDetail(Map<String, dynamic> destination) {
    final image = _featuredImageForDestination(destination);
    final detail = TouristDestinationDetail.fromFeaturedMap(
      destination,
      resolvedImage: image,
    );
    final spot = _spotFromFeatured(destination);
    _openDestinationDetail(detail: detail, firestoreSpot: spot);
  }

  void _openSpotDestinationDetail(TouristSpotFirestore spot) {
    _openDestinationDetail(
      detail: TouristDestinationDetail.fromFirestoreSpot(spot),
      firestoreSpot: spot,
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
              _buildFeaturedCardImage(_featuredImageForDestination(destination)),
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

  /// Compact weather beside the user name in the home header (no background).
  Widget _buildHeaderWeatherChip(Color onHeader) {
    final showInitialLoading = _weatherLoading && _weather == null;
    final w = _weather ?? MisamisOccidentalWeather.fallback();
    final mainIcon = _weatherIconForCode(w.weatherCode);

    return InkWell(
      onTap: _fetchWeather,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 2),
        child: Opacity(
          opacity: _weatherLoading && _weather != null ? 0.7 : 1,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 92),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      showInitialLoading ? Icons.wb_sunny_rounded : mainIcon,
                      color: onHeader,
                      size: 18,
                    ),
                    const SizedBox(width: 3),
                    if (showInitialLoading)
                      SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: onHeader,
                        ),
                      )
                    else
                      Flexible(
                        child: Text(
                          w.temperatureDisplay,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: onHeader,
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                            height: 1,
                          ),
                        ),
                      ),
                  ],
                ),
                if (!showInitialLoading) ...[
                  const SizedBox(height: 2),
                  Text(
                    w.subtitle.split('·').first.trim(),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.right,
                    style: TextStyle(
                      color: onHeader.withValues(alpha: 0.88),
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
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
                                      : 'â€”',
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
                      label: Text('Open map Â· ${spot.name}'),
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
    final spots = _allDestinationSpots;
    if (_isMobileLayout) {
      Navigator.of(context).push<void>(
        MaterialPageRoute<void>(
          fullscreenDialog: true,
          builder: (ctx) => Scaffold(
            backgroundColor: Colors.white,
            appBar: _mobileSheetAppBar(
              ctx,
              title: 'All Destinations',
              subtitle: '${spots.length} spots',
            ),
            body: ListView.builder(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
              itemCount: spots.length,
              itemBuilder: (context, index) {
                return _buildDestinationListItem(
                  spots[index],
                  listContext: ctx,
                );
              },
            ),
          ),
        ),
      );
      return;
    }

    _showCenteredHomePanel(
      title: 'All Destinations',
      icon: Icons.explore_rounded,
      trailingLabel: '${spots.length} spots',
      heightFraction: 0.82,
      body: ListView.builder(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
        itemCount: spots.length,
        itemBuilder: (context, index) {
          return _buildDestinationListItem(spots[index]);
        },
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
        _openSpotDestinationDetail(spot);
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
                : (MediaQuery.sizeOf(context).width < 600 ? 188 : 228),
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
                            'Open any spot from All places or your lists â€” it will show up here.',
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
    final accent = AppTheme.primary;
    final compact = MediaQuery.sizeOf(context).width < 600;
    final cardSize = compact ? 188.0 : 228.0;
    final imageH = compact ? 80.0 : 100.0;

    void onOpen() => _openVisitRecord(entry);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onOpen,
        borderRadius: BorderRadius.circular(20),
        child: SizedBox(
          width: cardSize,
          height: cardSize,
          child: Container(
            margin: const EdgeInsets.only(right: 12),
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
                      child: heroImage != null && heroImage.isNotEmpty
                          ? _buildSpotImage(
                              heroImage,
                              width: cardSize,
                              height: imageH,
                            )
                          : Container(
                              color: Colors.grey.shade200,
                              child: Icon(
                                Icons.place_rounded,
                                size: 42,
                                color: Colors.grey.shade500,
                              ),
                            ),
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
                            entry.category.trim().isEmpty
                                ? 'Recently viewed'
                                : entry.category.trim(),
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
                            entry.spotName,
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
                            Icon(
                              Icons.schedule_rounded,
                              size: 16,
                              color: Colors.grey.shade600,
                            ),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                timeLabel,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700,
                                  color: Colors.grey.shade700,
                                ),
                              ),
                            ),
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

  Widget _buildRecentVisitsSection(BuildContext context) {
    final accent = AppTheme.primary;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSectionHeader(
            title: 'Visited',
            subtitle: 'Tourist spots you checked in via QR',
            icon: Icons.route_rounded,
            trailing: TextButton(
              onPressed: _showVisitedPlacesDialog,
              child: Text(
                'See all',
                style: TextStyle(color: accent, fontWeight: FontWeight.w700),
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
                            'Scan a destination QR code to record your visit here.',
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
      onTap: () {
        final known = _findSpotById(visit.spotId);
        final spot = known ??
            TouristSpotFirestore(
              id: visit.spotId,
              name: visit.spotName,
              category: visit.category,
              latitude: _kMapCenterLat,
              longitude: _kMapCenterLng,
              rating: 4.5,
              image: heroImage ?? visit.imageUrl ?? '',
              vrLink: '',
            );
        _openSpotDestinationDetail(spot);
      },
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
                      ? _buildSpotImage(heroImage, width: cardW, height: imageH)
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
class _FeaturedDestinationFullScreenPage extends StatefulWidget {
  const _FeaturedDestinationFullScreenPage({
    required this.destination,
    required this.buildImage,
  });

  final Map<String, dynamic> destination;
  final Widget Function(String imageUrl) buildImage;

  @override
  State<_FeaturedDestinationFullScreenPage> createState() =>
      _FeaturedDestinationFullScreenPageState();
  }

class _FeaturedDestinationFullScreenPageState
    extends State<_FeaturedDestinationFullScreenPage> {
  bool _isSaved = false;
  bool _isSaving = false;

  String get _spotId => widget.destination['spotId']?.toString() ?? '';
  double get _lat => (widget.destination['latitude'] as num?)?.toDouble() ?? 0;
  double get _lng => (widget.destination['longitude'] as num?)?.toDouble() ?? 0;

  @override
  void initState() {
    super.initState();
    _loadSaved();
  }

  Future<void> _loadSaved() async {
    if (!mounted) return;
    final spotId = _spotId;
    if (spotId.isEmpty) {
      if (mounted) setState(() => _isSaved = false);
      return;
    }
    final saved = await activity.UserActivityService.isSpotSaved(spotId);
    if (!mounted) return;
    setState(() => _isSaved = saved);
  }

  Future<void> _launchDirections() async {
    final destination = widget.destination;
    final name = destination['name']?.toString() ?? '';
    final location = destination['location']?.toString() ?? '';
    await MapsDirectionsLauncher.open(
      destinationLabel: MapsDirectionsLauncher.placeLabel(
        name: name,
        address: location,
      ),
      destinationLatitude: _lat == 0 ? null : _lat,
      destinationLongitude: _lng == 0 ? null : _lng,
    );
  }

  Future<void> _toggleSave() async {
    final spotId = _spotId;
    if (spotId.isEmpty) return;
    if (_isSaving) return;
    setState(() => _isSaving = true);
    final savedNow = await activity.UserActivityService.toggleSaveSpot(spotId);
    if (!mounted) return;
    setState(() {
      _isSaved = savedNow;
      _isSaving = false;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(savedNow ? 'Saved to your list' : 'Removed from saved'),
        backgroundColor: AppTheme.primary,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: AppThemeController.instance,
      builder: (context, _) {
        final accent = AppTheme.primary;
        final onAccent = AppTheme.onPrimary;
        final destination = widget.destination;
        // Show the short description in the details view (as requested).
        final detail =
            destination['description'] as String? ??
            destination['detail'] as String? ??
            '';
        final image = destination['image'] as String;
        final name = destination['name'] as String;
        final category = destination['category'] as String;
        final rating = destination['rating'];
        final openingHours = destination['openingHours']?.toString() ?? '';
        final entranceFee = destination['entranceFee']?.toString() ?? '';
        final cottageRates = destination['cottageRates']?.toString() ?? '';
        final location = destination['location']?.toString() ?? '';
        final nearbyRestaurants = (destination['nearbyRestaurants'] as List?)
            ?.map((e) {
              if (e is Map) return e['name']?.toString() ?? '';
              return e.toString();
            })
            .where((s) => s.trim().isNotEmpty)
            .toList();
        final nearbyRestaurantCards =
            TouristDestinationDetail.fromFeaturedMap(destination).nearbyRestaurants;
        final featuredDetail =
            TouristDestinationDetail.fromFeaturedMap(destination);
        final nearbyHotelCards = featuredDetail.nearbyHotels;
        final nearbyHotels = (destination['nearbyHotels'] as List?)
            ?.map((e) {
              if (e is Map) return e['name']?.toString() ?? '';
              return e.toString();
            })
            .where((s) => s.trim().isNotEmpty)
            .toList();

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
                        backgroundColor: accent,
                        foregroundColor: onAccent,
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
                flexibleSpace: FlexibleSpaceBar(background: widget.buildImage(image)),
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
                    buildImage: widget.buildImage,
                    showHeroImage: false,
                    accent: accent,
                    openingHours: openingHours,
                    entranceFee: entranceFee,
                    cottageRates: cottageRates,
                    location: location,
                    nearbyRestaurants: nearbyRestaurants ?? const [],
                    nearbyRestaurantCards: nearbyRestaurantCards,
                    nearbyHotels: nearbyHotels ?? const [],
                    nearbyHotelCards: nearbyHotelCards,
                    nearbyHotelsNote:
                        destination['nearbyHotelsNote']?.toString() ?? '',
                    isSaved: _isSaved,
                    isSaving: _isSaving,
                    onDirections: () {
                      _launchDirections();
                    },
                    onSave: () {
                      _toggleSave();
                    },
                  ),
                ),
              ),
            ],
          ),
        );
      },
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
    this.accent,
    this.openingHours = '',
    this.entranceFee = '',
    this.cottageRates = '',
    this.location = '',
    this.nearbyRestaurants = const [],
    this.nearbyRestaurantCards = const [],
    this.nearbyHotels = const [],
    this.nearbyHotelCards = const [],
    this.nearbyHotelsNote = '',
    this.isSaved = false,
    this.isSaving = false,
    this.onDirections,
    this.onSave,
  });

  final String name;
  final String category;
  final dynamic rating;
  final String detail;
  final String image;
  final Widget Function(String imageUrl) buildImage;
  final bool showHeroImage;
  final Color? accent;
  final String openingHours;
  final String entranceFee;
  final String cottageRates;
  final String location;
  final List<String> nearbyRestaurants;
  final List<NearbyPlaceCard> nearbyRestaurantCards;
  final List<String> nearbyHotels;
  final List<NearbyPlaceCard> nearbyHotelCards;
  final String nearbyHotelsNote;
  final bool isSaved;
  final bool isSaving;
  final VoidCallback? onDirections;
  final VoidCallback? onSave;

  @override
  Widget build(BuildContext context) {
    final color = accent ?? AppTheme.primary;
    final restaurants = nearbyRestaurants.where((e) => e.trim().isNotEmpty).toList();
    final hotels = nearbyHotels.where((e) => e.trim().isNotEmpty).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (showHeroImage) ...[
          ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: AspectRatio(aspectRatio: 16 / 9, child: buildImage(image)),
          ),
          const SizedBox(height: 16),
        ],
        Row(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                category,
                style: TextStyle(
                  color: color,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Icon(Icons.star, size: 16, color: color),
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
        const SizedBox(height: 18),
        Wrap(
          spacing: 12,
          runSpacing: 10,
          children: [
            _InfoChip(
              icon: Icons.access_time,
              label: 'Opening hours',
              value: openingHours,
              color: color,
            ),
            _InfoChip(
              icon: Icons.monetization_on_outlined,
              label: 'Entrance fee',
              value: entranceFee,
              color: color,
            ),
            if (cottageRates.trim().isNotEmpty)
              _InfoChip(
                icon: Icons.holiday_village_outlined,
                label: 'Cottages & tables',
                value: cottageRates,
                color: color,
              ),
            _InfoChip(
              icon: Icons.location_on_outlined,
              label: 'Location',
              value: location,
              color: color,
            ),
          ],
        ),
        const SizedBox(height: 18),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            FilledButton.icon(
              onPressed: onDirections,
              icon: const Icon(Icons.near_me_rounded),
              label: const Text('Get Directions'),
              style: FilledButton.styleFrom(
                backgroundColor: color,
                foregroundColor: AppTheme.onPrimary,
                padding: const EdgeInsets.symmetric(horizontal: 14),
              ),
            ),
            FilledButton.icon(
              onPressed: onSave != null && !isSaving ? onSave : null,
              icon: Icon(isSaved ? Icons.bookmark : Icons.bookmark_border),
              label: Text(isSaved ? 'Saved' : 'Save'),
              style: FilledButton.styleFrom(
                backgroundColor: isSaved ? Colors.green.shade600 : color,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 14),
              ),
            ),
          ],
        ),
        if (nearbyRestaurantCards.isNotEmpty || restaurants.isNotEmpty || hotels.isNotEmpty) ...[
          const SizedBox(height: 18),
          if (nearbyRestaurantCards.isNotEmpty) ...[
            Row(
              children: [
                Icon(Icons.restaurant_outlined, color: color, size: 20),
                const SizedBox(width: 8),
                Text(
                  'Nearby Restaurants',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: color,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            SizedBox(
              height: 168,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: nearbyRestaurantCards.length,
                separatorBuilder: (_, __) => const SizedBox(width: 12),
                itemBuilder: (_, i) =>
                    _FeaturedNearbyRestaurantTile(
                      place: nearbyRestaurantCards[i],
                      accent: color,
                      buildImage: buildImage,
                    ),
              ),
            ),
            const SizedBox(height: 12),
          ] else if (restaurants.isNotEmpty) ...[
            _NearbySummaryCard(
              title: 'Nearby Restaurants',
              icon: Icons.restaurant_outlined,
              color: color,
              items: restaurants,
            ),
            const SizedBox(height: 12),
          ],
          if (hotels.isNotEmpty || nearbyHotelCards.isNotEmpty) ...[
            if (nearbyHotelsNote.trim().isNotEmpty) ...[
              Text(
                nearbyHotelsNote,
                style: TextStyle(
                  fontSize: 13,
                  height: 1.4,
                  color: Colors.grey.shade700,
                ),
              ),
              const SizedBox(height: 8),
            ],
            if (nearbyHotelCards.isNotEmpty) ...[
              Row(
                children: [
                  Icon(Icons.hotel_outlined, color: color, size: 20),
                  const SizedBox(width: 8),
                  Text(
                    'Nearby Hotels',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      color: color,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              SizedBox(
                height: 168,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: nearbyHotelCards.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 12),
                  itemBuilder: (_, i) => _FeaturedNearbyRestaurantTile(
                    place: nearbyHotelCards[i],
                    accent: color,
                    buildImage: buildImage,
                  ),
                ),
              ),
            ] else ...[
              _NearbySummaryCard(
                title: 'Nearby Hotels',
                icon: Icons.hotel_outlined,
                color: color,
                items: hotels,
              ),
            ],
          ],
        ],
      ],
    );
  }
}

class _FeaturedNearbyRestaurantTile extends StatelessWidget {
  const _FeaturedNearbyRestaurantTile({
    required this.place,
    required this.accent,
    required this.buildImage,
  });

  final NearbyPlaceCard place;
  final Color accent;
  final Widget Function(String imageUrl) buildImage;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () {
          unawaited(
            MapsDirectionsLauncher.open(
              destinationLabel: place.directionsLabel,
            ),
          );
        },
        borderRadius: BorderRadius.circular(18),
        child: Container(
      width: 152,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: accent.withValues(alpha: 0.12)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            height: 72,
            width: double.infinity,
            child: buildImage(place.imageUrl ?? ''),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    place.name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: _kDarkText,
                    ),
                  ),
                  const Spacer(),
                  Row(
                    children: [
                      Icon(Icons.star_rounded, size: 12, color: accent),
                      Text(
                        place.rating.toStringAsFixed(1),
                        style: const TextStyle(fontSize: 11),
                      ),
                      const Spacer(),
                      Text(
                        place.priceRange,
                        style: TextStyle(fontSize: 11, color: accent),
                      ),
                    ],
                  ),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          place.driveMinutes != null
                              ? '~${place.driveMinutes!.round()} min drive'
                              : '${place.distanceKm.toStringAsFixed(1)} km',
                          style: const TextStyle(fontSize: 10, color: _kMuted),
                        ),
                      ),
                      Icon(Icons.directions_rounded, size: 14, color: accent),
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
    );
  }
}

class _NearbySummaryCard extends StatelessWidget {
  const _NearbySummaryCard({
    required this.title,
    required this.icon,
    required this.color,
    required this.items,
  });

  final String title;
  final IconData icon;
  final Color color;
  final List<String> items;

  @override
  Widget build(BuildContext context) {
    final primary = items.isNotEmpty ? items.first.trim() : '';
    final extra = items.length - 1;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            color.withValues(alpha: 0.14),
            color.withValues(alpha: 0.06),
          ],
        ),
        border: Border.all(color: color.withValues(alpha: 0.18)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 18,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.16),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(icon, color: color),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w900,
                    color: color,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  primary.isEmpty ? 'â€”' : primary,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    color: _kDarkText,
                  ),
                ),
                if (extra > 0) ...[
                  const SizedBox(height: 2),
                  Text(
                    '+$extra more',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: Colors.grey.shade700,
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 8),
          Icon(Icons.chevron_right_rounded, color: color),
        ],
      ),
    );
  }
}

class _InfoChip extends StatelessWidget {
  const _InfoChip({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
  });

  final IconData icon;
  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final v = value.trim();
    final screenW = MediaQuery.sizeOf(context).width;
    final maxChipW = screenW < 420 ? screenW - 64 : 280.0;
    return ConstrainedBox(
      constraints: BoxConstraints(maxWidth: maxChipW),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: color.withValues(alpha: 0.2)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: color),
            const SizedBox(width: 8),
            Flexible(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      color: color.withValues(alpha: 0.85),
                    ),
                  ),
                  Text(
                    v.isEmpty ? 'â€”' : v,
                    maxLines: label == 'Location' ? 2 : 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF111827),
                      height: 1.2,
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
}

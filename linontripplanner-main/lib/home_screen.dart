import 'dart:async';
import 'dart:math' as math;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart' as firebase_auth;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:smooth_page_indicator/smooth_page_indicator.dart';
import 'data.dart';
import 'widgets/municipality_image.dart';
import 'municipality_detail_screen.dart';
import 'municipality_list_screen.dart';
import 'spot_detail_screen.dart';
import 'tourist_spots_screen.dart';
import 'tourist_plan/my_trips_screen.dart';
import 'events_screen.dart';
import 'firestore_loader.dart';
import 'notifications_screen.dart';
import 'profile_screen.dart';
import 'mapping_screen.dart';
import 'services/tourism_notifications_state.dart';
import 'services/tourism_session.dart';
import 'services/saved_trip_store.dart';
import 'services/home_personalization_service.dart';
import 'services/home_recommendation_service.dart';
import 'services/spot_interaction_history.dart';
import 'widgets/responsive_layout.dart';
import 'widgets/tourism_plan_ui.dart';
import 'widgets/profile_header_photo.dart';


class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final PageController _bannerController = PageController();
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  int _bottomIndex = 0;
  Timer? _bannerAutoPlayTimer;
  int _featuredBannerIndex = 0;
  bool _bannerPageChangeFromTimer = false;
  final _notifState = TourismNotificationsState.instance;

  /// Forces the Home tab root to rebuild (search, etc.) under the kept-alive
  /// tab [Navigator].
  final ValueNotifier<int> _homeUiTick = ValueNotifier<int>(0);

  /// Per-tab stacks so detail pages (spots, municipalities, etc.) do not cover
  /// the bottom navigation bar.
  final List<GlobalKey<NavigatorState>> _tabNavKeys =
      List<GlobalKey<NavigatorState>>.generate(
    7,
    (_) => GlobalKey<NavigatorState>(),
  );

  static const int _profileTab = 3;

  /// [IndexedStack] tab for each bottom bar item; Profile opens from the home
  /// header instead of the bottom bar.
  static const List<int> _bottomNavTabs = [0, 1, 2, 4, 5, 6];

  bool get _isSearching => _searchQuery.trim().isNotEmpty;

  /// Featured Spots — weighted popularity (not personal history).
  List<TouristSpot> get _featuredTouristSpots {
    final ranked =
        HomePersonalizationService.instance.featuredRanked(limit: 8);
    if (ranked.isNotEmpty) {
      return ranked.map((e) => e.spot).toList(growable: false);
    }
    // Warm-up fallback before first recompute finishes.
    if (featuredSpots.isNotEmpty) {
      return [
        for (final f in recommendedFeaturedForBanner)
          findTouristSpotByNameFuzzy(f.name),
      ].whereType<TouristSpot>().toList();
    }
    return List<TouristSpot>.from(allSpots)
      ..sort((a, b) => b.rating.compareTo(a.rating));
  }

  bool get _showFeaturedSection =>
      !_isSearching && _featuredTouristSpots.isNotEmpty;

  /// Recommended for You — hybrid personalized ranking.
  List<TouristSpot> get _recommendedForYouSpots {
    final ranked =
        HomePersonalizationService.instance.recommendedRanked(limit: 12);
    if (ranked.isNotEmpty) {
      return ranked.map((e) => e.spot).toList(growable: false);
    }
    return HomePersonalizationService.instance.personalizedSpots(limit: 12);
  }

  List<Municipality> get _homeMunicipalities {
    if (!tourismIsGuestSession() &&
        HomePersonalizationService.instance.profile?.hasSignals == true) {
      return HomePersonalizationService.instance.personalizedMunicipalities();
    }
    return recommendedMunicipalities;
  }

  List<Municipality> _filterMunicipalities(List<Municipality> list) {
    if (!_isSearching) return list;
    return list.where(_municipalityMatchesSearch).toList();
  }

  List<TouristSpot> _filterSpots(List<TouristSpot> list) {
    if (!_isSearching) return list;
    return list.where(_spotMatchesSearch).toList();
  }

  bool _textMatchesSearch(String text) {
    final q = _searchQuery.trim().toLowerCase();
    if (q.isEmpty) return true;
    return text.toLowerCase().contains(q);
  }

  bool _spotMatchesSearch(TouristSpot spot) {
    return _textMatchesSearch(spot.name) ||
        _textMatchesSearch(spot.location) ||
        _textMatchesSearch(spot.description) ||
        _textMatchesSearch(spot.type) ||
        _textMatchesSearch(spot.category) ||
        _textMatchesSearch(spot.priceRange);
  }

  List<TouristSpot> _spotsForHomeGrid() {
    final seenNames = <String>{};
    final base = _isSearching ? allSpots : _recommendedForYouSpots;
    return _filterSpots(
      base.where((s) => seenNames.add(s.name)).toList(),
    );
  }

  List<TouristSpot> get _displayFeaturedSpots =>
      _filterSpots(_featuredTouristSpots);

  bool _municipalityMatchesSearch(Municipality m) {
    return _textMatchesSearch(m.name) ||
        _textMatchesSearch(m.shortName) ||
        _textMatchesSearch(m.description);
  }

  @override
  void initState() {
    super.initState();
    _notifState.addListener(_onNotifStateChanged);
    tourismCatalogRevision.addListener(_onCatalogOrPersonalizationChanged);
    HomePersonalizationService.instance.revision
        .addListener(_onCatalogOrPersonalizationChanged);
    HomeRecommendationService.instance.revision
        .addListener(_onCatalogOrPersonalizationChanged);
    SpotInteractionHistoryStore.instance.revision
        .addListener(_onCatalogOrPersonalizationChanged);
    tourismShellTabRequest.addListener(_onShellTabRequest);
    unawaited(SavedTripStore.instance.ensureLoaded());
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _syncBannerPageWithListAndRestartAutoPlay();
    });
    _reloadHomeDataFromFirestore();
  }

  void _onShellTabRequest() {
    final index = tourismShellTabRequest.value;
    if (index == null || !mounted) return;
    tourismShellTabRequest.value = null;
    setState(() => _bottomIndex = index);
    _tabNavKeys[index].currentState?.popUntil((r) => r.isFirst);
  }

  void _onNotifStateChanged() {
    if (mounted) setState(() {});
  }

  void _onCatalogOrPersonalizationChanged() {
    if (!mounted) return;
    setState(() {});
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _syncBannerPageWithListAndRestartAutoPlay();
    });
  }

  void _syncBannerPageWithListAndRestartAutoPlay() {
    if (!mounted) return;
    final n = _displayFeaturedSpots.length;
    if (n > 0 &&
        _bannerController.hasClients &&
        _featuredBannerIndex >= n) {
      _featuredBannerIndex = 0;
      _bannerController.jumpToPage(0);
    }
    _restartFeaturedAutoPlay();
  }

  Future<void> _reloadHomeDataFromFirestore() async {
    try {
      // Catalog (spots / municipalities / featured) must paint as soon as it is
      // ready. Do not block that rebuild on a second personalization pass —
      // bootstrap already refreshes personalization, and a hung peer-profile
      // read left the home grid stuck on "Tourist spots are still loading…".
      await bootstrapAppFirestoreOnce();
      if (!mounted) return;
      setState(() {});
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _syncBannerPageWithListAndRestartAutoPlay();
      });

      unawaited(
        HomePersonalizationService.instance.refresh().then((_) {
          if (!mounted) return;
          setState(() {});
          WidgetsBinding.instance.addPostFrameCallback((_) {
            _syncBannerPageWithListAndRestartAutoPlay();
          });
        }),
      );
    } catch (_) {
      // Keep existing in-memory fallback if Firestore read fails.
      if (mounted) setState(() {});
    }
  }

  /// Pull latest events/announcements when opening Notifications or Events.
  Future<void> _refreshEventsAndNotifications() async {
    try {
      await Future.wait([
        loadEventsFromFirestore(),
        loadAnnouncementsFromFirestore(),
      ]);
      _notifState.refreshFromCatalog();
    } catch (e) {
      debugPrint('refresh events/notifications: $e');
    }
    if (mounted) setState(() {});
  }

  void _restartFeaturedAutoPlay() {
    _bannerAutoPlayTimer?.cancel();
    _bannerAutoPlayTimer = null;
    final n = _displayFeaturedSpots.length;
    if (n <= 1) return;
    _bannerAutoPlayTimer = Timer.periodic(const Duration(seconds: 3), (_) {
      _advanceFeaturedBanner();
    });
  }

  void _advanceFeaturedBanner() {
    if (!mounted) return;
    final list = _displayFeaturedSpots;
    if (list.length <= 1) return;
    if (!_bannerController.hasClients) return;
    final next = (_featuredBannerIndex + 1) % list.length;
    _bannerPageChangeFromTimer = true;
    _bannerController.animateToPage(
      next,
      duration: const Duration(milliseconds: 500),
      curve: Curves.easeInOut,
    );
  }

  @override
  void dispose() {
    _notifState.removeListener(_onNotifStateChanged);
    tourismCatalogRevision.removeListener(_onCatalogOrPersonalizationChanged);
    HomePersonalizationService.instance.revision
        .removeListener(_onCatalogOrPersonalizationChanged);
    HomeRecommendationService.instance.revision
        .removeListener(_onCatalogOrPersonalizationChanged);
    SpotInteractionHistoryStore.instance.revision
        .removeListener(_onCatalogOrPersonalizationChanged);
    tourismShellTabRequest.removeListener(_onShellTabRequest);
    _homeUiTick.dispose();
    _bannerAutoPlayTimer?.cancel();
    _searchController.dispose();
    _bannerController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        final tabNav = _tabNavKeys[_bottomIndex].currentState;
        if (tabNav != null && tabNav.canPop()) {
          tabNav.pop();
          return;
        }
        if (_bottomIndex != 0) {
          setState(() => _bottomIndex = 0);
          return;
        }
        SystemNavigator.pop();
      },
      child: Scaffold(
        backgroundColor: AppColors.planPageBg,
        body: IndexedStack(
          index: _bottomIndex,
          children: [
            _tabNavigator(0, _buildHomeTabRoot),
            _tabNavigator(
              1,
              () => const TouristSpotsScreen(embeddedInShell: true),
            ),
            _tabNavigator(
              2,
              () => const MyTripsScreen(embeddedInShell: true),
            ),
            _tabNavigator(_profileTab, () => const ProfileScreen()),
            _tabNavigator(4, () => const MappingScreen()),
            _tabNavigator(5, () => const NotificationsScreen()),
            _tabNavigator(6, () => const EventsScreen()),
          ],
        ),
        bottomNavigationBar: TourismBottomNavShell(
          child: BottomNavigationBar(
            currentIndex: math.max(0, _bottomNavTabs.indexOf(_bottomIndex)),
            type: BottomNavigationBarType.fixed,
            backgroundColor: Colors.transparent,
            elevation: 0,
            selectedItemColor: AppColors.primary,
            unselectedItemColor: AppColors.textGrey,
            showUnselectedLabels: true,
            onTap: (navIndex) {
              final index = _bottomNavTabs[navIndex];
              if (index == _bottomIndex) {
                // Tap active tab again → return to that tab’s root list.
                _tabNavKeys[index].currentState?.popUntil((r) => r.isFirst);
                if (index == 5 || index == 6) {
                  unawaited(_refreshEventsAndNotifications());
                }
                return;
              }
              setState(() => _bottomIndex = index);
              if (index == 5 || index == 6) {
                unawaited(_refreshEventsAndNotifications());
              }
            },
            items: [
              const BottomNavigationBarItem(
                icon: Icon(Icons.home_outlined),
                label: 'Home',
              ),
              const BottomNavigationBarItem(
                icon: Icon(Icons.public),
                label: 'Spots',
              ),
              const BottomNavigationBarItem(
                icon: Icon(Icons.luggage_outlined),
                label: 'Trips',
              ),
              const BottomNavigationBarItem(
                icon: Icon(Icons.map_outlined),
                label: 'Map',
              ),
              BottomNavigationBarItem(
                icon:
                    TourismNotificationNavIcon(count: _notifState.unreadCount),
                activeIcon: TourismNotificationNavIcon(
                  count: _notifState.unreadCount,
                  active: true,
                ),
                label: 'Notifications',
              ),
              const BottomNavigationBarItem(
                icon: Icon(Icons.event_rounded),
                label: 'Events',
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Home tab root — rebuilds from live catalog / personalization getters.
  Widget _buildHomeTabRoot() {
    final featuredForDisplay = _displayFeaturedSpots;
    final municipalitiesForDisplay =
        _filterMunicipalities(_homeMunicipalities);
    final spotsForDisplay = _spotsForHomeGrid();
    final hasFeaturedRecommendations = _showFeaturedSection;
    final showNoSearchResults = _isSearching &&
        featuredForDisplay.isEmpty &&
        municipalitiesForDisplay.isEmpty &&
        spotsForDisplay.isEmpty;
    final screenWidth = MediaQuery.sizeOf(context).width;
    final compactHeader = tourismIsPhoneWidth(screenWidth);

    return _buildHomeTabScaffold(
      compactHeader: compactHeader,
      featuredForDisplay: featuredForDisplay,
      municipalitiesForDisplay: municipalitiesForDisplay,
      spotsForDisplay: spotsForDisplay,
      hasFeaturedRecommendations: hasFeaturedRecommendations,
      showNoSearchResults: showNoSearchResults,
    );
  }

  Widget _tabNavigator(int tabIndex, Widget Function() rootBuilder) {
    return Navigator(
      key: _tabNavKeys[tabIndex],
      onGenerateRoute: (settings) {
        return MaterialPageRoute<void>(
          settings: settings,
          builder: (_) => _LiveShellTabRoot(
            listenable: Listenable.merge([
              tourismCatalogRevision,
              HomePersonalizationService.instance.revision,
              if (tabIndex == 0) _homeUiTick,
            ]),
            builder: rootBuilder,
          ),
        );
      },
    );
  }

  void _openBottomTab(int index) {
    setState(() => _bottomIndex = index);
  }

  Widget _buildProfileButton({required double size, required bool compact}) {
    return _HomeProfileButton(
      size: size,
      nameMaxWidth: compact ? 96 : 160,
      onTap: () => _openBottomTab(_profileTab),
    );
  }

  Widget _buildHomeTabScaffold({
    required bool compactHeader,
    required List<TouristSpot> featuredForDisplay,
    required List<Municipality> municipalitiesForDisplay,
    required List<TouristSpot> spotsForDisplay,
    required bool hasFeaturedRecommendations,
    required bool showNoSearchResults,
  }) {
    return Scaffold(
      backgroundColor: AppColors.planPageBg,
      appBar: AppBar(
        backgroundColor: AppColors.planPageBg,
        elevation: 0,
        centerTitle: false,
        toolbarHeight: compactHeader ? 64 : 72,
        titleSpacing: compactHeader ? 8 : 16,
        title: FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Image.asset(
                'assets/images/tripplan.png',
                height: compactHeader ? 48 : 64,
                filterQuality: FilterQuality.high,
              ),
              SizedBox(width: compactHeader ? 8 : 10),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'TripPlan',
                    style: TextStyle(
                      fontFamily: AppFonts.holidayCalling,
                      color: AppColors.primary,
                      fontSize: compactHeader ? 30 : 40,
                      fontWeight: FontWeight.w400,
                      height: 0.9,
                    ),
                  ),
                  Text(
                    'Misamis Occidental',
                    style: TextStyle(
                      fontFamily: AppFonts.holidayCalling,
                      color: AppColors.primary,
                      fontSize: compactHeader ? 24 : 34,
                      fontWeight: FontWeight.w400,
                      height: 0.9,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        actions: [
          Padding(
            padding: EdgeInsets.only(right: compactHeader ? 12 : 20),
            child: _buildProfileButton(
              size: compactHeader ? 50 : 58,
              compact: compactHeader,
            ),
          ),
        ],
      ),
      body: _buildHomeTabBody(
        featuredForDisplay: featuredForDisplay,
        municipalitiesForDisplay: municipalitiesForDisplay,
        spotsForDisplay: spotsForDisplay,
        hasFeaturedRecommendations: hasFeaturedRecommendations,
        showNoSearchResults: showNoSearchResults,
      ),
    );
  }

  Widget _buildHomeTabBody({
    required List<TouristSpot> featuredForDisplay,
    required List<Municipality> municipalitiesForDisplay,
    required List<TouristSpot> spotsForDisplay,
    required bool hasFeaturedRecommendations,
    required bool showNoSearchResults,
  }) {
    return TourismPlanPageBody(
      child: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final maxW = tourismContentMaxWidth(constraints.maxWidth);
            final hPad = tourismPagePadding(constraints.maxWidth);
            return Align(
              alignment: Alignment.topCenter,
              child: ConstrainedBox(
                constraints: BoxConstraints(maxWidth: maxW),
                child: SingleChildScrollView(
                  padding: EdgeInsets.symmetric(horizontal: hPad),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildSearchBar(),
                      if (_isSearching) ...[
                        const SizedBox(height: 12),
                        _buildSearchResultsHint(),
                      ],
                      if (showNoSearchResults) ...[
                        const SizedBox(height: 24),
                        _buildEmptySearchState(),
                      ] else ...[
                        if (hasFeaturedRecommendations) ...[
                          const SizedBox(height: 16),
                          TourismPlanUi.sectionTitleBar(title: 'Featured Spots'),
                          const SizedBox(height: 12),
                          _buildFeaturedTouristBanner(featuredForDisplay),
                          const SizedBox(height: 8),
                          _buildTouristPageIndicator(featuredForDisplay),
                          const SizedBox(height: 20),
                        ] else
                          const SizedBox(height: 12),
                        if (municipalitiesForDisplay.isNotEmpty) ...[
                          _buildSectionHeader(
                            _isSearching
                                ? 'Municipalities'
                                : 'Recommended Municipalities',
                            onTap: () {
                              _tabNavKeys[0].currentState?.push(
                                MaterialPageRoute<void>(
                                  builder: (_) =>
                                      const MunicipalityListScreen(),
                                ),
                              );
                            },
                          ),
                          const SizedBox(height: 12),
                          _buildMunicipalityList(municipalitiesForDisplay),
                          const SizedBox(height: 20),
                        ],
                        if (spotsForDisplay.isNotEmpty) ...[
                          _buildSectionHeader(
                            _isSearching
                                ? 'Tourist Spots'
                                : 'Recommended for You',
                            onTap: () => _openBottomTab(1),
                          ),
                          const SizedBox(height: 12),
                          _buildTouristSpotsGrid(spotsForDisplay),
                          if (_firstVisitAgainSpot(spotsForDisplay) != null) ...[
                            const SizedBox(height: 12),
                            _buildVisitAgainPrompt(
                              _firstVisitAgainSpot(spotsForDisplay)!,
                            ),
                          ],
                          const SizedBox(height: 12),
                        ] else if (!_isSearching && allSpots.isEmpty) ...[
                          const SizedBox(height: 16),
                          Text(
                            'Tourist spots are still loading...',
                            style: TextStyle(
                              color: AppColors.textGrey.withValues(alpha: 0.95),
                            ),
                          ),
                          const SizedBox(height: 12),
                        ] else if (!_isSearching && allSpots.isNotEmpty) ...[
                          _buildSectionHeader(
                            'Recommended for You',
                            onTap: () => _openBottomTab(1),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Open Spots to browse all ${allSpots.length} places.',
                            style: TextStyle(
                              color: AppColors.textGrey.withValues(alpha: 0.95),
                            ),
                          ),
                          const SizedBox(height: 12),
                        ],
                      ],
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildSearchBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(0, 12, 0, 0),
      child: TourismPlanUi.searchField(
        controller: _searchController,
        onChanged: (value) {
          setState(() => _searchQuery = value);
          _homeUiTick.value++;
          final q = value.trim();
          if (q.length >= 3) {
            final matches = allSpots
                .where(_spotMatchesSearch)
                .map((s) => s.name)
                .take(8);
            unawaited(
              SpotInteractionHistoryStore.instance.recordSearchedNames(matches),
            );
          }
          WidgetsBinding.instance.addPostFrameCallback((_) {
            _syncBannerPageWithListAndRestartAutoPlay();
          });
        },
        showClear: _isSearching,
        onClear: () {
          _searchController.clear();
          setState(() => _searchQuery = '');
          _homeUiTick.value++;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            _syncBannerPageWithListAndRestartAutoPlay();
          });
        },
      ),
    );
  }

  Widget _buildSearchResultsHint() {
    return Padding(
      padding: EdgeInsets.zero,
      child: Text(
        'Results for "${_searchQuery.trim()}"',
        style: const TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w600,
          color: AppColors.textDark,
        ),
      ),
    );
  }

  Widget _buildEmptySearchState() {
    return TourismEmptyState(
      icon: Icons.search_off_rounded,
      message:
          'No destinations match "${_searchQuery.trim()}".\nTry another name or municipality.',
      topPadding: 24,
    );
  }


  Widget _buildFeaturedTouristBanner(List<TouristSpot> recommended) {
    if (recommended.isEmpty) return const SizedBox.shrink();
    return Container(
      decoration: TourismPlanUi.planCardDecoration(),
      clipBehavior: Clip.antiAlias,
      child: SizedBox(
        height: 220,
        child: PageView.builder(
          controller: _bannerController,
          itemCount: recommended.length,
          onPageChanged: (index) {
            _featuredBannerIndex = index;
            if (_bannerPageChangeFromTimer) {
              _bannerPageChangeFromTimer = false;
            } else {
              _restartFeaturedAutoPlay();
            }
          },
          itemBuilder: (context, index) {
            final spot = recommended[index];
            return GestureDetector(
              onTap: () {
                unawaited(SpotInteractionHistoryStore.instance.recordViewed(spot));
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => SpotDetailScreen(spot: spot)),
                );
              },
              child: _FeaturedTouristCard(spot: spot),
            );
          },
        ),
      ),
    );
  }

  Widget _buildTouristPageIndicator(List<TouristSpot> recommended) {
    if (recommended.isEmpty) return const SizedBox.shrink();
    return Center(
      child: SmoothPageIndicator(
        controller: _bannerController,
        count: recommended.length,
        effect: const WormEffect(
          dotHeight: 8,
          dotWidth: 8,
          activeDotColor: AppColors.primary,
          dotColor: Color(0xFFCCCCCC),
        ),
      ),
    );
  }

  Widget _buildTouristSpotsGrid(List<TouristSpot> recommended) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final crossAxisCount =
            tourismSpotGridCrossAxisCount(constraints.maxWidth);
        return GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: crossAxisCount,
            crossAxisSpacing: 10,
            mainAxisSpacing: 14,
            childAspectRatio: 0.68,
          ),
          itemCount: recommended.length,
          itemBuilder: (context, index) {
            final spot = recommended[index];
            return GestureDetector(
              onTap: () {
                unawaited(
                  SpotInteractionHistoryStore.instance.recordViewed(spot),
                );
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => SpotDetailScreen(spot: spot),
                  ),
                );
              },
              child: _SpotCard(spot: spot),
            );
          },
        );
      },
    );
  }

  TouristSpot? _firstVisitAgainSpot(List<TouristSpot> spots) {
    for (final s in spots) {
      if (SpotInteractionHistoryStore.instance.shouldAskVisitAgain(s)) {
        return s;
      }
    }
    return null;
  }

  Widget _buildVisitAgainPrompt(TouristSpot spot) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: TourismPlanUi.planCardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Would you like to visit “${spot.name}” again?',
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: AppColors.textDark,
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () async {
                    await SpotInteractionHistoryStore.instance
                        .setRepeatVisitPreference(
                      spot: spot,
                      visitAgain: true,
                    );
                    await HomePersonalizationService.instance.refresh();
                    if (mounted) setState(() {});
                  },
                  child: const Text('Yes, visit again'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton(
                  onPressed: () async {
                    await SpotInteractionHistoryStore.instance
                        .setRepeatVisitPreference(
                      spot: spot,
                      visitAgain: false,
                    );
                    await HomePersonalizationService.instance.refresh();
                    if (mounted) setState(() {});
                  },
                  child: const Text('No, other spots'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title, {required VoidCallback onTap}) {
    return Row(
      children: [
        Expanded(child: TourismPlanUi.sectionTitleBar(title: title)),
        TextButton.icon(
          onPressed: onTap,
          icon: const Icon(Icons.chevron_right_rounded, size: 20),
          label: const Text('See all'),
          style: TextButton.styleFrom(
            foregroundColor: AppColors.primary,
            textStyle: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildMunicipalityList(List<Municipality> recommended) {
    return SizedBox(
      height: 112,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: EdgeInsets.zero,
        itemCount: recommended.length,
        separatorBuilder: (_, _) => const SizedBox(width: 16),
        itemBuilder: (context, index) {
          final m = recommended[index];
          return GestureDetector(
            onTap: () {
              final muni = m;
              _tabNavKeys[0].currentState?.push(
                MaterialPageRoute<void>(
                  builder: (_) => MunicipalityDetailScreen(municipality: muni),
                ),
              );
            },
            child: TourismMunicipalityAvatar(
              label: m.shortName,
              size: 68,
              image: buildMunicipalityImageForMunicipality(
                m,
                memCacheWidth: 200,
                memCacheHeight: 200,
                fallback: const Center(
                  child: Icon(
                    Icons.location_city_rounded,
                    color: AppColors.primary,
                    size: 28,
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}


// ─── Featured Tourist Card (matches prior Home Featured UI) ──────────

class _FeaturedTouristCard extends StatelessWidget {
  final TouristSpot spot;
  const _FeaturedTouristCard({required this.spot});

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        buildTouristSpotProfileImage(
          spot,
          fallback: Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFF1A6B3C), Color(0xFF2E8B57)],
              ),
            ),
          ),
        ),
        Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Colors.transparent, Colors.black.withValues(alpha: 0.72)],
              stops: const [0.4, 1.0],
            ),
          ),
        ),
        Positioned(
          top: 14,
          left: 14,
          child: TourismPlanUi.dayBadge('Featured'),
        ),
        Positioned(
          left: 16,
          right: 16,
          bottom: 16,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (spot.priceRange.trim().isNotEmpty) ...[
                Text(
                  spot.priceRange,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    shadows: [Shadow(blurRadius: 4, color: Colors.black45)],
                  ),
                ),
                const SizedBox(height: 4),
              ],
              Row(
                children: [
                  Expanded(
                    child: Text(
                      spot.displayName,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        shadows: [Shadow(blurRadius: 6, color: Colors.black54)],
                      ),
                    ),
                  ),
                  StarRating(rating: spot.rating, size: 18),
                  const SizedBox(width: 6),
                  Text(
                    spot.rating > 0 ? spot.rating.toStringAsFixed(1) : '—',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ─── Spot Card ────────────────────────────────────────────────────────

class _SpotCard extends StatelessWidget {
  final TouristSpot spot;
  const _SpotCard({required this.spot});

  Widget _spotImagePlaceholder() {
    return Container(
      color: AppColors.primary.withValues(alpha: 0.08),
      child: const Center(
        child: Icon(Icons.landscape, size: 40, color: AppColors.primary),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: TourismPlanUi.planCardDecoration(),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: Stack(
              fit: StackFit.expand,
              children: [
                buildTouristSpotProfileImage(
                  spot,
                  memCacheWidth: 320,
                  memCacheHeight: 320,
                  fallback: _spotImagePlaceholder(),
                ),
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: Container(
                    padding: const EdgeInsets.fromLTRB(10, 28, 10, 10),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.transparent,
                          Colors.black.withValues(alpha: 0.75),
                        ],
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          spot.displayName,
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                            height: 1.2,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            if (spot.priceRange.trim().isNotEmpty)
                              Expanded(
                                child: Text(
                                  spot.priceRange,
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: Colors.white.withValues(alpha: 0.9),
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              )
                            else
                              const Spacer(),
                            Icon(
                              Icons.star,
                              size: 14,
                              color: Colors.amber.shade400,
                            ),
                            const SizedBox(width: 3),
                            Text(
                              spot.rating.toStringAsFixed(1),
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                color: Colors.white,
                              ),
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
        ],
      ),
    );
  }
}

/// Rebuilds a bottom-nav tab root when the tourism catalog or personalization
/// changes. Needed because each tab sits under a kept-alive [Navigator] route
/// that would otherwise keep the first (often empty) paint forever.
class _LiveShellTabRoot extends StatefulWidget {
  final Listenable listenable;
  final Widget Function() builder;

  const _LiveShellTabRoot({
    required this.listenable,
    required this.builder,
  });

  @override
  State<_LiveShellTabRoot> createState() => _LiveShellTabRootState();
}

class _LiveShellTabRootState extends State<_LiveShellTabRoot> {
  @override
  void initState() {
    super.initState();
    widget.listenable.addListener(_onChange);
  }

  @override
  void didUpdateWidget(covariant _LiveShellTabRoot oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.listenable != widget.listenable) {
      oldWidget.listenable.removeListener(_onChange);
      widget.listenable.addListener(_onChange);
    }
  }

  @override
  void dispose() {
    widget.listenable.removeListener(_onChange);
    super.dispose();
  }

  void _onChange() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) => widget.builder();
}

/// Home header: signed-in user's first name and profile photo; opens Profile.
class _HomeProfileButton extends StatefulWidget {
  final double size;
  final double nameMaxWidth;
  final VoidCallback onTap;

  const _HomeProfileButton({
    required this.size,
    required this.nameMaxWidth,
    required this.onTap,
  });

  @override
  State<_HomeProfileButton> createState() => _HomeProfileButtonState();
}

class _HomeProfileButtonState extends State<_HomeProfileButton> {
  // Streams are cached: the home screen rebuilds often (search typing, catalog
  // updates) and a fresh `.snapshots()` each build re-downloads the tourist doc.
  late final Stream<firebase_auth.User?> _authStream =
      firebase_auth.FirebaseAuth.instance.authStateChanges();
  String? _docUid;
  Stream<DocumentSnapshot<Map<String, dynamic>>>? _docStream;

  Stream<DocumentSnapshot<Map<String, dynamic>>>? _touristDocStream(
    String? uid,
  ) {
    if (uid != _docUid) {
      _docUid = uid;
      _docStream = uid == null
          ? null
          : FirebaseFirestore.instance
              .collection(kTouristCollection)
              .doc(uid)
              .snapshots();
    }
    return _docStream;
  }

  double get size => widget.size;
  double get nameMaxWidth => widget.nameMaxWidth;
  VoidCallback get onTap => widget.onTap;

  static String _firstWord(String? s) {
    final t = s?.trim() ?? '';
    if (t.isEmpty) return '';
    return t.split(RegExp(r'\s+')).first;
  }

  static String _firstName(
    Map<String, dynamic>? doc,
    firebase_auth.User? auth,
  ) {
    final fromDoc = (doc?['firstName'] as String?)?.trim() ?? '';
    if (fromDoc.isNotEmpty) return fromDoc;
    for (final candidate in [
      doc?['fullName'] as String?,
      doc?['name'] as String?,
      findAppUserByFirebaseUid(auth?.uid)?.name,
      auth?.displayName,
    ]) {
      final w = _firstWord(candidate);
      if (w.isNotEmpty && !w.contains('@')) return w;
    }
    final email = auth?.email?.trim() ?? '';
    if (email.contains('@')) return email.split('@').first;
    return 'Guest';
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<firebase_auth.User?>(
      stream: _authStream,
      initialData: firebase_auth.FirebaseAuth.instance.currentUser,
      builder: (context, authSnap) {
        final auth = authSnap.data;
        final uid = auth?.uid;
        final appUser = findAppUserByFirebaseUid(uid);
        return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
          stream: _touristDocStream(uid),
          builder: (context, docSnap) {
            final name = _firstName(docSnap.data?.data(), auth);
            return Tooltip(
              message: 'Profile',
              child: InkWell(
                borderRadius: BorderRadius.circular(size),
                onTap: onTap,
                child: Padding(
                  padding: const EdgeInsets.all(2),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      ConstrainedBox(
                        constraints: BoxConstraints(maxWidth: nameMaxWidth),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(
                              'Hello!',
                              style: TextStyle(
                                fontFamily: AppFonts.holidayCalling,
                                color: AppColors.primary,
                                fontSize: size * 0.4,
                                fontWeight: FontWeight.w400,
                                height: 1,
                              ),
                            ),
                            Text(
                              name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontFamily: AppFonts.holidayCalling,
                                color: AppColors.primary,
                                fontSize: size * 0.56,
                                fontWeight: FontWeight.w400,
                                height: 1,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border:
                              Border.all(color: AppColors.primary, width: 2.5),
                        ),
                        child: ProfileHeaderPhoto(
                          key: ValueKey(uid ?? 'guest'),
                          uid: uid,
                          initialPhotoPath: appUser?.profilePhotoPath,
                          authPhotoUrl: auth?.photoURL,
                          size: size,
                          fallbackIconColor: AppColors.primary,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }
}

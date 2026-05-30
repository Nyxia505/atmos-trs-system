import 'dart:async' show Timer, unawaited;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderAbstractViewport;
import 'package:atmos_trs_system/features/navigation/placeholder_pages.dart'
    show ScanTabPage;
import 'package:atmos_trs_system/services/app_welcome_prefs.dart';
import 'package:atmos_trs_system/widgets/new_user_welcome_dialog.dart';
import 'package:atmos_trs_system/navigation/tripplan_entry_screen.dart';
import 'package:atmos_trs_system/screens/municipality_map_and_spots_screen.dart';
import 'package:atmos_trs_system/utils/logo_utils.dart';
import 'package:atmos_trs_system/widgets/hero_video_branding_overlay.dart';
import 'package:atmos_trs_system/widgets/hero_video_mute_control.dart';
import 'package:atmos_trs_system/widgets/onboarding_hero_video.dart';
import 'package:atmos_trs_system/config/atmos_brand_typography.dart';

class LandingPage extends StatefulWidget {
  const LandingPage({super.key});

  @override
  State<LandingPage> createState() => _LandingPageState();
}

class _LandingPageState extends State<LandingPage>
    with TickerProviderStateMixin {
  late AnimationController _heroAnimationController;
  late AnimationController _fadeController;
  late Animation<double> _heroFadeAnimation;
  late Animation<Offset> _heroSlideAnimation;

  bool _isScrolled = false;
  int? _hoveredFeatureIndex;
  String? _hoveredDestinationName;

  String? _activeSection;

  late final ScrollController _pageScrollController;

  /// While true, skip scroll listener rebuilds (avoids jank during nav taps).
  bool _isNavScrollAnimating = false;

  Timer? _scrollUiThrottle;

  final TextEditingController _heroSearchController = TextEditingController();
  final FocusNode _heroSearchFocusNode = FocusNode();

  /// Extra terms for hero/destination search (municipality name → aliases).
  static const Map<String, List<String>> _destinationSearchAliases = {
    'oroquieta city': ['oroquieta', 'capitol', 'plaza', 'good life'],
    'ozamis city': ['ozamiz', 'ozámiz', 'cotta', 'fort', 'shrine', 'wellness'],
    'tangub city': ['tangub', 'global garden', 'garden', 'festival'],
    'don victoriano chiongbian': ['don victoriano', 'dvc', 'donvic', 'piduan'],
    'sinacaban': [
      'amorap',
      'aquamarine',
      'adventure park',
      'overwater',
      'resort',
    ],
    'sapang dalaga': ['sapang', 'floating', 'cristo', 'caluya', 'bay'],
    'lopez jaena': ['lopez', 'jaena', 'beach'],
    'bonifacio': ['mountain', 'rural'],
    'concepcion': ['falls', 'waterfall', 'jungle'],
    'plaridel': ['pool', 'tropical'],
    'tudela': ['highland', 'eco park', 'swimming'],
    'baliangao': ['cabgan', 'island', 'beach'],
    'jimenez': ['church', 'baptist', 'heritage'],
    'panaon': ['seaside', 'coast'],
    'calamba': ['hills', 'palm'],
    'clarin': ['green'],
    'aloran': ['viewpoint', 'scenic'],
  };

  final GlobalKey _keyHome = GlobalKey();
  final GlobalKey _keyChooseExperience = GlobalKey();
  final GlobalKey _keyFeatures = GlobalKey();
  final GlobalKey _keyDestinations = GlobalKey();
  final GlobalKey _keyHowItWorks = GlobalKey();
  final GlobalKey _keyAbout = GlobalKey();

  /// Landing page always uses Asenso orange (not Settings theme color).
  static const Color _primaryOrange = Color(0xFFF97316);
  static const Color _brandLight = Color(0xFFFB923C);
  static const Color _brandDark = Color(0xFFEA580C);
  static const Color _darkBg = Color(0xFF0F172A);
  static const Color _accentOrange = Color(0xFFFB923C);

  /// Page shell: crisp white with optional muted strips (avoids cream/peach page fills).
  static const Color _pageBackground = Color(0xFFFFFFFF);
  static const Color _pageSurfaceMuted = Color(0xFFF8FAFC);
  static const Color _pageDivider = Color(0xFFE5E7EB);

  static const String _kAtmosTrsFullName =
      'Asenso Tourismo Misamis Occidental Smart Tourist Registration System';

  static const String _kTourismLogoAsset = 'assets/images/tourism logo.png';

  /// Soft tinted card backgrounds + accents (Asenso orange / cream family).
  final List<Map<String, dynamic>> _features = [
    {
      'icon': Icons.qr_code_rounded,
      'title': 'QR Code Registration',
      'description':
          'Quick and easy tourist registration with unique QR code identification',
      'bgStart': const Color(0xFFFFF7ED),
      'bgEnd': const Color(0xFFFFEDD5),
      'accent': _primaryOrange,
    },
    {
      'icon': Icons.vrpano_rounded,
      'title': 'Virtual Reality Tours',
      'description':
          'Explore destinations in immersive 360° VR before you visit',
      'bgStart': const Color(0xFFFEF3C7),
      'bgEnd': const Color(0xFFFDE68A),
      'accent': _brandDark,
    },
    {
      'icon': Icons.qr_code_scanner_rounded,
      'title': 'Smart Check-ins',
      'description':
          'Scan your QR at tourist spots for seamless check-in experience',
      'bgStart': const Color(0xFFFFFBEB),
      'bgEnd': const Color(0xFFFEF3C7),
      'accent': const Color(0xFFD97706),
    },
    {
      'icon': Icons.badge_rounded,
      'title': 'Digital Tourist ID',
      'description':
          'Your unique digital identification for all tourist activities',
      'bgStart': const Color(0xFFFFF7ED),
      'bgEnd': const Color(0xFFFFEDD5),
      'accent': _brandDark,
    },
    {
      'icon': Icons.map_rounded,
      'title': 'Itinerary Planner',
      'description': 'Plan and organize your travel itinerary',
      'bgStart': const Color(0xFFFFF7ED),
      'bgEnd': const Color(0xFFFFEDD5),
      'accent': const Color(0xFFEA580C),
      'route': 'itinerary',
    },
  ];

  final List<Map<String, String>> _destinations = [
    {
      'name': 'Oroquieta City',
      'category': 'Capital City',
      'description':
          'The provincial capital and seat of the capitol building, known as the "City of Good Life"',
      'image': 'assets/images/Orquieta Plaza.png',
      'isAsset': 'true',
    },
    {
      'name': 'Ozamis City',
      'category': 'City',
      'description': 'Rich in history and culture with beautiful coastal views',
      'image': 'assets/images/ozamis city.webp',
      'isAsset': 'true',
    },
    {
      'name': 'Tangub City',
      'category': 'City',
      'description':
          'Home to Asenso Global Gardens and gateway to pristine coasts',
      'image': 'assets/images/Asenso Global Garden 1.png',
      'isAsset': 'true',
    },
    {
      'name': 'Aloran',
      'category': 'Municipality',
      'description': 'Scenic landscapes and welcoming communities',
      'image':
          'https://images.unsplash.com/photo-1507525428034-b723cf961d3e?w=800',
      'isAsset': 'false',
    },
    {
      'name': 'Baliangao',
      'category': 'Municipality',
      'description':
          'Cabgan Island and pristine beaches with crystal clear waters',
      'image': 'assets/images/Baliangao - Cabgan Island.jpg',
      'isAsset': 'true',
    },
    {
      'name': 'Bonifacio',
      'category': 'Municipality',
      'description': 'Mountain views and rural charm',
      'image': 'assets/images/Piduan Falls Donvic.jpg',
      'isAsset': 'true',
    },
    {
      'name': 'Calamba',
      'category': 'Municipality',
      'description':
          'Lush green town amid rolling forested hills, palm trees, and serene community',
      'image': 'assets/images/CALAMBA.jpg',
      'isAsset': 'true',
    },
    {
      'name': 'Clarin',
      'category': 'Municipality',
      'description': 'Green landscapes and local hospitality',
      'image': 'assets/images/clarin.jpg',
      'isAsset': 'true',
    },
    {
      'name': 'Concepcion',
      'category': 'Municipality',
      'description':
          'Stunning multi-tiered waterfalls, rocky rivers, and lush tropical jungle',
      'image': 'assets/images/conception.png',
      'isAsset': 'true',
    },
    {
      'name': 'Don Victoriano Chiongbian',
      'category': 'Municipality',
      'description': 'Piduan Falls and lush mountain forests',
      'image': 'assets/images/Piduan Falls Donvic.jpg',
      'isAsset': 'true',
    },
    {
      'name': 'Jimenez',
      'category': 'Municipality',
      'description': 'St. John the Baptist Church and heritage sites',
      'image': 'assets/images/Jimenez - St. John the Baptist Church.jpg',
      'isAsset': 'true',
    },
    {
      'name': 'Lopez Jaena',
      'category': 'Municipality',
      'description': 'Beaches and coastal living',
      'image': 'assets/images/Panaon.webp',
      'isAsset': 'true',
    },
    {
      'name': 'Panaon',
      'category': 'Municipality',
      'description': 'Seaside towns and natural attractions',
      'image': 'assets/images/Panaon.webp',
      'isAsset': 'true',
    },
    {
      'name': 'Plaridel',
      'category': 'Municipality',
      'description':
          'Tropical pool resort with thatched bridges, palm trees, and clear blue waters',
      'image': 'assets/images/PLARIDEL.jpg',
      'isAsset': 'true',
    },
    {
      'name': 'Sapang Dalaga',
      'category': 'Municipality',
      'description':
          'Caluya Bay with floating playground and Cristo Redentor views',
      'image': 'assets/images/Sapang Dalaga.png',
      'isAsset': 'true',
    },
    {
      'name': 'Sinacaban',
      'category': 'Municipality',
      'description':
          'Home to AMORAP — Maldives-inspired eco-luxury park with overwater villas, lagoons, and coastal adventure',
      'image': 'assets/images/AMORAP.jpg',
      'isAsset': 'true',
    },
    {
      'name': 'Tudela',
      'category': 'Municipality',
      'description':
          'Swimming pools, resort amenities, and festivals in a lush tropical setting',
      'image': 'assets/images/Tudela Village.webp',
      'isAsset': 'true',
    },
  ];

  final List<Map<String, dynamic>> _steps = [
    {
      'number': '01',
      'title': 'Register',
      'description': 'Create your tourist account with basic information',
      'icon': Icons.person_add_rounded,
    },
    {
      'number': '02',
      'title': 'Get QR Code',
      'description': 'Receive your unique tourist QR identification',
      'icon': Icons.qr_code_2_rounded,
    },
    {
      'number': '03',
      'title': 'Explore / Preview',
      'description': 'Browse destinations and preview spots in VR',
      'icon': Icons.explore_rounded,
    },
    {
      'number': '04',
      'title': 'Plan Itinerary',
      'description':
          'Organize your trip and add destinations to your itinerary',
      'icon': Icons.map_rounded,
    },
    {
      'number': '05',
      'title': 'Check-in',
      'description': 'Scan your QR at each destination you visit',
      'icon': Icons.check_circle_rounded,
    },
  ];

  @override
  void initState() {
    super.initState();
    _pageScrollController = ScrollController();

    _heroAnimationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );
    _fadeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );

    _heroFadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _heroAnimationController, curve: Curves.easeOut),
    );

    _heroSlideAnimation =
        Tween<Offset>(begin: const Offset(0, 0.3), end: Offset.zero).animate(
          CurvedAnimation(
            parent: _heroAnimationController,
            curve: Curves.easeOutCubic,
          ),
        );

    _heroAnimationController.forward();
    _fadeController.forward();

    _heroSearchController.addListener(_onHeroSearchTextChanged);
    _heroSearchFocusNode.addListener(_onHeroSearchFocusChanged);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _maybeShowNewUserWelcome();
    });
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      try {
        final v = OnboardingHeroVideo.of(context);
        await v.ensureVideoPlaying();
        await v.resumeAfterLandingIfRemembered();
        await v.applySessionAudioToController();
      } catch (e, st) {
        debugPrint('Landing hero video: $e\n$st');
      }
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Keep player warm when inherited deps change (not for handoff — that runs in initState).
    unawaited(OnboardingHeroVideo.of(context).ensureVideoPlaying());
  }

  Future<void> _maybeShowNewUserWelcome() async {
    final show = await AppWelcomePrefs.shouldShowLandingWelcome();
    if (!mounted || !show) return;
    await showNewUserWelcomeDialog(context);
    if (mounted) await AppWelcomePrefs.markLandingWelcomeShown();
  }

  void _muteHeroVideoForAuthNavigation() {
    unawaited(OnboardingHeroVideo.of(context).setHeroVideoMuted(true));
  }

  void _navigateToLogin() {
    _muteHeroVideoForAuthNavigation();
    Navigator.of(context).pushNamed('/login');
  }

  static const List<String> _sectionOrder = [
    'home',
    'chooseExperience',
    'features',
    'destinations',
    'howItWorks',
    'about',
  ];

  /// Scroll offset where a section starts (relative to page [ScrollController]).
  double? _scrollOffsetForSection(GlobalKey key) {
    final ctx = key.currentContext;
    if (ctx == null) return null;
    final renderObject = ctx.findRenderObject();
    if (renderObject is! RenderBox || !renderObject.hasSize) return null;
    final viewport = RenderAbstractViewport.maybeOf(renderObject);
    if (viewport == null) return null;
    return viewport.getOffsetToReveal(renderObject, 0.0).offset;
  }

  /// Line under the app bar used to decide which section is "active" while scrolling.
  double _scrollProbeY(double scrollOffset) {
    final padTop = MediaQuery.paddingOf(context).top;
    final barHeight = _useDrawerNav ? (_isMobile ? 100.0 : 88.0) : 72.0;
    return scrollOffset + padTop + barHeight + 20;
  }

  String _detectActiveSection(double scrollOffset) {
    var active = 'home';
    for (final sectionId in _sectionOrder) {
      final key = _sectionKey(sectionId);
      if (key == null) continue;
      final sectionTop = _scrollOffsetForSection(key);
      if (sectionTop == null) continue;
      if (_scrollProbeY(scrollOffset) >= sectionTop - 56) {
        active = sectionId;
      }
    }
    return active;
  }

  void _applyScrollUiState(double offset) {
    if (!mounted) return;

    final newIsScrolled = offset > 50;
    final newActive = _detectActiveSection(offset);

    if (newIsScrolled != _isScrolled || newActive != _activeSection) {
      setState(() {
        _isScrolled = newIsScrolled;
        _activeSection = newActive;
      });
    }
  }

  void _onScroll(double offset) {
    if (!mounted || _isNavScrollAnimating) return;

    _scrollUiThrottle?.cancel();
    _scrollUiThrottle = Timer(const Duration(milliseconds: 48), () {
      if (!mounted || _isNavScrollAnimating) return;
      _applyScrollUiState(offset);
    });
  }

  void _onHeroSearchTextChanged() {
    if (mounted) setState(() {});
  }

  void _onHeroSearchFocusChanged() {
    if (mounted) setState(() {});
  }

  String _destinationSearchHaystack(Map<String, String> destination) {
    final name = (destination['name'] ?? '').trim();
    final aliases =
        _destinationSearchAliases[name.toLowerCase()] ?? const <String>[];
    return [
      name,
      destination['category'],
      destination['description'],
      destination['keywords'],
      ...aliases,
    ].whereType<String>().join(' ').toLowerCase();
  }

  List<Map<String, String>> get _filteredDestinations {
    final query = _heroSearchController.text.trim().toLowerCase();
    if (query.isEmpty) return _destinations;
    final terms = query
        .split(RegExp(r'\s+'))
        .where((t) => t.isNotEmpty)
        .toList();
    return _destinations.where((d) {
      final haystack = _destinationSearchHaystack(d);
      return terms.every(haystack.contains);
    }).toList();
  }

  void _clearHeroSearch() {
    _heroSearchController.clear();
    _heroSearchFocusNode.unfocus();
    setState(() {});
  }

  Future<void> _submitHeroSearch([String? raw]) async {
    final query = (raw ?? _heroSearchController.text).trim();
    if (query.isEmpty) return;
    _heroSearchFocusNode.unfocus();
    await _scrollToSection('destinations');
  }

  Future<void> _selectDestinationFromSearch(
    Map<String, String> destination,
  ) async {
    _heroSearchController.text = destination['name'] ?? '';
    _heroSearchFocusNode.unfocus();
    setState(() {});
    await _scrollToSection('destinations');
  }

  @override
  void dispose() {
    _scrollUiThrottle?.cancel();
    _heroSearchController.removeListener(_onHeroSearchTextChanged);
    _heroSearchFocusNode.removeListener(_onHeroSearchFocusChanged);
    _heroSearchController.dispose();
    _heroSearchFocusNode.dispose();
    OnboardingHeroVideo.read(context)?.releaseLandingHeroVideo();
    _pageScrollController.dispose();
    _heroAnimationController.dispose();
    _fadeController.dispose();
    super.dispose();
  }

  bool get _isMobile => MediaQuery.of(context).size.width < 768;
  bool get _isTablet =>
      MediaQuery.of(context).size.width >= 768 &&
      MediaQuery.of(context).size.width < 1024;

  /// Drawer + menu button for phones and tablets.
  bool get _useDrawerNav => MediaQuery.of(context).size.width < 1024;

  /// Smaller nav chips when horizontal space is limited.
  bool get _navCompact => MediaQuery.of(context).size.width < 1280;

  /// Shorter nav labels so all items fit on the right without clipping.
  bool get _navTight => MediaQuery.of(context).size.width < 1200;

  /// Full tagline beside logo on wide desktops only.
  bool get _showAppBarTagline =>
      !_useDrawerNav && MediaQuery.of(context).size.width >= 1280;

  static const List<({String label, String sectionId, IconData icon})>
  _landingNavItems = [
    (label: 'Home', sectionId: 'home', icon: Icons.home_rounded),
    (
      label: 'Experience',
      sectionId: 'chooseExperience',
      icon: Icons.explore_rounded,
    ),
    (
      label: 'Features',
      sectionId: 'features',
      icon: Icons.auto_awesome_rounded,
    ),
    (
      label: 'Destinations',
      sectionId: 'destinations',
      icon: Icons.location_city_rounded,
    ),
    (label: 'How It Works', sectionId: 'howItWorks', icon: Icons.route_rounded),
    (label: 'About', sectionId: 'about', icon: Icons.info_outline_rounded),
  ];

  GlobalKey? _sectionKey(String section) {
    return switch (section) {
      'home' => _keyHome,
      'chooseExperience' => _keyChooseExperience,
      'features' => _keyFeatures,
      'destinations' => _keyDestinations,
      'howItWorks' => _keyHowItWorks,
      'about' => _keyAbout,
      _ => null,
    };
  }

  void _onNavTap(String section) {
    if (_activeSection != section) {
      setState(() => _activeSection = section);
    }
    unawaited(_scrollToSection(section));
  }

  Future<void> _scrollToSection(String section) async {
    final targetContext = _sectionKey(section)?.currentContext;
    if (targetContext == null ||
        !targetContext.mounted ||
        !_pageScrollController.hasClients) {
      return;
    }

    final renderObject = targetContext.findRenderObject();
    if (renderObject is! RenderBox || !renderObject.hasSize) return;

    final viewport = RenderAbstractViewport.maybeOf(renderObject);
    if (viewport == null) return;

    final targetOffset = viewport
        .getOffsetToReveal(renderObject, 0.08)
        .offset
        .clamp(0.0, _pageScrollController.position.maxScrollExtent);

    if ((_pageScrollController.offset - targetOffset).abs() < 8) return;

    _isNavScrollAnimating = true;
    _scrollUiThrottle?.cancel();

    try {
      await _pageScrollController.animateTo(
        targetOffset,
        duration: const Duration(milliseconds: 460),
        curve: Curves.easeOutCubic,
      );
    } finally {
      if (mounted) {
        _isNavScrollAnimating = false;
        setState(() {
          _activeSection = section;
          _isScrolled = _pageScrollController.offset > 50;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _pageBackground,
      extendBodyBehindAppBar: true,
      appBar: _buildAppBar(),
      drawer: _useDrawerNav ? _buildNavDrawer() : null,
      body: NotificationListener<ScrollNotification>(
        onNotification: (notification) {
          if (notification.metrics.axis == Axis.vertical) {
            _onScroll(notification.metrics.pixels);
          }
          return false;
        },
        child: SingleChildScrollView(
          controller: _pageScrollController,
          physics: kIsWeb
              ? const ClampingScrollPhysics(
                  parent: AlwaysScrollableScrollPhysics(),
                )
              : const BouncingScrollPhysics(
                  parent: AlwaysScrollableScrollPhysics(),
                ),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              minHeight: MediaQuery.of(context).size.height,
              maxWidth: MediaQuery.of(context).size.width,
            ),
            child: Column(
              children: [
                Container(key: _keyHome, child: _buildHeroSection()),
                _buildRegisterCalloutSection(),
                Container(
                  key: _keyChooseExperience,
                  child: _buildChooseYourExperienceSection(),
                ),
                Container(key: _keyFeatures, child: _buildFeaturesSection()),
                Container(
                  key: _keyDestinations,
                  child: _buildDestinationsSection(),
                ),
                Container(
                  key: _keyHowItWorks,
                  child: _buildHowItWorksSection(),
                ),
                _buildStatisticsSection(),
                Container(key: _keyAbout, child: _buildAboutSection()),
                _buildFooter(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  PreferredSizeWidget _buildAppBar() {
    final barHeight = _useDrawerNav ? (_isMobile ? 100.0 : 88.0) : 72.0;
    return PreferredSize(
      preferredSize: Size.fromHeight(barHeight),
      child: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [_primaryOrange, _brandLight],
          ),
          boxShadow: [
            BoxShadow(
              color: _primaryOrange.withValues(alpha: 0.35),
              blurRadius: 16,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          toolbarHeight: barHeight,
          leadingWidth: 0,
          leading: const SizedBox.shrink(),
          titleSpacing: 0,
          title: Padding(
            padding: EdgeInsets.only(
              left: _useDrawerNav ? 4 : 16,
              right: _useDrawerNav ? 8 : 20,
            ),
            child: Row(
              children: [
                if (_useDrawerNav)
                  Builder(
                    builder: (context) => IconButton(
                      padding: EdgeInsets.zero,
                      visualDensity: VisualDensity.compact,
                      constraints: const BoxConstraints(
                        minWidth: 44,
                        minHeight: 44,
                      ),
                      icon: const Icon(Icons.menu_rounded, color: Colors.white),
                      onPressed: () => Scaffold.of(context).openDrawer(),
                    ),
                  ),
                if (_useDrawerNav) const SizedBox(width: 2),
                _buildAppBarLogoMark(size: _useDrawerNav ? 40 : 36),
                SizedBox(width: _useDrawerNav ? 12 : 10),
                if (_useDrawerNav)
                  Expanded(
                    child: _buildAppBarBrandText(
                      titleSize: 22,
                      showTagline: true,
                    ),
                  )
                else if (_showAppBarTagline)
                  Flexible(
                    fit: FlexFit.loose,
                    child: ConstrainedBox(
                      constraints: BoxConstraints(
                        maxWidth: MediaQuery.sizeOf(context).width * 0.34,
                      ),
                      child: _buildAppBarBrandText(
                        titleSize: 24,
                        showTagline: true,
                      ),
                    ),
                  )
                else
                  Text(
                    'ATMOS TRS',
                    style: AtmosBrandTypography.displayTitle(
                      color: Colors.white,
                      fontSize: 20,
                      letterSpacing: 0.5,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
              ],
            ),
          ),
          actions: [
            ListenableBuilder(
              listenable: OnboardingHeroVideo.of(context),
              builder: (context, _) {
                final hero = OnboardingHeroVideo.of(context);
                if (!hero.showVideoOnLandingHero) {
                  return const SizedBox.shrink();
                }
                return Padding(
                  padding: const EdgeInsets.only(right: 4),
                  child: HeroVideoMuteControl(
                    forAppBar: true,
                    iconSize: _isMobile ? 20 : 22,
                  ),
                );
              },
            ),
            if (!_useDrawerNav)
              Padding(
                padding: const EdgeInsets.only(right: 12),
                child: _buildInlineNavBar(),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildAppBarLogoMark({required double size}) {
    return Container(
      padding: const EdgeInsets.all(5),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.22),
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: SizedBox(
        height: size,
        width: size,
        child: TransparentLogo(
          height: size,
          width: size,
          fit: BoxFit.contain,
          errorIcon: Icons.travel_explore_rounded,
          errorIconSize: size * 0.65,
          errorIconColor: Colors.white,
        ),
      ),
    );
  }

  Widget _buildAppBarBrandText({
    required double titleSize,
    required bool showTagline,
  }) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          'ATMOS TRS',
          style: AtmosBrandTypography.displayTitle(
            color: Colors.white,
            fontSize: titleSize,
            letterSpacing: 0.6,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        if (showTagline)
          Text(
            _kAtmosTrsFullName,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.92),
              fontSize: _useDrawerNav ? 9.5 : 10.5,
              fontWeight: FontWeight.w500,
              height: 1.25,
              letterSpacing: 0.15,
            ),
            maxLines: _useDrawerNav ? 3 : 2,
            overflow: TextOverflow.ellipsis,
          ),
      ],
    );
  }

  Widget _buildInlineNavBar() {
    final compact = _navCompact;
    final screenWidth = MediaQuery.sizeOf(context).width;
    final maxNavWidth = screenWidth * 0.58;

    return ConstrainedBox(
      constraints: BoxConstraints(maxWidth: maxNavWidth),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        reverse: false,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final item in _landingNavItems)
              _buildNavChip(
                label: _navChipLabel(item),
                onTap: () => _onNavTap(item.sectionId),
                isActive: _activeSection == item.sectionId,
                compact: compact,
              ),
          ],
        ),
      ),
    );
  }

  String _navChipLabel(({String label, String sectionId, IconData icon}) item) {
    if (!_navTight) return item.label;
    return switch (item.sectionId) {
      'howItWorks' => 'Steps',
      'destinations' => 'Places',
      _ => item.label,
    };
  }

  Widget _buildNavChip({
    required String label,
    required VoidCallback onTap,
    required bool isActive,
    bool compact = false,
  }) {
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: compact ? 3 : 4),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(24),
          hoverColor: Colors.white.withValues(alpha: 0.14),
          splashColor: Colors.white.withValues(alpha: 0.2),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            curve: Curves.easeOut,
            padding: EdgeInsets.symmetric(
              horizontal: compact ? 10 : 14,
              vertical: compact ? 7 : 8,
            ),
            decoration: BoxDecoration(
              color: isActive
                  ? Colors.white
                  : Colors.white.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(
                color: Colors.white.withValues(alpha: isActive ? 0.95 : 0.28),
                width: isActive ? 1.5 : 1,
              ),
              boxShadow: isActive
                  ? [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.12),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      ),
                    ]
                  : null,
            ),
            child: Text(
              label,
              style: TextStyle(
                color: isActive ? _primaryOrange : Colors.white,
                fontSize: compact ? 12.5 : 14,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.15,
                height: 1.15,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildNavDrawer() {
    return Drawer(
      backgroundColor: Colors.white,
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              padding: const EdgeInsets.fromLTRB(24, 24, 24, 20),
              decoration: BoxDecoration(
                color: _primaryOrange,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.1),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      const Icon(
                        Icons.travel_explore_rounded,
                        color: Colors.white,
                        size: 28,
                      ),
                      const SizedBox(width: 12),
                      Text(
                        'ATMOS TRS',
                        style: AtmosBrandTypography.displayTitle(
                          color: Colors.white,
                          fontSize: 22,
                          letterSpacing: 0.6,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    _kAtmosTrsFullName,
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.92),
                      fontSize: 11,
                      fontWeight: FontWeight.w500,
                      height: 1.35,
                      letterSpacing: 0.15,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            ..._landingNavItems.map((item) {
              final isActive = _activeSection == item.sectionId;
              return ListTile(
                leading: Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: isActive
                        ? _primaryOrange.withValues(alpha: 0.14)
                        : Colors.grey.shade100,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    item.icon,
                    size: 20,
                    color: isActive ? _primaryOrange : Colors.grey.shade600,
                  ),
                ),
                title: Text(
                  item.label,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: isActive ? FontWeight.w700 : FontWeight.w600,
                    height: 1.2,
                    letterSpacing: 0.15,
                    color: isActive ? _primaryOrange : _darkBg,
                  ),
                ),
                trailing: isActive
                    ? Icon(
                        Icons.check_circle_rounded,
                        color: _primaryOrange,
                        size: 20,
                      )
                    : null,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                onTap: () {
                  Navigator.pop(context);
                  _onNavTap(item.sectionId);
                },
              );
            }),
            if (!kIsWeb)
              ListTile(
                leading: Icon(
                  Icons.qr_code_scanner_rounded,
                  color: _primaryOrange,
                ),
                title: const Text('Scan QR to check in'),
                subtitle: Text(
                  'Municipality or tourist spot',
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                ),
                onTap: () {
                  Navigator.pop(context);
                  Navigator.push<void>(
                    context,
                    MaterialPageRoute<void>(
                      builder: (_) => const ScanTabPage(guestMode: true),
                    ),
                  );
                },
              )
            else
              ListTile(
                leading: Icon(
                  Icons.qr_code_scanner_rounded,
                  color: Colors.grey.shade400,
                ),
                title: const Text('Scan QR to check in'),
                subtitle: const Text(
                  'Available in the mobile app',
                  style: TextStyle(fontSize: 12, color: Colors.grey),
                ),
                onTap: () {
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text(
                        'QR scanning runs in the ATMOS TRS mobile app. '
                        'Download the app to scan municipality or spot codes.',
                      ),
                      behavior: SnackBarBehavior.floating,
                    ),
                  );
                },
              ),
            const Divider(height: 24),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () {
                        _muteHeroVideoForAuthNavigation();
                        Navigator.pop(context);
                        Navigator.pushNamed(context, '/login');
                      },
                      style: OutlinedButton.styleFrom(
                        foregroundColor: _primaryOrange,
                        side: BorderSide(color: _primaryOrange),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                      child: const Text('Sign In'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton(
                      onPressed: () {
                        _muteHeroVideoForAuthNavigation();
                        Navigator.pop(context);
                        Navigator.pushNamed(context, '/signup');
                      },
                      style: FilledButton.styleFrom(
                        backgroundColor: _primaryOrange,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                      child: const Text('Sign Up'),
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

  Widget _buildHeroSection() {
    final h = MediaQuery.sizeOf(context).height;
    final heroVideo = OnboardingHeroVideo.of(context);
    final showVideo = heroVideo.showVideoOnLandingHero;
    final videoController = heroVideo.controller;

    return SizedBox(
      height: h,
      width: double.infinity,
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (showVideo && videoController != null)
            OnboardingVideoBackground(controller: videoController)
          else
            Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [Color(0xFF1E293B), Color(0xFF0F172A)],
                ),
              ),
            ),
          Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  const Color(0xFF0F172A).withOpacity(showVideo ? 0.16 : 0.45),
                  const Color(0xFF0F172A).withOpacity(showVideo ? 0.56 : 0.88),
                ],
              ),
            ),
          ),
          Positioned(
            top: -80,
            right: -60,
            child: IgnorePointer(
              child: Container(
                width: 280,
                height: 280,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [
                      _primaryOrange.withOpacity(0.25),
                      _primaryOrange.withOpacity(0),
                    ],
                  ),
                ),
              ),
            ),
          ),
          if (showVideo && videoController != null)
            Positioned(
              top:
                  MediaQuery.paddingOf(context).top + (_isMobile ? 88.0 : 76.0),
              left: 0,
              right: 0,
              child: const SizedBox(
                width: double.infinity,
                child: HeroVideoBrandingOverlay(compact: true),
              ),
            ),
          if (showVideo && videoController != null)
            Positioned(
              right: 12,
              bottom: MediaQuery.paddingOf(context).bottom + 16,
              child: const HeroVideoMuteControl(iconSize: 24),
            ),
          Center(
            child: FadeTransition(
              opacity: _heroFadeAnimation,
              child: SlideTransition(
                position: _heroSlideAnimation,
                child: SingleChildScrollView(
                  clipBehavior: Clip.none,
                  padding: EdgeInsets.symmetric(
                    horizontal: _isMobile ? 22 : 56,
                  ),
                  child: ConstrainedBox(
                    constraints: BoxConstraints(minHeight: h),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        SizedBox(height: _isMobile ? 88 : 96),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 8,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.14),
                            borderRadius: BorderRadius.circular(28),
                            border: Border.all(
                              color: Colors.white.withOpacity(0.28),
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              Padding(
                                padding: EdgeInsets.only(
                                  top: _isMobile ? 9.0 : 7.0,
                                ),
                                child: SizedBox(
                                  height: _isMobile ? 22 : 26,
                                  width: _isMobile ? 34 : 40,
                                  child: Image.asset(
                                    _kTourismLogoAsset,
                                    fit: BoxFit.contain,
                                    alignment: Alignment.centerLeft,
                                    errorBuilder: (_, __, ___) => Icon(
                                      Icons.travel_explore_rounded,
                                      color: _accentOrange,
                                      size: 18,
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Text(
                                'Misamis Occidental · Smart tourism',
                                style: TextStyle(
                                  color: Colors.white.withOpacity(0.95),
                                  fontSize: _isMobile ? 12.5 : 13.5,
                                  fontWeight: FontWeight.w600,
                                  letterSpacing: 0.3,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 24),
                        Column(
                          children: [
                            Text(
                              'Discover Misamis Occidental',
                              textAlign: TextAlign.center,
                              style: AtmosBrandTypography.heroHeadline(
                                color: Colors.white,
                                fontSize: _isMobile ? 34 : 50,
                                shadows: const [
                                  Shadow(
                                    offset: Offset(0, 2),
                                    blurRadius: 16,
                                    color: Color(0x66000000),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              'Your journey starts here',
                              textAlign: TextAlign.center,
                              style: AtmosBrandTypography.heroHeadline(
                                color: Colors.white,
                                fontSize: _isMobile ? 26 : 36,
                                shadows: const [
                                  Shadow(
                                    offset: Offset(0, 2),
                                    blurRadius: 12,
                                    color: Color(0x55000000),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 20),
                        Center(child: _buildHeroSearchBarLight()),
                        const SizedBox(height: 20),
                        Text(
                          'Walk destinations in immersive 360°, map your dream itinerary, '
                          'and discover all 17 LGUs — before you even pack your bags.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: Colors.white.withOpacity(0.9),
                            fontSize: _isMobile ? 15 : 17,
                            height: 1.55,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        const SizedBox(height: 20),
                        Wrap(
                          spacing: 10,
                          runSpacing: 10,
                          alignment: WrapAlignment.center,
                          children: [
                            _buildHeroChip(
                              Icons.vrpano_rounded,
                              '360° previews',
                            ),
                            _buildHeroChip(Icons.route_rounded, 'Trip planner'),
                            _buildHeroChip(
                              Icons.location_city_rounded,
                              '17 LGUs',
                            ),
                          ],
                        ),
                        const SizedBox(height: 28),
                        _buildHeroExploreLaunchpad(),
                        const SizedBox(height: 20),
                        TextButton(
                          onPressed: () {
                            _muteHeroVideoForAuthNavigation();
                            Navigator.pushNamed(context, '/signup');
                          },
                          style: TextButton.styleFrom(
                            foregroundColor: Colors.white.withOpacity(0.85),
                          ),
                          child: Text(
                            'Ready to visit? Create your free tourist ID →',
                            style: TextStyle(
                              fontSize: _isMobile ? 13 : 14,
                              fontWeight: FontWeight.w600,
                              decoration: TextDecoration.underline,
                              decorationColor: Colors.white.withOpacity(0.45),
                            ),
                          ),
                        ),
                        const SizedBox(height: 40),
                        GestureDetector(
                          onTap: () => _scrollToSection('chooseExperience'),
                          child: Column(
                            children: [
                              Text(
                                'Scroll to explore',
                                style: TextStyle(
                                  color: Colors.white.withOpacity(0.55),
                                  fontSize: 13,
                                ),
                              ),
                              const SizedBox(height: 6),
                              Icon(
                                Icons.keyboard_arrow_down_rounded,
                                color: Colors.white.withOpacity(0.55),
                                size: 28,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _openPlanItinerary() {
    _muteHeroVideoForAuthNavigation();
    final heroController = OnboardingHeroVideo.read(context)?.controller;
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (context) => TripPlanEntryScreen(
          sharedHeroController: heroController,
        ),
      ),
    );
  }

  Widget _buildHeroExploreLaunchpad() {
    final screenWidth = MediaQuery.sizeOf(context).width;
    final cardMaxWidth = _isMobile
        ? (screenWidth - 48).clamp(260.0, 340.0)
        : 440.0;

    final vrCard = _buildHeroExploreActionCard(
      title: 'Start VR Tour',
      subtitle: '360° previews of AMORAP & top spots',
      icon: Icons.vrpano_rounded,
      badge: 'Popular',
      accentColor: _primaryOrange,
      onTap: _navigateToLogin,
    );

    final itineraryCard = _buildHeroExploreActionCard(
      title: 'Plan your itinerary',
      subtitle: 'Map LGUs & build your day-by-day route',
      icon: Icons.map_rounded,
      badge: 'Planner',
      accentColor: const Color(0xFF38BDF8),
      onTap: _openPlanItinerary,
    );

    return Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: cardMaxWidth),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            if (_isMobile)
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.auto_awesome_rounded,
                    size: 16,
                    color: _accentOrange.withValues(alpha: 0.95),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Start exploring — no booking, just discovery',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.92),
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.2,
                    ),
                  ),
                ],
              )
            else
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.auto_awesome_rounded,
                    size: 16,
                    color: _accentOrange.withValues(alpha: 0.95),
                  ),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      'Start exploring — no booking, just discovery',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.92),
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.2,
                      ),
                    ),
                  ),
                ],
              ),
            const SizedBox(height: 10),
            if (_isMobile)
              Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  SizedBox(width: cardMaxWidth, child: vrCard),
                  const SizedBox(height: 10),
                  SizedBox(width: cardMaxWidth, child: itineraryCard),
                ],
              )
            else
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: vrCard),
                  const SizedBox(width: 10),
                  Expanded(child: itineraryCard),
                ],
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeroExploreActionCard({
    required String title,
    required String subtitle,
    required IconData icon,
    required String badge,
    required Color accentColor,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Ink(
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: accentColor.withValues(alpha: 0.42),
            ),
          ),
          padding: EdgeInsets.symmetric(
            horizontal: _isMobile ? 12 : 14,
            vertical: _isMobile ? 10 : 12,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: accentColor.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(icon, color: Colors.white, size: 20),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Align(
                      alignment: Alignment.centerRight,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.22),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          badge,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.2,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: Colors.white,
                  fontSize: _isMobile ? 16 : 17,
                  fontWeight: FontWeight.w800,
                  height: 1.1,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                subtitle,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.9),
                  fontSize: _isMobile ? 11.5 : 12,
                  height: 1.3,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 8),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Tap to open',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.9),
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Icon(
                    Icons.arrow_forward_rounded,
                    size: 14,
                    color: Colors.white.withValues(alpha: 0.9),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeroChip(IconData icon, String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.1),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withOpacity(0.2)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: _accentOrange),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              color: Colors.white.withOpacity(0.92),
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeroSearchBarLight() {
    final query = _heroSearchController.text.trim();
    final showSuggestions = _heroSearchFocusNode.hasFocus && query.isNotEmpty;
    final suggestions = showSuggestions
        ? _filteredDestinations.take(6).toList()
        : const <Map<String, String>>[];

    const searchBarHeight = 48.0;
    final screenWidth = MediaQuery.sizeOf(context).width;
    final barWidth = _isMobile
        ? (screenWidth - 48).clamp(280.0, 380.0)
        : 520.0;

    return SizedBox(
      width: barWidth,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Container(
            height: searchBarHeight,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.12),
              borderRadius: BorderRadius.circular(28),
              border: Border.all(color: Colors.white.withOpacity(0.22)),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.search_rounded,
                  color: Colors.white.withOpacity(0.7),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Theme(
                    data: Theme.of(context).copyWith(
                      canvasColor: Colors.transparent,
                      inputDecorationTheme: const InputDecorationTheme(
                        filled: true,
                        fillColor: Colors.transparent,
                        border: InputBorder.none,
                        enabledBorder: InputBorder.none,
                        focusedBorder: InputBorder.none,
                        disabledBorder: InputBorder.none,
                        errorBorder: InputBorder.none,
                        focusedErrorBorder: InputBorder.none,
                        contentPadding: EdgeInsets.zero,
                        isDense: true,
                      ),
                    ),
                    child: Material(
                      type: MaterialType.transparency,
                      child: TextField(
                        controller: _heroSearchController,
                        focusNode: _heroSearchFocusNode,
                        cursorColor: Colors.white,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 15,
                        ),
                        textInputAction: TextInputAction.search,
                        decoration: InputDecoration(
                          filled: true,
                          fillColor: Colors.transparent,
                          hintText: 'Search municipalities & destinations…',
                          hintStyle: TextStyle(
                            color: Colors.white.withOpacity(0.45),
                            fontSize: 14,
                          ),
                          border: InputBorder.none,
                          enabledBorder: InputBorder.none,
                          focusedBorder: InputBorder.none,
                          disabledBorder: InputBorder.none,
                          isDense: true,
                          contentPadding: const EdgeInsets.symmetric(
                            vertical: 12,
                          ),
                        ),
                        onSubmitted: _submitHeroSearch,
                      ),
                    ),
                  ),
                ),
                if (query.isNotEmpty) ...[
                  const SizedBox(width: 4),
                  IconButton(
                    onPressed: _clearHeroSearch,
                    icon: Icon(
                      Icons.close_rounded,
                      size: 20,
                      color: Colors.white.withOpacity(0.75),
                    ),
                    tooltip: 'Clear search',
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(
                      minWidth: 32,
                      minHeight: 32,
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (showSuggestions)
            Positioned(
              top: searchBarHeight + 8,
              left: 0,
              right: 0,
              child: Material(
                color: Colors.transparent,
                elevation: 12,
                shadowColor: Colors.black.withValues(alpha: 0.25),
                borderRadius: BorderRadius.circular(16),
                child: _buildHeroSearchSuggestions(suggestions, query: query),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildHeroSearchSuggestions(
    List<Map<String, String>> suggestions, {
    required String query,
  }) {
    if (suggestions.isEmpty) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.96),
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.12),
              blurRadius: 16,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Text(
          'No matches for "$query". Try a city, municipality, or place like AMORAP.',
          style: TextStyle(color: Colors.grey.shade700, fontSize: 13),
        ),
      );
    }

    return Container(
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.96),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.12),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: _isMobile ? 200 : 240),
        child: ListView.separated(
          shrinkWrap: true,
          padding: EdgeInsets.zero,
          itemCount: suggestions.length,
          separatorBuilder: (_, __) =>
              Divider(height: 1, color: Colors.grey.shade200),
          itemBuilder: (context, index) {
            final item = suggestions[index];
            return InkWell(
              onTap: () => _selectDestinationFromSearch(item),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.location_city_rounded,
                      size: 20,
                      color: _primaryOrange.withValues(alpha: 0.9),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            item['name'] ?? '',
                            style: const TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 14,
                              color: Color(0xFF0F172A),
                            ),
                          ),
                          if ((item['category'] ?? '').isNotEmpty)
                            Text(
                              item['category']!,
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.grey.shade600,
                              ),
                            ),
                        ],
                      ),
                    ),
                    Icon(
                      Icons.north_west_rounded,
                      size: 18,
                      color: Colors.grey.shade500,
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildRegisterCalloutSection() {
    final accent = _primaryOrange;
    final content = _isMobile
        ? Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _registerCalloutCopy(accent, titleSize: 22),
              const SizedBox(height: 18),
              _registerCalloutButton(),
            ],
          )
        : Row(
            children: [
              Expanded(child: _registerCalloutCopy(accent, titleSize: 26)),
              const SizedBox(width: 28),
              _registerCalloutButton(compact: false),
            ],
          );

    return Container(
      width: double.infinity,
      padding: EdgeInsets.symmetric(
        horizontal: _isMobile ? 16 : 56,
        vertical: _isMobile ? 24 : 32,
      ),
      color: _pageSurfaceMuted,
      child: Container(
        padding: EdgeInsets.all(_isMobile ? 20 : 28),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Colors.white, accent.withValues(alpha: 0.06)],
          ),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: accent.withValues(alpha: 0.22)),
          boxShadow: [
            BoxShadow(
              color: accent.withValues(alpha: 0.1),
              blurRadius: 24,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: content,
      ),
    );
  }

  Widget _registerCalloutCopy(Color accent, {required double titleSize}) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                accent.withValues(alpha: 0.18),
                accent.withValues(alpha: 0.08),
              ],
            ),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: accent.withValues(alpha: 0.25)),
          ),
          child: Icon(Icons.celebration_rounded, color: accent, size: 30),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Ready to explore Misamis Occidental?',
                style: AtmosBrandTypography.displayTitle(
                  color: _darkBg,
                  fontSize: titleSize,
                  letterSpacing: 0.3,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Create your ATMOS TRS account in minutes — digital tourist ID, '
                'QR check-ins, VR previews, and itinerary tools in one place.',
                style: TextStyle(
                  color: Colors.grey.shade700,
                  fontSize: _isMobile ? 14 : 15,
                  height: 1.5,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _registerCalloutButton({bool compact = true}) {
    return FilledButton.icon(
      onPressed: () {
        _muteHeroVideoForAuthNavigation();
        Navigator.of(context).pushNamed('/signup');
      },
      style: FilledButton.styleFrom(
        backgroundColor: _primaryOrange,
        foregroundColor: Colors.white,
        elevation: 2,
        shadowColor: _primaryOrange.withValues(alpha: 0.4),
        padding: EdgeInsets.symmetric(
          horizontal: compact ? 22 : 28,
          vertical: compact ? 14 : 18,
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
      icon: const Icon(Icons.person_add_alt_1_rounded, size: 22),
      label: Text(
        compact ? 'Register now — free' : 'Register now',
        style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
      ),
    );
  }

  Widget _buildChooseYourExperienceSection() {
    final List<Map<String, dynamic>> experienceCards = [
      {
        'title': 'VR Tour',
        'subtitle': 'Explore destinations in immersive 360° preview',
        'icon': Icons.vrpano_rounded,
        'bgStart': const Color(0xFFFFF7ED),
        'bgEnd': const Color(0xFFFFEDD5),
        'accent': _primaryOrange,
      },
      {
        'title': 'Itinerary Planner',
        'subtitle': 'Plan and organize your travel itinerary',
        'icon': Icons.map_rounded,
        'bgStart': const Color(0xFFFEF3C7),
        'bgEnd': const Color(0xFFFDE68A),
        'accent': _brandDark,
      },
      {
        'title': 'QR Check-in',
        'subtitle': 'Scan QR codes and record visits',
        'icon': Icons.qr_code_scanner_rounded,
        'bgStart': const Color(0xFFFFFBEB),
        'bgEnd': const Color(0xFFFEF3C7),
        'accent': const Color(0xFFD97706),
      },
    ];

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: _isMobile ? 16 : 64,
        vertical: _isMobile ? 36 : 72,
      ),
      color: _pageBackground,
      child: Column(
        children: [
          _buildSectionHeader(
            'Choose Your Experience',
            'One platform — explore, plan, and check in across Misamis Occidental',
            icon: Icons.explore_rounded,
            badge: 'VR · Itinerary · Check-in',
          ),
          SizedBox(height: _isMobile ? 24 : 40),
          _isMobile
              ? Column(
                  children: [
                    for (var i = 0; i < experienceCards.length; i++)
                      Padding(
                        padding: EdgeInsets.only(top: i == 0 ? 0 : 10),
                        child: _buildExperienceCard(
                          title: experienceCards[i]['title'] as String,
                          subtitle: experienceCards[i]['subtitle'] as String,
                          icon: experienceCards[i]['icon'] as IconData,
                          bgStart: experienceCards[i]['bgStart'] as Color,
                          bgEnd: experienceCards[i]['bgEnd'] as Color,
                          accent: experienceCards[i]['accent'] as Color,
                          compact: true,
                        ),
                      ),
                  ],
                )
              : LayoutBuilder(
                  builder: (context, constraints) {
                    final crossCount = _isTablet ? 2 : 3;
                    return GridView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: crossCount,
                        crossAxisSpacing: 20,
                        mainAxisSpacing: 20,
                        childAspectRatio: _isTablet ? 1.35 : 1.15,
                      ),
                      itemCount: experienceCards.length,
                      itemBuilder: (context, index) {
                        final card = experienceCards[index];
                        return _buildExperienceCard(
                          title: card['title'] as String,
                          subtitle: card['subtitle'] as String,
                          icon: card['icon'] as IconData,
                          bgStart: card['bgStart'] as Color,
                          bgEnd: card['bgEnd'] as Color,
                          accent: card['accent'] as Color,
                        );
                      },
                    );
                  },
                ),
        ],
      ),
    );
  }

  Widget _buildExperienceCard({
    required String title,
    required String subtitle,
    required IconData icon,
    required Color bgStart,
    required Color bgEnd,
    required Color accent,
    bool compact = false,
  }) {
    final radius = compact ? 16.0 : 22.0;

    final decoration = BoxDecoration(
      gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [bgStart, Color.lerp(bgEnd, accent, 0.05)!],
      ),
      borderRadius: BorderRadius.circular(radius),
      border: Border.all(color: accent.withValues(alpha: 0.22)),
      boxShadow: [
        BoxShadow(
          color: accent.withValues(alpha: 0.08),
          blurRadius: compact ? 10 : 18,
          offset: Offset(0, compact ? 4 : 8),
        ),
      ],
    );

    if (compact) {
      return Container(
        decoration: decoration,
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                width: 4,
                decoration: BoxDecoration(
                  color: accent,
                  borderRadius: BorderRadius.horizontal(
                    left: Radius.circular(radius),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(10),
                child: Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.8),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: accent.withValues(alpha: 0.25)),
                  ),
                  child: Icon(icon, color: accent, size: 22),
                ),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(0, 12, 14, 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: _darkBg,
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        subtitle,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: Colors.grey.shade700,
                          fontSize: 12,
                          height: 1.35,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Container(
      decoration: decoration,
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              width: 5,
              decoration: BoxDecoration(
                color: accent,
                borderRadius: BorderRadius.horizontal(
                  left: Radius.circular(radius),
                ),
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 18, 14, 18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(11),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.75),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: accent.withValues(alpha: 0.3),
                        ),
                      ),
                      child: Icon(icon, color: accent, size: 24),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: _darkBg,
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.2,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      subtitle,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Colors.grey.shade700,
                        fontSize: 13,
                        height: 1.4,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFeaturesSection() {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: _isMobile ? 16 : 64,
        vertical: _isMobile ? 48 : 72,
      ),
      color: _pageSurfaceMuted,
      child: Column(
        children: [
          _buildSectionHeader(
            'Why Choose ATMOS TRS?',
            'Smart registration, VR tours, itinerary planning & QR check-ins — all in one platform',
            icon: Icons.auto_awesome_rounded,
            badge: 'Official provincial platform',
          ),
          SizedBox(height: _isMobile ? 28 : 60),
          _isMobile
              ? Column(
                  children: [
                    for (var i = 0; i < _features.length; i++)
                      Padding(
                        padding: EdgeInsets.only(top: i == 0 ? 0 : 10),
                        child: _buildFeatureCard(
                          i,
                          _features[i],
                          compact: true,
                        ),
                      ),
                  ],
                )
              : GridView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: _isTablet ? 2 : 4,
                    crossAxisSpacing: 24,
                    mainAxisSpacing: 18,
                    childAspectRatio: _isTablet ? 1.28 : 1.35,
                  ),
                  itemCount: _features.length,
                  itemBuilder: (context, index) =>
                      _buildFeatureCard(index, _features[index]),
                ),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(
    String title,
    String subtitle, {
    IconData? icon,
    String? badge,
  }) {
    final accent = _primaryOrange;
    return Column(
      children: [
        if (badge != null || icon != null)
          Container(
            margin: const EdgeInsets.only(bottom: 14),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
            decoration: BoxDecoration(
              color: accent.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: accent.withValues(alpha: 0.28)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (icon != null) ...[
                  Icon(icon, size: 16, color: accent),
                  const SizedBox(width: 6),
                ],
                Text(
                  badge ?? 'Misamis Occidental',
                  style: TextStyle(
                    color: accent,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.4,
                  ),
                ),
              ],
            ),
          ),
        Text(
          title,
          textAlign: TextAlign.center,
          style: AtmosBrandTypography.displayTitle(
            color: _darkBg,
            fontSize: _isMobile ? 30 : 40,
            letterSpacing: 0.4,
          ),
        ),
        const SizedBox(height: 12),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: Text(
            subtitle,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.grey.shade600,
              fontSize: _isMobile ? 15 : 17,
              height: 1.5,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildFeatureCard(
    int index,
    Map<String, dynamic> feature, {
    bool compact = false,
  }) {
    final bgStart = feature['bgStart'] as Color;
    final bgEnd = feature['bgEnd'] as Color;
    final accent = feature['accent'] as Color;
    final isHovered = _hoveredFeatureIndex == index;
    final String? route = feature['route'] as String?;

    if (compact) {
      final radius = 16.0;
      Widget card = Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [bgStart, Color.lerp(bgEnd, accent, 0.04)!],
          ),
          borderRadius: BorderRadius.circular(radius),
          border: Border.all(color: accent.withValues(alpha: 0.2)),
          boxShadow: [
            BoxShadow(
              color: accent.withValues(alpha: 0.08),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                width: 4,
                decoration: BoxDecoration(
                  color: accent,
                  borderRadius: BorderRadius.horizontal(
                    left: Radius.circular(radius),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(10),
                child: Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.8),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: accent.withValues(alpha: 0.25)),
                  ),
                  child: Icon(
                    feature['icon'] as IconData,
                    color: accent,
                    size: 22,
                  ),
                ),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(0, 12, 14, 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        feature['title'] as String,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: _darkBg,
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          letterSpacing: -0.2,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        feature['description'] as String,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: Colors.grey.shade600,
                          fontSize: 12,
                          height: 1.35,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      );
      if (route == 'itinerary') {
        return GestureDetector(
          onTap: _openPlanItinerary,
          child: card,
        );
      }
      return card;
    }

    Widget card = MouseRegion(
      onEnter: (_) => setState(() => _hoveredFeatureIndex = index),
      onExit: (_) => setState(() => _hoveredFeatureIndex = null),
      cursor: SystemMouseCursors.click,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: Align(
          alignment: Alignment.topCenter,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 250),
            curve: Curves.easeOutCubic,
            transform: Matrix4.identity()
              ..translate(0.0, isHovered ? -8.0 : 0.0)
              ..scale(isHovered ? 1.02 : 1.0),
            transformAlignment: Alignment.center,
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  bgStart,
                  Color.lerp(bgEnd, accent, isHovered ? 0.06 : 0.02)!,
                ],
              ),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: isHovered
                    ? accent.withOpacity(0.35)
                    : accent.withOpacity(0.18),
                width: 1,
              ),
              boxShadow: [
                BoxShadow(
                  color: accent.withOpacity(isHovered ? 0.14 : 0.08),
                  blurRadius: isHovered ? 18 : 12,
                  offset: Offset(0, isHovered ? 8 : 4),
                ),
                BoxShadow(
                  color: Colors.black.withOpacity(0.04),
                  blurRadius: 6,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              mainAxisAlignment: MainAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                AnimatedContainer(
                  duration: const Duration(milliseconds: 250),
                  curve: Curves.easeOutCubic,
                  padding: const EdgeInsets.all(13),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(isHovered ? 0.75 : 0.55),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: accent.withOpacity(isHovered ? 0.35 : 0.22),
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: accent.withOpacity(0.06),
                        blurRadius: 6,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Icon(
                    feature['icon'] as IconData,
                    color: accent,
                    size: isHovered ? 26 : 24,
                  ),
                ),
                const SizedBox(height: 18),
                Text(
                  feature['title'] as String,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: _darkBg,
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.3,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 10),
                Text(
                  feature['description'] as String,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.grey.shade600,
                    fontSize: 13,
                    height: 1.45,
                  ),
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ),
      ),
    );

    if (route == 'itinerary') {
      return GestureDetector(
        onTap: _openPlanItinerary,
        child: card,
      );
    }
    return card;
  }

  Widget _buildDestinationsSection() {
    final query = _heroSearchController.text.trim();
    final filtered = _filteredDestinations;
    final isFiltering = query.isNotEmpty;
    final matchLabel = filtered.length == 1 ? 'match' : 'matches';

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: _isMobile ? 16 : 64,
        vertical: _isMobile ? 48 : 72,
      ),
      color: _pageBackground,
      child: Column(
        children: [
          _buildSectionHeader(
            isFiltering ? 'Search results' : 'Municipalities & Cities',
            isFiltering
                ? '${filtered.length} $matchLabel for "$query" — tap a card for VR tours, itinerary planning & tourist spots'
                : 'All 17 tourist destinations in Misamis Occidental — tap any card to explore in 360° or plan your trip',
            icon: Icons.location_city_rounded,
            badge: isFiltering ? '${filtered.length} found' : '17 LGUs',
          ),
          if (isFiltering) ...[
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: _clearHeroSearch,
                icon: const Icon(Icons.clear_all_rounded, size: 18),
                label: const Text('Clear search'),
                style: TextButton.styleFrom(foregroundColor: _primaryOrange),
              ),
            ),
          ],
          SizedBox(height: _isMobile ? 28 : 60),
          if (filtered.isEmpty)
            _buildDestinationsEmptyState(query)
          else if (_isMobile)
            Column(
              children: [
                for (var i = 0; i < filtered.length; i++)
                  Padding(
                    padding: EdgeInsets.only(top: i == 0 ? 0 : 10),
                    child: _buildDestinationCard(filtered[i], compact: true),
                  ),
              ],
            )
          else
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: _isTablet ? 2 : 4,
                crossAxisSpacing: 24,
                mainAxisSpacing: 24,
                childAspectRatio: 1.05,
              ),
              itemCount: filtered.length,
              itemBuilder: (context, index) =>
                  _buildDestinationCard(filtered[index]),
            ),
        ],
      ),
    );
  }

  Widget _buildDestinationsEmptyState(String query) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
      decoration: BoxDecoration(
        color: _pageSurfaceMuted,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: _pageDivider),
      ),
      child: Column(
        children: [
          Icon(Icons.search_off_rounded, size: 48, color: Colors.grey.shade400),
          const SizedBox(height: 16),
          Text(
            'No destinations match "$query"',
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: Color(0xFF0F172A),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Try a municipality name (e.g. Sinacaban, Ozamiz), a landmark (AMORAP, Global Garden), or a category like beach or falls.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 14,
              color: Colors.grey.shade600,
              height: 1.45,
            ),
          ),
          const SizedBox(height: 20),
          OutlinedButton.icon(
            onPressed: _clearHeroSearch,
            icon: const Icon(Icons.refresh_rounded, size: 18),
            label: const Text('Show all 17 locations'),
            style: OutlinedButton.styleFrom(
              foregroundColor: _primaryOrange,
              side: BorderSide(color: _primaryOrange.withValues(alpha: 0.5)),
            ),
          ),
        ],
      ),
    );
  }

  void _openDestinationTouristSpots(Map<String, String> destination) {
    final name = destination['name']?.trim();
    if (name == null || name.isEmpty) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) =>
            MunicipalityMapAndSpotsScreen(municipalityIdOrName: name),
      ),
    );
  }

  void _showDestinationExploreSheet(Map<String, String> destination) {
    final name = destination['name'] ?? 'Destination';
    final description = destination['description'] ?? '';
    final category = destination['category'] ?? 'Municipality';
    final imageUrl = destination['image'] ?? '';
    final isAsset = destination['isAsset'] == 'true';
    final screen = MediaQuery.sizeOf(context);

    showDialog<void>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.55),
      builder: (dialogContext) {
        return Center(
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: _isMobile ? 16 : 24),
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: _isMobile ? 360 : 420,
                maxHeight: screen.height * 0.88,
              ),
              child: Material(
                color: _pageBackground,
                elevation: 16,
                shadowColor: Colors.black.withValues(alpha: 0.25),
                borderRadius: BorderRadius.circular(22),
                clipBehavior: Clip.antiAlias,
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    SingleChildScrollView(
                  padding: EdgeInsets.fromLTRB(
                    _isMobile ? 18 : 22,
                    16,
                    _isMobile ? 18 : 22,
                    20,
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      const SizedBox(height: 8),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(14),
                        child: SizedBox(
                          height: _isMobile ? 130 : 160,
                          width: double.infinity,
                          child: _isMobile
                              ? GestureDetector(
                                  onTap: () => _showDestinationImageFullscreen(
                                    dialogContext,
                                    imageUrl: imageUrl,
                                    isAsset: isAsset,
                                    title: name,
                                  ),
                                  child: Stack(
                                    fit: StackFit.expand,
                                    children: [
                                      _buildDestinationSheetImage(
                                        imageUrl: imageUrl,
                                        isAsset: isAsset,
                                      ),
                                      Positioned(
                                        right: 10,
                                        bottom: 10,
                                        child: Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 8,
                                            vertical: 5,
                                          ),
                                          decoration: BoxDecoration(
                                            color: Colors.black
                                                .withValues(alpha: 0.55),
                                            borderRadius:
                                                BorderRadius.circular(8),
                                          ),
                                          child: const Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              Icon(
                                                Icons.fullscreen_rounded,
                                                color: Colors.white,
                                                size: 16,
                                              ),
                                              SizedBox(width: 4),
                                              Text(
                                                'View full',
                                                style: TextStyle(
                                                  color: Colors.white,
                                                  fontSize: 11,
                                                  fontWeight: FontWeight.w600,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                )
                              : _buildDestinationSheetImage(
                                  imageUrl: imageUrl,
                                  isAsset: isAsset,
                                ),
                        ),
                      ),
                      const SizedBox(height: 14),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        alignment: WrapAlignment.center,
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 5,
                            ),
                            decoration: BoxDecoration(
                              color: _primaryOrange.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.landscape_rounded,
                                  size: 14,
                                  color: _brandDark,
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  'Tourist destination',
                                  style: TextStyle(
                                    color: _brandDark,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 5,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.grey.shade100,
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Text(
                              category,
                              style: TextStyle(
                                color: Colors.grey.shade700,
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Text(
                        name,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: _darkBg,
                          fontSize: _isMobile ? 22 : 26,
                          fontWeight: FontWeight.w800,
                          height: 1.15,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        description,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Colors.grey.shade700,
                          fontSize: 14,
                          height: 1.45,
                        ),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'Choose how to explore $name:',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Colors.grey.shade800,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 14),
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton.icon(
                          onPressed: () {
                            Navigator.pop(dialogContext);
                            _navigateToLogin();
                          },
                          icon: const Icon(Icons.vrpano_rounded, size: 20),
                          label: const Text('Start VR Tour'),
                          style: FilledButton.styleFrom(
                            backgroundColor: _primaryOrange,
                            foregroundColor: Colors.white,
                            minimumSize: const Size(double.infinity, 46),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 10),
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          onPressed: () {
                            Navigator.pop(dialogContext);
                            _openPlanItinerary();
                          },
                          icon: const Icon(Icons.map_rounded, size: 20),
                          label: const Text('Plan itinerary'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: const Color(0xFF0369A1),
                            backgroundColor: const Color(0xFF0EA5E9)
                                .withValues(alpha: 0.08),
                            side: const BorderSide(color: Color(0xFF0EA5E9)),
                            minimumSize: const Size(double.infinity, 46),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 10),
                      SizedBox(
                        width: double.infinity,
                        child: TextButton.icon(
                          onPressed: () {
                            Navigator.pop(dialogContext);
                            _openDestinationTouristSpots(destination);
                          },
                          icon: Icon(
                            Icons.place_rounded,
                            size: 18,
                            color: _primaryOrange,
                          ),
                          label: Text(
                            'View tourist spots',
                            style: TextStyle(
                              color: _brandDark,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                    Positioned(
                      top: 4,
                      right: 4,
                      child: IconButton(
                        onPressed: () => Navigator.pop(dialogContext),
                        icon: const Icon(Icons.close_rounded),
                        color: Colors.grey.shade600,
                        visualDensity: VisualDensity.compact,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  void _showDestinationImageFullscreen(
    BuildContext context, {
    required String imageUrl,
    required bool isAsset,
    required String title,
  }) {
    if (!_isMobile) return;
    Navigator.of(context, rootNavigator: true).push<void>(
      MaterialPageRoute<void>(
        fullscreenDialog: true,
        builder: (ctx) => _DestinationImageFullscreenPage(
          imageUrl: imageUrl,
          isAsset: isAsset,
          title: title,
        ),
      ),
    );
  }

  Widget _buildDestinationSheetImage({
    required String imageUrl,
    required bool isAsset,
    BoxFit fit = BoxFit.cover,
  }) {
    const fallback =
        'https://images.unsplash.com/photo-1480714378408-67cf0d13bc1b?w=800';
    if (isAsset) {
      return Image.asset(
        imageUrl,
        fit: fit,
        errorBuilder: (_, __, ___) => Image.network(
          fallback,
          fit: fit,
          errorBuilder: (_, __, ___) => _buildPlaceholderImage(),
        ),
      );
    }
    return Image.network(
      imageUrl,
      fit: fit,
      errorBuilder: (_, __, ___) => _buildPlaceholderImage(),
    );
  }

  Widget _destinationCategoryBadge(String category, {bool onImage = false}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: onImage
            ? _primaryOrange
            : _primaryOrange.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        category,
        style: TextStyle(
          color: onImage ? Colors.white : _brandDark,
          fontSize: onImage ? 12 : 10,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  Widget _buildDestinationCard(
    Map<String, String> destination, {
    bool compact = false,
  }) {
    final isAsset = destination['isAsset'] == 'true';
    final imageUrl = destination['image']!;
    final name = destination['name'] ?? '';
    final category = destination['category'] ?? 'Municipality';
    final description = destination['description'] ?? '';
    final isHovered = _hoveredDestinationName == name;

    const fallbackNetworkImage =
        'https://images.unsplash.com/photo-1480714378408-67cf0d13bc1b?w=800';

    Widget spotImage({required double width, required double height}) {
      if (isAsset) {
        return Image.asset(
          imageUrl,
          width: width,
          height: height,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => Image.network(
            fallbackNetworkImage,
            width: width,
            height: height,
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => SizedBox(
              width: width,
              height: height,
              child: _buildPlaceholderImage(),
            ),
          ),
        );
      }
      return Image.network(
        imageUrl,
        width: width,
        height: height,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => SizedBox(
          width: width,
          height: height,
          child: _buildPlaceholderImage(),
        ),
      );
    }

    if (compact) {
      return MouseRegion(
        onEnter: (_) => setState(() => _hoveredDestinationName = name),
        onExit: (_) => setState(() => _hoveredDestinationName = null),
        cursor: SystemMouseCursors.click,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: () => _showDestinationExploreSheet(destination),
            borderRadius: BorderRadius.circular(16),
            child: Ink(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                color: Colors.white,
                border: Border.all(
                  color: isHovered
                      ? _primaryOrange.withValues(alpha: 0.45)
                      : _pageDivider,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(
                      alpha: isHovered ? 0.1 : 0.06,
                    ),
                    blurRadius: isHovered ? 16 : 12,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  ClipRRect(
                    borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(15),
                    ),
                    child: SizedBox(
                      height: 120,
                      width: double.infinity,
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          spotImage(width: double.infinity, height: 120),
                          Positioned(
                            top: 10,
                            left: 10,
                            child: _destinationCategoryBadge(
                              category,
                              onImage: true,
                            ),
                          ),
                          Positioned(
                            top: 10,
                            right: 10,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.black.withValues(alpha: 0.55),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: const Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    Icons.touch_app_rounded,
                                    color: Colors.white,
                                    size: 14,
                                  ),
                                  SizedBox(width: 4),
                                  Text(
                                    'Tap to explore',
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 11,
                                      fontWeight: FontWeight.w600,
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
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(
                              Icons.landscape_rounded,
                              size: 14,
                              color: _primaryOrange,
                            ),
                            const SizedBox(width: 6),
                            Text(
                              'Tourist destination',
                              style: TextStyle(
                                color: _brandDark,
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Text(
                          name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: _darkBg,
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          description,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: Colors.grey.shade600,
                            fontSize: 12,
                            height: 1.3,
                          ),
                        ),
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            Expanded(
                              child: _buildDestinationQuickAction(
                                label: 'VR Tour',
                                icon: Icons.vrpano_rounded,
                                color: _primaryOrange,
                                onTap: _navigateToLogin,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: _buildDestinationQuickAction(
                                label: 'Itinerary',
                                icon: Icons.map_rounded,
                                color: const Color(0xFF0369A1),
                                onTap: _openPlanItinerary,
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
        ),
      );
    }

    final gridCard = Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withValues(alpha: isHovered ? 0.35 : 0.2),
            blurRadius: isHovered ? 24 : 20,
            offset: Offset(0, isHovered ? 14 : 10),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: Stack(
          fit: StackFit.expand,
          children: [
            isAsset
                ? Image.asset(
                    imageUrl,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => Image.network(
                      fallbackNetworkImage,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => _buildPlaceholderImage(),
                    ),
                  )
                : Image.network(
                    imageUrl,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => _buildPlaceholderImage(),
                  ),
            Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.black.withValues(alpha: isHovered ? 0.15 : 0.05),
                    Colors.black.withValues(alpha: isHovered ? 0.88 : 0.78),
                  ],
                ),
              ),
            ),
            if (isHovered)
              Positioned.fill(
                child: Container(
                  alignment: Alignment.center,
                  padding: const EdgeInsets.all(12),
                  child: Text(
                    'Tap for VR & itinerary',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.95),
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
            Positioned(
              top: 10,
              left: 10,
              right: 10,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  _destinationCategoryBadge(category, onImage: true),
                  const SizedBox(height: 4),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 7,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.5),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      'Tourist spot',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.95),
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Positioned(
              bottom: 12,
              left: 12,
              right: 12,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    name,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    'Tap for VR & itinerary',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.82),
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );

    return MouseRegion(
      onEnter: (_) => setState(() => _hoveredDestinationName = name),
      onExit: (_) => setState(() => _hoveredDestinationName = null),
      cursor: SystemMouseCursors.click,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => _showDestinationExploreSheet(destination),
          borderRadius: BorderRadius.circular(20),
          child: gridCard,
        ),
      ),
    );
  }

  Widget _buildDestinationQuickAction({
    required String label,
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
  }) {
    return Material(
      color: color.withValues(alpha: 0.1),
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 16, color: color),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  color: color,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPlaceholderImage() {
    return Container(
      color: Colors.grey.shade200,
      child: Icon(
        Icons.landscape_rounded,
        color: Colors.grey.shade400,
        size: 48,
      ),
    );
  }

  Widget _buildHowItWorksSection() {
    final stepEntries = _steps.asMap().entries.toList();
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: _isMobile ? 16 : 80,
        vertical: _isMobile ? 40 : 72,
      ),
      color: _pageBackground,
      child: Column(
        children: [
          _buildSectionHeader(
            'How It Works',
            'Get started with ATMOS TRS in 5 simple steps',
            icon: Icons.route_rounded,
            badge: '5 easy steps',
          ),
          SizedBox(height: _isMobile ? 24 : 42),
          _isMobile
              ? Column(
                  children: [
                    for (var i = 0; i < stepEntries.length; i++) ...[
                      if (i > 0) _buildMobileStepConnector(),
                      _buildStepCard(stepEntries[i].value, compact: true),
                    ],
                  ],
                )
              : SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: stepEntries.expand((entry) {
                      final isLast = entry.key == stepEntries.length - 1;
                      return [
                        SizedBox(
                          width: 182,
                          child: _buildStepCard(entry.value),
                        ),
                        if (!isLast) _buildStepConnector(),
                      ];
                    }).toList(),
                  ),
                ),
        ],
      ),
    );
  }

  Widget _buildMobileStepConnector() {
    return Padding(
      padding: const EdgeInsets.only(left: 22, top: 6, bottom: 6),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Container(
          width: 2,
          height: 14,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(1),
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                _primaryOrange.withValues(alpha: 0.45),
                _primaryOrange.withValues(alpha: 0.12),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildStepConnector() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6),
      child: Row(
        children: [
          Container(
            width: 54,
            height: 1.5,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  _primaryOrange.withOpacity(0.26),
                  _primaryOrange.withOpacity(0.08),
                ],
              ),
            ),
          ),
          const SizedBox(width: 2),
          Icon(
            Icons.chevron_right_rounded,
            color: _primaryOrange.withOpacity(0.5),
            size: 14,
          ),
        ],
      ),
    );
  }

  Widget _buildStepCard(Map<String, dynamic> step, {bool compact = false}) {
    final number = step['number'] as String;
    final title = step['title'] as String;
    final description = step['description'] as String;
    final icon = step['icon'] as IconData;

    final cardDecoration = BoxDecoration(
      gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          Colors.white,
          Color.lerp(_pageSurfaceMuted, _primaryOrange, 0.04)!,
        ],
      ),
      borderRadius: BorderRadius.circular(compact ? 14 : 16),
      border: Border.all(
        color: _primaryOrange.withValues(alpha: compact ? 0.18 : 0.14),
      ),
      boxShadow: [
        BoxShadow(
          color: _primaryOrange.withValues(alpha: 0.07),
          blurRadius: compact ? 10 : 14,
          offset: Offset(0, compact ? 4 : 6),
        ),
        BoxShadow(
          color: Colors.black.withValues(alpha: 0.03),
          blurRadius: 6,
          offset: const Offset(0, 2),
        ),
      ],
    );

    final iconBox = Container(
      width: compact ? 44 : 34,
      height: compact ? 44 : 34,
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFFFA24A), Color(0xFFF97316)],
        ),
        borderRadius: BorderRadius.circular(compact ? 12 : 10),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.45),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: _primaryOrange.withValues(alpha: 0.22),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Icon(icon, color: Colors.white, size: compact ? 22 : 16),
    );

    if (compact) {
      return Container(
        decoration: cardDecoration,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 4,
              decoration: BoxDecoration(
                color: _primaryOrange,
                borderRadius: const BorderRadius.horizontal(
                  left: Radius.circular(14),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 12, 0, 12),
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  iconBox,
                  Positioned(
                    top: -5,
                    right: -5,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 5,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: _darkBg,
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.9),
                          width: 1,
                        ),
                      ),
                      child: Text(
                        number,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 9,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.2,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 12, 14, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: _darkBg,
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.2,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      description,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Colors.grey.shade600,
                        fontSize: 12,
                        height: 1.35,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      decoration: cardDecoration,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            number,
            style: TextStyle(
              color: _primaryOrange,
              fontSize: 10,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.3,
            ),
          ),
          const SizedBox(height: 7),
          iconBox,
          const SizedBox(height: 10),
          Text(
            title,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: _darkBg,
              fontSize: 14,
              fontWeight: FontWeight.w700,
              letterSpacing: -0.1,
              height: 1.2,
            ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 7),
          Text(
            description,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.grey.shade600,
              fontSize: 11,
              height: 1.32,
            ),
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  Widget _buildStatCard(Map<String, dynamic> stat) {
    final bgStart = stat['bgStart'] as Color;
    final bgEnd = stat['bgEnd'] as Color;
    final accent = stat['accent'] as Color;
    const radius = 14.0;

    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [bgStart, Color.lerp(bgEnd, accent, 0.05)!],
        ),
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: accent.withValues(alpha: 0.22)),
        boxShadow: [
          BoxShadow(
            color: accent.withValues(alpha: 0.08),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 4,
            decoration: BoxDecoration(
              color: accent,
              borderRadius: const BorderRadius.horizontal(
                left: Radius.circular(radius),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(10),
            child: Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.85),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: accent.withValues(alpha: 0.28)),
              ),
              child: Icon(stat['icon'] as IconData, color: accent, size: 22),
            ),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(0, 12, 14, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Text(
                      stat['value'] as String,
                      maxLines: 1,
                      style: TextStyle(
                        color: _darkBg,
                        fontSize: _isMobile ? 22 : 26,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.5,
                        height: 1.0,
                      ),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    stat['label'] as String,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: Colors.grey.shade700,
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      height: 1.3,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatisticsSection() {
    final stats = [
      {
        'value': '10,000+',
        'label': 'Registered Tourists',
        'icon': Icons.people_rounded,
        'bgStart': const Color(0xFFFFF7ED),
        'bgEnd': const Color(0xFFFFEDD5),
        'accent': _primaryOrange,
      },
      {
        'value': '15-25',
        'label': 'Tourist Spots',
        'icon': Icons.place_rounded,
        'bgStart': const Color(0xFFFFFBEB),
        'bgEnd': const Color(0xFFFEF3C7),
        'accent': const Color(0xFFD97706),
      },
      {
        'value': '17',
        'label': 'Cities & Municipalities',
        'icon': Icons.location_city_rounded,
        'bgStart': const Color(0xFFFFF7ED),
        'bgEnd': const Color(0xFFFFEDD5),
        'accent': _brandDark,
      },
      {
        'value': '7',
        'label': 'VR Tours',
        'icon': Icons.vrpano_rounded,
        'bgStart': const Color(0xFFFEF3C7),
        'bgEnd': const Color(0xFFFDE68A),
        'accent': _brandDark,
      },
    ];

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: _isMobile ? 16 : 64,
        vertical: _isMobile ? 48 : 72,
      ),
      color: _pageSurfaceMuted,
      child: Column(
        children: [
          _buildSectionHeader(
            'By the numbers',
            'Growing smart tourism across Misamis Occidental',
            icon: Icons.insights_rounded,
            badge: 'Impact',
          ),
          SizedBox(height: _isMobile ? 24 : 36),
          _isMobile
              ? Column(
                  children: [
                    for (var i = 0; i < stats.length; i++)
                      Padding(
                        padding: EdgeInsets.only(top: i == 0 ? 0 : 10),
                        child: _buildStatCard(stats[i]),
                      ),
                  ],
                )
              : _isTablet
              ? Column(
                  children: [
                    for (var row = 0; row < stats.length; row += 2)
                      Padding(
                        padding: EdgeInsets.only(top: row == 0 ? 0 : 12),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(child: _buildStatCard(stats[row])),
                            const SizedBox(width: 16),
                            Expanded(child: _buildStatCard(stats[row + 1])),
                          ],
                        ),
                      ),
                  ],
                )
              : Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (var i = 0; i < stats.length; i++) ...[
                      if (i > 0) const SizedBox(width: 16),
                      Expanded(child: _buildStatCard(stats[i])),
                    ],
                  ],
                ),
        ],
      ),
    );
  }

  Widget _buildAboutSection() {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: _isMobile ? 24 : 80,
        vertical: 80,
      ),
      color: _pageBackground,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: _primaryOrange.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(color: _primaryOrange.withOpacity(0.3)),
                  ),
                  child: Text(
                    'About ATMOS TRS',
                    style: TextStyle(
                      color: _primaryOrange,
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.3,
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                Text(
                  'Advancing Tourism in\nMisamis Occidental',
                  style: AtmosBrandTypography.displayTitle(
                    color: _darkBg,
                    fontSize: _isMobile ? 28 : 38,
                    letterSpacing: 0.3,
                    height: 1.15,
                  ),
                ),
                const SizedBox(height: 20),
                Text(
                  'ATMOS TRS — $_kAtmosTrsFullName — is the official digital platform for tourism in Misamis Occidental. '
                  'We provide seamless tourist registration, VR previews of destinations, itinerary planning, and QR check-ins at spots.\n\n'
                  'Our mission is to connect visitors with local communities and create a sustainable, smart tourism ecosystem across the province.',
                  style: TextStyle(
                    color: Colors.grey.shade700,
                    fontSize: 16,
                    height: 1.8,
                    fontWeight: FontWeight.w400,
                  ),
                ),
                const SizedBox(height: 30),
                Wrap(
                  spacing: 24,
                  runSpacing: 12,
                  children: [
                    _buildAboutFeature(
                      Icons.verified_rounded,
                      'Official Partner',
                    ),
                    _buildAboutFeature(
                      Icons.security_rounded,
                      'Secure Platform',
                    ),
                    _buildAboutFeature(
                      Icons.support_agent_rounded,
                      '24/7 Support',
                    ),
                  ],
                ),
              ],
            ),
          ),
          if (!_isMobile) ...[
            const SizedBox(width: 60),
            Expanded(
              child: Container(
                height: 400,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(24),
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      _primaryOrange.withOpacity(0.15),
                      _accentOrange.withOpacity(0.08),
                    ],
                  ),
                  border: Border.all(color: _primaryOrange.withOpacity(0.25)),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(24),
                  child: Stack(
                    children: [
                      Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Container(
                              padding: const EdgeInsets.all(20),
                              decoration: BoxDecoration(
                                color: _primaryOrange.withOpacity(0.15),
                                shape: BoxShape.circle,
                              ),
                              child: Icon(
                                Icons.travel_explore,
                                color: _primaryOrange,
                                size: 60,
                              ),
                            ),
                            const SizedBox(height: 20),
                            Text(
                              'Provincial Tourism Office',
                              style: TextStyle(
                                color: _darkBg,
                                fontSize: 18,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'Misamis Occidental',
                              style: TextStyle(
                                color: Colors.grey.shade600,
                                fontSize: 14,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildAboutFeature(IconData icon, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, color: _primaryOrange, size: 20),
        const SizedBox(width: 8),
        Text(
          label,
          style: TextStyle(color: _darkBg.withOpacity(0.8), fontSize: 14),
        ),
      ],
    );
  }

  Widget _buildFooter() {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: _isMobile ? 24 : 80,
        vertical: 40,
      ),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [_brandLight, _primaryOrange, _brandDark],
        ),
        border: Border(
          top: BorderSide(color: Colors.white.withValues(alpha: 0.24)),
        ),
      ),
      child: Column(
        children: [
          _isMobile
              ? Column(
                  children: [
                    _buildFooterMissionVision(),
                    const SizedBox(height: 32),
                    _buildFooterBrand(),
                    const SizedBox(height: 32),
                    _buildFooterLinks(),
                    const SizedBox(height: 32),
                    _buildFooterContact(),
                  ],
                )
              : Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(flex: 2, child: _buildFooterMissionVision()),
                    const SizedBox(width: 40),
                    Expanded(flex: 2, child: _buildFooterBrand()),
                    const SizedBox(width: 40),
                    Expanded(child: _buildFooterLinks()),
                    const SizedBox(width: 40),
                    Expanded(child: _buildFooterContact()),
                  ],
                ),
          const SizedBox(height: 40),
          Container(
            padding: const EdgeInsets.only(top: 24),
            decoration: BoxDecoration(
              border: Border(
                top: BorderSide(color: Colors.white.withOpacity(0.28)),
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(
                    '2026 © Province of Misamis Occidental',
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.95),
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                    ),
                    overflow: TextOverflow.ellipsis,
                    maxLines: 1,
                  ),
                ),
                const SizedBox(width: 16),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _buildSocialIcon(Icons.facebook_rounded),
                    _buildSocialIcon(Icons.camera_alt_rounded),
                    _buildSocialIcon(Icons.email_rounded),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFooterMissionVision() {
    return Column(
      crossAxisAlignment: _isMobile
          ? CrossAxisAlignment.center
          : CrossAxisAlignment.start,
      children: [
        Text(
          'Mission',
          style: TextStyle(
            color: Colors.white,
            fontSize: 16,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 10),
        Padding(
          padding: EdgeInsets.only(left: _isMobile ? 0 : 8),
          child: Text(
            'To inspire and connect travelers by showcasing the wonders of every destination, '
            'fostering sustainable tourism, and creating meaningful experiences that enrich both '
            'the traveler and the local communities.',
            textAlign: _isMobile ? TextAlign.center : TextAlign.start,
            style: TextStyle(
              color: Colors.white.withOpacity(0.96),
              fontSize: 14,
              height: 1.6,
              fontWeight: FontWeight.w400,
            ),
          ),
        ),
        const SizedBox(height: 28),
        Text(
          'Vision',
          style: TextStyle(
            color: Colors.white,
            fontSize: 16,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 10),
        Padding(
          padding: EdgeInsets.only(left: _isMobile ? 0 : 8),
          child: Text(
            'To become a leading platform for tourism, empowering travelers to explore the world '
            'with ease while promoting cultural appreciation, environmental responsibility, '
            'and economic growth in every destination.',
            textAlign: _isMobile ? TextAlign.center : TextAlign.start,
            style: TextStyle(
              color: Colors.white.withOpacity(0.96),
              fontSize: 14,
              height: 1.6,
              fontWeight: FontWeight.w400,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildFooterBrand() {
    return Column(
      crossAxisAlignment: _isMobile
          ? CrossAxisAlignment.center
          : CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: _primaryOrange,
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(
                Icons.travel_explore,
                color: Colors.white,
                size: 24,
              ),
            ),
            const SizedBox(width: 12),
            Text(
              'ATMOS TRS',
              style: AtmosBrandTypography.displayTitle(
                color: Colors.white,
                fontSize: 22,
                letterSpacing: 0.6,
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Text(
          _kAtmosTrsFullName,
          textAlign: _isMobile ? TextAlign.center : TextAlign.start,
          style: TextStyle(
            color: Colors.white.withOpacity(0.96),
            fontSize: 12,
            fontWeight: FontWeight.w600,
            height: 1.4,
            letterSpacing: 0.15,
          ),
        ),
      ],
    );
  }

  Widget _buildFooterLinks() {
    final links = ['Home', 'Features', 'Destinations', 'About', 'Contact'];
    return Column(
      crossAxisAlignment: _isMobile
          ? CrossAxisAlignment.center
          : CrossAxisAlignment.start,
      children: [
        const Text(
          'Quick Links',
          style: TextStyle(
            color: Colors.white,
            fontSize: 16,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 16),
        ...links.map(
          (link) => Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Text(
              link,
              style: TextStyle(
                color: Colors.white.withOpacity(0.95),
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildFooterContact() {
    return Column(
      crossAxisAlignment: _isMobile
          ? CrossAxisAlignment.center
          : CrossAxisAlignment.start,
      children: [
        const Text(
          'Contact Us',
          style: TextStyle(
            color: Colors.white,
            fontSize: 16,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 16),
        _buildContactItem(
          Icons.location_on_rounded,
          'Oroquieta City, Misamis Occidental',
        ),
        _buildContactItem(Icons.email_rounded, 'governor.atmos@misocc-demo.ph'),
        _buildContactItem(Icons.phone_rounded, '+63 123 456 7890'),
      ],
    );
  }

  Widget _buildContactItem(IconData icon, String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(10),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.15),
                  blurRadius: 6,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            alignment: Alignment.center,
            child: Icon(icon, color: _brandDark, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                text,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.98),
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  height: 1.35,
                ),
                softWrap: true,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSocialIcon(IconData icon) {
    return Container(
      margin: const EdgeInsets.only(left: 10),
      width: 42,
      height: 42,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.18),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      alignment: Alignment.center,
      child: Icon(icon, color: _brandDark, size: 22),
    );
  }
}

/// Full-screen destination photo (mobile only) from the explore dialog.
class _DestinationImageFullscreenPage extends StatelessWidget {
  const _DestinationImageFullscreenPage({
    required this.imageUrl,
    required this.isAsset,
    required this.title,
  });

  final String imageUrl;
  final bool isAsset;
  final String title;

  static const _fallback =
      'https://images.unsplash.com/photo-1480714378408-67cf0d13bc1b?w=1200';

  Widget _buildImage() {
    if (isAsset) {
      return Image.asset(
        imageUrl,
        fit: BoxFit.contain,
        errorBuilder: (_, __, ___) => Image.network(
          _fallback,
          fit: BoxFit.contain,
        ),
      );
    }
    return Image.network(
      imageUrl,
      fit: BoxFit.contain,
      errorBuilder: (_, __, ___) => Image.network(_fallback, fit: BoxFit.contain),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        elevation: 0,
        title: Text(
          title,
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
          ),
        ),
        leadingWidth: 80,
        leading: Padding(
          padding: const EdgeInsets.only(left: 8),
          child: Center(
            child: FilledButton(
              onPressed: () => Navigator.pop(context),
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFFF97316),
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
      ),
      body: SafeArea(
        child: InteractiveViewer(
          minScale: 1,
          maxScale: 4,
          child: Center(
            child: _buildImage(),
          ),
        ),
      ),
    );
  }
}

import 'dart:async' show Timer, unawaited;

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show debugPrint, kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderAbstractViewport;
import 'package:atmos_trs_system/features/navigation/placeholder_pages.dart'
    show ScanTabPage;
import 'package:atmos_trs_system/navigation/landing_intent_navigation.dart';
import 'package:atmos_trs_system/navigation/login_route_args.dart';
import 'package:atmos_trs_system/navigation/tripplan_entry_screen.dart';
import 'package:atmos_trs_system/data/landing_lgu_destinations.dart';
import 'package:atmos_trs_system/screens/municipality_map_and_spots_screen.dart';
import 'package:atmos_trs_system/widgets/atmos_brand_title.dart';
import 'package:atmos_trs_system/widgets/atmos_square_logo.dart';
import 'package:atmos_trs_system/widgets/hero_video_branding_overlay.dart';
import 'package:atmos_trs_system/widgets/hero_video_mute_control.dart';
import 'package:atmos_trs_system/widgets/onboarding_hero_video.dart';
import 'package:atmos_trs_system/config/atmos_brand_typography.dart';
import 'package:atmos_trs_system/config/session_storage.dart';
import 'package:atmos_trs_system/config/supabase_storage_config.dart';
import 'package:atmos_trs_system/services/landing_intent_service.dart';
import 'package:atmos_trs_system/services/login_flow_service.dart';
import 'package:atmos_trs_system/screens/vr_webview_screen.dart';
import 'package:atmos_trs_system/widgets/vr_download_app_prompt.dart';
import 'package:atmos_trs_system/utils/logo_utils.dart';
import 'package:atmos_trs_system/widgets/spot_image.dart';
import 'package:google_fonts/google_fonts.dart';
import 'dart:ui' show ImageFilter;

class LandingPage extends StatefulWidget {
  const LandingPage({super.key});

  @override
  State<LandingPage> createState() => _LandingPageState();
}

class _LandingPageState extends State<LandingPage> {
  bool _isScrolled = false;
  int? _hoveredExperienceIndex;
  int? _hoveredFeatureIndex;
  int? _hoveredHeroGlassIndex;
  String? _hoveredDestinationName;

  String? _activeSection = 'home';
  bool _signupSuccessPromptShown = false;
  String? _qrWelcomeMessage;
  bool _highlightExperienceSection = false;

  late final ScrollController _pageScrollController;

  /// While true, skip scroll listener rebuilds (avoids jank during nav taps).
  bool _isNavScrollAnimating = false;

  Timer? _scrollUiThrottle;
  Timer? _heavyImageWarmTimer;

  /// Municipality / About photos wait until the hero has painted (or user scrolls).
  bool _heavyImagesEnabled = false;
  /// First batch of destination cards (above the fold once Destinations is near).
  int _destinationImageBudget = 0;

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
    'baliangao': ['bless', 'amare', 'sunrise', 'beach', 'tugas'],
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
  static const Color _darkBg = Color(0xFF192334);
  static const Color _accentOrange = Color(0xFFFB923C);

  /// Page shell: crisp white with optional muted strips (avoids cream/peach page fills).
  static const Color _pageBackground = Color(0xFFFFFFFF);
  static const Color _pageSurfaceMuted = Color(0xFFF8FAFC);
  static const Color _pageDivider = Color(0xFFE5E7EB);
  static const Color _bodyText = Color(0xFF334155);
  static const double _cardRadius = 18.0;

  static const String _kAppFullName =
      'ATMOS-TRS - Asenso Tourismo Misamis Occidental Smart Tourist Registration System';

  static const String _kAppMeaning =
      'Asenso Tourismo Misamis Occidental Smart Tourist Registration System';

  static const String _kTourismLogoAsset = 'assets/images/tourism logo.png';
  static const String _kLandingHeroBackgroundAsset =
      'assets/images/landing page.png';
  static const String _kCapitolAsset = 'assets/images/capitol.webp';

  String get _landingHeroBackgroundUrl =>
      SupabaseStorageConfig.resolve(_kLandingHeroBackgroundAsset);

  ImageProvider get _landingHeroBackgroundImage {
    final url = _landingHeroBackgroundUrl;
    final size = MediaQuery.sizeOf(context);
    final dpr = MediaQuery.devicePixelRatioOf(context);
    final cacheW = (size.width * dpr).round().clamp(720, 1600);
    if (url.startsWith('http://') || url.startsWith('https://')) {
      return ResizeImage(NetworkImage(url), width: cacheW);
    }
    return ResizeImage(AssetImage(url), width: cacheW);
  }

  void _enableHeavyImages({int budget = 8}) {
    if (!mounted) return;
    final nextBudget = budget > _destinationImageBudget
        ? budget
        : _destinationImageBudget;
    if (_heavyImagesEnabled && nextBudget == _destinationImageBudget) return;
    setState(() {
      _heavyImagesEnabled = true;
      _destinationImageBudget = nextBudget;
    });
  }

  void _scheduleHeavyImageWarmup() {
    _heavyImageWarmTimer?.cancel();
    // Let the hero paint first, then warm a few cards, then the rest.
    _heavyImageWarmTimer = Timer(const Duration(milliseconds: 450), () {
      if (!mounted) return;
      _enableHeavyImages(budget: 6);
      Future<void>.delayed(const Duration(milliseconds: 900), () {
        if (!mounted) return;
        _enableHeavyImages(budget: _destinations.length);
      });
    });
  }

  /// Soft tinted card backgrounds + accents (Asenso orange family).
  final List<Map<String, dynamic>> _features = [
    {
      'icon': Icons.qr_code_rounded,
      'title': 'QR Code Registration',
      'description':
          'Quick and easy tourist registration with unique QR code identification',
      'accent': _primaryOrange,
    },
    {
      'icon': Icons.vrpano_rounded,
      'title': 'Virtual Reality Tours',
      'description':
          'Explore destinations in immersive 360° VR before you visit',
      'accent': _primaryOrange,
    },
    {
      'icon': Icons.qr_code_scanner_rounded,
      'title': 'Smart Check-ins',
      'description':
          'Scan your QR at tourist spots for seamless check-in experience',
      'accent': _primaryOrange,
    },
    {
      'icon': Icons.badge_rounded,
      'title': 'Digital Tourist ID',
      'description':
          'Your unique digital identification for all tourist activities',
      'accent': _primaryOrange,
    },
    {
      'icon': Icons.map_rounded,
      'title': 'Itinerary Planner',
      'description': 'Plan and organize your travel itinerary',
      'accent': _primaryOrange,
      'route': 'itinerary',
    },
  ];

  /// Images resolved from [TouristSpotImageCatalog] — same as the mobile app.
  late final List<Map<String, String>> _destinations =
      buildLandingLguDestinations();

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

    _heroSearchController.addListener(_onHeroSearchTextChanged);
    _heroSearchFocusNode.addListener(_onHeroSearchFocusChanged);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _handleLandingRouteArguments();
      unawaited(logoWithoutWhiteFuture);
      final size = MediaQuery.sizeOf(context);
      final dpr = MediaQuery.devicePixelRatioOf(context);
      final cacheW = (size.width * dpr).round().clamp(720, 1600);
      precacheImage(
        ResizeImage(
          NetworkImage(
            SupabaseStorageConfig.resolve(
              'assets/images/landing page.png',
            ),
          ),
          width: cacheW,
        ),
        context,
      );
      _scheduleHeavyImageWarmup();
    });
  }

  void _handleLandingRouteArguments() {
    if (!mounted) return;
    final args = ModalRoute.of(context)?.settings.arguments;
    final mapArgs = args is Map ? Map<String, dynamic>.from(args) : null;
    if (mapArgs == null) return;

    final fromQr = mapArgs['fromQrRegistration'] == true;
    final fromQrGuest = mapArgs['fromQrWelcomeGuest'] == true;
    final welcome = mapArgs['welcomeMessage'];
    final welcomeText =
        welcome is String && welcome.trim().isNotEmpty ? welcome.trim() : null;

    if ((fromQr || fromQrGuest) && welcomeText != null) {
      setState(() {
        _qrWelcomeMessage = welcomeText;
        _highlightExperienceSection = true;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(welcomeText),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 6),
          backgroundColor: _brandDark,
        ),
      );
      Future<void>.delayed(const Duration(milliseconds: 500), () {
        if (mounted) unawaited(_scrollToSection('chooseExperience'));
      });
      return;
    }

    if (_signupSuccessPromptShown) return;
    final shouldShow = mapArgs['showSignupSuccessPrompt'] == true;
    if (!shouldShow) return;

    _signupSuccessPromptShown = true;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Signup successful. Please sign in to continue.'),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
  }

  void _pauseHeroVideoForAuthNavigation() {
    unawaited(OnboardingHeroVideo.of(context).pauseForAuthOverlay());
    unawaited(OnboardingHeroVideo.of(context).setHeroVideoMuted(true));
  }

  void _resumeHeroVideoAfterAuthNavigation() {
    unawaited(OnboardingHeroVideo.of(context).resumeAfterAuthOverlay());
  }

  Future<T?> _pushAuthRoute<T>(String route, {Object? arguments}) {
    _pauseHeroVideoForAuthNavigation();
    return Navigator.of(context)
        .pushNamed<T>(route, arguments: arguments)
        .then((result) {
      if (mounted) _resumeHeroVideoAfterAuthNavigation();
      return result;
    });
  }

  void _navigateToLogin() {
    _pushAuthRoute('/login');
  }

  void _navigateToSignup() {
    _pushAuthRoute('/signup');
  }

  void _navigateToLoginForFeature({
    required String returnFeature,
    String? municipalityName,
  }) {
    final name = municipalityName?.trim();
    unawaited(
      LandingIntentService.setPending(
        feature: returnFeature,
        municipalityName: name,
      ),
    );
    _pushAuthRoute(
      '/login',
      arguments: LoginRouteArgs.forFeature(
        returnFeature: returnFeature,
        municipalityName: name,
      ),
    ).then((result) {
      if (!mounted || result is! String) return;
      _continueLandingFeatureAfterLogin(
        returnFeature: result,
        municipalityName: name,
      );
    });
  }

  Future<void> _continueLandingFeatureAfterLogin({
    required String returnFeature,
    String? municipalityName,
  }) async {
    await LandingIntentService.clear();
    if (!mounted) return;
    await LandingIntentNavigation.executeIntent(
      context,
      LandingIntent(
        feature: returnFeature,
        municipalityName: municipalityName,
      ),
    );
  }

  void _pushTripPlanEntry() {
    final heroController = OnboardingHeroVideo.read(context)?.controller;
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (context) => TripPlanEntryScreen(
          sharedHeroController: heroController,
        ),
      ),
    );
  }

  Future<void> _openPlanItinerary({String? municipalityName}) async {
    _pauseHeroVideoForAuthNavigation();
    await LandingIntentService.setPending(
      feature: LoginRouteArgs.featureItinerary,
      municipalityName: municipalityName,
    );
    if (!_isLoggedIn) {
      _navigateToLoginForFeature(
        returnFeature: LoginRouteArgs.featureItinerary,
        municipalityName: municipalityName,
      );
      return;
    }
    await LandingIntentService.clear();
    _pushTripPlanEntry();
  }

  Future<void> _openVrTourFromLanding({String? municipalityName}) async {
    _pauseHeroVideoForAuthNavigation();
    if (VrDownloadAppPrompt.blocksVrOnWeb) {
      await VrDownloadAppPrompt.show(context);
      return;
    }
    await LandingIntentService.setPending(
      feature: LoginRouteArgs.featureVr,
      municipalityName: municipalityName,
    );
    if (!_isLoggedIn) {
      _navigateToLoginForFeature(
        returnFeature: LoginRouteArgs.featureVr,
        municipalityName: municipalityName,
      );
      return;
    }
    await LandingIntentService.clear();
    if (!mounted) return;
    final title = municipalityName != null && municipalityName.isNotEmpty
        ? 'VR Tour — $municipalityName'
        : 'VR Tour';
    unawaited(openVrTour(context, title: title));
  }

  String get _landingVrButtonLabel {
    if (VrDownloadAppPrompt.blocksVrOnWeb) return 'Get the ATMOS app';
    return _isMobile ? 'VR Tour' : 'Start VR Tour';
  }

  String get _landingVrQuickActionLabel {
    if (VrDownloadAppPrompt.blocksVrOnWeb) return 'Get ATMOS app';
    return 'VR Tour';
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
    return scrollOffset + padTop + _landingAppBarHeight + 20;
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
    final screenH = MediaQuery.sizeOf(context).height;

    // Start loading destination photos once the user is near that section.
    if (!_heavyImagesEnabled || _destinationImageBudget < _destinations.length) {
      if (offset > screenH * 0.55) {
        _enableHeavyImages(budget: _destinations.length);
      }
    }

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
    if (!mounted) return;
    if (_heroSearchController.text.trim().isNotEmpty) {
      _enableHeavyImages(budget: _destinations.length);
    }
    setState(() {});
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

  bool get _heroSearchSuggestionsOpen =>
      _heroSearchFocusNode.hasFocus &&
      _heroSearchController.text.trim().isNotEmpty;

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
    _heavyImageWarmTimer?.cancel();
    _heroSearchController.removeListener(_onHeroSearchTextChanged);
    _heroSearchFocusNode.removeListener(_onHeroSearchFocusChanged);
    _heroSearchController.dispose();
    _heroSearchFocusNode.dispose();
    OnboardingHeroVideo.read(context)?.releaseLandingHeroVideo();
    _pageScrollController.dispose();
    super.dispose();
  }

  bool get _isMobile => MediaQuery.of(context).size.width < 768;

  /// Hero image height on municipality / city destination cards.
  double get _destinationCardImageHeight => _isMobile ? 176.0 : 200.0;

  bool get _isLoggedIn => FirebaseAuth.instance.currentUser != null;
  bool get _isTablet =>
      MediaQuery.of(context).size.width >= 768 &&
      MediaQuery.of(context).size.width < 1024;
  bool get _isDesktop => MediaQuery.of(context).size.width >= 1024;
  bool get _isWideDesktop => MediaQuery.of(context).size.width >= 1366;
  bool get _isUltraWide => MediaQuery.of(context).size.width >= 1920;

  /// Drawer + menu button for phones and tablets.
  bool get _useDrawerNav => MediaQuery.of(context).size.width < 1024;

  /// Smaller nav chips when horizontal space is limited.
  bool get _navCompact => MediaQuery.of(context).size.width < 1280;

  /// Shorter nav labels so all items fit on the right without clipping.
  bool get _navTight => MediaQuery.of(context).size.width < 1200;

  double get _landingAppBarHeight =>
      _useDrawerNav ? (_isMobile ? 96.0 : 88.0) : 72.0;

  /// One full-screen panel per nav item (area below the app bar).
  double get _sectionViewportHeight {
    final screenH = MediaQuery.sizeOf(context).height;
    return (screenH - _landingAppBarHeight).clamp(420.0, screenH);
  }

  double get _sectionContentMaxWidth {
    if (_isUltraWide) return 1560;
    if (_isWideDesktop) return 1360;
    if (_isDesktop) return 1180;
    return double.infinity;
  }

  double get _sectionTitleFontSize {
    if (_isMobile) return 30;
    if (_isTablet) return 34;
    if (_isWideDesktop) return 42;
    return 38;
  }

  double get _sectionSubtitleFontSize {
    if (_isMobile) return 15;
    if (_isTablet) return 16;
    return 17;
  }

  double get _sectionSubtitleMaxWidth {
    if (_isWideDesktop) return 860;
    if (_isDesktop) return 760;
    if (_isTablet) return 680;
    return 640;
  }

  Duration get _motionDuration => MediaQuery.disableAnimationsOf(context)
      ? Duration.zero
      : const Duration(milliseconds: 250);

  double get _sectionOuterPadding => _isMobile ? 16.0 : 32.0;

  double _sectionInnerVertical({required bool viewport}) {
    if (viewport) return _isMobile ? 16.0 : 32.0;
    return _isMobile ? 40.0 : 64.0;
  }

  Widget _wrapSectionContent(Widget child) {
    return SizedBox(
      width: double.infinity,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: _sectionContentMaxWidth),
        child: child,
      ),
    );
  }

  BoxDecoration _surfaceCardDecoration({
    bool hovered = false,
    Color accent = _primaryOrange,
  }) {
    return BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(_cardRadius),
      border: Border.all(
        color: hovered
            ? accent.withValues(alpha: 0.40)
            : const Color(0xFFE8ECF1),
        width: hovered ? 1.5 : 1,
      ),
      boxShadow: [
        BoxShadow(
          color: hovered
              ? accent.withValues(alpha: 0.12)
              : Colors.black.withValues(alpha: 0.05),
          blurRadius: hovered ? 20 : 12,
          offset: Offset(0, hovered ? 8 : 4),
        ),
      ],
    );
  }

  Widget _landingIconTile(
    IconData icon, {
    Color accent = _primaryOrange,
    double size = 48,
  }) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [accent, _brandDark],
        ),
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: accent.withValues(alpha: 0.32),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      alignment: Alignment.center,
      child: Icon(icon, color: Colors.white, size: size * 0.45),
    );
  }

  TextStyle get _sectionBodyStyle => TextStyle(
        color: _bodyText,
        fontSize: _isMobile ? 15 : 16,
        height: 1.6,
        fontWeight: FontWeight.w400,
      );

  TextStyle get _cardTitleStyle => TextStyle(
        color: _darkBg,
        fontSize: _isMobile ? 16 : 17,
        fontWeight: FontWeight.w700,
        height: 1.25,
        letterSpacing: -0.2,
      );

  TextStyle get _cardSubtitleStyle => TextStyle(
        color: _bodyText,
        fontSize: _isMobile ? 14 : 15,
        height: 1.45,
        fontWeight: FontWeight.w400,
      );

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
    if (section == 'destinations' ||
        section == 'about' ||
        section == 'howItWorks') {
      _enableHeavyImages(budget: _destinations.length);
    }
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
        .getOffsetToReveal(renderObject, 0.0)
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
                Container(
                  key: _keyHome,
                  height: MediaQuery.sizeOf(context).height,
                  child: _buildHeroSection(),
                ),
                if (!_isLoggedIn) _buildRegisterCalloutSection(),
                _buildViewportNavSection(
                  key: _keyChooseExperience,
                  color: _pageBackground,
                  fullScreenOnWeb: true,
                  child: _buildChooseYourExperienceSection(viewport: true),
                ),
                _buildViewportNavSection(
                  key: _keyFeatures,
                  color: _pageSurfaceMuted,
                  child: _buildFeaturesSection(viewport: true),
                ),
                _buildViewportNavSection(
                  key: _keyDestinations,
                  color: _pageBackground,
                  child: _buildDestinationsSection(viewport: true),
                ),
                _buildViewportNavSection(
                  key: _keyHowItWorks,
                  color: _pageSurfaceMuted,
                  child: _buildHowItWorksSection(viewport: true),
                ),
                _buildViewportNavSection(
                  key: _keyAbout,
                  color: _pageBackground,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _buildAboutSection(viewport: true),
                      _buildStatisticsSection(viewport: true),
                    ],
                  ),
                ),
                _buildFooter(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildAppBarBrandText() {
    final width = MediaQuery.sizeOf(context).width;
    final narrow = width < 520;
    final titleSize =
        _isMobile ? (narrow ? 18.0 : 20.0) : (_useDrawerNav ? 20.0 : 22.0);
    final meaningSize = narrow ? 8.5 : (_isMobile ? 9.0 : 9.5);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisAlignment: MainAxisAlignment.center,
      mainAxisSize: MainAxisSize.min,
      children: [
        AtmosBrandTitle(
          fontSize: titleSize,
          letterSpacing: narrow ? 0.85 : 1.0,
          textAlign: TextAlign.start,
        ),
        const SizedBox(height: 2),
        Text(
          _kAppMeaning,
          maxLines: narrow ? 3 : 2,
          overflow: TextOverflow.ellipsis,
          style: AtmosBrandTypography.meaningTagline(
            color: const Color(0xFF6B7280),
            fontSize: meaningSize,
            letterSpacing: 0.15,
            fontWeight: FontWeight.w500,
            height: 1.2,
          ),
        ),
      ],
    );
  }

  PreferredSizeWidget _buildAppBar() {
    final barHeight = _landingAppBarHeight;
    return PreferredSize(
      preferredSize: Size.fromHeight(barHeight),
      child: ClipRRect(
        borderRadius: const BorderRadius.only(
          bottomLeft: Radius.circular(28),
          bottomRight: Radius.circular(28),
        ),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
          child: AnimatedContainer(
            duration: _motionDuration,
            curve: Curves.easeOutCubic,
            decoration: BoxDecoration(
              color: Colors.white.withValues(
                alpha: _isScrolled ? 0.97 : 0.92,
              ),
              borderRadius: const BorderRadius.only(
                bottomLeft: Radius.circular(28),
                bottomRight: Radius.circular(28),
              ),
              border: Border(
                bottom: BorderSide(
                  color: Colors.white.withValues(alpha: 0.7),
                ),
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(
                    alpha: _isScrolled ? 0.10 : 0.06,
                  ),
                  blurRadius: _isScrolled ? 16 : 12,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: AppBar(
              backgroundColor: Colors.transparent,
              elevation: 0,
              scrolledUnderElevation: 0,
              toolbarHeight: barHeight,
              leadingWidth: 0,
              leading: const SizedBox.shrink(),
              titleSpacing: 0,
              title: Padding(
                padding: EdgeInsets.only(
                  left: _useDrawerNav ? 4 : 16,
                  right: _useDrawerNav ? 8 : 8,
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
                          icon: const Icon(
                            Icons.menu_rounded,
                            color: Color(0xFF192334),
                          ),
                          onPressed: () => Scaffold.of(context).openDrawer(),
                        ),
                      ),
                    AtmosSquareLogo(
                      height: _useDrawerNav ? (_isMobile ? 44.0 : 40.0) : 40.0,
                      padding: const EdgeInsets.all(3),
                      borderRadius: 20,
                      elevation: 0,
                    ),
                    const SizedBox(width: 8),
                    Flexible(
                      flex: _useDrawerNav ? 1 : 2,
                      child: _buildAppBarBrandText(),
                    ),
                    ListenableBuilder(
                      listenable: OnboardingHeroVideo.of(context),
                      builder: (context, _) {
                        final hero = OnboardingHeroVideo.of(context);
                        if (!hero.showVideoOnLandingHero) {
                          return const SizedBox.shrink();
                        }
                        return Padding(
                          padding: const EdgeInsets.only(left: 4),
                          child: HeroVideoMuteControl(
                            forAppBar: true,
                            iconSize: _isMobile ? 20 : 22,
                          ),
                        );
                      },
                    ),
                  ],
                ),
              ),
              actions: [
                if (!_useDrawerNav)
                  Padding(
                    padding: const EdgeInsets.only(right: 12),
                    child: Center(child: _buildInlineNavBar()),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Fixed-height panel for nav targets; scroll inside if content is taller than one screen.
  Widget _buildViewportNavSection({
    required GlobalKey key,
    required Color color,
    required Widget child,
    bool fullScreenOnWeb = false,
  }) {
    final useViewportPanel =
        _isMobile || (kIsWeb && fullScreenOnWeb && !_isMobile);
    return Container(
      key: key,
      constraints: BoxConstraints(
        minHeight: useViewportPanel ? _sectionViewportHeight : 0,
      ),
      width: double.infinity,
      color: color,
      child: Padding(
        padding: EdgeInsets.only(
          top: _landingAppBarHeight + (_isMobile ? 8 : 16),
          bottom: _isMobile ? 24 : 32,
          left: _sectionOuterPadding,
          right: _sectionOuterPadding,
        ),
        child: Align(
          alignment: useViewportPanel ? Alignment.center : Alignment.topCenter,
          child: _wrapSectionContent(child),
        ),
      ),
    );
  }

  Widget _buildInlineNavBar() {
    final compact = _navCompact;

    return SingleChildScrollView(
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
          if (!_isLoggedIn) ...[
            _buildHeaderAuthChip(
              label: 'Log In',
              onTap: _navigateToLogin,
              compact: compact,
            ),
            _buildHeaderAuthChip(
              label: 'Sign Up',
              onTap: _navigateToSignup,
              compact: compact,
              emphasized: true,
            ),
          ],
        ],
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
      padding: EdgeInsets.symmetric(horizontal: compact ? 2 : 3),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(24),
          hoverColor: _primaryOrange.withValues(alpha: 0.08),
          child: AnimatedContainer(
            duration: _motionDuration,
            curve: Curves.easeOut,
            padding: EdgeInsets.symmetric(
              horizontal: compact ? 8 : 11,
              vertical: compact ? 6 : 7,
            ),
            decoration: BoxDecoration(
              color: isActive ? _primaryOrange : Colors.transparent,
              borderRadius: BorderRadius.circular(24),
            ),
            child: Text(
              label,
              style: TextStyle(
                color: isActive ? Colors.white : const Color(0xFF192334),
                fontSize: compact ? 12 : 13,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.05,
                height: 1.15,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeaderAuthChip({
    required String label,
    required VoidCallback onTap,
    bool compact = false,
    bool emphasized = false,
  }) {
    return Padding(
      padding: EdgeInsets.only(
        left: compact ? 3 : 5,
        right: compact ? 3 : 4,
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(24),
          child: AnimatedContainer(
            duration: _motionDuration,
            curve: Curves.easeOut,
            padding: EdgeInsets.symmetric(
              horizontal: compact ? 10 : 14,
              vertical: compact ? 6 : 7,
            ),
            decoration: BoxDecoration(
              color: emphasized ? _primaryOrange : Colors.transparent,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(
                color: _primaryOrange,
                width: emphasized ? 0 : 1.5,
              ),
            ),
            child: Text(
              label,
              style: TextStyle(
                color: emphasized ? Colors.white : _primaryOrange,
                fontSize: compact ? 12 : 13,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.1,
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
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(20, 24, 20, 24),
              color: _pageBackground,
              child: Center(
                child: AtmosSquareLogo(
                  height: 72,
                  maxWidth: double.infinity,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                  borderRadius: 14,
                  elevation: 2,
                ),
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
            ),
            const Divider(height: 24),
            if (!_isLoggedIn)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                child: Column(
                  children: [
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton(
                        onPressed: () {
                          Navigator.pop(context);
                          _navigateToLogin();
                        },
                        style: OutlinedButton.styleFrom(
                          foregroundColor: _primaryOrange,
                          side: const BorderSide(
                            color: _primaryOrange,
                            width: 1.5,
                          ),
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(24),
                          ),
                        ),
                        child: const Text(
                          'Log In',
                          style: TextStyle(fontWeight: FontWeight.w700),
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        onPressed: () {
                          Navigator.pop(context);
                          _navigateToSignup();
                        },
                        style: FilledButton.styleFrom(
                          backgroundColor: _primaryOrange,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(24),
                          ),
                        ),
                        child: const Text(
                          'Sign Up',
                          style: TextStyle(fontWeight: FontWeight.w700),
                        ),
                      ),
                    ),
                  ],
                ),
              )
            else
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                child: SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: () {
                      Navigator.pop(context);
                      unawaited(_openUserApp());
                    },
                    style: FilledButton.styleFrom(
                      backgroundColor: _primaryOrange,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(24),
                      ),
                    ),
                    child: const Text('Go to dashboard'),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  /// Keeps hero copy readable on bright capitol photography.
  static const List<Shadow> _heroTextShadow = [
    Shadow(offset: Offset(0, 1), blurRadius: 4, color: Color(0x99000000)),
    Shadow(offset: Offset(0, 2), blurRadius: 10, color: Color(0x66000000)),
  ];

  Widget _buildHeroSection() {
    final h = MediaQuery.sizeOf(context).height;
    final topInset = MediaQuery.paddingOf(context).top +
        _landingAppBarHeight +
        (_isMobile ? 8 : 12);

    return SizedBox(
      height: h,
      width: double.infinity,
      child: Stack(
        fit: StackFit.expand,
        children: [
          DecoratedBox(
            decoration: BoxDecoration(
              image: DecorationImage(
                image: _landingHeroBackgroundImage,
                fit: BoxFit.cover,
                alignment: const Alignment(0.15, -0.08),
                filterQuality: FilterQuality.high,
                onError: (exception, stackTrace) {
                  debugPrint('[Landing] hero bg failed: $exception');
                },
              ),
              color: const Color(0xFF192334),
            ),
          ),
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.centerLeft,
                end: Alignment.centerRight,
                colors: [
                  Colors.black.withValues(alpha: _isMobile ? 0.55 : 0.48),
                  Colors.black.withValues(alpha: 0.28),
                  Colors.black.withValues(alpha: 0.08),
                  Colors.transparent,
                ],
                stops: const [0.0, 0.32, 0.58, 0.82],
              ),
            ),
          ),
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.black.withValues(alpha: 0.10),
                  Colors.transparent,
                  Colors.black.withValues(alpha: 0.42),
                ],
                stops: const [0.0, 0.45, 1.0],
              ),
            ),
          ),
          Padding(
            padding: EdgeInsets.fromLTRB(
              _isMobile ? 20 : 56,
              topInset + (_isMobile ? 20 : 28),
              _isMobile ? 20 : 56,
              20,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: SingleChildScrollView(
                    clipBehavior: Clip.none,
                    child: Align(
                      alignment: _isMobile
                          ? Alignment.topCenter
                          : Alignment.topLeft,
                      child: ConstrainedBox(
                        constraints: BoxConstraints(
                          maxWidth: _isMobile ? 520 : 640,
                        ),
                        child: Column(
                          crossAxisAlignment: _isMobile
                              ? CrossAxisAlignment.center
                              : CrossAxisAlignment.start,
                          children: [
                            _buildHeroHeadline(),
                            SizedBox(height: _isMobile ? 18 : 22),
                            _buildHeroSearchBarLight(),
                            if (!_heroSearchSuggestionsOpen) ...[
                              SizedBox(height: _isMobile ? 20 : 28),
                              _buildHeroGlassFeatureCards(),
                              if (_isLoggedIn) ...[
                                const SizedBox(height: 18),
                                _buildLoggedInHeroActions(),
                              ],
                            ],
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
                if (!_heroSearchSuggestionsOpen)
                  Padding(
                    padding: EdgeInsets.only(
                      bottom: MediaQuery.paddingOf(context).bottom + 6,
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Expanded(
                          child: Row(
                            children: [
                              const Icon(
                                Icons.location_on_rounded,
                                color: Colors.white,
                                size: 18,
                              ),
                              const SizedBox(width: 6),
                              Flexible(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Text(
                                      'MISAMIS OCCIDENTAL',
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontSize: 11,
                                        fontWeight: FontWeight.w800,
                                        letterSpacing: 0.6,
                                      ),
                                    ),
                                    Text(
                                      'A PROVINCE OF ENDLESS POSSIBILITIES',
                                      style: TextStyle(
                                        color: Colors.white.withValues(
                                          alpha: 0.85,
                                        ),
                                        fontSize: 8.5,
                                        fontWeight: FontWeight.w600,
                                        letterSpacing: 0.4,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                        GestureDetector(
                          onTap: () => _scrollToSection('chooseExperience'),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.mouse_outlined,
                                color: Colors.white.withValues(alpha: 0.75),
                                size: 22,
                              ),
                              Icon(
                                Icons.keyboard_arrow_down_rounded,
                                color: Colors.white.withValues(alpha: 0.75),
                                size: 20,
                              ),
                              Text(
                                'Scroll to explore',
                                style: TextStyle(
                                  color: Colors.white.withValues(alpha: 0.7),
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const Expanded(child: SizedBox.shrink()),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeroGlassFeatureCards() {
    final cards = const [
      (
        icon: Icons.vrpano_rounded,
        title: '360Â° Previews',
        subtitle: 'See before you go',
      ),
      (
        icon: Icons.map_rounded,
        title: 'Trip Planner',
        subtitle: 'Plan your adventure',
      ),
      (
        icon: Icons.groups_rounded,
        title: '17 LGUs',
        subtitle: 'Explore all municipalities',
      ),
      (
        icon: Icons.qr_code_scanner_rounded,
        title: 'QR Check-in',
        subtitle: 'Travel made easy',
      ),
    ];

    Widget buildCard(
      int index,
      ({IconData icon, String title, String subtitle}) c,
    ) {
      final hovered = _hoveredHeroGlassIndex == index;
      return MouseRegion(
        onEnter: (_) => setState(() => _hoveredHeroGlassIndex = index),
        onExit: (_) => setState(() => _hoveredHeroGlassIndex = null),
        child: AnimatedContainer(
          duration: _motionDuration,
          curve: Curves.easeOutCubic,
          transform: Matrix4.identity()
            ..translateByDouble(0, hovered ? -4.0 : 0.0, 0, 1),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(18),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 6, sigmaY: 6),
              child: AnimatedContainer(
                duration: _motionDuration,
                padding: EdgeInsets.symmetric(
                  horizontal: _isMobile ? 12 : 12,
                  vertical: _isMobile ? 10 : 10,
                ),
                decoration: BoxDecoration(
                  color: Color(hovered ? 0x660F172A : 0x4D0F172A),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: Colors.white.withValues(
                      alpha: hovered ? 0.28 : 0.16,
                    ),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(
                        alpha: hovered ? 0.10 : 0.05,
                      ),
                      blurRadius: hovered ? 12 : 6,
                      offset: Offset(0, hovered ? 4 : 2),
                    ),
                  ],
                ),
                child: _isMobile
                    ? Row(
                        children: [
                          _heroGlassIconBadge(c.icon),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  c.title,
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 13.5,
                                    fontWeight: FontWeight.w800,
                                    shadows: const [
                                      Shadow(
                                        offset: Offset(0, 1),
                                        blurRadius: 4,
                                        color: Color(0x99000000),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  c.subtitle,
                                  style: TextStyle(
                                    color: Colors.white.withValues(alpha: 0.92),
                                    fontSize: 11,
                                    fontWeight: FontWeight.w500,
                                    shadows: const [
                                      Shadow(
                                        offset: Offset(0, 1),
                                        blurRadius: 3,
                                        color: Color(0x88000000),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      )
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _heroGlassIconBadge(c.icon),
                          const SizedBox(height: 8),
                          Text(
                            c.title,
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 13.5,
                              fontWeight: FontWeight.w800,
                              height: 1.15,
                              shadows: const [
                                Shadow(
                                  offset: Offset(0, 1),
                                  blurRadius: 4,
                                  color: Color(0x99000000),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            c.subtitle,
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.92),
                              fontSize: 11,
                              fontWeight: FontWeight.w500,
                              height: 1.25,
                              shadows: const [
                                Shadow(
                                  offset: Offset(0, 1),
                                  blurRadius: 3,
                                  color: Color(0x88000000),
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
      );
    }

    if (_isMobile) {
      return Column(
        children: [
          for (var i = 0; i < cards.length; i++) ...[
            if (i > 0) const SizedBox(height: 8),
            buildCard(i, cards[i]),
          ],
        ],
      );
    }

    // Keep the row compact on the left so the ASENSO sign on the hero photo
    // stays visible on the right.
    return Align(
      alignment: Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 640),
        child: Row(
          children: [
            for (var i = 0; i < cards.length; i++) ...[
              if (i > 0) const SizedBox(width: 8),
              Expanded(child: buildCard(i, cards[i])),
            ],
          ],
        ),
      ),
    );
  }

  Widget _heroGlassIconBadge(IconData icon) {
    return Container(
      width: 30,
      height: 30,
      decoration: BoxDecoration(
        color: _primaryOrange,
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: _primaryOrange.withValues(alpha: 0.35),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      alignment: Alignment.center,
      child: Icon(icon, color: Colors.white, size: 16),
    );
  }

  Widget _buildHeroHeadline() {
    final align = _isMobile ? TextAlign.center : TextAlign.left;
    return Column(
      crossAxisAlignment:
          _isMobile ? CrossAxisAlignment.center : CrossAxisAlignment.start,
      children: [
        Text(
          'EXPLORE  â€¢  EXPERIENCE  â€¢  BELONG',
          textAlign: align,
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.92),
            fontSize: _isMobile ? 11 : 12.5,
            fontWeight: FontWeight.w700,
            letterSpacing: 2.6,
            shadows: _heroTextShadow,
          ),
        ),
        SizedBox(height: _isMobile ? 10 : 14),
        Text(
          'Discover',
          textAlign: align,
          style: TextStyle(
            color: Colors.white,
            fontSize: _isMobile ? 40 : 58,
            fontWeight: FontWeight.w800,
            height: 0.95,
            letterSpacing: -0.8,
            shadows: _heroTextShadow,
            fontFamily: 'Georgia',
          ),
        ),
        Transform.translate(
          offset: Offset(_isMobile ? 0 : -2, _isMobile ? -4 : -8),
          child: Text(
            'Misamis Occidental',
            textAlign: align,
            style: GoogleFonts.greatVibes(
              color: _primaryOrange,
              fontSize: _isMobile ? 44 : 72,
              height: 0.95,
              shadows: _heroTextShadow,
            ),
          ),
        ),
        SizedBox(height: _isMobile ? 10 : 14),
        Text(
          'Your journey starts here.',
          textAlign: align,
          style: TextStyle(
            color: Colors.white,
            fontSize: _isMobile ? 17 : 21,
            fontWeight: FontWeight.w700,
            shadows: _heroTextShadow,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Walk destinations in immersive 360Â°, map your dream itinerary, '
          'and discover all 17 LGUs â€” before you even pack your bags.',
          textAlign: align,
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.92),
            fontSize: _isMobile ? 14 : 15.5,
            height: 1.5,
            fontWeight: FontWeight.w500,
            shadows: _heroTextShadow,
          ),
        ),
      ],
    );
  }
  Future<void> _openUserApp({int initialIndex = 0}) async {
    _pauseHeroVideoForAuthNavigation();
    if (!_isLoggedIn) {
      _navigateToLogin();
      return;
    }

    final user = FirebaseAuth.instance.currentUser;
    final email = (user?.email ?? '').trim();
    final uid = user?.uid ?? '';

    // Staff must open their own dashboards — never the tourist /dashboard.
    final emailRole = SessionStorage.getRoleFromEmail(email);
    if (emailRole == UserRole.governor) {
      if (!mounted) return;
      Navigator.of(context).pushNamed('/governor-dashboard');
      return;
    }
    if (emailRole == UserRole.tourism) {
      if (!mounted) return;
      Navigator.of(context).pushNamed('/lgu-dashboard');
      return;
    }

    if (uid.isNotEmpty && email.isNotEmpty) {
      final route = await LoginFlowService.resolveRouteFast(
        uid: uid,
        email: email,
      );
      if (!mounted) return;
      if (route == '/governor-dashboard' ||
          route == '/lgu-dashboard' ||
          route == '/tourism-dashboard') {
        Navigator.of(context).pushNamed(route);
        return;
      }
      if (route == '/verify-otp') {
        Navigator.of(context).pushNamed(route);
        return;
      }
    } else {
      final storedRole = await SessionStorage.getStoredRole();
      if (!mounted) return;
      if (storedRole == UserRole.governor) {
        Navigator.of(context).pushNamed('/governor-dashboard');
        return;
      }
      if (storedRole == UserRole.tourism) {
        Navigator.of(context).pushNamed('/lgu-dashboard');
        return;
      }
    }

    if (!mounted) return;
    Navigator.of(context).pushNamed(
      '/dashboard',
      arguments: <String, dynamic>{'initialIndex': initialIndex},
    );
  }

  void _onExperienceCardTap(int index) {
    if (_qrWelcomeMessage != null) {
      // Post-signup from QR: VR Tour | Trip Planner | Continue on website
      switch (index) {
        case 0:
          _openVrTourFromLanding();
        case 1:
          _openPlanItinerary();
        case 2:
          _openUserApp();
      }
      return;
    }
    switch (index) {
      case 0:
        _openVrTourFromLanding();
      case 1:
        _openPlanItinerary();
      case 2:
        _openUserApp(initialIndex: 2);
    }
  }

  Widget _buildLoggedInHeroActions() {
    return Wrap(
      spacing: 12,
      runSpacing: 12,
      alignment: _isMobile ? WrapAlignment.center : WrapAlignment.start,
      children: [
        FilledButton.icon(
          onPressed: _openVrTourFromLanding,
          style: FilledButton.styleFrom(
            backgroundColor: _primaryOrange,
            foregroundColor: Colors.white,
            padding: EdgeInsets.symmetric(
              horizontal: _isMobile ? 18 : 24,
              vertical: _isMobile ? 14 : 16,
            ),
            elevation: 6,
            shadowColor: _primaryOrange.withValues(alpha: 0.5),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
          ),
          icon: const Icon(Icons.vrpano_rounded, size: 20),
          label: Text(
            _landingVrButtonLabel,
            style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
          ),
        ),
        OutlinedButton.icon(
          onPressed: _openPlanItinerary,
          style: OutlinedButton.styleFrom(
            foregroundColor: Colors.white,
            side: BorderSide(color: Colors.white.withValues(alpha: 0.45)),
            padding: EdgeInsets.symmetric(
              horizontal: _isMobile ? 18 : 24,
              vertical: _isMobile ? 14 : 16,
            ),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
          ),
          icon: const Icon(Icons.map_rounded, size: 20),
          label: const Text(
            'Plan itinerary',
            style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
          ),
        ),
        OutlinedButton.icon(
          onPressed: () => _openUserApp(),
          style: OutlinedButton.styleFrom(
            foregroundColor: Colors.white,
            side: BorderSide(color: Colors.white.withValues(alpha: 0.45)),
            padding: EdgeInsets.symmetric(
              horizontal: _isMobile ? 18 : 24,
              vertical: _isMobile ? 14 : 16,
            ),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
          ),
          icon: const Icon(Icons.dashboard_rounded, size: 20),
          label: Text(
            _isMobile ? 'Open app' : 'Open dashboard',
            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
          ),
        ),
      ],
    );
  }

  Widget _buildHeroSearchBarLight() {
    final query = _heroSearchController.text.trim();
    final showSuggestions = _heroSearchSuggestionsOpen;
    final suggestions = showSuggestions
        ? _filteredDestinations.take(6).toList()
        : const <Map<String, String>>[];

    const searchBarHeight = 54.0;
    final screenWidth = MediaQuery.sizeOf(context).width;
    final barWidth = _isMobile
        ? (screenWidth - 40).clamp(280.0, double.infinity)
        : 520.0;

    return SizedBox(
      width: barWidth,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Container(
            height: searchBarHeight,
            padding: const EdgeInsets.fromLTRB(18, 4, 6, 4),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(32),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.18),
                  blurRadius: 22,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: Row(
              children: [
                Icon(
                  Icons.search_rounded,
                  color: Colors.grey.shade500,
                  size: 22,
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
                        cursorColor: _primaryOrange,
                        style: const TextStyle(
                          color: Color(0xFF1F2937),
                          fontSize: 15,
                          fontWeight: FontWeight.w500,
                        ),
                        textInputAction: TextInputAction.search,
                        decoration: InputDecoration(
                          filled: true,
                          fillColor: Colors.transparent,
                          hintText: 'Search municipalities & destinations...',
                          hintStyle: TextStyle(
                            color: Colors.grey.shade500,
                            fontSize: 14,
                          ),
                          border: InputBorder.none,
                          enabledBorder: InputBorder.none,
                          focusedBorder: InputBorder.none,
                          disabledBorder: InputBorder.none,
                          isDense: true,
                          contentPadding: const EdgeInsets.symmetric(
                            vertical: 14,
                          ),
                        ),
                        onSubmitted: _submitHeroSearch,
                      ),
                    ),
                  ),
                ),
                if (query.isNotEmpty)
                  IconButton(
                    onPressed: _clearHeroSearch,
                    icon: Icon(
                      Icons.close_rounded,
                      size: 20,
                      color: Colors.grey.shade600,
                    ),
                    tooltip: 'Clear search',
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(
                      minWidth: 32,
                      minHeight: 32,
                    ),
                  ),
                Material(
                  color: _primaryOrange,
                  shape: const CircleBorder(),
                  child: InkWell(
                    customBorder: const CircleBorder(),
                    onTap: () => _submitHeroSearch(_heroSearchController.text),
                    child: const SizedBox(
                      width: 42,
                      height: 42,
                      child: Icon(
                        Icons.search_rounded,
                        color: Colors.white,
                        size: 22,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (showSuggestions)
            Positioned(
              top: searchBarHeight + 8,
              left: 0,
              right: 0,
              child: _buildHeroSearchSuggestions(suggestions, query: query),
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
      return Material(
        color: Colors.white,
        elevation: 24,
        shadowColor: Colors.black.withValues(alpha: 0.4),
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: Colors.grey.shade200),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Text(
            'No matches for "$query". Try a city, municipality, or place like AMORAP.',
            style: TextStyle(
              color: Colors.grey.shade800,
              fontSize: 13,
              height: 1.4,
            ),
          ),
        ),
      );
    }

    return Material(
      color: Colors.white,
      elevation: 24,
      shadowColor: Colors.black.withValues(alpha: 0.4),
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: Colors.grey.shade200),
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
            return Material(
              color: Colors.white,
              child: InkWell(
                onTap: () => _selectDestinationFromSearch(item),
                hoverColor: Colors.grey.shade100,
                splashColor: _primaryOrange.withValues(alpha: 0.08),
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
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildRegisterCalloutSection() {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.symmetric(
        horizontal: _sectionOuterPadding,
        vertical: _isMobile ? 24 : 32,
      ),
      color: _pageBackground,
      child: _wrapSectionContent(
        Container(
          padding: EdgeInsets.all(_isMobile ? 20 : 28),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Color(0xFFFFF7ED),
                Color(0xFFFFFFFF),
                Color(0xFFFFF7ED),
              ],
            ),
            borderRadius: BorderRadius.circular(_cardRadius),
            border: Border.all(color: _primaryOrange.withValues(alpha: 0.28)),
            boxShadow: [
              BoxShadow(
                color: _primaryOrange.withValues(alpha: 0.08),
                blurRadius: 18,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: _isMobile
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _registerCalloutCopy(titleSize: 22),
                    const SizedBox(height: 20),
                    _registerCalloutButton(),
                  ],
                )
              : Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Expanded(child: _registerCalloutCopy(titleSize: 26)),
                    const SizedBox(width: 24),
                    _registerCalloutButton(compact: false),
                  ],
                ),
        ),
      ),
    );
  }

  Widget _registerCalloutCopy({required double titleSize}) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _landingIconTile(Icons.celebration_rounded, size: 52),
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
                'Create your ATMOS-TRS account in minutes — digital tourist ID, '
                'QR check-ins, VR previews, and itinerary tools in one place.',
                style: _sectionBodyStyle.copyWith(fontSize: _isMobile ? 14 : 15),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _registerCalloutButton({bool compact = true}) {
    return FilledButton.icon(
      onPressed: _navigateToSignup,
      style: FilledButton.styleFrom(
        backgroundColor: _primaryOrange,
        foregroundColor: Colors.white,
        elevation: 0,
        padding: EdgeInsets.symmetric(
          horizontal: compact ? 22 : 28,
          vertical: compact ? 14 : 16,
        ),
        minimumSize: Size(compact ? 0 : 180, 48),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(999),
        ),
      ),
      icon: const Icon(Icons.person_add_alt_1_rounded, size: 20),
      label: Text(
        compact ? 'Register now — free' : 'Register now',
        style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
      ),
    );
  }

  Widget _buildChooseYourExperienceSection({bool viewport = false}) {
    final fromQrSignup = _qrWelcomeMessage != null;
    final List<Map<String, dynamic>> experienceCards = fromQrSignup
        ? [
            {
              'title': 'VR Tour',
              'subtitle': VrDownloadAppPrompt.blocksVrOnWeb
                  ? 'Unlocks on phone — get the ATMOS app'
                  : 'Explore destinations in immersive 360° preview',
              'icon': Icons.vrpano_rounded,
            },
            {
              'title': 'Trip Planner',
              'subtitle': 'Build and organize your travel itinerary',
              'icon': Icons.map_rounded,
            },
            {
              'title': kIsWeb ? 'Continue on website' : 'Continue in the app',
              'subtitle': kIsWeb
                  ? 'Browse destinations in your browser'
                  : 'Open your tourist dashboard and Digital Tourist ID',
              'icon':
                  kIsWeb ? Icons.language_rounded : Icons.dashboard_rounded,
            },
          ]
        : [
            {
              'title': 'VR Tour',
              'subtitle': VrDownloadAppPrompt.blocksVrOnWeb
                  ? 'Get the ATMOS app to explore in immersive 360°'
                  : 'Explore destinations in immersive 360° preview',
              'icon': Icons.vrpano_rounded,
            },
            {
              'title': 'Trip Planner',
              'subtitle': 'Plan and organize your travel itinerary',
              'icon': Icons.map_rounded,
            },
            {
              'title': 'QR Check-in',
              'subtitle': 'Scan QR codes and record visits',
              'icon': Icons.qr_code_scanner_rounded,
            },
          ];

    return Container(
      padding: EdgeInsets.symmetric(
        vertical: _sectionInnerVertical(viewport: viewport),
      ),
      color: viewport ? Colors.transparent : _pageBackground,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildSectionHeader(
            fromQrSignup ? 'What would you like to do?' : 'Choose Your Experience',
            fromQrSignup
                ? 'VR Tour and Trip Planner — continue on the website or get the ATMOS app'
                : 'One platform — explore, plan, and check in across Misamis Occidental',
            icon: Icons.explore_rounded,
            badge: fromQrSignup
                ? 'VR · Trip Planner · Website / App'
                : 'VR · Itinerary · Check-in',
          ),
          if (_qrWelcomeMessage != null) ...[
            SizedBox(height: viewport ? 16 : (_isMobile ? 20 : 24)),
            _buildQrRegistrationWelcomeBanner(),
          ],
          SizedBox(height: viewport ? 16 : (_isMobile ? 24 : 32)),
          _isMobile
              ? Column(
                  children: [
                    for (var i = 0; i < experienceCards.length; i++)
                      Padding(
                        padding: EdgeInsets.only(top: i == 0 ? 0 : 12),
                        child: _buildExperienceCard(
                          index: i,
                          title: experienceCards[i]['title'] as String,
                          subtitle: experienceCards[i]['subtitle'] as String,
                          icon: experienceCards[i]['icon'] as IconData,
                        ),
                      ),
                  ],
                )
              : Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (var i = 0; i < experienceCards.length; i++) ...[
                      if (i > 0) const SizedBox(width: 16),
                      Expanded(
                        child: _buildExperienceCard(
                          index: i,
                          title: experienceCards[i]['title'] as String,
                          subtitle: experienceCards[i]['subtitle'] as String,
                          icon: experienceCards[i]['icon'] as IconData,
                          expanded: true,
                        ),
                      ),
                    ],
                  ],
                ),
        ],
      ),
    );
  }

  Widget _buildQrRegistrationWelcomeBanner() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color(0xFFFFF7ED),
            Color(0xFFFFFFFF),
          ],
        ),
        borderRadius: BorderRadius.circular(_cardRadius),
        border: Border.all(color: _primaryOrange.withValues(alpha: 0.35)),
        boxShadow: [
          BoxShadow(
            color: _primaryOrange.withValues(alpha: 0.08),
            blurRadius: 14,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _landingIconTile(Icons.celebration_rounded, size: 44),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'You\'re all set!',
                  style: _cardTitleStyle.copyWith(color: _darkBg),
                ),
                const SizedBox(height: 6),
                Text(
                  _qrWelcomeMessage!,
                  style: _cardSubtitleStyle,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildExperienceCard({
    required int index,
    required String title,
    required String subtitle,
    required IconData icon,
    bool expanded = false,
  }) {
    final isHovered = _hoveredExperienceIndex == index;
    final isHighlighted = _highlightExperienceSection;

    return MouseRegion(
      onEnter: (_) => setState(() => _hoveredExperienceIndex = index),
      onExit: (_) => setState(() => _hoveredExperienceIndex = null),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: () => _onExperienceCardTap(index),
        child: AnimatedContainer(
          duration: _motionDuration,
          curve: Curves.easeOutCubic,
          transform: Matrix4.identity()
            ..translateByDouble(0, isHovered ? -4.0 : 0.0, 0, 1),
          constraints: expanded
              ? const BoxConstraints(minHeight: 168)
              : const BoxConstraints(),
          width: expanded ? double.infinity : null,
          padding: EdgeInsets.all(expanded ? 22 : 18),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(_cardRadius),
            border: Border.all(
              color: isHighlighted || isHovered
                  ? _primaryOrange.withValues(alpha: 0.45)
                  : const Color(0xFFE8ECF1),
              width: isHighlighted || isHovered ? 1.5 : 1,
            ),
            boxShadow: [
              BoxShadow(
                color: isHovered
                    ? _primaryOrange.withValues(alpha: 0.14)
                    : Colors.black.withValues(alpha: 0.05),
                blurRadius: isHovered ? 22 : 12,
                offset: Offset(0, isHovered ? 8 : 4),
              ),
            ],
          ),
          child: expanded
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        _landingIconTile(icon, size: 52),
                        const Spacer(),
                        Icon(
                          Icons.arrow_forward_rounded,
                          color: _primaryOrange.withValues(alpha: 0.9),
                          size: 22,
                        ),
                      ],
                    ),
                    const SizedBox(height: 18),
                    Text(
                      title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: _cardTitleStyle.copyWith(fontSize: 18),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      subtitle,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: _cardSubtitleStyle.copyWith(fontSize: 14),
                    ),
                  ],
                )
              : Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _landingIconTile(icon, size: 48),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            title,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: _cardTitleStyle,
                          ),
                          const SizedBox(height: 6),
                          Text(
                            subtitle,
                            maxLines: 3,
                            overflow: TextOverflow.ellipsis,
                            style: _cardSubtitleStyle.copyWith(fontSize: 14),
                          ),
                        ],
                      ),
                    ),
                    Icon(
                      Icons.arrow_forward_rounded,
                      color: _primaryOrange.withValues(alpha: 0.85),
                      size: 20,
                    ),
                  ],
                ),
        ),
      ),
    );
  }

  Widget _buildFeaturesSection({bool viewport = false}) {
    return Container(
      padding: EdgeInsets.symmetric(
        vertical: _sectionInnerVertical(viewport: viewport),
      ),
      color: viewport ? Colors.transparent : _pageSurfaceMuted,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildSectionHeader(
            'Why Choose ATMOS-TRS?',
            'Smart registration, VR tours, itinerary planning & QR check-ins — all in one platform',
            icon: Icons.auto_awesome_rounded,
            badge: 'Official provincial platform',
          ),
          SizedBox(height: viewport ? 16 : (_isMobile ? 24 : 32)),
          LayoutBuilder(
            builder: (context, constraints) {
              final columns = _isMobile
                  ? 1
                  : constraints.maxWidth >= 1100
                  ? 3
                  : 2;
              const spacing = 16.0;
              final cardWidth = columns == 1
                  ? constraints.maxWidth
                  : (constraints.maxWidth - spacing * (columns - 1)) /
                      columns;
              return Wrap(
                spacing: spacing,
                runSpacing: spacing,
                children: [
                  for (var i = 0; i < _features.length; i++)
                    SizedBox(
                      width: cardWidth,
                      child: _buildFeatureCard(
                        i,
                        _features[i],
                        compact: _isMobile,
                      ),
                    ),
                ],
              );
            },
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
    return Column(
      children: [
        Container(
          width: 44,
          height: 4,
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [_primaryOrange, _brandDark],
            ),
            borderRadius: BorderRadius.circular(4),
          ),
        ),
        const SizedBox(height: 16),
        if (badge != null) ...[
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: _primaryOrange.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(999),
              border: Border.all(
                color: _primaryOrange.withValues(alpha: 0.22),
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (icon != null) ...[
                  Icon(icon, size: 14, color: _primaryOrange),
                  const SizedBox(width: 6),
                ],
                Text(
                  badge.toUpperCase(),
                  style: const TextStyle(
                    color: _primaryOrange,
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.1,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
        ],
        Text(
          title,
          textAlign: TextAlign.center,
          style: TextStyle(
            color: _darkBg,
            fontSize: _sectionTitleFontSize,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.4,
            height: 1.15,
          ),
        ),
        const SizedBox(height: 12),
        ConstrainedBox(
          constraints: BoxConstraints(maxWidth: _sectionSubtitleMaxWidth),
          child: Text(
            subtitle,
            textAlign: TextAlign.center,
            style: _sectionBodyStyle.copyWith(
              fontSize: _sectionSubtitleFontSize,
              fontWeight: FontWeight.w500,
              color: const Color(0xFF64748B),
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
    final accent = feature['accent'] as Color? ?? _primaryOrange;
    final isHovered = _hoveredFeatureIndex == index;
    final String? route = feature['route'] as String?;

    if (compact) {
      Widget card = MouseRegion(
        onEnter: (_) => setState(() => _hoveredFeatureIndex = index),
        onExit: (_) => setState(() => _hoveredFeatureIndex = null),
        cursor: route != null ? SystemMouseCursors.click : SystemMouseCursors.basic,
        child: AnimatedContainer(
          duration: _motionDuration,
          curve: Curves.easeOutCubic,
          transform: Matrix4.identity()
            ..translateByDouble(0, isHovered ? -3.0 : 0.0, 0, 1),
          padding: const EdgeInsets.all(20),
          decoration: _surfaceCardDecoration(
            hovered: isHovered,
            accent: accent,
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _landingIconTile(
                feature['icon'] as IconData,
                accent: accent,
                size: 44,
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      feature['title'] as String,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: _cardTitleStyle.copyWith(fontSize: 16),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      feature['description'] as String,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: _cardSubtitleStyle.copyWith(fontSize: 14),
                    ),
                  ],
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
      child: AnimatedContainer(
        duration: _motionDuration,
        curve: Curves.easeOutCubic,
        transform: Matrix4.identity()
          ..translateByDouble(0, isHovered ? -4.0 : 0.0, 0, 1),
        padding: const EdgeInsets.fromLTRB(20, 22, 20, 20),
        decoration: _surfaceCardDecoration(
          hovered: isHovered,
          accent: accent,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            _landingIconTile(
              feature['icon'] as IconData,
              accent: accent,
              size: 48,
            ),
            const SizedBox(height: 16),
            Text(
              feature['title'] as String,
              textAlign: TextAlign.left,
              style: _cardTitleStyle,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 8),
            Text(
              feature['description'] as String,
              textAlign: TextAlign.left,
              style: _cardSubtitleStyle.copyWith(fontSize: 14),
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
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

  Widget _buildDestinationsSection({bool viewport = false}) {
    final query = _heroSearchController.text.trim();
    final filtered = _filteredDestinations;
    final isFiltering = query.isNotEmpty;
    final matchLabel = filtered.length == 1 ? 'match' : 'matches';

    return Container(
      padding: EdgeInsets.symmetric(
        vertical: _sectionInnerVertical(viewport: viewport),
      ),
      color: viewport ? Colors.transparent : _pageBackground,
      child: Column(
        mainAxisSize: MainAxisSize.min,
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
            const SizedBox(height: 16),
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
          SizedBox(height: viewport ? 16 : (_isMobile ? 24 : 32)),
          if (filtered.isEmpty)
            _buildDestinationsEmptyState(query)
          else if (_isMobile)
            Column(
              children: [
                for (var i = 0; i < filtered.length; i++)
                  Padding(
                    padding: EdgeInsets.only(top: i == 0 ? 0 : 12),
                    child: _buildDestinationCard(
                      filtered[i],
                      compact: true,
                      cardIndex: i,
                    ),
                  ),
              ],
            )
          else
            LayoutBuilder(
              builder: (context, constraints) {
                final columns = constraints.maxWidth >= 1280
                    ? 4
                    : constraints.maxWidth >= 960
                    ? 3
                    : 2;
                const spacing = 16.0;
                final cardWidth =
                    (constraints.maxWidth - spacing * (columns - 1)) /
                    columns;
                return Wrap(
                  spacing: spacing,
                  runSpacing: spacing,
                  children: [
                    for (var i = 0; i < filtered.length; i++)
                      SizedBox(
                        width: cardWidth,
                        child: _buildDestinationCard(
                          filtered[i],
                          compact: true,
                          cardIndex: i,
                        ),
                      ),
                  ],
                );
              },
            ),
        ],
      ),
    );
  }

  Widget _buildDestinationsEmptyState(String query) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 48),
      decoration: _surfaceCardDecoration(),
      child: Column(
        children: [
          _landingIconTile(Icons.search_off_rounded, size: 56),
          const SizedBox(height: 16),
          Text(
            'No destinations match "$query"',
            textAlign: TextAlign.center,
            style: _cardTitleStyle,
          ),
          const SizedBox(height: 8),
          Text(
            'Try a municipality name (e.g. Sinacaban, Ozamiz), a landmark (AMORAP, Global Garden), or a category like beach or falls.',
            textAlign: TextAlign.center,
            style: _cardSubtitleStyle,
          ),
          const SizedBox(height: 24),
          OutlinedButton.icon(
            onPressed: _clearHeroSearch,
            icon: const Icon(Icons.refresh_rounded, size: 18),
            label: const Text('Show all 17 locations'),
            style: OutlinedButton.styleFrom(
              foregroundColor: _primaryOrange,
              side: const BorderSide(color: _primaryOrange, width: 1.5),
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(999),
              ),
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
                            _openVrTourFromLanding(municipalityName: name);
                          },
                          icon: const Icon(Icons.vrpano_rounded, size: 20),
                          label: Text(_landingVrButtonLabel),
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
                            _openPlanItinerary(municipalityName: name);
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
    return SpotImage(
      imageUrl: imageUrl,
      fit: fit,
    );
  }

  Widget _destinationCategoryBadge(String category, {bool onImage = false}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: onImage
            ? Colors.black.withValues(alpha: 0.55)
            : _primaryOrange.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(999),
        border: onImage
            ? null
            : Border.all(color: _primaryOrange.withValues(alpha: 0.22)),
      ),
      child: Text(
        category,
        style: TextStyle(
          color: onImage ? Colors.white : _primaryOrange,
          fontSize: 11,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.2,
        ),
      ),
    );
  }

  Widget _buildDestinationCard(
    Map<String, String> destination, {
    bool compact = false,
    int cardIndex = 0,
  }) {
    final imageUrl = destination['image']!;
    final name = destination['name'] ?? '';
    final category = destination['category'] ?? 'Municipality';
    final description = destination['description'] ?? '';
    final isHovered = _hoveredDestinationName == name;
    final municipalityId = destination['municipalityId'];
    final showPhoto =
        _heavyImagesEnabled && cardIndex < _destinationImageBudget;

    Widget spotImage({required double height}) {
      if (!showPhoto) {
        return ColoredBox(
          color: const Color(0xFFE2E8F0),
          child: Center(
            child: SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(
                strokeWidth: 2.2,
                color: _primaryOrange.withValues(alpha: 0.7),
              ),
            ),
          ),
        );
      }
      return SpotImage(
        imageUrl: imageUrl,
        municipalityId: municipalityId,
        spotName: name,
        category: category,
        height: height,
        fit: BoxFit.cover,
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
            onTap: () {
              _enableHeavyImages(budget: _destinations.length);
              _showDestinationExploreSheet(destination);
            },
            borderRadius: BorderRadius.circular(_cardRadius),
            child: AnimatedContainer(
              duration: _motionDuration,
              curve: Curves.easeOutCubic,
              transform: Matrix4.identity()
                ..translateByDouble(0, isHovered ? -3.0 : 0.0, 0, 1),
              decoration: _surfaceCardDecoration(hovered: isHovered),
              clipBehavior: Clip.antiAlias,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SizedBox(
                    height: _destinationCardImageHeight,
                    width: double.infinity,
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        spotImage(height: _destinationCardImageHeight),
                        Positioned(
                          left: 0,
                          right: 0,
                          bottom: 0,
                          child: Container(
                            height: 48,
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.topCenter,
                                end: Alignment.bottomCenter,
                                colors: [
                                  Colors.transparent,
                                  Colors.black.withValues(alpha: 0.45),
                                ],
                              ),
                            ),
                          ),
                        ),
                        Positioned(
                          top: 10,
                          left: 10,
                          child: _destinationCategoryBadge(
                            category,
                            onImage: true,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: _cardTitleStyle,
                        ),
                        const SizedBox(height: 6),
                        Text(
                          description,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: _cardSubtitleStyle.copyWith(fontSize: 14),
                        ),
                        const SizedBox(height: 14),
                        Row(
                          children: [
                            Expanded(
                              child: _buildDestinationQuickAction(
                                label: _landingVrQuickActionLabel,
                                icon: Icons.vrpano_rounded,
                                color: _primaryOrange,
                                onTap: () =>
                                    _openVrTourFromLanding(municipalityName: name),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: _buildDestinationQuickAction(
                                label: 'Itinerary',
                                icon: Icons.map_rounded,
                                color: _primaryOrange,
                                onTap: () =>
                                    _openPlanItinerary(municipalityName: name),
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

    return MouseRegion(
      onEnter: (_) => setState(() => _hoveredDestinationName = name),
      onExit: (_) => setState(() => _hoveredDestinationName = null),
      cursor: SystemMouseCursors.click,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => _showDestinationExploreSheet(destination),
          borderRadius: BorderRadius.circular(_cardRadius),
          child: AnimatedContainer(
            duration: _motionDuration,
            curve: Curves.easeOutCubic,
            transform: Matrix4.identity()
              ..translateByDouble(0, isHovered ? -4.0 : 0.0, 0, 1),
            decoration: _surfaceCardDecoration(hovered: isHovered),
            clipBehavior: Clip.antiAlias,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SizedBox(
                  height: 180,
                  width: double.infinity,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      spotImage(height: 180),
                      Positioned(
                        left: 0,
                        right: 0,
                        bottom: 0,
                        child: Container(
                          height: 56,
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [
                                Colors.transparent,
                                Colors.black.withValues(alpha: 0.45),
                              ],
                            ),
                          ),
                        ),
                      ),
                      Positioned(
                        top: 10,
                        left: 10,
                        child: _destinationCategoryBadge(
                          category,
                          onImage: true,
                        ),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        name,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: _cardTitleStyle,
                      ),
                      const SizedBox(height: 6),
                      Text(
                        description.isEmpty
                            ? 'Tap for VR & itinerary'
                            : description,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: _cardSubtitleStyle.copyWith(fontSize: 14),
                      ),
                      const SizedBox(height: 14),
                      Row(
                        children: [
                          Expanded(
                            child: _buildDestinationQuickAction(
                              label: _landingVrQuickActionLabel,
                              icon: Icons.vrpano_rounded,
                              color: _primaryOrange,
                              onTap: () => _openVrTourFromLanding(
                                municipalityName: name,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: _buildDestinationQuickAction(
                              label: 'Itinerary',
                              icon: Icons.map_rounded,
                              color: _primaryOrange,
                              onTap: () =>
                                  _openPlanItinerary(municipalityName: name),
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

  Widget _buildDestinationQuickAction({
    required String label,
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: Ink(
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: color.withValues(alpha: 0.35)),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 9, horizontal: 6),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, size: 15, color: color),
                const SizedBox(width: 4),
                Flexible(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: color,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
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

  Widget _buildHowItWorksSection({bool viewport = false}) {
    final stepEntries = _steps.asMap().entries.toList();
    return Container(
      padding: EdgeInsets.symmetric(
        vertical: _sectionInnerVertical(viewport: viewport),
      ),
      color: viewport ? Colors.transparent : _pageSurfaceMuted,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildSectionHeader(
            'How It Works',
            'Get started with ATMOS-TRS in 5 simple steps',
            icon: Icons.route_rounded,
            badge: '5 easy steps',
          ),
          SizedBox(height: viewport ? 16 : (_isMobile ? 24 : 32)),
          _isMobile
              ? Column(
                  children: [
                    for (var i = 0; i < stepEntries.length; i++) ...[
                      if (i > 0) _buildMobileStepConnector(),
                      _buildStepCard(stepEntries[i].value, compact: true),
                    ],
                  ],
                )
              : LayoutBuilder(
                  builder: (context, constraints) {
                    final cardsInRow = constraints.maxWidth >= 1320
                        ? 5
                        : constraints.maxWidth >= 1080
                        ? 4
                        : 3;
                    const gap = 16.0;
                    final cardWidth =
                        (constraints.maxWidth - (gap * (cardsInRow - 1))) /
                        cardsInRow;

                    return Wrap(
                      spacing: gap,
                      runSpacing: gap,
                      alignment: WrapAlignment.center,
                      children: [
                        for (final step in stepEntries)
                          SizedBox(
                            width: cardWidth.clamp(200.0, 260.0),
                            child: _buildStepCard(
                              step.value,
                              compact: false,
                            ),
                          ),
                      ],
                    );
                  },
                ),
        ],
      ),
    );
  }

  Widget _buildMobileStepConnector() {
    return Padding(
      padding: const EdgeInsets.only(left: 28, top: 4, bottom: 4),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Container(
          width: 2,
          height: 20,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(1),
            color: _primaryOrange.withValues(alpha: 0.25),
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
                  _primaryOrange.withValues(alpha: 0.26),
                  _primaryOrange.withValues(alpha: 0.08),
                ],
              ),
            ),
          ),
          const SizedBox(width: 2),
          Icon(
            Icons.chevron_right_rounded,
            color: _primaryOrange.withValues(alpha: 0.5),
            size: 14,
          ),
        ],
      ),
    );
  }

  Widget _buildStepCard(
    Map<String, dynamic> step, {
    bool compact = false,
  }) {
    final number = step['number'] as String;
    final title = step['title'] as String;
    final description = step['description'] as String;
    final icon = step['icon'] as IconData;

    if (compact) {
      return Container(
        padding: const EdgeInsets.all(20),
        decoration: _surfaceCardDecoration(),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Column(
              children: [
                Stack(
                  clipBehavior: Clip.none,
                  children: [
                    _landingIconTile(icon, size: 48),
                    Positioned(
                      right: -4,
                      top: -4,
                      child: Container(
                        width: 22,
                        height: 22,
                        decoration: BoxDecoration(
                          color: Colors.white,
                          shape: BoxShape.circle,
                          border: Border.all(color: _primaryOrange, width: 1.5),
                        ),
                        alignment: Alignment.center,
                        child: Text(
                          number,
                          style: const TextStyle(
                            color: _primaryOrange,
                            fontSize: 10,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: _cardTitleStyle.copyWith(fontSize: 16),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    description,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: _cardSubtitleStyle.copyWith(fontSize: 14),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 22),
      decoration: _surfaceCardDecoration(),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Stack(
            clipBehavior: Clip.none,
            children: [
              _landingIconTile(icon, size: 52),
              Positioned(
                right: -6,
                top: -6,
                child: Container(
                  width: 24,
                  height: 24,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [_primaryOrange, _brandDark],
                    ),
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 2),
                    boxShadow: [
                      BoxShadow(
                        color: _primaryOrange.withValues(alpha: 0.35),
                        blurRadius: 6,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    number,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            title,
            textAlign: TextAlign.center,
            style: _cardTitleStyle.copyWith(fontSize: 15),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 8),
          Text(
            description,
            textAlign: TextAlign.center,
            style: _cardSubtitleStyle.copyWith(fontSize: 13),
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  Widget _buildStatCard(Map<String, dynamic> stat) {
    final accent = stat['accent'] as Color? ?? _primaryOrange;

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: _surfaceCardDecoration(accent: accent),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _landingIconTile(stat['icon'] as IconData, accent: accent, size: 44),
              const Spacer(),
            ],
          ),
          const SizedBox(height: 16),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              stat['value'] as String,
              maxLines: 1,
              style: TextStyle(
                color: _darkBg,
                fontSize: _isMobile ? 28 : 32,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.5,
                height: 1.0,
              ),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            stat['label'] as String,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: _cardSubtitleStyle.copyWith(
              fontSize: 14,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatisticsSection({bool viewport = false}) {
    final stats = [
      {
        'value': '10,000+',
        'label': 'Registered Tourists',
        'icon': Icons.people_rounded,
        'accent': _primaryOrange,
      },
      {
        'value': '15-25',
        'label': 'Tourist Spots',
        'icon': Icons.place_rounded,
        'accent': _primaryOrange,
      },
      {
        'value': '17',
        'label': 'Cities & Municipalities',
        'icon': Icons.location_city_rounded,
        'accent': _primaryOrange,
      },
      {
        'value': '7',
        'label': 'VR Tours',
        'icon': Icons.vrpano_rounded,
        'accent': _primaryOrange,
      },
    ];

    return Container(
      padding: EdgeInsets.symmetric(
        vertical: _sectionInnerVertical(viewport: viewport),
      ),
      color: viewport ? Colors.transparent : _pageSurfaceMuted,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildSectionHeader(
            'By the numbers',
            'Growing smart tourism across Misamis Occidental',
            icon: Icons.insights_rounded,
            badge: 'Impact',
          ),
          SizedBox(height: _isMobile ? 24 : 32),
          _isMobile
              ? Column(
                  children: [
                    for (var i = 0; i < stats.length; i++)
                      Padding(
                        padding: EdgeInsets.only(top: i == 0 ? 0 : 12),
                        child: _buildStatCard(stats[i]),
                      ),
                  ],
                )
              : _isTablet
              ? Column(
                  children: [
                    for (var row = 0; row < stats.length; row += 2)
                      Padding(
                        padding: EdgeInsets.only(top: row == 0 ? 0 : 16),
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

  Widget _buildProvincialTourismOfficeCard({required double height}) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(_cardRadius),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(_cardRadius),
        child: Container(
          height: height,
          decoration: BoxDecoration(
            border: Border.all(color: const Color(0xFFE8ECF1)),
          ),
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (_heavyImagesEnabled)
                SpotImage(
                  imageUrl: _kCapitolAsset,
                  fit: BoxFit.cover,
                  height: height,
                )
              else
                ColoredBox(
                  color: const Color(0xFFE2E8F0),
                  child: Center(
                    child: Icon(
                      Icons.account_balance_rounded,
                      size: 48,
                      color: _primaryOrange.withValues(alpha: 0.45),
                    ),
                  ),
                ),
              Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.black.withValues(alpha: 0.08),
                      Colors.black.withValues(alpha: 0.78),
                    ],
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.end,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 5,
                      ),
                      decoration: BoxDecoration(
                        color: _primaryOrange.withValues(alpha: 0.92),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: const Text(
                        'OFFICIAL PARTNER',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.8,
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Provincial Tourism Office',
                      style: _cardTitleStyle.copyWith(
                        fontSize: 18,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Misamis Occidental',
                      style: _cardSubtitleStyle.copyWith(
                        fontSize: 15,
                        color: Colors.white.withValues(alpha: 0.88),
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

  Widget _buildAboutSection({bool viewport = false}) {
    return Container(
      padding: EdgeInsets.symmetric(
        vertical: _sectionInnerVertical(viewport: viewport),
      ),
      color: viewport ? Colors.transparent : _pageBackground,
      child: _isMobile
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildAboutSectionCopy(),
                const SizedBox(height: 32),
                _buildProvincialTourismOfficeCard(height: 280),
              ],
            )
          : Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: _buildAboutSectionCopy()),
                const SizedBox(width: 48),
                Expanded(
                  child: _buildProvincialTourismOfficeCard(height: 400),
                ),
              ],
            ),
    );
  }

  Widget _buildAboutSectionCopy() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 44,
          height: 4,
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [_primaryOrange, _brandDark],
            ),
            borderRadius: BorderRadius.circular(4),
          ),
        ),
        const SizedBox(height: 14),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: _primaryOrange.withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(
              color: _primaryOrange.withValues(alpha: 0.22),
            ),
          ),
          child: const Text(
            'ABOUT ATMOS-TRS',
            style: TextStyle(
              color: _primaryOrange,
              fontSize: 11,
              fontWeight: FontWeight.w800,
              letterSpacing: 1.1,
            ),
          ),
        ),
        const SizedBox(height: 12),
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
          'ATMOS-TRS — $_kAppFullName — is the official digital platform for tourism in Misamis Occidental. '
          'We provide seamless tourist registration, VR previews of destinations, itinerary planning, and QR check-ins at spots.\n\n'
          'Our mission is to connect visitors with local communities and create a sustainable, smart tourism ecosystem across the province.',
          style: _sectionBodyStyle,
        ),
        const SizedBox(height: 28),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            _buildAboutFeature(Icons.verified_rounded, 'Official Partner'),
            _buildAboutFeature(Icons.security_rounded, 'Secure Platform'),
            _buildAboutFeature(Icons.support_agent_rounded, '24/7 Support'),
          ],
        ),
      ],
    );
  }

  Widget _buildAboutFeature(IconData icon, String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: _primaryOrange.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: _primaryOrange.withValues(alpha: 0.22)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: _primaryOrange, size: 18),
          const SizedBox(width: 8),
          Text(
            label,
            style: TextStyle(
              color: _darkBg,
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFooter() {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.symmetric(
        horizontal: _sectionOuterPadding,
        vertical: 48,
      ),
      decoration: const BoxDecoration(
        color: _darkBg,
        border: Border(
          top: BorderSide(color: _primaryOrange, width: 3),
        ),
      ),
      child: _wrapSectionContent(
        Column(
          children: [
            _isMobile
                ? Column(
                    children: [
                      _buildFooterMissionVision(),
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
                  top: BorderSide(color: Colors.white.withValues(alpha: 0.12)),
                ),
              ),
              child: _isMobile
                  ? Column(
                      children: [
                        Text(
                          '2026 © Province of Misamis Occidental',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.75),
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        const SizedBox(height: 16),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            _buildSocialIcon(Icons.facebook_rounded),
                            _buildSocialIcon(Icons.camera_alt_rounded),
                            _buildSocialIcon(Icons.email_rounded),
                          ],
                        ),
                      ],
                    )
                  : Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Text(
                            '2026 © Province of Misamis Occidental',
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.75),
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
            color: _primaryOrange,
            fontSize: 14,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.4,
          ),
        ),
        const SizedBox(height: 8),
        Align(
          alignment: _isMobile ? Alignment.center : Alignment.centerLeft,
          child: Container(
            width: 28,
            height: 3,
            decoration: BoxDecoration(
              color: _primaryOrange,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        ),
        const SizedBox(height: 10),
        Text(
          'To inspire and connect travelers by showcasing the wonders of every destination, '
          'fostering sustainable tourism, and creating meaningful experiences that enrich both '
          'the traveler and the local communities.',
          textAlign: _isMobile ? TextAlign.center : TextAlign.start,
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.78),
            fontSize: 14,
            height: 1.65,
            fontWeight: FontWeight.w400,
          ),
        ),
        const SizedBox(height: 28),
        Text(
          'Vision',
          style: TextStyle(
            color: _primaryOrange,
            fontSize: 14,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.4,
          ),
        ),
        const SizedBox(height: 8),
        Align(
          alignment: _isMobile ? Alignment.center : Alignment.centerLeft,
          child: Container(
            width: 28,
            height: 3,
            decoration: BoxDecoration(
              color: _primaryOrange,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        ),
        const SizedBox(height: 10),
        Text(
          'To become a leading platform for tourism, empowering travelers to explore the world '
          'with ease while promoting cultural appreciation, environmental responsibility, '
          'and economic growth in every destination.',
          textAlign: _isMobile ? TextAlign.center : TextAlign.start,
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.78),
            fontSize: 14,
            height: 1.65,
            fontWeight: FontWeight.w400,
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
        Text(
          'Quick Links',
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.95),
            fontSize: 15,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 8),
        Container(
          width: 28,
          height: 3,
          decoration: BoxDecoration(
            color: _primaryOrange,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(height: 16),
        ...links.map(
          (link) => Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Text(
              link,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.72),
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
        Text(
          'Contact Us',
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.95),
            fontSize: 15,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 8),
        Container(
          width: 28,
          height: 3,
          decoration: BoxDecoration(
            color: _primaryOrange,
            borderRadius: BorderRadius.circular(2),
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
              color: Colors.white.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
            ),
            alignment: Alignment.center,
            child: Icon(icon, color: _primaryOrange, size: 18),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                text,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.78),
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  height: 1.4,
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
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        color: _primaryOrange.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _primaryOrange.withValues(alpha: 0.35)),
      ),
      alignment: Alignment.center,
      child: Icon(icon, color: _primaryOrange, size: 20),
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

  Widget _buildImage() {
    return SpotImage(
      imageUrl: imageUrl,
      fit: BoxFit.contain,
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

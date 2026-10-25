import 'dart:async' show StreamSubscription, Timer, unawaited;
import 'dart:math' as math;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show debugPrint, kIsWeb;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderAbstractViewport;
import 'package:atmos_trs_system/data/app_faq_content.dart';
import 'package:atmos_trs_system/features/navigation/placeholder_pages.dart'
    show ScanTabPage;
import 'package:atmos_trs_system/navigation/landing_intent_navigation.dart';
import 'package:atmos_trs_system/navigation/login_route_args.dart';
import 'package:atmos_trs_system/navigation/role_router.dart';
import 'package:atmos_trs_system/navigation/trip_planner_access.dart';
import 'package:atmos_trs_system/data/landing_lgu_destinations.dart';
import 'package:atmos_trs_system/screens/municipality_map_and_spots_screen.dart';
import 'package:atmos_trs_system/widgets/atmos_square_logo.dart';
import 'package:atmos_trs_system/widgets/hero_video_branding_overlay.dart';
import 'package:atmos_trs_system/widgets/landing_about_section.dart';
import 'package:atmos_trs_system/widgets/landing_features_section.dart';
import 'package:atmos_trs_system/widgets/landing_how_it_works_section.dart';
import 'package:atmos_trs_system/widgets/hero_video_mute_control.dart';
import 'package:atmos_trs_system/widgets/onboarding_hero_video.dart';
import 'package:atmos_trs_system/config/app_store_links.dart';
import 'package:atmos_trs_system/config/atmos_brand_typography.dart';
import 'package:atmos_trs_system/config/session_storage.dart';
import 'package:atmos_trs_system/config/supabase_storage_config.dart';
import 'package:atmos_trs_system/services/landing_intent_service.dart';
import 'package:atmos_trs_system/data/misamis_occidental_municipalities.dart';
import 'package:atmos_trs_system/services/landing_public_stats_service.dart';
import 'package:atmos_trs_system/widgets/landing_hero_stats.dart';
import 'package:atmos_trs_system/services/user_directory_service.dart';
import 'package:atmos_trs_system/services/login_flow_service.dart';
import 'package:atmos_trs_system/screens/vr_webview_screen.dart';
import 'package:atmos_trs_system/widgets/vr_download_app_prompt.dart';
import 'package:atmos_trs_system/widgets/qr_camera_get_app_banner.dart';
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
  final GlobalKey _keyFaq = GlobalKey();

  /// Landing page always uses Asenso orange (not Settings theme color).
  static const Color _primaryOrange = Color(0xFFF97316);
  static const Color _brandLight = Color(0xFFFB923C);
  static const Color _brandDark = Color(0xFFEA580C);
  static const Color _darkBg = Color(0xFF192334);
  static const Color _accentOrange = Color(0xFFFB923C);

  /// Page shell: crisp white (avoids cream/peach page fills on sections that stay white).
  static const Color _pageBackground = Color(0xFFFFFFFF);
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

  User? _authUser = FirebaseAuth.instance.currentUser;
  StreamSubscription<User?>? _authSub;
  LandingPublicStats? _publicStats;
  int? _registeredTourists;
  bool _registeredTouristsLoading = true;
  bool _registeredTouristsFailed = false;
  bool _registeredTouristSeedStarted = false;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>?
      _registeredTouristSub;
  bool _heroStatsOpen = false;
  int? _touristSpots;
  int? _vrTours;
  bool _spotStatsLoading = true;
  bool _spotStatsFailed = false;
  StreamSubscription<LandingSpotCounts>? _spotStatsSub;

  Future<void> _loadPublicStats() async {
    final stats = await LandingPublicStatsService.load();
    if (mounted) {
      setState(() {
        _publicStats = stats;
        _touristSpots ??= stats.touristSpots;
        _vrTours ??= stats.vrTours;
        if (_spotStatsLoading &&
            stats.touristSpots != null &&
            stats.vrTours != null) {
          _spotStatsLoading = false;
          _spotStatsFailed = false;
        }
      });
    }
  }

  void _listenSpotCounts() {
    _spotStatsSub = LandingPublicStatsService.watchSpotCounts().listen(
      (counts) {
        if (!mounted) return;
        setState(() {
          _touristSpots = counts.touristSpots;
          _vrTours = counts.vrTours;
          _spotStatsLoading = false;
          _spotStatsFailed = false;
        });
      },
      onError: (Object error) {
        debugPrint('[LandingPublicStats] spot listener failed: $error');
        if (!mounted) return;
        setState(() {
          _spotStatsLoading = false;
          _spotStatsFailed = _touristSpots == null && _vrTours == null;
        });
      },
    );
  }

  void _listenRegisteredTourists() {
    _registeredTouristSub =
        LandingPublicStatsService.watchRegisteredTourists().listen(
      (snapshot) {
        final raw = snapshot.data()?['registeredTourists'];
        if (raw is num) {
          if (!mounted) return;
          setState(() {
            _registeredTourists = raw.toInt();
            _registeredTouristsLoading = false;
            _registeredTouristsFailed = false;
          });
          return;
        }
        unawaited(_seedRegisteredTourists());
      },
      onError: (Object error) {
        debugPrint('[LandingPublicStats] listener failed: $error');
        unawaited(_seedRegisteredTourists(fromError: true));
      },
    );
  }

  Future<void> _seedRegisteredTourists({bool fromError = false}) async {
    if (_registeredTouristSeedStarted) {
      if (fromError && _registeredTourists == null && mounted) {
        setState(() {
          _registeredTouristsLoading = false;
          _registeredTouristsFailed = true;
        });
      }
      return;
    }
    _registeredTouristSeedStarted = true;
    final count = await LandingPublicStatsService.ensureRegisteredTouristCount();
    if (!mounted) return;
    if (count != null) {
      setState(() {
        _registeredTourists = count;
        _registeredTouristsLoading = false;
        _registeredTouristsFailed = false;
      });
      return;
    }
    if (_registeredTourists == null) {
      setState(() {
        _registeredTouristsLoading = false;
        _registeredTouristsFailed = true;
      });
    }
  }

  String _formatStatCount(int? value) {
    if (value == null) return _publicStats == null ? '…' : '—';
    return value.toString().replaceAllMapped(
      RegExp(r'\B(?=(\d{3})+(?!\d))'),
      (_) => ',',
    );
  }

  @override
  void initState() {
    super.initState();
    _pageScrollController = ScrollController();
    // currentUser can still be the old account right after a dashboard logout
    // on web; follow auth events so header/hero actions update without restart.
    _authSub = FirebaseAuth.instance.authStateChanges().listen((user) {
      if (!mounted || user?.uid == _authUser?.uid) return;
      setState(() => _authUser = user);
    });

    _heroSearchController.addListener(_onHeroSearchTextChanged);
    _heroSearchFocusNode.addListener(_onHeroSearchFocusChanged);
    unawaited(_loadPublicStats());
    _listenRegisteredTourists();
    _listenSpotCounts();

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
            SupabaseStorageConfig.resolve('assets/images/landing page.png'),
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
    final welcomeText = welcome is String && welcome.trim().isNotEmpty
        ? welcome.trim()
        : null;

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
    return Navigator.of(context).pushNamed<T>(route, arguments: arguments).then(
      (result) {
        if (mounted) _resumeHeroVideoAfterAuthNavigation();
        return result;
      },
    );
  }

  void _navigateToLogin() {
    _pushAuthRoute('/login');
  }

  /// ATMOS-TRS login opens the role dashboard. A leftover VR intent must not
  /// turn this into an APK download.
  Future<void> _openAtmosLogin() async {
    await LandingIntentService.clear();
    if (!mounted) return;
    _navigateToLogin();
  }

  /// Header Log In: ATMOS TRS or Itinerary, then that product's login and dashboard.
  void _openHeaderLoginChoice() {
    showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return Dialog(
          backgroundColor: Colors.white,
          surfaceTintColor: Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(22),
          ),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(22, 22, 22, 16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'Log in',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.montserrat(
                      color: const Color(0xFF1B2433),
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Choose where to continue',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.montserrat(
                      color: const Color(0xFF64748B),
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 18),
                  _headerLoginChoiceTile(
                    icon: Icons.travel_explore_rounded,
                    title: 'ATMOS TRS',
                    subtitle: 'Tourist and establishment dashboard',
                    onTap: () {
                      Navigator.pop(dialogContext);
                      unawaited(_openAtmosLogin());
                    },
                  ),
                  const SizedBox(height: 10),
                  _headerLoginChoiceTile(
                    icon: Icons.map_outlined,
                    title: 'Itinerary',
                    subtitle: 'Trip Planner dashboard',
                    onTap: () {
                      Navigator.pop(dialogContext);
                      _navigateToLoginForFeature(
                        returnFeature: LoginRouteArgs.featureItinerary,
                      );
                    },
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _headerLoginChoiceTile({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return Material(
      color: const Color(0xFFFFF8F4),
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFFF4D5C2)),
          ),
          child: Row(
            children: [
              Icon(icon, color: _primaryOrange),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: GoogleFonts.montserrat(
                        color: const Color(0xFF1B2433),
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: GoogleFonts.montserrat(
                        color: const Color(0xFF64748B),
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.arrow_forward_rounded, color: _primaryOrange),
            ],
          ),
        ),
      ),
    );
  }

  void _navigateToSignup() {
    _pushAuthRoute('/signup');
  }

  void _continueCameraQrCheckInOnWeb() {
    Navigator.of(context).pushNamed('/qr-welcome');
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
    if (returnFeature == LoginRouteArgs.featureItinerary) {
      await LandingIntentNavigation.openPlanner(context);
      return;
    }
    // ATMOS-TRS login (including a VR return) opens the signed-in role
    // dashboard. APK downloads stay on the Home download buttons.
    await _openAuthorizedDashboard();
  }

  Future<void> _openPlanItinerary({String? municipalityName}) async {
    _pauseHeroVideoForAuthNavigation();
    // Signed-in catalog admins (OPTACA, governor, LGU) open the Trip Planner
    // admin dashboard from the home card. Do this before the tourist check,
    // which otherwise sends staff into the ATMOS role app.
    if (_isLoggedIn && await TripPlannerAccess.isCatalogAdmin()) {
      await LandingIntentService.clear();
      if (!mounted) return;
      await LandingIntentNavigation.openPlanner(context);
      return;
    }
    final access = _isLoggedIn
        ? await TripPlannerAccess.evaluate()
        : TripPlannerAccessResult.signedOut;
    if (!mounted) return;
    if (access == TripPlannerAccessResult.denied) {
      if (await TripPlannerAccess.isCatalogAdmin()) {
        await LandingIntentService.clear();
        if (!mounted) return;
        await LandingIntentNavigation.openPlanner(context);
        return;
      }
      await LandingIntentService.clear();
      if (!mounted) return;
      final route = await _authorizedDashboardRoute();
      if (!mounted) return;
      Navigator.of(context).pushNamed(route);
      return;
    }
    await LandingIntentService.setPending(
      feature: LoginRouteArgs.featureItinerary,
      municipalityName: municipalityName,
    );
    if (access == TripPlannerAccessResult.signedOut) {
      _navigateToLoginForFeature(
        returnFeature: LoginRouteArgs.featureItinerary,
        municipalityName: municipalityName,
      );
      return;
    }
    await LandingIntentService.clear();
    if (!mounted) return;
    await LandingIntentNavigation.openPlanner(context);
  }

  void _openVrOrLogin() {
    // ATMOS login. Sign Up opens the account chooser, with Tourist and Establishment.
      _navigateToLoginForFeature(returnFeature: LoginRouteArgs.featureVr);
    }

  Future<void> _openAuthorizedDashboard() async {
    _pauseHeroVideoForAuthNavigation();
    final route = await _authorizedDashboardRoute();
    if (!mounted) return;
    Navigator.of(context).pushNamed(route);
  }

  /// Role dashboard for the signed-in Firebase account. Does not create a new user.
  Future<String> _authorizedDashboardRoute() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return '/login';
    final profile = await UserDirectoryService.getProfileByUid(user.uid);
    if (profile != null) return RoleRouter.routeForProfile(profile);
    final storedUid = await SessionStorage.getStoredUser();
    if (storedUid != user.uid) return '/dashboard';
    final role = await SessionStorage.getStoredRole();
    return switch (role) {
      UserRole.governor => '/governor-dashboard',
      UserRole.provincialTourism => '/provincial-tourism-dashboard',
      UserRole.tourism => '/lgu-dashboard',
      UserRole.tourismEstablishment => '/establishment-dashboard',
      UserRole.tourist => '/dashboard',
    };
  }

  void _openTripPlannerOrLogin() {
    if (_isLoggedIn) {
      unawaited(_openPlanItinerary());
    } else {
      _navigateToLoginForFeature(
        returnFeature: LoginRouteArgs.featureItinerary,
      );
    }
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

  String get _landingVrButtonLabel => VrDownloadAppPrompt.ctaLabel(
    mobileLabel: _isMobile ? 'VR Tour' : 'Start VR Tour',
  );

  static const List<String> _sectionOrder = [
    'home',
    'chooseExperience',
    'features',
    'destinations',
    'howItWorks',
    'about',
    'faq',
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
    if (!_heavyImagesEnabled ||
        _destinationImageBudget < _destinations.length) {
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
    _authSub?.cancel();
    _registeredTouristSub?.cancel();
    _spotStatsSub?.cancel();
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

  bool get _isLoggedIn => _authUser != null;
  bool get _isTablet =>
      MediaQuery.of(context).size.width >= 768 &&
      MediaQuery.of(context).size.width < 1024;
  bool get _isDesktop => MediaQuery.of(context).size.width >= 1024;
  bool get _isWideDesktop => MediaQuery.of(context).size.width >= 1366;
  bool get _isUltraWide => MediaQuery.of(context).size.width >= 1920;

  TextStyle _navLabelStyle({required bool compact, Color? color}) {
    return GoogleFonts.montserrat(
      color: color,
      fontSize: compact ? 12 : 13,
      fontWeight: FontWeight.w700,
      letterSpacing: 0.05,
      height: 1.15,
    );
  }

  /// Width of the six full labels plus their chip padding.
  double _landingNavWidth({required bool compact}) {
    final style = _navLabelStyle(compact: compact);
    final innerPad = compact ? 16.0 : 22.0;
    final outerPad = compact ? 4.0 : 6.0;
    var total = 0.0;
    for (final item in _landingNavItems) {
      final painter = TextPainter(
        text: TextSpan(text: item.label, style: style),
        textDirection: TextDirection.ltr,
        maxLines: 1,
      )..layout();
      total += painter.width + innerPad + outerPad;
    }
    return total;
  }

  /// Space kept for the logo, brand, and optional mute control.
  double get _headerBrandReserve {
    final width = MediaQuery.sizeOf(context).width;
    final brandMin = width < 520 ? 132.0 : 176.0;
    // Keep room for the hero mute control so it cannot push the labels.
    return 52 + brandMin + 24 + 44;
  }

  /// Log In and Sign Up, or Dashboard when a session already exists.
  double get _headerAuthReserve {
    final style = GoogleFonts.montserrat(
      fontSize: 13,
      fontWeight: FontWeight.w700,
      height: 1.15,
    );
    double labelWidth(String text) {
      final painter = TextPainter(
        text: TextSpan(text: text, style: style),
        textDirection: TextDirection.ltr,
        maxLines: 1,
      )..layout();
      return painter.width + 36;
    }

    if (_isLoggedIn) return labelWidth('Dashboard');
    return labelWidth('Log In') + 8 + labelWidth('Sign Up');
  }

  /// Menu button only when the six full labels and auth actions cannot fit.
  bool get _useDrawerNav {
    final width = MediaQuery.sizeOf(context).width;
    return width <
        _landingNavWidth(compact: true) +
            _headerBrandReserve +
            _headerAuthReserve;
  }

  /// Tighter chip padding on smaller laptops. Labels stay unchanged.
  bool get _navCompact {
    if (_useDrawerNav) return false;
    final width = MediaQuery.sizeOf(context).width;
    return width <
        _landingNavWidth(compact: false) +
            _headerBrandReserve +
            _headerAuthReserve +
            24;
  }

  double get _landingAppBarHeight =>
      _useDrawerNav ? (_isMobile ? 96.0 : 88.0) : 72.0;

  /// One full-screen panel per nav item (area below the app bar).
  double get _sectionViewportHeight {
    final screenH = MediaQuery.sizeOf(context).height;
    final height = screenH - _landingAppBarHeight;
    // clamp() throws when the window is shorter than the 420px floor.
    if (height < 420) return height < 0 ? 0.0 : height;
    return height.clamp(420.0, screenH);
  }

  double get _sectionContentMaxWidth {
    if (_isUltraWide) return 1560;
    if (_isWideDesktop) return 1360;
    if (_isDesktop) return 1180;
    return double.infinity;
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

  /// City and municipality names on destination cards and search results.
  TextStyle get _destinationNameStyle => GoogleFonts.montserrat(
    color: _darkBg,
    fontSize: _isMobile ? 16 : 17,
    fontWeight: FontWeight.w800,
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
    (label: 'FAQ', sectionId: 'faq', icon: Icons.help_outline_rounded),
  ];

  GlobalKey? _sectionKey(String section) {
    return switch (section) {
      'home' => _keyHome,
      'chooseExperience' => _keyChooseExperience,
      'features' => _keyFeatures,
      'destinations' => _keyDestinations,
      'howItWorks' => _keyHowItWorks,
      'about' => _keyAbout,
      'faq' => _keyFaq,
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
                QrCameraGetAppBanner(
                  onContinueCheckIn: _continueCameraQrCheckInOnWeb,
                ),
                if (!_isLoggedIn) _buildRegisterCalloutSection(),
                _buildViewportNavSection(
                  key: _keyChooseExperience,
                  color: const Color(0xFFFFF8F4),
                  child: _buildChooseYourExperienceSection(viewport: true),
                ),
                _buildViewportNavSection(
                  key: _keyFeatures,
                  color: LandingFeaturesSection.page,
                  child: _buildFeaturesSection(viewport: true),
                ),
                _buildViewportNavSection(
                  key: _keyDestinations,
                  color: const Color(0xFFFFF8F4),
                  child: _buildDestinationsSection(viewport: true),
                ),
                _buildViewportNavSection(
                  key: _keyHowItWorks,
                  color: LandingHowItWorksSection.page,
                  child: _buildHowItWorksSection(viewport: true),
                ),
                _buildViewportNavSection(
                  key: _keyAbout,
                  color: _pageBackground,
                  child: _buildAboutAndStatistics(viewport: true),
                ),
                _buildViewportNavSection(
                  key: _keyFaq,
                  color: const Color(0xFFFFF8F4),
                  child: _buildLandingFaqSection(),
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
    final titleSize = _isMobile
        ? (narrow ? 18.0 : 20.0)
        : (_useDrawerNav ? 20.0 : 22.0);
    final meaningSize = narrow ? 8.5 : (_isMobile ? 9.0 : 9.5);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisAlignment: MainAxisAlignment.center,
      mainAxisSize: MainAxisSize.min,
      children: [
        _LandingHeaderWordmark(fontSize: titleSize),
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
              color: Colors.white.withValues(alpha: _isScrolled ? 0.97 : 0.92),
              borderRadius: const BorderRadius.only(
                bottomLeft: Radius.circular(28),
                bottomRight: Radius.circular(28),
              ),
              border: Border(
                bottom: BorderSide(color: Colors.white.withValues(alpha: 0.7)),
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
                    child: Center(
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _buildInlineNavBar(),
                          const SizedBox(width: 8),
                          _buildHeaderAuthActions(),
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

  /// Fixed-height panel for nav targets; scroll inside if content is taller than one screen.
  Widget _buildViewportNavSection({
    required GlobalKey key,
    required Color color,
    required Widget child,
    bool fullScreenOnWeb = false,
    BoxDecoration? decoration,
  }) {
    final useViewportPanel =
        _isMobile || (kIsWeb && fullScreenOnWeb && !_isMobile);
    return Container(
      key: key,
      alignment: useViewportPanel ? Alignment.center : Alignment.topCenter,
      constraints: BoxConstraints(
        minHeight: useViewportPanel ? _sectionViewportHeight : 0,
      ),
      width: double.infinity,
      decoration: decoration ?? BoxDecoration(color: color),
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

    return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final item in _landingNavItems)
            _buildNavChip(
            label: item.label,
              onTap: () => _onNavTap(item.sectionId),
              isActive: _activeSection == item.sectionId,
              compact: compact,
            ),
      ],
    );
  }

  Widget _buildHeaderAuthActions() {
    if (_isLoggedIn) {
      return _headerAuthButton(
        label: 'Dashboard',
        filled: true,
        onPressed: () => unawaited(_openAuthorizedDashboard()),
      );
    }
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _headerAuthButton(
              label: 'Log In',
          filled: false,
          onPressed: _openHeaderLoginChoice,
            ),
        const SizedBox(width: 8),
        _headerAuthButton(
              label: 'Sign Up',
          filled: true,
          onPressed: _navigateToSignup,
        ),
      ],
    );
  }

  Widget _headerAuthButton({
    required String label,
    required bool filled,
    required VoidCallback onPressed,
  }) {
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(999),
    );
    final textStyle = GoogleFonts.montserrat(
      fontSize: 13,
      fontWeight: FontWeight.w700,
      height: 1.15,
    );
    if (filled) {
      return FilledButton(
        onPressed: onPressed,
        style: FilledButton.styleFrom(
          backgroundColor: _primaryOrange,
          foregroundColor: Colors.white,
          elevation: 0,
          minimumSize: const Size(0, 36),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          shape: shape,
          textStyle: textStyle,
        ),
        child: Text(label),
      );
    }
    return OutlinedButton(
      onPressed: onPressed,
      style: OutlinedButton.styleFrom(
        foregroundColor: _primaryOrange,
        backgroundColor: Colors.white,
        side: const BorderSide(color: _primaryOrange, width: 1.4),
        minimumSize: const Size(0, 36),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        shape: shape,
        textStyle: textStyle,
      ),
      child: Text(label),
    );
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
              maxLines: 1,
              softWrap: false,
              style: _navLabelStyle(
                compact: compact,
                color: isActive ? Colors.white : const Color(0xFF192334),
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
                  maxLines: 1,
                  softWrap: false,
                  overflow: TextOverflow.ellipsis,
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
            if (!_isLoggedIn) ...[
            const Divider(height: 24),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                      child: OutlinedButton(
                        onPressed: () {
                          Navigator.pop(context);
                    _openHeaderLoginChoice();
                        },
                        style: OutlinedButton.styleFrom(
                          foregroundColor: _primaryOrange,
                    side: const BorderSide(color: _primaryOrange, width: 1.4),
                    minimumSize: const Size.fromHeight(44),
                          shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(999),
                          ),
                        ),
                        child: const Text(
                          'Log In',
                    style: TextStyle(fontWeight: FontWeight.w800),
                        ),
                      ),
                    ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                      child: FilledButton(
                        onPressed: () {
                          Navigator.pop(context);
                          _navigateToSignup();
                        },
                        style: FilledButton.styleFrom(
                          backgroundColor: _primaryOrange,
                          foregroundColor: Colors.white,
                    minimumSize: const Size.fromHeight(44),
                          shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(999),
                          ),
                        ),
                        child: const Text(
                          'Sign Up',
                    style: TextStyle(fontWeight: FontWeight.w800),
                        ),
                      ),
                    ),
                  ],
            if (_isLoggedIn) ...[
              const Divider(height: 24),
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
    final topInset =
        MediaQuery.paddingOf(context).top +
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
                              SizedBox(height: _isMobile ? 14 : 16),
                              _buildHeroApkDownloads(),
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
          if (_heroStatsOpen)
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.translucent,
                onTap: () => setState(() => _heroStatsOpen = false),
              ),
            ),
          Positioned(
            right: _isMobile ? 16 : 32,
            bottom: MediaQuery.paddingOf(context).bottom + (_isMobile ? 86 : 36),
            child: _buildHeroStatsAnchor(),
          ),
        ],
      ),
    );
  }

  List<LandingStatEntry> get _heroStatEntries {
    LandingStatStatus status({
      required bool loading,
      required bool failed,
      required int? value,
    }) {
      if (value != null) return LandingStatStatus.ready;
      if (loading && !failed) return LandingStatStatus.loading;
      return LandingStatStatus.unavailable;
    }

    final municipalities = getMisamisOccidentalMunicipalities().length;
    return [
      LandingStatEntry(
        label: 'Registered Tourists',
        icon: Icons.people_rounded,
        status: status(
          loading: _registeredTouristsLoading,
          failed: _registeredTouristsFailed,
          value: _registeredTourists,
        ),
        value: _registeredTourists,
      ),
      LandingStatEntry(
        label: 'Tourist Spots',
        icon: Icons.place_rounded,
        status: status(
          loading: _spotStatsLoading,
          failed: _spotStatsFailed,
          value: _touristSpots,
        ),
        value: _touristSpots,
      ),
      LandingStatEntry(
        label: 'Cities & Municipalities',
        icon: Icons.location_city_rounded,
        status: municipalities > 0
            ? LandingStatStatus.ready
            : LandingStatStatus.unavailable,
        value: municipalities > 0 ? municipalities : null,
      ),
      LandingStatEntry(
        label: 'VR Tours',
        icon: Icons.vrpano_rounded,
        status: status(
          loading: _spotStatsLoading,
          failed: _spotStatsFailed,
          value: _vrTours,
        ),
        value: _vrTours,
      ),
    ];
  }

  Widget _buildHeroStatsAnchor() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 220),
          switchInCurve: Curves.easeOutCubic,
          switchOutCurve: Curves.easeInCubic,
          transitionBuilder: (child, animation) {
            return FadeTransition(
              opacity: animation,
              child: ScaleTransition(
                scale: Tween<double>(begin: 0.94, end: 1).animate(animation),
                alignment: Alignment.bottomRight,
                child: child,
              ),
            );
          },
          child: _heroStatsOpen
              ? Padding(
                  key: const ValueKey('landing-stats-open'),
                  padding: const EdgeInsets.only(bottom: 10),
                  child: LandingHeroStatsPanel(
                    entries: _heroStatEntries,
                    onClose: () => setState(() => _heroStatsOpen = false),
                  ),
                )
              : const SizedBox.shrink(key: ValueKey('landing-stats-closed')),
        ),
        Tooltip(
          message: 'By the numbers',
          child: Material(
            color: Colors.white,
            elevation: 6,
            shadowColor: Colors.black26,
            shape: const CircleBorder(),
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: () => setState(() => _heroStatsOpen = !_heroStatsOpen),
              child: const SizedBox(
                width: 46,
                height: 46,
                child: Icon(
                  Icons.insights_rounded,
                  color: _primaryOrange,
                  size: 22,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildHeroGlassFeatureCards() {
    final cards = [
      (
        icon: Icons.vrpano_rounded,
        title: '360° Previews',
        subtitle: 'See before you go',
        onTap: _openVrOrLogin,
      ),
      (
        icon: Icons.map_rounded,
        title: 'Trip Planner',
        subtitle: 'Plan your adventure',
        onTap: _openTripPlannerOrLogin,
      ),
      (
        icon: Icons.groups_rounded,
        title: '17 LGUs',
        subtitle: '3 Cities & 14 Municipalities',
        onTap: () => _onNavTap('destinations'),
      ),
    ];

    Widget buildCard(
      int index,
      ({IconData icon, String title, String subtitle, VoidCallback onTap}) c,
    ) {
      final hovered = _hoveredHeroGlassIndex == index;
      return MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hoveredHeroGlassIndex = index),
        onExit: (_) => setState(() => _hoveredHeroGlassIndex = null),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: c.onTap,
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
                                      color: Colors.white.withValues(
                                        alpha: 0.92,
                                      ),
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
        constraints: const BoxConstraints(maxWidth: 500),
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
      crossAxisAlignment: _isMobile
          ? CrossAxisAlignment.center
          : CrossAxisAlignment.start,
      children: [
        Text(
          'EXPLORE  •  EXPERIENCE  •  BELONG',
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
          'Walk destinations in immersive 360°, map your dream itinerary, '
          'and discover all 17 LGUs — before you even pack your bags.',
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
    // OPTACA / provincial → Trip Planner OPTACA portal (not ATMOS tourist shell).
    final emailRole = SessionStorage.getRoleFromEmail(email);
    if (emailRole == UserRole.governor) {
      if (!mounted) return;
      Navigator.of(context).pushNamed('/governor-dashboard');
      return;
    }
    if (emailRole == UserRole.provincialTourism) {
      if (!mounted) return;
      Navigator.of(context).pushNamed('/trip-planner-admin');
      return;
    }
    if (emailRole == UserRole.tourism) {
      if (!mounted) return;
      Navigator.of(context).pushNamed('/lgu-dashboard');
      return;
    }
    if (emailRole == UserRole.tourismEstablishment) {
      if (!mounted) return;
      Navigator.of(context).pushNamed('/establishment-dashboard');
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
          route == '/tourism-dashboard' ||
          route == '/provincial-tourism-dashboard' ||
          route == '/establishment-dashboard') {
        // OPTACA: Open Dashboard opens Trip Planner admin, not ATMOS provincial.
        if (route == '/provincial-tourism-dashboard') {
          Navigator.of(context).pushNamed('/trip-planner-admin');
          return;
        }
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
      if (storedRole == UserRole.provincialTourism) {
        Navigator.of(context).pushNamed('/trip-planner-admin');
        return;
      }
      if (storedRole == UserRole.tourism) {
        Navigator.of(context).pushNamed('/lgu-dashboard');
        return;
      }
      if (storedRole == UserRole.tourismEstablishment) {
        Navigator.of(context).pushNamed('/establishment-dashboard');
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
    final preview = index == 0 ? _vrTourPreview : _tripPlannerPreview;
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    showGeneralDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
      barrierColor: Colors.black.withValues(alpha: 0.45),
      transitionDuration: reduceMotion
          ? Duration.zero
          : const Duration(milliseconds: 340),
      pageBuilder: (context, _, _) =>
          Center(child: _ExperiencePreviewDialog(preview: preview)),
      transitionBuilder: (context, animation, _, child) {
        final curved = CurvedAnimation(
          parent: animation,
          curve: Curves.easeOutCubic,
          reverseCurve: Curves.easeInCubic,
        );
        return FadeTransition(
          opacity: curved,
          child: ScaleTransition(
            scale: Tween<double>(begin: 0.96, end: 1).animate(curved),
            child: child,
          ),
        );
      },
    );
  }

  void _openExperienceVirtualTour() {
    if (!_isLoggedIn) {
      _navigateToLoginForFeature(returnFeature: LoginRouteArgs.featureVr);
      return;
    }
    unawaited(_openExperienceVirtualTourForRole());
  }

  Future<void> _openExperienceVirtualTourForRole() async {
    final user = FirebaseAuth.instance.currentUser;
    final profile = user == null
        ? null
        : await UserDirectoryService.getProfileByUid(user.uid);
    if (!mounted) return;
    if (profile == null || profile.isTourist) {
      await _openVrTourFromLanding();
      return;
    }
    _pauseHeroVideoForAuthNavigation();
    if (!mounted) return;
    Navigator.of(context).pushNamed(RoleRouter.routeForProfile(profile));
  }

  void _openExperienceTripPlanner() {
    if (_isLoggedIn) {
      unawaited(_openPlanItinerary());
      return;
    }
    _navigateToLoginForFeature(returnFeature: LoginRouteArgs.featureItinerary);
  }

  void _showApkDownloadMessage(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  /// Downloads the hosted ATMOS TRS APK. Does not open login or a dashboard.
  Future<void> _downloadVrTourApk() async {
    if (!kHasAndroidApkDownload) {
      _showApkDownloadMessage(
        'The VR Tour APK needs to be built or uploaded before it can be downloaded.',
      );
      return;
    }
    final opened = await openAtmosAppDownload(
      target: AtmosAppDownloadTarget.apk,
      copyCheckInLinkToClipboard: false,
    );
    if (!opened && mounted) {
      _showApkDownloadMessage(
        'The VR Tour APK could not be opened. Confirm the download file is hosted.',
      );
    }
  }

  /// Downloads the hosted Trip Planner APK (does not open the in-app module).
  Future<void> _downloadTripPlannerApk() async {
    if (!kHasTripPlannerApkDownload) {
      _showApkDownloadMessage(
        'The Trip Planner APK needs to be built or uploaded before it can be downloaded.',
      );
      return;
    }
    final opened = await openTripPlannerApkDownload();
    if (!opened && mounted) {
      _showApkDownloadMessage(
        'The Trip Planner APK could not be opened. Confirm the download file is hosted.',
      );
    }
  }

  Widget _buildHeroApkDownloads() {
    return _HeroApkDownloadSection(
      centered: _isMobile,
      compact: _isMobile,
      color: _primaryOrange,
      onDownloadVrTour: () => unawaited(_downloadVrTourApk()),
      onDownloadTripPlanner: () => unawaited(_downloadTripPlannerApk()),
    );
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
                              style: _destinationNameStyle.copyWith(fontSize: 14),
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
              colors: [Color(0xFFFFF7ED), Color(0xFFFFFFFF), Color(0xFFFFF7ED)],
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
                style: _sectionBodyStyle.copyWith(
                  fontSize: _isMobile ? 14 : 15,
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
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
      ),
      icon: const Icon(Icons.person_add_alt_1_rounded, size: 20),
      label: Text(
        compact ? 'Register now — free' : 'Register now',
        style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
      ),
    );
  }

  static const _ExperiencePreview _vrTourPreview = _ExperiencePreview(
    title: 'VR Tour',
    explanation:
        'This is the ATMOS TRS tourist screen for Oroquieta City Plaza: the 360° plaza panorama, Start VR Tour, nearby restaurants, nearby hotels, and the app navigation bar.',
    assets: ['assets/mockup/vr tour.png'],
    aspect: 878 / 1791,
  );

  static const _ExperiencePreview _tripPlannerPreview = _ExperiencePreview(
    title: 'Trip Planner',
    explanation:
        'This is the Assign days screen: Day 1 starts in Sinacaban, with destinations, travel distance, duration, transportation, estimated expenses, and Review my trip.',
    assets: ['assets/mockup/Trip planner.png'],
    aspect: 851 / 1848,
  );

  Widget _buildChooseYourExperienceSection({bool viewport = false}) {
    return Stack(
      children: [
        const Positioned.fill(
          child: CustomPaint(painter: _ExperienceSectionPainter()),
        ),
        Padding(
      padding: EdgeInsets.symmetric(
            vertical: viewport ? (_isMobile ? 8 : 12) : (_isMobile ? 28 : 40),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _ExperienceEntrance(
                child: _buildExperienceHeading(),
              ),
              if (_qrWelcomeMessage != null) ...[
                SizedBox(height: viewport ? 16 : (_isMobile ? 20 : 24)),
                _buildQrRegistrationWelcomeBanner(),
              ],
              SizedBox(height: _isMobile ? 22 : 28),
              LayoutBuilder(
                builder: (context, constraints) {
                  final width = constraints.maxWidth;
                  final phoneHeight = _experiencePhoneHeight;
                  final virtualTour = _experienceModule(
                    index: 0,
                    phoneHeight: phoneHeight,
                    info: _experienceVirtualTourCard(),
                  );
                  final tripPlanner = _experienceModule(
                    index: 1,
                    phoneHeight: phoneHeight,
                    info: _experienceTripPlannerCard(),
                  );
                  if (width >= 980) {
                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(child: virtualTour),
                        const SizedBox(width: 18),
                        Expanded(child: tripPlanner),
                      ],
                    );
                  }
                  return Column(
                    children: [
                      virtualTour,
                      const SizedBox(height: 18),
                      tripPlanner,
                    ],
                  );
                },
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _experienceModule({
    required int index,
    required double phoneHeight,
    required Widget info,
  }) {
    return _ExperienceMergedPanel(
      phone: _experiencePhone(index: index, height: phoneHeight),
      info: info,
    );
  }

  Widget _buildExperienceHeading() {
    final titleSize = _isMobile ? 34.0 : (_isTablet ? 44.0 : 52.0);
    return Column(
              children: [
                Text(
          'EXPLORE  ·  DISCOVER  ·  EXPERIENCE',
                  textAlign: TextAlign.center,
          style: GoogleFonts.montserrat(
                    color: _primaryOrange,
            fontSize: _isMobile ? 11 : 12,
                    fontWeight: FontWeight.w800,
            letterSpacing: _isMobile ? 1.4 : 2.2,
          ),
        ),
        SizedBox(height: _isMobile ? 12 : 16),
        Text.rich(
          TextSpan(
            children: [
              const TextSpan(text: 'Discover\n'),
              TextSpan(
                text: 'Misamis Occidental',
                style: TextStyle(color: _primaryOrange),
              ),
            ],
          ),
          textAlign: TextAlign.center,
          style: GoogleFonts.montserrat(
            color: const Color(0xFF1B2433),
            fontSize: titleSize,
            fontWeight: FontWeight.w800,
            height: 1.05,
            letterSpacing: -0.8,
          ),
        ),
        const SizedBox(height: 14),
                ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
                  child: Text(
            'Experience stunning destinations, local culture, and unique attractions through our smart tourism platform.',
                    textAlign: TextAlign.center,
            style: GoogleFonts.montserrat(
              color: const Color(0xFF475569),
              fontSize: _isMobile ? 14.5 : 16,
              height: 1.5,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
    );
  }

  Widget _experiencePhone({required int index, required double height}) {
    final asset = index == 0
        ? 'assets/mockup/vr tour.png'
        : 'assets/mockup/Trip planner.png';
    return _ExperienceEntrance(
      delay: Duration(milliseconds: 80 + index * 90),
      child: _ExperiencePhoneMotion(
        asset: asset,
        height: height,
        framed: false,
        aspect: index == 0 ? 878 / 1791 : 851 / 1848,
        motionIndex: index,
        onTap: () => _onExperienceCardTap(index),
      ),
    );
  }

  Widget _experienceVirtualTourCard() {
    return _ExperienceEntrance(
      delay: const Duration(milliseconds: 140),
        child: _ExperienceGlassCard(
          embedded: true,
          icon: Icons.vrpano_rounded,
          title: 'Virtual Tour',
          body:
              'Experience the beauty of Misamis Occidental through immersive 360° virtual tours.',
          points: const [
            '360° Interactive Tour',
            'Explore Tourist Spots',
            'View Nearby Establishments',
            'Realistic and Immersive Experience',
          ],
          buttonLabel: 'Explore Virtual Tour',
          highlighted: _highlightExperienceSection,
          onPressed: _openExperienceVirtualTour,
        ),
    );
  }

  Widget _experienceTripPlannerCard() {
    return _ExperienceEntrance(
      delay: const Duration(milliseconds: 220),
        child: _ExperienceGlassCard(
          embedded: true,
          icon: Icons.calendar_month_rounded,
          title: 'Trip Planner',
          body:
              'Plan your journey with day-by-day itineraries, travel estimates, and organized destinations.',
          points: const [
            'Create Day-by-Day Itineraries',
            'Estimated Travel Time & Distance',
            'Discover Recommended Destinations',
            'Save and Manage Your Trip',
          ],
          buttonLabel: 'Plan Your Trip',
          highlighted: _highlightExperienceSection,
          onPressed: _openExperienceTripPlanner,
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
          colors: [Color(0xFFFFF7ED), Color(0xFFFFFFFF)],
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
                Text(_qrWelcomeMessage!, style: _cardSubtitleStyle),
              ],
            ),
          ),
        ],
      ),
    );
  }

  double get _experiencePhoneHeight {
    final width = MediaQuery.sizeOf(context).width;
    if (width < 720) return 400;
    if (width < 1180) return 440;
    if (width < 1400) return 430;
    return 500;
  }

  Widget _buildFeaturesSection({bool viewport = false}) {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: viewport ? 8 : 36),
      child: const LandingFeaturesSection(),
    );
  }

  /// [highlight] must be a substring of [title]; it is drawn in brand orange.
  Widget _twoToneTitle(
    String title,
    String? highlight,
    TextStyle style, {
    TextAlign textAlign = TextAlign.center,
  }) {
    final i = (highlight == null || highlight.isEmpty)
        ? -1
        : title.lastIndexOf(highlight);
    if (i < 0) return Text(title, textAlign: textAlign, style: style);
    final end = i + highlight!.length;
    return Text.rich(
      TextSpan(
        children: [
          if (i > 0) TextSpan(text: title.substring(0, i)),
          TextSpan(
            text: highlight,
            style: const TextStyle(color: _primaryOrange),
          ),
          if (end < title.length) TextSpan(text: title.substring(end)),
        ],
      ),
      textAlign: textAlign,
      style: style,
    );
  }

  Widget _buildDestinationsSection({bool viewport = false}) {
    final query = _heroSearchController.text.trim();
    final filtered = _filteredDestinations;
    final isFiltering = query.isNotEmpty;
    final matchLabel = filtered.length == 1 ? 'match' : 'matches';

    return Stack(
      children: [
        const Positioned.fill(
          child: CustomPaint(painter: _DestinationsBackdropPainter()),
        ),
        Padding(
      padding: EdgeInsets.symmetric(
        vertical: _sectionInnerVertical(viewport: viewport),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildDestinationsHeading(
            title: isFiltering ? 'Search results' : 'Municipalities & Cities',
            subtitle: isFiltering
                ? '${filtered.length} $matchLabel for "$query" — tap a card for VR tours, itinerary planning & tourist spots'
                : 'All 17 tourist destinations in Misamis Occidental — tap any card to explore in 360° or plan your trip',
            badge: isFiltering ? '${filtered.length} found' : '17 LGUs',
            highlight: isFiltering ? 'results' : 'Cities',
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
                    (constraints.maxWidth - spacing * (columns - 1)) / columns;
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
        ),
      ],
    );
  }

  Widget _buildDestinationsHeading({
    required String title,
    required String subtitle,
    required String badge,
    required String highlight,
  }) {
    final titleSize = _isMobile ? 32.0 : 46.0;
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
          decoration: BoxDecoration(
            color: const Color(0xFFFFF1E6),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: const Color(0xFFF8D7C0)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.location_city_rounded,
                size: 14,
                color: _primaryOrange,
              ),
              const SizedBox(width: 6),
              Text(
                badge.toUpperCase(),
                style: GoogleFonts.montserrat(
                  color: _primaryOrange,
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.1,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        _twoToneTitle(
          title,
          highlight,
          GoogleFonts.montserrat(
            color: const Color(0xFF1B2433),
            fontSize: titleSize,
            fontWeight: FontWeight.w800,
            height: 1.1,
            letterSpacing: -0.6,
          ),
        ),
        const SizedBox(height: 10),
        ConstrainedBox(
          constraints: BoxConstraints(maxWidth: _sectionSubtitleMaxWidth),
          child: Text(
            subtitle,
            textAlign: TextAlign.center,
            style: GoogleFonts.montserrat(
              color: const Color(0xFF64748B),
              fontSize: _isMobile ? 14 : 16,
              fontWeight: FontWeight.w500,
              height: 1.5,
            ),
          ),
        ),
      ],
    );
  }

  BoxDecoration _destinationCardDecoration({required bool hovered}) {
    return BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(22),
      border: Border.all(
        color: hovered ? _primaryOrange : const Color(0xFFF4D5C2),
        width: hovered ? 1.5 : 1,
      ),
      boxShadow: [
        BoxShadow(
          color: hovered
              ? _primaryOrange.withValues(alpha: 0.16)
              : const Color(0x140F172A),
          blurRadius: hovered ? 24 : 16,
          offset: Offset(0, hovered ? 12 : 6),
        ),
      ],
    );
  }

  Widget _buildDestinationsEmptyState(String query) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 48),
      decoration: _destinationCardDecoration(hovered: false),
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
                color: const Color(0xFFFFF8F4),
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
                                      onTap: () =>
                                          _showDestinationImageFullscreen(
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
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                    horizontal: 8,
                                                    vertical: 5,
                                                  ),
                                              decoration: BoxDecoration(
                                                color: Colors.black.withValues(
                                                  alpha: 0.55,
                                                ),
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
                                                      fontWeight:
                                                          FontWeight.w600,
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
                            style: GoogleFonts.montserrat(
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
                          const SizedBox(height: 8),
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
    return SpotImage(imageUrl: imageUrl, fit: fit);
  }

  Widget _destinationCategoryBadge(String category) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF1E6),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: const Color(0xFFF8D7C0)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Text(
        category.toUpperCase(),
        style: GoogleFonts.montserrat(
          color: _primaryOrange,
          fontSize: 10,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.6,
        ),
      ),
    );
  }

  Widget _destinationExploreCue() {
    return Row(
      children: [
        const Icon(Icons.place_rounded, size: 16, color: _primaryOrange),
        const SizedBox(width: 6),
        Text(
          'Explore destination',
          style: GoogleFonts.montserrat(
            color: _primaryOrange,
            fontSize: 13,
          fontWeight: FontWeight.w700,
          ),
        ),
        const Spacer(),
        const Icon(
          Icons.arrow_forward_rounded,
          size: 16,
          color: _primaryOrange,
        ),
      ],
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
            borderRadius: BorderRadius.circular(22),
            child: AnimatedContainer(
              duration: _motionDuration,
              curve: Curves.easeOutCubic,
              transform: Matrix4.identity()
                ..translateByDouble(0, isHovered ? -6.0 : 0.0, 0, 1),
              decoration: _destinationCardDecoration(hovered: isHovered),
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
                          child: _destinationCategoryBadge(category),
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
                          style: _destinationNameStyle,
                        ),
                        const SizedBox(height: 6),
                        Text(
                          description,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.montserrat(
                            color: const Color(0xFF64748B),
                            fontSize: 13,
                            height: 1.45,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        const SizedBox(height: 12),
                        _destinationExploreCue(),
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
          borderRadius: BorderRadius.circular(22),
          child: AnimatedContainer(
            duration: _motionDuration,
            curve: Curves.easeOutCubic,
            transform: Matrix4.identity()
              ..translateByDouble(0, isHovered ? -6.0 : 0.0, 0, 1),
            decoration: _destinationCardDecoration(hovered: isHovered),
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
                        child: _destinationCategoryBadge(category),
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
                        style: _destinationNameStyle,
                      ),
                      const SizedBox(height: 6),
                      Text(
                        description,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.montserrat(
                          color: const Color(0xFF64748B),
                          fontSize: 13,
                          height: 1.45,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: 12),
                      _destinationExploreCue(),
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
    return Padding(
      padding: EdgeInsets.symmetric(vertical: viewport ? 8 : 36),
      child: LandingHowItWorksSection(
        steps: [
          for (final step in _steps)
            LandingHowItWorksStep(
              number: step['number'] as String,
              title: step['title'] as String,
              description: step['description'] as String,
              icon: step['icon'] as IconData,
          ),
        ],
      ),
    );
  }

  Widget _buildAboutAndStatistics({bool viewport = false}) {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: viewport ? 8 : 36),
      child: LandingAboutShowcase(
        bleed: _sectionOuterPadding,
        compact: _isMobile,
        tablet: _isTablet,
        showNumbers: false,
        titleSize: _isMobile ? 28 : 38,
        bodyStyle: _sectionBodyStyle,
        body:
            'ATMOS-TRS — $_kAppFullName — is the official digital platform for tourism in Misamis Occidental. '
            'We provide seamless tourist registration, VR previews of destinations, itinerary planning, and QR check-ins at spots.\n\n'
            'Our mission is to connect visitors with local communities and create a sustainable, smart tourism ecosystem across the province.',
        capitol: _heavyImagesEnabled
            ? const SpotImage(
                  imageUrl: _kCapitolAsset,
                  fit: BoxFit.cover,
                )
            : ColoredBox(
                  color: const Color(0xFFE2E8F0),
                  child: Center(
                    child: Icon(
                      Icons.account_balance_rounded,
                      size: 48,
                      color: _primaryOrange.withValues(alpha: 0.45),
                    ),
                  ),
                ),
        stats: [
          LandingAboutStat(
            value: '',
            label: 'Registered Tourists',
            icon: Icons.people_rounded,
            liveCount: _registeredTourists,
            liveLoading: _registeredTouristsLoading,
            liveUnavailable: _registeredTouristsFailed,
          ),
          LandingAboutStat(
            value: _formatStatCount(_publicStats?.touristSpots),
            label: 'Tourist Spots',
            icon: Icons.place_rounded,
          ),
          const LandingAboutStat(
            value: '17',
            label: 'Cities & Municipalities',
            icon: Icons.location_city_rounded,
          ),
          const LandingAboutStat(
            value: '7',
            label: 'VR Tours',
            icon: Icons.vrpano_rounded,
          ),
        ],
      ),
    );
  }

  Widget _buildLandingFaqSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'FAQ',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: _primaryOrange,
            fontSize: _isMobile ? 13 : 14,
            fontWeight: FontWeight.w800,
            letterSpacing: 1.1,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Frequently Asked Questions',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: _darkBg,
            fontSize: _isMobile ? 26 : 34,
            fontWeight: FontWeight.w800,
            height: 1.15,
            letterSpacing: -0.4,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Answers about registration, QR check-in, and using ATMOS-TRS.',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: _bodyText,
            fontSize: _isMobile ? 14 : 16,
            height: 1.45,
          ),
        ),
        const SizedBox(height: 22),
        const _LandingFaqAccordion(),
      ],
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
        border: Border(top: BorderSide(color: _primaryOrange, width: 3)),
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

  void _openLandingFaq() {
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    showGeneralDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Close frequently asked questions',
      barrierColor: Colors.black.withValues(alpha: 0.45),
      transitionDuration: reduceMotion
          ? Duration.zero
          : const Duration(milliseconds: 320),
      pageBuilder: (context, _, _) => const _LandingFaqDialog(),
      transitionBuilder: (context, animation, _, child) {
        final curved = CurvedAnimation(
          parent: animation,
          curve: Curves.easeOutCubic,
          reverseCurve: Curves.easeInCubic,
        );
        return FadeTransition(
          opacity: curved,
          child: SlideTransition(
            position: Tween<Offset>(
              begin: const Offset(0, 0.08),
              end: Offset.zero,
            ).animate(curved),
            child: child,
          ),
        );
      },
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
        InkWell(
          onTap: () => _onNavTap('faq'),
          borderRadius: BorderRadius.circular(8),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.help_outline_rounded,
                  size: 16,
                  color: Colors.white.withValues(alpha: 0.72),
                ),
                const SizedBox(width: 6),
                Text(
                  'FAQ',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.72),
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
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
    return SpotImage(imageUrl: imageUrl, fit: BoxFit.contain);
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
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
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
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
              ),
            ),
          ),
        ),
      ),
      body: SafeArea(
        child: InteractiveViewer(
          minScale: 1,
          maxScale: 4,
          child: Center(child: _buildImage()),
        ),
      ),
    );
  }
}

class _ExperienceEntrance extends StatefulWidget {
  const _ExperienceEntrance({
    required this.child,
    this.delay = Duration.zero,
  });

  final Widget child;
  final Duration delay;

  @override
  State<_ExperienceEntrance> createState() => _ExperienceEntranceState();
}

class _ExperienceEntranceState extends State<_ExperienceEntrance>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 620),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (MediaQuery.disableAnimationsOf(context)) {
        _controller.value = 1;
        return;
      }
      Future<void>.delayed(widget.delay, () {
        if (mounted) _controller.forward();
      });
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        final t = Curves.easeOutCubic.transform(_controller.value);
        return Opacity(
          opacity: t,
          child: Transform.translate(
            offset: Offset(0, (1 - t) * 28),
            child: child,
          ),
        );
      },
      child: widget.child,
    );
  }
}

class _ExperienceGlassCard extends StatefulWidget {
  const _ExperienceGlassCard({
    required this.icon,
    required this.title,
    required this.body,
    required this.points,
    required this.buttonLabel,
    required this.onPressed,
    this.highlighted = false,
    this.embedded = false,
  });

  final IconData icon;
  final String title;
  final String body;
  final List<String> points;
  final String buttonLabel;
  final VoidCallback onPressed;
  final bool highlighted;
  final bool embedded;

  @override
  State<_ExperienceGlassCard> createState() => _ExperienceGlassCardState();
}

class _ExperienceGlassCardState extends State<_ExperienceGlassCard> {
  static const Color _orange = Color(0xFFF97316);
  static const Color _navy = Color(0xFF192334);
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    final compact = MediaQuery.sizeOf(context).width < 720;
    return MouseRegion(
      onEnter: (event) {
        if (event.kind != PointerDeviceKind.mouse) return;
        setState(() => _hover = true);
      },
      onExit: (_) {
        if (_hover) setState(() => _hover = false);
      },
      child: AnimatedContainer(
        duration: reduceMotion ? Duration.zero : const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
        width: double.infinity,
        transform: Matrix4.translationValues(
          0,
          !widget.embedded && _hover && !reduceMotion ? -6 : 0,
          0,
        ),
        padding: EdgeInsets.fromLTRB(
          widget.embedded ? 4 : (compact ? 16 : 22),
          widget.embedded ? 4 : (compact ? 16 : 22),
          widget.embedded ? 4 : (compact ? 16 : 22),
          widget.embedded ? 0 : (compact ? 16 : 20),
        ),
        decoration: widget.embedded
            ? const BoxDecoration(color: Colors.transparent)
            : BoxDecoration(
          color: Colors.white.withValues(alpha: _hover ? 0.96 : 0.92),
          borderRadius: BorderRadius.circular(28),
          border: Border.all(
            color: widget.highlighted
                ? _orange.withValues(alpha: 0.7)
                : Colors.white.withValues(alpha: 0.8),
          ),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF0F172A).withValues(
                alpha: _hover ? 0.20 : 0.12,
              ),
              blurRadius: _hover ? 28 : 18,
              offset: Offset(0, _hover ? 14 : 8),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: compact ? 48 : 54,
              height: compact ? 48 : 54,
              decoration: BoxDecoration(
                color: _orange,
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: _orange.withValues(alpha: 0.35),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Icon(widget.icon, color: Colors.white, size: compact ? 26 : 28),
            ),
            SizedBox(height: compact ? 12 : 14),
            Text(
              widget.title,
              style: GoogleFonts.montserrat(
                color: _orange,
                fontSize: compact ? 22 : 26,
                fontWeight: FontWeight.w800,
                height: 1.1,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              widget.body,
              style: TextStyle(
                color: const Color(0xFF334155),
                fontSize: compact ? 14 : 15,
                height: 1.5,
                fontWeight: FontWeight.w500,
              ),
            ),
            SizedBox(height: compact ? 12 : 14),
            for (final point in widget.points)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Padding(
                      padding: EdgeInsets.only(top: 1),
                      child: Icon(
                        Icons.check_circle_rounded,
                        color: _orange,
                        size: 18,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        point,
                        style: TextStyle(
                          color: _navy,
                          fontSize: compact ? 13 : 14,
                          fontWeight: FontWeight.w600,
                          height: 1.3,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            SizedBox(height: compact ? 8 : 12),
            _ExperienceGradientButton(
              label: widget.buttonLabel,
              onPressed: widget.onPressed,
            ),
          ],
        ),
      ),
    );
  }
}

class _ExperienceGradientButton extends StatefulWidget {
  const _ExperienceGradientButton({
    required this.label,
    required this.onPressed,
  });

  final String label;
  final VoidCallback onPressed;

  @override
  State<_ExperienceGradientButton> createState() =>
      _ExperienceGradientButtonState();
}

class _ExperienceGradientButtonState extends State<_ExperienceGradientButton> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    return MouseRegion(
      onEnter: (event) {
        if (event.kind != PointerDeviceKind.mouse) return;
        setState(() => _hover = true);
      },
      onExit: (_) {
        if (_hover) setState(() => _hover = false);
      },
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: widget.onPressed,
        child: AnimatedScale(
          scale: _hover && !reduceMotion ? 1.03 : 1,
          duration: reduceMotion
              ? Duration.zero
              : const Duration(milliseconds: 180),
          curve: Curves.easeOutCubic,
          child: AnimatedContainer(
            duration: reduceMotion
                ? Duration.zero
                : const Duration(milliseconds: 180),
            width: double.infinity,
            constraints: const BoxConstraints(minHeight: 46),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: _hover
                    ? const [Color(0xFFFFB057), Color(0xFFFF6A00)]
                    : const [Color(0xFFFF9A3C), Color(0xFFF97316)],
              ),
              borderRadius: BorderRadius.circular(999),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFFF97316).withValues(
                    alpha: _hover ? 0.45 : 0.28,
                  ),
                  blurRadius: _hover ? 16 : 10,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Flexible(
                  child: Text(
                    widget.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.montserrat(
                      color: Colors.white,
                      fontSize: 14.5,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                const Icon(
                  Icons.arrow_forward_rounded,
                  color: Colors.white,
                  size: 18,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ExperiencePreview {
  const _ExperiencePreview({
    required this.title,
    required this.explanation,
    required this.assets,
    this.aspect = 878 / 1791,
  });

  final String title;
  final String explanation;
  final List<String> assets;
  final double aspect;
}

class _ExperiencePhoneMotion extends StatefulWidget {
  const _ExperiencePhoneMotion({
    required this.asset,
    required this.height,
    required this.framed,
    required this.motionIndex,
    required this.onTap,
    this.aspect = 878 / 1791,
  });

  final String asset;
  final double height;
  final bool framed;
  final double aspect;
  final int motionIndex;
  final VoidCallback onTap;

  @override
  State<_ExperiencePhoneMotion> createState() => _ExperiencePhoneMotionState();
}

class _ExperiencePhoneMotionState extends State<_ExperiencePhoneMotion>
    with TickerProviderStateMixin {
  late final AnimationController _float;
  late final AnimationController _hover;
  late final AnimationController _reveal;

  ScrollPosition? _position;
  final ValueNotifier<Offset> _tilt = ValueNotifier<Offset>(Offset.zero);
  double _screenHeight = 800;
  bool _reduceMotion = false;
  bool _revealed = false;
  bool _hovering = false;

  double get _phase => widget.motionIndex == 0 ? 0 : 0.42;
  double get _amplitude => widget.motionIndex == 0 ? 6 : 8;

  @override
  void initState() {
    super.initState();
    _float = AnimationController(
      vsync: this,
      duration: Duration(milliseconds: widget.motionIndex == 0 ? 3600 : 4500),
    );
    _hover = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 280),
    );
    _reveal = AnimationController(
      vsync: this,
      duration: Duration(milliseconds: 680 + widget.motionIndex * 140),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) => _onScroll());
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _screenHeight = MediaQuery.sizeOf(context).height;
    final reduce = MediaQuery.disableAnimationsOf(context);
    if (reduce != _reduceMotion) {
      _reduceMotion = reduce;
      if (reduce) {
        _float.stop();
        _hover.value = 0;
        _tilt.value = Offset.zero;
        _reveal.value = 1;
        _revealed = true;
      }
    }
    final next = Scrollable.maybeOf(context)?.position;
    if (!identical(next, _position)) {
      _position?.removeListener(_onScroll);
      _position = next;
      _position?.addListener(_onScroll);
    }
  }

  @override
  void dispose() {
    _position?.removeListener(_onScroll);
    _tilt.dispose();
    _float.dispose();
    _hover.dispose();
    _reveal.dispose();
    super.dispose();
  }

  bool _isInView() {
    final box = context.findRenderObject();
    if (box is! RenderBox || !box.hasSize || !box.attached) return false;
    final top = box.localToGlobal(Offset.zero).dy;
    final bottom = top + box.size.height;
    return bottom > 48 && top < _screenHeight - 48;
  }

  void _onScroll() {
    if (!mounted) return;
    final visible = _isInView();
    if (visible) _playReveal();
    if (_reduceMotion) {
      _float.stop();
      return;
    }
    if (visible && _revealed) {
      if (!_float.isAnimating) _float.repeat();
    } else {
      _float.stop();
    }
  }

  void _playReveal() {
    if (_revealed) return;
    _revealed = true;
    if (_reduceMotion) {
      _reveal.value = 1;
      return;
    }
    _reveal.forward(from: 0);
  }

  void _onHover(PointerHoverEvent event) {
    if (_reduceMotion || event.kind != PointerDeviceKind.mouse) return;
    final box = context.findRenderObject();
    if (box is! RenderBox || !box.hasSize) return;
    final local = box.globalToLocal(event.position);
    final dx = ((local.dx / box.size.width) - 0.5).clamp(-0.5, 0.5);
    final dy = ((local.dy / box.size.height) - 0.5).clamp(-0.5, 0.5);
    _tilt.value = Offset(-dy * 0.10, dx * 0.16);
    if (!_hovering) {
      _hovering = true;
      _hover.forward();
    }
  }

  void _onExit(PointerExitEvent event) {
    if (!_hovering && _tilt.value == Offset.zero) return;
    _hovering = false;
    _tilt.value = Offset.zero;
    _hover.reverse();
  }

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onHover: _onHover,
      onExit: _onExit,
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: widget.onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: AnimatedBuilder(
            animation: Listenable.merge([_float, _hover, _reveal, _tilt]),
            builder: (context, child) {
              final revealT = Curves.easeOutCubic.transform(_reveal.value);
              final hoverT = _hover.value;
              final floatY = _reduceMotion
                  ? 0.0
                  : math.sin((_float.value + _phase) * math.pi * 2) *
                      _amplitude;
              final scale = 1 + (0.035 * hoverT);
              final tilt = _tilt.value;
              final transform = Matrix4.identity()
                ..setEntry(3, 2, 0.0012)
                ..rotateX(tilt.dx * hoverT)
                ..rotateY(tilt.dy * hoverT)
                ..scaleByDouble(scale, scale, 1, 1);
              Widget phone = Transform(
                alignment: Alignment.center,
                filterQuality: FilterQuality.medium,
                transform: transform,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(widget.height * 0.08),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFF0F172A).withValues(
                          alpha: 0.08 + (0.10 * hoverT),
                        ),
                        blurRadius: 18 + (16 * hoverT),
                        offset: Offset(0, 10 + (6 * hoverT)),
                      ),
                    ],
                  ),
                  child: child,
                ),
              );
              phone = Transform.translate(
                offset: Offset(0, ((1 - revealT) * 32) + floatY),
                child: phone,
              );
              if (revealT < 1) {
                phone = Opacity(opacity: revealT, child: phone);
              }
              return phone;
            },
            child: RepaintBoundary(
              child: _LandingPhonePreview(
                asset: widget.asset,
                height: widget.height,
                framed: widget.framed,
                aspect: widget.aspect,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _LandingPhonePreview extends StatelessWidget {
  const _LandingPhonePreview({
    required this.asset,
    required this.height,
    required this.framed,
    this.aspect = 878 / 1791,
  });

  final String asset;
  final double height;
  final bool framed;
  final double aspect;

  static const double _shotAspect = 1080 / 2400;

  @override
  Widget build(BuildContext context) {
    if (!framed) {
      final width = height * aspect;
      return Container(
        width: width,
        height: height,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(height * 0.055),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.16),
              blurRadius: 22,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: Image.asset(
          asset,
          width: width,
          height: height,
          fit: BoxFit.contain,
          filterQuality: FilterQuality.high,
          gaplessPlayback: true,
        ),
      );
    }

    const bezel = 8.0;
    final screenHeight = height - bezel * 2;
    final screenWidth = screenHeight * _shotAspect;
    return Container(
      width: screenWidth + bezel * 2,
      height: height,
      padding: const EdgeInsets.all(bezel),
      decoration: BoxDecoration(
        color: const Color(0xFF161616),
        borderRadius: BorderRadius.circular(height * 0.055),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.16),
            blurRadius: 22,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(height * 0.042),
        child: Image.asset(
          asset,
          width: screenWidth,
          height: screenHeight,
          fit: BoxFit.fill,
          filterQuality: FilterQuality.high,
          gaplessPlayback: true,
        ),
      ),
    );
  }
}

class _ExperiencePreviewDialog extends StatefulWidget {
  const _ExperiencePreviewDialog({required this.preview});

  final _ExperiencePreview preview;

  @override
  State<_ExperiencePreviewDialog> createState() =>
      _ExperiencePreviewDialogState();
}

class _ExperiencePreviewDialogState extends State<_ExperiencePreviewDialog> {
  static const Color _orange = Color(0xFFF97316);
  static const Color _title = Color(0xFF192334);
  static const Color _muted = Color(0xFF64748B);

  int _index = 0;

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final compact = size.width < 600;
    final assets = widget.preview.assets;
    final canPage = assets.length > 1;
    final phoneHeight = (size.height * (compact ? 0.52 : 0.62)).clamp(
      320.0,
      640.0,
    );

    return Dialog(
      backgroundColor: Colors.white,
      surfaceTintColor: Colors.transparent,
      insetPadding: EdgeInsets.symmetric(
        horizontal: compact ? 12 : 24,
        vertical: compact ? 16 : 24,
      ),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
      clipBehavior: Clip.antiAlias,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 560,
          maxHeight: size.height * 0.92,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: EdgeInsets.fromLTRB(compact ? 16 : 22, 14, 8, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      widget.preview.title,
                      style: const TextStyle(
                        color: _title,
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Close',
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close_rounded, color: _muted),
                  ),
                ],
              ),
            ),
            ConstrainedBox(
              constraints: BoxConstraints(maxHeight: size.height * 0.76),
              child: SingleChildScrollView(
                padding: EdgeInsets.fromLTRB(
                  compact ? 16 : 22,
                  0,
                  compact ? 16 : 22,
                  20,
                ),
                child: Column(
                  children: [
                    Center(
                      child: _LandingPhonePreview(
                        asset: assets[_index],
                        height: phoneHeight,
                        framed: false,
                        aspect: widget.preview.aspect,
                      ),
                    ),
                    if (canPage) ...[
                      const SizedBox(height: 12),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          IconButton(
                            tooltip: 'Previous screenshot',
                            onPressed: _index == 0
                                ? null
                                : () => setState(() => _index -= 1),
                            icon: const Icon(Icons.chevron_left_rounded),
                          ),
                          Text(
                            '${_index + 1} / ${assets.length}',
                            style: const TextStyle(
                              color: _muted,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          IconButton(
                            tooltip: 'Next screenshot',
                            onPressed: _index == assets.length - 1
                                ? null
                                : () => setState(() => _index += 1),
                            icon: const Icon(Icons.chevron_right_rounded),
                          ),
                        ],
                      ),
                    ],
                    const SizedBox(height: 14),
                    Text(
                      widget.preview.explanation,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Color(0xFF475569),
                        fontSize: 14,
                        height: 1.55,
                      ),
                    ),
                    const SizedBox(height: 16),
                    TextButton(
                      onPressed: () => Navigator.of(context).pop(),
                      style: TextButton.styleFrom(foregroundColor: _orange),
                      child: const Text(
                        'Close',
                        style: TextStyle(fontWeight: FontWeight.w700),
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
}

class _LandingFaqDialog extends StatelessWidget {
  const _LandingFaqDialog();

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final compact = size.width < 600;
    return Dialog(
      backgroundColor: Colors.white,
      surfaceTintColor: Colors.transparent,
      insetPadding: EdgeInsets.symmetric(
        horizontal: compact ? 12 : 28,
        vertical: compact ? 16 : 28,
      ),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 680,
          maxHeight: size.height * 0.86,
        ),
        child: Column(
          children: [
            Padding(
              padding: EdgeInsets.fromLTRB(compact ? 16 : 20, 10, 6, 8),
      child: Row(
        children: [
          Container(
                    width: 36,
                    height: 36,
            decoration: BoxDecoration(
                      color: const Color(0xFFF97316).withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(10),
            ),
            alignment: Alignment.center,
            child: const Icon(
              Icons.help_outline_rounded,
                      color: Color(0xFFF97316),
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                  'Frequently Asked Questions',
                  style: TextStyle(
                        color: const Color(0xFF192334),
                        fontSize: compact ? 16 : 18,
                        fontWeight: FontWeight.w800,
                        height: 1.2,
                      ),
            ),
          ),
          IconButton(
            tooltip: 'Close',
            onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(
                      Icons.close_rounded,
                      color: Color(0xFF64748B),
                    ),
                  ),
                ],
              ),
            ),
            const Divider(height: 1, color: Color(0xFFEEF1F5)),
            const Expanded(
              child: SingleChildScrollView(
                padding: EdgeInsets.fromLTRB(12, 14, 12, 18),
                child: _LandingFaqAccordion(),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LandingFaqAccordion extends StatefulWidget {
  const _LandingFaqAccordion();

  @override
  State<_LandingFaqAccordion> createState() => _LandingFaqAccordionState();
}

class _LandingFaqAccordionState extends State<_LandingFaqAccordion> {
  static const Color _orange = Color(0xFFF97316);
  static const Color _title = Color(0xFF192334);
  static const Color _muted = Color(0xFF64748B);
  static const Color _border = Color(0xFFEEF1F5);

  int? _expandedIndex = 0;

  @override
  Widget build(BuildContext context) {
    final compact = MediaQuery.sizeOf(context).width < 600;
    return ListView.separated(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      padding: EdgeInsets.symmetric(horizontal: compact ? 0 : 8),
      itemCount: kAppFaqItems.length,
      separatorBuilder: (_, _) => const SizedBox(height: 10),
      itemBuilder: (context, i) => _buildItem(i, kAppFaqItems[i]),
    );
  }

  Widget _buildItem(int index, AppFaqItem item) {
    final expanded = _expandedIndex == index;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOutCubic,
      decoration: BoxDecoration(
        color: expanded ? const Color(0xFFFFFBF7) : Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: expanded ? _orange.withValues(alpha: 0.28) : _border,
        ),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: () => setState(() => _expandedIndex = expanded ? null : index),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 14, 10, 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 34,
                      height: 34,
                      decoration: BoxDecoration(
                        color: _orange.withValues(alpha: 0.10),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      alignment: Alignment.center,
                      child: Icon(item.icon, color: _orange, size: 18),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        item.question,
                        style: const TextStyle(
                          color: _title,
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          height: 1.35,
                        ),
                      ),
                    ),
                    AnimatedRotation(
                      turns: expanded ? 0.5 : 0,
                      duration: const Duration(milliseconds: 200),
                      child: Icon(
                        Icons.keyboard_arrow_down_rounded,
                        color: expanded ? _orange : _muted,
                      ),
                    ),
                  ],
                ),
                AnimatedSize(
                  duration: const Duration(milliseconds: 200),
                  curve: Curves.easeOutCubic,
                  alignment: Alignment.topCenter,
                  child: expanded
                      ? Padding(
                          padding: const EdgeInsets.fromLTRB(46, 10, 8, 0),
                          child: Text(
                            item.answer,
                            style: const TextStyle(
                              color: Color(0xFF475569),
                              fontSize: 14,
                              height: 1.6,
                            ),
                          ),
                        )
                      : const SizedBox(width: double.infinity),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ExperienceMergedPanel extends StatelessWidget {
  const _ExperienceMergedPanel({required this.phone, required this.info});

  final Widget phone;
  final Widget info;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(14, 16, 16, 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: const Color(0xFFF4D5C2)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x140F172A),
            blurRadius: 18,
            offset: Offset(0, 8),
          ),
        ],
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final sideBySide = constraints.maxWidth >= 560;
          if (!sideBySide) {
            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                phone,
                const SizedBox(height: 8),
                info,
              ],
            );
          }
          return Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              phone,
              const SizedBox(width: 8),
              Expanded(child: info),
            ],
          );
        },
      ),
    );
  }
}

class _ExperienceSectionPainter extends CustomPainter {
  const _ExperienceSectionPainter();

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(
      Offset.zero & size,
      Paint()..color = const Color(0xFFFFF8F4),
    );
    final wave = Path()
      ..moveTo(0, size.height * 0.86)
      ..quadraticBezierTo(
        size.width * 0.25,
        size.height * 0.78,
        size.width * 0.5,
        size.height * 0.88,
      )
      ..quadraticBezierTo(
        size.width * 0.78,
        size.height,
        size.width,
        size.height * 0.84,
      )
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();
    canvas.drawPath(wave, Paint()..color = const Color(0xFFFFE4CC));
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _DestinationsBackdropPainter extends CustomPainter {
  const _DestinationsBackdropPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final wash = Paint()..color = const Color(0xFFFFF8F4);
    canvas.drawRect(Offset.zero & size, wash);

    final hill = Paint()..color = const Color(0xFFFFE8D6);
    final path = Path()
      ..moveTo(0, size.height * 0.92)
      ..quadraticBezierTo(
        size.width * 0.22,
        size.height * 0.78,
        size.width * 0.48,
        size.height * 0.9,
      )
      ..quadraticBezierTo(
        size.width * 0.74,
        size.height * 1.02,
        size.width,
        size.height * 0.82,
      )
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();
    canvas.drawPath(path, hill);

    final dot = Paint()..color = const Color(0x33F97316);
    for (var i = 0; i < 8; i++) {
      canvas.drawCircle(
        Offset(size.width * (0.08 + i * 0.12), 36 + (i.isEven ? 10 : 28)),
        i.isEven ? 3 : 2,
        dot,
      );
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// Orange hero download actions. Same APK callbacks as before; presentation only.
class _HeroApkDownloadSection extends StatefulWidget {
  const _HeroApkDownloadSection({
    required this.centered,
    required this.compact,
    required this.color,
    required this.onDownloadVrTour,
    required this.onDownloadTripPlanner,
  });

  final bool centered;
  final bool compact;
  final Color color;
  final VoidCallback onDownloadVrTour;
  final VoidCallback onDownloadTripPlanner;

  @override
  State<_HeroApkDownloadSection> createState() => _HeroApkDownloadSectionState();
}

class _HeroApkDownloadSectionState extends State<_HeroApkDownloadSection>
    with TickerProviderStateMixin {
  late final AnimationController _arrow;
  late final AnimationController _caption;
  bool _captionStarted = false;

  @override
  void initState() {
    super.initState();
    _arrow = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
    _caption = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 720),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final reduce = MediaQuery.disableAnimationsOf(context);
    if (reduce) {
      _arrow.stop();
      _arrow.value = 0;
      _caption.value = 1;
      return;
    }
    if (!_arrow.isAnimating) {
      _arrow.repeat(reverse: true);
    }
    if (!_captionStarted) {
      _captionStarted = true;
      _caption.forward();
    }
  }

  @override
  void dispose() {
    _arrow.dispose();
    _caption.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final gap = widget.compact ? 10.0 : 12.0;
    return Column(
      crossAxisAlignment: widget.centered
          ? CrossAxisAlignment.center
          : CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: gap,
          runSpacing: gap,
          alignment: widget.centered
              ? WrapAlignment.center
              : WrapAlignment.start,
          children: [
            _HeroApkDownloadButton(
              label: 'Download VR Tour App',
              color: widget.color,
              compact: widget.compact,
              arrow: _arrow,
              onPressed: widget.onDownloadVrTour,
            ),
            _HeroApkDownloadButton(
              label: 'Download Trip Planner App',
              color: widget.color,
              compact: widget.compact,
              arrow: _arrow,
              onPressed: widget.onDownloadTripPlanner,
            ),
          ],
        ),
        const SizedBox(height: 10),
        FadeTransition(
          opacity: CurvedAnimation(parent: _caption, curve: Curves.easeOut),
          child: Text(
            'Download the app to get started',
            textAlign: widget.centered ? TextAlign.center : TextAlign.start,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.92),
              fontSize: widget.compact ? 12.5 : 13,
              fontWeight: FontWeight.w500,
              letterSpacing: 0.15,
              height: 1.3,
              shadows: const [
                Shadow(
                  color: Color(0x99000000),
                  blurRadius: 8,
                  offset: Offset(0, 1),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// Header wordmark only. Subtitle and logo stay on the existing styles.
class _LandingHeaderWordmark extends StatelessWidget {
  const _LandingHeaderWordmark({required this.fontSize});

  final double fontSize;

  static const Color _atmos = Color(0xFF222222);
  static const Color _trs = Color(0xFFFF7518);

  @override
  Widget build(BuildContext context) {
    final base = AtmosBrandTypography.landingAppMark(
      color: _atmos,
      fontSize: fontSize,
    );
    return Text.rich(
      TextSpan(
        children: [
          const TextSpan(text: 'ATMOS'),
          const TextSpan(text: '\u2013'),
          TextSpan(text: 'TRS', style: base.copyWith(color: _trs)),
        ],
      ),
      style: base,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      textAlign: TextAlign.start,
    );
  }
}

class _HeroApkDownloadButton extends StatefulWidget {
  const _HeroApkDownloadButton({
    required this.label,
    required this.color,
    required this.compact,
    required this.arrow,
    required this.onPressed,
  });

  final String label;
  final Color color;
  final bool compact;
  final Animation<double> arrow;
  final VoidCallback onPressed;

  @override
  State<_HeroApkDownloadButton> createState() => _HeroApkDownloadButtonState();
}

class _HeroApkDownloadButtonState extends State<_HeroApkDownloadButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final reduce = MediaQuery.disableAnimationsOf(context);
    final hovering = _hovered && !reduce;
    final horizontal = widget.compact ? 16.0 : 18.0;

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      cursor: SystemMouseCursors.click,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOutCubic,
        transform: Matrix4.translationValues(0, hovering ? -3 : 0, 0),
        transformAlignment: Alignment.center,
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: widget.color,
          borderRadius: BorderRadius.circular(999),
          boxShadow: [
            BoxShadow(
              color: widget.color.withValues(alpha: hovering ? 0.5 : 0.34),
              blurRadius: hovering ? 18 : 10,
              offset: Offset(0, hovering ? 8 : 4),
            ),
          ],
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: widget.onPressed,
            borderRadius: BorderRadius.circular(999),
            hoverColor: Colors.white.withValues(alpha: 0.08),
            splashColor: Colors.white.withValues(alpha: 0.16),
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 44, minWidth: 44),
              child: Padding(
                padding: EdgeInsets.symmetric(
                  horizontal: horizontal,
                  vertical: 12,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    AnimatedBuilder(
                      animation: widget.arrow,
                      builder: (context, child) {
                        final travel = reduce
                            ? 0.0
                            : widget.arrow.value * (hovering ? 6.0 : 3.5);
                        return Transform.translate(
                          offset: Offset(0, travel),
                          child: child,
                        );
                      },
                      child: const Icon(
                        Icons.arrow_downward_rounded,
                        color: Colors.white,
                        size: 18,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      widget.label,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                        fontSize: 14,
                        height: 1.1,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

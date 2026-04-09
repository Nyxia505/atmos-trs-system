import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:atmos_trs_system/features/navigation/placeholder_pages.dart'
    show ScanTabPage;
import 'package:atmos_trs_system/services/app_welcome_prefs.dart';
import 'package:atmos_trs_system/widgets/new_user_welcome_dialog.dart';
import 'package:atmos_trs_system/screens/itinerary_page.dart';
import 'package:atmos_trs_system/screens/vr_webview_screen.dart';
import 'package:atmos_trs_system/utils/logo_utils.dart';

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

  String? _activeSection;

  final GlobalKey _keyHome = GlobalKey();
  final GlobalKey _keyChooseExperience = GlobalKey();
  final GlobalKey _keyFeatures = GlobalKey();
  final GlobalKey _keyDestinations = GlobalKey();
  final GlobalKey _keyHowItWorks = GlobalKey();
  final GlobalKey _keyAbout = GlobalKey();

  static const Color _primaryOrange = Color(0xFFF97316);
  static const Color _darkBg = Color(0xFF0F172A);
  static const Color _accentOrange = Color(0xFFFB923C);

  static const String _kAtmosTrsFullName =
      'Asenso Tourismo Misamis Occidental Smart Tourist Registration System';

  /// Soft tinted card backgrounds + accents (Asenso orange / cream family).
  final List<Map<String, dynamic>> _features = [
    {
      'icon': Icons.qr_code_rounded,
      'title': 'QR Code Registration',
      'description':
          'Quick and easy tourist registration with unique QR code identification',
      'bgStart': const Color(0xFFEFF6FF),
      'bgEnd': const Color(0xFFDBEAFE),
      'accent': const Color(0xFF2563EB),
    },
    {
      'icon': Icons.vrpano_rounded,
      'title': 'Virtual Reality Tours',
      'description':
          'Explore destinations in immersive 360° VR before you visit',
      'bgStart': const Color(0xFFF5F3FF),
      'bgEnd': const Color(0xFFEDE9FE),
      'accent': const Color(0xFF7C3AED),
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
      'bgStart': const Color(0xFFFFF1F2),
      'bgEnd': const Color(0xFFFFE4E6),
      'accent': const Color(0xFFE11D48),
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
      'image': 'assets/images/AMORAP.jpg',
      'isAsset': 'true',
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
          'Overwater villas, winding piers, and lush coastal scenery by the water',
      'image': 'assets/images/sinacaban.jpg',
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

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _maybeShowNewUserWelcome();
    });
  }

  Future<void> _maybeShowNewUserWelcome() async {
    final show = await AppWelcomePrefs.shouldShowLandingWelcome();
    if (!mounted || !show) return;
    await showNewUserWelcomeDialog(context);
    if (mounted) await AppWelcomePrefs.markLandingWelcomeShown();
  }

  void _onScroll(double offset) {
    if (!mounted) return;

    final h = MediaQuery.of(context).size.height;

    final bool newIsScrolled = offset > 50;
    String? newActive;

    if (offset < h * 0.85) {
      newActive = 'home';
    } else if (offset < h * 1.35) {
      newActive = 'chooseExperience';
    } else if (offset < h * 2.35) {
      newActive = 'features';
    } else if (offset < h * 3.35) {
      newActive = 'destinations';
    } else if (offset < h * 4.4) {
      newActive = 'howItWorks';
    } else {
      newActive = 'about';
    }

    if (newIsScrolled != _isScrolled || newActive != _activeSection) {
      setState(() {
        _isScrolled = newIsScrolled;
        _activeSection = newActive;
      });
    }
  }

  @override
  void dispose() {
    _heroAnimationController.dispose();
    _fadeController.dispose();
    super.dispose();
  }

  bool get _isMobile => MediaQuery.of(context).size.width < 768;
  bool get _isTablet =>
      MediaQuery.of(context).size.width >= 768 &&
      MediaQuery.of(context).size.width < 1024;

  void _requireAuthThen(VoidCallback onLoggedIn) {
    if (FirebaseAuth.instance.currentUser != null) {
      onLoggedIn();
      return;
    }
    Navigator.pushNamed(context, '/login');
  }

  void _scrollToSection(String section) {
    GlobalKey? key;
    switch (section) {
      case 'home':
        key = _keyHome;
        break;
      case 'chooseExperience':
        key = _keyChooseExperience;
        break;
      case 'features':
        key = _keyFeatures;
        break;
      case 'destinations':
        key = _keyDestinations;
        break;
      case 'howItWorks':
        key = _keyHowItWorks;
        break;
      case 'about':
        key = _keyAbout;
        break;
    }

    final targetContext = key?.currentContext;
    if (targetContext != null && targetContext.mounted) {
      Scrollable.ensureVisible(
        targetContext,
        duration: const Duration(milliseconds: 600),
        curve: Curves.easeInOut,
        alignment: 0.15,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _darkBg,
      extendBodyBehindAppBar: true,
      appBar: _buildAppBar(),
      drawer: _isMobile ? _buildNavDrawer() : null,
      body: NotificationListener<ScrollNotification>(
        onNotification: (notification) {
          if (notification.metrics.axis == Axis.vertical) {
            _onScroll(notification.metrics.pixels);
          }
          return false;
        },
        child: SingleChildScrollView(
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
    final barHeight = _isMobile ? 100.0 : 78.0;
    return PreferredSize(
      preferredSize: Size.fromHeight(barHeight),
      child: Container(
        decoration: BoxDecoration(
          color: _primaryOrange,
          border: Border(
            bottom: BorderSide(color: Colors.orange.shade800, width: 3),
          ),
        ),
        child: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          toolbarHeight: barHeight,
          leadingWidth: 0,
          leading: const SizedBox.shrink(),
          titleSpacing: 0,
          title: Padding(
            padding: const EdgeInsets.only(left: 16),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.22),
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.08),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: SizedBox(
                    height: 40,
                    width: 40,
                    child: TransparentLogo(
                      height: 40,
                      width: 40,
                      fit: BoxFit.contain,
                      errorIcon: Icons.travel_explore_rounded,
                      errorIconSize: 26,
                      errorIconColor: Colors.white,
                    ),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text(
                        'ATMOS TRS',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 20,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.5,
                        ),
                      ),
                      Text(
                        _kAtmosTrsFullName,
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.92),
                          fontSize: _isMobile ? 9.5 : 11,
                          fontWeight: FontWeight.w500,
                          height: 1.25,
                          letterSpacing: 0.15,
                        ),
                        maxLines: _isMobile ? 4 : 3,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                if (_isMobile)
                  Builder(
                    builder: (context) => IconButton(
                      icon: const Icon(Icons.menu_rounded, color: Colors.white),
                      onPressed: () => Scaffold.of(context).openDrawer(),
                    ),
                  )
                else ...[
                  const Spacer(),
                  _buildNavButton(
                    'Home',
                    () => _scrollToSection('home'),
                    _activeSection == 'home',
                  ),
                  _buildNavButton(
                    'Experience',
                    () => _scrollToSection('chooseExperience'),
                    _activeSection == 'chooseExperience',
                  ),
                  _buildNavButton(
                    'Features',
                    () => _scrollToSection('features'),
                    _activeSection == 'features',
                  ),
                  _buildNavButton(
                    'Destinations',
                    () => _scrollToSection('destinations'),
                    _activeSection == 'destinations',
                  ),
                  _buildNavButton(
                    'How It Works',
                    () => _scrollToSection('howItWorks'),
                    _activeSection == 'howItWorks',
                  ),
                  _buildNavButton(
                    'About',
                    () => _scrollToSection('about'),
                    _activeSection == 'about',
                  ),
                  const SizedBox(width: 8),
                  TextButton(
                    onPressed: () => Navigator.of(context).pushNamed('/login'),
                    style: TextButton.styleFrom(
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
                    ),
                    child: const Text(
                      'Sign in',
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 15,
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.only(right: 12),
                    child: FilledButton(
                      onPressed: () =>
                          Navigator.of(context).pushNamed('/signup'),
                      style: FilledButton.styleFrom(
                        backgroundColor: Colors.white,
                        foregroundColor: _primaryOrange,
                        elevation: 2,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 18,
                          vertical: 12,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: const Text(
                        'Create account',
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 14,
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
          actions: const [],
        ),
      ),
    );
  }

  Widget _buildNavButton(
    String label,
    VoidCallback onTap, [
    bool isActive = false,
  ]) {
    return TextButton(
      onPressed: onTap,
      style: TextButton.styleFrom(
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: Colors.white,
          fontSize: 15,
          fontWeight: isActive ? FontWeight.w700 : FontWeight.w600,
          height: 1.2,
          letterSpacing: 0.2,
          decoration: isActive ? TextDecoration.underline : null,
          decorationColor: Colors.white,
          decorationThickness: 2,
          shadows: const [
            Shadow(
              offset: Offset(0, 1),
              blurRadius: 2,
              color: Color(0x55000000),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNavDrawer() {
    final navItems = [
      ('Home', 'home', () => _scrollToSection('home')),
      (
        'Experience',
        'chooseExperience',
        () => _scrollToSection('chooseExperience'),
      ),
      ('Features', 'features', () => _scrollToSection('features')),
      ('Destinations', 'destinations', () => _scrollToSection('destinations')),
      ('How It Works', 'howItWorks', () => _scrollToSection('howItWorks')),
      ('About', 'about', () => _scrollToSection('about')),
    ];

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
                      const Text(
                        'ATMOS TRS',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 20,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.5,
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
            ...navItems.map((e) {
              final isActive = _activeSection == e.$2;
              return ListTile(
                leading: Icon(
                  Icons.arrow_forward_ios_rounded,
                  size: 14,
                  color: isActive ? _primaryOrange : Colors.grey.shade600,
                ),
                title: Text(
                  e.$1,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: isActive ? FontWeight.w700 : FontWeight.w600,
                    height: 1.2,
                    letterSpacing: 0.15,
                    color: isActive ? _primaryOrange : _darkBg,
                    decoration: isActive ? TextDecoration.underline : null,
                    decorationColor: _primaryOrange,
                    decorationThickness: 2,
                  ),
                ),
                onTap: () {
                  Navigator.pop(context);
                  e.$3();
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
                        Navigator.pop(context);
                        Navigator.pushNamed(context, '/login');
                      },
                      style: OutlinedButton.styleFrom(
                        foregroundColor: _primaryOrange,
                        side: const BorderSide(color: _primaryOrange),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                      child: const Text('Sign In'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton(
                      onPressed: () {
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
    const kHeroImage = 'assets/images/Orquieta Plaza.png';

    return SizedBox(
      height: h,
      width: double.infinity,
      child: Stack(
        fit: StackFit.expand,
        children: [
          Image.asset(
            kHeroImage,
            fit: BoxFit.cover,
            alignment: Alignment.center,
            errorBuilder: (_, __, ___) => Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [Color(0xFF1E293B), Color(0xFF0F172A)],
                ),
              ),
            ),
          ),
          Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  const Color(0xFF0F172A).withOpacity(0.45),
                  const Color(0xFF0F172A).withOpacity(0.88),
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
          Center(
            child: FadeTransition(
              opacity: _heroFadeAnimation,
              child: SlideTransition(
                position: _heroSlideAnimation,
                child: Padding(
                  padding: EdgeInsets.symmetric(
                    horizontal: _isMobile ? 22 : 56,
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
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
                          children: [
                            Icon(
                              Icons.travel_explore_rounded,
                              color: _accentOrange,
                              size: 18,
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
                      Text(
                        'Discover Misamis Occidental \nYour journey starts here',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: _isMobile ? 32 : 48,
                          fontWeight: FontWeight.w800,
                          height: 1.12,
                          letterSpacing: -0.6,
                          shadows: const [
                            Shadow(
                              offset: Offset(0, 2),
                              blurRadius: 16,
                              color: Color(0x66000000),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'Register once for a digital tourist ID, QR check-ins at spots, '
                        'VR previews, and trip planning — all in ATMOS TRS.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.88),
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
                            Icons.qr_code_2_rounded,
                            'Digital QR ID',
                          ),
                          _buildHeroChip(
                            Icons.qr_code_scanner_rounded,
                            'Spot check-ins',
                          ),
                          _buildHeroChip(Icons.vrpano_rounded, '360° VR tours'),
                        ],
                      ),
                      const SizedBox(height: 24),
                      Text(
                        'Free to join · Takes only a few minutes',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.72),
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: 28),
                      _buildHeroSearchBarLight(),
                      const SizedBox(height: 24),
                      Text(
                        'Or explore first',
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.55),
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 0.4,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 12,
                        runSpacing: 12,
                        alignment: WrapAlignment.center,
                        children: [
                          _buildHeroOutlineButton(
                            'Start VR Tour',
                            Icons.vrpano_rounded,
                            () => _requireAuthThen(
                              () => openVrTour(context, title: 'VR Tour'),
                            ),
                          ),
                          _buildHeroOutlineButton(
                            'Plan itinerary',
                            Icons.map_rounded,
                            () => _requireAuthThen(() {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (context) => const ItineraryPage(),
                                ),
                              );
                            }),
                          ),
                        ],
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
        ],
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

  Widget _buildHeroOutlineButton(
    String label,
    IconData icon,
    VoidCallback onTap,
  ) {
    return OutlinedButton(
      onPressed: onTap,
      style: OutlinedButton.styleFrom(
        foregroundColor: Colors.white,
        side: BorderSide(color: Colors.white.withOpacity(0.45)),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 18),
          const SizedBox(width: 8),
          Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }

  Widget _buildHeroSearchBarLight() {
    return Container(
      width: _isMobile ? double.infinity : 520,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.12),
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: Colors.white.withOpacity(0.22)),
      ),
      child: Row(
        children: [
          Icon(Icons.search_rounded, color: Colors.white.withOpacity(0.7)),
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
                  cursorColor: Colors.white,
                  style: const TextStyle(color: Colors.white, fontSize: 15),
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
                    contentPadding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                  onSubmitted: (value) {
                    if (value.trim().isNotEmpty) {
                      _scrollToSection('destinations');
                    }
                  },
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRegisterCalloutSection() {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.symmetric(
        horizontal: _isMobile ? 20 : 64,
        vertical: _isMobile ? 28 : 36,
      ),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
          colors: [Color(0xFFFFF7ED), Color(0xFFFFEDD5), Color(0xFFFFF7ED)],
        ),
      ),
      child: _isMobile
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: _primaryOrange.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: const Icon(
                        Icons.celebration_rounded,
                        color: _primaryOrange,
                        size: 26,
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Text(
                        'Ready to explore?',
                        style: TextStyle(
                          color: _darkBg,
                          fontSize: 20,
                          fontWeight: FontWeight.w800,
                          height: 1.2,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Text(
                  'Create your ATMOS TRS account to unlock QR check-ins, your '
                  'tourist profile, and personalized tools for Misamis Occidental.',
                  style: TextStyle(
                    color: Colors.grey.shade700,
                    fontSize: 14,
                    height: 1.45,
                  ),
                ),
                const SizedBox(height: 18),
                FilledButton.icon(
                  onPressed: () => Navigator.of(context).pushNamed('/signup'),
                  style: FilledButton.styleFrom(
                    backgroundColor: _primaryOrange,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                      vertical: 14,
                      horizontal: 20,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  icon: const Icon(Icons.person_add_alt_1_rounded, size: 22),
                  label: const Text(
                    'Register now — it is free',
                    style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
                  ),
                ),
              ],
            )
          : Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: _primaryOrange.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: const Icon(
                    Icons.celebration_rounded,
                    color: _primaryOrange,
                    size: 32,
                  ),
                ),
                const SizedBox(width: 24),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Ready to explore Misamis Occidental?',
                        style: TextStyle(
                          color: _darkBg,
                          fontSize: 24,
                          fontWeight: FontWeight.w800,
                          height: 1.2,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Create your ATMOS TRS account in minutes — get your digital '
                        'tourist ID, QR for check-ins, and access to VR & itinerary tools.',
                        style: TextStyle(
                          color: Colors.grey.shade700,
                          fontSize: 15,
                          height: 1.5,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 24),
                FilledButton.icon(
                  onPressed: () => Navigator.of(context).pushNamed('/signup'),
                  style: FilledButton.styleFrom(
                    backgroundColor: _primaryOrange,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 28,
                      vertical: 18,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  icon: const Icon(Icons.person_add_alt_1_rounded, size: 24),
                  label: const Text(
                    'Register now',
                    style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
                  ),
                ),
              ],
            ),
    );
  }

  Widget _buildChooseYourExperienceSection() {
    final List<Map<String, dynamic>> experienceCards = [
      {
        'title': 'VR Tour',
        'subtitle': 'Explore destinations in immersive 360° preview',
        'icon': Icons.vrpano_rounded,
        'bgStart': const Color(0xFFF5F3FF),
        'bgEnd': const Color(0xFFEDE9FE),
        'accent': const Color(0xFF7C3AED),
        'onTap': () =>
            _requireAuthThen(() => openVrTour(context, title: 'VR Tour')),
      },
      {
        'title': 'Itinerary Planner',
        'subtitle': 'Plan and organize your travel itinerary',
        'icon': Icons.map_rounded,
        'bgStart': const Color(0xFFECFDF5),
        'bgEnd': const Color(0xFFD1FAE5),
        'accent': const Color(0xFF059669),
        'onTap': () => _requireAuthThen(() {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (context) => const ItineraryPage()),
          );
        }),
      },
      {
        'title': 'QR Check-in',
        'subtitle': 'Scan QR codes and record visits',
        'icon': Icons.qr_code_scanner_rounded,
        'bgStart': const Color(0xFFFFF7ED),
        'bgEnd': const Color(0xFFFFEDD5),
        'accent': _primaryOrange,
        'onTap': () {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Register and get your QR code to check in at spots',
              ),
              behavior: SnackBarBehavior.floating,
            ),
          );
          _scrollToSection('howItWorks');
        },
      },
    ];

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: _isMobile ? 24 : 80,
        vertical: 72,
      ),
      color: const Color(0xFFFFF7ED),
      child: Column(
        children: [
          _buildSectionHeader(
            'Choose Your Experience',
            'One platform — explore, plan, and check in across Misamis Occidental',
          ),
          const SizedBox(height: 48),
          LayoutBuilder(
            builder: (context, constraints) {
              final crossCount = _isMobile ? 1 : (_isTablet ? 2 : 3);
              return GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: crossCount,
                  crossAxisSpacing: 24,
                  mainAxisSpacing: 24,
                  childAspectRatio: _isMobile ? 1.75 : 1.35,
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
                    onTap: card['onTap'] as VoidCallback,
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
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [bgStart, bgEnd],
            ),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: accent.withOpacity(0.22)),
            boxShadow: [
              BoxShadow(
                color: accent.withOpacity(0.12),
                blurRadius: 16,
                offset: const Offset(0, 6),
              ),
              BoxShadow(
                color: Colors.black.withOpacity(0.04),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.65),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: accent.withOpacity(0.25)),
                  boxShadow: [
                    BoxShadow(
                      color: accent.withOpacity(0.08),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Icon(icon, color: accent, size: 28),
              ),
              const SizedBox(height: 14),
              Text(
                title,
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: _darkBg,
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 6),
              Flexible(
                child: Text(
                  subtitle,
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Colors.grey.shade600,
                    fontSize: 13,
                    height: 1.35,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFeaturesSection() {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: _isMobile ? 24 : 80,
        vertical: 72,
      ),
      color: const Color(0xFFFFF7ED),
      child: Column(
        children: [
          _buildSectionHeader(
            'Why Choose ATMOS TRS?',
            'Smart registration, VR tours, itinerary planning & QR check-ins — all in one platform',
          ),
          const SizedBox(height: 60),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: _isMobile ? 1 : (_isTablet ? 2 : 4),
              crossAxisSpacing: 24,
              mainAxisSpacing: 24,
              // Mobile: keep cells tall enough for icon + title + 3-line body (2.7 was too flat → overflow).
              childAspectRatio: _isMobile ? 1.15 : (_isTablet ? 1.0 : 0.85),
            ),
            itemCount: _features.length,
            itemBuilder: (context, index) =>
                _buildFeatureCard(index, _features[index]),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title, String subtitle) {
    return Column(
      children: [
        Text(
          title,
          textAlign: TextAlign.center,
          style: TextStyle(
            color: _darkBg,
            fontSize: _isMobile ? 28 : 36,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 16),
        Text(
          subtitle,
          textAlign: TextAlign.center,
          style: TextStyle(color: Colors.grey.shade600, fontSize: 16),
        ),
      ],
    );
  }

  Widget _buildFeatureCard(int index, Map<String, dynamic> feature) {
    final bgStart = feature['bgStart'] as Color;
    final bgEnd = feature['bgEnd'] as Color;
    final accent = feature['accent'] as Color;
    final isHovered = _hoveredFeatureIndex == index;
    final String? route = feature['route'] as String?;

    Widget card = MouseRegion(
      onEnter: (_) => setState(() => _hoveredFeatureIndex = index),
      onExit: (_) => setState(() => _hoveredFeatureIndex = null),
      cursor: SystemMouseCursors.click,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: SizedBox.expand(
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 250),
            curve: Curves.easeOutCubic,
            transform: Matrix4.identity()
              ..translate(0.0, isHovered ? -8.0 : 0.0)
              ..scale(isHovered ? 1.02 : 1.0),
            transformAlignment: Alignment.center,
            padding: EdgeInsets.all(_isMobile ? 20 : 24),
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
              crossAxisAlignment: _isMobile
                  ? CrossAxisAlignment.start
                  : CrossAxisAlignment.center,
              mainAxisAlignment: MainAxisAlignment.start,
              mainAxisSize: MainAxisSize.max,
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
                  textAlign: _isMobile ? TextAlign.start : TextAlign.center,
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
                Expanded(
                  child: Text(
                    feature['description'] as String,
                    textAlign: _isMobile ? TextAlign.start : TextAlign.center,
                    style: TextStyle(
                      color: Colors.grey.shade600,
                      fontSize: 13,
                      height: 1.5,
                    ),
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    if (route == 'itinerary') {
      return GestureDetector(
        onTap: () {
          _requireAuthThen(() {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (context) => const ItineraryPage()),
            );
          });
        },
        child: card,
      );
    }
    return card;
  }

  Widget _buildDestinationsSection() {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: _isMobile ? 24 : 80,
        vertical: 72,
      ),
      color: Colors.grey.shade50,
      child: Column(
        children: [
          _buildSectionHeader(
            'Municipalities & Cities',
            'All 17 locations in Misamis Occidental — discover beaches, heritage, and natural wonders',
          ),
          const SizedBox(height: 60),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: _isMobile ? 1 : (_isTablet ? 2 : 4),
              crossAxisSpacing: 24,
              mainAxisSpacing: 24,
              childAspectRatio: _isMobile ? 1.35 : 0.95,
            ),
            itemCount: _destinations.length,
            itemBuilder: (context, index) =>
                _buildDestinationCard(_destinations[index]),
          ),
        ],
      ),
    );
  }

  Widget _buildDestinationCard(Map<String, String> destination) {
    final isAsset = destination['isAsset'] == 'true';
    final imageUrl = destination['image']!;
    final name = destination['name'] ?? '';
    final category = destination['category'] ?? 'Municipality';

    const fallbackNetworkImage =
        'https://images.unsplash.com/photo-1480714378408-67cf0d13bc1b?w=800';

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withOpacity(0.2),
            blurRadius: 20,
            offset: const Offset(0, 10),
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
                    errorBuilder: (context, error, stackTrace) => Image.network(
                      fallbackNetworkImage,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => _buildPlaceholderImage(),
                    ),
                  )
                : Image.network(
                    imageUrl,
                    fit: BoxFit.cover,
                    errorBuilder: (context, error, stackTrace) =>
                        _buildPlaceholderImage(),
                  ),
            Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Colors.transparent, Colors.black.withOpacity(0.75)],
                ),
              ),
            ),
            Positioned(
              top: 14,
              left: 14,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: _primaryOrange,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  category,
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
              child: Text(
                name,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
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
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: _isMobile ? 24 : 80,
        vertical: 72,
      ),
      color: Colors.white,
      child: Column(
        children: [
          _buildSectionHeader(
            'How It Works',
            'Get started with ATMOS TRS in 5 simple steps',
          ),
          const SizedBox(height: 60),
          _isMobile
              ? Column(
                  children: _steps.asMap().entries.map((entry) {
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 24),
                      child: _buildStepCard(
                        entry.value,
                        entry.key == _steps.length - 1,
                      ),
                    );
                  }).toList(),
                )
              : Row(
                  children: _steps.asMap().entries.map((entry) {
                    return Expanded(
                      child: Row(
                        children: [
                          Expanded(child: _buildStepCard(entry.value, false)),
                          if (entry.key < _steps.length - 1)
                            Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 4,
                              ),
                              child: Icon(
                                Icons.arrow_forward_rounded,
                                color: _primaryOrange,
                                size: 20,
                              ),
                            ),
                        ],
                      ),
                    );
                  }).toList(),
                ),
        ],
      ),
    );
  }

  Widget _buildStepCard(Map<String, dynamic> step, bool isLast) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.grey.shade200),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withOpacity(0.1),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          Container(
            width: 60,
            height: 60,
            decoration: BoxDecoration(
              gradient: LinearGradient(colors: [_primaryOrange, _accentOrange]),
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: _primaryOrange.withOpacity(0.3),
                  blurRadius: 15,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: Icon(
              step['icon'] as IconData,
              color: Colors.white,
              size: 28,
            ),
          ),
          const SizedBox(height: 20),
          Text(
            step['number'] as String,
            style: TextStyle(
              color: _primaryOrange,
              fontSize: 14,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            step['title'] as String,
            style: TextStyle(
              color: _darkBg,
              fontSize: 18,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            step['description'] as String,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.grey.shade600,
              fontSize: 14,
              height: 1.5,
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
      },
      {'value': '15-25', 'label': 'Tourist Spots', 'icon': Icons.place_rounded},
      {
        'value': '17',
        'label': 'Cities & Municipalities',
        'icon': Icons.location_city_rounded,
      },
      {'value': '7', 'label': 'VR Tours', 'icon': Icons.vrpano_rounded},
    ];

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: _isMobile ? 24 : 80,
        vertical: 80,
      ),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [_primaryOrange.withOpacity(0.08), Colors.white],
        ),
      ),
      child: GridView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: _isMobile ? 2 : 4,
          crossAxisSpacing: 24,
          mainAxisSpacing: 24,
          childAspectRatio: _isMobile ? 1.2 : 1.5,
        ),
        itemCount: stats.length,
        itemBuilder: (context, index) {
          final stat = stats[index];
          return Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: _primaryOrange.withOpacity(0.2)),
              boxShadow: [
                BoxShadow(
                  color: _primaryOrange.withOpacity(0.08),
                  blurRadius: 15,
                  offset: const Offset(0, 5),
                ),
              ],
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(stat['icon'] as IconData, color: _primaryOrange, size: 32),
                const SizedBox(height: 12),
                Text(
                  stat['value'] as String,
                  style: TextStyle(
                    color: _darkBg,
                    fontSize: _isMobile ? 24 : 32,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  stat['label'] as String,
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildAboutSection() {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: _isMobile ? 24 : 80,
        vertical: 80,
      ),
      color: Colors.grey.shade50,
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
                  child: const Text(
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
                  style: TextStyle(
                    color: _darkBg,
                    fontSize: _isMobile ? 28 : 36,
                    fontWeight: FontWeight.w800,
                    height: 1.2,
                    letterSpacing: -0.3,
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
                              child: const Icon(
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
        color: const Color(0xFF0A0F1A),
        border: Border(top: BorderSide(color: Colors.white.withOpacity(0.05))),
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
                top: BorderSide(color: Colors.white.withOpacity(0.05)),
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(
                    '2026 © Province of Misamis Occidental',
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.5),
                      fontSize: 13,
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
            color: Colors.white.withOpacity(0.95),
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
              color: Colors.white.withOpacity(0.75),
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
            color: Colors.white.withOpacity(0.95),
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
              color: Colors.white.withOpacity(0.75),
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
            const Text(
              'ATMOS TRS',
              style: TextStyle(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.5,
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Text(
          _kAtmosTrsFullName,
          textAlign: _isMobile ? TextAlign.center : TextAlign.start,
          style: TextStyle(
            color: Colors.white.withOpacity(0.82),
            fontSize: 12,
            fontWeight: FontWeight.w500,
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
                color: Colors.white.withOpacity(0.6),
                fontSize: 14,
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
          Icon(icon, color: _primaryOrange, size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                color: Colors.white.withOpacity(0.6),
                fontSize: 14,
              ),
              softWrap: true,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSocialIcon(IconData icon) {
    return Container(
      margin: const EdgeInsets.only(left: 12),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.05),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Icon(icon, color: Colors.white.withOpacity(0.6), size: 18),
    );
  }
}

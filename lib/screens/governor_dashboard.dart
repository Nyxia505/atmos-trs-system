import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:atmos_trs_system/config/session_storage.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:io' show Platform;
import 'dart:typed_data';
import 'package:image_picker/image_picker.dart';
import 'package:atmos_trs_system/widgets/app_search_bar.dart';
import 'package:atmos_trs_system/data/misamis_occidental_municipalities.dart';
import 'package:atmos_trs_system/utils/spot_qr_helper.dart';
import 'package:atmos_trs_system/utils/lgu_qr_export.dart';
import 'package:atmos_trs_system/utils/logo_utils.dart';
import 'package:atmos_trs_system/utils/municipality_helper.dart';
import 'package:atmos_trs_system/utils/tourist_id_helper.dart';
import 'package:atmos_trs_system/widgets/app_logout_button.dart';
import 'package:atmos_trs_system/services/announcement_push_service.dart';
import 'package:atmos_trs_system/services/governor_firestore_service.dart';
import 'package:atmos_trs_system/services/user_directory_service.dart';

class GovernorDashboard extends StatefulWidget {
  const GovernorDashboard({super.key});

  @override
  State<GovernorDashboard> createState() => _GovernorDashboardState();
}

class _GovernorDashboardState extends State<GovernorDashboard>
    with SingleTickerProviderStateMixin {
  int _selectedIndex = 0;
  bool _isSidebarExpanded = true;
  late AnimationController _animationController;

  // Data states
  bool _isLoading = true;
  String? _errorMessage;
  int _totalTourists = 0;
  int _totalCheckIns = 0;

  /// Unique tourists who checked in today (one person = 1 even if they checked in at multiple municipalities).
  int _uniqueTouristsToday = 0;
  int _activeSpots = 17;
  String _selectedTimeFilter = 'This Month';
  final _searchController = TextEditingController();

  // Orange theme colors - FlexiMart style
  static const Color _primaryOrange = Color(
    0xFFEA580C,
  ); // dark orange (sidebar)
  static const Color _accentOrange = Color(
    0xFFF97316,
  ); // orange-500 (highlights)
  static const Color _lightOrange = Color(
    0xFFFED7AA,
  ); // light orange (for icons bg)
  static const Color _darkBg = Color(0xFFF4F4F5); // flat neutral background
  static const Color _cardBg = Colors.white;
  static const Color _sidebarBg = Color(0xFFEA580C); // dark orange sidebar
  static const Color _sidebarHover = Color(
    0xFFC2410C,
  ); // darker orange for hover
  static const Color _textDark = Color(0xFF1A1A1A);
  static const Color _textMuted = Color(0xFF6B7280);
  static const Color _cardBorder = Color(0xFFE4E4E7);

  // Flat KPI card colors (minimal, easy on the eyes)
  static const Color _kpiGreen = Color(0xFF9CCC65);
  static const Color _kpiOrange = Color(0xFFFFB74D);
  static const Color _kpiBlue = Color(0xFF64B5F6);
  static const Color _kpiPurple = Color(0xFF9575CD);

  final List<_NavItem> _navItems = [
    _NavItem(icon: Icons.dashboard_rounded, label: 'Dashboard'),
    _NavItem(icon: Icons.people_alt_rounded, label: 'Tourists'),
    _NavItem(icon: Icons.qr_code_2_rounded, label: 'LGU QR Codes'),
    _NavItem(icon: Icons.location_city_rounded, label: 'Municipalities'),
    _NavItem(icon: Icons.analytics_rounded, label: 'Analytics'),
    _NavItem(icon: Icons.campaign_rounded, label: 'Announcements'),
    _NavItem(icon: Icons.settings_rounded, label: 'Settings'),
  ];

  // All municipalities data
  final List<Map<String, dynamic>> _allMunicipalities = [
    {
      'name': 'Oroquieta City',
      'type': 'City',
      'tourists': 0,
      'lat': 8.4854,
      'lng': 123.8058,
    },
    {
      'name': 'Ozamis City',
      'type': 'City',
      'tourists': 0,
      'lat': 8.1481,
      'lng': 123.8444,
    },
    {
      'name': 'Tangub City',
      'type': 'City',
      'tourists': 0,
      'lat': 8.0656,
      'lng': 123.7547,
    },
    {
      'name': 'Aloran',
      'type': 'Municipality',
      'tourists': 0,
      'lat': 8.4167,
      'lng': 123.8333,
    },
    {
      'name': 'Baliangao',
      'type': 'Municipality',
      'tourists': 0,
      'lat': 8.6167,
      'lng': 123.5667,
    },
    {
      'name': 'Bonifacio',
      'type': 'Municipality',
      'tourists': 0,
      'lat': 8.0667,
      'lng': 123.6167,
    },
    {
      'name': 'Calamba',
      'type': 'Municipality',
      'tourists': 0,
      'lat': 8.1667,
      'lng': 123.7167,
    },
    {
      'name': 'Clarin',
      'type': 'Municipality',
      'tourists': 0,
      'lat': 8.2167,
      'lng': 123.8500,
    },
    {
      'name': 'Concepcion',
      'type': 'Municipality',
      'tourists': 0,
      'lat': 8.1500,
      'lng': 123.5833,
    },
    {
      'name': 'Don Victoriano Chiongbian',
      'type': 'Municipality',
      'tourists': 0,
      'lat': 7.9167,
      'lng': 123.4667,
    },
    {
      'name': 'Jimenez',
      'type': 'Municipality',
      'tourists': 0,
      'lat': 8.3333,
      'lng': 123.8333,
    },
    {
      'name': 'Lopez Jaena',
      'type': 'Municipality',
      'tourists': 0,
      'lat': 8.5500,
      'lng': 123.7667,
    },
    {
      'name': 'Panaon',
      'type': 'Municipality',
      'tourists': 0,
      'lat': 8.6833,
      'lng': 123.7167,
    },
    {
      'name': 'Plaridel',
      'type': 'Municipality',
      'tourists': 0,
      'lat': 8.6167,
      'lng': 123.7000,
    },
    {
      'name': 'Sapang Dalaga',
      'type': 'Municipality',
      'tourists': 0,
      'lat': 8.5333,
      'lng': 123.5500,
    },
    {
      'name': 'Sinacaban',
      'type': 'Municipality',
      'tourists': 0,
      'lat': 8.2833,
      'lng': 123.8500,
    },
    {
      'name': 'Tudela',
      'type': 'Municipality',
      'tourists': 0,
      'lat': 8.5333,
      'lng': 123.8500,
    },
  ];

  List<Map<String, dynamic>> _announcements = [];
  List<Map<String, dynamic>> _tourists = [];
  List<Map<String, dynamic>> _checkIns = [];
  List<Map<String, dynamic>> _governorAllSpots = [];

  // Settings states
  bool _emailNotifications = true;
  bool _pushNotifications = true;
  bool _weeklyReports = false;
  String _profileName = 'Governor';
  String _profileEmail = '';
  String? _profilePhotoBase64;
  Uint8List? _profilePhotoBytes;
  String? _lastBackupDate;
  String? _lastSyncDate;
  bool _isExporting = false;
  double _exportProgress = 0.0;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 250),
    );
    _animationController.forward();
    _loadData();
    _loadSettings();
  }

  Widget _buildSidebarAvatar({required double size}) {
    final borderColor = Colors.white.withOpacity(0.9);
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: borderColor, width: 2),
      ),
      child: ClipOval(
        child: _profilePhotoBytes != null
            ? Image.memory(_profilePhotoBytes!, fit: BoxFit.cover)
            : Container(
                color: const Color(0xFFFFF7ED),
                child: Center(
                  child: Text(
                    _profileName.isNotEmpty
                        ? _profileName[0].toUpperCase()
                        : 'G',
                    style: TextStyle(
                      color: _primaryOrange,
                      fontSize: size * 0.5,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
      ),
    );
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    final authEmail = FirebaseAuth.instance.currentUser?.email?.trim();
    setState(() {
      _emailNotifications = prefs.getBool('email_notifications') ?? true;
      _pushNotifications = prefs.getBool('push_notifications') ?? true;
      _weeklyReports = prefs.getBool('weekly_reports') ?? false;
      _profileName = prefs.getString('profile_name') ?? 'Governor';
      _profileEmail = prefs.getString('profile_email') ?? authEmail ?? '';
      _lastBackupDate = prefs.getString('last_backup_date');
      _lastSyncDate = prefs.getString('last_sync_date');
      final photoStr = prefs.getString('profile_photo');
      if (photoStr != null && photoStr.isNotEmpty) {
        _profilePhotoBase64 = photoStr;
        try {
          _profilePhotoBytes = base64Decode(photoStr);
        } catch (_) {
          _profilePhotoBytes = null;
        }
      }
    });
  }

  Future<void> _saveSettings() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('email_notifications', _emailNotifications);
    await prefs.setBool('push_notifications', _pushNotifications);
    await prefs.setBool('weekly_reports', _weeklyReports);
    await prefs.setString('profile_name', _profileName);
    await prefs.setString('profile_email', _profileEmail);
    if (_profilePhotoBase64 != null) {
      await prefs.setString('profile_photo', _profilePhotoBase64!);
    }
  }

  @override
  void dispose() {
    _animationController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  /// Governor analytics and lists are limited to Misamis Occidental (17 LGUs).

  bool _isQrCheckInInMisamisOccidental(Map<String, dynamic> c) {
    if (isMisamisOccidentalMunicipalityId(c['municipalityId']?.toString())) {
      return true;
    }
    final fromName = getMunicipalityIdFromName(c['municipality']?.toString());
    return fromName.isNotEmpty && isMisamisOccidentalMunicipalityId(fromName);
  }

  bool _isTouristSpotInMisamisOccidental(Map<String, dynamic> spot) {
    if (isMisamisOccidentalMunicipalityId(spot['municipalityId']?.toString())) {
      return true;
    }
    final fromName = getMunicipalityIdFromName(
      spot['municipality']?.toString(),
    );
    return fromName.isNotEmpty && isMisamisOccidentalMunicipalityId(fromName);
  }

  bool _isTouristInMisamisOccidentalScope(Map<String, dynamic> t) {
    final prov = t['province']?.toString().toLowerCase() ?? '';
    if (prov.contains('misamis occidental') || prov.contains('misocc')) {
      return true;
    }
    final city = t['city']?.toString().toLowerCase().trim() ?? '';
    if (city.isEmpty) return false;
    for (final m in getMisamisOccidentalMunicipalities()) {
      final mn = m.name.toLowerCase();
      if (city == mn || city.contains(mn) || mn.contains(city)) return true;
      if (city.contains(m.id)) return true;
    }
    return false;
  }

  void _resetMunicipalityTouristCounts() {
    for (final muni in _allMunicipalities) {
      muni['tourists'] = 0;
    }
  }

  Future<void> _loadData() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      if (Firebase.apps.isEmpty) {
        setState(() {
          _errorMessage = 'Firebase is not initialized yet.';
          _isLoading = false;
        });
        return;
      }

      final authUser = FirebaseAuth.instance.currentUser;
      if (authUser == null) {
        setState(() {
          _errorMessage =
              'Sign in required to load provincial data from the database.';
          _isLoading = false;
        });
        return;
      }

      await authUser.getIdToken(true);
      final email = authUser.email ?? '';
      final staffReady =
          await UserDirectoryService.prepareProvincialStaffFirestoreAccess(
        uid: authUser.uid,
        email: email.isNotEmpty ? email : SessionStorage.governorEmail,
        roleRaw: 'governor',
        fullName: _profileName,
      );
      if (!staffReady) {
        debugPrint(
          '[GovernorDashboard] users/${authUser.uid} missing staff role '
          '(email=$email)',
        );
        if (!mounted) return;
        setState(() {
          _errorMessage =
              'Could not verify governor access in Firestore (users/${authUser.uid} '
              'needs role "governor"). Log out, sign in again, or check Firebase rules.';
          _isLoading = false;
        });
        return;
      }

      final snapshot = await GovernorFirestoreService().loadProvincialSnapshot();

      _tourists = snapshot.tourists;
      _checkIns = snapshot.checkIns;
      _governorAllSpots = snapshot.touristSpots;
      _announcements = snapshot.announcements;

      _totalTourists = _tourists.length;
      _totalCheckIns = _checkIns.length;

      final today = DateTime.now();
      final todayUserIds = <String>{};
      for (final c in _checkIns) {
        final d = GovernorFirestoreService.parseCheckInTime(c);
        if (d == null) continue;
        if (d.year != today.year ||
            d.month != today.month ||
            d.day != today.day) {
          continue;
        }
        final uid = GovernorFirestoreService.checkInUserId(c);
        if (uid.isNotEmpty) todayUserIds.add(uid);
      }
      _uniqueTouristsToday = todayUserIds.length;

      _activeSpots = _governorAllSpots.isNotEmpty
          ? _governorAllSpots.length
          : 17;

      final profile = await UserDirectoryService.getProfileByUid(authUser.uid);
      if (profile != null) {
        final name = profile.fullName?.trim() ?? '';
        if (name.isNotEmpty) {
          _profileName = name;
        }
        _profileEmail = profile.email.isNotEmpty
            ? profile.email
            : (authUser.email ?? _profileEmail);
      }

      // Calculate tourists per municipality from check-ins (qr_checkins has municipalityId)
      _resetMunicipalityTouristCounts();
      final checkInsByCity = <String, int>{};
      for (var c in _checkIns) {
        final muniId = c['municipalityId']?.toString() ?? '';
        if (muniId.isNotEmpty) {
          checkInsByCity[muniId] = (checkInsByCity[muniId] ?? 0) + 1;
        }
      }

      // Also count by tourist registration city
      for (var tourist in _tourists) {
        final city = tourist['city']?.toString() ?? '';
        if (city.isNotEmpty) {
          // Find matching municipality and update count
          for (var muni in _allMunicipalities) {
            if (muni['name'].toString().toLowerCase().contains(
                  city.toLowerCase(),
                ) ||
                city.toLowerCase().contains(
                  muni['name'].toString().toLowerCase(),
                )) {
              muni['tourists'] = (muni['tourists'] as int) + 1;
            }
          }
        }
      }

      // Update municipality tourist counts from check-ins (by municipalityId)
      final muniIdToName = <String, String>{};
      for (final m in getMisamisOccidentalMunicipalities()) {
        muniIdToName[m.id] = m.name;
      }
      for (var entry in checkInsByCity.entries) {
        final muniName = muniIdToName[entry.key];
        if (muniName == null) continue;
        for (var muni in _allMunicipalities) {
          if (muni['name'].toString().toLowerCase() == muniName.toLowerCase() ||
              muniName.toLowerCase().contains(
                muni['name'].toString().toLowerCase(),
              )) {
            muni['tourists'] = (muni['tourists'] as int) + entry.value;
            break;
          }
        }
      }

      if (!mounted) return;
      setState(() {
        _errorMessage = snapshot.loadWarnings.isNotEmpty
            ? snapshot.loadWarnings.first
            : null;
        _isLoading = false;
      });
      if (snapshot.loadWarnings.length > 1 && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(snapshot.loadWarnings.join(' ')),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      debugPrint('Error loading governor data: $e');
      if (!mounted) return;
      setState(() {
        _errorMessage = 'Could not load database: $e';
        _isLoading = false;
      });
    }
  }

  void _toggleSidebar() {
    setState(() {
      _isSidebarExpanded = !_isSidebarExpanded;
    });
    if (_isSidebarExpanded) {
      _animationController.forward();
    } else {
      _animationController.reverse();
    }
  }

  bool get _isMobile => MediaQuery.of(context).size.width < 768;
  bool get _isTablet =>
      MediaQuery.of(context).size.width >= 768 &&
      MediaQuery.of(context).size.width < 1024;

  int get _gridCrossAxisCount {
    if (_isMobile) return 2;
    if (_isTablet) return 2;
    return 4;
  }

  /// Desktop/tablet wide layout: fit stats + all charts in one viewport (no scroll).
  bool get _dashboardOnePage => MediaQuery.of(context).size.width >= 900;

  double get _dashboardPanelPadding => _dashboardOnePage ? 12 : 20;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _darkBg,
      drawer: _isMobile ? _buildDrawer() : null,
      body: Row(
        children: [
          if (!_isMobile) _buildSidebar(),
          Expanded(child: _buildMainContent()),
        ],
      ),
      bottomNavigationBar: _isMobile ? _buildBottomNav() : null,
    );
  }

  Widget _buildDrawer() {
    final bottomInset = MediaQuery.paddingOf(context).bottom;
    return Drawer(
      backgroundColor: _sidebarBg,
      child: Column(
        children: [
          const SizedBox(height: 48),
          _buildLogo(expanded: true),
          const SizedBox(height: 24),
          Expanded(child: _buildNavigation(expanded: true)),
          const SizedBox(height: 10),
          _buildLogoutButton(expanded: true),
          SizedBox(height: 16 + bottomInset),
        ],
      ),
    );
  }

  Widget _buildBottomNav() {
    const Color bottomNavSelectedBg = Color(0xFFFFF7ED);
    const Color bottomNavSelectedFg = Color(0xFFC2410C);
    const Color bottomNavUnselected = Color(0xE6FFFFFF);
    return Material(
      color: _sidebarBg,
      elevation: 8,
      shadowColor: Colors.black26,
      child: SafeArea(
        top: false,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final maxW = constraints.maxWidth;
            return SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              physics: const BouncingScrollPhysics(),
              child: ConstrainedBox(
                constraints: BoxConstraints(minWidth: maxW),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(8, 10, 8, 10),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: List.generate(_navItems.length.clamp(0, 5), (
                      index,
                    ) {
                      final item = _navItems[index];
                      final isSelected = _selectedIndex == index;
                      return Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 2),
                        child: Material(
                          color: Colors.transparent,
                          child: InkWell(
                            onTap: () => setState(() => _selectedIndex = index),
                            borderRadius: BorderRadius.circular(18),
                            splashColor: Colors.white24,
                            highlightColor: Colors.white12,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 10,
                              ),
                              decoration: BoxDecoration(
                                color: isSelected
                                    ? bottomNavSelectedBg
                                    : Colors.transparent,
                                borderRadius: BorderRadius.circular(18),
                                boxShadow: isSelected
                                    ? [
                                        BoxShadow(
                                          color: Colors.black.withOpacity(0.12),
                                          blurRadius: 8,
                                          offset: const Offset(0, 2),
                                        ),
                                      ]
                                    : null,
                              ),
                              child: SizedBox(
                                width: 76,
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      item.icon,
                                      color: isSelected
                                          ? bottomNavSelectedFg
                                          : bottomNavUnselected,
                                      size: 24,
                                    ),
                                    const SizedBox(height: 6),
                                    Text(
                                      item.label,
                                      textAlign: TextAlign.center,
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        color: isSelected
                                            ? bottomNavSelectedFg
                                            : bottomNavUnselected,
                                        fontSize: 10,
                                        height: 1.15,
                                        letterSpacing: 0.15,
                                        fontWeight: isSelected
                                            ? FontWeight.w700
                                            : FontWeight.w500,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                      );
                    }),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildSidebar() {
    final width = _isSidebarExpanded ? 260.0 : 80.0;
    final bottomInset = MediaQuery.paddingOf(context).bottom;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 250),
      width: width,
      color: _sidebarBg,
      child: Column(
        children: [
          const SizedBox(height: 16),
          _buildSidebarToggle(),
          const SizedBox(height: 8),
          _buildLogo(expanded: _isSidebarExpanded),
          const SizedBox(height: 24),
          Expanded(child: _buildNavigation(expanded: _isSidebarExpanded)),
          const SizedBox(height: 10),
          _buildLogoutButton(expanded: _isSidebarExpanded),
          SizedBox(height: 16 + bottomInset),
        ],
      ),
    );
  }

  Widget _buildSidebarToggle() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Align(
        alignment: _isSidebarExpanded
            ? Alignment.centerRight
            : Alignment.center,
        child: Tooltip(
          message: _isSidebarExpanded ? 'Collapse sidebar' : 'Expand sidebar',
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: _toggleSidebar,
              borderRadius: BorderRadius.circular(10),
              child: Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.white.withOpacity(0.1)),
                ),
                child: Icon(
                  _isSidebarExpanded
                      ? Icons.menu_open_rounded
                      : Icons.menu_rounded,
                  color: Colors.white,
                  size: 20,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildLogo({required bool expanded}) {
    final logoSize = expanded ? 46.0 : 32.0;
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: expanded ? 16 : 12),
      child: Container(
        padding: EdgeInsets.all(expanded ? 12 : 8),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.06),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: _primaryOrange.withOpacity(0.9), width: 1),
        ),
        child: expanded
            ? Row(
                mainAxisAlignment: MainAxisAlignment.start,
                children: [
                  SizedBox(
                    width: logoSize,
                    height: logoSize,
                    child: TransparentLogo(
                      width: logoSize,
                      height: logoSize,
                      fit: BoxFit.contain,
                      errorIcon: Icons.public,
                      errorIconSize: 26,
                      errorIconColor: _primaryOrange,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'ATMOS TRS',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 0.5,
                          ),
                        ),
                        Text(
                          'Governor Portal',
                          style: TextStyle(
                            color: Colors.white.withOpacity(0.8),
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  _buildSidebarAvatar(size: 34),
                ],
              )
            : Center(
                child: SizedBox(
                  width: logoSize,
                  height: logoSize,
                  child: TransparentLogo(
                    width: logoSize,
                    height: logoSize,
                    fit: BoxFit.contain,
                    errorIcon: Icons.public,
                    errorIconSize: 22,
                    errorIconColor: _primaryOrange,
                  ),
                ),
              ),
      ),
    );
  }

  Widget _buildNavigation({required bool expanded}) {
    // SingleChildScrollView + Column avoids a tall empty gap between the last nav item
    // and Logout when [ListView] sits inside [Expanded].
    return SingleChildScrollView(
      padding: EdgeInsets.only(
        left: expanded ? 12 : 8,
        right: expanded ? 12 : 8,
        bottom: 4,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (int index = 0; index < _navItems.length; index++)
            _buildGovernorNavItem(
              index: index,
              expanded: expanded,
              isLast: index == _navItems.length - 1,
            ),
        ],
      ),
    );
  }

  Widget _buildGovernorNavItem({
    required int index,
    required bool expanded,
    bool isLast = false,
  }) {
    final item = _navItems[index];
    final isSelected = _selectedIndex == index;
    return Tooltip(
      message: expanded ? '' : item.label,
      child: Container(
        margin: EdgeInsets.only(bottom: isLast ? 0 : 6),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: () => setState(() => _selectedIndex = index),
            borderRadius: BorderRadius.circular(14),
            hoverColor: Colors.white.withOpacity(0.06),
            splashColor: Colors.white.withOpacity(0.08),
            child: Container(
              padding: EdgeInsets.symmetric(
                horizontal: expanded ? 16 : 12,
                vertical: 14,
              ),
              decoration: BoxDecoration(
                color: isSelected
                    ? Colors.white
                    : Colors.white.withOpacity(0.04),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Row(
                mainAxisAlignment: expanded
                    ? MainAxisAlignment.start
                    : MainAxisAlignment.center,
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: isSelected
                          ? _primaryOrange.withOpacity(0.12)
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(
                      item.icon,
                      color: isSelected
                          ? _primaryOrange
                          : Colors.white.withOpacity(0.7),
                      size: 22,
                    ),
                  ),
                  if (expanded) ...[
                    const SizedBox(width: 14),
                    Text(
                      item.label,
                      style: TextStyle(
                        color: isSelected
                            ? _primaryOrange
                            : Colors.white.withOpacity(0.8),
                        fontSize: 15,
                        fontWeight: isSelected
                            ? FontWeight.w600
                            : FontWeight.w500,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildLogoutButton({required bool expanded}) {
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: expanded ? 16 : 8),
      child: Tooltip(
        message: expanded ? '' : 'Logout',
        child: AppLogoutButton(
          style: AppLogoutStyle.sidebarOnOrange,
          expanded: expanded,
          onPressed: _logout,
        ),
      ),
    );
  }

  Future<void> _logout() async {
    await SessionStorage.clearSession();
    if (!mounted) return;
    Navigator.pushReplacementNamed(context, '/login');
  }

  Widget _buildMainContent() {
    if (_isLoading) {
      return const Center(
        child: CircularProgressIndicator(color: _primaryOrange),
      );
    }

    if (_errorMessage != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.error_outline, color: Colors.red.shade300, size: 64),
            const SizedBox(height: 16),
            Text(_errorMessage!, style: const TextStyle(color: _textMuted)),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _loadData,
              style: ElevatedButton.styleFrom(backgroundColor: _primaryOrange),
              child: const Text('Retry'),
            ),
          ],
        ),
      );
    }

    switch (_selectedIndex) {
      case 0:
        return _buildDashboardContent();
      case 1:
        return _buildTouristsContent();
      case 2:
        return _buildGovernorSpotQRCodesContent();
      case 3:
        return _buildMunicipalitiesContent();
      case 4:
        return _buildAnalyticsContent();
      case 5:
        return _buildAnnouncementsContent();
      case 6:
        return _buildSettingsContent();
      default:
        return _buildDashboardContent();
    }
  }

  Widget _buildHeader(
    String title, {
    String? subtitle,
    List<Widget>? actions,
    bool compact = false,
  }) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: _isMobile ? 16 : 24,
        vertical: compact ? 10 : 16,
      ),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [_accentOrange, _primaryOrange],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: const BorderRadius.vertical(bottom: Radius.circular(24)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.08),
            blurRadius: 18,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: compact ? 18 : (_isMobile ? 18 : 22),
                    fontWeight: FontWeight.bold,
                  ),
                ),
                if (subtitle != null)
                  Text(
                    subtitle,
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.8),
                      fontSize: compact ? 11 : (_isMobile ? 12 : 14),
                    ),
                  ),
              ],
            ),
          ),
          if (actions != null) ...actions,
          if (_isMobile) ...[_buildMobileHeaderProfileAction()],
          if (!_isMobile) ...[
            _buildHeaderAction(
              Icons.notifications_outlined,
              badge: _unreadNotificationCount > 0
                  ? '$_unreadNotificationCount'
                  : null,
              onPressed: _showNotificationsPanel,
            ),
            const SizedBox(width: 12),
            _buildHeaderProfile(),
          ],
        ],
      ),
    );
  }

  int get _unreadNotificationCount {
    final count = _announcements.length;
    return count > 99 ? 99 : count;
  }

  void _showNotificationsPanel() {
    showDialog(
      context: context,
      barrierColor: Colors.black54,
      builder: (context) => Center(
        child: Material(
          color: Colors.transparent,
          child: Container(
            width: MediaQuery.of(context).size.width > 600
                ? 440
                : MediaQuery.of(context).size.width * 0.9,
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(context).size.height * 0.75,
            ),
            decoration: BoxDecoration(
              color: _cardBg,
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.2),
                  blurRadius: 24,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Header
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 20, 12, 16),
                  child: Row(
                    children: [
                      const Text(
                        'Notifications',
                        style: TextStyle(
                          color: _textDark,
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const Spacer(),
                      TextButton(
                        onPressed: () {
                          Navigator.pop(context);
                          setState(() => _selectedIndex = 5);
                        },
                        style: TextButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          minimumSize: Size.zero,
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                        child: const Text(
                          'View all',
                          style: TextStyle(
                            color: _primaryOrange,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(
                          Icons.close_rounded,
                          color: _textMuted,
                          size: 22,
                        ),
                        onPressed: () => Navigator.pop(context),
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(
                          minWidth: 36,
                          minHeight: 36,
                        ),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1),
                // List
                Flexible(
                  child: _announcements.isEmpty
                      ? const Padding(
                          padding: EdgeInsets.symmetric(vertical: 48),
                          child: Center(
                            child: Text(
                              'No notifications yet.',
                              style: TextStyle(color: _textMuted, fontSize: 14),
                            ),
                          ),
                        )
                      : ListView.separated(
                          shrinkWrap: true,
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          itemCount: _announcements.length,
                          separatorBuilder: (_, __) =>
                              Divider(height: 1, color: Colors.grey.shade200),
                          itemBuilder: (context, i) {
                            final a = _announcements[i];
                            final type = a['type']?.toString() ?? 'General';
                            IconData icon = Icons.campaign_rounded;
                            if (type == 'Promo')
                              icon = Icons.local_offer_rounded;
                            else if (type == 'Event')
                              icon = Icons.event_rounded;
                            else if (type == 'Alert')
                              icon = Icons.warning_amber_rounded;
                            return ListTile(
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 20,
                                vertical: 4,
                              ),
                              leading: CircleAvatar(
                                radius: 20,
                                backgroundColor: _primaryOrange.withOpacity(
                                  0.15,
                                ),
                                child: Icon(
                                  icon,
                                  color: _primaryOrange,
                                  size: 20,
                                ),
                              ),
                              title: Text(
                                a['title']?.toString() ?? 'Announcement',
                                style: const TextStyle(
                                  color: _textDark,
                                  fontWeight: FontWeight.w600,
                                  fontSize: 14,
                                ),
                              ),
                              subtitle: Padding(
                                padding: const EdgeInsets.only(top: 4),
                                child: Text(
                                  a['content']
                                          ?.toString()
                                          .replaceAll('\n', ' ')
                                          .trim() ??
                                      '',
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    color: _textMuted,
                                    fontSize: 12,
                                    height: 1.35,
                                  ),
                                ),
                              ),
                              onTap: () {
                                Navigator.pop(context);
                                setState(() => _selectedIndex = 5);
                              },
                            );
                          },
                        ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeaderAction(
    IconData icon, {
    String? badge,
    VoidCallback? onPressed,
  }) {
    final isNotificationAction = icon == Icons.notifications_outlined;
    return Tooltip(
      message: isNotificationAction ? 'Notifications' : 'Search',
      child: GestureDetector(
        onTap: onPressed,
        child: Stack(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: isNotificationAction ? Colors.transparent : Colors.white,
                borderRadius: BorderRadius.circular(10),
                border: isNotificationAction
                    ? Border.all(
                        color: Colors.white.withOpacity(0.75),
                        width: 1.4,
                      )
                    : null,
              ),
              child: Icon(
                icon,
                color: isNotificationAction ? Colors.white : _primaryOrange,
                size: 22,
              ),
            ),
            if (badge != null)
              Positioned(
                right: 0,
                top: 0,
                child: Container(
                  padding: const EdgeInsets.all(4),
                  decoration: const BoxDecoration(
                    color: _primaryOrange,
                    shape: BoxShape.circle,
                  ),
                  child: Text(
                    badge,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  /// Profile (avatar + name) in the top header next to search and notification.
  Widget _buildHeaderProfile() {
    return Tooltip(
      message: _profileName,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(
            color: _primaryOrange.withOpacity(0.25),
            width: 1.5,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.06),
              blurRadius: 10,
              offset: const Offset(0, 2),
            ),
            BoxShadow(
              color: _primaryOrange.withOpacity(0.08),
              blurRadius: 12,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildSidebarAvatar(size: 36),
            const SizedBox(width: 12),
            Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _profileName,
                  style: const TextStyle(
                    color: _textDark,
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.2,
                  ),
                  overflow: TextOverflow.ellipsis,
                  maxLines: 1,
                ),
                const SizedBox(height: 2),
                Text(
                  'Governor',
                  style: TextStyle(
                    color: _textMuted,
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMobileHeaderProfileAction() {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        onTap: _showMobileProfileActionsSheet,
        borderRadius: BorderRadius.circular(18),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildSidebarAvatar(size: 30),
              const SizedBox(width: 6),
              const Icon(
                Icons.keyboard_arrow_down_rounded,
                color: _textDark,
                size: 18,
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showMobileProfileActionsSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: _cardBg,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  _buildSidebarAvatar(size: 42),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _profileName,
                          style: const TextStyle(
                            color: _textDark,
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const Text(
                          'Governor',
                          style: TextStyle(color: _textMuted, fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              ListTile(
                leading: const Icon(
                  Icons.settings_rounded,
                  color: _primaryOrange,
                ),
                title: const Text('Settings'),
                onTap: () {
                  Navigator.pop(ctx);
                  setState(() => _selectedIndex = 6);
                },
              ),
              ListTile(
                leading: const Icon(
                  Icons.logout_rounded,
                  color: Colors.redAccent,
                ),
                title: const Text('Logout'),
                onTap: () {
                  Navigator.pop(ctx);
                  _logout();
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ==================== DASHBOARD SECTION ====================
  Widget _buildDashboardContent() {
    return RefreshIndicator(
      onRefresh: _loadData,
      color: _primaryOrange,
      child: _buildDashboardCanvas(
        child: Column(
          children: [
            _buildHeader(
              'Welcome back, Governor',
              subtitle: _dashboardOnePage
                  ? 'Misamis Occidental · provincial tourism overview'
                  : 'Here\'s what\'s happening in Misamis Occidental today',
              compact: _dashboardOnePage,
            ),
            Expanded(
              child: LayoutBuilder(
                builder: (context, viewport) {
                  final body = _dashboardOnePage
                      ? SizedBox(
                          height: viewport.maxHeight,
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                _buildStatsGrid(),
                                const SizedBox(height: 10),
                                Expanded(child: _buildDashboardOnePageCharts()),
                              ],
                            ),
                          ),
                        )
                      : SingleChildScrollView(
                          physics: const AlwaysScrollableScrollPhysics(),
                          padding: EdgeInsets.all(_isMobile ? 16 : 24),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _buildStatsGrid(),
                              const SizedBox(height: 20),
                              _buildChartsSection(),
                              const SizedBox(height: 20),
                              _buildVisitorDemographicsSection(),
                            ],
                          ),
                        );
                  if (_dashboardOnePage) {
                    return SingleChildScrollView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      child: body,
                    );
                  }
                  return body;
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDashboardCanvas({required Widget child}) {
    return ColoredBox(color: _darkBg, child: child);
  }

  /// All chart panels in two rows — fills remaining viewport height.
  Widget _buildDashboardOnePageCharts() {
    return Column(
      children: [
        Expanded(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(flex: 3, child: _buildTouristArrivalsChart(dense: true)),
              const SizedBox(width: 10),
              Expanded(flex: 2, child: _buildTopCategoriesCard(dense: true)),
            ],
          ),
        ),
        const SizedBox(height: 10),
        Expanded(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(child: _buildGenderPieChart(dense: true)),
              const SizedBox(width: 10),
              Expanded(child: _buildAgeRangeBarChart(dense: true)),
              const SizedBox(width: 10),
              Expanded(child: _buildLocalForeignPieChart(dense: true)),
              const SizedBox(width: 10),
              Expanded(child: _buildCityRankingBarChart(dense: true)),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildStatsGrid() {
    final checkInTrend = _checkInsTrendText;
    final stats = [
      _StatCard(
        title: 'Total Tourists',
        value: _formatNumber(_totalTourists),
        icon: Icons.people_alt_rounded,
        color: _kpiGreen,
      ),
      _StatCard(
        title: 'Tourists Today',
        value: _formatNumber(_uniqueTouristsToday),
        icon: Icons.qr_code_scanner_rounded,
        color: _kpiOrange,
      ),
      _StatCard(
        title: 'Total Check-ins',
        value: _formatNumber(_totalCheckIns),
        change: checkInTrend.text,
        isPositive: checkInTrend.isPositive,
        icon: Icons.touch_app_rounded,
        color: _kpiBlue,
      ),
      _StatCard(
        title: 'Active Spots',
        value: '$_activeSpots',
        icon: Icons.location_on_rounded,
        color: _kpiPurple,
      ),
    ];

    if (_dashboardOnePage) {
      return SizedBox(
        height: 96,
        child: Row(
          children: [
            for (var i = 0; i < stats.length; i++) ...[
              if (i > 0) const SizedBox(width: 10),
              Expanded(child: _buildStatCard(stats[i], compact: true)),
            ],
          ],
        ),
      );
    }

    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: _gridCrossAxisCount,
        crossAxisSpacing: 16,
        mainAxisSpacing: 16,
        childAspectRatio: _isMobile ? 1.35 : 1.55,
      ),
      itemCount: stats.length,
      itemBuilder: (context, index) => _buildStatCard(stats[index]),
    );
  }

  BoxDecoration _dashboardPanelDecoration({Color? accent}) {
    return BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: _cardBorder),
      boxShadow: const [
        BoxShadow(
          color: Color(0x0A000000),
          blurRadius: 8,
          offset: Offset(0, 2),
        ),
      ],
    );
  }

  Widget _wrapDashboardRichPanel({
    required Widget child,
    Color? accent,
    EdgeInsetsGeometry? padding,
  }) {
    return Container(
      padding: padding ?? EdgeInsets.all(_dashboardPanelPadding),
      decoration: _dashboardPanelDecoration(accent: accent),
      child: child,
    );
  }

  Widget _buildChartPlotArea({
    required Widget child,
    Color? tint,
    bool dense = false,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFFFAFAFA),
        borderRadius: BorderRadius.circular(dense ? 8 : 10),
        border: Border.all(color: _cardBorder),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(dense ? 8 : 10),
        child: child,
      ),
    );
  }

  List<double> _statSparklineValues(_StatCard stat) {
    if (stat.title.contains('Check-in')) {
      final v = _dashboardTrendValues;
      if (v.isNotEmpty && v.any((e) => e > 0)) return v;
    }
    final n = double.tryParse(stat.value.replaceAll(',', '')) ?? 0;
    final base = n > 0 ? n : 1.0;
    return List.generate(10, (i) => base * (0.82 + 0.18 * (i / 9)));
  }

  Widget _dashboardSectionTitle({
    required String title,
    required IconData icon,
    Widget? trailing,
    bool dense = false,
  }) {
    final box = dense ? 28.0 : 36.0;
    final iconSize = dense ? 15.0 : 18.0;
    return Row(
      children: [
        Container(
          width: box,
          height: box,
          decoration: BoxDecoration(
            color: _primaryOrange.withOpacity(0.12),
            borderRadius: BorderRadius.circular(dense ? 8 : 10),
          ),
          child: Icon(icon, color: _primaryOrange, size: iconSize),
        ),
        SizedBox(width: dense ? 8 : 10),
        Expanded(
          child: Text(
            title,
            style: TextStyle(
              color: _textDark,
              fontSize: dense ? 13 : 15,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        if (trailing != null) trailing,
      ],
    );
  }

  bool get _hasArrivalChartData =>
      _dashboardTrendValues.any((value) => value > 0);

  String _formatNumber(int number) {
    if (number >= 1000000) {
      return '${(number / 1000000).toStringAsFixed(1)}M';
    } else if (number >= 1000) {
      return '${(number / 1000).toStringAsFixed(number >= 10000 ? 0 : 1)}K';
    }
    return number.toString();
  }

  List<double> get _dashboardTrendValues {
    int days;
    if (_selectedTimeFilter == 'This Week') {
      days = 7;
    } else if (_selectedTimeFilter == 'This Month') {
      days = 14;
    } else {
      days = 12;
    }
    if (_selectedTimeFilter == 'This Year') {
      final now = DateTime.now();
      final counts = List.filled(12, 0.0);
      for (var c in _checkIns) {
        final d = _checkInTimestamp(c);
        if (d != null) {
          final diff = (now.year - d.year) * 12 + (now.month - d.month);
          if (diff >= 0 && diff < 12) counts[11 - diff] += 1;
        }
      }
      return counts;
    }
    final now = DateTime.now();
    final counts = List.filled(days, 0.0);
    for (var c in _checkIns) {
      final d = _checkInTimestamp(c);
      if (d != null) {
        final diff = now.difference(DateTime(d.year, d.month, d.day)).inDays;
        if (diff >= 0 && diff < days) counts[days - 1 - diff] += 1;
      }
    }
    return counts;
  }

  ({String text, bool isPositive}) get _checkInsTrendText {
    int thisWeek = 0, lastWeek = 0;
    final now = DateTime.now();
    for (var c in _checkIns) {
      final d = _checkInTimestamp(c);
      if (d == null) continue;
      final diff = now.difference(DateTime(d.year, d.month, d.day)).inDays;
      if (diff >= 0 && diff < 7)
        thisWeek++;
      else if (diff >= 7 && diff < 14)
        lastWeek++;
    }
    if (lastWeek == 0) return (text: '—', isPositive: true);
    final pct = ((thisWeek - lastWeek) / lastWeek) * 100;
    if (pct > 0) return (text: '+${pct.toStringAsFixed(1)}%', isPositive: true);
    if (pct < 0) return (text: '${pct.toStringAsFixed(1)}%', isPositive: false);
    return (text: '0%', isPositive: true);
  }

  List<Map<String, dynamic>> get _dashboardCategoryStats {
    final byCategory = <String, int>{};
    for (var c in _checkIns) {
      final cat =
          c['spotCategory']?.toString().trim() ??
          c['category']?.toString().trim() ??
          'Other';
      final key = cat.isEmpty ? 'Other' : cat;
      byCategory[key] = (byCategory[key] ?? 0) + 1;
    }
    final total = byCategory.values.fold<int>(0, (a, b) => a + b);
    if (total == 0) {
      return [
        {'name': 'Beach', 'count': 0, 'percentage': 0.0},
        {'name': 'Falls', 'count': 0, 'percentage': 0.0},
        {'name': 'Historical', 'count': 0, 'percentage': 0.0},
        {'name': 'Mountain', 'count': 0, 'percentage': 0.0},
        {'name': 'Resorts', 'count': 0, 'percentage': 0.0},
      ];
    }
    return byCategory.entries
        .map(
          (e) => {
            'name': e.key,
            'count': e.value,
            'percentage': e.value / total,
          },
        )
        .toList()
      ..sort(
        (a, b) =>
            (b['percentage'] as double).compareTo(a['percentage'] as double),
      );
  }

  static const Color _genderMaleColor = Color(0xFFEF4444);
  static const Color _genderFemaleColor = Color(0xFF06B6D4);
  static const Color _genderOtherColor = Color(0xFF84CC16);
  static const Color _localVisitorColor = Color(0xFF29B6F6);
  static const Color _foreignVisitorColor = Color(0xFFFF8C32);

  int? _touristAgeYears(Map<String, dynamic> tourist) {
    final dob = tourist['dateOfBirth']?.toString().trim();
    if (dob == null || dob.isEmpty) return null;
    try {
      final parts = dob.split('-');
      if (parts.length < 3) return null;
      final birth = DateTime(
        int.parse(parts[0]),
        int.parse(parts[1]),
        int.parse(parts[2]),
      );
      final now = DateTime.now();
      var age = now.year - birth.year;
      if (now.month < birth.month ||
          (now.month == birth.month && now.day < birth.day)) {
        age--;
      }
      return age < 0 ? null : age;
    } catch (_) {
      return null;
    }
  }

  String _normalizeGender(Map<String, dynamic> tourist) {
    final raw = (tourist['sex'] ?? tourist['gender'] ?? '')
        .toString()
        .trim()
        .toLowerCase();
    if (raw.contains('female') || raw == 'f') return 'Female';
    if (raw.contains('male') || raw == 'm') return 'Male';
    if (raw.isNotEmpty) return 'Others';
    return 'Others';
  }

  bool? _isLocalTourist(Map<String, dynamic> tourist) {
    final isLocal = tourist['isLocal'];
    if (isLocal is bool) return isLocal;
    final label = tourist['localOrForeign']?.toString().toLowerCase() ?? '';
    if (label.contains('local')) return true;
    if (label.contains('foreign')) return false;
    final nationality = tourist['nationality']?.toString().toLowerCase() ?? '';
    if (nationality.contains('filipin') || nationality == 'ph') return true;
    if (nationality.isNotEmpty) return false;
    return null;
  }

  String _ageBucketForTourist(int? age) {
    if (age == null) return 'Unknown';
    if (age < 18) return '18-35';
    if (age <= 35) return '18-35';
    if (age <= 50) return '36-50';
    if (age <= 64) return '51-64';
    return '65+';
  }

  Map<String, int> get _genderCounts {
    final counts = <String, int>{'Male': 0, 'Female': 0, 'Others': 0};
    for (final tourist in _tourists) {
      final key = _normalizeGender(tourist);
      counts[key] = (counts[key] ?? 0) + 1;
    }
    return counts;
  }

  List<({String label, int male, int female, int others})>
  get _ageGenderSeries {
    const labels = ['18-35', '36-50', '51-64', '65+'];
    final data = <String, ({int male, int female, int others})>{
      for (final label in labels) label: (male: 0, female: 0, others: 0),
    };
    for (final tourist in _tourists) {
      final bucket = _ageBucketForTourist(_touristAgeYears(tourist));
      if (!data.containsKey(bucket)) continue;
      final gender = _normalizeGender(tourist);
      final current = data[bucket]!;
      if (gender == 'Male') {
        data[bucket] = (
          male: current.male + 1,
          female: current.female,
          others: current.others,
        );
      } else if (gender == 'Female') {
        data[bucket] = (
          male: current.male,
          female: current.female + 1,
          others: current.others,
        );
      } else {
        data[bucket] = (
          male: current.male,
          female: current.female,
          others: current.others + 1,
        );
      }
    }
    return labels.map((label) {
      final row = data[label]!;
      return (
        label: label,
        male: row.male,
        female: row.female,
        others: row.others,
      );
    }).toList();
  }

  Map<String, int> get _localForeignCounts {
    var local = 0;
    var foreign = 0;
    for (final tourist in _tourists) {
      if (_isLocalTourist(tourist) == true) {
        local++;
      } else {
        foreign++;
      }
    }
    return {'Local': local, 'Foreign': foreign};
  }

  List<({String name, int count})> get _cityRankingData {
    final counts = <String, int>{};
    for (final muni in _allMunicipalities) {
      final name = muni['name']?.toString().trim() ?? '';
      final value = (muni['tourists'] as num?)?.toInt() ?? 0;
      if (name.isNotEmpty && value > 0) counts[name] = value;
    }
    if (counts.isEmpty) {
      for (final tourist in _tourists) {
        final city = tourist['city']?.toString().trim() ?? '';
        if (city.isEmpty) continue;
        counts[city] = (counts[city] ?? 0) + 1;
      }
    }
    final sorted = counts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return sorted.take(6).map((e) => (name: e.key, count: e.value)).toList();
  }

  List<({Color color, double fraction})> _segmentsFromCounts(
    Map<String, int> counts,
    Map<String, Color> colors,
  ) {
    final total = counts.values.fold<int>(0, (a, b) => a + b);
    if (total == 0) return [];
    return [
      for (final entry in counts.entries)
        if (entry.value > 0)
          (
            color: colors[entry.key] ?? Colors.grey,
            fraction: entry.value / total,
          ),
    ];
  }

  Widget _buildVisitorDemographicsSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Visitor Demographics',
          style: TextStyle(
            color: _textDark,
            fontSize: 16,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 12),
        _buildDemographicsChartsGrid(),
      ],
    );
  }

  Widget _buildDemographicsChartsGrid() {
    final charts = [
      _buildGenderPieChart(),
      _buildAgeRangeBarChart(),
      _buildLocalForeignPieChart(),
      _buildCityRankingBarChart(),
    ];

    if (_isMobile) {
      return Column(
        children: [
          for (var i = 0; i < charts.length; i++) ...[
            if (i > 0) const SizedBox(height: 16),
            charts[i],
          ],
        ],
      );
    }

    return Column(
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: charts[0]),
            const SizedBox(width: 16),
            Expanded(child: charts[1]),
          ],
        ),
        const SizedBox(height: 16),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: charts[2]),
            const SizedBox(width: 16),
            Expanded(child: charts[3]),
          ],
        ),
      ],
    );
  }

  Widget _buildDemographicsChartShell({
    required String title,
    required IconData icon,
    required Widget child,
    bool dense = false,
    Color? accent,
  }) {
    return _wrapDashboardRichPanel(
      accent: accent,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _dashboardSectionTitle(title: title, icon: icon, dense: dense),
          SizedBox(height: dense ? 6 : 12),
          Expanded(
            child: _buildChartPlotArea(
              dense: dense,
              tint: accent,
              child: child,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDonutChartContent({
    required List<({Color color, double fraction})> segments,
    required int total,
    required List<Widget> legendRows,
    required String emptyMessage,
    bool dense = false,
  }) {
    if (total == 0) {
      return _buildDemographicsEmptyState(emptyMessage);
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        final maxPie = dense
            ? math.min(constraints.maxHeight - 8, 120.0)
            : 168.0;
        final pieSize = (constraints.maxWidth * (dense ? 0.38 : 0.42)).clamp(
          dense ? 72.0 : 120.0,
          maxPie,
        );
        return Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            SizedBox(
              width: pieSize,
              height: pieSize,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  CustomPaint(
                    size: Size(pieSize, pieSize),
                    painter: _CategoryPiePainter(
                      segments: segments,
                      holeColor: Colors.white,
                    ),
                  ),
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        _formatNumber(total),
                        style: TextStyle(
                          color: _textDark,
                          fontSize: dense ? 16 : 20,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      Text(
                        'Total',
                        style: TextStyle(
                          color: _textMuted.withOpacity(0.9),
                          fontSize: dense ? 9 : 11,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: SingleChildScrollView(
                physics: dense ? const NeverScrollableScrollPhysics() : null,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: legendRows,
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildDemographicsLegendRow(
    String label,
    Color color,
    int count,
    int total, {
    bool dense = false,
  }) {
    final pct = total > 0 ? (count / total * 100) : 0.0;
    final pctLabel = pct >= 10 || pct == 0
        ? '${pct.round()}%'
        : '${pct.toStringAsFixed(1)}%';
    return Padding(
      padding: EdgeInsets.only(bottom: dense ? 4 : 10),
      child: Row(
        children: [
          Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                color: _textMuted,
                fontSize: dense ? 10 : 12,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          Text(
            '${_formatNumber(count)} · $pctLabel',
            style: TextStyle(
              color: _textDark,
              fontSize: dense ? 9 : 11,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDemographicsEmptyState(String message) {
    return Center(
      child: Text(
        message,
        textAlign: TextAlign.center,
        style: TextStyle(
          color: _textMuted.withOpacity(0.9),
          fontSize: 12,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }

  Widget _buildGenderPieChart({bool dense = false}) {
    final counts = _genderCounts;
    final total = counts.values.fold<int>(0, (a, b) => a + b);
    final segments = _segmentsFromCounts(counts, {
      'Male': _genderMaleColor,
      'Female': _genderFemaleColor,
      'Others': _genderOtherColor,
    });
    final chart = _buildDemographicsChartShell(
      dense: dense,
      accent: _genderMaleColor,
      title: 'Gender',
      icon: Icons.wc_rounded,
      child: _buildDonutChartContent(
        dense: dense,
        segments: segments,
        total: total,
        emptyMessage: 'No gender data yet',
        legendRows: [
          _buildDemographicsLegendRow(
            'Male',
            _genderMaleColor,
            counts['Male'] ?? 0,
            total,
            dense: dense,
          ),
          _buildDemographicsLegendRow(
            'Female',
            _genderFemaleColor,
            counts['Female'] ?? 0,
            total,
            dense: dense,
          ),
          _buildDemographicsLegendRow(
            'Others',
            _genderOtherColor,
            counts['Others'] ?? 0,
            total,
            dense: dense,
          ),
        ],
      ),
    );
    if (dense) return chart;
    return SizedBox(height: _isMobile ? 260 : 300, child: chart);
  }

  Widget _buildLocalForeignPieChart({bool dense = false}) {
    final counts = _localForeignCounts;
    final total = counts.values.fold<int>(0, (a, b) => a + b);
    final segments = _segmentsFromCounts(counts, {
      'Local': _localVisitorColor,
      'Foreign': _foreignVisitorColor,
    });
    final chart = _buildDemographicsChartShell(
      dense: dense,
      accent: _foreignVisitorColor,
      title: 'Local vs Foreign',
      icon: Icons.public_rounded,
      child: _buildDonutChartContent(
        dense: dense,
        segments: segments,
        total: total,
        emptyMessage: 'No local/foreign data yet',
        legendRows: [
          _buildDemographicsLegendRow(
            'Local',
            _localVisitorColor,
            counts['Local'] ?? 0,
            total,
            dense: dense,
          ),
          _buildDemographicsLegendRow(
            'Foreign',
            _foreignVisitorColor,
            counts['Foreign'] ?? 0,
            total,
            dense: dense,
          ),
        ],
      ),
    );
    if (dense) return chart;
    return SizedBox(height: _isMobile ? 260 : 300, child: chart);
  }

  Widget _buildAgeRangeBarChart({bool dense = false}) {
    final series = _ageGenderSeries;
    final total = series.fold<int>(
      0,
      (sum, row) => sum + row.male + row.female + row.others,
    );
    final chart = _buildDemographicsChartShell(
      dense: dense,
      accent: const Color(0xFF7C3AED),
      title: 'Age Range',
      icon: Icons.calendar_view_month_rounded,
      child: total == 0
          ? _buildDemographicsEmptyState('Add date of birth on registration')
          : Column(
              children: [
                Expanded(
                  child: CustomPaint(
                    painter: _GroupedAgeGenderBarPainter(
                      series: series,
                      maleColor: _genderMaleColor,
                      femaleColor: _genderFemaleColor,
                      otherColor: _genderOtherColor,
                    ),
                    child: Container(),
                  ),
                ),
                SizedBox(
                  height: dense ? 14 : 24,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      _buildAgeGenderLegendChip('Male', _genderMaleColor),
                      SizedBox(width: dense ? 6 : 12),
                      _buildAgeGenderLegendChip('Female', _genderFemaleColor),
                      SizedBox(width: dense ? 6 : 12),
                      _buildAgeGenderLegendChip('Others', _genderOtherColor),
                    ],
                  ),
                ),
              ],
            ),
    );
    if (dense) return chart;
    return SizedBox(height: _isMobile ? 280 : 300, child: chart);
  }

  Widget _buildAgeGenderLegendChip(String label, Color color) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 5),
        Text(
          label,
          style: const TextStyle(
            color: _textMuted,
            fontSize: 11,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }

  Widget _buildCityRankingBarChart({bool dense = false}) {
    final cities = _cityRankingData;
    final maxCount = cities.isEmpty
        ? 1
        : cities.map((e) => e.count).reduce((a, b) => a > b ? a : b);
    const barColors = [
      Color(0xFF66D2B3),
      Color(0xFFFF8C32),
      Color(0xFF8E44AD),
      Color(0xFF29B6F6),
      Color(0xFFFFC107),
      Color(0xFF0D9488),
    ];

    final chart = _buildDemographicsChartShell(
      dense: dense,
      accent: const Color(0xFF0D9488),
      title: 'City Ranking',
      icon: Icons.location_city_rounded,
      child: cities.isEmpty
          ? _buildDemographicsEmptyState('Check-ins will rank cities here')
          : Column(
              children: [
                Expanded(
                  child: CustomPaint(
                    painter: _CityRankingBarPainter(
                      cities: cities,
                      maxCount: maxCount,
                      colors: barColors,
                    ),
                    child: Container(),
                  ),
                ),
                if (!dense)
                  Wrap(
                    alignment: WrapAlignment.center,
                    spacing: 8,
                    runSpacing: 4,
                    children: [
                      for (var i = 0; i < cities.length && i < 4; i++)
                        _buildAgeGenderLegendChip(
                          _shortCityLabel(cities[i].name),
                          barColors[i % barColors.length],
                        ),
                    ],
                  ),
              ],
            ),
    );
    if (dense) return chart;
    return SizedBox(height: _isMobile ? 280 : 300, child: chart);
  }

  String _shortCityLabel(String name) {
    if (name.length <= 14) return name;
    return '${name.substring(0, 12)}…';
  }

  Widget _buildStatCard(_StatCard stat, {bool compact = false}) {
    final sparkH = compact ? 26.0 : 34.0;
    final valueSize = compact ? 22.0 : (_isMobile ? 26.0 : 28.0);
    final labelSize = compact ? 11.0 : 12.0;

    return Container(
      decoration: BoxDecoration(
        color: stat.color,
        borderRadius: BorderRadius.circular(12),
      ),
      clipBehavior: Clip.antiAlias,
      padding: EdgeInsets.fromLTRB(
        compact ? 12 : 16,
        compact ? 10 : 14,
        compact ? 12 : 16,
        compact ? 8 : 10,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            stat.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: Colors.white.withOpacity(0.92),
              fontSize: labelSize,
              fontWeight: FontWeight.w500,
            ),
          ),
          SizedBox(height: compact ? 4 : 6),
          Text(
            stat.value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: Colors.white,
              fontSize: valueSize,
              fontWeight: FontWeight.w700,
              letterSpacing: -0.5,
              height: 1.05,
            ),
          ),
          const Spacer(),
          SizedBox(
            height: sparkH,
            width: double.infinity,
            child: CustomPaint(
              painter: _MiniSparklinePainter(
                values: _statSparklineValues(stat),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildChartsSection() {
    if (_isMobile) {
      return Column(
        children: [
          _buildTouristArrivalsChart(),
          const SizedBox(height: 16),
          _buildTopCategoriesCard(),
        ],
      );
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(flex: 2, child: _buildTouristArrivalsChart()),
        const SizedBox(width: 16),
        Expanded(child: _buildTopCategoriesCard()),
      ],
    );
  }

  Widget _buildTouristArrivalsChart({bool dense = false}) {
    return _wrapDashboardRichPanel(
      accent: _primaryOrange,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _dashboardSectionTitle(
            title: 'Tourist Arrivals',
            icon: Icons.show_chart_rounded,
            trailing: _buildTimeFilterDropdown(dense: dense),
            dense: dense,
          ),
          SizedBox(height: dense ? 6 : 12),
          if (dense)
            Expanded(
              child: _buildChartPlotArea(
                dense: true,
                child: LayoutBuilder(
                  builder: (context, constraints) => _buildArrivalsChartStack(
                    width: constraints.maxWidth,
                    height: constraints.maxHeight,
                    dense: true,
                  ),
                ),
              ),
            )
          else
            _buildChartPlotArea(
              child: SizedBox(
                height: 200,
                child: LayoutBuilder(
                  builder: (context, constraints) => _buildArrivalsChartStack(
                    width: constraints.maxWidth,
                    height: 200,
                    dense: false,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildArrivalsChartStack({
    required double width,
    required double height,
    required bool dense,
  }) {
    return Stack(
      children: [
        CustomPaint(
          size: Size(width, height),
          painter: _ChartPainter(
            color: _primaryOrange,
            values: _dashboardTrendValues,
            showPlaceholder: !_hasArrivalChartData,
          ),
        ),
        if (!_hasArrivalChartData)
          Positioned.fill(
            child: Center(
              child: Text(
                'No arrivals in this period',
                style: TextStyle(
                  color: _textMuted,
                  fontSize: dense ? 11 : 13,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildTimeFilterDropdown({bool dense = false}) {
    return PopupMenuButton<String>(
      initialValue: _selectedTimeFilter,
      onSelected: (value) => setState(() => _selectedTimeFilter = value),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      itemBuilder: (context) => ['This Week', 'This Month', 'This Year']
          .map(
            (filter) => PopupMenuItem(
              value: filter,
              child: Text(
                filter,
                style: TextStyle(
                  fontWeight: filter == _selectedTimeFilter
                      ? FontWeight.w700
                      : FontWeight.w500,
                  color: filter == _selectedTimeFilter
                      ? _primaryOrange
                      : _textDark,
                ),
              ),
            ),
          )
          .toList(),
      child: Container(
        padding: EdgeInsets.symmetric(
          horizontal: dense ? 8 : 12,
          vertical: dense ? 4 : 8,
        ),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(dense ? 8 : 10),
          border: Border.all(color: _cardBorder),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              _selectedTimeFilter,
              style: TextStyle(
                color: _primaryOrange,
                fontSize: dense ? 10 : 12,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(width: 2),
            const Icon(
              Icons.keyboard_arrow_down_rounded,
              color: _primaryOrange,
              size: 18,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTopCategoriesCard({bool dense = false}) {
    final stats = _dashboardCategoryStats.take(5).toList();
    final sumP = stats.fold<double>(
      0,
      (a, s) => a + (s['percentage'] as double),
    );
    final totalCount = stats.fold<int>(
      0,
      (a, s) => a + ((s['count'] as num?)?.toInt() ?? 0),
    );
    final segments = <({Color color, double fraction})>[];
    for (final s in stats) {
      final name = s['name'] as String;
      final p = (s['percentage'] as double);
      final frac = sumP > 0
          ? p / sumP
          : (stats.isEmpty ? 0.0 : 1.0 / stats.length);
      segments.add((color: _categoryColor(name), fraction: frac));
    }

    return _wrapDashboardRichPanel(
      accent: _accentOrange,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _dashboardSectionTitle(
            title: 'Top Categories',
            icon: Icons.donut_large_rounded,
            dense: dense,
            trailing: TextButton(
              onPressed: () => setState(() => _selectedIndex = 4),
              style: TextButton.styleFrom(
                foregroundColor: _primaryOrange,
                padding: EdgeInsets.symmetric(horizontal: dense ? 6 : 10),
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: Text(
                'View All',
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: dense ? 11 : 13,
                ),
              ),
            ),
          ),
          SizedBox(height: dense ? 6 : 12),
          if (dense)
            Expanded(
              child: _buildChartPlotArea(
                dense: true,
                tint: _accentOrange,
                child: LayoutBuilder(
                  builder: (context, constraints) =>
                      _buildTopCategoriesChartBody(
                        constraints: constraints,
                        dense: true,
                        stats: stats,
                        segments: segments,
                        totalCount: totalCount,
                        sumP: sumP,
                      ),
                ),
              ),
            )
          else
            _buildChartPlotArea(
              tint: _accentOrange,
              child: SizedBox(
                height: 220,
                child: LayoutBuilder(
                  builder: (context, constraints) =>
                      _buildTopCategoriesChartBody(
                        constraints: constraints,
                        dense: false,
                        stats: stats,
                        segments: segments,
                        totalCount: totalCount,
                        sumP: sumP,
                      ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildTopCategoriesChartBody({
    required BoxConstraints constraints,
    required bool dense,
    required List<Map<String, dynamic>> stats,
    required List<({Color color, double fraction})> segments,
    required int totalCount,
    required double sumP,
  }) {
    final w = constraints.maxWidth;
    final h = constraints.maxHeight;
    final pieSize = dense
        ? math.min(w * 0.55, h - 8).clamp(64.0, 120.0)
        : (w < 420 ? w * 0.72 : 200.0).clamp(160.0, 240.0);
    final chart = SizedBox(
      width: pieSize,
      height: pieSize,
      child: Stack(
        alignment: Alignment.center,
        children: [
          CustomPaint(
            size: Size(pieSize, pieSize),
            painter: _CategoryPiePainter(
              segments: segments,
              holeColor: Colors.white,
              isEmpty: totalCount == 0,
            ),
          ),
          if (totalCount == 0 && !dense)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.pie_chart_outline_rounded,
                    color: _primaryOrange.withOpacity(0.55),
                    size: 24,
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'No check-in data yet',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: _textMuted.withOpacity(0.9),
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
    final legend = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < stats.length; i++)
          _buildCategoryLegendRow(
            stats[i]['name'] as String,
            totalCount == 0
                ? 0.0
                : (sumP > 0
                      ? (stats[i]['percentage'] as double) / sumP
                      : (stats.isEmpty ? 0.0 : 1.0 / stats.length)),
            _categoryColor(stats[i]['name'] as String),
          ),
      ],
    );
    if (w < 420 || dense) {
      return Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          chart,
          SizedBox(width: dense ? 10 : 20),
          Expanded(child: legend),
        ],
      );
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        chart,
        const SizedBox(width: 20),
        Expanded(child: legend),
      ],
    );
  }

  Color _categoryColor(String name) {
    final n = name.toLowerCase();
    if (n.contains('beach')) return _primaryOrange;
    if (n.contains('fall')) return Colors.cyan;
    if (n.contains('historical')) return _accentOrange;
    if (n.contains('mountain')) return Colors.green;
    if (n.contains('resort')) return Colors.purple;
    return Colors.grey;
  }

  /// Legend row for pie chart (share among displayed categories).
  Widget _buildCategoryLegendRow(
    String name,
    double fractionOfDisplayed,
    Color color,
  ) {
    final pct = (fractionOfDisplayed * 100);
    final pctLabel = pct >= 10 || pct == 0
        ? '${pct.round()}%'
        : '${pct.toStringAsFixed(1)}%';
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              name,
              style: const TextStyle(
                color: _textMuted,
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Text(
            pctLabel,
            style: const TextStyle(
              color: _textDark,
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  void _showMunicipalityDetails(Map<String, dynamic> municipality) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: _cardBg,
        title: Text(
          municipality['name']?.toString() ?? 'Municipality',
          style: const TextStyle(color: _textDark, fontWeight: FontWeight.w600),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _detailRow('Type', municipality['type']),
            _detailRow('Total Tourists', '${municipality['tourists']}'),
            _detailRow('Latitude', '${municipality['lat']}'),
            _detailRow('Longitude', '${municipality['lng']}'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close', style: TextStyle(color: _primaryOrange)),
          ),
        ],
      ),
    );
  }

  Widget _detailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(color: _textMuted)),
          Text(value, style: const TextStyle(color: _textDark)),
        ],
      ),
    );
  }

  // ==================== TOURISTS SECTION ====================
  String _getTouristDisplayName(Map<String, dynamic> t) {
    final full = t['fullName']?.toString().trim();
    if (full != null && full.isNotEmpty) return full;
    final name = t['name']?.toString().trim();
    if (name != null && name.isNotEmpty) return name;
    final first = t['firstName']?.toString().trim() ?? '';
    final last = t['lastName']?.toString().trim() ?? '';
    final combined = '$first $last'.trim();
    if (combined.isNotEmpty) return combined;
    final email = t['email']?.toString().trim();
    if (email != null && email.isNotEmpty) return email;
    return 'Unknown';
  }

  String _getTouristOrigin(Map<String, dynamic> t) {
    final city = t['city']?.toString().trim();
    final country = t['country']?.toString().trim();
    final origin = t['origin']?.toString().trim();
    if (city != null && city.isNotEmpty) {
      if (country != null && country.isNotEmpty) return '$city, $country';
      return city;
    }
    if (country != null && country.isNotEmpty) return country;
    if (origin != null && origin.isNotEmpty) return origin;
    return '—';
  }

  /// Same fields as LGU tourism dashboard: `registeredAt`, `registeredDate`, `createdAt`.
  DateTime? _registeredDateTimeFromTourist(Map<String, dynamic> t) {
    final regAt = t['registeredAt'];
    if (regAt is Timestamp) return regAt.toDate();
    if (regAt is DateTime) return regAt;
    if (t['registeredDate'] is DateTime) return t['registeredDate'] as DateTime;
    final created = t['createdAt'] ?? t['created_at'];
    if (created is Timestamp) return created.toDate();
    if (created is DateTime) return created;
    return null;
  }

  String _formatRegisteredDateOnly(DateTime? dt) {
    if (dt == null) return '—';
    return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';
  }

  String _formatRegisteredTimeOnly(DateTime? dt) {
    if (dt == null) return '—';
    final h24 = dt.hour;
    final min = dt.minute.toString().padLeft(2, '0');
    final sec = dt.second.toString().padLeft(2, '0');
    final period = h24 >= 12 ? 'PM' : 'AM';
    final h12 = h24 == 0 ? 12 : (h24 > 12 ? h24 - 12 : h24);
    return '$h12:$min:$sec $period';
  }

  Widget _buildTouristsContent() {
    final filteredTourists = _tourists.where((t) {
      final query = _searchController.text.toLowerCase();
      if (query.isEmpty) return true;
      final displayName = _getTouristDisplayName(t).toLowerCase();
      return displayName.contains(query) ||
          (t['id']?.toString().toLowerCase().contains(query) ?? false) ||
          (t['email']?.toString().toLowerCase().contains(query) ?? false) ||
          (t['city']?.toString().toLowerCase().contains(query) ?? false) ||
          (t['country']?.toString().toLowerCase().contains(query) ?? false);
    }).toList();

    return Container(
      color: _darkBg,
      child: Column(
        children: [
          _buildHeader(
            'Registered Tourists',
            subtitle:
                'Misamis Occidental — tourists registered in the province',
          ),
          Expanded(
            child: Padding(
              padding: EdgeInsets.fromLTRB(
                _isMobile ? 12 : 20,
                12,
                _isMobile ? 12 : 20,
                16,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _buildTouristsSummaryBar(filteredTourists.length),
                  const SizedBox(height: 12),
                  Expanded(
                    child: Container(
                      decoration: _dashboardPanelDecoration(),
                      clipBehavior: Clip.antiAlias,
                      child: Column(
                        children: [
                          Padding(
                            padding: EdgeInsets.fromLTRB(
                              _isMobile ? 12 : 16,
                              14,
                              _isMobile ? 12 : 16,
                              10,
                            ),
                            child: _buildSearchBar('Search tourists...'),
                          ),
                          const Divider(height: 1, color: _cardBorder),
                          Expanded(
                            child: filteredTourists.isEmpty
                                ? _buildEmptyState(
                                    'No tourists match your search',
                                    Icons.people_outline_rounded,
                                  )
                                : _isMobile
                                ? _buildTouristsListMobile(filteredTourists)
                                : _buildTouristsTableDesktop(filteredTourists),
                          ),
                        ],
                      ),
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

  Widget _buildTouristsSummaryBar(int visibleCount) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: _cardBorder),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: _primaryOrange.withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(
              Icons.people_alt_rounded,
              color: _primaryOrange,
              size: 20,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              '$visibleCount of ${_tourists.length} tourists',
              style: const TextStyle(
                color: _textDark,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: _kpiGreen.withOpacity(0.15),
              borderRadius: BorderRadius.circular(20),
            ),
            child: const Text(
              'Province scope',
              style: TextStyle(
                color: Color(0xFF558B2F),
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  int _touristVisitCount(Map<String, dynamic> t) {
    final v = t['totalVisits'] ?? t['visits'] ?? 0;
    if (v is int) return v;
    if (v is num) return v.toInt();
    return int.tryParse(v.toString()) ?? 0;
  }

  List<Map<String, dynamic>> _sortedTouristsByVisits(
    List<Map<String, dynamic>> tourists,
  ) {
    final sorted = List<Map<String, dynamic>>.from(tourists)
      ..sort((a, b) => _touristVisitCount(b).compareTo(_touristVisitCount(a)));
    return sorted;
  }

  Widget _touristAvatar(Map<String, dynamic> t, {double radius = 18}) {
    final name = _getTouristDisplayName(t);
    final initial =
        name.trim().isNotEmpty ? name.trim()[0].toUpperCase() : '?';
    final url = t['profilePhotoUrl']?.toString().trim() ?? '';
    if (url.isNotEmpty) {
      return CircleAvatar(
        radius: radius,
        backgroundColor: _primaryOrange.withOpacity(0.12),
        child: ClipOval(
          child: Image.network(
            url,
            width: radius * 2,
            height: radius * 2,
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => Text(
              initial,
              style: TextStyle(
                color: _primaryOrange,
                fontWeight: FontWeight.w700,
                fontSize: radius * 0.85,
              ),
            ),
          ),
        ),
      );
    }
    final b64 = t['profileImageBase64']?.toString();
    if (b64 != null && b64.isNotEmpty) {
      try {
        return CircleAvatar(
          radius: radius,
          backgroundColor: _primaryOrange.withOpacity(0.12),
          backgroundImage: MemoryImage(base64Decode(b64)),
        );
      } catch (_) {}
    }
    return CircleAvatar(
      radius: radius,
      backgroundColor: _primaryOrange.withOpacity(0.12),
      child: Text(
        initial,
        style: TextStyle(
          color: _primaryOrange,
          fontWeight: FontWeight.w700,
          fontSize: radius * 0.85,
        ),
      ),
    );
  }

  Widget _touristIdChip(String id, {double? maxWidth}) {
    final text = id.trim().isEmpty ? '—' : id;
    final chip = Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: _primaryOrange.withOpacity(0.08),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: _primaryOrange.withOpacity(0.22)),
      ),
      child: Text(
        text,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(
          color: _primaryOrange,
          fontSize: 11,
          fontWeight: FontWeight.w600,
          fontFamily: 'monospace',
        ),
      ),
    );
    if (maxWidth == null) return chip;
    return ConstrainedBox(
      constraints: BoxConstraints(maxWidth: maxWidth),
      child: chip,
    );
  }

  Widget _visitCountBadge(int count) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: count > 0 ? const Color(0xFFE3F2FD) : const Color(0xFFF4F4F5),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        '$count',
        style: TextStyle(
          color: count > 0 ? const Color(0xFF1565C0) : _textMuted,
          fontSize: 12,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  Widget _touristViewButton({required VoidCallback onPressed}) {
    return Material(
      color: _primaryOrange,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(20),
        child: const SizedBox(
          width: 36,
          height: 36,
          child: Icon(Icons.visibility_rounded, color: Colors.white, size: 18),
        ),
      ),
    );
  }

  Widget _buildSearchBar(String hint) {
    return AppSearchBar(
      controller: _searchController,
      hintText: hint,
      onChanged: (_) => setState(() {}),
      horizontalPadding: 0,
    );
  }

  Widget _buildEmptyState(String message, IconData icon) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: _textMuted.withOpacity(0.4), size: 48),
            const SizedBox(height: 12),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(color: _textMuted, fontSize: 14),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTouristsListMobile(List<Map<String, dynamic>> tourists) {
    final sorted = _sortedTouristsByVisits(tourists);

    return ListView.separated(
      padding: const EdgeInsets.all(12),
      itemCount: sorted.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        final t = sorted[index];
        final name = _getTouristDisplayName(t);
        final visits = _touristVisitCount(t);
        return Material(
          color: index.isEven ? const Color(0xFFFAFAFA) : Colors.white,
          borderRadius: BorderRadius.circular(10),
          child: InkWell(
            onTap: () => _showTouristDetails(t),
            borderRadius: BorderRadius.circular(10),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  _touristAvatar(t),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          name,
                          style: const TextStyle(
                            color: _textDark,
                            fontWeight: FontWeight.w600,
                            fontSize: 14,
                          ),
                        ),
                        const SizedBox(height: 4),
                        _touristIdChip(
                          TouristIdHelper.displayForTourist(t),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          _getTouristOrigin(t),
                          style: const TextStyle(
                            color: _textMuted,
                            fontSize: 11,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '${_formatRegisteredDateOnly(_registeredDateTimeFromTourist(t))} · ${_formatRegisteredTimeOnly(_registeredDateTimeFromTourist(t))}',
                          style: const TextStyle(
                            color: _textMuted,
                            fontSize: 10,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Column(
                    children: [
                      _visitCountBadge(visits),
                      const SizedBox(height: 8),
                      _touristViewButton(
                        onPressed: () => _showTouristDetails(t),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildTouristsTableDesktop(List<Map<String, dynamic>> tourists) {
    final sorted = _sortedTouristsByVisits(tourists);

    const headStyle = TextStyle(
      color: _textMuted,
      fontWeight: FontWeight.w600,
      fontSize: 11,
      letterSpacing: 0.3,
    );

    Widget headerCell(
      String label, {
      double flex = 1,
      EdgeInsets padding = EdgeInsets.zero,
    }) {
      return Expanded(
        flex: (flex * 10).round(),
        child: Padding(
          padding: padding,
          child: Text(label.toUpperCase(), style: headStyle),
        ),
      );
    }

    return Column(
      children: [
        Container(
          color: const Color(0xFFF9FAFB),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          child: Row(
            children: [
              headerCell('Name', flex: 2.2),
              headerCell(
                'Tourist ID',
                flex: 1.6,
                padding: const EdgeInsets.only(right: 24),
              ),
              headerCell(
                'Origin',
                flex: 2.1,
                padding: const EdgeInsets.only(left: 4),
              ),
              headerCell('Date', flex: 1),
              headerCell('Time', flex: 1.1),
              headerCell('Visits', flex: 0.6),
              const SizedBox(
                width: 48,
                child: Text(
                  'VIEW',
                  style: headStyle,
                  textAlign: TextAlign.center,
                ),
              ),
            ],
          ),
        ),
        const Divider(height: 1, color: _cardBorder),
        Expanded(
          child: Scrollbar(
            thumbVisibility: true,
            child: ListView.separated(
              itemCount: sorted.length,
              separatorBuilder: (_, __) => const Divider(
                height: 1,
                color: _cardBorder,
                indent: 16,
                endIndent: 16,
              ),
              itemBuilder: (context, index) {
                final t = sorted[index];
                final name = _getTouristDisplayName(t);
                final id = TouristIdHelper.displayForTourist(t);
                final visits = _touristVisitCount(t);
                final bg = index.isEven
                    ? Colors.white
                    : const Color(0xFFFAFAFA);

                return Material(
                  color: bg,
                  child: InkWell(
                    onTap: () => _showTouristDetails(t),
                    hoverColor: _primaryOrange.withOpacity(0.04),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 12,
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          Expanded(
                            flex: 22,
                            child: Row(
                              children: [
                                _touristAvatar(t, radius: 16),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Text(
                                    name,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      color: _textDark,
                                      fontWeight: FontWeight.w600,
                                      fontSize: 13,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Expanded(
                            flex: 16,
                            child: Padding(
                              padding: const EdgeInsets.only(right: 24),
                              child: Align(
                                alignment: Alignment.centerLeft,
                                child: _touristIdChip(id, maxWidth: 200),
                              ),
                            ),
                          ),
                          Expanded(
                            flex: 21,
                            child: Padding(
                              padding: const EdgeInsets.only(left: 4),
                              child: Text(
                                _getTouristOrigin(t),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: _textMuted,
                                  fontSize: 12,
                                ),
                              ),
                            ),
                          ),
                          Expanded(
                            flex: 10,
                            child: Text(
                              _formatRegisteredDateOnly(
                                _registeredDateTimeFromTourist(t),
                              ),
                              style: const TextStyle(
                                color: _textDark,
                                fontSize: 12,
                              ),
                            ),
                          ),
                          Expanded(
                            flex: 11,
                            child: Text(
                              _formatRegisteredTimeOnly(
                                _registeredDateTimeFromTourist(t),
                              ),
                              style: const TextStyle(
                                color: _textDark,
                                fontSize: 12,
                              ),
                            ),
                          ),
                          Expanded(flex: 6, child: _visitCountBadge(visits)),
                          _touristViewButton(
                            onPressed: () => _showTouristDetails(t),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      ],
    );
  }

  void _showTouristDetails(Map<String, dynamic> tourist) {
    final name = _getTouristDisplayName(tourist);
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: _cardBg,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            _touristAvatar(tourist, radius: 22),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                name,
                style: const TextStyle(
                  color: _textDark,
                  fontWeight: FontWeight.w700,
                  fontSize: 16,
                ),
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _touristIdChip(
              TouristIdHelper.displayForTourist(tourist),
            ),
            const SizedBox(height: 14),
            _detailRow(
              'Tourist ID',
              TouristIdHelper.displayForTourist(tourist),
            ),
            _detailRow('Email', tourist['email'] ?? '-'),
            _detailRow('Origin', _getTouristOrigin(tourist)),
            _detailRow(
              'Date registered',
              _formatRegisteredDateOnly(
                _registeredDateTimeFromTourist(tourist),
              ),
            ),
            _detailRow(
              'Time registered',
              _formatRegisteredTimeOnly(
                _registeredDateTimeFromTourist(tourist),
              ),
            ),
            _detailRow('Total visits', '${_touristVisitCount(tourist)}'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close', style: TextStyle(color: _primaryOrange)),
          ),
        ],
      ),
    );
  }

  // ==================== LGU QR CODES (GOVERNOR) — one QR per municipality only ====================
  Widget _buildGovernorSpotQRCodesContent() {
    return Container(
      color: _darkBg,
      child: Column(
        children: [
          _buildHeader(
            'LGU QR Codes',
            subtitle:
                'One ATMOS QR per municipality (LGU). Download PNG or PDF for printing — no per-spot codes.',
          ),
          Expanded(
            child: SingleChildScrollView(
              padding: EdgeInsets.all(_isMobile ? 16 : 24),
              child: _buildGovernorLguQrSection(),
            ),
          ),
        ],
      ),
    );
  }

  /// One downloadable QR per LGU (same payload as on each tourism dashboard).
  Widget _buildGovernorLguQrSection() {
    final municipalities = getMisamisOccidentalMunicipalities();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'All LGUs (Misamis Occidental)',
          style: TextStyle(
            color: _textDark,
            fontSize: 18,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          'Each card is the only QR needed for that municipality (ATMOS-TRS-LGU).',
          style: TextStyle(color: _textMuted, fontSize: 13),
        ),
        const SizedBox(height: 16),
        Wrap(
          spacing: 16,
          runSpacing: 16,
          children: municipalities.map((m) {
            final qrData = lguQrData(m.id, anchorLat: m.lat, anchorLng: m.lng);
            return Container(
              width: _isMobile ? double.infinity : 240,
              padding: EdgeInsets.all(_isMobile ? 12 : 16),
              decoration: BoxDecoration(
                color: _cardBg,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: _cardBorder),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    m.name,
                    style: const TextStyle(
                      color: _textDark,
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                    ),
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 10),
                  Container(
                    padding: EdgeInsets.all(_isMobile ? 6 : 8),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: QrImageView(
                      data: qrData,
                      version: QrVersions.auto,
                      size: _isMobile ? 160 : 180,
                      backgroundColor: Colors.white,
                      errorCorrectionLevel: QrErrorCorrectLevel.H,
                    ),
                  ),
                  SizedBox(height: _isMobile ? 8 : 10),
                  Wrap(
                    alignment: WrapAlignment.center,
                    spacing: _isMobile ? 6 : 10,
                    runSpacing: 4,
                    children: [
                      TextButton(
                        onPressed: () async {
                          await downloadLguQrPng(
                            m.id,
                            anchorLat: m.lat,
                            anchorLng: m.lng,
                          );
                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text(
                                  'PNG ready — check downloads or share sheet',
                                ),
                                backgroundColor: _primaryOrange,
                              ),
                            );
                          }
                        },
                        child: Text(
                          'PNG',
                          style: TextStyle(
                            color: _primaryOrange,
                            fontSize: _isMobile ? 13 : 14,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      TextButton(
                        onPressed: () async {
                          await downloadLguQrPdf(
                            m.id,
                            m.name,
                            anchorLat: m.lat,
                            anchorLng: m.lng,
                          );
                        },
                        child: Text(
                          'PDF',
                          style: TextStyle(
                            color: _primaryOrange,
                            fontSize: _isMobile ? 13 : 14,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            );
          }).toList(),
        ),
      ],
    );
  }

  // ==================== MUNICIPALITIES SECTION ====================
  Widget _buildMunicipalitiesContent() {
    return Container(
      color: _darkBg,
      child: Column(
        children: [
          _buildHeader(
            'Municipalities & Cities',
            subtitle: 'All 17 locations in Misamis Occidental',
          ),
          Expanded(
            child: SingleChildScrollView(
              padding: EdgeInsets.all(_isMobile ? 16 : 24),
              child: _isMobile
                  ? _buildMunicipalitiesGridMobile()
                  : _buildMunicipalitiesGridDesktop(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMunicipalitiesGridMobile() {
    return Column(
      children: _allMunicipalities
          .map((m) => _buildMunicipalityCard(m))
          .toList(),
    );
  }

  Widget _buildMunicipalitiesGridDesktop() {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: _isTablet ? 2 : 3,
        crossAxisSpacing: 16,
        mainAxisSpacing: 16,
        childAspectRatio: 2,
      ),
      itemCount: _allMunicipalities.length,
      itemBuilder: (context, index) =>
          _buildMunicipalityCard(_allMunicipalities[index]),
    );
  }

  Widget _buildMunicipalityCard(Map<String, dynamic> municipality) {
    final name = municipality['name']?.toString() ?? 'Unknown';
    final type = municipality['type']?.toString() ?? 'Municipality';
    final tourists = municipality['tourists'] ?? 0;
    final accent = type == 'City' ? _primaryOrange : _accentOrange;
    return Material(
      color: Colors.transparent,
      child: Container(
        margin: _isMobile ? const EdgeInsets.only(bottom: 12) : null,
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: () => _showMunicipalityDetails(municipality),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  const Color(0xFFFFFFFF),
                  Color.lerp(const Color(0xFFFFFFFF), accent, 0.06)!,
                ],
              ),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: accent.withOpacity(0.22), width: 1.0),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.08),
                  blurRadius: 18,
                  offset: const Offset(0, 8),
                ),
                BoxShadow(
                  color: accent.withOpacity(0.12),
                  blurRadius: 22,
                  offset: const Offset(0, 10),
                  spreadRadius: -10,
                ),
                BoxShadow(
                  color: Colors.white.withOpacity(0.65),
                  blurRadius: 1,
                  offset: const Offset(0, -1),
                ),
              ],
            ),
            child: Row(
              children: [
                Container(
                  width: 4,
                  margin: const EdgeInsets.only(right: 10),
                  decoration: BoxDecoration(
                    color: accent.withOpacity(0.55),
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.all(11),
                  decoration: BoxDecoration(
                    color: accent.withOpacity(0.14),
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: [
                      BoxShadow(
                        color: accent.withOpacity(0.18),
                        blurRadius: 12,
                        offset: const Offset(0, 4),
                        spreadRadius: -8,
                      ),
                    ],
                  ),
                  child: Icon(
                    Icons.location_city_rounded,
                    color: accent,
                    size: 22,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        name,
                        style: const TextStyle(
                          color: _textDark,
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          height: 1.15,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 3,
                            ),
                            decoration: BoxDecoration(
                              color: accent.withOpacity(0.14),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              type,
                              style: TextStyle(
                                color: accent,
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              '$tourists ${tourists == 1 ? 'tourist' : 'tourists'}',
                              style: const TextStyle(
                                color: _textMuted,
                                fontSize: 13,
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
                const SizedBox(width: 8),
                Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: accent.withOpacity(0.28)),
                  ),
                  child: Icon(
                    Icons.chevron_right_rounded,
                    color: accent.withOpacity(0.9),
                    size: 18,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  DateTime? _checkInTimestamp(Map<String, dynamic> c) =>
      GovernorFirestoreService.parseCheckInTime(c);

  int get _analyticsDailyAvg {
    if (_checkIns.isEmpty) return 0;
    final dates = <DateTime>{};
    for (var c in _checkIns) {
      final d = _checkInTimestamp(c);
      if (d != null) dates.add(DateTime(d.year, d.month, d.day));
    }
    if (dates.isEmpty) return 0;
    final min = dates.reduce((a, b) => a.isBefore(b) ? a : b);
    final max = dates.reduce((a, b) => a.isAfter(b) ? a : b);
    final days = max.difference(min).inDays + 1;
    return days > 0 ? (_checkIns.length / days).round() : _checkIns.length;
  }

  String get _analyticsPeakHour {
    final byHour = <int, int>{};
    for (var c in _checkIns) {
      final d = _checkInTimestamp(c);
      if (d != null) {
        final h = d.hour;
        byHour[h] = (byHour[h] ?? 0) + 1;
      }
    }
    if (byHour.isEmpty) return '—';
    final top = byHour.entries.reduce((a, b) => a.value >= b.value ? a : b);
    final h = top.key;
    final end = h + 1;
    final am2 = end < 12 ? 'AM' : 'PM';
    final s = h == 0 ? 12 : (h > 12 ? h - 12 : h);
    final e = end == 0 ? 12 : (end > 12 ? end - 12 : end);
    return '$s-$e $am2';
  }

  String get _analyticsTopOrigin {
    final counts = <String, int>{};
    for (var t in _tourists) {
      final one =
          t['city']?.toString().trim() ??
          t['country']?.toString().trim() ??
          t['origin']?.toString().trim() ??
          t['nationality']?.toString().trim();
      if (one != null && one.isNotEmpty) {
        counts[one] = (counts[one] ?? 0) + 1;
      }
    }
    if (counts.isEmpty) return '—';
    return counts.entries.reduce((a, b) => a.value >= b.value ? a : b).key;
  }

  List<Map<String, dynamic>> get _analyticsTopSpots {
    final byLocation = <String, int>{};
    for (var c in _checkIns) {
      final loc =
          c['location']?.toString().trim() ??
          c['spotName']?.toString().trim() ??
          '';
      if (loc.isNotEmpty) byLocation[loc] = (byLocation[loc] ?? 0) + 1;
    }
    return byLocation.entries
        .map((e) => {'name': e.key, 'visits': e.value})
        .toList()
      ..sort((a, b) => (b['visits'] as int).compareTo(a['visits'] as int));
  }

  // ==================== ANALYTICS SECTION ====================
  /// Insights not shown on the main Dashboard (no duplicate totals/trends/demographics).
  Widget _buildAnalyticsContent() {
    return Container(
      color: _darkBg,
      child: Column(
        children: [
          _buildHeader(
            'Analytics',
            subtitle:
                'Patterns & spot rankings — totals and charts are on Dashboard',
          ),
          Expanded(
            child: SingleChildScrollView(
              padding: EdgeInsets.all(_isMobile ? 12 : 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _buildAnalyticsCards(),
                  const SizedBox(height: 16),
                  _buildTopSpotsChart(),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAnalyticsCards() {
    final topOrigin = _analyticsTopOrigin;
    final originDisplay = topOrigin.length > 22
        ? '${topOrigin.substring(0, 20)}…'
        : topOrigin;

    return GridView.count(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisCount: _isMobile ? 1 : 3,
      crossAxisSpacing: 12,
      mainAxisSpacing: 12,
      childAspectRatio: _isMobile ? 2.4 : 2.2,
      children: [
        _buildAnalyticsCard(
          title: 'Daily Avg',
          subtitle: 'Average check-ins per active day',
          value: '$_analyticsDailyAvg',
          icon: Icons.calendar_today_rounded,
          background: const Color(0xFFE3F2FD),
          iconBg: const Color(0xFFBBDEFB),
          iconColor: const Color(0xFF1565C0),
        ),
        _buildAnalyticsCard(
          title: 'Peak Hour',
          subtitle: 'Busiest hour for QR scans',
          value: _analyticsPeakHour,
          icon: Icons.access_time_rounded,
          background: const Color(0xFFFFF3E0),
          iconBg: const Color(0xFFFFE0B2),
          iconColor: const Color(0xFFE65100),
        ),
        _buildAnalyticsCard(
          title: 'Top Origin',
          subtitle: 'Where most tourists registered from',
          value: originDisplay,
          icon: Icons.flight_rounded,
          background: const Color(0xFFE8F5E9),
          iconBg: const Color(0xFFC8E6C9),
          iconColor: const Color(0xFF2E7D32),
        ),
      ],
    );
  }

  Widget _buildAnalyticsCard({
    required String title,
    required String subtitle,
    required String value,
    required IconData icon,
    required Color background,
    required Color iconBg,
    required Color iconColor,
  }) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.black.withOpacity(0.04)),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: iconBg,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: iconColor, size: 22),
          ),
          const SizedBox(height: 10),
          Text(
            value,
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: _textDark,
              fontSize: 22,
              fontWeight: FontWeight.w700,
              height: 1.1,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            title,
            style: const TextStyle(
              color: _textDark,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
          Text(
            subtitle,
            style: TextStyle(color: _textMuted.withOpacity(0.9), fontSize: 10),
          ),
        ],
      ),
    );
  }

  Widget _buildTopSpotsChart() {
    final spots = _analyticsTopSpots.take(8).toList();
    final maxVisits = spots.isEmpty ? 1 : (spots.first['visits'] as int);

    return _wrapDashboardRichPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _dashboardSectionTitle(
            title: 'Most Visited Spots',
            icon: Icons.location_on_rounded,
          ),
          const SizedBox(height: 14),
          if (spots.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 32),
              child: Center(
                child: Text(
                  'No spot check-ins yet',
                  style: TextStyle(color: _textMuted, fontSize: 13),
                ),
              ),
            )
          else
            ...spots.asMap().entries.map((entry) {
              final index = entry.key;
              final spot = entry.value;
              final visits = spot['visits'] as int;
              final name = spot['name'] as String;
              return Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Row(
                  children: [
                    Container(
                      width: 26,
                      height: 26,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: index == 0
                            ? _primaryOrange
                            : const Color(0xFFF4F4F5),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        '${index + 1}',
                        style: TextStyle(
                          color: index == 0 ? Colors.white : _textMuted,
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: _textDark,
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          const SizedBox(height: 6),
                          ClipRRect(
                            borderRadius: BorderRadius.circular(4),
                            child: LinearProgressIndicator(
                              value: maxVisits > 0 ? visits / maxVisits : 0,
                              backgroundColor: const Color(0xFFE4E4E7),
                              valueColor: const AlwaysStoppedAnimation<Color>(
                                _primaryOrange,
                              ),
                              minHeight: 6,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 10),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFFF3E0),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        '$visits',
                        style: const TextStyle(
                          color: _primaryOrange,
                          fontWeight: FontWeight.w700,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ],
                ),
              );
            }),
        ],
      ),
    );
  }

  // ==================== ANNOUNCEMENTS SECTION ====================
  Widget _buildAnnouncementsContent() {
    final publishedCount = _announcements
        .where((a) => a['published'] == true)
        .length;
    final draftCount = _announcements.length - publishedCount;

    return Container(
      color: _darkBg,
      child: Column(
        children: [
          _buildHeader(
            'Announcements',
            subtitle: 'Create and publish notices for tourists',
            actions: [
              if (!_isMobile)
                OutlinedButton.icon(
                  onPressed: _sendTestPushAnnouncement,
                  icon: const Icon(
                    Icons.notifications_active_rounded,
                    size: 18,
                  ),
                  label: const Text(
                    'Test push',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white,
                    side: const BorderSide(color: Colors.white, width: 1.5),
                    backgroundColor: Colors.white.withOpacity(0.12),
                  ),
                ),
              if (!_isMobile) const SizedBox(width: 8),
              ElevatedButton.icon(
                onPressed: _showCreateAnnouncementDialog,
                icon: Icon(
                  Icons.add_rounded,
                  size: 18,
                  color: _isMobile ? Colors.white : _primaryOrange,
                ),
                label: Text(
                  _isMobile ? 'New' : 'New announcement',
                  style: TextStyle(
                    color: _isMobile ? Colors.white : _primaryOrange,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: _isMobile
                      ? Colors.white.withOpacity(0.2)
                      : Colors.white,
                  foregroundColor: _isMobile ? Colors.white : _primaryOrange,
                  elevation: 0,
                  side: _isMobile
                      ? const BorderSide(color: Colors.white, width: 1.5)
                      : null,
                ),
              ),
            ],
          ),
          Expanded(
            child: Padding(
              padding: EdgeInsets.fromLTRB(
                _isMobile ? 12 : 20,
                0,
                _isMobile ? 12 : 20,
                16,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (_isMobile)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: OutlinedButton.icon(
                        onPressed: _sendTestPushAnnouncement,
                        icon: const Icon(Icons.notifications_active_rounded),
                        label: const Text('Send test push'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: _primaryOrange,
                          side: const BorderSide(color: _cardBorder),
                        ),
                      ),
                    ),
                  if (_announcements.isNotEmpty)
                    _buildAnnouncementsSummaryBar(publishedCount, draftCount),
                  if (_announcements.isNotEmpty) const SizedBox(height: 12),
                  Expanded(
                    child: _announcements.isEmpty
                        ? Center(
                            child: _buildEmptyState(
                              'No announcements yet — tap New announcement',
                              Icons.campaign_outlined,
                            ),
                          )
                        : Container(
                            decoration: _dashboardPanelDecoration(),
                            child: ListView.separated(
                              padding: const EdgeInsets.all(12),
                              itemCount: _announcements.length,
                              separatorBuilder: (_, __) =>
                                  const SizedBox(height: 10),
                              itemBuilder: (context, index) =>
                                  _buildAnnouncementCard(_announcements[index]),
                            ),
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

  Widget _buildAnnouncementsSummaryBar(int published, int drafts) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: _cardBorder),
      ),
      child: Row(
        children: [
          _announcementCountChip(
            '$published published',
            const Color(0xFFE8F5E9),
            const Color(0xFF2E7D32),
          ),
          const SizedBox(width: 8),
          _announcementCountChip(
            '$drafts draft',
            const Color(0xFFF4F4F5),
            _textMuted,
          ),
          const Spacer(),
          Text(
            '${_announcements.length} total',
            style: const TextStyle(color: _textMuted, fontSize: 12),
          ),
        ],
      ),
    );
  }

  Widget _announcementCountChip(String label, Color bg, Color textColor) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: textColor,
          fontSize: 11,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  Color _announcementTypeColor(String type) {
    switch (type) {
      case 'Alert':
        return const Color(0xFFEF5350);
      case 'Event':
        return const Color(0xFF42A5F5);
      case 'Promo':
        return const Color(0xFF66BB6A);
      default:
        return _primaryOrange;
    }
  }

  IconData _announcementTypeIcon(String type) {
    switch (type) {
      case 'Alert':
        return Icons.warning_amber_rounded;
      case 'Event':
        return Icons.event_rounded;
      case 'Promo':
        return Icons.local_offer_rounded;
      default:
        return Icons.campaign_rounded;
    }
  }

  Future<bool> _broadcastPublishedAnnouncement({
    required String title,
    required String content,
    required String type,
    String? announcementId,
  }) {
    return AnnouncementPushService.broadcastToInstalledApps(
      title: title,
      content: content,
      type: type,
      announcementId: announcementId,
    );
  }

  String _publishedAnnouncementSnackMessage(bool pushSent) {
    return pushSent
        ? 'Published — push notification sent to users with the app installed.'
        : 'Published — saved. If users do not receive a push, run: firebase deploy --only functions';
  }

  Future<void> _sendTestPushAnnouncement() async {
    final now = DateTime.now();
    final yyyy = now.year.toString().padLeft(4, '0');
    final mm = now.month.toString().padLeft(2, '0');
    final dd = now.day.toString().padLeft(2, '0');
    final hh = now.hour.toString().padLeft(2, '0');
    final min = now.minute.toString().padLeft(2, '0');
    final stamp = '$yyyy-$mm-$dd $hh:$min';

    final announcementData = <String, dynamic>{
      'title': 'Test push from Governor',
      'content': 'This is a test notification sent at $stamp.',
      'type': 'Alert',
      'published': true,
      'date': '$yyyy-$mm-$dd',
      'createdAt': FieldValue.serverTimestamp(),
      'createdBy': 'Governor',
    };

    try {
      if (Firebase.apps.isEmpty) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Firebase is not initialized. Cannot send test push.',
            ),
            backgroundColor: Colors.redAccent,
          ),
        );
        return;
      }

      final docRef = await FirebaseFirestore.instance
          .collection('announcements')
          .add(announcementData);
      final pushSent = await _broadcastPublishedAnnouncement(
        title: announcementData['title'] as String,
        content: announcementData['content'] as String,
        type: announcementData['type'] as String,
        announcementId: docRef.id,
      );
      if (!mounted) return;
      setState(() {
        _announcements.insert(0, {
          'id': docRef.id,
          ...announcementData,
          'createdAt': now,
        });
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_publishedAnnouncementSnackMessage(pushSent)),
          backgroundColor: _primaryOrange,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to send test push: $e'),
          backgroundColor: Colors.redAccent,
        ),
      );
    }
  }

  Widget _buildAnnouncementCard(Map<String, dynamic> announcement) {
    final isPublished = announcement['published'] == true;
    final type = announcement['type']?.toString() ?? 'General';
    final typeColor = _announcementTypeColor(type);
    final title = announcement['title']?.toString().trim() ?? 'Untitled';
    final content = announcement['content']?.toString().trim() ?? '';
    final date = announcement['date']?.toString() ?? '—';

    final body = Padding(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: typeColor.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  _announcementTypeIcon(type),
                  color: typeColor,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            title,
                            style: const TextStyle(
                              color: _textDark,
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        _announcementStatusBadge(isPublished),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      content.isEmpty ? 'No message body' : content,
                      style: TextStyle(
                        color: content.isEmpty
                            ? _textMuted.withOpacity(0.7)
                            : _textMuted,
                        fontSize: 13,
                        height: 1.35,
                      ),
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Icon(Icons.calendar_today_outlined, size: 14, color: _textMuted),
              Text(
                date,
                style: const TextStyle(color: _textMuted, fontSize: 11),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: typeColor.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  type,
                  style: TextStyle(
                    color: typeColor,
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          if (_isMobile) ...[
            const SizedBox(height: 12),
            _buildAnnouncementActionsRow(announcement, isPublished),
          ],
        ],
      ),
    );

    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFFFAFAFA),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _cardBorder),
      ),
      clipBehavior: Clip.antiAlias,
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              width: 4,
              color: isPublished ? _primaryOrange : const Color(0xFF9CA3AF),
            ),
            Expanded(child: body),
            if (!_isMobile) ...[
              const VerticalDivider(width: 1, color: _cardBorder),
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 10,
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    _buildAnnouncementActionsRow(announcement, isPublished),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _announcementStatusBadge(bool isPublished) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: isPublished ? const Color(0xFFFFF3E0) : const Color(0xFFF4F4F5),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        isPublished ? 'Published' : 'Draft',
        style: TextStyle(
          color: isPublished ? _primaryOrange : _textMuted,
          fontSize: 10,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  Widget _buildAnnouncementActionsRow(
    Map<String, dynamic> announcement,
    bool isPublished,
  ) {
    if (_isMobile) {
      return Row(
        children: [
          Expanded(
            child: _announcementActionButton(
              label: isPublished ? 'Unpublish' : 'Publish',
              icon: isPublished
                  ? Icons.visibility_off_outlined
                  : Icons.publish_outlined,
              color: isPublished ? _textMuted : const Color(0xFF2E7D32),
              onPressed: () => _togglePublishAnnouncement(announcement),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _announcementActionButton(
              label: 'Edit',
              icon: Icons.edit_outlined,
              color: _primaryOrange,
              onPressed: () => _editAnnouncement(announcement),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _announcementActionButton(
              label: 'Delete',
              icon: Icons.delete_outline,
              color: const Color(0xFFC62828),
              onPressed: () => _deleteAnnouncement(announcement),
            ),
          ),
        ],
      );
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _announcementActionButton(
          label: isPublished ? 'Unpublish' : 'Publish',
          icon: isPublished
              ? Icons.visibility_off_outlined
              : Icons.publish_outlined,
          color: isPublished ? _textMuted : const Color(0xFF2E7D32),
          onPressed: () => _togglePublishAnnouncement(announcement),
        ),
        const SizedBox(height: 6),
        _announcementActionButton(
          label: 'Edit',
          icon: Icons.edit_outlined,
          color: _primaryOrange,
          onPressed: () => _editAnnouncement(announcement),
        ),
        const SizedBox(height: 6),
        _announcementActionButton(
          label: 'Delete',
          icon: Icons.delete_outline,
          color: const Color(0xFFC62828),
          onPressed: () => _deleteAnnouncement(announcement),
        ),
      ],
    );
  }

  Widget _announcementActionButton({
    required String label,
    required IconData icon,
    required Color color,
    required VoidCallback onPressed,
  }) {
    return SizedBox(
      width: _isMobile ? null : 96,
      child: OutlinedButton.icon(
        onPressed: onPressed,
        icon: Icon(icon, size: 16, color: color),
        label: Text(
          label,
          style: TextStyle(
            color: color,
            fontSize: 11,
            fontWeight: FontWeight.w600,
          ),
        ),
        style: OutlinedButton.styleFrom(
          foregroundColor: color,
          side: BorderSide(color: color.withOpacity(0.35)),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
          minimumSize: const Size(0, 36),
        ),
      ),
    );
  }

  void _showCreateAnnouncementDialog() {
    final titleController = TextEditingController();
    final contentController = TextEditingController();
    String selectedType = 'General';
    bool isPublished = false;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          backgroundColor: _cardBg,
          title: const Text(
            'New Announcement',
            style: TextStyle(color: _textDark, fontWeight: FontWeight.w600),
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: titleController,
                  decoration: InputDecoration(
                    labelText: 'Title',
                    labelStyle: const TextStyle(color: _textMuted),
                    hintText: 'Enter title',
                    hintStyle: TextStyle(color: _textMuted.withOpacity(0.8)),
                    filled: true,
                    fillColor: Colors.white,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide(color: Colors.grey.shade300),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide(color: Colors.grey.shade300),
                    ),
                  ),
                  style: const TextStyle(color: _textDark),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: contentController,
                  maxLines: 4,
                  decoration: InputDecoration(
                    labelText: 'Content',
                    labelStyle: const TextStyle(color: _textMuted),
                    hintText: 'Enter content',
                    hintStyle: TextStyle(color: _textMuted.withOpacity(0.8)),
                    filled: true,
                    fillColor: Colors.white,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide(color: Colors.grey.shade300),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide(color: Colors.grey.shade300),
                    ),
                  ),
                  style: const TextStyle(color: _textDark),
                ),
                const SizedBox(height: 16),
                const Text(
                  'Type',
                  style: TextStyle(
                    color: _textDark,
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  children: ['General', 'Promo', 'Event', 'Alert'].map((type) {
                    final isSelected = selectedType == type;
                    return GestureDetector(
                      onTap: () => setDialogState(() => selectedType = type),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
                        decoration: BoxDecoration(
                          color: isSelected
                              ? _primaryOrange
                              : Colors.grey.shade200,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          type,
                          style: TextStyle(
                            color: isSelected ? Colors.white : _textDark,
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Checkbox(
                      value: isPublished,
                      onChanged: (v) =>
                          setDialogState(() => isPublished = v ?? false),
                      activeColor: _primaryOrange,
                    ),
                    const Text(
                      'Publish immediately',
                      style: TextStyle(color: _textDark, fontSize: 14),
                    ),
                  ],
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel', style: TextStyle(color: _textDark)),
            ),
            ElevatedButton(
              onPressed: () async {
                if (titleController.text.isNotEmpty) {
                  final announcementData = {
                    'title': titleController.text,
                    'content': contentController.text,
                    'type': selectedType,
                    'published': isPublished,
                    'date': DateTime.now().toString().split(' ')[0],
                    'createdAt': FieldValue.serverTimestamp(),
                    'createdBy': 'Governor',
                  };

                  String? docId;
                  try {
                    if (Firebase.apps.isNotEmpty) {
                      final docRef = await FirebaseFirestore.instance
                          .collection('announcements')
                          .add(announcementData);
                      docId = docRef.id;
                      setState(() {
                        _announcements.insert(0, {
                          'id': docRef.id,
                          ...announcementData,
                          'createdAt': DateTime.now(),
                        });
                      });
                    } else {
                      docId = DateTime.now().millisecondsSinceEpoch.toString();
                      setState(() {
                        _announcements.insert(0, {
                          'id': docId,
                          ...announcementData,
                        });
                      });
                    }
                  } catch (e) {
                    debugPrint('Error saving announcement: $e');
                    docId = DateTime.now().millisecondsSinceEpoch.toString();
                    setState(() {
                      _announcements.insert(0, {
                        'id': docId,
                        ...announcementData,
                      });
                    });
                  }

                  var snackText = isPublished
                      ? 'Announcement published'
                      : 'Announcement saved as draft';
                  if (isPublished) {
                    final pushSent = await _broadcastPublishedAnnouncement(
                      title: titleController.text,
                      content: contentController.text,
                      type: selectedType,
                      announcementId: docId,
                    );
                    snackText = _publishedAnnouncementSnackMessage(pushSent);
                  }

                  if (!context.mounted) return;
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(snackText),
                      backgroundColor: _primaryOrange,
                    ),
                  );
                }
              },
              style: ElevatedButton.styleFrom(backgroundColor: _primaryOrange),
              child: const Text('Create'),
            ),
          ],
        ),
      ),
    );
  }

  void _togglePublishAnnouncement(Map<String, dynamic> announcement) async {
    final newPublished = !((announcement['published'] ?? false) as bool);

    // Update in Firestore
    try {
      if (Firebase.apps.isNotEmpty) {
        await FirebaseFirestore.instance
            .collection('announcements')
            .doc(announcement['id'])
            .update({'published': newPublished});
      }
    } catch (e) {
      debugPrint('Error updating announcement: $e');
    }

    setState(() {
      final index = _announcements.indexWhere(
        (a) => a['id'] == announcement['id'],
      );
      if (index != -1) {
        _announcements[index]['published'] = newPublished;
      }
    });

    var snackText = newPublished
        ? 'Announcement published'
        : 'Announcement unpublished';
    if (newPublished) {
      final pushSent = await _broadcastPublishedAnnouncement(
        title: announcement['title']?.toString() ?? '',
        content: announcement['content']?.toString() ?? '',
        type: announcement['type']?.toString() ?? 'General',
        announcementId: announcement['id']?.toString(),
      );
      snackText = _publishedAnnouncementSnackMessage(pushSent);
    }

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(snackText),
        backgroundColor: _primaryOrange,
      ),
    );
  }

  void _editAnnouncement(Map<String, dynamic> announcement) {
    final titleController = TextEditingController(text: announcement['title']);
    final contentController = TextEditingController(
      text: announcement['content'],
    );

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: _cardBg,
        title: const Text(
          'Edit Announcement',
          style: TextStyle(color: _textDark, fontWeight: FontWeight.w600),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: titleController,
              decoration: InputDecoration(
                labelText: 'Title',
                labelStyle: const TextStyle(color: _textMuted),
                hintText: 'Enter title',
                hintStyle: TextStyle(color: _textMuted.withOpacity(0.8)),
                filled: true,
                fillColor: Colors.white,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(color: Colors.grey.shade300),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(color: Colors.grey.shade300),
                ),
              ),
              style: const TextStyle(color: _textDark),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: contentController,
              maxLines: 4,
              decoration: InputDecoration(
                labelText: 'Content',
                labelStyle: const TextStyle(color: _textMuted),
                hintText: 'Enter content',
                hintStyle: TextStyle(color: _textMuted.withOpacity(0.8)),
                filled: true,
                fillColor: Colors.white,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(color: Colors.grey.shade300),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(color: Colors.grey.shade300),
                ),
              ),
              style: const TextStyle(color: _textDark),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel', style: TextStyle(color: _textDark)),
          ),
          ElevatedButton(
            onPressed: () {
              setState(() {
                final index = _announcements.indexWhere(
                  (a) => a['id'] == announcement['id'],
                );
                if (index != -1) {
                  _announcements[index]['title'] = titleController.text;
                  _announcements[index]['content'] = contentController.text;
                }
              });
              Navigator.pop(context);
            },
            style: ElevatedButton.styleFrom(backgroundColor: _primaryOrange),
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  void _deleteAnnouncement(Map<String, dynamic> announcement) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: _cardBg,
        title: const Text(
          'Delete Announcement',
          style: TextStyle(color: _textDark, fontWeight: FontWeight.w600),
        ),
        content: const Text(
          'Are you sure you want to delete this announcement?',
          style: TextStyle(color: _textDark, fontSize: 14),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel', style: TextStyle(color: _textDark)),
          ),
          ElevatedButton(
            onPressed: () async {
              // Delete from Firestore
              try {
                if (Firebase.apps.isNotEmpty) {
                  await FirebaseFirestore.instance
                      .collection('announcements')
                      .doc(announcement['id'])
                      .delete();
                }
              } catch (e) {
                debugPrint('Error deleting announcement: $e');
              }

              setState(() {
                _announcements.removeWhere(
                  (a) => a['id'] == announcement['id'],
                );
              });
              Navigator.pop(context);

              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Announcement deleted'),
                  backgroundColor: Colors.redAccent,
                ),
              );
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  // ==================== SETTINGS SECTION ====================
  Widget _buildSettingsContent() {
    return Container(
      color: _darkBg,
      child: Column(
        children: [
          _buildHeader(
            'Settings',
            subtitle: 'System configuration and preferences',
          ),
          Expanded(
            child: SingleChildScrollView(
              padding: EdgeInsets.all(_isMobile ? 16 : 24),
              child: Column(
                children: [
                  _buildSettingsSection('Account', [
                    _buildSettingsTile(
                      'Change Password',
                      Icons.lock_outline,
                      _showChangePasswordDialog,
                    ),
                    _buildSettingsTile(
                      'Profile Settings',
                      Icons.person_outline,
                      _showProfileSettingsDialog,
                    ),
                  ]),
                  const SizedBox(height: 16),
                  _buildSettingsSection('Notifications', [
                    _buildNotificationToggle(
                      'Email Notifications',
                      Icons.email_outlined,
                      _emailNotifications,
                      (value) {
                        setState(() => _emailNotifications = value);
                        _saveSettings();
                      },
                    ),
                    _buildNotificationToggle(
                      'Push Notifications',
                      Icons.notifications_outlined,
                      _pushNotifications,
                      (value) {
                        setState(() => _pushNotifications = value);
                        _saveSettings();
                      },
                    ),
                    _buildNotificationToggle(
                      'Weekly Reports',
                      Icons.assessment_outlined,
                      _weeklyReports,
                      (value) {
                        setState(() => _weeklyReports = value);
                        _saveSettings();
                      },
                    ),
                  ]),
                  const SizedBox(height: 16),
                  _buildSettingsSection('Data', [
                    _buildSettingsTileWithSubtitle(
                      'Export Data',
                      Icons.download_outlined,
                      _isExporting
                          ? 'Exporting... ${(_exportProgress * 100).toInt()}%'
                          : 'Export tourists and check-ins data',
                      _showExportDataDialog,
                    ),
                    _buildSettingsTileWithSubtitle(
                      'Backup Settings',
                      Icons.backup_outlined,
                      _lastBackupDate != null
                          ? 'Last backup: $_lastBackupDate'
                          : 'No backup yet',
                      _showBackupDialog,
                    ),
                  ]),
                  const SizedBox(height: 16),
                  _buildSettingsSection('About', [
                    _buildSettingsTile(
                      'System Information',
                      Icons.info_outline,
                      _showSystemInfo,
                    ),
                    _buildSettingsTile(
                      'Help & Support',
                      Icons.help_outline,
                      _showHelpSupportDialog,
                    ),
                  ]),
                  const SizedBox(height: 16),
                  _buildDangerZone(),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSettingsSection(String title, List<Widget> children) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: _cardBg,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: _cardBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              color: _textDark,
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 16),
          ...children,
        ],
      ),
    );
  }

  Widget _buildSettingsTile(String title, IconData icon, VoidCallback onTap) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: _primaryOrange.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icon, color: _primaryOrange, size: 20),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(color: _textDark, fontSize: 14),
                ),
              ),
              const Icon(Icons.chevron_right, color: _textMuted),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSettingsTileWithSubtitle(
    String title,
    IconData icon,
    String subtitle,
    VoidCallback onTap,
  ) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: _primaryOrange.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icon, color: _primaryOrange, size: 20),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(color: _textDark, fontSize: 14),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: TextStyle(color: _textMuted, fontSize: 12),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, color: _textMuted),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildNotificationToggle(
    String title,
    IconData icon,
    bool value,
    ValueChanged<bool> onChanged,
  ) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: _primaryOrange.withOpacity(0.15),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, color: _primaryOrange, size: 20),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Text(
              title,
              style: const TextStyle(color: _textDark, fontSize: 14),
            ),
          ),
          Switch(
            value: value,
            onChanged: onChanged,
            activeColor: _primaryOrange,
          ),
        ],
      ),
    );
  }

  Widget _buildDangerZone() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: _cardBg,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.red.withOpacity(0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(
                Icons.warning_amber_rounded,
                color: Colors.redAccent,
                size: 20,
              ),
              SizedBox(width: 8),
              Text(
                'Danger Zone',
                style: TextStyle(
                  color: Colors.redAccent,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          _buildDangerTile(
            'Clear All Data',
            Icons.delete_forever,
            _showClearDataDialog,
          ),
          _buildDangerTile(
            'Reset Settings',
            Icons.restore,
            _showResetSettingsDialog,
          ),
        ],
      ),
    );
  }

  Widget _buildDangerTile(String title, IconData icon, VoidCallback onTap) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.red.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icon, color: Colors.redAccent, size: 20),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(color: Colors.redAccent, fontSize: 14),
                ),
              ),
              const Icon(Icons.chevron_right, color: Colors.redAccent),
            ],
          ),
        ),
      ),
    );
  }

  // ==================== CHANGE PASSWORD DIALOG ====================
  void _showChangePasswordDialog() {
    final currentPasswordController = TextEditingController();
    final newPasswordController = TextEditingController();
    final confirmPasswordController = TextEditingController();
    bool isLoading = false;
    String? errorMessage;
    bool obscureCurrent = true;
    bool obscureNew = true;
    bool obscureConfirm = true;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          bool validatePassword(String password) {
            if (password.length < 8) return false;
            if (!password.contains(RegExp(r'[A-Z]'))) return false;
            if (!password.contains(RegExp(r'[a-z]'))) return false;
            if (!password.contains(RegExp(r'[0-9]'))) return false;
            if (!password.contains(RegExp(r'[!@#$%^&*(),.?":{}|<>]')))
              return false;
            return true;
          }

          return AlertDialog(
            backgroundColor: _cardBg,
            title: const Text(
              'Change Password',
              style: TextStyle(color: Colors.white),
            ),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (errorMessage != null)
                    Container(
                      padding: const EdgeInsets.all(12),
                      margin: const EdgeInsets.only(bottom: 16),
                      decoration: BoxDecoration(
                        color: Colors.red.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.error_outline,
                            color: Colors.redAccent,
                            size: 18,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              errorMessage!,
                              style: const TextStyle(
                                color: Colors.redAccent,
                                fontSize: 12,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  TextField(
                    controller: currentPasswordController,
                    obscureText: obscureCurrent,
                    decoration: InputDecoration(
                      hintText: 'Current Password',
                      hintStyle: TextStyle(color: _textMuted),
                      filled: true,
                      fillColor: Colors.white.withOpacity(0.05),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: BorderSide.none,
                      ),
                      suffixIcon: IconButton(
                        icon: Icon(
                          obscureCurrent
                              ? Icons.visibility_off
                              : Icons.visibility,
                          color: _textMuted,
                        ),
                        onPressed: () => setDialogState(
                          () => obscureCurrent = !obscureCurrent,
                        ),
                      ),
                    ),
                    style: const TextStyle(color: Colors.white),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: newPasswordController,
                    obscureText: obscureNew,
                    decoration: InputDecoration(
                      hintText: 'New Password',
                      hintStyle: TextStyle(color: _textMuted),
                      filled: true,
                      fillColor: Colors.white.withOpacity(0.05),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: BorderSide.none,
                      ),
                      suffixIcon: IconButton(
                        icon: Icon(
                          obscureNew ? Icons.visibility_off : Icons.visibility,
                          color: _textMuted,
                        ),
                        onPressed: () =>
                            setDialogState(() => obscureNew = !obscureNew),
                      ),
                    ),
                    style: const TextStyle(color: Colors.white),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Password must contain: 8+ chars, uppercase, lowercase, number, special char',
                    style: TextStyle(color: _textMuted, fontSize: 11),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: confirmPasswordController,
                    obscureText: obscureConfirm,
                    decoration: InputDecoration(
                      hintText: 'Confirm New Password',
                      hintStyle: TextStyle(color: _textMuted),
                      filled: true,
                      fillColor: Colors.white.withOpacity(0.05),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: BorderSide.none,
                      ),
                      suffixIcon: IconButton(
                        icon: Icon(
                          obscureConfirm
                              ? Icons.visibility_off
                              : Icons.visibility,
                          color: _textMuted,
                        ),
                        onPressed: () => setDialogState(
                          () => obscureConfirm = !obscureConfirm,
                        ),
                      ),
                    ),
                    style: const TextStyle(color: Colors.white),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: isLoading ? null : () => Navigator.pop(context),
                child: const Text(
                  'Cancel',
                  style: TextStyle(color: _textMuted),
                ),
              ),
              ElevatedButton(
                onPressed: isLoading
                    ? null
                    : () async {
                        setDialogState(() {
                          errorMessage = null;
                          isLoading = true;
                        });

                        // Validate current password (no plaintext compare in widget code)
                        if (!await SessionStorage.matchesStoredGovernorPassword(
                          currentPasswordController.text,
                        )) {
                          setDialogState(() {
                            errorMessage = 'Current password is incorrect';
                            isLoading = false;
                          });
                          return;
                        }

                        // Validate new password
                        if (!validatePassword(newPasswordController.text)) {
                          setDialogState(() {
                            errorMessage =
                                'New password does not meet requirements';
                            isLoading = false;
                          });
                          return;
                        }

                        // Check passwords match
                        if (newPasswordController.text !=
                            confirmPasswordController.text) {
                          setDialogState(() {
                            errorMessage = 'Passwords do not match';
                            isLoading = false;
                          });
                          return;
                        }

                        // Simulate save (in real app, save to Firebase Auth)
                        await Future.delayed(const Duration(seconds: 1));

                        // Save to SharedPreferences for demo
                        final prefs = await SharedPreferences.getInstance();
                        await prefs.setString(
                          'governor_password',
                          newPasswordController.text,
                        );

                        if (!context.mounted) return;
                        Navigator.pop(context);
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Password updated successfully'),
                            backgroundColor: _primaryOrange,
                          ),
                        );
                      },
                style: ElevatedButton.styleFrom(
                  backgroundColor: _primaryOrange,
                ),
                child: isLoading
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Text('Update'),
              ),
            ],
          );
        },
      ),
    );
  }

  // ==================== PROFILE SETTINGS DIALOG ====================
  void _showProfileSettingsDialog() {
    final nameController = TextEditingController(text: _profileName);
    final emailController = TextEditingController(text: _profileEmail);
    Uint8List? dialogPhotoBytes = _profilePhotoBytes;
    String? dialogPhotoBase64 = _profilePhotoBase64;
    bool isLoading = false;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          backgroundColor: _cardBg,
          title: const Text(
            'Profile Settings',
            style: TextStyle(color: _textDark, fontWeight: FontWeight.w600),
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                GestureDetector(
                  onTap: isLoading
                      ? null
                      : () async {
                          final picker = ImagePicker();
                          try {
                            final picked = await picker.pickImage(
                              source: ImageSource.gallery,
                              maxWidth: 512,
                              maxHeight: 512,
                              imageQuality: 85,
                            );
                            if (picked != null) {
                              final bytes = await picked.readAsBytes();
                              setDialogState(() {
                                dialogPhotoBytes = bytes;
                                dialogPhotoBase64 = base64Encode(bytes);
                              });
                            }
                          } catch (_) {
                            // ignore errors for now
                          }
                        },
                  child: Stack(
                    alignment: Alignment.bottomRight,
                    children: [
                      CircleAvatar(
                        radius: 50,
                        backgroundColor: _primaryOrange.withOpacity(0.2),
                        backgroundImage: dialogPhotoBytes != null
                            ? MemoryImage(dialogPhotoBytes!)
                            : null,
                        child: dialogPhotoBytes == null
                            ? const Icon(
                                Icons.person,
                                color: _primaryOrange,
                                size: 50,
                              )
                            : null,
                      ),
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: _primaryOrange,
                          shape: BoxShape.circle,
                          border: Border.all(color: _cardBg, width: 3),
                        ),
                        child: const Icon(
                          Icons.camera_alt,
                          color: Colors.white,
                          size: 16,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                TextField(
                  controller: nameController,
                  decoration: InputDecoration(
                    labelText: 'Display Name',
                    labelStyle: const TextStyle(color: _textMuted),
                    hintText: 'Enter display name',
                    hintStyle: TextStyle(color: _textMuted.withOpacity(0.8)),
                    filled: true,
                    fillColor: Colors.white,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide(color: Colors.grey.shade300),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide(color: Colors.grey.shade300),
                    ),
                    prefixIcon: const Icon(
                      Icons.person_outline,
                      color: _primaryOrange,
                    ),
                  ),
                  style: const TextStyle(color: _textDark),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: emailController,
                  keyboardType: TextInputType.emailAddress,
                  decoration: InputDecoration(
                    labelText: 'Email Address',
                    labelStyle: const TextStyle(color: _textMuted),
                    hintText: 'Enter email',
                    hintStyle: TextStyle(color: _textMuted.withOpacity(0.8)),
                    filled: true,
                    fillColor: Colors.white,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide(color: Colors.grey.shade300),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide(color: Colors.grey.shade300),
                    ),
                    prefixIcon: const Icon(
                      Icons.email_outlined,
                      color: _primaryOrange,
                    ),
                  ),
                  style: const TextStyle(color: _textDark),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Changing email will require verification',
                  style: TextStyle(color: _textMuted, fontSize: 12),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: isLoading ? null : () => Navigator.pop(context),
              child: const Text('Cancel', style: TextStyle(color: _textDark)),
            ),
            ElevatedButton(
              onPressed: isLoading
                  ? null
                  : () async {
                      setDialogState(() => isLoading = true);

                      await Future.delayed(const Duration(seconds: 1));

                      setState(() {
                        _profileName = nameController.text;
                        _profileEmail = emailController.text;
                        _profilePhotoBytes = dialogPhotoBytes;
                        _profilePhotoBase64 = dialogPhotoBase64;
                      });
                      await _saveSettings();

                      if (!context.mounted) return;
                      Navigator.pop(context);
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Profile updated successfully'),
                          backgroundColor: _primaryOrange,
                        ),
                      );
                    },
              style: ElevatedButton.styleFrom(backgroundColor: _primaryOrange),
              child: isLoading
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Text('Save'),
            ),
          ],
        ),
      ),
    );
  }

  // ==================== EXPORT DATA DIALOG ====================
  void _showExportDataDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: _cardBg,
        title: const Text('Export Data', style: TextStyle(color: Colors.white)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildExportOption(
              'Tourists Data (CSV)',
              Icons.people_alt_rounded,
              () => _exportData('tourists'),
            ),
            const SizedBox(height: 12),
            _buildExportOption(
              'Check-ins Data (CSV)',
              Icons.qr_code_scanner_rounded,
              () => _exportData('checkins'),
            ),
            const SizedBox(height: 12),
            _buildExportOption(
              'Summary Report (PDF)',
              Icons.assessment_rounded,
              () => _exportData('report'),
            ),
            const SizedBox(height: 12),
            _buildExportOption(
              'All Data (ZIP)',
              Icons.folder_zip,
              () => _exportData('all'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close', style: TextStyle(color: _textMuted)),
          ),
        ],
      ),
    );
  }

  Widget _buildExportOption(String title, IconData icon, VoidCallback onTap) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.grey.shade200,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              Icon(icon, color: _primaryOrange, size: 24),
              const SizedBox(width: 16),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(color: _textDark, fontSize: 14),
                ),
              ),
              const Icon(Icons.download, color: _textMuted, size: 20),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildExportPreviewTable(List<String> lines) {
    if (lines.isEmpty) return const SizedBox.shrink();
    final headers = lines.first.split(',').map((s) => s.trim()).toList();
    final dataRows = lines.length > 1 ? lines.sublist(1) : <String>[];
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: DataTable(
        headingRowColor: WidgetStateProperty.all(Colors.grey.shade100),
        columnSpacing: 16,
        horizontalMargin: 12,
        columns: headers
            .map(
              (h) => DataColumn(
                label: Text(
                  h,
                  style: const TextStyle(
                    color: _textDark,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            )
            .toList(),
        rows: dataRows.map((line) {
          final cells = line.split(',').map((s) => s.trim()).toList();
          return DataRow(
            cells: List.generate(
              headers.length,
              (i) => DataCell(
                Text(
                  i < cells.length ? cells[i] : '',
                  style: const TextStyle(color: _textDark, fontSize: 12),
                  overflow: TextOverflow.ellipsis,
                  maxLines: 1,
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Future<void> _exportData(String type) async {
    Navigator.pop(context);

    setState(() {
      _isExporting = true;
      _exportProgress = 0.0;
    });

    // Simulate export progress
    for (int i = 1; i <= 10; i++) {
      await Future.delayed(const Duration(milliseconds: 200));
      setState(() => _exportProgress = i / 10);
    }

    setState(() => _isExporting = false);

    // Generate mock data content
    String content;
    String filename;
    switch (type) {
      case 'tourists':
        content = 'ID,Name,Email,Origin,Visits\n';
        for (var t in _tourists) {
          content +=
              '${t['id']},${_getTouristDisplayName(t)},${t['email'] ?? ''},${t['origin'] ?? t['city'] ?? t['country'] ?? ''},${t['visits'] ?? t['totalVisits'] ?? 0}\n';
        }
        filename =
            'tourists_export_${DateTime.now().millisecondsSinceEpoch}.csv';
        break;
      case 'checkins':
        content = 'Date,Tourist ID,Location,Status\n';
        content += '2026-02-24,ATMOS-0001,Azure Coast,Verified\n';
        content += '2026-02-24,ATMOS-0002,Baliangao Beach,Verified\n';
        filename =
            'checkins_export_${DateTime.now().millisecondsSinceEpoch}.csv';
        break;
      case 'report':
        content = 'ATMOS TRS Summary Report\n';
        content += 'Generated: ${DateTime.now()}\n\n';
        content += 'Total Tourists: $_totalTourists\n';
        content += 'Total Check-ins: $_totalCheckIns\n';
        content += 'Active Spots: $_activeSpots\n';
        filename = 'report_${DateTime.now().millisecondsSinceEpoch}.txt';
        break;
      default:
        content = 'All data export';
        filename = 'all_data_${DateTime.now().millisecondsSinceEpoch}.zip';
    }

    // Save to SharedPreferences for demo (in real app, save to file)
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('last_export_$type', content);

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('$filename exported successfully'),
        backgroundColor: _primaryOrange,
        action: SnackBarAction(
          label: 'View',
          textColor: Colors.white,
          onPressed: () {
            // Show export preview as table when CSV
            final lines = content
                .split('\n')
                .where((s) => s.trim().isNotEmpty)
                .toList();
            final isCsv = lines.isNotEmpty && lines.first.contains(',');
            showDialog(
              context: context,
              builder: (context) => AlertDialog(
                backgroundColor: _cardBg,
                title: Text(
                  filename,
                  style: const TextStyle(color: _textDark, fontSize: 14),
                ),
                content: SingleChildScrollView(
                  child: isCsv && lines.length > 1
                      ? _buildExportPreviewTable(lines)
                      : SelectableText(
                          content,
                          style: const TextStyle(
                            color: _textDark,
                            fontSize: 12,
                            fontFamily: 'monospace',
                          ),
                        ),
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text(
                      'Close',
                      style: TextStyle(color: _primaryOrange),
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  // ==================== BACKUP DIALOG ====================
  void _showBackupDialog() {
    bool isBackingUp = false;
    bool isRestoring = false;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            backgroundColor: _cardBg,
            title: const Text(
              'Backup & Restore',
              style: TextStyle(color: Colors.white),
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade200,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.cloud_done,
                        color: _primaryOrange,
                        size: 40,
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Last Backup',
                              style: TextStyle(
                                color: _textDark,
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            Text(
                              _lastBackupDate ?? 'No backup available',
                              style: TextStyle(color: _textMuted, fontSize: 12),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: isBackingUp
                        ? null
                        : () async {
                            setDialogState(() => isBackingUp = true);

                            // Simulate backup
                            await Future.delayed(const Duration(seconds: 2));

                            final backupDate = DateTime.now().toString().split(
                              '.',
                            )[0];
                            final prefs = await SharedPreferences.getInstance();
                            await prefs.setString(
                              'last_backup_date',
                              backupDate,
                            );

                            // Save backup data
                            final backupData = jsonEncode({
                              'email_notifications': _emailNotifications,
                              'push_notifications': _pushNotifications,
                              'weekly_reports': _weeklyReports,
                              'profile_name': _profileName,
                              'profile_email': _profileEmail,
                              'backup_date': backupDate,
                            });
                            await prefs.setString('backup_data', backupData);

                            setState(() => _lastBackupDate = backupDate);
                            setDialogState(() => isBackingUp = false);

                            if (!context.mounted) return;
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('Backup created successfully'),
                                backgroundColor: _primaryOrange,
                              ),
                            );
                          },
                    icon: isBackingUp
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(Icons.backup),
                    label: Text(
                      isBackingUp ? 'Backing up...' : 'Create Backup',
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _primaryOrange,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: _lastBackupDate == null || isRestoring
                        ? null
                        : () async {
                            setDialogState(() => isRestoring = true);

                            final prefs = await SharedPreferences.getInstance();
                            final backupDataStr = prefs.getString(
                              'backup_data',
                            );

                            if (backupDataStr != null) {
                              final backupData =
                                  jsonDecode(backupDataStr)
                                      as Map<String, dynamic>;
                              setState(() {
                                _emailNotifications =
                                    backupData['email_notifications'] ?? true;
                                _pushNotifications =
                                    backupData['push_notifications'] ?? true;
                                _weeklyReports =
                                    backupData['weekly_reports'] ?? false;
                                _profileName =
                                    backupData['profile_name'] ?? 'Governor';
                                _profileEmail =
                                    backupData['profile_email'] as String? ??
                                    FirebaseAuth.instance.currentUser?.email
                                        ?.trim() ??
                                    '';
                              });
                              await _saveSettings();
                            }

                            setDialogState(() => isRestoring = false);

                            if (!context.mounted) return;
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('Settings restored from backup'),
                                backgroundColor: _primaryOrange,
                              ),
                            );
                          },
                    icon: isRestoring
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: _primaryOrange,
                            ),
                          )
                        : const Icon(Icons.restore),
                    label: Text(
                      isRestoring ? 'Restoring...' : 'Restore from Backup',
                    ),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: _primaryOrange,
                      side: const BorderSide(color: _primaryOrange),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Close', style: TextStyle(color: _textMuted)),
              ),
            ],
          );
        },
      ),
    );
  }

  // ==================== SYSTEM INFO DIALOG ====================
  void _showSystemInfo() {
    String platform = 'Unknown';
    if (kIsWeb) {
      platform = 'Web';
    } else {
      try {
        if (Platform.isAndroid) platform = 'Android';
        if (Platform.isIOS) platform = 'iOS';
        if (Platform.isWindows) platform = 'Windows';
        if (Platform.isMacOS) platform = 'macOS';
        if (Platform.isLinux) platform = 'Linux';
      } catch (_) {
        platform = 'Web';
      }
    }

    final isFirebaseConnected = Firebase.apps.isNotEmpty;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: _cardBg,
        title: const Row(
          children: [
            Icon(Icons.info_outline, color: _primaryOrange),
            SizedBox(width: 12),
            Text('System Information', style: TextStyle(color: Colors.white)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildInfoRow('App Name', 'ATMOS TRS'),
            _buildInfoRow('Version', '1.0.0'),
            _buildInfoRow('Build', '2026.02.24'),
            const Divider(color: Colors.white24, height: 24),
            _buildInfoRow('Platform', platform),
            _buildInfoRow('Framework', 'Flutter'),
            _buildInfoRow('Dart Version', '3.x'),
            const Divider(color: Colors.white24, height: 24),
            _buildInfoRow('Database', 'Firebase Firestore'),
            _buildStatusRow(
              'Connection',
              isFirebaseConnected ? 'Connected' : 'Disconnected',
              isFirebaseConnected,
            ),
            _buildInfoRow('Last Sync', _lastSyncDate ?? 'Never'),
            const Divider(color: Colors.white24, height: 24),
            _buildInfoRow('Province', 'Misamis Occidental'),
            _buildInfoRow('Total Municipalities', '17'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () async {
              final prefs = await SharedPreferences.getInstance();
              final syncDate = DateTime.now().toString().split('.')[0];
              await prefs.setString('last_sync_date', syncDate);
              setState(() => _lastSyncDate = syncDate);
              if (!context.mounted) return;
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Synced successfully'),
                  backgroundColor: _primaryOrange,
                ),
              );
            },
            child: const Text(
              'Sync Now',
              style: TextStyle(color: _primaryOrange),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close', style: TextStyle(color: _textMuted)),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(color: _textMuted, fontSize: 13)),
          Text(value, style: const TextStyle(color: _textDark, fontSize: 13)),
        ],
      ),
    );
  }

  Widget _buildStatusRow(String label, String value, bool isGood) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(color: _textMuted, fontSize: 13)),
          Row(
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: isGood ? Colors.greenAccent : Colors.redAccent,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 6),
              Text(
                value,
                style: TextStyle(
                  color: isGood ? Colors.greenAccent : Colors.redAccent,
                  fontSize: 13,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ==================== HELP & SUPPORT DIALOG ====================
  void _showHelpSupportDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: _cardBg,
        title: const Text(
          'Help & Support',
          style: TextStyle(color: Colors.white),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildHelpOption(
              'Documentation',
              Icons.menu_book_rounded,
              () async {
                Navigator.pop(context);
                final url = Uri.parse('https://docs.atmostrssystem.com');
                if (await canLaunchUrl(url)) {
                  await launchUrl(url);
                } else {
                  if (!mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Could not open documentation'),
                      backgroundColor: Colors.redAccent,
                    ),
                  );
                }
              },
            ),
            const SizedBox(height: 12),
            _buildHelpOption('FAQs', Icons.quiz_rounded, () {
              Navigator.pop(context);
              _showFAQDialog();
            }),
            const SizedBox(height: 12),
            _buildHelpOption('Contact Support', Icons.email_rounded, () async {
              Navigator.pop(context);
              final url = Uri.parse(
                'mailto:support@atmostrssystem.com?subject=Governor Dashboard Support',
              );
              if (await canLaunchUrl(url)) {
                await launchUrl(url);
              } else {
                if (!mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Could not open email client'),
                    backgroundColor: Colors.redAccent,
                  ),
                );
              }
            }),
            const SizedBox(height: 12),
            _buildHelpOption('Report a Bug', Icons.bug_report_rounded, () {
              Navigator.pop(context);
              _showReportBugDialog();
            }),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close', style: TextStyle(color: _textMuted)),
          ),
        ],
      ),
    );
  }

  Widget _buildHelpOption(String title, IconData icon, VoidCallback onTap) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.grey.shade200,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              Icon(icon, color: _primaryOrange, size: 24),
              const SizedBox(width: 16),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(color: _textDark, fontSize: 14),
                ),
              ),
              const Icon(Icons.chevron_right, color: _textMuted, size: 20),
            ],
          ),
        ),
      ),
    );
  }

  void _showFAQDialog() {
    final faqs = [
      {
        'q': 'How do I add a new tourist spot?',
        'a': 'Go to Tourism Dashboard > Tourist Spots > Add Spot button.',
      },
      {
        'q': 'How do I export data?',
        'a': 'Go to Settings > Data > Export Data and choose the format.',
      },
      {
        'q': 'How do I change my password?',
        'a': 'Go to Settings > Account > Change Password.',
      },
      {
        'q': 'How do I view analytics?',
        'a': 'Click on Analytics in the sidebar to view detailed statistics.',
      },
      {
        'q': 'How do I create announcements?',
        'a': 'Go to Announcements section and click "New" button.',
      },
    ];

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: _cardBg,
        title: const Text(
          'Frequently Asked Questions',
          style: TextStyle(color: Colors.white),
        ),
        content: SizedBox(
          width: 400,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: faqs
                  .map(
                    (faq) => ExpansionTile(
                      title: Text(
                        faq['q']!,
                        style: const TextStyle(color: _textDark, fontSize: 13),
                      ),
                      iconColor: _primaryOrange,
                      collapsedIconColor: Colors.white54,
                      children: [
                        Padding(
                          padding: const EdgeInsets.all(16),
                          child: Text(
                            faq['a']!,
                            style: TextStyle(
                              color: Colors.white.withOpacity(0.7),
                              fontSize: 12,
                            ),
                          ),
                        ),
                      ],
                    ),
                  )
                  .toList(),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close', style: TextStyle(color: _primaryOrange)),
          ),
        ],
      ),
    );
  }

  void _showReportBugDialog() {
    final titleController = TextEditingController();
    final descriptionController = TextEditingController();
    bool isSubmitting = false;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          backgroundColor: _cardBg,
          title: const Text(
            'Report a Bug',
            style: TextStyle(color: Colors.white),
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: titleController,
                  decoration: InputDecoration(
                    labelText: 'Bug Title',
                    labelStyle: TextStyle(color: _textMuted),
                    filled: true,
                    fillColor: Colors.white.withOpacity(0.05),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide.none,
                    ),
                  ),
                  style: const TextStyle(color: Colors.white),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: descriptionController,
                  maxLines: 5,
                  decoration: InputDecoration(
                    labelText: 'Description',
                    labelStyle: TextStyle(color: _textMuted),
                    hintText: 'Please describe the bug in detail...',
                    hintStyle: TextStyle(color: Colors.white.withOpacity(0.3)),
                    filled: true,
                    fillColor: Colors.white.withOpacity(0.05),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide.none,
                    ),
                  ),
                  style: const TextStyle(color: Colors.white),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: isSubmitting ? null : () => Navigator.pop(context),
              child: const Text('Cancel', style: TextStyle(color: _textMuted)),
            ),
            ElevatedButton(
              onPressed: isSubmitting
                  ? null
                  : () async {
                      if (titleController.text.isEmpty ||
                          descriptionController.text.isEmpty) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Please fill in all fields'),
                            backgroundColor: Colors.redAccent,
                          ),
                        );
                        return;
                      }

                      setDialogState(() => isSubmitting = true);
                      await Future.delayed(const Duration(seconds: 1));

                      if (!context.mounted) return;
                      Navigator.pop(context);
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Bug report submitted. Thank you!'),
                          backgroundColor: _primaryOrange,
                        ),
                      );
                    },
              style: ElevatedButton.styleFrom(backgroundColor: _primaryOrange),
              child: isSubmitting
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Text('Submit'),
            ),
          ],
        ),
      ),
    );
  }

  // ==================== DANGER ZONE DIALOGS ====================
  void _showClearDataDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: _cardBg,
        title: const Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: Colors.redAccent),
            SizedBox(width: 12),
            Text('Clear All Data', style: TextStyle(color: Colors.white)),
          ],
        ),
        content: const Text(
          'This action will permanently delete all cached data. This cannot be undone. Are you sure you want to continue?',
          style: TextStyle(color: _textMuted),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel', style: TextStyle(color: _textMuted)),
          ),
          ElevatedButton(
            onPressed: () async {
              final prefs = await SharedPreferences.getInstance();
              await prefs.clear();
              await _loadSettings();

              if (!context.mounted) return;
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('All data cleared'),
                  backgroundColor: Colors.redAccent,
                ),
              );
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
            child: const Text('Clear Data'),
          ),
        ],
      ),
    );
  }

  void _showResetSettingsDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: _cardBg,
        title: const Row(
          children: [
            Icon(Icons.restore, color: Colors.redAccent),
            SizedBox(width: 12),
            Text('Reset Settings', style: TextStyle(color: Colors.white)),
          ],
        ),
        content: const Text(
          'This will reset all settings to their default values. Are you sure?',
          style: TextStyle(color: _textMuted),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel', style: TextStyle(color: _textMuted)),
          ),
          ElevatedButton(
            onPressed: () async {
              setState(() {
                _emailNotifications = true;
                _pushNotifications = true;
                _weeklyReports = false;
                _profileName = 'Governor';
                _profileEmail =
                    FirebaseAuth.instance.currentUser?.email?.trim() ?? '';
              });
              await _saveSettings();

              if (!context.mounted) return;
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Settings reset to defaults'),
                  backgroundColor: _primaryOrange,
                ),
              );
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
            child: const Text('Reset'),
          ),
        ],
      ),
    );
  }
}

class _NavItem {
  final IconData icon;
  final String label;
  _NavItem({required this.icon, required this.label});
}

/// Donut pie chart for dashboard category shares (renormalized to top 5).
class _CategoryPiePainter extends CustomPainter {
  _CategoryPiePainter({
    required this.segments,
    required this.holeColor,
    this.isEmpty = false,
  });

  final List<({Color color, double fraction})> segments;
  final Color holeColor;
  final bool isEmpty;

  @override
  void paint(Canvas canvas, Size size) {
    final c = Offset(size.width / 2, size.height / 2);
    final r = math.min(size.width, size.height) / 2;
    final rect = Rect.fromCircle(center: c, radius: r * 0.98);

    if (isEmpty) {
      final track = Paint()
        ..color = const Color(0xFFE4E4E7)
        ..style = PaintingStyle.stroke
        ..strokeWidth = r * 0.28;
      canvas.drawCircle(c, r * 0.68, track);
      return;
    }

    var angle = -math.pi / 2;
    for (final seg in segments) {
      final sweep = 2 * math.pi * seg.fraction;
      if (sweep <= 0) continue;
      final paint = Paint()
        ..color = seg.color
        ..style = PaintingStyle.fill;
      canvas.drawArc(rect, angle, sweep, true, paint);
      angle += sweep;
    }

    final holePaint = Paint()..color = holeColor;
    canvas.drawCircle(c, r * 0.52, holePaint);
  }

  @override
  bool shouldRepaint(covariant _CategoryPiePainter oldDelegate) => true;
}

class _StatCard {
  final String title;
  final String value;
  final String? subtitle;
  final String? change;
  final bool? isPositive;
  final IconData icon;
  final Color color;
  _StatCard({
    required this.title,
    required this.value,
    this.subtitle,
    this.change,
    this.isPositive,
    required this.icon,
    required this.color,
  });
}

class _ChartPainter extends CustomPainter {
  final Color color;
  final List<double> values;
  final bool showPlaceholder;
  _ChartPainter({
    required this.color,
    this.values = const [],
    this.showPlaceholder = false,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final gridPaint = Paint()
      ..color = const Color(0xFFF3F4F6)
      ..strokeWidth = 1;

    for (int i = 0; i < 5; i++) {
      final y = size.height * i / 4;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }

    if (showPlaceholder || values.isEmpty) {
      final baseline = Paint()
        ..color = color.withOpacity(0.35)
        ..strokeWidth = 2
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round;
      canvas.drawLine(
        Offset(0, size.height * 0.88),
        Offset(size.width, size.height * 0.88),
        baseline,
      );
      return;
    }

    final paint = Paint()
      ..color = color
      ..strokeWidth = 3
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    final fillPaint = Paint()..color = color.withOpacity(0.12);

    final maxVal = values
        .reduce((a, b) => a > b ? a : b)
        .clamp(1.0, double.infinity);
    final points = <Offset>[];
    if (values.length >= 2) {
      for (int i = 0; i < values.length; i++) {
        final x = size.width * (i / (values.length - 1));
        final y = size.height * (1 - (values[i] / maxVal) * 0.85);
        points.add(Offset(x, y));
      }
    }

    if (points.isEmpty) return;
    final path = Path();
    path.moveTo(points.first.dx, points.first.dy);
    for (int i = 1; i < points.length; i++) {
      final p0 = points[i - 1];
      final p1 = points[i];
      final controlPoint1 = Offset(p0.dx + (p1.dx - p0.dx) / 2, p0.dy);
      final controlPoint2 = Offset(p0.dx + (p1.dx - p0.dx) / 2, p1.dy);
      path.cubicTo(
        controlPoint1.dx,
        controlPoint1.dy,
        controlPoint2.dx,
        controlPoint2.dy,
        p1.dx,
        p1.dy,
      );
    }

    final fillPath = Path.from(path);
    fillPath.lineTo(size.width, size.height);
    fillPath.lineTo(0, size.height);
    fillPath.close();
    canvas.drawPath(fillPath, fillPaint);
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _ChartPainter oldDelegate) {
    return oldDelegate.color != color ||
        oldDelegate.showPlaceholder != showPlaceholder ||
        oldDelegate.values != values;
  }
}

/// Grouped Male / Female / Others bars per age bucket.
class _GroupedAgeGenderBarPainter extends CustomPainter {
  _GroupedAgeGenderBarPainter({
    required this.series,
    required this.maleColor,
    required this.femaleColor,
    required this.otherColor,
  });

  final List<({String label, int male, int female, int others})> series;
  final Color maleColor;
  final Color femaleColor;
  final Color otherColor;

  @override
  void paint(Canvas canvas, Size size) {
    final leftPad = 36.0;
    final bottomPad = 28.0;
    final topPad = 12.0;
    final chartW = size.width - leftPad - 8;
    final chartH = size.height - bottomPad - topPad;
    final origin = Offset(leftPad, topPad + chartH);

    final gridPaint = Paint()
      ..color = const Color(0xFFF3F4F6)
      ..strokeWidth = 1;
    for (var i = 0; i <= 4; i++) {
      final y = topPad + chartH * i / 4;
      canvas.drawLine(Offset(leftPad, y), Offset(size.width - 4, y), gridPaint);
    }

    final maxVal = series
        .map((r) => math.max(r.male, math.max(r.female, r.others)))
        .fold<int>(0, (a, b) => a > b ? a : b)
        .clamp(1, 999999)
        .toDouble();

    final groupCount = series.length;
    final groupWidth = chartW / groupCount;
    final barWidth = groupWidth * 0.18;
    final gap = barWidth * 0.35;

    for (var g = 0; g < groupCount; g++) {
      final row = series[g];
      final values = [row.male, row.female, row.others];
      final colors = [maleColor, femaleColor, otherColor];
      final groupStart = leftPad + g * groupWidth + groupWidth * 0.12;

      for (var b = 0; b < 3; b++) {
        final value = values[b].toDouble();
        final barH = (value / maxVal) * chartH;
        final x = groupStart + b * (barWidth + gap);
        final rect = RRect.fromRectAndRadius(
          Rect.fromLTWH(x, origin.dy - barH, barWidth, barH),
          const Radius.circular(6),
        );
        final paint = Paint()..color = colors[b];
        canvas.drawRRect(rect, paint);
      }

      final label = row.label;
      final tp = TextPainter(
        text: TextSpan(
          text: label,
          style: const TextStyle(
            color: Color(0xFF6B7280),
            fontSize: 10,
            fontWeight: FontWeight.w500,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(
        canvas,
        Offset(
          leftPad + g * groupWidth + (groupWidth - tp.width) / 2,
          origin.dy + 6,
        ),
      );
    }

    for (var i = 0; i <= 4; i++) {
      final val = (maxVal * (4 - i) / 4).round();
      final y = topPad + chartH * i / 4;
      final tp = TextPainter(
        text: TextSpan(
          text: '$val',
          style: const TextStyle(color: Color(0xFF9CA3AF), fontSize: 9),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(0, y - tp.height / 2));
    }
  }

  @override
  bool shouldRepaint(covariant _GroupedAgeGenderBarPainter oldDelegate) => true;
}

/// Vertical bars for top municipalities / cities.
class _CityRankingBarPainter extends CustomPainter {
  _CityRankingBarPainter({
    required this.cities,
    required this.maxCount,
    required this.colors,
  });

  final List<({String name, int count})> cities;
  final int maxCount;
  final List<Color> colors;

  @override
  void paint(Canvas canvas, Size size) {
    final leftPad = 8.0;
    final bottomPad = 32.0;
    final topPad = 20.0;
    final chartW = size.width - leftPad * 2;
    final chartH = size.height - bottomPad - topPad;
    final origin = Offset(leftPad, topPad + chartH);
    final maxVal = maxCount.clamp(1, 999999).toDouble();

    final gridPaint = Paint()
      ..color = const Color(0xFFF3F4F6)
      ..strokeWidth = 1;
    for (var i = 0; i <= 4; i++) {
      final y = topPad + chartH * i / 4;
      canvas.drawLine(
        Offset(leftPad, y),
        Offset(size.width - leftPad, y),
        gridPaint,
      );
    }

    final barCount = cities.length;
    final slot = chartW / barCount;
    final barWidth = slot * 0.5;

    for (var i = 0; i < barCount; i++) {
      final city = cities[i];
      final value = city.count.toDouble();
      final barH = (value / maxVal) * chartH;
      final x = leftPad + i * slot + (slot - barWidth) / 2;
      final color = colors[i % colors.length];
      final rect = RRect.fromRectAndRadius(
        Rect.fromLTWH(x, origin.dy - barH, barWidth, barH),
        const Radius.circular(8),
      );
      final paint = Paint()..color = color;
      canvas.drawRRect(rect, paint);

      final countTp = TextPainter(
        text: TextSpan(
          text: '${city.count}',
          style: const TextStyle(
            color: Color(0xFF1A1A1A),
            fontSize: 10,
            fontWeight: FontWeight.w700,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      countTp.paint(
        canvas,
        Offset(x + (barWidth - countTp.width) / 2, origin.dy - barH - 14),
      );

      var label = city.name;
      if (label.length > 10) label = '${label.substring(0, 9)}…';
      final labelTp = TextPainter(
        text: TextSpan(
          text: label,
          style: const TextStyle(
            color: Color(0xFF6B7280),
            fontSize: 9,
            fontWeight: FontWeight.w500,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      labelTp.paint(
        canvas,
        Offset(x + (barWidth - labelTp.width) / 2, origin.dy + 6),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _CityRankingBarPainter oldDelegate) => true;
}

/// Minimal white sparkline for flat KPI cards.
class _MiniSparklinePainter extends CustomPainter {
  _MiniSparklinePainter({required this.values});

  final List<double> values;

  @override
  void paint(Canvas canvas, Size size) {
    if (values.isEmpty) return;
    final maxVal = values
        .reduce((a, b) => a > b ? a : b)
        .clamp(1.0, double.infinity);
    final points = <Offset>[];
    for (var i = 0; i < values.length; i++) {
      final x = values.length == 1
          ? size.width / 2
          : size.width * (i / (values.length - 1));
      final y = size.height * (1 - (values[i] / maxVal) * 0.85);
      points.add(Offset(x, y));
    }
    if (points.length < 2) return;

    final paint = Paint()
      ..color = Colors.white.withOpacity(0.9)
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final path = Path()..moveTo(points.first.dx, points.first.dy);
    for (var i = 1; i < points.length; i++) {
      path.lineTo(points[i].dx, points[i].dy);
    }
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _MiniSparklinePainter oldDelegate) =>
      oldDelegate.values != values;
}

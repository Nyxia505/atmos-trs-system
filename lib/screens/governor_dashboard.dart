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
import 'package:atmos_trs_system/widgets/app_logout_button.dart';

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
  static const Color _darkBg = Color(0xFFFFF7ED); // cream background
  static const Color _cardBg = Color(0xFFFFFBF7); // soft white cards
  static const Color _sidebarBg = Color(0xFFEA580C); // dark orange sidebar
  static const Color _sidebarHover = Color(
    0xFFC2410C,
  ); // darker orange for hover
  static const Color _textDark = Color(0xFF1A1A1A);
  static const Color _textMuted = Color(0xFF6B7280);
  static const Color _cardBorder = Color(0xFFFFEDD5); // soft orange border

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
            ? Image.memory(
                _profilePhotoBytes!,
                fit: BoxFit.cover,
              )
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
    final fromName = getMunicipalityIdFromName(spot['municipality']?.toString());
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

  Future<void> _loadData() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      // Check Firebase initialization
      if (Firebase.apps.isEmpty) {
        // Use mock data if Firebase not available
        _useMockData();
        return;
      }

      final firestore = FirebaseFirestore.instance;

      // Load tourists — Governor portal: Misamis Occidental scope only
      final touristsSnapshot = await firestore.collection('tourists').get();
      _tourists = touristsSnapshot.docs
          .map((doc) => {'id': doc.id, ...doc.data()})
          .where(_isTouristInMisamisOccidentalScope)
          .toList();
      _totalTourists = _tourists.length;

      // Load check-ins — filter to province LGUs (municipalityId / municipality name)
      final qrCheckInsSnapshot = await firestore.collection('qr_checkins').get();
      _checkIns = qrCheckInsSnapshot.docs
          .map((doc) => {'id': doc.id, ...doc.data()})
          .where(_isQrCheckInInMisamisOccidental)
          .toList();
      _totalCheckIns = _checkIns.length;

      // Unique tourists today: same person checking in at Tangub, Ozamiz, Sapang Dalaga = 1 tourist
      final today = DateTime.now();
      final todayCheckIns = _checkIns.where((c) {
        final timestamp = c['timestamp'];
        if (timestamp is Timestamp) {
          final d = timestamp.toDate();
          return d.year == today.year && d.month == today.month && d.day == today.day;
        }
        return false;
      }).toList();
      final todayUserIds = todayCheckIns
          .map((c) => c['userId']?.toString())
          .whereType<String>()
          .toSet();
      _uniqueTouristsToday = todayUserIds.length;

      // Tourist spots — province list only (same 17 LGUs)
      final spotsSnapshot = await firestore.collection('tourist_spots').get();
      _governorAllSpots = spotsSnapshot.docs
          .map((doc) => {'id': doc.id, ...doc.data()})
          .where(_isTouristSpotInMisamisOccidental)
          .toList();
      _activeSpots = _governorAllSpots.isNotEmpty ? _governorAllSpots.length : 17;

      // Load announcements
      final announcementsSnapshot = await firestore
          .collection('announcements')
          .orderBy('createdAt', descending: true)
          .get();
      _announcements = announcementsSnapshot.docs
          .map((doc) => {'id': doc.id, ...doc.data()})
          .toList();

      // Calculate tourists per municipality from check-ins (qr_checkins has municipalityId)
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
              muniName.toLowerCase().contains(muni['name'].toString().toLowerCase())) {
            muni['tourists'] = (muni['tourists'] as int) + entry.value;
            break;
          }
        }
      }

      setState(() => _isLoading = false);
    } catch (e) {
      debugPrint('Error loading data: $e');
      _useMockData();
    }
  }

  void _useMockData() {
    setState(() {
      _totalTourists = 12458;
      _totalCheckIns = 8234;
      _uniqueTouristsToday = 312;
      _activeSpots = 47;
      _tourists = List.generate(
        20,
        (i) => {
          'id': 'ATMOS-${(i + 1).toString().padLeft(4, '0')}',
          'name': 'Tourist ${i + 1}',
          'email': 'tourist${i + 1}@example.com',
          'origin': ['Manila', 'Cebu', 'Davao', 'CDO'][i % 4],
          'visits': (i % 10) + 1,
          'province': 'Misamis Occidental',
          'city': 'Oroquieta City',
          'registeredAt': Timestamp.fromDate(
            DateTime.now().subtract(
              Duration(days: i * 2, hours: i % 12, minutes: i % 60),
            ),
          ),
        },
      );
      _checkIns = List.generate(
        100,
        (i) => {
          'location': ['Baliangao Beach', 'Sapang Dalaga Falls', 'Oroquieta City Capitol', 'Panaon Island', 'Hoyohoy Highland'][i % 5],
          'timestamp': Timestamp.fromDate(DateTime.now().subtract(Duration(days: i % 30))),
          'city': ['Oroquieta City', 'Ozamis City', 'Baliangao', 'Sapang Dalaga'][i % 4],
        },
      );
      _announcements = [
        {
          'id': '1',
          'title': 'Welcome to ATMOS TRS',
          'content': 'Tourism registration system is now live!',
          'published': true,
          'date': '2026-02-20',
        },
        {
          'id': '2',
          'title': 'New Tourist Spots Added',
          'content': '5 new spots have been added to the system.',
          'published': true,
          'date': '2026-02-18',
        },
        {
          'id': '3',
          'title': 'System Maintenance',
          'content': 'Scheduled maintenance on Feb 28.',
          'published': false,
          'date': '2026-02-15',
        },
      ];
      _isLoading = false;
    });
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
    if (_isMobile) return 1;
    if (_isTablet) return 2;
    return 4;
  }

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
    return Container(
      decoration: BoxDecoration(
        color: _sidebarBg,
        border: Border(top: BorderSide(color: Colors.grey.shade300)),
      ),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: List.generate(_navItems.length.clamp(0, 5), (index) {
              final item = _navItems[index];
              final isSelected = _selectedIndex == index;
              return InkWell(
                onTap: () => setState(() => _selectedIndex = index),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: isSelected
                        ? _primaryOrange.withOpacity(0.15)
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        item.icon,
                        color: isSelected ? _primaryOrange : Colors.white54,
                        size: 22,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        item.label,
                        style: TextStyle(
                          color: isSelected ? _primaryOrange : Colors.white54,
                          fontSize: 10,
                          fontWeight: isSelected
                              ? FontWeight.w600
                              : FontWeight.w400,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }),
          ),
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
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: expanded ? 16 : 12),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.06),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: _primaryOrange.withOpacity(0.9), width: 1),
        ),
        child: Row(
          mainAxisAlignment:
              expanded ? MainAxisAlignment.start : MainAxisAlignment.center,
          children: [
            SizedBox(
              width: 46,
              height: 46,
              child: TransparentLogo(
                width: 46,
                height: 46,
                fit: BoxFit.contain,
                errorIcon: Icons.public,
                errorIconSize: 26,
                errorIconColor: _primaryOrange,
              ),
            ),
            if (expanded) ...[
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
            ] else ...[
              const SizedBox(width: 8),
            ],
          ],
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

  Widget _buildHeader(String title, {String? subtitle, List<Widget>? actions}) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: _isMobile ? 16 : 24,
        vertical: 16,
      ),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [_accentOrange, _primaryOrange],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: const BorderRadius.vertical(
          bottom: Radius.circular(24),
        ),
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
          if (_isMobile)
            IconButton(
              onPressed: () => Scaffold.of(context).openDrawer(),
              icon: Icon(Icons.menu, color: _textDark),
            ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: _isMobile ? 18 : 22,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                if (subtitle != null)
                  Text(
                    subtitle,
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.8),
                      fontSize: _isMobile ? 12 : 14,
                    ),
                  ),
              ],
            ),
          ),
          if (actions != null) ...actions,
          if (!_isMobile) ...[
            _buildHeaderAction(
              Icons.notifications_outlined,
              badge: _unreadNotificationCount > 0 ? '$_unreadNotificationCount' : null,
              onPressed: _showNotificationsPanel,
            ),
            const SizedBox(width: 12),
            _buildHeaderAction(
              Icons.search_rounded,
              onPressed: _showSearchPanel,
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
            width: MediaQuery.of(context).size.width > 600 ? 440 : MediaQuery.of(context).size.width * 0.9,
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
                        child: const Text('View all', style: TextStyle(color: _primaryOrange, fontWeight: FontWeight.w600)),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close_rounded, color: _textMuted, size: 22),
                        onPressed: () => Navigator.pop(context),
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
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
                          separatorBuilder: (_, __) => Divider(height: 1, color: Colors.grey.shade200),
                          itemBuilder: (context, i) {
                            final a = _announcements[i];
                            final type = a['type']?.toString() ?? 'General';
                            IconData icon = Icons.campaign_rounded;
                            if (type == 'Promo') icon = Icons.local_offer_rounded;
                            else if (type == 'Event') icon = Icons.event_rounded;
                            else if (type == 'Alert') icon = Icons.warning_amber_rounded;
                            return ListTile(
                              contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
                              leading: CircleAvatar(
                                radius: 20,
                                backgroundColor: _primaryOrange.withOpacity(0.15),
                                child: Icon(icon, color: _primaryOrange, size: 20),
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
                                  a['content']?.toString().replaceAll('\n', ' ').trim() ?? '',
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(color: _textMuted, fontSize: 12, height: 1.35),
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

  void _showSearchPanel() {
    final fieldController = TextEditingController();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: _cardBg,
        title: const Text(
          'Search',
          style: TextStyle(color: _textDark, fontWeight: FontWeight.w600),
        ),
        content: TextField(
          controller: fieldController,
          autofocus: true,
          decoration: InputDecoration(
            hintText: 'Search tourists, announcements...',
            prefixIcon: const Icon(Icons.search_rounded, color: _primaryOrange),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: Colors.grey.shade300),
            ),
          ),
          style: const TextStyle(color: _textDark),
          onSubmitted: (value) {
            Navigator.pop(context);
            _searchController.text = value;
            setState(() => _selectedIndex = 1);
          },
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel', style: TextStyle(color: _textDark)),
          ),
          ElevatedButton(
            onPressed: () {
              final value = fieldController.text.trim();
              Navigator.pop(context);
              _searchController.text = value;
              setState(() => _selectedIndex = 1);
            },
            style: ElevatedButton.styleFrom(backgroundColor: _primaryOrange),
            child: const Text('Search'),
          ),
        ],
      ),
    );
  }

  Widget _buildHeaderAction(IconData icon, {String? badge, VoidCallback? onPressed}) {
    return Tooltip(
      message: icon == Icons.notifications_outlined
          ? 'Notifications'
          : 'Search',
      child: GestureDetector(
        onTap: onPressed,
        child: Stack(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: _primaryOrange, size: 22),
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

  // ==================== DASHBOARD SECTION ====================
  Widget _buildDashboardContent() {
    return RefreshIndicator(
      onRefresh: _loadData,
      color: _primaryOrange,
      child: Container(
        color: _darkBg,
        child: Column(
          children: [
            _buildHeader(
              'Welcome back, Governor',
              subtitle: 'Here\'s what\'s happening in Misamis Occidental today',
            ),
            Expanded(
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: EdgeInsets.all(_isMobile ? 16 : 24),
                child: _isMobile
                    ? Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _buildStatsGrid(),
                          const SizedBox(height: 24),
                          _buildChartsSection(),
                          const SizedBox(height: 24),
                          _buildGovernorHeroPanel(),
                        ],
                      )
                    : Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            flex: 3,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                _buildStatsGrid(),
                                const SizedBox(height: 24),
                                _buildChartsSection(),
                              ],
                            ),
                          ),
                          const SizedBox(width: 24),
                          Expanded(
                            flex: 2,
                            child: _buildGovernorHeroPanel(),
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

  /// Right-side hero panel for governor dashboard (image + call-to-action)
  Widget _buildGovernorHeroPanel() {
    return Container(
      height: _isMobile ? 220 : 260,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        gradient: const LinearGradient(
          colors: [_accentOrange, _primaryOrange],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.12),
            blurRadius: 20,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Stack(
        children: [
          Align(
            alignment: Alignment.centerRight,
            child: Opacity(
              opacity: 0.18,
              child: Padding(
                padding: const EdgeInsets.only(right: 12),
                child: Icon(
                  Icons.leaderboard_rounded,
                  size: _isMobile ? 140 : 180,
                  color: Colors.white,
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: const [
                    Text(
                      'Tell the Province\'s story',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    SizedBox(height: 8),
                    Text(
                      'Upload a featured image and message to highlight your priorities for Misamis Occidental.',
                      style: TextStyle(
                        color: Colors.white70,
                        fontSize: 13,
                        height: 1.4,
                      ),
                    ),
                  ],
                ),
                Align(
                  alignment: Alignment.bottomLeft,
                  child: ElevatedButton.icon(
                    onPressed: () {
                      _showCreateAnnouncementDialog();
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.white,
                      foregroundColor: _primaryOrange,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 18,
                        vertical: 12,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(999),
                      ),
                    ),
                    icon: const Icon(Icons.image_outlined, size: 18),
                    label: const Text(
                      'Add banner or message',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
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

  Widget _buildStatsGrid() {
    final checkInTrend = _checkInsTrendText;
    final stats = [
      _StatCard(
        title: 'Total Tourists',
        value: _formatNumber(_totalTourists),
        change: '—',
        isPositive: true,
        icon: Icons.people_alt_rounded,
        color: _primaryOrange,
      ),
      _StatCard(
        title: 'Tourists today',
        value: _formatNumber(_uniqueTouristsToday),
        change: 'Unique (1 per person across all LGUs)',
        isPositive: true,
        icon: Icons.qr_code_scanner_rounded,
        color: Colors.blue,
      ),
      _StatCard(
        title: 'Total Check-ins',
        value: _formatNumber(_totalCheckIns),
        change: checkInTrend.text,
        isPositive: checkInTrend.isPositive,
        icon: Icons.touch_app_rounded,
        color: _accentOrange,
      ),
      _StatCard(
        title: 'Active Spots',
        value: '$_activeSpots',
        change: '—',
        isPositive: true,
        icon: Icons.location_on_rounded,
        color: _accentOrange,
      ),
    ];

    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: _gridCrossAxisCount,
        crossAxisSpacing: 16,
        mainAxisSpacing: 16,
        childAspectRatio: _isMobile ? 0.72 : 0.95,
      ),
      itemCount: stats.length,
      itemBuilder: (context, index) => _buildStatCard(stats[index]),
    );
  }

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
      if (diff >= 0 && diff < 7) thisWeek++;
      else if (diff >= 7 && diff < 14) lastWeek++;
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
      final cat = c['spotCategory']?.toString().trim() ?? c['category']?.toString().trim() ?? 'Other';
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
        .map((e) => {
              'name': e.key,
              'count': e.value,
              'percentage': e.value / total,
            })
        .toList()
      ..sort((a, b) => (b['percentage'] as double).compareTo(a['percentage'] as double));
  }

  Widget _buildStatCard(_StatCard stat) {
    return Container(
      padding: EdgeInsets.all(_isMobile ? 14 : 18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: stat.color.withOpacity(0.08),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.03),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
          BoxShadow(
            color: stat.color.withOpacity(0.06),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 24,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          return FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.center,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  padding: EdgeInsets.all(_isMobile ? 12 : 16),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [
                      BoxShadow(
                        color: stat.color.withOpacity(0.35),
                        blurRadius: 16,
                        offset: const Offset(0, 4),
                      ),
                      BoxShadow(
                        color: stat.color.withOpacity(0.2),
                        blurRadius: 24,
                        offset: const Offset(0, 6),
                      ),
                    ],
                    gradient: RadialGradient(
                      center: Alignment.topLeft,
                      radius: 1.2,
                      colors: [
                        stat.color.withOpacity(0.45),
                        stat.color.withOpacity(0.28),
                        stat.color.withOpacity(0.15),
                      ],
                      stops: const [0.0, 0.5, 1.0],
                    ),
                  ),
                  child: Icon(
                    stat.icon,
                    color: Colors.white,
                    size: _isMobile ? 26 : 32,
                  ),
                ),
                SizedBox(height: _isMobile ? 10 : 14),
                Text(
                  stat.title,
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: const Color(0xFF374151),
                    fontSize: _isMobile ? 13 : 15,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.2,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  stat.value,
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: const Color(0xFF111827),
                    fontSize: _isMobile ? 22 : 28,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.5,
                    height: 1.15,
                  ),
                ),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: stat.isPositive
                          ? [
                              const Color(0xFFD1FAE5),
                              const Color(0xFFA7F3D0),
                            ]
                          : [
                              const Color(0xFFFECACA),
                              const Color(0xFFFCA5A5),
                            ],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [
                      BoxShadow(
                        color: (stat.isPositive
                                ? const Color(0xFF16A34A)
                                : const Color(0xFFDC2626))
                            .withOpacity(0.15),
                        blurRadius: 6,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        stat.isPositive
                            ? Icons.trending_up_rounded
                            : Icons.trending_down_rounded,
                        color: stat.isPositive
                            ? const Color(0xFF059669)
                            : const Color(0xFFB91C1C),
                        size: 14,
                      ),
                      const SizedBox(width: 5),
                      Text(
                        stat.change,
                        style: TextStyle(
                          color: stat.isPositive
                              ? const Color(0xFF047857)
                              : const Color(0xFF991B1B),
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
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

  Widget _buildTouristArrivalsChart() {
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
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Tourist Arrivals',
                style: TextStyle(
                  color: _textDark,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
              _buildTimeFilterDropdown(),
            ],
          ),
          const SizedBox(height: 24),
          SizedBox(
            height: 200,
            child: CustomPaint(
              size: const Size(double.infinity, 200),
              painter: _ChartPainter(color: _primaryOrange, values: _dashboardTrendValues),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTimeFilterDropdown() {
    return PopupMenuButton<String>(
      initialValue: _selectedTimeFilter,
      onSelected: (value) => setState(() => _selectedTimeFilter = value),
      itemBuilder: (context) => ['This Week', 'This Month', 'This Year']
          .map((filter) => PopupMenuItem(value: filter, child: Text(filter)))
          .toList(),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: Colors.grey.shade200,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              _selectedTimeFilter,
              style: const TextStyle(color: _textMuted, fontSize: 12),
            ),
            const SizedBox(width: 4),
            const Icon(Icons.keyboard_arrow_down, color: _textMuted, size: 18),
          ],
        ),
      ),
    );
  }

  Widget _buildTopCategoriesCard() {
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
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Top Categories',
                style: TextStyle(
                  color: _textDark,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
              TextButton(
                onPressed: () => setState(() => _selectedIndex = 4),
                child: const Text(
                  'View All',
                  style: TextStyle(color: _primaryOrange),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          LayoutBuilder(
            builder: (context, constraints) {
              final w = constraints.maxWidth;
              final pieSize = (w < 420 ? w * 0.72 : 200.0)
                  .clamp(160.0, 240.0)
                  .toDouble();
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
                        holeColor: _cardBg,
                        isEmpty: totalCount == 0,
                      ),
                    ),
                    if (totalCount == 0)
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 20),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.pie_chart_outline_rounded,
                              color: Colors.grey.shade400,
                              size: 28,
                            ),
                            const SizedBox(height: 6),
                            Text(
                              'No check-in data yet',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: Colors.grey.shade600,
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
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
                children: [
                  for (var i = 0; i < stats.length; i++)
                    _buildCategoryLegendRow(
                      stats[i]['name'] as String,
                      totalCount == 0
                          ? 0.0
                          : (sumP > 0
                              ? (stats[i]['percentage'] as double) / sumP
                              : (stats.isEmpty
                                  ? 0.0
                                  : 1.0 / stats.length)),
                      _categoryColor(stats[i]['name'] as String),
                    ),
                ],
              );
              if (w < 420) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Center(child: chart),
                    const SizedBox(height: 18),
                    legend,
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
            },
          ),
        ],
      ),
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
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              name,
              style: const TextStyle(color: _textMuted, fontSize: 13),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Text(
            pctLabel,
            style: const TextStyle(
              color: _textDark,
              fontSize: 13,
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
                'Misamis Occidental — tourists whose profile lists this province or a municipality/city in the province.',
          ),
          Expanded(
            child: SingleChildScrollView(
              padding: EdgeInsets.all(_isMobile ? 16 : 24),
              child: Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: _cardBg,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: _cardBorder),
                ),
                child: Column(
                  children: [
                    _buildSearchBar('Search tourists...'),
                    const SizedBox(height: 20),
                    if (filteredTourists.isEmpty)
                      _buildEmptyState(
                        'No tourists found',
                        Icons.people_outline,
                      )
                    else
                      _isMobile
                          ? _buildTouristsListMobile(filteredTourists)
                          : _buildTouristsTableDesktop(filteredTourists),
                  ],
                ),
              ),
            ),
          ),
        ],
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
    return Container(
      padding: const EdgeInsets.all(40),
      child: Column(
        children: [
          Icon(icon, color: Colors.white24, size: 64),
          const SizedBox(height: 16),
          Text(
            message,
            style: const TextStyle(color: _textMuted, fontSize: 16),
          ),
        ],
      ),
    );
  }

  Widget _buildTouristsListMobile(List<Map<String, dynamic>> tourists) {
    int visitCount(Map<String, dynamic> t) {
      final v = t['totalVisits'] ?? t['visits'] ?? 0;
      if (v is int) return v;
      if (v is num) return v.toInt();
      return int.tryParse(v.toString()) ?? 0;
    }
    final sorted = List<Map<String, dynamic>>.from(tourists)
      ..sort((a, b) => visitCount(b).compareTo(visitCount(a)));

    return Column(
      children: sorted
          .map(
            (t) => Container(
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.grey.shade100,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  CircleAvatar(
                    backgroundColor: _primaryOrange.withOpacity(0.2),
                    child: Text(
                      (_getTouristDisplayName(t))[0].toUpperCase(),
                      style: const TextStyle(
                        color: _primaryOrange,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _getTouristDisplayName(t),
                          style: const TextStyle(
                            color: _textDark,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        Text(
                          t['id'] ?? '',
                          style: TextStyle(
                            color: _primaryOrange.withOpacity(0.8),
                            fontSize: 12,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Date: ${_formatRegisteredDateOnly(_registeredDateTimeFromTourist(t))}',
                          style: TextStyle(
                            color: _textMuted,
                            fontSize: 11,
                          ),
                        ),
                        Text(
                          'Time: ${_formatRegisteredTimeOnly(_registeredDateTimeFromTourist(t))}',
                          style: TextStyle(
                            color: _textMuted,
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: () => _showTouristDetails(t),
                    icon: const Icon(
                      Icons.visibility,
                      color: _primaryOrange,
                      size: 20,
                    ),
                  ),
                ],
              ),
            ),
          )
          .toList(),
    );
  }

  // Min widths so DataTable does not shrink the Actions column off-screen.
  static const double _touristColName = 200;
  static const double _touristColId = 128;
  static const double _touristColOrigin = 220;
  static const double _touristColDate = 108;
  static const double _touristColTime = 120;
  static const double _touristColVisits = 72;
  static const double _touristColActions = 88;

  Widget _buildTouristsTableDesktop(List<Map<String, dynamic>> tourists) {
    // Sort by visits descending (most visits first / by rank)
    int visitCount(Map<String, dynamic> t) {
      final v = t['totalVisits'] ?? t['visits'] ?? 0;
      if (v is int) return v;
      if (v is num) return v.toInt();
      return int.tryParse(v.toString()) ?? 0;
    }
    final sorted = List<Map<String, dynamic>>.from(tourists)
      ..sort((a, b) => visitCount(b).compareTo(visitCount(a)));

    const headStyle = TextStyle(
      color: _textDark,
      fontWeight: FontWeight.w700,
      fontSize: 13,
    );

    Widget colLabel(String text, double w) => SizedBox(
          width: w,
          child: Text(text, style: headStyle),
        );

    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: Colors.black, width: 1.5),
        borderRadius: BorderRadius.circular(12),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Scrollbar(
          scrollbarOrientation: ScrollbarOrientation.bottom,
          thumbVisibility: true,
          thickness: 8,
          radius: const Radius.circular(4),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            primary: false,
            child: DataTable(
              columnSpacing: 20,
              horizontalMargin: 12,
              headingRowColor: WidgetStateProperty.all(
                Colors.grey.shade100,
              ),
              headingTextStyle: headStyle,
              columns: [
                DataColumn(label: colLabel('Name', _touristColName)),
                DataColumn(label: colLabel('Tourist ID', _touristColId)),
                DataColumn(label: colLabel('Origin', _touristColOrigin)),
                DataColumn(label: colLabel('Date', _touristColDate)),
                DataColumn(label: colLabel('Time', _touristColTime)),
                DataColumn(label: colLabel('Visits', _touristColVisits)),
                DataColumn(label: colLabel('Actions', _touristColActions)),
              ],
              rows: sorted
                  .map(
                    (t) => DataRow(
                      cells: [
                        DataCell(
                          SizedBox(
                            width: _touristColName,
                            child: Text(
                              _getTouristDisplayName(t),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(color: _textDark),
                            ),
                          ),
                        ),
                        DataCell(
                          SizedBox(
                            width: _touristColId,
                            child: Text(
                              t['id'] ?? '',
                              style: const TextStyle(
                                color: _primaryOrange,
                                fontFamily: 'monospace',
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ),
                        DataCell(
                          SizedBox(
                            width: _touristColOrigin,
                            child: Text(
                              _getTouristOrigin(t),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(color: _textMuted),
                            ),
                          ),
                        ),
                        DataCell(
                          SizedBox(
                            width: _touristColDate,
                            child: Text(
                              _formatRegisteredDateOnly(
                                _registeredDateTimeFromTourist(t),
                              ),
                              style: const TextStyle(
                                color: _textDark,
                                fontSize: 13,
                              ),
                            ),
                          ),
                        ),
                        DataCell(
                          SizedBox(
                            width: _touristColTime,
                            child: Text(
                              _formatRegisteredTimeOnly(
                                _registeredDateTimeFromTourist(t),
                              ),
                              style: const TextStyle(
                                color: _textDark,
                                fontSize: 13,
                              ),
                            ),
                          ),
                        ),
                        DataCell(
                          SizedBox(
                            width: _touristColVisits,
                            child: Text(
                              '${t['totalVisits'] ?? t['visits'] ?? 0}',
                              style: const TextStyle(color: _textMuted),
                            ),
                          ),
                        ),
                        DataCell(
                          SizedBox(
                            width: _touristColActions,
                            child: Align(
                              alignment: Alignment.centerLeft,
                              child: IconButton(
                                padding: EdgeInsets.zero,
                                constraints: const BoxConstraints(
                                  minWidth: 44,
                                  minHeight: 44,
                                ),
                                onPressed: () => _showTouristDetails(t),
                                icon: const Icon(
                                  Icons.visibility,
                                  color: _primaryOrange,
                                  size: 20,
                                ),
                                tooltip: 'View',
                              ),
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
      ),
    );
  }

  void _showTouristDetails(Map<String, dynamic> tourist) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: _cardBg,
        title: Text(
          _getTouristDisplayName(tourist),
          style: const TextStyle(color: _textDark, fontWeight: FontWeight.w600),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _detailRow('Tourist ID', tourist['id'] ?? tourist['touristId'] ?? '-'),
            _detailRow('Email', tourist['email'] ?? '-'),
            _detailRow('Origin', tourist['origin']?.toString() ?? tourist['city']?.toString() ?? tourist['country']?.toString() ?? '-'),
            _detailRow(
              'Date registered',
              _formatRegisteredDateOnly(_registeredDateTimeFromTourist(tourist)),
            ),
            _detailRow(
              'Time registered',
              _formatRegisteredTimeOnly(_registeredDateTimeFromTourist(tourist)),
            ),
            _detailRow('Total Visits', '${tourist['visits'] ?? tourist['totalVisits'] ?? 0}'),
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
              padding: const EdgeInsets.all(16),
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
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: QrImageView(
                      data: qrData,
                      version: QrVersions.auto,
                      size: 180,
                      backgroundColor: Colors.white,
                      errorCorrectionLevel: QrErrorCorrectLevel.H,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
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
                                content: Text('PNG ready — check downloads or share sheet'),
                                backgroundColor: _primaryOrange,
                              ),
                            );
                          }
                        },
                        child: Text('PNG', style: TextStyle(color: _primaryOrange)),
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
                        child: Text('PDF', style: TextStyle(color: _primaryOrange)),
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
    return Container(
      margin: _isMobile ? const EdgeInsets.only(bottom: 12) : null,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _cardBg,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: Colors.grey.shade300,
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: _primaryOrange.withOpacity(0.15),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              Icons.location_city_rounded,
              color: _primaryOrange,
              size: 24,
            ),
          ),
          const SizedBox(width: 16),
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
                    fontWeight: FontWeight.w600,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: _primaryOrange.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        type,
                        style: const TextStyle(
                          color: _primaryOrange,
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
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
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          GestureDetector(
            onTap: () => _showMunicipalityDetails(municipality),
            child: Icon(
              Icons.arrow_forward_ios_rounded,
              color: _textMuted,
              size: 16,
            ),
          ),
        ],
      ),
    );
  }

  DateTime? _checkInTimestamp(Map<String, dynamic> c) {
    final t = c['timestamp'];
    if (t == null) return null;
    if (t is Timestamp) return t.toDate();
    return null;
  }

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
      final one = t['city']?.toString().trim() ??
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

  List<double> get _analyticsTrendValues {
    const days = 14;
    final counts = List.filled(days, 0.0);
    for (var c in _checkIns) {
      final d = _checkInTimestamp(c);
      if (d != null) {
        final today = DateTime.now();
        final diff = today.difference(DateTime(d.year, d.month, d.day)).inDays;
        if (diff >= 0 && diff < days) counts[days - 1 - diff] += 1;
      }
    }
    return counts;
  }

  List<Map<String, dynamic>> get _analyticsTopSpots {
    final byLocation = <String, int>{};
    for (var c in _checkIns) {
      final loc = c['location']?.toString().trim() ?? c['spotName']?.toString().trim() ?? '';
      if (loc.isNotEmpty) byLocation[loc] = (byLocation[loc] ?? 0) + 1;
    }
    return byLocation.entries
        .map((e) => {'name': e.key, 'visits': e.value})
        .toList()
      ..sort((a, b) => (b['visits'] as int).compareTo(a['visits'] as int));
  }

  // ==================== ANALYTICS SECTION ====================
  Widget _buildAnalyticsContent() {
    return Container(
      color: _darkBg,
      child: Column(
        children: [
          _buildHeader(
            'Analytics',
            subtitle: 'Misamis Occidental only — tourism insights from provincial check-ins & registrations',
          ),
          Expanded(
            child: SingleChildScrollView(
              padding: EdgeInsets.all(_isMobile ? 16 : 24),
              child: Column(
                children: [
                  _buildAnalyticsCards(),
                  const SizedBox(height: 24),
                  _buildVisitorTrendsChart(),
                  const SizedBox(height: 24),
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
    return GridView.count(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisCount: _isMobile ? 2 : 4,
      crossAxisSpacing: 16,
      mainAxisSpacing: 16,
      childAspectRatio: 1.5,
      children: [
        _buildAnalyticsCard(
          'Daily Avg',
          '$_analyticsDailyAvg',
          Icons.calendar_today,
          Colors.blue,
        ),
        _buildAnalyticsCard(
          'Peak Hour',
          _analyticsPeakHour,
          Icons.access_time,
          _primaryOrange,
        ),
        _buildAnalyticsCard('Top Origin', _analyticsTopOrigin, Icons.flight, Colors.green),
        _buildAnalyticsCard('Avg Stay', '—', Icons.hotel, Colors.purple),
      ],
    );
  }

  Widget _buildAnalyticsCard(
    String label,
    String value,
    IconData icon,
    Color color,
  ) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _cardBg,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: _cardBorder),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, color: color, size: 28),
          const SizedBox(height: 8),
          Text(
            value,
            style: const TextStyle(
              color: _textDark,
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          Text(label, style: const TextStyle(color: _textMuted, fontSize: 12)),
        ],
      ),
    );
  }

  Widget _buildVisitorTrendsChart() {
    final values = _analyticsTrendValues;
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
          const Text(
            'Visitor Trends',
            style: TextStyle(
              color: _textDark,
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 24),
          SizedBox(
            height: 200,
            child: CustomPaint(
              size: const Size(double.infinity, 200),
              painter: _ChartPainter(color: _primaryOrange, values: values),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTopSpotsChart() {
    final spots = _analyticsTopSpots.take(10).toList();
    final maxVisits = spots.isEmpty ? 1 : (spots.first['visits'] as int);

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
          const Text(
            'Most Visited Spots',
            style: TextStyle(
              color: _textDark,
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 20),
          if (spots.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: Text(
                'No check-in data yet.',
                style: TextStyle(color: _textMuted, fontSize: 14),
              ),
            )
          else
            ...spots.asMap().entries.map((entry) {
              final index = entry.key;
              final spot = entry.value;
              final visits = spot['visits'] as int;
              return Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Row(
                  children: [
                    Container(
                      width: 24,
                      height: 24,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: index == 0
                            ? _primaryOrange
                            : _primaryOrange.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        '${index + 1}',
                        style: TextStyle(
                          color: index == 0 ? Colors.white : _primaryOrange,
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            spot['name'] as String,
                            style: const TextStyle(
                              color: _textDark,
                              fontSize: 13,
                            ),
                          ),
                          const SizedBox(height: 4),
                          ClipRRect(
                            borderRadius: BorderRadius.circular(4),
                            child: LinearProgressIndicator(
                              value: maxVisits > 0 ? visits / maxVisits : 0,
                              backgroundColor: Colors.grey.shade200,
                              valueColor: AlwaysStoppedAnimation<Color>(
                                _primaryOrange.withOpacity(0.8),
                              ),
                              minHeight: 4,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    Text(
                      '$visits',
                      style: const TextStyle(
                        color: _primaryOrange,
                        fontWeight: FontWeight.w600,
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
    return Container(
      color: _darkBg,
      child: Column(
        children: [
          _buildHeader(
            'Announcements',
            subtitle: 'Manage public announcements',
            actions: [
              ElevatedButton.icon(
                onPressed: _showCreateAnnouncementDialog,
                icon: const Icon(Icons.add, size: 18),
                label: const Text('New'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: _primaryOrange,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                ),
              ),
            ],
          ),
          Expanded(
            child: _announcements.isEmpty
                ? Center(
                    child: _buildEmptyState(
                      'No announcements yet',
                      Icons.campaign_outlined,
                    ),
                  )
                : ListView.builder(
                    padding: EdgeInsets.all(_isMobile ? 16 : 24),
                    itemCount: _announcements.length,
                    itemBuilder: (context, index) =>
                        _buildAnnouncementCard(_announcements[index]),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildAnnouncementCard(Map<String, dynamic> announcement) {
    final isPublished = announcement['published'] ?? false;
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: _cardBg,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isPublished
              ? _primaryOrange.withOpacity(0.3)
              : Colors.white.withOpacity(0.05),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  announcement['title'] ?? 'Untitled',
                  style: const TextStyle(
                    color: _textDark,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: isPublished
                      ? _primaryOrange.withOpacity(0.15)
                      : Colors.grey.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  isPublished ? 'Published' : 'Draft',
                  style: TextStyle(
                    color: isPublished ? _primaryOrange : Colors.grey,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            announcement['content'] ?? '',
            style: TextStyle(
              color: Colors.white.withOpacity(0.7),
              fontSize: 14,
            ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Icon(Icons.calendar_today, color: _textMuted, size: 14),
              const SizedBox(width: 6),
              Text(
                announcement['date'] ?? '-',
                style: TextStyle(color: _textMuted, fontSize: 12),
              ),
              const Spacer(),
              IconButton(
                onPressed: () => _togglePublishAnnouncement(announcement),
                icon: Icon(
                  isPublished ? Icons.visibility_off : Icons.visibility,
                  color: _textMuted,
                  size: 18,
                ),
                tooltip: isPublished ? 'Unpublish' : 'Publish',
              ),
              IconButton(
                onPressed: () => _editAnnouncement(announcement),
                icon: const Icon(Icons.edit, color: _textMuted, size: 18),
                tooltip: 'Edit',
              ),
              IconButton(
                onPressed: () => _deleteAnnouncement(announcement),
                icon: const Icon(
                  Icons.delete,
                  color: Colors.redAccent,
                  size: 18,
                ),
                tooltip: 'Delete',
              ),
            ],
          ),
        ],
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

                  // Save to Firestore
                  try {
                    if (Firebase.apps.isNotEmpty) {
                      final docRef = await FirebaseFirestore.instance
                          .collection('announcements')
                          .add(announcementData);
                      setState(() {
                        _announcements.insert(0, {
                          'id': docRef.id,
                          ...announcementData,
                          'createdAt': DateTime.now(),
                        });
                      });
                    } else {
                      setState(() {
                        _announcements.insert(0, {
                          'id': DateTime.now().millisecondsSinceEpoch
                              .toString(),
                          ...announcementData,
                        });
                      });
                    }
                  } catch (e) {
                    debugPrint('Error saving announcement: $e');
                    setState(() {
                      _announcements.insert(0, {
                        'id': DateTime.now().millisecondsSinceEpoch.toString(),
                        ...announcementData,
                      });
                    });
                  }

                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        'Announcement ${isPublished ? "published" : "saved as draft"}',
                      ),
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

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          newPublished ? 'Announcement published' : 'Announcement unpublished',
        ),
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
            .map((h) => DataColumn(
                  label: Text(
                    h,
                    style: const TextStyle(
                      color: _textDark,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ))
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
            final lines = content.split('\n').where((s) => s.trim().isNotEmpty).toList();
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
        ..color = Colors.grey.shade300
        ..style = PaintingStyle.stroke
        ..strokeWidth = r * 0.32;
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
  final String change;
  final bool isPositive;
  final IconData icon;
  final Color color;
  _StatCard({
    required this.title,
    required this.value,
    required this.change,
    required this.isPositive,
    required this.icon,
    required this.color,
  });
}

class _ChartPainter extends CustomPainter {
  final Color color;
  final List<double> values;
  _ChartPainter({required this.color, this.values = const []});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 3
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    final fillPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [color.withOpacity(0.3), color.withOpacity(0.0)],
      ).createShader(Rect.fromLTWH(0, 0, size.width, size.height));

    final gridPaint = Paint()
      ..color = Colors.grey.shade300
      ..strokeWidth = 1;

    for (int i = 0; i < 5; i++) {
      final y = size.height * i / 4;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }

    final maxVal = values.isEmpty ? 1.0 : values.reduce((a, b) => a > b ? a : b).clamp(1.0, double.infinity);
    final points = <Offset>[];
    if (values.length >= 2) {
      for (int i = 0; i < values.length; i++) {
        final x = size.width * (i / (values.length - 1));
        final y = size.height * (1 - (values[i] / maxVal));
        points.add(Offset(x, y));
      }
    } else {
      points.addAll([
        Offset(0, size.height * 0.6),
        Offset(size.width * 0.15, size.height * 0.5),
        Offset(size.width * 0.3, size.height * 0.7),
        Offset(size.width * 0.45, size.height * 0.4),
        Offset(size.width * 0.6, size.height * 0.5),
        Offset(size.width * 0.75, size.height * 0.3),
        Offset(size.width * 0.9, size.height * 0.4),
        Offset(size.width, size.height * 0.2),
      ]);
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
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

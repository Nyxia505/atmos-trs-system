import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart'
    show kIsWeb, defaultTargetPlatform, TargetPlatform;
import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:cross_file/cross_file.dart';
import 'package:share_plus/share_plus.dart';
import 'package:gal/gal.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:atmos_trs_system/config/auth_config.dart';
import 'package:atmos_trs_system/config/beta_testing_config.dart';
import 'package:atmos_trs_system/config/session_storage.dart';
import 'package:atmos_trs_system/config/supabase_storage_config.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'dart:convert';
import 'dart:math' as math;
import 'package:atmos_trs_system/widgets/ui_skeleton.dart';
import 'package:atmos_trs_system/services/dashboard_stats_cache.dart';
import 'package:atmos_trs_system/widgets/app_search_bar.dart';
import 'package:atmos_trs_system/data/misamis_occidental_municipalities.dart';
import 'package:atmos_trs_system/utils/spot_qr_helper.dart';
import 'package:atmos_trs_system/utils/spot_qr_export.dart';
import 'package:atmos_trs_system/widgets/atmos_square_logo.dart';
import 'package:atmos_trs_system/services/registration_municipality_resolver.dart';
import 'package:atmos_trs_system/services/user_directory_service.dart';
import 'package:atmos_trs_system/services/auth_service.dart';
import 'package:atmos_trs_system/services/tourist_account_admin_service.dart';
import 'package:atmos_trs_system/utils/municipality_helper.dart';
import 'package:atmos_trs_system/utils/tourist_id_helper.dart';
import 'package:atmos_trs_system/models/tourist_spot.dart';
import 'package:atmos_trs_system/navigation/post_logout_navigation.dart';
import 'package:atmos_trs_system/services/tourist_spots_firestore_service.dart';
import 'package:atmos_trs_system/utils/csv_file_download.dart';
import 'package:atmos_trs_system/utils/checkin_visitor_count.dart';
import 'package:atmos_trs_system/utils/dot_var2_visitor_record_report.dart';
import 'package:atmos_trs_system/utils/production_data_filters.dart';
import 'package:atmos_trs_system/services/vr_tour_firestore_service.dart';
import 'package:atmos_trs_system/screens/vr_webview_screen.dart';
import 'package:image_picker/image_picker.dart';
import 'package:atmos_trs_system/widgets/dot_report_export_panel.dart';
import 'package:atmos_trs_system/services/dae3_auto_report_service.dart';
import 'package:atmos_trs_system/widgets/lgu_events_panel.dart';
import 'package:atmos_trs_system/services/lgu_event_service.dart';

class LguDashboard extends StatefulWidget {
  const LguDashboard({super.key});

  @override
  State<LguDashboard> createState() => _LguDashboardState();
}

class _LguDashboardState extends State<LguDashboard>
    with SingleTickerProviderStateMixin {
  int _selectedIndex = 0;
  bool _isSidebarExpanded = true;
  bool _didInitializeSidebarForViewport = false;
  late AnimationController _animationController;

  // Theme â€” premium LGU tourism dashboard
  static const Color _primaryOrange = Color(0xFFF97316);
  static const Color _accentOrange = Color(0xFFFB923C);
  static const Color _darkBg = Color(0xFFFFF8F3);
  static const Color _cardBg = Color(0xFFFFFFFF);
  static const Color _textDark = Color(0xFF111827);
  static const Color _textMuted = Color(0xFF6B7280);
  static const Color _kAnalyticsSurfaceBorder = Color(0xFFE5E7EB);
  static const Color _kpiGreen = Color(0xFF10B981);
  static const Color _kpiOrange = Color(0xFFF97316);
  static const Color _kpiBlue = Color(0xFF3B82F6);
  static const Color _kpiPurple = Color(0xFF8B5CF6);
  static const Color _surfaceBg = Color(0xFFF9FAFB);
  static const Color _panelBorder = Color(0xFFE5E7EB);
  static const Color _tintBlue = Color(0xFFE8F4FF);
  static const Color _tintGreen = Color(0xFFECFDF3);
  static const Color _tintPurple = Color(0xFFF5F0FF);
  static const Color _tintOrange = Color(0xFFFFF3E8);

  /// Shared brand gradient for sidebar + every page header (same colors).
  static const LinearGradient _lguBrandGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [
      Color(0xFFFB923C),
      Color(0xFFF97316),
      Color(0xFFEA580C),
    ],
    stops: [0.0, 0.55, 1.0],
  );
  static const String _fallbackLguScenicAsset =
      'assets/images/capitol lp bg.png';

  /// Hero photos must match the logged-in LGU
  /// (Oroquieta Plaza for Oroquieta â€” never Tangub/Ozamiz landmarks).
  String get _dashboardHeroImageAsset {
    switch (normalizeMunicipalityId(_storedMunicipalityId)) {
      case 'oroquieta':
        return 'assets/images/oroquieta City plaza.jpeg';
      case 'ozamiz':
        return 'assets/images/ozamis city.webp';
      case 'tangub':
        return 'assets/images/Asenso Global Garden 1.png';
      case 'sinacaban':
        return 'assets/images/Amorap.png';
      case 'baliangao':
        return 'assets/images/Baliangao.png';
      case 'bonifacio':
        return 'assets/images/Bonifacio_kanao.png';
      case 'calamba':
        return 'assets/images/Calamba.png';
      case 'clarin':
        return 'assets/images/Clarin.png';
      case 'jimenez':
        return 'assets/images/Jimenez.png';
      case 'lopezjaena':
        return 'assets/images/Lopez Jaena.png';
      case 'panaon':
        return 'assets/images/Panaon.png';
      case 'plaridel':
        return 'assets/images/Plaridel.png';
      case 'sapangdalaga':
        return 'assets/images/Sapang_Dalaga_v2.png';
      case 'dvc':
        return 'assets/images/DonVic_v2.png';
      case 'aloran':
        return 'assets/images/aloran.png';
      case 'tudela':
        return 'assets/images/Tudela Village.webp';
      case 'concepcion':
        return 'assets/images/conception_v2.png';
      default:
        return _fallbackLguScenicAsset;
    }
  }

  String get _dashboardCityDisplayName {
    final named = _municipalityName?.trim();
    if (named != null && named.isNotEmpty) return named;
    final id = normalizeMunicipalityId(_storedMunicipalityId);
    for (final m in getMisamisOccidentalMunicipalities()) {
      if (normalizeMunicipalityId(m.id) == id) return m.name;
    }
    return 'Misamis Occidental';
  }

  BoxDecoration _tourismPanelDecoration() => BoxDecoration(
    color: Colors.white,
    borderRadius: BorderRadius.circular(20),
    border: Border.all(color: _panelBorder.withValues(alpha: 0.9)),
    boxShadow: [
      BoxShadow(
        color: Colors.black.withValues(alpha: 0.04),
        blurRadius: 18,
        offset: const Offset(0, 8),
      ),
    ],
  );

  Widget _wrapTourismPanel(Widget child, {EdgeInsets? padding}) {
    return Container(
      padding: padding ?? EdgeInsets.all(_isMobile ? 14 : 16),
      decoration: _tourismPanelDecoration(),
      child: child,
    );
  }

  /// Large rounded UI (dashboard reference): main panel.

  // Data states â€” staged loading for smooth post-login paint
  bool _isBootstrapping = true;
  bool _isLoadingDetails = true;
  bool _hasCachedStats = false;
  String? _errorMessage;

  /// Newest check-ins only — enough for dashboard lists/KPIs without full history.
  static const int _qrCheckInFetchLimit = 100;
  static const int _touristDocIdChunkSize = 10;

  // Dashboard stats
  int _todayCheckIns = 0;
  int _totalTourists = 0;
  int _activeSpots = 0;
  int _totalVRTours = 0;

  // Data lists
  List<Map<String, dynamic>> _checkIns = [];
  List<TouristSpot> _touristSpots = [];
  List<Map<String, dynamic>> _tourists = [];
  final Map<String, Map<String, dynamic>> _touristProfileByUid = {};
  List<Map<String, dynamic>> _vrTours = [];
  List<Map<String, dynamic>> _recentActivity = [];
  List<Map<String, dynamic>> _notifications = [];
  int _unreadNotifications = 0;

  /// Province events stream â€” badge + snackbar for new posts from other LGUs.
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>?
      _lguEventsSubscription;
  bool _lguEventsStreamPrimed = false;
  /// All announcements from Firestore (used for cross-LGU badges).
  List<Map<String, dynamic>> _lguEvents = [];
  final Set<String> _seenCrossLguEventIds = {};
  Set<String> _knownPublishedEventIds = {};
  /// 0 Province Live, 1 My posts â€” for Events fragment tabs.
  int _eventsPanelTab = 0;

  /// For real-time check-in notifications: newest check-in doc id we've seen.
  String? _lastSeenCheckInId;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>?
  _qrCheckInsSubscription;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>?
  _qrCheckInsLguSubscription;
  QuerySnapshot<Map<String, dynamic>>? _munCheckInsSnap;
  QuerySnapshot<Map<String, dynamic>>? _lguCheckInsSnap;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>?
  _touristRegistrationsSubscription;
  bool _touristRegistrationStreamPrimed = false;
  StreamSubscription<List<TouristSpot>>? _touristSpotsSubscription;
  String? _storedMunicipalityId;
  List<TouristSpot> _allTouristSpots = [];

  // Search controllers
  final _checkInsSearchController = TextEditingController();
  final _spotsSearchController = TextEditingController();
  final _touristsSearchController = TextEditingController();
  final _dashboardSearchController = TextEditingController();
  // Filter states
  String _checkInStatusFilter = 'All';
  String _checkInDateFilter = 'All';
  String _spotCategoryFilter = 'All';
  String _spotVrFilter = 'All';
  // Export states
  bool _isExporting = false;
  double _exportProgress = 0.0;

  /// Analytics page RepaintBoundary (insights) for PNG screenshot.
  final GlobalKey _reportsRepaintKey = GlobalKey();
  bool _reportsScreenshotBusy = false;

  /// One-shot Firestore sync for `qrValue` / `qr_payload` / `createdAt` on `tourist_spots`.
  bool _isBackfillingSpotQr = false;
  bool _didAutoBackfillSpotQr = false;
  bool _touristFirestoreReadsBlocked = false;

  // Settings (local prefs; same pattern as governor dashboard)
  bool _emailNotifications = true;
  bool _pushNotifications = true;
  bool _weeklyReports = false;
  String? _lastBackupDate;
  String _profileName = 'LGU Office';
  String _profileEmail = '';
  String? _profilePhotoBase64;
  Uint8List? _profilePhotoBytes;

  final List<_NavItem> _navItems = [
    _NavItem(icon: Icons.dashboard_rounded, label: 'Dashboard'),
    _NavItem(icon: Icons.qr_code_scanner_rounded, label: 'Tourist Visits'),
    _NavItem(icon: Icons.place_rounded, label: 'Tourist Spots'),
    _NavItem(icon: Icons.qr_code_2_rounded, label: 'Spot QR Codes'),
    _NavItem(icon: Icons.people_alt_rounded, label: 'Registered Tourists'),
    _NavItem(icon: Icons.analytics_rounded, label: 'Analytics'),
    _NavItem(icon: Icons.event_rounded, label: 'Events'),
    _NavItem(icon: Icons.settings_rounded, label: 'Settings'),
  ];

  static const int _mainNavCount = 6; // Dashboard through Analytics
  static const int _touristSpotsNavIndex = 2;
  static const int _spotQRCodesIndex = 3;
  static const int _analyticsIndex = 5;
  static const int _eventsIndex = 6;
  static const int _settingsIndex = 7;

  final List<String> _categories = [
    'All',
    'Beach',
    'Falls',
    'Historical',
    'Mountain',
    'Resort',
  ];
  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 250),
    );
    _animationController.forward();
    _subscribeToTouristSpots();
    unawaited(_loadTourismSettings());
    // Paint cached KPIs and start network load in parallel (don't gate on prefs I/O).
    unawaited(_restoreLguStatsCache());
    unawaited(_loadData());
  }

  Future<void> _restoreLguStatsCache() async {
    var munId = await SessionStorage.getStoredMunicipalityId();
    final cached = await DashboardStatsCache.loadLgu(munId);
    if (cached == null || !mounted) return;
    setState(() {
      _todayCheckIns = cached.todayCheckIns;
      _totalTourists = cached.totalTourists;
      _activeSpots = cached.activeSpots;
      _totalVRTours = cached.totalVrTours;
      if (cached.municipalityName != null) {
        _municipalityName = cached.municipalityName;
      }
      if (cached.profileName != null && cached.profileName!.isNotEmpty) {
        _profileName = cached.profileName!;
      }
      _hasCachedStats = true;
    });
  }

  Future<void> _saveLguStatsCache() async {
    await DashboardStatsCache.saveLgu(
      _storedMunicipalityId,
      LguDashboardStatsCache(
        todayCheckIns: _todayCheckIns,
        totalTourists: _totalTourists,
        activeSpots: _activeSpots,
        totalVrTours: _totalVRTours,
        municipalityName: _municipalityName,
        profileName: _profileName,
      ),
    );
  }

  List<Map<String, dynamic>> _processCheckInDocs(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
  ) {
    final sorted = _sortCheckInsNewestFirst(
      _filterRealCheckIns(
        docs
            .map(
              (doc) => _normalizeCheckInForUi({
                'id': doc.id,
                ...doc.data(),
              }),
            )
            .toList(),
      ),
    );
    return sorted.length > 100 ? sorted.take(100).toList() : sorted;
  }

  Future<void> _loadMunicipalityCheckInsAndTourists({
    required FirebaseFirestore firestore,
    required List<String> queryIds,
  }) async {
    var docs = await _fetchQrCheckInDocs(
      firestore,
      queryIds,
      getOptions: const GetOptions(source: Source.cache),
    );
    final usedCache = docs.isNotEmpty;
    if (docs.isEmpty) {
      docs = await _fetchQrCheckInDocs(
        firestore,
        queryIds,
        getOptions: const GetOptions(source: Source.server),
      );
    }

    _checkIns = _processCheckInDocs(docs);
    _lastSeenCheckInId =
        _checkIns.isNotEmpty ? (_checkIns.first['id'] as String?) : null;
    debugPrint(
      '[LguDashboard] loaded ${_checkIns.length} qr_checkins for $queryIds',
    );
    _subscribeToCheckIns(queryIds);
    _subscribeToTouristRegistrations(queryIds);
    _recomputeDashboardStats();

    if (mounted) {
      setState(() => _isBootstrapping = false);
      unawaited(_saveLguStatsCache());
    }

    final checkInUserIds = _checkIns
        .map((c) => c['userId']?.toString().trim())
        .whereType<String>()
        .where((id) => id.isNotEmpty)
        .toSet();

    await Future.wait<void>([
      () async {
        try {
          _tourists = _filterRealTourists(
            await _loadRegisteredTouristsForMunicipality(
              firestore: firestore,
              queryIds: queryIds,
              checkInUserIds: checkInUserIds,
            ),
          );
          _tourists = _filterRealTourists(
            _mergeTouristVisitsFromCheckIns(_tourists),
          );
        } catch (e) {
          debugPrint('Failed loading tourists for dashboard: $e');
          _tourists = [];
        }
      }(),
      if (usedCache)
        () async {
          try {
            final serverDocs = await _fetchQrCheckInDocs(
              firestore,
              queryIds,
              getOptions: const GetOptions(source: Source.server),
            );
            if (serverDocs.isNotEmpty && mounted) {
              _checkIns = _processCheckInDocs(serverDocs);
              _lastSeenCheckInId = _checkIns.isNotEmpty
                  ? (_checkIns.first['id'] as String?)
                  : null;
              _recomputeDashboardStats();
            }
          } catch (e) {
            debugPrint('[LguDashboard] server refresh qr_checkins: $e');
          }
        }(),
    ]);

    // Paint lists ASAP; hydrate missing profiles in background.
    _rebuildTouristProfileIndex();
    _applyTouristProfilesToCheckIns();
    _mergeVisitorsFromCheckIns();
    _recomputeDashboardStats();

    if (mounted) {
      setState(() => _isLoadingDetails = false);
      unawaited(_saveLguStatsCache());
      _scheduleDae3DraftRefresh();
    }

    unawaited(
      _finalizeCheckInAndTouristData().then((_) {
        if (!mounted) return;
        _recomputeDashboardStats();
        setState(() {});
        unawaited(_saveLguStatsCache());
      }).catchError((Object e) {
        debugPrint('[LguDashboard] background tourist hydrate: $e');
      }),
    );

    unawaited(
      _reloadVrToursFromDatabase().then((_) {
        if (!mounted) return;
        setState(() => _totalVRTours = _vrTours.length);
        unawaited(_saveLguStatsCache());
      }).catchError((Object e) {
        debugPrint('VR tours deferred load: $e');
      }),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_didInitializeSidebarForViewport) return;
    _didInitializeSidebarForViewport = true;
    // Start collapsed on phones so content is visible immediately.
    if (_isMobile) _isSidebarExpanded = false;
  }

  Future<void> _loadTourismSettings() async {
    final prefs = await SharedPreferences.getInstance();
    final email = await SessionStorage.getStoredEmail();
    if (!mounted) return;
    setState(() {
      _emailNotifications =
          prefs.getBool('tourism_email_notifications') ?? true;
      _pushNotifications = prefs.getBool('tourism_push_notifications') ?? true;
      _weeklyReports = prefs.getBool('tourism_weekly_reports') ?? false;
      _lastBackupDate = prefs.getString('tourism_last_backup_date');
      final savedName = prefs.getString('tourism_profile_name');
      if (savedName != null && savedName.isNotEmpty) {
        _profileName = savedName;
      } else {
        _profileName =
            _municipalityName != null && _municipalityName!.isNotEmpty
            ? _municipalityName!
            : 'LGU Office';
      }
      _profileEmail =
          prefs.getString('tourism_profile_email') ??
          email ??
          FirebaseAuth.instance.currentUser?.email?.trim() ??
          '';
      final photoStr = prefs.getString('tourism_profile_photo');
      if (photoStr != null && photoStr.isNotEmpty) {
        _profilePhotoBase64 = photoStr;
        try {
          _profilePhotoBytes = base64Decode(photoStr);
        } catch (_) {
          _profilePhotoBytes = null;
        }
      } else {
        _profilePhotoBase64 = null;
        _profilePhotoBytes = null;
      }
    });
  }

  Future<void> _saveTourismSettings() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('tourism_email_notifications', _emailNotifications);
    await prefs.setBool('tourism_push_notifications', _pushNotifications);
    await prefs.setBool('tourism_weekly_reports', _weeklyReports);
    await prefs.setString('tourism_profile_name', _profileName);
    await prefs.setString('tourism_profile_email', _profileEmail);
    if (_profilePhotoBase64 != null) {
      await prefs.setString('tourism_profile_photo', _profilePhotoBase64!);
    } else {
      await prefs.remove('tourism_profile_photo');
    }
  }

  void _subscribeToTouristSpots() {
    _touristSpotsSubscription?.cancel();
    _touristSpotsSubscription =
        TouristSpotsFirestoreService.streamTouristSpots().listen(
          (list) {
            if (!mounted) return;
            final filtered = _filterSpotsByMunicipality(
              list,
              _storedMunicipalityId,
            );
            setState(() {
              _allTouristSpots = list;
              _touristSpots = filtered;
              _activeSpots = _touristSpots
                  .where((s) => s.status == 'Active')
                  .length;
              if (_activeSpots == 0 && _touristSpots.isNotEmpty) {
                _activeSpots = _touristSpots.length;
              }
            });
          },
          onError: (Object e) {
            debugPrint('tourist_spots stream error: $e');
          },
        );
  }

  List<TouristSpot> _filterSpotsByMunicipality(
    List<TouristSpot> spots,
    String? municipalityId,
  ) {
    if (municipalityId == null || municipalityId.isEmpty) return spots;
    final queryIds = municipalityIdsForQuery(municipalityId);
    String? municipalityNameForFilter;
    for (final m in getMisamisOccidentalMunicipalities()) {
      if (m.id == municipalityId) {
        municipalityNameForFilter = m.name;
        break;
      }
    }
    final idsForFilter = queryIds.isNotEmpty
        ? queryIds
        : [normalizeMunicipalityId(municipalityId)];
    return spots.where((s) {
      final mid = normalizeMunicipalityId(
        s.municipalityId.isNotEmpty ? s.municipalityId : null,
      );
      final mName = s.municipality.toLowerCase();
      if (mid.isNotEmpty && idsForFilter.contains(mid)) return true;
      if (municipalityNameForFilter != null &&
          mName.contains(municipalityNameForFilter.toLowerCase()))
        return true;
      return false;
    }).toList();
  }

  @override
  void dispose() {
    _qrCheckInsSubscription?.cancel();
    _qrCheckInsLguSubscription?.cancel();
    _touristRegistrationsSubscription?.cancel();
    _touristSpotsSubscription?.cancel();
    _lguEventsSubscription?.cancel();
    _animationController.dispose();
    _checkInsSearchController.dispose();
    _spotsSearchController.dispose();
    _touristsSearchController.dispose();
    _dashboardSearchController.dispose();
    super.dispose();
  }

  bool get _isMobile => MediaQuery.of(context).size.width < 768;
  bool get _isTablet =>
      MediaQuery.of(context).size.width >= 768 &&
      MediaQuery.of(context).size.width < 1100;

  // When true, show banner that we're showing all data (no municipality filter)
  bool _showAllDataBanner = false;
  String?
  _municipalityName; // Display name for current filter (e.g. "Oroquieta City")

  Future<void> _loadData() async {
    final isRefresh = !_isBootstrapping;
    if (isRefresh) {
      setState(() => _isLoadingDetails = true);
    }
    setState(() => _errorMessage = null);
    _touristFirestoreReadsBlocked = false;

    try {
      if (Firebase.apps.isEmpty) {
        setState(() {
          _errorMessage = 'Firebase is not initialized yet.';
          _isBootstrapping = false;
          _isLoadingDetails = false;
        });
        return;
      }

      final authUser = FirebaseAuth.instance.currentUser;
      if (authUser == null) {
        setState(() {
          _errorMessage =
              'Your session expired. Please sign in again to load dashboard data.';
          _isBootstrapping = false;
          _isLoadingDetails = false;
        });
        return;
      }
      AuthConfig.currentUserUid = authUser.uid;

      // Token is attached by the Firestore SDK; don't block dashboard on refresh.
      unawaited(authUser.getIdToken());
      final authEmail =
          authUser.email?.trim() ?? (await SessionStorage.getStoredEmail()) ?? '';

      final firestore = FirebaseFirestore.instance;
      var municipalityId = await SessionStorage.getStoredMunicipalityId();
      if (municipalityId == null || municipalityId.isEmpty) {
        municipalityId = SessionStorage.getMunicipalityIdFromTourismEmail(
          authEmail,
        );
        if (municipalityId != null && municipalityId.isNotEmpty) {
          final uid = AuthConfig.currentUserUid;
          if (uid != null && uid.isNotEmpty) {
            await SessionStorage.saveSession(
              uid,
              role: UserRole.tourism,
              email: authEmail,
              municipalityId: municipalityId,
            );
          }
        }
      }
      if ((municipalityId == null || municipalityId.isEmpty) &&
          BetaTestingGuard.isActive) {
        municipalityId = BetaTestingGuard.dashboardMunicipalityId;
        final uid = authUser.uid;
        if (uid.isNotEmpty) {
          await SessionStorage.saveSession(
            uid,
            role: UserRole.tourism,
            email: authEmail,
            municipalityId: municipalityId,
          );
        }
      }

      final staffReady =
          await UserDirectoryService.prepareProvincialStaffFirestoreAccess(
        uid: authUser.uid,
        email: authEmail.isNotEmpty ? authEmail : SessionStorage.tourismEmail,
        roleRaw: 'tourism',
        fullName: _profileName,
        municipalityId: municipalityId,
      );
      if (!staffReady) {
        final isStaff = await UserDirectoryService.isCurrentUserProvincialStaff();
        debugPrint(
          '[LguDashboard] staff Firestore access not ready (email=$authEmail, isStaff=$isStaff) ? '
          'publish firestore.rules if queries fail.',
        );
        if (!isStaff && mounted) {
          setState(() {
            _errorMessage =
                'This account is not authorized for the LGU dashboard. '
                'Sign in with a tourism staff email (e.g. tourism.oroquieta@? or '
                'tourismoffice.atmos@misocc-demo.ph).';
            _isBootstrapping = false;
            _isLoadingDetails = false;
          });
          return;
        }
      }

      _storedMunicipalityId = municipalityId;
      _showAllDataBanner = municipalityId == null;
      String? munName;
      for (final m in getMisamisOccidentalMunicipalities()) {
        if (m.id == municipalityId) {
          munName = m.name;
          break;
        }
      }
      _municipalityName = munName ?? municipalityId;
      if (municipalityId != null && municipalityId.isNotEmpty) {
        _startLguEventsListener(municipalityId);
        unawaited(
          LguEventService().prefetchForLgu(municipalityId).catchError((Object e) {
            debugPrint('[LguDashboard] events prefetch: $e');
          }),
        );
      }
      _touristSpots = _filterSpotsByMunicipality(
        _allTouristSpots,
        _storedMunicipalityId,
      );
      _activeSpots = _touristSpots.where((s) => s.status == 'Active').length;
      if (_activeSpots == 0 && _touristSpots.isNotEmpty) {
        _activeSpots = _touristSpots.length;
      }

      if (!_didAutoBackfillSpotQr) {
        _didAutoBackfillSpotQr = true;
        unawaited(
          _runBackfillSpotQrMetadata(showSnack: false).catchError((Object e) {
            debugPrint('Spot QR metadata backfill skipped: $e');
          }),
        );
      }

      if (municipalityId != null) {
        final queryIds = municipalityIdsForQuery(municipalityId);
        if (queryIds.isNotEmpty) {
          try {
            await _loadMunicipalityCheckInsAndTourists(
              firestore: firestore,
              queryIds: queryIds,
            );
          } catch (e) {
            debugPrint('Failed loading qr_checkins for dashboard: $e');
            _checkIns = [];
            _lastSeenCheckInId = null;
            if (e.toString().contains('permission-denied') && mounted) {
              _errorMessage =
                  'Firestore rules are not published yet. Open FIRESTORE_RULES_DEPLOY.md '
                  'in the project folder, copy firestore.rules into Firebase Console -> Firestore -> Rules, '
                  'then Publish and restart the app.';
            }
            if (mounted) {
              setState(() {
                _isBootstrapping = false;
                _isLoadingDetails = false;
              });
            }
          }
        } else if (mounted) {
          setState(() {
            _isBootstrapping = false;
            _isLoadingDetails = false;
          });
        }
      } else {
        final fallbackIds = BetaTestingGuard.isActive
            ? municipalityIdsForQuery(BetaTestingGuard.dashboardMunicipalityId)
            : <String>[];
        _qrCheckInsSubscription?.cancel();
        _qrCheckInsLguSubscription?.cancel();
        _munCheckInsSnap = null;
        _lguCheckInsSnap = null;
        _touristRegistrationsSubscription?.cancel();
        _touristRegistrationsSubscription = null;
        _touristRegistrationStreamPrimed = false;
        _lastSeenCheckInId = null;
        if (fallbackIds.isNotEmpty) {
          try {
            await _loadMunicipalityCheckInsAndTourists(
              firestore: firestore,
              queryIds: fallbackIds,
            );
          } catch (e) {
            debugPrint('Failed loading qr_checkins (no municipality): $e');
            _checkIns = [];
            if (mounted) {
              setState(() {
                _isBootstrapping = false;
                _isLoadingDetails = false;
              });
            }
          }
        } else {
          _checkIns = [];
          _tourists = [];
          if (mounted) {
            setState(() {
              _isBootstrapping = false;
              _isLoadingDetails = false;
            });
          }
        }
      }

      _recomputeDashboardStats();
      _activeSpots = _touristSpots.where((s) => s.status == 'Active').length;
      if (_activeSpots == 0 && _touristSpots.isNotEmpty) {
        _activeSpots = _touristSpots.length;
      }

      if (mounted) {
        setState(() => _errorMessage = null);
        unawaited(_saveLguStatsCache());
      }
    } catch (e) {
      debugPrint('Error loading tourism dashboard data: $e');
      if (mounted) {
        setState(() {
          _errorMessage =
              'Could not load dashboard data. Pull to refresh or sign in again.';
          _isBootstrapping = false;
          _isLoadingDetails = false;
        });
      }
    } finally {
      if (mounted && _isBootstrapping) {
        setState(() {
          _isBootstrapping = false;
          _isLoadingDetails = false;
        });
      }
    }
  }

  /// Subscribes to qr_checkins (municipalityId + lguId) and updates _checkIns in real time.
  void _subscribeToCheckIns(List<String> queryIds) {
    _qrCheckInsSubscription?.cancel();
    _qrCheckInsLguSubscription?.cancel();
    _munCheckInsSnap = null;
    _lguCheckInsSnap = null;
    if (queryIds.isEmpty || Firebase.apps.isEmpty) return;

    void emitMerged() {
      final byId = <String, QueryDocumentSnapshot<Map<String, dynamic>>>{};
      for (final snap in [_munCheckInsSnap, _lguCheckInsSnap]) {
        if (snap == null) continue;
        for (final doc in snap.docs) {
          byId[doc.id] = doc;
        }
      }
      unawaited(_handleCheckInsDocs(byId.values.toList(), queryIds));
    }

    Query<Map<String, dynamic>> munBase = queryIds.length == 1
        ? FirebaseFirestore.instance
              .collection('qr_checkins')
              .where('municipalityId', isEqualTo: queryIds.first)
        : FirebaseFirestore.instance
              .collection('qr_checkins')
              .where('municipalityId', whereIn: queryIds);
    final munQuery = munBase
        .orderBy('timestamp', descending: true)
        .limit(_qrCheckInFetchLimit);
    _qrCheckInsSubscription = munQuery.snapshots().listen(
      (snapshot) {
        _munCheckInsSnap = snapshot;
        emitMerged();
      },
      onError: (Object e) {
        debugPrint('qr_checkins municipalityId stream error: $e');
        // Fallback without orderBy if composite index is missing.
        _qrCheckInsSubscription?.cancel();
        _qrCheckInsSubscription = munBase.limit(_qrCheckInFetchLimit).snapshots().listen(
          (snapshot) {
            _munCheckInsSnap = snapshot;
            emitMerged();
          },
          onError: (Object e2) {
            debugPrint('qr_checkins municipalityId stream fallback error: $e2');
          },
        );
      },
    );

    Query<Map<String, dynamic>> lguBase = queryIds.length == 1
        ? FirebaseFirestore.instance
              .collection('qr_checkins')
              .where('lguId', isEqualTo: queryIds.first)
        : FirebaseFirestore.instance
              .collection('qr_checkins')
              .where('lguId', whereIn: queryIds);
    final lguQuery = lguBase
        .orderBy('timestamp', descending: true)
        .limit(_qrCheckInFetchLimit);
    _qrCheckInsLguSubscription = lguQuery.snapshots().listen(
      (snapshot) {
        _lguCheckInsSnap = snapshot;
        emitMerged();
      },
      onError: (Object e) {
        debugPrint('qr_checkins lguId stream error: $e');
        _qrCheckInsLguSubscription?.cancel();
        _qrCheckInsLguSubscription = lguBase.limit(_qrCheckInFetchLimit).snapshots().listen(
          (snapshot) {
            _lguCheckInsSnap = snapshot;
            emitMerged();
          },
          onError: (Object e2) {
            debugPrint('qr_checkins lguId stream fallback error: $e2');
          },
        );
      },
    );
  }

  /// Loads recent qr_checkins matching [queryIds] via municipalityId and lguId (merged).
  Future<List<QueryDocumentSnapshot<Map<String, dynamic>>>> _fetchQrCheckInDocs(
    FirebaseFirestore firestore,
    List<String> queryIds, {
    GetOptions getOptions = const GetOptions(source: Source.server),
  }) async {
    final byId = <String, QueryDocumentSnapshot<Map<String, dynamic>>>{};

    Future<void> mergeQuery(String field) async {
      if (queryIds.isEmpty) return;
      final Query<Map<String, dynamic>> base = queryIds.length == 1
          ? firestore
                .collection('qr_checkins')
                .where(field, isEqualTo: queryIds.first)
          : firestore
                .collection('qr_checkins')
                .where(field, whereIn: queryIds);
      try {
        final snap = await base
            .orderBy('timestamp', descending: true)
            .limit(_qrCheckInFetchLimit)
            .get(getOptions);
        for (final doc in snap.docs) {
          byId[doc.id] = doc;
        }
      } catch (e) {
        debugPrint(
          '[LguDashboard] qr_checkins $field ordered query failed, '
          'falling back to limit-only: $e',
        );
        try {
          final snap =
              await base.limit(_qrCheckInFetchLimit).get(getOptions);
          for (final doc in snap.docs) {
            byId[doc.id] = doc;
          }
        } catch (e2) {
          debugPrint('[LguDashboard] qr_checkins $field query: $e2');
        }
      }
    }

    await Future.wait<void>([
      mergeQuery('municipalityId'),
      mergeQuery('lguId'),
    ]);
    return byId.values.toList();
  }

  Future<void> _handleCheckInsDocs(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
    List<String> queryIds,
  ) async {
    if (!mounted) return;
    final sorted = _sortCheckInsNewestFirst(
      _filterRealCheckIns(
        docs
            .map((d) => _normalizeCheckInForUi({'id': d.id, ...d.data()}))
            .toList(),
      ),
    );
    final checkIns =
        sorted.length > 100 ? sorted.take(100).toList(growable: false) : sorted;
    final previousFirstId = _lastSeenCheckInId;
    final newFirstId =
        checkIns.isNotEmpty ? checkIns.first['id']?.toString() : null;
    _lastSeenCheckInId = newFirstId;
    _checkIns = checkIns;

    final checkInUserIds = _checkIns
        .map((c) => c['userId']?.toString().trim())
        .whereType<String>()
        .where((id) => id.isNotEmpty)
        .toSet();
    try {
      _rebuildTouristProfileIndex();
      final missingIds = checkInUserIds
          .where((id) => !_touristProfileByUid.containsKey(id))
          .toSet();
      if (_tourists.isEmpty) {
        final registered = await _loadRegisteredTouristsForMunicipality(
          firestore: FirebaseFirestore.instance,
          queryIds: queryIds,
          checkInUserIds: checkInUserIds,
        );
        _tourists = _filterRealTourists(registered);
      } else if (missingIds.isNotEmpty) {
        final extra = await _fetchTouristDocsByIds(
          FirebaseFirestore.instance,
          missingIds,
          queryIds: queryIds,
          checkInUserIds: checkInUserIds,
        );
        if (extra.isNotEmpty) {
          _tourists = _filterRealTourists([..._tourists, ...extra]);
        }
      }
    } catch (e) {
      debugPrint('Tourism: reload tourists on check-in stream: $e');
    }

    await _finalizeCheckInAndTouristData();
    _recomputeDashboardStats();

    if (previousFirstId != null &&
        newFirstId != null &&
        newFirstId != previousFirstId) {
      var newCount = 0;
      for (final c in checkIns) {
        final id = c['id']?.toString();
        if (id == previousFirstId) break;
        if (_isDummyCheckIn(c)) continue;
        newCount++;
        final spotLabel = c['location']?.toString().trim().isNotEmpty == true
            ? c['location'].toString()
            : (c['spotId']?.toString() ?? 'spot').replaceAll('_', ' ');
        _pushNotification({
          'title': 'New check-in',
          'message':
              '${_displayTouristIdFromCheckIn(c)} scanned $spotLabel',
          'time': 'Just now',
        });
      }
      if (newCount > 0 && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              newCount == 1
                  ? 'New QR visit recorded in your municipality!'
                  : '$newCount new QR visits in your municipality!',
            ),
            backgroundColor: _primaryOrange,
            behavior: SnackBarBehavior.floating,
          ),
        );
        _scheduleDae3DraftRefresh(newestCheckInId: newFirstId);
      }
    }
    if (mounted) setState(() {});
  }

  void _scheduleDae3DraftRefresh({String? newestCheckInId}) {
    final mid = _storedMunicipalityId;
    if (mid == null || mid.isEmpty) return;
    final scopeName = (_municipalityName ?? mid).trim();
    final scopeLabel = scopeName.toLowerCase().contains('misamis occidental')
        ? scopeName
        : '$scopeName, Misamis Occidental';
    final slug = normalizeMunicipalityId(mid);
    Dae3AutoReportService.instance.scheduleRefresh(
      municipalityId: mid,
      scopeLabel: scopeLabel,
      scopeSlug: slug.isEmpty ? 'lgu' : slug,
      localCheckIns: _realCheckIns,
      tourists: _tourists,
      newestCheckInId: newestCheckInId ?? _lastSeenCheckInId,
      parseTimestamp: _parseCheckInTimestamp,
    );
  }

  /// Subscribes to new tourist registrations for this LGU and refreshes the list.
  void _subscribeToTouristRegistrations(List<String> queryIds) {
    _touristRegistrationsSubscription?.cancel();
    _touristRegistrationStreamPrimed = false;
    if (queryIds.isEmpty || Firebase.apps.isEmpty || _touristFirestoreReadsBlocked) {
      return;
    }

    final Query<Map<String, dynamic>> q = queryIds.length == 1
        ? FirebaseFirestore.instance
              .collection('tourists')
              .where('registrationMunicipalityId', isEqualTo: queryIds.first)
        : FirebaseFirestore.instance
              .collection('tourists')
              .where('registrationMunicipalityId', whereIn: queryIds);

    _touristRegistrationsSubscription = q.limit(250).snapshots().listen(
      (snapshot) {
        if (!mounted) return;
        // Ignore initial snapshot so existing records won't flood notifications.
        if (!_touristRegistrationStreamPrimed) {
          _touristRegistrationStreamPrimed = true;
          return;
        }

        final added = snapshot.docChanges
            .where((c) => c.type == DocumentChangeType.added)
            .toList();
        for (final change in added) {
          final data = change.doc.data() ?? <String, dynamic>{};
          final firstName = (data['firstName'] ?? '').toString().trim();
          final lastName = (data['lastName'] ?? '').toString().trim();
          final fullName = '$firstName $lastName'.trim();
          _pushNotification({
            'title': 'New registration',
            'message': fullName.isNotEmpty
                ? '$fullName registered'
                : 'A new tourist registered',
            'time': 'Just now',
          });
        }

        if (added.isNotEmpty && mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                added.length == 1
                    ? '1 new tourist registration'
                    : '${added.length} new tourist registrations',
              ),
              backgroundColor: _primaryOrange,
              behavior: SnackBarBehavior.floating,
            ),
          );
        }

        // Keep Registered Tourists list in sync (same source as governor, LGU-scoped).
        unawaited(_reloadMunicipalityRegisteredTourists(queryIds));
      },
      onError: (Object e) {
        if (_isFirestorePermissionDenied(e)) {
          _onTouristFirestorePermissionDenied(e);
          return;
        }
        debugPrint('Tourism: tourist registrations stream: $e');
      },
    );
  }

  /// Reloads municipality-scoped registered tourists (registration + check-in visitors).
  Future<void> _reloadMunicipalityRegisteredTourists(
    List<String> queryIds,
  ) async {
    if (!mounted ||
        queryIds.isEmpty ||
        Firebase.apps.isEmpty ||
        _touristFirestoreReadsBlocked) {
      return;
    }
    final checkInUserIds = _checkIns
        .map(
          (c) =>
              c['userId']?.toString().trim() ??
              c['tourist_id']?.toString().trim(),
        )
        .whereType<String>()
        .where((id) => id.isNotEmpty)
        .toSet();
    try {
      final registered = await _loadRegisteredTouristsForMunicipality(
        firestore: FirebaseFirestore.instance,
        queryIds: queryIds,
        checkInUserIds: checkInUserIds,
      );
      if (!mounted) return;
      setState(() {
        _tourists = _filterRealTourists(
          _mergeTouristVisitsFromCheckIns(registered),
        );
        _totalTourists = _tourists.length;
      });
      _recomputeDashboardStats();
      unawaited(_saveLguStatsCache());
    } catch (e) {
      debugPrint('Tourism: reload registered tourists: $e');
    }
  }

  bool _isFirestorePermissionDenied(Object e) {
    return e.toString().contains('permission-denied');
  }

  void _onTouristFirestorePermissionDenied([Object? cause]) {
    if (_touristFirestoreReadsBlocked) return;
    _touristFirestoreReadsBlocked = true;
    _touristRegistrationsSubscription?.cancel();
    _touristRegistrationsSubscription = null;
    debugPrint(
      '[LguDashboard] tourists/ reads blocked (${cause ?? 'permission-denied'}) - '
      'using qr_checkins only. Publish firestore.rules (see FIRESTORE_RULES_DEPLOY.md).',
    );
    if (mounted && _errorMessage == null) {
      _errorMessage =
          'Firestore rules need updating. Open FIRESTORE_RULES_DEPLOY.md, '
          'copy firestore.rules into Firebase Console -> Firestore -> Rules, '
          'Publish, then sign out and sign in again.';
    }
  }

  void _pushNotification(Map<String, String> item) {
    _notifications.insert(0, item);
    _unreadNotifications++;
  }

  String _crossLguEventSeenKey(String eventId) => eventId;

  int get _eventsNavBadgeCount {
    final myMun = (_storedMunicipalityId ?? '').trim();
    if (myMun.isEmpty) return 0;
    var n = 0;
    for (final e in _lguEvents) {
      if (!LguEventService.isVisibleToTourists(e)) continue;
      if (LguEventService.matchesMunicipality(e, myMun)) continue;
      final id = e['id']?.toString() ?? '';
      if (id.isEmpty) continue;
      if (!_seenCrossLguEventIds.contains(_crossLguEventSeenKey(id))) {
        n++;
      }
    }
    return n > 99 ? 99 : n;
  }

  Future<void> _loadSeenCrossLguEventIds(String municipalityId) async {
    final prefs = await SharedPreferences.getInstance();
    final mun = municipalityId.trim().toLowerCase();
    final key = 'lgu_cross_events_seen_$mun';
    final seededKey = 'lgu_cross_events_seeded_$mun';
    final stored = prefs.getStringList(key) ?? [];
    _seenCrossLguEventIds
      ..clear()
      ..addAll(stored);
    if (!(prefs.getBool(seededKey) ?? false)) {
      // First run: don't badge historical province events.
      for (final e in _lguEvents) {
        if (!LguEventService.isVisibleToTourists(e)) continue;
        if (LguEventService.matchesMunicipality(e, municipalityId)) continue;
        final id = e['id']?.toString() ?? '';
        if (id.isNotEmpty) {
          _seenCrossLguEventIds.add(_crossLguEventSeenKey(id));
        }
      }
      await prefs.setBool(seededKey, true);
      await prefs.setStringList(key, _seenCrossLguEventIds.toList());
    }
  }

  Future<void> _persistSeenCrossLguEventIds() async {
    final mun = (_storedMunicipalityId ?? '').trim().toLowerCase();
    if (mun.isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(
      'lgu_cross_events_seen_$mun',
      _seenCrossLguEventIds.toList(),
    );
  }

  Future<void> _markAllEventDecisionsSeen() async {
    final myMun = (_storedMunicipalityId ?? '').trim();
    for (final e in _lguEvents) {
      if (!LguEventService.isVisibleToTourists(e)) continue;
      if (myMun.isNotEmpty &&
          LguEventService.matchesMunicipality(e, myMun)) {
        continue;
      }
      final id = e['id']?.toString() ?? '';
      if (id.isNotEmpty) {
        _seenCrossLguEventIds.add(_crossLguEventSeenKey(id));
      }
    }
    await _persistSeenCrossLguEventIds();
    if (mounted) setState(() {});
  }

  void _startLguEventsListener(String municipalityId) {
    if (Firebase.apps.isEmpty || municipalityId.trim().isEmpty) return;
    _lguEventsSubscription?.cancel();
    _lguEventsStreamPrimed = false;
    _knownPublishedEventIds = {};

    _lguEventsSubscription = FirebaseFirestore.instance
        .collection(LguEventService.collection)
        .snapshots()
        .listen(
      (snapshot) async {
        if (!mounted) return;
        final list = snapshot.docs
            .map((d) => <String, dynamic>{'id': d.id, ...d.data()})
            .toList();

        final previousPublished = Set<String>.from(_knownPublishedEventIds);
        final wasPrimed = _lguEventsStreamPrimed;

        final publishedIds = <String>{
          for (final e in list)
            if (LguEventService.isVisibleToTourists(e) &&
                (e['id']?.toString() ?? '').isNotEmpty)
              e['id'].toString(),
        };

        setState(() {
          _lguEvents = list;
          _knownPublishedEventIds = publishedIds;
        });

        if (!wasPrimed) {
          _lguEventsStreamPrimed = true;
          await _loadSeenCrossLguEventIds(municipalityId);
          if (mounted) setState(() {});
          return;
        }

        final newlyPublishedFromOthers = <Map<String, dynamic>>[];
        for (final e in list) {
          if (!LguEventService.isVisibleToTourists(e)) continue;
          if (LguEventService.matchesMunicipality(e, municipalityId)) continue;
          final id = e['id']?.toString() ?? '';
          if (id.isEmpty) continue;
          if (previousPublished.contains(id)) continue;
          newlyPublishedFromOthers.add(e);
        }

        if (newlyPublishedFromOthers.isEmpty) return;

        if (mounted) setState(() {});

        final first = newlyPublishedFromOthers.first;
        final from = LguEventService.sourceMunicipalityLabel(first);
        final title = first['title']?.toString().trim() ?? 'event';
        final count = newlyPublishedFromOthers.length;
        final message = count == 1
            ? '$from published "$title"'
            : '$count new events from other LGUs';

        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(message),
            backgroundColor: _primaryOrange,
            behavior: SnackBarBehavior.floating,
            action: SnackBarAction(
              label: 'View',
              textColor: Colors.white,
              onPressed: () {
                if (!mounted) return;
                setState(() {
                  _selectedIndex = _eventsIndex;
                  _eventsPanelTab = 0;
                });
              },
            ),
          ),
        );
      },
      onError: (Object e) {
        debugPrint('[LguDashboard] events stream: $e');
      },
    );
  }

  String _formatTime(dynamic timestamp) {
    DateTime date;
    if (timestamp is Timestamp) {
      date = timestamp.toDate();
    } else if (timestamp is DateTime) {
      date = timestamp;
    } else {
      return 'Unknown';
    }

    final now = DateTime.now();
    final diff = now.difference(date);

    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes} min ago';
    if (diff.inHours < 24) return '${diff.inHours} hours ago';
    return '${diff.inDays} days ago';
  }

  /// Separate date / time (Governor portal parity).
  String _formatRegisteredDateOnlyDisplay(DateTime? dt) {
    if (dt == null) return '?';
    return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';
  }

  String _formatRegisteredTimeOnlyDisplay(DateTime? dt) {
    if (dt == null) return '?';
    final h24 = dt.hour;
    final min = dt.minute.toString().padLeft(2, '0');
    final sec = dt.second.toString().padLeft(2, '0');
    final period = h24 >= 12 ? 'PM' : 'AM';
    final h12 = h24 == 0 ? 12 : (h24 > 12 ? h24 - 12 : h24);
    return '$h12:$min:$sec $period';
  }

  /// Parse [timestamp] from a `qr_checkins` or legacy check-in map.
  DateTime? _parseCheckInTimestamp(Map<String, dynamic> c) {
    final ts = c['timestamp'] ?? c['createdAt'] ?? c['checkin_time'];
    if (ts is Timestamp) return ts.toDate();
    if (ts is DateTime) return ts;
    return null;
  }

  bool _isDummyCheckIn(Map<String, dynamic> row) =>
      ProductionDataFilters.isDummyCheckIn(row);

  bool _isDummyTourist(Map<String, dynamic> row) =>
      ProductionDataFilters.isDummyTourist(row);

  List<Map<String, dynamic>> _filterRealCheckIns(
    List<Map<String, dynamic>> rows,
  ) => ProductionDataFilters.realCheckIns(
        rows,
        collapseRedundant: true,
      );

  List<Map<String, dynamic>> _filterRealTourists(
    List<Map<String, dynamic>> rows,
  ) => ProductionDataFilters.realTourists(rows);

  List<Map<String, dynamic>> get _realCheckIns =>
      _filterRealCheckIns(_checkIns);

  List<Map<String, dynamic>> get _realTouristsList =>
      _filterRealTourists(_tourists);

  List<Map<String, dynamic>> _sortCheckInsNewestFirst(
    List<Map<String, dynamic>> rows,
  ) {
    final sorted = List<Map<String, dynamic>>.from(rows);
    sorted.sort((a, b) {
      final ta = _parseCheckInTimestamp(a);
      final tb = _parseCheckInTimestamp(b);
      if (ta == null && tb == null) return 0;
      if (ta == null) return 1;
      if (tb == null) return -1;
      return tb.compareTo(ta);
    });
    return sorted;
  }

  /// Normalizes both `qr_checkins` and legacy `check_ins` docs to a common UI shape.
  Map<String, dynamic> _normalizeCheckInForUi(Map<String, dynamic> row) {
    final touristNameRaw = row['touristName']?.toString().trim() ?? '';
    final userIdRaw =
        row['userId']?.toString().trim() ??
        row['tourist_id']?.toString().trim() ??
        '';
    final spotNameRaw = row['spot_name']?.toString().trim() ??
        row['spotName']?.toString().trim() ??
        '';
    final locationRaw = row['location']?.toString().trim() ?? '';
    final spotIdRaw =
        row['touristSpotId']?.toString().trim() ??
        row['spotId']?.toString().trim() ??
        row['spot_id']?.toString().trim() ??
        '';
    final lguIdRaw =
        row['lguId']?.toString().trim() ??
        row['municipalityId']?.toString().trim() ??
        '';
    final statusRaw = row['status']?.toString().trim() ?? '';

    final touristName = touristNameRaw.isNotEmpty
        ? touristNameRaw
        : (userIdRaw.isNotEmpty
              ? 'User ${userIdRaw.length > 8 ? userIdRaw.substring(0, 8) : userIdRaw}'
              : 'Tourist');
    final location = locationRaw.isNotEmpty
        ? locationRaw
        : (spotNameRaw.isNotEmpty
              ? spotNameRaw
              : (spotIdRaw.isNotEmpty
                    ? spotIdRaw.replaceAll('_', ' ')
                    : 'Unknown location'));

    final normalizedStatus = statusRaw.isNotEmpty
        ? (statusRaw.toLowerCase() == 'verified'
            ? 'Verified'
            : statusRaw[0].toUpperCase() + statusRaw.substring(1))
        : 'Verified';

    return <String, dynamic>{
      ...row,
      'touristName': touristName,
      'touristId': row['touristId']?.toString() ?? '',
      'location': location,
      'spotId': spotIdRaw,
      'touristSpotId': spotIdRaw,
      'lguId': lguIdRaw,
      'municipalityId': lguIdRaw.isNotEmpty
          ? lguIdRaw
          : row['municipalityId']?.toString(),
      'status': normalizedStatus,
      'touristEmail':
          row['touristEmail']?.toString() ?? row['email']?.toString() ?? '',
    };
  }

  void _rebuildTouristProfileIndex() {
    _touristProfileByUid.clear();
    for (final t in _tourists) {
      final uid =
          t['firebaseUid']?.toString().trim() ?? t['id']?.toString().trim() ?? '';
      if (uid.isNotEmpty) {
        _touristProfileByUid[uid] = t;
      }
    }
  }

  Future<void> _hydrateMissingTouristProfilesForCheckIns() async {
    if (Firebase.apps.isEmpty || _checkIns.isEmpty || _touristFirestoreReadsBlocked) {
      return;
    }
    final missing = <String>{};
    for (final c in _checkIns) {
      final uid =
          c['userId']?.toString().trim() ??
          c['tourist_id']?.toString().trim() ??
          '';
      if (uid.isNotEmpty && !_touristProfileByUid.containsKey(uid)) {
        missing.add(uid);
      }
    }
    if (missing.isEmpty) return;

    final checkInUserIds = _checkIns
        .map(
          (c) =>
              c['userId']?.toString().trim() ??
              c['tourist_id']?.toString().trim() ??
              '',
        )
        .where((id) => id.isNotEmpty)
        .toSet();
    final queryIds = municipalityIdsForQuery(_storedMunicipalityId);
    final extraTourists = await _fetchTouristDocsByIds(
      FirebaseFirestore.instance,
      missing,
      queryIds: queryIds,
      checkInUserIds: checkInUserIds,
    );
    if (extraTourists.isNotEmpty) {
      for (final row in extraTourists) {
        final uid = row['id']?.toString().trim() ?? '';
        if (uid.isNotEmpty) _touristProfileByUid[uid] = row;
      }
      _tourists = _mergeTouristVisitsFromCheckIns([
        ..._tourists,
        ...extraTourists,
      ]);
      _totalTourists = _tourists.length;
    }
  }

  /// Batched `tourists` doc reads (avoids sequential N+1 gets).
  Future<List<Map<String, dynamic>>> _fetchTouristDocsByIds(
    FirebaseFirestore firestore,
    Set<String> uids, {
    required List<String> queryIds,
    required Set<String> checkInUserIds,
  }) async {
    if (uids.isEmpty || _touristFirestoreReadsBlocked) return const [];
    final out = <Map<String, dynamic>>[];
    final idList = uids.toList(growable: false);
    for (var i = 0; i < idList.length; i += _touristDocIdChunkSize) {
      final end = math.min(i + _touristDocIdChunkSize, idList.length);
      final chunk = idList.sublist(i, end);
      try {
        final snap = await firestore
            .collection('tourists')
            .where(FieldPath.documentId, whereIn: chunk)
            .get()
            .timeout(const Duration(seconds: 12));
        for (final doc in snap.docs) {
          if (!doc.exists || doc.data().isEmpty) continue;
          final row = <String, dynamic>{'id': doc.id, ...doc.data()};
          if (ProductionDataFilters.isDummyTourist(row)) continue;
          if (RegistrationMunicipalityResolver.touristMatchesMunicipality(
            tourist: row,
            queryIds: queryIds,
            checkInUserIds: checkInUserIds,
          )) {
            out.add(row);
          }
        }
      } catch (e) {
        if (_isFirestorePermissionDenied(e)) {
          _onTouristFirestorePermissionDenied(e);
          break;
        }
        // Fallback: per-doc gets for this chunk if whereIn is unsupported.
        for (final uid in chunk) {
          try {
            final doc = await firestore
                .collection('tourists')
                .doc(uid)
                .get()
                .timeout(const Duration(seconds: 12));
            if (!doc.exists || doc.data() == null) continue;
            final row = <String, dynamic>{'id': doc.id, ...doc.data()!};
            if (ProductionDataFilters.isDummyTourist(row)) continue;
            if (RegistrationMunicipalityResolver.touristMatchesMunicipality(
              tourist: row,
              queryIds: queryIds,
              checkInUserIds: checkInUserIds,
            )) {
              out.add(row);
            }
          } catch (e2) {
            if (_isFirestorePermissionDenied(e2)) {
              _onTouristFirestorePermissionDenied(e2);
              return out;
            }
          }
        }
      }
      if (_touristFirestoreReadsBlocked) break;
    }
    return out;
  }

  Map<String, dynamic> _enrichCheckInWithTouristProfile(
    Map<String, dynamic> c,
  ) {
    final uid =
        c['userId']?.toString().trim() ??
        c['tourist_id']?.toString().trim() ??
        '';
    if (uid.isEmpty) return c;
    final profile = _touristProfileByUid[uid];
    if (profile == null) {
      final name = c['touristName']?.toString().trim() ??
          c['fullName']?.toString().trim() ??
          '';
      final email = c['touristEmail']?.toString().trim() ?? '';
      if (name.isEmpty && email.isEmpty) return c;
      return <String, dynamic>{
        ...c,
        if (name.isNotEmpty) 'touristName': name,
        if (email.isNotEmpty) 'touristEmail': email,
        // Never show raw Firebase UID in Tourist ID column.
        'touristId': TouristIdHelper.displayForTourist(c),
      };
    }
    final name = _getTouristDisplayName(profile);
    return <String, dynamic>{
      ...c,
      'touristName': name,
      'touristId': TouristIdHelper.displayForTourist(profile),
      'touristProfile': profile,
      'profilePhotoUrl': profile['profilePhotoUrl'],
      'profileImageBase64': profile['profileImageBase64'],
      'touristEmail': profile['email']?.toString() ?? '',
      'touristOrigin': _getTouristOrigin(profile),
    };
  }

  void _applyTouristProfilesToCheckIns() {
    if (_checkIns.isEmpty) return;
    _checkIns =
        _checkIns.map(_enrichCheckInWithTouristProfile).toList(growable: false);
    _recentActivity =
        _checkIns.take(5).map(_recentActivityFromCheckIn).toList();
  }

  Future<void> _finalizeCheckInAndTouristData() async {
    _rebuildTouristProfileIndex();
    await _hydrateMissingTouristProfilesForCheckIns();
    _rebuildTouristProfileIndex();
    _applyTouristProfilesToCheckIns();
    _mergeVisitorsFromCheckIns();
  }

  /// Builds visitor rows from real QR check-ins (works even when tourists/ reads are denied).
  void _mergeVisitorsFromCheckIns() {
    final byUid = <String, Map<String, dynamic>>{};
    for (final t in _filterRealTourists(_tourists)) {
      final uid =
          (t['firebaseUid'] ?? t['id'] ?? '').toString().trim();
      if (uid.isNotEmpty) byUid[uid] = t;
    }
    for (final c in _filterRealCheckIns(_checkIns)) {
      final uid =
          (c['userId'] ?? c['tourist_id'] ?? '').toString().trim();
      if (uid.isEmpty || byUid.containsKey(uid)) continue;
      final name = c['touristName']?.toString().trim() ?? '';
      final email = c['touristEmail']?.toString().trim() ?? '';
      byUid[uid] = <String, dynamic>{
        'id': uid,
        'firebaseUid': uid,
        'fullName': name.isNotEmpty ? name : 'Visitor',
        'name': name.isNotEmpty ? name : 'Visitor',
        'email': email,
        'status': 'Active',
        'fromQrCheckIn': true,
      };
    }
    _tourists = _mergeTouristVisitsFromCheckIns(byUid.values.toList());
    _totalTourists = _tourists.length;
  }

  void _recomputeDashboardStats() {
    final today = DateTime.now();
    _todayCheckIns = sumCheckInVisitors(
      _filterRealCheckIns(_checkIns).where((c) {
        final d = _parseCheckInTimestamp(c);
        if (d == null) return false;
        return d.year == today.year &&
            d.month == today.month &&
            d.day == today.day;
      }),
    );
    _mergeVisitorsFromCheckIns();
    _recentActivity = _filterRealCheckIns(_checkIns)
        .take(5)
        .map(_recentActivityFromCheckIn)
        .toList();
  }

  Widget _buildVisitPrivacyAvatar({double radius = 18}) {
    return CircleAvatar(
      radius: radius,
      backgroundColor: _primaryOrange.withValues(alpha: 0.12),
      child: Icon(
        Icons.person_outline_rounded,
        color: _primaryOrange,
        size: radius * 1.1,
      ),
    );
  }

  Widget _buildVisitTouristIdChip(String id, {double? maxWidth}) {
    final text = id.trim().isEmpty ? 'â€”' : id;
    final chip = Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: _primaryOrange.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: _primaryOrange.withValues(alpha: 0.22)),
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

  /// Privacy-safe display ID for a visit row (never name / email / Firebase UID).
  String _displayTouristIdFromCheckIn(Map<String, dynamic> c) {
    final profile = c['touristProfile'];
    if (profile is Map<String, dynamic>) {
      final fromProfile = TouristIdHelper.displayForTourist(profile);
      if (fromProfile.isNotEmpty && !fromProfile.endsWith('PENDING')) {
        return fromProfile;
      }
    }
    final stored = c['touristId']?.toString().trim() ?? '';
    if (TouristIdHelper.isFormattedTouristId(stored)) return stored;
    if (stored.startsWith('ATMOS-') && stored.length > 6) return stored;
    if (TouristIdHelper.looksLikeFirebaseUid(stored) || stored.isEmpty) {
      return TouristIdHelper.displayForTourist({
        'touristId': '',
        'province': c['touristOrigin']?.toString() ??
            c['province']?.toString() ??
            '',
      });
    }
    return stored;
  }

  Widget _buildCheckInProfileAvatar(
    Map<String, dynamic> c, {
    double radius = 20,
  }) {
    // Tourist Visits: privacy avatar only (same as Governor â€” no photo / initials).
    return _buildVisitPrivacyAvatar(radius: radius);
  }

  Widget _buildCheckInTouristCell(Map<String, dynamic> c) {
    final id = _displayTouristIdFromCheckIn(c);
    return Row(
      children: [
        _buildVisitPrivacyAvatar(radius: 18),
        const SizedBox(width: 10),
        Expanded(child: _buildVisitTouristIdChip(id, maxWidth: 220)),
      ],
    );
  }

  Map<String, dynamic> _recentActivityFromCheckIn(Map<String, dynamic> c) {
    final location = c['location']?.toString().trim();
    final spotLabel = (location != null && location.isNotEmpty)
        ? location
        : (c['spotId']?.toString() ?? '').replaceAll('_', ' ');
    final id = _displayTouristIdFromCheckIn(c);
    return <String, dynamic>{
      'icon': Icons.qr_code_scanner_rounded,
      'color': _primaryOrange,
      'title': id,
      'description':
          'Checked in at ${spotLabel.isNotEmpty ? spotLabel : 'Unknown spot'}',
      'time': _formatTime(c['timestamp']),
    };
  }

  /// Derives per-tourist visit counts from currently loaded `_checkIns`.
  /// This keeps "Visits" in the tourists table aligned with QR check-ins.
  List<Map<String, dynamic>> _mergeTouristVisitsFromCheckIns(
    List<Map<String, dynamic>> tourists,
  ) {
    if (tourists.isEmpty) return tourists;

    final Map<String, int> visitsByUid = <String, int>{};
    for (final c in _realCheckIns) {
      final uid =
          (c['userId']?.toString().trim() ??
                  c['tourist_id']?.toString().trim() ??
                  '')
              .trim();
      if (uid.isEmpty) continue;
      visitsByUid[uid] = (visitsByUid[uid] ?? 0) + 1;
    }

    return tourists.map((t) {
      final uid =
          (t['firebaseUid']?.toString().trim() ??
                  t['id']?.toString().trim() ??
                  '')
              .trim();
      final visits = uid.isNotEmpty ? (visitsByUid[uid] ?? 0) : 0;
      return <String, dynamic>{...t, 'visits': visits, 'totalVisits': visits};
    }).toList();
  }

  /// Display label for analytics "top spots" (name over raw spot id).
  String _analyticsSpotLabel(Map<String, dynamic> c) {
    final spotName = c['spot_name']?.toString().trim();
    if (spotName != null && spotName.isNotEmpty) return spotName;
    final loc = c['location']?.toString().trim();
    if (loc != null && loc.isNotEmpty) return loc;
    final spotId =
        c['spotId']?.toString().trim() ?? c['spot_id']?.toString().trim() ?? '';
    if (spotId.isNotEmpty) {
      for (final s in _touristSpots) {
        if (s.id == spotId) return s.name.isNotEmpty ? s.name : spotId;
      }
      return spotId.replaceAll('_', ' ');
    }
    return 'Unknown spot';
  }

  int get _lguAnalyticsDailyAvg {
    if (_realCheckIns.isEmpty) return 0;
    final dates = <DateTime>{};
    for (final c in _realCheckIns) {
      final d = _parseCheckInTimestamp(c);
      if (d != null) dates.add(DateTime(d.year, d.month, d.day));
    }
    if (dates.isEmpty) return 0;
    final min = dates.reduce((a, b) => a.isBefore(b) ? a : b);
    final max = dates.reduce((a, b) => a.isAfter(b) ? a : b);
    final days = max.difference(min).inDays + 1;
    return days > 0 ? (_realCheckIns.length / days).round() : _realCheckIns.length;
  }

  String get _lguAnalyticsPeakHour {
    final byHour = <int, int>{};
    for (final c in _realCheckIns) {
      final d = _parseCheckInTimestamp(c);
      if (d != null) {
        final h = d.hour;
        byHour[h] = (byHour[h] ?? 0) + 1;
      }
    }
    if (byHour.isEmpty) return '?';
    final top = byHour.entries.reduce((a, b) => a.value >= b.value ? a : b);
    final h = top.key;
    final end = (h + 1) % 24;
    final am2 = end < 12 ? 'AM' : 'PM';
    final s = h == 0 ? 12 : (h > 12 ? h - 12 : h);
    final e = end == 0 ? 12 : (end > 12 ? end - 12 : end);
    return '$s-$e $am2';
  }

  String get _lguAnalyticsTopOrigin {
    final counts = <String, int>{};
    for (final t in _realTouristsList) {
      final o = _getTouristOrigin(t).trim();
      if (o.isNotEmpty && o != '?') {
        counts[o] = (counts[o] ?? 0) + 1;
      } else {
        final one = t['nationality']?.toString().trim();
        if (one != null && one.isNotEmpty) {
          counts[one] = (counts[one] ?? 0) + 1;
        }
      }
    }
    if (counts.isEmpty) return '?';
    final top = counts.entries.reduce((a, b) => a.value >= b.value ? a : b).key;
    return _compactOriginForAnalyticsCard(top);
  }

  /// Short label for analytics cards (avoids overflow on long addresses).
  String _compactOriginForAnalyticsCard(String origin) {
    final trimmed = origin.trim();
    if (trimmed.isEmpty || trimmed == '?') return '?';
    final parts = trimmed
        .split(',')
        .map((p) => p.trim())
        .where((p) => p.isNotEmpty)
        .toList();
    if (parts.isEmpty) return trimmed;
    if (parts.length == 1) return parts.first;
    if (parts.length == 2) return '${parts[0]}\n${parts[1]}';
    return '${parts[0]}\n${parts[1]}';
  }

  List<double> get _lguAnalyticsTrendValues {
    const days = 14;
    final counts = List.filled(days, 0.0);
    final today = DateTime.now();
    for (final c in _realCheckIns) {
      final d = _parseCheckInTimestamp(c);
      if (d != null) {
        final diff = today.difference(DateTime(d.year, d.month, d.day)).inDays;
        if (diff >= 0 && diff < days) counts[days - 1 - diff] += 1;
      }
    }
    return counts;
  }

  List<Map<String, dynamic>> get _lguAnalyticsTopSpots {
    final byLabel = <String, int>{};
    for (final c in _realCheckIns) {
      final label = _analyticsSpotLabel(c);
      if (label.isNotEmpty) {
        byLabel[label] = (byLabel[label] ?? 0) + 1;
      }
    }
    return byLabel.entries
        .map((e) => {'name': e.key, 'visits': e.value})
        .toList()
      ..sort((a, b) => (b['visits'] as int).compareTo(a['visits'] as int));
  }

  void _toggleSidebar() {
    setState(() => _isSidebarExpanded = !_isSidebarExpanded);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _darkBg,
      body: _isMobile
          ? _buildMobileBody()
          : Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (_isSidebarExpanded) _buildSidebar(),
                // Cream underlay — header orange still joins the sidebar; never flash
                // a full-viewport solid orange behind tab content.
                Expanded(
                  child: ColoredBox(
                    color: _darkBg,
                    child: _buildMainContent(),
                  ),
                ),
              ],
            ),
      bottomNavigationBar: _isMobile ? _buildMobileBottomNav() : null,
    );
  }

  Widget _buildMobileBottomNav() {
    const tabIndices = [0, 1, 2, 5];
    final selected = tabIndices.contains(_selectedIndex)
        ? tabIndices.indexOf(_selectedIndex)
        : 0;

    return NavigationBar(
      height: 64,
      backgroundColor: Colors.white,
      indicatorColor: _primaryOrange.withValues(alpha: 0.14),
      selectedIndex: selected,
      onDestinationSelected: (navIndex) {
        if (navIndex == 4) {
          setState(() => _isSidebarExpanded = true);
          return;
        }
        setState(() {
          _selectedIndex = tabIndices[navIndex];
          _isSidebarExpanded = false;
        });
      },
      destinations: const [
        NavigationDestination(
          icon: Icon(Icons.dashboard_outlined),
          selectedIcon: Icon(Icons.dashboard_rounded),
          label: 'Home',
        ),
        NavigationDestination(
          icon: Icon(Icons.qr_code_scanner_outlined),
          selectedIcon: Icon(Icons.qr_code_scanner_rounded),
          label: 'Visits',
        ),
        NavigationDestination(
          icon: Icon(Icons.place_outlined),
          selectedIcon: Icon(Icons.place_rounded),
          label: 'Spots',
        ),
        NavigationDestination(
          icon: Icon(Icons.analytics_outlined),
          selectedIcon: Icon(Icons.analytics_rounded),
          label: 'Stats',
        ),
        NavigationDestination(
          icon: Icon(Icons.apps_outlined),
          selectedIcon: Icon(Icons.apps_rounded),
          label: 'More',
        ),
      ],
    );
  }

  Widget _buildMobileBody() {
    final screenW = MediaQuery.of(context).size.width;
    final drawerWidth = (screenW * 0.8).clamp(240.0, 300.0);
    final bottomInset = MediaQuery.paddingOf(context).bottom;

    return ColoredBox(
      color: _darkBg,
      child: Stack(
      children: [
        Positioned.fill(child: _buildMainContent()),
        if (_isSidebarExpanded)
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: _toggleSidebar,
              child: Container(color: Colors.black.withOpacity(0.28)),
            ),
          ),
        AnimatedPositioned(
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOutCubic,
          left: _isSidebarExpanded ? 0 : -drawerWidth,
          top: 0,
          bottom: 0,
          width: drawerWidth,
          child: Material(
            color: Colors.transparent,
            elevation: 12,
            child: Container(
              decoration: _sidebarGradientDecoration(),
              child: SafeArea(
                top: false,
                bottom: false,
                child: Column(
                  children: [
                    _buildSidebarProfileStrip(showCollapseButton: true),
                    _buildSidebarNavScroll(expanded: true),
                    const SizedBox(height: 12),
                    _buildLogoutButton(expanded: true),
                    SizedBox(height: 16 + bottomInset),
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

  BoxDecoration _sidebarGradientDecoration() {
    return BoxDecoration(
      gradient: _lguBrandGradient,
      boxShadow: [
        BoxShadow(
          color: _primaryOrange.withValues(alpha: 0.18),
          blurRadius: 18,
          offset: const Offset(2, 0),
        ),
      ],
    );
  }

  Widget _buildSidebar() {
    final expanded = _isSidebarExpanded;
    final bottomInset = MediaQuery.paddingOf(context).bottom;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 250),
      width: expanded ? 272 : 84,
      decoration: _sidebarGradientDecoration(),
      child: Column(
        children: [
          if (expanded)
            _buildSidebarProfileStrip(showCollapseButton: true)
          else
            _buildSidebarCollapsedToggle(),
          _buildSidebarNavScroll(expanded: expanded),
          const SizedBox(height: 12),
          _buildLogoutButton(expanded: expanded),
          SizedBox(height: 16 + bottomInset),
        ],
      ),
    );
  }

  Widget _buildSidebarCollapsedToggle() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [_buildSidebarToggleButton(expanded: false)],
      ),
    );
  }

  Widget _buildSidebarToggleButton({required bool expanded}) {
    return Tooltip(
      message: expanded ? 'Collapse sidebar' : 'Expand sidebar',
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: _toggleSidebar,
          borderRadius: BorderRadius.circular(14),
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: Icon(
              expanded ? Icons.close_rounded : Icons.menu_rounded,
              color: Colors.white,
              size: 20,
            ),
          ),
        ),
      ),
    );
  }

  /// Profile row â€” logo, office name, and optional collapse control on one line.
  Widget _buildSidebarProfileStrip({bool showCollapseButton = false}) {
    final city = _municipalityName?.trim() ?? '';
    final rawName = _profileName.trim();
    final displayName = rawName.isNotEmpty
        ? rawName
        : (city.isNotEmpty ? city : 'LGU Office');
    // Avoid repeating the city/name in the subtitle when they match.
    final String subtitle;
    if (city.isNotEmpty &&
        displayName.toLowerCase() != city.toLowerCase()) {
      subtitle = city;
    } else if (city.isNotEmpty) {
      subtitle = 'LGU Tourism Office';
    } else {
      subtitle = 'Misamis Occidental';
    }

    return Padding(
      padding: EdgeInsets.fromLTRB(16, _isMobile ? 10 : 14, 8, _isMobile ? 2 : 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          _buildSidebarBrandLogo(size: _isMobile ? 36 : 40),
          SizedBox(width: _isMobile ? 8 : 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  displayName,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: _isMobile ? 13 : 14,
                    fontWeight: FontWeight.w700,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                SizedBox(height: _isMobile ? 1 : 2),
                Text(
                  subtitle,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.82),
                    fontSize: _isMobile ? 10 : 11,
                    fontWeight: FontWeight.w500,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          if (showCollapseButton) ...[
            SizedBox(width: _isMobile ? 4 : 6),
            _buildSidebarToggleButton(expanded: true),
          ],
        ],
      ),
    );
  }

  Future<void> _reloadVrToursFromDatabase() async {
    _vrTours = await VrTourFirestoreService.loadForTourism(
      municipalityId: _storedMunicipalityId,
      spots: _touristSpots,
    );
    _totalVRTours = _vrTours.length;
  }

  /// Registered visitors + check-in profiles for this LGU (no full-collection scan).
  /// Loads real Firestore `tourists` by registrationMunicipalityId, city name, and check-in UIDs.
  Future<List<Map<String, dynamic>>> _loadRegisteredTouristsForMunicipality({
    required FirebaseFirestore firestore,
    required List<String> queryIds,
    required Set<String> checkInUserIds,
  }) async {
    final byId = <String, Map<String, dynamic>>{};
    if (_touristFirestoreReadsBlocked) return byId.values.toList();

    void mergeDoc(QueryDocumentSnapshot<Map<String, dynamic>> doc) {
      final row = <String, dynamic>{'id': doc.id, ...doc.data()};
      if (ProductionDataFilters.isDummyTourist(row)) return;
      if (!RegistrationMunicipalityResolver.touristMatchesMunicipality(
        tourist: row,
        queryIds: queryIds,
        checkInUserIds: checkInUserIds,
      )) {
        return;
      }
      byId[doc.id] = row;
    }

    final queryFutures = <Future<void>>[];
    for (final mid in queryIds) {
      queryFutures.add(() async {
        try {
          final snap = await firestore
              .collection('tourists')
              .where('registrationMunicipalityId', isEqualTo: mid)
              .limit(250)
              .get()
              .timeout(const Duration(seconds: 20));
          for (final doc in snap.docs) {
            mergeDoc(doc);
          }
        } catch (e) {
          if (_isFirestorePermissionDenied(e)) {
            _onTouristFirestorePermissionDenied(e);
            return;
          }
          debugPrint('Tourism: tourists registrationMunicipalityId=$mid: $e');
        }
      }());

      // Real registrations often store city ("Oroquieta City") without registrationMunicipalityId.
      for (final cityName in municipalityCityNamesForQuery(mid)) {
        queryFutures.add(() async {
          try {
            final snap = await firestore
                .collection('tourists')
                .where('city', isEqualTo: cityName)
                .limit(250)
                .get()
                .timeout(const Duration(seconds: 20));
            for (final doc in snap.docs) {
              mergeDoc(doc);
            }
          } catch (e) {
            if (_isFirestorePermissionDenied(e)) {
              _onTouristFirestorePermissionDenied(e);
              return;
            }
            debugPrint('Tourism: tourists city=$cityName: $e');
          }
        }());
      }
    }
    await Future.wait(queryFutures);

    if (_touristFirestoreReadsBlocked) return byId.values.toList();

    final missingUids =
        checkInUserIds.where((uid) => !byId.containsKey(uid)).toSet();
    if (missingUids.isNotEmpty) {
      final extra = await _fetchTouristDocsByIds(
        firestore,
        missingUids,
        queryIds: queryIds,
        checkInUserIds: checkInUserIds,
      );
      for (final row in extra) {
        final id = row['id']?.toString() ?? '';
        if (id.isNotEmpty) byId[id] = row;
      }
    }

    return byId.values.toList();
  }

  /// Sidebar + drawer: scrollable nav including Settings at the bottom.
  Widget _buildSidebarNavScroll({required bool expanded}) {
    return Expanded(
      child: SingleChildScrollView(
        padding: EdgeInsets.only(
          top: _isMobile ? 10 : 20,
          bottom: 4,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (int i = 0; i < _mainNavCount; i++)
                    _buildTourismNavItem(
                      index: i,
                      expanded: expanded,
                      bottomMargin: i == 0
                          ? (_isMobile ? 8 : 14)
                          : (_isMobile ? 4 : 6),
                    ),
                  SizedBox(height: _isMobile ? 2 : 4),
                  _buildTourismNavItem(
                    index: _eventsIndex,
                    expanded: expanded,
                  ),
                  SizedBox(height: _isMobile ? 4 : 6),
                  _buildTourismNavItem(
                    index: _settingsIndex,
                    expanded: expanded,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTourismNavItem({
    required int index,
    required bool expanded,
    double bottomMargin = 8,
  }) {
    final item = _navItems[index];
    final isSelected = _selectedIndex == index;
    final iconSize = _isMobile ? 22.0 : 24.0;
    final labelSize = _isMobile ? 13.0 : 14.0;
    final horizontalPadding = _isMobile
        ? (expanded ? 12.0 : 10.0)
        : (expanded ? 14.0 : 12.0);
    final verticalPadding = _isMobile
        ? (expanded ? 11.0 : 12.0)
        : (expanded ? 13.0 : 14.0);
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOutCubic,
      margin: EdgeInsets.only(bottom: bottomMargin),
      child: Tooltip(
        message: expanded ? '' : item.label,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: () {
              setState(() => _selectedIndex = index);
              if (_isMobile && _isSidebarExpanded) {
                _toggleSidebar();
              }
            },
            borderRadius: BorderRadius.circular(16),
            hoverColor: Colors.white.withValues(alpha: 0.12),
            splashColor: Colors.white.withValues(alpha: 0.16),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              curve: Curves.easeOutCubic,
              padding: EdgeInsets.symmetric(
                horizontal: horizontalPadding,
                vertical: verticalPadding,
              ),
              constraints: const BoxConstraints(minHeight: 48),
              decoration: BoxDecoration(
                color: isSelected
                    ? Colors.white.withValues(alpha: 0.92)
                    : Colors.white.withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: isSelected
                      ? Colors.white.withValues(alpha: 0.95)
                      : Colors.white.withValues(alpha: 0.14),
                ),
                boxShadow: isSelected
                    ? [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.14),
                          blurRadius: 14,
                          offset: const Offset(0, 6),
                        ),
                      ]
                    : null,
              ),
              child: Row(
                mainAxisAlignment: expanded
                    ? MainAxisAlignment.start
                    : MainAxisAlignment.center,
                children: [
                  Icon(
                    item.icon,
                    color: isSelected
                        ? _primaryOrange
                        : Colors.white.withValues(alpha: 0.88),
                    size: iconSize,
                  ),
                  if (expanded) ...[
                    const SizedBox(width: 14),
                    Expanded(
                      child: Text(
                        item.label,
                        style: GoogleFonts.poppins(
                          color: isSelected
                              ? _primaryOrange
                              : Colors.white.withValues(alpha: 0.94),
                          fontSize: labelSize,
                          fontWeight: isSelected
                              ? FontWeight.w600
                              : FontWeight.w500,
                        ),
                        overflow: TextOverflow.ellipsis,
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

  Future<void> _logout() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Log out?'),
        content: const Text('Are you sure you want to log out?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Log out'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    UserDirectoryService.clearStaffAccessCache();
    await SessionStorage.clearSession();
    AuthConfig.currentUserUid = null;
    try {
      await FirebaseAuth.instance.signOut();
    } catch (_) {}
    if (!mounted) return;
    navigateAfterLogout(context);
  }

  Widget _buildLogoutButton({required bool expanded}) {
    return Padding(
      padding: EdgeInsets.fromLTRB(expanded ? 16 : 10, 0, expanded ? 16 : 10, 4),
      child: Tooltip(
        message: expanded ? '' : 'Logout',
        child: Material(
          color: Colors.transparent,
          elevation: 10,
          shadowColor: Colors.black.withValues(alpha: 0.28),
          borderRadius: BorderRadius.circular(18),
          child: InkWell(
            onTap: _logout,
            borderRadius: BorderRadius.circular(18),
            child: Ink(
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    Color(0xFFFFF7ED),
                    Color(0xFFFFEDD5),
                    Color(0xFFFDBA74),
                  ],
                ),
                borderRadius: BorderRadius.circular(18),
                border: Border.all(
                  color: Colors.white.withValues(alpha: 0.7),
                ),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFFEA580C).withValues(alpha: 0.28),
                    blurRadius: 16,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: Padding(
                padding: EdgeInsets.symmetric(
                  horizontal: expanded ? 16 : 12,
                  vertical: expanded ? 14 : 12,
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.logout_rounded,
                      size: expanded ? 20 : 22,
                      color: const Color(0xFFC2410C),
                    ),
                    if (expanded) ...[
                      const SizedBox(width: 10),
                      Text(
                        'Logout',
                        style: GoogleFonts.poppins(
                          color: const Color(0xFF9A3412),
                          fontWeight: FontWeight.w700,
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildMainContent() {
    if (_errorMessage != null) {
      return ColoredBox(
        color: _darkBg,
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.error_outline, color: Colors.redAccent, size: 48),
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
        ),
      );
    }

    if (_isBootstrapping && !_hasCachedStats) {
      return ColoredBox(
        color: _darkBg,
        child: DashboardContentSkeleton(accent: _primaryOrange),
      );
    }

    // Keep visited tabs alive so Visits ↔ Spots ↔ Events switches instantly
    // without tearing down state or re-fetching on every tap.
    return IndexedStack(
      index: _selectedIndex.clamp(0, _navItems.length - 1),
      sizing: StackFit.expand,
      children: [
        for (var i = 0; i < _navItems.length; i++)
          _LguLazyKeepAliveTab(
            active: _selectedIndex == i,
            builder: () => _buildTabPage(i),
          ),
      ],
    );
  }

  Widget _buildTabPage(int index) {
    return switch (index) {
      0 => _buildDashboardContent(),
      1 => _buildCheckInsContent(),
      2 => _buildTouristSpotsContent(),
      _spotQRCodesIndex => _buildSpotQRCodesContent(),
      4 => _buildTouristsContent(),
      _analyticsIndex => _buildAnalyticsContent(),
      _eventsIndex => _buildEventsContent(),
      _settingsIndex => _buildSettingsContent(),
      _ => _buildDashboardContent(),
    };
  }

  Widget _buildFramedContentShell({
    required String title,
    String? subtitle,
    List<Widget>? actions,
    bool showAddSpotButton = false,
    Widget? preBody,
    required Widget body,
    Decoration? bodyDecoration,
    List<BoxShadow>? frameShadow,
  }) {
    final mergedActions = <Widget>[
      if (actions != null) ...actions,
      if (_isMobile) ...[
        if (actions != null && actions.isNotEmpty) const SizedBox(width: 8),
        _buildMobileHeaderProfileAction(onColoredHeader: true),
      ],
    ];

    const frameMargin = EdgeInsets.zero;
    final frameRadius = BorderRadius.only(
      bottomLeft: Radius.circular(_isMobile ? 12 : 14),
      bottomRight: Radius.circular(_isMobile ? 12 : 14),
    );

    return SizedBox(
      width: double.infinity,
      height: double.infinity,
      child: Container(
      margin: frameMargin,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: frameRadius,
        border: Border(
          right: BorderSide(color: _panelBorder),
          bottom: BorderSide(color: _panelBorder),
        ),
        boxShadow:
            frameShadow ??
            [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.06),
                blurRadius: 16,
                offset: const Offset(0, 6),
              ),
            ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          _buildHeader(
            title,
            subtitle: subtitle,
            actions: mergedActions.isEmpty ? null : mergedActions,
            showAddSpotButton: showAddSpotButton,
          ),
          if (preBody != null) preBody,
          Expanded(
            child: Container(
              decoration:
                  bodyDecoration ?? const BoxDecoration(color: _surfaceBg),
              child: body,
            ),
          ),
        ],
      ),
      ),
    );
  }

  // ==================== DASHBOARD SECTION ====================
  Widget _buildDashboardContent() {
    final cityLabel = _dashboardCityDisplayName;

    return ColoredBox(
      color: _darkBg,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildPremiumDashboardTopBar(cityLabel: cityLabel),
          Expanded(
            child: RefreshIndicator(
              onRefresh: _loadData,
              color: _primaryOrange,
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: EdgeInsets.fromLTRB(
                  _isMobile ? 16 : 24,
                  16,
                  _isMobile ? 16 : 24,
                  32,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (_showAllDataBanner) ...[
                      _buildDashboardAllDataBanner(),
                      const SizedBox(height: 16),
                    ],
                    _buildDashboardHeroBanner(cityLabel: cityLabel),
                    const SizedBox(height: 20),
                    _buildQuickStats(),
                    const SizedBox(height: 24),
                    LayoutBuilder(
                      builder: (context, constraints) {
                        final showRightRail = constraints.maxWidth >= 1100;
                        final touristsBlock =
                            (_isLoadingDetails && _tourists.isEmpty)
                            ? const ShimmerScope(
                                child: SkeletonListTiles(count: 3),
                              )
                            : DashboardFadeIn(
                                child: _buildDashboardRecentTourists(),
                              );

                        if (!showRightRail) {
                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              touristsBlock,
                              const SizedBox(height: 24),
                              _buildDashboardRightRail(),
                              const SizedBox(height: 24),
                              _buildSpotQRCodesDashboardCard(),
                              const SizedBox(height: 24),
                              if (_isLoadingDetails &&
                                  _recentActivity.isEmpty)
                                const ShimmerScope(
                                  child: SkeletonListTiles(count: 3),
                                )
                              else
                                DashboardFadeIn(
                                  child: _buildRecentActivity(),
                                ),
                            ],
                          );
                        }

                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(flex: 7, child: touristsBlock),
                                const SizedBox(width: 24),
                                Expanded(
                                  flex: 3,
                                  child: _buildDashboardRightRail(),
                                ),
                              ],
                            ),
                            const SizedBox(height: 24),
                            _buildSpotQRCodesDashboardCard(),
                            const SizedBox(height: 24),
                            if (_isLoadingDetails && _recentActivity.isEmpty)
                              const ShimmerScope(
                                child: SkeletonListTiles(count: 3),
                              )
                            else
                              DashboardFadeIn(child: _buildRecentActivity()),
                          ],
                        );
                      },
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDashboardAllDataBanner() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: _tintOrange,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _primaryOrange.withValues(alpha: 0.25)),
      ),
      child: Row(
        children: [
          Icon(Icons.info_outline, color: _primaryOrange, size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Showing all data. Use a municipality-specific account (e.g. tourism.oroquieta@misocc.gov.ph) to see only your municipality\'s check-ins and spots.',
              style: GoogleFonts.inter(fontSize: 13, color: _textDark),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPremiumDashboardTopBar({required String cityLabel}) {
    final notifBadge = _unreadNotifications + _eventsNavBadgeCount;
    const onHeader = Colors.white;
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: _isMobile ? 14 : 20,
        vertical: _isMobile ? 12 : 14,
      ),
      decoration: BoxDecoration(
        gradient: _lguBrandGradient,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.12),
            blurRadius: 14,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          if (!_isSidebarExpanded && !_isMobile)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: IconButton(
                onPressed: _toggleSidebar,
                icon: const Icon(Icons.menu_rounded, color: onHeader),
                tooltip: 'Open sidebar',
              ),
            ),
          if (_isMobile)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: IconButton(
                onPressed: _toggleSidebar,
                icon: const Icon(Icons.menu_rounded, color: onHeader),
                tooltip: 'Menu',
              ),
            ),
          Expanded(
            flex: _isMobile ? 3 : 2,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Dashboard',
                  style: GoogleFonts.inter(
                    color: onHeader,
                    fontSize: _isMobile ? 18 : 21,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.2,
                    height: 1.1,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '$cityLabel â€” live registrations, visits, and spots',
                  style: GoogleFonts.inter(
                    color: onHeader.withValues(alpha: 0.9),
                    fontSize: _isMobile ? 11.5 : 13,
                    fontWeight: FontWeight.w500,
                    height: 1.3,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          if (!_isMobile) ...[
            const SizedBox(width: 16),
            Expanded(
              flex: 3,
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.95),
                  borderRadius: BorderRadius.circular(999),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.08),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: TextField(
                  controller: _dashboardSearchController,
                  onSubmitted: (q) {
                    final query = q.trim();
                    if (query.isEmpty) return;
                    _touristsSearchController.text = query;
                    setState(() => _selectedIndex = 4);
                  },
                  style: GoogleFonts.inter(fontSize: 14, color: _textDark),
                  decoration: InputDecoration(
                    hintText: 'Search tourists, spots, or reports...',
                    hintStyle: GoogleFonts.inter(
                      color: _textMuted,
                      fontSize: 13,
                    ),
                    prefixIcon: const Icon(
                      Icons.search_rounded,
                      color: _textMuted,
                      size: 22,
                    ),
                    filled: true,
                    fillColor: Colors.white,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 14,
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(999),
                      borderSide: BorderSide.none,
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(999),
                      borderSide: BorderSide.none,
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(999),
                      borderSide: const BorderSide(
                        color: Colors.white,
                        width: 1.5,
                      ),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            _buildHeaderAction(
              Icons.notifications_outlined,
              badge: notifBadge > 0 ? '$notifBadge' : null,
              onTap: _showNotificationsDialog,
              onColoredHeader: true,
            ),
            const SizedBox(width: 10),
            _buildDesktopHeaderProfileMenu(onColoredHeader: true),
          ] else ...[
            _buildHeaderAction(
              Icons.notifications_outlined,
              badge: notifBadge > 0 ? '$notifBadge' : null,
              onTap: _showNotificationsDialog,
              onColoredHeader: true,
            ),
            const SizedBox(width: 4),
            _buildMobileHeaderProfileAction(onColoredHeader: true),
          ],
        ],
      ),
    );
  }

  Widget _buildDashboardHeroBanner({required String cityLabel}) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(24),
      child: SizedBox(
        height: _isMobile ? 176 : 196,
        child: DecoratedBox(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
              colors: [
                Color(0xFFFFF3E8),
                Color(0xFFFFE7D1),
                Color(0xFFFFF8F3),
              ],
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                flex: _isMobile ? 5 : 6,
                child: Padding(
                  padding: EdgeInsets.fromLTRB(
                    _isMobile ? 18 : 28,
                    _isMobile ? 18 : 24,
                    12,
                    _isMobile ? 18 : 24,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        'GOOD DAY, LGU OFFICE!',
                        style: GoogleFonts.inter(
                          color: const Color(0xFFEA580C),
                          fontSize: _isMobile ? 12 : 13,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.8,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text.rich(
                        TextSpan(
                          children: [
                            TextSpan(
                              text:
                                  'Together for a Smarter, More Vibrant $cityLabel ',
                              style: GoogleFonts.poppins(
                                color: _textDark,
                                fontSize: _isMobile ? 17 : 22,
                                fontWeight: FontWeight.w700,
                                height: 1.25,
                              ),
                            ),
                            TextSpan(
                              text: 'ðŸ§¡',
                              style: TextStyle(
                                fontSize: _isMobile ? 17 : 20,
                              ),
                            ),
                          ],
                        ),
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 10),
                      Text(
                        'Track. Manage. Promote. A better tourism experience for everyone.',
                        style: GoogleFonts.inter(
                          color: _textMuted,
                          fontSize: 13,
                          height: 1.4,
                          fontWeight: FontWeight.w400,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              ),
              if (!_isMobile)
                Expanded(
                  flex: 5,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      Image.network(
                        SupabaseStorageConfig.resolve(_dashboardHeroImageAsset),
                        fit: BoxFit.cover,
                        alignment: Alignment.center,
                        errorBuilder: (_, __, ___) =>
                            Container(color: _tintOrange),
                      ),
                      DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.centerLeft,
                            end: Alignment.centerRight,
                            colors: [
                              const Color(0xFFFFE7D1),
                              const Color(0xFFFFE7D1).withValues(alpha: 0.55),
                              Colors.transparent,
                            ],
                            stops: const [0.0, 0.22, 0.55],
                          ),
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

  Widget _buildDashboardRightRail() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: _tourismPanelDecoration(),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(
                    Icons.bolt_rounded,
                    color: _primaryOrange,
                    size: 20,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Quick Actions',
                    style: GoogleFonts.poppins(
                      color: _textDark,
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              GridView.count(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                crossAxisCount: 2,
                mainAxisSpacing: 8,
                crossAxisSpacing: 8,
                childAspectRatio: 1.55,
                children: [
                  _buildQuickActionGridTile(
                    icon: Icons.qr_code_2_rounded,
                    label: 'Generate QR Code',
                    onTap: () => setState(() {
                      _selectedIndex = _spotQRCodesIndex;
                      if (_isMobile) _isSidebarExpanded = false;
                    }),
                  ),
                  _buildQuickActionGridTile(
                    icon: Icons.add_location_alt_rounded,
                    label: 'Add Tourist Spot',
                    onTap: _showAddSpotDialog,
                  ),
                  _buildQuickActionGridTile(
                    icon: Icons.analytics_outlined,
                    label: 'View Analytics',
                    onTap: () => setState(() {
                      _selectedIndex = _analyticsIndex;
                      if (_isMobile) _isSidebarExpanded = false;
                    }),
                  ),
                  _buildQuickActionGridTile(
                    icon: Icons.description_outlined,
                    label: 'Create Report',
                    onTap: () => setState(() {
                      _selectedIndex = _analyticsIndex;
                      if (_isMobile) _isSidebarExpanded = false;
                    }),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildQuickActionGridTile({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Ink(
          decoration: BoxDecoration(
            color: _tintOrange,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: _primaryOrange.withValues(alpha: 0.22),
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, color: _primaryOrange, size: 18),
                const SizedBox(height: 4),
                Text(
                  label,
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.inter(
                    color: const Color(0xFF9A3412),
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    height: 1.15,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  List<Map<String, dynamic>> _dashboardRecentRegisteredTourists({
    int limit = 5,
  }) {
    final sorted = _sortedTouristsByRegistrationDate(
      _filterRealTourists(_tourists),
    );
    if (sorted.length <= limit) return sorted;
    return sorted.take(limit).toList(growable: false);
  }

  Widget _buildDashboardRecentTourists() {
    final recent = _dashboardRecentRegisteredTourists();
    final munLabel =
        (_municipalityName ?? _storedMunicipalityId ?? 'this LGU').trim();

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 12),
      decoration: _tourismPanelDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Registered tourists',
                      style: GoogleFonts.inter(
                        color: _textDark,
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Newest sign-ups â€” names hidden for data privacy',
                      style: GoogleFonts.inter(
                        color: _textMuted,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
              TextButton(
                onPressed: () => setState(() {
                  _selectedIndex = 4;
                  if (_isMobile) _isSidebarExpanded = false;
                }),
                style: TextButton.styleFrom(
                  foregroundColor: Colors.white,
                  backgroundColor: _primaryOrange,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 10,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
                child: Text(
                  'View all â†’',
                  style: GoogleFonts.inter(
                    fontWeight: FontWeight.w700,
                    fontSize: 12,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (recent.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 24),
              child: Text(
                'No registered tourists for $munLabel yet. '
                'New sign-ups via your municipality QR appear here.',
                style: GoogleFonts.inter(
                  color: _textMuted,
                  fontSize: 14,
                  height: 1.4,
                ),
              ),
            )
          else if (_isMobile)
            ...List.generate(recent.length, (index) {
              final t = recent[index];
              return _buildDashboardTouristMobileRow(t, index == 0);
            })
          else
            _buildDashboardTouristsTable(recent),
        ],
      ),
    );
  }

  Widget _buildDashboardTouristsTable(List<Map<String, dynamic>> recent) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 0, 8, 10),
          child: Row(
            children: [
              const SizedBox(width: 44),
              Expanded(flex: 3, child: _tableHeader('Tourist ID')),
              Expanded(flex: 2, child: _tableHeader('Registration Date')),
              const SizedBox(width: 44),
            ],
          ),
        ),
        ...List.generate(recent.length, (index) {
          final t = recent[index];
          final id = TouristIdHelper.displayForTourist(t);
          final regDt = _registeredDateTimeNullableFromTourist(t);

          return Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: () => _showTouristDetailsDialog(t),
                borderRadius: BorderRadius.circular(16),
                hoverColor: _tintOrange.withValues(alpha: 0.55),
                child: Ink(
                  decoration: BoxDecoration(
                    color:
                        index.isEven ? const Color(0xFFFAFAFA) : Colors.white,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 10,
                    ),
                    child: Row(
                      children: [
                        _buildVisitPrivacyAvatar(radius: 18),
                        const SizedBox(width: 8),
                        Expanded(
                          flex: 3,
                          child: _buildVisitTouristIdChip(id, maxWidth: 260),
                        ),
                        Expanded(
                          flex: 2,
                          child: Text(
                            _formatRegisteredDateOnlyDisplay(regDt),
                            style: GoogleFonts.inter(
                              color: _textMuted,
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                        SizedBox(
                          width: 44,
                          child: IconButton(
                            tooltip: 'View',
                            onPressed: () => _showTouristDetailsDialog(t),
                            icon: Container(
                              width: 32,
                              height: 32,
                              decoration: const BoxDecoration(
                                color: _tintOrange,
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(
                                Icons.visibility_rounded,
                                color: _primaryOrange,
                                size: 18,
                              ),
                            ),
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
      ],
    );
  }

  Widget _tableHeader(String label) {
    return Text(
      label,
      style: GoogleFonts.inter(
        color: _textMuted,
        fontSize: 12,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.2,
      ),
    );
  }

  Widget _buildDashboardTouristMobileRow(
    Map<String, dynamic> t,
    bool isFirst,
  ) {
    final id = TouristIdHelper.displayForTourist(t);
    final regDt = _registeredDateTimeNullableFromTourist(t);

    return Padding(
      padding: EdgeInsets.only(top: isFirst ? 0 : 8),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => _showTouristDetailsDialog(t),
          borderRadius: BorderRadius.circular(16),
          child: Ink(
            decoration: BoxDecoration(
              color: _surfaceBg,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: _panelBorder.withValues(alpha: 0.7)),
            ),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  _buildVisitPrivacyAvatar(radius: 20),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildVisitTouristIdChip(id, maxWidth: 220),
                        const SizedBox(height: 4),
                        Text(
                          _formatRegisteredDateOnlyDisplay(regDt),
                          style: GoogleFonts.inter(
                            color: _textMuted,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: () => _showTouristDetailsDialog(t),
                    icon: const Icon(
                      Icons.visibility_rounded,
                      color: _primaryOrange,
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

  // Greeting helper kept for possible future header use.
  // ignore: unused_element
  String _timeBasedGreeting() {
    final h = DateTime.now().hour;
    if (h < 12) return 'Good morning';
    if (h < 17) return 'Good afternoon';
    return 'Good evening';
  }

  Widget _buildDashboardSectionLabel({
    required String title,
    required String subtitle,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: GoogleFonts.poppins(
            color: _textDark,
            fontSize: 24,
            fontWeight: FontWeight.w600,
            letterSpacing: -0.2,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          subtitle,
          style: GoogleFonts.inter(
            color: _textMuted,
            fontSize: _isMobile ? 12 : 14,
            fontWeight: FontWeight.w400,
          ),
        ),
      ],
    );
  }

  Widget _buildHeader(
    String title, {
    String? subtitle,
    List<Widget>? actions,
    bool showAddSpotButton = false,
  }) {
    const onHeader = Colors.white;

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: _isMobile ? 14 : 20,
        vertical: _isMobile ? 12 : 14,
      ),
      decoration: BoxDecoration(
        gradient: _lguBrandGradient,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.12),
            blurRadius: 14,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          if (!_isSidebarExpanded && !_isMobile)
            IconButton(
              onPressed: _toggleSidebar,
              icon: Icon(Icons.menu, color: onHeader),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
            ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    color: onHeader,
                    fontSize: _isMobile ? 18 : 21,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.2,
                  ),
                ),
                if (subtitle != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      subtitle,
                      style: TextStyle(
                        color: onHeader.withValues(alpha: 0.9),
                        fontSize: _isMobile ? 11.5 : 13,
                        fontWeight: FontWeight.w500,
                        height: 1.3,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          if (actions != null) ...actions,
          if (_isMobile) ...[
            _buildHeaderAction(
              Icons.notifications_outlined,
              badge: (_unreadNotifications + _eventsNavBadgeCount) > 0
                  ? '${_unreadNotifications + _eventsNavBadgeCount}'
                  : null,
              onTap: _showNotificationsDialog,
              onColoredHeader: true,
            ),
          ] else if (_selectedIndex == 0) ...[
            _buildHeaderAction(
              Icons.notifications_outlined,
              badge: (_unreadNotifications + _eventsNavBadgeCount) > 0
                  ? '${_unreadNotifications + _eventsNavBadgeCount}'
                  : null,
              onTap: _showNotificationsDialog,
              onColoredHeader: true,
            ),
            if (showAddSpotButton) ...[
              const SizedBox(width: 8),
              TextButton.icon(
                onPressed: _showAddSpotDialog,
                icon: const Icon(Icons.add, size: 18),
                label: const Text('Add Spot'),
                style: TextButton.styleFrom(
                  foregroundColor: _primaryOrange,
                  backgroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 10,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(24),
                  ),
                ),
              ),
            ],
            const SizedBox(width: 8),
            _buildDesktopHeaderProfileMenu(onColoredHeader: true),
          ],
          if (_isMobile && showAddSpotButton)
            IconButton(
              tooltip: 'Add tourist spot',
              onPressed: _showAddSpotDialog,
              icon: Icon(Icons.add_circle_outline, color: onHeader, size: 26),
            ),
        ],
      ),
    );
  }

  Widget _buildDesktopHeaderProfileMenu({bool onColoredHeader = false}) {
    final fg = onColoredHeader ? Colors.white : _textDark;
    final bg = onColoredHeader
        ? Colors.white.withValues(alpha: 0.16)
        : const Color(0xFFF3F4F6);

    return PopupMenuButton<String>(
      tooltip: 'Account',
      onSelected: _handleProfileMenuSelection,
      itemBuilder: (context) => _buildProfileMenuItems(),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(18),
          border: onColoredHeader
              ? Border.all(color: Colors.white.withValues(alpha: 0.35))
              : null,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildHeaderProfileAvatar(size: 30),
            const SizedBox(width: 8),
            Text(
              _profileName.isNotEmpty ? _profileName : 'Tourism',
              style: TextStyle(
                color: fg,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(width: 6),
            Icon(
              Icons.keyboard_arrow_down_rounded,
              color: fg,
              size: 18,
            ),
          ],
        ),
      ),
    );
  }

  List<PopupMenuEntry<String>> _buildProfileMenuItems() {
    return const [
      PopupMenuItem<String>(
        value: 'logout',
        child: ListTile(
          contentPadding: EdgeInsets.zero,
          leading: Icon(Icons.logout_rounded, color: Colors.redAccent),
          title: Text('Logout'),
        ),
      ),
    ];
  }

  void _handleProfileMenuSelection(String value) {
    if (value == 'logout') {
      _logout();
    }
  }

  void _openSettings() {
    setState(() => _selectedIndex = _settingsIndex);
  }

  Widget _buildMobileHeaderProfileAction({bool onColoredHeader = false}) {
    final fg = onColoredHeader ? Colors.white : _textDark;
    final bg = onColoredHeader
        ? Colors.white.withValues(alpha: 0.16)
        : const Color(0xFFF3F4F6);

    return PopupMenuButton<String>(
      tooltip: 'Account',
      onSelected: _handleProfileMenuSelection,
      itemBuilder: (context) => _buildProfileMenuItems(),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(18),
          border: onColoredHeader
              ? Border.all(color: Colors.white.withValues(alpha: 0.35))
              : null,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildHeaderProfileAvatar(size: 30),
            const SizedBox(width: 6),
            Icon(Icons.keyboard_arrow_down_rounded, color: fg, size: 18),
          ],
        ),
      ),
    );
  }

  Widget _buildHeaderAction(
    IconData icon, {
    String? badge,
    bool highlighted = false,
    VoidCallback? onTap,
    bool onColoredHeader = false,
  }) {
    final isSettings = icon == Icons.settings_outlined;
    final isNotifications = icon == Icons.notifications_outlined;
    final iconColor = onColoredHeader
        ? Colors.white
        : (highlighted ? _primaryOrange : _textMuted);
    final bgColor = onColoredHeader
        ? (highlighted
            ? Colors.white.withValues(alpha: 0.28)
            : Colors.white.withValues(alpha: 0.16))
        : (highlighted
            ? _primaryOrange.withOpacity(0.15)
            : Colors.grey.shade200);

    return Tooltip(
      message: isNotifications
          ? 'Notifications'
          : isSettings
          ? 'Settings'
          : 'Search',
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: bgColor,
                borderRadius: BorderRadius.circular(16),
                border: onColoredHeader
                    ? Border.all(color: Colors.white.withValues(alpha: 0.35))
                    : null,
              ),
              child: Icon(
                icon,
                color: iconColor,
                size: 22,
              ),
            ),
            if (badge != null && badge != '0')
              Positioned(
                right: 0,
                top: 0,
                child: Container(
                  padding: const EdgeInsets.all(4),
                  decoration: const BoxDecoration(
                    color: Colors.redAccent,
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

  Widget _buildQuickStats() {
    if (_isBootstrapping && !_hasCachedStats) {
      final crossCount = _isMobile ? 2 : (_isTablet ? 2 : 4);
      if (crossCount == 2) {
        return const ShimmerScope(
          child: Column(
            children: [
              SkeletonStatCardsRow(count: 2),
              SizedBox(height: 8),
              SkeletonStatCardsRow(count: 2),
            ],
          ),
        );
      }
      return const ShimmerScope(child: SkeletonStatCardsRow(count: 4));
    }

    final activeVrCount = _vrTours.where((v) => v['status'] == 'Active').length;
    final inactiveSpots = (_touristSpots.length - _activeSpots).clamp(0, 999);
    final weekCounts = _last7DayCheckInCounts();
    final weekVisits = weekCounts.fold<double>(0, (a, b) => a + b).round();
    final yesterdayVisits = weekCounts.length >= 2 ? weekCounts[5].round() : 0;
    final todayTrendPct = yesterdayVisits == 0
        ? (_todayCheckIns == 0 ? 0 : 100)
        : (((_todayCheckIns - yesterdayVisits) / yesterdayVisits) * 100)
            .round();
    final monthTourists = _touristsRegisteredInLastDays(30);
    final touristTrendPct = _totalTourists == 0
        ? 0
        : ((monthTourists / math.max(_totalTourists, 1)) * 100).round().clamp(
            0,
            999,
          );
    final priorWeek = _checkInsInDayRange(7, 14);
    final weekDelta = weekVisits - priorWeek;

    final stats = [
      _StatCard(
        title: 'Today\'s Visits',
        value: '$_todayCheckIns',
        subtitle: 'QR check-ins today',
        icon: Icons.qr_code_scanner_rounded,
        color: _kpiOrange,
        tint: _tintOrange,
        trendLabel: todayTrendPct >= 0
            ? 'â†‘ $todayTrendPct% from yesterday'
            : 'â†“ ${todayTrendPct.abs()}% from yesterday',
        trendPositive: todayTrendPct >= 0,
      ),
      _StatCard(
        title: 'Registered Tourists',
        value: '$_totalTourists',
        subtitle: _storedMunicipalityId != null
            ? 'This municipality only'
            : 'Province (no LGU filter)',
        icon: Icons.people_alt_rounded,
        color: _kpiBlue,
        tint: _tintBlue,
        trendLabel: 'â†‘ +$touristTrendPct% from last month',
        trendPositive: true,
        onTap: () => setState(() {
          _selectedIndex = 4;
          if (_isMobile) _isSidebarExpanded = false;
        }),
      ),
      _StatCard(
        title: 'Active Spots',
        value: '$_activeSpots',
        subtitle: inactiveSpots > 0
            ? '$inactiveSpots inactive'
            : 'All spots active',
        icon: Icons.place_rounded,
        color: _kpiGreen,
        tint: _tintGreen,
        trendLabel: inactiveSpots > 0
            ? 'â†’ $inactiveSpots need attention'
            : 'âœ“ 100% operational',
        trendPositive: inactiveSpots == 0,
      ),
      _StatCard(
        title: 'Visits 7 days',
        value: '$weekVisits',
        subtitle: activeVrCount > 0
            ? '$activeVrCount spots with VR'
            : 'Last 7 days in this LGU',
        icon: Icons.insights_rounded,
        color: _kpiPurple,
        tint: _tintPurple,
        trendLabel: weekDelta == 0
            ? 'â†’ No change'
            : (weekDelta > 0
                ? 'â†‘ +$weekDelta vs prior week'
                : 'â†“ ${weekDelta.abs()} vs prior week'),
        trendPositive: weekDelta >= 0,
        onTap: () => setState(() {
          _selectedIndex = 1;
          if (_isMobile) _isSidebarExpanded = false;
        }),
      ),
    ];

    final crossCount = _isMobile ? 2 : (_isTablet ? 2 : 4);
    const gap = 16.0;

    return DashboardFadeIn(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final cardWidth =
              (constraints.maxWidth - gap * (crossCount - 1)) / crossCount;
          return Wrap(
            spacing: gap,
            runSpacing: gap,
            children: [
              for (final stat in stats)
                SizedBox(
                  width: cardWidth,
                  child: _buildStatCard(stat),
                ),
            ],
          );
        },
      ),
    );
  }

  int _touristsRegisteredInLastDays(int days) {
    final cutoff = DateTime.now().subtract(Duration(days: days));
    var count = 0;
    for (final t in _filterRealTourists(_tourists)) {
      final dt = _registeredDateTimeNullableFromTourist(t);
      if (dt != null && !dt.isBefore(cutoff)) count++;
    }
    return count;
  }

  int _checkInsInDayRange(int startExclusiveDaysAgo, int endExclusiveDaysAgo) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    var count = 0;
    for (final c in _realCheckIns) {
      final ts = c['timestamp'];
      DateTime? date;
      if (ts is Timestamp) {
        date = ts.toDate();
      } else if (ts is DateTime) {
        date = ts;
      }
      if (date == null) continue;
      final day = DateTime(date.year, date.month, date.day);
      final diff = today.difference(day).inDays;
      if (diff >= startExclusiveDaysAgo && diff < endExclusiveDaysAgo) {
        count++;
      }
    }
    return count;
  }

  List<double> _last7DayCheckInCounts() {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final counts = List<double>.filled(7, 0);
    for (final c in _realCheckIns) {
      final ts = c['timestamp'];
      DateTime? date;
      if (ts is Timestamp) {
        date = ts.toDate();
      } else if (ts is DateTime) {
        date = ts;
      }
      if (date == null) continue;
      final day = DateTime(date.year, date.month, date.day);
      final diff = today.difference(day).inDays;
      if (diff >= 0 && diff < 7) {
        counts[6 - diff] += 1;
      }
    }
    return counts;
  }

  /// LGU id for QR: prefer session, else any loaded spot with [municipalityId].
  String? _effectiveLguMunicipalityId() {
    final s = _storedMunicipalityId?.trim();
    if (s != null && s.isNotEmpty) return s;
    for (final spot in _allTouristSpots) {
      final m = spot.municipalityId.trim();
      if (m.isNotEmpty) return m;
    }
    for (final spot in _touristSpots) {
      final m = spot.municipalityId.trim();
      if (m.isNotEmpty) return m;
    }
    return null;
  }

  String? _effectiveLguQrDisplayName() {
    final mid = _effectiveLguMunicipalityId();
    if (mid == null) return null;
    if (_storedMunicipalityId == mid &&
        _municipalityName != null &&
        _municipalityName!.trim().isNotEmpty) {
      return _municipalityName;
    }
    for (final spot in _allTouristSpots) {
      if (spot.municipalityId == mid && spot.municipality.trim().isNotEmpty) {
        return spot.municipality;
      }
    }
    for (final spot in _touristSpots) {
      if (spot.municipalityId == mid && spot.municipality.trim().isNotEmpty) {
        return spot.municipality;
      }
    }
    for (final m in getMisamisOccidentalMunicipalities()) {
      if (m.id == mid) return m.name;
    }
    return mid;
  }

  Widget _buildSpotQRCodesDashboardCard() {
    final spotCount = _touristSpots.length;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _panelBorder),
      ),
      child: _isMobile
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: _primaryOrange.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(24),
                      ),
                      child: Icon(
                        Icons.qr_code_2_rounded,
                        color: _primaryOrange,
                        size: 36,
                      ),
                    ),
                    const SizedBox(width: 16),
                    const Expanded(
                      child: Text(
                        'Spot QR codes',
                        style: TextStyle(
                          color: _textDark,
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  spotCount == 0
                      ? 'Add a QR for each tourist spot (Plaza, El Triunfo, etc.) so you can see where visitors check in.'
                      : 'Each attraction has its own QR. Manage $spotCount spot code${spotCount == 1 ? '' : 's'} to track visits by place.',
                  style: const TextStyle(
                    color: Color(0xFF4B5563),
                    fontSize: 14,
                    height: 1.45,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 14),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: () =>
                        setState(() => _selectedIndex = _spotQRCodesIndex),
                    icon: const Icon(Icons.qr_code_2_rounded, size: 20),
                    label: const Text('Manage spot QR codes'),
                    style: FilledButton.styleFrom(
                      backgroundColor: _primaryOrange,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 13),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ),
              ],
            )
          : Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: _primaryOrange.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(24),
                  ),
                  child: Icon(
                    Icons.qr_code_2_rounded,
                    color: _primaryOrange,
                    size: 36,
                  ),
                ),
                const SizedBox(width: 20),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Spot QR codes',
                        style: TextStyle(
                          color: _textDark,
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        spotCount == 0
                            ? 'Add a QR for each tourist spot (Plaza, El Triunfo, etc.) so you can see where visitors check in.'
                            : 'Each attraction has its own QR. Manage $spotCount spot code${spotCount == 1 ? '' : 's'} to track visits by place.',
                        style: const TextStyle(
                          color: Color(0xFF4B5563),
                          fontSize: 14,
                          height: 1.45,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
                FilledButton.icon(
                  onPressed: () =>
                      setState(() => _selectedIndex = _spotQRCodesIndex),
                  icon: const Icon(Icons.qr_code_2_rounded, size: 20),
                  label: const Text('Manage spot QR codes'),
                  style: FilledButton.styleFrom(
                    backgroundColor: _primaryOrange,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 13,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ],
            ),
    );
  }

  Widget _buildStatCard(_StatCard stat) {
    final valueSize = _isMobile ? 28.0 : 34.0;
    final tint = stat.tint ?? stat.color.withValues(alpha: 0.1);
    final trend = stat.trendLabel ?? '';
    final trendColor = stat.trendPositive
        ? const Color(0xFF059669)
        : const Color(0xFFDC2626);

    return _HoverLiftCard(
      onTap: stat.onTap,
      child: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Colors.white,
              tint.withValues(alpha: 0.7),
            ],
          ),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: stat.color.withValues(alpha: 0.12)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 20,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        clipBehavior: Clip.antiAlias,
        child: Stack(
          children: [
            Positioned(
              right: -10,
              bottom: -8,
              child: Icon(
                stat.icon,
                size: 72,
                color: stat.color.withValues(alpha: 0.08),
              ),
            ),
            Padding(
              padding: EdgeInsets.all(_isMobile ? 14 : 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          color: tint,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Icon(stat.icon, color: stat.color, size: 18),
                      ),
                      const Spacer(),
                      if (trend.isNotEmpty)
                        Flexible(
                          child: Text(
                            trend,
                            textAlign: TextAlign.right,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: GoogleFonts.inter(
                              color: trendColor,
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text(
                    stat.value,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.inter(
                      color: _textDark,
                      fontSize: valueSize,
                      fontWeight: FontWeight.w800,
                      height: 1.05,
                      letterSpacing: -0.8,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    stat.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.inter(
                      color: _textDark,
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  if (stat.subtitle != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      stat.subtitle!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.inter(
                        color: _textMuted,
                        fontSize: 12,
                        fontWeight: FontWeight.w400,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRecentActivity() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Recent Activity',
              style: GoogleFonts.poppins(
                color: const Color(0xFF111827),
                fontSize: 24,
                fontWeight: FontWeight.w600,
              ),
            ),
            TextButton(
              onPressed: () => setState(() {
                _selectedIndex = 1;
                if (_isMobile) _isSidebarExpanded = false;
              }),
              child: Text(
                'View all',
                style: GoogleFonts.poppins(
                  color: _primaryOrange,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        if (_recentActivity.isEmpty)
          _buildEmptyState('No recent activity')
        else
          ...List.generate(_recentActivity.length, (index) {
            final activity = _recentActivity[index];
            return Container(
              margin: EdgeInsets.only(
                bottom: index < _recentActivity.length - 1 ? 12 : 0,
              ),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: _panelBorder),
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: ((activity['color'] as Color?) ?? _primaryOrange)
                          .withOpacity(0.15),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(
                      activity['icon'] as IconData? ?? Icons.info,
                      color: (activity['color'] as Color?) ?? _primaryOrange,
                      size: 22,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          activity['title']?.toString() ?? 'Unknown',
                          style: const TextStyle(
                            color: _textDark,
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          activity['description']?.toString() ?? '',
                          style: TextStyle(color: _textMuted, fontSize: 13),
                        ),
                      ],
                    ),
                  ),
                  if (activity['time'] != null)
                    Text(
                      activity['time']?.toString() ?? '',
                      style: TextStyle(color: _textMuted, fontSize: 11),
                    ),
                ],
              ),
            );
          }),
      ],
    );
  }

  Widget _buildEmptyState(
    String message, {
    IconData? icon,
    Color? iconColor,
    String? subtitle,
  }) {
    final accent = iconColor ?? _primaryOrange;
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 36, horizontal: 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: accent.withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon ?? Icons.inbox_rounded, color: accent, size: 36),
            ),
            const SizedBox(height: 14),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: _textDark,
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
            if (subtitle != null) ...[
              const SizedBox(height: 6),
              Text(
                subtitle,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: _textMuted,
                  fontSize: 13,
                  height: 1.4,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  // ==================== CHECK-INS SECTION ====================
  Widget _buildCheckInsContent() {
    final filteredCheckIns = _checkIns.where((c) {
      final searchQuery = _checkInsSearchController.text.toLowerCase();
      final id = _displayTouristIdFromCheckIn(c).toLowerCase();
      final matchesSearch =
          searchQuery.isEmpty ||
          id.contains(searchQuery) ||
          (c['touristId']?.toString() ?? '').toLowerCase().contains(
            searchQuery,
          ) ||
          (c['location']?.toString() ?? '').toLowerCase().contains(searchQuery) ||
          (c['spot_name']?.toString() ?? '').toLowerCase().contains(searchQuery) ||
          (c['spotId']?.toString() ?? '').toLowerCase().contains(searchQuery);

      final matchesStatus =
          _checkInStatusFilter == 'All' || c['status'] == _checkInStatusFilter;

      final matchesDate = _matchesCheckInDateFilter(c);

      return matchesSearch && matchesStatus && matchesDate;
    }).toList();

    final munLabel =
        (_municipalityName ?? _storedMunicipalityId ?? 'your LGU').trim();

    return RefreshIndicator(
      onRefresh: _loadData,
      color: _primaryOrange,
      child: _buildFramedContentShell(
        title: 'Tourist Visits',
        subtitle:
            'QR check-ins in $munLabel â€” names hidden for data privacy',
        body: Padding(
          padding: EdgeInsets.fromLTRB(
            _isMobile ? 12 : 16,
            12,
            _isMobile ? 12 : 16,
            16,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildLguVisitsSummaryBar(sumCheckInVisitors(filteredCheckIns)),
              const SizedBox(height: 10),
              _buildCheckInDateFilterBar(),
              const SizedBox(height: 12),
              Expanded(
                child: Container(
                  decoration: _tourismPanelDecoration(),
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
                        child: _buildCheckInsSearchAndStatusRow(),
                      ),
                      const Divider(height: 1, color: _panelBorder),
                      Expanded(
                        child: filteredCheckIns.isEmpty
                            ? _buildEmptyState(
                                'No visits match your filters',
                                icon: Icons.qr_code_scanner_rounded,
                                iconColor: _primaryOrange,
                                subtitle:
                                    'Scans from your municipality QR appear here.',
                              )
                            : _isMobile
                            ? ListView(
                                padding: const EdgeInsets.fromLTRB(
                                  12,
                                  12,
                                  12,
                                  16,
                                ),
                                children: [
                                  _buildCheckInsListMobile(filteredCheckIns),
                                ],
                              )
                            : SingleChildScrollView(
                                padding: const EdgeInsets.fromLTRB(
                                  12,
                                  12,
                                  12,
                                  16,
                                ),
                                child: _buildCheckInsTable(filteredCheckIns),
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
    );
  }

  Widget _buildLguVisitsSummaryBar(int visibleCount) {
    final munLabel =
        (_municipalityName ?? _storedMunicipalityId ?? 'Your LGU').trim();
    final pending = _checkIns.where((c) => c['status'] == 'Pending').length;
    final verified = _checkIns.where((c) => c['status'] == 'Verified').length;
    final today = _checkIns.where((c) {
      final t = _parseCheckInTimestamp(c);
      if (t == null) return false;
      final now = DateTime.now();
      return t.year == now.year && t.month == now.month && t.day == now.day;
    }).length;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: _panelBorder),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: _primaryOrange.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(
              Icons.qr_code_scanner_rounded,
              color: _primaryOrange,
              size: 20,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '$visibleCount of ${sumCheckInVisitors(_checkIns)} visitors',
                  style: const TextStyle(
                    color: _textDark,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Text(
                  'Today $today Â· Verified $verified Â· Pending $pending',
                  style: const TextStyle(color: _textMuted, fontSize: 11),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: const Color(0xFFECFDF3),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: const Color(0xFF86EFAC)),
            ),
            child: const Text(
              'Privacy on',
              style: TextStyle(
                color: Color(0xFF15803D),
                fontSize: 11,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: const Color(0xFFDCFCE7),
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: const Color(0xFF86EFAC)),
            ),
            child: Text(
              munLabel,
              style: const TextStyle(
                color: Color(0xFF15803D),
                fontWeight: FontWeight.w700,
                fontSize: 11,
              ),
            ),
          ),
        ],
      ),
    );
  }

  bool _matchesCheckInDateFilter(Map<String, dynamic> c) {
    if (_checkInDateFilter == 'All') return true;
    final t = _parseCheckInTimestamp(c);
    if (t == null) return false;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final day = DateTime(t.year, t.month, t.day);
    switch (_checkInDateFilter) {
      case 'Today':
        return day == today;
      case '7 days':
        return !day.isBefore(today.subtract(const Duration(days: 6)));
      case '30 days':
        return !day.isBefore(today.subtract(const Duration(days: 29)));
      default:
        return true;
    }
  }

  Widget _buildCheckInDateFilterBar() {
    Widget modeChip(String option) {
      final selected = _checkInDateFilter == option;
      return FilterChip(
        label: Text(option),
        selected: selected,
        showCheckmark: false,
        onSelected: (_) => setState(() => _checkInDateFilter = option),
        selectedColor: _primaryOrange.withValues(alpha: 0.18),
        labelStyle: TextStyle(
          color: selected ? _primaryOrange : _textDark,
          fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
          fontSize: 12,
        ),
        side: BorderSide(
          color: selected
              ? _primaryOrange.withValues(alpha: 0.45)
              : _panelBorder,
        ),
        backgroundColor: Colors.white,
        visualDensity: VisualDensity.compact,
      );
    }

    Widget statusChip(String option) {
      final selected = _checkInStatusFilter == option;
      return FilterChip(
        label: Text(option == 'All' ? 'All status' : option),
        selected: selected,
        showCheckmark: false,
        onSelected: (_) => setState(() => _checkInStatusFilter = option),
        selectedColor: _primaryOrange.withValues(alpha: 0.18),
        labelStyle: TextStyle(
          color: selected ? _primaryOrange : _textDark,
          fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
          fontSize: 12,
        ),
        side: BorderSide(
          color: selected
              ? _primaryOrange.withValues(alpha: 0.45)
              : _panelBorder,
        ),
        backgroundColor: Colors.white,
        visualDensity: VisualDensity.compact,
      );
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: _panelBorder),
      ),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          const Text(
            'Filter by visit:',
            style: TextStyle(
              color: _textMuted,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
          modeChip('All'),
          modeChip('Today'),
          modeChip('7 days'),
          modeChip('30 days'),
          Container(
            width: 1,
            height: 22,
            color: _panelBorder,
            margin: const EdgeInsets.symmetric(horizontal: 4),
          ),
          statusChip('All'),
          statusChip('Verified'),
          statusChip('Pending'),
        ],
      ),
    );
  }

  Widget _buildCheckInsSearchAndStatusRow() {
    return AppSearchBar(
      controller: _checkInsSearchController,
      hintText: 'Search by Tourist ID or location...',
      onChanged: (value) => setState(() {}),
      horizontalPadding: 0,
      backgroundColor: const Color(0xFFF9FAFB),
      borderColor: _panelBorder,
      showMicrophone: false,
      height: 46,
      showShadow: false,
    );
  }

  Widget _buildCheckInsListMobile(List<Map<String, dynamic>> checkIns) {
    return Column(
      children: checkIns
          .map(
            (c) => Container(
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: _kAnalyticsSurfaceBorder, width: 1),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.05),
                    blurRadius: 10,
                    offset: const Offset(0, 3),
                  ),
                ],
              ),
              child: InkWell(
                onTap: () => _showCheckInDetailsDialog(c),
                borderRadius: BorderRadius.circular(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(child: _buildCheckInTouristCell(c)),
                        const SizedBox(width: 8),
                        _buildStatusBadge(c['status']),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(c['location'], style: TextStyle(color: _textMuted)),
                    const SizedBox(height: 4),
                    Text(
                      _formatTime(c['timestamp']),
                      style: TextStyle(color: _textMuted, fontSize: 12),
                    ),
                    if (c['status'] == 'Pending') ...[
                      const SizedBox(height: 12),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          onPressed: () => _verifyCheckIn(c),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: _primaryOrange,
                          ),
                          child: const Text('Verify'),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          )
          .toList(),
    );
  }

  Widget _buildCheckInsTable(List<Map<String, dynamic>> checkIns) {
    const headerBg = Color(0xFFF9FAFB);
    const stripe = Color(0xFFF3F4F6);
    const tableHeadingStyle = TextStyle(
      color: _textDark,
      fontWeight: FontWeight.w800,
      fontSize: 12,
      letterSpacing: 0.35,
    );

    const minTableWidth = 760.0;

    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border.all(color: _kAnalyticsSurfaceBorder, width: 1),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 14,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final cw = constraints.maxWidth;
            final tableWidth = cw.isFinite && cw > 0
                ? (cw < minTableWidth ? minTableWidth : cw)
                : minTableWidth;

            return SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: SizedBox(
                width: tableWidth,
                child: DataTable(
                  headingRowColor: WidgetStateProperty.all(headerBg),
                  headingRowHeight: 48,
                  dataRowMinHeight: 54,
                  dataRowMaxHeight: 88,
                  horizontalMargin: 20,
                  columnSpacing: 24,
                  headingTextStyle: tableHeadingStyle,
                  dataTextStyle: const TextStyle(
                    color: _textDark,
                    fontSize: 13,
                  ),
                  dividerThickness: 1,
                  border: TableBorder(
                    horizontalInside: BorderSide(
                      color: _kAnalyticsSurfaceBorder,
                    ),
                    top: BorderSide(color: _kAnalyticsSurfaceBorder),
                    bottom: BorderSide(color: _kAnalyticsSurfaceBorder),
                  ),
                  columns: [
                    const DataColumn(label: Text('Tourist ID')),
                    const DataColumn(label: Text('Location')),
                    const DataColumn(label: Text('Time')),
                    const DataColumn(label: Text('Status')),
                    DataColumn(
                      label: SizedBox(
                        width: 88,
                        child: Center(
                          child: Text('Actions', style: tableHeadingStyle),
                        ),
                      ),
                    ),
                  ],
                  rows: [
                    for (var i = 0; i < checkIns.length; i++)
                      _buildCheckInDataRow(checkIns[i], i, stripe),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  DataRow _buildCheckInDataRow(
    Map<String, dynamic> c,
    int index,
    Color stripeColor,
  ) {
    final rowBg = index.isOdd ? stripeColor : const Color(0xFFFFFFFF);
    return DataRow(
      color: WidgetStateProperty.all(rowBg),
      cells: [
        DataCell(_buildCheckInTouristCell(c)),
        DataCell(
          Text(
            c['location']?.toString() ?? '',
            style: const TextStyle(color: _textDark),
          ),
        ),
        DataCell(
          Text(
            _formatTime(c['timestamp']),
            style: const TextStyle(color: _textMuted, fontSize: 13),
          ),
        ),
        DataCell(_buildStatusBadge(c['status']?.toString() ?? '')),
        DataCell(
          SizedBox(
            width: 88,
            child: Center(
              child: Tooltip(
                message: 'View details',
                child: Material(
                  color: _primaryOrange.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                  child: InkWell(
                    onTap: () => _showCheckInDetailsDialog(c),
                    borderRadius: BorderRadius.circular(12),
                    child: const Padding(
                      padding: EdgeInsets.all(8),
                      child: Icon(
                        Icons.visibility_rounded,
                        color: _primaryOrange,
                        size: 20,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildStatusBadge(String status) {
    final isVerified = status == 'Verified';
    final bg = isVerified ? const Color(0xFFDCFCE7) : const Color(0xFFFFEDD5);
    final fg = isVerified ? const Color(0xFF15803D) : const Color(0xFFC2410C);
    final border = isVerified
        ? const Color(0xFF86EFAC).withOpacity(0.9)
        : const Color(0xFFFDBA74).withOpacity(0.85);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: border, width: 1),
      ),
      child: Text(
        status,
        style: TextStyle(
          color: fg,
          fontSize: 12,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.2,
        ),
      ),
    );
  }

  void _showCheckInDetailsDialog(Map<String, dynamic> checkIn) {
    final id = _displayTouristIdFromCheckIn(checkIn);
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: _cardBg,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text(
          'Visit details',
          style: TextStyle(
            color: _textDark,
            fontWeight: FontWeight.w800,
            fontSize: 20,
          ),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(child: _buildVisitPrivacyAvatar(radius: 28)),
            const SizedBox(height: 12),
            Center(child: _buildVisitTouristIdChip(id)),
            const SizedBox(height: 8),
            const Center(
              child: Text(
                'Name hidden for data privacy',
                style: TextStyle(color: _textMuted, fontSize: 12),
              ),
            ),
            const SizedBox(height: 12),
            _buildDetailRow('Tourist ID', id),
            _buildDetailRow(
              'Location',
              checkIn['location']?.toString() ?? 'â€”',
            ),
            _buildDetailRow('Time', _formatTime(checkIn['timestamp'])),
            _buildDetailRow(
              'Status',
              checkIn['status']?.toString() ?? 'â€”',
            ),
          ],
        ),
        actions: [
          if (checkIn['status'] == 'Pending')
            ElevatedButton(
              onPressed: () {
                Navigator.pop(context);
                _verifyCheckIn(checkIn);
              },
              style: ElevatedButton.styleFrom(backgroundColor: _primaryOrange),
              child: const Text('Verify'),
            ),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close', style: TextStyle(color: _textMuted)),
          ),
        ],
      ),
    );
  }

  Widget _buildDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(color: _textMuted)),
          Text(
            value,
            style: const TextStyle(
              color: _textDark,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _verifyCheckIn(Map<String, dynamic> checkIn) async {
    final docId = checkIn['id']?.toString();
    if (docId == null || docId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Cannot verify: missing check-in ID'),
          backgroundColor: Colors.redAccent,
        ),
      );
      return;
    }

    try {
      if (Firebase.apps.isNotEmpty) {
        await FirebaseFirestore.instance.collection('qr_checkins').doc(docId).update({
          'status': 'verified',
          'verifiedAt': FieldValue.serverTimestamp(),
          'verifiedBy': FirebaseAuth.instance.currentUser?.email ?? '',
        });
      }
      if (!mounted) return;
      setState(() {
        final index = _checkIns.indexWhere((c) => c['id'] == docId);
        if (index != -1) {
          _checkIns[index]['status'] = 'Verified';
        }
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Visit verified successfully'),
          backgroundColor: _primaryOrange,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Could not verify visit: $e'),
          backgroundColor: Colors.redAccent,
        ),
      );
    }
  }

  // ==================== TOURIST SPOTS SECTION ====================
  Future<void> _runBackfillSpotQrMetadata({bool showSnack = true}) async {
    if (_isBackfillingSpotQr) return;
    setState(() => _isBackfillingSpotQr = true);
    try {
      // Non-destructive: seed missing defaults + backfill QR/images.
      // Do NOT call enforceCanonicalSpotDocuments() here â€” that deletes
      // LGU-created spots (e.g. Ambak-Ambak Falls) on refresh.
      final result = await TouristSpotsFirestoreService.syncAllSpotQrData();
      if (!mounted || !showSnack) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            (result.created == 0 &&
                    result.backfilled == 0 &&
                    result.imagesUpdated == 0)
                ? 'No spot changes needed (or you may be offline).'
                : 'Sync complete: ${result.created} seed spot(s), '
                      '${result.backfilled} QR field(s), '
                      '${result.imagesUpdated} image(s) saved to Firestore. '
                      'Custom LGU spots were kept.',
          ),
          backgroundColor: _primaryOrange,
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (e) {
      if (!mounted || !showSnack) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Could not sync QR fields: $e'),
          backgroundColor: Colors.redAccent,
          behavior: SnackBarBehavior.floating,
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _isBackfillingSpotQr = false);
      }
    }
  }

  Future<void> _runSyncSpotImagesOnly({bool showSnack = true}) async {
    if (_isBackfillingSpotQr) return;
    setState(() => _isBackfillingSpotQr = true);
    try {
      final result = await TouristSpotsFirestoreService.backfillSpotImagesInFirestore(
        overwriteExisting: true,
      );
      if (!mounted || !showSnack) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            result.updated == 0
                ? 'No image updates (${result.skipped} already set, ${result.missing} unmatched).'
                : 'Saved ${result.updated} spot image(s) to Firestore '
                      '(${result.skipped} unchanged, ${result.missing} without a catalog match).',
          ),
          backgroundColor: _primaryOrange,
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (e) {
      if (!mounted || !showSnack) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Could not sync images: $e'),
          backgroundColor: Colors.redAccent,
          behavior: SnackBarBehavior.floating,
        ),
      );
    } finally {
      if (mounted) setState(() => _isBackfillingSpotQr = false);
    }
  }

  /// Banner: sync canonical spots, QR fields, and images to Firestore.
  Widget _buildSpotQrFirestoreSyncBanner() {
    return Material(
      color: Colors.transparent,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: const Color(0xFFFFF7ED),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: _panelBorder),
        ),
        child: _isMobile
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        Icons.cloud_sync_rounded,
                        color: _primaryOrange,
                        size: 22,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Sync spots to Firestore',
                          style: TextStyle(
                            color: _textDark,
                            fontWeight: FontWeight.w700,
                            fontSize: 14,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Pushes municipality spot images into tourist_spots, '
                    'fills QR fields for seed spots, and keeps custom LGU-created spots.',
                    style: TextStyle(
                      color: _textMuted,
                      fontSize: 12,
                      height: 1.35,
                    ),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: _isBackfillingSpotQr
                          ? null
                          : _runBackfillSpotQrMetadata,
                      icon: _isBackfillingSpotQr
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Icon(Icons.play_arrow_rounded, size: 20),
                      style: FilledButton.styleFrom(
                        backgroundColor: _primaryOrange,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                      label: Text(
                        _isBackfillingSpotQr ? 'Syncing?' : 'Full sync',
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: _isBackfillingSpotQr
                          ? null
                          : _runSyncSpotImagesOnly,
                      icon: const Icon(Icons.image_rounded, size: 18),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: _primaryOrange,
                        side: BorderSide(color: _primaryOrange.withOpacity(0.5)),
                        padding: const EdgeInsets.symmetric(vertical: 11),
                      ),
                      label: const Text(
                        'Images only',
                        style: TextStyle(fontWeight: FontWeight.w600),
                      ),
                    ),
                  ),
                ],
              )
            : Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.cloud_sync_rounded,
                    color: _primaryOrange,
                    size: 26,
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Sync spots to Firestore',
                          style: TextStyle(
                            color: _textDark,
                            fontWeight: FontWeight.w700,
                            fontSize: 15,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'Saves municipality images to tourist_spots, fills QR metadata '
                          'for seed spots, and keeps custom LGU-created spots.',
                          style: TextStyle(
                            color: _textMuted,
                            fontSize: 13,
                            height: 1.4,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      FilledButton.icon(
                        onPressed: _isBackfillingSpotQr
                            ? null
                            : _runBackfillSpotQrMetadata,
                        icon: _isBackfillingSpotQr
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : const Icon(Icons.play_arrow_rounded, size: 20),
                        style: FilledButton.styleFrom(
                          backgroundColor: _primaryOrange,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 12,
                          ),
                        ),
                        label: Text(
                          _isBackfillingSpotQr ? 'Syncing?' : 'Full sync',
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                      ),
                      const SizedBox(height: 8),
                      OutlinedButton.icon(
                        onPressed: _isBackfillingSpotQr
                            ? null
                            : _runSyncSpotImagesOnly,
                        icon: const Icon(Icons.image_rounded, size: 18),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: _primaryOrange,
                          side: BorderSide(
                            color: _primaryOrange.withOpacity(0.5),
                          ),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 10,
                          ),
                        ),
                        label: const Text(
                          'Images only',
                          style: TextStyle(fontWeight: FontWeight.w600),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
      ),
    );
  }

  bool _spotHasVr(TouristSpot spot) =>
      spot.vrLink != null && spot.vrLink!.trim().isNotEmpty;

  int _vrViewsForSpot(String spotId) {
    for (final tour in _vrTours) {
      if (tour['spotId']?.toString() == spotId) {
        final views = tour['views'];
        return views is int ? views : (views is num ? views.toInt() : 0);
      }
    }
    return 0;
  }

  Widget _buildSpotVrBadge(TouristSpot spot) {
    if (!_spotHasVr(spot)) {
      return Text(
        'No VR',
        style: TextStyle(color: _textMuted, fontSize: 12),
      );
    }
    final views = _vrViewsForSpot(spot.id);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: Colors.purple.withOpacity(0.12),
            borderRadius: BorderRadius.circular(12),
          ),
          child: const Text(
            'VR linked',
            style: TextStyle(
              color: Colors.purple,
              fontSize: 11,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        if (views > 0) ...[
          const SizedBox(width: 6),
          Text(
            '$views views',
            style: TextStyle(color: _textMuted, fontSize: 11),
          ),
        ],
      ],
    );
  }

  List<Widget> _buildSpotActionButtons(TouristSpot spot) {
    return [
      if (_spotHasVr(spot))
        IconButton(
          onPressed: () => _playVrForSpot(spot),
          icon: const Icon(Icons.play_circle, color: Colors.purple, size: 20),
          tooltip: 'Preview VR tour',
          visualDensity: VisualDensity.compact,
        ),
      IconButton(
        onPressed: () => _showEditSpotDialog(spot),
        icon: const Icon(Icons.edit, color: Colors.blue, size: 18),
        tooltip: 'Edit spot & VR URL',
        visualDensity: VisualDensity.compact,
      ),
      if (_spotHasVr(spot))
        IconButton(
          onPressed: () => _showRemoveVrLinkForSpot(spot),
          icon: const Icon(Icons.link_off, color: Colors.redAccent, size: 18),
          tooltip: 'Remove VR link',
          visualDensity: VisualDensity.compact,
        ),
      IconButton(
        onPressed: () => _showDeleteSpotDialog(spot),
        icon: const Icon(Icons.delete, color: Colors.redAccent, size: 18),
        tooltip: 'Delete',
        visualDensity: VisualDensity.compact,
      ),
      IconButton(
        onPressed: () => _toggleSpotStatus(spot),
        icon: Icon(
          spot.status == 'Active' ? Icons.visibility_off : Icons.visibility,
          color: Colors.orange,
          size: 18,
        ),
        tooltip: spot.status == 'Active' ? 'Deactivate' : 'Activate',
        visualDensity: VisualDensity.compact,
      ),
    ];
  }

  Future<void> _playVrForSpot(TouristSpot spot) async {
    final vrLink = spot.vrLink?.trim() ?? '';
    if (vrLink.isEmpty) return;
    await VrTourFirestoreService.incrementViewsForSpot(spot.id);
    await openVrForTouristSpot(
      context,
      spotId: spot.id,
      spotName: spot.name,
      vrLink: vrLink,
      imageUrl: spot.imageUrl,
      allowWeb: true,
    );
    if (!mounted) return;
    await _loadData();
    setState(() {});
  }

  void _showRemoveVrLinkForSpot(TouristSpot spot) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: _cardBg,
        title: const Row(
          children: [
            Icon(Icons.link_off, color: Colors.redAccent),
            SizedBox(width: 12),
            Text('Remove VR link', style: TextStyle(color: _textDark)),
          ],
        ),
        content: Text(
          'Remove the VR tour URL from "${spot.name}"? The tourist spot stays; '
          'only the VR link is cleared.',
          style: const TextStyle(color: _textMuted),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel', style: TextStyle(color: _textMuted)),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(context);
              final ok = await VrTourFirestoreService.clearVrLinkForSpot(spot.id);
              if (!context.mounted) return;
              if (!ok) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Could not remove VR link'),
                    backgroundColor: Colors.redAccent,
                  ),
                );
                return;
              }
              await _loadData();
              if (!mounted) return;
              setState(() {});
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('VR link removed from tourist spot'),
                  backgroundColor: Color(0xFFF97316),
                ),
              );
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
            child: const Text('Remove link'),
          ),
        ],
      ),
    );
  }

  Widget _buildTouristSpotsContent() {
    final filteredSpots = _touristSpots.where((s) {
      final searchQuery = _spotsSearchController.text.toLowerCase();
      final matchesSearch =
          searchQuery.isEmpty ||
          s.name.toLowerCase().contains(searchQuery) ||
          s.municipality.toLowerCase().contains(searchQuery);

      final matchesCategory =
          _spotCategoryFilter == 'All' || s.category == _spotCategoryFilter;

      final hasVr = _spotHasVr(s);
      final matchesVr = _spotVrFilter == 'All' ||
          (_spotVrFilter == 'With VR' && hasVr) ||
          (_spotVrFilter == 'Without VR' && !hasVr);

      return matchesSearch && matchesCategory && matchesVr;
    }).toList();

    return RefreshIndicator(
      onRefresh: _loadData,
      color: _primaryOrange,
      child: _buildFramedContentShell(
        title: 'Tourist Spots',
        subtitle:
            'One place for destinations ? edit spot details, paste VR tour URLs, '
            'and manage QR codes',
        body: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: EdgeInsets.all(_isMobile ? 12 : 16),
          child: _wrapTourismPanel(
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildSpotsFilters(),
                const SizedBox(height: 14),
                _buildSpotQrFirestoreSyncBanner(),
                const SizedBox(height: 16),
                if (filteredSpots.isEmpty)
                  _buildEmptyState(
                    'No tourist spots found',
                    icon: Icons.place_rounded,
                    iconColor: _primaryOrange,
                    subtitle:
                        'Add a spot or run Sync to load canonical destinations.',
                  )
                else if (_isMobile)
                  _buildSpotsGridMobile(filteredSpots)
                else
                  _buildSpotsTable(filteredSpots),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _copyQrPayloadToClipboard(String payload, {String label = 'Link'}) async {
    await Clipboard.setData(ClipboardData(text: payload));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('$label copied'),
        backgroundColor: _primaryOrange,
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  Widget _buildSpotQRCodesContent() {
    final effectiveMunicipalityId = _effectiveLguMunicipalityId();
    final municipalityDisplayName =
        _effectiveLguQrDisplayName() ?? effectiveMunicipalityId;
    final spots = List<TouristSpot>.from(_touristSpots)
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    final spotsNeedingQr = spots
        .where((s) => (s.qrPayload ?? '').trim().isEmpty)
        .toList();
    final savedCount =
        spots.where((s) => (s.qrPayload ?? '').trim().isNotEmpty).length;

    void openAddDialog() {
      if (effectiveMunicipalityId == null || effectiveMunicipalityId.isEmpty) {
        return;
      }
      _showGenerateSpotQrDialog(
        municipalityId: effectiveMunicipalityId,
        municipalityDisplayName:
            municipalityDisplayName ?? effectiveMunicipalityId,
        candidates: spotsNeedingQr,
      );
    }

    return RefreshIndicator(
      onRefresh: _loadData,
      color: _primaryOrange,
      child: _buildFramedContentShell(
        title: 'Spot QR Codes',
        subtitle:
            'Each tourist spot has its own check-in QR so you can see where visitors go.',
        actions: [
          if (effectiveMunicipalityId != null &&
              effectiveMunicipalityId.isNotEmpty) ...[
            if (!_isMobile)
              TextButton.icon(
                onPressed: openAddDialog,
                icon: const Icon(Icons.add_rounded, size: 18),
                label: const Text('Add spot QR'),
                style: TextButton.styleFrom(
                  foregroundColor: _primaryOrange,
                  backgroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 10,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              )
            else
              IconButton(
                tooltip: 'Add spot QR',
                onPressed: openAddDialog,
                icon: const Icon(Icons.add_rounded, color: Colors.white),
              ),
          ],
        ],
        body: effectiveMunicipalityId == null || effectiveMunicipalityId.isEmpty
            ? Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.qr_code_2_rounded, size: 56, color: _textMuted),
                      const SizedBox(height: 14),
                      const Text(
                        'Municipality not set',
                        style: TextStyle(
                          color: _textDark,
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'Set your LGU municipality in Settings so spot QR codes can load.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: _textMuted, fontSize: 14),
                      ),
                    ],
                  ),
                ),
              )
            : SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: EdgeInsets.all(_isMobile ? 14 : 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFFF7ED),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: _primaryOrange.withValues(alpha: 0.25),
                        ),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(
                            Icons.place_rounded,
                            color: _primaryOrange,
                            size: 22,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              spots.isEmpty
                                  ? 'Add a spot QR for each attraction (e.g. Plaza, El Triunfo). '
                                      'Scans are counted per place in Analytics.'
                                  : '$savedCount of ${spots.length} spots have a saved QR. '
                                      'Print each code at its location so visits show as Plaza vs El Triunfo, not a general city scan.',
                              style: const TextStyle(
                                color: Color(0xFF9A3412),
                                fontSize: 13,
                                height: 1.4,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    if (spots.isEmpty)
                      Container(
                        padding: const EdgeInsets.all(22),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(18),
                          border: Border.all(color: _panelBorder),
                        ),
                        child: Column(
                          children: [
                            Icon(
                              Icons.travel_explore_rounded,
                              size: 40,
                              color: _textMuted,
                            ),
                            const SizedBox(height: 12),
                            const Text(
                              'No spot QRs yet',
                              style: TextStyle(
                                color: _textDark,
                                fontWeight: FontWeight.w700,
                                fontSize: 15,
                              ),
                            ),
                            const SizedBox(height: 6),
                            const Text(
                              'Add a spot QR for each attraction (e.g. Plaza, El Triunfo).',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: _textMuted,
                                fontSize: 13,
                                height: 1.35,
                              ),
                            ),
                            const SizedBox(height: 14),
                            FilledButton.icon(
                              onPressed: openAddDialog,
                              icon: const Icon(Icons.add_rounded, size: 18),
                              label: const Text('Add spot QR'),
                              style: FilledButton.styleFrom(
                                backgroundColor: _primaryOrange,
                              ),
                            ),
                          ],
                        ),
                      )
                    else
                      ...spots.map(
                        (spot) => Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: _buildSpotQrCard(
                            spot: spot,
                            municipalityId: effectiveMunicipalityId,
                            municipalityDisplayName:
                                municipalityDisplayName ??
                                    effectiveMunicipalityId,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
      ),
    );
  }

  String _spotQrPayloadFor(TouristSpot spot, String municipalityId) {
    final stored = (spot.qrPayload ?? '').trim();
    if (stored.isNotEmpty) return stored;
    final mid = normalizeMunicipalityId(
      spot.municipalityId.isNotEmpty ? spot.municipalityId : municipalityId,
    );
    return spotQrData(
      mid.isNotEmpty ? mid : municipalityId,
      spot.id,
      latitude: spot.latitude,
      longitude: spot.longitude,
    );
  }

  Widget _buildSpotQrCard({
    required TouristSpot spot,
    required String municipalityId,
    required String municipalityDisplayName,
  }) {
    final mid = normalizeMunicipalityId(
      spot.municipalityId.isNotEmpty ? spot.municipalityId : municipalityId,
    );
    final qrData = _spotQrPayloadFor(spot, municipalityId);
    final hasSavedPayload = (spot.qrPayload ?? '').trim().isNotEmpty;
    final placeLabel = spot.municipality.isNotEmpty
        ? spot.municipality
        : municipalityDisplayName;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _panelBorder),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final wide = constraints.maxWidth >= 640;
          final preview = Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: const Color(0xFFF9FAFB),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: _panelBorder),
            ),
            child: QrImageView(
              data: qrData,
              version: QrVersions.auto,
              size: wide ? 96 : 120,
              backgroundColor: Colors.white,
              errorCorrectionLevel: QrErrorCorrectLevel.H,
            ),
          );

          final details = Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          spot.name,
                          style: GoogleFonts.poppins(
                            color: _textDark,
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          '${spot.category} · $placeLabel',
                          style: const TextStyle(
                            color: _textMuted,
                            fontSize: 12.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 9,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: hasSavedPayload
                          ? _tintGreen
                          : _primaryOrange.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      hasSavedPayload ? 'Ready' : 'Needs save',
                      style: TextStyle(
                        color: hasSavedPayload
                            ? const Color(0xFF15803D)
                            : _primaryOrange,
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  if (!hasSavedPayload)
                    ElevatedButton.icon(
                      onPressed: () => _persistSpotQr(
                        spot: spot,
                        municipalityId: mid.isNotEmpty ? mid : municipalityId,
                      ),
                      icon: const Icon(Icons.save_rounded, size: 16),
                      label: const Text('Save QR'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _primaryOrange,
                        foregroundColor: Colors.white,
                        elevation: 0,
                        visualDensity: VisualDensity.compact,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                    ),
                  ElevatedButton.icon(
                    onPressed: () async {
                      await downloadSpotQrPng(
                        mid.isNotEmpty ? mid : municipalityId,
                        spot.id,
                        latitude: spot.latitude,
                        longitude: spot.longitude,
                      );
                      if (!mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('PNG download started (check Downloads)'),
                          backgroundColor: _primaryOrange,
                          behavior: SnackBarBehavior.floating,
                        ),
                      );
                    },
                    icon: const Icon(Icons.download_rounded, size: 16),
                    label: const Text('PNG'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: hasSavedPayload
                          ? _primaryOrange
                          : const Color(0xFFEA580C),
                      foregroundColor: Colors.white,
                      elevation: 0,
                      visualDensity: VisualDensity.compact,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                  ),
                  OutlinedButton.icon(
                    onPressed: () async {
                      await downloadSpotQrPdf(
                        municipalityId:
                            mid.isNotEmpty ? mid : municipalityId,
                        spotId: spot.id,
                        spotName: spot.name,
                        municipalityDisplayName: municipalityDisplayName,
                        latitude: spot.latitude,
                        longitude: spot.longitude,
                      );
                    },
                    icon: Icon(
                      Icons.picture_as_pdf_rounded,
                      color: _primaryOrange,
                      size: 16,
                    ),
                    label: Text(
                      'PDF',
                      style: TextStyle(
                        color: _primaryOrange,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    style: OutlinedButton.styleFrom(
                      side: BorderSide(color: _panelBorder),
                      visualDensity: VisualDensity.compact,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                  ),
                  TextButton.icon(
                    onPressed: () => _copyQrPayloadToClipboard(
                      qrData,
                      label: 'Spot QR link',
                    ),
                    icon: Icon(
                      Icons.copy_rounded,
                      size: 15,
                      color: _primaryOrange,
                    ),
                    label: Text(
                      'Copy link',
                      style: TextStyle(
                        color: _primaryOrange,
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          );

          if (!wide) {
            return Column(
              children: [
                preview,
                const SizedBox(height: 12),
                details,
              ],
            );
          }
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              preview,
              const SizedBox(width: 14),
              Expanded(child: details),
            ],
          );
        },
      ),
    );
  }

  Future<void> _persistSpotQr({
    required TouristSpot spot,
    required String municipalityId,
  }) async {
    final ok = await TouristSpotsFirestoreService.ensureSpotQrMetadata(
      spotId: spot.id,
      municipalityId: municipalityId,
      latitude: spot.latitude,
      longitude: spot.longitude,
    );
    if (!mounted) return;
    if (ok) await _loadData();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          ok
              ? 'Unique QR saved for ${spot.name}'
              : 'Could not save QR. Check Firebase permissions.',
        ),
        backgroundColor: ok ? _primaryOrange : Colors.redAccent,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  void _showGenerateSpotQrDialog({
    required String municipalityId,
    required String municipalityDisplayName,
    required List<TouristSpot> candidates,
  }) {
    final nameController = TextEditingController();
    final descriptionController = TextEditingController();
    final latController = TextEditingController();
    final lngController = TextEditingController();
    final anchor = getMunicipalityAnchorCoordinates(municipalityId);
    if (anchor != null) {
      latController.text = anchor.lat.toStringAsFixed(6);
      lngController.text = anchor.lng.toStringAsFixed(6);
    }

    var createNewSpot = true;
    String selectedCategory = 'Beach';
    TouristSpot? selectedExisting =
        candidates.isNotEmpty ? candidates.first : null;
    var saving = false;

    showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) {
          final canGenerateExisting =
              !createNewSpot && selectedExisting != null;
          final generateEnabled = !saving &&
              (createNewSpot || canGenerateExisting);

          return AlertDialog(
            backgroundColor: _cardBg,
            title: Text(
              'Add QR Code',
              style: GoogleFonts.inter(
                color: _textDark,
                fontSize: 18,
                fontWeight: FontWeight.w800,
              ),
            ),
            content: SizedBox(
              width: 460,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      'Create a new tourist spot with its own unique QR, or attach a QR to an existing spot that still needs one. Spots with a saved QR cannot get another.',
                      style: GoogleFonts.inter(
                        color: _textMuted,
                        fontSize: 13,
                        height: 1.35,
                      ),
                    ),
                    const SizedBox(height: 14),
                    SegmentedButton<bool>(
                      segments: const [
                        ButtonSegment<bool>(
                          value: true,
                          label: Text('New spot'),
                          icon: Icon(Icons.add_location_alt_outlined, size: 18),
                        ),
                        ButtonSegment<bool>(
                          value: false,
                          label: Text('Existing'),
                          icon: Icon(Icons.list_alt_rounded, size: 18),
                        ),
                      ],
                      selected: {createNewSpot},
                      onSelectionChanged: saving
                          ? null
                          : (s) => setDialogState(() {
                                createNewSpot = s.first;
                              }),
                      style: ButtonStyle(
                        foregroundColor:
                            WidgetStateProperty.resolveWith((states) {
                          if (states.contains(WidgetState.selected)) {
                            return Colors.white;
                          }
                          return _textDark;
                        }),
                        backgroundColor:
                            WidgetStateProperty.resolveWith((states) {
                          if (states.contains(WidgetState.selected)) {
                            return _primaryOrange;
                          }
                          return Colors.white;
                        }),
                      ),
                    ),
                    const SizedBox(height: 16),
                    if (createNewSpot) ...[
                      _buildDialogTextField(
                        nameController,
                        'Tourist Spot Name',
                        Icons.place_rounded,
                        hintText: 'e.g. Rizal Park Viewpoint',
                      ),
                      const SizedBox(height: 14),
                      InputDecorator(
                        decoration: InputDecoration(
                          labelText: 'Category (optional)',
                          filled: true,
                          fillColor: const Color(0xFFF9FAFB),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide(color: _panelBorder),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide(color: _panelBorder),
                          ),
                        ),
                        child: DropdownButtonHideUnderline(
                          child: DropdownButton<String>(
                            value: selectedCategory,
                            isExpanded: true,
                            items: _categories
                                .where((c) => c != 'All')
                                .map(
                                  (c) => DropdownMenuItem(
                                    value: c,
                                    child: Text(c),
                                  ),
                                )
                                .toList(),
                            onChanged: saving
                                ? null
                                : (v) {
                                    if (v == null) return;
                                    setDialogState(
                                      () => selectedCategory = v,
                                    );
                                  },
                          ),
                        ),
                      ),
                      const SizedBox(height: 14),
                      _buildDialogTextField(
                        descriptionController,
                        'Description (optional)',
                        Icons.description_outlined,
                        maxLines: 3,
                      ),
                      const SizedBox(height: 14),
                      _buildSpotGpsFields(
                        latController: latController,
                        lngController: lngController,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Saved under $municipalityDisplayName only.',
                        style: GoogleFonts.inter(
                          color: _textMuted,
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ] else if (candidates.isEmpty) ...[
                      Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: _tintOrange,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: _primaryOrange.withValues(alpha: 0.25),
                          ),
                        ),
                        child: Text(
                          'All existing spots already have a saved QR. Switch to New spot to add another unique code.',
                          style: GoogleFonts.inter(
                            color: _textDark,
                            fontSize: 13,
                            height: 1.35,
                          ),
                        ),
                      ),
                    ] else ...[
                      InputDecorator(
                        decoration: InputDecoration(
                          labelText: 'Existing spot without QR',
                          filled: true,
                          fillColor: const Color(0xFFF9FAFB),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide(color: _panelBorder),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide(color: _panelBorder),
                          ),
                        ),
                        child: DropdownButtonHideUnderline(
                          child: DropdownButton<TouristSpot>(
                            value: selectedExisting,
                            isExpanded: true,
                            items: candidates
                                .map(
                                  (s) => DropdownMenuItem(
                                    value: s,
                                    child: Text(
                                      s.name,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                )
                                .toList(),
                            onChanged: saving
                                ? null
                                : (v) => setDialogState(
                                      () => selectedExisting = v,
                                    ),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed:
                    saving ? null : () => Navigator.pop(dialogContext),
                child: const Text(
                  'Cancel',
                  style: TextStyle(color: _textMuted),
                ),
              ),
              ElevatedButton.icon(
                onPressed: !generateEnabled
                    ? null
                    : () async {
                        if (createNewSpot) {
                          final name = nameController.text.trim();
                          if (name.isEmpty) {
                            ScaffoldMessenger.of(this.context).showSnackBar(
                              const SnackBar(
                                content: Text(
                                  'Tourist Spot Name is required.',
                                ),
                                backgroundColor: Colors.redAccent,
                              ),
                            );
                            return;
                          }
                          final coordError = _validateSpotCoordinates(
                            latController.text,
                            lngController.text,
                          );
                          if (coordError != null) {
                            ScaffoldMessenger.of(this.context).showSnackBar(
                              SnackBar(
                                content: Text(coordError),
                                backgroundColor: Colors.redAccent,
                              ),
                            );
                            return;
                          }
                          final lat = _tryParseCoord(latController.text)!;
                          final lng = _tryParseCoord(lngController.text)!;
                          final mid = normalizeMunicipalityId(municipalityId);
                          if (mid.isEmpty) {
                            ScaffoldMessenger.of(this.context).showSnackBar(
                              const SnackBar(
                                content: Text(
                                  'Could not determine your LGU municipality.',
                                ),
                                backgroundColor: Colors.redAccent,
                              ),
                            );
                            return;
                          }

                          setDialogState(() => saving = true);
                          final result =
                              await TouristSpotsFirestoreService.addSpotDetailed(
                            TouristSpot(
                              id: '',
                              name: name,
                              category: selectedCategory,
                              municipality: municipalityDisplayName,
                              description:
                                  descriptionController.text.trim(),
                              rating: 0,
                              latitude: lat,
                              longitude: lng,
                              status: 'Active',
                              visitors: 0,
                              municipalityId: mid,
                            ),
                          );
                          if (!dialogContext.mounted) return;
                          Navigator.pop(dialogContext);
                          if (!mounted) return;
                          if (result.ok) await _loadData();
                          if (!mounted) return;
                          ScaffoldMessenger.of(this.context).showSnackBar(
                            SnackBar(
                              content: Text(
                                result.ok
                                    ? 'Unique QR created for "$name"'
                                    : (result.error ??
                                        'Failed to create spot QR. Check Firebase.'),
                              ),
                              backgroundColor: result.ok
                                  ? _primaryOrange
                                  : Colors.redAccent,
                              behavior: SnackBarBehavior.floating,
                              duration: Duration(
                                seconds: result.ok ? 4 : 8,
                              ),
                            ),
                          );
                          return;
                        }

                        final spot = selectedExisting;
                        if (spot == null) return;
                        if ((spot.qrPayload ?? '').trim().isNotEmpty) {
                          ScaffoldMessenger.of(this.context).showSnackBar(
                            const SnackBar(
                              content: Text(
                                'This spot already has a saved QR. Pick another or create a new spot.',
                              ),
                              backgroundColor: Colors.redAccent,
                            ),
                          );
                          return;
                        }

                        setDialogState(() => saving = true);
                        final mid = normalizeMunicipalityId(
                          spot.municipalityId.isNotEmpty
                              ? spot.municipalityId
                              : municipalityId,
                        );
                        final ok =
                            await TouristSpotsFirestoreService.ensureSpotQrMetadata(
                          spotId: spot.id,
                          municipalityId:
                              mid.isNotEmpty ? mid : municipalityId,
                          latitude: spot.latitude,
                          longitude: spot.longitude,
                        );
                        if (!dialogContext.mounted) return;
                        Navigator.pop(dialogContext);
                        if (!mounted) return;
                        if (ok) await _loadData();
                        if (!mounted) return;
                        ScaffoldMessenger.of(this.context).showSnackBar(
                          SnackBar(
                            content: Text(
                              ok
                                  ? 'Unique QR generated for ${spot.name}'
                                  : 'Failed to generate QR. Check Firebase.',
                            ),
                            backgroundColor:
                                ok ? _primaryOrange : Colors.redAccent,
                            behavior: SnackBarBehavior.floating,
                          ),
                        );
                      },
                icon: saving
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.qr_code_2_rounded, size: 18),
                label: Text(
                  saving
                      ? 'Savingâ€¦'
                      : (createNewSpot ? 'Create & Generate' : 'Generate'),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: _primaryOrange,
                  foregroundColor: Colors.white,
                ),
              ),
            ],
          );
        },
      ),
    ).whenComplete(() {
      nameController.dispose();
      descriptionController.dispose();
      latController.dispose();
      lngController.dispose();
    });
  }

  Widget _buildSpotsFilters() {
    return Wrap(
      spacing: 16,
      runSpacing: 16,
      children: [
        SizedBox(
          width: _isMobile ? double.infinity : 300,
          child: AppSearchBar(
            controller: _spotsSearchController,
            hintText: 'Search spots...',
            onChanged: (value) => setState(() {}),
            horizontalPadding: 0,
            showMicrophone: false,
          ),
        ),
        SizedBox(
          width: _isMobile ? double.infinity : 160,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: _panelBorder),
            ),
            child: DropdownButton<String>(
              value: _spotCategoryFilter,
              isExpanded: true,
              borderRadius: BorderRadius.circular(12),
              dropdownColor: Colors.white,
              underline: const SizedBox(),
              icon: Icon(Icons.expand_more_rounded, color: _textDark, size: 22),
              style: const TextStyle(
                color: _textDark,
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
              items: _categories
                  .map(
                    (c) => DropdownMenuItem<String>(
                      value: c,
                      child: Text(
                        c,
                        style: const TextStyle(
                          color: _textDark,
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  )
                  .toList(),
              onChanged: (value) =>
                  setState(() => _spotCategoryFilter = value!),
            ),
          ),
        ),
        SizedBox(
          width: _isMobile ? double.infinity : 160,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: _panelBorder),
            ),
            child: DropdownButton<String>(
              value: _spotVrFilter,
              isExpanded: true,
              borderRadius: BorderRadius.circular(12),
              dropdownColor: Colors.white,
              underline: const SizedBox(),
              icon: Icon(Icons.expand_more_rounded, color: _textDark, size: 22),
              style: const TextStyle(
                color: _textDark,
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
              items: const [
                DropdownMenuItem(value: 'All', child: Text('All VR')),
                DropdownMenuItem(value: 'With VR', child: Text('With VR')),
                DropdownMenuItem(
                  value: 'Without VR',
                  child: Text('Without VR'),
                ),
              ],
              onChanged: (value) => setState(() => _spotVrFilter = value!),
            ),
          ),
        ),
        ElevatedButton.icon(
          onPressed: _showAddSpotDialog,
          icon: const Icon(Icons.add, size: 18),
          label: const Text('Add Spot'),
          style: ElevatedButton.styleFrom(
            backgroundColor: _primaryOrange,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSpotsGridMobile(List<TouristSpot> spots) {
    return Column(
      children: spots
          .map(
            (s) => Container(
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.grey.shade50,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Text(
                          s.name,
                          style: const TextStyle(
                            color: _textDark,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      _buildStatusBadge(s.status),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.blue.withOpacity(0.15),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          s.category,
                          style: const TextStyle(
                            color: Colors.blue,
                            fontSize: 11,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(s.municipality, style: TextStyle(color: _textMuted)),
                    ],
                  ),
                  const SizedBox(height: 8),
                  _buildSpotVrBadge(s),
                  const SizedBox(height: 12),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: _buildSpotActionButtons(s),
                  ),
                ],
              ),
            ),
          )
          .toList(),
    );
  }

  Widget _buildSpotsTable(List<TouristSpot> spots) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: DataTable(
        headingRowColor: WidgetStateProperty.all(Colors.grey.shade100),
        dataTextStyle: const TextStyle(color: _textDark, fontSize: 13),
        dividerThickness: 0,
        columns: const [
          DataColumn(
            label: Text(
              'Spot Name',
              style: TextStyle(
                color: _textDark,
                fontWeight: FontWeight.w700,
                fontSize: 13,
              ),
            ),
          ),
          DataColumn(
            label: Text(
              'Category',
              style: TextStyle(
                color: _textDark,
                fontWeight: FontWeight.w700,
                fontSize: 13,
              ),
            ),
          ),
          DataColumn(
            label: Text(
              'Location',
              style: TextStyle(
                color: _textDark,
                fontWeight: FontWeight.w700,
                fontSize: 13,
              ),
            ),
          ),
          DataColumn(
            label: Text(
              'Visitors',
              style: TextStyle(
                color: _textDark,
                fontWeight: FontWeight.w700,
                fontSize: 13,
              ),
            ),
          ),
          DataColumn(
            label: Text(
              'VR',
              style: TextStyle(
                color: _textDark,
                fontWeight: FontWeight.w700,
                fontSize: 13,
              ),
            ),
          ),
          DataColumn(
            label: Text(
              'Status',
              style: TextStyle(
                color: _textDark,
                fontWeight: FontWeight.w700,
                fontSize: 13,
              ),
            ),
          ),
          DataColumn(
            label: Text(
              'Actions',
              style: TextStyle(
                color: _textDark,
                fontWeight: FontWeight.w700,
                fontSize: 13,
              ),
            ),
          ),
        ],
        rows: spots
            .map(
              (s) => DataRow(
                cells: [
                  DataCell(
                    Text(
                      s.name,
                      style: const TextStyle(
                        color: _textDark,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  DataCell(
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.blue.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        s.category,
                        style: const TextStyle(
                          color: Colors.blue,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ),
                  DataCell(
                    Text(
                      s.municipality,
                      style: const TextStyle(color: _textDark),
                    ),
                  ),
                  DataCell(
                    Text(
                      '${s.visitors}',
                      style: const TextStyle(
                        color: _textDark,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  DataCell(_buildSpotVrBadge(s)),
                  DataCell(_buildStatusBadge(s.status)),
                  DataCell(Row(children: _buildSpotActionButtons(s))),
                ],
              ),
            )
            .toList(),
      ),
    );
  }

  void _showAddSpotDialog() {
    final normalizedStored = normalizeMunicipalityId(_storedMunicipalityId);
    final lockMunicipality = normalizedStored.isNotEmpty;
    final initialCity = lockMunicipality
        ? (_municipalityName ?? _storedMunicipalityId ?? '').trim()
        : '';
    final nameController = TextEditingController();
    final cityController = TextEditingController(text: initialCity);
    final descriptionController = TextEditingController();
    final imageUrlController = TextEditingController();
    final vrLinkController = TextEditingController();
    final dotCodeController = TextEditingController();
    final latController = TextEditingController();
    final lngController = TextEditingController();
    String selectedCategory = 'Beach';

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(minWidth: 440, maxWidth: 520),
            child: AlertDialog(
              backgroundColor: _cardBg,
              title: Text(
                'Add Tourist Spot',
                style: TextStyle(
                  color: _textDark,
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _buildDialogTextField(
                      nameController,
                      'Spot Name',
                      Icons.place,
                    ),
                    const SizedBox(height: 16),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      decoration: BoxDecoration(
                        color: Colors.grey.shade200,
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: DropdownButton<String>(
                        value: selectedCategory,
                        isExpanded: true,
                        dropdownColor: _cardBg,
                        underline: const SizedBox(),
                        style: TextStyle(color: _textDark, fontSize: 16),
                        items: _categories
                            .where((c) => c != 'All')
                            .map(
                              (c) => DropdownMenuItem(value: c, child: Text(c)),
                            )
                            .toList(),
                        onChanged: (value) =>
                            setDialogState(() => selectedCategory = value!),
                      ),
                    ),
                    const SizedBox(height: 16),
                    if (lockMunicipality) ...[
                      _buildDialogTextField(
                        cityController,
                        'City/Municipality',
                        Icons.location_city,
                        readOnly: true,
                      ),
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Text(
                          'This spot is created under your LGU.',
                          style: TextStyle(color: _textMuted, fontSize: 12),
                        ),
                      ),
                    ] else
                      _buildDialogTextField(
                        cityController,
                        'City/Municipality',
                        Icons.location_city,
                      ),
                    const SizedBox(height: 16),
                    _buildDialogTextField(
                      descriptionController,
                      'Description',
                      Icons.description,
                      maxLines: 3,
                    ),
                    const SizedBox(height: 16),
                    _buildDialogTextField(
                      imageUrlController,
                      'Image URL (optional)',
                      Icons.image,
                    ),
                    const SizedBox(height: 16),
                    _buildDialogTextField(
                      vrLinkController,
                      'VR Tour URL (only place to set VR)',
                      Icons.vrpano,
                      hintText: 'https://tiiny.host/? or your published tiiny.site URL',
                    ),
                    const SizedBox(height: 16),
                    _buildDialogTextField(
                      dotCodeController,
                      'DOT Attraction Code (VAR 2, optional)',
                      Icons.tag_rounded,
                      hintText: 'e.g. 202, 108, 414',
                    ),
                    const SizedBox(height: 16),
                    _buildSpotGpsFields(
                      latController: latController,
                      lngController: lngController,
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text(
                    'Cancel',
                    style: TextStyle(color: _textMuted),
                  ),
                ),
                ElevatedButton(
                  onPressed: () async {
                    if (nameController.text.isEmpty ||
                        cityController.text.trim().isEmpty) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Please fill required fields'),
                          backgroundColor: Colors.redAccent,
                        ),
                      );
                      return;
                    }

                    final coordError = _validateSpotCoordinates(
                      latController.text,
                      lngController.text,
                    );
                    if (coordError != null) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(coordError),
                          backgroundColor: Colors.redAccent,
                        ),
                      );
                      return;
                    }
                    final lat = _tryParseCoord(latController.text)!;
                    final lng = _tryParseCoord(lngController.text)!;

                    final cityTrim = cityController.text.trim();
                    String municipalityId = normalizedStored;
                    if (municipalityId.isEmpty) {
                      municipalityId = getMunicipalityIdFromName(cityTrim);
                    }
                    if (municipalityId.isEmpty) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text(
                            'Could not determine municipality. Enter a city from the list or sign in with an LGU account.',
                          ),
                          backgroundColor: Colors.redAccent,
                        ),
                      );
                      return;
                    }

                    final spot = TouristSpot(
                      id: '',
                      name: nameController.text.trim(),
                      category: selectedCategory,
                      municipality: cityTrim,
                      description: descriptionController.text.trim(),
                      rating: 0,
                      latitude: lat,
                      longitude: lng,
                      imageUrl: imageUrlController.text.trim().isNotEmpty
                          ? imageUrlController.text.trim()
                          : null,
                      vrLink: vrLinkController.text.trim().isNotEmpty
                          ? vrLinkController.text.trim()
                          : null,
                      status: 'Active',
                      visitors: 0,
                      municipalityId: municipalityId,
                      dotAttractionCode: dotCodeController.text.trim(),
                    );
                    final result =
                        await TouristSpotsFirestoreService.addSpotDetailed(
                      spot,
                    );
                    final docId = result.id;
                    if (docId != null &&
                        spot.vrLink != null &&
                        spot.vrLink!.isNotEmpty) {
                      await VrTourFirestoreService.syncAnalyticsDocForSpot(
                        spotId: docId,
                        spotName: spot.name,
                        vrUrl: spot.vrLink!,
                        municipalityId: municipalityId,
                      );
                    }
                    if (docId != null) await _loadData();
                    Navigator.pop(context);
                    if (docId != null && mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                            'Tourist spot added. A unique QR was created for "${nameController.text.trim()}".',
                          ),
                          backgroundColor: _primaryOrange,
                          behavior: SnackBarBehavior.floating,
                          action: SnackBarAction(
                            label: 'View QR',
                            textColor: Colors.white,
                            onPressed: () {
                              setState(() => _selectedIndex = _spotQRCodesIndex);
                            },
                          ),
                        ),
                      );
                    } else if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                            result.error ??
                                'Failed to add spot. Check Firebase.',
                          ),
                          backgroundColor: Colors.redAccent,
                          behavior: SnackBarBehavior.floating,
                          duration: const Duration(seconds: 8),
                        ),
                      );
                    }
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _primaryOrange,
                  ),
                  child: const Text('Add'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _showEditSpotDialog(TouristSpot spot) {
    final nameController = TextEditingController(text: spot.name);
    final cityController = TextEditingController(text: spot.municipality);
    final descriptionController = TextEditingController(text: spot.description);
    final imageUrlController = TextEditingController(text: spot.imageUrl ?? '');
    final vrLinkController = TextEditingController(text: spot.vrLink ?? '');
    final dotCodeController = TextEditingController(text: spot.dotAttractionCode);
    final latController = TextEditingController(
      text: _formatCoordForField(spot.latitude),
    );
    final lngController = TextEditingController(
      text: _formatCoordForField(spot.longitude),
    );
    String selectedCategory = spot.category;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(minWidth: 440, maxWidth: 520),
            child: AlertDialog(
              backgroundColor: _cardBg,
              title: Text(
                'Edit Tourist Spot',
                style: TextStyle(
                  color: _textDark,
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _buildDialogTextField(
                      nameController,
                      'Spot Name',
                      Icons.place,
                    ),
                    const SizedBox(height: 16),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      decoration: BoxDecoration(
                        color: Colors.grey.shade200,
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: DropdownButton<String>(
                        value: selectedCategory,
                        isExpanded: true,
                        dropdownColor: _cardBg,
                        underline: const SizedBox(),
                        style: TextStyle(color: _textDark, fontSize: 16),
                        items: _categories
                            .where((c) => c != 'All')
                            .map(
                              (c) => DropdownMenuItem(value: c, child: Text(c)),
                            )
                            .toList(),
                        onChanged: (value) =>
                            setDialogState(() => selectedCategory = value!),
                      ),
                    ),
                    const SizedBox(height: 16),
                    _buildDialogTextField(
                      cityController,
                      'City/Municipality',
                      Icons.location_city,
                    ),
                    const SizedBox(height: 16),
                    _buildDialogTextField(
                      descriptionController,
                      'Description',
                      Icons.description,
                      maxLines: 3,
                    ),
                    const SizedBox(height: 16),
                    _buildDialogTextField(
                      imageUrlController,
                      'Image URL',
                      Icons.image,
                    ),
                    const SizedBox(height: 16),
                    _buildDialogTextField(
                      vrLinkController,
                      'VR Tour URL',
                      Icons.vrpano,
                      hintText: 'https://tiiny.host/? or your published tiiny.site URL',
                    ),
                    const SizedBox(height: 16),
                    _buildDialogTextField(
                      dotCodeController,
                      'DOT Attraction Code (VAR 2)',
                      Icons.tag_rounded,
                      hintText: 'e.g. 202, 108, 414',
                    ),
                    const SizedBox(height: 16),
                    _buildSpotGpsFields(
                      latController: latController,
                      lngController: lngController,
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text(
                    'Cancel',
                    style: TextStyle(color: _textMuted),
                  ),
                ),
                ElevatedButton(
                  onPressed: () async {
                    final coordError = _validateSpotCoordinates(
                      latController.text,
                      lngController.text,
                    );
                    if (coordError != null) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(coordError),
                          backgroundColor: Colors.redAccent,
                        ),
                      );
                      return;
                    }
                    final lat = _tryParseCoord(latController.text)!;
                    final lng = _tryParseCoord(lngController.text)!;

                    final cityTrim = cityController.text.trim();
                    var municipalityId = spot.municipalityId;
                    if (cityTrim.isNotEmpty) {
                      final fromCity = getMunicipalityIdFromName(cityTrim);
                      if (fromCity.isNotEmpty) municipalityId = fromCity;
                    }
                    final ok =
                        await TouristSpotsFirestoreService.updateSpot(spot.id, {
                          'name': nameController.text.trim(),
                          'category': selectedCategory,
                          'municipality': cityTrim,
                          'description': descriptionController.text.trim(),
                          'latitude': lat,
                          'longitude': lng,
                          'image_url': imageUrlController.text.trim().isNotEmpty
                              ? imageUrlController.text.trim()
                              : null,
                          'vr_link': vrLinkController.text.trim().isNotEmpty
                              ? vrLinkController.text.trim()
                              : null,
                          'dotAttractionCode':
                              dotCodeController.text.trim().isNotEmpty
                                  ? dotCodeController.text.trim()
                                  : null,
                          if (municipalityId.isNotEmpty)
                            'municipalityId': municipalityId,
                          'qrValue': spot.id,
                          'qr_payload': spotQrData(
                            municipalityId,
                            spot.id,
                            latitude: lat,
                            longitude: lng,
                          ),
                          'hasVR': vrLinkController.text.trim().isNotEmpty,
                        });
                    if (ok) {
                      final vr = vrLinkController.text.trim();
                      if (vr.isNotEmpty) {
                        await VrTourFirestoreService.syncAnalyticsDocForSpot(
                          spotId: spot.id,
                          spotName: nameController.text.trim(),
                          vrUrl: vr,
                          municipalityId: municipalityId,
                        );
                      } else {
                        await VrTourFirestoreService.clearVrLinkForSpot(
                          spot.id,
                        );
                      }
                      await _loadData();
                    }
                    Navigator.pop(context);
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                            ok
                                ? 'Tourist spot updated successfully'
                                : 'Failed to update. Check Firebase.',
                          ),
                          backgroundColor: ok
                              ? _primaryOrange
                              : Colors.redAccent,
                        ),
                      );
                    }
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _primaryOrange,
                  ),
                  child: const Text('Save'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _showDeleteSpotDialog(TouristSpot spot) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: _cardBg,
        title: const Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: Colors.redAccent),
            SizedBox(width: 12),
            Text('Delete Spot', style: TextStyle(color: Colors.white)),
          ],
        ),
        content: Text(
          'Are you sure you want to delete "${spot.name}"? This action cannot be undone.',
          style: const TextStyle(color: _textMuted),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel', style: TextStyle(color: _textMuted)),
          ),
          ElevatedButton(
            onPressed: () async {
              final ok = await TouristSpotsFirestoreService.deleteSpot(spot.id);
              Navigator.pop(context);
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      ok
                          ? 'Tourist spot deleted'
                          : 'Failed to delete. Check Firebase.',
                    ),
                    backgroundColor: ok ? Colors.redAccent : Colors.redAccent,
                  ),
                );
              }
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  void _toggleSpotStatus(TouristSpot spot) async {
    final newStatus = spot.status == 'Active' ? 'Inactive' : 'Active';
    final ok = await TouristSpotsFirestoreService.updateSpotStatus(
      spot.id,
      newStatus,
    );
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            ok
                ? 'Spot ${spot.status == 'Active' ? 'deactivated' : 'activated'}'
                : 'Failed to update status. Check Firebase.',
          ),
          backgroundColor: ok ? _primaryOrange : Colors.redAccent,
        ),
      );
    }
  }

  double? _tryParseCoord(String raw) {
    final t = raw.trim().replaceAll(',', '.');
    return double.tryParse(t);
  }

  String? _validateSpotCoordinates(String latRaw, String lngRaw) {
    if (latRaw.trim().isEmpty || lngRaw.trim().isEmpty) {
      return 'Latitude and longitude are required so tourists can check in on site.';
    }
    final lat = _tryParseCoord(latRaw);
    final lng = _tryParseCoord(lngRaw);
    if (lat == null || lng == null) {
      return 'Enter valid numbers (e.g. 8.486000 and 123.804800).';
    }
    if (lat.abs() <= 1e-7 && lng.abs() <= 1e-7) {
      return 'Coordinates cannot be 0,0. Copy from Google Maps at the tourist spot.';
    }
    if (lat < -90 || lat > 90) {
      return 'Latitude must be between -90 and 90.';
    }
    if (lng < -180 || lng > 180) {
      return 'Longitude must be between -180 and 180.';
    }
    return null;
  }

  String _formatCoordForField(double value) {
    if (value.abs() <= 1e-7) return '';
    return value.toStringAsFixed(6);
  }

  Widget _buildSpotGpsFields({
    required TextEditingController latController,
    required TextEditingController lngController,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'GPS coordinates (required for QR check-in)',
          style: TextStyle(
            color: _textMuted,
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'In Google Maps: long-press the spot ? copy coordinates. '
          'Tourists must be within about 5 m to scan.',
          style: TextStyle(color: _textMuted, fontSize: 11, height: 1.35),
        ),
        const SizedBox(height: 12),
        _buildDialogTextField(
          latController,
          'Latitude',
          Icons.my_location,
          keyboardType: const TextInputType.numberWithOptions(
            decimal: true,
            signed: true,
          ),
          hintText: 'e.g. 8.486000',
        ),
        const SizedBox(height: 16),
        _buildDialogTextField(
          lngController,
          'Longitude',
          Icons.explore_outlined,
          keyboardType: const TextInputType.numberWithOptions(
            decimal: true,
            signed: true,
          ),
          hintText: 'e.g. 123.804800',
        ),
      ],
    );
  }

  Widget _buildDialogTextField(
    TextEditingController controller,
    String label,
    IconData icon, {
    int maxLines = 1,
    bool readOnly = false,
    TextInputType? keyboardType,
    String? hintText,
  }) {
    return TextField(
      controller: controller,
      maxLines: maxLines,
      readOnly: readOnly,
      keyboardType: keyboardType,
      decoration: InputDecoration(
        labelText: label,
        hintText: hintText,
        labelStyle: TextStyle(color: _textMuted),
        hintStyle: TextStyle(color: _textMuted.withValues(alpha: 0.7)),
        prefixIcon: Icon(icon, color: _primaryOrange),
        filled: true,
        fillColor: Colors.grey.shade200,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide.none,
        ),
      ),
      style: TextStyle(color: _textDark, fontSize: 16),
    );
  }

  // ==================== TOURISTS SECTION ====================
  /// Prefer Storage URL (new signups); fall back to legacy base64 in Firestore.
  ImageProvider? _touristAvatarImage(Map<String, dynamic> t) {
    final url = t['profilePhotoUrl']?.toString().trim();
    if (url != null && url.isNotEmpty) {
      return NetworkImage(url);
    }
    final b64 = t['profileImageBase64']?.toString();
    if (b64 != null && b64.isNotEmpty) {
      try {
        return MemoryImage(base64Decode(b64));
      } catch (_) {}
    }
    return null;
  }

  List<Map<String, dynamic>> _sortedTouristsByRegistrationDate(
    List<Map<String, dynamic>> tourists,
  ) {
    final sorted = List<Map<String, dynamic>>.from(tourists)
      ..sort((a, b) {
        final aDt = _registeredDateTimeNullableFromTourist(a);
        final bDt = _registeredDateTimeNullableFromTourist(b);
        if (aDt == null && bDt == null) return 0;
        if (aDt == null) return 1;
        if (bDt == null) return -1;
        return bDt.compareTo(aDt); // newest registration first
      });
    return sorted;
  }

  Widget _buildLguTouristsSummaryBar(int visibleCount) {
    final munLabel =
        (_municipalityName ?? _storedMunicipalityId ?? 'Your LGU').trim();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: _primaryOrange.withValues(alpha: 0.1),
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
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '$visibleCount of ${_tourists.length} registered tourists',
                  style: const TextStyle(
                    color: _textDark,
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                  ),
                ),
                const Text(
                  'Unique people Â· names hidden',
                  style: TextStyle(color: _textMuted, fontSize: 11),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: const Color(0xFFECFDF3),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: const Color(0xFF86EFAC)),
            ),
            child: const Text(
              'Privacy on',
              style: TextStyle(
                color: Color(0xFF15803D),
                fontSize: 11,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: const Color(0xFFDCFCE7),
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: const Color(0xFF86EFAC)),
            ),
            child: Text(
              munLabel,
              style: const TextStyle(
                color: Color(0xFF15803D),
                fontWeight: FontWeight.w700,
                fontSize: 11,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTouristsContent() {
    final filteredTourists = _tourists.where((t) {
      final searchQuery = _touristsSearchController.text.toLowerCase();
      final id = TouristIdHelper.displayForTourist(t);
      final origin = t['city']?.toString() ?? t['origin']?.toString() ?? '';
      return searchQuery.isEmpty ||
          id.toLowerCase().contains(searchQuery) ||
          origin.toLowerCase().contains(searchQuery);
    }).toList();

    final munLabel =
        (_municipalityName ?? _storedMunicipalityId ?? 'your municipality')
            .trim();

    return RefreshIndicator(
      onRefresh: _loadData,
      color: _primaryOrange,
      child: _buildFramedContentShell(
        title: 'Registered Tourists',
        subtitle: _storedMunicipalityId != null
            ? '$munLabel â€” unique registrations, names hidden for data privacy'
            : 'Assign an LGU municipality to your account to see tourists who '
                'registered here. Province-wide list is on the Governor dashboard.',
        body: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: EdgeInsets.all(_isMobile ? 12 : 16),
          child: _wrapTourismPanel(
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildLguTouristsSummaryBar(filteredTourists.length),
                const SizedBox(height: 12),
                _buildTouristsFilters(),
                const SizedBox(height: 16),
                if (filteredTourists.isEmpty)
                  _buildEmptyState(
                    _storedMunicipalityId != null
                        ? 'No registered tourists yet'
                        : 'No tourists loaded',
                    icon: Icons.people_alt_rounded,
                    iconColor: _primaryOrange,
                    subtitle: _storedMunicipalityId != null
                        ? 'Tourists who register via your municipality QR '
                            '(or select this city) appear here â€” IDs only, '
                            'same privacy as Governor.'
                        : 'Assign your LGU municipality to load registered tourists.',
                  )
                else if (_isMobile)
                  _buildTouristsListMobile(filteredTourists)
                else
                  _buildTouristsTable(filteredTourists),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTouristsFilters() {
    return Wrap(
      spacing: 16,
      runSpacing: 16,
      children: [
        SizedBox(
          width: _isMobile ? double.infinity : 380,
          child: AppSearchBar(
            controller: _touristsSearchController,
            hintText: 'Search by Tourist ID or origin...',
            onChanged: (value) => setState(() {}),
            horizontalPadding: 0,
            showMicrophone: false,
          ),
        ),
        ElevatedButton.icon(
          onPressed: _exportTouristsData,
          icon: _isExporting
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : const Icon(Icons.download_rounded, size: 18),
          label: Text(
            _isExporting
                ? 'Exporting... ${(_exportProgress * 100).toInt()}%'
                : 'Export',
          ),
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF0EA5E9),
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(999),
            ),
            elevation: 2,
            shadowColor: const Color(0xFF0EA5E9).withOpacity(0.35),
          ),
        ),
      ],
    );
  }

  Widget _buildTouristsListMobile(List<Map<String, dynamic>> tourists) {
    final sorted = _sortedTouristsByRegistrationDate(tourists);

    return Column(
      children: sorted.map((t) {
        final touristId = TouristIdHelper.displayForTourist(t);
        final origin = _getTouristOrigin(t);
        final visits = t['totalVisits'] ?? t['visits'] ?? 0;
        final isLocal = t['isLocal'] == true || t['localOrForeign'] == 'Local';

        return Container(
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.04),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: InkWell(
            onTap: () => _showTouristDetailsDialog(t),
            borderRadius: BorderRadius.circular(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    _buildVisitPrivacyAvatar(radius: 20),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _buildVisitTouristIdChip(touristId, maxWidth: 220),
                          const SizedBox(height: 4),
                          Text(
                            'From: $origin',
                            style: TextStyle(
                              color: _textMuted,
                              fontSize: 12,
                              fontStyle:
                                  origin == '?' ? FontStyle.italic : null,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: isLocal
                                ? Colors.green.withValues(alpha: 0.12)
                                : Colors.purple.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(28),
                          ),
                          child: Text(
                            isLocal ? 'Local' : 'Foreign',
                            style: TextStyle(
                              color: isLocal
                                  ? const Color(0xFF16A34A)
                                  : const Color(0xFF7C3AED),
                              fontSize: 11,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '$visits visits',
                          style: const TextStyle(
                            color: Color(0xFF0284C7),
                            fontSize: 11,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  'Date: ${_formatRegisteredDateOnlyDisplay(_registeredDateTimeNullableFromTourist(t))}',
                  style: const TextStyle(color: _textMuted, fontSize: 11),
                ),
                Text(
                  'Time: ${_formatRegisteredTimeOnlyDisplay(_registeredDateTimeNullableFromTourist(t))}',
                  style: const TextStyle(color: _textMuted, fontSize: 11),
                ),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildTouristsTable(List<Map<String, dynamic>> tourists) {
    final sorted = _sortedTouristsByRegistrationDate(tourists);

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 12,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: DataTable(
            headingRowColor: WidgetStateProperty.all(Colors.grey.shade50),
            headingTextStyle: const TextStyle(
              color: _textDark,
              fontWeight: FontWeight.w700,
              fontSize: 13,
            ),
            dataTextStyle: const TextStyle(color: _textDark, fontSize: 14),
            dividerThickness: 0,
            horizontalMargin: 20,
            columnSpacing: 28,
            columns: const [
              DataColumn(label: Text('Tourist ID')),
              DataColumn(label: Text('Type')),
              DataColumn(label: Text('Origin')),
              DataColumn(label: Text('Date')),
              DataColumn(label: Text('Time')),
              DataColumn(label: Text('Visits')),
              DataColumn(label: Text('Status')),
              DataColumn(label: Text('Actions')),
            ],
            rows: sorted.map((t) {
              final touristId = TouristIdHelper.displayForTourist(t);
              final origin = _getTouristOrigin(t);
              final visits = t['totalVisits'] ?? t['visits'] ?? 0;
              final regDt = _registeredDateTimeNullableFromTourist(t);
              final isLocal =
                  t['isLocal'] == true || t['localOrForeign'] == 'Local';
              final status = t['status']?.toString() ?? 'Active';

              return DataRow(
                cells: [
                  DataCell(
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _buildVisitPrivacyAvatar(radius: 16),
                        const SizedBox(width: 10),
                        _buildVisitTouristIdChip(touristId, maxWidth: 180),
                      ],
                    ),
                  ),
                  DataCell(
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 5,
                      ),
                      decoration: BoxDecoration(
                        color: isLocal
                            ? Colors.green.withValues(alpha: 0.12)
                            : Colors.purple.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(28),
                      ),
                      child: Text(
                        isLocal ? 'Local' : 'Foreign',
                        style: TextStyle(
                          color: isLocal
                              ? const Color(0xFF16A34A)
                              : const Color(0xFF7C3AED),
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ),
                  DataCell(
                    Text(
                      origin,
                      style: TextStyle(
                        color: origin == '?' ? _textMuted : _textDark,
                        fontSize: 13,
                        fontStyle: origin == '?' ? FontStyle.italic : null,
                      ),
                    ),
                  ),
                  DataCell(
                    Text(
                      _formatRegisteredDateOnlyDisplay(regDt),
                      style: const TextStyle(color: _textDark, fontSize: 13),
                    ),
                  ),
                  DataCell(
                    Text(
                      _formatRegisteredTimeOnlyDisplay(regDt),
                      style: const TextStyle(color: _textDark, fontSize: 13),
                    ),
                  ),
                  DataCell(
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 5,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFF0EA5E9).withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(28),
                      ),
                      child: Text(
                        '$visits',
                        style: const TextStyle(
                          color: Color(0xFF0284C7),
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                  DataCell(
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 5,
                      ),
                      decoration: BoxDecoration(
                        color: status == 'Active'
                            ? Colors.green.withValues(alpha: 0.12)
                            : Colors.red.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(28),
                      ),
                      child: Text(
                        status,
                        style: TextStyle(
                          color: status == 'Active'
                              ? const Color(0xFF16A34A)
                              : const Color(0xFFDC2626),
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ),
                  DataCell(
                    IconButton(
                      onPressed: () => _showTouristDetailsDialog(t),
                      icon: const Icon(
                        Icons.visibility_rounded,
                        color: Color(0xFF0EA5E9),
                        size: 20,
                      ),
                      tooltip: 'View Details',
                      style: IconButton.styleFrom(
                        backgroundColor: const Color(
                          0xFF0EA5E9,
                        ).withValues(alpha: 0.1),
                      ),
                    ),
                  ),
                ],
              );
            }).toList(),
          ),
        ),
      ),
    );
  }

  String _getTouristOrigin(Map<String, dynamic> t) {
    if (t['city'] != null && t['city'].toString().trim().isNotEmpty) {
      final parts = <String>[
        t['city'].toString().trim(),
        if (t['province'] != null && t['province'].toString().trim().isNotEmpty)
          t['province'].toString().trim(),
        if (t['country'] != null && t['country'].toString().trim().isNotEmpty)
          t['country'].toString().trim(),
      ];
      return parts.join(', ');
    }
    final origin = t['origin']?.toString().trim();
    if (origin != null && origin.isNotEmpty) return origin;
    final country = t['country']?.toString().trim();
    if (country != null && country.isNotEmpty) return country;
    final nationality = t['nationality']?.toString().trim();
    if (nationality != null && nationality.isNotEmpty) return nationality;
    return '?';
  }

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

  void _showTouristDetailsDialog(Map<String, dynamic> tourist) {
    final touristId = TouristIdHelper.displayForTourist(tourist);
    final isLocal =
        tourist['isLocal'] == true || tourist['localOrForeign'] == 'Local';
    final visits = tourist['totalVisits'] ?? tourist['visits'] ?? 0;
    final status = tourist['status']?.toString() ?? 'Active';
    final origin = _getTouristOrigin(tourist);

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: _cardBg,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            _buildVisitPrivacyAvatar(radius: 22),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Registered tourist',
                    style: TextStyle(
                      color: _textMuted,
                      fontWeight: FontWeight.w500,
                      fontSize: 12,
                    ),
                  ),
                  Text(
                    touristId,
                    style: const TextStyle(
                      color: _textDark,
                      fontWeight: FontWeight.w700,
                      fontSize: 16,
                      fontFamily: 'monospace',
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
                          color: isLocal
                              ? Colors.green.withValues(alpha: 0.15)
                              : Colors.purple.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          isLocal ? 'Local' : 'Foreign',
                          style: TextStyle(
                            color: isLocal ? Colors.green : Colors.purple,
                            fontSize: 10,
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: status == 'Active'
                              ? Colors.green.withValues(alpha: 0.15)
                              : Colors.red.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          status,
                          style: TextStyle(
                            color: status == 'Active'
                                ? Colors.green
                                : Colors.red,
                            fontSize: 10,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Name hidden for data privacy',
              style: TextStyle(color: _textMuted, fontSize: 12),
            ),
            const SizedBox(height: 12),
            _buildDetailRow('Tourist ID', touristId),
            _buildDetailRow('Origin', origin),
            _buildDetailRow('Total Visits', '$visits'),
            _buildDetailRow(
              'Date registered',
              _formatRegisteredDateOnlyDisplay(
                _registeredDateTimeNullableFromTourist(tourist),
              ),
            ),
            _buildDetailRow(
              'Time registered',
              _formatRegisteredTimeOnlyDisplay(
                _registeredDateTimeNullableFromTourist(tourist),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close', style: TextStyle(color: _textMuted)),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _confirmDeleteTouristAccount(tourist);
            },
            child: const Text(
              'Delete account',
              style: TextStyle(
                color: Color(0xFFDC2626),
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmDeleteTouristAccount(Map<String, dynamic> tourist) async {
    final touristId = TouristIdHelper.displayForTourist(tourist);
    final uid = TouristAccountAdminService.resolveTouristUid(tourist);
    if (uid == null || uid.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Cannot delete: tourist id is missing.'),
          backgroundColor: Color(0xFFDC2626),
        ),
      );
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: _cardBg,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text(
          'Delete tourist account?',
          style: TextStyle(color: _textDark, fontWeight: FontWeight.w700),
        ),
        content: Text(
          'This permanently removes tourist $touristId from ATMOS-TRS '
          '(profile, check-ins, and login). This cannot be undone.',
          style: const TextStyle(color: _textMuted, height: 1.4),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel', style: TextStyle(color: _textMuted)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFDC2626),
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    BuildContext? loadingDialogContext;
    unawaited(
      showDialog<void>(
        context: context,
        barrierDismissible: false,
        useRootNavigator: true,
        builder: (ctx) {
          loadingDialogContext = ctx;
          return const PopScope(
            canPop: false,
            child: Center(
              child: Card(
                child: Padding(
                  padding: EdgeInsets.all(24),
                  child: CircularProgressIndicator(color: _primaryOrange),
                ),
              ),
            ),
          );
        },
      ),
    );

    void closeLoadingDialog() {
      final dialogCtx = loadingDialogContext;
      if (dialogCtx != null && dialogCtx.mounted) {
        Navigator.of(dialogCtx).pop();
      }
    }

    try {
      final result =
          await TouristAccountAdminService.deleteTouristAccount(uid);
      if (!mounted) return;
      closeLoadingDialog();
      setState(() {
        _tourists = _tourists
            .where((t) {
              final id = TouristAccountAdminService.resolveTouristUid(t);
              return id != uid &&
                  !TouristAccountAdminService.isDeletedTouristRow(t);
            })
            .toList(growable: true);
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            result.authDeleted
                ? 'Deleted account for $touristId'
                : 'Removed $touristId from Registered Tourists.',
          ),
          backgroundColor: _primaryOrange,
        ),
      );
      unawaited(_loadData());
    } catch (e) {
      if (!mounted) return;
      closeLoadingDialog();
      final message = e is FirebaseFunctionsException
          ? TouristAccountAdminService.userFacingError(e)
          : e
              .toString()
              .replaceFirst('Bad state: ', '')
              .replaceFirst('Exception: ', '');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: const Color(0xFFDC2626),
        ),
      );
    }
  }

  DateTime? _registeredDateTimeNullableFromTourist(Map<String, dynamic> t) {
    final regAt = t['registeredAt'];
    if (regAt is Timestamp) return regAt.toDate();
    if (regAt is DateTime) return regAt;
    if (t['registeredDate'] is DateTime) return t['registeredDate'] as DateTime;
    final created = t['createdAt'] ?? t['created_at'];
    if (created is Timestamp) return created.toDate();
    if (created is DateTime) return created;
    return null;
  }

  String _buildTouristsExportCsv() {
    var csv =
        'Tourist ID,Full Name,Email,Mobile,Nationality,Type,Origin,Visits,Status,Registered Date,Registered Time\n';
    for (final t in _tourists) {
      final name = _getTouristDisplayName(t);
      final touristId = TouristIdHelper.displayForTourist(t);
      final email = t['email']?.toString() ?? '';
      final mobile = t['mobile']?.toString() ?? '';
      final nationality = t['nationality']?.toString() ?? '';
      final isLocal = t['isLocal'] == true || t['localOrForeign'] == 'Local';
      final origin = _getTouristOrigin(t);
      final visits = t['totalVisits'] ?? t['visits'] ?? 0;
      final status = t['status']?.toString() ?? 'Active';
      final regDt = _registeredDateTimeNullableFromTourist(t);
      final dateCsv = _formatRegisteredDateOnlyDisplay(regDt);
      final timeCsv = _formatRegisteredTimeOnlyDisplay(regDt);
      csv +=
          '$touristId,"$name",$email,$mobile,$nationality,${isLocal ? 'Local' : 'Foreign'},"$origin",$visits,$status,$dateCsv,$timeCsv\n';
    }
    return csv;
  }

  Future<void> _exportTouristsData() async {
    setState(() {
      _isExporting = true;
      _exportProgress = 0.0;
    });

    for (int i = 1; i <= 10; i++) {
      await Future.delayed(const Duration(milliseconds: 150));
      setState(() => _exportProgress = i / 10);
    }

    final csv = _buildTouristsExportCsv();

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('tourists_export', csv);

    setState(() => _isExporting = false);

    if (!mounted) return;
    _showTouristsExportOrganizedDialog(csv);
  }

  void _showTouristsExportOrganizedDialog(String csv) {
    final textStyle = TextStyle(color: _textDark, fontSize: 13);
    final headerStyle = TextStyle(
      color: _textDark,
      fontWeight: FontWeight.w700,
      fontSize: 12,
    );
    final rows = <DataRow>[];
    for (final t in _tourists) {
      final name = _getTouristDisplayName(t);
      final touristId = TouristIdHelper.displayForTourist(t);
      final email = t['email']?.toString() ?? '?';
      final mobile = t['mobile']?.toString() ?? '?';
      final nationality = t['nationality']?.toString() ?? '?';
      final isLocal = t['isLocal'] == true || t['localOrForeign'] == 'Local';
      final origin = _getTouristOrigin(t);
      final visits = '${t['totalVisits'] ?? t['visits'] ?? 0}';
      final status = t['status']?.toString() ?? 'Active';
      final regDt = _registeredDateTimeNullableFromTourist(t);
      final dateStr = _formatRegisteredDateOnlyDisplay(regDt);
      final timeStr = _formatRegisteredTimeOnlyDisplay(regDt);
      rows.add(
        DataRow(
          cells: [
            DataCell(Text(touristId, style: textStyle)),
            DataCell(Text(name, style: textStyle)),
            DataCell(Text(email, style: textStyle)),
            DataCell(Text(mobile, style: textStyle)),
            DataCell(Text(nationality, style: textStyle)),
            DataCell(Text(isLocal ? 'Local' : 'Foreign', style: textStyle)),
            DataCell(Text(origin, style: textStyle)),
            DataCell(Text(visits, style: textStyle)),
            DataCell(Text(status, style: textStyle)),
            DataCell(Text(dateStr, style: textStyle)),
            DataCell(Text(timeStr, style: textStyle)),
          ],
        ),
      );
    }

    final w = MediaQuery.of(context).size.width;
    final h = MediaQuery.of(context).size.height;

    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: _cardBg,
        insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
        title: Row(
          children: [
            Icon(Icons.table_chart_rounded, color: _primaryOrange, size: 26),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'Registered Tourists export',
                style: const TextStyle(
                  color: _textDark,
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
        content: SizedBox(
          width: w > 900 ? 880 : w * 0.92,
          height: h * 0.62,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                '${_tourists.length} record${_tourists.length == 1 ? '' : 's'} ? scroll horizontally for all columns',
                style: TextStyle(color: _textMuted, fontSize: 13),
              ),
              const SizedBox(height: 12),
              Expanded(
                child: _tourists.isEmpty
                    ? Center(
                        child: Text(
                          'No registered tourists to export.',
                          style: TextStyle(color: _textMuted, fontSize: 16),
                        ),
                      )
                    : Scrollbar(
                        thumbVisibility: true,
                        child: SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: SingleChildScrollView(
                            child: DataTable(
                              headingRowColor: WidgetStateProperty.all<Color>(
                                const Color(0xFFFFEDD5),
                              ),
                              dataRowMinHeight: 44,
                              horizontalMargin: 16,
                              columnSpacing: 20,
                              dividerThickness: 0,
                              border: const TableBorder(),
                              columns: [
                                DataColumn(
                                  label: Text('Tourist ID', style: headerStyle),
                                ),
                                DataColumn(
                                  label: Text('Full name', style: headerStyle),
                                ),
                                DataColumn(
                                  label: Text('Email', style: headerStyle),
                                ),
                                DataColumn(
                                  label: Text('Mobile', style: headerStyle),
                                ),
                                DataColumn(
                                  label: Text(
                                    'Nationality',
                                    style: headerStyle,
                                  ),
                                ),
                                DataColumn(
                                  label: Text('Type', style: headerStyle),
                                ),
                                DataColumn(
                                  label: Text('Origin', style: headerStyle),
                                ),
                                DataColumn(
                                  label: Text('Visits', style: headerStyle),
                                ),
                                DataColumn(
                                  label: Text('Status', style: headerStyle),
                                ),
                                DataColumn(
                                  label: Text('Date', style: headerStyle),
                                ),
                                DataColumn(
                                  label: Text('Time', style: headerStyle),
                                ),
                              ],
                              rows: rows,
                            ),
                          ),
                        ),
                      ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton.icon(
            onPressed: () async {
              final filename =
                  'tourists_export_${DateTime.now().toIso8601String().split('T').first}.csv';
              await downloadCsvFile(filename, csv);
              if (!context.mounted) return;
              Navigator.pop(ctx);
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                    csvDownloadUsesClipboard
                        ? 'CSV copied to clipboard ? paste into Excel or save as .csv'
                        : 'CSV file download started',
                  ),
                  backgroundColor: _primaryOrange,
                  behavior: SnackBarBehavior.floating,
                ),
              );
            },
            icon: Icon(Icons.download_rounded, color: _primaryOrange, size: 20),
            label: Text(
              'Download CSV',
              style: TextStyle(
                color: _primaryOrange,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('Close', style: TextStyle(color: _primaryOrange)),
          ),
        ],
      ),
    );
  }

  // ==================== ANALYTICS (LGU-scoped) ====================
  /// 0 = Overview (insights + charts), 1 = DOT exports
  int _analyticsTab = 0;

  Widget _buildAnalyticsContent() {
    final city = (_municipalityName ?? _storedMunicipalityId ?? 'your LGU').trim();
    final subtitle = _municipalityName != null
        ? '$city — insights and municipal DOT exports'
        : 'Insights and municipal DOT exports from loaded check-ins';

    return RefreshIndicator(
      onRefresh: _loadData,
      color: _primaryOrange,
      child: _buildFramedContentShell(
        title: 'Analytics',
        subtitle: subtitle,
        actions: [
          if (_analyticsTab == 0)
            Tooltip(
              message: 'Save an image of analytics (key insights and charts)',
              child: IconButton(
                onPressed: _reportsScreenshotBusy
                    ? null
                    : _captureReportsSectionScreenshot,
                icon: _reportsScreenshotBusy
                    ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: _primaryOrange,
                        ),
                      )
                    : const Icon(Icons.screenshot_monitor_outlined),
                color: Colors.white,
              ),
            ),
        ],
        body: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: EdgeInsets.fromLTRB(
                _isMobile ? 16 : 24,
                16,
                _isMobile ? 16 : 24,
                0,
              ),
              child: _buildAnalyticsSegmentTabs(),
            ),
            Expanded(
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 220),
                switchInCurve: Curves.easeOut,
                switchOutCurve: Curves.easeIn,
                child: _analyticsTab == 0
                    ? KeyedSubtree(
                        key: const ValueKey('analytics-overview'),
                        child: _buildAnalyticsOverviewScroll(city),
                      )
                    : KeyedSubtree(
                        key: const ValueKey('analytics-exports'),
                        child: _buildAnalyticsExportsScroll(),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAnalyticsSegmentTabs() {
    Widget chip(String label, IconData icon, int index) {
      final selected = _analyticsTab == index;
      return Expanded(
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: () => setState(() => _analyticsTab = index),
            borderRadius: BorderRadius.circular(12),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              padding: const EdgeInsets.symmetric(vertical: 11, horizontal: 10),
              decoration: BoxDecoration(
                color: selected ? _primaryOrange : Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: selected ? _primaryOrange : _panelBorder,
                ),
                boxShadow: selected
                    ? [
                        BoxShadow(
                          color: _primaryOrange.withValues(alpha: 0.22),
                          blurRadius: 10,
                          offset: const Offset(0, 4),
                        ),
                      ]
                    : null,
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    icon,
                    size: 17,
                    color: selected ? Colors.white : _textMuted,
                  ),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      label,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: selected ? Colors.white : _textDark,
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
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

    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: const Color(0xFFF3F4F6),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          chip('Overview', Icons.insights_rounded, 0),
          const SizedBox(width: 6),
          chip('DOT exports', Icons.description_outlined, 1),
        ],
      ),
    );
  }

  Widget _buildAnalyticsOverviewScroll(String city) {
    return SingleChildScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: EdgeInsets.fromLTRB(
        _isMobile ? 16 : 24,
        16,
        _isMobile ? 16 : 24,
        28,
      ),
      child: RepaintBoundary(
        key: _reportsRepaintKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildAnalyticsIntroBanner(city),
            const SizedBox(height: 18),
            Text(
              'Key insights',
              style: GoogleFonts.poppins(
                color: _textDark,
                fontSize: 15,
                fontWeight: FontWeight.w700,
                letterSpacing: -0.2,
              ),
            ),
            const SizedBox(height: 4),
            const Text(
              'From check-ins and registrations in your municipality',
              style: TextStyle(color: _textMuted, fontSize: 12.5, height: 1.35),
            ),
            const SizedBox(height: 12),
            _buildLguAnalyticsCards(),
            const SizedBox(height: 22),
            Text(
              'Trends & rankings',
              style: GoogleFonts.poppins(
                color: _textDark,
                fontSize: 15,
                fontWeight: FontWeight.w700,
                letterSpacing: -0.2,
              ),
            ),
            const SizedBox(height: 4),
            const Text(
              'Visitor movement and most visited spots',
              style: TextStyle(color: _textMuted, fontSize: 12.5, height: 1.35),
            ),
            const SizedBox(height: 12),
            LayoutBuilder(
              builder: (context, constraints) {
                final sideBySide = !_isMobile && constraints.maxWidth >= 980;
                if (!sideBySide) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _buildLguVisitorTrendsChart(),
                      const SizedBox(height: 14),
                      _buildLguTopSpotsChart(),
                    ],
                  );
                }
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(flex: 5, child: _buildLguVisitorTrendsChart()),
                    const SizedBox(width: 14),
                    Expanded(flex: 4, child: _buildLguTopSpotsChart()),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAnalyticsExportsScroll() {
    return SingleChildScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: EdgeInsets.fromLTRB(
        _isMobile ? 16 : 24,
        16,
        _isMobile ? 16 : 24,
        28,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Municipal DOT exports',
            style: GoogleFonts.poppins(
              color: _textDark,
              fontSize: 15,
              fontWeight: FontWeight.w700,
              letterSpacing: -0.2,
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            'Official Supabase templates filled from your LGU check-ins only',
            style: TextStyle(color: _textMuted, fontSize: 12.5, height: 1.35),
          ),
          const SizedBox(height: 14),
          _buildLguDotReportExports(),
        ],
      ),
    );
  }

  Widget _buildAnalyticsIntroBanner(String city) {
    final visits = _realCheckIns.length;
    final tourists = _realTouristsList.length;
    return Container(
      width: double.infinity,
      padding: EdgeInsets.fromLTRB(
        _isMobile ? 16 : 20,
        _isMobile ? 16 : 18,
        _isMobile ? 16 : 20,
        _isMobile ? 16 : 18,
      ),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color(0xFFFFF7ED),
            Color(0xFFFFEDD5),
            Color(0xFFFFF1E6),
          ],
        ),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: _primaryOrange.withValues(alpha: 0.22)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  city,
                  style: GoogleFonts.poppins(
                    color: _textDark,
                    fontSize: _isMobile ? 17 : 19,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.3,
                  ),
                ),
                const SizedBox(height: 4),
                const Text(
                  'Live snapshot of visits, origins, and spot performance',
                  style: TextStyle(
                    color: _textMuted,
                    fontSize: 12.5,
                    height: 1.35,
                  ),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _analyticsStatChip('$visits recent visits'),
                    _analyticsStatChip('$tourists registered'),
                    _analyticsStatChip(
                      '${_touristSpots.where((s) => s.status == 'Active').length} active spots',
                    ),
                  ],
                ),
              ],
            ),
          ),
          if (!_isMobile) ...[
            const SizedBox(width: 12),
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.85),
                borderRadius: BorderRadius.circular(14),
              ),
              child: const Icon(
                Icons.analytics_rounded,
                color: Color(0xFFEA580C),
                size: 26,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _analyticsStatChip(String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.88),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: _primaryOrange.withValues(alpha: 0.18)),
      ),
      child: Text(
        label,
        style: const TextStyle(
          color: Color(0xFF9A3412),
          fontSize: 11.5,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  Widget _buildLguDotReportExports() {
    final scopeName = (_municipalityName ?? _storedMunicipalityId ?? 'LGU')
        .trim();
    final scopeLabel = scopeName.toLowerCase().contains('misamis occidental')
        ? scopeName
        : '$scopeName, Misamis Occidental';
    final slug = normalizeMunicipalityId(_storedMunicipalityId);
    final catalog = _touristSpots
        .map(
          (s) => DotVar2SpotCatalogEntry(
            spotId: s.id,
            name: s.name,
            dotAttractionCode: s.dotAttractionCode,
          ),
        )
        .toList();

    return DotReportExportPanel(
      primaryColor: _primaryOrange,
      textDark: _textDark,
      textMuted: _textMuted,
      borderColor: _panelBorder,
      scopeLabel: scopeLabel,
      scopeSlug: slug.isEmpty ? 'lgu' : slug,
      isProvincial: false,
      isMobile: _isMobile,
      municipalityId: _storedMunicipalityId,
      checkIns: _realCheckIns,
      tourists: _tourists,
      catalogSpots: catalog,
      parseTimestamp: _parseCheckInTimestamp,
      wrapPanel: (child) => _wrapTourismPanel(child),
    );
  }

  Widget _buildLguAnalyticsCards() {
    final cards = [
      (
        title: 'Daily average',
        subtitle: 'Check-ins per active day',
        value: '$_lguAnalyticsDailyAvg',
        icon: Icons.calendar_today_rounded,
        accent: const Color(0xFF2563EB),
      ),
      (
        title: 'Peak hour',
        subtitle: 'Busiest QR scan window',
        value: _lguAnalyticsPeakHour,
        icon: Icons.access_time_rounded,
        accent: _primaryOrange,
      ),
      (
        title: 'Top origin',
        subtitle: 'Most common registration source',
        value: _lguAnalyticsTopOrigin,
        icon: Icons.flight_takeoff_rounded,
        accent: const Color(0xFF059669),
      ),
      (
        title: 'Active spots',
        subtitle: 'Tourist spots currently active',
        value:
            '${_touristSpots.where((s) => s.status == 'Active').length}',
        icon: Icons.place_rounded,
        accent: const Color(0xFF0F766E),
      ),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= 900;
        if (wide) {
          return Row(
            children: [
              for (var i = 0; i < cards.length; i++) ...[
                if (i > 0) const SizedBox(width: 12),
                Expanded(
                  child: _buildLguAnalyticsCard(
                    title: cards[i].title,
                    subtitle: cards[i].subtitle,
                    value: cards[i].value,
                    icon: cards[i].icon,
                    accent: cards[i].accent,
                  ),
                ),
              ],
            ],
          );
        }
        return Column(
          children: [
            for (var row = 0; row < 2; row++) ...[
              if (row > 0) const SizedBox(height: 10),
              Row(
                children: [
                  for (var col = 0; col < 2; col++) ...[
                    if (col > 0) const SizedBox(width: 10),
                    Expanded(
                      child: _buildLguAnalyticsCard(
                        title: cards[row * 2 + col].title,
                        subtitle: cards[row * 2 + col].subtitle,
                        value: cards[row * 2 + col].value,
                        icon: cards[row * 2 + col].icon,
                        accent: cards[row * 2 + col].accent,
                      ),
                    ),
                  ],
                ],
              ),
            ],
          ],
        );
      },
    );
  }

  Widget _buildLguAnalyticsCard({
    required String title,
    required String subtitle,
    required String value,
    required IconData icon,
    required Color accent,
  }) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _kAnalyticsSurfaceBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(11),
                ),
                child: Icon(icon, color: accent, size: 18),
              ),
              const Spacer(),
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: accent,
                  shape: BoxShape.circle,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Text(
            value,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: _textDark,
              fontSize: value.contains('\n') || value.length > 16 ? 17 : 24,
              fontWeight: FontWeight.w800,
              height: 1.12,
              letterSpacing: -0.4,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            title,
            style: const TextStyle(
              color: _textDark,
              fontSize: 13,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            subtitle,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: _textMuted,
              fontSize: 11.5,
              height: 1.3,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLguVisitorTrendsChart() {
    final values = _lguAnalyticsTrendValues;
    return Container(
      padding: EdgeInsets.all(_isMobile ? 14 : 18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _kAnalyticsSurfaceBorder),
        boxShadow: const [
          BoxShadow(
            color: Color(0x08000000),
            blurRadius: 12,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Visitor trends',
                      style: TextStyle(
                        color: _textDark,
                        fontSize: 14.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    SizedBox(height: 4),
                    Text(
                      'Visits per day Â· last 14 days',
                      style: TextStyle(
                        color: _textMuted,
                        fontSize: 12,
                        height: 1.35,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFF7ED),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.trending_up_rounded,
                      size: 14,
                      color: Color(0xFFC2410C),
                    ),
                    const SizedBox(width: 5),
                    Text(
                      'Total ${values.fold<double>(0, (a, b) => a + b).toStringAsFixed(0)}',
                      style: const TextStyle(
                        color: Color(0xFFC2410C),
                        fontSize: 11.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          _AnalyticsTrendChart(values: values, color: _primaryOrange),
        ],
      ),
    );
  }

  Widget _buildLguTopSpotsChart() {
    final spots = _lguAnalyticsTopSpots.take(8).toList();
    final maxVisits = spots.isEmpty ? 1 : (spots.first['visits'] as int);

    return Container(
      padding: EdgeInsets.all(_isMobile ? 14 : 18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _kAnalyticsSurfaceBorder),
        boxShadow: const [
          BoxShadow(
            color: Color(0x08000000),
            blurRadius: 12,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Most visited spots',
                  style: TextStyle(
                    color: _textDark,
                    fontSize: 14.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFFF1F5F9),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  '${spots.length} listed',
                  style: const TextStyle(
                    color: _textMuted,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          if (spots.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 28),
              child: Center(
                child: Text(
                  'No check-in data yet',
                  style: TextStyle(color: _textMuted, fontSize: 13),
                ),
              ),
            )
          else
            ...spots.asMap().entries.map((entry) {
              final index = entry.key;
              final spot = entry.value;
              final visits = spot['visits'] as int;
              final isTop = index == 0;
              return Padding(
                padding: EdgeInsets.only(
                  bottom: index == spots.length - 1 ? 0 : 12,
                ),
                child: Row(
                  children: [
                    Container(
                      width: 28,
                      height: 28,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: isTop ? _primaryOrange : const Color(0xFFF1F5F9),
                        borderRadius: BorderRadius.circular(9),
                      ),
                      child: Text(
                        '${index + 1}',
                        style: TextStyle(
                          color: isTop ? Colors.white : _textMuted,
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
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
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: _textDark,
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 7),
                          ClipRRect(
                            borderRadius: BorderRadius.circular(999),
                            child: LinearProgressIndicator(
                              value: maxVisits > 0 ? visits / maxVisits : 0,
                              backgroundColor: const Color(0xFFF1F5F9),
                              valueColor: AlwaysStoppedAnimation<Color>(
                                isTop
                                    ? _primaryOrange
                                    : _primaryOrange.withValues(alpha: 0.55),
                              ),
                              minHeight: 7,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    Text(
                      '$visits',
                      style: TextStyle(
                        color: isTop ? _primaryOrange : _textDark,
                        fontWeight: FontWeight.w800,
                        fontSize: 13,
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

  // ==================== REPORTS SECTION ====================
  Future<void> _captureReportsSectionScreenshot() async {
    if (_reportsScreenshotBusy) return;
    setState(() => _reportsScreenshotBusy = true);
    try {
      await WidgetsBinding.instance.endOfFrame;
      await Future<void>.delayed(const Duration(milliseconds: 80));
      if (!mounted) return;
      final boundary =
          _reportsRepaintKey.currentContext?.findRenderObject()
              as RenderRepaintBoundary?;
      if (boundary == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Analytics view is not ready yet. Try again.'),
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
        return;
      }
      final pr = MediaQuery.devicePixelRatioOf(context).clamp(1.0, 2.5);
      final ui.Image image = await boundary.toImage(pixelRatio: pr);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      final png = byteData?.buffer.asUint8List();
      if (png == null || png.isEmpty) {
        throw Exception('empty png');
      }
      final baseName =
          'atmos_trs_reports_${DateTime.now().millisecondsSinceEpoch}';
      final fileName = '$baseName.png';

      if (kIsWeb) {
        final xfile = XFile.fromData(
          png,
          mimeType: 'image/png',
          name: fileName,
        );
        await SharePlus.instance.share(
          ShareParams(
            files: [xfile],
            text: 'ATMOS-TRS â€” Analytics',
            title: 'Analytics screenshot',
          ),
        );
      } else {
        switch (defaultTargetPlatform) {
          case TargetPlatform.android:
          case TargetPlatform.iOS:
            final hasAccess = await Gal.hasAccess();
            if (!hasAccess) {
              final granted = await Gal.requestAccess();
              if (!granted) throw Exception('gallery permission denied');
            }
            await Gal.putImageBytes(png, name: fileName);
            break;
          default:
            final xfile = XFile.fromData(
              png,
              mimeType: 'image/png',
              name: fileName,
            );
            await SharePlus.instance.share(
              ShareParams(
                files: [xfile],
                text: 'ATMOS-TRS â€” Analytics',
                title: 'Analytics screenshot',
              ),
            );
        }
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            kIsWeb
                ? 'Screenshot ready ? use your browser or share dialog to save.'
                : (defaultTargetPlatform == TargetPlatform.android ||
                      defaultTargetPlatform == TargetPlatform.iOS)
                ? 'Screenshot saved to gallery.'
                : 'Screenshot ready to save or share.',
          ),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Could not capture screenshot. Please try again.'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _reportsScreenshotBusy = false);
    }
  }

  Widget _buildEventsContent() {
    final scope = (_municipalityName ?? _storedMunicipalityId ?? 'LGU').trim();
    return _buildFramedContentShell(
      title: 'Events & Posts',
      subtitle: '$scope — live province feed (auto-published)',
      body: RefreshIndicator(
        onRefresh: () async {
          LguEventService.invalidateEventsCache();
          await _loadData();
        },
        color: _primaryOrange,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: EdgeInsets.all(_isMobile ? 14 : 20),
          child: LguEventsPanel(
            key: const ValueKey('lgu-events-panel'),
            municipalityId: _storedMunicipalityId,
            municipalityName: _municipalityName,
            primaryColor: _primaryOrange,
            initialTabIndex: _eventsPanelTab,
            showChrome: false,
          ),
        ),
      ),
    );
  }

  // ==================== DIALOGS ====================
  List<Map<String, String>> _unreadCrossLguEventNotifications() {
    final myMun = (_storedMunicipalityId ?? '').trim();
    if (myMun.isEmpty) return const [];
    final items = <Map<String, String>>[];
    for (final e in _lguEvents) {
      if (!LguEventService.isVisibleToTourists(e)) continue;
      if (LguEventService.matchesMunicipality(e, myMun)) continue;
      final id = e['id']?.toString() ?? '';
      if (id.isEmpty) continue;
      if (_seenCrossLguEventIds.contains(_crossLguEventSeenKey(id))) continue;
      final title = e['title']?.toString().trim() ?? 'Event';
      final from = LguEventService.sourceMunicipalityLabel(e);
      final date = e['date']?.toString().trim() ?? '';
      items.add({
        'title': 'New event from $from',
        'message': date.isEmpty ? title : '$title Â· $date',
        'time': 'New',
      });
    }
    return items;
  }

  void _showNotificationsDialog() {
    final eventNotifs = _unreadCrossLguEventNotifications();
    final combined = [...eventNotifs, ..._notifications];
    // Opening the bell clears event unread; other alerts clear via Clear All.
    if (eventNotifs.isNotEmpty) {
      unawaited(_markAllEventDecisionsSeen());
    }
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: _cardBg,
        title: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              'Notifications',
              style: TextStyle(color: _textDark, fontWeight: FontWeight.w700),
            ),
            TextButton(
              onPressed: () {
                setState(() {
                  _notifications.clear();
                  _unreadNotifications = 0;
                });
                unawaited(_markAllEventDecisionsSeen());
                Navigator.pop(context);
              },
              child: const Text(
                'Clear All',
                style: TextStyle(color: Colors.redAccent, fontSize: 12),
              ),
            ),
          ],
        ),
        content: SizedBox(
          width: 350,
          child: combined.isEmpty
              ? const Center(
                  child: Text(
                    'No notifications',
                    style: TextStyle(color: _textMuted),
                  ),
                )
              : Column(
                  mainAxisSize: MainAxisSize.min,
                  children: combined
                      .map(
                        (n) => Container(
                          margin: const EdgeInsets.only(bottom: 12),
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.grey.shade200,
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                  color: _primaryOrange.withOpacity(0.15),
                                  borderRadius: BorderRadius.circular(14),
                                ),
                                child: const Icon(
                                  Icons.notifications,
                                  color: _primaryOrange,
                                  size: 16,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      n['title']!,
                                      style: const TextStyle(
                                        color: _textDark,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                    Text(
                                      n['message']!,
                                      style: TextStyle(
                                        color: _textMuted,
                                        fontSize: 12,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              Text(
                                n['time']!,
                                style: TextStyle(
                                  color: _textMuted,
                                  fontSize: 10,
                                ),
                              ),
                            ],
                          ),
                        ),
                      )
                      .toList(),
                ),
        ),
        actions: [
          if (eventNotifs.isNotEmpty)
            TextButton(
              onPressed: () {
                Navigator.pop(context);
                setState(() {
                  _selectedIndex = _eventsIndex;
                  _eventsPanelTab = 0;
                });
              },
              child: const Text('View Events'),
            ),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close', style: TextStyle(color: _primaryOrange)),
          ),
        ],
      ),
    );
  }

  /// Sidebar brand mark â€” always ATMOS logo (not the account profile photo).
  Widget _buildSidebarBrandLogo({required double size}) {
    return AtmosSquareLogo(
      height: size,
      width: size,
      padding: EdgeInsets.all(size * 0.1),
      borderRadius: size * 0.2,
      elevation: 0,
    );
  }

  /// Header account chip â€” profile photo when set (same as Governor).
  Widget _buildHeaderProfileAvatar({required double size}) {
    if (_profilePhotoBytes != null) {
      return Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white.withValues(alpha: 0.9), width: 2),
        ),
        child: ClipOval(
          child: Image.memory(_profilePhotoBytes!, fit: BoxFit.cover),
        ),
      );
    }

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: const Color(0xFFFFF7ED),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.85),
          width: 1.5,
        ),
      ),
      child: Icon(
        Icons.person_rounded,
        size: size * 0.55,
        color: _primaryOrange,
      ),
    );
  }

  // ==================== SETTINGS (aligned with governor) ====================
  Widget _buildSettingsContent() {
    return _buildFramedContentShell(
      title: 'Settings',
      subtitle: 'System configuration and preferences',
      body: SingleChildScrollView(
        padding: EdgeInsets.all(_isMobile ? 16 : 24),
        child: Column(
          children: [
            _buildTourismSettingsSection('Account', [
              _buildTourismSettingsTile(
                'Change Password',
                Icons.lock_outline,
                _showTourismChangePasswordDialog,
              ),
              _buildTourismSettingsTile(
                'Profile Settings',
                Icons.person_outline,
                _showTourismProfileSettingsDialog,
              ),
            ]),
            const SizedBox(height: 16),
            _buildTourismSettingsSection('Notifications', [
              _buildTourismNotificationToggle(
                'Email Notifications',
                Icons.email_outlined,
                _emailNotifications,
                (value) {
                  setState(() => _emailNotifications = value);
                  _saveTourismSettings();
                },
              ),
              _buildTourismNotificationToggle(
                'Push Notifications',
                Icons.notifications_outlined,
                _pushNotifications,
                (value) {
                  setState(() => _pushNotifications = value);
                  _saveTourismSettings();
                },
              ),
              _buildTourismNotificationToggle(
                'Weekly Reports',
                Icons.assessment_outlined,
                _weeklyReports,
                (value) {
                  setState(() => _weeklyReports = value);
                  _saveTourismSettings();
                },
              ),
            ]),
            const SizedBox(height: 16),
            _buildTourismSettingsSection('Data', [
              _buildTourismSettingsTileWithSubtitle(
                'Export Data',
                Icons.download_outlined,
                _isExporting
                    ? 'Exporting... ${(_exportProgress * 100).toInt()}%'
                    : 'Download registered tourist data as CSV',
                _showTourismExportDataDialog,
              ),
              _buildTourismSettingsTileWithSubtitle(
                'Backup Settings',
                Icons.backup_outlined,
                _lastBackupDate != null
                    ? 'Last backup: $_lastBackupDate'
                    : 'No backup yet',
                _showTourismBackupDialog,
              ),
            ]),
            const SizedBox(height: 16),
            _buildTourismSettingsSection('About', [
              _buildTourismSettingsTile(
                'System Information',
                Icons.info_outline,
                _showTourismSystemInfoDialog,
              ),
              _buildTourismSettingsTile(
                'Help & Support',
                Icons.help_outline,
                _showTourismHelpSupportDialog,
              ),
            ]),
          ],
        ),
      ),
    );
  }

  Widget _buildTourismSettingsSection(String title, List<Widget> children) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: _cardBg,
        borderRadius: BorderRadius.circular(28),
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

  Widget _buildTourismSettingsTile(
    String title,
    IconData icon,
    VoidCallback onTap,
  ) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: _primaryOrange.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(14),
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

  Widget _buildTourismSettingsTileWithSubtitle(
    String title,
    IconData icon,
    String subtitle,
    VoidCallback onTap,
  ) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: _primaryOrange.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(14),
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

  Widget _buildTourismNotificationToggle(
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
              borderRadius: BorderRadius.circular(14),
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
            activeThumbColor: const Color(0xFFFFFFFF),
            activeTrackColor: _primaryOrange,
          ),
        ],
      ),
    );
  }

  InputDecoration _tourismChangePasswordFieldDecoration({
    required String hint,
    required bool obscure,
    required VoidCallback onToggleObscure,
  }) {
    return InputDecoration(
      hintText: hint,
      hintStyle: const TextStyle(
        color: _textMuted,
        fontSize: 14,
        fontWeight: FontWeight.w500,
      ),
      filled: true,
      fillColor: const Color(0xFFF8FAFC),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: Colors.grey.shade300, width: 1.2),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: _primaryOrange, width: 2),
      ),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: Colors.grey.shade300),
      ),
      suffixIcon: IconButton(
        tooltip: obscure ? 'Show password' : 'Hide password',
        icon: Icon(
          obscure ? Icons.visibility_off_rounded : Icons.visibility_rounded,
          color: _textMuted,
        ),
        onPressed: onToggleObscure,
      ),
    );
  }

  Widget _tourismChangePasswordFieldLabel(String label) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Text(
        label,
        style: const TextStyle(
          color: _textDark,
          fontSize: 13,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  Widget _tourismPasswordRequirementRow(String text, bool met) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          Icon(
            met ? Icons.check_circle_rounded : Icons.radio_button_unchecked,
            size: 18,
            color: met ? const Color(0xFF16A34A) : _textMuted,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                color: met ? const Color(0xFF166534) : _textDark,
                fontSize: 13,
                fontWeight: FontWeight.w600,
                height: 1.25,
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showTourismChangePasswordDialog() {
    final currentPasswordController = TextEditingController();
    final newPasswordController = TextEditingController();
    final confirmPasswordController = TextEditingController();
    bool isLoading = false;
    String? errorMessage;
    bool obscureCurrent = true;
    bool obscureNew = true;
    bool obscureConfirm = true;
    var newPassword = '';

    showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) {
          bool validatePassword(String password) {
            if (password.length < 8) return false;
            if (!password.contains(RegExp(r'[A-Z]'))) return false;
            if (!password.contains(RegExp(r'[a-z]'))) return false;
            if (!password.contains(RegExp(r'[0-9]'))) return false;
            if (!password.contains(RegExp(r'[!@#$%^&*(),.?":{}|<>]'))) {
              return false;
            }
            return true;
          }

          final hasLen = newPassword.length >= 8;
          final hasUpper = newPassword.contains(RegExp(r'[A-Z]'));
          final hasLower = newPassword.contains(RegExp(r'[a-z]'));
          final hasNumber = newPassword.contains(RegExp(r'[0-9]'));
          final hasSpecial =
              newPassword.contains(RegExp(r'[!@#$%^&*(),.?":{}|<>]'));

          return AlertDialog(
            backgroundColor: _cardBg,
            surfaceTintColor: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
            ),
            insetPadding: EdgeInsets.symmetric(
              horizontal: _isMobile ? 16 : 40,
              vertical: 24,
            ),
            titlePadding: const EdgeInsets.fromLTRB(24, 22, 24, 0),
            contentPadding: const EdgeInsets.fromLTRB(24, 16, 24, 8),
            actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            title: const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Change Password',
                  style: TextStyle(
                    color: _textDark,
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                SizedBox(height: 6),
                Text(
                  'Update your LGU Tourism Office account password. Use a strong password you have not used before.',
                  style: TextStyle(
                    color: _textMuted,
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    height: 1.35,
                  ),
                ),
              ],
            ),
            content: SizedBox(
              width: 420,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (errorMessage != null)
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(12),
                        margin: const EdgeInsets.only(bottom: 14),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFEE2E2),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: const Color(0xFFFECACA)),
                        ),
                        child: Row(
                          children: [
                            const Icon(
                              Icons.error_outline_rounded,
                              color: Color(0xFFDC2626),
                              size: 20,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                errorMessage!,
                                style: const TextStyle(
                                  color: Color(0xFFB91C1C),
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    _tourismChangePasswordFieldLabel('Current password'),
                    TextField(
                      controller: currentPasswordController,
                      obscureText: obscureCurrent,
                      style: const TextStyle(
                        color: _textDark,
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                      decoration: _tourismChangePasswordFieldDecoration(
                        hint: 'Enter your current password',
                        obscure: obscureCurrent,
                        onToggleObscure: () => setDialogState(
                          () => obscureCurrent = !obscureCurrent,
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    _tourismChangePasswordFieldLabel('New password'),
                    TextField(
                      controller: newPasswordController,
                      obscureText: obscureNew,
                      onChanged: (v) => setDialogState(() => newPassword = v),
                      style: const TextStyle(
                        color: _textDark,
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                      decoration: _tourismChangePasswordFieldDecoration(
                        hint: 'Create a new password',
                        obscure: obscureNew,
                        onToggleObscure: () =>
                            setDialogState(() => obscureNew = !obscureNew),
                      ),
                    ),
                    const SizedBox(height: 10),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.fromLTRB(12, 12, 12, 6),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFFF7ED),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: const Color(0xFFFED7AA)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Password must include:',
                            style: TextStyle(
                              color: _textDark,
                              fontSize: 13,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(height: 8),
                          _tourismPasswordRequirementRow(
                            'At least 8 characters',
                            hasLen,
                          ),
                          _tourismPasswordRequirementRow(
                            'One uppercase letter (Aâ€“Z)',
                            hasUpper,
                          ),
                          _tourismPasswordRequirementRow(
                            'One lowercase letter (aâ€“z)',
                            hasLower,
                          ),
                          _tourismPasswordRequirementRow(
                            'One number (0â€“9)',
                            hasNumber,
                          ),
                          _tourismPasswordRequirementRow(
                            'One special character (!@#\$%â€¦)',
                            hasSpecial,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    _tourismChangePasswordFieldLabel('Confirm new password'),
                    TextField(
                      controller: confirmPasswordController,
                      obscureText: obscureConfirm,
                      style: const TextStyle(
                        color: _textDark,
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                      decoration: _tourismChangePasswordFieldDecoration(
                        hint: 'Re-enter new password',
                        obscure: obscureConfirm,
                        onToggleObscure: () => setDialogState(
                          () => obscureConfirm = !obscureConfirm,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: isLoading ? null : () => Navigator.pop(dialogContext),
                child: const Text(
                  'Cancel',
                  style: TextStyle(
                    color: _textMuted,
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                  ),
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

                        final effective =
                            await SessionStorage.getEffectiveTourismPassword();
                        if (currentPasswordController.text != effective) {
                          setDialogState(() {
                            errorMessage = 'Current password is incorrect';
                            isLoading = false;
                          });
                          return;
                        }

                        if (!validatePassword(newPasswordController.text)) {
                          setDialogState(() {
                            errorMessage =
                                'New password does not meet all requirements below';
                            isLoading = false;
                          });
                          return;
                        }

                        if (newPasswordController.text !=
                            confirmPasswordController.text) {
                          setDialogState(() {
                            errorMessage =
                                'New password and confirmation do not match';
                            isLoading = false;
                          });
                          return;
                        }

                        final newPassword = newPasswordController.text;
                        final typedCurrent = currentPasswordController.text;
                        final authEmail =
                            FirebaseAuth.instance.currentUser?.email?.trim() ??
                                SessionStorage.tourismEmail;
                        try {
                          await AuthService.reauthenticateAndUpdatePassword(
                            email: authEmail,
                            currentPassword: typedCurrent,
                            newPassword: newPassword,
                          );
                        } on FirebaseAuthException catch (authErr) {
                          final code = authErr.code;
                          final canRetryDefault = code == 'wrong-password' ||
                              code == 'invalid-credential' ||
                              code == 'invalid-login-credentials';
                          if (!canRetryDefault ||
                              typedCurrent == SessionStorage.tourismPassword) {
                            setDialogState(() {
                              errorMessage = authErr.message?.trim().isNotEmpty ==
                                      true
                                  ? authErr.message!
                                  : 'Could not update Firebase password. Try logging in again.';
                              isLoading = false;
                            });
                            return;
                          }
                          try {
                            await AuthService.reauthenticateAndUpdatePassword(
                              email: authEmail,
                              currentPassword: SessionStorage.tourismPassword,
                              newPassword: newPassword,
                            );
                          } on FirebaseAuthException catch (authErr2) {
                            setDialogState(() {
                              errorMessage = authErr2.message?.trim().isNotEmpty ==
                                      true
                                  ? authErr2.message!
                                  : 'Could not update Firebase password. Try logging in again.';
                              isLoading = false;
                            });
                            return;
                          }
                        } catch (e) {
                          setDialogState(() {
                            errorMessage = 'Could not update password: $e';
                            isLoading = false;
                          });
                          return;
                        }

                        final prefs = await SharedPreferences.getInstance();
                        await prefs.setString(
                          'tourism_password',
                          newPassword,
                        );

                        if (!dialogContext.mounted) return;
                        Navigator.pop(dialogContext);
                        if (!mounted) return;
                        ScaffoldMessenger.of(this.context).showSnackBar(
                          const SnackBar(
                            content: Text('Password updated successfully'),
                            backgroundColor: _primaryOrange,
                          ),
                        );
                      },
                style: ElevatedButton.styleFrom(
                  backgroundColor: _primaryOrange,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 12,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
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
                    : const Text(
                        'Update Password',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                          fontSize: 14,
                        ),
                      ),
              ),
            ],
          );
        },
      ),
    );
  }

  void _showTourismProfileSettingsDialog() {
    final nameController = TextEditingController(text: _profileName);
    final emailController = TextEditingController(text: _profileEmail);
    Uint8List? dialogPhotoBytes = _profilePhotoBytes;
    String? dialogPhotoBase64 = _profilePhotoBase64;
    bool isLoading = false;

    showDialog<void>(
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
                            // ignore
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
                      borderRadius: BorderRadius.circular(14),
                      borderSide: BorderSide(color: Colors.grey.shade300),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
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
                      borderRadius: BorderRadius.circular(14),
                      borderSide: BorderSide(color: Colors.grey.shade300),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
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
                      await _saveTourismSettings();

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

  void _showTourismExportDataDialog() {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: _cardBg,
        title: const Text(
          'Export Data',
          style: TextStyle(color: _textDark, fontWeight: FontWeight.w600),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildTourismExportOption(
              'Registered Tourists data (CSV)',
              Icons.people_alt_rounded,
              () {
                Navigator.pop(context);
                _exportTouristsData();
              },
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

  Widget _buildTourismExportOption(
    String title,
    IconData icon,
    VoidCallback onTap,
  ) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.grey.shade200,
            borderRadius: BorderRadius.circular(20),
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
              const Icon(Icons.chevron_right, color: _textMuted),
            ],
          ),
        ),
      ),
    );
  }

  void _showTourismBackupDialog() {
    unawaited(_runTourismBackupAsync());
  }

  Future<void> _runTourismBackupAsync() async {
    final prefs = await SharedPreferences.getInstance();
    final date = DateTime.now().toIso8601String().split('T').first;
    setState(() => _lastBackupDate = date);
    await prefs.setString('tourism_last_backup_date', date);
    await _saveTourismSettings();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Backup is not available during beta testing'),
        backgroundColor: _primaryOrange,
      ),
    );
  }

  void _showTourismSystemInfoDialog() {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: _cardBg,
        title: const Text(
          'System Information',
          style: TextStyle(color: _textDark, fontWeight: FontWeight.w600),
        ),
        content: const Text(
          'ATMOS-TRS ? LGU Office dashboard.\n\n'
          'Data syncs with Firebase when configured. '
          'Profile and notification preferences are stored on this device.',
          style: TextStyle(color: _textDark, fontSize: 14),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('OK', style: TextStyle(color: _primaryOrange)),
          ),
        ],
      ),
    );
  }

  void _showTourismHelpSupportDialog() {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: _cardBg,
        title: const Text(
          'Help & Support',
          style: TextStyle(color: _textDark, fontWeight: FontWeight.w600),
        ),
        content: const Text(
          'For account issues, contact your LGU administrator or MISORS technical support.\n\n'
          'Use Settings ? Change Password to update your login password (demo/local storage).',
          style: TextStyle(color: _textDark, fontSize: 14),
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
}

/// Visitor trend chart with Y-axis gutter, X labels, and hover readout.
class _AnalyticsTrendChart extends StatefulWidget {
  const _AnalyticsTrendChart({required this.values, required this.color});

  final List<double> values;
  final Color color;

  @override
  State<_AnalyticsTrendChart> createState() => _AnalyticsTrendChartState();
}

class _AnalyticsTrendChartState extends State<_AnalyticsTrendChart> {
  int? _hoverIndex;
  double? _hoverX;

  int get _n => widget.values.length;

  int _indexAtDx(double dx, double width) {
    final n = _n;
    if (n <= 1 || width <= 0) return 0;
    final t = (dx / width).clamp(0.0, 1.0);
    return ((n - 1) * t).round().clamp(0, n - 1);
  }

  String _dayLabel(int i) {
    final d = DateTime.now().subtract(Duration(days: 13 - i));
    return '${d.month}/${d.day}';
  }

  int get _maxY {
    if (widget.values.isEmpty) return 1;
    final m = widget.values.reduce(math.max);
    return math.max(1, m.ceil());
  }

  @override
  Widget build(BuildContext context) {
    final maxY = _maxY;
    final midY = (maxY / 2).ceil();
    const axisStyle = TextStyle(
      color: Color(0xFF6B7280),
      fontSize: 11,
      fontWeight: FontWeight.w600,
    );
    const chartH = 208.0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          height: chartH,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(
                width: 40,
                child: Padding(
                  padding: const EdgeInsets.only(right: 6, top: 8, bottom: 4),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text('$maxY', style: axisStyle),
                      Text(maxY > 1 ? '$midY' : ' ', style: axisStyle),
                      const Text('0', style: axisStyle),
                    ],
                  ),
                ),
              ),
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: LayoutBuilder(
                    builder: (context, cons) {
                      return Listener(
                        behavior: HitTestBehavior.opaque,
                        onPointerDown: (e) {
                          final i = _indexAtDx(
                            e.localPosition.dx,
                            cons.maxWidth,
                          );
                          setState(() {
                            _hoverIndex = i;
                            _hoverX = e.localPosition.dx;
                          });
                        },
                        child: MouseRegion(
                          onExit: (_) {
                            setState(() {
                              _hoverIndex = null;
                              _hoverX = null;
                            });
                          },
                          onHover: (event) {
                            final dx = event.localPosition.dx;
                            final i = _indexAtDx(dx, cons.maxWidth);
                            setState(() {
                              _hoverIndex = i;
                              _hoverX = dx;
                            });
                          },
                          child: Stack(
                            clipBehavior: Clip.hardEdge,
                            children: [
                              CustomPaint(
                                size: Size(cons.maxWidth, chartH),
                                painter: _TourismAnalyticsChartPainter(
                                  color: widget.color,
                                  values: widget.values,
                                  maxVal: maxY.toDouble(),
                                  hoverX: _hoverX,
                                ),
                              ),
                              if (_hoverIndex != null && _hoverX != null)
                                Positioned(
                                  top: 8,
                                  left: (_hoverX!.clamp(
                                    8.0,
                                    cons.maxWidth - 132,
                                  )).clamp(0.0, cons.maxWidth - 140),
                                  child: Material(
                                    elevation: 4,
                                    borderRadius: BorderRadius.circular(10),
                                    color: Colors.white,
                                    child: Padding(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 10,
                                        vertical: 8,
                                      ),
                                      child: Text(
                                        '${_dayLabel(_hoverIndex!)} ? ${widget.values[_hoverIndex!].toStringAsFixed(0)} check-ins',
                                        style: const TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.w700,
                                          color: Color(0xFF111827),
                                        ),
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
                ),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(left: 40, top: 8, right: 4),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(_dayLabel(0), style: axisStyle),
              Text(_dayLabel(6), style: axisStyle),
              Text(_dayLabel(13), style: axisStyle),
            ],
          ),
        ),
        const Padding(
          padding: EdgeInsets.only(left: 40, top: 2),
          child: Text(
            'Date (oldest ? today)',
            style: TextStyle(
              color: Color(0xFF9CA3AF),
              fontSize: 11,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ],
    );
  }
}

/// Line / area chart for LGU analytics (plotted area only; axes are Flutter widgets).
class _TourismAnalyticsChartPainter extends CustomPainter {
  _TourismAnalyticsChartPainter({
    required this.color,
    this.values = const [],
    this.maxVal,
    this.hoverX,
  });

  final Color color;
  final List<double> values;
  final double? maxVal;
  final double? hoverX;

  @override
  void paint(Canvas canvas, Size size) {
    final bg = RRect.fromRectAndRadius(
      Offset.zero & size,
      const Radius.circular(12),
    );
    canvas.drawRRect(bg, Paint()..color = const Color(0xFFF9FAFB));
    canvas.drawRRect(
      bg,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = const Color(0xFFE5E7EB),
    );

    final gridPaint = Paint()
      ..color = const Color(0xFFE5E7EB)
      ..strokeWidth = 1;

    for (int i = 0; i < 5; i++) {
      final y = size.height * i / 4;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }

    double maxV = maxVal ?? 1;
    if (maxV <= 0) maxV = 1;
    if (values.isEmpty) {
      final tp = TextPainter(
        text: TextSpan(
          text: 'No check-ins in the last 14 days',
          style: TextStyle(
            color: Colors.grey.shade600,
            fontSize: 13,
            fontWeight: FontWeight.w600,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout(maxWidth: size.width - 24);
      tp.paint(
        canvas,
        Offset((size.width - tp.width) / 2, (size.height - tp.height) / 2),
      );
      return;
    }

    final paint = Paint()
      ..color = color
      ..strokeWidth = 3
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    final fillPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [color.withOpacity(0.28), color.withOpacity(0.02)],
      ).createShader(Rect.fromLTWH(0, 0, size.width, size.height));

    final points = <Offset>[];
    if (values.length >= 2) {
      for (int i = 0; i < values.length; i++) {
        final x = size.width * (i / (values.length - 1));
        final y = size.height * (1 - (values[i] / maxV).clamp(0.0, 1.0));
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

    final hx = hoverX;
    if (hx != null && hx >= 0 && hx <= size.width) {
      final guide = Paint()
        ..color = color.withOpacity(0.35)
        ..strokeWidth = 1;
      canvas.drawLine(Offset(hx, 0), Offset(hx, size.height), guide);
    }

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
  bool shouldRepaint(covariant _TourismAnalyticsChartPainter oldDelegate) {
    if (oldDelegate.color != color ||
        oldDelegate.maxVal != maxVal ||
        oldDelegate.hoverX != hoverX) {
      return true;
    }
    if (oldDelegate.values.length != values.length) return true;
    for (var i = 0; i < values.length; i++) {
      if (oldDelegate.values[i] != values[i]) return true;
    }
    return false;
  }
}

/// Lazily builds an LGU sidebar tab on first visit and keeps it alive afterward
/// so switching features (Visits → Spots → Events) is instant with no reload flash.
class _LguLazyKeepAliveTab extends StatefulWidget {
  const _LguLazyKeepAliveTab({
    required this.active,
    required this.builder,
  });

  final bool active;
  final Widget Function() builder;

  @override
  State<_LguLazyKeepAliveTab> createState() => _LguLazyKeepAliveTabState();
}

class _LguLazyKeepAliveTabState extends State<_LguLazyKeepAliveTab>
    with AutomaticKeepAliveClientMixin {
  bool _activated = false;

  @override
  bool get wantKeepAlive => _activated;

  @override
  void initState() {
    super.initState();
    if (widget.active) _activated = true;
  }

  @override
  void didUpdateWidget(covariant _LguLazyKeepAliveTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.active && !_activated) {
      setState(() => _activated = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    if (!_activated) return const SizedBox.expand();
    return widget.builder();
  }
}

class _NavItem {
  final IconData icon;
  final String label;
  _NavItem({required this.icon, required this.label});
}

class _StatCard {
  final String title;
  final String value;
  final String? subtitle;
  final IconData icon;
  final Color color;
  final Color? tint;
  final String? chipLabel;
  final String? trendLabel;
  final bool trendPositive;
  final VoidCallback? onTap;
  _StatCard({
    required this.title,
    required this.value,
    this.subtitle,
    required this.icon,
    required this.color,
    this.tint,
    this.chipLabel,
    this.trendLabel,
    this.trendPositive = true,
    this.onTap,
  });
}

/// Soft lift + scale on hover for premium KPI / action cards.
class _HoverLiftCard extends StatefulWidget {
  const _HoverLiftCard({required this.child, this.onTap});

  final Widget child;
  final VoidCallback? onTap;

  @override
  State<_HoverLiftCard> createState() => _HoverLiftCardState();
}

class _HoverLiftCardState extends State<_HoverLiftCard> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: AnimatedScale(
        scale: _hovered ? 1.02 : 1.0,
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOutCubic,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOutCubic,
          transform: Matrix4.translationValues(0, _hovered ? -4 : 0, 0),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: widget.onTap,
              borderRadius: BorderRadius.circular(20),
              child: widget.child,
            ),
          ),
        ),
      ),
    );
  }
}

/// White sparkline on flat KPI cards.
class _TourismMiniSparklinePainter extends CustomPainter {
  _TourismMiniSparklinePainter({
    required this.values,
    this.lineColor = const Color(0xE6FFFFFF),
  });

  final List<double> values;
  final Color lineColor;

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
      ..color = lineColor
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
  bool shouldRepaint(covariant _TourismMiniSparklinePainter oldDelegate) =>
      oldDelegate.values != values || oldDelegate.lineColor != lineColor;
}


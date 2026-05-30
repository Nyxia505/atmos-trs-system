import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/foundation.dart'
    show kIsWeb, defaultTargetPlatform, TargetPlatform;
import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:cross_file/cross_file.dart';
import 'package:share_plus/share_plus.dart';
import 'package:image_gallery_saver_plus/image_gallery_saver_plus.dart';
import 'package:atmos_trs_system/config/auth_config.dart';
import 'package:atmos_trs_system/config/session_storage.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'dart:convert';
import 'dart:math' as math;
import 'package:atmos_trs_system/widgets/app_search_bar.dart';
import 'package:atmos_trs_system/widgets/app_logout_button.dart';
import 'package:atmos_trs_system/data/misamis_occidental_municipalities.dart';
import 'package:atmos_trs_system/utils/spot_qr_helper.dart';
import 'package:atmos_trs_system/utils/logo_utils.dart';
import 'package:atmos_trs_system/services/registration_municipality_resolver.dart';
import 'package:atmos_trs_system/services/user_directory_service.dart';
import 'package:atmos_trs_system/utils/municipality_helper.dart';
import 'package:atmos_trs_system/utils/tourist_id_helper.dart';
import 'package:atmos_trs_system/models/tourist_spot.dart';
import 'package:atmos_trs_system/services/tourist_spots_firestore_service.dart';
import 'package:atmos_trs_system/utils/csv_file_download.dart';
import 'package:atmos_trs_system/utils/lgu_qr_export.dart';
import 'package:atmos_trs_system/services/vr_tour_firestore_service.dart';
import 'package:atmos_trs_system/screens/vr_webview_screen.dart';
import 'package:image_picker/image_picker.dart';

class TourismDashboard extends StatefulWidget {
  const TourismDashboard({super.key});

  @override
  State<TourismDashboard> createState() => _TourismDashboardState();
}

class _TourismDashboardState extends State<TourismDashboard>
    with SingleTickerProviderStateMixin {
  int _selectedIndex = 0;
  bool _isSidebarExpanded = true;
  bool _didInitializeSidebarForViewport = false;
  late AnimationController _animationController;

  // Theme colors - FlexiMart style with Orange
  static const Color _primaryOrange = Color(
    0xFFEA580C,
  ); // dark orange (sidebar)
  static const Color _accentOrange = Color(
    0xFFF97316,
  ); // orange-500 (highlights, user card)
  static const Color _darkBg = Color(0xFFFFF7ED); // cream background
  static const Color _cardBg = Color(0xFFFFFBF7); // soft white cards
  static const Color _sidebarBg = Color(0xFFEA580C); // dark orange sidebar
  static const Color _textDark = Color(0xFF1A1A1A);
  static const Color _textMuted = Color(0xFF6B7280);
  static const Color _kAnalyticsSurfaceBorder = Color(0xFFE5E7EB);
  static const Color _kpiGreen = Color(0xFF9CCC65);
  static const Color _kpiOrange = Color(0xFFFFB74D);
  static const Color _kpiBlue = Color(0xFF64B5F6);
  static const Color _kpiPurple = Color(0xFF9575CD);
  static const Color _surfaceBg = Color(0xFFF4F4F5);
  static const Color _panelBorder = Color(0xFFE4E4E7);

  BoxDecoration _tourismPanelDecoration() => BoxDecoration(
    color: Colors.white,
    borderRadius: BorderRadius.circular(12),
    border: Border.all(color: _panelBorder),
  );

  Widget _wrapTourismPanel(Widget child, {EdgeInsets? padding}) {
    return Container(
      padding: padding ?? EdgeInsets.all(_isMobile ? 14 : 16),
      decoration: _tourismPanelDecoration(),
      child: child,
    );
  }

  /// Large rounded UI (dashboard reference): main panel.

  // Data states
  bool _isLoading = true;
  String? _errorMessage;

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

  /// For real-time check-in notifications: newest check-in doc id we've seen.
  String? _lastSeenCheckInId;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>?
  _qrCheckInsSubscription;
  StreamSubscription<List<TouristSpot>>? _touristSpotsSubscription;
  String? _storedMunicipalityId;
  List<TouristSpot> _allTouristSpots = [];

  // Search controllers
  final _checkInsSearchController = TextEditingController();
  final _spotsSearchController = TextEditingController();
  final _touristsSearchController = TextEditingController();
  final _vrToursSearchController = TextEditingController();

  // Filter states
  String _checkInStatusFilter = 'All';
  String _spotCategoryFilter = 'All';
  String _reportType = 'All Data';
  DateTime? _reportStartDate;
  DateTime? _reportEndDate;

  // Export states
  bool _isExporting = false;
  double _exportProgress = 0.0;

  /// Full Reports tab (quick exports + custom report) for PNG screenshot.
  final GlobalKey _reportsRepaintKey = GlobalKey();
  bool _reportsScreenshotBusy = false;

  /// One-shot Firestore sync for `qrValue` / `qr_payload` / `createdAt` on `tourist_spots`.
  bool _isBackfillingSpotQr = false;
  bool _didAutoBackfillSpotQr = false;

  // Settings (local prefs; same pattern as governor dashboard)
  bool _emailNotifications = true;
  bool _pushNotifications = true;
  bool _weeklyReports = false;
  String? _lastBackupDate;
  String _profileName = 'Tourism Office';
  String _profileEmail = '';
  String? _profilePhotoBase64;
  Uint8List? _profilePhotoBytes;

  final List<_NavItem> _navItems = [
    _NavItem(icon: Icons.dashboard_rounded, label: 'Dashboard'),
    _NavItem(icon: Icons.qr_code_scanner_rounded, label: 'Visit log'),
    _NavItem(icon: Icons.place_rounded, label: 'Tourist Spots'),
    _NavItem(icon: Icons.qr_code_2_rounded, label: 'Spot QR Codes'),
    _NavItem(icon: Icons.people_alt_rounded, label: 'Visitors'),
    _NavItem(icon: Icons.vrpano_rounded, label: 'VR Tours'),
    _NavItem(icon: Icons.analytics_rounded, label: 'Analytics'),
    _NavItem(icon: Icons.assessment_rounded, label: 'Reports'),
  ];

  static const int _mainNavCount = 7; // Dashboard through Analytics
  static const int _touristSpotsNavIndex = 2;
  static const int _spotQRCodesIndex = 3;
  static const int _analyticsIndex = 6;
  static const int _reportsIndex = 7;
  static const int _settingsIndex = 8;

  final List<String> _categories = [
    'All',
    'Beach',
    'Falls',
    'Historical',
    'Mountain',
    'Resort',
  ];
  final List<String> _reportTypes = [
    'All Data',
    'Visits only',
    'Tourists Only',
    'Tourist Spots Only',
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
    _loadTourismSettings();
    _loadData();
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
            : 'Tourism Office';
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
    _touristSpotsSubscription?.cancel();
    _animationController.dispose();
    _checkInsSearchController.dispose();
    _spotsSearchController.dispose();
    _touristsSearchController.dispose();
    _vrToursSearchController.dispose();
    super.dispose();
  }

  bool get _isMobile => MediaQuery.of(context).size.width < 768;
  bool get _isTablet =>
      MediaQuery.of(context).size.width >= 768 &&
      MediaQuery.of(context).size.width < 1024;

  // When true, show banner that we're showing all data (no municipality filter)
  bool _showAllDataBanner = false;
  String?
  _municipalityName; // Display name for current filter (e.g. "Oroquieta City")

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
              'Your session expired. Please sign in again to load dashboard data.';
          _isLoading = false;
        });
        return;
      }
      AuthConfig.currentUserUid = authUser.uid;

      await authUser.getIdToken(true);
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

      final staffReady =
          await UserDirectoryService.prepareProvincialStaffFirestoreAccess(
        uid: authUser.uid,
        email: authEmail.isNotEmpty ? authEmail : SessionStorage.tourismEmail,
        roleRaw: 'tourism',
        fullName: _profileName,
        municipalityId: municipalityId,
      );
      if (!staffReady) {
        debugPrint(
          '[TourismDashboard] staff Firestore access not ready (email=$authEmail)',
        );
        if (!mounted) return;
        setState(() {
          _errorMessage =
              'Could not verify tourism office access in Firestore. '
              'Log out and sign in with your tourism account (e.g. tourism.oroquieta@… '
              'or tourismoffice.atmos@misocc-demo.ph), then try again.';
          _isLoading = false;
        });
        return;
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
      // Re-apply municipality filter to spots when municipality changes (e.g. after login)
      _touristSpots = _filterSpotsByMunicipality(
        _allTouristSpots,
        _storedMunicipalityId,
      );
      _activeSpots = _touristSpots.where((s) => s.status == 'Active').length;
      if (_activeSpots == 0 && _touristSpots.isNotEmpty) {
        _activeSpots = _touristSpots.length;
      }

      // Ensure all existing spot docs carry qrValue/qr_payload/createdAt.
      // Run once per dashboard session to keep Firestore complete.
      if (!_didAutoBackfillSpotQr) {
        _didAutoBackfillSpotQr = true;
        try {
          await _runBackfillSpotQrMetadata(showSnack: false);
        } catch (e) {
          debugPrint('Spot QR metadata backfill skipped: $e');
        }
      }

      if (municipalityId != null) {
        // Per-municipality: use qr_checkins and filter tourists by this municipality.
        // Tourist spots are loaded via stream in _subscribeToTouristSpots() and filtered there.
        final queryIds = municipalityIdsForQuery(municipalityId);
        if (queryIds.isNotEmpty) {
          try {
            final Query<Map<String, dynamic>> checkInsQuery =
                queryIds.length == 1
                ? firestore
                      .collection('qr_checkins')
                      .where('municipalityId', isEqualTo: queryIds.first)
                : firestore
                      .collection('qr_checkins')
                      .where('municipalityId', whereIn: queryIds);
            final checkInsSnapshot = await checkInsQuery.get();
            _checkIns = checkInsSnapshot.docs
                .map(
                  (doc) =>
                      _normalizeCheckInForUi({'id': doc.id, ...doc.data()}),
                )
                .toList();
            _checkIns = _dedupeCheckInsByTouristSpotAndDay(_checkIns);
            _checkIns.sort((a, b) {
              final ta = a['timestamp'];
              final tb = b['timestamp'];
              if (ta is Timestamp && tb is Timestamp) {
                return tb.compareTo(ta);
              }
              return 0;
            });
            if (_checkIns.length > 100) {
              _checkIns = _checkIns.take(100).toList();
            }
            _lastSeenCheckInId = _checkIns.isNotEmpty
                ? (_checkIns.first['id'] as String?)
                : null;
            _subscribeToCheckIns(queryIds);
          } catch (e) {
            debugPrint('Failed loading qr_checkins for dashboard: $e');
            _checkIns = [];
            _lastSeenCheckInId = null;
          }
        }

        final checkInUserIds = _checkIns
            .map((c) => c['userId']?.toString().trim())
            .whereType<String>()
            .where((id) => id.isNotEmpty)
            .toSet();
        try {
          _tourists = await _loadRegisteredTouristsForMunicipality(
            firestore: firestore,
            queryIds: queryIds,
            checkInUserIds: checkInUserIds,
          );
          _tourists = _mergeTouristVisitsFromCheckIns(_tourists);
        } catch (e) {
          debugPrint('Failed loading tourists for dashboard: $e');
          _tourists = [];
        }

        await _finalizeCheckInAndTouristData();

        await _reloadVrToursFromDatabase();
      } else {
        // No municipality filter: load from check_ins (legacy) and all spots/tourists
        _qrCheckInsSubscription?.cancel();
        _qrCheckInsSubscription = null;
        _lastSeenCheckInId = null;
        try {
          final checkInsSnapshot = await firestore
              .collection('check_ins')
              .orderBy('timestamp', descending: true)
              .limit(100)
              .get();
          _checkIns = checkInsSnapshot.docs
              .map(
                (doc) => _normalizeCheckInForUi({'id': doc.id, ...doc.data()}),
              )
              .toList();
          _checkIns = _dedupeCheckInsByTouristSpotAndDay(_checkIns);
          await _finalizeCheckInAndTouristData();
        } catch (e) {
          debugPrint('Failed loading legacy check_ins for dashboard: $e');
          _checkIns = [];
        }

        // Tourist spots are loaded via stream in _subscribeToTouristSpots()

        // Full `tourists` registration directory is Governor (admin) only — not exposed on LGU.
        _tourists = [];

        await _reloadVrToursFromDatabase();
      }

      // Calculate stats
      final today = DateTime.now();
      _todayCheckIns = _checkIns.where((c) {
        final timestamp = c['timestamp'];
        if (timestamp is Timestamp) {
          final date = timestamp.toDate();
          return date.day == today.day &&
              date.month == today.month &&
              date.year == today.year;
        }
        return false;
      }).length;

      _totalTourists = _tourists.length;
      _activeSpots = _touristSpots.where((s) => s.status == 'Active').length;
      if (_activeSpots == 0 && _touristSpots.isNotEmpty) {
        _activeSpots = _touristSpots.length;
      }
      _totalVRTours = _vrTours.length;

      // Generate recent activity (location = spot name from qr_checkins)
      _recentActivity = _checkIns.take(5).map(_recentActivityFromCheckIn).toList();

      setState(() {
        _errorMessage = null;
        _isLoading = false;
      });
      await _loadTourismSettings();
    } catch (e) {
      debugPrint('Error loading tourism dashboard data: $e');
      if (mounted) {
        setState(() {
          _errorMessage =
              'Could not load dashboard data. Pull to refresh or sign in again.';
          _isLoading = false;
        });
      }
    } finally {
      if (mounted && _isLoading) {
        setState(() => _isLoading = false);
      }
    }
  }

  /// Subscribes to qr_checkins for the given municipality id(s) and updates _checkIns in real time.
  /// When new check-ins appear, adds them to _notifications and shows a SnackBar.
  /// [queryIds] should be from municipalityIdsForQuery() so alternate spellings (e.g. ozamiz, ozamis) are included.
  void _subscribeToCheckIns(List<String> queryIds) {
    _qrCheckInsSubscription?.cancel();
    if (queryIds.isEmpty || Firebase.apps.isEmpty) return;
    final now = DateTime.now();
    final Query<Map<String, dynamic>> subscriptionQuery = queryIds.length == 1
        ? FirebaseFirestore.instance
              .collection('qr_checkins')
              .where('municipalityId', isEqualTo: queryIds.first)
        : FirebaseFirestore.instance
              .collection('qr_checkins')
              .where('municipalityId', whereIn: queryIds);
    _qrCheckInsSubscription = subscriptionQuery
        .orderBy('timestamp', descending: true)
        .limit(50)
        .snapshots()
        .listen(
          (QuerySnapshot<Map<String, dynamic>> snapshot) {
            if (!mounted) return;
            final docs = snapshot.docs;
            final checkIns = docs
                .map((d) => _normalizeCheckInForUi({'id': d.id, ...d.data()}))
                .toList();
            final previousFirstId = _lastSeenCheckInId;
            _lastSeenCheckInId = docs.isEmpty ? null : docs.first.id;
            _checkIns = _dedupeCheckInsByTouristSpotAndDay(checkIns);
            _tourists = _mergeTouristVisitsFromCheckIns(_tourists);
            _rebuildTouristProfileIndex();
            _applyTouristProfilesToCheckIns();
            _todayCheckIns = _checkIns.where((c) {
              final timestamp = c['timestamp'];
              if (timestamp is Timestamp) {
                final date = timestamp.toDate();
                return date.day == now.day &&
                    date.month == now.month &&
                    date.year == now.year;
              }
              return false;
            }).length;
            _recentActivity =
                _checkIns.take(5).map(_recentActivityFromCheckIn).toList();
            if (previousFirstId != null &&
                docs.isNotEmpty &&
                docs.first.id != previousFirstId) {
              int newCount = 0;
              for (var d in docs) {
                if (d.id == previousFirstId) break;
                newCount++;
                final row = _normalizeCheckInForUi({'id': d.id, ...d.data()});
                final spotLabel =
                    row['location']?.toString().trim().isNotEmpty == true
                    ? row['location'].toString()
                    : (row['spotId']?.toString() ?? 'spot')
                          .replaceAll('_', ' ');
                _notifications.insert(0, {
                  'title': 'New check-in',
                  'message': 'Check-in at $spotLabel',
                  'time': 'Just now',
                });
              }
              if (newCount > 0 && mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      newCount == 1
                          ? 'New check-in in your municipality!'
                          : '$newCount new check-ins in your municipality!',
                    ),
                    backgroundColor: _primaryOrange,
                    behavior: SnackBarBehavior.floating,
                  ),
                );
              }
            }
            setState(() {});
          },
          onError: (Object e) {
            debugPrint('qr_checkins stream error: $e');
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

  String _formatDate(DateTime date) {
    return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
  }

  /// Separate date / time (Governor portal parity).
  String _formatRegisteredDateOnlyDisplay(DateTime? dt) {
    if (dt == null) return '—';
    return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';
  }

  String _formatRegisteredTimeOnlyDisplay(DateTime? dt) {
    if (dt == null) return '—';
    final h24 = dt.hour;
    final min = dt.minute.toString().padLeft(2, '0');
    final sec = dt.second.toString().padLeft(2, '0');
    final period = h24 >= 12 ? 'PM' : 'AM';
    final h12 = h24 == 0 ? 12 : (h24 > 12 ? h24 - 12 : h24);
    return '$h12:$min:$sec $period';
  }

  /// Short display format for date picker trigger, e.g. "Mon, Mar 2"
  String _formatDateDisplay(DateTime date) {
    const weekdays = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    return '${weekdays[date.weekday % 7]}, ${months[date.month - 1]} ${date.day}';
  }

  /// Parse [timestamp] from a `qr_checkins` or legacy check-in map.
  DateTime? _parseCheckInTimestamp(Map<String, dynamic> c) {
    final ts = c['timestamp'];
    if (ts is Timestamp) return ts.toDate();
    if (ts is DateTime) return ts;
    return null;
  }

  /// Normalizes both `qr_checkins` and legacy `check_ins` docs to a common UI shape.
  Map<String, dynamic> _normalizeCheckInForUi(Map<String, dynamic> row) {
    final touristNameRaw = row['touristName']?.toString().trim() ?? '';
    final userIdRaw =
        row['userId']?.toString().trim() ??
        row['tourist_id']?.toString().trim() ??
        '';
    final spotNameRaw = row['spot_name']?.toString().trim() ?? '';
    final locationRaw = row['location']?.toString().trim() ?? '';
    final spotIdRaw =
        row['spotId']?.toString().trim() ??
        row['spot_id']?.toString().trim() ??
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

    return <String, dynamic>{
      ...row,
      'touristName': touristName,
      'touristId': row['touristId']?.toString() ?? '',
      'location': location,
      // `qr_checkins` typically has no explicit status; default to verified.
      'status': statusRaw.isNotEmpty ? statusRaw : 'Verified',
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
    if (Firebase.apps.isEmpty || _checkIns.isEmpty) return;
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

    final firestore = FirebaseFirestore.instance;
    final extraTourists = <Map<String, dynamic>>[];
    for (final uid in missing) {
      try {
        final snap = await firestore.collection('tourists').doc(uid).get();
        if (!snap.exists || snap.data() == null) continue;
        final row = <String, dynamic>{'id': snap.id, ...snap.data()!};
        _touristProfileByUid[uid] = row;
        extraTourists.add(row);
      } catch (e) {
        debugPrint('Tourism: tourists/$uid load failed: $e');
      }
    }
    if (extraTourists.isNotEmpty) {
      _tourists = _mergeTouristVisitsFromCheckIns([
        ..._tourists,
        ...extraTourists,
      ]);
      _totalTourists = _tourists.length;
    }
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
    if (profile == null) return c;
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
  }

  Widget _buildCheckInProfileAvatar(
    Map<String, dynamic> c, {
    double radius = 20,
  }) {
    final profile = c['touristProfile'] as Map<String, dynamic>?;
    final row = profile ?? c;
    final avatar = _touristAvatarImage(row);
    final name = c['touristName']?.toString() ?? '?';
    final initial =
        name.trim().isNotEmpty ? name.trim()[0].toUpperCase() : '?';
    return CircleAvatar(
      radius: radius,
      backgroundColor: _primaryOrange.withOpacity(0.15),
      backgroundImage: avatar,
      child: avatar == null
          ? Text(
              initial,
              style: TextStyle(
                color: _primaryOrange,
                fontWeight: FontWeight.bold,
                fontSize: radius * 0.85,
              ),
            )
          : null,
    );
  }

  Widget _buildCheckInTouristCell(Map<String, dynamic> c) {
    final name = c['touristName']?.toString() ?? 'Tourist';
    final email = c['touristEmail']?.toString() ?? '';
    return Row(
      children: [
        _buildCheckInProfileAvatar(c),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                name,
                style: const TextStyle(
                  color: _textDark,
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              if (email.isNotEmpty)
                Text(
                  email,
                  style: TextStyle(color: _textMuted, fontSize: 11),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
            ],
          ),
        ),
      ],
    );
  }

  Map<String, dynamic> _recentActivityFromCheckIn(Map<String, dynamic> c) {
    final location = c['location']?.toString().trim();
    final spotLabel = (location != null && location.isNotEmpty)
        ? location
        : (c['spotId']?.toString() ?? '').replaceAll('_', ' ');
    return <String, dynamic>{
      'icon': Icons.qr_code_scanner_rounded,
      'color': _primaryOrange,
      'title': c['touristName'] ?? c['userId']?.toString() ?? 'Tourist',
      'description': 'Checked in at ${spotLabel.isNotEmpty ? spotLabel : 'Unknown spot'}',
      'time': _formatTime(c['timestamp']),
    };
  }

  /// Derives per-tourist visit counts from currently loaded `_checkIns`.
  /// This keeps "Visits" in the tourists table aligned with QR check-ins.
  List<Map<String, dynamic>> _mergeTouristVisitsFromCheckIns(
    List<Map<String, dynamic>> tourists,
  ) {
    if (tourists.isEmpty) return tourists;

    final deduped = _dedupeCheckInsByTouristSpotAndDay(_checkIns);
    final Map<String, int> visitsByUid = <String, int>{};
    for (final c in deduped) {
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

  /// Keeps at most one check-in per (tourist, spot, local calendar day).
  /// If duplicates exist, keeps the latest timestamp entry.
  List<Map<String, dynamic>> _dedupeCheckInsByTouristSpotAndDay(
    List<Map<String, dynamic>> rows,
  ) {
    final Map<String, Map<String, dynamic>> bestByKey =
        <String, Map<String, dynamic>>{};
    final Map<String, DateTime> bestTimeByKey = <String, DateTime>{};

    for (final c in rows) {
      final uid =
          (c['userId']?.toString().trim() ??
                  c['tourist_id']?.toString().trim() ??
                  '')
              .trim();
      final spot =
          (c['spotId']?.toString().trim() ??
                  c['spot_id']?.toString().trim() ??
                  '')
              .trim();
      final t = _parseCheckInTimestamp(c);
      if (uid.isEmpty || spot.isEmpty || t == null) {
        // Keep non-standard rows with a unique synthetic key.
        final key = 'raw:${c['id'] ?? c.hashCode}';
        bestByKey[key] = c;
        bestTimeByKey[key] = t ?? DateTime.fromMillisecondsSinceEpoch(0);
        continue;
      }
      final dayKey =
          '${t.year}-${t.month.toString().padLeft(2, '0')}-${t.day.toString().padLeft(2, '0')}';
      final key = '$uid|$spot|$dayKey';
      final prevTime = bestTimeByKey[key];
      if (prevTime == null || t.isAfter(prevTime)) {
        bestByKey[key] = c;
        bestTimeByKey[key] = t;
      }
    }

    final out = bestByKey.values.toList();
    out.sort((a, b) {
      final ta = _parseCheckInTimestamp(a);
      final tb = _parseCheckInTimestamp(b);
      if (ta == null && tb == null) return 0;
      if (ta == null) return 1;
      if (tb == null) return -1;
      return tb.compareTo(ta);
    });
    return out;
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
    if (_checkIns.isEmpty) return 0;
    final dates = <DateTime>{};
    for (final c in _checkIns) {
      final d = _parseCheckInTimestamp(c);
      if (d != null) dates.add(DateTime(d.year, d.month, d.day));
    }
    if (dates.isEmpty) return 0;
    final min = dates.reduce((a, b) => a.isBefore(b) ? a : b);
    final max = dates.reduce((a, b) => a.isAfter(b) ? a : b);
    final days = max.difference(min).inDays + 1;
    return days > 0 ? (_checkIns.length / days).round() : _checkIns.length;
  }

  String get _lguAnalyticsPeakHour {
    final byHour = <int, int>{};
    for (final c in _checkIns) {
      final d = _parseCheckInTimestamp(c);
      if (d != null) {
        final h = d.hour;
        byHour[h] = (byHour[h] ?? 0) + 1;
      }
    }
    if (byHour.isEmpty) return '—';
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
    for (final t in _tourists) {
      final o = _getTouristOrigin(t).trim();
      if (o.isNotEmpty && o != '—') {
        counts[o] = (counts[o] ?? 0) + 1;
      } else {
        final one = t['nationality']?.toString().trim();
        if (one != null && one.isNotEmpty) {
          counts[one] = (counts[one] ?? 0) + 1;
        }
      }
    }
    if (counts.isEmpty) return '—';
    final top = counts.entries.reduce((a, b) => a.value >= b.value ? a : b).key;
    return _compactOriginForAnalyticsCard(top);
  }

  /// Short label for analytics cards (avoids overflow on long addresses).
  String _compactOriginForAnalyticsCard(String origin) {
    final trimmed = origin.trim();
    if (trimmed.isEmpty || trimmed == '—') return '—';
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
    for (final c in _checkIns) {
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
    for (final c in _checkIns) {
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

  /// Check-ins with [timestamp] in [start]–[end] inclusive (by local calendar day).
  List<Map<String, dynamic>> _checkInsInDateRange(
    DateTime start,
    DateTime end,
  ) {
    final startNorm = DateTime(start.year, start.month, start.day);
    final endNorm = DateTime(end.year, end.month, end.day, 23, 59, 59, 999);
    return _checkIns.where((c) {
      final t = _parseCheckInTimestamp(c);
      if (t == null) return false;
      return !t.isBefore(startNorm) && !t.isAfter(endNorm);
    }).toList();
  }

  String _buildCheckInsCsv(List<Map<String, dynamic>> rows) {
    final buf = StringBuffer(
      'Timestamp,Spot ID,Spot Name,User ID,Municipality,Municipality ID\n',
    );
    for (final c in rows) {
      final t = _parseCheckInTimestamp(c);
      final when = t != null ? t.toIso8601String() : '';
      final spotId = c['spotId']?.toString() ?? c['spot_id']?.toString() ?? '';
      final spotName = (c['spot_name']?.toString() ?? '').replaceAll('"', '""');
      final uid = c['userId']?.toString() ?? c['tourist_id']?.toString() ?? '';
      final mun = (c['municipality']?.toString() ?? '').replaceAll('"', '""');
      final mid = c['municipalityId']?.toString() ?? '';
      buf.write('"$when","$spotId","$spotName","$uid","$mun","$mid"\n');
    }
    return buf.toString();
  }

  void _toggleSidebar() {
    setState(() => _isSidebarExpanded = !_isSidebarExpanded);
  }

  @override
  Widget build(BuildContext context) {
    final outerPadding = _isMobile
        ? EdgeInsets.zero
        : const EdgeInsets.only(top: 25, right: 25, bottom: 25);
    return Container(
      color: _primaryOrange,
      padding: outerPadding,
      child: Scaffold(
        backgroundColor: _darkBg,
        body: _isMobile
            ? _buildMobileBody()
            : Row(
                children: [
                  if (_isSidebarExpanded) _buildSidebar(),
                  if (_isSidebarExpanded)
                    const SizedBox(
                      width: 1,
                      child: ColoredBox(color: _sidebarBg),
                    ),
                  Expanded(child: _buildMainContent()),
                ],
              ),
        bottomNavigationBar: null,
      ),
    );
  }

  Widget _buildMobileBody() {
    final screenW = MediaQuery.of(context).size.width;
    final drawerWidth = (screenW * 0.8).clamp(240.0, 300.0);

    return Stack(
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
            color: _sidebarBg,
            elevation: 12,
            child: SafeArea(
              bottom: false,
              child: Column(
                children: [
                  const SizedBox(height: 8),
                  _buildLogoRow(expanded: true),
                  _buildSidebarProfileStrip(),
                  _buildSidebarNavScroll(expanded: true),
                  const SizedBox(height: 10),
                  _buildLogoutButton(expanded: true),
                  const SizedBox(height: 12),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildLogoutButton({required bool expanded}) {
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: expanded ? 16 : 8),
      child: AppLogoutButton(
        style: AppLogoutStyle.sidebarOnOrange,
        expanded: expanded,
        onPressed: _logout,
      ),
    );
  }

  Widget _buildSidebar() {
    final expanded = _isSidebarExpanded;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 250),
      width: expanded ? 260 : 80,
      color: _sidebarBg,
      child: Column(
        children: [
          const SizedBox(height: 8),
          _buildLogoRow(expanded: expanded),
          if (expanded) _buildSidebarProfileStrip(),
          _buildSidebarNavScroll(expanded: expanded),
          const SizedBox(height: 10),
          _buildLogoutButton(expanded: expanded),
          const SizedBox(height: 12),
        ],
      ),
    );
  }

  Widget _buildLogoRow({required bool expanded}) {
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: expanded ? 16 : 12),
      child: Row(
        children: [
          Expanded(child: _buildLogo(expanded: expanded)),
          if (expanded)
            Tooltip(
              message: 'Collapse sidebar',
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: _toggleSidebar,
                  borderRadius: BorderRadius.circular(14),
                  child: Padding(
                    padding: const EdgeInsets.all(8),
                    child: Icon(
                      Icons.close_rounded,
                      color: Colors.white,
                      size: 20,
                    ),
                  ),
                ),
              ),
            )
          else
            Tooltip(
              message: 'Expand sidebar',
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: _toggleSidebar,
                  borderRadius: BorderRadius.circular(14),
                  child: Padding(
                    padding: const EdgeInsets.all(8),
                    child: Icon(
                      Icons.menu_rounded,
                      color: Colors.white,
                      size: 20,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildLogo({required bool expanded}) {
    const logoSize = 40.0;
    const logoSizeCollapsed = 32.0;

    if (!expanded) {
      return Center(
        child: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.12),
            borderRadius: BorderRadius.circular(12),
          ),
          child: TransparentLogo(
            width: logoSizeCollapsed,
            height: logoSizeCollapsed,
            fit: BoxFit.contain,
            errorIcon: Icons.travel_explore,
            errorIconSize: 20,
            errorIconColor: Colors.white,
          ),
        ),
      );
    }

    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.12),
            borderRadius: BorderRadius.circular(12),
          ),
          child: TransparentLogo(
            width: logoSize,
            height: logoSize,
            fit: BoxFit.contain,
            errorIcon: Icons.travel_explore,
            errorIconSize: 24,
            errorIconColor: Colors.white,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'ATMOS TRS',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 17,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 0.3,
                ),
                overflow: TextOverflow.ellipsis,
              ),
              Text(
                'Tourism Office',
                style: TextStyle(
                  color: Colors.white.withOpacity(0.82),
                  fontSize: 12,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// Profile row under logo — flat strip, no nested card box.
  Widget _buildSidebarProfileStrip() {
    final city = _municipalityName?.trim();
    final displayName = _profileName.isNotEmpty
        ? _profileName
        : (city != null && city.isNotEmpty ? city : 'Tourism Office');
    final subtitle = city != null && city.isNotEmpty
        ? 'Tourism Office · $city'
        : 'Misamis Occidental';

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      child: Column(
        children: [
          Divider(color: Colors.white.withOpacity(0.22), height: 1),
          const SizedBox(height: 16),
          Row(
            children: [
              _buildSidebarAvatar(size: 40),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      displayName,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.78),
                        fontSize: 11,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: Colors.white.withOpacity(0.45)),
                ),
                child: const Text(
                  'Staff',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
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
  Future<List<Map<String, dynamic>>> _loadRegisteredTouristsForMunicipality({
    required FirebaseFirestore firestore,
    required List<String> queryIds,
    required Set<String> checkInUserIds,
  }) async {
    final byId = <String, Map<String, dynamic>>{};

    for (final mid in queryIds) {
      try {
        final snap = await firestore
            .collection('tourists')
            .where('registrationMunicipalityId', isEqualTo: mid)
            .limit(250)
            .get()
            .timeout(const Duration(seconds: 20));
        for (final doc in snap.docs) {
          byId[doc.id] = {'id': doc.id, ...doc.data()};
        }
      } catch (e) {
        debugPrint('Tourism: tourists registrationMunicipalityId=$mid: $e');
      }
    }

    for (final uid in checkInUserIds) {
      if (byId.containsKey(uid)) continue;
      try {
        final doc = await firestore
            .collection('tourists')
            .doc(uid)
            .get()
            .timeout(const Duration(seconds: 12));
        if (!doc.exists || doc.data() == null) continue;
        final row = <String, dynamic>{'id': doc.id, ...doc.data()!};
        if (RegistrationMunicipalityResolver.touristMatchesMunicipality(
          tourist: row,
          queryIds: queryIds,
          checkInUserIds: checkInUserIds,
        )) {
          byId[uid] = row;
        }
      } catch (e) {
        debugPrint('Tourism: tourists/$uid: $e');
      }
    }

    return byId.values.toList();
  }

  /// Sidebar + drawer: scrollable nav; Settings is header icon only (not listed here).
  Widget _buildSidebarNavScroll({required bool expanded}) {
    final bottomInset = MediaQuery.paddingOf(context).bottom;
    return Expanded(
      child: SingleChildScrollView(
        padding: EdgeInsets.only(top: 20, bottom: 20 + bottomInset),
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
                      bottomMargin: i == 0 ? 14 : 6,
                    ),
                  const SizedBox(height: 4),
                  _buildTourismNavItem(
                    index: _reportsIndex,
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
    double bottomMargin = 6,
  }) {
    final item = _navItems[index];
    final isSelected = _selectedIndex == index;
    return Container(
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
            borderRadius: BorderRadius.circular(12),
            hoverColor: Colors.white.withOpacity(0.08),
            splashColor: Colors.white.withOpacity(0.12),
            child: Container(
              padding: EdgeInsets.symmetric(
                horizontal: expanded ? 12 : 10,
                vertical: expanded ? 11 : 12,
              ),
              decoration: BoxDecoration(
                color: isSelected
                    ? Colors.white
                    : Colors.white.withOpacity(0.05),
                borderRadius: BorderRadius.circular(12),
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
                        : Colors.white.withOpacity(0.75),
                    size: 22,
                  ),
                  if (expanded) ...[
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        item.label,
                        style: TextStyle(
                          color: isSelected
                              ? _primaryOrange
                              : Colors.white.withOpacity(0.88),
                          fontSize: 14,
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
      );
    }

    switch (_selectedIndex) {
      case 0:
        return _buildDashboardContent();
      case 1:
        return _buildCheckInsContent();
      case 2:
        return _buildTouristSpotsContent();
      case _spotQRCodesIndex:
        return _buildSpotQRCodesContent();
      case 4:
        return _buildTouristsContent();
      case 5:
        return _buildVRToursContent();
      case _analyticsIndex:
        return _buildAnalyticsContent();
      case _reportsIndex:
        return _buildReportsContent();
      case _settingsIndex:
        return _buildSettingsContent();
      default:
        return _buildDashboardContent();
    }
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
        _buildMobileHeaderProfileAction(),
      ],
    ];

    return Container(
      margin: EdgeInsets.all(_isMobile ? 10 : 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _panelBorder),
        boxShadow:
            frameShadow ??
            [
              BoxShadow(
                color: Colors.black.withOpacity(0.04),
                blurRadius: 12,
                offset: const Offset(0, 4),
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
    );
  }

  // ==================== DASHBOARD SECTION ====================
  Widget _buildDashboardContent() {
    return RefreshIndicator(
      onRefresh: _loadData,
      color: _primaryOrange,
      child: _buildFramedContentShell(
        title: 'Dashboard',
        subtitle: _municipalityName != null
            ? '$_municipalityName – Tourism Office'
            : 'Tourism Office Management Panel',
        preBody: _showAllDataBanner
            ? Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 10,
                ),
                color: _accentOrange.withOpacity(0.2),
                child: Row(
                  children: [
                    Icon(Icons.info_outline, color: _primaryOrange, size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Showing all data. Use a municipality-specific account (e.g. tourism.oroquieta@misocc.gov.ph) to see only your municipality\'s check-ins and spots.',
                        style: TextStyle(fontSize: 13, color: _textDark),
                      ),
                    ),
                  ],
                ),
              )
            : null,
        body: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: EdgeInsets.all(_isMobile ? 16 : 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildQuickStats(),
              const SizedBox(height: 24),
              _buildSpotQRCodesDashboardCard(),
              const SizedBox(height: 24),
              _buildRecentActivity(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(
    String title, {
    String? subtitle,
    List<Widget>? actions,
    bool showAddSpotButton = false,
  }) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: _isMobile ? 16 : 24,
        vertical: 16,
      ),
      decoration: BoxDecoration(
        // Pure white header background (reference style)
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.06),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          if (!_isSidebarExpanded)
            IconButton(
              onPressed: _toggleSidebar,
              icon: Icon(Icons.menu, color: _textDark),
            ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    color: _textDark,
                    fontSize: _isMobile ? 18 : 22,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                if (subtitle != null)
                  Text(
                    subtitle,
                    style: TextStyle(
                      color: const Color(0xFF374151),
                      fontSize: _isMobile ? 12 : 14,
                      fontWeight: FontWeight.w500,
                      height: 1.35,
                    ),
                  ),
              ],
            ),
          ),
          if (actions != null) ...actions,
          _buildHeaderAction(
            Icons.settings_outlined,
            highlighted: _selectedIndex == _settingsIndex,
            onTap: _openSettings,
          ),
          const SizedBox(width: 8),
          if (!_isMobile) ...[
            _buildHeaderAction(
              Icons.notifications_outlined,
              badge: _notifications.isNotEmpty
                  ? '${_notifications.length}'
                  : null,
              onTap: _showNotificationsDialog,
            ),
            const SizedBox(width: 12),
            if (showAddSpotButton) ...[
              const SizedBox(width: 12),
              ElevatedButton.icon(
                onPressed: _showAddSpotDialog,
                icon: const Icon(Icons.add, size: 18),
                label: const Text('+ Add Spot'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: _primaryOrange,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 12,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(32),
                  ),
                ),
              ),
            ],
            const SizedBox(width: 12),
            _buildDesktopHeaderProfileMenu(),
          ],
          if (_isMobile && showAddSpotButton)
            IconButton(
              tooltip: 'Add tourist spot',
              onPressed: _showAddSpotDialog,
              icon: Icon(
                Icons.add_circle_outline,
                color: _primaryOrange,
                size: 28,
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildDesktopHeaderProfileMenu() {
    return PopupMenuButton<String>(
      tooltip: 'Account',
      onSelected: _handleProfileMenuSelection,
      itemBuilder: (context) => _buildProfileMenuItems(),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: const Color(0xFFF3F4F6),
          borderRadius: BorderRadius.circular(18),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildSidebarAvatar(size: 30),
            const SizedBox(width: 8),
            Text(
              _profileName.isNotEmpty ? _profileName : 'Tourism',
              style: const TextStyle(
                color: _textDark,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(width: 6),
            const Icon(
              Icons.keyboard_arrow_down_rounded,
              color: _textDark,
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

  Widget _buildMobileHeaderProfileAction() {
    return PopupMenuButton<String>(
      tooltip: 'Account',
      onSelected: _handleProfileMenuSelection,
      itemBuilder: (context) => _buildProfileMenuItems(),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        decoration: BoxDecoration(
          color: const Color(0xFFF3F4F6),
          borderRadius: BorderRadius.circular(18),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildSidebarAvatar(size: 30),
            const SizedBox(width: 6),
            Icon(Icons.keyboard_arrow_down_rounded, color: _textDark, size: 18),
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
  }) {
    final isSettings = icon == Icons.settings_outlined;
    final isNotifications = icon == Icons.notifications_outlined;
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
                color: highlighted
                    ? _primaryOrange.withOpacity(0.15)
                    : Colors.grey.shade200,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Icon(
                icon,
                color: highlighted ? _primaryOrange : _textMuted,
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
    final activeVrCount = _vrTours.where((v) => v['status'] == 'Active').length;
    final inactiveSpots = (_touristSpots.length - _activeSpots).clamp(0, 999);
    final stats = [
      _StatCard(
        title: 'Today\'s visits',
        value: '$_todayCheckIns',
        subtitle: 'Recorded today',
        icon: Icons.qr_code_scanner_rounded,
        color: _kpiOrange,
      ),
      _StatCard(
        title: _storedMunicipalityId != null
            ? 'Visitors'
            : 'Visitors (province)',
        value: '$_totalTourists',
        subtitle: 'Linked to QR visits',
        icon: Icons.people_alt_rounded,
        color: _kpiBlue,
      ),
      _StatCard(
        title: 'Active Spots',
        value: '$_activeSpots',
        subtitle: inactiveSpots > 0
            ? '$inactiveSpots inactive'
            : 'All spots active',
        icon: Icons.place_rounded,
        color: _kpiGreen,
      ),
      _StatCard(
        title: 'VR Tours',
        value: '$_totalVRTours',
        subtitle: activeVrCount > 0
            ? '$activeVrCount active'
            : 'None active yet',
        icon: Icons.vrpano_rounded,
        color: _kpiPurple,
      ),
    ];

    final crossCount = _isMobile ? 2 : (_isTablet ? 2 : 4);
    final childAspectRatio = crossCount == 2 ? (_isMobile ? 1.05 : 1.2) : 1.55;

    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: crossCount,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
        childAspectRatio: childAspectRatio,
      ),
      itemCount: stats.length,
      itemBuilder: (context, index) => _buildStatCard(stats[index]),
    );
  }

  List<double> _last7DayCheckInCounts() {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final counts = List<double>.filled(7, 0);
    for (final c in _checkIns) {
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

  List<double> _statSparklineValues(_StatCard stat) {
    if (stat.title.contains('visit') || stat.title.contains('Check-in')) {
      final week = _last7DayCheckInCounts();
      if (week.any((v) => v > 0)) return week;
    }
    final n = double.tryParse(stat.value.replaceAll(',', '')) ?? 0;
    final base = n > 0 ? n : 1.0;
    return List.generate(8, (i) => base * (0.82 + 0.18 * (i / 7)));
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

  String _lguQrPayloadString(String municipalityId) {
    final coords = getMunicipalityAnchorCoordinates(municipalityId);
    if (coords != null) {
      return lguQrData(
        municipalityId,
        anchorLat: coords.lat,
        anchorLng: coords.lng,
      );
    }
    return lguQrData(municipalityId);
  }

  Widget _buildSpotQRCodesDashboardCard() {
    final mid = _effectiveLguMunicipalityId();
    final lguQrDataStr = mid != null ? _lguQrPayloadString(mid) : null;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(28),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.08),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
          BoxShadow(
            color: _primaryOrange.withOpacity(0.08),
            blurRadius: 24,
            offset: const Offset(0, 10),
            spreadRadius: -10,
          ),
        ],
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
                        color: _primaryOrange.withOpacity(0.15),
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
                        'Municipality QR code',
                        style: TextStyle(
                          color: _textDark,
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
                if (lguQrDataStr != null) ...[
                  const SizedBox(height: 16),
                  Center(
                    child: Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: Colors.grey.shade200),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.06),
                            blurRadius: 8,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: QrImageView(
                        data: lguQrDataStr,
                        version: QrVersions.auto,
                        size: 120,
                        backgroundColor: Colors.white,
                        errorCorrectionLevel: QrErrorCorrectLevel.H,
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 12),
                Text(
                  'Use one official QR code for your municipality. Download PNG or PDF for posters and sharing.',
                  style: TextStyle(
                    color: Color(0xFF4B5563),
                    fontSize: 14,
                    height: 1.45,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: () =>
                        setState(() => _selectedIndex = _spotQRCodesIndex),
                    icon: const Icon(Icons.qr_code_2_rounded, size: 20),
                    label: const Text('View & download municipality QR'),
                    style: FilledButton.styleFrom(
                      backgroundColor: _primaryOrange,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(22),
                      ),
                    ),
                  ),
                ),
              ],
            )
          : Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                if (lguQrDataStr != null)
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: Colors.grey.shade200),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.06),
                          blurRadius: 8,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: QrImageView(
                      data: lguQrDataStr,
                      version: QrVersions.auto,
                      size: 100,
                      backgroundColor: Colors.white,
                      errorCorrectionLevel: QrErrorCorrectLevel.H,
                    ),
                  )
                else
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: _primaryOrange.withOpacity(0.15),
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
                        'Municipality QR code',
                        style: TextStyle(
                          color: _textDark,
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Use one official QR code for your municipality. Download PNG or PDF for posters and sharing.',
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
                  label: const Text('View & download municipality QR'),
                  style: FilledButton.styleFrom(
                    backgroundColor: _primaryOrange,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 14,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(22),
                    ),
                  ),
                ),
              ],
            ),
    );
  }

  Widget _buildStatCard(_StatCard stat) {
    final sparkH = _isMobile ? 22.0 : 28.0;
    final valueSize = _isMobile ? 22.0 : 26.0;
    final labelSize = _isMobile ? 10.5 : 11.0;

    return Container(
      decoration: BoxDecoration(
        color: stat.color,
        borderRadius: BorderRadius.circular(12),
      ),
      clipBehavior: Clip.antiAlias,
      padding: EdgeInsets.fromLTRB(
        _isMobile ? 12 : 14,
        _isMobile ? 10 : 12,
        _isMobile ? 12 : 14,
        _isMobile ? 8 : 10,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  stat.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.92),
                    fontSize: labelSize,
                    fontWeight: FontWeight.w500,
                    height: 1.2,
                  ),
                ),
              ),
              Icon(
                stat.icon,
                color: Colors.white.withOpacity(0.35),
                size: _isMobile ? 18 : 20,
              ),
            ],
          ),
          SizedBox(height: _isMobile ? 4 : 6),
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
          if (stat.subtitle != null) ...[
            const SizedBox(height: 4),
            Text(
              stat.subtitle!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: Colors.white.withOpacity(0.78),
                fontSize: _isMobile ? 9.5 : 10,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
          const Spacer(),
          SizedBox(
            height: sparkH,
            width: double.infinity,
            child: CustomPaint(
              painter: _TourismMiniSparklinePainter(
                values: _statSparklineValues(stat),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRecentActivity() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Recent Activity',
          style: TextStyle(
            color: const Color(0xFF111827),
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
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
                borderRadius: BorderRadius.circular(26),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.08),
                    blurRadius: 16,
                    offset: const Offset(0, 6),
                  ),
                  BoxShadow(
                    color: _primaryOrange.withOpacity(0.05),
                    blurRadius: 18,
                    offset: const Offset(0, 8),
                    spreadRadius: -10,
                  ),
                ],
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: ((activity['color'] as Color?) ?? _primaryOrange)
                          .withOpacity(0.15),
                      borderRadius: BorderRadius.circular(20),
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
      final matchesSearch =
          searchQuery.isEmpty ||
          (c['touristName']?.toString() ?? '').toLowerCase().contains(
            searchQuery,
          ) ||
          (c['touristId']?.toString() ?? '').toLowerCase().contains(
            searchQuery,
          ) ||
          (c['userId']?.toString() ?? '').toLowerCase().contains(searchQuery) ||
          (c['location']?.toString() ?? '').toLowerCase().contains(searchQuery) ||
          (c['spot_name']?.toString() ?? '').toLowerCase().contains(searchQuery) ||
          (c['spotId']?.toString() ?? '').toLowerCase().contains(searchQuery);

      final matchesStatus =
          _checkInStatusFilter == 'All' || c['status'] == _checkInStatusFilter;

      return matchesSearch && matchesStatus;
    }).toList();

    return RefreshIndicator(
      onRefresh: _loadData,
      color: _primaryOrange,
      child: _buildFramedContentShell(
        title: 'Visit log',
        subtitle:
            'Shows QR visits at tourist spots in your municipality only '
            '(${_municipalityName ?? _storedMunicipalityId ?? 'your LGU'}). '
            'A scan at a spot in another town appears on that town\'s tourism dashboard.',
        body: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: EdgeInsets.all(_isMobile ? 12 : 16),
          child: _wrapTourismPanel(
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildCheckInsFilters(),
                const SizedBox(height: 16),
                if (filteredCheckIns.isEmpty)
                  _buildEmptyState(
                    'No visits found',
                    icon: Icons.qr_code_scanner_rounded,
                    iconColor: _primaryOrange,
                    subtitle:
                        'Scans from your municipality QR will appear here.',
                  )
                else if (_isMobile)
                  _buildCheckInsListMobile(filteredCheckIns)
                else
                  _buildCheckInsTable(filteredCheckIns),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCheckInsFilters() {
    final searchField = AppSearchBar(
      controller: _checkInsSearchController,
      hintText: 'Search by name, ID, or location...',
      onChanged: (value) => setState(() {}),
      horizontalPadding: 0,
      backgroundColor: Colors.white,
      borderColor: _panelBorder,
      showMicrophone: false,
      height: 48,
      showShadow: false,
    );

    final filterChip = Container(
      height: 48,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      alignment: Alignment.centerLeft,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: _panelBorder),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: _checkInStatusFilter,
          isExpanded: true,
          borderRadius: BorderRadius.circular(14),
          dropdownColor: Colors.white,
          icon: Icon(Icons.expand_more_rounded, color: _textDark, size: 22),
          style: const TextStyle(
            color: _textDark,
            fontWeight: FontWeight.w600,
            fontSize: 14,
          ),
          items: ['All', 'Verified', 'Pending']
              .map(
                (s) => DropdownMenuItem<String>(
                  value: s,
                  child: Text(
                    s,
                    style: const TextStyle(
                      color: _textDark,
                      fontWeight: FontWeight.w500,
                      fontSize: 14,
                    ),
                  ),
                ),
              )
              .toList(),
          onChanged: (value) => setState(() => _checkInStatusFilter = value!),
        ),
      ),
    );

    if (_isMobile) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          searchField,
          const SizedBox(height: 12),
          SizedBox(width: double.infinity, child: filterChip),
        ],
      );
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(child: searchField),
        const SizedBox(width: 14),
        SizedBox(width: 168, child: filterChip),
      ],
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
    const headerBg = Color(0xFFFFF4E8);
    const stripe = Color(0xFFFFFBF7);
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
          border: Border.all(color: _primaryOrange.withOpacity(0.12), width: 1),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 14,
              offset: const Offset(0, 4),
            ),
            BoxShadow(
              color: _primaryOrange.withOpacity(0.06),
              blurRadius: 18,
              offset: const Offset(0, 6),
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
                      color: _primaryOrange.withOpacity(0.10),
                    ),
                    top: BorderSide(color: _primaryOrange.withOpacity(0.12)),
                    bottom: BorderSide(color: _primaryOrange.withOpacity(0.12)),
                  ),
                  columns: [
                    const DataColumn(label: Text('Tourist')),
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
          SelectableText(
            c['touristId'] ?? 'N/A',
            style: const TextStyle(
              color: _textMuted,
              fontWeight: FontWeight.w500,
              fontSize: 12,
            ),
          ),
        ),
        DataCell(
          Text(c['location'] ?? '', style: const TextStyle(color: _textDark)),
        ),
        DataCell(
          Text(
            _formatTime(c['timestamp']),
            style: const TextStyle(color: _textMuted, fontSize: 13),
          ),
        ),
        DataCell(_buildStatusBadge(c['status'])),
        DataCell(
          SizedBox(
            width: 88,
            child: Center(
              child: Tooltip(
                message: 'View details',
                child: Material(
                  color: _primaryOrange.withOpacity(0.12),
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
            Center(child: _buildCheckInProfileAvatar(checkIn, radius: 36)),
            const SizedBox(height: 12),
            Center(
              child: Text(
                checkIn['touristName']?.toString() ?? 'Tourist',
                style: const TextStyle(
                  color: _textDark,
                  fontWeight: FontWeight.w700,
                  fontSize: 16,
                ),
                textAlign: TextAlign.center,
              ),
            ),
            if ((checkIn['touristEmail']?.toString() ?? '').isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Center(
                  child: Text(
                    checkIn['touristEmail'].toString(),
                    style: TextStyle(color: _textMuted, fontSize: 12),
                  ),
                ),
              ),
            const SizedBox(height: 12),
            _buildDetailRow('Tourist ID', checkIn['touristId'] ?? 'N/A'),
            if ((checkIn['touristOrigin']?.toString() ?? '').isNotEmpty)
              _buildDetailRow('Origin', checkIn['touristOrigin'].toString()),
            _buildDetailRow('Location', checkIn['location']),
            _buildDetailRow('Time', _formatTime(checkIn['timestamp'])),
            _buildDetailRow('Status', checkIn['status']),
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

  void _verifyCheckIn(Map<String, dynamic> checkIn) {
    setState(() {
      final index = _checkIns.indexWhere((c) => c['id'] == checkIn['id']);
      if (index != -1) {
        _checkIns[index]['status'] = 'Verified';
        _todayCheckIns++;
      }
    });

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Visit verified successfully'),
        backgroundColor: _primaryOrange,
      ),
    );
  }

  // ==================== TOURIST SPOTS SECTION ====================
  Future<void> _runBackfillSpotQrMetadata({bool showSnack = true}) async {
    if (_isBackfillingSpotQr) return;
    setState(() => _isBackfillingSpotQr = true);
    try {
      final result =
          await TouristSpotsFirestoreService.enforceCanonicalSpotDocuments();
      if (!mounted || !showSnack) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            (result.upserted == 0 &&
                    result.removed == 0 &&
                    result.backfilled == 0)
                ? 'No spot changes needed (or you may be offline).'
                : 'Strict sync complete: kept ${result.upserted} canonical spot(s) '
                      '(slug document ids), removed ${result.removed} other doc(s), '
                      'updated ${result.backfilled} QR field set(s).',
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

  /// Banner: backfill `qrValue`, `qr_payload`, `createdAt` for older `tourist_spots` docs.
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
                          'Sync QR fields to Firestore',
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
                    'Strict mode: enforces exactly 17 canonical tourist spots in tourist_spots '
                    '(document ids are spot slugs like oroquieta_city_boulevard_and_peoples_park, not municipality names). '
                    'Other documents are removed; then qrValue, qr_payload, and createdAt are filled.',
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
                        _isBackfillingSpotQr ? 'Syncing…' : 'Sync now',
                        style: const TextStyle(fontWeight: FontWeight.w600),
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
                          'Sync QR fields to Firestore',
                          style: TextStyle(
                            color: _textDark,
                            fontWeight: FontWeight.w700,
                            fontSize: 15,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'Strict mode keeps only the 17 canonical spot documents (ids are spot slugs; '
                          'each row still has municipalityId for dashboards). Other tourist_spots docs '
                          'are deleted, then qrValue, qr_payload, and createdAt are filled. '
                          'Open Firebase Console → Firestore → tourist_spots to verify.',
                          style: TextStyle(
                            color: _textMuted,
                            fontSize: 13,
                            height: 1.4,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 16),
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
                        horizontal: 18,
                        vertical: 12,
                      ),
                    ),
                    label: Text(
                      _isBackfillingSpotQr ? 'Syncing…' : 'Sync now',
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              ),
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

      return matchesSearch && matchesCategory;
    }).toList();

    return RefreshIndicator(
      onRefresh: _loadData,
      color: _primaryOrange,
      child: _buildFramedContentShell(
        title: 'Tourist Spots',
        subtitle: 'Manage tourist destinations',
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

  /// One QR per LGU (`ATMOS-TRS-LGU:municipalityId` + optional anchor) — downloadable PNG/PDF.
  Widget _buildLguQrCardForDashboard(
    String municipalityId,
    String displayName,
  ) {
    final coords = getMunicipalityAnchorCoordinates(municipalityId);
    final qrData = _lguQrPayloadString(municipalityId);
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: _tourismPanelDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: _primaryOrange.withOpacity(0.1),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.location_city_rounded,
                  color: _primaryOrange,
                  size: 16,
                ),
                const SizedBox(width: 8),
                Text(
                  'Your LGU QR code',
                  style: TextStyle(
                    color: _primaryOrange,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          Text(
            displayName,
            style: TextStyle(
              color: _textDark,
              fontSize: 22,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.2,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Unique to your municipality — download for posters, flyers, or social media.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: _textMuted,
              fontSize: 13,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 18),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: Colors.grey.shade200),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.07),
                  blurRadius: 14,
                  offset: const Offset(0, 5),
                ),
              ],
            ),
            child: QrImageView(
              data: qrData,
              version: QrVersions.auto,
              size: _isMobile ? 190 : 210,
              backgroundColor: Colors.white,
              errorCorrectionLevel: QrErrorCorrectLevel.H,
            ),
          ),
          const SizedBox(height: 12),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.75),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: Colors.grey.shade200),
            ),
            child: SelectableText(
              qrData,
              style: TextStyle(
                color: _textMuted,
                fontSize: 11,
                fontFamily: 'monospace',
                height: 1.25,
              ),
            ),
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 12,
            runSpacing: 8,
            alignment: WrapAlignment.center,
            children: [
              ElevatedButton.icon(
                onPressed: () async {
                  await downloadLguQrPng(
                    municipalityId,
                    anchorLat: coords?.lat,
                    anchorLng: coords?.lng,
                  );
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text(
                          'If download did not start, check browser downloads or use the share sheet on mobile.',
                        ),
                        backgroundColor: _primaryOrange,
                        behavior: SnackBarBehavior.floating,
                      ),
                    );
                  }
                },
                icon: Icon(
                  Icons.download_rounded,
                  color: Colors.white,
                  size: 20,
                ),
                label: const Text(
                  'Download PNG',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: _primaryOrange,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 18,
                    vertical: 12,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
              ),
              OutlinedButton.icon(
                onPressed: () async {
                  await downloadLguQrPdf(
                    municipalityId,
                    displayName,
                    anchorLat: coords?.lat,
                    anchorLng: coords?.lng,
                  );
                },
                icon: Icon(
                  Icons.picture_as_pdf_rounded,
                  color: _primaryOrange,
                  size: 20,
                ),
                label: Text(
                  'Download PDF',
                  style: TextStyle(
                    color: _primaryOrange,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                style: OutlinedButton.styleFrom(
                  side: BorderSide(color: _primaryOrange.withOpacity(0.45)),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 18,
                    vertical: 12,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSpotQRCodesContent() {
    final effectiveMunicipalityId = _effectiveLguMunicipalityId();
    final municipalityDisplayName =
        _effectiveLguQrDisplayName() ?? effectiveMunicipalityId;

    return RefreshIndicator(
      onRefresh: _loadData,
      color: _primaryOrange,
      child: _buildFramedContentShell(
        title: 'Spot QR Codes',
        subtitle: municipalityDisplayName != null
            ? 'One official LGU QR for $municipalityDisplayName only — use PNG/PDF for sharing and posters.'
            : 'One official municipality QR only — use PNG/PDF for sharing and posters.',
        body: effectiveMunicipalityId == null || effectiveMunicipalityId.isEmpty
            ? Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.qr_code_2_rounded, size: 64, color: _textMuted),
                    const SizedBox(height: 16),
                    Text(
                      'No municipality QR available yet',
                      style: TextStyle(color: _textMuted, fontSize: 16),
                    ),
                    const SizedBox(height: 8),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 24),
                      child: Text(
                        'Set your LGU municipality on the account (or ensure at least one tourist spot includes a municipality) so the official QR can load.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: _textMuted, fontSize: 14),
                      ),
                    ),
                  ],
                ),
              )
            : SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: EdgeInsets.all(_isMobile ? 12 : 16),
                child: _buildLguQrCardForDashboard(
                  effectiveMunicipalityId,
                  municipalityDisplayName ?? effectiveMunicipalityId,
                ),
              ),
      ),
    );
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
                  const SizedBox(height: 12),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      IconButton(
                        onPressed: () => _showEditSpotDialog(s),
                        icon: const Icon(
                          Icons.edit,
                          color: Colors.blue,
                          size: 20,
                        ),
                      ),
                      IconButton(
                        onPressed: () => _showDeleteSpotDialog(s),
                        icon: const Icon(
                          Icons.delete,
                          color: Colors.redAccent,
                          size: 20,
                        ),
                      ),
                    ],
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
                  DataCell(_buildStatusBadge(s.status)),
                  DataCell(
                    Row(
                      children: [
                        IconButton(
                          onPressed: () => _showEditSpotDialog(s),
                          icon: const Icon(
                            Icons.edit,
                            color: Colors.blue,
                            size: 18,
                          ),
                          tooltip: 'Edit',
                        ),
                        IconButton(
                          onPressed: () => _showDeleteSpotDialog(s),
                          icon: const Icon(
                            Icons.delete,
                            color: Colors.redAccent,
                            size: 18,
                          ),
                          tooltip: 'Delete',
                        ),
                        IconButton(
                          onPressed: () => _toggleSpotStatus(s),
                          icon: Icon(
                            s.status == 'Active'
                                ? Icons.visibility_off
                                : Icons.visibility,
                            color: Colors.orange,
                            size: 18,
                          ),
                          tooltip: s.status == 'Active'
                              ? 'Deactivate'
                              : 'Activate',
                        ),
                      ],
                    ),
                  ),
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
                      hintText: 'https://tiiny.host/… or your published tiiny.site URL',
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
                    );
                    final docId = await TouristSpotsFirestoreService.addSpot(
                      spot,
                    );
                    if (docId != null && spot.vrLink != null && spot.vrLink!.isNotEmpty) {
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
                        const SnackBar(
                          content: Text('Tourist spot added successfully'),
                          backgroundColor: _primaryOrange,
                        ),
                      );
                    } else if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Failed to add spot. Check Firebase.'),
                          backgroundColor: Colors.redAccent,
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
                      hintText: 'https://tiiny.host/… or your published tiiny.site URL',
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
          'In Google Maps: long-press the spot → copy coordinates. '
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

  Widget _buildTouristsContent() {
    final filteredTourists = _tourists.where((t) {
      final searchQuery = _touristsSearchController.text.toLowerCase();
      final name = t['fullName']?.toString() ?? t['name']?.toString() ?? '';
      final id = TouristIdHelper.displayForTourist(t);
      final origin = t['city']?.toString() ?? t['origin']?.toString() ?? '';
      final email = t['email']?.toString() ?? '';
      return searchQuery.isEmpty ||
          name.toLowerCase().contains(searchQuery) ||
          id.toLowerCase().contains(searchQuery) ||
          origin.toLowerCase().contains(searchQuery) ||
          email.toLowerCase().contains(searchQuery);
    }).toList();

    return RefreshIndicator(
      onRefresh: _loadData,
      color: _primaryOrange,
      child: _buildFramedContentShell(
        title: _storedMunicipalityId != null ? 'Registered visitors' : 'Visitors',
        subtitle: _storedMunicipalityId != null
            ? 'Tourists who registered via your municipality QR or selected your '
                  'city as a prior destination, plus anyone with a check-in here. '
                  'Province-wide list: Governor dashboard only.'
            : 'Assign an LGU municipality to your account to see visitor '
                  'profiles tied to your check-ins. Province-wide registrations '
                  'are on the Governor dashboard only.',
        body: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: EdgeInsets.all(_isMobile ? 12 : 16),
          child: _wrapTourismPanel(
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildTouristsFilters(),
                const SizedBox(height: 16),
                if (filteredTourists.isEmpty)
                  _buildEmptyState(
                    _storedMunicipalityId != null
                        ? 'No visitors yet'
                        : 'No visitors loaded',
                    icon: Icons.people_alt_rounded,
                    iconColor: _primaryOrange,
                    subtitle: _storedMunicipalityId != null
                        ? 'New sign-ups from your QR appear here after registration. '
                              'QR visits also appear in the Visit log.'
                        : 'Assign your LGU municipality to load visitor profiles from check-ins.',
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
            hintText: 'Search by name, ID, or origin...',
            onChanged: (value) => setState(() {}),
            horizontalPadding: 0,
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
    int visitCount(Map<String, dynamic> t) {
      final v = t['totalVisits'] ?? t['visits'] ?? 0;
      if (v is int) return v;
      if (v is num) return v.toInt();
      return int.tryParse(v.toString()) ?? 0;
    }

    final sorted = List<Map<String, dynamic>>.from(tourists)
      ..sort((a, b) => visitCount(b).compareTo(visitCount(a)));

    return Column(
      children: sorted.map((t) {
        final name = _getTouristDisplayName(t);
        final touristId = TouristIdHelper.displayForTourist(t);
        final origin = _getTouristOrigin(t);
        final visits = t['totalVisits'] ?? t['visits'] ?? 0;
        final isLocal = t['isLocal'] == true || t['localOrForeign'] == 'Local';
        final avatar = _touristAvatarImage(t);
        final hasProfileImage = avatar != null;

        return Container(
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.04),
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
                    CircleAvatar(
                      radius: 20,
                      backgroundColor: _primaryOrange.withOpacity(0.15),
                      backgroundImage: avatar,
                      child: hasProfileImage
                          ? null
                          : Text(
                              name.isNotEmpty
                                  ? name.substring(0, 1).toUpperCase()
                                  : '?',
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
                            name,
                            style: const TextStyle(
                              color: _textDark,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          Text(
                            touristId,
                            style: TextStyle(color: _textMuted, fontSize: 12),
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
                                ? Colors.green.withOpacity(0.12)
                                : Colors.purple.withOpacity(0.12),
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
                          style: TextStyle(
                            color: const Color(0xFF0284C7),
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
                  'From: $origin',
                  style: TextStyle(
                    color: _textMuted,
                    fontSize: 12,
                    fontStyle: origin == '—' ? FontStyle.italic : null,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Date: ${_formatRegisteredDateOnlyDisplay(_registeredDateTimeNullableFromTourist(t))}',
                  style: TextStyle(color: _textMuted, fontSize: 11),
                ),
                Text(
                  'Time: ${_formatRegisteredTimeOnlyDisplay(_registeredDateTimeNullableFromTourist(t))}',
                  style: TextStyle(color: _textMuted, fontSize: 11),
                ),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildTouristsTable(List<Map<String, dynamic>> tourists) {
    // Sort by visits descending (most visits first / by rank)
    int visitCount(Map<String, dynamic> t) {
      final v = t['totalVisits'] ?? t['visits'] ?? 0;
      if (v is int) return v;
      if (v is num) return v.toInt();
      return int.tryParse(v.toString()) ?? 0;
    }

    final sorted = List<Map<String, dynamic>>.from(tourists)
      ..sort((a, b) => visitCount(b).compareTo(visitCount(a)));

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
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
            headingTextStyle: TextStyle(
              color: _textDark,
              fontWeight: FontWeight.w700,
              fontSize: 13,
            ),
            dataTextStyle: TextStyle(color: _textDark, fontSize: 14),
            dividerThickness: 0,
            horizontalMargin: 20,
            columnSpacing: 28,
            columns: const [
              DataColumn(label: Text('Name')),
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
              final name = _getTouristDisplayName(t);
              final touristId =
                  TouristIdHelper.displayForTourist(t);
              final origin = _getTouristOrigin(t);
              final visits = t['totalVisits'] ?? t['visits'] ?? 0;
              final regDt = _registeredDateTimeNullableFromTourist(t);
              final isLocal =
                  t['isLocal'] == true || t['localOrForeign'] == 'Local';
              final status = t['status']?.toString() ?? 'Active';
              final avatar = _touristAvatarImage(t);
              final hasProfileImage = avatar != null;
              final email = t['email']?.toString() ?? '';

              return DataRow(
                cells: [
                  DataCell(
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        CircleAvatar(
                          radius: 18,
                          backgroundColor: _primaryOrange.withOpacity(0.15),
                          backgroundImage: avatar,
                          child: hasProfileImage
                              ? null
                              : Text(
                                  name.isNotEmpty
                                      ? name.substring(0, 1).toUpperCase()
                                      : '?',
                                  style: const TextStyle(
                                    color: _primaryOrange,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 14,
                                  ),
                                ),
                        ),
                        const SizedBox(width: 12),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisAlignment: MainAxisAlignment.center,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              name,
                              style: const TextStyle(
                                color: _textDark,
                                fontWeight: FontWeight.w600,
                                fontSize: 14,
                              ),
                            ),
                            if (email.isNotEmpty)
                              Text(
                                email,
                                style: TextStyle(
                                  color: _textMuted,
                                  fontSize: 12,
                                ),
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  DataCell(
                    Text(
                      touristId,
                      style: TextStyle(color: _textMuted, fontSize: 13),
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
                            ? Colors.green.withOpacity(0.12)
                            : Colors.purple.withOpacity(0.12),
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
                        color: origin == '—' ? _textMuted : _textDark,
                        fontSize: 13,
                        fontStyle: origin == '—' ? FontStyle.italic : null,
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
                        color: const Color(0xFF0EA5E9).withOpacity(0.12),
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
                            ? Colors.green.withOpacity(0.12)
                            : Colors.red.withOpacity(0.12),
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
                        ).withOpacity(0.1),
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
    return '—';
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
    final name = _getTouristDisplayName(tourist);
    final touristId = TouristIdHelper.displayForTourist(tourist);
    final email = tourist['email']?.toString() ?? 'N/A';
    final mobile = tourist['mobile']?.toString() ?? 'N/A';
    final nationality = tourist['nationality']?.toString() ?? 'N/A';
    final isLocal =
        tourist['isLocal'] == true || tourist['localOrForeign'] == 'Local';
    final visits = tourist['totalVisits'] ?? tourist['visits'] ?? 0;
    final status = tourist['status']?.toString() ?? 'Active';
    final avatar = _touristAvatarImage(tourist);
    final hasProfileImage = avatar != null;

    // Build origin string
    String origin = '';
    if (tourist['city'] != null) {
      origin = tourist['city'];
      if (tourist['province'] != null) origin += ', ${tourist['province']}';
      if (tourist['country'] != null) origin += ', ${tourist['country']}';
    } else {
      origin = tourist['origin']?.toString() ?? 'N/A';
    }

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: _cardBg,
        title: Row(
          children: [
            CircleAvatar(
              radius: 24,
              backgroundColor: _primaryOrange.withOpacity(0.2),
              backgroundImage: avatar,
              child: hasProfileImage
                  ? null
                  : Text(
                      name.substring(0, 1).toUpperCase(),
                      style: const TextStyle(
                        color: _primaryOrange,
                        fontWeight: FontWeight.bold,
                        fontSize: 20,
                      ),
                    ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    style: const TextStyle(color: _textDark, fontSize: 18),
                  ),
                  Text(
                    touristId,
                    style: TextStyle(color: _textMuted, fontSize: 12),
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
                              ? Colors.green.withOpacity(0.15)
                              : Colors.purple.withOpacity(0.15),
                          borderRadius: BorderRadius.circular(8),
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
                              ? Colors.green.withOpacity(0.15)
                              : Colors.red.withOpacity(0.15),
                          borderRadius: BorderRadius.circular(8),
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
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.grey.shade200,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: QrImageView(
                  data: touristId,
                  version: QrVersions.auto,
                  size: 150,
                  backgroundColor: Colors.white,
                ),
              ),
              const SizedBox(height: 20),
              _buildDetailRow('Email', email),
              _buildDetailRow('Mobile', mobile),
              _buildDetailRow('Nationality', nationality),
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
              if (tourist['travelHistory'] != null) ...[
                const Divider(color: Colors.white24, height: 24),
                const Text(
                  'Travel History',
                  style: TextStyle(
                    color: _primaryOrange,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 8),
                _buildDetailRow(
                  '1st Destination',
                  tourist['travelHistory']['firstDestination'] ?? 'N/A',
                ),
                _buildDetailRow(
                  '2nd Destination',
                  tourist['travelHistory']['secondDestination'] ?? 'N/A',
                ),
                _buildDetailRow(
                  '3rd Destination',
                  tourist['travelHistory']['thirdDestination'] ?? 'N/A',
                ),
                _buildDetailRow(
                  'How Heard About',
                  tourist['travelHistory']['howHeardAbout'] ?? 'N/A',
                ),
              ],
              if (tourist['transportation'] != null)
                _buildDetailRow('Transportation', tourist['transportation']),
            ],
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
      final email = t['email']?.toString() ?? '—';
      final mobile = t['mobile']?.toString() ?? '—';
      final nationality = t['nationality']?.toString() ?? '—';
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
                'Visitors export',
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
                '${_tourists.length} record${_tourists.length == 1 ? '' : 's'} · scroll horizontally for all columns',
                style: TextStyle(color: _textMuted, fontSize: 13),
              ),
              const SizedBox(height: 12),
              Expanded(
                child: _tourists.isEmpty
                    ? Center(
                        child: Text(
                          'No visitors to export.',
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
                        ? 'CSV copied to clipboard — paste into Excel or save as .csv'
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

  /// Renders generated report text as a printable “paper” document (not raw monospace).
  Widget _buildReportDocumentBody(String content) {
    final lines = content.split('\n');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: _parseReportLinesToDocumentWidgets(lines),
    );
  }

  List<Widget> _parseReportLinesToDocumentWidgets(List<String> lines) {
    final out = <Widget>[];
    for (final line in lines) {
      final t = line.trimRight();
      if (t.isEmpty) {
        out.add(const SizedBox(height: 8));
        continue;
      }
      if (t.startsWith('===') && t.endsWith('===')) {
        final inner = t.replaceAll('=', '').trim();
        out.add(
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Text(
              inner,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: _textDark,
                fontSize: 20,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.4,
              ),
            ),
          ),
        );
        out.add(Divider(color: Colors.grey.shade300, thickness: 1.2));
        out.add(const SizedBox(height: 12));
        continue;
      }
      if (t.startsWith('---') && t.endsWith('---')) {
        final inner = t.replaceAll('-', '').trim();
        out.add(const SizedBox(height: 8));
        out.add(_reportDocumentSectionHeader(inner));
        out.add(const SizedBox(height: 10));
        continue;
      }
      if (RegExp(r'^\s{2,}').hasMatch(line) && line.trim().isNotEmpty) {
        out.add(
          Padding(
            padding: const EdgeInsets.only(bottom: 6, left: 4),
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: const Color(0xFFF8FAFC),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 8,
                ),
                child: SelectableText(
                  line.trim(),
                  style: const TextStyle(
                    color: _textDark,
                    fontSize: 11.5,
                    height: 1.35,
                    fontFamily: 'monospace',
                  ),
                ),
              ),
            ),
          ),
        );
        continue;
      }
      final colonIdx = t.indexOf(':');
      if (colonIdx > 0) {
        final key = t.substring(0, colonIdx).trim();
        final val = t.substring(colonIdx + 1).trim();
        if (val.isEmpty) {
          out.add(
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Text(
                t,
                style: const TextStyle(
                  color: _textDark,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          );
        } else {
          out.add(_reportDocumentKeyValueRow(key, val));
        }
        continue;
      }
      out.add(
        Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: SelectableText(
            t,
            style: const TextStyle(
              color: _textDark,
              fontSize: 13,
              height: 1.45,
            ),
          ),
        ),
      );
    }
    return out;
  }

  Widget _reportDocumentSectionHeader(String title) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: _primaryOrange.withOpacity(0.12),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Text(
        title.toUpperCase(),
        style: const TextStyle(
          color: _textDark,
          fontSize: 12,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.9,
        ),
      ),
    );
  }

  Widget _reportDocumentKeyValueRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: LayoutBuilder(
        builder: (context, constraints) {
          if (constraints.maxWidth < 420) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    color: Colors.grey.shade700,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                SelectableText(
                  value,
                  style: const TextStyle(
                    color: _textDark,
                    fontSize: 13,
                    height: 1.4,
                  ),
                ),
              ],
            );
          }
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 168,
                child: Text(
                  label,
                  style: TextStyle(
                    color: Colors.grey.shade700,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              Expanded(
                child: SelectableText(
                  value,
                  style: const TextStyle(
                    color: _textDark,
                    fontSize: 13,
                    height: 1.4,
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  void _showExportPreview(
    String title,
    String content, {
    String? csvData,
    String? csvFilename,
  }) {
    showDialog<void>(
      context: context,
      builder: (dialogContext) {
        final mq = MediaQuery.of(context);
        final maxH = mq.size.height * 0.82;
        final dialogW = math.min(720.0, mq.size.width - 40);
        return Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: const EdgeInsets.symmetric(
            horizontal: 20,
            vertical: 24,
          ),
          child: SizedBox(
            width: dialogW,
            height: maxH,
            child: Material(
              color: Colors.white,
              elevation: 8,
              shadowColor: Colors.black26,
              borderRadius: BorderRadius.circular(26),
              clipBehavior: Clip.antiAlias,
              child: Column(
                children: [
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.fromLTRB(20, 18, 16, 18),
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        colors: [Color(0xFFEA580C), Color(0xFFF97316)],
                        begin: Alignment.centerLeft,
                        end: Alignment.centerRight,
                      ),
                    ),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.2),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: const Icon(
                            Icons.description_outlined,
                            color: Colors.white,
                            size: 26,
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                title,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 18,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: 0.2,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'ATMOS TRS · Tourism Office · Export preview',
                                style: TextStyle(
                                  color: Colors.white.withOpacity(0.92),
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
                  Expanded(
                    child: Container(
                      color: const Color(0xFFE8E8E8),
                      padding: const EdgeInsets.all(16),
                      child: Scrollbar(
                        thumbVisibility: true,
                        child: SingleChildScrollView(
                          child: Container(
                            width: double.infinity,
                            padding: const EdgeInsets.fromLTRB(28, 32, 28, 36),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(4),
                              boxShadow: const [
                                BoxShadow(
                                  color: Color(0x1A000000),
                                  blurRadius: 12,
                                  offset: Offset(0, 4),
                                ),
                              ],
                            ),
                            child: _buildReportDocumentBody(content),
                          ),
                        ),
                      ),
                    ),
                  ),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(color: const Color(0xFFFFFBF7)),
                    child: Wrap(
                      alignment: WrapAlignment.end,
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        if (csvData != null &&
                            csvData.isNotEmpty &&
                            csvFilename != null &&
                            csvFilename.isNotEmpty)
                          TextButton.icon(
                            onPressed: () async {
                              await downloadCsvFile(csvFilename, csvData);
                              if (!dialogContext.mounted) return;
                              Navigator.pop(dialogContext);
                              if (!mounted) return;
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(
                                    csvDownloadUsesClipboard
                                        ? 'Check-in CSV copied — paste into Excel'
                                        : 'Check-in CSV download started',
                                  ),
                                  backgroundColor: _primaryOrange,
                                  behavior: SnackBarBehavior.floating,
                                ),
                              );
                            },
                            icon: Icon(
                              Icons.download_rounded,
                              color: _primaryOrange,
                              size: 20,
                            ),
                            label: Text(
                              'Download check-ins CSV',
                              style: TextStyle(
                                color: _primaryOrange,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        TextButton(
                          onPressed: () => Navigator.pop(dialogContext),
                          child: const Text(
                            'Close',
                            style: TextStyle(
                              color: _primaryOrange,
                              fontWeight: FontWeight.w700,
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
      },
    );
  }

  // ==================== VR TOURS SECTION ====================
  Widget _buildVRToursContent() {
    final filteredTours = _vrTours.where((v) {
      final searchQuery = _vrToursSearchController.text.toLowerCase();
      return searchQuery.isEmpty ||
          (v['name']?.toString() ?? '').toLowerCase().contains(searchQuery) ||
          (v['spotName']?.toString() ?? '').toLowerCase().contains(searchQuery);
    }).toList();

    return RefreshIndicator(
      onRefresh: _loadData,
      color: _primaryOrange,
      child: _buildFramedContentShell(
        title: 'VR Tours',
        subtitle:
            'Spots with a VR link from Tourist Spots — add or change the link there',
        body: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: EdgeInsets.all(_isMobile ? 16 : 24),
          child: Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: _cardBg,
              borderRadius: BorderRadius.circular(28),
            ),
            child: Column(
              children: [
                _buildVRToursFilters(),
                const SizedBox(height: 20),
                if (filteredTours.isEmpty)
                  _buildEmptyState(
                    'No VR tours yet. Open Tourist Spots, edit a spot, and paste your Teleport360 VR URL.',
                    icon: Icons.vrpano_rounded,
                  )
                else if (_isMobile)
                  _buildVRToursListMobile(filteredTours)
                else
                  _buildVRToursTable(filteredTours),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildVRToursFilters() {
    return Wrap(
      spacing: 16,
      runSpacing: 16,
      children: [
        SizedBox(
          width: _isMobile ? double.infinity : 300,
          child: AppSearchBar(
            controller: _vrToursSearchController,
            hintText: 'Search VR tours...',
            onChanged: (value) => setState(() {}),
            horizontalPadding: 0,
          ),
        ),
        OutlinedButton.icon(
          onPressed: _goToTouristSpotsForVr,
          icon: const Icon(Icons.place_rounded, size: 18),
          label: const Text('Add VR on Tourist Spots'),
          style: OutlinedButton.styleFrom(
            foregroundColor: Colors.purple,
            side: const BorderSide(color: Colors.purple),
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildVRToursListMobile(List<Map<String, dynamic>> tours) {
    return Column(
      children: tours
          .map(
            (v) => Container(
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.03),
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
                          v['spotName'] ?? v['name'],
                          style: const TextStyle(
                            color: _textDark,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      _buildStatusBadge(v['status']),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    (v['vrUrl']?.toString() ?? '').length > 48
                        ? '${(v['vrUrl']?.toString() ?? '').substring(0, 48)}…'
                        : (v['vrUrl']?.toString() ?? ''),
                    style: TextStyle(color: _textMuted, fontSize: 12),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${v['views']} views',
                    style: TextStyle(color: _textMuted, fontSize: 12),
                  ),
                  const SizedBox(height: 12),
                  Align(
                    alignment: Alignment.centerRight,
                    child: _buildVrTourActions(v),
                  ),
                ],
              ),
            ),
          )
          .toList(),
    );
  }

  Widget _buildVrTourActions(Map<String, dynamic> tour) {
    void run(String action) {
      switch (action) {
        case 'play':
          _playVRTour(tour);
        case 'edit':
          _editVrTourSpot(tour);
        case 'delete':
          _showRemoveVrLinkDialog(tour);
      }
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          onPressed: () => run('play'),
          icon: const Icon(Icons.play_circle, color: Colors.purple, size: 22),
          tooltip: 'Play VR tour',
          visualDensity: VisualDensity.compact,
        ),
        IconButton(
          onPressed: () => run('edit'),
          icon: const Icon(Icons.edit_outlined, color: Colors.blue, size: 20),
          tooltip: 'Edit spot & VR URL',
          visualDensity: VisualDensity.compact,
        ),
        IconButton(
          onPressed: () => run('delete'),
          icon: const Icon(Icons.link_off, color: Colors.redAccent, size: 20),
          tooltip: 'Remove VR link',
          visualDensity: VisualDensity.compact,
        ),
        PopupMenuButton<String>(
          icon: const Icon(Icons.more_vert, color: _textMuted, size: 20),
          tooltip: 'More actions',
          onSelected: run,
          itemBuilder: (_) => const [
            PopupMenuItem(
              value: 'play',
              child: ListTile(
                leading: Icon(Icons.play_circle, color: Colors.purple),
                title: Text('Play'),
                contentPadding: EdgeInsets.zero,
                dense: true,
              ),
            ),
            PopupMenuItem(
              value: 'edit',
              child: ListTile(
                leading: Icon(Icons.edit, color: Colors.blue),
                title: Text('Edit tourist spot'),
                contentPadding: EdgeInsets.zero,
                dense: true,
              ),
            ),
            PopupMenuItem(
              value: 'delete',
              child: ListTile(
                leading: Icon(Icons.link_off, color: Colors.redAccent),
                title: Text('Remove VR link'),
                contentPadding: EdgeInsets.zero,
                dense: true,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildVRToursTable(List<Map<String, dynamic>> tours) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: DataTable(
        headingRowColor: WidgetStateProperty.all(Colors.grey.shade100),
        dataTextStyle: const TextStyle(color: _textDark, fontSize: 13),
        dividerThickness: 0,
        columns: const [
          DataColumn(
            label: Text(
              'Tourist Spot',
              style: TextStyle(
                color: _textDark,
                fontWeight: FontWeight.w700,
                fontSize: 13,
              ),
            ),
          ),
          DataColumn(
            label: Text(
              'Views',
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
        rows: tours
            .map(
              (v) => DataRow(
                cells: [
                  DataCell(
                    Text(
                      v['spotName'] ?? v['name'],
                      style: const TextStyle(
                        color: _textDark,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  DataCell(
                    Text(
                      '${v['views']}',
                      style: const TextStyle(
                        color: _textDark,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  DataCell(_buildStatusBadge(v['status'])),
                  DataCell(_buildVrTourActions(v)),
                ],
              ),
            )
            .toList(),
      ),
    );
  }

  void _goToTouristSpotsForVr() {
    setState(() => _selectedIndex = _touristSpotsNavIndex);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'Edit a tourist spot and paste your VR Tour URL (Teleport360 link).',
        ),
        backgroundColor: Color(0xFFF97316),
        duration: Duration(seconds: 4),
      ),
    );
  }

  void _editVrTourSpot(Map<String, dynamic> tour) {
    final spotId = tour['spotId']?.toString() ?? '';
    if (spotId.isEmpty) {
      _goToTouristSpotsForVr();
      return;
    }
    try {
      final spot = _touristSpots.firstWhere((s) => s.id == spotId);
      _showEditSpotDialog(spot);
    } catch (_) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Tourist spot not found. Refresh and try again.'),
          backgroundColor: Colors.redAccent,
        ),
      );
    }
  }

  void _showRemoveVrLinkDialog(Map<String, dynamic> tour) {
    final spotName =
        tour['spotName']?.toString() ?? tour['name']?.toString() ?? 'this spot';
    final spotId = tour['spotId']?.toString() ?? '';
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
          'Remove the VR tour URL from "$spotName"? The tourist spot stays; only the VR link is cleared.',
          style: const TextStyle(color: _textMuted),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel', style: TextStyle(color: _textMuted)),
          ),
          ElevatedButton(
            onPressed: () async {
              if (spotId.isEmpty) {
                Navigator.pop(context);
                return;
              }
              final ok = await VrTourFirestoreService.clearVrLinkForSpot(spotId);
              if (!context.mounted) return;
              Navigator.pop(context);
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


  void _playVRTour(Map<String, dynamic> tour) async {
    final tourId = tour['id']?.toString() ?? '';
    final spotId = tour['spotId']?.toString() ?? '';
    if (spotId.isNotEmpty) {
      await VrTourFirestoreService.incrementViewsForSpot(spotId);
    }
    final spotName =
        tour['spotName']?.toString() ?? tour['name']?.toString() ?? 'VR Tour';
    await openVrForTouristSpot(
      context,
      spotId: spotId,
      spotName: spotName,
      vrLink: tour['vrUrl']?.toString(),
      imageUrl: tour['thumbnail']?.toString(),
    );

    if (!mounted) return;
    setState(() {
      final index = _vrTours.indexWhere((v) => v['id'] == tourId);
      if (index != -1) {
        final views = _vrTours[index]['views'];
        final n = views is int
            ? views
            : (views is num ? views.toInt() : 0);
        _vrTours[index] = {..._vrTours[index], 'views': n + 1};
      }
    });
  }

  // ==================== ANALYTICS (LGU-scoped) ====================
  Widget _buildAnalyticsContent() {
    final subtitle = _municipalityName != null
        ? '$_municipalityName — insights from your check-ins and registered visitors'
        : 'Insights from loaded check-ins and visitors (sign in with a municipality account to scope data)';

    return RefreshIndicator(
      onRefresh: _loadData,
      color: _primaryOrange,
      child: _buildFramedContentShell(
        title: 'Analytics',
        subtitle: subtitle,
        body: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: EdgeInsets.all(_isMobile ? 16 : 24),
          child: Column(
            children: [
              _buildLguAnalyticsCards(),
              const SizedBox(height: 24),
              _buildLguVisitorTrendsChart(),
              const SizedBox(height: 24),
              _buildLguTopSpotsChart(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLguAnalyticsCards() {
    return GridView.count(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisCount: _isMobile ? 2 : 4,
      crossAxisSpacing: 16,
      mainAxisSpacing: 16,
      childAspectRatio: _isMobile ? 1.05 : 1.42,
      children: [
        _buildLguAnalyticsCard(
          'Daily Avg',
          '$_lguAnalyticsDailyAvg',
          Icons.calendar_today,
          Colors.blue,
        ),
        _buildLguAnalyticsCard(
          'Peak Hour',
          _lguAnalyticsPeakHour,
          Icons.access_time,
          _primaryOrange,
        ),
        _buildLguAnalyticsCard(
          'Top Origin',
          _lguAnalyticsTopOrigin,
          Icons.flight,
          Colors.green,
        ),
        _buildLguAnalyticsCard(
          'Active Spots',
          '${_touristSpots.where((s) => s.status == 'Active').length}',
          Icons.place_rounded,
          Colors.purple,
        ),
      ],
    );
  }

  Widget _buildLguAnalyticsCard(
    String label,
    String value,
    IconData icon,
    Color color,
  ) {
    final softTint = Color.lerp(Colors.white, color, 0.07) ?? Colors.white;
    final deepTint = Color.lerp(Colors.white, color, 0.13) ?? Colors.white;
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: Color.lerp(_kAnalyticsSurfaceBorder, color, 0.35)!,
        ),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Colors.white, softTint, deepTint],
          stops: const [0.0, 0.48, 1.0],
        ),
        boxShadow: [
          BoxShadow(
            color: color.withOpacity(0.28),
            blurRadius: 30,
            offset: const Offset(0, 12),
            spreadRadius: -8,
          ),
          BoxShadow(
            color: Colors.black.withOpacity(0.12),
            blurRadius: 22,
            offset: const Offset(0, 9),
          ),
          BoxShadow(
            color: Colors.white.withOpacity(0.74),
            blurRadius: 14,
            offset: const Offset(0, -2),
            spreadRadius: -8,
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            height: 3,
            margin: const EdgeInsets.only(bottom: 8),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(999),
              gradient: LinearGradient(
                colors: [
                  color.withOpacity(0.0),
                  color.withOpacity(0.58),
                  color.withOpacity(0.0),
                ],
              ),
            ),
          ),
          Center(
            child: Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: color.withOpacity(0.16),
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: color.withOpacity(0.24), width: 1),
              ),
              child: Icon(icon, color: color, size: 24),
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: Center(
              child: Text(
                value,
                style: TextStyle(
                  color: _textDark,
                  fontSize: value.contains('\n') || value.length > 18
                      ? 14
                      : (value.length > 12 ? 17 : 22),
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.3,
                  height: 1.2,
                ),
                textAlign: TextAlign.center,
                maxLines: 4,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
          Text(
            label.toUpperCase(),
            style: TextStyle(
              color: _textMuted,
              fontSize: 10,
              fontWeight: FontWeight.w700,
              height: 1.15,
              letterSpacing: 0.7,
            ),
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  Widget _buildLguVisitorTrendsChart() {
    final values = _lguAnalyticsTrendValues;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: _cardBg,
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: _kAnalyticsSurfaceBorder, width: 1),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.06),
            blurRadius: 14,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Visitor trends',
                      style: TextStyle(
                        color: _textDark,
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                        letterSpacing: -0.2,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Visits per day (last 14 days, local time)',
                      style: TextStyle(
                        color: const Color(0xFF374151),
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        height: 1.35,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: _primaryOrange.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: _primaryOrange.withOpacity(0.35),
                    width: 1,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.trending_up_rounded,
                      size: 16,
                      color: _primaryOrange,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      'Total ${values.fold<double>(0, (a, b) => a + b).toStringAsFixed(0)}',
                      style: const TextStyle(
                        color: _textDark,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          _AnalyticsTrendChart(values: values, color: _primaryOrange),
        ],
      ),
    );
  }

  Widget _buildLguTopSpotsChart() {
    final spots = _lguAnalyticsTopSpots.take(10).toList();
    final maxVisits = spots.isEmpty ? 1 : (spots.first['visits'] as int);

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: _cardBg,
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: _kAnalyticsSurfaceBorder, width: 1),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.06),
            blurRadius: 14,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Most visited spots',
            style: TextStyle(
              color: _textDark,
              fontSize: 17,
              fontWeight: FontWeight.w700,
              letterSpacing: -0.2,
            ),
          ),
          const SizedBox(height: 20),
          if (spots.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: Text(
                'No check-in data yet.',
                style: TextStyle(
                  color: Color(0xFF374151),
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
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
                        borderRadius: BorderRadius.circular(12),
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
                            borderRadius: BorderRadius.circular(8),
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
              content: Text('Reports view is not ready yet. Try again.'),
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
            text: 'ATMOS TRS — Reports',
            title: 'Reports screenshot',
          ),
        );
      } else {
        switch (defaultTargetPlatform) {
          case TargetPlatform.android:
          case TargetPlatform.iOS:
            final result = await ImageGallerySaverPlus.saveImage(
              png,
              quality: 100,
              name: baseName,
            );
            final ok =
                result is Map &&
                (result['isSuccess'] == true || result['success'] == true);
            if (!ok) throw Exception('gallery save failed');
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
                text: 'ATMOS TRS — Reports',
                title: 'Reports screenshot',
              ),
            );
        }
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            kIsWeb
                ? 'Screenshot ready — use your browser or share dialog to save.'
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

  Widget _buildReportsContent() {
    return RefreshIndicator(
      onRefresh: _loadData,
      color: _primaryOrange,
      child: _buildFramedContentShell(
        title: 'Reports',
        subtitle:
            'Check-in stats use your selected date range only (e.g. March 1–31). Use Custom for a full month.',
        actions: [
          Tooltip(
            message:
                'Save an image of this whole page (quick exports + custom report)',
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
              color: _textDark,
            ),
          ),
        ],
        body: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: EdgeInsets.all(_isMobile ? 16 : 24),
          child: RepaintBoundary(
            key: _reportsRepaintKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildQuickReports(),
                const SizedBox(height: 24),
                _buildCustomReportGenerator(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildQuickReports() {
    return _wrapTourismPanel(
      Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: _primaryOrange.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(
                  Icons.folder_open_rounded,
                  color: _primaryOrange,
                  size: 20,
                ),
              ),
              const SizedBox(width: 10),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Quick export documents',
                      style: TextStyle(
                        color: _textDark,
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    SizedBox(height: 4),
                    Text(
                      'Preset windows for fast exports. Tap a row to generate.',
                      style: TextStyle(
                        color: _textMuted,
                        fontSize: 12,
                        height: 1.35,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Column(
            children: [
              _buildQuickReportDocumentRow(
                title: 'Daily Report',
                subtitle:
                    "Today's activity snapshot (check-ins filtered to today)",
                icon: Icons.today_rounded,
                accent: Colors.blue,
                type: 'daily',
              ),
              const SizedBox(height: 10),
              _buildQuickReportDocumentRow(
                title: 'Weekly Report',
                subtitle: 'Last 7 days including today',
                icon: Icons.date_range_rounded,
                accent: Colors.orange,
                type: 'weekly',
              ),
              const SizedBox(height: 10),
              _buildQuickReportDocumentRow(
                title: 'Monthly Report',
                subtitle: 'From the 1st of this month through today',
                icon: Icons.calendar_month_rounded,
                accent: _primaryOrange,
                type: 'monthly',
              ),
              const SizedBox(height: 10),
              _buildQuickReportDocumentRow(
                title: 'Annual Report',
                subtitle: 'Year-to-date from January 1 through today',
                icon: Icons.calendar_today_rounded,
                accent: Colors.purple,
                type: 'annual',
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildQuickReportDocumentRow({
    required String title,
    required String subtitle,
    required IconData icon,
    required Color accent,
    required String type,
  }) {
    final rangeText = _quickReportRangeText(type);

    return InkWell(
      onTap: () => _generateQuickReport(type),
      borderRadius: BorderRadius.circular(10),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: _panelBorder),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: accent.withOpacity(0.16),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(icon, color: accent, size: 18),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                          color: _textDark,
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        subtitle,
                        style: const TextStyle(
                          color: _textMuted,
                          fontSize: 11,
                          height: 1.3,
                        ),
                      ),
                    ],
                  ),
                ),
                if (!_isMobile)
                  Text(
                    rangeText,
                    style: TextStyle(
                      color: accent.withOpacity(0.95),
                      fontSize: 10.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                if (_isMobile)
                  Expanded(
                    child: Text(
                      rangeText,
                      style: TextStyle(
                        color: accent.withOpacity(0.95),
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  )
                else
                  const Spacer(),
                const SizedBox(width: 8),
                FilledButton.icon(
                  onPressed: () => _generateQuickReport(type),
                  icon: const Icon(Icons.download_rounded, size: 14),
                  label: const Text('Export'),
                  style: FilledButton.styleFrom(
                    backgroundColor: accent,
                    foregroundColor: Colors.white,
                    elevation: 2,
                    shadowColor: accent.withOpacity(0.35),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 8,
                    ),
                    textStyle: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  String _quickReportRangeText(String type) {
    final now = DateTime.now();
    switch (type) {
      case 'daily':
        return '[${_formatDateDisplay(now)}]';
      case 'weekly':
        final start = now.subtract(const Duration(days: 6));
        return '[${_formatDateDisplay(start)} – ${_formatDateDisplay(now)}]';
      case 'monthly':
        final start = DateTime(now.year, now.month, 1);
        return '[${_formatDateDisplay(start)} – ${_formatDateDisplay(now)}]';
      case 'annual':
        final start = DateTime(now.year, 1, 1);
        return '[${_formatDateDisplay(start)} – ${_formatDateDisplay(now)}]';
      default:
        return '[${_formatDateDisplay(now)}]';
    }
  }

  Widget _buildCustomReportGenerator() {
    return _wrapTourismPanel(
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: _primaryOrange.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  Icons.tune_rounded,
                  color: _primaryOrange,
                  size: 16,
                ),
              ),
              const SizedBox(width: 8),
              const Text(
                'Generate Custom Report',
                style: TextStyle(
                  color: _textDark,
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'Choose date range and report type, then export your file.',
            style: TextStyle(color: _textMuted, fontSize: 11.5, height: 1.3),
          ),
          const SizedBox(height: 12),
          _isMobile ? _buildCustomReportMobile() : _buildCustomReportDesktop(),
        ],
      ),
    );
  }

  Widget _buildCustomReportMobile() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildDatePicker(
          'Start Date',
          _reportStartDate,
          (date) => setState(() => _reportStartDate = date),
        ),
        const SizedBox(height: 12),
        _buildDatePicker(
          'End Date',
          _reportEndDate,
          (date) => setState(() => _reportEndDate = date),
        ),
        const SizedBox(height: 12),
        _buildReportTypeDropdown(),
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: _generateCustomReport,
            icon: _isExporting
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Icon(Icons.download, size: 17),
            label: Text(_isExporting ? 'Generating...' : 'Generate'),
            style: ElevatedButton.styleFrom(
              backgroundColor: _primaryOrange,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildCustomReportDesktop() {
    const fieldWidth = 200.0;
    const typeWidth = 168.0;

    return Align(
      alignment: Alignment.centerLeft,
      child: Wrap(
        spacing: 12,
        runSpacing: 12,
        crossAxisAlignment: WrapCrossAlignment.end,
        children: [
          SizedBox(
            width: fieldWidth,
            child: _buildDatePicker(
              'Start Date',
              _reportStartDate,
              (date) => setState(() => _reportStartDate = date),
            ),
          ),
          SizedBox(
            width: fieldWidth,
            child: _buildDatePicker(
              'End Date',
              _reportEndDate,
              (date) => setState(() => _reportEndDate = date),
            ),
          ),
          SizedBox(width: typeWidth, child: _buildReportTypeDropdown()),
          Padding(
            padding: const EdgeInsets.only(bottom: 1),
            child: ElevatedButton.icon(
              onPressed: _generateCustomReport,
              icon: _isExporting
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.download_rounded, size: 17),
              label: Text(_isExporting ? 'Generating...' : 'Generate'),
              style: ElevatedButton.styleFrom(
                backgroundColor: _primaryOrange,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(
                  horizontal: 18,
                  vertical: 11,
                ),
                minimumSize: const Size(0, 40),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDatePicker(
    String label,
    DateTime? selectedDate,
    ValueChanged<DateTime> onSelect,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label, style: TextStyle(color: _textMuted, fontSize: 11)),
        const SizedBox(height: 4),
        InkWell(
          onTap: () async {
            final date = await showDatePicker(
              context: context,
              initialDate: selectedDate ?? DateTime.now(),
              firstDate: DateTime(2020),
              lastDate: DateTime.now(),
              builder: (context, child) {
                return Theme(
                  data: Theme.of(context).copyWith(
                    colorScheme: ColorScheme.light(
                      primary: _primaryOrange,
                      onPrimary: Colors.white,
                      surface: const Color(0xFFFFFBF5),
                      onSurface: _textDark,
                      surfaceContainerHighest: const Color(0xFFF7F0E8),
                    ),
                    dialogBackgroundColor: const Color(0xFFFFFBF5),
                    datePickerTheme: DatePickerThemeData(
                      backgroundColor: const Color(0xFFFFFBF5),
                      surfaceTintColor: Colors.transparent,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(32),
                      ),
                      headerBackgroundColor: Colors.transparent,
                      headerForegroundColor: _textDark,
                      headerHeadlineStyle: const TextStyle(
                        color: _textDark,
                        fontSize: 24,
                        fontWeight: FontWeight.w600,
                      ),
                      headerHelpStyle: TextStyle(
                        color: _textMuted,
                        fontSize: 13,
                      ),
                      weekdayStyle: TextStyle(
                        color: _textMuted,
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                      dayStyle: const TextStyle(color: _textDark, fontSize: 14),
                      dayForegroundColor: WidgetStateProperty.resolveWith((
                        Set<WidgetState> states,
                      ) {
                        if (states.contains(WidgetState.selected))
                          return Colors.white;
                        return null;
                      }),
                      dayBackgroundColor: WidgetStateProperty.resolveWith((
                        Set<WidgetState> states,
                      ) {
                        if (states.contains(WidgetState.selected))
                          return _primaryOrange;
                        return null;
                      }),
                      todayForegroundColor: WidgetStateProperty.resolveWith((
                        Set<WidgetState> states,
                      ) {
                        return _primaryOrange;
                      }),
                      todayBackgroundColor: WidgetStateProperty.resolveWith((
                        Set<WidgetState> states,
                      ) {
                        return null;
                      }),
                      todayBorder: const BorderSide(
                        color: _primaryOrange,
                        width: 2,
                      ),
                      dividerColor: Colors.grey.shade300,
                      cancelButtonStyle: TextButton.styleFrom(
                        foregroundColor: _primaryOrange,
                        textStyle: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      confirmButtonStyle: TextButton.styleFrom(
                        foregroundColor: _primaryOrange,
                        textStyle: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                    ),
                  ),
                  child: child!,
                );
              },
            );
            if (date != null) onSelect(date);
          },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: _kAnalyticsSurfaceBorder),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.04),
                  blurRadius: 6,
                  offset: const Offset(0, 1),
                ),
              ],
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(
                    selectedDate != null
                        ? _formatDateDisplay(selectedDate)
                        : 'Select date',
                    style: TextStyle(
                      color: selectedDate != null ? _textDark : _textMuted,
                      fontSize: 13,
                      fontWeight: selectedDate != null
                          ? FontWeight.w600
                          : FontWeight.normal,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Icon(
                  Icons.calendar_today_rounded,
                  color: _primaryOrange,
                  size: 18,
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildReportTypeDropdown() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('Report Type', style: TextStyle(color: _textMuted, fontSize: 11)),
        const SizedBox(height: 4),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(
            color: Colors.grey.shade200,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.grey.shade300),
          ),
          child: DropdownButton<String>(
            value: _reportType,
            isExpanded: true,
            isDense: true,
            dropdownColor: Colors.white,
            underline: const SizedBox(),
            style: const TextStyle(color: _textDark, fontSize: 13),
            icon: Icon(Icons.keyboard_arrow_down, color: _textMuted, size: 20),
            items: _reportTypes
                .map(
                  (t) => DropdownMenuItem(
                    value: t,
                    child: Text(
                      t,
                      style: const TextStyle(color: _textDark, fontSize: 13),
                    ),
                  ),
                )
                .toList(),
            onChanged: (value) => setState(() => _reportType = value!),
          ),
        ),
      ],
    );
  }

  Future<void> _generateQuickReport(String type) async {
    final now = DateTime.now();
    late DateTime startDate;
    late DateTime endDate;

    switch (type) {
      case 'daily':
        startDate = DateTime(now.year, now.month, now.day);
        endDate = DateTime(now.year, now.month, now.day, 23, 59, 59, 999);
        break;
      case 'weekly':
        final todayStart = DateTime(now.year, now.month, now.day);
        startDate = todayStart.subtract(const Duration(days: 6));
        endDate = DateTime(now.year, now.month, now.day, 23, 59, 59, 999);
        break;
      case 'monthly':
        // This calendar month only (e.g. all of March when in March).
        startDate = DateTime(now.year, now.month, 1);
        endDate = DateTime(now.year, now.month, now.day, 23, 59, 59, 999);
        break;
      case 'annual':
        startDate = DateTime(now.year, 1, 1);
        endDate = DateTime(now.year, now.month, now.day, 23, 59, 59, 999);
        break;
      default:
        startDate = DateTime(now.year, now.month, now.day);
        endDate = DateTime(now.year, now.month, now.day, 23, 59, 59, 999);
    }

    await _generateReport(startDate, endDate, 'All Data', type);
  }

  Future<void> _generateCustomReport() async {
    if (_reportStartDate == null || _reportEndDate == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please select both start and end dates'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    final start = DateTime(
      _reportStartDate!.year,
      _reportStartDate!.month,
      _reportStartDate!.day,
    );
    final end = DateTime(
      _reportEndDate!.year,
      _reportEndDate!.month,
      _reportEndDate!.day,
      23,
      59,
      59,
      999,
    );
    if (end.isBefore(start)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('End date must be on or after start date'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    await _generateReport(start, end, _reportType, 'custom');
  }

  Future<void> _generateReport(
    DateTime startDate,
    DateTime endDate,
    String type,
    String period,
  ) async {
    setState(() {
      _isExporting = true;
      _exportProgress = 0.0;
    });

    for (int i = 1; i <= 10; i++) {
      await Future.delayed(const Duration(milliseconds: 100));
      setState(() => _exportProgress = i / 10);
    }

    final filteredCheckIns = _checkInsInDateRange(startDate, endDate);

    String report = '=== ATMOS TRS REPORT ===\n';
    report += 'Generated: ${DateTime.now()}\n';
    report +=
        'Period (check-ins filtered): ${_formatDate(startDate)} to ${_formatDate(endDate)}\n';
    report += 'Report type: $type\n';
    report +=
        'Note: Check-in counts and lists below include ONLY records in this date range.\n\n';

    String? checkInsCsv;
    if (type == 'All Data' || type == 'Visits only') {
      report += '--- CHECK-INS (within period) ---\n';
      report += 'Count in period: ${filteredCheckIns.length}\n';
      final verified = filteredCheckIns
          .where((c) => c['status'] == 'Verified')
          .length;
      final pending = filteredCheckIns
          .where((c) => c['status'] == 'Pending')
          .length;
      report += 'Verified (with status field): $verified\n';
      report += 'Pending (with status field): $pending\n\n';

      if (filteredCheckIns.isEmpty) {
        report += 'No check-ins in this period.\n\n';
      } else {
        report += 'Detail (sorted newest first):\n';
        final sorted = List<Map<String, dynamic>>.from(filteredCheckIns);
        sorted.sort((a, b) {
          final ta = _parseCheckInTimestamp(a);
          final tb = _parseCheckInTimestamp(b);
          if (ta == null && tb == null) return 0;
          if (ta == null) return 1;
          if (tb == null) return -1;
          return tb.compareTo(ta);
        });
        for (final c in sorted) {
          final t = _parseCheckInTimestamp(c);
          final when = t != null ? t.toIso8601String() : '—';
          final spotId =
              c['spotId']?.toString() ?? c['spot_id']?.toString() ?? '—';
          final spotName = c['spot_name']?.toString() ?? '';
          final uid =
              c['userId']?.toString() ?? c['tourist_id']?.toString() ?? '—';
          final spotLabel = spotName.isNotEmpty ? spotName : spotId;
          report += '  $when | $spotLabel | user=$uid\n';
        }
        report += '\n';
      }
      checkInsCsv = _buildCheckInsCsv(filteredCheckIns);
    }

    if (type == 'All Data' || type == 'Tourists Only') {
      report +=
          '--- TOURISTS (LGU: visitors linked to your check-ins only; full app registry is Governor admin) ---\n';
      report += 'Count in this scope: ${_tourists.length}\n';
      var visitSum = 0;
      for (final t in _tourists) {
        final v = t['visits'] ?? t['totalVisits'];
        if (v is int) {
          visitSum += v;
        } else if (v is num) {
          visitSum += v.toInt();
        }
      }
      report += 'Total Visits (profile field): $visitSum\n\n';
    }

    if (type == 'All Data' || type == 'Tourist Spots Only') {
      report += '--- TOURIST SPOTS (current list; not filtered by date) ---\n';
      report += 'Total Spots: ${_touristSpots.length}\n';
      report += 'Active: $_activeSpots\n';
      report += 'Inactive: ${_touristSpots.length - _activeSpots}\n\n';

      report += 'By Category:\n';
      for (var cat in _categories.where((c) => c != 'All')) {
        final count = _touristSpots.where((s) => s.category == cat).length;
        report += '  $cat: $count\n';
      }
    }

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('report_${period}_$type', report);

    setState(() => _isExporting = false);

    if (!mounted) return;
    final csvName =
        'checkins_${_formatDate(startDate)}_to_${_formatDate(endDate)}.csv';
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          '${period.capitalize()} report generated (${filteredCheckIns.length} check-ins in period)',
        ),
        backgroundColor: _primaryOrange,
        action: SnackBarAction(
          label: 'Preview',
          textColor: Colors.white,
          onPressed: () => _showExportPreview(
            '$period Report',
            report,
            csvData: checkInsCsv,
            csvFilename: csvName,
          ),
        ),
      ),
    );
  }

  // ==================== DIALOGS ====================
  void _showNotificationsDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: _cardBg,
        title: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text('Notifications', style: TextStyle(color: Colors.white)),
            TextButton(
              onPressed: () {
                setState(() => _notifications.clear());
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
          child: _notifications.isEmpty
              ? const Center(
                  child: Text(
                    'No notifications',
                    style: TextStyle(color: _textMuted),
                  ),
                )
              : Column(
                  mainAxisSize: MainAxisSize.min,
                  children: _notifications
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
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close', style: TextStyle(color: _primaryOrange)),
          ),
        ],
      ),
    );
  }

  // --- Profile (header + sidebar; same pattern as governor dashboard) ---
  Widget _buildSidebarAvatar({required double size}) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(shape: BoxShape.circle),
      child: ClipOval(
        child: _profilePhotoBytes != null
            ? Image.memory(_profilePhotoBytes!, fit: BoxFit.cover)
            : Container(
                color: const Color(0xFFFFF7ED),
                child: Center(
                  child: Text(
                    _profileName.isNotEmpty
                        ? _profileName[0].toUpperCase()
                        : 'T',
                    style: TextStyle(
                      color: _primaryOrange,
                      fontSize: size * 0.45,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
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
                    : 'Export tourists and check-ins data',
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

  void _showTourismChangePasswordDialog() {
    final currentPasswordController = TextEditingController();
    final newPasswordController = TextEditingController();
    final confirmPasswordController = TextEditingController();
    bool isLoading = false;
    String? errorMessage;
    bool obscureCurrent = true;
    bool obscureNew = true;
    bool obscureConfirm = true;

    showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
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

          return AlertDialog(
            backgroundColor: _cardBg,
            title: const Text(
              'Change Password',
              style: TextStyle(color: _textDark, fontWeight: FontWeight.w600),
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
                        borderRadius: BorderRadius.circular(14),
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
                      fillColor: Colors.white,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: BorderSide(color: Colors.grey.shade300),
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
                    style: const TextStyle(color: _textDark),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: newPasswordController,
                    obscureText: obscureNew,
                    decoration: InputDecoration(
                      hintText: 'New Password',
                      hintStyle: TextStyle(color: _textMuted),
                      filled: true,
                      fillColor: Colors.white,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: BorderSide(color: Colors.grey.shade300),
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
                    style: const TextStyle(color: _textDark),
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
                      fillColor: Colors.white,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: BorderSide(color: Colors.grey.shade300),
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
                    style: const TextStyle(color: _textDark),
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
                                'New password does not meet requirements';
                            isLoading = false;
                          });
                          return;
                        }

                        if (newPasswordController.text !=
                            confirmPasswordController.text) {
                          setDialogState(() {
                            errorMessage = 'Passwords do not match';
                            isLoading = false;
                          });
                          return;
                        }

                        await Future.delayed(const Duration(seconds: 1));

                        final prefs = await SharedPreferences.getInstance();
                        await prefs.setString(
                          'tourism_password',
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
              'Visitors data (CSV)',
              Icons.people_alt_rounded,
              () {
                Navigator.pop(context);
                _exportTouristsData();
              },
            ),
            const SizedBox(height: 12),
            _buildTourismExportOption(
              'Check-ins (use Reports tab for full export)',
              Icons.qr_code_scanner_rounded,
              () {
                Navigator.pop(context);
                setState(() => _selectedIndex = _reportsIndex);
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
        content: Text('Backup completed (demo)'),
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
          'ATMOS TRS — Tourism Office dashboard.\n\n'
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
          'Use Settings → Change Password to update your login password (demo/local storage).',
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
                                        '${_dayLabel(_hoverIndex!)} · ${widget.values[_hoverIndex!].toStringAsFixed(0)} check-ins',
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
            'Date (oldest → today)',
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
  _StatCard({
    required this.title,
    required this.value,
    this.subtitle,
    required this.icon,
    required this.color,
  });
}

/// White sparkline on flat KPI cards.
class _TourismMiniSparklinePainter extends CustomPainter {
  _TourismMiniSparklinePainter({required this.values});

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
  bool shouldRepaint(covariant _TourismMiniSparklinePainter oldDelegate) =>
      oldDelegate.values != values;
}

extension StringExtension on String {
  String capitalize() {
    return '${this[0].toUpperCase()}${substring(1)}';
  }
}

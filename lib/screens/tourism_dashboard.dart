import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'dart:async';
import 'dart:typed_data';
import 'package:atmos_trs_system/config/session_storage.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'dart:convert';
import 'dart:math' as math;
import 'package:atmos_trs_system/widgets/app_search_bar.dart';
import 'package:atmos_trs_system/data/misamis_occidental_municipalities.dart';
import 'package:atmos_trs_system/utils/spot_qr_helper.dart';
import 'package:atmos_trs_system/utils/logo_utils.dart';
import 'package:atmos_trs_system/utils/municipality_helper.dart';
import 'package:atmos_trs_system/models/tourist_spot.dart';
import 'package:atmos_trs_system/services/tourist_spots_firestore_service.dart';
import 'package:atmos_trs_system/services/spot_qr_poster_pdf.dart';
import 'package:atmos_trs_system/utils/csv_file_download.dart';
import 'package:atmos_trs_system/utils/qr_png_bytes.dart';
import 'package:atmos_trs_system/utils/lgu_qr_export.dart';
import 'package:atmos_trs_system/utils/spot_qr_export.dart';
import 'package:atmos_trs_system/widgets/app_logout_button.dart';
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
  static const Color _sidebarHover = Color(
    0xFFC2410C,
  ); // darker orange for hover
  static const Color _textDark = Color(0xFF1A1A1A);
  static const Color _textMuted = Color(0xFF6B7280);
  static const Color _cardBorder = Color(0xFFFFEDD5); // soft orange border

  /// Large rounded UI (dashboard reference): main panel + sidebar curve.
  static const double _tdHeroRadius = 42;
  static const double _tdSidebarOuterRadius = 32;

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
  List<Map<String, dynamic>> _vrTours = [];
  List<Map<String, dynamic>> _recentActivity = [];
  List<Map<String, dynamic>> _notifications = [];

  /// For real-time check-in notifications: newest check-in doc id we've seen.
  String? _lastSeenCheckInId;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _qrCheckInsSubscription;
  StreamSubscription<List<TouristSpot>>? _touristSpotsSubscription;
  String? _storedMunicipalityId;
  List<TouristSpot> _allTouristSpots = [];

  // Search controllers
  final _checkInsSearchController = TextEditingController();
  final _spotsSearchController = TextEditingController();
  final _touristsSearchController = TextEditingController();
  final _vrToursSearchController = TextEditingController();
  final _globalSearchController = TextEditingController();

  // Filter states
  String _checkInStatusFilter = 'All';
  String _spotCategoryFilter = 'All';
  String _reportType = 'All Data';
  DateTime? _reportStartDate;
  DateTime? _reportEndDate;

  // Export states
  bool _isExporting = false;
  double _exportProgress = 0.0;

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
    _NavItem(icon: Icons.qr_code_scanner_rounded, label: 'Check-ins'),
    _NavItem(icon: Icons.place_rounded, label: 'Tourist Spots'),
    _NavItem(icon: Icons.qr_code_2_rounded, label: 'Spot QR Codes'),
    _NavItem(icon: Icons.people_alt_rounded, label: 'Tourists'),
    _NavItem(icon: Icons.vrpano_rounded, label: 'VR Tours'),
    _NavItem(icon: Icons.analytics_rounded, label: 'Analytics'),
    _NavItem(icon: Icons.assessment_rounded, label: 'Reports'),
    _NavItem(icon: Icons.settings_rounded, label: 'Settings'),
  ];

  static const int _mainNavCount = 7; // Dashboard through Analytics
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
    'Check-ins Only',
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

  Future<void> _loadTourismSettings() async {
    final prefs = await SharedPreferences.getInstance();
    final email = await SessionStorage.getStoredEmail();
    if (!mounted) return;
    setState(() {
      _emailNotifications = prefs.getBool('tourism_email_notifications') ?? true;
      _pushNotifications = prefs.getBool('tourism_push_notifications') ?? true;
      _weeklyReports = prefs.getBool('tourism_weekly_reports') ?? false;
      _lastBackupDate = prefs.getString('tourism_last_backup_date');
      final savedName = prefs.getString('tourism_profile_name');
      if (savedName != null && savedName.isNotEmpty) {
        _profileName = savedName;
      } else {
        _profileName = _municipalityName != null && _municipalityName!.isNotEmpty
            ? _municipalityName!
            : 'Tourism Office';
      }
      _profileEmail = prefs.getString('tourism_profile_email') ??
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
    _touristSpotsSubscription = TouristSpotsFirestoreService.streamTouristSpots().listen((list) {
      if (!mounted) return;
      final filtered = _filterSpotsByMunicipality(list, _storedMunicipalityId);
      setState(() {
        _allTouristSpots = list;
        _touristSpots = filtered;
        _activeSpots = _touristSpots.where((s) => s.status == 'Active').length;
        if (_activeSpots == 0 && _touristSpots.isNotEmpty) {
          _activeSpots = _touristSpots.length;
        }
      });
    }, onError: (Object e) {
      debugPrint('tourist_spots stream error: $e');
    });
  }

  List<TouristSpot> _filterSpotsByMunicipality(List<TouristSpot> spots, String? municipalityId) {
    if (municipalityId == null || municipalityId.isEmpty) return spots;
    final queryIds = municipalityIdsForQuery(municipalityId);
    String? municipalityNameForFilter;
    for (final m in getMisamisOccidentalMunicipalities()) {
      if (m.id == municipalityId) {
        municipalityNameForFilter = m.name;
        break;
      }
    }
    final idsForFilter = queryIds.isNotEmpty ? queryIds : [normalizeMunicipalityId(municipalityId)];
    return spots.where((s) {
      final mid = normalizeMunicipalityId(s.municipalityId.isNotEmpty ? s.municipalityId : null);
      final mName = s.municipality.toLowerCase();
      if (mid.isNotEmpty && idsForFilter.contains(mid)) return true;
      if (municipalityNameForFilter != null &&
          mName.contains(municipalityNameForFilter.toLowerCase())) return true;
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
    _globalSearchController.dispose();
    super.dispose();
  }

  bool get _isMobile => MediaQuery.of(context).size.width < 768;
  bool get _isTablet =>
      MediaQuery.of(context).size.width >= 768 &&
      MediaQuery.of(context).size.width < 1024;

  // When true, show banner that we're showing all data (no municipality filter)
  bool _showAllDataBanner = false;
  String? _municipalityName; // Display name for current filter (e.g. "Oroquieta City")

  Future<void> _loadData() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      if (Firebase.apps.isEmpty) {
        _useMockData();
        return;
      }

      final firestore = FirebaseFirestore.instance;
      final municipalityId = await SessionStorage.getStoredMunicipalityId();
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
      _touristSpots = _filterSpotsByMunicipality(_allTouristSpots, _storedMunicipalityId);
      _activeSpots = _touristSpots.where((s) => s.status == 'Active').length;
      if (_activeSpots == 0 && _touristSpots.isNotEmpty) {
        _activeSpots = _touristSpots.length;
      }

      if (municipalityId != null) {
        // Per-municipality: use qr_checkins and filter tourists by this municipality.
        // Tourist spots are loaded via stream in _subscribeToTouristSpots() and filtered there.
        final queryIds = municipalityIdsForQuery(municipalityId);
        if (queryIds.isNotEmpty) {
          final Query<Map<String, dynamic>> checkInsQuery = queryIds.length == 1
              ? firestore
                  .collection('qr_checkins')
                  .where('municipalityId', isEqualTo: queryIds.first)
              : firestore
                  .collection('qr_checkins')
                  .where('municipalityId', whereIn: queryIds);
          final checkInsSnapshot = await checkInsQuery.get();
          _checkIns = checkInsSnapshot.docs
              .map((doc) => _normalizeCheckInForUi({'id': doc.id, ...doc.data()}))
              .toList();
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
          _lastSeenCheckInId = _checkIns.isNotEmpty ? (_checkIns.first['id'] as String?) : null;
          _subscribeToCheckIns(queryIds);
        }

        final userIds = _checkIns
            .map((c) => c['userId']?.toString())
            .whereType<String>()
            .toSet()
            .toList();
        final touristsSnapshot = await firestore.collection('tourists').get();
        final allTourists = touristsSnapshot.docs
            .map((doc) => {'id': doc.id, ...doc.data()})
            .toList();
        if (userIds.isEmpty) {
          _tourists = [];
        } else {
          _tourists = allTourists.where((t) {
            final uid = t['firebaseUid']?.toString() ?? t['id']?.toString();
            return uid != null && userIds.contains(uid);
          }).toList();
          _tourists = _mergeTouristVisitsFromCheckIns(_tourists);
        }

        final vrToursSnapshot = await firestore.collection('vr_tours').get();
        _vrTours = vrToursSnapshot.docs
            .map((doc) => {'id': doc.id, ...doc.data()})
            .toList();
      } else {
        // No municipality filter: load from check_ins (legacy) and all spots/tourists
        _qrCheckInsSubscription?.cancel();
        _qrCheckInsSubscription = null;
        _lastSeenCheckInId = null;
        final checkInsSnapshot = await firestore
            .collection('check_ins')
            .orderBy('timestamp', descending: true)
            .limit(100)
            .get();
        _checkIns = checkInsSnapshot.docs
            .map((doc) => _normalizeCheckInForUi({'id': doc.id, ...doc.data()}))
            .toList();

        // Tourist spots are loaded via stream in _subscribeToTouristSpots()

        // Full `tourists` registration directory is Governor (admin) only — not exposed on LGU.
        _tourists = [];

        final vrToursSnapshot = await firestore.collection('vr_tours').get();
        _vrTours = vrToursSnapshot.docs
            .map((doc) => {'id': doc.id, ...doc.data()})
            .toList();
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

      // Generate recent activity (qr_checkins has userId, spotId, municipalityId; check_ins has touristName, location)
      _recentActivity = _checkIns.take(5).map((c) {
        final spotId = c['spotId']?.toString() ?? '';
        final location = spotId.isNotEmpty ? spotId.replaceAll('_', ' ') : (c['location'] ?? 'Unknown');
        return <String, dynamic>{
          'icon': Icons.qr_code_scanner_rounded,
          'color': _primaryOrange,
          'title': c['touristName'] ?? c['userId']?.toString() ?? 'Tourist',
          'description': 'Checked in at $location',
          'time': _formatTime(c['timestamp']),
        };
      }).toList();

      _notifications = [
        {
          'title': 'New Check-in',
          'message': '${_todayCheckIns} tourists checked in today',
          'time': 'Just now',
        },
        {
          'title': 'System Update',
          'message': 'Dashboard data refreshed',
          'time': '5 min ago',
        },
      ];

      setState(() => _isLoading = false);
      await _loadTourismSettings();
    } catch (e) {
      _useMockData();
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
        .listen((QuerySnapshot<Map<String, dynamic>> snapshot) {
      if (!mounted) return;
      final docs = snapshot.docs;
      final checkIns = docs
          .map((d) => _normalizeCheckInForUi({'id': d.id, ...d.data()}))
          .toList();
      final previousFirstId = _lastSeenCheckInId;
      _lastSeenCheckInId = docs.isEmpty ? null : docs.first.id;
      _checkIns = checkIns;
      _tourists = _mergeTouristVisitsFromCheckIns(_tourists);
      _todayCheckIns = _checkIns.where((c) {
        final timestamp = c['timestamp'];
        if (timestamp is Timestamp) {
          final date = timestamp.toDate();
          return date.day == now.day && date.month == now.month && date.year == now.year;
        }
        return false;
      }).length;
      _recentActivity = _checkIns.take(5).map((c) {
        final spotId = c['spotId']?.toString() ?? '';
        final location = spotId.isNotEmpty ? spotId.replaceAll('_', ' ') : (c['location'] ?? 'Unknown');
        return <String, dynamic>{
          'icon': Icons.qr_code_scanner_rounded,
          'color': _primaryOrange,
          'title': c['touristName'] ?? c['userId']?.toString() ?? 'Tourist',
          'description': 'Checked in at $location',
          'time': _formatTime(c['timestamp']),
        };
      }).toList();
      if (previousFirstId != null && docs.isNotEmpty && docs.first.id != previousFirstId) {
        int newCount = 0;
        for (var d in docs) {
          if (d.id == previousFirstId) break;
          newCount++;
          final spotId = d.data()['spotId']?.toString() ?? 'spot';
          final spotLabel = spotId.replaceAll('_', ' ');
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
    }, onError: (Object e) {
      debugPrint('qr_checkins stream error: $e');
    });
  }

  void _useMockData() {
    final now = DateTime.now();
    final names = [
      'Juan Dela Cruz',
      'Maria Santos',
      'Pedro Garcia',
      'Ana Reyes',
      'Jose Rizal',
    ];
    final touristIds = ['ABC123', 'DEF456', 'GHI789', 'JKL012', 'MNO345'];
    final locations = [
      'Azure Coast',
      'Baliangao Beach',
      'Oroquieta City Capitol',
      'Crystal Cove',
      'Sapang Dalaga Falls',
    ];

    _checkIns = List.generate(20, (i) {
      return <String, dynamic>{
        'id': 'CHK-${1000 + i}',
        'touristName': names[i % 5],
        'touristId': 'ATMOS-${touristIds[i % 5]}',
        'location': locations[i % 5],
        'timestamp': now.subtract(Duration(hours: i * 2)),
        'status': i % 4 == 0 ? 'Pending' : 'Verified',
      };
    });

    _allTouristSpots = [];
    _touristSpots = [];

    final touristNames = [
      'Juan Dela Cruz',
      'Maria Santos',
      'Pedro Garcia',
      'Ana Reyes',
      'Jose Rizal',
      'Elena Cruz',
      'Carlos Tan',
      'Rosa Lim',
    ];
    final prefixes = ['ABC', 'DEF', 'GHI', 'JKL', 'MNO'];
    final origins = ['Manila', 'Cebu', 'Davao', 'Cagayan de Oro', 'Iloilo'];

    _tourists = List.generate(15, (i) {
      return <String, dynamic>{
        'id': 'ATMOS-${prefixes[i % 5]}${100 + i}',
        'name': touristNames[i % 8],
        'email': 'tourist${i + 1}@email.com',
        'origin': origins[i % 5],
        'visits': (i + 1) * 2,
        'registeredDate': now.subtract(Duration(days: i * 10)),
      };
    });

    _vrTours = [
      {
        'id': 'VR-001',
        'name': 'Azure Coast VR Experience',
        'spotId': 'SPOT-001',
        'spotName': 'Azure Coast',
        'vrUrl': 'https://example.com/vr/azure',
        'thumbnail': '',
        'views': 1234,
        'status': 'Active',
      },
      {
        'id': 'VR-002',
        'name': 'Baliangao Beach Tour',
        'spotId': 'SPOT-002',
        'spotName': 'Baliangao Beach',
        'vrUrl': 'https://example.com/vr/baliangao',
        'thumbnail': '',
        'views': 987,
        'status': 'Active',
      },
      {
        'id': 'VR-003',
        'name': 'Falls Adventure 360',
        'spotId': 'SPOT-003',
        'spotName': 'Sapang Dalaga Falls',
        'vrUrl': 'https://example.com/vr/falls',
        'thumbnail': '',
        'views': 654,
        'status': 'Active',
      },
      {
        'id': 'VR-004',
        'name': 'Historical Plaza Walk',
        'spotId': 'SPOT-004',
        'spotName': 'Oroquieta City Capitol',
        'vrUrl': 'https://example.com/vr/plaza',
        'thumbnail': '',
        'views': 432,
        'status': 'Inactive',
      },
    ];

    _todayCheckIns = _checkIns.where((c) => c['status'] == 'Verified').length;
    _totalTourists = _tourists.length;
    _activeSpots = _touristSpots.where((s) => s.status == 'Active').length;
    _totalVRTours = _vrTours.length;

    _recentActivity = _checkIns.take(5).map((c) {
      return <String, dynamic>{
        'icon': Icons.qr_code_scanner_rounded,
        'color': _primaryOrange,
        'title': c['touristName'],
        'description': 'Checked in at ${c['location']}',
        'time': _formatTime(c['timestamp']),
      };
    }).toList();

    _notifications = [
      {
        'title': 'New Check-in',
        'message': '$_todayCheckIns tourists checked in today',
        'time': 'Just now',
      },
      {
        'title': 'New Tourist',
        'message': 'Maria Santos registered',
        'time': '10 min ago',
      },
      {
        'title': 'VR Tour View',
        'message': 'Azure Coast VR viewed 50 times',
        'time': '1 hour ago',
      },
    ];

    setState(() => _isLoading = false);
    _loadTourismSettings();
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
    const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
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
        row['userId']?.toString().trim() ?? row['tourist_id']?.toString().trim() ?? '';
    final spotNameRaw = row['spot_name']?.toString().trim() ?? '';
    final locationRaw = row['location']?.toString().trim() ?? '';
    final spotIdRaw = row['spotId']?.toString().trim() ?? row['spot_id']?.toString().trim() ?? '';
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
            : (spotIdRaw.isNotEmpty ? spotIdRaw.replaceAll('_', ' ') : 'Unknown location'));

    return <String, dynamic>{
      ...row,
      'touristName': touristName,
      'location': location,
      // `qr_checkins` typically has no explicit status; default to verified.
      'status': statusRaw.isNotEmpty ? statusRaw : 'Verified',
    };
  }

  /// Derives per-tourist visit counts from currently loaded `_checkIns`.
  /// This keeps "Visits" in the tourists table aligned with QR check-ins.
  List<Map<String, dynamic>> _mergeTouristVisitsFromCheckIns(
    List<Map<String, dynamic>> tourists,
  ) {
    if (tourists.isEmpty) return tourists;

    final Map<String, int> visitsByUid = <String, int>{};
    for (final c in _checkIns) {
      final uid = (c['userId']?.toString().trim() ??
              c['tourist_id']?.toString().trim() ??
              '')
          .trim();
      if (uid.isEmpty) continue;
      visitsByUid[uid] = (visitsByUid[uid] ?? 0) + 1;
    }

    return tourists.map((t) {
      final uid =
          (t['firebaseUid']?.toString().trim() ?? t['id']?.toString().trim() ?? '')
              .trim();
      final visits = uid.isNotEmpty ? (visitsByUid[uid] ?? 0) : 0;
      return <String, dynamic>{
        ...t,
        'visits': visits,
        'totalVisits': visits,
      };
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
    return counts.entries.reduce((a, b) => a.value >= b.value ? a : b).key;
  }

  List<double> get _lguAnalyticsTrendValues {
    const days = 14;
    final counts = List.filled(days, 0.0);
    final today = DateTime.now();
    for (final c in _checkIns) {
      final d = _parseCheckInTimestamp(c);
      if (d != null) {
        final diff =
            today.difference(DateTime(d.year, d.month, d.day)).inDays;
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
  List<Map<String, dynamic>> _checkInsInDateRange(DateTime start, DateTime end) {
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
    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: _primaryOrange, width: 3),
      ),
      child: Scaffold(
        backgroundColor: _darkBg,
        drawer: _isMobile ? _buildDrawer() : null,
        body: Row(
          children: [
            if (!_isMobile) _buildSidebar(),
            Expanded(child: _buildMainContent()),
          ],
        ),
        bottomNavigationBar: _isMobile ? _buildBottomNav() : null,
      ),
    );
  }

  Widget _buildDrawer() {
    return Drawer(
      backgroundColor: _sidebarBg,
      child: Column(
        children: [
          const SizedBox(height: 12),
          _buildLogoRow(expanded: true),
          const SizedBox(height: 16),
          _buildUserInfo(expanded: true),
          const SizedBox(height: 16),
          _buildSidebarNavScroll(expanded: true),
          const SizedBox(height: 12),
        ],
      ),
    );
  }

  Widget _buildBottomNav() {
    return Container(
      decoration: BoxDecoration(
        color: _sidebarBg,
        border: Border(top: BorderSide(color: Colors.grey.shade200)),
      ),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: List.generate(_navItems.length, (index) {
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
                    borderRadius: BorderRadius.circular(20),
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
                              : FontWeight.normal,
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
    return ClipRRect(
      borderRadius: BorderRadius.only(
        topRight: Radius.circular(_tdSidebarOuterRadius),
        bottomRight: Radius.circular(_tdSidebarOuterRadius),
      ),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 250),
        width: _isSidebarExpanded ? 260 : 80,
        color: _sidebarBg,
        child: Column(
          children: [
            const SizedBox(height: 12),
            _buildLogoRow(expanded: _isSidebarExpanded),
            const SizedBox(height: 16),
            if (_isSidebarExpanded) _buildUserInfo(expanded: true),
            if (_isSidebarExpanded) const SizedBox(height: 16),
            _buildSidebarNavScroll(expanded: _isSidebarExpanded),
            const SizedBox(height: 12),
          ],
        ),
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
                  onTap: () {
                    if (_isMobile) {
                      Navigator.pop(context);
                    } else {
                      _toggleSidebar();
                    }
                  },
                  borderRadius: BorderRadius.circular(14),
                  child: Padding(
                    padding: const EdgeInsets.all(8),
                    child: Icon(Icons.close_rounded, color: Colors.white, size: 20),
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
                    child: Icon(Icons.menu_rounded, color: Colors.white, size: 20),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildLogo({required bool expanded}) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final maxW = constraints.maxWidth.isFinite && constraints.maxWidth > 0
            ? constraints.maxWidth
            : (expanded ? 220.0 : 48.0);
        final maxWidth = expanded ? maxW.clamp(48.0, 220.0) : 48.0;
        final h = expanded ? 56.0 : 48.0;
        if (!expanded) {
          return Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.15),
              borderRadius: BorderRadius.circular(20),
            ),
            child: SizedBox(
              width: 36,
              height: 36,
              child: TransparentLogo(
                width: 36,
                height: 36,
                fit: BoxFit.contain,
                errorIcon: Icons.travel_explore,
                errorIconSize: 22,
                errorIconColor: Colors.white,
              ),
            ),
          );
        }
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: _sidebarHover,
            borderRadius: BorderRadius.circular(22),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.15),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: SizedBox(
            width: maxWidth,
            height: h,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 48,
                  height: 48,
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(14),
                    child: TransparentLogo(
                      width: 36,
                      height: 36,
                      fit: BoxFit.contain,
                      errorIcon: Icons.travel_explore,
                      errorIconSize: 28,
                      errorIconColor: Colors.white,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Flexible(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text(
                        'ATMOS TRS',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 0.5,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        'Tourism Office',
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.85),
                          fontSize: 13,
                          fontWeight: FontWeight.w400,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildUserInfo({required bool expanded}) {
    if (!expanded) return const SizedBox.shrink();

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _accentOrange,
        borderRadius: BorderRadius.circular(26),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.12),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Row(
        children: [
          _buildSidebarAvatar(size: 46),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        _profileName.isNotEmpty
                            ? _profileName
                            : (_municipalityName?.isNotEmpty == true
                                ? _municipalityName!
                                : 'Tourism Office'),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(28),
                        border: Border.all(color: _primaryOrange, width: 1.5),
                      ),
                      child: const Text(
                        'Staff',
                        style: TextStyle(
                          color: _primaryOrange,
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
                Text(
                  _municipalityName?.isNotEmpty == true
                      ? 'Tourism Office · Misamis Occidental'
                      : 'Misamis Occidental',
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.9),
                    fontSize: 12,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Sidebar + drawer: one scrollable column so Reports/Settings sit under Analytics
  /// without a tall empty flex gap (ListView in [Expanded] used to reserve that space).
  Widget _buildSidebarNavScroll({required bool expanded}) {
    final bottomInset = MediaQuery.paddingOf(context).bottom;
    return Expanded(
      child: SingleChildScrollView(
        padding: EdgeInsets.only(
          top: 4,
          bottom: 20 + bottomInset,
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
                    _buildTourismNavItem(index: i, expanded: expanded),
                  const SizedBox(height: 4),
                  _buildTourismNavItem(index: _reportsIndex, expanded: expanded),
                  _buildTourismNavItem(
                    index: _settingsIndex,
                    expanded: expanded,
                    bottomMargin: 0,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),
            _buildLogoutButton(expanded: expanded),
          ],
        ),
      ),
    );
  }

  Widget _buildTourismNavItem({
    required int index,
    required bool expanded,
    double bottomMargin = 4,
  }) {
    final item = _navItems[index];
    final isSelected = _selectedIndex == index;
    return Container(
      margin: EdgeInsets.only(bottom: bottomMargin),
      child: Material(
        color: Colors.transparent,
        child: Tooltip(
          message: !expanded ? item.label : '',
          child: InkWell(
            onTap: () {
              setState(() => _selectedIndex = index);
              if (_isMobile) Navigator.pop(context);
            },
            borderRadius: BorderRadius.circular(32),
            hoverColor: Colors.white.withOpacity(0.1),
            splashColor: Colors.white.withOpacity(0.15),
            child: Container(
              padding: EdgeInsets.symmetric(
                horizontal: expanded ? 16 : 0,
                vertical: 10,
              ),
              decoration: BoxDecoration(
                color: isSelected ? _primaryOrange : Colors.transparent,
                borderRadius: BorderRadius.circular(32),
              ),
              child: Row(
                mainAxisAlignment: expanded
                    ? MainAxisAlignment.start
                    : MainAxisAlignment.center,
                children: [
                  Icon(
                    item.icon,
                    color: isSelected
                        ? Colors.white
                        : Colors.white.withOpacity(0.85),
                    size: 22,
                  ),
                  if (expanded) ...[
                    const SizedBox(width: 14),
                    Text(
                      item.label,
                      style: TextStyle(
                        color: isSelected
                            ? Colors.white
                            : Colors.white.withOpacity(0.85),
                        fontSize: 15,
                        fontWeight: isSelected
                            ? FontWeight.w600
                            : FontWeight.w400,
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
      padding: EdgeInsets.only(
        left: expanded ? 16 : 0,
        right: expanded ? 16 : 0,
      ),
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

  // ==================== DASHBOARD SECTION ====================
  Widget _buildDashboardContent() {
    return RefreshIndicator(
      onRefresh: _loadData,
      color: _primaryOrange,
      child: Container(
        margin: EdgeInsets.all(_isMobile ? 12 : 24),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(_tdHeroRadius),
          border: Border.all(
            color: _primaryOrange.withOpacity(0.5),
            width: 2,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.1),
              blurRadius: 28,
              offset: const Offset(0, 8),
              spreadRadius: 0,
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(_tdHeroRadius),
          child: Column(
            children: [
              _buildHeader(
                'Dashboard',
                subtitle: _municipalityName != null
                    ? '$_municipalityName – Tourism Office'
                    : 'Tourism Office Management Panel',
              ),
              if (_showAllDataBanner)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
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
                ),
              Expanded(
                child: Container(
                  color: const Color(0xFFF5F5F5),
                  child: SingleChildScrollView(
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
              ),
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
    bool showHeaderProfile = true,
  }) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: _isMobile ? 16 : 24,
        vertical: 16,
      ),
      decoration: BoxDecoration(
        // Pure white header background (reference style)
        color: Colors.white,
        border: Border(
          bottom: BorderSide(color: Colors.grey.shade300),
        ),
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
                    color: _textDark,
                    fontSize: _isMobile ? 18 : 22,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                if (subtitle != null)
                  Text(
                    subtitle,
                    style: TextStyle(
                      color: _textMuted,
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
              badge: _notifications.isNotEmpty ? '${_notifications.length}' : null,
              showRedDot: _notifications.isNotEmpty,
              onTap: _showNotificationsDialog,
            ),
            const SizedBox(width: 12),
            _buildHeaderAction(
              Icons.search_rounded,
              onTap: _showGlobalSearchDialog,
            ),
            if (showHeaderProfile) ...[
              const SizedBox(width: 12),
              _buildHeaderProfileChip(),
            ],
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
          ],
          if (_isMobile && showAddSpotButton)
            IconButton(
              tooltip: 'Add tourist spot',
              onPressed: _showAddSpotDialog,
              icon: Icon(Icons.add_circle_outline, color: _primaryOrange, size: 28),
            ),
        ],
      ),
    );
  }

  Widget _buildHeaderAction(
    IconData icon, {
    String? badge,
    bool showRedDot = false,
    VoidCallback? onTap,
  }) {
    return Tooltip(
      message: icon == Icons.notifications_outlined
          ? 'Notifications'
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
                color: Colors.grey.shade200,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Icon(icon, color: _textMuted, size: 22),
            ),
            if (showRedDot)
              Positioned(
                right: -2,
                top: -2,
                child: Container(
                  width: 10,
                  height: 10,
                  decoration: const BoxDecoration(
                    color: Colors.redAccent,
                    shape: BoxShape.circle,
                  ),
                ),
              )
            else if (badge != null && badge != '0')
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
    final stats = [
      _StatCard(
        title: 'Today\'s Check-ins',
        value: '$_todayCheckIns',
        change: '+${(_todayCheckIns * 0.15).toInt()}',
        icon: Icons.qr_code_scanner_rounded,
        color: _primaryOrange,
      ),
      _StatCard(
        title: _storedMunicipalityId != null
            ? 'Visitors (check-ins only)'
            : 'Visitors (use Governor for full registry)',
        value: '$_totalTourists',
        change: '+${(_totalTourists * 0.05).toInt()}',
        icon: Icons.people_alt_rounded,
        color: Colors.blue,
      ),
      _StatCard(
        title: 'Active Spots',
        value: '$_activeSpots',
        change: '${_touristSpots.length - _activeSpots} inactive',
        icon: Icons.place_rounded,
        color: Colors.orange,
      ),
      _StatCard(
        title: 'VR Tours',
        value: '$_totalVRTours',
        change: '$activeVrCount active',
        icon: Icons.vrpano_rounded,
        color: Colors.purple,
        isPositiveOverride: activeVrCount > 0,
      ),
    ];

    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: _isMobile ? 2 : (_isTablet ? 2 : 4),
        crossAxisSpacing: 16,
        mainAxisSpacing: 16,
        childAspectRatio: _isMobile ? 0.88 : 1.3,
      ),
      itemCount: stats.length,
      itemBuilder: (context, index) => _buildStatCard(stats[index]),
    );
  }

  Widget _buildSpotQRCodesDashboardCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: _primaryOrange.withOpacity(0.35), width: 2),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.08),
            blurRadius: 18,
            offset: const Offset(0, 5),
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
                      child: Icon(Icons.qr_code_2_rounded, color: _primaryOrange, size: 36),
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
                  'Print or download unique QR codes for each tourist spot in your municipality.',
                  style: TextStyle(color: _textMuted, fontSize: 14, height: 1.4),
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: () => setState(() => _selectedIndex = _spotQRCodesIndex),
                    icon: const Icon(Icons.qr_code_2_rounded, size: 20),
                    label: const Text('View & print spot QR codes'),
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
              children: [
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: _primaryOrange.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(24),
                  ),
                  child: Icon(Icons.qr_code_2_rounded, color: _primaryOrange, size: 36),
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
                        'Print or download unique QR codes for each tourist spot in your municipality.',
                        style: TextStyle(color: _textMuted, fontSize: 14, height: 1.4),
                      ),
                    ],
                  ),
                ),
                FilledButton.icon(
                  onPressed: () => setState(() => _selectedIndex = _spotQRCodesIndex),
                  icon: const Icon(Icons.qr_code_2_rounded, size: 20),
                  label: const Text('View & print spot QR codes'),
                  style: FilledButton.styleFrom(
                    backgroundColor: _primaryOrange,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
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
    final isPositive = stat.isPositiveOverride ?? stat.change.startsWith('+');
    return Container(
      padding: EdgeInsets.all(_isMobile ? 14 : 18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: _cardBorder, width: 1.5),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.08),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: EdgeInsets.all(_isMobile ? 10 : 14),
            decoration: BoxDecoration(
              color: stat.color,
              borderRadius: BorderRadius.circular(24),
              boxShadow: [
                BoxShadow(
                  color: stat.color.withOpacity(0.3),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Icon(
              stat.icon,
              color: Colors.white,
              size: _isMobile ? 22 : 28,
            ),
          ),
          SizedBox(height: _isMobile ? 8 : 12),
          Text(
            stat.title,
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: _textDark,
              fontSize: _isMobile ? 12 : 14,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            stat.value,
            style: TextStyle(
              color: _textDark,
              fontSize: _isMobile ? 18 : 24,
              fontWeight: FontWeight.bold,
              letterSpacing: -0.5,
            ),
          ),
          const SizedBox(height: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: isPositive
                  ? const Color(0xFFDCFCE7)
                  : const Color(0xFFFEE2E2),
              borderRadius: BorderRadius.circular(28),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  isPositive
                      ? Icons.trending_up_rounded
                      : Icons.trending_down_rounded,
                  color: isPositive
                      ? const Color(0xFF16A34A)
                      : const Color(0xFFDC2626),
                  size: 14,
                ),
                const SizedBox(width: 4),
                Text(
                  stat.change,
                  style: TextStyle(
                    color: isPositive
                        ? const Color(0xFF16A34A)
                        : const Color(0xFFDC2626),
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
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
            color: _textDark,
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
                    color: Colors.black.withOpacity(0.06),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
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
                          style: TextStyle(
                            color: _textMuted,
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (activity['time'] != null)
                    Text(
                      activity['time']?.toString() ?? '',
                      style: TextStyle(
                        color: _textMuted,
                        fontSize: 11,
                      ),
                    ),
                ],
              ),
            );
          }),
      ],
    );
  }

  Widget _buildEmptyState(String message, {IconData? icon}) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          children: [
            Icon(icon ?? Icons.inbox_rounded, color: Colors.white24, size: 48),
            const SizedBox(height: 16),
            Text(message, style: const TextStyle(color: _textMuted)),
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
          (c['location']?.toString() ?? '').toLowerCase().contains(searchQuery);

      final matchesStatus =
          _checkInStatusFilter == 'All' || c['status'] == _checkInStatusFilter;

      return matchesSearch && matchesStatus;
    }).toList();

    return RefreshIndicator(
      onRefresh: _loadData,
      color: _primaryOrange,
      child: Container(
        margin: EdgeInsets.all(_isMobile ? 12 : 24),
        decoration: BoxDecoration(
          color: const Color(0xFFFFFBF5),
          borderRadius: BorderRadius.circular(36),
          border: Border.all(color: _primaryOrange, width: 1.5),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(34),
          child: Container(
            color: const Color(0xFFF7F0E8),
            child: Column(
              children: [
                _buildHeader('Check-in Logs', subtitle: 'Manage tourist check-ins'),
                Expanded(
                  child: SingleChildScrollView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: EdgeInsets.all(_isMobile ? 16 : 24),
                    child: Container(
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: _cardBg,
                        borderRadius: BorderRadius.circular(28),
                        border: Border.all(color: Colors.grey.shade200),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.04),
                            blurRadius: 12,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: Column(
                        children: [
                          _buildCheckInsFilters(),
                          const SizedBox(height: 20),
                          if (filteredCheckIns.isEmpty)
                            _buildEmptyState(
                              'No check-ins found',
                              icon: Icons.qr_code_scanner_rounded,
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
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCheckInsFilters() {
    return Wrap(
      spacing: 16,
      runSpacing: 16,
      children: [
        SizedBox(
          width: _isMobile ? double.infinity : 320,
          child: AppSearchBar(
            controller: _checkInsSearchController,
            hintText: 'Search by name or location...',
            onChanged: (value) => setState(() {}),
            horizontalPadding: 0,
            backgroundColor: Colors.white,
            showMicrophone: true,
            height: 48,
          ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          decoration: BoxDecoration(
            color: const Color(0xFFF0F0F0),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: Colors.grey.shade300),
          ),
          child: DropdownButton<String>(
            value: _checkInStatusFilter,
            dropdownColor: Colors.white,
            underline: const SizedBox(),
            icon: Icon(Icons.keyboard_arrow_down_rounded, color: _textDark),
            style: const TextStyle(
              color: _textDark,
              fontWeight: FontWeight.w500,
              fontSize: 14,
            ),
            items: [
              'All',
              'Verified',
              'Pending',
            ]
                .map(
                  (s) => DropdownMenuItem(
                    value: s,
                    child: Text(s),
                  ),
                )
                .toList(),
            onChanged: (value) => setState(() => _checkInStatusFilter = value!),
          ),
        ),
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
                border: Border.all(color: Colors.grey.shade200),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.05),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
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
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          c['touristName'],
                          style: const TextStyle(
                            color: _textDark,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
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
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: DataTable(
        headingRowColor: WidgetStateProperty.all(Colors.grey.shade100),
        headingTextStyle: const TextStyle(
          color: _textDark,
          fontWeight: FontWeight.w600,
          fontSize: 13,
        ),
        dataTextStyle: const TextStyle(
          color: _textDark,
          fontSize: 13,
        ),
        dividerThickness: 1,
        columns: const [
          DataColumn(
            label: Text('Tourist Name'),
          ),
          DataColumn(
            label: Text('Tourist ID'),
          ),
          DataColumn(
            label: Text('Location'),
          ),
          DataColumn(
            label: Text('Time'),
          ),
          DataColumn(
            label: Text('Status'),
          ),
          DataColumn(
            label: Text('Actions'),
          ),
        ],
        rows: checkIns
            .map(
              (c) => DataRow(
                cells: [
                  DataCell(
                    Text(
                      c['touristName'] ?? '',
                      style: const TextStyle(color: _textDark),
                    ),
                  ),
                  DataCell(
                    Text(
                      c['touristId'] ?? 'N/A',
                      style: const TextStyle(color: _textMuted),
                    ),
                  ),
                  DataCell(
                    Text(
                      c['location'] ?? '',
                      style: const TextStyle(color: _textDark),
                    ),
                  ),
                  DataCell(
                    Text(
                      _formatTime(c['timestamp']),
                      style: const TextStyle(color: _textMuted),
                    ),
                  ),
                  DataCell(_buildStatusBadge(c['status'])),
                  DataCell(
                    IconButton(
                      onPressed: () => _showCheckInDetailsDialog(c),
                      icon: const Icon(
                        Icons.visibility_rounded,
                        color: Colors.blue,
                        size: 22,
                      ),
                      tooltip: 'View Details',
                      style: IconButton.styleFrom(
                        backgroundColor: Colors.blue.withOpacity(0.08),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            )
            .toList(),
      ),
    );
  }

  Widget _buildStatusBadge(String status) {
    final isVerified = status == 'Verified';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: isVerified
            ? _primaryOrange.withOpacity(0.18)
            : Colors.orange.withOpacity(0.18),
        borderRadius: BorderRadius.circular(28),
        border: Border.all(
          color: (isVerified ? _primaryOrange : Colors.orange).withOpacity(0.4),
          width: 1,
        ),
      ),
      child: Text(
        status,
        style: TextStyle(
          color: isVerified ? _primaryOrange : Colors.orange.shade800,
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  void _showCheckInDetailsDialog(Map<String, dynamic> checkIn) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: _cardBg,
        title: const Text(
          'Check-in Details',
          style: TextStyle(color: Colors.white),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildDetailRow('Tourist Name', checkIn['touristName']),
            _buildDetailRow('Tourist ID', checkIn['touristId'] ?? 'N/A'),
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
        content: Text('Check-in verified successfully'),
        backgroundColor: _primaryOrange,
      ),
    );
  }

  // ==================== TOURIST SPOTS SECTION ====================
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
      child: Container(
        color: _darkBg,
        child: Column(
          children: [
            _buildHeader(
              'Tourist Spots',
              subtitle: 'Manage tourist destinations',
            ),
            Expanded(
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: EdgeInsets.all(_isMobile ? 16 : 24),
                child: Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: _cardBg,
                    borderRadius: BorderRadius.circular(28),
                    border: Border.all(color: _cardBorder),
                  ),
                  child: Column(
                    children: [
                      _buildSpotsFilters(),
                      const SizedBox(height: 20),
                      if (filteredSpots.isEmpty)
                        _buildEmptyState(
                          'No tourist spots found',
                          icon: Icons.place_rounded,
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
          ],
        ),
      ),
    );
  }

  /// One QR per LGU (`ATMOS-TRS-LGU:municipalityId` + optional anchor) — downloadable PNG/PDF.
  Widget _buildLguQrCardForDashboard(String municipalityId, String displayName) {
    final coords = getMunicipalityAnchorCoordinates(municipalityId);
    final qrData = coords != null
        ? lguQrData(municipalityId, anchorLat: coords.lat, anchorLng: coords.lng)
        : lguQrData(municipalityId);
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(26),
        border: Border.all(color: _cardBorder),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.06),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Text(
            'Your LGU QR code',
            style: TextStyle(
              color: _textDark,
              fontSize: 18,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            displayName,
            style: TextStyle(
              color: _primaryOrange,
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Unique to your municipality — download for posters, flyers, or social media.',
            textAlign: TextAlign.center,
            style: TextStyle(color: _textMuted, fontSize: 13),
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: Colors.grey.shade300),
            ),
            child: QrImageView(
              data: qrData,
              version: QrVersions.auto,
              size: 200,
              backgroundColor: Colors.white,
              errorCorrectionLevel: QrErrorCorrectLevel.H,
            ),
          ),
          const SizedBox(height: 12),
          SelectableText(
            qrData,
            style: TextStyle(
              color: _textMuted,
              fontSize: 11,
              fontFamily: 'monospace',
            ),
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 12,
            runSpacing: 8,
            alignment: WrapAlignment.center,
            children: [
              OutlinedButton.icon(
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
                icon: Icon(Icons.download_rounded, color: _primaryOrange, size: 20),
                label: Text(
                  'Download PNG',
                  style: TextStyle(color: _primaryOrange, fontWeight: FontWeight.w600),
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
                icon: Icon(Icons.picture_as_pdf_rounded, color: _primaryOrange, size: 20),
                label: Text(
                  'Download PDF',
                  style: TextStyle(color: _primaryOrange, fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSpotQRCodesContent() {
    return FutureBuilder<String?>(
      future: SessionStorage.getStoredMunicipalityId(),
      builder: (context, snapshot) {
        final storedMunicipalityId = snapshot.data;
        final spots = _touristSpots;
        String? municipalityDisplayName = _municipalityName;
        if (storedMunicipalityId == null && spots.isNotEmpty) {
          municipalityDisplayName = null;
        }

        return RefreshIndicator(
          onRefresh: _loadData,
          color: _primaryOrange,
          child: Container(
            color: _darkBg,
            child: Column(
              children: [
                _buildHeader(
                  'Spot QR Codes',
                  subtitle: municipalityDisplayName != null
                      ? 'LGU QR for $municipalityDisplayName, then unique QR per tourist spot — PNG/PDF on each card (same as Governor portal)'
                      : 'Your municipality LGU QR below, then one QR per spot — download PNG or PDF on each card',
                  actions: [
                    TextButton.icon(
                      onPressed: () => _printSpotPosters(storedMunicipalityId),
                      icon: const Icon(Icons.picture_as_pdf_rounded, size: 20),
                      label: const Text('Print posters (A4)'),
                      style: TextButton.styleFrom(
                        foregroundColor: _primaryOrange,
                      ),
                    ),
                    TextButton.icon(
                      onPressed: () => _printSpotQRCodes(storedMunicipalityId),
                      icon: const Icon(Icons.print_rounded, size: 20),
                      label: const Text('Print'),
                      style: TextButton.styleFrom(
                        foregroundColor: _primaryOrange,
                      ),
                    ),
                  ],
                ),
                Expanded(
                  child: spots.isEmpty && storedMunicipalityId == null
                      ? Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.qr_code_2_rounded, size: 64, color: _textMuted),
                              const SizedBox(height: 16),
                              Text(
                                'No tourist spots to show QR codes',
                                style: TextStyle(color: _textMuted, fontSize: 16),
                              ),
                              const SizedBox(height: 8),
                              Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 24),
                                child: Text(
                                  'Add spots in Firestore with municipalityId for your municipality. Use Print above when you have spots.',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(color: _textMuted, fontSize: 14),
                                ),
                              ),
                            ],
                          ),
                        )
                      : SingleChildScrollView(
                          physics: const AlwaysScrollableScrollPhysics(),
                          padding: EdgeInsets.all(_isMobile ? 16 : 24),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              if (storedMunicipalityId != null &&
                                  storedMunicipalityId.isNotEmpty)
                                Padding(
                                  padding: const EdgeInsets.only(bottom: 24),
                                  child: _buildLguQrCardForDashboard(
                                    storedMunicipalityId,
                                    municipalityDisplayName ??
                                        storedMunicipalityId,
                                  ),
                                ),
                              if (spots.isNotEmpty) ...[
                                Align(
                                  alignment: Alignment.centerLeft,
                                  child: Text(
                                    'Tourist spots (unique QR each)',
                                    style: TextStyle(
                                      color: _textDark,
                                      fontSize: 18,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  'Each code is unique to that location — use PNG or PDF for posters and signage.',
                                  style: TextStyle(color: _textMuted, fontSize: 13),
                                ),
                                const SizedBox(height: 16),
                              ],
                              if (spots.isEmpty)
                                Padding(
                                  padding: const EdgeInsets.only(top: 8),
                                  child: Column(
                                    children: [
                                      Icon(Icons.place_rounded,
                                          size: 48, color: _textMuted),
                                      const SizedBox(height: 12),
                                      Text(
                                        'No individual spot QR codes yet',
                                        style: TextStyle(
                                            color: _textMuted, fontSize: 16),
                                      ),
                                      const SizedBox(height: 8),
                                      Text(
                                        'Add tourist_spots in Firestore for your LGU to print per-location codes.',
                                        textAlign: TextAlign.center,
                                        style: TextStyle(
                                            color: _textMuted, fontSize: 14),
                                      ),
                                    ],
                                  ),
                                )
                              else if (_isMobile)
                                _buildSpotQRCodesGridMobile(
                                    spots, storedMunicipalityId)
                              else
                                _buildSpotQRCodesGrid(
                                    spots, storedMunicipalityId),
                            ],
                          ),
                        ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<Uint8List?> _qrDataToPngBytes(String qrData, {int size = 200}) async {
    return qrDataToPngBytes(qrData, size: size);
  }

  /// Prints A4 portrait posters (one page per spot) for posting at entrances.
  Future<void> _printSpotPosters(String? storedMunicipalityId) async {
    final spots = _touristSpots;
    if (spots.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'No tourist spots yet. Add spots in Firestore with municipalityId, then use Print posters.',
            ),
            backgroundColor: _primaryOrange,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
      return;
    }
    final posterItems = spots.map((s) => SpotPosterItem(
      id: s.id,
      name: s.name.isNotEmpty ? s.name : 'Tourist Spot',
      municipality: s.municipality.isNotEmpty ? s.municipality : (_municipalityName ?? ''),
      municipalityId: s.municipalityId.isNotEmpty ? s.municipalityId : (storedMunicipalityId ?? ''),
    )).toList();
    try {
      final pdf = await buildSpotPosterPdfDocument(
        posterItems,
        (String qrData, int size) => _qrDataToPngBytes(qrData, size: size),
      );
      await Printing.layoutPdf(
        onLayout: (PdfPageFormat format) async => pdf.save(),
        name: 'ATMOS-TRS-Spot-Posters.pdf',
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Generated ${spots.length} poster page(s). Print or save as PDF.'),
            backgroundColor: _primaryOrange,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Print posters failed: $e'),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  Future<void> _printSpotQRCodes(String? storedMunicipalityId) async {
    final spots = _touristSpots;
    if (spots.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'No tourist spots yet. Add spots in Firestore with municipalityId for your municipality, then use Print to generate QR codes.',
            ),
            backgroundColor: _primaryOrange,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
      return;
    }
    final pdf = pw.Document();
    const qrSize = 120.0;
    final municipalityName = _municipalityName ?? storedMunicipalityId ?? '';

    for (var i = 0; i < spots.length; i++) {
      final spot = spots[i];
      final spotId = spot.id;
      final municipalityId = spot.municipalityId.isNotEmpty
          ? spot.municipalityId
          : (storedMunicipalityId ?? '');
      final spotName = spot.name.isNotEmpty ? spot.name : 'Spot';
      final qrData = municipalityId.isNotEmpty ? spotQrData(municipalityId, spotId) : '';
      pw.Widget? qrImage;
      if (qrData.isNotEmpty) {
        final bytes = await _qrDataToPngBytes(qrData, size: qrSize.toInt());
        if (bytes != null && bytes.isNotEmpty) {
          qrImage = pw.Image(pw.MemoryImage(bytes), width: qrSize, height: qrSize);
        }
      }
      pdf.addPage(
        pw.Page(
          pageFormat: PdfPageFormat.a4,
          build: (pw.Context context) {
            return pw.Center(
              child: pw.Column(
                mainAxisSize: pw.MainAxisSize.min,
                children: [
                  pw.Text(
                    'Spot QR Code – $municipalityName',
                    style: pw.TextStyle(fontSize: 12),
                  ),
                  pw.SizedBox(height: 8),
                  pw.Text(
                    spotName,
                    style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold),
                    textAlign: pw.TextAlign.center,
                  ),
                  pw.SizedBox(height: 16),
                  if (qrImage != null) qrImage else pw.Text('Set municipalityId in Firestore', style: pw.TextStyle(fontSize: 10)),
                ],
              ),
            );
          },
        ),
      );
    }

    try {
      await Printing.layoutPdf(
        onLayout: (PdfPageFormat format) async => pdf.save(),
        name: 'Spot-QR-Codes-$municipalityName.pdf',
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Print failed: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Widget _buildSpotQRCodesGrid(List<TouristSpot> spots, String? storedMunicipalityId) {
    return Wrap(
      spacing: 24,
      runSpacing: 24,
      children: spots.map((spot) {
        final spotId = spot.id;
        final municipalityId = spot.municipalityId.isNotEmpty
            ? spot.municipalityId
            : (storedMunicipalityId ?? '');
        final spotName = spot.name.isNotEmpty ? spot.name : 'Spot';
        final municipalityName = spot.municipality.isNotEmpty
            ? spot.municipality
            : (_municipalityName ?? municipalityId);
        final qrData = municipalityId.isNotEmpty ? spotQrData(municipalityId, spotId) : '';

        return Container(
          width: 220,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: _cardBg,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: _cardBorder),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (qrData.isEmpty)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(
                    'Set municipalityId in Firestore',
                    style: TextStyle(color: Colors.orange.shade800, fontSize: 11),
                  ),
                ),
              Text(
                spotName,
                style: const TextStyle(
                  color: _textDark,
                  fontWeight: FontWeight.w600,
                  fontSize: 14,
                ),
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 4),
              Text(
                municipalityName,
                style: TextStyle(color: _textMuted, fontSize: 12),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              if (qrData.isNotEmpty)
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: QrImageView(
                    data: qrData,
                    version: QrVersions.auto,
                    size: 200,
                    backgroundColor: Colors.white,
                    errorCorrectionLevel: QrErrorCorrectLevel.H,
                  ),
                ),
              if (qrData.isNotEmpty) ...[
                const SizedBox(height: 10),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    TextButton(
                      onPressed: () async {
                        await downloadSpotQrPng(municipalityId, spotId);
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
                        style: TextStyle(color: _primaryOrange),
                      ),
                    ),
                    TextButton(
                      onPressed: () async {
                        await downloadSpotQrPdf(
                          municipalityId: municipalityId,
                          spotId: spotId,
                          spotName: spotName,
                          municipalityDisplayName: municipalityName,
                        );
                      },
                      child: Text(
                        'PDF',
                        style: TextStyle(color: _primaryOrange),
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        );
      }).toList(),
    );
  }

  Widget _buildSpotQRCodesGridMobile(List<TouristSpot> spots, String? storedMunicipalityId) {
    return Column(
      children: spots.map((spot) {
        final spotId = spot.id;
        final municipalityId = spot.municipalityId.isNotEmpty
            ? spot.municipalityId
            : (storedMunicipalityId ?? '');
        final spotName = spot.name.isNotEmpty ? spot.name : 'Spot';
        final municipalityName = spot.municipality.isNotEmpty
            ? spot.municipality
            : (_municipalityName ?? municipalityId);
        final qrData = municipalityId.isNotEmpty ? spotQrData(municipalityId, spotId) : '';

        return Container(
          margin: const EdgeInsets.only(bottom: 16),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: _cardBg,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: _cardBorder),
          ),
          child: Column(
            children: [
              Text(
                spotName,
                style: const TextStyle(
                  color: _textDark,
                  fontWeight: FontWeight.w600,
                  fontSize: 16,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 4),
              Text(
                municipalityName,
                style: TextStyle(color: _textMuted, fontSize: 13),
              ),
              const SizedBox(height: 16),
              if (qrData.isNotEmpty)
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: QrImageView(
                    data: qrData,
                    version: QrVersions.auto,
                    size: 200,
                    backgroundColor: Colors.white,
                    errorCorrectionLevel: QrErrorCorrectLevel.H,
                  ),
                )
              else
                Text(
                  'Set municipalityId in Firestore for this spot',
                  style: TextStyle(color: Colors.orange.shade800, fontSize: 12),
                ),
              if (qrData.isNotEmpty) ...[
                const SizedBox(height: 10),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    TextButton(
                      onPressed: () async {
                        await downloadSpotQrPng(municipalityId, spotId);
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
                        style: TextStyle(color: _primaryOrange),
                      ),
                    ),
                    TextButton(
                      onPressed: () async {
                        await downloadSpotQrPdf(
                          municipalityId: municipalityId,
                          spotId: spotId,
                          spotName: spotName,
                          municipalityDisplayName: municipalityName,
                        );
                      },
                      child: Text(
                        'PDF',
                        style: TextStyle(color: _primaryOrange),
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        );
      }).toList(),
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
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          decoration: BoxDecoration(
            color: Colors.grey.shade200,
            borderRadius: BorderRadius.circular(16),
          ),
          child: DropdownButton<String>(
            value: _spotCategoryFilter,
            dropdownColor: _cardBg,
            underline: const SizedBox(),
            style: const TextStyle(color: Colors.white),
            items: _categories
                .map((c) => DropdownMenuItem(value: c, child: Text(c)))
                .toList(),
            onChanged: (value) => setState(() => _spotCategoryFilter = value!),
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
        headingRowColor: WidgetStateProperty.all(
          Colors.white.withOpacity(0.03),
        ),
        columns: const [
          DataColumn(
            label: Text(
              'Spot Name',
              style: TextStyle(color: _textMuted, fontWeight: FontWeight.w600),
            ),
          ),
          DataColumn(
            label: Text(
              'Category',
              style: TextStyle(color: _textMuted, fontWeight: FontWeight.w600),
            ),
          ),
          DataColumn(
            label: Text(
              'Location',
              style: TextStyle(color: _textMuted, fontWeight: FontWeight.w600),
            ),
          ),
          DataColumn(
            label: Text(
              'Visitors',
              style: TextStyle(color: _textMuted, fontWeight: FontWeight.w600),
            ),
          ),
          DataColumn(
            label: Text(
              'Status',
              style: TextStyle(color: _textMuted, fontWeight: FontWeight.w600),
            ),
          ),
          DataColumn(
            label: Text(
              'Actions',
              style: TextStyle(color: _textMuted, fontWeight: FontWeight.w600),
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
                      style: const TextStyle(color: Colors.white),
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
                      style: const TextStyle(color: Colors.white),
                    ),
                  ),
                  DataCell(
                    Text(
                      '${s.visitors}',
                      style: TextStyle(color: _textMuted),
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
                    _buildDialogTextField(nameController, 'Spot Name', Icons.place),
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
                            .map((c) => DropdownMenuItem(value: c, child: Text(c)))
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
                      'VR Link (optional)',
                      Icons.vrpano,
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Cancel', style: TextStyle(color: _textMuted)),
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
                      latitude: 0,
                      longitude: 0,
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
                    final docId = await TouristSpotsFirestoreService.addSpot(spot);
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
                  style: ElevatedButton.styleFrom(backgroundColor: _primaryOrange),
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
    final imageUrlController = TextEditingController(
      text: spot.imageUrl ?? '',
    );
    final vrLinkController = TextEditingController(text: spot.vrLink ?? '');
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
                    _buildDialogTextField(nameController, 'Spot Name', Icons.place),
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
                            .map((c) => DropdownMenuItem(value: c, child: Text(c)))
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
                      'VR Link',
                      Icons.vrpano,
                    ),
                  ],
                ),
              ),
              actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel', style: TextStyle(color: _textMuted)),
            ),
            ElevatedButton(
              onPressed: () async {
                final ok = await TouristSpotsFirestoreService.updateSpot(
                  spot.id,
                  {
                    'name': nameController.text.trim(),
                    'category': selectedCategory,
                    'municipality': cityController.text.trim(),
                    'description': descriptionController.text.trim(),
                    'image_url': imageUrlController.text.trim().isNotEmpty
                        ? imageUrlController.text.trim()
                        : null,
                    'vr_link': vrLinkController.text.trim().isNotEmpty
                        ? vrLinkController.text.trim()
                        : null,
                  },
                );
                Navigator.pop(context);
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        ok
                            ? 'Tourist spot updated successfully'
                            : 'Failed to update. Check Firebase.',
                      ),
                      backgroundColor: ok ? _primaryOrange : Colors.redAccent,
                    ),
                  );
                }
              },
              style: ElevatedButton.styleFrom(backgroundColor: _primaryOrange),
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
                      ok ? 'Tourist spot deleted' : 'Failed to delete. Check Firebase.',
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
    final ok = await TouristSpotsFirestoreService.updateSpotStatus(spot.id, newStatus);
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

  Widget _buildDialogTextField(
    TextEditingController controller,
    String label,
    IconData icon, {
    int maxLines = 1,
    bool readOnly = false,
  }) {
    return TextField(
      controller: controller,
      maxLines: maxLines,
      readOnly: readOnly,
      decoration: InputDecoration(
        labelText: label,
        labelStyle: TextStyle(color: _textMuted),
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

  Widget _buildTouristSpotSelector({
    required String? selectedSpotId,
    required VoidCallback onTap,
  }) {
    TouristSpot? spot;
    if (selectedSpotId != null) {
      try {
        spot = _touristSpots.firstWhere(
          (s) => s.id == selectedSpotId,
        );
      } catch (_) {}
    }
    final label = spot != null
        ? (spot.name.isNotEmpty ? spot.name : 'Unnamed')
        : 'Select Tourist Spot';
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        decoration: BoxDecoration(
          color: Colors.grey.shade200,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          children: [
            Icon(Icons.place, color: _primaryOrange),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  color: spot != null ? _textDark : _textMuted,
                  fontSize: 16,
                ),
              ),
            ),
            Icon(Icons.arrow_drop_down, color: _textMuted),
          ],
        ),
      ),
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
      final id = t['touristId']?.toString() ?? t['id']?.toString() ?? '';
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
      child: Container(
        color: _darkBg,
        child: Column(
          children: [
            _buildHeader(
              _storedMunicipalityId != null
                  ? 'Check-in visitors'
                  : 'Visitors',
              subtitle: _storedMunicipalityId != null
                  ? 'Tourists who checked in at your locations — full app registration list is visible only on the Governor admin dashboard'
                  : 'Province-wide app registrations are on the Governor dashboard only — assign your LGU municipality to see visitors linked to your check-ins',
            ),
            Expanded(
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: EdgeInsets.all(_isMobile ? 16 : 24),
                child: Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: _cardBg,
                    borderRadius: BorderRadius.circular(28),
                    border: Border.all(color: _cardBorder),
                  ),
                  child: Column(
                    children: [
                      _buildTouristsFilters(),
                      const SizedBox(height: 20),
                      if (filteredTourists.isEmpty)
                        _buildEmptyState(
                          _storedMunicipalityId != null
                              ? 'No check-in visitors yet — the full list of app registrants is on Governor admin only'
                              : 'No visitor list — full app registrations are on Governor admin. Assign a municipality to your LGU account to see visitors who checked in at your sites.',
                          icon: Icons.people_alt_rounded,
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
          ],
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
              borderRadius: BorderRadius.circular(20),
            ),
            elevation: 0,
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
        final touristId =
            t['touristId']?.toString() ?? t['id']?.toString() ?? 'N/A';
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
            border: Border.all(color: Colors.grey.shade200),
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
                  style: TextStyle(
                    color: _textMuted,
                    fontSize: 11,
                  ),
                ),
                Text(
                  'Time: ${_formatRegisteredTimeOnlyDisplay(_registeredDateTimeNullableFromTourist(t))}',
                  style: TextStyle(
                    color: _textMuted,
                    fontSize: 11,
                  ),
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
        border: Border.all(color: Colors.grey.shade200),
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
            dividerThickness: 1,
            horizontalMargin: 20,
            columnSpacing: 28,
            columns: const [
              DataColumn(
                label: Text('Name'),
              ),
              DataColumn(
                label: Text('Tourist ID'),
              ),
              DataColumn(
                label: Text('Type'),
              ),
              DataColumn(
                label: Text('Origin'),
              ),
              DataColumn(
                label: Text('Date'),
              ),
              DataColumn(
                label: Text('Time'),
              ),
              DataColumn(
                label: Text('Visits'),
              ),
              DataColumn(
                label: Text('Status'),
              ),
              DataColumn(
                label: Text('Actions'),
              ),
            ],
            rows: sorted.map((t) {
              final name = _getTouristDisplayName(t);
              final touristId =
                  t['touristId']?.toString() ?? t['id']?.toString() ?? 'N/A';
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
                      style: const TextStyle(
                        color: _textDark,
                        fontSize: 13,
                      ),
                    ),
                  ),
                  DataCell(
                    Text(
                      _formatRegisteredTimeOnlyDisplay(regDt),
                      style: const TextStyle(
                        color: _textDark,
                        fontSize: 13,
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
                        backgroundColor: const Color(0xFF0EA5E9).withOpacity(0.1),
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
    final touristId =
        tourist['touristId']?.toString() ?? tourist['id']?.toString() ?? 'N/A';
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
      final touristId =
          t['touristId']?.toString() ?? t['id']?.toString() ?? 'N/A';
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
      final touristId =
          t['touristId']?.toString() ?? t['id']?.toString() ?? 'N/A';
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
                'Tourists export',
                style: const TextStyle(
                  color: Colors.white,
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
                          'No tourists to export.',
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
                              border: TableBorder.symmetric(
                                inside: BorderSide(
                                  color: _cardBorder.withValues(alpha: 0.8),
                                ),
                              ),
                              columns: [
                                DataColumn(
                                    label: Text('Tourist ID', style: headerStyle)),
                                DataColumn(
                                    label: Text('Full name', style: headerStyle)),
                                DataColumn(
                                    label: Text('Email', style: headerStyle)),
                                DataColumn(
                                    label: Text('Mobile', style: headerStyle)),
                                DataColumn(
                                    label:
                                        Text('Nationality', style: headerStyle)),
                                DataColumn(
                                    label: Text('Type', style: headerStyle)),
                                DataColumn(
                                    label: Text('Origin', style: headerStyle)),
                                DataColumn(
                                    label: Text('Visits', style: headerStyle)),
                                DataColumn(
                                    label: Text('Status', style: headerStyle)),
                                DataColumn(
                                    label: Text('Date', style: headerStyle)),
                                DataColumn(
                                    label: Text('Time', style: headerStyle)),
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
                border: Border(
                  left: BorderSide(color: _primaryOrange, width: 3),
                ),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
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
        border: Border(
          left: BorderSide(color: _primaryOrange, width: 4),
        ),
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
          insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
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
                              border: Border.all(color: const Color(0xFFD4D4D4)),
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
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFFBF7),
                      border: Border(top: BorderSide(color: _cardBorder)),
                    ),
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
                            icon: Icon(Icons.download_rounded, color: _primaryOrange, size: 20),
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
      child: Container(
        color: _darkBg,
        child: Column(
          children: [
            _buildHeader(
              'VR Tours',
              subtitle: 'Manage virtual reality experiences',
            ),
            Expanded(
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: EdgeInsets.all(_isMobile ? 16 : 24),
                child: Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: _cardBg,
                    borderRadius: BorderRadius.circular(28),
                    border: Border.all(color: _cardBorder),
                  ),
                  child: Column(
                    children: [
                      _buildVRToursFilters(),
                      const SizedBox(height: 20),
                      if (filteredTours.isEmpty)
                        _buildEmptyState(
                          'No VR tours found',
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
          ],
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
        ElevatedButton.icon(
          onPressed: _showAddVRTourDialog,
          icon: const Icon(Icons.add, size: 18),
          label: const Text('Add VR Tour'),
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.purple,
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
                          v['name'],
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
                    'Linked to: ${v['spotName']}',
                    style: TextStyle(color: _textMuted),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${v['views']} views',
                    style: TextStyle(color: _textMuted, fontSize: 12),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      IconButton(
                        onPressed: () => _playVRTour(v),
                        icon: const Icon(
                          Icons.play_circle,
                          color: Colors.purple,
                          size: 24,
                        ),
                      ),
                      IconButton(
                        onPressed: () => _showEditVRTourDialog(v),
                        icon: const Icon(
                          Icons.edit,
                          color: Colors.blue,
                          size: 20,
                        ),
                      ),
                      IconButton(
                        onPressed: () => _showDeleteVRTourDialog(v),
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

  Widget _buildVRToursTable(List<Map<String, dynamic>> tours) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: DataTable(
        headingRowColor: WidgetStateProperty.all(
          Colors.white.withOpacity(0.03),
        ),
        columns: const [
          DataColumn(
            label: Text(
              'Tour Name',
              style: TextStyle(color: _textMuted, fontWeight: FontWeight.w600),
            ),
          ),
          DataColumn(
            label: Text(
              'Tourist Spot',
              style: TextStyle(color: _textMuted, fontWeight: FontWeight.w600),
            ),
          ),
          DataColumn(
            label: Text(
              'Views',
              style: TextStyle(color: _textMuted, fontWeight: FontWeight.w600),
            ),
          ),
          DataColumn(
            label: Text(
              'Status',
              style: TextStyle(color: _textMuted, fontWeight: FontWeight.w600),
            ),
          ),
          DataColumn(
            label: Text(
              'Actions',
              style: TextStyle(color: _textMuted, fontWeight: FontWeight.w600),
            ),
          ),
        ],
        rows: tours
            .map(
              (v) => DataRow(
                cells: [
                  DataCell(
                    Text(
                      v['name'],
                      style: const TextStyle(color: Colors.white),
                    ),
                  ),
                  DataCell(
                    Text(v['spotName'], style: TextStyle(color: _textMuted)),
                  ),
                  DataCell(
                    Text(
                      '${v['views']}',
                      style: const TextStyle(color: Colors.white),
                    ),
                  ),
                  DataCell(_buildStatusBadge(v['status'])),
                  DataCell(
                    Row(
                      children: [
                        IconButton(
                          onPressed: () => _playVRTour(v),
                          icon: const Icon(
                            Icons.play_circle,
                            color: Colors.purple,
                            size: 18,
                          ),
                          tooltip: 'Play',
                        ),
                        IconButton(
                          onPressed: () => _showEditVRTourDialog(v),
                          icon: const Icon(
                            Icons.edit,
                            color: Colors.blue,
                            size: 18,
                          ),
                          tooltip: 'Edit',
                        ),
                        IconButton(
                          onPressed: () => _showDeleteVRTourDialog(v),
                          icon: const Icon(
                            Icons.delete,
                            color: Colors.redAccent,
                            size: 18,
                          ),
                          tooltip: 'Delete',
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

  void _showAddVRTourDialog() {
    final nameController = TextEditingController();
    final vrUrlController = TextEditingController();
    final thumbnailController = TextEditingController();
    String? selectedSpotId = _touristSpots.isNotEmpty
        ? _touristSpots.first.id
        : null;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          backgroundColor: _cardBg,
          title: const Text(
            'Add VR Tour',
            style: TextStyle(color: Colors.white),
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildDialogTextField(
                  nameController,
                  'Tour Name',
                  Icons.vrpano,
                ),
                const SizedBox(height: 16),
                _buildTouristSpotSelector(
                  selectedSpotId: selectedSpotId,
                  onTap: () async {
                    if (_touristSpots.isEmpty) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('No tourist spots available'),
                          backgroundColor: Colors.orange,
                        ),
                      );
                      return;
                    }
                    final picked = await showModalBottomSheet<String>(
                      context: context,
                      backgroundColor: _cardBg,
                      shape: const RoundedRectangleBorder(
                        borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
                      ),
                      builder: (ctx) => SafeArea(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Padding(
                              padding: const EdgeInsets.all(16),
                              child: Text(
                                'Select Tourist Spot',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 18,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                            Flexible(
                              child: ListView.builder(
                                shrinkWrap: true,
                                itemCount: _touristSpots.length,
                                itemBuilder: (ctx, i) {
                                  final s = _touristSpots[i];
                                  final id = s.id;
                                  final name = s.name.isNotEmpty ? s.name : 'Unnamed';
                                  return ListTile(
                                    title: Text(name, style: TextStyle(color: Colors.white)),
                                    onTap: () => Navigator.pop(ctx, id),
                                  );
                                },
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                    if (picked != null && mounted) {
                      setDialogState(() => selectedSpotId = picked);
                    }
                  },
                ),
                const SizedBox(height: 16),
                _buildDialogTextField(vrUrlController, 'VR URL', Icons.link),
                const SizedBox(height: 16),
                _buildDialogTextField(
                  thumbnailController,
                  'Thumbnail URL (optional)',
                  Icons.image,
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel', style: TextStyle(color: _textMuted)),
            ),
            ElevatedButton(
              onPressed: () {
                if (nameController.text.isEmpty ||
                    vrUrlController.text.isEmpty ||
                    selectedSpotId == null) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Please fill required fields'),
                      backgroundColor: Colors.redAccent,
                    ),
                  );
                  return;
                }

                final selectedSpot = _touristSpots.firstWhere(
                  (s) => s.id == selectedSpotId,
                );

                setState(() {
                  _vrTours.add({
                    'id': 'VR-${DateTime.now().millisecondsSinceEpoch}',
                    'name': nameController.text,
                    'spotId': selectedSpotId,
                    'spotName': selectedSpot.name,
                    'vrUrl': vrUrlController.text,
                    'thumbnail': thumbnailController.text,
                    'views': 0,
                    'status': 'Active',
                  });
                  _totalVRTours = _vrTours.length;
                });

                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('VR tour added successfully'),
                    backgroundColor: _primaryOrange,
                  ),
                );
              },
              style: ElevatedButton.styleFrom(backgroundColor: Colors.purple),
              child: const Text('Add'),
            ),
          ],
        ),
      ),
    );
  }

  void _showEditVRTourDialog(Map<String, dynamic> tour) {
    final nameController = TextEditingController(text: tour['name']);
    final vrUrlController = TextEditingController(text: tour['vrUrl'] ?? '');
    final thumbnailController = TextEditingController(
      text: tour['thumbnail'] ?? '',
    );
    String? selectedSpotId = tour['spotId']?.toString();

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          backgroundColor: _cardBg,
          title: const Text(
            'Edit VR Tour',
            style: TextStyle(color: Colors.white),
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildDialogTextField(
                  nameController,
                  'Tour Name',
                  Icons.vrpano,
                ),
                const SizedBox(height: 16),
                _buildTouristSpotSelector(
                  selectedSpotId: selectedSpotId,
                  onTap: () async {
                    if (_touristSpots.isEmpty) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('No tourist spots available'),
                          backgroundColor: Colors.orange,
                        ),
                      );
                      return;
                    }
                    final picked = await showModalBottomSheet<String>(
                      context: context,
                      backgroundColor: _cardBg,
                      shape: const RoundedRectangleBorder(
                        borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
                      ),
                      builder: (ctx) => SafeArea(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Padding(
                              padding: const EdgeInsets.all(16),
                              child: Text(
                                'Select Tourist Spot',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 18,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                            Flexible(
                              child: ListView.builder(
                                shrinkWrap: true,
                                itemCount: _touristSpots.length,
                                itemBuilder: (ctx, i) {
                                  final s = _touristSpots[i];
                                  final id = s.id;
                                  final name = s.name.isNotEmpty ? s.name : 'Unnamed';
                                  return ListTile(
                                    title: Text(name, style: TextStyle(color: Colors.white)),
                                    onTap: () => Navigator.pop(ctx, id),
                                  );
                                },
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                    if (picked != null && mounted) {
                      setDialogState(() => selectedSpotId = picked);
                    }
                  },
                ),
                const SizedBox(height: 16),
                _buildDialogTextField(vrUrlController, 'VR URL', Icons.link),
                const SizedBox(height: 16),
                _buildDialogTextField(
                  thumbnailController,
                  'Thumbnail URL',
                  Icons.image,
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel', style: TextStyle(color: _textMuted)),
            ),
            ElevatedButton(
              onPressed: () {
                final selectedSpot = _touristSpots.firstWhere(
                  (s) => s.id == selectedSpotId,
                );

                setState(() {
                  final index = _vrTours.indexWhere(
                    (v) => v['id'] == tour['id'],
                  );
                  if (index != -1) {
                    _vrTours[index] = {
                      ..._vrTours[index],
                      'name': nameController.text,
                      'spotId': selectedSpotId,
                      'spotName': selectedSpot.name,
                      'vrUrl': vrUrlController.text,
                      'thumbnail': thumbnailController.text,
                    };
                  }
                });

                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('VR tour updated successfully'),
                    backgroundColor: _primaryOrange,
                  ),
                );
              },
              style: ElevatedButton.styleFrom(backgroundColor: Colors.purple),
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
  }

  void _showDeleteVRTourDialog(Map<String, dynamic> tour) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: _cardBg,
        title: const Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: Colors.redAccent),
            SizedBox(width: 12),
            Text('Delete VR Tour', style: TextStyle(color: Colors.white)),
          ],
        ),
        content: Text(
          'Are you sure you want to delete "${tour['name']}"? This action cannot be undone.',
          style: const TextStyle(color: _textMuted),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel', style: TextStyle(color: _textMuted)),
          ),
          ElevatedButton(
            onPressed: () {
              setState(() {
                _vrTours.removeWhere((v) => v['id'] == tour['id']);
                _totalVRTours = _vrTours.length;
              });

              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('VR tour deleted'),
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

  void _playVRTour(Map<String, dynamic> tour) async {
    // Increment view count
    setState(() {
      final index = _vrTours.indexWhere((v) => v['id'] == tour['id']);
      if (index != -1) {
        _vrTours[index]['views'] = (_vrTours[index]['views'] as int) + 1;
      }
    });

    final vrUrl = tour['vrUrl'] as String?;
    if (vrUrl != null && vrUrl.isNotEmpty) {
      final url = Uri.parse(vrUrl);
      if (await canLaunchUrl(url)) {
        await launchUrl(url);
      } else {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Could not open VR tour'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No VR URL available'),
          backgroundColor: Colors.orange,
        ),
      );
    }
  }

  // ==================== ANALYTICS (LGU-scoped) ====================
  Widget _buildAnalyticsContent() {
    final subtitle = _municipalityName != null
        ? '$_municipalityName — insights from your check-ins and registered visitors'
        : 'Insights from loaded check-ins and visitors (sign in with a municipality account to scope data)';

    return RefreshIndicator(
      onRefresh: _loadData,
      color: _primaryOrange,
      child: Container(
        color: _darkBg,
        child: Column(
          children: [
            _buildHeader(
              'Analytics',
              subtitle: subtitle,
            ),
            Expanded(
              child: SingleChildScrollView(
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
          ],
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
      childAspectRatio: 1.5,
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
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _cardBg,
        borderRadius: BorderRadius.circular(28),
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
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          Text(
            label,
            style: const TextStyle(color: _textMuted, fontSize: 12),
            textAlign: TextAlign.center,
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
        border: Border.all(color: _cardBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Visitor trends',
            style: TextStyle(
              color: _textDark,
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Check-ins per day (last 14 days)',
            style: TextStyle(color: _textMuted, fontSize: 12),
          ),
          const SizedBox(height: 16),
          SizedBox(
            height: 200,
            child: CustomPaint(
              size: const Size(double.infinity, 200),
              painter: _TourismAnalyticsChartPainter(
                color: _primaryOrange,
                values: values,
              ),
            ),
          ),
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
        border: Border.all(color: _cardBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Most visited spots',
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
  Widget _buildReportsContent() {
    return RefreshIndicator(
      onRefresh: _loadData,
      color: _primaryOrange,
      child: Container(
        margin: EdgeInsets.all(_isMobile ? 12 : 24),
        decoration: BoxDecoration(
          color: const Color(0xFFFFFBF5),
          borderRadius: BorderRadius.circular(36),
          border: Border.all(color: _primaryOrange, width: 1.5),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(34),
          child: Container(
            color: const Color(0xFFF7F0E8),
            child: Column(
              children: [
                _buildHeader(
                  'Reports',
                  subtitle:
                      'Check-in stats use your selected date range only (e.g. March 1–31). Use Custom for a full month.',
                ),
                Expanded(
                  child: SingleChildScrollView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: EdgeInsets.all(_isMobile ? 16 : 24),
                    child: Column(
                      children: [
                        _buildQuickReports(),
                        const SizedBox(height: 24),
                        _buildCustomReportGenerator(),
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

  Widget _buildQuickReports() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(26),
        border: Border.all(color: _cardBorder, width: 1.5),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.06),
            blurRadius: 14,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 10),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: _primaryOrange.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const Icon(
                    Icons.folder_open_rounded,
                    color: _primaryOrange,
                    size: 26,
                  ),
                ),
                const SizedBox(width: 14),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Quick export documents',
                        style: TextStyle(
                          color: _textDark,
                          fontSize: 17,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.2,
                        ),
                      ),
                      SizedBox(height: 6),
                      Text(
                        'Preset date windows — opens the same formatted report as “Preview”.',
                        style: TextStyle(
                          color: _textMuted,
                          fontSize: 12,
                          height: 1.4,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Divider(height: 1, color: Colors.grey.shade200),
          _buildQuickReportDocumentRow(
            title: 'Daily Report',
            subtitle: "Today's activity snapshot (check-ins filtered to today)",
            icon: Icons.today_rounded,
            accent: Colors.blue,
            type: 'daily',
          ),
          Divider(height: 1, indent: 16, endIndent: 16, color: Colors.grey.shade200),
          _buildQuickReportDocumentRow(
            title: 'Weekly Report',
            subtitle: 'Last 7 days including today',
            icon: Icons.date_range_rounded,
            accent: Colors.orange,
            type: 'weekly',
          ),
          Divider(height: 1, indent: 16, endIndent: 16, color: Colors.grey.shade200),
          _buildQuickReportDocumentRow(
            title: 'Monthly Report',
            subtitle: 'From the 1st of this month through today',
            icon: Icons.calendar_month_rounded,
            accent: _primaryOrange,
            type: 'monthly',
          ),
          Divider(height: 1, indent: 16, endIndent: 16, color: Colors.grey.shade200),
          _buildQuickReportDocumentRow(
            title: 'Annual Report',
            subtitle: 'Year-to-date from January 1 through today',
            icon: Icons.calendar_today_rounded,
            accent: Colors.purple,
            type: 'annual',
          ),
          const SizedBox(height: 8),
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
    final btn = OutlinedButton.icon(
      onPressed: () => _generateQuickReport(type),
      icon: Icon(Icons.download_rounded, size: 18, color: accent),
      label: Text(
        'Download',
        style: TextStyle(
          color: accent,
          fontWeight: FontWeight.w600,
        ),
      ),
      style: OutlinedButton.styleFrom(
        foregroundColor: accent,
        side: BorderSide(color: accent.withOpacity(0.45)),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
      ),
    );

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => _generateQuickReport(type),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: _isMobile
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: accent.withOpacity(0.12),
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: Icon(icon, color: accent, size: 24),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                title,
                                style: const TextStyle(
                                  color: _textDark,
                                  fontSize: 15,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                subtitle,
                                style: const TextStyle(
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
                    const SizedBox(height: 10),
                    Align(
                      alignment: Alignment.centerRight,
                      child: btn,
                    ),
                  ],
                )
              : Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: accent.withOpacity(0.12),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Icon(icon, color: accent, size: 24),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            title,
                            style: const TextStyle(
                              color: _textDark,
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            subtitle,
                            style: const TextStyle(
                              color: _textMuted,
                              fontSize: 12,
                              height: 1.35,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    btn,
                  ],
                ),
        ),
      ),
    );
  }

  Widget _buildCustomReportGenerator() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: _cardBg,
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: _cardBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Generate Custom Report',
            style: TextStyle(
              color: _textDark,
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 20),
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
        const SizedBox(height: 16),
        _buildDatePicker(
          'End Date',
          _reportEndDate,
          (date) => setState(() => _reportEndDate = date),
        ),
        const SizedBox(height: 16),
        _buildReportTypeDropdown(),
        const SizedBox(height: 16),
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
                : const Icon(Icons.download, size: 18),
            label: Text(_isExporting ? 'Generating...' : 'Generate'),
            style: ElevatedButton.styleFrom(
              backgroundColor: _primaryOrange,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildCustomReportDesktop() {
    return Row(
      children: [
        Expanded(
          child: _buildDatePicker(
            'Start Date',
            _reportStartDate,
            (date) => setState(() => _reportStartDate = date),
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: _buildDatePicker(
            'End Date',
            _reportEndDate,
            (date) => setState(() => _reportEndDate = date),
          ),
        ),
        const SizedBox(width: 16),
        Expanded(child: _buildReportTypeDropdown()),
        const SizedBox(width: 16),
        Padding(
          padding: const EdgeInsets.only(top: 24),
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
                : const Icon(Icons.download, size: 18),
            label: Text(_isExporting ? 'Generating...' : 'Generate'),
            style: ElevatedButton.styleFrom(
              backgroundColor: _primaryOrange,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildDatePicker(
    String label,
    DateTime? selectedDate,
    ValueChanged<DateTime> onSelect,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: TextStyle(color: _textMuted, fontSize: 12)),
        const SizedBox(height: 8),
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
                      dayStyle: const TextStyle(
                        color: _textDark,
                        fontSize: 14,
                      ),
                      dayForegroundColor: WidgetStateProperty.resolveWith((Set<WidgetState> states) {
                        if (states.contains(WidgetState.selected)) return Colors.white;
                        return null;
                      }),
                      dayBackgroundColor: WidgetStateProperty.resolveWith((Set<WidgetState> states) {
                        if (states.contains(WidgetState.selected)) return _primaryOrange;
                        return null;
                      }),
                      todayForegroundColor: WidgetStateProperty.resolveWith((Set<WidgetState> states) {
                        return _primaryOrange;
                      }),
                      todayBackgroundColor: WidgetStateProperty.resolveWith((Set<WidgetState> states) {
                        return null;
                      }),
                      todayBorder: const BorderSide(color: _primaryOrange, width: 2),
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
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: Colors.grey.shade300),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.05),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  selectedDate != null
                      ? _formatDateDisplay(selectedDate)
                      : 'Select date',
                  style: TextStyle(
                    color: selectedDate != null ? _textDark : _textMuted,
                    fontSize: selectedDate != null ? 15 : 14,
                    fontWeight: selectedDate != null ? FontWeight.w600 : FontWeight.normal,
                  ),
                ),
                Icon(
                  Icons.calendar_today_rounded,
                  color: _primaryOrange,
                  size: 20,
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
      children: [
        Text('Report Type', style: TextStyle(color: _textMuted, fontSize: 12)),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          decoration: BoxDecoration(
            color: Colors.grey.shade200,
            borderRadius: BorderRadius.circular(16),
          ),
          child: DropdownButton<String>(
            value: _reportType,
            isExpanded: true,
            dropdownColor: Colors.white,
            underline: const SizedBox(),
            style: TextStyle(color: _textDark, fontSize: 14),
            icon: Icon(Icons.keyboard_arrow_down, color: _textMuted),
            items: _reportTypes
                .map((t) => DropdownMenuItem(
                      value: t,
                      child: Text(
                        t,
                        style: TextStyle(color: _textDark, fontSize: 14),
                      ),
                    ))
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
    if (type == 'All Data' || type == 'Check-ins Only') {
      report += '--- CHECK-INS (within period) ---\n';
      report += 'Count in period: ${filteredCheckIns.length}\n';
      final verified = filteredCheckIns
          .where((c) => c['status'] == 'Verified')
          .length;
      final pending =
          filteredCheckIns.where((c) => c['status'] == 'Pending').length;
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
        content: Text('${period.capitalize()} report generated (${filteredCheckIns.length} check-ins in period)'),
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

  void _showGlobalSearchDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: _cardBg,
        title: const Text('Search', style: TextStyle(color: Colors.white)),
        content: SizedBox(
          width: 400,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: _globalSearchController,
                autofocus: true,
                decoration: InputDecoration(
                  hintText: 'Search tourists, spots, check-ins...',
                  hintStyle: TextStyle(color: _textMuted),
                  prefixIcon: Icon(Icons.search, color: _textMuted),
                  filled: true,
                  fillColor: Colors.white.withOpacity(0.05),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: BorderSide.none,
                  ),
                ),
                style: const TextStyle(color: Colors.white),
                onSubmitted: (value) {
                  Navigator.pop(context);
                  _performGlobalSearch(value);
                },
              ),
              const SizedBox(height: 16),
              Text(
                'Press Enter to search across all data',
                style: TextStyle(color: _textMuted, fontSize: 12),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel', style: TextStyle(color: _textMuted)),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              _performGlobalSearch(_globalSearchController.text);
            },
            style: ElevatedButton.styleFrom(backgroundColor: _primaryOrange),
            child: const Text('Search'),
          ),
        ],
      ),
    );
  }

  void _performGlobalSearch(String query) {
    if (query.isEmpty) return;

    final lowerQuery = query.toLowerCase();

    // Search in tourists
    final matchingTourists = _tourists
        .where(
          (t) =>
              (t['name']?.toString() ?? '').toLowerCase().contains(
                lowerQuery,
              ) ||
              (t['id']?.toString() ?? '').toLowerCase().contains(lowerQuery),
        )
        .toList();

    // Search in spots
    final matchingSpots = _touristSpots
        .where(
          (s) =>
              s.name.toLowerCase().contains(lowerQuery) ||
              s.municipality.toLowerCase().contains(lowerQuery),
        )
        .toList();

    // Search in check-ins
    final matchingCheckIns = _checkIns
        .where(
          (c) =>
              (c['touristName']?.toString() ?? '').toLowerCase().contains(
                lowerQuery,
              ) ||
              (c['location']?.toString() ?? '').toLowerCase().contains(
                lowerQuery,
              ),
        )
        .toList();

    // Show results
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: _cardBg,
        title: Text(
          'Search Results for "$query"',
          style: const TextStyle(color: Colors.white),
        ),
        content: SizedBox(
          width: 400,
          height: 400,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (matchingTourists.isNotEmpty) ...[
                  Text(
                    'Tourists (${matchingTourists.length})',
                    style: const TextStyle(
                      color: _primaryOrange,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 8),
                  ...matchingTourists
                      .take(5)
                      .map(
                        (t) => ListTile(
                          leading: const Icon(Icons.person, color: Colors.blue),
                          title: Text(
                            t['name'],
                            style: const TextStyle(color: Colors.white),
                          ),
                          subtitle: Text(
                            t['id'],
                            style: TextStyle(color: _textMuted),
                          ),
                          onTap: () {
                            Navigator.pop(context);
                            setState(() => _selectedIndex = 4);
                            _touristsSearchController.text = query;
                          },
                        ),
                      ),
                  const Divider(color: Colors.white24),
                ],
                if (matchingSpots.isNotEmpty) ...[
                  Text(
                    'Tourist Spots (${matchingSpots.length})',
                    style: const TextStyle(
                      color: _primaryOrange,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 8),
                  ...matchingSpots
                      .take(5)
                      .map(
                        (s) => ListTile(
                          leading: const Icon(
                            Icons.place,
                            color: Colors.orange,
                          ),
                          title: Text(
                            s.name,
                            style: const TextStyle(color: Colors.white),
                          ),
                          subtitle: Text(
                            s.municipality,
                            style: TextStyle(color: _textMuted),
                          ),
                          onTap: () {
                            Navigator.pop(context);
                            setState(() => _selectedIndex = 2);
                            _spotsSearchController.text = query;
                          },
                        ),
                      ),
                  const Divider(color: Colors.white24),
                ],
                if (matchingCheckIns.isNotEmpty) ...[
                  Text(
                    'Check-ins (${matchingCheckIns.length})',
                    style: const TextStyle(
                      color: _primaryOrange,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 8),
                  ...matchingCheckIns
                      .take(5)
                      .map(
                        (c) => ListTile(
                          leading: const Icon(
                            Icons.qr_code_scanner,
                            color: _primaryOrange,
                          ),
                          title: Text(
                            c['touristName'],
                            style: const TextStyle(color: Colors.white),
                          ),
                          subtitle: Text(
                            c['location'],
                            style: TextStyle(color: _textMuted),
                          ),
                          onTap: () {
                            Navigator.pop(context);
                            setState(() => _selectedIndex = 1);
                            _checkInsSearchController.text = query;
                          },
                        ),
                      ),
                ],
                if (matchingTourists.isEmpty &&
                    matchingSpots.isEmpty &&
                    matchingCheckIns.isEmpty)
                  const Center(
                    child: Text(
                      'No results found',
                      style: TextStyle(color: _textMuted),
                    ),
                  ),
              ],
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

  // --- Profile (header + sidebar; same pattern as governor dashboard) ---
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

  Widget _buildHeaderProfileChip() {
    return Tooltip(
      message: _profileName,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(32),
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
                  ),
                  overflow: TextOverflow.ellipsis,
                  maxLines: 1,
                ),
                const SizedBox(height: 2),
                Text(
                  'Tourism',
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

  // ==================== SETTINGS (aligned with governor) ====================
  Widget _buildSettingsContent() {
    return Container(
      color: _darkBg,
      child: Column(
        children: [
          _buildHeader(
            'Settings',
            subtitle: 'System configuration and preferences',
            showHeaderProfile: true,
          ),
          Expanded(
            child: SingleChildScrollView(
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
          ),
        ],
      ),
    );
  }

  Widget _buildTourismSettingsSection(String title, List<Widget> children) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: _cardBg,
        borderRadius: BorderRadius.circular(28),
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

  Widget _buildTourismSettingsTile(String title, IconData icon, VoidCallback onTap) {
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
                child: const Text('Cancel', style: TextStyle(color: _textMuted)),
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
              'Tourists Data (CSV)',
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

  Widget _buildTourismExportOption(String title, IconData icon, VoidCallback onTap) {
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

/// Line chart for LGU analytics (same visual language as Governor analytics).
class _TourismAnalyticsChartPainter extends CustomPainter {
  _TourismAnalyticsChartPainter({
    required this.color,
    this.values = const [],
  });

  final Color color;
  final List<double> values;

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

    final maxVal = values.isEmpty
        ? 1.0
        : values.reduce((a, b) => a > b ? a : b).clamp(1.0, double.infinity);
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

class _NavItem {
  final IconData icon;
  final String label;
  _NavItem({required this.icon, required this.label});
}

class _StatCard {
  final String title;
  final String value;
  final String change;
  final IconData icon;
  final Color color;
  final bool? isPositiveOverride;
  _StatCard({
    required this.title,
    required this.value,
    required this.change,
    required this.icon,
    required this.color,
    this.isPositiveOverride,
  });
}

extension StringExtension on String {
  String capitalize() {
    return '${this[0].toUpperCase()}${substring(1)}';
  }
}

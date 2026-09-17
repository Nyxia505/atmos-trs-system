import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:atmos_trs_system/config/auth_config.dart';
import 'package:atmos_trs_system/config/session_storage.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:async' show StreamSubscription, unawaited;
import 'dart:io' show Platform;
import 'dart:typed_data';
import 'package:image_picker/image_picker.dart';
import 'package:atmos_trs_system/widgets/ui_skeleton.dart';
import 'package:atmos_trs_system/services/dashboard_stats_cache.dart';
import 'package:atmos_trs_system/widgets/app_search_bar.dart';
import 'package:atmos_trs_system/data/misamis_occidental_municipalities.dart';
import 'package:atmos_trs_system/widgets/report_export_preview.dart';
import 'package:atmos_trs_system/utils/municipality_helper.dart';
import 'package:atmos_trs_system/utils/tourist_id_helper.dart';
import 'package:atmos_trs_system/navigation/post_logout_navigation.dart';
import 'package:atmos_trs_system/widgets/app_logout_button.dart';
import 'package:atmos_trs_system/services/announcement_push_service.dart';
import 'package:atmos_trs_system/services/lgu_event_service.dart';
import 'package:atmos_trs_system/services/governor_firestore_service.dart';
import 'package:atmos_trs_system/widgets/spot_image.dart';
import 'package:atmos_trs_system/services/user_directory_service.dart';
import 'package:atmos_trs_system/services/auth_service.dart';
import 'package:atmos_trs_system/services/tourist_account_admin_service.dart';
import 'package:atmos_trs_system/utils/checkin_visitor_count.dart';
import 'package:atmos_trs_system/utils/production_data_filters.dart';
import 'package:atmos_trs_system/utils/provincial_report_builder.dart';
import 'package:atmos_trs_system/utils/checkin_report_summary_csv.dart';
import 'package:atmos_trs_system/utils/dot_var2_visitor_record_report.dart';
import 'package:atmos_trs_system/utils/csv_file_download.dart';
import 'package:atmos_trs_system/utils/xlsx_file_download.dart';
import 'package:atmos_trs_system/widgets/dot_report_export_panel.dart';
import 'package:atmos_trs_system/features/governor/theme/governor_dashboard_tokens.dart';
import 'package:atmos_trs_system/features/governor/widgets/governor_sidebar.dart';
import 'package:atmos_trs_system/features/governor/widgets/governor_glass_header.dart';
import 'package:atmos_trs_system/features/governor/widgets/governor_kpi_card.dart';
import 'package:atmos_trs_system/features/governor/widgets/governor_quick_actions.dart';
import 'package:atmos_trs_system/features/governor/widgets/governor_chart_card.dart';
import 'package:atmos_trs_system/features/governor/widgets/governor_city_ranking_list.dart';
import 'package:atmos_trs_system/features/governor/widgets/charts/governor_arrivals_area_chart.dart';
import 'package:atmos_trs_system/features/governor/widgets/charts/governor_donut_chart.dart';
import 'package:atmos_trs_system/features/governor/widgets/charts/governor_age_bar_chart.dart';

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

  // Data states — staged loading for smooth post-login paint
  bool _isBootstrapping = true;
  bool _isLoadingDetails = true;
  bool _hasCachedStats = false;
  String? _errorMessage;
  int _totalTourists = 0;
  int _totalCheckIns = 0;

  /// Unique tourists who checked in today (one person = 1 even if they checked in at multiple municipalities).
  int _uniqueTouristsToday = 0;
  /// Unique tourists who checked in anywhere in Misamis Occidental (visit-based).
  int _provinceUniqueVisitors = 0;
  int _activeSpots = 0;
  String _selectedTimeFilter = 'This Month';
  /// Municipalities page chart: This Week / This Month / This Year.
  String _muniChartTimeFilter = 'This Year';
  final _searchController = TextEditingController();

  /// Registered Tourists page: All | Day | Month | Year (by registration date).
  String _touristRegFilterMode = 'All';
  DateTime _touristRegFilterAnchor = DateTime.now();

  // Premium analytics palette (concept match)
  static const Color _primaryOrange = GovernorDashboardTokens.primaryDark;
  static const Color _accentOrange = GovernorDashboardTokens.primary;
  static const Color _lightOrange = Color(0xFFFED7AA);
  static const Color _darkBg = GovernorDashboardTokens.background;
  static const Color _cardBg = GovernorDashboardTokens.card;
  static const Color _sidebarBg = GovernorDashboardTokens.card;
  static const Color _sidebarHover = Color(0xFFF1F5F9);
  static const Color _textDark = GovernorDashboardTokens.text;
  static const Color _textMuted = GovernorDashboardTokens.subtitle;
  static const Color _cardBorder = GovernorDashboardTokens.border;

  static const Color _kpiOrange = GovernorDashboardTokens.primary;
  static const Color _kpiPeach = Color(0xFFFB923C);
  static const Color _kpiBlue = Color(0xFF3B82F6);
  static const Color _kpiPurple = Color(0xFFA855F7);

  final List<_NavItem> _navItems = [
    _NavItem(icon: Icons.dashboard_rounded, label: 'Dashboard'),
    _NavItem(icon: Icons.people_alt_rounded, label: 'Registered Tourists'),
    _NavItem(icon: Icons.location_city_rounded, label: 'Municipalities'),
    _NavItem(icon: Icons.analytics_rounded, label: 'Analytics'),
    _NavItem(icon: Icons.settings_rounded, label: 'Settings'),
  ];

  static const int _municipalitiesIndex = 2;
  static const int _analyticsIndex = 3;
  static const int _settingsIndex = 4;
  /// Events are not in the sidebar — opened from the header notification bell.
  static const int _eventsIndex = 5;
  /// Bottom nav shows Dashboard → Settings (index 0–4).
  static const int _bottomNavItemCount = 5;

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
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>?
      _announcementsSubscription;
  bool _announcementsStreamPrimed = false;
  final Set<String> _seenGovernorEventIds = {};
  final Set<String> _dismissedGovernorNotificationIds = {};
  Set<String> _knownPublishedAnnouncementIds = {};

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
  String _reportType = 'All Data';
  DateTime? _reportStartDate;
  DateTime? _reportEndDate;

  static const List<String> _reportTypes = [
    'All Data',
    'Visits only',
    'Tourists Only',
    'Tourist Spots Only',
    'Summary by Municipality',
    'DOT Visitor to Attraction Report',
    'DOT Tourism Attraction Visitor Record (VAR 2)',
  ];

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 250),
    );
    _animationController.forward();
    unawaited(_loadSettings());
    unawaited(_restoreGovernorStatsCache().then((_) => _loadData()));
    _startAnnouncementsListener();
  }

  /// Live LGU event publications → badge + snackbar (no approval queue).
  void _startAnnouncementsListener() {
    if (Firebase.apps.isEmpty) return;
    _announcementsSubscription?.cancel();
    _announcementsStreamPrimed = false;
    _knownPublishedAnnouncementIds = {};
    unawaited(_loadSeenGovernorEventIds());
    _announcementsSubscription = FirebaseFirestore.instance
        .collection(LguEventService.collection)
        .snapshots()
        .listen(
      (snapshot) async {
        if (!mounted) return;
        final list = snapshot.docs
            .map((d) => <String, dynamic>{'id': d.id, ...d.data()})
            .toList();
        list.sort(_sortAnnouncementsForGovernor);

        final wasPrimed = _announcementsStreamPrimed;
        final previousPublished =
            Set<String>.from(_knownPublishedAnnouncementIds);

        final publishedIds = <String>{
          for (final a in list)
            if (LguEventService.isVisibleToTourists(a) &&
                (a['id']?.toString() ?? '').isNotEmpty)
              a['id'].toString(),
        };

        setState(() {
          _announcements = list;
          _knownPublishedAnnouncementIds = publishedIds;
        });

        if (!wasPrimed) {
          _announcementsStreamPrimed = true;
          // Do not mark existing live events as read — the bell should list them.
          if (mounted) setState(() {});
          return;
        }

        final newlyPublished = <Map<String, dynamic>>[];
        for (final a in list) {
          if (!LguEventService.isVisibleToTourists(a)) continue;
          final id = a['id']?.toString() ?? '';
          if (id.isEmpty || previousPublished.contains(id)) continue;
          newlyPublished.add(a);
        }

        if (newlyPublished.isEmpty) return;

        final first = newlyPublished.first;
        final mun = LguEventService.sourceMunicipalityLabel(first);
        final title = first['title']?.toString().trim() ?? 'event';
        final count = newlyPublished.length;
        final message = count == 1
            ? '$mun published "$title"'
            : '$count new LGU events published';

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
                _openEventsPage(markSeen: false);
              },
            ),
          ),
        );
      },
      onError: (Object e) {
        debugPrint('[GovernorDashboard] announcements stream: $e');
      },
    );
  }

  static int _sortAnnouncementsForGovernor(
    Map<String, dynamic> a,
    Map<String, dynamic> b,
  ) {
    final aTs = a['publishedAt'] ?? a['createdAt'];
    final bTs = b['publishedAt'] ?? b['createdAt'];
    if (aTs is Timestamp && bTs is Timestamp) {
      return bTs.compareTo(aTs);
    }
    return (b['date']?.toString() ?? '').compareTo(a['date']?.toString() ?? '');
  }

  int get _pendingLguEventsCount {
    var n = 0;
    for (final a in _announcements) {
      if (!LguEventService.isVisibleToTourists(a)) continue;
      final id = a['id']?.toString() ?? '';
      if (id.isEmpty) continue;
      if (_dismissedGovernorNotificationIds.contains(id)) continue;
      if (!_seenGovernorEventIds.contains(id)) n++;
    }
    return n > 99 ? 99 : n;
  }

  /// Live LGU events shown in the notification bell panel.
  List<Map<String, dynamic>> get _notificationFeedAnnouncements {
    final live = _announcements.where((a) {
      if (!LguEventService.isVisibleToTourists(a)) return false;
      final id = a['id']?.toString() ?? '';
      if (id.isEmpty) return false;
      return !_dismissedGovernorNotificationIds.contains(id);
    }).toList()
      ..sort(_sortAnnouncementsForGovernor);
    if (live.length <= 40) return live;
    return live.take(40).toList();
  }

  bool _isGovernorEventUnread(Map<String, dynamic> a) {
    final id = a['id']?.toString() ?? '';
    return id.isNotEmpty &&
        !_dismissedGovernorNotificationIds.contains(id) &&
        !_seenGovernorEventIds.contains(id);
  }

  Future<void> _loadSeenGovernorEventIds() async {
    final prefs = await SharedPreferences.getInstance();
    // Old seed / auto-read cleared the unread badge even with live LGU events.
    // Reset once so unread + Mark all as read work again.
    if (!(prefs.getBool('governor_notif_seen_v3') ?? false)) {
      await prefs.remove('governor_events_seen');
      await prefs.remove('governor_events_seeded');
      await prefs.setBool('governor_notif_seen_v3', true);
    }
    final stored = prefs.getStringList('governor_events_seen') ?? [];
    final dismissed = prefs.getStringList('governor_events_dismissed') ?? [];
    _seenGovernorEventIds
      ..clear()
      ..addAll(stored);
    _dismissedGovernorNotificationIds
      ..clear()
      ..addAll(dismissed);
  }

  Future<void> _persistGovernorNotificationPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(
      'governor_events_seen',
      _seenGovernorEventIds.toList(),
    );
    await prefs.setStringList(
      'governor_events_dismissed',
      _dismissedGovernorNotificationIds.toList(),
    );
  }

  Future<void> _markGovernorEventRead(String eventId) async {
    final id = eventId.trim();
    if (id.isEmpty) return;
    if (_seenGovernorEventIds.contains(id)) return;
    _seenGovernorEventIds.add(id);
    await _persistGovernorNotificationPrefs();
    if (mounted) setState(() {});
  }

  Future<void> _markAllGovernorEventsSeen() async {
    for (final a in _announcements) {
      if (!LguEventService.isVisibleToTourists(a)) continue;
      final id = a['id']?.toString() ?? '';
      if (id.isEmpty) continue;
      if (_dismissedGovernorNotificationIds.contains(id)) continue;
      _seenGovernorEventIds.add(id);
    }
    await _persistGovernorNotificationPrefs();
    if (mounted) setState(() {});
  }

  Future<void> _dismissGovernorNotification(String eventId) async {
    final id = eventId.trim();
    if (id.isEmpty) return;
    _dismissedGovernorNotificationIds.add(id);
    _seenGovernorEventIds.add(id);
    await _persistGovernorNotificationPrefs();
    if (mounted) setState(() {});
  }

  Future<void> _restoreGovernorStatsCache() async {
    final cached = await DashboardStatsCache.loadGovernor();
    if (cached == null || !mounted) return;
    setState(() {
      _totalTourists = cached.totalTourists;
      _totalCheckIns = cached.totalCheckIns;
      _uniqueTouristsToday = cached.uniqueTouristsToday;
      _activeSpots = cached.activeSpots;
      if (cached.profileName != null && cached.profileName!.isNotEmpty) {
        _profileName = cached.profileName!;
      }
      _hasCachedStats = true;
    });
  }

  Future<void> _saveGovernorStatsCache() async {
    await DashboardStatsCache.saveGovernor(
      GovernorDashboardStatsCache(
        totalTourists: _totalTourists,
        totalCheckIns: _totalCheckIns,
        uniqueTouristsToday: _uniqueTouristsToday,
        activeSpots: _activeSpots,
        profileName: _profileName,
      ),
    );
  }

  void _applyGovernorSnapshotStats(GovernorFirestoreSnapshot snapshot) {
    _tourists = _uniqueRegisteredTourists(
      ProductionDataFilters.realTourists(snapshot.tourists),
    );
    _checkIns = ProductionDataFilters.realCheckIns(snapshot.checkIns);
    _governorAllSpots = snapshot.touristSpots;
    _announcements = List<Map<String, dynamic>>.from(snapshot.announcements)
      ..sort(_sortAnnouncementsForGovernor);

    // Unique registered people (one row per tourist), not visit/check-in counts.
    _totalTourists = _tourists.length;
    _totalCheckIns = sumCheckInVisitors(_checkIns);

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
    _activeSpots = _governorAllSpots.length;

    _applyMunicipalityVisitStatsFromCheckIns();
  }

  /// Visit-based LGU stats from check-ins only (not registration home city).
  /// Province unique ≠ sum of LGU uniques (multi-city visitors counted once province-wide).
  void _applyMunicipalityVisitStatsFromCheckIns() {
    _resetMunicipalityTouristCounts();

    final provinceUsers = <String>{};
    final byMuniUsers = <String, Set<String>>{
      for (final m in getMisamisOccidentalMunicipalities())
        normalizeMunicipalityId(m.id): <String>{},
    };
    final byMuniCheckIns = <String, int>{
      for (final m in getMisamisOccidentalMunicipalities())
        normalizeMunicipalityId(m.id): 0,
    };
    final idToCanonicalName = <String, String>{
      for (final m in getMisamisOccidentalMunicipalities())
        normalizeMunicipalityId(m.id): m.name,
    };

    for (final c in _checkIns) {
      final id = _checkInMunicipalityId(c);
      if (id.isEmpty || !byMuniUsers.containsKey(id)) continue;

      byMuniCheckIns[id] =
          (byMuniCheckIns[id] ?? 0) + checkInVisitorCount(c);
      final uid = GovernorFirestoreService.checkInUserId(c);
      if (uid.isNotEmpty) {
        provinceUsers.add(uid);
        byMuniUsers[id]!.add(uid);
      }
    }

    _provinceUniqueVisitors = provinceUsers.length;

    for (final muni in _allMunicipalities) {
      final name = muni['name']?.toString() ?? '';
      var mid = normalizeMunicipalityId(getMunicipalityIdFromName(name));
      if (mid.isEmpty || !byMuniUsers.containsKey(mid)) {
        // Fallback: match display name to canonical list.
        for (final e in idToCanonicalName.entries) {
          if (e.value.toLowerCase() == name.toLowerCase()) {
            mid = e.key;
            break;
          }
        }
      }
      if (mid.isEmpty || !byMuniUsers.containsKey(mid)) continue;

      final unique = byMuniUsers[mid]!.length;
      final checks = byMuniCheckIns[mid] ?? 0;
      muni['id'] = mid;
      muni['uniqueVisitors'] = unique;
      muni['checkIns'] = checks;
      // Kept for dashboard city ranking / legacy reads — means unique visitors.
      muni['tourists'] = unique;
    }
  }

  Widget _buildSidebarAvatar({required double size}) {
    if (_profilePhotoBytes != null) {
      return Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white.withOpacity(0.9), width: 2),
        ),
        child: ClipOval(
          child: Image.memory(_profilePhotoBytes!, fit: BoxFit.cover),
        ),
      );
    }

    // Profile chip only — ATMOS logo stays on the sidebar brand mark.
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: const Color(0xFFFFF7ED),
        border: Border.all(color: _primaryOrange.withOpacity(0.35), width: 1.5),
      ),
      child: Icon(
        Icons.person_rounded,
        size: size * 0.55,
        color: _primaryOrange,
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
    _announcementsSubscription?.cancel();
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

  /// Canonical Misamis Occidental municipality id from a check-in row.
  String _checkInMunicipalityId(Map<String, dynamic> c) {
    final mid = normalizeMunicipalityId(c['municipalityId']?.toString());
    if (mid.isNotEmpty && isMisamisOccidentalMunicipalityId(mid)) return mid;
    return normalizeMunicipalityId(
      getMunicipalityIdFromName(
        c['municipality']?.toString() ?? c['city']?.toString(),
      ),
    );
  }

  void _resetMunicipalityTouristCounts() {
    for (final muni in _allMunicipalities) {
      muni['tourists'] = 0;
      muni['uniqueVisitors'] = 0;
      muni['checkIns'] = 0;
    }
    _provinceUniqueVisitors = 0;
  }

  Future<void> _loadData() async {
    final isRefresh = !_isBootstrapping;
    if (isRefresh) {
      setState(() => _isLoadingDetails = true);
    }
    setState(() => _errorMessage = null);

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
              'Sign in required to load provincial data from the database.';
          _isBootstrapping = false;
          _isLoadingDetails = false;
        });
        return;
      }

      await authUser.getIdToken();
      final email = authUser.email ?? '';
      if (!UserDirectoryService.isProvincialStaffEmail(email)) {
        if (!mounted) return;
        setState(() {
          _errorMessage =
              'This page is for the provincial governor account only. '
              'Sign in with ${SessionStorage.governorEmail} or use the tourist app.';
          _isBootstrapping = false;
          _isLoadingDetails = false;
        });
        return;
      }

      final staffReady =
          await UserDirectoryService.prepareProvincialStaffFirestoreAccess(
        uid: authUser.uid,
        email: email,
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
          _isBootstrapping = false;
          _isLoadingDetails = false;
        });
        return;
      }

      final service = GovernorFirestoreService();

      // Phase 1: quick stats (spots + tourists, no heavy check-ins)
      var quickSnapshot = await service.loadProvincialSnapshot(
        getOptions: const GetOptions(source: Source.cache),
        includeCheckIns: false,
      );
      if (quickSnapshot.tourists.isEmpty &&
          quickSnapshot.touristSpots.isEmpty) {
        quickSnapshot = await service.loadProvincialSnapshot(
          getOptions: const GetOptions(source: Source.server),
          includeCheckIns: false,
        );
      }
      _applyGovernorSnapshotStats(quickSnapshot);

      if (mounted) {
        setState(() => _isBootstrapping = false);
        unawaited(_saveGovernorStatsCache());
      }

      // Phase 2: full server snapshot with check-ins (charts / analytics)
      final fullSnapshot = await service.loadProvincialSnapshot(
        getOptions: const GetOptions(source: Source.server),
        includeCheckIns: true,
      );
      _applyGovernorSnapshotStats(fullSnapshot);

      final profile = await UserDirectoryService.getProfileByUid(
        authUser.uid,
        preferServer: false,
      );
      if (profile != null) {
        final name = profile.fullName?.trim() ?? '';
        if (name.isNotEmpty) {
          _profileName = name;
        }
        _profileEmail = profile.email.isNotEmpty
            ? profile.email
            : (authUser.email ?? _profileEmail);
      }

      if (!mounted) return;
      setState(() {
        _errorMessage = fullSnapshot.loadWarnings.isNotEmpty
            ? fullSnapshot.loadWarnings.first
            : null;
        _isLoadingDetails = false;
      });
      unawaited(_saveGovernorStatsCache());

      if (fullSnapshot.loadWarnings.length > 1 && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(fullSnapshot.loadWarnings.join(' ')),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      debugPrint('Error loading governor data: $e');
      if (!mounted) return;
      setState(() {
        _errorMessage = 'Could not load database: $e';
        _isBootstrapping = false;
        _isLoadingDetails = false;
      });
    } finally {
      if (mounted && _isBootstrapping) {
        setState(() {
          _isBootstrapping = false;
          _isLoadingDetails = false;
        });
      }
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
    return GovernorSidebar(
      asDrawer: true,
      expanded: true,
      selectedIndex:
          _selectedIndex < _navItems.length ? _selectedIndex : -1,
      items: _governorSidebarItems,
      onSelect: (index) {
        setState(() => _selectedIndex = index);
        Navigator.of(context).maybePop();
      },
      onToggle: () => Navigator.of(context).maybePop(),
      onLogout: _logout,
      showBrandLogo: true,
      profileName:
          _profileName.trim().isNotEmpty ? _profileName.trim() : 'Governor',
      avatar: _buildSidebarAvatar(size: 36),
    );
  }

  List<GovernorNavItemData> get _governorSidebarItems => [
        for (var i = 0; i < _navItems.length; i++)
          GovernorNavItemData(
            label: _navItems[i].label,
            icon: _navItems[i].icon,
            // Event alerts live on the header notification bell only.
            badgeCount: 0,
          ),
      ];

  Widget _buildBottomNav() {
    const Color bottomNavSelectedBg = Color(0xFFFFF7ED);
    const Color bottomNavSelectedFg = Color(0xFFC2410C);
    const Color bottomNavUnselected = Color(0xFF64748B);
    return Material(
      color: GovernorDashboardTokens.card,
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
                    children: List.generate(_bottomNavItemCount, (
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
                                border: isSelected
                                    ? Border.all(
                                        color: bottomNavSelectedFg
                                            .withValues(alpha: 0.2),
                                      )
                                    : null,
                              ),
                              child: SizedBox(
                                width: 76,
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Stack(
                                      clipBehavior: Clip.none,
                                      children: [
                                        Icon(
                                          item.icon,
                                          color: isSelected
                                              ? bottomNavSelectedFg
                                              : bottomNavUnselected,
                                          size: 22,
                                        ),
                                      ],
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
    return GovernorSidebar(
      expanded: _isSidebarExpanded,
      selectedIndex:
          _selectedIndex < _navItems.length ? _selectedIndex : -1,
      items: _governorSidebarItems,
      onSelect: (index) => setState(() => _selectedIndex = index),
      onToggle: _toggleSidebar,
      onLogout: _logout,
      showBrandLogo: true,
      profileName:
          _profileName.trim().isNotEmpty ? _profileName.trim() : 'Governor',
      avatar: _buildSidebarAvatar(size: 36),
    );
  }

  Widget _buildSidebarCollapsedToggle() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 14, 12, 6),
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

  Widget _buildSidebarProfileStrip({bool showCollapseButton = false}) {
    final displayName =
        _profileName.trim().isNotEmpty ? _profileName.trim() : 'Governor';

    return Padding(
      padding: EdgeInsets.fromLTRB(16, _isMobile ? 10 : 14, 8, 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          _buildSidebarAvatar(size: _isMobile ? 36 : 40),
          const SizedBox(width: 10),
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
                const SizedBox(height: 2),
                Text(
                  'Misamis Occidental',
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
            const SizedBox(width: 4),
            _buildSidebarToggleButton(expanded: true),
          ],
        ],
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
                  Stack(
                    clipBehavior: Clip.none,
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
                    ],
                  ),
                  if (expanded) ...[
                    const SizedBox(width: 14),
                    Expanded(
                      child: Text(
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

  Widget _buildMainContent() {
    // Events opens from the notification bell only (not in the sidebar).
    if (_selectedIndex == _eventsIndex) {
      return _buildAnnouncementsContent();
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

    if (_isBootstrapping && !_hasCachedStats) {
      return DashboardContentSkeleton(accent: _primaryOrange);
    }

    final content = switch (_selectedIndex) {
      0 => _buildDashboardContent(),
      1 => _buildTouristsContent(),
      _municipalitiesIndex => _buildMunicipalitiesContent(),
      _analyticsIndex => _buildAnalyticsContent(),
      _settingsIndex => _buildSettingsContent(),
      _ => _buildDashboardContent(),
    };

    if (_selectedIndex == 0 && (!_isBootstrapping || _hasCachedStats)) {
      return DashboardFadeIn(child: content);
    }
    return content;
  }

  /// Close the notifications dialog (if any), then open the full Events page.
  void _openEventsPage({bool markSeen = true}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      setState(() => _selectedIndex = _eventsIndex);
      if (markSeen) unawaited(_markAllGovernorEventsSeen());
    });
  }

  Widget _buildHeader(
    String title, {
    String? subtitle,
    List<Widget>? actions,
    bool compact = false,
  }) {
    final greetingName =
        _profileName.trim().isNotEmpty ? _profileName.trim() : 'Governor';
    final isDashboard = _selectedIndex == 0;
    final headerTitle = isDashboard ? greetingName : title;
    final headerGreeting = isDashboard
        ? '${GovernorDashboardTokens.greetingEmoji()} ${GovernorDashboardTokens.greetingForNow()},'
        : null;
    final headerSubtitle = isDashboard
        ? (subtitle ??
            'Misamis Occidental - Provincial Tourism Overview')
        : subtitle;

    return GovernorGlassHeader(
      greeting: headerGreeting,
      title: headerTitle,
      subtitle: headerSubtitle,
      compact: compact,
      showConceptMeta: isDashboard,
      searchController: _searchController,
      notificationCount: _unreadNotificationCount,
      onNotifications: _showNotificationsPanel,
      leading: _isMobile
          ? Builder(
              builder: (ctx) => IconButton(
                tooltip: 'Menu',
                onPressed: () => Scaffold.of(ctx).openDrawer(),
                icon: const Icon(Icons.menu_rounded, size: 20),
                color: Colors.white,
              ),
            )
          : null,
      profile: _isMobile
          ? _buildMobileHeaderProfileAction()
          : _buildHeaderProfile(),
    );
  }

  int get _unreadNotificationCount {
    final count = _pendingLguEventsCount;
    return count > 99 ? 99 : count;
  }

  void _showNotificationsPanel() {
    showDialog(
      context: context,
      barrierColor: Colors.black54,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            final feed = _notificationFeedAnnouncements;
            final unread = _pendingLguEventsCount;

            Future<void> deleteOne(String id) async {
              await _dismissGovernorNotification(id);
              if (mounted) setDialogState(() {});
            }

            Future<void> markOneRead(String id) async {
              await _markGovernorEventRead(id);
              if (mounted) setDialogState(() {});
            }

            Future<void> markAllRead() async {
              await _markAllGovernorEventsSeen();
              if (mounted) setDialogState(() {});
            }

            return Center(
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
                      Padding(
                        padding: const EdgeInsets.fromLTRB(20, 20, 8, 16),
                        child: Row(
                          children: [
                            const Expanded(
                              child: Text(
                                'Notifications',
                                style: TextStyle(
                                  color: _textDark,
                                  fontSize: 18,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                            if (unread > 0)
                              Container(
                                margin: const EdgeInsets.only(right: 6),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 4,
                                ),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFEF4444),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Text(
                                  '$unread',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                            if (unread > 0)
                              TextButton(
                                onPressed: () => unawaited(markAllRead()),
                                style: TextButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 10,
                                  ),
                                  minimumSize: Size.zero,
                                  tapTargetSize:
                                      MaterialTapTargetSize.shrinkWrap,
                                ),
                                child: const Text(
                                  'Mark all as read',
                                  style: TextStyle(
                                    color: _primaryOrange,
                                    fontWeight: FontWeight.w600,
                                    fontSize: 13,
                                  ),
                                ),
                              ),
                            IconButton(
                              icon: const Icon(
                                Icons.close_rounded,
                                color: _textMuted,
                                size: 22,
                              ),
                              onPressed: () =>
                                  Navigator.pop(dialogContext),
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
                      Flexible(
                        child: feed.isEmpty
                            ? const Padding(
                                padding: EdgeInsets.symmetric(vertical: 48),
                                child: Center(
                                  child: Text(
                                    'No notifications',
                                    style: TextStyle(
                                      color: _textMuted,
                                      fontSize: 14,
                                    ),
                                  ),
                                ),
                              )
                            : ListView.separated(
                                shrinkWrap: true,
                                padding:
                                    const EdgeInsets.symmetric(vertical: 8),
                                itemCount: feed.length,
                                separatorBuilder: (_, __) => Divider(
                                  height: 1,
                                  color: Colors.grey.shade200,
                                ),
                                itemBuilder: (context, i) {
                                  final a = feed[i];
                                  final id = a['id']?.toString() ?? '';
                                  final type =
                                      a['type']?.toString() ?? 'General';
                                  final mun =
                                      LguEventService.sourceMunicipalityLabel(
                                    a,
                                  );
                                  final isUnread = _isGovernorEventUnread(a);
                                  IconData icon = Icons.campaign_rounded;
                                  if (type == 'Promo') {
                                    icon = Icons.local_offer_rounded;
                                  } else if (type == 'Event') {
                                    icon = Icons.event_rounded;
                                  } else if (type == 'Alert') {
                                    icon = Icons.warning_amber_rounded;
                                  }
                                  return ListTile(
                                    contentPadding:
                                        const EdgeInsets.fromLTRB(
                                      20,
                                      4,
                                      8,
                                      4,
                                    ),
                                    leading: CircleAvatar(
                                      radius: 20,
                                      backgroundColor:
                                          _primaryOrange.withOpacity(0.15),
                                      child: Icon(
                                        icon,
                                        color: _primaryOrange,
                                        size: 20,
                                      ),
                                    ),
                                    title: Text(
                                      a['title']?.toString() ?? 'Event',
                                      style: TextStyle(
                                        color: _textDark,
                                        fontWeight: isUnread
                                            ? FontWeight.w700
                                            : FontWeight.w600,
                                        fontSize: 14,
                                      ),
                                    ),
                                    subtitle: Padding(
                                      padding: const EdgeInsets.only(top: 4),
                                      child: Text(
                                        [
                                          if (mun.isNotEmpty) 'From $mun',
                                          'Live',
                                          a['content']
                                                  ?.toString()
                                                  .replaceAll('\n', ' ')
                                                  .trim() ??
                                              '',
                                        ]
                                            .where((s) => s.isNotEmpty)
                                            .join(' · '),
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                          color: _textMuted,
                                          fontSize: 12,
                                          height: 1.35,
                                        ),
                                      ),
                                    ),
                                    trailing: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        if (isUnread)
                                          Container(
                                            margin: const EdgeInsets.only(
                                              right: 4,
                                            ),
                                            padding:
                                                const EdgeInsets.symmetric(
                                              horizontal: 8,
                                              vertical: 4,
                                            ),
                                            decoration: BoxDecoration(
                                              color: const Color(0xFFFFF7ED),
                                              borderRadius:
                                                  BorderRadius.circular(8),
                                            ),
                                            child: const Text(
                                              'New',
                                              style: TextStyle(
                                                color: Color(0xFFD97706),
                                                fontSize: 11,
                                                fontWeight: FontWeight.w700,
                                              ),
                                            ),
                                          ),
                                        IconButton(
                                          tooltip: 'Delete notification',
                                          icon: const Icon(
                                            Icons.delete_outline_rounded,
                                            color: Color(0xFFEF4444),
                                            size: 22,
                                          ),
                                          onPressed: id.isEmpty
                                              ? null
                                              : () =>
                                                  unawaited(deleteOne(id)),
                                        ),
                                      ],
                                    ),
                                    onTap: id.isEmpty || !isUnread
                                        ? null
                                        : () => unawaited(markOneRead(id)),
                                  );
                                },
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
                    color: Color(0xFFEF4444),
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
        padding: const EdgeInsets.fromLTRB(10, 8, 8, 8),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.06),
              blurRadius: 10,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildSidebarAvatar(size: 34),
            const SizedBox(width: 10),
            Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _profileName.trim().isNotEmpty ? _profileName.trim() : 'Governor',
                  style: const TextStyle(
                    color: _textDark,
                    fontSize: 13.5,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.1,
                  ),
                  overflow: TextOverflow.ellipsis,
                  maxLines: 1,
                ),
                const SizedBox(height: 1),
                Text(
                  'Misamis Occidental',
                  style: TextStyle(
                    color: _textMuted,
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
            const SizedBox(width: 4),
            Icon(
              Icons.keyboard_arrow_down_rounded,
              size: 20,
              color: _textMuted,
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
                  setState(() => _selectedIndex = _settingsIndex);
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
      color: _accentOrange,
      child: _buildDashboardCanvas(
        child: Column(
          children: [
            _buildHeader(
              'Welcome back, Governor',
              subtitle: 'Misamis Occidental · Provincial Tourism Overview',
              compact: _dashboardOnePage,
            ),
            Expanded(
              child: LayoutBuilder(
                builder: (context, viewport) {
                  final body = _dashboardOnePage
                      ? SizedBox(
                          height: viewport.maxHeight,
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                _buildStatsGrid(),
                                const SizedBox(height: 12),
                                GovernorQuickActions(
                                  onAddMunicipality: () => setState(
                                    () =>
                                        _selectedIndex = _municipalitiesIndex,
                                  ),
                                  onExportReport: () => setState(
                                    () => _selectedIndex = _analyticsIndex,
                                  ),
                                  onViewAnalytics: () => setState(
                                    () => _selectedIndex = _analyticsIndex,
                                  ),
                                ),
                                const SizedBox(height: 12),
                                Expanded(
                                  child: _isLoadingDetails
                                      ? const DashboardChartsSkeleton(
                                          height: double.infinity,
                                        )
                                      : DashboardFadeIn(
                                          child: _buildDashboardOnePageCharts(),
                                        ),
                                ),
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
                              const SizedBox(height: 16),
                              GovernorQuickActions(
                                onAddMunicipality: () => setState(
                                  () => _selectedIndex = _municipalitiesIndex,
                                ),
                                onExportReport: () => setState(
                                  () => _selectedIndex = _analyticsIndex,
                                ),
                                onViewAnalytics: () => setState(
                                  () => _selectedIndex = _analyticsIndex,
                                ),
                              ),
                              const SizedBox(height: 20),
                              if (_isLoadingDetails) ...[
                                const DashboardChartsSkeleton(height: 220),
                                const SizedBox(height: 20),
                                const ShimmerScope(
                                  child: SkeletonListTiles(count: 2),
                                ),
                              ] else
                                DashboardFadeIn(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      _buildChartsSection(),
                                      const SizedBox(height: 16),
                                      _buildVisitorDemographicsSection(),
                                    ],
                                  ),
                                ),
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
              const SizedBox(width: 12),
              Expanded(flex: 2, child: _buildTopCategoriesCard(dense: true)),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Expanded(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(child: _buildGenderPieChart(dense: true)),
              const SizedBox(width: 12),
              Expanded(child: _buildAgeRangeBarChart(dense: true)),
              const SizedBox(width: 12),
              Expanded(child: _buildLocalForeignPieChart(dense: true)),
              const SizedBox(width: 12),
              Expanded(child: _buildCityRankingBarChart(dense: true)),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildStatsGrid() {
    if (_isBootstrapping && !_hasCachedStats) {
      if (_dashboardOnePage) {
        return const SizedBox(
          height: 96,
          child: ShimmerScope(child: SkeletonStatCardsRow(count: 4)),
        );
      }
      final crossCount = _gridCrossAxisCount;
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

    final checkInTrend = _checkInsTrendText;
    final touristSpark = _statSparklineValues(
      _StatCard(
        title: 'Registered Tourists',
        value: _formatNumber(_totalTourists),
        icon: Icons.people_alt_rounded,
        color: _kpiOrange,
      ),
    );
    final todaySpark = _statSparklineValues(
      _StatCard(
        title: 'Tourists Today',
        value: _formatNumber(_uniqueTouristsToday),
        icon: Icons.qr_code_scanner_rounded,
        color: _kpiPeach,
      ),
    );
    final checkInSpark = _statSparklineValues(
      _StatCard(
        title: 'Total Check-ins',
        value: _formatNumber(_totalCheckIns),
        icon: Icons.touch_app_rounded,
        color: _kpiBlue,
      ),
    );
    final spotsSpark = _statSparklineValues(
      _StatCard(
        title: 'Active Spots',
        value: '$_activeSpots',
        icon: Icons.location_on_rounded,
        color: _kpiPurple,
      ),
    );

    String growthFromSpark(List<double> values) {
      if (values.length < 2) return '—';
      final first = values.first;
      final last = values.last;
      if (first <= 0) return last > 0 ? '100%' : '0%';
      final pct = ((last - first) / first) * 100;
      if (pct.abs() < 0.05) return '0%';
      return '${pct.abs().toStringAsFixed(0)}%';
    }

    bool positiveFromSpark(List<double> values) {
      if (values.length < 2) return true;
      return values.last >= values.first;
    }

    String stripTrendSign(String text) {
      return text.replaceFirst(RegExp(r'^[+\-]'), '');
    }

    final kpiCards = [
      GovernorKpiCard(
        title: 'Registered Tourists',
        value: _formatNumber(_totalTourists),
        icon: Icons.people_alt_rounded,
        accent: _kpiOrange,
        changeText: growthFromSpark(touristSpark),
        isPositive: positiveFromSpark(touristSpark),
        trendHint: 'vs last month',
        sparkline: touristSpark,
        compact: _dashboardOnePage,
      ),
      GovernorKpiCard(
        title: 'Tourists Today',
        value: _formatNumber(_uniqueTouristsToday),
        icon: Icons.qr_code_scanner_rounded,
        accent: _kpiPeach,
        changeText: growthFromSpark(todaySpark),
        isPositive: positiveFromSpark(todaySpark),
        trendHint: 'vs yesterday',
        sparkline: todaySpark,
        compact: _dashboardOnePage,
      ),
      GovernorKpiCard(
        title: 'Total Check-ins',
        value: _formatNumber(_totalCheckIns),
        icon: Icons.touch_app_rounded,
        accent: _kpiBlue,
        changeText: stripTrendSign(checkInTrend.text),
        isPositive: checkInTrend.isPositive,
        trendHint: 'vs last week',
        sparkline: checkInSpark,
        compact: _dashboardOnePage,
      ),
      GovernorKpiCard(
        title: 'Active Spots',
        value: '$_activeSpots',
        icon: Icons.location_on_rounded,
        accent: _kpiPurple,
        changeText: growthFromSpark(spotsSpark),
        isPositive: positiveFromSpark(spotsSpark),
        trendHint: 'vs last month',
        sparkline: spotsSpark,
        compact: _dashboardOnePage,
      ),
    ];

    if (_dashboardOnePage) {
      return DashboardFadeIn(
        child: SizedBox(
          height: 108,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var i = 0; i < kpiCards.length; i++) ...[
                if (i > 0) const SizedBox(width: 12),
                Expanded(child: kpiCards[i]),
              ],
            ],
          ),
        ),
      );
    }

    return DashboardFadeIn(
      child: GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: _gridCrossAxisCount,
        crossAxisSpacing: 16,
        mainAxisSpacing: 16,
        childAspectRatio: _isMobile ? 2.2 : 2.6,
      ),
      itemCount: kpiCards.length,
      itemBuilder: (context, index) => kpiCards[index],
    ),
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
    final chart = GovernorChartCard(
      dense: dense,
      title: 'Gender',
      icon: Icons.people_alt_rounded,
      child: GovernorDonutChart(
        dense: dense,
        centerLabel: total > 0 ? '$total' : null,
        emptyMessage: 'No gender data yet',
        segments: [
          GovernorDonutSegment(
            label: 'Male',
            value: (counts['Male'] ?? 0).toDouble(),
            color: GovernorDashboardTokens.genderMale,
          ),
          GovernorDonutSegment(
            label: 'Female',
            value: (counts['Female'] ?? 0).toDouble(),
            color: GovernorDashboardTokens.genderFemale,
          ),
          GovernorDonutSegment(
            label: 'Others',
            value: (counts['Others'] ?? 0).toDouble(),
            color: GovernorDashboardTokens.genderOther,
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
    final chart = GovernorChartCard(
      dense: dense,
      title: 'Local vs Foreign',
      icon: Icons.public_rounded,
      child: GovernorDonutChart(
        dense: dense,
        centerLabel: total > 0 ? '$total' : null,
        emptyMessage: 'No local/foreign data yet',
        segments: [
          GovernorDonutSegment(
            label: 'Local',
            value: (counts['Local'] ?? 0).toDouble(),
            color: GovernorDashboardTokens.localVisitor,
          ),
          GovernorDonutSegment(
            label: 'Foreign',
            value: (counts['Foreign'] ?? 0).toDouble(),
            color: GovernorDashboardTokens.foreignVisitor,
          ),
        ],
      ),
    );
    if (dense) return chart;
    return SizedBox(height: _isMobile ? 260 : 300, child: chart);
  }

  Widget _buildAgeRangeBarChart({bool dense = false}) {
    final series = _ageGenderSeries;
    final chart = GovernorChartCard(
      dense: dense,
      title: 'Age Range',
      icon: Icons.calendar_view_month_rounded,
      child: GovernorAgeBarChart(series: series, dense: dense),
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
            color: _textDark,
            fontSize: 11,
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }

  Widget _buildCityRankingBarChart({bool dense = false}) {
    final cities = _cityRankingData;
    final chart = GovernorChartCard(
      dense: dense,
      title: 'City Ranking',
      icon: Icons.emoji_events_rounded,
      child: GovernorCityRankingList(cities: cities, dense: dense),
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
          SizedBox(height: 280, child: _buildTouristArrivalsChart()),
          const SizedBox(height: 16),
          SizedBox(height: 280, child: _buildTopCategoriesCard()),
        ],
      );
    }
    return SizedBox(
      height: 320,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(flex: 2, child: _buildTouristArrivalsChart()),
          const SizedBox(width: 16),
          Expanded(child: _buildTopCategoriesCard()),
        ],
      ),
    );
  }

  Widget _buildTouristArrivalsChart({bool dense = false}) {
    return GovernorChartCard(
      dense: dense,
      title: 'Tourist Arrivals',
      icon: Icons.show_chart_rounded,
      trailing: _buildTimeFilterDropdown(dense: dense),
      child: GovernorArrivalsAreaChart(values: _dashboardTrendValues),
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
    final totalCount = stats.fold<int>(
      0,
      (a, s) => a + ((s['count'] as num?)?.toInt() ?? 0),
    );
    final segments = <GovernorDonutSegment>[
      for (var i = 0; i < stats.length; i++)
        GovernorDonutSegment(
          label: stats[i]['name'] as String,
          value: ((stats[i]['count'] as num?)?.toDouble() ?? 0),
          color: GovernorDashboardTokens.categoryPalette[
              i % GovernorDashboardTokens.categoryPalette.length],
        ),
    ];
    return GovernorChartCard(
      dense: dense,
      title: 'Top Categories',
      icon: Icons.donut_large_rounded,
      trailing: TextButton(
        onPressed: () =>
            setState(() => _selectedIndex = _analyticsIndex),
        style: TextButton.styleFrom(
          foregroundColor: GovernorDashboardTokens.primary,
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
      child: GovernorDonutChart(
        dense: dense,
        centerLabel: totalCount > 0 ? '100%\nTotal' : null,
        emptyMessage: 'No category data yet',
        segments: segments,
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
    final unique =
        (municipality['uniqueVisitors'] as num?)?.toInt() ??
        (municipality['tourists'] as num?)?.toInt() ??
        0;
    final checkIns = (municipality['checkIns'] as num?)?.toInt() ?? 0;
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
            _detailRow('Type', municipality['type']?.toString() ?? '—'),
            _detailRow('Unique visitors', '$unique'),
            _detailRow('Total check-ins', '$checkIns'),
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
  /// One row per registered person (by Firebase uid / tourist id).
  List<Map<String, dynamic>> _uniqueRegisteredTourists(
    List<Map<String, dynamic>> rows,
  ) {
    final seen = <String>{};
    final out = <Map<String, dynamic>>[];
    for (final t in rows) {
      final uid = TouristAccountAdminService.resolveTouristUid(t)?.trim() ?? '';
      final touristId = TouristIdHelper.displayForTourist(t).trim();
      final key = uid.isNotEmpty
          ? 'uid:$uid'
          : (touristId.isNotEmpty && touristId != 'MO-PENDING'
                ? 'tid:$touristId'
                : '');
      if (key.isEmpty) continue;
      if (!seen.add(key)) continue;
      out.add(t);
    }
    return out;
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

  static const _monthNames = <String>[
    'January',
    'February',
    'March',
    'April',
    'May',
    'June',
    'July',
    'August',
    'September',
    'October',
    'November',
    'December',
  ];

  String get _touristRegFilterLabel {
    final a = _touristRegFilterAnchor;
    switch (_touristRegFilterMode) {
      case 'Day':
        return _formatRegisteredDateOnly(a);
      case 'Month':
        return '${_monthNames[a.month - 1]} ${a.year}';
      case 'Year':
        return '${a.year}';
      default:
        return 'All time';
    }
  }

  bool _matchesTouristRegDateFilter(Map<String, dynamic> t) {
    if (_touristRegFilterMode == 'All') return true;
    final dt = _registeredDateTimeFromTourist(t);
    if (dt == null) return false;
    final a = _touristRegFilterAnchor;
    switch (_touristRegFilterMode) {
      case 'Day':
        return dt.year == a.year && dt.month == a.month && dt.day == a.day;
      case 'Month':
        return dt.year == a.year && dt.month == a.month;
      case 'Year':
        return dt.year == a.year;
      default:
        return true;
    }
  }

  bool _matchesTouristSearch(Map<String, dynamic> t, String query) {
    if (query.isEmpty) return true;
    final id = TouristIdHelper.displayForTourist(t).toLowerCase();
    final touristIdField = t['touristId']?.toString().toLowerCase() ?? '';
    final origin = _getTouristOrigin(t).toLowerCase();
    final city = t['city']?.toString().toLowerCase() ?? '';
    final country = t['country']?.toString().toLowerCase() ?? '';
    final originField = t['origin']?.toString().toLowerCase() ?? '';
    final dt = _registeredDateTimeFromTourist(t);
    final dateStr = _formatRegisteredDateOnly(dt).toLowerCase();
    final timeStr = _formatRegisteredTimeOnly(dt).toLowerCase();
    return id.contains(query) ||
        touristIdField.contains(query) ||
        origin.contains(query) ||
        city.contains(query) ||
        country.contains(query) ||
        originField.contains(query) ||
        dateStr.contains(query) ||
        timeStr.contains(query);
  }

  List<Map<String, dynamic>> _filteredRegisteredTourists() {
    final query = _searchController.text.trim().toLowerCase();
    return _tourists
        .where(
          (t) => _matchesTouristRegDateFilter(t) && _matchesTouristSearch(t, query),
        )
        .toList(growable: false);
  }

  Future<void> _pickTouristRegFilterDate() async {
    final now = DateTime.now();
    final firstDate = DateTime(2020);
    final lastDate = DateTime(now.year + 1, 12, 31);

    if (_touristRegFilterMode == 'Year') {
      final years = <int>[
        for (var y = now.year; y >= 2020; y--) y,
      ];
      final picked = await showDialog<int>(
        context: context,
        builder: (ctx) => SimpleDialog(
          title: const Text('Select year'),
          children: [
            for (final y in years)
              SimpleDialogOption(
                onPressed: () => Navigator.pop(ctx, y),
                child: Text(
                  '$y',
                  style: TextStyle(
                    fontWeight: y == _touristRegFilterAnchor.year
                        ? FontWeight.w700
                        : FontWeight.w500,
                    color: y == _touristRegFilterAnchor.year
                        ? _primaryOrange
                        : _textDark,
                  ),
                ),
              ),
          ],
        ),
      );
      if (picked != null && mounted) {
        setState(() {
          _touristRegFilterAnchor = DateTime(picked);
        });
      }
      return;
    }

    if (_touristRegFilterMode == 'Month') {
      final picked = await showDatePicker(
        context: context,
        initialDate: _touristRegFilterAnchor,
        firstDate: firstDate,
        lastDate: lastDate,
        helpText: 'Select month',
        initialDatePickerMode: DatePickerMode.year,
      );
      if (picked != null && mounted) {
        setState(() {
          _touristRegFilterAnchor = DateTime(picked.year, picked.month);
        });
      }
      return;
    }

    // Day
    final picked = await showDatePicker(
      context: context,
      initialDate: _touristRegFilterAnchor,
      firstDate: firstDate,
      lastDate: lastDate,
      helpText: 'Select registration day',
    );
    if (picked != null && mounted) {
      setState(() {
        _touristRegFilterAnchor = picked;
      });
    }
  }

  Widget _buildTouristsContent() {
    final filteredTourists = _filteredRegisteredTourists();

    return Container(
      color: _darkBg,
      child: Column(
        children: [
          _buildHeader(
            'Registered Tourists',
            subtitle:
                'Unique registrations — names hidden for data privacy',
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
                  const SizedBox(height: 10),
                  _buildTouristRegDateFilterBar(),
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
                            child: _buildSearchBar(
                              'Search by Tourist ID, origin, or date...',
                            ),
                          ),
                          const Divider(height: 1, color: _cardBorder),
                          Expanded(
                            child: filteredTourists.isEmpty
                                ? _buildEmptyState(
                                    'No registered tourists match your filters',
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

  Widget _buildTouristRegDateFilterBar() {
    Widget modeChip(String mode) {
      final selected = _touristRegFilterMode == mode;
      return FilterChip(
        label: Text(mode),
        selected: selected,
        onSelected: (_) {
          setState(() {
            _touristRegFilterMode = mode;
            if (mode != 'All') {
              _touristRegFilterAnchor = DateTime.now();
            }
          });
        },
        selectedColor: _primaryOrange.withOpacity(0.18),
        checkmarkColor: _primaryOrange,
        labelStyle: TextStyle(
          color: selected ? _primaryOrange : _textDark,
          fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
          fontSize: 12,
        ),
        side: BorderSide(
          color: selected ? _primaryOrange.withOpacity(0.45) : _cardBorder,
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
        border: Border.all(color: _cardBorder),
      ),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          const Text(
            'Filter by registration:',
            style: TextStyle(
              color: _textMuted,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
          modeChip('All'),
          modeChip('Day'),
          modeChip('Month'),
          modeChip('Year'),
          if (_touristRegFilterMode != 'All')
            OutlinedButton.icon(
              onPressed: _pickTouristRegFilterDate,
              icon: const Icon(Icons.calendar_today_rounded, size: 14),
              label: Text(_touristRegFilterLabel),
              style: OutlinedButton.styleFrom(
                foregroundColor: _primaryOrange,
                side: BorderSide(color: _primaryOrange.withOpacity(0.4)),
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                textStyle: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
                visualDensity: VisualDensity.compact,
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildTouristsSummaryBar(int visibleCount) {
    final periodHint = _touristRegFilterMode == 'All'
        ? 'all time'
        : _touristRegFilterLabel;
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
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '$visibleCount of ${_tourists.length} registered tourists',
                  style: const TextStyle(
                    color: _textDark,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  'Unique people · $periodHint',
                  style: const TextStyle(color: _textMuted, fontSize: 11),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: _kpiOrange.withOpacity(0.15),
              borderRadius: BorderRadius.circular(20),
            ),
            child: const Text(
              'Privacy on',
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

  List<Map<String, dynamic>> _sortedTouristsByRegistrationDate(
    List<Map<String, dynamic>> tourists,
  ) {
    final sorted = List<Map<String, dynamic>>.from(tourists)
      ..sort((a, b) {
        final aDt = _registeredDateTimeFromTourist(a);
        final bDt = _registeredDateTimeFromTourist(b);
        if (aDt == null && bDt == null) return 0;
        if (aDt == null) return 1; // missing dates last
        if (bDt == null) return -1;
        return bDt.compareTo(aDt); // newest registration first
      });
    return sorted;
  }

  /// Generic avatar — no photo / name initials (privacy).
  Widget _touristPrivacyAvatar({double radius = 18}) {
    return CircleAvatar(
      radius: radius,
      backgroundColor: _primaryOrange.withOpacity(0.12),
      child: Icon(
        Icons.person_outline_rounded,
        color: _primaryOrange,
        size: radius * 1.1,
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
    final sorted = _sortedTouristsByRegistrationDate(tourists);

    return ListView.separated(
      padding: const EdgeInsets.all(12),
      itemCount: sorted.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        final t = sorted[index];
        final id = TouristIdHelper.displayForTourist(t);
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
                  _touristPrivacyAvatar(),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          id,
                          style: const TextStyle(
                            color: _textDark,
                            fontWeight: FontWeight.w700,
                            fontSize: 14,
                            fontFamily: 'monospace',
                          ),
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
                  _touristViewButton(
                    onPressed: () => _showTouristDetails(t),
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
    final sorted = _sortedTouristsByRegistrationDate(tourists);

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
              headerCell('Tourist ID', flex: 2.4),
              headerCell(
                'Origin',
                flex: 2.4,
                padding: const EdgeInsets.only(left: 4),
              ),
              headerCell('Date', flex: 1.2),
              headerCell('Time', flex: 1.2),
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
                final id = TouristIdHelper.displayForTourist(t);
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
                            flex: 24,
                            child: Row(
                              children: [
                                _touristPrivacyAvatar(radius: 16),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Align(
                                    alignment: Alignment.centerLeft,
                                    child: _touristIdChip(id, maxWidth: 220),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Expanded(
                            flex: 24,
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
                            flex: 12,
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
                            flex: 12,
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
    final id = TouristIdHelper.displayForTourist(tourist);
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: _cardBg,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            _touristPrivacyAvatar(radius: 22),
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
                    id,
                    style: const TextStyle(
                      color: _textDark,
                      fontWeight: FontWeight.w700,
                      fontSize: 16,
                      fontFamily: 'monospace',
                    ),
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
            _detailRow('Tourist ID', id),
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
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Close', style: TextStyle(color: _textMuted)),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(dialogContext);
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
    final displayId = TouristIdHelper.displayForTourist(tourist);
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
          'This permanently removes tourist $displayId from ATMOS-TRS '
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
        return;
      }
    }

    try {
      final result =
          await TouristAccountAdminService.deleteTouristAccount(uid);
      if (!mounted) return;
      closeLoadingDialog();
      setState(() {
        _tourists = _uniqueRegisteredTourists(
          _tourists
              .where((t) {
                final id = TouristAccountAdminService.resolveTouristUid(t);
                return id != uid &&
                    !TouristAccountAdminService.isDeletedTouristRow(t);
              })
              .toList(growable: true),
        );
        _totalTourists = _tourists.length;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            result.authDeleted
                ? 'Deleted account for $displayId'
                : 'Removed $displayId from Registered Tourists.',
          ),
          backgroundColor: _primaryOrange,
        ),
      );
      // Light refresh only — avoid full bootstrap that can confuse navigation.
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

  // ==================== MUNICIPALITIES SECTION ====================

  String _shortMunicipalityChartLabel(String name) {
    var s = name.trim();
    s = s.replaceFirst(RegExp(r'\s+City$', caseSensitive: false), '');
    if (s.toLowerCase().startsWith('don victoriano')) return 'Don Vic.';
    if (s.toLowerCase() == 'sapang dalaga') return 'S. Dalaga';
    if (s.toLowerCase() == 'lopez jaena') return 'L. Jaena';
    if (s.length > 9) return '${s.substring(0, 8)}…';
    return s;
  }

  DateTime? get _muniChartPeriodStart {
    final now = DateTime.now();
    switch (_muniChartTimeFilter) {
      case 'This Week':
        final startOfWeek = now.subtract(Duration(days: now.weekday - 1));
        return DateTime(startOfWeek.year, startOfWeek.month, startOfWeek.day);
      case 'This Month':
        return DateTime(now.year, now.month, 1);
      case 'This Year':
        return DateTime(now.year, 1, 1);
      default:
        return null;
    }
  }

  /// Unique visitors per municipality for the municipalities chart (highest first).
  List<({String shortLabel, String fullName, double unique})>
      get _municipalityVisitChartSeries {
    final start = _muniChartPeriodStart;
    final byMuni = <String, Set<String>>{
      for (final m in getMisamisOccidentalMunicipalities())
        normalizeMunicipalityId(m.id): <String>{},
    };
    final names = <String, String>{
      for (final m in getMisamisOccidentalMunicipalities())
        normalizeMunicipalityId(m.id): m.name,
    };

    for (final c in _checkIns) {
      if (start != null) {
        final t = GovernorFirestoreService.parseCheckInTime(c);
        if (t == null || t.isBefore(start)) continue;
      }
      final id = _checkInMunicipalityId(c);
      if (id.isEmpty || !byMuni.containsKey(id)) continue;
      final uid = GovernorFirestoreService.checkInUserId(c);
      if (uid.isNotEmpty) byMuni[id]!.add(uid);
    }

    final rows = byMuni.entries
        .map((e) {
          final full = names[e.key] ?? e.key;
          return (
            shortLabel: _shortMunicipalityChartLabel(full),
            fullName: full,
            unique: e.value.length.toDouble(),
          );
        })
        .toList()
      ..sort((a, b) {
        final byUnique = b.unique.compareTo(a.unique);
        if (byUnique != 0) return byUnique;
        return a.fullName.compareTo(b.fullName);
      });
    return rows;
  }

  Widget _buildMuniChartTimeFilterDropdown({bool dense = false}) {
    return PopupMenuButton<String>(
      initialValue: _muniChartTimeFilter,
      onSelected: (value) => setState(() => _muniChartTimeFilter = value),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      itemBuilder: (context) => ['This Week', 'This Month', 'This Year']
          .map(
            (filter) => PopupMenuItem(
              value: filter,
              child: Text(
                filter,
                style: TextStyle(
                  fontWeight: filter == _muniChartTimeFilter
                      ? FontWeight.w700
                      : FontWeight.w500,
                  color: filter == _muniChartTimeFilter
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
              _muniChartTimeFilter,
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

  Widget _buildMunicipalityVisitorsChart() {
    final series = _municipalityVisitChartSeries;
    final values = series.map((e) => e.unique).toList(growable: false);
    final axisLabels =
        series.map((e) => e.shortLabel).toList(growable: false);
    final tooltipLabels =
        series.map((e) => e.fullName).toList(growable: false);

    final chartHeight = _isMobile ? 210.0 : 240.0;

    return SizedBox(
      height: chartHeight,
      child: GovernorChartCard(
        dense: _isMobile,
        title: 'Visitors by Municipality',
        icon: Icons.show_chart_rounded,
        trailing: _buildMuniChartTimeFilterDropdown(dense: _isMobile),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final minWidth = series.isEmpty ? constraints.maxWidth : series.length * 52.0;
            final chartWidth = constraints.maxWidth > minWidth
                ? constraints.maxWidth
                : minWidth;
            final chart = GovernorArrivalsAreaChart(
              values: values,
              labels: axisLabels,
              tooltipLabels: tooltipLabels,
              emptyMessage: 'No unique visitors in this period',
              valueNoun: 'unique visitors',
              rotateBottomLabels: true,
              showAllBottomLabels: true,
            );
            if (chartWidth <= constraints.maxWidth + 0.5) {
              return chart;
            }
            return Scrollbar(
              thumbVisibility: !_isMobile,
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: SizedBox(
                  width: chartWidth,
                  height: constraints.maxHeight,
                  child: chart,
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildMunicipalitiesContent() {
    final sorted = List<Map<String, dynamic>>.from(_allMunicipalities)
      ..sort((a, b) {
        final av = (a['uniqueVisitors'] as num?)?.toInt() ??
            (a['tourists'] as num?)?.toInt() ??
            0;
        final bv = (b['uniqueVisitors'] as num?)?.toInt() ??
            (b['tourists'] as num?)?.toInt() ??
            0;
        final byVisitors = bv.compareTo(av);
        if (byVisitors != 0) return byVisitors;
        return (a['name']?.toString() ?? '')
            .compareTo(b['name']?.toString() ?? '');
      });

    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Color(0xFFFFF7ED),
            Color(0xFFF8FAFC),
            Color(0xFFF1F5F9),
          ],
        ),
      ),
      child: Column(
        children: [
          _buildHeader(
            'Municipalities & Cities',
            subtitle:
                'Unique visitors by check-in location across Misamis Occidental',
          ),
          Expanded(
            child: Padding(
              padding: EdgeInsets.fromLTRB(
                _isMobile ? 14 : 20,
                _isMobile ? 8 : 12,
                _isMobile ? 14 : 20,
                _isMobile ? 14 : 20,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _buildMunicipalityProvinceVisitSummary(),
                  SizedBox(height: _isMobile ? 10 : 12),
                  _buildMunicipalityVisitorsChart(),
                  SizedBox(height: _isMobile ? 10 : 12),
                  Expanded(
                    child: _isMobile
                        ? _buildMunicipalitiesGridMobile(sorted)
                        : _buildMunicipalitiesGridDesktop(sorted),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMunicipalityProvinceVisitSummary() {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: _isMobile ? 14 : 18,
        vertical: _isMobile ? 14 : 16,
      ),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _cardBorder),
        boxShadow: [
          BoxShadow(
            color: _primaryOrange.withValues(alpha: 0.08),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: _isMobile ? 48 : 56,
            height: _isMobile ? 48 : 56,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  _primaryOrange.withValues(alpha: 0.22),
                  _accentOrange.withValues(alpha: 0.12),
                ],
              ),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(
              Icons.map_rounded,
              color: _primaryOrange,
              size: _isMobile ? 24 : 28,
            ),
          ),
          SizedBox(width: _isMobile ? 12 : 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Tourists who visited Misamis Occidental',
                  style: TextStyle(
                    color: _textMuted,
                    fontSize: _isMobile ? 12 : 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  _formatNumber(_provinceUniqueVisitors),
                  style: TextStyle(
                    color: _textDark,
                    fontSize: _isMobile ? 28 : 34,
                    fontWeight: FontWeight.w800,
                    height: 1.1,
                    letterSpacing: -0.5,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Unique visitors (1 person = 1, even across cities)',
                  style: TextStyle(
                    color: _textMuted,
                    fontSize: _isMobile ? 11 : 12,
                  ),
                ),
              ],
            ),
          ),
          Container(
            padding: EdgeInsets.symmetric(
              horizontal: _isMobile ? 10 : 14,
              vertical: _isMobile ? 8 : 10,
            ),
            decoration: BoxDecoration(
              color: const Color(0xFFF1F5F9),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: _cardBorder),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  'Total check-ins',
                  style: TextStyle(
                    color: _textMuted,
                    fontSize: _isMobile ? 10 : 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  _formatNumber(_totalCheckIns),
                  style: TextStyle(
                    color: _primaryOrange,
                    fontSize: _isMobile ? 18 : 22,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMunicipalitiesGridMobile(List<Map<String, dynamic>> municipalities) {
    return ListView.separated(
      itemCount: municipalities.length,
      separatorBuilder: (_, __) => const SizedBox(height: 12),
      itemBuilder: (context, index) =>
          _buildMunicipalityCard(municipalities[index], compact: false),
    );
  }

  Widget _buildMunicipalitiesGridDesktop(
    List<Map<String, dynamic>> municipalities,
  ) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final count = municipalities.length;
        // Fewer columns → larger cards that fill the viewport.
        final crossAxisCount = constraints.maxWidth >= 1400
            ? 4
            : constraints.maxWidth >= 1000
                ? 3
                : 2;
        final rows = (count / crossAxisCount).ceil().clamp(1, 20);
        const spacing = 14.0;
        final usableHeight = constraints.maxHeight;
        final usableWidth = constraints.maxWidth;
        // Expand cards to fill height (old max 88 left a huge empty gap).
        final itemHeight =
            ((usableHeight - spacing * (rows - 1)) / rows).clamp(96.0, 220.0);
        final itemWidth =
            (usableWidth - spacing * (crossAxisCount - 1)) / crossAxisCount;
        final aspectRatio = (itemWidth / itemHeight).clamp(1.6, 4.8);

        return GridView.builder(
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: crossAxisCount,
            crossAxisSpacing: spacing,
            mainAxisSpacing: spacing,
            childAspectRatio: aspectRatio,
          ),
          itemCount: count,
          itemBuilder: (context, index) => _buildMunicipalityCard(
            municipalities[index],
            compact: false,
          ),
        );
      },
    );
  }

  Widget _buildMunicipalityCard(
    Map<String, dynamic> municipality, {
    bool compact = false,
  }) {
    final name = municipality['name']?.toString() ?? 'Unknown';
    final type = municipality['type']?.toString() ?? 'Municipality';
    final uniqueVisitors = (municipality['uniqueVisitors'] as num?)?.toInt() ??
        (municipality['tourists'] as num?)?.toInt() ??
        0;
    final checkIns = (municipality['checkIns'] as num?)?.toInt() ?? 0;
    final isCity = type == 'City';
    final accent = isCity ? _accentOrange : _primaryOrange;

    return _MunicipalityHoverCard(
      onTap: () => _showMunicipalityDetails(municipality),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(compact ? 14 : 18),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Colors.white,
              accent.withValues(alpha: 0.04),
            ],
          ),
          border: Border.all(
            color: isCity
                ? accent.withValues(alpha: 0.32)
                : const Color(0xFFE2E8F0),
            width: isCity ? 1.4 : 1,
          ),
          boxShadow: [
            BoxShadow(
              color: accent.withValues(alpha: 0.08),
              blurRadius: 18,
              offset: const Offset(0, 8),
            ),
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 6,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Padding(
          padding: EdgeInsets.symmetric(
            horizontal: compact ? 12 : 16,
            vertical: compact ? 12 : 14,
          ),
          child: Row(
            children: [
              Container(
                width: compact ? 44 : 56,
                height: compact ? 44 : 56,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      accent.withValues(alpha: 0.22),
                      accent.withValues(alpha: 0.08),
                    ],
                  ),
                  borderRadius: BorderRadius.circular(compact ? 12 : 14),
                  border: Border.all(
                    color: accent.withValues(alpha: 0.2),
                  ),
                ),
                child: Icon(
                  isCity
                      ? Icons.apartment_rounded
                      : Icons.location_city_rounded,
                  color: accent,
                  size: compact ? 22 : 28,
                ),
              ),
              SizedBox(width: compact ? 10 : 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      name,
                      style: TextStyle(
                        color: _textDark,
                        fontSize: compact ? 16 : 18,
                        fontWeight: FontWeight.bold,
                        height: 1.2,
                        letterSpacing: -0.2,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    SizedBox(height: compact ? 6 : 8),
                    Row(
                      children: [
                        Container(
                          padding: EdgeInsets.symmetric(
                            horizontal: compact ? 8 : 10,
                            vertical: compact ? 3 : 4,
                          ),
                          decoration: BoxDecoration(
                            color: accent,
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(
                            type,
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: compact ? 10.5 : 11.5,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        SizedBox(width: compact ? 8 : 10),
                        Icon(
                          Icons.people_alt_rounded,
                          size: compact ? 14 : 16,
                          color: _textMuted,
                        ),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            '$uniqueVisitors unique visitor${uniqueVisitors == 1 ? '' : 's'}'
                            '${checkIns > 0 ? ' · $checkIns check-in${checkIns == 1 ? '' : 's'}' : ''}',
                            style: TextStyle(
                              color: _textMuted,
                              fontSize: compact ? 12 : 13,
                              fontWeight: FontWeight.w600,
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
              Container(
                width: compact ? 32 : 36,
                height: compact ? 32 : 36,
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.arrow_forward_rounded,
                  color: accent,
                  size: compact ? 16 : 18,
                ),
              ),
            ],
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
    return days > 0
        ? (sumCheckInVisitors(_checkIns) / days).round()
        : sumCheckInVisitors(_checkIns);
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
  /// Insights + provincial exports (moved from Reports).
  Widget _buildAnalyticsContent() {
    final pad = _isMobile ? 14.0 : 22.0;
    return RefreshIndicator(
      onRefresh: _loadData,
      color: _primaryOrange,
      child: Container(
        color: _darkBg,
        child: Column(
          children: [
            _buildHeader(
              'Analytics',
              subtitle:
                  'Insights and provincial exports for Misamis Occidental',
            ),
            Expanded(
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: EdgeInsets.fromLTRB(pad, 16, pad, pad + 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _buildAnalyticsSectionLabel(
                      'Key insights',
                      'Quick patterns from check-ins and registrations',
                      Icons.insights_rounded,
                    ),
                    const SizedBox(height: 12),
                    _buildAnalyticsCards(),
                    const SizedBox(height: 22),
                    _buildAnalyticsSectionLabel(
                      'Spot rankings',
                      'Most visited tourist spots by check-in volume',
                      Icons.emoji_events_outlined,
                    ),
                    const SizedBox(height: 12),
                    _buildTopSpotsChart(),
                    const SizedBox(height: 22),
                    _buildAnalyticsSectionLabel(
                      'Provincial exports',
                      'Download province-wide reports for all LGUs',
                      Icons.file_download_outlined,
                    ),
                    const SizedBox(height: 12),
                    LayoutBuilder(
                      builder: (context, constraints) {
                        final sideBySide = !_isMobile && constraints.maxWidth >= 980;
                        if (!sideBySide) {
                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              _buildGovernorQuickReports(),
                              const SizedBox(height: 14),
                              _buildGovernorCustomReportGenerator(),
                            ],
                          );
                        }
                        return Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(child: _buildGovernorQuickReports()),
                            const SizedBox(width: 14),
                            Expanded(child: _buildGovernorCustomReportGenerator()),
                          ],
                        );
                      },
                    ),
                    const SizedBox(height: 22),
                    _buildAnalyticsSectionLabel(
                      'DOT templates (provincial)',
                      'Official forms from Supabase — filled for all LGUs',
                      Icons.description_outlined,
                    ),
                    const SizedBox(height: 12),
                    _buildGovernorDotReportExports(),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildGovernorDotReportExports() {
    final catalog = _governorAllSpots
        .map(
          (s) => DotVar2SpotCatalogEntry(
            spotId: s['id']?.toString() ?? '',
            name: s['name']?.toString() ?? 'Unknown',
            dotAttractionCode: s['dotAttractionCode']?.toString() ?? '',
          ),
        )
        .toList();

    return DotReportExportPanel(
      primaryColor: _primaryOrange,
      textDark: _textDark,
      textMuted: _textMuted,
      borderColor: _cardBorder,
      scopeLabel: 'Misamis Occidental (Provincial)',
      scopeSlug: 'misamis_occidental_provincial',
      isProvincial: true,
      isMobile: _isMobile,
      checkIns: _checkIns,
      tourists: _tourists,
      catalogSpots: catalog,
      wrapPanel: (child) => _buildGovernorReportPanel(child: child),
    );
  }

  Widget _buildAnalyticsSectionLabel(
    String title,
    String subtitle,
    IconData icon,
  ) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: _primaryOrange.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(11),
          ),
          child: Icon(icon, color: _primaryOrange, size: 18),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  color: _textDark,
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.2,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                style: const TextStyle(
                  color: _textMuted,
                  fontSize: 12.5,
                  height: 1.35,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildAnalyticsCards() {
    final topOrigin = _analyticsTopOrigin;
    final originDisplay = topOrigin.length > 28
        ? '${topOrigin.substring(0, 26)}…'
        : topOrigin;

    final cards = [
      (
        title: 'Daily average',
        subtitle: 'Check-ins per active day',
        value: '$_analyticsDailyAvg',
        icon: Icons.calendar_today_rounded,
        accent: const Color(0xFF2563EB),
      ),
      (
        title: 'Peak hour',
        subtitle: 'Busiest QR scan window',
        value: _analyticsPeakHour,
        icon: Icons.access_time_rounded,
        accent: _primaryOrange,
      ),
      (
        title: 'Top origin',
        subtitle: 'Most common registration source',
        value: originDisplay,
        icon: Icons.flight_takeoff_rounded,
        accent: const Color(0xFF059669),
      ),
    ];

    if (_isMobile) {
      return Column(
        children: [
          for (var i = 0; i < cards.length; i++) ...[
            if (i > 0) const SizedBox(height: 10),
            _buildAnalyticsCard(
              title: cards[i].title,
              subtitle: cards[i].subtitle,
              value: cards[i].value,
              icon: cards[i].icon,
              accent: cards[i].accent,
            ),
          ],
        ],
      );
    }

    return Row(
      children: [
        for (var i = 0; i < cards.length; i++) ...[
          if (i > 0) const SizedBox(width: 12),
          Expanded(
            child: _buildAnalyticsCard(
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

  Widget _buildAnalyticsCard({
    required String title,
    required String subtitle,
    required String value,
    required IconData icon,
    required Color accent,
  }) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 15),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _cardBorder),
        boxShadow: const [
          BoxShadow(
            color: Color(0x08000000),
            blurRadius: 12,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: accent.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: accent, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: _textMuted,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  value,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: _textDark,
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    height: 1.15,
                    letterSpacing: -0.3,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: _textMuted.withValues(alpha: 0.92),
                    fontSize: 11.5,
                    height: 1.3,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTopSpotsChart() {
    final spots = _analyticsTopSpots.take(8).toList();
    final maxVisits = spots.isEmpty ? 1 : (spots.first['visits'] as int);

    return Container(
      padding: EdgeInsets.all(_isMobile ? 14 : 18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _cardBorder),
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
                  color: const Color(0xFFFFF7ED),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  '${spots.length} listed',
                  style: const TextStyle(
                    color: Color(0xFFC2410C),
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
              padding: EdgeInsets.symmetric(vertical: 36),
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
              final isTop = index == 0;
              return Padding(
                padding: EdgeInsets.only(bottom: index == spots.length - 1 ? 0 : 12),
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
                            name,
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

  // ==================== EVENTS (LGU publications — auto-published) ====================
  Widget _buildAnnouncementsContent() {
    final unreadCount = _pendingLguEventsCount;
    final publishedCount = _announcements
        .where((a) => LguEventService.isVisibleToTourists(a))
        .length;
    final unpublishedCount = _announcements
        .where(
          (a) =>
              LguEventService.statusOf(a) == 'approved' &&
              a['published'] != true,
        )
        .length;
    final sorted = List<Map<String, dynamic>>.from(_announcements)
      ..sort(_sortAnnouncementsForGovernor);

    return Container(
      color: _darkBg,
      child: Column(
        children: [
          _buildHeader(
            'Events',
            subtitle: unreadCount > 0
                ? '$unreadCount new LGU event${unreadCount == 1 ? '' : 's'}'
                : 'Province-wide LGU events (auto-published)',
          ),
          Expanded(
            child: Padding(
              padding: EdgeInsets.fromLTRB(
                _isMobile ? 12 : 20,
                _isMobile ? 14 : 18,
                _isMobile ? 12 : 20,
                16,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (_announcements.isNotEmpty)
                    _buildEventsSummaryBar(
                      unreadCount,
                      publishedCount,
                      unpublishedCount,
                    ),
                  if (_announcements.isNotEmpty) const SizedBox(height: 14),
                  Expanded(
                    child: _announcements.isEmpty
                        ? Center(
                            child: _buildEmptyState(
                              'No LGU events yet — municipalities publish events from their dashboard',
                              Icons.event_outlined,
                            ),
                          )
                        : Container(
                            decoration: _dashboardPanelDecoration(),
                            child: ListView.separated(
                              padding: const EdgeInsets.all(12),
                              itemCount: sorted.length,
                              separatorBuilder: (_, __) =>
                                  const SizedBox(height: 10),
                              itemBuilder: (context, index) =>
                                  _buildAnnouncementCard(sorted[index]),
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

  Widget _buildEventsSummaryBar(
    int unread,
    int published,
    int unpublished,
  ) {
    Widget statCard({
      required String label,
      required String value,
      required Color color,
      required IconData icon,
    }) {
      return Expanded(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: const Color(0xFFE5E7EB)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.04),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, color: color, size: 18),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      value,
                      style: TextStyle(
                        color: color,
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        height: 1.1,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      label,
                      style: const TextStyle(
                        color: _textMuted,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    }

    if (_isMobile) {
      return Column(
        children: [
          Row(
            children: [
              statCard(
                label: 'New',
                value: '$unread',
                color: const Color(0xFFEF4444),
                icon: Icons.fiber_new_rounded,
              ),
              const SizedBox(width: 8),
              statCard(
                label: 'Live',
                value: '$published',
                color: const Color(0xFF16A34A),
                icon: Icons.check_circle_rounded,
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              statCard(
                label: 'Unpublished',
                value: '$unpublished',
                color: _textMuted,
                icon: Icons.visibility_off_outlined,
              ),
              const SizedBox(width: 8),
              statCard(
                label: 'Total',
                value: '${_announcements.length}',
                color: _primaryOrange,
                icon: Icons.event_note_rounded,
              ),
            ],
          ),
        ],
      );
    }

    return Row(
      children: [
        statCard(
          label: 'New',
          value: '$unread',
          color: const Color(0xFFEF4444),
          icon: Icons.fiber_new_rounded,
        ),
        const SizedBox(width: 10),
        statCard(
          label: 'Live',
          value: '$published',
          color: const Color(0xFF16A34A),
          icon: Icons.check_circle_rounded,
        ),
        const SizedBox(width: 10),
        statCard(
          label: 'Unpublished',
          value: '$unpublished',
          color: _textMuted,
          icon: Icons.visibility_off_outlined,
        ),
        const SizedBox(width: 10),
        statCard(
          label: 'Total',
          value: '${_announcements.length}',
          color: _primaryOrange,
          icon: Icons.event_note_rounded,
        ),
      ],
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
        ? 'Published — push sent to installed apps.'
        : 'Published — saved for all users. Open-app alerts work now; '
            'background FCM needs Blaze billing + function deploy.';
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
    final status = LguEventService.statusOf(announcement);
    final isPublished = LguEventService.isVisibleToTourists(announcement);
    final type = announcement['type']?.toString() ?? LguEventService.typeEvent;
    final typeColor = _announcementTypeColor(type);
    final title = announcement['title']?.toString().trim() ?? 'Untitled';
    final content = announcement['content']?.toString().trim() ?? '';
    final date = announcement['date']?.toString() ?? '—';
    final municipality =
        announcement['municipalityName']?.toString().trim() ?? '';
    final imageUrl = LguEventService.resolveDisplayImage(announcement);
    final isPending = status == 'pending';

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isPending
              ? const Color(0xFFFBBF24).withValues(alpha: 0.65)
              : const Color(0xFFE5E7EB),
          width: isPending ? 1.4 : 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (imageUrl != null && imageUrl.isNotEmpty)
            SizedBox(
              height: _isMobile ? 148 : 168,
              width: double.infinity,
              child: ColoredBox(
                color: const Color(0xFF1E2530),
                child: SpotImage(
                  imageUrl: imageUrl,
                  fit: BoxFit.cover,
                  width: double.infinity,
                  height: double.infinity,
                ),
              ),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: typeColor.withValues(alpha: 0.12),
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
                          Text(
                            title,
                            style: const TextStyle(
                              color: _textDark,
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                              height: 1.25,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          if (municipality.isNotEmpty) ...[
                            const SizedBox(height: 4),
                            Text(
                              'From $municipality',
                              style: const TextStyle(
                                color: _textMuted,
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    _announcementStatusBadge(status, isPublished),
                  ],
                ),
                const SizedBox(height: 10),
                Text(
                  content.isEmpty ? 'No details' : content,
                  style: TextStyle(
                    color: content.isEmpty
                        ? _textMuted.withValues(alpha: 0.7)
                        : _textMuted,
                    fontSize: 13,
                    height: 1.4,
                  ),
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Icon(
                      Icons.calendar_today_outlined,
                      size: 14,
                      color: _textMuted,
                    ),
                    Text(
                      date,
                      style: const TextStyle(color: _textMuted, fontSize: 11),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: typeColor.withValues(alpha: 0.1),
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
                const SizedBox(height: 12),
                const Divider(height: 1, color: Color(0xFFE5E7EB)),
                const SizedBox(height: 10),
                _buildAnnouncementActionsRow(announcement, status, isPublished),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _announcementStatusBadge(String status, bool isPublished) {
    Color bg;
    Color fg;
    String label;
    switch (status) {
      case 'approved':
        label = isPublished ? 'Live' : 'Unpublished';
        bg = const Color(0xFFECFDF5);
        fg = const Color(0xFF16A34A);
        break;
      case 'rejected':
        label = 'Rejected (legacy)';
        bg = const Color(0xFFFEF2F2);
        fg = const Color(0xFFDC2626);
        break;
      default:
        label = 'Pending (legacy)';
        bg = const Color(0xFFFFF7ED);
        fg = const Color(0xFFD97706);
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: fg,
          fontSize: 10,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  Widget _buildAnnouncementActionsRow(
    Map<String, dynamic> announcement,
    String status,
    bool isPublished,
  ) {
    final buttons = <Widget>[];

    // Legacy pending items only — new posts auto-publish.
    if (status == 'pending') {
      buttons.add(
        _announcementActionButton(
          label: 'Publish',
          icon: Icons.check_circle_outline,
          color: const Color(0xFF2E7D32),
          onPressed: () => _approveLguEvent(announcement),
        ),
      );
    }
    if (status == 'approved' && isPublished) {
      buttons.add(
        _announcementActionButton(
          label: 'Unpublish',
          icon: Icons.visibility_off_outlined,
          color: _textMuted,
          onPressed: () => _unpublishLguEvent(announcement),
        ),
      );
    }

    if (buttons.isEmpty) {
      return const SizedBox.shrink();
    }

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: buttons,
    );
  }

  Future<void> _approveLguEvent(Map<String, dynamic> announcement) async {
    final id = announcement['id']?.toString() ?? '';
    if (id.isEmpty) return;
    try {
      await LguEventService().approveEvent(
        eventId: id,
        approvedBy: FirebaseAuth.instance.currentUser?.email ?? 'Governor',
      );
      final pushSent = await _broadcastPublishedAnnouncement(
        title: announcement['title']?.toString() ?? '',
        content: announcement['content']?.toString() ?? '',
        type: LguEventService.typeEvent,
        announcementId: id,
      );
      setState(() {
        final index = _announcements.indexWhere((a) => a['id'] == id);
        if (index != -1) {
          _announcements[index]['status'] = 'approved';
          _announcements[index]['published'] = true;
        }
      });
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_publishedAnnouncementSnackMessage(pushSent)),
          backgroundColor: _primaryOrange,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not approve event: $e')),
      );
    }
  }

  Future<void> _rejectLguEvent(Map<String, dynamic> announcement) async {
    final id = announcement['id']?.toString() ?? '';
    if (id.isEmpty) return;
    final reasonController = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Reject event?'),
        content: TextField(
          controller: reasonController,
          maxLines: 3,
          decoration: const InputDecoration(
            labelText: 'Reason (optional)',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Reject'),
          ),
        ],
      ),
    );
    if (confirmed != true) {
      reasonController.dispose();
      return;
    }
    try {
      await LguEventService().rejectEvent(
        eventId: id,
        reason: reasonController.text,
        rejectedBy: FirebaseAuth.instance.currentUser?.email ?? 'Governor',
      );
      setState(() {
        final index = _announcements.indexWhere((a) => a['id'] == id);
        if (index != -1) {
          _announcements[index]['status'] = 'rejected';
          _announcements[index]['published'] = false;
          if (reasonController.text.trim().isNotEmpty) {
            _announcements[index]['rejectedReason'] = reasonController.text.trim();
          }
        }
      });
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Event rejected')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not reject event: $e')),
      );
    } finally {
      reasonController.dispose();
    }
  }

  Future<void> _unpublishLguEvent(Map<String, dynamic> announcement) async {
    final id = announcement['id']?.toString() ?? '';
    if (id.isEmpty) return;
    try {
      await LguEventService().unpublishEvent(id);
      setState(() {
        final index = _announcements.indexWhere((a) => a['id'] == id);
        if (index != -1) {
          _announcements[index]['published'] = false;
        }
      });
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Event unpublished')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not unpublish event: $e')),
      );
    }
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

  // ==================== PROVINCIAL EXPORTS (on Analytics) ====================
  Widget _buildGovernorReportPanel({required Widget child}) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(_isMobile ? 14 : 18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _cardBorder),
        boxShadow: const [
          BoxShadow(
            color: Color(0x08000000),
            blurRadius: 12,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: child,
    );
  }

  Widget _buildGovernorQuickReports() {
    final items = <({
      String title,
      String subtitle,
      IconData icon,
      Color accent,
      String type,
    })>[
      (
        title: 'Daily',
        subtitle: "Today's check-ins",
        icon: Icons.today_rounded,
        accent: const Color(0xFF2563EB),
        type: 'daily',
      ),
      (
        title: 'Weekly',
        subtitle: 'Last 7 days',
        icon: Icons.date_range_rounded,
        accent: const Color(0xFFEA580C),
        type: 'weekly',
      ),
      (
        title: 'Monthly',
        subtitle: 'This month to date',
        icon: Icons.calendar_month_rounded,
        accent: _primaryOrange,
        type: 'monthly',
      ),
      (
        title: 'Annual',
        subtitle: 'Year to date',
        icon: Icons.calendar_today_rounded,
        accent: const Color(0xFF0F766E),
        type: 'annual',
      ),
    ];

    return _buildGovernorReportPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'Quick exports',
            style: TextStyle(
              color: _textDark,
              fontSize: 14.5,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            'One-tap province-wide downloads by time window.',
            style: TextStyle(color: _textMuted, fontSize: 12, height: 1.35),
          ),
          const SizedBox(height: 14),
          LayoutBuilder(
            builder: (context, constraints) {
              final twoCol = constraints.maxWidth >= 360;
              if (!twoCol) {
                return Column(
                  children: [
                    for (var i = 0; i < items.length; i++) ...[
                      if (i > 0) const SizedBox(height: 10),
                      _buildGovernorQuickReportRow(
                        title: items[i].title,
                        subtitle: items[i].subtitle,
                        icon: items[i].icon,
                        accent: items[i].accent,
                        type: items[i].type,
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
                            child: _buildGovernorQuickReportRow(
                              title: items[row * 2 + col].title,
                              subtitle: items[row * 2 + col].subtitle,
                              icon: items[row * 2 + col].icon,
                              accent: items[row * 2 + col].accent,
                              type: items[row * 2 + col].type,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildGovernorQuickReportRow({
    required String title,
    required String subtitle,
    required IconData icon,
    required Color accent,
    required String type,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => _generateGovernorQuickReport(type),
        borderRadius: BorderRadius.circular(14),
        child: Ink(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: const Color(0xFFF8FAFC),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: _cardBorder),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 34,
                    height: 34,
                    decoration: BoxDecoration(
                      color: accent.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(icon, color: accent, size: 17),
                  ),
                  const Spacer(),
                  Icon(Icons.download_rounded, size: 16, color: accent),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                title,
                style: const TextStyle(
                  color: _textDark,
                  fontSize: 13.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                style: const TextStyle(
                  color: _textMuted,
                  fontSize: 11.5,
                  height: 1.3,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildGovernorCustomReportGenerator() {
    return _buildGovernorReportPanel(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final stacked = _isMobile || constraints.maxWidth < 720;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'Custom report',
                style: TextStyle(
                  color: _textDark,
                  fontSize: 14.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 4),
              const Text(
                'Pick a date range and report type, then export province-wide.',
                style: TextStyle(color: _textMuted, fontSize: 12, height: 1.35),
              ),
              const SizedBox(height: 16),
              if (stacked) ...[
                _buildGovernorDatePicker(
                  'Start Date',
                  _reportStartDate,
                  (d) => setState(() => _reportStartDate = d),
                ),
                const SizedBox(height: 12),
                _buildGovernorDatePicker(
                  'End Date',
                  _reportEndDate,
                  (d) => setState(() => _reportEndDate = d),
                ),
                const SizedBox(height: 12),
                _buildGovernorReportTypeDropdown(),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: _generateGovernorCustomReport,
                    icon: _isExporting
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(Icons.download),
                    label: Text(_isExporting ? 'Generating...' : 'Generate'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _primaryOrange,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                  ),
                ),
              ] else
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  crossAxisAlignment: WrapCrossAlignment.end,
                  children: [
                    SizedBox(
                      width: 190,
                      child: _buildGovernorDatePicker(
                        'Start Date',
                        _reportStartDate,
                        (d) => setState(() => _reportStartDate = d),
                      ),
                    ),
                    SizedBox(
                      width: 190,
                      child: _buildGovernorDatePicker(
                        'End Date',
                        _reportEndDate,
                        (d) => setState(() => _reportEndDate = d),
                      ),
                    ),
                    SizedBox(
                      width: math.min(280.0, constraints.maxWidth - 24),
                      child: _buildGovernorReportTypeDropdown(),
                    ),
                    ElevatedButton.icon(
                      onPressed: _generateGovernorCustomReport,
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
                      ),
                    ),
                  ],
                ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildGovernorDatePicker(
    String label,
    DateTime? selected,
    ValueChanged<DateTime> onSelect,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(color: _textMuted, fontSize: 11)),
        const SizedBox(height: 4),
        InkWell(
          onTap: () async {
            final date = await showDatePicker(
              context: context,
              initialDate: selected ?? DateTime.now(),
              firstDate: DateTime(2020),
              lastDate: DateTime.now().add(const Duration(days: 365)),
            );
            if (date != null) onSelect(date);
          },
          borderRadius: BorderRadius.circular(10),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              border: Border.all(color: _cardBorder),
              borderRadius: BorderRadius.circular(10),
              color: Colors.white,
            ),
            child: Text(
              selected != null
                  ? formatReportDate(selected)
                  : 'Select date',
              style: TextStyle(
                color: selected != null ? _textDark : _textMuted,
                fontSize: 13,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildGovernorReportTypeDropdown() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        const Text(
          'Report Type',
          style: TextStyle(color: _textMuted, fontSize: 11),
        ),
        const SizedBox(height: 4),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: _cardBorder),
          ),
          child: DropdownButton<String>(
            value: _reportType,
            isExpanded: true,
            isDense: true,
            dropdownColor: Colors.white,
            underline: const SizedBox.shrink(),
            icon: Icon(Icons.keyboard_arrow_down, color: _textMuted, size: 20),
            style: const TextStyle(color: _textDark, fontSize: 13),
            items: _reportTypes
                .map(
                  (t) => DropdownMenuItem(
                    value: t,
                    child: Text(
                      t,
                      overflow: TextOverflow.ellipsis,
                      maxLines: 1,
                      style: const TextStyle(fontSize: 13),
                    ),
                  ),
                )
                .toList(),
            onChanged: (v) {
              if (v != null) setState(() => _reportType = v);
            },
          ),
        ),
      ],
    );
  }

  Future<void> _generateGovernorQuickReport(String type) async {
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

    await _generateGovernorReport(
      startDate,
      endDate,
      'All Data',
      type,
    );
  }

  Future<void> _generateGovernorCustomReport() async {
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

    if (_reportType == 'DOT Tourism Attraction Visitor Record (VAR 2)') {
      await _generateGovernorVar2Report(start, end, 'custom');
      return;
    }

    await _generateGovernorReport(start, end, _reportType, 'custom');
  }

  Future<void> _generateGovernorVar2Report(
    DateTime startDate,
    DateTime endDate,
    String period,
  ) async {
    setState(() {
      _isExporting = true;
      _exportProgress = 0.0;
    });

    for (var i = 1; i <= 8; i++) {
      await Future.delayed(const Duration(milliseconds: 80));
      if (mounted) setState(() => _exportProgress = i / 8);
    }

    final filtered = filterCheckInsInDateRange(_checkIns, startDate, endDate);
    final catalog = _governorAllSpots
        .map(
          (s) => DotVar2SpotCatalogEntry(
            spotId: s['id']?.toString() ?? '',
            name: s['name']?.toString() ?? 'Unknown',
            dotAttractionCode: s['dotAttractionCode']?.toString() ?? '',
          ),
        )
        .toList();

    const provinceLabel = 'Misamis Occidental (Provincial)';
    final var2 = buildDotVar2VisitorRecordReport(
      checkIns: filtered,
      catalogSpots: catalog,
      municipalityName: provinceLabel,
      startDate: startDate,
      endDate: endDate,
    );

    final csvName = var2CsvFilename(
      municipalitySlug: 'misamis_occidental_provincial',
      startDate: startDate,
      endDate: endDate,
    );
    final xlsxName = var2XlsxFilename(
      municipalitySlug: 'misamis_occidental_provincial',
      startDate: startDate,
      endDate: endDate,
    );

    final report = StringBuffer()
      ..writeln('=== DOT VAR 2 — PROVINCIAL (MISAMIS OCCIDENTAL) ===')
      ..writeln('Generated: ${DateTime.now()}')
      ..writeln('Month/Year: ${var2.monthYearLabel}')
      ..writeln('Scope: $provinceLabel')
      ..writeln('Check-ins in period: ${var2.checkInsProcessed}')
      ..writeln()
      ..writeln(var2.note)
      ..writeln()
      ..writeln('--- ATTRACTION SUMMARY (province-wide) ---');

    for (final row in var2.rows) {
      report.writeln(
        '${row.name} [${row.attractionCode.isEmpty ? 'no code' : row.attractionCode}] '
        '→ Grand Total: ${row.grandTotal.total}',
      );
    }
    report
      ..writeln()
      ..writeln(
        'Total of this Month ****: ${var2.footerTotals.grandTotal.total}',
      );

    if (mounted) setState(() => _isExporting = false);
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Provincial VAR 2 generated (${var2.checkInsProcessed} check-ins)',
        ),
        backgroundColor: _primaryOrange,
        action: SnackBarAction(
          label: 'Preview',
          textColor: Colors.white,
          onPressed: () => _showGovernorExportPreview(
            'Provincial VAR 2 Report',
            report.toString(),
            csvData: var2.csv,
            csvFilename: csvName,
            xlsxBytes: var2.xlsxBytes,
            xlsxFilename: xlsxName,
          ),
        ),
      ),
    );
  }

  Future<void> _generateGovernorReport(
    DateTime startDate,
    DateTime endDate,
    String type,
    String period,
  ) async {
    setState(() {
      _isExporting = true;
      _exportProgress = 0.0;
    });

    for (var i = 1; i <= 8; i++) {
      await Future.delayed(const Duration(milliseconds: 80));
      if (mounted) setState(() => _exportProgress = i / 8);
    }

    final built = buildProvincialAtmosReport(
      allCheckIns: _checkIns,
      tourists: _tourists,
      spots: _governorAllSpots,
      activeSpots: _activeSpots,
      startDate: startDate,
      endDate: endDate,
      reportType: type,
      period: period,
    );

    if (mounted) setState(() => _isExporting = false);
    if (!mounted) return;

    final summaryCsvName = built.summaryCsv != null
        ? checkInSummaryCsvFilename(
            period: period,
            startDate: startDate,
            endDate: endDate,
          ).replaceFirst('checkin_summary', 'provincial_checkin_summary')
        : null;
    final muniCsvName = built.municipalityCsv != null
        ? provincialReportCsvFilename(
            period: period,
            startDate: startDate,
            endDate: endDate,
            suffix: 'by_municipality',
          )
        : null;
    final detailCsvName = built.detailCsv != null
        ? provincialReportCsvFilename(
            period: period,
            startDate: startDate,
            endDate: endDate,
            suffix: 'checkins_detail',
          )
        : null;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Provincial $period report generated (${built.checkInsInPeriod} check-ins)',
        ),
        backgroundColor: _primaryOrange,
        action: SnackBarAction(
          label: 'Preview',
          textColor: Colors.white,
          onPressed: () => _showGovernorExportPreview(
            'Provincial ${_capitalizeLabel(period)} Report',
            built.reportText,
            csvData: built.summaryCsv,
            csvFilename: summaryCsvName,
            detailCsvData: built.municipalityCsv ?? built.detailCsv,
            detailCsvFilename: muniCsvName ?? detailCsvName,
          ),
        ),
      ),
    );
  }

  void _showGovernorExportPreview(
    String title,
    String content, {
    String? csvData,
    String? csvFilename,
    String? detailCsvData,
    String? detailCsvFilename,
    List<int>? xlsxBytes,
    String? xlsxFilename,
  }) {
    showReportExportPreviewDialog(
      context,
      title: title,
      subtitle: 'ATMOS-TRS · Governor Portal · Provincial export',
      content: content,
      csvData: csvData,
      csvFilename: csvFilename,
      detailCsvData: detailCsvData,
      detailCsvFilename: detailCsvFilename,
      detailCsvLabel: detailCsvFilename != null &&
              detailCsvFilename.contains('municipality')
          ? 'Download by municipality CSV'
          : 'Download detail CSV',
      xlsxBytes: xlsxBytes,
      xlsxFilename: xlsxFilename,
      accentColor: _primaryOrange,
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
                          : 'Provincial exports on Analytics (all LGUs)',
                      () => setState(() => _selectedIndex = _analyticsIndex),
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
                  style: const TextStyle(
                    color: _textDark,
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
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
                      style: const TextStyle(
                        color: _textDark,
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        color: _textMuted,
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
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
  InputDecoration _changePasswordFieldDecoration({
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
        borderSide: const BorderSide(color: _cardBorder, width: 1.2),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: _primaryOrange, width: 2),
      ),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: _cardBorder),
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

  Widget _changePasswordFieldLabel(String label) {
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

  Widget _passwordRequirementRow(String text, bool met) {
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

  void _showChangePasswordDialog() {
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
                  'Update your Governor account password. Use a strong password you have not used before.',
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
                    _changePasswordFieldLabel('Current password'),
                    TextField(
                      controller: currentPasswordController,
                      obscureText: obscureCurrent,
                      style: const TextStyle(
                        color: _textDark,
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                      decoration: _changePasswordFieldDecoration(
                        hint: 'Enter your current password',
                        obscure: obscureCurrent,
                        onToggleObscure: () => setDialogState(
                          () => obscureCurrent = !obscureCurrent,
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    _changePasswordFieldLabel('New password'),
                    TextField(
                      controller: newPasswordController,
                      obscureText: obscureNew,
                      onChanged: (v) => setDialogState(() => newPassword = v),
                      style: const TextStyle(
                        color: _textDark,
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                      decoration: _changePasswordFieldDecoration(
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
                          _passwordRequirementRow('At least 8 characters', hasLen),
                          _passwordRequirementRow('One uppercase letter (A–Z)', hasUpper),
                          _passwordRequirementRow('One lowercase letter (a–z)', hasLower),
                          _passwordRequirementRow('One number (0–9)', hasNumber),
                          _passwordRequirementRow(
                            'One special character (!@#\$%…)',
                            hasSpecial,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    _changePasswordFieldLabel('Confirm new password'),
                    TextField(
                      controller: confirmPasswordController,
                      obscureText: obscureConfirm,
                      style: const TextStyle(
                        color: _textDark,
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                      decoration: _changePasswordFieldDecoration(
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

                        if (!await SessionStorage.matchesStoredGovernorPassword(
                          currentPasswordController.text,
                        )) {
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
                        try {
                          await AuthService.reauthenticateAndUpdatePassword(
                            email: SessionStorage.governorEmail,
                            currentPassword: typedCurrent,
                            newPassword: newPassword,
                          );
                        } on FirebaseAuthException catch (authErr) {
                          // Prefs may already be ahead of Auth after a prior local-only change.
                          final code = authErr.code;
                          final canRetryDefault = code == 'wrong-password' ||
                              code == 'invalid-credential' ||
                              code == 'invalid-login-credentials';
                          if (!canRetryDefault ||
                              typedCurrent ==
                                  SessionStorage.governorPasswordLegacy) {
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
                              email: SessionStorage.governorEmail,
                              currentPassword:
                                  SessionStorage.governorPasswordLegacy,
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

                        await SessionStorage.persistGovernorPassword(newPassword);

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
              'Registered Tourists Data (CSV)',
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
        // Privacy: no name/email; unique registrations only (not visit counts).
        content = 'Tourist ID,Origin,Date Registered,Time Registered\n';
        for (final t in _uniqueRegisteredTourists(_tourists)) {
          final id = TouristIdHelper.displayForTourist(t).replaceAll(',', ' ');
          final origin = _getTouristOrigin(t).replaceAll(',', ' ');
          final dt = _registeredDateTimeFromTourist(t);
          content +=
              '$id,$origin,${_formatRegisteredDateOnly(dt)},${_formatRegisteredTimeOnly(dt)}\n';
        }
        filename =
            'tourists_export_${DateTime.now().millisecondsSinceEpoch}.csv';
        break;
      case 'checkins':
        content = 'Date,Tourist ID,Location,Status\n';
        for (final c in _checkIns) {
          final d = GovernorFirestoreService.parseCheckInTime(c);
          final date = d != null
              ? '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}'
              : '';
          final uid = GovernorFirestoreService.checkInUserId(c);
          final location =
              c['location']?.toString() ??
              c['spot_name']?.toString() ??
              c['spotId']?.toString() ??
              '';
          final status = c['status']?.toString() ?? 'Verified';
          content += '$date,$uid,"${location.replaceAll('"', '""')}",$status\n';
        }
        filename =
            'checkins_export_${DateTime.now().millisecondsSinceEpoch}.csv';
        break;
      case 'report':
        content = 'ATMOS-TRS Summary Report\n';
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
            _buildInfoRow('App Name', 'ATMOS-TRS'),
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
        'a':
            'Open Analytics in the sidebar for provincial exports (quick + custom reports for all LGUs). LGU staff export their municipality only.',
      },
      {
        'q': 'How do I change my password?',
        'a': 'Go to Settings > Account > Change Password.',
      },
      {
        'q': 'How do I view analytics?',
        'a':
            'Click Analytics in the sidebar for insights (daily avg, peak hour, top origin, top spots) and provincial export tools.',
      },
      {
        'q': 'How do LGU events get published?',
        'a':
            'LGUs publish events from their dashboard. Posts go live immediately. New events notify you on the header bell (with a count badge) — open Notifications to review them.',
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

  String _capitalizeLabel(String value) {
    if (value.isEmpty) return value;
    return '${value[0].toUpperCase()}${value.substring(1)}';
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
            color: Color(0xFF1A1A1A),
            fontSize: 10,
            fontWeight: FontWeight.bold,
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

/// Soft scale-up on hover for municipality cards (desktop / web).
class _MunicipalityHoverCard extends StatefulWidget {
  const _MunicipalityHoverCard({
    required this.child,
    required this.onTap,
  });

  final Widget child;
  final VoidCallback onTap;

  @override
  State<_MunicipalityHoverCard> createState() => _MunicipalityHoverCardState();
}

class _MunicipalityHoverCardState extends State<_MunicipalityHoverCard> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedScale(
          scale: _hovered ? 1.02 : 1.0,
          duration: const Duration(milliseconds: 160),
          curve: Curves.easeOut,
          child: AnimatedOpacity(
            opacity: _hovered ? 1 : 0.98,
            duration: const Duration(milliseconds: 160),
            child: widget.child,
          ),
        ),
      ),
    );
  }
}

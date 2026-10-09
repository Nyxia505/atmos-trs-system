import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:atmos_trs_system/config/ae_register_schema.dart';
import 'package:atmos_trs_system/config/app_theme.dart';
import 'package:atmos_trs_system/config/auth_config.dart';
import 'package:atmos_trs_system/config/session_storage.dart';
import 'package:atmos_trs_system/models/sign_off.dart';
import 'package:atmos_trs_system/services/ae_register_service.dart';
import 'package:atmos_trs_system/services/sign_off_service.dart';
import 'package:atmos_trs_system/services/establishment_gallery_service.dart';
import 'package:atmos_trs_system/services/establishment_firestore_write.dart';
import 'package:atmos_trs_system/services/establishment_map_pin_store.dart';
import 'package:atmos_trs_system/services/establishment_registration_service.dart';
import 'package:atmos_trs_system/services/firestore_auth_gate.dart';
import 'package:atmos_trs_system/utils/dot_report_entity_scope.dart';
import 'package:atmos_trs_system/utils/establishment_capability.dart';
import 'package:atmos_trs_system/utils/establishment_lodging_hours.dart';
import 'package:atmos_trs_system/widgets/ae_register/ae_register_workspace.dart';
import 'package:atmos_trs_system/widgets/dot_report_export_panel.dart';
import 'package:atmos_trs_system/widgets/mice_register/mice_register_workspace.dart';
import 'package:atmos_trs_system/widgets/establishment_dash_tokens.dart';
import 'package:atmos_trs_system/widgets/establishment_dashboard_components.dart';
import 'package:atmos_trs_system/widgets/establishment_insights_board.dart';
import 'package:atmos_trs_system/widgets/establishment_profile_cards.dart';
import 'package:atmos_trs_system/widgets/establishment_settings_panel.dart';
import 'package:atmos_trs_system/widgets/sign_off/sign_off_dialog.dart';
import 'package:atmos_trs_system/widgets/sign_off/sign_off_history_panel.dart';

/// Tourism establishment dashboard: DOT DAE-1B register (manual entry) +
/// Insights + profile. Feeds LGU / OPTACA / Governor via monthly reports.
class EstablishmentDashboardScreen extends StatefulWidget {
  const EstablishmentDashboardScreen({super.key});

  @override
  State<EstablishmentDashboardScreen> createState() =>
      _EstablishmentDashboardScreenState();
}

class _EstablishmentDashboardScreenState
    extends State<EstablishmentDashboardScreen> {
  static const double _mobileBreakpoint = 900;

  bool _loading = true;
  bool _sidebarExpanded = true;
  int _selectedIndex = 0;
  String _uid = '';
  String _businessName = '';
  String _category = '';
  String _status = 'pending';
  String _municipality = '';
  String _municipalityId = '';
  int _roomCount = 0;
  String _aeType = '';
  String _classificationCode = '';
  bool _hostsMice = false;
  String _checkInTime = EstablishmentLodgingHours.defaultCheckIn;
  String _checkOutTime = EstablishmentLodgingHours.defaultCheckOut;
  double? _latitude;
  double? _longitude;
  List<String> _galleryUrls = const [];
  String? _error;

  bool _savingProfile = false;
  bool _savingHours = false;
  bool _savingLocation = false;
  bool _locating = false;
  bool _galleryBusy = false;
  bool _statusBannerDismissed = false;

  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

  EstablishmentPackCopy get _copy =>
      EstablishmentCapability.copyFor(_category);
  bool get _isLodging => EstablishmentCapability.isLodging(_category);
  AeRegisterSchema get _schema => AeRegisterSchema.forCategory(_category);

  AeRegisterProfile get _profile => AeRegisterProfile(
        aeId: _uid,
        aeName: _businessName,
        municipalityId: _municipalityId,
        municipality: _municipality,
        totalRooms: _schema.tracksRooms ? _roomCount : 0,
        aeType: _aeType,
        classificationCode: _classificationCode,
        category: _category,
      );

  List<_AeTab> get _tabs => [
        _AeTab.register,
        if (_hostsMice) _AeTab.events,
        _AeTab.insights,
        if (_reportFormIds.isNotEmpty) _AeTab.reports,
        _AeTab.profile,
        _AeTab.settings,
      ];

  /// DOT forms this establishment can download from its own data.
  Set<String> get _reportFormIds => {
        if (_isLodging) ...{'dae1b_macro', 'dae1a_manual', 'dae1b2', 'dae1b2_domestic'},
        if (_hostsMice) 'mice_cus',
      };

  _AeTab get _currentTab {
    if (_selectedIndex < 0 || _selectedIndex >= _tabs.length) {
      return _AeTab.register;
    }
    return _tabs[_selectedIndex];
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final authUid = FirebaseAuth.instance.currentUser?.uid;
    final storedUid = await SessionStorage.getStoredUser();
    final uid = (authUid != null && authUid.isNotEmpty) ? authUid : storedUid;
    if (uid == null || uid.isEmpty) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Session expired. Please log in again.';
      });
      return;
    }

    final tokenOk = await FirestoreAuthGate.ensureFreshIdToken();
    if (!tokenOk && FirebaseAuth.instance.currentUser == null) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = FirestoreAuthGate.missingAuthMessage();
      });
      return;
    }

    try {
      final db = FirebaseFirestore.instance;
      Future<Map<String, dynamic>> readUser() async {
        try {
          final userDoc = await db.collection('users').doc(uid).get();
          return userDoc.data() ?? const <String, dynamic>{};
        } catch (e) {
          debugPrint('[AE Dashboard] users/$uid read: $e');
          return const <String, dynamic>{};
        }
      }

      Future<Map<String, dynamic>> readEstablishment() async {
        final estDoc = await db
            .collection(EstablishmentRegistrationService.establishmentsCollection)
            .doc(uid)
            .get();
        return estDoc.data() ?? const <String, dynamic>{};
      }

      final docs = await Future.wait([readUser(), readEstablishment()]);
      final user = docs[0];
      final est = docs[1];
      final businessName = (est['businessName'] ??
              est['name'] ??
              user['businessName'] ??
              'Your establishment')
          .toString();
      final municipalityId =
          (user['municipalityId'] ?? est['municipalityId'] ?? '').toString();
      final roomRaw = est['roomCount'] ?? user['roomCount'];
      final roomCount = roomRaw is int
          ? roomRaw
          : int.tryParse(roomRaw?.toString() ?? '') ?? 0;
      final checkInRaw = (est['checkInTime'] ?? user['checkInTime'] ?? '')
          .toString()
          .trim();
      final checkOutRaw = (est['checkOutTime'] ?? user['checkOutTime'] ?? '')
          .toString()
          .trim();
      double? asDouble(dynamic raw) {
        if (raw is double) return raw;
        if (raw is num) return raw.toDouble();
        return double.tryParse(raw?.toString() ?? '');
      }

      final latitude = asDouble(est['latitude'] ?? user['latitude']);
      final longitude = asDouble(est['longitude'] ?? user['longitude']);
      final galleryUrls = EstablishmentGalleryService.parseUrls(
        est[EstablishmentGalleryService.fieldGalleryUrls],
      );
      if (!mounted) return;
      final category =
          (est['category'] ?? est['type'] ?? user['category'] ?? '').toString();
      final aeTypeRaw = (est['aeType'] ?? '').toString().trim();
      final aeType = aeTypeRaw.isNotEmpty
          ? aeTypeRaw
          : AeTypeCatalog.typeForCategory(category);
      final codeRaw = (est['classificationCode'] ?? '').toString().trim();
      setState(() {
        _uid = uid;
        _businessName = businessName;
        _category = category;
        _status = (user['status'] ?? est['status'] ?? 'pending')
            .toString()
            .toLowerCase();
        _municipality =
            (user['municipality'] ?? est['municipality'] ?? '').toString();
        _municipalityId = municipalityId;
        _roomCount = roomCount;
        _aeType = aeType;
        _classificationCode =
            codeRaw.isNotEmpty ? codeRaw : AeTypeCatalog.codeFor(aeType);
        _hostsMice = EstablishmentCapability.hostsMice(category, est['hostsMice']);
        _checkInTime = EstablishmentLodgingHours.tryParse(checkInRaw) != null
            ? checkInRaw
            : EstablishmentLodgingHours.defaultCheckIn;
        _checkOutTime = EstablishmentLodgingHours.tryParse(checkOutRaw) != null
            ? checkOutRaw
            : EstablishmentLodgingHours.defaultCheckOut;
        _latitude = latitude;
        _longitude = longitude;
        _galleryUrls = galleryUrls;
        if (_selectedIndex >= _tabs.length) _selectedIndex = 0;
        _loading = false;
        _error = null;
      });
      // Prefer Supabase pin (free-tier source of truth) over stale Firestore coords.
      final supabasePin = await EstablishmentMapPinStore.load(uid);
      if (!mounted || supabasePin == null) return;
      setState(() {
        _latitude = supabasePin.latitude;
        _longitude = supabasePin.longitude;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Could not load establishment profile.';
      });
    }
  }

  Future<void> _saveReportingProfile({
    required int totalRooms,
    required String aeType,
    required String classificationCode,
    required bool hostsMice,
  }) async {
    if (_uid.isEmpty || _savingProfile) return;
    final before = <String, dynamic>{
      if (_schema.tracksRooms) 'totalRooms': _roomCount,
      'aeType': _aeType,
      'classificationCode': _classificationCode,
      'hostsMice': _hostsMice,
    };
    final after = <String, dynamic>{
      if (_schema.tracksRooms) 'totalRooms': totalRooms,
      'aeType': aeType,
      'classificationCode': classificationCode,
      'hostsMice': hostsMice,
    };
    final diffs = signOffDiffLines(before, after);
    if (diffs.isEmpty) {
      _snack('No changes to save.');
      return;
    }
    final capture = await SignOffDialog.show(
      context,
      ownerId: _uid,
      action: AeSignOffActions.reportingProfile,
      summary: 'Used on every monthly DOT register and DAE form (occupancy uses total rooms).',
      details: diffs,
    );
    if (capture == null || !mounted) return;
    setState(() => _savingProfile = true);
    try {
      await SignOffService.writeStandalone(
        subjectType: SignOffSubjects.aeProfile,
        subjectId: _uid,
        ownerId: _uid,
        ownerName: _businessName,
        municipalityId: _municipalityId,
        request: SignOffRequest(
          action: AeSignOffActions.reportingProfile,
          capture: capture,
          summary: diffs.join(' · '),
          details: diffs,
        ),
        contentHash: SignOffService.contentHash(after),
        snapshot: after,
        changes: [SignOffChange(op: 'edit', label: 'DOT reporting profile', before: before, after: after)],
      );
      await EstablishmentFirestoreWrite.mergeFields(_uid, {
        if (_schema.tracksRooms) 'roomCount': totalRooms,
        'aeType': aeType,
        'classificationCode': classificationCode,
        'hostsMice': hostsMice,
      });
      if (!mounted) return;
      final tab = _currentTab;
      setState(() {
        if (_schema.tracksRooms) _roomCount = totalRooms;
        _aeType = aeType;
        _classificationCode = classificationCode;
        _hostsMice = hostsMice;
        final i = _tabs.indexOf(tab);
        _selectedIndex = i < 0 ? 0 : i;
      });
      _snack('Reporting profile saved and signed. Monthly reports updated.');
      unawaited(
        AeRegisterService.refreshProfileOnHeaders(_profile).catchError(
          (Object e) => debugPrint('[AE Dashboard] header refresh: $e'),
        ),
      );
    } catch (e) {
      _snack('Save failed: $e', error: true);
    } finally {
      if (mounted) setState(() => _savingProfile = false);
    }
  }

  Future<void> _logout() async {
    await SessionStorage.clearSession();
    AuthConfig.currentUserUid = null;
    try {
      await FirebaseAuth.instance.signOut();
    } catch (_) {}
    if (!mounted) return;
    Navigator.pushNamedAndRemoveUntil(context, '/login', (_) => false);
  }

  bool get _isPending => _status == 'pending' || _status.isEmpty;
  bool get _isRejected => _status == 'rejected';

  Future<void> _pickAndSaveCheckInTime() async {
    if (_uid.isEmpty || _savingHours) return;
    final current = EstablishmentLodgingHours.tryParse(_checkInTime) ??
        const TimeOfDay(hour: 14, minute: 0);
    final picked = await showTimePicker(context: context, initialTime: current);
    if (picked == null || !mounted) return;
    await _saveLodgingHours(
      checkIn: EstablishmentLodgingHours.format(picked),
      checkOut: _checkOutTime,
    );
  }

  Future<void> _pickAndSaveCheckOutTime() async {
    if (_uid.isEmpty || _savingHours) return;
    final current = EstablishmentLodgingHours.tryParse(_checkOutTime) ??
        const TimeOfDay(hour: 12, minute: 0);
    final picked = await showTimePicker(context: context, initialTime: current);
    if (picked == null || !mounted) return;
    await _saveLodgingHours(
      checkIn: _checkInTime,
      checkOut: EstablishmentLodgingHours.format(picked),
    );
  }

  Future<void> _saveLodgingHours({
    required String checkIn,
    required String checkOut,
  }) async {
    final cin = EstablishmentLodgingHours.tryParse(checkIn);
    final cout = EstablishmentLodgingHours.tryParse(checkOut);
    if (cin == null || cout == null) {
      _snack('Invalid check-in or check-out time.');
      return;
    }
    if (EstablishmentLodgingHours.minutesSinceMidnight(cin) ==
        EstablishmentLodgingHours.minutesSinceMidnight(cout)) {
      _snack('Check-in and check-out times must be different.');
      return;
    }
    setState(() => _savingHours = true);
    try {
      await EstablishmentFirestoreWrite.mergeFields(_uid, {
        'checkInTime': checkIn,
        'checkOutTime': checkOut,
      });
      if (!mounted) return;
      setState(() {
        _checkInTime = checkIn;
        _checkOutTime = checkOut;
      });
      _snack('Check-in / check-out times saved.');
    } catch (e) {
      _snack('Save failed: $e', error: true);
    } finally {
      if (mounted) setState(() => _savingHours = false);
    }
  }

  Future<void> _saveMapPin({
    required double latitude,
    required double longitude,
  }) async {
    if (_uid.isEmpty || _savingLocation) return;
    if (latitude.abs() < 1e-6 && longitude.abs() < 1e-6) {
      _snack('Invalid map coordinates.', error: true);
      return;
    }
    if (_latitude != null &&
        _longitude != null &&
        (_latitude! - latitude).abs() < 1e-7 &&
        (_longitude! - longitude).abs() < 1e-7) {
      _snack('Map pin unchanged.');
      return;
    }

    setState(() {
      _latitude = latitude;
      _longitude = longitude;
      _savingLocation = true;
    });

    try {
      // Source of truth on free tier: Supabase (same bucket as photos).
      await EstablishmentMapPinStore.save(
        establishmentId: _uid,
        latitude: latitude,
        longitude: longitude,
      );
      if (!mounted) return;
      _snack(
        'Map pin saved. Tourists will see it on Explore after OPTACA approval.',
      );

      // Best-effort Firestore mirror only — never fail the UX on free-tier 429/hangs.
      unawaited(
        EstablishmentFirestoreWrite.mergeFields(_uid, {
          'latitude': latitude,
          'longitude': longitude,
        }).catchError((Object e) {
          debugPrint('[AE Dashboard] pin firestore mirror skipped: $e');
        }),
      );
    } catch (e) {
      if (!mounted) return;
      _snack('Could not save map pin. Check connection and try again.', error: true);
    } finally {
      if (mounted) setState(() => _savingLocation = false);
    }
  }

  Future<void> _addGalleryPhoto() async {
    if (_uid.isEmpty || _galleryBusy) return;
    setState(() => _galleryBusy = true);
    try {
      final next = await EstablishmentGalleryService.pickAndUpload(
        establishmentId: _uid,
        currentUrls: _galleryUrls,
      );
      if (!mounted) return;
      setState(() => _galleryUrls = next);
      _snack('Photo added. Tourists will see it on your map profile.');
    } catch (e) {
      if (!mounted) return;
      final msg = e.toString().replaceFirst('Bad state: ', '');
      _snack(msg, error: true);
    } finally {
      if (mounted) setState(() => _galleryBusy = false);
    }
  }

  void _snack(String message, {bool error = false}) {
    if (!mounted) return;
    final messenger = ScaffoldMessenger.maybeOf(context);
    if (messenger == null) return;
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: error ? Colors.red.shade700 : null,
          behavior: SnackBarBehavior.floating,
        ),
      );
  }

  Future<void> _removeGalleryPhoto(int index) async {
    if (_uid.isEmpty || _galleryBusy) return;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remove photo?'),
        content: const Text(
          'This photo will disappear from your tourist map profile.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    setState(() => _galleryBusy = true);
    try {
      final next = await EstablishmentGalleryService.removeAt(
        establishmentId: _uid,
        currentUrls: _galleryUrls,
        index: index,
      );
      if (!mounted) return;
      setState(() => _galleryUrls = next);
    } catch (e) {
      if (!mounted) return;
      _snack('Remove failed: $e', error: true);
    } finally {
      if (mounted) setState(() => _galleryBusy = false);
    }
  }

  void _selectTab(int index) {
    setState(() => _selectedIndex = index);
    if (_scaffoldKey.currentState?.isDrawerOpen ?? false) {
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final isMobile = width < _mobileBreakpoint;

    if (_loading) {
      return const Scaffold(
        backgroundColor: AeDashTokens.background,
        body: Center(child: CircularProgressIndicator()),
      );
    }

    if (_error != null) {
      return Scaffold(
        backgroundColor: AeDashTokens.background,
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  _error!,
                  textAlign: TextAlign.center,
                  style: AeDashTokens.body(color: AeDashTokens.text),
                ),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: _logout,
                  style: FilledButton.styleFrom(
                    backgroundColor: AppTheme.brandOrange,
                  ),
                  child: const Text('Back to login'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Scaffold(
      key: _scaffoldKey,
      backgroundColor: AeDashTokens.background,
      drawer: isMobile
          ? Drawer(
              width: 280,
              child: _buildSidebar(expanded: true, isDrawer: true),
            )
          : null,
      body: Row(
        children: [
          if (!isMobile)
            _buildSidebar(expanded: _sidebarExpanded, isDrawer: false),
          Expanded(
            child: Column(
              children: [
                if (isMobile || _currentTab == _AeTab.register)
                  _buildTopHeader(isMobile: isMobile),
                Expanded(
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 220),
                    switchInCurve: Curves.easeOut,
                    switchOutCurve: Curves.easeIn,
                    child: KeyedSubtree(
                      key: ValueKey(_selectedIndex),
                      child: _buildTabBody(),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      bottomNavigationBar: isMobile ? _buildMobileBottomNav() : null,
    );
  }

  static String _tabTitle(_AeTab t) => switch (t) {
        _AeTab.register => 'Register',
        _AeTab.events => 'Events (MICE)',
        _AeTab.insights => 'Insights',
        _AeTab.reports => 'Reports',
        _AeTab.profile => 'Profile',
        _AeTab.settings => 'Settings',
      };

  Widget _buildTopHeader({required bool isMobile}) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.fromLTRB(isMobile ? 12 : 24, 12, isMobile ? 12 : 20, 12),
      decoration: const BoxDecoration(
        color: AeDashTokens.surface,
        border: Border(bottom: BorderSide(color: AeDashTokens.border)),
      ),
      child: SafeArea(
        bottom: false,
        child: Row(
          children: [
            if (isMobile)
              IconButton(
                tooltip: 'Menu',
                onPressed: () => _scaffoldKey.currentState?.openDrawer(),
                icon: const Icon(Icons.menu_rounded, color: AeDashTokens.text),
              ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _currentTab == _AeTab.register
                        ? '$_businessName — DOT register'
                        : _tabTitle(_currentTab),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AeDashTokens.heading(size: isMobile ? 17 : 19),
                  ),
                  Text(
                    [
                      if (_aeType.isNotEmpty) '$_aeType ($_classificationCode)',
                      if (_municipality.isNotEmpty) _municipality,
                      if (_schema.tracksRooms) '$_roomCount rooms',
                    ].join(' · '),
                    style: AeDashTokens.body(size: 12),
                  ),
                ],
              ),
            ),
            _statusPill(compact: true),
          ],
        ),
      ),
    );
  }

  Widget _buildSidebar({required bool expanded, required bool isDrawer}) {
    return EstablishmentSidebar(
      businessName: _businessName,
      subtitle: _municipality.isNotEmpty ? _municipality : _copy.packLabel,
      expanded: expanded,
      width: isDrawer ? 280 : null,
      selectedIndex: _selectedIndex.clamp(0, _tabs.length - 1),
      onSelect: _selectTab,
      onLogout: _logout,
      onToggle: isDrawer
          ? () => Navigator.of(context).maybePop()
          : () => setState(() => _sidebarExpanded = !_sidebarExpanded),
      items: [
        for (final t in _tabs)
          switch (t) {
            _AeTab.register => const EstablishmentNavEntry(
                icon: Icons.table_chart_rounded,
                label: 'Register',
                section: 'Reporting',
              ),
            _AeTab.events => const EstablishmentNavEntry(
                icon: Icons.celebration_rounded,
                label: 'Events (MICE)',
              ),
            _AeTab.insights => const EstablishmentNavEntry(
                icon: Icons.insights_rounded,
                label: 'Insights',
              ),
            _AeTab.reports => const EstablishmentNavEntry(
                icon: Icons.summarize_rounded,
                label: 'Reports',
              ),
            _AeTab.profile => const EstablishmentNavEntry(
                icon: Icons.storefront_rounded,
                label: 'Profile',
                section: 'Account',
              ),
            _AeTab.settings => const EstablishmentNavEntry(
                icon: Icons.settings_rounded,
                label: 'Settings',
              ),
          },
      ],
    );
  }

  /// Bottom bar fits 5 items; Settings moves to the drawer when tabs overflow.
  List<_AeTab> get _bottomTabs {
    final tabs = _tabs;
    return tabs.length <= 5 ? tabs : tabs.where((t) => t != _AeTab.settings).toList();
  }

  Widget _buildMobileBottomNav() {
    final tabs = _bottomTabs;
    final current = tabs.indexOf(_currentTab);
    return NavigationBar(
      selectedIndex: current < 0 ? tabs.indexOf(_AeTab.profile).clamp(0, tabs.length - 1) : current,
      onDestinationSelected: (i) => _selectTab(_tabs.indexOf(tabs[i])),
      indicatorColor: AeDashTokens.softOrange,
      backgroundColor: Colors.white,
      destinations: [
        for (final t in tabs)
          switch (t) {
            _AeTab.register => const NavigationDestination(
                icon: Icon(Icons.table_chart_outlined),
                selectedIcon: Icon(Icons.table_chart_rounded),
                label: 'Register',
              ),
            _AeTab.events => const NavigationDestination(
                icon: Icon(Icons.celebration_outlined),
                selectedIcon: Icon(Icons.celebration_rounded),
                label: 'Events',
              ),
            _AeTab.insights => const NavigationDestination(
                icon: Icon(Icons.insights_outlined),
                selectedIcon: Icon(Icons.insights_rounded),
                label: 'Insights',
              ),
            _AeTab.reports => const NavigationDestination(
                icon: Icon(Icons.summarize_outlined),
                selectedIcon: Icon(Icons.summarize_rounded),
                label: 'Reports',
              ),
            _AeTab.profile => const NavigationDestination(
                icon: Icon(Icons.storefront_outlined),
                selectedIcon: Icon(Icons.storefront_rounded),
                label: 'Profile',
              ),
            _AeTab.settings => const NavigationDestination(
                icon: Icon(Icons.settings_outlined),
                selectedIcon: Icon(Icons.settings_rounded),
                label: 'Settings',
              ),
          },
      ],
    );
  }

  Widget _buildTabBody() {
    if (_uid.isEmpty) {
      return ListView(
        padding: const EdgeInsets.all(24),
        children: [
          Text('Sign in required.', style: AeDashTokens.body(color: AeDashTokens.text)),
        ],
      );
    }
    switch (_currentTab) {
      case _AeTab.register:
        return AeRegisterWorkspace(
          key: ValueKey('register-$_uid-$_roomCount-$_aeType-$_classificationCode'),
          profile: _profile,
          schema: _schema,
          banner: _statusBannerDismissed ? null : _statusBanner(),
          onOpenProfile: () => _selectTab(_tabs.indexOf(_AeTab.profile)),
        );
      case _AeTab.events:
        return MiceRegisterWorkspace(
          key: ValueKey('mice-$_uid'),
          profile: _profile,
          banner: _statusBannerDismissed ? null : _statusBanner(),
        );
      case _AeTab.insights:
        return EstablishmentInsightsBoard(profile: _profile, schema: _schema);
      case _AeTab.reports:
        return _reportsTab();
      case _AeTab.profile:
        return _profileTab();
      case _AeTab.settings:
        return _settingsTab();
    }
  }

  static double _pagePad(double width) =>
      width < 600 ? 14.0 : (width < 1000 ? 18.0 : 24.0);

  Widget _reportsTab() {
    return LayoutBuilder(
      builder: (context, c) {
        final pad = _pagePad(c.maxWidth);
        return ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: EdgeInsets.only(bottom: pad + 12),
          children: [
            AePageHero(
              icon: Icons.summarize_rounded,
              title: 'Reports',
              subtitle: 'Your DOT forms filled from your own register — preview, then download Excel or PDF.',
              flush: true,
            ),
            Padding(
              padding: EdgeInsets.fromLTRB(pad, c.maxWidth < 600 ? 12 : 18, pad, 0),
              child: DotReportExportPanel(
                key: ValueKey('ae-reports-$_uid-${_reportFormIds.join(',')}'),
                primaryColor: AeDashTokens.accent,
                textDark: AeDashTokens.text,
                textMuted: AeDashTokens.muted,
                borderColor: AeDashTokens.border,
                scopeLabel: _municipality.isNotEmpty ? _municipality : _businessName,
                scopeSlug: _municipalityId.isNotEmpty ? _municipalityId : 'establishment',
                isProvincial: false,
                isMobile: c.maxWidth < 700,
                checkIns: const [],
                tourists: const [],
                catalogSpots: const [],
                municipalityId: _municipalityId,
                lockedEstablishment: DotReportEntityOption(
                  id: _uid,
                  name: _businessName,
                  kind: DotReportEntityKind.establishment,
                  municipalityId: _municipalityId,
                  municipalityName: _municipality,
                ),
                allowedFormIds: _reportFormIds,
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _profileTab() {
    return LayoutBuilder(
      builder: (context, c) {
        final pad = _pagePad(c.maxWidth);
        return ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: EdgeInsets.only(bottom: pad + 12),
          children: [
            AePageHero(
              icon: Icons.storefront_rounded,
              title: 'Profile',
              subtitle: 'DOT reporting details, map pin and photos shown to tourists.',
              flush: true,
            ),
            Padding(
              padding: EdgeInsets.fromLTRB(pad, c.maxWidth < 600 ? 12 : 18, pad, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  EstablishmentReportingProfileCard(
                    tracksRooms: _schema.tracksRooms,
                    totalRooms: _roomCount,
                    aeType: _aeType,
                    classificationCode: _classificationCode,
                    hostsMice: _hostsMice,
                    saving: _savingProfile,
                    onSave: _saveReportingProfile,
                  ),
                  const SizedBox(height: 18),
                  SignOffHistoryPanel(
                    ownerId: _uid,
                    subjectType: SignOffSubjects.aeProfile,
                    subjectId: _uid,
                    title: 'Reporting profile sign-offs',
                    emptyText: 'No signed profile changes yet.',
                  ),
                  const SizedBox(height: 18),
                  EstablishmentMapPinCard(
                    latitude: _latitude,
                    longitude: _longitude,
                    locating: _locating,
                    saving: _savingLocation,
                    onBusyChanged: (b) {
                      if (mounted) setState(() => _locating = b);
                    },
                    onChanged: (pin) => _saveMapPin(
                      latitude: pin.latitude,
                      longitude: pin.longitude,
                    ),
                  ),
                  const SizedBox(height: 18),
                  EstablishmentPhotosCard(
                    urls: _galleryUrls,
                    maxImages: EstablishmentGalleryService.maxImages,
                    busy: _galleryBusy,
                    onAdd: _addGalleryPhoto,
                    onRemove: _removeGalleryPhoto,
                  ),
                  if (_isLodging) ...[
                    const SizedBox(height: 18),
                    _lodgingHoursSection(),
                  ],
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _settingsTab() {
    return LayoutBuilder(
      builder: (context, c) {
        final pad = _pagePad(c.maxWidth);
        return ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: EdgeInsets.only(bottom: pad + 12),
          children: [
            EstablishmentSettingsPanel(
              profile: _profile,
              schema: _schema,
              hostsMice: _hostsMice,
              flushHero: true,
              contentPadding: EdgeInsets.fromLTRB(
                pad,
                c.maxWidth < 600 ? 12 : 18,
                pad,
                0,
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _lodgingHoursSection() {
    final cin = EstablishmentLodgingHours.tryParse(_checkInTime);
    final cout = EstablishmentLodgingHours.tryParse(_checkOutTime);
    return EstablishmentHoursCard(
      checkInLabel:
          cin == null ? null : EstablishmentLodgingHours.displayLabel(cin),
      checkOutLabel:
          cout == null ? null : EstablishmentLodgingHours.displayLabel(cout),
      saving: _savingHours,
      onPickCheckIn: _pickAndSaveCheckInTime,
      onPickCheckOut: _pickAndSaveCheckOutTime,
    );
  }

  Widget _statusPill({bool compact = false}) {
    final pillLabel = _isRejected
        ? 'Rejected'
        : _isPending
            ? 'Pending'
            : 'Active';
    final pillBg = _isRejected
        ? const Color(0xFFFEE2E2)
        : _isPending
            ? const Color(0xFFFFF7ED)
            : const Color(0xFFECFDF5);
    final pillFg = _isRejected
        ? const Color(0xFF9F1239)
        : _isPending
            ? const Color(0xFF9A3412)
            : const Color(0xFF065F46);

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 10 : 12,
        vertical: compact ? 5 : 6,
      ),
      decoration: BoxDecoration(
        color: pillBg,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: pillFg.withValues(alpha: 0.25)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            _isRejected
                ? Icons.cancel_rounded
                : _isPending
                    ? Icons.schedule_rounded
                    : Icons.verified_rounded,
            size: 14,
            color: pillFg,
          ),
          const SizedBox(width: 5),
          Text(
            pillLabel,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w800,
              color: pillFg,
            ),
          ),
        ],
      ),
    );
  }

  Widget _statusBanner() {
    void dismiss() => setState(() => _statusBannerDismissed = true);
    if (_isPending) {
      return AeAlertBanner(
        title: 'Pending approval',
        message: 'Registration still pending LGU / Provincial approval — '
            'you can already fill in your register; it is shared once approved.',
        icon: Icons.schedule_rounded,
        color: const Color(0xFFEA580C),
        background: const Color(0xFFFFF7ED),
        borderColor: const Color(0xFFFED7AA),
        onClose: dismiss,
      );
    }
    if (_isRejected) {
      return AeAlertBanner(
        title: 'Registration rejected',
        message: 'Contact your LGU tourism office for next steps.',
        icon: Icons.error_rounded,
        color: AeDashTokens.danger,
        background: const Color(0xFFFEF2F2),
        borderColor: const Color(0xFFFECACA),
        onClose: dismiss,
      );
    }
    return AeAlertBanner(
      title: 'Monthly DOT register',
      message: 'Record each occupied room per night (or use "Add stay"). '
          'Occupancy, ALOS and the DAE-2 / DAE-1B sheets compute automatically. '
          'Submit each month to your LGU.',
      icon: Icons.table_chart_rounded,
      color: AeDashTokens.success,
      background: const Color(0xFFECFDF5),
      borderColor: const Color(0xFFD1FAE5),
      onClose: dismiss,
    );
  }
}

enum _AeTab { register, events, insights, reports, profile, settings }

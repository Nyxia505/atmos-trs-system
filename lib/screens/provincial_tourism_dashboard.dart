import 'dart:async' show unawaited;

import 'package:atmos_trs_system/config/auth_config.dart';
import 'package:atmos_trs_system/config/module_shell_prefs.dart';
import 'package:atmos_trs_system/config/session_storage.dart';
import 'package:atmos_trs_system/data/misamis_occidental_municipalities.dart';
import 'package:atmos_trs_system/features/governor/theme/governor_dashboard_tokens.dart';
import 'package:atmos_trs_system/features/governor/widgets/charts/governor_age_bar_chart.dart';
import 'package:atmos_trs_system/features/governor/widgets/charts/governor_arrivals_area_chart.dart';
import 'package:atmos_trs_system/features/governor/widgets/charts/governor_donut_chart.dart';
import 'package:atmos_trs_system/features/governor/widgets/governor_glass_header.dart';
import 'package:atmos_trs_system/features/governor/widgets/governor_sidebar.dart';
import 'package:atmos_trs_system/features/provincial_tourism/widgets/provincial_quick_actions.dart';
import 'package:atmos_trs_system/navigation/post_logout_navigation.dart';
import 'package:atmos_trs_system/services/auth_service.dart';
import 'package:atmos_trs_system/services/governor_firestore_service.dart';
import 'package:atmos_trs_system/services/provincial_tourism_service.dart';
import 'package:atmos_trs_system/services/user_directory_service.dart';
import 'package:atmos_trs_system/utils/dot_var2_visitor_record_report.dart';
import 'package:atmos_trs_system/utils/municipality_helper.dart';
import 'package:atmos_trs_system/utils/provincial_report_builder.dart';
import 'package:atmos_trs_system/utils/visit_stats.dart';
import 'package:atmos_trs_system/widgets/dot_report_export_panel.dart';
import 'package:atmos_trs_system/widgets/optaca_accounts_panel.dart';
import 'package:atmos_trs_system/widgets/optaca_alerts_quality_panel.dart';
import 'package:atmos_trs_system/widgets/optaca_establishment_review_panel.dart';
import 'package:atmos_trs_system/widgets/optaca_stakeholder_reports_panel.dart';
import 'package:atmos_trs_system/widgets/optaca_trip_planner_catalog.dart';
import 'package:atmos_trs_system/widgets/report_export_preview.dart';
import 'package:atmos_trs_system/widgets/ui_skeleton.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import 'package:atmos_trs_system/config/app_theme.dart';
import 'package:atmos_trs_system/widgets/lgu_debug_data_dialogs.dart';

const String _kOptacaLogoAsset = 'assets/images/tourism logo.png';
const String _kCapitolPhotoAsset = 'assets/images/capitol.webp';

class ProvincialTourismDashboard extends StatefulWidget {
  const ProvincialTourismDashboard({super.key});

  @override
  State<ProvincialTourismDashboard> createState() =>
      _ProvincialTourismDashboardState();
}

class _ProvincialTourismDashboardState extends State<ProvincialTourismDashboard> {
  final _service = ProvincialTourismService();
  final _searchController = TextEditingController();

  int _selectedIndex = 0;
  bool _isSidebarExpanded = true;
  bool _isBootstrapping = true;
  bool _isLoading = true;
  String? _errorMessage;
  String _selectedTimeFilter = 'This Month';
  String _profileName = 'Provincial Tourism';
  String _profileEmail = SessionStorage.provincialTourismEmail;

  List<Map<String, dynamic>> _tourists = [];
  List<Map<String, dynamic>> _checkIns = [];
  List<Map<String, dynamic>> _spots = [];
  List<Map<String, dynamic>> _announcements = [];
  List<Map<String, dynamic>> _campaigns = [];
  Set<String> _ackAlertIds = {};

  // Insights
  String _insightSearch = '';

  // Performance selection
  String? _selectedMunicipalityId;

  // Reports
  DateTime _reportStart =
      DateTime(DateTime.now().year, DateTime.now().month, 1);
  DateTime _reportEnd = DateTime.now();
  String _reportType = 'DOT Visitor to Attraction Report';
  String _reportMunicipality = 'All';
  bool _isExporting = false;

  // Settings
  bool _emailNotifications = true;
  bool _pushNotifications = true;
  bool _weeklyReports = true;
  final _currentPwController = TextEditingController();
  final _newPwController = TextEditingController();
  final _confirmPwController = TextEditingController();

  static const _navItems = [
    _NavItem(Icons.dashboard_rounded, 'Dashboard'),
    _NavItem(Icons.place_rounded, 'Destinations'),
    _NavItem(Icons.location_city_rounded, 'Municipality Performance'),
    _NavItem(Icons.insights_rounded, 'Tourist Insights'),
    _NavItem(Icons.event_rounded, 'Events & Campaigns'),
    _NavItem(Icons.route_rounded, 'Trip Planner'),
    _NavItem(Icons.assessment_rounded, 'DOT Reports'),
    _NavItem(Icons.hotel_rounded, 'Establishments'),
    _NavItem(Icons.manage_accounts_rounded, 'Accounts'),
    _NavItem(Icons.warning_amber_rounded, 'Alerts & Quality'),
    _NavItem(Icons.settings_rounded, 'Settings'),
  ];

  static const _dashboardIndex = 0;
  static const _destinationsIndex = 1;
  static const _performanceIndex = 2;
  static const _insightsIndex = 3;
  static const _eventsIndex = 4;
  static const _tripPlannerIndex = 5;
  static const _reportsIndex = 6;
  static const _establishmentsIndex = 7;
  static const _accountsIndex = 8;
  static const _alertsIndex = 9;
  static const _settingsIndex = 10;
  static const _bottomNavItemCount = 5;

  static const _reportTypes = [
    'DOT Visitor to Attraction Report',
    'DOT Tourism Attraction Visitor Record (VAR 2)',
    'DOT Accommodation Establishment Data',
    'All Data',
    'Summary by Municipality',
  ];

  bool get _isMobile => MediaQuery.sizeOf(context).width < 900;

  @override
  void initState() {
    super.initState();
    unawaited(_bootstrap());
  }

  @override
  void dispose() {
    _searchController.dispose();
    _currentPwController.dispose();
    _newPwController.dispose();
    _confirmPwController.dispose();
    super.dispose();
  }

  Future<void> _bootstrap() async {
    unawaited(
      ModuleShellPrefs.setActiveShell(ModuleShellPrefs.provincialTourism),
    );
    final email = await SessionStorage.getStoredEmail();
    if (email != null && email.isNotEmpty) {
      _profileEmail = email;
    }
    final profile = await UserDirectoryService.getProfileByUid(
      FirebaseAuth.instance.currentUser?.uid ?? '',
      preferServer: false,
    );
    if (profile?.fullName != null && profile!.fullName!.trim().isNotEmpty) {
      _profileName = profile.fullName!.trim();
    }
    _ackAlertIds = await ProvincialTourismService.loadAcknowledgedAlertIds();
    // Show shell immediately so the page is never stuck on a blank/skeleton frame.
    if (mounted) {
      setState(() {
        _isBootstrapping = false;
        _isLoading = false;
      });
    }
    await _loadData();
  }

  Future<void> _loadData() async {
    if (mounted) {
      setState(() {
        _isLoading = true;
        _errorMessage = null;
      });
    }
    try {
      final snap = await _service.loadSnapshot(includeCheckIns: true);
      if (!mounted) return;
      setState(() {
        _tourists = snap.tourists;
        _checkIns = snap.checkIns;
        _spots = snap.spots;
        _announcements = snap.announcements;
        _campaigns = snap.campaigns;
        _isBootstrapping = false;
        _isLoading = false;
      });
    } catch (e, st) {
      debugPrint('ProvincialTourism _loadData: $e\n$st');
      if (!mounted) return;
      setState(() {
        _isBootstrapping = false;
        _isLoading = false;
        _errorMessage = 'Could not load provincial tourism data.';
      });
    }
  }

  List<Map<String, dynamic>> get _periodCheckIns {
    final range =
        ProvincialTourismService.rangeForFilter(_selectedTimeFilter);
    return ProvincialTourismService.checkInsInRange(
      _checkIns,
      range.start,
      range.end,
    );
  }

  int get _pendingEvents =>
      ProvincialTourismService.pendingEventsCount(_announcements);

  int get _activeDestinations => _spots.where((s) {
        final status = (s['status']?.toString() ?? 'active').toLowerCase();
        return status != 'inactive' && status != 'closed';
      }).length;

  int get _lgusReporting {
    final ids = <String>{};
    for (final c in _periodCheckIns) {
      final id = ProvincialTourismService.municipalityIdOf(c);
      if (id.isNotEmpty) ids.add(id);
    }
    return ids.length;
  }

  List<ProvincialMunicipalityStats> get _muniStats =>
      ProvincialTourismService.municipalityPerformance(
        checkIns: _checkIns,
        spots: _spots,
        timeFilter: _selectedTimeFilter,
      );

  List<ProvincialAlert> get _alerts => ProvincialTourismService.buildAlerts(
        checkIns: _checkIns,
        spots: _spots,
        announcements: _announcements,
        timeFilter: _selectedTimeFilter,
        acknowledgedIds: _ackAlertIds,
      );

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

  void _go(int index) => setState(() => _selectedIndex = index);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: GovernorDashboardTokens.background,
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

  List<GovernorNavItemData> get _sidebarItems => [
        for (var i = 0; i < _navItems.length; i++)
          GovernorNavItemData(
            label: _navItems[i].label,
            icon: _navItems[i].icon,
            badgeCount: i == _eventsIndex
                ? _pendingEvents
                : (i == _alertsIndex ? _alerts.length : 0),
          ),
      ];

  Widget _buildSidebar() {
    return GovernorSidebar(
      expanded: _isSidebarExpanded,
      selectedIndex: _selectedIndex,
      items: _sidebarItems,
      onSelect: _go,
      onToggle: () => setState(() => _isSidebarExpanded = !_isSidebarExpanded),
      onLogout: _logout,
      brandLogoAsset: _kOptacaLogoAsset,
      footerImageAsset: _kCapitolPhotoAsset,
      brandTitle: 'Provincial Tourism',
      brandSubtitle: 'Misamis Occidental',
      profileName: _profileName,
      profileSubtitle: 'Provincial Tourism Office',
    );
  }

  Widget _buildDrawer() {
    return GovernorSidebar(
      asDrawer: true,
      expanded: true,
      selectedIndex: _selectedIndex,
      items: _sidebarItems,
      onSelect: (i) {
        _go(i);
        Navigator.of(context).maybePop();
      },
      onToggle: () => Navigator.of(context).maybePop(),
      onLogout: _logout,
      brandLogoAsset: _kOptacaLogoAsset,
      footerImageAsset: _kCapitolPhotoAsset,
      brandTitle: 'Provincial Tourism',
      brandSubtitle: 'Misamis Occidental',
      profileName: _profileName,
      profileSubtitle: 'Provincial Tourism Office',
    );
  }

  Widget _buildBottomNav() {
    const selectedBg = Color(0xFFFFF7ED);
    const selectedFg = Color(0xFFC2410C);
    const unselected = Color(0xFF64748B);
    return Material(
      color: GovernorDashboardTokens.card,
      elevation: 8,
      child: SafeArea(
        top: false,
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.fromLTRB(8, 10, 8, 10),
          child: Row(
            children: List.generate(_bottomNavItemCount, (index) {
              final item = _navItems[index];
              final selected = _selectedIndex == index;
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 2),
                child: InkWell(
                  onTap: () => _go(index),
                  borderRadius: BorderRadius.circular(18),
                  child: Container(
                    width: 84,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      color: selected ? selectedBg : Colors.transparent,
                      borderRadius: BorderRadius.circular(18),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          item.icon,
                          size: 22,
                          color: selected ? selectedFg : unselected,
                        ),
                        const SizedBox(height: 6),
                        Text(
                          item.label,
                          textAlign: TextAlign.center,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight:
                                selected ? FontWeight.w700 : FontWeight.w500,
                            color: selected ? selectedFg : unselected,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            }),
          ),
        ),
      ),
    );
  }

  Widget _buildMainContent() {
    if (_errorMessage != null && _tourists.isEmpty && _spots.isEmpty) {
      return ColoredBox(
        color: GovernorDashboardTokens.background,
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(_errorMessage!, style: GovernorDashboardTokens.body()),
                const SizedBox(height: 12),
                FilledButton(onPressed: _loadData, child: const Text('Retry')),
              ],
            ),
          ),
        ),
      );
    }

    final showSkeleton = _isBootstrapping && _isLoading;

    return ColoredBox(
      color: GovernorDashboardTokens.background,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          GovernorGlassHeader(
            title: 'Provincial Tourism',
            greeting:
                '${GovernorDashboardTokens.greetingEmoji()} GOOD DAY, PROVINCIAL TOURISM!',
            subtitle: 'Misamis Occidental Tourism Office · $_profileEmail',
            compact: _isMobile,
            leading: _isMobile
                ? Builder(
                    builder: (ctx) => IconButton(
                      onPressed: () => Scaffold.of(ctx).openDrawer(),
                      icon: const Icon(Icons.menu_rounded, color: Colors.white),
                    ),
                  )
                : null,
            searchController: _searchController,
            onSearchChanged: (q) {
              setState(() {
                if (_selectedIndex == _insightsIndex) {
                  _insightSearch = q;
                }
              });
            },
            searchHint: 'Search tourists, municipalities...',
            notificationCount: (_alerts.length + _pendingEvents).clamp(0, 99),
            onNotifications: () => _go(_alertsIndex),
          ),
          Expanded(
            child: showSkeleton
                ? const DashboardContentSkeleton()
                : Material(
                    color: GovernorDashboardTokens.background,
                    child: _safeTabBody(),
                  ),
          ),
        ],
      ),
    );
  }

  /// Isolates tab build failures so a chart/layout error cannot blank the page.
  Widget _safeTabBody() {
    try {
      return _buildSelectedTab();
    } catch (e, st) {
      debugPrint('ProvincialTourism tab build failed: $e\n$st');
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(24),
        children: [
          Text('Dashboard content error',
              style: GovernorDashboardTokens.heading(size: 18)),
          const SizedBox(height: 8),
          Text('$e', style: GovernorDashboardTokens.body()),
          const SizedBox(height: 16),
          FilledButton(onPressed: _loadData, child: const Text('Reload data')),
        ],
      );
    }
  }

  Widget _buildSelectedTab() {
    return switch (_selectedIndex) {
      _dashboardIndex => _buildDashboardTab(),
      _destinationsIndex => _buildDestinationsTab(),
      _performanceIndex => _buildPerformanceTab(),
      _insightsIndex => _buildInsightsTab(),
      _eventsIndex => _buildEventsTab(),
      _tripPlannerIndex => _buildTripPlannerTab(),
      _reportsIndex => _buildReportsTab(),
      _establishmentsIndex => _buildEstablishmentsTab(),
      _accountsIndex => const OptacaAccountsPanel(),
      _alertsIndex => _buildAlertsTab(),
      _settingsIndex => _buildSettingsTab(),
      _ => _buildDashboardTab(),
    };
  }

  Widget _buildEstablishmentsTab() {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
      children: const [
        OptacaEstablishmentReviewPanel(),
      ],
    );
  }

  Widget _simpleKpi({
    required String title,
    required String value,
    required IconData icon,
    required Color accent,
    String? subtitle,
  }) {
    return Container(
      constraints: const BoxConstraints(minHeight: 88),
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
      decoration: BoxDecoration(
        color: GovernorDashboardTokens.card,
        borderRadius: BorderRadius.circular(GovernorDashboardTokens.radiusCard),
        border: Border.all(color: GovernorDashboardTokens.border),
        boxShadow: GovernorDashboardTokens.cardShadow,
      ),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: accent.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: accent, size: 22),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(title, style: GovernorDashboardTokens.body(size: 12)),
                const SizedBox(height: 2),
                Text(value, style: GovernorDashboardTokens.number(size: 22)),
                if (subtitle != null && subtitle.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(subtitle, style: GovernorDashboardTokens.body(size: 11)),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _kpiGrid({
    required List<Widget> children,
  }) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final w = constraints.maxWidth;
        final crossAxisCount = w >= 1100
            ? 4
            : w >= 700
                ? 2
                : 1;
        if (crossAxisCount == 1) {
          return Column(
            children: [
              for (var i = 0; i < children.length; i++) ...[
                if (i > 0) const SizedBox(height: 10),
                children[i],
              ],
            ],
          );
        }
        final rows = <Widget>[];
        for (var i = 0; i < children.length; i += crossAxisCount) {
          final slice = children.sublist(
            i,
            (i + crossAxisCount).clamp(0, children.length),
          );
          rows.add(
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (var j = 0; j < crossAxisCount; j++) ...[
                  if (j > 0) const SizedBox(width: 12),
                  Expanded(
                    child: j < slice.length ? slice[j] : const SizedBox.shrink(),
                  ),
                ],
              ],
            ),
          );
          if (i + crossAxisCount < children.length) {
            rows.add(const SizedBox(height: 12));
          }
        }
        return Column(children: rows);
      },
    );
  }

  Widget _responsivePair(Widget left, Widget right) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 900) {
          return Column(
            children: [
              left,
              const SizedBox(height: 12),
              right,
            ],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: left),
            const SizedBox(width: 12),
            Expanded(child: right),
          ],
        );
      },
    );
  }

  Widget _rankColumn(List<({String name, int count})> rows) {
    if (rows.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(12),
        child: Text(
          'No data yet for this period',
          style: GovernorDashboardTokens.body(size: 12.5),
        ),
      );
    }
    final maxCount =
        rows.map((e) => e.count).reduce((a, b) => a > b ? a : b).clamp(1, 1 << 30);
    return Column(
      children: [
        for (var i = 0; i < rows.length; i++) ...[
          if (i > 0) const SizedBox(height: 8),
          Row(
            children: [
              SizedBox(
                width: 22,
                child: Text(
                  '${i + 1}',
                  style: GovernorDashboardTokens.sectionTitle(size: 12),
                ),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      rows[i].name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GovernorDashboardTokens.sectionTitle(size: 12.5),
                    ),
                    const SizedBox(height: 4),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(99),
                      child: LinearProgressIndicator(
                        value: rows[i].count / maxCount,
                        minHeight: 6,
                        backgroundColor: GovernorDashboardTokens.mutedSurface,
                        color: GovernorDashboardTokens.primary,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '${rows[i].count}',
                style: GovernorDashboardTokens.sectionTitle(size: 12),
              ),
            ],
          ),
        ],
      ],
    );
  }

  Widget _panel(Widget child, {EdgeInsetsGeometry? padding}) {
    return Container(
      width: double.infinity,
      padding: padding ?? const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: GovernorDashboardTokens.card,
        borderRadius: BorderRadius.circular(GovernorDashboardTokens.radiusCard),
        border: Border.all(color: GovernorDashboardTokens.border),
        boxShadow: GovernorDashboardTokens.cardShadow,
      ),
      child: child,
    );
  }

  Widget _timeFilters() {
    const filters = ['This Week', 'This Month', 'This Year'];
    return Wrap(
      spacing: 8,
      children: [
        for (final f in filters)
          FilterChip(
            label: Text(f),
            selected: _selectedTimeFilter == f,
            onSelected: (_) => setState(() => _selectedTimeFilter = f),
            selectedColor: GovernorDashboardTokens.softOrange,
            checkmarkColor: GovernorDashboardTokens.primaryDark,
          ),
      ],
    );
  }

  // ─── Dashboard ───────────────────────────────────────────────
  Widget _buildDashboardTab() {
    final period = _periodCheckIns;
    final byDay = ProvincialTourismService.arrivalsByDay(period, days: 14);
    final lf = ProvincialTourismService.localForeignCounts(_tourists);
    final gender = ProvincialTourismService.genderCounts(_tourists);
    final ages = ProvincialTourismService.ageBands(_tourists);
    final tops = ProvincialTourismService.topDestinations(
      checkIns: period,
      spots: _spots,
      limit: 5,
    );
    final under = _muniStats.where((m) => m.isUnderperforming).take(5).toList();
    final activity = _recentActivity();
    final muniTotal = getMisamisOccidentalMunicipalities().length;
    final ranking = _muniStats
        .take(8)
        .map((m) => (name: m.name, count: m.arrivals))
        .toList();

    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
      children: [
        Wrap(
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 12,
          runSpacing: 8,
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Overview', style: GovernorDashboardTokens.heading(size: 20)),
                const SizedBox(height: 2),
                Text(
                  'Province-wide tourism snapshot for Misamis Occidental',
                  style: GovernorDashboardTokens.body(size: 12.5),
                ),
              ],
            ),
            _timeFilters(),
          ],
        ),
        const SizedBox(height: 16),
        _kpiGrid(
          children: [
            _simpleKpi(
              title: 'Total visitors',
              value: '${VisitStats.fromCheckIns(period).visitors}',
              icon: Icons.groups_rounded,
              accent: GovernorDashboardTokens.primary,
              subtitle:
                  '${VisitStats.fromCheckIns(period).checkIns} check-ins · $_selectedTimeFilter',
            ),
            _simpleKpi(
              title: 'Active destinations',
              value: '$_activeDestinations',
              icon: Icons.place_rounded,
              accent: const Color(0xFF3B82F6),
            ),
            _simpleKpi(
              title: 'LGUs reporting',
              value: '$_lgusReporting / $muniTotal',
              icon: Icons.location_city_rounded,
              accent: const Color(0xFF22C55E),
            ),
            _simpleKpi(
              title: 'Pending events',
              value: '$_pendingEvents',
              icon: Icons.event_rounded,
              accent: const Color(0xFFEA580C),
              subtitle: '${_campaigns.length} campaigns',
            ),
          ],
        ),
        const SizedBox(height: 14),
        ProvincialQuickActions(
          onGenerateDotReport: () => _go(_reportsIndex),
          onReviewEvents: () => _go(_eventsIndex),
          onViewUnderperforming: () {
            setState(() {
              _selectedIndex = _performanceIndex;
              _selectedMunicipalityId =
                  under.isNotEmpty ? under.first.id : null;
            });
          },
          onOpenDestinations: () => _go(_destinationsIndex),
        ),
        const SizedBox(height: 16),
        Text('Insights', style: GovernorDashboardTokens.heading(size: 18)),
        const SizedBox(height: 10),
        _responsivePair(
          _panel(
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Arrivals trend',
                    style: GovernorDashboardTokens.sectionTitle()),
                const SizedBox(height: 8),
                SizedBox(
                  height: 200,
                  child: GovernorArrivalsAreaChart(
                    values: byDay.map((e) => e.count.toDouble()).toList(),
                    labels: byDay
                        .map((e) => '${e.day.month}/${e.day.day}')
                        .toList(),
                  ),
                ),
              ],
            ),
          ),
          _panel(
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Local vs foreign',
                    style: GovernorDashboardTokens.sectionTitle()),
                const SizedBox(height: 8),
                SizedBox(
                  height: 200,
                  child: GovernorDonutChart(
                    segments: [
                      GovernorDonutSegment(
                        label: 'Local',
                        value: (lf['local'] ?? 0).toDouble(),
                        color: GovernorDashboardTokens.primary,
                      ),
                      GovernorDonutSegment(
                        label: 'Foreign',
                        value: (lf['foreign'] ?? 0).toDouble(),
                        color: const Color(0xFF3B82F6),
                      ),
                    ],
                    centerLabel: '${_tourists.length}',
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        _responsivePair(
          _panel(
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Top destinations',
                    style: GovernorDashboardTokens.sectionTitle()),
                const SizedBox(height: 8),
                _rankColumn([
                  for (final t in tops) (name: t.name, count: t.count),
                ]),
              ],
            ),
          ),
          _panel(
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Municipality ranking',
                    style: GovernorDashboardTokens.sectionTitle()),
                const SizedBox(height: 8),
                _rankColumn(ranking),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        _responsivePair(
          _panel(
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Age & gender',
                    style: GovernorDashboardTokens.sectionTitle()),
                const SizedBox(height: 8),
                Text(
                  'M ${gender['male'] ?? 0} · F ${gender['female'] ?? 0} · Other ${gender['others'] ?? 0}',
                  style: GovernorDashboardTokens.body(),
                ),
                const SizedBox(height: 8),
                SizedBox(
                  height: 180,
                  child: GovernorAgeBarChart(
                    series: [
                      for (final a in ages)
                        (
                          label: a.label,
                          male: 0,
                          female: 0,
                          others: a.count,
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          _panel(
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Recent activity',
                    style: GovernorDashboardTokens.sectionTitle()),
                const SizedBox(height: 10),
                if (activity.isEmpty)
                  Text('No recent activity yet.',
                      style: GovernorDashboardTokens.body())
                else
                  ...activity.take(8).map(
                        (a) => ListTile(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          leading: Icon(a.$1,
                              color: GovernorDashboardTokens.primary),
                          title: Text(a.$2,
                              style: GovernorDashboardTokens.sectionTitle(
                                  size: 13)),
                          subtitle: Text(a.$3,
                              style: GovernorDashboardTokens.body(size: 12)),
                        ),
                      ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  List<(IconData, String, String)> _recentActivity() {
    final items = <(IconData, String, String, DateTime)>[];
    for (final c in _checkIns.take(40)) {
      final t = GovernorFirestoreService.parseCheckInTime(c);
      if (t == null) continue;
      final spot = c['spot_name']?.toString() ??
          c['spotName']?.toString() ??
          'Spot check-in';
      final muni = ProvincialTourismService.municipalityNameOf(
        ProvincialTourismService.municipalityIdOf(c),
      );
      items.add((Icons.qr_code_scanner_rounded, spot, muni, t));
    }
    for (final a in _announcements.take(20)) {
      final t = a['updatedAt'] is Timestamp
          ? (a['updatedAt'] as Timestamp).toDate()
          : (a['createdAt'] is Timestamp
              ? (a['createdAt'] as Timestamp).toDate()
              : null);
      if (t == null) continue;
      final status = a['status']?.toString() ?? '';
      items.add((
        Icons.event_rounded,
        a['title']?.toString() ?? 'Event',
        'Status: $status',
        t,
      ));
    }
    for (final s in _spots.take(20)) {
      final t = s['createdAt'] is Timestamp
          ? (s['createdAt'] as Timestamp).toDate()
          : null;
      if (t == null) continue;
      items.add((
        Icons.add_location_alt_rounded,
        s['name']?.toString() ?? 'New spot',
        ProvincialTourismService.municipalityNameOf(
          ProvincialTourismService.municipalityIdOf(s),
        ),
        t,
      ));
    }
    items.sort((a, b) => b.$4.compareTo(a.$4));
    return [
      for (final i in items.take(12)) (i.$1, i.$2, i.$3),
    ];
  }

  // ─── Destinations (view-only LGU catalog) ─────────────────────
  Widget _tabHeader({
    required IconData icon,
    required String title,
    required String subtitle,
    Widget? trailing,
  }) {
    final heading = Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            gradient: GovernorDashboardTokens.primaryGradient,
            borderRadius: BorderRadius.circular(14),
            boxShadow: [
              BoxShadow(
                color: GovernorDashboardTokens.primary.withValues(alpha: 0.28),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Icon(icon, color: Colors.white, size: 22),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: GovernorDashboardTokens.heading(size: 20)),
              const SizedBox(height: 2),
              Text(subtitle, style: GovernorDashboardTokens.body(size: 13)),
            ],
          ),
        ),
      ],
    );
    if (trailing == null) return heading;
    if (_isMobile) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [heading, const SizedBox(height: 12), trailing],
      );
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(child: heading),
        const SizedBox(width: 12),
        trailing,
      ],
    );
  }

  Widget _emptyMessage({
    required IconData icon,
    required String title,
    required String message,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 20),
      child: Column(
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: GovernorDashboardTokens.softOrange,
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: GovernorDashboardTokens.primaryDark),
          ),
          const SizedBox(height: 10),
          Text(title, style: GovernorDashboardTokens.sectionTitle()),
          const SizedBox(height: 3),
          Text(
            message,
            textAlign: TextAlign.center,
            style: GovernorDashboardTokens.body(size: 12.5),
          ),
        ],
      ),
    );
  }

  Widget _buildDestinationsTab() {
    return const OptacaTripPlannerCatalog(
      showSectionTabs: false,
      initialTabIndex: 0,
    );
  }

  // ─── Trip Planner: Destinations + Virtual Tour (view-only) ───
  Widget _buildTripPlannerTab() {
    return const OptacaTripPlannerCatalog(
      showSectionTabs: true,
      initialTabIndex: 0,
    );
  }

  // ─── Municipality performance ────────────────────────────────
  Widget _growthChip(ProvincialMunicipalityStats m, {bool onDark = false}) {
    if (m.arrivals == 0 && m.previousArrivals == 0) {
      return Text(
        '—',
        style: GovernorDashboardTokens.body(
          size: 12,
          color: onDark ? Colors.white70 : GovernorDashboardTokens.subtitle,
        ),
      );
    }
    final g = m.growthPercent;
    final up = g >= 0;
    final color = up ? const Color(0xFF16A34A) : GovernorDashboardTokens.danger;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: onDark ? Colors.white : color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(99),
      ),
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              up ? Icons.arrow_upward_rounded : Icons.arrow_downward_rounded,
              size: 11,
              color: color,
            ),
            const SizedBox(width: 2),
            Text(
              '${g.abs().toStringAsFixed(0)}%',
              maxLines: 1,
              softWrap: false,
              style:
                  GovernorDashboardTokens.sectionTitle(size: 10.5, color: color),
            ),
          ],
        ),
      ),
    );
  }

  Widget _gradientBar(double fraction, {double height = 6}) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(99),
      child: Container(
        height: height,
        color: GovernorDashboardTokens.mutedSurface,
        alignment: Alignment.centerLeft,
        child: FractionallySizedBox(
          widthFactor: fraction.clamp(0.0, 1.0),
          child: Container(
            decoration: BoxDecoration(
              gradient: GovernorDashboardTokens.primaryGradient,
              borderRadius: BorderRadius.circular(99),
            ),
          ),
        ),
      ),
    );
  }

  Widget _rankBadge(int rank, {required bool hasData}) {
    final medal = !hasData
        ? null
        : switch (rank) {
            1 => const Color(0xFFF59E0B),
            2 => const Color(0xFF94A3B8),
            3 => const Color(0xFFB45309),
            _ => null,
          };
    return Container(
      width: 26,
      height: 26,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: medal ?? GovernorDashboardTokens.mutedSurface,
        shape: BoxShape.circle,
      ),
      child: Text(
        '$rank',
        style: GovernorDashboardTokens.sectionTitle(
          size: 11.5,
          color: medal != null ? Colors.white : GovernorDashboardTokens.subtitle,
        ),
      ),
    );
  }

  Widget _perfRankRow(
    int rank,
    ProvincialMunicipalityStats m,
    int maxArrivals, {
    required bool selected,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () => setState(() => _selectedMunicipalityId = m.id),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              color: selected
                  ? GovernorDashboardTokens.softOrange.withValues(alpha: 0.7)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: selected
                    ? GovernorDashboardTokens.primary.withValues(alpha: 0.45)
                    : Colors.transparent,
              ),
            ),
            child: Row(
              children: [
                _rankBadge(rank, hasData: m.arrivals > 0),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              m.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: GovernorDashboardTokens.sectionTitle(
                                size: 13,
                              ),
                            ),
                          ),
                          if (m.isUnderperforming) ...[
                            Icon(
                              Icons.flag_rounded,
                              size: 13,
                              color: GovernorDashboardTokens.danger
                                  .withValues(alpha: 0.75),
                            ),
                            const SizedBox(width: 6),
                          ],
                          Text(
                            '${m.arrivals}',
                            style: GovernorDashboardTokens.sectionTitle(
                              size: 13,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 5),
                      _gradientBar(m.arrivals / maxArrivals),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                SizedBox(
                  width: 64,
                  child: Align(
                    alignment: Alignment.centerRight,
                    child: _growthChip(m),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPerformanceTab() {
    final stats = _muniStats;
    ProvincialMunicipalityStats? selected;
    for (final m in stats) {
      if (m.id == _selectedMunicipalityId) {
        selected = m;
        break;
      }
    }
    selected ??= stats.isNotEmpty ? stats.first : null;

    final totalArrivals = stats.fold<int>(0, (a, m) => a + m.arrivals);
    final activeLgus = stats.where((m) => m.arrivals > 0).length;
    final flagged = stats.where((m) => m.isUnderperforming).length;
    ProvincialMunicipalityStats? leader;
    for (final m in stats) {
      if (m.arrivals > 0 && (leader == null || m.arrivals > leader.arrivals)) {
        leader = m;
      }
    }
    final maxArrivals = (leader?.arrivals ?? 0).clamp(1, 1 << 30);

    final ranking = _panel(
      Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(
                Icons.leaderboard_rounded,
                size: 18,
                color: GovernorDashboardTokens.primary,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'LGU ranking by arrivals',
                  style: GovernorDashboardTokens.sectionTitle(),
                ),
              ),
              Text(
                '${stats.length} LGUs',
                style: GovernorDashboardTokens.body(size: 12),
              ),
            ],
          ),
          const SizedBox(height: 2),
          Text(
            'Tap an LGU to view its details.',
            style: GovernorDashboardTokens.body(size: 12),
          ),
          const SizedBox(height: 12),
          if (stats.isEmpty)
            _emptyMessage(
              icon: Icons.location_city_rounded,
              title: 'No LGU data yet',
              message: 'Arrivals appear once QR check-ins come in.',
            )
          else
            for (var i = 0; i < stats.length; i++)
              _perfRankRow(
                i + 1,
                stats[i],
                maxArrivals,
                selected: stats[i].id == selected?.id,
              ),
        ],
      ),
    );

    final detail = selected == null
        ? _panel(
            _emptyMessage(
              icon: Icons.touch_app_rounded,
              title: 'Select an LGU',
              message: 'Pick a municipality from the ranking.',
            ),
          )
        : _panel(_municipalityDetail(selected), padding: const EdgeInsets.all(14));

    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
      children: [
        _tabHeader(
          icon: Icons.location_city_rounded,
          title: 'Municipality Performance',
          subtitle: 'Arrivals ranking and health of each LGU · $_selectedTimeFilter',
          trailing: _timeFilters(),
        ),
        const SizedBox(height: 16),
        _kpiGrid(
          children: [
            _simpleKpi(
              title: 'Total arrivals',
              value: '$totalArrivals',
              icon: Icons.groups_rounded,
              accent: GovernorDashboardTokens.primary,
              subtitle: 'QR check-ins · $_selectedTimeFilter',
            ),
            _simpleKpi(
              title: 'LGUs with arrivals',
              value: '$activeLgus / ${stats.length}',
              icon: Icons.location_city_rounded,
              accent: const Color(0xFF22C55E),
            ),
            _simpleKpi(
              title: 'Top LGU',
              value: leader?.name ?? '—',
              icon: Icons.emoji_events_rounded,
              accent: const Color(0xFFF59E0B),
              subtitle: leader == null
                  ? 'No arrivals yet'
                  : '${leader.arrivals} arrivals',
            ),
            _simpleKpi(
              title: 'Flagged LGUs',
              value: '$flagged',
              icon: Icons.flag_rounded,
              accent: GovernorDashboardTokens.danger,
              subtitle: 'Zero activity or down ≥25%',
            ),
          ],
        ),
        const SizedBox(height: 14),
        LayoutBuilder(
          builder: (context, c) {
            if (c.maxWidth < 1000) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [ranking, const SizedBox(height: 14), detail],
              );
            }
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(flex: 5, child: ranking),
                const SizedBox(width: 14),
                Expanded(flex: 6, child: detail),
              ],
            );
          },
        ),
      ],
    );
  }

  Widget _metricTile({
    required IconData icon,
    required String label,
    required String value,
    required Color accent,
    Widget? footer,
  }) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: GovernorDashboardTokens.background,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: GovernorDashboardTokens.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icon, size: 16, color: accent),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GovernorDashboardTokens.body(size: 12),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(value, style: GovernorDashboardTokens.number(size: 22)),
          if (footer != null) ...[const SizedBox(height: 6), footer],
        ],
      ),
    );
  }

  Widget _municipalityDetail(ProvincialMunicipalityStats m) {
    final tops = ProvincialTourismService.topDestinations(
      checkIns: _periodCheckIns
          .where((c) => ProvincialTourismService.municipalityIdOf(c) == m.id)
          .toList(),
      spots: _spots
          .where((s) => ProvincialTourismService.municipalityIdOf(s) == m.id)
          .toList(),
      limit: 5,
    );
    final growth = m.growthPercent;
    final growthColor = m.arrivals == 0 && m.previousArrivals == 0
        ? GovernorDashboardTokens.subtitle
        : growth >= 0
            ? const Color(0xFF16A34A)
            : GovernorDashboardTokens.danger;
    final spotRatio = m.spotCount == 0 ? 0.0 : m.activeSpotCount / m.spotCount;
    final topMax = tops.isEmpty
        ? 1
        : tops.map((t) => t.count).reduce((a, b) => a > b ? a : b).clamp(1, 1 << 30);

    final (statusLabel, statusIcon, statusColor) = m.isUnderperforming
        ? (
            m.hasZeroActivity
                ? 'Zero activity'
                : 'Down ${growth.abs().toStringAsFixed(0)}%',
            Icons.flag_rounded,
            GovernorDashboardTokens.danger,
          )
        : ('Healthy', Icons.check_circle_rounded, const Color(0xFF16A34A));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            gradient: GovernorDashboardTokens.primaryGradient,
            borderRadius: BorderRadius.circular(18),
          ),
          child: Row(
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: Colors.white.withValues(alpha: 0.35)),
                ),
                child: const Icon(
                  Icons.location_city_rounded,
                  color: Colors.white,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      m.name,
                      style: GovernorDashboardTokens.heading(
                        size: 18,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Misamis Occidental · $_selectedTimeFilter',
                      style: GovernorDashboardTokens.body(
                        size: 12,
                        color: Colors.white.withValues(alpha: 0.9),
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.fromLTRB(8, 4, 10, 4),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(99),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(statusIcon, size: 13, color: statusColor),
                    const SizedBox(width: 4),
                    Text(
                      statusLabel,
                      style: GovernorDashboardTokens.sectionTitle(
                        size: 11.5,
                        color: statusColor,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        if (m.isUnderperforming) ...[
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFFFEF2F2),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFFECACA)),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.warning_amber_rounded,
                  size: 18,
                  color: GovernorDashboardTokens.danger,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    m.hasZeroActivity
                        ? 'No QR check-ins recorded for ${m.name} this period.'
                        : 'Arrivals are down ${growth.abs().toStringAsFixed(0)}% vs the prior period.',
                    style: GovernorDashboardTokens.body(
                      size: 12.5,
                      color: const Color(0xFF991B1B),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
        const SizedBox(height: 12),
        LayoutBuilder(
          builder: (context, c) {
            final cols = c.maxWidth >= 620 ? 4 : 2;
            const gap = 10.0;
            final w = (c.maxWidth - gap * (cols - 1)) / cols;
            return Wrap(
              spacing: gap,
              runSpacing: gap,
              children: [
                SizedBox(
                  width: w,
                  child: _metricTile(
                    icon: Icons.groups_rounded,
                    label: 'Arrivals',
                    value: '${m.arrivals}',
                    accent: GovernorDashboardTokens.primary,
                  ),
                ),
                SizedBox(
                  width: w,
                  child: _metricTile(
                    icon: growth >= 0
                        ? Icons.trending_up_rounded
                        : Icons.trending_down_rounded,
                    label: 'Growth vs prior',
                    value:
                        '${growth > 0 ? '+' : ''}${growth.toStringAsFixed(1)}%',
                    accent: growthColor,
                  ),
                ),
                SizedBox(
                  width: w,
                  child: _metricTile(
                    icon: Icons.place_rounded,
                    label: 'Active spots',
                    value: '${m.activeSpotCount}/${m.spotCount}',
                    accent: const Color(0xFF3B82F6),
                    footer: _gradientBar(spotRatio, height: 4),
                  ),
                ),
                SizedBox(
                  width: w,
                  child: _metricTile(
                    icon: Icons.person_rounded,
                    label: 'Unique visitors',
                    value: '${m.uniqueVisitors}',
                    accent: const Color(0xFF8B5CF6),
                  ),
                ),
              ],
            );
          },
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            const Icon(Icons.star_rounded, size: 18, color: Color(0xFFF59E0B)),
            const SizedBox(width: 6),
            Text('Top spots', style: GovernorDashboardTokens.sectionTitle()),
          ],
        ),
        const SizedBox(height: 8),
        if (tops.isEmpty)
          Container(
            padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 12),
            decoration: BoxDecoration(
              color: GovernorDashboardTokens.background,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: GovernorDashboardTokens.border),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.qr_code_scanner_rounded,
                  size: 18,
                  color: GovernorDashboardTokens.subtitle,
                ),
                const SizedBox(width: 8),
                Text(
                  'No check-ins yet for this period',
                  style: GovernorDashboardTokens.body(size: 12.5),
                ),
              ],
            ),
          )
        else
          for (var i = 0; i < tops.length; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                children: [
                  _rankBadge(i + 1, hasData: tops[i].count > 0),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                tops[i].name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: GovernorDashboardTokens.sectionTitle(
                                  size: 12.5,
                                ),
                              ),
                            ),
                            Text(
                              '${tops[i].count}',
                              style: GovernorDashboardTokens.sectionTitle(
                                size: 12.5,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        _gradientBar(tops[i].count / topMax, height: 5),
                      ],
                    ),
                  ),
                ],
              ),
            ),
      ],
    );
  }

  // ─── Tourist insights ────────────────────────────────────────
  Widget _buildInsightsTab() {
    final q = _insightSearch.trim().toLowerCase();
    final tourists = _tourists.where((t) {
      if (q.isEmpty) return true;
      final name = (t['fullName'] ?? t['name'] ?? '').toString().toLowerCase();
      final email = (t['email'] ?? '').toString().toLowerCase();
      return name.contains(q) || email.contains(q);
    }).toList();
    final lf = ProvincialTourismService.localForeignCounts(_tourists);
    final gender = ProvincialTourismService.genderCounts(_tourists);
    final ages = ProvincialTourismService.ageBands(_tourists);
    final peak = ProvincialTourismService.peakHour(_periodCheckIns);
    final ret = ProvincialTourismService.returningVsNew(_periodCheckIns);

    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
      children: [
        Text('Tourist Insights', style: GovernorDashboardTokens.heading(size: 20)),
        const SizedBox(height: 12),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            _statChip('Local', '${lf['local'] ?? 0}'),
            _statChip('Foreign', '${lf['foreign'] ?? 0}'),
            _statChip('Male', '${gender['male'] ?? 0}'),
            _statChip('Female', '${gender['female'] ?? 0}'),
            _statChip('Peak hour', '${peak.toString().padLeft(2, '0')}:00'),
            _statChip('Returning', '${ret.returning}'),
            _statChip('First-time', '${ret.firstTimers}'),
          ],
        ),
        const SizedBox(height: 14),
        _panel(
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Age bands', style: GovernorDashboardTokens.sectionTitle()),
              const SizedBox(height: 8),
              SizedBox(
                height: 200,
                child: GovernorAgeBarChart(
                  series: [
                    for (final a in ages)
                      (
                        label: a.label,
                        male: 0,
                        female: 0,
                        others: a.count,
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        _panel(
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Registered tourists', style: GovernorDashboardTokens.sectionTitle()),
              const SizedBox(height: 8),
              ...tourists.take(40).map((t) {
                final name = t['fullName']?.toString() ??
                    t['name']?.toString() ??
                    'Tourist';
                final email = t['email']?.toString() ?? '—';
                final type = t['touristType']?.toString() ??
                    t['nationality']?.toString() ??
                    '';
                return ListTile(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  title: Text(name),
                  subtitle: Text('$email${type.isNotEmpty ? ' · $type' : ''}'),
                );
              }),
              if (tourists.isEmpty)
                Text('No tourists found.', style: GovernorDashboardTokens.body()),
            ],
          ),
        ),
      ],
    );
  }

  Widget _statChip(String label, String value) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: GovernorDashboardTokens.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: GovernorDashboardTokens.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: GovernorDashboardTokens.body(size: 11)),
          Text(value, style: GovernorDashboardTokens.number(size: 18)),
        ],
      ),
    );
  }

  // ─── Trip Planner: same LGU Events & Posts calendar ─────────
  // ─── Events & campaigns ──────────────────────────────────────
  Widget _buildEventsTab() {
    final pending = _announcements.where((a) {
      final s = (a['status']?.toString() ?? '').toLowerCase();
      return s == 'pending' || s == 'submitted' || s == 'review';
    }).toList();
    final published = _announcements.where((a) {
      final s = (a['status']?.toString() ?? '').toLowerCase();
      return s == 'published' || s == 'approved';
    }).toList();
    final rejected = _announcements.where((a) {
      final s = (a['status']?.toString() ?? '').toLowerCase();
      return s == 'rejected';
    }).toList();

    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
      children: [
        Row(
          children: [
            Expanded(
              child: Text('Events & Campaigns',
                  style: GovernorDashboardTokens.heading(size: 20)),
            ),
            FilledButton.icon(
              onPressed: _showCampaignEditor,
              icon: const Icon(Icons.add_rounded),
              label: const Text('New campaign'),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          'LGUs write and publish their own event announcements. This office can view them and still runs provincial campaigns.',
          style: GovernorDashboardTokens.body(size: 12.5),
        ),
        const SizedBox(height: 14),
        Wrap(
          spacing: 10,
          children: [
            _statChip('Pending', '${pending.length}'),
            _statChip('Published', '${published.length}'),
            _statChip('Rejected', '${rejected.length}'),
            _statChip('Campaigns', '${_campaigns.length}'),
          ],
        ),
        const SizedBox(height: 14),
        _panel(
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('LGU events queue', style: GovernorDashboardTokens.sectionTitle()),
              const SizedBox(height: 8),
              ..._announcements.take(30).map((a) {
                final status = a['status']?.toString() ?? '—';
                return ListTile(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  title: Text(a['title']?.toString() ?? 'Event'),
                  subtitle: Text(
                    '${a['municipality'] ?? a['municipalityId'] ?? 'LGU'} · $status',
                  ),
                  trailing: Text(
                    status,
                    style: GovernorDashboardTokens.sectionTitle(
                      size: 12,
                      color: status.toLowerCase() == 'pending'
                          ? GovernorDashboardTokens.primaryDark
                          : GovernorDashboardTokens.subtitle,
                    ),
                  ),
                );
              }),
              if (_announcements.isEmpty)
                Text('No events yet.', style: GovernorDashboardTokens.body()),
            ],
          ),
        ),
        const SizedBox(height: 14),
        _panel(
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Provincial campaigns', style: GovernorDashboardTokens.sectionTitle()),
              const SizedBox(height: 8),
              ..._campaigns.map((c) {
                return ListTile(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  title: Text(c['title']?.toString() ?? 'Campaign'),
                  subtitle: Text(
                    '${c['status'] ?? 'draft'} · targets ${(c['targetMunicipalityIds'] as List?)?.length ?? 0} LGUs',
                  ),
                  trailing: IconButton(
                    icon: const Icon(Icons.edit_rounded),
                    onPressed: () => _showCampaignEditor(existing: c),
                  ),
                );
              }),
              if (_campaigns.isEmpty)
                Text('No campaigns yet. Create one to promote destinations.',
                    style: GovernorDashboardTokens.body()),
            ],
          ),
        ),
      ],
    );
  }

  Future<void> _showCampaignEditor({Map<String, dynamic>? existing}) async {
    final titleCtrl =
        TextEditingController(text: existing?['title']?.toString() ?? '');
    final descCtrl =
        TextEditingController(text: existing?['description']?.toString() ?? '');
    var status = existing?['status']?.toString() ?? 'draft';
    var start = DateTime.now();
    var end = DateTime.now().add(const Duration(days: 14));
    if (existing?['startDate'] is Timestamp) {
      start = (existing!['startDate'] as Timestamp).toDate();
    }
    if (existing?['endDate'] is Timestamp) {
      end = (existing!['endDate'] as Timestamp).toDate();
    }
    final selected = <String>{
      ...((existing?['targetMunicipalityIds'] as List?)
              ?.map((e) => e.toString()) ??
          const []),
    };

    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setLocal) {
            return AlertDialog(
              title: Text(existing == null ? 'New campaign' : 'Edit campaign'),
              content: SizedBox(
                width: 420,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      TextField(
                        controller: titleCtrl,
                        decoration: const InputDecoration(labelText: 'Title'),
                      ),
                      TextField(
                        controller: descCtrl,
                        decoration:
                            const InputDecoration(labelText: 'Description'),
                        maxLines: 2,
                      ),
                      const SizedBox(height: 8),
                      DropdownButtonFormField<String>(
                        initialValue: status,
                        items: const [
                          DropdownMenuItem(value: 'draft', child: Text('Draft')),
                          DropdownMenuItem(
                              value: 'active', child: Text('Active')),
                          DropdownMenuItem(
                              value: 'ended', child: Text('Ended')),
                        ],
                        onChanged: (v) => setLocal(() => status = v ?? 'draft'),
                        decoration: const InputDecoration(labelText: 'Status'),
                      ),
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text('Start: ${formatReportDate(start)}'),
                        trailing: const Icon(Icons.calendar_today_rounded),
                        onTap: () async {
                          final d = await showDatePicker(
                            context: ctx,
                            initialDate: start,
                            firstDate: DateTime(2020),
                            lastDate: DateTime(2100),
                          );
                          if (d != null) setLocal(() => start = d);
                        },
                      ),
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text('End: ${formatReportDate(end)}'),
                        trailing: const Icon(Icons.calendar_today_rounded),
                        onTap: () async {
                          final d = await showDatePicker(
                            context: ctx,
                            initialDate: end,
                            firstDate: DateTime(2020),
                            lastDate: DateTime(2100),
                          );
                          if (d != null) setLocal(() => end = d);
                        },
                      ),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Text('Target municipalities',
                            style: GovernorDashboardTokens.sectionTitle(size: 13)),
                      ),
                      Wrap(
                        spacing: 6,
                        children: [
                          for (final m in getMisamisOccidentalMunicipalities())
                            FilterChip(
                              label: Text(m.name.split(' ').first),
                              selected: selected.contains(m.id),
                              onSelected: (v) => setLocal(() {
                                if (v) {
                                  selected.add(m.id);
                                } else {
                                  selected.remove(m.id);
                                }
                              }),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(ctx, true),
                  child: const Text('Save'),
                ),
              ],
            );
          },
        );
      },
    );

    if (saved != true) return;
    final id = await _service.saveCampaign(
      id: existing?['id']?.toString(),
      title: titleCtrl.text,
      description: descCtrl.text,
      start: start,
      end: end,
      targetMunicipalityIds: selected.toList(),
      status: status,
    );
    if (!mounted) return;
    if (id == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not save campaign (check Firestore rules).')),
      );
      return;
    }
    await _loadData();
  }

  // ─── DOT Reports ─────────────────────────────────────────────
  Widget _buildReportsTab() {
    final munis = [
      'All',
      ...getMisamisOccidentalMunicipalities().map((m) => m.name),
    ];
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
      children: [
        Text('DOT Reports', style: GovernorDashboardTokens.heading(size: 20)),
        const SizedBox(height: 8),
        Text(
          'Official forms: preview + Excel/PDF. Scope any spot or establishment '
          'province-wide (super-admin).',
          style: GovernorDashboardTokens.body(),
        ),
        const SizedBox(height: 12),
        _panel(
          OptacaStakeholderReportsPanel(spots: _spots),
        ),
        const SizedBox(height: 12),
        _buildOptacaDotReportExports(),
        const SizedBox(height: 28),
        _panel(
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Quick CSV / summary (legacy)',
                style: GovernorDashboardTokens.sectionTitle(),
              ),
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                initialValue: _reportType,
                items: [
                  for (final t in _reportTypes)
                    DropdownMenuItem(value: t, child: Text(t)),
                ],
                onChanged: (v) => setState(() => _reportType = v ?? _reportType),
                decoration: const InputDecoration(labelText: 'Report type'),
              ),
              const SizedBox(height: 10),
              DropdownButtonFormField<String>(
                initialValue: _reportMunicipality,
                items: [
                  for (final m in munis)
                    DropdownMenuItem(value: m, child: Text(m)),
                ],
                onChanged: (v) =>
                    setState(() => _reportMunicipality = v ?? 'All'),
                decoration: const InputDecoration(labelText: 'Municipality'),
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text('From: ${formatReportDate(_reportStart)}'),
                trailing: const Icon(Icons.date_range_rounded),
                onTap: () async {
                  final d = await showDatePicker(
                    context: context,
                    initialDate: _reportStart,
                    firstDate: DateTime(2020),
                    lastDate: DateTime.now(),
                  );
                  if (d != null) setState(() => _reportStart = d);
                },
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text('To: ${formatReportDate(_reportEnd)}'),
                trailing: const Icon(Icons.date_range_rounded),
                onTap: () async {
                  final d = await showDatePicker(
                    context: context,
                    initialDate: _reportEnd,
                    firstDate: DateTime(2020),
                    lastDate: DateTime.now().add(const Duration(days: 1)),
                  );
                  if (d != null) setState(() => _reportEnd = d);
                },
              ),
              const SizedBox(height: 8),
              FilledButton.icon(
                onPressed: _isExporting ? null : _generateReport,
                icon: _isExporting
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.preview_rounded),
                label: Text(_isExporting ? 'Generating...' : 'Preview / Export'),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildOptacaDotReportExports() {
    final catalog = _spots
        .map(
          (s) => DotVar2SpotCatalogEntry(
            spotId: s['id']?.toString() ?? '',
            name: s['name']?.toString() ?? 'Unknown',
            dotAttractionCode: s['dotAttractionCode']?.toString() ?? '',
            municipalityId: ProvincialTourismService.municipalityIdOf(s),
            municipalityName: ProvincialTourismService.municipalityNameOf(
              ProvincialTourismService.municipalityIdOf(s),
            ),
            status: s['status']?.toString() ?? '',
          ),
        )
        .toList();
    return DotReportExportPanel(
      primaryColor: AppTheme.brandOrange,
      textDark: GovernorDashboardTokens.text,
      textMuted: GovernorDashboardTokens.subtitle,
      borderColor: const Color(0xFFE2E8F0),
      scopeLabel: 'Misamis Occidental (OPTACA)',
      scopeSlug: 'misamis_occidental_optaca',
      isProvincial: true,
      isMobile: _isMobile,
      checkIns: _checkIns,
      tourists: _tourists,
      catalogSpots: catalog,
      wrapPanel: (child) => _panel(child),
    );
  }

  Future<void> _generateReport() async {
    setState(() => _isExporting = true);
    try {
      var checkIns = filterCheckInsInDateRange(
        _checkIns,
        _reportStart,
        _reportEnd,
      );
      var spots = List<Map<String, dynamic>>.from(_spots);
      if (_reportMunicipality != 'All') {
        final mid = getMunicipalityIdFromName(_reportMunicipality);
        checkIns = checkIns
            .where((c) =>
                ProvincialTourismService.municipalityIdOf(c) == mid ||
                ProvincialTourismService.municipalityNameOf(
                      ProvincialTourismService.municipalityIdOf(c),
                    ) ==
                    _reportMunicipality)
            .toList();
        spots = spots
            .where((s) =>
                ProvincialTourismService.municipalityIdOf(s) == mid ||
                ProvincialTourismService.municipalityNameOf(
                      ProvincialTourismService.municipalityIdOf(s),
                    ) ==
                    _reportMunicipality)
            .toList();
      }

      if (_reportType == 'DOT Accommodation Establishment Data') {
        if (!mounted) return;
        await showReportExportPreviewDialog(
          context,
          title: 'DOT Accommodation Establishment Data',
          subtitle:
              '${formatReportDate(_reportStart)} – ${formatReportDate(_reportEnd)}',
              content:
              '=== DOT ACCOMMODATION ESTABLISHMENT DATA ===\n\n'
              'Use the Establishments tab to approve AEs and track their monthly DOT\n'
              'registers (DAE-1B). LGU/Analytics DAE forms fill from those registers.\n\n'
              'Scope: ${_reportMunicipality == 'All' ? 'Province-wide' : _reportMunicipality}\n'
              'Period: ${formatReportDate(_reportStart)} to ${formatReportDate(_reportEnd)}\n\n'
              'Open Analytics → DAE-3 / DAE 3B.2 on an LGU dashboard (or use the catalogue)\n'
              'for filled preview + Excel/PDF once hotels fill their registers.',
        );
        return;
      }

      if (_reportType.contains('VAR 2')) {
        final catalog = [
          for (final s in spots)
            DotVar2SpotCatalogEntry(
              spotId: s['id']?.toString() ?? '',
              name: s['name']?.toString() ?? 'Spot',
              dotAttractionCode: s['dotAttractionCode']?.toString() ??
                  s['attractionCode']?.toString() ??
                  s['code']?.toString() ??
                  '',
              municipalityId: ProvincialTourismService.municipalityIdOf(s),
              municipalityName: ProvincialTourismService.municipalityNameOf(
                ProvincialTourismService.municipalityIdOf(s),
              ),
              status: s['status']?.toString() ?? '',
            ),
        ];
        final scope = _reportMunicipality == 'All'
            ? 'Misamis Occidental (Provincial)'
            : _reportMunicipality;
        final var2 = buildDotVar2VisitorRecordReport(
          checkIns: checkIns,
          catalogSpots: catalog,
          municipalityName: scope,
          startDate: _reportStart,
          endDate: _reportEnd,
        );
        final report = StringBuffer()
          ..writeln('=== DOT VAR 2 — PROVINCIAL TOURISM ===')
          ..writeln('Generated: ${DateTime.now()}')
          ..writeln('Month/Year: ${var2.monthYearLabel}')
          ..writeln('Scope: $scope')
          ..writeln('Check-ins in period: ${var2.checkInsProcessed}')
          ..writeln()
          ..writeln(var2.note)
          ..writeln()
          ..writeln('--- ATTRACTION SUMMARY ---');
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
        if (!mounted) return;
        await showReportExportPreviewDialog(
          context,
          title: 'DOT VAR 2 Visitor Record',
          subtitle:
              '${formatReportDate(_reportStart)} – ${formatReportDate(_reportEnd)}',
          content: report.toString(),
          csvData: var2.csv,
          csvFilename: 'dot_var2_provincial.csv',
          xlsxBytes: var2.xlsxBytes,
          xlsxFilename: 'dot_var2_provincial.xlsx',
        );
        return;
      }

      final built = buildProvincialAtmosReport(
        allCheckIns: checkIns,
        tourists: _tourists,
        spots: spots,
        activeSpots: spots.length,
        startDate: _reportStart,
        endDate: _reportEnd,
        reportType: _reportType,
        period:
            '${formatReportDate(_reportStart)} – ${formatReportDate(_reportEnd)}',
      );
      if (!mounted) return;
      await showReportExportPreviewDialog(
        context,
        title: _reportType,
        subtitle:
            '${formatReportDate(_reportStart)} – ${formatReportDate(_reportEnd)}',
        content: built.reportText,
        csvData: built.municipalityCsv ?? built.summaryCsv,
        csvFilename: 'provincial_dot_report.csv',
        detailCsvData: built.detailCsv,
        detailCsvFilename: 'provincial_dot_detail.csv',
      );
    } finally {
      if (mounted) setState(() => _isExporting = false);
    }
  }

  // ─── Alerts & Quality (live QR + catalog audit) ──────────────
  Widget _buildAlertsTab() {
    return OptacaAlertsQualityPanel(
      spotsCache: _spots,
      checkInsCache: _checkIns,
      announcementsCache: _announcements,
      timeFilter: _selectedTimeFilter,
      acknowledgedIds: _ackAlertIds,
      timeFilterWidget: _timeFilters(),
      onAcknowledge: (id) async {
        await ProvincialTourismService.acknowledgeAlert(id);
        if (!mounted) return;
        setState(() => _ackAlertIds = {..._ackAlertIds, id});
      },
    );
  }

  // ─── Settings ────────────────────────────────────────────────
  Widget _buildSettingsTab() {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
      children: [
        Text('Settings', style: GovernorDashboardTokens.heading(size: 20)),
        const SizedBox(height: 12),
        _panel(
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Profile', style: GovernorDashboardTokens.sectionTitle()),
              const SizedBox(height: 8),
              Text('Office: $_profileName', style: GovernorDashboardTokens.body()),
              Text('Email: $_profileEmail', style: GovernorDashboardTokens.body()),
              Text('Role: Provincial Tourism Office',
                  style: GovernorDashboardTokens.body()),
            ],
          ),
        ),
        const SizedBox(height: 12),
        _panel(
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Notifications', style: GovernorDashboardTokens.sectionTitle()),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Email notifications'),
                value: _emailNotifications,
                onChanged: (v) => setState(() => _emailNotifications = v),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Push notifications'),
                value: _pushNotifications,
                onChanged: (v) => setState(() => _pushNotifications = v),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Weekly reports'),
                value: _weeklyReports,
                onChanged: (v) => setState(() => _weeklyReports = v),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        _panel(
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Debug data', style: GovernorDashboardTokens.sectionTitle()),
              const SizedBox(height: 4),
              Text(
                'Registered tourists = home address. Charts + seed + full purge (incl. establishment stays).',
                style: GovernorDashboardTokens.body(),
              ),
              const SizedBox(height: 8),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.analytics_outlined),
                title: const Text('Debug data hub'),
                subtitle: const Text('Overview charts, seed, full purge'),
                onTap: _openOptacaDebugDataHub,
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        _panel(
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Change password', style: GovernorDashboardTokens.sectionTitle()),
              TextField(
                controller: _currentPwController,
                obscureText: true,
                decoration: const InputDecoration(labelText: 'Current password'),
              ),
              TextField(
                controller: _newPwController,
                obscureText: true,
                decoration: const InputDecoration(labelText: 'New password'),
              ),
              TextField(
                controller: _confirmPwController,
                obscureText: true,
                decoration:
                    const InputDecoration(labelText: 'Confirm new password'),
              ),
              const SizedBox(height: 10),
              FilledButton(
                onPressed: _changePassword,
                child: const Text('Update password'),
              ),
            ],
          ),
        ),
      ],
    );
  }

  void _openOptacaDebugDataHub() {
    unawaited(
      LguDebugDataDialogs.openHub(
        context: context,
        municipalityId: '',
        municipalityName: 'All municipalities',
        spots: const [],
        onDone: () {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text(
                  'Debug action complete. Refresh DSS / registry views.',
                ),
                behavior: SnackBarBehavior.floating,
              ),
            );
          }
        },
      ),
    );
  }

  Future<void> _changePassword() async {
    final current = _currentPwController.text;
    final next = _newPwController.text;
    final confirm = _confirmPwController.text;
    if (next.length < 8) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('New password must be at least 8 characters.')),
      );
      return;
    }
    if (next != confirm) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('New passwords do not match.')),
      );
      return;
    }
    final ok =
        await SessionStorage.validateCredentialsAsync(_profileEmail, current);
    if (!ok) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Current password is incorrect.')),
      );
      return;
    }
    await SessionStorage.persistProvincialTourismPassword(next);
    try {
      await AuthService.syncDemoStaffAuthPassword(
        email: _profileEmail,
        newPassword: next,
        previousPasswordCandidates: [
          current,
          SessionStorage.provincialTourismPassword,
          SessionStorage.provincialTourismPasswordLegacy,
        ],
      );
    } catch (_) {}
    if (!mounted) return;
    _currentPwController.clear();
    _newPwController.clear();
    _confirmPwController.clear();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Password updated.')),
    );
  }
}

class _NavItem {
  const _NavItem(this.icon, this.label);
  final IconData icon;
  final String label;
}

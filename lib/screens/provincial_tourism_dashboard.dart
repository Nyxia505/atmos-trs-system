import 'dart:async' show unawaited;

import 'package:atmos_trs_system/config/auth_config.dart';
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
import 'package:atmos_trs_system/widgets/report_export_preview.dart';
import 'package:atmos_trs_system/widgets/ui_skeleton.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

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

  // Destinations filters
  String _destSearch = '';
  String _destCategory = 'All';
  String _destMunicipality = 'All';

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
    _NavItem(Icons.assessment_rounded, 'DOT Reports'),
    _NavItem(Icons.warning_amber_rounded, 'Alerts & Quality'),
    _NavItem(Icons.settings_rounded, 'Settings'),
  ];

  static const _dashboardIndex = 0;
  static const _destinationsIndex = 1;
  static const _performanceIndex = 2;
  static const _insightsIndex = 3;
  static const _eventsIndex = 4;
  static const _reportsIndex = 5;
  static const _alertsIndex = 6;
  static const _settingsIndex = 7;
  static const _bottomNavItemCount = 5;

  static const _categories = [
    'All',
    'Beach',
    'Falls',
    'Historical',
    'Mountain',
    'Resort',
  ];

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
                if (_selectedIndex == _destinationsIndex) {
                  _destSearch = q;
                } else if (_selectedIndex == _insightsIndex) {
                  _insightSearch = q;
                }
              });
            },
            searchHint: 'Search destinations, tourists, municipalities...',
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
      _reportsIndex => _buildReportsTab(),
      _alertsIndex => _buildAlertsTab(),
      _settingsIndex => _buildSettingsTab(),
      _ => _buildDashboardTab(),
    };
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
              title: 'Total arrivals',
              value: '${period.length}',
              icon: Icons.groups_rounded,
              accent: GovernorDashboardTokens.primary,
              subtitle: _selectedTimeFilter,
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

  // ─── Destinations ────────────────────────────────────────────
  Widget _buildDestinationsTab() {
    final munis = ['All', ...getMisamisOccidentalMunicipalities().map((m) => m.name)];
    final filtered = _spots.where((s) {
      final name = (s['name']?.toString() ?? '').toLowerCase();
      final cat = (s['category']?.toString() ?? '').toLowerCase();
      final mid = ProvincialTourismService.municipalityIdOf(s);
      final mname = ProvincialTourismService.municipalityNameOf(mid);
      if (_destSearch.trim().isNotEmpty &&
          !name.contains(_destSearch.toLowerCase()) &&
          !mname.toLowerCase().contains(_destSearch.toLowerCase())) {
        return false;
      }
      if (_destCategory != 'All' && !cat.contains(_destCategory.toLowerCase())) {
        return false;
      }
      if (_destMunicipality != 'All' && mname != _destMunicipality) {
        return false;
      }
      return true;
    }).toList();

    final visitCounts = <String, int>{};
    for (final c in _periodCheckIns) {
      final sid = c['spotId']?.toString() ?? c['spot_id']?.toString() ?? '';
      if (sid.isEmpty) continue;
      visitCounts[sid] = (visitCounts[sid] ?? 0) + 1;
    }

    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
      children: [
        Text('Destinations', style: GovernorDashboardTokens.heading(size: 20)),
        const SizedBox(height: 4),
        Text(
          'Province-wide inventory (read-only; LGU offices manage spot CRUD).',
          style: GovernorDashboardTokens.body(size: 13),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final c in _categories)
              FilterChip(
                label: Text(c),
                selected: _destCategory == c,
                onSelected: (_) => setState(() => _destCategory = c),
              ),
          ],
        ),
        const SizedBox(height: 8),
        DropdownButtonFormField<String>(
          initialValue: _destMunicipality,
          decoration: const InputDecoration(
            labelText: 'Municipality',
            border: OutlineInputBorder(),
            isDense: true,
          ),
          items: [
            for (final m in munis)
              DropdownMenuItem(value: m, child: Text(m)),
          ],
          onChanged: (v) => setState(() => _destMunicipality = v ?? 'All'),
        ),
        const SizedBox(height: 14),
        _panel(
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: DataTable(
              columns: const [
                DataColumn(label: Text('Name')),
                DataColumn(label: Text('Municipality')),
                DataColumn(label: Text('Category')),
                DataColumn(label: Text('Visits')),
                DataColumn(label: Text('Status')),
                DataColumn(label: Text('VR')),
                DataColumn(label: Text('Featured')),
              ],
              rows: [
                for (final s in filtered)
                  DataRow(
                    cells: [
                      DataCell(Text(s['name']?.toString() ?? '—')),
                      DataCell(Text(ProvincialTourismService.municipalityNameOf(
                        ProvincialTourismService.municipalityIdOf(s),
                      ))),
                      DataCell(Text(s['category']?.toString() ?? '—')),
                      DataCell(Text('${visitCounts[s['id']?.toString()] ?? 0}')),
                      DataCell(Text(
                        (s['status']?.toString().isNotEmpty == true)
                            ? s['status'].toString()
                            : 'active',
                      )),
                      DataCell(Text(
                        (s['vrTourUrl'] ?? s['vrUrl'] ?? s['hasVr']) != null &&
                                (s['vrTourUrl'] ?? s['vrUrl'] ?? '')
                                    .toString()
                                    .isNotEmpty
                            ? 'Yes'
                            : (s['hasVr'] == true ? 'Yes' : '—'),
                      )),
                      DataCell(
                        Switch(
                          value: s['provincialFeatured'] == true,
                          onChanged: (v) async {
                            final id = s['id']?.toString() ?? '';
                            final ok = await _service.setDestinationFeatured(
                              spotId: id,
                              featured: v,
                            );
                            if (ok && mounted) {
                              setState(() => s['provincialFeatured'] = v);
                            }
                          },
                        ),
                      ),
                    ],
                  ),
              ],
            ),
          ),
        ),
        if (filtered.isEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 16),
            child: Text('No destinations match filters.', style: GovernorDashboardTokens.body()),
          ),
      ],
    );
  }

  // ─── Municipality performance ────────────────────────────────
  Widget _buildPerformanceTab() {
    ProvincialMunicipalityStats? selected;
    for (final m in _muniStats) {
      if (m.id == _selectedMunicipalityId) {
        selected = m;
        break;
      }
    }
    selected ??= _muniStats.isNotEmpty ? _muniStats.first : null;

    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
      children: [
        Row(
          children: [
            Expanded(
              child: Text('Municipality Performance',
                  style: GovernorDashboardTokens.heading(size: 20)),
            ),
            _timeFilters(),
          ],
        ),
        const SizedBox(height: 12),
        _panel(
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('LGU ranking by arrivals',
                  style: GovernorDashboardTokens.sectionTitle()),
              const SizedBox(height: 10),
              _rankColumn([
                for (final m in _muniStats.take(12))
                  (name: m.name, count: m.arrivals),
              ]),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final m in _muniStats.take(12))
              ActionChip(
                label: Text(m.name),
                onPressed: () =>
                    setState(() => _selectedMunicipalityId = m.id),
              ),
          ],
        ),
        const SizedBox(height: 12),
        if (selected == null)
          _panel(Text('Select an LGU.', style: GovernorDashboardTokens.body()))
        else
          _panel(_municipalityDetail(selected)),
      ],
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(m.name, style: GovernorDashboardTokens.heading(size: 18)),
        const SizedBox(height: 8),
        if (m.isUnderperforming)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: const Color(0xFFFEE2E2),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              m.hasZeroActivity
                  ? 'Flagged: zero activity this period'
                  : 'Flagged: arrivals down ${m.growthPercent.abs().toStringAsFixed(0)}%',
              style: GovernorDashboardTokens.sectionTitle(
                size: 12,
                color: GovernorDashboardTokens.danger,
              ),
            ),
          ),
        const SizedBox(height: 12),
        Text('Arrivals: ${m.arrivals}', style: GovernorDashboardTokens.body()),
        Text(
          'Growth vs prior: ${m.growthPercent.toStringAsFixed(1)}%',
          style: GovernorDashboardTokens.body(),
        ),
        Text(
          'Spots: ${m.activeSpotCount}/${m.spotCount} active',
          style: GovernorDashboardTokens.body(),
        ),
        Text(
          'Unique visitors: ${m.uniqueVisitors}',
          style: GovernorDashboardTokens.body(),
        ),
        const SizedBox(height: 12),
        Text('Top spots', style: GovernorDashboardTokens.sectionTitle()),
        const SizedBox(height: 8),
        _rankColumn([
          for (final t in tops) (name: t.name, count: t.count),
        ]),
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
          'Event approval remains with the Governor workflow. This office monitors status and runs provincial campaigns.',
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
        const SizedBox(height: 12),
        _panel(
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
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
              'Status: Stubbed — accommodation establishment collection is not wired yet.\n'
              'Scope: ${_reportMunicipality == 'All' ? 'Province-wide' : _reportMunicipality}\n'
              'Period: ${formatReportDate(_reportStart)} to ${formatReportDate(_reportEnd)}\n\n'
              'Once accommodation data is available in Firestore, this report will export occupancy and guest counts.',
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

  // ─── Alerts ──────────────────────────────────────────────────
  Widget _buildAlertsTab() {
    final alerts = _alerts;
    Color sevColor(ProvincialAlertSeverity s) {
      switch (s) {
        case ProvincialAlertSeverity.critical:
          return GovernorDashboardTokens.danger;
        case ProvincialAlertSeverity.warning:
          return GovernorDashboardTokens.primaryDark;
        case ProvincialAlertSeverity.info:
          return const Color(0xFF3B82F6);
      }
    }

    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
      children: [
        Row(
          children: [
            Expanded(
              child: Text('Alerts & Quality',
                  style: GovernorDashboardTokens.heading(size: 20)),
            ),
            _timeFilters(),
          ],
        ),
        const SizedBox(height: 12),
        if (alerts.isEmpty)
          _panel(Text('No open alerts. Quality looks healthy for this period.',
              style: GovernorDashboardTokens.body()))
        else
          ...alerts.map((a) {
            return Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: _panel(
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: sevColor(a.severity).withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        a.severity.name.toUpperCase(),
                        style: GovernorDashboardTokens.sectionTitle(
                          size: 11,
                          color: sevColor(a.severity),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(a.title,
                              style: GovernorDashboardTokens.sectionTitle()),
                          Text(a.message, style: GovernorDashboardTokens.body()),
                        ],
                      ),
                    ),
                    TextButton(
                      onPressed: () async {
                        await ProvincialTourismService.acknowledgeAlert(a.id);
                        setState(() => _ackAlertIds = {..._ackAlertIds, a.id});
                      },
                      child: const Text('Acknowledge'),
                    ),
                  ],
                ),
              ),
            );
          }),
      ],
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
        const SizedBox(height: 12),
        _panel(
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('About', style: GovernorDashboardTokens.sectionTitle()),
              Text(
                'ATMOS TRS · Provincial Tourism Office\nMisamis Occidental',
                style: GovernorDashboardTokens.body(),
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: _logout,
                icon: const Icon(Icons.logout_rounded),
                label: const Text('Log out'),
              ),
            ],
          ),
        ),
      ],
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

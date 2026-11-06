import 'dart:async';
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:image_picker/image_picker.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'data.dart';
import 'event_datetime_format.dart';
import 'event_schedule.dart';
import 'firestore_loader.dart';
import 'municipality_bus_terminals.dart';
import 'services/admin_live_collections.dart';
import 'services/admin_session_bootstrap.dart';
import 'services/auth_roles.dart';
import 'municipality_performance.dart';
import 'trip_planner_analytics_tab.dart';
import 'services/public_firestore_read.dart';
import 'services/reports/report_check_ins.dart';
import 'services/storage_image_upload.dart';
import 'services/spot_ratings_store.dart';
import 'services/bus_location_store.dart';
import 'services/tourism_session.dart' show tourismCatalogRevision;
import 'services/tourist_spot_unique_views_service.dart';
import 'admin_announcements_tab.dart';
import 'admin_event_form_page.dart';
import 'admin_bus_locations_tab.dart';
import 'admin_matrix_fares_tab.dart';
import 'admin_reports_tab.dart';
import 'tourist_registry_tab.dart';
import 'trip_planner_utils.dart';
import 'auth/auth_navigation.dart';
import 'theme/tourism_app_theme.dart';
import 'trip_plan_host_bridge.dart';
import 'utils/spot_coordinates.dart';
import 'widgets/admin_bulk_selection_bar.dart';
import 'widgets/admin_featured_spot_picker.dart';
import 'widgets/admin_high_rating_spots_map.dart';
import 'widgets/admin_spot_location_picker.dart';
import 'widgets/admin_tourist_spot_details_dialog.dart';
import 'widgets/municipality_image.dart';
import 'widgets/optaca_accounts_panel.dart';
import 'widgets/optaca_portal_ui.dart';
import 'widgets/responsive_layout.dart';
import 'widgets/tourism_events_calendar.dart';
import 'widgets/tourism_plan_ui.dart';
import 'widgets/user_profile_avatar.dart';

/// Lets heavy admin tabs pause work when another route is pushed above the dashboard.
final RouteObserver<PageRoute<dynamic>> tourismAdminRouteObserver =
    RouteObserver<PageRoute<dynamic>>();

// ─── Governor Portal (ATMOS TRS) theme ───────────────────────────────────
const Color _kPortalIconBlue = Color(0xFF42A5F5);
const Color _kTrendGreen = Color(0xFF66BB6A);

/// Sidebar titles. Indices match [_buildGovernorTabBody].
const _kGovernorNavItems = [
  (icon: Icons.dashboard_rounded, label: 'Overview Dashboard'),
  (icon: Icons.people_outline_rounded, label: 'Tourist Monitoring'),
  (icon: Icons.place_outlined, label: 'Tourist Spots'),
  (icon: Icons.star_outline_rounded, label: 'Featured Destinations'),
  (icon: Icons.view_in_ar_outlined, label: 'Virtual Tours'),
  (icon: Icons.location_city_outlined, label: 'Municipality Performance'),
  (icon: Icons.route_outlined, label: 'Trip Planner Analytics'),
  (icon: Icons.grid_on_outlined, label: 'Matrix Fares'),
  (icon: Icons.campaign_outlined, label: 'Events & Announcements'),
  (icon: Icons.storefront_outlined, label: 'Establishments'),
  (icon: Icons.assessment_outlined, label: 'DOT Reports'),
  (icon: Icons.warning_amber_rounded, label: 'Alerts & Quality'),
  (icon: Icons.manage_accounts_rounded, label: 'LGU Account Management'),
  (icon: Icons.settings_outlined, label: 'Settings'),
];

const _kNavSections = <({String? title, List<int> indices})>[
  (title: null, indices: [0]),
  (title: 'Visitors', indices: [1, 5, 6]),
  (title: 'Places', indices: [2, 3, 4, 8, 9]),
  (title: 'Reports', indices: [7, 10, 11]),
  (title: 'System', indices: [12, 13]),
];

String _portalPageTitle(int selected) {
  if (selected >= 0 && selected < _kGovernorNavItems.length) {
    return _kGovernorNavItems[selected].label;
  }
  return switch (selected) {
    14 => 'Bus stops',
    15 => 'Spots & QR',
    16 => 'QR check-in history',
    _ => 'OPTACA Portal',
  };
}

String _slug(String name) {
  return name
      .toLowerCase()
      .trim()
      .replaceAll(RegExp(r'[^a-z0-9\s]'), '')
      .replaceAll(RegExp(r'\s+'), '_');
}

class AdminDashboardScreen extends StatefulWidget {
  static const routeName = '/admin';

  const AdminDashboardScreen({super.key});

  @override
  State<AdminDashboardScreen> createState() => _AdminDashboardScreenState();
}

class _AdminDashboardScreenState extends State<AdminDashboardScreen> {
  /// Tab changes use this notifier so the heavy content area rebuilds without
  /// rebuilding the entire scaffold (smoother on web).
  final ValueNotifier<int> _tabIndex = ValueNotifier<int>(0);
  /// Null follows screen width (compact on tablet). User toggle pins the choice.
  bool? _navCollapsed;

  void _onGovernorDataChanged() => setState(() {});

  Widget _buildGovernorTabBody(int index) {
    switch (index) {
      case 0:
        return _OverviewTab(onOpen: (index) => _tabIndex.value = index);
      case 1:
        return _TouristMonitoringHost(
          onOpenCheckIns: () => _tabIndex.value = 16,
        );
      case 2:
        return _SpotsListTab(onChanged: _onGovernorDataChanged);
      case 3:
        return AdminFeaturedSpotsTab(onChanged: _onGovernorDataChanged);
      case 4:
        return const _AdminVrTourTab();
      case 5:
        return _MunicipalitiesListTab(onChanged: _onGovernorDataChanged);
      case 6:
        return const TripPlannerAnalyticsTab();
      case 7:
        return const AdminMatrixFaresTab();
      case 8:
        return _EventsAndAnnouncementsHost(onChanged: _onGovernorDataChanged);
      case 9:
        return const _PortalEstablishmentsTab();
      case 10:
        return AdminReportsTab(
          onOpenMatrixFares: () => _tabIndex.value = 7,
        );
      case 11:
        return const _AlertsQualityTab();
      case 12:
        return const _LguAccountManagementTab();
      case 13:
        return _AdminSettingsTab(
          onOpenBusStops: () => _tabIndex.value = 14,
          onOpenSpotsQr: () => _tabIndex.value = 15,
        );
      case 14:
        return const AdminBusLocationsTab();
      case 15:
        return _AdminSpotsQrTab(
          onOpenSpotsTab: () => _tabIndex.value = 2,
        );
      case 16:
        return const _AdminCheckInsTab();
      default:
        return const SizedBox.shrink();
    }
  }

  @override
  void initState() {
    super.initState();
    TripPlanHostBridge.openMatrixFaresTab = () => _tabIndex.value = 7;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      BusLocationStore.instance.ensureListening();
      if (mounted) {
        precacheImage(
          const ResizeImage(
            AssetImage(_OverviewHeroBanner._hostAsset),
            width: 1400,
          ),
          context,
        );
      }
      prefetchAdminDashboardCatalogs().then((_) {
        if (mounted) setState(() {});
      });
    });
  }

  @override
  void dispose() {
    if (TripPlanHostBridge.openMatrixFaresTab != null) {
      TripPlanHostBridge.openMatrixFaresTab = null;
    }
    _tabIndex.dispose();
    super.dispose();
  }

  Widget _buildGovernorMainColumn(int selected, {required bool useDrawer}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Tabs with in-content cream headers skip chrome titles.
        if (!useDrawer && selected != 2 && selected != 3 && selected != 6)
        _GovernorPageHeader(
          title: _portalPageTitle(selected),
        ),
        Expanded(
          child: RepaintBoundary(
            child: ColoredBox(
              color: OptacaAdminTheme.background,
              child: _KeepAliveGovernorTabs(
                index: selected,
                builder: _buildGovernorTabBody,
              ),
            ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return AdminLiveScope(
      child: Theme(
      data: OptacaAdminTheme.theme(Theme.of(context)),
      child: LayoutBuilder(
      builder: (context, constraints) {
        final useDrawer = constraints.maxWidth < TourismBreakpoints.adminDrawer;
        final autoCompact = constraints.maxWidth < TourismBreakpoints.wide;
        final navCollapsed = !useDrawer && (_navCollapsed ?? autoCompact);
        return ValueListenableBuilder<int>(
          valueListenable: _tabIndex,
          builder: (context, selected, _) {
            void selectTab(int index) {
              if (index == selected) {
                if (useDrawer && Scaffold.maybeOf(context)?.isDrawerOpen == true) {
                  Navigator.pop(context);
                }
                return;
              }
              _tabIndex.value = index;
              if (useDrawer && Scaffold.maybeOf(context)?.isDrawerOpen == true) {
                Navigator.pop(context);
              }
            }

            final sidebar = _GovernorSidebar(
              selectedIndex: selected,
              onSelect: selectTab,
              onLogout: () => performTourismLogout(context),
              fullWidth: useDrawer,
              collapsed: navCollapsed,
              onToggleCollapse: useDrawer
                  ? null
                  : () => setState(() => _navCollapsed = !navCollapsed),
            );

            if (useDrawer) {
              return Scaffold(
                backgroundColor: OptacaAdminTheme.background,
                drawer: Drawer(
                  width: (constraints.maxWidth * 0.86).clamp(260.0, 320.0),
                  child: sidebar,
                ),
                appBar: AppBar(
                  backgroundColor: OptacaAdminTheme.primary,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  title: Text(
                    _portalPageTitle(selected),
                    style: TourismAppTheme.adminAppBar.titleTextStyle,
                  ),
                ),
                body: _buildGovernorMainColumn(selected, useDrawer: true),
              );
            }

            return Scaffold(
              backgroundColor: OptacaAdminTheme.background,
              body: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  RepaintBoundary(child: sidebar),
                  Expanded(child: _buildGovernorMainColumn(selected, useDrawer: false)),
                ],
              ),
            );
          },
        );
      },
      ),
    ),
    );
  }
}

/// Keeps visited modules mounted so tab switches do not flash a blank frame
/// or re-subscribe to Firestore. Inactive tabs skip rebuilds until selected.
class _KeepAliveGovernorTabs extends StatefulWidget {
  const _KeepAliveGovernorTabs({
    required this.index,
    required this.builder,
  });

  final int index;
  final Widget Function(int index) builder;

  @override
  State<_KeepAliveGovernorTabs> createState() => _KeepAliveGovernorTabsState();
}

class _KeepAliveGovernorTabsState extends State<_KeepAliveGovernorTabs> {
  late final Set<int> _visited = {widget.index};
  final Set<int> _firstPaint = {};

  @override
  void didUpdateWidget(covariant _KeepAliveGovernorTabs oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_visited.contains(widget.index)) {
      _visited.add(widget.index);
      _firstPaint.add(widget.index);
      final target = widget.index;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        if (!_firstPaint.contains(target)) return;
        setState(() => _firstPaint.remove(target));
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final idx = widget.index;
    return Stack(
      fit: StackFit.expand,
      children: [
        for (final i in _visited)
          _HoldInactiveChild(
            active: i == idx,
            child: i == idx
                ? KeyedSubtree(
                    key: ValueKey('optaca-tab-$i'),
                    child: widget.builder(i),
                  )
                : const SizedBox.shrink(),
          ),
        if (_firstPaint.contains(idx))
          const ColoredBox(
            color: OptacaAdminTheme.background,
            child: Center(
              child: CircularProgressIndicator(color: AppColors.primary),
            ),
          ),
      ],
    );
  }
}

class _HoldInactiveChild extends StatefulWidget {
  const _HoldInactiveChild({
    required this.active,
    required this.child,
  });

  final bool active;
  final Widget child;

  @override
  State<_HoldInactiveChild> createState() => _HoldInactiveChildState();
}

class _HoldInactiveChildState extends State<_HoldInactiveChild> {
  Widget? _held;

  @override
  Widget build(BuildContext context) {
    if (widget.active || _held == null) {
      _held = widget.child;
    }
    return TickerMode(
      enabled: widget.active,
      child: Offstage(
        offstage: !widget.active,
        child: _held!,
      ),
    );
  }
}

class _GovernorSidebar extends StatelessWidget {
  final int selectedIndex;
  final ValueChanged<int> onSelect;
  final VoidCallback onLogout;
  final bool fullWidth;
  final bool collapsed;
  final VoidCallback? onToggleCollapse;

  const _GovernorSidebar({
    required this.selectedIndex,
    required this.onSelect,
    required this.onLogout,
    this.fullWidth = false,
    this.collapsed = false,
    this.onToggleCollapse,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
      width: fullWidth ? double.infinity : (collapsed ? 84 : 276),
      decoration: BoxDecoration(
        gradient: OptacaAdminTheme.sidebarGradient,
        borderRadius: fullWidth
            ? BorderRadius.zero
            : const BorderRadius.only(
                topRight: Radius.circular(18),
                bottomRight: Radius.circular(18),
              ),
        boxShadow: fullWidth
            ? null
            : [
                BoxShadow(
                  color: OptacaAdminTheme.primary.withValues(alpha: 0.28),
                  blurRadius: 22,
                  offset: const Offset(4, 0),
                ),
              ],
      ),
      clipBehavior: Clip.antiAlias,
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: EdgeInsets.fromLTRB(collapsed ? 10 : 16, 18, collapsed ? 10 : 12, 8),
              child: collapsed
                  ? Column(
                      children: [
                        Tooltip(
                          message: 'OPTACA Portal',
                          child: _optacaSealLogo(),
                        ),
                        if (onToggleCollapse != null)
                          IconButton(
                            tooltip: 'Expand menu',
                            onPressed: onToggleCollapse,
                            icon: Icon(
                              Icons.keyboard_double_arrow_right_rounded,
                              color: Colors.white.withValues(alpha: 0.85),
                            ),
                          ),
                      ],
                    )
                  : Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        _optacaSealLogo(),
                        const SizedBox(width: 12),
                        const Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'OPTACA',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w800,
                                  color: Colors.white,
                                  letterSpacing: 0.6,
                                  height: 1.05,
                                ),
                              ),
                              SizedBox(height: 3),
                              Text(
                                'Provincial Tourism Office',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 11.5,
                                  color: Colors.white,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),
                        if (onToggleCollapse != null)
                          IconButton(
                            tooltip: 'Collapse menu',
                            onPressed: onToggleCollapse,
                            icon: Icon(
                              Icons.keyboard_double_arrow_left_rounded,
                              color: Colors.white.withValues(alpha: 0.85),
                            ),
                          ),
                      ],
                    ),
            ),
            if (!collapsed)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 10),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.18),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: Colors.white.withValues(alpha: 0.28)),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.08),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: const Text(
                    'Misamis Occidental',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 11.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            Expanded(child: _navList()),
            if (!collapsed)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 6, 16, 8),
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.16),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: Colors.white.withValues(alpha: 0.22)),
                  ),
                  child: const Row(
                    children: [
                      Icon(Icons.verified_outlined, color: Colors.white, size: 18),
                      SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'OPTACA Admin',
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w700,
                            fontSize: 12.5,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            Padding(
              padding: EdgeInsets.fromLTRB(collapsed ? 10 : 16, 4, collapsed ? 10 : 16, 16),
              child: collapsed
                  ? Tooltip(
                      message: 'Logout',
                      child: Material(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        child: IconButton(
                          onPressed: onLogout,
                          icon: const Icon(
                            Icons.logout_rounded,
                            color: OptacaAdminTheme.primary,
                          ),
                        ),
                      ),
                    )
                  : FilledButton.icon(
                      onPressed: onLogout,
                      style: FilledButton.styleFrom(
                        backgroundColor: Colors.white,
                        foregroundColor: OptacaAdminTheme.primary,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        minimumSize: const Size.fromHeight(46),
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      icon: const Icon(Icons.logout_rounded, size: 18),
                      label: const Text(
                        'Logout',
                        style: TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  static const _kTourismSealAsset =
      'assets/images/misamis_occidental_tourism_seal_sidebar.png';

  Widget _optacaSealLogo() {
    return SizedBox(
      width: 44,
      height: 44,
      child: ClipOval(
        child: Image.asset(
          _kTourismSealAsset,
          package: 'trip_plan',
          width: 44,
          height: 44,
          fit: BoxFit.contain,
          alignment: Alignment.center,
          filterQuality: FilterQuality.high,
          isAntiAlias: true,
          gaplessPlayback: true,
          errorBuilder: (context, error, stackTrace) => const Icon(
            Icons.shield_outlined,
            color: Colors.white,
            size: 26,
          ),
        ),
      ),
    );
  }

  Widget _navList() {
    return ListView(
      padding: EdgeInsets.fromLTRB(collapsed ? 8 : 12, 4, collapsed ? 8 : 12, 12),
      children: [
        for (final section in _kNavSections) ...[
          if (!collapsed && section.title != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 16, 12, 8),
              child: Text(
                section.title!.toUpperCase(),
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.78),
                  fontSize: 10.5,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.4,
                ),
              ),
            )
          else if (collapsed && section.title != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 10, 8, 6),
              child: Divider(color: Colors.white.withValues(alpha: 0.28), height: 1),
            ),
          for (final index in section.indices) _navTile(index),
        ],
      ],
    );
  }

  Widget _navTile(int index) {
    final item = _kGovernorNavItems[index];
    final selected = selectedIndex == index;
    final tile = Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => onSelect(index),
          borderRadius: BorderRadius.circular(12),
          hoverColor: Colors.white.withValues(alpha: selected ? 0.12 : 0.14),
          splashColor: Colors.white.withValues(alpha: 0.22),
          highlightColor: Colors.white.withValues(alpha: 0.10),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOut,
            padding: EdgeInsets.symmetric(
              horizontal: collapsed ? 0 : 12,
              vertical: collapsed ? 11 : 12,
            ),
            decoration: BoxDecoration(
              color: selected ? Colors.white : Colors.transparent,
              borderRadius: BorderRadius.circular(12),
              boxShadow: selected
                  ? [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.12),
                        blurRadius: 12,
                        offset: const Offset(0, 4),
                      ),
                    ]
                  : null,
            ),
            child: Row(
              mainAxisAlignment:
                  collapsed ? MainAxisAlignment.center : MainAxisAlignment.start,
              children: [
                Icon(
                  item.icon,
                  size: 21,
                  color: selected
                      ? OptacaAdminTheme.primary
                      : Colors.white.withValues(alpha: 0.95),
                ),
                if (!collapsed) ...[
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      item.label,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13.5,
                        height: 1.2,
                        fontWeight: selected ? FontWeight.w800 : FontWeight.w500,
                        color: selected
                            ? OptacaAdminTheme.primary
                            : Colors.white.withValues(alpha: 0.95),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
    if (!collapsed) return tile;
    return Tooltip(
      message: item.label,
      waitDuration: const Duration(milliseconds: 250),
      child: tile,
    );
  }
}

class _GovernorPageHeader extends StatelessWidget {
  final String title;

  const _GovernorPageHeader({
    required this.title,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: OptacaAdminTheme.lightOrange,
      elevation: 0,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(28, 16, 28, 14),
        decoration: BoxDecoration(
          color: OptacaAdminTheme.lightOrange,
          border: const Border(bottom: BorderSide(color: OptacaAdminTheme.border)),
          boxShadow: [
            BoxShadow(
              color: OptacaAdminTheme.primary.withValues(alpha: 0.06),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.only(bottom: 10),
              decoration: BoxDecoration(
                color: OptacaAdminTheme.primary,
                borderRadius: BorderRadius.circular(4),
              ),
            ),
            Text(
              title,
              style: const TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.w800,
                color: OptacaAdminTheme.text,
                letterSpacing: -0.4,
                height: 1.1,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TouristMonitoringHost extends StatelessWidget {
  const _TouristMonitoringHost({required this.onOpenCheckIns});

  final VoidCallback onOpenCheckIns;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Align(
          alignment: Alignment.centerRight,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: FilledButton.tonalIcon(
              onPressed: onOpenCheckIns,
              icon: const Icon(Icons.fact_check_outlined, size: 18),
              label: const Text('QR check-in history'),
              style: FilledButton.styleFrom(
                backgroundColor: OptacaAdminTheme.lightOrange,
                foregroundColor: OptacaAdminTheme.darkOrange,
              ),
            ),
          ),
        ),
        const Expanded(child: TouristRegistryTab()),
      ],
    );
  }
}

/// Shows the existing announcements page or the existing events page.
/// Only one is mounted, so the two lists do not share a scroll controller.
class _EventsAndAnnouncementsHost extends StatefulWidget {
  const _EventsAndAnnouncementsHost({required this.onChanged});

  final VoidCallback onChanged;

  @override
  State<_EventsAndAnnouncementsHost> createState() =>
      _EventsAndAnnouncementsHostState();
}

class _EventsAndAnnouncementsHostState extends State<_EventsAndAnnouncementsHost> {
  int _page = 0;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: Container(
            padding: const EdgeInsets.all(6),
            decoration: OptacaAdminTheme.cardDecoration,
            child: SizedBox(
              width: double.infinity,
              child: SegmentedButton<int>(
                showSelectedIcon: false,
                segments: const [
                  ButtonSegment(
                    value: 0,
                    icon: Icon(Icons.campaign_outlined, size: 18),
                    label: Text('Announcements'),
                  ),
                  ButtonSegment(
                    value: 1,
                    icon: Icon(Icons.event_outlined, size: 18),
                    label: Text('Events'),
                  ),
                ],
                selected: {_page},
                onSelectionChanged: (next) {
                  setState(() => _page = next.first);
                },
              ),
            ),
          ),
        ),
        Expanded(
          child: Stack(
            fit: StackFit.expand,
            children: [
              TickerMode(
                enabled: _page == 0,
                child: Offstage(
                  offstage: _page != 0,
                  child: AdminAnnouncementsTab(onChanged: widget.onChanged),
                ),
              ),
              TickerMode(
                enabled: _page == 1,
                child: Offstage(
                  offstage: _page != 1,
                  child: _EventsListTab(onChanged: widget.onChanged),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _PortalEstablishmentsTab extends StatefulWidget {
  const _PortalEstablishmentsTab();

  @override
  State<_PortalEstablishmentsTab> createState() =>
      _PortalEstablishmentsTabState();
}

class _PortalEstablishmentsTabState extends State<_PortalEstablishmentsTab> {
  late Future<PublicFirestoreDocs> _load =
      fetchPublicFirestoreCollection('accommodation_establishments');
  final TextEditingController _search = TextEditingController();

  void _reload() {
    setState(() {
      _load = fetchPublicFirestoreCollection('accommodation_establishments');
    });
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<PublicFirestoreDocs>(
      future: _load,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snap.hasError) {
          return OptacaLoadError(
            title: 'Could not load establishments',
            message: '${snap.error}',
            onRetry: _reload,
          );
        }
        final docs = snap.data?.docs ?? const <PublicFirestoreDoc>[];
        if (docs.isEmpty) {
          return const OptacaEmptyState(
            icon: Icons.storefront_outlined,
            title: 'No establishments yet',
            message: 'No establishment records are available to this account.',
          );
        }
        final q = _search.text.trim().toLowerCase();
        final filtered = [
          for (final doc in docs)
            if (q.isEmpty ||
                (doc.data()['name'] ?? doc.data()['establishmentName'] ?? '')
                    .toString()
                    .toLowerCase()
                    .contains(q) ||
                (doc.data()['municipality'] ?? doc.data()['location'] ?? '')
                    .toString()
                    .toLowerCase()
                    .contains(q))
              doc,
        ];
        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
              child: TextField(
                controller: _search,
                onChanged: (_) => setState(() {}),
                decoration: OptacaPortalUi.searchDecoration(
                  hint: 'Search establishments',
                ),
              ),
            ),
            Expanded(
              child: filtered.isEmpty
                  ? const OptacaEmptyState(
                      icon: Icons.search_off_outlined,
                      title: 'No matching establishments',
                      message: 'Try another name or municipality.',
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.all(20),
                      itemCount: filtered.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 10),
                      itemBuilder: (context, index) {
                        final data = filtered[index].data();
                        final name = (data['name'] ??
                                data['establishmentName'] ??
                                'Establishment')
                            .toString();
                        final place = (data['municipality'] ??
                                data['location'] ??
                                '')
                            .toString();
                        final category =
                            (data['category'] ?? data['type'] ?? '').toString();
                        return OptacaPortalCard(
                          padding: EdgeInsets.zero,
                          child: ListTile(
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 8,
                            ),
                            leading: Container(
                              width: 44,
                              height: 44,
                              decoration: BoxDecoration(
                                color: OptacaAdminTheme.lightOrange,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: const Icon(
                                Icons.storefront_outlined,
                                color: OptacaAdminTheme.primary,
                              ),
                            ),
                            title: Text(
                              name,
                              style: const TextStyle(fontWeight: FontWeight.w700),
                            ),
                            subtitle: Text(
                              [place, category]
                                  .where((s) => s.isNotEmpty)
                                  .join(' · '),
                              style: const TextStyle(
                                color: OptacaAdminTheme.textMuted,
                              ),
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ],
        );
      },
    );
  }
}

class _LguAccountManagementTab extends StatelessWidget {
  const _LguAccountManagementTab();

  @override
  Widget build(BuildContext context) {
    // Prefer ATMOS-injected panel when hosted inside ATMOS; otherwise use the
    // Trip Planner built-in panel (same Cloud Function + Firestore fallback).
    final host = TripPlanHostBridge.lguAccountManagementPanel;
    if (host != null) return host(context);
    return const OptacaAccountsPanel();
  }
}

class _AlertsQualityTab extends StatelessWidget {
  const _AlertsQualityTab();

  @override
  Widget build(BuildContext context) {
    final host = TripPlanHostBridge.alertsQualityPanel;
    if (host != null) return host(context);

    // Standalone Trip Planner fallback (ATMOS host not wired).
    final missingImage = <String>[];
    final missingCoordinates = <String>[];
    final missingMunicipality = <String>[];
    final missingQr = <String>[];
    for (final spot in allSpots) {
      if (spot.imagePath.trim().isEmpty) missingImage.add(spot.displayName);
      if (spot.latitude == null || spot.longitude == null) {
        missingCoordinates.add(spot.displayName);
      }
      if (spot.location.trim().isEmpty) {
        missingMunicipality.add(spot.displayName);
      }
      // Trip Planner TouristSpot model has no qr fields — flag via Firestore id when empty name/location already covered.
    }
    final groups = [
      (title: 'Missing image', icon: Icons.image_not_supported_outlined, names: missingImage),
      (title: 'Missing coordinates', icon: Icons.wrong_location_outlined, names: missingCoordinates),
      (title: 'Missing municipality', icon: Icons.location_off_outlined, names: missingMunicipality),
      (title: 'Missing QR (open from ATMOS for full QR audit)', icon: Icons.qr_code_2_outlined, names: missingQr),
    ];
    final total = missingImage.length +
        missingCoordinates.length +
        missingMunicipality.length;
    if (total == 0) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(32),
          child: Text(
            'No basic catalog gaps in loaded spots.\n'
            'Open this portal from ATMOS for the full QR + quality audit.',
            textAlign: TextAlign.center,
            style: TextStyle(color: AppColors.textGrey, height: 1.4),
          ),
        ),
      );
    }
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Text(
          '$total item${total == 1 ? '' : 's'} to review',
          style: const TextStyle(
            color: AppColors.textGrey,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 12),
        for (final group in groups)
          if (group.names.isNotEmpty) ...[
            Material(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              clipBehavior: Clip.antiAlias,
              child: ExpansionTile(
                leading: Icon(group.icon, color: const Color(0xFFC2410C)),
                title: Text(
                  group.title,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                subtitle: Text(
                  '${group.names.length} spot${group.names.length == 1 ? '' : 's'}',
                ),
                children: [
                  for (final name in group.names)
                    ListTile(
                      dense: true,
                      tileColor: Colors.white,
                      title: Text(name),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 10),
          ],
      ],
    );
  }
}

// ─── Overview ───────────────────────────────────────────────────────────

class _OverviewHeroBanner extends StatelessWidget {
  const _OverviewHeroBanner({required this.now});

  final DateTime now;

  static const _hostAsset =
      'linontripplanner-main/assets/images/capitolni.jpg';
  static const _packageAsset = 'assets/images/capitolni.jpg';
  static const _orange = Color(0xFFFF8A1F);

  static (List<double>, List<Color>) _fade(double width) {
    final start = width < 560
        ? 0.42
        : width < 900
            ? 0.36
            : 0.34;
    return (
      <double>[
        0.0,
        start,
        start + 0.06,
        start + 0.12,
        start + 0.18,
        start + 0.26,
        start + 0.34,
        1.0,
      ],
      const <Color>[
        _orange,
        _orange,
        Color(0xF2FF8A1F),
        Color(0xB8FF8A1F),
        Color(0x73FF7900),
        Color(0x2EE66D00),
        Color(0x0AE66D00),
        Color(0x00E66D00),
      ],
    );
  }

  Widget _capitolPhoto({int? cacheWidth}) {
    const align = Alignment(0, 0.08);
    return Image.asset(
      _hostAsset,
      fit: BoxFit.cover,
      alignment: align,
      cacheWidth: cacheWidth,
      filterQuality: FilterQuality.medium,
      gaplessPlayback: true,
      excludeFromSemantics: true,
      errorBuilder: (context, error, stackTrace) {
        debugPrint('Overview capitol host asset failed: $error');
        return Image.asset(
          _packageAsset,
          package: 'trip_plan',
          fit: BoxFit.cover,
          alignment: align,
          cacheWidth: cacheWidth,
          filterQuality: FilterQuality.medium,
          gaplessPlayback: true,
          excludeFromSemantics: true,
          errorBuilder: (context, error, stackTrace) {
            debugPrint('Overview capitol package asset failed: $error');
            return const SizedBox.expand();
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: OptacaAdminTheme.primary.withValues(alpha: 0.28),
            blurRadius: 24,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(18),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final width = constraints.maxWidth;
            final textMax = width < 560
                ? width * 0.92
                : width < 900
                    ? width * 0.58
                    : width * 0.48;
            final fade = _fade(width);
            final imageWidth = width < 560
                ? width * 0.58
                : width < 900
                    ? width * 0.60
                    : width * 0.64;
            final minHeight = width < 560
                ? 152.0
                : width < 900
                    ? 176.0
                    : 200.0;
            return SizedBox(
              height: minHeight,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  const Positioned.fill(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: OptacaAdminTheme.heroGradient,
                      ),
                    ),
                  ),
                  Positioned(
                    top: 0,
                    right: 0,
                    bottom: 0,
                    width: imageWidth,
                    child: RepaintBoundary(
                      child: _capitolPhoto(cacheWidth: 1400),
                    ),
                  ),
                  Positioned.fill(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.centerLeft,
                          end: Alignment.centerRight,
                          stops: fade.$1,
                          colors: fade.$2,
                        ),
                      ),
                    ),
                  ),
                  Positioned.fill(
                    child: CustomPaint(
                      painter: _OrangeWaveOverlayPainter(
                        color: OptacaAdminTheme.primary.withValues(alpha: 0.22),
                      ),
                    ),
                  ),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(24, 22, 24, 22),
                      child: ConstrainedBox(
                        constraints: BoxConstraints(maxWidth: textMax),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Provincial Tourism Dashboard',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 26,
                                fontWeight: FontWeight.w800,
                                height: 1.15,
                                letterSpacing: -0.4,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              '${_monthLabels[now.month - 1]} ${now.day}, ${now.year}',
                              style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.92),
                                fontSize: 13.5,
                                height: 1.35,
                              ),
                            ),
                          ],
                        ),
                      ),
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
}

/// Soft wave shapes for the provincial banner (visual only).
class _OrangeWaveOverlayPainter extends CustomPainter {
  const _OrangeWaveOverlayPainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = color;
    final path = Path()
      ..moveTo(size.width * 0.38, 0)
      ..cubicTo(
        size.width * 0.48,
        size.height * 0.18,
        size.width * 0.42,
        size.height * 0.42,
        size.width * 0.52,
        size.height * 0.55,
      )
      ..cubicTo(
        size.width * 0.62,
        size.height * 0.70,
        size.width * 0.56,
        size.height * 0.88,
        size.width * 0.68,
        size.height,
      )
      ..lineTo(size.width * 0.42, size.height)
      ..cubicTo(
        size.width * 0.34,
        size.height * 0.78,
        size.width * 0.36,
        size.height * 0.45,
        size.width * 0.28,
        size.height * 0.22,
      )
      ..close();
    canvas.drawPath(path, paint);

    final paint2 = Paint()..color = color.withValues(alpha: 0.55);
    final path2 = Path()
      ..moveTo(size.width * 0.50, 0)
      ..cubicTo(
        size.width * 0.58,
        size.height * 0.25,
        size.width * 0.54,
        size.height * 0.55,
        size.width * 0.64,
        size.height * 0.72,
      )
      ..cubicTo(
        size.width * 0.72,
        size.height * 0.86,
        size.width * 0.70,
        size.height * 0.96,
        size.width * 0.78,
        size.height,
      )
      ..lineTo(size.width * 0.55, size.height)
      ..cubicTo(
        size.width * 0.48,
        size.height * 0.80,
        size.width * 0.48,
        size.height * 0.40,
        size.width * 0.42,
        0,
      )
      ..close();
    canvas.drawPath(path2, paint2);
  }

  @override
  bool shouldRepaint(covariant _OrangeWaveOverlayPainter oldDelegate) =>
      oldDelegate.color != color;
}

class _OverviewTab extends StatefulWidget {
  const _OverviewTab({required this.onOpen});

  final ValueChanged<int> onOpen;

  @override
  State<_OverviewTab> createState() => _OverviewTabState();
}

class _OverviewTabState extends State<_OverviewTab> {
  ValueChanged<int> get onOpen => widget.onOpen;

  DateTime? _qrCheckInDateTime(Map<String, dynamic> raw) {
    dynamic read(Map<String, dynamic> d, String key) => d[key];
    final flat = <String, dynamic>{...raw};
    for (final nest in const [
      'checkIn',
      'check_in',
      'user',
      'profile',
      'tourist',
      'data',
      'payload',
    ]) {
      final inner = raw[nest];
      if (inner is Map<String, dynamic>) {
        for (final e in inner.entries) {
          flat.putIfAbsent(e.key, () => e.value);
        }
      }
    }
    for (final key in const [
      'checkInAt',
      'checkinAt',
      'visitAt',
      'createdAt',
      'timestamp',
      'timeStamp',
    ]) {
      final value = read(flat, key);
      if (value is Timestamp) return value.toDate();
      if (value is DateTime) return value;
      if (value is String) {
        final parsed = DateTime.tryParse(value.trim());
        if (parsed != null) return parsed;
      }
    }
    return null;
  }

  String _qrIdentity(Map<String, dynamic> raw) {
    final flat = <String, dynamic>{...raw};
    for (final nest in const [
      'checkIn',
      'check_in',
      'user',
      'profile',
      'tourist',
      'data',
      'payload',
    ]) {
      final inner = raw[nest];
      if (inner is Map<String, dynamic>) {
        for (final e in inner.entries) {
          flat.putIfAbsent(e.key, () => e.value);
        }
      }
    }
    for (final key in const [
      'userId',
      'uid',
      'firebaseUid',
      'touristID',
      'touristId',
      'email',
      'phone',
      'name',
      'fullName',
      'visitorName',
      'touristName',
    ]) {
      final value = flat[key];
      if (value == null) continue;
      final text = value.toString().trim();
      if (text.isNotEmpty) return text;
    }
    return '';
  }

  @override
  Widget build(BuildContext context) {
    return AdminLiveDataBuilder(
      builder: (context, live) {
        if ((live.touristsError != null || live.checkInsError != null) &&
            live.touristsReady &&
            live.checkInsReady &&
            live.tourists.isEmpty &&
            live.checkIns.isEmpty) {
          return OptacaLoadError(
            title: 'Dashboard data could not be loaded',
            message: '${live.touristsError ?? live.checkInsError}',
            onRetry: live.retry,
          );
        }
        final registryCount = live.tourists.length;
        final docs = live.checkIns;
        final now = DateTime.now();
        final todayIds = <String>{};
        for (final doc in docs) {
          final data = doc.data();
          final at = _qrCheckInDateTime(data);
          if (at == null) continue;
          final sameDay =
              at.year == now.year && at.month == now.month && at.day == now.day;
          if (!sameDay) continue;
          final id = _qrIdentity(data);
          if (id.isNotEmpty) todayIds.add(id);
        }
        final seededTourists = users
            .where((user) => AppRole.fromString(user.role) == AppRole.tourist)
            .length;
        final totalTourists = registryCount > 0
            ? registryCount
            : (seededTourists > 0 ? seededTourists : users.length);
        final touristsToday = todayIds.length;
        final totalCheckins = docs.length;
        final activeSpots = allSpots.length;
        final monthlyVisits = _visitsPerMonthFromCheckIns(docs);

        final nowDay = DateTime(now.year, now.month, now.day);
        final upcomingEvents = tourismEvents
            .where(
              (event) => eventExpandedCalendarDays(event)
                  .any((day) => !day.isBefore(nowDay)),
            )
            .length;

        final waiting = !live.touristsReady || !live.checkInsReady;
        return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 36),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _OverviewHeroBanner(now: now),
          const SizedBox(height: 18),
          const OptacaSectionHeader(
            title: 'Key figures',
          ),
          const SizedBox(height: 10),
          if (waiting)
            const OptacaKpiSkeletonRow()
          else
          LayoutBuilder(
            builder: (context, c) {
              final w = c.maxWidth;
              final cols = w >= 1200 ? 5 : (w >= 700 ? 2 : 1);
              final children = [
                _PortalStatCard(
                  title: 'Registered Tourists',
                  value: totalTourists,
                  icon: Icons.groups_2_outlined,
                ),
                _PortalStatCard(
                  title: 'Tourists Today',
                  value: touristsToday,
                  subtitle: 'Unique (1 per person across all LGUs)',
                  icon: Icons.qr_code_2_rounded,
                ),
                _PortalStatCard(
                  title: 'Total Check-ins',
                  value: totalCheckins,
                  icon: Icons.touch_app_outlined,
                ),
                _PortalStatCard(
                  title: 'Active Tourist Spots',
                  value: activeSpots,
                  icon: Icons.location_on_outlined,
                ),
                _PortalStatCard(
                  title: 'Upcoming Events',
                  value: upcomingEvents,
                  icon: Icons.event_outlined,
                ),
              ];
              if (cols >= 5) {
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (var i = 0; i < children.length; i++) ...[
                      if (i > 0) const SizedBox(width: 12),
                      Expanded(child: children[i]),
                    ],
                  ],
                );
              }
              if (cols == 2) {
                return Column(
                  children: [
                    for (var i = 0; i < children.length; i += 2) ...[
                      if (i > 0) const SizedBox(height: 16),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(child: children[i]),
                          const SizedBox(width: 16),
                          Expanded(
                            child: i + 1 < children.length
                                ? children[i + 1]
                                : const SizedBox.shrink(),
                          ),
                        ],
                      ),
                    ],
                  ],
                );
              }
              return Column(
                children: [
                  for (var i = 0; i < children.length; i++) ...[
                    if (i > 0) const SizedBox(height: 16),
                    children[i],
                  ],
                ],
              );
            },
          ),
          const SizedBox(height: 20),
          const OptacaSectionHeader(
            title: 'Arrivals and categories',
          ),
          const SizedBox(height: 10),
          LayoutBuilder(
            builder: (context, c) {
              final wide = c.maxWidth >= 900;
              final arrivals = _TouristArrivalsCard(monthly: monthlyVisits);
              final categories = _TopCategoriesDonutCard();
              if (wide) {
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(flex: 3, child: arrivals),
                    const SizedBox(width: 16),
                    Expanded(flex: 2, child: categories),
                  ],
                );
              }
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [arrivals, const SizedBox(height: 16), categories],
              );
            },
          ),
          const SizedBox(height: 20),
          const OptacaSectionHeader(
            title: 'High rating spots',
          ),
          const SizedBox(height: 10),
          _HighRatingSpotsCard(),
          const SizedBox(height: 20),
          const OptacaSectionHeader(
            title: 'Jump to a workspace',
          ),
          const SizedBox(height: 10),
          LayoutBuilder(
            builder: (context, c) {
              final cols = c.maxWidth >= 1100
                  ? 5
                  : c.maxWidth >= 720
                      ? 2
                      : 1;
              final actions = const [
                (index: 1, icon: Icons.people_outline_rounded, label: 'Tourist Monitoring'),
                (index: 5, icon: Icons.location_city_outlined, label: 'Municipality Performance'),
                (index: 6, icon: Icons.route_outlined, label: 'Trip Planner Analytics'),
                (index: 10, icon: Icons.assessment_outlined, label: 'DOT Reports'),
                (index: 11, icon: Icons.warning_amber_rounded, label: 'Alerts & Quality'),
              ];
              if (cols == 1) {
                return Column(
                  children: [
                    for (var i = 0; i < actions.length; i++) ...[
                      if (i > 0) const SizedBox(height: 10),
                      OptacaQuickLink(
                        icon: actions[i].icon,
                        label: actions[i].label,
                        onTap: () => onOpen(actions[i].index),
                      ),
                    ],
                  ],
                );
              }
              return Column(
                children: [
                  for (var i = 0; i < actions.length; i += cols) ...[
                    if (i > 0) const SizedBox(height: 10),
                    Row(
                      children: [
                        for (var j = 0; j < cols; j++) ...[
                          if (j > 0) const SizedBox(width: 10),
                          Expanded(
                            child: i + j < actions.length
                                ? OptacaQuickLink(
                                    icon: actions[i + j].icon,
                                    label: actions[i + j].label,
                                    onTap: () => onOpen(actions[i + j].index),
                                  )
                                : const SizedBox.shrink(),
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
      },
    );
  }
}

class _PortalStatCard extends StatefulWidget {
  final String title;
  final int value;
  final IconData icon;
  final String? subtitle;

  const _PortalStatCard({
    required this.title,
    required this.value,
    required this.icon,
    this.subtitle,
  });

  @override
  State<_PortalStatCard> createState() => _PortalStatCardState();
}

class _PortalStatCardState extends State<_PortalStatCard> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
        transform: Matrix4.translationValues(0, _hovered ? -3 : 0, 0),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: OptacaAdminTheme.primary
                  .withValues(alpha: _hovered ? 0.38 : 0.26),
              blurRadius: _hovered ? 22 : 16,
              offset: Offset(0, _hovered ? 10 : 7),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: DecoratedBox(
            decoration: const BoxDecoration(
              gradient: OptacaAdminTheme.kpiGradient,
            ),
            child: Stack(
              children: [
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  height: 42,
                  child: CustomPaint(
                    painter: _KpiWavePainter(
                      color: Colors.white.withValues(alpha: 0.16),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(18, 16, 16, 18),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Text(
                              widget.title,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: Colors.white.withValues(alpha: 0.94),
                                height: 1.2,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Container(
                            width: 40,
                            height: 40,
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(12),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.08),
                                  blurRadius: 8,
                                  offset: const Offset(0, 2),
                                ),
                              ],
                            ),
                            child: Icon(
                              widget.icon,
                              color: OptacaAdminTheme.primary,
                              size: 20,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      Text(
                        OptacaAdminTheme.formatCount(widget.value),
                        style: const TextStyle(
                          fontSize: 30,
                          fontWeight: FontWeight.w800,
                          color: Colors.white,
                          height: 1,
                          letterSpacing: -0.6,
                        ),
                      ),
                      if (widget.subtitle != null) ...[
                        const SizedBox(height: 6),
                        Text(
                          widget.subtitle!,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 11,
                            color: Colors.white.withValues(alpha: 0.86),
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ] else
                        const SizedBox(height: 16),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _KpiWavePainter extends CustomPainter {
  const _KpiWavePainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = color;
    final path = Path()
      ..moveTo(0, size.height * 0.55)
      ..quadraticBezierTo(
        size.width * 0.25,
        size.height * 0.15,
        size.width * 0.5,
        size.height * 0.45,
      )
      ..quadraticBezierTo(
        size.width * 0.75,
        size.height * 0.85,
        size.width,
        size.height * 0.35,
      )
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _KpiWavePainter oldDelegate) =>
      oldDelegate.color != color;
}

class _TouristArrivalsCard extends StatelessWidget {
  final List<int> monthly;

  const _TouristArrivalsCard({required this.monthly});

  @override
  Widget build(BuildContext context) {
    final maxVal = monthly.isEmpty
        ? 0
        : monthly.reduce((a, b) => a > b ? a : b);
    if (maxVal == 0) {
      return _chartShell(
        title: 'Tourist Arrivals',
        trailing: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: OptacaAdminTheme.lightOrange,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: OptacaAdminTheme.border),
          ),
          child: const Text(
            'By month',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: OptacaAdminTheme.darkOrange,
            ),
          ),
        ),
        child: const Center(
          child: Padding(
            padding: EdgeInsets.all(32),
            child: Text(
              'No arrival data yet. Tourist visit records will appear here.',
              textAlign: TextAlign.center,
              style: TextStyle(color: OptacaAdminTheme.textMuted),
            ),
          ),
        ),
      );
    }
    final maxY = (maxVal.toDouble() * 1.25).ceilToDouble();
    return _chartShell(
      title: 'Tourist Arrivals',
      trailing: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: OptacaAdminTheme.lightOrange,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: OptacaAdminTheme.border),
        ),
        child: const Text(
          'By month',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: OptacaAdminTheme.darkOrange,
          ),
        ),
      ),
      child: SizedBox(
        height: 220,
        child: LineChart(
          LineChartData(
            minX: 0,
            maxX: 11,
            minY: 0,
            maxY: maxY,
            gridData: FlGridData(
              show: true,
              drawVerticalLine: false,
              horizontalInterval: maxY > 5 ? (maxY / 5) : 1,
              getDrawingHorizontalLine: (v) => FlLine(
                color: OptacaAdminTheme.border.withValues(alpha: 0.65),
                strokeWidth: 1,
              ),
            ),
            titlesData: FlTitlesData(
              bottomTitles: AxisTitles(
                sideTitles: SideTitles(
                  showTitles: true,
                  reservedSize: 28,
                  interval: 1,
                  getTitlesWidget: (v, m) {
                    final i = v.toInt();
                    if (i >= 0 && i < _monthLabels.length) {
                      return Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Text(
                          _monthLabels[i],
                          style: const TextStyle(
                            fontSize: 10,
                            color: OptacaAdminTheme.textMuted,
                          ),
                        ),
                      );
                    }
                    return const SizedBox.shrink();
                  },
                ),
              ),
              leftTitles: AxisTitles(
                sideTitles: SideTitles(
                  showTitles: true,
                  reservedSize: 28,
                  interval: maxY > 5 ? (maxY / 5) : 1,
                  getTitlesWidget: (v, m) => Text(
                    v.toInt().toString(),
                    style: const TextStyle(
                      fontSize: 10,
                      color: OptacaAdminTheme.textMuted,
                    ),
                  ),
                ),
              ),
              topTitles: const AxisTitles(
                sideTitles: SideTitles(showTitles: false),
              ),
              rightTitles: const AxisTitles(
                sideTitles: SideTitles(showTitles: false),
              ),
            ),
            borderData: FlBorderData(show: false),
            lineBarsData: [
              LineChartBarData(
                spots: monthly
                    .asMap()
                    .entries
                    .map((e) => FlSpot(e.key.toDouble(), e.value.toDouble()))
                    .toList(),
                isCurved: true,
                color: OptacaAdminTheme.primary,
                barWidth: 3.2,
                isStrokeCapRound: true,
                dotData: FlDotData(
                  show: true,
                  getDotPainter: (spot, percent, bar, index) =>
                      FlDotCirclePainter(
                    radius: 3.2,
                    color: Colors.white,
                    strokeWidth: 2,
                    strokeColor: OptacaAdminTheme.primary,
                  ),
                ),
                belowBarData: BarAreaData(
                  show: true,
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      OptacaAdminTheme.primary.withValues(alpha: 0.34),
                      OptacaAdminTheme.secondary.withValues(alpha: 0.12),
                      OptacaAdminTheme.primary.withValues(alpha: 0.02),
                    ],
                  ),
                ),
              ),
            ],
            lineTouchData: const LineTouchData(enabled: true),
          ),
          duration: const Duration(milliseconds: 450),
          curve: Curves.easeOutCubic,
        ),
      ),
    );
  }
}

Widget _chartShell({
  required String title,
  required Widget child,
  Widget? trailing,
}) {
  return Container(
    padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
    decoration: OptacaAdminTheme.analyticsCardDecoration,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 8,
              height: 22,
              decoration: BoxDecoration(
                color: OptacaAdminTheme.primary,
                borderRadius: BorderRadius.circular(4),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                title,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  color: OptacaAdminTheme.text,
                ),
              ),
            ),
            if (trailing != null) trailing,
          ],
        ),
        const SizedBox(height: 16),
        child,
      ],
    ),
  );
}

class _TopCategoriesDonutCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final map = <String, int>{};
    for (final s in allSpots) {
      final t = s.type.isEmpty ? 'Other' : s.type;
      map[t] = (map[t] ?? 0) + 1;
    }
    if (map.isEmpty) {
      return _chartShell(
        title: 'Top Categories',
        trailing: TextButton(
          onPressed: () {},
          child: const Text(
            'View All',
            style: TextStyle(
              color: OptacaAdminTheme.primary,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        child: const SizedBox(
          height: 200,
          child: Center(
            child: Text(
              'Add tourist spots to see categories.',
              style: TextStyle(color: OptacaAdminTheme.textMuted),
            ),
          ),
        ),
      );
    }
    final total = map.values.fold<int>(0, (a, b) => a + b);
    final entries = map.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final top = entries.take(5).toList();
    final colors = [
      OptacaAdminTheme.primary,
      OptacaAdminTheme.secondary,
      _kPortalIconBlue,
      _kTrendGreen,
      const Color(0xFFAB47BC),
    ];
    final lead = top.first;
    final leadPct = total == 0 ? 0.0 : lead.value / total * 100;
    return _chartShell(
      title: 'Top Categories',
      trailing: TextButton(
        onPressed: () {},
        child: const Text(
          'View All',
          style: TextStyle(
            color: OptacaAdminTheme.primary,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final pie = SizedBox(
            height: 196,
            width: 196,
            child: Stack(
              alignment: Alignment.center,
              children: [
                PieChart(
                  PieChartData(
                    sectionsSpace: 2.5,
                    centerSpaceRadius: 54,
                    sections: List.generate(top.length, (i) {
                      final e = top[i];
                      final pct = (e.value / total * 100);
                      return PieChartSectionData(
                        color: colors[i % colors.length],
                        value: e.value.toDouble(),
                        title: pct >= 10 ? '${pct.toStringAsFixed(0)}%' : '',
                        radius: i == 0 ? 34 : 28,
                        titleStyle: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      );
                    }),
                  ),
                  duration: const Duration(milliseconds: 450),
                  curve: Curves.easeOutCubic,
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 28),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        '${leadPct.toStringAsFixed(0)}%',
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w800,
                          color: OptacaAdminTheme.primary,
                          height: 1,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        lead.key,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w600,
                          color: OptacaAdminTheme.textMuted,
                          height: 1.2,
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
              for (var i = 0; i < top.length; i++)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Row(
                    children: [
                      Container(
                        width: 10,
                        height: 10,
                        decoration: BoxDecoration(
                          color: colors[i % colors.length],
                          borderRadius: BorderRadius.circular(3),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          top[i].key,
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: OptacaAdminTheme.text,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      Text(
                        '${(top[i].value / total * 100).toStringAsFixed(0)}%',
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: OptacaAdminTheme.textMuted,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          );
          if (constraints.maxWidth < 420) {
            return Column(
              children: [
                pie,
                const SizedBox(height: 12),
                legend,
              ],
            );
          }
          return Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              pie,
              const SizedBox(width: 12),
              Expanded(child: legend),
            ],
          );
        },
      ),
    );
  }
}

// ─── Analytics Tab ─────────────────────────────────────────────────────

// QR check-in parsing lives in services/reports/report_check_ins.dart so the
// dashboard tabs and the Reports page agree on how records are read.

/// Month labels for Jan–Dec.
const List<String> _monthLabels = [
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

/// Visits per month (Jan-Dec) from QR check-ins.
List<int> _visitsPerMonthFromCheckIns(
  Iterable<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
) => visitsPerMonthFromCheckIns(docs);

Map<String, int> _visitsPerMunicipalityFromRecords(
  List<CheckInRecord> records,
) {
  final map = <String, int>{for (final m in municipalities) m.name: 0};
  for (final record in records) {
    final name = record.municipalityName;
    if (name.isEmpty) continue;
    map[name] = (map[name] ?? 0) + 1;
  }
  return map;
}

List<int> _visitsPerMonthFromRecords(List<CheckInRecord> records) {
  final monthly = List<int>.filled(12, 0);
  for (final record in records) {
    final at = record.at;
    if (at == null) continue;
    final m = at.month;
    if (m >= 1 && m <= 12) monthly[m - 1]++;
  }
  return monthly;
}

List<int> _visitsPerDayThisMonthFromRecords(List<CheckInRecord> records) {
  final now = DateTime.now();
  final daysInMonth = DateTime(now.year, now.month + 1, 0).day;
  final daily = List<int>.filled(daysInMonth, 0);
  for (final record in records) {
    final at = record.at;
    if (at == null) continue;
    if (at.year == now.year && at.month == now.month) {
      daily[at.day - 1]++;
    }
  }
  return daily;
}

/// Rounds chart peak to a clean max (e.g. 57) with ~5 horizontal grid lines.
double _chartMaxY(List<int> values) {
  if (values.isEmpty) return 57;
  final peak = values.reduce((a, b) => a > b ? a : b);
  if (peak <= 0) return 57;
  final padded = (peak * 1.15).ceil();
  const niceMax = [11, 22, 34, 45, 57, 70, 85, 100, 120, 150, 200, 250, 300];
  for (final n in niceMax) {
    if (n >= padded) return n.toDouble();
  }
  return ((padded / 50).ceil() * 50).toDouble();
}

/// First index of the trailing zero plateau (flat line along the bottom).
int _plateauStartIndex(List<FlSpot> spots) {
  var lastPositive = -1;
  for (var i = 0; i < spots.length; i++) {
    if (spots[i].y > 0) lastPositive = i;
  }
  if (lastPositive < 0) return 0;
  for (var i = lastPositive + 1; i < spots.length; i++) {
    if (spots[i].y <= 0) return i;
  }
  return spots.length;
}

/// Curved peak + straight flat tail so the line stays visible at y = 0.
List<LineChartBarData> _touristArrivalsLineBars(List<FlSpot> spots) {
  const lineStyle = (
    color: AppColors.primary,
    width: 2.5,
  );

  if (spots.length < 2) {
    return [
      LineChartBarData(
        spots: spots,
        isCurved: false,
        color: lineStyle.color,
        barWidth: lineStyle.width,
        dotData: const FlDotData(show: false),
      ),
    ];
  }

  final plateauAt = _plateauStartIndex(spots);
  if (plateauAt >= spots.length) {
    return [
      LineChartBarData(
        spots: spots,
        isCurved: true,
        curveSmoothness: 0.28,
        preventCurveOverShooting: true,
        preventCurveOvershootingThreshold: 0,
        color: lineStyle.color,
        barWidth: lineStyle.width,
        isStrokeCapRound: true,
        dotData: const FlDotData(show: false),
        belowBarData: BarAreaData(
          show: true,
          cutOffY: 0,
          applyCutOffY: true,
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              AppColors.primary.withValues(alpha: 0.35),
              AppColors.primary.withValues(alpha: 0.02),
            ],
          ),
        ),
      ),
    ];
  }

  final curvedEnd = plateauAt.clamp(0, spots.length - 1);
  final curvedSpots = spots.sublist(0, curvedEnd + 1);
  final flatSpots = spots.sublist(curvedEnd);

  return [
    LineChartBarData(
      spots: curvedSpots,
      isCurved: true,
      curveSmoothness: 0.28,
      preventCurveOverShooting: true,
      preventCurveOvershootingThreshold: 0,
      color: lineStyle.color,
      barWidth: lineStyle.width,
      isStrokeCapRound: true,
      dotData: const FlDotData(show: false),
      belowBarData: BarAreaData(
        show: true,
        cutOffY: 0,
        applyCutOffY: true,
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            AppColors.primary.withValues(alpha: 0.35),
            AppColors.primary.withValues(alpha: 0.02),
          ],
        ),
      ),
    ),
    LineChartBarData(
      spots: flatSpots,
      isCurved: false,
      color: lineStyle.color,
      barWidth: lineStyle.width,
      isStrokeCapRound: true,
      dotData: const FlDotData(show: false),
      belowBarData: BarAreaData(show: false),
    ),
  ];
}

enum _AnalyticsPeriod { thisMonth, thisYear }

const _analyticsPeriodLabels = {
  _AnalyticsPeriod.thisMonth: 'This Month',
  _AnalyticsPeriod.thisYear: 'This Year',
};

class _AnalyticsTab extends StatefulWidget {
  final VoidCallback onChanged;

  const _AnalyticsTab({required this.onChanged});

  @override
  State<_AnalyticsTab> createState() => _AnalyticsTabState();
}

class _AnalyticsTabState extends State<_AnalyticsTab> {
  _AnalyticsPeriod _period = _AnalyticsPeriod.thisYear;

  Widget _periodFilterChip() {
    return PopupMenuButton<_AnalyticsPeriod>(
      initialValue: _period,
      onSelected: (v) => setState(() => _period = v),
      offset: const Offset(0, 40),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      itemBuilder: (ctx) => _AnalyticsPeriod.values
          .map(
            (p) => PopupMenuItem(
              value: p,
              child: Text(_analyticsPeriodLabels[p]!),
            ),
          )
          .toList(),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: const Color(0xFFE5E5E5)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              _analyticsPeriodLabels[_period]!,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: AppColors.textDark,
              ),
            ),
            const SizedBox(width: 4),
            const Icon(
              Icons.keyboard_arrow_down_rounded,
              size: 20,
              color: AppColors.textGrey,
            ),
          ],
        ),
      ),
    );
  }

  Widget _touristArrivalsChart({
    required List<int> series,
    required List<String> xLabels,
    required double maxX,
  }) {
    final maxY = _chartMaxY(series);
    final spots = series
        .asMap()
        .entries
        .map((e) => FlSpot(e.key.toDouble(), e.value.toDouble()))
        .toList();

    if (spots.isEmpty) {
      return const SizedBox(
        height: 260,
        child: Center(
          child: Text(
            'No arrivals in this period',
            style: TextStyle(color: AppColors.textGrey),
          ),
        ),
      );
    }
    final chartMaxX = maxX < 1 ? 1.0 : maxX;
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: SizedBox(
        height: 260,
        child: RepaintBoundary(
        child: LineChart(
          LineChartData(
            minX: 0,
            maxX: chartMaxX,
            minY: 0,
            maxY: maxY,
            clipData: const FlClipData.none(),
            gridData: const FlGridData(show: false),
            titlesData: FlTitlesData(
              show: true,
              bottomTitles: AxisTitles(
                sideTitles: SideTitles(
                  showTitles: true,
                  reservedSize: 32,
                  interval: 1,
                  getTitlesWidget: (value, meta) {
                    final i = value.toInt();
                    if (i < 0 || i >= xLabels.length) {
                      return const SizedBox.shrink();
                    }
                    if (_period == _AnalyticsPeriod.thisMonth &&
                        xLabels.length > 12 &&
                        i % 5 != 0 &&
                        i != xLabels.length - 1) {
                      return const SizedBox.shrink();
                    }
                    return Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: Text(
                        xLabels[i],
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                          color: AppColors.textDark,
                        ),
                      ),
                    );
                  },
                ),
              ),
              leftTitles: const AxisTitles(
                sideTitles: SideTitles(showTitles: false, reservedSize: 8),
              ),
              topTitles: const AxisTitles(
                sideTitles: SideTitles(showTitles: false),
              ),
              rightTitles: const AxisTitles(
                sideTitles: SideTitles(showTitles: false),
              ),
            ),
            borderData: FlBorderData(show: false),
            lineBarsData: _touristArrivalsLineBars(spots),
          lineTouchData: LineTouchData(
            enabled: true,
            touchTooltipData: LineTouchTooltipData(
              getTooltipColor: (_) => AppColors.textDark,
              tooltipRoundedRadius: 8,
              getTooltipItems: (touchedSpots) => touchedSpots
                  .map(
                    (s) => LineTooltipItem(
                      '${s.y.toInt()} arrival(s)',
                      const TextStyle(color: Colors.white, fontSize: 12),
                    ),
                  )
                  .toList(),
            ),
          ),
          ),
          duration: const Duration(milliseconds: 250),
        ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AdminLiveDataBuilder(
      builder: (context, live) {
        if (live.checkInsError != null &&
            live.checkInsReady &&
            live.checkIns.isEmpty) {
          return OptacaLoadError(
            title: 'Arrivals could not be loaded',
            message: '${live.checkInsError}',
            onRetry: live.retry,
          );
        }
        final docs = live.checkIns;
        final records =
            live.checkInsReady ? live.checkInRecords : const <CheckInRecord>[];
        final visits = _visitsPerMunicipalityFromRecords(records);
        final sortedMunis = List<String>.from(municipalities.map((m) => m.name))
          ..sort((a, b) {
            final byVisits =
                (visits[b] ?? 0).compareTo(visits[a] ?? 0);
            if (byVisits != 0) return byVisits;
            return a.compareTo(b);
          });

        final List<int> series;
        final List<String> xLabels;
        final double maxX;
        if (_period == _AnalyticsPeriod.thisYear) {
          series = _visitsPerMonthFromRecords(records);
          xLabels = _monthLabels;
          maxX = 11;
        } else {
          series = _visitsPerDayThisMonthFromRecords(records);
          xLabels = List.generate(
            series.length,
            (i) => '${i + 1}',
          );
          maxX = series.isEmpty ? 0 : (series.length - 1).toDouble();
        }

        return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.fromLTRB(20, 20, 16, 12),
            decoration: TourismPlanUi.planCardDecoration(),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Expanded(
                      child: Text(
                        'Tourist Arrivals',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textDark,
                          letterSpacing: -0.2,
                        ),
                      ),
                    ),
                    _periodFilterChip(),
                  ],
                ),
                const SizedBox(height: 8),
                _touristArrivalsChart(
                  series: series,
                  xLabels: xLabels,
                  maxX: maxX,
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          const Text(
            'Municipalities & cities',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: AppColors.textDark,
            ),
          ),
          const SizedBox(height: 12),
          if (!live.checkInsReady && docs.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: Center(
                child: CircularProgressIndicator(color: AppColors.primary),
              ),
            )
          else if (sortedMunis.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Text(
                'No municipalities loaded yet.',
                style: TextStyle(color: Colors.grey.shade600, fontSize: 14),
              ),
            )
          else
            ...sortedMunis.map((name) {
              final count = visits[name] ?? 0;
              final idx =
                  municipalities.indexWhere((m) => m.name == name);
              final muni = idx >= 0 ? municipalities[idx] : null;
              return TourismPeachListTile(
                title: name,
                subtitle: count == 1 ? '1 visit' : '$count visit(s)',
                leading: muni == null
                    ? null
                    : ClipOval(
                        child: SizedBox(
                          width: 46,
                          height: 46,
                          child: buildMunicipalityImageForMunicipality(
                            muni,
                            memCacheWidth: 92,
                            memCacheHeight: 92,
                            fallback: Container(
                              color: AppColors.primary.withValues(alpha: 0.12),
                              child: const Icon(
                                Icons.location_city_rounded,
                                color: AppColors.primary,
                                size: 24,
                              ),
                            ),
                          ),
                        ),
                      ),
                onTap: () async {
                  if (idx < 0) return;
                  await Navigator.of(context).push<void>(
                    MaterialPageRoute<void>(
                      builder: (ctx) => _AdminMunicipalitySpotsScreen(
                        municipality: municipalities[idx],
                        checkInVisitCount: count,
                        onChanged: widget.onChanged,
                      ),
                    ),
                  );
                  if (mounted) setState(() {});
                  widget.onChanged();
                },
              );
            }),
        ],
      ),
        );
      },
    );
  }
}

/// Per-municipality analytics: bar chart of spots in that municipality (visits = ratings count).
class _MunicipalityAnalyticsDetail extends StatelessWidget {
  final String municipalityName;

  const _MunicipalityAnalyticsDetail({required this.municipalityName});

  @override
  Widget build(BuildContext context) {
    final munIndex =
        municipalities.indexWhere((m) => m.name == municipalityName);
    final spotsInMuni = munIndex >= 0
        ? allSpots
            .where(
              (s) => touristSpotBelongsToMunicipality(
                s,
                municipalities[munIndex],
              ),
            )
            .toList()
        : allSpots
            .where(
              (s) =>
                  s.location.toLowerCase().trim() ==
                  municipalityName.toLowerCase().trim(),
            )
            .toList();
    final Map<String, int> visitsPerSpot = {};
    for (final s in spotsInMuni) {
      visitsPerSpot[s.name] = spotRatings
          .where((r) => r.spotName == s.name)
          .length;
    }
    final sortedSpots = List<String>.from(
      spotsInMuni.map((s) => s.name),
    )..sort((a, b) => (visitsPerSpot[b] ?? 0).compareTo(visitsPerSpot[a] ?? 0));
    final maxVisits = visitsPerSpot.values.isEmpty
        ? 1.0
        : visitsPerSpot.values.reduce((a, b) => a > b ? a : b).toDouble();

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text('$municipalityName analytics'),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Visits per tourist spot',
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: AppColors.textDark,
              ),
            ),
            const SizedBox(height: 12),
            if (sortedSpots.isEmpty)
              Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.06),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: const Center(
                  child: Text(
                    'No spots or ratings in this municipality yet.',
                    style: TextStyle(color: AppColors.textGrey),
                  ),
                ),
              )
            else
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.06),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: SizedBox(
                  height: 220,
                  child: BarChart(
                    BarChartData(
                      alignment: BarChartAlignment.spaceAround,
                      maxY: maxVisits < 1
                          ? 5
                          : (maxVisits * 1.2).ceilToDouble(),
                      barTouchData: BarTouchData(
                        enabled: true,
                        touchTooltipData: BarTouchTooltipData(
                          getTooltipColor: (_) => AppColors.textDark,
                          tooltipRoundedRadius: 8,
                          getTooltipItem: (group, groupIndex, rod, rodIndex) {
                            final name = groupIndex < sortedSpots.length
                                ? sortedSpots[groupIndex]
                                : '';
                            return BarTooltipItem(
                              '$name\n${rod.toY.round()} visit(s)',
                              const TextStyle(
                                color: Colors.white,
                                fontSize: 12,
                              ),
                            );
                          },
                        ),
                      ),
                      titlesData: FlTitlesData(
                        show: true,
                        bottomTitles: AxisTitles(
                          sideTitles: SideTitles(
                            showTitles: true,
                            reservedSize: 28,
                            getTitlesWidget: (value, meta) {
                              final i = value.toInt();
                              if (i >= 0 && i < sortedSpots.length) {
                                final name = sortedSpots[i];
                                final short = name.length > 12
                                    ? '${name.substring(0, 10)}…'
                                    : name;
                                return Padding(
                                  padding: const EdgeInsets.only(top: 8),
                                  child: Text(
                                    short,
                                    style: const TextStyle(
                                      fontSize: 10,
                                      color: AppColors.textGrey,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                );
                              }
                              return const SizedBox.shrink();
                            },
                          ),
                        ),
                        leftTitles: AxisTitles(
                          sideTitles: SideTitles(
                            showTitles: true,
                            reservedSize: 32,
                            getTitlesWidget: (value, meta) => Text(
                              value.toInt().toString(),
                              style: const TextStyle(
                                fontSize: 11,
                                color: AppColors.textGrey,
                              ),
                            ),
                          ),
                        ),
                        topTitles: const AxisTitles(
                          sideTitles: SideTitles(showTitles: false),
                        ),
                        rightTitles: const AxisTitles(
                          sideTitles: SideTitles(showTitles: false),
                        ),
                      ),
                      gridData: FlGridData(
                        show: true,
                        drawVerticalLine: false,
                        horizontalInterval: 1,
                        getDrawingHorizontalLine: (value) => FlLine(
                          color: Colors.grey.withOpacity(0.2),
                          strokeWidth: 1,
                        ),
                      ),
                      borderData: FlBorderData(show: false),
                      barGroups: List.generate(sortedSpots.length, (i) {
                        final name = sortedSpots[i];
                        final count = visitsPerSpot[name] ?? 0;
                        return BarChartGroupData(
                          x: i,
                          barRods: [
                            BarChartRodData(
                              toY: count.toDouble(),
                              color: AppColors.primary,
                              width: 20,
                              borderRadius: const BorderRadius.vertical(
                                top: Radius.circular(4),
                              ),
                            ),
                          ],
                          showingTooltipIndicators: [0],
                        );
                      }),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// ─── High rating spots map (Overview) ────────────────────────────────────

class _HighRatingSpotsCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final sortedByRating = List<TouristSpot>.from(allSpots)
      ..sort((a, b) => b.rating.compareTo(a.rating));
    final spotsWithLocation = sortedByRating
        .where((s) => s.latitude != null && s.longitude != null)
        .toList();

    return Container(
      decoration: OptacaAdminTheme.analyticsCardDecoration,
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(18, 16, 18, 0),
            child: Row(
              children: [
                Icon(Icons.star_rounded, color: OptacaAdminTheme.primary, size: 20),
                SizedBox(width: 8),
                Text(
                  'Map of top-rated destinations',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: OptacaAdminTheme.text,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          if (sortedByRating.isEmpty)
            const Padding(
              padding: EdgeInsets.all(24),
              child: Text(
                'No tourist spots yet. Add spots in the Spots tab.',
                style: TextStyle(fontSize: 14, color: OptacaAdminTheme.textMuted),
              ),
            )
          else if (spotsWithLocation.isEmpty)
            Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Add latitude & longitude to spots in the Spots tab to see them on the map.',
                    style: TextStyle(fontSize: 14, color: OptacaAdminTheme.textMuted),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(height: 200, child: _buildMap(context, [])),
                ],
              ),
            )
          else
            SizedBox(height: 280, child: _buildMap(context, spotsWithLocation)),
        ],
      ),
    );
  }

  Widget _buildMap(BuildContext context, List<TouristSpot> spots) {
    return AdminHighRatingSpotsMap(spots: spots);
  }
}

// ─── Featured list ──────────────────────────────────────────────────────

enum _FeaturedSortMode {
  newestFirst,
  oldestFirst,
  highestRated,
  lowestRated,
  nameAz,
  nameZa,
}

class AdminFeaturedSpotsTab extends StatefulWidget {
  final VoidCallback onChanged;

  const AdminFeaturedSpotsTab({super.key, required this.onChanged});

  @override
  State<AdminFeaturedSpotsTab> createState() => _FeaturedListTabState();
}

class _FeaturedListTabState extends State<AdminFeaturedSpotsTab> {
  bool _loading = true;
  final TextEditingController _search = TextEditingController();
  _FeaturedSortMode _sort = _FeaturedSortMode.newestFirst;
  /// Reference UI is horizontal list cards; grid remains available via toggle.
  bool _gridView = false;

  @override
  void initState() {
    super.initState();
    _loading = featuredSpots.isEmpty;
    _refresh(silent: featuredSpots.isNotEmpty);
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _refresh({bool silent = false}) async {
    if (!silent && mounted) setState(() => _loading = true);
    try {
      await loadFeaturedSpotsFromFirestore().timeout(
        const Duration(seconds: 25),
      );
    } catch (e, st) {
      debugPrint('Featured spots load: $e\n$st');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  TouristSpot? _linkedTouristSpot(FeaturedSpot featured) {
    return findTouristSpotByNameFuzzy(featured.name);
  }

  String _municipalityOf(FeaturedSpot featured) {
    final linked = _linkedTouristSpot(featured);
    final location = (linked?.location ?? '').trim();
    if (location.isNotEmpty) return location;
    return '—';
  }

  /// Prefer live tourist-spot average rating; fall back to featured record.
  double _ratingOf(FeaturedSpot featured) {
    final linked = _linkedTouristSpot(featured);
    if (linked != null && linked.rating > 0) return linked.rating;
    return featured.rating;
  }

  /// Existing featured numerical value (`priceRange`), preserved as-is.
  String _existingNumberOf(FeaturedSpot featured) {
    final raw = featured.priceRange.trim();
    if (raw.isEmpty) return '—';
    final digits = raw.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.isNotEmpty && RegExp(r'^\d+$').hasMatch(digits)) {
      final n = int.tryParse(digits);
      if (n != null) return OptacaAdminTheme.formatCount(n);
    }
    return raw;
  }

  List<FeaturedSpot> _filteredSorted() {
    final q = _search.text.trim().toLowerCase();
    final list = featuredSpots.where((spot) {
      if (q.isEmpty) return true;
      final muni = _municipalityOf(spot).toLowerCase();
      return spot.name.toLowerCase().contains(q) || muni.contains(q);
    }).toList();

    int byName(FeaturedSpot a, FeaturedSpot b) =>
        a.name.toLowerCase().compareTo(b.name.toLowerCase());

    switch (_sort) {
      case _FeaturedSortMode.newestFirst:
        // Keep Firestore / catalog order (current featured sequence).
        break;
      case _FeaturedSortMode.oldestFirst:
        return list.reversed.toList(growable: false);
      case _FeaturedSortMode.highestRated:
        list.sort((a, b) {
          final byRating = _ratingOf(b).compareTo(_ratingOf(a));
          return byRating != 0 ? byRating : byName(a, b);
        });
      case _FeaturedSortMode.lowestRated:
        list.sort((a, b) {
          final byRating = _ratingOf(a).compareTo(_ratingOf(b));
          return byRating != 0 ? byRating : byName(a, b);
        });
      case _FeaturedSortMode.nameAz:
        list.sort(byName);
      case _FeaturedSortMode.nameZa:
        list.sort((a, b) => byName(b, a));
    }
    return list;
  }

  Future<void> _openForm({FeaturedSpot? existing, int? index}) async {
    await showAdminFeaturedFormDialog(
      context,
      existing: existing,
      index: index,
    );
    await _refresh();
    widget.onChanged();
  }

  void _deleteFeatured(FeaturedSpot spot) {
    final index = featuredSpots.indexOf(spot);
    _confirmDelete(context, spot.name, () {
      if (index >= 0 && index < featuredSpots.length) {
        featuredSpots.removeAt(index);
      } else {
        featuredSpots.removeWhere((s) => s.name == spot.name);
      }
      deleteFeaturedSpotFromFirestoreByName(spot.name).catchError((_) {});
      widget.onChanged();
      if (mounted) setState(() {});
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_loading && featuredSpots.isEmpty) {
      return const Center(
        child: CircularProgressIndicator(color: AppColors.primary),
      );
    }

    final visible = _filteredSorted();

    return RefreshIndicator(
      color: AppColors.primary,
      onRefresh: _refresh,
      child: Stack(
        children: [
          ListView(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 96),
            physics: const AlwaysScrollableScrollPhysics(),
            children: [
              const _FeaturedDestinationsPageHeader(),
              const SizedBox(height: 14),
              _FeaturedToolbar(
                search: _search,
                sort: _sort,
                gridView: _gridView,
                onSearch: (_) => setState(() {}),
                onSort: (mode) => setState(() => _sort = mode),
                onGridView: (grid) => setState(() => _gridView = grid),
              ),
              const SizedBox(height: 14),
              if (visible.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 48),
                  child: OptacaEmptyState(
                    icon: Icons.star_outline_rounded,
                    title: 'No featured destinations',
                    message:
                        'Tap Add Featured Destination, or pull down to refresh.',
                  ),
                )
              else if (_gridView)
                LayoutBuilder(
                  builder: (context, c) {
                    final cols = c.maxWidth >= 1100
                        ? 3
                        : c.maxWidth >= 720
                            ? 2
                            : 1;
                    return GridView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: visible.length,
                      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: cols,
                        crossAxisSpacing: 12,
                        mainAxisSpacing: 12,
                        childAspectRatio: cols == 1 ? 2.4 : 1.35,
                      ),
                      itemBuilder: (context, i) {
                        final spot = visible[i];
                        return _FeaturedDestinationCard(
                          spot: spot,
                          rank: i + 1,
                          municipality: _municipalityOf(spot),
                          existingNumber: _existingNumberOf(spot),
                          rating: _ratingOf(spot),
                          grid: true,
                          onEdit: () => _openForm(
                            existing: spot,
                            index: featuredSpots.indexOf(spot),
                          ),
                          onDelete: () => _deleteFeatured(spot),
                        );
                      },
                    );
                  },
                )
              else
                Column(
                  children: [
                    for (var i = 0; i < visible.length; i++) ...[
                      if (i > 0) const SizedBox(height: 10),
                      _FeaturedDestinationCard(
                        spot: visible[i],
                        rank: i + 1,
                        municipality: _municipalityOf(visible[i]),
                        existingNumber: _existingNumberOf(visible[i]),
                        rating: _ratingOf(visible[i]),
                        grid: false,
                        onEdit: () => _openForm(
                          existing: visible[i],
                          index: featuredSpots.indexOf(visible[i]),
                        ),
                        onDelete: () => _deleteFeatured(visible[i]),
                      ),
                    ],
                  ],
                ),
            ],
          ),
          Positioned(
            right: 20,
            bottom: 20,
            child: DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(28),
                boxShadow: [
                  BoxShadow(
                    color: OptacaAdminTheme.primary.withValues(alpha: 0.35),
                    blurRadius: 16,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              child: FilledButton.icon(
                onPressed: () => _openForm(),
                icon: const Icon(Icons.add, size: 20),
                label: const Text('Add Featured Destination'),
                style: FilledButton.styleFrom(
                  backgroundColor: OptacaAdminTheme.primary,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 18,
                    vertical: 16,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(28),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _FeaturedDestinationsPageHeader extends StatelessWidget {
  const _FeaturedDestinationsPageHeader();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF6EC),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: OptacaAdminTheme.border.withValues(alpha: 0.75),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 4,
            height: 46,
            margin: const EdgeInsets.only(right: 12),
            decoration: BoxDecoration(
              color: OptacaAdminTheme.primary,
              borderRadius: BorderRadius.circular(4),
            ),
          ),
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              gradient: OptacaAdminTheme.kpiGradient,
              borderRadius: BorderRadius.circular(13),
              boxShadow: [
                BoxShadow(
                  color: OptacaAdminTheme.primary.withValues(alpha: 0.25),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: const Icon(
              Icons.workspace_premium_rounded,
              color: Colors.white,
              size: 24,
            ),
          ),
          const SizedBox(width: 12),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Featured Destinations',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w900,
                    color: OptacaAdminTheme.text,
                    letterSpacing: -0.2,
                    height: 1.15,
                  ),
                ),
                SizedBox(height: 4),
                Text(
                  'Highlight and manage the top tourist destinations.',
                  style: TextStyle(
                    fontSize: 12.5,
                    height: 1.35,
                    color: OptacaAdminTheme.textMuted,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          const IgnorePointer(
            child: CustomPaint(
              size: Size(68, 52),
              painter: _TouristSpotsHeaderArtPainter(),
            ),
          ),
        ],
      ),
    );
  }
}

class _FeaturedToolbar extends StatelessWidget {
  const _FeaturedToolbar({
    required this.search,
    required this.sort,
    required this.gridView,
    required this.onSearch,
    required this.onSort,
    required this.onGridView,
  });

  final TextEditingController search;
  final _FeaturedSortMode sort;
  final bool gridView;
  final ValueChanged<String> onSearch;
  final ValueChanged<_FeaturedSortMode> onSort;
  final ValueChanged<bool> onGridView;

  String _sortLabel(_FeaturedSortMode mode) => switch (mode) {
        _FeaturedSortMode.newestFirst => 'Newest First',
        _FeaturedSortMode.oldestFirst => 'Oldest First',
        _FeaturedSortMode.highestRated => 'Highest Rated',
        _FeaturedSortMode.lowestRated => 'Lowest Rated',
        _FeaturedSortMode.nameAz => 'Name A–Z',
        _FeaturedSortMode.nameZa => 'Name Z–A',
      };

  @override
  Widget build(BuildContext context) {
    final searchField = Material(
      elevation: 0,
      borderRadius: BorderRadius.circular(24),
      child: TextField(
        controller: search,
        onChanged: onSearch,
        decoration: InputDecoration(
          hintText: 'Search featured destination...',
          hintStyle: const TextStyle(
            color: OptacaAdminTheme.textMuted,
            fontSize: 13.5,
            fontWeight: FontWeight.w500,
          ),
          prefixIcon: const Icon(
            Icons.search_rounded,
            color: OptacaAdminTheme.primary,
          ),
          filled: true,
          fillColor: Colors.white,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 14,
          ),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(24),
            borderSide: const BorderSide(color: OptacaAdminTheme.border),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(24),
            borderSide: const BorderSide(color: OptacaAdminTheme.border),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(24),
            borderSide: const BorderSide(
              color: OptacaAdminTheme.primary,
              width: 1.4,
            ),
          ),
        ),
      ),
    );

    final sortMenu = PopupMenuButton<_FeaturedSortMode>(
      initialValue: sort,
      tooltip: 'Sort',
      onSelected: onSort,
      itemBuilder: (context) => [
        for (final mode in _FeaturedSortMode.values)
          PopupMenuItem(value: mode, child: Text(_sortLabel(mode))),
      ],
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: OptacaAdminTheme.border),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.swap_vert_rounded,
              size: 18,
              color: OptacaAdminTheme.primary,
            ),
            const SizedBox(width: 8),
            Text(
              _sortLabel(sort),
              style: const TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 13,
              ),
            ),
            const SizedBox(width: 4),
            const Icon(Icons.keyboard_arrow_down_rounded, size: 18),
          ],
        ),
      ),
    );

    final toggle = Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: OptacaAdminTheme.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _viewChip(
            selected: gridView,
            icon: Icons.grid_view_rounded,
            onTap: () => onGridView(true),
          ),
          _viewChip(
            selected: !gridView,
            icon: Icons.view_agenda_rounded,
            onTap: () => onGridView(false),
          ),
        ],
      ),
    );

    return LayoutBuilder(
      builder: (context, c) {
        if (c.maxWidth < 820) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              searchField,
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(child: sortMenu),
                  const SizedBox(width: 10),
                  toggle,
                ],
              ),
            ],
          );
        }
        return Row(
          children: [
            Expanded(child: searchField),
            const SizedBox(width: 10),
            sortMenu,
            const SizedBox(width: 10),
            toggle,
          ],
        );
      },
    );
  }

  Widget _viewChip({
    required bool selected,
    required IconData icon,
    required VoidCallback onTap,
  }) {
    return Material(
      color: selected ? OptacaAdminTheme.primary : Colors.transparent,
      borderRadius: BorderRadius.circular(9),
      child: InkWell(
        borderRadius: BorderRadius.circular(9),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          child: Icon(
            icon,
            size: 18,
            color: selected ? Colors.white : OptacaAdminTheme.textMuted,
          ),
        ),
      ),
    );
  }
}

class _FeaturedDestinationCard extends StatelessWidget {
  const _FeaturedDestinationCard({
    required this.spot,
    required this.rank,
    required this.municipality,
    required this.existingNumber,
    required this.rating,
    required this.grid,
    required this.onEdit,
    required this.onDelete,
  });

  final FeaturedSpot spot;
  final int rank;
  final String municipality;
  final String existingNumber;
  final double rating;
  final bool grid;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  String get _rankLabel => rank.toString().padLeft(2, '0');

  Widget _thumb({double? width, double? height, bool expand = false}) {
    final image = buildFeaturedSpotListAvatar(
      spot,
      fallback: ColoredBox(
        color: OptacaAdminTheme.lightOrange,
        child: const Icon(
          Icons.star_rounded,
          color: OptacaAdminTheme.primary,
          size: 28,
        ),
      ),
    );
    final stack = Stack(
      fit: expand ? StackFit.expand : StackFit.loose,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: expand
              ? image
              : SizedBox(width: width, height: height, child: image),
        ),
        Positioned(
          left: 6,
          top: 6,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: OptacaAdminTheme.primary,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              _rankLabel,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 11,
                fontWeight: FontWeight.w800,
                height: 1,
              ),
            ),
          ),
        ),
      ],
    );
    if (!expand) return stack;
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: stack,
    );
  }

  Widget _actions() {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Material(
          color: OptacaAdminTheme.lightOrange,
          borderRadius: BorderRadius.circular(12),
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: onEdit,
            child: const Padding(
              padding: EdgeInsets.all(10),
              child: Icon(
                Icons.edit_outlined,
                size: 18,
                color: OptacaAdminTheme.primary,
              ),
            ),
          ),
        ),
        const SizedBox(width: 8),
        Material(
          color: const Color(0xFFFEE2E2),
          borderRadius: BorderRadius.circular(12),
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: onDelete,
            child: const Padding(
              padding: EdgeInsets.all(10),
              child: Icon(
                Icons.delete_outline_rounded,
                size: 18,
                color: Color(0xFFDC2626),
              ),
            ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final info = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          spot.name,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            fontWeight: FontWeight.w800,
            fontSize: 15,
            color: OptacaAdminTheme.text,
            height: 1.2,
          ),
        ),
        const SizedBox(height: 6),
        Row(
          children: [
            const Icon(
              Icons.place_rounded,
              size: 14,
              color: OptacaAdminTheme.primary,
            ),
            const SizedBox(width: 4),
            Expanded(
              child: Text(
                municipality,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  color: OptacaAdminTheme.textMuted,
                ),
              ),
            ),
          ],
        ),
      ],
    );

    final metrics = Wrap(
      spacing: 14,
      runSpacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.visibility_outlined,
              size: 16,
              color: OptacaAdminTheme.primary,
            ),
            const SizedBox(width: 5),
            Text(
              existingNumber,
              style: const TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 13,
                color: OptacaAdminTheme.text,
              ),
            ),
          ],
        ),
        Container(width: 1, height: 18, color: OptacaAdminTheme.border),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.star_rounded,
              size: 16,
              color: OptacaAdminTheme.primary,
            ),
            const SizedBox(width: 4),
            Text(
              rating.toStringAsFixed(1),
              style: const TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: 13,
                color: OptacaAdminTheme.text,
              ),
            ),
          ],
        ),
      ],
    );

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: OptacaAdminTheme.border),
        boxShadow: OptacaAdminTheme.cardShadow,
      ),
      padding: const EdgeInsets.all(12),
      child: grid
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(child: _thumb(expand: true)),
                const SizedBox(height: 10),
                info,
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(child: metrics),
                    _actions(),
                  ],
                ),
              ],
            )
          : LayoutBuilder(
              builder: (context, c) {
                final compact = c.maxWidth < 720;
                if (compact) {
                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _thumb(width: 96, height: 80),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            info,
                            const SizedBox(height: 8),
                            metrics,
                            const SizedBox(height: 8),
                            Align(
                              alignment: Alignment.centerRight,
                              child: _actions(),
                            ),
                          ],
                        ),
                      ),
                    ],
                  );
                }
                return Row(
                  children: [
                    _thumb(width: 110, height: 78),
                    const SizedBox(width: 14),
                    Expanded(flex: 4, child: info),
                    Container(
                      width: 1,
                      height: 36,
                      color: OptacaAdminTheme.border,
                      margin: const EdgeInsets.symmetric(horizontal: 10),
                    ),
                    Expanded(flex: 3, child: metrics),
                    const SizedBox(width: 8),
                    _actions(),
                  ],
                );
              },
            ),
    );
  }
}

// ─── Spots list ─────────────────────────────────────────────────────────

enum _SpotSortMode {
  newestFirst,
  oldestFirst,
  highestRated,
  lowestRated,
  mostViewed,
  nameAz,
}

class _SpotsListTab extends StatefulWidget {
  final VoidCallback onChanged;

  const _SpotsListTab({required this.onChanged});

  @override
  State<_SpotsListTab> createState() => _SpotsListTabState();
}

class _SpotsListTabState extends State<_SpotsListTab> {
  static const _pageSize = 10;

  bool _loading = true;
  String? _loadError;
  final TextEditingController _search = TextEditingController();
  _SpotSortMode _sort = _SpotSortMode.newestFirst;
  bool _gridView = false;
  int _page = 0;
  int _totalRates = 0;

  @override
  void initState() {
    super.initState();
    _loading = allSpots.isEmpty;
    tourismCatalogRevision.addListener(_onCatalogRevision);
    SpotRatingsStore.instance.revision.addListener(_onRatingsRevision);
    TouristSpotUniqueViewsService.instance.revision
        .addListener(_onUniqueViewsRevision);
    _refresh(silent: allSpots.isNotEmpty);
  }

  @override
  void dispose() {
    tourismCatalogRevision.removeListener(_onCatalogRevision);
    SpotRatingsStore.instance.revision.removeListener(_onRatingsRevision);
    TouristSpotUniqueViewsService.instance.revision
        .removeListener(_onUniqueViewsRevision);
    _search.dispose();
    super.dispose();
  }

  void _onCatalogRevision() {
    if (!mounted) return;
    if (!optacaTabIsActive(context)) return;
    setState(() {});
  }

  void _onRatingsRevision() {
    if (!mounted) return;
    if (!optacaTabIsActive(context)) return;
    setState(() => _totalRates = spotRatings.length);
  }

  void _onUniqueViewsRevision() {
    if (!mounted) return;
    if (!optacaTabIsActive(context)) return;
    setState(() {});
  }

  /// Trip Planner unique authenticated views (Firestore), with legacy
  /// [TouristSpot.visitors] only as interim fallback before counters load.
  int _spotViewCount(TouristSpot spot) {
    final views = TouristSpotUniqueViewsService.instance;
    if (views.hasConfirmedCountForSpot(spot)) {
      return views.cachedCountForSpot(spot);
    }
    final cached = views.cachedCountForSpot(spot);
    if (cached > 0) return cached;
    return spot.visitors;
  }

  Future<void> _prefetchUniqueViews(Iterable<TouristSpot> spots) async {
    await TouristSpotUniqueViewsService.instance.prefetchForSpots(spots);
  }

  Future<void> _refresh({bool silent = false}) async {
    if (!silent && mounted) {
      setState(() {
        _loading = true;
        _loadError = null;
      });
    }
    try {
      await Future.wait([
        loadTouristSpotsFromFirestore().timeout(const Duration(seconds: 25)),
        SpotRatingsStore.instance.ensureLoaded(),
      ]);
      await SpotRatingsStore.instance.refreshFromFirestore();
      await _prefetchUniqueViews(allSpots);
      tourismCatalogRevision.value++;
      _totalRates = spotRatings.length;
      debugPrint('Admin Tourist Spots tab: ${allSpots.length} spots loaded');
    } catch (e, st) {
      debugPrint('Tourist spots load: $e\n$st');
      if (allSpots.isEmpty) _loadError = e.toString();
      _totalRates = spotRatings.length;
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  List<TouristSpot> _filteredSorted() {
    final q = _search.text.trim().toLowerCase();
    final list = allSpots.where((spot) {
      if (q.isEmpty) return true;
      return spot.name.toLowerCase().contains(q) ||
          spot.displayName.toLowerCase().contains(q) ||
          spot.description.toLowerCase().contains(q) ||
          spot.category.toLowerCase().contains(q) ||
          spot.type.toLowerCase().contains(q) ||
          spot.priceRange.toLowerCase().contains(q);
    }).toList();

    int cmpName(TouristSpot a, TouristSpot b) =>
        a.name.toLowerCase().compareTo(b.name.toLowerCase());

    list.sort((a, b) {
      switch (_sort) {
        case _SpotSortMode.newestFirst:
          final byTime = b.updatedAtMs.compareTo(a.updatedAtMs);
          return byTime != 0 ? byTime : cmpName(a, b);
        case _SpotSortMode.oldestFirst:
          final byTime = a.updatedAtMs.compareTo(b.updatedAtMs);
          return byTime != 0 ? byTime : cmpName(a, b);
        case _SpotSortMode.highestRated:
          final byRating = b.rating.compareTo(a.rating);
          return byRating != 0 ? byRating : cmpName(a, b);
        case _SpotSortMode.lowestRated:
          final byRating = a.rating.compareTo(b.rating);
          return byRating != 0 ? byRating : cmpName(a, b);
        case _SpotSortMode.mostViewed:
          final byViews = _spotViewCount(b).compareTo(_spotViewCount(a));
          return byViews != 0 ? byViews : cmpName(a, b);
        case _SpotSortMode.nameAz:
          return cmpName(a, b);
      }
    });
    return list;
  }

  Future<void> _openSpotFormModal({
    TouristSpot? existing,
    int? index,
  }) async {
    await showAdminSpotFormDialog(
      context,
      existing: existing,
      index: index,
    );
    await _refresh();
    widget.onChanged();
  }

  Future<void> _deleteSpot(TouristSpot spot) async {
    final messenger = ScaffoldMessenger.of(context);
    _confirmDelete(context, spot.name, () {
      () async {
        try {
          await deleteTouristSpotFromFirestore(spot);
          allSpots.removeWhere(
            (s) =>
                identical(s, spot) ||
                (s.firestoreDocId != null &&
                    s.firestoreDocId == spot.firestoreDocId) ||
                s.name == spot.name,
          );
          tourismCatalogRevision.value++;
          widget.onChanged();
          if (!mounted) return;
          await _refresh(silent: true);
          messenger.showSnackBar(
            SnackBar(
              content: Text('Deleted "${spot.name}"'),
              backgroundColor: Colors.green,
            ),
          );
        } catch (e) {
          if (!mounted) return;
          messenger.showSnackBar(
            SnackBar(
              content: Text('Delete failed: $e'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }();
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_loading && allSpots.isEmpty) {
      return const Center(
        child: CircularProgressIndicator(color: AppColors.primary),
      );
    }

    final canEdit = AuthRoles.canEditTouristSpotCatalog();
    final filtered = _filteredSorted();
    final pageCount = filtered.isEmpty
        ? 1
        : ((filtered.length + _pageSize - 1) / _pageSize).floor();
    final safePage = _page.clamp(0, pageCount - 1);
    if (safePage != _page) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() => _page = safePage);
      });
    }
    final start = safePage * _pageSize;
    final pageItems = filtered.skip(start).take(_pageSize).toList();

    final totalSpots = allSpots.length;
    final rated = allSpots.where((s) => s.rating > 0).toList();
    final avgRating = rated.isEmpty
        ? 0.0
        : rated.fold<double>(0, (acc, s) => acc + s.rating) / rated.length;
    final totalViews =
        allSpots.fold<int>(0, (acc, s) => acc + _spotViewCount(s));
    final totalRates = _totalRates > 0
        ? _totalRates
        : allSpots.fold<int>(0, (acc, s) => acc + s.ratingCount);

    // Keep counters warm for the visible page (and aliases).
    unawaited(_prefetchUniqueViews(pageItems));

    return RefreshIndicator(
      color: AppColors.primary,
      onRefresh: () => _refresh(),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          _TouristSpotsPageHeader(
            canEdit: canEdit,
            onAdd: () => _openSpotFormModal(),
          ),
          if (_loadError != null && allSpots.isEmpty) ...[
            const SizedBox(height: 10),
            Text(
              'Load failed — pull to refresh.\n$_loadError',
              style: TextStyle(color: Colors.red.shade700, fontSize: 12),
            ),
          ],
          const SizedBox(height: 14),
          _TouristSpotsStatsRow(
            totalSpots: totalSpots,
            averageRating: avgRating,
            totalRates: totalRates,
            totalViews: totalViews,
          ),
          const SizedBox(height: 14),
          _TouristSpotsToolbar(
            search: _search,
            sort: _sort,
            gridView: _gridView,
            onSearch: (_) => setState(() {
              _page = 0;
            }),
            onSort: (mode) => setState(() {
              _sort = mode;
              _page = 0;
            }),
            onGridView: (grid) => setState(() => _gridView = grid),
          ),
          const SizedBox(height: 14),
          if (filtered.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 48),
              child: OptacaEmptyState(
                icon: Icons.place_outlined,
                title: allSpots.isEmpty
                    ? 'No tourist spots'
                    : 'No matching tourist spots',
                message: allSpots.isEmpty
                    ? (canEdit
                        ? 'Tap Add Tourist Spot to create one, or pull to refresh.'
                        : 'LGUs manage destinations from their municipal dashboards.')
                    : 'Try a different search or sort.',
              ),
            )
          else ...[
            if (_gridView)
              LayoutBuilder(
                builder: (context, c) {
                  final cols = c.maxWidth >= 1100
                      ? 3
                      : c.maxWidth >= 720
                          ? 2
                          : 1;
                  return GridView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: pageItems.length,
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: cols,
                      crossAxisSpacing: 12,
                      mainAxisSpacing: 12,
                      childAspectRatio: cols == 1 ? 2.6 : 1.55,
                    ),
                    itemBuilder: (context, i) {
                      final spot = pageItems[i];
                      return _TouristSpotGridCard(
                        spot: spot,
                        viewCount: _spotViewCount(spot),
                        canEdit: canEdit,
                        onOpen: () => showAdminTouristSpotDetailsDialog(
                          context,
                          spot: spot,
                        ),
                        onRatings: () => _showSpotRatingsSheet(
                          context,
                          spot,
                          widget.onChanged,
                        ),
                        onEdit: () => _openSpotFormModal(
                          existing: spot,
                          index: allSpots.indexOf(spot),
                        ),
                        onDelete: () => _deleteSpot(spot),
                      );
                    },
                  );
                },
              )
            else
              Column(
                children: [
                  for (var i = 0; i < pageItems.length; i++) ...[
                    if (i > 0) const SizedBox(height: 10),
                    _TouristSpotListRow(
                      spot: pageItems[i],
                      viewCount: _spotViewCount(pageItems[i]),
                      canEdit: canEdit,
                      onOpen: () => showAdminTouristSpotDetailsDialog(
                        context,
                        spot: pageItems[i],
                      ),
                      onRatings: () => _showSpotRatingsSheet(
                        context,
                        pageItems[i],
                        widget.onChanged,
                      ),
                      onEdit: () => _openSpotFormModal(
                        existing: pageItems[i],
                        index: allSpots.indexOf(pageItems[i]),
                      ),
                      onDelete: () => _deleteSpot(pageItems[i]),
                    ),
                  ],
                ],
              ),
            if (pageCount > 1) ...[
              const SizedBox(height: 18),
              _TouristSpotsPagination(
                page: safePage,
                pageCount: pageCount,
                onChanged: (p) => setState(() => _page = p),
              ),
            ],
          ],
        ],
      ),
    );
  }
}

class _TouristSpotsPageHeader extends StatelessWidget {
  const _TouristSpotsPageHeader({
    required this.canEdit,
    required this.onAdd,
  });

  final bool canEdit;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF6EC),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: OptacaAdminTheme.border.withValues(alpha: 0.75),
        ),
      ),
      child: LayoutBuilder(
        builder: (context, c) {
          final stacked = c.maxWidth < 720;
          final titleBlock = Row(
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  gradient: OptacaAdminTheme.kpiGradient,
                  borderRadius: BorderRadius.circular(13),
                  boxShadow: [
                    BoxShadow(
                      color: OptacaAdminTheme.primary.withValues(alpha: 0.25),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: const Icon(
                  Icons.landscape_rounded,
                  color: Colors.white,
                  size: 24,
                ),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Tourist Spots',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w900,
                        color: OptacaAdminTheme.text,
                        letterSpacing: -0.2,
                        height: 1.15,
                      ),
                    ),
                    SizedBox(height: 4),
                    Text(
                      'Manage and maintain the list of tourist destinations in Misamis Occidental.',
                      style: TextStyle(
                        fontSize: 12.5,
                        height: 1.35,
                        color: OptacaAdminTheme.textMuted,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              const IgnorePointer(
                child: CustomPaint(
                  size: Size(68, 52),
                  painter: _TouristSpotsHeaderArtPainter(),
                ),
              ),
            ],
          );
          final addBtn = canEdit
              ? FilledButton.icon(
                  onPressed: onAdd,
                  icon: const Icon(Icons.add, size: 20),
                  label: const Text('Add Tourist Spot'),
                  style: FilledButton.styleFrom(
                    backgroundColor: OptacaAdminTheme.primary,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 14,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                )
              : null;
          if (addBtn == null) return titleBlock;
          if (stacked) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                titleBlock,
                const SizedBox(height: 12),
                Align(alignment: Alignment.centerRight, child: addBtn),
              ],
            );
          }
          return Row(
            children: [
              Expanded(child: titleBlock),
              const SizedBox(width: 12),
              addBtn,
            ],
          );
        },
      ),
    );
  }
}

class _TouristSpotsHeaderArtPainter extends CustomPainter {
  const _TouristSpotsHeaderArtPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final mountain = Path()
      ..moveTo(0, size.height)
      ..lineTo(size.width * 0.28, size.height * 0.42)
      ..lineTo(size.width * 0.48, size.height * 0.68)
      ..lineTo(size.width * 0.72, size.height * 0.28)
      ..lineTo(size.width, size.height)
      ..close();
    canvas.drawPath(
      mountain,
      Paint()..color = OptacaAdminTheme.primary.withValues(alpha: 0.18),
    );
    final palm = Paint()
      ..color = OptacaAdminTheme.primary.withValues(alpha: 0.55)
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    final trunkX = size.width * 0.86;
    canvas.drawLine(
      Offset(trunkX, size.height * 0.92),
      Offset(trunkX, size.height * 0.42),
      palm,
    );
    for (final dx in [-14.0, -6.0, 6.0, 14.0]) {
      canvas.drawLine(
        Offset(trunkX, size.height * 0.42),
        Offset(trunkX + dx, size.height * 0.22),
        palm,
      );
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _TouristSpotsCardWavePainter extends CustomPainter {
  const _TouristSpotsCardWavePainter();

  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()
      ..moveTo(size.width * 0.45, size.height)
      ..quadraticBezierTo(
        size.width * 0.65,
        size.height * 0.25,
        size.width,
        size.height * 0.5,
      )
      ..lineTo(size.width, size.height)
      ..close();
    canvas.drawPath(
      path,
      Paint()..color = OptacaAdminTheme.primary.withValues(alpha: 0.10),
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _TouristSpotsStatsRow extends StatelessWidget {
  const _TouristSpotsStatsRow({
    required this.totalSpots,
    required this.averageRating,
    required this.totalRates,
    required this.totalViews,
  });

  final int totalSpots;
  final double averageRating;
  final int totalRates;
  final int totalViews;

  @override
  Widget build(BuildContext context) {
    final cards = [
      _TouristSpotStatCard(
        icon: Icons.place_outlined,
        label: 'Total Tourist Spots',
        value: OptacaAdminTheme.formatCount(totalSpots),
      ),
      _TouristSpotStatCard(
        icon: Icons.star_rounded,
        label: 'Average Rating',
        value: averageRating.toStringAsFixed(1),
      ),
      _TouristSpotStatCard(
        icon: Icons.groups_outlined,
        label: 'Total Rates',
        value: OptacaAdminTheme.formatCount(totalRates),
      ),
      _TouristSpotStatCard(
        icon: Icons.visibility_outlined,
        label: 'Total Views',
        value: OptacaAdminTheme.formatCount(totalViews),
      ),
    ];
    return LayoutBuilder(
      builder: (context, c) {
        final cols = c.maxWidth >= 1000 ? 4 : (c.maxWidth >= 640 ? 2 : 1);
        if (cols == 1) {
          return Column(
            children: [
              for (var i = 0; i < cards.length; i++) ...[
                if (i > 0) const SizedBox(height: 12),
                cards[i],
              ],
            ],
          );
        }
        return Column(
          children: [
            for (var i = 0; i < cards.length; i += cols) ...[
              if (i > 0) const SizedBox(height: 12),
              Row(
                children: [
                  for (var j = 0; j < cols; j++) ...[
                    if (j > 0) const SizedBox(width: 12),
                    Expanded(
                      child: i + j < cards.length
                          ? cards[i + j]
                          : const SizedBox.shrink(),
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
}

class _TouristSpotStatCard extends StatelessWidget {
  const _TouristSpotStatCard({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: OptacaAdminTheme.border),
        boxShadow: OptacaAdminTheme.cardShadow,
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Stack(
          children: [
            const Positioned(
              right: 0,
              bottom: 0,
              width: 90,
              height: 54,
              child: CustomPaint(painter: _TouristSpotsCardWavePainter()),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: OptacaAdminTheme.lightOrange,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(icon, color: OptacaAdminTheme.primary),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          value,
                          style: const TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.w900,
                            color: OptacaAdminTheme.text,
                            height: 1.05,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          label,
                          style: const TextStyle(
                            color: AppColors.textGrey,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
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
}

class _TouristSpotsToolbar extends StatelessWidget {
  const _TouristSpotsToolbar({
    required this.search,
    required this.sort,
    required this.gridView,
    required this.onSearch,
    required this.onSort,
    required this.onGridView,
  });

  final TextEditingController search;
  final _SpotSortMode sort;
  final bool gridView;
  final ValueChanged<String> onSearch;
  final ValueChanged<_SpotSortMode> onSort;
  final ValueChanged<bool> onGridView;

  String _sortLabel(_SpotSortMode mode) => switch (mode) {
        _SpotSortMode.newestFirst => 'Newest First',
        _SpotSortMode.oldestFirst => 'Oldest First',
        _SpotSortMode.highestRated => 'Highest Rated',
        _SpotSortMode.lowestRated => 'Lowest Rated',
        _SpotSortMode.mostViewed => 'Most Viewed',
        _SpotSortMode.nameAz => 'Name A–Z',
      };

  @override
  Widget build(BuildContext context) {
    final searchField = Material(
      elevation: 0,
      borderRadius: BorderRadius.circular(24),
      child: TextField(
        controller: search,
        onChanged: onSearch,
        decoration: InputDecoration(
          hintText: 'Search tourist spot by name or keyword...',
          hintStyle: const TextStyle(
            color: OptacaAdminTheme.textMuted,
            fontSize: 13.5,
            fontWeight: FontWeight.w500,
          ),
          prefixIcon: const Icon(
            Icons.search_rounded,
            color: OptacaAdminTheme.primary,
          ),
          filled: true,
          fillColor: Colors.white,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 14,
          ),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(24),
            borderSide: const BorderSide(color: OptacaAdminTheme.border),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(24),
            borderSide: const BorderSide(color: OptacaAdminTheme.border),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(24),
            borderSide: const BorderSide(
              color: OptacaAdminTheme.primary,
              width: 1.4,
            ),
          ),
        ),
      ),
    );

    final sortMenu = PopupMenuButton<_SpotSortMode>(
      initialValue: sort,
      tooltip: 'Sort',
      onSelected: onSort,
      itemBuilder: (context) => [
        for (final mode in _SpotSortMode.values)
          PopupMenuItem(value: mode, child: Text(_sortLabel(mode))),
      ],
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: OptacaAdminTheme.border),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.swap_vert_rounded,
              size: 18,
              color: OptacaAdminTheme.primary,
            ),
            const SizedBox(width: 8),
            Text(
              _sortLabel(sort),
              style: const TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 13,
              ),
            ),
            const SizedBox(width: 4),
            const Icon(Icons.keyboard_arrow_down_rounded, size: 18),
          ],
        ),
      ),
    );

    final toggle = Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: OptacaAdminTheme.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _viewChip(
            selected: gridView,
            icon: Icons.grid_view_rounded,
            onTap: () => onGridView(true),
          ),
          _viewChip(
            selected: !gridView,
            icon: Icons.view_agenda_rounded,
            onTap: () => onGridView(false),
          ),
        ],
      ),
    );

    return LayoutBuilder(
      builder: (context, c) {
        if (c.maxWidth < 820) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              searchField,
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(child: sortMenu),
                  const SizedBox(width: 10),
                  toggle,
                ],
              ),
            ],
          );
        }
        return Row(
          children: [
            Expanded(child: searchField),
            const SizedBox(width: 10),
            sortMenu,
            const SizedBox(width: 10),
            toggle,
          ],
        );
      },
    );
  }

  Widget _viewChip({
    required bool selected,
    required IconData icon,
    required VoidCallback onTap,
  }) {
    return Material(
      color: selected ? OptacaAdminTheme.primary : Colors.transparent,
      borderRadius: BorderRadius.circular(9),
      child: InkWell(
        borderRadius: BorderRadius.circular(9),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          child: Icon(
            icon,
            size: 18,
            color: selected ? Colors.white : OptacaAdminTheme.textMuted,
          ),
        ),
      ),
    );
  }
}

class _TouristSpotListRow extends StatelessWidget {
  const _TouristSpotListRow({
    required this.spot,
    required this.viewCount,
    required this.canEdit,
    required this.onOpen,
    required this.onRatings,
    required this.onEdit,
    required this.onDelete,
  });

  final TouristSpot spot;
  final int viewCount;
  final bool canEdit;
  final VoidCallback onOpen;
  final VoidCallback onRatings;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final year = spot.updatedAtMs > 0
        ? DateTime.fromMillisecondsSinceEpoch(spot.updatedAtMs).year.toString()
        : null;

    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onOpen,
        hoverColor: OptacaAdminTheme.primary.withValues(alpha: 0.04),
        child: Ink(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: OptacaAdminTheme.border),
            boxShadow: OptacaAdminTheme.cardShadow,
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
            child: LayoutBuilder(
              builder: (context, c) {
                final compact = c.maxWidth < 760;
                final meta = Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    _SpotMetaChip(
                      icon: Icons.star_rounded,
                      label: spot.rating.toStringAsFixed(1),
                      emphasize: true,
                    ),
                    _SpotMetaChip(
                      icon: Icons.visibility_outlined,
                      label:
                          '${OptacaAdminTheme.formatCount(viewCount)} views',
                    ),
                    if (year != null)
                      _SpotMetaChip(
                        icon: Icons.calendar_today_outlined,
                        label: year,
                      ),
                  ],
                );
                final actions = Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _SpotActionButton(
                      icon: Icons.people_outline_rounded,
                      tooltip: 'Who rated',
                      onPressed: onRatings,
                    ),
                    if (canEdit) ...[
                      _SpotActionButton(
                        icon: Icons.edit_outlined,
                        tooltip: 'Edit',
                        onPressed: onEdit,
                      ),
                      _SpotActionButton(
                        icon: Icons.delete_outline_rounded,
                        tooltip: 'Delete',
                        color: const Color(0xFFDC2626),
                        onPressed: onDelete,
                      ),
                    ],
                  ],
                );
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: SizedBox(
                        width: 56,
                        height: 56,
                        child: buildTouristSpotProfileImage(
                          spot,
                          fallback: ColoredBox(
                            color: OptacaAdminTheme.lightOrange,
                            child: Icon(
                              spot.isHotel ? Icons.hotel : Icons.place,
                              color: OptacaAdminTheme.primary,
                            ),
                          ),
                          memCacheWidth: 112,
                          memCacheHeight: 112,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: compact
                          ? Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  spot.name,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w800,
                                    fontSize: 14.5,
                                    color: OptacaAdminTheme.text,
                                    height: 1.2,
                                  ),
                                ),
                                const SizedBox(height: 6),
                                meta,
                              ],
                            )
                          : Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    spot.name,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w800,
                                      fontSize: 14.5,
                                      color: OptacaAdminTheme.text,
                                      height: 1.2,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                meta,
                              ],
                            ),
                    ),
                    const SizedBox(width: 6),
                    actions,
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

class _TouristSpotGridCard extends StatelessWidget {
  const _TouristSpotGridCard({
    required this.spot,
    required this.viewCount,
    required this.canEdit,
    required this.onOpen,
    required this.onRatings,
    required this.onEdit,
    required this.onDelete,
  });

  final TouristSpot spot;
  final int viewCount;
  final bool canEdit;
  final VoidCallback onOpen;
  final VoidCallback onRatings;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onOpen,
        child: Ink(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: OptacaAdminTheme.border),
            boxShadow: OptacaAdminTheme.cardShadow,
          ),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: buildTouristSpotProfileImage(
                      spot,
                      fallback: ColoredBox(
                        color: OptacaAdminTheme.lightOrange,
                        child: Icon(
                          spot.isHotel ? Icons.hotel : Icons.place,
                          color: OptacaAdminTheme.primary,
                          size: 36,
                        ),
                      ),
                      memCacheWidth: 480,
                      memCacheHeight: 320,
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  spot.name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    _SpotMetaChip(
                      icon: Icons.star_rounded,
                      label: spot.rating.toStringAsFixed(1),
                      emphasize: true,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _SpotMetaChip(
                        icon: Icons.visibility_outlined,
                        label:
                            '${OptacaAdminTheme.formatCount(viewCount)} views',
                      ),
                    ),
                    _SpotActionButton(
                      icon: Icons.people_outline_rounded,
                      tooltip: 'Who rated',
                      onPressed: onRatings,
                    ),
                    if (canEdit) ...[
                      _SpotActionButton(
                        icon: Icons.edit_outlined,
                        tooltip: 'Edit',
                        onPressed: onEdit,
                      ),
                      _SpotActionButton(
                        icon: Icons.delete_outline_rounded,
                        tooltip: 'Delete',
                        color: const Color(0xFFDC2626),
                        onPressed: onDelete,
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SpotMetaChip extends StatelessWidget {
  const _SpotMetaChip({
    required this.icon,
    required this.label,
    this.emphasize = false,
  });

  final IconData icon;
  final String label;
  final bool emphasize;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: emphasize
            ? OptacaAdminTheme.lightOrange
            : Colors.transparent,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 15, color: OptacaAdminTheme.primary),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              label,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
                color: emphasize
                    ? OptacaAdminTheme.primary
                    : OptacaAdminTheme.text,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SpotActionButton extends StatelessWidget {
  const _SpotActionButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.color,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final tint = color ?? OptacaAdminTheme.textMuted;
    return Padding(
      padding: const EdgeInsets.only(left: 4),
      child: Tooltip(
        message: tooltip,
        child: Material(
          color: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
            side: BorderSide(color: tint.withValues(alpha: 0.35)),
          ),
          child: InkWell(
            borderRadius: BorderRadius.circular(10),
            onTap: onPressed,
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: Icon(icon, size: 18, color: tint),
            ),
          ),
        ),
      ),
    );
  }
}

class _TouristSpotsPagination extends StatelessWidget {
  const _TouristSpotsPagination({
    required this.page,
    required this.pageCount,
    required this.onChanged,
  });

  final int page;
  final int pageCount;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final pages = <int>[];
    if (pageCount <= 7) {
      pages.addAll(List.generate(pageCount, (i) => i));
    } else {
      pages.add(0);
      final start = (page - 1).clamp(1, pageCount - 4);
      final end = (page + 1).clamp(3, pageCount - 2);
      if (start > 1) pages.add(-1);
      for (var i = start; i <= end; i++) {
        pages.add(i);
      }
      if (end < pageCount - 2) pages.add(-1);
      pages.add(pageCount - 1);
    }

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        IconButton(
          tooltip: 'Previous page',
          onPressed: page > 0 ? () => onChanged(page - 1) : null,
          icon: const Icon(Icons.chevron_left_rounded),
        ),
        for (final p in pages)
          if (p < 0)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 4),
              child: Text('…', style: TextStyle(fontWeight: FontWeight.w700)),
            )
          else
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 3),
              child: Material(
                color: p == page
                    ? OptacaAdminTheme.primary
                    : Colors.white,
                borderRadius: BorderRadius.circular(10),
                child: InkWell(
                  borderRadius: BorderRadius.circular(10),
                  onTap: () => onChanged(p),
                  child: Container(
                    width: 36,
                    height: 36,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: p == page
                            ? OptacaAdminTheme.primary
                            : OptacaAdminTheme.border,
                      ),
                    ),
                    child: Text(
                      '${p + 1}',
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        color: p == page
                            ? Colors.white
                            : OptacaAdminTheme.text,
                      ),
                    ),
                  ),
                ),
              ),
            ),
        IconButton(
          tooltip: 'Next page',
          onPressed:
              page < pageCount - 1 ? () => onChanged(page + 1) : null,
          icon: const Icon(Icons.chevron_right_rounded),
        ),
      ],
    );
  }
}

// ─── Municipalities list (grid cards, matches Governor portal reference) ─

class _MunicipalitiesListTab extends StatefulWidget {
  final VoidCallback onChanged;

  const _MunicipalitiesListTab({required this.onChanged});

  @override
  State<_MunicipalitiesListTab> createState() => _MunicipalitiesListTabState();
}

class _MunicipalitiesListTabState extends State<_MunicipalitiesListTab> {
  final TextEditingController _search = TextEditingController();
  String? _compareLeft;
  String? _compareRight;
  bool _gridView = true;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  static String _touristCountLine(int n) {
    if (n == 1) return '1 arrival';
    return '$n arrivals';
  }

  void _openPerformance(Municipality municipality) {
    Navigator.push<void>(
      context,
      MaterialPageRoute<void>(
        builder: (_) => MunicipalityPerformancePage(
          municipality: municipality,
          onChanged: widget.onChanged,
          onManageSpots: () {
            Navigator.push<void>(
              context,
              MaterialPageRoute<void>(
                builder: (_) => _AdminMunicipalitySpotsScreen(
                  municipality: municipality,
                  onChanged: widget.onChanged,
                ),
              ),
            );
          },
          onEditSpot: (spot) async {
            final index = allSpots.indexOf(spot);
            await showAdminSpotFormDialog(
              context,
              existing: spot,
              index: index >= 0 ? index : null,
            );
            widget.onChanged();
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AdminLiveDataBuilder(
      builder: (context, live) {
        if (live.checkInsError != null &&
            live.checkInsReady &&
            live.checkIns.isEmpty) {
          return OptacaLoadError(
            title: 'Arrivals could not be loaded',
            message: '${live.checkInsError}',
            onRetry: live.retry,
          );
        }
        final arrivals = live.checkInsReady
            ? recordedArrivalsFromRecords(live.checkInRecords)
            : const <RecordedArrival>[];
        final counts = live.checkInsReady
            ? arrivalCountsByMunicipality(arrivals)
            : const <String, int>{};
        final query = _search.text.trim().toLowerCase();
        final visible = municipalities.where((municipality) {
          if (query.isEmpty) return true;
          return municipality.name.toLowerCase().contains(query) ||
              municipality.shortName.toLowerCase().contains(query);
        }).toList()
          ..sort((a, b) => a.name.compareTo(b.name));
        final ranks = rankMunicipalities(counts);
        final names = municipalities.map((municipality) => municipality.name).toList()..sort();
        List<RecordedArrival> forName(String? name) => [
              for (final arrival in arrivals)
                if (arrival.municipalityName == name) arrival,
            ];

        return ColoredBox(
          color: OptacaAdminTheme.background,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Column(
                  children: [
                    LayoutBuilder(
                      builder: (context, constraints) {
                        final button = DecoratedBox(
                          decoration: BoxDecoration(
                            gradient: OptacaAdminTheme.kpiGradient,
                            borderRadius: BorderRadius.circular(14),
                            boxShadow: [
                              BoxShadow(
                                color: OptacaAdminTheme.primary
                                    .withValues(alpha: 0.28),
                                blurRadius: 12,
                                offset: const Offset(0, 5),
                              ),
                            ],
                          ),
                          child: Material(
                            color: Colors.transparent,
                            child: InkWell(
                              borderRadius: BorderRadius.circular(14),
                              onTap: !live.checkInsReady ||
                                      live.checkInsError != null
                                  ? null
                                  : () {
                                      showDialog<void>(
                                        context: context,
                                        builder: (dialogContext) => Dialog(
                                          child: ConstrainedBox(
                                            constraints: const BoxConstraints(
                                              maxWidth: 520,
                                              maxHeight: 640,
                                            ),
                                            child: SingleChildScrollView(
                                              padding: const EdgeInsets.all(8),
                                              child: MunicipalityRankingList(
                                                ranks: ranks,
                                                onOpen: (municipality) {
                                                  Navigator.pop(dialogContext);
                                                  _openPerformance(municipality);
                                                },
                                              ),
                                            ),
                                          ),
                                        ),
                                      );
                                    },
                              child: const Padding(
                                padding: EdgeInsets.symmetric(
                                  horizontal: 16,
                                  vertical: 14,
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      Icons.leaderboard_rounded,
                                      size: 18,
                                      color: Colors.white,
                                    ),
                                    SizedBox(width: 8),
                                    Text(
                                      'Arrival Ranking',
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        );
                        final search = Material(
                          elevation: 1.5,
                          shadowColor: Colors.black12,
                          borderRadius: BorderRadius.circular(14),
                          child: TextField(
                            controller: _search,
                            onChanged: (_) => setState(() {}),
                            decoration: OptacaPortalUi.searchDecoration(
                              hint: 'Search municipalities...',
                              prefixIcon: const Icon(
                                Icons.search_rounded,
                                size: 22,
                                color: OptacaAdminTheme.primary,
                              ),
                            ).copyWith(
                              filled: true,
                              fillColor: Colors.white,
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 14,
                                vertical: 14,
                              ),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(14),
                                borderSide: const BorderSide(
                                  color: OptacaAdminTheme.border,
                                ),
                              ),
                              enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(14),
                                borderSide: const BorderSide(
                                  color: OptacaAdminTheme.border,
                                ),
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(14),
                                borderSide: const BorderSide(
                                  color: OptacaAdminTheme.primary,
                                  width: 1.4,
                                ),
                              ),
                            ),
                          ),
                        );
                        if (constraints.maxWidth < 560) {
                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              search,
                              const SizedBox(height: 10),
                              button,
                            ],
                          );
                        }
                        return Row(
                          children: [
                            Expanded(child: search),
                            const SizedBox(width: 10),
                            button,
                          ],
                        );
                      },
                    ),
                    if (live.checkInsError != null)
                      const Padding(
                        padding: EdgeInsets.only(top: 8),
                        child: Text(
                          'Recorded arrivals could not be loaded. Counts are not shown.',
                          style: TextStyle(color: AppColors.textGrey),
                        ),
                      )
                    else if (!live.checkInsReady)
                      const Padding(
                        padding: EdgeInsets.only(top: 8),
                        child: LinearProgressIndicator(minHeight: 2),
                      ),
                    const SizedBox(height: 12),
                    Expanded(
                      child: ListView(
                        padding: const EdgeInsets.only(bottom: 88),
                        children: [
                          MunicipalityComparisonPanel(
                            left: _compareLeft,
                            right: _compareRight,
                            choices: names,
                            leftArrivals: counts[_compareLeft] ?? 0,
                            rightArrivals: counts[_compareRight] ?? 0,
                            leftMonthly:
                                monthlyArrivalCounts(forName(_compareLeft)),
                            rightMonthly:
                                monthlyArrivalCounts(forName(_compareRight)),
                            leftGrowth: _compareLeft == null
                                ? null
                                : recordedArrivalGrowthLabel(
                                    forName(_compareLeft),
                                    null,
                                  ),
                            rightGrowth: _compareRight == null
                                ? null
                                : recordedArrivalGrowthLabel(
                                    forName(_compareRight),
                                    null,
                                  ),
                            onLeft: (value) =>
                                setState(() => _compareLeft = value),
                            onRight: (value) =>
                                setState(() => _compareRight = value),
                          ),
                          const SizedBox(height: 16),
                          Container(
                            padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(18),
                              border: Border.all(color: OptacaAdminTheme.border),
                              boxShadow: OptacaAdminTheme.cardShadow,
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Row(
                                  children: [
                                    Container(
                                      width: 32,
                                      height: 32,
                                      decoration: BoxDecoration(
                                        color: OptacaAdminTheme.lightOrange,
                                        borderRadius: BorderRadius.circular(10),
                                      ),
                                      child: const Icon(
                                        Icons.apartment_rounded,
                                        color: OptacaAdminTheme.primary,
                                        size: 18,
                                      ),
                                    ),
                                    const SizedBox(width: 10),
                                    const Expanded(
                                      child: Text(
                                        'Municipality List',
                                        style: TextStyle(
                                          fontSize: 16,
                                          fontWeight: FontWeight.w800,
                                          color: OptacaAdminTheme.text,
                                        ),
                                      ),
                                    ),
                                    _ViewModeToggle(
                                      gridView: _gridView,
                                      onChanged: (grid) =>
                                          setState(() => _gridView = grid),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 14),
                                if (visible.isEmpty)
                                  const Padding(
                                    padding: EdgeInsets.all(20),
                                    child: Text(
                                      'No municipalities match these filters.',
                                      textAlign: TextAlign.center,
                                      style: TextStyle(color: AppColors.textGrey),
                                    ),
                                  )
                                else if (_gridView)
                                  LayoutBuilder(
                                    builder: (context, constraints) {
                                      final cols = constraints.maxWidth >= 900
                                          ? 3
                                          : constraints.maxWidth >= 580
                                              ? 2
                                              : 1;
                                      return GridView.builder(
                                        shrinkWrap: true,
                                        physics:
                                            const NeverScrollableScrollPhysics(),
                                        gridDelegate:
                                            SliverGridDelegateWithFixedCrossAxisCount(
                                          crossAxisCount: cols,
                                          mainAxisSpacing: 12,
                                          crossAxisSpacing: 12,
                                          mainAxisExtent: 96,
                                        ),
                                        itemCount: visible.length,
                                        itemBuilder: (context, index) {
                                          final municipality = visible[index];
                                          final realIndex = municipalities
                                              .indexOf(municipality);
                                          final count =
                                              counts[municipality.name];
                                          return _AdminMunicipalityGridCard(
                                            municipality: municipality,
                                            realIndex: realIndex,
                                            touristLabel: !live.checkInsReady ||
                                                    live.checkInsError != null
                                                ? '— arrivals'
                                                : _touristCountLine(count ?? 0),
                                            onChanged: widget.onChanged,
                                            onOpen: () =>
                                                _openPerformance(municipality),
                                            listMode: false,
                                          );
                                        },
                                      );
                                    },
                                  )
                                else
                                  Column(
                                    children: [
                                      for (final municipality in visible) ...[
                                        _AdminMunicipalityGridCard(
                                          municipality: municipality,
                                          realIndex: municipalities
                                              .indexOf(municipality),
                                          touristLabel: !live.checkInsReady ||
                                                  live.checkInsError != null
                                              ? '— arrivals'
                                              : _touristCountLine(
                                                  counts[municipality.name] ??
                                                      0,
                                                ),
                                          onChanged: widget.onChanged,
                                          onOpen: () =>
                                              _openPerformance(municipality),
                                          listMode: true,
                                        ),
                                        const SizedBox(height: 10),
                                      ],
                                    ],
                                  ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                if (municipalities.isEmpty)
                  const Center(
                    child: Text(
                      'No municipalities.\nTap + to add.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: AppColors.textGrey, fontSize: 15),
                    ),
                  ),
                Positioned(
                  right: 12,
                  bottom: 12,
                  child: FloatingActionButton(
                    heroTag: 'municipalityPerfFab',
                    backgroundColor: OptacaAdminTheme.primary,
                    elevation: 6,
                    hoverElevation: 10,
                    onPressed: () async {
                      await Navigator.push<void>(
                        context,
                        MaterialPageRoute<void>(
                          builder: (_) => const AdminMunicipalityFormPage(),
                        ),
                      );
                      widget.onChanged();
                    },
                    child: const Icon(Icons.add, color: Colors.white, size: 28),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// Tourist spots for this municipality ([touristSpotBelongsToMunicipality]).
class _AdminMunicipalitySpotsScreen extends StatefulWidget {
  final Municipality municipality;
  final VoidCallback onChanged;
  final int checkInVisitCount;

  const _AdminMunicipalitySpotsScreen({
    required this.municipality,
    required this.onChanged,
    this.checkInVisitCount = 0,
  });

  @override
  State<_AdminMunicipalitySpotsScreen> createState() =>
      _AdminMunicipalitySpotsScreenState();
}

class _AdminMunicipalitySpotsScreenState extends State<_AdminMunicipalitySpotsScreen> {
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    if (allSpots.isEmpty) {
      _loading = true;
      _ensureSpotsLoaded();
    }
  }

  Future<void> _ensureSpotsLoaded() async {
    try {
      await loadTouristSpotsFromFirestore().timeout(const Duration(seconds: 25));
      tourismCatalogRevision.value++;
    } catch (e) {
      debugPrint('Municipality spots load: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  List<TouristSpot> _spotsInMunicipality() {
    final list = allSpots
        .where(
          (s) => touristSpotBelongsToMunicipality(s, widget.municipality),
        )
        .toList();
    list.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return list;
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Scaffold(
        backgroundColor: OptacaAdminTheme.background,
        appBar: AppBar(
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.white,
          title: Text(widget.municipality.name),
        ),
        body: const Center(
          child: CircularProgressIndicator(color: AppColors.primary),
        ),
      );
    }
    final spots = _spotsInMunicipality();

    return Scaffold(
      backgroundColor: OptacaAdminTheme.background,
      appBar: AppBar(
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              widget.municipality.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            Text(
              widget.checkInVisitCount > 0
                  ? '${widget.checkInVisitCount} QR visit${widget.checkInVisitCount == 1 ? '' : 's'} · '
                      '${spots.length} spot${spots.length == 1 ? '' : 's'}'
                  : '${spots.length} tourist spot${spots.length == 1 ? '' : 's'}',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.9),
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Visits per spot (chart)',
            icon: const Icon(Icons.insights_outlined),
            onPressed: () {
              Navigator.of(context).push<void>(
                MaterialPageRoute<void>(
                  builder: (ctx) => _MunicipalityAnalyticsDetail(
                    municipalityName: widget.municipality.name,
                  ),
                ),
              );
            },
          ),
        ],
      ),
      body: Stack(
        children: [
          ListView.builder(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 88),
            itemCount: spots.length,
            itemBuilder: (context, index) {
              final spot = spots[index];
              return Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Material(
                  color: const Color(0xFFFFF4EB),
                  borderRadius: BorderRadius.circular(22),
                  clipBehavior: Clip.antiAlias,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(12, 10, 4, 10),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        SizedBox(
                          width: 52,
                          height: 52,
                          child: ClipOval(
                            child: buildTouristSpotProfileImage(
                              spot,
                              fallback: Container(
                                color: AppColors.primary.withValues(alpha: 0.18),
                                alignment: Alignment.center,
                                child: Icon(
                                  spot.isHotel ? Icons.hotel : Icons.place,
                                  color: AppColors.primary,
                                  size: 26,
                                ),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                spot.name,
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 15,
                                  color: AppColors.textDark,
                                  height: 1.2,
                                ),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                              const SizedBox(height: 4),
                              Text(
                                '${spot.priceRange} · ${spot.rating.toStringAsFixed(1)}★ · ${spot.type}',
                                style: const TextStyle(
                                  fontSize: 13,
                                  color: AppColors.textGrey,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.people_outline, size: 22),
                          tooltip: 'Who rated',
                          onPressed: () => _showSpotRatingsSheet(
                            context,
                            spot,
                            () {
                              widget.onChanged();
                              setState(() {});
                            },
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.edit_outlined, size: 22),
                          tooltip: 'Edit',
                          onPressed: () async {
                            final listIndex = allSpots.indexOf(spot);
                            await showAdminSpotFormDialog(
                              context,
                              existing: spot,
                              index: listIndex >= 0 ? listIndex : null,
                            );
                            if (context.mounted) setState(() {});
                            widget.onChanged();
                          },
                        ),
                        IconButton(
                          icon: Icon(
                            Icons.delete_outline,
                            size: 22,
                            color: Colors.red.shade400,
                          ),
                          tooltip: 'Delete',
                          onPressed: () {
                            _confirmDelete(context, spot.name, () {
                              final id = spot.firestoreDocId?.trim();
                              final i = id != null && id.isNotEmpty
                                  ? allSpots.indexWhere(
                                      (s) => s.firestoreDocId?.trim() == id,
                                    )
                                  : allSpots.indexWhere(
                                      (s) =>
                                          s.name == spot.name &&
                                          touristSpotBelongsToMunicipality(
                                            s,
                                            widget.municipality,
                                          ),
                                    );
                              if (i >= 0) allSpots.removeAt(i);
                              setState(() {});
                              widget.onChanged();
                            });
                          },
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
          if (spots.isEmpty)
            Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  'No tourist spots linked to this ${widget.municipality.divisionLabel.toLowerCase()} yet.\n'
                  'Set each spot’s Location to this place’s full name or short name (or use municipality / municipalityName in Firebase). Tap + to add one.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.grey.shade700,
                    fontSize: 15,
                    height: 1.35,
                  ),
                ),
              ),
            ),
          Positioned(
            right: 16,
            bottom: 16,
            child: FloatingActionButton(
              heroTag: 'muniSpotsFab_${widget.municipality.name}',
              backgroundColor: AppColors.primary,
              onPressed: () async {
                await showAdminSpotFormDialog(
                  context,
                  initialLocation: widget.municipality.name,
                );
                if (context.mounted) setState(() {});
                widget.onChanged();
              },
              child: const Icon(Icons.add, color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }
}

class _ViewModeToggle extends StatelessWidget {
  const _ViewModeToggle({
    required this.gridView,
    required this.onChanged,
  });

  final bool gridView;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: OptacaAdminTheme.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _chip(
            selected: gridView,
            icon: Icons.grid_view_rounded,
            label: 'Grid',
            onTap: () => onChanged(true),
          ),
          _chip(
            selected: !gridView,
            icon: Icons.view_agenda_rounded,
            label: 'List',
            onTap: () => onChanged(false),
          ),
        ],
      ),
    );
  }

  Widget _chip({
    required bool selected,
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return Material(
      color: selected ? OptacaAdminTheme.lightOrange : Colors.transparent,
      borderRadius: BorderRadius.circular(9),
      child: InkWell(
        borderRadius: BorderRadius.circular(9),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
          child: Row(
            children: [
              Icon(
                icon,
                size: 16,
                color: selected
                    ? OptacaAdminTheme.primary
                    : OptacaAdminTheme.textMuted,
              ),
              const SizedBox(width: 5),
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: selected
                      ? OptacaAdminTheme.primary
                      : OptacaAdminTheme.textMuted,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MunicipalityWavePainter extends CustomPainter {
  const _MunicipalityWavePainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()
      ..moveTo(size.width * 0.35, size.height)
      ..quadraticBezierTo(
        size.width * 0.55,
        size.height * 0.35,
        size.width,
        size.height * 0.55,
      )
      ..lineTo(size.width, size.height)
      ..close();
    canvas.drawPath(path, Paint()..color = color.withValues(alpha: 0.14));
  }

  @override
  bool shouldRepaint(covariant _MunicipalityWavePainter oldDelegate) =>
      oldDelegate.color != color;
}

class _AdminMunicipalityGridCard extends StatelessWidget {
  final Municipality municipality;
  final int realIndex;
  final String touristLabel;
  final VoidCallback onChanged;
  final VoidCallback onOpen;
  final bool listMode;

  const _AdminMunicipalityGridCard({
    required this.municipality,
    required this.realIndex,
    required this.touristLabel,
    required this.onChanged,
    required this.onOpen,
    this.listMode = false,
  });

  Future<void> _openEdit(BuildContext context) async {
    await Navigator.push<void>(
      context,
      MaterialPageRoute<void>(
        builder: (_) => AdminMunicipalityFormPage(
          existing: municipality,
          index: realIndex,
        ),
      ),
    );
    onChanged();
  }

  @override
  Widget build(BuildContext context) {
    final isCity = municipality.divisionLabel == 'City';
    final imageSize = listMode ? 54.0 : 48.0;

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: OptacaAdminTheme.border.withValues(alpha: 0.95),
          ),
          boxShadow: [
            BoxShadow(
              color: OptacaAdminTheme.primary.withValues(alpha: 0.08),
              blurRadius: 14,
              offset: const Offset(0, 5),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: Stack(
            children: [
              Positioned.fill(
                child: CustomPaint(
                  painter: const _MunicipalityWavePainter(
                    OptacaAdminTheme.primary,
                  ),
                ),
              ),
              Material(
                color: Colors.transparent,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(
                      child: Tooltip(
                        message:
                            'Tap to view tourist spots in this ${isCity ? 'city' : 'municipality'}',
                        child: InkWell(
                          onTap: onOpen,
                          hoverColor: OptacaAdminTheme.primary
                              .withValues(alpha: 0.04),
                          child: Padding(
                            padding: EdgeInsets.fromLTRB(
                              listMode ? 14 : 12,
                              10,
                              4,
                              10,
                            ),
                            child: Row(
                              children: [
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(12),
                                  child: SizedBox(
                                    width: imageSize,
                                    height: imageSize,
                                    child: buildMunicipalityImageForMunicipality(
                                      municipality,
                                      fallback: ColoredBox(
                                        color: AppColors.primary
                                            .withValues(alpha: 0.14),
                                        child: Icon(
                                          isCity
                                              ? Icons.location_city_rounded
                                              : Icons.domain_rounded,
                                          color: AppColors.primary,
                                          size: 26,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        municipality.name,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                          fontSize: 14.5,
                                          fontWeight: FontWeight.w800,
                                          color: AppColors.textDark,
                                          height: 1.15,
                                        ),
                                      ),
                                      const SizedBox(height: 5),
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 9,
                                          vertical: 3,
                                        ),
                                        decoration: BoxDecoration(
                                          color: AppColors.primary,
                                          borderRadius:
                                              BorderRadius.circular(20),
                                        ),
                                        child: Text(
                                          municipality.divisionLabel,
                                          style: const TextStyle(
                                            fontSize: 10.5,
                                            fontWeight: FontWeight.w700,
                                            color: Colors.white,
                                            height: 1.1,
                                          ),
                                        ),
                                      ),
                                      const SizedBox(height: 5),
                                      Text(
                                        touristLabel,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: Colors.grey.shade600,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                Container(
                                  width: 34,
                                  height: 34,
                                  margin: const EdgeInsets.only(right: 6),
                                  decoration: const BoxDecoration(
                                    color: OptacaAdminTheme.lightOrange,
                                    shape: BoxShape.circle,
                                  ),
                                  child: const Icon(
                                    Icons.chevron_right_rounded,
                                    color: OptacaAdminTheme.primary,
                                    size: 22,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                    PopupMenuButton<String>(
                      tooltip: 'Actions',
                      padding: EdgeInsets.zero,
                      icon: Icon(
                        Icons.more_vert_rounded,
                        size: 20,
                        color: Colors.grey.shade600,
                      ),
                      onSelected: (value) async {
                        if (!context.mounted) return;
                        if (value == 'edit') {
                          await _openEdit(context);
                        } else if (value == 'delete') {
                          _confirmDelete(context, municipality.name, () {
                            final i = municipalities.indexWhere(
                              (x) => x.name == municipality.name,
                            );
                            if (i >= 0) {
                              municipalities.removeAt(i);
                              onChanged();
                            }
                          });
                        }
                      },
                      itemBuilder: (ctx) => [
                        const PopupMenuItem(
                          value: 'edit',
                          child: Text('Edit'),
                        ),
                        PopupMenuItem(
                          value: 'delete',
                          child: Text(
                            'Delete',
                            style: TextStyle(color: Colors.red.shade700),
                          ),
                        ),
                      ],
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
}

// ─── App user accounts (Firestore `users`) — opened from Settings ───────

class AppUsersManagementScreen extends StatefulWidget {
  const AppUsersManagementScreen({super.key});

  @override
  State<AppUsersManagementScreen> createState() =>
      _AppUsersManagementScreenState();
}

class _AppUsersManagementScreenState extends State<AppUsersManagementScreen> {
  Future<void> _reload() async {
    await loadUsersFromFirestore();
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: OptacaAdminTheme.background,
      appBar: AppBar(
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        title: const Text('App user accounts'),
      ),
      body: Stack(
        children: [
          ListView.builder(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 88),
            itemCount: users.length,
            itemBuilder: (context, index) {
              final user = users[index];
              return Card(
                margin: const EdgeInsets.only(bottom: 10),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                child: ListTile(
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  leading: buildUserListAvatar(user),
                  title: Text(
                    user.name,
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      color: AppColors.textDark,
                    ),
                  ),
                  subtitle: Text(
                    '${user.email} · ${user.role}',
                    style: const TextStyle(
                      fontSize: 13,
                      color: AppColors.textGrey,
                    ),
                  ),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.edit_outlined, size: 22),
                        onPressed: () async {
                          await Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => AdminUserFormPage(
                                existing: user,
                                index: index,
                              ),
                            ),
                          );
                          await _reload();
                        },
                      ),
                      IconButton(
                        icon: Icon(
                          Icons.delete_outline,
                          size: 22,
                          color: Colors.red.shade400,
                        ),
                        onPressed: () {
                          final messenger = ScaffoldMessenger.maybeOf(context);
                          _confirmDelete(context, user.name, () {
                            () async {
                              try {
                                await deleteAppUserFromFirestore(user.id);
                                await _reload();
                              } catch (e) {
                                messenger?.showSnackBar(
                                  SnackBar(
                                    content: Text('Delete failed: $e'),
                                    backgroundColor: Colors.redAccent,
                                  ),
                                );
                              }
                            }();
                          });
                        },
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
          if (users.isEmpty)
            const Center(
              child: Text(
                'No users found.\nTap + to add a document in the Firestore `users` collection.',
                textAlign: TextAlign.center,
                style: TextStyle(color: AppColors.textGrey, fontSize: 15),
              ),
            ),
          Positioned(
            right: 16,
            bottom: 16,
            child: FloatingActionButton(
              heroTag: 'usersFab',
              backgroundColor: AppColors.primary,
              onPressed: () async {
                await Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const AdminUserFormPage()),
                );
                await _reload();
              },
              child: const Icon(Icons.add, color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Events list ────────────────────────────────────────────────────────

class _EventsListTab extends StatefulWidget {
  final VoidCallback onChanged;

  const _EventsListTab({required this.onChanged});

  @override
  State<_EventsListTab> createState() => _EventsListTabState();
}

class _EventsListTabState extends State<_EventsListTab> {
  bool _loading = true;
  Object? _error;
  final Set<String> _selectedIds = {};
  bool _deleting = false;

  @override
  void initState() {
    super.initState();
    _loading = tourismEvents.isEmpty;
    tourismEventsRevision.addListener(_onEventsChanged);
    _load(silent: tourismEvents.isNotEmpty);
  }

  @override
  void dispose() {
    tourismEventsRevision.removeListener(_onEventsChanged);
    super.dispose();
  }

  void _onEventsChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _load({bool silent = false}) async {
    if (!silent && mounted) setState(() => _loading = true);
    try {
      await loadEventsFromFirestore().timeout(const Duration(seconds: 30));
      debugPrint('Admin Events tab: ${tourismEvents.length} events loaded');
      if (mounted) _error = null;
    } catch (e, st) {
      debugPrint('Events load: $e\n$st');
      if (mounted) _error = e;
    } finally {
      if (mounted) {
        _pruneSelection();
        setState(() => _loading = false);
      }
    }
  }

  /// All listed events are selectable — including announcement-backed mirrors
  /// (`announcement_*`), which delete from the announcements collection.
  List<TourismEvent> get _selectableEvents => List<TourismEvent>.from(tourismEvents);

  void _pruneSelection() {
    final visible = {for (final event in _selectableEvents) event.id};
    _selectedIds.removeWhere((id) => !visible.contains(id));
  }

  void _toggleSelect(TourismEvent event) {
    if (_deleting) return;
    setState(() {
      if (!_selectedIds.add(event.id)) _selectedIds.remove(event.id);
    });
  }

  void _selectAllVisible() {
    if (_deleting) return;
    setState(() {
      _selectedIds
        ..clear()
        ..addAll(_selectableEvents.map((e) => e.id));
    });
  }

  Future<void> _deleteSelected() async {
    if (_deleting || _selectedIds.isEmpty) return;
    final count = _selectedIds.length;
    final confirmed = await confirmAdminBulkDelete(
      context,
      count: count,
      nounSingular: 'event',
      nounPlural: 'events',
    );
    if (!confirmed || !mounted) return;
    final ids = Set<String>.from(_selectedIds);
    setState(() => _deleting = true);
    try {
      final result = await deleteTourismEventsByIds(ids);
      if (!mounted) return;
      setState(() {
        _selectedIds.removeAll(result.deletedIds);
        _deleting = false;
      });
      widget.onChanged();
      final deletedCount = result.deletedIds.length;
      final message = result.hasFailures
          ? '$deletedCount events deleted. ${result.failedIds.length} could not be deleted.'
          : '$deletedCount events deleted successfully.';
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
    } catch (e) {
      if (!mounted) return;
      setState(() => _deleting = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to delete events: $e'),
          backgroundColor: Colors.redAccent,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(
        child: CircularProgressIndicator(color: AppColors.primary),
      );
    }
    if (_error != null && tourismEvents.isEmpty) {
      return OptacaLoadError(
        title: 'Events could not be loaded',
        message: '$_error',
        onRetry: _load,
      );
    }
    final selectable = _selectableEvents;
    final selectedCount = _selectedIds.length;
    final allSelected =
        selectable.isNotEmpty && selectedCount == selectable.length;
    final selectAllTristate = selectedCount == 0
        ? false
        : allSelected
            ? true
            : null;
    return RefreshIndicator(
      color: AppColors.primary,
      onRefresh: _load,
      child: Stack(
        children: [
          ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 80),
            physics: const AlwaysScrollableScrollPhysics(),
            children: [
              TourismPlanCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    TourismPlanUi.sectionHeader(
                      icon: Icons.event_available_rounded,
                      title: 'Event calendar',
                      badge: '${tourismEvents.length}',
                    ),
                    const SizedBox(height: 12),
                    TourismEventsCalendar(
                      events: tourismEvents,
                      accentColor: AppColors.primary,
                      titleOnly: true,
                      initialMonth: tourismEvents.isNotEmpty
                          ? tourismEvents.first.dateTime
                          : null,
                      onEventTap: (e) => openTourismEventDetail(
                  context,
                  e,
                  accentColor: AppColors.primary,
                  onEdit: () async {
                    await openAdminEventForm(context, existing: e);
                    await _load();
                    widget.onChanged();
                  },
                  onDelete: () {
                    _confirmDelete(context, e.title, () async {
                      await deleteTourismEventFromFirestore(e.id);
                      await _load();
                      widget.onChanged();
                    });
                  },
                ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Expanded(
                    child: TourismPlanUi.sectionTitleBar(title: 'All events'),
                  ),
                  Flexible(
                    child: AdminBulkSelectionBar(
                      selectedCount: selectedCount,
                      totalVisible: selectable.length,
                      nounPlural: 'events',
                      onSelectAllVisible: _selectAllVisible,
                      onClear: () => setState(_selectedIds.clear),
                      onDelete: _deleteSelected,
                      deleting: _deleting,
                      selectAllChecked: allSelected,
                      selectAllTristate: selectAllTristate,
                      alignEnd: true,
                      compact: true,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              TourismEventTitlesList(
                events: tourismEvents,
                accentColor: AppColors.primary,
                selectedIds: _selectedIds,
                selectableIds: {for (final event in selectable) event.id},
                onToggleSelect: _toggleSelect,
                onEventTap: (e) => openTourismEventDetail(
                  context,
                  e,
                  accentColor: AppColors.primary,
                  onEdit: () async {
                    await openAdminEventForm(context, existing: e);
                    await _load();
                    widget.onChanged();
                  },
                  onDelete: () {
                    _confirmDelete(context, e.title, () async {
                      await deleteTourismEventFromFirestore(e.id);
                      await _load();
                      widget.onChanged();
                    });
                  },
                ),
              ),
            ],
          ),
          Positioned(
            right: 16,
            bottom: 16,
            child: FloatingActionButton(
              heroTag: 'eventsFab',
              backgroundColor: AppColors.primary,
              onPressed: () async {
                await openAdminEventForm(context);
                await _load();
                widget.onChanged();
              },
              child: const Icon(Icons.add, color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }
}

void _confirmDelete(BuildContext context, String name, VoidCallback onConfirm) {
  showDialog(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Delete'),
      content: Text('Remove "$name"? This action cannot be undone.'),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () {
            Navigator.pop(ctx);
            onConfirm();
          },
          style: FilledButton.styleFrom(
            backgroundColor: Colors.red.shade500,
            foregroundColor: Colors.white,
          ),
          child: const Text('Delete'),
        ),
      ],
    ),
  );
}

void _showSpotRatingsSheet(
  BuildContext context,
  TouristSpot spot,
  VoidCallback onChanged,
) {
  final ratings = spotRatings.where((r) => r.spotName == spot.name).toList();

  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (ctx) => DraggableScrollableSheet(
      initialChildSize: 0.5,
      minChildSize: 0.3,
      maxChildSize: 0.85,
      builder: (_, scrollController) => Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          children: [
            const SizedBox(height: 12),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(20),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Who rated',
                          style: TextStyle(
                            fontSize: 16,
                            color: AppColors.textGrey,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        Text(
                          spot.name,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            color: AppColors.textDark,
                          ),
                        ),
                      ],
                    ),
                  ),
                  TextButton.icon(
                    onPressed: () {
                      Navigator.pop(ctx);
                      _showAddRatingDialog(context, spot.name, onChanged);
                    },
                    icon: const Icon(Icons.add, size: 20),
                    label: const Text('Add rating'),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: ratings.isEmpty
                  ? const Center(
                      child: Padding(
                        padding: EdgeInsets.all(24),
                        child: Text(
                          'No ratings yet.\nTap "Add rating" to record who rated this spot.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: AppColors.textGrey,
                            fontSize: 14,
                          ),
                        ),
                      ),
                    )
                  : ListView.builder(
                      controller: scrollController,
                      padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
                      itemCount: ratings.length,
                      itemBuilder: (_, i) {
                        final r = ratings[i];
                        return ListTile(
                          leading: buildReviewerAvatar(
                            userId: r.userId,
                            profilePhotoPath: r.profilePhotoPath,
                            size: 42,
                          ),
                          title: Text(
                            r.userName,
                            style: const TextStyle(
                              fontWeight: FontWeight.w600,
                              color: AppColors.textDark,
                            ),
                          ),
                          subtitle: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const SizedBox(height: 2),
                              StarRating(
                                rating: r.rating,
                                size: 14,
                                color: AppColors.primary,
                              ),
                              if (r.description.trim().isNotEmpty) ...[
                                const SizedBox(height: 4),
                                Text(
                                  r.description,
                                  maxLines: 3,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    color: AppColors.textGrey,
                                    fontSize: 13,
                                  ),
                                ),
                              ],
                            ],
                          ),
                          isThreeLine: r.description.trim().isNotEmpty,
                          trailing: Text(
                            r.rating.toStringAsFixed(1),
                            style: const TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 16,
                              color: AppColors.primary,
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    ),
  );
}

void _showAddRatingDialog(
  BuildContext context,
  String spotName,
  VoidCallback onChanged,
) {
  final nameController = TextEditingController();
  final descriptionController = TextEditingController();
  double selectedRating = 5.0;

  showDialog(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setDialogState) => AlertDialog(
        title: const Text('Add rating'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Spot: $spotName',
                style: const TextStyle(color: AppColors.textGrey, fontSize: 13),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: nameController,
                decoration: const InputDecoration(
                  labelText: 'User name',
                  hintText: 'Who gave this rating?',
                ),
              ),
              const SizedBox(height: 16),
              Center(
                child: InteractiveRatingBadge(
                  rating: selectedRating,
                  onChanged: (v) => setDialogState(() => selectedRating = v),
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: descriptionController,
                maxLines: 3,
                minLines: 2,
                textCapitalization: TextCapitalization.sentences,
                decoration: InputDecoration(
                  labelText: 'Description (optional)',
                  hintText: 'Optional notes about the visit...',
                  alignLabelWithHint: true,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ],
          ),
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        actions: [
          TextButton(
            onPressed: () {
              nameController.dispose();
              descriptionController.dispose();
              Navigator.pop(ctx);
            },
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () async {
              final name = nameController.text.trim();
              if (name.isEmpty) return;
              await SpotRatingsStore.instance.add(
                SpotRating(
                  userName: name,
                  spotName: spotName,
                  rating: selectedRating,
                  description: descriptionController.text.trim(),
                ),
              );
              nameController.dispose();
              descriptionController.dispose();
              Navigator.pop(ctx);
              onChanged();
            },
            child: const Text('Add'),
          ),
        ],
      ),
    ),
  );
}

// ─── Featured form page ──────────────────────────────────────────────────

Future<void> showAdminFeaturedFormDialog(
  BuildContext context, {
  FeaturedSpot? existing,
  int? index,
}) async {
  if (!context.mounted) return;
  final size = MediaQuery.sizeOf(context);
  await showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: SizedBox(
        width: size.width < 640 ? size.width : 560,
        height: size.height * 0.9,
        child: AdminFeaturedFormPage(existing: existing, index: index),
      ),
    ),
  );
}

class AdminFeaturedFormPage extends StatefulWidget {
  final FeaturedSpot? existing;
  final int? index;

  const AdminFeaturedFormPage({super.key, this.existing, this.index});

  @override
  State<AdminFeaturedFormPage> createState() => _AdminFeaturedFormPageState();
}

class _AdminFeaturedFormPageState extends State<AdminFeaturedFormPage> {
  final _formKey = GlobalKey<FormState>();
  String? _selectedSpotName;
  bool _saving = false;
  List<TouristSpot> get _uniqueSpotOptions {
    final byName = <String, TouristSpot>{};
    for (final s in allSpots) {
      final existing = byName[s.name];
      if (existing == null) {
        byName[s.name] = s;
        continue;
      }
      final currentHasImage = s.imagePath.trim().isNotEmpty;
      final existingHasImage = existing.imagePath.trim().isNotEmpty;
      if (currentHasImage && !existingHasImage) {
        byName[s.name] = s;
      }
    }
    return byName.values.toList();
  }

  @override
  void initState() {
    super.initState();
    final existingName = widget.existing?.name;
    if (existingName != null &&
        _uniqueSpotOptions.any((s) => s.name == existingName)) {
      _selectedSpotName = existingName;
    }
  }

  Future<void> _save() async {
    if (_saving) return;
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    final selected = _uniqueSpotOptions.firstWhere(
      (s) => s.name == _selectedSpotName,
      orElse: () => _uniqueSpotOptions.first,
    );
    var imagePath = selected.imagePath.trim();
    if (imagePath.isEmpty) {
      imagePath =
          '$kTouristSpotProfileStorageRoot/${touristSpotProfileStorageSlug(selected.name)}';
    }
    final spot = FeaturedSpot(
      name: selected.name,
      priceRange: selected.priceRange,
      rating: selected.rating.clamp(0.0, 5.0),
      imagePath: imagePath,
    );
    try {
      final oldName = widget.existing?.name;
      await upsertFeaturedSpotToFirestore(spot, oldName: oldName);
      if (widget.index != null) {
        featuredSpots[widget.index!] = spot;
      } else {
        featuredSpots.add(spot);
      }
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to save featured spot to Firestore: $e'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        title: Text(
          widget.existing != null ? 'Edit featured spot' : 'Add featured spot',
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (_uniqueSpotOptions.isEmpty)
                const Text(
                  'No registered spots yet. Add spots first in the Spots tab.',
                  style: TextStyle(color: AppColors.textGrey),
                )
              else ...[
                const Text(
                  'Choose a tourist spot',
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 13.5,
                    color: AppColors.textDark,
                  ),
                ),
                const SizedBox(height: 8),
                AdminFeaturedSpotPicker(
                  spots: _uniqueSpotOptions,
                  initialValue: _selectedSpotName,
                  onChanged: (v) => setState(() => _selectedSpotName = v),
                ),
              ],
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: (_uniqueSpotOptions.isEmpty || _saving)
                    ? null
                    : _save,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                child: Text(
                  _saving ? 'Saving...' : 'Save',
                  style: const TextStyle(color: Colors.white),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Spot form page ─────────────────────────────────────────────────────

Future<void> showAdminSpotFormDialog(
  BuildContext context, {
  TouristSpot? existing,
  int? index,
  String? initialLocation,
}) async {
  if (!context.mounted) return;
  final size = MediaQuery.sizeOf(context);
  await showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: SizedBox(
        width: size.width < 640 ? size.width : 560,
        height: size.height * 0.9,
        child: AdminSpotFormPage(
          existing: existing,
          index: index,
          initialLocation: initialLocation,
        ),
      ),
    ),
  );
}

class AdminSpotFormPage extends StatefulWidget {
  final TouristSpot? existing;
  final int? index;
  /// When adding a new spot, pre-fills Location (e.g. opened from a municipality).
  final String? initialLocation;

  const AdminSpotFormPage({
    super.key,
    this.existing,
    this.index,
    this.initialLocation,
  });

  @override
  State<AdminSpotFormPage> createState() => _AdminSpotFormPageState();
}

class _AdminSpotFormPageState extends State<AdminSpotFormPage> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _nameController;
  late TextEditingController _locationController;
  late TextEditingController _descriptionController;
  late TextEditingController _walkingMinutesController;
  late TextEditingController _entranceFeeController;
  late TextEditingController _foodAndDrinksController;
  late TextEditingController _otherSouvenirsController;
  late TextEditingController _imageController;
  static const List<String> _spotTypeOptions = [
    'Nature',
    'Adventure',
    'Culture',
    'Relaxation',
    'Food',
  ];
  late String _type;
  double? _latitude;
  double? _longitude;
  bool _uploadingImage = false;
  bool _saving = false;
  String? _saveError;
  Uint8List? _previewBytes;

  @override
  void initState() {
    super.initState();
    if (!AuthRoles.canEditTouristSpotCatalog()) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'You do not have permission to edit tourist spots.',
            ),
          ),
        );
        Navigator.of(context).maybePop();
      });
    }
    _nameController = TextEditingController(text: widget.existing?.name ?? '');
    _locationController = TextEditingController(
      text: widget.existing?.location ??
          (widget.initialLocation?.trim().isNotEmpty == true
              ? widget.initialLocation!.trim()
              : ''),
    );
    _descriptionController = TextEditingController(
      text: widget.existing?.description ?? '',
    );
    _walkingMinutesController = TextEditingController(
      text: widget.existing?.walkingDistanceMinutes != null
          ? '${widget.existing!.walkingDistanceMinutes}'
          : '',
    );
    _entranceFeeController = TextEditingController(
      text: widget.existing?.entranceFee ?? '',
    );
    _foodAndDrinksController = TextEditingController(
      text: widget.existing?.foodAndDrinksPrice ?? '',
    );
    _otherSouvenirsController = TextEditingController(
      text: widget.existing?.otherSouvenirsPrice ?? '',
    );
    _imageController = TextEditingController(
      text: widget.existing?.imagePath ?? '',
    );
    _latitude = widget.existing?.latitude;
    _longitude = widget.existing?.longitude;
    final existingType = widget.existing?.type ?? 'spot';
    _type = existingType == 'spot'
        ? 'Nature'
        : existingType == 'hotel'
        ? 'Relaxation'
        : _spotTypeOptions.contains(existingType)
        ? existingType
        : 'Nature';
  }

  Future<void> _pickImage() async {
    final picker = ImagePicker();
    final xFile = await picker.pickImage(source: ImageSource.gallery);
    if (xFile == null) return;
    final bytes = await xFile.readAsBytes();
    if (!mounted) return;
    setState(() {
      _previewBytes = bytes;
      _uploadingImage = true;
    });
    try {
      final name = _nameController.text.trim();
      final spotSlug = touristSpotProfileStorageSlug(name.isEmpty ? 'spot' : name);
      final folder = '$kTouristSpotProfileStorageRoot/$spotSlug';
      final url = await uploadTourismCatalogImage(bytes, folder);
      if (mounted) {
        setState(() {
          _imageController.text = url;
          _uploadingImage = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _uploadingImage = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Upload failed: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Widget _buildSpotPickImagePlaceholder() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.add_photo_alternate,
            size: 48,
            color: AppColors.primary.withOpacity(0.6),
          ),
          const SizedBox(height: 8),
          Text(
            'Tap to pick from device',
            style: TextStyle(fontSize: 13, color: AppColors.textGrey),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _nameController.dispose();
    _locationController.dispose();
    _descriptionController.dispose();
    _walkingMinutesController.dispose();
    _entranceFeeController.dispose();
    _foodAndDrinksController.dispose();
    _otherSouvenirsController.dispose();
    _imageController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving) return;
    if (!_formKey.currentState!.validate()) {
      setState(() {
        _saveError = 'Please fill required fields (name and municipality).';
      });
      return;
    }
    if (!isValidSpotCoordinate(_latitude, _longitude)) {
      setState(() {
        _saveError = 'Set a map location before saving.';
      });
      return;
    }
    final name = _nameController.text.trim();
    final walkingRaw = _walkingMinutesController.text.trim();
    final walkingMinutes = walkingRaw.isEmpty
        ? null
        : int.tryParse(walkingRaw);
    final entranceFee = _entranceFeeController.text.trim();
    final foodAndDrinks = _foodAndDrinksController.text.trim();
    final otherSouvenirs = _otherSouvenirsController.text.trim();
    final priceRange = computeSpotPriceRangeFromFees(
      entranceFee: entranceFee,
      foodAndDrinksPrice: foodAndDrinks,
      otherSouvenirsPrice: otherSouvenirs,
    );
    final spot = TouristSpot(
      name: name,
      priceRange: priceRange,
      imagePath: _imageController.text.trim(),
      location: _locationController.text.trim(),
      rating: widget.existing?.rating ?? 0.0,
      description: _descriptionController.text.trim(),
      type: _type,
      latitude: _latitude,
      longitude: _longitude,
      walkingDistanceMinutes: walkingMinutes,
      entranceFee: entranceFee,
      foodAndDrinksPrice: foodAndDrinks,
      otherSouvenirsPrice: otherSouvenirs,
      firestoreDocId: widget.existing?.firestoreDocId,
      category: widget.existing?.category ?? '',
      visitors: widget.existing?.visitors ?? 0,
      ratingCount: widget.existing?.ratingCount ?? 0,
      updatedAtMs: widget.existing?.updatedAtMs ?? 0,
    );
    setState(() {
      _saving = true;
      _saveError = null;
    });
    try {
      await upsertTouristSpotToFirestore(spot, oldName: widget.existing?.name);
      try {
        await loadTouristSpotsFromFirestore();
        tourismCatalogRevision.value++;
      } catch (e) {
        debugPrint('reload after spot save (non-fatal): $e');
      }
      if (mounted) Navigator.pop(context);
    } catch (e) {
      debugPrint('AdminSpotFormPage save failed: $e');
      if (mounted) {
        setState(() {
          _saving = false;
          _saveError = 'Save failed: $e';
        });
      }
    }
  }

  Future<void> _openLocationPicker() async {
    final picked = await showAdminSpotLocationPicker(
      context,
      latitude: _latitude,
      longitude: _longitude,
      municipalityName: _locationController.text.trim(),
    );
    if (!mounted || picked == null) return;
    setState(() {
      _latitude = picked.latitude;
      _longitude = picked.longitude;
      if (_saveError == 'Set a map location before saving.') {
        _saveError = null;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final hasMapLocation = isValidSpotCoordinate(_latitude, _longitude);
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        title: Text(
          widget.existing != null ? 'Edit tourist spot' : 'Add tourist spot',
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextFormField(
                controller: _nameController,
                decoration: const InputDecoration(labelText: 'Name'),
                validator: (v) => v?.trim().isEmpty ?? true ? 'Required' : null,
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                value: _type,
                decoration: const InputDecoration(
                  labelText: 'Type',
                  hintText: 'Select a type',
                ),
                hint: const Text('Select a type'),
                isExpanded: true,
                items: _spotTypeOptions
                    .map(
                      (option) =>
                          DropdownMenuItem(value: option, child: Text(option)),
                    )
                    .toList(),
                onChanged: (v) => setState(() => _type = v ?? 'Nature'),
                validator: (v) =>
                    v == null || v.isEmpty ? 'Please select a type' : null,
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<String?>(
                value: _locationController.text.trim().isEmpty
                    ? null
                    : municipalities.any(
                        (m) => m.name == _locationController.text.trim(),
                      )
                    ? _locationController.text.trim()
                    : null,
                decoration: const InputDecoration(
                  labelText: 'Location (municipality)',
                  hintText: 'Select a municipality',
                ),
                hint: const Text('Select a municipality'),
                isExpanded: true,
                items: [
                  const DropdownMenuItem(
                    value: null,
                    child: Text('Select a municipality'),
                  ),
                  ...municipalities.map(
                    (m) => DropdownMenuItem(value: m.name, child: Text(m.name)),
                  ),
                ],
                onChanged: municipalities.isEmpty
                    ? null
                    : (v) => setState(() => _locationController.text = v ?? ''),
                validator: (v) => v == null || v.toString().trim().isEmpty
                    ? 'Please select a municipality'
                    : null,
              ),
              const SizedBox(height: 16),
              const Text(
                'Location',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: AppColors.textDark,
                ),
              ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: _openLocationPicker,
                icon: const Icon(Icons.location_on),
                label: const Text('Set Location on Map'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.primary,
                  side: const BorderSide(color: AppColors.primary),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
              ),
              const SizedBox(height: 8),
              if (hasMapLocation) ...[
                Text(
                  'Latitude: ${_latitude!.toStringAsFixed(4)}',
                  style: const TextStyle(
                    fontSize: 13,
                    color: AppColors.textDark,
                  ),
                ),
                Text(
                  'Longitude: ${_longitude!.toStringAsFixed(4)}',
                  style: const TextStyle(
                    fontSize: 13,
                    color: AppColors.textDark,
                  ),
                ),
                const SizedBox(height: 8),
                AdminSpotLocationPreview(
                  key: ValueKey('$_latitude,$_longitude'),
                  latitude: _latitude!,
                  longitude: _longitude!,
                ),
              ] else
                Text(
                  'No map location set yet.',
                  style: TextStyle(fontSize: 12, color: AppColors.textGrey),
                ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _descriptionController,
                decoration: const InputDecoration(labelText: 'Description'),
                maxLines: 3,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _walkingMinutesController,
                decoration: const InputDecoration(
                  labelText: 'Walking distance (minutes)',
                  hintText: 'e.g. 15',
                ),
                keyboardType: TextInputType.number,
                validator: (v) {
                  final t = v?.trim() ?? '';
                  if (t.isEmpty) return null;
                  final n = int.tryParse(t);
                  if (n == null) return 'Enter a whole number of minutes';
                  if (n < 0) return 'Minutes cannot be negative';
                  return null;
                },
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _entranceFeeController,
                decoration: const InputDecoration(
                  labelText: 'Entrance fee',
                  hintText: 'e.g. 50 or Free',
                ),
                keyboardType: TextInputType.number,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _foodAndDrinksController,
                decoration: const InputDecoration(
                  labelText: 'Food and drinks price',
                  hintText: 'e.g. 100',
                ),
                keyboardType: TextInputType.number,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _otherSouvenirsController,
                decoration: const InputDecoration(
                  labelText: 'Other souvenirs price',
                  hintText: 'e.g. 50',
                ),
                keyboardType: TextInputType.number,
              ),
              const SizedBox(height: 8),
              Text(
                'Price range is set automatically from entrance + food & drinks + souvenirs when you save.',
                style: TextStyle(
                  fontSize: 12,
                  color: AppColors.textGrey.withValues(alpha: 0.95),
                  height: 1.35,
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                'Profile picture',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: AppColors.textDark,
                ),
              ),
              const SizedBox(height: 8),
              GestureDetector(
                onTap: _uploadingImage ? null : _pickImage,
                child: Container(
                  height: 160,
                  decoration: BoxDecoration(
                    color: AppColors.primary.withOpacity(0.08),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: AppColors.primary.withOpacity(0.3),
                    ),
                  ),
                  child: _uploadingImage
                      ? const Center(child: CircularProgressIndicator())
                      : _previewBytes != null
                      ? ClipRRect(
                          borderRadius: BorderRadius.circular(12),
                          child: Image.memory(
                            _previewBytes!,
                            fit: BoxFit.cover,
                            filterQuality: FilterQuality.high,
                          ),
                        )
                      : _imageController.text.isNotEmpty
                      ? ClipRRect(
                          borderRadius: BorderRadius.circular(12),
                          child: buildMunicipalityImage(
                            _imageController.text,
                            fallback: _buildSpotPickImagePlaceholder(),
                          ),
                        )
                      : _buildSpotPickImagePlaceholder(),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Tap to pick image from device',
                style: TextStyle(fontSize: 12, color: AppColors.textGrey),
              ),
              if (_saveError != null) ...[
                const SizedBox(height: 8),
                Text(
                  _saveError!,
                  style: TextStyle(
                    color: Colors.red.shade700,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: _saving ? null : _save,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  disabledBackgroundColor:
                      AppColors.primary.withValues(alpha: 0.5),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                child: _saving
                    ? const SizedBox(
                        height: 22,
                        width: 22,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.5,
                          color: Colors.white,
                        ),
                      )
                    : const Text(
                        'Save',
                        style: TextStyle(color: Colors.white),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Municipality form page ─────────────────────────────────────────────

class AdminMunicipalityFormPage extends StatefulWidget {
  final Municipality? existing;
  final int? index;

  const AdminMunicipalityFormPage({super.key, this.existing, this.index});

  @override
  State<AdminMunicipalityFormPage> createState() =>
      _AdminMunicipalityFormPageState();
}

class _AdminMunicipalityFormPageState extends State<AdminMunicipalityFormPage> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _nameController;
  String? _imagePath;
  bool _uploadingImage = false;
  Uint8List? _previewBytes;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.existing?.name ?? '');
    _imagePath =
        (widget.existing != null && widget.existing!.imagePath.isNotEmpty)
        ? widget.existing!.imagePath
        : null;
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _pickImage() async {
    final picker = ImagePicker();
    final xFile = await picker.pickImage(source: ImageSource.gallery);
    if (xFile == null) return;
    final bytes = await xFile.readAsBytes();
    if (!mounted) return;
    setState(() {
      _previewBytes = bytes; // show picked image immediately from device
      _uploadingImage = true;
    });
    try {
      final currentName = _nameController.text.trim();
      final slug = _slug(currentName.isEmpty ? 'municipality' : currentName);
      final folder = 'municipalities/$slug';
      final url = await uploadTourismCatalogImage(bytes, folder);
      if (mounted) {
        setState(() {
          _imagePath = url;
          _uploadingImage = false;
        });
        // Also update the in-memory municipalities list so the list avatar
        // immediately reflects the new profile picture.
        if (widget.index != null &&
            widget.index! >= 0 &&
            widget.index! < municipalities.length) {
          final existing = municipalities[widget.index!];
          municipalities[widget.index!] = Municipality(
            name: existing.name,
            shortName: existing.shortName,
            imagePath: url,
            description: existing.description,
            spots: existing.spots,
            divisionKind: existing.divisionKind,
            busTerminal: existing.busTerminal,
          );
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() => _uploadingImage = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Upload failed: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Widget _buildPickImagePlaceholder() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.add_photo_alternate,
            size: 48,
            color: AppColors.primary.withOpacity(0.6),
          ),
          const SizedBox(height: 8),
          Text(
            'Tap to pick from device',
            style: TextStyle(fontSize: 13, color: AppColors.textGrey),
          ),
        ],
      ),
    );
  }

  Future<void> _save() async {
    if (_saving) return;
    if (!_formKey.currentState!.validate()) return;
    _saving = true;
    if (mounted) setState(() {});
    final name = _nameController.text.trim();
    final m = Municipality(
      name: name,
      shortName: name,
      imagePath: _imagePath ?? '',
      description: '',
      spots: const [],
      busTerminal: defaultBusTerminalFor(
        Municipality(
          name: name,
          shortName: name,
          imagePath: '',
          description: '',
          spots: const [],
        ),
      ),
    );
    if (widget.index != null) {
      municipalities[widget.index!] = m;
    } else if (!municipalities.any((existing) => existing.name == name)) {
      municipalities.add(m);
    }
    try {
      await upsertMunicipalityToFirestore(m, oldName: widget.existing?.name);
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Saved locally but Firestore failed: $e'),
            backgroundColor: Colors.orange,
          ),
        );
      }
      return;
    }
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        title: Text(
          widget.existing != null ? 'Edit municipality' : 'Add municipality',
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextFormField(
                controller: _nameController,
                decoration: const InputDecoration(
                  labelText: 'Name',
                  hintText: 'Municipality name',
                ),
                validator: (v) => v?.trim().isEmpty ?? true ? 'Required' : null,
              ),
              const SizedBox(height: 16),
              const Text(
                'Picture',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: AppColors.textDark,
                ),
              ),
              const SizedBox(height: 8),
              GestureDetector(
                onTap: _uploadingImage ? null : _pickImage,
                child: Container(
                  height: 160,
                  decoration: BoxDecoration(
                    color: AppColors.primary.withOpacity(0.08),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: AppColors.primary.withOpacity(0.3),
                    ),
                  ),
                  child: _uploadingImage
                      ? const Center(child: CircularProgressIndicator())
                      : _previewBytes != null
                      ? ClipRRect(
                          borderRadius: BorderRadius.circular(12),
                          child: Image.memory(
                            _previewBytes!,
                            fit: BoxFit.cover,
                            filterQuality: FilterQuality.high,
                          ),
                        )
                      : _imagePath != null
                      ? ClipRRect(
                          borderRadius: BorderRadius.circular(12),
                          child: buildMunicipalityImage(
                            _imagePath!,
                            fallback: _buildPickImagePlaceholder(),
                          ),
                        )
                      : _buildPickImagePlaceholder(),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Tap to pick image from device',
                style: TextStyle(fontSize: 12, color: AppColors.textGrey),
              ),
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: _saving ? null : _save,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  disabledBackgroundColor:
                      AppColors.primary.withValues(alpha: 0.5),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                child: Text(
                  _saving ? 'Saving...' : 'Save',
                  style: const TextStyle(color: Colors.white),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── User form page ─────────────────────────────────────────────────────

class AdminUserFormPage extends StatefulWidget {
  final AppUser? existing;
  final int? index;

  const AdminUserFormPage({super.key, this.existing, this.index});

  @override
  State<AdminUserFormPage> createState() => _AdminUserFormPageState();
}

class _AdminUserFormPageState extends State<AdminUserFormPage> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _nameController;
  late TextEditingController _emailController;
  String _role = 'user';
  late final String _docId;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final existingId = widget.existing?.id.trim() ?? '';
    _docId = existingId.isNotEmpty
        ? existingId
        : FirebaseFirestore.instance.collection(kUsersCollection).doc().id;
    _nameController = TextEditingController(text: widget.existing?.name ?? '');
    _emailController = TextEditingController(
      text: widget.existing?.email ?? '',
    );
    _role = widget.existing?.role ?? 'tourist';
  }

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving) return;
    if (!_formKey.currentState!.validate()) return;
    _saving = true;
    if (mounted) setState(() {});
    final user = AppUser(
      id: _docId,
      name: _nameController.text.trim(),
      email: _emailController.text.trim(),
      role: _role,
      profilePhotoPath: widget.existing?.profilePhotoPath ?? '',
      profilePhotoLookupId: widget.existing?.profilePhotoLookupId ?? '',
    );
    try {
      await upsertAppUserToFirestore(user);
      await loadUsersFromFirestore();
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to save user: $e'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        title: Text(widget.existing != null ? 'Edit user' : 'Add user'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextFormField(
                controller: _nameController,
                decoration: const InputDecoration(labelText: 'Name'),
                validator: (v) => v?.trim().isEmpty ?? true ? 'Required' : null,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _emailController,
                decoration: const InputDecoration(labelText: 'Email'),
                keyboardType: TextInputType.emailAddress,
                validator: (v) => v?.trim().isEmpty ?? true ? 'Required' : null,
              ),
              const SizedBox(height: 16),
              Builder(
                builder: (context) {
                  const presets = AuthRoles.adminRolePresetValues;
                  final choices = {...presets, _role}.toList()..sort();
                  final value = choices.contains(_role) ? _role : choices.first;
                  return DropdownButtonFormField<String>(
                    value: value,
                    decoration: const InputDecoration(labelText: 'Role'),
                    items: choices
                        .map(
                          (r) => DropdownMenuItem<String>(
                            value: r,
                            child: Text(
                              AppRole.fromString(r).label,
                            ),
                          ),
                        )
                        .toList(),
                    onChanged: (v) => setState(() => _role = v ?? 'tourist'),
                  );
                },
              ),
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: _saving ? null : _save,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  disabledBackgroundColor:
                      AppColors.primary.withValues(alpha: 0.5),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                child: Text(
                  _saving ? 'Saving...' : 'Save',
                  style: const TextStyle(color: Colors.white),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Check-ins, VR Tour, Reports, Spots & QR, Settings ─────────────────

class _AdminCheckInsTab extends StatefulWidget {
  const _AdminCheckInsTab();

  @override
  State<_AdminCheckInsTab> createState() => _AdminCheckInsTabState();
}

class _AdminCheckInsTabState extends State<_AdminCheckInsTab> {

  String _pickString(Map<String, dynamic> data, List<String> keys) {
    for (final key in keys) {
      final value = data[key];
      if (value == null) continue;
      final text = value.toString().trim();
      if (text.isNotEmpty) return text;
    }
    return '';
  }

  Map<String, dynamic> _flattenCheckIn(Map<String, dynamic> raw) {
    final flat = Map<String, dynamic>.from(raw);
    for (final nest in const [
      'user',
      'profile',
      'tourist',
      'visitor',
      'checkIn',
      'check_in',
      'data',
      'payload',
    ]) {
      final inner = raw[nest];
      if (inner is Map<String, dynamic>) {
        for (final e in inner.entries) {
          flat.putIfAbsent(e.key, () => e.value);
        }
      }
    }
    return flat;
  }

  DateTime? _pickDateTime(Map<String, dynamic> data) {
    for (final key in const ['checkInAt', 'checkinAt', 'visitAt', 'createdAt']) {
      final value = data[key];
      if (value is Timestamp) return value.toDate();
      if (value is DateTime) return value;
      if (value is String) {
        final parsed = DateTime.tryParse(value.trim());
        if (parsed != null) return parsed;
      }
    }
    return null;
  }

  String _timeLabel(Map<String, dynamic> data) {
    final explicitDate = _pickString(data, const ['date']);
    final explicitTime = _pickString(data, const ['time']);
    if (explicitDate.isNotEmpty || explicitTime.isNotEmpty) {
      return [if (explicitDate.isNotEmpty) explicitDate, if (explicitTime.isNotEmpty) explicitTime]
          .join(' · ');
    }
    final dt = _pickDateTime(data);
    if (dt == null) return '—';
    return formatEventDateTimeDisplay(dt);
  }

  @override
  Widget build(BuildContext context) {
    return AdminLiveDataBuilder(
      builder: (context, live) {
        if (live.checkInsError != null &&
            live.checkInsReady &&
            live.checkIns.isEmpty) {
          return OptacaLoadError(
            title: 'Could not load check-ins',
            message: '${live.checkInsError}',
            onRetry: live.retry,
          );
        }
        if (!live.checkInsReady) {
          return const Center(child: CircularProgressIndicator());
        }
        const collectionName = kQrCheckInsCollection;
        final docs = List<QueryDocumentSnapshot<Map<String, dynamic>>>.from(
          live.checkIns,
        )..sort((a, b) {
                final ta = _pickDateTime(a.data()) ??
                    DateTime.fromMillisecondsSinceEpoch(0);
                final tb = _pickDateTime(b.data()) ??
                    DateTime.fromMillisecondsSinceEpoch(0);
                return tb.compareTo(ta);
              });
            if (docs.isEmpty) {
              return _portalEmptyState(
                icon: Icons.fact_check_outlined,
                title: 'No check-ins yet',
                subtitle: 'No records found in "$collectionName".',
              );
            }
            return ListView.separated(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
          itemCount: docs.length,
          separatorBuilder: (_, __) => const SizedBox(height: 10),
          itemBuilder: (context, index) {
            final data = _flattenCheckIn(docs[index].data());
            final userName = _pickString(data, const [
              'visitorName',
              'visitor_name',
              'touristName',
              'tourist_name',
              'userName',
              'user_name',
              'fullName',
              'full_name',
              'displayName',
              'display_name',
              'nameOnRegistration',
              'registeredName',
              'name',
            ]);
            final userIdentity = _pickString(data, const [
              'userId',
              'uid',
              'firebaseUid',
              'touristID',
              'touristId',
              'email',
              'phone',
            ]);
            final touristId = _pickString(data, const [
              'touristID',
              'touristId',
              'touristDocumentId',
              'tourist_document_id',
            ]);
            final spot = _pickString(data, const [
              'spotName',
              'spot_name',
              'touristSpotName',
              'destination',
            ]);
            final municipality = _pickString(data, const [
              'visitMunicipality',
              'visitedMunicipality',
              'municipality',
              'city',
              'town',
              'location',
            ]);
            final whenLabel = _timeLabel(data);
            final topLine = spot.isNotEmpty ? spot : 'Check-in';
            final who = userName.isNotEmpty
                ? userName
                : (userIdentity.isNotEmpty ? userIdentity : 'Unknown user');
            final metaBits = <String>[
              who,
              if (touristId.isNotEmpty) touristId,
              if (municipality.isNotEmpty) municipality,
            ];
            return _portalListCard(
              child: ListTile(
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 18,
                  vertical: 6,
                ),
                leading: CircleAvatar(
                  backgroundColor: AppColors.primary.withValues(alpha: 0.12),
                  child: Icon(
                    Icons.where_to_vote_rounded,
                    color: AppColors.primary,
                    size: 22,
                  ),
                ),
                title: Text(
                  topLine,
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    color: AppColors.textDark,
                  ),
                ),
                subtitle: Text(
                  '${metaBits.join(' · ')}\n$whenLabel',
                  style: const TextStyle(
                    fontSize: 13,
                    color: AppColors.textGrey,
                    height: 1.35,
                  ),
                ),
                trailing: const Icon(
                  Icons.chevron_right,
                  color: AppColors.textGrey,
                ),
              ),
            );
          },
            );
      },
    );
  }
}

class _VrTourThumb extends StatelessWidget {
  const _VrTourThumb({required this.path});

  final String path;

  @override
  Widget build(BuildContext context) {
    final fallback = Container(
      color: AppColors.primary.withValues(alpha: 0.12),
      child: const Icon(Icons.vrpano_rounded, color: AppColors.primary),
    );
    if (path.isEmpty) return fallback;
    if (path.startsWith('assets/')) {
      return Image.asset(
        path,
        fit: BoxFit.cover,
        cacheWidth: 112,
        cacheHeight: 112,
        filterQuality: FilterQuality.medium,
        errorBuilder: (context, error, stackTrace) => fallback,
      );
    }
    return Image.network(
      path,
      fit: BoxFit.cover,
      cacheWidth: 112,
      cacheHeight: 112,
      filterQuality: FilterQuality.medium,
      errorBuilder: (context, error, stackTrace) => fallback,
      loadingBuilder: (context, child, progress) {
        if (progress == null) return child;
        return fallback;
      },
    );
  }
}

class _AdminVrTourTab extends StatefulWidget {
  const _AdminVrTourTab();

  @override
  State<_AdminVrTourTab> createState() => _AdminVrTourTabState();
}

class _AdminVrTourTabState extends State<_AdminVrTourTab> {
  final _search = TextEditingController();
  String _municipality = 'All';
  Stream<QuerySnapshot<Map<String, dynamic>>> _spots =
      FirebaseFirestore.instance.collection('tourist_spots').snapshots();

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  static String _vrLinkOf(Map<String, dynamic> d) {
    for (final key in const ['vr_link', 'vrLink', 'vrTourUrl', 'vrUrl', 'vr_url']) {
      final v = d[key]?.toString().trim() ?? '';
      if (v.isNotEmpty) return v;
    }
    return '';
  }

  static String _muniOf(Map<String, dynamic> d) {
    final name = d['municipality']?.toString().trim() ?? '';
    if (name.isNotEmpty) return name;
    return d['municipalityId']?.toString().trim() ?? 'Unassigned';
  }

  static String _imageOf(Map<String, dynamic> d) {
    for (final key in const ['image_url', 'imageUrl', 'image', 'thumbnail']) {
      final v = d[key]?.toString().trim() ?? '';
      if (v.isNotEmpty) return v;
    }
    return '';
  }

  /// Fallback Clear Pano catalog when ATMOS host bridge is not wired.
  static List<Map<String, dynamic>> _fallbackKnownVr() => const [
        {
          'id': 'oroquieta_city_boulevard_and_peoples_park',
          'name': 'Oroquieta City Boulevard And People\u2019s Park',
          'municipality': 'Oroquieta City',
          'municipalityId': 'oroquieta',
          'vr_link': 'https://tours.clearpano.com/aCxkEqVT',
          'image_url': 'assets/images/oroquieta City plaza.jpeg',
        },
        {
          'id': 'oroquieta_kenjelo_farm_resort',
          'name': 'Kenjelo Farm and Recreation Resort',
          'municipality': 'Oroquieta City',
          'municipalityId': 'oroquieta',
          'vr_link': 'https://tours.clearpano.com/Rpj4vYOF',
          'image_url': 'assets/images/Kenjelo.jpg',
        },
        {
          'id': 'jimenez_st_john_the_baptist_church',
          'name': 'Jimenez Church (St John The Baptist)',
          'municipality': 'Jimenez',
          'municipalityId': 'jimenez',
          'vr_link': 'https://tours.clearpano.com/Yx3FCtm9',
          'image_url': 'assets/images/Jimenez.png',
        },
        {
          'id': 'clarin_suman_capital',
          'name': 'Clarin Suman Capital',
          'municipality': 'Clarin',
          'municipalityId': 'clarin',
          'vr_link': 'https://tours.clearpano.com/GmFjcb6k',
          'image_url': 'assets/images/Clarin.png',
        },
        {
          'id': 'ozamiz_cotta_fort_shrine',
          'name': 'Cotta Fort & Shrine',
          'municipality': 'Ozamis City',
          'municipalityId': 'ozamiz',
          'vr_link': 'https://tours.clearpano.com/rDNLii_q',
          'image_url': 'assets/images/Cotta Fort & Shrine.jpg',
        },
      ];

  static List<Map<String, dynamic>> _mergeVrSpots(
    List<Map<String, dynamic>> firestoreSpots,
  ) {
    final merger = TripPlanHostBridge.mergeKnownVrDestinations;
    if (merger != null) return merger(firestoreSpots);

    final byId = {
      for (final s in firestoreSpots)
        if ((s['id']?.toString() ?? '').isNotEmpty) s['id'].toString(): s,
    };
    final out = <Map<String, dynamic>>[];
    final seen = <String>{};
    for (final known in _fallbackKnownVr()) {
      final id = known['id']!.toString();
      final existing = byId[id];
      if (existing != null) {
        final merged = Map<String, dynamic>.from(existing);
        if (_vrLinkOf(merged).isEmpty) {
          merged['vr_link'] = known['vr_link'];
          merged['hasVR'] = true;
        }
        out.add(merged);
      } else {
        out.add(Map<String, dynamic>.from(known));
      }
      seen.add(id);
    }
    for (final s in firestoreSpots) {
      final id = s['id']?.toString() ?? '';
      if (seen.contains(id)) continue;
      if (_vrLinkOf(s).isEmpty) continue;
      out.add(s);
      if (id.isNotEmpty) seen.add(id);
    }
    out.sort(
      (a, b) => (a['name']?.toString() ?? '')
          .toLowerCase()
          .compareTo((b['name']?.toString() ?? '').toLowerCase()),
    );
    return out;
  }

  @override
  Widget build(BuildContext context) {
    final canEdit = AuthRoles.canEditVirtualTourLinks();
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: _spots,
      builder: (context, snap) {
        if (snap.hasError) {
          return OptacaLoadError(
            title: 'Could not load virtual tours',
            message: '${snap.error}',
            onRetry: () => setState(() {
              _spots = FirebaseFirestore.instance
                  .collection('tourist_spots')
                  .snapshots();
            }),
          );
        }
        if (!snap.hasData) {
          return const Center(child: CircularProgressIndicator(color: AppColors.primary));
        }

        final firestoreSpots = snap.data!.docs
            .map((d) => <String, dynamic>{'id': d.id, ...d.data()})
            .toList();
        final withVr = _mergeVrSpots(firestoreSpots);

        final munis = <String>{
          'All',
          ...withVr.map(_muniOf).where((m) => m.isNotEmpty),
        }.toList()
          ..sort((a, b) {
            if (a == 'All') return -1;
            if (b == 'All') return 1;
            return a.compareTo(b);
          });

        final q = _search.text.trim().toLowerCase();
        final filtered = withVr.where((d) {
          final name = (d['name']?.toString() ?? '').toLowerCase();
          final muni = _muniOf(d);
          if (q.isNotEmpty && !name.contains(q) && !muni.toLowerCase().contains(q)) {
            return false;
          }
          if (_municipality != 'All' && muni != _municipality) return false;
          return true;
        }).toList();

        final counts = <String, int>{};
        for (final d in withVr) {
          final m = _muniOf(d);
          counts[m] = (counts[m] ?? 0) + 1;
        }

        return ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
          children: [
            Align(
              alignment: Alignment.centerRight,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: const Color(0xFF0EA5E9).withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(99),
                ),
                child: Text(
                  canEdit ? 'LGU-managed' : 'View Only',
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF0284C7),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _search,
              onChanged: (_) => setState(() {}),
              decoration: OptacaPortalUi.searchDecoration(
                hint: 'Search virtual tours',
              ),
            ),
            const SizedBox(height: 10),
            DropdownButtonFormField<String>(
              initialValue: munis.contains(_municipality) ? _municipality : 'All',
              isExpanded: true,
              decoration: InputDecoration(
                labelText: 'Municipality',
                filled: true,
                fillColor: Colors.white,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              ),
              items: [
                for (final m in munis)
                  DropdownMenuItem(
                    value: m,
                    child: Text(
                      m == 'All' ? 'All' : '$m (${counts[m] ?? 0})',
                    ),
                  ),
              ],
              onChanged: (v) => setState(() => _municipality = v ?? 'All'),
            ),
            const SizedBox(height: 14),
            Text(
              '${filtered.length} virtual tour${filtered.length == 1 ? '' : 's'}',
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: AppColors.textGrey,
              ),
            ),
            const SizedBox(height: 10),
            if (withVr.isEmpty)
              _portalListCard(
                child: const Padding(
                  padding: EdgeInsets.all(28),
                  child: Column(
                    children: [
                      Icon(Icons.vrpano_outlined, size: 40, color: AppColors.textGrey),
                      SizedBox(height: 12),
                      Text(
                        'No virtual tours yet',
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 16,
                          color: AppColors.textDark,
                        ),
                      ),
                      SizedBox(height: 6),
                      Text(
                        'When an LGU links a 360° tour to a destination, it appears here automatically.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: AppColors.textGrey, height: 1.4),
                      ),
                    ],
                  ),
                ),
              )
            else if (filtered.isEmpty)
              _portalListCard(
                child: const Padding(
                  padding: EdgeInsets.all(24),
                  child: Text(
                    'No tours match this filter.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: AppColors.textGrey),
                  ),
                ),
              )
            else
              for (final d in filtered) ...[
                _portalListCard(
                  child: ListTile(
                    contentPadding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
                    leading: ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: SizedBox(
                        width: 56,
                        height: 56,
                        child: _VrTourThumb(path: _imageOf(d)),
                      ),
                    ),
                    title: Text(
                      d['name']?.toString() ?? 'Destination',
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    subtitle: Text(
                      '${_muniOf(d)} · 360° tour linked',
                      style: const TextStyle(fontSize: 12.5, color: AppColors.textGrey),
                    ),
                    trailing: FilledButton.tonal(
                      onPressed: () async {
                        final preview = TripPlanHostBridge.openVrPreview;
                        if (preview == null) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text(
                                'Open this portal from ATMOS to preview the virtual tour.',
                              ),
                            ),
                          );
                          return;
                        }
                        await preview(
                          context,
                          spotId: d['id']?.toString() ?? '',
                          spotName: d['name']?.toString() ?? 'VR Tour',
                          vrLink: _vrLinkOf(d),
                          imageUrl: _imageOf(d),
                        );
                      },
                      child: const Text('Preview'),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
              ],
          ],
        );
      },
    );
  }
}

class _AdminSpotsQrTab extends StatefulWidget {
  final VoidCallback onOpenSpotsTab;

  const _AdminSpotsQrTab({required this.onOpenSpotsTab});

  @override
  State<_AdminSpotsQrTab> createState() => _AdminSpotsQrTabState();
}

class _AdminSpotsQrTabState extends State<_AdminSpotsQrTab> {
  static const String _kAllMunicipalities = 'All municipalities';

  String _selectedMunicipalityForSpots = _kAllMunicipalities;
  String _selectedSpot = 'All tourist spots';
  Stream<QuerySnapshot<Map<String, dynamic>>> _spots =
      FirebaseFirestore.instance
          .collection(kTouristSpotsCollection)
          .orderBy('name')
          .snapshots();

  void _retrySpots() {
    setState(() {
      _spots = FirebaseFirestore.instance
          .collection(kTouristSpotsCollection)
          .orderBy('name')
          .snapshots();
    });
  }

  String _slug(String value) {
    return value
        .toLowerCase()
        .trim()
        .replaceAll(RegExp(r'[^a-z0-9\s]'), '')
        .replaceAll(RegExp(r'\s+'), '_');
  }

  String _spotName(Map<String, dynamic> data, String docId) {
    final raw = data['name'];
    if (raw is String && raw.trim().isNotEmpty) return raw.trim();
    return docId;
  }

  String _spotMunicipality(Map<String, dynamic> data) {
    const candidateKeys = <String>[
      'location',
      'municipality',
      'municipalityName',
    ];
    for (final key in candidateKeys) {
      final raw = data[key];
      if (raw is String && raw.trim().isNotEmpty) return raw.trim();
    }
    return '';
  }

  String _spotQrValue(Map<String, dynamic> data, String docId) {
    const candidateKeys = <String>[
      'qrCode',
      'qrcode',
      'qr_code',
      'spotQrCode',
      'spot_qr_code',
    ];
    for (final key in candidateKeys) {
      final raw = data[key];
      if (raw is String && raw.trim().isNotEmpty) return raw.trim();
    }
    // Fallback keeps QR available even if value wasn't stored yet.
    return docId;
  }

  int _gridCountForWidth(double width) {
    if (width >= 1300) return 5;
    if (width >= 1050) return 4;
    if (width >= 760) return 3;
    if (width >= 520) return 2;
    return 1;
  }

  Widget _downloadAction({
    required BuildContext context,
    required String label,
    required String spotName,
  }) {
    return TextButton(
      onPressed: () {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '$label download for "$spotName" will be wired next.',
            ),
          ),
        );
      },
      style: TextButton.styleFrom(
        foregroundColor: AppColors.primary,
        textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
      ),
      child: Text(label),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _portalSectionTitle('Spots & LGU QR'),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _portalMiniStat(
                  label: 'Active spots',
                  value: '${allSpots.length}',
                  icon: Icons.place_outlined,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _portalMiniStat(
                  label: 'Municipalities',
                  value: '${municipalities.length}',
                  icon: Icons.location_city_outlined,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          _portalListCard(
            child: Padding(
              padding: const EdgeInsets.all(22),
              child: Builder(
                builder: (context) {
                  final sortedMuniNames =
                      municipalities.map((m) => m.name).toSet().toList()
                        ..sort();
                  final spotMunicipalityFilterOptions = <String>[
                    _kAllMunicipalities,
                    ...sortedMuniNames,
                  ];
                  if (!spotMunicipalityFilterOptions.contains(
                    _selectedMunicipalityForSpots,
                  )) {
                    _selectedMunicipalityForSpots = _kAllMunicipalities;
                  }

                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Municipality QR',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: AppColors.textDark,
                        ),
                      ),
                      const SizedBox(height: 12),
                      LayoutBuilder(
                        builder: (context, constraints) {
                          return GridView.builder(
                            shrinkWrap: true,
                            physics: const NeverScrollableScrollPhysics(),
                            itemCount: municipalities.length,
                            gridDelegate:
                                SliverGridDelegateWithFixedCrossAxisCount(
                                  crossAxisCount: _gridCountForWidth(
                                    constraints.maxWidth,
                                  ),
                                  mainAxisSpacing: 20,
                                  crossAxisSpacing: 20,
                                  childAspectRatio: 0.88,
                                ),
                            itemBuilder: (context, index) {
                              final m = municipalities[index];
                              final slug = _slug(m.name);
                              final name = m.name;
                              final qr = slug;
                              return Container(
                                padding: const EdgeInsets.all(10),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFFFFCFA),
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(
                                    color: const Color(0xFFE8DDD6),
                                    width: 0.75,
                                  ),
                                ),
                                child: Column(
                                  children: [
                                    Text(
                                      name,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                    const SizedBox(height: 8),
                                    Expanded(
                                      child: Center(
                                        child: Container(
                                          padding: const EdgeInsets.all(6),
                                          color: Colors.white,
                                          child: QrImageView(
                                            data: qr,
                                            size: 150,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            },
                          );
                        },
                      ),
                      const SizedBox(height: 18),
                      const Divider(height: 1),
                      const SizedBox(height: 18),
                      const Text(
                        'Tourist Spot QR',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: AppColors.textDark,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Expanded(
                            child: DropdownButtonFormField<String>(
                              value: _selectedMunicipalityForSpots,
                              decoration: const InputDecoration(
                                labelText: 'Municipality',
                              ),
                              items: spotMunicipalityFilterOptions
                                  .map(
                                    (n) => DropdownMenuItem<String>(
                                      value: n,
                                      child: Text(n),
                                    ),
                                  )
                                  .toList(),
                              onChanged: (v) => setState(() {
                                _selectedMunicipalityForSpots =
                                    v ?? _kAllMunicipalities;
                                _selectedSpot = 'All tourist spots';
                              }),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                              stream: _spots,
                              builder: (context, spotSnap) {
                                if (spotSnap.hasError) {
                                  return OptacaLoadError(
                                    title: 'Could not load spots',
                                    message: '${spotSnap.error}',
                                    onRetry: _retrySpots,
                                  );
                                }
                                final spotDocs =
                                    spotSnap.data?.docs ??
                                    <
                                      QueryDocumentSnapshot<
                                        Map<String, dynamic>
                                      >
                                    >[];
                                final filteredByMunicipality =
                                    _selectedMunicipalityForSpots ==
                                        _kAllMunicipalities
                                    ? spotDocs
                                    : spotDocs.where((d) {
                                        final muni = _spotMunicipality(
                                          d.data(),
                                        );
                                        return muni ==
                                            _selectedMunicipalityForSpots;
                                      }).toList();
                                final spotOptions = <String>[
                                  'All tourist spots',
                                  ...filteredByMunicipality
                                      .map((d) => _spotName(d.data(), d.id))
                                      .toSet()
                                      .toList()
                                    ..sort(),
                                ];
                                if (!spotOptions.contains(_selectedSpot)) {
                                  _selectedSpot = 'All tourist spots';
                                }

                                final filteredSpots =
                                    _selectedSpot == 'All tourist spots'
                                    ? filteredByMunicipality
                                    : filteredByMunicipality.where((d) {
                                        final n = _spotName(d.data(), d.id);
                                        return n == _selectedSpot;
                                      }).toList();

                                return Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    DropdownButtonFormField<String>(
                                      value: _selectedSpot,
                                      decoration: const InputDecoration(
                                        labelText: 'Tourist spot',
                                      ),
                                      items: spotOptions
                                          .map(
                                            (n) => DropdownMenuItem<String>(
                                              value: n,
                                              child: Text(n),
                                            ),
                                          )
                                          .toList(),
                                      onChanged: (v) => setState(
                                        () => _selectedSpot =
                                            v ?? 'All tourist spots',
                                      ),
                                    ),
                                    const SizedBox(height: 12),
                                    LayoutBuilder(
                                      builder: (context, constraints) {
                                        return GridView.builder(
                                          shrinkWrap: true,
                                          physics:
                                              const NeverScrollableScrollPhysics(),
                                          itemCount: filteredSpots.length,
                                          gridDelegate:
                                              SliverGridDelegateWithFixedCrossAxisCount(
                                                crossAxisCount:
                                                    _gridCountForWidth(
                                                      constraints.maxWidth,
                                                    ),
                                                mainAxisSpacing: 28,
                                                crossAxisSpacing: 28,
                                                childAspectRatio: 0.78,
                                              ),
                                          itemBuilder: (context, index) {
                                            final doc = filteredSpots[index];
                                            final data = doc.data();
                                            final spotName = _spotName(
                                              data,
                                              doc.id,
                                            );
                                            final qrValue = _spotQrValue(
                                              data,
                                              doc.id,
                                            );
                                            return Container(
                                              padding:
                                                  const EdgeInsets.fromLTRB(
                                                    8,
                                                    8,
                                                    8,
                                                    6,
                                                  ),
                                              decoration: BoxDecoration(
                                                color: const Color(0xFFFFFCFA),
                                                borderRadius:
                                                    BorderRadius.circular(10),
                                                border: Border.all(
                                                  color: const Color(
                                                    0xFFE8DDD6,
                                                  ),
                                                  width: 0.75,
                                                ),
                                              ),
                                              child: Column(
                                                children: [
                                                  Text(
                                                    spotName,
                                                    maxLines: 1,
                                                    overflow:
                                                        TextOverflow.ellipsis,
                                                    textAlign: TextAlign.center,
                                                    style: const TextStyle(
                                                      fontSize: 13,
                                                      fontWeight:
                                                          FontWeight.w700,
                                                      color: AppColors.textDark,
                                                    ),
                                                  ),
                                                  const SizedBox(height: 6),
                                                  Expanded(
                                                    child: Center(
                                                      child: Container(
                                                        padding:
                                                            const EdgeInsets.all(
                                                              5,
                                                            ),
                                                        decoration: BoxDecoration(
                                                          color: Colors.white,
                                                          borderRadius:
                                                              BorderRadius.circular(
                                                                8,
                                                              ),
                                                          border: Border.all(
                                                            color: const Color(
                                                              0xFFEEEEEE,
                                                            ),
                                                            width: 0.75,
                                                          ),
                                                        ),
                                                        child: QrImageView(
                                                          data: qrValue,
                                                          size: 104,
                                                          eyeStyle:
                                                              const QrEyeStyle(
                                                                color: Colors
                                                                    .black,
                                                                eyeShape:
                                                                    QrEyeShape
                                                                        .square,
                                                              ),
                                                          dataModuleStyle:
                                                              const QrDataModuleStyle(
                                                                color: Colors
                                                                    .black,
                                                                dataModuleShape:
                                                                    QrDataModuleShape
                                                                        .square,
                                                              ),
                                                        ),
                                                      ),
                                                    ),
                                                  ),
                                                  Row(
                                                    mainAxisAlignment:
                                                        MainAxisAlignment
                                                            .center,
                                                    children: [
                                                      _downloadAction(
                                                        context: context,
                                                        label: 'PNG',
                                                        spotName: spotName,
                                                      ),
                                                      _downloadAction(
                                                        context: context,
                                                        label: 'PDF',
                                                        spotName: spotName,
                                                      ),
                                                    ],
                                                  ),
                                                ],
                                              ),
                                            );
                                          },
                                        );
                                      },
                                    ),
                                  ],
                                );
                              },
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 20),
                      FilledButton.icon(
                        onPressed: widget.onOpenSpotsTab,
                        style: FilledButton.styleFrom(
                          backgroundColor: AppColors.primary,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 20,
                            vertical: 14,
                          ),
                        ),
                        icon: const Icon(
                          Icons.edit_location_alt_outlined,
                          color: Colors.white,
                        ),
                        label: const Text('Manage tourist spots'),
                      ),
                    ],
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _AdminSettingsTab extends StatefulWidget {
  const _AdminSettingsTab({
    this.onOpenBusStops,
    this.onOpenSpotsQr,
  });

  final VoidCallback? onOpenBusStops;
  final VoidCallback? onOpenSpotsQr;

  @override
  State<_AdminSettingsTab> createState() => _AdminSettingsTabState();
}

class _AdminSettingsTabState extends State<_AdminSettingsTab> {
  bool _emailDigest = true;
  bool _pushAlerts = true;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
      children: [
        _portalSectionTitle('Notifications'),
        const SizedBox(height: 8),
        _portalListCard(
          child: Column(
            children: [
              SwitchListTile(
                value: _emailDigest,
                onChanged: (v) => setState(() => _emailDigest = v),
                activeThumbColor: AppColors.primary,
                title: const Text(
                  'Weekly email digest',
                  style: TextStyle(fontWeight: FontWeight.w500),
                ),
                subtitle: const Text(
                  'Summary of arrivals and events',
                  style: TextStyle(fontSize: 13),
                ),
              ),
              const Divider(height: 1),
              SwitchListTile(
                value: _pushAlerts,
                onChanged: (v) => setState(() => _pushAlerts = v),
                activeThumbColor: AppColors.primary,
                title: const Text(
                  'Push alerts',
                  style: TextStyle(fontWeight: FontWeight.w500),
                ),
                subtitle: const Text(
                  'Urgent announcements to devices',
                  style: TextStyle(fontSize: 13),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),
        _portalSectionTitle('Portal'),
        const SizedBox(height: 8),
        _portalListCard(
          child: Column(
            children: [
              ListTile(
                leading: Icon(
                  Icons.info_outline_rounded,
                  color: AppColors.primary.withValues(alpha: 0.9),
                ),
                title: const Text('ATMOS TRS OPTACA PORTAL'),
                subtitle: const Text(
                  'Misamis Occidental tourism admin',
                  style: TextStyle(fontSize: 13),
                ),
              ),
              const Divider(height: 1),
              ListTile(
                leading: Icon(
                  Icons.policy_outlined,
                  color: AppColors.primary.withValues(alpha: 0.9),
                ),
                title: const Text('Privacy & data'),
                trailing: const Icon(
                  Icons.chevron_right,
                  color: AppColors.textGrey,
                ),
                onTap: () {},
              ),
              const Divider(height: 1),
              ListTile(
                leading: Icon(
                  Icons.directions_bus_outlined,
                  color: AppColors.primary.withValues(alpha: 0.9),
                ),
                title: const Text('Bus stops'),
                subtitle: const Text(
                  'Existing bus stop records',
                  style: TextStyle(fontSize: 13),
                ),
                trailing: const Icon(
                  Icons.chevron_right,
                  color: AppColors.textGrey,
                ),
                onTap: widget.onOpenBusStops,
              ),
              const Divider(height: 1),
              ListTile(
                leading: Icon(
                  Icons.qr_code_scanner_rounded,
                  color: AppColors.primary.withValues(alpha: 0.9),
                ),
                title: const Text('Spots & QR Code'),
                trailing: const Icon(
                  Icons.chevron_right,
                  color: AppColors.textGrey,
                ),
                onTap: widget.onOpenSpotsQr,
              ),
              if (TripPlanHostBridge.openDebugDataHub != null) ...[
                const Divider(height: 1),
                ListTile(
                  leading: Icon(
                    Icons.analytics_outlined,
                    color: AppColors.primary.withValues(alpha: 0.9),
                  ),
                  title: const Text('Debug data hub'),
                  subtitle: const Text(
                    'Charts, seed all LGUs, full purge — same as the Governor dashboard',
                    style: TextStyle(fontSize: 13),
                  ),
                  trailing: const Icon(
                    Icons.chevron_right,
                    color: AppColors.textGrey,
                  ),
                  onTap: () => TripPlanHostBridge.openDebugDataHub!(context),
                ),
              ],
              const Divider(height: 1),
              ListTile(
                leading: Icon(
                  Icons.people_outline_rounded,
                  color: AppColors.primary.withValues(alpha: 0.9),
                ),
                title: const Text('App user accounts'),
                subtitle: const Text(
                  'Firestore `users` (login profiles)',
                  style: TextStyle(fontSize: 13),
                ),
                trailing: const Icon(
                  Icons.chevron_right,
                  color: AppColors.textGrey,
                ),
                onTap: () {
                  Navigator.push<void>(
                    context,
                    MaterialPageRoute<void>(
                      builder: (_) => const AppUsersManagementScreen(),
                    ),
                  );
                },
              ),
            ],
          ),
        ),
      ],
    );
  }
}

Widget _portalSectionTitle(String text) {
  return Text(
    text,
    style: const TextStyle(
      fontSize: 13,
      fontWeight: FontWeight.bold,
      color: AppColors.textGrey,
      letterSpacing: 0.6,
    ),
  );
}

Widget _portalListCard({required Widget child}) {
  return Container(
    decoration: OptacaAdminTheme.cardDecoration,
    clipBehavior: Clip.antiAlias,
    child: child,
  );
}

Widget _portalMiniStat({
  required String label,
  required String value,
  required IconData icon,
}) {
  return Container(
    padding: const EdgeInsets.all(18),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(20),
      boxShadow: [
        BoxShadow(
          color: Colors.black.withValues(alpha: 0.07),
          blurRadius: 18,
          offset: const Offset(0, 6),
        ),
      ],
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: AppColors.primary, size: 22),
        const SizedBox(height: 10),
        Text(
          value,
          style: const TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.bold,
            color: AppColors.textDark,
          ),
        ),
        Text(
          label,
          style: const TextStyle(
            fontSize: 12,
            color: AppColors.textGrey,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    ),
  );
}

Widget _portalEmptyState({
  required IconData icon,
  required String title,
  required String subtitle,
}) {
  return Center(
    child: Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 56, color: AppColors.primary.withValues(alpha: 0.45)),
          const SizedBox(height: 16),
          Text(
            title,
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: AppColors.textDark,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            subtitle,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 14,
              color: AppColors.textGrey,
              height: 1.4,
            ),
          ),
        ],
      ),
    ),
  );
}

import 'dart:async' show unawaited;

import 'package:atmos_trs_system/config/module_shell_prefs.dart';
import 'package:atmos_trs_system/config/session_storage.dart';
import 'package:atmos_trs_system/config/vr_tour_config.dart';
import 'package:atmos_trs_system/navigation/login_route_args.dart';
import 'package:atmos_trs_system/navigation/post_logout_navigation.dart';
import 'package:atmos_trs_system/navigation/shared_module_logout.dart';
import 'package:atmos_trs_system/models/tourist_spot.dart';
import 'package:atmos_trs_system/screens/vr_webview_screen.dart';
import 'package:atmos_trs_system/services/user_directory_service.dart';
import 'package:atmos_trs_system/widgets/lgu_debug_data_dialogs.dart';
import 'package:atmos_trs_system/widgets/optaca_alerts_quality_panel.dart';
import 'package:atmos_trs_system/widgets/optaca_accounts_panel.dart';
import 'package:atmos_trs_system/utils/dot_report_entity_scope.dart';
import 'package:atmos_trs_system/widgets/optaca_portal_dot_reports.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:trip_plan/admin_dashboard_screen.dart';
import 'package:trip_plan/admin_reports_tab.dart';
import 'package:trip_plan/home_screen.dart';
import 'package:trip_plan/maps_platform_init.dart';
import 'package:trip_plan/widgets/admin_access_gate.dart';
import 'package:trip_plan/firestore_loader.dart';
import 'package:trip_plan/services/tourism_session.dart';
import 'package:trip_plan/theme/tourism_app_theme.dart';
import 'package:trip_plan/trip_plan_host_bridge.dart';
import 'package:video_player/video_player.dart';

/// Opens Trip Planner inside ATMOS.
///
/// [adminDashboard] is the catalog admin (governor, provincial, LGU tourism).
/// Tourists get the planner home.
class TripPlanEntryScreen extends StatefulWidget {
  const TripPlanEntryScreen({
    super.key,
    this.sharedHeroController,
    this.adminDashboard = false,
  });

  /// Kept so landing can pass the hero player; the planner home does not use it.
  final VideoPlayerController? sharedHeroController;

  final bool adminDashboard;

  @override
  State<TripPlanEntryScreen> createState() => _TripPlanEntryScreenState();
}

class _TripPlanEntryScreenState extends State<TripPlanEntryScreen> {
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    TripPlanHostBridge.embeddedInAtmos = true;
    if (widget.adminDashboard) {
      unawaited(
        ModuleShellPrefs.setActiveShell(ModuleShellPrefs.tripPlannerAdmin),
      );
      TripPlanHostBridge.isHostCatalogAdmin = () {
        // Sync hint for AdminAccessGate while users/{uid} is still loading.
        return true;
      };
      _bindOfficialDotReports();
      TripPlanHostBridge.openDebugDataHub = (ctx) {
        LguDebugDataDialogs.openHub(
          context: ctx,
          municipalityId: '',
          municipalityName: 'All municipalities',
          spots: const <TouristSpot>[],
          onDone: () {
            unawaited(loadUsersFromFirestore());
            unawaited(loadTouristSpotsFromFirestore());
            if (!ctx.mounted) return;
            ScaffoldMessenger.of(ctx).showSnackBar(
              const SnackBar(
                content: Text(
                  'Seed data is loaded. Overview and Tourist Monitoring use the same tourists and check-ins as the tourism dashboard.',
                ),
                behavior: SnackBarBehavior.floating,
              ),
            );
          },
        );
      };
    }
    TripPlanHostBridge.onSignedOut = signOutSharedModules;
    TripPlanHostBridge.openSharedLogin = (ctx) {
      Navigator.of(ctx).pushNamed(
        '/login',
        arguments: LoginRouteArgs.forFeature(
          returnFeature: LoginRouteArgs.featureItinerary,
        ),
      );
    };
    TripPlanHostBridge.openSharedSignup = (ctx) {
      final nav = Navigator.of(ctx);
      nav.pushNamed(
        '/login',
        arguments: LoginRouteArgs.forFeature(
          returnFeature: LoginRouteArgs.featureItinerary,
        ),
      );
      nav.pushNamed(
        '/signup-tourist',
        arguments: const {'fromLogin': true, 'loginDepth': 1},
      );
    };
    TripPlanHostBridge.leaveToHost = (ctx) {
      navigateAfterLogout(ctx);
    };
    if (widget.adminDashboard) {
      TripPlanHostBridge.openAtmosStaffModule = _openAtmosStaffModule;
    }
    TripPlanHostBridge.openVrPreview = (
      ctx, {
      required String spotId,
      required String spotName,
      String? vrLink,
      String? imageUrl,
    }) {
      return openVrForTouristSpot(
        ctx,
        spotId: spotId,
        spotName: spotName,
        vrLink: vrLink,
        imageUrl: imageUrl,
        allowWeb: true,
      );
    };
    TripPlanHostBridge.mergeKnownVrDestinations = mergeKnownVrDestinations;
    TripPlanHostBridge.alertsQualityPanel =
        (context) => const OptacaAlertsQualityPanel();
    TripPlanHostBridge.lguAccountManagementPanel =
        (context) => const OptacaAccountsPanel();
    unawaited(_bootstrap());
  }

  Future<void> _bootstrap() async {
    unawaited(initMapsForPlatform());
    unawaited(bootstrapAppFirestoreOnce());
    if (mounted) setState(() => _ready = true);
  }

  void _bindOfficialDotReports() {
    // Non-null flag: Fill forms for lists Events & Announcements and Matrix
    // Fares. Those categories now use the same Form Type / date / Excel / PDF
    // / preview controls as the other DOT forms — not AdminFillFormsExtraPanel.
    Widget extraFill(BuildContext _, DotReportEntityKind __) =>
        const SizedBox.shrink();

    AdminReportsTab.dotReportsBuilder = (context, _) => OptacaPortalDotReports(
          extraFillFormsBuilder: extraFill,
        );
    TripPlanHostBridge.officialDotReports = (context) => OptacaPortalDotReports(
          extraFillFormsBuilder: extraFill,
        );
  }

  @override
  void dispose() {
    TripPlanHostBridge.embeddedInAtmos = false;
    TripPlanHostBridge.openDebugDataHub = null;
    TripPlanHostBridge.onSignedOut = null;
    TripPlanHostBridge.openSharedLogin = null;
    TripPlanHostBridge.openSharedSignup = null;
    TripPlanHostBridge.leaveToHost = null;
    TripPlanHostBridge.openAtmosStaffModule = null;
    TripPlanHostBridge.openVrPreview = null;
    TripPlanHostBridge.mergeKnownVrDestinations = null;
    TripPlanHostBridge.alertsQualityPanel = null;
    TripPlanHostBridge.lguAccountManagementPanel = null;
    TripPlanHostBridge.isHostCatalogAdmin = null;
    super.dispose();
  }

  Future<void> _openAtmosStaffModule(BuildContext context) async {
    final user = FirebaseAuth.instance.currentUser;
    final email = (user?.email ?? '').trim();
    var role = email.isNotEmpty
        ? SessionStorage.getRoleFromEmail(email)
        : UserRole.tourist;

    if (role == UserRole.tourist && user != null) {
      final profile = await UserDirectoryService.getProfileByUid(
        user.uid,
        preferServer: false,
      );
      if (profile != null) {
        if (profile.isGovernor) {
          role = UserRole.governor;
        } else if (profile.isProvincialTourism) {
          role = UserRole.provincialTourism;
        } else if (profile.isTourismOffice) {
          role = UserRole.tourism;
        }
      } else {
        role = await SessionStorage.getStoredRole();
      }
    }

    final String route;
    switch (role) {
      case UserRole.governor:
        route = '/governor-dashboard';
      case UserRole.tourism:
        route = '/lgu-dashboard';
      case UserRole.provincialTourism:
        await ModuleShellPrefs.setActiveShell(
          ModuleShellPrefs.provincialTourism,
        );
        route = '/provincial-tourism-dashboard';
      default:
        if (!context.mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'No ATMOS TRS staff module is available for this account.',
            ),
            behavior: SnackBarBehavior.floating,
          ),
        );
        return;
    }

    if (!context.mounted) return;
    Navigator.of(context).pushNamedAndRemoveUntil(route, (_) => false);
  }

  @override
  Widget build(BuildContext context) {
    if (widget.adminDashboard) {
      _bindOfficialDotReports();
    }
    return Theme(
      data: TourismAppTheme.light,
      child: _ready
          ? (widget.adminDashboard
              ? const AdminAccessGate(child: AdminDashboardScreen())
              : const HomeScreen())
          : const Scaffold(
              body: Center(child: CircularProgressIndicator()),
            ),
    );
  }
}

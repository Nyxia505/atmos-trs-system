import 'package:flutter/material.dart';

import 'admin_dashboard_screen.dart';
import 'auth/login_screen.dart';
import 'auth/registration_screen.dart';
import 'trip_planner_page.dart';
import 'widgets/admin_access_gate.dart';

/// Named routes for TripPlan (standalone app + embedded in ATMOS TRS).
Map<String, WidgetBuilder> tripPlanRoutes() {
  return {
    TripPlannerPage.routeName: (_) => const TripPlannerPage(),
    AdminDashboardScreen.routeName: (_) => const AdminAccessGate(
          child: AdminDashboardScreen(),
        ),
    LoginScreen.routeName: (_) => const LoginScreen(),
    RegistrationScreen.routeName: (_) => const RegistrationScreen(),
  };
}

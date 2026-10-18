import 'package:flutter/material.dart';

import 'admin_dashboard_screen.dart';
import 'auth/login_screen.dart';
import 'auth/registration_screen.dart';
import 'tourist_plan/tourist_trip_planner_screen.dart';
import 'widgets/admin_access_gate.dart';

/// Named routes for the TripPlan module when it is hosted inside ATMOS.
Map<String, WidgetBuilder> tripPlanRoutes() => {
      TouristTripPlannerScreen.routeName: (_) =>
          const TouristTripPlannerScreen(),
      AdminDashboardScreen.routeName: (_) => const AdminAccessGate(
            child: AdminDashboardScreen(),
          ),
      LoginScreen.routeName: (_) => const LoginScreen(),
      RegistrationScreen.routeName: (_) => const RegistrationScreen(),
    };

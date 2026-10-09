import 'package:flutter/material.dart';

/// Hooks used when Trip Planner is opened from ATMOS TRS (shared Firebase Auth).
class TripPlanHostBridge {
  TripPlanHostBridge._();

  /// True while the planner dashboard is hosted inside the ATMOS navigator.
  static bool embeddedInAtmos = false;

  /// Clears the ATMOS session after Firebase sign-out (same account, both modules).
  static Future<void> Function()? onSignedOut;

  /// ATMOS login screen (same branding). Used instead of Trip Planner's own login.
  static void Function(BuildContext context)? openSharedLogin;

  /// ATMOS tourist signup. Used instead of Trip Planner's own registration form.
  static void Function(BuildContext context)? openSharedSignup;

  /// Leaves Trip Planner for the ATMOS post-logout route.
  static void Function(BuildContext context)? leaveToHost;
}

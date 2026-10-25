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

  /// Governor Debug data hub (charts, seed, full purge) hosted by ATMOS TRS.
  static void Function(BuildContext context)? openDebugDataHub;

  /// OPTACA / staff VR preview using ATMOS [openVrForTouristSpot] (read-only).
  static Future<void> Function(
    BuildContext context, {
    required String spotId,
    required String spotName,
    String? vrLink,
    String? imageUrl,
  })? openVrPreview;

  /// Merge Firestore spots with ATMOS known Clear Pano VR destinations.
  static List<Map<String, dynamic>> Function(
    List<Map<String, dynamic>> spots,
  )? mergeKnownVrDestinations;

  /// OPTACA Alerts & Quality panel (live Firestore audit) from ATMOS host.
  static WidgetBuilder? alertsQualityPanel;

  /// True while ATMOS has already authorized this user as a catalog admin
  /// (avoids Access Denied flash before Trip Planner `users` cache loads).
  static bool Function()? isHostCatalogAdmin;
}

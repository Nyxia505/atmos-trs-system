import 'package:atmos_trs_system/navigation/guest_startup_routes.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

/// Where to send users after an explicit logout.
///
/// Web returns to the public landing hero; mobile returns to Welcome
/// (onboarding is not shown again).
String get postLogoutRoute =>
    kIsWeb ? '/landing' : GuestStartupRoutes.welcome;

void navigateAfterLogout(BuildContext context) {
  Navigator.of(context, rootNavigator: true).pushNamedAndRemoveUntil(
    postLogoutRoute,
    (route) => false,
  );
}

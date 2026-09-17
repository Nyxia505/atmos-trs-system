import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

/// Where to send users after an explicit logout.
///
/// Web returns to the public landing hero; mobile keeps the dedicated login screen.
String get postLogoutRoute => kIsWeb ? '/landing' : '/login';

void navigateAfterLogout(BuildContext context) {
  Navigator.of(context, rootNavigator: true).pushNamedAndRemoveUntil(
    postLogoutRoute,
    (route) => false,
  );
}

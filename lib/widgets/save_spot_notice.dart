import 'package:atmos_trs_system/config/app_theme.dart';
import 'package:atmos_trs_system/navigation/root_navigator.dart';
import 'package:flutter/material.dart';

/// One orange save/unsave notice. A newer save replaces the previous one,
/// and leaving the screen removes it.
class SaveSpotNotice {
  SaveSpotNotice._();

  static int _token = 0;
  static bool _visible = false;

  static void show(
    BuildContext context,
    String message, {
    bool error = false,
  }) {
    final messenger = ScaffoldMessenger.maybeOf(context);
    if (messenger == null) return;
    final token = ++_token;
    _visible = true;
    messenger
      ..clearSnackBars()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          duration: const Duration(seconds: 2),
          behavior: SnackBarBehavior.floating,
          backgroundColor: error ? Colors.grey.shade700 : AppTheme.primary,
        ),
      ).closed.whenComplete(() {
        if (_token == token) _visible = false;
      });
  }

  static void dismiss([BuildContext? context]) {
    if (!_visible) return;
    _token++;
    _visible = false;
    final resolved = context ?? rootNavigatorKey.currentContext;
    if (resolved == null) return;
    ScaffoldMessenger.maybeOf(resolved)?.clearSnackBars();
  }
}

/// Clears a save notice when the tourist opens or leaves a screen.
class SaveSpotNoticeNavigatorObserver extends NavigatorObserver {
  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (previousRoute == null) return;
    SaveSpotNotice.dismiss(navigator?.context);
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    SaveSpotNotice.dismiss(navigator?.context);
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    SaveSpotNotice.dismiss(navigator?.context);
  }
}

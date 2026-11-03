import 'dart:async';

import 'package:atmos_trs_system/config/app_theme.dart';
import 'package:atmos_trs_system/navigation/root_navigator.dart';
import 'package:flutter/material.dart';

/// One orange save/unsave notice. A newer save replaces the previous one,
/// and leaving the screen removes it.
class SaveSpotNotice {
  SaveSpotNotice._();

  static int _token = 0;
  static bool _visible = false;
  static String? _lastMessage;
  static DateTime? _lastShownAt;
  static Timer? _hideTimer;
  static ScaffoldMessengerState? _messenger;

  static const Duration displayDuration = Duration(seconds: 2);
  static const Duration _duplicateWindow = Duration(milliseconds: 700);

  static void show(
    BuildContext context,
    String message, {
    bool error = false,
  }) {
    final messenger = ScaffoldMessenger.maybeOf(context) ??
        (rootNavigatorKey.currentContext == null
            ? null
            : ScaffoldMessenger.maybeOf(rootNavigatorKey.currentContext!));
    if (messenger == null) return;
    final now = DateTime.now();
    if (!error &&
        message == _lastMessage &&
        _lastShownAt != null &&
        now.difference(_lastShownAt!) < _duplicateWindow) {
      return;
    }
    _lastMessage = message;
    _lastShownAt = now;
    final token = ++_token;
    _visible = true;
    _messenger = messenger;
    _hideTimer?.cancel();
    final padding = MediaQuery.maybeOf(context)?.viewPadding.bottom ?? 0;
    messenger
      ..clearSnackBars()
      ..hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        content: Text(message),
        duration: displayDuration,
        behavior: SnackBarBehavior.floating,
        showCloseIcon: false,
        dismissDirection: DismissDirection.horizontal,
        margin: EdgeInsets.fromLTRB(16, 0, 16, padding + 16),
        backgroundColor: error ? Colors.grey.shade700 : AppTheme.primary,
      ),
    );
    // SnackBar.duration can be ignored (nested messengers / a11y). Force-hide.
    _hideTimer = Timer(displayDuration, () {
      if (_token != token) return;
      _forceHide();
    });
  }

  static void _forceHide() {
    _hideTimer?.cancel();
    _hideTimer = null;
    _visible = false;
    _lastMessage = null;
    try {
      _messenger?.hideCurrentSnackBar();
      _messenger?.clearSnackBars();
    } catch (_) {}
    final root = rootNavigatorKey.currentContext;
    if (root != null) {
      try {
        ScaffoldMessenger.maybeOf(root)?.hideCurrentSnackBar();
        ScaffoldMessenger.maybeOf(root)?.clearSnackBars();
      } catch (_) {}
    }
    _messenger = null;
  }

  @visibleForTesting
  static void resetForTest() {
    _token++;
    _forceHide();
    _lastShownAt = null;
  }

  static void dismiss([BuildContext? context]) {
    if (!_visible && _hideTimer == null) return;
    _token++;
    _forceHide();
    if (context != null) {
      ScaffoldMessenger.maybeOf(context)?.hideCurrentSnackBar();
      ScaffoldMessenger.maybeOf(context)?.clearSnackBars();
    }
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

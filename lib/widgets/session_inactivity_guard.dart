import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:atmos_trs_system/config/auth_config.dart';
import 'package:atmos_trs_system/config/session_storage.dart';

/// Signs the user out after a period without pointer, scroll, or keyboard activity.
/// Intended for shared/public terminals and kiosk-style deployments.
class SessionInactivityGuard extends StatefulWidget {
  const SessionInactivityGuard({
    super.key,
    required this.navigatorKey,
    required this.child,
    this.idleLimit = const Duration(minutes: 30),
  });

  final GlobalKey<NavigatorState> navigatorKey;
  final Widget child;
  final Duration idleLimit;

  @override
  State<SessionInactivityGuard> createState() => _SessionInactivityGuardState();
}

class _SessionInactivityGuardState extends State<SessionInactivityGuard> {
  Timer? _timer;
  StreamSubscription<User?>? _authSub;

  void _cancelTimer() {
    _timer?.cancel();
    _timer = null;
  }

  void _scheduleTimer() {
    if (FirebaseAuth.instance.currentUser == null) {
      _cancelTimer();
      return;
    }
    _cancelTimer();
    _timer = Timer(widget.idleLimit, _onTimeout);
  }

  void _onActivity() {
    if (FirebaseAuth.instance.currentUser != null) {
      _scheduleTimer();
    }
  }

  bool _onKey(KeyEvent event) {
    _onActivity();
    return false;
  }

  Future<void> _onTimeout() async {
    if (FirebaseAuth.instance.currentUser == null) return;
    await FirebaseAuth.instance.signOut();
    await SessionStorage.clearSession();
    AuthConfig.currentUserUid = null;
    final nav = widget.navigatorKey.currentState;
    if (nav == null || !nav.mounted) return;
    nav.pushNamedAndRemoveUntil('/login', (route) => false);
  }

  @override
  void initState() {
    super.initState();
    HardwareKeyboard.instance.addHandler(_onKey);
    _authSub = FirebaseAuth.instance.authStateChanges().listen((user) {
      if (user != null) {
        _scheduleTimer();
      } else {
        _cancelTimer();
      }
    });
    if (FirebaseAuth.instance.currentUser != null) {
      _scheduleTimer();
    }
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_onKey);
    _authSub?.cancel();
    _cancelTimer();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: (_) => _onActivity(),
      onPointerSignal: (_) => _onActivity(),
      child: widget.child,
    );
  }
}

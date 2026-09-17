import 'dart:async' show StreamSubscription, Timer, unawaited;

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:atmos_trs_system/config/auth_config.dart';
import 'package:atmos_trs_system/config/session_storage.dart';
import 'package:atmos_trs_system/navigation/post_logout_navigation.dart';

/// Signs tourists out after a period without pointer, scroll, or keyboard activity.
///
/// Governor and LGU (tourism) staff dashboards are excluded — only end-user/tourist
/// sessions auto-logout for security on shared devices.
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
    _timer = Timer(widget.idleLimit, () => unawaited(_onTimeout()));
  }

  /// Staff dashboards stay signed in; tourists get idle timeout.
  Future<bool> _isStaffAccount() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return false;

    final storedUid = await SessionStorage.getStoredUser();
    if (storedUid == user.uid) {
      final role = await SessionStorage.getStoredRole();
      if (role == UserRole.governor ||
          role == UserRole.tourism ||
          role == UserRole.provincialTourism) {
        return true;
      }
    }

    final emailRole = SessionStorage.getRoleFromEmail(user.email ?? '');
    return SessionStorage.isStaffRole(emailRole);
  }

  Future<void> _evaluateInactivityPolicy() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      _cancelTimer();
      return;
    }
    if (await _isStaffAccount()) {
      _cancelTimer();
      return;
    }
    _scheduleTimer();
  }

  void _onActivity() {
    if (FirebaseAuth.instance.currentUser == null) return;
    unawaited(_evaluateInactivityPolicy());
  }

  bool _onKey(KeyEvent event) {
    _onActivity();
    return false;
  }

  Future<void> _onTimeout() async {
    if (FirebaseAuth.instance.currentUser == null) return;
    if (await _isStaffAccount()) return;
    await FirebaseAuth.instance.signOut();
    await SessionStorage.clearSession();
    AuthConfig.currentUserUid = null;
    final nav = widget.navigatorKey.currentState;
    if (nav == null || !nav.mounted) return;
    nav.pushNamedAndRemoveUntil(postLogoutRoute, (route) => false);
  }

  @override
  void initState() {
    super.initState();
    HardwareKeyboard.instance.addHandler(_onKey);
    _authSub = FirebaseAuth.instance.authStateChanges().listen((user) {
      unawaited(_evaluateInactivityPolicy());
    });
    unawaited(_evaluateInactivityPolicy());
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

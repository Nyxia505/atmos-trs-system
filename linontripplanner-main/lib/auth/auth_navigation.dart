import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../admin_dashboard_screen.dart';
import '../home_screen.dart';
import '../services/reports/reports_service.dart';
import '../services/tourism_session.dart';
import '../trip_plan_host_bridge.dart';
import '../widgets/admin_access_gate.dart';
import 'login_screen.dart';
import 'registration_form_cache.dart';
import 'registration_screen.dart';

/// Light fade + slide transition for auth screens (feels instant on mobile).
Route<T> authSlideRoute<T>(Widget page) {
  return PageRouteBuilder<T>(
    pageBuilder: (_, _, _) => page,
    transitionDuration: const Duration(milliseconds: 200),
    reverseTransitionDuration: const Duration(milliseconds: 180),
    transitionsBuilder: (_, animation, _, child) {
      final curved = CurvedAnimation(
        parent: animation,
        curve: Curves.easeOutCubic,
        reverseCurve: Curves.easeInCubic,
      );
      return FadeTransition(
        opacity: curved,
        child: SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(0.03, 0),
            end: Offset.zero,
          ).animate(curved),
          child: child,
        ),
      );
    },
  );
}

void pushRegistrationScreen(BuildContext context) {
  RegistrationFormCache.warmUp();
  Navigator.of(context).push(
    authSlideRoute(const RegistrationScreen()),
  );
}

void pushLoginScreen(BuildContext context) {
  Navigator.of(context).pushReplacement(
    authSlideRoute(const LoginScreen()),
  );
}

/// Confirm sign-out, clear session data, and open the login screen.
///
/// Optimized for speed: clears local user/admin state, signs out Auth with a
/// short timeout, and navigates immediately — no catalog reload on the way out.
Future<void> performTourismLogout(BuildContext context) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Logout'),
      content: Text(
        TripPlanHostBridge.embeddedInAtmos
            ? 'Sign out of Trip Planner and ATMOS TRS?'
            : 'Sign out and return to the login screen?',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(ctx, true),
          child: Text(
            'Logout',
            style: TextStyle(color: Colors.red.shade400),
          ),
        ),
      ],
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    ),
  );
  if (confirmed != true || !context.mounted) return;

  // Drop user-specific memory first so UI cannot flash prior-account data.
  clearTourismSessionOnLogout();
  ReportsService.invalidateCache();

  // Don't block logout on a slow Auth network round-trip.
  try {
    await FirebaseAuth.instance
        .signOut()
        .timeout(const Duration(milliseconds: 1500));
  } catch (_) {
    unawaited(FirebaseAuth.instance.signOut());
  }

  if (!context.mounted) return;
  if (TripPlanHostBridge.embeddedInAtmos) {
    try {
      await TripPlanHostBridge.onSignedOut?.call();
    } catch (_) {}
    if (!context.mounted) return;
    final leave = TripPlanHostBridge.leaveToHost;
    if (leave != null) {
      leave(context);
      return;
    }
    Navigator.of(context).popUntil((route) => route.isFirst);
    return;
  }
  Navigator.of(context).pushAndRemoveUntil(
    authSlideRoute(const LoginScreen()),
    (_) => false,
  );
}

/// After sign-in: admins → dashboard; everyone else → app home ([TourismAuthGate]).
void navigateAfterSuccessfulLogin(
  BuildContext context, {
  required bool openAdminDashboard,
}) {
  if (openAdminDashboard) {
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute<void>(
        builder: (_) => const AdminAccessGate(
          child: AdminDashboardScreen(),
        ),
      ),
      (_) => false,
    );
    return;
  }
  // Tourist / regular user → home ([LoginScreen] is often embedded, not a navigator route).
  Navigator.of(context).pushAndRemoveUntil(
    MaterialPageRoute<void>(
      builder: (_) => const HomeScreen(),
    ),
    (_) => false,
  );
}

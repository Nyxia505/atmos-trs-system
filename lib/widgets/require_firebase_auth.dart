import 'package:atmos_trs_system/config/auth_config.dart';
import 'package:atmos_trs_system/navigation/post_logout_navigation.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

/// Blocks dashboard screens unless Firebase Auth currently has a signed-in user.
/// Direct `/dashboard` URLs with no session return to login / landing.
class RequireFirebaseAuth extends StatelessWidget {
  const RequireFirebaseAuth({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      initialData: FirebaseAuth.instance.currentUser,
      builder: (context, snapshot) {
        // Prefer the live Auth user over a transient null stream event so a
        // brief authStateChanges emission cannot bounce dashboards to Landing.
        final user = FirebaseAuth.instance.currentUser ?? snapshot.data;
        if (user != null) {
          AuthConfig.currentUserUid = user.uid;
          return child;
        }
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!context.mounted) return;
          // Re-check at callback time — Auth may have finished restoring.
          if (FirebaseAuth.instance.currentUser != null) return;
          Navigator.of(context, rootNavigator: true).pushNamedAndRemoveUntil(
            postLogoutRoute,
            (route) => false,
          );
        });
        return const Scaffold(
          body: Center(child: CircularProgressIndicator()),
        );
      },
    );
  }
}

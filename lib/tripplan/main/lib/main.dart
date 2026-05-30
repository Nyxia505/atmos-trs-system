import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import 'auth/login_screen.dart';
import 'home_screen.dart';

/// Auth gate: login screen or TripPlan home after Firebase sign-in.
class TourismAuthGate extends StatelessWidget {
  const TourismAuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        if (snapshot.hasData && snapshot.data != null) {
          return const HomeScreen();
        }
        return const LoginScreen();
      },
    );
  }
}

import 'package:flutter/material.dart';

import '../data.dart';
import 'login_screen.dart';

class RegistrationScreen extends StatelessWidget {
  const RegistrationScreen({super.key});

  static const String routeName = '/register';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Create account')),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TripPlanAssets.logoImage(height: 64),
              const SizedBox(height: 16),
              const Text(
                'Use your ATMOS TRS tourist account to access TripPlan.',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 20),
              FilledButton(
                onPressed: () {
                  Navigator.pushReplacementNamed(context, LoginScreen.routeName);
                },
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.primary,
                ),
                child: const Text('Back to sign in'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

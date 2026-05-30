import 'package:flutter/material.dart';

import 'data.dart';

class TripPlannerPage extends StatelessWidget {
  const TripPlannerPage({super.key});

  static const String routeName = '/trip-planner';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Trip planner'),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
      ),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TripPlanAssets.logoImage(height: 48),
            const SizedBox(height: 16),
            const Text(
              'Build your day-by-day route across Misamis Occidental.',
              style: TextStyle(fontSize: 16),
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: () => Navigator.pop(context),
              icon: const Icon(Icons.arrow_back_rounded),
              label: const Text('Back to dashboard'),
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.primary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

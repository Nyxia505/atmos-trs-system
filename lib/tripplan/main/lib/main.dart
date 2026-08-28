import 'package:flutter/material.dart';
import 'package:trip_plan/data.dart';

/// TripPlan sign-in gate (placeholder until full module sources are restored).
class TourismAuthGate extends StatelessWidget {
  const TourismAuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        title: const Text('TripPlan'),
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.map_outlined,
                size: 64,
                color: AppColors.primary.withValues(alpha: 0.8),
              ),
              const SizedBox(height: 16),
              const Text(
                'TripPlan module',
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF111827),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'The tourism TripPlan app source files are not in this '
                'workspace yet. ATMOS-TRS will still run; restore the full '
                'trip_plan lib folder to enable maps, itineraries, and admin.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 14,
                  height: 1.45,
                  color: Colors.grey.shade700,
                ),
              ),
              const SizedBox(height: 24),
              FilledButton(
                onPressed: () => Navigator.maybePop(context),
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.primary,
                ),
                child: const Text('Back to ATMOS'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import 'admin_dashboard_screen.dart';
import 'data.dart';
import 'trip_planner_page.dart';
import 'trip_plan_fonts.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    final compact = MediaQuery.sizeOf(context).width < 600;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        title: Row(
          children: [
            TripPlanAssets.logoImage(height: 36),
            const SizedBox(width: 10),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'TripPlan',
                  style: TextStyle(
                    fontFamily: TripPlanFonts.branding,
                    color: AppColors.primary,
                    fontSize: compact ? 26 : 34,
                    height: 0.95,
                  ),
                ),
                Text(
                  'Misamis Occidental',
                  style: TextStyle(
                    fontSize: compact ? 11 : 12,
                    color: Colors.grey.shade700,
                  ),
                ),
              ],
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Sign out',
            onPressed: () => FirebaseAuth.instance.signOut(),
            icon: const Icon(Icons.logout_rounded),
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Hello, ${user?.email?.split('@').first ?? 'traveler'}',
              style: const TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 8),
            const Text('Plan routes, map LGUs, and organize your visit.'),
            const SizedBox(height: 24),
            _ActionCard(
              icon: Icons.map_rounded,
              title: 'Open trip planner',
              subtitle: 'Build your itinerary',
              onTap: () {
                Navigator.pushNamed(context, TripPlannerPage.routeName);
              },
            ),
            const SizedBox(height: 12),
            _ActionCard(
              icon: Icons.admin_panel_settings_outlined,
              title: 'Admin dashboard',
              subtitle: 'Tourism staff only',
              onTap: () {
                Navigator.pushNamed(context, AdminDashboardScreen.routeName);
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _ActionCard extends StatelessWidget {
  const _ActionCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: AppColors.primary),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 16,
                      ),
                    ),
                    Text(
                      subtitle,
                      style: TextStyle(color: Colors.grey.shade600),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right_rounded),
            ],
          ),
        ),
      ),
    );
  }
}

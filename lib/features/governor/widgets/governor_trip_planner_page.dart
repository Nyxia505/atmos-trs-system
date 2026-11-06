import 'package:flutter/material.dart';
import 'package:trip_plan/admin_announcements_tab.dart';
import 'package:trip_plan/admin_dashboard_screen.dart';
import 'package:trip_plan/admin_matrix_fares_tab.dart';

/// One Trip Planner tool. The sidebar chooses which page is visible.
enum GovernorTripPlannerSection { featured, events, fares }

class GovernorTripPlannerPage extends StatelessWidget {
  const GovernorTripPlannerPage({super.key, required this.section});

  final GovernorTripPlannerSection section;

  @override
  Widget build(BuildContext context) {
    return switch (section) {
      GovernorTripPlannerSection.featured =>
        const AdminFeaturedSpotsTab(onChanged: _noop),
      GovernorTripPlannerSection.events =>
        const AdminAnnouncementsTab(onChanged: _noop),
      GovernorTripPlannerSection.fares => const AdminMatrixFaresTab(),
    };
  }
}

void _noop() {}

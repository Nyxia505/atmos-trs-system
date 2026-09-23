import 'package:atmos_trs_system/navigation/pending_checkin_navigation.dart';
import 'package:flutter/material.dart';

/// Completes a pending camera-QR check-in when the tourist is already signed in.
class QrPendingResumeScreen extends StatefulWidget {
  const QrPendingResumeScreen({super.key});

  @override
  State<QrPendingResumeScreen> createState() => _QrPendingResumeScreenState();
}

class _QrPendingResumeScreenState extends State<QrPendingResumeScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _run());
  }

  Future<void> _run() async {
    if (!mounted) return;
    await navigateToPendingSpotCheckInOrDashboard(
      context,
      defaultRoute: '/dashboard',
      isTouristDestination: true,
      preferLandingAfterPendingCheckIn: false,
    );
  }

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(child: CircularProgressIndicator()),
    );
  }
}

import 'package:atmos_trs_system/config/app_store_links.dart';
import 'package:atmos_trs_system/config/app_theme.dart';
import 'package:atmos_trs_system/navigation/landing_intent_navigation.dart';
import 'package:atmos_trs_system/navigation/pending_checkin_navigation.dart';
import 'package:atmos_trs_system/services/pending_lgu_checkin_storage.dart';
import 'package:atmos_trs_system/services/pending_spot_checkin_storage.dart';
import 'package:atmos_trs_system/widgets/vr_download_app_prompt.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

/// After a QR scan and tourist sign-in: destination choices, not an automatic check-in.
class QrPendingResumeScreen extends StatefulWidget {
  const QrPendingResumeScreen({super.key});

  @override
  State<QrPendingResumeScreen> createState() => _QrPendingResumeScreenState();
}

class _QrPendingResumeScreenState extends State<QrPendingResumeScreen> {
  String _place = 'this destination';
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final spot = await PendingSpotCheckInStorage.peek();
    final lgu = await PendingLguCheckInStorage.peek();
    final name = spot?.spotName?.trim().isNotEmpty == true
        ? spot!.spotName!.trim()
        : (lgu?.displayName.trim().isNotEmpty == true
            ? lgu!.displayName.trim()
            : 'this destination');
    if (!mounted) return;
    setState(() {
      _place = name;
      _loading = false;
    });
  }

  Future<void> _openVr() async {
    final allowed = await VrDownloadAppPrompt.ensureAllowed(context);
    if (!allowed || !mounted) return;
    await tryOpenAtmosAppWithPendingQr();
  }

  Future<void> _openItinerary() async {
    if (kHasTripPlannerApkDownload) {
      final uri = Uri.tryParse(kTripPlannerApkDownloadUrl);
      if (uri != null) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      }
      return;
    }
    if (!mounted) return;
    final openHere = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Trip Planner app'),
        content: const Text(
          'The Trip Planner APK download link is not configured yet. '
          'You can open Trip Planner in this site with your tourist account.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Not now'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Open here'),
          ),
        ],
      ),
    );
    if (openHere == true && mounted) {
      await LandingIntentNavigation.openPlanner(context);
    }
  }

  Future<void> _checkIn() async {
    await navigateToPendingSpotCheckInOrDashboard(
      context,
      defaultRoute: '/qr-resume',
      isTouristDestination: true,
      preferLandingAfterPendingCheckIn: false,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        backgroundColor: AppTheme.brandOrange,
        foregroundColor: Colors.white,
        title: const Text('Your destination'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(20, 24, 20, 32),
              children: [
                Text(
                  'Welcome to $_place',
                  style: const TextStyle(
                    fontSize: 26,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF0F172A),
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Choose VR Tour or Trip Planner. Scanning this code does not '
                  'check you in. Check-in still asks for your location.',
                  style: TextStyle(
                    fontSize: 15,
                    height: 1.4,
                    color: Color(0xFF475569),
                  ),
                ),
                const SizedBox(height: 24),
                _ActionCard(
                  icon: Icons.vrpano_rounded,
                  title: 'VR Tour',
                  subtitle: kHasAndroidApkDownload
                      ? 'Download the ATMOS TRS app for VR'
                      : 'ATMOS TRS app download is not configured',
                  onTap: _openVr,
                ),
                const SizedBox(height: 12),
                _ActionCard(
                  icon: Icons.map_rounded,
                  title: 'Trip Planner',
                  subtitle: kHasTripPlannerApkDownload
                      ? 'Download the Trip Planner app'
                      : 'APK link must be configured — open it here instead',
                  onTap: _openItinerary,
                ),
                const SizedBox(height: 12),
                _ActionCard(
                  icon: Icons.qr_code_scanner_rounded,
                  title: 'Check in here',
                  subtitle: 'Uses location. Only records a visit when you are at the spot.',
                  onTap: _checkIn,
                ),
              ],
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
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Icon(icon, color: AppTheme.brandOrange, size: 32),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        fontSize: 13,
                        height: 1.35,
                        color: Color(0xFF64748B),
                      ),
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

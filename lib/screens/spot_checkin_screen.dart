import 'package:flutter/material.dart';
import 'package:atmos_trs_system/config/app_theme.dart';
import 'package:atmos_trs_system/services/qr_checkin_service.dart';
import 'package:atmos_trs_system/services/qr_checkin_ui.dart';
import 'package:atmos_trs_system/services/user_activity_service.dart' as activity;

/// Check-in page for a Firestore [SpotInfo] after QR scan (logged-in flow).
class SpotCheckInScreen extends StatefulWidget {
  const SpotCheckInScreen({
    super.key,
    required this.spotInfo,
  });

  final SpotInfo spotInfo;

  @override
  State<SpotCheckInScreen> createState() => _SpotCheckInScreenState();
}

class _SpotCheckInScreenState extends State<SpotCheckInScreen> {
  static const Color _textDark = Color(0xFF111827);
  bool _submitting = false;

  Future<void> _checkIn() async {
    if (_submitting) return;
    setState(() => _submitting = true);
    final s = widget.spotInfo;

    final locationError = await QRCheckInService.verifyProximityToTouristSpot(
      latitude: s.latitude ?? 0,
      longitude: s.longitude ?? 0,
      spotLabel: s.spotName.isNotEmpty ? s.spotName : s.spotId,
    );
    if (!mounted) return;
    if (locationError != null) {
      setState(() => _submitting = false);
      showQRCheckInErrorDialog(context, locationError);
      return;
    }

    final ok = await performQRCheckIn(
      context,
      municipalityId: s.municipalityId,
      spotId: s.spotId,
      spotName: s.spotName.isNotEmpty ? s.spotName : null,
      municipality: s.municipality.isNotEmpty ? s.municipality : null,
    );
    if (ok) {
      final spotDisplay = s.spotName.isNotEmpty ? s.spotName : s.spotId;
      await activity.UserActivityService.addVisit(
        spotId: s.spotId,
        spotName: spotDisplay,
        category: 'Spot',
      );
    }
    if (mounted) setState(() => _submitting = false);
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.spotInfo;
    final title = s.spotName.isNotEmpty ? s.spotName : s.spotId.replaceAll('_', ' ');
    return Scaffold(
      backgroundColor: AppTheme.scaffoldBackground,
      appBar: AppBar(
        title: const Text('Register visit'),
        backgroundColor: AppTheme.cardBackground,
        foregroundColor: _textDark,
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () {
            Navigator.pushReplacementNamed(context, '/dashboard');
          },
        ),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Icon(Icons.place_rounded, size: 56, color: AppTheme.primary),
              const SizedBox(height: 16),
              Text(
                title,
                style: const TextStyle(
                  color: _textDark,
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                ),
              ),
              if (s.municipality.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(
                  s.municipality,
                  style: TextStyle(color: AppTheme.unselectedMuted, fontSize: 15),
                ),
              ],
              const SizedBox(height: 24),
              Text(
                'Tap Register visit to record your visit at this location.',
                style: TextStyle(color: AppTheme.unselectedMuted, fontSize: 15, height: 1.4),
              ),
              const Spacer(),
              FilledButton.icon(
                onPressed: _submitting ? null : _checkIn,
                style: FilledButton.styleFrom(
                  backgroundColor: AppTheme.primary,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                icon: _submitting
                    ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      )
                    : const Icon(Icons.check_circle_outline),
                label: Text(_submitting ? 'Saving…' : 'Register visit'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

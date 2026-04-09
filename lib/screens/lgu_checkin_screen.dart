import 'package:flutter/material.dart';
import 'package:atmos_trs_system/config/app_theme.dart';
import 'package:atmos_trs_system/services/qr_checkin_ui.dart';
import 'package:atmos_trs_system/services/user_activity_service.dart' as activity;
import 'package:atmos_trs_system/utils/municipality_helper.dart';

/// Check-in after scanning an LGU (municipality) QR — records visit for that LGU in [qr_checkins].
class LguCheckInScreen extends StatefulWidget {
  const LguCheckInScreen({
    super.key,
    required this.municipalityId,
    required this.displayName,
  });

  final String municipalityId;
  final String displayName;

  @override
  State<LguCheckInScreen> createState() => _LguCheckInScreenState();
}

class _LguCheckInScreenState extends State<LguCheckInScreen> {
  static const Color _textDark = Color(0xFF111827);
  bool _submitting = false;

  Future<void> _checkIn() async {
    if (_submitting) return;
    setState(() => _submitting = true);
    final mid = normalizeMunicipalityId(widget.municipalityId);
    final spotId = 'lgu_$mid';
    final spotName = 'LGU visit — ${widget.displayName}';
    final ok = await performQRCheckIn(
      context,
      municipalityId: mid,
      spotId: spotId,
      spotName: spotName,
      municipality: widget.displayName,
    );
    if (ok) {
      await activity.UserActivityService.addVisit(
        spotId: spotId,
        spotName: spotName,
        category: 'LGU',
      );
    }
    if (mounted) setState(() => _submitting = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.scaffoldBackground,
      appBar: AppBar(
        title: const Text('Check-in'),
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
              Icon(Icons.qr_code_2_rounded, size: 56, color: AppTheme.primary),
              const SizedBox(height: 16),
              Text(
                widget.displayName,
                style: const TextStyle(
                  color: _textDark,
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Municipality check-in',
                style: TextStyle(color: AppTheme.unselectedMuted, fontSize: 15),
              ),
              const SizedBox(height: 24),
              Text(
                'You scanned this LGU’s QR code. Tap Check-in to record your visit in '
                '${widget.displayName}.',
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
                label: Text(_submitting ? 'Saving…' : 'Check-in'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

import 'dart:async' show unawaited;

import 'package:flutter/material.dart';
import 'package:atmos_trs_system/config/app_theme.dart';
import 'package:atmos_trs_system/services/pending_spot_checkin_storage.dart';
import 'package:atmos_trs_system/services/qr_checkin_service.dart';
import 'package:atmos_trs_system/services/qr_checkin_ui.dart';
import 'package:atmos_trs_system/widgets/party_demographic_fields.dart';

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
  final _demoKey = GlobalKey<PartyDemographicFieldsState>();
  PartyDemographicValue _demo = const PartyDemographicValue(
    partySize: 1,
    maleCount: 0,
    femaleCount: 1,
    filipinoCount: 1,
    foreignCount: 0,
  );

  void _clearSubmitting() {
    if (mounted && _submitting) {
      setState(() => _submitting = false);
    }
  }

  Future<void> _leaveForDashboard({bool clearPending = true}) async {
    if (clearPending) {
      await PendingSpotCheckInStorage.clear();
    }
    if (!mounted) return;
    Navigator.pushNamedAndRemoveUntil(context, '/dashboard', (route) => false);
  }

  Future<void> _checkIn() async {
    if (_submitting) return;
    final demo = _demoKey.currentState?.value ?? _demo;
    if (!demo.isValid) {
      showQRCheckInErrorDialog(
        context,
        demo.validationMessage ??
            'Enter party size with Male/Female and Filipino/Foreign counts.',
      );
      return;
    }

    setState(() => _submitting = true);
    try {
      final s = widget.spotInfo;

      final lat = s.latitude;
      final lng = s.longitude;
      final hasCoords = lat != null &&
          lng != null &&
          lat.abs() > 1e-7 &&
          lng.abs() > 1e-7;
      if (hasCoords) {
        final locationError =
            await QRCheckInService.verifyProximityToTouristSpot(
          latitude: lat,
          longitude: lng,
          spotLabel: s.spotName.isNotEmpty ? s.spotName : s.spotId,
        );
        if (!mounted) return;
        if (locationError != null) {
          showQRCheckInErrorDialog(context, locationError);
          return;
        }
      }

      final ok = await performQRCheckIn(
        context,
        municipalityId: s.municipalityId,
        spotId: s.spotId,
        spotName: s.spotName.isNotEmpty ? s.spotName : null,
        municipality: s.municipality.isNotEmpty ? s.municipality : null,
        partySize: demo.partySize,
        femaleCount: demo.femaleCount,
        maleCount: demo.maleCount,
        onBeforeDialog: _clearSubmitting,
      );
      if (ok && mounted) {
        await _leaveForDashboard(clearPending: true);
      }
    } finally {
      _clearSubmitting();
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.spotInfo;
    final title =
        s.spotName.isNotEmpty ? s.spotName : s.spotId.replaceAll('_', ' ');
    return Scaffold(
      backgroundColor: AppTheme.scaffoldBackground,
      appBar: AppBar(
        title: const Text('Register visit'),
        backgroundColor: AppTheme.cardBackground,
        foregroundColor: _textDark,
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => unawaited(_leaveForDashboard(clearPending: false)),
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
                  style:
                      TextStyle(color: AppTheme.unselectedMuted, fontSize: 15),
                ),
              ],
              const SizedBox(height: 24),
              Text(
                'Party size',
                style: TextStyle(
                  color: _textDark,
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Enter total guests, then gender and Filipino/Foreign. '
                'One side auto-fills the other. Include yourself.',
                style: TextStyle(
                  color: AppTheme.unselectedMuted,
                  fontSize: 13,
                ),
              ),
              const SizedBox(height: 12),
              Expanded(
                child: SingleChildScrollView(
                  child: PartyDemographicFields(
                    key: _demoKey,
                    initialPartySize: 1,
                    initialMale: 0,
                    initialFemale: 1,
                    initialFilipino: 1,
                    initialForeign: 0,
                    onChanged: (v) => setState(() => _demo = v),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: _submitting ? null : _checkIn,
                style: FilledButton.styleFrom(
                  backgroundColor: AppTheme.primary,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                icon: _submitting
                    ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
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

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:atmos_trs_system/config/app_theme.dart';
import 'package:atmos_trs_system/services/qr_checkin_service.dart';
import 'package:atmos_trs_system/services/qr_checkin_ui.dart';

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
  final TextEditingController _partyController =
      TextEditingController(text: '1');
  final TextEditingController _femaleController =
      TextEditingController(text: '0');
  final TextEditingController _maleController =
      TextEditingController(text: '0');

  int _parseCount(TextEditingController c, {int fallback = 0}) {
    final n = int.tryParse(c.text.trim());
    if (n == null || n < 0) return fallback;
    return n > 99 ? 99 : n;
  }

  int get _partySize {
    final n = _parseCount(_partyController, fallback: 1);
    return n < 1 ? 1 : n;
  }

  int get _femaleCount => _parseCount(_femaleController);
  int get _maleCount => _parseCount(_maleController);

  @override
  void dispose() {
    _partyController.dispose();
    _femaleController.dispose();
    _maleController.dispose();
    super.dispose();
  }

  Future<void> _checkIn() async {
    if (_submitting) return;
    if (_femaleCount + _maleCount != _partySize) {
      showQRCheckInErrorDialog(
        context,
        'Female + male must equal total party ($_partySize).',
      );
      return;
    }

    setState(() => _submitting = true);
    final s = widget.spotInfo;

    final lat = s.latitude;
    final lng = s.longitude;
    final hasCoords = lat != null &&
        lng != null &&
        lat.abs() > 1e-7 &&
        lng.abs() > 1e-7;
    if (hasCoords) {
      final locationError = await QRCheckInService.verifyProximityToTouristSpot(
        latitude: lat,
        longitude: lng,
        spotLabel: s.spotName.isNotEmpty ? s.spotName : s.spotId,
      );
      if (!mounted) return;
      if (locationError != null) {
        setState(() => _submitting = false);
        showQRCheckInErrorDialog(context, locationError);
        return;
      }
    }

    await performQRCheckIn(
      context,
      municipalityId: s.municipalityId,
      spotId: s.spotId,
      spotName: s.spotName.isNotEmpty ? s.spotName : null,
      municipality: s.municipality.isNotEmpty ? s.municipality : null,
      partySize: _partySize,
      femaleCount: _femaleCount,
      maleCount: _maleCount,
      onBeforeDialog: () {
        if (mounted && _submitting) {
          setState(() => _submitting = false);
        }
      },
    );
    if (mounted && _submitting) {
      setState(() => _submitting = false);
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
                'Enter total guests, then female and male. Include yourself.',
                style: TextStyle(
                  color: AppTheme.unselectedMuted,
                  fontSize: 13,
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _partyController,
                keyboardType: TextInputType.number,
                onChanged: (_) => setState(() {}),
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                  LengthLimitingTextInputFormatter(2),
                ],
                decoration: InputDecoration(
                  labelText: 'Total party',
                  hintText: 'e.g. 5',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _femaleController,
                      keyboardType: TextInputType.number,
                      onChanged: (_) => setState(() {}),
                      inputFormatters: [
                        FilteringTextInputFormatter.digitsOnly,
                        LengthLimitingTextInputFormatter(2),
                      ],
                      decoration: InputDecoration(
                        labelText: 'Female',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextField(
                      controller: _maleController,
                      keyboardType: TextInputType.number,
                      onChanged: (_) => setState(() {}),
                      inputFormatters: [
                        FilteringTextInputFormatter.digitsOnly,
                        LengthLimitingTextInputFormatter(2),
                      ],
                      decoration: InputDecoration(
                        labelText: 'Male',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                'Total: $_partySize ($_femaleCount female · $_maleCount male)',
                style: TextStyle(
                  color: AppTheme.primary,
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                ),
              ),
              const Spacer(),
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

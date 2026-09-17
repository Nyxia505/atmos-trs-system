import 'dart:async' show unawaited;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:atmos_trs_system/config/app_theme.dart';
import 'package:atmos_trs_system/config/app_theme_controller.dart';
import 'package:atmos_trs_system/config/atmos_brand_typography.dart';
import 'package:atmos_trs_system/services/qr_checkin_ui.dart';
import 'package:atmos_trs_system/utils/municipality_helper.dart';
import 'package:atmos_trs_system/services/pending_lgu_checkin_storage.dart';

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
  static const Color _textMuted = Color(0xFF6B7280);
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

  void _clearSubmitting() {
    if (mounted && _submitting) {
      setState(() => _submitting = false);
    }
  }

  @override
  void dispose() {
    _partyController.dispose();
    _femaleController.dispose();
    _maleController.dispose();
    super.dispose();
  }

  Future<void> _leaveForDashboard({bool clearPending = true}) async {
    if (clearPending) {
      await PendingLguCheckInStorage.clear();
    }
    if (!mounted) return;
    Navigator.pushNamedAndRemoveUntil(context, '/dashboard', (route) => false);
  }

  void _goBack() {
    if (Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
    } else {
      unawaited(_leaveForDashboard());
    }
  }

  Future<void> _checkIn() async {
    if (_submitting) return;
    if (_femaleCount + _maleCount != _partySize) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Female + male must equal total party ($_partySize).',
            ),
            behavior: SnackBarBehavior.floating,
            backgroundColor: Colors.red.shade700,
          ),
        );
      }
      return;
    }
    setState(() => _submitting = true);
    try {
      final mid = normalizeMunicipalityId(widget.municipalityId);
      if (mid.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Invalid municipality ID for this QR code.'),
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
        return;
      }

      final spotId = 'lgu_$mid';
      final spotName = 'LGU visit — ${widget.displayName}';
      final ok = await performQRCheckIn(
        context,
        municipalityId: mid,
        spotId: spotId,
        spotName: spotName,
        municipality: widget.displayName,
        partySize: _partySize,
        femaleCount: _femaleCount,
        maleCount: _maleCount,
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
    return ListenableBuilder(
      listenable: AppThemeController.instance,
      builder: (context, _) {
        final accent = AppTheme.primary;
        final accentLight = AppTheme.primaryLight;
        final accentDark = AppTheme.primaryDark;
        final onAccent = AppTheme.onPrimary;

        return Scaffold(
          backgroundColor: const Color(0xFFF8FAFC),
          body: Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  accent.withValues(alpha: 0.08),
                  const Color(0xFFF8FAFC),
                  const Color(0xFFFFFFFF),
                ],
                stops: const [0.0, 0.35, 1.0],
              ),
            ),
            child: SafeArea(
              child: Column(
                children: [
                  _buildTopBar(accent),
                  Expanded(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _buildHeroCard(accent, accentLight, accentDark),
                          const SizedBox(height: 16),
                          _buildPartySizeCard(accent),
                        ],
                      ),
                    ),
                  ),
                  _buildBottomAction(accent, accentLight, accentDark, onAccent),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildTopBar(Color accent) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 4, 16, 4),
      child: Row(
        children: [
          IconButton(
            onPressed: _goBack,
            icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
            color: _textDark,
            tooltip: 'Back',
          ),
          const Spacer(),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: accent.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: accent.withValues(alpha: 0.25)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.qr_code_scanner_rounded, size: 16, color: accent),
                const SizedBox(width: 6),
                Text(
                  'LGU Check-in',
                  style: TextStyle(
                    color: accent,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.2,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeroCard(Color accent, Color accentLight, Color accentDark) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: accent.withValues(alpha: 0.22)),
        boxShadow: [
          BoxShadow(
            color: accent.withValues(alpha: 0.12),
            blurRadius: 24,
            offset: const Offset(0, 10),
          ),
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 22),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [accentLight, accentDark],
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: accent.withValues(alpha: 0.28),
                        blurRadius: 10,
                        offset: const Offset(0, 3),
                      ),
                    ],
                  ),
                  child: const Icon(
                    Icons.qr_code_scanner_rounded,
                    color: Colors.white,
                    size: 28,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 5,
                        ),
                        decoration: BoxDecoration(
                          color: accent.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          'Municipality check-in',
                          style: TextStyle(
                            color: accent,
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.3,
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        widget.displayName,
                        style: AtmosBrandTypography.displayTitle(
                          color: _textDark,
                          fontSize: 26,
                          letterSpacing: 0.3,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Text(
              'Tap Register visit to save your check-in in ${widget.displayName}.',
              style: const TextStyle(
                color: _textMuted,
                fontSize: 14,
                height: 1.5,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPartySizeCard(Color accent) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Party size',
            style: TextStyle(
              color: _textDark,
              fontSize: 16,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            'Enter total guests, then female and male. Include yourself.',
            style: TextStyle(color: _textMuted, fontSize: 13, height: 1.4),
          ),
          const SizedBox(height: 12),
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
              color: accent,
              fontWeight: FontWeight.w700,
              fontSize: 13,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBottomAction(
    Color accent,
    Color accentLight,
    Color accentDark,
    Color onAccent,
  ) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 16,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextButton(
            onPressed:
                _submitting ? null : () => unawaited(_leaveForDashboard()),
            child: const Text(
              'Skip for now — go to dashboard',
              style: TextStyle(
                color: Color(0xFF6B7280),
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(height: 4),
          Material(
            color: Colors.transparent,
            borderRadius: BorderRadius.circular(16),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: _submitting ? null : _checkIn,
              borderRadius: BorderRadius.circular(16),
              child: Ink(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [accentLight, accent, accentDark],
                  ),
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: accent.withValues(alpha: 0.35),
                      blurRadius: 14,
                      offset: const Offset(0, 5),
                    ),
                  ],
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      if (_submitting)
                        SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.5,
                            color: onAccent,
                          ),
                        )
                      else
                        Icon(Icons.check_circle_rounded,
                            color: onAccent, size: 22),
                      const SizedBox(width: 10),
                      Text(
                        _submitting ? 'Saving visit…' : 'Register visit',
                        style: TextStyle(
                          color: onAccent,
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.2,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

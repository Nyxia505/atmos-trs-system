import 'dart:async' show unawaited;

import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:atmos_trs_system/config/app_theme.dart';
import 'package:atmos_trs_system/models/tourist_group.dart';
import 'package:atmos_trs_system/services/pending_spot_checkin_storage.dart';
import 'package:atmos_trs_system/services/qr_checkin_service.dart';
import 'package:atmos_trs_system/services/qr_checkin_ui.dart';
import 'package:atmos_trs_system/services/qr_location_prompt.dart';
import 'package:atmos_trs_system/services/tourist_group_service.dart';
import 'package:atmos_trs_system/widgets/laag_group_checkin_toggle.dart';
import 'package:atmos_trs_system/widgets/party_demographic_fields.dart';
import 'package:atmos_trs_system/widgets/spot_image.dart';

/// Check-in page for a Firestore [SpotInfo] after QR scan (logged-in flow).
class SpotCheckInScreen extends StatefulWidget {
  const SpotCheckInScreen({
    super.key,
    required this.spotInfo,
    this.isDemoQr = false,
  });

  final SpotInfo spotInfo;

  /// Dummy QR: skips the on-site GPS check.
  final bool isDemoQr;

  @override
  State<SpotCheckInScreen> createState() => _SpotCheckInScreenState();
}

class _SpotCheckInScreenState extends State<SpotCheckInScreen> {
  static const Color _textDark = Color(0xFF111827);
  bool _submitting = false;
  var _demoKey = GlobalKey<PartyDemographicFieldsState>();
  PartyDemographicValue _demo = const PartyDemographicValue(
    partySize: 1,
    maleCount: 0,
    femaleCount: 1,
    filipinoCount: 1,
    foreignCount: 0,
  );
  TouristGroup? _group;
  bool _useGroup = true;

  bool get _groupMode =>
      _useGroup &&
      _group != null &&
      _group!.isLeader(FirebaseAuth.instance.currentUser?.uid ?? '');

  @override
  void initState() {
    super.initState();
    unawaited(_loadGroup());
  }

  Future<void> _loadGroup() async {
    final g = await TouristGroupService.myActiveGroup();
    if (!mounted || g == null) return;
    setState(() {
      _group = g;
      if (_groupMode) {
        _demo = kNoCompanions;
        _demoKey = GlobalKey<PartyDemographicFieldsState>();
      }
    });
  }

  void _setUseGroup(bool v) {
    setState(() {
      _useGroup = v;
      _demo = _groupMode ? kNoCompanions : kSoloParty;
      _demoKey = GlobalKey<PartyDemographicFieldsState>();
    });
  }

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
      final hasCoords =
          lat != null && lng != null && lat.abs() > 1e-7 && lng.abs() > 1e-7;
      if (hasCoords && !widget.isDemoQr) {
        final ready = await ensureQrLocationReady(
          context,
          spotLabel: s.spotName.isNotEmpty ? s.spotName : s.spotId,
        );
        if (!ready || !mounted) return;
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
        filipinoCount: demo.filipinoCount,
        foreignCount: demo.foreignCount,
        group: _groupMode ? _group : null,
        isDemoQr: widget.isDemoQr,
        onBeforeDialog: _clearSubmitting,
      );
      if (ok && mounted) {
        await _leaveForDashboard(clearPending: true);
      }
    } finally {
      _clearSubmitting();
    }
  }

  void _goBack() {
    final nav = Navigator.of(context);
    if (nav.canPop()) {
      nav.pop();
    } else {
      unawaited(_leaveForDashboard(clearPending: false));
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.spotInfo;
    final title = s.spotName.isNotEmpty
        ? s.spotName
        : s.spotId.replaceAll('_', ' ');
    final barBg = AppTheme.cardBackground;
    final barFg = ThemeData.estimateBrightnessForColor(barBg) == Brightness.dark
        ? Colors.white
        : _textDark;
    return Scaffold(
      backgroundColor: AppTheme.scaffoldBackground,
      appBar: AppBar(
        title: const Text('Register visit'),
        backgroundColor: barBg,
        foregroundColor: barFg,
        iconTheme: IconThemeData(color: barFg),
        titleTextStyle: TextStyle(
          color: barFg,
          fontSize: 18,
          fontWeight: FontWeight.w700,
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          tooltip: 'Back',
          onPressed: _goBack,
        ),
      ),
      body: SafeArea(
        top: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _buildSpotHeader(s, title),
                    if (_group != null) ...[
                      const SizedBox(height: 16),
                      LaagGroupCheckInToggle(
                        group: _group!,
                        isLeader: _group!.isLeader(
                          FirebaseAuth.instance.currentUser?.uid ?? '',
                        ),
                        enabled: _useGroup,
                        onChanged: _setUseGroup,
                      ),
                    ],
                    const SizedBox(height: 24),
                    Text(
                      _groupMode ? 'Companions without the app' : 'Party size',
                      style: TextStyle(
                        color: _textDark,
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _groupMode
                          ? kCompanionsHelpText
                          : 'Enter total guests, then gender and Filipino/Foreign. '
                              'One side auto-fills the other. Include yourself.',
                      style: TextStyle(
                        color: AppTheme.unselectedMuted,
                        fontSize: 13,
                      ),
                    ),
                    const SizedBox(height: 12),
                    PartyDemographicFields(
                      key: _demoKey,
                      initialPartySize: _demo.partySize,
                      initialMale: _demo.maleCount,
                      initialFemale: _demo.femaleCount,
                      initialFilipino: _demo.filipinoCount,
                      initialForeign: _demo.foreignCount,
                      minPartySize: _groupMode ? 0 : 1,
                      partyLabel: _groupMode ? 'Companions' : 'Party size',
                      partyHelperText: _groupMode
                          ? 'People with you who don\'t have the app (0 if none)'
                          : 'Total guests in this stay / visit',
                      onChanged: (v) => setState(() => _demo = v),
                    ),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
              child: FilledButton.icon(
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
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSpotHeader(SpotInfo s, String title) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: SizedBox(
        height: 200,
        child: Stack(
          fit: StackFit.expand,
          children: [
            SpotImage(
              imageUrl: s.imageUrl,
              spotId: s.spotId,
              municipalityId: s.municipalityId,
              spotName: title,
              category: s.category,
              fit: BoxFit.cover,
            ),
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  stops: const [0.35, 1.0],
                  colors: [
                    Colors.transparent,
                    Colors.black.withValues(alpha: 0.75),
                  ],
                ),
              ),
            ),
            Positioned(
              left: 16,
              right: 16,
              bottom: 14,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: AppTheme.primary,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.qr_code_scanner_rounded,
                          size: 14,
                          color: Colors.white,
                        ),
                        SizedBox(width: 6),
                        Text(
                          'You scanned',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                      height: 1.2,
                    ),
                  ),
                  if (s.municipality.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        const Icon(
                          Icons.place_rounded,
                          size: 15,
                          color: Colors.white70,
                        ),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            s.municipality,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.white70,
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

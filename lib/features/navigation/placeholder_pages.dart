import 'package:flutter/foundation.dart' show debugPrint, kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show HapticFeedback;
import 'dart:async';
import 'dart:convert';
import 'package:atmos_trs_system/screens/vr_webview_screen.dart';
import 'package:atmos_trs_system/widgets/vr_download_app_prompt.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart' show FirebaseAuth;
import 'package:atmos_trs_system/config/app_theme.dart';
import 'package:atmos_trs_system/models/tourist_group.dart';
import 'package:atmos_trs_system/screens/laag_with_friends_screen.dart';
import 'package:atmos_trs_system/services/tourist_group_service.dart';
import 'package:atmos_trs_system/widgets/ui_skeleton.dart';
import 'package:atmos_trs_system/config/app_theme_controller.dart';
import 'package:atmos_trs_system/config/auth_config.dart';
import 'package:atmos_trs_system/config/session_storage.dart';
import 'package:atmos_trs_system/config/vr_tour_config.dart';
import 'package:atmos_trs_system/features/navigation/tourist_web_layout.dart';
import 'package:atmos_trs_system/services/qr_checkin_ui.dart';
import 'package:atmos_trs_system/services/qr_checkin_service.dart';
import 'package:atmos_trs_system/services/qr_location_prompt.dart';
import 'package:atmos_trs_system/services/nearby_spot_service.dart';
import 'package:atmos_trs_system/services/qr_scan_demo_guard.dart';
import 'package:atmos_trs_system/services/pending_spot_checkin_storage.dart';
import 'package:atmos_trs_system/services/pending_lgu_checkin_storage.dart';
import 'package:atmos_trs_system/screens/spot_checkin_screen.dart';
import 'package:atmos_trs_system/screens/lgu_checkin_screen.dart';
import 'package:atmos_trs_system/screens/event_detail_screen.dart';
import 'package:atmos_trs_system/services/announcement_notification_sync.dart';
import 'package:atmos_trs_system/widgets/spot_image.dart';
import 'package:atmos_trs_system/services/notification_badge_notifier.dart';
import 'package:atmos_trs_system/services/notification_firestore_service.dart';
import 'package:atmos_trs_system/services/user_activity_service.dart'
    as activity;
import 'package:atmos_trs_system/models/notification_item.dart';
import 'package:atmos_trs_system/config/beta_testing_config.dart';
import 'package:atmos_trs_system/config/qr_scan_geofence_config.dart';
import 'package:atmos_trs_system/data/misamis_occidental_municipalities.dart';
import 'package:atmos_trs_system/services/qr_scan_location_guard.dart';
import 'package:atmos_trs_system/utils/municipality_helper.dart';
import 'package:atmos_trs_system/utils/spot_qr_helper.dart';
import 'package:shared_preferences/shared_preferences.dart';

export 'package:atmos_trs_system/features/profile/profile_tab_page.dart';

/// Placeholder for nav tabs (Home, Scan, Alerts) until real screens exist.
class PlaceholderNavPage extends StatelessWidget {
  const PlaceholderNavPage({
    super.key,
    required this.title,
    required this.icon,
  });

  final String title;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.scaffoldBackground,
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 64, color: AppTheme.primary),
            const SizedBox(height: 16),
            Text(
              title,
              style: const TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Coming soon',
              style: TextStyle(color: AppTheme.unselectedMuted, fontSize: 14),
            ),
          ],
        ),
      ),
    );
  }
}

/// Placeholder for "See All" destinations (navigated from home).
/// When [places] is provided (e.g. Misamis Occidental list), shows that list.
class SeeAllPage extends StatelessWidget {
  const SeeAllPage({super.key, this.places});

  /// Optional list of place names (e.g. municipalities & cities). When null, shows placeholder.
  final List<String>? places;

  @override
  Widget build(BuildContext context) {
    final showList = places != null && places!.isNotEmpty;
    return Scaffold(
      backgroundColor: AppTheme.scaffoldBackground,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text(
          showList ? 'Misamis Occidental' : 'All Destinations',
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      body: showList
          ? _buildPlacesList(context)
          : Center(
              child: Text(
                'Full list coming soon. Connect Firebase to load destinations.',
                style: TextStyle(color: AppTheme.unselectedMuted, fontSize: 14),
                textAlign: TextAlign.center,
              ),
            ),
    );
  }

  Widget _buildPlacesList(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 16),
          child: Text(
            'Municipalities & Cities',
            style: TextStyle(
              color: Colors.white.withOpacity(0.7),
              fontSize: 14,
            ),
          ),
        ),
        ...places!.map((name) {
          final isCity = name.endsWith(' City');
          return Card(
            margin: const EdgeInsets.only(bottom: 8),
            color: Colors.white.withOpacity(0.08),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            child: ListTile(
              leading: Icon(
                isCity ? Icons.location_city : Icons.place,
                color: AppTheme.primary,
                size: 22,
              ),
              title: Text(
                name,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w500,
                  fontSize: 15,
                ),
              ),
              trailing: Icon(
                Icons.chevron_right,
                color: Colors.white.withOpacity(0.5),
              ),
            ),
          );
        }),
      ],
    );
  }
}

/// Opens Oroquieta City Plaza Teleport360 (same helper as spot detail).
class VrTourPlaceholderPage extends StatelessWidget {
  const VrTourPlaceholderPage({super.key});

  @override
  Widget build(BuildContext context) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!context.mounted) return;
      Navigator.of(context).pop();
      openVrTour(
        context,
        url: kOroquietaCityPlazaVrUrl,
        title: 'Oroquieta City Plaza',
      );
    });
    return const Scaffold(body: Center(child: CircularProgressIndicator()));
  }
}

// -----------------------------------------------------------------------------
// Bottom nav tab placeholders (ATMOS TRS)
// -----------------------------------------------------------------------------

/// Explore tab: map + municipalities (placeholder content; use MisamisOccidentalScreen in shell).
class ExploreTabPage extends StatelessWidget {
  const ExploreTabPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.scaffoldBackground,
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.explore_rounded, size: 64, color: AppTheme.primary),
            const SizedBox(height: 16),
            const Text(
              'Explore',
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Map + municipalities',
              style: TextStyle(color: AppTheme.unselectedMuted, fontSize: 14),
            ),
          ],
        ),
      ),
    );
  }
}

/// Scan tab: real QR scanner using [mobile_scanner]. Opens camera, scans tourist spot QR codes,
/// looks up spot in Firestore, and saves check-in to qr_checkins.
///
/// Set [guestMode] when opened from the landing page (no account yet): after scanning an LGU or
/// spot QR, the user sees the QR welcome screen, then the landing page (check-in deferred).
class ScanTabPage extends StatefulWidget {
  const ScanTabPage({super.key, this.guestMode = false});

  /// True when launched before sign-in (e.g. from landing). Shows a back button and routes
  /// unauthenticated scans to `/qr-welcome` instead of a dialog.
  final bool guestMode;

  @override
  State<ScanTabPage> createState() => _ScanTabPageState();
}

class _ScanTabPageState extends State<ScanTabPage> with WidgetsBindingObserver {
  static const String _kAllowedMunicipalityId = 'oroquieta';

  final MobileScannerController _controller = MobileScannerController(
    detectionSpeed: DetectionSpeed.normal,
    facing: CameraFacing.back,
    torchEnabled: false,
    autoStart: false,
  );

  /// Cooldown to avoid duplicate scans (e.g. same code detected many times in a few seconds).
  static const Duration _scanCooldown = Duration(seconds: 3);

  /// Same QR text is ignored for longer so one code never creates two records.
  static const Duration _sameCodeCooldown = Duration(seconds: 6);
  DateTime? _lastScanAt;
  String? _lastScanRaw;
  bool _isProcessing = false;
  String _processingLabel = 'Saving check-in...';
  bool _isStartingCamera = false;
  bool _resultRouteOpen = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _startCamera();
    unawaited(_warmLocationForScan());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.resumed:
        if (!_resultRouteOpen) unawaited(_startCamera());
      case AppLifecycleState.inactive:
      case AppLifecycleState.hidden:
      case AppLifecycleState.paused:
        unawaited(_stopCamera());
      case AppLifecycleState.detached:
        break;
    }
  }

  Future<void> _stopCamera() async {
    try {
      await _controller.stop();
    } catch (e) {
      debugPrint('ScanTabPage: camera stop error: $e');
    }
  }

  /// Opens a result screen with the camera released, then resumes scanning.
  Future<T?> _pushResult<T>(Widget screen) async {
    _resultRouteOpen = true;
    unawaited(_stopCamera());
    try {
      return await Navigator.push<T>(
        context,
        MaterialPageRoute<T>(builder: (_) => screen),
      );
    } finally {
      _resultRouteOpen = false;
      if (mounted) {
        _lastScanAt = DateTime.now();
        unawaited(_startCamera());
      }
    }
  }

  /// Reads GPS while the camera starts so the scan itself doesn't wait for it.
  Future<void> _warmLocationForScan() async {
    if (QrScanLocationGuard.isBypassed || !QrScanLocationGuard.isPhone) return;
    try {
      if (await QrScanLocationGuard.checkReadiness() != null) return;
    } catch (_) {
      return;
    }
    await QrScanLocationGuard.prewarm();
  }

  Future<void> _startCamera({bool restart = false}) async {
    if (_isStartingCamera || !mounted) return;
    if (!restart && _controller.value.isRunning) return;
    _isStartingCamera = true;
    try {
      if (restart) await _controller.stop();
      await _controller.start();
    } catch (e) {
      debugPrint('ScanTabPage: camera start error: $e');
      if (mounted) setState(() {});
    } finally {
      _isStartingCamera = false;
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    unawaited(_controller.dispose());
    super.dispose();
  }

  void _clearProcessing() {
    if (!mounted) return;
    setState(() {
      _isProcessing = false;
      _processingLabel = 'Saving check-in...';
    });
  }

  void _onDetect(BarcodeCapture capture) {
    if (_isProcessing) return;
    // Scan tab stays alive under IndexedStack; ignore detects while a result
    // route (wait / receipt / check-in) is on top.
    if (ModalRoute.of(context)?.isCurrent != true) return;
    final barcodes = capture.barcodes;
    if (barcodes.isEmpty) return;
    final raw = barcodes.first.rawValue?.trim();
    if (raw == null || raw.isEmpty) return;
    final now = DateTime.now();
    if (_lastScanAt != null) {
      final since = now.difference(_lastScanAt!);
      if (since < _scanCooldown) return;
      if (raw == _lastScanRaw && since < _sameCodeCooldown) return;
    }
    _lastScanAt = now;
    _lastScanRaw = raw;
    HapticFeedback.selectionClick();
    setState(() {
      _isProcessing = true;
      _processingLabel = 'Reading QR…';
    });
    unawaited(_processScannedPayload(raw));
  }

  Future<void> _processScannedPayload(String raw) async {
    try {
      // Try tourist QR: {"type":"tourist","tourist_id":"..."}
      final touristId = _tryParseTouristQr(raw);
      if (touristId != null && touristId.isNotEmpty) {
        await _handleTouristQrScanned(touristId);
        return;
      }

      final groupQr = TouristGroup.parseQrPayload(raw);
      if (groupQr != null) {
        await _handleGroupQrScanned(groupQr.groupId, groupQr.code);
        return;
      }

      if (isScreenPreviewQr(raw)) {
        if (mounted) _showError(QrScanMessages.screenQr);
        return;
      }
      final isDemoQr = isDemoQrPayload(raw);

      if (parseEstablishmentQrPayload(raw) != null) {
        if (mounted) _showError(kRetiredEstablishmentQrMessage);
        return;
      }

      final lguPayload = parseLguQrPayload(raw);
      if (lguPayload != null) {
        if (mounted) {
          setState(() => _processingLabel = 'Saving check-in…');
        }
        await _handleLguQrScanned(lguPayload, isDemoQr: isDemoQr);
        return;
      }

      if (mounted) {
        setState(() => _processingLabel = 'Saving check-in…');
      }

      final spotPayload = parseSpotCheckInPayload(raw);
      final String spotId;
      final String? municipalityIdFromQr;
      final double? qrEmbedLat;
      final double? qrEmbedLng;
      if (spotPayload != null && spotPayload.spotId.isNotEmpty) {
        spotId = spotPayload.spotId;
        municipalityIdFromQr = spotPayload.municipalityId;
        qrEmbedLat = spotPayload.qrLat;
        qrEmbedLng = spotPayload.qrLng;
      } else {
        final deepSpotId = extractSpotIdFromCheckInDeepLink(raw);
        if (deepSpotId != null && deepSpotId.isNotEmpty) {
          spotId = deepSpotId;
          municipalityIdFromQr = null;
          qrEmbedLat = null;
          qrEmbedLng = null;
        } else {
          final parsed = parseSpotQrPayload(raw);
          spotId = parsed.spotId;
          municipalityIdFromQr = parsed.municipalityId;
          qrEmbedLat = null;
          qrEmbedLng = null;
        }
      }

      if (spotId.isEmpty || !_looksLikeSpotId(spotId)) {
        if (mounted) _showError(QrScanMessages.notCheckInQr);
        return;
      }

      if (kQrCheckInOroquietaOnly &&
          !BetaTestingGuard.bypassValidation &&
          !isDemoQr &&
          municipalityIdFromQr != null &&
          municipalityIdFromQr!.trim().isNotEmpty &&
          normalizeMunicipalityId(municipalityIdFromQr!) !=
              _kAllowedMunicipalityId) {
        if (mounted) {
          _showError(
            'For now, QR check-in is available in Oroquieta City only. '
            'Please scan an Oroquieta QR code.',
          );
        }
        return;
      }

      if (mounted) {
        setState(() => _processingLabel = 'Finding tourist spot…');
      }
      SpotInfo? spot = await QRCheckInService.getSpotById(
        spotId,
        municipalityId: municipalityIdFromQr,
      ).timeout(const Duration(seconds: 10), onTimeout: () => null);
      if (spot == null) {
        // Allow "unlisted" check-ins for Oroquieta even if the spot isn't registered in Firestore.
        // This supports scans from web/images or prints not yet added to Tourist Spots.
        final mid = normalizeMunicipalityId(
          municipalityIdFromQr ?? _kAllowedMunicipalityId,
        );
        if (!BetaTestingGuard.bypassValidation &&
            !isDemoQr &&
            mid != _kAllowedMunicipalityId) {
          if (mounted) {
            _showError(
              'Tourist spot not found. Use a valid ATMOS-TRS spot QR code.',
            );
          }
          return;
        }
        spot = SpotInfo(
          spotId: spotId,
          spotName: spotId.replaceAll('_', ' ').trim(),
          municipality: BetaTestingGuard.isActive
              ? BetaTestingGuard.dashboardMunicipalityName
              : _municipalityDisplayName(mid),
          municipalityId: BetaTestingGuard.isActive
              ? BetaTestingGuard.dashboardMunicipalityId
              : mid,
        );
      }
      // Continue existing spot flow below — inlined continuation via goto pattern.
      await _finishSpotCheckInFromScan(
        spot: spot,
        municipalityIdFromQr: municipalityIdFromQr,
        qrEmbedLat: qrEmbedLat,
        qrEmbedLng: qrEmbedLng,
        spotId: spotId,
        isDemoQr: isDemoQr,
      );
    } catch (e, st) {
      debugPrint('[Scan] payload failed: $e\n$st');
      if (mounted) _showError(friendlyQrScanError(e));
    } finally {
      _clearProcessing();
    }
  }

  /// Plain spot ids are Firestore doc ids (slugs); rejects URLs / random text.
  static final RegExp _spotIdPattern = RegExp(r'^[A-Za-z0-9_\-]{2,120}$');

  bool _looksLikeSpotId(String id) => _spotIdPattern.hasMatch(id.trim());

  /// Re-reads a device-cached spot from Firestore and returns it only when the
  /// LGU has since moved its coordinates, so a stale copy never blocks a scan.
  Future<SpotInfo?> _freshSpotIfMoved(SpotInfo spot) async {
    final oldLat = spot.latitude;
    final oldLng = spot.longitude;
    if (!spot.fromCache || oldLat == null || oldLng == null) return null;
    final fresh = await QRCheckInService.getSpotById(
      spot.spotId,
      preferCache: false,
    ).timeout(const Duration(seconds: 8), onTimeout: () => null);
    final lat = fresh?.latitude;
    final lng = fresh?.longitude;
    if (fresh == null || lat == null || lng == null) return null;
    final moved =
        QrScanLocationGuard.distanceMeters(lat, lng, oldLat, oldLng) > 1;
    return moved ? fresh : null;
  }

  Future<void> _finishSpotCheckInFromScan({
    required SpotInfo spot,
    required String spotId,
    String? municipalityIdFromQr,
    double? qrEmbedLat,
    double? qrEmbedLng,
    bool isDemoQr = false,
  }) async {
    final municipalityId = spot.municipalityId;
    final spotName = spot.spotName;
    final municipality = spot.municipality;
    if (municipalityId.isEmpty) {
      if (mounted) {
        _showError(
          'This spot has no municipality set. Ask the tourism office to update it.',
        );
      }
      return;
    }

    final demoSpotMsg = QrScanDemoGuard.municipalityRestrictionMessage(
      municipalityId,
    );
    if (demoSpotMsg != null) {
      if (mounted) _showDemoRestrictionSnack(demoSpotMsg);
      return;
    }

    final slat = spot.latitude;
    final slng = spot.longitude;
    final hasCoords =
        slat != null && slng != null && slat.abs() > 1e-7 && slng.abs() > 1e-7;
    final uid = await QRCheckInService.getCurrentUserId();
    final isGuestSpotScan = uid == null || uid.isEmpty;

    if (hasCoords &&
        !isGuestSpotScan &&
        !isDemoQr &&
        !BetaTestingGuard.bypassValidation) {
      final qrMismatchError =
          QRCheckInService.verifyQrCoordinatesMatchFirestore(
            qrLat: qrEmbedLat,
            qrLng: qrEmbedLng,
            firestoreLat: slat,
            firestoreLng: slng,
          );
      if (qrMismatchError != null) {
        final fresh = await _freshSpotIfMoved(spot);
        if (fresh != null) {
          return _finishSpotCheckInFromScan(
            spot: fresh,
            spotId: spotId,
            municipalityIdFromQr: municipalityIdFromQr,
            qrEmbedLat: qrEmbedLat,
            qrEmbedLng: qrEmbedLng,
            isDemoQr: isDemoQr,
          );
        }
        if (mounted) _showError(qrMismatchError);
        return;
      }

      final label = spotName.isNotEmpty ? spotName : spotId;
      if (!mounted) return;
      if (!await ensureQrLocationReady(context, spotLabel: label)) return;
      if (mounted) {
        setState(() => _processingLabel = 'Checking your location…');
      }

      final spotLocationError =
          await QRCheckInService.verifyProximityToTouristSpot(
            latitude: slat,
            longitude: slng,
            spotLabel: spotName.isNotEmpty ? spotName : spotId,
          );
      if (spotLocationError != null) {
        final fresh = await _freshSpotIfMoved(spot);
        if (fresh != null) {
          return _finishSpotCheckInFromScan(
            spot: fresh,
            spotId: spotId,
            municipalityIdFromQr: municipalityIdFromQr,
            qrEmbedLat: qrEmbedLat,
            qrEmbedLng: qrEmbedLng,
            isDemoQr: isDemoQr,
          );
        }
        if (mounted) _showError(spotLocationError);
        return;
      }
    }

    if (uid == null || uid.isEmpty) {
      final routed = BetaTestingGuard.applyCheckInRouting(
        municipalityId: municipalityId,
        municipality: municipality.isNotEmpty ? municipality : '',
        spotId: spotId,
        spotName: spotName.isNotEmpty ? spotName : spotId,
      );
      await PendingLguCheckInStorage.clear();
      await PendingSpotCheckInStorage.save(
        municipalityId: routed.municipalityId,
        spotId: routed.spotId,
        spotName: routed.spotName,
        municipality: routed.municipality,
        isDemoQr: isDemoQr,
      );
      if (!mounted) return;
      Navigator.of(
        context,
        rootNavigator: true,
      ).pushReplacementNamed('/qr-welcome');
      return;
    }

    if (!mounted) return;
    await _pushResult<void>(
      SpotCheckInScreen(spotInfo: spot, isDemoQr: isDemoQr),
    );
  }

  void _showError(String message) {
    showQRCheckInErrorDialog(context, message);
  }

  /// Friend's "Laag with Friends" group QR → confirm and join.
  Future<void> _handleGroupQrScanned(String groupId, String code) async {
    if (FirebaseAuth.instance.currentUser == null) {
      if (mounted) {
        _showError('Please log in first, then scan your friend\'s group QR.');
      }
      return;
    }
    if (mounted) setState(() => _processingLabel = 'Finding group…');
    final group = await TouristGroupService.findByQr(groupId, code);
    if (!mounted) return;
    if (group == null || !group.isActive) {
      _showError(
        'This group QR has ended or is not valid. Ask your friend to show '
        'their current group QR.',
      );
      return;
    }
    _clearProcessing();
    await confirmJoinTouristGroup(context, group);
  }

  String _municipalityDisplayName(String municipalityId) {
    for (final m in getMisamisOccidentalMunicipalities()) {
      if (m.id == municipalityId) return m.name;
    }
    return municipalityId;
  }

  void _showDemoRestrictionSnack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        duration: const Duration(seconds: 5),
        behavior: SnackBarBehavior.floating,
        backgroundColor: Colors.amber.shade800,
      ),
    );
  }

  Future<void> _handleLguQrScanned(
    LguQrPayload payload, {
    bool isDemoQr = false,
  }) async {
    final municipalityId = payload.municipalityId;

    if (kQrCheckInOroquietaOnly &&
        !BetaTestingGuard.bypassValidation &&
        !isDemoQr &&
        normalizeMunicipalityId(municipalityId) != _kAllowedMunicipalityId) {
      if (mounted) {
        _showError(
          'For now, QR check-in is available in Oroquieta City only. '
          'Please scan an Oroquieta QR code.',
        );
      }
      _clearProcessing();
      return;
    }

    final demoLguMsg = QrScanDemoGuard.municipalityRestrictionMessage(
      municipalityId,
    );
    if (demoLguMsg != null) {
      if (mounted) _showDemoRestrictionSnack(demoLguMsg);
      _clearProcessing();
      return;
    }

    String displayName = municipalityId;
    for (final m in getMisamisOccidentalMunicipalities()) {
      if (m.id == municipalityId) {
        displayName = m.name;
        break;
      }
    }

    final double anchorLat;
    final double anchorLng;
    final double maxDistanceMeters;
    if (payload.hasEmbeddedAnchor) {
      anchorLat = payload.anchorLat!;
      anchorLng = payload.anchorLng!;
      maxDistanceMeters = kQrScanLguAnchoredMaxDistanceMeters;
    } else {
      final coords = getMunicipalityAnchorCoordinates(municipalityId);
      if (coords == null) {
        if (mounted) {
          _showError('Unknown municipality for this QR code.');
        }
        _clearProcessing();
        return;
      }
      anchorLat = coords.lat;
      anchorLng = coords.lng;
      maxDistanceMeters = kQrScanLguCenterMaxDistanceMeters;
    }

    final uid = await QRCheckInService.getCurrentUserId();
    final isGuestScan = uid == null || uid.isEmpty;
    // Guests register from anywhere; their location is checked after sign-up
    // (PendingCheckinCompletionService). Logged-in users are checked now.
    if (!isGuestScan && !isDemoQr && !BetaTestingGuard.bypassValidation) {
      if (!mounted) return;
      if (!await ensureQrLocationReady(context, spotLabel: displayName)) {
        _clearProcessing();
        return;
      }
      final lguLocationError = await QrScanLocationGuard.verifyNearAnchor(
        anchorLat: anchorLat,
        anchorLng: anchorLng,
        maxDistanceMeters: maxDistanceMeters,
        spotLabel: displayName,
      );
      if (lguLocationError != null) {
        if (mounted) _showError(lguLocationError);
        _clearProcessing();
        return;
      }
    }

    final routedLguId = municipalityId;
    final routedLguName = displayName;

    if (uid != null && uid.isNotEmpty) {
      if (!mounted) return;
      await _pushResult<void>(
        LguCheckInScreen(
          municipalityId: routedLguId,
          displayName: routedLguName,
          isDemoQr: isDemoQr,
        ),
      );
      return;
    }

    await PendingSpotCheckInStorage.clear();
    await PendingLguCheckInStorage.save(
      municipalityId: routedLguId,
      displayName: routedLguName,
      anchorLat: payload.hasEmbeddedAnchor ? payload.anchorLat : null,
      anchorLng: payload.hasEmbeddedAnchor ? payload.anchorLng : null,
      isDemoQr: isDemoQr,
    );

    if (!mounted) return;
    Navigator.of(
      context,
      rootNavigator: true,
    ).pushReplacementNamed('/qr-welcome');
  }

  /// Parses JSON tourist QR payload. Returns tourist_id if type is "tourist", else null.
  String? _tryParseTouristQr(String raw) {
    try {
      final decoded = jsonDecode(raw) as dynamic;
      if (decoded is! Map) return null;
      final map = decoded as Map<String, dynamic>;
      if (map['type'] != 'tourist') return null;
      final id = map['tourist_id'];
      return id is String ? id : id?.toString();
    } catch (_) {
      return null;
    }
  }

  /// Fetches tourist from Firestore by Firebase UID and shows a dialog with their info.
  Future<void> _handleTouristQrScanned(String touristId) async {
    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('tourists')
          .where('firebaseUid', isEqualTo: touristId)
          .limit(1)
          .get();
      if (!mounted) return;
      if (snapshot.docs.isEmpty) {
        _showError('Tourist not found. No profile for this QR code.');
        _clearProcessing();
        return;
      }
      final data = snapshot.docs.first.data();
      final firstName = data['firstName'] as String? ?? '';
      final lastName = data['lastName'] as String? ?? '';
      final middleName = data['middleName'] as String?;
      final email = data['email'] as String? ?? '';
      final mobile = data['mobile'] as String? ?? '';
      final country = data['country'] as String? ?? '';
      final city = data['city'] as String? ?? '';
      String fullName =
          '$firstName ${middleName != null && middleName.isNotEmpty ? '${middleName[0]}.' : ''} $lastName'
              .trim();
      if (fullName.isEmpty) fullName = email.isNotEmpty ? email : 'Unknown';
      showTouristDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Tourist QR scanned'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '$fullName',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                if (email.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(email, style: TextStyle(color: Colors.grey.shade700)),
                ],
                if (mobile.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(mobile),
                ],
                if (city.isNotEmpty || country.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text('${city.isNotEmpty ? '$city, ' : ''}$country'),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('OK'),
            ),
          ],
        ),
      );
    } catch (e) {
      if (mounted) _showError(friendlyQrScanError(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.scaffoldBackground,
      body: SafeArea(
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
              color: AppTheme.cardBackground,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      if (widget.guestMode)
                        IconButton(
                          icon: const Icon(
                            Icons.arrow_back_rounded,
                            color: Color(0xFF111827),
                          ),
                          onPressed: () => Navigator.of(context).pop(),
                          tooltip: 'Back',
                        ),
                      Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: AppTheme.primary.withValues(alpha: 0.12),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          Icons.qr_code_scanner_rounded,
                          color: AppTheme.primary,
                          size: 22,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          widget.guestMode
                              ? 'Scan LGU or spot QR'
                              : 'QR Check-in',
                          style: const TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF111827),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            Expanded(
              child: ClipRRect(
                borderRadius: const BorderRadius.vertical(
                  bottom: Radius.circular(16),
                ),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    MobileScanner(
                      controller: _controller,
                      onDetect: _onDetect,
                      errorBuilder: (context, error) =>
                          _buildCameraError(error),
                    ),
                    Center(
                      child: Container(
                        width: 240,
                        height: 240,
                        decoration: BoxDecoration(
                          border: Border.all(
                            color: AppTheme.primary.withOpacity(0.8),
                            width: 3,
                          ),
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: const SizedBox.expand(),
                      ),
                    ),
                    if (_isProcessing)
                      Container(
                        color: Colors.black54,
                        child: Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              CircularProgressIndicator(
                                color: AppTheme.primary,
                              ),
                              const SizedBox(height: 16),
                              Text(
                                _processingLabel,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 16,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                widget.guestMode
                    ? 'Scan a municipality QR (e.g. Oroquieta) or a spot QR. '
                          'You will register or sign in, then finish check-in.'
                    : QrScanDemoGuard.isDemoActive
                    ? 'Demo: use Oroquieta City spot or LGU QR (camera or laptop webcam).'
                    : NearbySpotService.nearby.firstOrNull?.spot.name
                              .trim()
                              .isNotEmpty ==
                          true
                    ? 'You\'re near ${NearbySpotService.nearby.first.spot.name.trim()}. '
                          'Scan its official QR code to check in.'
                    : 'Align the QR inside the frame to check in. '
                          'Keep Location on — check-in works only at the '
                          'tourist spot.',
                style: TextStyle(color: AppTheme.unselectedMuted, fontSize: 14),
                textAlign: TextAlign.center,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCameraError(MobileScannerException error) {
    final isPermission =
        error.errorCode == MobileScannerErrorCode.permissionDenied;
    final isUnsupported = error.errorCode == MobileScannerErrorCode.unsupported;
    final title = isPermission
        ? 'Camera permission required'
        : isUnsupported
        ? 'Camera not available'
        : 'Camera could not start';
    final body = isPermission
        ? (kIsWeb
              ? 'Allow camera access in your browser (tap the camera icon in the '
                    'address bar), then tap Try again.'
              : 'Allow camera access for ATMOS in your phone Settings, then tap '
                    'Try again.')
        : isUnsupported
        ? 'This device or browser has no usable camera. Try another device, '
              'or scan the QR with your phone camera app.'
        : 'Close other apps that may be using the camera, then tap Try again.';
    return Container(
      color: AppTheme.scaffoldBackground,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                isPermission ? Icons.camera_alt_outlined : Icons.error_outline,
                size: 64,
                color: AppTheme.primary,
              ),
              const SizedBox(height: 16),
              Text(
                title,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF111827),
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                body,
                style: TextStyle(color: AppTheme.unselectedMuted, fontSize: 14),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              FilledButton.icon(
                onPressed: () => _startCamera(restart: true),
                icon: const Icon(Icons.refresh, size: 20),
                label: const Text('Try again'),
                style: FilledButton.styleFrom(
                  backgroundColor: AppTheme.primary,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: 14,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(24),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Filters for [AlertsTabPage] notification list.
enum _AlertsFilter { all, unread, announcements, activity }

String _formatNotificationRelativeTime(DateTime at) {
  final now = DateTime.now();
  final diff = now.difference(at);
  if (diff.inMinutes < 1) return 'Just now';
  if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
  if (diff.inHours < 24) return '${diff.inHours}h ago';
  if (diff.inDays < 7) return '${diff.inDays}d ago';
  return '${at.day}/${at.month}/${at.year}';
}

class _NotificationVisual {
  const _NotificationVisual({
    required this.icon,
    required this.color,
    required this.label,
  });

  final IconData icon;
  final Color color;
  final String label;
}

_NotificationVisual _notificationVisualFor(NotificationItem item) {
  if (item.isAnnouncement) {
    final type = item.type.toLowerCase();
    if (type == 'alert') {
      return const _NotificationVisual(
        icon: Icons.warning_amber_rounded,
        color: Color(0xFFDC2626),
        label: 'Alert',
      );
    }
    if (type == 'event') {
      return const _NotificationVisual(
        icon: Icons.event_rounded,
        color: Color(0xFFDB2777),
        label: 'Event',
      );
    }
    if (type == 'promo') {
      return const _NotificationVisual(
        icon: Icons.local_offer_rounded,
        color: Color(0xFF059669),
        label: 'Promo',
      );
    }
    return const _NotificationVisual(
      icon: Icons.campaign_rounded,
      color: Color(0xFF7C3AED),
      label: 'Announcement',
    );
  }

  final type = item.type.toLowerCase();
  if (type == 'welcome') {
    return _NotificationVisual(
      icon: Icons.waving_hand_rounded,
      color: AppTheme.primary,
      label: 'Welcome',
    );
  }
  if (type == 'checkin') {
    return const _NotificationVisual(
      icon: Icons.place_rounded,
      color: Color(0xFF059669),
      label: 'Check-in',
    );
  }
  return _NotificationVisual(
    icon: Icons.notifications_rounded,
    color: AppTheme.primary,
    label: 'Update',
  );
}

IconData _filterIcon(_AlertsFilter f) {
  switch (f) {
    case _AlertsFilter.all:
      return Icons.inbox_rounded;
    case _AlertsFilter.unread:
      return Icons.mark_email_unread_rounded;
    case _AlertsFilter.announcements:
      return Icons.campaign_rounded;
    case _AlertsFilter.activity:
      return Icons.history_rounded;
  }
}

/// Notification tab: user notifications (welcome, check-in) + announcements (promos, events).
/// Uses Firestore collections: notifications (user-specific), announcements (general).
class AlertsTabPage extends StatefulWidget {
  const AlertsTabPage({super.key});

  /// Last loaded list, kept across rebuilds (web remounts the tab on every
  /// switch) so reopening the tab paints instantly while it refreshes quietly.
  static String? _cacheUid;
  static List<NotificationItem>? _cache;
  static String? _inflightUid;
  static Future<List<NotificationItem>>? _inflight;

  static List<NotificationItem>? _cachedFor(String? uid) =>
      uid != null && uid == _cacheUid ? _cache : null;

  static void _remember(String? uid, List<NotificationItem> items) {
    if (uid == null || uid.isEmpty) return;
    _cacheUid = uid;
    _cache = List<NotificationItem>.from(items);
  }

  /// Single shared fetch so a prefetch and the tab opening do not both hit
  /// Firestore.
  static Future<List<NotificationItem>> _fetch(String? uid) {
    final running = _inflight;
    if (running != null && _inflightUid == uid) return running;
    final future = _runFetch(uid);
    _inflightUid = uid;
    _inflight = future;
    return future;
  }

  static Future<List<NotificationItem>> _runFetch(String? uid) async {
    try {
      final list = await AnnouncementNotificationSync.loadAlertItems(
        userId: uid,
      );
      _remember(uid, list);
      return list;
    } finally {
      _inflight = null;
      _inflightUid = null;
    }
  }

  /// Warms the notifications list in the background after sign-in.
  static Future<void> prefetch() async {
    try {
      final uid =
          AuthConfig.currentUserUid ?? await SessionStorage.getStoredUser();
      if (uid == null || uid.isEmpty) return;
      await _fetch(uid);
    } catch (e) {
      debugPrint('AlertsTabPage.prefetch: $e');
    }
  }

  @override
  State<AlertsTabPage> createState() => _AlertsTabPageState();
}

class _AlertsTabPageState extends State<AlertsTabPage> {
  List<NotificationItem> _items = [];
  bool _loading = false;
  bool _markingAll = false;
  String? _errorMessage;
  _AlertsFilter _filter = _AlertsFilter.all;
  Timer? _refreshTimer;
  bool _tabVisible = true;
  bool _quietLoadInFlight = false;
  String? _itemsUid;

  @override
  void initState() {
    super.initState();
    final uid = AuthConfig.currentUserUid;
    final cached = AlertsTabPage._cachedFor(uid);
    if (cached != null) {
      _items = List<NotificationItem>.from(cached);
      _itemsUid = uid;
      _load(quiet: true);
    } else {
      _load();
    }
    _refreshTimer = Timer.periodic(const Duration(seconds: 20), (_) {
      if (!mounted || !_tabVisible) return;
      _load(quiet: true);
    });
  }

  /// IndexedStack turns tickers off for hidden tabs: skip polling while hidden,
  /// refresh once when the Notifications tab is shown again.
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final visible = TickerMode.valuesOf(context).enabled;
    if (visible && !_tabVisible) unawaited(_load(quiet: true));
    _tabVisible = visible;
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    if (_errorMessage == null) AlertsTabPage._remember(_itemsUid, _items);
    super.dispose();
  }

  Future<String?> _resolveUid() async {
    final userId = AuthConfig.currentUserUid;
    if (userId != null && userId.isNotEmpty) return userId;
    return SessionStorage.getStoredUser();
  }

  Future<Set<String>> _loadDismissedAnnouncementIds(String uid) async {
    if (uid.isEmpty) return {};
    final prefs = await SharedPreferences.getInstance();
    final list = prefs.getStringList('notif_dismissed_ann_$uid');
    if (list == null || list.isEmpty) return {};
    return list.toSet();
  }

  Future<void> _persistDismissedAnnouncementIds(
    String uid,
    Set<String> ids,
  ) async {
    if (uid.isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    final sorted = ids.toList()..sort();
    await prefs.setStringList('notif_dismissed_ann_$uid', sorted);
  }

  Future<List<NotificationItem>> _applyLocalReadStateAndDismissed(
    List<NotificationItem> raw,
    String? uid,
  ) async {
    final local = await activity.UserActivityService.getNotifications();
    final annRead = <String, bool>{};
    for (final n in local) {
      if (n.id.startsWith('ann_')) {
        annRead[n.id.substring(4)] = n.isRead;
      }
    }
    var next = raw.map((item) {
      if (!item.isAnnouncement) return item;
      final r = annRead[item.id];
      if (r == null) return item;
      return item.copyWith(isRead: r);
    }).toList();

    if (uid != null && uid.isNotEmpty) {
      final dismissed = await _loadDismissedAnnouncementIds(uid);
      next = next.where((i) {
        if (!i.isAnnouncement) return true;
        return !dismissed.contains(i.id);
      }).toList();
    }
    return next;
  }

  Future<void> _load({bool quiet = false}) async {
    if (!mounted) return;
    if (quiet) {
      if (_quietLoadInFlight || _loading) return;
      _quietLoadInFlight = true;
    } else {
      setState(() {
        _loading = true;
        _errorMessage = null;
      });
    }
    try {
      final uid = await _resolveUid();
      final list = await AlertsTabPage._fetch(uid);
      unawaited(NotificationBadgeNotifier.instance.refresh(userId: uid));
      if (mounted) {
        setState(() {
          _items = list;
          _itemsUid = uid;
          _loading = false;
          _errorMessage = null;
        });
      }
    } catch (e) {
      debugPrint('AlertsTabPage: $e');
      // Background refresh failures keep the list already on screen.
      if (mounted && !quiet) {
        setState(() {
          _items = [];
          _loading = false;
          _errorMessage = e.toString();
        });
      }
    } finally {
      if (quiet) _quietLoadInFlight = false;
    }
  }

  List<NotificationItem> get _filteredItems {
    switch (_filter) {
      case _AlertsFilter.unread:
        return _items.where((i) => i.isUnread).toList();
      case _AlertsFilter.announcements:
        return _items.where((i) => i.isAnnouncement).toList();
      case _AlertsFilter.activity:
        return _items.where((i) => !i.isAnnouncement).toList();
      case _AlertsFilter.all:
        return List<NotificationItem>.from(_items);
    }
  }

  int get _unreadCount => _items.where((i) => i.isUnread).length;

  int _filterCount(_AlertsFilter f) {
    switch (f) {
      case _AlertsFilter.all:
        return _items.length;
      case _AlertsFilter.unread:
        return _items.where((i) => i.isUnread).length;
      case _AlertsFilter.announcements:
        return _items.where((i) => i.isAnnouncement).length;
      case _AlertsFilter.activity:
        return _items.where((i) => !i.isAnnouncement).length;
    }
  }

  String _filterLabel(_AlertsFilter f) {
    switch (f) {
      case _AlertsFilter.all:
        return 'All';
      case _AlertsFilter.unread:
        return 'Unread';
      case _AlertsFilter.announcements:
        return 'Announcements';
      case _AlertsFilter.activity:
        return 'Activity';
    }
  }

  void _setFilter(_AlertsFilter f) {
    if (_filter == f) return;
    setState(() => _filter = f);
  }

  static const Color _kNotifText = Color(0xFF111827);
  static const Color _kNotifMuted = Color(0xFF6B7280);

  Widget _buildNotificationsHeader(BuildContext context) {
    final showActions = !_loading && _errorMessage == null && _items.isNotEmpty;
    final accent = AppTheme.primary;
    final onHeader = AppTheme.onPrimary;
    final topInset = MediaQuery.paddingOf(context).top;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(height: topInset),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 18),
          decoration: BoxDecoration(
            color: accent,
            borderRadius: const BorderRadius.only(
              bottomLeft: Radius.circular(28),
              bottomRight: Radius.circular(28),
            ),
            boxShadow: [
              BoxShadow(
                color: accent.withValues(alpha: 0.35),
                blurRadius: 16,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: onHeader.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: onHeader.withValues(alpha: 0.45)),
                ),
                child: Icon(
                  Icons.notifications_active_rounded,
                  color: onHeader,
                  size: 26,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Notifications',
                      style: TextStyle(
                        color: onHeader,
                        fontSize: 24,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.2,
                        height: 1.1,
                      ),
                    ),
                    const SizedBox(height: 4),
                    if (_unreadCount > 0)
                      Container(
                        margin: const EdgeInsets.only(bottom: 6),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.redAccent,
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          _unreadCount > 99
                              ? '99+ unread'
                              : '$_unreadCount unread',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    Text(
                      'Updates, check-ins & Tourism Office news',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: onHeader.withValues(alpha: 0.88),
                        fontSize: 13,
                        height: 1.35,
                      ),
                    ),
                  ],
                ),
              ),
              if (showActions) _buildHeaderAction(onHeader: onHeader),
            ],
          ),
        ),
        if (showActions)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
            child: _buildFilterPillsRow(),
          ),
      ],
    );
  }

  Widget _buildHeaderAction({required Color onHeader}) {
    if (_unreadCount > 0) {
      return Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: _markingAll ? null : _markAllAsRead,
          borderRadius: BorderRadius.circular(12),
          child: Ink(
            decoration: BoxDecoration(
              color: onHeader.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: onHeader.withValues(alpha: 0.45)),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (_markingAll)
                  SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: onHeader,
                    ),
                  )
                else
                  Icon(Icons.done_all_rounded, size: 16, color: onHeader),
                const SizedBox(width: 4),
                Text(
                  _markingAll ? '…' : 'Read all',
                  style: TextStyle(
                    color: onHeader,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFFECFDF5),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: const Color(0xFF6EE7B7).withValues(alpha: 0.6),
        ),
      ),
      child: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.check_circle_rounded, size: 18, color: Color(0xFF059669)),
          SizedBox(width: 6),
          Text(
            'All read',
            style: TextStyle(
              color: Color(0xFF059669),
              fontSize: 13,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterPillsRow() {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(children: _AlertsFilter.values.map(_buildFilterPill).toList()),
    );
  }

  Widget _buildFilterPill(_AlertsFilter f) {
    final selected = _filter == f;
    final count = _filterCount(f);
    final label = _filterLabel(f);

    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => _setFilter(f),
          borderRadius: BorderRadius.circular(24),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOut,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
            decoration: BoxDecoration(
              color: selected
                  ? AppTheme.primary.withValues(alpha: 0.12)
                  : Colors.white,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: selected ? AppTheme.primary : const Color(0xFFE5E7EB),
                width: selected ? 1.5 : 1,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  _filterIcon(f),
                  size: 14,
                  color: selected ? AppTheme.primary : _kNotifMuted,
                ),
                const SizedBox(width: 5),
                Text(
                  label,
                  style: TextStyle(
                    color: selected ? AppTheme.primary : _kNotifMuted,
                    fontSize: 12,
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
                  ),
                ),
                const SizedBox(width: 5),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: selected
                        ? AppTheme.primary.withValues(alpha: 0.18)
                        : const Color(0xFFF3F4F6),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    '$count',
                    style: TextStyle(
                      color: selected ? AppTheme.primaryDark : _kNotifMuted,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _markAsRead(NotificationItem item) async {
    if (item.isRead) return;
    if (item.isAnnouncement) {
      await activity.UserActivityService.markNotificationAsRead(
        'ann_${item.id}',
      );
      if (mounted) {
        setState(() {
          final i = _items.indexWhere(
            (x) => x.id == item.id && x.isAnnouncement,
          );
          if (i >= 0) _items[i] = item.copyWith(isRead: true);
        });
      }
      await NotificationBadgeNotifier.instance.refresh();
      return;
    }
    if (item.id.startsWith('welcome_')) {
      await activity.UserActivityService.markNotificationAsRead(item.id);
      if (mounted) {
        setState(() {
          final i = _items.indexWhere((x) => x.id == item.id);
          if (i >= 0) _items[i] = item.copyWith(isRead: true);
        });
      }
      await NotificationBadgeNotifier.instance.refresh();
      return;
    }
    await NotificationFirestoreService.markAsRead(item.id);
    if (mounted) {
      setState(() {
        final i = _items.indexWhere(
          (x) => x.id == item.id && x.userId == item.userId,
        );
        if (i >= 0) _items[i] = item.copyWith(isRead: true);
      });
    }
    await NotificationBadgeNotifier.instance.refresh();
  }

  Future<void> _markAllAsRead() async {
    if (_markingAll || _items.isEmpty) return;
    final uid = await _resolveUid();
    if (uid == null || uid.isEmpty) return;

    setState(() => _markingAll = true);
    try {
      await NotificationFirestoreService.markAllAsReadForUser(uid);
      await activity.UserActivityService.markAllNotificationsAsRead();
      for (final item in _items) {
        if (item.isAnnouncement) {
          await activity.UserActivityService.markNotificationAsRead(
            'ann_${item.id}',
          );
        }
      }
      if (mounted) {
        setState(() {
          _items = _items.map((i) => i.copyWith(isRead: true)).toList();
        });
      }
      await NotificationBadgeNotifier.instance.refresh();
    } catch (e) {
      debugPrint('AlertsTabPage _markAllAsRead: $e');
    } finally {
      if (mounted) setState(() => _markingAll = false);
    }
  }

  Future<void> _deleteUserNotification(NotificationItem item) async {
    final confirmed = await showTouristDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete notification?'),
        content: const Text('This removes the notification from your list.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    if (item.id.startsWith('welcome_')) {
      await activity.UserActivityService.deleteNotification(item.id);
    } else {
      await NotificationFirestoreService.deleteUserNotification(item.id);
    }
    if (mounted) {
      setState(() {
        _items.removeWhere((x) => x.id == item.id && !x.isAnnouncement);
      });
    }
  }

  Future<void> _dismissAnnouncement(NotificationItem item) async {
    final uid = await _resolveUid();
    if (uid == null || uid.isEmpty) return;
    final set = await _loadDismissedAnnouncementIds(uid);
    set.add(item.id);
    await _persistDismissedAnnouncementIds(uid, set);
    if (mounted) {
      setState(() {
        _items.removeWhere((x) => x.id == item.id && x.isAnnouncement);
      });
    }
    await NotificationBadgeNotifier.instance.refresh();
  }

  Future<void> _confirmDismissAnnouncement(NotificationItem item) async {
    final confirmed = await showTouristDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remove from list?'),
        content: const Text(
          'This hides the announcement from your notifications. It does not delete the announcement for other users.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) await _dismissAnnouncement(item);
  }

  Future<void> _openNotificationDetail(NotificationItem item) async {
    await _markAsRead(item);
    if (!mounted) return;

    if (item.isAnnouncement) {
      await EventDetailScreen.open(
        context,
        eventId: item.id,
        title: item.title,
        content: item.message,
        imageUrl: item.imageUrl,
        municipalityName: item.municipalityName,
        type: item.type,
      );
      return;
    }

    final typeLabel = item.type.isEmpty ? 'Notice' : item.type;
    final visual = _notificationVisualFor(item);
    final accent = AppTheme.primary;

    await showTouristDialog<void>(
      context: context,
      builder: (ctx) => Dialog(
        insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        clipBehavior: Clip.antiAlias,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: double.infinity,
                padding: const EdgeInsets.fromLTRB(20, 16, 12, 16),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      accent.withValues(alpha: 0.16),
                      accent.withValues(alpha: 0.05),
                    ],
                  ),
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: visual.color.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(visual.icon, color: visual.color, size: 24),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        item.title,
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                          color: Color(0xFF111827),
                          height: 1.25,
                        ),
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.pop(ctx),
                      icon: const Icon(Icons.close_rounded),
                    ),
                  ],
                ),
              ),
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Wrap(
                        spacing: 8,
                        runSpacing: 6,
                        children: [
                          Chip(
                            label: Text(
                              item.isAnnouncement ? 'Announcement' : 'Activity',
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            backgroundColor: AppTheme.primary.withOpacity(0.12),
                            side: BorderSide.none,
                            padding: const EdgeInsets.symmetric(horizontal: 8),
                          ),
                          Chip(
                            label: Text(
                              typeLabel,
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            backgroundColor: Colors.grey.shade100,
                            side: BorderSide.none,
                            padding: const EdgeInsets.symmetric(horizontal: 8),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      SelectableText(
                        item.message.trim().isEmpty
                            ? '(No message)'
                            : item.message.trim(),
                        style: const TextStyle(
                          fontSize: 15,
                          height: 1.45,
                          color: Color(0xFF374151),
                        ),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        _formatNotificationRelativeTime(item.createdAt),
                        style: TextStyle(
                          color: AppTheme.unselectedMuted.withOpacity(0.95),
                          fontSize: 13,
                        ),
                      ),
                      const SizedBox(height: 24),
                      Row(
                        children: [
                          if (item.isAnnouncement)
                            Expanded(
                              child: OutlinedButton.icon(
                                onPressed: () {
                                  Navigator.pop(ctx);
                                  _confirmDismissAnnouncement(item);
                                },
                                icon: const Icon(
                                  Icons.hide_source_outlined,
                                  size: 18,
                                ),
                                label: const Text('Remove from list'),
                              ),
                            )
                          else
                            Expanded(
                              child: OutlinedButton.icon(
                                onPressed: () {
                                  Navigator.pop(ctx);
                                  _deleteUserNotification(item);
                                },
                                icon: const Icon(
                                  Icons.delete_outline_rounded,
                                  size: 18,
                                ),
                                label: const Text('Delete'),
                              ),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: AppThemeController.instance,
      builder: (context, _) {
        final accent = AppTheme.primary;
        return Scaffold(
          backgroundColor: const Color(0xFFF8FAFC),
          body: Column(
            children: [
              _buildNotificationsHeader(context),
              Expanded(
                child: SafeArea(
                  top: false,
                  child: RefreshIndicator(
                    onRefresh: () => _load(quiet: _items.isNotEmpty),
                    color: AppTheme.primary,
                    child: CustomScrollView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      slivers: [
                        if (_loading)
                          SliverPadding(
                            padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
                            sliver: SliverToBoxAdapter(
                              child: SkeletonListTiles(count: 5),
                            ),
                          )
                        else if (_errorMessage != null)
                          SliverFillRemaining(
                            child: Center(
                              child: Padding(
                                padding: const EdgeInsets.all(24),
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      Icons.error_outline,
                                      size: 48,
                                      color: AppTheme.primary,
                                    ),
                                    const SizedBox(height: 16),
                                    const Text(
                                      'Something went wrong',
                                      style: TextStyle(
                                        color: Color(0xFF111827),
                                        fontSize: 18,
                                        fontWeight: FontWeight.w600,
                                      ),
                                      textAlign: TextAlign.center,
                                    ),
                                    const SizedBox(height: 8),
                                    Text(
                                      _errorMessage!,
                                      style: TextStyle(
                                        color: AppTheme.unselectedMuted,
                                        fontSize: 14,
                                      ),
                                      textAlign: TextAlign.center,
                                      maxLines: 3,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    const SizedBox(height: 24),
                                    FilledButton.icon(
                                      onPressed: _load,
                                      icon: const Icon(Icons.refresh, size: 20),
                                      label: const Text('Retry'),
                                      style: FilledButton.styleFrom(
                                        backgroundColor: AppTheme.primary,
                                        foregroundColor: Colors.white,
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 24,
                                          vertical: 12,
                                        ),
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(
                                            24,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          )
                        else if (_items.isEmpty)
                          SliverFillRemaining(
                            child: _buildNotificationsEmptyState(
                              icon: Icons.notifications_none_rounded,
                              title: 'No notifications yet',
                              subtitle:
                                  'Welcome messages, check-ins, and Tourism Office\nannouncements will show up here.',
                            ),
                          )
                        else if (_filteredItems.isEmpty)
                          SliverFillRemaining(
                            child: _buildNotificationsEmptyState(
                              icon: Icons.filter_list_off_rounded,
                              title: 'Nothing in this filter',
                              subtitle:
                                  'Try another category or mark items as read.',
                            ),
                          )
                        else
                          SliverPadding(
                            padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
                            sliver: SliverList(
                              delegate: SliverChildBuilderDelegate((
                                context,
                                index,
                              ) {
                                final item = _filteredItems[index];
                                return _NotificationCard(
                                  item: item,
                                  onOpen: () => _openNotificationDetail(item),
                                  onRemove: () {
                                    if (item.isAnnouncement) {
                                      _confirmDismissAnnouncement(item);
                                    } else {
                                      _deleteUserNotification(item);
                                    }
                                  },
                                );
                              }, childCount: _filteredItems.length),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildNotificationsEmptyState({
    required IconData icon,
    required String title,
    required String subtitle,
  }) {
    final accent = AppTheme.primary;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(22),
              decoration: BoxDecoration(
                color: accent.withValues(alpha: 0.1),
                shape: BoxShape.circle,
                border: Border.all(color: accent.withValues(alpha: 0.2)),
              ),
              child: Icon(icon, size: 48, color: accent),
            ),
            const SizedBox(height: 20),
            Text(
              title,
              style: const TextStyle(
                color: _kNotifText,
                fontSize: 18,
                fontWeight: FontWeight.w700,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              subtitle,
              style: TextStyle(
                color: AppTheme.unselectedMuted.withValues(alpha: 0.95),
                fontSize: 14,
                height: 1.45,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

class _NotificationCard extends StatelessWidget {
  const _NotificationCard({
    required this.item,
    required this.onOpen,
    required this.onRemove,
  });

  final NotificationItem item;
  final VoidCallback onOpen;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final visual = _notificationVisualFor(item);
    final accent = AppTheme.primary;
    final hasUnread = item.isUnread;
    final message = item.message.replaceAll('\n', ' ').trim();

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: Colors.transparent,
        elevation: 0,
        child: InkWell(
          onTap: onOpen,
          borderRadius: BorderRadius.circular(12),
          child: Ink(
            decoration: BoxDecoration(
              color: hasUnread ? accent.withValues(alpha: 0.06) : Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: hasUnread
                    ? accent.withValues(alpha: 0.28)
                    : const Color(0xFFE5E7EB),
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(10, 10, 4, 10),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  if (item.isAnnouncement &&
                      (item.imageUrl?.trim().isNotEmpty ?? false))
                    ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: SizedBox(
                        width: 52,
                        height: 52,
                        child: SpotImage(
                          imageUrl: item.imageUrl,
                          fit: BoxFit.cover,
                        ),
                      ),
                    )
                  else
                    Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: visual.color.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(visual.icon, color: visual.color, size: 18),
                    ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                item.title,
                                style: TextStyle(
                                  color: const Color(0xFF111827),
                                  fontWeight: hasUnread
                                      ? FontWeight.w700
                                      : FontWeight.w600,
                                  fontSize: 14,
                                  height: 1.2,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            Text(
                              _formatNotificationRelativeTime(item.createdAt),
                              style: TextStyle(
                                color: AppTheme.unselectedMuted,
                                fontSize: 10,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 3),
                        Row(
                          children: [
                            _NotificationTypeChip(
                              label: visual.label,
                              color: visual.color,
                              compact: true,
                            ),
                            if (message.isNotEmpty) ...[
                              const SizedBox(width: 6),
                              Expanded(
                                child: Text(
                                  message,
                                  style: TextStyle(
                                    color: AppTheme.unselectedMuted,
                                    fontSize: 12,
                                    height: 1.25,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(
                      minWidth: 32,
                      minHeight: 32,
                    ),
                    icon: Icon(
                      Icons.close_rounded,
                      size: 18,
                      color: Colors.grey.shade500,
                    ),
                    tooltip: item.isAnnouncement
                        ? 'Remove from list'
                        : 'Delete',
                    onPressed: onRemove,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _NotificationTypeChip extends StatelessWidget {
  const _NotificationTypeChip({
    required this.label,
    required this.color,
    this.outlined = false,
    this.compact = false,
  });

  final String label;
  final Color color;
  final bool outlined;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 6 : 8,
        vertical: compact ? 2 : 3,
      ),
      decoration: BoxDecoration(
        color: outlined ? Colors.transparent : color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(compact ? 6 : 8),
        border: outlined
            ? Border.all(color: color.withValues(alpha: 0.35))
            : null,
      ),
      child: Text(
        label,
        style: TextStyle(
          color: outlined ? color : color.withValues(alpha: 0.95),
          fontSize: compact ? 9.5 : 10.5,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.15,
        ),
      ),
    );
  }
}

/// VR Tours tab: opens the Oroquieta City Plaza Teleport360 tour in-app.
class VrToursTabPage extends StatelessWidget {
  const VrToursTabPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.scaffoldBackground,
      body: SafeArea(
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.vrpano_rounded, size: 64, color: AppTheme.primary),
              const SizedBox(height: 16),
              const Text(
                'VR Tours',
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                '360° tours — open below',
                style: TextStyle(color: AppTheme.unselectedMuted, fontSize: 14),
              ),
              const SizedBox(height: 24),
              FilledButton.icon(
                onPressed: () => openVrTour(
                  context,
                  url: kOroquietaCityPlazaVrUrl,
                  title: 'Oroquieta City Plaza',
                ),
                icon: const Icon(Icons.play_circle_filled, size: 22),
                label: Text(
                  VrDownloadAppPrompt.ctaLabel(
                    mobileLabel: 'Oroquieta City Plaza VR',
                  ),
                ),
                style: FilledButton.styleFrom(
                  backgroundColor: AppTheme.primary,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: 14,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(24),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

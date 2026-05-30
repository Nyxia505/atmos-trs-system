import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'dart:convert';
import 'package:geolocator/geolocator.dart';
import 'package:atmos_trs_system/screens/vr_webview_screen.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:atmos_trs_system/config/app_theme.dart';
import 'package:atmos_trs_system/config/app_theme_controller.dart';
import 'package:atmos_trs_system/config/auth_config.dart';
import 'package:atmos_trs_system/config/session_storage.dart';
import 'package:atmos_trs_system/config/vr_tour_config.dart';
import 'package:atmos_trs_system/services/qr_checkin_ui.dart';
import 'package:atmos_trs_system/services/qr_checkin_service.dart';
import 'package:atmos_trs_system/services/qr_scan_demo_guard.dart';
import 'package:atmos_trs_system/services/pending_spot_checkin_storage.dart';
import 'package:atmos_trs_system/services/pending_lgu_checkin_storage.dart';
import 'package:atmos_trs_system/screens/spot_checkin_screen.dart';
import 'package:atmos_trs_system/screens/lgu_checkin_screen.dart';
import 'package:atmos_trs_system/services/announcement_notification_sync.dart';
import 'package:atmos_trs_system/services/notification_badge_notifier.dart';
import 'package:atmos_trs_system/services/notification_firestore_service.dart';
import 'package:atmos_trs_system/services/user_activity_service.dart' as activity;
import 'package:atmos_trs_system/models/notification_item.dart';
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
    return const Scaffold(
      body: Center(child: CircularProgressIndicator()),
    );
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
/// spot QR, the user is sent to `/signup` with pending check-in stored for after verification.
class ScanTabPage extends StatefulWidget {
  const ScanTabPage({super.key, this.guestMode = false});

  /// True when launched before sign-in (e.g. from landing). Shows a back button and routes
  /// unauthenticated scans to `/signup` instead of a dialog.
  final bool guestMode;

  @override
  State<ScanTabPage> createState() => _ScanTabPageState();
}

class _ScanTabPageState extends State<ScanTabPage> {
  final MobileScannerController _controller = MobileScannerController(
    detectionSpeed: DetectionSpeed.normal,
    facing: CameraFacing.back,
    torchEnabled: false,
    autoStart: false,
  );

  /// Cooldown to avoid duplicate scans (e.g. same code detected many times in a few seconds).
  static const Duration _scanCooldown = Duration(seconds: 3);
  DateTime? _lastScanAt;
  bool _isProcessing = false;
  bool _isStartingCamera = false;

  @override
  void initState() {
    super.initState();
    _startCamera();
    _warmLocationForScan();
  }

  Future<void> _warmLocationForScan() async {
    if (kIsWeb) return;
    try {
      final enabled = await Geolocator.isLocationServiceEnabled();
      if (!enabled) return;
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        return;
      }
      await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.medium,
          timeLimit: Duration(seconds: 8),
        ),
      );
    } catch (_) {}
  }

  Future<void> _startCamera() async {
    if (_isStartingCamera) return;
    _isStartingCamera = true;
    try {
      await _controller.stop();
      await _controller.start();
    } catch (e) {
      debugPrint('ScanTabPage: camera restart error: $e');
      if (mounted) setState(() {});
    } finally {
      _isStartingCamera = false;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _clearProcessing() {
    if (!mounted) return;
    setState(() => _isProcessing = false);
  }

  void _onDetect(BarcodeCapture capture) {
    if (_isProcessing) return;
    final barcodes = capture.barcodes;
    if (barcodes.isEmpty) return;
    final raw = barcodes.first.rawValue;
    if (raw == null || raw.isEmpty) return;
    if (_lastScanAt != null && DateTime.now().difference(_lastScanAt!) < _scanCooldown) {
      return;
    }
    _lastScanAt = DateTime.now();
    setState(() => _isProcessing = true);
    _processScannedPayload(raw);
  }

  Future<void> _processScannedPayload(String raw) async {
    // Try tourist QR: {"type":"tourist","tourist_id":"..."}
    final touristId = _tryParseTouristQr(raw);
    if (touristId != null && touristId.isNotEmpty) {
      await _handleTouristQrScanned(touristId);
      _clearProcessing();
      return;
    }

    final lguPayload = parseLguQrPayload(raw);
    if (lguPayload != null) {
      await _handleLguQrScanned(lguPayload);
      _clearProcessing();
      return;
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

    if (spotId.isEmpty) {
      if (mounted) _showError('Invalid QR code: no spot ID.');
      _clearProcessing();
      return;
    }

    SpotInfo? spot = await QRCheckInService.getSpotById(
      spotId,
      municipalityId: municipalityIdFromQr,
    );
    if (spot == null) {
      if (mounted) _showError('Tourist spot not found. Use a valid ATMOS TRS spot QR code.');
      _clearProcessing();
      return;
    }
    final municipalityId = spot.municipalityId;
    final spotName = spot.spotName;
    final municipality = spot.municipality;
    if (municipalityId.isEmpty) {
      if (mounted) _showError('This spot has no municipality set. Ask the tourism office to update it.');
      _clearProcessing();
      return;
    }

    final demoSpotMsg =
        QrScanDemoGuard.municipalityRestrictionMessage(municipalityId);
    if (demoSpotMsg != null) {
      if (mounted) _showDemoRestrictionSnack(demoSpotMsg);
      _clearProcessing();
      return;
    }

    final slat = spot.latitude;
    final slng = spot.longitude;
    if (slat == null ||
        slng == null ||
        slat.abs() <= 1e-7 ||
        slng.abs() <= 1e-7) {
      if (mounted) {
        _showError(
          'This spot has no latitude/longitude in the system. '
          'Ask the tourism office to add GPS coordinates for this tourist spot.',
        );
      }
      _clearProcessing();
      return;
    }

    final qrMismatchError = QRCheckInService.verifyQrCoordinatesMatchFirestore(
      qrLat: qrEmbedLat,
      qrLng: qrEmbedLng,
      firestoreLat: slat,
      firestoreLng: slng,
    );
    if (qrMismatchError != null) {
      if (mounted) _showError(qrMismatchError);
      _clearProcessing();
      return;
    }

    final spotLocationError = await QRCheckInService.verifyProximityToTouristSpot(
      latitude: slat,
      longitude: slng,
      spotLabel: spotName.isNotEmpty ? spotName : spotId,
    );
    if (spotLocationError != null) {
      if (mounted) _showError(spotLocationError);
      _clearProcessing();
      return;
    }

    final uid = await QRCheckInService.getCurrentUserId();
    if (uid == null || uid.isEmpty) {
      await PendingLguCheckInStorage.clear();
      await PendingSpotCheckInStorage.save(
        municipalityId: municipalityId,
        spotId: spotId,
        spotName: spotName.isNotEmpty ? spotName : null,
        municipality: municipality.isNotEmpty ? municipality : null,
      );
      if (!mounted) {
        return;
      }
      Navigator.pushReplacementNamed(context, '/signup');
      _clearProcessing();
      return;
    }

    if (!mounted) {
      return;
    }
    await Navigator.push<void>(
      context,
      MaterialPageRoute<void>(
        builder: (_) => SpotCheckInScreen(spotInfo: spot),
      ),
    );
    if (mounted) {
      _lastScanAt = DateTime.now();
    }
    _clearProcessing();
  }

  void _showError(String message) {
    showQRCheckInErrorDialog(context, message);
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

  Future<void> _handleLguQrScanned(LguQrPayload payload) async {
    final municipalityId = payload.municipalityId;

    final demoLguMsg =
        QrScanDemoGuard.municipalityRestrictionMessage(municipalityId);
    if (demoLguMsg != null) {
      if (mounted) _showDemoRestrictionSnack(demoLguMsg);
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
        return;
      }
      anchorLat = coords.lat;
      anchorLng = coords.lng;
      maxDistanceMeters = kQrScanLguCenterMaxDistanceMeters;
    }

    final lguLocationError = await QrScanLocationGuard.verifyNearAnchor(
      anchorLat: anchorLat,
      anchorLng: anchorLng,
      maxDistanceMeters: maxDistanceMeters,
    );
    if (lguLocationError != null) {
      if (mounted) _showError(lguLocationError);
      return;
    }

    final uid = await QRCheckInService.getCurrentUserId();
    if (uid != null && uid.isNotEmpty) {
      if (!mounted) return;
      await Navigator.push<void>(
        context,
        MaterialPageRoute<void>(
          builder: (_) => LguCheckInScreen(
            municipalityId: municipalityId,
            displayName: displayName,
          ),
        ),
      );
      if (mounted) {
        _lastScanAt = DateTime.now();
      }
      return;
    }

    await PendingSpotCheckInStorage.clear();
    await PendingLguCheckInStorage.save(
      municipalityId: municipalityId,
      displayName: displayName,
    );

    if (!mounted) return;
    Navigator.of(context).pushReplacementNamed('/signup');
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
      String fullName = '$firstName ${middleName != null && middleName.isNotEmpty ? '${middleName[0]}.' : ''} $lastName'.trim();
      if (fullName.isEmpty) fullName = email.isNotEmpty ? email : 'Unknown';
      showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Tourist QR scanned'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('$fullName', style: const TextStyle(fontWeight: FontWeight.bold)),
                if (email.isNotEmpty) ...[const SizedBox(height: 4), Text(email, style: TextStyle(color: Colors.grey.shade700))],
                if (mobile.isNotEmpty) ...[const SizedBox(height: 2), Text(mobile)],
                if (city.isNotEmpty || country.isNotEmpty) ...[const SizedBox(height: 2), Text('${city.isNotEmpty ? '$city, ' : ''}$country')],
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
      if (mounted) _showError('Could not load tourist: ${e.toString()}');
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
                          icon: const Icon(Icons.arrow_back_rounded, color: Color(0xFF111827)),
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
                          widget.guestMode ? 'Scan LGU or spot QR' : 'QR Check-in',
                          style: const TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF111827),
                          ),
                        ),
                      ),
                    ],
                  ),
                  if (QrScanDemoGuard.isDemoActive) ...[
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: Colors.amber.shade50,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.amber.shade200),
                      ),
                      child: Text(
                        'Demo mode: Oroquieta City only — GPS bypass on (presentation; scan anywhere).',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: Colors.amber.shade900,
                          height: 1.3,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            Expanded(
              child: ClipRRect(
                borderRadius: const BorderRadius.vertical(bottom: Radius.circular(16)),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    MobileScanner(
                      controller: _controller,
                      onDetect: _onDetect,
                      errorBuilder: (context, error) => _buildCameraError(error),
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
                              CircularProgressIndicator(color: AppTheme.primary),
                              const SizedBox(height: 16),
                              Text(
                                'Saving check-in...',
                                style: TextStyle(color: Colors.white, fontSize: 16),
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
                    ? 'Demo: scan any Oroquieta City spot or LGU QR from your device (no need to be on site).'
                    : 'Point your camera at a municipality or tourist spot QR code',
                style: TextStyle(
                  color: AppTheme.unselectedMuted,
                  fontSize: 14,
                ),
                textAlign: TextAlign.center,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCameraError(MobileScannerException error) {
    final isPermission = error.errorCode == MobileScannerErrorCode.permissionDenied;
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
                isPermission ? 'Camera permission required' : 'Camera error',
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF111827),
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                isPermission
                    ? 'Please allow camera access in Settings to scan QR codes at tourist spots.'
                    : error.errorDetails?.message ?? error.errorCode.name,
                style: TextStyle(color: AppTheme.unselectedMuted, fontSize: 14),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              FilledButton.icon(
                onPressed: () => _startCamera(),
                icon: const Icon(Icons.refresh, size: 20),
                label: const Text('Try again'),
                style: FilledButton.styleFrom(
                  backgroundColor: AppTheme.primary,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
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

  @override
  State<AlertsTabPage> createState() => _AlertsTabPageState();
}

class _AlertsTabPageState extends State<AlertsTabPage> {
  List<NotificationItem> _items = [];
  bool _loading = true;
  bool _markingAll = false;
  String? _errorMessage;
  _AlertsFilter _filter = _AlertsFilter.all;

  @override
  void initState() {
    super.initState();
    _load();
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

  Future<void> _persistDismissedAnnouncementIds(String uid, Set<String> ids) async {
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

  Future<void> _load() async {
    if (!mounted) return;
    setState(() {
      _loading = true;
      _errorMessage = null;
    });
    try {
      final uid = await _resolveUid();
      final list = await AnnouncementNotificationSync.loadAlertItems(
        userId: uid,
      );
      await NotificationBadgeNotifier.instance.refresh(userId: uid);
      if (mounted) {
        setState(() {
          _items = list;
          _loading = false;
          _errorMessage = null;
        });
      }
    } catch (e) {
      debugPrint('AlertsTabPage: $e');
      if (mounted) {
        setState(() {
          _items = [];
          _loading = false;
          _errorMessage = e.toString();
        });
      }
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

  Widget _buildNotificationsHeader() {
    final showActions =
        !_loading && _errorMessage == null && _items.isNotEmpty;
    final accent = AppTheme.primary;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: accent.withValues(alpha: 0.28)),
          boxShadow: [
            BoxShadow(
              color: accent.withValues(alpha: 0.1),
              blurRadius: 20,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(18, 18, 18, 20),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    accent.withValues(alpha: 0.18),
                    accent.withValues(alpha: 0.06),
                  ],
                ),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [
                        BoxShadow(
                          color: accent.withValues(alpha: 0.15),
                          blurRadius: 10,
                          offset: const Offset(0, 3),
                        ),
                      ],
                    ),
                    child: Icon(
                      Icons.notifications_active_rounded,
                      color: accent,
                      size: 28,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Notifications',
                          style: TextStyle(
                            color: _kNotifText,
                            fontSize: 24,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -0.35,
                            height: 1.15,
                          ),
                        ),
                        const SizedBox(height: 4),
                        const Text(
                          'Updates, check-ins & Tourism Office news',
                          style: TextStyle(
                            color: _kNotifMuted,
                            fontSize: 13,
                            height: 1.35,
                          ),
                        ),
                        if (showActions && _unreadCount > 0) ...[
                          const SizedBox(height: 10),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 5,
                            ),
                            decoration: BoxDecoration(
                              color: accent.withValues(alpha: 0.14),
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(
                                color: accent.withValues(alpha: 0.25),
                              ),
                            ),
                            child: Text(
                              '$_unreadCount unread',
                              style: TextStyle(
                                color: accent,
                                fontSize: 12,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  if (showActions) _buildHeaderAction(),
                ],
              ),
            ),
            if (showActions)
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 14, 14, 16),
                child: _buildFilterPillsRow(),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeaderAction() {
    if (_unreadCount > 0) {
      return Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: _markingAll ? null : _markAllAsRead,
          borderRadius: BorderRadius.circular(12),
          child: Ink(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: AppTheme.primary.withValues(alpha: 0.45),
              ),
              boxShadow: [
                BoxShadow(
                  color: AppTheme.primary.withValues(alpha: 0.08),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (_markingAll)
                  SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: AppTheme.primary,
                    ),
                  )
                else
                  Icon(
                    Icons.done_all_rounded,
                    size: 18,
                    color: AppTheme.primary,
                  ),
                const SizedBox(width: 6),
                Text(
                  _markingAll ? '…' : 'Read all',
                  style: TextStyle(
                    color: AppTheme.primary,
                    fontSize: 13,
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
        border: Border.all(color: const Color(0xFF6EE7B7).withValues(alpha: 0.6)),
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
      child: Row(
        children: _AlertsFilter.values.map(_buildFilterPill).toList(),
      ),
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
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: BoxDecoration(
              color: selected
                  ? AppTheme.primary.withValues(alpha: 0.12)
                  : Colors.white,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(
                color: selected
                    ? AppTheme.primary
                    : const Color(0xFFE5E7EB),
                width: selected ? 1.5 : 1,
              ),
              boxShadow: selected
                  ? [
                      BoxShadow(
                        color: AppTheme.primary.withValues(alpha: 0.12),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      ),
                    ]
                  : null,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  _filterIcon(f),
                  size: 16,
                  color: selected ? AppTheme.primary : _kNotifMuted,
                ),
                const SizedBox(width: 6),
                Text(
                  label,
                  style: TextStyle(
                    color: selected ? AppTheme.primary : _kNotifMuted,
                    fontSize: 13,
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
                  ),
                ),
                const SizedBox(width: 6),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
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
      await activity.UserActivityService.markNotificationAsRead('ann_${item.id}');
      if (mounted) {
        setState(() {
          final i = _items.indexWhere((x) => x.id == item.id && x.isAnnouncement);
          if (i >= 0) _items[i] = item.copyWith(isRead: true);
        });
      }
      await NotificationBadgeNotifier.instance.refresh();
      return;
    }
    await NotificationFirestoreService.markAsRead(item.id);
    if (mounted) {
      setState(() {
        final i = _items.indexWhere((x) => x.id == item.id && x.userId == item.userId);
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
          await activity.UserActivityService.markNotificationAsRead('ann_${item.id}');
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
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete notification?'),
        content: const Text('This removes the notification from your list.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await NotificationFirestoreService.deleteUserNotification(item.id);
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
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remove from list?'),
        content: const Text(
          'This hides the announcement from your notifications. It does not delete the announcement for other users.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
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
    final typeLabel = item.type.isEmpty ? 'Notice' : item.type;
    final visual = _notificationVisualFor(item);
    final accent = AppTheme.primary;

    await showDialog<void>(
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
                              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                            ),
                            backgroundColor: AppTheme.primary.withOpacity(0.12),
                            side: BorderSide.none,
                            padding: const EdgeInsets.symmetric(horizontal: 8),
                          ),
                          Chip(
                            label: Text(
                              typeLabel,
                              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                            ),
                            backgroundColor: Colors.grey.shade100,
                            side: BorderSide.none,
                            padding: const EdgeInsets.symmetric(horizontal: 8),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      SelectableText(
                        item.message.trim().isEmpty ? '(No message)' : item.message.trim(),
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
                                icon: const Icon(Icons.hide_source_outlined, size: 18),
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
                                icon: const Icon(Icons.delete_outline_rounded, size: 18),
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
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              accent.withValues(alpha: 0.05),
              const Color(0xFFF8FAFC),
            ],
          ),
        ),
        child: SafeArea(
        child: RefreshIndicator(
          onRefresh: _load,
          color: AppTheme.primary,
          child: CustomScrollView(
            slivers: [
              SliverToBoxAdapter(child: _buildNotificationsHeader()),
              if (_loading)
                SliverFillRemaining(
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        CircularProgressIndicator(color: AppTheme.primary),
                        const SizedBox(height: 16),
                        Text(
                          'Loading...',
                          style: TextStyle(color: AppTheme.unselectedMuted),
                        ),
                      ],
                    ),
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
                          Icon(Icons.error_outline, size: 48, color: AppTheme.primary),
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
                            style: TextStyle(color: AppTheme.unselectedMuted, fontSize: 14),
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
                              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
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
                    subtitle: 'Try another category or mark items as read.',
                  ),
                )
              else
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
                  sliver: SliverList(
                    delegate: SliverChildBuilderDelegate((context, index) {
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
      padding: const EdgeInsets.only(bottom: 12),
      child: Material(
        color: Colors.transparent,
        elevation: 0,
        child: InkWell(
          onTap: onOpen,
          borderRadius: BorderRadius.circular(18),
          child: Ink(
            decoration: BoxDecoration(
              color: hasUnread
                  ? accent.withValues(alpha: 0.07)
                  : Colors.white,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(
                color: hasUnread
                    ? accent.withValues(alpha: 0.38)
                    : const Color(0xFFE5E7EB),
                width: hasUnread ? 1.5 : 1,
              ),
              boxShadow: [
                BoxShadow(
                  color: hasUnread
                      ? accent.withValues(alpha: 0.12)
                      : Colors.black.withValues(alpha: 0.04),
                  blurRadius: hasUnread ? 14 : 10,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (hasUnread)
                    Container(
                      width: 4,
                      decoration: BoxDecoration(
                        color: accent,
                        borderRadius: const BorderRadius.horizontal(
                          left: Radius.circular(18),
                        ),
                      ),
                    ),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(14, 14, 8, 14),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Stack(
                            clipBehavior: Clip.none,
                            children: [
                              Container(
                                width: 48,
                                height: 48,
                                decoration: BoxDecoration(
                                  color: visual.color.withValues(alpha: 0.14),
                                  borderRadius: BorderRadius.circular(14),
                                  border: Border.all(
                                    color: visual.color.withValues(alpha: 0.22),
                                  ),
                                ),
                                child: Icon(
                                  visual.icon,
                                  color: visual.color,
                                  size: 24,
                                ),
                              ),
                              if (hasUnread)
                                Positioned(
                                  top: -2,
                                  right: -2,
                                  child: Container(
                                    width: 11,
                                    height: 11,
                                    decoration: BoxDecoration(
                                      color: accent,
                                      shape: BoxShape.circle,
                                      border: Border.all(
                                        color: Colors.white,
                                        width: 2,
                                      ),
                                    ),
                                  ),
                                ),
                            ],
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        item.title,
                                        style: TextStyle(
                                          color: const Color(0xFF111827),
                                          fontWeight: hasUnread
                                              ? FontWeight.w800
                                              : FontWeight.w600,
                                          fontSize: 15.5,
                                          height: 1.25,
                                        ),
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                    Icon(
                                      Icons.chevron_right_rounded,
                                      color: accent.withValues(alpha: 0.55),
                                      size: 22,
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 6),
                                Wrap(
                                  spacing: 6,
                                  runSpacing: 4,
                                  children: [
                                    _NotificationTypeChip(
                                      label: visual.label,
                                      color: visual.color,
                                    ),
                                    _NotificationTypeChip(
                                      label: item.isAnnouncement
                                          ? 'Tourism Office'
                                          : 'Your activity',
                                      color: accent,
                                      outlined: true,
                                    ),
                                  ],
                                ),
                                if (message.isNotEmpty) ...[
                                  const SizedBox(height: 8),
                                  Text(
                                    message,
                                    style: TextStyle(
                                      color: AppTheme.unselectedMuted,
                                      fontSize: 13.5,
                                      height: 1.4,
                                    ),
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ],
                                const SizedBox(height: 8),
                                Row(
                                  children: [
                                    Icon(
                                      Icons.schedule_rounded,
                                      size: 13,
                                      color: AppTheme.unselectedMuted
                                          .withValues(alpha: 0.85),
                                    ),
                                    const SizedBox(width: 4),
                                    Text(
                                      _formatNotificationRelativeTime(
                                        item.createdAt,
                                      ),
                                      style: TextStyle(
                                        color: AppTheme.unselectedMuted
                                            .withValues(alpha: 0.9),
                                        fontSize: 12,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                          Column(
                            children: [
                              IconButton(
                                visualDensity: VisualDensity.compact,
                                padding: EdgeInsets.zero,
                                constraints: const BoxConstraints(
                                  minWidth: 36,
                                  minHeight: 36,
                                ),
                                icon: Icon(
                                  Icons.close_rounded,
                                  size: 20,
                                  color: Colors.grey.shade500,
                                ),
                                tooltip: item.isAnnouncement
                                    ? 'Remove from list'
                                    : 'Delete',
                                onPressed: onRemove,
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
  });

  final String label;
  final Color color;
  final bool outlined;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: outlined ? Colors.transparent : color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
        border: outlined
            ? Border.all(color: color.withValues(alpha: 0.35))
            : null,
      ),
      child: Text(
        label,
        style: TextStyle(
          color: outlined ? color : color.withValues(alpha: 0.95),
          fontSize: 10.5,
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
                label: const Text('Oroquieta City Plaza VR'),
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

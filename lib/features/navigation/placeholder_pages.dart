import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'dart:convert';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:atmos_trs_system/config/app_theme.dart';
import 'package:atmos_trs_system/config/auth_config.dart';
import 'package:atmos_trs_system/config/session_storage.dart';
import 'package:atmos_trs_system/config/vr_tour_config.dart';
import 'package:atmos_trs_system/services/qr_checkin_ui.dart';
import 'package:atmos_trs_system/services/qr_checkin_service.dart';
import 'package:atmos_trs_system/services/pending_spot_checkin_storage.dart';
import 'package:atmos_trs_system/services/pending_lgu_checkin_storage.dart';
import 'package:atmos_trs_system/screens/spot_checkin_screen.dart';
import 'package:atmos_trs_system/screens/lgu_checkin_screen.dart';
import 'package:atmos_trs_system/services/notification_firestore_service.dart';
import 'package:atmos_trs_system/models/notification_item.dart';
import 'package:atmos_trs_system/config/qr_scan_geofence_config.dart';
import 'package:atmos_trs_system/data/misamis_occidental_municipalities.dart';
import 'package:atmos_trs_system/services/qr_scan_location_guard.dart';
import 'package:atmos_trs_system/utils/municipality_helper.dart';
import 'package:atmos_trs_system/utils/spot_qr_helper.dart';

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

/// Full-screen WebView that loads the VR tour URL (project-title-2.tiiny.site).
class VrTourPlaceholderPage extends StatefulWidget {
  const VrTourPlaceholderPage({super.key});

  @override
  State<VrTourPlaceholderPage> createState() => _VrTourPlaceholderPageState();
}

class _VrTourPlaceholderPageState extends State<VrTourPlaceholderPage> {
  late final WebViewController _controller;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageFinished: (_) => setState(() => _isLoading = false),
          onWebResourceError: (e) => setState(() => _isLoading = false),
        ),
      )
      ..loadRequest(Uri.parse(kVrTourUrl));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.close, color: Colors.white),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: const Text(
          'VR Tour',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
        ),
      ),
      body: Stack(
        children: [
          WebViewWidget(controller: _controller),
          if (_isLoading)
            const Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(color: AppTheme.primary),
                  SizedBox(height: 16),
                  Text(
                    'Loading VR Tour…',
                    style: TextStyle(color: AppTheme.unselectedMuted),
                  ),
                ],
              ),
            ),
        ],
      ),
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
  );

  /// Cooldown to avoid duplicate scans (e.g. same code detected many times in a few seconds).
  static const Duration _scanCooldown = Duration(seconds: 3);
  DateTime? _lastScanAt;
  bool _isProcessing = false;

  @override
  void initState() {
    super.initState();
    _startCamera();
  }

  Future<void> _startCamera() async {
    try {
      await _controller.start();
    } catch (e) {
      debugPrint('ScanTabPage: camera start error: $e');
      if (mounted) setState(() {});
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

    final deepSpotId = extractSpotIdFromCheckInDeepLink(raw);
    final String spotId;
    final String? municipalityIdFromQr;
    if (deepSpotId != null && deepSpotId.isNotEmpty) {
      spotId = deepSpotId;
      municipalityIdFromQr = null;
    } else {
      final parsed = parseSpotQrPayload(raw);
      spotId = parsed.spotId;
      municipalityIdFromQr = parsed.municipalityId;
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

    final double anchorLat;
    final double anchorLng;
    final double maxDistanceMeters;
    final slat = spot.latitude;
    final slng = spot.longitude;
    if (slat != null &&
        slng != null &&
        slat.abs() > 1e-7 &&
        slng.abs() > 1e-7) {
      anchorLat = slat;
      anchorLng = slng;
      maxDistanceMeters = kQrScanSpotMaxDistanceMeters;
    } else {
      final coords = getMunicipalityAnchorCoordinates(municipalityId);
      if (coords == null) {
        if (mounted) {
          _showError(
            'This spot has no latitude/longitude in the system. '
            'Ask the tourism office to add coordinates for this tourist spot.',
          );
        }
        _clearProcessing();
        return;
      }
      anchorLat = coords.lat;
      anchorLng = coords.lng;
      maxDistanceMeters = kQrScanLguCenterMaxDistanceMeters;
    }

    final spotLocationError = await QrScanLocationGuard.verifyNearAnchor(
      anchorLat: anchorLat,
      anchorLng: anchorLng,
      maxDistanceMeters: maxDistanceMeters,
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

  Future<void> _handleLguQrScanned(LguQrPayload payload) async {
    final municipalityId = payload.municipalityId;
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
              child: Row(
                children: [
                  if (widget.guestMode)
                    IconButton(
                      icon: const Icon(Icons.arrow_back_rounded, color: Color(0xFF111827)),
                      onPressed: () => Navigator.of(context).pop(),
                      tooltip: 'Back',
                    ),
                  Icon(Icons.qr_code_scanner_rounded, color: AppTheme.primary, size: 28),
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
                        child: const Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              CircularProgressIndicator(color: AppTheme.primary),
                              SizedBox(height: 16),
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
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (!mounted) return;
    setState(() {
      _loading = true;
      _errorMessage = null;
    });
    try {
      final userId = AuthConfig.currentUserUid;
      final uid = userId != null && userId.isNotEmpty
          ? userId
          : await SessionStorage.getStoredUser();
      final list = await NotificationFirestoreService.getMergedNotifications(uid);
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

  Future<void> _markAsRead(NotificationItem item) async {
    if (item.isAnnouncement || item.isRead) return;
    await NotificationFirestoreService.markAsRead(item.id);
    if (mounted) {
      setState(() {
        final i = _items.indexWhere((x) => x.id == item.id && x.userId == item.userId);
        if (i >= 0) _items[i] = item.copyWith(isRead: true);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.scaffoldBackground,
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _load,
          color: AppTheme.primary,
          child: CustomScrollView(
            slivers: [
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Notification',
                        style: TextStyle(
                          color: Color(0xFF111827),
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Your notifications & Tourism Office announcements',
                        style: TextStyle(
                          color: AppTheme.unselectedMuted,
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              if (_loading)
                const SliverFillRemaining(
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        CircularProgressIndicator(color: AppTheme.primary),
                        SizedBox(height: 16),
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
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.notifications_none_rounded,
                          size: 64,
                          color: AppTheme.unselectedMuted.withOpacity(0.6),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'No notifications yet',
                          style: TextStyle(
                            color: AppTheme.unselectedMuted,
                            fontSize: 16,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Welcome & check-in notifications will appear here.\nTourism Office announcements show up here too.',
                          style: TextStyle(
                            color: AppTheme.unselectedMuted.withOpacity(0.8),
                            fontSize: 13,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  ),
                )
              else
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
                  sliver: SliverList(
                    delegate: SliverChildBuilderDelegate((context, index) {
                      final item = _items[index];
                      return _NotificationCard(
                        item: item,
                        onTap: () => _markAsRead(item),
                      );
                    }, childCount: _items.length),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NotificationCard extends StatelessWidget {
  const _NotificationCard({
    required this.item,
    required this.onTap,
  });

  final NotificationItem item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final type = item.type.toLowerCase();
    IconData icon = Icons.campaign_rounded;
    Color color = AppTheme.primary;
    if (type == 'welcome') {
      icon = Icons.waving_hand_rounded;
      color = AppTheme.primary;
    } else if (type == 'checkin') {
      icon = Icons.check_circle_rounded;
      color = Colors.green;
    } else if (type == 'promo') {
      icon = Icons.local_offer_rounded;
      color = Colors.green;
    } else if (type == 'event') {
      icon = Icons.event_rounded;
      color = Colors.pink;
    } else if (type == 'alert') {
      icon = Icons.warning_amber_rounded;
      color = Colors.red;
    }
    final hasUnread = item.isUnread;
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      color: hasUnread ? AppTheme.primary.withOpacity(0.04) : AppTheme.cardBackground,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: hasUnread
            ? BorderSide(color: AppTheme.primary.withOpacity(0.3), width: 1)
            : BorderSide.none,
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Stack(
                clipBehavior: Clip.none,
                children: [
                  CircleAvatar(
                    backgroundColor: color.withOpacity(0.2),
                    child: Icon(icon, color: color, size: 22),
                  ),
                  if (hasUnread)
                    Positioned(
                      top: -2,
                      right: -2,
                      child: Container(
                        width: 10,
                        height: 10,
                        decoration: BoxDecoration(
                          color: AppTheme.primary,
                          shape: BoxShape.circle,
                          border: Border.all(color: AppTheme.cardBackground, width: 1),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.title,
                      style: TextStyle(
                        color: const Color(0xFF111827),
                        fontWeight: hasUnread ? FontWeight.w700 : FontWeight.w600,
                        fontSize: 15,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      item.message.replaceAll('\n', ' ').trim(),
                      style: TextStyle(
                        color: AppTheme.unselectedMuted,
                        fontSize: 13,
                        height: 1.35,
                      ),
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 6),
                    Text(
                      _formatTime(item.createdAt),
                      style: TextStyle(
                        color: AppTheme.unselectedMuted.withOpacity(0.8),
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  static String _formatTime(DateTime at) {
    final now = DateTime.now();
    final diff = now.difference(at);
    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    return '${at.day}/${at.month}/${at.year}';
  }
}

/// VR Tours tab: opens the VR tour (project-title-2.tiiny.site) in-app.
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
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const VrTourPlaceholderPage(),
                  ),
                ),
                icon: const Icon(Icons.play_circle_filled, size: 22),
                label: const Text('Open VR Tour'),
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

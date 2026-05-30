// VR tour launcher — hosted tours in WebView (mobile) or browser (web).

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:atmos_trs_system/config/app_theme.dart';
import 'package:atmos_trs_system/config/vr_tour_config.dart';
import 'package:atmos_trs_system/screens/hosted_vr_tour_screen.dart';
import 'package:atmos_trs_system/screens/simple_image_vr_screen.dart';
import 'package:atmos_trs_system/services/vr_tour_firestore_service.dart';

// -----------------------------------------------------------------------------
// Helper: open VR tour (all platforms)
// -----------------------------------------------------------------------------

/// Opens the VR tour in-app (mobile) or system browser (web).
///
/// [useLocalTour] – Legacy flag; opens [kOroquietaCityPlazaVrUrl].
/// [url] – VR tour URL (defaults to [kVrTourUrl] if null).
Future<void> openVrTour(
  BuildContext context, {
  bool useLocalTour = false,
  String? url,
  String title = 'VR Tour',
}) async {
  final targetUrl = useLocalTour
      ? kOroquietaCityPlazaVrUrl
      : (url ?? kVrTourUrl);
  final uri = Uri.tryParse(targetUrl);
  if (uri == null || (!uri.isScheme('http') && !uri.isScheme('https'))) {
    if (context.mounted) _showError(context, 'Invalid VR tour URL');
    return;
  }
  if (!context.mounted) return;
  if (kIsWeb) {
    await _openVrTourOnWeb(context, uri);
  } else {
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        fullscreenDialog: true,
        builder: (_) => HostedVrTourScreen(url: uri.toString(), title: title),
      ),
    );
  }
}

/// Convenience: open VR tour with URL as first argument after context.
Future<void> openVrTourWithUrl(BuildContext context, String url) =>
    openVrTour(context, url: url);

/// Opens hosted VR (Teleport360) or static panorama preview for a tourist spot.
Future<void> openVrForTouristSpot(
  BuildContext context, {
  required String spotId,
  required String spotName,
  String? vrLink,
  String? vrPanoramaUrl,
  String? imageUrl,
}) async {
  var effectiveLink = vrLink?.trim();
  if (effectiveLink == null || effectiveLink.isEmpty) {
    effectiveLink = await VrTourFirestoreService.resolveVrUrlForSpot(
      spotId,
      spotName: spotName,
    );
  }

  final hosted = resolveVrTourUrl(
    vrLink: effectiveLink,
    spotId: spotId,
    spotName: spotName,
  );
  if (hosted != null && hosted.isNotEmpty) {
    await openVrTour(context, url: hosted, title: spotName);
    return;
  }
  if (isOroquietaPlazaSpot(spotId: spotId, spotName: spotName)) {
    await openVrTour(context, url: kOroquietaCityPlazaVrUrl, title: spotName);
    return;
  }
  final pano = vrPanoramaUrl?.trim();
  if (pano != null && pano.isNotEmpty) {
    Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => SimpleImageVrScreen(title: spotName, imageUrl: pano),
      ),
    );
    return;
  }
  final fallback = imageUrl?.trim();
  if (fallback != null && fallback.isNotEmpty) {
    Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) =>
            SimpleImageVrScreen(title: spotName, imageUrl: fallback),
      ),
    );
    return;
  }
  if (context.mounted) {
    _showError(
      context,
      'No VR tour is available for this destination yet. '
      'Ask your LGU to add a VR link in the Tourism dashboard.',
    );
  }
}

Future<void> _openVrTourOnWeb(BuildContext context, Uri uri) async {
  final messenger = ScaffoldMessenger.of(context);
  messenger.showSnackBar(
    SnackBar(
      content: Row(
        children: [
          SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(
              color: Colors.white,
              strokeWidth: 2,
            ),
          ),
          const SizedBox(width: 12),
          const Text('Opening VR tour…'),
        ],
      ),
      backgroundColor: AppTheme.cardBackground,
      duration: const Duration(seconds: 2),
    ),
  );

  try {
    final launched = await launchUrl(
      uri,
      mode: LaunchMode.platformDefault,
      webOnlyWindowName: '_blank',
    );
    if (!launched && context.mounted) {
      _showError(context, 'Could not open VR tour');
    }
  } catch (e) {
    if (context.mounted) _showError(context, 'Could not open link: $e');
  }
}

void _showError(BuildContext context, String message) {
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Row(
        children: [
          Icon(Icons.error_outline, color: Colors.white, size: 20),
          const SizedBox(width: 12),
          Expanded(child: Text(message)),
        ],
      ),
      backgroundColor: Colors.red.shade700,
      behavior: SnackBarBehavior.floating,
    ),
  );
}

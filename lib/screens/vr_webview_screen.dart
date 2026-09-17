// VR tour launcher — bundled Marzipano (mobile), in-app WebView for hosted tours.

import 'package:flutter/material.dart';
import 'package:atmos_trs_system/config/app_theme.dart';
import 'package:atmos_trs_system/config/vr_tour_config.dart';
import 'package:atmos_trs_system/screens/hosted_vr_tour_screen.dart';
import 'package:atmos_trs_system/screens/simple_image_vr_screen.dart';
import 'package:atmos_trs_system/services/vr_tour_firestore_service.dart';
import 'package:atmos_trs_system/widgets/vr_download_app_prompt.dart';
import 'package:url_launcher/url_launcher.dart';

// -----------------------------------------------------------------------------
// Helper: open VR tour (all platforms)
// -----------------------------------------------------------------------------

/// Opens the VR tour in-app (mobile). On web, tourists are prompted to download
/// the app unless [allowWeb] is true (e.g. tourism staff preview).
Future<void> openVrTour(
  BuildContext context, {
  bool useLocalTour = false,
  String? url,
  String title = 'VR Tour',
  bool allowWeb = false,
}) async {
  if (!context.mounted) return;
  if (!await VrDownloadAppPrompt.ensureAllowed(context, allowWeb: allowWeb)) {
    return;
  }

  final configured = url ?? kVrTourUrl;
  final hosted = hostedVrUrlForLaunch(useLocalTour ? null : configured);

  if (hosted == null || useLocalTour || useBundledTourForUrl(hosted)) {
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        fullscreenDialog: true,
        builder: (_) => BundledVrTourScreen(title: title),
      ),
    );
    return;
  }

  final uri = Uri.tryParse(hosted);
  if (uri == null || (!uri.isScheme('http') && !uri.isScheme('https'))) {
    if (context.mounted) _showError(context, 'Invalid VR tour URL');
    return;
  }
  if (!context.mounted) return;

  if (isClearPanoTourUrl(hosted)) {
    await _openVrTourExternally(
      context,
      uri,
      title: title,
      reason: 'clearpano',
    );
    return;
  }

  await Navigator.of(context).push<void>(
    MaterialPageRoute<void>(
      fullscreenDialog: true,
      builder: (_) => HostedVrTourScreen(url: uri.toString(), title: title),
    ),
  );
}

/// Convenience: open VR tour with URL as first argument after context.
Future<void> openVrTourWithUrl(
  BuildContext context,
  String url, {
  bool allowWeb = false,
}) =>
    openVrTour(context, url: url, allowWeb: allowWeb);

/// Opens hosted VR (Teleport360) or static panorama preview for a tourist spot.
Future<void> openVrForTouristSpot(
  BuildContext context, {
  required String spotId,
  required String spotName,
  String? vrLink,
  String? vrPanoramaUrl,
  String? imageUrl,
  bool allowWeb = false,
}) async {
  if (!context.mounted) return;
  if (!await VrDownloadAppPrompt.ensureAllowed(context, allowWeb: allowWeb)) {
    return;
  }
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
    await openVrTour(
      context,
      url: hosted,
      title: spotName,
      allowWeb: allowWeb,
    );
    return;
  }
  if (isOroquietaPlazaSpot(spotId: spotId, spotName: spotName)) {
    await openVrTour(
      context,
      url: kOroquietaCityPlazaVrUrl,
      title: spotName,
      allowWeb: allowWeb,
    );
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

Future<void> _openVrTourExternally(
  BuildContext context,
  Uri uri, {
  required String title,
  String reason = 'browser',
}) async {
  if (!context.mounted) return;

  final message = reason == 'clearpano'
      ? 'Opening 360° tour in your browser (password may be required)…'
      : 'Opening 360° tour in your browser…';

  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Row(
        children: [
          const Icon(Icons.open_in_new, color: Colors.white, size: 20),
          const SizedBox(width: 12),
          Expanded(child: Text(message)),
        ],
      ),
      backgroundColor: AppTheme.cardBackground,
      duration: const Duration(seconds: 3),
      behavior: SnackBarBehavior.floating,
    ),
  );

  try {
    final launched = await launchUrl(
      uri,
      mode: LaunchMode.externalApplication,
      webOnlyWindowName: '_blank',
    );
    if (!launched && context.mounted) {
      _showError(context, 'Could not open VR tour. Check your internet connection.');
    }
  } catch (e) {
    if (context.mounted) {
      _showError(context, 'Could not open VR tour: $e');
    }
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

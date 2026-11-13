import 'package:atmos_trs_system/config/app_store_links.dart';
import 'package:atmos_trs_system/config/app_theme.dart';
import 'package:atmos_trs_system/services/pending_lgu_checkin_storage.dart';
import 'package:atmos_trs_system/services/pending_spot_checkin_storage.dart';
import 'package:atmos_trs_system/services/qr_launch_bootstrap.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// After QR signup/login on web: offer VR Tour / Trip Planner installs, or
/// dismiss with X to stay on the website only (pending QR is kept).
class QrWebAppInstallPrompt {
  QrWebAppInstallPrompt._();

  static bool _shownThisSession = false;
  static bool _dismissedThisSession = false;

  /// Call when a new camera QR is applied so the prompt can appear again.
  static void resetForNewScan() {
    _shownThisSession = false;
    _dismissedThisSession = false;
  }

  static Future<void> showIfNeeded(
    BuildContext context, {
    bool force = false,
    String? placeName,
  }) async {
    if (!kIsWeb || !context.mounted) return;
    // Fresh post-auth navigation always offers the popup once.
    if (force) {
      _dismissedThisSession = false;
      _shownThisSession = false;
    } else if (_shownThisSession || _dismissedThisSession) {
      return;
    }

    final hasPending = await QrLaunchBootstrap.hasPendingCheckIn();
    if (!hasPending && !force) return;
    if (!context.mounted) return;

    var place = (placeName ?? '').trim();
    if (place.isEmpty) {
      final spot = await PendingSpotCheckInStorage.peek();
      final lgu = await PendingLguCheckInStorage.peek();
      place = spot?.spotName?.trim().isNotEmpty == true
          ? spot!.spotName!.trim()
          : (lgu?.displayName.trim().isNotEmpty == true
              ? lgu!.displayName.trim()
              : 'this destination');
    }

    if (!context.mounted) return;
    _shownThisSession = true;
    final installed = await showDialog<bool>(
      context: context,
      barrierDismissible: true,
      barrierColor: Colors.black.withValues(alpha: 0.55),
      builder: (dialogContext) => _QrWebAppInstallDialog(placeName: place),
    );
    // X, barrier tap, or back = continue on website only.
    if (installed != true) {
      _dismissedThisSession = true;
    }
  }
}

class _QrWebAppInstallDialog extends StatefulWidget {
  const _QrWebAppInstallDialog({required this.placeName});

  final String placeName;

  @override
  State<_QrWebAppInstallDialog> createState() => _QrWebAppInstallDialogState();
}

class _QrWebAppInstallDialogState extends State<_QrWebAppInstallDialog> {
  bool _busy = false;

  void _close({required bool installedSomething}) {
    if (mounted) Navigator.of(context).pop(installedSomething);
  }

  Future<void> _downloadVr() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final ok = kHasAndroidApkDownload
          ? await openAtmosAppDownload(
              target: AtmosAppDownloadTarget.apk,
            )
          : await openAtmosAppDownload(
              target: AtmosAppDownloadTarget.playStore,
            );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            ok
                ? 'Opening VR Tour app download… Install it, then open ATMOS '
                    'to continue at ${widget.placeName}.'
                : 'Could not open the VR Tour download link.',
          ),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 5),
        ),
      );
      if (ok) _close(installedSomething: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _downloadTripPlanner() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final ok = await openTripPlannerApkDownload();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            ok
                ? 'Opening Trip Planner download…'
                : 'Could not open the Trip Planner download link.',
          ),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 5),
        ),
      );
      if (ok) _close(installedSomething: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final accent = AppTheme.brandOrange;
    final isMobile = MediaQuery.sizeOf(context).width < 600;

    return Center(
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: isMobile ? 16 : 24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Material(
            color: Colors.white,
            elevation: 16,
            shadowColor: Colors.black.withValues(alpha: 0.25),
            borderRadius: BorderRadius.circular(22),
            clipBehavior: Clip.antiAlias,
            child: Stack(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(22, 22, 22, 20),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const SizedBox(height: 8),
                      Icon(Icons.smartphone_rounded, size: 40, color: accent),
                      const SizedBox(height: 12),
                      Text(
                        'Install an app?',
                        textAlign: TextAlign.center,
                        style: GoogleFonts.montserrat(
                          color: const Color(0xFF1B2433),
                          fontSize: 22,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'You scanned ${widget.placeName}. Download the VR Tour '
                        'or Trip Planner app, or close this to continue on the '
                        'website.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Colors.grey.shade700,
                          fontSize: 14,
                          height: 1.45,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: 18),
                      FilledButton.icon(
                        onPressed: _busy ? null : _downloadVr,
                        style: FilledButton.styleFrom(
                          backgroundColor: accent,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                        icon: const Icon(Icons.vrpano_rounded, size: 20),
                        label: const Text(
                          'Install VR Tour App',
                          style: TextStyle(fontWeight: FontWeight.w700),
                        ),
                      ),
                      const SizedBox(height: 10),
                      OutlinedButton.icon(
                        onPressed: _busy ? null : _downloadTripPlanner,
                        style: OutlinedButton.styleFrom(
                          foregroundColor: accent,
                          side: BorderSide(
                            color: accent.withValues(alpha: 0.45),
                          ),
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                        icon: const Icon(Icons.map_rounded, size: 20),
                        label: const Text(
                          'Install Trip Planner App',
                          style: TextStyle(fontWeight: FontWeight.w700),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'Close to stay on the web version only.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Colors.grey.shade600,
                          fontSize: 12.5,
                          height: 1.35,
                        ),
                      ),
                    ],
                  ),
                ),
                Positioned(
                  top: 4,
                  right: 4,
                  child: IconButton(
                    tooltip: 'Continue on website',
                    onPressed: _busy
                        ? null
                        : () => _close(installedSomething: false),
                    icon: Icon(
                      Icons.close_rounded,
                      color: Colors.grey.shade700,
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
}

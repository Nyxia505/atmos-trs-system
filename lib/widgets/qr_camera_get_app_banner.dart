import 'dart:async' show unawaited;

import 'package:atmos_trs_system/config/app_store_links.dart';
import 'package:atmos_trs_system/config/app_theme.dart';
import 'package:atmos_trs_system/services/pending_establishment_stay_storage.dart';
import 'package:atmos_trs_system/services/pending_lgu_checkin_storage.dart';
import 'package:atmos_trs_system/services/pending_spot_checkin_storage.dart';
import 'package:atmos_trs_system/services/qr_launch_bootstrap.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

/// Shown on web landing when a camera QR opened the site (app may not be installed).
class QrCameraGetAppBanner extends StatefulWidget {
  const QrCameraGetAppBanner({
    super.key,
    required this.onContinueCheckIn,
  });

  /// Continues the web check-in / signup path for the pending QR.
  final VoidCallback onContinueCheckIn;

  @override
  State<QrCameraGetAppBanner> createState() => _QrCameraGetAppBannerState();
}

class _QrCameraGetAppBannerState extends State<QrCameraGetAppBanner> {
  bool _visible = false;
  String _placeLabel = 'this place';
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    if (!kIsWeb) return;
    final has = await QrLaunchBootstrap.hasPendingCheckIn() ||
        QrLaunchBootstrap.appliedFromLaunchUrl;
    if (!has || !mounted) return;

    String label = 'this place';
    final est = await PendingEstablishmentStayStorage.peek();
    if (est != null) {
      label = (est.businessName?.trim().isNotEmpty == true)
          ? est.businessName!.trim()
          : 'this establishment';
    } else {
      final spot = await PendingSpotCheckInStorage.peek();
      if (spot != null) {
        label = (spot.spotName?.trim().isNotEmpty == true)
            ? spot.spotName!.trim()
            : 'this tourist spot';
      } else {
        final lgu = await PendingLguCheckInStorage.peek();
        if (lgu != null) label = lgu.displayName;
      }
    }

    if (!mounted) return;
    setState(() {
      _visible = true;
      _placeLabel = label;
    });
  }

  Future<void> _download(AtmosAppDownloadTarget target) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final ok = await openAtmosAppDownload(target: target);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            ok
                ? 'Opening download… After install, open ATMOS — we saved your QR when possible. '
                    'If check-in does not resume, scan the same QR again.'
                : 'Could not open the download link.',
          ),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 6),
        ),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_visible) return const SizedBox.shrink();

    final accent = AppTheme.primary;
    return Material(
      color: Colors.transparent,
      child: Container(
        width: double.infinity,
        margin: const EdgeInsets.fromLTRB(16, 12, 16, 8),
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: accent.withValues(alpha: 0.35)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.08),
              blurRadius: 16,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: accent.withValues(alpha: 0.12),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(Icons.qr_code_scanner_rounded, color: accent),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'QR check-in ready',
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 16,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'You scanned $_placeLabel. Get the ATMOS app for the full flow, or continue here.',
                        style: TextStyle(
                          fontSize: 13,
                          height: 1.35,
                          color: Colors.grey.shade700,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            if (kHasAndroidApkDownload) ...[
              FilledButton.icon(
                onPressed: _busy
                    ? null
                    : () => _download(AtmosAppDownloadTarget.apk),
                style: FilledButton.styleFrom(
                  backgroundColor: accent,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
                icon: const Icon(Icons.smartphone_rounded, size: 20),
                label: const Text(
                  'Get the ATMOS app',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
              const SizedBox(height: 8),
            ],
            FilledButton.icon(
              onPressed: _busy
                  ? null
                  : () => _download(AtmosAppDownloadTarget.playStore),
              style: FilledButton.styleFrom(
                backgroundColor: kHasAndroidApkDownload
                    ? accent.withValues(alpha: 0.9)
                    : accent,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
              icon: const Icon(Icons.android_rounded, size: 20),
              label: const Text(
                'Get it on Google Play',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
            const SizedBox(height: 8),
            OutlinedButton(
              onPressed: _busy ? null : widget.onContinueCheckIn,
              style: OutlinedButton.styleFrom(
                foregroundColor: accent,
                side: BorderSide(color: accent.withValues(alpha: 0.45)),
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
              child: const Text(
                'Continue check-in on website',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

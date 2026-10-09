import 'package:atmos_trs_system/config/app_store_links.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

/// VR access policy (option B): playable in the **mobile ATMOS app only**.
///
/// - Landing + tourist web: tapping a VR CTA downloads the ATMOS Android APK
///   directly (no playable VR in the browser).
/// - Tourism dashboard staff preview may pass [ensureAllowed] `allowWeb: true`.
class VrDownloadAppPrompt {
  VrDownloadAppPrompt._();

  static bool get blocksVrOnWeb => kIsWeb;

  /// Button / chip label for tourist VR CTAs.
  static String ctaLabel({String mobileLabel = 'Launch VR Tour'}) =>
      blocksVrOnWeb ? 'Get the App for VR' : mobileLabel;

  /// Returns `true` when VR may open. On web (without [allowWeb]), starts the
  /// app download and returns `false`.
  static Future<bool> ensureAllowed(
    BuildContext context, {
    bool allowWeb = false,
  }) async {
    if (!blocksVrOnWeb || allowWeb) return true;
    await show(context);
    return false;
  }

  /// Starts the ATMOS app download (APK, or Play Store when no APK is hosted).
  static Future<void> show(BuildContext context) async {
    if (!context.mounted) return;
    final url = kHasAndroidApkDownload
        ? kAndroidApkDownloadUrl
        : kGooglePlayStoreAppUrl;
    final messenger = ScaffoldMessenger.maybeOf(context);

    var opened = false;
    final uri = Uri.tryParse(url);
    if (uri != null) {
      try {
        opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
      } catch (_) {
        opened = false;
      }
    }

    messenger?.hideCurrentSnackBar();
    messenger?.showSnackBar(
      SnackBar(
        content: Text(
          opened
              ? 'Downloading the ATMOS app — install it on your Android phone '
                  'to explore destinations in 360° VR.'
              : 'Could not open the download link.',
        ),
        duration: const Duration(seconds: 5),
      ),
    );
  }
}

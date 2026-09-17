import 'package:atmos_trs_system/config/app_store_links.dart';
import 'package:atmos_trs_system/config/app_theme.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

/// VR tours are mobile-app only. On web, tourists are prompted to download the app.
class VrDownloadAppPrompt {
  VrDownloadAppPrompt._();

  static const double _maxDialogWidth = 340;

  static bool get blocksVrOnWeb => kIsWeb;

  /// Returns `true` when VR may open. On web (without [allowWeb]), shows the
  /// download prompt and returns `false`.
  static Future<bool> ensureAllowed(
    BuildContext context, {
    bool allowWeb = false,
  }) async {
    if (!blocksVrOnWeb || allowWeb) return true;
    await show(context);
    return false;
  }

  static Future<void> show(BuildContext context) async {
    if (!context.mounted) return;
    final accent = AppTheme.primary;

    await showDialog<void>(
      context: context,
      builder: (ctx) {
        final screenWidth = MediaQuery.sizeOf(ctx).width;
        final dialogWidth = screenWidth > _maxDialogWidth + 48
            ? _maxDialogWidth
            : screenWidth - 32;

        return Dialog(
          insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          child: SizedBox(
            width: dialogWidth,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: accent.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Icon(Icons.vrpano_rounded, color: accent, size: 24),
                      ),
                      const SizedBox(width: 12),
                      const Expanded(
                        child: Text(
                          'VR tours are in the app',
                          style: TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Text(
                    'VR tours unlock on your phone in the ATMOS app — they can\'t '
                    'be viewed in the browser. Get the ATMOS app to explore '
                    'destinations in immersive 360° VR. QR check-in and your '
                    'digital tourist ID are also in the app.',
                    style: TextStyle(
                      height: 1.45,
                      color: Colors.grey.shade700,
                      fontSize: 14,
                    ),
                  ),
                  const SizedBox(height: 18),
                  if (kHasAndroidApkDownload) ...[
                    FilledButton.icon(
                      onPressed: () => _openStore(ctx, kAndroidApkDownloadUrl),
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
                    onPressed: () => _openStore(ctx, kGooglePlayStoreAppUrl),
                    style: FilledButton.styleFrom(
                      backgroundColor: kHasAndroidApkDownload
                          ? accent.withValues(alpha: 0.92)
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
                  OutlinedButton.icon(
                    onPressed: () => _openStore(ctx, kAppStoreAppUrl),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: accent,
                      side: BorderSide(color: accent.withValues(alpha: 0.45)),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                    icon: const Icon(Icons.phone_iphone_rounded, size: 20),
                    label: const Text(
                      'Open in ATMOS app (iOS)',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                  const SizedBox(height: 4),
                  TextButton(
                    onPressed: () => Navigator.pop(ctx),
                    child: const Text('Not now'),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  static Future<void> _openStore(BuildContext context, String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null) return;
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Could not open the download link.'),
          ),
        );
      }
    }
  }
}

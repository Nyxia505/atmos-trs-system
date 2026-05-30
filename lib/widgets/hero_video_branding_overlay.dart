import 'package:flutter/material.dart';

/// Misamis Occidental / Asenso branding on hero video: wordmark **left**,
/// two circular seals **right** in a horizontal row.
///
/// Asset files: [assets/images/] (see `pubspec.yaml`). For true transparency, use PNGs with
/// an alpha channel; baked-in white boxes cannot be removed reliably in Flutter alone.
class HeroVideoBrandingOverlay extends StatelessWidget {
  const HeroVideoBrandingOverlay({
    super.key,
    this.compact = false,
  });

  /// Landing hero uses [compact]. Narrow phones always get tighter sizing.
  final bool compact;

  static const String circularLogo =
      'assets/images/asenso_misamis_occidental_circular_logo.png';
  static const String wordmarkLogo =
      'assets/images/asenso_misamis_occidental_wordmark.png';
  static const String officialSeal =
      'assets/images/misamis_occidental_official_seal.png';

  static Widget _circleAsset(String path, double size) {
    return ClipOval(
      child: SizedBox(
        width: size,
        height: size,
        child: Image.asset(
          path,
          width: size,
          height: size,
          fit: BoxFit.cover,
          filterQuality: FilterQuality.high,
          errorBuilder: (_, __, ___) => SizedBox(width: size, height: size),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final w = MediaQuery.sizeOf(context).width;
    final narrowPhone = w < 520;

    /// Phone-sized layout: smaller wordmark + seals so the strip matches the center pill.
    final tight = compact || narrowPhone;

    final circle = (w * (tight ? 0.068 : 0.095))
        .clamp(tight ? 24.0 : 30.0, tight ? 34.0 : 46.0);
    final wordW = (w * (tight ? 0.17 : 0.30))
        .clamp(tight ? 52.0 : 72.0, tight ? 78.0 : 132.0);
    final wordMaxH = tight ? 34.0 : 48.0;

    return IgnorePointer(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          tight ? 4 : 8,
          tight ? 14 : 14,
          tight ? 4 : 8,
          tight ? 1 : 2,
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
              child: Align(
                alignment: Alignment.centerLeft,
                child: Padding(
                  padding: EdgeInsets.only(top: tight ? 6 : 8),
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      maxWidth: wordW,
                      maxHeight: wordMaxH,
                    ),
                    child: Image.asset(
                      wordmarkLogo,
                      fit: BoxFit.contain,
                      alignment: Alignment.centerLeft,
                      filterQuality: FilterQuality.high,
                      errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                    ),
                  ),
                ),
              ),
            ),
            SizedBox(width: tight ? 4 : 6),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _circleAsset(circularLogo, circle),
                SizedBox(width: tight ? 4 : 6),
                _circleAsset(officialSeal, circle),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

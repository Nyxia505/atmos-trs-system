import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image/image.dart' as img;

const String _kLogoAsset = 'assets/images/logo.png';

/// Cached logo bytes with white/near-white pixels made transparent.
Uint8List? _cachedLogoNoWhite;

/// Loads logo from assets and sets alpha to 0 for white/near-white pixels.
/// Result is cached so subsequent calls return the same bytes.
Future<Uint8List?> loadLogoWithoutWhiteBackground() async {
  if (_cachedLogoNoWhite != null) return _cachedLogoNoWhite;
  try {
    final data = await rootBundle.load(_kLogoAsset);
    final bytes = data.buffer.asUint8List();
    final image = img.decodeImage(bytes);
    if (image == null) return null;
    const threshold = 250;
    for (int y = 0; y < image.height; y++) {
      for (int x = 0; x < image.width; x++) {
        final p = image.getPixel(x, y);
        final r = p.r.toInt(), g = p.g.toInt(), b = p.b.toInt();
        if (r >= threshold && g >= threshold && b >= threshold) {
          image.setPixelRgba(x, y, r, g, b, 0);
        }
      }
    }
    final out = img.encodePng(image);
    _cachedLogoNoWhite = Uint8List.fromList(out);
    return _cachedLogoNoWhite;
  } catch (_) {
    return null;
  }
}

Future<Uint8List?>? _logoFuture;

/// One-time future for loading logo without white background (for use in FutureBuilder).
Future<Uint8List?> get logoWithoutWhiteFuture =>
    _logoFuture ??= loadLogoWithoutWhiteBackground();

/// Logo image with white background removed. Uses cached load; fallback to asset if load fails.
class TransparentLogo extends StatelessWidget {
  const TransparentLogo({
    super.key,
    this.width,
    this.height,
    this.fit = BoxFit.contain,
    this.errorIcon,
    this.errorIconSize = 28.0,
    this.errorIconColor,
  });

  final double? width;
  final double? height;
  final BoxFit fit;
  final IconData? errorIcon;
  final double errorIconSize;
  final Color? errorIconColor;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Uint8List?>(
      future: logoWithoutWhiteFuture,
      builder: (context, snapshot) {
        final bytes = snapshot.data;
        if (bytes != null && bytes.isNotEmpty) {
          return Image.memory(
            bytes,
            width: width,
            height: height,
            fit: fit,
            errorBuilder: (_, __, ___) => _fallback(context),
          );
        }
        return _fallback(context);
      },
    );
  }

  Widget _fallback(BuildContext context) {
    return Image.asset(
      _kLogoAsset,
      width: width,
      height: height,
      fit: fit,
      errorBuilder: (_, __, ___) => Icon(
        errorIcon ?? Icons.public,
        size: errorIconSize,
        color: errorIconColor ?? Theme.of(context).colorScheme.primary,
      ),
    );
  }
}

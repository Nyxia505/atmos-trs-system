import 'dart:io';
import 'dart:math' as math;

import 'package:image/image.dart' as img;

/// Generates Android notification icons from the launcher logo:
/// - `drawable-*dpi/ic_stat_atmos.png`: white-on-transparent silhouette
///   (Android renders the status-bar small icon from alpha only, so the
///   full-colour logo on white shows as a blank square).
/// - `drawable-nodpi/ic_notification_logo.png`: full-colour large icon.
///
/// Run from repo root: `dart run tools/gen_notification_icons.dart`
void main() {
  const res = 'android/app/src/main/res';
  const srcPath = '$res/mipmap-xxxhdpi/ic_launcher.png';
  final src = img.decodePng(File(srcPath).readAsBytesSync());
  if (src == null) {
    stderr.writeln('Failed to decode $srcPath');
    exit(1);
  }

  // Alpha = how far each pixel is from the white background.
  final mask = img.Image(width: src.width, height: src.height, numChannels: 4);
  var minX = src.width, minY = src.height, maxX = -1, maxY = -1;
  for (final p in src) {
    final r = p.r.toInt(), g = p.g.toInt(), b = p.b.toInt();
    final srcAlpha = p.a.toInt();
    final hi = math.max(r, math.max(g, b));
    final lo = math.min(r, math.min(g, b));
    final saturation = hi - lo;
    final darkness = 255 - lo;
    final strength = math.max(saturation, darkness);
    // Ramp 18..60 so anti-aliased edges stay smooth and paper-white drops out.
    var a = ((strength - 18) * 255 / 42).round().clamp(0, 255);
    a = (a * srcAlpha / 255).round();
    mask.setPixelRgba(p.x, p.y, 255, 255, 255, a);
    if (a > 40) {
      minX = math.min(minX, p.x);
      minY = math.min(minY, p.y);
      maxX = math.max(maxX, p.x);
      maxY = math.max(maxY, p.y);
    }
  }
  if (maxX < 0) {
    stderr.writeln('No logo pixels found.');
    exit(1);
  }

  final cropped = img.copyCrop(
    mask,
    x: minX,
    y: minY,
    width: maxX - minX + 1,
    height: maxY - minY + 1,
  );
  final side = (math.max(cropped.width, cropped.height) * 1.12).round();
  final square = img.Image(width: side, height: side, numChannels: 4);
  img.compositeImage(
    square,
    cropped,
    dstX: ((side - cropped.width) / 2).round(),
    dstY: ((side - cropped.height) / 2).round(),
  );

  const sizes = {
    'mdpi': 24,
    'hdpi': 36,
    'xhdpi': 48,
    'xxhdpi': 72,
    'xxxhdpi': 96,
  };
  sizes.forEach((density, px) {
    final dir = Directory('$res/drawable-$density')..createSync(recursive: true);
    final out = img.copyResize(
      square,
      width: px,
      height: px,
      interpolation: img.Interpolation.average,
    );
    final path = '${dir.path}/ic_stat_atmos.png';
    File(path).writeAsBytesSync(img.encodePng(out));
    stdout.writeln('Wrote $path (${px}x$px)');
  });

  final nodpi = Directory('$res/drawable-nodpi')..createSync(recursive: true);
  final largePath = '${nodpi.path}/ic_notification_logo.png';
  File(largePath).writeAsBytesSync(img.encodePng(src));
  stdout.writeln('Wrote $largePath (${src.width}x${src.height})');
}

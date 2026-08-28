import 'dart:io';

import 'package:image/image.dart' as img;

/// Compresses landing hero photo for Flutter web (large PNGs often fail to decode).
void main() {
  const src = 'assets/images/BG in landing page.png';
  const outJpg = 'assets/images/landing_page_bg.jpg';

  final raw = File(src).readAsBytesSync();
  final decoded = img.decodeImage(raw);
  if (decoded == null) {
    stderr.writeln('Failed to decode $src');
    exit(1);
  }

  final resized = img.copyResize(
    decoded,
    width: decoded.width > 1920 ? 1920 : decoded.width,
  );

  File(outJpg).writeAsBytesSync(img.encodeJpg(resized, quality: 82));

  stdout.writeln(
    'Wrote ${File(outJpg).lengthSync()} bytes -> $outJpg',
  );
}

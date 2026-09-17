import 'dart:io';

import 'package:image/image.dart' as img;

/// Builds the official ATMOS-TRS horizontal brand lockup on white with padding
/// and light sharpening. Source must be the provided orange banner artwork.
void main(List<String> args) {
  const defaultSrc =
      r'C:\Users\Melane\.cursor\projects\c-atmos-trs-system\assets\c__Users_Melane_AppData_Roaming_Cursor_User_workspaceStorage_2a65de5ad0730f5e6ea9e9496c81118c_images_image-5557cbbf-a179-4d40-8b5f-75012ca84183.png';
  const outPath = 'assets/images/atmos_trs_brand_logo.png';

  final srcPath = args.isNotEmpty ? args.first : defaultSrc;
  final raw = File(srcPath).readAsBytesSync();
  final decoded = img.decodeImage(raw);
  if (decoded == null) {
    stderr.writeln('Failed to decode $srcPath');
    exit(1);
  }

  // Upscale low-res uploads for crisp rendering on retina / wide headers.
  img.Image logo = decoded;
  if (logo.width < 1400) {
    logo = img.copyResize(
      logo,
      width: (logo.width * (1400 / logo.width)).round(),
      interpolation: img.Interpolation.cubic,
    );
  }

  // Subtle sharpen — preserves colors and layout.
  logo = img.convolution(
    logo,
    filter: [0, -0.5, 0, -0.5, 3, -0.5, 0, -0.5, 0],
    div: 1,
  );

  const padX = 0.14;
  const padY = 0.22;
  final canvasW = (logo.width * (1 + padX * 2)).round();
  final canvasH = (logo.height * (1 + padY * 2)).round();
  final canvas = img.Image(width: canvasW, height: canvasH);
  img.fill(canvas, color: img.ColorRgb8(255, 255, 255));

  final offsetX = ((canvasW - logo.width) / 2).round();
  final offsetY = ((canvasH - logo.height) / 2).round();
  img.compositeImage(canvas, logo, dstX: offsetX, dstY: offsetY);

  File(outPath).writeAsBytesSync(img.encodePng(canvas, level: 1));
  stdout.writeln(
    'Wrote ${File(outPath).lengthSync()} bytes -> $outPath '
    '(${canvasW}x$canvasH)',
  );
}

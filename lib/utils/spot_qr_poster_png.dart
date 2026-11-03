import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:atmos_trs_system/utils/spot_qr_poster.dart';
import 'package:flutter/material.dart';

/// Renders the shared A4 QR poster as a 2480 × 3508 PNG.
Future<Uint8List> renderSpotQrPosterPng(SpotQrPosterData data) async {
  final payload = data.payload.trim();
  if (payload.isEmpty) {
    throw StateError('This tourist spot has no QR payload to export.');
  }

  final assets = await SpotQrPosterAssets.load();
  final qr = SpotQrModules.encode(payload);
  const layout = SpotQrPosterLayout.a4;
  final scale = layout.pngScale;

  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);

  canvas.save();
  canvas.scale(scale);
  _paintPosterChrome(canvas, layout, data, assets);
  canvas.restore();

  paintQrModulesSharp(canvas, layout.qrRect, scale, qr);

  final picture = recorder.endRecording();
  final image = await picture.toImage(
    SpotQrPosterLayout.pngWidthPx,
    SpotQrPosterLayout.pngHeightPx,
  );
  picture.dispose();
  final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
  image.dispose();
  if (bytes == null) {
    throw StateError('Could not encode the QR poster PNG.');
  }
  return bytes.buffer.asUint8List();
}

void _paintPosterChrome(
  Canvas canvas,
  SpotQrPosterLayout layout,
  SpotQrPosterData data,
  SpotQrPosterAssets assets,
) {
  const page = Rect.fromLTWH(
    0,
    0,
    SpotQrPosterLayout.pageWidthPt,
    SpotQrPosterLayout.pageHeightPt,
  );
  canvas.drawRect(page, Paint()..color = kPosterPage);

  for (final fill in posterDecorationFills(layout)) {
    canvas.drawPath(fill.path.toUiPath(), Paint()..color = fill.color);
  }
  for (final circle in posterDecorationCircles(layout)) {
    canvas.drawCircle(
      Offset(circle.cx, circle.cy),
      circle.radius,
      Paint()..color = circle.color,
    );
  }

  final logo = assets.logoImage;
  if (logo != null) {
    final rect = layout.logoRect;
    final src = Rect.fromLTWH(
      0,
      0,
      logo.width.toDouble(),
      logo.height.toDouble(),
    );
    final dst = Rect.fromLTWH(rect.left, rect.top, rect.width, rect.height);
    final fitted = applyBoxFit(BoxFit.contain, src.size, dst.size);
    final input = Alignment.center.inscribe(fitted.source, src);
    final output = Alignment.center.inscribe(fitted.destination, dst);
    canvas.drawImageRect(
      logo,
      input,
      output,
      Paint()..filterQuality = FilterQuality.high,
    );
  }

  _drawText(
    canvas,
    text: kSpotQrPosterBrand,
    box: layout.brandRect,
    fontFamily: assets.boldFont,
    fontSize: 22,
    color: kPosterOrange,
    letterSpacing: 1.6,
    maxLines: 1,
  );

  _drawDivider(canvas, layout);

  _drawText(
    canvas,
    text: data.displayName,
    box: layout.nameRect,
    fontFamily: assets.boldFont,
    fontSize: 26,
    color: kPosterBrown,
    maxLines: 3,
    height: 1.15,
  );

  _drawMunicipality(canvas, layout, data, assets);
  _drawCard(canvas, layout);
  _drawScanPill(canvas, layout, assets);
  _drawInstruction(canvas, layout, assets);
  _drawFooter(canvas, layout, assets);
}

void _drawDivider(Canvas canvas, SpotQrPosterLayout layout) {
  const w = SpotQrPosterLayout.pageWidthPt;
  final y = layout.dividerY;
  final paint = Paint()
    ..color = kPosterGold
    ..strokeWidth = 1.4
    ..style = PaintingStyle.stroke;
  canvas.drawLine(Offset(w / 2 - 92, y), Offset(w / 2 - 12, y), paint);
  canvas.drawLine(Offset(w / 2 + 12, y), Offset(w / 2 + 92, y), paint);
  canvas.drawCircle(Offset(w / 2, y), 3.2, Paint()..color = kPosterOrangeMid);
}

void _drawMunicipality(
  Canvas canvas,
  SpotQrPosterLayout layout,
  SpotQrPosterData data,
  SpotQrPosterAssets assets,
) {
  final label = data.displayMunicipality;
  if (label.isEmpty) return;
  final box = layout.municipalityRect;
  canvas.drawPath(
    pinPath(box.centerX - 64, box.centerY - 2, 1).toUiPath(),
    Paint()..color = kPosterOrange,
  );
  canvas.drawCircle(
    Offset(box.centerX - 64, box.centerY - 4),
    2.2,
    Paint()..color = kPosterWhite,
  );
  _drawText(
    canvas,
    text: label,
    box: PosterRect(box.left + 18, box.top, box.width - 18, box.height),
    fontFamily: assets.regularFont,
    fontSize: 12.5,
    color: kPosterMuted,
    maxLines: 1,
  );
}

void _drawCard(Canvas canvas, SpotQrPosterLayout layout) {
  final r = layout.cardRect;
  final rect = RRect.fromLTRBR(
    r.left,
    r.top,
    r.right,
    r.bottom,
    const Radius.circular(22),
  );
  canvas.drawRRect(
    rect.shift(const Offset(0, 3)),
    Paint()..color = const Color(0x22EA580C),
  );
  canvas.drawRRect(rect, Paint()..color = kPosterWhite);
  canvas.drawRRect(
    rect,
    Paint()
      ..color = const Color(0xFFFFE4C8)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2,
  );
  canvas.drawPath(
    scanFramePath(layout.qrFrameRect).toUiPath(),
    Paint()..color = kPosterOrangeMid,
  );
}

void _drawScanPill(
  Canvas canvas,
  SpotQrPosterLayout layout,
  SpotQrPosterAssets assets,
) {
  final r = layout.scanPillRect;
  final pill = RRect.fromLTRBR(
    r.left,
    r.top,
    r.right,
    r.bottom,
    const Radius.circular(20),
  );
  canvas.drawRRect(pill, Paint()..color = kPosterOrange);
  _drawText(
    canvas,
    text: kSpotQrPosterScanHeading,
    box: r,
    fontFamily: assets.boldFont,
    fontSize: 13,
    color: kPosterWhite,
    letterSpacing: 0.8,
    maxLines: 1,
  );
}

void _drawInstruction(
  Canvas canvas,
  SpotQrPosterLayout layout,
  SpotQrPosterAssets assets,
) {
  final box = layout.instructionRect;
  final iconBox = PosterRect(box.left + 36, box.top + 10, 22, 22);
  final iconPaint = Paint()
    ..color = kPosterOrange
    ..style = PaintingStyle.stroke
    ..strokeWidth = 2
    ..strokeCap = StrokeCap.round
    ..strokeJoin = StrokeJoin.round;
  canvas.drawPath(_scanGlyphPath(iconBox), iconPaint);
  _drawText(
    canvas,
    text: kSpotQrPosterInstruction,
    box: PosterRect(box.left + 64, box.top, box.width - 80, box.height),
    fontFamily: assets.regularFont,
    fontSize: 11,
    color: kPosterBrown,
    maxLines: 3,
    height: 1.25,
    align: TextAlign.left,
  );
}

void _drawFooter(
  Canvas canvas,
  SpotQrPosterLayout layout,
  SpotQrPosterAssets assets,
) {
  final r = layout.footerRect;
  final pill = RRect.fromLTRBR(
    r.left,
    r.top,
    r.right,
    r.bottom,
    const Radius.circular(16),
  );
  canvas.drawRRect(pill, Paint()..color = kPosterOrange);
  _drawText(
    canvas,
    text: kSpotQrPosterFooter,
    box: r,
    fontFamily: assets.boldFont,
    fontSize: 10,
    color: kPosterWhite,
    maxLines: 1,
  );
}

ui.Path _scanGlyphPath(PosterRect box) {
  const arm = 7.0;
  final path = ui.Path();
  void corner(double x, double y, double dx, double dy) {
    path
      ..moveTo(x, y + dy * arm)
      ..lineTo(x, y)
      ..lineTo(x + dx * arm, y);
  }

  corner(box.left, box.top, 1, 1);
  corner(box.right, box.top, -1, 1);
  corner(box.left, box.bottom, 1, -1);
  corner(box.right, box.bottom, -1, -1);
  return path;
}

void _drawText(
  Canvas canvas, {
  required String text,
  required PosterRect box,
  required String fontFamily,
  required double fontSize,
  required Color color,
  int maxLines = 2,
  double letterSpacing = 0,
  double height = 1.2,
  TextAlign align = TextAlign.center,
}) {
  final builder = ui.ParagraphBuilder(
    ui.ParagraphStyle(
      textAlign: align,
      fontFamily: fontFamily,
      fontSize: fontSize,
      maxLines: maxLines,
      ellipsis: '',
      height: height,
    ),
  )
    ..pushStyle(
      ui.TextStyle(
        color: color,
        fontFamily: fontFamily,
        fontSize: fontSize,
        letterSpacing: letterSpacing,
        height: height,
      ),
    )
    ..addText(text);
  final paragraph = builder.build()
    ..layout(ui.ParagraphConstraints(width: box.width));
  final dy = box.top +
      (box.height - paragraph.height).clamp(0, box.height) / 2;
  canvas.drawParagraph(paragraph, Offset(box.left, dy));
}

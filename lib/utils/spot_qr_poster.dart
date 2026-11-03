import 'dart:ui' as ui;

import 'package:atmos_trs_system/utils/logo_utils.dart';
import 'package:atmos_trs_system/utils/spot_qr_helper.dart';
import 'package:atmos_trs_system/widgets/atmos_brand_logo.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';

/// Shared ATMOS TRS tourist-spot QR check-in poster (PNG + PDF).
///
/// Layout units are A4 PDF points (1/72 in). PNG multiplies by [pngScale]
/// to reach 2480 × 3508 px (A4 at 300 dpi).

const String kSpotQrPosterBrand = 'ATMOS-TRS';
const String kSpotQrPosterScanHeading = 'SCAN TO CHECK IN';
const String kSpotQrPosterInstruction =
    'Use the ATMOS TRS Tourist App to scan this QR code and check in.';
const String kSpotQrPosterFooter = 'For tourist check-in only.';

const String _kFontRegularAsset = 'assets/fonts/noto_sans/NotoSans-Regular.ttf';
const String _kFontBoldAsset = 'assets/fonts/noto_sans/NotoSans-Bold.ttf';

const Color kPosterOrange = Color(0xFFEA580C);
const Color kPosterOrangeMid = Color(0xFFF97316);
const Color kPosterOrangeSoft = Color(0xFFFFEDD5);
const Color kPosterPeach = Color(0xFFFFF7ED);
const Color kPosterGold = Color(0xFFFDBA74);
const Color kPosterBrown = Color(0xFF3F2A14);
const Color kPosterMuted = Color(0xFF7C5A3A);
const Color kPosterWhite = Color(0xFFFFFFFF);
const Color kPosterPage = Color(0xFFFFFBF7);

class PosterRect {
  const PosterRect(this.left, this.top, this.width, this.height);

  final double left;
  final double top;
  final double width;
  final double height;

  double get right => left + width;
  double get bottom => top + height;
  double get centerX => left + width / 2;
  double get centerY => top + height / 2;
}

/// A4 portrait geometry shared by both exporters.
class SpotQrPosterLayout {
  const SpotQrPosterLayout();

  static const SpotQrPosterLayout a4 = SpotQrPosterLayout();

  static const double pageWidthPt = 595.28;
  static const double pageHeightPt = 841.89;
  static const int pngWidthPx = 2480;
  static const int pngHeightPx = 3508;

  /// Device pixels per PDF point for the 300 dpi PNG.
  double get pngScale => pngWidthPx / pageWidthPt;

  double get contentLeft => 52;
  double get contentWidth => pageWidthPt - 104;

  PosterRect get logoRect {
    const size = 78.0;
    return PosterRect((pageWidthPt - size) / 2, 40, size, size);
  }

  PosterRect get brandRect =>
      PosterRect(contentLeft, 126, contentWidth, 26);

  double get dividerY => 160;

  PosterRect get nameRect =>
      PosterRect(contentLeft, 174, contentWidth, 64);

  PosterRect get municipalityRect =>
      PosterRect(contentLeft, 240, contentWidth, 22);

  PosterRect get cardRect => const PosterRect(64, 276, 467.28, 428);

  PosterRect get scanPillRect {
    const w = 248.0;
    const h = 34.0;
    return PosterRect((pageWidthPt - w) / 2, 292, w, h);
  }

  /// QR including quiet zone. Kept well inside the card, away from decorations.
  PosterRect get qrRect {
    const size = 268.0;
    return PosterRect((pageWidthPt - size) / 2, 342, size, size);
  }

  /// Orange corner ticks around the QR, outside the quiet zone.
  PosterRect get qrFrameRect {
    final q = qrRect;
    return PosterRect(q.left - 18, q.top - 12, q.width + 36, q.height + 24);
  }

  PosterRect get instructionRect =>
      PosterRect(contentLeft + 12, 622, contentWidth - 24, 48);

  PosterRect get footerRect {
    const w = 210.0;
    const h = 26.0;
    return PosterRect((pageWidthPt - w) / 2, 718, w, h);
  }

  double get landscapeTop => 754;
}

class SpotQrPosterData {
  const SpotQrPosterData({
    required this.spotName,
    required this.municipalityName,
    required this.payload,
    this.category = '',
  });

  final String spotName;
  final String municipalityName;
  final String payload;
  final String category;

  String get displayName =>
      spotName.trim().isEmpty ? 'Tourist Spot' : spotName.trim();

  String get displayMunicipality => municipalityName.trim();
}

class SpotQrModules {
  SpotQrModules._(this._image);

  final QrImage _image;

  int get moduleCount => _image.moduleCount;

  bool isDark(int row, int col) => _image.isDark(row, col);

  /// Encodes [payload] exactly; does not alter the string.
  static SpotQrModules encode(String payload) {
    final result = QrValidator.validate(
      data: payload,
      version: QrVersions.auto,
      errorCorrectionLevel: QrErrorCorrectLevel.H,
    );
    if (!result.isValid || result.qrCode == null) {
      throw StateError(
        'Could not encode the saved QR payload for this tourist spot.',
      );
    }
    return SpotQrModules._(QrImage(result.qrCode!));
  }
}

/// Prefer the stored check-in payload. Never rewrite a saved URL.
String resolveSpotQrPayload({
  required String municipalityId,
  required String spotId,
  String? savedPayload,
  double? latitude,
  double? longitude,
}) {
  final stored = (savedPayload ?? '').trim();
  if (stored.isNotEmpty) return stored;
  return spotQrData(
    municipalityId,
    spotId,
    latitude: latitude,
    longitude: longitude,
  );
}

SpotQrPosterData buildSpotQrPosterData({
  required String municipalityId,
  required String spotId,
  required String spotName,
  required String municipalityDisplayName,
  String? qrPayload,
  String? category,
  double? latitude,
  double? longitude,
}) {
  return SpotQrPosterData(
    spotName: spotName,
    municipalityName: municipalityDisplayName,
    category: (category ?? '').trim(),
    payload: resolveSpotQrPayload(
      municipalityId: municipalityId,
      spotId: spotId,
      savedPayload: qrPayload,
      latitude: latitude,
      longitude: longitude,
    ),
  );
}

String spotQrPosterFilename(String spotName, String extension) {
  var slug = spotName.trim().replaceAll(RegExp(r'\s+'), '_');
  slug = slug.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '');
  slug = slug.replaceAll(RegExp(r'_+'), '_');
  slug = slug.replaceAll(RegExp(r'^_|_$'), '');
  if (slug.isEmpty) slug = 'Spot';
  if (slug.length > 60) slug = slug.substring(0, 60);
  final ext = extension.startsWith('.') ? extension.substring(1) : extension;
  return 'ATMOS_TRS_${slug}_QR.$ext';
}

enum _PathOpKind { move, line, cubic, close }

class _PathOp {
  const _PathOp.move(this.x, this.y)
      : kind = _PathOpKind.move,
        x1 = 0,
        y1 = 0,
        x2 = 0,
        y2 = 0;
  const _PathOp.line(this.x, this.y)
      : kind = _PathOpKind.line,
        x1 = 0,
        y1 = 0,
        x2 = 0,
        y2 = 0;
  const _PathOp.cubic(
    this.x1,
    this.y1,
    this.x2,
    this.y2,
    this.x,
    this.y,
  ) : kind = _PathOpKind.cubic;
  const _PathOp.close()
      : kind = _PathOpKind.close,
        x = 0,
        y = 0,
        x1 = 0,
        y1 = 0,
        x2 = 0,
        y2 = 0;

  final _PathOpKind kind;
  final double x;
  final double y;
  final double x1;
  final double y1;
  final double x2;
  final double y2;
}

/// Closed vector path in top-left A4 coordinates (shared by PNG and PDF).
class PosterPath {
  PosterPath();

  final List<_PathOp> _ops = <_PathOp>[];

  void moveTo(double x, double y) => _ops.add(_PathOp.move(x, y));
  void lineTo(double x, double y) => _ops.add(_PathOp.line(x, y));
  void cubicTo(
    double x1,
    double y1,
    double x2,
    double y2,
    double x3,
    double y3,
  ) =>
      _ops.add(_PathOp.cubic(x1, y1, x2, y2, x3, y3));
  void close() => _ops.add(const _PathOp.close());

  ui.Path toUiPath({double scale = 1}) {
    final path = ui.Path();
    for (final op in _ops) {
      switch (op.kind) {
        case _PathOpKind.move:
          path.moveTo(op.x * scale, op.y * scale);
        case _PathOpKind.line:
          path.lineTo(op.x * scale, op.y * scale);
        case _PathOpKind.cubic:
          path.cubicTo(
            op.x1 * scale,
            op.y1 * scale,
            op.x2 * scale,
            op.y2 * scale,
            op.x * scale,
            op.y * scale,
          );
        case _PathOpKind.close:
          path.close();
      }
    }
    return path;
  }

  void addToPdf(dynamic graphics, double pageHeight) {
    for (final op in _ops) {
      switch (op.kind) {
        case _PathOpKind.move:
          graphics.moveTo(op.x, pageHeight - op.y);
        case _PathOpKind.line:
          graphics.lineTo(op.x, pageHeight - op.y);
        case _PathOpKind.cubic:
          graphics.curveTo(
            op.x1,
            pageHeight - op.y1,
            op.x2,
            pageHeight - op.y2,
            op.x,
            pageHeight - op.y,
          );
        case _PathOpKind.close:
          graphics.closePath();
      }
    }
  }
}

class PosterCircle {
  const PosterCircle(this.cx, this.cy, this.radius, this.color);
  final double cx;
  final double cy;
  final double radius;
  final Color color;
}

class PosterFill {
  const PosterFill(this.path, this.color);
  final PosterPath path;
  final Color color;
}

/// Tourism-inspired decorations kept away from the QR quiet zone.
List<PosterFill> posterDecorationFills(SpotQrPosterLayout layout) {
  const w = SpotQrPosterLayout.pageWidthPt;
  const h = SpotQrPosterLayout.pageHeightPt;
  final landscapeTop = layout.landscapeTop;

  final topLeft = PosterPath()
    ..moveTo(0, 0)
    ..lineTo(310, 0)
    ..cubicTo(250, 28, 170, 62, 0, 108)
    ..close();

  final topRight = PosterPath()
    ..moveTo(w, 0)
    ..lineTo(w - 300, 0)
    ..cubicTo(w - 240, 34, w - 150, 78, w, 118)
    ..close();

  final bottomBand = PosterPath()
    ..moveTo(0, h)
    ..lineTo(w, h)
    ..lineTo(w, landscapeTop + 36)
    ..cubicTo(w * 0.72, landscapeTop - 8, w * 0.38, landscapeTop + 48, 0,
        landscapeTop + 18)
    ..close();

  final water = PosterPath()
    ..moveTo(0, h)
    ..lineTo(w, h)
    ..lineTo(w, h - 38)
    ..cubicTo(w * 0.7, h - 52, w * 0.35, h - 24, 0, h - 44)
    ..close();

  final hillBack = PosterPath()
    ..moveTo(0, landscapeTop + 52)
    ..cubicTo(90, landscapeTop + 8, 170, landscapeTop + 44, 250, landscapeTop + 22)
    ..cubicTo(320, landscapeTop + 6, 390, landscapeTop + 38, 470, landscapeTop + 16)
    ..cubicTo(530, landscapeTop + 4, 570, landscapeTop + 28, w, landscapeTop + 18)
    ..lineTo(w, landscapeTop + 70)
    ..lineTo(0, landscapeTop + 70)
    ..close();

  final hillFront = PosterPath()
    ..moveTo(0, landscapeTop + 64)
    ..cubicTo(80, landscapeTop + 34, 160, landscapeTop + 70, 260, landscapeTop + 42)
    ..cubicTo(350, landscapeTop + 20, 455, landscapeTop + 58, w, landscapeTop + 36)
    ..lineTo(w, h - 28)
    ..lineTo(0, h - 28)
    ..close();

  return [
    PosterFill(topLeft, const Color(0xFFFFE4C8)),
    PosterFill(topRight, const Color(0xFFFFE4C8)),
    PosterFill(bottomBand, kPosterOrangeMid),
    PosterFill(hillBack, const Color(0xFFFDBA74)),
    PosterFill(hillFront, const Color(0xFFFB923C)),
    PosterFill(water, const Color(0xFFFED7AA)),
    PosterFill(_palm(w - 78, 52, 0.72), const Color(0xFFFFCC99)),
    PosterFill(_hiker(42, 86), const Color(0xFFFFCC99)),
    PosterFill(_palm(48, landscapeTop + 8, 0.9), const Color(0xFFEA580C)),
    PosterFill(_palm(92, landscapeTop + 18, 0.7), const Color(0xFFC2410C)),
    PosterFill(_lighthouse(w - 118, landscapeTop + 4), const Color(0xFF9A3412)),
    PosterFill(_palm(w - 64, landscapeTop + 14, 0.78), const Color(0xFF9A3412)),
  ];
}

List<PosterCircle> posterDecorationCircles(SpotQrPosterLayout layout) {
  const w = SpotQrPosterLayout.pageWidthPt;
  return [
    PosterCircle(w - 92, layout.landscapeTop + 22, 16, const Color(0xFFFDE68A)),
    PosterCircle(w - 92, layout.landscapeTop + 22, 9, const Color(0xFFFBBF24)),
  ];
}

PosterPath _palm(double x, double y, double s) {
  final p = PosterPath();
  p.moveTo(x, y + 62 * s);
  p.lineTo(x + 7 * s, y + 62 * s);
  p.lineTo(x + 5 * s, y + 18 * s);
  p.lineTo(x + 2 * s, y + 18 * s);
  p.close();
  void frond(double dx, double dy, double ex, double ey) {
    p.moveTo(x + 3.5 * s, y + 20 * s);
    p.cubicTo(
      x + dx * s,
      y + dy * s,
      x + ex * s,
      y + ey * s,
      x + (ex + 4) * s,
      y + (ey + 6) * s,
    );
    p.cubicTo(
      x + (dx * 0.4) * s,
      y + (dy + 8) * s,
      x + 6 * s,
      y + 22 * s,
      x + 3.5 * s,
      y + 20 * s,
    );
    p.close();
  }

  frond(-28, 8, -34, 22);
  frond(-18, -6, -30, 4);
  frond(4, -14, -6, -20);
  frond(22, -4, 32, 6);
  frond(26, 12, 36, 24);
  return p;
}

PosterPath _hiker(double x, double y) {
  final p = PosterPath();
  p.moveTo(x + 10, y);
  p.cubicTo(x + 16, y, x + 16, y + 10, x + 10, y + 10);
  p.cubicTo(x + 4, y + 10, x + 4, y, x + 10, y);
  p.close();
  p.moveTo(x + 6, y + 12);
  p.lineTo(x + 14, y + 12);
  p.lineTo(x + 16, y + 32);
  p.lineTo(x + 12, y + 32);
  p.lineTo(x + 11, y + 22);
  p.lineTo(x + 9, y + 32);
  p.lineTo(x + 5, y + 32);
  p.close();
  p.moveTo(x + 14, y + 14);
  p.lineTo(x + 20, y + 18);
  p.lineTo(x + 18, y + 22);
  p.lineTo(x + 14, y + 18);
  p.close();
  p.moveTo(x + 2, y + 8);
  p.lineTo(x + 4, y + 8);
  p.lineTo(x + 7, y + 36);
  p.lineTo(x + 5, y + 36);
  p.close();
  return p;
}

PosterPath _lighthouse(double x, double y) {
  final p = PosterPath();
  p.moveTo(x + 10, y);
  p.lineTo(x + 22, y);
  p.lineTo(x + 16, y - 14);
  p.close();
  p.moveTo(x + 8, y);
  p.lineTo(x + 24, y);
  p.lineTo(x + 22, y + 46);
  p.lineTo(x + 10, y + 46);
  p.close();
  return p;
}

PosterPath pinPath(double cx, double cy, double s) {
  final p = PosterPath();
  p.moveTo(cx, cy + 11 * s);
  p.cubicTo(cx - 8 * s, cy + 2 * s, cx - 8 * s, cy - 6 * s, cx, cy - 6 * s);
  p.cubicTo(cx + 8 * s, cy - 6 * s, cx + 8 * s, cy + 2 * s, cx, cy + 11 * s);
  p.close();
  return p;
}

PosterPath scanFramePath(PosterRect box) {
  const arm = 11.0;
  const t = 2.2;
  final p = PosterPath();
  void corner(double x, double y, double dx, double dy) {
    p.moveTo(x, y + dy * arm);
    p.lineTo(x, y);
    p.lineTo(x + dx * arm, y);
    p.lineTo(x + dx * arm, y + dy * t);
    p.lineTo(x + dx * t, y + dy * t);
    p.lineTo(x + dx * t, y + dy * arm);
    p.close();
  }

  corner(box.left, box.top, 1, 1);
  corner(box.right, box.top, -1, 1);
  corner(box.left, box.bottom, 1, -1);
  corner(box.right, box.bottom, -1, -1);
  return p;
}

class SpotQrPosterAssets {
  SpotQrPosterAssets._({
    required this.logoBytes,
    required this.logoImage,
    required this.regularFont,
    required this.boldFont,
    required this.regularFontData,
    required this.boldFontData,
  });

  final Uint8List? logoBytes;
  final ui.Image? logoImage;
  final String regularFont;
  final String boldFont;
  final ByteData regularFontData;
  final ByteData boldFontData;

  static const String regularFamily = 'SpotQrPosterNoto';
  static const String boldFamily = 'SpotQrPosterNotoBold';

  static SpotQrPosterAssets? _instance;
  static bool _fontsRegistered = false;

  static Future<SpotQrPosterAssets> load() async {
    if (_instance != null) return _instance!;

    final regularData = await rootBundle.load(_kFontRegularAsset);
    final boldData = await rootBundle.load(_kFontBoldAsset);

    if (!_fontsRegistered) {
      final regularLoader = FontLoader(regularFamily)
        ..addFont(Future<ByteData>.value(regularData));
      final boldLoader = FontLoader(boldFamily)
        ..addFont(Future<ByteData>.value(boldData));
      await regularLoader.load();
      await boldLoader.load();
      _fontsRegistered = true;
    }

    Uint8List? logoBytes;
    ui.Image? logoImage;
    try {
      logoBytes = await loadLogoWithoutWhiteBackground();
      logoBytes ??= (await rootBundle.load(AtmosBrandLogo.asset))
          .buffer
          .asUint8List();
      final codec = await ui.instantiateImageCodec(logoBytes);
      final frame = await codec.getNextFrame();
      logoImage = frame.image;
    } catch (_) {
      logoBytes = null;
      logoImage = null;
    }

    _instance = SpotQrPosterAssets._(
      logoBytes: logoBytes,
      logoImage: logoImage,
      regularFont: regularFamily,
      boldFont: boldFamily,
      regularFontData: regularData,
      boldFontData: boldData,
    );
    return _instance!;
  }
}

/// Draws QR modules with an integer pixel size and no anti-aliasing.
void paintQrModulesSharp(
  ui.Canvas canvas,
  PosterRect boxPt,
  double scale,
  SpotQrModules qr, {
  int quietZone = 4,
}) {
  final left = boxPt.left * scale;
  final top = boxPt.top * scale;
  final size = boxPt.width * scale;
  final total = qr.moduleCount + quietZone * 2;
  final module = (size / total).floorToDouble().clamp(1.0, size);
  final drawn = module * total;
  final ox = (left + (size - drawn) / 2).floorToDouble();
  final oy = (top + (size - drawn) / 2).floorToDouble();

  final bg = ui.Paint()
    ..color = kPosterWhite
    ..isAntiAlias = false
    ..style = PaintingStyle.fill;
  canvas.drawRect(Rect.fromLTWH(ox, oy, drawn, drawn), bg);

  final fg = ui.Paint()
    ..color = const Color(0xFF000000)
    ..isAntiAlias = false
    ..style = PaintingStyle.fill;
  for (var row = 0; row < qr.moduleCount; row++) {
    for (var col = 0; col < qr.moduleCount; col++) {
      if (!qr.isDark(row, col)) continue;
      canvas.drawRect(
        Rect.fromLTWH(
          ox + (col + quietZone) * module,
          oy + (row + quietZone) * module,
          module,
          module,
        ),
        fg,
      );
    }
  }
}

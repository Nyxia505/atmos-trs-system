import 'dart:typed_data';

import 'package:atmos_trs_system/utils/spot_qr_poster.dart';
import 'package:flutter/material.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

/// Data needed for one poster (spot id, name, municipality, municipalityId for QR).
class SpotPosterItem {
  const SpotPosterItem({
    required this.id,
    required this.name,
    required this.municipality,
    this.municipalityId = '',
    this.latitude,
    this.longitude,
    this.qrPayload,
    this.category = '',
  });

  final String id;
  final String name;
  final String municipality;
  final String municipalityId;
  final double? latitude;
  final double? longitude;
  final String? qrPayload;
  final String category;
}

PdfColor _pdf(Color c) => PdfColor.fromInt(c.toARGB32());

/// Builds an A4 portrait PDF using the same poster layout as the PNG export.
Future<pw.Document> buildSpotPosterPdfDocument(List<SpotPosterItem> spots) async {
  final assets = await SpotQrPosterAssets.load();
  final base = pw.Font.ttf(assets.regularFontData);
  final bold = pw.Font.ttf(assets.boldFontData);
  final pdf = pw.Document(
    theme: pw.ThemeData.withFont(base: base, bold: bold),
  );

  for (final spot in spots) {
    final data = buildSpotQrPosterData(
      municipalityId: spot.municipalityId,
      spotId: spot.id,
      spotName: spot.name,
      municipalityDisplayName: spot.municipality,
      qrPayload: spot.qrPayload,
      category: spot.category,
      latitude: spot.latitude,
      longitude: spot.longitude,
    );
    pdf.addPage(
      _posterPage(
        data: data,
        base: base,
        bold: bold,
        logoBytes: assets.logoBytes,
      ),
    );
  }
  return pdf;
}

Future<Uint8List> renderSpotQrPosterPdf(SpotQrPosterData data) async {
  final assets = await SpotQrPosterAssets.load();
  final base = pw.Font.ttf(assets.regularFontData);
  final bold = pw.Font.ttf(assets.boldFontData);
  final doc = pw.Document(
    theme: pw.ThemeData.withFont(base: base, bold: bold),
  );
  doc.addPage(
    _posterPage(
      data: data,
      base: base,
      bold: bold,
      logoBytes: assets.logoBytes,
    ),
  );
  return doc.save();
}

pw.Page _posterPage({
  required SpotQrPosterData data,
  required pw.Font base,
  required pw.Font bold,
  required Uint8List? logoBytes,
}) {
  final payload = data.payload.trim();
  if (payload.isEmpty) {
    throw StateError('This tourist spot has no QR payload to export.');
  }
  final qr = SpotQrModules.encode(payload);
  const layout = SpotQrPosterLayout.a4;
  pw.MemoryImage? logo;
  if (logoBytes != null && logoBytes.isNotEmpty) {
    logo = pw.MemoryImage(logoBytes);
  }

  return pw.Page(
    pageFormat: PdfPageFormat.a4,
    margin: pw.EdgeInsets.zero,
    build: (context) {
      return pw.SizedBox(
        width: PdfPageFormat.a4.width,
        height: PdfPageFormat.a4.height,
        child: pw.Stack(
          children: [
            pw.Positioned.fill(
              child: pw.CustomPaint(
                size: const PdfPoint(
                  SpotQrPosterLayout.pageWidthPt,
                  SpotQrPosterLayout.pageHeightPt,
                ),
                painter: (g, size) {
                  _paintPdfChrome(g, size.y, layout, qr);
                },
              ),
            ),
            if (logo != null)
              pw.Positioned(
                left: layout.logoRect.left,
                top: layout.logoRect.top,
                child: pw.SizedBox(
                  width: layout.logoRect.width,
                  height: layout.logoRect.height,
                  child: pw.Image(logo, fit: pw.BoxFit.contain),
                ),
              ),
            _textBox(
              layout.brandRect,
              kSpotQrPosterBrand,
              pw.TextStyle(
                font: bold,
                fontSize: 22,
                color: _pdf(kPosterOrange),
                letterSpacing: 1.6,
              ),
            ),
            _textBox(
              layout.nameRect,
              data.displayName,
              pw.TextStyle(
                font: bold,
                fontSize: 26,
                color: _pdf(kPosterBrown),
                lineSpacing: 2,
              ),
              maxLines: 3,
            ),
            _textBox(
              PosterRect(
                layout.municipalityRect.left + 18,
                layout.municipalityRect.top,
                layout.municipalityRect.width - 18,
                layout.municipalityRect.height,
              ),
              data.displayMunicipality,
              pw.TextStyle(
                font: base,
                fontSize: 12.5,
                color: _pdf(kPosterMuted),
              ),
              maxLines: 1,
            ),
            _textBox(
              layout.scanPillRect,
              kSpotQrPosterScanHeading,
              pw.TextStyle(
                font: bold,
                fontSize: 13,
                color: _pdf(kPosterWhite),
                letterSpacing: 0.8,
              ),
              maxLines: 1,
            ),
            _textBox(
              PosterRect(
                layout.instructionRect.left + 64,
                layout.instructionRect.top,
                layout.instructionRect.width - 80,
                layout.instructionRect.height,
              ),
              kSpotQrPosterInstruction,
              pw.TextStyle(
                font: base,
                fontSize: 11,
                color: _pdf(kPosterBrown),
                lineSpacing: 2,
              ),
              maxLines: 3,
              align: pw.TextAlign.left,
            ),
            _textBox(
              layout.footerRect,
              kSpotQrPosterFooter,
              pw.TextStyle(
                font: bold,
                fontSize: 10,
                color: _pdf(kPosterWhite),
              ),
              maxLines: 1,
            ),
          ],
        ),
      );
    },
  );
}

pw.Widget _textBox(
  PosterRect rect,
  String text,
  pw.TextStyle style, {
  int maxLines = 2,
  pw.TextAlign align = pw.TextAlign.center,
}) {
  return pw.Positioned(
    left: rect.left,
    top: rect.top,
    child: pw.SizedBox(
      width: rect.width,
      height: rect.height,
      child: pw.Center(
        child: pw.Text(
          text,
          maxLines: maxLines,
          textAlign: align,
          style: style,
        ),
      ),
    ),
  );
}

void _paintPdfChrome(
  PdfGraphics g,
  double pageH,
  SpotQrPosterLayout layout,
  SpotQrModules qr,
) {
  g
    ..setFillColor(_pdf(kPosterPage))
    ..drawRect(0, 0, SpotQrPosterLayout.pageWidthPt, pageH)
    ..fillPath();

  for (final fill in posterDecorationFills(layout)) {
    g.setFillColor(_pdf(fill.color));
    fill.path.addToPdf(g, pageH);
    g.fillPath();
  }
  for (final circle in posterDecorationCircles(layout)) {
    g.setFillColor(_pdf(circle.color));
    g.drawEllipse(circle.cx, pageH - circle.cy, circle.radius, circle.radius);
    g.fillPath();
  }

  final card = layout.cardRect;
  g.setFillColor(PdfColor(0.92, 0.34, 0.05, 0.12));
  g.drawRRect(
    card.left,
    pageH - card.bottom - 3,
    card.width,
    card.height,
    22,
    22,
  );
  g.fillPath();
  g.setFillColor(_pdf(kPosterWhite));
  g.drawRRect(card.left, pageH - card.bottom, card.width, card.height, 22, 22);
  g.fillPath();
  g.setStrokeColor(_pdf(const Color(0xFFFFE4C8)));
  g.setLineWidth(1.2);
  g.drawRRect(card.left, pageH - card.bottom, card.width, card.height, 22, 22);
  g.strokePath();

  final frame = scanFramePath(layout.qrFrameRect);
  g.setFillColor(_pdf(kPosterOrangeMid));
  frame.addToPdf(g, pageH);
  g.fillPath();

  final pill = layout.scanPillRect;
  g.setFillColor(_pdf(kPosterOrange));
  g.drawRRect(pill.left, pageH - pill.bottom, pill.width, pill.height, 20, 20);
  g.fillPath();

  final footer = layout.footerRect;
  g.setFillColor(_pdf(kPosterOrange));
  g.drawRRect(
    footer.left,
    pageH - footer.bottom,
    footer.width,
    footer.height,
    16,
    16,
  );
  g.fillPath();

  final muni = layout.municipalityRect;
  g.setFillColor(_pdf(kPosterOrange));
  pinPath(muni.centerX - 64, muni.centerY - 2, 1).addToPdf(g, pageH);
  g.fillPath();
  g.setFillColor(_pdf(kPosterWhite));
  g.drawEllipse(muni.centerX - 64, pageH - (muni.centerY - 4), 2.2, 2.2);
  g.fillPath();

  const w = SpotQrPosterLayout.pageWidthPt;
  final y = layout.dividerY;
  g.setStrokeColor(_pdf(kPosterGold));
  g.setLineWidth(1.4);
  g
    ..moveTo(w / 2 - 92, pageH - y)
    ..lineTo(w / 2 - 12, pageH - y)
    ..moveTo(w / 2 + 12, pageH - y)
    ..lineTo(w / 2 + 92, pageH - y)
    ..strokePath();
  g.setFillColor(_pdf(kPosterOrangeMid));
  g.drawEllipse(w / 2, pageH - y, 3.2, 3.2);
  g.fillPath();

  final icon = PosterRect(
    layout.instructionRect.left + 36,
    layout.instructionRect.top + 10,
    22,
    22,
  );
  const arm = 7.0;
  g.setStrokeColor(_pdf(kPosterOrange));
  g.setLineWidth(2);
  g.setLineCap(PdfLineCap.round);
  g.setLineJoin(PdfLineJoin.round);
  void corner(double x, double y, double dx, double dy) {
    g
      ..moveTo(x, pageH - (y + dy * arm))
      ..lineTo(x, pageH - y)
      ..lineTo(x + dx * arm, pageH - y);
  }

  corner(icon.left, icon.top, 1, 1);
  corner(icon.right, icon.top, -1, 1);
  corner(icon.left, icon.bottom, 1, -1);
  corner(icon.right, icon.bottom, -1, -1);
  g.strokePath();

  _paintPdfQr(g, pageH, layout.qrRect, qr);
}

void _paintPdfQr(
  PdfGraphics g,
  double pageH,
  PosterRect box,
  SpotQrModules qr, {
  int quietZone = 4,
}) {
  final total = qr.moduleCount + quietZone * 2;
  final module = box.width / total;
  final ox = box.left;
  final oy = box.top;

  g
    ..setFillColor(PdfColors.white)
    ..drawRect(ox, pageH - oy - box.height, box.width, box.height)
    ..fillPath();

  g.setFillColor(PdfColors.black);
  for (var row = 0; row < qr.moduleCount; row++) {
    for (var col = 0; col < qr.moduleCount; col++) {
      if (!qr.isDark(row, col)) continue;
      final x = ox + (col + quietZone) * module;
      final yTop = oy + (row + quietZone) * module;
      g.drawRect(x, pageH - yTop - module, module, module);
    }
  }
  g.fillPath();
}

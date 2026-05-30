import 'dart:typed_data';

import 'package:atmos_trs_system/utils/png_bytes_download.dart';
import 'package:atmos_trs_system/utils/qr_png_bytes.dart';
import 'package:atmos_trs_system/utils/spot_qr_helper.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

/// Downloads a single tourist-spot QR as PNG (web: file download; mobile: share sheet).
Future<void> downloadSpotQrPng(
  String municipalityId,
  String spotId, {
  double? latitude,
  double? longitude,
}) async {
  final data = spotQrData(
    municipalityId,
    spotId,
    latitude: latitude,
    longitude: longitude,
  );
  final bytes = await qrDataToPngBytes(data, size: 280);
  if (bytes == null) return;
  final safeMid = municipalityId.replaceAll(RegExp(r'[^a-z0-9_-]'), '_');
  final safeSid = spotId.replaceAll(RegExp(r'[^a-z0-9_-]'), '_');
  await downloadPngFile('ATMOS-TRS-SPOT-$safeMid-$safeSid.png', bytes);
}

/// Single-page PDF with spot QR (print / save as PDF on all platforms).
Future<void> downloadSpotQrPdf({
  required String municipalityId,
  required String spotId,
  required String spotName,
  required String municipalityDisplayName,
  double? latitude,
  double? longitude,
}) async {
  final data = spotQrData(
    municipalityId,
    spotId,
    latitude: latitude,
    longitude: longitude,
  );
  final Uint8List? pngBytes = await qrDataToPngBytes(data, size: 220);
  final doc = pw.Document();
  doc.addPage(
    pw.Page(
      pageFormat: PdfPageFormat.a4,
      build: (pw.Context context) {
        return pw.Center(
          child: pw.Column(
            mainAxisAlignment: pw.MainAxisAlignment.center,
            children: [
              pw.Text(
                'ATMOS TRS',
                style: pw.TextStyle(fontSize: 22, fontWeight: pw.FontWeight.bold),
              ),
              pw.SizedBox(height: 8),
              pw.Text(
                spotName,
                style: const pw.TextStyle(fontSize: 16),
                textAlign: pw.TextAlign.center,
              ),
              pw.SizedBox(height: 4),
              pw.Text(
                municipalityDisplayName,
                style: const pw.TextStyle(fontSize: 12),
                textAlign: pw.TextAlign.center,
              ),
              pw.SizedBox(height: 24),
              if (pngBytes != null && pngBytes.isNotEmpty)
                pw.Image(
                  pw.MemoryImage(pngBytes),
                  width: 220,
                  height: 220,
                ),
              pw.SizedBox(height: 20),
              pw.Text(
                'Spot QR — scan in the ATMOS TRS app',
                style: const pw.TextStyle(fontSize: 11),
              ),
              pw.SizedBox(height: 8),
              pw.Text(
                data,
                style: const pw.TextStyle(fontSize: 9),
              ),
            ],
          ),
        );
      },
    ),
  );
  final safeMid = municipalityId.replaceAll(RegExp(r'[^a-z0-9_-]'), '_');
  final safeSid = spotId.replaceAll(RegExp(r'[^a-z0-9_-]'), '_');
  await Printing.layoutPdf(
    onLayout: (PdfPageFormat format) async => doc.save(),
    name: 'ATMOS-TRS-SPOT-$safeMid-$safeSid.pdf',
  );
}

import 'dart:typed_data';

import 'package:atmos_trs_system/utils/png_bytes_download.dart';
import 'package:atmos_trs_system/utils/qr_png_bytes.dart';
import 'package:atmos_trs_system/utils/spot_qr_helper.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

Future<void> downloadEstablishmentQrPng({
  required String establishmentId,
  required String businessName,
  String? municipalityId,
}) async {
  final data = establishmentQrData(
    establishmentId,
    municipalityId: municipalityId,
    businessName: businessName,
  );
  final bytes = await qrDataToPngBytes(data, size: 280);
  if (bytes == null) return;
  final safe = businessName.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_');
  await downloadPngFile('ATMOS-TRS-EST-$safe.png', bytes);
}

Future<void> downloadEstablishmentQrPdf({
  required String establishmentId,
  required String businessName,
  String? municipalityId,
}) async {
  final data = establishmentQrData(
    establishmentId,
    municipalityId: municipalityId,
    businessName: businessName,
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
                'ATMOS-TRS',
                style: pw.TextStyle(fontSize: 22, fontWeight: pw.FontWeight.bold),
              ),
              pw.SizedBox(height: 8),
              pw.Text(
                businessName,
                style: const pw.TextStyle(fontSize: 16),
                textAlign: pw.TextAlign.center,
              ),
              pw.SizedBox(height: 8),
              pw.Text(
                'Establishment stay QR',
                style: const pw.TextStyle(fontSize: 12),
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
                'Tourist scans → front desk confirms on ATMOS dashboard',
                style: const pw.TextStyle(fontSize: 11),
                textAlign: pw.TextAlign.center,
              ),
            ],
          ),
        );
      },
    ),
  );
  final safe = businessName.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_');
  await Printing.layoutPdf(
    onLayout: (PdfPageFormat format) async => doc.save(),
    name: 'ATMOS-TRS-EST-$safe.pdf',
  );
}

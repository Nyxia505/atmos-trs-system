import 'dart:typed_data';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:atmos_trs_system/utils/spot_qr_helper.dart';

// Light orange for bottom accent (no alpha in PDF, use solid)
final PdfColor _orangeLight = PdfColor.fromInt(0xFFFFEDD5);

/// Data needed for one poster (spot id, name, municipality, municipalityId for QR).
class SpotPosterItem {
  const SpotPosterItem({
    required this.id,
    required this.name,
    required this.municipality,
    this.municipalityId = '',
    this.latitude,
    this.longitude,
  });

  final String id;
  final String name;
  final String municipality;
  final String municipalityId;
  final double? latitude;
  final double? longitude;
}

// Theme: ATMOS TRS orange and white
final PdfColor _orange = PdfColor.fromInt(0xFFF97316);
final PdfColor _orangeDark = PdfColor.fromInt(0xFFEA580C);
final PdfColor _white = PdfColors.white;
final PdfColor _textDark = PdfColor.fromInt(0xFF1F2937);
final PdfColor _textMuted = PdfColor.fromInt(0xFF6B7280);

/// Builds an A4 portrait PDF with one poster page per spot.
/// [getQrImageBytes] should return PNG bytes for the given QR data and size (e.g. from QrPainter).
Future<pw.Document> buildSpotPosterPdfDocument(
  List<SpotPosterItem> spots,
  Future<Uint8List?> Function(String qrData, int size) getQrImageBytes,
) async {
  const double qrSizePt = 280.0;
  const int qrPixelSize = 400;
  const double marginPt = 36.0;
  const double headerHeightPt = 56.0;

  final pdf = pw.Document();

  for (final spot in spots) {
    final municipalityId = spot.municipalityId.isNotEmpty
        ? spot.municipalityId
        : '';
    final lat = spot.latitude;
    final lng = spot.longitude;
    final hasCoords = lat != null &&
        lng != null &&
        lat.abs() > 1e-7 &&
        lng.abs() > 1e-7;
    final qrData = municipalityId.isNotEmpty
        ? spotQrData(
            municipalityId,
            spot.id,
            latitude: hasCoords ? lat : null,
            longitude: hasCoords ? lng : null,
          )
        : '';
    pw.Image? qrImage;
    if (qrData.isNotEmpty) {
      final bytes = await getQrImageBytes(qrData, qrPixelSize);
      if (bytes != null && bytes.isNotEmpty) {
        qrImage = pw.Image(
          pw.MemoryImage(bytes),
          width: qrSizePt,
          height: qrSizePt,
        );
      }
    }

    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: pw.EdgeInsets.zero,
        build: (pw.Context context) {
          return pw.Container(
            color: _white,
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.stretch,
              children: [
                // Top band: orange with title
                pw.Container(
                  height: headerHeightPt,
                  color: _orangeDark,
                  alignment: pw.Alignment.center,
                  child: pw.Text(
                    'ATMOS TRS Tourist Spot QR',
                    style: pw.TextStyle(
                      color: _white,
                      fontSize: 18,
                      fontWeight: pw.FontWeight.bold,
                    ),
                  ),
                ),
                pw.SizedBox(height: marginPt),
                // Spot name (centered)
                pw.Padding(
                  padding: pw.EdgeInsets.symmetric(horizontal: marginPt),
                  child: pw.Text(
                    spot.name,
                    style: pw.TextStyle(
                      color: _textDark,
                      fontSize: 22,
                      fontWeight: pw.FontWeight.bold,
                    ),
                    textAlign: pw.TextAlign.center,
                  ),
                ),
                pw.SizedBox(height: 8),
                // Municipality (centered)
                pw.Padding(
                  padding: pw.EdgeInsets.symmetric(horizontal: marginPt),
                  child: pw.Text(
                    spot.municipality.isNotEmpty
                        ? spot.municipality
                        : 'Misamis Occidental',
                    style: pw.TextStyle(
                      color: _textMuted,
                      fontSize: 14,
                    ),
                    textAlign: pw.TextAlign.center,
                  ),
                ),
                pw.SizedBox(height: 32),
                // QR code with white space around it
                pw.Center(
                  child: qrImage != null
                      ? pw.Container(
                          width: qrSizePt + 48,
                          height: qrSizePt + 48,
                          color: _white,
                          child: pw.Center(
                            child: qrImage,
                          ),
                        )
                      : pw.Text(
                          'Set municipalityId for this spot to generate QR',
                          style: pw.TextStyle(
                            color: _textMuted,
                            fontSize: 12,
                          ),
                        ),
                ),
                pw.SizedBox(height: 28),
                // Instruction
                pw.Center(
                  child: pw.Text(
                    'Scan here to check in',
                    style: pw.TextStyle(
                      color: _orange,
                      fontSize: 16,
                      fontWeight: pw.FontWeight.bold,
                    ),
                  ),
                ),
                pw.Spacer(),
                // Bottom subtle band (optional, for balance)
                pw.Container(
                  height: 6,
                  color: _orangeLight,
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  return pdf;
}

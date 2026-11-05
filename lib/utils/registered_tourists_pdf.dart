import 'package:atmos_trs_system/utils/lgu_registered_tourists_xlsx.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

String registeredTouristsPdfFilename({
  required String location,
  DateTime? generatedAt,
}) {
  final xlsx = lguRegisteredTouristsXlsxFilename(
    lguLocation: location,
    generatedAt: generatedAt,
  );
  return xlsx.replaceFirst(RegExp(r'\.xlsx$'), '.pdf');
}

Future<List<int>> buildRegisteredTouristsPdf({
  required String officeLabel,
  required String location,
  required List<LguRegisteredTouristExportRow> rows,
  required DateTime generatedAt,
  String privacyLabel = 'Privacy-safe export',
}) async {
  const orange = PdfColor.fromInt(0xFFF97316);
  const navy = PdfColor.fromInt(0xFF0B1F3A);
  const cream = PdfColor.fromInt(0xFFFFF4E8);
  const ink = PdfColor.fromInt(0xFF111827);
  const muted = PdfColor.fromInt(0xFF6B7280);
  const band = PdfColor.fromInt(0xFFD7EEF8);

  final place = location.trim().isEmpty ? 'Misamis Occidental' : location.trim();
  final doc = pw.Document();
  const headers = [
    'Tourist ID',
    'Type',
    'Origin',
    'Visits',
    'Status',
    'Registered Date',
    'Registered Time',
  ];

  doc.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.a4.landscape,
      margin: const pw.EdgeInsets.fromLTRB(28, 24, 28, 28),
      header: (context) => pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.stretch,
        children: [
          pw.Container(
            color: orange,
            padding: const pw.EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            child: pw.Text(
              'ATMOS TRS | REGISTERED TOURISTS',
              style: pw.TextStyle(
                color: PdfColors.white,
                fontSize: 16,
                fontWeight: pw.FontWeight.bold,
              ),
            ),
          ),
          pw.Container(
            color: cream,
            padding: const pw.EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            child: pw.Text(
              '$officeLabel - $place  |  $privacyLabel  |  ${formatExportDate(generatedAt)} ${formatExportTime(generatedAt)}',
              style: const pw.TextStyle(color: ink, fontSize: 9),
            ),
          ),
          pw.SizedBox(height: 8),
          pw.Text(
            '${rows.length} record${rows.length == 1 ? '' : 's'} - names and contact details omitted.',
            style: const pw.TextStyle(color: muted, fontSize: 8),
          ),
          pw.SizedBox(height: 8),
        ],
      ),
      build: (context) {
        if (rows.isEmpty) {
          return [
            pw.Padding(
              padding: const pw.EdgeInsets.only(top: 24),
              child: pw.Text(
                'No registered tourists to export.',
                style: const pw.TextStyle(color: muted, fontSize: 12),
              ),
            ),
          ];
        }
        return [
          pw.TableHelper.fromTextArray(
            headers: headers,
            data: [
              for (final row in rows)
                [
                  _pdfSafe(row.touristId),
                  _pdfSafe(row.type),
                  _pdfSafe(row.origin),
                  '${row.visits}',
                  _pdfSafe(row.status),
                  _pdfSafe(row.registeredDate),
                  _pdfSafe(row.registeredTime),
                ],
            ],
            headerStyle: pw.TextStyle(
              color: PdfColors.white,
              fontSize: 8,
              fontWeight: pw.FontWeight.bold,
            ),
            headerDecoration: const pw.BoxDecoration(color: navy),
            cellStyle: const pw.TextStyle(fontSize: 8, color: ink),
            cellAlignment: pw.Alignment.centerLeft,
            oddRowDecoration: const pw.BoxDecoration(color: band),
            cellPadding: const pw.EdgeInsets.symmetric(horizontal: 5, vertical: 4),
          ),
        ];
      },
    ),
  );
  return doc.save();
}

String _pdfSafe(String value) {
  return value
      .replaceAll('•', '|')
      .replaceAll('—', '-')
      .replaceAll('–', '-');
}

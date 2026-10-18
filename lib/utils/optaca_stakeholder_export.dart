import 'package:excel/excel.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import 'package:atmos_trs_system/data/misamis_occidental_municipalities.dart';
import 'package:atmos_trs_system/utils/csv_file_download.dart';
import 'package:atmos_trs_system/utils/municipality_helper.dart';
import 'package:atmos_trs_system/utils/pdf_file_download.dart';
import 'package:atmos_trs_system/utils/xlsx_file_download.dart';

class OptacaStakeholderRow {
  const OptacaStakeholderRow({
    required this.kind,
    required this.name,
    required this.municipality,
    required this.email,
    required this.status,
    required this.note,
  });

  final String kind;
  final String name;
  final String municipality;
  final String email;
  final String status;
  final String note;
}

/// Directory of LGUs, hotels, restaurants, and private attractions.
abstract final class OptacaStakeholderExport {
  static const headers = [
    'Stakeholder',
    'Name',
    'Municipality',
    'Email',
    'Status',
    'Notes',
  ];

  static String kindForEstablishmentCategory(String category) {
    final c = category.trim().toLowerCase();
    if (c == 'hotel' || c == 'resort' || c == 'glamping' || c == 'camping') {
      return 'Hotel';
    }
    if (c == 'restaurant' || c == 'food provider') return 'Restaurant';
    return 'Private attraction';
  }

  static List<OptacaStakeholderRow> build({
    required List<Map<String, dynamic>> users,
    required List<Map<String, dynamic>> establishments,
    required List<Map<String, dynamic>> spots,
    String kindFilter = 'All',
  }) {
    final rows = <OptacaStakeholderRow>[];
    for (final user in users) {
      final role = (user['role'] ?? '').toString().toLowerCase();
      if (role != 'tourism' && role != 'tourism_office') continue;
      final mid = (user['municipalityId'] ?? '').toString();
      rows.add(
        OptacaStakeholderRow(
          kind: 'LGU',
          name: (user['fullName'] ?? user['municipality'] ?? 'LGU office')
              .toString(),
          municipality: (user['municipality'] ?? '').toString().isNotEmpty
              ? user['municipality'].toString()
              : municipalityNameFromId(mid),
          email: (user['email'] ?? '').toString(),
          status: _status(user['status']),
          note: 'Municipal tourism office',
        ),
      );
    }
    for (final est in establishments) {
      final category = (est['category'] ?? est['type'] ?? '').toString();
      final kind = kindForEstablishmentCategory(category);
      rows.add(
        OptacaStakeholderRow(
          kind: kind,
          name: (est['businessName'] ?? est['name'] ?? 'Establishment')
              .toString(),
          municipality: (est['municipality'] ?? '').toString(),
          email: (est['email'] ?? '').toString(),
          status: _status(est['status']),
          note: category,
        ),
      );
    }
    for (final spot in spots) {
      final payload = (spot['qr_payload'] ?? spot['qrPayload'] ?? '')
          .toString()
          .trim();
      final mid = (spot['municipalityId'] ?? '').toString();
      rows.add(
        OptacaStakeholderRow(
          kind: 'Private attraction',
          name: (spot['name'] ?? 'Attraction').toString(),
          municipality: (spot['municipality'] ?? '').toString().isNotEmpty
              ? spot['municipality'].toString()
              : municipalityNameFromId(mid),
          email: '',
          status: _status(spot['status']),
          note: payload.isEmpty ? 'QR not enrolled' : 'QR enrolled',
        ),
      );
    }
    rows.sort((a, b) {
      final kind = a.kind.compareTo(b.kind);
      if (kind != 0) return kind;
      return a.name.toLowerCase().compareTo(b.name.toLowerCase());
    });
    if (kindFilter == 'All') return rows;
    return rows.where((row) => row.kind == kindFilter).toList();
  }

  static String _status(Object? raw) {
    final value = (raw ?? '').toString().trim();
    if (value.isEmpty) return 'Active';
    return value[0].toUpperCase() + value.substring(1);
  }

  static String municipalityNameFromId(String id) {
    final canonical = normalizeMunicipalityId(id);
    for (final municipality in getMisamisOccidentalMunicipalities()) {
      if (normalizeMunicipalityId(municipality.id) == canonical) {
        return municipality.name;
      }
    }
    return id;
  }

  static String toCsv(List<OptacaStakeholderRow> rows) {
    String cell(String value) {
      final escaped = value.replaceAll('"', '""');
      return '"$escaped"';
    }

    final lines = <String>[
      headers.map(cell).join(','),
      for (final row in rows)
        [
          row.kind,
          row.name,
          row.municipality,
          row.email,
          row.status,
          row.note,
        ].map(cell).join(','),
    ];
    return lines.join('\n');
  }

  static List<int> toExcel(List<OptacaStakeholderRow> rows) {
    final book = Excel.createExcel();
    final sheet = book['Stakeholders'];
    book.setDefaultSheet('Stakeholders');
    sheet.appendRow(headers.map(TextCellValue.new).toList());
    for (final row in rows) {
      sheet.appendRow([
        TextCellValue(row.kind),
        TextCellValue(row.name),
        TextCellValue(row.municipality),
        TextCellValue(row.email),
        TextCellValue(row.status),
        TextCellValue(row.note),
      ]);
    }
    if (book.sheets.containsKey('Sheet1')) {
      book.delete('Sheet1');
    }
    final bytes = book.encode();
    return bytes ?? <int>[];
  }

  static Future<List<int>> toPdf(List<OptacaStakeholderRow> rows) async {
    final doc = pw.Document();
    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        build: (context) => [
          pw.Text(
            'ATMOS TRS — OPTACA stakeholder directory',
            style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold),
          ),
          pw.SizedBox(height: 6),
          pw.Text(
            'LGUs, hotels, restaurants, and private attractions. ${rows.length} rows.',
            style: const pw.TextStyle(fontSize: 10),
          ),
          pw.SizedBox(height: 12),
          pw.TableHelper.fromTextArray(
            headers: headers,
            data: [
              for (final row in rows)
                [
                  row.kind,
                  row.name,
                  row.municipality,
                  row.email,
                  row.status,
                  row.note,
                ],
            ],
            headerStyle: pw.TextStyle(
              fontWeight: pw.FontWeight.bold,
              fontSize: 9,
            ),
            cellStyle: const pw.TextStyle(fontSize: 8),
            cellAlignment: pw.Alignment.centerLeft,
          ),
        ],
      ),
    );
    return doc.save();
  }

  static Future<void> download({
    required String format,
    required List<OptacaStakeholderRow> rows,
  }) async {
    final stamp = DateTime.now().toIso8601String().split('T').first;
    switch (format) {
      case 'csv':
        await downloadCsvFile(
          'ATMOS-OPTACA-stakeholders-$stamp.csv',
          toCsv(rows),
        );
      case 'excel':
        await downloadXlsxFile(
          'ATMOS-OPTACA-stakeholders-$stamp.xlsx',
          toExcel(rows),
        );
      case 'pdf':
        await downloadPdfFile(
          'ATMOS-OPTACA-stakeholders-$stamp.pdf',
          await toPdf(rows),
        );
      default:
        throw StateError('Unknown export format.');
    }
  }
}

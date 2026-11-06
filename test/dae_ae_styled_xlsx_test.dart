import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:atmos_trs_system/config/supabase_report_templates_config.dart';
import 'package:atmos_trs_system/models/ae_register.dart';
import 'package:atmos_trs_system/utils/ae_register_report_query.dart';
import 'package:atmos_trs_system/utils/dae_ae_styled_xlsx.dart';
import 'package:atmos_trs_system/utils/dot_report_export_service.dart';
import 'package:atmos_trs_system/utils/dot_report_preview.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final start = DateTime(2026, 11, 1);
  final end = DateTime(2026, 11, 30);

  AeRegisterReportData register() => AeRegisterReportData(
        reports: [
          AeMonthlyReport(
            id: 'ae1_2026_11',
            aeId: 'ae1',
            year: 2026,
            month: 11,
            aeName: 'Seaside Inn',
            municipality: 'Oroquieta',
            province: 'Misamis Occidental',
            totalRooms: 20,
            aeType: 'Hotel',
            classificationCode: 'H-3',
            totals: const AeMonthTotals(
              checkIns: 40,
              guestNights: 80,
              roomsOccupied: 50,
              domesticArrivals: 30,
              domesticNights: 60,
              foreignArrivals: 8,
              foreignNights: 16,
              overseasFilipinoArrivals: 2,
              overseasFilipinoNights: 4,
              rowCount: 3,
            ),
          ),
        ],
        rowsByReport: {
          'ae1_2026_11': [
            for (final day in [1, 2, 3])
              AeRegisterRow(
                id: 'r$day',
                date: DateTime(2026, 11, day),
                residence: 'Philippines (Filipino)',
                guests: 4,
                female: 2,
                male: 2,
                checkedInDay: true,
                roomNo: '10$day',
              ),
          ],
        },
      );

  test('DAE-1A styled workbook has Report sheet, columns, print setup', () {
    final form = kDotFormCatalog.firstWhere((e) => e.id == 'dae1a_manual');
    final preview = buildDotReportPreview(
      form: form,
      startDate: start,
      endDate: end,
      checkIns: const [],
      tourists: const [],
      catalogSpots: const [],
      scopeLabel: 'Oroquieta',
      aeRegister: register(),
    );

    expect(preview.headers, [
      'AE',
      'Date',
      'Check-ins',
      'Check-outs',
      'Guest nights',
      'Rooms occupied',
      'Occupancy',
    ]);
    expect(preview.footer?.first, 'TOTAL');

    final bytes = DaeAeStyledXlsx.build(
      form: form,
      preview: preview,
      scopeLabel: 'Oroquieta',
      startDate: start,
      endDate: end,
    );
    expect(bytes.length, greaterThan(1500));

    final sheets = _sheetNames(bytes);
    expect(sheets, contains(DaeAeStyledXlsx.reportSheetName));
    expect(sheets, contains(DaeAeStyledXlsx.gapsSheetName));
    expect(sheets, contains(DaeAeStyledXlsx.dataSheetName));

    final reportXml = _firstSheetXml(bytes, DaeAeStyledXlsx.reportSheetName);
    final shared = _fileText(bytes, 'xl/sharedStrings.xml');
    expect(shared, contains('ATMOS TRS | DOT REPORT'));
    expect(shared, contains('DAE-1A — MANUAL TALLY'));
    expect(shared, contains('Seaside Inn'));
    expect(shared, contains('TOTAL'));
    expect(reportXml, contains('pageSetup'));
    expect(reportXml, contains('paperSize="9"'));
    expect(reportXml, contains('horizontalCentered="1"'));
    expect(reportXml, contains('orientation="landscape"'));
    expect(reportXml, contains('mergeCell ref="A1:G1"'));
    // Column F (Rooms occupied) must be wide enough that the header is not clipped.
    expect(reportXml, contains('min="6" max="6" width="18.00"'));
    expect(shared, contains('Rooms occupied'));
    expect(shared, contains('Occupancy'));

    final workbookXml = _fileText(bytes, 'xl/workbook.xml');
    expect(workbookXml, contains('_xlnm.Print_Area'));
    expect(workbookXml, contains('_xlnm.Print_Titles'));

    Directory('test_output').createSync(recursive: true);
    File('test_output/dae1a_manual_styled.xlsx').writeAsBytesSync(bytes);
  });

  test('DAE-1B styled workbook centers Value and keeps item labels', () {
    final form = kDotFormCatalog.firstWhere((e) => e.id == 'dae1b_macro');
    final preview = buildDotReportPreview(
      form: form,
      startDate: start,
      endDate: end,
      checkIns: const [],
      tourists: const [],
      catalogSpots: const [],
      scopeLabel: 'Oroquieta',
      aeRegister: register(),
    );

    expect(preview.headers, ['Item', 'Description', 'Value']);
    expect(
      preview.rows.map((r) => r[1]),
      containsAll([
        'Identification of Accommodation Establishment',
        'Room Occupancy Rate',
        'Overall Average Length of Stay',
        'Overall Average Persons per Room',
      ]),
    );

    final bytes = DaeAeStyledXlsx.build(
      form: form,
      preview: preview,
      scopeLabel: 'Oroquieta',
      startDate: start,
      endDate: end,
    );

    final reportXml = _firstSheetXml(bytes, DaeAeStyledXlsx.reportSheetName);
    final shared = _fileText(bytes, 'xl/sharedStrings.xml');
    expect(shared, contains('DOT ET DAE-1B — MACRO REGISTER'));
    expect(shared, contains('Seaside Inn'));
    expect(shared, contains('Identification of Accommodation Establishment'));
    expect(reportXml, contains('orientation="portrait"'));
    expect(reportXml, contains('fitToWidth="1"'));
    expect(reportXml, contains('mergeCell ref="A1:C1"'));

    File('test_output/dae1b_macro_styled.xlsx').writeAsBytesSync(bytes);
  });

  test('exportCatalog routes DAE-1A/1B through styled Report sheet', () async {
    final service = DotReportExportService();
    final form = kDotFormCatalog.firstWhere((e) => e.id == 'dae1a_manual');
    final result = await service.exportCatalog(
      form: form,
      startDate: start,
      endDate: end,
      checkIns: const [],
      tourists: const [],
      catalogSpots: const [],
      scopeLabel: 'Oroquieta',
      scopeSlug: 'oroquieta',
      aeRegister: register(),
    );
    final sheets = _sheetNames(result.bytes);
    expect(sheets.first, DaeAeStyledXlsx.reportSheetName);
    expect(_fileText(result.bytes, 'xl/workbook.xml'), contains('Print_Area'));
  });
}

List<String> _sheetNames(List<int> bytes) {
  final xml = _fileText(bytes, 'xl/workbook.xml');
  return RegExp(r'<sheet[^>]*name="([^"]+)"')
      .allMatches(xml)
      .map((m) => m.group(1)!)
      .toList();
}

String _firstSheetXml(List<int> bytes, String sheetName) {
  final workbook = _fileText(bytes, 'xl/workbook.xml');
  final rels = _fileText(bytes, 'xl/_rels/workbook.xml.rels');
  final ridRe = RegExp(
    'name="${RegExp.escape(sheetName)}"[^>]*r:id="(rId\\d+)"'
    '|r:id="(rId\\d+)"[^>]*name="${RegExp.escape(sheetName)}"',
  );
  final rid = ridRe.firstMatch(workbook)?.group(1) ??
      ridRe.firstMatch(workbook)?.group(2);
  expect(rid, isNotNull);
  final target = RegExp('Id="$rid"[^>]*Target="([^"]+)"').firstMatch(rels)?.group(1) ??
      RegExp('Target="([^"]+)"[^>]*Id="$rid"').firstMatch(rels)?.group(1);
  expect(target, isNotNull);
  final path = target!.startsWith('xl/') ? target : 'xl/$target';
  return _fileText(bytes, path);
}

String _fileText(List<int> bytes, String name) {
  final archive = ZipDecoder().decodeBytes(bytes);
  final file = archive.files.firstWhere(
    (f) => f.name.replaceAll('\\', '/') == name,
  );
  return utf8.decode(file.content as List<int>);
}

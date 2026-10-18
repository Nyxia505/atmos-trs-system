import 'dart:io';

import 'package:atmos_trs_system/config/dae_residence_catalog.dart';
import 'package:atmos_trs_system/models/ae_register.dart';
import 'package:atmos_trs_system/utils/ae_register_report_query.dart';
import 'package:atmos_trs_system/utils/dae1b2_template_fill.dart';
import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('DAE 1B.2 workbooks keep the official sheets and receive region totals', () {
    final register = AeRegisterReportData(
      reports: [
        AeMonthlyReport(
          id: 'ae1_2026_01',
          aeId: 'ae1',
          year: 2026,
          month: 1,
          aeName: 'Hotel One',
          municipality: 'Oroquieta',
          province: 'Misamis Occidental',
          totals: const AeMonthTotals(
            domesticArrivals: 12,
            domesticNights: 24,
            rowCount: 1,
            byRegion: {
              'Region X - Northern Mindanao': AeCountryTotals(
                arrivals: 12,
                nights: 24,
                female: 7,
                male: 5,
              ),
            },
          ),
        ),
      ],
      rowsByReport: {
        'ae1_2026_01': [
          AeRegisterRow(
            id: 'r1',
            date: DateTime(2026, 1, 4),
            residence: DaeResidenceCatalog.phFilipino,
            guests: 12,
            phRegion: 'Region X - Northern Mindanao',
            female: 7,
            male: 5,
            checkedInDay: true,
          ),
        ],
      },
    );

    final aeFill = Dae1b2TemplateFill.fill(
      templateBytes: File('forms_format/3.-DAE1B.2.xlsx').readAsBytesSync(),
      register: register,
      scopeLabel: 'Oroquieta',
      withAeSheet: false,
    );
    final aeXml = _sheet(aeFill.bytes, 'xl/worksheets/sheet2.xml');
    expect(aeXml, contains('<v>12</v>'));
    expect(aeXml, contains('r="C116"'));
    expect(aeXml, contains('Hotel One'));
    expect(aeXml, contains('2026'));
    expect(aeXml, contains('<f>SUM(C11:C27)</f>'));
    final daily = _sheet(aeFill.bytes, 'xl/worksheets/sheet1.xml');
    expect(daily, contains('r="F117"'));
    expect(daily, contains('January'));
    expect(_sheet(aeFill.bytes, 'xl/worksheets/sheet90.xml'), contains('PH region'));

    final domestic = Dae1b2TemplateFill.fill(
      templateBytes: File('forms_format/DAE1B.2.Domestic.xlsx').readAsBytesSync(),
      register: register,
      scopeLabel: 'Oroquieta',
      withAeSheet: true,
    );
    final aeSheet = _sheet(domestic.bytes, 'xl/worksheets/sheet2.xml');
    expect(aeSheet, contains('Hotel One'));
    expect(aeSheet, contains('r="C117"'));
    final monthly = _sheet(domestic.bytes, 'xl/worksheets/sheet3.xml');
    expect(monthly, contains('r="C116"'));
    expect(monthly, contains('<v>12</v>'));
  });
}

String _sheet(List<int> bytes, String name) {
  final archive = ZipDecoder().decodeBytes(bytes);
  final file = archive.files.firstWhere((f) => f.name.replaceAll('\\', '/') == name);
  return String.fromCharCodes(file.content as List<int>);
}

import 'dart:io';

import 'package:excel/excel.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import 'package:atmos_trs_system/config/supabase_report_templates_config.dart';
import 'package:atmos_trs_system/utils/dot_report_export_service.dart';
import 'package:atmos_trs_system/utils/dot_var2_visitor_record_report.dart';

void main() {
  test('VAR 2 official sheet is filled from check-in aggregates', () async {
    final templatePath = File('tmp_var2.xlsx');
    if (!templatePath.existsSync()) {
      // CI / clean trees may not have the downloaded fixture.
      return;
    }

    final service = DotReportExportService(
      client: _FakeClient(templatePath.readAsBytesSync()),
    );

    final result = await service.exportFilled(
      type: DotReportType.var2VisitorRecord,
      startDate: DateTime(2026, 9, 1),
      endDate: DateTime(2026, 9, 15, 23, 59, 59),
      checkIns: [
        {
          'spotId': 'st_john',
          'spot_name': 'St. John Church',
          'timestamp': DateTime(2026, 9, 10, 10),
          'userId': 'u1',
          'touristProfile': {
            'sex': 'Male',
            'city': 'Jimenez',
            'province': 'Misamis Occidental',
            'country': 'Philippines',
            'isLocal': true,
            'localOrForeign': 'Local',
          },
        },
        {
          'spotId': 'st_john',
          'spot_name': 'St. John Church',
          'timestamp': DateTime(2026, 9, 11, 11),
          'userId': 'u2',
          'touristProfile': {
            'sex': 'Female',
            'city': 'Cebu City',
            'province': 'Cebu',
            'country': 'Philippines',
            'isLocal': true,
            'localOrForeign': 'Local',
          },
        },
      ],
      tourists: const [],
      catalogSpots: const [
        DotVar2SpotCatalogEntry(
          spotId: 'st_john',
          name: 'St. John Church',
          dotAttractionCode: '202',
        ),
      ],
      scopeLabel: 'Jimenez, Misamis Occidental',
      scopeSlug: 'jimenez',
      parseTimestamp: (c) => c['timestamp'] as DateTime?,
    );

    expect(result.checkInsProcessed, 2);
    expect(result.summary.toLowerCase(), contains('filled'));

    final excel = Excel.decodeBytes(result.bytes);
    expect(excel.tables.keys, contains('VAR 2M LGU Month Report'));
    final sheet = excel['VAR 2M LGU Month Report'];
    expect(
      sheet
          .cell(CellIndex.indexByColumnRow(columnIndex: 5, rowIndex: 5))
          .value
          ?.toString(),
      contains('Jimenez'),
    );
    expect(
      sheet
          .cell(CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: 11))
          .value
          ?.toString(),
      'St. John Church',
    );
    // This municipality male = 1
    expect(
      sheet
          .cell(CellIndex.indexByColumnRow(columnIndex: 3, rowIndex: 11))
          .value
          .toString(),
      contains('1'),
    );
    // Other province female = 1
    expect(
      sheet
          .cell(CellIndex.indexByColumnRow(columnIndex: 10, rowIndex: 11))
          .value
          .toString(),
      contains('1'),
    );

    service.dispose();
  });
}

class _FakeClient extends http.BaseClient {
  _FakeClient(this.bytes);
  final List<int> bytes;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    return http.StreamedResponse(
      Stream<List<int>>.fromIterable([bytes]),
      200,
      contentLength: bytes.length,
    );
  }
}

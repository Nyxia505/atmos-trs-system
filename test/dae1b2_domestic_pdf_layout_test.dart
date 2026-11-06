import 'dart:io';
import 'dart:typed_data';

import 'package:atmos_trs_system/config/dae_residence_catalog.dart';
import 'package:atmos_trs_system/config/supabase_report_templates_config.dart';
import 'package:atmos_trs_system/models/ae_register.dart';
import 'package:atmos_trs_system/utils/ae_register_report_query.dart';
import 'package:atmos_trs_system/utils/dot_report_pdf_export.dart';
import 'package:atmos_trs_system/utils/dot_report_preview.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AeRegisterReportData register;
  late DotFormCatalogEntry form;

  setUpAll(() {
    form = kDotFormCatalog.firstWhere((e) => e.id == 'dae1b2_domestic');
    register = AeRegisterReportData(
      reports: [
        AeMonthlyReport(
          id: 'ae1_2026_11',
          aeId: 'ae1',
          year: 2026,
          month: 11,
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
        'ae1_2026_11': [
          AeRegisterRow(
            id: 'r1',
            date: DateTime(2026, 11, 4),
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
  });

  test('domestic preview keeps PH Region of Residence on one header line', () {
    final preview = buildDotReportPreview(
      form: form,
      startDate: DateTime(2026, 11, 1),
      endDate: DateTime(2026, 11, 30),
      checkIns: const [],
      tourists: const [],
      catalogSpots: const [],
      scopeLabel: 'Hotel One',
      aeRegister: register,
    );

    expect(preview.headers.first, 'PH Region of Residence');
    expect(preview.headers.first.split(RegExp(r'\s+')).length, greaterThan(1));
    expect(preview.headers, contains('2026-11'));
    expect(preview.headers, contains('Total Arrivals'));
    expect(preview.headers, contains('Guest Nights'));
    expect(preview.rows, isNotEmpty);
  });

  test('A4 domestic PDF builds with centered manager sign-off', () async {
    final preview = buildDotReportPreview(
      form: form,
      startDate: DateTime(2026, 11, 1),
      endDate: DateTime(2026, 11, 30),
      checkIns: const [],
      tourists: const [],
      catalogSpots: const [],
      scopeLabel: 'Hotel One',
      aeRegister: register,
    );

    final signature = _sampleSignaturePng();
    final bytes = await buildDotReportPdfBytes(
      form: form,
      preview: preview,
      scopeLabel: 'Hotel One',
      startDate: DateTime(2026, 11, 1),
      endDate: DateTime(2026, 11, 30),
      paperSize: DotPdfPaperSize.a4,
      signOffs: [
        DotPdfSignOff(
          label: 'Hotel One · November 2026',
          name: 'Timmy Turdanes',
          position: 'Manager',
          action: 'submit',
          signaturePng: signature,
        ),
      ],
    );

    expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
    expect(bytes.length, greaterThan(2000));

    // Optional artifact for manual A4 layout review.
    final out = File('test_output/dae1b2_domestic_layout.pdf');
    out.parent.createSync(recursive: true);
    out.writeAsBytesSync(bytes);
  });
}

Uint8List _sampleSignaturePng() {
  // Tall transparent canvas with ink strokes near the top — mimics padded uploads.
  final canvas = img.Image(width: 400, height: 200);
  img.fill(canvas, color: img.ColorRgba8(255, 255, 255, 0));
  img.drawLine(
    canvas,
    x1: 40,
    y1: 30,
    x2: 180,
    y2: 70,
    color: img.ColorRgba8(20, 20, 20, 255),
    thickness: 3,
  );
  img.drawLine(
    canvas,
    x1: 180,
    y1: 70,
    x2: 320,
    y2: 25,
    color: img.ColorRgba8(20, 20, 20, 255),
    thickness: 3,
  );
  return Uint8List.fromList(img.encodePng(canvas));
}

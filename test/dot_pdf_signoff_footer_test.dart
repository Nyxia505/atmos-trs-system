import 'dart:typed_data';

import 'package:atmos_trs_system/config/supabase_report_templates_config.dart';
import 'package:atmos_trs_system/utils/dot_report_pdf_export.dart';
import 'package:atmos_trs_system/utils/dot_report_preview.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Uint8List signature() {
    final canvas = img.Image(width: 240, height: 80);
    img.fill(canvas, color: img.ColorRgba8(255, 255, 255, 0));
    img.drawLine(
      canvas,
      x1: 20,
      y1: 40,
      x2: 200,
      y2: 30,
      color: img.ColorRgba8(20, 20, 20, 255),
      thickness: 3,
    );
    return Uint8List.fromList(img.encodePng(canvas));
  }

  Future<Uint8List> build({
    required DotFormCatalogEntry form,
    required int rowCount,
    DotPdfPaperSize paper = DotPdfPaperSize.a4,
  }) {
    final preview = DotReportPreviewTable(
      headers: const ['Item', 'Value'],
      rows: [
        for (var i = 1; i <= rowCount; i++) ['Row $i', '$i'],
      ],
      summaryLine: '${form.code} · test · $rowCount rows',
      footer: rowCount > 0 ? ['TOTAL', '$rowCount'] : null,
      gaps: const ['Should not appear in PDF'],
    );
    return buildDotReportPdfBytes(
      form: form,
      preview: preview,
      scopeLabel: 'Seaside Inn',
      startDate: DateTime(2026, 11, 1),
      endDate: DateTime(2026, 11, 30),
      paperSize: paper,
      signOffs: [
        DotPdfSignOff(
          label: 'Seaside Inn · November 2026',
          name: 'Timmy Turdanes',
          position: 'Manager',
          action: 'submit',
          signaturePng: signature(),
        ),
      ],
    );
  }

  test('short DAE 1B.2 Domestic PDF builds with footer sign-off', () async {
    final form = kDotFormCatalog.firstWhere((e) => e.id == 'dae1b2_domestic');
    final bytes = await build(form: form, rowCount: 1);
    expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
    expect(bytes.length, greaterThan(1500));
  });

  test('5-row DAE-1A and 30-row DAE-1B PDFs build', () async {
    final a = kDotFormCatalog.firstWhere((e) => e.id == 'dae1a_manual');
    final b = kDotFormCatalog.firstWhere((e) => e.id == 'dae1b_macro');
    final short = await build(form: a, rowCount: 5);
    final long = await build(form: b, rowCount: 30);
    expect(String.fromCharCodes(short.take(5)), '%PDF-');
    expect(String.fromCharCodes(long.take(5)), '%PDF-');
  });

  test('letter paper size still builds with sign-off', () async {
    final form = kDotFormCatalog.firstWhere((e) => e.id == 'dae1b2');
    final bytes = await build(
      form: form,
      rowCount: 3,
      paper: DotPdfPaperSize.short,
    );
    expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
  });
}

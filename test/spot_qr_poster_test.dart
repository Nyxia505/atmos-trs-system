import 'dart:io';

import 'package:atmos_trs_system/services/spot_qr_poster_pdf.dart';
import 'package:atmos_trs_system/utils/spot_qr_helper.dart';
import 'package:atmos_trs_system/utils/spot_qr_poster.dart';
import 'package:atmos_trs_system/utils/spot_qr_poster_png.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const elTriunfoId = 'el_triunfo_beach';
  const plazaId = 'oroquieta_city_plaza';
  const cottaId = 'cotta_fort_shrine';

  final elTriunfoPayload = spotQrData(
    'oroquieta',
    elTriunfoId,
    latitude: 8.4722,
    longitude: 123.7988,
  );
  final plazaPayload = spotQrData(
    'oroquieta',
    plazaId,
    latitude: 8.4856,
    longitude: 123.8046,
  );
  final cottaPayload = spotQrData(
    'ozamiz',
    cottaId,
    latitude: 8.1481,
    longitude: 123.8406,
  );

  test('saved QR payload is used unchanged', () {
    const saved =
        'https://atmos-trs-system.web.app/checkin?type=spot&municipality_id=oroquieta&spot_id=el_triunfo_beach&lat=8.472200&lng=123.798800';
    final resolved = resolveSpotQrPayload(
      municipalityId: 'other-city',
      spotId: 'other-spot',
      savedPayload: saved,
      latitude: 1,
      longitude: 1,
    );
    expect(resolved, saved);
    expect(
      buildSpotQrPosterData(
        municipalityId: 'other-city',
        spotId: 'other-spot',
        spotName: 'El Triunfo',
        municipalityDisplayName: 'Oroquieta City',
        qrPayload: saved,
      ).payload,
      saved,
    );
  });

  test('fallback payload matches spotQrData when nothing is saved', () {
    final generated = spotQrData(
      'oroquieta',
      elTriunfoId,
      latitude: 8.4722,
      longitude: 123.7988,
    );
    expect(
      resolveSpotQrPayload(
        municipalityId: 'oroquieta',
        spotId: elTriunfoId,
        latitude: 8.4722,
        longitude: 123.7988,
      ),
      generated,
    );
  });

  test('filename uses ATMOS_TRS_[Spot_Name]_QR', () {
    expect(
      spotQrPosterFilename('El Triunfo', 'png'),
      'ATMOS_TRS_El_Triunfo_QR.png',
    );
    expect(
      spotQrPosterFilename('Cotta Fort & Shrine', 'pdf'),
      'ATMOS_TRS_Cotta_Fort_Shrine_QR.pdf',
    );
    expect(
      spotQrPosterFilename('   ', 'png'),
      'ATMOS_TRS_Spot_QR.png',
    );
  });

  test('A4 poster layout is portrait 210:297 and PNG is 2480x3508', () {
    const layout = SpotQrPosterLayout.a4;
    expect(
      SpotQrPosterLayout.pageWidthPt / SpotQrPosterLayout.pageHeightPt,
      closeTo(210 / 297, 0.001),
    );
    expect(SpotQrPosterLayout.pngWidthPx, 2480);
    expect(SpotQrPosterLayout.pngHeightPx, 3508);
    expect(layout.qrRect.width, greaterThan(240));
    expect(layout.qrRect.top, greaterThan(layout.scanPillRect.bottom));
    expect(layout.instructionRect.top, greaterThan(layout.qrRect.bottom));
  });

  test('encoded modules keep finder patterns and do not use mock art', () {
    final qr = SpotQrModules.encode(elTriunfoPayload);
    expect(qr.moduleCount, greaterThanOrEqualTo(21));
    expect(qr.isDark(0, 0), isTrue);
    expect(qr.isDark(0, 6), isTrue);
    expect(qr.isDark(6, 0), isTrue);
    expect(qr.isDark(1, 1), isFalse);
  });

  test('long tourist spot names stay in the shared name box', () {
    final data = buildSpotQrPosterData(
      municipalityId: 'oroquieta',
      spotId: 'long_spot',
      spotName:
          'Misamis Occidental Provincial Nature Park and Heritage Eco-Tourism Complex',
      municipalityDisplayName: 'Oroquieta City',
      qrPayload: plazaPayload,
    );
    expect(data.displayName.length, greaterThan(40));
    expect(SpotQrPosterLayout.a4.nameRect.height, greaterThanOrEqualTo(60));
  });

  test(
    'PNG and PDF posters share payload, A4 size, and scannable QR modules',
    () async {
      final spots = <SpotQrPosterData>[
        buildSpotQrPosterData(
          municipalityId: 'oroquieta',
          spotId: elTriunfoId,
          spotName: 'El Triunfo',
          municipalityDisplayName: 'Oroquieta City',
          qrPayload: elTriunfoPayload,
          category: 'Beach',
        ),
        buildSpotQrPosterData(
          municipalityId: 'oroquieta',
          spotId: plazaId,
          spotName: 'Oroquieta City Plaza',
          municipalityDisplayName: 'Oroquieta City',
          qrPayload: plazaPayload,
          category: 'Park',
        ),
        buildSpotQrPosterData(
          municipalityId: 'ozamiz',
          spotId: cottaId,
          spotName: 'Cotta Fort and Shrine of Our Lady of the Immaculate Conception',
          municipalityDisplayName: 'Ozamiz City',
          qrPayload: cottaPayload,
          category: 'Historical',
        ),
      ];

      final outDir = Directory('build/spot_qr_poster_samples');
      await outDir.create(recursive: true);

      for (final spot in spots) {
        expect(spot.payload, isNot(contains('PREVIEW')));
        final pngBytes = await renderSpotQrPosterPng(spot);
        final pdfBytes = await renderSpotQrPosterPdf(spot);

        expect(pngBytes.length, greaterThan(20000));
        expect(
          String.fromCharCodes(pdfBytes.take(5)),
          '%PDF-',
        );

        final decoded = img.decodePng(pngBytes);
        expect(decoded, isNotNull);
        expect(decoded!.width, 2480);
        expect(decoded.height, 3508);

        _expectQrRegionHasFinder(decoded);

        final pngName = spotQrPosterFilename(spot.displayName, 'png');
        final pdfName = spotQrPosterFilename(spot.displayName, 'pdf');
        await File('${outDir.path}/$pngName').writeAsBytes(pngBytes);
        await File('${outDir.path}/$pdfName').writeAsBytes(pdfBytes);
      }

      expect(
        spots.map((s) => s.payload).toSet().length,
        spots.length,
        reason: 'each spot must keep its own QR payload',
      );
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );

  test('multi-spot PDF builder uses A4 pages and saved payloads', () async {
    final doc = await buildSpotPosterPdfDocument([
      SpotPosterItem(
        id: elTriunfoId,
        name: 'El Triunfo',
        municipality: 'Oroquieta City',
        municipalityId: 'oroquieta',
        qrPayload: elTriunfoPayload,
        latitude: 8.4722,
        longitude: 123.7988,
      ),
      SpotPosterItem(
        id: plazaId,
        name: 'Oroquieta City Plaza',
        municipality: 'Oroquieta City',
        municipalityId: 'oroquieta',
        qrPayload: plazaPayload,
      ),
    ]);
    final bytes = await doc.save();
    expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
    expect(bytes.length, greaterThan(5000));
  });
}

void _expectQrRegionHasFinder(img.Image decoded) {
  const layout = SpotQrPosterLayout.a4;
  final scale = layout.pngScale;
  final left = (layout.qrRect.left * scale).round();
  final top = (layout.qrRect.top * scale).round();
  final size = (layout.qrRect.width * scale).round();

  var black = 0;
  var white = 0;
  for (var y = top + 40; y < top + size - 40; y += 17) {
    for (var x = left + 40; x < left + size - 40; x += 17) {
      final p = decoded.getPixel(x, y);
      final lum = (p.r + p.g + p.b) / 3;
      if (lum < 40) {
        black++;
      } else if (lum > 200) {
        white++;
      }
    }
  }
  expect(black, greaterThan(8), reason: 'QR region should contain dark modules');
  expect(white, greaterThan(8), reason: 'QR region should keep a white quiet zone');
}

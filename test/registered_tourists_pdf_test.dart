import 'package:atmos_trs_system/utils/lgu_registered_tourists_xlsx.dart';
import 'package:atmos_trs_system/utils/registered_tourists_pdf.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('registered tourists PDF is a valid PDF', () async {
    final bytes = await buildRegisteredTouristsPdf(
      officeLabel: "Governor's Office",
      location: 'Misamis Occidental',
      generatedAt: DateTime(2026, 11, 1, 20),
      privacyLabel: 'Privacy-safe Governor export',
      rows: [
        lguRegisteredTouristExportRowFromMap({
          'touristId': 'MO-B1CFA9DD',
          'isLocal': true,
          'city': 'Oroquieta City',
          'totalVisits': 2,
          'fullName': 'Hidden Name',
          'email': 'hidden@example.com',
        }),
      ],
    );
    expect(bytes.take(4).toList(), [0x25, 0x50, 0x44, 0x46]);
    expect(
      registeredTouristsPdfFilename(
        location: 'Misamis Occidental',
        generatedAt: DateTime(2026, 11, 1),
      ),
      'ATMOS_TRS_Registered_Tourists_misamis_occidental_2026-11-01.pdf',
    );
  });
}

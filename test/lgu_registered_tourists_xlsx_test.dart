import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:atmos_trs_system/utils/lgu_registered_tourists_xlsx.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final generatedAt = DateTime(2026, 10, 28, 14, 5, 9);

  LguRegisteredTouristsXlsx workbook({
    required List<Map<String, dynamic>> tourists,
    bool includePii = false,
  }) {
    return LguRegisteredTouristsXlsx(
      lguLocation: 'Jimenez, Misamis Occidental',
      rows: tourists.map(lguRegisteredTouristExportRowFromMap).toList(),
      generatedAt: generatedAt,
      includeRestrictedPersonalInfo: includePii,
    );
  }

  test('privacy-safe LGU export omits names, emails and mobiles', () {
    final bytes = workbook(tourists: _liveTourists).buildBytes();
    final xml = _allXml(bytes);

    expect(xml, contains('MO-B1CFA9DD'));
    expect(xml, contains('MO-A22F10CE'));
    expect(xml, contains('MO-C9D813AA'));
    expect(xml, contains('Jimenez, Misamis Occidental'));
    expect(xml, contains('ATMOS TRS | REGISTERED TOURISTS'));
    expect(xml, isNot(contains('Jane Doe')));
    expect(xml, isNot(contains('Ken Watanabe')));
    expect(xml, isNot(contains('jane@example.com')));
    expect(xml, isNot(contains('09171234567')));
    expect(xml, isNot(contains('ken@example.jp')));
    expect(xml, isNot(contains('Full Name')));
    expect(xml, isNot(contains('Email')));
    expect(xml, isNot(contains('Mobile')));
  });

  test('Governor export keeps LGU columns and omits personal names', () {
    final bytes = LguRegisteredTouristsXlsx(
      lguLocation: 'Misamis Occidental',
      officeLabel: "Governor's Office",
      privacyLabel: 'Privacy-safe Governor export',
      generatedAt: generatedAt,
      rows: _liveTourists.map(lguRegisteredTouristExportRowFromMap).toList(),
    ).buildBytes();
    final xml = _allXml(bytes);
    expect(xml, contains("Governor's Office"));
    expect(xml, contains('Misamis Occidental'));
    expect(xml, contains('MO-B1CFA9DD'));
    expect(xml, isNot(contains('Jane Doe')));
    expect(xml, isNot(contains('jane@example.com')));
  });

  test('authorized export may include restricted personal information', () {
    final bytes = workbook(
      tourists: _liveTourists,
      includePii: true,
    ).buildBytes();
    final xml = _allXml(bytes);
    expect(xml, contains('Jane Doe'));
    expect(xml, contains('jane@example.com'));
    expect(xml, contains('09171234567'));
  });

  test('workbook includes every loaded tourist, not a page subset', () {
    final bytes = workbook(tourists: _liveTourists).buildBytes();
    expect(_sheet(bytes, 'xl/sharedStrings.xml'), contains('MO-B1CFA9DD'));
    expect(_sheet(bytes, 'xl/sharedStrings.xml'), contains('MO-A22F10CE'));
    expect(_sheet(bytes, 'xl/sharedStrings.xml'), contains('MO-C9D813AA'));
    expect(_sheet(bytes, 'xl/sharedStrings.xml'), contains('Local'));
    expect(_sheet(bytes, 'xl/sharedStrings.xml'), contains('Foreign'));
    expect(
      _sheet(bytes, 'xl/sharedStrings.xml'),
      contains('Jimenez, Misamis Occidental, Philippines'),
    );
    expect(_sheet(bytes, 'xl/sharedStrings.xml'), contains('2026-03-04'));
    expect(_sheet(bytes, 'xl/sharedStrings.xml'), contains('9:15:00 AM'));
  });

  test('Summary formulas cover the full data range', () {
    final bytes = workbook(tourists: _liveTourists).buildBytes();
    final summary = _firstSheetContaining(bytes, 'COUNTA');
    expect(
      summary,
      contains("COUNTA('Registered Tourists'!A7:A9)"),
    );
    expect(
      summary,
      contains('COUNTIF(\'Registered Tourists\'!B7:B9,"Local")'),
    );
    expect(
      summary,
      contains('COUNTIF(\'Registered Tourists\'!B7:B9,"Foreign")'),
    );
    expect(
      summary,
      contains("SUM('Registered Tourists'!D7:D9)"),
    );
  });

  test('data sheet freezes headers and has no filter dropdowns', () {
    final bytes = workbook(tourists: _liveTourists).buildBytes();
    final xml = _allXml(bytes);
    expect(xml, contains('state="frozen"'));
    expect(xml, contains('ySplit="6"'));
    expect(xml, contains('topLeftCell="A7"'));
    expect(xml, isNot(contains('<autoFilter')));
    expect(xml, isNot(contains('<tableParts')));
    expect(_sheet(bytes, 'xl/tables/table1.xml'), isEmpty);
  });

  test('empty registry still builds formula workbook without sample rows', () {
    final bytes = workbook(tourists: const []).buildBytes();
    final xml = _allXml(bytes);
    expect(xml, isNot(contains('MO-')));
    expect(xml, contains("COUNTA('Registered Tourists'!A7:A7)"));
  });

  test('filename uses LGU location and date', () {
    expect(
      lguRegisteredTouristsXlsxFilename(
        lguLocation: 'Jimenez, Misamis Occidental',
        generatedAt: generatedAt,
      ),
      'ATMOS_TRS_Registered_Tourists_jimenez_misamis_occidental_2026-10-28.xlsx',
    );
  });

  test('row mapping preserves tourist id, visits, type and origin', () {
    final row = lguRegisteredTouristExportRowFromMap(_liveTourists.first);
    expect(row.touristId, 'MO-B1CFA9DD');
    expect(row.type, 'Local');
    expect(row.origin, 'Jimenez, Misamis Occidental, Philippines');
    expect(row.visits, 4);
    expect(row.registeredDate, '2026-03-04');
    expect(row.registeredTime, '9:15:00 AM');
  });
}

const _liveTourists = [
  {
    'touristId': 'MO-B1CFA9DD',
    'fullName': 'Jane Doe',
    'email': 'jane@example.com',
    'mobile': '09171234567',
    'isLocal': true,
    'city': 'Jimenez',
    'province': 'Misamis Occidental',
    'country': 'Philippines',
    'totalVisits': 4,
    'status': 'Active',
    'registeredAt': '2026-03-04T09:15:00',
  },
  {
    'touristId': 'MO-A22F10CE',
    'name': 'Ken Watanabe',
    'email': 'ken@example.jp',
    'localOrForeign': 'Foreign',
    'country': 'Japan',
    'visits': 2,
    'registeredAt': '2026-03-05T16:02:00',
  },
  {
    'touristId': 'MO-C9D813AA',
    'firstName': 'Maria',
    'lastName': 'Santos',
    'isLocal': true,
    'city': 'Oroquieta City',
    'province': 'Misamis Occidental',
    'country': 'Philippines',
    'totalVisits': '3',
    'registeredAt': '2026-03-06T08:40:00',
  },
];

String _allXml(List<int> bytes) {
  final archive = ZipDecoder().decodeBytes(bytes);
  final buf = StringBuffer();
  for (final f in archive) {
    if (!f.isFile) continue;
    buf.write(utf8.decode(f.content as List<int>, allowMalformed: true));
    buf.write('\n');
  }
  return buf.toString();
}

String _sheet(List<int> bytes, String name) {
  final archive = ZipDecoder().decodeBytes(bytes);
  final file = archive.files.firstWhere(
    (f) => f.name.replaceAll('\\', '/') == name,
    orElse: () => ArchiveFile(name, 0, const <int>[]),
  );
  return utf8.decode(file.content as List<int>, allowMalformed: true);
}

String _firstSheetContaining(List<int> bytes, String needle) {
  final archive = ZipDecoder().decodeBytes(bytes);
  for (final f in archive) {
    if (!f.isFile) continue;
    final xml = utf8.decode(f.content as List<int>, allowMalformed: true);
    if (xml.contains(needle)) return xml;
  }
  fail('No workbook part contained "$needle"');
}

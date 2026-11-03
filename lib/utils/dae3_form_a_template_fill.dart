import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:atmos_trs_system/config/dae_residence_catalog.dart';
import 'package:atmos_trs_system/models/ae_register.dart';
import 'package:atmos_trs_system/utils/ae_register_report_query.dart';

/// Fills `forms_format/DAE3B_FORM_A-International.xlsx` in place.
///
/// Sheet 1 — one column per establishment for the busiest month.
/// Sheet 2 — that month's province total.
/// Sheet 3 — DAE3. FORM A monthly grid (January–December), the sheet in the
/// official template screenshot.
///
/// SUB-TOTAL, TOTAL, occupancy, and ALOS stay as Excel formulas.
class Dae3FormATemplateFill {
  const Dae3FormATemplateFill._();

  static const _months = [
    'January',
    'February',
    'March',
    'April',
    'May',
    'June',
    'July',
    'August',
    'September',
    'October',
    'November',
    'December',
  ];

  /// Country leaf rows on "LGU FORM A by Country" and the Sum sheet.
  static const _aeRow = <String, int>{
    'filipinonationality': 16,
    'foreignnationality': 17,
    'brunei': 24,
    'cambodia': 25,
    'indonesia': 26,
    'laos': 27,
    'malaysia': 28,
    'myanmar': 29,
    'singapore': 30,
    'thailand': 31,
    'vietnam': 32,
    'china': 36,
    'hongkong': 37,
    'japan': 38,
    'korea': 39,
    'macau': 40,
    'taiwan': 41,
    'bangladesh': 45,
    'india': 46,
    'iran': 47,
    'nepal': 48,
    'pakistan': 49,
    'srilanka': 50,
    'bahrain': 54,
    'egypt': 55,
    'oman': 56,
    'israel': 57,
    'jordan': 58,
    'kuwait': 59,
    'qatar': 60,
    'saudiarabia': 61,
    'unitedarabemirates': 62,
    'canada': 68,
    'mexico': 69,
    'usa': 70,
    'argentina': 74,
    'brazil': 75,
    'colombia': 76,
    'peru': 77,
    'venezuela': 78,
    'andorra': 83,
    'austria': 84,
    'belgium': 85,
    'france': 86,
    'germany': 87,
    'luxembourg': 88,
    'netherlands': 89,
    'switzerland': 90,
    'denmark': 94,
    'finland': 95,
    'ireland': 96,
    'norway': 97,
    'sweden': 98,
    'unitedkingdom': 99,
    'greece': 103,
    'italy': 104,
    'portugal': 105,
    'spain': 106,
    'commonwealthofindependentstates': 110,
    'poland': 111,
    'russia': 112,
    'turkey': 116,
    'australia': 120,
    'guam': 121,
    'nauru': 122,
    'newzealand': 123,
    'papuanewguinea': 124,
    'nigeria': 130,
    'southafrica': 131,
    'others': 135,
    'overseas': 139,
  };

  /// Country leaf rows on "LGU FORM A by Country (Monthly)" / DAE3. FORM A.
  static const _monthRow = <String, int>{
    'filipinonationality': 16,
    'foreignnationality': 17,
    'brunei': 24,
    'cambodia': 25,
    'indonesia': 26,
    'laos': 27,
    'malaysia': 28,
    'myanmar': 29,
    'singapore': 30,
    'thailand': 31,
    'vietnam': 32,
    'china': 36,
    'hongkong': 37,
    'japan': 38,
    'korea': 39,
    'macau': 40,
    'taiwan': 41,
    'bangladesh': 45,
    'india': 46,
    'iran': 47,
    'nepal': 48,
    'pakistan': 49,
    'srilanka': 50,
    'bahrain': 54,
    'egypt': 55,
    'oman': 56,
    'jordan': 57,
    'kuwait': 58,
    'saudiarabia': 60,
    'unitedarabemirates': 61,
    'canada': 67,
    'mexico': 68,
    'usa': 69,
    'argentina': 73,
    'brazil': 74,
    'colombia': 75,
    'peru': 76,
    'venezuela': 77,
    'andorra': 82,
    'austria': 83,
    'belgium': 84,
    'france': 85,
    'germany': 86,
    'luxembourg': 87,
    'netherlands': 88,
    'switzerland': 89,
    'denmark': 93,
    'finland': 94,
    'ireland': 95,
    'norway': 96,
    'sweden': 97,
    'unitedkingdom': 98,
    'greece': 102,
    'italy': 103,
    'portugal': 104,
    'spain': 105,
    'commonwealthofindependentstates': 109,
    'poland': 110,
    'russia': 111,
    'israel': 114,
    'turkey': 115,
    'australia': 119,
    'guam': 120,
    'nauru': 121,
    'newzealand': 122,
    'papuanewguinea': 123,
    'nigeria': 129,
    'southafrica': 130,
    'others': 134,
    'overseas': 138,
  };

  static const _alias = <String, String>{
    'hongkongsar': 'hongkong',
    'southkorea': 'korea',
    'koreasouth': 'korea',
    'republicofkorea': 'korea',
    'unitedstates': 'usa',
    'unitedstatesofamerica': 'usa',
    'uk': 'unitedkingdom',
    'uae': 'unitedarabemirates',
    'irelandrepublicof': 'ireland',
    'russianfederation': 'russia',
    'macao': 'macau',
    'commonwealthofis': 'commonwealthofindependentstates',
  };

  static Dae3FormAFillResult fill({
    required List<int> templateBytes,
    required AeRegisterReportData register,
    required String scopeLabel,
  }) {
    final gaps = <String>[
      'Official DAE3. FORM A workbook filled from hotel DOT registers.',
      'All three sheets are filled: by establishment, province sum, and the monthly DAE3. FORM A grid.',
      'Open the file in Excel so SUB-TOTAL, TOTAL, occupancy, and length-of-stay formulas recalculate.',
      'Israel is on the Middle East row of the establishment and sum sheets, and on East Mediterranean on the monthly sheet.',
      'Qatar has no monthly row, so those guests are on Others and unspecified on the monthly sheet.',
    ];
    if (register.reports.isEmpty) {
      gaps.add('No hotel DOT register months in range — workbook left blank.');
      return Dae3FormAFillResult(
        bytes: templateBytes,
        gaps: gaps,
        summary: 'DAE3 Form A unchanged (no register months)',
        arrivals: 0,
      );
    }

    final year = _focusYear(register);
    final inYear = register.reports.where((r) => r.year == year).toList();
    final focusMonth = _focusMonth(inYear);
    final otherYears = register.reports.where((r) => r.year != year).length;
    if (otherYears > 0) {
      gaps.add(
        'Monthly columns are one calendar year. $year was filled; $otherYears month(s) in other years were left off.',
      );
    }

    final byMonth = <int, _Slice>{};
    for (final report in inYear) {
      final slice = _sliceOf(report);
      byMonth[report.month] = (byMonth[report.month] ?? const _Slice.empty()) + slice;
    }
    final aes = _aesForMonth(inYear, focusMonth);
    if (aes.length > 23) {
      gaps.add(
        '${aes.length} establishments in ${_months[focusMonth - 1]} $year. The first 23 are on the by-establishment sheet; the monthly sheet still includes everyone.',
      );
    }

    final city = _cityOf(scopeLabel, inYear);
    final province = _provinceOf(scopeLabel);
    final period = byMonth.length == 1
        ? '${_months[byMonth.keys.first - 1]} $year'
        : '$year';

    final archive = ZipDecoder().decodeBytes(templateBytes);
    final files = <String, String>{};
    for (final file in archive) {
      if (!file.isFile) continue;
      final name = file.name.replaceAll('\\', '/');
      if (!name.endsWith('.xml') && !name.endsWith('.rels')) continue;
      files[name] = utf8.decode(file.content as List<int>, allowMalformed: true);
    }

    void patch(String name, String Function(String xml) edit) {
      final xml = files[name];
      if (xml == null) return;
      files[name] = edit(xml);
    }

    String paint(
      String xml,
      Map<String, int> rows,
      Map<String, _Slice> columns,
      _IndicatorRows indicators,
    ) {
      xml = _header(xml, period: period, city: city, province: province);
      xml = _writeCounts(
        xml,
        rows: rows,
        columns: {for (final e in columns.entries) e.key: e.value.counts},
      );
      xml = _writeIndicators(xml, columns: columns, rows: indicators);
      return xml;
    }

    final shown = aes.take(23).toList();
    patch('xl/worksheets/sheet1.xml', (xml) {
      xml = paint(
        xml,
        _aeRow,
        {for (var i = 0; i < shown.length; i++) _col(2 + i): shown[i].slice},
        _aeIndicators,
      );
      for (var i = 0; i < shown.length; i++) {
        xml = _setText(xml, '${_col(2 + i)}13', shown[i].name);
      }
      return xml;
    });

    final monthSlice = byMonth[focusMonth] ?? const _Slice.empty();
    patch('xl/worksheets/sheet2.xml', (xml) {
      return paint(xml, _aeRow, {'B': monthSlice}, _aeIndicators);
    });

    patch('xl/worksheets/sheet3.xml', (xml) {
      return paint(
        xml,
        _monthRow,
        {
          for (final e in byMonth.entries)
            if (e.key >= 1 && e.key <= 12) _col(1 + e.key): e.value,
        },
        _monthIndicators,
      );
    });

    patch('xl/workbook.xml', (xml) {
      if (!xml.contains('fullCalcOnLoad')) {
        xml = xml.replaceFirst('<calcPr ', '<calcPr fullCalcOnLoad="1" ');
      }
      if (!xml.contains('ATMOS_GAPS')) {
        xml = xml.replaceFirst(
          '</sheets>',
          '<sheet name="ATMOS_GAPS" sheetId="90" r:id="rId90"/></sheets>',
        );
      }
      return xml;
    });
    patch('xl/_rels/workbook.xml.rels', (xml) {
      xml = xml.replaceAll(RegExp(r'<Relationship[^>]*calcChain[^>]*/>'), '');
      if (!xml.contains('rId90')) {
        xml = xml.replaceFirst(
          '</Relationships>',
          '<Relationship Id="rId90" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet90.xml"/></Relationships>',
        );
      }
      return xml;
    });
    patch('[Content_Types].xml', (xml) {
      xml = xml.replaceAll(RegExp(r'<Override[^>]*calcChain[^>]*/>'), '');
      if (!xml.contains('sheet90.xml')) {
        xml = xml.replaceFirst(
          '</Types>',
          '<Override PartName="/xl/worksheets/sheet90.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/></Types>',
        );
      }
      return xml;
    });
    files['xl/worksheets/sheet90.xml'] = _gapsSheet(gaps);

    final out = Archive();
    final written = <String>{};
    for (final file in archive) {
      if (!file.isFile) continue;
      final name = file.name.replaceAll('\\', '/');
      if (name.contains('calcChain')) continue;
      final body = files[name];
      final bytes = body != null ? utf8.encode(body) : (file.content as List<int>);
      out.addFile(ArchiveFile(name, bytes.length, bytes));
      written.add(name);
    }
    if (!written.contains('xl/worksheets/sheet90.xml')) {
      final bytes = utf8.encode(files['xl/worksheets/sheet90.xml']!);
      out.addFile(ArchiveFile('xl/worksheets/sheet90.xml', bytes.length, bytes));
    }

    final encoded = ZipEncoder().encode(out);
    final arrivals = byMonth.values.fold<int>(0, (s, v) => s + v.arrivals);
    return Dae3FormAFillResult(
      bytes: encoded ?? templateBytes,
      gaps: gaps,
      summary:
          'DAE3 Form A filled for $year · ${byMonth.length} month(s) on the monthly sheet · '
          '${_months[focusMonth - 1]} on the establishment and sum sheets · '
          '${aes.length} establishment(s) · $arrivals arrivals · $scopeLabel',
      arrivals: arrivals,
    );
  }

  static const _aeIndicators = _IndicatorRows(
    roomsOccupied: 150,
    roomsAvailable: 151,
    guestNights: 152,
    malePhilippine: 158,
    maleForeign: 159,
    maleOverseas: 160,
    maleUnspecified: 161,
    femalePhilippine: 164,
    femaleForeign: 165,
    femaleOverseas: 166,
    femaleUnspecified: 167,
  );

  static const _monthIndicators = _IndicatorRows(
    roomsOccupied: 149,
    roomsAvailable: 150,
    guestNights: 151,
    malePhilippine: 157,
    maleForeign: 158,
    maleOverseas: 159,
    maleUnspecified: 160,
    femalePhilippine: 163,
    femaleForeign: 164,
    femaleOverseas: 165,
    femaleUnspecified: 166,
  );

  static int _focusYear(AeRegisterReportData register) {
    final counts = <int, int>{};
    for (final r in register.reports) {
      counts[r.year] = (counts[r.year] ?? 0) + r.totals.checkIns;
    }
    return counts.entries.reduce((a, b) => a.value >= b.value ? a : b).key;
  }

  static int _focusMonth(List<AeMonthlyReport> reports) {
    final counts = <int, int>{};
    for (final r in reports) {
      counts[r.month] = (counts[r.month] ?? 0) + r.totals.checkIns;
    }
    return counts.entries.reduce((a, b) => a.value >= b.value ? a : b).key;
  }

  static List<_AeCol> _aesForMonth(List<AeMonthlyReport> reports, int month) {
    final byId = <String, _AeCol>{};
    for (final r in reports.where((r) => r.month == month)) {
      final slice = _sliceOf(r);
      final prev = byId[r.aeId];
      final name = r.aeName.trim().isEmpty ? r.aeId : r.aeName.trim();
      byId[r.aeId] = _AeCol(name, (prev?.slice ?? const _Slice.empty()) + slice);
    }
    final list = byId.values.toList()
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return list;
  }

  static _Slice _sliceOf(AeMonthlyReport report) {
    final counts = <String, int>{};
    var malePh = 0, maleForeign = 0, maleOfw = 0, maleUnk = 0;
    var femalePh = 0, femaleForeign = 0, femaleOfw = 0, femaleUnk = 0;
    var arrivals = 0;
    report.totals.byCountry.forEach((residence, totals) {
      if (totals.arrivals == 0 && totals.male == 0 && totals.female == 0) return;
      final key = _rowKey(residence);
      counts[key] = (counts[key] ?? 0) + totals.arrivals;
      arrivals += totals.arrivals;
      switch (DaeResidenceCatalog.bucketFor(residence)) {
        case DaeResidenceBucket.philippineResident:
          malePh += totals.male;
          femalePh += totals.female;
        case DaeResidenceBucket.foreign:
          maleForeign += totals.male;
          femaleForeign += totals.female;
        case DaeResidenceBucket.overseasFilipino:
          maleOfw += totals.male;
          femaleOfw += totals.female;
        case DaeResidenceBucket.unspecified:
          maleUnk += totals.male;
          femaleUnk += totals.female;
      }
    });
    final days = DateTime(report.year, report.month + 1, 0).day;
    final roomsAvailable = report.totalRooms > 0 ? report.totalRooms * days : 0;
    return _Slice(
      counts: counts,
      arrivals: arrivals,
      roomsOccupied: report.totals.roomsOccupied,
      roomsAvailable: roomsAvailable,
      guestNights: report.totals.guestNights,
      malePhilippine: malePh,
      maleForeign: maleForeign,
      maleOverseas: maleOfw,
      maleUnspecified: maleUnk,
      femalePhilippine: femalePh,
      femaleForeign: femaleForeign,
      femaleOverseas: femaleOfw,
      femaleUnspecified: femaleUnk,
    );
  }

  static String _rowKey(String residence) {
    final bucket = DaeResidenceCatalog.bucketFor(residence);
    if (bucket == DaeResidenceBucket.philippineResident) {
      return residence.trim() == DaeResidenceCatalog.phForeignNational
          ? 'foreignnationality'
          : 'filipinonationality';
    }
    if (bucket == DaeResidenceBucket.overseasFilipino) return 'overseas';
    if (bucket == DaeResidenceBucket.unspecified) return 'others';
    final known = DaeResidenceCatalog.countryFor(residence);
    final norm = _norm(known?.label ?? residence);
    if (_monthRow.containsKey(norm) || _aeRow.containsKey(norm)) return norm;
    final alias = _alias[norm];
    if (alias != null) return alias;
    return 'others';
  }

  static String _cityOf(String scopeLabel, List<AeMonthlyReport> reports) {
    final names = reports.map((r) => r.municipality.trim()).where((s) => s.isNotEmpty).toSet();
    if (names.length == 1) return names.first;
    final scope = scopeLabel.trim();
    if (scope.isEmpty) return '';
    final comma = scope.indexOf(',');
    return comma > 0 ? scope.substring(0, comma).trim() : scope;
  }

  static String _provinceOf(String scopeLabel) {
    final parts = scopeLabel.split(',');
    if (parts.length > 1 && parts.last.trim().isNotEmpty) return parts.last.trim();
    return 'Misamis Occidental';
  }

  static String _header(
    String xml, {
    required String period,
    required String city,
    required String province,
  }) {
    xml = _setText(xml, 'A3', 'Region: X');
    xml = _setText(xml, 'A5', period);
    if (city.isNotEmpty) xml = _setText(xml, 'B10', city);
    if (province.isNotEmpty) xml = _setText(xml, 'B11', province);
    return xml;
  }

  static String _writeCounts(
    String xml, {
    required Map<String, int> rows,
    required Map<String, Map<String, int>> columns,
  }) {
    for (final col in columns.entries) {
      for (final count in col.value.entries) {
        if (count.value == 0) continue;
        final row = rows[count.key];
        if (row == null) continue;
        xml = _setNumber(xml, '${col.key}$row', count.value);
      }
    }
    return xml;
  }

  static String _writeIndicators(
    String xml, {
    required Map<String, _Slice> columns,
    required _IndicatorRows rows,
  }) {
    for (final e in columns.entries) {
      final s = e.value;
      void put(int row, int value) {
        if (value <= 0) return;
        xml = _setNumber(xml, '${e.key}$row', value);
      }

      put(rows.roomsOccupied, s.roomsOccupied);
      put(rows.roomsAvailable, s.roomsAvailable);
      put(rows.guestNights, s.guestNights);
      put(rows.malePhilippine, s.malePhilippine);
      put(rows.maleForeign, s.maleForeign);
      put(rows.maleOverseas, s.maleOverseas);
      put(rows.maleUnspecified, s.maleUnspecified);
      put(rows.femalePhilippine, s.femalePhilippine);
      put(rows.femaleForeign, s.femaleForeign);
      put(rows.femaleOverseas, s.femaleOverseas);
      put(rows.femaleUnspecified, s.femaleUnspecified);
    }
    return xml;
  }

  static String _setNumber(String xml, String ref, num value) {
    final text = value.round().toString();
    return _replaceCell(xml, ref, (style) => '<c r="$ref"$style><v>$text</v></c>');
  }

  static String _setText(String xml, String ref, String text) {
    final safe = text.replaceAll('&', '&amp;').replaceAll('<', '&lt;').replaceAll('>', '&gt;');
    return _replaceCell(
      xml,
      ref,
      (style) => '<c r="$ref"$style t="inlineStr"><is><t xml:space="preserve">$safe</t></is></c>',
    );
  }

  static String _replaceCell(String xml, String ref, String Function(String style) build) {
    final re = RegExp('<c r="${RegExp.escape(ref)}"(?:[^>/]*/>|[^>]*>.*?</c>)', dotAll: true);
    final match = re.firstMatch(xml);
    if (match == null) return xml;
    final styleMatch = RegExp(' s="(\\d+)"').firstMatch(match.group(0)!);
    final style = styleMatch == null ? '' : ' s="${styleMatch.group(1)}"';
    return xml.replaceFirst(re, build(style));
  }

  static String _gapsSheet(List<String> gaps) {
    final rows = StringBuffer();
    for (var i = 0; i < gaps.length; i++) {
      final row = i + 1;
      final safe = gaps[i].replaceAll('&', '&amp;').replaceAll('<', '&lt;').replaceAll('>', '&gt;');
      rows.write(
        '<row r="$row"><c r="A$row" t="inlineStr"><is><t xml:space="preserve">$safe</t></is></c></row>',
      );
    }
    return '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">'
        '<sheetData>$rows</sheetData></worksheet>';
  }

  static String _col(int index) {
    var n = index;
    var s = '';
    while (n > 0) {
      n--;
      s = String.fromCharCode(65 + (n % 26)) + s;
      n ~/= 26;
    }
    return s;
  }

  static String _norm(String raw) => raw.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
}

class Dae3FormAFillResult {
  const Dae3FormAFillResult({
    required this.bytes,
    required this.gaps,
    required this.summary,
    required this.arrivals,
  });

  final List<int> bytes;
  final List<String> gaps;
  final String summary;
  final int arrivals;
}

class _IndicatorRows {
  const _IndicatorRows({
    required this.roomsOccupied,
    required this.roomsAvailable,
    required this.guestNights,
    required this.malePhilippine,
    required this.maleForeign,
    required this.maleOverseas,
    required this.maleUnspecified,
    required this.femalePhilippine,
    required this.femaleForeign,
    required this.femaleOverseas,
    required this.femaleUnspecified,
  });

  final int roomsOccupied;
  final int roomsAvailable;
  final int guestNights;
  final int malePhilippine;
  final int maleForeign;
  final int maleOverseas;
  final int maleUnspecified;
  final int femalePhilippine;
  final int femaleForeign;
  final int femaleOverseas;
  final int femaleUnspecified;
}

class _Slice {
  const _Slice({
    this.counts = const {},
    this.arrivals = 0,
    this.roomsOccupied = 0,
    this.roomsAvailable = 0,
    this.guestNights = 0,
    this.malePhilippine = 0,
    this.maleForeign = 0,
    this.maleOverseas = 0,
    this.maleUnspecified = 0,
    this.femalePhilippine = 0,
    this.femaleForeign = 0,
    this.femaleOverseas = 0,
    this.femaleUnspecified = 0,
  });

  const _Slice.empty() : this();

  final Map<String, int> counts;
  final int arrivals;
  final int roomsOccupied;
  final int roomsAvailable;
  final int guestNights;
  final int malePhilippine;
  final int maleForeign;
  final int maleOverseas;
  final int maleUnspecified;
  final int femalePhilippine;
  final int femaleForeign;
  final int femaleOverseas;
  final int femaleUnspecified;

  Map<String, int> get indicators => counts;

  _Slice operator +(_Slice o) {
    final counts = Map<String, int>.from(this.counts);
    o.counts.forEach((k, v) => counts[k] = (counts[k] ?? 0) + v);
    return _Slice(
      counts: counts,
      arrivals: arrivals + o.arrivals,
      roomsOccupied: roomsOccupied + o.roomsOccupied,
      roomsAvailable: roomsAvailable + o.roomsAvailable,
      guestNights: guestNights + o.guestNights,
      malePhilippine: malePhilippine + o.malePhilippine,
      maleForeign: maleForeign + o.maleForeign,
      maleOverseas: maleOverseas + o.maleOverseas,
      maleUnspecified: maleUnspecified + o.maleUnspecified,
      femalePhilippine: femalePhilippine + o.femalePhilippine,
      femaleForeign: femaleForeign + o.femaleForeign,
      femaleOverseas: femaleOverseas + o.femaleOverseas,
      femaleUnspecified: femaleUnspecified + o.femaleUnspecified,
    );
  }
}

class _AeCol {
  const _AeCol(this.name, this.slice);

  final String name;
  final _Slice slice;

  Map<String, int> get counts => slice.counts;
}

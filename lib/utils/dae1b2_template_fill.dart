import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:atmos_trs_system/config/dae_residence_catalog.dart';
import 'package:atmos_trs_system/models/ae_register.dart';
import 'package:atmos_trs_system/utils/ae_register_report_query.dart';

/// Fills the official DAE 1B.2 workbooks in place (styles and SUM formulas kept).
///
/// `forms_format/3.-DAE1B.2.xlsx` — daily + monthly.
/// `forms_format/DAE1B.2.Domestic.xlsx` — daily + one column per establishment + monthly.
///
/// Region header cells that receive a number lose their SUM formula so Excel
/// does not zero them. City and province rows stay blank: the register stores
/// PH region only. Negros Island guests are written on the Negros Occidental
/// row, which the form still rolls into Region VI.
class Dae1b2TemplateFill {
  const Dae1b2TemplateFill._();

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

  /// Daily-sheet row of each register region. Monthly sheet is one row higher.
  static const _regionRow = <String, int>{
    'ncr': 11,
    'car': 29,
    'regioniilocos': 37,
    'regioniicagayanvalley': 43,
    'regioniiicentralluzon': 50,
    'regionivacalabarzon': 60,
    'mimaropa': 68,
    'regionvbicol': 75,
    'regionviwesternvisayas': 85,
    'regionviicentralvisayas': 94,
    'regionviiieasternvisayas': 102,
    'regionixzamboangapeninsula': 111,
    'regionxnorthernmindanao': 117,
    'regionxidavao': 125,
    'regionxiisoccsksargen': 132,
    'regionxiiicaraga': 139,
    'barmm': 146,
  };

  static const _nirKey = 'nirnegrosisland';
  static const _nirLeafDaily = 91;

  static Dae1b2FillResult fill({
    required List<int> templateBytes,
    required AeRegisterReportData register,
    required String scopeLabel,
    required bool withAeSheet,
  }) {
    final gaps = <String>[
      'Official DAE 1B.2 workbook filled from hotel DOT registers.',
      'City and province rows are blank — the register records PH region only, written on the region row.',
      'Open the file in Excel so SUB-TOTAL and TOTAL formulas recalculate.',
    ];
    if (register.reports.isEmpty) {
      gaps.add('No hotel DOT register months in range — sheets left blank.');
      return Dae1b2FillResult(
        bytes: templateBytes,
        gaps: gaps,
        summary: 'DAE 1B.2 workbook unchanged (no register months)',
        arrivals: 0,
      );
    }

    final year = _focusYear(register);
    final month = _focusMonth(register, year);
    final yearReports = register.reports.where((r) => r.year == year).toList();
    final otherYears = register.reports.map((r) => r.year).toSet()..remove(year);
    if (otherYears.isNotEmpty) {
      gaps.add(
        'Monthly sheet is calendar year $year. Other years in range (${otherYears.join(', ')}) are not on this form.',
      );
    }

    final monthTotals = <int, _Slice>{};
    for (final r in yearReports) {
      final slice = _sliceOf(r, register.rowsFor(r));
      monthTotals[r.month] = (monthTotals[r.month] ?? const _Slice.empty()) + slice;
    }
    final focus = monthTotals[month] ?? const _Slice.empty();
    final unnamed = focus.unspecifiedArrivals;
    if (unnamed > 0) {
      gaps.add(
        '$unnamed domestic arrival(s) have no PH region — omitted from the origin grid (guest-night total still includes them).',
      );
    }
    if (focus.regions[_nirKey] != null) {
      gaps.add(
        'Negros Island Region is not a row on DAE 1B.2 — those arrivals are placed on Negros Occidental.',
      );
    }
    final missingRows = yearReports.where((r) => register.rowsFor(r).isEmpty && r.month == month);
    if (missingRows.isNotEmpty && focus.byDay.isEmpty) {
      gaps.add(
        'Daily sheet has no day split for ${_months[month - 1]} $year — register rows were not loaded. Monthly sheet still has the month totals.',
      );
    }

    final aes = _aesForMonth(register, year, month);
    if (withAeSheet && aes.length > 31) {
      gaps.add('AE sheet has 31 columns — ${aes.length - 31} establishment(s) omitted.');
    }

    final city = _unique(yearReports.map((r) => r.municipality));
    final province = _unique(yearReports.map((r) => r.province));
    final aeName = aes.length == 1
        ? aes.first.name
        : (aes.isEmpty ? scopeLabel : 'All establishments (${aes.length})');

    final files = <String, String>{};
    final archive = ZipDecoder().decodeBytes(templateBytes);
    for (final file in archive) {
      if (!file.isFile) continue;
      final name = file.name.replaceAll('\\', '/');
      if (name.endsWith('.xml')) {
        files[name] = utf8.decode(file.content as List<int>);
      }
    }

    void patch(String name, String Function(String) edit) {
      final xml = files[name];
      if (xml != null) files[name] = edit(xml);
    }

    patch('xl/worksheets/sheet1.xml', (xml) {
      xml = _header(
        xml,
        monthCell: 'S4',
        month: _months[month - 1],
        yearCell: 'AA4',
        year: year,
        nameCell: withAeSheet ? 'C6' : 'B6',
        name: aeName,
        cityCell: 'C7',
        city: city,
        provinceCell: 'C8',
        province: province,
      );
      xml = _writeRegions(
        xml,
        rowOf: (key) => _regionRow[key],
        nirLeaf: _nirLeafDaily,
        columns: {
          for (final e in focus.byDay.entries) _col(2 + e.key): e.value,
        },
      );
      xml = _indicators(
        xml,
        columns: {'C': focus},
        nightsRow: 160,
        alosRow: 163,
        maleRow: 165,
        femaleRow: 166,
      );
      return xml;
    });

    final monthlyName = withAeSheet ? 'xl/worksheets/sheet3.xml' : 'xl/worksheets/sheet2.xml';
    patch(monthlyName, (xml) {
      xml = _header(
        xml,
        monthCell: '',
        month: '',
        yearCell: 'H3',
        year: year,
        nameCell: 'B5',
        name: aeName,
        cityCell: 'C6',
        city: city,
        provinceCell: 'C7',
        province: province,
      );
      xml = _writeRegions(
        xml,
        rowOf: (key) => _regionRow[key] == null ? null : _regionRow[key]! - 1,
        nirLeaf: _nirLeafDaily - 1,
        columns: {
          for (final e in monthTotals.entries)
            if (e.key >= 1 && e.key <= 12) _col(2 + e.key): e.value.regions,
        },
      );
      xml = _indicators(
        xml,
        columns: {
          for (final e in monthTotals.entries)
            if (e.key >= 1 && e.key <= 12) _col(2 + e.key): e.value,
        },
        nightsRow: 159,
        alosRow: 162,
        maleRow: 164,
        femaleRow: 165,
      );
      return xml;
    });

    if (withAeSheet) {
      final shown = aes.take(31).toList();
      patch('xl/worksheets/sheet2.xml', (xml) {
        xml = _header(
          xml,
          monthCell: 'S4',
          month: _months[month - 1],
          yearCell: 'AA4',
          year: year,
          nameCell: 'B6',
          name: aeName,
          cityCell: 'C7',
          city: city,
          provinceCell: 'C8',
          province: province,
        );
        for (var i = 0; i < shown.length; i++) {
          xml = _setText(xml, '${_col(3 + i)}10', shown[i].name);
        }
        xml = _writeRegions(
          xml,
          rowOf: (key) => _regionRow[key],
          nirLeaf: _nirLeafDaily,
          columns: {
            for (var i = 0; i < shown.length; i++) _col(3 + i): shown[i].regions,
          },
        );
        xml = _indicators(
          xml,
          columns: {
            for (var i = 0; i < shown.length; i++) _col(3 + i): shown[i].slice,
          },
          nightsRow: 160,
          alosRow: 163,
          maleRow: 165,
          femaleRow: 166,
        );
        return xml;
      });
    }

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
      xml = xml.replaceAll(
        RegExp(r'<Relationship[^>]*calcChain[^>]*/>'),
        '',
      );
      if (!xml.contains('rId90')) {
        xml = xml.replaceFirst(
          '</Relationships>',
          '<Relationship Id="rId90" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet90.xml"/></Relationships>',
        );
      }
      return xml;
    });
    patch('[Content_Types].xml', (xml) {
      xml = xml.replaceAll(
        RegExp(r'<Override[^>]*calcChain[^>]*/>'),
        '',
      );
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
    final arrivals = monthTotals.values.fold<int>(0, (s, v) => s + v.domesticArrivals);
    return Dae1b2FillResult(
      bytes: encoded ?? templateBytes,
      gaps: gaps,
      summary:
          'DAE 1B.2 filled for $year · ${_months[month - 1]} daily'
          '${withAeSheet ? ' and ${aes.length.clamp(0, 31)} AE column(s)' : ''} · '
          '$arrivals domestic arrivals on the monthly sheet · $scopeLabel',
      arrivals: arrivals,
    );
  }

  static int _focusYear(AeRegisterReportData register) {
    final counts = <int, int>{};
    for (final r in register.reports) {
      counts[r.year] = (counts[r.year] ?? 0) + r.totals.domesticArrivals;
    }
    return counts.entries.reduce((a, b) => a.value >= b.value ? a : b).key;
  }

  static int _focusMonth(AeRegisterReportData register, int year) {
    final counts = <int, int>{};
    for (final r in register.reports.where((r) => r.year == year)) {
      counts[r.month] = (counts[r.month] ?? 0) + r.totals.domesticArrivals;
    }
    if (counts.isEmpty) return register.reports.first.month;
    return counts.entries.reduce((a, b) => a.value >= b.value ? a : b).key;
  }

  static List<_AeCol> _aesForMonth(AeRegisterReportData register, int year, int month) {
    final byId = <String, _AeCol>{};
    for (final r in register.reports.where((r) => r.year == year && r.month == month)) {
      final slice = _sliceOf(r, register.rowsFor(r));
      final prev = byId[r.aeId];
      byId[r.aeId] = _AeCol(
        r.aeName.trim().isEmpty ? r.aeId : r.aeName.trim(),
        (prev?.slice ?? const _Slice.empty()) + slice,
      );
    }
    final list = byId.values.toList()..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return list;
  }

  static _Slice _sliceOf(AeMonthlyReport report, List<AeRegisterRow> rows) {
    final regions = <String, int>{};
    final byDay = <int, Map<String, int>>{};
    var nights = report.totals.domesticNights;
    var arrivals = report.totals.domesticArrivals;
    var female = 0;
    var male = 0;

    void addRegion(String raw, int n) {
      if (n == 0) return;
      final key = _norm(raw);
      if (key == _nirKey || _regionRow.containsKey(key)) {
        regions[key] = (regions[key] ?? 0) + n;
      }
    }

    for (final e in report.totals.byRegion.entries) {
      addRegion(e.key, e.value.arrivals);
      female += e.value.female;
      male += e.value.male;
    }

    for (final row in rows) {
      if (DaeResidenceCatalog.bucketFor(row.residence) != DaeResidenceBucket.philippineResident) {
        continue;
      }
      final n = row.checkedInDay ? row.guests : 0;
      if (n == 0) continue;
      final key = _norm(row.phRegion);
      if (key.isEmpty || (key != _nirKey && !_regionRow.containsKey(key))) continue;
      final day = row.day;
      if (day < 1 || day > 31) continue;
      final map = byDay.putIfAbsent(day, () => {});
      map[key] = (map[key] ?? 0) + n;
    }

    final placed = regions.values.fold<int>(0, (s, v) => s + v);
    final unspecified = arrivals > placed ? arrivals - placed : 0;

    return _Slice(
      regions: regions,
      byDay: byDay,
      domesticArrivals: arrivals,
      domesticNights: nights,
      female: female,
      male: male,
      unspecifiedArrivals: unspecified,
    );
  }

  static String _writeRegions(
    String xml, {
    required int? Function(String key) rowOf,
    required int nirLeaf,
    required Map<String, Map<String, int>> columns,
  }) {
    for (final col in columns.entries) {
      for (final region in col.value.entries) {
        if (region.value == 0) continue;
        if (region.key == _nirKey) {
          xml = _setNumber(xml, '${col.key}$nirLeaf', region.value);
          continue;
        }
        final row = rowOf(region.key);
        if (row == null) continue;
        xml = _setNumber(xml, '${col.key}$row', region.value);
      }
    }
    return xml;
  }

  static String _indicators(
    String xml, {
    required Map<String, _Slice> columns,
    required int nightsRow,
    required int alosRow,
    required int maleRow,
    required int femaleRow,
  }) {
    for (final e in columns.entries) {
      final s = e.value;
      if (s.domesticNights > 0) xml = _setNumber(xml, '${e.key}$nightsRow', s.domesticNights);
      if (s.domesticArrivals > 0 && s.domesticNights > 0) {
        final alos = s.domesticNights / s.domesticArrivals;
        xml = _setNumber(xml, '${e.key}$alosRow', alos, places: 2);
      }
      if (s.male > 0) xml = _setNumber(xml, '${e.key}$maleRow', s.male);
      if (s.female > 0) xml = _setNumber(xml, '${e.key}$femaleRow', s.female);
    }
    return xml;
  }

  static String _header(
    String xml, {
    required String monthCell,
    required String month,
    required String yearCell,
    required int year,
    required String nameCell,
    required String name,
    required String cityCell,
    required String city,
    required String provinceCell,
    required String province,
  }) {
    if (monthCell.isNotEmpty && month.isNotEmpty) xml = _setText(xml, monthCell, month);
    xml = _setText(xml, yearCell, '$year');
    if (name.isNotEmpty) xml = _setText(xml, nameCell, name);
    if (city.isNotEmpty) xml = _setText(xml, cityCell, city);
    if (province.isNotEmpty) xml = _setText(xml, provinceCell, province);
    return xml;
  }

  static String _setNumber(String xml, String ref, num value, {int places = 0}) {
    final text = places == 0 ? value.round().toString() : value.toStringAsFixed(places);
    return _replaceCell(xml, ref, (style) => '<c r="$ref"$style><v>$text</v></c>');
  }

  static String _setText(String xml, String ref, String text) {
    final safe = text
        .replaceAll('&', '&amp;')
        .replaceAll('<', '&lt;')
        .replaceAll('>', '&gt;');
    return _replaceCell(
      xml,
      ref,
      (style) =>
          '<c r="$ref"$style t="inlineStr"><is><t xml:space="preserve">$safe</t></is></c>',
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

  static String _unique(Iterable<String> values) {
    final set = values.map((v) => v.trim()).where((v) => v.isNotEmpty).toSet();
    if (set.length == 1) return set.first;
    return '';
  }
}

class Dae1b2FillResult {
  const Dae1b2FillResult({
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

class _Slice {
  const _Slice({
    this.regions = const {},
    this.byDay = const {},
    this.domesticArrivals = 0,
    this.domesticNights = 0,
    this.female = 0,
    this.male = 0,
    this.unspecifiedArrivals = 0,
  });

  const _Slice.empty() : this();

  final Map<String, int> regions;
  final Map<int, Map<String, int>> byDay;
  final int domesticArrivals;
  final int domesticNights;
  final int female;
  final int male;
  final int unspecifiedArrivals;

  _Slice operator +(_Slice o) {
    final regions = Map<String, int>.from(this.regions);
    o.regions.forEach((k, v) => regions[k] = (regions[k] ?? 0) + v);
    final byDay = <int, Map<String, int>>{};
    for (final source in [this.byDay, o.byDay]) {
      source.forEach((day, map) {
        final dest = byDay.putIfAbsent(day, () => {});
        map.forEach((k, v) => dest[k] = (dest[k] ?? 0) + v);
      });
    }
    return _Slice(
      regions: regions,
      byDay: byDay,
      domesticArrivals: domesticArrivals + o.domesticArrivals,
      domesticNights: domesticNights + o.domesticNights,
      female: female + o.female,
      male: male + o.male,
      unspecifiedArrivals: unspecifiedArrivals + o.unspecifiedArrivals,
    );
  }
}

class _AeCol {
  const _AeCol(this.name, this.slice);
  final String name;
  final _Slice slice;
  Map<String, int> get regions => slice.regions;
}

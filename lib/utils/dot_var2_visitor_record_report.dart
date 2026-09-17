import 'package:excel/excel.dart';

import 'package:atmos_trs_system/utils/checkin_report_summary_csv.dart';

/// Sex bucket for DOT VAR 2 columns (Male / Female / Total).
class Var2SexCounts {
  const Var2SexCounts({this.male = 0, this.female = 0, this.total = 0});

  final int male;
  final int female;
  final int total;

  Var2SexCounts add({required String? sex, required bool countSexColumns}) {
    final normalized = _normalizeSex(sex);
    if (!countSexColumns) {
      return Var2SexCounts(
        male: male,
        female: female,
        total: total + 1,
      );
    }
    return Var2SexCounts(
      male: male + (normalized == Var2Sex.male ? 1 : 0),
      female: female + (normalized == Var2Sex.female ? 1 : 0),
      total: total + 1,
    );
  }

  Var2SexCounts operator +(Var2SexCounts other) => Var2SexCounts(
        male: male + other.male,
        female: female + other.female,
        total: total + other.total,
      );
}

enum Var2Sex { male, female, unknown }

enum Var2ResidenceBucket {
  thisMunicipality,
  thisProvince,
  otherProvince,
  foreign,
  profileMissing,
}

/// One attraction row in the VAR 2 table.
class Var2AttractionRow {
  const Var2AttractionRow({
    required this.spotId,
    required this.name,
    required this.attractionCode,
    required this.thisMunicipality,
    required this.thisProvince,
    required this.otherProvince,
    required this.foreign,
    required this.grandTotal,
  });

  final String spotId;
  final String name;
  final String attractionCode;
  final Var2SexCounts thisMunicipality;
  final Var2SexCounts thisProvince;
  final Var2SexCounts otherProvince;
  final Var2SexCounts foreign;
  final Var2SexCounts grandTotal;

  Var2AttractionRow operator +(Var2AttractionRow other) {
    return Var2AttractionRow(
      spotId: spotId,
      name: name,
      attractionCode: attractionCode,
      thisMunicipality: thisMunicipality + other.thisMunicipality,
      thisProvince: thisProvince + other.thisProvince,
      otherProvince: otherProvince + other.otherProvince,
      foreign: foreign + other.foreign,
      grandTotal: grandTotal + other.grandTotal,
    );
  }
}

class DotVar2VisitorRecordResult {
  const DotVar2VisitorRecordResult({
    required this.monthYearLabel,
    required this.municipalityName,
    required this.rows,
    required this.footerTotals,
    required this.csv,
    required this.xlsxBytes,
    required this.checkInsProcessed,
    required this.note,
  });

  final String monthYearLabel;
  final String municipalityName;
  final List<Var2AttractionRow> rows;
  final Var2AttractionRow footerTotals;
  final String csv;
  final List<int> xlsxBytes;
  final int checkInsProcessed;
  final String note;
}

class DotVar2SpotCatalogEntry {
  const DotVar2SpotCatalogEntry({
    required this.spotId,
    required this.name,
    this.dotAttractionCode = '',
  });

  final String spotId;
  final String name;
  final String dotAttractionCode;
}

Var2Sex _normalizeSex(String? sex) {
  final s = (sex ?? '').trim().toLowerCase();
  if (s.startsWith('m')) return Var2Sex.male;
  if (s.startsWith('f')) return Var2Sex.female;
  return Var2Sex.unknown;
}

String _normalizePlace(String? value) {
  return (value ?? '')
      .trim()
      .toLowerCase()
      .replaceAll(RegExp(r'\s+'), ' ')
      .replaceAll(' city', '')
      .replaceAll(' municipality', '');
}

bool isPhilippinesCountry(String? country) {
  final c = _normalizePlace(country);
  return c.isEmpty || c == 'philippines' || c == 'ph' || c == 'pilipinas';
}

bool isMisamisOccidentalProvince(String? province) {
  final p = _normalizePlace(province);
  return p.contains('misamis occidental') || p == 'misamis occidental';
}

bool cityMatchesMunicipality(String? city, String municipalityName) {
  final c = _normalizePlace(city);
  final m = _normalizePlace(municipalityName);
  if (c.isEmpty || m.isEmpty) return false;
  if (c == m) return true;
  if (c.contains(m) || m.contains(c)) return true;
  return false;
}

Var2ResidenceBucket classifyVar2Residence({
  required Map<String, dynamic>? profile,
  required String reportingMunicipalityName,
}) {
  if (profile == null || profile.isEmpty) {
    return Var2ResidenceBucket.profileMissing;
  }

  final isLocal =
      profile['isLocal'] == true || profile['localOrForeign'] == 'Local';
  final country = profile['country']?.toString();
  final isForeignFlag = profile['localOrForeign'] == 'Foreign';

  if (isForeignFlag || (!isLocal && !isPhilippinesCountry(country))) {
    return Var2ResidenceBucket.foreign;
  }
  if (!isPhilippinesCountry(country) && !isLocal) {
    return Var2ResidenceBucket.foreign;
  }

  final city = profile['city']?.toString();
  final province = profile['province']?.toString();

  if (cityMatchesMunicipality(city, reportingMunicipalityName)) {
    return Var2ResidenceBucket.thisMunicipality;
  }
  if (isMisamisOccidentalProvince(province)) {
    return Var2ResidenceBucket.thisProvince;
  }
  return Var2ResidenceBucket.otherProvince;
}

Var2SexCounts _applyVisit({
  required Var2SexCounts current,
  required String? sex,
  required bool countSexColumns,
}) {
  return current.add(sex: sex, countSexColumns: countSexColumns);
}

Var2AttractionRow _emptyRow({
  required String spotId,
  required String name,
  required String code,
}) {
  return Var2AttractionRow(
    spotId: spotId,
    name: name,
    attractionCode: code,
    thisMunicipality: const Var2SexCounts(),
    thisProvince: const Var2SexCounts(),
    otherProvince: const Var2SexCounts(),
    foreign: const Var2SexCounts(),
    grandTotal: const Var2SexCounts(),
  );
}

String _spotKeyFromCheckIn(Map<String, dynamic> c) {
  final spotId =
      c['spotId']?.toString().trim() ?? c['spot_id']?.toString().trim() ?? '';
  final spotName = c['spot_name']?.toString().trim() ?? '';
  if (spotId.isNotEmpty) return spotId;
  if (spotName.isNotEmpty) return spotName.toLowerCase();
  return 'unknown';
}

String formatVar2MonthYear(DateTime start, DateTime end) {
  if (start.year == end.year && start.month == end.month) {
    return _monthYearLabel(start);
  }
  return '${_monthYearLabel(start)} – ${_monthYearLabel(end)}';
}

String _monthYearLabel(DateTime d) {
  const months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];
  final yy = (d.year % 100).toString().padLeft(2, '0');
  return '${months[d.month - 1]}-$yy';
}

String var2CsvFilename({
  required String municipalitySlug,
  required DateTime startDate,
  required DateTime endDate,
}) {
  final slug = municipalitySlug.isEmpty ? 'lgu' : municipalitySlug;
  final start =
      '${startDate.year}-${startDate.month.toString().padLeft(2, '0')}';
  final end = '${endDate.year}-${endDate.month.toString().padLeft(2, '0')}';
  return 'dot_var2_visitor_record_${slug}_${start}_to_$end.csv';
}

String var2XlsxFilename({
  required String municipalitySlug,
  required DateTime startDate,
  required DateTime endDate,
}) {
  return var2CsvFilename(
    municipalitySlug: municipalitySlug,
    startDate: startDate,
    endDate: endDate,
  ).replaceAll('.csv', '.xlsx');
}

String _csvCell(String value) => '"${value.replaceAll('"', '""')}"';

List<String> _csvHeaderRow() => [
      'Name',
      'Attraction Code',
      'This Municipality Male',
      'This Municipality Female',
      'This Municipality Total',
      'This Province Male',
      'This Province Female',
      'This Province Total',
      'Other Province Male',
      'Other Province Female',
      'Other Province Total',
      'Foreign Male',
      'Foreign Female',
      'Foreign Total',
      'Grand Total Male',
      'Grand Total Female',
      'Grand Total Total',
    ];

List<String> _csvDataRow(Var2AttractionRow row) => [
      row.name,
      row.attractionCode,
      '${row.thisMunicipality.male}',
      '${row.thisMunicipality.female}',
      '${row.thisMunicipality.total}',
      '${row.thisProvince.male}',
      '${row.thisProvince.female}',
      '${row.thisProvince.total}',
      '${row.otherProvince.male}',
      '${row.otherProvince.female}',
      '${row.otherProvince.total}',
      '${row.foreign.male}',
      '${row.foreign.female}',
      '${row.foreign.total}',
      '${row.grandTotal.male}',
      '${row.grandTotal.female}',
      '${row.grandTotal.total}',
    ];

String buildVar2Csv({
  required String monthYearLabel,
  required String municipalityName,
  required List<Var2AttractionRow> rows,
  required Var2AttractionRow footer,
  required String note,
}) {
  final buf = StringBuffer();
  buf.writeln('Tourism Attraction Visitor Record (VAR 2)');
  buf.writeln('Month/Year,$monthYearLabel');
  buf.writeln('Name of Municipality,$municipalityName');
  buf.writeln('Note,$note');
  buf.writeln();
  buf.writeln(_csvHeaderRow().map(_csvCell).join(','));
  for (final row in rows) {
    buf.writeln(_csvDataRow(row).map(_csvCell).join(','));
  }
  final footerCells = _csvDataRow(footer);
  footerCells[0] = 'Total of this Month ****';
  footerCells[1] = '';
  buf.writeln(footerCells.map(_csvCell).join(','));
  return buf.toString();
}

DotVar2VisitorRecordResult buildDotVar2VisitorRecordReport({
  required List<Map<String, dynamic>> checkIns,
  required List<DotVar2SpotCatalogEntry> catalogSpots,
  required String municipalityName,
  required DateTime startDate,
  required DateTime endDate,
  Map<String, String>? attractionCodeBySpotId,
}) {
  final monthYearLabel = formatVar2MonthYear(startDate, endDate);
  final codeLookup = <String, String>{
    for (final s in catalogSpots)
      s.spotId: s.dotAttractionCode.trim().isNotEmpty
          ? s.dotAttractionCode.trim()
          : '',
  };
  if (attractionCodeBySpotId != null) {
    codeLookup.addAll(attractionCodeBySpotId);
  }

  final rowsBySpot = <String, Var2AttractionRow>{};
  final namesBySpot = <String, String>{};

  for (final entry in catalogSpots) {
    rowsBySpot[entry.spotId] = _emptyRow(
      spotId: entry.spotId,
      name: entry.name,
      code: codeLookup[entry.spotId] ?? '',
    );
    namesBySpot[entry.spotId] = entry.name;
  }

  var processed = 0;
  for (final c in checkIns) {
    if (isExcludedFromOfficialReports(c)) continue;
    processed++;
    final key = _spotKeyFromCheckIn(c);
    final spotName = c['spot_name']?.toString().trim() ?? key;
    namesBySpot[key] = spotName.isNotEmpty ? spotName : key;

    final profile = c['touristProfile'] is Map
        ? Map<String, dynamic>.from(c['touristProfile'] as Map)
        : null;
    final sex = profile?['sex']?.toString();
    final hasSex = _normalizeSex(sex) != Var2Sex.unknown;

    final residence = classifyVar2Residence(
      profile: profile,
      reportingMunicipalityName: municipalityName,
    );

    final existing = rowsBySpot[key] ??
        _emptyRow(
          spotId: key,
          name: namesBySpot[key] ?? key,
          code: codeLookup[key] ?? '',
        );

    Var2SexCounts thisMuni = existing.thisMunicipality;
    Var2SexCounts thisProv = existing.thisProvince;
    Var2SexCounts otherProv = existing.otherProvince;
    Var2SexCounts foreign = existing.foreign;
    Var2SexCounts grand = existing.grandTotal;

    if (residence == Var2ResidenceBucket.profileMissing) {
      grand = _applyVisit(
        current: grand,
        sex: sex,
        countSexColumns: false,
      );
    } else {
      final bucketUpdate = (Var2SexCounts current) => _applyVisit(
            current: current,
            sex: sex,
            countSexColumns: hasSex,
          );

      switch (residence) {
        case Var2ResidenceBucket.thisMunicipality:
          thisMuni = bucketUpdate(thisMuni);
        case Var2ResidenceBucket.thisProvince:
          thisProv = bucketUpdate(thisProv);
        case Var2ResidenceBucket.otherProvince:
          otherProv = bucketUpdate(otherProv);
        case Var2ResidenceBucket.foreign:
          foreign = bucketUpdate(foreign);
        case Var2ResidenceBucket.profileMissing:
          break;
      }

      if (hasSex) {
        grand = grand.add(sex: sex, countSexColumns: true);
      } else {
        grand = grand.add(sex: sex, countSexColumns: false);
      }
    }

    rowsBySpot[key] = Var2AttractionRow(
      spotId: key,
      name: namesBySpot[key] ?? key,
      attractionCode: codeLookup[key] ?? existing.attractionCode,
      thisMunicipality: thisMuni,
      thisProvince: thisProv,
      otherProvince: otherProv,
      foreign: foreign,
      grandTotal: grand,
    );
  }

  final rows = rowsBySpot.values.toList()
    ..sort((a, b) {
      final byTotal = b.grandTotal.total.compareTo(a.grandTotal.total);
      if (byTotal != 0) return byTotal;
      return a.name.compareTo(b.name);
    });

  Var2AttractionRow footer = _emptyRow(
    spotId: 'footer',
    name: 'Total of this Month ****',
    code: '',
  );
  for (final row in rows) {
    footer = footer + row;
  }

  const note =
      'Each QR check-in counts as one visitor. Sex and residence use tourist '
      'profile at signup; missing profile counts in Grand Total only. '
      'Total number must be recorded; sex and residence entries are optional.';

  final csv = buildVar2Csv(
    monthYearLabel: monthYearLabel,
    municipalityName: municipalityName,
    rows: rows,
    footer: footer,
    note: note,
  );

  final xlsxBytes = buildVar2XlsxBytes(
    monthYearLabel: monthYearLabel,
    municipalityName: municipalityName,
    rows: rows,
    footer: footer,
    note: note,
  );

  return DotVar2VisitorRecordResult(
    monthYearLabel: monthYearLabel,
    municipalityName: municipalityName,
    rows: rows,
    footerTotals: footer,
    csv: csv,
    xlsxBytes: xlsxBytes,
    checkInsProcessed: processed,
    note: note,
  );
}

List<int> buildVar2XlsxBytes({
  required String monthYearLabel,
  required String municipalityName,
  required List<Var2AttractionRow> rows,
  required Var2AttractionRow footer,
  required String note,
}) {
  final excel = Excel.createExcel();
  final defaultName = excel.getDefaultSheet()!;
  excel.rename(defaultName, 'VAR 2');
  final sheet = excel['VAR 2'];

  const yellow = 'FFFFEB9C';
  const greenLight = 'FFC6EFCE';
  const greenDark = 'FF92D050';

  void setCell(int row, int col, CellValue? value, {String? hex}) {
    final cell = sheet.cell(
      CellIndex.indexByColumnRow(columnIndex: col, rowIndex: row),
    );
    if (value != null) cell.value = value;
    if (hex != null) {
      cell.cellStyle = CellStyle(
        backgroundColorHex: ExcelColor.fromHexString(hex),
        bold: true,
        horizontalAlign: HorizontalAlign.Center,
        verticalAlign: VerticalAlign.Center,
      );
    }
  }

  setCell(0, 0, TextCellValue('Tourism Attraction Visitor Record'));
  setCell(0, 16, TextCellValue('VAR 2'), hex: yellow);
  setCell(
    1,
    0,
    TextCellValue(
      '( This recording form can be used instead of just counting the visitors )',
    ),
  );
  setCell(2, 0, TextCellValue('Month/Year:'));
  setCell(2, 2, TextCellValue(monthYearLabel));
  setCell(3, 0, TextCellValue('Name of Municipality:'));
  setCell(3, 2, TextCellValue(municipalityName));

  const headerRow = 5;
  setCell(headerRow, 0, TextCellValue('Visitor Attraction'), hex: yellow);
  setCell(headerRow, 1, TextCellValue('Attraction Code'), hex: yellow);
  setCell(headerRow, 2, TextCellValue('Place of Residence *** Philippines'), hex: yellow);
  setCell(headerRow, 11, TextCellValue('Foreign Country Residence'), hex: yellow);
  setCell(headerRow, 14, TextCellValue('Grand Total Number of Visitors *'), hex: yellow);

  const subHeaderRow = 6;
  final subLabels = [
    'Name',
    'Attraction Code',
    'This Municipality',
    '',
    '',
    'This Province',
    '',
    '',
    'Other Province',
    '',
    '',
    'Male',
    'Female',
    'Total',
    'Male',
    'Female',
    'Total',
  ];
  for (var i = 0; i < subLabels.length; i++) {
    if (subLabels[i].isEmpty) continue;
    setCell(subHeaderRow, i, TextCellValue(subLabels[i]), hex: yellow);
  }

  const colHeaderRow = 7;
  for (var c = 2; c <= 16; c++) {
    final label = switch (c % 3) {
      2 => 'Male',
      0 => 'Female',
      _ => 'Total',
    };
    if (c >= 2) setCell(colHeaderRow, c, TextCellValue(label), hex: yellow);
  }
  setCell(colHeaderRow, 0, TextCellValue('Name'), hex: yellow);
  setCell(colHeaderRow, 1, TextCellValue('Attraction Code'), hex: yellow);

  var dataRow = 8;
  for (final row in rows) {
    final values = _csvDataRow(row);
    for (var c = 0; c < values.length; c++) {
      final v = values[c];
      final cellValue = int.tryParse(v) != null
          ? IntCellValue(int.parse(v))
          : TextCellValue(v);
      setCell(dataRow, c, cellValue);
    }
    dataRow++;
  }

  final footerValues = _csvDataRow(footer);
  footerValues[0] = 'Total of this Month ****';
  for (var c = 0; c < footerValues.length; c++) {
    final v = footerValues[c];
    final cellValue = int.tryParse(v) != null
        ? IntCellValue(int.parse(v))
        : TextCellValue(v);
    setCell(
      dataRow,
      c,
      cellValue,
      hex: c <= 10 ? greenLight : greenDark,
    );
  }

  setCell(
    dataRow + 2,
    0,
    TextCellValue(
      'Note: *Total number must be recorded, ** Sex & ***Residence entries are '
      'optional. Total number of this month must be reported.',
    ),
  );
  setCell(dataRow + 3, 0, TextCellValue(note));

  final bytes = excel.encode();
  return bytes ?? <int>[];
}

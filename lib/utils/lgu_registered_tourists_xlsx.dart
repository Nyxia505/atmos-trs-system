import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:atmos_trs_system/utils/tourist_id_helper.dart';
import 'package:excel/excel.dart';

/// One registered-tourist row for the LGU Excel export.
class LguRegisteredTouristExportRow {
  const LguRegisteredTouristExportRow({
    required this.touristId,
    required this.type,
    required this.origin,
    required this.visits,
    required this.status,
    required this.registeredDate,
    required this.registeredTime,
    this.fullName,
    this.email,
    this.mobile,
    this.nationality,
  });

  final String touristId;
  final String type;
  final String origin;
  final int visits;
  final String status;
  final String registeredDate;
  final String registeredTime;
  final String? fullName;
  final String? email;
  final String? mobile;
  final String? nationality;

  Map<String, dynamic> toJson() => {
        'touristId': touristId,
        'type': type,
        'origin': origin,
        'visits': visits,
        'status': status,
        'registeredDate': registeredDate,
        'registeredTime': registeredTime,
        'fullName': fullName,
        'email': email,
        'mobile': mobile,
        'nationality': nationality,
      };

  factory LguRegisteredTouristExportRow.fromJson(Map<String, dynamic> json) {
    return LguRegisteredTouristExportRow(
      touristId: json['touristId']?.toString() ?? '',
      type: json['type']?.toString() ?? '',
      origin: json['origin']?.toString() ?? '',
      visits: json['visits'] is int
          ? json['visits'] as int
          : int.tryParse('${json['visits']}') ?? 0,
      status: json['status']?.toString() ?? '',
      registeredDate: json['registeredDate']?.toString() ?? '',
      registeredTime: json['registeredTime']?.toString() ?? '',
      fullName: json['fullName']?.toString(),
      email: json['email']?.toString(),
      mobile: json['mobile']?.toString(),
      nationality: json['nationality']?.toString(),
    );
  }
}

/// Maps a live `tourists` document (plus visit totals) into an export row.
LguRegisteredTouristExportRow lguRegisteredTouristExportRowFromMap(
  Map<String, dynamic> tourist,
) {
  final isLocal =
      tourist['isLocal'] == true || tourist['localOrForeign'] == 'Local';
  final rawVisits = tourist['totalVisits'] ?? tourist['visits'] ?? 0;
  final visits = rawVisits is int
      ? rawVisits
      : int.tryParse(rawVisits.toString()) ?? 0;
  final dt = registeredDateTimeFromTourist(tourist);
  return LguRegisteredTouristExportRow(
    touristId: TouristIdHelper.displayForTourist(tourist),
    type: isLocal ? 'Local' : 'Foreign',
    origin: originFromTourist(tourist),
    visits: visits,
    status: (tourist['status']?.toString().trim().isNotEmpty == true)
        ? tourist['status'].toString().trim()
        : 'Active',
    registeredDate: formatExportDate(dt),
    registeredTime: formatExportTime(dt),
    fullName: _displayName(tourist),
    email: tourist['email']?.toString().trim(),
    mobile: (tourist['mobile'] ?? tourist['phone'] ?? tourist['contactNumber'])
        ?.toString()
        .trim(),
    nationality: tourist['nationality']?.toString().trim(),
  );
}

DateTime? registeredDateTimeFromTourist(Map<String, dynamic> t) {
  return _coerceDateTime(t['registeredAt']) ??
      _coerceDateTime(t['registeredDate']) ??
      _coerceDateTime(t['createdAt'] ?? t['created_at']);
}

String originFromTourist(Map<String, dynamic> t) {
  if (t['city'] != null && t['city'].toString().trim().isNotEmpty) {
    final parts = <String>[
      t['city'].toString().trim(),
      if (t['province'] != null && t['province'].toString().trim().isNotEmpty)
        t['province'].toString().trim(),
      if (t['country'] != null && t['country'].toString().trim().isNotEmpty)
        t['country'].toString().trim(),
    ];
    return parts.join(', ');
  }
  final origin = t['origin']?.toString().trim();
  if (origin != null && origin.isNotEmpty) return origin;
  final country = t['country']?.toString().trim();
  if (country != null && country.isNotEmpty) return country;
  final nationality = t['nationality']?.toString().trim();
  if (nationality != null && nationality.isNotEmpty) return nationality;
  return '—';
}

String formatExportDate(DateTime? dt) {
  if (dt == null) return '—';
  return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';
}

String formatExportTime(DateTime? dt) {
  if (dt == null) return '—';
  final h24 = dt.hour;
  final min = dt.minute.toString().padLeft(2, '0');
  final sec = dt.second.toString().padLeft(2, '0');
  final period = h24 >= 12 ? 'PM' : 'AM';
  final h12 = h24 == 0 ? 12 : (h24 > 12 ? h24 - 12 : h24);
  return '$h12:$min:$sec $period';
}

String lguRegisteredTouristsXlsxFilename({
  required String lguLocation,
  DateTime? generatedAt,
}) {
  final when = generatedAt ?? DateTime.now();
  final day =
      '${when.year}-${when.month.toString().padLeft(2, '0')}-${when.day.toString().padLeft(2, '0')}';
  final slug = lguLocation
      .trim()
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
      .replaceAll(RegExp(r'^_+|_+$'), '');
  final place = slug.isEmpty ? 'lgu' : slug;
  return 'ATMOS_TRS_Registered_Tourists_${place}_$day.xlsx';
}

/// Privacy-safe LGU workbook. Restricted PII (name, email, mobile) is included
/// only when [includeRestrictedPersonalInfo] is true for an authorized role.
class LguRegisteredTouristsXlsx {
  const LguRegisteredTouristsXlsx({
    required this.lguLocation,
    required this.rows,
    required this.generatedAt,
    this.includeRestrictedPersonalInfo = false,
    this.officeLabel = 'LGU Office',
    this.privacyLabel,
  });

  final String lguLocation;
  final List<LguRegisteredTouristExportRow> rows;
  final DateTime generatedAt;
  final bool includeRestrictedPersonalInfo;
  final String officeLabel;
  final String? privacyLabel;

  static const dataSheetName = 'Registered Tourists';
  static const summarySheetName = 'Summary';
  static const _headerRow = 5; // Excel row 6
  static const _titleOrange = 'FFF97316';
  static const _headerNavy = 'FF0B1F3A';
  static const _bandBlue = 'FFD7EEF8';
  static const _cream = 'FFFFF4E8';
  static const _white = 'FFFFFFFF';
  static const _ink = 'FF111827';
  static const _muted = 'FF6B7280';
  static const _idBlue = 'FF1E3A5F';
  static const _localFill = 'FFDCFCE7';
  static const _localText = 'FF15803D';
  static const _foreignFill = 'FFF3E8FF';
  static const _foreignText = 'FF7C3AED';
  static const _activeFill = 'FFDCFCE7';
  static const _activeText = 'FF15803D';
  static const _border = 'FFD6DEE8';

  List<String> get headers {
    if (includeRestrictedPersonalInfo) {
      return const [
        'Tourist ID',
        'Full Name',
        'Email',
        'Mobile',
        'Nationality',
        'Type',
        'Origin',
        'Visits',
        'Status',
        'Registered Date',
        'Registered Time',
      ];
    }
    return const [
      'Tourist ID',
      'Type',
      'Origin',
      'Visits',
      'Status',
      'Registered Date',
      'Registered Time',
    ];
  }

  List<int> buildBytes() {
    final excel = Excel.createExcel();
    final defaultName = excel.getDefaultSheet() ?? 'Sheet1';
    if (defaultName != dataSheetName) {
      excel.rename(defaultName, dataSheetName);
    }
    excel[dataSheetName];
    excel[summarySheetName];
    for (final name in excel.sheets.keys.toList()) {
      if (name != dataSheetName && name != summarySheetName) {
        excel.delete(name);
      }
    }
    _writeDataSheet(excel[dataSheetName]);
    _writeSummarySheet(excel[summarySheetName]);
    excel.setDefaultSheet(dataSheetName);

    final encoded = excel.encode();
    if (encoded == null || encoded.isEmpty) return const <int>[];
    return _attachFreeze(
      Uint8List.fromList(encoded),
      sheetName: dataSheetName,
      freezeSplit: _headerRow + 1,
    );
  }

  void _writeDataSheet(Sheet sheet) {
    final lastCol = headers.length - 1;
    sheet.setDefaultRowHeight(20);
    _writeMergedBanner(
      sheet,
      startRow: 0,
      endRow: 1,
      lastCol: lastCol,
      text: 'ATMOS TRS | REGISTERED TOURISTS',
      size: 16,
      fill: _titleOrange,
      color: _white,
      bold: true,
    );
    final privacy = privacyLabel ??
        (includeRestrictedPersonalInfo
            ? 'Authorized export'
            : 'Privacy-safe LGU export');
    _writeMergedBanner(
      sheet,
      startRow: 2,
      endRow: 2,
      lastCol: lastCol,
      text:
          '$officeLabel • ${_locationLabel()}  |  $privacy  |  ${_longDate(generatedAt)}',
      size: 10,
      fill: _cream,
      color: _ink,
      bold: false,
    );
    _writeMergedBanner(
      sheet,
      startRow: 4,
      endRow: 4,
      lastCol: lastCol,
      text: 'Export authorized data only.',
      size: 9,
      fill: _white,
      color: _muted,
      bold: false,
      italic: true,
    );

    sheet.setRowHeight(0, 22);
    sheet.setRowHeight(1, 22);
    sheet.setRowHeight(2, 20);
    sheet.setRowHeight(3, 10);
    sheet.setRowHeight(4, 18);
    sheet.setRowHeight(_headerRow, 22);

    for (var c = 0; c < headers.length; c++) {
      _set(
        sheet,
        _headerRow,
        c,
        headers[c],
        style: _headerCellStyle(headers[c]),
      );
    }

    for (var i = 0; i < rows.length; i++) {
      final r = rows[i];
      final excelRow = _headerRow + 1 + i;
      sheet.setRowHeight(excelRow, 20);
      final band = i.isEven ? _bandBlue : _white;
      final values = _rowValues(r);
      for (var c = 0; c < values.length; c++) {
        final header = headers[c];
        final v = values[c];
        final style = _dataCellStyle(header, v, band);
        if (v is int) {
          _setInt(sheet, excelRow, c, v, style: style);
        } else {
          _set(sheet, excelRow, c, v.toString(), style: style);
        }
      }
    }

    for (var c = 0; c < headers.length; c++) {
      sheet.setColumnWidth(c, _widthFor(headers[c]));
    }
  }

  void _writeSummarySheet(Sheet sheet) {
    _writeMergedTitle(
      sheet,
      row: 0,
      lastCol: 1,
      text: 'ATMOS TRS',
      size: 18,
      orangeFill: true,
    );
    _writeMergedTitle(
      sheet,
      row: 1,
      lastCol: 1,
      text: 'Registered Tourists Summary',
      size: 14,
      orangeFill: true,
    );
    _set(
      sheet,
      2,
      0,
      '$officeLabel: ${_locationLabel()}',
      style: _textStyle(bold: true, color: _ink, size: 11),
    );
    _set(
      sheet,
      3,
      0,
      'Generated: ${formatExportDate(generatedAt)} ${formatExportTime(generatedAt)}',
      style: _textStyle(color: _muted, size: 10),
    );
    _set(
      sheet,
      4,
      0,
      'Values are Excel formulas over every row on "$dataSheetName".',
      style: _textStyle(color: _muted, size: 9, italic: true),
    );

    final metricHeader = _headerCellStyle('Status');
    _set(sheet, 6, 0, 'Metric', style: metricHeader);
    _set(sheet, 6, 1, 'Value', style: metricHeader);

    final lastDataExcelRow =
        _headerRow + 1 + (rows.isEmpty ? 1 : rows.length);
    final typeCol = _columnLetter(_typeColumnIndex);
    final visitsCol = _columnLetter(_visitsColumnIndex);
    final idRange =
        "'$dataSheetName'!A${_headerRow + 2}:A$lastDataExcelRow";
    final typeRange =
        "'$dataSheetName'!$typeCol${_headerRow + 2}:$typeCol$lastDataExcelRow";
    final visitsRange =
        "'$dataSheetName'!$visitsCol${_headerRow + 2}:$visitsCol$lastDataExcelRow";

    final metrics = <(String, String)>[
      ('Registered tourists', 'COUNTA($idRange)'),
      ('Local tourists', 'COUNTIF($typeRange,"Local")'),
      ('Foreign tourists', 'COUNTIF($typeRange,"Foreign")'),
      ('Total visits', 'SUM($visitsRange)'),
    ];
    final labelStyle = _textStyle(
      bold: true,
      color: _ink,
      fill: _bandBlue,
      border: true,
    );
    final valueStyle = _textStyle(
      bold: true,
      color: _ink,
      fill: _white,
      align: HorizontalAlign.Center,
      border: true,
    );
    for (var i = 0; i < metrics.length; i++) {
      final row = 7 + i;
      _set(sheet, row, 0, metrics[i].$1, style: labelStyle);
      _setFormula(sheet, row, 1, metrics[i].$2, style: valueStyle);
    }

    sheet.setColumnWidth(0, 28);
    sheet.setColumnWidth(1, 18);
  }

  List<Object> _rowValues(LguRegisteredTouristExportRow r) {
    if (includeRestrictedPersonalInfo) {
      return [
        r.touristId,
        r.fullName ?? '',
        r.email ?? '',
        r.mobile ?? '',
        r.nationality ?? '',
        r.type,
        r.origin,
        r.visits,
        r.status,
        r.registeredDate,
        r.registeredTime,
      ];
    }
    return [
      r.touristId,
      r.type,
      r.origin,
      r.visits,
      r.status,
      r.registeredDate,
      r.registeredTime,
    ];
  }

  int get _typeColumnIndex => includeRestrictedPersonalInfo ? 5 : 1;
  int get _visitsColumnIndex => includeRestrictedPersonalInfo ? 7 : 3;

  String _locationLabel() {
    final loc = lguLocation.trim();
    return loc.isEmpty ? 'Misamis Occidental' : loc;
  }

  double _widthFor(String header) {
    switch (header) {
      case 'Tourist ID':
        return 18;
      case 'Full Name':
        return 24;
      case 'Email':
        return 28;
      case 'Mobile':
        return 16;
      case 'Nationality':
        return 16;
      case 'Type':
        return 14;
      case 'Origin':
        return 44;
      case 'Visits':
        return 12;
      case 'Status':
        return 14;
      case 'Registered Date':
        return 20;
      case 'Registered Time':
        return 20;
      default:
        return 16;
    }
  }

  bool _isCenteredColumn(String header) {
    return header == 'Type' ||
        header == 'Registered Date' ||
        header == 'Registered Time' ||
        header == 'Visits' ||
        header == 'Status';
  }

  CellStyle _headerCellStyle(String header) {
    return _textStyle(
      bold: true,
      color: _white,
      fill: _headerNavy,
      size: 11,
      align: _isCenteredColumn(header)
          ? HorizontalAlign.Center
          : HorizontalAlign.Left,
      border: true,
    );
  }

  CellStyle _dataCellStyle(String header, Object value, String band) {
    var fill = band;
    var color = header == 'Tourist ID' ? _idBlue : _ink;
    var bold = header == 'Tourist ID';
    if (header == 'Type') {
      final type = value.toString();
      if (type == 'Local') {
        fill = _localFill;
        color = _localText;
        bold = true;
      } else if (type == 'Foreign') {
        fill = _foreignFill;
        color = _foreignText;
        bold = true;
      }
    } else if (header == 'Status' && value.toString() == 'Active') {
      fill = _activeFill;
      color = _activeText;
      bold = true;
    }
    return _textStyle(
      bold: bold,
      color: color,
      fill: fill,
      size: 10,
      align: _isCenteredColumn(header)
          ? HorizontalAlign.Center
          : HorizontalAlign.Left,
      wrap: header == 'Origin',
      border: true,
    );
  }

  void _writeMergedBanner(
    Sheet sheet, {
    required int startRow,
    required int endRow,
    required int lastCol,
    required String text,
    required int size,
    required String fill,
    required String color,
    required bool bold,
    bool italic = false,
  }) {
    final style = _textStyle(
      bold: bold,
      italic: italic,
      color: color,
      fill: fill,
      size: size,
      align: HorizontalAlign.Left,
    );
    for (var r = startRow; r <= endRow; r++) {
      for (var c = 0; c <= lastCol; c++) {
        _set(
          sheet,
          r,
          c,
          r == startRow && c == 0 ? text : '',
          style: style,
        );
      }
    }
    if (lastCol > 0 || endRow > startRow) {
      sheet.merge(
        CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: startRow),
        CellIndex.indexByColumnRow(columnIndex: lastCol, rowIndex: endRow),
      );
    }
  }

  void _writeMergedTitle(
    Sheet sheet, {
    required int row,
    required int lastCol,
    required String text,
    required int size,
    required bool orangeFill,
  }) {
    _writeMergedBanner(
      sheet,
      startRow: row,
      endRow: row,
      lastCol: lastCol,
      text: text,
      size: size,
      fill: orangeFill ? _titleOrange : _white,
      color: orangeFill ? _white : _ink,
      bold: true,
    );
  }

  void _set(
    Sheet sheet,
    int row,
    int col,
    String value, {
    CellStyle? style,
  }) {
    final cell = sheet.cell(
      CellIndex.indexByColumnRow(columnIndex: col, rowIndex: row),
    );
    cell.value = TextCellValue(value);
    if (style != null) cell.cellStyle = style;
  }

  void _setInt(
    Sheet sheet,
    int row,
    int col,
    int value, {
    CellStyle? style,
  }) {
    final cell = sheet.cell(
      CellIndex.indexByColumnRow(columnIndex: col, rowIndex: row),
    );
    cell.value = IntCellValue(value);
    if (style != null) cell.cellStyle = style;
  }

  void _setFormula(
    Sheet sheet,
    int row,
    int col,
    String formula, {
    CellStyle? style,
  }) {
    final cell = sheet.cell(
      CellIndex.indexByColumnRow(columnIndex: col, rowIndex: row),
    );
    cell.value = FormulaCellValue(formula);
    if (style != null) cell.cellStyle = style;
  }

  CellStyle _textStyle({
    bool bold = false,
    bool italic = false,
    String color = _ink,
    String fill = _white,
    int size = 10,
    HorizontalAlign align = HorizontalAlign.Left,
    bool wrap = false,
    bool border = false,
  }) {
    final edge = Border(
      borderStyle: BorderStyle.Thin,
      borderColorHex: ExcelColor.fromHexString(_border),
    );
    return CellStyle(
      bold: bold,
      italic: italic,
      fontSize: size,
      fontColorHex: ExcelColor.fromHexString(color),
      backgroundColorHex: ExcelColor.fromHexString(fill),
      horizontalAlign: align,
      verticalAlign: VerticalAlign.Center,
      textWrapping: wrap ? TextWrapping.WrapText : TextWrapping.Clip,
      leftBorder: border ? edge : null,
      rightBorder: border ? edge : null,
      topBorder: border ? edge : null,
      bottomBorder: border ? edge : null,
    );
  }

  String _longDate(DateTime dt) {
    const months = [
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
    return '${dt.day} ${months[dt.month - 1]} ${dt.year}';
  }
}

String _displayName(Map<String, dynamic> t) {
  final full = t['fullName']?.toString().trim();
  if (full != null && full.isNotEmpty) return full;
  final name = t['name']?.toString().trim();
  if (name != null && name.isNotEmpty) return name;
  final first = t['firstName']?.toString().trim() ?? '';
  final last = t['lastName']?.toString().trim() ?? '';
  final combined = '$first $last'.trim();
  if (combined.isNotEmpty) return combined;
  return '';
}

DateTime? _coerceDateTime(Object? raw) {
  if (raw == null) return null;
  if (raw is DateTime) return raw;
  try {
    final converted = (raw as dynamic).toDate();
    if (converted is DateTime) return converted;
  } catch (_) {}
  if (raw is String) return DateTime.tryParse(raw);
  return null;
}

String _columnLetter(int index) {
  var n = index + 1;
  final buf = StringBuffer();
  while (n > 0) {
    final rem = (n - 1) % 26;
    buf.writeCharCode(65 + rem);
    n = (n - 1) ~/ 26;
  }
  return buf.toString().split('').reversed.join();
}

List<int> _attachFreeze(
  Uint8List bytes, {
  required String sheetName,
  required int freezeSplit,
}) {
  try {
    final archive = ZipDecoder().decodeBytes(bytes);
    final files = <String, List<int>>{};
    for (final f in archive) {
      if (!f.isFile) continue;
      files[f.name.replaceAll('\\', '/')] = f.content as List<int>;
    }

    final workbookXml = utf8.decode(files['xl/workbook.xml'] ?? const []);
    final relsXml = utf8.decode(files['xl/_rels/workbook.xml.rels'] ?? const []);
    final rid = _sheetRidFor(workbookXml, sheetName);
    if (rid == null) return bytes;
    final target = _relTarget(relsXml, rid);
    if (target == null) return bytes;
    final sheetPath = target.startsWith('/')
        ? target.substring(1)
        : (target.startsWith('xl/') ? target : 'xl/$target');
    final sheetXml = utf8.decode(files[sheetPath] ?? const []);
    if (sheetXml.isEmpty) return bytes;

    files[sheetPath] = utf8.encode(_injectFreeze(sheetXml, freezeSplit));

    final out = Archive();
    for (final entry in files.entries) {
      out.addFile(ArchiveFile(entry.key, entry.value.length, entry.value));
    }
    final encoded = ZipEncoder().encode(out);
    return encoded ?? bytes;
  } catch (_) {
    return bytes;
  }
}

String? _sheetRidFor(String workbookXml, String sheetName) {
  final re = RegExp(
    'name="${RegExp.escape(sheetName)}"[^>]*r:id="(rId\\d+)"'
    '|r:id="(rId\\d+)"[^>]*name="${RegExp.escape(sheetName)}"',
  );
  final m = re.firstMatch(workbookXml);
  return m?.group(1) ?? m?.group(2);
}

String? _relTarget(String relsXml, String rid) {
  final re = RegExp('Id="$rid"[^>]*Target="([^"]+)"');
  final m = re.firstMatch(relsXml);
  if (m != null) return m.group(1);
  final re2 = RegExp('Target="([^"]+)"[^>]*Id="$rid"');
  return re2.firstMatch(relsXml)?.group(1);
}

String _injectFreeze(String sheetXml, int freezeSplit) {
  if (sheetXml.contains('state="frozen"')) return sheetXml;
  final pane =
      '<pane ySplit="$freezeSplit" topLeftCell="A${freezeSplit + 1}" activePane="bottomLeft" state="frozen"/>';

  final selfClosing = RegExp(r'<sheetView([^>]*)/>');
  if (selfClosing.hasMatch(sheetXml)) {
    return sheetXml.replaceFirstMapped(
      selfClosing,
      (m) => '<sheetView${m.group(1)}>$pane</sheetView>',
    );
  }
  if (sheetXml.contains('</sheetView>')) {
    return sheetXml.replaceFirst('</sheetView>', '$pane</sheetView>');
  }
  if (sheetXml.contains('<sheetViews>')) {
    return sheetXml.replaceFirst(
      '<sheetViews>',
      '<sheetViews><sheetView workbookViewId="0">$pane</sheetView>',
    );
  }
  return sheetXml.replaceFirst(
    '<sheetData',
    '<sheetViews><sheetView workbookViewId="0">$pane</sheetView></sheetViews><sheetData',
  );
}

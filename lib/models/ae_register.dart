import 'package:cloud_firestore/cloud_firestore.dart';

import 'package:atmos_trs_system/models/sign_off.dart';

/// Who last saved a register row (from the sign-off on that save).
class AeRowAudit {
  const AeRowAudit({
    this.signOffId = '',
    this.encodedBy = '',
    this.encodedPosition = '',
    this.createdBy = '',
    this.createdAt,
    this.updatedAt,
  });

  final String signOffId;
  final String encodedBy;
  final String encodedPosition;
  final String createdBy;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  bool get isEmpty => signOffId.isEmpty && encodedBy.isEmpty;

  factory AeRowAudit.fromMap(Map<String, dynamic> m) {
    DateTime? ts(dynamic v) => v is Timestamp ? v.toDate() : null;
    return AeRowAudit(
      signOffId: (m['signOffId'] ?? '').toString(),
      encodedBy: (m['encodedBy'] ?? '').toString(),
      encodedPosition: (m['encodedPosition'] ?? '').toString(),
      createdBy: (m['createdBy'] ?? '').toString(),
      createdAt: ts(m['createdAt']),
      updatedAt: ts(m['updatedAt']),
    );
  }
}

/// One DailyRecord line of the DOT ET DAE-1B workbook.
///
/// Lodging: one row = one occupied room for one night. Non-lodging packs
/// leave [roomNo] empty and every row counts as an arrival.
class AeRegisterRow {
  const AeRegisterRow({
    required this.id,
    required this.date,
    required this.residence,
    required this.guests,
    this.roomNo = '',
    this.phRegion = '',
    this.female = 0,
    this.male = 0,
    this.checkedInDay = false,
    this.rate = 0,
    this.chargesA = 0,
    this.chargesB = 0,
    this.isDemo = false,
    this.audit = const AeRowAudit(),
  });

  final String id;

  /// Not part of the DOT row; never included in [toMap] or content hashes.
  final AeRowAudit audit;

  /// Local calendar date (time stripped).
  final DateTime date;
  final String roomNo;
  final String residence;
  final String phRegion;
  final int guests;
  final int female;
  final int male;
  final bool checkedInDay;
  final double rate;
  final double chargesA;
  final double chargesB;
  final bool isDemo;

  int get day => date.day;
  double get subtotal => rate + chargesA + chargesB;

  AeRegisterRow copyWith({
    String? id,
    DateTime? date,
    String? roomNo,
    String? residence,
    String? phRegion,
    int? guests,
    int? female,
    int? male,
    bool? checkedInDay,
    double? rate,
    double? chargesA,
    double? chargesB,
  }) =>
      AeRegisterRow(
        id: id ?? this.id,
        date: date ?? this.date,
        roomNo: roomNo ?? this.roomNo,
        residence: residence ?? this.residence,
        phRegion: phRegion ?? this.phRegion,
        guests: guests ?? this.guests,
        female: female ?? this.female,
        male: male ?? this.male,
        checkedInDay: checkedInDay ?? this.checkedInDay,
        rate: rate ?? this.rate,
        chargesA: chargesA ?? this.chargesA,
        chargesB: chargesB ?? this.chargesB,
        isDemo: isDemo,
        audit: audit,
      );

  Map<String, dynamic> toMap() => {
        'date': dateKey(date),
        'day': date.day,
        'roomNo': roomNo,
        'residence': residence,
        if (phRegion.isNotEmpty) 'phRegion': phRegion,
        'guests': guests,
        'female': female,
        'male': male,
        'checkedInDay': checkedInDay,
        'rate': rate,
        'chargesA': chargesA,
        'chargesB': chargesB,
        if (isDemo) 'seed': 'demo',
      };

  factory AeRegisterRow.fromMap(String id, Map<String, dynamic> m) {
    return AeRegisterRow(
      id: id,
      date: parseDateKey(m['date']) ?? DateTime(1970),
      roomNo: (m['roomNo'] ?? '').toString(),
      residence: (m['residence'] ?? '').toString(),
      phRegion: (m['phRegion'] ?? '').toString(),
      guests: _int(m['guests']),
      female: _int(m['female']),
      male: _int(m['male']),
      checkedInDay: m['checkedInDay'] == true,
      rate: _double(m['rate']),
      chargesA: _double(m['chargesA']),
      chargesB: _double(m['chargesB']),
      isDemo: (m['seed'] ?? '').toString() == 'demo',
      audit: AeRowAudit.fromMap(m),
    );
  }

  factory AeRegisterRow.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) =>
      AeRegisterRow.fromMap(doc.id, doc.data() ?? const {});

  static String dateKey(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';

  static DateTime? parseDateKey(dynamic v) {
    if (v is Timestamp) {
      final d = v.toDate();
      return DateTime(d.year, d.month, d.day);
    }
    if (v is DateTime) return DateTime(v.year, v.month, v.day);
    final s = (v ?? '').toString().trim();
    if (s.isEmpty) return null;
    final p = DateTime.tryParse(s);
    if (p == null) return null;
    return DateTime(p.year, p.month, p.day);
  }
}

enum AeReportStatus { draft, submitted }

/// Saved per-country totals (DAE-1B Sum sheet).
class AeCountryTotals {
  const AeCountryTotals({
    this.arrivals = 0,
    this.nights = 0,
    this.female = 0,
    this.male = 0,
  });

  final int arrivals;
  final int nights;
  final int female;
  final int male;

  AeCountryTotals operator +(AeCountryTotals o) => AeCountryTotals(
        arrivals: arrivals + o.arrivals,
        nights: nights + o.nights,
        female: female + o.female,
        male: male + o.male,
      );

  Map<String, dynamic> toMap() => {
        'arrivals': arrivals,
        'nights': nights,
        'female': female,
        'male': male,
      };

  factory AeCountryTotals.fromMap(dynamic m) {
    if (m is! Map) return const AeCountryTotals();
    return AeCountryTotals(
      arrivals: _int(m['arrivals']),
      nights: _int(m['nights']),
      female: _int(m['female']),
      male: _int(m['male']),
    );
  }
}

/// Monthly totals (MonthlyRecord + DAE2_Auto sheets) saved on the header doc.
class AeMonthTotals {
  const AeMonthTotals({
    this.checkIns = 0,
    this.checkOuts = 0,
    this.guestNights = 0,
    this.roomsOccupied = 0,
    this.occupancyRate,
    this.alos,
    this.avgPersonsPerRoom,
    this.domesticArrivals = 0,
    this.domesticNights = 0,
    this.foreignArrivals = 0,
    this.foreignNights = 0,
    this.overseasFilipinoArrivals = 0,
    this.overseasFilipinoNights = 0,
    this.unknownArrivals = 0,
    this.unknownNights = 0,
    this.femaleArrivals = 0,
    this.maleArrivals = 0,
    this.filipinoNationalArrivals = 0,
    this.totalSales = 0,
    this.chargesA = 0,
    this.chargesB = 0,
    this.rowCount = 0,
    this.filledDays = 0,
    this.byCountry = const {},
    this.byRegion = const {},
  });

  final int checkIns;
  final int checkOuts;
  final int guestNights;
  final int roomsOccupied;

  /// 0..1 (rooms occupied ÷ rooms × days). Null when rooms unknown.
  final double? occupancyRate;
  final double? alos;
  final double? avgPersonsPerRoom;
  final int domesticArrivals;
  final int domesticNights;
  final int foreignArrivals;
  final int foreignNights;
  final int overseasFilipinoArrivals;
  final int overseasFilipinoNights;
  final int unknownArrivals;
  final int unknownNights;
  final int femaleArrivals;
  final int maleArrivals;
  final int filipinoNationalArrivals;
  final double totalSales;
  final double chargesA;
  final double chargesB;
  final int rowCount;

  /// Days with at least one row or explicitly marked "no guests".
  final int filledDays;

  /// Register residence label → totals (foreign + PH + OFW + unspecified).
  final Map<String, AeCountryTotals> byCountry;

  /// Domestic origin region → totals (Philippine residents with a region).
  final Map<String, AeCountryTotals> byRegion;

  double get grandTotalSales => totalSales + chargesA + chargesB;

  Map<String, dynamic> toMap() => {
        'checkIns': checkIns,
        'checkOuts': checkOuts,
        'guestNights': guestNights,
        'roomsOccupied': roomsOccupied,
        'occupancyRate': occupancyRate,
        'alos': alos,
        'avgPersonsPerRoom': avgPersonsPerRoom,
        'domesticArrivals': domesticArrivals,
        'domesticNights': domesticNights,
        'foreignArrivals': foreignArrivals,
        'foreignNights': foreignNights,
        'overseasFilipinoArrivals': overseasFilipinoArrivals,
        'overseasFilipinoNights': overseasFilipinoNights,
        'unknownArrivals': unknownArrivals,
        'unknownNights': unknownNights,
        'femaleArrivals': femaleArrivals,
        'maleArrivals': maleArrivals,
        'filipinoNationalArrivals': filipinoNationalArrivals,
        'totalSales': totalSales,
        'chargesA': chargesA,
        'chargesB': chargesB,
        'rowCount': rowCount,
        'filledDays': filledDays,
        'byCountry': {
          for (final e in byCountry.entries) _fieldKey(e.key): {
            'label': e.key,
            ...e.value.toMap(),
          },
        },
        'byRegion': {
          for (final e in byRegion.entries) _fieldKey(e.key): {
            'label': e.key,
            ...e.value.toMap(),
          },
        },
      };

  factory AeMonthTotals.fromMap(dynamic raw) {
    if (raw is! Map) return const AeMonthTotals();
    final m = Map<String, dynamic>.from(raw);
    return AeMonthTotals(
      checkIns: _int(m['checkIns']),
      checkOuts: _int(m['checkOuts']),
      guestNights: _int(m['guestNights']),
      roomsOccupied: _int(m['roomsOccupied']),
      occupancyRate: _doubleOrNull(m['occupancyRate']),
      alos: _doubleOrNull(m['alos']),
      avgPersonsPerRoom: _doubleOrNull(m['avgPersonsPerRoom']),
      domesticArrivals: _int(m['domesticArrivals']),
      domesticNights: _int(m['domesticNights']),
      foreignArrivals: _int(m['foreignArrivals']),
      foreignNights: _int(m['foreignNights']),
      overseasFilipinoArrivals: _int(m['overseasFilipinoArrivals']),
      overseasFilipinoNights: _int(m['overseasFilipinoNights']),
      unknownArrivals: _int(m['unknownArrivals']),
      unknownNights: _int(m['unknownNights']),
      femaleArrivals: _int(m['femaleArrivals']),
      maleArrivals: _int(m['maleArrivals']),
      filipinoNationalArrivals: _int(m['filipinoNationalArrivals']),
      totalSales: _double(m['totalSales']),
      chargesA: _double(m['chargesA']),
      chargesB: _double(m['chargesB']),
      rowCount: _int(m['rowCount']),
      filledDays: _int(m['filledDays']),
      byCountry: _labeledTotals(m['byCountry']),
      byRegion: _labeledTotals(m['byRegion']),
    );
  }

  static Map<String, AeCountryTotals> _labeledTotals(dynamic raw) {
    if (raw is! Map) return const {};
    final out = <String, AeCountryTotals>{};
    raw.forEach((k, v) {
      final label = v is Map && (v['label'] ?? '').toString().isNotEmpty
          ? v['label'].toString()
          : k.toString();
      out[label] = AeCountryTotals.fromMap(v);
    });
    return out;
  }

  /// Firestore map keys cannot contain `.`/`/` reliably — normalize.
  static String _fieldKey(String label) {
    final k = label.trim().replaceAll(RegExp(r'[^A-Za-z0-9]+'), '_');
    return k.isEmpty ? 'unspecified' : k;
  }
}

/// `ae_monthly_reports/{aeId}_{yyyy}_{mm}` header document.
class AeMonthlyReport {
  const AeMonthlyReport({
    required this.id,
    required this.aeId,
    required this.year,
    required this.month,
    this.aeName = '',
    this.municipalityId = '',
    this.municipality = '',
    this.province = 'Misamis Occidental',
    this.totalRooms = 0,
    this.aeType = '',
    this.classificationCode = '',
    this.category = '',
    this.prevMonthLastDayGuests = 0,
    this.zeroDays = const [],
    this.status = AeReportStatus.draft,
    this.submittedAt,
    this.updatedAt,
    this.totals = const AeMonthTotals(),
    this.isDemo = false,
    this.lastSignOff,
  });

  final String id;
  final String aeId;
  final int year;
  final int month;
  final String aeName;
  final String municipalityId;
  final String municipality;
  final String province;
  final int totalRooms;
  final String aeType;
  final String classificationCode;
  final String category;
  final int prevMonthLastDayGuests;

  /// Days explicitly marked "no guests" (counts toward completeness).
  final List<int> zeroDays;
  final AeReportStatus status;
  final DateTime? submittedAt;
  final DateTime? updatedAt;
  final AeMonthTotals totals;
  final bool isDemo;

  /// Latest signed save on this month (written by the service, not [toHeaderMap]).
  final SignOffStamp? lastSignOff;

  int get days => DateTime(year, month + 1, 0).day;
  String get periodKey => periodKeyFor(year, month);
  bool get isSubmitted => status == AeReportStatus.submitted;

  static String docIdFor(String aeId, int year, int month) =>
      '${aeId.trim()}_${year.toString().padLeft(4, '0')}_'
      '${month.toString().padLeft(2, '0')}';

  static String periodKeyFor(int year, int month) =>
      '${year.toString().padLeft(4, '0')}-${month.toString().padLeft(2, '0')}';

  AeMonthlyReport copyWith({
    String? aeName,
    String? municipalityId,
    String? municipality,
    int? totalRooms,
    String? aeType,
    String? classificationCode,
    String? category,
    int? prevMonthLastDayGuests,
    List<int>? zeroDays,
    AeReportStatus? status,
    DateTime? submittedAt,
    AeMonthTotals? totals,
  }) =>
      AeMonthlyReport(
        id: id,
        aeId: aeId,
        year: year,
        month: month,
        aeName: aeName ?? this.aeName,
        municipalityId: municipalityId ?? this.municipalityId,
        municipality: municipality ?? this.municipality,
        province: province,
        totalRooms: totalRooms ?? this.totalRooms,
        aeType: aeType ?? this.aeType,
        classificationCode: classificationCode ?? this.classificationCode,
        category: category ?? this.category,
        prevMonthLastDayGuests:
            prevMonthLastDayGuests ?? this.prevMonthLastDayGuests,
        zeroDays: zeroDays ?? this.zeroDays,
        status: status ?? this.status,
        submittedAt: submittedAt ?? this.submittedAt,
        updatedAt: updatedAt,
        totals: totals ?? this.totals,
        isDemo: isDemo,
        lastSignOff: lastSignOff,
      );

  Map<String, dynamic> toHeaderMap() => {
        'aeId': aeId,
        'aeName': aeName,
        'municipalityId': municipalityId,
        'municipality': municipality,
        'province': province,
        'periodKey': periodKey,
        'year': year,
        'month': month,
        'days': days,
        'totalRooms': totalRooms,
        'aeType': aeType,
        'classificationCode': classificationCode,
        'category': category,
        'prevMonthLastDayGuests': prevMonthLastDayGuests,
        'zeroDays': zeroDays,
        'status': status.name,
        if (submittedAt != null) 'submittedAt': Timestamp.fromDate(submittedAt!),
        'totals': totals.toMap(),
        if (isDemo) 'seed': 'demo',
      };

  factory AeMonthlyReport.fromMap(String id, Map<String, dynamic> m) {
    DateTime? ts(dynamic v) {
      if (v is Timestamp) return v.toDate();
      if (v is DateTime) return v;
      return null;
    }

    final zd = m['zeroDays'];
    return AeMonthlyReport(
      id: id,
      aeId: (m['aeId'] ?? '').toString(),
      year: _int(m['year']),
      month: _int(m['month']),
      aeName: (m['aeName'] ?? '').toString(),
      municipalityId: (m['municipalityId'] ?? '').toString(),
      municipality: (m['municipality'] ?? '').toString(),
      province: (m['province'] ?? 'Misamis Occidental').toString(),
      totalRooms: _int(m['totalRooms']),
      aeType: (m['aeType'] ?? '').toString(),
      classificationCode: (m['classificationCode'] ?? '').toString(),
      category: (m['category'] ?? '').toString(),
      prevMonthLastDayGuests: _int(m['prevMonthLastDayGuests']),
      zeroDays: zd is List ? zd.map(_int).where((d) => d > 0).toList() : const [],
      status: (m['status'] ?? '') == AeReportStatus.submitted.name
          ? AeReportStatus.submitted
          : AeReportStatus.draft,
      submittedAt: ts(m['submittedAt']),
      updatedAt: ts(m['updatedAt']),
      totals: AeMonthTotals.fromMap(m['totals']),
      isDemo: (m['seed'] ?? '').toString() == 'demo',
      lastSignOff: SignOffStamp.fromMap(m['lastSignOff']),
    );
  }

  factory AeMonthlyReport.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) =>
      AeMonthlyReport.fromMap(doc.id, doc.data() ?? const {});
}

int _int(dynamic v) {
  if (v is int) return v;
  if (v is num) return v.toInt();
  return int.tryParse((v ?? '').toString()) ?? 0;
}

double _double(dynamic v) {
  if (v is num) return v.toDouble();
  return double.tryParse((v ?? '').toString()) ?? 0;
}

double? _doubleOrNull(dynamic v) {
  if (v == null) return null;
  if (v is num) return v.toDouble();
  return double.tryParse(v.toString());
}

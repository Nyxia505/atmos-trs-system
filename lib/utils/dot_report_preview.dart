import 'package:atmos_trs_system/config/supabase_report_templates_config.dart';
import 'package:atmos_trs_system/utils/checkin_report_summary_csv.dart';
import 'package:atmos_trs_system/utils/checkin_visitor_expansion.dart';
import 'package:atmos_trs_system/utils/dae3_aggregates.dart';
import 'package:atmos_trs_system/config/dae_residence_catalog.dart';
import 'package:atmos_trs_system/models/ae_register.dart';
import 'package:atmos_trs_system/utils/ae_register_calculator.dart';
import 'package:atmos_trs_system/utils/ae_register_report_query.dart';
import 'package:atmos_trs_system/utils/dot_var2_visitor_record_report.dart';
import 'package:atmos_trs_system/utils/mice_register_calculator.dart';
import 'package:atmos_trs_system/utils/mice_report_query.dart';

/// Tabular preview of what a DOT export will contain (before download).
class DotReportPreviewTable {
  const DotReportPreviewTable({
    required this.headers,
    required this.rows,
    required this.summaryLine,
    this.footer,
    this.gaps = const [],
  });

  final List<String> headers;
  final List<List<String>> rows;
  final String summaryLine;
  final List<String>? footer;

  /// Field / policy gaps vs full official DOT annex.
  final List<String> gaps;

  bool get isEmpty => rows.isEmpty;
}

Map<String, Map<String, dynamic>> _indexTourists(
  List<Map<String, dynamic>> tourists,
) {
  final out = <String, Map<String, dynamic>>{};
  for (final t in tourists) {
    for (final key in ['id', 'firebaseUid', 'uid', 'userId', 'user_id']) {
      final id = t[key]?.toString().trim() ?? '';
      if (id.isNotEmpty) {
        out[id] = t;
        break;
      }
    }
  }
  return out;
}

String? _userIdFromCheckIn(Map<String, dynamic> c) {
  for (final key in ['userId', 'user_id', 'tourist_id', 'touristId']) {
    final id = c[key]?.toString().trim() ?? '';
    if (id.isNotEmpty) return id;
  }
  return null;
}

List<Map<String, dynamic>> _checkInsInRange(
  List<Map<String, dynamic>> checkIns,
  DateTime start,
  DateTime end, {
  DateTime? Function(Map<String, dynamic>)? parseTimestamp,
}) {
  final parse = parseTimestamp ?? parseCheckInTimestampFromMap;
  final startDay = DateTime(start.year, start.month, start.day);
  final endDay = DateTime(end.year, end.month, end.day, 23, 59, 59, 999);
  return checkIns.where((c) {
    if (isExcludedFromOfficialReports(c)) return false;
    final t = parse(c);
    if (t == null) return false;
    return !t.isBefore(startDay) && !t.isAfter(endDay);
  }).toList();
}

List<Map<String, dynamic>> _attachProfiles(
  List<Map<String, dynamic>> checkIns,
  Map<String, Map<String, dynamic>> touristById,
) {
  return checkIns.map((c) {
    if (c['touristProfile'] is Map) return c;
    final uid = _userIdFromCheckIn(c);
    final profile = uid == null ? null : touristById[uid];
    if (profile == null) return c;
    return <String, dynamic>{...c, 'touristProfile': profile};
  }).toList();
}

bool _isDomesticTourist(Map<String, dynamic> tourist) =>
    isDomesticVisitorProfile(tourist);

/// One profile per person (scanner / group members / companions).
/// Null entries are people whose residence is unknown (skipped by matrices).
({List<Map<String, dynamic>?> people, bool hasProxy}) _visitorProfiles(
  List<Map<String, dynamic>> filtered,
  Map<String, Map<String, dynamic>> touristById,
) {
  var hasProxy = false;
  final people = <Map<String, dynamic>?>[];
  for (final e in expandCheckInsToVisitors(
    filtered,
    profileFor: (c) => _profileFor(c, touristById),
  )) {
    final u = e.unit;
    if (u.isProxy) hasProxy = true;
    if (!u.hasProfile || (u.isProxy && !visitorHasResidencyInfo(u.profile))) {
      people.add(null);
    } else {
      people.add(u.profile);
    }
  }
  return (people: people, hasProxy: hasProxy);
}

String _domesticOriginLabel(Map<String, dynamic> tourist) {
  final city = tourist['city']?.toString().trim() ?? '';
  final province = tourist['province']?.toString().trim() ?? '';
  if (city.isNotEmpty && province.isNotEmpty) return '$city, $province';
  if (province.isNotEmpty) return province;
  if (city.isNotEmpty) return city;
  return tourist['nationality']?.toString().trim() ?? '';
}

String _countryLabel(Map<String, dynamic> tourist) {
  final country = tourist['country']?.toString().trim() ?? '';
  if (country.isNotEmpty) return country;
  final nationality = tourist['nationality']?.toString().trim() ?? '';
  if (nationality.isNotEmpty) return nationality;
  return 'Unspecified';
}

Map<String, dynamic>? _profileFor(
  Map<String, dynamic> c,
  Map<String, Map<String, dynamic>> touristById,
) {
  if (c['touristProfile'] is Map) {
    return Map<String, dynamic>.from(c['touristProfile'] as Map);
  }
  final uid = _userIdFromCheckIn(c);
  return uid == null ? null : touristById[uid];
}

/// Builds an on-screen preview for **every** catalog form (best-effort + gaps).
///
/// [aeRegister] — hotel DOT registers ([fetchAeRegisterReportData]).
/// Used for **DAE-family** forms only; VAR forms ignore them.
DotReportPreviewTable buildDotReportPreview({
  required DotFormCatalogEntry form,
  required DateTime startDate,
  required DateTime endDate,
  required List<Map<String, dynamic>> checkIns,
  required List<Map<String, dynamic>> tourists,
  required List<DotVar2SpotCatalogEntry> catalogSpots,
  required String scopeLabel,
  DateTime? Function(Map<String, dynamic> checkIn)? parseTimestamp,
  AeRegisterReportData aeRegister = AeRegisterReportData.empty,
  MiceReportData mice = MiceReportData.empty,
}) {
  if (form.reportType == DotReportType.cusMice) {
    return buildCusMicePreview(form: form, mice: mice, scopeLabel: scopeLabel);
  }
  final touristById = _indexTourists(tourists);
  final filtered = _attachProfiles(
    _checkInsInRange(
      checkIns,
      startDate,
      endDate,
      parseTimestamp: parseTimestamp,
    ),
    touristById,
  );
  final hasRegister = aeRegister.isNotEmpty;

  final type = form.reportType;
  if (type != null) {
    switch (type) {
      case DotReportType.var2VisitorRecord:
        return _previewVar2(
          filtered: filtered,
          catalogSpots: catalogSpots,
          scopeLabel: scopeLabel,
          startDate: startDate,
          endDate: endDate,
        );
      case DotReportType.var4DomesticTravelers:
        return _previewOriginMatrix(
          filtered: filtered,
          touristById: touristById,
          scopeLabel: scopeLabel,
          domesticOnly: true,
          titleCode: form.code,
          gaps: const [
            'Overnight vs day-trip not collected — all QR visits counted equally.',
            'PSA region rows not mapped yet — showing city/province text.',
            'Official VAR 4 cell layout may differ; Excel is ATMOS best-effort.',
          ],
        );
      case DotReportType.var5InternationalVisitors:
        return _previewCountryMatrix(
          filtered: filtered,
          touristById: touristById,
          scopeLabel: scopeLabel,
          titleCode: form.code,
          gaps: const [
            'DOT Form A country-row taxonomy not mapped yet — raw country labels.',
            'Official sheet cell layout may differ; Excel is ATMOS best-effort.',
          ],
        );
      case DotReportType.dae3bFormAInternational:
        if (hasRegister) {
          return _previewRegisterCountryMatrix(
            form: form,
            register: aeRegister,
            scopeLabel: scopeLabel,
          );
        }
        return _previewCountryMatrix(
          filtered: filtered,
          touristById: touristById,
          scopeLabel: scopeLabel,
          titleCode: form.code,
          gaps: const [
            'No hotel DOT register months in range — attraction/LGU QR used as labeled proxy.',
            'DOT Form A country-row taxonomy not mapped for QR profiles — raw country labels.',
            'Official sheet cell layout may differ; Excel is ATMOS best-effort.',
          ],
        );
      case DotReportType.dae3FormA:
        return _previewDae3(
          filtered: filtered,
          register: aeRegister,
          scopeLabel: scopeLabel,
          parseTimestamp: parseTimestamp,
        );
      case DotReportType.dae3b2Domestic:
        if (hasRegister) {
          return _previewRegisterDomestic(
            form: form,
            register: aeRegister,
            scopeLabel: scopeLabel,
          );
        }
        return _previewDae3b2(
          filtered: filtered,
          touristById: touristById,
          scopeLabel: scopeLabel,
        );
      case DotReportType.cusMice:
        return buildCusMicePreview(form: form, mice: mice, scopeLabel: scopeLabel);
    }
  }

  return _previewEstablishmentForm(
    form: form,
    filtered: filtered,
    register: aeRegister,
    scopeLabel: scopeLabel,
  );
}

/// CUS MICE preview: CUS SUMMARY rows (venue column when several venues).
/// Same rows feed the Excel writer and the PDF.
DotReportPreviewTable buildCusMicePreview({
  required DotFormCatalogEntry form,
  required MiceReportData mice,
  required String scopeLabel,
}) {
  final venues = mice.venues;
  final multi = venues.length > 1;
  final rows = mice.summaryRows;
  final t = mice.combined;
  String n(int v) => v == 0 ? '-' : '$v';
  return DotReportPreviewTable(
    headers: [
      'CN',
      'Date',
      'Event name',
      if (multi) 'Establishment',
      'Hours',
      'Type of event',
      'Foreign',
      'Local',
      'Total',
      'Male',
      'Female',
      'Exhibitors',
      'Visitors',
      'Organizer, contact & tel. no.',
      'Remarks',
    ],
    rows: [
      for (final (v, e) in rows)
        [
          '${v.controlNumbers[e.id] ?? ''}',
          MiceRegisterCalculator.dateLabel(e),
          e.eventName,
          if (multi) v.aeName,
          MiceRegisterCalculator.hoursLabel(e.hours),
          e.eventType,
          '${e.foreign}',
          '${e.local}',
          '${e.total}',
          '${e.male}',
          '${e.female}',
          e.hasExhibit ? '${e.exhibitors}' : '-',
          e.hasExhibit ? '${e.exhibitVisitors}' : '-',
          e.organizerCell.isEmpty ? '—' : e.organizerCell,
          e.remarks,
        ],
    ],
    summaryLine: mice.isEmpty
        ? '${form.code} · no venue MICE months in range · $scopeLabel'
        : '${form.code} · ${t.events} event(s) at ${venues.length} venue(s) · ${t.attendees} attendees '
            '(${t.local} local · ${t.foreign} foreign) · ${MiceRegisterCalculator.hoursLabel(t.hours)} h · '
            '${mice.periodLabel} · $scopeLabel',
    footer: rows.isEmpty
        ? null
        : [
            '',
            'TOTAL',
            '${t.events} event(s)',
            if (multi) '${venues.length} venue(s)',
            MiceRegisterCalculator.hoursLabel(t.hours),
            '',
            '${t.foreign}',
            '${t.local}',
            '${t.attendees}',
            '${t.male}',
            '${t.female}',
            n(t.exhibitors),
            n(t.exhibitVisitors),
            '',
            '',
          ],
    gaps: mice.isEmpty
        ? [
            '${form.code} needs venue MICE event logs in range.',
            'Venues turn on "We host events (MICE)" in their Profile, then log events on the Events tab.',
          ]
        : mice.sourceGaps(form.code),
  );
}

DotReportPreviewTable _previewVar2({
  required List<Map<String, dynamic>> filtered,
  required List<DotVar2SpotCatalogEntry> catalogSpots,
  required String scopeLabel,
  required DateTime startDate,
  required DateTime endDate,
}) {
  final var2 = buildDotVar2VisitorRecordReport(
    checkIns: filtered,
    catalogSpots: catalogSpots,
    municipalityName: scopeLabel,
    startDate: startDate,
    endDate: endDate,
  );
  final active = var2.rows.where((r) => r.grandTotal.total > 0).toList();
  const headers = [
    'Attraction',
    'Code',
    'This municipality',
    'This province',
    'Other province',
    'Foreign',
    'Total',
  ];
  final rows = [
    for (final r in active)
      [
        r.name,
        r.attractionCode.isEmpty ? '—' : r.attractionCode,
        '${r.thisMunicipality.total}',
        '${r.thisProvince.total}',
        '${r.otherProvince.total}',
        '${r.foreign.total}',
        '${r.grandTotal.total}',
      ],
  ];
  final f = var2.footerTotals;
  return DotReportPreviewTable(
    headers: headers,
    rows: rows,
    summaryLine:
        '${var2.checkInsProcessed} check-ins · ${active.length} attraction row(s) · '
        '${var2.monthYearLabel}',
    footer: active.isEmpty
        ? null
        : [
            'TOTAL',
            '',
            '${f.thisMunicipality.total}',
            '${f.thisProvince.total}',
            '${f.otherProvince.total}',
            '${f.foreign.total}',
            '${f.grandTotal.total}',
          ],
    gaps: [
      if (var2.note.trim().isNotEmpty) var2.note.trim(),
      'Attraction codes blank when spot has no dotAttractionCode.',
    ],
  );
}

DotReportPreviewTable _previewDae3({
  required List<Map<String, dynamic>> filtered,
  required AeRegisterReportData register,
  required String scopeLabel,
  DateTime? Function(Map<String, dynamic>)? parseTimestamp,
}) {
  final fromRegister = register.isNotEmpty;
  final agg = aggregateDae3PreferringRegister(
    reports: register.reports,
    checkIns: filtered,
    scopeLabel: scopeLabel,
    parseCheckInTimestamp: parseTimestamp,
  );
  const headers = [
    'Province',
    'Municipality',
    'Year',
    'Month',
    'AE',
    'Type',
    'Rooms avail.',
    'Guests',
    'Guest nights',
    'Rooms occupied',
    'Room nights',
    'Occ. %',
  ];
  final rows = [
    for (final r in agg)
      [
        r.province,
        r.municipality,
        '${r.year}',
        r.month.toString().padLeft(2, '0'),
        r.aeId,
        r.typeClass.isEmpty ? '—' : r.typeClass,
        r.roomsAvailable == null ? '—' : '${r.roomsAvailable}',
        '${r.guestsCheckedIn}',
        r.guestNights == null ? '—' : '${r.guestNights}',
        r.roomsOccupied == null ? '—' : '${r.roomsOccupied}',
        r.roomNights == null ? '—' : '${r.roomNights}',
        r.occupancyPct == null
            ? '—'
            : '${r.occupancyPct!.toStringAsFixed(1)}%',
      ],
  ];
  final totalGuests = agg.fold<int>(0, (sum, r) => sum + r.guestsCheckedIn);
  final totalRoomNights =
      agg.fold<int>(0, (sum, r) => sum + (r.roomNights ?? 0));
  return DotReportPreviewTable(
    headers: headers,
    rows: rows,
    summaryLine: fromRegister
        ? '${register.reports.length} AE-month register(s) → ${agg.length} AE row(s) · '
            '$totalGuests guests · $totalRoomNights room-nights'
        : '${filtered.length} check-ins (proxy) → ${agg.length} AE row(s) · $totalGuests guests',
    gaps: fromRegister
        ? [
            ...register.sourceGaps('DAE-3'),
            'Guests = check-ins; guest nights = Σ register guests; rooms occupied = register rows.',
            'Occ. % = rooms occupied ÷ (rooms avail. × days in month) — ATMOS preview aid.',
          ]
        : const [
            'No hotel DOT register months in range — attraction/LGU QR used as labeled proxy.',
            'Rooms occupied / guest-nights blank until hotels fill their monthly register.',
            'AE-ID uses spot name as proxy — not accommodation_establishments.',
          ],
  );
}

DotReportPreviewTable _previewDae3b2({
  required List<Map<String, dynamic>> filtered,
  required Map<String, Map<String, dynamic>> touristById,
  required String scopeLabel,
}) {
  final byOrigin = <String, int>{};
  var male = 0;
  var female = 0;
  var skipped = 0;
  final visitors = _visitorProfiles(filtered, touristById);

  for (final tourist in visitors.people) {
    if (tourist == null || !_isDomesticTourist(tourist)) {
      skipped++;
      continue;
    }
    final origin = _domesticOriginLabel(tourist);
    if (origin.isEmpty) {
      skipped++;
      continue;
    }
    byOrigin[origin] = (byOrigin[origin] ?? 0) + 1;
    final sex = (tourist['sex']?.toString() ?? '').trim().toLowerCase();
    if (sex.startsWith('m')) {
      male++;
    } else if (sex.startsWith('f')) {
      female++;
    }
  }

  final origins = byOrigin.keys.toList()..sort();
  const headers = ['Province / City of origin', 'Guests'];
  final rows = [
    for (final o in origins) [o, '${byOrigin[o]}'],
  ];
  final total = byOrigin.values.fold<int>(0, (a, b) => a + b);
  return DotReportPreviewTable(
    headers: headers,
    rows: rows,
    summaryLine:
        '$total domestic guests · Male $male · Female $female'
        '${skipped > 0 ? ' · $skipped skipped (foreign / incomplete)' : ''}'
        ' · $scopeLabel',
    footer: rows.isEmpty ? null : ['TOTAL', '$total'],
    gaps: [
      'No hotel DOT register months in range — QR visits used as domestic proxy rows.',
      'PSA region not derived for QR profiles — city/province text only.',
      'Official DAE 3B.2 layout may use ATMOS-built sheet.',
      if (visitors.hasProxy) kCompanionProxyGapNote,
    ],
  );
}

DotReportPreviewTable _previewOriginMatrix({
  required List<Map<String, dynamic>> filtered,
  required Map<String, Map<String, dynamic>> touristById,
  required String scopeLabel,
  required bool domesticOnly,
  required String titleCode,
  required List<String> gaps,
}) {
  final byOrigin = <String, int>{};
  var skipped = 0;
  final visitors = _visitorProfiles(filtered, touristById);
  for (final tourist in visitors.people) {
    if (tourist == null) {
      skipped++;
      continue;
    }
    if (domesticOnly && !_isDomesticTourist(tourist)) {
      skipped++;
      continue;
    }
    if (!domesticOnly && _isDomesticTourist(tourist)) {
      skipped++;
      continue;
    }
    final origin = _domesticOriginLabel(tourist);
    if (origin.isEmpty) {
      skipped++;
      continue;
    }
    byOrigin[origin] = (byOrigin[origin] ?? 0) + 1;
  }
  final keys = byOrigin.keys.toList()..sort();
  final rows = [
    for (final k in keys) [k, '${byOrigin[k]}'],
  ];
  final total = byOrigin.values.fold<int>(0, (a, b) => a + b);
  return DotReportPreviewTable(
    headers: const ['Origin (city / province)', 'Visits'],
    rows: rows,
    summaryLine:
        '$titleCode · $total row total · $skipped skipped · $scopeLabel',
    footer: rows.isEmpty ? null : ['TOTAL', '$total'],
    gaps: [...gaps, if (visitors.hasProxy) kCompanionProxyGapNote],
  );
}

DotReportPreviewTable _previewCountryMatrix({
  required List<Map<String, dynamic>> filtered,
  required Map<String, Map<String, dynamic>> touristById,
  required String scopeLabel,
  required String titleCode,
  required List<String> gaps,
}) {
  final byCountry = <String, int>{};
  var skipped = 0;
  final visitors = _visitorProfiles(filtered, touristById);
  for (final tourist in visitors.people) {
    if (tourist == null || _isDomesticTourist(tourist)) {
      skipped++;
      continue;
    }
    final country = _countryLabel(tourist);
    byCountry[country] = (byCountry[country] ?? 0) + 1;
  }
  final keys = byCountry.keys.toList()..sort();
  final rows = [
    for (final k in keys) [k, '${byCountry[k]}'],
  ];
  final total = byCountry.values.fold<int>(0, (a, b) => a + b);
  return DotReportPreviewTable(
    headers: const ['Country of residence', 'Visits'],
    rows: rows,
    summaryLine:
        '$titleCode · $total foreign visits · $skipped skipped · $scopeLabel',
    footer: rows.isEmpty ? null : ['TOTAL', '$total'],
    gaps: [...gaps, if (visitors.hasProxy) kCompanionProxyGapNote],
  );
}

String _ym(int year, int month) => '$year-${month.toString().padLeft(2, '0')}';

/// DAE-1B "by Country (Sum)" from hotel registers (DAE 1B.2 / DAE3 Form A).
DotReportPreviewTable _previewRegisterCountryMatrix({
  required DotFormCatalogEntry form,
  required AeRegisterReportData register,
  required String scopeLabel,
}) {
  final t = register.combined;
  final lines = AeRegisterCalculator.countryMatrix(t.byCountry);
  final rows = <List<String>>[];
  for (final l in lines) {
    final v = l.totals;
    if (v == null) {
      rows.add([l.label, '', '', '', '', '']);
      continue;
    }
    final empty = v.arrivals == 0 && v.nights == 0;
    if (empty &&
        (l.kind == AeMatrixLineKind.country || l.kind == AeMatrixLineKind.subtotal)) {
      continue;
    }
    rows.add([
      l.label,
      '${v.arrivals}',
      '${v.nights}',
      '${v.female}',
      '${v.male}',
      AeRegisterCalculator.dec(l.alos),
    ]);
  }
  return DotReportPreviewTable(
    headers: const ['Country of residence', 'Arrivals', 'Guest nights', 'Female', 'Male', 'ALOS'],
    rows: rows,
    summaryLine: '${form.code} · ${t.checkIns} arrivals · ${t.guestNights} guest-nights · '
        'foreign ${t.foreignArrivals} · overseas Filipinos ${t.overseasFilipinoArrivals} · $scopeLabel',
    gaps: [
      ...register.sourceGaps(form.code),
      'Countries with no arrivals are hidden; section totals always shown.',
    ],
  );
}

/// Domestic guests by PH region × month from hotel registers (DAE 3B.2 / DAE 1B.2 Dom).
DotReportPreviewTable _previewRegisterDomestic({
  required DotFormCatalogEntry form,
  required AeRegisterReportData register,
  required String scopeLabel,
}) {
  final byMonth = <String, List<AeMonthlyReport>>{};
  for (final r in register.reports) {
    byMonth.putIfAbsent(_ym(r.year, r.month), () => []).add(r);
  }
  final months = byMonth.keys.toList()..sort();
  final monthTotals = {
    for (final m in months) m: AeRegisterCalculator.combine(byMonth[m]!.map((r) => r.totals)),
  };
  const unspecified = 'Region not specified';
  final regions = [...DaeResidenceCatalog.philippineRegions, unspecified];

  int arrivalsFor(String region, AeMonthTotals t) {
    if (region != unspecified) return t.byRegion[region]?.arrivals ?? 0;
    final named = t.byRegion.values.fold<int>(0, (s, v) => s + v.arrivals);
    return (t.domesticArrivals - named).clamp(0, 1 << 30);
  }

  int nightsFor(String region, AeMonthTotals t) {
    if (region != unspecified) return t.byRegion[region]?.nights ?? 0;
    final named = t.byRegion.values.fold<int>(0, (s, v) => s + v.nights);
    return (t.domesticNights - named).clamp(0, 1 << 30);
  }

  final rows = <List<String>>[];
  final colTotals = List<int>.filled(months.length, 0);
  var totalArrivals = 0, totalNights = 0;
  for (final region in regions) {
    final perMonth = [for (final m in months) arrivalsFor(region, monthTotals[m]!)];
    final arrivals = perMonth.fold<int>(0, (a, b) => a + b);
    final nights = months.fold<int>(0, (s, m) => s + nightsFor(region, monthTotals[m]!));
    if (arrivals == 0 && nights == 0) continue;
    for (var i = 0; i < months.length; i++) {
      colTotals[i] += perMonth[i];
    }
    totalArrivals += arrivals;
    totalNights += nights;
    rows.add([region, for (final v in perMonth) '$v', '$arrivals', '$nights']);
  }

  var female = 0, male = 0;
  register.combined.byCountry.forEach((k, v) {
    if (DaeResidenceCatalog.bucketFor(k) != DaeResidenceBucket.philippineResident) return;
    female += v.female;
    male += v.male;
  });

  return DotReportPreviewTable(
    headers: ['PH region of residence', ...months, 'Total arrivals', 'Guest nights'],
    rows: rows,
    summaryLine: '${form.code} · $totalArrivals domestic arrivals · $totalNights guest-nights · '
        'Female $female · Male $male · $scopeLabel',
    footer: rows.isEmpty
        ? null
        : ['TOTAL', for (final v in colTotals) '$v', '$totalArrivals', '$totalNights'],
    gaps: [
      ...register.sourceGaps(form.code),
      'Domestic = Philippine residents (Filipino + foreign nationality living in PH).',
      'PH region is optional on the register — unfilled guests go to "$unspecified".',
    ],
  );
}

/// One KPI line per AE-month register (DAE-1B fallback / multi-establishment).
DotReportPreviewTable _previewRegisterMonthKpis({
  required DotFormCatalogEntry form,
  required AeRegisterReportData register,
  required String scopeLabel,
  List<String> extraGaps = const [],
}) {
  final reports = [...register.reports]
    ..sort((a, b) {
      final m = _ym(a.year, a.month).compareTo(_ym(b.year, b.month));
      return m != 0 ? m : a.aeName.compareTo(b.aeName);
    });
  final t = register.combined;
  return DotReportPreviewTable(
    headers: const [
      'AE',
      'Municipality',
      'Month',
      'Type',
      'Class code',
      'Rooms',
      'Check-ins',
      'Guest nights',
      'Rooms occupied',
      'Occupancy',
      'ALOS',
      'Persons/room',
      'Status',
    ],
    rows: [
      for (final r in reports)
        [
          r.aeName.isEmpty ? r.aeId : r.aeName,
          r.municipality,
          _ym(r.year, r.month),
          r.aeType.isEmpty ? '—' : r.aeType,
          r.classificationCode.isEmpty ? '—' : r.classificationCode,
          r.totalRooms > 0 ? '${r.totalRooms}' : '—',
          '${r.totals.checkIns}',
          '${r.totals.guestNights}',
          '${r.totals.roomsOccupied}',
          AeRegisterCalculator.pct(r.totals.occupancyRate, digits: 1),
          AeRegisterCalculator.dec(r.totals.alos),
          AeRegisterCalculator.dec(r.totals.avgPersonsPerRoom),
          r.isSubmitted ? 'Submitted' : 'Draft',
        ],
    ],
    summaryLine: '${form.code} · ${reports.length} AE-month register(s) · ${t.checkIns} check-ins · '
        '${t.guestNights} guest-nights · occupancy '
        '${AeRegisterCalculator.pct(AeRegisterCalculator.combinedOccupancy(reports), digits: 1)} · '
        '$scopeLabel',
    footer: reports.isEmpty
        ? null
        : [
            'TOTAL',
            '',
            '',
            '',
            '',
            '',
            '${t.checkIns}',
            '${t.guestNights}',
            '${t.roomsOccupied}',
            AeRegisterCalculator.pct(AeRegisterCalculator.combinedOccupancy(reports), digits: 1),
            AeRegisterCalculator.dec(t.alos),
            AeRegisterCalculator.dec(t.avgPersonsPerRoom),
            '',
          ],
    gaps: [...register.sourceGaps(form.code), ...extraGaps],
  );
}

/// DAE-2 auto summary for a single AE-month (DAE-1B macro register).
DotReportPreviewTable _previewRegisterDae2({
  required DotFormCatalogEntry form,
  required AeRegisterReportData register,
  required String scopeLabel,
}) {
  final r = register.reports.single;
  final items = AeRegisterCalculator.dae2Summary(r, r.totals);
  return DotReportPreviewTable(
    headers: const ['Item', 'Description', 'Value'],
    rows: [
      for (final i in items) ['(${i.no})', i.label, i.value.isEmpty ? '—' : i.value],
    ],
    summaryLine: '${form.code} · DAE-2 summary · ${r.aeName} · ${_ym(r.year, r.month)} · $scopeLabel',
    gaps: register.sourceGaps(form.code),
  );
}

/// Daily MonthlyRecord tally per AE (DAE-1A manual tally).
DotReportPreviewTable _previewRegisterDaily({
  required DotFormCatalogEntry form,
  required AeRegisterReportData register,
  required String scopeLabel,
}) {
  final rows = <List<String>>[];
  var checkIns = 0, guestNights = 0, rooms = 0;
  final reports = [...register.reports]
    ..sort((a, b) {
      final n = a.aeName.compareTo(b.aeName);
      return n != 0 ? n : _ym(a.year, a.month).compareTo(_ym(b.year, b.month));
    });
  for (final r in reports) {
    final lines = AeRegisterCalculator.dailyTable(
      rows: register.rowsFor(r),
      year: r.year,
      month: r.month,
      totalRooms: r.totalRooms,
      prevMonthLastDayGuests: r.prevMonthLastDayGuests,
      zeroDays: r.zeroDays,
    );
    for (final l in lines) {
      if (!l.isFilled) continue;
      checkIns += l.checkIns;
      guestNights += l.guestNights;
      rooms += l.roomsOccupied;
      rows.add([
        r.aeName.isEmpty ? r.aeId : r.aeName,
        '${_ym(r.year, r.month)}-${l.day.toString().padLeft(2, '0')}',
        '${l.checkIns}',
        '${l.checkOuts}',
        '${l.guestNights}',
        '${l.roomsOccupied}',
        AeRegisterCalculator.pct(l.occupancyRate, digits: 1),
      ]);
    }
  }
  return DotReportPreviewTable(
    headers: const ['AE', 'Date', 'Check-ins', 'Check-outs', 'Guest nights', 'Rooms occupied', 'Occupancy'],
    rows: rows,
    summaryLine: '${form.code} · ${rows.length} filled day(s) · $checkIns check-ins · '
        '$guestNights guest-nights · $rooms room-nights · $scopeLabel',
    footer: rows.isEmpty ? null : ['TOTAL', '', '$checkIns', '', '$guestNights', '$rooms', ''],
    gaps: [
      ...register.sourceGaps(form.code),
      'Only filled days are listed (days with rows or marked "no guests").',
    ],
  );
}

DotReportPreviewTable _previewEstablishmentForm({
  required DotFormCatalogEntry form,
  required List<Map<String, dynamic>> filtered,
  required AeRegisterReportData register,
  required String scopeLabel,
}) {
  if (register.isNotEmpty) {
    switch (form.id) {
      case 'dae1b2':
        return _previewRegisterCountryMatrix(form: form, register: register, scopeLabel: scopeLabel);
      case 'dae1b2_domestic':
        return _previewRegisterDomestic(form: form, register: register, scopeLabel: scopeLabel);
      case 'dae1b_macro':
        if (register.reports.length == 1) {
          return _previewRegisterDae2(form: form, register: register, scopeLabel: scopeLabel);
        }
        return _previewRegisterMonthKpis(
          form: form,
          register: register,
          scopeLabel: scopeLabel,
          extraGaps: const [
            'Several AE-months in scope — showing one DAE-2 KPI line each. '
                'Pick one establishment and one month for the full DAE-2 summary.',
          ],
        );
      case 'dae1a_manual':
        if (register.hasRows) {
          return _previewRegisterDaily(form: form, register: register, scopeLabel: scopeLabel);
        }
        return _previewRegisterMonthKpis(form: form, register: register, scopeLabel: scopeLabel);
      default:
        return _previewRegisterMonthKpis(form: form, register: register, scopeLabel: scopeLabel);
    }
  }

  return DotReportPreviewTable(
    headers: const ['Status', 'Detail'],
    rows: [
      [
        'Proxy note',
        '${filtered.length} attraction/LGU visit(s) in range — not hotel overnight data.',
      ],
      const ['Gap', 'No hotel DOT register months in this date range yet.'],
      const ['Gap', 'Hotels fill the Daily Register on the establishment dashboard.'],
    ],
    summaryLine: '${form.code} · awaiting hotel DOT registers · $scopeLabel',
    gaps: [
      '${form.code} needs hotel DOT register (DAE-1B) months in range.',
      'Do not treat attraction QR counts as hotel occupancy.',
    ],
  );
}

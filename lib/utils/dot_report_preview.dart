import 'package:atmos_trs_system/config/supabase_report_templates_config.dart';
import 'package:atmos_trs_system/utils/checkin_report_summary_csv.dart';
import 'package:atmos_trs_system/utils/dae3_aggregates.dart';
import 'package:atmos_trs_system/utils/dot_var2_visitor_record_report.dart';
import 'package:atmos_trs_system/utils/establishment_stay_report_query.dart';

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

bool _isDomesticTourist(Map<String, dynamic> tourist) {
  final localOrForeign = tourist['localOrForeign']?.toString().trim() ?? '';
  if (localOrForeign.toLowerCase() == 'foreign') return false;
  if (tourist['isLocal'] == true) return true;
  final country = (tourist['country']?.toString() ?? '').trim().toLowerCase();
  final nationality =
      (tourist['nationality']?.toString() ?? '').trim().toLowerCase();
  if (country.contains('philippine') || country == 'ph' || country == 'phl') {
    return true;
  }
  if (nationality.contains('filipino') || nationality.contains('philippine')) {
    return true;
  }
  return localOrForeign.toLowerCase() == 'local';
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
/// [confirmedStays] — maps from [fetchConfirmedEstablishmentStays] / stay events.
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
  List<Map<String, dynamic>> confirmedStays = const [],
}) {
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
  final stayEvents = _attachProfiles(
    _checkInsInRange(
      confirmedStays,
      startDate,
      endDate,
      parseTimestamp: parseStayEventTimestamp,
    ),
    touristById,
  );
  final hasStays = stayEvents.isNotEmpty;

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
        return _previewCountryMatrix(
          filtered: hasStays ? stayEvents : filtered,
          touristById: touristById,
          scopeLabel: scopeLabel,
          titleCode: form.code,
          gaps: [
            'DOT Form A country-row taxonomy not mapped yet — raw country labels.',
            if (!hasStays)
              'No confirmed AE stays in range — using attraction/LGU QR as labeled proxy.',
            if (hasStays)
              'Filled from confirmed establishment stays (party counted once per stay).',
            'Official sheet cell layout may differ; Excel is ATMOS best-effort.',
          ],
        );
      case DotReportType.dae3FormA:
        return _previewDae3(
          filtered: filtered,
          stayEvents: stayEvents,
          scopeLabel: scopeLabel,
          parseTimestamp: parseTimestamp,
        );
      case DotReportType.dae3b2Domestic:
        return _previewDae3b2(
          filtered: hasStays ? stayEvents : filtered,
          touristById: touristById,
          scopeLabel: scopeLabel,
          fromConfirmedStays: hasStays,
        );
    }
  }

  // Forms without a dedicated filler yet — still preview + gaps.
  if (form.category == DotFormCategory.mice) {
    return DotReportPreviewTable(
      headers: const ['Status', 'Detail'],
      rows: const [
        [
          'Gap',
          'No MICE utilization records linked yet — publish events / add MICE fields later.',
        ],
      ],
      summaryLine:
          '${form.code} · ${filtered.length} visit(s) in range (not MICE-specific) · $scopeLabel',
      gaps: const [
        'CUS MICE needs event utilization fields (venue, pax, days).',
        'LGU events are announcements today — not full MICE survey rows.',
      ],
    );
  }

  return _previewEstablishmentGaps(
    form: form,
    filtered: filtered,
    stayEvents: stayEvents,
    scopeLabel: scopeLabel,
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
  required List<Map<String, dynamic>> stayEvents,
  required String scopeLabel,
  DateTime? Function(Map<String, dynamic>)? parseTimestamp,
}) {
  final fromStays = stayEvents.isNotEmpty;
  final agg = aggregateDae3PreferringStays(
    stayEvents: stayEvents,
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
    summaryLine: fromStays
        ? '${stayEvents.length} confirmed stay(s) → ${agg.length} AE row(s) · '
            '$totalGuests guests · $totalRoomNights room-nights'
        : '${filtered.length} check-ins (proxy) → ${agg.length} AE row(s) · $totalGuests guests',
    gaps: fromStays
        ? const [
            'Filled from confirmed establishment stays (pending stays excluded).',
            'Guest Male/Female and Filipino/Foreign come from staff confirm counts.',
            'Room nights = rooms × nights; Occ. % = room-nights ÷ (rooms avail. × days in month).',
            'Official DAE-3 Excel keeps annex columns; Occ. % is ATMOS preview aid.',
          ]
        : const [
            'No confirmed AE stays in range — attraction/LGU QR used as labeled proxy.',
            'Rooms occupied / guest-nights blank until staff-confirmed stays exist.',
            'AE-ID uses spot name as proxy — not accommodation_establishments.',
          ],
  );
}

DotReportPreviewTable _previewDae3b2({
  required List<Map<String, dynamic>> filtered,
  required Map<String, Map<String, dynamic>> touristById,
  required String scopeLabel,
  required bool fromConfirmedStays,
}) {
  final byOrigin = <String, int>{};
  var male = 0;
  var female = 0;
  var skipped = 0;

  for (final c in filtered) {
    final tourist = _profileFor(c, touristById);

    if (fromConfirmedStays) {
      final fil = _countOrZero(c['filipinoCount']);
      final for_ = _countOrZero(c['foreignCount']);
      final hasResidencyCounts = fil + for_ > 0;
      final domesticWeight = hasResidencyCounts
          ? fil
          : ((tourist != null && _isDomesticTourist(tourist))
              ? _partyWeight(c)
              : 0);
      if (domesticWeight <= 0) {
        skipped++;
        continue;
      }
      final origin = tourist == null
          ? ''
          : _domesticOriginLabel(tourist);
      if (origin.isEmpty) {
        skipped++;
        continue;
      }
      byOrigin[origin] = (byOrigin[origin] ?? 0) + domesticWeight;

      final m = _countOrZero(c['maleCount']);
      final f = _countOrZero(c['femaleCount']);
      if (m + f > 0) {
        // Prefer stay sex counts; scale to domestic share when mixed party.
        final party = _partyWeight(c);
        if (hasResidencyCounts && for_ > 0 && party > 0) {
          male += ((m * domesticWeight) / party).round();
          female += ((f * domesticWeight) / party).round();
        } else {
          male += m;
          female += f;
        }
      } else if (tourist != null) {
        final sex = (tourist['sex']?.toString() ?? '').trim().toLowerCase();
        if (sex.startsWith('m')) {
          male += domesticWeight;
        } else if (sex.startsWith('f')) {
          female += domesticWeight;
        }
      }
      continue;
    }

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
    gaps: fromConfirmedStays
        ? const [
            'Filled from confirmed establishment stays.',
            'Domestic weight uses Filipino count; sex uses Male/Female counts.',
            'Country/nationality/origin snapshotted from tourist account.',
            'PSA region not derived — city/province text only.',
          ]
        : const [
            'No confirmed AE stays — QR visits used as domestic proxy rows.',
            'PSA region not derived — city/province text only.',
            'Official DAE 3B.2 layout may use ATMOS-built sheet.',
          ],
  );
}

int _countOrZero(dynamic v) {
  if (v is int) return v < 0 ? 0 : v;
  if (v is num) {
    final n = v.toInt();
    return n < 0 ? 0 : n;
  }
  return int.tryParse(v?.toString() ?? '') ?? 0;
}

int _partyWeight(Map<String, dynamic> event) {
  final p = event['partySize'];
  if (p is int && p > 0) return p;
  if (p is num && p.toInt() > 0) return p.toInt();
  return int.tryParse(p?.toString() ?? '') ?? 1;
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
  for (final c in filtered) {
    final tourist = _profileFor(c, touristById);
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
    gaps: gaps,
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
  for (final c in filtered) {
    final tourist = _profileFor(c, touristById);
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
    gaps: gaps,
  );
}

DotReportPreviewTable _previewEstablishmentGaps({
  required DotFormCatalogEntry form,
  required List<Map<String, dynamic>> filtered,
  required List<Map<String, dynamic>> stayEvents,
  required String scopeLabel,
}) {
  if (stayEvents.isNotEmpty) {
    final agg = aggregateDae3FromConfirmedStays(
      stayEvents: stayEvents,
      scopeLabel: scopeLabel,
    );
    final totalGuests =
        agg.fold<int>(0, (sum, r) => sum + r.guestsCheckedIn);
    final totalNights =
        agg.fold<int>(0, (sum, r) => sum + (r.guestNights ?? 0));
    final totalRooms =
        agg.fold<int>(0, (sum, r) => sum + (r.roomsOccupied ?? 0));
    final totalRoomNights =
        agg.fold<int>(0, (sum, r) => sum + (r.roomNights ?? 0));
    return DotReportPreviewTable(
      headers: const [
        'AE',
        'Municipality',
        'Month',
        'Guests',
        'Guest nights',
        'Rooms occupied',
        'Room nights',
        'Occ. %',
      ],
      rows: [
        for (final r in agg)
          [
            r.aeId,
            r.municipality,
            '${r.year}-${r.month.toString().padLeft(2, '0')}',
            '${r.guestsCheckedIn}',
            r.guestNights == null ? '—' : '${r.guestNights}',
            r.roomsOccupied == null ? '—' : '${r.roomsOccupied}',
            r.roomNights == null ? '—' : '${r.roomNights}',
            r.occupancyPct == null
                ? '—'
                : '${r.occupancyPct!.toStringAsFixed(1)}%',
          ],
      ],
      summaryLine:
          '${form.code} · ${stayEvents.length} confirmed stay(s) · '
          '$totalGuests guests · $totalNights guest-nights · '
          '$totalRooms rooms · $totalRoomNights room-nights · $scopeLabel',
      gaps: [
        '${form.code} filled from confirmed stays — full official annex cells may still differ.',
        'Room nights / Occ. % are ATMOS aids (rooms × nights ÷ inventory × days).',
        'DOT taxonomy / ET classification / available rooms not fully mapped.',
        'Pending stays are excluded.',
      ],
    );
  }

  return DotReportPreviewTable(
    headers: const ['Status', 'Detail'],
    rows: [
      [
        'Proxy note',
        '${filtered.length} attraction/LGU visit(s) in range — not staff-confirmed AE stays.',
      ],
      [
        'Gap',
        'No confirmed establishment stays in this date range yet.',
      ],
      [
        'Gap',
        'Confirm AE stays on the establishment dashboard to fill this form.',
      ],
    ],
    summaryLine:
        '${form.code} · awaiting confirmed establishment stays · $scopeLabel',
    gaps: [
      '${form.code} needs confirmed establishment stay records.',
      'Do not treat attraction QR counts as hotel occupancy.',
      'Confirm AE QR stays to populate guests / nights / rooms.',
    ],
  );
}

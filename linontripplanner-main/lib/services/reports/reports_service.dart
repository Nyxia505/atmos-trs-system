import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter/material.dart' show DateTimeRange;

import '../../data.dart';
import '../../firestore_loader.dart'
    show
        loadTouristSpotsForMunicipalityFromFirestore,
        municipalityLocationQueryValues;
import '../../hub_spot_transport_fee.dart';
import '../../hub_spot_transport_fees_loader.dart';
import '../../tourist_plan/tourist_travel_estimates.dart'
    show travelMinutesForKm;
import '../../transportation_fee.dart';
import '../../transportation_fees_loader.dart';
import '../../trip_planner_utils.dart' show matchMunicipalityByLocalityHint;
import '../public_firestore_read.dart';
import '../tourism_session.dart' show reloadAdminDashboardCatalogs;
import 'report_check_ins.dart';
import 'report_format.dart';
import 'report_models.dart';

/// Raised when a report cannot be produced. [message] is safe to show verbatim.
class ReportDataException implements Exception {
  final String message;
  const ReportDataException(this.message);

  @override
  String toString() => message;
}

/// Values offered by the filter dropdowns, derived from loaded catalog data.
class ReportFilterOptions {
  final List<String> municipalities;
  final List<String> touristSpots;
  final List<TourismEvent> events;
  final List<String> transportTypes;

  const ReportFilterOptions({
    required this.municipalities,
    required this.touristSpots,
    required this.events,
    required this.transportTypes,
  });
}

/// Builds the Reports page datasets from Firestore.
///
/// All catalog data (spots, LGUs, events, fares) is already held in memory by
/// [reloadAdminDashboardCatalogs]; only `qr_checkins` is read directly here
/// because it is a high-volume collection with no in-memory cache.
class ReportsService {
  ReportsService._();

  /// Cached check-ins, so switching report tabs does not re-read the
  /// collection. Cleared by [build] when `refresh` is set.
  static List<CheckInRecord>? _checkInCache;

  /// Options for the filter row. Reads only in-memory catalogs.
  ///
  /// When [municipality] is set, the tourist-spot dropdown only lists spots
  /// that belong to that LGU via [touristSpotBelongsToMunicipality].
  static ReportFilterOptions filterOptions({String? municipality}) {
    final lgu = _municipalityByName(municipality);
    final spotSource = lgu == null
        ? allSpots
        : allSpots.where((s) => touristSpotBelongsToMunicipality(s, lgu));
    final spotNames = spotSource.map((s) => s.name).toSet().toList()..sort();
    final types = <String>{
      ...transportationFeesByDocId.values.map((f) => f.routeType),
      ...hubSpotTransportFeesByDocId.values.map((f) => f.routeType),
    }..removeWhere((t) => t.trim().isEmpty);
    final sortedTypes = types.toList()..sort();
    final events = List<TourismEvent>.from(tourismEvents)
      ..sort((a, b) => b.dateTime.compareTo(a.dateTime));
    return ReportFilterOptions(
      municipalities: municipalities.map((m) => m.name).toList(),
      touristSpots: spotNames,
      events: events,
      transportTypes: sortedTypes,
    );
  }

  /// Discards the cached check-ins so the next build re-reads Firestore.
  static void invalidateCache() => _checkInCache = null;

  /// Computes [kind] under [filters].
  ///
  /// Set [refresh] to re-read Firestore first — used on export so a downloaded
  /// file reflects the newest data, not what the tab loaded minutes ago.
  static Future<ReportDataset> build({
    required ReportKind kind,
    ReportFilters filters = ReportFilters.none,
    bool refresh = false,
  }) async {
    _validate(filters);

    if (refresh) {
      _checkInCache = null;
      try {
        await reloadAdminDashboardCatalogs();
      } catch (e) {
        debugPrint('ReportsService catalog refresh: $e');
      }
    }

    final now = DateTime.now();
    final scopedSpots = await _loadSpotsForFilters(filters);

    if (kind == ReportKind.matrixFares) {
      return _buildMatrixFares(filters, now, scopedSpots);
    }

    final checkIns = await _loadCheckIns(filters: filters, scopedSpots: scopedSpots);
    final undated = checkIns.where((c) => c.at == null).length;
    final warning = undated > 0
        ? '$undated check-in ${undated == 1 ? 'record' : 'records'} '
              'have no date and are excluded from period breakdowns.'
        : null;

    return switch (kind) {
      ReportKind.touristArrivals => _buildArrivals(
        checkIns,
        filters,
        now,
        warning,
      ),
      ReportKind.spotPerformance => _buildSpotPerformance(
        checkIns,
        filters,
        now,
        warning,
        scopedSpots,
      ),
      ReportKind.eventsAnnouncements => _buildEvents(
        checkIns,
        filters,
        now,
        warning,
      ),
      ReportKind.matrixFares => throw StateError('handled above'),
    };
  }

  static void _validate(ReportFilters filters) {
    if (filters.needsMunicipalitySelection) {
      throw const ReportDataException(
        'Select a municipality / LGU before applying the Single Municipality filter.',
      );
    }
    final range = filters.dateRange;
    if (range == null) return;
    if (range.start.isAfter(range.end)) {
      throw const ReportDataException(
        'The start date is after the end date. Please pick a valid range.',
      );
    }
    if (range.start.isAfter(DateTime.now().add(const Duration(days: 1)))) {
      throw const ReportDataException(
        'The start date is in the future, so there is nothing to report yet.',
      );
    }
  }

  static Municipality? _municipalityByName(String? name) {
    final key = name?.trim().toLowerCase();
    if (key == null || key.isEmpty) return null;
    for (final m in municipalities) {
      if (m.name.toLowerCase() == key || m.shortName.toLowerCase() == key) {
        return m;
      }
    }
    return matchMunicipalityByLocalityHint(name ?? '');
  }

  /// Tourist spots included in this report. Single-municipality scope reads
  /// matching docs from Firestore; overall scope uses the full catalog.
  static Future<List<TouristSpot>> _loadSpotsForFilters(
    ReportFilters filters,
  ) async {
    final lguName = filters.effectiveMunicipality;
    if (lguName == null) {
      return List<TouristSpot>.from(allSpots);
    }
    final municipality = _municipalityByName(lguName);
    if (municipality == null) {
      throw ReportDataException(
        'Unknown municipality "$lguName". Pick an LGU from the list and try again.',
      );
    }
    try {
      final queried =
          await loadTouristSpotsForMunicipalityFromFirestore(municipality);
      if (queried.isNotEmpty) return queried;
      debugPrint(
        'ReportsService: Firestore LGU spot query returned 0 docs for '
        '${municipality.name}; falling back to catalog relationship filter.',
      );
    } catch (e) {
      debugPrint('ReportsService._loadSpotsForFilters: $e');
    }
    // Last resort when field names/values differ from query variants: use the
    // already-loaded catalog relationship, never include other LGUs.
    return allSpots
        .where((s) => touristSpotBelongsToMunicipality(s, municipality))
        .toList();
  }

  static Future<List<CheckInRecord>> _loadCheckIns({
    ReportFilters filters = ReportFilters.none,
    List<TouristSpot> scopedSpots = const [],
  }) async {
    final lgu = filters.effectiveMunicipality;
    // Overall reports can reuse the full-collection cache.
    if (lgu == null) {
      final cached = _checkInCache;
      if (cached != null) return cached;
      try {
        final snap = await fetchPublicFirestoreCollection(kQrCheckInsCollection);
        final records = snap.docs
            .map((d) => CheckInRecord.fromRaw(d.id, d.data()))
            .toList(growable: false);
        _checkInCache = records;
        return records;
      } on FirebaseException catch (e) {
        if (e.code == 'permission-denied') {
          throw const ReportDataException(
            'Your account is not allowed to read check-in records. '
            'Sign in with an administrator account and try again.',
          );
        }
        throw ReportDataException(
          'Could not read check-ins from the database (${e.code}). '
          'Check your connection and try again.',
        );
      } catch (e) {
        debugPrint('ReportsService._loadCheckIns: $e');
        throw const ReportDataException(
          'Could not read check-ins from the database. Please try again.',
        );
      }
    }

    final municipality = _municipalityByName(lgu);
    if (municipality == null) {
      throw ReportDataException(
        'Unknown municipality "$lgu". Pick an LGU from the list and try again.',
      );
    }

    try {
      final byId = <String, CheckInRecord>{};
      final locationValues = municipalityLocationQueryValues(municipality);
      const muniFields = <String>[
        'visitMunicipality',
        'visitedMunicipality',
        'municipalityName',
        'municipality_name',
        'municipality',
        'lgu',
        'LGU',
        'location',
      ];
      for (final field in muniFields) {
        for (final value in locationValues) {
          try {
            final snap = await fetchPublicFirestoreQuery(
              FirebaseFirestore.instance
                  .collection(kQrCheckInsCollection)
                  .where(field, isEqualTo: value),
            );
            for (final doc in snap.docs) {
              byId.putIfAbsent(
                doc.id,
                () => CheckInRecord.fromRaw(doc.id, doc.data()),
              );
            }
          } on FirebaseException catch (e) {
            debugPrint(
              'ReportsService check-in query ($field=$value): ${e.code}',
            );
          }
        }
      }

      // Also pull check-ins that name a spot belonging to this LGU.
      final spotNames = scopedSpots
          .map((s) => s.name.trim())
          .where((n) => n.isNotEmpty)
          .toSet()
          .toList();
      const spotFields = <String>[
        'spotName',
        'spot_name',
        'touristSpot',
        'tourist_spot',
        'spot',
      ];
      for (final field in spotFields) {
        for (var i = 0; i < spotNames.length; i += 10) {
          final chunk = spotNames.sublist(
            i,
            i + 10 > spotNames.length ? spotNames.length : i + 10,
          );
          if (chunk.isEmpty) continue;
          try {
            final snap = await fetchPublicFirestoreQuery(
              FirebaseFirestore.instance
                  .collection(kQrCheckInsCollection)
                  .where(field, whereIn: chunk),
            );
            for (final doc in snap.docs) {
              byId.putIfAbsent(
                doc.id,
                () => CheckInRecord.fromRaw(doc.id, doc.data()),
              );
            }
          } on FirebaseException catch (e) {
            debugPrint(
              'ReportsService check-in spot whereIn ($field): ${e.code}',
            );
          }
        }
      }

      final scopedNames = scopedSpots.map((s) => s.name).toSet();
      return byId.values.where((c) {
        if (c.municipalityName == municipality.name) return true;
        final spot = c.spot;
        if (spot != null && scopedNames.contains(spot.name)) return true;
        if (spot != null &&
            touristSpotBelongsToMunicipality(spot, municipality)) {
          return true;
        }
        return false;
      }).toList(growable: false);
    } on FirebaseException catch (e) {
      if (e.code == 'permission-denied') {
        throw const ReportDataException(
          'Your account is not allowed to read check-in records. '
          'Sign in with an administrator account and try again.',
        );
      }
      throw ReportDataException(
        'Could not read check-ins from the database (${e.code}). '
        'Check your connection and try again.',
      );
    } catch (e) {
      debugPrint('ReportsService._loadCheckIns(scoped): $e');
      throw const ReportDataException(
        'Could not read check-ins from the database. Please try again.',
      );
    }
  }

  // ─── Tourist arrivals ────────────────────────────────────────────────

  static ReportDataset _buildArrivals(
    List<CheckInRecord> all,
    ReportFilters filters,
    DateTime now,
    String? warning,
  ) {
    final lgu = filters.effectiveMunicipality;
    final inLgu = lgu == null
        ? all
        : all.where((c) => c.municipalityName == lgu).toList();
    final scoped = inLgu.where((c) => filters.includesDate(c.at)).toList();

    final range = _effectiveRange(filters, scoped, now);
    final months = _monthSpan(range);
    final counts = List<int>.filled(months.length, 0);
    for (final c in scoped) {
      final at = c.at;
      if (at == null) continue;
      final idx = months.indexWhere(
        (m) => m.$1 == at.year && m.$2 == at.month,
      );
      if (idx >= 0) counts[idx]++;
    }

    final total = scoped.length;
    final uniqueTourists = scoped.map((c) => c.identity).toSet().length;
    final average = months.isEmpty ? 0.0 : total / months.length;

    var highIdx = -1;
    var lowIdx = -1;
    for (var i = 0; i < counts.length; i++) {
      if (highIdx < 0 || counts[i] > counts[highIdx]) highIdx = i;
      if (lowIdx < 0 || counts[i] < counts[lowIdx]) lowIdx = i;
    }

    final previousTotal = _previousPeriodCount(inLgu, range);
    final change = previousTotal == 0
        ? null
        : (total - previousTotal) / previousTotal * 100;

    final perMunicipality = <String, int>{};
    for (final m in municipalities) {
      if (lgu != null && m.name != lgu) continue;
      perMunicipality[m.name] = 0;
    }
    var unassigned = 0;
    for (final c in scoped) {
      if (c.municipalityName.isEmpty) {
        unassigned++;
        continue;
      }
      perMunicipality[c.municipalityName] =
          (perMunicipality[c.municipalityName] ?? 0) + 1;
    }
    final rankedLgus = perMunicipality.entries.toList()
      ..sort((a, b) {
        final byCount = b.value.compareTo(a.value);
        return byCount != 0 ? byCount : a.key.compareTo(b.key);
      });

    final metrics = <ReportMetric>[
      ReportMetric(
        label: 'Total arrivals',
        value: formatCount(total),
        icon: ReportKind.touristArrivals.icon,
        caption: '$uniqueTourists unique ${uniqueTourists == 1 ? 'tourist' : 'tourists'}',
      ),
      ReportMetric(
        label: 'Average monthly arrivals',
        value: formatDecimal(average, decimals: 1),
        icon: ReportKind.touristArrivals.icon,
        caption: 'over ${months.length} ${months.length == 1 ? 'month' : 'months'}',
      ),
      ReportMetric(
        label: 'Highest month',
        value: highIdx < 0 || counts[highIdx] == 0
            ? '—'
            : formatMonthYearShort(months[highIdx].$1, months[highIdx].$2),
        icon: ReportKind.touristArrivals.icon,
        caption: highIdx < 0 || counts[highIdx] == 0
            ? 'no arrivals recorded'
            : '${formatCount(counts[highIdx])} arrivals',
      ),
      ReportMetric(
        label: 'Lowest month',
        value: lowIdx < 0
            ? '—'
            : formatMonthYearShort(months[lowIdx].$1, months[lowIdx].$2),
        icon: ReportKind.touristArrivals.icon,
        caption: lowIdx < 0 ? '—' : '${formatCount(counts[lowIdx])} arrivals',
      ),
      ReportMetric(
        label: 'Change vs previous period',
        value: formatSignedPercent(change),
        icon: ReportKind.touristArrivals.icon,
        caption: previousTotal == 0
            ? 'no arrivals in the prior period'
            : '${formatCount(previousTotal)} previously',
      ),
      ReportMetric(
        label: 'Municipalities with arrivals',
        value: formatCount(
          perMunicipality.values.where((v) => v > 0).length,
        ),
        icon: ReportKind.touristArrivals.icon,
        caption: 'of ${perMunicipality.length} in scope',
      ),
    ];

    final chartLgus = rankedLgus.where((e) => e.value > 0).take(12).toList();

    final charts = <ReportChart>[
      ReportChart(
        title: 'Monthly tourist arrivals',
        type: ReportChartType.line,
        labels: months.map((m) => formatMonthYearShort(m.$1, m.$2)).toList(),
        values: counts.map((c) => c.toDouble()).toList(),
        valueSuffix: 'arrival(s)',
      ),
      ReportChart(
        title: 'Arrivals by municipality',
        type: ReportChartType.bar,
        labels: chartLgus.map((e) => e.key).toList(),
        values: chartLgus.map((e) => e.value.toDouble()).toList(),
        valueSuffix: 'arrival(s)',
      ),
    ];

    final tables = <ReportTable>[
      ReportTable(
        title: 'Monthly arrivals',
        columns: const ['Month', 'Arrivals', 'Share of total'],
        numericColumns: const {1},
        rows: [
          for (var i = 0; i < months.length; i++)
            [
              formatMonthYear(months[i].$1, months[i].$2),
              counts[i].toString(),
              formatShare(counts[i], total),
            ],
        ],
      ),
      ReportTable(
        title: 'Arrivals by municipality',
        columns: const ['Municipality', 'Arrivals', 'Share of total'],
        numericColumns: const {1},
        rows: [
          for (final e in rankedLgus)
            [e.key, e.value.toString(), formatShare(e.value, total)],
          if (unassigned > 0)
            [
              'Unidentified location',
              unassigned.toString(),
              formatShare(unassigned, total),
            ],
        ],
      ),
    ];

    return ReportDataset(
      kind: ReportKind.touristArrivals,
      generatedAt: now,
      filters: filters,
      periodLabel: _rangeLabel(range),
      metrics: metrics,
      charts: charts,
      tables: tables,
      filterSummary: _filterSummary(filters, range),
      warning: warning,
    );
  }

  static int _previousPeriodCount(
    List<CheckInRecord> records,
    DateTimeRange range,
  ) {
    final span = range.end.difference(range.start) + const Duration(days: 1);
    final prevEnd = range.start.subtract(const Duration(days: 1));
    final prevStart = prevEnd.subtract(span - const Duration(days: 1));
    final window = ReportFilters(
      dateRange: DateTimeRange(start: prevStart, end: prevEnd),
    );
    return records.where((c) => window.includesDate(c.at)).length;
  }

  // ─── Spot performance ────────────────────────────────────────────────

  static ReportDataset _buildSpotPerformance(
    List<CheckInRecord> all,
    ReportFilters filters,
    DateTime now,
    String? warning,
    List<TouristSpot> spotsLoadedForScope,
  ) {
    final lgu = filters.effectiveMunicipality;
    final spotFilter = filters.touristSpot;
    final municipality = _municipalityByName(lgu);

    final spotsInScope = spotsLoadedForScope.where((s) {
      if (spotFilter != null && s.name != spotFilter) return false;
      if (municipality != null &&
          !touristSpotBelongsToMunicipality(s, municipality)) {
        // Keep spots that the Firestore LGU query already returned when the
        // embedded municipality.spots list is incomplete.
        final matched = matchMunicipalityByLocalityHint(s.location);
        if (matched?.name != municipality.name) return false;
      }
      return true;
    }).toList();
    final scopedNames = spotsInScope.map((s) => s.name).toSet();

    final scoped = all
        .where(
          (c) =>
              filters.includesDate(c.at) &&
              c.spot != null &&
              scopedNames.contains(c.spot!.name),
        )
        .toList();

    final visits = <String, int>{for (final s in spotsInScope) s.name: 0};
    for (final c in scoped) {
      visits[c.spot!.name] = (visits[c.spot!.name] ?? 0) + 1;
    }

    final rated = spotsInScope.where((s) => s.rating > 0).toList();
    final avgRating = rated.isEmpty
        ? 0.0
        : rated.map((s) => s.rating).reduce((a, b) => a + b) / rated.length;
    final totalRatingCount =
        spotsInScope.fold<int>(0, (total, s) => total + s.ratingCount);

    final ranked = List.of(spotsInScope)
      ..sort((a, b) {
        final byVisits = (visits[b.name] ?? 0).compareTo(visits[a.name] ?? 0);
        if (byVisits != 0) return byVisits;
        final byRating = b.rating.compareTo(a.rating);
        return byRating != 0 ? byRating : a.name.compareTo(b.name);
      });

    final byRating = List.of(rated)
      ..sort((a, b) {
        final byStars = b.rating.compareTo(a.rating);
        return byStars != 0 ? byStars : a.name.compareTo(b.name);
      });

    final distribution = <String, int>{
      '5 stars': 0,
      '4 stars': 0,
      '3 stars': 0,
      '2 stars': 0,
      '1 star': 0,
    };
    for (final s in rated) {
      final band = s.rating.round().clamp(1, 5);
      final key = band == 1 ? '1 star' : '$band stars';
      distribution[key] = (distribution[key] ?? 0) + 1;
    }

    final mostVisited = ranked.isEmpty ? null : ranked.first;
    final mostVisitedCount = mostVisited == null
        ? 0
        : (visits[mostVisited.name] ?? 0);

    final metrics = <ReportMetric>[
      ReportMetric(
        label: 'Total visits / check-ins',
        value: formatCount(scoped.length),
        icon: ReportKind.spotPerformance.icon,
        caption: '${scopedNames.length} ${scopedNames.length == 1 ? 'spot' : 'spots'} in scope',
      ),
      ReportMetric(
        label: 'Average rating',
        value: formatRating(avgRating),
        icon: ReportKind.spotPerformance.icon,
        caption: '${rated.length} rated ${rated.length == 1 ? 'spot' : 'spots'}'
            '${totalRatingCount > 0 ? ' · ${formatCount(totalRatingCount)} ratings' : ''}',
      ),
      ReportMetric(
        label: 'Most visited spot',
        value: mostVisitedCount == 0 ? '—' : mostVisited!.name,
        icon: ReportKind.spotPerformance.icon,
        caption: mostVisitedCount == 0
            ? 'no check-ins in this period'
            : '${formatCount(mostVisitedCount)} check-ins',
      ),
      ReportMetric(
        label: 'Highest-rated spot',
        value: byRating.isEmpty ? '—' : byRating.first.name,
        icon: ReportKind.spotPerformance.icon,
        caption: byRating.isEmpty
            ? 'no ratings yet'
            : '${formatRating(byRating.first.rating)} stars',
      ),
      ReportMetric(
        label: 'Lowest-rated spot',
        value: byRating.isEmpty ? '—' : byRating.last.name,
        icon: ReportKind.spotPerformance.icon,
        caption: byRating.isEmpty
            ? 'no ratings yet'
            : '${formatRating(byRating.last.rating)} stars',
      ),
      ReportMetric(
        label: 'Unique visitors',
        value: formatCount(scoped.map((c) => c.identity).toSet().length),
        icon: ReportKind.spotPerformance.icon,
        caption: 'distinct tourists checked in',
      ),
    ];

    final topVisited = ranked
        .where((s) => (visits[s.name] ?? 0) > 0)
        .take(10)
        .toList();
    final topRated = byRating.take(10).toList();

    final charts = <ReportChart>[
      ReportChart(
        title: 'Visits per tourist spot',
        type: ReportChartType.bar,
        labels: topVisited.map((s) => s.name).toList(),
        values: topVisited.map((s) => (visits[s.name] ?? 0).toDouble()).toList(),
        valueSuffix: 'check-in(s)',
      ),
      ReportChart(
        title: 'Tourist spot ratings',
        type: ReportChartType.bar,
        labels: topRated.map((s) => s.name).toList(),
        values: topRated.map((s) => s.rating).toList(),
        valueSuffix: 'stars',
      ),
      ReportChart(
        title: 'Rating distribution',
        type: ReportChartType.donut,
        labels: distribution.keys.toList(),
        values: distribution.values.map((v) => v.toDouble()).toList(),
        valueSuffix: 'spot(s)',
      ),
    ];

    final tables = <ReportTable>[
      ReportTable(
        title: 'Tourist spot ranking',
        columns: const [
          'Rank',
          'Tourist spot',
          'Municipality',
          'Category',
          'Visits / check-ins',
          'Rating',
          'Number of ratings',
          'Entrance fee',
        ],
        numericColumns: const {0, 4, 6},
        rows: [
          for (var i = 0; i < ranked.length; i++)
            [
              (i + 1).toString(),
              ranked[i].name,
              _municipalityOfSpot(ranked[i]) ?? ranked[i].location,
              ranked[i].type,
              (visits[ranked[i].name] ?? 0).toString(),
              formatRating(ranked[i].rating),
              formatCount(ranked[i].ratingCount),
              ranked[i].entranceFee.trim().isEmpty
                  ? '—'
                  : ranked[i].entranceFee,
            ],
        ],
      ),
      ReportTable(
        title: 'Rating distribution',
        columns: const ['Rating band', 'Tourist spots', 'Share of rated spots'],
        numericColumns: const {1},
        rows: [
          for (final e in distribution.entries)
            [e.key, e.value.toString(), formatShare(e.value, rated.length)],
        ],
      ),
    ];

    return ReportDataset(
      kind: ReportKind.spotPerformance,
      generatedAt: now,
      filters: filters,
      periodLabel: _rangeLabel(_effectiveRange(filters, scoped, now)),
      metrics: metrics,
      charts: charts,
      tables: tables,
      filterSummary: _filterSummary(
        filters,
        _effectiveRange(filters, scoped, now),
      ),
      warning: warning,
    );
  }

  static String? _municipalityOfSpot(TouristSpot spot) {
    for (final m in municipalities) {
      if (touristSpotBelongsToMunicipality(spot, m)) return m.name;
    }
    return matchMunicipalityByLocalityHint(spot.location)?.name;
  }

  // ─── Events & announcements ──────────────────────────────────────────

  static ReportDataset _buildEvents(
    List<CheckInRecord> all,
    ReportFilters filters,
    DateTime now,
    String? warning,
  ) {
    final lgu = filters.effectiveMunicipality;
    final eventId = filters.eventId;

    final events =
        tourismEvents.where((e) {
          if (eventId != null && e.id != eventId) return false;
          if (lgu != null && _municipalityOfEvent(e) != lgu) return false;
          return filters.includesDate(e.dateTime);
        }).toList()
          ..sort((a, b) => b.dateTime.compareTo(a.dateTime));

    final announcements =
        tourismAnnouncements
            .where((a) => filters.includesDate(a.publishedAt))
            .toList()
          ..sort((a, b) => b.publishedAt.compareTo(a.publishedAt));

    final upcoming = events.where((e) => e.dateTime.isAfter(now)).toList();
    final completed = events.where((e) => !e.dateTime.isAfter(now)).toList();

    // No collection links a check-in to an event, so attendance is approximated
    // by check-ins recorded in the event's LGU on the event's calendar day.
    final attendance = <String, int>{};
    for (final e in events) {
      final eventLgu = _municipalityOfEvent(e);
      attendance[e.id] = all.where((c) {
        final at = c.at;
        if (at == null) return false;
        if (at.year != e.dateTime.year ||
            at.month != e.dateTime.month ||
            at.day != e.dateTime.day) {
          return false;
        }
        if (eventLgu == null) return true;
        return c.municipalityName == eventLgu;
      }).length;
    }
    final totalAttendance = attendance.values.fold<int>(0, (a, b) => a + b);

    TourismEvent? mostAttended;
    for (final e in events) {
      if (mostAttended == null ||
          (attendance[e.id] ?? 0) > (attendance[mostAttended.id] ?? 0)) {
        mostAttended = e;
      }
    }
    final mostAttendedCount = mostAttended == null
        ? 0
        : (attendance[mostAttended.id] ?? 0);

    final byType = <String, int>{};
    for (final e in events) {
      final type = e.eventType.trim().isEmpty ? 'General' : e.eventType.trim();
      byType[type] = (byType[type] ?? 0) + 1;
    }
    final rankedTypes = byType.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    final metrics = <ReportMetric>[
      ReportMetric(
        label: 'Total events',
        value: formatCount(events.length),
        icon: ReportKind.eventsAnnouncements.icon,
        caption: '${announcements.length} public ${announcements.length == 1 ? 'announcement' : 'announcements'}',
      ),
      ReportMetric(
        label: 'Upcoming events',
        value: formatCount(upcoming.length),
        icon: ReportKind.eventsAnnouncements.icon,
        caption: 'scheduled after today',
      ),
      ReportMetric(
        label: 'Completed events',
        value: formatCount(completed.length),
        icon: ReportKind.eventsAnnouncements.icon,
        caption: 'already held',
      ),
      ReportMetric(
        label: 'Total check-ins on event days',
        value: formatCount(totalAttendance),
        icon: ReportKind.eventsAnnouncements.icon,
        caption: 'estimated attendance',
      ),
      ReportMetric(
        label: 'Most attended event',
        value: mostAttendedCount == 0 ? '—' : mostAttended!.title,
        icon: ReportKind.eventsAnnouncements.icon,
        caption: mostAttendedCount == 0
            ? 'no check-ins on event days'
            : '${formatCount(mostAttendedCount)} check-ins',
      ),
      ReportMetric(
        label: 'Event categories',
        value: formatCount(byType.length),
        icon: ReportKind.eventsAnnouncements.icon,
        caption: rankedTypes.isEmpty
            ? 'no events in scope'
            : 'most common: ${rankedTypes.first.key}',
      ),
    ];

    final attended =
        events.where((e) => (attendance[e.id] ?? 0) > 0).toList()
          ..sort(
            (a, b) => (attendance[b.id] ?? 0).compareTo(attendance[a.id] ?? 0),
          );
    final topAttended = attended.take(10).toList();

    final charts = <ReportChart>[
      ReportChart(
        title: 'Check-ins on event days',
        type: ReportChartType.bar,
        labels: topAttended.map((e) => e.title).toList(),
        values: topAttended
            .map((e) => (attendance[e.id] ?? 0).toDouble())
            .toList(),
        valueSuffix: 'check-in(s)',
      ),
      ReportChart(
        title: 'Events by status',
        type: ReportChartType.donut,
        labels: const ['Upcoming', 'Completed'],
        values: [upcoming.length.toDouble(), completed.length.toDouble()],
        valueSuffix: 'event(s)',
      ),
      ReportChart(
        title: 'Events by category',
        type: ReportChartType.bar,
        labels: rankedTypes.map((e) => e.key).toList(),
        values: rankedTypes.map((e) => e.value.toDouble()).toList(),
        valueSuffix: 'event(s)',
      ),
    ];

    final tables = <ReportTable>[
      ReportTable(
        title: 'Events',
        columns: const [
          'Event',
          'Category',
          'Municipality',
          'Venue',
          'Date & time',
          'Status',
          'Check-ins that day',
        ],
        numericColumns: const {6},
        rows: [
          for (final e in events)
            [
              e.title,
              e.eventType.trim().isEmpty ? 'General' : e.eventType,
              _municipalityOfEvent(e) ??
                  (e.municipality.trim().isEmpty ? '—' : e.municipality),
              e.venue.trim().isEmpty ? '—' : e.venue,
              formatReportDateTime(e.dateTime),
              e.dateTime.isAfter(now) ? 'Upcoming' : 'Completed',
              (attendance[e.id] ?? 0).toString(),
            ],
        ],
      ),
      ReportTable(
        title: 'Public announcements',
        columns: const ['Announcement', 'Published', 'Details'],
        rows: [
          for (final a in announcements)
            [
              a.title,
              formatReportDateTime(a.publishedAt),
              _excerpt(a.body),
            ],
        ],
      ),
    ];

    final range = _effectiveRangeFromDates(
      filters,
      events.map((e) => e.dateTime).followedBy(
        announcements.map((a) => a.publishedAt),
      ),
      now,
    );

    // Announcements carry no LGU field, so a municipality scope cannot narrow
    // them; say so rather than implying the list is LGU-specific.
    final notes = <String>[
      ?warning,
      if (lgu != null && announcements.isNotEmpty)
        'Public announcements are province-wide and are not narrowed by '
            'municipality.',
    ];

    return ReportDataset(
      kind: ReportKind.eventsAnnouncements,
      generatedAt: now,
      filters: filters,
      periodLabel: _rangeLabel(range),
      metrics: metrics,
      charts: charts,
      tables: tables,
      filterSummary: _filterSummary(
        filters,
        range,
        eventTitle: eventId == null ? null : _eventTitle(eventId),
      ),
      warning: notes.isEmpty ? null : notes.join(' '),
    );
  }

  static String? _eventTitle(String eventId) {
    for (final e in tourismEvents) {
      if (e.id == eventId) return e.title;
    }
    return null;
  }

  static String? _municipalityOfEvent(TourismEvent e) {
    final direct = matchMunicipalityByLocalityHint(e.municipality);
    if (direct != null) return direct.name;
    return matchMunicipalityByLocalityHint(e.venue)?.name;
  }

  static String _excerpt(String body) {
    final clean = body.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (clean.isEmpty) return '—';
    return clean.length <= 160 ? clean : '${clean.substring(0, 157)}…';
  }

  // ─── Matrix fares ────────────────────────────────────────────────────

  static ReportDataset _buildMatrixFares(
    ReportFilters filters,
    DateTime now,
    List<TouristSpot> scopedSpots,
  ) {
    final rows = <_FareRow>[
      ...transportationFeesByDocId.values.map(_interLguRow),
      ...hubSpotTransportFeesByDocId.values.map(_hubSpotRow),
    ];

    final lgu = filters.effectiveMunicipality;
    final spot = filters.touristSpot;
    final type = filters.transportType;
    final scopedSpotNames = scopedSpots.map((s) => s.name).toSet();

    final scoped = rows.where((r) {
      if (lgu != null && r.municipality != lgu && r.relatedMunicipality != lgu) {
        return false;
      }
      if (spot != null && r.touristSpot != spot) return false;
      if (type != null && r.transportType != type) return false;
      // When scoped to one LGU, hub↔spot legs must name a spot in that LGU.
      if (lgu != null &&
          r.touristSpot != null &&
          !scopedSpotNames.contains(r.touristSpot)) {
        return false;
      }
      return true;
    }).toList()..sort((a, b) {
      final byLgu = a.municipality.compareTo(b.municipality);
      if (byLgu != 0) return byLgu;
      final byType = a.transportType.compareTo(b.transportType);
      return byType != 0 ? byType : a.destination.compareTo(b.destination);
    });

    final fares = scoped.map((r) => r.fare).where((f) => f > 0).toList();
    final avg = fares.isEmpty
        ? 0.0
        : fares.reduce((a, b) => a + b) / fares.length;
    final lowest = fares.isEmpty ? null : fares.reduce((a, b) => a < b ? a : b);
    final highest = fares.isEmpty ? null : fares.reduce((a, b) => a > b ? a : b);

    final byMunicipality = <String, List<int>>{};
    final byType = <String, List<int>>{};
    for (final r in scoped) {
      if (r.fare <= 0) continue;
      byMunicipality.putIfAbsent(r.municipality, () => []).add(r.fare);
      byType.putIfAbsent(r.transportType, () => []).add(r.fare);
    }

    double mean(List<int> v) =>
        v.isEmpty ? 0 : v.reduce((a, b) => a + b) / v.length;

    final rankedLgus = byMunicipality.entries.toList()
      ..sort((a, b) => mean(b.value).compareTo(mean(a.value)));
    final rankedTypes = byType.entries.toList()
      ..sort((a, b) => b.value.length.compareTo(a.value.length));

    final cheapest = scoped.where((r) => r.fare > 0).toList()
      ..sort((a, b) => a.fare.compareTo(b.fare));

    final metrics = <ReportMetric>[
      ReportMetric(
        label: 'Average fare',
        value: fares.isEmpty ? '—' : formatPesoDecimal(avg),
        icon: ReportKind.matrixFares.icon,
        caption: '${formatCount(scoped.length)} ${scoped.length == 1 ? 'route' : 'routes'}',
      ),
      ReportMetric(
        label: 'Lowest fare',
        value: lowest == null ? '—' : formatPeso(lowest),
        icon: ReportKind.matrixFares.icon,
        caption: cheapest.isEmpty
            ? 'no fares in scope'
            : '${cheapest.first.startingPoint} → ${cheapest.first.destination}',
      ),
      ReportMetric(
        label: 'Highest fare',
        value: highest == null ? '—' : formatPeso(highest),
        icon: ReportKind.matrixFares.icon,
        caption: cheapest.isEmpty
            ? 'no fares in scope'
            : '${cheapest.last.startingPoint} → ${cheapest.last.destination}',
      ),
      ReportMetric(
        label: 'Transportation types',
        value: formatCount(byType.length),
        icon: ReportKind.matrixFares.icon,
        caption: rankedTypes.isEmpty
            ? 'no routes in scope'
            : 'most routes: ${formatTransportType(rankedTypes.first.key)}',
      ),
      ReportMetric(
        label: 'Municipalities covered',
        value: formatCount(byMunicipality.length),
        icon: ReportKind.matrixFares.icon,
        caption: 'with at least one fare',
      ),
      ReportMetric(
        label: 'Hub ↔ spot legs',
        value: formatCount(scoped.where((r) => r.touristSpot != null).length),
        icon: ReportKind.matrixFares.icon,
        caption: 'of ${formatCount(scoped.length)} total routes',
      ),
    ];

    final chartLgus = rankedLgus.take(12).toList();

    final charts = <ReportChart>[
      ReportChart(
        title: 'Routes by transportation type',
        type: ReportChartType.donut,
        labels: rankedTypes.map((e) => formatTransportType(e.key)).toList(),
        values: rankedTypes.map((e) => e.value.length.toDouble()).toList(),
        valueSuffix: 'route(s)',
      ),
      ReportChart(
        title: 'Average fare by transportation type',
        type: ReportChartType.bar,
        labels: rankedTypes.map((e) => formatTransportType(e.key)).toList(),
        values: rankedTypes.map((e) => mean(e.value)).toList(),
        valueSuffix: 'PHP',
      ),
      ReportChart(
        title: 'Average fare by municipality',
        type: ReportChartType.bar,
        labels: chartLgus.map((e) => e.key).toList(),
        values: chartLgus.map((e) => mean(e.value)).toList(),
        valueSuffix: 'PHP',
      ),
    ];

    final tables = <ReportTable>[
      ReportTable(
        title: 'Fare matrix',
        columns: const [
          'Municipality',
          'Starting point',
          'Destination / tourist spot',
          'Transportation type',
          'Fare',
          'Distance',
          'Estimated travel time',
        ],
        rows: [
          for (final r in scoped)
            [
              r.municipality,
              r.startingPoint,
              r.destination,
              formatTransportType(r.transportType),
              r.fareLabel,
              formatDistanceKm(r.distanceKm),
              formatTravelMinutes(r.travelMinutes),
            ],
        ],
      ),
      ReportTable(
        title: 'Fare by municipality',
        columns: const ['Municipality', 'Routes', 'Average fare', 'Lowest', 'Highest'],
        numericColumns: const {1},
        rows: [
          for (final e in rankedLgus)
            [
              e.key,
              e.value.length.toString(),
              formatPesoDecimal(mean(e.value)),
              formatPeso(e.value.reduce((a, b) => a < b ? a : b)),
              formatPeso(e.value.reduce((a, b) => a > b ? a : b)),
            ],
        ],
      ),
      ReportTable(
        title: 'Fare by transportation type',
        columns: const ['Transportation type', 'Routes', 'Average fare', 'Lowest', 'Highest'],
        numericColumns: const {1},
        rows: [
          for (final e in rankedTypes)
            [
              formatTransportType(e.key),
              e.value.length.toString(),
              formatPesoDecimal(mean(e.value)),
              formatPeso(e.value.reduce((a, b) => a < b ? a : b)),
              formatPeso(e.value.reduce((a, b) => a > b ? a : b)),
            ],
        ],
      ),
    ];

    return ReportDataset(
      kind: ReportKind.matrixFares,
      generatedAt: now,
      filters: filters,
      periodLabel: 'All published fares',
      metrics: metrics,
      charts: charts,
      tables: tables,
      filterSummary: _filterSummary(filters, null),
      warning: rows.isEmpty
          ? 'No fare records are loaded yet. Open the Matrix Fares tab to '
                'seed or refresh the fare matrix.'
          : null,
    );
  }

  static _FareRow _interLguRow(TransportationFee f) {
    final origin = municipalities.firstWhereOrNullByName(f.fromMunicipality);
    final start = origin?.busTerminal?.name;
    final km = f.estimatedDistance > 0 ? f.estimatedDistance : null;
    return _FareRow(
      municipality: f.fromMunicipality.isEmpty ? '—' : f.fromMunicipality,
      relatedMunicipality: f.toMunicipality,
      startingPoint: (start == null || start.trim().isEmpty)
          ? '${f.fromMunicipality} terminal'
          : start,
      destination: f.endpointName.trim().isEmpty
          ? f.toMunicipality
          : '${f.endpointName} (${f.toMunicipality})',
      transportType: f.routeType,
      fare: f.fare,
      fareLabel: formatPeso(f.fare),
      distanceKm: km,
      travelMinutes: km == null
          ? null
          : travelMinutesForKm(km, 'Public Transport'),
      touristSpot: null,
    );
  }

  static _FareRow _hubSpotRow(HubSpotTransportFee f) {
    final hub = f.fromEndpointName.trim().isEmpty
        ? '${f.municipality} terminal'
        : f.fromEndpointName;
    final spot = f.toTouristSpotName.trim().isEmpty
        ? '—'
        : f.toTouristSpotName;
    final spotToHub = f.direction == HubSpotLegDirection.spotToHub;
    final label = f.fareMin > 0 && f.fareMax > f.fareMin
        ? 'PHP ${formatCount(f.fareMin)}–${formatCount(f.fareMax)}'
        : formatPeso(f.fare);
    return _FareRow(
      municipality: f.municipality.isEmpty ? '—' : f.municipality,
      relatedMunicipality: f.municipality,
      startingPoint: spotToHub ? spot : hub,
      destination: spotToHub ? hub : spot,
      transportType: f.routeType,
      fare: f.fare,
      fareLabel: label,
      // Hub ↔ spot legs carry no distance in Firestore, so travel time cannot
      // be derived for them.
      distanceKm: null,
      travelMinutes: null,
      touristSpot: f.toTouristSpotName.trim().isEmpty
          ? null
          : f.toTouristSpotName,
    );
  }

  // ─── Shared ──────────────────────────────────────────────────────────

  static DateTimeRange _effectiveRange(
    ReportFilters filters,
    List<CheckInRecord> scoped,
    DateTime now,
  ) => _effectiveRangeFromDates(
    filters,
    scoped.map((c) => c.at).whereType<DateTime>(),
    now,
  );

  /// The period the report actually covers: the chosen filter when set,
  /// otherwise the span of the data, otherwise the current year.
  static DateTimeRange _effectiveRangeFromDates(
    ReportFilters filters,
    Iterable<DateTime> dates,
    DateTime now,
  ) {
    final chosen = filters.dateRange;
    if (chosen != null) return chosen;
    DateTime? min;
    DateTime? max;
    for (final d in dates) {
      if (min == null || d.isBefore(min)) min = d;
      if (max == null || d.isAfter(max)) max = d;
    }
    if (min == null || max == null) {
      return DateTimeRange(
        start: DateTime(now.year, 1, 1),
        end: DateTime(now.year, 12, 31),
      );
    }
    return DateTimeRange(start: min, end: max);
  }

  /// Year/month pairs spanning [range], capped so a very wide range cannot
  /// produce an unreadable chart.
  static List<(int, int)> _monthSpan(DateTimeRange range) {
    final out = <(int, int)>[];
    var year = range.start.year;
    var month = range.start.month;
    while (year < range.end.year ||
        (year == range.end.year && month <= range.end.month)) {
      out.add((year, month));
      if (out.length >= 120) break;
      month++;
      if (month > 12) {
        month = 1;
        year++;
      }
    }
    return out.isEmpty ? [(range.start.year, range.start.month)] : out;
  }

  static String _rangeLabel(DateTimeRange range) {
    final sameMonth =
        range.start.year == range.end.year &&
        range.start.month == range.end.month;
    if (sameMonth) return formatMonthYear(range.start.year, range.start.month);
    return '${formatMonthYear(range.start.year, range.start.month)} – '
        '${formatMonthYear(range.end.year, range.end.month)}';
  }

  static List<(String, String)> _filterSummary(
    ReportFilters filters,
    DateTimeRange? range, {
    String? eventTitle,
  }) {
    // Scope leads, so every preview and export states up front whether the
    // figures are province-wide or for one LGU.
    final out = <(String, String)>[('Scope', filters.scopeLabel)];
    final chosen = filters.dateRange;
    if (chosen != null) {
      out.add((
        'Date range',
        '${formatReportDate(chosen.start)} – ${formatReportDate(chosen.end)}',
      ));
    } else if (range != null) {
      out.add(('Period', _rangeLabel(range)));
    }
    final s = filters.touristSpot;
    if (s != null) out.add(('Tourist spot', s));
    if (eventTitle != null) out.add(('Event', eventTitle));
    final t = filters.transportType;
    if (t != null) out.add(('Transportation type', formatTransportType(t)));
    return out;
  }
}

/// One row of the unified fare matrix, covering both inter-LGU routes and
/// hub ↔ tourist-spot legs.
class _FareRow {
  final String municipality;

  /// The other LGU on the route, so a municipality filter matches either end.
  final String relatedMunicipality;
  final String startingPoint;
  final String destination;
  final String transportType;
  final int fare;
  final String fareLabel;
  final double? distanceKm;
  final int? travelMinutes;
  final String? touristSpot;

  const _FareRow({
    required this.municipality,
    required this.relatedMunicipality,
    required this.startingPoint,
    required this.destination,
    required this.transportType,
    required this.fare,
    required this.fareLabel,
    required this.distanceKm,
    required this.travelMinutes,
    required this.touristSpot,
  });
}

extension _MunicipalityLookup on List<Municipality> {
  Municipality? firstWhereOrNullByName(String name) {
    final lower = name.trim().toLowerCase();
    if (lower.isEmpty) return null;
    for (final m in this) {
      if (m.name.toLowerCase() == lower) return m;
    }
    return null;
  }
}

import 'dart:async';
import 'dart:math' as math;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import 'data.dart';
import 'services/admin_live_collections.dart';
import 'services/saved_trip_store.dart';
import 'theme/tourism_app_theme.dart';
import 'utils/trip_planner_analytics.dart';
import 'widgets/municipality_image.dart';
import 'widgets/optaca_portal_ui.dart';
import 'widgets/reports/trip_analytics_period_pickers.dart';

/// Read-only OPTACA view of saved Plan-my-trip itineraries.
///
/// These figures are planned trips, not confirmed arrivals.
class TripPlannerAnalyticsTab extends StatefulWidget {
  const TripPlannerAnalyticsTab({super.key});

  @override
  State<TripPlannerAnalyticsTab> createState() =>
      _TripPlannerAnalyticsTabState();
}

class _TripPlannerAnalyticsTabState extends State<TripPlannerAnalyticsTab> {
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _sub;
  List<AnalyticTripPlan> _plans = const [];
  bool _loading = true;
  Object? _error;
  int _seq = 0;

  TripTrendGrain _grain = TripTrendGrain.monthly;
  TripTrendWindow _window = TripTrendWindow.current(TripTrendGrain.monthly);

  @override
  void initState() {
    super.initState();
    _listen();
  }

  void _listen() {
    _sub?.cancel();
    _sub = FirebaseFirestore.instance
        .collection(kTouristTripCollection)
        .snapshots()
        .listen(_onSnapshot, onError: _onError);
  }

  void _retry() {
    if (!mounted) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    _listen();
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  void _onSnapshot(QuerySnapshot<Map<String, dynamic>> snap) {
    final seq = ++_seq;
    final seen = <String>{};
    final plans = <AnalyticTripPlan>[];
    for (final doc in snap.docs) {
      final raw = doc.data();
      final id = (raw['id']?.toString() ?? doc.id).trim();
      if (id.isEmpty || !seen.add(id)) continue;
      final json = _normalizeTrip(raw, id);
      plans.add(
        AnalyticTripPlan(
          plan: SavedTripPlan.fromJson(json),
          savedAt: _parseSavedAt(raw['createdAt'] ?? json['createdAt']),
        ),
      );
    }
    if (!mounted || seq != _seq) return;
    _plans = plans;
    _loading = false;
    _error = null;
    if (!optacaTabIsActive(context)) return;
    setState(() {});
  }

  void _onError(Object error) {
    debugPrint('TripPlannerAnalyticsTab: $error');
    if (!mounted) return;
    _loading = false;
    _error = error;
    if (!optacaTabIsActive(context)) return;
    setState(() {});
  }

  Future<void> _onGrainPressed(TripTrendGrain grain) async {
    final picked = await pickTripAnalyticsPeriod(
      context: context,
      grain: grain,
      current: _window,
    );
    if (!mounted) return;
    if (picked != null) {
      setState(() {
        _grain = grain;
        _window = picked;
      });
      return;
    }
    if (grain == _grain) return;
    setState(() {
      _grain = grain;
      _window = _window.withGrain(grain);
    });
  }

  Widget _grainChip(TripTrendGrain grain, String label) {
    final selected = _grain == grain;
    return Material(
      color: selected ? OptacaAdminTheme.primary : Colors.white,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: () => _onGrainPressed(grain),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: selected
                  ? OptacaAdminTheme.primary
                  : OptacaAdminTheme.border,
            ),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w800,
              color: selected ? Colors.white : OptacaAdminTheme.text,
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading && _plans.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null && _plans.isEmpty) {
      return OptacaLoadError(
        title: 'Trip plans could not be read with this account.',
        message:
            'OPTACA admins can read saved itineraries for analytics. '
            'Tourists can still open only their own plans, and the '
            'collection is not public. Retry after the updated access '
            'rules are deployed.',
        onRetry: _retry,
      );
    }
    if (_plans.isEmpty) {
      return const _Message(
        title: 'No saved trip plans yet.',
        body:
            'When tourists finish a plan, the totals here update from '
            'those records. Nothing is shown until a plan is saved.',
      );
    }

    final stats = TripPlannerAnalyticsSnapshot.compute(
      plans: _plans,
      window: _window,
    );

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
      children: [
        const _AnalyticsPageHeader(),
        const SizedBox(height: 14),
        _summary(stats),
        if (stats.skippedMissingTimestamp > 0) ...[
          const SizedBox(height: 10),
          Text(
            '${stats.skippedMissingTimestamp} '
            '${stats.skippedMissingTimestamp == 1 ? 'plan has' : 'plans have'} '
            'no saved date and ${stats.skippedMissingTimestamp == 1 ? 'is' : 'are'} '
            'omitted from this period.',
            style: const TextStyle(color: AppColors.textGrey, fontSize: 12),
          ),
        ],
        const SizedBox(height: 14),
        _trends(stats),
        const SizedBox(height: 14),
        _twoColumn(
          _rankedCard(
            title: 'Popular Tourist Destinations',
            icon: Icons.place_rounded,
            rows: stats.destinations,
            totalPlans: stats.planCount,
            kind: _RankThumbKind.destination,
          ),
          _rankedCard(
            title: 'Municipality Analytics',
            icon: Icons.apartment_rounded,
            rows: stats.municipalityRanks,
            totalPlans: stats.planCount,
            kind: _RankThumbKind.municipality,
          ),
        ),
        const SizedBox(height: 14),
        _twoColumn(_durationCard(stats), _routesCard(stats)),
      ],
    );
  }

  Widget _summary(TripPlannerAnalyticsSnapshot stats) {
    final cards = [
      _StatCard(
        icon: Icons.map_outlined,
        label: 'Total trip plans',
        value: '${stats.planCount}',
      ),
      _StatCard(
        icon: Icons.place_outlined,
        label: 'Total planned destinations',
        value: '${stats.distinctDestinations}',
      ),
      _StatCard(
        icon: Icons.access_time_rounded,
        label: 'Average travel duration',
        value: stats.averageDays == null
            ? '—'
            : '${stats.averageDays!.toStringAsFixed(1)} days',
      ),
      _StatCard(
        icon: Icons.location_city_outlined,
        label: 'Municipalities covered',
        value: '${stats.distinctMunicipalities}',
      ),
    ];
    return LayoutBuilder(
      builder: (context, c) {
        final cols = c.maxWidth >= 1000 ? 4 : (c.maxWidth >= 640 ? 2 : 1);
        if (cols == 1) {
          return Column(
            children: [
              for (var i = 0; i < cards.length; i++) ...[
                if (i > 0) const SizedBox(height: 12),
                cards[i],
              ],
            ],
          );
        }
        return Column(
          children: [
            for (var i = 0; i < cards.length; i += cols) ...[
              if (i > 0) const SizedBox(height: 12),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (var j = 0; j < cols; j++) ...[
                    if (j > 0) const SizedBox(width: 12),
                    Expanded(
                      child: i + j < cards.length
                          ? cards[i + j]
                          : const SizedBox.shrink(),
                    ),
                  ],
                ],
              ),
            ],
          ],
        );
      },
    );
  }

  Widget _trends(TripPlannerAnalyticsSnapshot stats) {
    const lineColor = Color(0xFFFF7900);
    const fillColor = Color(0xFFFFE2C7);
    const axisText = Color(0xFF1F2937);

    final series = stats.series;
    final maxCount = series.fold<int>(0, (m, p) => math.max(m, p.count));
    final maxY = math.max(1, maxCount + (maxCount < 6 ? 1 : 0)).toDouble();
    final yInterval = math.max(1, (maxY / 4).ceil()).toDouble();
    final showEveryX = series.length <= 12
        ? 1
        : series.length <= 16
            ? 2
            : series.length <= 31
                ? 5
                : 30;
    final peak = peakSeriesIndex(series);

    return _sectionCard(
      icon: Icons.insights_rounded,
      title: 'Trip Planner Trends',
      trailing: Wrap(
        spacing: 6,
        runSpacing: 6,
        children: [
          _grainChip(TripTrendGrain.daily, 'Daily'),
          _grainChip(TripTrendGrain.weekly, 'Weekly'),
          _grainChip(TripTrendGrain.monthly, 'Monthly'),
          _grainChip(TripTrendGrain.yearly, 'Yearly'),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Column(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  IconButton(
                    tooltip: 'Previous period',
                    visualDensity: VisualDensity.compact,
                    onPressed: () => setState(() {
                      _window = _window.previous();
                    }),
                    icon: const Icon(Icons.chevron_left_rounded),
                  ),
                  InkWell(
                    onTap: () => _onGrainPressed(_grain),
                    borderRadius: BorderRadius.circular(8),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 4,
                      ),
                      child: Text(
                        _window.label,
                        style: const TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 14,
                          color: axisText,
                        ),
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Next period',
                    visualDensity: VisualDensity.compact,
                    onPressed: _window.canGoNext
                        ? () => setState(() {
                              _window = _window.next();
                            })
                        : null,
                    icon: const Icon(Icons.chevron_right_rounded),
                  ),
                ],
              ),
              if (_window.preset == TripDatePreset.custom)
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Text(
                    '${_window.selectedDayCount} '
                    '${_window.selectedDayCount == 1 ? 'day' : 'days'}',
                    style: const TextStyle(
                      color: AppColors.textGrey,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              if (peak != null)
                Align(
                  alignment: Alignment.centerLeft,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 5,
                    ),
                    decoration: BoxDecoration(
                      color: fillColor,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.trending_up_rounded,
                          size: 14,
                          color: lineColor,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          'Peak: ${series[peak].count} trip '
                          '${series[peak].count == 1 ? 'plan' : 'plans'}',
                          style: const TextStyle(
                            color: lineColor,
                            fontWeight: FontWeight.w800,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          if (series.isEmpty)
            const Text(
              'No saved dates in this selection.',
              style: TextStyle(color: AppColors.textGrey),
            )
          else
            _TripTrendLineChart(
              key: ValueKey(
                '${_window.start.toIso8601String()}-'
                '${_window.end.toIso8601String()}-${_grain.name}',
              ),
              series: series,
              peakIndex: peak,
              maxY: maxY,
              yInterval: yInterval,
              showEveryX: showEveryX,
            ),
        ],
      ),
    );
  }

  Widget _durationCard(TripPlannerAnalyticsSnapshot stats) {
    final rows = stats.durations.where((row) => row.count > 0).toList();
    final total = rows.fold<int>(0, (acc, row) => acc + row.count);
    return _sectionCard(
      icon: Icons.access_time_rounded,
      title: 'Travel Duration',
      clipArt: true,
      child: rows.isEmpty
          ? const Text(
              'No itineraries in this selection have a travel-day count.',
              style: TextStyle(color: AppColors.textGrey),
            )
          : LayoutBuilder(
              builder: (context, c) {
                final pie = SizedBox(
                  width: 168,
                  height: 168,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      PieChart(
                        PieChartData(
                          sectionsSpace: 2,
                          centerSpaceRadius: 46,
                          sections: [
                            for (var i = 0; i < rows.length; i++)
                              PieChartSectionData(
                                color: _sliceColors[i % _sliceColors.length],
                                value: rows[i].count.toDouble(),
                                title: '',
                                radius: 28,
                                showTitle: false,
                              ),
                          ],
                        ),
                      ),
                      Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            '$total',
                            style: const TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.w900,
                              color: OptacaAdminTheme.text,
                            ),
                          ),
                          Text(
                            total == 1 ? 'trip plan' : 'trip plans',
                            style: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: OptacaAdminTheme.textMuted,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                );
                final legend = Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (var i = 0; i < rows.length; i++)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Row(
                          children: [
                            Container(
                              width: 10,
                              height: 10,
                              decoration: BoxDecoration(
                                color: _sliceColors[i % _sliceColors.length],
                                shape: BoxShape.circle,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                '${rows[i].label}: ${rows[i].count} '
                                '(${total == 0 ? 0 : (rows[i].count / total * 100).round()}%)',
                                style: const TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                );
                if (c.maxWidth < 420) {
                  return Column(
                    children: [pie, const SizedBox(height: 12), legend],
                  );
                }
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    pie,
                    const SizedBox(width: 16),
                    Expanded(child: legend),
                  ],
                );
              },
            ),
    );
  }

  Widget _routesCard(TripPlannerAnalyticsSnapshot stats) {
    return _sectionCard(
      icon: Icons.alt_route_rounded,
      title: 'Route Analytics',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          LayoutBuilder(
            builder: (context, c) {
              final starts = _routeEndpointBlock(
                title: 'Starting Municipalities',
                icon: Icons.play_arrow_rounded,
                iconColor: const Color(0xFF16A34A),
                rows: stats.starts,
              );
              final ends = _routeEndpointBlock(
                title: 'Ending Municipalities',
                icon: Icons.flag_rounded,
                iconColor: const Color(0xFFDC2626),
                rows: stats.ends,
              );
              if (c.maxWidth < 480) {
                return Column(
                  children: [starts, const SizedBox(height: 12), ends],
                );
              }
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: starts),
                  const SizedBox(width: 16),
                  Expanded(child: ends),
                ],
              );
            },
          ),
          if (stats.routes.isNotEmpty) ...[
            const SizedBox(height: 12),
            const Text(
              'Municipality routes',
              style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13),
            ),
            const SizedBox(height: 6),
            _miniList(stats.routes),
          ],
        ],
      ),
    );
  }

  Widget _routeEndpointBlock({
    required String title,
    required IconData icon,
    required Color iconColor,
    required List<TripRankRow> rows,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, size: 18, color: iconColor),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                title,
                style: const TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 13,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        _miniList(rows),
      ],
    );
  }

  Widget _miniList(List<TripRankRow> rows) {
    if (rows.isEmpty) {
      return const Text(
        'None recorded.',
        style: TextStyle(color: AppColors.textGrey),
      );
    }
    return Column(
      children: [
        for (final row in rows.take(5))
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    row.label,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
                Text(
                  '${row.count}',
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _rankedCard({
    required String title,
    required IconData icon,
    required List<TripRankRow> rows,
    required int totalPlans,
    required _RankThumbKind kind,
  }) {
    return _sectionCard(
      icon: icon,
      title: title,
      child: rows.isEmpty
          ? const Text(
              'Nothing to rank in this selection.',
              style: TextStyle(color: AppColors.textGrey),
            )
          : Builder(
              builder: (context) {
                final top = rows.take(10).toList(growable: false);
                return Column(
                  children: [
                    for (var i = 0; i < top.length; i++) ...[
                      if (i > 0) const SizedBox(height: 10),
                      _RankRowTile(
                        rank: i + 1,
                        row: top[i],
                        totalPlans: totalPlans,
                        kind: kind,
                      ),
                    ],
                  ],
                );
              },
            ),
    );
  }

  Widget _twoColumn(Widget left, Widget right) {
    return LayoutBuilder(
      builder: (context, c) {
        if (c.maxWidth < 900) {
          return Column(
            children: [left, const SizedBox(height: 14), right],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: left),
            const SizedBox(width: 14),
            Expanded(child: right),
          ],
        );
      },
    );
  }

  Widget _sectionCard({
    required IconData icon,
    required String title,
    required Widget child,
    Widget? trailing,
    bool clipArt = false,
  }) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: OptacaAdminTheme.border),
        boxShadow: OptacaAdminTheme.cardShadow,
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Stack(
          children: [
            if (clipArt)
              const Positioned(
                right: 0,
                bottom: 0,
                width: 120,
                height: 72,
                child: IgnorePointer(
                  child: CustomPaint(painter: _CardWavePainter()),
                ),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: 32,
                        height: 32,
                        decoration: BoxDecoration(
                          color: OptacaAdminTheme.lightOrange,
                          borderRadius: BorderRadius.circular(9),
                        ),
                        child: Icon(
                          icon,
                          color: OptacaAdminTheme.primary,
                          size: 18,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.only(top: 5),
                          child: Text(
                            title,
                            style: const TextStyle(
                              fontSize: 15.5,
                              fontWeight: FontWeight.w800,
                              color: OptacaAdminTheme.text,
                            ),
                          ),
                        ),
                      ),
                      if (trailing != null) Flexible(child: trailing),
                    ],
                  ),
                  const SizedBox(height: 12),
                  child,
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

enum _RankThumbKind { destination, municipality }

class _RankRowTile extends StatelessWidget {
  const _RankRowTile({
    required this.rank,
    required this.row,
    required this.totalPlans,
    required this.kind,
  });

  final int rank;
  final TripRankRow row;
  final int totalPlans;
  final _RankThumbKind kind;

  TouristSpot? get _spot {
    for (final spot in allSpots) {
      final docId = (spot.firestoreDocId ?? '').trim();
      if (docId.isNotEmpty && docId == row.id) return spot;
    }
    return findTouristSpotByNameFuzzy(row.label);
  }

  Municipality? get _municipality {
    bool matches(Municipality m, String raw) {
      final value = raw.trim();
      if (value.isEmpty) return false;
      if (m.name == value || m.shortName == value) return true;
      final lower = value.toLowerCase();
      if (m.name.toLowerCase() == lower || m.shortName.toLowerCase() == lower) {
        return true;
      }
      return normalizeTourismNameKey(m.name) == value ||
          normalizeTourismNameKey(m.shortName) == value;
    }

    for (final m in municipalities) {
      if (matches(m, row.label) || matches(m, row.id)) return m;
    }
    final resolved =
        resolveMunicipality(row.label) ?? resolveMunicipality(row.id);
    if (resolved == null) return null;
    for (final m in municipalities) {
      if (matches(m, resolved.label) ||
          normalizeTourismNameKey(m.name) == resolved.id) {
        return m;
      }
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final pct = row.percentOf(totalPlans);
    final bar = row.barOf(totalPlans);
    final title = kind == _RankThumbKind.destination && row.detail.isNotEmpty
        ? '${row.label} - ${row.detail}'
        : row.label;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        SizedBox(
          width: 18,
          child: Text(
            '$rank',
            style: const TextStyle(
              fontWeight: FontWeight.w800,
              fontSize: 13,
              color: OptacaAdminTheme.textMuted,
            ),
          ),
        ),
        const SizedBox(width: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: SizedBox(
            width: 42,
            height: 42,
            child: kind == _RankThumbKind.destination
                ? _destinationThumb()
                : _municipalityThumb(),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          flex: 5,
          child: Text(
            title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              height: 1.2,
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          flex: 4,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: bar,
              minHeight: 8,
              backgroundColor: const Color(0xFFFFEDD5),
              color: OptacaAdminTheme.primary,
            ),
          ),
        ),
        const SizedBox(width: 10),
        SizedBox(
          width: 92,
          child: Text(
            '${row.count} ${row.count == 1 ? 'plan' : 'plans'} ($pct%)',
            textAlign: TextAlign.right,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
      ],
    );
  }

  Widget _destinationThumb() {
    final spot = _spot;
    final fallback = ColoredBox(
      color: OptacaAdminTheme.lightOrange,
      child: const Icon(
        Icons.place_rounded,
        color: OptacaAdminTheme.primary,
        size: 20,
      ),
    );
    if (spot == null) return fallback;
    return buildTouristSpotProfileImage(
      spot,
      fallback: fallback,
      memCacheWidth: 96,
      memCacheHeight: 96,
    );
  }

  Widget _municipalityThumb() {
    final municipality = _municipality;
    final fallback = ColoredBox(
      color: OptacaAdminTheme.lightOrange,
      child: const Icon(
        Icons.location_city_rounded,
        color: OptacaAdminTheme.primary,
        size: 20,
      ),
    );
    if (municipality == null) return fallback;
    return buildMunicipalityImageForMunicipality(
      municipality,
      fallback: fallback,
      memCacheWidth: 96,
      memCacheHeight: 96,
    );
  }
}

class _AnalyticsPageHeader extends StatelessWidget {
  const _AnalyticsPageHeader();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF6EC),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: OptacaAdminTheme.border.withValues(alpha: 0.75),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              gradient: OptacaAdminTheme.kpiGradient,
              borderRadius: BorderRadius.circular(13),
              boxShadow: [
                BoxShadow(
                  color: OptacaAdminTheme.primary.withValues(alpha: 0.25),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: const Icon(
              Icons.route_rounded,
              color: Colors.white,
              size: 24,
            ),
          ),
          const SizedBox(width: 12),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Trip Planner Analytics',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w900,
                    color: OptacaAdminTheme.text,
                    letterSpacing: -0.2,
                    height: 1.15,
                  ),
                ),
                SizedBox(height: 4),
                Text(
                  'Monitor trip planning trends, popular destinations, and travel patterns across municipalities.',
                  style: TextStyle(
                    fontSize: 12.5,
                    height: 1.35,
                    color: OptacaAdminTheme.textMuted,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          IgnorePointer(
            child: CustomPaint(
              size: const Size(68, 52),
              painter: _HeaderArtPainter(),
            ),
          ),
        ],
      ),
    );
  }
}

class _HeaderArtPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final mountain = Path()
      ..moveTo(0, size.height)
      ..lineTo(size.width * 0.28, size.height * 0.42)
      ..lineTo(size.width * 0.48, size.height * 0.68)
      ..lineTo(size.width * 0.72, size.height * 0.28)
      ..lineTo(size.width, size.height)
      ..close();
    canvas.drawPath(
      mountain,
      Paint()..color = OptacaAdminTheme.primary.withValues(alpha: 0.18),
    );
    final palm = Paint()
      ..color = OptacaAdminTheme.primary.withValues(alpha: 0.55)
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    final trunkX = size.width * 0.86;
    canvas.drawLine(
      Offset(trunkX, size.height * 0.92),
      Offset(trunkX, size.height * 0.42),
      palm,
    );
    for (final dx in [-14.0, -6.0, 6.0, 14.0]) {
      canvas.drawLine(
        Offset(trunkX, size.height * 0.42),
        Offset(trunkX + dx, size.height * 0.22),
        palm,
      );
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _CardWavePainter extends CustomPainter {
  const _CardWavePainter();

  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()
      ..moveTo(size.width * 0.45, size.height)
      ..quadraticBezierTo(
        size.width * 0.65,
        size.height * 0.25,
        size.width,
        size.height * 0.5,
      )
      ..lineTo(size.width, size.height)
      ..close();
    canvas.drawPath(
      path,
      Paint()..color = OptacaAdminTheme.primary.withValues(alpha: 0.10),
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _TripTrendLineChart extends StatefulWidget {
  const _TripTrendLineChart({
    super.key,
    required this.series,
    required this.peakIndex,
    required this.maxY,
    required this.yInterval,
    required this.showEveryX,
  });

  final List<TripTrendPoint> series;
  final int? peakIndex;
  final double maxY;
  final double yInterval;
  final int showEveryX;

  @override
  State<_TripTrendLineChart> createState() => _TripTrendLineChartState();
}

class _TripTrendLineChartState extends State<_TripTrendLineChart> {
  static const _line = Color(0xFFFF7900);
  static const _highlight = Color(0xFFFF8C24);
  static const _fill = Color(0xFFFFE2C7);
  static const _grid = Color(0xFFE5E7EB);
  static const _axis = Color(0xFF1F2937);

  int? _touchedSpot;

  int? get _active {
    final touched = _touchedSpot;
    if (touched != null &&
        touched >= 0 &&
        touched < widget.series.length) {
      return touched;
    }
    return widget.peakIndex;
  }

  @override
  Widget build(BuildContext context) {
    final series = widget.series;
    final maxY = widget.maxY;
    final yInterval = widget.yInterval;
    final showEveryX = widget.showEveryX;
    final touched = _active;

    return SizedBox(
      height: 260,
      child: LineChart(
        LineChartData(
          minX: 0,
          maxX: math.max(0, series.length - 1).toDouble(),
          minY: 0,
          maxY: maxY,
          clipData: const FlClipData.none(),
          gridData: FlGridData(
            drawVerticalLine: false,
            horizontalInterval: yInterval,
            getDrawingHorizontalLine: (value) => const FlLine(
              color: _grid,
              strokeWidth: 1,
            ),
          ),
          borderData: FlBorderData(show: false),
          extraLinesData: ExtraLinesData(
            verticalLines: [
              if (touched != null)
                VerticalLine(
                  x: touched.toDouble(),
                  color: _highlight.withValues(alpha: 0.35),
                  strokeWidth: 1,
                  dashArray: const [5, 4],
                ),
            ],
          ),
          titlesData: FlTitlesData(
            topTitles: const AxisTitles(),
            rightTitles: const AxisTitles(),
            leftTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 28,
                interval: yInterval,
                getTitlesWidget: (value, meta) {
                  if (value < 0 || value > maxY + 0.01) {
                    return const SizedBox.shrink();
                  }
                  if ((value - value.roundToDouble()).abs() > 0.01) {
                    return const SizedBox.shrink();
                  }
                  return Text(
                    '${value.round()}',
                    style: const TextStyle(
                      fontSize: 10,
                      color: AppColors.textGrey,
                    ),
                  );
                },
              ),
            ),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 32,
                interval: 1,
                getTitlesWidget: (value, meta) {
                  final i = value.round();
                  if (i < 0 || i >= series.length) {
                    return const SizedBox.shrink();
                  }
                  if ((value - i).abs() > 0.01) {
                    return const SizedBox.shrink();
                  }
                  if (i % showEveryX != 0 && i != series.length - 1) {
                    return const SizedBox.shrink();
                  }
                  return Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      series[i].label,
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight:
                            i == touched ? FontWeight.w800 : FontWeight.w500,
                        color: i == touched ? _axis : AppColors.textGrey,
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
          lineBarsData: [
            LineChartBarData(
              spots: [
                for (var i = 0; i < series.length; i++)
                  FlSpot(i.toDouble(), series[i].count.toDouble()),
              ],
              isCurved: series.length > 1,
              preventCurveOverShooting: true,
              preventCurveOvershootingThreshold: 0,
              curveSmoothness: 0.28,
              color: _line,
              barWidth: 3,
              isStrokeCapRound: true,
              dotData: FlDotData(
                show: true,
                getDotPainter: (spot, percent, bar, index) {
                  final selected = index == touched;
                  return FlDotCirclePainter(
                    radius: selected ? 6 : 3.2,
                    color: selected ? Colors.white : _line,
                    strokeWidth: selected ? 3 : 0,
                    strokeColor: _line,
                  );
                },
              ),
              belowBarData: BarAreaData(
                show: true,
                cutOffY: 0,
                applyCutOffY: true,
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    _highlight.withValues(alpha: 0.38),
                    _fill.withValues(alpha: 0.22),
                    _fill.withValues(alpha: 0.0),
                  ],
                  stops: const [0, 0.45, 1],
                ),
              ),
            ),
          ],
          lineTouchData: LineTouchData(
            handleBuiltInTouches: true,
            getTouchedSpotIndicator: (bar, indexes) => [
              for (final _ in indexes)
                TouchedSpotIndicatorData(
                  const FlLine(
                    color: _highlight,
                    strokeWidth: 1,
                    dashArray: [5, 4],
                  ),
                  FlDotData(
                    getDotPainter: (spot, percent, bar, _) =>
                        FlDotCirclePainter(
                      radius: 6,
                      color: Colors.white,
                      strokeWidth: 3,
                      strokeColor: _line,
                    ),
                  ),
                ),
            ],
            touchTooltipData: LineTouchTooltipData(
              getTooltipColor: (_) => const Color(0xFF1C1410),
              tooltipRoundedRadius: 12,
              tooltipPadding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 8,
              ),
              fitInsideHorizontally: true,
              fitInsideVertically: true,
              getTooltipItems: (spots) => [
                for (final spot in spots)
                  if (spot.x.round() >= 0 &&
                      spot.x.round() < series.length)
                    LineTooltipItem(
                      '${series[spot.x.round()].tooltipLabel}\n',
                      const TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                      children: [
                        TextSpan(
                          text:
                              '${spot.y.round()} trip '
                              '${spot.y.round() == 1 ? 'plan' : 'plans'}',
                          style: const TextStyle(
                            color: Color(0xFFFFB46A),
                            fontSize: 13,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ],
                    ),
              ],
            ),
            touchCallback: (event, response) {
              final spots = response?.lineBarSpots;
              if (spots == null || spots.isEmpty) return;
              final index = spots.first.x.round();
              if (index == _touchedSpot) return;
              setState(() => _touchedSpot = index);
            },
          ),
        ),
        duration: const Duration(milliseconds: 280),
        curve: Curves.easeOutCubic,
      ),
    );
  }
}

const _sliceColors = <Color>[
  Color(0xFFF97316),
  Color(0xFFFB923C),
  Color(0xFFC2410C),
  Color(0xFF2563EB),
  Color(0xFF16A34A),
  Color(0xFFCA8A04),
];

class _StatCard extends StatelessWidget {
  const _StatCard({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: OptacaAdminTheme.border),
        boxShadow: OptacaAdminTheme.cardShadow,
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Stack(
          children: [
            const Positioned(
              right: 0,
              bottom: 0,
              width: 90,
              height: 54,
              child: CustomPaint(painter: _CardWavePainter()),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: OptacaAdminTheme.lightOrange,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(icon, color: OptacaAdminTheme.primary),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          value,
                          style: const TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.w900,
                            color: OptacaAdminTheme.text,
                            height: 1.05,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          label,
                          style: const TextStyle(
                            color: AppColors.textGrey,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Message extends StatelessWidget {
  const _Message({required this.title, required this.body});

  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 460),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                title,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                body,
                textAlign: TextAlign.center,
                style: const TextStyle(color: AppColors.textGrey),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

Map<String, dynamic> _normalizeTrip(Map<String, dynamic> raw, String id) {
  final data = Map<String, dynamic>.from(raw);
  data['id'] = data['id'] ?? id;
  final created = _parseSavedAt(data['createdAt']);
  if (created != null) {
    data['createdAt'] = created.toIso8601String();
  }
  return data;
}

DateTime? _parseSavedAt(dynamic raw) {
  if (raw == null) return null;
  if (raw is DateTime) return raw.toLocal();
  if (raw is Timestamp) return raw.toDate().toLocal();
  if (raw is int) {
    if (raw > 99999999999999) {
      return DateTime.fromMicrosecondsSinceEpoch(raw).toLocal();
    }
    if (raw > 9999999999) {
      return DateTime.fromMillisecondsSinceEpoch(raw).toLocal();
    }
    if (raw > 999999999) {
      return DateTime.fromMillisecondsSinceEpoch(raw * 1000).toLocal();
    }
    return null;
  }
  final text = '$raw'.trim();
  if (text.isEmpty || text == 'null') return null;
  return DateTime.tryParse(text)?.toLocal();
}

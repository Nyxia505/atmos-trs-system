import 'dart:math' as math;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import 'data.dart';
import 'firestore_loader.dart';
import 'services/admin_live_collections.dart';
import 'services/tourism_session.dart' show tourismCatalogRevision;
import 'services/reports/report_check_ins.dart';
import 'theme/tourism_app_theme.dart';
import 'utils/trip_planner_analytics.dart';
import 'widgets/municipality_image.dart';
import 'widgets/optaca_portal_ui.dart';
import 'widgets/reports/trip_analytics_period_pickers.dart';

/// One QR check-in counted as a recorded arrival. No tourist identity is kept.
class RecordedArrival {
  const RecordedArrival({
    required this.at,
    required this.municipalityName,
    required this.spotName,
  });

  final DateTime? at;
  final String municipalityName;
  final String spotName;

  bool get hasDate => at != null;
}

List<RecordedArrival> recordedArrivalsFromCheckIns(
  Iterable<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
) {
  return recordedArrivalsFromRecords([
    for (final doc in docs) CheckInRecord.fromRaw(doc.id, doc.data()),
  ]);
}

List<RecordedArrival> recordedArrivalsFromRecords(
  List<CheckInRecord> records,
) {
  return [
    for (final record in records)
      RecordedArrival(
        at: record.at,
        municipalityName: record.municipalityName,
        spotName: record.spotName,
      ),
  ];
}

bool arrivalInRange(RecordedArrival arrival, DateTimeRange? range) {
  if (range == null) return true;
  final at = arrival.at;
  if (at == null) return false;
  final day = DateTime(at.year, at.month, at.day);
  final start = DateTime(range.start.year, range.start.month, range.start.day);
  final end = DateTime(range.end.year, range.end.month, range.end.day);
  return !day.isBefore(start) && !day.isAfter(end);
}

Map<String, int> arrivalCountsByMunicipality(
  List<RecordedArrival> arrivals, {
  DateTimeRange? range,
}) {
  final counts = <String, int>{for (final m in municipalities) m.name: 0};
  for (final arrival in arrivals) {
    if (!arrivalInRange(arrival, range)) continue;
    final municipality = municipalityForArrival(arrival);
    if (municipality == null) continue;
    counts[municipality.name] = (counts[municipality.name] ?? 0) + 1;
  }
  return counts;
}

int spotsInMunicipality(Municipality municipality) {
  return allSpots
      .where((spot) => touristSpotBelongsToMunicipality(spot, municipality))
      .length;
}

Municipality? municipalityForArrival(RecordedArrival arrival) {
  final name = arrival.municipalityName.trim();
  if (name.isEmpty) return null;
  for (final municipality in municipalities) {
    if (municipality.name == name) return municipality;
    if (localityHintBelongsToMunicipality(name, municipality)) {
      return municipality;
    }
  }
  return null;
}

bool arrivalBelongsToMunicipality(
  RecordedArrival arrival,
  Municipality municipality,
) {
  return municipalityForArrival(arrival)?.name == municipality.name;
}

class MunicipalityRank {
  const MunicipalityRank({
    required this.municipality,
    required this.arrivals,
    required this.rank,
    required this.percent,
  });

  final Municipality municipality;
  final int arrivals;
  final int rank;
  final int percent;
}

List<MunicipalityRank> rankMunicipalities(Map<String, int> counts) {
  final total = counts.values.fold<int>(0, (sum, n) => sum + n);
  final ordered = List<Municipality>.from(municipalities)
    ..sort((a, b) {
      final byCount = (counts[b.name] ?? 0).compareTo(counts[a.name] ?? 0);
      if (byCount != 0) return byCount;
      return a.name.compareTo(b.name);
    });
  final ranks = <MunicipalityRank>[];
  var lastCount = -1;
  var lastRank = 0;
  for (var i = 0; i < ordered.length; i++) {
    final count = counts[ordered[i].name] ?? 0;
    if (count != lastCount) {
      lastRank = i + 1;
      lastCount = count;
    }
    ranks.add(
      MunicipalityRank(
        municipality: ordered[i],
        arrivals: count,
        rank: lastRank,
        percent: total == 0 ? 0 : (count / total * 100).round(),
      ),
    );
  }
  return ranks;
}

enum ArrivalGrain { daily, weekly, monthly, yearly }

class ArrivalBucket {
  const ArrivalBucket(this.label, this.count);
  final String label;
  final int count;
}

List<ArrivalBucket> arrivalTrend(
  List<RecordedArrival> arrivals,
  ArrivalGrain grain, {
  DateTimeRange? range,
}) {
  final dated = [
    for (final arrival in arrivals)
      if (arrival.hasDate && arrivalInRange(arrival, range)) arrival.at!,
  ]..sort();
  if (dated.isEmpty) return const [];

  final counts = <String, int>{};
  final labels = <String, String>{};
  for (final at in dated) {
    final local = at.toLocal();
    final String key;
    final String label;
    switch (grain) {
      case ArrivalGrain.daily:
        key = '${local.year}-${local.month}-${local.day}';
        label = '${local.month}/${local.day}';
      case ArrivalGrain.weekly:
        final start = local.subtract(Duration(days: local.weekday - 1));
        key = '${start.year}-${start.month}-${start.day}';
        label = '${start.month}/${start.day}';
      case ArrivalGrain.monthly:
        key = '${local.year}-${local.month.toString().padLeft(2, '0')}';
        label = '${_monthName(local.month)} ${local.year}';
      case ArrivalGrain.yearly:
        key = '${local.year}';
        label = '${local.year}';
    }
    counts[key] = (counts[key] ?? 0) + 1;
    labels[key] = label;
  }
  final keys = counts.keys.toList()..sort();
  return [for (final key in keys) ArrivalBucket(labels[key] ?? key, counts[key]!)];
}

/// Growth against the previous window of the same length.
/// Returns null when the earlier window has no arrivals to compare.
double? arrivalGrowthPercent({
  required int current,
  required int previous,
}) {
  if (previous <= 0) return null;
  return (current - previous) / previous * 100;
}

String? recordedArrivalGrowthLabel(
  List<RecordedArrival> arrivals,
  DateTimeRange? range,
) {
  final now = DateTime.now();
  final DateTime currentStart;
  final DateTime currentEnd;
  final DateTime previousStart;
  final DateTime previousEnd;
  if (range != null) {
    currentStart = range.start;
    currentEnd = range.end;
    final days = currentEnd.difference(currentStart).inDays + 1;
    previousEnd = currentStart.subtract(const Duration(days: 1));
    previousStart = previousEnd.subtract(Duration(days: days - 1));
  } else {
    currentStart = DateTime(now.year, now.month, 1);
    currentEnd = DateTime(now.year, now.month + 1, 0);
    previousStart = DateTime(now.year, now.month - 1, 1);
    previousEnd = DateTime(now.year, now.month, 0);
  }
  final current = arrivalsInWindow(arrivals, currentStart, currentEnd);
  final previous = arrivalsInWindow(arrivals, previousStart, previousEnd);
  final percent = arrivalGrowthPercent(current: current, previous: previous);
  if (percent == null) return null;
  final direction = percent >= 0 ? 'up' : 'down';
  return '$direction ${percent.abs().toStringAsFixed(0)}% ($previous earlier, $current in this period)';
}

int arrivalsInWindow(List<RecordedArrival> arrivals, DateTime start, DateTime end) {
  var count = 0;
  final from = DateTime(start.year, start.month, start.day);
  final to = DateTime(end.year, end.month, end.day);
  for (final arrival in arrivals) {
    final at = arrival.at;
    if (at == null) continue;
    final day = DateTime(at.year, at.month, at.day);
    if (!day.isBefore(from) && !day.isAfter(to)) count++;
  }
  return count;
}

class MunicipalityPerformancePage extends StatefulWidget {
  const MunicipalityPerformancePage({
    super.key,
    required this.municipality,
    required this.onChanged,
    required this.onManageSpots,
    required this.onEditSpot,
    this.initialRange,
  });

  final Municipality municipality;
  final VoidCallback onChanged;
  final VoidCallback onManageSpots;
  final ValueChanged<TouristSpot> onEditSpot;
  final DateTimeRange? initialRange;

  @override
  State<MunicipalityPerformancePage> createState() =>
      _MunicipalityPerformancePageState();
}

class _MunicipalityPerformancePageState extends State<MunicipalityPerformancePage> {
  late DateTimeRange? _range = widget.initialRange;
  TripTrendGrain _grain = TripTrendGrain.monthly;
  late TripTrendWindow _window = widget.initialRange == null
      ? TripTrendWindow.current(TripTrendGrain.monthly)
      : TripTrendWindow.fromRange(
          grain: TripTrendGrain.monthly,
          startInclusive: widget.initialRange!.start,
          endInclusive: widget.initialRange!.end,
        );
  bool _spotsLoading = false;
  String? _spotsError;

  @override
  void initState() {
    super.initState();
    tourismCatalogRevision.addListener(_onCatalog);
    if (allSpots.isEmpty) {
      _loadSpots();
    }
  }

  @override
  void dispose() {
    tourismCatalogRevision.removeListener(_onCatalog);
    super.dispose();
  }

  void _onCatalog() {
    if (!mounted) return;
    if (!optacaTabIsActive(context)) return;
    setState(() {});
  }

  Future<void> _loadSpots() async {
    if (_spotsLoading) return;
    setState(() {
      _spotsLoading = true;
      _spotsError = null;
    });
    try {
      await loadTouristSpotsFromFirestore().timeout(
        const Duration(seconds: 25),
      );
      tourismCatalogRevision.value++;
    } catch (e) {
      debugPrint('Municipality performance spots: $e');
      if (mounted) {
        setState(() => _spotsError = e.toString());
      }
    } finally {
      if (mounted) setState(() => _spotsLoading = false);
    }
  }

  DateTimeRange get _chartRange => DateTimeRange(
        start: _window.start,
        end: _window.inclusiveEnd,
      );

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
        _range = DateTimeRange(
          start: picked.start,
          end: picked.inclusiveEnd,
        );
      });
      return;
    }
    if (grain == _grain) return;
    setState(() {
      _grain = grain;
      _window = TripTrendWindow.current(grain);
      _range = DateTimeRange(
        start: _window.start,
        end: _window.inclusiveEnd,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final isCity = widget.municipality.divisionLabel == 'City';
    return Scaffold(
      backgroundColor: OptacaAdminTheme.background,
      appBar: AppBar(
        backgroundColor: OptacaAdminTheme.primary,
        foregroundColor: Colors.white,
        title: Text(widget.municipality.name),
      ),
      body: AdminLiveDataBuilder(
        builder: (context, live) {
          if (!live.checkInsReady) {
            return const Center(child: CircularProgressIndicator());
          }
          if (live.checkInsError != null && live.checkIns.isEmpty) {
            return OptacaLoadError(
              title: 'Recorded arrivals could not be loaded for this account.',
              message: '${live.checkInsError}',
              onRetry: live.retry,
            );
          }
          final all = recordedArrivalsFromRecords(live.checkInRecords);
          final mine = [
            for (final arrival in all)
              if (arrivalBelongsToMunicipality(arrival, widget.municipality))
                arrival,
          ];
          final chartRange = _range ?? _chartRange;
          final inRange = [
            for (final arrival in mine)
              if (arrivalInRange(arrival, chartRange)) arrival,
          ];
          final counts = arrivalCountsByMunicipality(all, range: chartRange);
          final ranks = rankMunicipalities(counts);
          final rank = ranks.cast<MunicipalityRank?>().firstWhere(
                (row) => row!.municipality.name == widget.municipality.name,
                orElse: () => null,
              );
          final spots = allSpots
              .where((spot) => touristSpotBelongsToMunicipality(spot, widget.municipality))
              .toList()
            ..sort((a, b) => a.displayName.compareTo(b.displayName));
          final spotCounts = _spotArrivalCounts(inRange, spots);
          final undated = mine.where((arrival) => !arrival.hasDate).length;
          final growth = recordedArrivalGrowthLabel(mine, chartRange);

          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
            children: [
              _header(isCity),
              const SizedBox(height: 12),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  _stat('Recorded arrivals', '${inRange.length}'),
                  _stat('Tourist spots', '${spots.length}'),
                  _stat(
                    'Provincial rank',
                    rank == null ? '—' : '#${rank.rank} of ${ranks.length}',
                  ),
                  _stat(
                    'Share of arrivals',
                    rank == null ? '—' : '${rank.percent}%',
                  ),
                ],
              ),
              if (undated > 0) ...[
                const SizedBox(height: 8),
                Text(
                  _range == null
                      ? '$undated arrivals have no date. They are in the total, not in the chart.'
                      : '$undated arrivals have no date and are left out of this date range.',
                  style: const TextStyle(color: AppColors.textGrey, fontSize: 12),
                ),
              ],
              const SizedBox(height: 8),
              Text(
                growth ??
                    'Growth is not shown until an earlier period has recorded arrivals.',
                style: const TextStyle(fontSize: 13),
              ),
              const SizedBox(height: 16),
              _trendCard(mine, chartRange),
              const SizedBox(height: 16),
              _spotsCard(spots, spotCounts),
            ],
          );
        },
      ),
    );
  }

  Widget _header(bool isCity) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: OptacaAdminTheme.cardDecoration,
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: SizedBox(
              width: 72,
              height: 72,
              child: buildMunicipalityImageForMunicipality(
                widget.municipality,
                fallback: ColoredBox(
                  color: AppColors.primary.withValues(alpha: 0.14),
                  child: Icon(
                    isCity ? Icons.location_city_rounded : Icons.domain_rounded,
                    color: AppColors.primary,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.municipality.name,
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 6),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppColors.primary,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    widget.municipality.divisionLabel,
                    style: const TextStyle(color: Colors.white, fontSize: 12),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _stat(String label, String value) {
    return Container(
      width: 180,
      padding: const EdgeInsets.all(16),
      decoration: OptacaAdminTheme.cardDecoration,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            value,
            style: const TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w800,
              color: OptacaAdminTheme.text,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: const TextStyle(
              color: OptacaAdminTheme.textMuted,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _grainChip(TripTrendGrain grain, String label) {
    final selected = _grain == grain;
    return ChoiceChip(
      label: Text(label),
      selected: selected,
      selectedColor: const Color(0xFFFFE2C7),
      labelStyle: TextStyle(
        color: const Color(0xFF1F2937),
        fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
      ),
      side: BorderSide(
        color: selected ? OptacaAdminTheme.primary : OptacaAdminTheme.border,
      ),
      showCheckmark: false,
      onSelected: (_) => _onGrainPressed(grain),
    );
  }

  Widget _trendCard(List<RecordedArrival> mine, DateTimeRange chartRange) {
    const lineColor = Color(0xFFFF7900);
    const fillColor = Color(0xFFFFE2C7);
    const axisText = Color(0xFF1F2937);

    final dated = [
      for (final arrival in mine)
        if (arrival.hasDate && arrivalInRange(arrival, chartRange)) arrival.at!,
    ];
    final series = fillTrendSeries(savedAt: dated, window: _window);
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

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: OptacaAdminTheme.cardDecoration,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Recorded arrival trend',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              _grainChip(TripTrendGrain.daily, 'Daily'),
              _grainChip(TripTrendGrain.weekly, 'Weekly'),
              _grainChip(TripTrendGrain.monthly, 'Monthly'),
              _grainChip(TripTrendGrain.yearly, 'Yearly'),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              IconButton(
                tooltip: 'Previous period',
                visualDensity: VisualDensity.compact,
                onPressed: () => setState(() {
                  _window = _window.previous();
                  _grain = _window.grain;
                  _range = DateTimeRange(
                    start: _window.start,
                    end: _window.inclusiveEnd,
                  );
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
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.calendar_today_outlined,
                        size: 14,
                        color: axisText,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        _window.label,
                        style: const TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 14,
                          color: axisText,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              IconButton(
                tooltip: 'Next period',
                visualDensity: VisualDensity.compact,
                onPressed: _window.canGoNext
                    ? () => setState(() {
                          _window = _window.next();
                          _grain = _window.grain;
                          _range = DateTimeRange(
                            start: _window.start,
                            end: _window.inclusiveEnd,
                          );
                        })
                    : null,
                icon: const Icon(Icons.chevron_right_rounded),
              ),
              if (peak != null)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: fillColor,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    'Peak: ${series[peak].count} '
                    '${series[peak].count == 1 ? 'arrival' : 'arrivals'}',
                    style: const TextStyle(
                      color: lineColor,
                      fontWeight: FontWeight.w800,
                      fontSize: 12,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          if (series.isEmpty)
            const Text(
              'No dated arrivals in this period.',
              style: TextStyle(color: AppColors.textGrey),
            )
          else
            _ArrivalTrendLineChart(
              key: ValueKey(
                '${_window.start.toIso8601String()}-'
                '${_window.end.toIso8601String()}-${_window.grain.name}',
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

  Widget _spotsCard(List<TouristSpot> spots, Map<String, int> counts) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: OptacaAdminTheme.cardDecoration,
      child: Material(
        color: Colors.white,
        child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Tourist spots',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
                ),
              ),
              TextButton(onPressed: widget.onManageSpots, child: const Text('Manage spots')),
            ],
          ),
          const SizedBox(height: 8),
          if (_spotsLoading && spots.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 16),
              child: Center(
                child: CircularProgressIndicator(color: AppColors.primary),
              ),
            )
          else if (_spotsError != null && spots.isEmpty)
            OptacaLoadError(
              title: 'Tourist spots could not be loaded.',
              message: _spotsError!,
              onRetry: _loadSpots,
            )
          else if (spots.isEmpty)
            const Text(
              'No tourist spots are saved for this municipality.',
              style: TextStyle(color: AppColors.textGrey),
            )
          else
            for (final spot in spots)
              ListTile(
                tileColor: Colors.white,
                contentPadding: EdgeInsets.zero,
                leading: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: SizedBox(
                    width: 48,
                    height: 48,
                    child: buildTouristSpotProfileImage(
                      spot,
                      fallback: ColoredBox(
                        color: AppColors.primary.withValues(alpha: 0.14),
                        child: const Icon(Icons.place, color: AppColors.primary),
                      ),
                    ),
                  ),
                ),
                title: Text(spot.displayName, maxLines: 1, overflow: TextOverflow.ellipsis),
                subtitle: Text(
                  [
                    spot.location.isEmpty
                        ? widget.municipality.name
                        : spot.location,
                    if (spot.category.trim().isNotEmpty) spot.category.trim(),
                    '${counts[spot.name] ?? 0} arrivals',
                    _spotStatus(spot),
                  ].join(' · '),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                trailing: IconButton(
                  tooltip: 'Edit spot',
                  icon: const Icon(Icons.edit_outlined),
                  onPressed: () => widget.onEditSpot(spot),
                ),
              ),
        ],
        ),
      ),
    );
  }

}

Map<String, int> _spotArrivalCounts(List<RecordedArrival> arrivals, List<TouristSpot> spots) {
  final counts = <String, int>{for (final spot in spots) spot.name: 0};
  for (final arrival in arrivals) {
    final spotName = arrival.spotName.toLowerCase();
    if (spotName.isEmpty) continue;
    for (final spot in spots) {
      if (spot.name.toLowerCase() == spotName ||
          spot.displayName.toLowerCase() == spotName) {
        counts[spot.name] = (counts[spot.name] ?? 0) + 1;
        break;
      }
    }
  }
  return counts;
}

String _spotStatus(TouristSpot spot) {
  final missingImage = spot.imagePath.trim().isEmpty;
  final missingPlace = spot.latitude == null || spot.longitude == null;
  if (missingImage && missingPlace) return 'Incomplete';
  if (missingImage) return 'Missing image';
  if (missingPlace) return 'Missing coordinates';
  return 'Listed';
}

String _monthName(int month) {
  const names = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];
  return names[month - 1];
}

class _ArrivalTrendLineChart extends StatefulWidget {
  const _ArrivalTrendLineChart({
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
  State<_ArrivalTrendLineChart> createState() => _ArrivalTrendLineChartState();
}

class _ArrivalTrendLineChartState extends State<_ArrivalTrendLineChart> {
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
      height: 268,
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
          titlesData: FlTitlesData(
            topTitles: const AxisTitles(),
            rightTitles: const AxisTitles(),
            leftTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 36,
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
                  if (spot.x.round() >= 0 && spot.x.round() < series.length)
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
                              '${spot.y.round()} '
                              '${spot.y.round() == 1 ? 'arrival' : 'arrivals'}',
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

class MunicipalityRankingList extends StatelessWidget {
  const MunicipalityRankingList({super.key, required this.ranks, required this.onOpen});

  final List<MunicipalityRank> ranks;
  final ValueChanged<Municipality> onOpen;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: OptacaAdminTheme.cardDecoration,
      child: Material(
        color: Colors.white,
        child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Arrival ranking',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 4),
          const Text(
            'Share of recorded provincial arrivals in the current filter. Not trip plans.',
            style: TextStyle(color: AppColors.textGrey, fontSize: 12),
          ),
          const SizedBox(height: 8),
          for (final row in ranks)
            ListTile(
              tileColor: Colors.white,
              dense: true,
              contentPadding: EdgeInsets.zero,
              leading: Text('#${row.rank}', style: const TextStyle(fontWeight: FontWeight.w800)),
              title: Text(row.municipality.name),
              subtitle: Text('${row.arrivals} arrivals · ${row.percent}%'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => onOpen(row.municipality),
            ),
        ],
        ),
      ),
    );
  }
}

class MunicipalityComparisonPanel extends StatelessWidget {
  const MunicipalityComparisonPanel({
    super.key,
    required this.left,
    required this.right,
    required this.leftArrivals,
    required this.rightArrivals,
    required this.leftMonthly,
    required this.rightMonthly,
    required this.leftGrowth,
    required this.rightGrowth,
    required this.onLeft,
    required this.onRight,
    required this.choices,
  });

  final String? left;
  final String? right;
  final int leftArrivals;
  final int rightArrivals;
  final List<int> leftMonthly;
  final List<int> rightMonthly;
  final String? leftGrowth;
  final String? rightGrowth;
  final ValueChanged<String?> onLeft;
  final ValueChanged<String?> onRight;
  final List<String> choices;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: OptacaAdminTheme.cardDecoration,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Compare municipalities',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              _picker('First', left, onLeft),
              _picker('Second', right, onRight),
            ],
          ),
          if (left != null && right != null && left != right) ...[
            const SizedBox(height: 12),
            LayoutBuilder(
              builder: (context, constraints) {
                final sideBySide = constraints.maxWidth >= 700;
                final cards = [
                  _side(left!, leftArrivals, spotsFor(left!), leftGrowth),
                  _side(right!, rightArrivals, spotsFor(right!), rightGrowth),
                ];
                if (!sideBySide) {
                  return Column(children: [cards[0], const SizedBox(height: 12), cards[1]]);
                }
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: cards[0]),
                    const SizedBox(width: 12),
                    Expanded(child: cards[1]),
                  ],
                );
              },
            ),
            const SizedBox(height: 12),
            const Text('Monthly recorded arrivals', style: TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            SizedBox(
              height: 180,
              child: BarChart(
                BarChartData(
                  alignment: BarChartAlignment.spaceAround,
                  gridData: const FlGridData(drawVerticalLine: false),
                  borderData: FlBorderData(show: false),
                  barGroups: [
                    for (var i = 0; i < 12; i++)
                      BarChartGroupData(
                        x: i,
                        barRods: [
                          BarChartRodData(
                            toY: leftMonthly[i].toDouble(),
                            color: AppColors.primary,
                            width: 6,
                          ),
                          BarChartRodData(
                            toY: rightMonthly[i].toDouble(),
                            color: const Color(0xFF2563EB),
                            width: 6,
                          ),
                        ],
                      ),
                  ],
                  titlesData: FlTitlesData(
                    topTitles: const AxisTitles(),
                    rightTitles: const AxisTitles(),
                    leftTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: true, reservedSize: 28),
                    ),
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        getTitlesWidget: (value, meta) {
                          final i = value.toInt();
                          if (i < 0 || i > 11) return const SizedBox.shrink();
                          return Text(_monthName(i + 1), style: const TextStyle(fontSize: 9));
                        },
                      ),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              '$left is orange. $right is blue.',
              style: const TextStyle(color: AppColors.textGrey, fontSize: 12),
            ),
          ],
        ],
      ),
    );
  }

  Widget _picker(String label, String? value, ValueChanged<String?> onChanged) {
    return SizedBox(
      width: 240,
      child: DropdownButtonFormField<String?>(
        value: choices.contains(value) ? value : null,
        isExpanded: true,
        decoration: InputDecoration(
          labelText: label,
          isDense: true,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        ),
        items: [
          const DropdownMenuItem<String?>(value: null, child: Text('Select')),
          for (final name in choices)
            DropdownMenuItem(value: name, child: Text(name, overflow: TextOverflow.ellipsis)),
        ],
        onChanged: onChanged,
      ),
    );
  }

  static int spotsFor(String name) {
    final match = municipalities.where((m) => m.name == name);
    if (match.isEmpty) return 0;
    return spotsInMunicipality(match.first);
  }

  Widget _side(String name, int arrivals, int spots, String? growth) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(name, style: const TextStyle(fontWeight: FontWeight.w800)),
        Text('$arrivals recorded arrivals'),
        Text('$spots tourist spots'),
        Text(
          growth ?? 'No earlier period to measure growth.',
          style: const TextStyle(color: AppColors.textGrey, fontSize: 12),
        ),
      ],
    );
  }
}

List<int> monthlyArrivalCounts(List<RecordedArrival> arrivals, {DateTimeRange? range}) {
  final months = List<int>.filled(12, 0);
  for (final arrival in arrivals) {
    if (!arrivalInRange(arrival, range)) continue;
    final at = arrival.at;
    if (at == null) continue;
    months[at.month - 1]++;
  }
  return months;
}

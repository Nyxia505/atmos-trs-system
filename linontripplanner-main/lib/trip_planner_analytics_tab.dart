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
      avatar: Icon(
        switch (grain) {
          TripTrendGrain.daily => Icons.calendar_today_outlined,
          TripTrendGrain.weekly => Icons.date_range_outlined,
          TripTrendGrain.monthly => Icons.calendar_month_outlined,
          TripTrendGrain.yearly => Icons.event_outlined,
        },
        size: 16,
        color: selected ? OptacaAdminTheme.primary : AppColors.textGrey,
      ),
      showCheckmark: false,
      onSelected: (_) => _onGrainPressed(grain),
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
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
      children: [
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
        const SizedBox(height: 16),
        _trends(stats),
        const SizedBox(height: 16),
        _twoColumn(
          _rankedCard(
            title: 'Popular tourist destinations',
            rows: stats.destinations,
            totalPlans: stats.planCount,
          ),
          _rankedCard(
            title: 'Municipality analytics',
            rows: stats.municipalityRanks,
            totalPlans: stats.planCount,
          ),
        ),
        const SizedBox(height: 16),
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
        icon: Icons.timelapse_outlined,
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

    return _card(
      title: 'Trip Planner Trends',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
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
                        })
                    : null,
                icon: const Icon(Icons.chevron_right_rounded),
              ),
              if (_window.preset == TripDatePreset.custom)
                Text(
                  '${_window.selectedDayCount} '
                  '${_window.selectedDayCount == 1 ? 'day' : 'days'}',
                  style: const TextStyle(
                    color: AppColors.textGrey,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
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
                    'Peak: ${series[peak].count} trip '
                    '${series[peak].count == 1 ? 'plan' : 'plans'}',
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
    final total = rows.fold<int>(0, (total, row) => total + row.count);
    return _card(
      title: 'Travel duration',
      child: rows.isEmpty
          ? const Text(
              'No itineraries in this selection have a travel-day count.',
              style: TextStyle(color: AppColors.textGrey),
            )
          : LayoutBuilder(
              builder: (context, c) {
                final pie = SizedBox(
                  width: 160,
                  height: 160,
                  child: PieChart(
                    PieChartData(
                      sectionsSpace: 2,
                      centerSpaceRadius: 36,
                      sections: [
                        for (var i = 0; i < rows.length; i++)
                          PieChartSectionData(
                            color: _sliceColors[i % _sliceColors.length],
                            value: rows[i].count.toDouble(),
                            title: total == 0
                                ? ''
                                : '${(rows[i].count / total * 100).round()}%',
                            radius: 28,
                            titleStyle: const TextStyle(
                              color: Colors.white,
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                      ],
                    ),
                  ),
                );
                final legend = Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (var i = 0; i < rows.length; i++)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: Text(
                          '${rows[i].label}: ${rows[i].count} '
                          '(${total == 0 ? 0 : (rows[i].count / total * 100).round()}%)',
                          style: const TextStyle(fontSize: 13),
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
                  crossAxisAlignment: CrossAxisAlignment.start,
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
    final recorded = stats.coastal + stats.highland;
    return _card(
      title: 'Route analytics',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            recorded == 0
                ? 'No coastal or highland route recorded.'
                : 'Coastal ${stats.coastal} · Highland ${stats.highland}'
                    ' · ${stats.coastalPercent}% / ${stats.highlandPercent}%',
            style: const TextStyle(fontSize: 13),
          ),
          if (stats.routeTypeMissing > 0)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                '${stats.routeTypeMissing} plans have no route type stored, so they are not assigned to either route.',
                style: const TextStyle(color: AppColors.textGrey, fontSize: 12),
              ),
            ),
          const SizedBox(height: 12),
          const Text(
            'Starting municipalities',
            style: TextStyle(fontWeight: FontWeight.w700),
          ),
          _miniList(stats.starts),
          const SizedBox(height: 8),
          const Text(
            'Ending municipalities',
            style: TextStyle(fontWeight: FontWeight.w700),
          ),
          _miniList(stats.ends),
          const SizedBox(height: 8),
          const Text(
            'Municipality routes',
            style: TextStyle(fontWeight: FontWeight.w700),
          ),
          _miniList(stats.routes),
        ],
      ),
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
                  child: Text(row.label, overflow: TextOverflow.ellipsis),
                ),
                Text('${row.count}'),
              ],
            ),
          ),
      ],
    );
  }

  Widget _rankedCard({
    required String title,
    required List<TripRankRow> rows,
    required int totalPlans,
  }) {
    return _card(
      title: title,
      child: rows.isEmpty
          ? const Text(
              'Nothing to rank in this selection.',
              style: TextStyle(color: AppColors.textGrey),
            )
          : Column(
              children: [
                for (final row in rows.take(10))
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                row.detail.isEmpty
                                    ? row.label
                                    : '${row.label} · ${row.detail}',
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            Text(
                              '${row.count} ${row.count == 1 ? 'plan' : 'plans'} '
                              '(${row.percentOf(totalPlans)}%)',
                              style: const TextStyle(fontWeight: FontWeight.w700),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(6),
                          child: LinearProgressIndicator(
                            value: row.barOf(totalPlans),
                            minHeight: 8,
                            backgroundColor: const Color(0xFFFFEDD5),
                            color: AppColors.primary,
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
    );
  }

  Widget _twoColumn(Widget left, Widget right) {
    return LayoutBuilder(
      builder: (context, c) {
        if (c.maxWidth < 900) {
          return Column(
            children: [left, const SizedBox(height: 16), right],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: left),
            const SizedBox(width: 16),
            Expanded(child: right),
          ],
        );
      },
    );
  }

  Widget _card({
    required String title,
    required Widget child,
    Widget? trailing,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: OptacaAdminTheme.cardDecoration,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 12,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                ),
              ),
              ?trailing,
            ],
          ),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }
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
                              '${spot.y.round()} saved trip '
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
      padding: const EdgeInsets.all(16),
      decoration: OptacaAdminTheme.cardDecoration,
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
                    fontWeight: FontWeight.w800,
                  ),
                ),
                Text(
                  label,
                  style: const TextStyle(
                    color: AppColors.textGrey,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
        ],
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

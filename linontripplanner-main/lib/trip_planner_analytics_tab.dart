import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:excel/excel.dart' hide Border;
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import 'data.dart';
import 'services/reports/report_file_saver.dart';
import 'services/saved_trip_store.dart';
import 'widgets/tourism_plan_ui.dart';

/// Read-only OPTACA view of saved Plan-my-trip itineraries.
///
/// These figures are planned trips, not confirmed arrivals.
class TripPlannerAnalyticsTab extends StatefulWidget {
  const TripPlannerAnalyticsTab({super.key});

  @override
  State<TripPlannerAnalyticsTab> createState() =>
      _TripPlannerAnalyticsTabState();
}

enum _TrendGrain { daily, weekly, monthly, yearly }

class _TripPlannerAnalyticsTabState extends State<TripPlannerAnalyticsTab> {
  static const _durationOptions = <String>[
    'Any duration',
    '1-day trips',
    '2-day trips',
    '3-day trips',
    '4–5-day trips',
    '6–7-day trips',
    '8 or more days',
  ];

  late final Stream<QuerySnapshot<Map<String, dynamic>>> _trips =
      FirebaseFirestore.instance
          .collection(kTouristTripCollection)
          .limit(500)
          .snapshots();

  DateTimeRange? _range;
  String? _municipality;
  String? _startMunicipality;
  String? _endMunicipality;
  String _duration = _durationOptions.first;
  String _routeType = 'Any route type';
  _TrendGrain _grain = _TrendGrain.monthly;
  bool _exporting = false;

  void _resetFilters() {
    setState(() {
      _range = null;
      _municipality = null;
      _startMunicipality = null;
      _endMunicipality = null;
      _duration = _durationOptions.first;
      _routeType = 'Any route type';
    });
  }

  Future<void> _pickRange() async {
    final now = DateTime.now();
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime(now.year + 1, 12, 31),
      initialDateRange: _range,
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: ColorScheme.light(primary: AppColors.primary),
          ),
          child: child ?? const SizedBox.shrink(),
        );
      },
    );
    if (picked != null) setState(() => _range = picked);
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: _trips,
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting &&
            !snap.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snap.hasError) {
          return const _Message(
            title: 'Trip plans could not be read with this account.',
            body:
                'OPTACA admins can read saved itineraries for analytics. '
                'Tourists can still open only their own plans, and the '
                'collection is not public. Reload this page after the '
                'updated access rules are deployed.',
          );
        }
        final plans = [
          for (final doc in snap.data?.docs ?? const [])
            SavedTripPlan.fromJson(_normalizeTrip(doc.data(), doc.id)),
        ];
        if (plans.isEmpty) {
          return const _Message(
            title: 'No saved trip plans yet.',
            body:
                'When tourists finish a plan, the totals here update from '
                'those records. Nothing is shown until a plan is saved.',
          );
        }
        final stats = _TripStats.compute(
          plans,
          range: _range,
          municipality: _municipality,
          startMunicipality: _startMunicipality,
          endMunicipality: _endMunicipality,
          duration: _duration == _durationOptions.first ? null : _duration,
          routeType: switch (_routeType) {
            'Coastal' => 'coastal',
            'Highland' => 'highland',
            'Not recorded' => '',
            _ => null,
          },
        );
        final capped = (snap.data?.docs.length ?? 0) >= 500;
        return ListView(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
          children: [
            _filters(stats.municipalityChoices),
            if (capped)
              const Padding(
                padding: EdgeInsets.only(top: 8),
                child: Text(
                  'Showing 500 saved plans. Older plans are not included in this view.',
                  style: TextStyle(color: AppColors.textGrey, fontSize: 12),
                ),
              ),
            const SizedBox(height: 16),
            if (stats.plans.isEmpty)
              const _Message(
                title: 'No trip plans match these filters.',
                body: 'Reset the filters to see every saved itinerary.',
              )
            else ...[
              _summary(stats),
              const SizedBox(height: 16),
              _trends(stats),
              const SizedBox(height: 16),
              _twoColumn(
                _rankedCard(
                  title: 'Popular tourist destinations',
                  subtitle:
                      'Planned spots. Each spot is counted once per itinerary, not as a confirmed visit.',
                  rows: stats.destinations,
                ),
                _rankedCard(
                  title: 'Municipality analytics',
                  subtitle:
                      'Itineraries that include the municipality as a start, end, or planned spot.',
                  rows: stats.municipalityRanks,
                  showPercentOf: stats.plans.length,
                ),
              ),
              const SizedBox(height: 16),
              _twoColumn(_durationCard(stats), _routesCard(stats)),
            ],
          ],
        );
      },
    );
  }

  Widget _filters(List<String> municipalities) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: TourismPlanUi.planCardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Planned itineraries',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
                ),
              ),
              PopupMenuButton<String>(
                tooltip: 'Generate report',
                onSelected: (format) => _export(format),
                enabled: !_exporting,
                itemBuilder: (context) => const [
                  PopupMenuItem(value: 'pdf', child: Text('PDF')),
                  PopupMenuItem(value: 'xlsx', child: Text('Excel (.xlsx)')),
                ],
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.primary,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    _exporting ? 'Preparing…' : 'Generate report',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          const Text(
            'These numbers are planned trips, not tourist arrivals or QR check-ins.',
            style: TextStyle(color: AppColors.textGrey, fontSize: 12),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              OutlinedButton.icon(
                onPressed: _pickRange,
                icon: const Icon(Icons.date_range_outlined, size: 18),
                label: Text(_range == null ? 'All dates' : _rangeLabel(_range!)),
              ),
              _menu(
                'Municipality',
                _municipality,
                municipalities,
                (v) => setState(() => _municipality = v),
              ),
              _menu(
                'Starting municipality',
                _startMunicipality,
                municipalities,
                (v) => setState(() => _startMunicipality = v),
              ),
              _menu(
                'Ending municipality',
                _endMunicipality,
                municipalities,
                (v) => setState(() => _endMunicipality = v),
              ),
              _choice(
                _duration,
                _durationOptions,
                (v) => setState(() => _duration = v),
              ),
              _choice(
                _routeType,
                const [
                  'Any route type',
                  'Coastal',
                  'Highland',
                  'Not recorded',
                ],
                (v) => setState(() => _routeType = v),
              ),
              TextButton(onPressed: _resetFilters, child: const Text('Reset filters')),
            ],
          ),
        ],
      ),
    );
  }

  Widget _menu(
    String label,
    String? value,
    List<String> options,
    ValueChanged<String?> onChanged,
  ) {
    return SizedBox(
      width: 220,
      child: DropdownButtonFormField<String?>(
        value: options.contains(value) ? value : null,
        isExpanded: true,
        decoration: InputDecoration(
          labelText: label,
          isDense: true,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        ),
        items: [
          const DropdownMenuItem<String?>(value: null, child: Text('All')),
          for (final name in options)
            DropdownMenuItem<String?>(
              value: name,
              child: Text(name, overflow: TextOverflow.ellipsis),
            ),
        ],
        onChanged: onChanged,
      ),
    );
  }

  Widget _choice(
    String value,
    List<String> options,
    ValueChanged<String> onChanged,
  ) {
    return SizedBox(
      width: 180,
      child: DropdownButtonFormField<String>(
        value: value,
        isExpanded: true,
        decoration: InputDecoration(
          isDense: true,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        ),
        items: [
          for (final option in options)
            DropdownMenuItem(value: option, child: Text(option)),
        ],
        onChanged: (next) {
          if (next != null) onChanged(next);
        },
      ),
    );
  }

  Widget _summary(_TripStats stats) {
    final cards = [
      _StatCard(
        icon: Icons.map_outlined,
        label: 'Total trip plans',
        value: '${stats.plans.length}',
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

  Widget _trends(_TripStats stats) {
    final series = stats.trend(_grain);
    return _card(
      title: 'Monthly trip trends',
      subtitle: 'Itineraries grouped by the date they were saved.',
      trailing: SegmentedButton<_TrendGrain>(
        segments: const [
          ButtonSegment(value: _TrendGrain.daily, label: Text('Daily')),
          ButtonSegment(value: _TrendGrain.weekly, label: Text('Weekly')),
          ButtonSegment(value: _TrendGrain.monthly, label: Text('Monthly')),
          ButtonSegment(value: _TrendGrain.yearly, label: Text('Yearly')),
        ],
        selected: {_grain},
        onSelectionChanged: (next) => setState(() => _grain = next.first),
      ),
      child: series.isEmpty
          ? const Text(
              'No saved dates in this selection.',
              style: TextStyle(color: AppColors.textGrey),
            )
          : SizedBox(
              height: 220,
              child: LineChart(
                LineChartData(
                  minY: 0,
                  gridData: const FlGridData(drawVerticalLine: false),
                  borderData: FlBorderData(show: false),
                  titlesData: FlTitlesData(
                    topTitles: const AxisTitles(),
                    rightTitles: const AxisTitles(),
                    leftTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 28,
                        getTitlesWidget: (value, meta) => Text(
                          value == value.roundToDouble()
                              ? '${value.toInt()}'
                              : '',
                          style: const TextStyle(fontSize: 10),
                        ),
                      ),
                    ),
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 28,
                        interval: series.length > 8
                            ? (series.length / 6).ceilToDouble()
                            : 1,
                        getTitlesWidget: (value, meta) {
                          final i = value.toInt();
                          if (i < 0 || i >= series.length) {
                            return const SizedBox.shrink();
                          }
                          return Text(
                            series[i].label,
                            style: const TextStyle(fontSize: 10),
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
                      isCurved: series.length > 2,
                      color: AppColors.primary,
                      barWidth: 3,
                      dotData: const FlDotData(show: true),
                      belowBarData: BarAreaData(
                        show: true,
                        color: AppColors.primary.withValues(alpha: 0.12),
                      ),
                    ),
                  ],
                  lineTouchData: LineTouchData(
                    touchTooltipData: LineTouchTooltipData(
                      getTooltipItems: (spots) => [
                        for (final spot in spots)
                          LineTooltipItem(
                            '${series[spot.x.toInt()].label}\n${spot.y.toInt()} plans',
                            const TextStyle(color: Colors.white, fontSize: 12),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
    );
  }

  Widget _durationCard(_TripStats stats) {
    final rows = stats.durations.where((row) => row.count > 0).toList();
    final total = rows.fold<int>(0, (total, row) => total + row.count);
    return _card(
      title: 'Travel duration',
      subtitle: 'Days selected on the itinerary. Unlimited day counts stay in the last group.',
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
                  return Column(children: [pie, const SizedBox(height: 12), legend]);
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

  Widget _routesCard(_TripStats stats) {
    final recorded = stats.coastal + stats.highland;
    return _card(
      title: 'Route analytics',
      subtitle:
          'Start, end, and route type are taken from the saved plan. '
          'A coastal or highland label is shown only when that choice was stored.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            recorded == 0
                ? 'No saved plan in this selection has a coastal or highland choice recorded.'
                : 'Coastal ${stats.coastal} · Highland ${stats.highland}'
                    '${recorded == 0 ? '' : ' · ${stats.coastalPercent}% coastal, ${stats.highlandPercent}% highland among plans that stored a route type.'}',
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
          const Text('Starting municipalities', style: TextStyle(fontWeight: FontWeight.w700)),
          _miniList(stats.starts),
          const SizedBox(height: 8),
          const Text('Ending municipalities', style: TextStyle(fontWeight: FontWeight.w700)),
          _miniList(stats.ends),
          const SizedBox(height: 8),
          const Text('Municipality routes', style: TextStyle(fontWeight: FontWeight.w700)),
          _miniList(stats.routes),
        ],
      ),
    );
  }

  Widget _miniList(List<_RankRow> rows) {
    if (rows.isEmpty) {
      return const Text('None recorded.', style: TextStyle(color: AppColors.textGrey));
    }
    return Column(
      children: [
        for (final row in rows.take(5))
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Row(
              children: [
                Expanded(child: Text(row.label, overflow: TextOverflow.ellipsis)),
                Text('${row.count}'),
              ],
            ),
          ),
      ],
    );
  }

  Widget _rankedCard({
    required String title,
    required String subtitle,
    required List<_RankRow> rows,
    int? showPercentOf,
  }) {
    final max = rows.isEmpty ? 0 : rows.first.count;
    return _card(
      title: title,
      subtitle: subtitle,
      child: rows.isEmpty
          ? const Text('Nothing to rank in this selection.', style: TextStyle(color: AppColors.textGrey))
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
                              showPercentOf == null || showPercentOf == 0
                                  ? '${row.count}'
                                  : '${row.count} · ${(row.count / showPercentOf * 100).round()}%',
                              style: const TextStyle(fontWeight: FontWeight.w700),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(6),
                          child: LinearProgressIndicator(
                            value: max == 0 ? 0 : row.count / max,
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
          return Column(children: [left, const SizedBox(height: 16), right]);
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
    required String subtitle,
    required Widget child,
    Widget? trailing,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: TourismPlanUi.planCardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 12,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
              if (trailing != null) trailing,
            ],
          ),
          const SizedBox(height: 4),
          Text(subtitle, style: const TextStyle(color: AppColors.textGrey, fontSize: 12)),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }

  Future<void> _export(String format) async {
    final stats = _shownStats;
    if (stats == null || _exporting) return;
    setState(() => _exporting = true);
    try {
      final now = DateTime.now();
      final stamp =
          '${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}';
      final bytes = format == 'pdf'
          ? await _pdfBytes(stats, now)
          : Uint8List.fromList(_xlsxBytes(stats, now));
      final name = format == 'pdf'
          ? 'optaca_trip_planner_analytics_$stamp.pdf'
          : 'optaca_trip_planner_analytics_$stamp.xlsx';
      final where = await saveReportFile(
        fileName: name,
        bytes: bytes,
        mimeType: format == 'pdf'
            ? 'application/pdf'
            : 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Report saved to $where')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('The report could not be saved. $e')),
      );
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }
}

_TripStats? _shownStats;

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
      decoration: TourismPlanUi.planCardDecoration(),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: AppColors.primary),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  value,
                  style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
                ),
                Text(
                  label,
                  style: const TextStyle(color: AppColors.textGrey, fontSize: 12),
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
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
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

class _RankRow {
  const _RankRow(this.label, this.count, {this.detail = ''});
  final String label;
  final String detail;
  final int count;
}

class _TrendPoint {
  const _TrendPoint(this.label, this.count);
  final String label;
  final int count;
}

class _TripStats {
  _TripStats(this.plans);

  final List<SavedTripPlan> plans;
  late final List<_RankRow> destinations;
  late final List<_RankRow> municipalityRanks;
  late final List<_RankRow> starts;
  late final List<_RankRow> ends;
  late final List<_RankRow> routes;
  late final List<_RankRow> durations;
  late final int distinctDestinations;
  late final int distinctMunicipalities;
  late final double? averageDays;
  late final int coastal;
  late final int highland;
  late final int routeTypeMissing;
  late final List<String> municipalityChoices;

  int get coastalPercent =>
      coastal + highland == 0 ? 0 : (coastal / (coastal + highland) * 100).round();
  int get highlandPercent =>
      coastal + highland == 0 ? 0 : (highland / (coastal + highland) * 100).round();

  static _TripStats compute(
    List<SavedTripPlan> all, {
    required DateTimeRange? range,
    required String? municipality,
    required String? startMunicipality,
    required String? endMunicipality,
    required String? duration,
    required String? routeType,
  }) {
    final filtered = all.where((plan) {
      if (range != null) {
        final day = DateTime(plan.createdAt.year, plan.createdAt.month, plan.createdAt.day);
        final start = DateTime(range.start.year, range.start.month, range.start.day);
        final end = DateTime(range.end.year, range.end.month, range.end.day);
        if (day.isBefore(start) || day.isAfter(end)) return false;
      }
      if (municipality != null &&
          !_municipalitiesOf(plan).any((name) => _same(name, municipality))) {
        return false;
      }
      if (startMunicipality != null &&
          !_same(_municipalityOfName(plan.startName), startMunicipality) &&
          !_same(plan.startName, startMunicipality)) {
        return false;
      }
      if (endMunicipality != null &&
          !_same(_municipalityOfName(plan.endName), endMunicipality) &&
          !_same(plan.endName, endMunicipality)) {
        return false;
      }
      if (duration != null && _durationLabel(plan) != duration) return false;
      if (routeType != null && plan.routeType != routeType) return false;
      return true;
    }).toList();
    final stats = _TripStats(filtered).._fill();
    _shownStats = stats;
    return stats;
  }

  void _fill() {
    final destCounts = <String, int>{};
    final destMuni = <String, String>{};
    final muniCounts = <String, int>{};
    final startCounts = <String, int>{};
    final endCounts = <String, int>{};
    final routeCounts = <String, int>{};
    final durationCounts = <String, int>{
      for (final label in const [
        '1-day trips',
        '2-day trips',
        '3-day trips',
        '4–5-day trips',
        '6–7-day trips',
        '8 or more days',
      ])
        label: 0,
    };
    final allMunis = <String>{};
    var daySum = 0;
    var dayPlans = 0;
    var coastalCount = 0;
    var highlandCount = 0;
    var missingRoute = 0;
    final choices = <String>{
      for (final m in municipalities) m.name,
    };

    for (final plan in plans) {
      final spots = <String>{};
      for (final day in plan.daySpotNames) {
        for (final raw in day) {
          final name = raw.trim();
          if (name.isEmpty) continue;
          spots.add(name.toLowerCase());
          destMuni.putIfAbsent(name.toLowerCase(), () => name);
        }
      }
      for (final key in spots) {
        destCounts[key] = (destCounts[key] ?? 0) + 1;
      }
      final munis = _municipalitiesOf(plan);
      allMunis.addAll(munis);
      choices.addAll(munis);
      for (final muni in munis) {
        muniCounts[muni] = (muniCounts[muni] ?? 0) + 1;
      }
      final start = plan.startName.trim();
      final end = plan.endName.trim();
      if (start.isNotEmpty) startCounts[start] = (startCounts[start] ?? 0) + 1;
      if (end.isNotEmpty) endCounts[end] = (endCounts[end] ?? 0) + 1;
      if (start.isNotEmpty && end.isNotEmpty) {
        final pair = '$start → $end';
        routeCounts[pair] = (routeCounts[pair] ?? 0) + 1;
      }
      final label = _durationLabel(plan);
      if (label != null) {
        durationCounts[label] = (durationCounts[label] ?? 0) + 1;
        daySum += _dayCount(plan);
        dayPlans++;
      }
      if (plan.routeType == 'coastal') {
        coastalCount++;
      } else if (plan.routeType == 'highland') {
        highlandCount++;
      } else {
        missingRoute++;
      }
    }

    distinctDestinations = destCounts.length;
    distinctMunicipalities = allMunis.length;
    averageDays = dayPlans == 0 ? null : daySum / dayPlans;
    coastal = coastalCount;
    highland = highlandCount;
    routeTypeMissing = missingRoute;
    destinations = _rank(destCounts, (key) {
      final muni = _municipalityOfName(destMuni[key] ?? key);
      return (destMuni[key] ?? key, muni);
    });
    municipalityRanks = _rank(muniCounts, (key) => (key, ''));
    starts = _rank(startCounts, (key) => (key, ''));
    ends = _rank(endCounts, (key) => (key, ''));
    routes = _rank(routeCounts, (key) => (key, ''));
    durations = [
      for (final entry in durationCounts.entries)
        _RankRow(entry.key, entry.value),
    ];
    municipalityChoices = choices.toList()..sort();
  }

  List<_TrendPoint> trend(_TrendGrain grain) {
    final counts = <String, int>{};
    final labels = <String, String>{};
    for (final plan in plans) {
      final at = plan.createdAt.toLocal();
      final String key;
      final String label;
      switch (grain) {
        case _TrendGrain.daily:
          key = '${at.year}-${at.month}-${at.day}';
          label = '${at.month}/${at.day}';
        case _TrendGrain.weekly:
          final start = at.subtract(Duration(days: at.weekday - 1));
          key = '${start.year}-${start.month}-${start.day}';
          label = '${start.month}/${start.day}';
        case _TrendGrain.monthly:
          key = '${at.year}-${at.month}';
          label = '${_month(at.month)} ${at.year}';
        case _TrendGrain.yearly:
          key = '${at.year}';
          label = '${at.year}';
      }
      counts[key] = (counts[key] ?? 0) + 1;
      labels[key] = label;
    }
    final keys = counts.keys.toList()..sort();
    return [for (final key in keys) _TrendPoint(labels[key] ?? key, counts[key]!)];
  }
}

List<_RankRow> _rank(
  Map<String, int> counts,
  (String, String) Function(String key) label,
) {
  final keys = counts.keys.toList()
    ..sort((a, b) => counts[b]!.compareTo(counts[a]!));
  return [
    for (final key in keys)
      _RankRow(label(key).$1, counts[key]!, detail: label(key).$2),
  ];
}

Map<String, dynamic> _normalizeTrip(Map<String, dynamic> raw, String id) {
  final data = Map<String, dynamic>.from(raw);
  data['id'] = data['id'] ?? id;
  final created = data['createdAt'];
  if (created is Timestamp) {
    data['createdAt'] = created.toDate().toIso8601String();
  }
  return data;
}

int _dayCount(SavedTripPlan plan) {
  if (plan.tripDays > 0) return plan.tripDays;
  return plan.daySpotNames.where((day) => day.isNotEmpty).length;
}

String? _durationLabel(SavedTripPlan plan) {
  final days = _dayCount(plan);
  if (days <= 0) return null;
  if (days == 1) return '1-day trips';
  if (days == 2) return '2-day trips';
  if (days == 3) return '3-day trips';
  if (days <= 5) return '4–5-day trips';
  if (days <= 7) return '6–7-day trips';
  return '8 or more days';
}

bool _same(String a, String b) => a.trim().toLowerCase() == b.trim().toLowerCase();

String _municipalityOfName(String name) {
  final trimmed = name.trim();
  if (trimmed.isEmpty) return '';
  for (final municipality in municipalities) {
    if (_same(municipality.name, trimmed) || _same(municipality.shortName, trimmed)) {
      return municipality.name;
    }
  }
  final spot = findTouristSpotByNameFuzzy(trimmed);
  final location = spot?.location.trim() ?? '';
  if (location.isNotEmpty) return location;
  return '';
}

Set<String> _municipalitiesOf(SavedTripPlan plan) {
  final names = <String>{};
  void add(String raw) {
    final muni = _municipalityOfName(raw);
    if (muni.isNotEmpty) names.add(muni);
  }

  add(plan.startName);
  add(plan.endName);
  for (final day in plan.daySpotNames) {
    for (final spot in day) {
      add(spot);
    }
  }
  return names;
}

String _rangeLabel(DateTimeRange range) {
  String one(DateTime d) => '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
  return '${one(range.start)} – ${one(range.end)}';
}

String _month(int month) {
  const names = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];
  return names[month - 1];
}

String _filterSummary() {
  return 'Filters follow the dashboard selection. Personal tourist details are omitted.';
}

Future<pw.Document> _pdfDocument(_TripStats stats, DateTime generated) async {
  final doc = pw.Document();
  doc.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      build: (context) => [
        pw.Text('OPTACA Portal', style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold)),
        pw.Text('Trip Planner Analytics'),
        pw.Text('Generated ${generated.toLocal()}'),
        pw.SizedBox(height: 6),
        pw.Text(_filterSummary()),
        pw.Text('These figures are planned itineraries, not confirmed arrivals.'),
        pw.SizedBox(height: 12),
        pw.Text('Summary', style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
        pw.Bullet(text: 'Total trip plans: ${stats.plans.length}'),
        pw.Bullet(text: 'Planned destinations: ${stats.distinctDestinations}'),
        pw.Bullet(
          text: 'Average travel duration: ${stats.averageDays == null ? '—' : stats.averageDays!.toStringAsFixed(1)} days',
        ),
        pw.Bullet(text: 'Municipalities covered: ${stats.distinctMunicipalities}'),
        pw.SizedBox(height: 10),
        _pdfTable('Popular destinations', ['Destination', 'Municipality', 'Plans'], [
          for (final row in stats.destinations.take(10))
            [row.label, row.detail, '${row.count}'],
        ]),
        _pdfTable('Municipalities', ['Municipality', 'Itineraries'], [
          for (final row in stats.municipalityRanks) [row.label, '${row.count}'],
        ]),
        _pdfTable('Travel duration', ['Group', 'Plans'], [
          for (final row in stats.durations) [row.label, '${row.count}'],
        ]),
        _pdfTable('Routes', ['Item', 'Plans'], [
          ['Coastal (stored)', '${stats.coastal}'],
          ['Highland (stored)', '${stats.highland}'],
          ['Route type not recorded', '${stats.routeTypeMissing}'],
          for (final row in stats.starts.take(8)) ['Start: ${row.label}', '${row.count}'],
          for (final row in stats.ends.take(8)) ['End: ${row.label}', '${row.count}'],
          for (final row in stats.routes.take(8)) [row.label, '${row.count}'],
        ]),
        _pdfTable('Saved over time', ['Period', 'Plans'], [
          for (final point in stats.trend(_TrendGrain.monthly))
            [point.label, '${point.count}'],
        ]),
      ],
    ),
  );
  return doc;
}

pw.Widget _pdfTable(String title, List<String> headers, List<List<String>> rows) {
  return pw.Column(
    crossAxisAlignment: pw.CrossAxisAlignment.start,
    children: [
      pw.SizedBox(height: 10),
      pw.Text(title, style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
      pw.SizedBox(height: 4),
      pw.TableHelper.fromTextArray(headers: headers, data: rows.isEmpty ? [['—', '0']] : rows),
    ],
  );
}

Future<Uint8List> _pdfBytes(_TripStats stats, DateTime generated) async {
  final doc = await _pdfDocument(stats, generated);
  return doc.save();
}

List<int> _xlsxBytes(_TripStats stats, DateTime generated) {
  final book = Excel.createExcel();
  final defaultSheet = book.getDefaultSheet();
  final sheet = book['Trip planner'];
  void row(List<String> cells) {
    sheet.appendRow([for (final cell in cells) TextCellValue(cell)]);
  }

  row(['OPTACA Portal']);
  row(['Trip Planner Analytics']);
  row(['Generated', generated.toLocal().toString()]);
  row(['Note', 'Planned itineraries, not confirmed arrivals. No personal tourist data.']);
  row([]);
  row(['Metric', 'Value']);
  row(['Total trip plans', '${stats.plans.length}']);
  row(['Planned destinations', '${stats.distinctDestinations}']);
  row([
    'Average travel duration (days)',
    stats.averageDays == null ? '' : stats.averageDays!.toStringAsFixed(1),
  ]);
  row(['Municipalities covered', '${stats.distinctMunicipalities}']);
  row([]);
  row(['Popular destinations', 'Municipality', 'Plans']);
  for (final item in stats.destinations.take(10)) {
    row([item.label, item.detail, '${item.count}']);
  }
  row([]);
  row(['Municipality', 'Itineraries']);
  for (final item in stats.municipalityRanks) {
    row([item.label, '${item.count}']);
  }
  row([]);
  row(['Travel duration', 'Plans']);
  for (final item in stats.durations) {
    row([item.label, '${item.count}']);
  }
  row([]);
  row(['Route type', 'Plans']);
  row(['Coastal (stored)', '${stats.coastal}']);
  row(['Highland (stored)', '${stats.highland}']);
  row(['Not recorded', '${stats.routeTypeMissing}']);
  row([]);
  row(['Starting municipality', 'Plans']);
  for (final item in stats.starts) {
    row([item.label, '${item.count}']);
  }
  row([]);
  row(['Ending municipality', 'Plans']);
  for (final item in stats.ends) {
    row([item.label, '${item.count}']);
  }
  row([]);
  row(['Route', 'Plans']);
  for (final item in stats.routes) {
    row([item.label, '${item.count}']);
  }
  row([]);
  row(['Month', 'Plans']);
  for (final point in stats.trend(_TrendGrain.monthly)) {
    row([point.label, '${point.count}']);
  }
  if (defaultSheet != null && defaultSheet != 'Trip planner') {
    book.delete(defaultSheet);
  }
  final encoded = book.encode();
  return encoded ?? const <int>[];
}

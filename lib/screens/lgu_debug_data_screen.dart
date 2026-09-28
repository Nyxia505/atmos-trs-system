import 'dart:async';

import 'package:atmos_trs_system/data/misamis_occidental_municipalities.dart';
import 'package:atmos_trs_system/models/tourist_spot.dart';
import 'package:atmos_trs_system/services/lgu_debug_data_service.dart';
import 'package:atmos_trs_system/utils/municipality_helper.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Full-screen Debug data hub: live charts + seed + full purge (incl. stays).
class LguDebugDataScreen extends StatefulWidget {
  const LguDebugDataScreen({
    super.key,
    required this.municipalityId,
    required this.municipalityName,
    this.spots = const [],
    this.onDone,
  });

  final String municipalityId;
  final String municipalityName;
  final List<TouristSpot> spots;
  final VoidCallback? onDone;

  static Future<void> open({
    required BuildContext context,
    required String municipalityId,
    required String municipalityName,
    List<TouristSpot> spots = const [],
    VoidCallback? onDone,
  }) {
    final munId = normalizeMunicipalityId(municipalityId);
    return Navigator.of(context).push<void>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => LguDebugDataScreen(
          municipalityId: munId,
          municipalityName: municipalityName,
          spots: spots,
          onDone: onDone,
        ),
      ),
    );
  }

  @override
  State<LguDebugDataScreen> createState() => _LguDebugDataScreenState();
}

class _LguDebugDataScreenState extends State<LguDebugDataScreen>
    with SingleTickerProviderStateMixin {
  static const Color _orange = Color(0xFFF97316);
  static const Color _bg = Color(0xFFF8FAFC);
  static const Color _card = Colors.white;
  static const Color _text = Color(0xFF0F172A);
  static const Color _muted = Color(0xFF64748B);

  late TabController _tabs;
  LguDebugDataSnapshot? _snapshot;
  bool _loadingStats = true;
  String? _statsError;

  // Scope for charts: empty = province-wide
  late String _chartScopeMunId;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 3, vsync: this);
    _chartScopeMunId = widget.municipalityId;
    unawaited(_refreshStats());
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  Future<void> _refreshStats() async {
    setState(() {
      _loadingStats = true;
      _statsError = null;
    });
    try {
      final snap = await LguDebugDataService.loadSnapshot(
        municipalityId:
            _chartScopeMunId.isEmpty ? null : _chartScopeMunId,
      );
      if (!mounted) return;
      setState(() {
        _snapshot = snap;
        _loadingStats = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loadingStats = false;
        _statsError = e.toString();
      });
    }
  }

  void _afterMutation() {
    widget.onDone?.call();
    unawaited(_refreshStats());
  }

  String _munLabel(String id) {
    final key = normalizeMunicipalityId(id);
    if (key.isEmpty || key == 'unknown') return 'Unknown';
    for (final m in getMisamisOccidentalMunicipalities()) {
      if (normalizeMunicipalityId(m.id) == key) return m.name;
    }
    return id;
  }

  @override
  Widget build(BuildContext context) {
    final titleMun = widget.municipalityName.trim().isEmpty
        ? 'Misamis Occidental'
        : widget.municipalityName;
    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: _card,
        foregroundColor: _text,
        surfaceTintColor: _card,
        elevation: 0,
        centerTitle: false,
        iconTheme: const IconThemeData(color: _text),
        actionsIconTheme: const IconThemeData(color: _text),
        leadingWidth: 104,
        leading: Padding(
          padding: const EdgeInsets.only(left: 12, top: 10, bottom: 10),
          child: OutlinedButton.icon(
            onPressed: () => Navigator.of(context).maybePop(),
            icon: const Icon(Icons.arrow_back_rounded, size: 18),
            label: const Text('Back'),
            style: OutlinedButton.styleFrom(
              foregroundColor: _text,
              side: const BorderSide(color: Color(0xFFCBD5E1)),
              padding: const EdgeInsets.symmetric(horizontal: 10),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
              textStyle: const TextStyle(
                fontWeight: FontWeight.w600,
                fontSize: 13,
              ),
            ),
          ),
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Debug data',
              style: TextStyle(
                color: _text,
                fontWeight: FontWeight.w700,
                fontSize: 18,
              ),
            ),
            Text(
              titleMun,
              style: const TextStyle(
                fontSize: 12,
                color: _muted,
                fontWeight: FontWeight.w400,
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Refresh charts',
            onPressed: _loadingStats ? null : _refreshStats,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
        bottom: TabBar(
          controller: _tabs,
          labelColor: _orange,
          unselectedLabelColor: _muted,
          indicatorColor: _orange,
          tabs: const [
            Tab(text: 'Overview'),
            Tab(text: 'Seed'),
            Tab(text: 'Full purge'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabs,
        children: [
          _OverviewTab(
            loading: _loadingStats,
            error: _statsError,
            snapshot: _snapshot,
            chartScopeMunId: _chartScopeMunId,
            defaultMunId: widget.municipalityId,
            munLabel: _munLabel,
            onScopeChanged: (id) {
              setState(() => _chartScopeMunId = id);
              unawaited(_refreshStats());
            },
            orange: _orange,
            card: _card,
            text: _text,
            muted: _muted,
          ),
          _SeedTab(
            municipalityId: widget.municipalityId.isEmpty
                ? 'oroquieta'
                : widget.municipalityId,
            municipalityName: widget.municipalityName,
            spots: widget.spots,
            onDone: _afterMutation,
            orange: _orange,
            card: _card,
            muted: _muted,
          ),
          _PurgeTab(
            municipalityId: widget.municipalityId,
            municipalityName: widget.municipalityName,
            onDone: _afterMutation,
            orange: _orange,
            card: _card,
            muted: _muted,
          ),
        ],
      ),
    );
  }
}

// ── Overview / charts ───────────────────────────────────────────────

class _OverviewTab extends StatelessWidget {
  const _OverviewTab({
    required this.loading,
    required this.error,
    required this.snapshot,
    required this.chartScopeMunId,
    required this.defaultMunId,
    required this.munLabel,
    required this.onScopeChanged,
    required this.orange,
    required this.card,
    required this.text,
    required this.muted,
  });

  final bool loading;
  final String? error;
  final LguDebugDataSnapshot? snapshot;
  final String chartScopeMunId;
  final String defaultMunId;
  final String Function(String) munLabel;
  final ValueChanged<String> onScopeChanged;
  final Color orange;
  final Color card;
  final Color text;
  final Color muted;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
      children: [
        _ScopeChipRow(
          chartScopeMunId: chartScopeMunId,
          defaultMunId: defaultMunId,
          munLabel: munLabel,
          onScopeChanged: onScopeChanged,
          orange: orange,
        ),
        const SizedBox(height: 12),
        if (loading)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 48),
            child: Center(child: CircularProgressIndicator()),
          )
        else if (error != null)
          _Card(
            color: card,
            child: Text(
              error!,
              style: const TextStyle(color: Color(0xFFDC2626)),
            ),
          )
        else if (snapshot != null) ...[
          _StatStrip(
            items: [
              _StatItem('Tourists', snapshot!.totalTourists, Icons.people_outline),
              _StatItem(
                'Check-ins',
                snapshot!.totalCheckIns,
                Icons.qr_code_scanner_outlined,
              ),
              _StatItem(
                'Est. stays',
                snapshot!.totalStays,
                Icons.hotel_outlined,
              ),
              _StatItem(
                'Reviews',
                snapshot!.totalReviews,
                Icons.rate_review_outlined,
              ),
            ],
            card: card,
            text: text,
            muted: muted,
            orange: orange,
          ),
          const SizedBox(height: 16),
          _ChartCard(
            title: 'Registered tourists by area',
            subtitle: 'Home address / registrationMunicipalityId',
            card: card,
            text: text,
            muted: muted,
            child: _BarChartBlock(
              data: _topN(snapshot!.touristsByMunicipality, 12),
              labelOf: munLabel,
              color: orange,
              muted: muted,
            ),
          ),
          const SizedBox(height: 16),
          _ChartCard(
            title: 'Spots visited',
            subtitle: 'Attraction / LGU QR check-ins',
            card: card,
            text: text,
            muted: muted,
            child: _BarChartBlock(
              data: _topN(snapshot!.checkInsBySpot, 10),
              labelOf: (s) => s.length > 18 ? '${s.substring(0, 16)}…' : s,
              color: const Color(0xFF0EA5E9),
              muted: muted,
            ),
          ),
          const SizedBox(height: 16),
          LayoutBuilder(
            builder: (context, c) {
              final sideBySide = c.maxWidth > 640;
              final visits = _ChartCard(
                title: 'Visits by LGU',
                subtitle: 'Check-in municipality',
                card: card,
                text: text,
                muted: muted,
                child: _DonutBlock(
                  data: snapshot!.checkInsByMunicipality,
                  labelOf: munLabel,
                  muted: muted,
                ),
              );
              final stays = _ChartCard(
                title: 'Establishment stays',
                subtitle: 'By status (pending → confirmed)',
                card: card,
                text: text,
                muted: muted,
                child: _DonutBlock(
                  data: snapshot!.staysByStatus,
                  labelOf: (s) => s,
                  muted: muted,
                ),
              );
              if (sideBySide) {
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: visits),
                    const SizedBox(width: 12),
                    Expanded(child: stays),
                  ],
                );
              }
              return Column(
                children: [
                  visits,
                  const SizedBox(height: 12),
                  stays,
                ],
              );
            },
          ),
        ],
      ],
    );
  }

  static Map<String, int> _topN(Map<String, int> src, int n) {
    final entries = src.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return Map.fromEntries(entries.take(n));
  }
}

class _ScopeChipRow extends StatelessWidget {
  const _ScopeChipRow({
    required this.chartScopeMunId,
    required this.defaultMunId,
    required this.munLabel,
    required this.onScopeChanged,
    required this.orange,
  });

  final String chartScopeMunId;
  final String defaultMunId;
  final String Function(String) munLabel;
  final ValueChanged<String> onScopeChanged;
  final Color orange;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        ChoiceChip(
          label: const Text('All province'),
          selected: chartScopeMunId.isEmpty,
          selectedColor: orange.withValues(alpha: 0.2),
          onSelected: (_) => onScopeChanged(''),
        ),
        if (defaultMunId.isNotEmpty)
          ChoiceChip(
            label: Text(munLabel(defaultMunId)),
            selected: chartScopeMunId == defaultMunId,
            selectedColor: orange.withValues(alpha: 0.2),
            onSelected: (_) => onScopeChanged(defaultMunId),
          ),
      ],
    );
  }
}

class _StatItem {
  const _StatItem(this.label, this.value, this.icon);
  final String label;
  final int value;
  final IconData icon;
}

class _StatStrip extends StatelessWidget {
  const _StatStrip({
    required this.items,
    required this.card,
    required this.text,
    required this.muted,
    required this.orange,
  });

  final List<_StatItem> items;
  final Color card;
  final Color text;
  final Color muted;
  final Color orange;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, c) {
        final wide = c.maxWidth > 700;
        final children = items
            .map(
              (it) => Expanded(
                child: _Card(
                  color: card,
                  child: Row(
                    children: [
                      Icon(it.icon, color: orange, size: 22),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '${it.value}',
                              style: TextStyle(
                                fontSize: 22,
                                fontWeight: FontWeight.w700,
                                color: text,
                              ),
                            ),
                            Text(
                              it.label,
                              style: TextStyle(fontSize: 12, color: muted),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            )
            .toList();
        if (wide) {
          return Row(
            children: [
              for (var i = 0; i < children.length; i++) ...[
                if (i > 0) const SizedBox(width: 10),
                children[i],
              ],
            ],
          );
        }
        return Column(
          children: [
            Row(children: [children[0], const SizedBox(width: 10), children[1]]),
            const SizedBox(height: 10),
            Row(children: [children[2], const SizedBox(width: 10), children[3]]),
          ],
        );
      },
    );
  }
}

class _ChartCard extends StatelessWidget {
  const _ChartCard({
    required this.title,
    required this.subtitle,
    required this.child,
    required this.card,
    required this.text,
    required this.muted,
  });

  final String title;
  final String subtitle;
  final Widget child;
  final Color card;
  final Color text;
  final Color muted;

  @override
  Widget build(BuildContext context) {
    return _Card(
      color: card,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(
              fontWeight: FontWeight.w700,
              fontSize: 15,
              color: text,
            ),
          ),
          const SizedBox(height: 2),
          Text(subtitle, style: TextStyle(fontSize: 12, color: muted)),
          const SizedBox(height: 16),
          child,
        ],
      ),
    );
  }
}

class _Card extends StatelessWidget {
  const _Card({required this.color, required this.child});
  final Color color;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: child,
    );
  }
}

class _BarChartBlock extends StatelessWidget {
  const _BarChartBlock({
    required this.data,
    required this.labelOf,
    required this.color,
    required this.muted,
  });

  final Map<String, int> data;
  final String Function(String) labelOf;
  final Color color;
  final Color muted;

  @override
  Widget build(BuildContext context) {
    if (data.isEmpty) {
      return SizedBox(
        height: 160,
        child: Center(
          child: Text('No data yet', style: TextStyle(color: muted)),
        ),
      );
    }
    final keys = data.keys.toList();
    final maxY = data.values.fold<int>(0, (a, b) => a > b ? a : b).toDouble();
    return SizedBox(
      height: 220,
      child: BarChart(
        BarChartData(
          maxY: maxY <= 0 ? 1 : maxY * 1.15,
          gridData: FlGridData(
            show: true,
            drawVerticalLine: false,
            getDrawingHorizontalLine: (v) => FlLine(
              color: muted.withValues(alpha: 0.15),
              strokeWidth: 1,
            ),
          ),
          borderData: FlBorderData(show: false),
          titlesData: FlTitlesData(
            topTitles:
                const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            rightTitles:
                const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            leftTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 28,
                getTitlesWidget: (v, _) => Text(
                  v.toInt().toString(),
                  style: TextStyle(fontSize: 10, color: muted),
                ),
              ),
            ),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 42,
                getTitlesWidget: (v, meta) {
                  final i = v.toInt();
                  if (i < 0 || i >= keys.length) {
                    return const SizedBox.shrink();
                  }
                  return Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Transform.rotate(
                      angle: -0.6,
                      child: Text(
                        labelOf(keys[i]),
                        style: TextStyle(fontSize: 9, color: muted),
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
          barGroups: [
            for (var i = 0; i < keys.length; i++)
              BarChartGroupData(
                x: i,
                barRods: [
                  BarChartRodData(
                    toY: (data[keys[i]] ?? 0).toDouble(),
                    color: color,
                    width: 14,
                    borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(4),
                    ),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

class _DonutBlock extends StatelessWidget {
  const _DonutBlock({
    required this.data,
    required this.labelOf,
    required this.muted,
  });

  final Map<String, int> data;
  final String Function(String) labelOf;
  final Color muted;

  static const _palette = [
    Color(0xFFF97316),
    Color(0xFF0EA5E9),
    Color(0xFF22C55E),
    Color(0xFFA855F7),
    Color(0xFFEAB308),
    Color(0xFFEF4444),
    Color(0xFF14B8A6),
    Color(0xFF64748B),
  ];

  @override
  Widget build(BuildContext context) {
    if (data.isEmpty || data.values.every((v) => v == 0)) {
      return SizedBox(
        height: 160,
        child: Center(
          child: Text('No data yet', style: TextStyle(color: muted)),
        ),
      );
    }
    final entries = data.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final total = entries.fold<int>(0, (a, e) => a + e.value).toDouble();
    return Column(
      children: [
        SizedBox(
          height: 140,
          child: PieChart(
            PieChartData(
              sectionsSpace: 2,
              centerSpaceRadius: 32,
              sections: [
                for (var i = 0; i < entries.length; i++)
                  PieChartSectionData(
                    value: entries[i].value.toDouble(),
                    title: total > 0
                        ? '${((entries[i].value / total) * 100).round()}%'
                        : '',
                    color: _palette[i % _palette.length],
                    radius: 40,
                    titleStyle: const TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      color: Colors.white,
                    ),
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 8),
        ...entries.take(6).map((e) {
          final i = entries.indexOf(e);
          return Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Row(
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: _palette[i % _palette.length],
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    labelOf(e.key),
                    style: TextStyle(fontSize: 11, color: muted),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Text(
                  '${e.value}',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: muted,
                  ),
                ),
              ],
            ),
          );
        }),
      ],
    );
  }
}

// ── Seed tab ────────────────────────────────────────────────────────

class _SeedTab extends StatefulWidget {
  const _SeedTab({
    required this.municipalityId,
    required this.municipalityName,
    required this.spots,
    required this.onDone,
    required this.orange,
    required this.card,
    required this.muted,
  });

  final String municipalityId;
  final String municipalityName;
  final List<TouristSpot> spots;
  final VoidCallback onDone;
  final Color orange;
  final Color card;
  final Color muted;

  @override
  State<_SeedTab> createState() => _SeedTabState();
}

class _SeedTabState extends State<_SeedTab> {
  late String _selectedMunId;
  bool _seedAll = false;
  bool _useSplit = true;
  final _totalCtrl = TextEditingController(text: '20');
  final _localCtrl = TextEditingController(text: '14');
  final _foreignCtrl = TextEditingController(text: '6');
  final _checkInsCtrl = TextEditingController(text: '2');
  final Set<String> _selectedSpotIds = {};
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _selectedMunId = widget.municipalityId;
    for (final s in widget.spots) {
      if (s.id.trim().isNotEmpty) _selectedSpotIds.add(s.id);
    }
  }

  @override
  void dispose() {
    _totalCtrl.dispose();
    _localCtrl.dispose();
    _foreignCtrl.dispose();
    _checkInsCtrl.dispose();
    super.dispose();
  }

  int _parse(TextEditingController c, {int fallback = 0}) {
    return int.tryParse(c.text.trim()) ?? fallback;
  }

  Future<void> _run() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final checkIns = _parse(_checkInsCtrl, fallback: 2).clamp(1, 7);
      final spotIds = _selectedSpotIds.toList();
      final LguDebugSeedResult result;
      if (_useSplit) {
        final local = _parse(_localCtrl).clamp(0, 200);
        final foreign = _parse(_foreignCtrl).clamp(0, 200);
        if (local + foreign < 1) {
          throw StateError('Enter at least 1 Filipino or foreign tourist.');
        }
        result = await LguDebugDataService.seedAnalyticsData(
          municipalityId: _selectedMunId,
          seedAllMunicipalities: _seedAll,
          localCount: local,
          foreignCount: foreign,
          spotIds: spotIds.isEmpty ? null : spotIds,
          checkInsPerTourist: checkIns,
        );
      } else {
        final total = _parse(_totalCtrl, fallback: 20).clamp(1, 200);
        result = await LguDebugDataService.seedAnalyticsData(
          municipalityId: _selectedMunId,
          seedAllMunicipalities: _seedAll,
          touristCount: total,
          spotIds: spotIds.isEmpty ? null : spotIds,
          checkInsPerTourist: checkIns,
        );
      }
      if (!mounted) return;
      widget.onDone();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(result.summaryMessage),
          backgroundColor: const Color(0xFF10B981),
        ),
      );
      setState(() => _busy = false);
    } catch (e) {
      setState(() {
        _busy = false;
        _error = e.toString().replaceFirst('Bad state: ', '');
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final muns = getMisamisOccidentalMunicipalities();
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
      children: [
        _Card(
          color: widget.card,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Seed registered tourists + visit check-ins',
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  color: Colors.grey.shade900,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Locals get home address in the selected LGU (Registered Tourists). '
                'Foreign visitors get check-ins only — they do not inflate the registry.',
                style: TextStyle(fontSize: 13, color: widget.muted),
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                initialValue: _selectedMunId,
                decoration: const InputDecoration(
                  labelText: 'Primary LGU',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
                items: [
                  for (final m in muns)
                    DropdownMenuItem(value: m.id, child: Text(m.name)),
                ],
                onChanged: _busy
                    ? null
                    : (v) {
                        if (v != null) setState(() => _selectedMunId = v);
                      },
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Seed all municipalities'),
                subtitle: const Text('Repeats the same counts for every LGU'),
                value: _seedAll,
                activeThumbColor: Colors.white,
                activeTrackColor: widget.orange,
                onChanged:
                    _busy ? null : (v) => setState(() => _seedAll = v),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Split local / foreign'),
                value: _useSplit,
                activeThumbColor: Colors.white,
                activeTrackColor: widget.orange,
                onChanged:
                    _busy ? null : (v) => setState(() => _useSplit = v),
              ),
              if (_useSplit) ...[
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _localCtrl,
                        enabled: !_busy,
                        keyboardType: TextInputType.number,
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly,
                        ],
                        decoration: const InputDecoration(
                          labelText: 'Locals (address)',
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: TextField(
                        controller: _foreignCtrl,
                        enabled: !_busy,
                        keyboardType: TextInputType.number,
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly,
                        ],
                        decoration: const InputDecoration(
                          labelText: 'Foreign visitors',
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                      ),
                    ),
                  ],
                ),
              ] else
                TextField(
                  controller: _totalCtrl,
                  enabled: !_busy,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  decoration: const InputDecoration(
                    labelText: 'Total tourists',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
              const SizedBox(height: 12),
              TextField(
                controller: _checkInsCtrl,
                enabled: !_busy,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: const InputDecoration(
                  labelText: 'Check-ins per tourist',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
              ),
              if (widget.spots.isNotEmpty) ...[
                const SizedBox(height: 12),
                Text(
                  'Spots for check-ins',
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    color: Colors.grey.shade800,
                  ),
                ),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final s in widget.spots)
                      FilterChip(
                        label: Text(s.name),
                        selected: _selectedSpotIds.contains(s.id),
                        onSelected: _busy
                            ? null
                            : (sel) {
                                setState(() {
                                  if (sel) {
                                    _selectedSpotIds.add(s.id);
                                  } else {
                                    _selectedSpotIds.remove(s.id);
                                  }
                                });
                              },
                      ),
                  ],
                ),
              ],
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(
                  _error!,
                  style: const TextStyle(color: Color(0xFFDC2626), fontSize: 13),
                ),
              ],
              const SizedBox(height: 16),
              FilledButton(
                onPressed: _busy ? null : _run,
                style: FilledButton.styleFrom(
                  backgroundColor: widget.orange,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                child: _busy
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Text('Seed now'),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ── Full purge tab ──────────────────────────────────────────────────

class _PurgeTab extends StatefulWidget {
  const _PurgeTab({
    required this.municipalityId,
    required this.municipalityName,
    required this.onDone,
    required this.orange,
    required this.card,
    required this.muted,
  });

  final String municipalityId;
  final String municipalityName;
  final VoidCallback onDone;
  final Color orange;
  final Color card;
  final Color muted;

  @override
  State<_PurgeTab> createState() => _PurgeTabState();
}

class _PurgeTabState extends State<_PurgeTab> {
  late bool _thisLguOnly;
  final _confirmCtrl = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _thisLguOnly = widget.municipalityId.trim().isNotEmpty;
  }

  @override
  void dispose() {
    _confirmCtrl.dispose();
    super.dispose();
  }

  Future<void> _run() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final result = await LguDebugDataService.clearTouristData(
        municipalityId: _thisLguOnly ? widget.municipalityId : null,
        confirmPhrase: _confirmCtrl.text,
      );
      if (!mounted) return;
      widget.onDone();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(result.summaryMessage),
          backgroundColor: const Color(0xFFDC2626),
        ),
      );
      setState(() {
        _busy = false;
        _confirmCtrl.clear();
      });
    } catch (e) {
      setState(() {
        _busy = false;
        _error = e.toString().replaceFirst('Bad state: ', '');
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final label = widget.municipalityName.trim().isEmpty
        ? 'this LGU'
        : widget.municipalityName;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
      children: [
        _Card(
          color: widget.card,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Row(
                children: [
                  Icon(Icons.warning_amber_rounded, color: Color(0xFFDC2626)),
                  SizedBox(width: 8),
                  Text(
                    'Full purge',
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 16,
                      color: Color(0xFFDC2626),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                _thisLguOnly
                    ? 'Deletes registered tourists, QR check-ins, establishment '
                        'stay requests, and stay reviews for $label — so the '
                        'establishment dashboard has no orphan pending/confirmed stays.'
                    : 'Deletes ALL tourist profiles, check-ins, establishment '
                        'stay requests, and stay reviews in the project. '
                        'Staff accounts and tourist spots are kept.',
                style: TextStyle(fontSize: 13, color: widget.muted),
              ),
              const SizedBox(height: 12),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: Text('Only $label'),
                subtitle: const Text('Off = clear entire tourist + stay database'),
                value: _thisLguOnly,
                activeThumbColor: Colors.white,
                activeTrackColor: widget.orange,
                onChanged: _busy
                    ? null
                    : (v) => setState(() => _thisLguOnly = v),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _confirmCtrl,
                enabled: !_busy,
                decoration: const InputDecoration(
                  labelText: 'Type CLEAR ALL TOURISTS',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
              ),
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(
                  _error!,
                  style: const TextStyle(color: Color(0xFFDC2626), fontSize: 13),
                ),
              ],
              const SizedBox(height: 16),
              FilledButton(
                onPressed: _busy ? null : _run,
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFFDC2626),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                child: _busy
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Text('Run full purge'),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

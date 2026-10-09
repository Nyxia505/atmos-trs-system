import 'package:atmos_trs_system/config/ae_register_schema.dart';
import 'package:atmos_trs_system/services/establishment_approval_service.dart';
import 'package:atmos_trs_system/utils/checkin_visitor_count.dart';
import 'package:atmos_trs_system/widgets/ae_register/ae_register_viewer_screen.dart';
import 'package:atmos_trs_system/widgets/establishment_dss_charts.dart';
import 'package:atmos_trs_system/widgets/establishment_insights_board.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import 'package:atmos_trs_system/features/governor/theme/governor_dashboard_tokens.dart';
import 'package:atmos_trs_system/features/governor/widgets/charts/governor_donut_chart.dart';

/// Kind of entity shown on Governor L3 analytics.
enum GovernorEntityAnalyticsKind { spot, establishment }

/// Governor L3: full analytics for one tourist spot or establishment.
class GovernorEntityAnalyticsScreen extends StatelessWidget {
  const GovernorEntityAnalyticsScreen._({
    required this.kind,
    required this.municipalityId,
    required this.municipalityName,
    required this.title,
    required this.subtitle,
    this.spot,
    this.establishment,
    this.checkIns = const [],
    this.tourists = const [],
  });

  factory GovernorEntityAnalyticsScreen.spot({
    required String municipalityId,
    required String municipalityName,
    required Map<String, dynamic> spot,
    required List<Map<String, dynamic>> checkIns,
    required List<Map<String, dynamic>> tourists,
  }) {
    final name = (spot['name'] ?? 'Spot').toString();
    final cat = (spot['category'] ?? 'Attraction').toString();
    return GovernorEntityAnalyticsScreen._(
      kind: GovernorEntityAnalyticsKind.spot,
      municipalityId: municipalityId,
      municipalityName: municipalityName,
      title: name,
      subtitle: '$cat · $municipalityName',
      spot: spot,
      checkIns: checkIns,
      tourists: tourists,
    );
  }

  factory GovernorEntityAnalyticsScreen.establishment({
    required String municipalityId,
    required String municipalityName,
    required EstablishmentRegistryEntry establishment,
    required List<Map<String, dynamic>> tourists,
  }) {
    return GovernorEntityAnalyticsScreen._(
      kind: GovernorEntityAnalyticsKind.establishment,
      municipalityId: municipalityId,
      municipalityName: municipalityName,
      title: establishment.businessName,
      subtitle:
          '${establishment.category.isEmpty ? 'Establishment' : establishment.category}'
          ' · $municipalityName',
      establishment: establishment,
      tourists: tourists,
    );
  }

  final GovernorEntityAnalyticsKind kind;
  final String municipalityId;
  final String municipalityName;
  final String title;
  final String subtitle;
  final Map<String, dynamic>? spot;
  final EstablishmentRegistryEntry? establishment;
  final List<Map<String, dynamic>> checkIns;
  final List<Map<String, dynamic>> tourists;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: GovernorDashboardTokens.background,
      appBar: AppBar(
        backgroundColor: Colors.white,
        foregroundColor: GovernorDashboardTokens.text,
        elevation: 0,
        leading: IconButton(
          tooltip: 'Back',
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: const TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: 17,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            Text(
              subtitle,
              style: const TextStyle(
                fontSize: 12,
                color: GovernorDashboardTokens.subtitle,
                fontWeight: FontWeight.w400,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
      body: kind == GovernorEntityAnalyticsKind.spot
          ? _SpotAnalyticsBody(
              spot: spot!,
              checkIns: checkIns,
              tourists: tourists,
            )
          : _EstablishmentAnalyticsBody(
              establishment: establishment!,
            ),
    );
  }
}

// ── Spot analytics ──────────────────────────────────────────────────

class _SpotAnalyticsBody extends StatelessWidget {
  const _SpotAnalyticsBody({
    required this.spot,
    required this.checkIns,
    required this.tourists,
  });

  final Map<String, dynamic> spot;
  final List<Map<String, dynamic>> checkIns;
  final List<Map<String, dynamic>> tourists;

  List<Map<String, dynamic>> get _matched {
    final spotId = (spot['id'] ?? spot['spotId'] ?? '').toString().trim();
    final spotName = (spot['name'] ?? '').toString().trim().toLowerCase();
    return [
      for (final c in checkIns)
        if (_matches(c, spotId, spotName)) c,
    ];
  }

  bool _matches(Map<String, dynamic> c, String spotId, String spotName) {
    final cid = (c['spotId'] ?? c['spot_id'] ?? '').toString().trim();
    final cname =
        (c['spot_name'] ?? c['spotName'] ?? '').toString().trim().toLowerCase();
    if (spotId.isNotEmpty && cid == spotId) return true;
    if (spotName.isNotEmpty && cname == spotName) return true;
    return false;
  }

  DateTime? _ts(Map<String, dynamic> c) {
    final raw = c['timestamp'] ?? c['createdAt'] ?? c['checkInAt'];
    if (raw == null) return null;
    if (raw is DateTime) return raw;
    if (raw is Timestamp) return raw.toDate();
    return DateTime.tryParse(raw.toString());
  }

  @override
  Widget build(BuildContext context) {
    final matched = _matched;
    final uids = <String>{};
    var male = 0;
    var female = 0;
    var filipino = 0;
    var foreign = 0;
    final byWeekday = List<int>.filled(7, 0);
    final byDay = <DateTime, int>{};
    final origins = <String, int>{};
    final now = DateTime.now();
    final start14 = DateTime(now.year, now.month, now.day)
        .subtract(const Duration(days: 13));

    for (final c in matched) {
      final uid =
          (c['userId'] ?? c['uid'] ?? c['touristId'] ?? '').toString().trim();
      if (uid.isNotEmpty) uids.add(uid);
      final visitors = checkInVisitorCount(c);
      final day = _ts(c);
      if (day != null) {
        final d0 = DateTime(day.year, day.month, day.day);
        byWeekday[day.weekday - 1] += visitors;
        if (!d0.isBefore(start14)) {
          byDay[d0] = (byDay[d0] ?? 0) + visitors;
        }
      }
      // Demographics from tourist join when available
      Map<String, dynamic>? profile;
      if (uid.isNotEmpty) {
        for (final t in tourists) {
          final tid =
              (t['id'] ?? t['uid'] ?? t['userId'] ?? '').toString().trim();
          if (tid == uid) {
            profile = t;
            break;
          }
        }
      }
      final sex = (c['sex'] ?? profile?['sex'] ?? '').toString().toLowerCase();
      if (sex.startsWith('m')) {
        male += visitors;
      } else if (sex.startsWith('f')) {
        female += visitors;
      }
      final nat =
          (c['nationality'] ?? profile?['nationality'] ?? profile?['country'] ?? '')
              .toString()
              .toLowerCase();
      final isFil = nat.contains('filipino') ||
          nat.contains('philippine') ||
          nat == 'ph' ||
          nat == 'philippines' ||
          (profile?['isLocal'] == true);
      if (isFil) {
        filipino += visitors;
      } else if (nat.isNotEmpty) {
        foreign += visitors;
      }
      final city = (profile?['city'] ?? c['city'] ?? c['origin'] ?? '')
          .toString()
          .trim();
      if (city.isNotEmpty) {
        origins[city] = (origins[city] ?? 0) + visitors;
      }
    }

    final trendValues = <int>[];
    final trendLabels = <String>[];
    const names = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    for (var i = 0; i < 14; i++) {
      final d = start14.add(Duration(days: i));
      trendValues.add(byDay[d] ?? 0);
      trendLabels.add(names[(d.weekday - 1) % 7]);
    }

    final originEntries = origins.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final totalVisitors = matched.fold<int>(0, (a, c) => a + checkInVisitorCount(c));

    final wide = MediaQuery.sizeOf(context).width >= 900;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
      children: [
        Text('Attraction analytics', style: GovernorDashboardTokens.heading(size: 18)),
        const SizedBox(height: 4),
        Text(
          'QR check-ins at this spot (VAR-family data). Confirmed hotel stays are separate.',
          style: GovernorDashboardTokens.body(size: 12.5),
        ),
        const SizedBox(height: 14),
        _KpiStrip(
          items: [
            _Kpi('Unique visitors', '${uids.length}', Icons.people_outline),
            _Kpi('Check-ins', '$totalVisitors', Icons.qr_code_scanner),
            _Kpi(
              'Avg / day (14d)',
              trendValues.isEmpty
                  ? '0'
                  : (trendValues.reduce((a, b) => a + b) / 14)
                      .toStringAsFixed(1),
              Icons.trending_up,
            ),
            _Kpi(
              'Peak weekday',
              _peakWeekday(byWeekday),
              Icons.calendar_today_outlined,
            ),
          ],
        ),
        const SizedBox(height: 14),
        EstablishmentDssCharts.panel(
          title: 'Visitors · last 14 days',
          subtitle: 'Headcount from QR check-ins',
          height: 220,
          child: _trendLine(trendValues, trendLabels),
        ),
        const SizedBox(height: 12),
        if (wide)
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: EstablishmentDssCharts.panel(
                  title: 'Sex mix',
                  subtitle: 'From check-in / profile',
                  height: 180,
                  child: GovernorDonutChart(
                    segments: [
                      GovernorDonutSegment(
                        label: 'Male',
                        value: male.toDouble(),
                        color: const Color(0xFF3B82F6),
                      ),
                      GovernorDonutSegment(
                        label: 'Female',
                        value: female.toDouble(),
                        color: const Color(0xFFEC4899),
                      ),
                    ],
                    emptyMessage: 'No sex data yet',
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: EstablishmentDssCharts.panel(
                  title: 'Residency mix',
                  subtitle: 'Filipino vs foreign',
                  height: 180,
                  child: GovernorDonutChart(
                    segments: [
                      GovernorDonutSegment(
                        label: 'Filipino',
                        value: filipino.toDouble(),
                        color: GovernorDashboardTokens.primary,
                      ),
                      GovernorDonutSegment(
                        label: 'Foreign',
                        value: foreign.toDouble(),
                        color: const Color(0xFF0EA5E9),
                      ),
                    ],
                    emptyMessage: 'No residency data yet',
                  ),
                ),
              ),
            ],
          )
        else ...[
          EstablishmentDssCharts.panel(
            title: 'Sex mix',
            subtitle: 'From check-in / profile',
            height: 180,
            child: GovernorDonutChart(
              segments: [
                GovernorDonutSegment(
                  label: 'Male',
                  value: male.toDouble(),
                  color: const Color(0xFF3B82F6),
                ),
                GovernorDonutSegment(
                  label: 'Female',
                  value: female.toDouble(),
                  color: const Color(0xFFEC4899),
                ),
              ],
              emptyMessage: 'No sex data yet',
            ),
          ),
          const SizedBox(height: 12),
          EstablishmentDssCharts.panel(
            title: 'Residency mix',
            subtitle: 'Filipino vs foreign',
            height: 180,
            child: GovernorDonutChart(
              segments: [
                GovernorDonutSegment(
                  label: 'Filipino',
                  value: filipino.toDouble(),
                  color: GovernorDashboardTokens.primary,
                ),
                GovernorDonutSegment(
                  label: 'Foreign',
                  value: foreign.toDouble(),
                  color: const Color(0xFF0EA5E9),
                ),
              ],
              emptyMessage: 'No residency data yet',
            ),
          ),
        ],
        const SizedBox(height: 12),
        EstablishmentDssCharts.panel(
          title: 'Visitors by weekday',
          subtitle: 'All check-ins at this spot',
          height: 180,
          child: EstablishmentDssCharts.weekdayBars(byWeekday),
        ),
        const SizedBox(height: 12),
        _OriginsCard(entries: originEntries.take(8).toList()),
      ],
    );
  }

  String _peakWeekday(List<int> byWeekday) {
    const names = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    var best = 0;
    for (var i = 1; i < 7; i++) {
      if (byWeekday[i] > byWeekday[best]) best = i;
    }
    if (byWeekday.every((v) => v == 0)) return '—';
    return names[best];
  }

  Widget _trendLine(List<int> values, List<String> labels) {
    if (values.every((v) => v == 0)) {
      return EstablishmentDssCharts.emptyChart('No check-ins in the last 14 days.');
    }
    return EstablishmentDssCharts.staysTrendLine(values: values, labels: labels);
  }
}

// ── Establishment analytics ─────────────────────────────────────────

class _EstablishmentAnalyticsBody extends StatelessWidget {
  const _EstablishmentAnalyticsBody({required this.establishment});

  final EstablishmentRegistryEntry establishment;

  @override
  Widget build(BuildContext context) {
    final profile = AeRegisterViewerScreen.profileFor(
      aeId: establishment.id,
      aeName: establishment.businessName,
      category: establishment.category,
      municipalityId: establishment.municipalityId,
      municipality: establishment.municipality,
      totalRooms: establishment.roomCount,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  'Figures from the establishment\'s monthly DOT register (DAE-1B). '
                  'Occupancy = rooms occupied ÷ rooms available; ALOS = guest-nights ÷ check-ins.',
                  style: GovernorDashboardTokens.body(size: 12.5),
                ),
              ),
              const SizedBox(width: 12),
              OutlinedButton.icon(
                onPressed: () => AeRegisterViewerScreen.open(
                  context,
                  profile: profile,
                  showEvents: establishment.hostsMice,
                ),
                icon: const Icon(Icons.table_chart_rounded, size: 18),
                label: const Text('Open register'),
              ),
            ],
          ),
        ),
        Expanded(
          child: EstablishmentInsightsBoard(
            profile: profile,
            schema: AeRegisterSchema.forCategory(establishment.category),
            embedded: true,
          ),
        ),
      ],
    );
  }
}

// ── Shared widgets ──────────────────────────────────────────────────

class _Kpi {
  const _Kpi(this.label, this.value, this.icon);
  final String label;
  final String value;
  final IconData icon;
}

class _KpiStrip extends StatelessWidget {
  const _KpiStrip({required this.items});
  final List<_Kpi> items;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, c) {
        final wide = c.maxWidth > 700;
        Widget cell(_Kpi k) => Expanded(
              child: Container(
                margin: const EdgeInsets.only(right: 8),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: GovernorDashboardTokens.border),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(k.icon,
                        size: 18, color: GovernorDashboardTokens.primary),
                    const SizedBox(height: 6),
                    Text(
                      k.value,
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 18,
                        color: GovernorDashboardTokens.text,
                      ),
                    ),
                    Text(
                      k.label,
                      style: const TextStyle(
                        fontSize: 11,
                        color: GovernorDashboardTokens.subtitle,
                      ),
                    ),
                  ],
                ),
              ),
            );
        if (wide) {
          return Row(children: [for (final k in items) cell(k)]);
        }
        return Column(
          children: [
            Row(children: [cell(items[0]), cell(items[1])]),
            const SizedBox(height: 8),
            Row(children: [cell(items[2]), cell(items[3])]),
          ],
        );
      },
    );
  }
}

class _OriginsCard extends StatelessWidget {
  const _OriginsCard({required this.entries});
  final List<MapEntry<String, int>> entries;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: GovernorDashboardTokens.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Top origins', style: GovernorDashboardTokens.sectionTitle()),
          const SizedBox(height: 4),
          Text(
            'Registration city / origin on linked tourist profiles',
            style: GovernorDashboardTokens.body(size: 12),
          ),
          const SizedBox(height: 10),
          if (entries.isEmpty)
            Text('No origin data yet.', style: GovernorDashboardTokens.body())
          else
            for (final e in entries)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        e.key,
                        style: const TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 13,
                        ),
                      ),
                    ),
                    Text(
                      '${e.value}',
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        color: GovernorDashboardTokens.primary,
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

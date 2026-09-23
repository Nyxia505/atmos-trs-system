import 'package:flutter/material.dart';

import 'package:atmos_trs_system/utils/establishment_capability.dart';
import 'package:atmos_trs_system/utils/establishment_dss_aggregates.dart';
import 'package:atmos_trs_system/utils/establishment_room_grid.dart';
import 'package:atmos_trs_system/widgets/establishment_dash_tokens.dart';
import 'package:atmos_trs_system/widgets/establishment_dss_charts.dart';

/// Dense Home command center: welcome, KPIs, glance charts, queue slots.
class EstablishmentHomeBoard extends StatelessWidget {
  const EstablishmentHomeBoard({
    super.key,
    required this.businessName,
    required this.category,
    required this.municipality,
    required this.pack,
    required this.copy,
    required this.categoryIcon,
    required this.statusPill,
    required this.statusBanner,
    required this.kpis,
    required this.dss,
    required this.isLodging,
    this.roomStats,
    required this.pendingSection,
    required this.recentSection,
    this.onOpenRooms,
  });

  final String businessName;
  final String category;
  final String municipality;
  final EstablishmentPack pack;
  final EstablishmentPackCopy copy;
  final IconData categoryIcon;
  final Widget statusPill;
  final Widget statusBanner;
  final EstablishmentHomeKpis kpis;
  final EstablishmentDssSnapshot dss;
  final bool isLodging;
  final EstablishmentRoomStats? roomStats;
  final Widget pendingSection;
  final Widget recentSection;
  final VoidCallback? onOpenRooms;

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= 1100;

    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
      children: [
        _welcomeRow(),
        const SizedBox(height: 10),
        statusBanner,
        const SizedBox(height: 14),
        _kpiStrip(),
        if (isLodging && roomStats != null) ...[
          const SizedBox(height: 12),
          _roomSnapshot(roomStats!),
        ],
        const SizedBox(height: 14),
        if (wide)
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: _miniTrend()),
              const SizedBox(width: 12),
              Expanded(child: _miniMixOrOccupancy()),
            ],
          )
        else ...[
          _miniTrend(),
          const SizedBox(height: 12),
          _miniMixOrOccupancy(),
        ],
        const SizedBox(height: 16),
        pendingSection,
        const SizedBox(height: 16),
        recentSection,
      ],
    );
  }

  Widget _welcomeRow() {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: AeDashTokens.cardDecoration(),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: AeDashTokens.softAccent,
              borderRadius: BorderRadius.circular(AeDashTokens.radiusSm),
            ),
            child: Icon(categoryIcon, color: AeDashTokens.accent, size: 24),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  businessName,
                  style: AeDashTokens.heading(size: 18),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  [
                    if (category.isNotEmpty) category,
                    copy.packLabel,
                    if (municipality.isNotEmpty) municipality,
                  ].join(' · '),
                  style: AeDashTokens.body(size: 12),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          statusPill,
        ],
      ),
    );
  }

  Widget _kpiStrip() {
    final fourth = switch (pack) {
      EstablishmentPack.lodging => '${kpis.roomsMonth}',
      EstablishmentPack.dining => kpis.avgPartySize == 0
          ? '—'
          : kpis.avgPartySize.toStringAsFixed(
              kpis.avgPartySize == kpis.avgPartySize.roundToDouble() ? 0 : 1,
            ),
      EstablishmentPack.venue =>
        kpis.peakDay == 0 ? '—' : 'Day ${kpis.peakDay}',
    };

    final items = [
      _Kpi('Pending', '${kpis.pending}', Icons.hourglass_top_rounded),
      _Kpi('Today', '${kpis.confirmedToday}', Icons.check_circle_outline),
      _Kpi(copy.kpiGuestsLabel, '${kpis.guestsMonth}', Icons.groups_outlined),
      _Kpi(copy.kpiFourthLabel, fourth, copy.kpiFourthIcon),
    ];

    return LayoutBuilder(
      builder: (context, c) {
        final tight = c.maxWidth < 640;
        if (tight) {
          return Column(
            children: [
              Row(
                children: [
                  Expanded(child: _kpiTile(items[0])),
                  const SizedBox(width: 8),
                  Expanded(child: _kpiTile(items[1])),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(child: _kpiTile(items[2])),
                  const SizedBox(width: 8),
                  Expanded(child: _kpiTile(items[3])),
                ],
              ),
            ],
          );
        }
        return Row(
          children: [
            for (var i = 0; i < items.length; i++) ...[
              if (i > 0) const SizedBox(width: 8),
              Expanded(child: _kpiTile(items[i])),
            ],
          ],
        );
      },
    );
  }

  Widget _kpiTile(_Kpi item) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 10),
      decoration: AeDashTokens.cardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(item.icon, size: 18, color: AeDashTokens.accent),
          const SizedBox(height: 8),
          Text(item.value, style: AeDashTokens.number(size: 22)),
          const SizedBox(height: 2),
          Text(
            item.label,
            style: AeDashTokens.body(size: 11),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  Widget _roomSnapshot(EstablishmentRoomStats stats) {
    Widget chip(String label, String value, Color color) {
      return Expanded(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
          decoration: BoxDecoration(
            color: AeDashTokens.surface,
            borderRadius: BorderRadius.circular(AeDashTokens.radiusSm),
            border: Border.all(color: color.withValues(alpha: 0.35)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(value, style: AeDashTokens.number(size: 18, color: color)),
              Text(label, style: AeDashTokens.body(size: 10.5)),
            ],
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Text('Room snapshot', style: AeDashTokens.section()),
            const Spacer(),
            if (onOpenRooms != null)
              TextButton(
                onPressed: onOpenRooms,
                child: const Text('Open Rooms'),
              ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            chip('Total', '${stats.total}', AeDashTokens.accent),
            const SizedBox(width: 8),
            chip('Occupied', '${stats.occupied}', AeDashTokens.danger),
            const SizedBox(width: 8),
            chip('Free', '${stats.free}', AeDashTokens.success),
            const SizedBox(width: 8),
            chip('Off', '${stats.disabled}', const Color(0xFFEA580C)),
          ],
        ),
      ],
    );
  }

  Widget _miniTrend() {
    return EstablishmentDssCharts.panel(
      title: 'Last 7 days',
      subtitle: copy.chartSubtitle,
      height: 160,
      child: EstablishmentDssCharts.staysTrendLine(
        values: dss.staysTrend7,
        labels: dss.dayLabels7,
      ),
    );
  }

  Widget _miniMixOrOccupancy() {
    if (isLodging && roomStats != null) {
      return EstablishmentDssCharts.panel(
        title: 'Live occupancy',
        subtitle: 'Rooms in house right now',
        height: 160,
        child: EstablishmentDssCharts.occupancyGauge(
          occupied: roomStats!.occupied,
          free: roomStats!.free,
          total: roomStats!.total,
        ),
      );
    }
    final d = dss.demographics;
    return EstablishmentDssCharts.panel(
      title: 'Guests this month',
      subtitle: 'Filipino vs foreign',
      height: 160,
      child: EstablishmentDssCharts.mixPie(
        aLabel: 'Filipino',
        aValue: d.filipino,
        aColor: AeDashTokens.accent,
        bLabel: 'Foreign',
        bValue: d.foreign,
        bColor: AeDashTokens.chartSecondary,
      ),
    );
  }
}

class EstablishmentHomeKpis {
  const EstablishmentHomeKpis({
    required this.pending,
    required this.confirmedToday,
    required this.guestsMonth,
    required this.roomsMonth,
    required this.avgPartySize,
    required this.peakDay,
    required this.peakDayGuests,
  });

  final int pending;
  final int confirmedToday;
  final int guestsMonth;
  final int roomsMonth;
  final double avgPartySize;
  final int peakDay;
  final int peakDayGuests;
}

class _Kpi {
  const _Kpi(this.label, this.value, this.icon);
  final String label;
  final String value;
  final IconData icon;
}

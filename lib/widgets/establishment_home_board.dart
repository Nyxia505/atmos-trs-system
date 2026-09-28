import 'package:flutter/material.dart';

import 'package:atmos_trs_system/utils/establishment_capability.dart';
import 'package:atmos_trs_system/utils/establishment_room_grid.dart';
import 'package:atmos_trs_system/widgets/establishment_dash_tokens.dart';
import 'package:atmos_trs_system/widgets/establishment_dashboard_components.dart';

/// Home front desk: hero, approval notice, today's KPIs, guest requests.
/// Room status lives on Rooms; charts on Insights; reviews on Reviews.
class EstablishmentHomeBoard extends StatefulWidget {
  const EstablishmentHomeBoard({
    super.key,
    required this.businessName,
    required this.category,
    required this.municipality,
    required this.pack,
    required this.copy,
    required this.categoryIcon,
    required this.statusPill,
    required this.kpis,
    required this.isLodging,
    required this.requestsSection,
    this.statusBanner,
    this.roomStats,
    this.onOpenRooms,
    this.onOpenInsights,
  });

  final String businessName;
  final String category;
  final String municipality;
  final EstablishmentPack pack;
  final EstablishmentPackCopy copy;
  final IconData categoryIcon;
  final Widget statusPill;
  final Widget? statusBanner;
  final EstablishmentHomeKpis kpis;
  final bool isLodging;
  final EstablishmentRoomStats? roomStats;
  final Widget requestsSection;
  final VoidCallback? onOpenRooms;
  final VoidCallback? onOpenInsights;

  @override
  State<EstablishmentHomeBoard> createState() => _EstablishmentHomeBoardState();
}

class _EstablishmentHomeBoardState extends State<EstablishmentHomeBoard> {
  final GlobalKey _requestsKey = GlobalKey();

  void _scrollToRequests() {
    final ctx = _requestsKey.currentContext;
    if (ctx == null) return;
    Scrollable.ensureVisible(
      ctx,
      duration: const Duration(milliseconds: 350),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, c) {
        final w = c.maxWidth;
        final pad = w < 600 ? 14.0 : (w < 1000 ? 18.0 : 24.0);
        final gap = w < 600 ? 12.0 : 16.0;

        return ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: EdgeInsets.only(bottom: pad + 12),
          children: [
            _hero(),
            Padding(
              padding: EdgeInsets.fromLTRB(pad, gap, pad, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: _body(gap),
              ),
            ),
          ],
        );
      },
    );
  }

  List<Widget> _body(double gap) {
    return [
      if (widget.statusBanner != null) ...[
        widget.statusBanner!,
        SizedBox(height: gap),
      ],
      _summaryCards(gap),
      SizedBox(height: gap),
      KeyedSubtree(key: _requestsKey, child: widget.requestsSection),
    ];
  }

  Widget _hero() {
    return EstablishmentHeroHeader(
      greeting: AeDashTokens.greetingForNow(),
      businessName: widget.businessName,
      tags: [
        if (widget.category.isNotEmpty)
          EstablishmentHeroTag(widget.categoryIcon, widget.category),
        EstablishmentHeroTag(Icons.apartment_rounded, widget.copy.packLabel),
        if (widget.municipality.isNotEmpty)
          EstablishmentHeroTag(Icons.location_on_outlined, widget.municipality),
      ],
      trailing: widget.statusPill,
      flush: true,
    );
  }

  Widget _summaryCards(double gap) {
    final k = widget.kpis;
    final stats = widget.roomStats;

    final String fourthValue;
    final String fourthSubtitle;
    VoidCallback? fourthTap = widget.onOpenInsights;
    switch (widget.pack) {
      case EstablishmentPack.lodging:
        fourthValue = '${stats?.occupied ?? 0}';
        fourthSubtitle = 'Occupied right now';
        fourthTap = widget.onOpenRooms ?? widget.onOpenInsights;
      case EstablishmentPack.dining:
        fourthValue = k.avgPartySize == 0
            ? '—'
            : k.avgPartySize.toStringAsFixed(
                k.avgPartySize == k.avgPartySize.roundToDouble() ? 0 : 1,
              );
        fourthSubtitle = 'Per confirmed visit';
      case EstablishmentPack.venue:
        fourthValue = k.peakDay == 0 ? '—' : 'Day ${k.peakDay}';
        fourthSubtitle = 'Busiest day this month';
    }

    return AeResponsiveGrid(
      spacing: gap,
      minItemWidth: 230,
      children: [
        AeSummaryCard(
          title: 'Pending',
          subtitle: 'Awaiting confirmation',
          value: '${k.pending}',
          icon: Icons.hourglass_top_rounded,
          color: AeDashTokens.accent,
          onTap: _scrollToRequests,
        ),
        AeSummaryCard(
          title: 'Confirmed today',
          subtitle: 'Guests checked in',
          value: '${k.confirmedToday}',
          icon: Icons.check_circle_rounded,
          color: AeDashTokens.success,
          onTap: widget.onOpenInsights,
        ),
        AeSummaryCard(
          title: widget.copy.kpiGuestsLabel,
          subtitle: 'Total guests this month',
          value: '${k.guestsMonth}',
          icon: Icons.groups_rounded,
          color: AeDashTokens.purple,
          onTap: widget.onOpenInsights,
        ),
        AeSummaryCard(
          title: widget.copy.kpiFourthLabel,
          subtitle: fourthSubtitle,
          value: fourthValue,
          icon: widget.isLodging
              ? Icons.meeting_room_rounded
              : widget.copy.kpiFourthIcon,
          color: AeDashTokens.blue,
          onTap: fourthTap,
        ),
      ],
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

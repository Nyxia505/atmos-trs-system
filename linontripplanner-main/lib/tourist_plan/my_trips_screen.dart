import 'package:flutter/material.dart';

import '../data.dart';
import '../services/saved_trip_store.dart';
import '../services/trip_post_finish_rating.dart';
import '../spot_detail_screen.dart';
import '../trip_plan_route_map_page.dart';
import '../trip_route_fare_service.dart';
import '../widgets/municipality_image.dart';
import '../widgets/tourism_plan_ui.dart';
import 'tourist_trip_planner_screen.dart';
import 'tourist_travel_estimates.dart';

void _openTripPlanner(BuildContext context) {
  final nav = tourismRootNavigatorKey.currentState ?? Navigator.of(context);
  nav.pushNamed(TouristTripPlannerScreen.routeName);
}

/// Bottom-nav Trips tab — finished Plan my trip results.
class MyTripsScreen extends StatefulWidget {
  final bool embeddedInShell;

  const MyTripsScreen({super.key, this.embeddedInShell = false});

  @override
  State<MyTripsScreen> createState() => _MyTripsScreenState();
}

class _MyTripsScreenState extends State<MyTripsScreen> {
  @override
  void initState() {
    super.initState();
    SavedTripStore.instance.ensureLoaded();
    SavedTripStore.instance.revision.addListener(_onRev);
  }

  @override
  void dispose() {
    SavedTripStore.instance.revision.removeListener(_onRev);
    super.dispose();
  }

  void _onRev() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final trips = SavedTripStore.instance.trips;
    return Scaffold(
      backgroundColor: AppColors.planPageBg,
      appBar: AppBar(
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        title: const Text('My trips'),
        automaticallyImplyLeading: !widget.embeddedInShell,
      ),
      body: Column(
        children: [
          Expanded(
            child: trips.isEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(28),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.luggage_outlined,
                            size: 56,
                            color: AppColors.primary.withValues(alpha: 0.7),
                          ),
                          const SizedBox(height: 14),
                          const Text(
                            'No trips yet',
                            style: TextStyle(
                              fontWeight: FontWeight.w800,
                              fontSize: 18,
                              color: AppColors.textDark,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Finish a plan in Plan my trip and it will show up here.',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: AppColors.textGrey.withValues(alpha: 0.95),
                              height: 1.4,
                            ),
                          ),
                        ],
                      ),
                    ),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
                    itemCount: trips.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 10),
                    itemBuilder: (context, i) {
                      final trip = trips[i];
                      return _TripCard(
                        trip: trip,
                        onOpen: () {
                          Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => SavedTripDetailScreen(trip: trip),
                            ),
                          );
                        },
                        onDelete: () async {
                          await SavedTripStore.instance.remove(trip.id);
                        },
                      );
                    },
                  ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
              child: TourismGradientButton(
                label: 'Plan a new trip',
                icon: Icons.add_road,
                onPressed: () => _openTripPlanner(context),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _TripCard extends StatelessWidget {
  final SavedTripPlan trip;
  final VoidCallback onOpen;
  final VoidCallback onDelete;

  const _TripCard({
    required this.trip,
    required this.onOpen,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onOpen,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.black.withValues(alpha: 0.06)),
          ),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.map_outlined, color: AppColors.primary),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${trip.startName} to ${trip.endName}',
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 15,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${trip.tripDays} day${trip.tripDays == 1 ? '' : 's'} - '
                      '${trip.spotCount} spot${trip.spotCount == 1 ? '' : 's'} - '
                      '${transportModeLabel(trip.transportMode)}',
                      style: TextStyle(
                        fontSize: 12.5,
                        color: AppColors.textGrey.withValues(alpha: 0.95),
                      ),
                    ),
                    Text(
                      formatFarePhp(trip.estimatedTotalPhp),
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        color: AppColors.primary,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: 'Delete',
                onPressed: onDelete,
                icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

Municipality? _municipalityNamed(String name) {
  final needle = name.trim().toLowerCase();
  if (needle.isEmpty) return null;
  for (final m in municipalities) {
    if (m.name.toLowerCase() == needle || m.shortName.toLowerCase() == needle) {
      return m;
    }
  }
  return null;
}

class _SavedViewRouteButton extends StatelessWidget {
  final SavedTripPlan trip;

  const _SavedViewRouteButton({required this.trip});

  @override
  Widget build(BuildContext context) {
    return TourismGradientButton(
      label: 'View route on map',
      icon: Icons.map_rounded,
      onPressed: () {
        final start = _municipalityNamed(trip.startName);
        final end = _municipalityNamed(trip.endName);
        if (start == null || end == null) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Start or end place is missing for this trip.'),
            ),
          );
          return;
        }
        final days = trip.resolveDays();
        final spots = <TouristSpot>[for (final day in days) ...day];
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => TripPlanRouteMapPage(
              start: start,
              end: end,
              spots: spots,
              spotDays: days,
              transportMode: trip.transportMode,
            ),
          ),
        );
      },
    );
  }
}

/// Finished trip detail — same day-card layout as Assign days.
class SavedTripDetailScreen extends StatelessWidget {
  final SavedTripPlan trip;
  static const _accent = AppColors.primary;

  const SavedTripDetailScreen({super.key, required this.trip});

  @override
  Widget build(BuildContext context) {
    final days = trip.resolveDays();
    final dateLine = trip.arrivalDate != null && trip.departureDate != null
        ? '${_fmtSavedDate(trip.arrivalDate!)} – ${_fmtSavedDate(trip.departureDate!)}'
        : null;
    return Scaffold(
      backgroundColor: AppColors.planPageBg,
      appBar: AppBar(
        backgroundColor: _accent,
        foregroundColor: Colors.white,
        title: const Text('Trip plan'),
      ),
      body: Column(
        children: [
          Expanded(
            child: CustomScrollView(
              slivers: [
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                  sliver: SliverToBoxAdapter(
                    child: _SavedTripHero(
                      trip: trip,
                      dateLine: dateLine,
                      accent: _accent,
                    ),
                  ),
                ),
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(16, 18, 16, 10),
                  sliver: SliverToBoxAdapter(
                    child: TourismPlanUi.sectionHeader(
                      icon: Icons.calendar_month_rounded,
                      title: 'Itinerary',
                      badge: '${days.length} day${days.length == 1 ? '' : 's'}',
                    ),
                  ),
                ),
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
                  sliver: SliverList(
                    delegate: SliverChildBuilderDelegate(
                      (context, d) {
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 14),
                          child: _SavedDaySection(
                            dayIndex: d,
                            spots: days[d],
                            trip: trip,
                            accent: _accent,
                          ),
                        );
                      },
                      childCount: days.length,
                    ),
                  ),
                ),
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 20),
                  sliver: SliverToBoxAdapter(
                    child: _SavedTripSummaryCard(trip: trip, accent: _accent),
                  ),
                ),
              ],
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
              child: _SavedViewRouteButton(trip: trip),
            ),
          ),
        ],
      ),
    );
  }
}

class _SavedTripHero extends StatelessWidget {
  final SavedTripPlan trip;
  final String? dateLine;
  final Color accent;

  const _SavedTripHero({
    required this.trip,
    required this.dateLine,
    required this.accent,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
      decoration: TourismPlanUi.planCardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Your plan',
            style: TextStyle(
              fontFamily: AppFonts.holidayCalling,
              fontSize: 28,
              color: accent,
              height: 1.05,
            ),
          ),
          if (dateLine != null) ...[
            const SizedBox(height: 4),
            Text(
              dateLine!,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: AppColors.textGrey.withValues(alpha: 0.95),
              ),
            ),
          ],
          const SizedBox(height: 14),
          _endpoint(Icons.trip_origin, const Color(0xFF1565C0), 'Start', trip.startName),
          Padding(
            padding: const EdgeInsets.only(left: 15),
            child: Container(
              width: 2,
              height: 14,
              color: accent.withValues(alpha: 0.35),
            ),
          ),
          _endpoint(Icons.place, const Color(0xFFE53935), 'End', trip.endName),
          const SizedBox(height: 14),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _stat(Icons.calendar_today_rounded, '${trip.tripDays} day${trip.tripDays == 1 ? '' : 's'}'),
              _stat(Icons.people_alt_rounded, '${trip.travelers} traveler${trip.travelers == 1 ? '' : 's'}'),
              _stat(Icons.directions_rounded, transportModeLabel(trip.transportMode)),
              _stat(Icons.place_outlined, '${trip.spotCount} spot${trip.spotCount == 1 ? '' : 's'}'),
            ],
          ),
        ],
      ),
    );
  }

  Widget _endpoint(IconData icon, Color color, String label, String name) {
    return Row(
      children: [
        Icon(icon, size: 22, color: color),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: color,
                  letterSpacing: 0.3,
                ),
              ),
              Text(
                name,
                style: const TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 16,
                  color: AppColors.textDark,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _stat(IconData icon, String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.listTilePeach,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: accent.withValues(alpha: 0.16)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: accent),
          const SizedBox(width: 6),
          Text(
            label,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: AppColors.textDark,
            ),
          ),
        ],
      ),
    );
  }
}

class _SavedDaySection extends StatelessWidget {
  final int dayIndex;
  final List<TouristSpot> spots;
  final SavedTripPlan trip;
  final Color accent;

  const _SavedDaySection({
    required this.dayIndex,
    required this.spots,
    required this.trip,
    required this.accent,
  });

  @override
  Widget build(BuildContext context) {
    final route = spots.isEmpty
        ? null
        : buildRouteEstimate(
            orderedStops: spots,
            mode: trip.transportMode,
            tourists: trip.travelers,
          );

    final dayDate = trip.arrivalDate == null
        ? null
        : _fmtSavedDate(trip.arrivalDate!.add(Duration(days: dayIndex)));

    return Container(
      decoration: TourismPlanUi.planCardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 14, 14, 8),
            child: Row(
              children: [
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: accent.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    'Day ${dayIndex + 1}',
                    style: TextStyle(
                      fontWeight: FontWeight.w900,
                      color: accent,
                      fontSize: 13,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    dayDate ?? '${spots.length} stop${spots.length == 1 ? '' : 's'}',
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 14,
                      color: AppColors.textDark,
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (spots.isNotEmpty && route != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 8),
              child: Wrap(
                spacing: 8,
                runSpacing: 6,
                children: [
                  _chip('${spots.length} spot${spots.length == 1 ? '' : 's'}'),
                  if (route.totalDistanceKm > 0)
                    _chip('~${route.totalDistanceKm.toStringAsFixed(1)} km'),
                  if (route.totalTravelMinutes > 0)
                    _chip(
                      'Travel ${formatHoursMinutes(route.totalTravelMinutes)}',
                    ),
                ],
              ),
            ),
          if (spots.isEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 8, 14, 16),
              child: Container(
                width: double.infinity,
                padding:
                    const EdgeInsets.symmetric(vertical: 28, horizontal: 16),
                decoration: BoxDecoration(
                  color: AppColors.insetSurface,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: accent.withValues(alpha: 0.2)),
                ),
                child: Column(
                  children: [
                    Icon(
                      Icons.place_outlined,
                      size: 36,
                      color: accent.withValues(alpha: 0.7),
                    ),
                    const SizedBox(height: 10),
                    const Text(
                      'No spots on this day',
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 16,
                        color: AppColors.textDark,
                      ),
                    ),
                  ],
                ),
              ),
            )
          else
            for (var i = 0; i < spots.length; i++) ...[
              if (i > 0 && route != null && i - 1 < route.legs.length)
                Padding(
                  padding: const EdgeInsets.fromLTRB(14, 0, 14, 2),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                    decoration: BoxDecoration(
                      color: AppColors.listTilePeach,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.route_rounded,
                          size: 15,
                          color: accent,
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            '${route.legs[i - 1].timeLabel} · ${route.legs[i - 1].distanceLabel} · '
                            '${transportModeLabel(trip.transportMode)}'
                            '${route.legs[i - 1].transportFeePhp > 0 ? ' · ${formatFarePhp(route.legs[i - 1].transportFeePhp)}' : ''}',
                            style: TextStyle(
                              fontSize: 11.5,
                              fontWeight: FontWeight.w600,
                              color: AppColors.textGrey.withValues(alpha: 0.95),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => SpotDetailScreen(spot: spots[i]),
                      ),
                    );
                  },
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(14, 8, 14, 10),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(12),
                          child: SizedBox(
                            width: 72,
                            height: 72,
                            child: buildTouristSpotProfileImage(
                              spots[i],
                              fallback: Container(
                                color: accent.withValues(alpha: 0.15),
                                alignment: Alignment.center,
                                child: Icon(Icons.place, color: accent),
                              ),
                              memCacheWidth: 144,
                              memCacheHeight: 144,
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '${i + 1}. ${spots[i].name}',
                                style: const TextStyle(
                                  fontWeight: FontWeight.w800,
                                  fontSize: 14.5,
                                  color: AppColors.textDark,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                spots[i].location,
                                style: TextStyle(
                                  fontSize: 12.5,
                                  color:
                                      AppColors.textGrey.withValues(alpha: 0.95),
                                ),
                              ),
                              if (spots[i].priceRange.isNotEmpty) ...[
                                const SizedBox(height: 4),
                                Text(
                                  spots[i].priceRange,
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700,
                                    color: accent,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                        const Icon(Icons.chevron_right, color: AppColors.textGrey),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          const SizedBox(height: 6),
        ],
      ),
    );
  }

  Widget _chip(String label) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
        decoration: BoxDecoration(
          color: AppColors.insetSurface,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.black.withValues(alpha: 0.05)),
        ),
        child: Text(
          label,
          style: const TextStyle(
            fontSize: 11.5,
            fontWeight: FontWeight.w700,
            color: AppColors.textDark,
          ),
        ),
      );
}

class _SavedTripSummaryCard extends StatelessWidget {
  final SavedTripPlan trip;
  final Color accent;

  const _SavedTripSummaryCard({required this.trip, required this.accent});

  @override
  Widget build(BuildContext context) {
    final budget = trip.budgetPhp.round();
    final estimate = trip.estimatedTotalPhp;
    final hasBudget = budget > 0;
    final over = hasBudget && estimate > budget;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: TourismPlanUi.planCardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TourismPlanUi.sectionHeader(
            icon: Icons.receipt_long_rounded,
            title: 'Trip summary',
          ),
          const SizedBox(height: 14),
          _row('Days', '${trip.tripDays}'),
          _row('Spots on itinerary', '${trip.spotCount}'),
          _row('Travelers', '${trip.travelers}'),
          _row('Transport', transportModeLabel(trip.transportMode)),
          const Divider(height: 22),
          _row('Estimated overall', formatFarePhp(estimate), bold: true),
          _row('Your budget', formatFarePhp(budget)),
          if (hasBudget) ...[
            const SizedBox(height: 8),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: over ? const Color(0xFFFFEBEE) : const Color(0xFFE8F5E9),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                over
                    ? 'Over budget by ${formatFarePhp(estimate - budget)}.'
                    : 'Within budget by ${formatFarePhp(budget - estimate)}.',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: over ? Colors.red.shade800 : Colors.green.shade900,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _row(String label, String value, {bool bold = false}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                fontSize: 13.5,
                fontWeight: bold ? FontWeight.w800 : FontWeight.w500,
                color: AppColors.textDark,
              ),
            ),
          ),
          Text(
            value,
            style: TextStyle(
              fontSize: 13.5,
              fontWeight: bold ? FontWeight.w900 : FontWeight.w700,
              color: bold ? accent : AppColors.textDark,
            ),
          ),
        ],
      ),
    );
  }
}

String _fmtSavedDate(DateTime d) {
  const m = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];
  return '${m[d.month - 1]} ${d.day}, ${d.year}';
}

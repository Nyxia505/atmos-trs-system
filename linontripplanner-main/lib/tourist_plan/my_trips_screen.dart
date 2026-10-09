import 'package:flutter/material.dart';

import '../data.dart';
import '../services/saved_trip_store.dart';
import '../spot_detail_screen.dart';
import '../trip_route_fare_service.dart';
import '../widgets/municipality_image.dart';
import '../widgets/tourism_plan_ui.dart';
import 'tourist_trip_planner_screen.dart';
import 'tourist_travel_estimates.dart';

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
      body: trips.isEmpty
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
                    const SizedBox(height: 18),
                    TourismGradientButton(
                      label: 'Plan my trip',
                      icon: Icons.route_rounded,
                      onPressed: () {
                        Navigator.of(context, rootNavigator: true).pushNamed(
                          TouristTripPlannerScreen.routeName,
                        );
                      },
                    ),
                  ],
                ),
              ),
            )
          : ListView.separated(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
              itemCount: trips.length + 1,
              separatorBuilder: (_, _) => const SizedBox(height: 10),
              itemBuilder: (context, i) {
                if (i == 0) {
                  return TourismGradientButton(
                    label: 'Plan a new trip',
                    icon: Icons.add_road,
                    onPressed: () {
                      Navigator.of(context, rootNavigator: true).pushNamed(
                        TouristTripPlannerScreen.routeName,
                      );
                    },
                  );
                }
                final trip = trips[i - 1];
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

/// Finished trip detail — same day-card layout as Assign days.
class SavedTripDetailScreen extends StatelessWidget {
  final SavedTripPlan trip;
  static const _accent = Color(0xFFFF6B00);

  const SavedTripDetailScreen({super.key, required this.trip});

  @override
  Widget build(BuildContext context) {
    final days = trip.resolveDays();
    return Scaffold(
      backgroundColor: AppColors.planPageBg,
      appBar: AppBar(
        backgroundColor: _accent,
        foregroundColor: Colors.white,
        title: const Text('Trip plan'),
      ),
      body: CustomScrollView(
        slivers: [
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            sliver: SliverToBoxAdapter(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Your plan',
                    style: TextStyle(
                      fontFamily: AppFonts.holidayCalling,
                      fontSize: 26,
                      color: _accent,
                      height: 1.1,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '${trip.startName} to ${trip.endName}',
                    style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 15,
                      color: AppColors.textDark,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '${trip.tripDays} day${trip.tripDays == 1 ? '' : 's'}'
                    '${trip.arrivalDate != null && trip.departureDate != null ? ' - ${_fmtSavedDate(trip.arrivalDate!)} - ${_fmtSavedDate(trip.departureDate!)}' : ''}'
                    ' - ${trip.travelers} traveler${trip.travelers == 1 ? '' : 's'}'
                    ' - ${transportModeLabel(trip.transportMode)}',
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 14,
                      color: _accent,
                    ),
                  ),
                  const SizedBox(height: 12),
                ],
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
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 28),
            sliver: SliverToBoxAdapter(
              child: _SavedTripSummaryCard(trip: trip, accent: _accent),
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
    final dateLabel = trip.arrivalDate == null
        ? 'Day ${dayIndex + 1}'
        : 'Day ${dayIndex + 1} - ${_fmtSavedDate(trip.arrivalDate!.add(Duration(days: dayIndex)))}';
    final route = spots.isEmpty
        ? null
        : buildRouteEstimate(
            orderedStops: spots,
            mode: trip.transportMode,
            tourists: trip.travelers,
          );

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.black.withValues(alpha: 0.06)),
        boxShadow: [
          BoxShadow(
            color: accent.withValues(alpha: 0.07),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
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
                    dateLabel.replaceFirst(RegExp(r'^Day \d+ - '), ''),
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
                  padding: const EdgeInsets.fromLTRB(56, 0, 14, 0),
                  child: Row(
                    children: [
                      Icon(
                        Icons.directions,
                        size: 14,
                        color: accent.withValues(alpha: 0.8),
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          '${route.legs[i - 1].timeLabel} - ${route.legs[i - 1].distanceLabel} - '
                          '${transportModeLabel(trip.transportMode)}'
                          '${route.legs[i - 1].transportFeePhp > 0 ? ' - ${formatFarePhp(route.legs[i - 1].transportFeePhp)}' : ''}',
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
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            accent.withValues(alpha: 0.12),
            Colors.white,
          ],
        ),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: accent.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Trip summary',
            style: TextStyle(
              fontWeight: FontWeight.w900,
              fontSize: 16,
              color: accent,
            ),
          ),
          const SizedBox(height: 10),
          _row('Days', '${trip.tripDays}'),
          _row(
            'Spots on itinerary',
            '${trip.spotCount}',
          ),
          _row('Travelers', '${trip.travelers}'),
          _row('Transport', transportModeLabel(trip.transportMode)),
          const Divider(height: 20),
          _row(
            'Estimated overall',
            formatFarePhp(trip.estimatedTotalPhp),
            bold: true,
          ),
          _row('Your budget', formatFarePhp(trip.budgetPhp.round())),
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

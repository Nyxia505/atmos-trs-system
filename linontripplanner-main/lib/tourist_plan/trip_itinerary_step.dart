import 'package:flutter/material.dart';

import '../data.dart';
import '../spot_detail_screen.dart';
import '../trip_route_fare_service.dart';
import '../widgets/municipality_image.dart';
import 'tourist_travel_estimates.dart';
import 'trip_wizard_controller.dart';

/// Step 2 - day-by-day itinerary builder.
class TripItineraryStep extends StatelessWidget {
  final TripWizardController wizard;
  final Color accent;

  const TripItineraryStep({
    super.key,
    required this.wizard,
    required this.accent,
  });

  @override
  Widget build(BuildContext context) {
    final byDay = wizard.spotsByDay;
    return CustomScrollView(
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          sliver: SliverToBoxAdapter(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Assign days',
                  style: TextStyle(
                    fontFamily: AppFonts.holidayCalling,
                    fontSize: 26,
                    color: accent,
                    height: 1.1,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Build your own plan: "Add nearest" picks the closest unvisited spot, '
                  'or choose any with "Add another spot". "End day here" makes the last '
                  'spot the start of the next day; new days are added until every spot is planned. '
                  'Each day holds up to ${TripWizardController.absoluteMaxSpotsPerDay} spots. '
                  'A spot used on one day will not show on other days.',
                  style: TextStyle(
                    fontSize: 13.5,
                    height: 1.4,
                    color: AppColors.textGrey.withValues(alpha: 0.95),
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  '${wizard.tripDays} day${wizard.tripDays == 1 ? '' : 's'}'
                  '${wizard.arrivalDate != null && wizard.departureDate != null ? ' - ${_fmtDate(wizard.arrivalDate!)} - ${_fmtDate(wizard.departureDate!)}' : ''}',
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 14,
                    color: accent,
                  ),
                ),
                if (wizard.municipalitiesOnRoute.length >= 2) ...[
                  const SizedBox(height: 8),
                  Text(
                    'Route by road: '
                    '${wizard.municipalitiesOnRoute.map((m) => m.shortName.isNotEmpty ? m.shortName : m.name).join(' → ')}',
                    style: const TextStyle(fontSize: 13, height: 1.4),
                  ),
                  if (wizard.routeDistanceKm != null)
                    Text(
                      '${wizard.routeDistanceKm!.toStringAsFixed(1)} km'
                      '${wizard.routeDrivingMinutes != null ? ' - ~${formatHoursMinutes(wizard.routeDrivingMinutes!)} driving' : ''}',
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textGrey.withValues(alpha: 0.95),
                      ),
                    ),
                ],
                if (wizard.algorithmInsight != null) ...[
                  const SizedBox(height: 6),
                  Text(
                    wizard.algorithmInsight!,
                    style: TextStyle(
                      fontSize: 12.5,
                      height: 1.35,
                      fontWeight: FontWeight.w600,
                      color: accent,
                    ),
                  ),
                ],
                if (wizard.routeSpotPool.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Builder(
                    builder: (context) {
                      final total = wizard.routeSpotPool.length;
                      final left = wizard.unvisitedSpotCount;
                      return Text(
                        left == 0
                            ? 'All $total route spots are planned.'
                            : '${total - left} of $total route spots planned - '
                                  '$left left. Each day starts where the previous '
                                  'day ended.',
                        style: TextStyle(
                          fontSize: 12.5,
                          height: 1.35,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textGrey.withValues(alpha: 0.95),
                        ),
                      );
                    },
                  ),
                ],
                if (wizard.unassignedSpots.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: accent.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: accent.withValues(alpha: 0.25)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${wizard.unassignedSpots.length} selected '
                          '${wizard.unassignedSpots.length == 1 ? 'spot is' : 'spots are'} '
                          'not on a day yet',
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            color: accent,
                            fontSize: 13.5,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          wizard.unassignedSpots.map((s) => s.name).join(', '),
                          style: TextStyle(
                            fontSize: 12.5,
                            height: 1.35,
                            color: AppColors.textGrey.withValues(alpha: 0.95),
                          ),
                        ),
                        const SizedBox(height: 4),
                        const Text(
                          'Use Add Spot on a day, or tap Suggest plan.',
                          style: TextStyle(fontSize: 12, height: 1.3),
                        ),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    OutlinedButton.icon(
                      onPressed: wizard.loadingDayPlan
                          ? null
                          : () async {
                              await wizard.suggestRouteDayPlan();
                              if (context.mounted) {
                                final n = wizard.assignedSpotNames.length;
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text(
                                      n == 0
                                          ? 'No route spots found to suggest.'
                                          : 'Suggested $n spots along your route.',
                                    ),
                                    backgroundColor: accent,
                                  ),
                                );
                              }
                            },
                      icon: const Icon(Icons.auto_awesome, size: 18),
                      label: const Text('Suggest plan'),
                    ),
                    TextButton(
                      onPressed: wizard.loadingDayPlan
                          ? null
                          : () => wizard.clearAllDayAssignments(),
                      child: const Text('Clear all days'),
                    ),
                  ],
                ),
                if (wizard.loadingDayPlan)
                  const Padding(
                    padding: EdgeInsets.only(top: 8),
                    child: LinearProgressIndicator(),
                  ),
                const SizedBox(height: 8),
              ],
            ),
          ),
        ),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
          sliver: SliverList(
            delegate: SliverChildBuilderDelegate((context, d) {
              return Padding(
                padding: const EdgeInsets.only(bottom: 14),
                child: _DaySection(
                  dayIndex: d,
                  wizard: wizard,
                  accent: accent,
                  spots: byDay[d],
                ),
              );
            }, childCount: byDay.length),
          ),
        ),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 28),
          sliver: SliverToBoxAdapter(
            child: _TripSummaryCard(wizard: wizard, accent: accent),
          ),
        ),
      ],
    );
  }
}

class _DaySection extends StatelessWidget {
  final int dayIndex;
  final TripWizardController wizard;
  final Color accent;
  final List<TouristSpot> spots;

  const _DaySection({
    required this.dayIndex,
    required this.wizard,
    required this.accent,
    required this.spots,
  });

  @override
  Widget build(BuildContext context) {
    final dateLabel = wizard.arrivalDate == null
        ? 'Day ${dayIndex + 1}'
        : 'Day ${dayIndex + 1} - ${_fmtDate(wizard.arrivalDate!.add(Duration(days: dayIndex)))}';
    final route = wizard.dayRouteEstimate(dayIndex);
    final starts = wizard.suggestedStartMinutesForDay(dayIndex);

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
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
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
                TextButton(
                  style: TextButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    foregroundColor: accent,
                  ),
                  onPressed: () => _pickDayStart(context),
                  child: Text(
                    _fmtClock(wizard.dayStartMinutesFor(dayIndex)),
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                ),
              ],
            ),
          ),
          if (wizard.dayStartLabel(dayIndex).isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 8),
              child: Row(
                children: [
                  Icon(Icons.trip_origin, size: 14, color: accent),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      dayIndex == 0
                          ? 'Starts from your starting point: '
                                '${wizard.dayStartLabel(dayIndex)}'
                          : 'Starts from: ${wizard.dayStartLabel(dayIndex)}',
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textGrey.withValues(alpha: 0.95),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          if (spots.isNotEmpty)
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
                  _chip(
                    'Activities ${formatHoursMinutes(wizard.dayActivityMinutes(dayIndex))}',
                  ),
                  _chip(
                    'Est. ${formatFarePhp(wizard.dayEstimatedExpensePhp(dayIndex))}',
                  ),
                ],
              ),
            ),
          if (spots.length >= TripWizardController.absoluteMaxSpotsPerDay)
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 8),
              child: Text(
                'This day is full (maximum ${TripWizardController.absoluteMaxSpotsPerDay} spots). '
                'Choose its last spot with "End day here" to continue on the next day.',
                style: TextStyle(
                  fontSize: 12,
                  color: AppColors.textGrey.withValues(alpha: 0.95),
                ),
              ),
            ),
          if (spots.isEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 8, 14, 16),
              child: _EmptyDay(
                accent: accent,
                onAdd: () => _openAddSpotSheet(context),
                nearest: wizard.nearestUnvisitedForDay(dayIndex),
                onAddNearest: () => _addNearest(context),
              ),
            )
          else ...[
            ReorderableListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              buildDefaultDragHandles: false,
              itemCount: spots.length,
              onReorder: (oldIndex, newIndex) {
                wizard.moveSpotWithinDay(dayIndex, oldIndex, newIndex);
              },
              itemBuilder: (context, i) {
                final spot = spots[i];
                TouristLegEstimate? fromPrev;
                if (i > 0) {
                  final legs = buildRouteEstimate(
                    orderedStops: [spots[i - 1], spot],
                    mode: wizard.transportMode,
                    tourists: wizard.travelers,
                  ).legs;
                  if (legs.isNotEmpty) fromPrev = legs.first;
                }
                return _ItinerarySpotCard(
                  key: ValueKey('day$dayIndex-${spot.name}'),
                  index: i,
                  dayIndex: dayIndex,
                  spot: spot,
                  accent: accent,
                  wizard: wizard,
                  startMinutes: starts.length > i ? starts[i] : null,
                  fromPrev: fromPrev,
                  onReorderHandle: (ctx) => ReorderableDragStartListener(
                    index: i,
                    child: const Padding(
                      padding: EdgeInsets.all(8),
                      child: Icon(Icons.drag_handle, color: AppColors.textGrey),
                    ),
                  ),
                );
              },
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 4, 14, 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (spots.length <
                      TripWizardController.absoluteMaxSpotsPerDay) ...[
                    _AddNearestButton(
                      accent: accent,
                      nearest: wizard.nearestUnvisitedForDay(dayIndex),
                      km: _nearestKm(),
                      onPressed: () => _addNearest(context),
                    ),
                    const SizedBox(height: 8),
                  ],
                  OutlinedButton.icon(
                    onPressed: () => _openAddSpotSheet(context),
                    icon: Icon(Icons.add, color: accent),
                    label: Text(
                      'Add another spot',
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        color: accent,
                      ),
                    ),
                    style: OutlinedButton.styleFrom(
                      side: BorderSide(color: accent.withValues(alpha: 0.45)),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                  ),
                  const SizedBox(height: 4),
                  TextButton.icon(
                    onPressed: () => wizard.endDayAt(dayIndex, spots.last),
                    icon: Icon(Icons.flag_outlined, color: accent, size: 18),
                    label: Text(
                      'End day here (last spot: ${spots.last.name})',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        color: accent,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
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

  Future<void> _pickDayStart(BuildContext context) async {
    final current = wizard.dayStartMinutesFor(dayIndex);
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: current ~/ 60, minute: current % 60),
    );
    if (picked == null) return;
    wizard.setDayStartMinutes(dayIndex, picked.hour * 60 + picked.minute);
  }

  double? _nearestKm() {
    final next = wizard.nearestUnvisitedForDay(dayIndex);
    return next == null ? null : wizard.kmFromDayPosition(dayIndex, next);
  }

  void _addNearest(BuildContext context) {
    final err = wizard.addNearestSpotToDay(dayIndex);
    if (err != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(err), backgroundColor: Colors.redAccent),
      );
    }
  }

  Future<void> _openAddSpotSheet(BuildContext context) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: AppColors.planPageBg,
      builder: (ctx) =>
          _AddSpotSheet(wizard: wizard, dayIndex: dayIndex, accent: accent),
    );
  }
}

/// "Add nearest spot" — one Nearest Neighbor step from the day's current
/// location.
class _AddNearestButton extends StatelessWidget {
  final Color accent;
  final TouristSpot? nearest;
  final double? km;
  final VoidCallback onPressed;

  const _AddNearestButton({
    required this.accent,
    required this.nearest,
    required this.km,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final next = nearest;
    return FilledButton.icon(
      style: FilledButton.styleFrom(
        backgroundColor: accent,
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 12),
      ),
      onPressed: next == null ? null : onPressed,
      icon: const Icon(Icons.near_me, size: 18),
      label: Text(
        next == null
            ? 'No unvisited spots nearby'
            : 'Add nearest: ${next.name}'
                  '${km == null ? '' : ' (~${km!.toStringAsFixed(1)} km)'}',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontWeight: FontWeight.w800),
      ),
    );
  }
}

class _EmptyDay extends StatelessWidget {
  final Color accent;
  final VoidCallback onAdd;
  final TouristSpot? nearest;
  final VoidCallback onAddNearest;

  const _EmptyDay({
    required this.accent,
    required this.onAdd,
    required this.nearest,
    required this.onAddNearest,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 16),
      decoration: BoxDecoration(
        color: AppColors.insetSurface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: accent.withValues(alpha: 0.2),
          style: BorderStyle.solid,
        ),
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
            'No spots added yet',
            style: TextStyle(
              fontWeight: FontWeight.w800,
              fontSize: 16,
              color: AppColors.textDark,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Pick attractions along your route for this day.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 13,
              color: AppColors.textGrey.withValues(alpha: 0.95),
            ),
          ),
          const SizedBox(height: 14),
          Wrap(
            alignment: WrapAlignment.center,
            spacing: 8,
            runSpacing: 8,
            children: [
              FilledButton.icon(
                style: FilledButton.styleFrom(backgroundColor: accent),
                onPressed: nearest == null ? null : onAddNearest,
                icon: const Icon(Icons.near_me),
                label: const Text('Add nearest spot'),
              ),
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(foregroundColor: accent),
                onPressed: onAdd,
                icon: const Icon(Icons.add),
                label: const Text('Add spot'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ItinerarySpotCard extends StatelessWidget {
  final int index;
  final int dayIndex;
  final TouristSpot spot;
  final Color accent;
  final TripWizardController wizard;
  final int? startMinutes;
  final TouristLegEstimate? fromPrev;
  final Widget Function(BuildContext) onReorderHandle;

  const _ItinerarySpotCard({
    super.key,
    required this.index,
    required this.dayIndex,
    required this.spot,
    required this.accent,
    required this.wizard,
    required this.startMinutes,
    required this.fromPrev,
    required this.onReorderHandle,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        if (fromPrev != null)
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
                    '${fromPrev!.timeLabel} - ${fromPrev!.distanceLabel} - '
                    '${transportModeLabel(wizard.transportMode)}'
                    '${fromPrev!.transportFeePhp > 0 ? ' - ${formatFarePhp(fromPrev!.transportFeePhp)}' : ''}',
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
                MaterialPageRoute(builder: (_) => SpotDetailScreen(spot: spot)),
              );
            },
            child: Padding(
              padding: const EdgeInsets.fromLTRB(8, 8, 8, 10),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  onReorderHandle(context),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: SizedBox(
                      width: 72,
                      height: 72,
                      child: buildTouristSpotProfileImage(
                        spot,
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
                        Row(
                          children: [
                            if (startMinutes != null)
                              GestureDetector(
                                onTap: () => _editTime(context),
                                child: Container(
                                  margin: const EdgeInsets.only(right: 8),
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 3,
                                  ),
                                  decoration: BoxDecoration(
                                    color: accent.withValues(alpha: 0.12),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Text(
                                    _fmtClock(startMinutes!),
                                    style: TextStyle(
                                      fontWeight: FontWeight.w900,
                                      fontSize: 12,
                                      color: accent,
                                    ),
                                  ),
                                ),
                              ),
                            Expanded(
                              child: Text(
                                spot.name,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w800,
                                  fontSize: 14.5,
                                  color: AppColors.textDark,
                                ),
                              ),
                            ),
                          ],
                        ),
                        if (spot.location.trim().isNotEmpty) ...[
                          const SizedBox(height: 2),
                          Text(
                            spot.location,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 12.5,
                              color: AppColors.textGrey,
                            ),
                          ),
                        ],
                        const SizedBox(height: 4),
                        Wrap(
                          spacing: 8,
                          runSpacing: 4,
                          children: [
                            _meta(
                              Icons.star_rounded,
                              spot.rating.toStringAsFixed(1),
                            ),
                            _meta(
                              Icons.schedule,
                              '~${formatHoursMinutes(estimatedStayMinutes(spot))}',
                            ),
                            if (fromPrev != null)
                              _meta(Icons.straighten, fromPrev!.distanceLabel),
                            _meta(
                              Icons.directions_transit_filled_outlined,
                              transportModeLabel(wizard.transportMode),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  PopupMenuButton<String>(
                    tooltip: 'Options',
                    onSelected: (v) => _onMenu(context, v),
                    itemBuilder: (_) => [
                      const PopupMenuItem(
                        value: 'time',
                        child: Text('Set time'),
                      ),
                      const PopupMenuItem(
                        value: 'last',
                        child: Text('Make last spot (end day here)'),
                      ),
                      const PopupMenuItem(
                        value: 'move',
                        child: Text('Move to another day'),
                      ),
                      const PopupMenuItem(
                        value: 'edit',
                        child: Text('View / edit details'),
                      ),
                      const PopupMenuItem(
                        value: 'remove',
                        child: Text('Remove'),
                      ),
                    ],
                    icon: const Icon(Icons.more_vert, size: 20),
                  ),
                ],
              ),
            ),
          ),
        ),
        const Divider(height: 1, indent: 56),
      ],
    );
  }

  Widget _meta(IconData icon, String text) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Icon(icon, size: 13, color: AppColors.textGrey),
      const SizedBox(width: 3),
      Text(
        text,
        style: const TextStyle(
          fontSize: 11.5,
          fontWeight: FontWeight.w600,
          color: AppColors.textGrey,
        ),
      ),
    ],
  );

  Future<void> _editTime(BuildContext context) async {
    final base = startMinutes ?? wizard.dayStartMinutesFor(dayIndex);
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: base ~/ 60, minute: base % 60),
    );
    if (picked == null) return;
    wizard.setSpotStartOverride(
      dayIndex,
      spot,
      picked.hour * 60 + picked.minute,
    );
  }

  Future<void> _onMenu(BuildContext context, String value) async {
    switch (value) {
      case 'time':
        await _editTime(context);
      case 'last':
        wizard.endDayAt(dayIndex, spot);
      case 'move':
        await _moveDay(context);
      case 'edit':
        if (!context.mounted) return;
        await Navigator.of(
          context,
        ).push(MaterialPageRoute(builder: (_) => SpotDetailScreen(spot: spot)));
      case 'remove':
        final ok = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Remove spot?'),
            content: Text('Remove "${spot.name}" from Day ${dayIndex + 1}?'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                style: FilledButton.styleFrom(backgroundColor: accent),
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Remove'),
              ),
            ],
          ),
        );
        if (ok == true) {
          wizard.removeSpotFromDay(spot, dayIndex);
        }
    }
  }

  Future<void> _moveDay(BuildContext context) async {
    final days = wizard.tripDays;
    final picked = await showModalBottomSheet<int>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Move to day',
                  style: TextStyle(fontWeight: FontWeight.w800, fontSize: 17),
                ),
              ),
            ),
            for (var d = 0; d < days; d++)
              ListTile(
                enabled: d != dayIndex,
                title: Text('Day ${d + 1}'),
                trailing: d == dayIndex
                    ? const Text(
                        'Current',
                        style: TextStyle(color: AppColors.textGrey),
                      )
                    : Icon(Icons.arrow_forward, color: accent),
                onTap: d == dayIndex ? null : () => Navigator.pop(ctx, d),
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (picked == null) return;
    final err = wizard.moveSpotToDay(spot, picked);
    if (err != null && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(err), backgroundColor: Colors.redAccent),
      );
    }
  }
}

class _AddSpotSheet extends StatefulWidget {
  final TripWizardController wizard;
  final int dayIndex;
  final Color accent;

  const _AddSpotSheet({
    required this.wizard,
    required this.dayIndex,
    required this.accent,
  });

  @override
  State<_AddSpotSheet> createState() => _AddSpotSheetState();
}

class _AddSpotSheetState extends State<_AddSpotSheet> {
  final _search = TextEditingController();
  final _selected = <String>{};

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  List<TouristSpot> get _candidates {
    final q = _search.text.trim().toLowerCase();
    var list = widget.wizard.spotsAvailableForDay(widget.dayIndex);
    if (q.isNotEmpty) {
      list = list
          .where(
            (s) =>
                s.name.toLowerCase().contains(q) ||
                s.location.toLowerCase().contains(q),
          )
          .toList();
    }
    return list;
  }

  @override
  Widget build(BuildContext context) {
    final list = _candidates;
    final h = MediaQuery.sizeOf(context).height * 0.72;
    return SizedBox(
      height: h,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Add to Day ${widget.dayIndex + 1}',
                  style: const TextStyle(
                    fontWeight: FontWeight.w900,
                    fontSize: 18,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  widget.dayIndex == 0
                      ? 'Day 1 shows only the places nearest your starting '
                            'point, closest first. Spots already used on another '
                            'day stay hidden.'
                      : 'Closest to ${widget.wizard.dayCurrentLabel(widget.dayIndex)} '
                            'first. Spots already used on another day are hidden here.',
                  style: TextStyle(
                    color: AppColors.textGrey.withValues(alpha: 0.95),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _search,
                  onChanged: (_) => setState(() {}),
                  decoration: InputDecoration(
                    hintText: 'Search spots...',
                    prefixIcon: const Icon(Icons.search),
                    filled: true,
                    fillColor: Colors.white,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    isDense: true,
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: list.isEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(
                        widget.dayIndex == 0
                            ? 'No unused spots near your starting point for Day 1.'
                            : 'No more unused spots available for this day.',
                        textAlign: TextAlign.center,
                      ),
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
                    itemCount: list.length,
                    itemBuilder: (context, i) {
                      final s = list[i];
                      final checked = _selected.contains(s.name);
                      return CheckboxListTile(
                        value: checked,
                        activeColor: widget.accent,
                        secondary: ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: SizedBox(
                            width: 48,
                            height: 48,
                            child: buildTouristSpotProfileImage(
                              s,
                              fallback: Container(
                                color: widget.accent.withValues(alpha: 0.12),
                                child: Icon(Icons.place, color: widget.accent),
                              ),
                              memCacheWidth: 96,
                              memCacheHeight: 96,
                            ),
                          ),
                        ),
                        title: Text(
                          s.name,
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                        subtitle: Builder(
                          builder: (context) {
                            final km = widget.wizard.kmFromDayPosition(
                              widget.dayIndex,
                              s,
                            );
                            final from = widget.wizard.dayCurrentLabel(
                              widget.dayIndex,
                            );
                            return Text(
                              '${s.location} - ${s.rating.toStringAsFixed(1)}'
                              '${km == null ? '' : ' - ~${km.toStringAsFixed(1)} km from $from'}',
                            );
                          },
                        ),
                        onChanged: (v) {
                          setState(() {
                            if (v == true) {
                              _selected.add(s.name);
                            } else {
                              _selected.remove(s.name);
                            }
                          });
                        },
                      );
                    },
                  ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Cancel'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    flex: 2,
                    child: FilledButton(
                      style: FilledButton.styleFrom(
                        backgroundColor: widget.accent,
                      ),
                      onPressed: _selected.isEmpty
                          ? null
                          : () {
                              final byName = {for (final s in list) s.name: s};
                              for (final name in _selected) {
                                final spot = byName[name];
                                if (spot == null) continue;
                                widget.wizard.addCatalogSpotToDay(
                                  spot,
                                  widget.dayIndex,
                                );
                              }
                              Navigator.pop(context);
                            },
                      child: Text(
                        _selected.isEmpty
                            ? 'Add spot'
                            : 'Add ${_selected.length} spot${_selected.length == 1 ? '' : 's'}',
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _TripSummaryCard extends StatelessWidget {
  final TripWizardController wizard;
  final Color accent;

  const _TripSummaryCard({required this.wizard, required this.accent});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [accent.withValues(alpha: 0.12), Colors.white],
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
          _row('Days', '${wizard.tripDays}'),
          _row('Spots on itinerary', '${wizard.assignedSpotCount}'),
          _row(
            'Total distance',
            wizard.totalAssignedDistanceKm > 0
                ? '~${wizard.totalAssignedDistanceKm.toStringAsFixed(1)} km'
                : '-',
          ),
          _row(
            'Travel time',
            wizard.totalAssignedTravelMinutes > 0
                ? formatHoursMinutes(wizard.totalAssignedTravelMinutes)
                : '-',
          ),
          if (wizard.needsAccommodation)
            _row('Accommodation nights', '${wizard.nights}'),
          _row(
            'Transport (days)',
            formatFarePhp(wizard.totalAssignedTransportPhp),
          ),
          _row('Entrances', formatFarePhp(wizard.entranceFeesTotal)),
          _row('Food (est.)', formatFarePhp(wizard.foodEstimatePhp)),
          if (wizard.needsAccommodation)
            _row(
              'Lodging (est.)',
              formatFarePhp(wizard.accommodationEstimatePhp),
            ),
          const Divider(height: 20),
          _row(
            'Estimated overall',
            formatFarePhp(wizard.estimatedTotalPhp),
            bold: true,
          ),
          _row('Your budget', formatFarePhp(wizard.budgetPhp.round())),
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

String _fmtDate(DateTime d) {
  const m = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];
  return '${m[d.month - 1]} ${d.day}, ${d.year}';
}

String _fmtClock(int minutes) {
  final h24 = (minutes ~/ 60) % 24;
  final m = minutes % 60;
  final period = h24 >= 12 ? 'PM' : 'AM';
  final h12 = h24 == 0 ? 12 : (h24 > 12 ? h24 - 12 : h24);
  final mm = m.toString().padLeft(2, '0');
  return '$h12:$mm $period';
}

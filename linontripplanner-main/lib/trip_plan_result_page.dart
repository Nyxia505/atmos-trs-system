import 'dart:async';

import 'package:flutter/material.dart';

import 'algorithms/on_device_trip_planner.dart';
import 'data.dart';
import 'event_datetime_format.dart';
import 'trip_plan_route_map_page.dart';
import 'trip_planner_utils.dart';
import 'trip_preferences_store.dart';
import 'trip_recommendation_engine.dart';
import 'itinerary_transport_service.dart';
import 'trip_route_fare_service.dart';
import 'services/spot_ratings_store.dart';
import 'widgets/municipality_image.dart';
import 'widgets/responsive_layout.dart';
import 'widgets/tourism_plan_ui.dart';

class TripPlanResultPage extends StatefulWidget {
  final DateTimeRange dateRange;
  final Municipality start;
  final Municipality end;
  final int numberOfTourists;
  final String transportMode;
  final List<String> interests;
  final double budget;
  final String budgetTierLabel;
  final List<TouristSpot> spots;
  final List<Municipality> municipalitiesAlongRoute;
  final TripRouteFareBreakdown? routeFareBreakdown;
  final Set<String> exactBudgetSpotNames;
  final List<TourismEvent> routeEvents;
  final String insightSummary;
  /// Ranked spots along the route (for add-to-itinerary picker).
  final List<ScoredRecommendation> alternativeSpots;
  final Set<String> routeLocationAliases;

  const TripPlanResultPage({
    super.key,
    required this.dateRange,
    required this.start,
    required this.end,
    this.numberOfTourists = 1,
    required this.transportMode,
    required this.interests,
    required this.budget,
    this.budgetTierLabel = '',
    required this.spots,
    required this.municipalitiesAlongRoute,
    this.routeFareBreakdown,
    required this.exactBudgetSpotNames,
    this.routeEvents = const [],
    this.insightSummary = '',
    this.alternativeSpots = const [],
    this.routeLocationAliases = const {},
  });

  @override
  State<TripPlanResultPage> createState() => _TripPlanResultPageState();
}

class _TripPlanResultPageState extends State<TripPlanResultPage> {
  Timer? _ratingTimer;
  bool _ratingPromptOpen = false;
  final Set<String> _promptedSpotKeys = <String>{};
  final Map<String, DateTime> _snoozedUntil = <String, DateTime>{};
  TripRouteFareBreakdown? _itineraryTransportFare;
  late List<TouristSpot> _itinerarySpots;
  List<Municipality> _itineraryMunicipalities = const [];

  int get _days =>
      widget.dateRange.end.difference(widget.dateRange.start).inDays + 1;

  String get _dateRangeLabel {
    final startStr =
        '${_monthName(widget.dateRange.start.month)} ${widget.dateRange.start.day}, ${widget.dateRange.start.year}';
    final endStr =
        '${_monthName(widget.dateRange.end.month)} ${widget.dateRange.end.day}, ${widget.dateRange.end.year}';
    return '$startStr - $endStr';
  }

  bool get _showTransportationFees =>
      shouldShowTransportationFees(widget.transportMode);

  TripRouteFareBreakdown? get _effectiveItineraryTransportFare {
    if (!_showTransportationFees) return null;
    return _itineraryTransportFare;
  }

  @override
  void initState() {
    super.initState();
    _itinerarySpots = List<TouristSpot>.from(widget.spots);
    _itineraryMunicipalities =
        orderedMunicipalitiesWithItinerarySpots(_itinerarySpots);
    _applyLocalFare();
    if (_showTransportationFees) {
      unawaited(_loadRouteFares());
    }
    _startRatingWatcher();
  }

  void _applyLocalFare() {
    if (!_showTransportationFees) {
      _itineraryTransportFare = null;
      return;
    }
    _itineraryTransportFare = widget.routeFareBreakdown ??
        buildItineraryTransportFareBreakdownSync(_itinerarySpots);
  }

  Future<void> _loadRouteFares() async {
    if (!_showTransportationFees) return;

    final breakdown =
        await buildItineraryTransportFareBreakdown(_itinerarySpots);
    if (!mounted) return;
    setState(() {
      _itineraryTransportFare = breakdown ??
          buildItineraryTransportFareBreakdownSync(_itinerarySpots);
    });
  }

  String _spotKey(TouristSpot spot) =>
      spot.firestoreDocId ?? '${spot.name}|${normalizeMunicipalityName(spot.location)}';

  Set<String> get _itinerarySpotKeys =>
      _itinerarySpots.map(_spotKey).toSet();

  int get _maxSpotsPerDay =>
      OnDeviceTripPlanner.maxSpotsPerDay(widget.transportMode);

  int get _maxTotalSpots => _days * _maxSpotsPerDay;

  List<TouristSpot> _routePickableSpots() {
    final byKey = <String, TouristSpot>{};
    for (final rec in widget.alternativeSpots) {
      byKey[_spotKey(rec.spot)] = rec.spot;
    }
    if (byKey.isEmpty) {
      for (final spot in allSpots) {
        final loc = normalizeMunicipalityName(spot.location);
        if (widget.routeLocationAliases.contains(loc)) {
          byKey[_spotKey(spot)] = spot;
        }
      }
    }
    final list = byKey.values.toList()
      ..sort((a, b) => a.name.compareTo(b.name));
    return list;
  }

  List<TouristSpot> _spotsAvailableToAdd() {
    return _routePickableSpots()
        .where((s) => !_itinerarySpotKeys.contains(_spotKey(s)))
        .toList();
  }

  int _startIndexForDay(int dayIndex) {
    var start = 0;
    for (var d = 0; d < dayIndex; d++) {
      start += _spotsForDay(d).length;
    }
    return start;
  }

  void _refreshAfterItineraryEdit() {
    setState(() {
      _itineraryMunicipalities =
          orderedMunicipalitiesWithItinerarySpots(_itinerarySpots);
    });
    _applyLocalFare();
    if (_showTransportationFees) {
      unawaited(_loadRouteFares());
    }
  }

  void _showItinerarySnack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
    );
  }

  Future<void> _confirmRemoveSpot(int dayIndex, int indexInDay) async {
    final daySpots = _spotsForDay(dayIndex);
    if (indexInDay < 0 || indexInDay >= daySpots.length) return;
    final spot = daySpots[indexInDay];
    final remove = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remove from plan?'),
        content: Text(
          'Remove "${spot.name}" from Day ${dayIndex + 1}? You can add it again later.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (remove != true || !mounted) return;
    final global = _startIndexForDay(dayIndex) + indexInDay;
    if (global < 0 || global >= _itinerarySpots.length) return;
    setState(() => _itinerarySpots.removeAt(global));
    _refreshAfterItineraryEdit();
    _showItinerarySnack('Removed ${spot.name}');
  }

  void _addSpotToDay(int dayIndex, TouristSpot spot) {
    final dayCount = _spotsForDay(dayIndex).length;
    if (dayCount >= _maxSpotsPerDay) {
      _showItinerarySnack(
        'Day ${dayIndex + 1} already has $_maxSpotsPerDay stops (max for ${widget.transportMode}).',
      );
      return;
    }
    if (_itinerarySpots.length >= _maxTotalSpots) {
      _showItinerarySnack('This trip allows up to $_maxTotalSpots stops.');
      return;
    }
    if (_itinerarySpotKeys.contains(_spotKey(spot))) {
      _showItinerarySnack('${spot.name} is already in your plan.');
      return;
    }
    setState(() {
      _itinerarySpots.insert(_startIndexForDay(dayIndex) + dayCount, spot);
    });
    _refreshAfterItineraryEdit();
    _showItinerarySnack('Added ${spot.name} to Day ${dayIndex + 1}');
  }

  Future<void> _openSpotPicker(int dayIndex) async {
    final available = _spotsAvailableToAdd();
    if (available.isEmpty) {
      _showItinerarySnack('No more spots along your route to add.');
      return;
    }
    final dayCount = _spotsForDay(dayIndex).length;
    if (dayCount >= _maxSpotsPerDay) {
      _showItinerarySnack('This day is full ($_maxSpotsPerDay stops max).');
      return;
    }
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _ItinerarySpotPickerSheet(
        dayNumber: dayIndex + 1,
        spots: available,
        budget: widget.budget,
        exactBudgetSpotNames: widget.exactBudgetSpotNames,
        onPick: (spot) {
          Navigator.pop(ctx);
          _addSpotToDay(dayIndex, spot);
        },
      ),
    );
  }

  @override
  void dispose() {
    _ratingTimer?.cancel();
    super.dispose();
  }

  String _monthName(int month) {
    const months = [
      'January',
      'February',
      'March',
      'April',
      'May',
      'June',
      'July',
      'August',
      'September',
      'October',
      'November',
      'December',
    ];
    return months[month - 1];
  }

  IconData _transportIcon() {
    switch (widget.transportMode) {
      case 'Motorcycle':
        return Icons.two_wheeler_rounded;
      case 'Car':
        return Icons.directions_car_rounded;
      case 'Public Transport':
      default:
        return Icons.directions_bus_rounded;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.planPageBg,
      appBar: AppBar(
        title: const Text('Your Plan'),
      ),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final maxW = tourismContentMaxWidth(constraints.maxWidth);
            final hPad = tourismPagePadding(constraints.maxWidth);
            return Align(
              alignment: Alignment.topCenter,
              child: ConstrainedBox(
                constraints: BoxConstraints(maxWidth: maxW),
                child: ListView(
                  padding: EdgeInsets.fromLTRB(hPad, 4, hPad, 28),
              children: [
                _buildPlanHeroBanner(),
                const SizedBox(height: 16),
                _buildSummaryCard(),
                const SizedBox(height: 16),
                _buildMunicipalitiesAlongRoute(),
                const SizedBox(height: 16),
                _buildBudgetFilterCard(),
                if (widget.routeEvents.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  _buildEventsPreview(),
                ],
                const SizedBox(height: 16),
                _buildViewRoutesButton(context),
                const SizedBox(height: 24),
                _buildItinerarySectionHeader(),
                _buildItineraryEditHint(),
                const SizedBox(height: 4),
                ...List.generate(_days, (index) {
                  final dayNumber = index + 1;
                  final daySpots = _spotsForDay(index);
                  return Padding(
                    padding: EdgeInsets.only(top: index == 0 ? 0 : 16),
                    child: _buildDayCard(
                      context,
                      dayIndex: index,
                      dayNumber: dayNumber,
                      daySpots: daySpots,
                    ),
                  );
                }),
              ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildPlanHeroBanner() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: TourismPlanUi.primaryGradient,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withValues(alpha: 0.35),
            blurRadius: 16,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.22),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  '$_days day${_days > 1 ? 's' : ''}',
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  ),
                ),
              ),
              const Spacer(),
              Icon(_transportIcon(), color: Colors.white.withValues(alpha: 0.95), size: 22),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            _dateRangeLabel,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: Colors.white.withValues(alpha: 0.92),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.trip_origin, size: 16, color: Colors.white),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  widget.start.shortName.isNotEmpty
                      ? widget.start.shortName
                      : widget.start.name,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                  ),
                ),
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Row(
              children: [
                Container(
                  width: 2,
                  height: 20,
                  margin: const EdgeInsets.only(left: 7),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.5),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(width: 12),
                Icon(
                  Icons.arrow_downward_rounded,
                  size: 16,
                  color: Colors.white.withValues(alpha: 0.8),
                ),
              ],
            ),
          ),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.place_rounded, size: 16, color: Colors.white),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  widget.end.shortName.isNotEmpty
                      ? widget.end.shortName
                      : widget.end.name,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildItinerarySectionHeader() {
    return TourismPlanUi.sectionTitleBar(
      title: 'Daily itinerary',
      trailing:
          '${_itinerarySpots.length} spot${_itinerarySpots.length == 1 ? '' : 's'}',
    );
  }

  Widget _buildItineraryEditHint() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          Icon(
            Icons.edit_outlined,
            size: 16,
            color: AppColors.primary.withValues(alpha: 0.9),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              'Remove stops with × or add spots from along your route.',
              style: TextStyle(
                fontSize: 12.5,
                color: AppColors.textGrey.withValues(alpha: 0.95),
                height: 1.3,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryCard() {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: TourismPlanUi.planCardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TourismPlanUi.sectionHeader(
            icon: Icons.summarize_rounded,
            title: 'Trip summary',
          ),
          const SizedBox(height: 14),
          _summaryRow(Icons.calendar_month_outlined, 'Dates', _dateRangeLabel),
          _summaryDivider(),
          _summaryRow(
            Icons.timelapse_rounded,
            'Duration',
            '$_days day${_days > 1 ? 's' : ''}',
          ),
          _summaryDivider(),
          _summaryRow(
            Icons.route_rounded,
            'Route',
            '${widget.start.shortName.isNotEmpty ? widget.start.shortName : widget.start.name} → ${widget.end.shortName.isNotEmpty ? widget.end.shortName : widget.end.name}',
            valueColor: AppColors.primary,
          ),
          _summaryDivider(),
          _summaryRow(
            Icons.groups_outlined,
            'Number of tourist',
            '${widget.numberOfTourists} ${widget.numberOfTourists == 1 ? 'person' : 'people'}',
          ),
          _summaryDivider(),
          _summaryRow(
            _transportIcon(),
            'Transport',
            widget.transportMode,
          ),
          if (widget.interests.isNotEmpty) ...[
            _summaryDivider(),
            _interestsSummaryBlock(),
          ],
          _summaryDivider(),
          _summaryRow(
            Icons.account_balance_wallet_outlined,
            'Budget',
            widget.budgetTierLabel.isNotEmpty
                ? '${widget.budgetTierLabel} (₱${widget.budget.toStringAsFixed(0)})'
                : '₱${widget.budget.toStringAsFixed(0)}',
            valueColor: AppColors.primary,
          ),
        ],
      ),
    );
  }

  Widget _summaryDivider() => Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Divider(
          height: 1,
          thickness: 1,
          color: Colors.black.withValues(alpha: 0.06),
        ),
      );

  Widget _interestsSummaryBlock() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.favorite_border_rounded, size: 18, color: AppColors.textGrey.withValues(alpha: 0.9)),
              const SizedBox(width: 10),
              const Text(
                'Interests',
                style: TextStyle(fontSize: 13, color: AppColors.textGrey),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: widget.interests
                .map(
                  (i) => Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: AppColors.primary.withValues(alpha: 0.22),
                      ),
                    ),
                    child: Text(
                      i,
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: AppColors.primary,
                      ),
                    ),
                  ),
                )
                .toList(),
          ),
        ],
      ),
    );
  }

  Widget _buildEventsPreview() {
    final preview = widget.routeEvents.take(3).toList();
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: TourismPlanUi.planCardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TourismPlanUi.sectionHeader(
            icon: Icons.event_rounded,
            title: 'Events on your route',
            badge: '${widget.routeEvents.length}',
          ),
          const SizedBox(height: 12),
          ...preview.map(
            (e) => Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: const Color(0xFFF8F9FB),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(
                      Icons.event_rounded,
                      size: 20,
                      color: AppColors.primary,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          e.title,
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: AppColors.textDark,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          formatEventDateTimeDisplay(e.dateTime),
                          style: const TextStyle(
                            fontSize: 11,
                            color: AppColors.textGrey,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (widget.routeEvents.length > 3)
            Text(
              '+ ${widget.routeEvents.length - 3} more',
              style: const TextStyle(fontSize: 12, color: AppColors.textGrey),
            ),
        ],
      ),
    );
  }

  Widget _buildViewRoutesButton(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton.icon(
        onPressed: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => TripPlanRouteMapPage(
                start: widget.start,
                end: widget.end,
                spots: _itinerarySpots,
                budget: widget.budget,
                exactBudgetSpotNames: widget.exactBudgetSpotNames,
                routeFareBreakdown: _effectiveItineraryTransportFare,
                transportMode: widget.transportMode,
              ),
            ),
          );
        },
        icon: const Icon(Icons.map_outlined, size: 20),
        label: const Text('View Routes on Map'),
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.primary,
          backgroundColor: Colors.transparent,
          side: const BorderSide(color: AppColors.primary, width: 1.5),
          padding: const EdgeInsets.symmetric(vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
      ),
    );
  }

  int _scaledFare(int perPersonFarePhp) =>
      scaleTransportFareForTourists(perPersonFarePhp, widget.numberOfTourists);

  Widget _summaryRow(
    IconData icon,
    String label,
    String value, {
    Color? valueColor,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: AppColors.textGrey.withValues(alpha: 0.85)),
          const SizedBox(width: 10),
          Expanded(
            flex: 2,
            child: Text(
              label,
              style: const TextStyle(fontSize: 13, color: AppColors.textGrey),
            ),
          ),
          Expanded(
            flex: 3,
            child: Text(
              value,
              textAlign: TextAlign.end,
              style: TextStyle(
                fontSize: 13.5,
                fontWeight: FontWeight.w600,
                color: valueColor ?? AppColors.textDark,
                height: 1.3,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMunicipalitiesAlongRoute() {
    if (_itineraryMunicipalities.isEmpty) return const SizedBox.shrink();
    final interSegments = _showTransportationFees
        ? (_itineraryTransportFare?.segments ?? const [])
        : const [];
    final hubSpotSegments = _showTransportationFees
        ? (_itineraryTransportFare?.hubSpotSegments ?? const [])
        : const [];
    final lineCount = interSegments.length + hubSpotSegments.length;
    final showLegTotal =
        _showTransportationFees && lineCount > 1 && _itineraryTransportFare != null;
    final tourists = widget.numberOfTourists;
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: TourismPlanUi.planCardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TourismPlanUi.sectionHeader(
            icon: Icons.location_city_rounded,
            title: 'Municipalities in itinerary',
            badge: '${_itineraryMunicipalities.length}',
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _itineraryMunicipalities
                .map(
                  (m) => Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          AppColors.primary.withValues(alpha: 0.08),
                          AppColors.primaryLight.withValues(alpha: 0.05),
                        ],
                      ),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: AppColors.primary.withValues(alpha: 0.28),
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.place_rounded,
                          size: 14,
                          color: AppColors.primary.withValues(alpha: 0.9),
                        ),
                        const SizedBox(width: 4),
                        Text(
                          m.shortName.isNotEmpty ? m.shortName : m.name,
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: AppColors.textDark,
                          ),
                        ),
                      ],
                    ),
                  ),
                )
                .toList(),
          ),
          if (interSegments.isNotEmpty) ...[
            const SizedBox(height: 18),
            _fareSubsectionTitle(
              tourists > 1
                  ? 'Fare by leg (×$tourists tourists)'
                  : 'Fare by leg (between municipalities)',
            ),
            const SizedBox(height: 8),
            ...interSegments.map(
              (s) => _fareBreakdownRow(
                s.label,
                formatFarePhp(_scaledFare(s.farePhp)),
              ),
            ),
          ],
          if (hubSpotSegments.isNotEmpty) ...[
            const SizedBox(height: 18),
            _fareSubsectionTitle(
              tourists > 1
                  ? 'Hub ↔ tourist spot (×$tourists tourists)'
                  : 'Hub ↔ tourist spot',
            ),
            const SizedBox(height: 8),
            ...hubSpotSegments.map(
              (s) => _fareBreakdownRow(
                s.label,
                formatFarePhp(_scaledFare(s.farePhp)),
              ),
            ),
          ],
          if (showLegTotal) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(12),
              ),
              child: _fareBreakdownRow(
                'Total itinerary transport',
                formatFarePhp(
                  _itineraryTransportFare!.totalFarePhpForTourists(tourists),
                ),
                bold: true,
                compact: true,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _fareSubsectionTitle(String title) {
    return Row(
      children: [
        Container(
          width: 3,
          height: 16,
          decoration: BoxDecoration(
            color: AppColors.primary,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            title,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: AppColors.textDark,
            ),
          ),
        ),
      ],
    );
  }

  Widget _fareBreakdownRow(
    String label,
    String fare, {
    bool bold = false,
    bool compact = false,
  }) {
    return Container(
      margin: EdgeInsets.only(bottom: compact ? 0 : 6),
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 0 : 10,
        vertical: compact ? 0 : 8,
      ),
      decoration: compact
          ? null
          : BoxDecoration(
              color: const Color(0xFFF8F9FB),
              borderRadius: BorderRadius.circular(10),
            ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!compact)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Icon(
                Icons.swap_horiz_rounded,
                size: 16,
                color: AppColors.textGrey.withValues(alpha: 0.7),
              ),
            ),
          if (!compact) const SizedBox(width: 8),
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: bold ? FontWeight.w700 : FontWeight.w500,
                color: AppColors.textDark,
                height: 1.35,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Text(
            fare,
            style: TextStyle(
              fontSize: bold ? 14 : 13,
              fontWeight: FontWeight.w800,
              color: bold ? AppColors.primary : AppColors.textDark,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBudgetFilterCard() {
    final exactCount = _itinerarySpots
        .where(
          (spot) =>
              widget.exactBudgetSpotNames.contains(spot.name) ||
              evaluateBudgetFit(spot, widget.budget).exactBudgetMatch,
        )
        .length;
    final withinCount = _itinerarySpots.length - exactCount;

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: TourismPlanUi.planCardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TourismPlanUi.sectionHeader(
            icon: Icons.savings_outlined,
            title: 'Budget filter',
            badge: '₱${widget.budget.toStringAsFixed(0)}',
          ),
          const SizedBox(height: 10),
          Text(
            'Spots in your itinerary are grouped by municipality and matched to this budget.',
            style: TextStyle(
              fontSize: 12.5,
              color: AppColors.textGrey.withValues(alpha: 0.95),
              height: 1.4,
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: _budgetStatBox(
                  label: 'Budget match',
                  value: '$exactCount',
                  color: const Color(0xFF1E8E3E),
                  bg: const Color(0xFFE6F4EA),
                  icon: Icons.check_circle_outline_rounded,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _budgetStatBox(
                  label: 'Within budget',
                  value: '$withinCount',
                  color: const Color(0xFFE37400),
                  bg: const Color(0xFFFFF4E5),
                  icon: Icons.trending_down_rounded,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _budgetStatBox({
    required String label,
    required String value,
    required Color color,
    required Color bg,
    required IconData icon,
  }) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: color),
          const SizedBox(height: 8),
          Text(
            value,
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w800,
              color: color,
              height: 1,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w600,
              color: color.withValues(alpha: 0.85),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDayCard(
    BuildContext context, {
    required int dayIndex,
    required int dayNumber,
    required List<TouristSpot> daySpots,
  }) {
    final canAddMore = daySpots.length < _maxSpotsPerDay &&
        _itinerarySpots.length < _maxTotalSpots &&
        _spotsAvailableToAdd().isNotEmpty;
    final schedules = _buildSchedulesForDay(daySpots);
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: TourismPlanUi.planCardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              TourismPlanUi.dayBadge('Day $dayNumber'),
              const SizedBox(width: 10),
              Text(
                daySpots.isEmpty
                    ? 'Rest day'
                    : '${daySpots.length} stop${daySpots.length == 1 ? '' : 's'}',
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textGrey,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (daySpots.isEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: const Color(0xFFF8F9FB),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  Icon(Icons.self_improvement_outlined, color: AppColors.textGrey.withValues(alpha: 0.8)),
                  const SizedBox(width: 10),
                  const Expanded(
                    child: Text(
                      'No stops yet — add spots below or keep this as a rest day.',
                      style: TextStyle(
                        fontSize: 13,
                        color: AppColors.textGrey,
                        height: 1.4,
                      ),
                    ),
                  ),
                ],
              ),
            )
          else
            ...daySpots.asMap().entries.map(
              (entry) => Padding(
                padding: EdgeInsets.only(top: entry.key == 0 ? 0 : 12),
                child: _SpotRow(
                  spot: entry.value,
                  exactBudgetMatch:
                      widget.exactBudgetSpotNames.contains(entry.value.name) ||
                      evaluateBudgetFit(
                        entry.value,
                        widget.budget,
                      ).exactBudgetMatch,
                  periodLabel: schedules[entry.key].periodLabel,
                  timeRangeLabel:
                      '${schedules[entry.key].startLabel} - ${schedules[entry.key].endLabel}',
                  durationLabel: schedules[entry.key].durationLabel,
                  transferLabel: schedules[entry.key].transferLabel,
                  onRemove: () => _confirmRemoveSpot(dayIndex, entry.key),
                ),
              ),
            ),
          if (canAddMore) ...[
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () => _openSpotPicker(dayIndex),
                icon: const Icon(Icons.add_location_alt_outlined, size: 18),
                label: const Text('Add spot to this day'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.primary,
                  side: BorderSide(
                    color: AppColors.primary.withValues(alpha: 0.45),
                  ),
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  List<TouristSpot> _spotsForDay(int dayIndex) {
    if (_itinerarySpots.isEmpty || _days <= 0) return const <TouristSpot>[];
    final base = _itinerarySpots.length ~/ _days;
    final remainder = _itinerarySpots.length % _days;
    final countForThisDay = base + (dayIndex < remainder ? 1 : 0);
    if (countForThisDay == 0) return const <TouristSpot>[];

    var startIndex = 0;
    for (var i = 0; i < dayIndex; i++) {
      startIndex += base + (i < remainder ? 1 : 0);
    }
    return _itinerarySpots.skip(startIndex).take(countForThisDay).toList();
  }

  List<_SpotSchedule> _buildSchedulesForDay(List<TouristSpot> daySpots) {
    if (daySpots.length == 2) {
      return const [
        _SpotSchedule(
          periodLabel: 'Morning',
          startMinutes: 8 * 60,
          startLabel: '8:00 AM',
          endLabel: '12:00 PM',
          durationLabel: '4.0h stay',
          transferLabel: 'Lunch / travel break: 60 min',
        ),
        _SpotSchedule(
          periodLabel: 'Afternoon',
          startMinutes: 13 * 60,
          startLabel: '1:00 PM',
          endLabel: '5:00 PM',
          durationLabel: '4.0h stay',
        ),
      ];
    }

    final schedules = <_SpotSchedule>[];
    var cursorMinutes = 8 * 60; // 8:00 AM start
    final transferMinutes = _transferMinutesByMode();
    for (var i = 0; i < daySpots.length; i++) {
      if (cursorMinutes >= 12 * 60 && cursorMinutes < 13 * 60) {
        cursorMinutes = 13 * 60;
      }
      final spot = daySpots[i];
      final stayMinutes = _stayMinutesForSpot(spot);
      final start = _formatClock(cursorMinutes);
      final end = _formatClock(cursorMinutes + stayMinutes);
      final period = _periodLabel(cursorMinutes);
      final transfer = i < daySpots.length - 1
          ? 'Travel to next: ${transferMinutes} min'
          : null;
      schedules.add(
        _SpotSchedule(
          periodLabel: period,
          startMinutes: cursorMinutes,
          startLabel: start,
          endLabel: end,
          durationLabel: '${(stayMinutes / 60).toStringAsFixed(1)}h stay',
          transferLabel: transfer,
        ),
      );
      cursorMinutes += stayMinutes + transferMinutes;
    }
    return schedules;
  }

  int _stayMinutesForSpot(TouristSpot spot) {
    if (spot.isHotel) return 180;
    if (spot.type == 'Nature' || spot.type == 'Adventure') return 150;
    return 120;
  }

  int _transferMinutesByMode() {
    switch (widget.transportMode) {
      case 'Public Transport':
        return 35;
      case 'Motorcycle':
        return 20;
      case 'Car':
      default:
        return 25;
    }
  }

  String _formatClock(int totalMinutes) {
    final normalized = ((totalMinutes % (24 * 60)) + (24 * 60)) % (24 * 60);
    final hour24 = normalized ~/ 60;
    final minute = normalized % 60;
    final suffix = hour24 >= 12 ? 'PM' : 'AM';
    final hour12 = hour24 % 12 == 0 ? 12 : hour24 % 12;
    final mm = minute.toString().padLeft(2, '0');
    return '$hour12:$mm $suffix';
  }

  String _periodLabel(int minutesOfDay) {
    final normalized = ((minutesOfDay % (24 * 60)) + (24 * 60)) % (24 * 60);
    final hour = normalized ~/ 60;
    if (hour < 12) return 'Morning';
    if (hour < 18) return 'Afternoon';
    return 'Evening';
  }

  void _startRatingWatcher() {
    _ratingTimer?.cancel();
    _checkDueSpotRatings();
    _ratingTimer = Timer.periodic(
      const Duration(seconds: 30),
      (_) => _checkDueSpotRatings(),
    );
  }

  Future<void> _checkDueSpotRatings() async {
    if (!mounted || _ratingPromptOpen) return;
    final now = DateTime.now();
    final schedules = _runtimeSchedules();
    schedules.sort((a, b) => a.triggerAt.compareTo(b.triggerAt));
    for (final entry in schedules) {
      if (now.isBefore(entry.triggerAt)) continue;
      if (_promptedSpotKeys.contains(entry.key)) continue;
      final snoozeUntil = _snoozedUntil[entry.key];
      if (snoozeUntil != null && now.isBefore(snoozeUntil)) continue;
      final submitted = await _showSpotRatingPrompt(entry.spot);
      if (submitted) {
        _promptedSpotKeys.add(entry.key);
        _snoozedUntil.remove(entry.key);
      } else {
        _snoozedUntil[entry.key] = now.add(const Duration(minutes: 15));
      }
      break;
    }
  }

  List<_RuntimeSpotSchedule> _runtimeSchedules() {
    final all = <_RuntimeSpotSchedule>[];
    for (var dayIndex = 0; dayIndex < _days; dayIndex++) {
      final daySpots = _spotsForDay(dayIndex);
      final schedules = _buildSchedulesForDay(daySpots);
      final dayDate = DateTime(
        widget.dateRange.start.year,
        widget.dateRange.start.month,
        widget.dateRange.start.day,
      ).add(Duration(days: dayIndex));
      for (var i = 0; i < daySpots.length && i < schedules.length; i++) {
        final startAt = dayDate.add(
          Duration(minutes: schedules[i].startMinutes),
        );
        final triggerAt = startAt.add(const Duration(hours: 2));
        all.add(
          _RuntimeSpotSchedule(
            key: 'd${dayIndex}_s${i}_${daySpots[i].name}',
            spot: daySpots[i],
            triggerAt: triggerAt,
          ),
        );
      }
    }
    return all;
  }

  Future<bool> _showSpotRatingPrompt(TouristSpot spot) async {
    if (!mounted) return false;
    _ratingPromptOpen = true;
    double selectedRating = 5.0;
    final descriptionController = TextEditingController();
    bool submitted = false;
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setDialogState) {
            return AlertDialog(
              title: const Text('Rate this spot'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      spot.name,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 6),
                    const Text(
                      '2 hours reached. Please rate your visit.',
                      style: TextStyle(fontSize: 13, color: AppColors.textGrey),
                    ),
                    const SizedBox(height: 16),
                    Center(
                      child: InteractiveRatingBadge(
                        rating: selectedRating,
                        onChanged: (v) =>
                            setDialogState(() => selectedRating = v),
                      ),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: descriptionController,
                      maxLines: 3,
                      minLines: 2,
                      textCapitalization: TextCapitalization.sentences,
                      decoration: InputDecoration(
                        labelText: 'Description (optional)',
                        hintText: 'Share anything about your visit...',
                        alignLabelWithHint: true,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: const BorderSide(
                            color: AppColors.primary,
                            width: 1.5,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('Later'),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                  ),
                  onPressed: () async {
                    final reviewer = SpotRatingsStore.currentReviewer();
                    await SpotRatingsStore.instance.add(
                      SpotRating(
                        userName: reviewer.name,
                        spotName: spot.name,
                        rating: selectedRating,
                        description: descriptionController.text.trim(),
                        userId: reviewer.userId,
                        profilePhotoPath: reviewer.photo,
                      ),
                    );
                    await TripPreferencesStore.instance.recordSpotRating(
                      spot.type,
                      selectedRating,
                    );
                    submitted = true;
                    if (ctx.mounted) Navigator.pop(ctx);
                  },
                  child: const Text('Submit'),
                ),
              ],
            );
          },
        );
      },
    );
    descriptionController.dispose();
    _ratingPromptOpen = false;
    return submitted;
  }
}

class _SpotRow extends StatelessWidget {
  final TouristSpot spot;
  final bool exactBudgetMatch;
  final String periodLabel;
  final String timeRangeLabel;
  final String durationLabel;
  final String? transferLabel;
  final VoidCallback? onRemove;

  const _SpotRow({
    required this.spot,
    required this.exactBudgetMatch,
    required this.periodLabel,
    required this.timeRangeLabel,
    required this.durationLabel,
    this.transferLabel,
    this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: TourismPlanUi.insetRowDecoration(),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: SizedBox(
              width: 76,
              height: 76,
              child: buildTouristSpotProfileImage(
                spot,
                fallback: _placeholder(),
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  spot.name,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textDark,
                    height: 1.2,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                if (spot.location.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    spot.location,
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppColors.textGrey,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
                const SizedBox(height: 6),
                Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    _periodChip(periodLabel),
                    Icon(
                      Icons.access_time_rounded,
                      size: 14,
                      color: Colors.amber.shade700,
                    ),
                    Text(
                      timeRangeLabel,
                      style: const TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textDark,
                      ),
                    ),
                    Text(
                      durationLabel,
                      style: TextStyle(
                        fontSize: 11,
                        color: AppColors.textGrey.withValues(alpha: 0.9),
                      ),
                    ),
                  ],
                ),
                if (spot.description.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text(
                    spot.description,
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppColors.textGrey,
                      height: 1.35,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    _spotTag(
                      spot.isHotel ? 'Stay' : 'Visit',
                      const Color(0xFFE8EEF5),
                      AppColors.textDark,
                    ),
                    _spotTag(
                      exactBudgetMatch ? 'Budget match' : 'Within budget',
                      exactBudgetMatch
                          ? const Color(0xFFE6F4EA)
                          : const Color(0xFFFFF4E5),
                      exactBudgetMatch
                          ? const Color(0xFF1E8E3E)
                          : const Color(0xFFE37400),
                    ),
                    Icon(Icons.star, size: 14, color: Colors.amber.shade700),
                    Text(
                      spot.rating.toStringAsFixed(1),
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textDark,
                      ),
                    ),
                  ],
                ),
                if (transferLabel != null) ...[
                  const SizedBox(height: 6),
                  Text(
                    transferLabel!,
                    style: const TextStyle(
                      fontSize: 11.5,
                      color: AppColors.textGrey,
                      fontStyle: FontStyle.italic,
                      height: 1.3,
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (onRemove != null)
            IconButton(
              onPressed: onRemove,
              icon: Icon(
                Icons.close_rounded,
                size: 20,
                color: AppColors.textGrey.withValues(alpha: 0.75),
              ),
              tooltip: 'Remove from plan',
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
            ),
        ],
      ),
    );
  }

  Widget _periodChip(String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: const Color(0xFF1976D2),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        label,
        style: const TextStyle(
          fontSize: 10.5,
          fontWeight: FontWeight.w700,
          color: Colors.white,
        ),
      ),
    );
  }

  Widget _spotTag(String text, Color bg, Color fg) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: fg,
        ),
      ),
    );
  }

  Widget _placeholder() {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            AppColors.primary.withValues(alpha: 0.12),
            AppColors.primaryLight.withValues(alpha: 0.08),
          ],
        ),
      ),
      child: const Center(
        child: Icon(Icons.landscape_rounded, color: AppColors.primary, size: 28),
      ),
    );
  }
}

class _ItinerarySpotPickerSheet extends StatefulWidget {
  final int dayNumber;
  final List<TouristSpot> spots;
  final double budget;
  final Set<String> exactBudgetSpotNames;
  final ValueChanged<TouristSpot> onPick;

  const _ItinerarySpotPickerSheet({
    required this.dayNumber,
    required this.spots,
    required this.budget,
    required this.exactBudgetSpotNames,
    required this.onPick,
  });

  @override
  State<_ItinerarySpotPickerSheet> createState() =>
      _ItinerarySpotPickerSheetState();
}

class _ItinerarySpotPickerSheetState extends State<_ItinerarySpotPickerSheet> {
  String _query = '';

  List<TouristSpot> get _filtered {
    final q = _query.trim().toLowerCase();
    if (q.isEmpty) return widget.spots;
    return widget.spots
        .where(
          (s) =>
              s.name.toLowerCase().contains(q) ||
              s.location.toLowerCase().contains(q) ||
              s.type.toLowerCase().contains(q),
        )
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.paddingOf(context).bottom;
    final filtered = _filtered;

    return DraggableScrollableSheet(
      initialChildSize: 0.72,
      minChildSize: 0.45,
      maxChildSize: 0.92,
      builder: (context, scrollController) {
        return Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: Column(
            children: [
              const SizedBox(height: 10),
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 14, 12, 8),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Add spot — Day ${widget.dayNumber}',
                        style: const TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textDark,
                        ),
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: TextField(
                  decoration: InputDecoration(
                    hintText: 'Search spots along your route…',
                    prefixIcon: const Icon(Icons.search, size: 22),
                    filled: true,
                    fillColor: const Color(0xFFF4F5F7),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                    contentPadding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                  onChanged: (v) => setState(() => _query = v),
                ),
              ),
              const SizedBox(height: 8),
              Expanded(
                child: filtered.isEmpty
                    ? Center(
                        child: Text(
                          _query.isEmpty
                              ? 'No spots available'
                              : 'No matches for "$_query"',
                          style: const TextStyle(color: AppColors.textGrey),
                        ),
                      )
                    : ListView.separated(
                        controller: scrollController,
                        padding: EdgeInsets.fromLTRB(16, 8, 16, bottom + 16),
                        itemCount: filtered.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 8),
                        itemBuilder: (context, index) {
                          final spot = filtered[index];
                          final exact = widget.exactBudgetSpotNames
                                  .contains(spot.name) ||
                              evaluateBudgetFit(spot, widget.budget)
                                  .exactBudgetMatch;
                          return Material(
                            color: const Color(0xFFFAFBFC),
                            borderRadius: BorderRadius.circular(12),
                            child: InkWell(
                              borderRadius: BorderRadius.circular(12),
                              onTap: () => widget.onPick(spot),
                              child: Padding(
                                padding: const EdgeInsets.all(10),
                                child: Row(
                                  children: [
                                    ClipRRect(
                                      borderRadius: BorderRadius.circular(8),
                                      child: SizedBox(
                                        width: 56,
                                        height: 56,
                                        child: buildTouristSpotProfileImage(
                                          spot,
                                          fallback: Container(
                                            color: AppColors.primary
                                                .withValues(alpha: 0.08),
                                            child: const Icon(
                                              Icons.landscape,
                                              color: AppColors.primary,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            spot.name,
                                            style: const TextStyle(
                                              fontSize: 14,
                                              fontWeight: FontWeight.w700,
                                              color: AppColors.textDark,
                                            ),
                                            maxLines: 2,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                          if (spot.location.isNotEmpty)
                                            Text(
                                              spot.location,
                                              style: const TextStyle(
                                                fontSize: 12,
                                                color: AppColors.textGrey,
                                              ),
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          const SizedBox(height: 4),
                                          Row(
                                            children: [
                                              Icon(
                                                Icons.star,
                                                size: 14,
                                                color: Colors.amber.shade700,
                                              ),
                                              const SizedBox(width: 3),
                                              Text(
                                                spot.rating.toStringAsFixed(1),
                                                style: const TextStyle(
                                                  fontSize: 12,
                                                  fontWeight: FontWeight.w600,
                                                ),
                                              ),
                                              const SizedBox(width: 8),
                                              Text(
                                                spot.priceRange,
                                                style: const TextStyle(
                                                  fontSize: 11.5,
                                                  color: AppColors.textGrey,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ],
                                      ),
                                    ),
                                    Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.end,
                                      children: [
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 8,
                                            vertical: 3,
                                          ),
                                          decoration: BoxDecoration(
                                            color: exact
                                                ? const Color(0xFFE6F4EA)
                                                : const Color(0xFFFFF4E5),
                                            borderRadius:
                                                BorderRadius.circular(10),
                                          ),
                                          child: Text(
                                            exact
                                                ? 'Budget match'
                                                : 'Within budget',
                                            style: TextStyle(
                                              fontSize: 10,
                                              fontWeight: FontWeight.w600,
                                              color: exact
                                                  ? const Color(0xFF1E8E3E)
                                                  : const Color(0xFFE37400),
                                            ),
                                          ),
                                        ),
                                        const SizedBox(height: 8),
                                        Icon(
                                          Icons.add_circle_outline,
                                          color: AppColors.primary,
                                          size: 26,
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          );
                        },
                      ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _SpotSchedule {
  final String periodLabel;
  final int startMinutes;
  final String startLabel;
  final String endLabel;
  final String durationLabel;
  final String? transferLabel;

  const _SpotSchedule({
    required this.periodLabel,
    required this.startMinutes,
    required this.startLabel,
    required this.endLabel,
    required this.durationLabel,
    this.transferLabel,
  });
}

class _RuntimeSpotSchedule {
  final String key;
  final TouristSpot spot;
  final DateTime triggerAt;

  const _RuntimeSpotSchedule({
    required this.key,
    required this.spot,
    required this.triggerAt,
  });
}

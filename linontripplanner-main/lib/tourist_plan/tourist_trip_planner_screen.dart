import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../data.dart';
import '../municipal_road_distances.dart'
    show RoadRouteDirection, RoadRouteOption;
import '../services/bus_location_store.dart';
import '../services/saved_trip_store.dart';
import '../services/tourism_session.dart';
import '../services/trip_post_finish_rating.dart';
import '../trip_plan_route_map_page.dart';
import '../trip_route_fare_service.dart';
import '../widgets/municipality_image.dart';
import '../widgets/tourism_plan_ui.dart';
import 'tourist_travel_estimates.dart';
import 'trip_itinerary_step.dart';
import 'trip_wizard_controller.dart';

/// Guided "Plan my trip" wizard - itinerary only after the user finishes Review.
class TouristTripPlannerScreen extends StatefulWidget {
  static const routeName = '/trip-planner';

  const TouristTripPlannerScreen({super.key});

  @override
  State<TouristTripPlannerScreen> createState() =>
      _TouristTripPlannerScreenState();
}

class _TouristTripPlannerScreenState extends State<TouristTripPlannerScreen> {
  late final TripWizardController _w;
  static const _accent = Color(0xFFFF6B00);

  final _budgetCtrl = TextEditingController(text: '5000');
  final _travelersCtrl = TextEditingController(text: '1');

  @override
  void initState() {
    super.initState();
    _w = TripWizardController();
    final now = DateTime.now();
    _w.setArrival(now);
    _w.setDayCount(3);
    _w.addListener(_onChanged);
  }

  void _onChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _w.removeListener(_onChanged);
    _w.dispose();
    _budgetCtrl.dispose();
    _travelersCtrl.dispose();
    super.dispose();
  }

  void _snack(String msg, {bool error = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: error ? Colors.redAccent : _accent,
      ),
    );
  }

  Future<void> _next() async {
    try {
      switch (_w.step) {
        case TripWizardStep.tripInfo:
          _applyTripInfoFields();
          final err = _w.tripInfoValidationError();
          if (err != null) {
            _snack(err, error: true);
            return;
          }
          await _w.goToItinerary();
        case TripWizardStep.itinerary:
          if (_w.assignedSpotNames.isEmpty) {
            _snack('Add at least one spot to a day to continue.', error: true);
            return;
          }
          _w.goToReview();
        case TripWizardStep.review:
          if (_w.overBudget) {
            final proceed = await showDialog<bool>(
              context: context,
              builder: (ctx) => AlertDialog(
                title: const Text('Over budget'),
                content: Text(
                  'Estimated cost ${formatFarePhp(_w.estimatedTotalPhp)} '
                  'exceeds your budget ${formatFarePhp(_w.budgetPhp.round())}.\n\n'
                  'You can go back and adjust days, travelers, or budget - '
                  'or finish anyway.',
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(ctx, false),
                    child: const Text('Adjust trip'),
                  ),
                  FilledButton(
                    style: FilledButton.styleFrom(backgroundColor: _accent),
                    onPressed: () => Navigator.pop(ctx, true),
                    child: const Text('Finish anyway'),
                  ),
                ],
              ),
            );
            if (proceed != true) return;
          }
          await _saveAndOpenTrips();
      }
    } catch (e) {
      _snack(e.toString().replaceFirst('Bad state: ', ''), error: true);
    }
  }

  void _applyTripInfoFields() {
    final budget = double.tryParse(_budgetCtrl.text.replaceAll(',', ''));
    if (budget != null) _w.setBudget(budget);
    if (_w.arrivalDate != null && _w.departureDate != null) {
      _w.syncDayCountFromDates();
    }
    final travelers = int.tryParse(_travelersCtrl.text.trim());
    if (travelers != null) _w.setTravelers(travelers);
  }

  Future<void> _saveAndOpenTrips() async {
    final days = _w.spotsByDay;
    final dayNames = [
      for (final day in days) [for (final s in day) s.name],
    ];
    final trip = SavedTripPlan(
      id: 'trip_${DateTime.now().millisecondsSinceEpoch}',
      createdAt: DateTime.now(),
      startName: _w.start?.name ?? '',
      endName: _w.end?.name ?? '',
      arrivalDate: _w.arrivalDate,
      departureDate: _w.departureDate,
      tripDays: _w.tripDays,
      travelers: _w.travelers,
      transportMode: _w.transportMode,
      budgetPhp: _w.budgetPhp,
      estimatedTotalPhp: _w.estimatedTotalPhp,
      daySpotNames: dayNames,
      routeType: _w.routeDirection?.name ?? '',
    );
    await SavedTripStore.instance.save(trip);
    TripPostFinishRatingScheduler.instance.scheduleFirstSpotRating(
      _w.daySpotAssignments,
    );
    if (!mounted) return;
    tourismShellTabRequest.value = 2;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Trip saved.')),
    );
    Navigator.of(context).maybePop();
  }

  String get _title {
    switch (_w.step) {
      case TripWizardStep.tripInfo:
        return 'Trip details';
      case TripWizardStep.itinerary:
        return 'Assign days';
      case TripWizardStep.review:
        return 'Review trip';
    }
  }

  int get _stepIndex {
    switch (_w.step) {
      case TripWizardStep.tripInfo:
        return 0;
      case TripWizardStep.itinerary:
        return 1;
      case TripWizardStep.review:
        return 2;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.planPageBg,
      appBar: AppBar(
        backgroundColor: _accent,
        foregroundColor: Colors.white,
        automaticallyImplyLeading: false,
        title: Text(_title),
      ),
      body: Column(
        children: [
          _StepHeader(current: _stepIndex, accent: _accent),
          Expanded(
            child: switch (_w.step) {
              TripWizardStep.tripInfo => _TripInfoStep(
                  wizard: _w,
                  accent: _accent,
                  budgetCtrl: _budgetCtrl,
                  travelersCtrl: _travelersCtrl,
                ),
              TripWizardStep.itinerary => _w.loadingRoute
                  ? const Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          CircularProgressIndicator(color: Color(0xFFFF6B00)),
                          SizedBox(height: 12),
                          Text('Finding spots along your route...'),
                        ],
                      ),
                    )
                  : TripItineraryStep(
                      wizard: _w,
                      accent: _accent,
                    ),
              TripWizardStep.review => _ReviewStep(
                  wizard: _w,
                  accent: _accent,
                ),
            },
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
              child: Row(
                children: [
                  OutlinedButton(
                    onPressed: (_w.loadingRoute || _w.loadingDayPlan)
                        ? null
                        : () {
                            if (_w.step == TripWizardStep.tripInfo) {
                              Navigator.of(context).maybePop();
                            } else {
                              _w.goBack();
                            }
                          },
                    style: OutlinedButton.styleFrom(
                      foregroundColor: _accent,
                      side: const BorderSide(color: _accent),
                      minimumSize: const Size(96, 48),
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                    ),
                    child: const Text(
                      'Back',
                      style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: SizedBox(
                      height: 48,
                      child: FilledButton(
                        style: FilledButton.styleFrom(backgroundColor: _accent),
                        onPressed: (_w.loadingRoute || _w.loadingDayPlan)
                            ? null
                            : _next,
                        child: Text(
                          switch (_w.step) {
                            TripWizardStep.tripInfo => 'Assign spots by day',
                            TripWizardStep.itinerary => 'Review my trip',
                            TripWizardStep.review => 'Finish',
                          },
                          style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 15,
                          ),
                        ),
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

class _StepHeader extends StatelessWidget {
  final int current;
  final Color accent;

  const _StepHeader({required this.current, required this.accent});

  static const _labels = ['Details', 'Days', 'Review'];

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      elevation: 1,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
        child: Row(
          children: [
            for (var i = 0; i < _labels.length; i++) ...[
              if (i > 0)
                Expanded(
                  child: Container(
                    height: 2,
                    color: i <= current
                        ? accent
                        : Colors.grey.shade300,
                  ),
                ),
              Column(
                children: [
                  CircleAvatar(
                    radius: 12,
                    backgroundColor:
                        i <= current ? accent : Colors.grey.shade300,
                    child: Text(
                      '${i + 1}',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        color: i <= current ? Colors.white : Colors.black54,
                      ),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _labels[i],
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight:
                          i == current ? FontWeight.w700 : FontWeight.w500,
                      color: i == current ? accent : Colors.black54,
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ---

class _RouteChoiceSection extends StatefulWidget {
  final List<RoadRouteOption> options;
  final RoadRouteDirection? selected;
  final Color accent;
  final ValueChanged<RoadRouteDirection> onSelect;

  const _RouteChoiceSection({
    super.key,
    required this.options,
    required this.selected,
    required this.accent,
    required this.onSelect,
  });

  @override
  State<_RouteChoiceSection> createState() => _RouteChoiceSectionState();
}

class _RouteChoiceSectionState extends State<_RouteChoiceSection> {
  bool _expanded = false;

  void _tap(RoadRouteDirection direction) {
    if (widget.selected == direction) {
      setState(() => _expanded = !_expanded);
      return;
    }
    widget.onSelect(direction);
    setState(() => _expanded = true);
  }

  @override
  Widget build(BuildContext context) {
    final coastal = widget.options
        .where((o) => o.direction == RoadRouteDirection.coastal)
        .firstOrNull;
    final highland = widget.options
        .where((o) => o.direction == RoadRouteDirection.highland)
        .firstOrNull;
    final selectedOption = widget.options
        .where((o) => o.direction == widget.selected)
        .firstOrNull;
    final showTimeline = _expanded && selectedOption != null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (coastal != null)
              Expanded(
                child: _RouteChoiceChip(
                  label: 'Coastal Route',
                  option: coastal,
                  selected: widget.selected == RoadRouteDirection.coastal,
                  accent: widget.accent,
                  onTap: () => _tap(RoadRouteDirection.coastal),
                ),
              ),
            if (coastal != null && highland != null) const SizedBox(width: 8),
            if (highland != null)
              Expanded(
                child: _RouteChoiceChip(
                  label: 'Highland Route',
                  option: highland,
                  selected: widget.selected == RoadRouteDirection.highland,
                  accent: widget.accent,
                  onTap: () => _tap(RoadRouteDirection.highland),
                ),
              ),
          ],
        ),
        ClipRect(
          child: AnimatedSize(
            duration: const Duration(milliseconds: 280),
            curve: Curves.easeInOut,
            alignment: Alignment.topCenter,
            child: showTimeline
                ? Padding(
                    padding: const EdgeInsets.only(top: 10),
                    child: _RouteTimeline(
                      option: selectedOption,
                      accent: widget.accent,
                    ),
                  )
                : const SizedBox(width: double.infinity),
          ),
        ),
      ],
    );
  }
}

class _RouteChoiceChip extends StatelessWidget {
  final String label;
  final RoadRouteOption option;
  final bool selected;
  final Color accent;
  final VoidCallback onTap;

  const _RouteChoiceChip({
    required this.label,
    required this.option,
    required this.selected,
    required this.accent,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? accent.withValues(alpha: 0.08) : Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: selected ? accent : Colors.grey.shade300,
          width: selected ? 2 : 1,
        ),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
          child: Row(
            children: [
              Icon(
                selected ? Icons.radio_button_checked : Icons.radio_button_off,
                color: selected ? accent : Colors.grey,
                size: 20,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 13.5,
                        color: selected ? accent : AppColors.textDark,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${option.distanceKm.toStringAsFixed(1)} km · '
                      '~${formatHoursMinutes(option.drivingMinutes)}',
                      style: TextStyle(
                        fontSize: 11.5,
                        height: 1.25,
                        color: selected ? accent : AppColors.textGrey,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RouteTimeline extends StatelessWidget {
  final RoadRouteOption option;
  final Color accent;

  const _RouteTimeline({required this.option, required this.accent});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<int>(
      valueListenable: BusLocationStore.instance.revision,
      builder: (context, _, __) {
        final stops = BusLocationStore.instance.alongMunicipalities(
          option.municipalities.map((m) => m.name),
          option.direction,
        );
        if (stops.isEmpty) {
          return const Padding(
            padding: EdgeInsets.only(top: 8),
            child: Text(
              'No bus stops are saved for this route.',
              style: TextStyle(fontSize: 13, height: 1.35),
            ),
          );
        }
        return _timeline(stops);
      },
    );
  }

  Widget _timeline(List<BusLocation> stops) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: accent.withValues(alpha: 0.35)),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
        child: Column(
          children: [
            for (var i = 0; i < stops.length; i++) ...[
              Row(
                children: [
                  SizedBox(
                    width: 22,
                    child: Center(
                      child: Container(
                        width: 12,
                        height: 12,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: accent,
                        ),
                      ),
                    ),
                  ),
                  Icon(Icons.arrow_forward, size: 16, color: accent),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          stops[i].name,
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            height: 1.2,
                          ),
                        ),
                        Text(
                          stops[i].municipality,
                          style: const TextStyle(fontSize: 12, height: 1.2),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              if (i < stops.length - 1)
                Align(
                  alignment: Alignment.centerLeft,
                  child: SizedBox(
                    width: 22,
                    child: Column(
                      children: [
                        Container(
                          width: 2,
                          height: 8,
                          color: accent.withValues(alpha: 0.45),
                        ),
                        Icon(
                          Icons.arrow_downward,
                          size: 14,
                          color: accent,
                        ),
                        Container(
                          width: 2,
                          height: 8,
                          color: accent.withValues(alpha: 0.45),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }
}

class _TripInfoStep extends StatelessWidget {
  final TripWizardController wizard;
  final Color accent;
  final TextEditingController budgetCtrl;
  final TextEditingController travelersCtrl;

  const _TripInfoStep({
    required this.wizard,
    required this.accent,
    required this.budgetCtrl,
    required this.travelersCtrl,
  });

  @override
  Widget build(BuildContext context) {
    final names = sortedMunicipalities;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      children: [
        Text(
          'Tell us about your trip first. Next you will assign spots to Day 1, '
          'Day 2, and so on along your route.',
          style: TextStyle(
            fontSize: 13.5,
            height: 1.4,
            color: AppColors.textGrey.withValues(alpha: 0.95),
          ),
        ),
        const SizedBox(height: 14),
        _infoCard(
          icon: Icons.route_rounded,
          title: 'Where are you going?',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _sectionLabel('Starting point'),
              _muniDropdown(
                value: wizard.start,
                names: names,
                hint: 'Where do you start?',
                onChanged: wizard.setStart,
              ),
              const SizedBox(height: 12),
              _sectionLabel('Endpoint / final destination'),
              _muniDropdown(
                value: wizard.end,
                names: names,
                hint: 'Where do you finish?',
                onChanged: wizard.setEnd,
              ),
              if (wizard.routeOptions.isNotEmpty) ...[
                const SizedBox(height: 12),
                _sectionLabel('Select Your Route'),
                _RouteChoiceSection(
                  key: ValueKey('${wizard.start?.name}|${wizard.end?.name}'),
                  options: wizard.routeOptions,
                  selected: wizard.routeDirection,
                  accent: accent,
                  onSelect: wizard.setRouteDirection,
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 12),
        _infoCard(
          icon: Icons.event_rounded,
          title: 'When and how you travel',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _sectionLabel('Travel dates'),
              Material(
                color: AppColors.insetSurface,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                  side: BorderSide(color: Colors.black.withValues(alpha: 0.08)),
                ),
                child: ListTile(
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  leading: Icon(Icons.date_range, color: accent),
                  title: Text(
                    wizard.arrivalDate == null || wizard.departureDate == null
                        ? 'Select start - end dates'
                        : '${_fmtDate(wizard.arrivalDate!)} – ${_fmtDate(wizard.departureDate!)}',
                    style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
                  ),
                  subtitle: wizard.arrivalDate != null && wizard.departureDate != null
                      ? Text(
                          '${wizard.tripDays} day${wizard.tripDays == 1 ? '' : 's'} to explore '
                          '(inclusive)',
                        )
                      : const Text('Both start and end dates count as trip days'),
                  onTap: () async {
                    final now = DateTime.now();
                    final initialStart = wizard.arrivalDate ?? now;
                    final initialEnd = wizard.departureDate ??
                        initialStart.add(const Duration(days: 3));
                    final range = await showDateRangePicker(
                      context: context,
                      firstDate: now,
                      lastDate: DateTime(now.year + 2),
                      initialDateRange: DateTimeRange(
                        start: initialStart.isBefore(now) ? now : initialStart,
                        end: initialEnd.isBefore(initialStart)
                            ? initialStart.add(const Duration(days: 3))
                            : initialEnd,
                      ),
                      helpText: 'Trip dates (inclusive)',
                      saveText: 'Save',
                    );
                    if (range != null) {
                      wizard.setDateRange(range.start, range.end);
                    }
                  },
                ),
              ),
              const SizedBox(height: 14),
              _sectionLabel('Transportation'),
              DropdownButtonFormField<String>(
                value: kTransportModes.contains(wizard.transportMode)
                    ? wizard.transportMode
                    : kTransportModes.first,
                decoration: _fieldDeco(),
                items: kTransportModes
                    .map(
                      (m) => DropdownMenuItem(
                        value: m,
                        child: Text(transportModeLabel(m)),
                      ),
                    )
                    .toList(),
                onChanged: (v) {
                  if (v != null) wizard.setTransport(v);
                },
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        _infoCard(
          icon: Icons.payments_rounded,
          title: 'Budget and travelers',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _sectionLabel('Total budget (PHP)'),
              TextField(
                controller: budgetCtrl,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: _fieldDeco(label: 'Total trip budget'),
                onChanged: (v) {
                  final n = double.tryParse(v);
                  if (n != null) wizard.setBudget(n);
                },
              ),
              const SizedBox(height: 12),
              _sectionLabel('Number of travelers'),
              TextField(
                controller: travelersCtrl,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: _fieldDeco(label: 'Travelers'),
                onChanged: (v) {
                  final n = int.tryParse(v);
                  if (n != null) wizard.setTravelers(n);
                },
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        _infoCard(
          icon: Icons.interests_rounded,
          title: 'Interests',
          child: ValueListenableBuilder<int>(
            valueListenable: tourismCatalogRevision,
            builder: (context, _, __) {
              final categories = catalogSpotCategories();
              if (categories.isEmpty) {
                return Text(
                  'Spot categories will appear when tourist spots finish loading.',
                  style: TextStyle(
                    fontSize: 13,
                    height: 1.35,
                    color: AppColors.textGrey.withValues(alpha: 0.95),
                  ),
                );
              }
              return Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final interest in categories)
                    FilterChip(
                      label: Text(interest),
                      selected: wizard.interests.contains(interest),
                      onSelected: (_) => wizard.toggleInterest(interest),
                      selectedColor: accent.withValues(alpha: 0.22),
                      checkmarkColor: accent,
                      backgroundColor: AppColors.insetSurface,
                      side: BorderSide(
                        color: wizard.interests.contains(interest)
                            ? accent
                            : Colors.black.withValues(alpha: 0.08),
                      ),
                    ),
                ],
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _infoCard({
    required IconData icon,
    required String title,
    required Widget child,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 16),
      decoration: TourismPlanUi.planCardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TourismPlanUi.sectionHeader(icon: icon, title: title),
          const SizedBox(height: 14),
          child,
        ],
      ),
    );
  }

  Widget _muniDropdown({
    required Municipality? value,
    required List<Municipality> names,
    required String hint,
    required ValueChanged<Municipality?> onChanged,
  }) {
    // The catalog reloads with new Municipality objects, so match by name.
    final seen = <String>{};
    final items = [
      for (final m in names)
        if (seen.add(m.name)) m,
    ];
    final selected = value == null
        ? null
        : items.where((m) => m.name == value.name).firstOrNull;
    return DropdownButtonFormField<Municipality>(
      value: selected,
      isExpanded: true,
      decoration: _fieldDeco(label: hint),
      items: items
          .map(
            (m) => DropdownMenuItem(
              value: m,
              child: Text(m.shortName, overflow: TextOverflow.ellipsis),
            ),
          )
          .toList(),
      onChanged: onChanged,
    );
  }

  Widget _sectionLabel(String t) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Text(
          t,
          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
        ),
      );

  InputDecoration _fieldDeco({String? label}) => InputDecoration(
        labelText: label,
        filled: true,
        fillColor: AppColors.insetSurface,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.black.withValues(alpha: 0.08)),
        ),
        isDense: true,
      );
}

String _fmtDate(DateTime d) {
  const m = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];
  return '${m[d.month - 1]} ${d.day}, ${d.year}';
}

class _ReviewStep extends StatelessWidget {
  final TripWizardController wizard;
  final Color accent;

  const _ReviewStep({required this.wizard, required this.accent});

  @override
  Widget build(BuildContext context) {
    final over = wizard.overBudget;
    final arrival = wizard.arrivalDate;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      children: [
        Container(
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
              if (arrival != null) ...[
                const SizedBox(height: 4),
                Text(
                  '${_fmtDate(arrival)}'
                  '${wizard.departureDate != null ? ' – ${_fmtDate(wizard.departureDate!)}' : ''}',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textGrey.withValues(alpha: 0.95),
                  ),
                ),
              ],
              const SizedBox(height: 14),
              _reviewEndpoint(
                Icons.trip_origin,
                const Color(0xFF1565C0),
                'Start',
                wizard.start?.name ?? '',
              ),
              Padding(
                padding: const EdgeInsets.only(left: 15),
                child: Container(
                  width: 2,
                  height: 14,
                  color: accent.withValues(alpha: 0.35),
                ),
              ),
              _reviewEndpoint(
                Icons.place,
                const Color(0xFFE53935),
                'End',
                wizard.end?.name ?? '',
              ),
              const SizedBox(height: 14),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _reviewChip('${wizard.tripDays} day${wizard.tripDays == 1 ? '' : 's'}'),
                  _reviewChip('${wizard.nights} night${wizard.nights == 1 ? '' : 's'}'),
                  _reviewChip(
                    '${wizard.travelers} traveler${wizard.travelers == 1 ? '' : 's'}',
                  ),
                  _reviewChip(transportModeLabel(wizard.transportMode)),
                  _reviewChip(formatFarePhp(wizard.budgetPhp.round())),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        _viewRouteOnMapButton(context),
        const SizedBox(height: 18),
        TourismPlanUi.sectionHeader(
          icon: Icons.calendar_month_rounded,
          title: 'Day plan',
          badge: '${wizard.spotsByDay.length} day${wizard.spotsByDay.length == 1 ? '' : 's'}',
        ),
        const SizedBox(height: 10),
        for (var d = 0; d < wizard.spotsByDay.length; d++)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
              decoration: TourismPlanUi.planCardDecoration(),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                          color: accent.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          'Day ${d + 1}',
                          style: TextStyle(
                            fontWeight: FontWeight.w900,
                            color: accent,
                            fontSize: 13,
                          ),
                        ),
                      ),
                      if (arrival != null) ...[
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            _fmtDate(arrival.add(Duration(days: d))),
                            style: const TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 14,
                              color: AppColors.textDark,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 10),
                  if (wizard.spotsByDay[d].isEmpty)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Text(
                        'No spots on this day.',
                        style: TextStyle(
                          fontSize: 13,
                          color: AppColors.textGrey.withValues(alpha: 0.95),
                        ),
                      ),
                    )
                  else
                    for (var i = 0; i < wizard.spotsByDay[d].length; i++)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _SpotThumb(
                              spot: wizard.spotsByDay[d][i],
                              size: 64,
                              badge: '${i + 1}',
                              accent: accent,
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    wizard.spotsByDay[d][i].name,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w800,
                                      fontSize: 14.5,
                                      color: AppColors.textDark,
                                    ),
                                  ),
                                  Text(
                                    wizard.spotsByDay[d][i].location,
                                    style: TextStyle(
                                      fontSize: 12.5,
                                      color: AppColors.textGrey.withValues(alpha: 0.95),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                ],
              ),
            ),
          ),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
          decoration: TourismPlanUi.planCardDecoration(),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TourismPlanUi.sectionHeader(
                icon: Icons.receipt_long_rounded,
                title: 'Estimated costs',
              ),
              const SizedBox(height: 12),
              _costLine('Transportation', wizard.transportTotalPhp),
              _costLine('Entrance fees', wizard.entranceFeesTotal),
              _costLine('Food (estimate)', wizard.foodEstimatePhp),
              _costLine('Activities / souvenirs', wizard.activityEstimatePhp),
              if (wizard.needsAccommodation)
                _costLine('Accommodation (estimate)', wizard.accommodationEstimatePhp),
              const Divider(height: 22),
              _costLine('Estimated total', wizard.estimatedTotalPhp, bold: true),
              _costLine('Your budget', wizard.budgetPhp.round(), bold: true),
              const SizedBox(height: 8),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: over ? const Color(0xFFFFEBEE) : const Color(0xFFE8F5E9),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  over
                      ? 'Over budget by ${formatFarePhp(wizard.estimatedTotalPhp - wizard.budgetPhp.round())}. '
                          'Remove stops, shorten the trip, or raise your budget before finishing.'
                      : 'Within budget. Your day plan is ready to finish.',
                  style: TextStyle(
                    fontSize: 13,
                    height: 1.35,
                    fontWeight: FontWeight.w700,
                    color: over ? Colors.red.shade800 : Colors.green.shade900,
                  ),
                ),
              ),
              if (over) ...[
                const SizedBox(height: 8),
                Text(
                  'Ideas to reduce cost: fewer stops, Public Transport, '
                  'fewer travelers for private vehicle, or a shorter stay.',
                  style: TextStyle(
                    fontSize: 12.5,
                    height: 1.35,
                    color: AppColors.textGrey.withValues(alpha: 0.95),
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _reviewEndpoint(IconData icon, Color color, String label, String name) {
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

  Widget _reviewChip(String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.listTilePeach,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: accent.withValues(alpha: 0.16)),
      ),
      child: Text(
        label,
        style: const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          color: AppColors.textDark,
        ),
      ),
    );
  }

  Widget _viewRouteOnMapButton(BuildContext context) {
    return TourismGradientButton(
      label: 'View route on map',
      icon: Icons.map_rounded,
      onPressed: () {
          final s = wizard.start;
          final e = wizard.end;
          if (s == null || e == null) return;
          final spots = <TouristSpot>[
            for (final day in wizard.spotsByDay) ...day,
          ];
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => TripPlanRouteMapPage(
                start: s,
                end: e,
                spots: spots.isNotEmpty ? spots : wizard.selectedSpots,
                spotDays: wizard.spotsByDay,
                lockedDayIndexes: wizard.orderLockedDays,
                lockedEndSpotNames: wizard.lockedEndSpotNames,
                onOrderSaved: wizard.applyRoadVisitOrder,
                transportMode: wizard.transportMode,
                direction: wizard.selectedRouteDirection,
              ),
            ),
          );
        },
    );
  }

  Widget _costLine(String label, int amount, {bool bold = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                fontWeight: bold ? FontWeight.w800 : FontWeight.w500,
              ),
            ),
          ),
          Text(
            formatFarePhp(amount),
            style: TextStyle(
              fontWeight: bold ? FontWeight.w800 : FontWeight.w600,
              color: bold ? accent : null,
            ),
          ),
        ],
      ),
    );
  }
}

/// Compact spot photo used on the Review list.
class _SpotThumb extends StatelessWidget {
  final TouristSpot spot;
  final double size;
  final String? badge;
  final Color accent;

  const _SpotThumb({
    required this.spot,
    required this.size,
    required this.accent,
    this.badge,
  });

  @override
  Widget build(BuildContext context) {
    final cache = (size * 2).round().clamp(96, 320);
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: SizedBox(
              width: size,
              height: size,
              child: buildTouristSpotProfileImage(
                spot,
                memCacheWidth: cache,
                memCacheHeight: cache,
                fallback: Container(
                  color: Colors.grey.shade200,
                  alignment: Alignment.center,
                  child: Icon(
                    Icons.image_outlined,
                    color: Colors.grey.shade500,
                    size: size * 0.35,
                  ),
                ),
              ),
            ),
          ),
          if (badge != null)
            Positioned(
              left: -4,
              top: -4,
              child: CircleAvatar(
                radius: 11,
                backgroundColor: accent,
                child: Text(
                  badge!,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}


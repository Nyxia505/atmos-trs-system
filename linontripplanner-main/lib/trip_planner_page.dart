import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import 'data.dart';
import 'directions_service.dart';
import 'firestore_loader.dart';
import 'municipal_road_distances.dart';
import 'municipality_coordinates.dart' show getMunicipalityCoordinates;
import 'trip_plan_result_page.dart';
import 'trip_planner_utils.dart';
import 'trip_preferences_store.dart';
import 'trip_recommendation_engine.dart';
import 'itinerary_transport_service.dart';
import 'trip_route_fare_service.dart';
import 'widgets/responsive_layout.dart';

class TripPlannerPage extends StatefulWidget {
  static const routeName = '/trip-planner';

  const TripPlannerPage({super.key});

  @override
  State<TripPlannerPage> createState() => _TripPlannerPageState();
}

class _TripPlannerPageState extends State<TripPlannerPage> {
  DateTimeRange? _dateRange;
  Municipality? _startMunicipality;
  Municipality? _endMunicipality;
  bool _useCurrentLocation = false;
  bool _resolvingCurrentLocation = false;
  String? _currentLocationLabel;
  String _transportMode = kTransportModes.first;
  final Set<String> _selectedInterests = {'Nature'};
  TripBudgetTier _budgetTier = TripBudgetTier.moderate;
  final TextEditingController _budgetController = TextEditingController();
  final TextEditingController _timeConstraintController =
      TextEditingController();
  final TextEditingController _dateRangeDisplayController =
      TextEditingController(text: 'Select dates');
  final TextEditingController _touristCountController =
      TextEditingController(text: '1');
  bool _generating = false;
  bool _userPickedTransportMode = false;

  final _formKey = GlobalKey<FormState>();

  @override
  void initState() {
    super.initState();
    _loadSavedPreferences();
  }

  Future<void> _loadSavedPreferences() async {
    final store = TripPreferencesStore.instance;
    final transport = await store.loadLastTransport();
    final interests = await store.loadLastInterests();
    final tierName = await store.loadLastBudgetTier();
    if (!mounted) return;
    setState(() {
      // Do not overwrite if the user already picked a mode (async prefs race).
      if (!_userPickedTransportMode &&
          transport != null &&
          kTransportModes.contains(transport)) {
        _transportMode = transport;
      }
      if (interests.isNotEmpty) {
        _selectedInterests
          ..clear()
          ..addAll(interests.where(kTravelInterests.contains));
      }
      if (tierName != null) {
        _budgetTier = TripBudgetTier.values.firstWhere(
          (t) => t.name == tierName,
          orElse: () => TripBudgetTier.moderate,
        );
      }
      if (_budgetController.text.isEmpty &&
          _budgetTier != TripBudgetTier.custom) {
        _budgetController.text =
            _budgetTier.resolveBudget(null).toStringAsFixed(0);
      }
    });
  }

  @override
  void dispose() {
    _budgetController.dispose();
    _timeConstraintController.dispose();
    _dateRangeDisplayController.dispose();
    _touristCountController.dispose();
    super.dispose();
  }

  int _parsedTouristCount() {
    final n = int.tryParse(_touristCountController.text.trim());
    if (n == null || n < 1) return 1;
    return n > 99 ? 99 : n;
  }

  String? _validateTouristCount(String? value) {
    final raw = value?.trim() ?? '';
    if (raw.isEmpty) return 'Enter number of tourists';
    final n = int.tryParse(raw);
    if (n == null) return 'Enter a whole number';
    if (n < 1) return 'At least 1 tourist';
    if (n > 99) return 'Maximum 99 tourists';
    return null;
  }

  Future<void> _pickDateRange() async {
    final now = DateTime.now();
    final result = await showDateRangePicker(
      context: context,
      firstDate: now,
      lastDate: DateTime(now.year + 2),
      initialDateRange:
          _dateRange ??
          DateTimeRange(start: now, end: now.add(const Duration(days: 2))),
    );

    if (result != null) {
      setState(() {
        _dateRange = result;
        final days = result.end.difference(result.start).inDays + 1;
        _timeConstraintController.text = '$days day${days == 1 ? '' : 's'}';
        _dateRangeDisplayController.text = _formatDateRange();
      });
    }
  }

  String _formatDateRange() {
    if (_dateRange == null) return 'Select dates';
    final start = _dateRange!.start;
    final end = _dateRange!.end;
    final startStr = '${_monthName(start.month)} ${start.day}, ${start.year}';
    final endStr = '${_monthName(end.month)} ${end.day}, ${end.year}';
    return '$startStr - $endStr';
  }

  String _monthName(int month) {
    const months = [
      'January', 'February', 'March', 'April', 'May', 'June',
      'July', 'August', 'September', 'October', 'November', 'December',
    ];
    return months[month - 1];
  }

  double _resolvedBudget() {
    final custom = double.tryParse(_budgetController.text.trim());
    return _budgetTier.resolveBudget(custom);
  }

  Future<void> _toggleUseCurrentLocation(bool useCurrent) async {
    if (!useCurrent) {
      setState(() {
        _useCurrentLocation = false;
        _resolvingCurrentLocation = false;
      });
      return;
    }
    setState(() {
      _useCurrentLocation = true;
      _resolvingCurrentLocation = true;
      _currentLocationLabel = null;
    });
    await _resolveCurrentLocationStart();
  }

  Future<void> _resolveCurrentLocationStart() async {
    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        _showLocationError('Please enable location services first.');
        return;
      }

      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        _showLocationError(
          'Location permission is required to use current location.',
        );
        return;
      }

      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
        ),
      );
      final nearest = _nearestMunicipality(
        LatLng(position.latitude, position.longitude),
      );
      if (nearest == null) {
        _showLocationError(
          'Could not map your location to a starting municipality.',
        );
        return;
      }
      if (!mounted) return;
      setState(() {
        _startMunicipality = nearest;
        _currentLocationLabel =
            'Using current location near ${nearest.shortName}';
        _resolvingCurrentLocation = false;
      });
    } catch (_) {
      _showLocationError('Unable to get current location. Try again.');
    }
  }

  Municipality? _nearestMunicipality(LatLng current) {
    Municipality? nearest;
    double nearestDistance = double.infinity;
    for (final municipality in municipalities) {
      final coord = getMunicipalityCoordinates(municipality);
      if (coord == null) continue;
      final dLat = current.latitude - coord.latitude;
      final dLng = current.longitude - coord.longitude;
      final distanceSquared = dLat * dLat + dLng * dLng;
      if (distanceSquared < nearestDistance) {
        nearestDistance = distanceSquared;
        nearest = municipality;
      }
    }
    return nearest;
  }

  void _showLocationError(String message) {
    if (!mounted) return;
    setState(() {
      _useCurrentLocation = false;
      _resolvingCurrentLocation = false;
      _currentLocationLabel = null;
    });
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  void _toggleInterest(String interest) {
    setState(() {
      if (_selectedInterests.contains(interest)) {
        if (_selectedInterests.length > 1) {
          _selectedInterests.remove(interest);
        }
      } else {
        _selectedInterests.add(interest);
      }
    });
  }

  Future<void> _onGeneratePlan() async {
    if (!_formKey.currentState!.validate()) return;
    if (_selectedInterests.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Select at least one interest.')),
      );
      return;
    }

    setState(() => _generating = true);
    try {
      await loadEventsFromFirestore();

      final dateRange = _dateRange!;
      if (_startMunicipality == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Please set your starting point first.'),
            ),
          );
        }
        return;
      }
      final start = _startMunicipality!;
      final end = _endMunicipality!;
      final budget = _resolvedBudget();

      final municipalitiesOnRoute = await _resolveMunicipalitiesAlongRoute(
        start: start,
        end: end,
      );
      final routeAliases = <String>{};
      for (final municipality in municipalitiesOnRoute) {
        routeAliases.addAll(municipalityAliases(municipality));
      }

      final numberOfTourists = _parsedTouristCount();

      final request = TripRecommendationRequest(
        dateRange: dateRange,
        start: start,
        end: end,
        numberOfTourists: numberOfTourists,
        transportMode: _transportMode,
        interests: Set<String>.from(_selectedInterests),
        budget: budget,
        budgetTier: _budgetTier,
        municipalitiesOnRoute: municipalitiesOnRoute,
        routeLocationAliases: routeAliases,
      );

      final result =
          await TripRecommendationEngine.instance.generate(request);

      final routeFareBreakdown = shouldShowTransportationFees(_transportMode)
          ? (await buildItineraryTransportFareBreakdown(
                result.itinerarySpots,
              ) ??
              buildItineraryTransportFareBreakdownSync(result.itinerarySpots))
          : null;

      if (!mounted) return;
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => TripPlanResultPage(
            dateRange: dateRange,
            start: start,
            end: end,
            numberOfTourists: numberOfTourists,
            transportMode: _transportMode,
            interests: _selectedInterests.toList()..sort(),
            budget: budget,
            budgetTierLabel: _budgetTier.label,
            spots: result.itinerarySpots,
            municipalitiesAlongRoute: municipalitiesOnRoute,
            routeFareBreakdown: routeFareBreakdown,
            exactBudgetSpotNames: result.exactBudgetSpotNames,
            routeEvents: result.routeEvents,
            insightSummary: result.insightSummary,
            alternativeSpots: result.scoredCandidates,
            routeLocationAliases: routeAliases,
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _generating = false);
    }
  }

  Future<List<Municipality>> _resolveMunicipalitiesAlongRoute({
    required Municipality start,
    required Municipality end,
  }) async {
    final byRoadTable = municipalitiesOnRoadBetween(start, end);
    if (byRoadTable != null) return byRoadTable;

    final startCoord = getMunicipalityCoordinates(start);
    final endCoord = getMunicipalityCoordinates(end);
    if (startCoord == null || endCoord == null) {
      return [start, end];
    }

    final directions = await getDirectionsRoute([startCoord, endCoord]);
    final points =
        directions.polyline ?? _interpolate(startCoord, endCoord, 32);
    return municipalitiesAlongRoute(
      start: start,
      end: end,
      routePoints: points,
    );
  }

  List<LatLng> _interpolate(LatLng a, LatLng b, int segments) {
    final points = <LatLng>[];
    for (var i = 0; i <= segments; i++) {
      final t = i / segments;
      points.add(
        LatLng(
          a.latitude + (b.latitude - a.latitude) * t,
          a.longitude + (b.longitude - a.longitude) * t,
        ),
      );
    }
    return points;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.primary,
        elevation: 0,
        foregroundColor: Colors.white,
        centerTitle: true,
        title: const Text(
          'Generate',
          style: TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w600,
            color: Colors.white,
          ),
        ),
      ),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final hPad = tourismPagePadding(constraints.maxWidth);
            final maxW = constraints.maxWidth < 520
                ? constraints.maxWidth
                : 520.0;
            return Center(
              child: ConstrainedBox(
                constraints: BoxConstraints(maxWidth: maxW),
                child: Column(
              children: [
                Expanded(
                  child: SingleChildScrollView(
                    padding: EdgeInsets.symmetric(
                      horizontal: hPad,
                      vertical: 8,
                    ),
                    child: Form(
                      key: _formKey,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const SizedBox(height: 8),
                          const Center(
                            child: Text(
                              'Trip planner',
                              style: TextStyle(
                                fontSize: 28,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 0.2,
                              ),
                            ),
                          ),
                          const SizedBox(height: 20),

                          const Text(
                            'Travel Dates',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 6),
                          GestureDetector(
                            onTap: _pickDateRange,
                            child: AbsorbPointer(
                              child: TextFormField(
                                readOnly: true,
                                decoration: const InputDecoration(
                                  suffixIcon: Icon(
                                    Icons.calendar_today_outlined,
                                    size: 18,
                                    color: Colors.grey,
                                  ),
                                ),
                                controller: _dateRangeDisplayController,
                                validator: (_) {
                                  if (_dateRange == null) {
                                    return 'Please select travel dates';
                                  }
                                  return null;
                                },
                              ),
                            ),
                          ),
                          const SizedBox(height: 16),

                          LayoutBuilder(
                            builder: (context, constraints) {
                              final locationButton = TextButton.icon(
                                onPressed: _resolvingCurrentLocation
                                    ? null
                                    : () => _toggleUseCurrentLocation(
                                        !_useCurrentLocation,
                                      ),
                                icon: Icon(
                                  _useCurrentLocation
                                      ? Icons.my_location
                                      : Icons.location_searching,
                                  size: 16,
                                ),
                                label: Text(
                                  _useCurrentLocation
                                      ? 'Using location'
                                      : 'Use my location',
                                ),
                              );
                              if (constraints.maxWidth <
                                  TourismBreakpoints.phone) {
                                return Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: [
                                    const Text(
                                      'Starting Point',
                                      style: TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                    Align(
                                      alignment: Alignment.centerLeft,
                                      child: locationButton,
                                    ),
                                  ],
                                );
                              }
                              return Row(
                                children: [
                                  const Expanded(
                                    child: Text(
                                      'Starting Point',
                                      style: TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                  locationButton,
                                ],
                              );
                            },
                          ),
                          const SizedBox(height: 6),
                          if (_useCurrentLocation)
                            TextFormField(
                              readOnly: true,
                              decoration: InputDecoration(
                                hintText: _resolvingCurrentLocation
                                    ? 'Getting your location...'
                                    : (_currentLocationLabel ??
                                          'Using current location'),
                                suffixIcon: _resolvingCurrentLocation
                                    ? const Padding(
                                        padding: EdgeInsets.all(12),
                                        child: SizedBox(
                                          width: 16,
                                          height: 16,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                          ),
                                        ),
                                      )
                                    : const Icon(
                                        Icons.my_location,
                                        size: 18,
                                        color: Colors.green,
                                      ),
                              ),
                              validator: (_) {
                                if (_useCurrentLocation &&
                                    _startMunicipality == null) {
                                  return 'Unable to detect your location';
                                }
                                return null;
                              },
                            )
                          else
                            DropdownButtonFormField<Municipality>(
                              isExpanded: true,
                              decoration: const InputDecoration(),
                              initialValue: _startMunicipality,
                              items: sortedMunicipalities
                                  .map(
                                    (m) => DropdownMenuItem(
                                      value: m,
                                      child: Text(m.name),
                                    ),
                                  )
                                  .toList(),
                              onChanged: (m) {
                                setState(() => _startMunicipality = m);
                              },
                              validator: (value) => value == null
                                  ? 'Please select starting point'
                                  : null,
                            ),
                          const SizedBox(height: 16),

                          const Text(
                            'End Point',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 6),
                          DropdownButtonFormField<Municipality>(
                            isExpanded: true,
                            decoration: const InputDecoration(),
                            initialValue: _endMunicipality,
                            items: sortedMunicipalities
                                .map(
                                  (m) => DropdownMenuItem(
                                    value: m,
                                    child: Text(m.name),
                                  ),
                                )
                                .toList(),
                            onChanged: (m) {
                              setState(() => _endMunicipality = m);
                            },
                            validator: (value) => value == null
                                ? 'Please select end point'
                                : null,
                          ),
                          const SizedBox(height: 16),

                          const Text(
                            'Number of tourist',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 4),
                          const Text(
                            'How many people are traveling on this trip?',
                            style: TextStyle(
                              fontSize: 12,
                              color: AppColors.textGrey,
                            ),
                          ),
                          const SizedBox(height: 6),
                          TextFormField(
                            controller: _touristCountController,
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(
                              hintText: 'e.g. 2',
                            ),
                            onChanged: (_) => setState(() {}),
                            validator: _validateTouristCount,
                          ),
                          const SizedBox(height: 16),

                          const Text(
                            'Transportation Mode',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            _transportHint(_transportMode),
                            style: const TextStyle(
                              fontSize: 12,
                              color: AppColors.textGrey,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: kTransportModes.map((mode) {
                              final selected = _transportMode == mode;
                              return ChoiceChip(
                                label: Text(mode),
                                selected: selected,
                                onSelected: (_) {
                                  setState(() {
                                    _userPickedTransportMode = true;
                                    _transportMode = mode;
                                  });
                                },
                                selectedColor:
                                    AppColors.primary.withOpacity(0.25),
                                labelStyle: TextStyle(
                                  fontWeight: selected
                                      ? FontWeight.w700
                                      : FontWeight.w500,
                                  color: selected
                                      ? AppColors.primary
                                      : AppColors.textDark,
                                ),
                              );
                            }).toList(),
                          ),
                          const SizedBox(height: 16),

                          const Text(
                            'Interests',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 4),
                          const Text(
                            'Select all that apply - we prioritize spots matching your mix.',
                            style: TextStyle(
                              fontSize: 12,
                              color: AppColors.textGrey,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: kTravelInterests.map((interest) {
                              final selected =
                                  _selectedInterests.contains(interest);
                              return FilterChip(
                                label: Text(interest),
                                selected: selected,
                                onSelected: (_) => _toggleInterest(interest),
                                selectedColor:
                                    AppColors.primary.withOpacity(0.22),
                                checkmarkColor: AppColors.primary,
                              );
                            }).toList(),
                          ),
                          const SizedBox(height: 16),

                          const Text(
                            'Budget',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: TripBudgetTier.values.map((tier) {
                              final selected = _budgetTier == tier;
                              return ChoiceChip(
                                label: Text(tier.label),
                                selected: selected,
                                onSelected: (_) => setState(() {
                                  _budgetTier = tier;
                                  if (tier != TripBudgetTier.custom) {
                                    _budgetController.text = tier
                                        .resolveBudget(null)
                                        .toStringAsFixed(0);
                                  }
                                }),
                                selectedColor:
                                    AppColors.primary.withOpacity(0.25),
                              );
                            }).toList(),
                          ),
                          const SizedBox(height: 8),
                          TextFormField(
                            controller: _budgetController,
                            keyboardType: TextInputType.number,
                            readOnly: _budgetTier != TripBudgetTier.custom,
                            decoration: InputDecoration(
                              hintText: _budgetTier.hint,
                              prefixText: '₱ ',
                            ),
                            validator: (value) {
                              if (_budgetTier == TripBudgetTier.custom &&
                                  (value == null || value.trim().isEmpty)) {
                                return 'Enter your budget amount';
                              }
                              return null;
                            },
                          ),
                          const SizedBox(height: 16),

                          const Text(
                            'Duration',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 6),
                          TextFormField(
                            controller: _timeConstraintController,
                            readOnly: true,
                            decoration: InputDecoration(
                              hintText: 'From travel dates',
                              suffixIcon: _dateRange != null
                                  ? const Icon(
                                      Icons.check_circle_outline,
                                      size: 18,
                                      color: Colors.green,
                                    )
                                  : null,
                            ),
                          ),
                          const SizedBox(height: 28),
                        ],
                      ),
                    ),
                  ),
                ),

                Container(
                  padding: EdgeInsets.symmetric(
                    horizontal: hPad,
                  ).copyWith(bottom: 16),
                  color: Colors.white,
                  child: SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      onPressed: _generating ? null : _onGeneratePlan,
                      child: _generating
                          ? const SizedBox(
                              width: 22,
                              height: 22,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Text(
                              'Generate Plan',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                                color: Colors.white,
                              ),
                            ),
                    ),
                  ),
                ),
              ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  String _transportHint(String mode) {
    switch (mode) {
      case 'Public Transport':
        return 'Stops near transport hubs along your route.';
      case 'Motorcycle':
        return 'Flexible routing with more stops per day.';
      case 'Car':
      default:
        return 'Full route coverage with up to 4 stops per day.';
    }
  }
}

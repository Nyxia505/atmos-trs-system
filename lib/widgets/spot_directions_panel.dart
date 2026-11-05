import 'dart:async';

import 'package:atmos_trs_system/config/app_theme.dart';
import 'package:atmos_trs_system/models/tourist_spot_firestore.dart';
import 'package:atmos_trs_system/screens/choose_starting_town_page.dart';
import 'package:atmos_trs_system/screens/spot_directions_route_page.dart';
import 'package:atmos_trs_system/utils/spot_route_destination.dart';
import 'package:atmos_trs_system/widgets/spot_route_itinerary.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart' show LatLng;
import 'package:trip_plan/data.dart' as trip;
import 'package:trip_plan/municipality_bus_terminals.dart'
    show haversineDistanceKm;
import 'package:trip_plan/municipality_coordinates.dart';
import 'package:trip_plan/tourist_plan/tourist_travel_estimates.dart'
    show formatHoursMinutes, travelMinutesForKm;
import 'package:trip_plan/widgets/trip_route_map_view.dart';

/// Collapsible Trip Planner map on Tourist Spot Details.
class SpotDirectionsPanel extends StatefulWidget {
  const SpotDirectionsPanel({
    super.key,
    required this.spotId,
    required this.spotName,
    required this.municipality,
    this.latitude = 0,
    this.longitude = 0,
    this.firestoreSpot,
  });

  final String spotId;
  final String spotName;
  final String municipality;
  final double latitude;
  final double longitude;
  final TouristSpotFirestore? firestoreSpot;

  @override
  State<SpotDirectionsPanel> createState() => SpotDirectionsPanelState();
}

class SpotDirectionsPanelState extends State<SpotDirectionsPanel> {
  final _mapKey = GlobalKey<TripRouteMapViewState>();

  bool _expanded = true;
  bool _resolving = true;
  bool _permissionDenied = false;
  bool _pickedManually = false;
  String? _locationMessage;
  String? _destError;
  SpotMapPoint? _dest;
  LatLng? _origin;
  String _originLabel = 'Your location';
  bool _routeFailed = false;
  bool _routeLoading = false;
  String? _routeError;
  double? _routeKm;
  int? _routeMinutes;
  int _routeGeneration = 0;
  String _travelMode = 'Motorcycle';

  static const _travelModes = <({String id, String label, IconData icon})>[
    (id: 'Car', label: 'Car', icon: Icons.directions_car_rounded),
    (id: 'Motorcycle', label: 'Two-wheeler', icon: Icons.two_wheeler_rounded),
    (id: 'Walking', label: 'Walk', icon: Icons.directions_walk_rounded),
  ];

  @override
  void initState() {
    super.initState();
    // Defer until after this frame. Calling setState from initState while the
    // details screen is still building aborts retry() and leaves the spinner.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(retry());
    });
  }

  static const _destLookupTimeout = Duration(seconds: 5);
  static const _locationTimeout = Duration(seconds: 5);
  static const _unableToLoad =
      'Unable to load directions. Please try again.';

  Future<void> retry() async {
    final generation = ++_routeGeneration;
    final knownDest = spotMapPointFromKnownSources(
      spotId: widget.spotId,
      name: widget.spotName,
      municipality: widget.municipality,
      latitude: widget.latitude,
      longitude: widget.longitude,
      firestoreSpot: widget.firestoreSpot,
    );
    if (mounted) {
      setState(() {
        _resolving = knownDest == null;
        _dest = knownDest ?? _dest;
        _destError = null;
        _routeFailed = false;
        _routeError = null;
        _routeLoading = false;
        _expanded = true;
      });
    }

    try {
      SpotMapPoint? dest = knownDest ?? await _lookupDestination();
      if (!mounted || generation != _routeGeneration) return;

      if (dest == null) {
        setState(() {
          _resolving = false;
          _dest = null;
          _destError = _unableToLoad;
        });
        return;
      }

      setState(() {
        _dest = dest;
        _resolving = false;
      });
      await _resolveOrigin(generation: generation);
    } catch (_) {
      if (!mounted || generation != _routeGeneration) return;
      setState(() {
        _resolving = false;
        if (_dest == null) {
          _destError = _unableToLoad;
        } else if (_origin == null && _locationMessage == null) {
          _locationMessage =
              'Could not read your current location. Pick a starting town or retry.';
        }
      });
    }
  }

  Future<SpotMapPoint?> _lookupDestination() async {
    try {
      return await resolveSpotMapPoint(
        spotId: widget.spotId,
        name: widget.spotName,
        municipality: widget.municipality,
        latitude: widget.latitude,
        longitude: widget.longitude,
        firestoreSpot: widget.firestoreSpot,
      ).timeout(_destLookupTimeout);
    } catch (_) {
      return spotMapPointFromKnownSources(
        spotId: widget.spotId,
        name: widget.spotName,
        municipality: widget.municipality,
        latitude: widget.latitude,
        longitude: widget.longitude,
        firestoreSpot: widget.firestoreSpot,
      );
    }
  }

  Future<void> _resolveOrigin({required int generation}) async {
    if (_pickedManually && _origin != null) return;
    if (mounted && generation == _routeGeneration) {
      setState(() {
        _locationMessage = null;
        _permissionDenied = false;
      });
    }
    try {
      final result = await _readCurrentLocation();
      if (!mounted || generation != _routeGeneration) return;
      setState(() {
        _permissionDenied = result.denied;
        _locationMessage = result.message;
        if (result.point != null) {
          _origin = result.point;
          _originLabel = result.label;
          _pickedManually = false;
        }
      });
    } catch (_) {
      if (!mounted || generation != _routeGeneration) return;
      setState(() {
        _locationMessage ??=
            'Could not read your current location. Pick a starting town or retry.';
      });
    }
  }

  Future<({LatLng? point, String label, bool denied, String? message})>
      _readCurrentLocation() async {
    try {
      final enabled = await Geolocator.isLocationServiceEnabled()
          .timeout(const Duration(seconds: 2), onTimeout: () => false);
      if (!enabled) {
        return (
          point: null,
          label: 'Your location',
          denied: true,
          message:
              'Turn on Location to start from where you are, or pick a starting town.',
        );
      }
      var permission = await Geolocator.checkPermission()
          .timeout(const Duration(seconds: 2));
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission()
            .timeout(const Duration(seconds: 8));
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        return (
          point: null,
          label: 'Your location',
          denied: true,
          message:
              'Location permission is off. Allow it, or pick a starting town to see the route.',
        );
      }
      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.medium,
          timeLimit: _locationTimeout,
        ),
      ).timeout(_locationTimeout);
      final point = LatLng(pos.latitude, pos.longitude);
      final nearest = nearestTripMunicipality(point);
      return (
        point: point,
        label: 'Your location (near ${nearest.shortName})',
        denied: false,
        message: null,
      );
    } on TimeoutException {
      return (
        point: null,
        label: 'Your location',
        denied: false,
        message:
            'Could not read your current location. Pick a starting town or retry.',
      );
    } catch (_) {
      return (
        point: null,
        label: 'Your location',
        denied: false,
        message:
            'Could not read your current location. Pick a starting town or retry.',
      );
    }
  }

  Future<void> _pickStartingTown() async {
    final dest = _dest;
    final chosen = await Navigator.of(context).push<trip.Municipality>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => const ChooseStartingTownPage(),
      ),
    );
    if (!mounted || chosen == null) return;
    final coord = getMunicipalityCoordinates(chosen);
    if (coord == null) {
      setState(() {
        _locationMessage =
            'No map pin is saved for ${chosen.shortName}. Try another town.';
      });
      return;
    }
    setState(() {
      _origin = coord;
      _originLabel = chosen.shortName.isNotEmpty ? chosen.shortName : chosen.name;
      _pickedManually = true;
      _permissionDenied = false;
      _locationMessage = dest == null
          ? null
          : 'Starting from $_originLabel.';
      _routeFailed = false;
      _routeError = null;
    });
  }

  void _onRouteUpdate(TripRouteUpdate update) {
    if (!mounted) return;
    if (update.loading) return;
    final failed = update.failed && update.distanceKm == null && _routeKm == null;
    final error = failed
        ? (update.errorMessage == null || update.errorMessage!.trim().isEmpty
            ? _unableToLoad
            : update.errorMessage)
        : null;
    if (_routeLoading == false &&
        _routeFailed == failed &&
        _routeKm == (update.distanceKm ?? _routeKm) &&
        _routeMinutes == (update.durationMinutes ?? _routeMinutes) &&
        _routeError == error) {
      return;
    }
    setState(() {
      _routeLoading = false;
      _routeFailed = failed;
      if (update.distanceKm != null) _routeKm = update.distanceKm;
      if (update.durationMinutes != null) {
        _routeMinutes = update.durationMinutes;
      }
      _routeError = error;
    });
  }

  void _openFullRoute() {
    final dest = _dest;
    final origin = _origin;
    if (dest == null || origin == null) return;
    Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        fullscreenDialog: true,
        builder: (_) => SpotDirectionsRoutePage(
          spotId: widget.spotId,
          spotName: widget.spotName,
          municipality: widget.municipality,
          latitude: dest.latitude,
          longitude: dest.longitude,
          firestoreSpot: widget.firestoreSpot,
          initialOrigin: origin,
          initialOriginLabel: _originLabel,
          initialTravelMode: _travelMode,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final accent = AppTheme.primary;
    final dest = _dest;
    final origin = _origin;

    return _surface(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            onTap: () => setState(() => _expanded = !_expanded),
            child: Row(
              children: [
                Icon(Icons.alt_route_rounded, color: accent),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Route to ${widget.spotName}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                          color: AppTheme.textPrimary,
                        ),
                      ),
                      Text(
                        _summaryLine(),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12,
                          color: AppTheme.unselectedMuted,
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(
                  _expanded
                      ? Icons.expand_less_rounded
                      : Icons.expand_more_rounded,
                  color: AppTheme.unselectedMuted,
                ),
              ],
            ),
          ),
          if (_expanded) ...[
            const SizedBox(height: 12),
            if (_destError != null)
              _messageCard(
                _destError!,
                actionLabel: 'Retry',
                onAction: retry,
              )
            else if (_resolving && dest == null)
              const SizedBox.shrink()
            else ...[
              if (_locationMessage != null) ...[
                _messageCard(
                  _locationMessage!,
                  actionLabel: _permissionDenied
                      ? 'Choose start'
                      : 'Retry location',
                  onAction: _permissionDenied
                      ? _pickStartingTown
                      : () => unawaited(
                            _resolveOrigin(generation: _routeGeneration),
                          ),
                  secondaryLabel:
                      _permissionDenied ? 'Retry location' : 'Choose start',
                  onSecondary: _permissionDenied
                      ? () => unawaited(
                            _resolveOrigin(generation: _routeGeneration),
                          )
                      : _pickStartingTown,
                ),
                const SizedBox(height: 10),
              ],
              if (dest != null) ...[
                ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: SizedBox(
                    height: _mapHeight(context),
                    width: double.infinity,
                    child: RepaintBoundary(
                      child: TripRouteMapView(
                      key: _mapKey,
                      compact: true,
                      interactive: true,
                      start: origin == null
                          ? tripMunicipalityFor(
                              name: dest.municipality,
                              latitude: dest.latitude,
                              longitude: dest.longitude,
                            )
                          : nearestTripMunicipality(origin),
                      end: tripMunicipalityFor(
                        name: dest.municipality,
                        latitude: dest.latitude,
                        longitude: dest.longitude,
                      ),
                      spots: [tripSpotFor(dest)],
                      visitStops: [
                        if (origin != null)
                          (
                            place: nearestTripMunicipality(origin).name,
                            point: origin,
                          ),
                        (
                          place: tripMunicipalityFor(
                            name: dest.municipality,
                            latitude: dest.latitude,
                            longitude: dest.longitude,
                          ).name,
                          point: dest.latLng,
                        ),
                      ],
                      startPinPoint: origin,
                      startPinTitle: _originLabel,
                      startPinDetail: _originLabel,
                      endPinPoint: dest.latLng,
                      endPinTitle: dest.name,
                      endPinDetail: dest.municipality,
                      showTouristSpots: true,
                      showBusStops: false,
                      showBusTerminals: false,
                      travelMode: _travelMode,
                      onRouteUpdate: _onRouteUpdate,
                    ),
                    ),
                  ),
                ),
                if (_routeFailed) ...[
                  const SizedBox(height: 10),
                  _messageCard(
                    _unableToLoad,
                    actionLabel: 'Retry',
                    onAction: () {
                      _mapKey.currentState?.retryDirections();
                      unawaited(retry());
                    },
                  ),
                ],
                if (origin != null) ...[
                  const SizedBox(height: 12),
                  _travelModePicker(dest),
                ],
                const SizedBox(height: 12),
                if (origin != null)
                  SpotRouteItinerary(
                    places: placesAlongSpotRoute(
                      originLabel: _originLabel,
                      origin: origin,
                      dest: dest,
                    ),
                    compact: true,
                  )
                else
                  SpotRouteItinerary(
                    places: SpotRoutePlaces(
                      startLabel: 'Choose a starting location',
                      startTown: '',
                      endLabel: dest.name,
                      endTown: dest.municipality,
                      viaTowns: const [],
                      allTowns: dest.municipality.isEmpty
                          ? [dest.name]
                          : [dest.municipality],
                    ),
                    compact: true,
                  ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    FilledButton.icon(
                      onPressed: origin == null ? _pickStartingTown : _openFullRoute,
                      icon: Icon(
                        origin == null
                            ? Icons.edit_location_alt_outlined
                            : Icons.fullscreen_rounded,
                      ),
                      label: Text(
                        origin == null ? 'Choose start' : 'View Full Route',
                      ),
                    ),
                    OutlinedButton.icon(
                      onPressed: () => unawaited(retry()),
                      icon: const Icon(Icons.refresh_rounded),
                      label: const Text('Retry'),
                    ),
                    if (origin != null)
                      OutlinedButton.icon(
                        onPressed: _pickStartingTown,
                        icon: const Icon(Icons.flag_outlined),
                        label: const Text('Change start'),
                      ),
                  ],
                ),
              ],
            ],
          ],
        ],
      ),
    );
  }

  String _summaryLine() {
    if (_destError != null) return _destError!;
    if (_resolving && _dest == null) {
      return 'Finding this destination on the map…';
    }
    if (_routeFailed) {
      return _unableToLoad;
    }
    if (_origin == null) {
      return _dest == null
          ? 'Pick a starting location to draw the route.'
          : 'Showing ${_dest!.name}. Choose a start to see the full route.';
    }
    final dest = _dest;
    if (dest != null) {
      final places = placesAlongSpotRoute(
        originLabel: _originLabel,
        origin: _origin!,
        dest: dest,
      );
      final km = _displayKm(dest);
      final minutes = km > 0 ? travelMinutesForKm(km, _travelMode) : 0;
      final via = places.hasViaTowns
          ? 'From ${places.startTown} via ${places.viaTowns.join(', ')} to ${places.endLabel}'
          : 'From ${places.startTown} to ${places.endLabel}';
      if (minutes > 0) {
        return '$via · ${formatHoursMinutes(minutes)} by ${_travelMode.toLowerCase()}';
      }
      return via;
    }
    if (_routeKm != null || _routeMinutes != null) {
      return [
        if (_routeKm != null) '${_routeKm!.toStringAsFixed(1)} km',
        if (_routeMinutes != null)
          '~${formatHoursMinutes(_routeMinutes!)} driving',
      ].join(' · ');
    }
    if (_routeLoading) return 'Drawing the road route…';
    return 'From $_originLabel';
  }

  double _mapHeight(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final shortest = size.shortestSide;
    if (shortest < 600) {
      return (size.height * 0.42).clamp(280.0, 420.0);
    }
    return (size.height * 0.46).clamp(320.0, 560.0);
  }

  double _displayKm(SpotMapPoint dest) {
    if (_routeKm != null && _routeKm! > 0) return _routeKm!;
    final origin = _origin;
    if (origin == null) return 0;
    return haversineDistanceKm(
          origin.latitude,
          origin.longitude,
          dest.latitude,
          dest.longitude,
        ) *
        1.25;
  }

  Widget _travelModePicker(SpotMapPoint dest) {
    final accent = AppTheme.primary;
    final km = _displayKm(dest);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          km > 0 ? '${km.toStringAsFixed(1)} km by road' : 'Travel time',
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: AppTheme.textPrimary,
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            for (var i = 0; i < _travelModes.length; i++) ...[
              if (i > 0) const SizedBox(width: 8),
              Expanded(
                child: _modeChip(_travelModes[i], km, accent),
              ),
            ],
          ],
        ),
      ],
    );
  }

  Widget _modeChip(
    ({String id, String label, IconData icon}) mode,
    double km,
    Color accent,
  ) {
    final selected = _travelMode == mode.id;
    final minutes = km > 0 ? travelMinutesForKm(km, mode.id) : 0;
    return Material(
      color: selected ? accent : AppTheme.cardBackground,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: () => setState(() => _travelMode = mode.id),
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: selected ? accent : AppTheme.border,
              width: 1.5,
            ),
          ),
          child: Column(
            children: [
              Icon(
                mode.icon,
                size: 20,
                color: selected ? Colors.white : accent,
              ),
              const SizedBox(height: 4),
              Text(
                mode.label,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  color: selected ? Colors.white : AppTheme.textPrimary,
                ),
              ),
              Text(
                minutes > 0 ? formatHoursMinutes(minutes) : '—',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  color: selected
                      ? Colors.white.withValues(alpha: 0.9)
                      : AppTheme.unselectedMuted,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _surface({required Widget child}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.cardBackground,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppTheme.border, width: 1.5),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 18,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: child,
    );
  }

  Widget _messageCard(
    String message, {
    required String actionLabel,
    required VoidCallback onAction,
    String? secondaryLabel,
    VoidCallback? onSecondary,
  }) {
    final accent = AppTheme.primary;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 10),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: accent.withValues(alpha: 0.28)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            message,
            style: TextStyle(
              fontSize: 13,
              height: 1.35,
              color: AppTheme.textPrimary,
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            children: [
              TextButton(onPressed: onAction, child: Text(actionLabel)),
              if (secondaryLabel != null && onSecondary != null)
                TextButton(onPressed: onSecondary, child: Text(secondaryLabel)),
            ],
          ),
        ],
      ),
    );
  }
}

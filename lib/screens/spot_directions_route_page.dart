import 'dart:async';

import 'package:atmos_trs_system/models/tourist_spot_firestore.dart';
import 'package:atmos_trs_system/screens/choose_starting_town_page.dart';
import 'package:atmos_trs_system/utils/maps_directions_launcher.dart';
import 'package:atmos_trs_system/utils/spot_route_destination.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart' show LatLng;
import 'package:share_plus/share_plus.dart';
import 'package:trip_plan/data.dart' as trip;
import 'package:trip_plan/municipality_bus_terminals.dart'
    show haversineDistanceKm;
import 'package:trip_plan/municipality_coordinates.dart';
import 'package:trip_plan/tourist_plan/tourist_travel_estimates.dart'
    show formatHoursMinutes, travelMinutesForKm;
import 'package:trip_plan/widgets/trip_route_map_view.dart';

/// Full-screen Google Maps–style directions for one tourist spot.
class SpotDirectionsRoutePage extends StatefulWidget {
  const SpotDirectionsRoutePage({
    super.key,
    required this.spotId,
    required this.spotName,
    required this.municipality,
    this.latitude = 0,
    this.longitude = 0,
    this.firestoreSpot,
    this.initialOrigin,
    this.initialOriginLabel,
    this.initialTravelMode = 'Motorcycle',
  });

  final String spotId;
  final String spotName;
  final String municipality;
  final double latitude;
  final double longitude;
  final TouristSpotFirestore? firestoreSpot;
  final LatLng? initialOrigin;
  final String? initialOriginLabel;
  final String initialTravelMode;

  @override
  State<SpotDirectionsRoutePage> createState() =>
      _SpotDirectionsRoutePageState();
}

class _SpotDirectionsRoutePageState extends State<SpotDirectionsRoutePage> {
  static const _mapsBlue = Color(0xFF1A73E8);
  static const _startTeal = Color(0xFF0F766E);
  static const _sheetBg = Color(0xFFFFFFFF);
  static const _text = Color(0xFF202124);
  static const _muted = Color(0xFF5F6368);

  static const _modes = <({String id, IconData icon, bool enabled})>[
    (id: 'Car', icon: Icons.directions_car_rounded, enabled: true),
    (id: 'Motorcycle', icon: Icons.two_wheeler_rounded, enabled: true),
    (id: 'Transit', icon: Icons.directions_transit_rounded, enabled: false),
    (id: 'Walking', icon: Icons.directions_walk_rounded, enabled: true),
  ];

  final _mapKey = GlobalKey<TripRouteMapViewState>();

  SpotMapPoint? _dest;
  LatLng? _origin;
  String _originLabel = 'Oroquieta City';
  String _travelMode = 'Motorcycle';
  bool _swapped = false;
  double? _routeKm;
  bool _loadingOrigin = true;

  @override
  void initState() {
    super.initState();
    _travelMode = widget.initialTravelMode;
    _dest = spotMapPointFromKnownSources(
      spotId: widget.spotId,
      name: widget.spotName,
      municipality: widget.municipality,
      latitude: widget.latitude,
      longitude: widget.longitude,
      firestoreSpot: widget.firestoreSpot,
    );
    final given = widget.initialOrigin;
    if (given != null) {
      _origin = given;
      _originLabel = widget.initialOriginLabel?.trim().isNotEmpty == true
          ? widget.initialOriginLabel!.trim()
          : 'Your location';
      _loadingOrigin = false;
    } else {
      _origin = _oroquietaPoint();
      _originLabel = 'Oroquieta City';
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      unawaited(_lookupDestination());
      if (widget.initialOrigin == null) unawaited(_resolveGpsOrigin());
    });
  }

  LatLng _oroquietaPoint() {
    final muni = tripMunicipalityFor(name: 'Oroquieta City');
    return getMunicipalityCoordinates(muni) ??
        const LatLng(8.493037148800576, 123.79814266814685);
  }

  Future<void> _lookupDestination() async {
    if (_dest != null) return;
    final dest = await resolveSpotMapPoint(
      spotId: widget.spotId,
      name: widget.spotName,
      municipality: widget.municipality,
      latitude: widget.latitude,
      longitude: widget.longitude,
      firestoreSpot: widget.firestoreSpot,
    );
    if (!mounted) return;
    setState(() => _dest = dest);
  }

  Future<void> _resolveGpsOrigin() async {
    try {
      final enabled = await Geolocator.isLocationServiceEnabled()
          .timeout(const Duration(seconds: 2), onTimeout: () => false);
      if (!enabled) {
        if (mounted) setState(() => _loadingOrigin = false);
        return;
      }
      var permission = await Geolocator.checkPermission()
          .timeout(const Duration(seconds: 2));
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission()
            .timeout(const Duration(seconds: 8));
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        if (mounted) setState(() => _loadingOrigin = false);
        return;
      }
      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.medium,
          timeLimit: Duration(seconds: 5),
        ),
      ).timeout(const Duration(seconds: 5));
      if (!mounted) return;
      setState(() {
        _origin = LatLng(pos.latitude, pos.longitude);
        _originLabel = 'Your location';
        _loadingOrigin = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loadingOrigin = false);
    }
  }

  Future<void> _pickStartingTown() async {
    final chosen = await Navigator.of(context).push<trip.Municipality>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => const ChooseStartingTownPage(),
      ),
    );
    if (!mounted || chosen == null) return;
    final coord = getMunicipalityCoordinates(chosen);
    if (coord == null) return;
    setState(() {
      _origin = coord;
      _originLabel =
          chosen.shortName.isNotEmpty ? chosen.shortName : chosen.name;
      _swapped = false;
      _loadingOrigin = false;
    });
  }

  void _onRouteUpdate(TripRouteUpdate update) {
    if (!mounted || update.loading) return;
    if (update.distanceKm == _routeKm) return;
    setState(() {
      if (update.distanceKm != null) _routeKm = update.distanceKm;
    });
  }

  LatLng? get _fromPoint {
    final dest = _dest;
    final origin = _origin;
    if (dest == null || origin == null) return origin;
    return _swapped ? dest.latLng : origin;
  }

  LatLng? get _toPoint {
    final dest = _dest;
    final origin = _origin;
    if (dest == null) return null;
    if (origin == null) return dest.latLng;
    return _swapped ? origin : dest.latLng;
  }

  String get _fromLabel {
    final dest = _dest;
    if (_swapped && dest != null) return dest.name;
    return _originLabel;
  }

  String get _toLabel {
    final dest = _dest;
    if (_swapped) return _originLabel;
    return dest?.name ?? widget.spotName;
  }

  double _displayKm() {
    if (_routeKm != null && _routeKm! > 0) return _routeKm!;
    final from = _fromPoint;
    final to = _toPoint;
    if (from == null || to == null) return 0;
    return haversineDistanceKm(
          from.latitude,
          from.longitude,
          to.latitude,
          to.longitude,
        ) *
        1.25;
  }

  String _viaLine() {
    final dest = _dest;
    final origin = _origin;
    if (dest == null || origin == null) return '';
    final places = placesAlongSpotRoute(
      originLabel: _fromLabel,
      origin: _fromPoint!,
      dest: _swapped
          ? SpotMapPoint(
              spotId: 'origin',
              name: _originLabel,
              latitude: origin.latitude,
              longitude: origin.longitude,
              municipality: nearestTripMunicipality(origin).shortName,
            )
          : dest,
    );
    if (places.hasViaTowns) return 'via ${places.viaTowns.join(', ')}';
    return 'via ${places.startTown}';
  }

  String _googleTravelMode() {
    switch (_travelMode) {
      case 'Walking':
        return 'walking';
      case 'Motorcycle':
        return 'two_wheeler';
      case 'Car':
      default:
        return 'driving';
    }
  }

  Future<void> _startNavigation() async {
    final to = _toPoint;
    if (to == null) return;
    final from = _fromPoint;
    await MapsDirectionsLauncher.open(
      destinationLabel: _toLabel,
      destinationLatitude: to.latitude,
      destinationLongitude: to.longitude,
      originLabel: _fromLabel,
      originLatitude: from?.latitude,
      originLongitude: from?.longitude,
      travelMode: _googleTravelMode(),
    );
  }

  Future<void> _shareRoute() async {
    final to = _toPoint;
    final from = _fromPoint;
    final buffer = StringBuffer()
      ..writeln('$_fromLabel → $_toLabel')
      ..writeln();
    if (from != null && to != null) {
      buffer.writeln(
        'https://www.google.com/maps/dir/?api=1'
        '&origin=${from.latitude},${from.longitude}'
        '&destination=${to.latitude},${to.longitude}'
        '&travelmode=${_googleTravelMode()}',
      );
    }
    buffer.writeln('\nShared via ATMOS-TRS');
    await Share.share(buffer.toString(), subject: _toLabel);
  }

  @override
  Widget build(BuildContext context) {
    final dest = _dest;
    final origin = _origin;
    final from = _fromPoint;
    final to = _toPoint;
    final bottomInset = MediaQuery.paddingOf(context).bottom;

    return Scaffold(
      backgroundColor: const Color(0xFFE8EEF2),
      body: Stack(
        children: [
          Positioned.fill(
            child: dest == null
                ? const Center(child: CircularProgressIndicator())
                : TripRouteMapView(
                    key: _mapKey,
                    compact: true,
                    interactive: true,
                    travelMode: _travelMode,
                    googleStyleEndpoints: true,
                    start: origin == null
                        ? tripMunicipalityFor(
                            name: dest.municipality,
                            latitude: dest.latitude,
                            longitude: dest.longitude,
                          )
                        : nearestTripMunicipality(from ?? origin),
                    end: tripMunicipalityFor(
                      name: dest.municipality,
                      latitude: dest.latitude,
                      longitude: dest.longitude,
                    ),
                    spots: [tripSpotFor(dest)],
                    visitStops: [
                      if (from != null)
                        (
                          place: nearestTripMunicipality(from).name,
                          point: from,
                        ),
                      if (to != null)
                        (
                          place: tripMunicipalityFor(
                            name: dest.municipality,
                            latitude: dest.latitude,
                            longitude: dest.longitude,
                          ).name,
                          point: to,
                        ),
                    ],
                    startPinPoint: from,
                    startPinTitle: _fromLabel,
                    startPinDetail: _fromLabel,
                    endPinPoint: to,
                    endPinTitle: _toLabel,
                    endPinDetail: dest.municipality,
                    showTouristSpots: false,
                    showBusStops: false,
                    showBusTerminals: false,
                    onRouteUpdate: _onRouteUpdate,
                  ),
          ),
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: SafeArea(
              bottom: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                child: _originDestCard(),
              ),
            ),
          ),
          Positioned(
            right: 16,
            bottom: 268 + bottomInset,
            child: Material(
              color: Colors.white,
              shape: const CircleBorder(),
              elevation: 3,
              child: IconButton(
                tooltip: 'Your location',
                onPressed: () {
                  setState(() => _loadingOrigin = true);
                  unawaited(_resolveGpsOrigin());
                },
                icon: const Icon(Icons.my_location_rounded, color: _mapsBlue),
              ),
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: _bottomSheet(bottomInset),
          ),
        ],
      ),
    );
  }

  Widget _originDestCard() {
    return Material(
      color: _sheetBg,
      elevation: 3,
      shadowColor: Colors.black26,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(4, 8, 4, 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            IconButton(
              tooltip: 'Close',
              onPressed: () => Navigator.of(context).maybePop(),
              icon: const Icon(Icons.arrow_back_rounded, color: _text),
            ),
            Expanded(
              child: Column(
                children: [
                  _placeRow(
                    leading: Container(
                      width: 12,
                      height: 12,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(color: _muted, width: 2.4),
                      ),
                    ),
                    label: _fromLabel,
                    onTap: _pickStartingTown,
                  ),
                  Padding(
                    padding: const EdgeInsets.only(left: 5),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Container(
                        width: 2,
                        height: 18,
                        color: const Color(0xFFDADCE0),
                      ),
                    ),
                  ),
                  _placeRow(
                    leading: const Icon(
                      Icons.location_on,
                      size: 18,
                      color: Color(0xFFEA4335),
                    ),
                    label: _toLabel,
                    emphasize: true,
                  ),
                ],
              ),
            ),
            Column(
              children: [
                IconButton(
                  tooltip: 'More',
                  onPressed: _showMore,
                  icon: const Icon(Icons.more_vert_rounded, color: _text),
                ),
                IconButton(
                  tooltip: 'Swap start and destination',
                  onPressed: _origin == null || _dest == null
                      ? null
                      : () => setState(() => _swapped = !_swapped),
                  icon: const Icon(Icons.swap_vert_rounded, color: _text),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _placeRow({
    required Widget leading,
    required String label,
    VoidCallback? onTap,
    bool emphasize = false,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
        child: Row(
          children: [
            SizedBox(width: 22, child: Center(child: leading)),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: emphasize ? FontWeight.w600 : FontWeight.w500,
                  color: _text,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showMore() {
    showModalBottomSheet<void>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.my_location_rounded),
              title: const Text('Use current location'),
              onTap: () {
                Navigator.pop(ctx);
                setState(() => _loadingOrigin = true);
                unawaited(_resolveGpsOrigin());
              },
            ),
            ListTile(
              leading: const Icon(Icons.flag_outlined),
              title: const Text('Choose starting town'),
              onTap: () {
                Navigator.pop(ctx);
                unawaited(_pickStartingTown());
              },
            ),
            ListTile(
              leading: const Icon(Icons.refresh_rounded),
              title: const Text('Retry route'),
              onTap: () {
                Navigator.pop(ctx);
                _mapKey.currentState?.retryDirections();
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _bottomSheet(double bottomInset) {
    final km = _displayKm();
    final minutes = km > 0 ? travelMinutesForKm(km, _travelMode) : 0;
    final walking = _travelMode == 'Walking';

    return Material(
      color: _sheetBg,
      elevation: 12,
      shadowColor: Colors.black26,
      borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
      child: Padding(
        padding: EdgeInsets.fromLTRB(8, 8, 8, 12 + bottomInset),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: const Color(0xFFDADCE0),
                borderRadius: BorderRadius.circular(99),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 4, 0),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      _selectedModeTitle,
                      style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w700,
                        color: _text,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Share',
                    onPressed: _shareRoute,
                    icon: const Icon(Icons.share_outlined, color: _muted),
                  ),
                  IconButton(
                    tooltip: 'Close',
                    onPressed: () => Navigator.of(context).maybePop(),
                    icon: const Icon(Icons.close_rounded, color: _muted),
                  ),
                ],
              ),
            ),
            Row(
              children: [
                for (final mode in _modes)
                  Expanded(child: _modeTab(mode, km)),
              ],
            ),
            const Divider(height: 20),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      minutes > 0
                          ? '${formatHoursMinutes(minutes)} (${km.toStringAsFixed(1)} km)'
                          : _loadingOrigin
                              ? 'Finding the fastest route…'
                              : 'Route to $_toLabel',
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                        color: _text,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _viaLine().isEmpty ? 'Route on the provincial road' : _viaLine(),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 13, color: _muted),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 14),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    FilledButton.icon(
                      onPressed: _toPoint == null ? null : _startNavigation,
                      style: FilledButton.styleFrom(
                        backgroundColor: _startTeal,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 18,
                          vertical: 12,
                        ),
                      ),
                      icon: Icon(
                        walking
                            ? Icons.preview_rounded
                            : Icons.navigation_rounded,
                        size: 18,
                      ),
                      label: Text(walking ? 'Preview' : 'Start'),
                    ),
                    const SizedBox(width: 8),
                    OutlinedButton.icon(
                      onPressed: _pickStartingTown,
                      style: OutlinedButton.styleFrom(
                        foregroundColor: _startTeal,
                        side: const BorderSide(color: Color(0xFFDADCE0)),
                      ),
                      icon: const Icon(
                        Icons.add_location_alt_outlined,
                        size: 18,
                      ),
                      label: const Text('Add stops'),
                    ),
                    const SizedBox(width: 8),
                    OutlinedButton.icon(
                      onPressed: _shareRoute,
                      style: OutlinedButton.styleFrom(
                        foregroundColor: _startTeal,
                        side: const BorderSide(color: Color(0xFFDADCE0)),
                      ),
                      icon: const Icon(Icons.share_outlined, size: 18),
                      label: const Text('Share'),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String get _selectedModeTitle {
    switch (_travelMode) {
      case 'Walking':
        return 'Walk';
      case 'Car':
        return 'Driving';
      case 'Motorcycle':
      default:
        return 'Two-wheeler';
    }
  }

  String _tabTime(int minutes) {
    if (minutes < 60) return '$minutes min';
    final h = minutes ~/ 60;
    final m = minutes % 60;
    if (m == 0) return '$h hr';
    return '$h hr $m';
  }

  Widget _modeTab(
    ({String id, IconData icon, bool enabled}) mode,
    double km,
  ) {
    final selected = _travelMode == mode.id;
    final minutes = mode.enabled && km > 0
        ? travelMinutesForKm(km, mode.id)
        : 0;
    final color = !mode.enabled
        ? const Color(0xFF9AA0A6)
        : selected
            ? _mapsBlue
            : _muted;
    return InkWell(
      onTap: mode.enabled
          ? () => setState(() => _travelMode = mode.id)
          : null,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(
              color: selected ? _mapsBlue : Colors.transparent,
              width: 3,
            ),
          ),
        ),
        child: Column(
          children: [
            Icon(mode.icon, color: color, size: 22),
            const SizedBox(height: 4),
            Text(
              mode.enabled
                  ? (minutes > 0 ? _tabTime(minutes) : '…')
                  : '—',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

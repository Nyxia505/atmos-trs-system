import 'dart:async';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

import 'package:atmos_trs_system/config/qr_scan_geofence_config.dart';
import 'package:atmos_trs_system/services/osm_place_search.dart';
import 'package:atmos_trs_system/utils/municipality_helper.dart';
import 'package:atmos_trs_system/widgets/atmos_osm_tile_layer.dart';

/// True when a printed spot QR no longer matches the saved pin
/// (check-in rejects QR vs Firestore mismatches above this distance).
bool spotPinNeedsReprint({
  required double printedLatitude,
  required double printedLongitude,
  required double latitude,
  required double longitude,
}) {
  if (printedLatitude.abs() <= 1e-6 && printedLongitude.abs() <= 1e-6) {
    return false;
  }
  return Geolocator.distanceBetween(
        printedLatitude,
        printedLongitude,
        latitude,
        longitude,
      ) >
      kQrScanQrVsFirestoreMaxMismatchMeters;
}

/// Tourist-spot map pin for LGU dialogs: auto-locates on open (falls back to
/// the municipality anchor) and reuses the establishment "Adjust pin" map.
class SpotLocationPicker extends StatefulWidget {
  const SpotLocationPicker({
    super.key,
    required this.onChanged,
    this.initialLatitude,
    this.initialLongitude,
    this.fallbackLatitude,
    this.fallbackLongitude,
    this.autoLocate = false,
    this.placePinOnFallback = true,
    this.printedLatitude,
    this.printedLongitude,
    this.accentColor,
    this.municipalityId,
  });

  final ValueChanged<({double latitude, double longitude})> onChanged;
  final double? initialLatitude;
  final double? initialLongitude;

  /// Municipality anchor used when device GPS is unavailable.
  final double? fallbackLatitude;
  final double? fallbackLongitude;

  /// Try device GPS once when the picker opens.
  final bool autoLocate;

  /// When false, the municipality center only frames the map. The pin is set
  /// after a search, a map tap or drag, Get Location, or Adjust Pin.
  final bool placePinOnFallback;

  /// Coordinates encoded in the already-printed QR (edit mode).
  final double? printedLatitude;
  final double? printedLongitude;

  final Color? accentColor;

  /// Biases place search toward this LGU.
  final String? municipalityId;

  @override
  State<SpotLocationPicker> createState() => _SpotLocationPickerState();
}

class _SpotLocationPickerState extends State<SpotLocationPicker> {
  double? _lat;
  double? _lng;
  bool _busy = false;
  String? _sourceNote;
  final _searchController = TextEditingController();
  final _searchFocus = FocusNode();
  Timer? _searchDebounce;
  List<OsmPlaceHit> _hits = const [];
  bool _searching = false;
  String? _searchMessage;
  int _mapSeek = 0;

  // Editable coordinate controllers & validation state.
  final _latController = TextEditingController();
  final _lngController = TextEditingController();
  String? _latError;
  String? _lngError;
  Timer? _coordDebounce;

  @override
  void initState() {
    super.initState();
    _lat = widget.initialLatitude;
    _lng = widget.initialLongitude;
    if (!_hasValidPin(_lat, _lng) && widget.placePinOnFallback) {
      _lat = widget.fallbackLatitude;
      _lng = widget.fallbackLongitude;
      if (_hasValidPin(_lat, _lng)) {
        _sourceNote = 'Pinned at the municipality center — move it to the spot.';
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) widget.onChanged((latitude: _lat!, longitude: _lng!));
        });
      }
    }
    // Prime coordinate text fields from the initial pin (or blank if not set).
    _latController.text = (_hasValidPin(_lat, _lng)) ? _lat!.toStringAsFixed(6) : '';
    _lngController.text = (_hasValidPin(_lat, _lng)) ? _lng!.toStringAsFixed(6) : '';
    if (widget.autoLocate) _autoLocate();
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _coordDebounce?.cancel();
    _searchController.dispose();
    _searchFocus.dispose();
    _latController.dispose();
    _lngController.dispose();
    super.dispose();
  }

  void _onSearchChanged(String value) {
    _searchDebounce?.cancel();
    final query = value.trim();
    if (query.length < 2) {
      setState(() {
        _hits = const [];
        _searching = false;
        _searchMessage = null;
      });
      return;
    }
    _searchDebounce = Timer(const Duration(milliseconds: 400), () {
      unawaited(_runSearch(query));
    });
  }

  Future<void> _runSearch(String query) async {
    setState(() {
      _searching = true;
      _searchMessage = null;
    });
    final anchor = getMunicipalityAnchorCoordinates(widget.municipalityId ?? '');
    try {
      final hits = await OsmPlaceSearch.search(
        query: query,
        biasLatitude: anchor?.lat ?? _lat ?? widget.fallbackLatitude,
        biasLongitude: anchor?.lng ?? _lng ?? widget.fallbackLongitude,
      );
      if (!mounted || _searchController.text.trim() != query) return;
      final mid = widget.municipalityId?.trim() ?? '';
      final localHits = mid.isEmpty
          ? hits
          : hits
              .where(
                (hit) =>
                    coordinatesOutsideMunicipalityMessage(
                      lat: hit.latitude,
                      lng: hit.longitude,
                      municipalityId: mid,
                    ) ==
                    null,
              )
              .toList();
      setState(() {
        _searching = false;
        _hits = localHits;
        _searchMessage = localHits.isEmpty
            ? (hits.isEmpty
                ? 'No places found. Try a landmark, or move the pin on the map.'
                : 'No matches inside your municipality. Try another name or move the pin.')
            : null;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _searching = false;
        _hits = const [];
        _searchMessage =
            'Location search is unavailable. Use Get Location or move the pin.';
      });
    }
  }

  void _selectHit(OsmPlaceHit hit) {
    _searchFocus.unfocus();
    setState(() {
      _hits = const [];
      _searchMessage = null;
      _searchController.text = hit.label;
    });
    _placePin(
      hit.latitude,
      hit.longitude,
      'Map moved to ${hit.label}. Drag the map to fine-tune the pin.',
    );
  }

  static bool _hasValidPin(double? lat, double? lng) {
    if (lat == null || lng == null) return false;
    return lat.abs() > 1e-6 || lng.abs() > 1e-6;
  }

  // ------------------------------------------------------------------
  // Location helpers
  // ------------------------------------------------------------------

  /// Authoritative setter for all non-user-typing sources (GPS, search, Adjust
  /// Pin, map tap). Increments [_mapSeek] so the map re-centers, and syncs
  /// the editable lat/lng fields.
  void _placePin(double latitude, double longitude, String note) {
    final latStr = latitude.toStringAsFixed(6);
    final lngStr = longitude.toStringAsFixed(6);
    // Sync text controllers only when the value actually changed to avoid
    // disturbing the cursor position unnecessarily.
    if (_latController.text != latStr) _latController.text = latStr;
    if (_lngController.text != lngStr) _lngController.text = lngStr;
    setState(() {
      _lat = latitude;
      _lng = longitude;
      _mapSeek++;
      _sourceNote = note;
      _latError = null;
      _lngError = null;
    });
    widget.onChanged((latitude: latitude, longitude: longitude));
  }

  /// Called when the map pin is dragged / the map is panned. Does NOT
  /// increment [_mapSeek] (map is already there), avoiding a re-center loop.
  void _syncFromMapMove(double latitude, double longitude) {
    final latStr = latitude.toStringAsFixed(6);
    final lngStr = longitude.toStringAsFixed(6);
    if (_latController.text != latStr) _latController.text = latStr;
    if (_lngController.text != lngStr) _lngController.text = lngStr;
    setState(() {
      _lat = latitude;
      _lng = longitude;
      _sourceNote = 'Pin updated. Tourists check in from this point.';
      _latError = null;
      _lngError = null;
    });
    widget.onChanged((latitude: latitude, longitude: longitude));
  }

  // ------------------------------------------------------------------
  // Manual coordinate entry
  // ------------------------------------------------------------------

  void _onCoordChanged() {
    _coordDebounce?.cancel();
    // Wait for the user to pause before parsing — avoids errors while mid-type.
    _coordDebounce = Timer(const Duration(milliseconds: 700), _applyManualCoords);
  }

  void _applyManualCoords() {
    if (!mounted) return;
    final latText = _latController.text.trim().replaceAll(',', '.');
    final lngText = _lngController.text.trim().replaceAll(',', '.');

    String? latErr;
    String? lngErr;
    double? lat;
    double? lng;

    if (latText.isEmpty) {
      latErr = null; // silent — don't nag while field is empty
    } else {
      lat = double.tryParse(latText);
      if (lat == null) {
        latErr = 'Enter a number, e.g. 8.4860';
      } else if (lat < -90 || lat > 90) {
        latErr = 'Latitude must be −90 to 90';
      }
    }

    if (lngText.isEmpty) {
      lngErr = null; // silent
    } else {
      lng = double.tryParse(lngText);
      if (lng == null) {
        lngErr = 'Enter a number, e.g. 123.8048';
      } else if (lng < -180 || lng > 180) {
        lngErr = 'Longitude must be −180 to 180';
      }
    }

    setState(() {
      _latError = latErr;
      _lngError = lngErr;
    });

    // Both fields valid and non-zero: move the map.
    if (latErr == null && lngErr == null && lat != null && lng != null) {
      // Do NOT overwrite the controller text (user is actively typing).
      setState(() {
        _lat = lat;
        _lng = lng;
        _mapSeek++;
        _sourceNote = 'Location set from entered coordinates. '
            'Drag or tap the map to refine.';
      });
      widget.onChanged((latitude: lat, longitude: lng));
    }
  }

  Future<void> _useDeviceGps() async {
    setState(() => _busy = true);
    try {
      final enabled = await Geolocator.isLocationServiceEnabled();
      if (!enabled) {
        _showLocationMessage(
          'Location is turned off. Turn it on, then try Get Location again.',
        );
        return;
      }
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        _showLocationMessage(
          'Location permission was denied. Allow location to drop the pin, or tap the map.',
        );
        return;
      }
      final pos = await Geolocator.getCurrentPosition(
        locationSettings: LocationSettings(
          accuracy: kIsWeb ? LocationAccuracy.medium : LocationAccuracy.high,
          timeLimit: const Duration(seconds: 8),
        ),
      );
      if (!mounted) return;
      _placePin(
        pos.latitude,
        pos.longitude,
        'Pinned at your current location. Drag or tap the map to adjust it.',
      );
    } catch (_) {
      _showLocationMessage(
        'Could not read GPS. Search a place or tap the map to set the pin.',
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _adjustPin() {
    final lat = _hasValidPin(_lat, _lng) ? _lat : widget.fallbackLatitude;
    final lng = _hasValidPin(_lat, _lng) ? _lng : widget.fallbackLongitude;
    if (!_hasValidPin(lat, lng)) {
      _showLocationMessage(
        'Search a place or use Get Location, then drag or tap the map.',
      );
      return;
    }
    _placePin(
      lat!,
      lng!,
      'Drag the map or tap it to move the pin. Latitude and longitude update with the pin.',
    );
  }

  void _showLocationMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
    );
  }

  Future<void> _autoLocate() async {
    await _useDeviceGps();
  }

  double? get _movedMeters {
    final pLat = widget.printedLatitude;
    final pLng = widget.printedLongitude;
    if (!_hasValidPin(pLat, pLng) || !_hasValidPin(_lat, _lng)) return null;
    return Geolocator.distanceBetween(pLat!, pLng!, _lat!, _lng!);
  }

  @override
  Widget build(BuildContext context) {
    final moved = _movedMeters;
    final needsReprint =
        moved != null && moved > kQrScanQrVsFirestoreMaxMismatchMeters;
    final accent = widget.accentColor ?? const Color(0xFFF97316);
    final lat = _lat;
    final lng = _lng;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: _searchController,
          focusNode: _searchFocus,
          onChanged: _onSearchChanged,
          textInputAction: TextInputAction.search,
          decoration: InputDecoration(
            hintText: 'Search tourist spot or location...',
            prefixIcon: Icon(Icons.search_rounded, color: accent),
            suffixIcon: _searching
                ? const Padding(
                    padding: EdgeInsets.all(12),
                    child: SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  )
                : null,
            filled: true,
            fillColor: const Color(0xFFF9FAFB),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: Color(0xFFE5E7EB)),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: Color(0xFFE5E7EB)),
            ),
          ),
        ),
        if (_hits.isNotEmpty)
          Container(
            margin: const EdgeInsets.only(top: 6),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFE5E7EB)),
            ),
            child: Column(
              children: [
                for (final hit in _hits)
                  ListTile(
                    dense: true,
                    leading: Icon(Icons.place_outlined, color: accent),
                    title: Text(hit.label, maxLines: 2, overflow: TextOverflow.ellipsis),
                    onTap: () => _selectHit(hit),
                  ),
              ],
            ),
          )
        else if (_searchMessage != null)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              _searchMessage!,
              style: TextStyle(color: Colors.grey.shade700, fontSize: 12, height: 1.35),
            ),
          ),
        const SizedBox(height: 12),
        if (_hasValidPin(lat, lng) ||
            _hasValidPin(widget.fallbackLatitude, widget.fallbackLongitude))
          ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: SizedBox(
              height: 280,
              width: double.infinity,
              child: _InlineSpotMap(
                seek: _mapSeek,
                latitude: _hasValidPin(lat, lng)
                    ? lat!
                    : widget.fallbackLatitude!,
                longitude: _hasValidPin(lat, lng)
                    ? lng!
                    : widget.fallbackLongitude!,
                showPin: _hasValidPin(lat, lng),
                accent: accent,
                onMoved: (pin) =>
                    _syncFromMapMove(pin.latitude, pin.longitude),
              ),
            ),
          )
        else
          Container(
            height: 160,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: const Color(0xFFFFF7ED),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: accent.withValues(alpha: 0.3)),
            ),
            child: Text(
              'Search a place or use Get Location to drop the pin.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey.shade700),
            ),
          ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _busy ? null : _useDeviceGps,
                icon: _busy
                    ? SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: accent,
                        ),
                      )
                    : Icon(Icons.my_location_rounded, color: accent),
                label: Text(_busy ? 'Getting location…' : 'Get Location'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: accent,
                  side: BorderSide(color: accent.withValues(alpha: 0.55)),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _busy ? null : _adjustPin,
                icon: Icon(Icons.tune_rounded, color: accent),
                label: const Text('Adjust Pin'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: accent,
                  side: BorderSide(color: accent.withValues(alpha: 0.55)),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: TextField(
                controller: _latController,
                keyboardType: const TextInputType.numberWithOptions(
                  signed: true,
                  decimal: true,
                ),
                decoration: InputDecoration(
                  labelText: 'Latitude',
                  hintText: '8.4860',
                  errorText: _latError,
                  filled: true,
                  fillColor: const Color(0xFFF9FAFB),
                  border: const OutlineInputBorder(),
                  enabledBorder: OutlineInputBorder(
                    borderSide: BorderSide(
                      color: _latError != null
                          ? Colors.redAccent
                          : const Color(0xFFE5E7EB),
                    ),
                  ),
                ),
                onChanged: (_) => _onCoordChanged(),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: TextField(
                controller: _lngController,
                keyboardType: const TextInputType.numberWithOptions(
                  signed: true,
                  decimal: true,
                ),
                decoration: InputDecoration(
                  labelText: 'Longitude',
                  hintText: '123.8048',
                  errorText: _lngError,
                  filled: true,
                  fillColor: const Color(0xFFF9FAFB),
                  border: const OutlineInputBorder(),
                  enabledBorder: OutlineInputBorder(
                    borderSide: BorderSide(
                      color: _lngError != null
                          ? Colors.redAccent
                          : const Color(0xFFE5E7EB),
                    ),
                  ),
                ),
                onChanged: (_) => _onCoordChanged(),
              ),
            ),
          ],
        ),
        if (_sourceNote != null) ...[
          const SizedBox(height: 6),
          Text(
            _sourceNote!,
            style: TextStyle(
              fontSize: 11.5,
              height: 1.35,
              color: Colors.grey.shade700,
            ),
          ),
        ],
        if (needsReprint) ...[
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: const Color(0xFFFFF7ED),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: const Color(0xFFFDBA74)),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(
                  Icons.print_rounded,
                  size: 18,
                  color: Color(0xFFC2410C),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Pin moved ${moved.round()} m from the printed QR. '
                    'Re-print and replace the posted QR after saving — '
                    'the old one will be rejected at check-in.',
                    style: const TextStyle(
                      fontSize: 12,
                      height: 1.35,
                      color: Color(0xFF9A3412),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

class _InlineSpotMap extends StatefulWidget {
  const _InlineSpotMap({
    required this.seek,
    required this.latitude,
    required this.longitude,
    required this.showPin,
    required this.accent,
    required this.onMoved,
  });

  final int seek;
  final double latitude;
  final double longitude;
  final bool showPin;
  final Color accent;
  final ValueChanged<({double latitude, double longitude})> onMoved;

  @override
  State<_InlineSpotMap> createState() => _InlineSpotMapState();
}

class _InlineSpotMapState extends State<_InlineSpotMap> {
  final _controller = MapController();
  late int _appliedSeek = widget.seek;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant _InlineSpotMap oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.seek == _appliedSeek) return;
    _appliedSeek = widget.seek;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _controller.move(LatLng(widget.latitude, widget.longitude), 16);
    });
  }

  void _publishCenter() {
    final center = _controller.camera.center;
    widget.onMoved((latitude: center.latitude, longitude: center.longitude));
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        FlutterMap(
          mapController: _controller,
          options: MapOptions(
            initialCenter: LatLng(widget.latitude, widget.longitude),
            initialZoom: 16,
            minZoom: 11,
            maxZoom: 19,
            onTap: (_, point) {
              _controller.move(point, _controller.camera.zoom);
              widget.onMoved((
                latitude: point.latitude,
                longitude: point.longitude,
              ));
            },
            onMapEvent: (event) {
              const userSources = {
                MapEventSource.dragEnd,
                MapEventSource.multiFingerEnd,
                MapEventSource.scrollWheel,
                MapEventSource.doubleTap,
                MapEventSource.flingAnimationController,
                MapEventSource.doubleTapZoomAnimationController,
              };
              if (!userSources.contains(event.source)) return;
              if (event is MapEventMoveEnd ||
                  event is MapEventFlingAnimationEnd ||
                  event is MapEventDoubleTapZoomEnd) {
                _publishCenter();
              }
            },
            interactionOptions: const InteractionOptions(
              flags: InteractiveFlag.all & ~InteractiveFlag.rotate,
            ),
          ),
          children: [
            buildAtmosOsmTileLayer(),
          ],
        ),
        if (widget.showPin)
        IgnorePointer(
          child: Center(
            child: Icon(
              Icons.location_on_rounded,
              color: widget.accent,
              size: 46,
              shadows: const [
                Shadow(
                  color: Colors.black26,
                  blurRadius: 6,
                  offset: Offset(0, 2),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

import 'dart:async';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

import 'package:atmos_trs_system/config/app_theme.dart';
import 'package:atmos_trs_system/services/osm_place_search.dart';
import 'package:atmos_trs_system/utils/municipality_helper.dart';
import 'package:atmos_trs_system/widgets/atmos_osm_tile_layer.dart';
import 'package:atmos_trs_system/widgets/establishment_dash_tokens.dart';

/// Captures establishment map pin via device GPS ("Get location")
/// and lets staff open a map preview to verify the pin.
class EstablishmentLocationCapture extends StatelessWidget {
  const EstablishmentLocationCapture({
    super.key,
    required this.latitude,
    required this.longitude,
    required this.onChanged,
    this.busy = false,
    this.onBusyChanged,
    this.required = true,
    this.accentColor,
    this.dashboardStyle = false,
    this.pinIcon = Icons.hotel_rounded,
    this.emptyPinMessage,
    this.showMapPreview = true,
    this.showStatus = true,
    this.mapHeight = 160,
    this.adjustLatitude,
    this.adjustLongitude,
    this.municipalityId,
  });

  final double? latitude;
  final double? longitude;
  final ValueChanged<({double latitude, double longitude})> onChanged;
  final bool busy;
  final ValueChanged<bool>? onBusyChanged;
  final bool required;
  final Color? accentColor;

  /// Establishment dashboard layout: tinted status row + filled action.
  final bool dashboardStyle;

  /// Icon drawn inside the map pin.
  final IconData pinIcon;

  /// Overrides the "Map pin required / No map pin yet" status text.
  final String? emptyPinMessage;

  /// When false, only the Get location / Adjust pin actions are shown.
  final bool showMapPreview;

  /// When false, the "Pin: lat, lng" line is hidden.
  final bool showStatus;

  final double mapHeight;

  /// Map center for Adjust Pin when a saved pin is not set yet.
  final double? adjustLatitude;
  final double? adjustLongitude;

  /// Biases place search toward this LGU (Misamis Occidental).
  final String? municipalityId;

  String get _emptyText =>
      emptyPinMessage ??
      (required
          ? 'Map pin required — tourists will see you on Explore.'
          : 'No map pin yet.');

  /// Reads the device position without any UI; null when unavailable.
  static Future<({double latitude, double longitude})?>
      readCurrentPosition() async {
    try {
      if (!await Geolocator.isLocationServiceEnabled()) return null;
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        return null;
      }
      final pos = await Geolocator.getCurrentPosition(
        locationSettings: LocationSettings(
          accuracy: kIsWeb ? LocationAccuracy.medium : LocationAccuracy.high,
          timeLimit: const Duration(seconds: 8),
        ),
      );
      return (latitude: pos.latitude, longitude: pos.longitude);
    } catch (_) {
      return null;
    }
  }

  bool get _hasPin {
    final lat = latitude;
    final lng = longitude;
    if (lat == null || lng == null) return false;
    return lat.abs() > 1e-6 || lng.abs() > 1e-6;
  }

  Future<void> _capture(BuildContext context) async {
    onBusyChanged?.call(true);
    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Turn on Location services, then try Get location again.',
              ),
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
        return;
      }
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Allow Location so tourists can find your establishment on the map.',
              ),
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
        return;
      }

      // Medium accuracy + short timeout — laptop GPS is approximate; Adjust pin fine-tunes.
      final pos = await Geolocator.getCurrentPosition(
        locationSettings: LocationSettings(
          accuracy: kIsWeb ? LocationAccuracy.medium : LocationAccuracy.high,
          timeLimit: const Duration(seconds: 8),
        ),
      );
      // Do not save yet — only persist when user taps Save pin here (avoids double writes / 429).
      onBusyChanged?.call(false);
      if (context.mounted) {
        await _openMapPreview(
          context,
          latitude: pos.latitude,
          longitude: pos.longitude,
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Could not get GPS quickly. Use Adjust pin and drag the map instead.',
            ),
            backgroundColor: Colors.red.shade700,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      onBusyChanged?.call(false);
    }
  }

  ({double lat, double lng}) _adjustFallbackCenter() {
    if (_hasPin) return (lat: latitude!, lng: longitude!);
    if (adjustLatitude != null && adjustLongitude != null) {
      return (lat: adjustLatitude!, lng: adjustLongitude!);
    }
    final mid = municipalityId?.trim() ?? '';
    final anchor = mid.isEmpty ? null : getMunicipalityAnchorCoordinates(mid);
    if (anchor != null) return (lat: anchor.lat, lng: anchor.lng);
    return (
      lat: kMisamisOccidentalBiasLat,
      lng: kMisamisOccidentalBiasLng,
    );
  }

  Future<void> _openMapPreview(
    BuildContext context, {
    double? latitude,
    double? longitude,
  }) {
    final fallback = _adjustFallbackCenter();
    final lat = latitude ?? fallback.lat;
    final lng = longitude ?? fallback.lng;
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        final media = MediaQuery.of(ctx);
        final height = media.size.height * 0.88;
        final accent = accentColor ?? AppTheme.brandOrange;
        return Padding(
          padding: EdgeInsets.only(bottom: media.viewInsets.bottom),
          child: SizedBox(
            height: height,
            child: _AdjustPinSheet(
              initialLatitude: lat,
              initialLongitude: lng,
              accent: accent,
              pinIcon: pinIcon,
              municipalityId: municipalityId,
              onSave: (pin) {
                onChanged(pin);
                Navigator.pop(ctx);
              },
              onClose: () => Navigator.pop(ctx),
            ),
          ),
        );
      },
    );
  }

  Widget _pinPreview(
    BuildContext context,
    Color accent,
    double lat,
    double lng,
  ) {
    return GestureDetector(
      onTap: () => _openMapPreview(
        context,
        latitude: lat,
        longitude: lng,
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: SizedBox(
          height: mapHeight,
          width: double.infinity,
          child: LayoutBuilder(
            builder: (context, constraints) {
              final width = constraints.maxWidth;
              final height = constraints.maxHeight;
              if (!width.isFinite ||
                  !height.isFinite ||
                  width < 8 ||
                  height < 8) {
                return const ColoredBox(color: Color(0xFFF1F5F9));
              }
              return Stack(
            fit: StackFit.expand,
            children: [
              IgnorePointer(
                child: _EstablishmentPinMap(
                  latitude: lat,
                  longitude: lng,
                  accent: accent,
                  pinIcon: pinIcon,
                  interactive: false,
                ),
              ),
              Positioned(
                right: 8,
                bottom: 8,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.95),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: accent.withValues(alpha: 0.35),
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.open_in_full_rounded, size: 14, color: accent),
                      const SizedBox(width: 4),
                      Text(
                        'Adjust pin',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: accent,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _dashboardLayout(BuildContext context, Color accent) {
    final lat = latitude;
    final lng = longitude;
    final status = Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF7ED),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFFED7AA)),
      ),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: accent.withValues(alpha: 0.14),
              shape: BoxShape.circle,
            ),
            child: Icon(Icons.location_on_rounded, color: accent, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              _hasPin
                  ? 'Pin: ${lat!.toStringAsFixed(5)}, ${lng!.toStringAsFixed(5)}'
                  : _emptyText,
              style: TextStyle(
                fontSize: 13.5,
                fontWeight: FontWeight.w600,
                color: _hasPin
                    ? const Color(0xFF334155)
                    : const Color(0xFFC2410C),
              ),
            ),
          ),
        ],
      ),
    );
    final getButton = FilledButton.icon(
      onPressed: busy ? null : () => _capture(context),
      icon: busy
          ? const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: Colors.white,
              ),
            )
          : const Icon(Icons.my_location_rounded, size: 19),
      label: Text(busy ? 'Getting location…' : 'Get location'),
      style: FilledButton.styleFrom(
        backgroundColor: accent,
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 18),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        textStyle: AeDashTokens.body(
          size: 13.5,
          color: Colors.white,
          weight: FontWeight.w700,
        ),
      ),
    );
    final adjustButton = OutlinedButton.icon(
      onPressed: () => _openMapPreview(
        context,
        latitude: _hasPin ? lat : null,
        longitude: _hasPin ? lng : null,
      ),
      icon: Icon(Icons.tune_rounded, color: accent, size: 19),
      label: Text(_hasPin ? 'Adjust pin' : 'Set map pin'),
      style: OutlinedButton.styleFrom(
        foregroundColor: accent,
        side: BorderSide(color: accent.withValues(alpha: 0.55)),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 18),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
      ),
    );
    return LayoutBuilder(
      builder: (context, c) {
        final narrow = c.maxWidth < 560;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (narrow) ...[
              status,
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(child: getButton),
                  const SizedBox(width: 8),
                  Expanded(child: adjustButton),
                ],
              ),
            ] else
              Row(
                children: [
                  Expanded(child: status),
                  const SizedBox(width: 12),
                  getButton,
                  const SizedBox(width: 8),
                  adjustButton,
                ],
              ),
            if (_hasPin) ...[
              const SizedBox(height: 12),
              _pinPreview(context, accent, lat!, lng!),
            ],
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final accent = accentColor ?? AppTheme.brandOrange;
    if (dashboardStyle) return _dashboardLayout(context, accent);
    final lat = latitude;
    final lng = longitude;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (showStatus)
          Text(
            _hasPin
                ? 'Pin: ${lat!.toStringAsFixed(5)}, ${lng!.toStringAsFixed(5)}'
                : _emptyText,
            style: TextStyle(
              fontSize: 13,
              height: 1.35,
              color: _hasPin ? const Color(0xFF334155) : Colors.red.shade700,
              fontWeight: FontWeight.w600,
            ),
          ),
        if (showMapPreview && _hasPin) ...[
          if (showStatus) const SizedBox(height: 10),
          _pinPreview(context, accent, lat!, lng!),
        ],
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: busy ? null : () => _capture(context),
                icon: busy
                    ? SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: accent,
                        ),
                      )
                    : Icon(Icons.my_location_rounded, color: accent),
                label: Text(busy ? 'Getting location…' : 'Get Location'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: accent,
                  side: BorderSide(color: accent.withValues(alpha: 0.55)),
                  padding:
                      const EdgeInsets.symmetric(vertical: 14, horizontal: 12),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () => _openMapPreview(
                  context,
                  latitude: _hasPin ? lat : null,
                  longitude: _hasPin ? lng : null,
                ),
                icon: Icon(Icons.tune_rounded, color: accent),
                label: Text(_hasPin ? 'Adjust Pin' : 'Set Map Pin'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: accent,
                  side: BorderSide(color: accent.withValues(alpha: 0.55)),
                  padding: const EdgeInsets.symmetric(
                    vertical: 14,
                    horizontal: 12,
                  ),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _AdjustPinSheet extends StatefulWidget {
  const _AdjustPinSheet({
    required this.initialLatitude,
    required this.initialLongitude,
    required this.accent,
    required this.pinIcon,
    required this.onSave,
    required this.onClose,
    this.municipalityId,
  });

  final double initialLatitude;
  final double initialLongitude;
  final Color accent;
  final IconData pinIcon;
  final ValueChanged<({double latitude, double longitude})> onSave;
  final VoidCallback onClose;
  final String? municipalityId;

  @override
  State<_AdjustPinSheet> createState() => _AdjustPinSheetState();
}

class _AdjustPinSheetState extends State<_AdjustPinSheet> {
  late double _lat = widget.initialLatitude;
  late double _lng = widget.initialLongitude;
  final _mapController = MapController();

  final _searchController = TextEditingController();
  final _searchFocus = FocusNode();
  Timer? _searchDebounce;
  List<OsmPlaceHit> _hits = const [];
  bool _searching = false;
  String? _searchMessage;

  final _latController = TextEditingController();
  final _lngController = TextEditingController();
  String? _latError;
  String? _lngError;
  Timer? _coordDebounce;
  bool _locating = false;
  bool _syncingCoordsFromMap = false;

  @override
  void initState() {
    super.initState();
    _latController.text = _lat.toStringAsFixed(6);
    _lngController.text = _lng.toStringAsFixed(6);
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _coordDebounce?.cancel();
    _searchController.dispose();
    _searchFocus.dispose();
    _latController.dispose();
    _lngController.dispose();
    _mapController.dispose();
    super.dispose();
  }

  void _syncCoordFields(double lat, double lng) {
    final latStr = lat.toStringAsFixed(6);
    final lngStr = lng.toStringAsFixed(6);
    _syncingCoordsFromMap = true;
    if (_latController.text != latStr) _latController.text = latStr;
    if (_lngController.text != lngStr) _lngController.text = lngStr;
    _syncingCoordsFromMap = false;
  }

  void _moveMapTo(double lat, double lng, {double zoom = 17}) {
    _mapController.move(LatLng(lat, lng), zoom);
    setState(() {
      _lat = lat;
      _lng = lng;
      _latError = null;
      _lngError = null;
    });
    _syncCoordFields(lat, lng);
  }

  void _onMapEvent(MapEvent event) {
    if (event is! MapEventMoveEnd &&
        event is! MapEventFlingAnimationEnd &&
        event is! MapEventDoubleTapZoomEnd) {
      return;
    }
    final c = _mapController.camera.center;
    setState(() {
      _lat = c.latitude;
      _lng = c.longitude;
      _latError = null;
      _lngError = null;
    });
    _syncCoordFields(c.latitude, c.longitude);
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
    _searchDebounce = Timer(const Duration(milliseconds: 450), () {
      unawaited(_runSearch(query));
    });
  }

  Future<void> _runSearch(String query) async {
    setState(() {
      _searching = true;
      _searchMessage = null;
    });
    final mid = widget.municipalityId?.trim() ?? '';
    final anchor = mid.isEmpty ? null : getMunicipalityAnchorCoordinates(mid);
    try {
      final hits = await OsmPlaceSearch.search(
        query: query,
        biasLatitude: anchor?.lat ?? _lat,
        biasLongitude: anchor?.lng ?? _lng,
        preferMisamisOccidental: true,
      );
      if (!mounted || _searchController.text.trim() != query) return;
      setState(() {
        _searching = false;
        _hits = hits;
        _searchMessage = hits.isEmpty
            ? 'No establishment found. Try another name, or move the pin on the map.'
            : null;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _searching = false;
        _hits = const [];
        _searchMessage =
            'Location search is unavailable. Enter coordinates or move the pin.';
      });
    }
  }

  void _selectHit(OsmPlaceHit hit) {
    _searchFocus.unfocus();
    setState(() {
      _hits = const [];
      _searchMessage = null;
      _searchController.text = hit.name.isNotEmpty ? hit.name : hit.label;
    });
    // Preview only — not saved until Save Location.
    _moveMapTo(hit.latitude, hit.longitude, zoom: 17.5);
  }

  void _onCoordChanged() {
    if (_syncingCoordsFromMap) return;
    _coordDebounce?.cancel();
    _coordDebounce =
        Timer(const Duration(milliseconds: 700), _applyManualCoords);
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
      latErr = 'Latitude is required';
    } else {
      lat = double.tryParse(latText);
      if (lat == null) {
        latErr = 'Enter a number, e.g. 8.486012';
      } else if (lat < -90 || lat > 90) {
        latErr = 'Latitude must be −90 to 90';
      }
    }

    if (lngText.isEmpty) {
      lngErr = 'Longitude is required';
    } else {
      lng = double.tryParse(lngText);
      if (lng == null) {
        lngErr = 'Enter a number, e.g. 123.804812';
      } else if (lng < -180 || lng > 180) {
        lngErr = 'Longitude must be −180 to 180';
      }
    }

    setState(() {
      _latError = latErr;
      _lngError = lngErr;
    });

    if (latErr == null && lngErr == null && lat != null && lng != null) {
      _mapController.move(LatLng(lat, lng), _mapController.camera.zoom);
      setState(() {
        _lat = lat!;
        _lng = lng!;
      });
    }
  }

  bool _coordsAreValid(double lat, double lng) {
    if (lat < -90 || lat > 90 || lng < -180 || lng > 180) return false;
    if (lat.abs() < 1e-6 && lng.abs() < 1e-6) return false;
    return true;
  }

  void _trySave() {
    // Prefer typed values if valid; otherwise map center.
    final latText = _latController.text.trim().replaceAll(',', '.');
    final lngText = _lngController.text.trim().replaceAll(',', '.');
    final typedLat = double.tryParse(latText);
    final typedLng = double.tryParse(lngText);

    String? latErr;
    String? lngErr;
    var lat = _lat;
    var lng = _lng;

    if (latText.isNotEmpty || lngText.isNotEmpty) {
      if (typedLat == null) {
        latErr = 'Enter a valid latitude';
      } else if (typedLat < -90 || typedLat > 90) {
        latErr = 'Latitude must be −90 to 90';
      } else {
        lat = typedLat;
      }
      if (typedLng == null) {
        lngErr = 'Enter a valid longitude';
      } else if (typedLng < -180 || typedLng > 180) {
        lngErr = 'Longitude must be −180 to 180';
      } else {
        lng = typedLng;
      }
    }

    if (!_coordsAreValid(lat, lng)) {
      latErr ??= 'Invalid coordinates';
      lngErr ??= 'Invalid coordinates';
    }

    if (latErr != null || lngErr != null) {
      setState(() {
        _latError = latErr;
        _lngError = lngErr;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Fix latitude and longitude before saving.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    widget.onSave((latitude: lat, longitude: lng));
  }

  Future<void> _getDeviceLocation() async {
    setState(() => _locating = true);
    try {
      final enabled = await Geolocator.isLocationServiceEnabled();
      if (!enabled) {
        _snack('Turn on Location services, then try Get Location again.');
        return;
      }
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        _snack(
          'Location permission denied. Search your establishment or enter coordinates.',
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
      _moveMapTo(pos.latitude, pos.longitude, zoom: 17);
      _snack(
        'Device location set as a preview. Drag the map if the entrance differs.',
      );
    } catch (_) {
      _snack('Could not read GPS. Search a place or enter coordinates.');
    } finally {
      if (mounted) setState(() => _locating = false);
    }
  }

  void _snack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
    );
  }

  InputDecoration _coordDecoration({
    required String label,
    required String hint,
    String? errorText,
  }) {
    return InputDecoration(
      labelText: label,
      hintText: hint,
      errorText: errorText,
      isDense: true,
      filled: true,
      fillColor: const Color(0xFFFFF7ED),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(
          color: errorText != null
              ? Colors.redAccent
              : widget.accent.withValues(alpha: 0.35),
        ),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: widget.accent, width: 1.4),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 10),
        Center(
          child: Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.grey.shade300,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 8, 4),
          child: Row(
            children: [
              Icon(Icons.location_on_rounded, color: widget.accent),
              const SizedBox(width: 10),
              const Expanded(
                child: Text(
                  'Adjust map pin',
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF111827),
                  ),
                ),
              ),
              IconButton(
                onPressed: widget.onClose,
                icon: const Icon(Icons.close_rounded),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: Text(
            'Search your establishment or move the map to adjust the pin.',
            style: TextStyle(
              fontSize: 13,
              height: 1.35,
              color: Colors.grey.shade700,
            ),
          ),
        ),
        // —— Search Location ——
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
          child: TextField(
            controller: _searchController,
            focusNode: _searchFocus,
            onChanged: _onSearchChanged,
            textInputAction: TextInputAction.search,
            decoration: InputDecoration(
              hintText: 'Search hotel, resort, or establishment...',
              prefixIcon: Icon(Icons.search_rounded, color: widget.accent),
              suffixIcon: _searching
                  ? const Padding(
                      padding: EdgeInsets.all(12),
                      child: SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    )
                  : (_searchController.text.isEmpty
                      ? null
                      : IconButton(
                          icon: const Icon(Icons.clear_rounded, size: 18),
                          onPressed: () {
                            _searchController.clear();
                            setState(() {
                              _hits = const [];
                              _searchMessage = null;
                              _searching = false;
                            });
                          },
                        )),
              filled: true,
              fillColor: const Color(0xFFFFF7ED),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(
                  color: widget.accent.withValues(alpha: 0.35),
                ),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(
                  color: widget.accent.withValues(alpha: 0.35),
                ),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: widget.accent, width: 1.4),
              ),
            ),
          ),
        ),
        if (_hits.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 6, 16, 0),
            child: Material(
              elevation: 3,
              borderRadius: BorderRadius.circular(12),
              color: Colors.white,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 168),
                child: ListView.separated(
                  shrinkWrap: true,
                  padding: EdgeInsets.zero,
                  itemCount: _hits.length,
                  separatorBuilder: (_, __) =>
                      const Divider(height: 1, color: Color(0xFFE5E7EB)),
                  itemBuilder: (context, i) {
                    final hit = _hits[i];
                    return ListTile(
                      dense: true,
                      leading: Icon(Icons.hotel_rounded, color: widget.accent),
                      title: Text(
                        hit.name.isNotEmpty ? hit.name : hit.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 13.5,
                        ),
                      ),
                      subtitle: hit.address.isEmpty
                          ? null
                          : Text(
                              hit.address,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 11.5,
                                color: Colors.grey.shade700,
                              ),
                            ),
                      onTap: () => _selectHit(hit),
                    );
                  },
                ),
              ),
            ),
          )
        else if (_searchMessage != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 6, 16, 0),
            child: Text(
              _searchMessage!,
              style: TextStyle(
                color: Colors.grey.shade700,
                fontSize: 12,
                height: 1.35,
              ),
            ),
          ),
        const SizedBox(height: 8),
        // —— Interactive Map ——
        Expanded(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  FlutterMap(
                    mapController: _mapController,
                    options: MapOptions(
                      initialCenter: LatLng(
                        widget.initialLatitude,
                        widget.initialLongitude,
                      ),
                      initialZoom: 17,
                      minZoom: 12,
                      maxZoom: 19,
                      onMapEvent: _onMapEvent,
                      interactionOptions: const InteractionOptions(
                        flags: InteractiveFlag.all & ~InteractiveFlag.rotate,
                      ),
                    ),
                    children: [
                      buildAtmosOsmTileLayer(),
                    ],
                  ),
                  IgnorePointer(
                    child: Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 48,
                            height: 48,
                            decoration: BoxDecoration(
                              color: widget.accent,
                              shape: BoxShape.circle,
                              border:
                                  Border.all(color: Colors.white, width: 2.5),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.3),
                                  blurRadius: 8,
                                  offset: const Offset(0, 3),
                                ),
                              ],
                            ),
                            child: Icon(
                              widget.pinIcon,
                              color: Colors.white,
                              size: 24,
                            ),
                          ),
                          Container(
                            width: 3,
                            height: 10,
                            color: widget.accent,
                          ),
                        ],
                      ),
                    ),
                  ),
                  Positioned(
                    right: 10,
                    bottom: 10,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _MiniZoomBtn(
                          icon: Icons.add,
                          onTap: () {
                            final z = (_mapController.camera.zoom + 1)
                                .clamp(12.0, 19.0);
                            _mapController.move(
                              _mapController.camera.center,
                              z,
                            );
                          },
                        ),
                        const SizedBox(height: 6),
                        _MiniZoomBtn(
                          icon: Icons.remove,
                          onTap: () {
                            final z = (_mapController.camera.zoom - 1)
                                .clamp(12.0, 19.0);
                            _mapController.move(
                              _mapController.camera.center,
                              z,
                            );
                          },
                        ),
                        const SizedBox(height: 6),
                        _MiniZoomBtn(
                          icon: Icons.my_location,
                          onTap: _locating ? () {} : _getDeviceLocation,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        // —— Latitude / Longitude ——
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: TextField(
                  controller: _latController,
                  keyboardType: const TextInputType.numberWithOptions(
                    signed: true,
                    decimal: true,
                  ),
                  decoration: _coordDecoration(
                    label: 'Latitude',
                    hint: '8.486012',
                    errorText: _latError,
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
                  decoration: _coordDecoration(
                    label: 'Longitude',
                    hint: '123.804812',
                    errorText: _lngError,
                  ),
                  onChanged: (_) => _onCoordChanged(),
                ),
              ),
            ],
          ),
        ),
        // —— Get Location / Save Location ——
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _locating ? null : _getDeviceLocation,
                  icon: _locating
                      ? SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: widget.accent,
                          ),
                        )
                      : Icon(Icons.my_location_rounded, color: widget.accent),
                  label: Text(_locating ? 'Getting…' : 'Get Location'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: widget.accent,
                    side: BorderSide(
                      color: widget.accent.withValues(alpha: 0.55),
                    ),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                flex: 2,
                child: FilledButton.icon(
                  onPressed: _trySave,
                  icon: const Icon(Icons.check_rounded),
                  label: const Text('Save Location'),
                  style: FilledButton.styleFrom(
                    backgroundColor: widget.accent,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _EstablishmentPinMap extends StatefulWidget {
  const _EstablishmentPinMap({
    required this.latitude,
    required this.longitude,
    required this.accent,
    this.pinIcon = Icons.hotel_rounded,
    this.interactive = true,
    this.showZoomControls = false,
  });

  final double latitude;
  final double longitude;
  final Color accent;
  final IconData pinIcon;
  final bool interactive;
  final bool showZoomControls;

  @override
  State<_EstablishmentPinMap> createState() => _EstablishmentPinMapState();
}

class _EstablishmentPinMapState extends State<_EstablishmentPinMap> {
  late final MapController _controller = MapController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final center = LatLng(widget.latitude, widget.longitude);
    return Stack(
      fit: StackFit.expand,
      children: [
        FlutterMap(
          mapController: _controller,
          options: MapOptions(
            initialCenter: center,
            initialZoom: 16.5,
            minZoom: 10,
            maxZoom: 19,
            interactionOptions: InteractionOptions(
              flags: widget.interactive
                  ? (InteractiveFlag.all & ~InteractiveFlag.rotate)
                  : InteractiveFlag.none,
            ),
          ),
          children: [
            buildAtmosOsmTileLayer(),
            MarkerLayer(
              markers: [
                Marker(
                  point: center,
                  width: 44,
                  height: 44,
                  child: Container(
                    decoration: BoxDecoration(
                      color: widget.accent,
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 2.5),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.28),
                          blurRadius: 6,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Icon(
                      widget.pinIcon,
                      color: Colors.white,
                      size: 22,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
        if (widget.showZoomControls)
          Positioned(
            right: 10,
            bottom: 10,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _MiniZoomBtn(
                  icon: Icons.add,
                  onTap: () {
                    final z =
                        (_controller.camera.zoom + 1).clamp(10.0, 19.0);
                    _controller.move(_controller.camera.center, z);
                  },
                ),
                const SizedBox(height: 6),
                _MiniZoomBtn(
                  icon: Icons.remove,
                  onTap: () {
                    final z =
                        (_controller.camera.zoom - 1).clamp(10.0, 19.0);
                    _controller.move(_controller.camera.center, z);
                  },
                ),
                const SizedBox(height: 6),
                _MiniZoomBtn(
                  icon: Icons.my_location,
                  onTap: () => _controller.move(center, 16.5),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _MiniZoomBtn extends StatelessWidget {
  const _MiniZoomBtn({required this.icon, required this.onTap});

  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(8),
      elevation: 2,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: SizedBox(
          width: 36,
          height: 36,
          child: Icon(icon, size: 20, color: const Color(0xFF1F2937)),
        ),
      ),
    );
  }
}

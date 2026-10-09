import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';

import 'package:atmos_trs_system/config/qr_scan_geofence_config.dart';
import 'package:atmos_trs_system/widgets/establishment_location_capture.dart';

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
    this.printedLatitude,
    this.printedLongitude,
    this.accentColor,
  });

  final ValueChanged<({double latitude, double longitude})> onChanged;
  final double? initialLatitude;
  final double? initialLongitude;

  /// Municipality anchor used when device GPS is unavailable.
  final double? fallbackLatitude;
  final double? fallbackLongitude;

  /// Try device GPS once when the picker opens.
  final bool autoLocate;

  /// Coordinates encoded in the already-printed QR (edit mode).
  final double? printedLatitude;
  final double? printedLongitude;

  final Color? accentColor;

  @override
  State<SpotLocationPicker> createState() => _SpotLocationPickerState();
}

class _SpotLocationPickerState extends State<SpotLocationPicker> {
  double? _lat;
  double? _lng;
  bool _busy = false;
  String? _sourceNote;

  @override
  void initState() {
    super.initState();
    _lat = widget.initialLatitude;
    _lng = widget.initialLongitude;
    if (!_hasValidPin(_lat, _lng)) {
      _lat = widget.fallbackLatitude;
      _lng = widget.fallbackLongitude;
      if (_hasValidPin(_lat, _lng)) {
        _sourceNote = 'Pinned at the municipality center — move it to the spot.';
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) widget.onChanged((latitude: _lat!, longitude: _lng!));
        });
      }
    }
    if (widget.autoLocate) _autoLocate();
  }

  static bool _hasValidPin(double? lat, double? lng) {
    if (lat == null || lng == null) return false;
    return lat.abs() > 1e-6 || lng.abs() > 1e-6;
  }

  Future<void> _autoLocate() async {
    setState(() => _busy = true);
    final pos = await EstablishmentLocationCapture.readCurrentPosition();
    if (!mounted) return;
    setState(() {
      _busy = false;
      if (pos != null) {
        _lat = pos.latitude;
        _lng = pos.longitude;
        _sourceNote =
            'Pinned at your current location — use Adjust pin if the QR is posted elsewhere.';
      } else if (_hasValidPin(_lat, _lng)) {
        _sourceNote ??=
            'Could not read GPS. Drag the pin to where the QR is posted.';
      }
    });
    if (pos != null) widget.onChanged(pos);
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        EstablishmentLocationCapture(
          latitude: _lat,
          longitude: _lng,
          busy: _busy,
          onBusyChanged: (b) => setState(() => _busy = b),
          accentColor: widget.accentColor,
          pinIcon: Icons.place_rounded,
          emptyPinMessage:
              'Map pin required — tourists check in within '
              '${kQrScanSpotMaxDistanceMeters.round()} m of this point.',
          onChanged: (pin) {
            setState(() {
              _lat = pin.latitude;
              _lng = pin.longitude;
              _sourceNote = null;
            });
            widget.onChanged(pin);
          },
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

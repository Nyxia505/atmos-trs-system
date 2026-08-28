import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:geolocator/geolocator.dart';
import 'package:url_launcher/url_launcher.dart';

/// Opens Google Maps turn-by-turn directions (origin → destination, route options).
class MapsDirectionsLauncher {
  MapsDirectionsLauncher._();

  /// Default tourist starting point when GPS is unavailable (Misamis Occidental).
  static const String defaultOriginLabel =
      'Oroquieta City, Misamis Occidental';

  /// [travelMode]: `driving`, `walking`, `bicycling`, `transit`, or `two_wheeler`.
  static Future<void> open({
    required String destinationLabel,
    double? destinationLatitude,
    double? destinationLongitude,
    String? originLabel,
    double? originLatitude,
    double? originLongitude,
    String travelMode = 'driving',
  }) async {
    final destination = _formatDestination(
      label: destinationLabel,
      latitude: destinationLatitude,
      longitude: destinationLongitude,
    );
    if (destination.isEmpty) return;

    final origin = await _resolveOrigin(
      label: originLabel,
      latitude: originLatitude,
      longitude: originLongitude,
    );

    final uri = Uri.https(
      'www.google.com',
      '/maps/dir/',
      <String, String>{
        'api': '1',
        'origin': origin,
        'destination': destination,
        'travelmode': travelMode,
      },
    );

    final launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!launched) {
      // Path-style fallback (works in some browsers).
      final fallback = Uri.parse(
        'https://www.google.com/maps/dir/'
        '${Uri.encodeComponent(origin)}/'
        '${Uri.encodeComponent(destination)}',
      );
      await launchUrl(fallback, mode: LaunchMode.externalApplication);
    }
  }

  static String _formatDestination({
    required String label,
    double? latitude,
    double? longitude,
  }) {
    final trimmed = label.trim();
    if (trimmed.isNotEmpty) return trimmed;
    if (latitude != null &&
        longitude != null &&
        (latitude.abs() > 1e-6 || longitude.abs() > 1e-6)) {
      return '$latitude,$longitude';
    }
    return '';
  }

  static Future<String> _resolveOrigin({
    String? label,
    double? latitude,
    double? longitude,
  }) async {
    if (latitude != null &&
        longitude != null &&
        (latitude.abs() > 1e-6 || longitude.abs() > 1e-6)) {
      return '$latitude,$longitude';
    }
    final trimmed = label?.trim() ?? '';
    if (trimmed.isNotEmpty) return trimmed;

    final pos = await _tryCurrentPosition();
    if (pos != null) {
      return '${pos.latitude},${pos.longitude}';
    }
    return defaultOriginLabel;
  }

  static Future<Position?> _tryCurrentPosition() async {
    if (kIsWeb) {
      // Geolocator on web still needs permission; best-effort only.
    }
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
      return await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.medium,
          timeLimit: Duration(seconds: 8),
        ),
      );
    } catch (_) {
      return null;
    }
  }

  /// Builds a Google-friendly place label, e.g. "Camp Sawi, Baliangao–Calamba Road".
  static String placeLabel({
    required String name,
    String? address,
    String? municipality,
  }) {
    final parts = <String>[
      name.trim(),
      if (address != null && address.trim().isNotEmpty) address.trim(),
      if (municipality != null &&
          municipality.trim().isNotEmpty &&
          !(address ?? '').toLowerCase().contains(municipality.toLowerCase()))
        municipality.trim(),
    ].where((s) => s.isNotEmpty);
    return parts.join(', ');
  }
}

import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

/// Colored teardrop pins for Google Maps (web ignores [BitmapDescriptor.defaultMarkerWithHue]).
class GoogleMapPinIcons {
  GoogleMapPinIcons._();

  static final Map<String, BitmapDescriptor> _cache = {};

  static const Color busTerminalColor = Color(0xFF1565C0);
  static const Color busStopColor = Color(0xFF7B1FA2);
  static const Color touristSpotColor = Color(0xFFE65100);
  static const Color routeStartFallback = Color(0xFFD32F2F);
  static const Color routeEndFallback = Color(0xFF388E3C);

  static Future<BitmapDescriptor> busTerminal() =>
      _teardropPin(busTerminalColor, 'terminal');

  static Future<BitmapDescriptor> busStop() =>
      _teardropPin(busStopColor, 'stop');

  static Future<BitmapDescriptor> touristSpot() =>
      _teardropPin(touristSpotColor, 'spot');

  static Future<BitmapDescriptor> routeStart() =>
      _teardropPin(routeStartFallback, 'start');

  static Future<BitmapDescriptor> routeEnd() =>
      _teardropPin(routeEndFallback, 'end');

  static Future<BitmapDescriptor> forBusKind(String kind) {
    return kind == 'stop' ? busStop() : busTerminal();
  }

  static Future<BitmapDescriptor> _teardropPin(Color color, String key) async {
    final cacheKey = '${color.toARGB32()}_$key';
    final cached = _cache[cacheKey];
    if (cached != null) return cached;

    const double w = 44;
    const double h = 56;
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);

    final fill = Paint()..color = color;
    final headCenter = Offset(w / 2, 16);

    canvas.drawCircle(headCenter, 14, fill);

    final tail = Path()
      ..moveTo(w / 2, h - 2)
      ..lineTo(w / 2 - 11, 28)
      ..lineTo(w / 2 + 11, 28)
      ..close();
    canvas.drawPath(tail, fill);

    canvas.drawCircle(
      headCenter,
      5,
      Paint()..color = Colors.white.withValues(alpha: 0.95),
    );

    final picture = recorder.endRecording();
    final image = await picture.toImage(w.ceil(), h.ceil());
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    if (bytes == null) {
      return BitmapDescriptor.defaultMarker;
    }

    final descriptor = BitmapDescriptor.bytes(
      bytes.buffer.asUint8List(),
      width: w,
      height: h,
    );
    _cache[cacheKey] = descriptor;
    return descriptor;
  }
}

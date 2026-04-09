import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';

/// Renders [qrData] to PNG bytes (for PDFs and file download).
Future<Uint8List?> qrDataToPngBytes(String qrData, {int size = 200}) async {
  try {
    final painter = QrPainter(
      data: qrData,
      version: QrVersions.auto,
      gapless: true,
      color: const Color(0xFF000000),
      emptyColor: const Color(0xFFFFFFFF),
    );
    final byteData = await painter.toImageData(size.toDouble());
    return byteData?.buffer.asUint8List();
  } catch (_) {
    return null;
  }
}

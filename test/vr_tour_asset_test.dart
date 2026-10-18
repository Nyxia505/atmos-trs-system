import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('Experience mockups are bundled PNGs', () async {
    for (final path in [
      'assets/mockup/vr tour.png',
      'assets/mockup/Trip planner.png',
    ]) {
      final data = await rootBundle.load(path);
      final bytes = data.buffer.asUint8List(
        data.offsetInBytes,
        data.lengthInBytes,
      );
      expect(bytes.length, greaterThan(1000), reason: path);
      expect(bytes[0], 0x89, reason: path);
      expect(bytes[1], 0x50, reason: path);
    }
  });
}

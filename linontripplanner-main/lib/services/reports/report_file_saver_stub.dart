import 'dart:typed_data';

/// Fallback for platforms with neither `dart:io` nor a browser.
Future<String> saveReportFile({
  required String fileName,
  required Uint8List bytes,
  required String mimeType,
}) {
  throw UnsupportedError(
    'Saving report files is not supported on this platform.',
  );
}

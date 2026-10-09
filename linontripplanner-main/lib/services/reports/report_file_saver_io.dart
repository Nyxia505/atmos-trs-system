import 'dart:io';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';

/// Writes the report into the platform Downloads folder, falling back to the
/// app documents directory on platforms that have no Downloads concept
/// (Android, iOS).
Future<String> saveReportFile({
  required String fileName,
  required Uint8List bytes,
  required String mimeType,
}) async {
  Directory? target;
  try {
    target = await getDownloadsDirectory();
  } on UnsupportedError {
    target = null;
  } catch (_) {
    target = null;
  }
  target ??= await getApplicationDocumentsDirectory();

  if (!await target.exists()) {
    await target.create(recursive: true);
  }

  final file = File('${target.path}${Platform.pathSeparator}$fileName');
  await file.writeAsBytes(bytes, flush: true);
  return file.path;
}

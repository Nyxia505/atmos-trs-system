import 'dart:io';

import 'package:path_provider/path_provider.dart';

/// Writes [bytes] and opens them with the OS default app (Excel, PDF viewer).
Future<void> saveAndOpenFile(
  String filename,
  List<int> bytes, {
  required String mimeType,
}) async {
  Directory dir;
  try {
    dir = await getDownloadsDirectory() ?? await getTemporaryDirectory();
  } catch (_) {
    dir = await getTemporaryDirectory();
  }
  final safeName = filename.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
  final file = File('${dir.path}${Platform.pathSeparator}$safeName');
  await file.writeAsBytes(bytes, flush: true);
  if (Platform.isWindows) {
    await Process.run('cmd', ['/c', 'start', '', file.path]);
    return;
  }
  if (Platform.isMacOS) {
    await Process.run('open', [file.path]);
    return;
  }
  if (Platform.isLinux) {
    await Process.run('xdg-open', [file.path]);
  }
}

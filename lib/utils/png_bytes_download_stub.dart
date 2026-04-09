import 'dart:io';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

/// Mobile/desktop: share PNG via system sheet (user can save to Files/Photos).
Future<void> downloadPngFile(String filename, Uint8List bytes) async {
  final dir = await getTemporaryDirectory();
  final path = '${dir.path}/$filename';
  await File(path).writeAsBytes(bytes);
  await SharePlus.instance.share(
    ShareParams(
      files: [XFile(path)],
      text: 'LGU QR code',
    ),
  );
}

import 'dart:typed_data';

import 'package:cross_file/cross_file.dart';
import 'package:share_plus/share_plus.dart';

/// Non-web: share XLSX bytes via the system share sheet.
Future<void> downloadXlsxFile(String filename, List<int> bytes) async {
  final file = XFile.fromData(
    Uint8List.fromList(bytes),
    mimeType:
        'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
    name: filename,
  );
  await Share.shareXFiles([file], text: 'DOT VAR 2 report');
}

bool get xlsxDownloadUsesShareSheet => true;

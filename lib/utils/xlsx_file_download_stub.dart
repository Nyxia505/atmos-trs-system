import 'dart:typed_data';

import 'package:atmos_trs_system/utils/save_and_open_file_stub.dart';
import 'package:cross_file/cross_file.dart';
import 'package:share_plus/share_plus.dart';

/// Non-web: share XLSX bytes via the system share sheet, or open locally.
Future<void> downloadXlsxFile(
  String filename,
  List<int> bytes, {
  bool openAfterDownload = false,
}) async {
  const mime =
      'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet';
  if (openAfterDownload) {
    await saveAndOpenFile(filename, bytes, mimeType: mime);
    return;
  }
  final file = XFile.fromData(
    Uint8List.fromList(bytes),
    mimeType: mime,
    name: filename,
  );
  await Share.shareXFiles([file], text: 'DOT VAR 2 report');
}

bool get xlsxDownloadUsesShareSheet => true;

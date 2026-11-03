import 'dart:typed_data';

import 'package:atmos_trs_system/utils/save_and_open_file_stub.dart';
import 'package:cross_file/cross_file.dart';
import 'package:share_plus/share_plus.dart';

/// Non-web: share PDF bytes via the system share sheet, or open locally.
Future<void> downloadPdfFile(
  String filename,
  List<int> bytes, {
  bool openAfterDownload = false,
}) async {
  const mime = 'application/pdf';
  if (openAfterDownload) {
    await saveAndOpenFile(filename, bytes, mimeType: mime);
    return;
  }
  final file = XFile.fromData(
    Uint8List.fromList(bytes),
    mimeType: mime,
    name: filename,
  );
  await Share.shareXFiles([file], text: 'ATMOS DOT report PDF');
}

bool get pdfDownloadUsesShareSheet => true;

import 'dart:typed_data';

import 'package:cross_file/cross_file.dart';
import 'package:share_plus/share_plus.dart';

/// Non-web: share PDF bytes via the system share sheet.
Future<void> downloadPdfFile(String filename, List<int> bytes) async {
  final file = XFile.fromData(
    Uint8List.fromList(bytes),
    mimeType: 'application/pdf',
    name: filename,
  );
  await Share.shareXFiles([file], text: 'ATMOS DOT report PDF');
}

bool get pdfDownloadUsesShareSheet => true;

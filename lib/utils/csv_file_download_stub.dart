import 'package:flutter/services.dart';

/// Non-web: copy full CSV so users can paste into Excel or save manually.
Future<void> downloadCsvFile(String filename, String csvContent) async {
  await Clipboard.setData(ClipboardData(text: csvContent));
}

bool get csvDownloadUsesClipboard => true;

import 'dart:convert';
import 'dart:html' as html;

/// Web: trigger browser download of a UTF-8 CSV file.
Future<void> downloadCsvFile(String filename, String csvContent) async {
  final bytes = utf8.encode(csvContent);
  final blob = html.Blob([bytes], 'text/csv;charset=utf-8');
  final url = html.Url.createObjectUrlFromBlob(blob);
  html.AnchorElement(href: url)
    ..setAttribute('download', filename)
    ..click();
  html.Url.revokeObjectUrl(url);
}

bool get csvDownloadUsesClipboard => false;

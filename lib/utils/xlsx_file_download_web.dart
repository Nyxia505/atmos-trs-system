import 'dart:html' as html;
import 'dart:typed_data';

/// Web: trigger browser download of an XLSX file.
Future<void> downloadXlsxFile(
  String filename,
  List<int> bytes, {
  bool openAfterDownload = false,
}) async {
  final blob = html.Blob([
    Uint8List.fromList(bytes),
  ], 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet');
  final url = html.Url.createObjectUrlFromBlob(blob);
  html.AnchorElement(href: url)
    ..setAttribute('download', filename)
    ..click();
  if (openAfterDownload) {
    html.window.open(url, '_blank');
  }
  Future<void>.delayed(const Duration(seconds: 30), () {
    html.Url.revokeObjectUrl(url);
  });
}

bool get xlsxDownloadUsesShareSheet => false;

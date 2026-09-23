import 'dart:html' as html;
import 'dart:typed_data';

/// Web: trigger browser download of a PDF file.
Future<void> downloadPdfFile(String filename, List<int> bytes) async {
  final blob = html.Blob([Uint8List.fromList(bytes)], 'application/pdf');
  final url = html.Url.createObjectUrlFromBlob(blob);
  html.AnchorElement(href: url)
    ..setAttribute('download', filename)
    ..click();
  html.Url.revokeObjectUrl(url);
}

bool get pdfDownloadUsesShareSheet => false;

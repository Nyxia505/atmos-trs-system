import 'dart:html' as html;
import 'dart:typed_data';

/// Web: trigger download of a PNG file.
Future<void> downloadPngFile(String filename, Uint8List bytes) async {
  final blob = html.Blob([bytes], 'image/png');
  final url = html.Url.createObjectUrlFromBlob(blob);
  html.AnchorElement(href: url)
    ..setAttribute('download', filename)
    ..click();
  html.Url.revokeObjectUrl(url);
}

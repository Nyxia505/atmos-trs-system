import 'package:flutter/material.dart';

/// Web: file paths from device picker are not directly displayable.
Widget buildFileImage({required String path, required Widget fallback}) {
  return fallback;
}

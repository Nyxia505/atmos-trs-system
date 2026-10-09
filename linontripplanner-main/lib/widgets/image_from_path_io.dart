import 'dart:io';

import 'package:flutter/material.dart';

Widget buildFileImage({required String path, required Widget fallback}) {
  final file = File(path);
  if (!file.existsSync()) return fallback;
  return Image.file(
    file,
    width: double.infinity,
    height: double.infinity,
    fit: BoxFit.cover,
    filterQuality: FilterQuality.high,
    errorBuilder: (_, __, ___) => fallback,
  );
}

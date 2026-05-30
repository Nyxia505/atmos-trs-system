import 'package:flutter/material.dart';
import 'package:atmos_trs_system/config/app_theme.dart';

/// Thumbnail for tourist spot list/detail cards (assets + network).
Widget touristSpotThumbnail(
  String? imageUrl, {
  required double size,
  BorderRadius? borderRadius,
}) {
  final path = (imageUrl ?? '').trim();
  final radius = borderRadius ?? BorderRadius.circular(8);

  Widget child;
  if (path.isEmpty) {
    child = _placeholder(size);
  } else if (path.startsWith('http://') || path.startsWith('https://')) {
    child = Image.network(
      path,
      width: size,
      height: size,
      fit: BoxFit.cover,
      gaplessPlayback: true,
      errorBuilder: (_, __, ___) => _placeholder(size),
    );
  } else {
    final assetPath = path.startsWith('assets/') ? path : 'assets/images/$path';
    child = Image.asset(
      assetPath,
      width: size,
      height: size,
      fit: BoxFit.cover,
      gaplessPlayback: true,
      errorBuilder: (_, __, ___) {
        if (assetPath != path) {
          return Image.asset(
            path,
            width: size,
            height: size,
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => _placeholder(size),
          );
        }
        return _placeholder(size);
      },
    );
  }

  return ClipRRect(borderRadius: radius, child: child);
}

Widget _placeholder(double size) {
  return Container(
    width: size,
    height: size,
    color: AppTheme.unselectedMuted.withValues(alpha: 0.15),
    alignment: Alignment.center,
    child: Icon(
      Icons.landscape_rounded,
      color: AppTheme.unselectedMuted.withValues(alpha: 0.7),
      size: size * 0.42,
    ),
  );
}

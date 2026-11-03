import 'dart:typed_data';
import 'dart:ui' show ImageFilter, TileMode;

import 'package:flutter/material.dart';

import 'municipality_image.dart';

/// Poster frame that keeps the full image visible. Side gaps use a soft blur
/// of the same picture. Stored files are not changed.
class CatalogImagePreview extends StatelessWidget {
  const CatalogImagePreview({
    super.key,
    this.bytes,
    this.imagePath = '',
    this.width,
    this.height = 160,
    this.borderRadius = const BorderRadius.all(Radius.circular(10)),
    this.fallback,
  });

  final Uint8List? bytes;
  final String imagePath;
  final double? width;
  final double height;
  final BorderRadius borderRadius;
  final Widget? fallback;

  @override
  Widget build(BuildContext context) {
    final placeholder =
        fallback ??
        const ColoredBox(
          color: Color(0xFFFFF7ED),
          child: Icon(Icons.image_outlined, color: Color(0xFFFF6B00)),
        );
    return ClipRRect(
      borderRadius: borderRadius,
      child: SizedBox(width: width, height: height, child: _stack(placeholder)),
    );
  }

  Widget _stack(Widget placeholder) {
    final memory = bytes;
    if (memory != null && memory.isNotEmpty) {
      return _layered(
        (fit) => Image.memory(
          memory,
          fit: fit,
          alignment: Alignment.center,
          gaplessPlayback: true,
          filterQuality: FilterQuality.medium,
          width: double.infinity,
          height: double.infinity,
        ),
      );
    }
    final path = imagePath.trim();
    if (path.startsWith('http://') || path.startsWith('https://')) {
      return _layered(
        (fit) => Image.network(
          path,
          fit: fit,
          alignment: Alignment.center,
          filterQuality: FilterQuality.medium,
          width: double.infinity,
          height: double.infinity,
          errorBuilder: (_, _, _) => placeholder,
        ),
      );
    }
    if (path.isEmpty) return placeholder;
    return buildMunicipalityImage(path, fallback: placeholder);
  }

  Widget _layered(Widget Function(BoxFit fit) image) {
    return Stack(
      fit: StackFit.expand,
      alignment: Alignment.center,
      children: [
        ImageFiltered(
          imageFilter: ImageFilter.blur(
            sigmaX: 14,
            sigmaY: 14,
            tileMode: TileMode.clamp,
          ),
          child: Transform.scale(scale: 1.12, child: image(BoxFit.cover)),
        ),
        const ColoredBox(color: Color(0x24000000)),
        image(BoxFit.contain),
      ],
    );
  }
}

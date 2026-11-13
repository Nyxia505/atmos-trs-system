import 'package:flutter/material.dart';

/// Map marker glyph that keeps its fill color in Android release builds.
///
/// Material [Icon] + [Shadow] can composite as a black silhouette on some
/// Impeller/Skia release paths. [ColorFiltered] tints the glyph after layout
/// so bus/stop/spot colors match the Map & Routes legend.
///
/// Do not wrap this in [DecoratedBox]/[BoxShadow]: Flutter paints box shadows
/// as the child's rectangular bounds (not the glyph outline), which shows up
/// as large black blurry rectangles behind every pin on Android release APKs.
class OsmMapGlyph extends StatelessWidget {
  const OsmMapGlyph({
    super.key,
    required this.icon,
    required this.color,
    this.size = 36,
  });

  final IconData icon;
  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) {
    return ColorFiltered(
      colorFilter: ColorFilter.mode(color, BlendMode.srcIn),
      child: Icon(icon, size: size, color: Colors.white),
    );
  }
}

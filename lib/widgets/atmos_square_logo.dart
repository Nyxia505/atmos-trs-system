import 'package:flutter/material.dart';

/// Official ATMOS-TRS logo mark — [assets/images/final logo.png].
///
/// Always renders in a square box with [BoxFit.contain] so the mark never
/// stretches into a wide strip. White background on the asset is preserved.
class AtmosSquareLogo extends StatelessWidget {
  const AtmosSquareLogo({
    super.key,
    this.height,
    this.width,
    this.maxWidth,
    this.padding = const EdgeInsets.all(6),
    this.borderRadius = 12,
    this.backgroundColor = const Color(0xFFFFFFFF),
    this.elevation = 1,
    this.border,
  });

  static const String asset = 'assets/images/final logo.png';

  final double? height;
  final double? width;
  final double? maxWidth;
  final EdgeInsetsGeometry padding;
  final double borderRadius;
  final Color backgroundColor;
  final double elevation;
  final BoxBorder? border;

  @override
  Widget build(BuildContext context) {
    final side = height ?? width ?? 40.0;
    final boxSide = width != null && height != null
        ? (width! < height! ? width! : height!)
        : side;

    final image = Image.asset(
      asset,
      width: boxSide,
      height: boxSide,
      fit: BoxFit.contain,
      alignment: Alignment.center,
      filterQuality: FilterQuality.high,
      errorBuilder: (_, __, ___) => Icon(
        Icons.travel_explore_rounded,
        size: boxSide * 0.65,
        color: const Color(0xFFF97316),
      ),
    );

    Widget child = SizedBox(
      width: boxSide,
      height: boxSide,
      child: image,
    );
    if (maxWidth != null) {
      child = ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth!),
        child: child,
      );
    }

    return DecoratedBox(
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(borderRadius),
        border: border,
        boxShadow: elevation > 0
            ? [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.08),
                  blurRadius: elevation * 4,
                  offset: Offset(0, elevation),
                ),
              ]
            : null,
      ),
      child: Padding(
        padding: padding,
        child: Center(child: child),
      ),
    );
  }
}

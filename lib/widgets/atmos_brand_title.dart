import 'package:flutter/material.dart';
import 'package:atmos_trs_system/config/atmos_brand_typography.dart';

/// Custom ATMOS-TRS wordmark — flat geometric sans.
///
/// Default: black ATMOS + orange gradient TRS.
/// [solidBlack] / [solidWhite]: entire mark one bold solid color (no gradient).
class AtmosBrandTitle extends StatelessWidget {
  const AtmosBrandTitle({
    super.key,
    this.fontSize = 30,
    this.letterSpacing = 1.05,
    this.atmosColor = AtmosBrandTypography.wordmarkInk,
    this.textAlign = TextAlign.center,
    this.height = 1.0,
    /// Extra horizontal gap on each side of the hyphen (scaled with [fontSize]).
    this.hyphenGapFactor = 0.28,
    /// When true, ATMOS + hyphen render white; TRS keeps orange gradient.
    this.onDarkSurface = false,
    /// When true, full wordmark is bold black (no orange gradient on TRS).
    this.solidBlack = false,
    /// When true, full wordmark is bold white (no orange gradient on TRS).
    this.solidWhite = false,
    /// Optional shadows for legibility on colored or photo backgrounds.
    /// Ignored on the gradient TRS segment, which is drawn with a shader mask.
    this.shadows,
  });

  final double fontSize;
  final double letterSpacing;
  final Color atmosColor;
  final TextAlign textAlign;
  final double height;
  final double hyphenGapFactor;
  final bool onDarkSurface;
  final bool solidBlack;
  final bool solidWhite;
  final List<Shadow>? shadows;

  static const LinearGradient _trsGradient = LinearGradient(
    begin: Alignment.centerLeft,
    end: Alignment.centerRight,
    colors: [
      AtmosBrandTypography.wordmarkTrsStart,
      AtmosBrandTypography.wordmarkTrsEnd,
    ],
  );

  @override
  Widget build(BuildContext context) {
    final monochrome = solidBlack || solidWhite;
    final Color ink;
    if (solidWhite) {
      ink = Colors.white;
    } else if (solidBlack) {
      ink = AtmosBrandTypography.wordmarkInk;
    } else if (onDarkSurface) {
      ink = Colors.white;
    } else {
      ink = atmosColor;
    }
    final gap = fontSize * hyphenGapFactor;

    final atmosStyle = (monochrome
            ? AtmosBrandTypography.wordmarkTrs(
                color: ink,
                fontSize: fontSize,
                letterSpacing: letterSpacing,
                height: height,
              )
            : AtmosBrandTypography.wordmarkAtmos(
                color: ink,
                fontSize: fontSize,
                letterSpacing: letterSpacing,
                height: height,
              ))
        .copyWith(shadows: shadows);
    final hyphenStyle = AtmosBrandTypography.wordmarkHyphen(
      color: ink,
      fontSize: fontSize,
      height: height,
    ).copyWith(
      fontWeight: monochrome ? FontWeight.w800 : FontWeight.w700,
      shadows: shadows,
    );

    final trsBase = AtmosBrandTypography.wordmarkTrs(
      color: monochrome ? ink : Colors.white,
      fontSize: fontSize,
      letterSpacing: letterSpacing + 0.1,
      height: height,
    ).copyWith(shadows: monochrome ? shadows : null);

    final Widget trsChild = monochrome
        ? Text('TRS', style: trsBase)
        : ShaderMask(
            blendMode: BlendMode.srcIn,
            shaderCallback: (bounds) => _trsGradient.createShader(bounds),
            child: Text('TRS', style: trsBase),
          );

    final mark = Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.baseline,
      textBaseline: TextBaseline.alphabetic,
      children: [
        Text('ATMOS', style: atmosStyle),
        Padding(
          padding: EdgeInsets.symmetric(horizontal: gap),
          child: Text('-', style: hyphenStyle),
        ),
        trsChild,
      ],
    );

    return Align(
      alignment: _alignmentFor(textAlign),
      child: mark,
    );
  }

  static Alignment _alignmentFor(TextAlign align) {
    switch (align) {
      case TextAlign.left:
      case TextAlign.start:
        return Alignment.centerLeft;
      case TextAlign.right:
      case TextAlign.end:
        return Alignment.centerRight;
      case TextAlign.center:
      case TextAlign.justify:
        return Alignment.center;
    }
  }
}

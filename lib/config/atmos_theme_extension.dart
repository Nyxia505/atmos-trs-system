import 'package:flutter/material.dart';

/// Extra accent shades on [ThemeData] so widgets can use [Theme.of] instead of static colors.
class AtmosThemeExtension extends ThemeExtension<AtmosThemeExtension> {
  const AtmosThemeExtension({
    required this.primaryLight,
    required this.primaryDark,
    required this.onPrimary,
  });

  final Color primaryLight;
  final Color primaryDark;
  final Color onPrimary;

  @override
  AtmosThemeExtension copyWith({
    Color? primaryLight,
    Color? primaryDark,
    Color? onPrimary,
  }) {
    return AtmosThemeExtension(
      primaryLight: primaryLight ?? this.primaryLight,
      primaryDark: primaryDark ?? this.primaryDark,
      onPrimary: onPrimary ?? this.onPrimary,
    );
  }

  @override
  AtmosThemeExtension lerp(ThemeExtension<AtmosThemeExtension>? other, double t) {
    if (other is! AtmosThemeExtension) return this;
    return AtmosThemeExtension(
      primaryLight: Color.lerp(primaryLight, other.primaryLight, t)!,
      primaryDark: Color.lerp(primaryDark, other.primaryDark, t)!,
      onPrimary: Color.lerp(onPrimary, other.onPrimary, t)!,
    );
  }
}

extension AtmosThemeContext on BuildContext {
  ColorScheme get appColors => Theme.of(this).colorScheme;

  Color get accent => appColors.primary;

  AtmosThemeExtension get atmos =>
      Theme.of(this).extension<AtmosThemeExtension>()!;

  Color get accentLight => atmos.primaryLight;

  Color get accentDark => atmos.primaryDark;

  Color get onAccent => atmos.onPrimary;
}

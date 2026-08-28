import 'package:flutter/material.dart';
import 'package:atmos_trs_system/config/app_theme_controller.dart';

/// Rebuilds [child] when the user picks a new theme color in Settings.
///
/// Uses a [ValueKey] on the preset id so [IndexedStack] tabs refresh accents
/// (home, explore, profile, etc.) instead of keeping stale colors.
class ThemeReactiveScope extends StatelessWidget {
  const ThemeReactiveScope({
    super.key,
    required this.child,
  });

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: AppThemeController.instance,
      builder: (context, _) {
        return KeyedSubtree(
          key: ValueKey<String>(AppThemeController.instance.presetId),
          child: child,
        );
      },
    );
  }
}

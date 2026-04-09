import 'package:flutter/material.dart';
import 'package:atmos_trs_system/config/app_theme.dart';

/// Shared logout UI: door icon (no exit arrow) + **Logout**
/// (Governor / Tourism sidebars: solid orange pill; profile: solid pill on light surfaces).
enum AppLogoutStyle {
  /// Solid orange pill with light elevation (sidebar/drawer on orange background).
  sidebarOnOrange,

  /// Full orange pill for profile / light surfaces (tourist app).
  solidPill,
}

class AppLogoutButton extends StatelessWidget {
  const AppLogoutButton({
    super.key,
    required this.onPressed,
    required this.style,
    this.expanded = true,
    this.fullWidth = false,
    this.margin,
  });

  final VoidCallback onPressed;
  final AppLogoutStyle style;
  final bool expanded;

  /// When [style] is [AppLogoutStyle.solidPill], stretches to max width.
  final bool fullWidth;
  final EdgeInsetsGeometry? margin;

  static const IconData _doorIcon = Icons.meeting_room_rounded;

  static Widget _iconChipOnSolidOrange() {
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.24),
        borderRadius: BorderRadius.circular(10),
      ),
      child: const Icon(
        _doorIcon,
        color: Colors.white,
        size: 20,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final labelStyle = TextStyle(
      color: Colors.white,
      fontSize: style == AppLogoutStyle.solidPill ? 16 : 15,
      fontWeight: FontWeight.w600,
      letterSpacing: 0.15,
    );

    const double sidebarRadius = 24;
    const doorSize = 22.0;

    late final Widget interactive;
    switch (style) {
      case AppLogoutStyle.sidebarOnOrange:
        final content = expanded
            ? Row(
                mainAxisAlignment: MainAxisAlignment.start,
                children: [
                  const Icon(
                    _doorIcon,
                    color: Colors.white,
                    size: doorSize,
                  ),
                  const SizedBox(width: 12),
                  Text('Logout', style: labelStyle),
                ],
              )
            : const Icon(
                _doorIcon,
                color: Colors.white,
                size: doorSize,
              );
        interactive = SizedBox(
          width: expanded ? double.infinity : null,
          child: Material(
            color: AppTheme.primaryDark,
            elevation: 3,
            shadowColor: Colors.black.withOpacity(0.35),
            borderRadius: BorderRadius.circular(sidebarRadius),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: onPressed,
              borderRadius: BorderRadius.circular(sidebarRadius),
              hoverColor: Colors.white.withOpacity(0.12),
              splashColor: Colors.white.withOpacity(0.2),
              child: Padding(
                padding: EdgeInsets.symmetric(
                  horizontal: expanded ? 18 : 14,
                  vertical: expanded ? 14 : 12,
                ),
                child: content,
              ),
            ),
          ),
        );
        break;
      case AppLogoutStyle.solidPill:
        interactive = SizedBox(
          width: fullWidth ? double.infinity : null,
          child: Material(
            color: Colors.transparent,
            borderRadius: BorderRadius.circular(14),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: onPressed,
              borderRadius: BorderRadius.circular(14),
              hoverColor: Colors.white.withOpacity(0.08),
              splashColor: Colors.white.withOpacity(0.15),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  color: AppTheme.primaryDark,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: Colors.white.withOpacity(0.22)),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.12),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _iconChipOnSolidOrange(),
                    const SizedBox(width: 14),
                    Text('Logout', style: labelStyle),
                  ],
                ),
              ),
            ),
          ),
        );
        break;
    }

    Widget child = interactive;
    if (style == AppLogoutStyle.sidebarOnOrange && !expanded) {
      child = Align(
        alignment: Alignment.center,
        child: interactive,
      );
    }
    return Padding(
      padding: margin ?? EdgeInsets.zero,
      child: child,
    );
  }
}

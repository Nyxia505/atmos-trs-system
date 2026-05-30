import 'package:flutter/material.dart';
import 'package:atmos_trs_system/config/app_theme.dart';
import 'package:atmos_trs_system/config/app_theme_controller.dart';

/// Shared logout UI for admin sidebars and profile screens.
enum AppLogoutStyle {
  /// Fixed orange pill on Governor / Tourism sidebars (not user theme color).
  sidebarOnOrange,

  /// Full-width accent pill for profile / light surfaces (tourist app).
  solidPill,
}

/// Admin sidebar orange — always orange on Governor / Tourism dashboards.
const Color kAdminLogoutOrange = Color(0xFFEA580C);
const Color kAdminLogoutOrangeLight = Color(0xFFF97316);
const Color kAdminLogoutOrangeDark = Color(0xFFC2410C);

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

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: AppThemeController.instance,
      builder: (context, _) => _buildButton(context),
    );
  }

  Widget _buildButton(BuildContext context) {
    final labelStyle = TextStyle(
      color: AppTheme.onPrimary,
      fontSize: style == AppLogoutStyle.solidPill ? 16 : 15,
      fontWeight: FontWeight.w700,
      letterSpacing: 0.2,
    );

    final accentLight = AppTheme.primaryLight;
    final accent = AppTheme.primary;
    final accentDark = AppTheme.primaryDark;

    late final _LogoutVisualConfig config;
    switch (style) {
      case AppLogoutStyle.sidebarOnOrange:
        config = _LogoutVisualConfig(
          radius: 24,
          horizontalPadding: expanded ? 18 : 12,
          verticalPadding: expanded ? 14 : 12,
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              kAdminLogoutOrangeLight,
              kAdminLogoutOrange,
              kAdminLogoutOrangeDark,
            ],
          ),
          borderColor: Colors.white.withValues(alpha: 0.24),
          shadowColor: Colors.black.withValues(alpha: 0.28),
          overlayColor: Colors.white.withValues(alpha: 0.08),
          splashColor: Colors.white.withValues(alpha: 0.18),
        );
        break;
      case AppLogoutStyle.solidPill:
        config = _LogoutVisualConfig(
          radius: 14,
          horizontalPadding: 16,
          verticalPadding: 12,
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [accentLight, accent, accentDark],
          ),
          borderColor: Colors.white.withValues(alpha: 0.2),
          shadowColor: Colors.black.withValues(alpha: 0.14),
          overlayColor: Colors.white.withValues(alpha: 0.08),
          splashColor: Colors.white.withValues(alpha: 0.15),
        );
        break;
    }

    final content = FittedBox(
      fit: BoxFit.scaleDown,
      child: Text(
        'Logout',
        maxLines: 1,
        softWrap: false,
        style: labelStyle,
      ),
    );

    final child = SizedBox(
      width: (style == AppLogoutStyle.solidPill && fullWidth) || expanded
          ? double.infinity
          : null,
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(config.radius),
        clipBehavior: Clip.antiAlias,
        child: Ink(
          decoration: BoxDecoration(
            gradient: config.gradient,
            borderRadius: BorderRadius.circular(config.radius),
            border: Border.all(color: config.borderColor),
            boxShadow: [
              BoxShadow(
                color: config.shadowColor,
                blurRadius: 10,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: InkWell(
            onTap: onPressed,
            borderRadius: BorderRadius.circular(config.radius),
            hoverColor: config.overlayColor,
            splashColor: config.splashColor,
            child: Stack(
              children: [
                Positioned(
                  left: 0,
                  right: 0,
                  top: 0,
                  child: IgnorePointer(
                    child: Container(
                      height: 1.2,
                      color: Colors.white.withValues(alpha: 0.35),
                    ),
                  ),
                ),
                Padding(
                  padding: EdgeInsets.symmetric(
                    horizontal: config.horizontalPadding,
                    vertical: config.verticalPadding,
                  ),
                  child: Center(child: content),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    return Padding(
      padding: margin ?? EdgeInsets.zero,
      child: child,
    );
  }
}

class _LogoutVisualConfig {
  const _LogoutVisualConfig({
    required this.radius,
    required this.horizontalPadding,
    required this.verticalPadding,
    required this.gradient,
    required this.borderColor,
    required this.shadowColor,
    required this.overlayColor,
    required this.splashColor,
  });

  final double radius;
  final double horizontalPadding;
  final double verticalPadding;
  final Gradient gradient;
  final Color borderColor;
  final Color shadowColor;
  final Color overlayColor;
  final Color splashColor;
}

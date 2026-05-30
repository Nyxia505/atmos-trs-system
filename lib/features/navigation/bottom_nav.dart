import 'package:flutter/material.dart';
import 'package:atmos_trs_system/config/app_theme.dart';

/// Bottom nav items: Home, Explore, Scan (center elevated), Notification, Account.
/// Active: theme accent; Inactive: grey.
const List<(IconData, String)> kBottomNavItems = [
  (Icons.home_rounded, 'Home'),
  (Icons.explore_rounded, 'Explore'),
  (Icons.qr_code_scanner_rounded, 'Scan'),
  (Icons.notifications_rounded, 'Notification'),
  (Icons.person_rounded, 'Account'),
];

class BottomNav extends StatelessWidget {
  const BottomNav({
    super.key,
    required this.currentIndex,
    required this.onTap,
    this.unreadNotificationCount = 0,
  });

  final int currentIndex;
  final ValueChanged<int> onTap;
  final int unreadNotificationCount;

  @override
  Widget build(BuildContext context) {
    final showLabels = MediaQuery.sizeOf(context).width >= 360;
    final padding = _adaptiveHorizontalPadding(context);
    return Container(
      decoration: BoxDecoration(
        color: AppTheme.cardBackground,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.2),
            blurRadius: 12,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: SafeArea(
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: padding, vertical: 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: List.generate(kBottomNavItems.length, (index) {
              final item = kBottomNavItems[index];
              return _NavItem(
                icon: item.$1,
                label: item.$2,
                isSelected: index == currentIndex,
                isScanTab: index == 2,
                showLabel: showLabels,
                badgeCount: index == 3 ? unreadNotificationCount : 0,
                onTap: () => onTap(index),
              );
            }),
          ),
        ),
      ),
    );
  }

  static double _adaptiveHorizontalPadding(BuildContext context) {
    final w = MediaQuery.sizeOf(context).width;
    if (w >= 600) return 24;
    if (w >= 400) return 16;
    return 8;
  }
}

class _NavItem extends StatelessWidget {
  const _NavItem({
    required this.icon,
    required this.label,
    required this.isSelected,
    required this.isScanTab,
    required this.showLabel,
    required this.badgeCount,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool isSelected;
  final bool isScanTab;
  final bool showLabel;
  final int badgeCount;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = isSelected ? AppTheme.primary : AppTheme.unselectedMuted;
    final iconSize = isScanTab ? 28.0 : 24.0;

    Widget iconWidget = Icon(
      icon,
      size: iconSize,
      color: isScanTab && isSelected ? AppTheme.primary : color,
    );

    if (isScanTab) {
      iconWidget = Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: isSelected ? AppTheme.primary.withOpacity(0.2) : Colors.transparent,
          border: isSelected ? Border.all(color: AppTheme.primary.withOpacity(0.6), width: 1.5) : null,
        ),
        child: Icon(
          icon,
          size: 26,
          color: isSelected ? AppTheme.primary : AppTheme.unselectedMuted,
        ),
      );
    }

    final iconWithBadge = badgeCount > 0
        ? Badge(
            label: Text(
              badgeCount > 99 ? '99+' : '$badgeCount',
              style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700),
            ),
            backgroundColor: const Color(0xFFDC2626),
            child: iconWidget,
          )
        : iconWidget;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            iconWithBadge,
            if (showLabel) ...[
              const SizedBox(height: 4),
              Text(
                label,
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                  color: color,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
    
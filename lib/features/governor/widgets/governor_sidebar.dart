import 'dart:ui';

import 'package:atmos_trs_system/config/supabase_storage_config.dart';
import 'package:atmos_trs_system/data/tourist_spot_image_catalog.dart';
import 'package:atmos_trs_system/features/governor/theme/governor_dashboard_tokens.dart';
import 'package:atmos_trs_system/widgets/atmos_square_logo.dart';
import 'package:flutter/material.dart';

class GovernorNavItemData {
  const GovernorNavItemData({
    required this.label,
    required this.icon,
    this.badgeCount = 0,
  });

  final String label;
  final IconData icon;
  final int badgeCount;
}

/// Floating white sidebar card with thick orange outer frame (concept image 2).
class GovernorSidebar extends StatelessWidget {
  const GovernorSidebar({
    super.key,
    required this.expanded,
    required this.selectedIndex,
    required this.items,
    required this.onSelect,
    required this.onToggle,
    required this.onLogout,
    this.brandTitle = 'Governor',
    this.brandSubtitle = 'Misamis Occidental',
    this.profileName = 'Governor',
    this.profileSubtitle = 'Misamis Occidental',
    this.avatar,
    this.asDrawer = false,
    /// ATMOS mark beside the brand title. Enable only on the Governor portal.
    this.showBrandLogo = false,
  });

  final bool expanded;
  final int selectedIndex;
  final List<GovernorNavItemData> items;
  final ValueChanged<int> onSelect;
  final VoidCallback onToggle;
  final VoidCallback onLogout;
  /// Top brand label in the sidebar header (e.g. Governor / Provincial Tourism).
  final String brandTitle;
  final String brandSubtitle;
  final String profileName;
  final String profileSubtitle;
  final Widget? avatar;
  final bool asDrawer;
  final bool showBrandLogo;

  static const double _frameInset = 8;
  static const double _panelRadius = 28;

  double get _innerWidth => expanded
      ? GovernorDashboardTokens.sidebarExpanded
      : GovernorDashboardTokens.sidebarCollapsed;

  double get _outerWidth => _innerWidth + (_frameInset * 2);

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.paddingOf(context).bottom;
    final topInset = asDrawer ? MediaQuery.paddingOf(context).top : 0.0;

    final panel = ClipRRect(
      borderRadius: BorderRadius.circular(_panelRadius),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.96),
            borderRadius: BorderRadius.circular(_panelRadius),
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.9),
              width: 1.2,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.12),
                blurRadius: 22,
                offset: const Offset(0, 10),
              ),
              BoxShadow(
                color: GovernorDashboardTokens.primary.withValues(alpha: 0.18),
                blurRadius: 18,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            children: [
              SizedBox(height: asDrawer ? 8 : 10),
              _buildBrandHeader(),
              const SizedBox(height: 14),
              Expanded(child: _buildNav()),
              if (expanded) _buildFooterArt(),
              Padding(
                padding: EdgeInsets.fromLTRB(
                  expanded ? 16 : 10,
                  expanded ? 10 : 8,
                  expanded ? 16 : 10,
                  14 + bottomInset,
                ),
                child: _GlassLogoutButton(
                  expanded: expanded,
                  onPressed: onLogout,
                ),
              ),
            ],
          ),
        ),
      ),
    );

    final framed = DecoratedBox(
      decoration: const BoxDecoration(
        gradient: GovernorDashboardTokens.headerGradient,
      ),
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          _frameInset,
          _frameInset + topInset,
          _frameInset,
          _frameInset,
        ),
        child: panel,
      ),
    );

    if (asDrawer) {
      return Drawer(
        width: _outerWidth + 8,
        backgroundColor: Colors.transparent,
        child: DecoratedBox(
          decoration: const BoxDecoration(
            gradient: GovernorDashboardTokens.headerGradient,
          ),
          child: framed,
        ),
      );
    }

    return AnimatedContainer(
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOutCubic,
      width: _outerWidth,
      child: framed,
    );
  }

  Widget _buildBrandHeader() {
    final mark = _BrandMark(size: expanded ? 44 : 34, showLogo: showBrandLogo);

    if (!expanded) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(6, 4, 6, 0),
        child: Column(
          children: [
            InkWell(
              onTap: onToggle,
              borderRadius: BorderRadius.circular(12),
              child: mark,
            ),
            const SizedBox(height: 4),
            IconButton(
              tooltip: 'Expand sidebar',
              onPressed: onToggle,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
              icon: const Icon(
                Icons.keyboard_double_arrow_right_rounded,
                size: 18,
              ),
              color: GovernorDashboardTokens.primary,
            ),
          ],
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 6, 4, 4),
      child: Row(
        children: [
          mark,
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  brandTitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GovernorDashboardTokens.sectionTitle(size: 14),
                ),
                Text(
                  brandSubtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GovernorDashboardTokens.body(size: 10.5),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: asDrawer ? 'Close' : 'Collapse sidebar',
            onPressed: onToggle,
            visualDensity: VisualDensity.compact,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
            icon: Icon(
              asDrawer
                  ? Icons.close_rounded
                  : Icons.keyboard_double_arrow_left_rounded,
              size: 18,
            ),
            color: GovernorDashboardTokens.subtitle,
          ),
        ],
      ),
    );
  }

  Widget _buildNav() {
    return ListView.separated(
      padding: EdgeInsets.symmetric(
        horizontal: expanded ? 12 : 6,
        vertical: 4,
      ),
      itemCount: items.length,
      separatorBuilder: (_, __) => const SizedBox(height: 6),
      itemBuilder: (context, index) {
        final item = items[index];
        return _NavTile(
          item: item,
          expanded: expanded,
          selected: index == selectedIndex,
          onTap: () => onSelect(index),
        );
      },
    );
  }

  Widget _buildFooterArt() {
    final heroUrl =
        SupabaseStorageConfig.resolve(MisamisOccidentalImages.landingBg);
    final isNetwork =
        heroUrl.startsWith('http://') || heroUrl.startsWith('https://');

    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 4, 14, 0),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(GovernorDashboardTokens.radiusMd),
        child: SizedBox(
          height: 108,
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (isNetwork)
                Image.network(
                  heroUrl,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => Container(
                    color: GovernorDashboardTokens.softOrange,
                  ),
                )
              else
                Image.asset(
                  heroUrl,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => Container(
                    color: GovernorDashboardTokens.softOrange,
                  ),
                ),
              DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.white.withValues(alpha: 0.08),
                      Colors.black.withValues(alpha: 0.45),
                    ],
                  ),
                ),
              ),
              const Padding(
                padding: EdgeInsets.all(12),
                child: Align(
                  alignment: Alignment.bottomLeft,
                  child: Text(
                    'Explore · Preserve · Empower',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                      fontSize: 11.5,
                      letterSpacing: 0.2,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _BrandMark extends StatelessWidget {
  const _BrandMark({required this.size, required this.showLogo});
  final double size;
  final bool showLogo;

  @override
  Widget build(BuildContext context) {
    if (showLogo) {
      // Official ATMOS mark — Governor sidebar only.
      return AtmosSquareLogo(
        height: size,
        width: size,
        padding: EdgeInsets.all(size * 0.04),
        borderRadius: size * 0.26,
        elevation: 1,
        border: Border.all(
          color: GovernorDashboardTokens.primary.withValues(alpha: 0.18),
        ),
      );
    }

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(size * 0.28),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color(0xFFFFB86B),
            Color(0xFFF97316),
            Color(0xFF0EA5E9),
          ],
        ),
        boxShadow: [
          BoxShadow(
            color: GovernorDashboardTokens.primary.withValues(alpha: 0.28),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Icon(
        Icons.landscape_rounded,
        color: Colors.white,
        size: size * 0.55,
      ),
    );
  }
}

class _GlassLogoutButton extends StatelessWidget {
  const _GlassLogoutButton({required this.expanded, required this.onPressed});
  final bool expanded;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(999),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
        child: Material(
          color: Colors.white.withValues(alpha: 0.55),
          child: InkWell(
            onTap: onPressed,
            child: Container(
              width: double.infinity,
              padding: EdgeInsets.symmetric(
                horizontal: expanded ? 16 : 10,
                vertical: 12,
              ),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(999),
                border: Border.all(
                  color: GovernorDashboardTokens.primary.withValues(alpha: 0.55),
                  width: 1.4,
                ),
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    GovernorDashboardTokens.softOrange.withValues(alpha: 0.85),
                    Colors.white.withValues(alpha: 0.75),
                  ],
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(
                    Icons.logout_rounded,
                    size: 18,
                    color: GovernorDashboardTokens.primaryDark,
                  ),
                  if (expanded) ...[
                    const SizedBox(width: 8),
                    Text(
                      'Logout',
                      style: GovernorDashboardTokens.sectionTitle(
                        size: 13.5,
                        color: GovernorDashboardTokens.primaryDark,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _NavTile extends StatefulWidget {
  const _NavTile({
    required this.item,
    required this.expanded,
    required this.selected,
    required this.onTap,
  });

  final GovernorNavItemData item;
  final bool expanded;
  final bool selected;
  final VoidCallback onTap;

  @override
  State<_NavTile> createState() => _NavTileState();
}

class _NavTileState extends State<_NavTile> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final selected = widget.selected;
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: Tooltip(
        message: widget.expanded ? '' : widget.item.label,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOutCubic,
          decoration: BoxDecoration(
            gradient: selected ? GovernorDashboardTokens.primaryGradient : null,
            color: selected
                ? null
                : (_hovered
                    ? GovernorDashboardTokens.mutedSurface
                    : Colors.transparent),
            borderRadius:
                BorderRadius.circular(GovernorDashboardTokens.radiusMd),
            boxShadow: selected
                ? [
                    BoxShadow(
                      color: GovernorDashboardTokens.primary
                          .withValues(alpha: 0.35),
                      blurRadius: 14,
                      offset: const Offset(0, 6),
                    ),
                  ]
                : null,
          ),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: widget.onTap,
              borderRadius:
                  BorderRadius.circular(GovernorDashboardTokens.radiusMd),
              child: Padding(
                padding: EdgeInsets.symmetric(
                  horizontal: widget.expanded ? 14 : 6,
                  vertical: 12,
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Stack(
                      clipBehavior: Clip.none,
                      children: [
                        Icon(
                          widget.item.icon,
                          size: 20,
                          color: selected
                              ? Colors.white
                              : GovernorDashboardTokens.subtitle,
                        ),
                        if (widget.item.badgeCount > 0)
                          Positioned(
                            right: -8,
                            top: -6,
                            child: _Badge(count: widget.item.badgeCount),
                          ),
                      ],
                    ),
                    if (widget.expanded) ...[
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          widget.item.label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: GovernorDashboardTokens.sectionTitle(
                            size: 13.5,
                            color: selected
                                ? Colors.white
                                : GovernorDashboardTokens.text,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge({required this.count});
  final int count;

  @override
  Widget build(BuildContext context) {
    final label = count > 99 ? '99+' : '$count';
    return Container(
      constraints: const BoxConstraints(minWidth: 16, minHeight: 16),
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
      decoration: BoxDecoration(
        color: GovernorDashboardTokens.danger,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.white, width: 1.2),
      ),
      alignment: Alignment.center,
      child: Text(
        label,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 9,
          fontWeight: FontWeight.w800,
          height: 1.1,
        ),
      ),
    );
  }
}

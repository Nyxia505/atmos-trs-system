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
    this.pageIndex,
    this.children = const [],
  });

  final String label;
  final IconData icon;
  final int badgeCount;

  /// Content page this tile opens. Parents with [children] can omit it.
  final int? pageIndex;
  final List<GovernorNavItemData> children;
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
    /// Circular office seal beside the brand title (e.g. OPTACA). Takes
    /// precedence over [showBrandLogo].
    this.brandLogoAsset,
    /// Bundled photo for the footer card; defaults to the landing hero.
    this.footerImageAsset,
    this.groupExpanded = false,
    this.onToggleGroup,
    this.plain = false,
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
  final String? brandLogoAsset;
  final String? footerImageAsset;

  /// Whether the Trip Planner-style parent with children is open.
  final bool groupExpanded;
  final VoidCallback? onToggleGroup;

  /// Orange sidebar matching the Governor header. OPTACA keeps the framed style.
  final bool plain;

  static const double _frameInset = 8;
  static const double _panelRadius = 28;

  double get _innerWidth => expanded
      ? GovernorDashboardTokens.sidebarExpanded
      : GovernorDashboardTokens.sidebarCollapsed;

  double get _outerWidth => _innerWidth + (_frameInset * 2);

  Widget _panelShell(double bottomInset) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: plain
            ? Colors.transparent
            : Colors.white.withValues(alpha: 0.96),
        borderRadius: BorderRadius.circular(_panelRadius),
        border: plain
            ? null
            : Border.all(
                color: Colors.white.withValues(alpha: 0.9),
                width: 1.2,
              ),
        boxShadow: plain
            ? null
            : [
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
      child: LayoutBuilder(
        builder: (context, constraints) {
          final open = asDrawer ||
              (expanded &&
                  constraints.maxWidth >=
                      GovernorDashboardTokens.sidebarExpanded - 0.5);
          return Column(
            children: [
              SizedBox(height: asDrawer ? 8 : 10),
              _buildBrandHeader(open),
              const SizedBox(height: 14),
              Expanded(child: _buildNav(open)),
              if (open && footerImageAsset != null) _buildFooterArt(),
              Padding(
                padding: EdgeInsets.fromLTRB(
                  open ? 16 : 10,
                  open ? 10 : 8,
                  open ? 16 : 10,
                  14 + bottomInset,
                ),
                child: _GlassLogoutButton(
                  expanded: open,
                  onPressed: onLogout,
                  plain: plain,
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.paddingOf(context).bottom;
    final topInset = asDrawer ? MediaQuery.paddingOf(context).top : 0.0;

    final panel = ClipRRect(
      borderRadius: BorderRadius.circular(plain ? 0 : _panelRadius),
      child: plain
          ? _panelShell(bottomInset)
          : BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
              child: _panelShell(bottomInset),
            ),
    );

    final framed = DecoratedBox(
      decoration: const BoxDecoration(
        gradient: GovernorDashboardTokens.sidebarGradient,
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
        width: plain ? _innerWidth : _outerWidth + 8,
        backgroundColor: plain ? Colors.transparent : Colors.transparent,
        child: plain
            ? DecoratedBox(
                decoration: const BoxDecoration(
                  gradient: GovernorDashboardTokens.headerGradient,
                ),
                child: panel,
              )
            : DecoratedBox(
                decoration: const BoxDecoration(
                  gradient: GovernorDashboardTokens.sidebarGradient,
                ),
                child: framed,
              ),
      );
    }

    if (plain) {
      return AnimatedContainer(
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOutCubic,
        width: _innerWidth,
        decoration: const BoxDecoration(
          gradient: GovernorDashboardTokens.headerGradient,
        ),
        child: panel,
      );
    }

    return AnimatedContainer(
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOutCubic,
      width: _outerWidth,
      child: framed,
    );
  }

  Widget _buildBrandHeader(bool open) {
    final mark = _BrandMark(
      size: open ? 44 : 34,
      showLogo: showBrandLogo,
      logoAsset: brandLogoAsset,
    );

    if (!open) {
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
              color: plain ? Colors.white : GovernorDashboardTokens.primary,
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
                  style: GovernorDashboardTokens.sectionTitle(
                    size: 14,
                    color: plain ? Colors.white : null,
                  ),
                ),
                Text(
                  brandSubtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GovernorDashboardTokens.body(
                    size: 10.5,
                    color: plain ? Colors.white.withValues(alpha: 0.9) : null,
                  ),
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
            color: plain ? Colors.white : GovernorDashboardTokens.subtitle,
          ),
        ],
      ),
    );
  }

  Widget _buildNav(bool open) {
    return ListView.separated(
      padding: EdgeInsets.symmetric(
        horizontal: open ? 12 : 6,
        vertical: 4,
      ),
      itemCount: items.length,
      separatorBuilder: (_, __) => const SizedBox(height: 6),
      itemBuilder: (context, index) {
        final item = items[index];
        final page = item.pageIndex ?? index;
        if (item.children.isEmpty) {
          return _NavTile(
            item: item,
            expanded: open,
            selected: page == selectedIndex,
            onOrange: plain,
            onTap: () => onSelect(page),
          );
        }
        final childActive = item.children.any(
          (child) => child.pageIndex == selectedIndex,
        );
        return _NavGroup(
          item: item,
          expanded: open,
          groupOpen: groupExpanded || childActive,
          childActive: childActive,
          selectedIndex: selectedIndex,
          onOrange: plain,
          onToggle: onToggleGroup ?? () {},
          onSelect: onSelect,
        );
      },
    );
  }

  Widget _buildFooterArt() {
    final heroUrl = footerImageAsset ??
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
  const _BrandMark({
    required this.size,
    required this.showLogo,
    this.logoAsset,
  });
  final double size;
  final bool showLogo;
  final String? logoAsset;

  @override
  Widget build(BuildContext context) {
    final asset = logoAsset;
    if (asset != null) {
      return Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: Colors.white,
          boxShadow: [
            BoxShadow(
              color: GovernorDashboardTokens.primary.withValues(alpha: 0.22),
              blurRadius: 10,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: ClipOval(
          child: Image.asset(
            asset,
            fit: BoxFit.cover,
            filterQuality: FilterQuality.high,
            errorBuilder: (_, __, ___) => Icon(
              Icons.landscape_rounded,
              color: GovernorDashboardTokens.primary,
              size: size * 0.55,
            ),
          ),
        ),
      );
    }

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
  const _GlassLogoutButton({
    required this.expanded,
    required this.onPressed,
    this.plain = false,
  });
  final bool expanded;
  final VoidCallback onPressed;
  final bool plain;

  @override
  Widget build(BuildContext context) {
    if (plain) {
      return Material(
        color: Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(999),
          side: const BorderSide(color: Colors.white, width: 1.4),
        ),
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(999),
          child: Padding(
            padding: EdgeInsets.symmetric(
              horizontal: expanded ? 16 : 10,
              vertical: 12,
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(
                  Icons.logout_rounded,
                  color: GovernorDashboardTokens.primaryDark,
                  size: 18,
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
      );
    }
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
    this.trailing,
    this.dense = false,
    this.emphasized = false,
    this.onOrange = false,
  });

  final GovernorNavItemData item;
  final bool expanded;
  final bool selected;
  final VoidCallback onTap;
  final Widget? trailing;
  final bool dense;
  final bool emphasized;
  final bool onOrange;

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
            gradient: selected && !widget.onOrange
                ? GovernorDashboardTokens.primaryGradient
                : null,
            color: selected
                ? (widget.onOrange ? Colors.white : null)
                : (_hovered
                    ? (widget.onOrange
                        ? Colors.white.withValues(alpha: 0.16)
                        : GovernorDashboardTokens.mutedSurface)
                    : (widget.emphasized
                        ? (widget.onOrange
                            ? Colors.white.withValues(alpha: 0.22)
                            : GovernorDashboardTokens.softOrange)
                        : Colors.transparent)),
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
                  horizontal: widget.expanded ? (widget.dense ? 10 : 14) : 6,
                  vertical: widget.dense ? 9 : 12,
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
                              ? (widget.onOrange
                                  ? GovernorDashboardTokens.primaryDark
                                  : Colors.white)
                              : (widget.onOrange
                                  ? Colors.white
                                  : (widget.emphasized
                                      ? GovernorDashboardTokens.primaryDark
                                      : GovernorDashboardTokens.subtitle)),
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
                                ? (widget.onOrange
                                    ? GovernorDashboardTokens.primaryDark
                                    : Colors.white)
                                : (widget.onOrange
                                    ? Colors.white
                                    : (widget.emphasized
                                        ? GovernorDashboardTokens.primaryDark
                                        : GovernorDashboardTokens.text)),
                          ),
                        ),
                      ),
                      if (widget.trailing != null) widget.trailing!,
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

class _NavGroup extends StatelessWidget {
  const _NavGroup({
    required this.item,
    required this.expanded,
    required this.groupOpen,
    required this.childActive,
    required this.selectedIndex,
    required this.onToggle,
    required this.onSelect,
    this.onOrange = false,
  });

  final GovernorNavItemData item;
  final bool expanded;
  final bool groupOpen;
  final bool childActive;
  final int selectedIndex;
  final VoidCallback onToggle;
  final ValueChanged<int> onSelect;
  final bool onOrange;

  @override
  Widget build(BuildContext context) {
    final showChildren = expanded && groupOpen;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _NavTile(
          item: item,
          expanded: expanded,
          selected: false,
          onOrange: onOrange,
          emphasized: childActive && !showChildren,
          trailing: expanded
              ? Icon(
                  showChildren
                      ? Icons.expand_more_rounded
                      : Icons.chevron_right_rounded,
                  size: 20,
                  color: onOrange
                      ? Colors.white
                      : (childActive
                          ? GovernorDashboardTokens.primaryDark
                          : GovernorDashboardTokens.subtitle),
                )
              : null,
          onTap: onToggle,
        ),
        AnimatedSize(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
          alignment: Alignment.topCenter,
          child: showChildren
              ? Padding(
                  padding: const EdgeInsets.only(left: 18, top: 4),
                  child: Column(
                    children: [
                      for (var i = 0; i < item.children.length; i++) ...[
                        if (i > 0) const SizedBox(height: 4),
                        _NavTile(
                          item: item.children[i],
                          expanded: true,
                          onOrange: onOrange,
                          selected: item.children[i].pageIndex == selectedIndex,
                          dense: true,
                          onTap: () {
                            final page = item.children[i].pageIndex;
                            if (page != null) onSelect(page);
                          },
                        ),
                      ],
                    ],
                  ),
                )
              : const SizedBox(width: double.infinity),
        ),
      ],
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

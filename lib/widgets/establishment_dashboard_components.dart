import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:atmos_trs_system/widgets/atmos_square_logo.dart';
import 'package:atmos_trs_system/widgets/establishment_dash_tokens.dart';

/// Building blocks for the establishment (hotel) dashboard chrome.

class EstablishmentNavEntry {
  const EstablishmentNavEntry({
    required this.icon,
    required this.label,
    this.badgeCount = 0,
    this.section,
  });

  final IconData icon;
  final String label;
  final int badgeCount;

  /// Group heading shown above this entry (first entry of each group).
  final String? section;
}

/// Full-height orange sidebar: brand strip, nav, hotel artwork, log out.
class EstablishmentSidebar extends StatelessWidget {
  const EstablishmentSidebar({
    super.key,
    required this.businessName,
    required this.subtitle,
    required this.items,
    required this.selectedIndex,
    required this.onSelect,
    required this.onLogout,
    this.expanded = true,
    this.width,
    this.onToggle,
  });

  static const String artAsset = 'assets/images/ae_sidebar_hotel_art.png';

  /// Keeps the light artwork strokes as white, drops the flat orange backdrop.
  static const ColorFilter _artToWhite = ColorFilter.matrix(<double>[
    0, 0, 0, 0, 255, //
    0, 0, 0, 0, 255, //
    0, 0, 0, 0, 255, //
    0, 0, 1.4, 0, -40, //
  ]);

  final String businessName;
  final String subtitle;
  final List<EstablishmentNavEntry> items;
  final int selectedIndex;
  final ValueChanged<int> onSelect;
  final VoidCallback onLogout;
  final bool expanded;
  final double? width;
  final VoidCallback? onToggle;

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.paddingOf(context).bottom;
    final resolvedWidth =
        width ??
        (expanded
            ? AeDashTokens.sidebarExpanded
            : AeDashTokens.sidebarCollapsed);

    return AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      width: resolvedWidth,
      clipBehavior: Clip.hardEdge,
      decoration: BoxDecoration(
        gradient: AeDashTokens.sidebarRichGradient,
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF7C2D12).withValues(alpha: 0.18),
            blurRadius: 18,
            offset: const Offset(4, 0),
          ),
        ],
      ),
      child: LayoutBuilder(
        builder: (context, c) => _content(
          // Stay compact until the width animation has room for labels.
          full: expanded && c.maxWidth >= AeDashTokens.sidebarExpanded - 8,
          bottomInset: bottomInset,
        ),
      ),
    );
  }

  Widget _content({required bool full, required double bottomInset}) {
    return Stack(
      children: [
        const Positioned.fill(
          child: IgnorePointer(
            child: CustomPaint(painter: _SidebarGlowPainter()),
          ),
        ),
        if (full)
          Positioned(
            left: -70,
            right: -70,
            bottom: 30 + bottomInset,
            child: IgnorePointer(
              child: Opacity(
                opacity: 0.42,
                child: ColorFiltered(
                  colorFilter: _artToWhite,
                  child: Image.asset(
                    artAsset,
                    fit: BoxFit.fitWidth,
                    alignment: Alignment.bottomCenter,
                    errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                  ),
                ),
              ),
            ),
          ),
        SafeArea(
          right: false,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (full) _brandStrip() else _collapsedToggle(),
              const SizedBox(height: 12),
              Expanded(child: _nav(full)),
              _logout(full),
              SizedBox(height: 16 + bottomInset),
            ],
          ),
        ),
      ],
    );
  }

  Widget _brandStrip() {
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 14, 12, 4),
      padding: const EdgeInsets.fromLTRB(8, 8, 2, 8),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Colors.white.withValues(alpha: 0.24),
            Colors.white.withValues(alpha: 0.10),
          ],
        ),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white.withValues(alpha: 0.28)),
      ),
      child: Row(
        children: [
          Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF7C2D12).withValues(alpha: 0.25),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: const AtmosSquareLogo(
              height: 44,
              width: 44,
              padding: EdgeInsets.all(4),
              borderRadius: 12,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  businessName,
                  style: AeDashTokens.section(size: 15, color: Colors.white),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: AeDashTokens.body(
                    size: 12,
                    color: Colors.white.withValues(alpha: 0.88),
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          if (onToggle != null)
            IconButton(
              tooltip: 'Collapse sidebar',
              onPressed: onToggle,
              visualDensity: VisualDensity.compact,
              icon: const Icon(
                Icons.close_rounded,
                color: Colors.white,
                size: 20,
              ),
            ),
        ],
      ),
    );
  }

  Widget _collapsedToggle() {
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Column(
        children: [
          const AtmosSquareLogo(
            height: 40,
            width: 40,
            padding: EdgeInsets.all(4),
            borderRadius: 12,
          ),
          const SizedBox(height: 8),
          IconButton(
            tooltip: 'Expand sidebar',
            onPressed: onToggle,
            icon: const Icon(Icons.menu_rounded, color: Colors.white),
          ),
        ],
      ),
    );
  }

  Widget _nav(bool full) {
    return ListView(
      padding: EdgeInsets.symmetric(horizontal: full ? 12 : 10),
      children: [
        for (var i = 0; i < items.length; i++) ...[
          if (items[i].section != null) _sectionHeader(items[i].section!, i, full),
          _navTile(i, full),
          const SizedBox(height: 2),
        ],
      ],
    );
  }

  Widget _sectionHeader(String label, int index, bool full) {
    if (!full) {
      if (index == 0) return const SizedBox.shrink();
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        child: Divider(
          height: 1,
          thickness: 1,
          color: Colors.white.withValues(alpha: 0.3),
        ),
      );
    }
    return Padding(
      padding: EdgeInsets.fromLTRB(14, index == 0 ? 6 : 18, 14, 8),
      child: Row(
        children: [
          Text(
            label.toUpperCase(),
            style: AeDashTokens.body(
              size: 11,
              color: Colors.white.withValues(alpha: 0.85),
              weight: FontWeight.w800,
            ).copyWith(letterSpacing: 1.2),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Container(
              height: 1,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    Colors.white.withValues(alpha: 0.35),
                    Colors.white.withValues(alpha: 0.0),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _navTile(int index, bool full) {
    final item = items[index];
    final selected = index == selectedIndex;
    final fg = selected ? AeDashTokens.accent : Colors.white;
    final icon = (!full && item.badgeCount > 0)
        ? Badge(
            label: Text('${item.badgeCount}'),
            child: Icon(item.icon, color: fg, size: 21),
          )
        : Icon(item.icon, color: fg, size: 21);

    return Tooltip(
      message: full ? '' : item.label,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => onSelect(index),
          borderRadius: BorderRadius.circular(14),
          hoverColor: Colors.white.withValues(alpha: 0.12),
          splashColor: Colors.white.withValues(alpha: 0.16),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            height: 48,
            padding: EdgeInsets.symmetric(horizontal: full ? 14 : 0),
            decoration: BoxDecoration(
              color: selected ? AeDashTokens.cream : Colors.transparent,
              borderRadius: BorderRadius.circular(14),
              boxShadow: selected
                  ? [
                      BoxShadow(
                        color: const Color(0xFF9A3412).withValues(alpha: 0.18),
                        blurRadius: 12,
                        offset: const Offset(0, 4),
                      ),
                    ]
                  : null,
            ),
            child: Row(
              mainAxisAlignment: full
                  ? MainAxisAlignment.start
                  : MainAxisAlignment.center,
              children: [
                icon,
                if (full) ...[
                  const SizedBox(width: 14),
                  Expanded(
                    child: Text(
                      item.label,
                      style: AeDashTokens.body(
                        size: 14,
                        color: fg,
                        weight: selected ? FontWeight.w700 : FontWeight.w500,
                      ),
                    ),
                  ),
                  if (item.badgeCount > 0)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: selected ? AeDashTokens.accent : Colors.white,
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        '${item.badgeCount}',
                        style: AeDashTokens.body(
                          size: 11,
                          color: selected ? Colors.white : AeDashTokens.accent,
                          weight: FontWeight.w800,
                        ),
                      ),
                    ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _logout(bool full) {
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: full ? 16 : 12),
      child: Tooltip(
        message: full ? '' : 'Log out',
        child: Material(
          color: AeDashTokens.cream,
          borderRadius: BorderRadius.circular(14),
          elevation: 0,
          child: InkWell(
            onTap: onLogout,
            borderRadius: BorderRadius.circular(14),
            child: Container(
              height: 50,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(14),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF9A3412).withValues(alpha: 0.20),
                    blurRadius: 14,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(
                    Icons.logout_rounded,
                    color: AeDashTokens.accent,
                    size: 20,
                  ),
                  if (full) ...[
                    const SizedBox(width: 10),
                    Text(
                      'Log out',
                      style: AeDashTokens.body(
                        size: 14,
                        color: const Color(0xFFC2410C),
                        weight: FontWeight.w700,
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

class EstablishmentHeroTag {
  const EstablishmentHeroTag(this.icon, this.label);
  final IconData icon;
  final String label;
}

/// Orange/peach welcome banner with hotel-room artwork on the right.
class EstablishmentHeroHeader extends StatelessWidget {
  const EstablishmentHeroHeader({
    super.key,
    required this.greeting,
    required this.businessName,
    required this.tags,
    this.trailing,
    this.flush = false,
  });

  static const String photoAsset = 'assets/images/ae_hero_hotel_room.png';

  /// Photo strip width: ~3:1 of the banner height so the 16:9 photo is not
  /// over-cropped (keeps headboard, pillows and duvet in frame).
  static double heroPhotoWidth(double maxWidth, bool compact, double height) =>
      compact ? maxWidth * 0.7 : math.min(maxWidth * 0.55, height * 3.0);

  /// Bed sits in the lower-right of the photo.
  static const Alignment heroPhotoAlignment = Alignment(0.4, 0.6);

  /// Lifts the warm, dim hotel photo so the bed reads clearly.
  static const ColorFilter heroPhotoBrighten = ColorFilter.matrix(<double>[
    1.18, 0, 0, 0, 14, //
    0, 1.18, 0, 0, 14, //
    0, 0, 1.18, 0, 18, //
    0, 0, 0, 1, 0, //
  ]);

  final String greeting;
  final String businessName;
  final List<EstablishmentHeroTag> tags;
  final Widget? trailing;

  /// Edge-to-edge banner: square corners, no drop shadow.
  final bool flush;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, c) {
        final compact = c.maxWidth < 620;
        final photoWidth = heroPhotoWidth(c.maxWidth, compact, 140);

        return Container(
          constraints: BoxConstraints(minHeight: compact ? 150 : 136),
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            borderRadius: flush ? BorderRadius.zero : BorderRadius.circular(20),
            gradient: AeDashTokens.bannerGradient,
            boxShadow: flush
                ? null
                : [
                    BoxShadow(
                      color: AeDashTokens.accent.withValues(alpha: 0.22),
                      blurRadius: 20,
                      offset: const Offset(0, 8),
                    ),
                  ],
          ),
          child: Stack(
            children: [
              const Positioned.fill(child: AeBannerBackdrop()),
              Positioned(
                right: 0,
                top: 0,
                bottom: 0,
                width: photoWidth,
                child: IgnorePointer(
                  child: ShaderMask(
                    blendMode: BlendMode.dstIn,
                    shaderCallback: (rect) => const LinearGradient(
                      begin: Alignment.centerLeft,
                      end: Alignment.centerRight,
                      colors: [Colors.transparent, Colors.black, Colors.black],
                      stops: [0.0, 0.2, 1.0],
                    ).createShader(rect),
                    child: Opacity(
                      opacity: compact ? 0.45 : 1.0,
                      child: ColorFiltered(
                        colorFilter: heroPhotoBrighten,
                        child: Image.asset(
                          photoAsset,
                          fit: BoxFit.cover,
                          alignment: heroPhotoAlignment,
                          errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              Padding(
                padding: EdgeInsets.fromLTRB(
                  compact ? 16 : 22,
                  compact ? 16 : 20,
                  compact ? 12 : 16,
                  compact ? 16 : 20,
                ),
                child: compact ? _compactBody() : _wideBody(),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _texts({required bool compact}) {
    final hour = DateTime.now().hour;
    final timeIcon = hour < 17
        ? Icons.wb_sunny_rounded
        : Icons.nights_stay_rounded;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.fromLTRB(6, 3, 10, 3),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.18),
            borderRadius: BorderRadius.circular(999),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(timeIcon, size: 14, color: const Color(0xFFFEF3C7)),
              const SizedBox(width: 6),
              Text(
                '$greeting,',
                style: AeDashTokens.body(
                  size: compact ? 12 : 13,
                  color: Colors.white,
                  weight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 6),
        Text(
          '$businessName 👋',
          style: AeDashTokens.heading(
            size: compact ? 22 : 27,
            color: Colors.white,
          ),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 6,
          children: [for (final t in tags) _tag(t)],
        ),
      ],
    );
  }

  Widget _wideBody() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(child: _texts(compact: false)),
        if (trailing != null) ...[const SizedBox(width: 8), trailing!],
      ],
    );
  }

  Widget _compactBody() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(child: _texts(compact: true)),
        if (trailing != null) ...[const SizedBox(width: 8), trailing!],
      ],
    );
  }

  Widget _tag(EstablishmentHeroTag tag) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.white.withValues(alpha: 0.38)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(tag.icon, size: 13, color: Colors.white),
          const SizedBox(width: 5),
          Text(
            tag.label,
            style: AeDashTokens.body(
              size: 11.5,
              color: Colors.white,
              weight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

/// White pill with a colored status dot and optional dropdown chevron.
class AeStatusPill extends StatelessWidget {
  const AeStatusPill({
    super.key,
    required this.label,
    required this.color,
    this.showChevron = false,
  });

  final String label;
  final Color color;
  final bool showChevron;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 7, 10, 7),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(999),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.10),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 7),
          Text(
            label,
            style: AeDashTokens.body(
              size: 12.5,
              color: AeDashTokens.text,
              weight: FontWeight.w700,
            ),
          ),
          if (showChevron) ...[
            const SizedBox(width: 6),
            const Icon(
              Icons.keyboard_arrow_down_rounded,
              size: 18,
              color: AeDashTokens.text,
            ),
          ],
        ],
      ),
    );
  }
}

/// Full-width notice card (e.g. account approved) with optional close.
class AeAlertBanner extends StatelessWidget {
  const AeAlertBanner({
    super.key,
    required this.title,
    required this.message,
    required this.icon,
    required this.color,
    required this.background,
    required this.borderColor,
    this.onClose,
  });

  final String title;
  final String message;
  final IconData icon;
  final Color color;
  final Color background;
  final Color borderColor;
  final VoidCallback? onClose;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: borderColor),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 28),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: AeDashTokens.section(size: 13.5)),
                const SizedBox(height: 2),
                Text(message, style: AeDashTokens.body(size: 12.5)),
              ],
            ),
          ),
          if (onClose != null)
            IconButton(
              tooltip: 'Dismiss',
              onPressed: onClose,
              visualDensity: VisualDensity.compact,
              icon: Icon(Icons.close_rounded, size: 18, color: color),
            ),
        ],
      ),
    );
  }
}

/// KPI card: solid icon tile, title/subtitle, big number, chevron, soft wave.
class AeSummaryCard extends StatelessWidget {
  const AeSummaryCard({
    super.key,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.icon,
    required this.color,
    this.onTap,
  });

  final String title;
  final String subtitle;
  final String value;
  final IconData icon;
  final Color color;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AeDashTokens.radiusXl),
        child: Ink(
          decoration: AeDashTokens.panelDecoration(),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(AeDashTokens.radiusXl),
            child: Stack(
              children: [
                Positioned.fill(
                  child: IgnorePointer(
                    child: CustomPaint(painter: _SoftWavePainter(color)),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(18, 18, 12, 18),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: 50,
                        height: 50,
                        decoration: BoxDecoration(
                          color: color,
                          borderRadius: BorderRadius.circular(14),
                          boxShadow: [
                            BoxShadow(
                              color: color.withValues(alpha: 0.30),
                              blurRadius: 10,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: Icon(icon, color: Colors.white, size: 26),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              title,
                              style: AeDashTokens.section(size: 13.5),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 2),
                            Text(
                              subtitle,
                              style: AeDashTokens.body(size: 11.5),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 10),
                            Text(value, style: AeDashTokens.number(size: 28)),
                          ],
                        ),
                      ),
                      if (onTap != null)
                        Icon(
                          Icons.chevron_right_rounded,
                          color: color,
                          size: 22,
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SoftWavePainter extends CustomPainter {
  _SoftWavePainter(this.color);
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final back = Path()
      ..moveTo(w * 0.30, h)
      ..cubicTo(w * 0.50, h * 0.55, w * 0.70, h * 0.95, w, h * 0.38)
      ..lineTo(w, h)
      ..close();
    final front = Path()
      ..moveTo(w * 0.42, h)
      ..cubicTo(w * 0.62, h * 0.72, w * 0.80, h * 1.0, w, h * 0.62)
      ..lineTo(w, h)
      ..close();
    final rect = Offset.zero & size;
    canvas.drawPath(
      back,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            color.withValues(alpha: 0.10),
            color.withValues(alpha: 0.02),
          ],
        ).createShader(rect),
    );
    canvas.drawPath(
      front,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            color.withValues(alpha: 0.14),
            color.withValues(alpha: 0.04),
          ],
        ).createShader(rect),
    );
  }

  @override
  bool shouldRepaint(covariant _SoftWavePainter old) => old.color != color;
}

/// Large white card shell with icon header used across Home sections.
class AePanelCard extends StatelessWidget {
  const AePanelCard({
    super.key,
    required this.title,
    required this.icon,
    required this.child,
    this.subtitle,
    this.iconColor = AeDashTokens.accent,
    this.trailing,
    this.padding = const EdgeInsets.fromLTRB(20, 18, 20, 20),
  });

  final String title;
  final String? subtitle;
  final IconData icon;
  final Color iconColor;
  final Widget? trailing;
  final Widget child;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: padding,
      decoration: AeDashTokens.panelDecoration(),
      child: LayoutBuilder(
        builder: (context, c) {
          final stackTrailing = trailing != null && c.maxWidth < 420;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      color: iconColor.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(11),
                    ),
                    child: Icon(icon, color: iconColor, size: 20),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(title, style: AeDashTokens.section(size: 15)),
                        if (subtitle != null && subtitle!.isNotEmpty) ...[
                          const SizedBox(height: 2),
                          Text(subtitle!, style: AeDashTokens.body(size: 12)),
                        ],
                      ],
                    ),
                  ),
                  if (trailing != null && !stackTrailing) ...[
                    const SizedBox(width: 8),
                    trailing!,
                  ],
                ],
              ),
              if (stackTrailing) ...[
                const SizedBox(height: 10),
                Align(alignment: Alignment.centerLeft, child: trailing!),
              ],
              const SizedBox(height: 16),
              child,
            ],
          );
        },
      ),
    );
  }
}

/// Tinted status tile inside the room snapshot card.
class AeRoomStatusCard extends StatelessWidget {
  const AeRoomStatusCard({
    super.key,
    required this.label,
    required this.value,
    required this.caption,
    required this.icon,
    required this.color,
  });

  final String label;
  final String value;
  final String caption;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: color, size: 22),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: AeDashTokens.body(
                    size: 12,
                    color: AeDashTokens.text,
                    weight: FontWeight.w600,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(value, style: AeDashTokens.number(size: 22, color: color)),
                Text(
                  caption,
                  style: AeDashTokens.body(size: 11),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Chart card: [AePanelCard] with a fixed-height body.
class AeAnalyticsCard extends StatelessWidget {
  const AeAnalyticsCard({
    super.key,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.child,
    this.iconColor = AeDashTokens.accent,
    this.trailing,
    this.height = 210,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final Color iconColor;
  final Widget? trailing;
  final Widget child;
  final double height;

  @override
  Widget build(BuildContext context) {
    return AePanelCard(
      title: title,
      subtitle: subtitle,
      icon: icon,
      iconColor: iconColor,
      trailing: trailing,
      child: SizedBox(height: height, child: child),
    );
  }
}

/// Small outlined action (e.g. "View Rooms", "View All", dropdown triggers).
class AeOutlineAction extends StatelessWidget {
  const AeOutlineAction({
    super.key,
    required this.label,
    this.leading,
    this.trailing,
    this.onTap,
  });

  final String label;
  final IconData? leading;
  final IconData? trailing;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final body = Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AeDashTokens.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (leading != null) ...[
            Icon(leading, size: 15, color: AeDashTokens.text),
            const SizedBox(width: 6),
          ],
          Text(
            label,
            style: AeDashTokens.body(
              size: 12,
              color: AeDashTokens.text,
              weight: FontWeight.w600,
            ),
          ),
          if (trailing != null) ...[
            const SizedBox(width: 6),
            Icon(trailing, size: 16, color: AeDashTokens.text),
          ],
        ],
      ),
    );
    if (onTap == null) return body;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: body,
      ),
    );
  }
}

/// Dropdown styled like [AeOutlineAction].
class AeDropdownAction<T> extends StatelessWidget {
  const AeDropdownAction({
    super.key,
    required this.value,
    required this.options,
    required this.onChanged,
    this.leading,
  });

  final T value;
  final Map<T, String> options;
  final ValueChanged<T> onChanged;
  final IconData? leading;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<T>(
      tooltip: '',
      initialValue: value,
      onSelected: onChanged,
      position: PopupMenuPosition.under,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      itemBuilder: (_) => [
        for (final e in options.entries)
          PopupMenuItem<T>(
            value: e.key,
            child: Text(
              e.value,
              style: AeDashTokens.body(
                size: 13,
                color: AeDashTokens.text,
                weight: e.key == value ? FontWeight.w700 : FontWeight.w500,
              ),
            ),
          ),
      ],
      child: AeOutlineAction(
        label: options[value] ?? '',
        leading: leading,
        trailing: Icons.keyboard_arrow_down_rounded,
      ),
    );
  }
}

enum AeEmptyArt {
  chart,
  bed,
  document,
  people,
  globe,
  weekday,
  review,
  calendar,
}

/// Centered empty state with a drawn illustration (or [imageAsset]) and an
/// optional call-to-action button.
class AeIllustratedEmpty extends StatelessWidget {
  const AeIllustratedEmpty({
    super.key,
    required this.title,
    required this.message,
    this.art = AeEmptyArt.document,
    this.imageAsset,
    this.imageHeight = 150,
    this.actionLabel,
    this.actionIcon,
    this.onAction,
  });

  final String title;
  final String message;
  final AeEmptyArt art;
  final String? imageAsset;
  final double imageHeight;
  final String? actionLabel;
  final IconData? actionIcon;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (imageAsset != null)
              Image.asset(
                imageAsset!,
                height: imageHeight,
                fit: BoxFit.contain,
                errorBuilder: (_, __, ___) => _art(),
              )
            else
              _art(),
            const SizedBox(height: 12),
            Text(
              title,
              textAlign: TextAlign.center,
              style: AeDashTokens.section(size: 13.5),
            ),
            const SizedBox(height: 3),
            Text(
              message,
              textAlign: TextAlign.center,
              style: AeDashTokens.body(size: 12),
            ),
            if (actionLabel != null && onAction != null) ...[
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: onAction,
                icon: Icon(actionIcon ?? Icons.arrow_forward_rounded, size: 18),
                label: Text(actionLabel!),
                style: FilledButton.styleFrom(
                  backgroundColor: AeDashTokens.accent,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 22,
                    vertical: 14,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  textStyle: AeDashTokens.body(
                    size: 13.5,
                    color: Colors.white,
                    weight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  static Widget _iconBlob({
    required Color blob,
    required IconData icon,
    required Color color,
    IconData? left,
    IconData? right,
    Color? sideColor,
  }) {
    final side = sideColor ?? color.withValues(alpha: 0.55);
    return SizedBox(
      width: 150,
      height: 84,
      child: Stack(
        alignment: Alignment.bottomCenter,
        children: [
          Positioned(
            bottom: 0,
            child: Container(
              width: 150,
              height: 58,
              decoration: BoxDecoration(
                color: blob,
                borderRadius: BorderRadius.circular(40),
              ),
            ),
          ),
          Positioned(bottom: 8, child: Icon(icon, size: 56, color: color)),
          if (left != null)
            Positioned(
              bottom: 12,
              left: 20,
              child: Icon(left, size: 24, color: side),
            ),
          if (right != null)
            Positioned(
              bottom: 14,
              right: 20,
              child: Icon(right, size: 22, color: side),
            ),
        ],
      ),
    );
  }

  Widget _art() {
    switch (art) {
      case AeEmptyArt.people:
        return _iconBlob(
          blob: const Color(0xFFFFEDD5),
          icon: Icons.groups_rounded,
          color: AeDashTokens.secondary,
          left: Icons.person_rounded,
          right: Icons.person_rounded,
          sideColor: const Color(0xFFA78BFA),
        );
      case AeEmptyArt.globe:
        return _iconBlob(
          blob: const Color(0xFFE0F2FE),
          icon: Icons.public_rounded,
          color: const Color(0xFF60A5FA),
          right: Icons.location_on_rounded,
          sideColor: AeDashTokens.accent,
        );
      case AeEmptyArt.weekday:
        return SizedBox(
          width: 150,
          height: 84,
          child: Stack(
            alignment: Alignment.bottomCenter,
            children: [
              Positioned(
                bottom: 0,
                child: Container(
                  width: 150,
                  height: 58,
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFEDD5).withValues(alpha: 0.8),
                    borderRadius: BorderRadius.circular(40),
                  ),
                ),
              ),
              Positioned(
                bottom: 8,
                left: 38,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    _bar(22, const Color(0xFFFDBA74)),
                    const SizedBox(width: 6),
                    _bar(40, const Color(0xFFFB923C)),
                    const SizedBox(width: 6),
                    _bar(30, AeDashTokens.accent),
                  ],
                ),
              ),
              const Positioned(
                bottom: 30,
                right: 26,
                child: Icon(
                  Icons.schedule_rounded,
                  size: 30,
                  color: Color(0xFF8B5CF6),
                ),
              ),
            ],
          ),
        );
      case AeEmptyArt.review:
        return _iconBlob(
          blob: const Color(0xFFFFEDD5),
          icon: Icons.forum_rounded,
          color: AeDashTokens.secondary,
          left: Icons.star_rounded,
          right: Icons.star_rounded,
          sideColor: AeDashTokens.warning,
        );
      case AeEmptyArt.calendar:
        return _iconBlob(
          blob: const Color(0xFFF1F5F9),
          icon: Icons.event_available_rounded,
          color: AeDashTokens.secondary,
        );
      case AeEmptyArt.chart:
        return SizedBox(
          width: 150,
          height: 84,
          child: Stack(
            alignment: Alignment.bottomCenter,
            children: [
              Positioned(
                bottom: 0,
                child: Container(
                  width: 150,
                  height: 58,
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFEDD5).withValues(alpha: 0.8),
                    borderRadius: BorderRadius.circular(40),
                  ),
                ),
              ),
              Positioned(bottom: 30, left: 18, child: _cloud(30)),
              Positioned(bottom: 36, right: 14, child: _cloud(24)),
              Positioned(
                bottom: 8,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    _bar(18, const Color(0xFFFDBA74)),
                    const SizedBox(width: 7),
                    _bar(32, const Color(0xFFFB923C)),
                    const SizedBox(width: 7),
                    _bar(50, AeDashTokens.accent),
                  ],
                ),
              ),
            ],
          ),
        );
      case AeEmptyArt.bed:
        return SizedBox(
          width: 150,
          height: 84,
          child: Stack(
            alignment: Alignment.bottomCenter,
            children: [
              Positioned(
                bottom: 0,
                child: Container(
                  width: 150,
                  height: 58,
                  decoration: BoxDecoration(
                    color: const Color(0xFFEDE9FE).withValues(alpha: 0.9),
                    borderRadius: BorderRadius.circular(40),
                  ),
                ),
              ),
              const Positioned(
                bottom: 6,
                child: Icon(
                  Icons.king_bed_rounded,
                  size: 58,
                  color: Color(0xFFA78BFA),
                ),
              ),
              const Positioned(
                bottom: 10,
                left: 22,
                child: Icon(
                  Icons.local_florist_rounded,
                  size: 26,
                  color: Color(0xFFC4B5FD),
                ),
              ),
              const Positioned(
                bottom: 12,
                right: 22,
                child: Icon(
                  Icons.light_rounded,
                  size: 22,
                  color: Color(0xFFC4B5FD),
                ),
              ),
            ],
          ),
        );
      case AeEmptyArt.document:
        return Container(
          width: 44,
          height: 44,
          decoration: const BoxDecoration(
            color: AeDashTokens.mutedSurface,
            shape: BoxShape.circle,
          ),
          child: const Icon(
            Icons.description_outlined,
            size: 22,
            color: AeDashTokens.muted,
          ),
        );
    }
  }

  static Widget _bar(double h, Color c) => Container(
    width: 14,
    height: h,
    decoration: BoxDecoration(
      color: c,
      borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
    ),
  );

  static Widget _cloud(double w) => Container(
    width: w,
    height: w * 0.42,
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(w),
    ),
  );
}

/// Lays children in equal columns, wrapping to [minItemWidth]-based rows.
class AeResponsiveGrid extends StatelessWidget {
  const AeResponsiveGrid({
    super.key,
    required this.children,
    this.minItemWidth = 220,
    this.maxColumns = 4,
    this.spacing = 16,
  });

  final List<Widget> children;
  final double minItemWidth;
  final int maxColumns;
  final double spacing;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, c) {
        var columns = ((c.maxWidth + spacing) / (minItemWidth + spacing))
            .floor()
            .clamp(1, maxColumns);
        if (columns == 3 && children.length == 4) columns = 2;
        final rows = <Widget>[];
        for (var i = 0; i < children.length; i += columns) {
          final slice = children.sublist(
            i,
            (i + columns).clamp(0, children.length),
          );
          rows.add(
            IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (var j = 0; j < columns; j++) ...[
                    if (j > 0) SizedBox(width: spacing),
                    Expanded(
                      child: j < slice.length
                          ? slice[j]
                          : const SizedBox.shrink(),
                    ),
                  ],
                ],
              ),
            ),
          );
        }
        return Column(
          children: [
            for (var i = 0; i < rows.length; i++) ...[
              if (i > 0) SizedBox(height: spacing),
              rows[i],
            ],
          ],
        );
      },
    );
  }
}

/// Page banner for Rooms / Insights: white icon tile, title, subtitle, note,
/// optional action and hotel-room artwork (or custom [art]) on the right.
class AePageHero extends StatelessWidget {
  const AePageHero({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    this.note,
    this.trailing,
    this.art,
    this.flush = false,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final String? note;
  final Widget? trailing;

  /// Decorative widget painted over the photo on wide layouts.
  final Widget? art;

  /// Edge-to-edge banner: square corners, no drop shadow.
  final bool flush;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, c) {
        final compact = c.maxWidth < 620;
        final photoWidth = EstablishmentHeroHeader.heroPhotoWidth(
          c.maxWidth,
          compact,
          150,
        );
        return Container(
          constraints: BoxConstraints(minHeight: compact ? 140 : 150),
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            borderRadius: flush ? BorderRadius.zero : BorderRadius.circular(20),
            gradient: AeDashTokens.bannerGradient,
            boxShadow: flush
                ? null
                : [
                    BoxShadow(
                      color: AeDashTokens.accent.withValues(alpha: 0.22),
                      blurRadius: 20,
                      offset: const Offset(0, 8),
                    ),
                  ],
          ),
          child: Stack(
            children: [
              const Positioned.fill(child: AeBannerBackdrop()),
              Positioned(
                right: 0,
                top: 0,
                bottom: 0,
                width: photoWidth,
                child: IgnorePointer(
                  child: ShaderMask(
                    blendMode: BlendMode.dstIn,
                    shaderCallback: (rect) => const LinearGradient(
                      begin: Alignment.centerLeft,
                      end: Alignment.centerRight,
                      colors: [Colors.transparent, Colors.black, Colors.black],
                      stops: [0.0, 0.2, 1.0],
                    ).createShader(rect),
                    child: Opacity(
                      opacity: compact ? 0.4 : 1.0,
                      child: ColorFiltered(
                        colorFilter: EstablishmentHeroHeader.heroPhotoBrighten,
                        child: Image.asset(
                          EstablishmentHeroHeader.photoAsset,
                          fit: BoxFit.cover,
                          alignment: EstablishmentHeroHeader.heroPhotoAlignment,
                          errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              if (art != null && !compact)
                Positioned(
                  right: photoWidth * 0.86,
                  bottom: 18,
                  child: IgnorePointer(child: art!),
                ),
              Padding(
                padding: EdgeInsets.fromLTRB(
                  compact ? 16 : 24,
                  compact ? 16 : 22,
                  compact ? 16 : 22,
                  compact ? 16 : 22,
                ),
                child: compact
                    ? _compactBody()
                    : _wideBody(art == null ? 0 : photoWidth * 0.86 + 80),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _iconTile(double size) => Container(
    width: size,
    height: size,
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(size * 0.28),
      boxShadow: [
        BoxShadow(
          color: const Color(0xFF9A3412).withValues(alpha: 0.18),
          blurRadius: 12,
          offset: const Offset(0, 4),
        ),
      ],
    ),
    child: Icon(icon, color: AeDashTokens.accent, size: size * 0.5),
  );

  Widget _texts({required bool compact}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          title,
          style: AeDashTokens.heading(
            size: compact ? 22 : 28,
            color: Colors.white,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          subtitle,
          style: AeDashTokens.body(
            size: compact ? 13 : 14.5,
            color: Colors.white,
            weight: FontWeight.w600,
          ),
        ),
        if (note != null && note!.isNotEmpty) ...[
          const SizedBox(height: 8),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: Text(
              note!,
              style: AeDashTokens.body(
                size: 12.5,
                color: Colors.white.withValues(alpha: 0.94),
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _wideBody(double artReserve) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        _iconTile(72),
        const SizedBox(width: 20),
        Expanded(child: _texts(compact: false)),
        if (artReserve > 0) SizedBox(width: artReserve),
        if (trailing != null) ...[const SizedBox(width: 12), trailing!],
      ],
    );
  }

  Widget _compactBody() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            _iconTile(52),
            const Spacer(),
            if (trailing != null) trailing!,
          ],
        ),
        const SizedBox(height: 12),
        _texts(compact: true),
      ],
    );
  }
}

/// Soft glows, dot grid and a wave line layered over orange banners.
class AeBannerBackdrop extends StatelessWidget {
  const AeBannerBackdrop({super.key});

  @override
  Widget build(BuildContext context) {
    return const IgnorePointer(
      child: CustomPaint(painter: _BannerBackdropPainter()),
    );
  }
}

class _BannerBackdropPainter extends CustomPainter {
  const _BannerBackdropPainter();

  void _glow(Canvas canvas, Offset c, double r, double alpha, Color color) {
    final rect = Rect.fromCircle(center: c, radius: r);
    canvas.drawCircle(
      c,
      r,
      Paint()
        ..shader = RadialGradient(
          colors: [
            color.withValues(alpha: alpha),
            color.withValues(alpha: 0),
          ],
        ).createShader(rect),
    );
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final w = size.width;
    final h = size.height;

    _glow(canvas, Offset(w * 0.08, -h * 0.35), h * 1.1, 0.22, Colors.white);
    _glow(canvas, Offset(w * 0.42, h * 1.25), h * 0.95, 0.16, const Color(0xFFFDE68A));
    final dot = Paint()..color = Colors.white.withValues(alpha: 0.16);
    const gap = 14.0;
    final startX = w * 0.26;
    for (var r = 0; r < 4; r++) {
      for (var c = 0; c < 7; c++) {
        canvas.drawCircle(
          Offset(startX + c * gap, 16 + r * gap),
          1.4,
          dot,
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant _BannerBackdropPainter oldDelegate) => false;
}

class _SidebarGlowPainter extends CustomPainter {
  const _SidebarGlowPainter();

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    void glow(Offset c, double r, double alpha, Color color) {
      canvas.drawCircle(
        c,
        r,
        Paint()
          ..shader = RadialGradient(
            colors: [
              color.withValues(alpha: alpha),
              color.withValues(alpha: 0),
            ],
          ).createShader(Rect.fromCircle(center: c, radius: r)),
      );
    }

    final w = size.width;
    final h = size.height;
    glow(Offset(w * 1.05, -20), 190, 0.26, Colors.white);
    glow(Offset(-40, h * 0.42), 160, 0.12, const Color(0xFFFDE68A));
    glow(Offset(w * 0.9, h * 0.78), 180, 0.2, const Color(0xFF7C2D12));

    final ring = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2
      ..color = Colors.white.withValues(alpha: 0.1);
    canvas.drawCircle(Offset(w + 10, 40), 90, ring);
    canvas.drawCircle(Offset(w + 10, 40), 130, ring..color = Colors.white.withValues(alpha: 0.06));
  }

  @override
  bool shouldRepaint(covariant _SidebarGlowPainter oldDelegate) => false;
}

/// White pill button used on orange heroes (e.g. "Edit rooms").
class AeHeroButton extends StatelessWidget {
  const AeHeroButton({
    super.key,
    required this.label,
    required this.icon,
    required this.onPressed,
  });

  final String label;
  final IconData icon;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return FilledButton.icon(
      onPressed: onPressed,
      icon: Icon(icon, size: 18),
      label: Text(label),
      style: FilledButton.styleFrom(
        backgroundColor: Colors.white,
        foregroundColor: AeDashTokens.text,
        elevation: 2,
        shadowColor: const Color(0xFF9A3412).withValues(alpha: 0.3),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        textStyle: AeDashTokens.body(
          size: 13.5,
          color: AeDashTokens.text,
          weight: FontWeight.w700,
        ),
      ),
    );
  }
}

/// KPI tile: tinted icon, big number, label, corner glyph and soft wave.
class AeStatCard extends StatelessWidget {
  const AeStatCard({
    super.key,
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
    this.cornerIcon,
  });

  final String label;
  final String value;
  final IconData icon;
  final Color color;
  final IconData? cornerIcon;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: AeDashTokens.panelDecoration(),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AeDashTokens.radiusXl),
        child: Stack(
          children: [
            Positioned.fill(
              child: IgnorePointer(
                child: CustomPaint(painter: _SoftWavePainter(color)),
              ),
            ),
            if (cornerIcon != null)
              Positioned(
                top: 14,
                right: 14,
                child: Icon(
                  cornerIcon,
                  size: 18,
                  color: color.withValues(alpha: 0.45),
                ),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 18, 18, 18),
              child: Row(
                children: [
                  Container(
                    width: 52,
                    height: 52,
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.13),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Icon(icon, color: color, size: 26),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(value, style: AeDashTokens.number(size: 28)),
                        Text(
                          label,
                          style: AeDashTokens.body(
                            size: 13,
                            color: AeDashTokens.muted,
                            weight: FontWeight.w600,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Rounded filter pill with a status dot; selected shows cream + check.
class AeFilterPill extends StatelessWidget {
  const AeFilterPill({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
    this.dotColor,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final Color? dotColor;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: BoxDecoration(
            color: selected ? const Color(0xFFFFEDD5) : Colors.white,
            borderRadius: BorderRadius.circular(999),
            border: Border.all(
              color: selected
                  ? AeDashTokens.accent.withValues(alpha: 0.45)
                  : AeDashTokens.border,
            ),
            boxShadow: selected ? null : AeDashTokens.softShadow,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (selected)
                const Icon(
                  Icons.check_rounded,
                  size: 16,
                  color: AeDashTokens.accent,
                )
              else if (dotColor != null)
                Container(
                  width: 9,
                  height: 9,
                  decoration: BoxDecoration(
                    color: dotColor,
                    shape: BoxShape.circle,
                  ),
                ),
              if (selected || dotColor != null) const SizedBox(width: 8),
              Text(
                label,
                style: AeDashTokens.body(
                  size: 13,
                  color: selected ? const Color(0xFFC2410C) : AeDashTokens.text,
                  weight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Large rounded search input.
class AeSearchBar extends StatelessWidget {
  const AeSearchBar({
    super.key,
    required this.controller,
    required this.hint,
    required this.onChanged,
  });

  final TextEditingController controller;
  final String hint;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final border = OutlineInputBorder(
      borderRadius: BorderRadius.circular(14),
      borderSide: const BorderSide(color: AeDashTokens.border),
    );
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        boxShadow: AeDashTokens.softShadow,
      ),
      child: TextField(
        controller: controller,
        onChanged: onChanged,
        style: AeDashTokens.body(size: 14, color: AeDashTokens.text),
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: AeDashTokens.body(
            size: 14,
            color: const Color(0xFF94A3B8),
          ),
          prefixIcon: const Icon(
            Icons.search_rounded,
            color: AeDashTokens.muted,
            size: 22,
          ),
          suffixIcon: controller.text.isEmpty
              ? null
              : IconButton(
                  tooltip: 'Clear',
                  icon: const Icon(Icons.close_rounded, size: 18),
                  onPressed: () {
                    controller.clear();
                    onChanged('');
                  },
                ),
          filled: true,
          fillColor: Colors.white,
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 16,
          ),
          border: border,
          enabledBorder: border,
          focusedBorder: border.copyWith(
            borderSide: const BorderSide(
              color: AeDashTokens.accent,
              width: 1.4,
            ),
          ),
        ),
      ),
    );
  }
}

/// Grid / list switch shown in list card headers.
class AeViewToggle extends StatelessWidget {
  const AeViewToggle({
    super.key,
    required this.gridSelected,
    required this.onChanged,
  });

  final bool gridSelected;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    Widget btn(IconData icon, bool grid, String tip) {
      final on = grid == gridSelected;
      return Tooltip(
        message: tip,
        child: Material(
          color: on ? const Color(0xFFFFEDD5) : Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
            side: BorderSide(
              color: on
                  ? AeDashTokens.accent.withValues(alpha: 0.45)
                  : AeDashTokens.border,
            ),
          ),
          child: InkWell(
            onTap: () => onChanged(grid),
            borderRadius: BorderRadius.circular(10),
            child: SizedBox(
              width: 38,
              height: 38,
              child: Icon(
                icon,
                size: 20,
                color: on ? AeDashTokens.accent : AeDashTokens.muted,
              ),
            ),
          ),
        ),
      );
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        btn(Icons.grid_view_rounded, true, 'Grid view'),
        const SizedBox(width: 8),
        btn(Icons.view_list_rounded, false, 'List view'),
      ],
    );
  }
}

/// Rounded rectangle with a dashed border (upload drop zones).
class AeDashedBox extends StatelessWidget {
  const AeDashedBox({
    super.key,
    required this.child,
    this.color = AeDashTokens.secondary,
    this.radius = 14,
    this.background = const Color(0xFFFFFBF7),
  });

  final Widget child;
  final Color color;
  final double radius;
  final Color background;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _DashedRRectPainter(color: color, radius: radius),
      child: Container(
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(radius),
        ),
        child: child,
      ),
    );
  }
}

class _DashedRRectPainter extends CustomPainter {
  _DashedRRectPainter({required this.color, required this.radius});
  final Color color;
  final double radius;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color.withValues(alpha: 0.7)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4;
    final rrect = RRect.fromRectAndRadius(
      (Offset.zero & size).deflate(0.7),
      Radius.circular(radius),
    );
    final path = Path()..addRRect(rrect);
    for (final metric in path.computeMetrics()) {
      var d = 0.0;
      while (d < metric.length) {
        canvas.drawPath(metric.extractPath(d, d + 6), paint);
        d += 11;
      }
    }
  }

  @override
  bool shouldRepaint(covariant _DashedRRectPainter old) =>
      old.color != color || old.radius != radius;
}

/// Dropdown-looking field: icon, small label, bold value, chevron.
class AeSelectField extends StatelessWidget {
  const AeSelectField({
    super.key,
    required this.icon,
    required this.label,
    required this.value,
    required this.onTap,
    this.iconColor = AeDashTokens.accent,
  });

  final IconData icon;
  final String label;
  final String value;
  final VoidCallback? onTap;
  final Color iconColor;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: const BorderSide(color: AeDashTokens.border),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: iconColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(11),
                ),
                child: Icon(icon, color: iconColor, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(label, style: AeDashTokens.body(size: 12)),
                    const SizedBox(height: 2),
                    Text(
                      value,
                      style: AeDashTokens.section(size: 15),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              const Icon(
                Icons.keyboard_arrow_down_rounded,
                color: AeDashTokens.muted,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Colored dot + label used in chart legends.
class AeLegendDot extends StatelessWidget {
  const AeLegendDot({super.key, required this.color, required this.label});

  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 9,
          height: 9,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 6),
        Text(
          label,
          style: AeDashTokens.body(
            size: 12,
            color: AeDashTokens.text,
            weight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

import 'package:flutter/material.dart';

import '../theme/tourism_app_theme.dart';

/// Shared OPTACA portal chrome. Visual only — no data or routing changes.
abstract final class OptacaPortalUi {
  static const radius = 18.0;
  static const controlRadius = 12.0;

  static BoxDecoration card({bool selected = false}) {
    return BoxDecoration(
      color: selected ? OptacaAdminTheme.lightOrange : OptacaAdminTheme.card,
      borderRadius: BorderRadius.circular(radius),
      border: Border.all(
        color: selected
            ? OptacaAdminTheme.primary.withValues(alpha: 0.45)
            : OptacaAdminTheme.border,
        width: selected ? 1.4 : 1.2,
      ),
      boxShadow: OptacaAdminTheme.cardShadow,
    );
  }

  static InputDecoration searchDecoration({
    required String hint,
    Widget? prefixIcon,
    Widget? suffixIcon,
  }) {
    return InputDecoration(
      hintText: hint,
      prefixIcon: prefixIcon ?? const Icon(Icons.search_rounded, size: 20),
      suffixIcon: suffixIcon,
      isDense: true,
      filled: true,
      fillColor: const Color(0xFFFAF7F4),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(controlRadius),
        borderSide: const BorderSide(color: OptacaAdminTheme.border),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(controlRadius),
        borderSide: const BorderSide(color: OptacaAdminTheme.border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(controlRadius),
        borderSide: const BorderSide(color: OptacaAdminTheme.primary, width: 1.4),
      ),
    );
  }
}

class OptacaSectionHeader extends StatelessWidget {
  const OptacaSectionHeader({
    super.key,
    required this.title,
    this.caption,
    this.trailing,
  });

  final String title;
  final String? caption;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 28,
                height: 3,
                margin: const EdgeInsets.only(bottom: 8),
                decoration: BoxDecoration(
                  color: OptacaAdminTheme.primary,
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
              Text(
                title,
                style: const TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                  color: OptacaAdminTheme.text,
                  letterSpacing: -0.2,
                ),
              ),
              if (caption != null) ...[
                const SizedBox(height: 4),
                Text(
                  caption!,
                  style: const TextStyle(
                    fontSize: 12.5,
                    height: 1.35,
                    color: OptacaAdminTheme.textMuted,
                  ),
                ),
              ],
            ],
          ),
        ),
        if (trailing != null) trailing!,
      ],
    );
  }
}

class OptacaPortalCard extends StatelessWidget {
  const OptacaPortalCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(20),
    this.onTap,
    this.selected = false,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final body = Padding(padding: padding, child: child);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(OptacaPortalUi.radius),
        hoverColor: OptacaAdminTheme.primary.withValues(alpha: 0.04),
        child: Ink(
          decoration: OptacaPortalUi.card(selected: selected),
          child: body,
        ),
      ),
    );
  }
}

class OptacaQuickLink extends StatelessWidget {
  const OptacaQuickLink({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return OptacaPortalCard(
      onTap: onTap,
      padding: const EdgeInsets.fromLTRB(16, 16, 14, 16),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: OptacaAdminTheme.lightOrange,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: OptacaAdminTheme.primary, size: 22),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              label,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 13.5,
                height: 1.25,
                color: OptacaAdminTheme.text,
              ),
            ),
          ),
          const Icon(
            Icons.arrow_forward_rounded,
            size: 18,
            color: OptacaAdminTheme.primary,
          ),
        ],
      ),
    );
  }
}

class OptacaEmptyState extends StatelessWidget {
  const OptacaEmptyState({
    super.key,
    required this.title,
    this.message,
    this.icon = Icons.inbox_outlined,
  });

  final String title;
  final String? message;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: OptacaAdminTheme.lightOrange,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Icon(icon, size: 30, color: OptacaAdminTheme.primary),
              ),
              const SizedBox(height: 16),
              Text(
                title,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                  color: OptacaAdminTheme.text,
                ),
              ),
              if (message != null) ...[
                const SizedBox(height: 8),
                Text(
                  message!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 13.5,
                    height: 1.45,
                    color: OptacaAdminTheme.textMuted,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Visible recovery UI for a failed Firestore/network load. Never a blank box.
class OptacaLoadError extends StatelessWidget {
  const OptacaLoadError({
    super.key,
    required this.title,
    this.message,
    this.onRetry,
  });

  final String title;
  final String? message;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.error_outline_rounded,
                size: 40,
                color: OptacaAdminTheme.primary,
              ),
              const SizedBox(height: 12),
              Text(
                title,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                  color: OptacaAdminTheme.text,
                ),
              ),
              if (message != null && message!.trim().isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(
                  message!,
                  maxLines: 6,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 13.5,
                    height: 1.45,
                    color: OptacaAdminTheme.textMuted,
                  ),
                ),
              ],
              if (onRetry != null) ...[
                const SizedBox(height: 16),
                FilledButton.icon(
                  onPressed: onRetry,
                  icon: const Icon(Icons.refresh_rounded, size: 18),
                  label: const Text('Retry'),
                  style: FilledButton.styleFrom(
                    backgroundColor: OptacaAdminTheme.primary,
                    foregroundColor: Colors.white,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class OptacaSkeletonBlock extends StatelessWidget {
  const OptacaSkeletonBlock({
    super.key,
    this.height = 16,
    this.width,
    this.radius = 8,
  });

  final double height;
  final double? width;
  final double radius;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: height,
      width: width,
      decoration: BoxDecoration(
        color: OptacaAdminTheme.border,
        borderRadius: BorderRadius.circular(radius),
      ),
    );
  }
}

class OptacaKpiSkeletonRow extends StatelessWidget {
  const OptacaKpiSkeletonRow({super.key, this.count = 5});

  final int count;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, c) {
        final cols = c.maxWidth >= 1200 ? count : (c.maxWidth >= 700 ? 2 : 1);
        final cards = List<Widget>.generate(
          count,
          (_) => const OptacaPortalCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                OptacaSkeletonBlock(height: 36, width: 36, radius: 12),
                SizedBox(height: 16),
                OptacaSkeletonBlock(height: 26, width: 72),
                SizedBox(height: 10),
                OptacaSkeletonBlock(height: 12, width: 110),
              ],
            ),
          ),
        );
        if (cols >= count) {
          return Row(
            children: [
              for (var i = 0; i < cards.length; i++) ...[
                if (i > 0) const SizedBox(width: 12),
                Expanded(child: cards[i]),
              ],
            ],
          );
        }
        return Column(
          children: [
            for (var i = 0; i < cards.length; i += cols) ...[
              if (i > 0) const SizedBox(height: 16),
              Row(
                children: [
                  for (var j = 0; j < cols; j++) ...[
                    if (j > 0) const SizedBox(width: 16),
                    Expanded(
                      child: i + j < cards.length
                          ? cards[i + j]
                          : const SizedBox.shrink(),
                    ),
                  ],
                ],
              ),
            ],
          ],
        );
      },
    );
  }
}

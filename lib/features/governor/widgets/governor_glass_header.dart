import 'package:atmos_trs_system/features/governor/theme/governor_dashboard_tokens.dart';
import 'package:flutter/material.dart';

/// Dashboard hero header matching the concept screenshot.
class GovernorGlassHeader extends StatelessWidget {
  const GovernorGlassHeader({
    super.key,
    required this.title,
    this.greeting,
    this.subtitle,
    this.notificationCount = 0,
    this.onNotifications,
    this.profile,
    this.searchController,
    this.onSearchChanged,
    this.searchHint = 'Search tourist, municipality, or report...',
    this.compact = false,
    this.leading,
    this.showConceptMeta = true,
  });

  /// Large bold name / page title (e.g. "Governor").
  final String title;

  /// Optional first line, e.g. "👋 Good Morning,".
  final String? greeting;

  final String? subtitle;
  final int notificationCount;
  final VoidCallback? onNotifications;
  final Widget? profile;
  final TextEditingController? searchController;
  final ValueChanged<String>? onSearchChanged;
  final String searchHint;
  final bool compact;
  final Widget? leading;
  final bool showConceptMeta;

  static const _weekdays = [
    'Monday',
    'Tuesday',
    'Wednesday',
    'Thursday',
    'Friday',
    'Saturday',
    'Sunday',
  ];
  static const _months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];

  String _formatDate(DateTime d) {
    return '${_weekdays[d.weekday - 1]}, ${_months[d.month - 1]} ${d.day}, ${d.year}';
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final isNarrow = width < 980;
    final dateLabel = _formatDate(DateTime.now());

    final height = compact
        ? (isNarrow ? 118.0 : 128.0)
        : (isNarrow ? 128.0 : 142.0);

    return ClipRRect(
      borderRadius: const BorderRadius.vertical(bottom: Radius.circular(24)),
      child: SizedBox(
        height: height,
        child: Stack(
          fit: StackFit.expand,
          children: [
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: GovernorDashboardTokens.headerGradient,
              ),
            ),
            // Soft highlight so content stays readable on orange.
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.white.withValues(alpha: 0.18),
                    Colors.white.withValues(alpha: 0.06),
                    GovernorDashboardTokens.background.withValues(alpha: 0.35),
                  ],
                ),
              ),
            ),
            Positioned(
              right: -40,
              top: -30,
              child: Container(
                width: 220,
                height: 220,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [
                      Colors.white.withValues(alpha: 0.18),
                      Colors.white.withValues(alpha: 0.0),
                    ],
                  ),
                ),
              ),
            ),
            Padding(
              padding: EdgeInsets.fromLTRB(
                isNarrow ? 14 : 24,
                compact ? 14 : 18,
                isNarrow ? 14 : 24,
                compact ? 12 : 16,
              ),
              child: isNarrow
                  ? _buildNarrow(
                      dateLabel: dateLabel,
                    )
                  : _buildWide(
                      dateLabel: dateLabel,
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildWide({required String dateLabel}) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (leading != null) ...[
          leading!,
          const SizedBox(width: 8),
        ],
        Expanded(
          flex: 3,
          child: _GreetingBlock(
            greeting: greeting,
            title: title,
            subtitle: subtitle,
            compact: compact,
          ),
        ),
        const SizedBox(width: 18),
        Expanded(
          flex: 4,
          child: Padding(
            padding: EdgeInsets.only(top: compact ? 6 : 10),
            child: _SearchField(
              controller: searchController,
              hint: searchHint,
              onChanged: onSearchChanged,
            ),
          ),
        ),
        const SizedBox(width: 14),
        Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _NotificationButton(
                  count: notificationCount,
                  onPressed: onNotifications,
                ),
                const SizedBox(width: 10),
                if (profile != null) profile!,
              ],
            ),
            if (showConceptMeta) ...[
              const SizedBox(height: 8),
              Text(
                dateLabel,
                style: GovernorDashboardTokens.sectionTitle(
                  size: 12,
                  color: Colors.white,
                ),
              ),
              Text(
                'Make Misamis Occidental a top destination!',
                style: GovernorDashboardTokens.body(
                  size: 11,
                  color: Colors.white.withValues(alpha: 0.92),
                ).copyWith(fontStyle: FontStyle.italic),
              ),
            ],
          ],
        ),
      ],
    );
  }

  Widget _buildNarrow({required String dateLabel}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            if (leading != null) ...[
              leading!,
              const SizedBox(width: 4),
            ],
            Expanded(
              child: _GreetingBlock(
                greeting: greeting,
                title: title,
                subtitle: subtitle,
                compact: true,
              ),
            ),
            _NotificationButton(
              count: notificationCount,
              onPressed: onNotifications,
            ),
            const SizedBox(width: 8),
            if (profile != null) profile!,
          ],
        ),
        if (showConceptMeta) ...[
          const SizedBox(height: 4),
          Text(
            dateLabel,
            textAlign: TextAlign.right,
            style: GovernorDashboardTokens.body(
              size: 10.5,
              color: Colors.white,
            ),
          ),
        ],
      ],
    );
  }
}

class _GreetingBlock extends StatelessWidget {
  const _GreetingBlock({
    required this.title,
    this.greeting,
    this.subtitle,
    this.compact = false,
  });

  final String title;
  final String? greeting;
  final String? subtitle;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (greeting != null && greeting!.isNotEmpty)
          Text(
            greeting!,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: GovernorDashboardTokens.body(
              size: compact ? 12.5 : 14,
              color: Colors.white.withValues(alpha: 0.95),
            ).copyWith(fontWeight: FontWeight.w500),
          ),
        Text(
          title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: GovernorDashboardTokens.heading(
            size: compact ? 22 : 28,
            color: Colors.white,
          ),
        ),
        if (subtitle != null && subtitle!.isNotEmpty) ...[
          const SizedBox(height: 2),
          Text(
            subtitle!,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: GovernorDashboardTokens.body(
              size: compact ? 11 : 12.5,
              color: Colors.white.withValues(alpha: 0.88),
            ),
          ),
        ],
      ],
    );
  }
}

class _SearchField extends StatelessWidget {
  const _SearchField({
    this.controller,
    required this.hint,
    this.onChanged,
  });

  final TextEditingController? controller;
  final String hint;
  final ValueChanged<String>? onChanged;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 46,
      child: TextField(
        controller: controller,
        onChanged: onChanged,
        style: GovernorDashboardTokens.body(
          size: 13.5,
          color: GovernorDashboardTokens.text,
        ),
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: GovernorDashboardTokens.body(size: 13),
          prefixIcon: const Icon(
            Icons.search_rounded,
            size: 20,
            color: GovernorDashboardTokens.subtitle,
          ),
          filled: true,
          fillColor: Colors.white.withValues(alpha: 0.92),
          contentPadding: const EdgeInsets.symmetric(horizontal: 14),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(999),
            borderSide: BorderSide.none,
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(999),
            borderSide: BorderSide(
              color: Colors.white.withValues(alpha: 0.7),
            ),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(999),
            borderSide: const BorderSide(
              color: GovernorDashboardTokens.primary,
              width: 1.4,
            ),
          ),
        ),
      ),
    );
  }
}

class _NotificationButton extends StatelessWidget {
  const _NotificationButton({required this.count, this.onPressed});

  final int count;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(14),
      elevation: 0,
      shadowColor: Colors.black26,
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onPressed,
        child: SizedBox(
          width: 44,
          height: 44,
          child: Stack(
            alignment: Alignment.center,
            children: [
              const Icon(
                Icons.notifications_outlined,
                size: 20,
                color: GovernorDashboardTokens.text,
              ),
              if (count > 0)
                Positioned(
                  right: 8,
                  top: 8,
                  child: Container(
                    constraints:
                        const BoxConstraints(minWidth: 16, minHeight: 16),
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    decoration: BoxDecoration(
                      color: GovernorDashboardTokens.danger,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      count > 99 ? '99+' : '$count',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 9,
                        fontWeight: FontWeight.w800,
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

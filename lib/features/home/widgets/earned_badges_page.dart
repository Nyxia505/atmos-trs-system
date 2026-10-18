import 'package:flutter/material.dart';

import 'package:atmos_trs_system/config/app_theme.dart';
import 'package:atmos_trs_system/services/user_activity_service.dart'
    as activity;
import 'package:atmos_trs_system/widgets/tourist_full_page.dart';

class _BadgeDef {
  const _BadgeDef(this.id, this.name, this.need, this.icon, this.colors);
  final String id;
  final String name;
  final int need;
  final IconData icon;
  final List<Color> colors;

  String get goal => need == 1 ? 'Check in at your first spot' : 'Visit $need tourist spots';
}

const _kBadgeDefs = <_BadgeDef>[
  _BadgeDef('first_visit', 'First Steps', 1, Icons.explore_rounded,
      [Color(0xFF34D399), Color(0xFF059669)]),
  _BadgeDef('explorer', 'Explorer', 5, Icons.emoji_events_rounded,
      [Color(0xFFFBBF24), Color(0xFFF59E0B)]),
  _BadgeDef('adventurer', 'Adventurer', 10, Icons.military_tech_rounded,
      [Color(0xFF60A5FA), Color(0xFF2563EB)]),
  _BadgeDef('travel_guru', 'Travel Guru', 25, Icons.workspace_premium_rounded,
      [Color(0xFFC084FC), Color(0xFF7C3AED)]),
];

/// Full-screen tourist badges: progress summary + locked / unlocked grid.
class EarnedBadgesPage extends StatelessWidget {
  const EarnedBadgesPage({
    super.key,
    required this.earned,
    required this.visitedCount,
  });

  final List<activity.Badge> earned;
  final int visitedCount;

  static const _months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];

  static String _fmt(DateTime d) => '${_months[d.month - 1]} ${d.day}, ${d.year}';

  @override
  Widget build(BuildContext context) {
    final byId = {for (final b in earned) b.id: b};
    final unlocked = _kBadgeDefs.where((d) => byId.containsKey(d.id)).length;
    final extra = earned.where((b) => !_kBadgeDefs.any((d) => d.id == b.id)).toList();
    _BadgeDef? next;
    for (final d in _kBadgeDefs) {
      if (!byId.containsKey(d.id)) {
        next = d;
        break;
      }
    }

    return TouristFullPage(
      title: 'Earned badges',
      subtitle: 'Check in at tourist spots to unlock new badges.',
      icon: Icons.emoji_events_rounded,
      child: LayoutBuilder(
        builder: (context, c) {
          final cols = c.maxWidth >= 520 ? 3 : 2;
          return CustomScrollView(
            slivers: [
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 18, 16, 6),
                sliver: SliverToBoxAdapter(
                  child: _SummaryCard(
                    unlocked: unlocked + extra.length,
                    total: _kBadgeDefs.length + extra.length,
                    visited: visitedCount,
                    next: next,
                  ),
                ),
              ),
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(20, 14, 20, 10),
                sliver: SliverToBoxAdapter(
                  child: Text(
                    'All badges',
                    style: TextStyle(
                      color: AppTheme.textPrimary,
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ),
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
                sliver: SliverGrid(
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: cols,
                    mainAxisSpacing: 12,
                    crossAxisSpacing: 12,
                    mainAxisExtent: 196,
                  ),
                  delegate: SliverChildListDelegate([
                    for (final d in _kBadgeDefs)
                      _BadgeTile(
                        def: d,
                        earned: byId[d.id],
                        visited: visitedCount,
                        dateLabel: byId[d.id] == null ? null : _fmt(byId[d.id]!.earnedAt),
                      ),
                    for (final b in extra)
                      _BadgeTile(
                        def: _BadgeDef(b.id, b.name, 0, Icons.star_rounded,
                            const [Color(0xFFFB923C), Color(0xFFEA580C)]),
                        earned: b,
                        visited: visitedCount,
                        dateLabel: _fmt(b.earnedAt),
                      ),
                  ]),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({
    required this.unlocked,
    required this.total,
    required this.visited,
    required this.next,
  });

  final int unlocked;
  final int total;
  final int visited;
  final _BadgeDef? next;

  @override
  Widget build(BuildContext context) {
    final n = next;
    final progress = n == null ? 1.0 : (visited / n.need).clamp(0.0, 1.0);
    final left = n == null ? 0 : (n.need - visited).clamp(0, n.need);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.cardBackground,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppTheme.border),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 14,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              SizedBox(
                width: 64,
                height: 64,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    SizedBox.expand(
                      child: CircularProgressIndicator(
                        value: total == 0 ? 0 : unlocked / total,
                        strokeWidth: 6,
                        strokeCap: StrokeCap.round,
                        backgroundColor: AppTheme.primary.withValues(alpha: 0.22),
                        color: AppTheme.primary,
                      ),
                    ),
                    Text(
                      '$unlocked/$total',
                      style: TextStyle(
                        color: AppTheme.textPrimary,
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      unlocked == 0
                          ? 'No badges yet'
                          : '$unlocked ${unlocked == 1 ? 'badge' : 'badges'} unlocked',
                      style: TextStyle(
                        color: AppTheme.textPrimary,
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      '$visited ${visited == 1 ? 'spot' : 'spots'} visited so far',
                      style: TextStyle(color: AppTheme.unselectedMuted, fontSize: 13),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppTheme.primary.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AppTheme.primary.withValues(alpha: 0.35)),
            ),
            child: n == null
                ? Row(
                    children: [
                      Icon(Icons.celebration_rounded, color: AppTheme.primary),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'You unlocked every badge. Amazing explorer!',
                          style: TextStyle(
                            color: AppTheme.textPrimary,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  )
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(n.icon, size: 18, color: AppTheme.primary),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Next: ${n.name}',
                              style: TextStyle(
                                color: AppTheme.textPrimary,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                          Text(
                            left == 0
                                ? 'On your next check-in'
                                : '$left more ${left == 1 ? 'spot' : 'spots'}',
                            style: TextStyle(
                              color: AppTheme.primary,
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: LinearProgressIndicator(
                          value: progress,
                          minHeight: 8,
                          backgroundColor: AppTheme.border,
                          color: AppTheme.primary,
                        ),
                      ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}

class _BadgeTile extends StatelessWidget {
  const _BadgeTile({
    required this.def,
    required this.earned,
    required this.visited,
    required this.dateLabel,
  });

  final _BadgeDef def;
  final activity.Badge? earned;
  final int visited;
  final String? dateLabel;

  @override
  Widget build(BuildContext context) {
    final isEarned = earned != null;
    final progress = def.need == 0 ? 1.0 : (visited / def.need).clamp(0.0, 1.0);

    return Container(
      padding: const EdgeInsets.fromLTRB(12, 16, 12, 12),
      decoration: BoxDecoration(
        color: isEarned ? AppTheme.cardBackground : AppTheme.surfaceMuted,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: isEarned ? def.colors.last.withValues(alpha: 0.35) : AppTheme.border,
        ),
        boxShadow: isEarned
            ? [
                BoxShadow(
                  color: def.colors.last.withValues(alpha: 0.14),
                  blurRadius: 14,
                  offset: const Offset(0, 6),
                ),
              ]
            : null,
      ),
      child: Column(
        children: [
          Stack(
            clipBehavior: Clip.none,
            children: [
              Container(
                width: 62,
                height: 62,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: isEarned
                      ? LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: def.colors,
                        )
                      : null,
                  color: isEarned ? null : AppTheme.border,
                ),
                child: Icon(
                  def.icon,
                  size: 30,
                  color: isEarned ? Colors.white : AppTheme.unselectedMuted,
                ),
              ),
              if (!isEarned)
                Positioned(
                  right: -2,
                  bottom: -2,
                  child: Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: AppTheme.cardBackground,
                      shape: BoxShape.circle,
                      border: Border.all(color: AppTheme.border),
                    ),
                    child: Icon(
                      Icons.lock_rounded,
                      size: 12,
                      color: AppTheme.unselectedMuted,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            def.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: isEarned ? AppTheme.textPrimary : AppTheme.unselectedMuted,
              fontSize: 14.5,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            isEarned ? earned!.description : def.goal,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: TextStyle(color: AppTheme.unselectedMuted, fontSize: 11.5, height: 1.3),
          ),
          const Spacer(),
          if (isEarned)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: def.colors.last.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.check_circle_rounded, size: 13, color: def.colors.last),
                  const SizedBox(width: 4),
                  Flexible(
                    child: Text(
                      dateLabel ?? 'Unlocked',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: def.colors.last,
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
            )
          else
            Column(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: LinearProgressIndicator(
                    value: progress,
                    minHeight: 6,
                    backgroundColor: AppTheme.border,
                    color: AppTheme.unselectedMuted,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  '${visited.clamp(0, def.need)} / ${def.need} spots',
                  style: TextStyle(
                    color: AppTheme.unselectedMuted,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }
}

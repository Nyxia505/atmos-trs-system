import 'package:atmos_trs_system/features/governor/theme/governor_dashboard_tokens.dart';
import 'package:flutter/material.dart';

/// Quick actions tailored for Provincial Tourism Office.
class ProvincialQuickActions extends StatelessWidget {
  const ProvincialQuickActions({
    super.key,
    required this.onGenerateDotReport,
    required this.onReviewEvents,
    required this.onViewUnderperforming,
    required this.onOpenDestinations,
  });

  final VoidCallback onGenerateDotReport;
  final VoidCallback onReviewEvents;
  final VoidCallback onViewUnderperforming;
  final VoidCallback onOpenDestinations;

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final wrap = width < 980;

    final actions = [
      _ActionSpec(
        label: 'Generate DOT report',
        icon: Icons.assessment_rounded,
        primary: true,
        onTap: onGenerateDotReport,
      ),
      _ActionSpec(
        label: 'Review pending events',
        icon: Icons.event_available_rounded,
        onTap: onReviewEvents,
      ),
      _ActionSpec(
        label: 'Underperforming LGUs',
        icon: Icons.trending_down_rounded,
        onTap: onViewUnderperforming,
      ),
      _ActionSpec(
        label: 'Open destinations',
        icon: Icons.place_rounded,
        onTap: onOpenDestinations,
      ),
    ];

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: BoxDecoration(
        color: GovernorDashboardTokens.card,
        borderRadius: BorderRadius.circular(GovernorDashboardTokens.radiusCard),
        border: Border.all(color: GovernorDashboardTokens.border),
        boxShadow: GovernorDashboardTokens.cardShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Quick Actions',
            style: GovernorDashboardTokens.sectionTitle(size: 14),
          ),
          const SizedBox(height: 2),
          Text(
            'Jump to the most common provincial tourism tasks.',
            style: GovernorDashboardTokens.body(size: 12),
          ),
          const SizedBox(height: 12),
          if (wrap)
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                for (final a in actions)
                  SizedBox(
                    width: width < 520 ? double.infinity : (width - 72) / 2,
                    height: 52,
                    child: _ActionButton(spec: a),
                  ),
              ],
            )
          else
            Row(
              children: [
                for (var i = 0; i < actions.length; i++) ...[
                  if (i > 0) const SizedBox(width: 10),
                  Expanded(
                    child: SizedBox(
                      height: 52,
                      child: _ActionButton(spec: actions[i]),
                    ),
                  ),
                ],
              ],
            ),
        ],
      ),
    );
  }
}

class _ActionSpec {
  const _ActionSpec({
    required this.label,
    required this.icon,
    required this.onTap,
    this.primary = false,
  });

  final String label;
  final IconData icon;
  final VoidCallback onTap;
  final bool primary;
}

class _ActionButton extends StatefulWidget {
  const _ActionButton({required this.spec});

  final _ActionSpec spec;

  @override
  State<_ActionButton> createState() => _ActionButtonState();
}

class _ActionButtonState extends State<_ActionButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final primary = widget.spec.primary;
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: widget.spec.onTap,
          borderRadius: BorderRadius.circular(14),
            child: AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            alignment: Alignment.centerLeft,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              gradient: primary ? GovernorDashboardTokens.primaryGradient : null,
              color: primary
                  ? null
                  : (_hovered
                      ? GovernorDashboardTokens.softOrange
                      : GovernorDashboardTokens.mutedSurface),
              borderRadius: BorderRadius.circular(14),
              border: primary
                  ? null
                  : Border.all(color: GovernorDashboardTokens.border),
              boxShadow: primary && _hovered
                  ? GovernorDashboardTokens.cardShadowHover
                  : null,
            ),
            child: Row(
              children: [
                Icon(
                  widget.spec.icon,
                  size: 18,
                  color: primary
                      ? Colors.white
                      : GovernorDashboardTokens.primaryDark,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    widget.spec.label,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: GovernorDashboardTokens.sectionTitle(
                      size: 12.5,
                      color: primary
                          ? Colors.white
                          : GovernorDashboardTokens.text,
                    ),
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

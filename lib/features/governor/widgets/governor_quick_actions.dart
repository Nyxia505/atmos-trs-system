import 'package:atmos_trs_system/features/governor/theme/governor_dashboard_tokens.dart';
import 'package:flutter/material.dart';

class GovernorQuickActions extends StatelessWidget {
  const GovernorQuickActions({
    super.key,
    required this.onAddMunicipality,
    required this.onExportReport,
    required this.onViewAnalytics,
  });

  final VoidCallback onAddMunicipality;
  final VoidCallback onExportReport;
  final VoidCallback onViewAnalytics;

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final wrap = width < 980;

    final actions = [
      _ActionSpec(
        label: 'Add Municipality',
        icon: Icons.add_rounded,
        primary: true,
        onTap: onAddMunicipality,
      ),
      _ActionSpec(
        label: 'Export Report',
        icon: Icons.download_rounded,
        onTap: onExportReport,
      ),
      _ActionSpec(
        label: 'View Analytics',
        icon: Icons.bar_chart_rounded,
        onTap: onViewAnalytics,
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
            'Common tasks for faster management.',
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
                    child: _ActionButton(spec: a),
                  ),
              ],
            )
          else
            Row(
              children: [
                for (var i = 0; i < actions.length; i++) ...[
                  if (i > 0) const SizedBox(width: 10),
                  Expanded(child: _ActionButton(spec: actions[i])),
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
          borderRadius:
              BorderRadius.circular(GovernorDashboardTokens.radiusMd),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            decoration: BoxDecoration(
              gradient: primary ? GovernorDashboardTokens.primaryGradient : null,
              color: primary
                  ? null
                  : (_hovered
                      ? GovernorDashboardTokens.softOrange
                      : GovernorDashboardTokens.mutedSurface),
              borderRadius:
                  BorderRadius.circular(GovernorDashboardTokens.radiusMd),
              border: primary
                  ? null
                  : Border.all(color: GovernorDashboardTokens.border),
              boxShadow: _hovered
                  ? GovernorDashboardTokens.cardShadowHover
                  : const [],
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
                    maxLines: 1,
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

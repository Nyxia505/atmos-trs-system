import 'package:atmos_trs_system/features/governor/theme/governor_dashboard_tokens.dart';
import 'package:flutter/material.dart';

class GovernorQuickActions extends StatelessWidget {
  const GovernorQuickActions({
    super.key,
    required this.onAddMunicipality,
    required this.onExportReport,
    required this.onViewAnalytics,
    required this.onManageSpots,
  });

  final VoidCallback onAddMunicipality;
  final VoidCallback onExportReport;
  final VoidCallback onViewAnalytics;
  final VoidCallback onManageSpots;

  @override
  Widget build(BuildContext context) {
    final wrap = MediaQuery.sizeOf(context).width < 1100;

    final actions = [
      _ActionSpec(
        label: 'Add Municipality',
        icon: Icons.add_rounded,
        primary: true,
        onTap: onAddMunicipality,
      ),
      _ActionSpec(
        label: 'Export Report',
        icon: Icons.file_download_outlined,
        onTap: onExportReport,
      ),
      _ActionSpec(
        label: 'View Analytics',
        icon: Icons.bar_chart_rounded,
        onTap: onViewAnalytics,
      ),
      _ActionSpec(
        label: 'Manage Tourist Spots',
        icon: Icons.place_outlined,
        onTap: onManageSpots,
      ),
    ];

    final buttons = Wrap(
      spacing: 10,
      runSpacing: 10,
      alignment: WrapAlignment.end,
      children: [for (final action in actions) _ActionButton(spec: action)],
    );

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: GovernorDashboardTokens.card,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: GovernorDashboardTokens.border),
        boxShadow: GovernorDashboardTokens.cardShadow,
      ),
      child: wrap
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const _QuickTitle(),
                const SizedBox(height: 12),
                buttons,
              ],
            )
          : Row(
              children: [
                const _QuickTitle(),
                const SizedBox(width: 16),
                Expanded(child: Align(alignment: Alignment.centerRight, child: buttons)),
              ],
            ),
    );
  }
}

class _QuickTitle extends StatelessWidget {
  const _QuickTitle();

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: GovernorDashboardTokens.softOrange,
            borderRadius: BorderRadius.circular(12),
          ),
          child: const Icon(
            Icons.bolt_rounded,
            color: GovernorDashboardTokens.primary,
            size: 20,
          ),
        ),
        const SizedBox(width: 10),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Quick Actions',
              style: GovernorDashboardTokens.sectionTitle(size: 14),
            ),
            Text(
              'Common tasks for faster management.',
              style: GovernorDashboardTokens.body(size: 11.5),
            ),
          ],
        ),
      ],
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
          borderRadius: BorderRadius.circular(24),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              gradient: primary ? GovernorDashboardTokens.primaryGradient : null,
              color: primary
                  ? null
                  : (_hovered
                      ? GovernorDashboardTokens.softOrange
                      : Colors.white),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(
                color: primary
                    ? Colors.transparent
                    : GovernorDashboardTokens.border,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  widget.spec.icon,
                  size: 16,
                  color: primary
                      ? Colors.white
                      : GovernorDashboardTokens.text,
                ),
                const SizedBox(width: 6),
                Text(
                  widget.spec.label,
                  style: GovernorDashboardTokens.sectionTitle(
                    size: 12.5,
                    color: primary
                        ? Colors.white
                        : GovernorDashboardTokens.text,
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

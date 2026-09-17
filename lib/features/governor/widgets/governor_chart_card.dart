import 'package:atmos_trs_system/features/governor/theme/governor_dashboard_tokens.dart';
import 'package:flutter/material.dart';

/// Shared white analytics card shell.
class GovernorChartCard extends StatelessWidget {
  const GovernorChartCard({
    super.key,
    required this.title,
    required this.child,
    this.icon,
    this.trailing,
    this.dense = false,
    this.padding,
  });

  final String title;
  final Widget child;
  final IconData? icon;
  final Widget? trailing;
  final bool dense;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: GovernorDashboardTokens.card,
        borderRadius: BorderRadius.circular(GovernorDashboardTokens.radiusCard),
        border: Border.all(color: GovernorDashboardTokens.border),
        boxShadow: GovernorDashboardTokens.cardShadow,
      ),
      padding: padding ??
          EdgeInsets.all(dense ? 12 : GovernorDashboardTokens.radiusMd),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (icon != null) ...[
                Container(
                  width: dense ? 28 : 34,
                  height: dense ? 28 : 34,
                  decoration: BoxDecoration(
                    color: GovernorDashboardTokens.primary
                        .withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    icon,
                    size: dense ? 14 : 16,
                    color: GovernorDashboardTokens.primary,
                  ),
                ),
                SizedBox(width: dense ? 8 : 10),
              ],
              Expanded(
                child: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GovernorDashboardTokens.sectionTitle(
                    size: dense ? 13 : 15,
                  ),
                ),
              ),
              if (trailing != null) trailing!,
            ],
          ),
          SizedBox(height: dense ? 8 : 12),
          Expanded(child: child),
        ],
      ),
    );
  }
}

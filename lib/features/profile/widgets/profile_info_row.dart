import 'package:flutter/material.dart';

/// Label / value row used on the profile tab.
class ProfileInfoRow extends StatelessWidget {
  const ProfileInfoRow({
    super.key,
    required this.label,
    required this.value,
    this.icon,
    this.dense = false,
    this.maxLines = 2,
  });

  final String label;
  final String value;
  final IconData? icon;
  final bool dense;
  final int maxLines;

  static const _labelColor = Color(0xFF6B7280);
  static const _valueColor = Color(0xFF111827);

  @override
  Widget build(BuildContext context) {
    final vertical = dense ? 8.0 : 12.0;
    return Padding(
      padding: EdgeInsets.symmetric(vertical: vertical),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 18, color: Theme.of(context).colorScheme.primary),
            const SizedBox(width: 10),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontSize: dense ? 11 : 12,
                    fontWeight: FontWeight.w600,
                    color: _labelColor,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  value.isEmpty ? '—' : value,
                  maxLines: maxLines,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: dense ? 13 : 14,
                    fontWeight: FontWeight.w600,
                    color: _valueColor,
                    height: 1.35,
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

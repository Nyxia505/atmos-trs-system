import 'package:flutter/material.dart';

class GovernorBreadcrumbItem {
  const GovernorBreadcrumbItem({
    required this.label,
    this.onTap,
  });

  final String label;

  /// Null on the current page.
  final VoidCallback? onTap;
}

/// Clickable trail for the Governor municipality drill-down.
class GovernorBreadcrumb extends StatelessWidget {
  const GovernorBreadcrumb({super.key, required this.items});

  final List<GovernorBreadcrumbItem> items;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
        decoration: const BoxDecoration(
          border: Border(bottom: BorderSide(color: Color(0xFFE7E5E4))),
        ),
        child: Wrap(
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 4,
          runSpacing: 4,
          children: [
            for (var i = 0; i < items.length; i++) ...[
              if (i > 0)
                const Icon(
                  Icons.chevron_right_rounded,
                  size: 18,
                  color: Color(0xFF78716C),
                ),
              _Crumb(item: items[i], current: items[i].onTap == null),
            ],
          ],
        ),
      ),
    );
  }
}

class _Crumb extends StatelessWidget {
  const _Crumb({required this.item, required this.current});

  final GovernorBreadcrumbItem item;
  final bool current;

  @override
  Widget build(BuildContext context) {
    final style = TextStyle(
      fontSize: 13.5,
      fontWeight: FontWeight.w800,
      color: current ? const Color(0xFF9A3412) : const Color(0xFF1C1917),
      height: 1.2,
    );
    if (current) {
      return Text(item.label, style: style);
    }
    return InkWell(
      onTap: item.onTap,
      borderRadius: BorderRadius.circular(6),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
        child: Text(
          item.label,
          style: style.copyWith(
            decoration: TextDecoration.underline,
            decorationColor: const Color(0xFF44403C),
          ),
        ),
      ),
    );
  }
}

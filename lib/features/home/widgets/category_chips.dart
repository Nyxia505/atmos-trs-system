import 'package:flutter/material.dart';
import 'package:atmos_trs_system/config/app_theme.dart';

/// Category chip: display [label] and optional [filterValue] for filtering (e.g. "Beaches" -> "Beach").
class CategoryChipData {
  const CategoryChipData({
    required this.label,
    required this.icon,
    required this.filterValue,
  });

  final String label;
  final IconData icon;
  /// Value used when filtering destinations (e.g. "Beach", "Mountain").
  final String filterValue;
}

/// Horizontally scrollable category chips. Dark dashboard style: selected = solid orange + white; unselected = white + dark grey.
class CategoryChips extends StatelessWidget {
  const CategoryChips({
    super.key,
    required this.categories,
    required this.selectedIndex,
    required this.onSelected,
  });

  final List<CategoryChipData> categories;
  final int selectedIndex;
  final ValueChanged<int> onSelected;

  static const double _kChipRadius = 24;

  static List<CategoryChipData> get defaultCategories => [
    const CategoryChipData(label: 'Beaches', icon: Icons.waves_rounded, filterValue: 'Beach'),
    const CategoryChipData(label: 'Mountains', icon: Icons.terrain_rounded, filterValue: 'Mountain'),
    const CategoryChipData(label: 'Heritage', icon: Icons.account_balance_rounded, filterValue: 'Historical'),
    const CategoryChipData(label: 'Festivals', icon: Icons.celebration_rounded, filterValue: 'Festivals'),
  ];

  @override
  Widget build(BuildContext context) {
    final horizontalPadding = _horizontalPadding(context);
    return SizedBox(
      height: 48,
      width: double.infinity,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: EdgeInsets.only(left: horizontalPadding, top: 16, right: horizontalPadding, bottom: 4),
        itemCount: categories.length,
        itemBuilder: (context, index) {
          final chip = categories[index];
          final isSelected = index == selectedIndex;
          return Padding(
            padding: const EdgeInsets.only(right: 12),
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: () => onSelected(index),
                borderRadius: BorderRadius.circular(_kChipRadius),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                  decoration: BoxDecoration(
                    color: isSelected ? AppTheme.primary : Colors.white,
                    borderRadius: BorderRadius.circular(_kChipRadius),
                    boxShadow: isSelected
                        ? null
                        : [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.06),
                              blurRadius: 8,
                              offset: const Offset(0, 2),
                            ),
                          ],
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        chip.icon,
                        size: 22,
                        color: isSelected ? Colors.white : AppTheme.unselectedMuted,
                      ),
                      const SizedBox(width: 10),
                      Text(
                        chip.label,
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: isSelected ? Colors.white : AppTheme.unselectedMuted,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  static double _horizontalPadding(BuildContext context) {
    final w = MediaQuery.sizeOf(context).width;
    if (w >= 1100) return 48;
    if (w >= 600) return 32;
    return 20;
  }
}

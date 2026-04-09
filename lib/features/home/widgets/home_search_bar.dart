import 'package:flutter/material.dart';
import 'package:atmos_trs_system/widgets/app_search_bar.dart';

/// @Deprecated('Use AppSearchBar from widgets/app_search_bar.dart instead.')
/// Full-width rounded search bar. Clean white pill-shaped design.
/// 
/// This widget is deprecated. Use [AppSearchBar] instead for consistency
/// across the entire ATMOS TRS system.
class HomeSearchBar extends StatelessWidget {
  const HomeSearchBar({
    super.key,
    required this.controller,
    required this.onChanged,
    this.onFilterTap,
  });

  final TextEditingController controller;
  final ValueChanged<String> onChanged;
  final VoidCallback? onFilterTap;

  static const double _height = 50;
  static const double _radius = _height / 2;

  @override
  Widget build(BuildContext context) {
    final horizontalPadding = _horizontalPadding(context);
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: horizontalPadding),
      child: Container(
        width: double.infinity,
        height: _height,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(_radius),
          border: Border.all(color: Colors.grey.shade300, width: 1),
        ),
        child: Row(
          children: [
            const SizedBox(width: 16),
            Icon(Icons.search_rounded, color: Colors.grey.shade500, size: 22),
            const SizedBox(width: 12),
            Expanded(
              child: TextField(
                controller: controller,
                onChanged: onChanged,
                style: TextStyle(color: Colors.grey.shade800, fontSize: 15),
                decoration: InputDecoration(
                  hintText: 'Search...',
                  hintStyle: TextStyle(color: Colors.grey.shade400, fontSize: 15),
                  border: InputBorder.none,
                  contentPadding: EdgeInsets.zero,
                ),
              ),
            ),
            GestureDetector(
              onTap: onFilterTap,
              child: Icon(Icons.mic_none_rounded, color: Colors.grey.shade500, size: 22),
            ),
            const SizedBox(width: 16),
          ],
        ),
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

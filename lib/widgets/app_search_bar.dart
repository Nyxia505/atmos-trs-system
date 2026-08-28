import 'package:flutter/material.dart';

/// A reusable, modern search bar widget with rounded design and optional microphone icon.
/// Use this consistently across the entire ATMOS TRS system.
class AppSearchBar extends StatelessWidget {
  const AppSearchBar({
    super.key,
    required this.controller,
    this.hintText = 'Search...',
    this.onChanged,
    this.onSubmitted,
    this.onMicPressed,
    this.showMicrophone = true,
    this.showShadow = true,
    this.backgroundColor = Colors.white,
    this.height = 50,
    this.autofocus = false,
    this.enabled = true,
    this.horizontalPadding,
    this.customShadow,
    this.borderColor,
  });

  final TextEditingController controller;
  final String hintText;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final VoidCallback? onMicPressed;
  final bool showMicrophone;
  final bool showShadow;
  final Color backgroundColor;
  final double height;
  final bool autofocus;
  final bool enabled;
  final double? horizontalPadding;
  /// When set, overrides the default shadow for a custom look (e.g. enhanced depth).
  final List<BoxShadow>? customShadow;

  /// When set, overrides the default grey border (e.g. brand accent on dashboards).
  final Color? borderColor;

  double _getHorizontalPadding(BuildContext context) {
    if (horizontalPadding != null) return horizontalPadding!;
    final w = MediaQuery.sizeOf(context).width;
    if (w >= 1100) return 48;
    if (w >= 600) return 32;
    return 20;
  }

  @override
  Widget build(BuildContext context) {
    final radius = height / 2;
    final padding = _getHorizontalPadding(context);

    return Padding(
      padding: EdgeInsets.symmetric(horizontal: padding),
      child: Container(
        width: double.infinity,
        height: height,
        decoration: BoxDecoration(
          color: backgroundColor,
          borderRadius: BorderRadius.circular(radius),
          border: Border.all(
            color: borderColor ?? Colors.grey.shade300,
            width: 1,
          ),
          boxShadow: customShadow ?? (showShadow
              ? [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.06),
                    blurRadius: 10,
                    offset: const Offset(0, 3),
                  ),
                ]
              : null),
        ),
        child: Row(
          children: [
            const SizedBox(width: 16),
            Icon(Icons.search_rounded, color: Colors.grey.shade500, size: 22),
            const SizedBox(width: 12),
            Expanded(
              child: Theme(
                data: ThemeData(
                  textSelectionTheme: TextSelectionThemeData(
                    cursorColor: Colors.grey.shade600,
                    selectionColor: Colors.orange.withOpacity(0.3),
                  ),
                ),
                child: TextField(
                  controller: controller,
                  onChanged: onChanged,
                  onSubmitted: onSubmitted,
                  autofocus: autofocus,
                  enabled: enabled,
                  cursorColor: Colors.grey.shade600,
                  style: const TextStyle(
                    color: Color(0xFF1F2937),
                    fontSize: 15,
                    fontWeight: FontWeight.w400,
                  ),
                  decoration: InputDecoration(
                    hintText: hintText,
                    hintStyle: TextStyle(color: Colors.grey.shade400, fontSize: 15),
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    disabledBorder: InputBorder.none,
                    errorBorder: InputBorder.none,
                    filled: false,
                    fillColor: Colors.transparent,
                    contentPadding: EdgeInsets.zero,
                    isDense: true,
                  ),
                ),
              ),
            ),
            if (showMicrophone)
              GestureDetector(
                onTap: onMicPressed ?? () {},
                child: Container(
                  padding: const EdgeInsets.all(8),
                  child: Icon(
                    Icons.mic_none_rounded,
                    color: Colors.grey.shade500,
                    size: 22,
                  ),
                ),
              ),
            if (!showMicrophone && controller.text.isNotEmpty)
              GestureDetector(
                onTap: () {
                  controller.clear();
                  onChanged?.call('');
                },
                child: Container(
                  padding: const EdgeInsets.all(8),
                  child: Icon(
                    Icons.close_rounded,
                    color: Colors.grey.shade500,
                    size: 20,
                  ),
                ),
              ),
            const SizedBox(width: 8),
          ],
        ),
      ),
    );
  }
}

/// A dark-themed variant of the search bar for use on dark backgrounds.
class AppSearchBarDark extends StatelessWidget {
  const AppSearchBarDark({
    super.key,
    required this.controller,
    this.hintText = 'Search...',
    this.onChanged,
    this.onSubmitted,
    this.showClearButton = true,
    this.height = 48,
    this.autofocus = false,
    this.horizontalPadding,
  });

  final TextEditingController controller;
  final String hintText;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final bool showClearButton;
  final double height;
  final bool autofocus;
  final double? horizontalPadding;

  double _getHorizontalPadding(BuildContext context) {
    if (horizontalPadding != null) return horizontalPadding!;
    final w = MediaQuery.sizeOf(context).width;
    if (w >= 1100) return 48;
    if (w >= 600) return 32;
    return 20;
  }

  @override
  Widget build(BuildContext context) {
    final radius = height / 2;
    final padding = _getHorizontalPadding(context);

    return Padding(
      padding: EdgeInsets.symmetric(horizontal: padding),
      child: Container(
        width: double.infinity,
        height: height,
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.1),
          borderRadius: BorderRadius.circular(radius),
          border: Border.all(color: Colors.white.withOpacity(0.2), width: 1),
        ),
        child: Row(
          children: [
            const SizedBox(width: 16),
            Icon(Icons.search_rounded, color: Colors.white.withOpacity(0.6), size: 22),
            const SizedBox(width: 12),
            Expanded(
              child: TextField(
                controller: controller,
                onChanged: onChanged,
                onSubmitted: onSubmitted,
                autofocus: autofocus,
                style: const TextStyle(color: Colors.white, fontSize: 15),
                decoration: InputDecoration(
                  hintText: hintText,
                  hintStyle: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 15),
                  border: InputBorder.none,
                  contentPadding: EdgeInsets.zero,
                ),
              ),
            ),
            if (showClearButton && controller.text.isNotEmpty)
              GestureDetector(
                onTap: () {
                  controller.clear();
                  onChanged?.call('');
                },
                child: Container(
                  padding: const EdgeInsets.all(8),
                  child: Icon(
                    Icons.close_rounded,
                    color: Colors.white.withOpacity(0.6),
                    size: 20,
                  ),
                ),
              ),
            const SizedBox(width: 8),
          ],
        ),
      ),
    );
  }
}

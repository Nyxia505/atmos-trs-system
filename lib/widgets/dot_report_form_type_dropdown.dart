import 'package:flutter/material.dart';

import 'package:atmos_trs_system/config/supabase_report_templates_config.dart';

/// Searchable Form Type control used by every DOT Reports category
/// (VAR / DAE / MICE, Events & Announcements, and Matrix Fares).
///
/// This is the extracted VAR/DAE dropdown from [DotReportExportPanel].
/// Categories only differ by [forms] data — not by a second menu design.
class DotReportFormTypeDropdown extends StatelessWidget {
  const DotReportFormTypeDropdown({
    super.key,
    required this.forms,
    required this.selected,
    required this.controller,
    required this.onSelected,
    required this.primaryColor,
    required this.textDark,
    required this.textMuted,
    required this.borderColor,
    this.enabled = true,
  });

  final List<DotFormCatalogEntry> forms;
  final DotFormCatalogEntry selected;
  final TextEditingController controller;
  final ValueChanged<DotFormCatalogEntry> onSelected;
  final Color primaryColor;
  final Color textDark;
  final Color textMuted;
  final Color borderColor;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final menuWidth = constraints.maxWidth.isFinite && constraints.maxWidth > 0
            ? constraints.maxWidth
            : 420.0;
        return DropdownMenu<DotFormCatalogEntry>(
          controller: controller,
          initialSelection: selected,
          enabled: enabled,
          enableFilter: true,
          requestFocusOnTap: true,
          width: menuWidth,
          menuHeight: 360,
          leadingIcon: Icon(
            Icons.search_rounded,
            color: primaryColor,
            size: 20,
          ),
          trailingIcon: Icon(
            Icons.arrow_drop_down_rounded,
            color: textMuted,
          ),
          inputDecorationTheme: InputDecorationTheme(
            isDense: true,
            filled: true,
            fillColor: const Color(0xFFF8FAFC),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 12,
              vertical: 12,
            ),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: borderColor),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: borderColor),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: primaryColor, width: 1.4),
            ),
            hintStyle: TextStyle(color: textMuted, fontSize: 13),
          ),
          textStyle: TextStyle(
            color: textDark,
            fontSize: 13,
            fontWeight: FontWeight.w600,
          ),
          hintText: 'Search form type…',
          filterCallback: (entries, filter) {
            final q = filter.trim();
            if (q.isEmpty || q == selected.title) return entries;
            return [
              for (final e in entries)
                if (e.value.matchesSearch(q)) e,
            ];
          },
          onSelected: (form) {
            if (form == null || !enabled) return;
            onSelected(form);
          },
          dropdownMenuEntries: [
            for (final form in forms)
              DropdownMenuEntry<DotFormCatalogEntry>(
                value: form,
                label: form.title,
                style: ButtonStyle(
                  backgroundColor: WidgetStatePropertyAll(
                    form.id == selected.id
                        ? primaryColor.withValues(alpha: 0.12)
                        : Colors.transparent,
                  ),
                  overlayColor: WidgetStateProperty.resolveWith((states) {
                    if (states.contains(WidgetState.hovered) ||
                        states.contains(WidgetState.focused)) {
                      return primaryColor.withValues(alpha: 0.08);
                    }
                    return Colors.transparent;
                  }),
                ),
                leadingIcon: Icon(
                  form.id == selected.id
                      ? Icons.check_circle_rounded
                      : Icons.auto_awesome_outlined,
                  size: 18,
                  color: primaryColor,
                ),
                labelWidget: SizedBox(
                  width: menuWidth - 72,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        form.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: form.id == selected.id
                              ? primaryColor
                              : textDark,
                          fontWeight: FontWeight.w700,
                          fontSize: 12.5,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        form.menuDescription,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: textMuted,
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

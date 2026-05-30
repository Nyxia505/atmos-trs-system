import 'package:atmos_trs_system/config/app_theme_controller.dart';
import 'package:flutter/material.dart';

/// Bottom sheet for choosing the app accent color preset.
class ThemeColorPickerSheet extends StatelessWidget {
  const ThemeColorPickerSheet({super.key});

  static Future<void> show(BuildContext context) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => const ThemeColorPickerSheet(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final controller = AppThemeController.instance;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: const Color(0xFFE5E7EB),
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'Theme color',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: Color(0xFF111827),
              ),
            ),
            const SizedBox(height: 4),
            const Text(
              'Choose an accent color for buttons and highlights.',
              style: TextStyle(color: Color(0xFF6B7280)),
            ),
            const SizedBox(height: 16),
            ...AppThemeController.presets.map((preset) {
              final selected = controller.presetId == preset.id;
              return ListTile(
                contentPadding: EdgeInsets.zero,
                leading: CircleAvatar(
                  backgroundColor: preset.color,
                  child: selected
                      ? Icon(
                          Icons.check_rounded,
                          color: preset.color.computeLuminance() > 0.55
                              ? Colors.black
                              : Colors.white,
                        )
                      : null,
                ),
                title: Text(
                  preset.label,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                subtitle: Text(preset.description),
                onTap: () async {
                  await controller.setPresetId(preset.id);
                  if (context.mounted) Navigator.pop(context);
                },
              );
            }),
          ],
        ),
      ),
    );
  }
}

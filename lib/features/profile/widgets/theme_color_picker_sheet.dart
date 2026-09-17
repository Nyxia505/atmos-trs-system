import 'package:atmos_trs_system/config/app_theme.dart';
import 'package:atmos_trs_system/config/app_theme_controller.dart';
import 'package:atmos_trs_system/features/navigation/tourist_web_layout.dart';
import 'package:flutter/material.dart';

class ThemeColorPickerSheet {
  ThemeColorPickerSheet._();

  static Future<void> show(BuildContext context) {
    return showTouristDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (ctx) {
        return ListenableBuilder(
          listenable: AppThemeController.instance,
          builder: (context, _) {
            final size = MediaQuery.sizeOf(ctx);
            final maxHeight = size.height * 0.78;
            final surface = Theme.of(ctx).colorScheme.surface;
            final onSurface = Theme.of(ctx).colorScheme.onSurface;
            final muted = AppTheme.unselectedMuted;
            final isDark = AppThemeController.instance.isDarkMode;

            return Center(
              child: Material(
                color: Colors.transparent,
                child: Container(
                  margin: const EdgeInsets.symmetric(horizontal: 24),
                  constraints: BoxConstraints(
                    maxWidth: 420,
                    maxHeight: maxHeight,
                  ),
                  decoration: BoxDecoration(
                    color: surface,
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.12),
                        blurRadius: 24,
                        offset: const Offset(0, 8),
                      ),
                    ],
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(20, 22, 20, 12),
                        child: Column(
                          children: [
                            Text(
                              'Color',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w800,
                                color: onSurface,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Choose accent color and appearance',
                              textAlign: TextAlign.center,
                              style: TextStyle(fontSize: 13, color: muted),
                            ),
                          ],
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                        child: Row(
                          children: [
                            Expanded(
                              child: _AppearanceChip(
                                label: 'Light',
                                icon: Icons.light_mode_outlined,
                                selected: !isDark,
                                onTap: () => AppThemeController.instance
                                    .setDarkMode(false),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: _AppearanceChip(
                                label: 'Dark',
                                icon: Icons.dark_mode_outlined,
                                selected: isDark,
                                onTap: () => AppThemeController.instance
                                    .setDarkMode(true),
                              ),
                            ),
                          ],
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(20, 8, 20, 4),
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: Text(
                            'Accent color',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: muted,
                            ),
                          ),
                        ),
                      ),
                      Flexible(
                        child: ListView.separated(
                          shrinkWrap: true,
                          padding: const EdgeInsets.fromLTRB(8, 0, 8, 16),
                          itemCount: AppThemeController.presets.length,
                          separatorBuilder: (_, __) => const SizedBox(height: 2),
                          itemBuilder: (context, index) {
                            final preset = AppThemeController.presets[index];
                            final selected =
                                AppThemeController.instance.presetId ==
                                    preset.id;
                            return ListTile(
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 12,
                              ),
                              leading: CircleAvatar(
                                backgroundColor: preset.color,
                                radius: 16,
                              ),
                              title: Text(
                                preset.label,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              subtitle: Text(preset.description),
                              trailing: selected
                                  ? Icon(
                                      Icons.check_circle,
                                      color: preset.color,
                                    )
                                  : null,
                              onTap: () async {
                                await AppThemeController.instance
                                    .setPresetId(preset.id);
                              },
                            );
                          },
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                        child: SizedBox(
                          width: double.infinity,
                          child: FilledButton(
                            onPressed: () => Navigator.pop(ctx),
                            child: const Text('Done'),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }
}

class _AppearanceChip extends StatelessWidget {
  const _AppearanceChip({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    return Material(
      color: selected
          ? accent.withValues(alpha: 0.12)
          : Theme.of(context).colorScheme.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 12),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                size: 20,
                color: selected ? accent : AppTheme.unselectedMuted,
              ),
              const SizedBox(width: 8),
              Text(
                label,
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  color: selected ? accent : AppTheme.unselectedMuted,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

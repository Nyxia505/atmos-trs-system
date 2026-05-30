import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Preset accent colors — each chosen for strong contrast with white button text.
class AppThemePreset {
  const AppThemePreset({
    required this.id,
    required this.label,
    required this.color,
    required this.description,
  });

  final String id;
  final String label;
  final Color color;
  final String description;
}

/// Loads / saves user accent color and notifies [MaterialApp] to rebuild.
class AppThemeController extends ChangeNotifier {
  AppThemeController._();
  static final AppThemeController instance = AppThemeController._();

  static const String _prefKey = 'app_theme_preset_id';

  static const String defaultPresetId = 'royal_purple';

  static const List<AppThemePreset> presets = [
    AppThemePreset(
      id: 'royal_purple',
      label: 'Royal Purple',
      color: Color(0xFF7851A9),
      description: 'Default ATMOS look',
    ),
    AppThemePreset(
      id: 'asenso_orange',
      label: 'Asenso Orange',
      color: Color(0xFFF97316),
      description: 'Classic warm accent',
    ),
    AppThemePreset(
      id: 'ocean_blue',
      label: 'Ocean Blue',
      color: Color(0xFF2563EB),
      description: 'Cool & professional',
    ),
    AppThemePreset(
      id: 'forest_green',
      label: 'Forest Green',
      color: Color(0xFF059669),
      description: 'Nature & eco',
    ),
    AppThemePreset(
      id: 'sunset_red',
      label: 'Sunset Red',
      color: Color(0xFFDC2626),
      description: 'Warm & energetic',
    ),
    AppThemePreset(
      id: 'teal',
      label: 'Teal',
      color: Color(0xFF0D9488),
      description: 'Calm coastal',
    ),
    AppThemePreset(
      id: 'deep_navy',
      label: 'Deep Navy',
      color: Color(0xFF1E40AF),
      description: 'Official & trusted',
    ),
  ];

  String _presetId = defaultPresetId;
  bool _loaded = false;

  bool get isLoaded => _loaded;
  String get presetId => _presetId;

  AppThemePreset get currentPreset {
    for (final p in presets) {
      if (p.id == _presetId) return p;
    }
    return presets.first;
  }

  Color get primary => currentPreset.color;

  Color get primaryLight => Color.lerp(primary, Colors.white, 0.22)!;

  Color get primaryDark => Color.lerp(primary, Colors.black, 0.12)!;

  /// White or near-black for text/icons on [primary] backgrounds.
  Color get onPrimary =>
      primary.computeLuminance() > 0.55 ? const Color(0xFF111827) : Colors.white;

  Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getString(_prefKey);
      if (saved != null && presets.any((p) => p.id == saved)) {
        if (saved == 'asenso_orange') {
          _presetId = defaultPresetId;
          await prefs.setString(_prefKey, defaultPresetId);
        } else {
          _presetId = saved;
        }
      }
    } catch (_) {}
    _loaded = true;
    notifyListeners();
  }

  Future<void> setPresetId(String id) async {
    if (!presets.any((p) => p.id == id)) return;
    if (id == _presetId) return;
    _presetId = id;
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefKey, id);
    } catch (_) {}
  }
}

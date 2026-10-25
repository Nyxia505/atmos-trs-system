import 'package:shared_preferences/shared_preferences.dart';

/// Remembers which authorized shell OPTACA / catalog admins last used so a
/// browser refresh can restore Trip Planner admin instead of bouncing away.
abstract final class ModuleShellPrefs {
  static const _key = 'atmos_active_module_shell';

  /// Full Trip Planner OPTACA / catalog admin portal ([TripPlanEntryScreen]
  /// with `adminDashboard: true`).
  static const tripPlannerAdmin = 'trip_planner_admin';

  /// ATMOS Provincial Tourism dashboard.
  static const provincialTourism = 'provincial_tourism';

  static Future<void> setActiveShell(String shell) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, shell);
  }

  static Future<String?> getActiveShell() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_key);
  }

  static Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key);
  }
}

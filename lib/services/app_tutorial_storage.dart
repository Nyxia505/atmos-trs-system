import 'package:shared_preferences/shared_preferences.dart';

/// Tracks whether an in-app guided tour was finished (or skipped) per user.
class AppTutorialStorage {
  AppTutorialStorage._();

  static const touristTour = 'tourist_v2';

  static String _key(String tour, String? uid) {
    final id = (uid == null || uid.isEmpty) ? 'anon' : uid;
    return 'app_tutorial_${tour}_$id';
  }

  static Future<bool> isDone(String tour, String? uid) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_key(tour, uid)) ?? false;
  }

  static Future<void> markDone(String tour, String? uid) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_key(tour, uid), true);
  }

  static Future<void> reset(String tour, String? uid) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key(tour, uid));
  }
}

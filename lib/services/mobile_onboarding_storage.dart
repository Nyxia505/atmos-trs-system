import 'package:shared_preferences/shared_preferences.dart';

/// Tracks whether the first-time mobile app onboarding carousel was completed.
class MobileOnboardingStorage {
  MobileOnboardingStorage._();

  static const _kComplete = 'mobile_onboarding_completed_v1';

  static Future<bool> isComplete() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_kComplete) ?? false;
  }

  static Future<void> markComplete() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kComplete, true);
  }
}

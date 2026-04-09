import 'package:shared_preferences/shared_preferences.dart';

/// First-visit welcome on the landing page (encourage app download on web).
class AppWelcomePrefs {
  AppWelcomePrefs._();

  static const String _keyLandingWelcomeShown = 'landing_welcome_v1_shown';

  static Future<bool> shouldShowLandingWelcome() async {
    final p = await SharedPreferences.getInstance();
    return !(p.getBool(_keyLandingWelcomeShown) ?? false);
  }

  static Future<void> markLandingWelcomeShown() async {
    final p = await SharedPreferences.getInstance();
    await p.setBool(_keyLandingWelcomeShown, true);
  }
}

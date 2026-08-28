/// Loads TripPlan custom fonts declared in [pubspec.yaml].
class TripPlanFonts {
  TripPlanFonts._();

  static Future<void> ensureLoaded() async {
    // Fonts are bundled via pubspec; no runtime loading required.
  }
}

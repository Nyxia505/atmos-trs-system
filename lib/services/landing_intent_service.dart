import 'package:atmos_trs_system/navigation/login_route_args.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// A landing-page action the user wanted before signing in.
class LandingIntent {
  const LandingIntent({
    required this.feature,
    this.municipalityName,
  });

  final String feature;
  final String? municipalityName;

  bool get isVr => feature == LoginRouteArgs.featureVr;
  bool get isItinerary => feature == LoginRouteArgs.featureItinerary;
}

/// Persists VR / itinerary intent across login, signup, and OTP verification.
class LandingIntentService {
  LandingIntentService._();

  static const String _keyFeature = 'landing_intent_feature';
  static const String _keyMunicipality = 'landing_intent_municipality';

  static Future<void> setPending({
    required String feature,
    String? municipalityName,
  }) async {
    if (feature != LoginRouteArgs.featureVr &&
        feature != LoginRouteArgs.featureItinerary) {
      return;
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyFeature, feature);
    final name = municipalityName?.trim();
    if (name != null && name.isNotEmpty) {
      await prefs.setString(_keyMunicipality, name);
    } else {
      await prefs.remove(_keyMunicipality);
    }
  }

  static Future<LandingIntent?> peek() async {
    final prefs = await SharedPreferences.getInstance();
    final feature = prefs.getString(_keyFeature)?.trim();
    if (feature == null || feature.isEmpty) return null;
    if (feature != LoginRouteArgs.featureVr &&
        feature != LoginRouteArgs.featureItinerary) {
      return null;
    }
    final municipality = prefs.getString(_keyMunicipality)?.trim();
    return LandingIntent(
      feature: feature,
      municipalityName:
          municipality != null && municipality.isNotEmpty ? municipality : null,
    );
  }

  static Future<LandingIntent?> consume() async {
    final intent = await peek();
    if (intent != null) {
      await clear();
    }
    return intent;
  }

  static Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_keyFeature);
    await prefs.remove(_keyMunicipality);
  }

  static Map<String, dynamic>? loginArgsFromPending(LandingIntent intent) {
    return LoginRouteArgs.forFeature(
      returnFeature: intent.feature,
      municipalityName: intent.municipalityName,
    );
  }
}

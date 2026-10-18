/// Route arguments for [LoginScreen] when gating landing-page features.
class LoginRouteArgs {
  const LoginRouteArgs({
    this.loginOnly = false,
    this.returnFeature,
    this.municipalityName,
    this.touristOnlySignup = false,
  });

  static const String loginOnlyKey = 'loginOnly';
  static const String returnFeatureKey = 'returnFeature';
  static const String municipalityNameKey = 'municipalityName';
  static const String touristOnlySignupKey = 'touristOnlySignup';

  static const String featureVr = 'vr';
  static const String featureItinerary = 'itinerary';
  static const String featureQr = 'qr';

  final bool loginOnly;
  final String? returnFeature;
  final String? municipalityName;

  /// Trip Planner signup hides Tourist / Establishment / LGU and registers a tourist.
  final bool touristOnlySignup;

  static Map<String, dynamic> forFeature({
    required String returnFeature,
    String? municipalityName,
  }) {
    final name = municipalityName?.trim();
    final touristOnly =
        returnFeature == featureItinerary || returnFeature == featureQr;
    return {
      loginOnlyKey: true,
      returnFeatureKey: returnFeature,
      if (name != null && name.isNotEmpty) municipalityNameKey: name,
      if (touristOnly) touristOnlySignupKey: true,
    };
  }

  static LoginRouteArgs? from(Object? raw) {
    if (raw is! Map) return null;
    final map = Map<String, dynamic>.from(raw);
    final feature = map[returnFeatureKey]?.toString();
    return LoginRouteArgs(
      loginOnly: map[loginOnlyKey] == true,
      returnFeature: feature,
      municipalityName: map[municipalityNameKey]?.toString(),
      touristOnlySignup: map[touristOnlySignupKey] == true ||
          feature == featureItinerary ||
          feature == featureQr,
    );
  }

  String? get subtitle {
    if (!loginOnly) return null;
    final place =
        municipalityName != null && municipalityName!.trim().isNotEmpty
            ? ' for ${municipalityName!.trim()}'
            : '';
    return switch (returnFeature) {
      featureVr => 'Sign in to access VR Tour$place.',
      featureItinerary => 'Sign in to plan your itinerary$place.',
      featureQr => 'Sign in to continue at this destination$place.',
      _ => 'Sign in to continue.',
    };
  }

  /// Trip Planner login/signup keeps TripPlan logo and font.
  bool get usesTripPlannerBranding => returnFeature == featureItinerary;
}

/// Route arguments for [LoginScreen] when gating landing-page features.
class LoginRouteArgs {
  const LoginRouteArgs({
    this.loginOnly = false,
    this.returnFeature,
    this.municipalityName,
  });

  static const String loginOnlyKey = 'loginOnly';
  static const String returnFeatureKey = 'returnFeature';
  static const String municipalityNameKey = 'municipalityName';

  static const String featureVr = 'vr';
  static const String featureItinerary = 'itinerary';

  final bool loginOnly;
  final String? returnFeature;
  final String? municipalityName;

  static Map<String, dynamic> forFeature({
    required String returnFeature,
    String? municipalityName,
  }) {
    final name = municipalityName?.trim();
    return {
      loginOnlyKey: true,
      returnFeatureKey: returnFeature,
      if (name != null && name.isNotEmpty) municipalityNameKey: name,
    };
  }

  static LoginRouteArgs? from(Object? raw) {
    if (raw is! Map) return null;
    final map = Map<String, dynamic>.from(raw);
    return LoginRouteArgs(
      loginOnly: map[loginOnlyKey] == true,
      returnFeature: map[returnFeatureKey]?.toString(),
      municipalityName: map[municipalityNameKey]?.toString(),
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
      _ => 'Sign in to continue.',
    };
  }
}

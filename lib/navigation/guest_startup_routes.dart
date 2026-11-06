/// Guest (unauthenticated) entry routes for the tourist mobile opening flow.
abstract final class GuestStartupRoutes {
  static const splash = '/splash';
  static const welcome = '/welcome';
  static const onboarding = '/mobile-onboarding';
  static const login = '/login';
  static const signup = '/signup';
  static const signupTourist = '/signup-tourist';
  /// QR-first five-question Create Account (entry QR scans).
  static const signupTouristQr = '/signup-tourist-qr';
  /// Simple Log In / Create Account gate after scanning an entry QR.
  static const qrEntry = '/qr-entry';
  static const qrResume = '/qr-resume';
  static const forgotPassword = '/forgot-password';

  static const Set<String> guestForms = {
    splash,
    welcome,
    onboarding,
    login,
    signup,
    signupTourist,
    signupTouristQr,
    qrEntry,
    '/signup-lgu',
    '/signup-lgu-info',
    '/signup-establishment',
    forgotPassword,
  };

  /// Screens the tourist opened intentionally for auth — never auto-replace
  /// these with Landing/Welcome/QR entry while still unauthenticated.
  static const Set<String> explicitAuthForms = {
    login,
    signup,
    signupTourist,
    signupTouristQr,
    forgotPassword,
    '/signup-lgu',
    '/signup-lgu-info',
    '/signup-establishment',
  };

  static const Set<String> signedInDestinations = {
    '/dashboard',
    '/verify-otp',
    '/qr-resume',
    '/tourist-qr-success',
    '/governor-dashboard',
    '/lgu-dashboard',
    '/tourism-dashboard',
    '/provincial-tourism-dashboard',
    '/establishment-dashboard',
    '/trip-planner-admin',
  };

  /// Unauthenticated cold-start destination. Onboarding is opt-in from Welcome.
  ///
  /// Phone-camera QR (no app installed) always opens [qrEntry] so the tourist
  /// can Log In or Create Account immediately — not the marketing landing.
  static String unauthenticatedRoute({
    required bool isWeb,
    required bool hasPendingQr,
  }) {
    if (hasPendingQr) return qrEntry;
    if (isWeb) return '/landing';
    return welcome;
  }

  static bool isExplicitAuthForm(String route) =>
      explicitAuthForms.contains(route);

  /// Splash and onboarding own their own navigation. Auth forms stay put unless
  /// the user became signed-in.
  static bool shouldSkipAuthoritativeReplace({
    required String currentRoute,
    required String authoritative,
  }) {
    if (currentRoute == splash || currentRoute == onboarding) return true;
    if (currentRoute == authoritative) return true;
    // Login / Sign Up / Forgot Password must stay open until the tourist
    // navigates away or a confirmed signed-in destination is ready.
    if (isExplicitAuthForm(currentRoute) &&
        !signedInDestinations.contains(authoritative)) {
      return true;
    }
    final stayingGuest = guestForms.contains(currentRoute);
    final becameSignedIn = signedInDestinations.contains(authoritative);
    if (stayingGuest && !becameSignedIn) return true;
    return false;
  }
}

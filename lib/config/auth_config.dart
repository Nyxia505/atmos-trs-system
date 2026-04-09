/// Holds test user identity for automatic login when testing.
/// In debug builds, the app can skip login and use this UID.
class AuthConfig {
  AuthConfig._();

  /// Test user UID from Firebase (atmos-trs-system).
  /// Use this when testing so the app treats you as this user.
  static const String testUserUid = 'cQiM7z0oBdYHPzA1OEEw6BGjXgZ2';

  /// Test credentials (from Firebase Auth). Used for auto sign-in in debug.
  static const String testEmail = 'atmostrs@gmail.com';
  static const String testPassword = 'AtmosTRS@2026';

  /// Current user UID after login (or test UID in debug when auto-logged in).
  static String? currentUserUid;
}

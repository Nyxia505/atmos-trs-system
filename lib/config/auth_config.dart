/// Holds test user identity for automatic login when testing.
/// In debug builds, the app can skip login and use this UID.
class AuthConfig {
  AuthConfig._();

  /// Test user UID from Firebase (atmos-trs-system).
  /// Use this when testing so the app treats you as this user.
  static const String testUserUid = String.fromEnvironment(
    'AUTH_TEST_USER_UID',
    defaultValue: '',
  );

  /// Test credentials for auto sign-in in debug. Pass via `--dart-define`.
  static const String testEmail = String.fromEnvironment(
    'AUTH_TEST_EMAIL',
    defaultValue: '',
  );

  static const String testPassword = String.fromEnvironment(
    'AUTH_TEST_PASSWORD',
    defaultValue: '',
  );

  /// Current user UID after login (or test UID in debug when auto-logged in).
  static String? currentUserUid;
}

import 'package:shared_preferences/shared_preferences.dart';

/// User roles for the ATMOS TRS system
enum UserRole {
  tourist,
  governor,
  tourism,
}

/// Persists login session so user stays logged in until they tap Logout.
class SessionStorage {
  SessionStorage._();

  static const _keyUserUid = 'auth_user_uid';
  static const _keyUserRole = 'auth_user_role';
  static const _keyUserEmail = 'auth_user_email';
  static const _keyMunicipalityId = 'auth_municipality_id';

  /// Admin credentials
  static const String governorEmail = 'governor.atmos@misocc-demo.ph';
  static const String governorPassword = 'Asenso@MISocc#2026!Gov';
  static const String tourismEmail = 'tourismoffice.atmos@misocc-demo.ph';
  static const String tourismPassword = 'ATMOS#Tourism@2026_MisOcc!';

  /// Password used by tourism dashboard "Change Password" validation (prefs override or demo default).
  static Future<String> getEffectiveTourismPassword() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('tourism_password') ?? tourismPassword;
  }

  /// Returns true if the email local part starts with "tourism." (e.g. tourism.oroquieta@misocc.gov.ph).
  static bool _isTourismMunicipalityEmail(String email) {
    final normalized = email.trim().toLowerCase();
    final atIndex = normalized.indexOf('@');
    if (atIndex <= 0) return false;
    final localPart = normalized.substring(0, atIndex);
    return localPart.startsWith('tourism.');
  }

  /// Extracts municipalityId from tourism email (e.g. tourism.oroquieta@misocc.gov.ph → oroquieta).
  /// Returns null if email does not match tourism.*@* pattern.
  static String? getMunicipalityIdFromTourismEmail(String email) {
    final normalized = email.trim().toLowerCase();
    final atIndex = normalized.indexOf('@');
    if (atIndex <= 0) return null;
    final localPart = normalized.substring(0, atIndex);
    if (!localPart.startsWith('tourism.')) return null;
    final id = localPart.substring('tourism.'.length);
    return id.isEmpty ? null : id;
  }

  /// Determines user role based on email
  static UserRole getRoleFromEmail(String email) {
    final normalizedEmail = email.toLowerCase().trim();
    if (normalizedEmail == governorEmail.toLowerCase()) {
      return UserRole.governor;
    }
    if (normalizedEmail == tourismEmail.toLowerCase() || _isTourismMunicipalityEmail(email)) {
      return UserRole.tourism;
    }
    return UserRole.tourist;
  }

  /// Validates admin credentials. Returns true only for governor and old tourism demo.
  /// For tourism.*@* emails returns false so login uses Firebase Auth.
  ///
  /// Prefer [validateCredentialsAsync] so passwords changed in Settings (SharedPreferences)
  /// are respected at login.
  static bool validateCredentials(String email, String password) {
    final normalizedEmail = email.toLowerCase().trim();
    if (normalizedEmail == governorEmail.toLowerCase()) {
      return password == governorPassword;
    }
    if (normalizedEmail == tourismEmail.toLowerCase()) {
      return password == tourismPassword;
    }
    // tourism.oroquieta@... etc. → validate via Firebase, not here
    return false;
  }

  /// Validates the governor account password against SharedPreferences override or demo default.
  /// Use this from UI instead of comparing to [governorPassword] directly.
  static Future<bool> matchesStoredGovernorPassword(String password) async {
    final prefs = await SharedPreferences.getInstance();
    final effective = prefs.getString('governor_password') ?? governorPassword;
    return password == effective;
  }

  /// Same as [validateCredentials] but uses stored overrides from governor/tourism Settings.
  static Future<bool> validateCredentialsAsync(
    String email,
    String password,
  ) async {
    final normalizedEmail = email.toLowerCase().trim();
    final prefs = await SharedPreferences.getInstance();
    if (normalizedEmail == governorEmail.toLowerCase()) {
      final effective = prefs.getString('governor_password') ?? governorPassword;
      return password == effective;
    }
    if (normalizedEmail == tourismEmail.toLowerCase()) {
      final effective = prefs.getString('tourism_password') ?? tourismPassword;
      return password == effective;
    }
    return false;
  }

  /// Returns stored user UID if the user previously logged in and did not log out.
  static Future<String?> getStoredUser() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_keyUserUid);
  }

  /// Returns stored user role
  static Future<UserRole> getStoredRole() async {
    final prefs = await SharedPreferences.getInstance();
    final roleStr = prefs.getString(_keyUserRole);
    if (roleStr == 'governor') return UserRole.governor;
    if (roleStr == 'tourism') return UserRole.tourism;
    return UserRole.tourist;
  }

  /// Returns stored user email
  static Future<String?> getStoredEmail() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_keyUserEmail);
  }

  /// Call after successful login to persist session across app restarts.
  static Future<void> saveSession(String uid, {UserRole role = UserRole.tourist, String? email, String? municipalityId}) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyUserUid, uid);
    await prefs.setString(_keyUserRole, role.name);
    if (email != null) {
      await prefs.setString(_keyUserEmail, email);
    }
    if (municipalityId != null) {
      await prefs.setString(_keyMunicipalityId, municipalityId);
    } else {
      await prefs.remove(_keyMunicipalityId);
    }
  }

  /// Returns stored municipality ID for tourism users (e.g. oroquieta, ozamiz).
  static Future<String?> getStoredMunicipalityId() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_keyMunicipalityId);
  }

  /// Call when user taps Logout. Clears stored session so next launch shows login.
  static Future<void> clearSession() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_keyUserUid);
    await prefs.remove(_keyUserRole);
    await prefs.remove(_keyUserEmail);
    await prefs.remove(_keyMunicipalityId);
  }

  /// Returns the dashboard route based on role
  static String getDashboardRoute(UserRole role) {
    switch (role) {
      case UserRole.governor:
        return '/governor-dashboard';
      case UserRole.tourism:
        return '/tourism-dashboard';
      case UserRole.tourist:
        return '/dashboard';
    }
  }
}

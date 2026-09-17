import 'package:shared_preferences/shared_preferences.dart';

/// User roles for the ATMOS TRS system
enum UserRole {
  tourist,
  governor,
  tourism,
  provincialTourism,
  tourismEstablishment,
}

/// Persists login session so user stays logged in until they tap Logout.
class SessionStorage {
  SessionStorage._();

  static const _keyUserUid = 'auth_user_uid';
  static const _keyUserRole = 'auth_user_role';
  static const _keyUserEmail = 'auth_user_email';
  static const _keyMunicipalityId = 'auth_municipality_id';
  static const _keyTouristEmailVerifiedPrefix = 'tourist_email_verified_';

  /// Admin credentials
  static const String governorEmail = 'governor.atmos@misocc-demo.ph';
  /// Current demo default (also used when SharedPreferences has no override).
  static const String governorPassword = 'Admin123@';
  /// Previous demo password — kept so login can sync Firebase Auth after a Settings change.
  static const String governorPasswordLegacy = 'Asenso@MISocc#2026!Gov';
  static const String tourismEmail = 'tourismoffice.atmos@misocc-demo.ph';
  static const String tourismPassword = 'ATMOS#Tourism@2026_MisOcc!';
  /// Provincial Tourism Office (province-wide ops — not LGU municipality).
  static const String provincialTourismEmail = 'tourism@gmail.com';
  static const String provincialTourismPassword = 'OPTACA2026!';
  /// Previous demo account — still accepted for local/dev continuity.
  static const String provincialTourismEmailLegacy =
      'provincial.tourism@misocc-demo.ph';
  static const String provincialTourismPasswordLegacy =
      'ATMOS#ProvTourism@2026_MisOcc!';

  static const String _keyGovernorPassword = 'governor_password';
  static const String _keyTourismPassword = 'tourism_password';
  static const String _keyProvincialTourismPassword =
      'provincial_tourism_password';

  /// True for any email that maps to the Provincial Tourism Office dashboard.
  static bool isProvincialTourismEmail(String email) {
    final normalized = email.toLowerCase().trim();
    return normalized == provincialTourismEmail.toLowerCase() ||
        normalized == provincialTourismEmailLegacy.toLowerCase();
  }

  /// Passwords accepted for provincial tourism demo accounts (prefs override first).
  static Future<List<String>> knownProvincialTourismPasswords() async {
    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getString(_keyProvincialTourismPassword);
    return <String>{
      if (stored != null && stored.isNotEmpty) stored,
      provincialTourismPassword,
      provincialTourismPasswordLegacy,
    }.toList();
  }

  /// Passwords that may still be valid on Firebase Auth for the governor demo account.
  static Future<List<String>> knownGovernorPasswords() async {
    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getString(_keyGovernorPassword);
    return <String>{
      if (stored != null && stored.isNotEmpty) stored,
      governorPassword,
      governorPasswordLegacy,
    }.toList();
  }

  /// Persists the password used at a successful governor demo login.
  static Future<void> persistGovernorPassword(String password) async {
    if (password.isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyGovernorPassword, password);
  }

  /// Password used by tourism dashboard "Change Password" validation (prefs override or demo default).
  static Future<String> getEffectiveTourismPassword() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_keyTourismPassword) ?? tourismPassword;
  }

  /// Password used by provincial tourism Settings (prefs override or demo default).
  static Future<String> getEffectiveProvincialTourismPassword() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_keyProvincialTourismPassword) ??
        provincialTourismPassword;
  }

  static Future<void> persistProvincialTourismPassword(String password) async {
    if (password.isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyProvincialTourismPassword, password);
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
    if (isProvincialTourismEmail(normalizedEmail)) {
      return UserRole.provincialTourism;
    }
    if (normalizedEmail == tourismEmail.toLowerCase() ||
        _isTourismMunicipalityEmail(email)) {
      return UserRole.tourism;
    }
    return UserRole.tourist;
  }

  /// Validates admin credentials. Returns true only for governor and demo staff.
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
    if (isProvincialTourismEmail(normalizedEmail)) {
      return password == provincialTourismPassword ||
          password == provincialTourismPasswordLegacy;
    }
    // tourism.oroquieta@... etc. → validate via Firebase, not here
    return false;
  }

  /// Validates the governor account password against SharedPreferences override or demo default.
  /// Use this from UI instead of comparing to [governorPassword] directly.
  static Future<bool> matchesStoredGovernorPassword(String password) async {
    final known = await knownGovernorPasswords();
    return known.contains(password);
  }

  /// Same as [validateCredentials] but uses stored overrides from governor/tourism Settings.
  /// Governor also accepts the legacy demo password so Firebase Auth can be synced.
  static Future<bool> validateCredentialsAsync(
    String email,
    String password,
  ) async {
    final normalizedEmail = email.toLowerCase().trim();
    final prefs = await SharedPreferences.getInstance();
    if (normalizedEmail == governorEmail.toLowerCase()) {
      final known = await knownGovernorPasswords();
      return known.contains(password);
    }
    if (normalizedEmail == tourismEmail.toLowerCase()) {
      final effective =
          prefs.getString(_keyTourismPassword) ?? tourismPassword;
      return password == effective;
    }
    if (isProvincialTourismEmail(normalizedEmail)) {
      final known = await knownProvincialTourismPasswords();
      return known.contains(password);
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
    if (roleStr == 'provincialTourism' ||
        roleStr == 'provincial_tourism' ||
        roleStr == 'tourism_province') {
      return UserRole.provincialTourism;
    }
    if (roleStr == 'tourism') return UserRole.tourism;
    if (roleStr == 'tourismEstablishment' ||
        roleStr == 'tourism_establishment' ||
        roleStr == 'establishment') {
      return UserRole.tourismEstablishment;
    }
    return UserRole.tourist;
  }

  /// Returns stored user email
  static Future<String?> getStoredEmail() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_keyUserEmail);
  }

  /// Call after successful login to persist session across app restarts.
  static Future<void> saveSession(
    String uid, {
    UserRole role = UserRole.tourist,
    String? email,
    String? municipalityId,
  }) async {
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

  /// Local cache: tourist finished in-app email OTP (survives app restarts).
  static Future<bool> isTouristEmailVerifiedCached(String uid) async {
    if (uid.isEmpty) return false;
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool('$_keyTouristEmailVerifiedPrefix$uid') ?? false;
  }

  static Future<void> setTouristEmailVerified(
    String uid, {
    required bool verified,
  }) async {
    if (uid.isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    final key = '$_keyTouristEmailVerifiedPrefix$uid';
    if (verified) {
      await prefs.setBool(key, true);
    } else {
      await prefs.remove(key);
    }
  }

  /// Call when user taps Logout. Clears stored session so next launch shows login.
  static Future<void> clearSession() async {
    final prefs = await SharedPreferences.getInstance();
    final uid = prefs.getString(_keyUserUid);
    if (uid != null && uid.isNotEmpty) {
      await prefs.remove('$_keyTouristEmailVerifiedPrefix$uid');
    }
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
      case UserRole.provincialTourism:
        return '/provincial-tourism-dashboard';
      case UserRole.tourism:
        return '/lgu-dashboard';
      case UserRole.tourismEstablishment:
        return '/establishment-dashboard';
      case UserRole.tourist:
        return '/dashboard';
    }
  }

  /// True for any staff role (Governor, LGU tourism, Provincial Tourism).
  static bool isStaffRole(UserRole role) =>
      role == UserRole.governor ||
      role == UserRole.tourism ||
      role == UserRole.provincialTourism;
}

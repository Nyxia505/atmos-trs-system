import 'package:atmos_trs_system/utils/email_utils.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Stores user profile data from signup for display in Profile tab.
class UserProfileStorage {
  UserProfileStorage._();

  static UserProfile? _memoryCache;
  static String? _ownerUid;
  static bool _diskLoaded = false;

  /// In-memory profile for the signed-in account only.
  static UserProfile? get cachedProfile {
    final p = _memoryCache;
    if (p == null || p.firstName.trim().isEmpty) return null;
    if (!_belongsToSignedInUser(p)) return null;
    return p;
  }

  /// True when this profile was saved for the current Firebase user.
  /// Older installs have no owner id, so the saved email is compared instead.
  static bool _belongsToSignedInUser(UserProfile profile) {
    final auth = FirebaseAuth.instance.currentUser;
    if (auth == null) return true;
    final owner = _ownerUid;
    if (owner != null && owner.isNotEmpty) return owner == auth.uid;
    final authEmail = normalizeEmail(auth.email ?? '');
    if (authEmail.isEmpty) return true;
    return normalizeEmail(profile.email) == authEmail;
  }

  /// Loads SharedPreferences into [cachedProfile] before the first frame.
  static Future<void> warmCache() async {
    await getUserProfile();
  }

  static const _keyOwnerUid = 'user_profile_owner_uid';
  static const _keyFirstName = 'user_first_name';
  static const _keyMiddleName = 'user_middle_name';
  static const _keyLastName = 'user_last_name';
  static const _keySuffix = 'user_suffix';
  static const _keySex = 'user_sex';
  static const _keyCivilStatus = 'user_civil_status';
  static const _keyNationality = 'user_nationality';
  static const _keyDateOfBirth = 'user_date_of_birth';
  static const _keyMobile = 'user_mobile';
  static const _keyEmail = 'user_email';
  static const _keyCountry = 'user_country';
  static const _keyProvince = 'user_province';
  static const _keyCity = 'user_city';
  static const _keyStreet = 'user_street';
  static const _keyBarangay = 'user_barangay';
  static const _keyTouristId = 'user_tourist_id';
  static const _keyProfileImage = 'user_profile_image';
  static const _keyProfilePhotoUrl = 'user_profile_photo_url';

  /// SharedPreferences / platform limits — avoid storing multi‑MB base64 strings.
  static const int maxProfileImageBase64Length = 120000;

  /// Save all user profile data after signup
  static Future<void> saveUserProfile({
    required String firstName,
    String? middleName,
    required String lastName,
    String? suffix,
    String? sex,
    String? civilStatus,
    String? nationality,
    String? dateOfBirth,
    required String mobile,
    required String email,
    String? country,
    String? province,
    String? city,
    String? street,
    String? barangay,
    required String touristId,
    String? profileImageBase64,
    String? profilePhotoUrl,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final ownerUid = FirebaseAuth.instance.currentUser?.uid ?? '';
    if (ownerUid.isNotEmpty) {
      await prefs.setString(_keyOwnerUid, ownerUid);
      _ownerUid = ownerUid;
    }
    await prefs.setString(_keyFirstName, firstName);
    if (middleName != null) await prefs.setString(_keyMiddleName, middleName);
    await prefs.setString(_keyLastName, lastName);
    if (suffix != null) await prefs.setString(_keySuffix, suffix);
    if (sex != null) await prefs.setString(_keySex, sex);
    if (civilStatus != null) await prefs.setString(_keyCivilStatus, civilStatus);
    if (nationality != null) await prefs.setString(_keyNationality, nationality);
    if (dateOfBirth != null) await prefs.setString(_keyDateOfBirth, dateOfBirth);
    await prefs.setString(_keyMobile, mobile);
    await prefs.setString(_keyEmail, email);
    if (country != null) await prefs.setString(_keyCountry, country);
    if (province != null) await prefs.setString(_keyProvince, province);
    if (city != null) await prefs.setString(_keyCity, city);
    if (street != null) await prefs.setString(_keyStreet, street);
    if (barangay != null) await prefs.setString(_keyBarangay, barangay);
    await prefs.setString(_keyTouristId, touristId);
    if (profileImageBase64 != null &&
        profileImageBase64.length <= maxProfileImageBase64Length) {
      await prefs.setString(_keyProfileImage, profileImageBase64);
    }
    if (profilePhotoUrl != null) await prefs.setString(_keyProfilePhotoUrl, profilePhotoUrl);
    _memoryCache = UserProfile(
      firstName: firstName,
      middleName: middleName,
      lastName: lastName,
      suffix: suffix,
      sex: sex,
      civilStatus: civilStatus,
      nationality: nationality,
      dateOfBirth: dateOfBirth,
      mobile: mobile,
      email: email,
      country: country,
      province: province,
      city: city,
      street: street,
      barangay: barangay,
      touristId: touristId,
      profileImageBase64: profileImageBase64,
      profilePhotoUrl: profilePhotoUrl,
    );
  }

  /// Persists only the Storage download URL (e.g. after hydrating from Firestore).
  static Future<void> updateProfilePhotoUrl(String url) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyProfilePhotoUrl, url);
    final cached = _memoryCache;
    if (cached != null) {
      _memoryCache = cached.withProfilePhotoUrl(url);
    }
  }

  /// Persists a Firestore-fallback photo and drops the old Storage URL (URL wins in UI).
  static Future<void> updateProfileImageBase64(String b64) async {
    final prefs = await SharedPreferences.getInstance();
    if (b64.length <= maxProfileImageBase64Length) {
      await prefs.setString(_keyProfileImage, b64);
    }
    await prefs.remove(_keyProfilePhotoUrl);
    final cached = _memoryCache;
    if (cached != null) {
      _memoryCache = cached.withProfileImageBase64(b64);
    }
  }

  /// Get user profile data for the signed-in account.
  /// A profile left on the device by a previous login is discarded.
  static Future<UserProfile?> getUserProfile() async {
    await _loadFromDisk();
    final profile = _memoryCache;
    if (profile == null || profile.firstName.trim().isEmpty) return null;
    if (_belongsToSignedInUser(profile)) return profile;
    await clearUserProfile();
    return null;
  }

  static Future<void> _loadFromDisk() async {
    if (_diskLoaded) return;
    final prefs = await SharedPreferences.getInstance();
    _ownerUid = prefs.getString(_keyOwnerUid);
    final firstName = prefs.getString(_keyFirstName);
    _diskLoaded = true;
    if (firstName == null) return;

    _memoryCache = UserProfile(
      firstName: firstName,
      middleName: prefs.getString(_keyMiddleName),
      lastName: prefs.getString(_keyLastName) ?? '',
      suffix: prefs.getString(_keySuffix),
      sex: prefs.getString(_keySex),
      civilStatus: prefs.getString(_keyCivilStatus),
      nationality: prefs.getString(_keyNationality),
      dateOfBirth: prefs.getString(_keyDateOfBirth),
      mobile: prefs.getString(_keyMobile) ?? '',
      email: prefs.getString(_keyEmail) ?? '',
      country: prefs.getString(_keyCountry),
      province: prefs.getString(_keyProvince),
      city: prefs.getString(_keyCity),
      street: prefs.getString(_keyStreet),
      barangay: prefs.getString(_keyBarangay),
      touristId: prefs.getString(_keyTouristId) ?? '',
      profileImageBase64: prefs.getString(_keyProfileImage),
      profilePhotoUrl: prefs.getString(_keyProfilePhotoUrl),
    );
  }

  /// Clear user profile data on logout
  static Future<void> clearUserProfile() async {
    _memoryCache = null;
    _ownerUid = null;
    _diskLoaded = true;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_keyOwnerUid);
    await prefs.remove(_keyFirstName);
    await prefs.remove(_keyMiddleName);
    await prefs.remove(_keyLastName);
    await prefs.remove(_keySuffix);
    await prefs.remove(_keySex);
    await prefs.remove(_keyCivilStatus);
    await prefs.remove(_keyNationality);
    await prefs.remove(_keyDateOfBirth);
    await prefs.remove(_keyMobile);
    await prefs.remove(_keyEmail);
    await prefs.remove(_keyCountry);
    await prefs.remove(_keyProvince);
    await prefs.remove(_keyCity);
    await prefs.remove(_keyStreet);
    await prefs.remove(_keyBarangay);
    await prefs.remove(_keyTouristId);
    await prefs.remove(_keyProfileImage);
    await prefs.remove(_keyProfilePhotoUrl);
  }
}

/// User profile data model
class UserProfile {
  final String firstName;
  final String? middleName;
  final String lastName;
  final String? suffix;
  final String? sex;
  final String? civilStatus;
  final String? nationality;
  final String? dateOfBirth;
  final String mobile;
  final String email;
  final String? country;
  final String? province;
  final String? city;
  final String? street;
  final String? barangay;
  final String touristId;
  final String? profileImageBase64;
  final String? profilePhotoUrl;

  UserProfile({
    required this.firstName,
    this.middleName,
    required this.lastName,
    this.suffix,
    this.sex,
    this.civilStatus,
    this.nationality,
    this.dateOfBirth,
    required this.mobile,
    required this.email,
    this.country,
    this.province,
    this.city,
    this.street,
    this.barangay,
    required this.touristId,
    this.profileImageBase64,
    this.profilePhotoUrl,
  });

  String get fullName {
    final middle = middleName?.isNotEmpty == true ? '${middleName![0]}.' : '';
    final suf = suffix?.isNotEmpty == true && suffix!.toLowerCase() != 'none'
        ? ' $suffix'
        : '';
    return '$firstName $middle $lastName$suf'.replaceAll('  ', ' ').trim();
  }

  String get fullAddress {
    final parts = <String>[];
    if (street?.isNotEmpty == true) parts.add(street!);
    if (barangay?.isNotEmpty == true) parts.add('Brgy. $barangay');
    if (city?.isNotEmpty == true) parts.add(city!);
    if (province?.isNotEmpty == true) parts.add(province!);
    if (country?.isNotEmpty == true) parts.add(country!);
    return parts.join(', ');
  }

  /// Copy with an updated Firebase Storage profile photo URL (canonical for UI).
  UserProfile withProfilePhotoUrl(String url) {
    return UserProfile(
      firstName: firstName,
      middleName: middleName,
      lastName: lastName,
      suffix: suffix,
      sex: sex,
      civilStatus: civilStatus,
      nationality: nationality,
      dateOfBirth: dateOfBirth,
      mobile: mobile,
      email: email,
      country: country,
      province: province,
      city: city,
      street: street,
      barangay: barangay,
      touristId: touristId,
      profileImageBase64: profileImageBase64,
      profilePhotoUrl: url,
    );
  }

  /// Copy with an inline (Firestore fallback) photo and no Storage URL.
  UserProfile withProfileImageBase64(String b64) {
    return UserProfile(
      firstName: firstName,
      middleName: middleName,
      lastName: lastName,
      suffix: suffix,
      sex: sex,
      civilStatus: civilStatus,
      nationality: nationality,
      dateOfBirth: dateOfBirth,
      mobile: mobile,
      email: email,
      country: country,
      province: province,
      city: city,
      street: street,
      barangay: barangay,
      touristId: touristId,
      profileImageBase64: b64,
    );
  }
}

import 'package:atmos_trs_system/config/auth_config.dart';
import 'package:atmos_trs_system/services/otp_delivery_service.dart';
import 'package:atmos_trs_system/services/otp_service.dart';
import 'package:atmos_trs_system/services/pending_registration_cache.dart';
import 'package:atmos_trs_system/services/registration_municipality_resolver.dart';
import 'package:atmos_trs_system/services/tourist_registration_service.dart';
import 'package:atmos_trs_system/services/user_directory_service.dart';
import 'package:atmos_trs_system/utils/email_utils.dart';
import 'package:atmos_trs_system/utils/signup_field_validation.dart';
import 'package:atmos_trs_system/utils/tourist_id_helper.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:uuid/uuid.dart';

/// Result of the QR-first five-question tourist registration handoff to OTP.
class QrTouristBasicRegistrationResult {
  const QrTouristBasicRegistrationResult({
    required this.contactEmail,
    required this.delivery,
  });

  final String contactEmail;
  final OtpDeliveryResult delivery;
}

/// Client-facing five basic questions (QR entry Create Account).
///
/// Mapped to existing `tourists` fields. Auth password + legal consent are a
/// separate secure step — not part of the five questions.
abstract final class QrTouristBasicRegistrationFields {
  static const fullName = 'fullName';
  static const nationality = 'nationality';
  static const placeOfOrigin = 'placeOfOrigin';
  static const contactMobile = 'contactMobile';
  static const verificationEmail = 'verificationEmail';

  /// Suggested client set (no separate locked five-field doc in-repo).
  static const labels = <String>[
    'Full Name',
    'Nationality',
    'Place of Origin',
    'Contact Information',
    'Email (account verification)',
  ];
}

/// Builds deferred Auth + OTP pending registration from the QR five-question form.
abstract final class QrTouristBasicRegistrationService {
  static const _nationalityHomeCountry = <String, String>{
    'Filipino': 'Philippines',
    'Filipino (dual citizen)': 'Philippines',
    'American': 'United States',
    'Australian': 'Australia',
    'British': 'United Kingdom',
    'Canadian': 'Canada',
    'Chinese': 'China',
    'French': 'France',
    'German': 'Germany',
    'Indian': 'India',
    'Indonesian': 'Indonesia',
    'Italian': 'Italy',
    'Japanese': 'Japan',
    'Korean': 'South Korea',
    'Malaysian': 'Malaysia',
    'Singaporean': 'Singapore',
    'Spanish': 'Spain',
    'Thai': 'Thailand',
    'Vietnamese': 'Vietnam',
  };

  static const nationalities = <String>[
    'Filipino',
    'Filipino (dual citizen)',
    'American',
    'Australian',
    'British',
    'Canadian',
    'Chinese',
    'French',
    'German',
    'Indian',
    'Indonesian',
    'Italian',
    'Japanese',
    'Korean',
    'Malaysian',
    'Singaporean',
    'Spanish',
    'Thai',
    'Vietnamese',
    'Other',
  ];

  static String? validateFiveQuestions({
    required String fullName,
    required String? nationality,
    required String placeOfOrigin,
    required String mobileLocal,
    required String dialCode,
    required String email,
  }) {
    final name = fullName.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (name.length < 2) return 'Enter your full name.';
    if (!RegExp(r"^[A-Za-zÀ-ÖØ-öø-ÿ .'-]+$").hasMatch(name)) {
      return 'Use letters only for your full name.';
    }
    if (nationality == null || nationality.trim().isEmpty) {
      return 'Select your nationality.';
    }
    if (placeOfOrigin.trim().length < 2) {
      return 'Enter your place of origin.';
    }
    final mobileErr = validateMobileForDialCode(mobileLocal, dialCode);
    if (mobileErr != null) return mobileErr;
    final normalized = normalizeEmail(email);
    if (!isValidEmailFormat(normalized)) {
      return 'Enter a valid email for account verification.';
    }
    return null;
  }

  static String? validateSecureStep({
    required String password,
    required String confirmPassword,
    required bool agreedToTerms,
  }) {
    if (!agreedToTerms) {
      return 'Please agree to the Terms and Data Privacy notice.';
    }
    if (password.length < 8) {
      return 'Password must be at least 8 characters.';
    }
    if (password != confirmPassword) {
      return 'Passwords do not match.';
    }
    return null;
  }

  static ({String firstName, String lastName, String fullName}) splitFullName(
    String raw,
  ) {
    final cleaned = raw.trim().replaceAll(RegExp(r'\s+'), ' ');
    final parts = cleaned.split(' ');
    if (parts.length == 1) {
      return (firstName: parts.first, lastName: parts.first, fullName: cleaned);
    }
    final first = parts.first;
    final last = parts.sublist(1).join(' ');
    return (firstName: first, lastName: last, fullName: cleaned);
  }

  static Future<QrTouristBasicRegistrationResult> submitDeferred({
    required String fullName,
    required String nationality,
    required String placeOfOrigin,
    required String mobileLocal,
    required String dialCode,
    required String email,
    required String password,
  }) async {
    if (Firebase.apps.isEmpty) {
      throw StateError(
        'Firebase is not initialized. Check firebase_options / FlutterFire.',
      );
    }

    final contactEmail = normalizeEmail(email);
    final names = splitFullName(fullName);
    final mobile = composeE164Mobile(dialCode, mobileLocal);
    final country = _nationalityHomeCountry[nationality] ??
        (nationality == 'Filipino' || nationality.startsWith('Filipino')
            ? 'Philippines'
            : 'Other');
    final isPh = country == 'Philippines';
    final origin = placeOfOrigin.trim().replaceAll(RegExp(r'\s+'), ' ');
    final province = isPh ? 'Misamis Occidental' : origin;
    final city = origin;

    final fiveErr = validateFiveQuestions(
      fullName: fullName,
      nationality: nationality,
      placeOfOrigin: placeOfOrigin,
      mobileLocal: mobileLocal,
      dialCode: dialCode,
      email: email,
    );
    if (fiveErr != null) throw StateError(fiveErr);
    final secureErr = validateSecureStep(
      password: password,
      confirmPassword: password,
      agreedToTerms: true,
    );
    if (secureErr != null) throw StateError(secureErr);

    try {
      await FirebaseAuth.instance.signOut();
    } catch (_) {}

    final alreadyRegistered =
        await UserDirectoryService.emailHasDurableRegistration(contactEmail);
    if (alreadyRegistered) {
      throw StateError(
        'This email is already registered. Please sign in instead.',
      );
    }

    final pendingId = const Uuid().v4();
    final otp = OtpService.generateSixDigitOtp();
    await OtpService.saveOtpPreAuth(
      pendingId: pendingId,
      email: contactEmail,
      otp: otp,
    );

    final touristId = TouristIdHelper.generate(province: province);
    final registrationMunicipalityId =
        RegistrationMunicipalityResolver.fromHomeAddress(
      country: country,
      province: province,
      city: city,
    );

    final touristData = <String, dynamic>{
      'touristId': touristId,
      'firebaseUid': pendingId,
      'firstName': names.firstName,
      'middleName': '',
      'lastName': names.lastName,
      'fullName': names.fullName,
      'suffix': null,
      'sex': null,
      'nationality': nationality,
      'dateOfBirth': null,
      'mobile': mobile,
      'email': contactEmail,
      'authEmail': contactEmail,
      'country': country,
      'province': province,
      'city': city,
      'street': '',
      'barangay': '',
      'placeOfOrigin': origin,
      'profilePhotoUrl': null,
      'profilePhotoPending': false,
      'isLocal': isPh,
      'localOrForeign': isPh ? 'Local' : 'Foreign',
      'transportation': '',
      'travelHistory': {
        'firstDestination': '',
        'secondDestination': '',
        'thirdDestination': '',
        'howHeardAbout': '',
      },
      'receiveUpdates': true,
      if (registrationMunicipalityId != null &&
          registrationMunicipalityId.isNotEmpty)
        'registrationMunicipalityId': registrationMunicipalityId,
      'status': 'Active',
      'totalVisits': 0,
      'isVerified': false,
      'verifiedCitizen': true,
      'level': 1,
      'levelTitle': 'Explorer',
      'minorAccountHolder': false,
      'parentGuardianFullName': null,
      'travelPartyChildren': <Map<String, dynamic>>[],
      'accompanyingChildrenCount': 0,
      'partyHeadcount': 1,
      'registrationSource': 'qr_entry_basic',
    };

    final userData = <String, dynamic>{
      'firebaseUid': pendingId,
      'email': contactEmail,
      'fullName': names.fullName,
      'role': 'tourist',
      'municipality': '',
      'isVerified': false,
    };

    final delivery = await OtpDeliveryService.deliverVerificationCode(
      uid: pendingId,
      email: contactEmail,
      displayName: names.fullName,
      otp: otp,
      mobile: mobile,
      notifyOnThisDevice: false,
      trySms: false,
      otpAlreadyInFirestore: true,
      emailInBackground: true,
    );

    await PendingRegistrationCache.save(
      PendingRegistration(
        uid: pendingId,
        contactEmail: contactEmail,
        authEmail: contactEmail,
        authDeferred: true,
        password: password,
        touristData: TouristRegistrationService.jsonSafeMap(touristData),
        userData: TouristRegistrationService.jsonSafeMap(userData),
        usedPhotoFirestoreFallback: false,
        localProfile: PendingLocalProfile(
          firstName: names.firstName,
          middleName: '',
          lastName: names.lastName,
          sex: null,
          nationality: nationality,
          dateOfBirth: null,
          mobile: mobile,
          email: contactEmail,
          country: country,
          province: province,
          city: city,
          street: '',
          barangay: '',
          touristId: touristId,
          profileImageBase64: null,
          profilePhotoUrl: null,
        ),
      ),
    );

    AuthConfig.currentUserUid = null;
    debugPrint(
      '[QR-REG] deferred Auth pendingId=$pendingId touristId=$touristId',
    );

    return QrTouristBasicRegistrationResult(
      contactEmail: contactEmail,
      delivery: delivery,
    );
  }
}

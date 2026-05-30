import 'package:flutter/material.dart';
import 'package:atmos_trs_system/config/app_theme.dart';
import 'package:atmos_trs_system/config/atmos_brand_typography.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:async';
import 'dart:convert';
import 'package:atmos_trs_system/utils/email_utils.dart';
import 'package:atmos_trs_system/utils/signup_field_validation.dart';
import 'package:atmos_trs_system/utils/tourist_id_helper.dart';
import 'package:atmos_trs_system/utils/firebase_client_blocked_message.dart';
import 'package:atmos_trs_system/config/user_profile_storage.dart';
import 'package:atmos_trs_system/config/session_storage.dart';
import 'package:atmos_trs_system/config/auth_config.dart';
import 'package:atmos_trs_system/services/notification_firestore_service.dart';
import 'package:atmos_trs_system/services/otp_service.dart';
import 'package:atmos_trs_system/services/registration_municipality_resolver.dart';
import 'package:atmos_trs_system/services/tourist_registration_service.dart';
import 'package:atmos_trs_system/services/otp_delivery_service.dart';
import 'package:atmos_trs_system/data/misamis_occidental_barangays.dart';
import 'package:atmos_trs_system/data/signup_prior_destinations.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:image/image.dart' as img;

/// Resize/compress profile photos so Storage uploads succeed and Firestore docs stay under ~1MB.
Uint8List _compressProfileJpeg(
  Uint8List raw, {
  int maxSide = 1024,
  int quality = 82,
}) {
  try {
    final decoded = img.decodeImage(raw);
    if (decoded == null) return raw;
    var work = decoded;
    if (work.width > maxSide || work.height > maxSide) {
      if (work.width >= work.height) {
        work = img.copyResize(work, width: maxSide);
      } else {
        work = img.copyResize(work, height: maxSide);
      }
    }
    return Uint8List.fromList(img.encodeJpg(work, quality: quality));
  } catch (e, st) {
    debugPrint('Profile image compress skipped: $e $st');
    return raw;
  }
}

/// Result of profile photo upload — Storage URL and/or Firestore base64 fallback.
class _ProfilePhotoResult {
  const _ProfilePhotoResult({
    this.profilePhotoUrl,
    this.profileImageBase64,
    this.usedFirestoreFallback = false,
  });

  final String? profilePhotoUrl;
  final String? profileImageBase64;
  final bool usedFirestoreFallback;

  bool get hasPhoto =>
      (profilePhotoUrl != null && profilePhotoUrl!.isNotEmpty) ||
      (profileImageBase64 != null && profileImageBase64!.isNotEmpty);
}

bool _storageUploadShouldUseFirestoreFallback(FirebaseException e) {
  if (e.plugin != 'firebase_storage') return false;
  // Profile photos are optional for Storage; save base64 in Firestore when
  // Storage is unavailable (billing 402, quota, App Check, etc.).
  const fallbackCodes = {
    'quota-exceeded',
    'unauthorized',
    'unauthenticated',
    'retry-limit-exceeded',
    'bucket-not-found',
    'project-not-found',
    'object-not-found',
    'canceled',
    'unavailable',
    'unknown',
  };
  if (fallbackCodes.contains(e.code)) return true;
  final m = (e.message ?? '').toLowerCase();
  return m.contains('billing') ||
      m.contains('delinquent') ||
      m.contains('402') ||
      m.contains('payment') ||
      m.contains('terminated the upload');
}

bool _looksLikeFirebaseBillingDisabled(Object e) {
  final text = e.toString().toLowerCase();
  return text.contains('billing') &&
      (text.contains('delinquent') ||
          text.contains('disabled') ||
          text.contains('402'));
}

String? _profilePhotoBase64ForFirestore(Uint8List jpegBytes) {
  var bytes = jpegBytes;
  var encoded = base64Encode(bytes);
  if (encoded.length <= UserProfileStorage.maxProfileImageBase64Length) {
    return encoded;
  }
  bytes = _compressProfileJpeg(bytes, maxSide: 512, quality: 70);
  encoded = base64Encode(bytes);
  if (encoded.length <= UserProfileStorage.maxProfileImageBase64Length) {
    return encoded;
  }
  bytes = _compressProfileJpeg(bytes, maxSide: 384, quality: 60);
  encoded = base64Encode(bytes);
  if (encoded.length <= UserProfileStorage.maxProfileImageBase64Length) {
    return encoded;
  }
  return null;
}

Future<_ProfilePhotoResult?> _uploadProfilePhoto({
  required String uid,
  required Uint8List compressedPhoto,
}) async {
  try {
    debugPrint(
      '[REG] STEP 2: Storage.putData (bytes) — Flutter Web compatible; do not use putFile here',
    );
    final storageRef = FirebaseStorage.instance.ref().child(
      'profile_photos/$uid.jpg',
    );
    final uploadTask = await storageRef.putData(
      compressedPhoto,
      SettableMetadata(contentType: 'image/jpeg'),
    );
    final profilePhotoUrl = await uploadTask.ref.getDownloadURL();
    debugPrint('[REG] STEP 2 OK: url=$profilePhotoUrl');
    return _ProfilePhotoResult(profilePhotoUrl: profilePhotoUrl);
  } on FirebaseException catch (e, st) {
    if (!_storageUploadShouldUseFirestoreFallback(e)) {
      debugPrint(
        '[REG] STEP 2 FAIL: plugin=${e.plugin} code=${e.code} message=${e.message}\n$st',
      );
      rethrow;
    }
    debugPrint(
      '[REG] STEP 2 Storage unavailable (${e.code}); saving photo in Firestore instead',
    );
  } catch (e, st) {
    debugPrint(
      '[REG] STEP 2 Storage error ($e); trying Firestore fallback\n$st',
    );
  }

  final profileImageBase64 = _profilePhotoBase64ForFirestore(compressedPhoto);
  if (profileImageBase64 == null) {
    debugPrint('[REG] STEP 2 FAIL: photo too large for Firestore fallback');
    return null;
  }
  debugPrint(
    '[REG] STEP 2 OK: Firestore base64 fallback (${profileImageBase64.length} chars)',
  );
  return _ProfilePhotoResult(
    profileImageBase64: profileImageBase64,
    usedFirestoreFallback: true,
  );
}

class SignupScreen extends StatefulWidget {
  const SignupScreen({super.key});

  @override
  State<SignupScreen> createState() => _SignupScreenState();
}

class _SignupScreenState extends State<SignupScreen> {
  /// Age 12 and below = minor; 13 and above = adult registrant.
  static const int _minorMaxAgeYears = 12;

  final _formKey = GlobalKey<FormState>();
  int _currentStep = 0;
  int _personalDetailsSubStep =
      0; // 0: Terms, 1: Basic, 2: Personal, 3: Contact, 4: Family

  // Personal Details Controllers
  final _firstNameController = TextEditingController();
  final _middleNameController = TextEditingController();
  final _lastNameController = TextEditingController();
  final _mobileController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  final _barangayController = TextEditingController();
  final _foreignCityController = TextEditingController();
  final _foreignRegionController = TextEditingController();
  final _accompanyingChildrenCountController = TextEditingController();

  String? _selectedHowHeard;

  String? _selectedPriorDestination1;
  String? _selectedPriorDestination2;
  String? _selectedPriorDestination3;
  String? _selectedTransportation;

  // Dropdown values
  String? _selectedSuffix;
  String? _selectedSex;
  String? _selectedNationality;
  DateTime? _selectedDateOfBirth;
  int? _selectedDay;
  int? _selectedMonth;
  int? _selectedYear;
  String? _selectedCountry;
  String? _selectedProvince;
  String? _selectedCity;
  String? _selectedBarangay;

  bool _obscurePassword = true;
  bool _obscureConfirmPassword = true;

  // Upload step variables
  bool _receiveUpdates = false;
  bool _agreeToTerms = false;
  bool _privacySectionExpanded = false;
  bool _termsSectionExpanded = false;
  bool _hasReviewedPrivacy = false;
  bool _hasReviewedTerms = false;
  bool _isSubmitting = false;
  Uint8List? _uploadedImageBytes;
  final ImagePicker _imagePicker = ImagePicker();

  // OTP verification variables
  final List<TextEditingController> _otpControllers = List.generate(
    6,
    (_) => TextEditingController(),
  );
  final List<FocusNode> _otpFocusNodes = List.generate(6, (_) => FocusNode());
  String? _verificationId;
  ConfirmationResult? _webConfirmationResult;
  bool _isVerifying = false;
  bool _isSendingOtp = false;
  bool _otpSent = false;
  bool _isPhoneVerified = false;
  int _resendTimer = 0;
  Timer? _timer;

  /// Parent/guardian name when registrant is age 12 or below.
  final _parentGuardianController = TextEditingController();

  static const List<String> _howHeardOptions = [
    'Facebook',
    'Instagram',
    'TikTok',
    'Friends / Family',
    'Word of mouth',
    'Tourism office / LGU',
    'Hotel or resort',
    'Travel agency / tour operator',
    'Google / online search',
    'News / TV / radio',
    'School / work',
    'Other',
  ];

  static const List<String> _transportationModes = [
    'Private car (own vehicle)',
    'Rented car or van',
    'Tour van / package transport',
    'Public bus',
    'UV Express',
    'Jeepney',
    'Tricycle',
    'Motorcycle',
    'Bicycle or walking',
    'Domestic flight',
    'Ferry / RORO boat',
    'Chartered boat',
    'Other',
  ];

  static const Color _backgroundWhite = Color(0xFFFFF7ED); // orange-50
  static const Color _cardWhite = Colors.white;
  static const Color _textDark = Color(0xFF1F2937);
  static const Color _textMuted = Color(0xFF6B7280);
  static const Color _inputBorder = Color(0xFFE5E7EB);
  static const Color _inputFill = Color(0xFFFFFFFF);
  static const Color _requiredAccent = Color(0xFFEA580C);

  String? _requiredField(String? value, String fieldLabel) {
    if (value == null || value.trim().isEmpty) {
      return '$fieldLabel is required';
    }
    return null;
  }

  final List<String> _suffixes = ['None', 'Jr.', 'Sr.', 'II', 'III', 'IV', 'V'];
  final List<String> _sexOptions = ['Male', 'Female'];
  static const String _dualCitizenNationalityLabel = 'Filipino (dual citizen)';

  /// Maps signup nationality label → [ _countries ] entry (auto home country).
  static const Map<String, String> _nationalityHomeCountry = {
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

  final List<String> _nationalities = [
    'Filipino',
    _dualCitizenNationalityLabel,
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
  final List<String> _countries = [
    'Philippines',
    'Afghanistan',
    'Albania',
    'Algeria',
    'American Samoa',
    'Andorra',
    'Angola',
    'Anguilla',
    'Antarctica',
    'Antigua and Barbuda',
    'Argentina',
    'Armenia',
    'Aruba',
    'Australia',
    'Austria',
    'Azerbaijan',
    'Bahamas',
    'Bahrain',
    'Bangladesh',
    'Barbados',
    'Belarus',
    'Belgium',
    'Belize',
    'Benin',
    'Bermuda',
    'Bhutan',
    'Bolivia',
    'Bosnia and Herzegovina',
    'Botswana',
    'Brazil',
    'Brunei',
    'Bulgaria',
    'Burkina Faso',
    'Burundi',
    'Cambodia',
    'Cameroon',
    'Canada',
    'Cape Verde',
    'Cayman Islands',
    'Central African Republic',
    'Chad',
    'Chile',
    'China',
    'Colombia',
    'Comoros',
    'Congo',
    'Costa Rica',
    'Croatia',
    'Cuba',
    'Cyprus',
    'Czech Republic',
    'Denmark',
    'Djibouti',
    'Dominica',
    'Dominican Republic',
    'Ecuador',
    'Egypt',
    'El Salvador',
    'Equatorial Guinea',
    'Eritrea',
    'Estonia',
    'Ethiopia',
    'Fiji',
    'Finland',
    'France',
    'Gabon',
    'Gambia',
    'Georgia',
    'Germany',
    'Ghana',
    'Greece',
    'Greenland',
    'Grenada',
    'Guam',
    'Guatemala',
    'Guinea',
    'Guinea-Bissau',
    'Guyana',
    'Haiti',
    'Honduras',
    'Hong Kong',
    'Hungary',
    'Iceland',
    'India',
    'Indonesia',
    'Iran',
    'Iraq',
    'Ireland',
    'Israel',
    'Italy',
    'Jamaica',
    'Japan',
    'Jordan',
    'Kazakhstan',
    'Kenya',
    'Kiribati',
    'Kuwait',
    'Kyrgyzstan',
    'Laos',
    'Latvia',
    'Lebanon',
    'Lesotho',
    'Liberia',
    'Libya',
    'Liechtenstein',
    'Lithuania',
    'Luxembourg',
    'Macau',
    'Madagascar',
    'Malawi',
    'Malaysia',
    'Maldives',
    'Mali',
    'Malta',
    'Marshall Islands',
    'Mauritania',
    'Mauritius',
    'Mexico',
    'Micronesia',
    'Moldova',
    'Monaco',
    'Mongolia',
    'Montenegro',
    'Morocco',
    'Mozambique',
    'Myanmar',
    'Namibia',
    'Nauru',
    'Nepal',
    'Netherlands',
    'New Zealand',
    'Nicaragua',
    'Niger',
    'Nigeria',
    'North Korea',
    'North Macedonia',
    'Norway',
    'Oman',
    'Pakistan',
    'Palau',
    'Palestine',
    'Panama',
    'Papua New Guinea',
    'Paraguay',
    'Peru',
    'Poland',
    'Portugal',
    'Puerto Rico',
    'Qatar',
    'Romania',
    'Russia',
    'Rwanda',
    'Saint Kitts and Nevis',
    'Saint Lucia',
    'Saint Vincent',
    'Samoa',
    'San Marino',
    'Saudi Arabia',
    'Senegal',
    'Serbia',
    'Seychelles',
    'Sierra Leone',
    'Singapore',
    'Slovakia',
    'Slovenia',
    'Solomon Islands',
    'Somalia',
    'South Africa',
    'South Korea',
    'South Sudan',
    'Spain',
    'Sri Lanka',
    'Sudan',
    'Suriname',
    'Sweden',
    'Switzerland',
    'Syria',
    'Taiwan',
    'Tajikistan',
    'Tanzania',
    'Thailand',
    'Timor-Leste',
    'Togo',
    'Tonga',
    'Trinidad and Tobago',
    'Tunisia',
    'Turkey',
    'Turkmenistan',
    'Tuvalu',
    'Uganda',
    'Ukraine',
    'United Arab Emirates',
    'United Kingdom',
    'United States',
    'Uruguay',
    'Uzbekistan',
    'Vanuatu',
    'Vatican City',
    'Venezuela',
    'Vietnam',
    'Yemen',
    'Zambia',
    'Zimbabwe',
  ];
  final List<String> _provinces = [
    'Misamis Occidental',
    'Misamis Oriental',
    'Bukidnon',
    'Lanao del Norte',
    'Lanao del Sur',
    'Zamboanga del Norte',
    'Zamboanga del Sur',
    'Other',
  ];

  final List<String> _months = [
    'January',
    'February',
    'March',
    'April',
    'May',
    'June',
    'July',
    'August',
    'September',
    'October',
    'November',
    'December',
  ];

  List<int> _getDaysInMonth(int? month, int? year) {
    if (month == null) return List.generate(31, (i) => i + 1);
    final y = year ?? DateTime.now().year;
    final daysInMonth = DateTime(y, month + 1, 0).day;
    return List.generate(daysInMonth, (i) => i + 1);
  }

  List<int> _getYears() {
    final currentYear = DateTime.now().year;
    return List.generate(100, (i) => currentYear - i);
  }

  void _updateDateOfBirth() {
    if (_selectedDay != null &&
        _selectedMonth != null &&
        _selectedYear != null) {
      setState(() {
        _selectedDateOfBirth = DateTime(
          _selectedYear!,
          _selectedMonth!,
          _selectedDay!,
        );
      });
    }
  }

  bool get _isPureFilipinoNationality => _selectedNationality == 'Filipino';

  bool get _isDualCitizenNationality =>
      _selectedNationality == _dualCitizenNationalityLabel;

  /// Filipino or dual citizen may select Philippines; other nationalities may not.
  bool get _maySelectPhilippines =>
      _isPureFilipinoNationality || _isDualCitizenNationality;

  bool get _isPhilippines => _selectedCountry == 'Philippines';

  String get _derivedLocalOrForeign => _isPhilippines ? 'Local' : 'Foreign';

  bool get _showPhilippineSubdivisions =>
      _maySelectPhilippines && _isPhilippines;

  bool get _showInternationalAddressFields =>
      _selectedCountry != null && !_showPhilippineSubdivisions;

  String? get _autoHomeCountry =>
      _nationalityHomeCountry[_selectedNationality];

  /// When nationality maps to one country (e.g. American → United States).
  bool get _countryLockedByNationality => _autoHomeCountry != null;

  bool get _showForeignStateRegion =>
      _showInternationalAddressFields && !_countryLockedByNationality;

  List<String> get _countriesForResidence => _maySelectPhilippines
      ? _countries
      : _countries.where((c) => c != 'Philippines').toList();

  bool get _useSelectableBarangay =>
      _showPhilippineSubdivisions &&
      _selectedProvince == 'Misamis Occidental' &&
      isMisamisOccidentalSignupCity(_selectedCity);

  String _resolvedBarangay() {
    if (_useSelectableBarangay) {
      return _selectedBarangay?.trim() ?? '';
    }
    return _barangayController.text.trim();
  }

  String? _validateBarangayField(String? _) {
    if (!_showPhilippineSubdivisions) return null;
    final v = _resolvedBarangay();
    if (_useSelectableBarangay) {
      return v.isEmpty ? 'Select your barangay' : null;
    }
    return validatePhilippineBarangay(v);
  }

  void _onNationalityChanged(String? nationality) {
    setState(() {
      _selectedNationality = nationality;
      final mayPh = nationality == 'Filipino' ||
          nationality == _dualCitizenNationalityLabel;
      final homeCountry = nationality != null
          ? _nationalityHomeCountry[nationality]
          : null;
      if (homeCountry != null) {
        _selectedCountry = homeCountry;
        _clearPhilippineAddressFields();
        _foreignRegionController.clear();
      } else if (!mayPh) {
        if (_selectedCountry == 'Philippines') {
          _selectedCountry = null;
        }
        _clearPhilippineAddressFields();
      } else if (nationality == 'Filipino' && _selectedCountry == null) {
        _selectedCountry = 'Philippines';
        _clearInternationalAddressFields();
      }
    });
  }

  void _clearPhilippineAddressFields() {
    _selectedProvince = null;
    _selectedCity = null;
    _selectedBarangay = null;
    _barangayController.clear();
  }

  void _clearInternationalAddressFields() {
    _foreignCityController.clear();
    _foreignRegionController.clear();
  }

  String _resolvedProvinceForSave() {
    if (_showPhilippineSubdivisions) {
      return _selectedProvince?.trim() ?? '';
    }
    if (_showForeignStateRegion) {
      return _foreignRegionController.text.trim();
    }
    return '';
  }

  String _resolvedCityForSave() {
    if (_showPhilippineSubdivisions) {
      return _selectedCity?.trim() ?? '';
    }
    if (_showInternationalAddressFields) {
      return _foreignCityController.text.trim();
    }
    return '';
  }

  void _onCountryChanged(String? country) {
    setState(() {
      if (!_maySelectPhilippines && country == 'Philippines') {
        return;
      }
      _selectedCountry = country;
      if (country == 'Philippines') {
        _clearInternationalAddressFields();
      } else {
        _clearPhilippineAddressFields();
      }
    });
  }

  List<String> _getCitiesForProvince(String? province) {
    if (province == 'Misamis Occidental') {
      return const [
        'Aloran',
        'Baliangao',
        'Bonifacio',
        'Calamba',
        'Clarin',
        'Concepcion',
        'Don Victoriano Chiongbian',
        'Jimenez',
        'Lopez Jaena',
        'Oroquieta City',
        'Ozamiz City',
        'Panaon',
        'Plaridel',
        'Sapang Dalaga',
        'Sinacaban',
        'Tangub City',
        'Tudela',
      ];
    }
    return const ['Select province first'];
  }

  @override
  void dispose() {
    _firstNameController.dispose();
    _middleNameController.dispose();
    _lastNameController.dispose();
    _mobileController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    _barangayController.dispose();
    _foreignCityController.dispose();
    _foreignRegionController.dispose();
    _accompanyingChildrenCountController.dispose();
    _parentGuardianController.dispose();
    for (var controller in _otpControllers) {
      controller.dispose();
    }
    for (var focusNode in _otpFocusNodes) {
      focusNode.dispose();
    }
    _timer?.cancel();
    super.dispose();
  }

  int? _ageInYears() {
    if (_selectedDateOfBirth == null) return null;
    final dob = _selectedDateOfBirth!;
    final now = DateTime.now();
    var age = now.year - dob.year;
    if (now.month < dob.month ||
        (now.month == dob.month && now.day < dob.day)) {
      age--;
    }
    return age;
  }

  bool _isMinorRegistrant() {
    final age = _ageInYears();
    return age != null && age <= _minorMaxAgeYears;
  }

  int _parsedAccompanyingChildrenCount() {
    final text = _accompanyingChildrenCountController.text.trim();
    if (text.isEmpty) return 0;
    return int.tryParse(text) ?? 0;
  }

  String? _validateAccompanyingChildrenCount(String? v) {
    if (v == null || v.trim().isEmpty) return null;
    final n = int.tryParse(v.trim());
    if (n == null || n < 0 || n > 50) {
      return 'Enter a number from 0 to 50';
    }
    return null;
  }

  String? _validateTravelParty() {
    if (_isMinorRegistrant()) {
      if (_parentGuardianController.text.trim().isEmpty) {
        return 'Please enter your parent or guardian\'s full name.';
      }
      return null;
    }
    return _validateAccompanyingChildrenCount(
      _accompanyingChildrenCountController.text,
    );
  }

  /// Tourists counted: minor alone = 1; adult = 1 + children brought.
  int _computePartyHeadcount() {
    if (_isMinorRegistrant()) return 1;
    return 1 + _parsedAccompanyingChildrenCount();
  }

  int _accompanyingChildrenForSave() {
    if (_isMinorRegistrant()) return 0;
    return _parsedAccompanyingChildrenCount();
  }

  Widget _buildLegalBullet(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Container(
              width: 6,
              height: 6,
              decoration: const BoxDecoration(
                color: _textMuted,
                shape: BoxShape.circle,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                fontSize: 13,
                color: _textDark.withValues(alpha: 0.9),
                height: 1.45,
              ),
            ),
          ),
        ],
      ),
    );
  }

  bool get _legalReviewComplete => _hasReviewedPrivacy && _hasReviewedTerms;

  Widget _buildLegalProgressChip({
    required String label,
    required bool done,
    required IconData icon,
    required Color accent,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: done ? accent.withValues(alpha: 0.1) : const Color(0xFFF9FAFB),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: done ? accent.withValues(alpha: 0.45) : _inputBorder,
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            done ? Icons.check_circle_rounded : icon,
            size: 16,
            color: done ? accent : _textMuted,
          ),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: done ? accent : _textMuted,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLegalExpansionCard({
    required String title,
    required String subtitle,
    required IconData icon,
    required Color accent,
    required Color surface,
    required Color border,
    required bool expanded,
    required bool reviewed,
    required ValueChanged<bool> onExpandedChanged,
    required List<String> bullets,
  }) {
    return Material(
      color: surface,
      elevation: expanded ? 2 : 0,
      shadowColor: accent.withValues(alpha: 0.12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: reviewed ? accent.withValues(alpha: 0.5) : border,
          width: reviewed ? 1.5 : 1,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          InkWell(
            onTap: () {
              final next = !expanded;
              onExpandedChanged(next);
            },
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(14, 14, 10, 14),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    accent.withValues(alpha: 0.16),
                    accent.withValues(alpha: 0.03),
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.85),
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: [
                        BoxShadow(
                          color: accent.withValues(alpha: 0.15),
                          blurRadius: 8,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Icon(icon, color: accent, size: 22),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                title,
                                style: const TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w800,
                                  color: _textDark,
                                ),
                              ),
                            ),
                            if (reviewed)
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 3,
                                ),
                                decoration: BoxDecoration(
                                  color: accent.withValues(alpha: 0.15),
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                child: Text(
                                  'Read',
                                  style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w800,
                                    color: accent,
                                  ),
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(height: 2),
                        Text(
                          subtitle,
                          style: const TextStyle(
                            fontSize: 12,
                            color: _textMuted,
                            height: 1.3,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Icon(
                    expanded
                        ? Icons.keyboard_arrow_up_rounded
                        : Icons.keyboard_arrow_down_rounded,
                    color: accent,
                    size: 28,
                  ),
                ],
              ),
            ),
          ),
          AnimatedCrossFade(
            firstChild: const SizedBox.shrink(),
            secondChild: Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 14),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 220),
                child: Scrollbar(
                  thumbVisibility: true,
                  radius: const Radius.circular(8),
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(4, 8, 4, 4),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: bullets.map(_buildLegalBullet).toList(),
                    ),
                  ),
                ),
              ),
            ),
            crossFadeState: expanded
                ? CrossFadeState.showSecond
                : CrossFadeState.showFirst,
            duration: const Duration(milliseconds: 220),
          ),
        ],
      ),
    );
  }

  Widget _buildTermsConsentAgreementCard() {
    final canAgree = _legalReviewComplete;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (!canAgree)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Row(
              children: [
                Icon(
                  Icons.touch_app_outlined,
                  size: 16,
                  color: Colors.amber.shade800,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Open and read both sections above before you can agree.',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.amber.shade900,
                      fontWeight: FontWeight.w600,
                      height: 1.35,
                    ),
                  ),
                ),
              ],
            ),
          ),
        Material(
          color: _agreeToTerms
              ? AppTheme.brandOrange.withValues(alpha: 0.07)
              : _cardWhite,
          elevation: _agreeToTerms ? 1 : 0,
          shadowColor: AppTheme.brandOrange.withValues(alpha: 0.2),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(
              color: _agreeToTerms
                  ? AppTheme.brandOrange
                  : (canAgree ? _inputBorder : Colors.amber.shade200),
              width: _agreeToTerms ? 2 : 1,
            ),
          ),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: canAgree
                ? () => setState(() => _agreeToTerms = !_agreeToTerms)
                : null,
            child: Opacity(
              opacity: canAgree ? 1 : 0.55,
              child: Padding(
                padding: const EdgeInsets.all(18),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      width: 28,
                      height: 28,
                      decoration: BoxDecoration(
                        color: _agreeToTerms
                            ? AppTheme.brandOrange
                            : Colors.transparent,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: _agreeToTerms
                              ? AppTheme.brandOrange
                              : _inputBorder,
                          width: 2,
                        ),
                      ),
                      child: _agreeToTerms
                          ? const Icon(
                              Icons.check_rounded,
                              size: 20,
                              color: Colors.white,
                            )
                          : null,
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _agreeToTerms
                                ? 'Agreed — you may continue registration'
                                : canAgree
                                ? 'I agree to continue'
                                : 'Review required',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w800,
                              color: _agreeToTerms
                                  ? AppTheme.brandOrange
                                  : _textDark,
                            ),
                          ),
                          const SizedBox(height: 8),
                          const Text(
                            'I have read and agree to the Terms and Conditions '
                            'and the Data Privacy Policy (Republic Act No. 10173) '
                            'of ATMOS TRS — Asenso Tourismo Misamis Occidental '
                            'Smart Tourist Registration System.',
                            style: TextStyle(
                              fontSize: 13,
                              color: _textDark,
                              height: 1.5,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  void _nextStep() {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    if (_currentStep == 0) {
      if (_personalDetailsSubStep == 0) {
        if (!_legalReviewComplete) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text(
                'Please open and read both the Data Privacy and Terms sections.',
              ),
              backgroundColor: Colors.red.shade700,
              behavior: SnackBarBehavior.floating,
            ),
          );
          return;
        }
        if (!_agreeToTerms) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text(
                'Please agree to the Terms and Conditions and Data Privacy Policy.',
              ),
              backgroundColor: Colors.red.shade700,
              behavior: SnackBarBehavior.floating,
            ),
          );
          return;
        }
      }
      if (_personalDetailsSubStep == 2) {
        if (_selectedDay == null ||
            _selectedMonth == null ||
            _selectedYear == null) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text('Please select your complete Date of Birth'),
              backgroundColor: Colors.red.shade700,
              behavior: SnackBarBehavior.floating,
            ),
          );
          return;
        }
      }
      if (_personalDetailsSubStep == 4) {
        final err = _validateTravelParty();
        if (err != null) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(err),
              backgroundColor: Colors.red.shade700,
              behavior: SnackBarBehavior.floating,
            ),
          );
          return;
        }
        setState(() => _currentStep++);
        return;
      }
      if (_personalDetailsSubStep < 4) {
        setState(() {
          _personalDetailsSubStep++;
        });
        return;
      }
    }
    setState(() => _currentStep++);
  }

  void _focusNextFormField() {
    if (_isSubmitting) return;
    FocusScope.of(context).nextFocus();
  }

  void _submitCurrentStepFromKeyboard() {
    if (_isSubmitting) return;
    if (_currentStep == 2) {
      _submitForm();
    } else {
      _nextStep();
    }
  }

  void _previousStep() {
    if (_currentStep == 0 && _personalDetailsSubStep > 0) {
      setState(() => _personalDetailsSubStep--);
      return;
    }
    setState(() => _currentStep--);
  }

  String _formatPhoneNumber(String phone) {
    String cleaned = phone.replaceAll(RegExp(r'[^\d+]'), '');
    if (cleaned.startsWith('09') && cleaned.length == 11) {
      return '+63${cleaned.substring(1)}';
    }
    if (cleaned.startsWith('639') && cleaned.length == 12) {
      return '+$cleaned';
    }
    if (cleaned.startsWith('+639') && cleaned.length == 13) {
      return cleaned;
    }
    if (!cleaned.startsWith('+')) {
      return '+$cleaned';
    }
    return cleaned;
  }

  void _startResendTimer() {
    setState(() => _resendTimer = 60);
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_resendTimer > 0) {
        setState(() => _resendTimer--);
      } else {
        timer.cancel();
      }
    });
  }

  Future<void> _sendOtp() async {
    final phoneNumber = _formatPhoneNumber(_mobileController.text.trim());

    if (phoneNumber.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Please enter a valid phone number'),
          backgroundColor: Colors.red.shade700,
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    setState(() => _isSendingOtp = true);

    try {
      if (kIsWeb) {
        // Web platform - use signInWithPhoneNumber with reCAPTCHA
        final confirmationResult = await FirebaseAuth.instance
            .signInWithPhoneNumber(phoneNumber);

        setState(() {
          _webConfirmationResult = confirmationResult;
          _otpSent = true;
          _isSendingOtp = false;
        });
        _startResendTimer();

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('OTP sent to $phoneNumber'),
              backgroundColor: Colors.green.shade700,
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      } else {
        // Mobile platform - use verifyPhoneNumber
        await FirebaseAuth.instance.verifyPhoneNumber(
          phoneNumber: phoneNumber,
          timeout: const Duration(seconds: 60),
          verificationCompleted: (PhoneAuthCredential credential) async {
            setState(() {
              _isPhoneVerified = true;
              _isSendingOtp = false;
            });
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: const Text('Phone verified automatically!'),
                  backgroundColor: Colors.green.shade700,
                  behavior: SnackBarBehavior.floating,
                ),
              );
              setState(() => _currentStep++);
            }
          },
          verificationFailed: (FirebaseAuthException e) {
            setState(() => _isSendingOtp = false);
            String errorMessage = 'Verification failed';
            if (e.code == 'invalid-phone-number') {
              errorMessage = 'Invalid phone number format';
            } else if (e.code == 'too-many-requests') {
              errorMessage = 'Too many requests. Please try again later.';
            } else if (e.code == 'quota-exceeded') {
              errorMessage = 'SMS quota exceeded. Please try again later.';
            } else {
              errorMessage =
                  e.message ?? 'Verification failed. Please try again.';
            }
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(errorMessage),
                  backgroundColor: Colors.red.shade700,
                  behavior: SnackBarBehavior.floating,
                ),
              );
            }
          },
          codeSent: (String verificationId, int? resendToken) {
            setState(() {
              _verificationId = verificationId;
              _otpSent = true;
              _isSendingOtp = false;
            });
            _startResendTimer();
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('OTP sent to $phoneNumber'),
                  backgroundColor: Colors.green.shade700,
                  behavior: SnackBarBehavior.floating,
                ),
              );
            }
          },
          codeAutoRetrievalTimeout: (String verificationId) {
            _verificationId = verificationId;
          },
        );
      }
    } catch (e) {
      setState(() => _isSendingOtp = false);
      if (mounted) {
        String errorMessage = e.toString();
        if (errorMessage.contains('reCAPTCHA')) {
          errorMessage = 'Please complete the reCAPTCHA verification';
        } else if (errorMessage.contains('invalid-phone-number')) {
          errorMessage = 'Invalid phone number format. Use +639XXXXXXXXX';
        }
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $errorMessage'),
            backgroundColor: Colors.red.shade700,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  Future<void> _verifyOtp() async {
    final otp = _otpControllers.map((c) => c.text).join();

    if (otp.length != 6) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Please enter the complete 6-digit code'),
          backgroundColor: Colors.red.shade700,
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    if (kIsWeb && _webConfirmationResult == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Session expired. Please resend OTP.'),
          backgroundColor: Colors.red.shade700,
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    if (!kIsWeb && _verificationId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Verification ID not found. Please resend OTP.'),
          backgroundColor: Colors.red.shade700,
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    setState(() => _isVerifying = true);

    try {
      if (kIsWeb) {
        // Web platform - confirm with the confirmation result
        await _webConfirmationResult!.confirm(otp);
      } else {
        // Mobile platform - use credential
        PhoneAuthCredential credential = PhoneAuthProvider.credential(
          verificationId: _verificationId!,
          smsCode: otp,
        );
        await FirebaseAuth.instance.signInWithCredential(credential);
      }

      setState(() {
        _isPhoneVerified = true;
        _isVerifying = false;
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Phone number verified successfully!'),
            backgroundColor: Colors.green.shade700,
            behavior: SnackBarBehavior.floating,
          ),
        );
        setState(() => _currentStep++);
      }
    } on FirebaseAuthException catch (e) {
      setState(() => _isVerifying = false);
      String errorMessage = 'Verification failed';
      if (e.code == 'invalid-verification-code') {
        errorMessage = 'Invalid OTP code. Please try again.';
      } else if (e.code == 'session-expired') {
        errorMessage = 'OTP expired. Please request a new one.';
      } else {
        errorMessage = e.message ?? 'Verification failed. Please try again.';
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(errorMessage),
            backgroundColor: Colors.red.shade700,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      setState(() => _isVerifying = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: ${e.toString()}'),
            backgroundColor: Colors.red.shade700,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  void _clearOtpFields() {
    for (var controller in _otpControllers) {
      controller.clear();
    }
    _otpFocusNodes[0].requestFocus();
  }

  void _registrationSnack(String message, {required Color background}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: SelectableText(
          message,
          style: const TextStyle(color: Colors.white, fontSize: 14),
        ),
        backgroundColor: background,
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 8),
      ),
    );
  }

  void _setSubmitting(bool v) {
    if (mounted) setState(() => _isSubmitting = v);
  }

  /// Extra checks beyond [FormState] validators (terms, photo, password length).
  String? _validateRegistrationExtra() {
    if (!_agreeToTerms) {
      return 'Please agree to the Terms and Conditions and Data Privacy Policy.';
    }
    if (!_receiveUpdates) {
      return 'Please check the updates/promotion consent before submitting registration.';
    }
    if (_uploadedImageBytes == null || _uploadedImageBytes!.isEmpty) {
      return 'Please take a close-up selfie photo of your face.';
    }
    final email = normalizeEmail(_emailController.text);
    if (email.isEmpty) return 'Please enter your email address.';
    if (!isValidEmailFormat(_emailController.text)) {
      return 'Please enter a valid email address.';
    }
    final pw = _passwordController.text;
    if (pw.isEmpty) return 'Please enter a password.';
    if (pw.length < 8) {
      return 'Password must be at least 8 characters.';
    }
    if (!_isPasswordStrongEnough(pw)) {
      return 'Password is too weak. Use at least 8 characters including '
          'uppercase, lowercase, and a number.';
    }
    if (_firstNameController.text.trim().isEmpty) {
      return 'Please enter your first name.';
    }
    if (_lastNameController.text.trim().isEmpty) {
      return 'Please enter your last name.';
    }
    return null;
  }

  /// Client-side bar so users see a clear message before Firebase rejects weak passwords.
  bool _isPasswordStrongEnough(String pw) {
    final hasUpper = RegExp(r'[A-Z]').hasMatch(pw);
    final hasLower = RegExp(r'[a-z]').hasMatch(pw);
    final hasDigit = RegExp(r'[0-9]').hasMatch(pw);
    return hasUpper && hasLower && hasDigit;
  }

  bool _isGmailAddress(String email) {
    final v = email.trim().toLowerCase();
    return v.endsWith('@gmail.com');
  }

  String _buildMinorGmailAlias(String parentGmail) {
    final normalized = parentGmail.trim().toLowerCase();
    final at = normalized.indexOf('@');
    if (at <= 0) return normalized;
    final local = normalized.substring(0, at).replaceAll('+', '');
    final ts = DateTime.now().millisecondsSinceEpoch;
    return '${local}+minor$ts@gmail.com';
  }

  Future<void> _deleteAuthUserBestEffort() async {
    try {
      await FirebaseAuth.instance.currentUser?.delete();
    } catch (e) {
      debugPrint('[REG] deleteAuthUserBestEffort: $e');
    }
  }

  /// Ensures Firestore requests run with a fresh Auth token (fixes web permission-denied after sign-up).
  Future<void> _ensureAuthReadyForFirestore(String uid) async {
    final auth = FirebaseAuth.instance;
    User? user = auth.currentUser;
    if (user?.uid != uid) {
      debugPrint('[REG] waiting for authStateChanges uid=$uid');
      user = await auth
          .authStateChanges()
          .firstWhere((u) => u?.uid == uid)
          .timeout(const Duration(seconds: 15));
    }
    if (user == null || user.uid != uid) {
      throw StateError(
        'Signed in user not ready for Firestore (expected uid=$uid).',
      );
    }
    await user.getIdToken(true);
    debugPrint('[REG] Firestore auth ready uid=$uid');
  }

  /// Always includes [FirebaseAuthException.code] and message when present.
  String _formatFirebaseAuthException(FirebaseAuthException e) {
    final m = e.message?.trim();
    if (looksLikeGoogleFirebaseClientBlocked(m)) {
      debugPrintFirebaseClientBlockedHint();
      return firebaseClientBlockedUserMessage();
    }
    if (m != null && m.isNotEmpty) return 'Auth [${e.code}]: $m';
    return 'Auth [${e.code}]: (no message — check Firebase Console → Authentication)';
  }

  /// Always includes plugin, code, and message for Firestore/Storage/etc.
  String _formatFirebaseException(FirebaseException e) {
    final m = e.message?.trim();
    if (looksLikeGoogleFirebaseClientBlocked(m)) {
      debugPrintFirebaseClientBlockedHint();
      return firebaseClientBlockedUserMessage();
    }
    if (_looksLikeFirebaseBillingDisabled(e)) {
      return 'Firebase billing for project atmos-trs-system is disabled or past due. '
          'In Google Cloud Console → Billing, re-enable the account linked to this project, '
          'then try again.';
    }
    final plugin = e.plugin;
    final code = e.code;
    if (m != null && m.isNotEmpty) {
      return '[$plugin] $code: $m';
    }
    return '[$plugin] $code (no message — check rules, network, and browser console)';
  }

  /// Maps any thrown value to a non-generic user-visible string (web-safe).
  String _formatRegistrationError(Object e) {
    if (e is FirebaseAuthException) return _formatFirebaseAuthException(e);
    if (e is FirebaseException) return _formatFirebaseException(e);
    if (e is PlatformException) {
      final m = e.message?.trim();
      if (m != null && m.isNotEmpty) return 'Platform [${e.code}]: $m';
      return 'Platform [${e.code}]';
    }
    final s = e.toString().trim();
    if (s == 'Error' ||
        s == 'Instance of \'Error\'' ||
        s == 'Instance of "Error"') {
      return 'Browser threw a generic Error. Open DevTools (F12) → Console and '
          'look for the red stack trace above [REG] logs. Often: CORS, blocked '
          'third-party cookies, or Firebase config.';
    }
    if (s.length > 400) return '${s.substring(0, 400)}…';
    return s;
  }

  void _submitForm() async {
    debugPrint('[REG] ========== registration start ==========');
    if (!_formKey.currentState!.validate()) {
      debugPrint('[REG] Form field validators failed');
      return;
    }
    final extra = _validateRegistrationExtra();
    if (extra != null) {
      _registrationSnack(extra, background: Colors.red.shade700);
      return;
    }

    // Decline OS/browser "save password?" prompts (esp. Chrome) for shared/public devices.
    TextInput.finishAutofillContext(shouldSave: false);

    _setSubmitting(true);

    if (Firebase.apps.isEmpty) {
      _setSubmitting(false);
      _registrationSnack(
        'Firebase is not initialized. Check firebase_options / FlutterFire.',
        background: Colors.red.shade700,
      );
      return;
    }

    final contactEmail = normalizeEmail(_emailController.text);
    var authEmail = contactEmail;
    final password = _passwordController.text;
    final ageYearsForAuth = _ageInYears();
    final isMinorRegistrant =
        ageYearsForAuth != null && ageYearsForAuth <= _minorMaxAgeYears;
    if (isMinorRegistrant && _isGmailAddress(contactEmail)) {
      try {
        final methods = await FirebaseAuth.instance.fetchSignInMethodsForEmail(
          contactEmail,
        );
        if (methods.isNotEmpty) {
          authEmail = _buildMinorGmailAlias(contactEmail);
          if (mounted) {
            _registrationSnack(
              'Parent/guardian Gmail is already used. Minor account will proceed using a protected alias.',
              background: Colors.green.shade700,
            );
          }
        }
      } catch (e) {
        debugPrint('[REG] minor gmail precheck skipped: $e');
      }
    }

    UserCredential? userCredential;
    String? uid;

    // --- STEP 1: Firebase Auth only ---
    try {
      debugPrint('[REG] STEP 1: createUserWithEmailAndPassword');
      try {
        await FirebaseAuth.instance.signOut();
      } catch (_) {}
      userCredential = await FirebaseAuth.instance.createUserWithEmailAndPassword(
        email: authEmail,
        password: password,
      );
      uid = userCredential.user?.uid;
      debugPrint('[REG] STEP 1 OK: uid=$uid');
      if (uid == null || uid.isEmpty) {
        _setSubmitting(false);
        _registrationSnack(
          'Auth [internal]: user id missing after createUser.',
          background: Colors.red.shade700,
        );
        return;
      }
      try {
        await _ensureAuthReadyForFirestore(uid);
      } catch (e) {
        debugPrint('[REG] STEP 1 auth ready (non-fatal): $e');
      }
    } on FirebaseAuthException catch (e, st) {
      debugPrint('[REG] STEP 1 FAIL: code=${e.code} message=${e.message}\n$st');
      _setSubmitting(false);
      // Account already exists in Firebase Authentication — no new signup / OTP flow.
      if (e.code == 'email-already-in-use') {
        if (mounted) {
          _registrationSnack(
            'This email is already registered. Sign in with your password — '
            'no verification code needed.',
            background: Colors.orange.shade800,
          );
          Navigator.pushReplacementNamed(context, '/login');
        }
        return;
      }
      _registrationSnack(
        _formatFirebaseAuthException(e),
        background: Colors.red.shade700,
      );
      return;
    } catch (e, st) {
      debugPrint('[REG] STEP 1 FAIL (non-FirebaseAuth): $e\n$st');
      _setSubmitting(false);
      _registrationSnack(
        _formatRegistrationError(e),
        background: Colors.red.shade700,
      );
      return;
    }

    // --- STEP 2: Firebase Storage, or Firestore base64 when Storage quota is full ---
    final compressedPhoto = _compressProfileJpeg(_uploadedImageBytes!);
    if (compressedPhoto.isEmpty) {
      await _deleteAuthUserBestEffort();
      _setSubmitting(false);
      _registrationSnack(
        'Photo could not be compressed. Try another JPG/PNG.',
        background: Colors.red.shade700,
      );
      return;
    }

    _ProfilePhotoResult? profilePhoto;
    try {
      profilePhoto = await _uploadProfilePhoto(
        uid: uid,
        compressedPhoto: compressedPhoto,
      );
    } on FirebaseException catch (e, st) {
      debugPrint(
        '[REG] STEP 2 FAIL: plugin=${e.plugin} code=${e.code} message=${e.message}\n$st',
      );
      // Should not happen: _uploadProfilePhoto falls back to Firestore for Storage errors.
      await _deleteAuthUserBestEffort();
      _setSubmitting(false);
      _registrationSnack(
        'Profile photo could not be saved — ${_formatFirebaseException(e)}',
        background: Colors.red.shade700,
      );
      return;
    } catch (e, st) {
      debugPrint('[REG] STEP 2 FAIL (non-Firebase): $e\n$st');
      await _deleteAuthUserBestEffort();
      _setSubmitting(false);
      _registrationSnack(
        'Profile photo upload failed — ${_formatRegistrationError(e)}',
        background: Colors.red.shade700,
      );
      return;
    }

    if (profilePhoto == null || !profilePhoto.hasPhoto) {
      await _deleteAuthUserBestEffort();
      _setSubmitting(false);
      _registrationSnack(
        'Photo is too large to save. Try a smaller JPG or PNG.',
        background: Colors.red.shade700,
      );
      return;
    }

    final profilePhotoUrl = profilePhoto.profilePhotoUrl;
    final profileImageBase64 = profilePhoto.profileImageBase64;
    final usedPhotoFirestoreFallback = profilePhoto.usedFirestoreFallback;

    // --- Prepare name + tourist id (needed for Firestore) ---
    final touristId = TouristIdHelper.generate(
      province: _resolvedProvinceForSave(),
    );

    String? dobString;
    if (_selectedDateOfBirth != null) {
      dobString =
          '${_selectedDateOfBirth!.year}-${_selectedDateOfBirth!.month.toString().padLeft(2, '0')}-${_selectedDateOfBirth!.day.toString().padLeft(2, '0')}';
    }

    String fullName = _firstNameController.text.trim();
    if (_middleNameController.text.trim().isNotEmpty) {
      fullName += ' ${_middleNameController.text.trim()[0]}.';
    }
    fullName += ' ${_lastNameController.text.trim()}';
    if (_selectedSuffix != null && _selectedSuffix != 'None') {
      fullName += ' $_selectedSuffix';
    }

    final ageYears = _ageInYears();
    final isMinorAccount = ageYears != null && ageYears <= _minorMaxAgeYears;
    final accompanyingChildren = _accompanyingChildrenForSave();
    final partyHeadcount = _computePartyHeadcount();

    final registrationMunicipalityId =
        await RegistrationMunicipalityResolver.resolveForSignup(
      priorDestination1: signupPriorDestinationValueForSave(
        _selectedPriorDestination1,
      ),
      priorDestination2: signupPriorDestinationValueForSave(
        _selectedPriorDestination2,
      ),
      priorDestination3: signupPriorDestinationValueForSave(
        _selectedPriorDestination3,
      ),
    );

    // --- STEP 3: Firestore profile docs (client rules or Cloud Function fallback) ---
    final touristData = <String, dynamic>{
      'touristId': touristId,
      'firebaseUid': uid,
      'firstName': _firstNameController.text.trim(),
      'middleName': _middleNameController.text.trim(),
      'lastName': _lastNameController.text.trim(),
      'fullName': fullName,
      'suffix': _selectedSuffix,
      'sex': _selectedSex,
      'nationality': _selectedNationality,
      'dateOfBirth': dobString,
      'mobile': _mobileController.text.trim(),
      'email': contactEmail,
      'authEmail': authEmail,
      'country': _selectedCountry,
      'province': _resolvedProvinceForSave(),
      'city': _resolvedCityForSave(),
      'street': '',
      'barangay': _resolvedBarangay(),
      'profilePhotoUrl': profilePhotoUrl,
      if (profileImageBase64 != null) 'profileImageBase64': profileImageBase64,
      'profilePhotoPending': usedPhotoFirestoreFallback,
      'isLocal': _isPhilippines,
      'localOrForeign': _derivedLocalOrForeign,
      'transportation': _selectedTransportation,
      'travelHistory': {
        'firstDestination': signupPriorDestinationValueForSave(
          _selectedPriorDestination1,
        ),
        'secondDestination': signupPriorDestinationValueForSave(
          _selectedPriorDestination2,
        ),
        'thirdDestination': signupPriorDestinationValueForSave(
          _selectedPriorDestination3,
        ),
        'howHeardAbout': _selectedHowHeard?.trim() ?? '',
      },
      'receiveUpdates': _receiveUpdates,
      'registeredAt': FieldValue.serverTimestamp(),
      if (registrationMunicipalityId != null &&
          registrationMunicipalityId.isNotEmpty)
        'registrationMunicipalityId': registrationMunicipalityId,
      'status': 'Active',
      'totalVisits': 0,
      'isVerified': false,
      'verifiedCitizen': true,
      'level': 1,
      'levelTitle': 'Explorer',
      'minorAccountHolder': isMinorAccount,
      'parentGuardianFullName': isMinorAccount
          ? _parentGuardianController.text.trim()
          : null,
      if (isMinorAccount) 'parentGuardianEmail': contactEmail,
      'travelPartyChildren': <Map<String, dynamic>>[],
      'accompanyingChildrenCount': accompanyingChildren,
      'partyHeadcount': partyHeadcount,
    };
    final userData = <String, dynamic>{
      'firebaseUid': uid,
      'email': authEmail,
      if (isMinorAccount) 'parentGuardianEmail': contactEmail,
      'fullName': fullName,
      'role': 'tourist',
      'municipality': '',
      'isVerified': false,
      'createdAt': FieldValue.serverTimestamp(),
    };

    try {
      await _ensureAuthReadyForFirestore(uid);
      debugPrint('[REG] STEP 3: Firestore tourists + users');
      await TouristRegistrationService.saveRegistration(
        uid: uid,
        touristData: touristData,
        userData: userData,
      );
      debugPrint('[REG] STEP 3 OK');
    } on FirebaseException catch (e, st) {
      debugPrint(
        '[REG] STEP 3A FAIL: plugin=${e.plugin} code=${e.code} message=${e.message}\n$st',
      );
      if (e.code == 'permission-denied') {
        await _deleteAuthUserBestEffort();
      }
      _setSubmitting(false);
      final rulesHint = e.code == 'permission-denied'
          ? ' In Firebase Console → Firestore → Rules, publish rules from firestore.rules, '
                'or run: firebase deploy --only firestore:rules,functions'
          : '';
      _registrationSnack(
        'Firestore save failed — ${_formatFirebaseException(e)}.$rulesHint',
        background: Colors.red.shade700,
      );
      return;
    } catch (e, st) {
      debugPrint('[REG] STEP 3 FAIL (non-Firebase): $e\n$st');
      await _deleteAuthUserBestEffort();
      _setSubmitting(false);
      _registrationSnack(
        'Firestore save failed — ${_formatRegistrationError(e)}',
        background: Colors.red.shade700,
      );
      return;
    }

    // Local prefs (non-fatal)
    try {
      await UserProfileStorage.saveUserProfile(
        firstName: _firstNameController.text.trim(),
        middleName: _middleNameController.text.trim(),
        lastName: _lastNameController.text.trim(),
        suffix: _selectedSuffix,
        sex: _selectedSex,
        nationality: _selectedNationality,
        dateOfBirth: dobString,
        mobile: _mobileController.text.trim(),
        email: contactEmail,
        country: _selectedCountry,
        province: _resolvedProvinceForSave(),
        city: _resolvedCityForSave(),
        street: '',
        barangay: _resolvedBarangay(),
        touristId: touristId,
        profileImageBase64: profileImageBase64,
        profilePhotoUrl: profilePhotoUrl,
      );
    } catch (e, st) {
      debugPrint('[REG] Local prefs (non-fatal): $e\n$st');
    }

    // --- STEP 4: OTP doc in Firestore (test this alone: watch for [REG] STEP 4 FAIL) ---
    final otp = OtpService.generateSixDigitOtp();
    try {
      debugPrint('[REG] STEP 4: email_otps save');
      await OtpService.saveOtp(uid: uid, email: contactEmail, otp: otp);
      debugPrint('[REG] STEP 4 OK');
    } on FirebaseException catch (e, st) {
      debugPrint(
        '[REG] STEP 4 FAIL: plugin=${e.plugin} code=${e.code} message=${e.message}\n$st',
      );
      _setSubmitting(false);
      _registrationSnack(
        'OTP save failed — ${_formatFirebaseException(e)}',
        background: Colors.red.shade700,
      );
      return;
    } catch (e, st) {
      debugPrint('[REG] STEP 4 FAIL: $e\n$st');
      _setSubmitting(false);
      _registrationSnack(
        'OTP save failed — ${_formatRegistrationError(e)}',
        background: Colors.red.shade700,
      );
      return;
    }

    // --- STEP 5: Email to inbox + phone notification (mobile backup) ---
    debugPrint('[REG] STEP 5: OTP delivery (email + notification)');
    final delivery = await OtpDeliveryService.deliverVerificationCode(
      uid: uid,
      email: contactEmail,
      displayName: fullName,
      otp: otp,
    );

    AuthConfig.currentUserUid = uid;
    try {
      await SessionStorage.saveSession(
        uid,
        role: UserRole.tourist,
        email: authEmail,
      );
    } catch (e, st) {
      debugPrint('[REG] session save (non-fatal): $e\n$st');
    }

    try {
      await NotificationFirestoreService.createWelcomeNotification(uid);
    } catch (e, st) {
      debugPrint('[REG] welcome notification (non-fatal): $e\n$st');
    }

    _setSubmitting(false);
    if (mounted) {
      if (usedPhotoFirestoreFallback) {
        _registrationSnack(
          'Your profile photo was saved to your account. Cloud file storage is full; '
          'your photo still appears in the app.',
          background: Colors.orange.shade800,
        );
      }
      if (delivery.emailSent) {
        debugPrint('[REG] STEP 5 OK: email sent');
      } else {
        debugPrint('[REG] STEP 5 email failed: ${delivery.emailError}');
      }
      _registrationSnack(
        delivery.messageForUser(contactEmail),
        background: delivery.emailSent
            ? Colors.green.shade700
            : Colors.orange.shade800,
      );
      Navigator.pushReplacementNamed(context, '/verify-otp');
    }
    debugPrint('[REG] ========== registration end ==========');
  }

  Future<void> _pickImage(ImageSource source) async {
    if (source != ImageSource.camera) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('For signup, please take a selfie photo only.'),
            backgroundColor: Colors.orange.shade800,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
      return;
    }
    try {
      final XFile? pickedFile = await _imagePicker.pickImage(
        source: source,
        maxWidth: 800,
        maxHeight: 800,
        imageQuality: 85,
      );
      if (pickedFile != null) {
        final bytes = await pickedFile.readAsBytes();
        setState(() {
          _uploadedImageBytes = bytes;
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error picking image: $e'),
            backgroundColor: Colors.red.shade700,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  InputDecoration _inputDecoration({
    required String hint,
    IconData? prefixIcon,
    Widget? suffixIcon,
  }) {
    return InputDecoration(
      hintText: hint,
      hintStyle: TextStyle(
        color: _textMuted.withValues(alpha: 0.75),
        fontSize: 14,
        fontWeight: FontWeight.w400,
      ),
      prefixIcon: prefixIcon != null
          ? Padding(
              padding: const EdgeInsets.only(left: 12, right: 4),
              child: Icon(prefixIcon, color: AppTheme.brandOrange, size: 20),
            )
          : null,
      prefixIconConstraints: const BoxConstraints(minWidth: 44, minHeight: 48),
      suffixIcon: suffixIcon,
      filled: true,
      fillColor: _inputFill,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
      errorStyle: TextStyle(
        fontSize: 11,
        height: 1.25,
        color: Colors.red.shade700,
        fontWeight: FontWeight.w500,
      ),
      errorMaxLines: 2,
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: _inputBorder, width: 1),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: AppTheme.brandOrange, width: 2),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: Colors.red.shade300, width: 1),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: Colors.red.shade400, width: 2),
      ),
    );
  }

  Widget _buildSectionLabel(String label, {bool required = false}) {
    return Text.rich(
      TextSpan(
        text: label,
        style: const TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w600,
          color: _textDark,
          letterSpacing: 0.1,
        ),
        children: required
            ? const [
                TextSpan(
                  text: ' *',
                  style: TextStyle(
                    color: _requiredAccent,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ]
            : [],
      ),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );
  }

  BoxDecoration _signupFormCardDecoration() {
    return BoxDecoration(
      color: _cardWhite,
      borderRadius: BorderRadius.circular(_isWeb ? 20 : 16),
      border: Border.all(color: AppTheme.brandOrange.withValues(alpha: 0.12)),
      boxShadow: [
        BoxShadow(
          color: Colors.black.withValues(alpha: _isWeb ? 0.06 : 0.04),
          blurRadius: _isWeb ? 20 : 12,
          offset: const Offset(0, 4),
        ),
        BoxShadow(
          color: AppTheme.brandOrange.withValues(alpha: 0.05),
          blurRadius: _isWeb ? 28 : 0,
          offset: const Offset(0, 8),
        ),
      ],
    );
  }

  bool get _isWeb => kIsWeb && MediaQuery.sizeOf(context).width >= 768;

  @override
  Widget build(BuildContext context) {
    const double cardRadius = 24.0;

    final headerSection = Stack(
      children: [
        Container(
          width: double.infinity,
          height: 200,
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [AppTheme.brandOrange, AppTheme.brandOrangeLight],
            ),
            borderRadius: _isWeb
                ? const BorderRadius.only(
                    topLeft: Radius.circular(cardRadius),
                    topRight: Radius.circular(cardRadius),
                  )
                : const BorderRadius.only(
                    bottomLeft: Radius.circular(40),
                    bottomRight: Radius.circular(40),
                  ),
          ),
        ),
        SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
            child: Column(
              children: [
                Row(
                  children: [
                    GestureDetector(
                      onTap: () => Navigator.pop(context),
                      child: Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.2),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Text(
                          'Back',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),
                    const Spacer(),
                  ],
                ),
                const SizedBox(height: 16),
                Text(
                  'STEP ${_currentStep + 1}',
                  style: const TextStyle(
                    fontSize: 32,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                    fontStyle: FontStyle.italic,
                  ),
                ),
                const SizedBox(height: 4),
                const Text(
                  'Registration',
                  style: TextStyle(
                    fontSize: 16,
                    color: Colors.white,
                    fontWeight: FontWeight.w400,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );

    final contentSection = _isWeb
        ? Container(
            width: double.infinity,
            decoration: const BoxDecoration(
              color: _cardWhite,
              borderRadius: BorderRadius.only(
                bottomLeft: Radius.circular(cardRadius),
                bottomRight: Radius.circular(cardRadius),
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _buildStepProgressIndicator(),
                  const SizedBox(height: 20),
                  RichText(
                    textAlign: TextAlign.center,
                    text: TextSpan(
                      style: const TextStyle(fontSize: 13, color: _textMuted),
                      children: [
                        const TextSpan(
                          text:
                              'Please provide accurate and valid details only to help us serve you better. If you already have an account, ',
                        ),
                        WidgetSpan(
                          child: GestureDetector(
                            onTap: () => Navigator.pushReplacementNamed(
                              context,
                              '/login',
                            ),
                            child: Text(
                              'LOG IN',
                              style: TextStyle(
                                color: AppTheme.brandOrangeLight,
                                fontWeight: FontWeight.w600,
                                fontSize: 13,
                              ),
                            ),
                          ),
                        ),
                        const TextSpan(text: ' instead.'),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),
                  Container(
                    width: double.infinity,
                    decoration: _signupFormCardDecoration(),
                    child: Padding(
                      padding: EdgeInsets.all(_isWeb ? 24 : 28),
                      child: Form(
                        key: _formKey,
                        child: AutofillGroup(child: _buildCurrentStep()),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          )
        : Padding(
            padding: EdgeInsets.symmetric(
              horizontal: _isWeb ? 16 : 24,
              vertical: _isWeb ? 16 : 24,
            ),
            child: Column(
              children: [
                _buildStepProgressIndicator(),
                const SizedBox(height: 20),
                RichText(
                  textAlign: TextAlign.center,
                  text: TextSpan(
                    style: const TextStyle(fontSize: 13, color: _textMuted),
                    children: [
                      const TextSpan(
                        text:
                            'Please provide accurate and valid details only to help us serve you better. If you already have an account, ',
                      ),
                      WidgetSpan(
                        child: GestureDetector(
                          onTap: () =>
                              Navigator.pushReplacementNamed(context, '/login'),
                          child: Text(
                            'LOG IN',
                            style: TextStyle(
                              color: AppTheme.brandOrangeLight,
                              fontWeight: FontWeight.w600,
                              fontSize: 13,
                            ),
                          ),
                        ),
                      ),
                      const TextSpan(text: ' instead.'),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                Container(
                  width: double.infinity,
                  decoration: _signupFormCardDecoration(),
                  child: Padding(
                    padding: EdgeInsets.all(_isWeb ? 24 : 28),
                    child: Form(
                      key: _formKey,
                      child: AutofillGroup(child: _buildCurrentStep()),
                    ),
                  ),
                ),
              ],
            ),
          );

    final content = Column(
      mainAxisSize: MainAxisSize.min,
      children: [headerSection, contentSection],
    );

    final bodyContent = _isWeb
        ? Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(cardRadius),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.08),
                  blurRadius: 28,
                  offset: const Offset(0, 10),
                  spreadRadius: 0,
                ),
                BoxShadow(
                  color: AppTheme.brandOrange.withOpacity(0.06),
                  blurRadius: 36,
                  offset: const Offset(0, 14),
                  spreadRadius: -4,
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(cardRadius),
              child: content,
            ),
          )
        : content;

    return Scaffold(
      backgroundColor: _backgroundWhite,
      body: _isWeb
          ? SizedBox(
              width: MediaQuery.sizeOf(context).width,
              height: MediaQuery.sizeOf(context).height,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  Image.asset(
                    'assets/images/capitol.webp',
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => Image.network(
                      'https://images.unsplash.com/photo-1488646953014-85cb44e25828?w=1200',
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => Container(
                        color: AppTheme.brandOrange.withOpacity(0.9),
                      ),
                    ),
                  ),
                  Container(
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.45),
                    ),
                  ),
                  Center(
                    child: SingleChildScrollView(
                      padding: EdgeInsets.symmetric(
                        vertical: _isWeb ? 16 : 24,
                        horizontal: _isWeb ? 16 : 24,
                      ),
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 440),
                        child: bodyContent,
                      ),
                    ),
                  ),
                ],
              ),
            )
          : SingleChildScrollView(child: content),
    );
  }

  Widget _buildStepProgressIndicator() {
    final steps = ['Personal Details', 'Travel History', 'Uploads'];
    return Column(
      children: [
        // Main step indicator
        Row(
          children: List.generate(3, (index) {
            final isCompleted = index < _currentStep;
            final isCurrent = index == _currentStep;
            return Expanded(
              child: Row(
                children: [
                  if (index > 0)
                    Expanded(
                      child: Container(
                        height: 2,
                        color: isCompleted
                            ? AppTheme.brandOrange
                            : _inputBorder,
                      ),
                    ),
                  Flexible(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 34,
                          height: 34,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: isCompleted || isCurrent
                                ? AppTheme.brandOrange
                                : const Color(0xFFF9FAFB),
                            border: Border.all(
                              color: isCompleted || isCurrent
                                  ? AppTheme.brandOrange
                                  : _inputBorder,
                              width: isCurrent ? 2 : 1.5,
                            ),
                            boxShadow: isCurrent
                                ? [
                                    BoxShadow(
                                      color: AppTheme.brandOrange.withValues(
                                        alpha: 0.25,
                                      ),
                                      blurRadius: 8,
                                      offset: const Offset(0, 2),
                                    ),
                                  ]
                                : null,
                          ),
                          child: Center(
                            child: isCompleted
                                ? const Icon(
                                    Icons.check,
                                    color: Colors.white,
                                    size: 16,
                                  )
                                : Text(
                                    '${index + 1}',
                                    style: TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w600,
                                      color: isCurrent
                                          ? Colors.white
                                          : _textMuted,
                                    ),
                                  ),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          steps[index],
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: isCurrent
                                ? FontWeight.w600
                                : FontWeight.normal,
                            color: isCurrent
                                ? AppTheme.brandOrange
                                : _textMuted,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (index < 2)
                    Expanded(
                      child: Container(
                        height: 2,
                        color: isCompleted
                            ? AppTheme.brandOrange
                            : _inputBorder,
                      ),
                    ),
                ],
              ),
            );
          }),
        ),
      ],
    );
  }

  Widget _buildCurrentStep() {
    switch (_currentStep) {
      case 0:
        return _buildPersonalDetailsStep();
      case 1:
        return _buildTravelHistoryStep();
      case 2:
        return _buildUploadsStep();
      default:
        return _buildPersonalDetailsStep();
    }
  }

  Widget _buildPersonalDetailsStep() {
    switch (_personalDetailsSubStep) {
      case 0:
        return _buildTermsConsentSubStep();
      case 1:
        return _buildBasicInfoSubStep();
      case 2:
        return _buildPersonalInfoSubStep();
      case 3:
        return _buildContactAddressSubStep();
      case 4:
        return _buildFamilyTravelPartySubStep();
      default:
        return _buildTermsConsentSubStep();
    }
  }

  void _setAllLegalSectionsExpanded(bool expanded) {
    setState(() {
      _privacySectionExpanded = expanded;
      _termsSectionExpanded = expanded;
      if (expanded) {
        _hasReviewedPrivacy = true;
        _hasReviewedTerms = true;
      }
    });
  }

  Widget _buildTermsConsentSubStep() {
    const privacyBlue = Color(0xFF1D4ED8);
    const privacySurface = Color(0xFFEFF6FF);
    const privacyBorder = Color(0xFF93C5FD);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSubStepHeader(
          'Terms & Data Privacy',
          'Review how ATMOS TRS handles your information, then agree to continue.',
          Icons.verified_user_outlined,
        ),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            gradient: LinearGradient(
              colors: [
                AppTheme.brandOrange.withValues(alpha: 0.14),
                privacyBlue.withValues(alpha: 0.08),
              ],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            border: Border.all(
              color: AppTheme.brandOrange.withValues(alpha: 0.2),
            ),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.9),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.lock_outline_rounded,
                  color: AppTheme.brandOrange,
                  size: 26,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Your privacy matters',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        color: _textDark,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'ATMOS TRS follows RA 10173 and provincial tourism policies. '
                      'Please review both sections before registering.',
                      style: TextStyle(
                        fontSize: 12,
                        color: _textDark.withValues(alpha: 0.82),
                        height: 1.4,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        Row(
          children: [
            Expanded(
              child: _buildLegalProgressChip(
                label: 'Data Privacy',
                done: _hasReviewedPrivacy,
                icon: Icons.shield_outlined,
                accent: privacyBlue,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _buildLegalProgressChip(
                label: 'Terms',
                done: _hasReviewedTerms,
                icon: Icons.description_outlined,
                accent: AppTheme.brandOrange,
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Align(
          alignment: Alignment.centerRight,
          child: TextButton.icon(
            onPressed: () {
              final expandAll =
                  !(_privacySectionExpanded && _termsSectionExpanded);
              _setAllLegalSectionsExpanded(expandAll);
            },
            icon: Icon(
              _privacySectionExpanded && _termsSectionExpanded
                  ? Icons.unfold_less_rounded
                  : Icons.unfold_more_rounded,
              size: 18,
            ),
            label: Text(
              _privacySectionExpanded && _termsSectionExpanded
                  ? 'Collapse all'
                  : 'Expand all',
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            style: TextButton.styleFrom(
              foregroundColor: AppTheme.brandOrange,
              padding: const EdgeInsets.symmetric(horizontal: 8),
            ),
          ),
        ),
        const SizedBox(height: 6),
        _buildLegalExpansionCard(
          title: 'Data Privacy Act (RA 10173)',
          subtitle: 'Collection, use, and your rights',
          icon: Icons.shield_outlined,
          accent: privacyBlue,
          surface: privacySurface,
          border: privacyBorder,
          expanded: _privacySectionExpanded,
          reviewed: _hasReviewedPrivacy,
          onExpandedChanged: (v) => setState(() {
            _privacySectionExpanded = v;
            if (v) _hasReviewedPrivacy = true;
          }),
          bullets: const [
            'We collect personal data only for tourist registration, QR check-in, '
                'and LGU / provincial tourism reporting in Misamis Occidental.',
            'Data may include your name, contact details, address, photo, and '
                'visit history within the system.',
            'We use reasonable security measures and do not sell your data to '
                'unrelated third parties.',
            'Account-related messages (e.g. email verification, announcements) '
                'may be sent to you; marketing messages are optional.',
            'You may request access, correction, or raise privacy concerns '
                'through your municipal or provincial Tourism Office.',
          ],
        ),
        const SizedBox(height: 12),
        _buildLegalExpansionCard(
          title: 'Terms and Conditions',
          subtitle: 'Your responsibilities as a registrant',
          icon: Icons.description_outlined,
          accent: AppTheme.brandOrange,
          surface: const Color(0xFFFFF7ED),
          border: AppTheme.brandOrange.withValues(alpha: 0.28),
          expanded: _termsSectionExpanded,
          reviewed: _hasReviewedTerms,
          onExpandedChanged: (v) => setState(() {
            _termsSectionExpanded = v;
            if (v) _hasReviewedTerms = true;
          }),
          bullets: const [
            'You confirm that all information you provide is true, complete, '
                'and updated.',
            'ATMOS TRS is for lawful tourism registration and check-in only, '
                'including accredited tourist spots and LGU QR processes.',
            'You agree to follow local tourism rules, geofence / QR policies, '
                'and instructions from authorized staff.',
            'Misuse of the system, false identity, or abusive behavior may '
                'result in restricted access or account action.',
            'The Province and LGUs may use aggregated visit data for tourism '
                'planning and public service reporting.',
          ],
        ),
        const SizedBox(height: 20),
        _buildTermsConsentAgreementCard(),
        const SizedBox(height: 32),
        _buildPersonalDetailsNavButtons(showBack: false),
      ],
    );
  }

  Widget _buildSubStepHeader(String title, String description, IconData icon) {
    return Column(
      children: [
        Container(
          width: 64,
          height: 64,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                AppTheme.brandOrange.withValues(alpha: 0.18),
                AppTheme.brandOrangeLight.withValues(alpha: 0.28),
              ],
            ),
            border: Border.all(
              color: AppTheme.brandOrange.withValues(alpha: 0.35),
              width: 1.5,
            ),
            boxShadow: [
              BoxShadow(
                color: AppTheme.brandOrange.withValues(alpha: 0.12),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Icon(icon, size: 30, color: AppTheme.brandOrange),
        ),
        const SizedBox(height: 16),
        Text(
          title,
          textAlign: TextAlign.center,
          style: AtmosBrandTypography.displayTitle(
            color: _textDark,
            fontSize: 20,
            letterSpacing: 0.2,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          description,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 14,
            color: Colors.grey.shade600,
            height: 1.45,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 20),
        Container(
          height: 3,
          width: 48,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(2),
            gradient: const LinearGradient(
              colors: [AppTheme.brandOrange, AppTheme.brandOrangeLight],
            ),
          ),
        ),
        const SizedBox(height: 20),
      ],
    );
  }

  Widget _buildBasicInfoSubStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSubStepHeader(
          'Basic Information',
          'Let\'s start with your name. This will be used for your tourist ID.',
          Icons.person_outline,
        ),

        _buildFormField(
          label: 'First Name',
          required: true,
          child: TextFormField(
            controller: _firstNameController,
            textInputAction: TextInputAction.next,
            onFieldSubmitted: (_) => _focusNextFormField(),
            onEditingComplete: _focusNextFormField,
            style: const TextStyle(
              color: _textDark,
              fontSize: 15,
              fontWeight: FontWeight.w500,
            ),
            decoration: _inputDecoration(
              hint: 'e.g. Juan',
              prefixIcon: Icons.person_outline_rounded,
            ),
            validator: (v) => _requiredField(v, 'First name'),
            textCapitalization: TextCapitalization.words,
          ),
        ),

        _buildFormField(
          label: 'Middle Name',
          child: TextFormField(
            controller: _middleNameController,
            textInputAction: TextInputAction.next,
            onFieldSubmitted: (_) => _focusNextFormField(),
            onEditingComplete: _focusNextFormField,
            style: const TextStyle(
              color: _textDark,
              fontSize: 15,
              fontWeight: FontWeight.w500,
            ),
            decoration: _inputDecoration(
              hint: 'e.g. Dela',
              prefixIcon: Icons.badge_outlined,
            ),
            textCapitalization: TextCapitalization.words,
          ),
        ),

        _buildFormField(
          label: 'Last Name',
          required: true,
          child: TextFormField(
            controller: _lastNameController,
            textInputAction: TextInputAction.done,
            onFieldSubmitted: (_) => _submitCurrentStepFromKeyboard(),
            onEditingComplete: _submitCurrentStepFromKeyboard,
            style: const TextStyle(
              color: _textDark,
              fontSize: 15,
              fontWeight: FontWeight.w500,
            ),
            decoration: _inputDecoration(
              hint: 'e.g. Cruz',
              prefixIcon: Icons.person_outline_rounded,
            ),
            validator: (v) => _requiredField(v, 'Last name'),
            textCapitalization: TextCapitalization.words,
          ),
        ),

        _buildFormField(
          label: 'Suffix',
          child: DropdownButtonFormField<String>(
            value: _selectedSuffix,
            dropdownColor: Colors.white,
            icon: const SizedBox.shrink(),
            iconSize: 0,
            borderRadius: BorderRadius.circular(12),
            style: const TextStyle(
              color: _textDark,
              fontSize: 15,
              fontWeight: FontWeight.w500,
            ),
            decoration: _inputDecoration(
              hint: 'e.g. Jr., Sr., III',
              prefixIcon: Icons.label_outline_rounded,
            ),
            items: _suffixes
                .map((s) => DropdownMenuItem(value: s, child: Text(s)))
                .toList(),
            onChanged: (v) => setState(() => _selectedSuffix = v),
          ),
        ),

        _buildPersonalDetailsNavButtons(showBack: true),
      ],
    );
  }

  Widget _buildPersonalInfoSubStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSubStepHeader(
          'Personal Information',
          'Tell us more about yourself. This helps us personalize your experience.',
          Icons.info_outline,
        ),

        _buildFormField(
          label: 'Sex',
          required: true,
          child: DropdownButtonFormField<String>(
            value: _selectedSex,
            dropdownColor: Colors.white,
            icon: const SizedBox.shrink(),
            iconSize: 0,
            style: const TextStyle(color: _textDark, fontSize: 14),
            decoration: _inputDecoration(
              hint: 'Select your sex',
              prefixIcon: Icons.wc_outlined,
            ),
            items: _sexOptions
                .map((s) => DropdownMenuItem(value: s, child: Text(s)))
                .toList(),
            validator: (v) => v == null ? 'Required' : null,
            onChanged: (v) => setState(() => _selectedSex = v),
          ),
        ),
        const SizedBox(height: 16),

        _buildFormField(
          label: 'Nationality',
          required: true,
          child: DropdownButtonFormField<String>(
            value: _selectedNationality,
            dropdownColor: Colors.white,
            icon: const SizedBox.shrink(),
            iconSize: 0,
            style: const TextStyle(color: _textDark, fontSize: 14),
            decoration: _inputDecoration(
              hint: 'Select nationality',
              prefixIcon: Icons.flag_outlined,
            ),
            items: _nationalities
                .map((n) => DropdownMenuItem(value: n, child: Text(n)))
                .toList(),
            validator: (v) => v == null ? 'Required' : null,
            onChanged: _onNationalityChanged,
          ),
        ),
        if (_selectedNationality != null &&
            !_maySelectPhilippines &&
            !_countryLockedByNationality) ...[
          const SizedBox(height: 8),
          const Text(
            'Foreign nationals: select your home country below. Philippines is '
            'not available — use City and State/Province/Region.',
            style: TextStyle(fontSize: 12, color: _textMuted, height: 1.35),
          ),
        ],
        if (_isDualCitizenNationality) ...[
          const SizedBox(height: 8),
          Text(
            'Dual citizens: choose Philippines if you live here (province, city, '
            'barangay), or your other home country for an international address.',
            style: TextStyle(fontSize: 12, color: _textMuted, height: 1.35),
          ),
        ],
        const SizedBox(height: 16),

        _buildSectionLabel('Date of Birth', required: true),
        Row(
          children: [
            Expanded(
              child: Container(
                height: 48,
                decoration: BoxDecoration(
                  color: _inputFill,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: _inputBorder),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<int>(
                    value: _selectedMonth,
                    isExpanded: true,
                    dropdownColor: Colors.white,
                    icon: const SizedBox.shrink(),
                    iconSize: 0,
                    hint: Text(
                      'Month',
                      style: TextStyle(
                        color: _textMuted.withOpacity(0.6),
                        fontSize: 14,
                      ),
                    ),
                    style: const TextStyle(color: _textDark, fontSize: 14),
                    items: List.generate(
                      12,
                      (i) => DropdownMenuItem(
                        value: i + 1,
                        child: Text(_months[i]),
                      ),
                    ),
                    onChanged: (v) {
                      setState(() {
                        _selectedMonth = v;
                        final maxDays = _getDaysInMonth(
                          v,
                          _selectedYear,
                        ).length;
                        if (_selectedDay != null && _selectedDay! > maxDays) {
                          _selectedDay = maxDays;
                        }
                      });
                      _updateDateOfBirth();
                    },
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Container(
                height: 48,
                decoration: BoxDecoration(
                  color: _inputFill,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: _inputBorder),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<int>(
                    value: _selectedDay,
                    isExpanded: true,
                    dropdownColor: Colors.white,
                    icon: const SizedBox.shrink(),
                    iconSize: 0,
                    hint: Text(
                      'Day',
                      style: TextStyle(
                        color: _textMuted.withOpacity(0.6),
                        fontSize: 14,
                      ),
                    ),
                    style: const TextStyle(color: _textDark, fontSize: 14),
                    items: _getDaysInMonth(_selectedMonth, _selectedYear)
                        .map(
                          (d) => DropdownMenuItem(value: d, child: Text('$d')),
                        )
                        .toList(),
                    onChanged: (v) {
                      setState(() => _selectedDay = v);
                      _updateDateOfBirth();
                    },
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Container(
                height: 48,
                decoration: BoxDecoration(
                  color: _inputFill,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: _inputBorder),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<int>(
                    value: _selectedYear,
                    isExpanded: true,
                    dropdownColor: Colors.white,
                    icon: const SizedBox.shrink(),
                    iconSize: 0,
                    hint: Text(
                      'Year',
                      style: TextStyle(
                        color: _textMuted.withOpacity(0.6),
                        fontSize: 14,
                      ),
                    ),
                    style: const TextStyle(color: _textDark, fontSize: 14),
                    items: _getYears()
                        .map(
                          (y) => DropdownMenuItem(value: y, child: Text('$y')),
                        )
                        .toList(),
                    onChanged: (v) {
                      setState(() {
                        _selectedYear = v;
                        final maxDays = _getDaysInMonth(
                          _selectedMonth,
                          v,
                        ).length;
                        if (_selectedDay != null && _selectedDay! > maxDays) {
                          _selectedDay = maxDays;
                        }
                      });
                      _updateDateOfBirth();
                    },
                  ),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 32),

        _buildPersonalDetailsNavButtons(),
      ],
    );
  }

  Widget _buildContactAddressSubStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSubStepHeader(
          'Contact & Address',
          'How can we reach you? This information keeps your account secure.',
          Icons.contact_mail_outlined,
        ),

        _buildFormField(
          label: 'Primary Mobile No.',
          required: true,
          child: TextFormField(
            controller: _mobileController,
            keyboardType: TextInputType.phone,
            textInputAction: TextInputAction.next,
            onFieldSubmitted: (_) => _focusNextFormField(),
            onEditingComplete: _focusNextFormField,
            style: const TextStyle(color: _textDark, fontSize: 14),
            decoration: _inputDecoration(
              hint: 'e.g. 09171234567',
              prefixIcon: Icons.phone_outlined,
            ),
            validator: validatePhilippineMobile,
          ),
        ),
        const SizedBox(height: 16),

        _buildFormField(
          label: 'Email Address',
          required: true,
          child: TextFormField(
            controller: _emailController,
            keyboardType: TextInputType.emailAddress,
            textInputAction: TextInputAction.next,
            onFieldSubmitted: (_) => _focusNextFormField(),
            onEditingComplete: _focusNextFormField,
            autofillHints: const [],
            autocorrect: false,
            enableSuggestions: false,
            style: const TextStyle(color: _textDark, fontSize: 14),
            decoration: _inputDecoration(
              hint: 'e.g. juan@email.com',
              prefixIcon: Icons.email_outlined,
            ),
            validator: (v) {
              if (v == null || v.isEmpty) return 'Required';
              if (!isValidEmailFormat(v)) return 'Enter valid email';
              return null;
            },
          ),
        ),
        const SizedBox(height: 16),

        Row(
          children: [
            Expanded(
              child: _buildFormField(
                label: 'Password',
                required: true,
                child: TextFormField(
                  controller: _passwordController,
                  obscureText: _obscurePassword,
                  textInputAction: TextInputAction.next,
                  onFieldSubmitted: (_) => _focusNextFormField(),
                  onEditingComplete: _focusNextFormField,
                  autofillHints: const [],
                  autocorrect: false,
                  enableSuggestions: false,
                  style: const TextStyle(color: _textDark, fontSize: 14),
                  decoration: _inputDecoration(
                    hint: 'Min 8 chars',
                    prefixIcon: Icons.lock_outline,
                    suffixIcon: IconButton(
                      icon: Icon(
                        _obscurePassword
                            ? Icons.visibility_off_outlined
                            : Icons.visibility_outlined,
                        color: _textMuted,
                        size: 20,
                      ),
                      onPressed: () =>
                          setState(() => _obscurePassword = !_obscurePassword),
                    ),
                  ),
                  validator: (v) {
                    if (v == null || v.isEmpty) return 'Required';
                    if (v.length < 8) return 'Min 8 chars';
                    if (!_isPasswordStrongEnough(v)) {
                      return 'Use upper, lower, and a number';
                    }
                    return null;
                  },
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _buildFormField(
                label: 'Confirm Password',
                required: true,
                child: TextFormField(
                  controller: _confirmPasswordController,
                  obscureText: _obscureConfirmPassword,
                  textInputAction: TextInputAction.next,
                  onFieldSubmitted: (_) => _focusNextFormField(),
                  onEditingComplete: _focusNextFormField,
                  autofillHints: const [],
                  autocorrect: false,
                  enableSuggestions: false,
                  style: const TextStyle(color: _textDark, fontSize: 14),
                  decoration: _inputDecoration(
                    hint: 'Re-type',
                    prefixIcon: Icons.lock_outline,
                    suffixIcon: IconButton(
                      icon: Icon(
                        _obscureConfirmPassword
                            ? Icons.visibility_off_outlined
                            : Icons.visibility_outlined,
                        color: _textMuted,
                        size: 20,
                      ),
                      onPressed: () => setState(
                        () =>
                            _obscureConfirmPassword = !_obscureConfirmPassword,
                      ),
                    ),
                  ),
                  validator: (v) {
                    if (v == null || v.isEmpty) return 'Required';
                    if (v != _passwordController.text) return 'No match';
                    return null;
                  },
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 24),

        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppTheme.brandOrange.withOpacity(0.05),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: AppTheme.brandOrange.withOpacity(0.2)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    Icons.home_outlined,
                    size: 20,
                    color: AppTheme.brandOrange,
                  ),
                  const SizedBox(width: 8),
                  const Text(
                    'Address Information',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: _textDark,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              _buildFormField(
                label: _maySelectPhilippines
                    ? 'Country of residence'
                    : 'Home country',
                required: true,
                child: _countryLockedByNationality
                    ? TextFormField(
                        key: ValueKey(_selectedCountry),
                        initialValue: _selectedCountry,
                        readOnly: true,
                        style: const TextStyle(color: _textDark, fontSize: 14),
                        decoration: _inputDecoration(
                          hint: 'Home country',
                          prefixIcon: Icons.public_outlined,
                        ),
                      )
                    : DropdownButtonFormField<String>(
                        value: _countriesForResidence.contains(_selectedCountry)
                            ? _selectedCountry
                            : null,
                        dropdownColor: Colors.white,
                        icon: const SizedBox.shrink(),
                        iconSize: 0,
                        style: const TextStyle(color: _textDark, fontSize: 14),
                        decoration: _inputDecoration(
                          hint: _maySelectPhilippines
                              ? 'Select country'
                              : 'Select home country (not Philippines)',
                        ),
                        items: _countriesForResidence
                            .map(
                              (c) => DropdownMenuItem(value: c, child: Text(c)),
                            )
                            .toList(),
                        validator: (v) => v == null ? 'Required' : null,
                        onChanged: _onCountryChanged,
                      ),
              ),
              if (_showPhilippineSubdivisions) ...[
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: _buildFormField(
                        label: 'Province',
                        required: true,
                        child: DropdownButtonFormField<String>(
                          value: _selectedProvince,
                          isExpanded: true,
                          dropdownColor: Colors.white,
                          icon: const SizedBox.shrink(),
                          iconSize: 0,
                          style: const TextStyle(
                            color: _textDark,
                            fontSize: 14,
                          ),
                          decoration: _inputDecoration(hint: 'Province'),
                          items: _provinces
                              .map(
                                (p) => DropdownMenuItem(
                                  value: p,
                                  child: Text(
                                    p,
                                    overflow: TextOverflow.ellipsis,
                                    maxLines: 1,
                                  ),
                                ),
                              )
                              .toList(),
                          selectedItemBuilder: (context) => _provinces
                              .map(
                                (p) => Text(
                                  p,
                                  overflow: TextOverflow.ellipsis,
                                  maxLines: 1,
                                ),
                              )
                              .toList(),
                          validator: (v) => v == null ? 'Required' : null,
                          onChanged: (v) {
                            setState(() {
                              _selectedProvince = v;
                              _selectedCity = null;
                              _selectedBarangay = null;
                              _barangayController.clear();
                            });
                          },
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _buildFormField(
                        label: 'City/Municipality',
                        required: true,
                        child: DropdownButtonFormField<String>(
                          value: _selectedCity,
                          isExpanded: true,
                          dropdownColor: Colors.white,
                          icon: const SizedBox.shrink(),
                          iconSize: 0,
                          style: const TextStyle(
                            color: _textDark,
                            fontSize: 14,
                          ),
                          decoration: _inputDecoration(hint: 'City'),
                          items: _getCitiesForProvince(_selectedProvince)
                              .map(
                                (c) => DropdownMenuItem(
                                  value: c,
                                  child: Text(
                                    c,
                                    overflow: TextOverflow.ellipsis,
                                    maxLines: 1,
                                  ),
                                ),
                              )
                              .toList(),
                          selectedItemBuilder: (context) =>
                              _getCitiesForProvince(_selectedProvince)
                                  .map(
                                    (c) => Text(
                                      c,
                                      overflow: TextOverflow.ellipsis,
                                      maxLines: 1,
                                    ),
                                  )
                                  .toList(),
                          validator: (v) =>
                              v == null || v == 'Select province first'
                              ? 'Required'
                              : null,
                          onChanged: (v) {
                            setState(() {
                              _selectedCity = v;
                              _selectedBarangay = null;
                              _barangayController.clear();
                            });
                          },
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                _buildFormField(
                  label: 'Barangay',
                  required: true,
                  child: _useSelectableBarangay
                      ? DropdownButtonFormField<String>(
                          value: _selectedBarangay,
                          isExpanded: true,
                          dropdownColor: Colors.white,
                          icon: const SizedBox.shrink(),
                          iconSize: 0,
                          style: const TextStyle(
                            color: _textDark,
                            fontSize: 14,
                          ),
                          decoration: _inputDecoration(hint: 'Select barangay'),
                          items:
                              barangaysForMisamisOccidentalCity(_selectedCity)
                                  .map(
                                    (b) => DropdownMenuItem(
                                      value: b,
                                      child: Text(
                                        b,
                                        overflow: TextOverflow.ellipsis,
                                        maxLines: 1,
                                      ),
                                    ),
                                  )
                                  .toList(),
                          validator: _validateBarangayField,
                          onChanged: (v) =>
                              setState(() => _selectedBarangay = v),
                        )
                      : TextFormField(
                          controller: _barangayController,
                          textInputAction: TextInputAction.done,
                          onFieldSubmitted: (_) =>
                              _submitCurrentStepFromKeyboard(),
                          onEditingComplete: _submitCurrentStepFromKeyboard,
                          style: const TextStyle(
                            color: _textDark,
                            fontSize: 14,
                          ),
                          decoration: _inputDecoration(hint: 'e.g. Poblacion'),
                          textCapitalization: TextCapitalization.words,
                          validator: _validateBarangayField,
                        ),
                ),
              ],
              if (_showInternationalAddressFields) ...[
                const SizedBox(height: 12),
                _buildFormField(
                  label: 'City',
                  required: true,
                  child: TextFormField(
                    controller: _foreignCityController,
                    style: const TextStyle(color: _textDark, fontSize: 14),
                    decoration: _inputDecoration(
                      hint: _countryLockedByNationality
                          ? 'e.g. Los Angeles'
                          : 'e.g. Sydney',
                    ),
                    textCapitalization: TextCapitalization.words,
                    validator: (v) => validateInternationalCity(v),
                  ),
                ),
                if (_showForeignStateRegion) ...[
                  const SizedBox(height: 12),
                  _buildFormField(
                    label: 'State / Province / Region',
                    required: true,
                    child: TextFormField(
                      controller: _foreignRegionController,
                      style: const TextStyle(color: _textDark, fontSize: 14),
                      decoration: _inputDecoration(hint: 'e.g. California'),
                      textCapitalization: TextCapitalization.words,
                      validator: (v) => validateInternationalRegion(v),
                    ),
                  ),
                ],
              ],
            ],
          ),
        ),
        const SizedBox(height: 32),

        _buildPersonalDetailsNavButtons(),
      ],
    );
  }

  Widget _buildFamilyTravelPartySubStep() {
    final isMinor = _isMinorRegistrant();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSubStepHeader(
          'Family / travel party',
          isMinor
              ? 'Age 12 and below: add your parent or guardian\'s name. '
                    'You are still counted as 1 tourist.'
              : 'If you are a parent traveling with children, enter how many '
                    'children you are bringing. You and each child count as tourists.',
          Icons.family_restroom_outlined,
        ),
        if (isMinor) ...[
          _buildFormField(
            label: 'Parent / guardian full name',
            required: true,
            child: TextFormField(
              controller: _parentGuardianController,
              textInputAction: TextInputAction.done,
              onFieldSubmitted: (_) => _submitCurrentStepFromKeyboard(),
              onEditingComplete: _submitCurrentStepFromKeyboard,
              style: const TextStyle(color: _textDark, fontSize: 14),
              decoration: _inputDecoration(
                hint: 'e.g. Maria Santos',
                prefixIcon: Icons.supervisor_account_outlined,
              ),
              textCapitalization: TextCapitalization.words,
              validator: (v) {
                if (v == null || v.trim().isEmpty) return 'Required';
                return null;
              },
            ),
          ),
        ] else ...[
          _buildFormField(
            label: 'Children you are bringing',
            required: false,
            child: TextFormField(
              controller: _accompanyingChildrenCountController,
              onChanged: (_) => setState(() {}),
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              textInputAction: TextInputAction.done,
              onFieldSubmitted: (_) => _submitCurrentStepFromKeyboard(),
              onEditingComplete: _submitCurrentStepFromKeyboard,
              style: const TextStyle(color: _textDark, fontSize: 14),
              decoration: _inputDecoration(
                hint: 'e.g. 3 (leave blank if none)',
                prefixIcon: Icons.numbers_rounded,
              ),
              validator: _validateAccompanyingChildrenCount,
            ),
          ),
        ],
        const SizedBox(height: 24),
        _buildPersonalDetailsNavButtons(isLastSubStep: true),
      ],
    );
  }

  Widget _buildPersonalDetailsNavButtons({
    bool showBack = true,
    bool isLastSubStep = false,
  }) {
    final nextStyle = FilledButton.styleFrom(
      backgroundColor: AppTheme.brandOrange,
      foregroundColor: Colors.white,
      elevation: 0,
      padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 14),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    );

    return Column(
      children: [
        Divider(color: _inputBorder.withValues(alpha: 0.9), height: 1),
        const SizedBox(height: 20),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            if (showBack)
              TextButton(
                onPressed: _previousStep,
                style: TextButton.styleFrom(
                  foregroundColor: _textMuted,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 12,
                  ),
                ),
                child: const Text(
                  'Back',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                ),
              )
            else
              TextButton(
                onPressed: () => Navigator.pop(context),
                style: TextButton.styleFrom(
                  foregroundColor: _textMuted,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 12,
                  ),
                ),
                child: const Text(
                  'Cancel',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                ),
              ),
            isLastSubStep
                ? FilledButton(
                    onPressed: _nextStep,
                    style: nextStyle,
                    child: const Text(
                      'Continue',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                  )
                : FilledButton(
                    onPressed: _nextStep,
                    style: nextStyle,
                    child: const Text(
                      'Next',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
          ],
        ),
      ],
    );
  }

  Widget _buildFormField({
    required String label,
    required Widget child,
    bool required = false,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(child: _buildSectionLabel(label, required: required)),
              if (!required)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF3F4F6),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: _inputBorder),
                  ),
                  child: const Text(
                    'Optional',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      color: _textMuted,
                      letterSpacing: 0.2,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          child,
        ],
      ),
    );
  }

  // ignore: unused_element
  Widget _buildOtpVerificationStep() {
    final phoneNumber = _formatPhoneNumber(_mobileController.text.trim());

    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        // Phone icon
        Container(
          width: 80,
          height: 80,
          decoration: BoxDecoration(
            color: AppTheme.brandOrange.withOpacity(0.1),
            shape: BoxShape.circle,
          ),
          child: Icon(
            Icons.phone_android,
            size: 40,
            color: AppTheme.brandOrange,
          ),
        ),
        const SizedBox(height: 24),

        const Text(
          'Verify Your Phone Number',
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: _textDark,
          ),
        ),
        const SizedBox(height: 12),

        Text(
          _otpSent
              ? 'We sent a 6-digit code to\n$phoneNumber'
              : 'We will send a verification code to\n$phoneNumber',
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 14, color: _textMuted, height: 1.5),
        ),
        const SizedBox(height: 32),

        if (!_otpSent) ...[
          // Send OTP button
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: _isSendingOtp ? null : _sendOtp,
              icon: _isSendingOtp
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                      ),
                    )
                  : const Icon(Icons.sms_outlined, size: 20),
              label: Text(
                _isSendingOtp ? 'Sending...' : 'Send Verification Code',
              ),
              style: FilledButton.styleFrom(
                backgroundColor: AppTheme.brandOrange,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
            ),
          ),
        ] else ...[
          // OTP input fields
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(6, (index) {
              return Container(
                width: 48,
                height: 56,
                margin: EdgeInsets.only(
                  left: index == 0 ? 0 : 6,
                  right: index == 5 ? 0 : 6,
                ),
                child: TextFormField(
                  controller: _otpControllers[index],
                  focusNode: _otpFocusNodes[index],
                  keyboardType: TextInputType.number,
                  textAlign: TextAlign.center,
                  maxLength: 1,
                  style: const TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: _textDark,
                  ),
                  decoration: InputDecoration(
                    counterText: '',
                    filled: true,
                    fillColor: _inputFill,
                    contentPadding: const EdgeInsets.symmetric(vertical: 12),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: const BorderSide(
                        color: _inputBorder,
                        width: 1,
                      ),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide(
                        color: AppTheme.brandOrange,
                        width: 2,
                      ),
                    ),
                  ),
                  onChanged: (value) {
                    if (value.isNotEmpty && index < 5) {
                      _otpFocusNodes[index + 1].requestFocus();
                    } else if (value.isEmpty && index > 0) {
                      _otpFocusNodes[index - 1].requestFocus();
                    }
                    if (index == 5 && value.isNotEmpty) {
                      final otp = _otpControllers.map((c) => c.text).join();
                      if (otp.length == 6) {
                        _verifyOtp();
                      }
                    }
                  },
                ),
              );
            }),
          ),
          const SizedBox(height: 24),

          // Verify button
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: _isVerifying ? null : _verifyOtp,
              style: FilledButton.styleFrom(
                backgroundColor: AppTheme.brandOrange,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              child: _isVerifying
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                      ),
                    )
                  : const Text(
                      'Verify Code',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
            ),
          ),
          const SizedBox(height: 16),

          // Resend timer/button
          if (_resendTimer > 0)
            Text(
              'Resend code in $_resendTimer seconds',
              style: const TextStyle(fontSize: 14, color: _textMuted),
            )
          else
            TextButton.icon(
              onPressed: _isSendingOtp
                  ? null
                  : () {
                      _clearOtpFields();
                      _sendOtp();
                    },
              icon: const Icon(Icons.refresh, size: 18),
              label: const Text('Resend Code'),
              style: TextButton.styleFrom(
                foregroundColor: AppTheme.brandOrange,
              ),
            ),
        ],

        const SizedBox(height: 32),

        // Help text
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.blue.shade50,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.blue.shade100),
          ),
          child: Row(
            children: [
              Icon(Icons.info_outline, color: Colors.blue.shade700, size: 20),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  kIsWeb
                      ? 'For web: Make sure localhost is added to Firebase authorized domains.'
                      : 'Make sure your phone number is correct and can receive SMS messages.',
                  style: TextStyle(fontSize: 13, color: Colors.blue.shade700),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),

        // Skip verification for testing (development only)
        Center(
          child: TextButton(
            onPressed: () {
              showDialog(
                context: context,
                builder: (context) => AlertDialog(
                  title: const Text('Skip Verification?'),
                  content: const Text(
                    'This option is for testing purposes only. '
                    'In production, phone verification should be required.\n\n'
                    'Do you want to skip phone verification?',
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Cancel'),
                    ),
                    FilledButton(
                      onPressed: () {
                        Navigator.pop(context);
                        setState(() {
                          _isPhoneVerified = true;
                          _currentStep++;
                        });
                      },
                      style: FilledButton.styleFrom(
                        backgroundColor: AppTheme.brandOrange,
                      ),
                      child: const Text('Skip'),
                    ),
                  ],
                ),
              );
            },
            child: Text(
              'Skip verification (Testing only)',
              style: TextStyle(
                fontSize: 12,
                color: _textMuted.withOpacity(0.7),
              ),
            ),
          ),
        ),
        const SizedBox(height: 16),

        // Navigation buttons
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            TextButton(
              onPressed: () {
                _timer?.cancel();
                setState(() {
                  _otpSent = false;
                  _resendTimer = 0;
                });
                _clearOtpFields();
                _previousStep();
              },
              child: const Text(
                'Back',
                style: TextStyle(color: _textMuted, fontSize: 15),
              ),
            ),
            if (_isPhoneVerified)
              FilledButton(
                onPressed: _nextStep,
                style: FilledButton.styleFrom(
                  backgroundColor: AppTheme.brandOrange,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 32,
                    vertical: 14,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                child: const Text(
                  'Continue',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                ),
              ),
          ],
        ),
      ],
    );
  }

  Widget _buildPriorDestinationDropdown({
    required String label,
    required String? value,
    required ValueChanged<String?> onChanged,
    required List<String> options,
  }) {
    final effectiveValue = options.contains(value) ? value : null;
    return _buildFormField(
      label: label,
      required: false,
      child: DropdownButtonFormField<String>(
        value: effectiveValue,
        isExpanded: true,
        dropdownColor: Colors.white,
        icon: const SizedBox.shrink(),
        iconSize: 0,
        style: const TextStyle(color: _textDark, fontSize: 14),
        decoration: _inputDecoration(
          hint: 'Select destination',
          prefixIcon: Icons.place_outlined,
        ),
        items: options
            .map((d) => DropdownMenuItem(value: d, child: Text(d)))
            .toList(),
        onChanged: onChanged,
      ),
    );
  }

  Widget _buildTravelHistoryStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Last tourist destinations visited (optional)',
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: _textDark,
          ),
        ),
        const SizedBox(height: 6),
        const Text(
          'Select up to three places you visited before (or choose None).',
          style: TextStyle(fontSize: 13, color: _textMuted, height: 1.35),
        ),
        const SizedBox(height: 16),
        _buildPriorDestinationDropdown(
          label: '1',
          value: _selectedPriorDestination1,
          options: signupPriorDestinationChoices(
            exclude2: _selectedPriorDestination2,
            exclude3: _selectedPriorDestination3,
          ),
          onChanged: (v) => setState(() => _selectedPriorDestination1 = v),
        ),
        const SizedBox(height: 12),
        _buildPriorDestinationDropdown(
          label: '2',
          value: _selectedPriorDestination2,
          options: signupPriorDestinationChoices(
            exclude1: _selectedPriorDestination1,
            exclude3: _selectedPriorDestination3,
          ),
          onChanged: (v) => setState(() => _selectedPriorDestination2 = v),
        ),
        const SizedBox(height: 12),
        _buildPriorDestinationDropdown(
          label: '3',
          value: _selectedPriorDestination3,
          options: signupPriorDestinationChoices(
            exclude1: _selectedPriorDestination1,
            exclude2: _selectedPriorDestination2,
          ),
          onChanged: (v) => setState(() => _selectedPriorDestination3 = v),
        ),
        const SizedBox(height: 24),

        _buildFormField(
          label: 'How did you hear about Misamis Occidental?',
          required: true,
          child: DropdownButtonFormField<String>(
            value: _selectedHowHeard,
            isExpanded: true,
            dropdownColor: Colors.white,
            icon: const SizedBox.shrink(),
            iconSize: 0,
            style: const TextStyle(color: _textDark, fontSize: 14),
            decoration: _inputDecoration(
              hint: 'Select one',
              prefixIcon: Icons.info_outline,
            ),
            items: _howHeardOptions
                .map((o) => DropdownMenuItem(value: o, child: Text(o)))
                .toList(),
            validator: (v) => v == null ? 'Required' : null,
            onChanged: (v) => setState(() => _selectedHowHeard = v),
          ),
        ),
        const SizedBox(height: 24),

        _buildSectionLabel(
          'How will you travel in Misamis Occidental?',
          required: true,
        ),
        const SizedBox(height: 12),
        DropdownButtonFormField<String>(
          value: _selectedTransportation,
          isExpanded: true,
          dropdownColor: Colors.white,
          icon: const SizedBox.shrink(),
          iconSize: 0,
          style: const TextStyle(color: _textDark, fontSize: 14),
          decoration: _inputDecoration(
            hint: 'Select primary mode of transport',
            prefixIcon: Icons.directions_outlined,
          ),
          items: _transportationModes
              .map(
                (m) => DropdownMenuItem(
                  value: m,
                  child: Text(m, overflow: TextOverflow.ellipsis),
                ),
              )
              .toList(),
          validator: (v) => v == null ? 'Please select how you will travel' : null,
          onChanged: (v) => setState(() => _selectedTransportation = v),
        ),
        const SizedBox(height: 24),

        if (_selectedCountry != null) ...[
          const SizedBox(height: 12),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: const Color(0xFFFFF7ED),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: AppTheme.brandOrange.withValues(alpha: 0.25),
              ),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.badge_outlined,
                  size: 20,
                  color: AppTheme.brandOrange,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Visitor type: $_derivedLocalOrForeign'
                    '${_isPhilippines ? ' (Philippines)' : ''}',
                    style: const TextStyle(
                      color: _textDark,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
        const SizedBox(height: 32),

        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            TextButton(
              onPressed: _previousStep,
              child: const Text(
                'Back',
                style: TextStyle(color: _textMuted, fontSize: 15),
              ),
            ),
            FilledButton(
              onPressed: _nextStep,
              style: FilledButton.styleFrom(
                backgroundColor: AppTheme.brandOrange,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(
                  horizontal: 32,
                  vertical: 14,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              child: const Text(
                'Proceed',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildUploadsStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionLabel(
          'Upload a close-up photo of your face',
          required: true,
        ),
        const SizedBox(height: 12),

        Container(
          width: double.infinity,
          height: 180,
          decoration: BoxDecoration(
            color: _inputFill,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: _uploadedImageBytes != null
                  ? AppTheme.brandOrange
                  : _inputBorder,
              width: _uploadedImageBytes != null ? 2 : 1,
            ),
          ),
          child: _uploadedImageBytes != null
              ? Stack(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(7),
                      child: Image.memory(
                        _uploadedImageBytes!,
                        width: double.infinity,
                        height: double.infinity,
                        fit: BoxFit.cover,
                      ),
                    ),
                    Positioned(
                      top: 8,
                      right: 8,
                      child: GestureDetector(
                        onTap: () => setState(() {
                          _uploadedImageBytes = null;
                        }),
                        child: Container(
                          padding: const EdgeInsets.all(4),
                          decoration: const BoxDecoration(
                            color: Colors.red,
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.close,
                            color: Colors.white,
                            size: 16,
                          ),
                        ),
                      ),
                    ),
                    Positioned(
                      bottom: 8,
                      left: 8,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: AppTheme.brandOrange,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.check, color: Colors.white, size: 14),
                            SizedBox(width: 4),
                            Text(
                              'Photo uploaded',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                )
              : Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.camera_alt_outlined,
                      size: 48,
                      color: _textMuted.withOpacity(0.5),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'No file chosen',
                      style: TextStyle(
                        color: _textMuted.withOpacity(0.7),
                        fontSize: 14,
                      ),
                    ),
                  ],
                ),
        ),
        const SizedBox(height: 16),

        FilledButton.icon(
          onPressed: !kIsWeb ? () => _pickImage(ImageSource.camera) : null,
          icon: const Icon(Icons.camera_alt, size: 18),
          label: Text(!kIsWeb ? 'Take a Selfie' : 'Selfie capture is mobile-only'),
          style: FilledButton.styleFrom(
            backgroundColor: AppTheme.brandOrange,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 14),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
          ),
        ),
        const SizedBox(height: 32),

        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 24,
              height: 24,
              child: Checkbox(
                value: _receiveUpdates,
                onChanged: (v) => setState(() => _receiveUpdates = v ?? false),
                activeColor: AppTheme.brandOrange,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(4),
                ),
                side: const BorderSide(color: _inputBorder),
              ),
            ),
            const SizedBox(width: 12),
            const Expanded(
              child: Text(
                'I would like to receive updates and promotions',
                style: TextStyle(fontSize: 14, color: _textMuted),
              ),
            ),
          ],
        ),
        const SizedBox(height: 32),

        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            TextButton(
              onPressed: _previousStep,
              child: const Text(
                'Back',
                style: TextStyle(color: _textMuted, fontSize: 15),
              ),
            ),
            FilledButton(
              onPressed: _isSubmitting ? null : _submitForm,
              style: FilledButton.styleFrom(
                backgroundColor: AppTheme.brandOrange,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(
                  horizontal: 32,
                  vertical: 14,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              child: _isSubmitting
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                      ),
                    )
                  : const Text(
                      'Submit Registration',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
            ),
          ],
        ),
      ],
    );
  }
}

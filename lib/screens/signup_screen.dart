import 'package:flutter/material.dart';
import 'package:atmos_trs_system/config/app_theme.dart';
import 'package:flutter/foundation.dart' show debugPrint, kIsWeb;
import 'package:flutter/services.dart';
import 'dart:async';
import 'package:atmos_trs_system/utils/email_utils.dart';
import 'package:atmos_trs_system/utils/signup_field_validation.dart';
import 'package:atmos_trs_system/utils/tourist_id_helper.dart';
import 'package:atmos_trs_system/utils/firebase_client_blocked_message.dart';
import 'package:atmos_trs_system/config/session_storage.dart';
import 'package:atmos_trs_system/config/auth_config.dart';
import 'package:atmos_trs_system/services/otp_service.dart';
import 'package:atmos_trs_system/services/registration_municipality_resolver.dart';
import 'package:atmos_trs_system/services/tourist_registration_service.dart';
import 'package:atmos_trs_system/services/pending_registration_cache.dart';
import 'package:atmos_trs_system/services/otp_delivery_service.dart';
import 'package:atmos_trs_system/services/registration_rollback_service.dart';
import 'package:atmos_trs_system/services/user_directory_service.dart';
import 'package:atmos_trs_system/data/misamis_occidental_barangays.dart';
import 'package:atmos_trs_system/widgets/web_glass_auth_scaffold.dart';
import 'package:atmos_trs_system/widgets/tourist_signup_chrome.dart';
import 'package:atmos_trs_system/widgets/dial_code_mobile_field.dart';
import 'package:atmos_trs_system/widgets/country_city_autocomplete_field.dart';
import 'package:atmos_trs_system/data/signup_cities_by_country.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';

bool _looksLikeFirebaseBillingDisabled(Object e) {
  final text = e.toString().toLowerCase();
  return text.contains('billing') &&
      (text.contains('delinquent') ||
          text.contains('disabled') ||
          text.contains('402'));
}

/// Capitalizes the first letter of each word (e.g. juan → Juan).
class _CapitalizeWordsFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final text = newValue.text;
    if (text.isEmpty) return newValue;
    final buffer = StringBuffer();
    var capitalizeNext = true;
    for (final rune in text.runes) {
      final ch = String.fromCharCode(rune);
      if (RegExp(r'\s|-').hasMatch(ch)) {
        buffer.write(ch);
        capitalizeNext = true;
      } else if (capitalizeNext) {
        buffer.write(ch.toUpperCase());
        capitalizeNext = false;
      } else {
        buffer.write(ch);
      }
    }
    final formatted = buffer.toString();
    if (formatted == text) return newValue;
    return TextEditingValue(
      text: formatted,
      selection: newValue.selection,
      composing: TextRange.empty,
    );
  }
}

/// Single letter, always uppercase (middle initial).
class _MiddleInitialFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final letters = newValue.text.replaceAll(RegExp(r'[^a-zA-Z]'), '');
    if (letters.isEmpty) {
      return const TextEditingValue(
        text: '',
        selection: TextSelection.collapsed(offset: 0),
      );
    }
    final initial = letters[0].toUpperCase();
    return TextEditingValue(
      text: initial,
      selection: const TextSelection.collapsed(offset: 1),
    );
  }
}

String _capitalizeNameWords(String raw) {
  final trimmed = raw.trim();
  if (trimmed.isEmpty) return '';
  return trimmed.split(RegExp(r'\s+')).map((word) {
    if (word.isEmpty) return word;
    if (word.length == 1) return word.toUpperCase();
    return '${word[0].toUpperCase()}${word.substring(1)}';
  }).join(' ');
}

String _normalizeMiddleInitial(String raw) {
  final letters = raw.replaceAll(RegExp(r'[^a-zA-Z]'), '');
  if (letters.isEmpty) return '';
  return letters[0].toUpperCase();
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
  /// Dial code for primary mobile (synced from nationality/country).
  String _mobileDialCode = '+63';

  // Optional marketing preference (shown on final signup step).
  bool _receiveUpdates = false;
  bool _agreeToTerms = false;
  bool _privacySectionExpanded = false;
  bool _termsSectionExpanded = false;
  bool _hasReviewedPrivacy = false;
  bool _hasReviewedTerms = false;
  bool _isSubmitting = false;
  String? _submitPhase;
  bool _registrationInFlight = false;

  /// Returned from OTP “Edit details” — review/fix fields without cancelling.
  bool _editingPendingSignup = false;
  String? _pendingContactEmailBaseline;
  String? _existingTouristId;
  String? _pendingRegistrationMunicipalityId;
  bool _pendingEditRestoreStarted = false;

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

  static const Color _cardWhite = Colors.white;
  static const Color _textDark = Color(0xFF1F2937);
  static const Color _textMuted = Color(0xFF6B7280);
  static const Color _inputBorder = Color(0xFFE5E7EB);
  static const Color _inputFill = Color(0xFFF3F4F6);
  static const Color _requiredAccent = Color(0xFFEF4444);

  /// Mock visual step (0–2): Personal Details → Personal Info → Contact.
  int get _visualStepIndex {
    switch (_personalDetailsSubStep) {
      case 0:
      case 1:
        return 0;
      case 2:
        return 1;
      default:
        return 2;
    }
  }

  int get _displayStepNumber => _visualStepIndex + 1;

  String get _stepSlogan =>
      TouristSignupChrome.sloganForVisualStep(_visualStepIndex);

  String? _requiredField(String? value, String fieldLabel) {
    if (value == null || value.trim().isEmpty) {
      return '$fieldLabel is required';
    }
    return null;
  }

  final List<String> _suffixes = ['None', 'Jr.', 'Sr.', 'II', 'III', 'IV', 'V'];
  final List<String> _sexOptions = [
    'Male',
    'Female',
    'Prefer not to say',
  ];
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
        // City list depends on country — reset so user picks under new country.
        _foreignCityController.clear();
        _foreignRegionController.clear();
      } else if (!mayPh) {
        if (_selectedCountry == 'Philippines') {
          _selectedCountry = null;
        }
        _clearPhilippineAddressFields();
        _foreignCityController.clear();
      } else if (nationality == 'Filipino' && _selectedCountry == null) {
        _selectedCountry = 'Philippines';
        _clearInternationalAddressFields();
      }
      _syncMobileDialCodeFromCountry();
    });
  }

  void _syncMobileDialCodeFromCountry() {
    _mobileDialCode = dialCodeForCountry(_selectedCountry);
  }

  /// Local digits + selected dial code → E.164-ish value for save / SMS helpers.
  String _mobileForSave() =>
      composeE164Mobile(_mobileDialCode, _mobileController.text);

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
        // Suggestions are country-scoped — clear previous city.
        _foreignCityController.clear();
      }
      _syncMobileDialCodeFromCountry();
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
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_maybeRestorePendingEdit());
    });
  }

  bool get _pendingEmailChanged {
    if (!_editingPendingSignup) return false;
    final baseline = normalizeEmail(
      _pendingContactEmailBaseline ??
          PendingRegistrationCache.forUid(
            FirebaseAuth.instance.currentUser?.uid ?? '',
          )?.contactEmail ??
          '',
    );
    if (baseline.isEmpty) return false;
    return normalizeEmail(_emailController.text) != baseline;
  }

  Future<void> _maybeRestorePendingEdit() async {
    if (!mounted || _pendingEditRestoreStarted) return;
    final args = ModalRoute.of(context)?.settings.arguments;
    final editPending = args is Map && args['editPending'] == true;
    if (!editPending) return;
    _pendingEditRestoreStarted = true;

    await PendingRegistrationCache.hydrate();
    if (!mounted) return;
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      _registrationSnack(
        'Sign-in session missing. Please sign up again.',
        background: Colors.red.shade700,
      );
      return;
    }
    final pending = PendingRegistrationCache.forUid(user.uid);
    if (pending == null) {
      _registrationSnack(
        'No unfinished signup found to edit.',
        background: Colors.orange.shade800,
      );
      return;
    }

    _applyPendingToForm(pending);
    if (!mounted) return;
    setState(() {
      _editingPendingSignup = true;
      _pendingContactEmailBaseline = pending.contactEmail;
      _currentStep = 0;
      _personalDetailsSubStep = 3; // Contact & Address (email)
      _agreeToTerms = true;
      _hasReviewedPrivacy = true;
      _hasReviewedTerms = true;
      _privacySectionExpanded = false;
      _termsSectionExpanded = false;
    });
    _registrationSnack(
      'Review your details. Fix your email if needed, then continue.',
      background: Colors.green.shade700,
    );
  }

  void _applyPendingToForm(PendingRegistration pending) {
    final local = pending.localProfile;
    final t = pending.touristData;

    String str(String key) =>
        (local != null
                ? _localProfileString(local, key)
                : null) ??
            t[key]?.toString() ??
            '';

    _firstNameController.text = str('firstName');
    _middleNameController.text = str('middleName');
    _lastNameController.text = str('lastName');
    _emailController.text = pending.contactEmail.isNotEmpty
        ? pending.contactEmail
        : str('email');
    _selectedSuffix = local?.suffix ?? t['suffix']?.toString();
    if (_selectedSuffix == 'None') _selectedSuffix = null;
    _selectedSex = local?.sex ?? t['sex']?.toString();
    _selectedNationality =
        local?.nationality ?? t['nationality']?.toString();
    _selectedCountry = (local?.country.isNotEmpty == true)
        ? local!.country
        : t['country']?.toString();
    _selectedProvince = (local?.province.isNotEmpty == true)
        ? local!.province
        : t['province']?.toString();
    _selectedCity = (local?.city.isNotEmpty == true)
        ? local!.city
        : t['city']?.toString();

    final barangay = (local?.barangay.isNotEmpty == true)
        ? local!.barangay
        : (t['barangay']?.toString() ?? '');
    if (_selectedProvince == 'Misamis Occidental' &&
        isMisamisOccidentalSignupCity(_selectedCity)) {
      _selectedBarangay = barangay.isEmpty ? null : barangay;
      _barangayController.clear();
    } else {
      _selectedBarangay = null;
      _barangayController.text = barangay;
    }

    if (_selectedCountry != null && _selectedCountry != 'Philippines') {
      _foreignCityController.text = _selectedCity ?? '';
      _foreignRegionController.text = _selectedProvince ?? '';
    }

    _applyMobileFromSaved(local?.mobile ?? t['mobile']?.toString() ?? '');
    _applyDobFromSaved(local?.dateOfBirth ?? t['dateOfBirth']?.toString());

    final parent = t['parentGuardianFullName']?.toString();
    if (parent != null && parent.isNotEmpty) {
      _parentGuardianController.text = parent;
    }
    _receiveUpdates = t['receiveUpdates'] == true;
    _existingTouristId =
        local?.touristId ?? t['touristId']?.toString();
    final muni = t['registrationMunicipalityId']?.toString();
    if (muni != null && muni.isNotEmpty) {
      _pendingRegistrationMunicipalityId = muni;
    }
  }

  String? _localProfileString(PendingLocalProfile local, String key) {
    switch (key) {
      case 'firstName':
        return local.firstName;
      case 'middleName':
        return local.middleName;
      case 'lastName':
        return local.lastName;
      case 'email':
        return local.email;
      default:
        return null;
    }
  }

  void _applyMobileFromSaved(String saved) {
    final parsed = parseStoredMobile(saved);
    _mobileDialCode = parsed.dialCode;
    _mobileController.text = parsed.localDigits;
  }

  void _applyDobFromSaved(String? dob) {
    if (dob == null || dob.trim().isEmpty) return;
    final parts = dob.trim().split('-');
    if (parts.length != 3) return;
    final y = int.tryParse(parts[0]);
    final m = int.tryParse(parts[1]);
    final d = int.tryParse(parts[2]);
    if (y == null || m == null || d == null) return;
    _selectedYear = y;
    _selectedMonth = m;
    _selectedDay = d;
    _selectedDateOfBirth = DateTime(y, m, d);
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

  String? _validateTravelParty() {
    if (_isMinorRegistrant()) {
      if (_parentGuardianController.text.trim().isEmpty) {
        return 'Please enter your parent or guardian\'s full name.';
      }
      return null;
    }
    // Adults: party size / gender is asked on QR scan welcome — not during signup.
    return null;
  }

  /// Profile headcount is 1; visit party size comes from the QR check-in flow.
  int _computePartyHeadcount() => 1;

  int _accompanyingChildrenForSave() => 0;

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
              decoration: BoxDecoration(
                color: _legalMutedColor,
                shape: BoxShape.circle,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                fontSize: 14,
                color: _legalBodyColor,
                height: 1.55,
                fontWeight: _isDesktopGlass ? FontWeight.w500 : FontWeight.w400,
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
        color: done
            ? accent.withValues(alpha: _isDesktopGlass ? 0.38 : 0.1)
            : (_isDesktopGlass
                ? Colors.black.withValues(alpha: 0.38)
                : const Color(0xFFF9FAFB)),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: done
              ? accent.withValues(alpha: _isDesktopGlass ? 0.85 : 0.45)
              : (_isDesktopGlass
                  ? Colors.white.withValues(alpha: 0.28)
                  : _inputBorder),
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            done ? Icons.check_circle_rounded : icon,
            size: 16,
            color: done
                ? (_isDesktopGlass ? Colors.white : accent)
                : _legalMutedColor,
          ),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: done
                    ? (_isDesktopGlass ? Colors.white : accent)
                    : _legalMutedColor,
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
      color: _legalSurface(surface),
      elevation: expanded ? 2 : 0,
      shadowColor: accent.withValues(alpha: 0.12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: reviewed
              ? accent.withValues(alpha: _isDesktopGlass ? 0.75 : 0.5)
              : (_isDesktopGlass
                  ? Colors.white.withValues(alpha: 0.22)
                  : border),
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
                  colors: _isDesktopGlass
                      ? [
                          accent.withValues(alpha: 0.62),
                          Colors.black.withValues(alpha: 0.38),
                        ]
                      : [
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
                      color: _isDesktopGlass
                          ? Colors.white.withValues(alpha: 0.14)
                          : Colors.white.withValues(alpha: 0.85),
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: [
                        BoxShadow(
                          color: accent.withValues(alpha: 0.15),
                          blurRadius: 8,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Icon(
                      icon,
                      color: _isDesktopGlass ? Colors.white : accent,
                      size: 22,
                    ),
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
                                style: TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w800,
                                  color: _legalTitleColor,
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
                                  color: accent.withValues(
                                    alpha: _isDesktopGlass ? 0.35 : 0.15,
                                  ),
                                  borderRadius: BorderRadius.circular(20),
                                  border: _isDesktopGlass
                                      ? Border.all(
                                          color: Colors.white
                                              .withValues(alpha: 0.35),
                                        )
                                      : null,
                                ),
                                child: Text(
                                  'Read',
                                  style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w800,
                                    color:
                                        _isDesktopGlass ? Colors.white : accent,
                                  ),
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(height: 2),
                        Text(
                          subtitle,
                          style: TextStyle(
                            fontSize: 12,
                            color: _legalMutedColor,
                            height: 1.35,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Icon(
                    expanded
                        ? Icons.keyboard_arrow_up_rounded
                        : Icons.keyboard_arrow_down_rounded,
                    color: _isDesktopGlass ? Colors.white : accent,
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
          color: _legalAgreementFill(agreed: _agreeToTerms),
          elevation: _agreeToTerms ? 1 : 0,
          shadowColor: AppTheme.brandOrange.withValues(alpha: 0.2),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(
              color: _agreeToTerms
                  ? AppTheme.brandOrange
                  : (canAgree
                      ? (_isDesktopGlass
                          ? Colors.white.withValues(alpha: 0.28)
                          : _inputBorder)
                      : Colors.amber.shade200),
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
                              : (_isDesktopGlass
                                  ? Colors.white.withValues(alpha: 0.45)
                                  : _inputBorder),
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
                                  ? (_isDesktopGlass
                                      ? Colors.white
                                      : AppTheme.brandOrange)
                                  : _legalTitleColor,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'I have read and agree to the Terms and Conditions '
                            'and the Data Privacy Policy (Republic Act No. 10173) '
                            'of ATMOS-TRS - Asenso Tourismo Misamis Occidental '
                            'Smart Tourist Registration System.',
                            style: TextStyle(
                              fontSize: 14,
                              color: _legalBodyColor,
                              height: 1.55,
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
      if (_personalDetailsSubStep == 3) {
        // Adults: contact is the last signup step (photo is post-registration).
        // Minors continue to parent/guardian.
        if (!_isMinorRegistrant()) {
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
        return;
      }
      if (_personalDetailsSubStep < 4) {
        setState(() {
          _personalDetailsSubStep++;
        });
        return;
      }
    }
  }

  void _focusNextFormField() {
    if (_isSubmitting) return;
    FocusScope.of(context).nextFocus();
  }

  void _submitCurrentStepFromKeyboard() {
    if (_isSubmitting || _registrationInFlight) return;
    if (_currentStep == 0) {
      final lastAdult =
          _personalDetailsSubStep == 3 && !_isMinorRegistrant();
      final lastMinor = _personalDetailsSubStep == 4;
      if (lastAdult || lastMinor) {
        if (_formKey.currentState?.validate() ?? false) {
          unawaited(_submitForm());
        }
        return;
      }
    }
    _nextStep();
  }

  void _previousStep() {
    if (_personalDetailsSubStep > 0) {
      setState(() => _personalDetailsSubStep--);
    }
  }

  String _formatPhoneNumber(String phone) {
    return composeE164Mobile(_mobileDialCode, phone);
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
          style: TextStyle(color: Colors.white, fontSize: 14),
        ),
        backgroundColor: background,
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 8),
      ),
    );
  }

  void _setSubmitting(bool v, {String? phase}) {
    if (!mounted) return;
    setState(() {
      _isSubmitting = v;
      _submitPhase = v ? (phase ?? _submitPhase) : null;
    });
  }

  void _updateSubmitPhase(String phase) {
    if (mounted && _isSubmitting) {
      setState(() => _submitPhase = phase);
    }
  }

  /// Full registration validation on final submit (step 3 has almost no [FormField]s).
  String? _validateRegistrationSnapshot() {
    if (!_legalReviewComplete) {
      return 'Please open and read both the Data Privacy and Terms sections (Step 1).';
    }
    if (!_agreeToTerms) {
      return 'Please agree to the Terms and Conditions and Data Privacy Policy.';
    }
    if (_selectedSex == null) return 'Please select your sex (Step 1).';
    if (_selectedNationality == null) {
      return 'Please select your nationality (Step 1).';
    }
    if (_selectedDateOfBirth == null &&
        (_selectedDay == null ||
            _selectedMonth == null ||
            _selectedYear == null)) {
      return 'Please select your complete date of birth (Step 1).';
    }
    final mobileErr = validateMobileForDialCode(
      _mobileController.text,
      _mobileDialCode,
    );
    if (mobileErr != null) return mobileErr;
    if (_selectedCountry == null) {
      return 'Please select your country (Step 1).';
    }
    if (_showPhilippineSubdivisions) {
      if (_selectedProvince == null || _selectedCity == null) {
        return 'Please select province and city/municipality (Step 1).';
      }
      final barangayErr = _validateBarangayField(_selectedBarangay);
      if (barangayErr != null) return barangayErr;
    } else if (_showInternationalAddressFields) {
      final cityErr = validateInternationalCity(_foreignCityController.text);
      if (cityErr != null) return cityErr;
      if (_showForeignStateRegion) {
        final regionErr =
            validateInternationalRegion(_foreignRegionController.text);
        if (regionErr != null) return regionErr;
      }
    }
    if (_passwordController.text != _confirmPasswordController.text) {
      return 'Password and confirm password do not match.';
    }
    return _validateRegistrationExtra();
  }

  /// Extra checks beyond [FormState] validators (terms, password length).
  /// Profile photo is optional — many tourists prefer to skip it.
  String? _validateRegistrationExtra() {
    final email = normalizeEmail(_emailController.text);
    if (email.isEmpty) return 'Please enter your email address.';
    if (!isValidEmailFormat(_emailController.text)) {
      return 'Please enter a valid email address.';
    }
    final pw = _passwordController.text;
    final emailChanging = _editingPendingSignup && _pendingEmailChanged;
    if (!_editingPendingSignup || emailChanging || pw.isNotEmpty) {
      if (pw.isEmpty) {
        return emailChanging
            ? 'Enter your password to change your email.'
            : 'Please enter a password.';
      }
      if (pw.length < 8) {
        return 'Password must be at least 8 characters.';
      }
      if (_confirmPasswordController.text != pw) {
        return 'Password and confirm password do not match.';
      }
    }
    if (_firstNameController.text.trim().isEmpty) {
      return 'Please enter your first name.';
    }
    if (_lastNameController.text.trim().isEmpty) {
      return 'Please enter your last name.';
    }
    return null;
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

  /// When Auth still has an email but Firestore registration was deleted (or never
  /// completed), sign in with the same password, wipe the remnant, so signup can
  /// recreate the account. Returns true if Auth is clear for a new createUser.
  Future<bool> _tryReclaimOrphanAuthEmail({
    required String contactEmail,
    required String authEmail,
    required String password,
  }) async {
    final durable =
        await UserDirectoryService.emailHasDurableRegistration(contactEmail);
    if (durable) return false;

    try {
      try {
        await FirebaseAuth.instance.signOut();
      } catch (_) {}
      final cred = await FirebaseAuth.instance.signInWithEmailAndPassword(
        email: authEmail,
        password: password,
      );
      final orphanUid = cred.user?.uid;
      if (orphanUid == null || orphanUid.isEmpty) return false;
      await RegistrationRollbackService.rollback(orphanUid);
      try {
        await FirebaseAuth.instance.signOut();
      } catch (_) {}
      debugPrint('[REG] reclaimed orphan Auth for $authEmail');
      return true;
    } on FirebaseAuthException catch (e) {
      debugPrint('[REG] orphan reclaim failed: ${e.code} ${e.message}');
      return false;
    } catch (e, st) {
      debugPrint('[REG] orphan reclaim error: $e\n$st');
      return false;
    }
  }

  Future<void> _handleEmailAlreadyInUseOnSignup({
    required String contactEmail,
    required String authEmail,
    required String password,
  }) async {
    final durable =
        await UserDirectoryService.emailHasDurableRegistration(contactEmail);
    if (durable) {
      if (mounted) {
        _registrationSnack(
          'This email is already registered. Please sign in instead.',
          background: Colors.orange.shade800,
        );
        Navigator.pushReplacementNamed(context, '/login');
      }
      return;
    }

    if (mounted) {
      _registrationSnack(
        'This email was removed from the system. '
        'Sign up again with the same password to recreate your account, '
        'or use a different email.',
        background: Colors.orange.shade800,
      );
    }
    final reclaimed = await _tryReclaimOrphanAuthEmail(
      contactEmail: contactEmail,
      authEmail: authEmail,
      password: password,
    );
    if (!mounted) return;
    if (reclaimed) {
      _registrationSnack(
        'Previous account cleared. Tap Submit Registration again to continue.',
        background: Colors.green.shade700,
      );
    } else {
      _registrationSnack(
        'Could not free this email automatically. Use the password from the '
        'old signup and tap Submit again, or contact support.',
        background: Colors.red.shade700,
      );
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
          .timeout(const Duration(seconds: 8));
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
    if (e.code == 'weak-password') {
      return 'Password was rejected by Firebase. Use at least 8 characters '
          '(your project may still require a stronger password in Firebase Console).';
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

  /// Re-save pending signup after OTP “Edit details” (no cancel / rollback).
  Future<void> _submitPendingSignupEdits() async {
    if (_registrationInFlight || _isSubmitting) return;
    _registrationInFlight = true;
    debugPrint('[REG] ========== pending edit start ==========');

    try {
      final snapshotError = _validateRegistrationSnapshot();
      if (snapshotError != null) {
        _registrationSnack(snapshotError, background: Colors.red.shade700);
        return;
      }
      if (_formKey.currentState != null && !_formKey.currentState!.validate()) {
        _registrationSnack(
          'Please fix the highlighted fields before continuing.',
          background: Colors.red.shade700,
        );
        return;
      }

      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        _registrationSnack(
          'Session expired. Please sign up again.',
          background: Colors.red.shade700,
        );
        return;
      }
      await PendingRegistrationCache.hydrate();
      final existing = PendingRegistrationCache.forUid(user.uid);
      if (existing == null) {
        _registrationSnack(
          'No unfinished signup found.',
          background: Colors.red.shade700,
        );
        return;
      }

      _setSubmitting(true, phase: 'Saving your updates…');
      TextInput.finishAutofillContext(shouldSave: false);

      final contactEmail = normalizeEmail(_emailController.text);
      final emailChanged =
          contactEmail != normalizeEmail(existing.contactEmail);
      var authEmail = emailChanged
          ? contactEmail
          : (existing.authEmail.isNotEmpty
              ? existing.authEmail
              : contactEmail);
      var regUid = user.uid;
      String? registrationOtp;
      var otpAlreadySent = true;
      var emailDeliveryFailed = false;

      if (emailChanged) {
        final password = _passwordController.text;
        _updateSubmitPhase('Updating account email…');
        try {
          final oldAuthEmail = normalizeEmail(
            existing.authEmail.isNotEmpty
                ? existing.authEmail
                : (user.email ?? existing.contactEmail),
          );
          final credential = EmailAuthProvider.credential(
            email: oldAuthEmail,
            password: password,
          );
          await user.reauthenticateWithCredential(credential);
          try {
            await OtpService.deleteOtp(user.uid);
          } catch (_) {}
          // Keep pending until new Auth user exists.
          await user.delete();

          try {
            final cred =
                await FirebaseAuth.instance.createUserWithEmailAndPassword(
              email: authEmail,
              password: password,
            );
            regUid = cred.user?.uid ?? '';
          } on FirebaseAuthException catch (e) {
            if (e.code == 'email-already-in-use' &&
                _isMinorRegistrant() &&
                _isGmailAddress(contactEmail)) {
              authEmail = _buildMinorGmailAlias(contactEmail);
              final cred =
                  await FirebaseAuth.instance.createUserWithEmailAndPassword(
                email: authEmail,
                password: password,
              );
              regUid = cred.user?.uid ?? '';
            } else {
              rethrow;
            }
          }
          if (regUid.isEmpty) {
            throw StateError('Auth user id missing after email change.');
          }
          await _ensureAuthReadyForFirestore(regUid);
          registrationOtp = OtpService.generateSixDigitOtp();
          await OtpService.saveOtp(
            uid: regUid,
            email: contactEmail,
            otp: registrationOtp,
          );
          otpAlreadySent = false;
        } on FirebaseAuthException catch (e) {
          _setSubmitting(false);
          _registrationSnack(
            e.code == 'wrong-password' || e.code == 'invalid-credential'
                ? 'Wrong password. Enter the password you used to sign up.'
                : _formatFirebaseAuthException(e),
            background: Colors.red.shade700,
          );
          return;
        } catch (e) {
          _setSubmitting(false);
          _registrationSnack(
            _formatRegistrationError(e),
            background: Colors.red.shade700,
          );
          return;
        }
      }

      final firstName = _capitalizeNameWords(_firstNameController.text);
      final middleInitial =
          _normalizeMiddleInitial(_middleNameController.text);
      final lastName = _capitalizeNameWords(_lastNameController.text);
      String fullName = firstName;
      if (middleInitial.isNotEmpty) fullName += ' $middleInitial.';
      fullName += ' $lastName';
      if (_selectedSuffix != null && _selectedSuffix != 'None') {
        fullName += ' $_selectedSuffix';
      }

      String? dobString;
      if (_selectedDateOfBirth != null) {
        dobString =
            '${_selectedDateOfBirth!.year}-${_selectedDateOfBirth!.month.toString().padLeft(2, '0')}-${_selectedDateOfBirth!.day.toString().padLeft(2, '0')}';
      }

      final ageYears = _ageInYears();
      final isMinorAccount =
          ageYears != null && ageYears <= _minorMaxAgeYears;
      final touristId = (_existingTouristId != null &&
              _existingTouristId!.trim().isNotEmpty)
          ? _existingTouristId!.trim()
          : TouristIdHelper.generate(province: _resolvedProvinceForSave());

      String? profileImageBase64 = existing.localProfile?.profileImageBase64 ??
          existing.touristData['profileImageBase64']?.toString();
      String? profilePhotoUrl = existing.localProfile?.profilePhotoUrl ??
          existing.touristData['profilePhotoUrl']?.toString();
      var usedPhotoFirestoreFallback = existing.usedPhotoFirestoreFallback;

      final registrationMunicipalityId =
          RegistrationMunicipalityResolver.fromHomeAddress(
            country: _selectedCountry,
            province: _resolvedProvinceForSave(),
            city: _resolvedCityForSave(),
          );

      final touristData = <String, dynamic>{
        ...Map<String, dynamic>.from(existing.touristData),
        'touristId': touristId,
        'firebaseUid': regUid,
        'firstName': firstName,
        'middleName': middleInitial,
        'lastName': lastName,
        'fullName': fullName,
        'suffix': _selectedSuffix,
        'sex': _selectedSex,
        'nationality': _selectedNationality,
        'dateOfBirth': dobString,
        'mobile': _mobileForSave(),
        'email': contactEmail,
        'authEmail': authEmail,
        'country': _selectedCountry,
        'province': _resolvedProvinceForSave(),
        'city': _resolvedCityForSave(),
        'street': '',
        'barangay': _resolvedBarangay(),
        'profilePhotoUrl': profilePhotoUrl,
        'profilePhotoPending': usedPhotoFirestoreFallback,
        'isLocal': _isPhilippines,
        'localOrForeign': _derivedLocalOrForeign,
        'receiveUpdates': _receiveUpdates,
        if (registrationMunicipalityId != null &&
            registrationMunicipalityId.isNotEmpty)
          'registrationMunicipalityId': registrationMunicipalityId,
        'isVerified': false,
        'minorAccountHolder': isMinorAccount,
        'parentGuardianFullName': isMinorAccount
            ? _parentGuardianController.text.trim()
            : null,
        if (isMinorAccount) 'parentGuardianEmail': contactEmail,
      };
      if (profileImageBase64 != null) {
        touristData['profileImageBase64'] = profileImageBase64;
      } else {
        touristData.remove('profileImageBase64');
      }

      final userData = <String, dynamic>{
        ...Map<String, dynamic>.from(existing.userData),
        'firebaseUid': regUid,
        'email': authEmail,
        if (isMinorAccount) 'parentGuardianEmail': contactEmail,
        'fullName': fullName,
        'role': 'tourist',
        'isVerified': false,
      };

      await PendingRegistrationCache.save(
        PendingRegistration(
          uid: regUid,
          contactEmail: contactEmail,
          authEmail: authEmail,
          touristData: TouristRegistrationService.jsonSafeMap(touristData),
          userData: TouristRegistrationService.jsonSafeMap(userData),
          usedPhotoFirestoreFallback: usedPhotoFirestoreFallback,
          localProfile: PendingLocalProfile(
            firstName: firstName,
            middleName: middleInitial,
            lastName: lastName,
            suffix: _selectedSuffix,
            sex: _selectedSex,
            nationality: _selectedNationality,
            dateOfBirth: dobString,
            mobile: _mobileForSave(),
            email: contactEmail,
            country: _selectedCountry ?? '',
            province: _resolvedProvinceForSave(),
            city: _resolvedCityForSave(),
            street: '',
            barangay: _resolvedBarangay(),
            touristId: touristId,
            profileImageBase64: profileImageBase64,
            profilePhotoUrl: profilePhotoUrl,
          ),
        ),
      );

      AuthConfig.currentUserUid = regUid;
      try {
        await SessionStorage.saveSession(
          regUid,
          role: UserRole.tourist,
          email: authEmail,
        );
      } catch (e, st) {
        debugPrint('[REG] pending-edit session (non-fatal): $e\n$st');
      }

      if (emailChanged && registrationOtp != null) {
        _updateSubmitPhase('Sending email code…');
        final delivery = await OtpDeliveryService.deliverVerificationCode(
          uid: regUid,
          email: contactEmail,
          displayName: fullName,
          otp: registrationOtp,
          mobile: _mobileForSave(),
          notifyOnThisDevice: false,
          trySms: false,
          otpAlreadyInFirestore: true,
          emailInBackground: true,
        ).timeout(
          const Duration(seconds: 5),
          onTimeout: () => const OtpDeliveryResult(
            emailSent: false,
            emailError: 'Delivery timed out',
            otpAlreadyInFirestore: true,
          ),
        );
        emailDeliveryFailed = !delivery.canCompleteRegistration;
        if (!mounted) return;
        _registrationSnack(
          delivery.emailSent
              ? 'We sent a new code to $contactEmail.'
              : delivery.messageForUser(contactEmail),
          background: delivery.emailSent
              ? Colors.green.shade700
              : Colors.orange.shade800,
        );
      } else if (!mounted) {
        return;
      } else {
        _registrationSnack(
          'Details updated. Enter the code sent to $contactEmail.',
          background: Colors.green.shade700,
        );
      }

      _setSubmitting(false);
      if (!mounted) return;
      Navigator.pushReplacementNamed(
        context,
        '/verify-otp',
        arguments: <String, dynamic>{
          'contactEmail': contactEmail,
          'fromSignup': true,
          'otpAlreadySent': otpAlreadySent || !emailChanged,
          'emailDeliveryFailed': emailDeliveryFailed,
        },
      );
      debugPrint('[REG] ========== pending edit end ==========');
    } finally {
      _registrationInFlight = false;
      if (mounted) _setSubmitting(false);
    }
  }

  Future<void> _submitForm() async {
    if (_registrationInFlight || _isSubmitting) {
      debugPrint('[REG] submit ignored (already in progress)');
      return;
    }
    if (_editingPendingSignup) {
      await _submitPendingSignupEdits();
      return;
    }
    _registrationInFlight = true;
    debugPrint('[REG] ========== registration start ==========');

    try {
      final snapshotError = _validateRegistrationSnapshot();
      if (snapshotError != null) {
        debugPrint('[REG] validation failed: $snapshotError');
        _registrationSnack(snapshotError, background: Colors.red.shade700);
        return;
      }

      if (_formKey.currentState != null &&
          !_formKey.currentState!.validate()) {
        debugPrint('[REG] Form field validators failed');
        _registrationSnack(
          'Please fix the highlighted fields before submitting.',
          background: Colors.red.shade700,
        );
        return;
      }

      // Decline OS/browser "save password?" prompts (esp. Chrome) for shared/public devices.
      TextInput.finishAutofillContext(shouldSave: false);

      _setSubmitting(true, phase: 'Creating account…');

      if (Firebase.apps.isEmpty) {
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

    // Home LGU for Registered tourists = signup address (not QR scan place).
    final Future<String?> municipalityFuture = Future<String?>.value(
      RegistrationMunicipalityResolver.fromHomeAddress(
        country: _selectedCountry,
        province: _resolvedProvinceForSave(),
        city: _resolvedCityForSave(),
      ),
    );

    // Firebase Auth 6 removed fetchSignInMethodsForEmail (email enumeration).
    // For minors using a parent Gmail, try that address first; on conflict we
    // retry with a protected alias below in the createUser catch path.
    var minorAliasRetryEligible =
        isMinorRegistrant && _isGmailAddress(contactEmail);

    UserCredential? userCredential;
    String? uid;
    String? registrationOtp;

    // --- STEP 1: Firebase Auth + OTP save (must succeed before navigate) ---
    try {
      debugPrint('[REG] STEP 1: createUserWithEmailAndPassword');
      try {
        await FirebaseAuth.instance.signOut();
      } catch (_) {}
      try {
        userCredential = await FirebaseAuth.instance.createUserWithEmailAndPassword(
          email: authEmail,
          password: password,
        );
      } on FirebaseAuthException catch (e) {
        if (e.code == 'email-already-in-use' &&
            minorAliasRetryEligible &&
            authEmail == contactEmail) {
          authEmail = _buildMinorGmailAlias(contactEmail);
          minorAliasRetryEligible = false;
          if (mounted) {
            _registrationSnack(
              'Parent/guardian Gmail is already used. Minor account will proceed using a protected alias.',
              background: Colors.green.shade700,
            );
          }
          userCredential =
              await FirebaseAuth.instance.createUserWithEmailAndPassword(
            email: authEmail,
            password: password,
          );
        } else if (e.code == 'email-already-in-use') {
          final reclaimed = await _tryReclaimOrphanAuthEmail(
            contactEmail: contactEmail,
            authEmail: authEmail,
            password: password,
          );
          if (!reclaimed) rethrow;
          userCredential =
              await FirebaseAuth.instance.createUserWithEmailAndPassword(
            email: authEmail,
            password: password,
          );
        } else {
          rethrow;
        }
      }
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
      await _ensureAuthReadyForFirestore(uid);

      _updateSubmitPhase('Saving verification code…');
      registrationOtp = OtpService.generateSixDigitOtp();
      debugPrint('[REG] STEP 3: email_otps save (immediately after auth)');
      await OtpService.saveOtp(
        uid: uid,
        email: contactEmail,
        otp: registrationOtp,
      );
      debugPrint('[REG] STEP 3 OK');
    } on FirebaseAuthException catch (e, st) {
      debugPrint('[REG] STEP 1 FAIL: code=${e.code} message=${e.message}\n$st');
      _setSubmitting(false);
      if (e.code == 'email-already-in-use') {
        await _handleEmailAlreadyInUseOnSignup(
          contactEmail: contactEmail,
          authEmail: authEmail,
          password: password,
        );
        return;
      }
      _registrationSnack(
        _formatFirebaseAuthException(e),
        background: Colors.red.shade700,
      );
      return;
    } on FirebaseException catch (e, st) {
      debugPrint(
        '[REG] STEP 3 FAIL: plugin=${e.plugin} code=${e.code} message=${e.message}\n$st',
      );
      await _deleteAuthUserBestEffort();
      _registrationSnack(
        'Verification code could not be saved. Your account was not created. '
        'Please try again. If this persists, contact support.',
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

    // OTP is saved — never delete the Auth user from here on (keeps code intact).
    final String regUid = uid;
    _updateSubmitPhase('Preparing your profile…');

    // Profile photo is optional and added later from Profile tab.
    debugPrint('[REG] STEP 2: skipping profile photo during signup');
    final String? registrationMunicipalityId = await municipalityFuture;

    // --- Prepare name + tourist id (needed for Firestore) ---
    final touristId = TouristIdHelper.generate(
      province: _resolvedProvinceForSave(),
    );

    String? dobString;
    if (_selectedDateOfBirth != null) {
      dobString =
          '${_selectedDateOfBirth!.year}-${_selectedDateOfBirth!.month.toString().padLeft(2, '0')}-${_selectedDateOfBirth!.day.toString().padLeft(2, '0')}';
    }

    final firstName = _capitalizeNameWords(_firstNameController.text);
    final middleInitial =
        _normalizeMiddleInitial(_middleNameController.text);
    final lastName = _capitalizeNameWords(_lastNameController.text);
    // Keep controllers in sync with normalized casing for later UI / pending save.
    if (_firstNameController.text != firstName) {
      _firstNameController.value = TextEditingValue(
        text: firstName,
        selection: TextSelection.collapsed(offset: firstName.length),
      );
    }
    if (_middleNameController.text != middleInitial) {
      _middleNameController.value = TextEditingValue(
        text: middleInitial,
        selection: TextSelection.collapsed(offset: middleInitial.length),
      );
    }
    if (_lastNameController.text != lastName) {
      _lastNameController.value = TextEditingValue(
        text: lastName,
        selection: TextSelection.collapsed(offset: lastName.length),
      );
    }

    String fullName = firstName;
    if (middleInitial.isNotEmpty) {
      fullName += ' $middleInitial.';
    }
    fullName += ' $lastName';
    if (_selectedSuffix != null && _selectedSuffix != 'None') {
      fullName += ' $_selectedSuffix';
    }

    final ageYears = _ageInYears();
    final isMinorAccount = ageYears != null && ageYears <= _minorMaxAgeYears;
    final accompanyingChildren = _accompanyingChildrenForSave();
    final partyHeadcount = _computePartyHeadcount();

    final otp = registrationOtp;

    // --- STEP 4: email Inbox only (no on-device OTP popup) ---
    // Do NOT sync FCM / write users|tourists stubs until after OTP verification.
    _updateSubmitPhase('Sending email code…');
    debugPrint('[REG] STEP 4: OTP email delivery (Inbox only, no local popup)');
    final delivery = await OtpDeliveryService.deliverVerificationCode(
      uid: regUid,
      email: contactEmail,
      displayName: fullName,
      otp: otp,
      mobile: _mobileForSave(),
      notifyOnThisDevice: false,
      trySms: false,
      otpAlreadyInFirestore: true,
      emailInBackground: true,
    ).timeout(
      const Duration(seconds: 5),
      onTimeout: () {
        debugPrint('[REG] STEP 4 timeout — continuing with saved OTP');
        return const OtpDeliveryResult(
          emailSent: false,
          emailError: 'Delivery timed out',
          otpAlreadyInFirestore: true,
        );
      },
    );
    // OTP already in Firestore — never roll back for delivery hiccups.
    if (delivery.emailSent) {
      debugPrint('[REG] STEP 4 OK: email sent');
    } else {
      debugPrint(
        '[REG] STEP 4: email deferred/background — OTP saved, continuing to verify',
      );
    }

    _updateSubmitPhase('Opening verification…');

    // --- Defer Firestore profile until OTP verified on /verify-otp ---
    final touristData = <String, dynamic>{
      'touristId': touristId,
      'firebaseUid': regUid,
      'firstName': firstName,
      'middleName': middleInitial,
      'lastName': lastName,
      'fullName': fullName,
      'suffix': _selectedSuffix,
      'sex': _selectedSex,
      'nationality': _selectedNationality,
      'dateOfBirth': dobString,
      'mobile': _mobileForSave(),
      'email': contactEmail,
      'authEmail': authEmail,
      'country': _selectedCountry,
      'province': _resolvedProvinceForSave(),
      'city': _resolvedCityForSave(),
      'street': '',
      'barangay': _resolvedBarangay(),
      'profilePhotoUrl': null,
      'profilePhotoPending': false,
      'isLocal': _isPhilippines,
      'localOrForeign': _derivedLocalOrForeign,
      'transportation': '',
      'travelHistory': {
        'firstDestination': '',
        'secondDestination': '',
        'thirdDestination': '',
        'howHeardAbout': '',
      },
      'receiveUpdates': _receiveUpdates,
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
      'firebaseUid': regUid,
      'email': authEmail,
      if (isMinorAccount) 'parentGuardianEmail': contactEmail,
      'fullName': fullName,
      'role': 'tourist',
      'municipality': '',
      'isVerified': false,
    };

    await PendingRegistrationCache.save(
      PendingRegistration(
        uid: regUid,
        contactEmail: contactEmail,
        authEmail: authEmail,
        touristData: TouristRegistrationService.jsonSafeMap(touristData),
        userData: TouristRegistrationService.jsonSafeMap(userData),
        usedPhotoFirestoreFallback: false,
        localProfile: PendingLocalProfile(
          firstName: firstName,
          middleName: middleInitial,
          lastName: lastName,
          suffix: _selectedSuffix,
          sex: _selectedSex,
          nationality: _selectedNationality,
          dateOfBirth: dobString,
          mobile: _mobileForSave(),
          email: contactEmail,
          country: _selectedCountry ?? '',
          province: _resolvedProvinceForSave(),
          city: _resolvedCityForSave(),
          street: '',
          barangay: _resolvedBarangay(),
          touristId: touristId,
          profileImageBase64: null,
          profilePhotoUrl: null,
        ),
      ),
    );

    AuthConfig.currentUserUid = regUid;
    try {
      await SessionStorage.saveSession(
        regUid,
        role: UserRole.tourist,
        email: authEmail,
      );
    } catch (e, st) {
      debugPrint('[REG] session save (non-fatal): $e\n$st');
    }

    _setSubmitting(false);
    if (mounted) {
      debugPrint('[REG] STEP 5 deferred — navigate to verify-otp');
      final snackMsg = delivery.emailSent
          ? 'We sent a 6-digit code to $contactEmail. Open your email Inbox and enter it below.'
          : delivery.messageForUser(contactEmail);
      _registrationSnack(
        snackMsg,
        background: delivery.emailSent || delivery.smsSent
            ? Colors.green.shade700
            : Colors.orange.shade800,
      );
      if (!mounted) return;
      Navigator.pushReplacementNamed(
        context,
        '/verify-otp',
        arguments: <String, dynamic>{
          'contactEmail': contactEmail,
          'fromSignup': true,
          'otpAlreadySent': true,
          'emailDeliveryFailed': !delivery.canCompleteRegistration,
        },
      );
    }
      debugPrint('[REG] ========== registration end ==========');
    } finally {
      _registrationInFlight = false;
      if (mounted) _setSubmitting(false);
    }
  }

  InputDecoration _inputDecoration({
    required String hint,
    IconData? prefixIcon,
    Widget? suffixIcon,
    /// Frees horizontal room so long values (e.g. emails) stay fully visible.
    bool compact = false,
  }) {
    if (_isDesktopGlass) {
      final base = webGlassInputDecoration(
        hint: hint,
        prefixIcon: prefixIcon,
        suffixIcon: suffixIcon,
      );
      return base.copyWith(
        fillColor: _formFillColor,
        hintStyle: compact
            ? _fieldHintTextStyle.copyWith(fontSize: 14)
            : _fieldHintTextStyle,
      );
    }
    return InputDecoration(
      hintText: hint,
      hintStyle: compact
          ? _fieldHintTextStyle.copyWith(fontSize: 14)
          : _fieldHintTextStyle,
      prefixIcon: prefixIcon != null
          ? Padding(
              padding: EdgeInsets.only(left: compact ? 10 : 12, right: 4),
              child: Icon(
                prefixIcon,
                color: AppTheme.brandOrange,
                size: compact ? 18 : 20,
              ),
            )
          : null,
      prefixIconConstraints: BoxConstraints(
        minWidth: compact ? 36 : 44,
        minHeight: 48,
      ),
      suffixIcon: suffixIcon,
      filled: true,
      fillColor: _formFillColor,
      contentPadding: EdgeInsets.symmetric(
        horizontal: compact ? 10 : 14,
        vertical: 16,
      ),
      errorStyle: TextStyle(
        fontSize: 12,
        height: 1.3,
        color: Colors.red.shade700,
        fontWeight: FontWeight.w600,
      ),
      errorMaxLines: 2,
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(color: _formBorderColor, width: 1),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: AppTheme.brandOrange, width: 1.8),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(color: Colors.red.shade300, width: 1),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(color: Colors.red.shade400, width: 1.8),
      ),
    );
  }

  Widget _buildSectionLabel(String label, {bool required = false}) {
    final labelColor = _isDesktopGlass ? Colors.white : _textDark;
    return Text.rich(
      TextSpan(
        text: label,
        style: TextStyle(
          fontSize: 15,
          fontWeight: FontWeight.w700,
          color: labelColor,
          letterSpacing: 0.1,
          shadows: _isDesktopGlass
              ? const [
                  Shadow(
                    color: Color(0x99000000),
                    blurRadius: 4,
                    offset: Offset(0, 1),
                  ),
                ]
              : null,
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

  Widget _buildSignupIntro() {
    if (_isDesktopGlass) {
      final bodyStyle = TextStyle(
        fontSize: 14,
        color: Colors.white,
        height: 1.45,
        fontWeight: FontWeight.w600,
      );
      return RichText(
        textAlign: TextAlign.center,
        text: TextSpan(
          style: bodyStyle,
          children: [
            const TextSpan(
              text:
                  'Please provide accurate and valid details only to help us serve you better. If you already have an account, ',
            ),
            WidgetSpan(
              alignment: PlaceholderAlignment.baseline,
              baseline: TextBaseline.alphabetic,
              child: GestureDetector(
                onTap: () => Navigator.pushReplacementNamed(context, '/login'),
                child: const Text(
                  'Log in',
                  style: TextStyle(
                    color: AppTheme.brandOrange,
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                    decoration: TextDecoration.underline,
                    decorationColor: AppTheme.brandOrange,
                  ),
                ),
              ),
            ),
            const TextSpan(text: ' instead.'),
          ],
        ),
      );
    }

    return _buildStepInfoBanner();
  }

  Widget _buildStepInfoBanner() {
    // Per-step peach info banners (mock).
    switch (_personalDetailsSubStep) {
      case 0:
        return TouristSignupInfoBanner(
          icon: Icons.privacy_tip_outlined,
          child: Text(
            'Please review Data Privacy and Terms before continuing. Required for a secure tourist account.',
            style: TextStyle(
              fontSize: 12.5,
              height: 1.4,
              fontWeight: FontWeight.w500,
              color: TouristSignupChrome.textDark.withValues(alpha: 0.85),
            ),
          ),
        );
      case 2:
        return TouristSignupInfoBanner(
          icon: Icons.info_outline_rounded,
          child: Text(
            'Tell us more about yourself. This helps us personalize your experience.',
            style: TextStyle(
              fontSize: 12.5,
              height: 1.4,
              fontWeight: FontWeight.w500,
              color: TouristSignupChrome.textDark.withValues(alpha: 0.85),
            ),
          ),
        );
      case 3:
      case 4:
        return TouristSignupInfoBanner(
          icon: Icons.badge_outlined,
          child: Text(
            'How can we reach you? This information keeps your account secure.',
            style: TextStyle(
              fontSize: 12.5,
              height: 1.4,
              fontWeight: FontWeight.w500,
              color: TouristSignupChrome.textDark.withValues(alpha: 0.85),
            ),
          ),
        );
      default:
        return TouristSignupInfoBanner(
          icon: Icons.person_rounded,
          child: RichText(
            text: TextSpan(
              style: TextStyle(
                fontSize: 12.5,
                height: 1.4,
                fontWeight: FontWeight.w500,
                color: TouristSignupChrome.textDark.withValues(alpha: 0.85),
              ),
              children: [
                const TextSpan(
                  text:
                      'Please provide accurate and valid details only to help us serve you better. If you already have an account, ',
                ),
                WidgetSpan(
                  alignment: PlaceholderAlignment.baseline,
                  baseline: TextBaseline.alphabetic,
                  child: GestureDetector(
                    onTap: () =>
                        Navigator.pushReplacementNamed(context, '/login'),
                    child: const Text(
                      'Log in',
                      style: TextStyle(
                        color: TouristSignupChrome.heroOrange,
                        fontWeight: FontWeight.w700,
                        fontSize: 12.5,
                        decoration: TextDecoration.underline,
                        decorationColor: TouristSignupChrome.heroOrange,
                      ),
                    ),
                  ),
                ),
                const TextSpan(text: ' instead.'),
              ],
            ),
          ),
        );
    }
  }

  BoxDecoration _signupFormCardDecoration() {
    if (_isDesktopGlass) {
      return BoxDecoration(
        color: Colors.black.withValues(alpha: 0.28),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withValues(alpha: 0.28)),
      );
    }
    return BoxDecoration(
      color: _cardWhite,
      borderRadius: BorderRadius.circular(20),
      boxShadow: [
        BoxShadow(
          color: Colors.black.withValues(alpha: 0.10),
          blurRadius: 28,
          offset: const Offset(0, 12),
        ),
      ],
    );
  }

  bool get _isDesktopGlass =>
      MediaQuery.sizeOf(context).width >= kWebGlassAuthBreakpoint;

  Color get _fieldTextColor =>
      _isDesktopGlass ? Colors.white : _textDark;

  Color get _helperTextColor =>
      _isDesktopGlass ? Colors.white.withValues(alpha: 0.82) : _textMuted;

  Color _legalSurface(Color lightSurface) =>
      _isDesktopGlass ? Colors.black.withValues(alpha: 0.52) : lightSurface;

  Color get _legalTitleColor => _isDesktopGlass ? Colors.white : _textDark;

  Color get _legalBodyColor =>
      _isDesktopGlass ? Colors.white.withValues(alpha: 0.94) : _textDark;

  Color get _legalMutedColor =>
      _isDesktopGlass ? Colors.white.withValues(alpha: 0.82) : _textMuted;

  Color _legalAgreementFill({required bool agreed}) {
    if (!_isDesktopGlass) {
      return agreed
          ? AppTheme.brandOrange.withValues(alpha: 0.07)
          : _cardWhite;
    }
    return agreed
        ? AppTheme.brandOrange.withValues(alpha: 0.3)
        : Colors.black.withValues(alpha: 0.44);
  }

  /// Opaque enough that white value text stays readable over light panels.
  Color get _formFillColor => _isDesktopGlass
      ? Colors.black.withValues(alpha: 0.58)
      : _inputFill;

  Color get _formBorderColor =>
      _isDesktopGlass ? Colors.white.withValues(alpha: 0.45) : _inputBorder;

  /// Light-mode placeholder grey (matches signup UX reference).
  static const Color _fieldHintColorLight = Color(0xFF9CA3AF);

  /// Placeholders: muted grey on light fills; near-white on dark glass fills.
  TextStyle get _fieldHintTextStyle => TextStyle(
        color: _isDesktopGlass
            ? Colors.white.withValues(alpha: 0.88)
            : _fieldHintColorLight,
        fontSize: 15,
        fontWeight: FontWeight.w400,
        letterSpacing: 0.1,
        height: 1.25,
      );

  TextStyle get _formValueTextStyle => TextStyle(
        color: _isDesktopGlass ? Colors.white : _textDark,
        fontSize: 16,
        fontWeight: FontWeight.w600,
      );

  Widget _dropdownHint(String text, {double fontSize = 15}) {
    return Text(
      text,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: _fieldHintTextStyle.copyWith(fontSize: fontSize),
    );
  }

  TextStyle _dropdownMenuTextStyle({double fontSize = 16}) => TextStyle(
        color: _textDark,
        fontSize: fontSize,
        fontWeight: FontWeight.w500,
      );

  Widget _dropdownMenuText(
    String text, {
    double fontSize = 16,
    int? maxLines,
    TextOverflow? overflow,
  }) {
    return Text(
      text,
      maxLines: maxLines,
      overflow: overflow,
      style: _dropdownMenuTextStyle(fontSize: fontSize),
    );
  }

  Widget _dropdownSelectedText(
    String text, {
    double fontSize = 16,
    int? maxLines,
    TextOverflow? overflow,
  }) {
    return Text(
      text,
      maxLines: maxLines,
      overflow: overflow,
      style: _formValueTextStyle.copyWith(fontSize: fontSize),
    );
  }

  List<DropdownMenuItem<String>> _stringDropdownItems(
    Iterable<String> values, {
    double fontSize = 16,
  }) {
    return values
        .map(
          (value) => DropdownMenuItem<String>(
            value: value,
            child: _dropdownMenuText(
              value,
              fontSize: fontSize,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        )
        .toList();
  }

  List<Widget> _stringSelectedLabels(
    Iterable<String> values, {
    double fontSize = 16,
  }) {
    return values
        .map(
          (value) => Align(
            alignment: Alignment.centerLeft,
            child: _dropdownSelectedText(
              value,
              fontSize: fontSize,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        )
        .toList();
  }

  List<DropdownMenuItem<int>> _intDropdownItems(
    Iterable<int> values, {
    double fontSize = 16,
  }) {
    return values
        .map(
          (value) => DropdownMenuItem<int>(
            value: value,
            child: _dropdownMenuText('$value', fontSize: fontSize),
          ),
        )
        .toList();
  }

  List<Widget> _intSelectedLabels(
    Iterable<int> values, {
    double fontSize = 16,
  }) {
    return values
        .map(
          (value) => Align(
            alignment: Alignment.centerLeft,
            child: _dropdownSelectedText('$value', fontSize: fontSize),
          ),
        )
        .toList();
  }

  BoxDecoration _compactDropdownDecoration() {
    return BoxDecoration(
      color: _formFillColor,
      borderRadius: BorderRadius.circular(8),
      border: Border.all(color: _formBorderColor),
    );
  }

  Widget _buildSignupFormBody({required EdgeInsets formPadding}) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (_isDesktopGlass) ...[
          TouristSignupProgressTracker(
            visualStepIndex: _visualStepIndex,
            onDark: true,
          ),
          const SizedBox(height: 16),
          _buildSignupIntro(),
          const SizedBox(height: 20),
        ],
        Container(
          width: double.infinity,
          decoration: _signupFormCardDecoration(),
          child: Padding(
            padding: formPadding,
            child: Form(
              key: _formKey,
              child: AutofillGroup(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (!_isDesktopGlass) ...[
                      _buildSignupIntro(),
                      const SizedBox(height: 18),
                    ],
                    _isDesktopGlass
                        ? Theme(
                            data: Theme.of(context).copyWith(
                              canvasColor: Colors.white,
                              dropdownMenuTheme: DropdownMenuThemeData(
                                textStyle: _dropdownMenuTextStyle(),
                              ),
                            ),
                            child: _buildCurrentStep(),
                          )
                        : _buildCurrentStep(),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isDesktopGlass) {
      return Scaffold(
        backgroundColor: Colors.transparent,
        body: WebGlassAuthScaffold(
          maxWidth: 560,
          child: WebGlassAuthCard(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(28, 24, 28, 32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Align(
                    alignment: Alignment.centerLeft,
                    child: WebGlassBackButton(
                      onPressed: () => Navigator.pop(context),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Expanded(
                        child: TouristSignupBrandRow(onDark: true),
                      ),
                      const SizedBox(width: 8),
                      Flexible(
                        child: TouristSignupScriptSlogan(
                          text: _stepSlogan,
                          color: Colors.white,
                          fontSize: 20,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Step $_displayStepNumber',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 26,
                      fontWeight: FontWeight.w800,
                      color: Colors.white,
                      letterSpacing: 0.3,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Registration',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.white.withValues(alpha: 0.9),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 18),
                  _buildSignupFormBody(
                    formPadding: const EdgeInsets.all(24),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    final topPad = MediaQuery.paddingOf(context).top;
    final bottomPad = MediaQuery.paddingOf(context).bottom;
    final heroH = (MediaQuery.sizeOf(context).height * 0.28).clamp(210.0, 260.0);

    return Scaffold(
      backgroundColor: Colors.white,
      body: SingleChildScrollView(
        physics: const BouncingScrollPhysics(),
        padding: EdgeInsets.only(bottom: bottomPad + 8),
        child: Column(
          children: [
            SizedBox(
              height: heroH,
              width: double.infinity,
              child: ClipPath(
                clipper: const TouristSignupHeroWaveClipper(),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    const ColoredBox(color: TouristSignupChrome.heroOrange),
                    Align(
                      alignment: Alignment.centerRight,
                      child: FractionallySizedBox(
                        widthFactor: 0.72,
                        heightFactor: 1,
                        child: Image.asset(
                          TouristSignupChrome.heroAsset,
                          fit: BoxFit.cover,
                          alignment: const Alignment(0.2, 0),
                          errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                        ),
                      ),
                    ),
                    DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.centerLeft,
                          end: Alignment.centerRight,
                          colors: [
                            TouristSignupChrome.heroOrange,
                            TouristSignupChrome.heroOrange.withValues(
                              alpha: 0.94,
                            ),
                            TouristSignupChrome.heroOrange.withValues(
                              alpha: 0.55,
                            ),
                          ],
                          stops: const [0.0, 0.45, 1.0],
                        ),
                      ),
                    ),
                    Padding(
                      padding: EdgeInsets.fromLTRB(16, topPad + 4, 16, 40),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              IconButton(
                                icon: const Icon(
                                  Icons.arrow_back_ios_new_rounded,
                                  color: Colors.white,
                                  size: 18,
                                ),
                                onPressed: () => Navigator.pop(context),
                                tooltip: 'Back',
                                padding: EdgeInsets.zero,
                                constraints: const BoxConstraints(
                                  minWidth: 36,
                                  minHeight: 36,
                                ),
                              ),
                              const SizedBox(width: 4),
                              const Expanded(
                                child: TouristSignupBrandRow(onDark: true),
                              ),
                              const SizedBox(width: 6),
                              Flexible(
                                child: Padding(
                                  padding: const EdgeInsets.only(top: 4),
                                  child: TouristSignupScriptSlogan(
                                    text: _stepSlogan,
                                    color: Colors.white,
                                    fontSize: 20,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const Spacer(),
                          Text(
                            'Step $_displayStepNumber',
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              fontSize: 28,
                              fontWeight: FontWeight.w800,
                              color: Colors.white,
                              letterSpacing: 0.2,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'Registration',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 14,
                              color: Colors.white.withValues(alpha: 0.92),
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Transform.translate(
              offset: const Offset(0, -28),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 18),
                child: Column(
                  children: [
                    TouristSignupProgressTracker(
                      visualStepIndex: _visualStepIndex,
                    ),
                    const SizedBox(height: 16),
                    _buildSignupFormBody(
                      formPadding: const EdgeInsets.fromLTRB(18, 18, 18, 16),
                    ),
                  ],
                ),
              ),
            ),
            const TouristSignupFooterMotif(),
          ],
        ),
      ),
    );
  }

  Widget _buildCurrentStep() {
    return _buildPersonalDetailsStep();
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
          'Review how ATMOS-TRS handles your information, then agree to continue.',
          Icons.verified_user_outlined,
        ),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            gradient: LinearGradient(
              colors: _isDesktopGlass
                  ? [
                      Colors.black.withValues(alpha: 0.55),
                      AppTheme.brandOrange.withValues(alpha: 0.35),
                    ]
                  : [
                      AppTheme.brandOrange.withValues(alpha: 0.14),
                      privacyBlue.withValues(alpha: 0.08),
                    ],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            border: Border.all(
              color: _isDesktopGlass
                  ? Colors.white.withValues(alpha: 0.22)
                  : AppTheme.brandOrange.withValues(alpha: 0.2),
            ),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: _isDesktopGlass
                      ? Colors.white.withValues(alpha: 0.14)
                      : Colors.white.withValues(alpha: 0.9),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.lock_outline_rounded,
                  color: _isDesktopGlass ? Colors.white : AppTheme.brandOrange,
                  size: 26,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Your privacy matters',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        color: _legalTitleColor,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'ATMOS-TRS follows RA 10173 and provincial tourism policies. '
                      'Please review both sections before registering.',
                      style: TextStyle(
                        fontSize: 13,
                        color: _legalBodyColor,
                        height: 1.45,
                        fontWeight: FontWeight.w500,
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
              style: TextStyle(fontWeight: FontWeight.w600),
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
            'ATMOS-TRS is for lawful tourism registration and check-in only, '
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
    return TouristSignupSectionHeader(
      title: title,
      description: description,
      icon: icon,
      onDark: _isDesktopGlass,
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
            style: _formValueTextStyle,
            decoration: _inputDecoration(
              hint: 'enter your name',
              prefixIcon: Icons.person_outline_rounded,
            ),
            validator: (v) => _requiredField(v, 'First name'),
            textCapitalization: TextCapitalization.words,
            inputFormatters: [_CapitalizeWordsFormatter()],
          ),
        ),

        _buildFormField(
          label: 'Middle Initial',
          child: TextFormField(
            controller: _middleNameController,
            textInputAction: TextInputAction.next,
            onFieldSubmitted: (_) => _focusNextFormField(),
            onEditingComplete: _focusNextFormField,
            style: _formValueTextStyle,
            decoration: _inputDecoration(
              hint: 'enter your middle initial',
              prefixIcon: Icons.badge_outlined,
            ),
            textCapitalization: TextCapitalization.characters,
            inputFormatters: [
              LengthLimitingTextInputFormatter(1),
              _MiddleInitialFormatter(),
            ],
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
            style: _formValueTextStyle,
            decoration: _inputDecoration(
              hint: 'enter your last name',
              prefixIcon: Icons.person_outline_rounded,
            ),
            validator: (v) => _requiredField(v, 'Last name'),
            textCapitalization: TextCapitalization.words,
            inputFormatters: [_CapitalizeWordsFormatter()],
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
            style: _formValueTextStyle,
            selectedItemBuilder: (context) =>
                _stringSelectedLabels(_suffixes),
            hint: _dropdownHint('e.g. Jr., Sr., III'),
            decoration: _inputDecoration(
              hint: 'e.g. Jr., Sr., III',
              prefixIcon: Icons.label_outline_rounded,
            ),
            items: _stringDropdownItems(_suffixes),
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
            style: _formValueTextStyle,
            selectedItemBuilder: (context) =>
                _stringSelectedLabels(_sexOptions),
            hint: _dropdownHint('Select your sex'),
            decoration: _inputDecoration(
              hint: 'Select your sex',
              prefixIcon: Icons.wc_outlined,
            ),
            items: _stringDropdownItems(_sexOptions),
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
            style: _formValueTextStyle,
            selectedItemBuilder: (context) =>
                _stringSelectedLabels(_nationalities),
            hint: _dropdownHint('Select nationality'),
            decoration: _inputDecoration(
              hint: 'Select nationality',
              prefixIcon: Icons.flag_outlined,
            ),
            items: _stringDropdownItems(_nationalities),
            validator: (v) => v == null ? 'Required' : null,
            onChanged: _onNationalityChanged,
          ),
        ),
        if (_selectedNationality != null &&
            !_maySelectPhilippines &&
            !_countryLockedByNationality) ...[
          const SizedBox(height: 8),
          Text(
            'Foreign nationals: select your home country below. Philippines is '
            'not available — use City and State/Province/Region.',
            style: TextStyle(fontSize: 14, color: _helperTextColor, height: 1.45),
          ),
        ],
        if (_isDualCitizenNationality) ...[
          const SizedBox(height: 8),
          Text(
            'Dual citizens: choose Philippines if you live here (province, city, '
            'barangay), or your other home country for an international address.',
            style: TextStyle(fontSize: 14, color: _helperTextColor, height: 1.45),
          ),
        ],
        const SizedBox(height: 16),

        _buildSectionLabel('Date of Birth', required: true),
        Row(
          children: [
            Expanded(
              child: Container(
                height: 48,
                decoration: _compactDropdownDecoration(),
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<int>(
                    value: _selectedMonth,
                    isExpanded: true,
                    dropdownColor: Colors.white,
                    icon: const SizedBox.shrink(),
                    iconSize: 0,
                    hint: _dropdownHint('Month'),
                    style: _formValueTextStyle,
                    selectedItemBuilder: (context) => List.generate(
                      12,
                      (i) => Align(
                        alignment: Alignment.centerLeft,
                        child: _dropdownSelectedText(_months[i]),
                      ),
                    ),
                    items: List.generate(
                      12,
                      (i) => DropdownMenuItem<int>(
                        value: i + 1,
                        child: _dropdownMenuText(_months[i]),
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
                decoration: _compactDropdownDecoration(),
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<int>(
                    value: _selectedDay,
                    isExpanded: true,
                    dropdownColor: Colors.white,
                    icon: const SizedBox.shrink(),
                    iconSize: 0,
                    hint: _dropdownHint('Day'),
                    style: _formValueTextStyle,
                    selectedItemBuilder: (context) => _intSelectedLabels(
                      _getDaysInMonth(_selectedMonth, _selectedYear),
                    ),
                    items: _intDropdownItems(
                      _getDaysInMonth(_selectedMonth, _selectedYear),
                    ),
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
                decoration: _compactDropdownDecoration(),
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<int>(
                    value: _selectedYear,
                    isExpanded: true,
                    dropdownColor: Colors.white,
                    icon: const SizedBox.shrink(),
                    iconSize: 0,
                    hint: _dropdownHint('Year'),
                    style: _formValueTextStyle,
                    selectedItemBuilder: (context) =>
                        _intSelectedLabels(_getYears()),
                    items: _intDropdownItems(_getYears()),
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
        const SizedBox(height: 20),
        if (!_isDesktopGlass) ...[
          const TouristSignupExploreStrip(),
          const SizedBox(height: 12),
        ],
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
          child: DialCodeMobileField(
            controller: _mobileController,
            dialCode: _mobileDialCode,
            onDialCodeChanged: (v) => setState(() => _mobileDialCode = v),
            textStyle: _formValueTextStyle,
            dialTextStyle: _formValueTextStyle.copyWith(
              fontSize: 15,
              height: 1.2,
              fontWeight: FontWeight.w700,
            ),
            menuItemTextStyle: _dropdownMenuTextStyle(fontSize: 14),
            textInputAction: TextInputAction.next,
            onFieldSubmitted: (_) => _focusNextFormField(),
            onEditingComplete: _focusNextFormField,
            dialDecoration: _inputDecoration(
              hint: '+63',
              compact: true,
            ),
            numberDecoration: _inputDecoration(
              hint: _mobileDialCode == '+63'
                  ? '9XXXXXXXXX'
                  : 'enter your number',
              prefixIcon: Icons.phone_outlined,
            ),
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
            onChanged: _editingPendingSignup
                ? (_) {
                    setState(() {});
                  }
                : null,
            autofillHints: const [],
            autocorrect: false,
            enableSuggestions: false,
            style: _formValueTextStyle.copyWith(
              fontSize: 14,
              letterSpacing: 0,
            ),
            decoration: _inputDecoration(
              hint: 'enter your email',
              prefixIcon: Icons.email_outlined,
              compact: true,
            ),
            validator: (v) {
              if (v == null || v.isEmpty) return 'Required';
              if (!isValidEmailFormat(v)) return 'Enter valid email';
              return null;
            },
          ),
        ),
        if (_editingPendingSignup) ...[
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              _pendingEmailChanged
                  ? 'Email changed — enter your password below, then continue to get a new code.'
                  : 'You can fix your email here. Password is only needed if you change it.',
              style: TextStyle(
                fontSize: 12.5,
                height: 1.35,
                fontWeight: FontWeight.w600,
                color: _helperTextColor,
              ),
            ),
          ),
        ],
        const SizedBox(height: 16),

        _buildFormField(
          label: 'Password',
          required: !_editingPendingSignup,
          child: TextFormField(
            controller: _passwordController,
            obscureText: _obscurePassword,
            textInputAction: TextInputAction.next,
            onFieldSubmitted: (_) => _focusNextFormField(),
            onEditingComplete: _focusNextFormField,
            autofillHints: const [],
            autocorrect: false,
            enableSuggestions: false,
            style: _formValueTextStyle,
            decoration: _inputDecoration(
              hint: _editingPendingSignup
                  ? 'needed only to change email'
                  : 'enter your password',
              prefixIcon: Icons.lock_outline,
              suffixIcon: IconButton(
                icon: Icon(
                  _obscurePassword
                      ? Icons.visibility_off_outlined
                      : Icons.visibility_outlined,
                  color: _helperTextColor,
                  size: 20,
                ),
                onPressed: () =>
                    setState(() => _obscurePassword = !_obscurePassword),
              ),
            ),
            validator: (v) {
              if (_editingPendingSignup) {
                if (!_pendingEmailChanged && (v == null || v.isEmpty)) {
                  return null;
                }
                if (_pendingEmailChanged && (v == null || v.isEmpty)) {
                  return 'Required to change email';
                }
                if (v != null && v.isNotEmpty && v.length < 8) {
                  return 'Password must be at least 8 characters';
                }
                return null;
              }
              return validateTouristSignupPassword(v);
            },
          ),
        ),
        const SizedBox(height: 16),
        _buildFormField(
          label: 'Confirm Password',
          required: !_editingPendingSignup,
          child: TextFormField(
            controller: _confirmPasswordController,
            obscureText: _obscureConfirmPassword,
            textInputAction: TextInputAction.next,
            onFieldSubmitted: (_) => _focusNextFormField(),
            onEditingComplete: _focusNextFormField,
            autofillHints: const [],
            autocorrect: false,
            enableSuggestions: false,
            style: _formValueTextStyle,
            decoration: _inputDecoration(
              hint: _editingPendingSignup
                  ? 'confirm if changing email'
                  : 'confirm your password',
              prefixIcon: Icons.lock_outline,
              suffixIcon: IconButton(
                icon: Icon(
                  _obscureConfirmPassword
                      ? Icons.visibility_off_outlined
                      : Icons.visibility_outlined,
                  color: _helperTextColor,
                  size: 20,
                ),
                onPressed: () => setState(
                  () => _obscureConfirmPassword = !_obscureConfirmPassword,
                ),
              ),
            ),
            validator: (v) {
              if (_editingPendingSignup) {
                if (!_pendingEmailChanged &&
                    _passwordController.text.isEmpty &&
                    (v == null || v.isEmpty)) {
                  return null;
                }
              }
              if (v == null || v.isEmpty) {
                if (_editingPendingSignup && !_pendingEmailChanged) {
                  return null;
                }
                return 'Required';
              }
              if (v != _passwordController.text) return 'No match';
              return null;
            },
          ),
        ),
        const SizedBox(height: 24),

        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            // Peach washes out white glass field text; use a dark panel on glass.
            color: _isDesktopGlass
                ? Colors.black.withValues(alpha: 0.42)
                : TouristSignupChrome.peachBanner,
            borderRadius: BorderRadius.circular(16),
            border: _isDesktopGlass
                ? Border.all(color: Colors.white.withValues(alpha: 0.22))
                : null,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: TouristSignupChrome.heroOrange.withValues(
                        alpha: _isDesktopGlass ? 0.28 : 0.12,
                      ),
                    ),
                    child: const Icon(
                      Icons.home_outlined,
                      size: 18,
                      color: TouristSignupChrome.heroOrange,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    'Address Information',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: _fieldTextColor,
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
                        style: _formValueTextStyle,
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
                        style: _formValueTextStyle,
                        selectedItemBuilder: (context) =>
                            _stringSelectedLabels(_countriesForResidence),
                        hint: _dropdownHint(
                          _maySelectPhilippines
                              ? 'Select country'
                              : 'Select home country (not Philippines)',
                        ),
                        decoration: _inputDecoration(
                          hint: _maySelectPhilippines
                              ? 'Select country'
                              : 'Select home country (not Philippines)',
                        ),
                        items: _stringDropdownItems(_countriesForResidence),
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
                          style: _formValueTextStyle.copyWith(fontSize: 14),
                          selectedItemBuilder: (context) =>
                              _stringSelectedLabels(_provinces, fontSize: 14),
                          hint: _dropdownHint('Province', fontSize: 14),
                          decoration: _inputDecoration(hint: 'Province'),
                          items: _stringDropdownItems(_provinces, fontSize: 14),
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
                          style: _formValueTextStyle.copyWith(fontSize: 14),
                          selectedItemBuilder: (context) =>
                              _stringSelectedLabels(
                            _getCitiesForProvince(_selectedProvince),
                            fontSize: 14,
                          ),
                          hint: _dropdownHint('City', fontSize: 14),
                          decoration: _inputDecoration(hint: 'City'),
                          items: _stringDropdownItems(
                            _getCitiesForProvince(_selectedProvince),
                            fontSize: 14,
                          ),
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
                          style: _formValueTextStyle.copyWith(fontSize: 14),
                          selectedItemBuilder: (context) =>
                              _stringSelectedLabels(
                            barangaysForMisamisOccidentalCity(_selectedCity),
                            fontSize: 14,
                          ),
                          hint: _dropdownHint('Select barangay', fontSize: 14),
                          decoration: _inputDecoration(hint: 'Select barangay'),
                          items: _stringDropdownItems(
                            barangaysForMisamisOccidentalCity(_selectedCity),
                            fontSize: 14,
                          ),
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
                          style: _formValueTextStyle.copyWith(fontSize: 14),
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
                  child: CountryCityAutocompleteField(
                    key: ValueKey('city_${_selectedCountry ?? 'none'}'),
                    controller: _foreignCityController,
                    country: _selectedCountry,
                    textStyle: _formValueTextStyle,
                    textInputAction: _showForeignStateRegion
                        ? TextInputAction.next
                        : TextInputAction.done,
                    onFieldSubmitted: (_) {
                      if (!_showForeignStateRegion) {
                        _submitCurrentStepFromKeyboard();
                      }
                    },
                    onEditingComplete: _showForeignStateRegion
                        ? null
                        : _submitCurrentStepFromKeyboard,
                    decoration: _inputDecoration(
                      hint: SignupCitiesByCountry.hasCuratedList(
                            _selectedCountry,
                          )
                          ? 'Type or pick a city'
                          : 'e.g. your city',
                      prefixIcon: Icons.location_city_outlined,
                    ),
                  ),
                ),
                if (_showForeignStateRegion) ...[
                  const SizedBox(height: 12),
                  _buildFormField(
                    label: 'State / Province / Region',
                    required: true,
                    child: TextFormField(
                      controller: _foreignRegionController,
                      style: _formValueTextStyle,
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

        _buildPersonalDetailsNavButtons(
          isRegistrationSubmit: !_isMinorRegistrant(),
        ),
      ],
    );
  }

  Widget _buildFamilyTravelPartySubStep() {
    // Adults skip this step (party size asked after QR scan). Minors: guardian only.
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSubStepHeader(
          'Parent / guardian',
          'Age 12 and below: add your parent or guardian\'s name. '
              'You are still counted as 1 tourist. Party size for visits '
              'is asked when you scan a destination QR.',
          Icons.supervisor_account_outlined,
        ),
        _buildFormField(
          label: 'Parent / guardian full name',
          required: true,
          child: TextFormField(
            controller: _parentGuardianController,
            textInputAction: TextInputAction.done,
            onFieldSubmitted: (_) => _submitCurrentStepFromKeyboard(),
            onEditingComplete: _submitCurrentStepFromKeyboard,
            style: _formValueTextStyle,
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
        const SizedBox(height: 24),
        _buildPersonalDetailsNavButtons(isRegistrationSubmit: true),
      ],
    );
  }

  Widget _buildPersonalDetailsNavButtons({
    bool showBack = true,
    bool isRegistrationSubmit = false,
  }) {
    final nextStyle = FilledButton.styleFrom(
      backgroundColor: TouristSignupChrome.heroOrange,
      foregroundColor: Colors.white,
      elevation: 0,
      padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
    );

    return Column(
      children: [
        if (isRegistrationSubmit) ...[
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 24,
                height: 24,
                child: Checkbox(
                  value: _receiveUpdates,
                  onChanged: (v) =>
                      setState(() => _receiveUpdates = v ?? false),
                  activeColor: AppTheme.brandOrange,
                  checkColor: Colors.white,
                  fillColor: WidgetStateProperty.resolveWith((states) {
                    if (states.contains(WidgetState.selected)) {
                      return AppTheme.brandOrange;
                    }
                    return _isDesktopGlass
                        ? Colors.white.withValues(alpha: 0.2)
                        : null;
                  }),
                  side: BorderSide(
                    color: _isDesktopGlass
                        ? Colors.white.withValues(alpha: 0.75)
                        : _inputBorder,
                    width: 1.5,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'I would like to receive updates and promotions (optional)',
                  style: TextStyle(
                    fontSize: 14,
                    height: 1.4,
                    fontWeight: FontWeight.w600,
                    color: _isDesktopGlass
                        ? Colors.white.withValues(alpha: 0.95)
                        : _textDark,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
        ],
        const SizedBox(height: 8),
        Divider(color: _inputBorder.withValues(alpha: 0.9), height: 1),
        const SizedBox(height: 16),
        Row(
          children: [
            if (showBack)
              TextButton(
                onPressed: _previousStep,
                style: TextButton.styleFrom(
                  foregroundColor: TouristSignupChrome.textMuted,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
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
                  foregroundColor: TouristSignupChrome.textMuted,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 12,
                  ),
                ),
                child: const Text(
                  'Cancel',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                ),
              ),
            const Spacer(),
            FilledButton(
              onPressed: isRegistrationSubmit
                  ? (_isSubmitting ? null : _submitForm)
                  : _nextStep,
              style: nextStyle,
              child: isRegistrationSubmit && _isSubmitting
                  ? Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const SizedBox(
                          height: 18,
                          width: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor:
                                AlwaysStoppedAnimation<Color>(Colors.white),
                          ),
                        ),
                        if (_submitPhase != null) ...[
                          const SizedBox(width: 10),
                          Flexible(
                            child: Text(
                              _submitPhase!,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ],
                    )
                  : Text(
                      isRegistrationSubmit
                          ? (_editingPendingSignup
                              ? 'Save & continue verification'
                              : 'Submit Registration')
                          : 'Next',
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 15,
                      ),
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
                    color: _isDesktopGlass
                        ? Colors.white.withValues(alpha: 0.14)
                        : const Color(0xFFF3F4F6),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(
                      color: _isDesktopGlass
                          ? Colors.white.withValues(alpha: 0.28)
                          : _inputBorder,
                    ),
                  ),
                  child: Text(
                    'Optional',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: _isDesktopGlass ? Colors.white : _textMuted,
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

        Text(
          'Verify Your Phone Number',
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: _fieldTextColor,
          ),
        ),
        const SizedBox(height: 12),

        Text(
          _otpSent
              ? 'We sent a 6-digit code to\n$phoneNumber'
              : 'We will send a verification code to\n$phoneNumber',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 14, color: _helperTextColor, height: 1.5),
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
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: _fieldTextColor,
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
              style: TextStyle(fontSize: 14, color: _textMuted),
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
                color: _helperTextColor.withValues(alpha: 0.78),
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
              child: Text(
                'Back',
                style: TextStyle(color: _helperTextColor, fontSize: 15),
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
}

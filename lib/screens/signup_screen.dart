import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:uuid/uuid.dart';
import 'dart:async';
import 'package:atmos_trs_system/utils/email_utils.dart';
import 'package:atmos_trs_system/utils/signup_field_validation.dart';
import 'package:atmos_trs_system/utils/firebase_client_blocked_message.dart';
import 'package:atmos_trs_system/config/user_profile_storage.dart';
import 'package:atmos_trs_system/config/session_storage.dart';
import 'package:atmos_trs_system/config/auth_config.dart';
import 'package:atmos_trs_system/services/notification_firestore_service.dart';
import 'package:atmos_trs_system/services/otp_service.dart';
import 'package:atmos_trs_system/services/emailjs_service.dart';
import 'package:atmos_trs_system/models/travel_party_child.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:image/image.dart' as img;

/// Resize/compress profile photos so Storage uploads succeed and Firestore docs stay under ~1MB.
Uint8List _compressProfileJpeg(Uint8List raw) {
  try {
    final decoded = img.decodeImage(raw);
    if (decoded == null) return raw;
    var work = decoded;
    const int maxSide = 1024;
    if (work.width > maxSide || work.height > maxSide) {
      if (work.width >= work.height) {
        work = img.copyResize(work, width: maxSide);
      } else {
        work = img.copyResize(work, height: maxSide);
      }
    }
    return Uint8List.fromList(img.encodeJpg(work, quality: 82));
  } catch (e, st) {
    debugPrint('Profile image compress skipped: $e $st');
    return raw;
  }
}

class SignupScreen extends StatefulWidget {
  const SignupScreen({super.key});

  @override
  State<SignupScreen> createState() => _SignupScreenState();
}

class _SignupScreenState extends State<SignupScreen> {
  final _formKey = GlobalKey<FormState>();
  int _currentStep = 0;
  int _personalDetailsSubStep =
      0; // 0: Basic Info, 1: Personal Info, 2: Contact & Address

  // Personal Details Controllers
  final _firstNameController = TextEditingController();
  final _middleNameController = TextEditingController();
  final _lastNameController = TextEditingController();
  final _mobileController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  final _streetController = TextEditingController();
  final _barangayController = TextEditingController();

  // Travel History Controllers
  final _firstDestinationController = TextEditingController();
  final _secondDestinationController = TextEditingController();
  final _thirdDestinationController = TextEditingController();
  final _howHeardController = TextEditingController();
  String? _selectedTransportation;

  // Dropdown values
  String? _selectedSuffix;
  String? _selectedSex;
  String? _selectedCivilStatus;
  String? _selectedNationality;
  String? _selectedLocalOrForeign;
  DateTime? _selectedDateOfBirth;
  int? _selectedDay;
  int? _selectedMonth;
  int? _selectedYear;
  String? _selectedCountry;
  String? _selectedProvince;
  String? _selectedCity;

  bool _obscurePassword = true;
  bool _obscureConfirmPassword = true;

  // Upload step variables
  bool _receiveUpdates = false;
  bool _agreeToTerms = false;
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

  /// Parent/guardian full name — required when registrant is under 18.
  final _parentGuardianController = TextEditingController();
  final List<TravelPartyChildRowControllers> _travelPartyChildren = [];

  // Theme colors - Orange palette
  static const Color _primaryOrange = Color(0xFFF97316); // orange-500
  static const Color _backgroundWhite = Color(0xFFFFF7ED); // orange-50
  static const Color _cardWhite = Colors.white;
  static const Color _textDark = Color(0xFF1F2937);
  static const Color _textMuted = Color(0xFF6B7280);
  static const Color _inputBorder = Color(0xFFE5E7EB);
  static const Color _inputFill = Color(0xFFFFFBEB); // warm tint
  static const Color _accentOrange = Color(0xFFFB923C); // orange-400

  final List<String> _suffixes = ['None', 'Jr.', 'Sr.', 'II', 'III', 'IV', 'V'];
  final List<String> _sexOptions = ['Male', 'Female'];
  final List<String> _civilStatusOptions = [
    'Single',
    'Married',
    'Divorced',
    'Widowed',
  ];
  final List<String> _nationalities = [
    'Filipino',
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
    _streetController.dispose();
    _barangayController.dispose();
    _firstDestinationController.dispose();
    _secondDestinationController.dispose();
    _thirdDestinationController.dispose();
    _howHeardController.dispose();
    _parentGuardianController.dispose();
    for (final row in _travelPartyChildren) {
      row.dispose();
    }
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

  /// Rows with non-empty child name (used for party count and Firestore).
  List<TravelPartyChildRowControllers> _filledTravelPartyRows() {
    return _travelPartyChildren
        .where((r) => r.nameController.text.trim().isNotEmpty)
        .toList();
  }

  String? _validateTravelParty() {
    for (final r in _travelPartyChildren) {
      final name = r.nameController.text.trim();
      final ageText = r.ageController.text.trim();
      if (name.isEmpty &&
          ageText.isEmpty &&
          (r.gender == null || r.gender!.isEmpty)) {
        continue;
      }
      if (name.isEmpty) {
        return 'Enter each child\'s full name or clear empty rows.';
      }
      final a = int.tryParse(ageText);
      if (a == null || a < 0 || a > 120) {
        return 'Enter a valid age for $name.';
      }
      if (r.gender == null || r.gender!.isEmpty) {
        return 'Select gender for $name.';
      }
    }

    final age = _ageInYears();
    final filled = _filledTravelPartyRows();
    if (age != null && age < 18) {
      if (_parentGuardianController.text.trim().isEmpty) {
        return 'Please enter parent or guardian full name.';
      }
      if (filled.isEmpty) {
        return 'Add all minors traveling with you (name, age, gender).';
      }
    }
    return null;
  }

  void _prefillMinorTravelParty() {
    final age = _ageInYears();
    if (age == null || age >= 18) return;
    if (_travelPartyChildren.isNotEmpty) return;
    final row = TravelPartyChildRowControllers();
    final fn = _firstNameController.text.trim();
    final ln = _lastNameController.text.trim();
    row.nameController.text = '$fn $ln'.trim();
    row.ageController.text = '$age';
    row.gender = _selectedSex;
    _travelPartyChildren.add(row);
  }

  void _addTravelPartyChildRow() {
    setState(() {
      _travelPartyChildren.add(TravelPartyChildRowControllers());
    });
  }

  void _removeTravelPartyChildRow(int index) {
    setState(() {
      final removed = _travelPartyChildren.removeAt(index);
      removed.dispose();
    });
  }

  int _computePartyHeadcount() {
    return 1 + _filledTravelPartyRows().length;
  }

  void _nextStep() {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    if (_currentStep == 0) {
      if (_personalDetailsSubStep == 1) {
        if (_selectedDay == null ||
            _selectedMonth == null ||
            _selectedYear == null) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text(
                'Please select your complete Date of Birth',
              ),
              backgroundColor: Colors.red.shade700,
              behavior: SnackBarBehavior.floating,
            ),
          );
          return;
        }
      }
      if (_personalDetailsSubStep == 3) {
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
      if (_personalDetailsSubStep < 3) {
        setState(() {
          _personalDetailsSubStep++;
          if (_personalDetailsSubStep == 3) {
            _prefillMinorTravelParty();
          }
        });
        return;
      }
    }
    setState(() => _currentStep++);
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
    if (_uploadedImageBytes == null || _uploadedImageBytes!.isEmpty) {
      return 'Please upload a close-up photo of your face.';
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

  Future<void> _deleteAuthUserBestEffort() async {
    try {
      await FirebaseAuth.instance.currentUser?.delete();
    } catch (e) {
      debugPrint('[REG] deleteAuthUserBestEffort: $e');
    }
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
    if (s == 'Error' || s == 'Instance of \'Error\'' || s == 'Instance of "Error"') {
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

    final email = normalizeEmail(_emailController.text);
    final password = _passwordController.text;

    UserCredential? userCredential;
    String? uid;

    // --- STEP 1: Firebase Auth only ---
    try {
      debugPrint('[REG] STEP 1: createUserWithEmailAndPassword');
      try {
        await FirebaseAuth.instance.signOut();
      } catch (_) {}
      userCredential = await FirebaseAuth.instance
          .createUserWithEmailAndPassword(email: email, password: password);
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
        await userCredential.user?.getIdToken(true);
      } catch (e) {
        debugPrint('[REG] STEP 1 getIdToken (non-fatal): $e');
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

    // --- STEP 2: Firebase Storage (web uses putData(Uint8List), not putFile) ---
    String? profilePhotoUrl;

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

    try {
      debugPrint(
        '[REG] STEP 2: Storage.putData (bytes) — Flutter Web compatible; do not use putFile here',
      );
      final storage = FirebaseStorage.instance;
      final storageRef = storage.ref().child('profile_photos/$uid.jpg');
      final uploadTask = await storageRef.putData(
        compressedPhoto,
        SettableMetadata(contentType: 'image/jpeg'),
      );
      profilePhotoUrl = await uploadTask.ref.getDownloadURL();
      debugPrint('[REG] STEP 2 OK: url=$profilePhotoUrl');
    } on FirebaseException catch (e, st) {
      debugPrint(
        '[REG] STEP 2 FAIL: plugin=${e.plugin} code=${e.code} message=${e.message}\n$st',
      );
      await _deleteAuthUserBestEffort();
      _setSubmitting(false);
      _registrationSnack(
        'Storage upload failed — ${_formatFirebaseException(e)}',
        background: Colors.red.shade700,
      );
      return;
    } catch (e, st) {
      debugPrint('[REG] STEP 2 FAIL (non-Firebase): $e\n$st');
      await _deleteAuthUserBestEffort();
      _setSubmitting(false);
      _registrationSnack(
        'Storage upload failed — ${_formatRegistrationError(e)}',
        background: Colors.red.shade700,
      );
      return;
    }

    // --- Prepare name + tourist id (needed for Firestore) ---
    const uuid = Uuid();
    final touristId = 'ATMOS-${uuid.v4().substring(0, 8).toUpperCase()}';

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
    final isMinorAccount = ageYears != null && ageYears < 18;
    final travelPartyMaps = _filledTravelPartyRows()
        .map(
          (r) => <String, dynamic>{
            'name': r.nameController.text.trim(),
            'age': int.tryParse(r.ageController.text.trim()) ?? 0,
            'gender': r.gender ?? '',
          },
        )
        .toList();
    final partyHeadcount = _computePartyHeadcount();

    // --- STEP 3: Firestore (tourists + users) ---
    try {
      debugPrint('[REG] STEP 3: Firestore tourists + users');
      final firestore = FirebaseFirestore.instance;

      await firestore.collection('tourists').doc(uid).set({
        'touristId': touristId,
        'firebaseUid': uid,
        'firstName': _firstNameController.text.trim(),
        'middleName': _middleNameController.text.trim(),
        'lastName': _lastNameController.text.trim(),
        'fullName': fullName,
        'suffix': _selectedSuffix,
        'sex': _selectedSex,
        'civilStatus': _selectedCivilStatus,
        'nationality': _selectedNationality,
        'dateOfBirth': dobString,
        'mobile': _mobileController.text.trim(),
        'email': email,
        'country': _selectedCountry,
        'province': _selectedProvince,
        'city': _selectedCity,
        'street': _streetController.text.trim(),
        'barangay': _barangayController.text.trim(),
        'profilePhotoUrl': profilePhotoUrl,
        'profilePhotoPending': false,
        'isLocal': _selectedLocalOrForeign == 'Local',
        'localOrForeign': _selectedLocalOrForeign,
        'transportation': _selectedTransportation,
        'travelHistory': {
          'firstDestination': _firstDestinationController.text.trim(),
          'secondDestination': _secondDestinationController.text.trim(),
          'thirdDestination': _thirdDestinationController.text.trim(),
          'howHeardAbout': _howHeardController.text.trim(),
        },
        'receiveUpdates': _receiveUpdates,
        'registeredAt': FieldValue.serverTimestamp(),
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
        'travelPartyChildren': travelPartyMaps,
        'partyHeadcount': partyHeadcount,
      });

      await firestore.collection('users').doc(uid).set({
        'firebaseUid': uid,
        'email': email,
        'fullName': fullName,
        'role': 'tourist',
        'municipality': '',
        'isVerified': false,
        'createdAt': FieldValue.serverTimestamp(),
      });
      debugPrint('[REG] STEP 3 OK');
    } on FirebaseException catch (e, st) {
      debugPrint(
        '[REG] STEP 3 FAIL: plugin=${e.plugin} code=${e.code} message=${e.message}\n$st',
      );
      if (e.code == 'permission-denied') {
        await _deleteAuthUserBestEffort();
      }
      _setSubmitting(false);
      _registrationSnack(
        'Firestore save failed — ${_formatFirebaseException(e)}',
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
        civilStatus: _selectedCivilStatus,
        nationality: _selectedNationality,
        dateOfBirth: dobString,
        mobile: _mobileController.text.trim(),
        email: email,
        country: _selectedCountry,
        province: _selectedProvince,
        city: _selectedCity,
        street: _streetController.text.trim(),
        barangay: _barangayController.text.trim(),
        touristId: touristId,
        profileImageBase64: null,
        profilePhotoUrl: profilePhotoUrl,
      );
    } catch (e, st) {
      debugPrint('[REG] Local prefs (non-fatal): $e\n$st');
    }

    // --- STEP 4: OTP doc in Firestore (test this alone: watch for [REG] STEP 4 FAIL) ---
    final otp = OtpService.generateSixDigitOtp();
    try {
      debugPrint('[REG] STEP 4: email_otps save');
      await OtpService.saveOtp(uid: uid, email: email, otp: otp);
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

    // --- STEP 5: EmailJS (must return null for “email sent” success messaging) ---
    debugPrint('[REG] STEP 5: EmailJS send (after OTP saved in Firestore)');
    final emailErr = await EmailjsService.sendOtpEmail(
      toEmail: email,
      toName: fullName,
      otp: otp,
    );

    AuthConfig.currentUserUid = uid;
    try {
      await SessionStorage.saveSession(
        uid,
        role: UserRole.tourist,
        email: email,
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
      if (emailErr != null) {
        debugPrint('[REG] STEP 5 FAIL: $emailErr');
        _registrationSnack(
          'Account created and OTP saved, but email was not sent: $emailErr '
          'Use Resend on the next screen after fixing EmailJS config.',
          background: Colors.orange.shade800,
        );
      } else {
        debugPrint('[REG] STEP 5 OK: EmailJS accepted the send');
        _registrationSnack(
          'Verification code sent to your email. Check inbox and spam.',
          background: Colors.green.shade700,
        );
      }
      Navigator.pushReplacementNamed(context, '/verify-otp');
    }
    debugPrint('[REG] ========== registration end ==========');
  }

  Future<void> _pickImage(ImageSource source) async {
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
      hintStyle: TextStyle(color: _textMuted.withOpacity(0.6), fontSize: 14),
      prefixIcon: prefixIcon != null
          ? Icon(prefixIcon, color: _textMuted, size: 20)
          : null,
      suffixIcon: suffixIcon,
      filled: true,
      fillColor: _inputFill,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: _inputBorder, width: 1),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: _primaryOrange, width: 2),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: BorderSide(color: Colors.red.shade300),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: BorderSide(color: Colors.red.shade400, width: 2),
      ),
    );
  }

  Widget _buildSectionLabel(String label, {bool required = false}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text.rich(
        TextSpan(
          text: label,
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w500,
            color: _textDark,
          ),
          children: required
              ? [
                  const TextSpan(
                    text: ' *',
                    style: TextStyle(color: Colors.red),
                  ),
                ]
              : [],
        ),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }

  bool get _isWeb =>
      kIsWeb && MediaQuery.sizeOf(context).width >= 768;

  @override
  Widget build(BuildContext context) {
    const double cardRadius = 24.0;

    final headerSection = Stack(
      children: [
        Container(
          width: double.infinity,
          height: 200,
          decoration: BoxDecoration(
            color: _primaryOrange,
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
                        child: const Icon(
                          Icons.arrow_back,
                          color: Colors.white,
                          size: 20,
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
              padding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 16,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _buildStepProgressIndicator(),
                  const SizedBox(height: 24),
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
                            child: const Text(
                              'LOG IN',
                              style: TextStyle(
                                color: _accentOrange,
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
                    decoration: BoxDecoration(
                      color: _cardWhite,
                      borderRadius: BorderRadius.circular(_isWeb ? 20 : 12),
                      border: _isWeb
                          ? Border.all(
                              color: _primaryOrange.withOpacity(0.12),
                              width: 1,
                            )
                          : null,
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(_isWeb ? 0.06 : 0.05),
                          blurRadius: _isWeb ? 20 : 10,
                          offset: const Offset(0, 2),
                        ),
                        if (_isWeb)
                          BoxShadow(
                            color: _primaryOrange.withOpacity(0.06),
                            blurRadius: 24,
                            offset: const Offset(0, 6),
                          ),
                      ],
                    ),
                    child: Padding(
                      padding: EdgeInsets.all(_isWeb ? 20 : 24),
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
              // Step progress indicator
              _buildStepProgressIndicator(),
              const SizedBox(height: 24),

              // Description text
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
                        child: const Text(
                          'LOG IN',
                          style: TextStyle(
                            color: _accentOrange,
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

              // Form container
              Container(
                width: double.infinity,
                decoration: BoxDecoration(
                  color: _cardWhite,
                  borderRadius: BorderRadius.circular(_isWeb ? 20 : 12),
                  border: _isWeb
                      ? Border.all(
                          color: _primaryOrange.withOpacity(0.12),
                          width: 1,
                        )
                      : null,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(_isWeb ? 0.06 : 0.05),
                      blurRadius: _isWeb ? 20 : 10,
                      offset: const Offset(0, 2),
                    ),
                    if (_isWeb)
                      BoxShadow(
                        color: _primaryOrange.withOpacity(0.06),
                        blurRadius: 24,
                        offset: const Offset(0, 6),
                      ),
                  ],
                ),
                child: Padding(
                  padding: EdgeInsets.all(_isWeb ? 20 : 24),
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
      children: [
        headerSection,
        contentSection,
      ],
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
                  color: _primaryOrange.withOpacity(0.06),
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
                    'assets/images/Orquieta Plaza.png',
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => Image.network(
                      'https://images.unsplash.com/photo-1488646953014-85cb44e25828?w=1200',
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => Container(
                        color: _primaryOrange.withOpacity(0.9),
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
    final steps = [
      'Personal Details',
      'Travel History',
      'Uploads',
    ];
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
                        color: isCompleted ? _primaryOrange : _inputBorder,
                      ),
                    ),
                  Flexible(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 32,
                          height: 32,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: isCompleted || isCurrent
                                ? _primaryOrange
                                : _inputFill,
                            border: Border.all(
                              color: isCompleted || isCurrent
                                  ? _primaryOrange
                                  : _inputBorder,
                              width: 2,
                            ),
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
                            color: isCurrent ? _primaryOrange : _textMuted,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (index < 2)
                    Expanded(
                      child: Container(
                        height: 2,
                        color: isCompleted ? _primaryOrange : _inputBorder,
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
        return _buildBasicInfoSubStep();
      case 1:
        return _buildPersonalInfoSubStep();
      case 2:
        return _buildContactAddressSubStep();
      case 3:
        return _buildFamilyTravelPartySubStep();
      default:
        return _buildBasicInfoSubStep();
    }
  }

  Widget _buildSubStepHeader(String title, String description, IconData icon) {
    return Column(
      children: [
        Container(
          width: 56,
          height: 56,
          decoration: BoxDecoration(
            color: _primaryOrange.withOpacity(0.1),
            shape: BoxShape.circle,
          ),
          child: Icon(icon, size: 28, color: _primaryOrange),
        ),
        const SizedBox(height: 16),
        Text(
          title,
          style: const TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: _textDark,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          description,
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 13, color: _textMuted),
        ),
        const SizedBox(height: 24),
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
            style: const TextStyle(color: _textDark, fontSize: 14),
            decoration: _inputDecoration(
              hint: 'e.g. Juan',
              prefixIcon: Icons.badge_outlined,
            ),
            validator: (v) => v == null || v.isEmpty ? 'Required' : null,
            textCapitalization: TextCapitalization.words,
          ),
        ),
        const SizedBox(height: 16),

        _buildFormField(
          label: 'Middle Name',
          child: TextFormField(
            controller: _middleNameController,
            style: const TextStyle(color: _textDark, fontSize: 14),
            decoration: _inputDecoration(
              hint: 'e.g. Dela (Optional)',
              prefixIcon: Icons.badge_outlined,
            ),
            textCapitalization: TextCapitalization.words,
          ),
        ),
        const SizedBox(height: 16),

        _buildFormField(
          label: 'Last Name',
          required: true,
          child: TextFormField(
            controller: _lastNameController,
            style: const TextStyle(color: _textDark, fontSize: 14),
            decoration: _inputDecoration(
              hint: 'e.g. Cruz',
              prefixIcon: Icons.badge_outlined,
            ),
            validator: (v) => v == null || v.isEmpty ? 'Required' : null,
            textCapitalization: TextCapitalization.words,
          ),
        ),
        const SizedBox(height: 16),

        _buildFormField(
          label: 'Suffix',
          child: DropdownButtonFormField<String>(
            value: _selectedSuffix,
            dropdownColor: Colors.white,
            style: const TextStyle(color: _textDark, fontSize: 14),
            decoration: _inputDecoration(
              hint: 'e.g. Jr., Sr., III (Optional)',
              prefixIcon: Icons.more_horiz,
            ),
            items: _suffixes
                .map((s) => DropdownMenuItem(value: s, child: Text(s)))
                .toList(),
            onChanged: (v) => setState(() => _selectedSuffix = v),
          ),
        ),
        const SizedBox(height: 32),

        _buildPersonalDetailsNavButtons(showBack: false),
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
          label: 'Civil Status',
          required: true,
          child: DropdownButtonFormField<String>(
            value: _selectedCivilStatus,
            dropdownColor: Colors.white,
            style: const TextStyle(color: _textDark, fontSize: 14),
            decoration: _inputDecoration(
              hint: 'Select civil status',
              prefixIcon: Icons.favorite_border,
            ),
            items: _civilStatusOptions
                .map((s) => DropdownMenuItem(value: s, child: Text(s)))
                .toList(),
            validator: (v) => v == null ? 'Required' : null,
            onChanged: (v) => setState(() => _selectedCivilStatus = v),
          ),
        ),
        const SizedBox(height: 16),

        _buildFormField(
          label: 'Nationality',
          required: true,
          child: DropdownButtonFormField<String>(
            value: _selectedNationality,
            dropdownColor: Colors.white,
            style: const TextStyle(color: _textDark, fontSize: 14),
            decoration: _inputDecoration(
              hint: 'Select nationality',
              prefixIcon: Icons.flag_outlined,
            ),
            items: _nationalities
                .map((n) => DropdownMenuItem(value: n, child: Text(n)))
                .toList(),
            validator: (v) => v == null ? 'Required' : null,
            onChanged: (v) => setState(() => _selectedNationality = v),
          ),
        ),
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
                    icon: Icon(
                      Icons.keyboard_arrow_down,
                      color: _textMuted.withOpacity(0.6),
                      size: 20,
                    ),
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
                    icon: Icon(
                      Icons.keyboard_arrow_down,
                      color: _textMuted.withOpacity(0.6),
                      size: 20,
                    ),
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
                    icon: Icon(
                      Icons.keyboard_arrow_down,
                      color: _textMuted.withOpacity(0.6),
                      size: 20,
                    ),
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
            color: _primaryOrange.withOpacity(0.05),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: _primaryOrange.withOpacity(0.2)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.home_outlined, size: 20, color: _primaryOrange),
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
                label: 'Country',
                required: true,
                child: DropdownButtonFormField<String>(
                  value: _selectedCountry,
                  dropdownColor: Colors.white,
                  style: const TextStyle(color: _textDark, fontSize: 14),
                  decoration: _inputDecoration(hint: 'Select country'),
                  items: _countries
                      .map((c) => DropdownMenuItem(value: c, child: Text(c)))
                      .toList(),
                  validator: (v) => v == null ? 'Required' : null,
                  onChanged: (v) => setState(() => _selectedCountry = v),
                ),
              ),
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
                        style: const TextStyle(color: _textDark, fontSize: 14),
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
                        style: const TextStyle(color: _textDark, fontSize: 14),
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
                        validator: (v) => v == null ? 'Required' : null,
                        onChanged: (v) => setState(() => _selectedCity = v),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),

              Row(
                children: [
                  Expanded(
                    child: _buildFormField(
                      label: 'Barangay',
                      required: true,
                      child: TextFormField(
                        controller: _barangayController,
                        style: const TextStyle(color: _textDark, fontSize: 14),
                        decoration: _inputDecoration(hint: 'e.g. Poblacion'),
                        textCapitalization: TextCapitalization.words,
                        validator: validatePhilippineBarangay,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _buildFormField(
                      label: 'Street',
                      required: true,
                      child: TextFormField(
                        controller: _streetController,
                        style: const TextStyle(color: _textDark, fontSize: 14),
                        decoration: _inputDecoration(
                          hint: 'e.g. 123 Rizal St.',
                        ),
                        textCapitalization: TextCapitalization.words,
                        validator: validatePhilippineStreet,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 32),

        _buildPersonalDetailsNavButtons(),
      ],
    );
  }

  Widget _buildFamilyTravelPartySubStep() {
    final age = _ageInYears();
    final isMinor = age != null && age < 18;
    final filled = _filledTravelPartyRows();
    final headcount = _computePartyHeadcount();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSubStepHeader(
          'Family / travel party',
          isMinor
              ? 'A parent or guardian must be named below. List every minor '
                  'traveling with you (name, age, gender only). '
                  'Total headcount = 1 parent + children.'
              : 'Optional: add children traveling with you. '
                  'Party size for LGU reports = 1 (you) + each child listed.',
          Icons.family_restroom_outlined,
        ),
        if (isMinor) ...[
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: _primaryOrange.withOpacity(0.08),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: _primaryOrange.withOpacity(0.25)),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.info_outline, color: _primaryOrange, size: 22),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'You indicated you are under 18. Enter your parent or '
                    'guardian\'s full name, then list all minors in your group.',
                    style: TextStyle(
                      fontSize: 13,
                      color: _textDark.withOpacity(0.9),
                      height: 1.35,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          _buildFormField(
            label: 'Parent / guardian full name',
            required: true,
            child: TextFormField(
              controller: _parentGuardianController,
              style: const TextStyle(color: _textDark, fontSize: 14),
              decoration: _inputDecoration(
                hint: 'e.g. Parent registering this account',
                prefixIcon: Icons.supervisor_account_outlined,
              ),
              textCapitalization: TextCapitalization.words,
              validator: (v) {
                if (!isMinor) return null;
                if (v == null || v.trim().isEmpty) return 'Required';
                return null;
              },
            ),
          ),
          const SizedBox(height: 16),
        ],
        Text(
          isMinor ? 'Minors (name, age, gender)' : 'Children (optional)',
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: _textDark,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Reported party size: $headcount '
          '(1 ${isMinor ? 'parent/guardian' : 'adult'} + ${filled.length} '
          '${filled.length == 1 ? 'child' : 'children'})',
          style: TextStyle(fontSize: 12, color: _textMuted.withOpacity(0.95)),
        ),
        const SizedBox(height: 16),
        ...List.generate(_travelPartyChildren.length, (index) {
          final row = _travelPartyChildren[index];
          return Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: _inputFill,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: _inputBorder),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        'Child ${index + 1}',
                        style: const TextStyle(
                          fontWeight: FontWeight.w600,
                          color: _textDark,
                          fontSize: 13,
                        ),
                      ),
                      const Spacer(),
                      if (_travelPartyChildren.length > 1)
                        IconButton(
                          onPressed: () => _removeTravelPartyChildRow(index),
                          icon: Icon(
                            Icons.remove_circle_outline,
                            color: Colors.red.shade400,
                            size: 22,
                          ),
                          tooltip: 'Remove',
                        ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  _buildFormField(
                    label: 'Full name',
                    required: isMinor,
                    child: TextFormField(
                      controller: row.nameController,
                      onChanged: (_) => setState(() {}),
                      style: const TextStyle(color: _textDark, fontSize: 14),
                      decoration: _inputDecoration(
                        hint: 'Name',
                        prefixIcon: Icons.person_outline,
                      ),
                      textCapitalization: TextCapitalization.words,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: _buildFormField(
                          label: 'Age',
                          required: isMinor,
                          child: TextFormField(
                            controller: row.ageController,
                            onChanged: (_) => setState(() {}),
                            keyboardType: TextInputType.number,
                            style: const TextStyle(
                              color: _textDark,
                              fontSize: 14,
                            ),
                            decoration: _inputDecoration(
                              hint: 'Age',
                              prefixIcon: Icons.cake_outlined,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _buildFormField(
                          label: 'Gender',
                          required: isMinor,
                          child: DropdownButtonFormField<String>(
                            value: row.gender,
                            dropdownColor: Colors.white,
                            style: const TextStyle(
                              color: _textDark,
                              fontSize: 14,
                            ),
                            decoration: _inputDecoration(
                              hint: 'Select',
                              prefixIcon: Icons.wc_outlined,
                            ),
                            items: _sexOptions
                                .map(
                                  (s) => DropdownMenuItem(
                                    value: s,
                                    child: Text(s),
                                  ),
                                )
                                .toList(),
                            onChanged: (v) => setState(() => row.gender = v),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          );
        }),
        Align(
          alignment: Alignment.centerLeft,
          child: OutlinedButton.icon(
            onPressed: _addTravelPartyChildRow,
            icon: const Icon(Icons.add, size: 20),
            label: const Text('Add child'),
            style: OutlinedButton.styleFrom(
              foregroundColor: _primaryOrange,
              side: BorderSide(color: _primaryOrange.withOpacity(0.5)),
            ),
          ),
        ),
        if (isMinor && _travelPartyChildren.isEmpty) ...[
          const SizedBox(height: 8),
          Text(
            'Tap "Add child" if the suggested row did not appear.',
            style: TextStyle(fontSize: 12, color: _textMuted.withOpacity(0.9)),
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
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        if (showBack)
          TextButton.icon(
            onPressed: _previousStep,
            icon: const Icon(Icons.arrow_back, size: 18),
            label: const Text('Back'),
            style: TextButton.styleFrom(
              foregroundColor: _textMuted,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            ),
          )
        else
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text(
              'Cancel',
              style: TextStyle(color: _textMuted, fontSize: 15),
            ),
          ),
        FilledButton.icon(
          onPressed: _nextStep,
          icon: Icon(
            isLastSubStep ? Icons.check : Icons.arrow_forward,
            size: 18,
          ),
          label: Text(isLastSubStep ? 'Continue' : 'Next'),
          style: FilledButton.styleFrom(
            backgroundColor: _primaryOrange,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildFormField({
    required String label,
    required Widget child,
    bool required = false,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionLabel(label, required: required),
        child,
      ],
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
            color: _primaryOrange.withOpacity(0.1),
            shape: BoxShape.circle,
          ),
          child: const Icon(
            Icons.phone_android,
            size: 40,
            color: _primaryOrange,
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
                backgroundColor: _primaryOrange,
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
                      borderSide: const BorderSide(
                        color: _primaryOrange,
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
                backgroundColor: _primaryOrange,
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
              style: TextButton.styleFrom(foregroundColor: _primaryOrange),
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
                        backgroundColor: _primaryOrange,
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
                  backgroundColor: _primaryOrange,
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

  Widget _buildTravelHistoryStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Please indicate the LAST 3 TOURIST DESTINATIONS you have visited.',
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w500,
            color: _textMuted,
          ),
        ),
        const SizedBox(height: 16),

        _buildSectionLabel('1st destination you have visited', required: true),
        TextFormField(
          controller: _firstDestinationController,
          style: const TextStyle(color: _textDark, fontSize: 14),
          decoration: _inputDecoration(
            hint: 'e.g. Boracay, Aklan',
            prefixIcon: Icons.place_outlined,
          ),
          validator: (v) => v == null || v.isEmpty ? 'Required' : null,
        ),
        const SizedBox(height: 16),

        _buildSectionLabel('2nd destination you have visited', required: true),
        TextFormField(
          controller: _secondDestinationController,
          style: const TextStyle(color: _textDark, fontSize: 14),
          decoration: _inputDecoration(
            hint: 'e.g. Cebu City',
            prefixIcon: Icons.place_outlined,
          ),
          validator: (v) => v == null || v.isEmpty ? 'Required' : null,
        ),
        const SizedBox(height: 16),

        _buildSectionLabel('3rd destination you have visited', required: true),
        TextFormField(
          controller: _thirdDestinationController,
          style: const TextStyle(color: _textDark, fontSize: 14),
          decoration: _inputDecoration(
            hint: 'e.g. Palawan',
            prefixIcon: Icons.place_outlined,
          ),
          validator: (v) => v == null || v.isEmpty ? 'Required' : null,
        ),
        const SizedBox(height: 24),

        _buildSectionLabel(
          'How did you hear about Misamis Occidental?',
          required: true,
        ),
        TextFormField(
          controller: _howHeardController,
          style: const TextStyle(color: _textDark, fontSize: 14),
          decoration: _inputDecoration(
            hint: 'e.g. Facebook, Friends, Family',
            prefixIcon: Icons.info_outline,
          ),
          validator: (v) => v == null || v.isEmpty ? 'Required' : null,
        ),
        const SizedBox(height: 24),

        _buildSectionLabel(
          'What Mode of Transportation will you take?',
          required: true,
        ),
        DropdownButtonFormField<String>(
          value: _selectedTransportation,
          dropdownColor: Colors.white,
          style: const TextStyle(color: _textDark, fontSize: 14),
          decoration: _inputDecoration(
            hint: 'e.g. Private Car, Public Bus',
            prefixIcon: Icons.directions_car_outlined,
          ),
          items: const [
            DropdownMenuItem(value: 'Private Car', child: Text('Private Car')),
            DropdownMenuItem(value: 'Public Bus', child: Text('Public Bus')),
            DropdownMenuItem(
              value: 'Van/UV Express',
              child: Text('Van/UV Express'),
            ),
            DropdownMenuItem(value: 'Motorcycle', child: Text('Motorcycle')),
            DropdownMenuItem(value: 'Tricycle', child: Text('Tricycle')),
            DropdownMenuItem(value: 'Airplane', child: Text('Airplane')),
            DropdownMenuItem(value: 'Ferry/Boat', child: Text('Ferry/Boat')),
            DropdownMenuItem(value: 'Others', child: Text('Others')),
          ],
          validator: (v) => v == null ? 'Required' : null,
          onChanged: (v) => setState(() => _selectedTransportation = v),
        ),
        const SizedBox(height: 24),

        _buildSectionLabel('Local or Foreign', required: true),
        DropdownButtonFormField<String>(
          value: _selectedLocalOrForeign,
          dropdownColor: Colors.white,
          style: const TextStyle(color: _textDark, fontSize: 14),
          decoration: _inputDecoration(
            hint: 'e.g. Local / Foreign',
            prefixIcon: Icons.person_outline,
          ),
          items: const [
            DropdownMenuItem(value: 'Local', child: Text('Local')),
            DropdownMenuItem(value: 'Foreign', child: Text('Foreign')),
          ],
          validator: (v) => v == null ? 'Required' : null,
          onChanged: (v) => setState(() => _selectedLocalOrForeign = v),
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
              onPressed: _nextStep,
              style: FilledButton.styleFrom(
                backgroundColor: _primaryOrange,
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
                  ? _primaryOrange
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
                          color: _primaryOrange,
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

        Row(
          children: [
            Expanded(
              child: FilledButton.icon(
                onPressed: () => _pickImage(ImageSource.gallery),
                icon: const Icon(Icons.upload_file, size: 18),
                label: const Text('Upload'),
                style: FilledButton.styleFrom(
                  backgroundColor: _primaryOrange,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
              ),
            ),
            if (!kIsWeb) ...[
              const SizedBox(width: 16),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => _pickImage(ImageSource.camera),
                  icon: const Icon(Icons.camera_alt, size: 18),
                  label: const Text('Take a Photo'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: _primaryOrange,
                    side: const BorderSide(color: _primaryOrange),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                ),
              ),
            ],
          ],
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
                activeColor: _primaryOrange,
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
        const SizedBox(height: 16),

        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 24,
              height: 24,
              child: Checkbox(
                value: _agreeToTerms,
                onChanged: (v) => setState(() => _agreeToTerms = v ?? false),
                activeColor: _primaryOrange,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(4),
                ),
                side: const BorderSide(color: _inputBorder),
              ),
            ),
            const SizedBox(width: 12),
            const Expanded(
              child: Text(
                'I agree to the Terms and Conditions and Data Privacy Policy',
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
                backgroundColor: _primaryOrange,
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

import 'dart:async' show unawaited;
import 'dart:typed_data';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart' show debugPrint, kIsWeb;
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:atmos_trs_system/config/app_theme.dart';
import 'package:atmos_trs_system/navigation/auth_navigation.dart';
import 'package:atmos_trs_system/screens/verify_otp_screen.dart';
import 'package:atmos_trs_system/services/auth_service.dart';
import 'package:atmos_trs_system/config/session_storage.dart';
import 'package:atmos_trs_system/data/misamis_occidental_barangays.dart';
import 'package:atmos_trs_system/services/establishment_category_service.dart';
import 'package:atmos_trs_system/services/firestore_auth_gate.dart';
import 'package:atmos_trs_system/services/otp_delivery_service.dart';
import 'package:atmos_trs_system/services/otp_service.dart';
import 'package:atmos_trs_system/services/pending_establishment_registration_cache.dart';
import 'package:atmos_trs_system/services/push_notification_service.dart';
import 'package:atmos_trs_system/services/registration_rollback_service.dart';
import 'package:atmos_trs_system/services/username_registry_service.dart';
import 'package:atmos_trs_system/utils/email_utils.dart';
import 'package:atmos_trs_system/utils/establishment_capability.dart';
import 'package:atmos_trs_system/utils/establishment_lodging_hours.dart';
import 'package:atmos_trs_system/utils/logo_utils.dart';
import 'package:atmos_trs_system/utils/municipality_helper.dart';
import 'package:atmos_trs_system/utils/signup_field_validation.dart';
import 'package:atmos_trs_system/widgets/dial_code_mobile_field.dart';
import 'package:atmos_trs_system/widgets/establishment_location_capture.dart';
import 'package:atmos_trs_system/widgets/signup_legal_consent.dart';
import 'package:atmos_trs_system/widgets/tourist_signup_chrome.dart';
import 'package:atmos_trs_system/widgets/web_glass_auth_scaffold.dart';

/// Self-registration for tourism establishments (hotels, resorts, etc.).
class EstablishmentSignupScreen extends StatefulWidget {
  const EstablishmentSignupScreen({super.key});

  @override
  State<EstablishmentSignupScreen> createState() =>
      _EstablishmentSignupScreenState();
}

class _EstablishmentSignupScreenState extends State<EstablishmentSignupScreen> {
  final _formKey = GlobalKey<FormState>();
  final _businessNameController = TextEditingController();
  final _ownerNameController = TextEditingController();
  final _businessPermitNoController = TextEditingController();
  final _contactController = TextEditingController();
  final _emailController = TextEditingController();
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  final _ownerNameFocus = FocusNode();
  final _businessPermitNoFocus = FocusNode();
  final _contactFocus = FocusNode();
  final _emailFocus = FocusNode();
  final _usernameFocus = FocusNode();
  final _passwordFocus = FocusNode();
  final _confirmPasswordFocus = FocusNode();
  final _confirmPasswordFieldKey = GlobalKey<FormFieldState<String>>();

  String _contactDialCode = '+63';
  String? _category;
  bool _categoryPendingReview = false;
  List<String> _approvedExtraCategories = const [];
  String? _municipality;
  String? _barangay;
  int? _yearEstablished;
  TimeOfDay _checkInTime = const TimeOfDay(hour: 14, minute: 0);
  TimeOfDay _checkOutTime = const TimeOfDay(hour: 12, minute: 0);
  double? _latitude;
  double? _longitude;
  bool _locating = false;
  bool _obscurePassword = true;
  bool _obscureConfirm = true;
  bool _agreeToTerms = false;
  bool _privacyOpened = false;
  bool _termsOpened = false;
  bool _submitting = false;
  bool _submitGuard = false;
  String? _submitPhase;

  /// Optional business permit photo (bytes held until Auth uid exists).
  Uint8List? _permitImageBytes;
  String? _permitImageName;

  bool get _isDesktopGlass =>
      kIsWeb && MediaQuery.sizeOf(context).width >= kWebGlassAuthBreakpoint;

  bool get _legalReviewComplete => _privacyOpened && _termsOpened;

  List<String> get _municipalities {
    final keys = kMisamisOccidentalBarangaysByCity.keys.toList()..sort();
    return keys;
  }

  List<int> get _years {
    final now = DateTime.now().year;
    return List<int>.generate(now - 1899, (i) => now - i);
  }

  List<String> get _barangayOptions =>
      barangaysForMisamisOccidentalCity(_municipality);

  bool get _isLodgingCategory =>
      EstablishmentCapability.isLodging(_category);

  List<String> get _officialCategories =>
      EstablishmentCategoryService.mergeOfficial(
        extras: _approvedExtraCategories,
      );

  @override
  void initState() {
    super.initState();
    unawaited(_loadOfficialCategories());
  }

  Future<void> _loadOfficialCategories() async {
    final extras = await EstablishmentCategoryService.loadApprovedExtras();
    if (!mounted) return;
    setState(() => _approvedExtraCategories = extras);
  }

  Future<void> _openSuggestCategoryDialog() async {
    if (_submitting) return;
    final accepted = await showDialog<String>(
      context: context,
      builder: (ctx) => _SuggestCategoryDialog(
        official: _officialCategories,
        alreadySuggested: _categoryPendingReview ? _category : null,
      ),
    );
    if (accepted == null || accepted.isEmpty || !mounted) return;
    setState(() {
      _category = accepted;
      _categoryPendingReview = true;
    });
  }

  Future<void> _pickCheckInTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: _checkInTime,
    );
    if (picked != null && mounted) setState(() => _checkInTime = picked);
  }

  Future<void> _pickCheckOutTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: _checkOutTime,
    );
    if (picked != null && mounted) setState(() => _checkOutTime = picked);
  }

  @override
  void dispose() {
    _businessNameController.dispose();
    _ownerNameController.dispose();
    _businessPermitNoController.dispose();
    _contactController.dispose();
    _emailController.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    _ownerNameFocus.dispose();
    _businessPermitNoFocus.dispose();
    _contactFocus.dispose();
    _emailFocus.dispose();
    _usernameFocus.dispose();
    _passwordFocus.dispose();
    _confirmPasswordFocus.dispose();
    super.dispose();
  }

  Future<void> _pickBusinessPermitPhoto() async {
    try {
      final picked = await ImagePicker().pickImage(
        source: ImageSource.gallery,
        imageQuality: 85,
        maxWidth: 2000,
      );
      if (picked == null) return;
      final bytes = await picked.readAsBytes();
      if (!mounted) return;
      setState(() {
        _permitImageBytes = bytes;
        _permitImageName = picked.name;
      });
    } catch (e) {
      debugPrint('[EST-SIGNUP] permit pick failed: $e');
      if (mounted) _snack('Could not attach permit photo. Try again.');
    }
  }

  Future<String?> _uploadPermitIfAny(String uid) async {
    final bytes = _permitImageBytes;
    if (bytes == null || bytes.isEmpty) return null;
    try {
      final name = (_permitImageName ?? 'permit.jpg').toLowerCase();
      final ext = name.endsWith('.png')
          ? 'png'
          : name.endsWith('.webp')
              ? 'webp'
              : 'jpg';
      final contentType = ext == 'png'
          ? 'image/png'
          : ext == 'webp'
              ? 'image/webp'
              : 'image/jpeg';
      final ref = FirebaseStorage.instance
          .ref()
          .child('establishment_permits/$uid/business_permit.$ext');
      await ref.putData(bytes, SettableMetadata(contentType: contentType));
      return await ref.getDownloadURL();
    } catch (e) {
      debugPrint('[EST-SIGNUP] permit upload failed (non-fatal): $e');
      return null;
    }
  }

  TextStyle get _fieldTextStyle => TextStyle(
        color: _isDesktopGlass ? Colors.white : const Color(0xFF1C1917),
        fontSize: 16,
        fontWeight: FontWeight.w600,
        height: 1.35,
      );

  TextStyle get _dropdownItemStyle => const TextStyle(
        color: Color(0xFF1C1917),
        fontSize: 15,
        fontWeight: FontWeight.w600,
      );

  Color get _fieldIconColor =>
      _isDesktopGlass ? Colors.white : const Color(0xFF78716C);

  TextStyle get _hintTextStyle => const TextStyle(
        // Match tourist signup muted grey placeholders.
        color: Color(0xFF9CA3AF),
        fontSize: 15,
        fontWeight: FontWeight.w400,
        letterSpacing: 0.1,
        height: 1.25,
      );

  Widget _dropdownHint(String text) {
    return Text(
      text,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: _hintTextStyle,
    );
  }

  InputDecoration _dec({
    required String hint,
    IconData? icon,
    Widget? suffix,
  }) {
    if (_isDesktopGlass) {
      return webGlassInputDecoration(
        hint: hint,
        prefixIcon: icon,
        suffixIcon: suffix,
      ).copyWith(
        fillColor: Colors.black.withValues(alpha: 0.58),
        // Keep decoration hint empty for dropdowns; they use the [hint] widget.
        hintStyle: _hintTextStyle,
        errorStyle: TextStyle(
          color: Colors.orange.shade100,
          fontSize: 12,
          fontWeight: FontWeight.w700,
        ),
      );
    }
    return InputDecoration(
      hintText: hint,
      hintStyle: _hintTextStyle,
      prefixIcon: icon != null
          ? Icon(icon, color: AppTheme.brandOrange, size: 20)
          : null,
      suffixIcon: suffix,
      filled: true,
      fillColor: Colors.white,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Color(0xFFE7E5E4)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: AppTheme.brandOrange, width: 2),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: Colors.red.shade400),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: Colors.red.shade700, width: 2),
      ),
    );
  }

  Widget _glassDropdown<T>({
    required T? value,
    required String hint,
    required IconData icon,
    required List<DropdownMenuItem<T>> items,
    required ValueChanged<T?>? onChanged,
    required String? Function(T?)? validator,
  }) {
    // Build selected labels from item values so closed-state text stays bright.
    final selectedLabels = <Widget>[
      for (final item in items)
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: Text(
            item.value?.toString() ?? '',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: _fieldTextStyle,
          ),
        ),
    ];

    return DropdownButtonFormField<T>(
      // ignore: deprecated_member_use
      value: value,
      isExpanded: true,
      // Explicit grey hint — decoration hintStyle alone is ignored by dropdowns.
      hint: _dropdownHint(hint),
      disabledHint: _dropdownHint(hint),
      decoration: _dec(hint: hint, icon: icon).copyWith(
        // Avoid a second stacked hint from InputDecoration.
        hintText: null,
      ),
      dropdownColor: Colors.white,
      iconEnabledColor: _isDesktopGlass ? Colors.white : const Color(0xFF78716C),
      iconDisabledColor: _isDesktopGlass
          ? Colors.white.withValues(alpha: 0.45)
          : const Color(0xFFD6D3D1),
      style: _fieldTextStyle,
      selectedItemBuilder: (_) => selectedLabels,
      items: [
        for (final item in items)
          DropdownMenuItem<T>(
            value: item.value,
            enabled: item.enabled,
            child: Text(
              item.value?.toString() ?? '',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: _dropdownItemStyle,
            ),
          ),
      ],
      onChanged: onChanged,
      validator: validator,
    );
  }

  bool _privacyExpanded = false;
  bool _termsExpanded = false;

  /// 0 = Terms & Privacy first; 1 = registration fields.
  int _signupStep = 0;

  Widget _buildLegalSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SignupLegalExpansionCard(
          onDark: _isDesktopGlass,
          title: 'Data Privacy (RA 10173)',
          subtitle: 'How we collect and use your information',
          icon: Icons.shield_outlined,
          expanded: _privacyExpanded,
          reviewed: _privacyOpened,
          onExpandedChanged: (v) => setState(() {
            _privacyExpanded = v;
            if (v) _privacyOpened = true;
          }),
          bullets: const [
            'We collect personal and business data only for tourism '
                'establishment registration, accreditation support, and LGU / '
                'provincial tourism reporting in Misamis Occidental.',
            'Data may include business name, owner name, contact details, '
                'location, category, and account credentials.',
            'Information may be shared with the Provincial Tourism Office and '
                'relevant LGU tourism offices for review and visitor services.',
            'We use reasonable security measures and do not sell your data to '
                'unrelated third parties.',
            'You may request access, correction, or raise privacy concerns '
                'through your municipal or provincial Tourism Office.',
          ],
        ),
        const SizedBox(height: 10),
        SignupLegalExpansionCard(
          onDark: _isDesktopGlass,
          title: 'Terms and Conditions',
          subtitle: 'Your responsibilities as a registrant',
          icon: Icons.description_outlined,
          expanded: _termsExpanded,
          reviewed: _termsOpened,
          onExpandedChanged: (v) => setState(() {
            _termsExpanded = v;
            if (v) _termsOpened = true;
          }),
          bullets: const [
            'You confirm that all business and owner details you provide are '
                'true, complete, and match your Business Permit records.',
            'ATMOS-TRS is for lawful tourism establishment registration and '
                'related provincial / LGU tourism processes only.',
            'Misrepresentation or misuse of the system may result in pending '
                'rejection, restricted access, or account action.',
            'Your account may remain pending until LGU or Provincial Tourism '
                'officers complete review and approval.',
            'The Province and LGUs may use aggregated establishment data for '
                'tourism planning and public service reporting.',
          ],
        ),
        const SizedBox(height: 18),
        SignupLegalAgreementCard(
          onDark: _isDesktopGlass,
          agreed: _agreeToTerms,
          canAgree: _legalReviewComplete,
          onChanged: _submitting
              ? null
              : (v) => setState(() => _agreeToTerms = v),
        ),
      ],
    );
  }

  Future<void> _continueFromLegal() async {
    if (!_legalReviewComplete) {
      _snack('Please open and read both the Data Privacy and Terms sections.');
      return;
    }
    if (!_agreeToTerms) {
      _snack('Please agree to the Terms and Data Privacy Policy.');
      return;
    }
    setState(() => _signupStep = 1);
  }

  void _onBack() {
    if (_submitting) return;
    if (_signupStep > 0) {
      setState(() => _signupStep = 0);
      return;
    }
    Navigator.pop(context);
  }

  void _onPasswordEdited() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (_confirmPasswordController.text.isEmpty) return;
      _confirmPasswordFieldKey.currentState?.validate();
    });
  }

  Future<void> _submit() async {
    if (_submitGuard) return;
    _submitGuard = true;
    if (!_formKey.currentState!.validate()) {
      _submitGuard = false;
      return;
    }
    if (!_legalReviewComplete || !_agreeToTerms) {
      _submitGuard = false;
      setState(() => _signupStep = 0);
      _snack('Please complete Terms & Data Privacy first.');
      return;
    }
    if (_category == null ||
        _municipality == null ||
        _barangay == null ||
        _yearEstablished == null) {
      _submitGuard = false;
      _snack('Please complete all required fields.');
      return;
    }
    final lat = _latitude;
    final lng = _longitude;
    if (lat == null ||
        lng == null ||
        (lat.abs() < 1e-6 && lng.abs() < 1e-6)) {
      _submitGuard = false;
      _snack('Tap Get location so tourists can find you on the map.');
      return;
    }
    if (_isLodgingCategory &&
        EstablishmentLodgingHours.minutesSinceMidnight(_checkInTime) ==
            EstablishmentLodgingHours.minutesSinceMidnight(_checkOutTime)) {
      _submitGuard = false;
      _snack('Check-in and check-out times must be different.');
      return;
    }

    final email = normalizeEmail(_emailController.text);
    final username = _usernameController.text.trim();
    final password = _passwordController.text;
    final businessName = _businessNameController.text.trim();
    final ownerName = _ownerNameController.text.trim();
    final contact = composeE164Mobile(
      _contactDialCode,
      _contactController.text,
    );

    setState(() {
      _submitting = true;
      _submitPhase = 'Creating your account...';
    });
    String? createdUid;
    var usernameClaimed = false;

    try {
      // Format-only first. Full uniqueness is enforced after Auth (signed-in claim).
      final formatError = UsernameRegistryService.validateFormat(username);
      if (formatError != null) {
        _snack(formatError);
        return;
      }

      if (Firebase.apps.isEmpty) {
        _snack('Firebase is not ready. Try again.');
        return;
      }

      // Create Auth with the establishment's real email, then verify via OTP
      // before the profile is written / dashboard is opened.
      final cred = await FirebaseAuth.instance.createUserWithEmailAndPassword(
        email: email,
        password: password,
      );
      final uid = cred.user?.uid;
      if (uid == null || uid.isEmpty) {
        _snack('Could not create account. Try again.');
        return;
      }
      createdUid = uid;
      unawaited(() async {
        try {
          await AuthService.sendEmailVerification();
        } catch (e, st) {
          debugPrint('[EST-SIGNUP] Firebase verification email: $e\n$st');
        }
      }());
      final tokenFuture = FirestoreAuthGate.ensureFreshIdToken();
      final permitFuture = _uploadPermitIfAny(uid).onError((Object e, StackTrace st) {
        debugPrint('[EST-SIGNUP] permit upload: $e\n$st');
        return null;
      });
      await tokenFuture;

      final usernameError =
          await UsernameRegistryService.checkAvailable(username);
      if (usernameError != null) {
        await RegistrationRollbackService.rollback(uid);
        createdUid = null;
        _snack(usernameError);
        return;
      }

      try {
        await UsernameRegistryService.claim(
          username: username,
          uid: uid,
          email: email,
        );
        usernameClaimed = true;
      } catch (e) {
        debugPrint('[EST-SIGNUP] username claim failed: $e');
        await RegistrationRollbackService.rollback(uid);
        createdUid = null;
        final taken = e is StateError && e.message == 'USERNAME_TAKEN';
        _snack(
          taken
              ? 'This username was just taken. Choose another.'
              : e is FirebaseException && e.code == 'permission-denied'
                  ? 'Could not save your username (permission denied). '
                      'Please try again in a moment.'
                  : 'Could not save your username: $e',
        );
        return;
      }

      String? suggestionId;
      if (_categoryPendingReview && (_category ?? '').trim().isNotEmpty) {
        if (mounted) {
          setState(() => _submitPhase = 'Saving category suggestion...');
        }
        suggestionId =
            await EstablishmentCategoryService.submitPendingSuggestion(
          uid: uid,
          name: _category!,
          establishmentId: uid,
          businessName: businessName,
        );
      }

      if (mounted) {
        setState(() => _submitPhase = 'Sending verification email...');
      }
      final otp = OtpService.generateSixDigitOtp();
      await OtpService.saveOtp(uid: uid, otp: otp, email: email);

      if (!kIsWeb) {
        unawaited(ensureEmailOtpNotificationSupport());
        unawaited(syncFcmTokenToUserDoc(uid));
      }

      unawaited(
        OtpDeliveryService.deliverVerificationCode(
          uid: uid,
          email: email,
          displayName: businessName,
          otp: otp,
          mobile: contact,
          notifyOnThisDevice: false,
          trySms: false,
          otpAlreadyInFirestore: true,
          emailInBackground: true,
        ),
      );

      final municipalityId = getMunicipalityIdFromName(_municipality);
      final permitNo = _businessPermitNoController.text.trim();
      if (mounted && _permitImageBytes != null) {
        setState(() => _submitPhase = 'Uploading permit photo...');
      }
      final permitUrl = await permitFuture;
      final lodging = EstablishmentCapability.isLodging(_category);
      final checkInStr = EstablishmentLodgingHours.format(_checkInTime);
      final checkOutStr = EstablishmentLodgingHours.format(_checkOutTime);

      final userData = PendingEstablishmentRegistrationCache.jsonSafeMap({
        'firebaseUid': uid,
        'email': email,
        'fullName': ownerName,
        'businessName': businessName,
        'role': 'tourism_establishment',
        'municipality': _municipality,
        'municipalityId': municipalityId,
        'barangay': _barangay,
        'username': username,
        'contactNumber': contact,
        'category': _category,
        if (_categoryPendingReview) ...{
          'categoryPendingReview': true,
          'suggestedCategory': _category,
          if (suggestionId != null) 'categorySuggestionId': suggestionId,
        },
        'latitude': lat,
        'longitude': lng,
        'yearEstablished': _yearEstablished,
        if (permitNo.isNotEmpty) 'businessPermitNo': permitNo,
        if (permitUrl != null) 'businessPermitUrl': permitUrl,
        if (lodging) ...{
          'checkInTime': checkInStr,
          'checkOutTime': checkOutStr,
        },
        'isVerified': false,
        'status': 'pending',
      });
      final establishmentData =
          PendingEstablishmentRegistrationCache.jsonSafeMap({
        'id': uid,
        'name': businessName,
        'businessName': businessName,
        'type': _category,
        'category': _category,
        if (_categoryPendingReview) ...{
          'categoryPendingReview': true,
          'suggestedCategory': _category,
          if (suggestionId != null) 'categorySuggestionId': suggestionId,
        },
        'ownerName': ownerName,
        'contactNumber': contact,
        'email': email,
        'username': username,
        'municipality': _municipality,
        'municipalityId': municipalityId,
        'barangay': _barangay,
        'location': '$_barangay, $_municipality, Misamis Occidental',
        'latitude': lat,
        'longitude': lng,
        'yearEstablished': _yearEstablished,
        if (permitNo.isNotEmpty) 'businessPermitNo': permitNo,
        if (permitUrl != null) 'businessPermitUrl': permitUrl,
        if (lodging) ...{
          'checkInTime': checkInStr,
          'checkOutTime': checkOutStr,
        },
        'status': 'pending',
        'ownerUid': uid,
        'authUid': uid,
      });

      await PendingEstablishmentRegistrationCache.save(
        PendingEstablishmentRegistration(
          uid: uid,
          contactEmail: email,
          authEmail: email,
          userData: userData,
          establishmentData: establishmentData,
        ),
      );

      await SessionStorage.saveSession(
        uid,
        role: UserRole.tourismEstablishment,
        email: email,
        municipalityId: municipalityId.isNotEmpty ? municipalityId : null,
      );

      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        verificationHandoffRoute(
          builder: (_) => const VerifyOtpScreen(),
          arguments: {
            'contactEmail': email,
            'fromSignup': true,
            'otpAlreadySent': true,
            'accountType': 'tourism_establishment',
          },
        ),
      );
    } on FirebaseAuthException catch (e) {
      debugPrint('[EST-SIGNUP] Auth error: ${e.code} ${e.message}');
      if (createdUid != null) {
        if (usernameClaimed) {
          await UsernameRegistryService.release(username);
        }
        await RegistrationRollbackService.rollback(createdUid);
      }
      _snack(_authErrorMessage(e));
    } catch (e, st) {
      debugPrint('[EST-SIGNUP] failed: $e\n$st');
      if (createdUid != null) {
        if (usernameClaimed) {
          await UsernameRegistryService.release(username);
        }
        await RegistrationRollbackService.rollback(createdUid);
      }
      _snack('Registration failed: $e');
    } finally {
      _submitGuard = false;
      if (mounted) {
        setState(() {
          _submitting = false;
          _submitPhase = null;
        });
      }
    }
  }

  String _authErrorMessage(FirebaseAuthException e) {
    switch (e.code) {
      case 'email-already-in-use':
        return 'This email is already registered. Log in, or use another email.';
      case 'weak-password':
        return 'Password is too short. Use at least 6 characters.';
      case 'invalid-email':
        return 'Enter a valid email address.';
      case 'operation-not-allowed':
        return 'Email/password sign-up is not enabled. Contact the administrator.';
      case 'network-request-failed':
        return 'Network error. Check your connection and try again.';
      default:
        return e.message?.isNotEmpty == true
            ? e.message!
            : 'Could not create account (${e.code}).';
    }
  }

  void _snack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red.shade700,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  TextStyle get _labelTextStyle => TextStyle(
        fontSize: 13.5,
        fontWeight: FontWeight.w800,
        letterSpacing: 0.15,
        color: _isDesktopGlass ? Colors.white : const Color(0xFF292524),
        shadows: _isDesktopGlass
            ? const [
                Shadow(
                  color: Color(0x99000000),
                  blurRadius: 6,
                  offset: Offset(0, 1),
                ),
              ]
            : null,
      );

  Widget _brandHeader({required bool showTitle}) {
    return Column(
      children: [
        Center(
          child: Container(
            width: 96,
            height: 96,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.white,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.18),
                  blurRadius: 20,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: const ClipOval(
              child: Padding(
                padding: EdgeInsets.all(6),
                child: TransparentLogo(
                  width: 84,
                  height: 84,
                  fit: BoxFit.contain,
                ),
              ),
            ),
          ),
        ),
        if (showTitle) ...[
          const SizedBox(height: 12),
          Text(
            'Tourism Establishment Signup',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w800,
              height: 1.2,
              color: _isDesktopGlass ? Colors.white : const Color(0xFF1C1917),
              shadows: _isDesktopGlass
                  ? const [
                      Shadow(
                        color: Color(0x99000000),
                        blurRadius: 8,
                        offset: Offset(0, 2),
                      ),
                    ]
                  : null,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Register your tourism business.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: _isDesktopGlass ? Colors.white : const Color(0xFF78716C),
              shadows: _isDesktopGlass
                  ? const [
                      Shadow(
                        color: Color(0x88000000),
                        blurRadius: 6,
                        offset: Offset(0, 1),
                      ),
                    ]
                  : null,
            ),
          ),
        ],
      ],
    );
  }

  Widget _fieldLabel(String text, {bool required = false}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8, top: 2),
      child: Row(
        children: [
          Flexible(
            child: Text(text, style: _labelTextStyle),
          ),
          if (required)
            Text(
              ' *',
              style: TextStyle(
                color: Colors.red.shade600,
                fontWeight: FontWeight.w900,
                fontSize: _labelTextStyle.fontSize,
              ),
            ),
        ],
      ),
    );
  }

  Widget _formSection({
    required String title,
    required IconData icon,
    required List<Widget> children,
  }) {
    final onGlass = _isDesktopGlass;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 16),
      decoration: BoxDecoration(
        color: onGlass ? Colors.white.withValues(alpha: 0.10) : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: onGlass
              ? Colors.white.withValues(alpha: 0.18)
              : const Color(0xFFFFEDD5),
        ),
        boxShadow: onGlass
            ? null
            : [
                BoxShadow(
                  color: const Color(0xFFEA580C).withValues(alpha: 0.08),
                  blurRadius: 16,
                  offset: const Offset(0, 6),
                ),
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.04),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              color: AppTheme.brandOrange.withValues(alpha: onGlass ? 0.22 : 0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              children: [
                Icon(icon, size: 18, color: AppTheme.brandOrange),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    title,
                    style: TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.2,
                      color: onGlass ? Colors.white : AppTheme.brandOrangeDark,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          ...children,
        ],
      ),
    );
  }

  List<DropdownMenuItem<String>> _categoryMenuItems() {
    final items = <DropdownMenuItem<String>>[
      for (final c in _officialCategories)
        DropdownMenuItem(value: c, child: Text(c)),
    ];
    final pending = _category;
    if (_categoryPendingReview &&
        pending != null &&
        EstablishmentCategoryNames.canonicalMatch(
              pending,
              _officialCategories,
            ) ==
            null) {
      items.add(
        DropdownMenuItem(
          value: pending,
          child: Text('$pending (pending review)'),
        ),
      );
    }
    return items;
  }

  Widget _createAccountButton() {
    return FilledButton(
      onPressed: _submitting ? null : _submit,
      style: FilledButton.styleFrom(
        backgroundColor: AppTheme.brandOrange,
        minimumSize: const Size.fromHeight(52),
        padding: const EdgeInsets.symmetric(vertical: 16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
      child: _submitting
          ? Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const SizedBox(
                  height: 22,
                  width: 22,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.5,
                    color: Colors.white,
                  ),
                ),
                if (_submitPhase != null) ...[
                  const SizedBox(width: 12),
                  Flexible(
                    child: Text(
                      _submitPhase!,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                ],
              ],
            )
          : const Text(
              'Create account',
              style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
            ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final formBody = Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _brandHeader(showTitle: true),
          const SizedBox(height: 18),
          _formSection(
            title: 'Business Details',
            icon: Icons.storefront_outlined,
            children: [
              _fieldLabel('Name of Business', required: true),
              TextFormField(
            controller: _businessNameController,
            style: _fieldTextStyle,
            cursorColor: _isDesktopGlass ? Colors.white : AppTheme.brandOrange,
            textCapitalization: TextCapitalization.words,
            textInputAction: TextInputAction.next,
            onFieldSubmitted: (_) => _ownerNameFocus.requestFocus(),
            decoration: _dec(
              hint: 'Enter your business name',
              icon: Icons.storefront_rounded,
            ),
            validator: (v) =>
                (v == null || v.trim().isEmpty) ? 'Required' : null,
          ),
              const SizedBox(height: 12),
              _fieldLabel('Category Type', required: true),
              _glassDropdown<String>(
                value: _category,
                hint: 'Select your category',
                icon: Icons.category,
                items: _categoryMenuItems(),
                onChanged: _submitting
                    ? null
                    : (v) => setState(() {
                          _category = v;
                          _categoryPendingReview = v != null &&
                              EstablishmentCategoryNames.canonicalMatch(
                                    v,
                                    _officialCategories,
                                  ) ==
                                  null;
                        }),
                validator: (v) => v == null ? 'Required' : null,
              ),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: _submitting ? null : _openSuggestCategoryDialog,
                  icon: const Icon(Icons.add_rounded, size: 18),
                  label: const Text('+ Add New Category'),
                  style: TextButton.styleFrom(
                    foregroundColor: AppTheme.brandOrangeDark,
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                  ),
                ),
              ),
              if (_categoryPendingReview && _category != null)
                Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFF7ED),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: const Color(0xFFFED7AA)),
                  ),
                  child: Text(
                    'Suggested category “$_category” is pending OPTACA review. '
                    'Your application can still be submitted.',
                    style: const TextStyle(
                      fontSize: 12,
                      height: 1.35,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF9A3412),
                    ),
                  ),
                ),
              if (_isLodgingCategory) ...[
                const SizedBox(height: 4),
                _fieldLabel('Standard check-in / check-out times'),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _submitting ? null : _pickCheckInTime,
                    icon: const Icon(Icons.login_rounded, size: 18),
                    label: Text(
                      'In ${EstablishmentLodgingHours.displayLabel(_checkInTime)}',
                    ),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppTheme.brandOrange,
                      side: BorderSide(
                        color: AppTheme.brandOrange.withValues(alpha: 0.55),
                      ),
                      padding: const EdgeInsets.symmetric(
                        vertical: 14,
                        horizontal: 8,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _submitting ? null : _pickCheckOutTime,
                    icon: const Icon(Icons.logout_rounded, size: 18),
                    label: Text(
                      'Out ${EstablishmentLodgingHours.displayLabel(_checkOutTime)}',
                    ),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppTheme.brandOrange,
                      side: BorderSide(
                        color: AppTheme.brandOrange.withValues(alpha: 0.55),
                      ),
                      padding: const EdgeInsets.symmetric(
                        vertical: 14,
                        horizontal: 8,
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              'Guests arriving before check-in may be charged an extra night. '
              'You can edit these later under QR & profile.',
              style: TextStyle(
                fontSize: 12,
                height: 1.35,
                color: _isDesktopGlass
                    ? Colors.white70
                    : const Color(0xFF64748B),
              ),
            ),
          ],
              const SizedBox(height: 12),
              _fieldLabel('Name of Owner (from Business Permit)', required: true),
              TextFormField(
            controller: _ownerNameController,
            focusNode: _ownerNameFocus,
            style: _fieldTextStyle,
            cursorColor: _isDesktopGlass ? Colors.white : AppTheme.brandOrange,
            textCapitalization: TextCapitalization.words,
            textInputAction: TextInputAction.next,
            onFieldSubmitted: (_) => _businessPermitNoFocus.requestFocus(),
            decoration: _dec(
              hint: 'Enter owner full name',
              icon: Icons.badge_outlined,
            ),
            validator: (v) =>
                (v == null || v.trim().isEmpty) ? 'Required' : null,
          ),
              const SizedBox(height: 12),
              _fieldLabel('Business Permit Number'),
              TextFormField(
            controller: _businessPermitNoController,
            focusNode: _businessPermitNoFocus,
            style: _fieldTextStyle,
            cursorColor: _isDesktopGlass ? Colors.white : AppTheme.brandOrange,
            textInputAction: TextInputAction.next,
            onFieldSubmitted: (_) => _contactFocus.requestFocus(),
            decoration: _dec(
              hint: 'Permit number (optional)',
              icon: Icons.article_outlined,
            ),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: _submitting ? null : _pickBusinessPermitPhoto,
            icon: Icon(
              _permitImageBytes == null
                  ? Icons.add_photo_alternate_outlined
                  : Icons.check_circle_outline,
              size: 18,
            ),
            label: Text(
              _permitImageBytes == null
                  ? 'Attach Business Permit Photo (optional)'
                  : 'Permit photo attached'
                      '${_permitImageName != null ? ' · $_permitImageName' : ''}',
            ),
            style: OutlinedButton.styleFrom(
              foregroundColor: AppTheme.brandOrange,
              side: BorderSide(
                color: AppTheme.brandOrange.withValues(alpha: 0.55),
              ),
              padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 12),
            ),
          ),
              if (_permitImageBytes != null) ...[
                const SizedBox(height: 10),
                ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Image.memory(
                    _permitImageBytes!,
                    height: 140,
                    width: double.infinity,
                    fit: BoxFit.cover,
                  ),
                ),
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton(
                    onPressed: _submitting
                        ? null
                        : () => setState(() {
                              _permitImageBytes = null;
                              _permitImageName = null;
                            }),
                    child: Text(
                      'Remove photo',
                      style: TextStyle(
                        color: _isDesktopGlass
                            ? Colors.white70
                            : const Color(0xFF78716C),
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 14),
          _formSection(
            title: 'Contact Details',
            icon: Icons.contact_phone_outlined,
            children: [
              _fieldLabel('Contact Number (+63)', required: true),
              DialCodeMobileField(
            controller: _contactController,
            focusNode: _contactFocus,
            textInputAction: TextInputAction.next,
            onFieldSubmitted: (_) => _emailFocus.requestFocus(),
            dialCode: _contactDialCode,
            onDialCodeChanged: (v) => setState(() => _contactDialCode = v),
            textStyle: _fieldTextStyle,
            dialTextStyle: _fieldTextStyle.copyWith(fontWeight: FontWeight.w700),
            dropdownColor: _isDesktopGlass
                ? const Color(0xFF1C1917)
                : Colors.white,
            menuItemTextStyle: TextStyle(
              fontSize: 14,
              color: _isDesktopGlass ? Colors.white : Colors.black87,
            ),
            dialDecoration: _dec(hint: '+63').copyWith(
              prefixIcon: null,
              prefixIconConstraints:
                  const BoxConstraints(minWidth: 0, minHeight: 0),
            ),
            numberDecoration: _dec(
              hint: _contactDialCode == '+63'
                  ? '9XXXXXXXXX'
                  : 'Enter your number',
              icon: Icons.phone_rounded,
            ),
          ),
              const SizedBox(height: 12),
              _fieldLabel('Email Address', required: true),
              TextFormField(
            controller: _emailController,
            focusNode: _emailFocus,
            style: _fieldTextStyle,
            cursorColor: _isDesktopGlass ? Colors.white : AppTheme.brandOrange,
            keyboardType: TextInputType.emailAddress,
            autocorrect: false,
            textInputAction: TextInputAction.next,
            onFieldSubmitted: (_) => _usernameFocus.requestFocus(),
            decoration: _dec(
              hint: 'Enter your email',
              icon: Icons.email,
            ),
            validator: (v) {
              if (v == null || v.trim().isEmpty) return 'Required';
              if (!isValidEmailFormat(v)) return 'Enter a valid email.';
              return null;
            },
          ),
              Padding(
                padding: const EdgeInsets.only(top: 6, bottom: 4),
                child: Text(
                  'Use your real email. A verification code will be sent before '
                  'your account is activated.',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    height: 1.35,
                    color: _isDesktopGlass
                        ? Colors.white.withValues(alpha: 0.9)
                        : const Color(0xFF78716C),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          _formSection(
            title: 'Location',
            icon: Icons.place_outlined,
            children: [
              _fieldLabel('Municipality / City', required: true),
              _glassDropdown<String>(
            value: _municipality,
            hint: 'Select municipality / city',
            icon: Icons.location_city,
            items: _municipalities
                .map((m) => DropdownMenuItem(value: m, child: Text(m)))
                .toList(),
            onChanged: _submitting
                ? null
                : (v) => setState(() {
                      _municipality = v;
                      _barangay = null;
                    }),
            validator: (v) => v == null ? 'Required' : null,
          ),
              const SizedBox(height: 12),
              _fieldLabel('Barangay', required: true),
              _glassDropdown<String>(
            value: _barangay,
            hint: 'Select barangay',
            icon: Icons.place,
            items: _barangayOptions
                .map((b) => DropdownMenuItem(value: b, child: Text(b)))
                .toList(),
            onChanged: (_submitting || _municipality == null)
                ? null
                : (v) => setState(() => _barangay = v),
            validator: (v) => v == null ? 'Required' : null,
          ),
              const SizedBox(height: 12),
              _fieldLabel('Map Pin / Get Location', required: true),
              EstablishmentLocationCapture(
            latitude: _latitude,
            longitude: _longitude,
            busy: _locating || _submitting,
            municipalityId: _municipality == null
                ? null
                : getMunicipalityIdFromName(_municipality),
            onBusyChanged: (b) {
              if (mounted) setState(() => _locating = b);
            },
            onChanged: (pin) {
              if (mounted) {
                setState(() {
                  _latitude = pin.latitude;
                  _longitude = pin.longitude;
                });
              }
            },
          ),
            ],
          ),
          const SizedBox(height: 14),
          _formSection(
            title: 'Account Setup',
            icon: Icons.lock_person_outlined,
            children: [
              _fieldLabel('Year Established', required: true),
              _glassDropdown<int>(
                value: _yearEstablished,
                hint: 'Select year established',
                icon: Icons.calendar_today,
                items: _years
                    .map(
                      (y) => DropdownMenuItem(value: y, child: Text('$y')),
                    )
                    .toList(),
                onChanged: _submitting
                    ? null
                    : (v) => setState(() => _yearEstablished = v),
                validator: (v) => v == null ? 'Required' : null,
              ),
              const SizedBox(height: 12),
              _fieldLabel('Username', required: true),
              TextFormField(
                controller: _usernameController,
                focusNode: _usernameFocus,
                style: _fieldTextStyle,
                cursorColor:
                    _isDesktopGlass ? Colors.white : AppTheme.brandOrange,
                autocorrect: false,
                textInputAction: TextInputAction.next,
                onFieldSubmitted: (_) => _passwordFocus.requestFocus(),
                decoration: _dec(
                  hint: 'Enter your username',
                  icon: Icons.person,
                ),
                validator: UsernameRegistryService.validateFormat,
              ),
              const SizedBox(height: 12),
              _fieldLabel('Password', required: true),
              TextFormField(
                controller: _passwordController,
                focusNode: _passwordFocus,
                style: _fieldTextStyle,
                cursorColor:
                    _isDesktopGlass ? Colors.white : AppTheme.brandOrange,
                obscureText: _obscurePassword,
                enableInteractiveSelection: true,
                autovalidateMode: AutovalidateMode.onUserInteraction,
                textInputAction: TextInputAction.next,
                onChanged: (_) => _onPasswordEdited(),
                onFieldSubmitted: (_) => _confirmPasswordFocus.requestFocus(),
                decoration: _dec(
                  hint: 'At least 6 characters',
                  icon: Icons.lock_outline,
                  suffix: IconButton(
                    icon: Icon(
                      _obscurePassword
                          ? Icons.visibility_off_outlined
                          : Icons.visibility_outlined,
                      color: _fieldIconColor,
                    ),
                    onPressed: () =>
                        setState(() => _obscurePassword = !_obscurePassword),
                  ),
                ),
                validator: validateSimplePassword,
              ),
              const SizedBox(height: 12),
              _fieldLabel('Confirm Password', required: true),
              TextFormField(
                key: _confirmPasswordFieldKey,
                controller: _confirmPasswordController,
                focusNode: _confirmPasswordFocus,
                style: _fieldTextStyle,
                cursorColor:
                    _isDesktopGlass ? Colors.white : AppTheme.brandOrange,
                obscureText: _obscureConfirm,
                enableInteractiveSelection: true,
                autovalidateMode: AutovalidateMode.onUserInteraction,
                textInputAction: TextInputAction.done,
                onFieldSubmitted: (_) {
                  if (!_submitting) unawaited(_submit());
                },
                decoration: _dec(
                  hint: 'Confirm your password',
                  icon: Icons.lock_outline,
                  suffix: IconButton(
                    icon: Icon(
                      _obscureConfirm
                          ? Icons.visibility_off_outlined
                          : Icons.visibility_outlined,
                      color: _fieldIconColor,
                    ),
                    onPressed: () =>
                        setState(() => _obscureConfirm = !_obscureConfirm),
                  ),
                ),
                validator: (v) {
                  if (v == null || v.isEmpty) return 'Required';
                  if (v != _passwordController.text) {
                    return 'Passwords do not match.';
                  }
                  return null;
                },
              ),
            ],
          ),
          const SizedBox(height: 18),
          _createAccountButton(),
        ],
      ),
    );

    final form = Theme(
      data: Theme.of(context).copyWith(
        hintColor: const Color(0xFF9CA3AF),
        textTheme: Theme.of(context).textTheme.apply(
              bodyColor: _isDesktopGlass ? Colors.white : const Color(0xFF1C1917),
              displayColor:
                  _isDesktopGlass ? Colors.white : const Color(0xFF1C1917),
            ),
        inputDecorationTheme: InputDecorationTheme(
          hintStyle: _hintTextStyle,
        ),
      ),
      child: _signupStep == 0
          ? SignupEnterToContinue(
              onEnter: _submitting ? null : _continueFromLegal,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _brandHeader(showTitle: false),
                  const SizedBox(height: 16),
                  TouristSignupSectionHeader(
                    title: 'Terms & Data Privacy',
                    description:
                        'Open both sections below, then agree to continue.',
                    icon: Icons.verified_user_outlined,
                    onDark: _isDesktopGlass,
                  ),
                  _buildLegalSection(),
                  const SizedBox(height: 28),
                  FilledButton(
                    onPressed: _submitting ? null : _continueFromLegal,
                    style: FilledButton.styleFrom(
                      backgroundColor: AppTheme.brandOrange,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                    ),
                    child: const Text(
                      'Continue to registration',
                      style: TextStyle(fontWeight: FontWeight.w800),
                    ),
                  ),
                ],
              ),
            )
          : formBody,
    );

    if (_isDesktopGlass) {
      return Scaffold(
        backgroundColor: Colors.transparent,
        body: WebGlassAuthScaffold(
          maxWidth: 560,
          child: WebGlassAuthCard(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(28, 20, 28, 28),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Align(
                    alignment: Alignment.centerLeft,
                    child: WebGlassBackButton(onPressed: _onBack),
                  ),
                  const SizedBox(height: 12),
                  ConstrainedBox(
                    constraints: BoxConstraints(
                      maxHeight: MediaQuery.sizeOf(context).height * 0.78,
                    ),
                    child: SingleChildScrollView(child: form),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      resizeToAvoidBottomInset: true,
      appBar: AppBar(
        backgroundColor: AppTheme.brandOrange,
        foregroundColor: Colors.white,
        title: Text(
          _signupStep == 0 ? 'Terms & Privacy' : 'Establishment signup',
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: _onBack,
        ),
      ),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            return SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
              child: ConstrainedBox(
                constraints: BoxConstraints(minWidth: constraints.maxWidth),
                child: _signupStep == 0 ? SignupLegalCard(child: form) : form,
              ),
            );
          },
        ),
      ),
    );
  }
}

class _SuggestCategoryDialog extends StatefulWidget {
  const _SuggestCategoryDialog({
    required this.official,
    this.alreadySuggested,
  });

  final List<String> official;
  final String? alreadySuggested;

  @override
  State<_SuggestCategoryDialog> createState() => _SuggestCategoryDialogState();
}

class _SuggestCategoryDialogState extends State<_SuggestCategoryDialog> {
  final _controller = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final msg = EstablishmentCategoryService.validateSuggestion(
      raw: _controller.text,
      official: widget.official,
      alreadySuggested: widget.alreadySuggested,
    );
    if (msg != null) {
      setState(() => _error = msg);
      return;
    }
    Navigator.pop(context, EstablishmentCategoryNames.cleaned(_controller.text));
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: const Text('Suggest a category'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'OPTACA will review this before it is added to the official list. '
            'You can finish signup with this category marked as pending review.',
            style: TextStyle(
              fontSize: 13,
              height: 1.35,
              color: Colors.grey.shade700,
            ),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _controller,
            textCapitalization: TextCapitalization.words,
            autofocus: true,
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => _submit(),
            decoration: InputDecoration(
              labelText: 'Category name',
              hintText: 'Enter a category name',
              errorText: _error,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _submit,
          style: FilledButton.styleFrom(backgroundColor: AppTheme.brandOrange),
          child: const Text('Use this category'),
        ),
      ],
    );
  }
}

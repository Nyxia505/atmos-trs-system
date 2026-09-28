import 'dart:async' show unawaited;

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart' show debugPrint, kIsWeb;
import 'package:flutter/material.dart';
import 'package:atmos_trs_system/config/app_theme.dart';
import 'package:atmos_trs_system/config/session_storage.dart';
import 'package:atmos_trs_system/data/misamis_occidental_municipalities.dart';
import 'package:atmos_trs_system/models/municipality.dart';
import 'package:atmos_trs_system/services/otp_delivery_service.dart';
import 'package:atmos_trs_system/services/otp_service.dart';
import 'package:atmos_trs_system/services/pending_lgu_registration_cache.dart';
import 'package:atmos_trs_system/services/push_notification_service.dart';
import 'package:atmos_trs_system/services/registration_rollback_service.dart';
import 'package:atmos_trs_system/utils/email_utils.dart';
import 'package:atmos_trs_system/utils/signup_field_validation.dart';
import 'package:atmos_trs_system/widgets/dial_code_mobile_field.dart';
import 'package:atmos_trs_system/widgets/signup_legal_consent.dart';
import 'package:atmos_trs_system/widgets/tourist_signup_chrome.dart';
import 'package:atmos_trs_system/widgets/web_glass_auth_scaffold.dart';

/// Self-registration for municipal LGU tourism office accounts.
class LguSignupScreen extends StatefulWidget {
  const LguSignupScreen({super.key});

  @override
  State<LguSignupScreen> createState() => _LguSignupScreenState();
}

class _LguSignupScreenState extends State<LguSignupScreen> {
  final _formKey = GlobalKey<FormState>();
  final _officeNameController = TextEditingController();
  final _contactPersonController = TextEditingController();
  final _contactController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  final _contactPersonFocus = FocusNode();
  final _contactFocus = FocusNode();
  final _emailFocus = FocusNode();
  final _passwordFocus = FocusNode();
  final _confirmPasswordFocus = FocusNode();

  String _contactDialCode = '+63';
  String? _municipalityId;
  late final List<Municipality> _municipalities =
      List<Municipality>.unmodifiable(getMisamisOccidentalMunicipalities());
  bool _obscurePassword = true;
  bool _obscureConfirm = true;
  bool _agreeToTerms = false;
  bool _privacyOpened = false;
  bool _termsOpened = false;
  bool _privacyExpanded = false;
  bool _termsExpanded = false;
  bool _submitting = false;

  /// 0 = Terms & Privacy first; 1 = registration fields.
  int _signupStep = 0;

  bool get _isDesktopGlass =>
      kIsWeb && MediaQuery.sizeOf(context).width >= kWebGlassAuthBreakpoint;

  bool get _legalReviewComplete => _privacyOpened && _termsOpened;

  Municipality? get _selectedMunicipality {
    final id = _municipalityId;
    if (id == null || id.isEmpty) return null;
    for (final m in _municipalities) {
      if (m.id == id) return m;
    }
    return null;
  }

  @override
  void dispose() {
    _officeNameController.dispose();
    _contactPersonController.dispose();
    _contactController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    _contactPersonFocus.dispose();
    _contactFocus.dispose();
    _emailFocus.dispose();
    _passwordFocus.dispose();
    _confirmPasswordFocus.dispose();
    super.dispose();
  }

  TextStyle get _fieldTextStyle => TextStyle(
        color: _isDesktopGlass ? Colors.white : const Color(0xFF1C1917),
        fontSize: 16,
        fontWeight: FontWeight.w600,
        height: 1.35,
      );

  TextStyle get _hintTextStyle => const TextStyle(
        // Match tourist signup muted grey placeholders.
        color: Color(0xFF9CA3AF),
        fontSize: 15,
        fontWeight: FontWeight.w400,
        letterSpacing: 0.1,
        height: 1.25,
      );

  TextStyle get _dropdownItemStyle => const TextStyle(
        color: Color(0xFF1C1917),
        fontSize: 15,
        fontWeight: FontWeight.w600,
      );

  Color get _fieldIconColor =>
      _isDesktopGlass ? Colors.white : const Color(0xFF78716C);

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

  Widget _sectionLabel(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8, top: 4),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w800,
          color: _isDesktopGlass ? Colors.white : const Color(0xFF292524),
        ),
      ),
    );
  }

  Widget _dropdownHint(String text) => Text(
        text,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: _hintTextStyle,
      );

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

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    if (!_legalReviewComplete || !_agreeToTerms) {
      setState(() => _signupStep = 0);
      _snack('Please complete Terms & Data Privacy first.');
      return;
    }
    if (_municipalityId == null || _selectedMunicipality == null) {
      _snack('Please select a municipality.');
      return;
    }

    final email = normalizeEmail(_emailController.text);
    final password = _passwordController.text;
    final officeName = _officeNameController.text.trim();
    final contactPerson = _contactPersonController.text.trim();
    final contact = composeE164Mobile(_contactDialCode, _contactController.text);
    final mun = _selectedMunicipality!;

    setState(() => _submitting = true);
    String? createdUid;

    try {
      if (Firebase.apps.isEmpty) {
        _snack('Firebase is not ready. Try again.');
        return;
      }

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

      final otp = OtpService.generateSixDigitOtp();
      await OtpService.saveOtp(uid: uid, otp: otp, email: email);

      if (!kIsWeb) {
        unawaited(ensureEmailOtpNotificationSupport());
        unawaited(syncFcmTokenToUserDoc(uid));
      }

      final delivery = await OtpDeliveryService.deliverVerificationCode(
        uid: uid,
        email: email,
        displayName: contactPerson.isNotEmpty ? contactPerson : officeName,
        otp: otp,
        mobile: contact,
        notifyOnThisDevice: false,
        trySms: false,
        otpAlreadyInFirestore: true,
      );
      if (!delivery.canCompleteRegistration) {
        await RegistrationRollbackService.rollback(uid);
        createdUid = null;
        _snack(
          'Verification code could not be saved. Your account was not created.',
        );
        return;
      }

      final userData = PendingLguRegistrationCache.jsonSafeMap({
        'firebaseUid': uid,
        'email': email,
        'fullName': contactPerson.isNotEmpty ? contactPerson : officeName,
        'officeName': officeName,
        'contactNumber': contact,
        'role': 'tourism',
        'municipality': mun.name,
        'municipalityId': mun.id,
        'isVerified': false,
        'status': 'pending',
      });

      await PendingLguRegistrationCache.save(
        PendingLguRegistration(
          uid: uid,
          contactEmail: email,
          authEmail: email,
          userData: userData,
        ),
      );

      await SessionStorage.saveSession(
        uid,
        role: UserRole.tourism,
        email: email,
        municipalityId: mun.id,
      );

      if (!mounted) return;
      Navigator.pushReplacementNamed(
        context,
        '/verify-otp',
        arguments: {
          'contactEmail': email,
          'fromSignup': true,
          'accountType': 'lgu',
        },
      );
    } on FirebaseAuthException catch (e) {
      debugPrint('[LGU-SIGNUP] Auth error: ${e.code} ${e.message}');
      if (createdUid != null) {
        await RegistrationRollbackService.rollback(createdUid);
      }
      _snack(_authErrorMessage(e));
    } catch (e, st) {
      debugPrint('[LGU-SIGNUP] failed: $e\n$st');
      if (createdUid != null) {
        await RegistrationRollbackService.rollback(createdUid);
      }
      _snack('Registration failed: $e');
    } finally {
      if (mounted) setState(() => _submitting = false);
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
            'We collect account and office details for LGU tourism operations '
                'and provincial coordination in Misamis Occidental.',
            'Data may include office name, contact person, email, phone, and '
                'municipality assignment.',
            'You may request access or correction through the Provincial '
                'Tourism Office.',
          ],
        ),
        const SizedBox(height: 10),
        SignupLegalExpansionCard(
          onDark: _isDesktopGlass,
          title: 'Terms and Conditions',
          subtitle: 'LGU tourism office responsibilities',
          icon: Icons.description_outlined,
          expanded: _termsExpanded,
          reviewed: _termsOpened,
          onExpandedChanged: (v) => setState(() {
            _termsExpanded = v;
            if (v) _termsOpened = true;
          }),
          bullets: const [
            'You confirm you are authorized to register for this municipality’s '
                'tourism office account.',
            'ATMOS-TRS LGU access is for official tourism registration, '
                'check-in, and reporting processes only.',
            'Misuse or false representation may result in restricted access.',
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

  @override
  Widget build(BuildContext context) {
    final formBody = Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'LGU Tourism Office',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.w800,
              color: _isDesktopGlass ? Colors.white : const Color(0xFF1C1917),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Register your municipal tourism office',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: _isDesktopGlass ? Colors.white : const Color(0xFF78716C),
            ),
          ),
          const SizedBox(height: 20),
          _sectionLabel('Municipality / City'),
          DropdownButtonFormField<String>(
            // ignore: deprecated_member_use
            value: _municipalityId,
            isExpanded: true,
            hint: _dropdownHint('Select your municipality'),
            decoration: _dec(
              hint: 'Select your municipality',
              icon: Icons.location_city,
            ).copyWith(hintText: null),
            dropdownColor: Colors.white,
            iconEnabledColor:
                _isDesktopGlass ? Colors.white : const Color(0xFF78716C),
            style: _fieldTextStyle,
            selectedItemBuilder: (_) => [
              for (final m in _municipalities)
                Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: Text(
                    m.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: _fieldTextStyle,
                  ),
                ),
            ],
            items: [
              for (final m in _municipalities)
                DropdownMenuItem<String>(
                  value: m.id,
                  child: Text(m.name, style: _dropdownItemStyle),
                ),
            ],
            onChanged: _submitting
                ? null
                : (v) => setState(() => _municipalityId = v),
            validator: (v) =>
                (v == null || v.isEmpty) ? 'Required' : null,
          ),
          const SizedBox(height: 12),
          _sectionLabel('Tourism Office Name'),
          TextFormField(
            controller: _officeNameController,
            style: _fieldTextStyle,
            cursorColor: _isDesktopGlass ? Colors.white : AppTheme.brandOrange,
            textCapitalization: TextCapitalization.words,
            textInputAction: TextInputAction.next,
            onFieldSubmitted: (_) => _contactPersonFocus.requestFocus(),
            decoration: _dec(
              hint: 'Enter your tourism office name',
              icon: Icons.account_balance_rounded,
            ),
            validator: (v) =>
                (v == null || v.trim().isEmpty) ? 'Required' : null,
          ),
          const SizedBox(height: 12),
          _sectionLabel('Contact Person'),
          TextFormField(
            controller: _contactPersonController,
            focusNode: _contactPersonFocus,
            style: _fieldTextStyle,
            cursorColor: _isDesktopGlass ? Colors.white : AppTheme.brandOrange,
            textCapitalization: TextCapitalization.words,
            textInputAction: TextInputAction.next,
            onFieldSubmitted: (_) => _contactFocus.requestFocus(),
            decoration: _dec(
              hint: 'Enter officer / staff full name',
              icon: Icons.badge_outlined,
            ),
            validator: (v) =>
                (v == null || v.trim().isEmpty) ? 'Required' : null,
          ),
          const SizedBox(height: 12),
          _sectionLabel('Contact Number'),
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
          _sectionLabel('Email Address'),
          TextFormField(
            controller: _emailController,
            focusNode: _emailFocus,
            style: _fieldTextStyle,
            cursorColor: _isDesktopGlass ? Colors.white : AppTheme.brandOrange,
            keyboardType: TextInputType.emailAddress,
            autocorrect: false,
            textInputAction: TextInputAction.next,
            onFieldSubmitted: (_) => _passwordFocus.requestFocus(),
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
              'your LGU dashboard opens.',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: _isDesktopGlass
                    ? Colors.white.withValues(alpha: 0.9)
                    : const Color(0xFF78716C),
              ),
            ),
          ),
          const SizedBox(height: 12),
          _sectionLabel('Password'),
          TextFormField(
            controller: _passwordController,
            focusNode: _passwordFocus,
            style: _fieldTextStyle,
            cursorColor: _isDesktopGlass ? Colors.white : AppTheme.brandOrange,
            obscureText: _obscurePassword,
            textInputAction: TextInputAction.next,
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
          _sectionLabel('Confirm Password'),
          TextFormField(
            controller: _confirmPasswordController,
            focusNode: _confirmPasswordFocus,
            style: _fieldTextStyle,
            cursorColor: _isDesktopGlass ? Colors.white : AppTheme.brandOrange,
            obscureText: _obscureConfirm,
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
          const SizedBox(height: 16),
          FilledButton(
            onPressed: _submitting ? null : _submit,
            style: FilledButton.styleFrom(
              backgroundColor: AppTheme.brandOrange,
              padding: const EdgeInsets.symmetric(vertical: 16),
            ),
            child: _submitting
                ? const SizedBox(
                    height: 22,
                    width: 22,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.5,
                      color: Colors.white,
                    ),
                  )
                : const Text(
                    'Create account',
                    style: TextStyle(fontWeight: FontWeight.w800),
                  ),
          ),
        ],
      ),
    );

    final form = Theme(
      data: Theme.of(context).copyWith(
        hintColor: const Color(0xFF9CA3AF),
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
      appBar: AppBar(
        backgroundColor: AppTheme.brandOrange,
        foregroundColor: Colors.white,
        title: Text(_signupStep == 0 ? 'Terms & Privacy' : 'LGU signup'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: _onBack,
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
          child: _signupStep == 0 ? SignupLegalCard(child: form) : form,
        ),
      ),
    );
  }
}

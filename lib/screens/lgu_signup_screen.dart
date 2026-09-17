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
    super.dispose();
  }

  TextStyle get _fieldTextStyle => TextStyle(
        color: _isDesktopGlass ? Colors.white : const Color(0xFF1C1917),
        fontSize: 16,
        fontWeight: FontWeight.w600,
        height: 1.35,
      );

  TextStyle get _hintTextStyle => TextStyle(
        color: _isDesktopGlass
            ? Colors.white.withValues(alpha: 0.95)
            : const Color(0xFF57534E),
        fontSize: 15,
        fontWeight: FontWeight.w600,
      );

  TextStyle get _dropdownItemStyle => const TextStyle(
        color: Color(0xFF1C1917),
        fontSize: 15,
        fontWeight: FontWeight.w600,
      );

  Color get _fieldIconColor =>
      _isDesktopGlass ? Colors.white : const Color(0xFF78716C);

  Color get _legalTitleColor =>
      _isDesktopGlass ? Colors.white : const Color(0xFF1C1917);

  Color get _legalBodyColor => _isDesktopGlass
      ? Colors.white.withValues(alpha: 0.92)
      : const Color(0xFF44403C);

  Color get _legalMutedColor => _isDesktopGlass
      ? Colors.white.withValues(alpha: 0.7)
      : const Color(0xFF78716C);

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
    final contact = _contactController.text.trim();
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
        notifyOnThisDevice: !kIsWeb,
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
        return 'Password is too weak. Use 8+ characters with upper, lower, and a digit.';
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
                fontSize: 13,
                color: _legalBodyColor,
                height: 1.5,
                fontWeight: FontWeight.w500,
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
    required bool expanded,
    required bool reviewed,
    required ValueChanged<bool> onExpandedChanged,
    required List<String> bullets,
  }) {
    return Material(
      color: _isDesktopGlass
          ? Colors.black.withValues(alpha: 0.28)
          : Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: reviewed
              ? accent.withValues(alpha: _isDesktopGlass ? 0.75 : 0.5)
              : (_isDesktopGlass
                  ? Colors.white.withValues(alpha: 0.22)
                  : const Color(0xFFE7E5E4)),
          width: reviewed ? 1.5 : 1,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          InkWell(
            onTap: () => onExpandedChanged(!expanded),
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
                ),
              ),
              child: Row(
                children: [
                  Icon(icon, color: _isDesktopGlass ? Colors.white : accent),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w800,
                            color: _legalTitleColor,
                          ),
                        ),
                        Text(
                          subtitle,
                          style: TextStyle(
                            fontSize: 12,
                            color: _legalMutedColor,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Icon(
                    expanded
                        ? Icons.expand_less_rounded
                        : Icons.expand_more_rounded,
                    color: _legalTitleColor,
                  ),
                ],
              ),
            ),
          ),
          if (expanded)
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
              child: Column(
                children: bullets.map(_buildLegalBullet).toList(),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildLegalSection() {
    const privacyBlue = Color(0xFF2563EB);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Please review before continuing',
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w800,
            color: _legalTitleColor,
          ),
        ),
        const SizedBox(height: 12),
        _buildLegalExpansionCard(
          title: 'Data Privacy Act (RA 10173)',
          subtitle: 'Collection, use, and your rights',
          icon: Icons.shield_outlined,
          accent: privacyBlue,
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
        const SizedBox(height: 12),
        _buildLegalExpansionCard(
          title: 'Terms and Conditions',
          subtitle: 'LGU tourism office responsibilities',
          icon: Icons.description_outlined,
          accent: AppTheme.brandOrange,
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
        const SizedBox(height: 14),
        Material(
          color: _agreeToTerms
              ? AppTheme.brandOrange.withValues(
                  alpha: _isDesktopGlass ? 0.28 : 0.08,
                )
              : (_isDesktopGlass
                  ? Colors.black.withValues(alpha: 0.28)
                  : const Color(0xFFF8FAFC)),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
            side: BorderSide(
              color: _agreeToTerms
                  ? AppTheme.brandOrange
                  : (_isDesktopGlass
                      ? Colors.white.withValues(alpha: 0.28)
                      : const Color(0xFFE7E5E4)),
              width: _agreeToTerms ? 2 : 1,
            ),
          ),
          child: InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: !_legalReviewComplete || _submitting
                ? null
                : () => setState(() => _agreeToTerms = !_agreeToTerms),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 24,
                    height: 24,
                    decoration: BoxDecoration(
                      color: _agreeToTerms
                          ? AppTheme.brandOrange
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(
                        color: _agreeToTerms
                            ? AppTheme.brandOrange
                            : (_isDesktopGlass
                                ? Colors.white.withValues(alpha: 0.7)
                                : const Color(0xFFA8A29E)),
                        width: 2,
                      ),
                    ),
                    child: _agreeToTerms
                        ? const Icon(
                            Icons.check_rounded,
                            size: 16,
                            color: Colors.white,
                          )
                        : null,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'I have read and agree to the Terms and Conditions and '
                      'the Data Privacy Policy (RA 10173) of ATMOS-TRS.',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        height: 1.45,
                        color: _legalBodyColor,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
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
            hint: _dropdownHint('Select municipality'),
            decoration: _dec(
              hint: 'Select municipality',
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
            decoration: _dec(
              hint: 'e.g. Oroquieta City Tourism Office',
              icon: Icons.account_balance_rounded,
            ),
            validator: (v) =>
                (v == null || v.trim().isEmpty) ? 'Required' : null,
          ),
          const SizedBox(height: 12),
          _sectionLabel('Contact Person'),
          TextFormField(
            controller: _contactPersonController,
            style: _fieldTextStyle,
            cursorColor: _isDesktopGlass ? Colors.white : AppTheme.brandOrange,
            textCapitalization: TextCapitalization.words,
            decoration: _dec(
              hint: 'Full name of officer / staff',
              icon: Icons.badge_outlined,
            ),
            validator: (v) =>
                (v == null || v.trim().isEmpty) ? 'Required' : null,
          ),
          const SizedBox(height: 12),
          _sectionLabel('Contact Number'),
          TextFormField(
            controller: _contactController,
            style: _fieldTextStyle,
            cursorColor: _isDesktopGlass ? Colors.white : AppTheme.brandOrange,
            keyboardType: TextInputType.phone,
            decoration: _dec(hint: '09XXXXXXXXX', icon: Icons.phone_rounded),
            validator: validatePhilippineMobile,
          ),
          const SizedBox(height: 12),
          _sectionLabel('Email Address'),
          TextFormField(
            controller: _emailController,
            style: _fieldTextStyle,
            cursorColor: _isDesktopGlass ? Colors.white : AppTheme.brandOrange,
            keyboardType: TextInputType.emailAddress,
            autocorrect: false,
            decoration: _dec(hint: 'email@example.com', icon: Icons.email),
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
            style: _fieldTextStyle,
            cursorColor: _isDesktopGlass ? Colors.white : AppTheme.brandOrange,
            obscureText: _obscurePassword,
            decoration: _dec(
              hint: 'Create password',
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
            validator: validateStrongPassword,
          ),
          const SizedBox(height: 12),
          _sectionLabel('Confirm Password'),
          TextFormField(
            controller: _confirmPasswordController,
            style: _fieldTextStyle,
            cursorColor: _isDesktopGlass ? Colors.white : AppTheme.brandOrange,
            obscureText: _obscureConfirm,
            decoration: _dec(
              hint: 'Re-enter password',
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
        hintColor: _isDesktopGlass
            ? Colors.white.withValues(alpha: 0.95)
            : const Color(0xFF57534E),
      ),
      child: _signupStep == 0
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Terms & Data Privacy',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w800,
                    color: _isDesktopGlass
                        ? Colors.white
                        : const Color(0xFF1C1917),
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Review how ATMOS-TRS handles your information, then agree to continue.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: _isDesktopGlass
                        ? Colors.white
                        : const Color(0xFF78716C),
                  ),
                ),
                const SizedBox(height: 20),
                _buildLegalSection(),
                const SizedBox(height: 16),
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
          child: form,
        ),
      ),
    );
  }
}

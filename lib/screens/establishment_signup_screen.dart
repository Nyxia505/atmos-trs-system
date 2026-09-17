import 'dart:async' show unawaited;

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart' show debugPrint, kIsWeb;
import 'package:flutter/material.dart';
import 'package:atmos_trs_system/config/app_theme.dart';
import 'package:atmos_trs_system/config/session_storage.dart';
import 'package:atmos_trs_system/data/misamis_occidental_barangays.dart';
import 'package:atmos_trs_system/services/establishment_registration_service.dart';
import 'package:atmos_trs_system/services/otp_delivery_service.dart';
import 'package:atmos_trs_system/services/otp_service.dart';
import 'package:atmos_trs_system/services/pending_establishment_registration_cache.dart';
import 'package:atmos_trs_system/services/push_notification_service.dart';
import 'package:atmos_trs_system/services/registration_rollback_service.dart';
import 'package:atmos_trs_system/services/username_registry_service.dart';
import 'package:atmos_trs_system/utils/email_utils.dart';
import 'package:atmos_trs_system/utils/municipality_helper.dart';
import 'package:atmos_trs_system/utils/signup_field_validation.dart';
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
  final _contactController = TextEditingController();
  final _emailController = TextEditingController();
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();

  String? _category;
  String? _municipality;
  String? _barangay;
  int? _yearEstablished;
  bool _obscurePassword = true;
  bool _obscureConfirm = true;
  bool _agreeToTerms = false;
  bool _privacyOpened = false;
  bool _termsOpened = false;
  bool _submitting = false;

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

  @override
  void dispose() {
    _businessNameController.dispose();
    _ownerNameController.dispose();
    _contactController.dispose();
    _emailController.dispose();
    _usernameController.dispose();
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

  TextStyle get _dropdownItemStyle => const TextStyle(
        color: Color(0xFF1C1917),
        fontSize: 15,
        fontWeight: FontWeight.w600,
      );

  Color get _fieldIconColor =>
      _isDesktopGlass ? Colors.white : const Color(0xFF78716C);

  TextStyle get _hintTextStyle => TextStyle(
        color: _isDesktopGlass
            ? Colors.white.withValues(alpha: 0.95)
            : const Color(0xFF57534E),
        fontSize: 15,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.1,
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
        // Keep decoration hint empty for dropdowns; they use the [hint] widget.
        // Text fields still show this hintText with a bright style.
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
      // Explicit white hint — decoration hintStyle alone is ignored by dropdowns.
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

  Color get _legalTitleColor =>
      _isDesktopGlass ? Colors.white : const Color(0xFF1C1917);

  Color get _legalBodyColor => _isDesktopGlass
      ? Colors.white.withValues(alpha: 0.92)
      : const Color(0xFF44403C);

  Color get _legalMutedColor => _isDesktopGlass
      ? Colors.white.withValues(alpha: 0.7)
      : const Color(0xFF78716C);

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
                  : const Color(0xFFE7E5E4)),
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
    required bool expanded,
    required bool reviewed,
    required ValueChanged<bool> onExpandedChanged,
    required List<String> bullets,
  }) {
    return Material(
      color: _isDesktopGlass
          ? Colors.black.withValues(alpha: 0.28)
          : Colors.white,
      elevation: expanded ? 2 : 0,
      shadowColor: accent.withValues(alpha: 0.12),
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
                        Text(
                          title,
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w800,
                            color: _legalTitleColor,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          subtitle,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                            color: _legalMutedColor,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (reviewed)
                    Padding(
                      padding: const EdgeInsets.only(right: 4),
                      child: Icon(
                        Icons.check_circle_rounded,
                        size: 18,
                        color: _isDesktopGlass ? Colors.white : accent,
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
                crossAxisAlignment: CrossAxisAlignment.start,
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
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: _buildLegalProgressChip(
                label: 'Data Privacy',
                done: _privacyOpened,
                icon: Icons.shield_outlined,
                accent: privacyBlue,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _buildLegalProgressChip(
                label: 'Terms',
                done: _termsOpened,
                icon: Icons.description_outlined,
                accent: AppTheme.brandOrange,
              ),
            ),
          ],
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
        const SizedBox(height: 12),
        _buildLegalExpansionCard(
          title: 'Terms and Conditions',
          subtitle: 'Your responsibilities as a registrant',
          icon: Icons.description_outlined,
          accent: AppTheme.brandOrange,
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
                    margin: const EdgeInsets.only(top: 1),
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
                      'the Data Privacy Policy (Republic Act No. 10173) of '
                      'ATMOS-TRS.',
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
    if (_category == null ||
        _municipality == null ||
        _barangay == null ||
        _yearEstablished == null) {
      _snack('Please complete all required fields.');
      return;
    }

    final email = normalizeEmail(_emailController.text);
    final username = _usernameController.text.trim();
    final password = _passwordController.text;
    final businessName = _businessNameController.text.trim();
    final ownerName = _ownerNameController.text.trim();
    final contact = _contactController.text.trim();

    setState(() => _submitting = true);
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
      } catch (_) {
        await RegistrationRollbackService.rollback(uid);
        createdUid = null;
        _snack('This username was just taken. Choose another.');
        return;
      }

      final otp = OtpService.generateSixDigitOtp();
      await OtpService.saveOtp(uid: uid, otp: otp, email: email);

      if (!kIsWeb) {
        unawaited(ensureEmailOtpNotificationSupport());
        unawaited(syncFcmTokenToUserDoc(uid));
      }

      final delivery = await OtpDeliveryService.deliverVerificationCode(
        uid: uid,
        email: email,
        displayName: businessName,
        otp: otp,
        mobile: contact,
        notifyOnThisDevice: !kIsWeb,
        trySms: false,
        otpAlreadyInFirestore: true,
      );
      if (!delivery.canCompleteRegistration) {
        if (usernameClaimed) {
          await UsernameRegistryService.release(username);
        }
        await RegistrationRollbackService.rollback(uid);
        createdUid = null;
        _snack(
          'Verification code could not be saved. Your account was not created. '
          'Please try again.',
        );
        return;
      }

      final municipalityId = getMunicipalityIdFromName(_municipality);
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
        'yearEstablished': _yearEstablished,
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
        'ownerName': ownerName,
        'contactNumber': contact,
        'email': email,
        'username': username,
        'municipality': _municipality,
        'municipalityId': municipalityId,
        'barangay': _barangay,
        'location': '$_barangay, $_municipality, Misamis Occidental',
        'yearEstablished': _yearEstablished,
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
      Navigator.pushReplacementNamed(
        context,
        '/verify-otp',
        arguments: {
          'contactEmail': email,
          'fromSignup': true,
          'accountType': 'tourism_establishment',
        },
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

  Widget _sectionLabel(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8, top: 4),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.2,
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
        ),
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
          Text(
            'Tourism Establishment',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.w800,
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
          const SizedBox(height: 6),
          Text(
            'Register your business for ATMOS-TRS',
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
          const SizedBox(height: 20),
          _sectionLabel('Name of Business'),
          TextFormField(
            controller: _businessNameController,
            style: _fieldTextStyle,
            cursorColor: _isDesktopGlass ? Colors.white : AppTheme.brandOrange,
            textCapitalization: TextCapitalization.words,
            decoration: _dec(
              hint: 'Business name',
              icon: Icons.storefront_rounded,
            ),
            validator: (v) =>
                (v == null || v.trim().isEmpty) ? 'Required' : null,
          ),
          const SizedBox(height: 12),
          _sectionLabel('Category Type'),
          _glassDropdown<String>(
            value: _category,
            hint: 'Select category',
            icon: Icons.category,
            items: EstablishmentRegistrationService.categoryTypes
                .map(
                  (c) => DropdownMenuItem(value: c, child: Text(c)),
                )
                .toList(),
            onChanged: _submitting
                ? null
                : (v) => setState(() => _category = v),
            validator: (v) => v == null ? 'Required' : null,
          ),
          const SizedBox(height: 12),
          _sectionLabel('Name of Owner (from Business Permit)'),
          TextFormField(
            controller: _ownerNameController,
            style: _fieldTextStyle,
            cursorColor: _isDesktopGlass ? Colors.white : AppTheme.brandOrange,
            textCapitalization: TextCapitalization.words,
            decoration: _dec(
              hint: 'Owner full name',
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
            decoration: _dec(
              hint: '09XXXXXXXXX',
              icon: Icons.phone_rounded,
            ),
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
          const SizedBox(height: 12),
          _sectionLabel('Location — Municipality / City'),
          _glassDropdown<String>(
            value: _municipality,
            hint: 'Select municipality',
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
          _sectionLabel('Barangay'),
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
          _sectionLabel('Year Established'),
          _glassDropdown<int>(
            value: _yearEstablished,
            hint: 'Select year',
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
          _sectionLabel('Username'),
          TextFormField(
            controller: _usernameController,
            style: _fieldTextStyle,
            cursorColor: _isDesktopGlass ? Colors.white : AppTheme.brandOrange,
            autocorrect: false,
            decoration: _dec(hint: 'Unique username', icon: Icons.person),
            validator: UsernameRegistryService.validateFormat,
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
        title: Text(
          _signupStep == 0 ? 'Terms & Privacy' : 'Establishment signup',
        ),
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

import 'package:atmos_trs_system/config/app_theme.dart';
import 'package:atmos_trs_system/navigation/auth_navigation.dart';
import 'package:atmos_trs_system/navigation/guest_startup_routes.dart';
import 'package:atmos_trs_system/screens/verify_otp_screen.dart';
import 'package:atmos_trs_system/services/otp_delivery_service.dart';
import 'package:atmos_trs_system/services/qr_tourist_basic_registration_service.dart';
import 'package:atmos_trs_system/utils/signup_field_validation.dart';
import 'package:atmos_trs_system/widgets/atmos_brand_logo.dart';
import 'package:atmos_trs_system/widgets/signup_legal_consent.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// QR-first Create Account: exactly five basic questions, then a secure
/// password + consent step, then existing email OTP verification.
class QrTouristBasicSignupScreen extends StatefulWidget {
  const QrTouristBasicSignupScreen({super.key});

  @override
  State<QrTouristBasicSignupScreen> createState() =>
      _QrTouristBasicSignupScreenState();
}

class _QrTouristBasicSignupScreenState extends State<QrTouristBasicSignupScreen> {
  static const _bg = Color(0xFFFFF7ED);
  static const _text = Color(0xFF1F2937);
  static const _muted = Color(0xFF6B7280);

  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _origin = TextEditingController();
  final _mobile = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _confirm = TextEditingController();

  String? _nationality;
  String _dialCode = '+63';
  bool _stepSecure = false;
  bool _busy = false;
  bool _obscure = true;
  bool _agreed = false;
  bool _termsReviewed = false;
  bool _privacyReviewed = false;
  bool _termsExpanded = false;
  bool _privacyExpanded = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _origin.dispose();
    _mobile.dispose();
    _email.dispose();
    _password.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _continueFromQuestions() async {
    FocusManager.instance.primaryFocus?.unfocus();
    final err = QrTouristBasicRegistrationService.validateFiveQuestions(
      fullName: _name.text,
      nationality: _nationality,
      placeOfOrigin: _origin.text,
      mobileLocal: _mobile.text,
      dialCode: _dialCode,
      email: _email.text,
    );
    if (err != null) {
      setState(() => _error = err);
      return;
    }
    setState(() {
      _error = null;
      _stepSecure = true;
    });
  }

  Future<void> _submit() async {
    if (_busy) return;
    final secureErr = QrTouristBasicRegistrationService.validateSecureStep(
      password: _password.text,
      confirmPassword: _confirm.text,
      agreedToTerms: _agreed && _termsReviewed && _privacyReviewed,
    );
    if (secureErr != null) {
      setState(() => _error = secureErr);
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      TextInput.finishAutofillContext(shouldSave: false);
      final result = await QrTouristBasicRegistrationService.submitDeferred(
        fullName: _name.text,
        nationality: _nationality!,
        placeOfOrigin: _origin.text,
        mobileLocal: _mobile.text,
        dialCode: _dialCode,
        email: _email.text,
        password: _password.text,
      );
      if (!mounted) return;
      final delivery = result.delivery;
      final contact = result.contactEmail;
      final snackOk =
          delivery.emailSent || delivery.emailDeliveryPending || delivery.smsSent;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            snackOk
                ? OtpDeliveryResult.deliveryPendingMessage(contact)
                : delivery.messageForUser(contact),
          ),
          backgroundColor:
              snackOk ? Colors.green.shade700 : Colors.orange.shade800,
          behavior: SnackBarBehavior.floating,
        ),
      );
      Navigator.of(context).pushReplacement(
        verificationHandoffRoute(
          builder: (_) => const VerifyOtpScreen(),
          arguments: <String, dynamic>{
            'contactEmail': contact,
            'fromSignup': true,
            'fromQrBasicSignup': true,
            'otpAlreadySent': true,
            'emailDeliveryFailed': !delivery.canCompleteRegistration,
            'authDeferred': true,
          },
        ),
      );
    } catch (e) {
      if (!mounted) return;
      final msg = e.toString().replaceFirst(RegExp(r'^StateError:\s*'), '');
      setState(() {
        _busy = false;
        _error = msg;
      });
      if (msg.toLowerCase().contains('already registered')) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(msg),
            backgroundColor: Colors.orange.shade800,
            behavior: SnackBarBehavior.floating,
            action: SnackBarAction(
              label: 'Log In',
              textColor: Colors.white,
              onPressed: () {
                Navigator.pushReplacementNamed(
                  context,
                  GuestStartupRoutes.login,
                );
              },
            ),
          ),
        );
      }
    }
  }

  InputDecoration _dec(String label, {String? hint, Widget? prefix}) {
    return InputDecoration(
      labelText: label,
      hintText: hint,
      prefixIcon: prefix,
      filled: true,
      fillColor: Colors.white,
      isDense: true,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: AppTheme.brandOrange, width: 1.4),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: _bg,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: _text),
          onPressed: _busy
              ? null
              : () {
                  if (_stepSecure) {
                    setState(() {
                      _stepSecure = false;
                      _error = null;
                    });
                  } else {
                    Navigator.maybePop(context);
                  }
                },
        ),
        title: const AtmosBrandLogo(height: 32),
        centerTitle: true,
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 440),
            child: Form(
              key: _formKey,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
                children: [
                  Text(
                    _stepSecure
                        ? 'Secure your account'
                        : 'Create tourist account',
                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                      color: _text,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    _stepSecure
                        ? 'Choose your own password, then verify by email. '
                            'We never use shared or predictable passwords.'
                        : 'Answer five basic questions. New accommodation or '
                            'staff accounts are not created here.',
                    style: const TextStyle(
                      fontSize: 13.5,
                      height: 1.4,
                      color: _muted,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 18),
                  if (!_stepSecure) ..._buildQuestions() else ..._buildSecure(),
                  if (_error != null) ...[
                    const SizedBox(height: 12),
                    Text(
                      _error!,
                      style: TextStyle(
                        color: Colors.red.shade700,
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                      ),
                    ),
                  ],
                  const SizedBox(height: 20),
                  FilledButton(
                    onPressed: _busy
                        ? null
                        : (_stepSecure ? _submit : _continueFromQuestions),
                    style: FilledButton.styleFrom(
                      backgroundColor: AppTheme.brandOrange,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 15),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: _busy
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : Text(
                            _stepSecure
                                ? 'Verify email & create account'
                                : 'Continue',
                            style: const TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 15.5,
                            ),
                          ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> _buildQuestions() {
    return [
      TextField(
        controller: _name,
        textCapitalization: TextCapitalization.words,
        enabled: !_busy,
        decoration: _dec('1. Full Name', hint: 'Given name and surname'),
        onChanged: (_) {
          if (_error != null) setState(() => _error = null);
        },
      ),
      const SizedBox(height: 12),
      DropdownButtonFormField<String>(
        value: _nationality,
        decoration: _dec('2. Nationality'),
        items: [
          for (final n in QrTouristBasicRegistrationService.nationalities)
            DropdownMenuItem(value: n, child: Text(n)),
        ],
        onChanged: _busy
            ? null
            : (v) {
                setState(() {
                  _nationality = v;
                  if (v == 'Filipino' ||
                      v == 'Filipino (dual citizen)') {
                    _dialCode = '+63';
                  }
                  _error = null;
                });
              },
      ),
      const SizedBox(height: 12),
      TextField(
        controller: _origin,
        textCapitalization: TextCapitalization.words,
        enabled: !_busy,
        decoration: _dec(
          '3. Place of Origin',
          hint: 'City / municipality or home region',
        ),
        onChanged: (_) {
          if (_error != null) setState(() => _error = null);
        },
      ),
      const SizedBox(height: 12),
      Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 96,
            child: DropdownButtonFormField<String>(
              value: _dialCode,
              decoration: _dec('Code'),
              items: [
                for (final c in dialCodeOptionsFor(_dialCode))
                  DropdownMenuItem(value: c, child: Text(c)),
              ],
              onChanged: _busy
                  ? null
                  : (v) {
                      if (v == null) return;
                      setState(() => _dialCode = v);
                    },
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: TextField(
              controller: _mobile,
              enabled: !_busy,
              keyboardType: TextInputType.phone,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: _dec(
                '4. Contact Information',
                hint: _dialCode == '+63' ? '9171234567' : 'Phone number',
              ),
              onChanged: (_) {
                if (_error != null) setState(() => _error = null);
              },
            ),
          ),
        ],
      ),
      const SizedBox(height: 12),
      TextField(
        controller: _email,
        enabled: !_busy,
        keyboardType: TextInputType.emailAddress,
        autocorrect: false,
        decoration: _dec(
          '5. Email (account verification)',
          hint: 'Used to verify and sign in',
        ),
        onChanged: (_) {
          if (_error != null) setState(() => _error = null);
        },
      ),
    ];
  }

  List<Widget> _buildSecure() {
    return [
      TextField(
        controller: _password,
        enabled: !_busy,
        obscureText: _obscure,
        decoration: _dec('Create password').copyWith(
          suffixIcon: IconButton(
            onPressed: () => setState(() => _obscure = !_obscure),
            icon: Icon(
              _obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined,
            ),
          ),
        ),
      ),
      const SizedBox(height: 12),
      TextField(
        controller: _confirm,
        enabled: !_busy,
        obscureText: _obscure,
        decoration: _dec('Confirm password'),
      ),
      const SizedBox(height: 14),
      SignupLegalExpansionCard(
        title: 'Terms of Service',
        subtitle: 'Please open and review',
        icon: Icons.description_outlined,
        expanded: _termsExpanded,
        reviewed: _termsReviewed,
        onExpandedChanged: (v) => setState(() {
          _termsExpanded = v;
          if (v) _privacyExpanded = false;
        }),
        onScrolledToEnd: () => setState(() => _termsReviewed = true),
        bullets: const [
          'ATMOS TRS accounts are for tourism registration and visit services.',
          'Do not share your password or verification codes.',
          'False information may affect visitor analytics accuracy.',
        ],
      ),
      const SizedBox(height: 10),
      SignupLegalExpansionCard(
        title: 'Data Privacy',
        subtitle: 'Please open and review',
        icon: Icons.privacy_tip_outlined,
        expanded: _privacyExpanded,
        reviewed: _privacyReviewed,
        onExpandedChanged: (v) => setState(() {
          _privacyExpanded = v;
          if (v) _termsExpanded = false;
        }),
        onScrolledToEnd: () => setState(() => _privacyReviewed = true),
        bullets: const [
          'Your profile supports LGU and provincial tourism monitoring.',
          'Personal QR codes encode a server-verifiable tourist id, not email or phone.',
          'You can update profile details later from your account.',
        ],
      ),
      const SizedBox(height: 10),
      SignupLegalAgreementCard(
        agreed: _agreed,
        canAgree: _termsReviewed && _privacyReviewed && !_busy,
        onChanged: (v) => setState(() {
          _agreed = v;
          _error = null;
        }),
      ),
    ];
  }
}

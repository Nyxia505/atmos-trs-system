import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:atmos_trs_system/config/app_theme.dart';
import 'package:flutter/services.dart';
import 'package:atmos_trs_system/services/password_reset_service.dart';
import 'package:atmos_trs_system/services/push_notification_service.dart';
import 'package:atmos_trs_system/utils/email_utils.dart';
import 'package:atmos_trs_system/utils/logo_utils.dart';

enum _ForgotPasswordStep {
  enterEmail,
  enterCodeAndPassword,
  emailLinkSent,
  success,
}

/// Password recovery via 6-digit OTP (phone notification + inbox email).
class ForgotPasswordScreen extends StatefulWidget {
  const ForgotPasswordScreen({super.key, this.initialEmail});

  final String? initialEmail;

  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  final _emailFormKey = GlobalKey<FormState>();
  final _resetFormKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _otpController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();

  _ForgotPasswordStep _step = _ForgotPasswordStep.enterEmail;
  bool _isLoading = false;
  bool _resending = false;
  int _cooldown = 0;
  bool _obscurePassword = true;
  bool _obscureConfirm = true;
  String? _activeEmail;
  String? _deliveryHint;

  static const Color _backgroundCream = Color(0xFFFFF7ED);
  static const Color _textDark = Color(0xFF1A1A1A);
  static const Color _textMuted = Color(0xFF6B7280);
  static const Color _inputBorder = Color(0xFFE5E7EB);

  @override
  void initState() {
    super.initState();
    final initial = widget.initialEmail?.trim();
    if (initial != null && initial.isNotEmpty) {
      _emailController.text = initial;
    }
    if (!kIsWeb) {
      ensurePasswordResetNotificationSupport(
        onOtpFromPush: (otp) {
          if (!mounted) return;
          if (_otpController.text.isEmpty) {
            _otpController.text = otp;
          }
        },
      );
    }
  }

  @override
  void dispose() {
    if (!kIsWeb) {
      disposePasswordResetNotificationSupport();
    }
    _emailController.dispose();
    _otpController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  Future<void> _requestCode() async {
    if (!_emailFormKey.currentState!.validate()) return;
    if (Firebase.apps.isEmpty) {
      _showSnack('Firebase is not available. Please try again later.', isError: true);
      return;
    }

    setState(() => _isLoading = true);
    final email = normalizeEmail(_emailController.text);

    try {
      final result = await PasswordResetService.requestOtp(email);
      if (!mounted) return;
      _applyRequestResult(result);
    } on FirebaseFunctionsException catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      _showSnack(PasswordResetService.errorMessage(e), isError: true);
    } on FirebaseAuthException catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      _showSnack(PasswordResetService.authErrorMessage(e), isError: true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      _showSnack('Could not send reset instructions. Please try again.', isError: true);
    }
  }

  void _applyRequestResult(PasswordResetOtpRequestResult result) {
    setState(() {
      _isLoading = false;
      _activeEmail = result.email;
      _deliveryHint = PasswordResetService.messageForOtpRequest(result);
      if (result.emailLinkSent) {
        _step = _ForgotPasswordStep.emailLinkSent;
      } else if (result.accountFound) {
        _step = _ForgotPasswordStep.enterCodeAndPassword;
        _otpController.clear();
        _passwordController.clear();
        _confirmPasswordController.clear();
      } else {
        _step = _ForgotPasswordStep.emailLinkSent;
        _deliveryHint =
            'If an account exists for ${maskEmailForDisplay(result.email)}, '
            'you will receive reset instructions by email.';
      }
    });
    _showSnack(_deliveryHint!, isError: false);
  }

  Future<void> _resendCode() async {
    if (_cooldown > 0 || _activeEmail == null) return;
    setState(() => _resending = true);
    try {
      final result = await PasswordResetService.requestOtp(_activeEmail!);
      if (!mounted) return;
      _applyRequestResult(result);
      _startCooldown(60);
    } on FirebaseFunctionsException catch (e) {
      if (!mounted) return;
      _showSnack(PasswordResetService.errorMessage(e), isError: true);
    } on FirebaseAuthException catch (e) {
      if (!mounted) return;
      _showSnack(PasswordResetService.authErrorMessage(e), isError: true);
    } catch (_) {
      if (!mounted) return;
      _showSnack('Could not resend.', isError: true);
    } finally {
      if (mounted) setState(() => _resending = false);
    }
  }

  Future<void> _submitNewPassword() async {
    if (!_resetFormKey.currentState!.validate()) return;
    final email = _activeEmail ?? normalizeEmail(_emailController.text);
    final password = _passwordController.text;
    final confirm = _confirmPasswordController.text;
    if (password != confirm) {
      _showSnack('Passwords do not match.', isError: true);
      return;
    }

    setState(() => _isLoading = true);
    try {
      await PasswordResetService.completeReset(
        email: email,
        otp: _otpController.text,
        newPassword: password,
      );
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _step = _ForgotPasswordStep.success;
      });
    } on PasswordResetNeedsEmailLinkException {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _step = _ForgotPasswordStep.emailLinkSent;
        _deliveryHint =
            'The 6-digit code service is not available yet. '
            'We sent a reset link to your email — open it to set a new password.';
      });
      _showSnack(_deliveryHint!, isError: false);
    } on FirebaseFunctionsException catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      _showSnack(PasswordResetService.errorMessage(e), isError: true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      _showSnack('Could not reset password. Please try again.', isError: true);
    }
  }

  void _startCooldown(int seconds) {
    setState(() => _cooldown = seconds);
    Future.doWhile(() async {
      await Future<void>.delayed(const Duration(seconds: 1));
      if (!mounted) return false;
      setState(() => _cooldown = _cooldown - 1);
      return _cooldown > 0;
    });
  }

  void _showSnack(String message, {required bool isError}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? Colors.redAccent : const Color(0xFF059669),
      ),
    );
  }

  bool get _isWeb => MediaQuery.sizeOf(context).width >= 768;

  InputDecoration _inputDecoration({
    required String hint,
    Widget? suffixIcon,
  }) {
    return InputDecoration(
      hintText: hint,
      hintStyle: TextStyle(color: _textMuted.withValues(alpha: 0.6), fontSize: 14),
      suffixIcon: suffixIcon,
      filled: true,
      fillColor: Colors.white,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: _inputBorder, width: 1),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: BorderSide(color: AppTheme.brandOrange, width: 2),
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _backgroundCream,
      body: _isWeb ? _buildWebLayout() : _buildMobileLayout(),
    );
  }

  Widget _buildWebLayout() {
    return SizedBox.expand(
      child: Stack(
        fit: StackFit.expand,
        children: [
          Image.asset(
            'assets/images/oroquieta City plaza.jpeg',
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => Container(color: AppTheme.brandOrange),
          ),
          Container(color: Colors.black.withValues(alpha: 0.45)),
          Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 16),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 440),
                child: _buildCard(),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMobileLayout() {
    return SingleChildScrollView(child: _buildCard());
  }

  Widget _buildCard() {
    final header = Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: AppTheme.brandOrange,
        borderRadius: _isWeb
            ? const BorderRadius.only(
                topLeft: Radius.circular(24),
                topRight: Radius.circular(24),
              )
            : const BorderRadius.only(
                bottomLeft: Radius.circular(40),
                bottomRight: Radius.circular(40),
              ),
      ),
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 16, 24, 40),
          child: Column(
            children: [
              Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
                    onPressed: _isLoading ? null : () => Navigator.pop(context),
                    tooltip: 'Back to sign in',
                  ),
                  const Spacer(),
                ],
              ),
              const SizedBox(height: 8),
              Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 72),
                  child: TransparentLogo(height: 72, fit: BoxFit.contain),
                ),
              ),
              const SizedBox(height: 12),
              const Text(
                'Reset your password',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w800,
                  color: Colors.white,
                ),
              ),
            ],
          ),
        ),
      ),
    );

    final body = Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: _isWeb
            ? const BorderRadius.only(
                bottomLeft: Radius.circular(24),
                bottomRight: Radius.circular(24),
              )
            : BorderRadius.circular(24),
        boxShadow: _isWeb
            ? null
            : [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.06),
                  blurRadius: 24,
                  offset: const Offset(0, 4),
                ),
              ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: switch (_step) {
          _ForgotPasswordStep.enterEmail => _buildEmailStep(),
          _ForgotPasswordStep.enterCodeAndPassword => _buildCodeAndPasswordStep(),
          _ForgotPasswordStep.emailLinkSent => _buildEmailLinkStep(),
          _ForgotPasswordStep.success => _buildSuccessStep(),
        },
      ),
    );

    if (_isWeb) {
      return Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(24),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.08),
              blurRadius: 28,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [header, body],
          ),
        ),
      );
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        header,
        Transform.translate(
          offset: const Offset(0, -24),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: body,
          ),
        ),
      ],
    );
  }

  Widget _buildEmailStep() {
    return Form(
      key: _emailFormKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Forgot your password?',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: _textDark,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            kIsWeb
                ? 'We will send a 6-digit code to your email inbox and to your phone if you use the ATMOS app.'
                : 'We will send a 6-digit code as a phone notification — no need to open Gmail. '
                    'We also send it to your inbox as backup.',
            style: const TextStyle(fontSize: 14, color: _textMuted, height: 1.45),
          ),
          const SizedBox(height: 24),
          const Row(
            children: [
              Text(
                'Email Address',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: _textDark,
                ),
              ),
              Text(
                ' *',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: Colors.red,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          TextFormField(
            controller: _emailController,
            keyboardType: TextInputType.emailAddress,
            textInputAction: TextInputAction.done,
            autocorrect: false,
            enabled: !_isLoading,
            onFieldSubmitted: (_) {
              if (!_isLoading) _requestCode();
            },
            decoration: _inputDecoration(hint: 'Enter email address'),
            validator: (value) {
              if (value == null || value.trim().isEmpty) {
                return 'Please enter your email';
              }
              if (!isValidEmailFormat(value)) {
                return 'Please enter a valid email';
              }
              return null;
            },
          ),
          const SizedBox(height: 24),
          _primaryButton(
            label: 'Send code',
            onPressed: _requestCode,
          ),
          const SizedBox(height: 16),
          _backToSignInButton(),
        ],
      ),
    );
  }

  Widget _buildCodeAndPasswordStep() {
    final email = _activeEmail ?? '';
    final masked = maskEmailForDisplay(email);

    return Form(
      key: _resetFormKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!kIsWeb)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(
                color: const Color(0xFFFFF7ED),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AppTheme.brandOrange.withValues(alpha: 0.35)),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.notifications_active_outlined, color: AppTheme.brandOrange, size: 22),
                  SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Look for an ATMOS-TRS notification on this phone. '
                      'The 6-digit code appears there — you do not need Gmail.',
                      style: TextStyle(fontSize: 13, color: _textDark, height: 1.4),
                    ),
                  ),
                ],
              ),
            ),
          Text(
            'Enter the code sent to $masked',
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: _textDark,
            ),
          ),
          if (_deliveryHint != null) ...[
            const SizedBox(height: 8),
            Text(
              _deliveryHint!,
              style: const TextStyle(fontSize: 13, color: _textMuted, height: 1.4),
            ),
          ],
          const SizedBox(height: 20),
          TextFormField(
            controller: _otpController,
            keyboardType: TextInputType.number,
            maxLength: 6,
            textAlign: TextAlign.center,
            enabled: !_isLoading,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            style: const TextStyle(
              fontSize: 26,
              letterSpacing: 6,
              fontWeight: FontWeight.w700,
            ),
            decoration: _inputDecoration(hint: '6-digit code').copyWith(counterText: ''),
            validator: (value) {
              final digits = (value ?? '').replaceAll(RegExp(r'\D'), '');
              if (digits.length != 6) return 'Enter the 6-digit code';
              return null;
            },
          ),
          const SizedBox(height: 16),
          const Text(
            'New password',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w500,
              color: _textDark,
            ),
          ),
          const SizedBox(height: 8),
          TextFormField(
            controller: _passwordController,
            obscureText: _obscurePassword,
            enabled: !_isLoading,
            decoration: _inputDecoration(
              hint: 'At least 6 characters',
              suffixIcon: IconButton(
                onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                icon: Icon(
                  _obscurePassword ? Icons.visibility_off_rounded : Icons.visibility_rounded,
                  color: _textMuted,
                ),
              ),
            ),
            validator: (value) {
              if (value == null || value.length < 6) {
                return 'Password must be at least 6 characters';
              }
              return null;
            },
          ),
          const SizedBox(height: 16),
          const Text(
            'Confirm password',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w500,
              color: _textDark,
            ),
          ),
          const SizedBox(height: 8),
          TextFormField(
            controller: _confirmPasswordController,
            obscureText: _obscureConfirm,
            enabled: !_isLoading,
            textInputAction: TextInputAction.done,
            onFieldSubmitted: (_) {
              if (!_isLoading) _submitNewPassword();
            },
            decoration: _inputDecoration(
              hint: 'Re-enter password',
              suffixIcon: IconButton(
                onPressed: () => setState(() => _obscureConfirm = !_obscureConfirm),
                icon: Icon(
                  _obscureConfirm ? Icons.visibility_off_rounded : Icons.visibility_rounded,
                  color: _textMuted,
                ),
              ),
            ),
            validator: (value) {
              if (value == null || value.isEmpty) return 'Please confirm your password';
              if (value != _passwordController.text) return 'Passwords do not match';
              return null;
            },
          ),
          const SizedBox(height: 24),
          _primaryButton(
            label: 'Set new password',
            onPressed: _submitNewPassword,
          ),
          const SizedBox(height: 12),
          Center(
            child: TextButton(
              onPressed: (_resending || _cooldown > 0) ? null : _resendCode,
              child: Text(
                _cooldown > 0
                    ? 'Resend code in $_cooldown s'
                    : _resending
                    ? 'Sending…'
                    : 'Resend code',
                style: TextStyle(
                  color: AppTheme.brandOrange,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
          _backToSignInButton(),
        ],
      ),
    );
  }

  Widget _buildEmailLinkStep() {
    final email = _activeEmail ?? normalizeEmail(_emailController.text);
    final masked = maskEmailForDisplay(email);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(Icons.link_rounded, size: 48, color: Colors.green.shade600),
        const SizedBox(height: 16),
        const Text(
          'Check your email',
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w800,
            color: _textDark,
          ),
        ),
        const SizedBox(height: 12),
        Text(
          _deliveryHint ??
              'We sent a password reset link to $masked. Open the email, tap the link, '
                  'and choose a new password.',
          style: const TextStyle(fontSize: 14, color: _textMuted, height: 1.45),
        ),
        const SizedBox(height: 12),
        const Text(
          'Look in your inbox first. If you do not see it, check Spam or Promotions.',
          style: TextStyle(fontSize: 13, color: _textMuted, height: 1.4),
        ),
        const SizedBox(height: 28),
        _primaryButton(
          label: 'Back to Sign In',
          onPressed: () => Navigator.pop(context),
        ),
        const SizedBox(height: 12),
        Center(
          child: TextButton(
            onPressed: _isLoading ? null : _requestCode,
            child: Text(
              'Send again',
              style: TextStyle(color: AppTheme.brandOrange, fontWeight: FontWeight.w500),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSuccessStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(Icons.check_circle_outline, size: 48, color: Colors.green.shade600),
        const SizedBox(height: 16),
        const Text(
          'Password updated',
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w800,
            color: _textDark,
          ),
        ),
        const SizedBox(height: 12),
        const Text(
          'You can now sign in with your new password.',
          style: TextStyle(fontSize: 14, color: _textMuted, height: 1.45),
        ),
        const SizedBox(height: 28),
        _primaryButton(
          label: 'Back to Sign In',
          onPressed: () => Navigator.pop(context),
        ),
      ],
    );
  }

  Widget _primaryButton({
    required String label,
    required VoidCallback onPressed,
  }) {
    return SizedBox(
      width: double.infinity,
      child: FilledButton(
        onPressed: _isLoading ? null : onPressed,
        style: FilledButton.styleFrom(
          backgroundColor: AppTheme.brandOrange,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(vertical: 16),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
        child: _isLoading
            ? const SizedBox(
                height: 20,
                width: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                ),
              )
            : Text(
                label,
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
              ),
      ),
    );
  }

  Widget _backToSignInButton() {
    return Center(
      child: TextButton(
        onPressed: _isLoading ? null : () => Navigator.pop(context),
        child: Text(
          'Back to Sign In',
          style: TextStyle(color: AppTheme.brandOrange, fontWeight: FontWeight.w600),
        ),
      ),
    );
  }
}

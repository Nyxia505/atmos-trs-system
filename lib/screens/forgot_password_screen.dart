import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:atmos_trs_system/config/app_theme.dart';
import 'package:atmos_trs_system/services/password_reset_service.dart';
import 'package:atmos_trs_system/utils/email_utils.dart';
import 'package:atmos_trs_system/utils/logo_utils.dart';
import 'package:atmos_trs_system/utils/signup_field_validation.dart';

enum _ForgotPasswordStep {
  enterEmail,
  emailLinkSent,
  resetFromEmailLink,
  success,
}

/// Password recovery via Firebase's email reset link.
class ForgotPasswordScreen extends StatefulWidget {
  const ForgotPasswordScreen({super.key, this.initialEmail});

  final String? initialEmail;

  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  static const int _resendCooldownSeconds = 60;

  final _emailFormKey = GlobalKey<FormState>();
  final _resetFormKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();

  _ForgotPasswordStep _step = _ForgotPasswordStep.enterEmail;
  bool _isLoading = false;
  bool _requestInFlight = false;
  bool _verifyingLink = false;
  int _cooldown = 0;
  String? _emailStepBanner;
  bool _obscurePassword = true;
  bool _obscureConfirm = true;
  String? _activeEmail;
  String? _emailResetOobCode;

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
    WidgetsBinding.instance.addPostFrameCallback((_) => _checkForEmailResetLink());
  }

  Future<void> _checkForEmailResetLink() async {
    final oobCode = PasswordResetService.emailResetOobCodeFromLaunchUrl();
    if (oobCode == null) return;
    setState(() {
      _emailResetOobCode = oobCode;
      _step = _ForgotPasswordStep.resetFromEmailLink;
      _verifyingLink = true;
      _passwordController.clear();
      _confirmPasswordController.clear();
    });
    try {
      final email = await PasswordResetService.verifyEmailResetLink(oobCode);
      if (!mounted) return;
      setState(() {
        _activeEmail = email;
        _emailController.text = email;
        _verifyingLink = false;
      });
    } on FirebaseAuthException catch (e) {
      if (!mounted) return;
      _showLinkProblem(e.message ?? PasswordResetService.authErrorMessage(e));
    } catch (_) {
      if (!mounted) return;
      _showLinkProblem('Could not open this reset link. Request a new one.');
    }
  }

  void _showLinkProblem(String message) {
    setState(() {
      _verifyingLink = false;
      _emailResetOobCode = null;
      _step = _ForgotPasswordStep.enterEmail;
      _emailStepBanner = message;
    });
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  Future<void> _requestEmailLink() async {
    if (_requestInFlight || _isLoading) return;
    final String email;
    if (_step == _ForgotPasswordStep.enterEmail) {
      if (!_emailFormKey.currentState!.validate()) return;
      email = normalizeEmail(_emailController.text);
    } else {
      if (_cooldown > 0) return;
      email = _activeEmail ?? normalizeEmail(_emailController.text);
    }
    if (Firebase.apps.isEmpty) {
      _showSnack('Firebase is not available. Please try again later.', isError: true);
      return;
    }

    _requestInFlight = true;
    setState(() {
      _isLoading = true;
      _emailStepBanner = null;
    });

    try {
      final result = await PasswordResetService.requestEmailResetLink(email);
      if (!mounted) return;
      if (!result.accountFound) {
        setState(() {
          _isLoading = false;
          _step = _ForgotPasswordStep.enterEmail;
          _emailStepBanner = 'No login account exists for this email. '
              'Use Sign Up to create one, or check the spelling.';
        });
        return;
      }
      setState(() {
        _isLoading = false;
        _activeEmail = result.email;
        _step = _ForgotPasswordStep.emailLinkSent;
      });
      _startCooldown(_resendCooldownSeconds);
      _showSnack(
        'Reset link sent to ${maskEmailForDisplay(result.email)}.',
        isError: false,
      );
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
      _showSnack(
        PasswordResetService.messageForGenericError(e),
        isError: true,
      );
    } finally {
      _requestInFlight = false;
    }
  }

  Future<void> _submitNewPassword() async {
    if (_verifyingLink) return;
    if (!_resetFormKey.currentState!.validate()) return;
    final password = _passwordController.text;
    final confirm = _confirmPasswordController.text;
    if (password != confirm) {
      _showSnack('Passwords do not match.', isError: true);
      return;
    }
    final strengthError = validateStrongPassword(password);
    if (strengthError != null) {
      _showSnack(strengthError, isError: true);
      return;
    }

    setState(() => _isLoading = true);
    try {
      await PasswordResetService.completeResetFromEmailLink(
        oobCode: _emailResetOobCode ?? '',
        newPassword: password,
      );
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _step = _ForgotPasswordStep.success;
      });
    } on ArgumentError catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      _showSnack(PasswordResetService.messageForGenericError(e), isError: true);
    } on FirebaseAuthException catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      final message = e.message ?? PasswordResetService.authErrorMessage(e);
      if (e.code == 'expired-action-code' || e.code == 'invalid-action-code') {
        _showLinkProblem(message);
      }
      _showSnack(message, isError: true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      _showSnack(
        PasswordResetService.messageForGenericError(e),
        isError: true,
      );
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

  /// Reset links open this screen as the first route on web, so there may be
  /// nothing to pop back to.
  void _goToSignIn() {
    final navigator = Navigator.of(context);
    if (navigator.canPop()) {
      navigator.pop();
      return;
    }
    navigator.pushReplacementNamed('/login');
  }

  void _showSnack(String message, {required bool isError}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? Colors.red.shade700 : Colors.green.shade700,
        behavior: SnackBarBehavior.floating,
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
                    onPressed: _isLoading ? null : () => _goToSignIn(),
                    tooltip: 'Back to sign in',
                  ),
                  const Spacer(),
                ],
              ),
              const SizedBox(height: 8),
              Center(
                child: Container(
                  width: 112,
                  height: 112,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.white,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.18),
                        blurRadius: 18,
                        offset: const Offset(0, 6),
                      ),
                    ],
                  ),
                  child: const ClipOval(
                    child: Padding(
                      padding: EdgeInsets.all(8),
                      child: TransparentLogo(
                        width: 96,
                        height: 96,
                        fit: BoxFit.contain,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 16),
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
          _ForgotPasswordStep.emailLinkSent => _buildEmailLinkStep(),
          _ForgotPasswordStep.resetFromEmailLink => _buildResetFromEmailLinkStep(),
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
          const Text(
            'Enter the email you use to sign in. We will send you a link to '
            'create a new password.',
            style: TextStyle(fontSize: 14, color: _textMuted, height: 1.45),
          ),
          if (_emailStepBanner != null) ...[
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFFFF7ED),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AppTheme.brandOrange.withValues(alpha: 0.35)),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.info_outline, color: AppTheme.brandOrange, size: 20),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      _emailStepBanner!,
                      style: const TextStyle(fontSize: 13, color: _textDark, height: 1.4),
                    ),
                  ),
                ],
              ),
            ),
          ],
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
              if (!_isLoading) _requestEmailLink();
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
            label: 'Send reset link',
            onPressed: _requestEmailLink,
          ),
          const SizedBox(height: 8),
          _backToSignInButton(),
        ],
      ),
    );
  }

  Widget _buildResetFromEmailLinkStep() {
    final email = _activeEmail;
    return Form(
      key: _resetFormKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.link_rounded, size: 48, color: AppTheme.brandOrange),
          const SizedBox(height: 16),
          const Text(
            'Choose a new password',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w800,
              color: _textDark,
            ),
          ),
          const SizedBox(height: 8),
          if (_verifyingLink)
            const Row(
              children: [
                SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                SizedBox(width: 10),
                Text(
                  'Checking your reset link…',
                  style: TextStyle(fontSize: 14, color: _textMuted),
                ),
              ],
            )
          else
            Text(
              email != null && email.isNotEmpty
                  ? 'Enter and confirm a new password for ${maskEmailForDisplay(email)}.'
                  : 'Your reset link is valid. Enter and confirm your new password below.',
              style: const TextStyle(fontSize: 14, color: _textMuted, height: 1.45),
            ),
          const SizedBox(height: 20),
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
            enabled: !_isLoading && !_verifyingLink,
            decoration: _inputDecoration(
              hint: 'At least 8 chars, upper, lower, number',
              suffixIcon: IconButton(
                onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                icon: Icon(
                  _obscurePassword ? Icons.visibility_off_rounded : Icons.visibility_rounded,
                  color: _textMuted,
                ),
              ),
            ),
            validator: validateStrongPassword,
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
            enabled: !_isLoading && !_verifyingLink,
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
          _backToSignInButton(),
        ],
      ),
    );
  }

  Widget _buildEmailLinkStep() {
    final email = _activeEmail ?? normalizeEmail(_emailController.text);
    final masked = maskEmailForDisplay(email);
    final canResend = !_isLoading && !_requestInFlight && _cooldown <= 0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(Icons.mark_email_read_outlined, size: 48, color: Colors.green.shade600),
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
          'We sent a password reset link to $masked. Open the email, tap the link, '
          'and create a new password.',
          style: const TextStyle(fontSize: 14, color: _textMuted, height: 1.45),
        ),
        const SizedBox(height: 12),
        const Text(
          'Look in your Inbox first. If you do not see it within a few minutes, '
          'check Spam or Promotions.',
          style: TextStyle(fontSize: 13, color: _textMuted, height: 1.4),
        ),
        const SizedBox(height: 28),
        _primaryButton(
          label: 'Back to Sign In',
          onPressed: _goToSignIn,
        ),
        const SizedBox(height: 12),
        Center(
          child: TextButton(
            onPressed: canResend ? _requestEmailLink : null,
            child: Text(
              _cooldown > 0
                  ? 'Resend link in $_cooldown s'
                  : _isLoading
                      ? 'Sending…'
                      : 'Resend link',
              style: TextStyle(color: AppTheme.brandOrange, fontWeight: FontWeight.w600),
            ),
          ),
        ),
        Center(
          child: TextButton(
            onPressed: _isLoading
                ? null
                : () => setState(() {
                      _step = _ForgotPasswordStep.enterEmail;
                      _emailStepBanner = null;
                    }),
            child: const Text(
              'Use a different email',
              style: TextStyle(color: _textMuted, fontWeight: FontWeight.w500),
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
          onPressed: () => Navigator.pushReplacementNamed(context, '/login'),
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
        onPressed: _isLoading ? null : () => _goToSignIn(),
        child: Text(
          'Back to Sign In',
          style: TextStyle(color: AppTheme.brandOrange, fontWeight: FontWeight.w600),
        ),
      ),
    );
  }
}

import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:atmos_trs_system/config/app_theme.dart';
import 'package:atmos_trs_system/config/atmos_brand_typography.dart';
import 'package:flutter/services.dart';
import 'package:atmos_trs_system/config/auth_config.dart';
import 'package:atmos_trs_system/config/session_storage.dart';
import 'package:atmos_trs_system/utils/email_utils.dart';
import 'package:atmos_trs_system/utils/logo_utils.dart';
import 'package:atmos_trs_system/utils/firebase_client_blocked_message.dart';
import 'package:atmos_trs_system/services/login_flow_service.dart';
import 'package:atmos_trs_system/navigation/login_route_args.dart';
import 'package:atmos_trs_system/navigation/pending_checkin_navigation.dart';
import 'package:atmos_trs_system/services/pending_lgu_checkin_storage.dart';
import 'package:atmos_trs_system/services/pending_spot_checkin_storage.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _passwordFocusNode = FocusNode();

  bool _isLoading = false;
  bool _obscurePassword = true;
  LoginRouteArgs? _loginRouteArgs;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _readRouteArguments());
  }

  void _readRouteArguments() {
    final args = ModalRoute.of(context)?.settings.arguments;
    final parsed = LoginRouteArgs.from(args);
    if (parsed != null) {
      setState(() => _loginRouteArgs = parsed);
    }
    if (args is String && args.trim().isNotEmpty) {
      _emailController.text = normalizeEmail(args);
    } else if (args is Map) {
      final email = args['email'];
      if (email is String && email.trim().isNotEmpty) {
        _emailController.text = normalizeEmail(email);
      }
    }
  }

  @override
  void dispose() {
    TextInput.finishAutofillContext(shouldSave: false);
    _emailController.dispose();
    _passwordController.dispose();
    _passwordFocusNode.dispose();
    super.dispose();
  }

  /// Signs in with email/password.
  /// creates the Firebase Auth user if it does not exist yet (Firestore profiles do not
  /// create Auth accounts). If the email is already registered, sign-in must succeed
  /// or we surface a wrong-password style error.
  Future<UserCredential> _signInOrProvisionDemoStaff({
    required String email,
    required String password,
  }) async {
    final demo = await SessionStorage.validateCredentialsAsync(email, password);
    try {
      return await FirebaseAuth.instance.signInWithEmailAndPassword(
        email: email,
        password: password,
      );
    } on FirebaseAuthException catch (e) {
      if (!demo) rethrow;

      if (e.code == 'user-not-found') {
        return await FirebaseAuth.instance.createUserWithEmailAndPassword(
          email: email,
          password: password,
        );
      }

      // Newer Firebase often returns invalid-credential for both missing user and bad password.
      if (e.code == 'invalid-credential') {
        try {
          return await FirebaseAuth.instance.createUserWithEmailAndPassword(
            email: email,
            password: password,
          );
        } on FirebaseAuthException catch (e2) {
          if (e2.code == 'email-already-in-use') {
            throw FirebaseAuthException(
              code: 'wrong-password',
              message:
                  'The password is invalid or the user does not have a password.',
            );
          }
          rethrow;
        }
      }

      rethrow;
    }
  }

  void _login() async {
    if (!_formKey.currentState!.validate()) return;

    // Decline OS/browser "save password?" prompts (esp. Chrome) for shared/public devices.
    TextInput.finishAutofillContext(shouldSave: false);

    setState(() => _isLoading = true);

    final email = normalizeEmail(_emailController.text);
    final password = _passwordController.text;

    try {
      if (Firebase.apps.isEmpty) {
        setState(() => _isLoading = false);
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Firebase is not available. Please try again later.'),
            backgroundColor: Colors.redAccent,
          ),
        );
        return;
      }

      // All accounts use Firebase Auth + Firestore `users`. Firestore alone does not enable login.
      // Demo staff emails (SessionStorage) can auto-create Auth if missing but password matches.
      final userCredential = await _signInOrProvisionDemoStaff(
        email: email,
        password: password,
      );
      final uid = userCredential.user?.uid;
      if (uid == null) {
        setState(() => _isLoading = false);
        return;
      }
      AuthConfig.currentUserUid = uid;

      final route = await LoginFlowService.resolveRouteFast(
        uid: uid,
        email: email,
      );

      LoginFlowService.scheduleBackgroundFinalize(
        uid: uid,
        email: email,
        password: password,
      );

      setState(() => _isLoading = false);
      if (!mounted) return;

      final isStaff = route == '/governor-dashboard' ||
          route == '/lgu-dashboard' ||
          route == '/tourism-dashboard';
      if (isStaff) {
        await LoginFlowService.finalizeLoginInBackground(
          uid: uid,
          email: email,
          password: password,
        );
        await PendingSpotCheckInStorage.clear();
        await PendingLguCheckInStorage.clear();
        if (!mounted) return;
        Navigator.pushReplacementNamed(context, route);
        return;
      }
      if (route == '/verify-otp') {
        Navigator.pushReplacementNamed(context, route);
        return;
      }
      if (await _completeLoginOnlyFeatureReturn(route)) {
        return;
      }
      await navigateToPendingSpotCheckInOrDashboard(
        context,
        defaultRoute: route,
        isTouristDestination: route == '/dashboard',
      );
    } on FirebaseAuthException catch (e) {
      setState(() => _isLoading = false);
      if (!mounted) return;
      final errorMessage = _loginErrorMessage(e);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(errorMessage),
          backgroundColor: Colors.redAccent,
        ),
      );
    } catch (e) {
      setState(() => _isLoading = false);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Login error: ${e.toString()}'),
          backgroundColor: Colors.redAccent,
        ),
      );
    }
  }

  /// Matches [FirebaseAuthException.code] variants across Firebase / FlutterFire versions.
  static String _normalizeAuthErrorCode(String code) {
    return code.replaceAll(RegExp(r'^firebase_auth/', caseSensitive: false), '').trim().replaceAll('_', '-').toLowerCase();
  }

  /// Clear messages for common Firebase Auth failures (Auth is separate from Firestore data).
  String _loginErrorMessage(FirebaseAuthException e) {
    final raw = e.message?.trim();
    if (looksLikeGoogleFirebaseClientBlocked(raw)) {
      debugPrintFirebaseClientBlockedHint();
      return firebaseClientBlockedUserMessage();
    }
    final code = _normalizeAuthErrorCode(e.code);
    if (code == 'user-disabled') {
      return 'This account has been disabled.';
    }
    if (code == 'too-many-requests') {
      return 'Too many failed attempts. Please try again later.';
    }
    if (code == 'network-request-failed') {
      return 'Network error. Check your connection and try again.';
    }
    if (code == 'user-not-found') {
      if (_loginRouteArgs?.loginOnly == true) {
        return 'No account exists for this email. Use Register on the home page if you are a new tourist.';
      }
      return 'No Firebase login account exists for this email. '
          'Saving a profile in Firestore does not create a password login—use Sign Up in this app, '
          'or ask an admin to add this email in Firebase Authentication (Authentication → Users).';
    }
    if (code == 'wrong-password' ||
        code == 'invalid-credential' ||
        code == 'invalid-login-credentials' ||
        code == 'invalid-password') {
      return 'Invalid email or password. Tap Forgot password to get a code on your phone.';
    }
    // Native message wording (often not surfaced as Dart `code`).
    final msgLower = raw?.toLowerCase() ?? '';
    if (msgLower.contains('incorrect') &&
        msgLower.contains('malformed')) {
      return 'Invalid email or password. Tap Forgot password to get a code on your phone.';
    }
    if (raw != null && raw.isNotEmpty) return raw;
    return 'Login failed (${e.code}).';
  }

  /// After login-only VR/itinerary auth, pop back to landing with the feature id.
  Future<bool> _completeLoginOnlyFeatureReturn(String route) async {
    final args = _loginRouteArgs;
    if (args?.loginOnly != true ||
        args!.returnFeature == null ||
        route != '/dashboard') {
      return false;
    }

    final pendingSpot = await PendingSpotCheckInStorage.peek();
    final pendingLgu = await PendingLguCheckInStorage.peek();
    if (pendingSpot != null || pendingLgu != null) {
      return false;
    }

    if (!mounted) return true;
    Navigator.pop(context, args.returnFeature);
    return true;
  }

  void _openForgotPassword() {
    Navigator.pushNamed(
      context,
      '/forgot-password',
      arguments: _emailController.text.trim(),
    );
  }

  static const Color _backgroundCream = Color(0xFFFFF7ED); // orange-50
  static const Color _cardWhite = Colors.white;
  static const Color _textDark = Color(0xFF1A1A1A);
  static const Color _textMuted = Color(0xFF6B7280);
  static const Color _inputBorder = Color(0xFFE5E7EB);
  static const double _logoCircleSize = 120.0;
  static const double _cardRadius = 22.0;
  static const double _fieldRadius = 14.0;
  static const double _buttonRadius = 14.0;

  InputDecoration _inputDecoration({
    required String hint,
    IconData? prefixIcon,
    Widget? suffixIcon,
  }) {
    return InputDecoration(
      hintText: hint,
      hintStyle: TextStyle(color: _textMuted.withValues(alpha: 0.65), fontSize: 15),
      prefixIcon: prefixIcon != null
          ? Icon(prefixIcon, color: _textMuted.withValues(alpha: 0.75), size: 22)
          : null,
      suffixIcon: suffixIcon,
      filled: true,
      fillColor: const Color(0xFFF9FAFB),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(_fieldRadius),
        borderSide: const BorderSide(color: _inputBorder, width: 1),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(_fieldRadius),
        borderSide: const BorderSide(color: AppTheme.brandOrange, width: 2),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(_fieldRadius),
        borderSide: BorderSide(color: Colors.red.shade300),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(_fieldRadius),
        borderSide: BorderSide(color: Colors.red.shade400, width: 2),
      ),
    );
  }

  Widget _buildFloatingLogoCircle({double size = _logoCircleSize}) {
    const double logoInset = 8;
    final double innerSize = size - (logoInset * 2);

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.12),
            blurRadius: 24,
            offset: const Offset(0, 8),
            spreadRadius: 0,
          ),
          BoxShadow(
            color: AppTheme.brandOrange.withValues(alpha: 0.18),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: ClipOval(
        child: Padding(
          padding: const EdgeInsets.all(logoInset),
          child: TransparentLogo(
            width: innerSize,
            height: innerSize,
            fit: BoxFit.cover,
            alignment: Alignment.topCenter,
          ),
        ),
      ),
    );
  }

  Widget _buildLoginCard({required Widget child, Color? backgroundColor}) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: backgroundColor ?? _cardWhite,
        borderRadius: BorderRadius.circular(_cardRadius),
        border: Border.all(
          color: AppTheme.brandOrange.withValues(alpha: 0.08),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.07),
            blurRadius: 28,
            offset: const Offset(0, 10),
            spreadRadius: 0,
          ),
          BoxShadow(
            color: AppTheme.brandOrange.withValues(alpha: 0.06),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 28, 24, 28),
        child: child,
      ),
    );
  }

  Widget _buildBackRow({Color iconColor = Colors.white}) {
    return Row(
      children: [
        IconButton(
          key: const Key('back-to-landing-button'),
          icon: Icon(
            Icons.arrow_back_rounded,
            color: iconColor,
            size: 24,
          ),
          onPressed: _goBackToLanding,
          tooltip: 'Back to home',
        ),
        const Spacer(),
      ],
    );
  }

  Widget _buildHeaderBranding() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _buildFloatingLogoCircle(),
        const SizedBox(height: 14),
        Text(
          'ATMOS-TRS',
          textAlign: TextAlign.center,
          style: AtmosBrandTypography.authAppMark(
            color: Colors.white,
            fontSize: 28,
            letterSpacing: 1.8,
          ),
        ),
      ],
    );
  }

  Widget _buildFieldLabel(String label, {bool required = false}) {
    return Row(
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: _textDark,
            letterSpacing: 0.1,
          ),
        ),
        if (required)
          const Text(
            ' *',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: Colors.red,
            ),
          ),
      ],
    );
  }

  bool get _isWeb => MediaQuery.sizeOf(context).width >= 768;

  /// Navigate back to landing page (e.g. when user came via Start VR and skips login/sign up).
  void _goBackToLanding() {
    if (Navigator.canPop(context)) {
      Navigator.pop(context);
    } else {
      Navigator.pushReplacementNamed(context, _isWeb ? '/landing' : '/login');
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (bool didPop, dynamic result) {
        if (didPop) return;
        _goBackToLanding();
      },
      child: Scaffold(
        backgroundColor: _backgroundCream,
        body: _isWeb ? _buildWebLayout(context) : _buildMobileLayout(context),
      ),
    );
  }

  /// Web: full-screen background image + overlay + centered mobile-style auth card.
  Widget _buildWebLayout(BuildContext context) {
    return SizedBox(
      width: MediaQuery.sizeOf(context).width,
      height: MediaQuery.sizeOf(context).height,
      child: Stack(
        fit: StackFit.expand,
        children: [
          Image.asset(
            'assets/images/oroquieta City plaza.jpeg',
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => Image.network(
              'https://images.unsplash.com/photo-1488646953014-85cb44e25828?w=1200',
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) =>
                  Container(color: AppTheme.brandOrange.withOpacity(0.9)),
            ),
          ),
          Container(
            decoration: BoxDecoration(color: Colors.black.withOpacity(0.45)),
          ),
          Center(
            child: SingleChildScrollView(
              padding: EdgeInsets.symmetric(
                vertical: _isWeb ? 16 : 24,
                horizontal: _isWeb ? 16 : 24,
              ),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 440),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(24),
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
                    child: Container(
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(24),
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.3),
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.2),
                            blurRadius: 28,
                            offset: const Offset(0, 10),
                          ),
                        ],
                      ),
                      child: _buildAuthContent(),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Mobile: logo above title (reference layout), orange header, white card.
  Widget _buildMobileLayout(BuildContext context) {
    return SingleChildScrollView(
      child: Column(
        children: [
          Container(
            width: double.infinity,
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [AppTheme.brandOrange, AppTheme.brandOrangeLight],
              ),
              borderRadius: BorderRadius.only(
                bottomLeft: Radius.circular(36),
                bottomRight: Radius.circular(36),
              ),
            ),
            child: SafeArea(
              bottom: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 36),
                child: Column(
                  children: [
                    _buildBackRow(),
                    const SizedBox(height: 16),
                    _buildHeaderBranding(),
                  ],
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
            child: _buildLoginCard(child: _buildLoginForm()),
          ),
        ],
      ),
    );
  }

  /// Shared auth UI for web: logo above title, then white form section.
  Widget _buildAuthContent() {
    final header = Container(
      width: double.infinity,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            AppTheme.brandOrange.withValues(alpha: 0.92),
            AppTheme.brandOrangeLight.withValues(alpha: 0.88),
          ],
        ),
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(24),
          topRight: Radius.circular(24),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 16, 24, 28),
        child: Column(
          children: [
            _buildBackRow(),
            const SizedBox(height: 12),
            _buildHeaderBranding(),
          ],
        ),
      ),
    );

    final formSection = Container(
      width: double.infinity,
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.only(
          bottomLeft: Radius.circular(24),
          bottomRight: Radius.circular(24),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 8, 24, 28),
        child: _buildLoginForm(),
      ),
    );

    return ClipRRect(
      borderRadius: BorderRadius.circular(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [header, formSection],
      ),
    );
  }

  Widget _buildLoginForm() {
    final loginOnly = _loginRouteArgs?.loginOnly == true;
    final subtitle = _loginRouteArgs?.subtitle;

    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (subtitle != null) ...[
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: _textMuted,
                fontSize: 14,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 24),
          ],
          _buildFieldLabel('Email Address', required: true),
          const SizedBox(height: 10),
          TextFormField(
            key: const Key('email-field'),
            controller: _emailController,
            keyboardType: TextInputType.emailAddress,
            textInputAction: TextInputAction.next,
            autofillHints: const [],
            autocorrect: false,
            enableSuggestions: false,
            enableIMEPersonalizedLearning: false,
            onFieldSubmitted: (_) {
              if (_isLoading) return;
              FocusScope.of(context).requestFocus(_passwordFocusNode);
            },
            onEditingComplete: () {
              if (_isLoading) return;
              FocusScope.of(context).requestFocus(_passwordFocusNode);
            },
            style: const TextStyle(color: _textDark, fontSize: 15),
            decoration: _inputDecoration(
              hint: 'Enter email address',
              prefixIcon: Icons.email_outlined,
            ),
            validator: (value) {
              if (value == null || value.isEmpty) {
                return 'Please enter your email';
              }
              if (!isValidEmailFormat(value)) {
                return 'Please enter a valid email';
              }
              return null;
            },
          ),
          const SizedBox(height: 22),
          _buildFieldLabel('Password', required: true),
          const SizedBox(height: 10),
          TextFormField(
            key: const Key('password-field'),
            controller: _passwordController,
            focusNode: _passwordFocusNode,
            obscureText: _obscurePassword,
            textInputAction: TextInputAction.done,
            autofillHints: const [],
            autocorrect: false,
            enableSuggestions: false,
            enableIMEPersonalizedLearning: false,
            onFieldSubmitted: (_) {
              if (_isLoading) return;
              _login();
            },
            onEditingComplete: () {
              if (_isLoading) return;
              _login();
            },
            style: const TextStyle(color: _textDark, fontSize: 15),
            decoration: _inputDecoration(
              hint: 'Enter password',
              prefixIcon: Icons.lock_outline_rounded,
              suffixIcon: IconButton(
                onPressed: _isLoading
                    ? null
                    : () =>
                          setState(() => _obscurePassword = !_obscurePassword),
                tooltip: _obscurePassword ? 'Show password' : 'Hide password',
                icon: Icon(
                  _obscurePassword
                      ? Icons.visibility_off_rounded
                      : Icons.visibility_rounded,
                  color: _textMuted,
                  size: 22,
                ),
              ),
            ),
            validator: (value) {
              if (value == null || value.isEmpty) {
                return 'Please enter your password';
              }
              if (value.length < 6) {
                return 'Password must be at least 6 characters';
              }
              return null;
            },
          ),
          const SizedBox(height: 10),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              key: const Key('forgot-password-button'),
              onPressed: _isLoading ? null : _openForgotPassword,
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: const Text(
                'Forgot Password?',
                style: TextStyle(
                  color: AppTheme.brandOrange,
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                ),
              ),
            ),
          ),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            height: 54,
            child: FilledButton(
              key: const Key('sign-in-button'),
              onPressed: _isLoading ? null : _login,
              style: FilledButton.styleFrom(
                backgroundColor: AppTheme.brandOrange,
                foregroundColor: Colors.white,
                disabledBackgroundColor: AppTheme.brandOrange.withValues(alpha: 0.6),
                elevation: 3,
                shadowColor: AppTheme.brandOrange.withValues(alpha: 0.45),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(_buttonRadius),
                ),
              ),
              child: _isLoading
                  ? const SizedBox(
                      height: 22,
                      width: 22,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.5,
                        valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                      ),
                    )
                  : const Text(
                      'Sign In',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.3,
                      ),
                    ),
            ),
          ),
          if (!loginOnly) ...[
            const SizedBox(height: 24),
            Center(
              child: Wrap(
                alignment: WrapAlignment.center,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  const Text(
                    "Don't have an account? ",
                    style: TextStyle(color: _textMuted, fontSize: 14),
                  ),
                  GestureDetector(
                    key: const Key('sign-up-button'),
                    onTap: () => Navigator.pushNamed(context, '/signup'),
                    child: const Text(
                      'Sign Up',
                      style: TextStyle(
                        color: AppTheme.brandOrange,
                        fontWeight: FontWeight.w700,
                        fontSize: 14,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

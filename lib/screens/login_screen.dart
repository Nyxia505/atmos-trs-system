import 'package:flutter/material.dart';
import 'dart:async' show unawaited;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:atmos_trs_system/config/app_theme.dart';
import 'package:flutter/services.dart';
import 'package:atmos_trs_system/config/auth_config.dart';
import 'package:atmos_trs_system/config/session_storage.dart';
import 'package:atmos_trs_system/utils/email_utils.dart';
import 'package:atmos_trs_system/utils/logo_utils.dart';
import 'package:atmos_trs_system/utils/firebase_client_blocked_message.dart';
import 'package:atmos_trs_system/services/login_flow_service.dart';
import 'package:atmos_trs_system/services/auth_service.dart';
import 'package:atmos_trs_system/services/user_directory_service.dart';
import 'package:atmos_trs_system/navigation/login_route_args.dart';
import 'package:atmos_trs_system/navigation/pending_checkin_navigation.dart';
import 'package:atmos_trs_system/services/pending_lgu_checkin_storage.dart';
import 'package:atmos_trs_system/services/pending_spot_checkin_storage.dart';
import 'package:atmos_trs_system/services/landing_intent_service.dart';
import 'package:atmos_trs_system/widgets/atmos_brand_title.dart';
import 'package:atmos_trs_system/widgets/web_glass_auth_scaffold.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:google_fonts/google_fonts.dart';

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
    unawaited(logoWithoutWhiteFuture);
    WidgetsBinding.instance.addPostFrameCallback((_) => _readRouteArguments());
  }

  void _readRouteArguments() {
    final args = ModalRoute.of(context)?.settings.arguments;
    final parsed = LoginRouteArgs.from(args);
    if (parsed != null) {
      setState(() => _loginRouteArgs = parsed);
    } else {
      unawaited(_applyPendingLandingIntentArgs());
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
  ///
  /// Demo governor/tourism: Settings may store a new password in SharedPreferences
  /// without updating Firebase Auth â€” we sync Auth from known prior passwords.
  Future<UserCredential> _signInOrProvisionDemoStaff({
    required String email,
    required String password,
  }) async {
    final demo = await SessionStorage.validateCredentialsAsync(email, password);
    try {
      final cred = await FirebaseAuth.instance.signInWithEmailAndPassword(
        email: email,
        password: password,
      );
      if (demo &&
          SessionStorage.getRoleFromEmail(email) == UserRole.governor) {
        await SessionStorage.persistGovernorPassword(password);
      }
      return cred;
    } on FirebaseAuthException catch (e) {
      if (!demo) rethrow;

      if (e.code == 'user-not-found') {
        final created =
            await FirebaseAuth.instance.createUserWithEmailAndPassword(
          email: email,
          password: password,
        );
        if (SessionStorage.getRoleFromEmail(email) == UserRole.governor) {
          await SessionStorage.persistGovernorPassword(password);
        }
        return created;
      }

      final code = e.code;
      final looksLikeBadPassword = code == 'wrong-password' ||
          code == 'invalid-credential' ||
          code == 'invalid-login-credentials';

      if (looksLikeBadPassword) {
        final prior = await SessionStorage.knownGovernorPasswords();
        final synced = await AuthService.syncDemoStaffAuthPassword(
          email: email,
          newPassword: password,
          previousPasswordCandidates: [
            ...prior,
            SessionStorage.governorPasswordLegacy,
            SessionStorage.governorPassword,
            SessionStorage.tourismPassword,
            SessionStorage.provincialTourismPassword,
            SessionStorage.provincialTourismPasswordLegacy,
          ],
        );
        if (synced != null) {
          if (SessionStorage.getRoleFromEmail(email) == UserRole.governor) {
            await SessionStorage.persistGovernorPassword(password);
          }
          return synced;
        }
      }

      // Newer Firebase often returns invalid-credential for both missing user and bad password.
      if (code == 'invalid-credential') {
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

  Future<void> _applyPendingLandingIntentArgs() async {
    final pending = await LandingIntentService.peek();
    if (pending == null) return;
    final map = LandingIntentService.loginArgsFromPending(pending);
    if (!mounted || map == null) return;
    setState(() => _loginRouteArgs = LoginRouteArgs.from(map));
  }

  Future<void> _continueTouristNavigation(String route) async {
    // Web landing "login only then return to feature" stays on the website flow.
    if (kIsWeb && await _completeLoginOnlyFeatureReturn(route)) {
      return;
    }

    // Installed app (and normal mobile auth): go straight to dashboard.
    // Clear any leftover VR / Trip Planner landing intent so it does not hijack nav.
    await LandingIntentService.clear();

    if (!mounted) return;
    await navigateToPendingSpotCheckInOrDashboard(
      context,
      defaultRoute: route,
      isTouristDestination: route == '/dashboard',
    );
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
          route == '/tourism-dashboard' ||
          route == '/provincial-tourism-dashboard';
      if (isStaff) {
        await LoginFlowService.persistStaffSessionQuick(uid: uid, email: email);
        await PendingSpotCheckInStorage.clear();
        await PendingLguCheckInStorage.clear();
        await LandingIntentService.clear();
        if (!mounted) return;
        Navigator.pushReplacementNamed(context, route);
        return;
      }
      if (route == '/verify-otp') {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Email is not verified. Enter the 6-digit code sent to your email.',
            ),
            backgroundColor: Color(0xFFFF6B00),
          ),
        );
        Navigator.pushReplacementNamed(context, route);
        return;
      }
      await _continueTouristNavigation(route);
    } on FirebaseAuthException catch (e) {
      setState(() => _isLoading = false);
      if (!mounted) return;
      final staffByEmail = SessionStorage.getRoleFromEmail(email);
      final isStaffEmail = SessionStorage.isStaffRole(staffByEmail);
      var directoryProfileKnown = false;
      if (!isStaffEmail) {
        try {
          directoryProfileKnown =
              await UserDirectoryService.getProfileByEmail(email) != null;
        } catch (_) {
          directoryProfileKnown = false;
        }
      }
      final errorMessage = _loginErrorMessage(
        e,
        directoryProfileKnown: directoryProfileKnown,
        isStaffEmail: isStaffEmail,
      );
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
  ///
  /// [directoryProfileKnown]: optional Firestore `users` hit for this email. When Auth returns
  /// collapsed `invalid-credential` and the directory has no tourist/staff doc, we prefer
  /// "The email is not registered" (Fleximart-style). Staff emails skip that heuristic.
  String _loginErrorMessage(
    FirebaseAuthException e, {
    bool directoryProfileKnown = false,
    bool isStaffEmail = false,
  }) {
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
    if (code == 'invalid-email') {
      return 'Please enter a valid email address.';
    }
    if (code == 'user-not-found') {
      return 'The email is not registered';
    }
    if (code == 'wrong-password' ||
        code == 'invalid-credential' ||
        code == 'invalid-login-credentials' ||
        code == 'invalid-password') {
      // Newer Firebase often collapses missing-user + bad-password into invalid-credential.
      if (!isStaffEmail && !directoryProfileKnown) {
        return 'The email is not registered';
      }
      return 'Wrong password';
    }
    // Native message wording (often not surfaced as Dart `code`).
    final msgLower = raw?.toLowerCase() ?? '';
    if (msgLower.contains('incorrect') &&
        msgLower.contains('malformed')) {
      if (!isStaffEmail && !directoryProfileKnown) {
        return 'The email is not registered';
      }
      return 'Wrong password';
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

  static const Color _backgroundCream = Color(0xFFFFFFFF);
  static const Color _cardWhite = Colors.white;
  static const Color _textDark = Color(0xFF1F2937);
  static const Color _textMuted = Color(0xFF9CA3AF);
  static const Color _inputBorder = Color(0xFFE5E7EB);
  static const Color _inputFill = Color(0xFFF3F4F6);
  static const Color _heroOrange = Color(0xFFF97316);
  static const String _loginHeroAsset = 'assets/images/login_hero_bg.png';
  static const double _logoCircleSize = 120.0;
  static const double _cardRadius = 36.0;
  static const double _fieldRadius = 18.0;
  static const double _buttonRadius = 16.0;
  static const String _systemName =
      'Asenso Tourismo Misamis Occidental\nSmart Tourist Registration System';

  InputDecoration _inputDecoration({
    required String hint,
    Widget? suffixIcon,
  }) {
    return InputDecoration(
      hintText: hint,
      hintStyle: const TextStyle(
        color: Color(0xFFB0B7C3),
        fontSize: 14,
        fontWeight: FontWeight.w400,
      ),
      suffixIcon: suffixIcon,
      filled: true,
      fillColor: _inputFill,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(_fieldRadius),
        borderSide: const BorderSide(color: _inputBorder, width: 1),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(_fieldRadius),
        borderSide: const BorderSide(color: _heroOrange, width: 1.6),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(_fieldRadius),
        borderSide: BorderSide(color: Colors.red.shade300),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(_fieldRadius),
        borderSide: BorderSide(color: Colors.red.shade400, width: 1.6),
      ),
    );
  }

  Widget _buildFieldIconBadge(IconData icon) {
    return Container(
      width: 46,
      height: 46,
      decoration: const BoxDecoration(
        shape: BoxShape.circle,
        color: _heroOrange,
      ),
      child: Icon(icon, color: Colors.white, size: 20),
    );
  }

  Widget _buildFloatingLogoCircle({double size = _logoCircleSize}) {
    const double logoInset = 6;
    final double innerSize = size - (logoInset * 2);

    return Container(
      width: size,
      height: size,
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
      child: ClipOval(
        child: Padding(
          padding: const EdgeInsets.all(logoInset),
          // Keep original ATMOS-TRS mark as-is (no redraw / crop / recolor).
          child: TransparentLogo(
            width: innerSize,
            height: innerSize,
            fit: BoxFit.contain,
          ),
        ),
      ),
    );
  }

  Widget _buildLoginCard({required Widget child}) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: _cardWhite,
        borderRadius: BorderRadius.circular(_cardRadius),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.12),
            blurRadius: 30,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 30, 24, 26),
        child: child,
      ),
    );
  }

  Widget _buildHeaderBranding() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _buildFloatingLogoCircle(),
        const SizedBox(height: 16),
        const AtmosBrandTitle(
          fontSize: 28,
          letterSpacing: 1.5,
          solidWhite: true,
          shadows: [
            Shadow(
              color: Color(0x40000000),
              blurRadius: 8,
              offset: Offset(0, 2),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Text(
          _systemName,
          textAlign: TextAlign.center,
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.96),
            fontSize: 12,
            height: 1.4,
            fontWeight: FontWeight.w500,
            letterSpacing: 0.05,
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
            fontSize: 13.5,
            fontWeight: FontWeight.w700,
            color: _textDark,
            letterSpacing: 0.1,
          ),
        ),
        if (required)
          const Text(
            ' *',
            style: TextStyle(
              fontSize: 13.5,
              fontWeight: FontWeight.w700,
              color: Color(0xFFEF4444),
            ),
          ),
      ],
    );
  }

  Widget _buildLabeledField({
    required String label,
    required IconData icon,
    required Widget field,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildFieldLabel(label, required: true),
        const SizedBox(height: 10),
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            _buildFieldIconBadge(icon),
            const SizedBox(width: 12),
            Expanded(child: field),
          ],
        ),
      ],
    );
  }

  bool get _isDesktopGlass =>
      MediaQuery.sizeOf(context).width >= kWebGlassAuthBreakpoint;

  /// Navigate back to landing page (e.g. when user came via Start VR and skips login/sign up).
  void _goBackToLanding() {
    if (Navigator.canPop(context)) {
      Navigator.pop(context);
    } else {
      Navigator.pushReplacementNamed(
        context,
        _isDesktopGlass ? '/landing' : '/login',
      );
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
        body: _isDesktopGlass
            ? _buildDesktopGlassLayout(context)
            : _buildMobileLayout(context),
      ),
    );
  }

  /// Desktop/tablet wide (â‰¥1024px): glassmorphism card over full-screen background.
  Widget _buildDesktopGlassLayout(BuildContext context) {
    final loginOnly = _loginRouteArgs?.loginOnly == true;

    return WebGlassAuthScaffold(
      child: WebGlassAuthCard(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(28, 24, 28, 32),
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Align(
                  alignment: Alignment.centerLeft,
                  child: WebGlassBackButton(onPressed: _goBackToLanding),
                ),
                const SizedBox(height: 20),
                const WebGlassLogoHeader(),
                const SizedBox(height: 28),
                _buildGlassFieldLabel('Email Address', required: true),
                const SizedBox(height: 10),
                WebGlassAuthTextField(
                  fieldKey: const Key('email-field'),
                  controller: _emailController,
                  hint: 'Enter email address',
                  prefixIcon: Icons.email_outlined,
                  keyboardType: TextInputType.emailAddress,
                  textInputAction: TextInputAction.next,
                  onFieldSubmitted: (_) {
                    if (_isLoading) return;
                    FocusScope.of(context).requestFocus(_passwordFocusNode);
                  },
                  onEditingComplete: () {
                    if (_isLoading) return;
                    FocusScope.of(context).requestFocus(_passwordFocusNode);
                  },
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
                _buildGlassFieldLabel('Password', required: true),
                const SizedBox(height: 10),
                WebGlassAuthTextField(
                  fieldKey: const Key('password-field'),
                  controller: _passwordController,
                  focusNode: _passwordFocusNode,
                  hint: 'Enter password',
                  prefixIcon: Icons.lock_outline_rounded,
                  obscureText: _obscurePassword,
                  textInputAction: TextInputAction.done,
                  onFieldSubmitted: (_) {
                    if (_isLoading) return;
                    _login();
                  },
                  onEditingComplete: () {
                    if (_isLoading) return;
                    _login();
                  },
                  suffixIcon: IconButton(
                    onPressed: _isLoading
                        ? null
                        : () => setState(
                              () => _obscurePassword = !_obscurePassword,
                            ),
                    tooltip:
                        _obscurePassword ? 'Show password' : 'Hide password',
                    icon: Icon(
                      _obscurePassword
                          ? Icons.visibility_off_rounded
                          : Icons.visibility_rounded,
                      color: Colors.white.withValues(alpha: 0.75),
                      size: 22,
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
                const SizedBox(height: 12),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    key: const Key('forgot-password-button'),
                    onPressed: _isLoading ? null : _openForgotPassword,
                    style: TextButton.styleFrom(
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 4,
                        vertical: 4,
                      ),
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    child: const Text(
                      'Forgot Password?',
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                WebGlassPrimaryButton(
                  testKey: const Key('sign-in-button'),
                  label: 'Sign In',
                  isLoading: _isLoading,
                  onPressed: _isLoading ? null : _login,
                ),
                if (!loginOnly) ...[
                  const SizedBox(height: 24),
                  Center(
                    child: Wrap(
                      alignment: WrapAlignment.center,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Text(
                          "Don't have an account? ",
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.75),
                            fontSize: 14,
                          ),
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
          ),
        ),
      ),
    );
  }

  Widget _buildGlassFieldLabel(String label, {bool required = false}) {
    return Row(
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: Colors.white.withValues(alpha: 0.92),
            letterSpacing: 0.2,
          ),
        ),
        if (required)
          Text(
            ' *',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: Colors.red.shade300,
            ),
          ),
      ],
    );
  }


  /// Mobile login matched to the attached mock (header + card composition).
  Widget _buildMobileLayout(BuildContext context) {
    final media = MediaQuery.of(context);
    final topPad = media.padding.top;
    final bottomPad = media.padding.bottom;
    final screenH = media.size.height;
    // Hero fills roughly the upper half like the mock, with room for the wave.
    final heroHeight = (screenH * 0.46).clamp(300.0, 420.0);

    return Stack(
      children: [
        const Positioned.fill(child: ColoredBox(color: Colors.white)),
        const Positioned.fill(
          child: CustomPaint(painter: _LoginTourismBackdropPainter()),
        ),
        SingleChildScrollView(
          physics: const BouncingScrollPhysics(),
          padding: EdgeInsets.only(bottom: 40 + bottomPad),
          child: Column(
            children: [
              SizedBox(
                height: heroHeight,
                width: double.infinity,
                child: _buildMobileHeroHeader(topPad: topPad),
              ),
              Transform.translate(
                offset: const Offset(0, -56),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: _buildLoginCard(child: _buildLoginForm()),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildMobileHeroHeader({required double topPad}) {
    return ClipPath(
      clipper: const _LoginHeroWaveClipper(),
      child: Stack(
        fit: StackFit.expand,
        children: [
          // Solid warm orange base (#F97316)
          const ColoredBox(color: _heroOrange),
          // Coastal landscape â€” visible mainly on the RIGHT
          Align(
            alignment: Alignment.centerRight,
            child: FractionallySizedBox(
              widthFactor: 0.78,
              heightFactor: 1,
              child: Image.asset(
                _loginHeroAsset,
                fit: BoxFit.cover,
                alignment: const Alignment(0.15, 0.0),
                errorBuilder: (_, __, ___) => const SizedBox.shrink(),
              ),
            ),
          ),
          // Leftâ†’right sunset wash: branding stays primary, photo secondary
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.centerLeft,
                end: Alignment.centerRight,
                colors: [
                  _heroOrange,
                  _heroOrange.withValues(alpha: 0.96),
                  _heroOrange.withValues(alpha: 0.72),
                  _heroOrange.withValues(alpha: 0.42),
                ],
                stops: const [0.0, 0.32, 0.62, 1.0],
              ),
            ),
          ),
          // Soft vertical sunset depth
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  _heroOrange.withValues(alpha: 0.20),
                  Colors.transparent,
                  _heroOrange.withValues(alpha: 0.35),
                ],
                stops: const [0.0, 0.45, 1.0],
              ),
            ),
          ),
          // Airplane + dotted flight path (TOP-LEFT)
          Positioned(
            top: topPad + 8,
            left: 12,
            child: const CustomPaint(
              size: Size(92, 48),
              painter: _FlightPathPainter(),
            ),
          ),
          // Back control â€” absolute so branding stays centered like the mock
          Positioned(
            top: topPad + 2,
            left: 4,
            child: IconButton(
              key: const Key('back-to-landing-button'),
              icon: Icon(
                Icons.arrow_back_ios_new_rounded,
                color: Colors.white.withValues(alpha: 0.85),
                size: 18,
              ),
              onPressed: _goBackToLanding,
              tooltip: 'Back to home',
            ),
          ),
          // Centered logo + titles
          Padding(
            padding: EdgeInsets.fromLTRB(24, topPad + 36, 24, 56),
            child: Align(
              alignment: Alignment.center,
              child: _buildHeaderBranding(),
            ),
          ),
        ],
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
          Text(
            'Welcome!',
            textAlign: TextAlign.center,
            // Sacrifice is a DEMO font (shows "Heinzel Studio") — use a real script face.
            style: GoogleFonts.greatVibes(
              fontSize: 44,
              height: 1.05,
              color: _heroOrange,
              fontWeight: FontWeight.w400,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Sign in to continue',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: _textDark,
              fontSize: 18,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.3,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            subtitle ??
                "Access your account and explore Misamis Occidental's beautiful destinations.",
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: _textMuted,
              fontSize: 12.5,
              height: 1.45,
              fontWeight: FontWeight.w400,
            ),
          ),
          const SizedBox(height: 28),
          _buildLabeledField(
            label: 'Email Address',
            icon: Icons.email_rounded,
            field: TextFormField(
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
              style: const TextStyle(
                color: _textDark,
                fontSize: 14.5,
                fontWeight: FontWeight.w500,
              ),
              decoration: _inputDecoration(hint: 'Enter email address'),
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
          ),
          const SizedBox(height: 18),
          _buildLabeledField(
            label: 'Password',
            icon: Icons.lock_rounded,
            field: TextFormField(
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
              style: const TextStyle(
                color: _textDark,
                fontSize: 14.5,
                fontWeight: FontWeight.w500,
              ),
              decoration: _inputDecoration(
                hint: 'Enter password',
                suffixIcon: IconButton(
                  onPressed: _isLoading
                      ? null
                      : () => setState(
                            () => _obscurePassword = !_obscurePassword,
                          ),
                  tooltip:
                      _obscurePassword ? 'Show password' : 'Hide password',
                  icon: Icon(
                    _obscurePassword
                        ? Icons.visibility_off_rounded
                        : Icons.visibility_rounded,
                    color: const Color(0xFF9CA3AF),
                    size: 20,
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
          ),
          const SizedBox(height: 10),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              key: const Key('forgot-password-button'),
              onPressed: _isLoading ? null : _openForgotPassword,
              style: TextButton.styleFrom(
                foregroundColor: _heroOrange,
                padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 2),
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: const Text(
                'Forgot Password? >',
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                ),
              ),
            ),
          ),
          const SizedBox(height: 18),
          SizedBox(
            width: double.infinity,
            height: 54,
            child: FilledButton(
              key: const Key('sign-in-button'),
              onPressed: _isLoading ? null : _login,
              style: FilledButton.styleFrom(
                backgroundColor: _heroOrange,
                foregroundColor: Colors.white,
                disabledBackgroundColor: _heroOrange.withValues(alpha: 0.65),
                elevation: 0,
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
                        valueColor:
                            AlwaysStoppedAnimation<Color>(Colors.white),
                      ),
                    )
                  : const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.login_rounded, size: 20),
                        SizedBox(width: 8),
                        Text(
                          'Sign In',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.2,
                          ),
                        ),
                      ],
                    ),
            ),
          ),
          if (!loginOnly) ...[
            const SizedBox(height: 22),
            Center(
              child: Wrap(
                alignment: WrapAlignment.center,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  const Text(
                    "Don't have an account? ",
                    style: TextStyle(color: _textMuted, fontSize: 13.5),
                  ),
                  GestureDetector(
                    key: const Key('sign-up-button'),
                    onTap: () => Navigator.pushNamed(context, '/signup'),
                    child: const Text(
                      'Sign Up >',
                      style: TextStyle(
                        color: _heroOrange,
                        fontWeight: FontWeight.w700,
                        fontSize: 13.5,
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

/// Soft organic wave â€” orange hero â†’ white bottom (matches mock).
class _LoginHeroWaveClipper extends CustomClipper<Path> {
  const _LoginHeroWaveClipper();

  @override
  Path getClip(Size size) {
    final w = size.width;
    final h = size.height;
    return Path()
      ..lineTo(0, h - 42)
      ..cubicTo(
        w * 0.18,
        h - 8,
        w * 0.38,
        h - 58,
        w * 0.55,
        h - 34,
      )
      ..cubicTo(
        w * 0.72,
        h - 12,
        w * 0.88,
        h - 48,
        w,
        h - 22,
      )
      ..lineTo(w, 0)
      ..close();
  }

  @override
  bool shouldReclip(covariant CustomClipper<Path> oldClipper) => false;
}

/// White airplane silhouette + curved dotted flight path (top-left of mock).
class _FlightPathPainter extends CustomPainter {
  const _FlightPathPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final dashPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.82)
      ..strokeWidth = 1.7
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    final path = Path()
      ..moveTo(2, size.height * 0.78)
      ..quadraticBezierTo(
        size.width * 0.28,
        size.height * 0.08,
        size.width * 0.62,
        size.height * 0.42,
      );

    for (final metric in path.computeMetrics()) {
      var distance = 0.0;
      const dash = 3.5;
      const gap = 4.5;
      while (distance < metric.length) {
        final next = (distance + dash).clamp(0.0, metric.length);
        canvas.drawPath(metric.extractPath(distance, next), dashPaint);
        distance += dash + gap;
      }
    }

    // Airplane silhouette near end of trail
    final tip = Offset(size.width * 0.70, size.height * 0.38);
    canvas.save();
    canvas.translate(tip.dx, tip.dy);
    canvas.rotate(-0.55);
    final plane = Path()
      ..moveTo(10, 0)
      ..lineTo(-8, 5)
      ..lineTo(-4, 1.2)
      ..lineTo(-12, -1)
      ..lineTo(-4, -1.2)
      ..lineTo(-7, -5.5)
      ..close();
    canvas.drawPath(
      plane,
      Paint()..color = Colors.white.withValues(alpha: 0.95),
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// Soft Misamis Occidental tourism motifs under the floating login card.
class _LoginTourismBackdropPainter extends CustomPainter {
  const _LoginTourismBackdropPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    final wave1 = Path()
      ..moveTo(0, h * 0.90)
      ..quadraticBezierTo(w * 0.28, h * 0.86, w * 0.52, h * 0.91)
      ..quadraticBezierTo(w * 0.78, h * 0.96, w, h * 0.88)
      ..lineTo(w, h)
      ..lineTo(0, h)
      ..close();
    canvas.drawPath(
      wave1,
      Paint()..color = const Color(0xFFF97316).withValues(alpha: 0.06),
    );

    final wave2 = Path()
      ..moveTo(0, h * 0.94)
      ..quadraticBezierTo(w * 0.32, h * 0.98, w * 0.58, h * 0.93)
      ..quadraticBezierTo(w * 0.82, h * 0.89, w, h * 0.95)
      ..lineTo(w, h)
      ..lineTo(0, h)
      ..close();
    canvas.drawPath(
      wave2,
      Paint()..color = const Color(0xFFF97316).withValues(alpha: 0.09),
    );

    final leafPaint = Paint()
      ..color = const Color(0xFFF97316).withValues(alpha: 0.10)
      ..style = PaintingStyle.fill;
    canvas.drawOval(
      Rect.fromCenter(center: Offset(w * 0.06, h * 0.95), width: 64, height: 30),
      leafPaint,
    );
    canvas.drawOval(
      Rect.fromCenter(center: Offset(w * 0.14, h * 0.97), width: 50, height: 24),
      leafPaint,
    );
    canvas.drawOval(
      Rect.fromCenter(center: Offset(w * 0.10, h * 0.92), width: 36, height: 18),
      leafPaint,
    );

    final line = Paint()
      ..color = const Color(0xFFF97316).withValues(alpha: 0.22)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..strokeJoin = StrokeJoin.round
      ..strokeCap = StrokeCap.round;

    canvas.drawCircle(Offset(w * 0.86, h * 0.88), 7, line);

    final mountains = Path()
      ..moveTo(w * 0.62, h * 0.98)
      ..lineTo(w * 0.70, h * 0.90)
      ..lineTo(w * 0.76, h * 0.95)
      ..lineTo(w * 0.84, h * 0.87)
      ..lineTo(w * 0.92, h * 0.96)
      ..lineTo(w * 0.98, h * 0.92);
    canvas.drawPath(mountains, line);

    canvas.drawArc(
      Rect.fromCenter(center: Offset(w * 0.80, h * 0.97), width: 54, height: 10),
      0.15,
      2.8,
      false,
      line,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

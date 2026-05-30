import 'package:flutter/material.dart';
import 'package:atmos_trs_system/config/app_theme.dart';
import 'package:atmos_trs_system/config/atmos_brand_typography.dart';
import 'package:flutter/services.dart';
import 'package:atmos_trs_system/config/auth_config.dart';
import 'package:atmos_trs_system/config/session_storage.dart';
import 'package:atmos_trs_system/utils/email_utils.dart';
import 'package:atmos_trs_system/utils/logo_utils.dart';
import 'package:atmos_trs_system/utils/municipality_helper.dart';
import 'package:atmos_trs_system/utils/firebase_client_blocked_message.dart';
import 'package:atmos_trs_system/services/dashboard_user_service.dart';
import 'package:atmos_trs_system/services/user_directory_service.dart';
import 'package:atmos_trs_system/navigation/role_router.dart';
import 'package:atmos_trs_system/navigation/pending_checkin_navigation.dart';
import 'package:atmos_trs_system/services/pending_spot_checkin_storage.dart';
import 'package:atmos_trs_system/services/pending_lgu_checkin_storage.dart';
import 'package:atmos_trs_system/services/tourist_profile_hydration.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';

/// Same long form as the landing page hero / app title.
const String _kAtmosTrsFullName =
    'Asenso Tourismo Misamis Occidental Smart Tourist Registration System';

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

  @override
  void dispose() {
    TextInput.finishAutofillContext(shouldSave: false);
    _emailController.dispose();
    _passwordController.dispose();
    _passwordFocusNode.dispose();
    super.dispose();
  }

  bool _isLoading = false;
  bool _obscurePassword = true;

  /// Signs in with email/password. For [SessionStorage] demo staff credentials only,
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

      await UserDirectoryService.syncVerifiedStatusFromAuthIfNeeded(uid);

      // 1) Canonical profile: users/{uid} or query by email
      AppUserProfile? profile =
          await UserDirectoryService.getProfileByUid(uid, preferServer: true) ??
          await UserDirectoryService.getProfileByEmail(email);

      if (profile != null) {
        if (profile.isGovernor || profile.isTourismOffice) {
          await UserDirectoryService.ensureStaffUserDoc(
            uid: uid,
            email: profile.email,
            roleRaw: profile.roleRaw,
            fullName: profile.fullName,
          );
        }
        if (profile.isTourist) {
          await _loadTouristProfile(uid, email);
        }
        final route = await RoleRouter.persistSessionAndGetRoute(
          profile: profile,
          firebaseUid: uid,
        );
        setState(() => _isLoading = false);
        if (!mounted) return;
        if (!profile.isTourist) {
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
        await navigateToPendingSpotCheckInOrDashboard(
          context,
          defaultRoute: route,
          isTouristDestination: route == '/dashboard',
        );
        return;
      }

      // 2) Legacy rows: older `users` docs queried by DashboardUserService shape
      final dash = await DashboardUserService.getProfileByEmail(email);
      if (dash != null && dash.role == 'governor') {
        await UserDirectoryService.ensureStaffUserDoc(
          uid: uid,
          email: email,
          roleRaw: 'governor',
        );
        await SessionStorage.saveSession(
          uid,
          role: UserRole.governor,
          email: email,
        );
        await _loadTouristProfile(uid, email);
        setState(() => _isLoading = false);
        if (!mounted) return;
        await PendingSpotCheckInStorage.clear();
        await PendingLguCheckInStorage.clear();
        if (!mounted) return;
        Navigator.pushReplacementNamed(context, '/governor-dashboard');
        return;
      }
      if (dash != null && dash.role == 'tourism') {
        await UserDirectoryService.ensureStaffUserDoc(
          uid: uid,
          email: email,
          roleRaw: 'tourism',
        );
        String municipalityId = getMunicipalityIdFromName(dash.municipality);
        if (municipalityId.isEmpty) {
          municipalityId =
              SessionStorage.getMunicipalityIdFromTourismEmail(email) ?? '';
        }
        await SessionStorage.saveSession(
          uid,
          role: UserRole.tourism,
          email: email,
          municipalityId: municipalityId.isNotEmpty ? municipalityId : null,
        );
        await _loadTouristProfile(uid, email);
        setState(() => _isLoading = false);
        if (!mounted) return;
        await PendingSpotCheckInStorage.clear();
        await PendingLguCheckInStorage.clear();
        if (!mounted) return;
        Navigator.pushReplacementNamed(context, '/tourism-dashboard');
        return;
      }

      // 3) Legacy email pattern (tourism.*@...) without a full user doc
      final legacyMunId = SessionStorage.getMunicipalityIdFromTourismEmail(
        email,
      );
      if (legacyMunId != null) {
        await SessionStorage.saveSession(
          uid,
          role: UserRole.tourism,
          email: email,
          municipalityId: legacyMunId,
        );
        await _loadTouristProfile(uid, email);
        setState(() => _isLoading = false);
        if (!mounted) return;
        await PendingSpotCheckInStorage.clear();
        await PendingLguCheckInStorage.clear();
        if (!mounted) return;
        Navigator.pushReplacementNamed(context, '/tourism-dashboard');
        return;
      }

      // 3b) Demo governor in SessionStorage but no `users` row yet (Auth was just provisioned)
      if (email.toLowerCase().trim() ==
              SessionStorage.governorEmail.toLowerCase() &&
          await SessionStorage.validateCredentialsAsync(email, password)) {
        final synthetic = AppUserProfile(
          uid: uid,
          email: email,
          roleRaw: 'governor',
          isVerified: true,
        );
        await _loadTouristProfile(uid, email);
        final route = await RoleRouter.persistSessionAndGetRoute(
          profile: synthetic,
          firebaseUid: uid,
        );
        setState(() => _isLoading = false);
        if (!mounted) return;
        await PendingSpotCheckInStorage.clear();
        await PendingLguCheckInStorage.clear();
        if (!mounted) return;
        Navigator.pushReplacementNamed(context, route);
        return;
      }

      // 3c) Demo tourism office in SessionStorage but no `users` row yet
      if (email.toLowerCase().trim() ==
              SessionStorage.tourismEmail.toLowerCase() &&
          await SessionStorage.validateCredentialsAsync(email, password)) {
        final synthetic = AppUserProfile(
          uid: uid,
          email: email,
          roleRaw: 'tourism',
          isVerified: true,
        );
        await _loadTouristProfile(uid, email);
        final route = await RoleRouter.persistSessionAndGetRoute(
          profile: synthetic,
          firebaseUid: uid,
        );
        setState(() => _isLoading = false);
        if (!mounted) return;
        await PendingSpotCheckInStorage.clear();
        await PendingLguCheckInStorage.clear();
        if (!mounted) return;
        Navigator.pushReplacementNamed(context, route);
        return;
      }

      // 4) Tourist-only `tourists` registration without `users` doc (migration)
      final migratedVerified =
          await UserDirectoryService.getTouristIsVerifiedFromTouristsDoc(uid);
      final emailVerified =
          FirebaseAuth.instance.currentUser?.emailVerified ?? false;
      final synthetic = AppUserProfile(
        uid: uid,
        email: email,
        roleRaw: 'tourist',
        isVerified: (migratedVerified == true) || emailVerified,
      );
      await _loadTouristProfile(uid, email);
      final route = await RoleRouter.persistSessionAndGetRoute(
        profile: synthetic,
        firebaseUid: uid,
      );
      setState(() => _isLoading = false);
      if (!mounted) return;
      if (route == '/verify-otp') {
        Navigator.pushReplacementNamed(context, route);
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

  void _openForgotPassword() {
    Navigator.pushNamed(
      context,
      '/forgot-password',
      arguments: _emailController.text.trim(),
    );
  }

  Future<void> _loadTouristProfile(String uid, String email) async {
    final rawEmail = _emailController.text.trim();
    await TouristProfileHydration.hydrateFromFirestore(
      uid: uid,
      email: email.isNotEmpty ? email : rawEmail,
    );
  }

  static const Color _backgroundCream = Color(0xFFFFF7ED); // orange-50
  static const Color _cardWhite = Colors.white;
  static const Color _textDark = Color(0xFF1A1A1A);
  static const Color _textMuted = Color(0xFF6B7280);
  static const Color _inputBorder = Color(0xFFE5E7EB);

  InputDecoration _inputDecoration({required String hint, Widget? suffixIcon}) {
    return InputDecoration(
      hintText: hint,
      hintStyle: TextStyle(color: _textMuted.withOpacity(0.6), fontSize: 14),
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
                child: _buildAuthContent(),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Mobile: same layout as before (scrollable header + form card).
  Widget _buildMobileLayout(BuildContext context) {
    return SingleChildScrollView(child: _buildAuthContent());
  }

  /// Shared auth UI: orange header + white form card (same on web and mobile).
  /// On web: single cohesive card with rounded corners and shadow (per reference image).
  Widget _buildAuthContent() {
    final header = Container(
      width: double.infinity,
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [AppTheme.brandOrange, AppTheme.brandOrangeLight],
        ),
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
          padding: const EdgeInsets.fromLTRB(24, 32, 24, 50),
          child: Column(
            children: [
              Row(
                children: [
                  IconButton(
                    key: const Key('back-to-landing-button'),
                    icon: const Icon(
                      Icons.arrow_back_rounded,
                      color: Colors.white,
                      size: 28,
                    ),
                    onPressed: _goBackToLanding,
                    tooltip: 'Back to home',
                  ),
                  const Spacer(),
                ],
              ),
              Center(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    return ConstrainedBox(
                      constraints: BoxConstraints(
                        maxWidth: constraints.maxWidth,
                        maxHeight: 96,
                      ),
                      child: TransparentLogo(height: 96, fit: BoxFit.contain),
                    );
                  },
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'ATMOS TRS',
                textAlign: TextAlign.center,
                style: AtmosBrandTypography.displayTitle(
                  color: Colors.white,
                  fontSize: 40,
                  letterSpacing: 0.8,
                ),
              ),
              const SizedBox(height: 12),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Text(
                  _kAtmosTrsFullName,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.92),
                    fontSize: 13,
                    height: 1.4,
                    fontWeight: FontWeight.w500,
                    letterSpacing: 0.15,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );

    final formSection = _isWeb
        ? Container(
            width: double.infinity,
            decoration: const BoxDecoration(
              color: _cardWhite,
              borderRadius: BorderRadius.only(
                bottomLeft: Radius.circular(24),
                bottomRight: Radius.circular(24),
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: _buildLoginForm(),
              ),
            ),
          )
        : Transform.translate(
            offset: const Offset(0, -30),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Container(
                width: double.infinity,
                decoration: BoxDecoration(
                  color: _cardWhite,
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(
                    color: AppTheme.brandOrange.withOpacity(0.12),
                    width: 1,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.06),
                      blurRadius: 24,
                      offset: const Offset(0, 4),
                      spreadRadius: 0,
                    ),
                  ],
                ),
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: _buildLoginForm(),
                ),
              ),
            ),
          );

    if (_isWeb) {
      return Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(24),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.08),
              blurRadius: 28,
              offset: const Offset(0, 10),
              spreadRadius: 0,
            ),
            BoxShadow(
              color: AppTheme.brandOrange.withOpacity(0.06),
              blurRadius: 36,
              offset: const Offset(0, 14),
              spreadRadius: -4,
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [header, formSection],
          ),
        ),
      );
    }
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [header, formSection],
    );
  }

  Widget _buildLoginForm() {
    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text(
                'Email Address',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: _textDark,
                ),
              ),
              const Text(
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
            decoration: _inputDecoration(hint: 'Enter email address'),
            validator: (value) {
              if (value == null || value.isEmpty)
                return 'Please enter your email';
              if (!isValidEmailFormat(value)) {
                return 'Please enter a valid email';
              }
              return null;
            },
          ),
          const SizedBox(height: 20),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  const Text(
                    'Password',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      color: _textDark,
                    ),
                  ),
                  const Text(
                    ' *',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      color: Colors.red,
                    ),
                  ),
                ],
              ),
              TextButton(
                key: const Key('forgot-password-button'),
                onPressed: _isLoading ? null : _openForgotPassword,
                style: TextButton.styleFrom(
                  padding: EdgeInsets.zero,
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child: Text(
                  'Forgot password?',
                  style: TextStyle(
                    color: AppTheme.brandOrange,
                    fontWeight: FontWeight.w500,
                    fontSize: 13,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
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
              if (value == null || value.isEmpty)
                return 'Please enter your password';
              if (value.length < 6)
                return 'Password must be at least 6 characters';
              return null;
            },
          ),
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              key: const Key('sign-in-button'),
              onPressed: _isLoading ? null : _login,
              style: FilledButton.styleFrom(
                backgroundColor: AppTheme.brandOrange,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                elevation: 0,
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
                  : const Text(
                      'Sign In',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
            ),
          ),
          const SizedBox(height: 24),
          Center(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Text(
                  "Don't have an account? ",
                  style: TextStyle(color: _textMuted, fontSize: 14),
                ),
                GestureDetector(
                  key: const Key('sign-up-button'),
                  onTap: () => Navigator.pushNamed(context, '/signup'),
                  child: Text(
                    'Sign Up',
                    style: TextStyle(
                      color: AppTheme.brandOrange,
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                      decoration: TextDecoration.underline,
                      decorationColor: AppTheme.brandOrange,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

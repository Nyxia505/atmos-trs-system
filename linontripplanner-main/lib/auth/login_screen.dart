import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../data.dart';
import '../services/admin_session_bootstrap.dart';
import '../services/auth_role_claims.dart';
import '../services/admin_accounts_service.dart';
import '../services/tourism_session.dart';
import 'auth_navigation.dart';
import 'auth_widgets.dart';
import 'registration_form_cache.dart';

class LoginScreen extends StatefulWidget {
  static const routeName = '/login';

  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _obscure = true;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      RegistrationFormCache.warmUp();
    });
  }

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  void _openSignUp() {
    if (_busy) return;
    pushRegistrationScreen(context);
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _busy = true);
    try {
      final email = _email.text.trim();
      final password = _password.text;

      await FirebaseAuth.instance.signInWithEmailAndPassword(
        email: email,
        password: password,
      );

      final openAdminDashboard = await resolveOpenAdminDashboardAfterLogin();

      if (!mounted) return;
      navigateAfterSuccessfulLogin(
        context,
        openAdminDashboard: openAdminDashboard,
      );

      if (openAdminDashboard) {
        await AdminAccountsService.applyAdminRoleIfRegistered();
        await persistLongTermStaffRoleClaims();
        unawaited(reloadAdminDashboardCatalogs());
      }
      unawaited(bootstrapAppFirestoreOnce());
    } on FirebaseAuthException catch (e) {
      if (!mounted) return;
      final feedback = _loginFeedback(e);
      if (feedback.clearPassword) {
        _password.clear();
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(feedback.message),
          action: feedback.signUp
              ? SnackBarAction(
                  label: 'Sign Up',
                  onPressed: _openSignUp,
                )
              : feedback.forgotPassword
                  ? SnackBarAction(
                      label: 'Forgot Password',
                      onPressed: _forgotPassword,
                    )
                  : null,
        ),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not sign in. Please try again.'),
        ),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _forgotPassword() async {
    final email = _email.text.trim();
    if (email.isEmpty || !email.contains('@')) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Enter your email above, then tap Forgot password.'),
        ),
      );
      return;
    }
    try {
      await FirebaseAuth.instance.sendPasswordResetEmail(email: email);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Password reset email sent.')),
      );
    } on FirebaseAuthException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_loginFeedback(e).message)),
      );
    }
  }

  static ({String message, bool clearPassword, bool signUp, bool forgotPassword})
      _loginFeedback(FirebaseAuthException e) {
    switch (e.code.replaceAll('_', '-')) {
      case 'user-not-found':
        return (
          message:
              'Sorry, your email is not registered. Please sign up first.',
          clearPassword: false,
          signUp: true,
          forgotPassword: false,
        );
      case 'wrong-password':
        return (
          message:
              'Sorry, your password is incorrect. Please try again.',
          clearPassword: true,
          signUp: false,
          forgotPassword: true,
        );
      case 'invalid-credential':
      case 'invalid-login-credentials':
        return (
          message:
              'Incorrect email or password. Please try again or sign up.',
          clearPassword: true,
          signUp: true,
          forgotPassword: false,
        );
      case 'invalid-email':
        return (
          message: 'Please enter a valid email address.',
          clearPassword: false,
          signUp: false,
          forgotPassword: false,
        );
      case 'too-many-requests':
        return (
          message: 'Too many attempts. Please try again later.',
          clearPassword: false,
          signUp: false,
          forgotPassword: false,
        );
      case 'network-request-failed':
        return (
          message:
              'Unable to connect. Please check your internet connection.',
          clearPassword: false,
          signUp: false,
          forgotPassword: false,
        );
      case 'user-disabled':
        return (
          message: 'This account has been disabled.',
          clearPassword: false,
          signUp: false,
          forgotPassword: false,
        );
      default:
        return (
          message: 'Could not sign in. Please try again.',
          clearPassword: false,
          signUp: false,
          forgotPassword: false,
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    const surfaceOpacity = AuthDesign.loginSurfaceOpacity;

    return Scaffold(
      body: AuthLoginPhotoBackground(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Stack(
              clipBehavior: Clip.none,
              children: [
                AuthLoginBrandHeader(
                  surfaceOpacity: surfaceOpacity,
                  fullWidth: true,
                ),
                if (Navigator.of(context).canPop())
                  Positioned(
                    top: 4,
                    left: 4,
                    child: IconButton(
                      onPressed: () => Navigator.maybePop(context),
                      icon: const Icon(Icons.arrow_back_ios_new, size: 20),
                      color: Colors.white,
                    ),
                  ),
              ],
            ),
            AuthLoginFormScroll(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Material(
              elevation: 0,
              borderRadius: BorderRadius.circular(20),
              color: Colors.white.withValues(alpha: surfaceOpacity),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 24, 20, 22),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const AuthFieldLabel('Email Address', required: true),
                      AuthTextField(
                        controller: _email,
                        hint: 'Enter email address',
                        icon: Icons.mail_outline_rounded,
                        keyboardType: TextInputType.emailAddress,
                        textInputAction: TextInputAction.next,
                        enabled: !_busy,
                        validator: (v) {
                          final s = v?.trim() ?? '';
                          if (s.isEmpty) {
                            return 'Please enter your email address.';
                          }
                          if (!s.contains('@')) {
                            return 'Please enter a valid email address.';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 18),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Expanded(
                            child:
                                AuthFieldLabel('Password', required: true),
                          ),
                          TextButton(
                            onPressed: _busy ? null : _forgotPassword,
                            style: TextButton.styleFrom(
                              padding: EdgeInsets.zero,
                              minimumSize: Size.zero,
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                              foregroundColor: AppColors.primary,
                            ),
                            child: const Text(
                              'Forgot password?',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),
                      AuthTextField(
                        controller: _password,
                        hint: 'Enter password',
                        icon: Icons.lock_outline_rounded,
                        obscure: _obscure,
                        textInputAction: TextInputAction.go,
                        enabled: !_busy,
                        onFieldSubmitted: (_) {
                          if (!_busy) _submit();
                        },
                        suffix: IconButton(
                          onPressed: () => setState(() => _obscure = !_obscure),
                          icon: Icon(
                            _obscure
                                ? Icons.visibility_off_outlined
                                : Icons.visibility_outlined,
                            color: AuthDesign.secondaryText,
                          ),
                        ),
                        validator: (v) {
                          if (v == null || v.isEmpty) {
                            return 'Please enter your password.';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 10),
                      Text(
                        'Do not save this password in your browser on shared or public computers.',
                        style: TextStyle(
                          color: AuthDesign.secondaryText.withValues(
                            alpha: 0.9,
                          ),
                          fontSize: 12,
                          height: 1.3,
                        ),
                      ),
                      const SizedBox(height: 22),
                      AuthPrimaryButton(
                        label: _busy ? 'Signing in…' : 'Sign In',
                        onPressed: _busy ? null : _submit,
                      ),
                      const SizedBox(height: 18),
                          Center(
                            child: Wrap(
                              alignment: WrapAlignment.center,
                              crossAxisAlignment: WrapCrossAlignment.center,
                              children: [
                                const Text(
                                  "Don't have an account? ",
                                  style: TextStyle(
                                    color: AuthDesign.secondaryText,
                                    fontSize: 14,
                                  ),
                                ),
                                TextButton(
                                  onPressed: _busy ? null : _openSignUp,
                                  style: TextButton.styleFrom(
                                    foregroundColor: AppColors.primary,
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 4,
                                      vertical: 0,
                                    ),
                                    minimumSize: Size.zero,
                                    tapTargetSize:
                                        MaterialTapTargetSize.shrinkWrap,
                                  ),
                                  child: const Text(
                                    'Sign Up',
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 14,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                    ],
                  ),
                ),
              ),
            ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
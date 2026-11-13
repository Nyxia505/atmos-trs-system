import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../data.dart';
import '../services/otp_delivery_service.dart';
import '../services/otp_service.dart';
import '../services/pending_trip_registration_cache.dart';
import '../services/trip_registration_completion_service.dart';
import 'auth_navigation.dart';
import 'auth_widgets.dart';

/// Email OTP verification after deferred Trip Planner signup (ATMOS-style).
class VerifyOtpScreen extends StatefulWidget {
  static const routeName = '/verify-otp';

  const VerifyOtpScreen({
    super.key,
    this.contactEmail,
  });

  final String? contactEmail;

  @override
  State<VerifyOtpScreen> createState() => _VerifyOtpScreenState();
}

class _VerifyOtpScreenState extends State<VerifyOtpScreen> {
  final _code = TextEditingController();
  bool _busy = false;
  bool _resending = false;
  String? _email;

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    final pending = await PendingTripRegistrationCache.hydrate();
    if (!mounted) return;
    setState(() {
      _email = widget.contactEmail?.trim().isNotEmpty == true
          ? widget.contactEmail!.trim()
          : pending?.email;
    });
  }

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  Future<void> _verify() async {
    if (_busy) return;
    final code = _code.text.trim();
    if (code.length != 6) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter the 6-digit code from your email.')),
      );
      return;
    }

    setState(() => _busy = true);
    try {
      final pending = await PendingTripRegistrationCache.hydrate();
      if (pending == null) {
        throw StateError('Signup session expired. Please register again.');
      }

      final outcome = await OtpService.verifyOtpPreAuth(
        pendingId: pending.otpKey,
        enteredOtp: code,
      );
      if (!outcome.ok) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(outcome.message ?? 'Invalid code')),
        );
        return;
      }

      await TripRegistrationCompletionService.createAuthAndCompleteAfterOtp(
        pending: pending,
      );

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Registration complete. Welcome!')),
      );
      navigateAfterSuccessfulLogin(context, openAdminDashboard: false);
    } on FirebaseAuthException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.message ?? 'Registration failed (${e.code})')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$e')),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _resend() async {
    if (_resending || _busy) return;
    setState(() => _resending = true);
    try {
      final pending = await PendingTripRegistrationCache.hydrate();
      if (pending == null) {
        throw StateError('Signup session expired. Please register again.');
      }
      final otp = OtpService.generateSixDigitOtp();
      await OtpService.saveOtpPreAuth(
        pendingId: pending.otpKey,
        email: pending.email,
        otp: otp,
      );
      final delivery = await OtpDeliveryService.deliverVerificationCode(
        email: pending.email,
        displayName: pending.fullName,
        otp: otp,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(delivery.messageForUser(pending.email))),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not resend: $e')),
      );
    } finally {
      if (mounted) setState(() => _resending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final email = _email ?? 'your email';
    return Scaffold(
      backgroundColor: AuthDesign.creamBackground,
      body: AuthCenteredScrollPage(
        child: AuthWhiteCard(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const AuthCardHeroIcon(icon: Icons.mark_email_read_outlined),
              const SizedBox(height: 12),
              const Text(
                'Verify your email',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: AppColors.textDark,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                'Enter the 6-digit code sent to\n$email',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 14,
                  color: AppColors.textGrey,
                  height: 1.35,
                ),
              ),
              const SizedBox(height: 22),
              AuthTextField(
                controller: _code,
                hint: '6-digit code',
                icon: Icons.password_outlined,
                keyboardType: TextInputType.number,
              ),
              const SizedBox(height: 18),
              AuthPrimaryButton(
                label: _busy ? 'Verifying…' : 'Verify & create account',
                icon: Icons.check_rounded,
                onPressed: _busy ? null : _verify,
              ),
              const SizedBox(height: 12),
              TextButton(
                onPressed: (_busy || _resending) ? null : _resend,
                child: Text(
                  _resending ? 'Sending…' : 'Resend code',
                  style: const TextStyle(color: AppColors.primary),
                ),
              ),
              TextButton(
                onPressed: _busy
                    ? null
                    : () {
                        Navigator.of(context).pop();
                      },
                child: const Text('Back to registration'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

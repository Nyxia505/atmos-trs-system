import 'package:atmos_trs_system/navigation/guest_startup_routes.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('unauthenticated mobile users land on Welcome, not Login', () {
    expect(
      GuestStartupRoutes.unauthenticatedRoute(
        isWeb: false,
        hasPendingQr: false,
      ),
      GuestStartupRoutes.welcome,
    );
  });

  test('pending QR check-in opens QR entry gate', () {
    expect(
      GuestStartupRoutes.unauthenticatedRoute(
        isWeb: false,
        hasPendingQr: true,
      ),
      GuestStartupRoutes.qrEntry,
    );
  });

  test('pending QR on web also opens QR entry gate', () {
    expect(
      GuestStartupRoutes.unauthenticatedRoute(
        isWeb: true,
        hasPendingQr: true,
      ),
      GuestStartupRoutes.qrEntry,
    );
  });

  test('web guests still use the public landing page', () {
    expect(
      GuestStartupRoutes.unauthenticatedRoute(
        isWeb: true,
        hasPendingQr: false,
      ),
      '/landing',
    );
  });

  test('refine does not pull users out of Welcome or onboarding', () {
    expect(
      GuestStartupRoutes.shouldSkipAuthoritativeReplace(
        currentRoute: GuestStartupRoutes.welcome,
        authoritative: GuestStartupRoutes.login,
      ),
      isTrue,
    );
    expect(
      GuestStartupRoutes.shouldSkipAuthoritativeReplace(
        currentRoute: GuestStartupRoutes.onboarding,
        authoritative: GuestStartupRoutes.welcome,
      ),
      isTrue,
    );
    expect(
      GuestStartupRoutes.shouldSkipAuthoritativeReplace(
        currentRoute: GuestStartupRoutes.splash,
        authoritative: GuestStartupRoutes.welcome,
      ),
      isTrue,
    );
  });

  test('refine still sends a restored tourist to Home', () {
    expect(
      GuestStartupRoutes.shouldSkipAuthoritativeReplace(
        currentRoute: GuestStartupRoutes.welcome,
        authoritative: '/dashboard',
      ),
      isFalse,
    );
  });

  test('Login is not replaced by Landing while still unauthenticated', () {
    expect(
      GuestStartupRoutes.shouldSkipAuthoritativeReplace(
        currentRoute: GuestStartupRoutes.login,
        authoritative: '/landing',
      ),
      isTrue,
    );
  });

  test('Login is not replaced by QR entry while still unauthenticated', () {
    expect(
      GuestStartupRoutes.shouldSkipAuthoritativeReplace(
        currentRoute: GuestStartupRoutes.login,
        authoritative: GuestStartupRoutes.qrEntry,
      ),
      isTrue,
    );
  });

  test('Login may still refine into Tourist Home after auth', () {
    expect(
      GuestStartupRoutes.shouldSkipAuthoritativeReplace(
        currentRoute: GuestStartupRoutes.login,
        authoritative: '/dashboard',
      ),
      isFalse,
    );
  });

  test('Sign Up and Forgot Password stay open when refine prefers Landing', () {
    expect(
      GuestStartupRoutes.shouldSkipAuthoritativeReplace(
        currentRoute: GuestStartupRoutes.signupTouristQr,
        authoritative: '/landing',
      ),
      isTrue,
    );
    expect(
      GuestStartupRoutes.shouldSkipAuthoritativeReplace(
        currentRoute: GuestStartupRoutes.forgotPassword,
        authoritative: '/landing',
      ),
      isTrue,
    );
  });
}

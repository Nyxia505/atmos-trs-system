import 'package:atmos_trs_system/utils/password_sign_in_guard.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('PasswordSignInGuard.credentialMatchesAttempt', () {
    test('rejects a missing Auth user', () {
      expect(
        PasswordSignInGuard.credentialMatchesAttempt(
          submittedEmail: 'user@example.com',
          authenticatedEmail: 'user@example.com',
          authenticatedUid: null,
        ),
        isFalse,
      );
    });

    test('rejects a leftover session for a different email', () {
      expect(
        PasswordSignInGuard.credentialMatchesAttempt(
          submittedEmail: 'new@example.com',
          authenticatedEmail: 'old@example.com',
          authenticatedUid: 'uid-old',
        ),
        isFalse,
      );
    });

    test('accepts only the submitted email after a real sign-in', () {
      expect(
        PasswordSignInGuard.credentialMatchesAttempt(
          submittedEmail: '  User@Example.com ',
          authenticatedEmail: 'user@example.com',
          authenticatedUid: 'uid-1',
        ),
        isTrue,
      );
    });
  });

  test('profile must belong to the authenticated UID', () {
    expect(
      PasswordSignInGuard.profileBelongsToAuthUser(
        firebaseUid: 'uid-a',
        profileUid: 'uid-b',
      ),
      isFalse,
    );
    expect(
      PasswordSignInGuard.profileBelongsToAuthUser(
        firebaseUid: 'uid-a',
        profileUid: 'uid-a',
      ),
      isTrue,
    );
  });
}

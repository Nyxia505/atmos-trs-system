import 'package:atmos_trs_system/utils/login_auth_messages.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('LoginAuthMessages.fromCode', () {
    test('uses distinct copy only when Firebase names the failure', () {
      expect(
        LoginAuthMessages.fromCode('user-not-found').message,
        LoginAuthMessages.unregisteredEmail,
      );
      expect(
        LoginAuthMessages.fromCode('wrong-password').message,
        LoginAuthMessages.wrongPassword,
      );
      expect(
        LoginAuthMessages.fromCode('wrong-password').clearPassword,
        isTrue,
      );
    });

    test('does not guess existence from invalid-credential', () {
      final feedback = LoginAuthMessages.fromCode('invalid-credential');
      expect(feedback.message, LoginAuthMessages.ambiguousCredentials);
      expect(feedback.clearPassword, isTrue);
      expect(feedback.action, LoginAuthAction.signUp);
      expect(feedback.message, isNot(LoginAuthMessages.unregisteredEmail));
      expect(feedback.message, isNot(LoginAuthMessages.wrongPassword));
    });

    test('maps validation and connectivity codes', () {
      expect(
        LoginAuthMessages.fromCode('invalid-email').message,
        LoginAuthMessages.invalidEmail,
      );
      expect(
        LoginAuthMessages.fromCode('network-request-failed').message,
        LoginAuthMessages.networkError,
      );
      expect(
        LoginAuthMessages.fromCode('too-many-requests').message,
        LoginAuthMessages.tooManyAttempts,
      );
    });

    test('normalizes FlutterFire code prefixes', () {
      final e = FirebaseAuthException(
        code: 'firebase_auth/wrong-password',
      );
      expect(
        LoginAuthMessages.fromException(e).message,
        LoginAuthMessages.wrongPassword,
      );
    });
  });
}

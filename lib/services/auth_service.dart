import 'package:firebase_auth/firebase_auth.dart';

/// Auth helpers: Firebase Auth session + legacy email verification (optional).
class AuthService {
  AuthService._();

  static final FirebaseAuth _auth = FirebaseAuth.instance;

  static User? get currentUser => _auth.currentUser;

  /// Signs out (clears Firebase Auth session).
  static Future<void> signOut() => _auth.signOut();

  /// Optional: Firebase built-in email link verification (not used for tourist
  /// gate when [AppUserProfile.isVerified] + EmailJS OTP is the source of truth).
  static Future<void> sendEmailVerification() async {
    final user = _auth.currentUser;
    if (user == null) return;
    if (user.emailVerified) return;
    await _auth.currentUser!.sendEmailVerification();
  }

  static Future<bool> reloadAndCheckEmailVerified() async {
    final user = _auth.currentUser;
    if (user == null) return false;
    await _auth.currentUser!.reload();
    return _auth.currentUser?.emailVerified ?? false;
  }
}

import 'dart:async' show TimeoutException;

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show debugPrint;

/// Ensures Firestore requests carry a fresh Firebase Auth ID token.
///
/// Web demos often keep [SessionStorage] / [AuthConfig] while Auth is null or
/// the token is stale — that surfaces as `permission-denied` on gated collections.
abstract final class FirestoreAuthGate {
  static const Duration tokenTimeout = Duration(seconds: 8);

  /// Returns true when [FirebaseAuth.instance.currentUser] is present and a
  /// token was obtained (or refreshed).
  static Future<bool> ensureFreshIdToken({bool forceRefresh = true}) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      debugPrint('[FirestoreAuthGate] currentUser is null');
      return false;
    }
    try {
      // Prefer cached token first (fast); then optional force refresh.
      await user.getIdToken(false).timeout(tokenTimeout);
      if (forceRefresh) {
        try {
          await user.getIdToken(true).timeout(tokenTimeout);
        } catch (e) {
          debugPrint('[FirestoreAuthGate] force refresh skipped: $e');
        }
      }
      return true;
    } on TimeoutException {
      debugPrint('[FirestoreAuthGate] getIdToken timed out');
      return false;
    } catch (e) {
      debugPrint('[FirestoreAuthGate] getIdToken failed: $e');
      return false;
    }
  }

  static String missingAuthMessage() =>
      'Firebase Auth session is missing. Sign out, then sign in again with '
      'email and password (do not rely on a cached page).';
}

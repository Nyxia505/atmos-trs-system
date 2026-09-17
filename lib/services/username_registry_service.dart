import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart' show debugPrint;

/// Reserves unique usernames in Firestore `usernames/{normalized}`.
class UsernameRegistryService {
  UsernameRegistryService._();

  static const String collectionId = 'usernames';

  static String normalize(String raw) => raw.trim().toLowerCase();

  /// Username: 3–32 chars, letters/numbers/underscore/. / hyphen.
  static String? validateFormat(String? raw) {
    if (raw == null || raw.trim().isEmpty) return 'Username is required.';
    final s = raw.trim();
    if (s.length < 3) return 'Username must be at least 3 characters.';
    if (s.length > 32) return 'Username must be at most 32 characters.';
    if (!RegExp(r'^[a-zA-Z0-9._-]+$').hasMatch(s)) {
      return 'Use letters, numbers, dots, underscores, or hyphens only.';
    }
    return null;
  }

  /// Returns an error message if taken; null if available (or if check cannot run).
  ///
  /// Permission / network failures do **not** block signup — uniqueness is
  /// enforced later by [claim] after Firebase Auth signs the user in.
  static Future<String?> checkAvailable(String username) async {
    final formatError = validateFormat(username);
    if (formatError != null) return formatError;
    final id = normalize(username);
    try {
      final doc =
          await FirebaseFirestore.instance.collection(collectionId).doc(id).get();
      if (doc.exists) return 'This username is already taken.';
      return null;
    } on FirebaseException catch (e) {
      debugPrint(
        '[USERNAME] availability check skipped (${e.code}): ${e.message}',
      );
      // Do not block signup when rules/network prevent pre-auth reads.
      return null;
    } catch (e) {
      debugPrint('[USERNAME] availability check skipped: $e');
      return null;
    }
  }

  /// Claims username for [uid]. Throws if already taken.
  static Future<void> claim({
    required String username,
    required String uid,
    required String email,
  }) async {
    final id = normalize(username);
    final ref = FirebaseFirestore.instance.collection(collectionId).doc(id);
    await FirebaseFirestore.instance.runTransaction((tx) async {
      final snap = await tx.get(ref);
      if (snap.exists) {
        final existingUid = snap.data()?['uid']?.toString() ?? '';
        if (existingUid != uid) {
          throw StateError('USERNAME_TAKEN');
        }
      }
      tx.set(ref, {
        'uid': uid,
        'username': username.trim(),
        'email': email.trim().toLowerCase(),
        'createdAt': FieldValue.serverTimestamp(),
      });
    });
  }

  static Future<void> release(String username) async {
    final id = normalize(username);
    if (id.isEmpty) return;
    try {
      await FirebaseFirestore.instance.collection(collectionId).doc(id).delete();
    } catch (e) {
      debugPrint('[USERNAME] release failed (non-fatal): $e');
    }
  }
}

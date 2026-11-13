import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart' show debugPrint, kIsWeb;

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
      if (doc.exists) {
        final existingUid = doc.data()?['uid']?.toString() ?? '';
        if (existingUid.isNotEmpty) return 'This username is already taken.';
      }
      return null;
    } on FirebaseException catch (e) {
      debugPrint(
        '[USERNAME] availability check skipped (${e.code}): ${e.message}',
      );
      return null;
    } catch (e) {
      debugPrint('[USERNAME] availability check skipped: $e');
      return null;
    }
  }

  /// Claims username for [uid].
  ///
  /// **No `runTransaction`** — Flutter Web's Firestore interop boxes Dart
  /// errors from transactions as "converted Future" and registration dies.
  /// Uniqueness is enforced by: (1) pre-read, (2) rules that only allow
  /// create for your uid / update of your own doc.
  static Future<void> claim({
    required String username,
    required String uid,
    required String email,
  }) async {
    final formatError = validateFormat(username);
    if (formatError != null) {
      throw StateError(formatError);
    }
    final id = normalize(username);
    if (uid.trim().isEmpty) {
      throw StateError('Missing authenticated user for username claim.');
    }

    final ref = FirebaseFirestore.instance.collection(collectionId).doc(id);
    final payload = <String, dynamic>{
      'uid': uid,
      'username': username.trim(),
      'email': email.trim().toLowerCase(),
      // Avoid FieldValue.serverTimestamp in any web transaction path; plain
      // DateTime is fine for registry metadata.
      'createdAt': DateTime.now().toUtc().toIso8601String(),
    };

    try {
      final existing = await ref.get();
      if (existing.exists) {
        final existingUid = (existing.data()?['uid'] ?? '').toString();
        if (existingUid == uid) {
          await ref.set(payload, SetOptions(merge: true));
          debugPrint('[USERNAME] reclaimed "$id" for same uid=$uid');
          return;
        }
        if (existingUid.isNotEmpty) {
          throw StateError('USERNAME_TAKEN');
        }
        // Orphan doc — overwrite.
        await ref.set(payload);
        debugPrint('[USERNAME] claimed orphan "$id" for uid=$uid');
        return;
      }

      await ref.set(payload);
      debugPrint('[USERNAME] claimed "$id" for uid=$uid (web=$kIsWeb)');
    } on FirebaseException catch (e) {
      debugPrint('[USERNAME] claim FirebaseException (${e.code}): ${e.message}');
      // Race: another client created the doc first → update denied by rules.
      if (e.code == 'permission-denied') {
        final again = await ref.get();
        final existingUid = (again.data()?['uid'] ?? '').toString();
        if (existingUid == uid) return;
        if (existingUid.isNotEmpty) {
          throw StateError('USERNAME_TAKEN');
        }
      }
      rethrow;
    } catch (e, st) {
      final unwrapped = unwrapError(e);
      if (unwrapped is StateError) rethrow;
      debugPrint('[USERNAME] claim error: $unwrapped\n$st');
      if (unwrapped is FirebaseException) throw unwrapped;
      // Last resort: if web boxed a permission/taken error, re-check ownership.
      try {
        final again = await ref.get();
        if (again.exists) {
          final existingUid = (again.data()?['uid'] ?? '').toString();
          if (existingUid == uid) return;
          if (existingUid.isNotEmpty) {
            throw StateError('USERNAME_TAKEN');
          }
        }
      } catch (inner) {
        final u = unwrapError(inner);
        if (u is StateError) rethrow;
      }
      throw unwrapped is Exception ? unwrapped : Exception(unwrapped.toString());
    }
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

  /// Flutter Web boxes Dart errors thrown across JS Promise boundaries.
  static Object unwrapError(Object error) {
    Object current = error;
    for (var i = 0; i < 4; i++) {
      try {
        // ignore: avoid_dynamic_calls
        final nested = (current as dynamic).error;
        if (nested is Object && !identical(nested, current)) {
          current = nested;
          continue;
        }
      } catch (_) {}
      break;
    }
    final text = current.toString();
    if (text.contains('USERNAME_TAKEN')) {
      return StateError('USERNAME_TAKEN');
    }
    return current;
  }

  /// User-facing copy for claim/check failures (never raw stack / JS interop).
  static String userFacingClaimError(Object error) {
    final e = unwrapError(error);
    if (e is StateError) {
      final msg = e.message;
      if (msg == 'USERNAME_TAKEN') {
        return 'This username is already taken. Please choose another.';
      }
      if (msg.toLowerCase().contains('username')) return msg;
    }
    if (e is FirebaseException) {
      switch (e.code) {
        case 'already-exists':
          return 'This username is already taken. Please choose another.';
        case 'permission-denied':
          return 'Registration could not be completed. Please try again in a moment.';
        case 'unavailable':
        case 'deadline-exceeded':
        case 'network-request-failed':
          return 'Unable to connect. Please check your internet connection and try again.';
        default:
          debugPrint('[USERNAME] claim FirebaseException ${e.code}: ${e.message}');
          return 'Could not reserve this username. Please try again.';
      }
    }
    final text = e.toString().toLowerCase();
    if (text.contains('username_taken') || text.contains('already')) {
      return 'This username is already taken. Please choose another.';
    }
    if (text.contains('network') || text.contains('socket')) {
      return 'Unable to connect. Please check your internet connection and try again.';
    }
    if (text.contains('permission')) {
      return 'Registration could not be completed. Please try again in a moment.';
    }
    debugPrint('[USERNAME] claim error (hidden from UI): $e');
    return 'Could not reserve this username. Please try again.';
  }
}

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart' show debugPrint;

/// Permission-denied or Firestore web SDK assertion — keep in-memory data, do not surface raw errors.
bool isRecoverableFirestoreError(Object error) {
  final s = error.toString();
  return s.contains('permission-denied') ||
      s.contains('INTERNAL ASSERTION FAILED') ||
      s.contains('Unexpected state') ||
      s.contains('converted Future');
}

void logRecoverableFirestoreLoad(String loader, Object error) {
  debugPrint('$loader: recoverable Firestore error (keeping cache): $error');
}

/// Unwrap Flutter-web JS Future boxing and return a short user-facing message.
String friendlyFirestoreError(Object error) {
  Object current = error;
  for (var i = 0; i < 5; i++) {
    try {
      final dynamic boxed = current;
      final inner = boxed.error ?? boxed.cause ?? boxed.message;
      if (inner != null && !identical(inner, current)) {
        current = inner is Object ? inner : inner.toString();
        continue;
      }
    } catch (_) {}
    break;
  }

  if (current is FirebaseException) {
    final code = current.code;
    final message = (current.message ?? '').trim();
    if (code == 'permission-denied') {
      return message.isNotEmpty
          ? message
          : 'Permission denied. Sign in again with an OPTACA or tourism staff account.';
    }
    if (message.isNotEmpty) return message;
    return code;
  }

  final text = current.toString().trim();
  final lower = text.toLowerCase();
  if (lower.contains('permission-denied') ||
      lower.contains('permission_denied') ||
      lower.contains('missing or insufficient permissions')) {
    return 'Permission denied. Sign in again with an OPTACA or tourism staff account.';
  }
  if (text.contains('converted Future') ||
      text.contains('Dart exception thrown')) {
    return 'Could not save to the database. Check your connection and account permissions, then try again.';
  }
  if (text.startsWith('Exception: ')) return text.substring(11);
  if (text.startsWith('Error: ')) return text.substring(7);
  return text.isEmpty ? 'Unknown error' : text;
}

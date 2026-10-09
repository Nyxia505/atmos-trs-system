import 'package:flutter/foundation.dart' show debugPrint;

/// Permission-denied or Firestore web SDK assertion — keep in-memory data, do not surface raw errors.
bool isRecoverableFirestoreError(Object error) {
  final s = error.toString();
  return s.contains('permission-denied') ||
      s.contains('INTERNAL ASSERTION FAILED') ||
      s.contains('Unexpected state');
}

void logRecoverableFirestoreLoad(String loader, Object error) {
  debugPrint('$loader: recoverable Firestore error (keeping cache): $error');
}

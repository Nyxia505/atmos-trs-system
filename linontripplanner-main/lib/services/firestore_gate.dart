import 'dart:async';

import 'package:flutter/foundation.dart' show kIsWeb;

/// Serializes Firestore work on web to avoid JS SDK watch-stream assertion crashes.
final _FirestoreGate _gate = _FirestoreGate();

/// True while a gated Firestore action is running (allows nested loader calls).
bool _runFirestoreActive = false;

Future<T> runFirestore<T>(Future<T> Function() action) {
  if (!kIsWeb || _runFirestoreActive) {
    return action();
  }
  return _gate.run(action);
}

class _FirestoreGate {
  Future<void> _tail = Future<void>.value();

  Future<T> run<T>(Future<T> Function() action) {
    final completer = Completer<T>();
    _tail = _tail.then((_) async {
      _runFirestoreActive = true;
      try {
        if (!completer.isCompleted) {
          completer.complete(await action());
        }
      } catch (e, st) {
        if (!completer.isCompleted) {
          completer.completeError(e, st);
        }
      } finally {
        _runFirestoreActive = false;
      }
    });
    return completer.future;
  }
}

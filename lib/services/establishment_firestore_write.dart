import 'dart:async';
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart' show debugPrint, kIsWeb;
import 'package:http/http.dart' as http;

import 'package:atmos_trs_system/services/establishment_registration_service.dart';
import 'package:atmos_trs_system/services/firestore_auth_gate.dart';

/// Fast AE profile field writes. On web, uses Firestore REST (SDK WebChannel hangs).
abstract final class EstablishmentFirestoreWrite {
  static CollectionReference<Map<String, dynamic>> get _estCol =>
      FirebaseFirestore.instance.collection(
        EstablishmentRegistrationService.establishmentsCollection,
      );

  static Future<void>? _writeChain;
  static DateTime? _last429At;

  /// Merge-patch fields onto `accommodation_establishments/{uid}`.
  static Future<void> mergeFields(
    String uid,
    Map<String, dynamic> fields, {
    Duration timeout = const Duration(seconds: 12),
  }) async {
    final id = uid.trim();
    if (id.isEmpty) throw StateError('Missing establishment id.');

    final previous = _writeChain;
    final done = Completer<void>();
    _writeChain = done.future;
    try {
      if (previous != null) {
        try {
          await previous.timeout(const Duration(seconds: 15));
        } catch (_) {}
      }
      await FirestoreAuthGate.ensureFreshIdToken(forceRefresh: false);

      // After a 429, wait out free-tier burst limit before the next REST write.
      final last429 = _last429At;
      if (last429 != null) {
        final wait = const Duration(seconds: 45) - DateTime.now().difference(last429);
        if (wait > Duration.zero) {
          // #region agent log
          debugPrint(
            '[DBG-b96d41] cooldown ${wait.inSeconds}s after prior 429',
          );
          // #endregion
          await Future<void>.delayed(wait);
        }
      }

      if (kIsWeb) {
        await _mergeViaRestWithRetry(id, fields).timeout(timeout);
      } else {
        await _estCol
            .doc(id)
            .set(fields, SetOptions(merge: true))
            .timeout(timeout);
      }
      done.complete();
    } catch (e, st) {
      done.completeError(e, st);
      rethrow;
    } finally {
      if (identical(_writeChain, done.future)) {
        _writeChain = null;
      }
    }
  }

  static Future<void> _mergeViaRestWithRetry(
    String uid,
    Map<String, dynamic> fields,
  ) async {
    const backoffs = <Duration>[
      Duration.zero,
      Duration(seconds: 5),
      Duration(seconds: 15),
    ];
    Object? lastError;
    for (var i = 0; i < backoffs.length; i++) {
      final delay = backoffs[i];
      if (delay > Duration.zero) {
        await Future<void>.delayed(delay);
      }
      try {
        await _mergeViaRest(uid, fields);
        return;
      } on StateError catch (e) {
        lastError = e;
        if (!e.toString().contains('(429)')) rethrow;
        _last429At = DateTime.now();
        // #region agent log
        debugPrint('[DBG-b96d41] REST 429 attempt ${i + 1}/${backoffs.length}');
        // #endregion
      }
    }
    // Do NOT fall back to Firestore SDK on web — it hangs and surfaces as TimeoutException.
    throw lastError ?? StateError('Save failed (429). Try again in a minute.');
  }

  static Future<void> _mergeViaRest(
    String uid,
    Map<String, dynamic> fields,
  ) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) throw StateError('Sign in again.');
    final token = await user.getIdToken(false).timeout(
      const Duration(seconds: 5),
    );
    if (token == null || token.isEmpty) {
      throw StateError('Auth token missing. Sign in again.');
    }
    final projectId = Firebase.app().options.projectId;
    if (projectId.isEmpty) {
      throw StateError('Firebase project is not configured.');
    }

    final masks = <String>[];
    final restFields = <String, dynamic>{};
    fields.forEach((key, value) {
      masks.add('updateMask.fieldPaths=${Uri.encodeQueryComponent(key)}');
      restFields[key] = _toRestValue(value);
    });
    if (!restFields.containsKey('updatedAt')) {
      masks.add('updateMask.fieldPaths=updatedAt');
      restFields['updatedAt'] = {
        'timestampValue': DateTime.now().toUtc().toIso8601String(),
      };
    }

    final docPath =
        'projects/$projectId/databases/(default)/documents/'
        '${EstablishmentRegistrationService.establishmentsCollection}/$uid';
    final uri = Uri.parse(
      'https://firestore.googleapis.com/v1/$docPath?${masks.join('&')}',
    );
    final response = await http
        .patch(
          uri,
          headers: {
            'Authorization': 'Bearer $token',
            'Content-Type': 'application/json',
          },
          body: jsonEncode({'fields': restFields}),
        )
        .timeout(const Duration(seconds: 8));
    if (response.statusCode == 429) {
      _last429At = DateTime.now();
      debugPrint('[EstFsWrite] REST 429 ${response.body}');
      throw StateError('Save failed (429).');
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      debugPrint(
        '[EstFsWrite] REST ${response.statusCode} ${response.body}',
      );
      throw StateError('Save failed (${response.statusCode}).');
    }
  }

  static Map<String, dynamic> _toRestValue(dynamic value) {
    if (value == null) return {'nullValue': null};
    if (value is String) return {'stringValue': value};
    if (value is bool) return {'booleanValue': value};
    if (value is int) return {'integerValue': '$value'};
    if (value is double) return {'doubleValue': value};
    if (value is FieldValue) {
      return {
        'timestampValue': DateTime.now().toUtc().toIso8601String(),
      };
    }
    if (value is List) {
      return {
        'arrayValue': {
          'values': [for (final e in value) _toRestValue(e)],
        },
      };
    }
    if (value is Map) {
      return {
        'mapValue': {
          'fields': {
            for (final e in value.entries)
              e.key.toString(): _toRestValue(e.value),
          },
        },
      };
    }
    return {'stringValue': value.toString()};
  }
}

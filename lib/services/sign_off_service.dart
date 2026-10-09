import 'dart:async';
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:crypto/crypto.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

import 'package:atmos_trs_system/models/sign_off.dart';

/// Name + position + fresh signature on every major save.
///
/// Records live in `signoffs/{id}` (append-only, signature PNG embedded as a
/// blob so the record and the data change commit in one batch). Remembered
/// people live in `signoff_signers/{ownerId}/people/{key}`.
abstract final class SignOffService {
  static const collection = 'signoffs';
  static const signersCollection = 'signoff_signers';
  static const maxChanges = 60;
  static const _timeout = Duration(seconds: 20);

  static CollectionReference<Map<String, dynamic>> get _col =>
      FirebaseFirestore.instance.collection(collection);

  static CollectionReference<Map<String, dynamic>> _people(String ownerId) =>
      FirebaseFirestore.instance.collection(signersCollection).doc(ownerId).collection('people');

  static DocumentReference<Map<String, dynamic>> newRef() => _col.doc();

  // ---------------------------------------------------------------- signers

  static Stream<List<SignOffSigner>> watchSigners(String ownerId) {
    if (ownerId.trim().isEmpty) return Stream.value(const []);
    return _people(ownerId).snapshots().map((s) {
      final docs = s.docs.toList()
        ..sort((a, b) {
          final ta = a.data()['lastUsedAt'];
          final tb = b.data()['lastUsedAt'];
          final ma = ta is Timestamp ? ta.millisecondsSinceEpoch : 0;
          final mb = tb is Timestamp ? tb.millisecondsSinceEpoch : 0;
          return mb.compareTo(ma);
        });
      return docs.map(SignOffSigner.fromDoc).toList();
    });
  }

  static Future<void> rememberSigner(String ownerId, String name, String position) async {
    if (ownerId.trim().isEmpty || name.trim().isEmpty) return;
    await _people(ownerId).doc(SignOffSigner.keyFor(name, position)).set({
      'name': name.trim(),
      'position': position.trim(),
      'lastUsedAt': FieldValue.serverTimestamp(),
      'useCount': FieldValue.increment(1),
    }, SetOptions(merge: true)).timeout(_timeout);
  }

  /// Removes a person from quick-pick only; past sign-offs are untouched.
  static Future<void> forgetSigner(String ownerId, String signerId) =>
      _people(ownerId).doc(signerId).delete().timeout(_timeout);

  // ---------------------------------------------------------------- records

  /// Sign-off document body. Add to the same batch as the data it certifies.
  static Map<String, dynamic> recordMap({
    required String subjectType,
    required String subjectId,
    required String ownerId,
    required SignOffRequest request,
    String ownerName = '',
    String municipalityId = '',
    String periodKey = '',
    String contentHash = '',
    Map<String, dynamic> snapshot = const {},
    List<SignOffChange> changes = const [],
  }) {
    final c = request.capture;
    final user = FirebaseAuth.instance.currentUser;
    return {
      'schemaVersion': 1,
      'subjectType': subjectType,
      'subjectId': subjectId,
      'ownerId': ownerId,
      'ownerName': ownerName,
      'municipalityId': municipalityId,
      'periodKey': periodKey,
      'action': request.action.code,
      'actionLabel': request.action.label,
      'summary': request.summary,
      'details': request.details,
      'reason': c.reason.trim(),
      'signerName': c.name.trim(),
      'signerPosition': c.position.trim(),
      'signaturePng': Blob(c.signaturePng),
      'signatureSha256': sha256Hex(c.signaturePng),
      'contentHash': contentHash,
      'snapshot': snapshot,
      'changes': [for (final ch in changes.take(maxChanges)) ch.toMap()],
      'changesTruncated': changes.length > maxChanges ? changes.length - maxChanges : 0,
      'accountUid': user?.uid ?? '',
      'accountEmail': user?.email ?? '',
      'platform': kIsWeb ? 'web' : defaultTargetPlatform.name,
      'createdAt': FieldValue.serverTimestamp(),
    };
  }

  /// Sign-off for a change that is written separately (e.g. profile fields).
  static Future<String> writeStandalone({
    required String subjectType,
    required String subjectId,
    required String ownerId,
    required SignOffRequest request,
    String ownerName = '',
    String municipalityId = '',
    String contentHash = '',
    Map<String, dynamic> snapshot = const {},
    List<SignOffChange> changes = const [],
  }) async {
    final ref = newRef();
    await ref
        .set(recordMap(
          subjectType: subjectType,
          subjectId: subjectId,
          ownerId: ownerId,
          request: request,
          ownerName: ownerName,
          municipalityId: municipalityId,
          contentHash: contentHash,
          snapshot: snapshot,
          changes: changes,
        ))
        .timeout(_timeout);
    return ref.id;
  }

  /// History for one subject, newest first.
  static Stream<List<SignOffRecord>> watchForSubject({
    required String ownerId,
    required String subjectType,
    required String subjectId,
  }) =>
      _col
          .where('ownerId', isEqualTo: ownerId)
          .where('subjectId', isEqualTo: subjectId)
          .snapshots()
          .map((s) => _newestFirst(
                s.docs.map(SignOffRecord.fromDoc).where((r) => r.subjectType == subjectType),
              ));

  /// Latest sign-off per subject id (DAE / CUS PDFs). Pass [ownerId] when the
  /// owner itself reads (rules only allow owner queries filtered by owner).
  static Future<Map<String, SignOffRecord>> latestForSubjects({
    required String subjectType,
    required Iterable<String> subjectIds,
    String? ownerId,
  }) async {
    final ids = subjectIds.where((e) => e.isNotEmpty).toSet().toList();
    final out = <String, SignOffRecord>{};
    for (var i = 0; i < ids.length; i += 30) {
      final chunk = ids.sublist(i, i + 30 > ids.length ? ids.length : i + 30);
      Query<Map<String, dynamic>> q = _col.where('subjectId', whereIn: chunk);
      if ((ownerId ?? '').isNotEmpty) q = q.where('ownerId', isEqualTo: ownerId);
      final snap = await q.get().timeout(_timeout);
      for (final r in snap.docs.map(SignOffRecord.fromDoc)) {
        if (r.subjectType != subjectType) continue;
        final cur = out[r.subjectId];
        if (cur == null || _millis(r) > _millis(cur)) out[r.subjectId] = r;
      }
    }
    return out;
  }

  static List<SignOffRecord> _newestFirst(Iterable<SignOffRecord> list) =>
      list.toList()..sort((a, b) => _millis(b).compareTo(_millis(a)));

  // Pending server timestamps sort first (just written).
  static int _millis(SignOffRecord r) => r.createdAt?.millisecondsSinceEpoch ?? 9007199254740991;

  // ---------------------------------------------------------------- hashing

  static String sha256Hex(Uint8List bytes) => sha256.convert(bytes).toString();

  /// Platform-stable hash of JSON-like data (sorted keys, integral doubles
  /// written as ints so web and mobile agree).
  static String contentHash(Object? data) =>
      sha256.convert(utf8.encode(_canonical(data))).toString();

  static String _canonical(Object? v) {
    if (v == null) return 'null';
    if (v is bool) return v ? 'true' : 'false';
    if (v is num) {
      if (!v.isFinite) return '0';
      if (v == v.roundToDouble()) return v.round().toString();
      return v.toStringAsFixed(4);
    }
    if (v is String) return jsonEncode(v);
    if (v is DateTime) return jsonEncode(v.toIso8601String());
    if (v is Timestamp) return jsonEncode(v.toDate().toUtc().toIso8601String());
    if (v is Map) {
      final keys = v.keys.map((k) => k.toString()).toList()..sort();
      return '{${keys.map((k) => '${jsonEncode(k)}:${_canonical(v[k])}').join(',')}}';
    }
    if (v is Iterable) return '[${v.map(_canonical).join(',')}]';
    return jsonEncode(v.toString());
  }
}

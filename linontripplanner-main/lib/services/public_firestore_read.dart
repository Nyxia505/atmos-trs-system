import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show debugPrint, kDebugMode, kIsWeb;
import 'package:http/http.dart' as http;

import '../firebase_options.dart';

/// One document from a public catalog read (SDK or REST fallback).
class PublicFirestoreDoc {
  const PublicFirestoreDoc({required this.id, required Map<String, dynamic> data})
      : _data = data;

  final String id;
  final Map<String, dynamic> _data;

  Map<String, dynamic> data() => _data;
}

/// Result of [fetchPublicFirestoreCollection] / [fetchPublicFirestoreQuery].
class PublicFirestoreDocs {
  const PublicFirestoreDocs(this.docs);

  final List<PublicFirestoreDoc> docs;

  int get size => docs.length;
}

/// Reads a public catalog collection (`allow read: if true` in [firestore.rules]).
///
/// On web, prefers the Firestore REST API first — the JS SDK often reports
/// `permission-denied` for public catalogs even when rules allow open read.
/// Elsewhere: SDK with retry, then REST fallback on deny.
Future<PublicFirestoreDocs> fetchPublicFirestoreCollection(
  String collectionPath, {
  int maxAttempts = 2,
}) async {
  if (kIsWeb) {
    for (var restAttempt = 0; restAttempt < 3; restAttempt++) {
      try {
        if (restAttempt > 0) {
          await Future<void>.delayed(Duration(milliseconds: 400 * restAttempt));
        }
        return await _fetchPublicCollectionViaRest(collectionPath);
      } catch (e) {
        final denied = e.toString().contains('permission-denied') ||
            e.toString().contains('403');
        if (denied && restAttempt < 2) {
          if (kDebugMode) {
            debugPrint(
              'fetchPublicFirestoreCollection: REST deny for "$collectionPath" '
              '— retry ${restAttempt + 1}/3',
            );
          }
          continue;
        }
        if (kDebugMode) {
          debugPrint(
            'fetchPublicFirestoreCollection: REST failed for "$collectionPath" '
            '($e) — trying SDK',
          );
        }
        break;
      }
    }
  }

  try {
    return await fetchPublicFirestoreQuery(
      FirebaseFirestore.instance.collection(collectionPath),
      maxAttempts: maxAttempts,
    );
  } on FirebaseException catch (e) {
    if (e.code != 'permission-denied') rethrow;
    if (kDebugMode) {
      debugPrint(
        'fetchPublicFirestoreCollection: SDK denied for "$collectionPath" — '
        'trying REST fallback',
      );
    }
    return _fetchPublicCollectionViaRest(collectionPath);
  }
}

/// Runs a public Firestore [query] with the same retry behaviour as
/// [fetchPublicFirestoreCollection].
Future<PublicFirestoreDocs> fetchPublicFirestoreQuery(
  Query<Map<String, dynamic>> query, {
  int maxAttempts = 2,
}) async {
  FirebaseException? lastDenied;
  for (var attempt = 0; attempt < maxAttempts; attempt++) {
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      try {
        await user.getIdToken(attempt > 0);
      } catch (_) {}
    }
    if (attempt > 0) {
      await Future<void>.delayed(Duration(milliseconds: 300 * attempt));
    }

    // Prefer cache+server so repeat visits paint spots without a full round-trip.
    final sources = attempt == 0
        ? const [Source.serverAndCache]
        : const [Source.server, Source.cache, Source.serverAndCache];

    for (final source in sources) {
      try {
        final snap = await query.get(GetOptions(source: source));
        // After a server permission-denied, an empty cache must not look like a
        // successful "0 documents" load (that wipes in-memory catalogs).
        if (lastDenied != null &&
            snap.docs.isEmpty &&
            (source == Source.cache || source == Source.serverAndCache)) {
          continue;
        }
        return PublicFirestoreDocs([
          for (final d in snap.docs)
            PublicFirestoreDoc(id: d.id, data: d.data()),
        ]);
      } on FirebaseException catch (e) {
        if (e.code == 'unavailable' && source == Source.cache) {
          continue;
        }
        if (e.code != 'permission-denied') rethrow;
        lastDenied = e;
        if (kDebugMode) {
          debugPrint(
            'fetchPublicFirestoreQuery: permission-denied '
            '(attempt ${attempt + 1}/$maxAttempts, source=$source)',
          );
        }
      }
    }
  }
  throw lastDenied ??
      FirebaseException(
        plugin: 'cloud_firestore',
        code: 'permission-denied',
        message: 'Missing or insufficient permissions.',
      );
}

Future<PublicFirestoreDocs> _fetchPublicCollectionViaRest(
  String collectionPath,
) async {
  final opts = DefaultFirebaseOptions.currentPlatform;
  final projectId = opts.projectId;
  final apiKey = opts.apiKey;
  final uri = Uri.parse(
    'https://firestore.googleapis.com/v1/projects/$projectId/'
    'databases/(default)/documents/$collectionPath',
  ).replace(queryParameters: {
    'key': apiKey,
    'pageSize': '300',
  });

  final response = await http.get(uri);
  if (response.statusCode != 200) {
    throw FirebaseException(
      plugin: 'cloud_firestore',
      code: 'permission-denied',
      message:
          'REST fallback failed for $collectionPath '
          '(${response.statusCode}): ${response.body}',
    );
  }

  final decoded = jsonDecode(response.body);
  final docsJson = (decoded is Map && decoded['documents'] is List)
      ? decoded['documents'] as List
      : const <dynamic>[];

  final docs = <PublicFirestoreDoc>[];
  for (final raw in docsJson) {
    if (raw is! Map) continue;
    final name = raw['name']?.toString() ?? '';
    final id = name.split('/').isNotEmpty ? name.split('/').last : '';
    if (id.isEmpty) continue;
    final fields = raw['fields'];
    final data = fields is Map
        ? _decodeFirestoreRestFields(Map<String, dynamic>.from(fields))
        : <String, dynamic>{};
    docs.add(PublicFirestoreDoc(id: id, data: data));
  }

  if (kDebugMode) {
    debugPrint(
      'fetchPublicFirestoreCollection REST: $collectionPath → ${docs.length} docs',
    );
  }
  return PublicFirestoreDocs(docs);
}

Map<String, dynamic> _decodeFirestoreRestFields(Map<String, dynamic> fields) {
  final out = <String, dynamic>{};
  for (final entry in fields.entries) {
    out[entry.key] = _decodeFirestoreRestValue(entry.value);
  }
  return out;
}

dynamic _decodeFirestoreRestValue(dynamic value) {
  if (value is! Map) return value;
  final m = Map<String, dynamic>.from(value);
  if (m.containsKey('stringValue')) return m['stringValue'];
  if (m.containsKey('integerValue')) {
    return int.tryParse('${m['integerValue']}') ?? m['integerValue'];
  }
  if (m.containsKey('doubleValue')) return m['doubleValue'];
  if (m.containsKey('booleanValue')) return m['booleanValue'] == true;
  if (m.containsKey('timestampValue')) {
    final raw = m['timestampValue']?.toString();
    if (raw == null || raw.isEmpty) return null;
    final dt = DateTime.tryParse(raw);
    return dt != null ? Timestamp.fromDate(dt.toUtc()) : raw;
  }
  if (m.containsKey('nullValue')) return null;
  if (m.containsKey('mapValue')) {
    final fields = m['mapValue'] is Map ? m['mapValue']['fields'] : null;
    if (fields is Map) {
      return _decodeFirestoreRestFields(Map<String, dynamic>.from(fields));
    }
    return <String, dynamic>{};
  }
  if (m.containsKey('arrayValue')) {
    final values = m['arrayValue'] is Map ? m['arrayValue']['values'] : null;
    if (values is List) {
      return [for (final v in values) _decodeFirestoreRestValue(v)];
    }
    return <dynamic>[];
  }
  return m;
}

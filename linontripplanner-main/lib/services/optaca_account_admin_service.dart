import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';

/// OPTACA account actions. Prefer `optacaManageAccount` (Admin SDK) when
/// deployed. Create falls back to a secondary Auth app so the OPTACA session
/// stays signed in when Cloud Functions cannot be deployed (no Blaze).
class OptacaAccountException implements Exception {
  OptacaAccountException(this.message);
  final String message;

  @override
  String toString() => message;
}

const String _kOptacaAdminSecondaryApp = 'optacaAccountAdmin';

class OptacaAccountListResult {
  const OptacaAccountListResult({
    required this.accounts,
    required this.summary,
    required this.page,
    required this.pageSize,
    required this.hasMore,
    this.fromFallback = false,
  });

  final List<Map<String, dynamic>> accounts;
  final Map<String, dynamic> summary;
  final int page;
  final int pageSize;
  final bool hasMore;
  final bool fromFallback;
}

class OptacaAccountAdminService {
  OptacaAccountAdminService._();

  static OptacaAccountException _mapFunctionsError(
    FirebaseFunctionsException e, {
    String undeployedHint =
        'Deploy adminResetAccountPassword / optacaManageAccount (asia-southeast1).',
  }) {
    final message = (e.message ?? '').trim();
    final details = (e.details?.toString() ?? '').trim();
    if (e.code == 'not-found' || e.code == 'unavailable') {
      return OptacaAccountException(
        'Account tools are not deployed yet. $undeployedHint',
      );
    }
    if (e.code == 'permission-denied') {
      return OptacaAccountException(
        message.isEmpty
            ? 'Only OPTACA administrators can manage accounts.'
            : message,
      );
    }
    if (e.code == 'resource-exhausted') {
      return OptacaAccountException(
        message.isEmpty
            ? 'Too many password resets. Wait a few minutes and try again.'
            : message,
      );
    }
    if (e.code == 'already-exists') {
      return OptacaAccountException(
        message.isEmpty ? 'That email is already registered.' : message,
      );
    }
    if (e.code == 'internal' &&
        (message.isEmpty || message.toLowerCase() == 'internal')) {
      return OptacaAccountException(
        'Could not complete the account action on the server. '
        '$undeployedHint'
        '${details.isEmpty ? '' : ' Details: $details'}',
      );
    }
    return OptacaAccountException(
      message.isEmpty ? 'Account action failed (${e.code}).' : message,
    );
  }

  static Future<Map<String, dynamic>> call(Map<String, dynamic> data) async {
    try {
      final functions = FirebaseFunctions.instanceFor(region: 'asia-southeast1');
      final callable = functions.httpsCallable(
        'optacaManageAccount',
        options: HttpsCallableOptions(timeout: const Duration(seconds: 90)),
      );
      final result = await callable.call(data);
      final payload = result.data;
      if (payload is Map) {
        return Map<String, dynamic>.from(payload);
      }
      return <String, dynamic>{'ok': true};
    } on FirebaseFunctionsException catch (e) {
      throw _mapFunctionsError(e);
    } catch (e) {
      if (e is OptacaAccountException) rethrow;
      throw OptacaAccountException('Account action failed. $e');
    }
  }

  static void assertPasswordStrength(String password) {
    if (password.length < 8 ||
        !RegExp(r'[A-Z]').hasMatch(password) ||
        !RegExp(r'[a-z]').hasMatch(password) ||
        !RegExp(r'[0-9]').hasMatch(password)) {
      throw OptacaAccountException(
        'Password must be 8+ characters with upper, lower, and a number.',
      );
    }
  }

  /// Direct Admin SDK password reset via `adminResetAccountPassword`.
  /// Falls back to `optacaManageAccount` `setPassword` when the dedicated
  /// function is not deployed yet. Never stores or returns the password.
  static Future<void> resetAccountPassword({
    required String uid,
    required String newPassword,
  }) async {
    final targetUid = uid.trim();
    if (targetUid.isEmpty) {
      throw OptacaAccountException('Account UID is missing.');
    }
    assertPasswordStrength(newPassword);

    final functions = FirebaseFunctions.instanceFor(region: 'asia-southeast1');
    try {
      final callable = functions.httpsCallable(
        'adminResetAccountPassword',
        options: HttpsCallableOptions(timeout: const Duration(seconds: 60)),
      );
      await callable.call(<String, dynamic>{
        'uid': targetUid,
        'password': newPassword,
      });
      return;
    } on FirebaseFunctionsException catch (e) {
      final missing = e.code == 'not-found' ||
          e.code == 'unavailable' ||
          (e.code == 'internal' &&
              ((e.message ?? '').trim().isEmpty ||
                  (e.message ?? '').trim().toLowerCase() == 'internal'));
      if (!missing) {
        throw _mapFunctionsError(
          e,
          undeployedHint:
              'Deploy adminResetAccountPassword (asia-southeast1) on Blaze.',
        );
      }
    }

    await call({
      'action': 'setPassword',
      'uid': targetUid,
      'password': newPassword,
    });
  }

  static bool _isLguRole(String role) {
    final r = role.trim().toLowerCase();
    return r == 'tourism' ||
        r == 'tourism_office' ||
        r == 'lgu' ||
        r == 'lgu_tourism' ||
        r == 'municipal_tourism';
  }

  static bool _isTouristRole(String role) {
    final r = role.trim().toLowerCase();
    return r == 'tourist' || r == 'user';
  }

  static bool _isEstablishmentRole(String role) {
    final r = role.trim().toLowerCase();
    return r == 'tourism_establishment' ||
        r == 'tourismestablishment' ||
        r == 'establishment';
  }

  static bool _matchesType(String role, String accountType) {
    switch (accountType) {
      case 'lgu':
        return _isLguRole(role);
      case 'tourist':
        return _isTouristRole(role);
      case 'establishment':
        return _isEstablishmentRole(role);
      default:
        return false;
    }
  }

  static String _statusOf(Map<String, dynamic> data) {
    final status = (data['status'] ?? 'active').toString().toLowerCase();
    if (status == 'inactive' ||
        status == 'disabled' ||
        status == 'deactivated') {
      return 'deactivated';
    }
    return 'active';
  }

  static int _createdAtMs(dynamic value) {
    if (value is Timestamp) return value.millisecondsSinceEpoch;
    if (value is num) return value.toInt();
    return 0;
  }

  /// Direct Firestore read used when the callable list fails or is not deployed.
  static Future<OptacaAccountListResult> listAccountsFromFirestore({
    required String accountType,
    String search = '',
    String status = '',
    String municipalityId = '',
    int page = 0,
    int pageSize = 25,
  }) async {
    final snap = await FirebaseFirestore.instance.collection('users').get();
    final q = search.trim().toLowerCase();
    final statusFilter = status.trim().toLowerCase();
    final muni = municipalityId.trim().toLowerCase();

    var rows = <Map<String, dynamic>>[];
    for (final doc in snap.docs) {
      final data = doc.data();
      final role = (data['role'] ?? '').toString();
      if (!_matchesType(role, accountType)) continue;

      final row = <String, dynamic>{
        ...data,
        'uid': doc.id,
        'firebaseUid': data['firebaseUid'] ?? doc.id,
        'fullName': (data['fullName'] ?? data['displayName'] ?? data['name'] ?? '')
            .toString(),
        'email': (data['email'] ?? '').toString().toLowerCase(),
        'role': role,
        'municipality': (data['municipality'] ?? '').toString(),
        'municipalityId': (data['municipalityId'] ?? '').toString().toLowerCase(),
        'status': _statusOf(data),
        'createdAtMs': _createdAtMs(data['createdAt']),
        'reviewFlags': <String>[],
      };

      if (muni.isNotEmpty) {
        final id = row['municipalityId'].toString();
        final name = row['municipality'].toString().toLowerCase();
        if (id != muni && !name.contains(muni)) continue;
      }
      if (q.isNotEmpty) {
        final hay = [
          row['fullName'],
          row['email'],
          row['municipality'],
          row['municipalityId'],
          row['uid'],
        ].join(' ').toLowerCase();
        if (!hay.contains(q)) continue;
      }
      if (statusFilter == 'active' || statusFilter == 'deactivated') {
        if (row['status'] != statusFilter) continue;
      }
      rows.add(row);
    }

    rows.sort(
      (a, b) => ((b['createdAtMs'] as num?)?.toInt() ?? 0)
          .compareTo((a['createdAtMs'] as num?)?.toInt() ?? 0),
    );

    final covered = <String>{};
    for (final row in rows) {
      final key = (row['municipalityId']?.toString().isNotEmpty == true)
          ? row['municipalityId'].toString()
          : row['municipality'].toString();
      if (key.isNotEmpty) covered.add(key);
    }

    final summary = <String, dynamic>{
      'total': rows.length,
      'active': rows.where((r) => r['status'] == 'active').length,
      'deactivated': rows.where((r) => r['status'] == 'deactivated').length,
      'municipalitiesCovered': covered.length,
      'needsReview': 0,
    };

    final start = page * pageSize;
    final pageRows = rows.skip(start).take(pageSize).toList();
    return OptacaAccountListResult(
      accounts: pageRows,
      summary: summary,
      page: page,
      pageSize: pageSize,
      hasMore: start + pageSize < rows.length,
      fromFallback: true,
    );
  }

  static Future<OptacaAccountListResult> listAccounts({
    required String accountType,
    String search = '',
    String status = '',
    String municipalityId = '',
    int page = 0,
    int pageSize = 25,
  }) async {
    try {
      final raw = await call({
        'action': 'list',
        'accountType': accountType,
        'search': search,
        'status': status,
        'municipalityId': municipalityId,
        'page': page,
        'pageSize': pageSize,
      });
      final accounts = <Map<String, dynamic>>[];
      final list = raw['accounts'];
      if (list is List) {
        for (final item in list) {
          if (item is Map) {
            accounts.add(Map<String, dynamic>.from(item));
          }
        }
      }
      final summary = raw['summary'] is Map
          ? Map<String, dynamic>.from(raw['summary'] as Map)
          : <String, dynamic>{};
      return OptacaAccountListResult(
        accounts: accounts,
        summary: summary,
        page: (raw['page'] as num?)?.toInt() ?? page,
        pageSize: (raw['pageSize'] as num?)?.toInt() ?? pageSize,
        hasMore: raw['hasMore'] == true,
      );
    } on OptacaAccountException {
      // Show existing Firestore accounts even when the callable fails.
      return listAccountsFromFirestore(
        accountType: accountType,
        search: search,
        status: status,
        municipalityId: municipalityId,
        page: page,
        pageSize: pageSize,
      );
    }
  }

  static Future<List<Map<String, dynamic>>> reconcileLguAccounts() async {
    final raw = await call({'action': 'reconcile'});
    final issues = <Map<String, dynamic>>[];
    final list = raw['issues'];
    if (list is List) {
      for (final item in list) {
        if (item is Map) {
          issues.add(Map<String, dynamic>.from(item));
        }
      }
    }
    return issues;
  }

  static bool _looksLikeMissingCallable(OptacaAccountException e) {
    final m = e.message.toLowerCase();
    return m.contains('not deployed') ||
        m.contains('not-found') ||
        m.contains('unavailable') ||
        m.contains('could not complete the account action') ||
        m == 'internal' ||
        m.contains('account action failed (internal)');
  }

  static String municipalityDisplayName(String municipalityId) {
    switch (municipalityId.trim().toLowerCase()) {
      case 'oroquieta':
        return 'Oroquieta City';
      case 'ozamiz':
      case 'ozamis':
        return 'Ozamis City';
      case 'tangub':
        return 'Tangub City';
      case 'aloran':
        return 'Aloran';
      case 'baliangao':
        return 'Baliangao';
      case 'bonifacio':
        return 'Bonifacio';
      case 'calamba':
        return 'Calamba';
      case 'clarin':
        return 'Clarin';
      case 'concepcion':
        return 'Concepcion';
      case 'dvc':
        return 'Don Victoriano Chiongbian';
      case 'jimenez':
        return 'Jimenez';
      case 'lopezjaena':
        return 'Lopez Jaena';
      case 'panaon':
        return 'Panaon';
      case 'plaridel':
        return 'Plaridel';
      case 'sapangdalaga':
        return 'Sapang Dalaga';
      case 'sinacaban':
        return 'Sinacaban';
      case 'tudela':
        return 'Tudela';
      default:
        return municipalityId.trim();
    }
  }

  static void _assertPasswordStrength(String password) {
    if (password.length < 8 ||
        !RegExp(r'[A-Z]').hasMatch(password) ||
        !RegExp(r'[a-z]').hasMatch(password) ||
        !RegExp(r'[0-9]').hasMatch(password)) {
      throw OptacaAccountException(
        'Password must be 8+ characters with upper, lower, and a number.',
      );
    }
  }

  static Future<FirebaseApp> _secondaryApp() async {
    try {
      return Firebase.app(_kOptacaAdminSecondaryApp);
    } catch (_) {
      return Firebase.initializeApp(
        name: _kOptacaAdminSecondaryApp,
        options: Firebase.app().options,
      );
    }
  }

  /// Creates an LGU (or establishment) account. Uses the Cloud Function when
  /// available; otherwise creates Auth + Firestore via a secondary app so the
  /// signed-in OPTACA admin is not replaced.
  static Future<Map<String, dynamic>> createStakeholderAccount({
    required String fullName,
    required String email,
    required String password,
    required String municipalityId,
    required String role,
    String category = '',
  }) async {
    final payload = <String, dynamic>{
      'action': 'create',
      'fullName': fullName.trim(),
      'email': email.trim().toLowerCase(),
      'password': password,
      'municipalityId': municipalityId.trim().toLowerCase(),
      'role': role.trim().toLowerCase(),
      if (category.trim().isNotEmpty) 'category': category.trim(),
    };

    try {
      return await call(payload);
    } on OptacaAccountException catch (e) {
      if (!_looksLikeMissingCallable(e)) rethrow;
    }

    return _createStakeholderAccountClientSide(
      fullName: fullName.trim(),
      email: email.trim().toLowerCase(),
      password: password,
      municipalityId: municipalityId.trim().toLowerCase(),
      role: role.trim().toLowerCase(),
      category: category.trim(),
    );
  }

  static Future<Map<String, dynamic>> _createStakeholderAccountClientSide({
    required String fullName,
    required String email,
    required String password,
    required String municipalityId,
    required String role,
    required String category,
  }) async {
    if (!email.contains('@')) {
      throw OptacaAccountException('A valid email is required.');
    }
    if (fullName.isEmpty) {
      throw OptacaAccountException('Name is required.');
    }
    _assertPasswordStrength(password);

    final normalizedRole =
        role == 'tourism_office' ? 'tourism' : role;
    if (normalizedRole != 'tourism' &&
        normalizedRole != 'tourism_establishment') {
      throw OptacaAccountException(
        'Role must be an LGU office or a tourism establishment.',
      );
    }
    final municipality = municipalityDisplayName(municipalityId);
    final knownIds = {
      'oroquieta',
      'ozamiz',
      'ozamis',
      'tangub',
      'aloran',
      'baliangao',
      'bonifacio',
      'calamba',
      'clarin',
      'concepcion',
      'dvc',
      'jimenez',
      'lopezjaena',
      'panaon',
      'plaridel',
      'sapangdalaga',
      'sinacaban',
      'tudela',
    };
    if (!knownIds.contains(municipalityId) || municipality.isEmpty) {
      throw OptacaAccountException(
        'Choose a municipality in Misamis Occidental.',
      );
    }
    if (normalizedRole == 'tourism_establishment' && category.isEmpty) {
      throw OptacaAccountException('Establishment category is required.');
    }

    final existing = await FirebaseFirestore.instance
        .collection('users')
        .where('email', isEqualTo: email)
        .limit(1)
        .get();
    if (existing.docs.isNotEmpty) {
      throw OptacaAccountException('That email is already registered.');
    }

    final callerUid = FirebaseAuth.instance.currentUser?.uid ?? '';
    final app = await _secondaryApp();
    final auth = FirebaseAuth.instanceFor(app: app);
    final db = FirebaseFirestore.instanceFor(app: app);

    UserCredential? cred;
    try {
      cred = await auth.createUserWithEmailAndPassword(
        email: email,
        password: password,
      );
      final user = cred.user;
      if (user == null) {
        throw OptacaAccountException('Could not create the Auth account.');
      }
      try {
        await user.updateDisplayName(fullName);
      } catch (_) {}

      await db.collection('users').doc(user.uid).set({
        'firebaseUid': user.uid,
        'email': email,
        'fullName': fullName,
        'role': normalizedRole,
        'municipality': municipality,
        'municipalityId': municipalityId == 'ozamis' ? 'ozamiz' : municipalityId,
        'category':
            normalizedRole == 'tourism_establishment' ? category : '',
        'status': 'active',
        'isVerified': true,
        'mustChangePassword': true,
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
        'createdByUid': callerUid,
        'createdBy': callerUid,
        'createdVia': 'optacaClientSecondaryAuth',
      });

      if (normalizedRole == 'tourism') {
        final officeId =
            municipalityId == 'ozamis' ? 'ozamiz' : municipalityId;
        try {
          await db.collection('lgu_offices').doc(officeId).set({
            'municipalityId': officeId,
            'municipality': municipalityDisplayName(officeId),
            'holderUid': user.uid,
          });
        } catch (_) {
          // Municipality may already have an office claim; account still works.
        }
      }

      if (normalizedRole == 'tourism_establishment') {
        try {
          await db.collection('accommodation_establishments').doc(user.uid).set({
            'id': user.uid,
            'businessName': fullName,
            'name': fullName,
            'category': category,
            'type': category,
            'ownerName': fullName,
            'email': email,
            'municipality': municipalityDisplayName(municipalityId),
            'municipalityId':
                municipalityId == 'ozamis' ? 'ozamiz' : municipalityId,
            'ownerUid': user.uid,
            'authUid': user.uid,
            'status': 'active',
            'createdAt': FieldValue.serverTimestamp(),
            'updatedAt': FieldValue.serverTimestamp(),
            'createdBy': 'optaca',
          });
        } catch (_) {}
      }

      return {'ok': true, 'uid': user.uid, 'via': 'client'};
    } on FirebaseAuthException catch (e) {
      final code = e.code.toLowerCase();
      if (code == 'email-already-in-use') {
        throw OptacaAccountException('That email is already registered.');
      }
      if (code == 'weak-password' || code == 'invalid-password') {
        throw OptacaAccountException(
          'Password must be 8+ characters with upper, lower, and a number.',
        );
      }
      if (code == 'invalid-email') {
        throw OptacaAccountException('A valid email is required.');
      }
      throw OptacaAccountException(
        e.message?.trim().isNotEmpty == true
            ? e.message!.trim()
            : 'Could not create the Auth account ($code).',
      );
    } catch (e) {
      if (e is OptacaAccountException) rethrow;
      final uid = cred?.user?.uid;
      if (uid != null) {
        try {
          await auth.currentUser?.delete();
        } catch (_) {}
      }
      throw OptacaAccountException('Could not save the LGU profile. $e');
    } finally {
      try {
        await auth.signOut();
      } catch (_) {}
    }
  }

  static Future<List<Map<String, dynamic>>> listActivity({
    String actionFilter = '',
    String actorUid = '',
    int pageSize = 50,
  }) async {
    try {
      final raw = await call({
        'action': 'listActivity',
        'actionFilter': actionFilter,
        'actorUid': actorUid,
        'pageSize': pageSize,
      });
      final logs = <Map<String, dynamic>>[];
      final list = raw['logs'];
      if (list is List) {
        for (final item in list) {
          if (item is Map) {
            logs.add(Map<String, dynamic>.from(item));
          }
        }
      }
      return logs;
    } on OptacaAccountException {
      return listActivityFromFirestore(
        actionFilter: actionFilter,
        actorUid: actorUid,
        pageSize: pageSize,
      );
    }
  }

  /// Client fallback when `optacaManageAccount` is not deployed.
  static Future<List<Map<String, dynamic>>> listActivityFromFirestore({
    String actionFilter = '',
    String actorUid = '',
    int pageSize = 50,
  }) async {
    Future<QuerySnapshot<Map<String, dynamic>>> run(bool withOrder) {
      Query<Map<String, dynamic>> query =
          FirebaseFirestore.instance.collection('account_activity_logs');
      if (actorUid.trim().isNotEmpty) {
        query = query.where('actorUid', isEqualTo: actorUid.trim());
      }
      if (withOrder) {
        query = query.orderBy('timestamp', descending: true);
      }
      return query.limit(pageSize).get();
    }

    QuerySnapshot<Map<String, dynamic>> snap;
    try {
      snap = await run(true);
    } on FirebaseException catch (e) {
      // Missing composite index or empty field — retry without orderBy.
      if (e.code == 'failed-precondition' || e.code == 'invalid-argument') {
        try {
          snap = await run(false);
        } on FirebaseException catch (inner) {
          if (inner.code == 'permission-denied') {
            return const [];
          }
          throw OptacaAccountException(
            'Could not load activity logs (${inner.code}).',
          );
        }
      } else if (e.code == 'permission-denied') {
        // Rules not deployed yet, or caller is not OPTACA — show empty quietly.
        return const [];
      } else {
        throw OptacaAccountException(
          'Could not load activity logs (${e.code}).',
        );
      }
    }

    final logs = <Map<String, dynamic>>[];
    for (final doc in snap.docs) {
      final d = doc.data();
      final ts = d['timestamp'];
      final action = (d['action'] ?? '').toString();
      if (actionFilter.isNotEmpty &&
          !action.toLowerCase().contains(actionFilter.toLowerCase())) {
        continue;
      }
      logs.add({
        'id': doc.id,
        ...d,
        'timestampMs': ts is Timestamp ? ts.millisecondsSinceEpoch : 0,
      });
    }
    logs.sort(
      (a, b) => ((b['timestampMs'] as num?)?.toInt() ?? 0)
          .compareTo((a['timestampMs'] as num?)?.toInt() ?? 0),
    );
    return logs;
  }
}

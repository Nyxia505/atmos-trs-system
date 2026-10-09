import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show debugPrint;

import 'admin_account.dart';
import 'services/firestore_errors.dart';
import 'services/firestore_gate.dart';

/// Firestore collection for registered admin emails.
const String kAdminAccountsCollection = 'admin_accounts';

/// In-memory cache after [loadAdminAccountsFromFirestore].
final Map<String, AdminAccount> adminAccountsByDocId = {};

/// Uploads all [kBuiltInAdminAccounts] to Firestore (staff/admin write rules).
Future<int> syncBuiltInAdminAccountsToFirestore() async {
  final col = FirebaseFirestore.instance.collection(kAdminAccountsCollection);
  var count = 0;
  for (final account in kBuiltInAdminAccounts) {
    await col.doc(account.docId).set(
      {
        ...account.toFirestoreMap(),
        'createdAt': FieldValue.serverTimestamp(),
      },
      SetOptions(merge: true),
    );
    adminAccountsByDocId[account.docId] = account;
    count++;
    debugPrint('admin_accounts: wrote ${account.docId} (${account.email})');
  }
  return count;
}

Future<bool> _tokenHasStaffClaims() async {
  final user = FirebaseAuth.instance.currentUser;
  if (user == null) return false;
  try {
    final result = await user.getIdTokenResult();
    final claims = result.claims;
    if (claims == null) return false;
    final staff = claims['staff'] == true || claims['staff'] == 'true';
    final admin = claims['admin'] == true || claims['admin'] == 'true';
    return staff || admin;
  } catch (_) {
    return false;
  }
}

/// Loads `admin_accounts` for the signed-in user (built-in list + own Firestore doc).
///
/// Avoids unfiltered `.get()` / `where` queries that fail when rules only allow
/// reading your own row (uses [AdminAccount.docIdForEmail] + single-doc get).
Future<void> loadAdminAccountsFromFirestore() async {
  return runFirestore(() async {
    adminAccountsByDocId.clear();
    for (final account in kBuiltInAdminAccounts) {
      adminAccountsByDocId[account.docId] = account;
    }

    final auth = FirebaseAuth.instance.currentUser;
    final email = auth?.email?.trim() ?? '';
    if (email.isEmpty) return;

    try {
      await auth?.getIdToken(true);
    } catch (_) {}

    final col = FirebaseFirestore.instance.collection(kAdminAccountsCollection);
    final docId = AdminAccount.docIdForEmail(email);

    try {
      final own = await col.doc(docId).get();
      if (own.exists && own.data() != null) {
        adminAccountsByDocId[own.id] =
            AdminAccount.fromFirestore(own.id, own.data()!);
      }
    } on FirebaseException catch (e) {
      if (isRecoverableFirestoreError(e)) {
        logRecoverableFirestoreLoad(
          'loadAdminAccountsFromFirestore doc($docId)',
          e,
        );
      } else {
        debugPrint('loadAdminAccountsFromFirestore doc: $e');
      }
    }

    // Full list only when JWT already has staff/admin (after rules + claims deploy).
    if (!await _tokenHasStaffClaims()) return;

    try {
      final snap = await col.get();
      for (final doc in snap.docs) {
        adminAccountsByDocId[doc.id] =
            AdminAccount.fromFirestore(doc.id, doc.data());
      }
    } on FirebaseException catch (e) {
      if (isRecoverableFirestoreError(e)) {
        logRecoverableFirestoreLoad('loadAdminAccountsFromFirestore list', e);
      } else {
        debugPrint('loadAdminAccountsFromFirestore list: $e');
      }
    }
  });
}

AdminAccount? adminAccountForEmail(String email) {
  final lower = email.trim().toLowerCase();
  if (lower.isEmpty) return null;
  for (final a in adminAccountsByDocId.values) {
    if (a.emailLower == lower && a.active) return a;
  }
  for (final a in kBuiltInAdminAccounts) {
    if (a.emailLower == lower && a.active) return a;
  }
  return null;
}

bool isRegisteredAdminEmail(String email) => adminAccountForEmail(email) != null;

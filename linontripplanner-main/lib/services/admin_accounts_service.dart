import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show debugPrint;

import '../admin_account.dart';
import '../admin_accounts_loader.dart';
import '../firestore_loader.dart';
import 'auth_role_claims.dart';
import 'auth_roles.dart';

export '../admin_account.dart' show AdminAccount, kBuiltInAdminAccounts;
export '../admin_accounts_loader.dart'
    show
        kAdminAccountsCollection,
        adminAccountsByDocId,
        syncBuiltInAdminAccountsToFirestore,
        loadAdminAccountsFromFirestore,
        adminAccountForEmail,
        isRegisteredAdminEmail;

/// Default provincial admin.
const String kDefaultAdminEmail = 'OPTACA@gmail.com';
const String kDefaultAdminEmailLower = 'optaca@gmail.com';

class AdminAccountsService {
  AdminAccountsService._();

  static bool emailMatchesDefaultAdmin(String email) =>
      email.trim().toLowerCase() == kDefaultAdminEmailLower;

  static AdminAccount? _builtInOrCached(String email) {
    final trimmed = email.trim();
    if (trimmed.isEmpty) return null;
    return adminAccountForEmail(trimmed);
  }

  /// Loads admin row for [email] (cache → Firestore → built-in list).
  static Future<AdminAccount?> fetchForEmail(String email) async {
    final trimmed = email.trim();
    if (trimmed.isEmpty) return null;

    final cached = _builtInOrCached(trimmed);
    if (cached != null) return cached;

    final auth = FirebaseAuth.instance.currentUser;
    if (auth != null) {
      try {
        await auth.getIdToken(true);
      } catch (_) {}
    }

    try {
      final docId = AdminAccount.docIdForEmail(trimmed);
      final doc = await FirebaseFirestore.instance
          .collection(kAdminAccountsCollection)
          .doc(docId)
          .get();
      if (!doc.exists) return null;
      final account = AdminAccount.fromFirestore(doc.id, doc.data() ?? {});
      if (!account.active) return null;
      adminAccountsByDocId[doc.id] = account;
      return account;
    } on FirebaseException catch (e) {
      if (e.code != 'permission-denied') {
        debugPrint('fetchForEmail admin_accounts: $e');
      }
      return _builtInOrCached(trimmed);
    } catch (e) {
      debugPrint('fetchForEmail admin_accounts: $e');
      return _builtInOrCached(trimmed);
    }
  }

  static Future<AdminAccount?> fetchForCurrentUser() async {
    final email = FirebaseAuth.instance.currentUser?.email ?? '';
    return fetchForEmail(email);
  }

  static Future<bool> isCurrentUserAdminAccount() async {
    final record = await fetchForCurrentUser();
    return record != null;
  }

  /// Ensures `admin_accounts` doc + `users/{uid}` admin role for listed emails.
  static Future<bool> applyAdminRoleIfRegistered() async {
    final auth = FirebaseAuth.instance.currentUser;
    if (auth == null) return false;

    final email = (auth.email ?? '').trim();
    if (email.isEmpty) return false;

    final account = await fetchForEmail(email);
    if (account == null) return false;

    try {
      await auth.getIdToken(true);
    } catch (_) {}

    final uid = auth.uid;
    final emailLower = account.emailLower.isNotEmpty
        ? account.emailLower
        : email.toLowerCase();

    // Write users/{uid} first (rules: maySelfGrantAdminRole) so staff claims can sync.
    final userRef =
        FirebaseFirestore.instance.collection(kUsersCollection).doc(uid);
    await userRef.set(
      {
        'email': account.email.isNotEmpty ? account.email : email,
        'emailLower': emailLower,
        'role': AppRole.admin.firestoreValue,
        'rolePermanent': true,
        'firebaseUid': uid,
        'fullName': auth.displayName?.trim().isNotEmpty == true
            ? auth.displayName!.trim()
            : account.displayName,
        'name': auth.displayName?.trim().isNotEmpty == true
            ? auth.displayName!.trim()
            : account.displayName,
        'updatedAt': FieldValue.serverTimestamp(),
      },
      SetOptions(merge: true),
    );

    await ensureAdminAccountDocumentInFirestore(
      account: account,
      firebaseUid: uid,
    );
    await persistLongTermStaffRoleClaims();
    await loadUsersFromFirestore();
    return true;
  }

  /// Creates or updates `admin_accounts/{docId}`.
  static Future<void> ensureAdminAccountDocumentInFirestore({
    required AdminAccount account,
    required String firebaseUid,
  }) async {
    final ref = FirebaseFirestore.instance
        .collection(kAdminAccountsCollection)
        .doc(account.docId);
    try {
      final payload =
          account.toFirestoreMap(firebaseUidOverride: firebaseUid);
      // Merge set without a prior get — bootstrap rules apply before JWT staff claims.
      await ref.set(payload, SetOptions(merge: true));
      adminAccountsByDocId[account.docId] = AdminAccount(
        docId: account.docId,
        email: account.email,
        emailLower: account.emailLower,
        password: account.password,
        role: account.role,
        active: account.active,
        displayName: account.displayName,
        firebaseUid: firebaseUid,
      );
    } on FirebaseException catch (e) {
      debugPrint('ensureAdminAccountDocumentInFirestore: $e');
    }
  }
}

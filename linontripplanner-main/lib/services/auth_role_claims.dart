import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show debugPrint;

import '../data.dart';
import 'admin_accounts_service.dart';
import 'admin_session_bootstrap.dart' show isKnownAdminEmail;
import 'auth_roles.dart';
import 'firebase_functions_config.dart';

const String _kUsersCollection = 'users';

/// Refreshes the ID token so Firestore rules receive permanent role custom claims.
Future<void> refreshAuthRoleClaims({bool forceRefresh = true}) async {
  final user = FirebaseAuth.instance.currentUser;
  if (user == null) return;
  try {
    await user.getIdToken(forceRefresh);
    final result = await user.getIdTokenResult(forceRefresh);
    final claims = result.claims;
    if (claims == null) return;
    final role = claims['role'];
    if (role is String && role.isNotEmpty) {
      debugPrint(
        'Auth role claims: role=$role staff=${claims['staff']} admin=${claims['admin']}',
      );
    }
  } catch (e) {
    debugPrint('refreshAuthRoleClaims: $e');
  }
}

/// Pushes `users/{uid}` role to Auth custom claims via Cloud Function, then refreshes JWT.
Future<void> syncRoleClaimsFromCloudFunction() async {
  final user = FirebaseAuth.instance.currentUser;
  if (user == null) return;
  try {
    final callable =
        tourismCloudFunctions().httpsCallable('refreshRoleClaims');
    await callable.call();
  } on FirebaseFunctionsException catch (e) {
    if (e.code != 'not-found' && e.code != 'unavailable') {
      debugPrint('syncRoleClaimsFromCloudFunction: $e');
    }
  } catch (e) {
    debugPrint('syncRoleClaimsFromCloudFunction: $e');
  }
}

/// Long-term staff/admin: Firestore profile + Auth claims (retries for new sign-ins).
Future<void> persistLongTermStaffRoleClaims({int maxAttempts = 4}) async {
  final user = FirebaseAuth.instance.currentUser;
  if (user == null) return;

  for (var attempt = 0; attempt < maxAttempts; attempt++) {
    await syncRoleClaimsFromCloudFunction();
    await refreshAuthRoleClaims(forceRefresh: true);
    try {
      final result = await user.getIdTokenResult(true);
      final claims = result.claims;
      final staff = claims?['staff'] == true || claims?['staff'] == 'true';
      final admin = claims?['admin'] == true || claims?['admin'] == 'true';
      if (staff || admin) return;
    } catch (_) {}
    if (attempt < maxAttempts - 1) {
      await Future<void>.delayed(Duration(milliseconds: 600 * (attempt + 1)));
    }
  }
}

/// Ensures `users/{uid}` has permanent staff/admin role and JWT claims before catalog writes.
Future<void> ensurePermanentStaffRoleForCatalogWrite() async {
  final auth = FirebaseAuth.instance.currentUser;
  if (auth == null) {
    throw FirebaseException(
      plugin: 'cloud_firestore',
      code: 'permission-denied',
      message: 'Sign in required to edit tourism data.',
    );
  }

  final email = (auth.email ?? '').trim();
  if (email.isNotEmpty && isKnownAdminEmail(email)) {
    await AdminAccountsService.applyAdminRoleIfRegistered();
    return;
  }

  if (await AdminAccountsService.isCurrentUserAdminAccount()) {
    await AdminAccountsService.applyAdminRoleIfRegistered();
    return;
  }

  final uid = auth.uid;
  final userRef =
      FirebaseFirestore.instance.collection(_kUsersCollection).doc(uid);
  final snap = await userRef.get();
  final data = snap.data();
  var role = AppRole.fromString(data?['role'] as String?);
  final appUser = findAppUserByFirebaseUid(uid);
  if (role == AppRole.user || role == AppRole.tourist) {
    final fromCache = AppRole.fromString(appUser?.role);
    if (fromCache == AppRole.admin || fromCache == AppRole.municipalManager) {
      role = fromCache;
    }
  }

  if (role == AppRole.admin || role == AppRole.municipalManager) {
    await userRef.set(
      {
        'email': email.isNotEmpty ? email : (data?['email'] ?? ''),
        'emailLower': email.toLowerCase(),
        'role': role.firestoreValue,
        'rolePermanent': true,
        'firebaseUid': uid,
        'updatedAt': FieldValue.serverTimestamp(),
      },
      SetOptions(merge: true),
    );
    await persistLongTermStaffRoleClaims();
    return;
  }

  await persistLongTermStaffRoleClaims();
  final claims = await auth.getIdTokenResult(true);
  final staff = claims.claims?['staff'] == true ||
      claims.claims?['staff'] == 'true' ||
      claims.claims?['admin'] == true ||
      claims.claims?['admin'] == 'true';
  if (staff) return;

  throw FirebaseException(
    plugin: 'cloud_firestore',
    code: 'permission-denied',
    message:
        'Your account needs a permanent admin or municipal_manager role. '
        'Sign out, sign in again, or ask an administrator to update your role.',
  );
}

/// Best-effort role: custom claims first, then [fallbackRole] from Firestore.
Future<AppRole> resolveAppRole({required String fallbackRole}) async {
  final user = FirebaseAuth.instance.currentUser;
  if (user == null) return AppRole.tourist;
  try {
    final result = await user.getIdTokenResult();
    final raw = result.claims?['role'];
    if (raw is String && raw.trim().isNotEmpty) {
      return AppRole.fromString(raw);
    }
  } catch (_) {}
  return AppRole.fromString(fallbackRole);
}

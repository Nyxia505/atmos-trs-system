import 'dart:async' show unawaited;

import 'package:atmos_trs_system/config/auth_config.dart';
import 'package:atmos_trs_system/config/session_storage.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:trip_plan/services/tourism_session.dart';

/// Signs out of Firebase and clears both ATMOS and Trip Planner local sessions.
Future<void> signOutSharedModules() async {
  AuthConfig.currentUserUid = null;
  try {
    clearTourismSessionOnLogout();
  } catch (_) {}
  try {
    await SessionStorage.clearSession();
  } catch (_) {}
  try {
    await FirebaseAuth.instance
        .signOut()
        .timeout(const Duration(milliseconds: 1500));
  } catch (_) {
    unawaited(FirebaseAuth.instance.signOut());
  }
}

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../data.dart';
import '../firestore_loader.dart';
import '../home_screen.dart';
import '../services/admin_accounts_service.dart';
import '../services/admin_session_bootstrap.dart';
import '../services/auth_roles.dart';

/// Blocks admin UI unless the signed-in user has admin or municipal_manager role.
class AdminAccessGate extends StatefulWidget {
  final Widget child;

  const AdminAccessGate({super.key, required this.child});

  @override
  State<AdminAccessGate> createState() => _AdminAccessGateState();
}

class _AdminAccessGateState extends State<AdminAccessGate> {
  bool _loading = true;
  bool _allowed = false;

  @override
  void initState() {
    super.initState();
    final quickAllow = isLikelyAdminSession();
    if (quickAllow) {
      _allowed = true;
      _loading = false;
      _verifyInBackground();
      return;
    }
    _verify();
  }

  Future<void> _verifyInBackground() async {
    await _verify(silent: true);
  }

  Future<void> _verify({bool silent = false}) async {
    try {
      if (!silent) {
        await loadUsersFromFirestore();
      }
      await ensureCurrentUserProfileInFirestore();
      await AdminAccountsService.applyAdminRoleIfRegistered();
      if (!silent) {
        await loadUsersFromFirestore();
      }
    } catch (_) {}
    if (!mounted) return;
    final roleOk = AuthRoles.canAccessAdminDashboard();
    final accountOk = await AdminAccountsService.isCurrentUserAdminAccount();
    setState(() {
      _allowed = roleOk || accountOk;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Scaffold(
        backgroundColor: AppColors.background,
        body: const Center(
          child: CircularProgressIndicator(color: AppColors.primary),
        ),
      );
    }
    if (!_allowed) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('Access denied'),
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.white,
        ),
        body: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.lock_outline, size: 56, color: AppColors.textGrey),
              const SizedBox(height: 16),
              const Text(
                'You do not have permission to open the admin dashboard.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 16, height: 1.4),
              ),
              const SizedBox(height: 8),
              Text(
                _roleHint(),
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 13,
                  color: AppColors.textGrey,
                ),
              ),
              const SizedBox(height: 24),
              FilledButton(
                onPressed: () {
                  Navigator.of(context).pushAndRemoveUntil(
                    MaterialPageRoute<void>(
                      builder: (_) => const HomeScreen(),
                    ),
                    (_) => false,
                  );
                },
                child: const Text('Open app home'),
              ),
            ],
          ),
        ),
      );
    }
    return widget.child;
  }

  String _roleHint() {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    final user = findAppUserByFirebaseUid(uid);
    final role = user?.role ?? 'unknown';
    return 'Your account role is "$role". Contact an administrator to grant admin or municipal_manager access.';
  }
}

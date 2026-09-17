import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:atmos_trs_system/config/app_theme.dart';
import 'package:atmos_trs_system/config/auth_config.dart';
import 'package:atmos_trs_system/config/session_storage.dart';
import 'package:atmos_trs_system/services/establishment_registration_service.dart';

/// Post-signup home for tourism establishments (pending approval + placeholder).
class EstablishmentDashboardScreen extends StatefulWidget {
  const EstablishmentDashboardScreen({super.key});

  @override
  State<EstablishmentDashboardScreen> createState() =>
      _EstablishmentDashboardScreenState();
}

class _EstablishmentDashboardScreenState
    extends State<EstablishmentDashboardScreen> {
  bool _loading = true;
  String _businessName = '';
  String _category = '';
  String _status = 'pending';
  String _municipality = '';
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final uid = FirebaseAuth.instance.currentUser?.uid ??
        await SessionStorage.getStoredUser();
    if (uid == null || uid.isEmpty) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Session expired. Please log in again.';
      });
      return;
    }

    try {
      final db = FirebaseFirestore.instance;
      final userDoc = await db.collection('users').doc(uid).get();
      final estDoc = await db
          .collection(EstablishmentRegistrationService.establishmentsCollection)
          .doc(uid)
          .get();
      final user = userDoc.data() ?? const <String, dynamic>{};
      final est = estDoc.data() ?? const <String, dynamic>{};
      if (!mounted) return;
      setState(() {
        _businessName = (est['businessName'] ??
                est['name'] ??
                user['businessName'] ??
                'Your establishment')
            .toString();
        _category = (est['category'] ?? est['type'] ?? user['category'] ?? '')
            .toString();
        _status = (user['status'] ?? est['status'] ?? 'pending')
            .toString()
            .toLowerCase();
        _municipality =
            (user['municipality'] ?? est['municipality'] ?? '').toString();
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Could not load establishment profile.';
      });
    }
  }

  Future<void> _logout() async {
    await SessionStorage.clearSession();
    AuthConfig.currentUserUid = null;
    try {
      await FirebaseAuth.instance.signOut();
    } catch (_) {}
    if (!mounted) return;
    Navigator.pushNamedAndRemoveUntil(context, '/login', (_) => false);
  }

  bool get _isPending => _status == 'pending' || _status.isEmpty;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        backgroundColor: AppTheme.brandOrange,
        foregroundColor: Colors.white,
        title: const Text('Establishment'),
        actions: [
          IconButton(
            tooltip: 'Log out',
            onPressed: _logout,
            icon: const Icon(Icons.logout_rounded),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(_error!, textAlign: TextAlign.center),
                        const SizedBox(height: 16),
                        FilledButton(
                          onPressed: _logout,
                          child: const Text('Back to login'),
                        ),
                      ],
                    ),
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(20, 24, 20, 40),
                    children: [
                      Text(
                        _businessName,
                        style: const TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.w800,
                          color: Color(0xFF1C1917),
                        ),
                      ),
                      if (_category.isNotEmpty) ...[
                        const SizedBox(height: 6),
                        Text(
                          _category,
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFF78716C),
                          ),
                        ),
                      ],
                      if (_municipality.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(
                          _municipality,
                          style: const TextStyle(
                            fontSize: 13,
                            color: Color(0xFFA8A29E),
                          ),
                        ),
                      ],
                      const SizedBox(height: 24),
                      Container(
                        padding: const EdgeInsets.all(18),
                        decoration: BoxDecoration(
                          color: _isPending
                              ? const Color(0xFFFFF7ED)
                              : const Color(0xFFECFDF5),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: _isPending
                                ? const Color(0xFFFDBA74)
                                : const Color(0xFF6EE7B7),
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _isPending
                                  ? 'Pending LGU / Provincial approval'
                                  : 'Account approved',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w800,
                                color: _isPending
                                    ? const Color(0xFF9A3412)
                                    : const Color(0xFF065F46),
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              _isPending
                                  ? 'Your tourism establishment registration was '
                                      'submitted successfully. An LGU or Provincial '
                                      'Tourism officer will review your details. '
                                      'You can log in anytime to check this status.'
                                  : 'Your establishment is active on ATMOS-TRS. '
                                      'More establishment tools will appear here soon.',
                              style: TextStyle(
                                fontSize: 14,
                                height: 1.45,
                                color: _isPending
                                    ? const Color(0xFF9A3412)
                                    : const Color(0xFF065F46),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 28),
                      const Text(
                        'What happens next',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 10),
                      const Text(
                        '1. Keep your Business Permit details accurate.\n'
                        '2. Wait for approval from tourism officers.\n'
                        '3. Once approved, establishment features will unlock here.',
                        style: TextStyle(
                          fontSize: 14,
                          height: 1.55,
                          color: Color(0xFF57534E),
                        ),
                      ),
                    ],
                  ),
                ),
    );
  }
}

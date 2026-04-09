import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';

/// Profile for a dashboard user stored in Firestore `users` collection.
/// Used to restrict municipal dashboard data by [municipality].
/// Passwords are never stored; use Firebase Auth for login.
class DashboardUserProfile {
  const DashboardUserProfile({
    required this.email,
    required this.role,
    required this.municipality,
  });

  final String email;
  final String role;
  final String municipality;

  static DashboardUserProfile? fromFirestore(Map<String, dynamic> data) {
    final email = data['email'] as String?;
    final role = data['role'] as String?;
    final municipality = data['municipality'] as String?;
    if (email == null || email.isEmpty) return null;
    return DashboardUserProfile(
      email: email.trim(),
      role: (role ?? '').trim().toLowerCase(),
      municipality: (municipality ?? '').trim(),
    );
  }
}

/// Fetches dashboard user profile from Firestore `users` collection by email.
/// Each document should have: email, role, municipality (no passwords).
class DashboardUserService {
  DashboardUserService._();

  static const String _collectionId = 'users';

  static bool get _isFirebaseInitialized {
    try {
      return Firebase.apps.isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  static FirebaseFirestore get _firestore => FirebaseFirestore.instance;

  /// Fetches the dashboard user profile for the given email.
  /// Returns null if Firebase is not initialized, or no document matches.
  static Future<DashboardUserProfile?> getProfileByEmail(String email) async {
    if (!_isFirebaseInitialized || email.trim().isEmpty) return null;
    final trimmed = email.trim();
    final lower = trimmed.toLowerCase();
    // Firestore equality is case-sensitive; try both normalized and as-entered.
    for (final candidate in <String>{lower, trimmed}) {
      if (candidate.isEmpty) continue;
      try {
        final snapshot = await _firestore
            .collection(_collectionId)
            .where('email', isEqualTo: candidate)
            .limit(1)
            .get();
        if (snapshot.docs.isEmpty) continue;
        final data = snapshot.docs.first.data();
        return DashboardUserProfile.fromFirestore(data);
      } catch (_) {
        continue;
      }
    }
    return null;
  }
}

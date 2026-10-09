import 'package:cloud_firestore/cloud_firestore.dart';

/// One row in Firestore collection `admin_accounts`.
///
/// Document id: [AdminAccount.docId] (from email, e.g. `optaca_at_gmail_com`).
/// Password is stored for your records; sign-in uses Firebase Authentication.
class AdminAccount {
  final String docId;
  final String email;
  final String emailLower;
  final String password;
  final String role;
  final bool active;
  final String displayName;
  final String? firebaseUid;

  const AdminAccount({
    required this.docId,
    required this.email,
    required this.emailLower,
    required this.password,
    this.role = 'admin',
    this.active = true,
    this.displayName = 'Admin',
    this.firebaseUid,
  });

  factory AdminAccount.fromFirestore(String docId, Map<String, dynamic> data) {
    return AdminAccount(
      docId: docId,
      email: (data['email'] as String?)?.trim() ?? '',
      emailLower: (data['emailLower'] as String?)?.trim().toLowerCase() ?? '',
      password: (data['password'] as String?) ?? '',
      role: (data['role'] as String?)?.trim().toLowerCase() ?? 'admin',
      active: data['active'] != false,
      displayName: (data['displayName'] as String?)?.trim().isNotEmpty == true
          ? (data['displayName'] as String).trim()
          : 'Admin',
      firebaseUid: (data['firebaseUid'] as String?)?.trim(),
    );
  }

  Map<String, dynamic> toFirestoreMap({String? firebaseUidOverride}) {
    return {
      'email': email,
      'emailLower': emailLower,
      'password': password,
      'role': role,
      'active': active,
      'displayName': displayName,
      if (firebaseUidOverride != null && firebaseUidOverride.isNotEmpty)
        'firebaseUid': firebaseUidOverride
      else if (firebaseUid != null && firebaseUid!.isNotEmpty)
        'firebaseUid': firebaseUid,
      'updatedAt': FieldValue.serverTimestamp(),
    };
  }

  static String docIdForEmail(String email) {
    final lower = email.trim().toLowerCase();
    return lower
        .replaceAll('@', '_at_')
        .replaceAll('.', '_')
        .replaceAll(RegExp(r'[^a-z0-9_]+'), '');
  }
}

/// Built-in admin accounts uploaded to `admin_accounts` (extend this list as needed).
const List<AdminAccount> kBuiltInAdminAccounts = [
  AdminAccount(
    docId: 'optaca_at_gmail_com',
    email: 'OPTACA@gmail.com',
    emailLower: 'optaca@gmail.com',
    password: 'admin123',
    role: 'admin',
    active: true,
    displayName: 'Provincial Admin',
  ),
];

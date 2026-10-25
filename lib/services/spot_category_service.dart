import 'package:atmos_trs_system/config/session_storage.dart';
import 'package:atmos_trs_system/services/user_directory_service.dart';
import 'package:atmos_trs_system/utils/municipality_helper.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show debugPrint;

/// Built-in tourist spot categories plus LGU-added names in `spot_categories`.
class SpotCategoryService {
  SpotCategoryService._();

  static final SpotCategoryService instance = SpotCategoryService._();

  static const collectionId = 'spot_categories';

  /// Dropdown value that opens the new-category prompt. Not a real category.
  static const addNewValue = '__add_new_category__';

  static const builtIn = <String>[
    'Beach',
    'Falls',
    'Historical',
    'Mountain',
    'Resort',
  ];

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  Stream<List<String>> watchCustomNames() {
    return _firestore.collection(collectionId).snapshots().map((snap) {
      final names = <String>[];
      for (final doc in snap.docs) {
        final name = (doc.data()['name'] as String?)?.trim() ?? '';
        if (name.isNotEmpty) names.add(name);
      }
      return names;
    });
  }

  /// Saves [raw] for LGU accounts. Returns the canonical name to select.
  Future<SpotCategoryAddResult> add(String raw) async {
    final cleaned = SpotCategoryNames.cleaned(raw);
    if (cleaned == null) {
      return const SpotCategoryAddResult.failure(
        'Enter a category name using letters or numbers (2–40 characters).',
      );
    }

    final user = FirebaseAuth.instance.currentUser;
    final uid = user?.uid;
    if (user == null || uid == null || uid.isEmpty) {
      return const SpotCategoryAddResult.failure(
        'Your session expired. Please sign in again.',
      );
    }

    final profile = await UserDirectoryService.getProfileByUid(uid);
    final sessionRole = await SessionStorage.getStoredRole();
    final emailRole = SessionStorage.getRoleFromEmail(user.email ?? '');
    final profileRole =
        UserDirectoryService.canonicalStaffRole(profile?.roleRaw ?? '');
    final sessionIsLgu = sessionRole == UserRole.tourism ||
        sessionRole == UserRole.provincialTourism;
    final emailIsLgu = emailRole == UserRole.tourism ||
        emailRole == UserRole.provincialTourism;
    final profileIsLgu = profileRole == 'tourism' ||
        profileRole == 'provincial_tourism' ||
        profileRole == 'governor';
    if (!sessionIsLgu && !emailIsLgu && !profileIsLgu) {
      if (profile == null) {
        return const SpotCategoryAddResult.failure(
          'Missing users profile for this login (users.email or users.role).',
        );
      }
      final shown = profile.roleRaw.trim().isEmpty
          ? 'missing'
          : profile.roleRaw.trim();
      return SpotCategoryAddResult.failure(
        'users.role is "$shown". Category creation needs an LGU tourism role '
        '(tourism or tourism_office) for this municipality.',
      );
    }

    var municipalityId = profile?.municipalityId.trim() ?? '';
    if (municipalityId.isEmpty) {
      municipalityId = getMunicipalityIdFromName(profile?.municipality);
    }
    if (municipalityId.isEmpty) {
      municipalityId =
          (await SessionStorage.getStoredMunicipalityId())?.trim() ?? '';
    }
    if (municipalityId.isEmpty) {
      municipalityId =
          SessionStorage.getMunicipalityIdFromTourismEmail(user.email ?? '') ??
          '';
    }
    final isProvincial = profileRole == 'provincial_tourism' ||
        profileRole == 'governor' ||
        sessionRole == UserRole.provincialTourism ||
        emailRole == UserRole.provincialTourism;
    if (!isProvincial && municipalityId.isEmpty) {
      return const SpotCategoryAddResult.failure(
        'Missing users.municipalityId. This LGU account is not linked to a municipality.',
      );
    }

    final roleRaw = profileRole ??
        (isProvincial ? 'provincial_tourism' : 'tourism');
    await UserDirectoryService.ensureStaffUserDoc(
      uid: uid,
      email: user.email ?? profile?.email ?? '',
      roleRaw: roleRaw,
      fullName: profile?.fullName,
      municipalityId: municipalityId.isEmpty ? null : municipalityId,
    );

    final key = SpotCategoryNames.keyOf(cleaned);
    if (key.length < 2) {
      return const SpotCategoryAddResult.failure(
        'Enter a category name using letters or numbers (2–40 characters).',
      );
    }

    final builtInMatch = SpotCategoryNames.canonicalMatch(cleaned, builtIn);
    if (builtInMatch != null) {
      return SpotCategoryAddResult.duplicate(builtInMatch);
    }

    final ref = _firestore.collection(collectionId).doc(key);
    try {
      final savedNames =
          await _firestore.collection(collectionId).limit(200).get();
      for (final doc in savedNames.docs) {
        final saved = (doc.data()['name'] as String?)?.trim() ?? '';
        if (SpotCategoryNames.canonicalMatch(cleaned, [saved]) != null) {
          return SpotCategoryAddResult.duplicate(
            saved.isEmpty ? cleaned : saved,
          );
        }
      }
      await ref.set({
        'name': cleaned,
        'nameKey': key,
        'createdByUid': uid,
        if (municipalityId.isNotEmpty) 'municipalityId': municipalityId,
        'createdAt': FieldValue.serverTimestamp(),
      });
      return SpotCategoryAddResult.created(cleaned);
    } on FirebaseException catch (e) {
      if (e.code == 'permission-denied') {
        // Firestore rules may deny when users.municipalityId is missing
        // (the doc has municipality but not municipalityId). Fall back to the
        // Cloud Function which runs with admin privileges and also backfills
        // municipalityId on the user doc for future direct writes.
        debugPrint(
          '[SpotCategory] Direct write denied. Trying Cloud Function fallback.',
        );
        return _addViaCloudFunction(cleaned, municipalityId);
      }
      return const SpotCategoryAddResult.failure(
        'Could not save that category. Check your connection and try again.',
      );
    }
  }

  static Future<SpotCategoryAddResult> _addViaCloudFunction(
    String cleaned,
    String municipalityId,
  ) async {
    try {
      final functions =
          FirebaseFunctions.instanceFor(region: 'asia-southeast1');
      final callable = functions.httpsCallable(
        'createSpotCategory',
        options: HttpsCallableOptions(timeout: const Duration(seconds: 30)),
      );
      final response = await callable.call<Map<String, dynamic>>({
        'name': cleaned,
        if (municipalityId.isNotEmpty) 'municipalityId': municipalityId,
      });
      final data = response.data;
      final name = (data['name'] as String?)?.trim() ?? cleaned;
      final alreadyExists = data['alreadyExists'] == true;
      if (data['ok'] == true) {
        if (alreadyExists) return SpotCategoryAddResult.duplicate(name);
        return SpotCategoryAddResult.created(name);
      }
      return const SpotCategoryAddResult.failure(
        'Cloud Function did not confirm the category was saved.',
      );
    } on FirebaseFunctionsException catch (e) {
      debugPrint('[SpotCategory] CF error: ${e.code} ${e.message}');
      return SpotCategoryAddResult.failure(
        e.message?.trim().isNotEmpty == true
            ? e.message!.trim()
            : 'Could not save category [${e.code}]. '
                'Deploy the createSpotCategory Cloud Function.',
      );
    } catch (e) {
      debugPrint('[SpotCategory] CF call failed: $e');
      return SpotCategoryAddResult.failure(
        'Could not save that category. Check your connection and try again.',
      );
    }
  }
}

class SpotCategoryAddResult {
  const SpotCategoryAddResult._({
    required this.name,
    required this.alreadyExists,
    required this.error,
  });

  const SpotCategoryAddResult.created(String name)
      : this._(name: name, alreadyExists: false, error: null);

  const SpotCategoryAddResult.duplicate(String name)
      : this._(name: name, alreadyExists: true, error: null);

  const SpotCategoryAddResult.failure(String error)
      : this._(name: null, alreadyExists: false, error: error);

  final String? name;
  final bool alreadyExists;
  final String? error;

  bool get ok => name != null && error == null;
}

/// Name cleanup and duplicate checks shared by the form and tests.
class SpotCategoryNames {
  SpotCategoryNames._();

  static final _allowed = RegExp(r"^[A-Za-z0-9][A-Za-z0-9 '&./-]{1,39}$");

  /// Trimmed display name, or null when the input is not a usable category.
  static String? cleaned(String raw) {
    final collapsed = raw.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (collapsed.length < 2 || collapsed.length > 40) return null;
    if (collapsed.toLowerCase() == 'all') return null;
    if (!_allowed.hasMatch(collapsed)) return null;
    return collapsed;
  }

  static String keyOf(String name) {
    return name
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
        .replaceAll(RegExp(r'^_+|_+$'), '');
  }

  /// Existing label that matches [candidate] ignoring case and extra spaces.
  static String? canonicalMatch(String candidate, Iterable<String> existing) {
    final key = keyOf(candidate);
    if (key.isEmpty) return null;
    for (final name in existing) {
      if (keyOf(name) == key) return name;
    }
    return null;
  }

  /// Built-in names, then saved names, then categories already used on spots.
  static List<String> merge({
    required Iterable<String> saved,
    required Iterable<String> fromSpots,
  }) {
    final ordered = <String>[];
    final seen = <String>{};

    void add(String raw) {
      final name = raw.trim().replaceAll(RegExp(r'\s+'), ' ');
      if (name.isEmpty || name.toLowerCase() == 'all') return;
      final key = keyOf(name);
      if (key.isEmpty || !seen.add(key)) return;
      ordered.add(name);
    }

    for (final name in SpotCategoryService.builtIn) {
      add(name);
    }
    for (final name in saved) {
      add(name);
    }
    for (final name in fromSpots) {
      add(name);
    }
    return ordered;
  }
}

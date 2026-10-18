import 'package:atmos_trs_system/config/session_storage.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

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

    final role = await SessionStorage.getStoredRole();
    final allowed =
        role == UserRole.tourism || role == UserRole.provincialTourism;
    if (!allowed) {
      return const SpotCategoryAddResult.failure(
        'Only LGU tourism accounts can add categories.',
      );
    }

    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null || uid.isEmpty) {
      return const SpotCategoryAddResult.failure(
        'Your session expired. Please sign in again.',
      );
    }

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
      final existing = await ref.get();
      if (existing.exists) {
        final saved = (existing.data()?['name'] as String?)?.trim();
        return SpotCategoryAddResult.duplicate(
          saved == null || saved.isEmpty ? cleaned : saved,
        );
      }
      await ref.set({
        'name': cleaned,
        'nameKey': key,
        'createdByUid': uid,
        'createdAt': FieldValue.serverTimestamp(),
      });
      return SpotCategoryAddResult.created(cleaned);
    } on FirebaseException catch (e) {
      if (e.code == 'permission-denied') {
        return const SpotCategoryAddResult.failure(
          'Only LGU tourism accounts can add categories.',
        );
      }
      return const SpotCategoryAddResult.failure(
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

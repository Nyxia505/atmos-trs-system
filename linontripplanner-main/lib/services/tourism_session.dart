import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart'
    show ValueNotifier, debugPrint, kDebugMode, kIsWeb;

import '../data.dart';
import '../firestore_loader.dart';
import '../municipal_road_distances.dart';
import '../municipality_bus_terminals.dart';
import '../admin_accounts_loader.dart';
import '../hub_spot_transport_fees_loader.dart';
import '../transportation_fees_loader.dart';
import '../widgets/municipality_image.dart' show clearTourismImageUrlCache;
import 'admin_accounts_service.dart';
import 'admin_session_bootstrap.dart' show isKnownAdminEmail;
import 'auth_role_claims.dart';
import 'firestore_gate.dart';
import 'home_personalization_service.dart';
import 'spot_interaction_history.dart';
import 'spot_ratings_store.dart';
import 'supabase_image_library.dart' show ensureSupabaseImageIndexLoaded;

/// Signed-out — login required for profile / CF; public catalogs may still load.
bool tourismIsGuestSession() => FirebaseAuth.instance.currentUser == null;

bool _publicCatalogLoaded = false;
Future<void>? _publicCatalogLoadFuture;
String? _completedBootstrapKey;
Future<void>? _bootstrapFuture;

/// True after [loadPublicTourismCatalogFromFirestore] completes successfully.
bool get isPublicTourismCatalogLoaded => _publicCatalogLoaded;

/// Bumped when public catalogs finish loading so tab roots (Spots, Map, …)
/// rebuild even when they sit under a kept-alive [Navigator] route.
final ValueNotifier<int> tourismCatalogRevision = ValueNotifier<int>(0);

String _bootstrapAuthKey() =>
    FirebaseAuth.instance.currentUser?.uid ?? '__guest__';

/// Waits for Firebase Auth token when a user is signed in.
Future<void> _ensureAuthTokenReady({bool forceRefresh = false}) async {
  final user = FirebaseAuth.instance.currentUser;
  if (user == null) return;
  try {
    await user.getIdToken(forceRefresh);
  } catch (e) {
    debugPrint('Auth token refresh before Firestore: $e');
  }
}

Future<bool> _sessionUsesPublicCatalogOnly() async {
  final user = FirebaseAuth.instance.currentUser;
  if (user == null) return true;
  try {
    final result = await user.getIdTokenResult();
    final claims = result.claims;
    if (claims?['staff'] == true || claims?['staff'] == 'true') return false;
    if (claims?['admin'] == true || claims?['admin'] == 'true') return false;
    final role = claims?['role'];
    if (role is! String || role.trim().isEmpty) return true;
    final r = role.trim().toLowerCase();
    return r == 'tourist' || r == 'user';
  } catch (_) {
    return true;
  }
}

Future<void> loadSpotRatingsFromFirestore() async {
  final remote = await fetchSpotRatingsFromFirestore();
  SpotRatingsStore.instance.mergeRemote(remote);
}

const _catalogLoaders = <String, Future<void> Function()>{
  'tourist_spots': loadTouristSpotsFromFirestore,
  'municipalities': loadMunicipalitiesFromFirestore,
  'featured_spots': loadFeaturedSpotsFromFirestore,
  'events': loadEventsFromFirestore,
  'announcements': loadAnnouncementsFromFirestore,
  'spot_ratings': loadSpotRatingsFromFirestore,
  'transportation_fees': loadTransportationFeesFromFirestore,
  'hub_spot_transport_fees': loadHubSpotTransportFeesFromFirestore,
  kMunicipalRoadDistancesCollection: loadMunicipalRoadDistancesFromFirestore,
};

Future<void> _runCatalogLoaders() async {
  // Photos live in Supabase Storage; re-read the bucket listing alongside the
  // catalog so images edited in Supabase show up on the next refresh.
  clearTourismImageUrlCache();
  // Not awaited: municipality widgets load the index themselves.
  unawaited(ensureSupabaseImageIndexLoaded());

  final user = FirebaseAuth.instance.currentUser;
  final publicOnly = await _sessionUsesPublicCatalogOnly();
  if (user != null) {
    if (publicOnly) {
      await _ensureAuthTokenReady();
    } else {
      try {
        await persistLongTermStaffRoleClaims();
      } catch (e) {
        debugPrint('Catalog load role claims: $e');
      }
      await _ensureAuthTokenReady();
    }
  }

  Future<void> loadOne(String key, Future<void> Function() loader) async {
    for (var attempt = 0; attempt < 3; attempt++) {
      try {
        await loader();
        if (kDebugMode) debugPrint('Firestore load $key: ok');
        if (key == 'transportation_fees') {
          seedTransportationFeesFromEmbeddedMatrixIfEmpty();
        }
        if (key == 'hub_spot_transport_fees') {
          seedHubSpotTransportFeesFromEmbeddedMatrixIfEmpty();
        }
        return;
      } catch (e, st) {
        final denied = e.toString().contains('permission-denied');
        if (denied && attempt < 2) {
          if (user != null && !publicOnly) {
            try {
              await persistLongTermStaffRoleClaims();
            } catch (_) {}
          }
          await _ensureAuthTokenReady(forceRefresh: true);
          await Future<void>.delayed(Duration(milliseconds: 400 * (attempt + 1)));
          continue;
        }
        if (denied && kDebugMode) {
          debugPrint(
            'Firestore load $key failed: $e\n'
            'Deploy rules: firebase deploy --only firestore:rules --project atmos-trs-system',
          );
        } else {
          debugPrint('Firestore load $key failed: $e\n$st');
        }
        return;
      }
    }
  }

  // Spots first so Home / Spots tab can paint without waiting on the rest.
  final spotsLoader = _catalogLoaders['tourist_spots'];
  if (spotsLoader != null) {
    await loadOne('tourist_spots', spotsLoader);
    tourismCatalogRevision.value++;
  }

  // Remaining catalogs in parallel (much faster than sequential + 80ms gaps).
  final rest = _catalogLoaders.entries
      .where((e) => e.key != 'tourist_spots')
      .toList(growable: false);
  await Future.wait([
    for (final e in rest) loadOne(e.key, e.value),
  ]);

  applyDefaultMunicipalityBusTerminals();
  _publicCatalogLoaded = true;
  tourismCatalogRevision.value++;
}

/// Public catalogs ([firestore.rules]: `allow read: if true` — no sign-in required).
Future<void> loadPublicTourismCatalogFromFirestore({bool force = false}) async {
  if (!force && _publicCatalogLoaded) return;

  if (_publicCatalogLoadFuture != null) {
    await _publicCatalogLoadFuture!;
    if (!force && _publicCatalogLoaded) return;
  }

  if (force) {
    _publicCatalogLoaded = false;
  }
  if (!force && _publicCatalogLoaded) return;

  final future = _runCatalogLoaders();
  _publicCatalogLoadFuture = future;
  try {
    await future;
    await SpotRatingsStore.instance.ensureLoaded();
  } finally {
    if (identical(_publicCatalogLoadFuture, future)) {
      _publicCatalogLoadFuture = null;
    }
  }
}

/// Featured, spots, events, and announcements for the governor admin tabs.
const _adminGovernorCatalogLoaders = <String, Future<void> Function()>{
  'tourist_spots': loadTouristSpotsFromFirestore,
  'featured_spots': loadFeaturedSpotsFromFirestore,
  'events': loadEventsFromFirestore,
  'announcements': loadAnnouncementsFromFirestore,
};

Future<void> loadAdminGovernorCatalogsFromFirestore() async {
  await _ensureAuthTokenReady();

  for (final entry in _adminGovernorCatalogLoaders.entries) {
    // tourist_spots is loaded first in [reloadAdminDashboardCatalogs].
    if (entry.key == 'tourist_spots' && allSpots.isNotEmpty) {
      if (kDebugMode) {
        debugPrint(
          'Admin governor catalog tourist_spots: skip '
          '(already ${allSpots.length})',
        );
      }
      continue;
    }
    var ok = false;
    for (var attempt = 0; attempt < 2 && !ok; attempt++) {
      try {
        await entry.value();
        ok = true;
        if (kDebugMode) {
          debugPrint('Admin governor catalog ${entry.key}: ok');
        }
      } catch (e, st) {
        final denied = e.toString().contains('permission-denied');
        if (denied && attempt == 0) {
          await _ensureAuthTokenReady();
          continue;
        }
        debugPrint('Admin governor catalog ${entry.key} failed: $e\n$st');
      }
    }
    if (kIsWeb && entry.key != _adminGovernorCatalogLoaders.keys.last) {
      await Future<void>.delayed(const Duration(milliseconds: 80));
    }
  }
}

/// One coordinated Firestore bootstrap per auth state (guest vs each signed-in uid).
Future<void> bootstrapAppFirestoreOnce() async {
  final key = _bootstrapAuthKey();

  if (_bootstrapFuture != null) {
    await _bootstrapFuture!;
    if (_completedBootstrapKey == key) return;
  }

  if (_completedBootstrapKey == key) return;

  final future = _bootstrapAppFirestoreImpl(
    key: key,
    forceCatalog: _completedBootstrapKey != null && _completedBootstrapKey != key,
  );
  _bootstrapFuture = future;
  try {
    await future;
    _completedBootstrapKey = key;
  } finally {
    if (identical(_bootstrapFuture, future)) {
      _bootstrapFuture = null;
    }
  }
}

Future<void> _bootstrapAppFirestoreImpl({
  required String key,
  required bool forceCatalog,
}) async {
  await _ensureAuthTokenReady();

  if (FirebaseAuth.instance.currentUser != null) {
    final email = FirebaseAuth.instance.currentUser!.email ?? '';
    if (isKnownAdminEmail(email)) {
      try {
        await AdminAccountsService.applyAdminRoleIfRegistered();
        await persistLongTermStaffRoleClaims();
      } catch (e) {
        debugPrint('bootstrap permanent admin role: $e');
      }
    }
    await runFirestore(syncAccountAfterLogin);
    await refreshAuthRoleClaims();
  }

  if (!_publicCatalogLoaded || forceCatalog) {
    await loadPublicTourismCatalogFromFirestore(
      force: forceCatalog || !_publicCatalogLoaded,
    );
  }

  if (tourismIsGuestSession()) return;

  try {
    await loadUsersFromFirestore();
    if (kDebugMode) debugPrint('Firestore load users: ok');
  } catch (e, st) {
    debugPrint('Firestore load users failed: $e\n$st');
  }

  try {
    await loadAdminAccountsFromFirestore();
    if (kDebugMode) {
      debugPrint(
        'Firestore load admin_accounts: ${adminAccountsByDocId.length} docs',
      );
    }
  } catch (e, st) {
    debugPrint('Firestore load admin_accounts failed: $e\n$st');
  }

  try {
    await HomePersonalizationService.instance.refresh();
  } catch (e, st) {
    debugPrint('Home personalization refresh failed: $e\n$st');
  }

  if (kDebugMode) {
    final project = FirebaseFirestore.instance.app.options.projectId;
    debugPrint(
      'Firestore session loaded (project: $project, key: $key, '
      'spots: ${allSpots.length}, events: ${tourismEvents.length})',
    );
  }
}

/// Reloads tourism catalogs for the admin dashboard (after login or stale cache).
Future<void> reloadAdminDashboardCatalogs() async {
  await _ensureAuthTokenReady();
  if (FirebaseAuth.instance.currentUser != null) {
    try {
      await refreshAuthRoleClaims();
    } catch (e) {
      debugPrint('reloadAdminDashboardCatalogs claims: $e');
    }
  }
  try {
    // Spots first so the Tourist Spots tab is never empty while other catalogs load.
    await loadTouristSpotsFromFirestore();
    tourismCatalogRevision.value++;
    await loadAdminGovernorCatalogsFromFirestore();
    await loadMunicipalitiesFromFirestore();
  } catch (e, st) {
    debugPrint('reloadAdminDashboardCatalogs: $e\n$st');
  }
  if (!tourismIsGuestSession()) {
    try {
      await loadUsersFromFirestore();
    } catch (e) {
      debugPrint('reloadAdminDashboardCatalogs users: $e');
    }
  }
  tourismCatalogRevision.value++;
  if (kDebugMode) {
    debugPrint(
      'Admin catalogs: featured=${featuredSpots.length} spots=${allSpots.length} '
      'events=${tourismEvents.length} announcements=${tourismAnnouncements.length}',
    );
  }
}

/// Loads Firestore data for the current session (public catalogs + user profile).
Future<void> loadTourismDataForSession() async {
  await bootstrapAppFirestoreOnce();
}

/// Instant local cleanup used by logout so the login screen can open without
/// waiting on catalog reloads or personalization network calls.
void clearTourismSessionOnLogout() {
  // Mark guest bootstrap as done so logout does not force a full catalog reload.
  _completedBootstrapKey = '__guest__';
  _bootstrapFuture = null;
  HomePersonalizationService.instance.clearForLogout();
  SpotInteractionHistoryStore.instance.clearMemoryForLogout();
}

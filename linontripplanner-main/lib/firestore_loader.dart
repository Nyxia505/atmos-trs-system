import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart'
    show ValueNotifier, debugPrint, kDebugMode;

import 'services/firestore_errors.dart';
import 'services/firestore_gate.dart';
import 'services/public_firestore_read.dart';
import 'services/supabase_event_push.dart';
import 'services/supabase_image_library.dart'
    show applyCuratedTouristSpotImageUrls;
import 'package:shared_preferences/shared_preferences.dart';

import 'data.dart';
import 'municipality_bus_terminals.dart';
import 'config/supabase_config.dart';
import 'services/admin_accounts_service.dart';
import 'services/auth_role_claims.dart';
import 'services/auth_roles.dart';
import 'services/travel_history_profile.dart';
import 'trip_planner_utils.dart' show matchMunicipalityByLocalityHint;
import 'algorithms/collaborative_filtering.dart';
import 'algorithms/content_based_filtering.dart';

const String kTouristSpotsCollection = 'tourist_spots';
const String kMunicipalitiesCollection = 'municipalities';
const String kFeaturedSpotsCollection = 'featured_spots';
const String kEventsCollection = 'events';
const String _kCachedEventsPrefsKey = 'tourism_events_cache_v1';

Future<void> _persistEventsCache(List<TourismEvent> events) async {
  try {
    final sp = await SharedPreferences.getInstance();
    await sp.setString(
      _kCachedEventsPrefsKey,
      jsonEncode(events.map((e) => e.toJson()).toList()),
    );
  } catch (e) {
    debugPrint('persist events cache failed: $e');
  }
}

Future<List<TourismEvent>> _loadEventsCache() async {
  try {
    final sp = await SharedPreferences.getInstance();
    final raw = sp.getString(_kCachedEventsPrefsKey);
    if (raw == null || raw.isEmpty) return const [];
    final list = jsonDecode(raw);
    if (list is! List) return const [];
    return [
      for (final item in list)
        if (item is Map)
          TourismEvent.fromJson(Map<String, dynamic>.from(item)),
    ];
  } catch (e) {
    debugPrint('load events cache failed: $e');
    return const [];
  }
}

/// Bumped after [loadEventsFromFirestore] so Events / Notifications UIs can rebuild.
final ValueNotifier<int> tourismEventsRevision = ValueNotifier<int>(0);
const String kAnnouncementsCollection = 'announcements';
/// Tourist spot reviews (rating + optional comment) from the app.
const String kSpotRatingsCollection = 'spot_ratings';
/// Same collection as mobile/auth app: `fullName`, `email`, `role`, `firebaseUid`, …
const String kUsersCollection = 'users';
/// Registered tourists / visits (Governor portal table). Use plural to match
/// typical Firestore collection naming; `tourist` (singular) is also allowed in rules.
const String kTouristCollection = 'tourists';

/// One document per check-in / visit. Reference the tourist with any of:
/// `touristId`, `touristID`, `touristDocumentId` (matches [TouristRegistryEntry.docId]
/// or the business id on the `tourists` doc).
const String kTouristVisitsCollection = 'tourist_visits';
/// Public anonymized profiles for on-device collaborative filtering.
const String kRecommendationProfilesCollection = 'recommendation_profiles';

/// Builds a [TouristSpot] from one `tourist_spots` document.
TouristSpot? touristSpotFromFirestoreDoc(
  String docId,
  Map<String, dynamic> d,
) {
  final name = _str(d, 'name') ?? docId;
  if (name.isEmpty) return null;

  final rating = _double(d, 'rating');
  final lat = _doubleOrNull(d, 'latitude') ?? _doubleOrNull(d, 'lat');
  final lng = _doubleOrNull(d, 'longitude') ?? _doubleOrNull(d, 'lng');

  String location = '';
  for (final key in <String>[
    'location',
    'locationName',
    'location_name',
    'municipality',
    'municipalityName',
    'municipality_name',
  ]) {
    final v = _str(d, key);
    if (v != null && v.trim().isNotEmpty) {
      location = v.trim();
      break;
    }
  }

  return TouristSpot(
    name: name,
    priceRange: _str(d, 'priceRange') ?? _str(d, 'price_range') ?? '',
    imagePath: _touristSpotImagePathFromFirestore(d),
    location: location,
    rating: rating,
    description: _str(d, 'description') ?? '',
    type: _str(d, 'type') ?? 'spot',
    latitude: lat,
    longitude: lng,
    walkingDistanceMinutes: _intOrNull(
          d,
          'walkingDistanceMinutes',
        ) ??
        _intOrNull(d, 'walking_distance_minutes'),
    entranceFee: _str(d, 'entranceFee') ?? _str(d, 'entrance_fee') ?? '',
    foodAndDrinksPrice: _str(d, 'foodAndDrinksPrice') ??
        _str(d, 'food_and_drinks_price') ??
        '',
    otherSouvenirsPrice: _str(d, 'otherSouvenirsPrice') ??
        _str(d, 'other_souvenirs_price') ??
        '',
    firestoreDocId: docId,
    category: _str(d, 'category') ?? '',
    visitors: _intOrNull(d, 'visitors') ??
        _intOrNull(d, 'visitorCount') ??
        _intOrNull(d, 'visitor_count') ??
        0,
    ratingCount: _intOrNull(d, 'ratingCount') ??
        _intOrNull(d, 'rating_count') ??
        _intOrNull(d, 'ratingsCount') ??
        _intOrNull(d, 'numberOfRatings') ??
        _intOrNull(d, 'number_of_ratings') ??
        0,
    updatedAtMs: _timestampMillis(d, 'updatedAt') ??
        _timestampMillis(d, 'updated_at') ??
        0,
  );
}

/// Fetches documents from Firestore `tourist_spots` collection and fills [allSpots].
/// Safe to call multiple times; replaces existing spots each time.
Future<void> loadTouristSpotsFromFirestore() async {
  return runFirestore(() async {
  try {
  final snapshot =
      await fetchPublicFirestoreCollection(kTouristSpotsCollection);

  final List<TouristSpot> loaded = [];
  for (final doc in snapshot.docs) {
    final spot = touristSpotFromFirestoreDoc(doc.id, doc.data());
    if (spot != null) loaded.add(spot);
  }

  allSpots
    ..clear()
    ..addAll(loaded);
  // Lock curated files (Piduan Falls, Panaon Seaside, …) and drop duplicates.
  applyCuratedTouristSpotImageUrls();
  if (kDebugMode) {
    debugPrint('loadTouristSpotsFromFirestore: ${allSpots.length} spots');
  }
  } catch (e) {
    if (_isNonPermissionRecoverableFirestoreError(e)) {
      logRecoverableFirestoreLoad('loadTouristSpotsFromFirestore', e);
      return;
    }
    rethrow;
  }
  });
}

/// Name / short-name variants used when querying tourist spots for one LGU.
List<String> municipalityLocationQueryValues(Municipality municipality) {
  final out = <String>{};
  void add(String raw) {
    final t = raw.trim();
    if (t.isNotEmpty) out.add(t);
  }

  add(municipality.name);
  add(municipality.shortName);
  return out.toList(growable: false);
}

/// Loads tourist spots that belong to [municipality] via Firestore equality
/// queries on location / municipality fields (not by filtering a full in-memory
/// dump after the fact). Results are still verified with
/// [touristSpotBelongsToMunicipality] so unrelated matches are dropped.
Future<List<TouristSpot>> loadTouristSpotsForMunicipalityFromFirestore(
  Municipality municipality,
) async {
  final values = municipalityLocationQueryValues(municipality);
  if (values.isEmpty) return const [];

  const fields = <String>[
    'location',
    'locationName',
    'location_name',
    'municipality',
    'municipalityName',
    'municipality_name',
  ];

  final byId = <String, TouristSpot>{};
  for (final field in fields) {
    for (final value in values) {
      try {
        final snap = await fetchPublicFirestoreQuery(
          FirebaseFirestore.instance
              .collection(kTouristSpotsCollection)
              .where(field, isEqualTo: value),
        );
        for (final doc in snap.docs) {
          if (byId.containsKey(doc.id)) continue;
          final spot = touristSpotFromFirestoreDoc(doc.id, doc.data());
          if (spot == null) continue;
          if (touristSpotBelongsToMunicipality(spot, municipality) ||
              matchMunicipalityByLocalityHint(spot.location)?.name ==
                  municipality.name) {
            byId[doc.id] = spot;
          }
        }
      } on FirebaseException catch (e) {
        // Missing composite indexes / odd field types — try the next variant.
        debugPrint(
          'loadTouristSpotsForMunicipalityFromFirestore '
          '($field=$value): ${e.code}',
        );
      }
    }
  }

  final list = byId.values.toList()
    ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
  return list;
}

/// Deletes from Firestore: tourist spots with no picture, and duplicate spots (by name).
/// Keeps one spot per name (prefer the one with imagePath). Then reloads [allSpots].
/// Returns the number of documents deleted.
Future<int> deleteTouristSpotsWithNoPictureAndDuplicatesFromFirestore() async {
  final col = FirebaseFirestore.instance.collection(kTouristSpotsCollection);
  final snapshot = await col.get();

  /// For each name, keep the doc id we want to keep (prefer one with imagePath).
  final Map<String, String> keptByName = {};
  final Set<String> idsToDelete = {};

  for (final doc in snapshot.docs) {
    final d = doc.data();
    final name = (_str(d, 'name') ?? doc.id).trim();
    final imagePath = _touristSpotImagePathFromFirestore(d);
    final hasImage = imagePath.isNotEmpty;

    if (name.isEmpty) {
      idsToDelete.add(doc.id);
      continue;
    }

    final keptId = keptByName[name];
    if (keptId == null) {
      keptByName[name] = doc.id;
    } else {
      final keptDoc = snapshot.docs.firstWhere((x) => x.id == keptId);
      final keptHasImage =
          _touristSpotImagePathFromFirestore(keptDoc.data()).isNotEmpty;
      if (hasImage && !keptHasImage) {
        keptByName[name] = doc.id;
        idsToDelete.add(keptId);
      } else {
        idsToDelete.add(doc.id);
      }
    }
  }

  for (final name in keptByName.keys) {
    final docId = keptByName[name]!;
    final doc = snapshot.docs.firstWhere((d) => d.id == docId);
    final imagePath = _touristSpotImagePathFromFirestore(doc.data());
    if (imagePath.isEmpty) idsToDelete.add(docId);
  }

  for (final id in idsToDelete) {
    await col.doc(id).delete();
  }

  await loadTouristSpotsFromFirestore();
  return idsToDelete.length;
}

/// Slug from municipality name (same as admin dashboard and transportation fees).
String municipalitySlug(String name) => _slug(name);

/// Slug from municipality name (same as admin dashboard).
String _slug(String name) {
  return name
      .toLowerCase()
      .trim()
      .replaceAll(RegExp(r'[^a-z0-9\s]'), '')
      .replaceAll(RegExp(r'\s+'), '_');
}

String _municipalityKey(String name) {
  return name
      .toLowerCase()
      .trim()
      .replaceAll(RegExp(r'[\(\)]'), ' ')
      .replaceAll('provincial capital', ' ')
      .replaceAll('city', ' ')
      .replaceAll(RegExp(r'[^a-z0-9\s]'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
}

/// Loads Firestore `municipalities` and merges imagePath/description into [municipalities].
/// Matching is by slug (doc id). Keeps existing list order and names.
Future<void> loadMunicipalitiesFromFirestore() async {
  return runFirestore(() async {
  try {
  final snapshot =
      await fetchPublicFirestoreCollection(kMunicipalitiesCollection);

  for (final doc in snapshot.docs) {
    final d = doc.data();
    final slug = doc.id;
    final name = (_str(d, 'name') ?? '').trim();
    final shortName = (_str(d, 'shortName') ?? name).trim();
    final imagePath = (_str(d, 'imagePath') ?? _str(d, 'image_path') ?? '')
        .trim();
    final description = _str(d, 'description') ?? '';

    final docKey = _municipalityKey(name);
    final idx = municipalities.indexWhere((m) {
      if (_slug(m.name) == slug) return true;
      if (name.isNotEmpty && _municipalityKey(m.name) == docKey) return true;
      if (name.isNotEmpty && _municipalityKey(m.shortName) == docKey) {
        return true;
      }
      if (shortName.isNotEmpty &&
          _municipalityKey(m.name) == _municipalityKey(shortName)) {
        return true;
      }
      return false;
    });
    final divisionKind = (_str(d, 'divisionKind') ??
            _str(d, 'division_kind') ??
            _str(d, 'adminType') ??
            _str(d, 'admin_type') ??
            _str(d, 'type') ??
            '')
        .trim();

    final busTerminal =
        busTerminalFromFirestoreDoc(d) ??
        (idx >= 0
            ? defaultBusTerminalFor(municipalities[idx])
            : (name.isNotEmpty
                ? kDefaultMunicipalityBusTerminals[name]
                : null));

    if (idx >= 0) {
      final existing = municipalities[idx];
      municipalities[idx] = Municipality(
        name: existing.name,
        shortName: existing.shortName,
        imagePath: imagePath.isNotEmpty ? imagePath : existing.imagePath,
        description: description.isNotEmpty
            ? description
            : existing.description,
        spots: existing.spots,
        divisionKind:
            divisionKind.isNotEmpty ? divisionKind : existing.divisionKind,
        busTerminal: busTerminal ?? existing.busTerminal,
      );
    } else if (name.isNotEmpty) {
      municipalities.add(
        Municipality(
          name: name,
          shortName: shortName,
          imagePath: imagePath,
          description: description,
          spots: const [],
          divisionKind: divisionKind,
          busTerminal: busTerminal,
        ),
      );
    }
  }
  applyDefaultMunicipalityBusTerminals();
  } catch (e) {
    if (_isNonPermissionRecoverableFirestoreError(e)) {
      logRecoverableFirestoreLoad('loadMunicipalitiesFromFirestore', e);
      return;
    }
    rethrow;
  }
  });
}

/// Loads Firestore `featured_spots` into [featuredSpots].
Future<void> loadFeaturedSpotsFromFirestore() async {
  return runFirestore(() async {
  try {
  final snapshot =
      await fetchPublicFirestoreCollection(kFeaturedSpotsCollection);

  final loaded = <FeaturedSpot>[];
  final seenNames = <String>{};
  for (final doc in snapshot.docs) {
    final d = doc.data();
    final name = _str(d, 'name') ?? doc.id;
    if (name.isEmpty || !seenNames.add(name)) continue;
    loaded.add(
      FeaturedSpot(
        name: name,
        priceRange: _str(d, 'priceRange') ?? _str(d, 'price_range') ?? '',
        rating: _double(d, 'rating').clamp(0.0, 5.0),
        imagePath: _touristSpotImagePathFromFirestore(d),
      ),
    );
  }

  featuredSpots
    ..clear()
    ..addAll(loaded);
  } catch (e) {
    if (_isNonPermissionRecoverableFirestoreError(e)) {
      logRecoverableFirestoreLoad('loadFeaturedSpotsFromFirestore', e);
      return;
    }
    rethrow;
  }
  });
}

bool _isNonPermissionRecoverableFirestoreError(Object error) {
  final s = error.toString();
  if (s.contains('permission-denied')) return false;
  return isRecoverableFirestoreError(error);
}

String buildStableDocId(String name, String fallbackPrefix) {
  final slug = _slug(name);
  if (slug.isNotEmpty) return slug;
  return '${fallbackPrefix}_${DateTime.now().millisecondsSinceEpoch}';
}

Future<void> upsertFeaturedSpotToFirestore(
  FeaturedSpot spot, {
  String? oldName,
}) async {
  await ensurePermanentStaffRoleForCatalogWrite();
  final col = FirebaseFirestore.instance.collection(kFeaturedSpotsCollection);
  final docId = buildStableDocId(spot.name, 'featured');
  if (oldName != null &&
      oldName.trim().isNotEmpty &&
      oldName.trim() != spot.name.trim()) {
    final oldDocId = buildStableDocId(oldName, 'featured');
    await col.doc(oldDocId).delete().catchError((_) {});
  }
  await col.doc(docId).set({
    'name': spot.name,
    'priceRange': spot.priceRange,
    'rating': spot.rating.clamp(0.0, 5.0),
    'image_url': spot.imagePath,
    'imageUrl': spot.imagePath,
    'image': spot.imagePath,
    'imagePath': spot.imagePath,
    'updatedAt': FieldValue.serverTimestamp(),
  }, SetOptions(merge: true));
}

Future<void> deleteFeaturedSpotFromFirestoreByName(String name) async {
  await ensurePermanentStaffRoleForCatalogWrite();
  final docId = buildStableDocId(name, 'featured');
  await FirebaseFirestore.instance
      .collection(kFeaturedSpotsCollection)
      .doc(docId)
      .delete();
}

Future<void> upsertTouristSpotToFirestore(
  TouristSpot spot, {
  String? oldName,
}) async {
  await ensurePermanentStaffRoleForCatalogWrite();
  final col = FirebaseFirestore.instance.collection(kTouristSpotsCollection);
  final String docId;
  if (spot.firestoreDocId != null && spot.firestoreDocId!.trim().isNotEmpty) {
    docId = spot.firestoreDocId!.trim();
  } else {
    docId = buildStableDocId(spot.name, 'spot');
  }
  if (oldName != null &&
      oldName.trim().isNotEmpty &&
      oldName.trim() != spot.name.trim()) {
    final oldSlugId = buildStableDocId(oldName, 'spot');
    if (oldSlugId != docId) {
      await col.doc(oldSlugId).delete().catchError((_) {});
    }
  }
  await col.doc(docId).set({
    'name': spot.name,
    'priceRange': spot.priceRange,
    // App reads Supabase URL from `image_url` (not legacy Firebase `imagePath`).
    'image_url': spot.imagePath,
    'imageUrl': spot.imagePath,
    'image': spot.imagePath,
    'imagePath': spot.imagePath,
    'location': spot.location,
    'rating': spot.rating.clamp(0.0, 5.0),
    'description': spot.description,
    'type': spot.type,
    if (spot.latitude != null) 'latitude': spot.latitude,
    if (spot.longitude != null) 'longitude': spot.longitude,
    if (spot.walkingDistanceMinutes != null)
      'walkingDistanceMinutes': spot.walkingDistanceMinutes
    else
      'walkingDistanceMinutes': FieldValue.delete(),
    'entranceFee': spot.entranceFee,
    'foodAndDrinksPrice': spot.foodAndDrinksPrice,
    'otherSouvenirsPrice': spot.otherSouvenirsPrice,
    'transportationFee': FieldValue.delete(),
    'updatedAt': FieldValue.serverTimestamp(),
  }, SetOptions(merge: true));
}

Future<void> upsertMunicipalityToFirestore(
  Municipality municipality, {
  String? oldName,
}) async {
  await ensurePermanentStaffRoleForCatalogWrite();
  final col = FirebaseFirestore.instance.collection(kMunicipalitiesCollection);
  final docId = buildStableDocId(municipality.name, 'municipality');
  if (oldName != null &&
      oldName.trim().isNotEmpty &&
      oldName.trim() != municipality.name.trim()) {
    final oldDocId = buildStableDocId(oldName, 'municipality');
    await col.doc(oldDocId).delete().catchError((_) {});
  }
  final busPayload = busTerminalFirestorePayload(municipality.busTerminal);
  await col.doc(docId).set({
    'name': municipality.name,
    'shortName': municipality.shortName,
    'imagePath': municipality.imagePath,
    'description': municipality.description,
    if (municipality.divisionKind.trim().isNotEmpty)
      'divisionKind': municipality.divisionKind.trim(),
    if (busPayload != null) 'busTerminal': busPayload,
    'updatedAt': FieldValue.serverTimestamp(),
  }, SetOptions(merge: true));
}

String? _eventTitleFromDoc(Map<String, dynamic> d) {
  for (final key in ['title', 'name', 'eventTitle', 'event_title']) {
    final s = _str(d, key)?.trim();
    if (s != null && s.isNotEmpty) return s;
  }
  return null;
}

DateTime? _eventDateFromDoc(Map<String, dynamic> d) {
  for (final key in [
    'startAt',
    'start_at',
    'dateTime',
    'date_time',
    'date',
    'eventDate',
    'event_date',
    'scheduledAt',
    'scheduled_at',
  ]) {
    final v = d[key];
    if (v is Timestamp) return v.toDate();
    if (v is DateTime) return v;
    if (v is String && v.isNotEmpty) {
      final parsed = DateTime.tryParse(v);
      if (parsed != null) return parsed;
    }
  }
  final updated = d['updatedAt'];
  if (updated is Timestamp) return updated.toDate();
  return null;
}

/// Loads [tourismEvents] from Firestore `events`, newest first.
/// Keeps previously loaded events if the remote read fails or returns empty.
Future<void> loadEventsFromFirestore() async {
  return runFirestore(() async {
  Object? lastError;
  for (var attempt = 0; attempt < 3; attempt++) {
    try {
      if (attempt > 0) {
        await Future<void>.delayed(Duration(milliseconds: 500 * attempt));
      }
      final snapshot = await fetchPublicFirestoreCollection(kEventsCollection);

      final loaded = <TourismEvent>[];
      for (final doc in snapshot.docs) {
        final d = doc.data();
        final title = _eventTitleFromDoc(d);
        if (title == null) continue;
        final dt = _eventDateFromDoc(d) ?? DateTime.now();
        loaded.add(
          TourismEvent(
            id: doc.id,
            title: title,
            imagePath: _eventOrAnnouncementImagePathFromFirestore(d),
            venue: _str(d, 'venue') ?? '',
            municipality: _str(d, 'municipality') ?? '',
            dateTime: dt,
            eventType:
                _str(d, 'eventType') ?? _str(d, 'event_type') ?? 'General',
            description: _str(d, 'description') ?? '',
          ),
        );
      }
      loaded.sort((a, b) => b.dateTime.compareTo(a.dateTime));

      // Never wipe a good in-memory list with an empty/failed catalog read.
      if (loaded.isEmpty && tourismEvents.isNotEmpty) {
        if (kDebugMode) {
          debugPrint(
            'loadEventsFromFirestore: remote empty (${snapshot.docs.length} docs) — '
            'keeping ${tourismEvents.length} cached events',
          );
        }
        return;
      }

      if (loaded.isEmpty) {
        final cached = await _loadEventsCache();
        if (cached.isNotEmpty) {
          tourismEvents
            ..clear()
            ..addAll(cached);
          tourismEventsRevision.value++;
          if (kDebugMode) {
            debugPrint(
              'loadEventsFromFirestore: remote empty — restored '
              '${cached.length} events from disk cache',
            );
          }
          return;
        }
      }

      tourismEvents
        ..clear()
        ..addAll(loaded);
      tourismEventsRevision.value++;
      if (loaded.isNotEmpty) {
        unawaited(_persistEventsCache(loaded));
      }
      if (kDebugMode) {
        debugPrint(
          'loadEventsFromFirestore: ${snapshot.docs.length} docs → '
          '${loaded.length} events',
        );
      }
      return;
    } catch (e) {
      lastError = e;
      final denied = e.toString().contains('permission-denied');
      if (denied && attempt < 2) {
        if (kDebugMode) {
          debugPrint(
            'loadEventsFromFirestore: permission-denied, retry '
            '${attempt + 1}/3',
          );
        }
        continue;
      }
      if (_isNonPermissionRecoverableFirestoreError(e) || denied) {
        logRecoverableFirestoreLoad('loadEventsFromFirestore', e);
        if (tourismEvents.isEmpty) {
          final cached = await _loadEventsCache();
          if (cached.isNotEmpty) {
            tourismEvents
              ..clear()
              ..addAll(cached);
            tourismEventsRevision.value++;
            if (kDebugMode) {
              debugPrint(
                'loadEventsFromFirestore: restored ${cached.length} events '
                'from disk after error',
              );
            }
          }
        } else if (kDebugMode) {
          debugPrint(
            'loadEventsFromFirestore: keeping ${tourismEvents.length} cached events '
            'after load error',
          );
        }
        return;
      }
      rethrow;
    }
  }
  if (lastError != null) {
    logRecoverableFirestoreLoad('loadEventsFromFirestore', lastError);
    if (tourismEvents.isEmpty) {
      final cached = await _loadEventsCache();
      if (cached.isNotEmpty) {
        tourismEvents
          ..clear()
          ..addAll(cached);
        tourismEventsRevision.value++;
      }
    }
  }
  });
}

Future<void> upsertTourismEventToFirestore(TourismEvent e) async {
  await ensurePermanentStaffRoleForCatalogWrite();
  final col = FirebaseFirestore.instance.collection(kEventsCollection);
  final isNew = e.id.isEmpty;
  final docRef = isNew ? col.doc() : col.doc(e.id);
  final imageUrl = e.imagePath.trim();
  await docRef.set({
    'title': e.title,
    // Binary lives in Supabase Storage; Firestore only stores the public URL.
    'imagePath': imageUrl,
    'image_url': imageUrl,
    'imageUrl': imageUrl,
    'venue': e.venue,
    'municipality': e.municipality,
    'eventType': e.eventType,
    'description': e.description,
    'startAt': Timestamp.fromDate(e.dateTime),
    'updatedAt': FieldValue.serverTimestamp(),
  }, SetOptions(merge: true));

  // Spark-safe push: Supabase Edge Function → FCM topic `tourism_events`.
  // (Firebase Cloud Functions require Blaze; this path does not.)
  if (isNew) {
    await broadcastTourismEventPushViaSupabase(
      eventId: docRef.id,
      title: e.title,
      municipality: e.municipality,
      venue: e.venue,
      description: e.description,
      dateTime: e.dateTime,
    );
  }
}

Future<void> deleteTourismEventFromFirestore(String id) async {
  await ensurePermanentStaffRoleForCatalogWrite();
  await FirebaseFirestore.instance
      .collection(kEventsCollection)
      .doc(id)
      .delete();
}

/// Loads [tourismAnnouncements] from Firestore `announcements`, newest first.
Future<void> loadAnnouncementsFromFirestore() async {
  return runFirestore(() async {
  try {
  final snapshot =
      await fetchPublicFirestoreCollection(kAnnouncementsCollection);

  final loaded = <TourismAnnouncement>[];
  for (final doc in snapshot.docs) {
    final d = doc.data();
    final title = _str(d, 'title') ?? '';
    if (title.isEmpty) continue;
    DateTime published = DateTime.now();
    final p = d['publishedAt'] ?? d['published_at'] ?? d['createdAt'];
    if (p is Timestamp) {
      published = p.toDate();
    }
    loaded.add(
      TourismAnnouncement(
        id: doc.id,
        title: title,
        body: _str(d, 'body') ?? _str(d, 'message') ?? '',
        imagePath: _eventOrAnnouncementImagePathFromFirestore(d),
        publishedAt: published,
      ),
    );
  }
  loaded.sort((a, b) => b.publishedAt.compareTo(a.publishedAt));
  tourismAnnouncements
    ..clear()
    ..addAll(loaded);
  } catch (e) {
    if (_isNonPermissionRecoverableFirestoreError(e)) {
      logRecoverableFirestoreLoad('loadAnnouncementsFromFirestore', e);
      return;
    }
    rethrow;
  }
  });
}

Future<void> upsertTourismAnnouncementToFirestore(TourismAnnouncement a) async {
  await ensurePermanentStaffRoleForCatalogWrite();
  final col = FirebaseFirestore.instance.collection(kAnnouncementsCollection);
  final docRef = a.id.isEmpty ? col.doc() : col.doc(a.id);
  final imageUrl = a.imagePath.trim();
  await docRef.set({
    'title': a.title,
    'body': a.body,
    // Binary lives in Supabase Storage; Firestore only stores the public URL.
    'imagePath': imageUrl,
    'image_url': imageUrl,
    'imageUrl': imageUrl,
    'publishedAt': Timestamp.fromDate(a.publishedAt),
    'updatedAt': FieldValue.serverTimestamp(),
  }, SetOptions(merge: true));
}

Future<void> deleteTourismAnnouncementFromFirestore(String id) async {
  await ensurePermanentStaffRoleForCatalogWrite();
  await FirebaseFirestore.instance
      .collection(kAnnouncementsCollection)
      .doc(id)
      .delete();
}

/// Loads spot reviews from Firestore `spot_ratings`.
Future<List<SpotRating>> fetchSpotRatingsFromFirestore() async {
  return runFirestore(() async {
    try {
      final snapshot =
          await fetchPublicFirestoreCollection(kSpotRatingsCollection);
      final loaded = <SpotRating>[];
      for (final doc in snapshot.docs) {
        final d = doc.data();
        final spotName = (_str(d, 'spotName') ?? _str(d, 'spot_name') ?? '')
            .trim();
        if (spotName.isEmpty) continue;
        DateTime? created;
        final rawCreated = d['createdAt'] ?? d['created_at'];
        if (rawCreated is Timestamp) {
          created = rawCreated.toDate();
        } else if (rawCreated is String) {
          created = DateTime.tryParse(rawCreated);
        }
        loaded.add(
          SpotRating(
            id: doc.id,
            userName: (_str(d, 'userName') ?? _str(d, 'user_name') ?? 'Traveler')
                .trim(),
            spotName: spotName,
            rating: _double(d, 'rating').clamp(0.0, 5.0),
            description: (_str(d, 'description') ??
                    _str(d, 'comment') ??
                    _str(d, 'body') ??
                    '')
                .trim(),
            userId: (_str(d, 'userId') ??
                    _str(d, 'user_id') ??
                    _str(d, 'firebaseUid') ??
                    '')
                .trim(),
            profilePhotoPath: (_str(d, 'profilePhotoPath') ??
                    _str(d, 'profile_photo_path') ??
                    _str(d, 'photoURL') ??
                    '')
                .trim(),
            createdAt: created,
          ),
        );
      }
      return loaded;
    } catch (e) {
      logRecoverableFirestoreLoad('fetchSpotRatingsFromFirestore', e);
      return const <SpotRating>[];
    }
  });
}

/// Writes a tourist rating + optional comment to Firestore `spot_ratings`.
/// Returns the document id.
Future<String> upsertSpotRatingToFirestore(SpotRating rating) async {
  return runFirestore(() async {
    final col = FirebaseFirestore.instance.collection(kSpotRatingsCollection);
    final docRef =
        rating.id.trim().isEmpty ? col.doc() : col.doc(rating.id.trim());
    final uid = FirebaseAuth.instance.currentUser?.uid ?? rating.userId;
    await docRef.set({
      'userName': rating.userName,
      'spotName': rating.spotName,
      'rating': rating.rating.clamp(0.0, 5.0),
      'description': rating.description,
      'comment': rating.description,
      'userId': uid,
      'firebaseUid': uid,
      'profilePhotoPath': rating.profilePhotoPath,
      'createdAt': rating.createdAt != null
          ? Timestamp.fromDate(rating.createdAt!)
          : FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
    return docRef.id;
  });
}

/// Reads a profile image URL from a Firestore user/tourist document (incl. nested fields).
String profilePhotoSourceFromFirestoreMap(Map<String, dynamic> d) {
  final flat = _touristDocFlattened(d);
  const keys = <String>[
    'photoURL',
    'photoUrl',
    'profilePhotoUrl',
    'profileImageUrl',
    'profilePhoto',
    'profileImage',
    'profile_photo_url',
    'facePhotoUrl',
    'face_photo_url',
    'avatarUrl',
    'imageUrl',
    'picture',
  ];
  for (final k in keys) {
    final v = _str(flat, k);
    if (v != null && v.trim().isNotEmpty) return v.trim();
  }
  return '';
}

/// JPEG/PNG bytes stored inline on a tourist/user doc (`profileImageBase64`).
Uint8List? profileImageBytesFromFirestoreMap(Map<String, dynamic>? data) {
  if (data == null) return null;
  final flat = _touristDocFlattened(data);
  const keys = <String>[
    'profileImageBase64',
    'profile_image_base64',
    'facePhotoBase64',
    'face_photo_base64',
    'photoBase64',
    'imageBase64',
  ];
  for (final k in keys) {
    final v = flat[k];
    if (v is! String) continue;
    final decoded = _decodeProfileImageBase64(v);
    if (decoded != null && decoded.isNotEmpty) return decoded;
  }
  return null;
}

Uint8List? _decodeProfileImageBase64(String raw) {
  var s = raw.trim();
  if (s.isEmpty) return null;
  if (s.startsWith('data:image')) {
    final comma = s.indexOf(',');
    if (comma >= 0) s = s.substring(comma + 1);
  }
  try {
    final bytes = base64Decode(s);
    return bytes.isEmpty ? null : bytes;
  } catch (_) {
    return null;
  }
}

/// `tourists/{authUid}` or any doc whose `firebaseUid` matches [firebaseUid].
Future<Map<String, dynamic>?> fetchTouristFirestoreDataForFirebaseUid(
  String firebaseUid,
) async {
  final id = firebaseUid.trim();
  if (id.isEmpty) return null;

  try {
    final direct = await FirebaseFirestore.instance
        .collection(kTouristCollection)
        .doc(id)
        .get();
    if (direct.exists) return direct.data();
  } catch (_) {}

  try {
    final byField = await FirebaseFirestore.instance
        .collection(kTouristCollection)
        .where('firebaseUid', isEqualTo: id)
        .limit(1)
        .get();
    if (byField.docs.isNotEmpty) return byField.docs.first.data();
  } catch (_) {}

  return null;
}

/// Loads [users] for the signed-in account (or all users for staff dashboards).
/// Tourists may only read `users/{theirUid}` per security rules — not the whole collection.
Future<void> loadUsersFromFirestore() async {
  return runFirestore(() async {
  final auth = FirebaseAuth.instance.currentUser;
  if (auth == null) {
    users.clear();
    return;
  }

  final col = FirebaseFirestore.instance.collection(kUsersCollection);
  final loaded = <AppUser>[];

  void addFromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data();
    if (d == null) return;
    final fullName = _str(d, 'fullName') ?? _str(d, 'name') ?? '';
    final email = _str(d, 'email') ?? '';
    if (fullName.isEmpty && email.isEmpty) return;
    final uid = _str(d, 'firebaseUid') ?? '';
    loaded.add(
      AppUser(
        id: doc.id,
        name: fullName.isNotEmpty ? fullName : email,
        email: email,
        role: _str(d, 'role') ?? 'user',
        profilePhotoPath: profilePhotoSourceFromFirestoreMap(d),
        profilePhotoLookupId: uid.isNotEmpty ? uid : doc.id,
      ),
    );
  }

  final ownDoc = await col.doc(auth.uid).get();
  if (ownDoc.exists) {
    addFromDoc(ownDoc);
  }

  if (loaded.isNotEmpty && loaded.first.profilePhotoPath.trim().isEmpty) {
    try {
      final touristData = await fetchTouristFirestoreDataForFirebaseUid(auth.uid);
      if (touristData != null) {
        var photo = profilePhotoSourceFromFirestoreMap(touristData);
        if (photo.isEmpty &&
            profileImageBytesFromFirestoreMap(touristData) != null) {
          photo = 'firestore-base64-profile';
        }
        if (photo.isNotEmpty) {
          final u = loaded.first;
          loaded[0] = AppUser(
            id: u.id,
            name: u.name,
            email: u.email,
            role: u.role,
            profilePhotoPath: photo,
            profilePhotoLookupId: u.profilePhotoLookupId,
          );
        }
      }
    } catch (_) {}
  }

  final role = loaded.isEmpty ? '' : AppRole.fromString(loaded.first.role);
  final staff = role == AppRole.admin || role == AppRole.municipalManager;
  if (staff) {
    final snapshot = await col.get();
    loaded.clear();
    for (final doc in snapshot.docs) {
      addFromDoc(doc);
    }
  }

  loaded.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
  users
    ..clear()
    ..addAll(loaded);
  });
}

/// Ensures `users/{authUid}` exists and links any existing `tourists` / `users`
/// record (by uid or email) after sign-in.
Future<void> ensureCurrentUserProfileInFirestore() async {
  await syncAccountAfterLogin();
}

/// After Firebase Auth sign-in, link Firestore `tourists` / `users` docs and
/// refresh the in-app profile so returning users can open the home screen.
Future<void> syncAccountAfterLogin() async {
  final auth = FirebaseAuth.instance.currentUser;
  if (auth == null) return;

  final uid = auth.uid;
  final email = (auth.email ?? '').trim();
  Map<String, dynamic>? touristData;

  touristData = await fetchTouristFirestoreDataForFirebaseUid(uid);

  final userRef =
      FirebaseFirestore.instance.collection(kUsersCollection).doc(uid);
  final userSnap = await userRef.get();
  var existingUser = userSnap.data();

  final selfRole = AppRole.fromString(_str(existingUser, 'role'));
  final isStaff =
      selfRole == AppRole.admin || selfRole == AppRole.municipalManager;

  // Collection queries by email are staff-only; tourists use `/{uid}` docs only.
  if (touristData == null && email.isNotEmpty && isStaff) {
    try {
      final byEmail = await FirebaseFirestore.instance
          .collection(kTouristCollection)
          .where('email', isEqualTo: email)
          .limit(1)
          .get();
      if (byEmail.docs.isNotEmpty) {
        final merged = byEmail.docs.first.data();
        touristData = merged;
        await FirebaseFirestore.instance
            .collection(kTouristCollection)
            .doc(uid)
            .set(
          {
            ...merged,
            'firebaseUid': uid,
            'touristID': uid,
            'touristId': uid,
            'email': email,
            'updatedAt': FieldValue.serverTimestamp(),
          },
          SetOptions(merge: true),
        );
      }
    } catch (_) {}
  }

  if (existingUser == null && email.isNotEmpty && isStaff) {
    try {
      final usersByEmail = await FirebaseFirestore.instance
          .collection(kUsersCollection)
          .where('email', isEqualTo: email)
          .limit(1)
          .get();
      if (usersByEmail.docs.isNotEmpty) {
        existingUser = usersByEmail.docs.first.data();
      }
    } catch (_) {}
  }

  final rolePermanent = existingUser?['rolePermanent'] == true;
  final priorRole = _str(existingUser, 'role');

  var role = AppRole.tourist.firestoreValue;
  if (email.isNotEmpty) {
    final adminAccount = await AdminAccountsService.fetchForEmail(email);
    if (adminAccount != null) {
      role = AppRole.admin.firestoreValue;
    }
  }
  if (rolePermanent &&
      priorRole != null &&
      priorRole.trim().isNotEmpty) {
    role = AppRole.fromString(priorRole).firestoreValue;
  } else if (priorRole != null &&
      priorRole.trim().isNotEmpty &&
      role != AppRole.admin.firestoreValue) {
    role = AppRole.fromString(priorRole).firestoreValue;
  }

  final resolvedRole = AppRole.fromString(role);
  final permanentRole = resolvedRole == AppRole.admin ||
      resolvedRole == AppRole.municipalManager ||
      (email.isNotEmpty && await AdminAccountsService.fetchForEmail(email) != null);

  final fullName = _str(touristData, 'fullName') ??
      _str(touristData, 'name') ??
      _str(existingUser, 'fullName') ??
      _str(existingUser, 'name') ??
      auth.displayName ??
      'Guest';

  if (fullName.isNotEmpty &&
      fullName != 'Guest' &&
      auth.displayName != fullName) {
    await auth.updateDisplayName(fullName);
  }

  var profilePhotoUrl = profilePhotoSourceFromFirestoreMap(touristData ?? {});
  if (profilePhotoUrl.isEmpty) {
    profilePhotoUrl = profilePhotoSourceFromFirestoreMap(existingUser ?? {});
  }
  if (profilePhotoUrl.isEmpty) {
    profilePhotoUrl = auth.photoURL?.trim() ?? '';
  }

  if (profilePhotoUrl.trim().isEmpty) {
    profilePhotoUrl = await _discoverStorageProfilePhoto(uid) ?? '';
  }
  if (profilePhotoUrl.trim().isNotEmpty &&
      (auth.photoURL ?? '').trim() != profilePhotoUrl.trim()) {
    try {
      await auth.updatePhotoURL(profilePhotoUrl.trim());
    } catch (_) {}
  }

  await userRef.set({
    'fullName': fullName,
    'name': fullName,
    'email': email.isNotEmpty ? email : (_str(existingUser, 'email') ?? ''),
    'role': role,
    if (permanentRole) 'rolePermanent': true,
    'firebaseUid': uid,
    'updatedAt': FieldValue.serverTimestamp(),
    if (profilePhotoUrl.trim().isNotEmpty) ...{
      'profilePhotoUrl': profilePhotoUrl.trim(),
      'photoURL': profilePhotoUrl.trim(),
      'profilePhotoPending': false,
    },
    if (_str(touristData, 'phone') != null) 'phone': _str(touristData, 'phone'),
    if (!userSnap.exists) 'createdAt': FieldValue.serverTimestamp(),
    if (!userSnap.exists) 'isVerified': false,
  }, SetOptions(merge: true));
  if (permanentRole) {
    await persistLongTermStaffRoleClaims();
  } else if (resolvedRole == AppRole.admin ||
      resolvedRole == AppRole.municipalManager) {
    await userRef.set(
      {'rolePermanent': true},
      SetOptions(merge: true),
    );
    await persistLongTermStaffRoleClaims();
  } else {
    await refreshAuthRoleClaims();
  }
}

Future<String?> _discoverStorageProfilePhoto(String uid) async {
  if (uid.trim().isEmpty) return null;
  final paths = [
    'user_profiles/$uid/face_photo.jpg',
    'user_profiles/$uid/face_photo.jpeg',
    'profile_photos/$uid.jpg',
    'profile_photos/$uid.jpeg',
  ];
  for (final path in paths) {
    try {
      return await FirebaseStorage.instance.ref(path).getDownloadURL();
    } catch (_) {}
  }
  return null;
}

const Map<String, String> _transportModeToInterest = {
  'Motorcycle': 'Adventure',
  'Public Transport': 'Culture',
  'Car': 'Food',
};

/// Builds `travelHistory` list from registration destination fields.
List<String> registrationTravelHistoryFromMap(Map<String, dynamic> raw) {
  final flat = _touristDocFlattened(raw);
  final fromList = flat['travelHistory'] ?? flat['travel_history'];
  if (fromList is List) {
    final out = <String>[];
    for (final item in fromList) {
      final s = item is String ? item.trim() : item?.toString().trim() ?? '';
      if (s.isNotEmpty && !out.contains(s)) out.add(s);
    }
    if (out.isNotEmpty) return out;
  }
  final out = <String>[];
  for (final key in const [
    'lastDestination1',
    'lastDestination2',
    'lastDestination3',
  ]) {
    final s = (_str(flat, key) ?? '').trim();
    if (s.isNotEmpty && !out.contains(s)) out.add(s);
  }
  return out;
}

void _applyVisitorTypeInterests(String? visitorType, Set<String> interestTags) {
  final t = (visitorType ?? '').toLowerCase();
  if (t.isEmpty) return;
  if (t.contains('foreign') || t.contains('international')) {
    interestTags.addAll(['Culture', 'Historical Places', 'Beaches']);
  } else if (t.contains('local') || t.contains('domestic')) {
    interestTags.addAll(['Food', 'Culture', 'Nature']);
  }
}

/// Reads travel history from Firestore `tourists/{uid}` (saved at registration).
Future<TravelHistoryProfile> fetchTravelHistoryProfile(String uid) async {
  final interestTags = <String>{};
  final interestWeights = <String, double>{};
  final visitedSpotNameKeys = <String>{};
  final visitedMunicipalityNames = <String>{};
  final pastDestinations = <String>[];

  void addDestination(String? raw) {
    final hint = (raw ?? '').trim();
    if (hint.isEmpty) return;
    if (!pastDestinations.contains(hint)) pastDestinations.add(hint);

    interestTags.addAll(ContentBasedFiltering.interestsFromDestinationText(hint));

    final spot = findTouristSpotByNameFuzzy(hint);
    if (spot != null) {
      visitedSpotNameKeys.add(normalizeTourismNameKey(spot.name));
      interestTags.addAll(ContentBasedFiltering.spotInterests(spot));
    }

    final m = matchMunicipalityByLocalityHint(hint);
    if (m != null) {
      visitedMunicipalityNames.add(m.name);
      for (final s in allSpots.where((x) => touristSpotBelongsToMunicipality(x, m))) {
        interestTags.addAll(ContentBasedFiltering.spotInterests(s));
      }
    }
  }

  final touristSnap = await FirebaseFirestore.instance
      .collection(kTouristCollection)
      .doc(uid)
      .get();
  if (!touristSnap.exists) {
    return const TravelHistoryProfile();
  }

  final flat = _touristDocFlattened(touristSnap.data() ?? {});
  for (final dest in registrationTravelHistoryFromMap(touristSnap.data() ?? {})) {
    addDestination(dest);
  }

  final transport = _str(flat, 'transportMode') ?? _str(flat, 'transport_mode');
  if (transport != null) {
    final tag = _transportModeToInterest[transport.trim()];
    if (tag != null) interestTags.add(tag);
  }

  _applyVisitorTypeInterests(_str(flat, 'visitorType'), interestTags);

  for (final tag in interestTags) {
    interestWeights[tag] = (interestWeights[tag] ?? 0) + 1.0;
  }

  return TravelHistoryProfile(
    pastDestinations: pastDestinations,
    interestTags: interestTags,
    interestWeights: interestWeights,
    visitedSpotNameKeys: visitedSpotNameKeys,
    visitedMunicipalityNames: visitedMunicipalityNames,
  );
}

/// Maps [TravelHistoryProfile] to user–item and tag vectors for collaborative filtering.
({Map<String, double> items, Map<String, double> tags}) travelHistoryToCfVectors(
  TravelHistoryProfile profile,
) {
  final items = <String, double>{
    for (final k in profile.visitedSpotNameKeys) k: 1.0,
  };
  for (final dest in profile.pastDestinations) {
    final spot = findTouristSpotByNameFuzzy(dest);
    if (spot != null) {
      items[normalizeTourismNameKey(spot.name)] = 0.85;
    }
  }
  final tags = <String, double>{
    for (final t in profile.interestTags)
      t: profile.interestWeights[t] ?? 1.0,
  };
  return (items: items, tags: tags);
}

/// Publishes anonymized travel signals so peers can power collaborative filtering.
Future<void> saveRecommendationProfileForCollaborativeFiltering({
  required String uid,
  required TravelHistoryProfile profile,
}) async {
  if (!profile.hasSignals) return;
  final vectors = travelHistoryToCfVectors(profile);
  await FirebaseFirestore.instance
      .collection(kRecommendationProfilesCollection)
      .doc(uid)
      .set({
    'likedSpotKeys': vectors.items.keys.toList(),
    'itemScores': vectors.items,
    'interestTags': vectors.tags.keys.toList(),
    'tagScores': vectors.tags,
    'destinationHints': profile.pastDestinations,
    'updatedAt': FieldValue.serverTimestamp(),
  }, SetOptions(merge: true));
}

/// Loads peer profiles for collaborative filtering (excludes [excludeUid]).
Future<List<CollaborativeUserProfile>> loadCollaborativePeerProfiles({
  required String excludeUid,
  int limit = 200,
}) async {
  final snap = await FirebaseFirestore.instance
      .collection(kRecommendationProfilesCollection)
      .limit(limit)
      .get();

  final peers = <CollaborativeUserProfile>[];
  for (final doc in snap.docs) {
    if (doc.id == excludeUid) continue;
    final d = doc.data();
    final itemScores = <String, double>{};
    final rawItems = d['itemScores'];
    if (rawItems is Map) {
      for (final e in rawItems.entries) {
        final k = e.key.toString().trim();
        if (k.isEmpty) continue;
        final v = e.value;
        itemScores[k] = v is num ? v.toDouble() : 1.0;
      }
    } else {
      final keys = d['likedSpotKeys'];
      if (keys is List) {
        for (final k in keys) {
          final s = k.toString().trim();
          if (s.isNotEmpty) itemScores[s] = 1.0;
        }
      }
    }

    final tagScores = <String, double>{};
    final rawTags = d['tagScores'];
    if (rawTags is Map) {
      for (final e in rawTags.entries) {
        final k = e.key.toString().trim();
        if (k.isEmpty) continue;
        final v = e.value;
        tagScores[k] = v is num ? v.toDouble() : 1.0;
      }
    } else {
      final tags = d['interestTags'];
      if (tags is List) {
        for (final t in tags) {
          final s = t.toString().trim();
          if (s.isNotEmpty) tagScores[s] = 1.0;
        }
      }
    }

    if (itemScores.isEmpty && tagScores.isEmpty) continue;
    peers.add(
      CollaborativeUserProfile(
        userId: doc.id,
        itemScores: itemScores,
        tagScores: tagScores,
      ),
    );
  }
  return peers;
}

/// Persists tourist self‑registration questionnaire fields on `users/{uid}` (merge).
Future<void> saveExtendedUserRegistration({
  required String uid,
  required String fullName,
  required String email,
  String? phone,
  String? profilePhotoUrl,
  required Map<String, dynamic> questionnaire,
}) async {
  final docRef =
      FirebaseFirestore.instance.collection(kUsersCollection).doc(uid);
  final snap = await docRef.get();
  final existing = snap.data();
  var role = AppRole.tourist.firestoreValue;
  if (existing != null) {
    final prior = _str(existing, 'role');
    if (prior != null && prior.trim().isNotEmpty) {
      role = AppRole.fromString(prior).firestoreValue;
    }
  }

  final data = <String, dynamic>{
    'fullName': fullName,
    'name': fullName,
    'email': email,
    'firebaseUid': uid,
    'role': role,
    'updatedAt': FieldValue.serverTimestamp(),
    if (phone != null && phone.trim().isNotEmpty) 'phone': phone.trim(),
    if (profilePhotoUrl != null && profilePhotoUrl.trim().isNotEmpty)
      'profilePhotoUrl': profilePhotoUrl.trim(),
    for (final e in questionnaire.entries)
      if (e.value != null) e.key: e.value,
  };

  await docRef.set(data, SetOptions(merge: true));
  await refreshAuthRoleClaims();
}

/// Saves a new tourist self-registration to `tourists/{uid}` (Governor registry).
Future<void> saveTouristRegistrationToFirestore({
  required String uid,
  required String fullName,
  required String email,
  String? phone,
  String? profilePhotoUrl,
  required Map<String, dynamic> registration,
}) async {
  final now = DateTime.now();
  final docRef =
      FirebaseFirestore.instance.collection(kTouristCollection).doc(uid);

  final dest1 = (registration['lastDestination1'] as String?)?.trim() ?? '';
  final nationality = (registration['nationality'] as String?)?.trim() ?? '';
  final visitorType = (registration['visitorType'] as String?)?.trim() ?? '';
  final origin = dest1.isNotEmpty
      ? dest1
      : (nationality.isNotEmpty ? nationality : visitorType);

  final travelHistory = registrationTravelHistoryFromMap(registration);

  final data = <String, dynamic>{
    'fullName': fullName,
    'name': fullName,
    'email': email,
    'firebaseUid': uid,
    'touristID': uid,
    'touristId': uid,
    'registeredAt': FieldValue.serverTimestamp(),
    'createdAt': FieldValue.serverTimestamp(),
    'updatedAt': FieldValue.serverTimestamp(),
    'date': _registryDateYmd(now),
    'time': _registryTime12h(now),
    'visits': 1,
    if (origin.isNotEmpty) 'origin': origin,
    if (travelHistory.isNotEmpty) 'travelHistory': travelHistory,
    if (phone != null && phone.trim().isNotEmpty) 'phone': phone.trim(),
    if (profilePhotoUrl != null && profilePhotoUrl.trim().isNotEmpty)
      'profilePhotoUrl': profilePhotoUrl.trim(),
    for (final e in registration.entries)
      if (e.value != null) e.key: e.value,
  };

  await docRef.set(data, SetOptions(merge: true));
  await refreshAuthRoleClaims();
}

Future<void> upsertAppUserToFirestore(AppUser u) async {
  final col = FirebaseFirestore.instance.collection(kUsersCollection);
  final docRef = u.id.isEmpty ? col.doc() : col.doc(u.id);
  final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
  final data = <String, dynamic>{
    'fullName': u.name,
    'name': u.name,
    'email': u.email,
    'role': AppRole.fromString(u.role).firestoreValue,
    'rolePermanent': true,
    'updatedAt': FieldValue.serverTimestamp(),
  };
  if (uid.isNotEmpty && (u.profilePhotoLookupId == uid || u.id == uid)) {
    data['firebaseUid'] = uid;
  } else if (u.profilePhotoLookupId.isNotEmpty) {
    data['firebaseUid'] = u.profilePhotoLookupId;
  }
  if (u.id.isEmpty) {
    data['createdAt'] = FieldValue.serverTimestamp();
    data['isVerified'] = false;
  }
  await docRef.set(data, SetOptions(merge: true));
  await refreshAuthRoleClaims();
}

Future<void> deleteAppUserFromFirestore(String id) async {
  if (id.isEmpty) return;
  await FirebaseFirestore.instance.collection(kUsersCollection).doc(id).delete();
}

String _registryDateYmd(DateTime dt) {
  final y = dt.year.toString().padLeft(4, '0');
  final m = dt.month.toString().padLeft(2, '0');
  final day = dt.day.toString().padLeft(2, '0');
  return '$y-$m-$day';
}

String _registryTime12h(DateTime dt) {
  var hour12 = dt.hour % 12;
  if (hour12 == 0) hour12 = 12;
  final mm = dt.minute.toString().padLeft(2, '0');
  final ss = dt.second.toString().padLeft(2, '0');
  final period = dt.hour >= 12 ? 'PM' : 'AM';
  return '$hour12:$mm:$ss $period';
}

DateTime? _timestampLikeToDateTime(dynamic v) {
  if (v is Timestamp) return v.toDate();
  if (v is String) return DateTime.tryParse(v);
  return null;
}

/// Reads the Supabase photo URL from Firestore `image_url` / `imageUrl` / `image`.
/// Never uses legacy Firebase `imagePath` — that field is a different storage host.
String _touristSpotImagePathFromFirestore(Map<String, dynamic> d) {
  for (final key in const [
    'image_url',
    'imageUrl',
    'image',
    'supabaseImageUrl',
    'supabase_image_url',
  ]) {
    final raw = _str(d, key)?.trim() ?? '';
    if (raw.isEmpty) continue;
    if (SupabaseConfig.isSupabaseStorageUrl(raw) ||
        raw.startsWith('http://') ||
        raw.startsWith('https://')) {
      return raw;
    }
    // Relative object path under the tourist-images bucket.
    if (!raw.contains(':\\') && !raw.startsWith('/')) {
      return SupabaseConfig.publicObjectUrl(
        SupabaseConfig.photoLibraryBucket,
        raw,
      );
    }
  }
  return '';
}

/// Same preference order for events / announcements (Supabase URL first).
String _eventOrAnnouncementImagePathFromFirestore(Map<String, dynamic> d) =>
    _touristSpotImagePathFromFirestore(d);

/// First non-empty string among [keys] (trimmed). Keys match case-insensitively.
/// Values may be String or other (toString).
String? _strFirstNonEmpty(Map<String, dynamic> d, List<String> keys) {
  for (final key in keys) {
    var v = d[key];
    if (v == null) {
      final want = key.toLowerCase();
      for (final e in d.entries) {
        if (e.key.toLowerCase() == want) {
          v = e.value;
          break;
        }
      }
    }
    if (v == null) continue;
    final s = v is String ? v.trim() : v.toString().trim();
    if (s.isNotEmpty && s != 'null') return s;
  }
  return null;
}

String? _touristDocName(Map<String, dynamic> d) {
  final direct = _strFirstNonEmpty(d, const [
    'name',
    'fullName',
    'full_name',
    'touristName',
    'tourist_name',
    'displayName',
    'display_name',
    'visitorName',
    'visitor_name',
    'userName',
    'user_name',
    'username',
  ]);
  if (direct != null) return direct;

  final first = (_strFirstNonEmpty(d, const ['firstName', 'first_name', 'givenName']) ??
          '')
      .trim();
  final last = (_strFirstNonEmpty(d, const ['lastName', 'last_name', 'familyName']) ??
          '')
      .trim();
  if (first.isNotEmpty || last.isNotEmpty) {
    return '$first $last'.trim();
  }
  return _strFirstNonEmpty(d, const ['email', 'phone', 'phoneNumber', 'phone_number']);
}

/// Merges common nested maps (`user`, `profile`, …) into a single map for field lookup.
Map<String, dynamic> _touristDocFlattened(Map<String, dynamic> raw) {
  final flat = Map<String, dynamic>.from(raw);
  for (final nest in [
    'user',
    'profile',
    'tourist',
    'visitor',
    'data',
    'details',
    'checkIn',
    'check_in',
  ]) {
    final inner = raw[nest];
    if (inner is Map<String, dynamic>) {
      for (final e in inner.entries) {
        flat.putIfAbsent(e.key, () => e.value);
      }
    }
  }
  return flat;
}

/// Best-effort visit count stored on the `tourists` document (scalar or list length).
int _visitCountFromTouristDoc(Map<String, dynamic> d) {
  int best = 0;
  for (final key in const [
    'visits',
    'visitCount',
    'totalVisits',
    'checkInCount',
    'check_in_count',
    'visit_count',
    'numberOfVisits',
    'number_of_visits',
  ]) {
    final v = d[key];
    if (v is num) {
      final n = v.toInt();
      if (n > best) best = n;
    } else if (v is String) {
      final n = int.tryParse(v.trim());
      if (n != null && n > best) best = n;
    } else if (v is List && v.length > best) {
      best = v.length;
    }
  }
  for (final key in const [
    'visitHistory',
    'checkIns',
    'check_ins',
    'visitLog',
    'visit_log',
    'checkInHistory',
  ]) {
    final v = d[key];
    if (v is List && v.length > best) best = v.length;
  }
  return best < 0 ? 0 : best;
}

/// Counts visit documents per tourist id / Firestore doc id.
Map<String, int> touristVisitCountsFromVisitsSnapshot(
  QuerySnapshot<Map<String, dynamic>> snap,
) {
  final counts = <String, int>{};
  void bump(String? id) {
    final k = (id ?? '').trim();
    if (k.isEmpty) return;
    counts[k] = (counts[k] ?? 0) + 1;
  }

  for (final doc in snap.docs) {
    final d = doc.data();
    String? id;
    for (final key in const [
      'touristID',
      'touristId',
      'touristDocumentId',
      'tourist_document_id',
    ]) {
      final v = (_str(d, key) ?? '').trim();
      if (v.isNotEmpty) {
        id = v;
        break;
      }
    }
    bump(id);
  }
  return counts;
}

String? _touristDocOrigin(Map<String, dynamic> d) {
  return _strFirstNonEmpty(d, const [
    'origin',
    'from',
    'hometown',
    'homeTown',
    'home_town',
    'placeOfOrigin',
    'place_of_origin',
    'address',
    'location',
    'city',
    'municipality',
    'province',
    'country',
    'originCity',
    'origin_city',
    'residence',
    'residentialAddress',
    'residential_address',
    'barangay',
    'region',
    'place',
    'whereFrom',
    'where_from',
  ]);
}

/// Locality string from a `tourists` document (for municipality rollups).
String touristDocLocalityHint(DocumentSnapshot<Map<String, dynamic>> doc) {
  final d = _touristDocFlattened(doc.data() ?? {});
  return (_strFirstNonEmpty(d, const [
            'municipality',
            'visitMunicipality',
            'visitedMunicipality',
            'currentMunicipality',
            'city',
            'town',
            'origin',
            'hometown',
            'from',
            'location',
            'placeOfOrigin',
            'place_of_origin',
            'address',
          ]) ??
          '')
      .trim();
}

/// Counts `tourists` documents per LGU using [touristDocLocalityHint] and
/// [matchMunicipalityByLocalityHint] (same logic as the public Municipalities grid).
Map<String, int> touristCountsPerMunicipalityFromTouristDocs(
  Iterable<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
) {
  final counts = <String, int>{
    for (final m in sortedMunicipalities) m.name: 0,
  };
  for (final doc in docs) {
    final hint = touristDocLocalityHint(doc);
    final m = matchMunicipalityByLocalityHint(hint);
    if (m != null) {
      counts[m.name] = (counts[m.name] ?? 0) + 1;
    }
  }
  return counts;
}

/// Maps a Firestore `tourists` (or legacy `tourist`) document to [TouristRegistryEntry].
/// Supports fields: `name` (and common aliases), `touristID` / `touristId`, `origin`
/// (and common aliases), `date`, `time`, `visits`, and timestamps for date/time fallbacks.
TouristRegistryEntry touristRegistryEntryFromDoc(
  DocumentSnapshot<Map<String, dynamic>> doc,
) {
  final d = _touristDocFlattened(doc.data() ?? {});
  final rawName = (_touristDocName(d) ?? '').trim();
  final name = rawName.isEmpty ? '—' : rawName;

  var touristId = (_str(d, 'touristID') ?? _str(d, 'touristId') ?? '').trim();
  if (touristId.isEmpty) touristId = doc.id;

  final origin = (_touristDocOrigin(d) ?? '').trim();

  var dateDisplay = (_str(d, 'date') ?? '').trim();
  var timeDisplay = (_str(d, 'time') ?? '').trim();

  DateTime sortKey = DateTime.fromMillisecondsSinceEpoch(0);
  void considerSort(DateTime? t) {
    if (t != null && t.isAfter(sortKey)) sortKey = t;
  }

  final dateField = d['date'];
  if (dateField is Timestamp) {
    final dt = dateField.toDate();
    if (dateDisplay.isEmpty) dateDisplay = _registryDateYmd(dt);
    if (timeDisplay.isEmpty) timeDisplay = _registryTime12h(dt);
    considerSort(dt);
  } else if (dateField != null && dateDisplay.isEmpty) {
    dateDisplay = dateField.toString();
    considerSort(DateTime.tryParse(dateDisplay));
  }

  for (final key in ['registeredAt', 'createdAt', 'updatedAt', 'visitAt']) {
    considerSort(_timestampLikeToDateTime(d[key]));
  }

  if (dateDisplay.isEmpty || timeDisplay.isEmpty) {
    final fallback = _timestampLikeToDateTime(
          d['registeredAt'] ?? d['createdAt'] ?? d['updatedAt'],
        ) ??
        _timestampLikeToDateTime(dateField);
    if (fallback != null) {
      if (dateDisplay.isEmpty) dateDisplay = _registryDateYmd(fallback);
      if (timeDisplay.isEmpty) timeDisplay = _registryTime12h(fallback);
      considerSort(fallback);
    }
  }

  var visits = _visitCountFromTouristDoc(d);

  if (sortKey.millisecondsSinceEpoch == 0) {
    final parsed = DateTime.tryParse(dateDisplay);
    if (parsed != null) sortKey = parsed;
  }

  return TouristRegistryEntry(
    docId: doc.id,
    name: name,
    touristId: touristId,
    origin: origin.isEmpty ? '—' : origin,
    dateDisplay: dateDisplay.isEmpty ? '—' : dateDisplay,
    timeDisplay: timeDisplay.isEmpty ? '—' : timeDisplay,
    visits: visits,
    sortKey: sortKey,
  );
}

Future<void> syncAllMunicipalitiesToFirestore() async {
  applyDefaultMunicipalityBusTerminals();
  final firestore = FirebaseFirestore.instance;
  final batch = firestore.batch();
  for (final m in municipalities) {
    final docId = buildStableDocId(m.name, 'municipality');
    final docRef = firestore.collection(kMunicipalitiesCollection).doc(docId);
    final busPayload = busTerminalFirestorePayload(m.busTerminal);
    batch.set(docRef, {
      'name': m.name,
      'shortName': m.shortName,
      'imagePath': m.imagePath,
      'description': m.description,
      if (m.divisionKind.trim().isNotEmpty) 'divisionKind': m.divisionKind.trim(),
      if (busPayload != null) 'busTerminal': busPayload,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }
  await batch.commit();
}

String? _str(Map<String, dynamic>? d, String key) {
  if (d == null) return null;
  final v = d[key];
  return v is String ? v : v?.toString();
}

double _double(Map<String, dynamic>? d, String key) {
  if (d == null) return 0;
  final v = d[key];
  if (v is num) return v.toDouble();
  if (v is String) return double.tryParse(v) ?? 0;
  return 0;
}

double? _doubleOrNull(Map<String, dynamic>? d, String key) {
  if (d == null) return null;
  final v = d[key];
  if (v == null) return null;
  if (v is num) return v.toDouble();
  if (v is String) return double.tryParse(v);
  return null;
}

int? _intOrNull(Map<String, dynamic>? d, String key) {
  if (d == null) return null;
  final v = d[key];
  if (v == null) return null;
  if (v is int) return v;
  if (v is num) return v.toInt();
  if (v is String) return int.tryParse(v.trim());
  return null;
}

int? _timestampMillis(Map<String, dynamic>? d, String key) {
  if (d == null) return null;
  final v = d[key];
  if (v == null) return null;
  if (v is Timestamp) return v.millisecondsSinceEpoch;
  if (v is DateTime) return v.millisecondsSinceEpoch;
  if (v is int) return v;
  if (v is num) return v.toInt();
  if (v is String) {
    final parsed = DateTime.tryParse(v);
    return parsed?.millisecondsSinceEpoch;
  }
  return null;
}

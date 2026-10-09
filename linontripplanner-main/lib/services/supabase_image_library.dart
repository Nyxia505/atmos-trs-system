import 'dart:convert';

import 'package:flutter/foundation.dart' show debugPrint, kDebugMode;
import 'package:http/http.dart' as http;

import '../config/supabase_config.dart';
import '../data.dart' show TouristSpot, allSpots;

/// Supabase Storage is the source of truth for municipality and tourist-spot
/// photos.
///
/// Records normally carry a Supabase URL in their Firestore `imagePath`. When
/// that field is empty (most of the seeded municipalities) this library finds
/// the photo by matching the record name against the objects actually present
/// in the public buckets, so nothing has to be hardcoded and replacing a file
/// in Supabase is enough to change what the app shows.

/// Which kind of record an indexed object may be used for.
enum SupabaseImageScope { municipality, touristSpot, any }

/// One image object discovered in a public Supabase bucket.
class SupabaseImageObject {
  final String bucket;

  /// Object path inside [bucket], e.g. `images/aloran.jpg`.
  final String path;
  final SupabaseImageScope scope;

  /// Normalized name of the folder directly containing the object. Admin
  /// uploads land in `<root>/<record-slug>/`, so this is an exact record key.
  final String folderKey;

  /// Normalized file name without its extension.
  final String fileKey;

  /// Significant words describing the subject. Taken from the file name, or
  /// from the folder when the file is named by upload timestamp.
  final List<String> tokens;

  const SupabaseImageObject({
    required this.bucket,
    required this.path,
    required this.scope,
    required this.folderKey,
    required this.fileKey,
    required this.tokens,
  });

  String get url => SupabaseConfig.publicObjectUrl(bucket, path);
}

class _IndexRoot {
  final String bucket;
  final String prefix;
  final SupabaseImageScope scope;

  /// How many folder levels below [prefix] to walk.
  final int depth;

  const _IndexRoot({
    required this.bucket,
    required this.prefix,
    required this.scope,
    required this.depth,
  });
}

/// Folders scanned when resolving a photo by name, most specific first.
const List<_IndexRoot> _indexRoots = [
  // Curated LGU profile photos: tourist-images/municipalities/<lgu>/<file>.
  _IndexRoot(
    bucket: SupabaseConfig.photoLibraryBucket,
    prefix: 'municipalities',
    scope: SupabaseImageScope.municipality,
    depth: 2,
  ),
  // Written by the admin upload form; folder name is the record slug.
  _IndexRoot(
    bucket: SupabaseConfig.imageBucket,
    prefix: 'municipalities',
    scope: SupabaseImageScope.municipality,
    depth: 2,
  ),
  _IndexRoot(
    bucket: SupabaseConfig.imageBucket,
    prefix: 'tourist-spots',
    scope: SupabaseImageScope.touristSpot,
    depth: 2,
  ),
  // Curated spot photos live in tourist-images/images/<file>.
  _IndexRoot(
    bucket: SupabaseConfig.photoLibraryBucket,
    prefix: 'images',
    scope: SupabaseImageScope.touristSpot,
    depth: 1,
  ),
  // Curated photo library, organised by subject rather than by record.
  _IndexRoot(
    bucket: SupabaseConfig.photoLibraryBucket,
    prefix: '',
    scope: SupabaseImageScope.any,
    depth: 3,
  ),
];

/// Known Supabase folder slugs that differ from a simple name normalization
/// (e.g. "Don Victoriano Chiongbian" → `dvc`).
const Map<String, String> _municipalityFolderAliases = {
  'donvictorianochiongbian': 'dvc',
  'donvchiongbian': 'dvc',
  'donvictoriano': 'dvc',
  'lopezjaena': 'lopezjaena',
  'sapangdalaga': 'sapangdalaga',
  'oroquietacity': 'oroquieta',
  'ozamizcity': 'ozamiz',
  'ozamis': 'ozamiz',
  'ozamiscity': 'ozamiz',
  'tangubcity': 'tangub',
};

/// Exact profile-object paths under `tourist-images` when the file is not named
/// `<slug>/<slug>.ext` (curated landmark photos supplied for each LGU folder).
const Map<String, String> _municipalityKnownProfilePaths = {
  'baliangao': 'municipalities/baliangao/baliangao.jpg',
  'dvc': 'municipalities/dvc/dvc_piduan_falls.jpg',
  'jimenez':
      'municipalities/jimenez/jimenez_st_john_the_baptist_church.jpg',
  'oroquieta': 'municipalities/oroquieta/oroquieta_capitol.webp',
  'ozamiz': 'municipalities/ozamiz/ozamiz_city.webp',
  'sinacaban': 'municipalities/sinacaban/sinacaban_amorap.jpg',
  'tangub': 'municipalities/tangub/tangub_asenso_global_garden.png',
  'tudela': 'municipalities/tudela/tudela_village.webp',
};

/// Broken / undecodable Storage objects (Chrome throws EncodingError).
const Set<String> _blacklistedObjectPathSuffixes = {
  'oroquieta_city_plaza.jpeg',
  'oroquieta_city_plaza.jpg',
};

/// Curated Firestore spot name → `tourist-images/...` object path.
/// Keys are [normalizeSupabaseImageKey] of the spot title (and short aliases).
/// Prefer this over fuzzy matching so LGU files are not shown as spot photos.
const Map<String, String> _touristSpotKnownImagePaths = {
  'baliangaoprotectedlandscape':
      'images/baliangao_protected_landscape_seascape.png',
  'blessamaresunrisebeach': 'images/Sunrise Beach Baliangao.jpg',
  'bonifaciomountainoverlook': 'images/Bonifacio_kanao.png',
  'lakeduminagat': 'images/lake_duminagat.webp',
  'concepcionfalls': 'images/conception.png',
  'mountmalindangrangenaturalpark': 'images/DonVic_v2.png',
  'stjohnthebaptistchurchjimenez':
      'images/Jimenez - St. John the Baptist Church.jpg',
  'stjohnthebaptistchurch':
      'images/Jimenez - St. John the Baptist Church.jpg',
  'cottabeachozamiscity': 'images/Cotta Beach.jpg',
  'cottabeach': 'images/Cotta Beach.jpg',
  'cottafortandshrineozamiscity': 'images/Cotta Fort & Shrine.jpg',
  'cottafortandshrine': 'images/Cotta Fort & Shrine.jpg',
  'cottafortshrineozamiscity': 'images/Cotta Fort & Shrine.jpg',
  'cottafortshrine': 'images/Cotta Fort & Shrine.jpg',
  'immaculateconceptioncathedralozamiscity':
      'images/Immaculate Conception Cathedral.webp',
  'immaculateconceptioncathedral':
      'images/Immaculate Conception Cathedral.webp',
  'panaonseaside': 'images/Panaon.png',
  'piduanfalls': 'images/Piduan Falls Donvic.jpg',
  'plaridelresort': 'images/Plaridel.png',
  'eltriunfo': 'images/el triunfo.png',
  'sapangdalagafloatingcottages': 'images/Sapang_Dalaga_v2.png',
  'amorapasensomisamisoccidentalresortandaquamarinepark': 'images/AMORAP.jpg',
  'amorap': 'images/AMORAP.jpg',
  'asensoglobalgardenstangubcity': 'images/Asenso Global Garden 1.png',
  'asensoglobalgardens': 'images/Asenso Global Garden 1.png',
  'asensoozamizwellnessparkozamiscity': 'images/ozamis city.webp',
  'asensoozamizwellnesspark': 'images/ozamis city.webp',
};

bool _isBlacklistedStoragePath(String pathOrUrl) {
  final lower = pathOrUrl.toLowerCase();
  for (final suffix in _blacklistedObjectPathSuffixes) {
    if (lower.endsWith(suffix) || lower.contains('/$suffix')) return true;
  }
  return false;
}

/// Sync curated URL for a spot name (no network). Used to lock Piduan / Panaon
/// / etc. to the correct `tourist-images/images/…` file after Firestore load.
String? curatedTouristSpotImageUrl(String spotName) {
  final keys = <String>{
    normalizeSupabaseImageKey(spotName),
    for (final v in supabaseImageNameVariants([spotName]))
      normalizeSupabaseImageKey(v),
  };
  for (final key in keys) {
    if (key.isEmpty) continue;
    final path = _touristSpotKnownImagePaths[key];
    if (path == null || path.isEmpty) continue;
    final url = SupabaseConfig.publicObjectUrl(
      SupabaseConfig.photoLibraryBucket,
      path,
    );
    if (_isBlacklistedStoragePath(url)) continue;
    return url;
  }
  return null;
}

Future<String?> _knownTouristSpotImageUrl(String spotName) async {
  final url = curatedTouristSpotImageUrl(spotName);
  if (url == null) return null;
  if (await _publicObjectExists(url)) return url;
  return null;
}

/// Applies curated spot→file maps (e.g. Piduan Falls → `Piduan Falls Donvic.jpg`,
/// Panaon Seaside → `Panaon.png`) and clears those URLs from any other spot that
/// wrongly reused them (e.g. Mount Malindang pointing at Piduan Falls).
int applyCuratedTouristSpotImageUrls() {
  if (!SupabaseConfig.isConfigured || allSpots.isEmpty) return 0;

  final curatedByIndex = <int, String>{};
  final claimed = <String>{};
  for (var i = 0; i < allSpots.length; i++) {
    final url = curatedTouristSpotImageUrl(allSpots[i].name);
    if (url == null || url.isEmpty) continue;
    if (!claimed.add(url)) continue;
    curatedByIndex[i] = url;
  }

  var changed = 0;
  final next = <TouristSpot>[];
  for (var i = 0; i < allSpots.length; i++) {
    final spot = allSpots[i];
    final curated = curatedByIndex[i];
    if (curated != null) {
      if (spot.imagePath != curated) changed++;
      next.add(spot.copyWith(imagePath: curated));
      continue;
    }
    final current = spot.imagePath.trim();
    if (current.isNotEmpty && claimed.contains(current)) {
      // Another curated spot owns this file — don't show a duplicate.
      changed++;
      next.add(spot.copyWith(imagePath: ''));
    } else {
      next.add(spot);
    }
  }

  allSpots
    ..clear()
    ..addAll(next);

  if (kDebugMode && changed > 0) {
    debugPrint(
      'Curated spot images applied: $changed corrections '
      '(Piduan/Panaon/DonVic maps + exclusive URLs)',
    );
  }
  return changed;
}

const _imageExtensions = {'jpg', 'jpeg', 'png', 'webp', 'gif', 'bmp', 'heic'};

List<SupabaseImageObject> _index = const [];
Future<void>? _indexLoad;

/// Resolved tourist-spot URLs keyed by [normalizeSupabaseImageKey] of the name.
final Map<String, String> _touristSpotUrlByNameKey = {};
Future<void>? _touristSpotWarm;

/// Drops the cached bucket index so the next lookup re-reads Supabase.
void clearSupabaseImageIndex() {
  _index = const [];
  _indexLoad = null;
  _publicExistsCache.clear();
  _touristSpotUrlByNameKey.clear();
  _touristSpotWarm = null;
}

/// Number of objects currently indexed (0 until the first lookup completes).
int get supabaseImageIndexSize => _index.length;

/// Loads the bucket index once per session. Safe to call concurrently.
Future<void> ensureSupabaseImageIndexLoaded() {
  if (!SupabaseConfig.isConfigured) return Future.value();
  return _indexLoad ??= _buildIndex();
}

/// Best matching Supabase image for a record, or null when nothing matches
/// confidently enough to show.
///
/// [names] are tried in order of preference (e.g. full name, then short name).
/// [folderHints] are optional municipality / place folder slugs used when
/// probing tourist-spot photos under `tourist-images/<folder>/`.
Future<String?> resolveSupabaseImageUrlForNames(
  List<String> names, {
  required SupabaseImageScope scope,
  List<String> folderHints = const [],
}) async {
  if (names.isEmpty) return null;

  if (scope == SupabaseImageScope.touristSpot) {
    for (final n in names) {
      final cached = _touristSpotUrlByNameKey[normalizeSupabaseImageKey(n)];
      if (cached != null && cached.isNotEmpty) return cached;
    }
    // Prefer the catalog warm result when it is already running so list cards
    // share one discovery pass instead of each probing independently.
    final warm = _touristSpotWarm;
    if (warm != null) {
      await warm;
      for (final n in names) {
        final cached = _touristSpotUrlByNameKey[normalizeSupabaseImageKey(n)];
        if (cached != null && cached.isNotEmpty) return cached;
      }
    }

    final known = await _knownTouristSpotImageUrl(names.first);
    if (known != null) {
      _cacheTouristSpotUrl(names.first, known);
      return known;
    }
  }

  await ensureSupabaseImageIndexLoaded();

  // Curated LGU profiles first — avoids fuzzy picks of broken files
  // (e.g. oroquieta_city_plaza.jpeg) over known-good capitol photos.
  if (scope == SupabaseImageScope.municipality) {
    final direct = await _probeMunicipalityProfileUrl(names);
    if (direct != null && !_isBlacklistedStoragePath(direct)) return direct;
  }

  if (_index.isNotEmpty) {
    final best = bestSupabaseImageMatch(
      _index,
      names,
      scope: scope,
      // Tourist spots: only strong matches (exact file/folder). Weak fuzzy
      // pairs often attach LGU photos (Aloran.jpg, Calamba.png) to spots.
      minScore: scope == SupabaseImageScope.touristSpot ? 850 : 1,
    );
    if (best != null && !_isBlacklistedStoragePath(best.path)) {
      if (kDebugMode) {
        debugPrint(
          'Supabase image "${names.first}" -> ${best.bucket}/${best.path}',
        );
      }
      if (scope == SupabaseImageScope.touristSpot) {
        _cacheTouristSpotUrl(names.first, best.url);
      }
      return best.url;
    }
  }

  // Bucket listing is often blocked for the anon key (HTTP 200 + empty array).
  // Fall back to probing public object URLs derived from the record name.
  if (scope == SupabaseImageScope.municipality) {
    // Already tried above.
  } else if (scope == SupabaseImageScope.touristSpot) {
    final direct = await _probeTouristSpotProfileUrl(
      names,
      folderHints: folderHints,
    );
    if (direct != null && !_isBlacklistedStoragePath(direct)) {
      _cacheTouristSpotUrl(names.first, direct);
      return direct;
    }
  }
  return null;
}

void _cacheTouristSpotUrl(String name, String url) {
  final key = normalizeSupabaseImageKey(name);
  if (key.isEmpty || url.isEmpty) return;
  _touristSpotUrlByNameKey[key] = url;
}

/// Prefetches Supabase photos for every tourist spot so home/list cards do not
/// each re-probe the bucket. Discovers live objects by name-derived public URL
/// probes (listing is often blocked for the anon key), then fuzzy-matches.
Future<void> warmTouristSpotImagesFromSupabase(
  Iterable<({String name, String location})> spots,
) {
  return _touristSpotWarm ??= _warmTouristSpotImagesImpl(spots);
}

/// Loads Firestore [allSpots], finds the Supabase Storage file whose name
/// matches each spot name, and writes that public URL onto [TouristSpot.imagePath].
///
/// Matching order: exact file/folder key → fuzzy index match → public URL probe
/// under `tourist-images/images/<spot-name>.*`.
///
/// Returns how many spots received a new Supabase URL.
Future<int> applySupabaseImagesToLoadedTouristSpots() async {
  if (!SupabaseConfig.isConfigured || allSpots.isEmpty) return 0;

  // Force a fresh warm so curated maps apply even after a prior fuzzy pass.
  _touristSpotWarm = null;
  _touristSpotUrlByNameKey.clear();

  await warmTouristSpotImagesFromSupabase(
    allSpots.map((s) => (name: s.name, location: s.location)),
  );

  var applied = 0;
  final claimed = <String>{};
  final next = <TouristSpot>[];
  for (final spot in allSpots) {
    var url = cachedTouristSpotImageUrl(spot.name);
    url ??= await resolveSupabaseImageUrlForNames(
      [spot.name],
      scope: SupabaseImageScope.touristSpot,
      folderHints: spot.location.trim().isEmpty
          ? const []
          : municipalitySupabaseFolderSlugs([spot.location]),
    );

    if (url != null &&
        url.isNotEmpty &&
        !_isBlacklistedStoragePath(url) &&
        claimed.add(url)) {
      _cacheTouristSpotUrl(spot.name, url);
      if (spot.imagePath != url) applied++;
      next.add(spot.copyWith(imagePath: url));
    } else if (url != null &&
        url.isNotEmpty &&
        claimed.contains(url) &&
        SupabaseConfig.isSupabaseStorageUrl(spot.imagePath) &&
        spot.imagePath == url) {
      // Same correct URL already claimed by this spot earlier in the list.
      next.add(spot);
    } else if (url != null && url.isNotEmpty && claimed.contains(url)) {
      // Another spot already owns this file — leave blank rather than duplicate.
      next.add(
        SupabaseConfig.isSupabaseStorageUrl(spot.imagePath)
            ? spot.copyWith(imagePath: '')
            : spot,
      );
    } else {
      // Clear prior wrong fuzzy Supabase URLs so UI shows placeholder.
      next.add(
        SupabaseConfig.isSupabaseStorageUrl(spot.imagePath)
            ? spot.copyWith(imagePath: '')
            : spot,
      );
    }
  }

  allSpots
    ..clear()
    ..addAll(next);

  if (kDebugMode) {
    debugPrint(
      'Supabase spot images applied: $applied/${allSpots.length} '
      '(curated / exact name match)',
    );
  }
  return applied;
}

/// Cached Supabase URL for a spot name, if warm/resolve already found one.
String? cachedTouristSpotImageUrl(String name) {
  final key = normalizeSupabaseImageKey(name);
  if (key.isEmpty) return null;
  final url = _touristSpotUrlByNameKey[key];
  if (url == null || url.isEmpty) return null;
  return url;
}

Future<void> _warmTouristSpotImagesImpl(
  Iterable<({String name, String location})> spots,
) async {
  final list = spots
      .map((s) => (name: s.name.trim(), location: s.location.trim()))
      .where((s) => s.name.isNotEmpty)
      .toList(growable: false);
  if (list.isEmpty || !SupabaseConfig.isConfigured) return;

  await ensureSupabaseImageIndexLoaded();

  // Probe each spot (listing is often empty for anon). Parallel batches keep
  // startup reasonable while still covering the full catalog.
  const concurrency = 4;
  for (var i = 0; i < list.length; i += concurrency) {
    final batch = list.sublist(
      i,
      i + concurrency > list.length ? list.length : i + concurrency,
    );
    await Future.wait(
      batch.map((spot) async {
        final known = await _knownTouristSpotImageUrl(spot.name);
        if (known != null) {
          _cacheTouristSpotUrl(spot.name, known);
          return;
        }

        // Exact file / folder name == spot name (normalized).
        if (_index.isNotEmpty) {
          final exact = exactSupabaseImageMatchForName(
            _index,
            spot.name,
            scope: SupabaseImageScope.touristSpot,
          );
          if (exact != null) {
            _cacheTouristSpotUrl(spot.name, exact.url);
            return;
          }
        }

        final nameVariants = supabaseImageNameVariantsForTouristSpot([
          spot.name,
        ]);
        if (_index.isNotEmpty) {
          final best = bestSupabaseImageMatch(
            _index,
            nameVariants,
            scope: SupabaseImageScope.touristSpot,
            minScore: 850,
          );
          if (best != null) {
            _cacheTouristSpotUrl(spot.name, best.url);
            return;
          }
        }
        final probed = await _probeTouristSpotProfileUrl(
          [spot.name],
          folderHints: const [], // do not probe LGU folders for spot photos
        );
        if (probed != null) _cacheTouristSpotUrl(spot.name, probed);
      }),
    );
  }

  if (kDebugMode) {
    debugPrint(
      'Supabase spot warm: resolved ${_touristSpotUrlByNameKey.length}/'
      '${list.length} spots',
    );
  }
}

/// Folder slug candidates for an LGU name, matching the Supabase folder layout
/// shown in Storage (`aloran`, `lopezjaena`, `dvc`, …).
List<String> municipalitySupabaseFolderSlugs(List<String> names) {
  final out = <String>[];
  void add(String slug) {
    if (slug.isEmpty || out.contains(slug)) return;
    out.add(slug);
  }

  for (final variant in supabaseImageNameVariants(names)) {
    final key = normalizeSupabaseImageKey(variant);
    if (key.isEmpty) continue;
    add(_municipalityFolderAliases[key] ?? key);
    // Compact form without spaces already applied by normalize; also keep a
    // hyphenless "lopez jaena" → lopezjaena style from spaced names.
    add(variant.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), ''));
  }
  return out;
}

Future<String?> _probeMunicipalityProfileUrl(List<String> names) async {
  final slugs = municipalitySupabaseFolderSlugs(names);
  if (slugs.isEmpty) return null;

  // Curated landmark filenames that do not follow <slug>/<slug>.ext.
  for (final slug in slugs) {
    final known = _municipalityKnownProfilePaths[slug];
    if (known == null) continue;
    final url = SupabaseConfig.publicObjectUrl(
      SupabaseConfig.photoLibraryBucket,
      known,
    );
    if (await _publicObjectExists(url)) {
      if (kDebugMode) {
        debugPrint(
          'Supabase municipality known path "${names.first}" -> $url',
        );
      }
      return url;
    }
  }

  const exts = ['jpg', 'png', 'jpeg', 'webp', 'JPG', 'PNG'];

  for (final slug in slugs) {
    // Most folders use <slug>/<slug>.jpg|png — check those first, in parallel.
    final primary = await _firstExistingUrl([
      for (final ext in exts)
        SupabaseConfig.publicObjectUrl(
          SupabaseConfig.photoLibraryBucket,
          'municipalities/$slug/$slug.$ext',
        ),
    ]);
    if (primary != null) {
      if (kDebugMode) {
        debugPrint(
          'Supabase municipality probe "${names.first}" -> $primary',
        );
      }
      return primary;
    }

    final secondary = await _firstExistingUrl([
      for (final stem in ['profile', 'cover', 'image', 'main', 'photo'])
        for (final ext in const ['jpg', 'png', 'jpeg', 'webp'])
          SupabaseConfig.publicObjectUrl(
            SupabaseConfig.photoLibraryBucket,
            'municipalities/$slug/$stem.$ext',
          ),
      for (final ext in const ['jpg', 'png', 'webp'])
        SupabaseConfig.publicObjectUrl(
          SupabaseConfig.photoLibraryBucket,
          'images/$slug.$ext',
        ),
    ]);
    if (secondary != null) {
      if (kDebugMode) {
        debugPrint(
          'Supabase municipality probe "${names.first}" -> $secondary',
        );
      }
      return secondary;
    }
  }
  return null;
}

/// Probes public URLs for a tourist spot when bucket listing is empty.
///
/// Curated files live under `tourist-images/images/<file>` and sometimes under
/// `tourist-images/municipalities/<lgu>/…`. Paths are derived from the Firestore
/// spot name (and optional location folder) — nothing is hardcoded per spot.
Future<String?> _probeTouristSpotProfileUrl(
  List<String> names, {
  List<String> folderHints = const [],
}) async {
  // Prefer curated path when available.
  for (final n in names) {
    final known = await _knownTouristSpotImageUrl(n);
    if (known != null) return known;
  }

  final stems = <String>[
    for (final n in names) ...supabaseImageNameVariantsForTouristSpot([n]),
    ..._touristSpotFileStems(names),
  ];
  final deduped = <String>[];
  for (final s in stems) {
    final key = normalizeSupabaseImageKey(s);
    // Skip short stems that collide with LGU files (aloran, calamba, …).
    if (key.length < 8 &&
        !(s.length <= 8 && s.toUpperCase() == s && RegExp(r'^[A-Za-z0-9]+$').hasMatch(s))) {
      continue;
    }
    if (deduped.any((d) => d.toLowerCase() == s.toLowerCase())) continue;
    deduped.add(s);
  }
  if (deduped.isEmpty) return null;

  const exts = ['jpg', 'png', 'webp', 'jpeg', 'JPG', 'PNG', 'WEBP', 'JPEG'];
  final library = SupabaseConfig.photoLibraryBucket;

  final candidatePaths = <String>[
    for (final stem in deduped)
      for (final ext in exts) 'images/$stem.$ext',
    for (final stem in deduped.take(8))
      for (final ext in exts) 'tourist-spots/$stem/$stem.$ext',
  ];

  final urls = [
    for (final path in candidatePaths)
      if (!_isBlacklistedStoragePath(path))
        SupabaseConfig.publicObjectUrl(library, path),
  ];
  final hit = await _firstExistingUrl(urls);
  if (hit != null && kDebugMode) {
    debugPrint('Supabase spot probe "${names.first}" -> $hit');
  }
  return hit;
}

/// File-name stems that may appear under `tourist-images/images/`.
///
/// Short / high-signal stems are listed first so probes hit `AMORAP.jpg`
/// before spending time on long decorated titles.
List<String> _touristSpotFileStems(List<String> names) {
  final short = <String>[];
  final long = <String>[];
  void add(String raw, {required bool prefer}) {
    final t = raw.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (t.isEmpty || t.contains('/')) return;
    if (short.contains(t) || long.contains(t)) return;
    (prefer ? short : long).add(t);
  }

  String titleCase(String s) {
    return s
        .split(RegExp(r'\s+'))
        .where((w) => w.isNotEmpty)
        .map((w) => '${w[0].toUpperCase()}${w.substring(1).toLowerCase()}')
        .join(' ');
  }

  String singularizePhrase(String s) {
    return s
        .split(RegExp(r'\s+'))
        .map((w) {
          final lower = w.toLowerCase();
          if (lower.length > 4 &&
              lower.endsWith('s') &&
              !lower.endsWith('ss') &&
              !lower.endsWith('us') &&
              !lower.endsWith('is')) {
            return w.substring(0, w.length - 1);
          }
          return w;
        })
        .join(' ');
  }

  void addForms(String variant, {required bool prefer}) {
    add(variant, prefer: prefer);
    add(variant.toLowerCase(), prefer: prefer);
    add(titleCase(variant), prefer: prefer);
    // Common PH place-name spelling drift (Concepcion ↔ Conception).
    if (RegExp(r'conception', caseSensitive: false).hasMatch(variant)) {
      final alt = variant.replaceAll(RegExp(r'[Cc]onception'), 'Concepcion');
      add(alt, prefer: prefer);
      add(titleCase(alt), prefer: prefer);
    }
    if (RegExp(r'concepcion', caseSensitive: false).hasMatch(variant)) {
      final alt = variant.replaceAll(RegExp(r'[Cc]oncepcion'), 'Conception');
      add(alt, prefer: prefer);
      add(titleCase(alt), prefer: prefer);
    }
    final singular = singularizePhrase(variant);
    if (singular.toLowerCase() != variant.toLowerCase()) {
      add(singular, prefer: prefer);
      add(titleCase(singular), prefer: prefer);
      // Curated files sometimes append " 1" (e.g. Asenso Global Garden 1.png).
      add('$singular 1', prefer: prefer);
      add('${titleCase(singular)} 1', prefer: prefer);
    }
    final snake = variant
        .toLowerCase()
        .replaceAll('&', ' and ')
        .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
        .replaceAll(RegExp(r'^_+|_+$'), '');
    if (snake.isEmpty) return;
    add(snake, prefer: prefer);
    add(snake.replaceAll('_', '-'), prefer: prefer);
    add(snake.replaceAll('_', ' '), prefer: prefer);
    add(titleCase(snake.replaceAll('_', ' ')), prefer: prefer);
    final snakeSingular = singularizePhrase(snake.replaceAll('_', ' '))
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
        .replaceAll(RegExp(r'^_+|_+$'), '');
    if (snakeSingular.isNotEmpty && snakeSingular != snake) {
      add(snakeSingular, prefer: prefer);
      add('${snakeSingular}_1', prefer: prefer);
      add('${snakeSingular.replaceAll('_', ' ')} 1', prefer: prefer);
    }
  }

  for (final variant in supabaseImageNameVariants(names)) {
    // Acronyms / leading label before an en-dash ("AMORAP – …").
    final head = variant.split(RegExp(r'\s[\u2013\u2014-]\s')).first.trim();
    if (head.isNotEmpty && head.toLowerCase() != variant.toLowerCase()) {
      addForms(head, prefer: true);
    }
    final words = variant.split(RegExp(r'\s+')).where((w) => w.isNotEmpty);
    addForms(variant, prefer: words.length <= 4);
  }

  return [...short, ...long].take(36).toList(growable: false);
}

Future<String?> _firstExistingUrl(List<String> urls) async {
  // Check in small parallel batches so a missing LGU does not serialize dozens
  // of sequential network round-trips.
  const batchSize = 6;
  for (var i = 0; i < urls.length; i += batchSize) {
    final batch = urls.sublist(
      i,
      i + batchSize > urls.length ? urls.length : i + batchSize,
    );
    final results = await Future.wait(batch.map(_publicObjectExists));
    for (var j = 0; j < results.length; j++) {
      if (results[j]) return batch[j];
    }
  }
  return null;
}

final Map<String, Future<bool>> _publicExistsCache = {};

Future<bool> _publicObjectExists(String url) {
  return _publicExistsCache.putIfAbsent(url, () async {
    try {
      final head = await http
          .head(Uri.parse(url))
          .timeout(const Duration(seconds: 6));
      if (head.statusCode >= 200 && head.statusCode < 300) return true;
      // Supabase often answers HEAD with 400 for both hits and misses; confirm
      // with a tiny ranged GET (avoids downloading the whole image).
      if (head.statusCode == 400 ||
          head.statusCode == 403 ||
          head.statusCode == 405 ||
          head.statusCode == 404) {
        final get = await http
            .get(
              Uri.parse(url),
              headers: const {'Range': 'bytes=0-0'},
            )
            .timeout(const Duration(seconds: 6));
        if (get.statusCode >= 200 && get.statusCode < 300) return true;
        // Missing keys come back as HTTP 400 + NoSuchKey JSON.
        final body = get.body;
        if (body.contains('NoSuchKey') || body.contains('not_found')) {
          return false;
        }
        // Some objects reject Range; a short non-ranged GET still works.
        if (get.statusCode == 400 || get.statusCode == 416) {
          final full = await http
              .get(Uri.parse(url))
              .timeout(const Duration(seconds: 8));
          return full.statusCode >= 200 && full.statusCode < 300;
        }
      }
      return false;
    } catch (_) {
      return false;
    }
  });
}

/// Highest-scoring object for a record, or null when nothing matches
/// confidently enough to show. Exposed so the matching can be exercised
/// against a known object list.
SupabaseImageObject? bestSupabaseImageMatch(
  Iterable<SupabaseImageObject> objects,
  List<String> names, {
  required SupabaseImageScope scope,
  int minScore = 1,
}) {
  if (names.isNotEmpty) {
    final exact =
        exactSupabaseImageMatchForName(objects, names.first, scope: scope);
    if (exact != null) return exact;
  }

  final candidates = scope == SupabaseImageScope.touristSpot
      ? supabaseImageNameVariantsForTouristSpot(names)
      : supabaseImageNameVariants(names);
  if (candidates.isEmpty) return null;

  final keys = [for (final n in candidates) normalizeSupabaseImageKey(n)];
  final tokenSets = [for (final n in candidates) supabaseImageNameTokens(n)];

  SupabaseImageObject? best;
  var bestScore = 0;
  for (final entry in objects) {
    if (entry.scope != SupabaseImageScope.any && entry.scope != scope) continue;
    if (_isBlacklistedStoragePath(entry.path)) continue;
    var score = 0;
    for (var i = 0; i < keys.length; i++) {
      // Later variants are weaker signals (short name, name minus suffix).
      final penalty = i * 20;
      final raw = _scoreKey(entry, keys[i], tokenSets[i]);
      if (raw > 0 && raw - penalty > score) score = raw - penalty;
    }
    if (score > bestScore) {
      bestScore = score;
      best = entry;
    }
  }
  if (bestScore < minScore) return null;
  return best;
}

/// Exact match: normalized spot name equals the storage file stem or folder.
SupabaseImageObject? exactSupabaseImageMatchForName(
  Iterable<SupabaseImageObject> objects,
  String name, {
  required SupabaseImageScope scope,
}) {
  final variants = scope == SupabaseImageScope.touristSpot
      ? supabaseImageNameVariantsForTouristSpot([name])
      : supabaseImageNameVariants([name]);
  final wantKeys = <String>{};
  for (final variant in variants) {
    final k = normalizeSupabaseImageKey(variant);
    // Tourist spots: require longer keys so "aloran" alone never wins.
    final minLen = scope == SupabaseImageScope.touristSpot ? 8 : 3;
    if (k.length >= minLen) wantKeys.add(k);
    // Allow short acronyms (AMORAP).
    if (scope == SupabaseImageScope.touristSpot &&
        k.length >= 3 &&
        k.length <= 8 &&
        RegExp(r'^[a-z0-9]+$').hasMatch(k) &&
        variant.toUpperCase() == variant) {
      wantKeys.add(k);
    }
  }
  if (wantKeys.isEmpty) return null;

  SupabaseImageObject? fileHit;
  SupabaseImageObject? folderHit;
  for (final entry in objects) {
    if (entry.scope != SupabaseImageScope.any && entry.scope != scope) continue;
    if (_isBlacklistedStoragePath(entry.path)) continue;
    if (wantKeys.contains(entry.fileKey)) {
      fileHit = entry;
      break;
    }
    if (folderHit == null && wantKeys.contains(entry.folderKey)) {
      folderHit = entry;
    }
  }
  return fileHit ?? folderHit;
}

/// Names to try for a record, best first: the name itself, then progressively
/// trimmed forms. Catalog names carry decorations the file names lack, such as
/// "Cotta Beach – Ozamis City" and "Oroquieta City (Provincial Capital)".
List<String> supabaseImageNameVariants(List<String> names) {
  final out = <String>[];
  void add(String s) {
    final t = s.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (t.isEmpty) return;
    if (out.any((o) => o.toLowerCase() == t.toLowerCase())) return;
    out.add(t);
  }

  for (final n in names) {
    add(n);
  }
  for (final n in List<String>.from(out)) {
    add(n.replaceAll(RegExp(r'\s*\([^)]*\)'), ''));
  }
  // Drop a trailing " – Municipality" / " - Municipality" qualifier.
  for (final n in List<String>.from(out)) {
    final cut = n.split(RegExp(r'\s[\u2013\u2014-]\s')).first;
    add(cut);
  }
  for (final n in List<String>.from(out)) {
    add(n.replaceAll(RegExp(r'\s+city$', caseSensitive: false), ''));
  }
  // Leading words alone ("Concepcion Falls" → "Concepcion") help match files
  // that omit the rest of the title or use near-spellings.
  for (final n in List<String>.from(out)) {
    final parts = n
        .split(RegExp(r'\s+'))
        .where((w) => w.trim().length >= 3)
        .toList();
    if (parts.isEmpty) continue;
    add(parts.first);
    if (parts.length >= 2) add('${parts[0]} ${parts[1]}');
  }
  return out;
}

/// Stricter variants for tourist spots — no lone first-word matches that steal
/// municipality photos (e.g. "Aloran Viewpoint" → `aloran.jpg`).
List<String> supabaseImageNameVariantsForTouristSpot(List<String> names) {
  final out = <String>[];
  void add(String s) {
    final t = s.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (t.isEmpty) return;
    if (out.any((o) => o.toLowerCase() == t.toLowerCase())) return;
    out.add(t);
  }

  for (final n in names) {
    add(n);
  }
  for (final n in List<String>.from(out)) {
    add(n.replaceAll(RegExp(r'\s*\([^)]*\)'), ''));
  }
  for (final n in List<String>.from(out)) {
    final cut = n.split(RegExp(r'\s[\u2013\u2014-]\s')).first;
    add(cut);
  }
  // Acronym before en-dash only (AMORAP – …).
  for (final n in List<String>.from(out)) {
    final head = n.split(RegExp(r'\s[\u2013\u2014-]\s')).first.trim();
    if (head.length >= 3 &&
        head.length <= 8 &&
        RegExp(r'^[A-Za-z0-9]+$').hasMatch(head) &&
        head.toUpperCase() == head) {
      add(head);
    }
  }
  // First two significant words only when the title is longer.
  for (final n in List<String>.from(out)) {
    final parts = n
        .split(RegExp(r'\s+'))
        .where((w) => w.trim().length >= 3)
        .toList();
    if (parts.length >= 2) add('${parts[0]} ${parts[1]}');
  }
  return out;
}

/// Comparison key: lowercase alphanumerics only, `&` spelled out.
String normalizeSupabaseImageKey(String s) {
  var t = s.toLowerCase().trim();
  if (t.isEmpty) return '';
  t = t.replaceAll('&', ' and ');
  t = t.replaceAll(RegExp(r'[^a-z0-9]+'), '');
  return t;
}

/// Words too common in this catalog to identify a subject on their own.
const _stopWords = {
  'the', 'and', 'for', 'with', 'city', 'misamis', 'occidental', 'nearby',
  'image', 'images', 'photo', 'new', 'old',
};

/// Significant lowercase words in a name, de-pluralized so "Gardens" and
/// "Garden" match.
List<String> supabaseImageNameTokens(String s) {
  final out = <String>[];
  for (var t in s.toLowerCase().replaceAll('&', ' and ').split(
    RegExp(r'[^a-z0-9]+'),
  )) {
    if (t.length < 3 || _stopWords.contains(t)) continue;
    if (t.length > 4 && t.endsWith('s') && !t.endsWith('ss')) {
      t = t.substring(0, t.length - 1);
    }
    if (!out.contains(t)) out.add(t);
  }
  return out;
}

/// 0 = no usable match. Exact matches outrank prefixes, which outrank
/// near-spellings and word overlap, so a record never steals a photo that
/// names another record more precisely.
int _scoreKey(SupabaseImageObject entry, String want, List<String> wantTokens) {
  if (want.length < 3) return 0;

  // Admin uploads land in a folder named after the record.
  if (entry.folderKey == want) return 1000;
  if (entry.fileKey == want) return 900;

  // "Oroquieta City" -> "oroquieta city plaza.jpeg"
  if (want.length >= 5 && entry.fileKey.startsWith(want)) {
    return 700 + want.length;
  }
  // "Cabgan Island" -> "Baliangao - Cabgan Island.jpg"
  if (want.length >= 6 && entry.fileKey.contains(want)) {
    return 500 + want.length;
  }
  // Spelling drift between Firestore and the file name
  // ("Ozamiz City" vs "ozamis city", "Concepcion" vs "conception").
  final tolerance = want.length >= 10 ? 2 : 1;
  if (want.length >= 6 &&
      (entry.fileKey.length - want.length).abs() <= tolerance &&
      _editDistanceWithin(entry.fileKey, want, tolerance)) {
    return 600;
  }
  return _tokenOverlapScore(entry.tokens, wantTokens);
}

/// Handles word-order and suffix differences such as
/// "Cotta Beach – Ozamis City" vs "Cotta Beach.jpg". Two shared significant
/// words are required, so a lone generic word like "Resort" never matches.
int _tokenOverlapScore(List<String> fileTokens, List<String> wantTokens) {
  if (fileTokens.length < 2 || wantTokens.length < 2) return 0;
  var shared = 0;
  for (final t in fileTokens) {
    if (wantTokens.contains(t)) shared++;
  }
  if (shared < 2) return 0;
  final fileCoverage = shared / fileTokens.length;
  final wantCoverage = shared / wantTokens.length;
  final coverage = fileCoverage > wantCoverage ? fileCoverage : wantCoverage;
  if (coverage < 0.6) return 0;
  return 400 + shared * 10 + (coverage * 100).round();
}

/// Levenshtein distance capped at [max] (returns false as soon as it exceeds).
bool _editDistanceWithin(String a, String b, int max) {
  if (a == b) return true;
  if ((a.length - b.length).abs() > max) return false;
  var prev = List<int>.generate(b.length + 1, (i) => i);
  var curr = List<int>.filled(b.length + 1, 0);
  for (var i = 1; i <= a.length; i++) {
    curr[0] = i;
    var rowMin = curr[0];
    for (var j = 1; j <= b.length; j++) {
      final cost = a.codeUnitAt(i - 1) == b.codeUnitAt(j - 1) ? 0 : 1;
      final v = [curr[j - 1] + 1, prev[j] + 1, prev[j - 1] + cost]
          .reduce((x, y) => x < y ? x : y);
      curr[j] = v;
      if (v < rowMin) rowMin = v;
    }
    if (rowMin > max) return false;
    final tmp = prev;
    prev = curr;
    curr = tmp;
  }
  return prev[b.length] <= max;
}

Future<void> _buildIndex() async {
  final found = <SupabaseImageObject>[];
  try {
    final batches = await Future.wait(
      _indexRoots.map(
        (root) => _listTree(
          bucket: root.bucket,
          prefix: root.prefix,
          scope: root.scope,
          depth: root.depth,
        ),
      ),
    );
    for (final batch in batches) {
      found.addAll(batch);
    }
  } catch (e) {
    debugPrint('Supabase image index failed: $e');
  }
  _index = List.unmodifiable(found);
  if (_index.isEmpty) {
    // Public buckets serve files without a policy but do not let the anon key
    // *list* them, and Storage answers 200 with an empty array rather than an
    // error — so say what is missing instead of silently showing placeholders.
    debugPrint(
      'Supabase image index is empty: the anon key cannot list '
      '${SupabaseConfig.photoLibraryBucket} / ${SupabaseConfig.imageBucket}. '
      'Add a SELECT policy on storage.objects for those buckets.',
    );
  } else if (kDebugMode) {
    debugPrint('Supabase image index: ${_index.length} objects');
  }
}

Future<List<SupabaseImageObject>> _listTree({
  required String bucket,
  required String prefix,
  required SupabaseImageScope scope,
  required int depth,
}) async {
  final out = <SupabaseImageObject>[];
  final rows = await _listFolder(bucket, prefix);
  final subfolders = <String>[];

  for (final row in rows) {
    final name = (row['name'] as String?)?.trim() ?? '';
    if (name.isEmpty || name == '.emptyFolderPlaceholder') continue;
    final path = prefix.isEmpty ? name : '$prefix/$name';
    // Supabase returns a null id for synthetic folder rows.
    if (row['id'] == null) {
      subfolders.add(path);
      continue;
    }
    if (!_looksLikeImage(name)) continue;
    final folder = _lastSegment(prefix);
    final base = _stripExtension(name);
    final fileTokens = supabaseImageNameTokens(base);
    out.add(
      SupabaseImageObject(
        bucket: bucket,
        path: path,
        scope: scope,
        folderKey: normalizeSupabaseImageKey(folder),
        fileKey: normalizeSupabaseImageKey(base),
        // Admin uploads are named by timestamp, so fall back to the folder.
        tokens: fileTokens.isEmpty
            ? supabaseImageNameTokens(folder)
            : fileTokens,
      ),
    );
  }

  if (depth > 0 && subfolders.isNotEmpty) {
    final nested = await Future.wait(
      subfolders.map(
        (p) => _listTree(
          bucket: bucket,
          prefix: p,
          scope: scope,
          depth: depth - 1,
        ),
      ),
    );
    for (final batch in nested) {
      out.addAll(batch);
    }
  }
  return out;
}

Future<List<Map<String, dynamic>>> _listFolder(
  String bucket,
  String prefix,
) async {
  final res = await http
      .post(
        Uri.parse('${SupabaseConfig.storageApiBase}/object/list/$bucket'),
        headers: {
          'apikey': SupabaseConfig.anonKey,
          'Authorization': 'Bearer ${SupabaseConfig.anonKey}',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'prefix': prefix,
          'limit': 1000,
          'offset': 0,
          'sortBy': {'column': 'name', 'order': 'asc'},
        }),
      )
      .timeout(const Duration(seconds: 15));

  if (res.statusCode < 200 || res.statusCode >= 300) {
    debugPrint(
      'Supabase list $bucket/$prefix failed (${res.statusCode}): ${res.body}',
    );
    return const [];
  }
  final decoded = jsonDecode(res.body);
  if (decoded is! List) return const [];
  return decoded.whereType<Map<String, dynamic>>().toList(growable: false);
}

bool _looksLikeImage(String fileName) {
  final dot = fileName.lastIndexOf('.');
  if (dot < 0 || dot == fileName.length - 1) return false;
  return _imageExtensions.contains(fileName.substring(dot + 1).toLowerCase());
}

String _stripExtension(String fileName) {
  final dot = fileName.lastIndexOf('.');
  return dot <= 0 ? fileName : fileName.substring(0, dot);
}

String _lastSegment(String path) {
  if (path.isEmpty) return '';
  final i = path.lastIndexOf('/');
  return i < 0 ? path : path.substring(i + 1);
}

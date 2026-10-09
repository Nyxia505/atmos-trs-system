import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/foundation.dart' show debugPrint, kDebugMode, kIsWeb;
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../config/supabase_config.dart';
import '../data.dart'
    show
        FeaturedSpot,
        Municipality,
        TouristSpot,
        findTouristSpotByNameFuzzy;
import '../services/supabase_image_library.dart';
import 'image_from_path_io.dart'
    if (dart.library.html) 'image_from_path_web.dart'
    as impl;

/// Municipality and tourist-spot photos come from **Supabase Storage only**
/// (`tourist-images`). Firestore may still hold old Firebase `imagePath`
/// values; those are ignored. A Supabase HTTPS URL in `imagePath`, `image_url`,
/// or `image` is used as-is; otherwise the photo is looked up by name under
/// `tourist-images/images/` and `tourist-images/municipalities/`.

final Map<String, Future<String?>> _directUrlResolutionCache = {};
final Map<String, Future<String?>> _storagePathResolutionCache = {};

/// Stable futures so FutureBuilder does not reset on every parent rebuild
/// (e.g. home banner autoplay setState).
final Map<String, Future<String?>> _touristSpotImageFutureCache = {};
final Map<String, Future<String?>> _municipalityImageFutureCache = {};

/// Clears in-memory image caches. Call after the catalog reloads or the signed
/// in account changes so Supabase edits are picked up.
void clearTourismImageUrlCache() {
  _directUrlResolutionCache.clear();
  _storagePathResolutionCache.clear();
  _touristSpotImageFutureCache.clear();
  _municipalityImageFutureCache.clear();
  clearSupabaseImageIndex();
}

/// Default decode/cache size (px) for list/card images — smaller bitmaps decode faster (especially on web).
const int kDefaultNetworkImageMemCache = 720;

/// Builds an image widget from a path (Supabase URL, Storage object path, or
/// local file). Shows [fallback] when the source is missing or unreadable.
Widget buildMunicipalityImage(
  String path, {
  required Widget fallback,
  int? memCacheWidth,
  int? memCacheHeight,
}) {
  final normalizedPath = path.trim();
  if (normalizedPath.isEmpty) return fallback;

  // Mobile local file paths (e.g. /data/user/0/...) — not protocol-relative //.
  if (normalizedPath.startsWith('/') && !normalizedPath.startsWith('//')) {
    return impl.buildFileImage(path: normalizedPath, fallback: fallback);
  }
  if (_looksLikeLocalWindowsPath(normalizedPath)) {
    return impl.buildFileImage(path: normalizedPath, fallback: fallback);
  }

  return _resolvedNetworkImage(
    future: _resolveSingleImageSourceToUrl(normalizedPath),
    fallback: fallback,
    memCacheWidth: memCacheWidth,
    memCacheHeight: memCacheHeight,
  );
}

/// Municipality photo from Supabase (`tourist-images/municipalities/…`).
Widget buildMunicipalityImageForMunicipality(
  Municipality municipality, {
  required Widget fallback,
  int? memCacheWidth,
  int? memCacheHeight,
}) {
  return _resolvedNetworkImage(
    future: _resolveMunicipalityImageUrl(municipality),
    fallback: fallback,
    memCacheWidth: memCacheWidth,
    memCacheHeight: memCacheHeight,
  );
}

/// Tourist-spot photo from the Supabase URL stored on the Firestore spot doc.
Widget buildTouristSpotProfileImage(
  TouristSpot spot, {
  required Widget fallback,
  int? memCacheWidth,
  int? memCacheHeight,
}) {
  final mw = memCacheWidth ?? kDefaultNetworkImageMemCache;
  final mh = memCacheHeight ?? kDefaultNetworkImageMemCache;
  final stored = spot.imagePath.trim();
  // Fast path: Firestore `image_url` is already on the model — no FutureBuilder.
  if (stored.startsWith('http://') || stored.startsWith('https://')) {
    return _httpNetworkImage(
      stored,
      fallback: fallback,
      memCacheWidth: mw,
      memCacheHeight: mh,
    );
  }
  if (stored.isEmpty) return fallback;
  return _resolvedNetworkImage(
    future: _resolveTouristSpotImageUrl(spot),
    fallback: fallback,
    memCacheWidth: mw,
    memCacheHeight: mh,
  );
}

/// Picks one [TouristSpot] for a display name (exact or fuzzy match).
TouristSpot? touristSpotByNamePreferringImage(String name) =>
    findTouristSpotByNameFuzzy(name);

/// Featured cards use the matched tourist spot's Firestore `image_url`, or the
/// featured doc's own Supabase URL — no name-based Storage guessing.
Widget buildFeaturedSpotListAvatar(
  FeaturedSpot featured, {
  required Widget fallback,
  int? memCacheWidth,
  int? memCacheHeight,
}) {
  final match = findTouristSpotByNameFuzzy(featured.name);
  if (match != null && match.imagePath.trim().isNotEmpty) {
    return buildTouristSpotProfileImage(
      match,
      fallback: fallback,
      memCacheWidth: memCacheWidth,
      memCacheHeight: memCacheHeight,
    );
  }
  final stored = featured.imagePath.trim();
  if (stored.isNotEmpty &&
      (SupabaseConfig.isSupabaseStorageUrl(stored) ||
          stored.startsWith('http://') ||
          stored.startsWith('https://'))) {
    return buildMunicipalityImage(
      stored,
      fallback: fallback,
      memCacheWidth: memCacheWidth,
      memCacheHeight: memCacheHeight,
    );
  }
  return fallback;
}

// ---------------------------------------------------------------------------
// Resolution — Supabase only for catalog photos
// ---------------------------------------------------------------------------

Future<String?> _resolveMunicipalityImageUrl(Municipality municipality) {
  final key = '${municipality.name}|${municipality.shortName}'
      '|${municipality.imagePath}';
  return _municipalityImageFutureCache.putIfAbsent(key, () async {
    final stored = municipality.imagePath.trim();
    if (stored.isNotEmpty &&
        SupabaseConfig.isSupabaseStorageUrl(stored) &&
        !stored.toLowerCase().contains('oroquieta_city_plaza')) {
      return stored;
    }

    final url = await resolveSupabaseImageUrlForNames(
      [
        municipality.name,
        municipality.shortName,
        ..._extraNamesFromStoredPath(municipality.imagePath),
      ],
      scope: SupabaseImageScope.municipality,
    );
    if (url == null && kDebugMode) {
      debugPrint('No Supabase image for municipality "${municipality.name}"');
    }
    return url;
  });
}

Future<String?> _resolveTouristSpotImageUrl(TouristSpot spot) {
  final key = '${spot.firestoreDocId}|${spot.name}|${spot.imagePath}';
  return _touristSpotImageFutureCache.putIfAbsent(key, () async {
    // [TouristSpot.imagePath] is filled from Firestore `image_url` only
    // (see _touristSpotImagePathFromFirestore) — never from Firebase imagePath.
    final stored = spot.imagePath.trim();
    if (stored.isEmpty) {
      if (kDebugMode) {
        debugPrint('No image_url on Firestore spot "${spot.name}"');
      }
      return null;
    }
    return stored;
  });
}

/// Useful name fragments from a stored path or legacy Firebase download URL.
///
/// Examples:
/// - `Tourist Spots Image/lake_duminagat` → `lake_duminagat`
/// - `…/o/Tourist%20Spots%20Image%2Famorap%2F123.jpg?alt=media` → `amorap`
List<String> _extraNamesFromStoredPath(String raw) {
  final t = raw.trim();
  if (t.isEmpty || t.contains(':\\')) return const [];

  var path = t;
  if (t.startsWith('http://') || t.startsWith('https://')) {
    final m = RegExp(r'/o/([^?]+)').firstMatch(t);
    if (m == null) return const [];
    path = Uri.decodeComponent(m.group(1)!);
  }

  final segments = path
      .replaceAll('\\', '/')
      .split('/')
      .map((s) => s.trim())
      .where((s) => s.isNotEmpty)
      .toList();
  if (segments.isEmpty) return const [];

  final out = <String>[];
  void add(String s) {
    final cleaned = s.replaceAll(RegExp(r'\.[a-zA-Z0-9]{2,5}$'), '').trim();
    if (cleaned.isEmpty) return;
    // Skip upload timestamps like 1776509381333.
    if (RegExp(r'^\d{10,}$').hasMatch(cleaned)) return;
    if (out.any((o) => o.toLowerCase() == cleaned.toLowerCase())) return;
    out.add(cleaned);
  }

  // Prefer the folder under "Tourist Spots Image" / tourist-spots when present.
  for (var i = 0; i < segments.length; i++) {
    final seg = segments[i].toLowerCase().replaceAll(' ', '');
    if (seg == 'touristspotsimage' ||
        seg == 'tourist-spots' ||
        seg == 'touristspots' ||
        seg == 'municipalities' ||
        seg == 'images') {
      if (i + 1 < segments.length) add(segments[i + 1]);
    }
  }
  add(segments.last);
  if (segments.length >= 2) add(segments[segments.length - 2]);
  return out;
}

/// Turns one stored image source into a displayable URL, or null when it is
/// empty, unusable, or points at storage that no longer serves images.
Future<String?> _resolveSingleImageSourceToUrl(String raw) async {
  final t = raw.trim();
  if (t.isEmpty) return null;
  if (t.startsWith('/') && !t.startsWith('//')) return null;
  if (_looksLikeLocalWindowsPath(t)) return null;

  final direct = _normalizeDirectUrl(t);
  if (direct != null) return _resolveDirectUrlCached(direct);

  // `gs://bucket/object/path` — keep the object path, drop the bucket.
  if (t.startsWith('gs://')) {
    final rest = t.substring('gs://'.length);
    final slash = rest.indexOf('/');
    if (slash < 0 || slash == rest.length - 1) return null;
    return _resolveStorageObjectPathCached(rest.substring(slash + 1));
  }

  if (t.contains('/')) return _resolveStorageObjectPathCached(t);
  return null;
}

bool _isFirebaseStorageUrl(String url) {
  final u = url.toLowerCase();
  return u.contains('firebasestorage.googleapis.com') ||
      u.contains('firebasestorage.app') ||
      u.contains('googleapis.com/storage');
}

/// Validates a direct HTTPS URL. Supabase links are trusted as-is; anything
/// else is probed once so a dead link shows the placeholder instead of a
/// broken-image error.
Future<String?> _resolveDirectUrlCached(String url) {
  final key = url.trim();
  return _directUrlResolutionCache.putIfAbsent(key, () async {
    if (SupabaseConfig.isSupabaseStorageUrl(key)) return key;
    if (key.startsWith('blob:')) return key;
    // Firebase Storage quota is exceeded on this project — skip probing every
    // legacy download URL (they all fail and stall the UI).
    if (_isFirebaseStorageUrl(key)) return null;
    final ok = await _remoteUrlServesImage(key);
    if (!ok) {
      if (kDebugMode) debugPrint('Image URL does not serve an image: $key');
      return null;
    }
    return key;
  });
}

/// Resolves a bare object path against the public Supabase buckets.
Future<String?> _resolveStorageObjectPathCached(String rawPath) {
  final key = rawPath.trim();
  return _storagePathResolutionCache.putIfAbsent(key, () async {
    for (final candidate in _supabaseObjectCandidates(key)) {
      final url = SupabaseConfig.publicObjectUrl(
        candidate.bucket,
        candidate.path,
      );
      if (await _remoteUrlServesImage(url)) return url;
    }
    return null;
  });
}

class _BucketObject {
  final String bucket;
  final String path;
  const _BucketObject(this.bucket, this.path);
}

/// Bucket/object pairs to try for a stored path, most likely first.
List<_BucketObject> _supabaseObjectCandidates(String rawPath) {
  var path = rawPath.replaceAll('\\', '/');
  path = path.replaceAll(RegExp(r'^/+|/+$'), '');
  if (path.isEmpty) return const [];

  // Only a path ending in an image file can be fetched directly; folder-style
  // paths are handled by the name index instead.
  if (!RegExp(r'\.(jpe?g|png|webp|gif|bmp|heic)$', caseSensitive: false)
      .hasMatch(path)) {
    return const [];
  }

  final out = <_BucketObject>[];
  void add(String bucket, String p) {
    if (p.isEmpty) return;
    if (out.any((o) => o.bucket == bucket && o.path == p)) return;
    out.add(_BucketObject(bucket, p));
  }

  // A path may already start with a bucket name.
  for (final bucket in const [
    SupabaseConfig.imageBucket,
    SupabaseConfig.photoLibraryBucket,
  ]) {
    if (path.startsWith('$bucket/')) {
      add(bucket, path.substring(bucket.length + 1));
    }
  }
  add(SupabaseConfig.imageBucket, path);
  add(SupabaseConfig.photoLibraryBucket, path);
  return out;
}

/// False when the URL answers with an error page or JSON instead of an image.
Future<bool> _remoteUrlServesImage(String url) async {
  try {
    final uri = Uri.parse(url);
    var res = await http.head(uri).timeout(const Duration(seconds: 6));
    if (res.statusCode == 405 || res.statusCode == 501) {
      res = await http
          .get(uri, headers: {'Range': 'bytes=0-63'})
          .timeout(const Duration(seconds: 8));
    }
    if (res.statusCode < 200 || res.statusCode >= 300) return false;
    final ct = (res.headers['content-type'] ?? '').toLowerCase();
    if (ct.contains('application/json') || ct.contains('text/html')) {
      return false;
    }
    return ct.startsWith('image/') || ct.isEmpty || res.statusCode == 206;
  } catch (e) {
    if (kDebugMode) debugPrint('Image probe failed for $url: $e');
    return false;
  }
}

bool _looksLikeLocalWindowsPath(String path) => path.contains(r':\');

String? _normalizeDirectUrl(String path) {
  final trimmed = path.trim();
  if (trimmed.isEmpty) return null;
  final lower = trimmed.toLowerCase();
  if (trimmed.startsWith('blob:')) return trimmed;
  if (lower.startsWith('https://')) return trimmed.replaceAll(' ', '%20');
  if (lower.startsWith('http://')) {
    return 'https://${trimmed.substring('http://'.length)}'.replaceAll(
      ' ',
      '%20',
    );
  }
  if (trimmed.startsWith('//')) {
    return 'https:${trimmed.replaceAll(' ', '%20')}';
  }
  if (lower.startsWith('www.')) {
    return 'https://${trimmed.replaceAll(' ', '%20')}';
  }
  return null;
}

// ---------------------------------------------------------------------------
// Rendering
// ---------------------------------------------------------------------------

/// Shows a spinner while [future] resolves, the image once it does, and
/// [fallback] when no image is available.
Widget _resolvedNetworkImage({
  required Future<String?> future,
  required Widget fallback,
  int? memCacheWidth,
  int? memCacheHeight,
}) {
  final mw = memCacheWidth ?? kDefaultNetworkImageMemCache;
  final mh = memCacheHeight ?? kDefaultNetworkImageMemCache;
  return FutureBuilder<String?>(
    future: future,
    builder: (context, snapshot) {
      if (snapshot.connectionState == ConnectionState.waiting &&
          !snapshot.hasData) {
        return _imageLoadingPlaceholder();
      }
      final url = snapshot.data;
      if (url == null || url.isEmpty) return fallback;
      return _httpNetworkImage(
        url,
        fallback: fallback,
        memCacheWidth: mw,
        memCacheHeight: mh,
      );
    },
  );
}

Widget _imageLoadingPlaceholder() {
  return const Center(
    child: SizedBox(
      width: 22,
      height: 22,
      child: CircularProgressIndicator(strokeWidth: 2),
    ),
  );
}

Widget _httpNetworkImage(
  String url, {
  required Widget fallback,
  required int memCacheWidth,
  required int memCacheHeight,
}) {
  // Skip known-corrupt Storage objects (web decoder throws EncodingError).
  if (url.toLowerCase().contains('oroquieta_city_plaza.jpeg') ||
      url.toLowerCase().contains('oroquieta_city_plaza.jpg')) {
    return fallback;
  }

  // Web: use the HTML <img> element so Storage URLs display without CORS.
  if (kIsWeb) {
    return Image.network(
      url,
      width: double.infinity,
      height: double.infinity,
      fit: BoxFit.cover,
      filterQuality: FilterQuality.low,
      cacheWidth: memCacheWidth,
      cacheHeight: memCacheHeight,
      webHtmlElementStrategy: WebHtmlElementStrategy.prefer,
      errorBuilder: (context, error, stack) {
        if (kDebugMode) {
          debugPrint('Image.network failed: $url → $error');
        }
        return fallback;
      },
      loadingBuilder: (context, child, progress) {
        if (progress == null) return child;
        return fallback;
      },
    );
  }
  return CachedNetworkImage(
    imageUrl: url,
    width: double.infinity,
    height: double.infinity,
    fit: BoxFit.cover,
    memCacheWidth: memCacheWidth,
    memCacheHeight: memCacheHeight,
    maxWidthDiskCache: memCacheWidth,
    maxHeightDiskCache: memCacheHeight,
    fadeInDuration: Duration.zero,
    fadeOutDuration: Duration.zero,
    filterQuality: FilterQuality.medium,
    placeholder: (context, url) => _imageLoadingPlaceholder(),
    errorWidget: (context, url, error) => fallback,
  );
}

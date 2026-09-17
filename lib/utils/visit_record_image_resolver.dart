import 'package:atmos_trs_system/config/supabase_storage_config.dart';
import 'package:atmos_trs_system/data/tourist_spot_image_catalog.dart';
import 'package:atmos_trs_system/models/tourist_spot_firestore.dart';
import 'package:atmos_trs_system/services/user_activity_service.dart';
import 'package:atmos_trs_system/services/tourist_spots_repository.dart';
import 'package:atmos_trs_system/utils/municipality_helper.dart';

/// Thumbnails for municipalities and well-known spot doc ids.
Map<String, String> get kMisOccAttractionAssetImages =>
    TouristSpotImageCatalog.kMunicipalityAssetById;

/// Resolves a display image for a persisted visit (assets, Firestore spots, LGU municipalities).
class VisitRecordImageResolver {
  VisitRecordImageResolver._();

  static String _normalizeKey(String raw) {
    return raw.trim().toLowerCase().replaceAll(RegExp(r'[\s\-]+'), '_');
  }

  static String? _assetForKey(String key) {
    if (key.isEmpty) return null;
    final direct = TouristSpotImageCatalog.bundledAssetFor(spotId: key);
    if (direct != null) return SupabaseStorageConfig.resolve(direct);

    final normalized = _normalizeKey(key);
    final normHit = TouristSpotImageCatalog.bundledAssetFor(spotId: normalized);
    if (normHit != null) return SupabaseStorageConfig.resolve(normHit);

    for (final e in kMisOccAttractionAssetImages.entries) {
      if (normalized.contains(e.key) || e.key.contains(normalized)) {
        return SupabaseStorageConfig.resolve(e.value);
      }
    }
    return null;
  }

  static String? _municipalityAssetForVisit(VisitRecord entry) {
    var mid = entry.spotId.trim().toLowerCase();
    if (mid.startsWith('lgu_')) {
      mid = mid.substring(4);
    }
    mid = normalizeMunicipalityId(mid);
    if (mid.isEmpty) {
      mid = getMunicipalityIdFromName(entry.spotName);
    }
    if (mid.isEmpty && entry.category.toUpperCase() != 'LGU') {
      mid = getMunicipalityIdFromName(entry.category);
    }
    if (mid.isEmpty) return null;

    for (final q in municipalityIdsForQuery(mid)) {
      final hit = _assetForKey(q);
      if (hit != null) return hit;
    }
    return null;
  }

  static String? _imageFromSpotList(
    VisitRecord entry,
    List<TouristSpotFirestore> spots,
  ) {
    if (spots.isEmpty) return null;

    for (final s in spots) {
      if (s.id == entry.spotId ||
          _normalizeKey(s.id) == _normalizeKey(entry.spotId)) {
        final img = _spotImageFromFirestoreSpot(s);
        if (img != null) return img;
      }
    }

    final nameLower = entry.spotName.trim().toLowerCase();
    if (nameLower.isEmpty) return null;

    for (final s in spots) {
      final sn = s.name.trim().toLowerCase();
      if (sn.isEmpty) continue;
      if (nameLower.contains(sn) || sn.contains(nameLower)) {
        final img = _spotImageFromFirestoreSpot(s);
        if (img != null) return img;
      }
    }
    return null;
  }

  static String? _spotImageFromFirestoreSpot(TouristSpotFirestore spot) {
    return TouristSpotImageCatalog.displayUrlForSpot(spot);
  }

  /// Synchronous resolve using cached spot list (Firestore + local fallback).
  static String resolve(
    VisitRecord entry, {
    List<TouristSpotFirestore> spots = const [],
  }) {
    final stored = entry.imageUrl?.trim();
    if (stored != null &&
        stored.isNotEmpty &&
        TouristSpotImageCatalog.isValidDisplayUrl(stored)) {
      return SupabaseStorageConfig.resolve(stored);
    }

    final fromList = _imageFromSpotList(entry, spots);
    if (fromList != null && fromList.isNotEmpty) return fromList;

    final mun = _municipalityAssetForVisit(entry);
    if (mun != null) return mun;

    final fromSpotId = _assetForKey(entry.spotId);
    if (fromSpotId != null) return fromSpotId;

    return TouristSpotImageCatalog.displayUrl(
      preferred: stored,
      spotId: entry.spotId,
      spotName: entry.spotName,
      category: entry.category,
    );
  }

  /// Image for a municipality LGU check-in (before visit is saved).
  static String? imageForMunicipalityId(String municipalityId) {
    final mid = normalizeMunicipalityId(municipalityId);
    if (mid.isEmpty) return null;
    for (final q in municipalityIdsForQuery(mid)) {
      final hit = _assetForKey(q);
      if (hit != null) return hit;
    }
    final bundled =
        TouristSpotImageCatalog.bundledAssetFor(municipalityId: mid);
    return bundled == null ? null : SupabaseStorageConfig.resolve(bundled);
  }

  /// Thumbnail when saving a new QR check-in visit.
  static String imageForCheckIn({
    required String spotId,
    String? spotName,
    String? category,
    String? municipalityId,
    List<TouristSpotFirestore> spots = const [],
  }) {
    final sid = spotId.trim().toLowerCase();
    if (sid.startsWith('lgu_')) {
      return imageForMunicipalityId(sid.substring(4)) ??
          TouristSpotImageCatalog.displayUrl(
            spotId: spotId,
            spotName: spotName,
            category: category,
          );
    }
    final mid = normalizeMunicipalityId(municipalityId);
    if (mid.isNotEmpty) {
      final mun = imageForMunicipalityId(mid);
      if (mun != null) return mun;
    }
    return resolve(
      VisitRecord(
        spotId: spotId,
        spotName: (spotName ?? spotId).trim(),
        category: (category ?? 'Spot').trim(),
        visitedAt: DateTime.now(),
      ),
      spots: spots,
    );
  }

  /// Fills missing or broken [VisitRecord.imageUrl] and optionally persists.
  static Future<List<VisitRecord>> enrichAndPersist(
    List<VisitRecord> visits, {
    List<TouristSpotFirestore> spots = const [],
    bool persist = true,
  }) async {
    if (visits.isEmpty) return visits;

    var spotList = spots;
    if (spotList.isEmpty) {
      spotList = await TouristSpotsRepository.getTouristSpots();
    }

    final enriched = <VisitRecord>[];
    var changed = false;
    for (final v in visits) {
      TouristSpotFirestore? matched;
      for (final s in spotList) {
        if (s.id == v.spotId ||
            _normalizeKey(s.id) == _normalizeKey(v.spotId)) {
          matched = s;
          break;
        }
      }

      final existing = v.imageUrl?.trim();
      final img = resolve(v, spots: spotList);
      final nextName = matched != null && matched.name.trim().isNotEmpty
          ? matched.name.trim()
          : v.spotName;
      final nextCategory = matched != null && matched.category.trim().isNotEmpty
          ? matched.category.trim()
          : v.category;

      final nameChanged = nextName != v.spotName;
      final categoryChanged = nextCategory != v.category;
      final imageChanged = img.isNotEmpty &&
          (existing == null ||
              existing.isEmpty ||
              !TouristSpotImageCatalog.isValidDisplayUrl(existing)) &&
          img != existing;

      if (!nameChanged && !categoryChanged && !imageChanged) {
        enriched.add(v);
        continue;
      }

      changed = true;
      enriched.add(
        v.copyWith(
          spotName: nextName,
          category: nextCategory,
          imageUrl: imageChanged ? img : v.imageUrl,
        ),
      );
    }

    if (persist && changed) {
      await UserActivityService.replaceVisitedSpots(enriched);
    }

    return enriched;
  }
}

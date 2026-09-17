import 'package:atmos_trs_system/config/vr_tour_config.dart';
import 'package:atmos_trs_system/data/tourist_spot_image_catalog.dart';
import 'package:atmos_trs_system/data/tourist_spots_default_seed.dart';
import 'package:atmos_trs_system/models/tourist_spot_firestore.dart';
import 'package:atmos_trs_system/utils/municipality_helper.dart';

/// Canonical 17 LGU destinations for home Featured / All Places and Explore map.
class MisamisOccidentalDisplaySpots {
  MisamisOccidentalDisplaySpots._();

  /// Legacy UI ids used in featured carousel and saved spots.
  static const Map<String, String> _legacyAliasToMunicipalityId = {
    'oroquieta_city': 'oroquieta',
    'oroquieta_city_plaza': 'oroquieta',
    'ozamis_city': 'ozamiz',
    'tangub_city': 'tangub',
    'don_victoriano': 'dvc',
    'sapang_dalaga': 'sapangdalaga',
    'lopez_jaena': 'lopezjaena',
    'sinacaban': 'sinacaban',
    'amorap': 'sinacaban',
  };

  static TouristSpotFirestore fromSeed(DefaultTouristSpotSeed seed) {
    final image = TouristSpotImageCatalog.displayUrl(
      preferred: seed.imageUrl,
      spotId: seed.docId,
      municipalityId: seed.municipalityId,
      spotName: seed.name,
      category: seed.category,
    );
    return TouristSpotFirestore(
      id: seed.docId,
      name: seed.name,
      category: seed.category,
      latitude: seed.latitude,
      longitude: seed.longitude,
      rating: seed.rating,
      image: image,
      description: seed.description,
      municipality: seed.municipality,
      municipalityId: seed.municipalityId,
      vrLink: resolveVrTourUrl(
            vrLink: seed.vrLink,
            spotId: seed.docId,
            spotName: seed.name,
          ) ??
          seed.vrLink ??
          '',
      qrValue: seed.docId,
    );
  }

  /// One flagship spot per city/municipality with bundled images.
  static List<TouristSpotFirestore> fromSeeds() {
    return kDefaultTouristSpotSeeds.map(fromSeed).toList();
  }

  static String _resolveImage(
    TouristSpotFirestore remote,
    TouristSpotFirestore sample,
  ) {
    final bundled = TouristSpotImageCatalog.bundledAssetFor(
      spotId: sample.id,
      municipalityId: sample.municipalityId,
      spotName: sample.name,
    );
    if (bundled != null) {
      return TouristSpotImageCatalog.displayUrl(preferred: bundled);
    }
    return TouristSpotImageCatalog.displayUrlForSpot(remote);
  }

  static TouristSpotFirestore _mergeRemote(
    TouristSpotFirestore sample,
    TouristSpotFirestore remote,
  ) {
    return TouristSpotFirestore(
      id: sample.id,
      name: remote.name.isNotEmpty ? remote.name : sample.name,
      category: remote.category.isNotEmpty ? remote.category : sample.category,
      latitude: remote.latitude != 0.0 ? remote.latitude : sample.latitude,
      longitude: remote.longitude != 0.0 ? remote.longitude : sample.longitude,
      image: _resolveImage(remote, sample),
      rating: remote.rating != 0.0 ? remote.rating : sample.rating,
      description:
          remote.description.isNotEmpty ? remote.description : sample.description,
      municipality: remote.municipality.isNotEmpty
          ? remote.municipality
          : sample.municipality,
      municipalityId: remote.municipalityId.isNotEmpty
          ? remote.municipalityId
          : sample.municipalityId,
      vrLink: resolveVrTourUrl(
            vrLink: (remote.vrLink != null && remote.vrLink!.trim().isNotEmpty)
                ? remote.vrLink
                : sample.vrLink,
            spotId: sample.id,
            spotName: remote.name.isNotEmpty ? remote.name : sample.name,
          ) ??
          sample.vrLink,
      qrValue: remote.qrValue.isNotEmpty ? remote.qrValue : sample.qrValue,
      qrPayload: remote.qrPayload ?? sample.qrPayload,
    );
  }

  /// Merges Firestore `tourist_spots` into the 17 canonical LGU rows.
  static List<TouristSpotFirestore> mergeWithFirestore(
    List<TouristSpotFirestore> firestoreSpots,
  ) {
    final base = fromSeeds();
    if (firestoreSpots.isEmpty) return base;

    final byDocId = {for (final s in firestoreSpots) s.id: s};
    final byMunicipality = <String, TouristSpotFirestore>{};
    for (final s in firestoreSpots) {
      var mid = normalizeMunicipalityId(s.municipalityId);
      if (mid.isEmpty) {
        mid = getMunicipalityIdFromName(s.municipality);
      }
      if (mid.isEmpty) {
        mid = getMunicipalityIdFromName(s.name);
      }
      if (mid.isNotEmpty) {
        byMunicipality.putIfAbsent(mid, () => s);
      }
    }

    return base.map((sample) {
      final mid = normalizeMunicipalityId(sample.municipalityId);
      final remote = byDocId[sample.id] ?? byMunicipality[mid];
      if (remote == null) return sample;
      return _mergeRemote(sample, remote);
    }).toList();
  }

  /// Lookup map for featured ids, doc ids, and municipality aliases.
  static Map<String, TouristSpotFirestore> buildKnownSpotsMap({
    List<TouristSpotFirestore> firestoreSpots = const [],
    Iterable<Map<String, dynamic>> featuredDestinations = const [],
  }) {
    final map = <String, TouristSpotFirestore>{};
    void put(String key, TouristSpotFirestore spot) {
      final k = key.trim();
      if (k.isEmpty) return;
      map[k] = spot;
    }

    for (final spot in mergeWithFirestore(firestoreSpots)) {
      put(spot.id, spot);
      put(spot.municipalityId, spot);
      for (final q in municipalityIdsForQuery(spot.municipalityId)) {
        put(q, spot);
      }
    }

    for (final entry in _legacyAliasToMunicipalityId.entries) {
      final hit = map[entry.value];
      if (hit != null) put(entry.key, hit);
    }

    for (final d in featuredDestinations) {
      final spotId = d['spotId']?.toString() ?? '';
      if (spotId.isEmpty) continue;
      final existing = map[spotId];
      if (existing != null) continue;
      final mid = _legacyAliasToMunicipalityId[spotId] ?? spotId;
      final fromMid = map[mid] ?? map[normalizeMunicipalityId(mid)];
      if (fromMid != null) {
        put(spotId, fromMid);
        continue;
      }
      put(
        spotId,
        TouristSpotFirestore(
          id: spotId,
          name: d['name']?.toString() ?? spotId,
          category: d['category']?.toString() ?? 'Spot',
          latitude: (d['latitude'] as num?)?.toDouble() ?? 0,
          longitude: (d['longitude'] as num?)?.toDouble() ?? 0,
          rating: (d['rating'] as num?)?.toDouble() ?? 4.5,
          image: TouristSpotImageCatalog.displayUrl(
            spotId: spotId,
            spotName: d['name']?.toString(),
            category: d['category']?.toString(),
          ),
          municipality: d['location']?.toString() ?? '',
          municipalityId: mid,
          vrLink: '',
        ),
      );
    }

    return map;
  }

  static TouristSpotFirestore? findByAnyId(
    String spotId, {
    List<TouristSpotFirestore> firestoreSpots = const [],
    Iterable<Map<String, dynamic>> featuredDestinations = const [],
  }) {
    final map = buildKnownSpotsMap(
      firestoreSpots: firestoreSpots,
      featuredDestinations: featuredDestinations,
    );
    final direct = map[spotId];
    if (direct != null) return direct;
    final mid = _legacyAliasToMunicipalityId[spotId] ?? spotId;
    return map[mid] ?? map[normalizeMunicipalityId(mid)];
  }
}

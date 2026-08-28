import 'package:atmos_trs_system/data/tourist_spots_default_seed.dart';
import 'package:atmos_trs_system/features/explore/explore_data.dart' show kMockSpots;
import 'package:atmos_trs_system/models/tourist_spot_firestore.dart';
import 'package:atmos_trs_system/utils/municipality_helper.dart';

/// Bundled Misamis Occidental images under [assets/images/].
abstract final class MisamisOccidentalImages {
  static const String kPrefix = 'assets/images/';

  static const String landingBg = '${kPrefix}landing_page_bg.jpg';
  static const String oroquietaPlaza = '${kPrefix}oroquieta City plaza.jpeg';
  static const String ozamisCity = '${kPrefix}ozamis city.webp';
  static const String cottaFortShrine = '${kPrefix}Cotta Fort & Shrine.jpg';
  static const String immaculateConceptionCathedral =
      '${kPrefix}Immaculate Conception Cathedral.webp';
  static const String cottaBeach = '${kPrefix}Cotta Beach.jpg';
  static const String asensoGlobalGarden = '${kPrefix}Asenso Global Garden 1.png';
  static const String aloran = '${kPrefix}aloran.jpg';
  static const String baliangao = '${kPrefix}Baliangao - Cabgan Island.jpg';
  static const String calamba = '${kPrefix}Calamba.jpg';
  static const String clarin = '${kPrefix}clarin.jpg';
  static const String lakeDuminagat = '${kPrefix}lake_duminagat.webp';
  static const String concepcion = '${kPrefix}conception.png';
  static const String piduanFalls = '${kPrefix}Piduan Falls Donvic.jpg';
  static const String jimenezChurch =
      '${kPrefix}Jimenez - St. John the Baptist Church.jpg';
  static const String lopezJaena = '${kPrefix}Lopez Jaena.jpg';
  static const String panaon = '${kPrefix}Panaon.png';
  static const String plaridel = '${kPrefix}PLARIDEL.jpg';
  static const String sapangDalaga = '${kPrefix}Sapang Dalaga.png';
  static const String amorap = '${kPrefix}AMORAP.jpg';
  static const String tudela = '${kPrefix}Tudela Village.webp';
  static const String capitol = '${kPrefix}capitol.webp';
  static const String elTriunfo = '${kPrefix}el triunfo.png';
  static const String lumantas = '${kPrefix}lumantas river side garden.webp';
  static const String barkoBarko = '${kPrefix}barko-barko villaflor.webp';
  static const String tripplan = '${kPrefix}tripplan.png';
}

/// Local image paths / URLs for tourist spots and municipalities.
class TouristSpotImageCatalog {
  TouristSpotImageCatalog._();

  static const String kDefaultAsset = MisamisOccidentalImages.landingBg;

  /// Legacy network fallbacks (used only when no bundled asset exists).
  static const String kPlaceholderNetwork =
      'https://images.unsplash.com/photo-1506905925346-21bda4d32df4?w=800&q=80';

  static const String kBeachNetwork =
      'https://images.unsplash.com/photo-1507525428034-b723cf961d3e?w=800&q=80';

  static const String kMountainNetwork =
      'https://images.unsplash.com/photo-1464822759023-fed622ff2c3b?w=800&q=80';

  static const String kParkNetwork =
      'https://images.unsplash.com/photo-1519331375858-ce4b01699d96?w=800&q=80';

  static const String kHistoricalNetwork =
      'https://images.unsplash.com/photo-1471922694854-ff1b63b20054?w=800&q=80';

  static const String kFallsNetwork =
      'https://images.unsplash.com/photo-1432405972618-d60bd74db5c5?w=800&q=80';

  static const String kResortNetwork =
      'https://images.unsplash.com/photo-1510414842594-a61c69b5ae57?w=800&q=80';

  static const String kCityNetwork =
      'https://images.unsplash.com/photo-1514565131-fce0801e5785?w=800&q=80';

  /// City / municipality → bundled asset (17 LGUs + common spot ids).
  static const Map<String, String> kMunicipalityAssetById = {
    'oroquieta': MisamisOccidentalImages.oroquietaPlaza,
    'oroquieta_city': MisamisOccidentalImages.oroquietaPlaza,
    'oroquieta_city_plaza': MisamisOccidentalImages.oroquietaPlaza,
    'oroquieta_city_boulevard_and_peoples_park':
        MisamisOccidentalImages.oroquietaPlaza,
    'ozamiz': MisamisOccidentalImages.ozamisCity,
    'ozamis': MisamisOccidentalImages.ozamisCity,
    'ozamis_city': MisamisOccidentalImages.ozamisCity,
    'ozamiz_asenso_wellness_park': MisamisOccidentalImages.ozamisCity,
    'ozamiz_cotta_fort_shrine': MisamisOccidentalImages.cottaFortShrine,
    'ozamiz_immaculate_conception_cathedral':
        MisamisOccidentalImages.immaculateConceptionCathedral,
    'ozamiz_cotta_beach': MisamisOccidentalImages.cottaBeach,
    'ozamiz_cotta_fort_wellness_park': MisamisOccidentalImages.cottaFortShrine,
    'tangub': MisamisOccidentalImages.asensoGlobalGarden,
    'tangub_city': MisamisOccidentalImages.asensoGlobalGarden,
    'tangub_asenso_global_gardens': MisamisOccidentalImages.asensoGlobalGarden,
    'aloran': MisamisOccidentalImages.aloran,
    'aloran_viewpoint': MisamisOccidentalImages.aloran,
    'baliangao': MisamisOccidentalImages.baliangao,
    'bless_amare_sunrise_beach': MisamisOccidentalImages.baliangao,
    'baliangao_protected_landscape': MisamisOccidentalImages.baliangao,
    'bonifacio': MisamisOccidentalImages.calamba,
    'bonifacio_mountain_overlook': MisamisOccidentalImages.calamba,
    'calamba': MisamisOccidentalImages.calamba,
    'calamba_green_hills': MisamisOccidentalImages.calamba,
    'clarin': MisamisOccidentalImages.clarin,
    'clarin_lake_duminagat': MisamisOccidentalImages.lakeDuminagat,
    'concepcion': MisamisOccidentalImages.concepcion,
    'concepcion_falls': MisamisOccidentalImages.concepcion,
    'dvc': MisamisOccidentalImages.piduanFalls,
    'don_victoriano': MisamisOccidentalImages.piduanFalls,
    'piduan_falls': MisamisOccidentalImages.piduanFalls,
    'dvc_mount_malindang_natural_park': MisamisOccidentalImages.piduanFalls,
    'jimenez': MisamisOccidentalImages.jimenezChurch,
    'jimenez_st_john_the_baptist_church': MisamisOccidentalImages.jimenezChurch,
    'lopezjaena': MisamisOccidentalImages.lopezJaena,
    'lopez_jaena': MisamisOccidentalImages.lopezJaena,
    'lopez_jaena_beachfront': MisamisOccidentalImages.lopezJaena,
    'panaon': MisamisOccidentalImages.panaon,
    'panaon_seaside': MisamisOccidentalImages.panaon,
    'plaridel': MisamisOccidentalImages.plaridel,
    'plaridel_resort': MisamisOccidentalImages.plaridel,
    'sapang_dalaga': MisamisOccidentalImages.sapangDalaga,
    'sapangdalaga': MisamisOccidentalImages.sapangDalaga,
    'sapang_dalaga_floating_cottages': MisamisOccidentalImages.sapangDalaga,
    'sinacaban': MisamisOccidentalImages.amorap,
    'amorap': MisamisOccidentalImages.amorap,
    'sinacaban_asenso_aquamarine_park': MisamisOccidentalImages.amorap,
    'tudela': MisamisOccidentalImages.tudela,
    'tudela_highland_resort_eco_park': MisamisOccidentalImages.tudela,
    'capitol': MisamisOccidentalImages.capitol,
    'misocc_capitol': MisamisOccidentalImages.capitol,
    'el_triunfo_beach': MisamisOccidentalImages.elTriunfo,
    'el_triungo_beach': MisamisOccidentalImages.elTriunfo,
    'lumantas_riverside': MisamisOccidentalImages.lumantas,
    'triplan_hub': MisamisOccidentalImages.tripplan,
  };

  static Map<String, String>? _byDocId;
  static Map<String, String>? _byMunicipalityId;

  static Map<String, String> get byDocId {
    _byDocId ??= _buildDocMap();
    return _byDocId!;
  }

  static Map<String, String> get byMunicipalityId {
    _byMunicipalityId ??= _buildMunicipalityMap();
    return _byMunicipalityId!;
  }

  static void _put(Map<String, String> map, String key, String? url) {
    final k = key.trim();
    final u = url?.trim() ?? '';
    if (k.isEmpty || u.isEmpty) return;
    map.putIfAbsent(k, () => u);
    final slug = _slug(k);
    if (slug.isNotEmpty) map.putIfAbsent(slug, () => u);
  }

  static Map<String, String> _buildDocMap() {
    final map = <String, String>{};
    for (final e in kMunicipalityAssetById.entries) {
      _put(map, e.key, e.value);
    }
    for (final seed in kDefaultTouristSpotSeeds) {
      _put(map, seed.docId, seed.imageUrl);
      _put(map, seed.municipalityId, seed.imageUrl);
    }
    for (final spot in kMockSpots) {
      final img = spot.imageUrl.trim();
      if (img.startsWith('assets/images/')) {
        _put(map, spot.id, img);
        _put(map, spot.name, img);
      }
    }
    return map;
  }

  static Map<String, String> _buildMunicipalityMap() {
    final map = <String, String>{};
    for (final e in kMunicipalityAssetById.entries) {
      final mid = normalizeMunicipalityId(e.key);
      if (mid.isNotEmpty) map.putIfAbsent(mid, () => e.value);
    }
    for (final seed in kDefaultTouristSpotSeeds) {
      final mid = normalizeMunicipalityId(seed.municipalityId);
      final img = seed.imageUrl?.trim();
      if (mid.isNotEmpty && img != null && img.isNotEmpty) {
        map.putIfAbsent(mid, () => img);
      }
    }
    return map;
  }

  static String _slug(String raw) {
    return raw
        .trim()
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
        .replaceAll(RegExp(r'_+'), '_')
        .replaceAll(RegExp(r'^_|_$'), '');
  }

  /// Decode over-encoded paths and normalize to a valid Flutter asset key.
  static String normalizeAssetPath(String? raw) {
    var u = raw?.trim() ?? '';
    if (u.isEmpty) return u;

    while (u.contains('%')) {
      try {
        final decoded = Uri.decodeComponent(u);
        if (decoded == u) break;
        u = decoded;
      } catch (_) {
        break;
      }
    }

    if (u.startsWith('assets/assets/')) {
      u = u.substring('assets/'.length);
    }

    if (u.startsWith('http://') || u.startsWith('https://')) return u;

    if (!u.startsWith('assets/')) {
      u = u.startsWith('images/')
          ? 'assets/$u'
          : '${MisamisOccidentalImages.kPrefix}$u';
    }

    return u;
  }

  /// Whether [url] can be shown without falling back.
  static bool isValidDisplayUrl(String? url) {
    final u = url?.trim() ?? '';
    if (u.isEmpty) return false;
    if (u.startsWith('http://') || u.startsWith('https://')) return true;
    if (u.startsWith(MisamisOccidentalImages.kPrefix)) return true;
    return false;
  }

  /// Bundled asset for a municipality or spot id (no network).
  static String? bundledAssetFor({
    String? spotId,
    String? municipalityId,
    String? spotName,
  }) {
    final sid = spotId?.trim() ?? '';
    if (sid.isNotEmpty) {
      final direct = kMunicipalityAssetById[sid] ??
          kMunicipalityAssetById[_slug(sid)];
      if (direct != null) return direct;
      final fromDoc = byDocId[sid] ?? byDocId[_slug(sid)];
      if (fromDoc != null && fromDoc.startsWith(MisamisOccidentalImages.kPrefix)) {
        return fromDoc;
      }
    }

    final name = spotName?.trim() ?? '';
    if (name.isNotEmpty) {
      final fromName = byDocId[_slug(name)];
      if (fromName != null &&
          fromName.startsWith(MisamisOccidentalImages.kPrefix)) {
        return fromName;
      }
    }

    final mid = normalizeMunicipalityId(
      municipalityId ?? getMunicipalityIdFromName(spotName),
    );
    if (mid.isNotEmpty) {
      return byMunicipalityId[mid] ?? kMunicipalityAssetById[mid];
    }
    return null;
  }

  /// Firebase / network URL from a spot model (no catalog fallback).
  static String? firebaseImageUrl(String? url) {
    final u = url?.trim() ?? '';
    if (u.isEmpty) return null;
    if (u.startsWith('http://') || u.startsWith('https://')) return u;
    if (isValidDisplayUrl(u)) return u;
    return null;
  }

  /// Best display URL for a loaded [TouristSpotFirestore] — bundled assets first.
  static String displayUrlForSpot(TouristSpotFirestore spot) {
    final bundled = bundledAssetFor(
      spotId: spot.id,
      municipalityId: spot.municipalityId,
      spotName: spot.name,
    );
    if (bundled != null) return bundled;

    final fromDb = firebaseImageUrl(spot.image);
    if (fromDb != null) return fromDb;

    return displayUrl(
      preferred: spot.image,
      spotId: spot.id,
      municipalityId: spot.municipalityId,
      spotName: spot.name,
      category: spot.category,
    );
  }

  static String? _coerce(String? url) {
    final u = url?.trim() ?? '';
    if (u.isEmpty) return null;
    if (isValidDisplayUrl(u)) return u;
    return null;
  }

  static String _categoryFallback(String? category) {
    return kDefaultAsset;
  }

  /// Returns a displayable image URL (bundled asset preferred).
  static String displayUrl({
    String? preferred,
    String? spotId,
    String? municipalityId,
    String? spotName,
    String? category,
  }) {
    final direct = _coerce(preferred);
    if (direct != null) return direct;

    final bundled = bundledAssetFor(
      spotId: spotId,
      municipalityId: municipalityId,
      spotName: spotName,
    );
    if (bundled != null) return bundled;

    final sid = spotId?.trim() ?? '';
    if (sid.isNotEmpty) {
      final byId = _coerce(byDocId[sid]) ?? _coerce(byDocId[_slug(sid)]);
      if (byId != null) return byId;
    }

    final name = spotName?.trim() ?? '';
    if (name.isNotEmpty) {
      final byName = _coerce(byDocId[_slug(name)]);
      if (byName != null) return byName;
    }

    final mid = normalizeMunicipalityId(
      municipalityId ?? getMunicipalityIdFromName(spotName),
    );
    if (mid.isNotEmpty) {
      final mun = _coerce(byMunicipalityId[mid]);
      if (mun != null) return mun;
    }

    return _categoryFallback(category);
  }

  /// Best image for a Firestore `tourist_spots` document.
  static String resolveForFirestoreDoc({
    required String docId,
    required Map<String, dynamic> data,
  }) {
    final bundled = bundledAssetFor(
      spotId: docId,
      municipalityId: data['municipalityId'] as String?,
      spotName: data['name'] as String?,
    );
    if (bundled != null) return bundled;

    final fromData = TouristSpotFirestore.readImageUrl(data);
    final fromDb = firebaseImageUrl(fromData);
    if (fromDb != null) return fromDb;

    return displayUrl(
      spotId: docId,
      municipalityId: data['municipalityId'] as String?,
      spotName: data['name'] as String?,
      category: data['category'] as String?,
    );
  }
}

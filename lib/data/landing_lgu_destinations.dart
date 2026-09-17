import 'package:atmos_trs_system/config/supabase_storage_config.dart';
import 'package:atmos_trs_system/data/tourist_spot_image_catalog.dart';
import 'package:atmos_trs_system/data/tourist_spots_default_seed.dart';
import 'package:atmos_trs_system/utils/municipality_helper.dart';

/// Public landing page cards for all 17 Misamis Occidental LGUs.
///
/// Images resolve from [TouristSpotImageCatalog] / Supabase Storage — same
/// sources as the mobile Home / Explore / All Destinations screens.
List<Map<String, String>> buildLandingLguDestinations() {
  final seedByMunicipalityId = <String, DefaultTouristSpotSeed>{};
  for (final seed in kDefaultTouristSpotSeeds) {
    seedByMunicipalityId.putIfAbsent(seed.municipalityId, () => seed);
  }

  return _landingLguCopy.map((entry) {
    final mid = entry['municipalityId']!;
    final catalogImage = landingLguImagePathForMunicipality(mid);
    final resolved = SupabaseStorageConfig.resolve(catalogImage);
    final seed = seedByMunicipalityId[mid];
    final isAsset =
        resolved.startsWith('assets/') && !resolved.startsWith('http');
    return {
      'name': entry['name']!,
      'category': entry['category']!,
      'description': entry['description'] ?? seed?.description ?? '',
      'image': resolved,
      'isAsset': isAsset ? 'true' : 'false',
      'municipalityId': mid,
    };
  }).toList(growable: false);
}

/// Unresolved catalog path for one LGU (same source as landing destination cards).
String landingLguImagePathForMunicipality(String municipalityId) {
  final mid = normalizeMunicipalityId(municipalityId);
  return TouristSpotImageCatalog.byMunicipalityId[mid] ??
      TouristSpotImageCatalog.bundledAssetFor(municipalityId: mid) ??
      TouristSpotImageCatalog.kDefaultAsset;
}

/// All landing-page municipality images in landing order (17 LGUs).
/// Used by web login/signup glass auth slideshow.
List<String> landingLguDestinationImagePaths() {
  return _landingLguCopy
      .map((e) => landingLguImagePathForMunicipality(e['municipalityId']!))
      .toList(growable: false);
}

/// Copy and categories for the landing page (images filled at build time).
const List<Map<String, String>> _landingLguCopy = [
  {
    'municipalityId': 'oroquieta',
    'name': 'Oroquieta City',
    'category': 'Capital City',
    'description':
        'The provincial capital and seat of the capitol building, known as the "City of Good Life"',
  },
  {
    'municipalityId': 'ozamiz',
    'name': 'Ozamis City',
    'category': 'City',
    'description': 'Rich in history and culture with beautiful coastal views',
  },
  {
    'municipalityId': 'tangub',
    'name': 'Tangub City',
    'category': 'City',
    'description':
        'Home to Asenso Global Gardens and gateway to pristine coasts',
  },
  {
    'municipalityId': 'aloran',
    'name': 'Aloran',
    'category': 'Municipality',
    'description': 'Scenic landscapes and welcoming communities',
  },
  {
    'municipalityId': 'baliangao',
    'name': 'Baliangao',
    'category': 'Municipality',
    'description':
        'Bless Amare Sunrise Beach and pristine coastal views in Barangay Tugas',
  },
  {
    'municipalityId': 'bonifacio',
    'name': 'Bonifacio',
    'category': 'Municipality',
    'description': 'Mountain views and rural charm',
  },
  {
    'municipalityId': 'calamba',
    'name': 'Calamba',
    'category': 'Municipality',
    'description':
        'Lush green town amid rolling forested hills, palm trees, and serene community',
  },
  {
    'municipalityId': 'clarin',
    'name': 'Clarin',
    'category': 'Municipality',
    'description': 'Green landscapes and local hospitality',
  },
  {
    'municipalityId': 'concepcion',
    'name': 'Concepcion',
    'category': 'Municipality',
    'description':
        'Stunning multi-tiered waterfalls, rocky rivers, and lush tropical jungle',
  },
  {
    'municipalityId': 'dvc',
    'name': 'Don Victoriano Chiongbian',
    'category': 'Municipality',
    'description':
        'Piduan Falls (Curtain Falls) — majestic waterfall at Mount Malindang, Barangay Napangan',
  },
  {
    'municipalityId': 'jimenez',
    'name': 'Jimenez',
    'category': 'Municipality',
    'description': 'St. John the Baptist Church and heritage sites',
  },
  {
    'municipalityId': 'lopezjaena',
    'name': 'Lopez Jaena',
    'category': 'Municipality',
    'description': 'Beaches and coastal living',
  },
  {
    'municipalityId': 'panaon',
    'name': 'Panaon',
    'category': 'Municipality',
    'description': 'Seaside towns and natural attractions',
  },
  {
    'municipalityId': 'plaridel',
    'name': 'Plaridel',
    'category': 'Municipality',
    'description':
        'Tropical pool resort with thatched bridges, palm trees, and clear blue waters',
  },
  {
    'municipalityId': 'sapangdalaga',
    'name': 'Sapang Dalaga',
    'category': 'Municipality',
    'description':
        'Caluya Bay with floating playground and Cristo Redentor views',
  },
  {
    'municipalityId': 'sinacaban',
    'name': 'Sinacaban',
    'category': 'Municipality',
    'description':
        'Home to AMORAP — Maldives-inspired eco-luxury park with overwater villas, lagoons, and coastal adventure',
  },
  {
    'municipalityId': 'tudela',
    'name': 'Tudela',
    'category': 'Municipality',
    'description':
        'Swimming pools, resort amenities, and festivals in a lush tropical setting',
  },
];

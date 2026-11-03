import 'package:atmos_trs_system/data/featured_destinations.dart';
import 'package:atmos_trs_system/data/tourist_spot_image_catalog.dart';
import 'package:atmos_trs_system/data/tourist_spots_default_seed.dart';
import 'package:atmos_trs_system/services/pending_lgu_checkin_storage.dart';
import 'package:atmos_trs_system/services/pending_spot_checkin_storage.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';

/// Kind of authorized entry QR (attraction / LGU gate). Airport & seaport are
/// only inferred from existing spot category text — never invented records.
enum QrEntryPointKind {
  attraction,
  municipality,
  airport,
  seaport,
}

/// Destination payload shown on the QR welcome / entry gate screens.
class QrWelcomeDestinationContext {
  const QrWelcomeDestinationContext({
    required this.name,
    required this.municipality,
    required this.description,
    required this.imageUrl,
    this.spotId,
    this.municipalityId,
    this.isMunicipalityScan = false,
    this.entryKind = QrEntryPointKind.attraction,
    this.category = '',
  });

  final String name;
  final String municipality;
  final String description;
  final String imageUrl;
  final String? spotId;
  final String? municipalityId;
  final bool isMunicipalityScan;
  final QrEntryPointKind entryKind;
  final String category;

  String get entryLabel {
    if (isMunicipalityScan) return name;
    return name;
  }

  String get entryKindLabel => switch (entryKind) {
        QrEntryPointKind.airport => 'Airport entry point',
        QrEntryPointKind.seaport => 'Seaport entry point',
        QrEntryPointKind.municipality => 'Municipality entry QR',
        QrEntryPointKind.attraction => 'Tourist attraction entry QR',
      };

  static QrEntryPointKind kindFromCategory(
    String? category, {
    bool isMunicipalityScan = false,
  }) {
    if (isMunicipalityScan) return QrEntryPointKind.municipality;
    final c = (category ?? '').trim().toLowerCase();
    if (c.contains('airport') || c.contains('aerodrome')) {
      return QrEntryPointKind.airport;
    }
    if (c.contains('seaport') ||
        c.contains('sea port') ||
        c.contains('ferry') ||
        (c.contains('port') && !c.contains('sport'))) {
      return QrEntryPointKind.seaport;
    }
    return QrEntryPointKind.attraction;
  }
}

/// Resolves destination details from a pending QR scan.
class QrWelcomeDestinationResolver {
  QrWelcomeDestinationResolver._();

  static DefaultTouristSpotSeed? _seedForSpotId(String spotId) {
    final sid = spotId.trim().toLowerCase();
    for (final seed in kDefaultTouristSpotSeeds) {
      if (seed.docId.toLowerCase() == sid) return seed;
    }
    return null;
  }

  static DefaultTouristSpotSeed? _seedForMunicipalityId(String municipalityId) {
    final mid = municipalityId.trim().toLowerCase();
    for (final seed in kDefaultTouristSpotSeeds) {
      if (seed.municipalityId.toLowerCase() == mid) return seed;
    }
    return null;
  }

  static Map<String, dynamic>? _featuredForSpotId(String spotId) {
    final sid = spotId.trim().toLowerCase();
    for (final item in kFeaturedDestinations) {
      final id = (item['spotId'] as String?)?.trim().toLowerCase() ?? '';
      if (id == sid) return item;
    }
    return null;
  }

  static Future<QrWelcomeDestinationContext?> resolveFromPendingScan() async {
    final spot = await PendingSpotCheckInStorage.peek();
    final lgu = await PendingLguCheckInStorage.peek();
    if (spot == null && lgu == null) return null;

    if (spot != null) {
      return _resolveSpot(spot);
    }
    return _resolveLgu(lgu!);
  }

  static Future<QrWelcomeDestinationContext> _resolveSpot(
    PendingSpotCheckIn spot,
  ) async {
    final spotId = spot.spotId.trim();
    final municipalityId = spot.municipalityId.trim();
    final seed = _seedForSpotId(spotId);
    final featured = _featuredForSpotId(spotId);

    var name = spot.spotName?.trim().isNotEmpty == true
        ? spot.spotName!.trim()
        : seed?.name ?? featured?['name'] as String? ?? 'Tourist Destination';
    var municipality = spot.municipality?.trim().isNotEmpty == true
        ? spot.municipality!.trim()
        : seed?.municipality ??
            _municipalityFromFeatured(featured) ??
            'Misamis Occidental';

    var description = seed?.description ??
        featured?['detail'] as String? ??
        featured?['description'] as String? ??
        'Discover attractions, culture, and natural beauty in $municipality.';

    description = await _enrichDescriptionFromFirestore(spotId, description);

    final category = (seed?.category ?? featured?['category'] as String? ?? '')
        .trim();
    final firestoreCategory = await _categoryFromFirestore(spotId);
    final resolvedCategory =
        firestoreCategory.isNotEmpty ? firestoreCategory : category;

    final imageUrl = TouristSpotImageCatalog.displayUrl(
      preferred: seed?.imageUrl ?? featured?['image'] as String?,
      spotId: spotId,
      municipalityId: municipalityId,
      spotName: name,
      category: resolvedCategory.isNotEmpty ? resolvedCategory : category,
    );

    return QrWelcomeDestinationContext(
      name: name,
      municipality: municipality,
      description: description,
      imageUrl: imageUrl,
      spotId: spotId,
      municipalityId: municipalityId,
      category: resolvedCategory,
      entryKind: QrWelcomeDestinationContext.kindFromCategory(resolvedCategory),
    );
  }

  static Future<QrWelcomeDestinationContext> _resolveLgu(
    PendingLguCheckIn lgu,
  ) async {
    final municipalityId = lgu.municipalityId.trim();
    final displayName = lgu.displayName.trim();
    final seed = _seedForMunicipalityId(municipalityId);

    final name = displayName.isNotEmpty
        ? displayName
        : seed?.municipality ?? 'Misamis Occidental';
    final municipality = name;
    final description = seed?.description ??
        'Explore beaches, heritage sites, parks, and local culture across '
        '$name — one of Misamis Occidental\'s welcoming destinations.';

    final imageUrl = TouristSpotImageCatalog.displayUrl(
      preferred: seed?.imageUrl,
      spotId: seed?.docId,
      municipalityId: municipalityId,
      spotName: seed?.name ?? name,
      category: seed?.category,
    );

    return QrWelcomeDestinationContext(
      name: name,
      municipality: municipality,
      description: description,
      imageUrl: imageUrl,
      spotId: seed?.docId,
      municipalityId: municipalityId,
      isMunicipalityScan: true,
      category: seed?.category ?? '',
      entryKind: QrEntryPointKind.municipality,
    );
  }

  static String? _municipalityFromFeatured(Map<String, dynamic>? featured) {
    if (featured == null) return null;
    final location = featured['location'] as String?;
    if (location == null || location.trim().isEmpty) return null;
    final parts = location.split(',');
    if (parts.length >= 2) {
      return parts[parts.length - 2].trim();
    }
    return null;
  }

  static Future<String> _enrichDescriptionFromFirestore(
    String spotId,
    String fallback,
  ) async {
    if (spotId.isEmpty) return fallback;
    try {
      if (Firebase.apps.isEmpty) return fallback;
      final doc = await FirebaseFirestore.instance
          .collection('tourist_spots')
          .doc(spotId)
          .get()
          .timeout(const Duration(seconds: 3));
      if (!doc.exists) return fallback;
      final data = doc.data();
      final desc = data?['description'] as String?;
      if (desc != null && desc.trim().isNotEmpty) return desc.trim();
    } catch (_) {}
    return fallback;
  }

  static Future<String> _categoryFromFirestore(String spotId) async {
    if (spotId.isEmpty) return '';
    try {
      if (Firebase.apps.isEmpty) return '';
      final doc = await FirebaseFirestore.instance
          .collection('tourist_spots')
          .doc(spotId)
          .get()
          .timeout(const Duration(seconds: 3));
      if (!doc.exists) return '';
      return (doc.data()?['category'] as String?)?.trim() ?? '';
    } catch (_) {
      return '';
    }
  }
}

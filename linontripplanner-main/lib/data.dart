import 'package:flutter/material.dart';

// ─── Data Models ─────────────────────────────────────────────────────

/// Public transport hub for a municipality (bus terminal or roadside stop).
class MunicipalityBusTerminal {
  final String name;
  final double latitude;
  final double longitude;
  /// `terminal` or `stop`.
  final String kind;

  const MunicipalityBusTerminal({
    required this.name,
    required this.latitude,
    required this.longitude,
    required this.kind,
  });

  Map<String, dynamic> toFirestoreMap() => {
        'name': name,
        'latitude': latitude,
        'longitude': longitude,
        'kind': kind,
      };

  static MunicipalityBusTerminal? fromFirestoreMap(Map<String, dynamic>? raw) {
    if (raw == null || raw.isEmpty) return null;
    final name = (raw['name'] as String?)?.trim() ?? '';
    final lat = _readDouble(raw['latitude'] ?? raw['lat']);
    final lng = _readDouble(raw['longitude'] ?? raw['lng'] ?? raw['lon']);
    final kind = (raw['kind'] as String?)?.trim().toLowerCase() ?? 'terminal';
    if (name.isEmpty || lat == null || lng == null) return null;
    return MunicipalityBusTerminal(
      name: name,
      latitude: lat,
      longitude: lng,
      kind: kind == 'stop' ? 'stop' : 'terminal',
    );
  }

  static double? _readDouble(dynamic v) {
    if (v == null) return null;
    if (v is num) return v.toDouble();
    if (v is String) return double.tryParse(v.trim());
    return null;
  }
}

class FeaturedSpot {
  final String name;
  final String priceRange;
  final double rating;
  final String imagePath;
  const FeaturedSpot({
    required this.name,
    required this.priceRange,
    required this.rating,
    required this.imagePath,
  });
}

class Municipality {
  final String name;
  final String shortName;
  final String imagePath;
  final String description;
  final List<TouristSpot> spots;
  /// From Firestore (`divisionKind`, `type`, …). Empty = infer from [name].
  final String divisionKind;
  /// Public bus terminal or stop for trip routing (Firestore `busTerminal`).
  final MunicipalityBusTerminal? busTerminal;

  const Municipality({
    required this.name,
    required this.shortName,
    required this.imagePath,
    required this.description,
    required this.spots,
    this.divisionKind = '',
    this.busTerminal,
  });

  /// Badge for list cards: "City" vs "Municipality".
  String get divisionLabel {
    final raw = divisionKind.trim();
    if (raw.isNotEmpty) {
      final lower = raw.toLowerCase();
      if (lower == 'city') return 'City';
      if (lower == 'municipality' || lower == 'muni') {
        return 'Municipality';
      }
      return raw[0].toUpperCase() + (raw.length > 1 ? raw.substring(1) : '');
    }
    final n = name.toLowerCase();
    if (n.contains('city')) return 'City';
    return 'Municipality';
  }
}

class TouristSpot {
  final String name;
  final String priceRange;
  final String imagePath;
  final String location;
  final double rating;
  final String description;
  final String
  type; // 'Nature' | 'Adventure' | 'Culture' | 'Relaxation' | 'Food' (legacy: 'spot' | 'hotel')
  final double? latitude;
  final double? longitude;
  /// Walking time to reach or explore the spot (minutes), from Firestore.
  final int? walkingDistanceMinutes;
  final String entranceFee;
  /// Admin-entered food & drinks cost (saved to Firestore; not shown as price range).
  final String foodAndDrinksPrice;
  /// Admin-entered other souvenirs cost (included in auto price range).
  final String otherSouvenirsPrice;
  /// Set when loaded from Firestore so edits update the same document (avoids duplicates).
  final String? firestoreDocId;
  /// Firestore `category` (e.g. Mountain, Beach) when present.
  final String category;
  /// Firestore `visitors` / popularity counter when present.
  final int visitors;
  /// Explicit rating count when present (`ratingCount`, etc.); else 0.
  final int ratingCount;
  /// `updatedAt` millis for recent-engagement scoring (0 if unknown).
  final int updatedAtMs;

  /// True when type is Relaxation or Food (or legacy 'hotel').
  bool get isHotel => type == 'Relaxation' || type == 'Food' || type == 'hotel';

  /// Title without trailing " – Municipality" / " - City" qualifier for UI.
  String get displayName {
    final cut = name.split(RegExp(r'\s[\u2013\u2014-]\s')).first.trim();
    return cut.isEmpty ? name : cut;
  }

  const TouristSpot({
    required this.name,
    required this.priceRange,
    required this.imagePath,
    required this.location,
    required this.rating,
    required this.description,
    required this.type,
    this.latitude,
    this.longitude,
    this.walkingDistanceMinutes,
    this.entranceFee = '',
    this.foodAndDrinksPrice = '',
    this.otherSouvenirsPrice = '',
    this.firestoreDocId,
    this.category = '',
    this.visitors = 0,
    this.ratingCount = 0,
    this.updatedAtMs = 0,
  });

  TouristSpot copyWith({
    String? name,
    String? priceRange,
    String? imagePath,
    String? location,
    double? rating,
    String? description,
    String? type,
    double? latitude,
    double? longitude,
    int? walkingDistanceMinutes,
    String? entranceFee,
    String? foodAndDrinksPrice,
    String? otherSouvenirsPrice,
    String? firestoreDocId,
    String? category,
    int? visitors,
    int? ratingCount,
    int? updatedAtMs,
  }) {
    return TouristSpot(
      name: name ?? this.name,
      priceRange: priceRange ?? this.priceRange,
      imagePath: imagePath ?? this.imagePath,
      location: location ?? this.location,
      rating: rating ?? this.rating,
      description: description ?? this.description,
      type: type ?? this.type,
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      walkingDistanceMinutes:
          walkingDistanceMinutes ?? this.walkingDistanceMinutes,
      entranceFee: entranceFee ?? this.entranceFee,
      foodAndDrinksPrice: foodAndDrinksPrice ?? this.foodAndDrinksPrice,
      otherSouvenirsPrice: otherSouvenirsPrice ?? this.otherSouvenirsPrice,
      firestoreDocId: firestoreDocId ?? this.firestoreDocId,
      category: category ?? this.category,
      visitors: visitors ?? this.visitors,
      ratingCount: ratingCount ?? this.ratingCount,
      updatedAtMs: updatedAtMs ?? this.updatedAtMs,
    );
  }
}

/// Firebase Storage root folder for tourist spot profile photos (matches console: `Tourist Spots Image/`).
const String kTouristSpotProfileStorageRoot = 'Tourist Spots Image';

/// Subfolder under [kTouristSpotProfileStorageRoot]: lowercase snake_case
/// (e.g. `tudela_highland_resort_and_eco_park`). Expands `&` to `and` so names
/// match typical Firebase Storage folder names.
String touristSpotProfileStorageSlug(String spotName) {
  var s = spotName.toLowerCase().trim();
  if (s.isEmpty) return 'spot';
  s = s.replaceAll('&', ' and ');
  s = s.replaceAll(RegExp(r'[^a-z0-9\s]+'), ' ');
  s = s.trim().replaceAll(RegExp(r'\s+'), '_');
  while (s.contains('__')) {
    s = s.replaceAll('__', '_');
  }
  if (s.isEmpty || s == '_') return 'spot';
  return s;
}

class AppUser {
  /// Firestore document id in the `users` collection; empty before first save.
  final String id;
  final String name;
  final String email;
  final String role; // e.g. tourist, admin, user
  /// Download URL, `gs://…`, or Storage path (e.g. under `profile_photos/`).
  final String profilePhotoPath;
  /// Used with `profile_photos/<this>` when [profilePhotoPath] is empty; usually matches Firebase Auth uid.
  final String profilePhotoLookupId;

  const AppUser({
    this.id = '',
    required this.name,
    required this.email,
    required this.role,
    this.profilePhotoPath = '',
    this.profilePhotoLookupId = '',
  });
}

/// A rating given by a user for a spot.
class SpotRating {
  /// Firestore document id when persisted remotely; empty for local-only.
  final String id;
  final String userName;
  final String spotName;
  final double rating;
  /// Optional written feedback / comment; empty when the user skips it.
  final String description;
  /// Firebase Auth uid when known (used to load profile photo).
  final String userId;
  /// Direct photo URL/path when known.
  final String profilePhotoPath;
  final DateTime? createdAt;

  const SpotRating({
    this.id = '',
    required this.userName,
    required this.spotName,
    required this.rating,
    this.description = '',
    this.userId = '',
    this.profilePhotoPath = '',
    this.createdAt,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'userName': userName,
        'spotName': spotName,
        'rating': rating,
        'description': description,
        'userId': userId,
        'profilePhotoPath': profilePhotoPath,
        if (createdAt != null) 'createdAt': createdAt!.toIso8601String(),
      };

  factory SpotRating.fromJson(Map<String, dynamic> json) {
    DateTime? created;
    final rawCreated = json['createdAt'] ?? json['created_at'];
    if (rawCreated is String) {
      created = DateTime.tryParse(rawCreated);
    }
    return SpotRating(
      id: (json['id'] as String?)?.trim() ?? '',
      userName: (json['userName'] as String?)?.trim() ?? 'Traveler',
      spotName: (json['spotName'] as String?)?.trim() ?? '',
      rating: (json['rating'] as num?)?.toDouble() ?? 0,
      description: (json['description'] as String?)?.trim() ??
          (json['comment'] as String?)?.trim() ??
          '',
      userId: (json['userId'] as String?)?.trim() ?? '',
      profilePhotoPath: (json['profilePhotoPath'] as String?)?.trim() ?? '',
      createdAt: created,
    );
  }

  SpotRating copyWith({
    String? id,
    String? userName,
    String? spotName,
    double? rating,
    String? description,
    String? userId,
    String? profilePhotoPath,
    DateTime? createdAt,
  }) {
    return SpotRating(
      id: id ?? this.id,
      userName: userName ?? this.userName,
      spotName: spotName ?? this.spotName,
      rating: rating ?? this.rating,
      description: description ?? this.description,
      userId: userId ?? this.userId,
      profilePhotoPath: profilePhotoPath ?? this.profilePhotoPath,
      createdAt: createdAt ?? this.createdAt,
    );
  }
}

/// One document from the Firestore `tourists` collection (registry / check-in list).
class TouristRegistryEntry {
  final String docId;
  final String name;
  final String touristId;
  final String origin;
  final String dateDisplay;
  final String timeDisplay;
  final int visits;
  /// For sorting rows (newest first when known).
  final DateTime sortKey;

  const TouristRegistryEntry({
    required this.docId,
    required this.name,
    required this.touristId,
    required this.origin,
    required this.dateDisplay,
    required this.timeDisplay,
    required this.visits,
    required this.sortKey,
  });

  bool matchesSearch(String query, {int? visitsOverride}) {
    final q = query.toLowerCase().trim();
    if (q.isEmpty) return true;
    final visitText = (visitsOverride ?? visits).toString();
    return name.toLowerCase().contains(q) ||
        touristId.toLowerCase().contains(q) ||
        origin.toLowerCase().contains(q) ||
        dateDisplay.contains(q) ||
        timeDisplay.toLowerCase().contains(q) ||
        visitText.contains(q);
  }
}

/// Trip planner: user-selectable travel interests (multi-select).
/// Prefer [catalogSpotCategories] for the tourist wizard (live Firestore data).
const List<String> kTravelInterests = [
  'Nature',
  'Beaches',
  'Food',
  'Culture',
  'Adventure',
  'Historical Places',
  'Festivals',
  'Shopping',
  'Nightlife',
];

/// Unique spot categories from the loaded catalog ([TouristSpot.category],
/// falling back to [TouristSpot.type] when category is empty).
List<String> catalogSpotCategories() {
  final seen = <String>{};
  for (final s in allSpots) {
    final category = s.category.trim();
    if (category.isNotEmpty) {
      seen.add(category);
      continue;
    }
    final type = s.type.trim();
    if (type.isNotEmpty && type != 'spot' && type != 'hotel') {
      seen.add(type);
    }
  }
  final list = seen.toList()
    ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
  return list;
}

/// Trip planner: transportation modes.
const List<String> kTransportModes = [
  'Car',
  'Motorcycle',
  'Public Transport',
];

/// Budget tiers for intelligent recommendations (PHP).
enum TripBudgetTier {
  economy(maxPhp: 2000, label: 'Economy', hint: 'Under ₱2,000'),
  moderate(maxPhp: 5000, label: 'Moderate', hint: '₱2,000 – ₱5,000'),
  comfortable(maxPhp: 15000, label: 'Comfortable', hint: '₱5,000 – ₱15,000'),
  premium(maxPhp: double.infinity, label: 'Premium', hint: '₱15,000+'),
  custom(maxPhp: double.infinity, label: 'Custom', hint: 'Enter amount');

  const TripBudgetTier({
    required this.maxPhp,
    required this.label,
    required this.hint,
  });

  final double maxPhp;
  final String label;
  final String hint;

  double resolveBudget(double? customAmount) {
    if (this == TripBudgetTier.custom) {
      return customAmount ?? 0;
    }
    return maxPhp == double.infinity ? (customAmount ?? 50000) : maxPhp;
  }
}

/// Preset categories for [TourismEvent.eventType] (admin pick-list).
const List<String> kEventTypeOptions = [
  'General',
  'Festival',
  'Cultural',
  'Sports',
  'Community',
  'Conference',
  'Religious',
  'Food & Drink',
  'Music',
  'Other',
];

/// Admin-managed tourism event (image, date, time, venue, type).
class TourismEvent {
  final String id;
  final String title;
  final String imagePath;
  final String venue;
  /// LGU where the event is held (admin pick-list).
  final String municipality;
  final DateTime dateTime;
  /// Kind of event (e.g. Festival, Cultural) — shown to users.
  final String eventType;
  /// Optional longer text shown in detail and on cards.
  final String description;

  const TourismEvent({
    required this.id,
    required this.title,
    required this.imagePath,
    required this.venue,
    this.municipality = '',
    required this.dateTime,
    this.eventType = 'General',
    this.description = '',
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'imagePath': imagePath,
        'venue': venue,
        'municipality': municipality,
        'dateTime': dateTime.toIso8601String(),
        'eventType': eventType,
        'description': description,
      };

  factory TourismEvent.fromJson(Map<String, dynamic> json) {
    return TourismEvent(
      id: '${json['id'] ?? ''}',
      title: '${json['title'] ?? ''}',
      imagePath: '${json['imagePath'] ?? ''}',
      venue: '${json['venue'] ?? ''}',
      municipality: '${json['municipality'] ?? ''}',
      dateTime: DateTime.tryParse('${json['dateTime']}') ?? DateTime.now(),
      eventType: '${json['eventType'] ?? 'General'}',
      description: '${json['description'] ?? ''}',
    );
  }
}

/// Governor portal / app: short notices (not scheduled events).
class TourismAnnouncement {
  final String id;
  final String title;
  final String body;
  final String imagePath;
  final DateTime publishedAt;

  const TourismAnnouncement({
    required this.id,
    required this.title,
    this.body = '',
    this.imagePath = '',
    required this.publishedAt,
  });
}

// ─── Shared Data ──────────────────────────────────────────────────────

final List<FeaturedSpot> featuredSpots = <FeaturedSpot>[];
final List<TourismEvent> tourismEvents = <TourismEvent>[];
final List<TourismAnnouncement> tourismAnnouncements = <TourismAnnouncement>[];

/// Merged feed for notifications UI and the admin announcements tab.
sealed class TourismNewsFeedItem {
  DateTime get sortDate;
}

final class TourismNewsFeedAnnouncement extends TourismNewsFeedItem {
  TourismNewsFeedAnnouncement(this.announcement);
  final TourismAnnouncement announcement;
  @override
  DateTime get sortDate => announcement.publishedAt;
}

final class TourismNewsFeedEvent extends TourismNewsFeedItem {
  TourismNewsFeedEvent(this.event);
  final TourismEvent event;
  @override
  DateTime get sortDate => event.dateTime;
}

/// Newest first — combines Firestore `announcements` and `events`.
List<TourismNewsFeedItem> buildNewsFeedItemsSorted() {
  final out = <TourismNewsFeedItem>[
    for (final a in tourismAnnouncements) TourismNewsFeedAnnouncement(a),
    for (final e in tourismEvents) TourismNewsFeedEvent(e),
  ];
  out.sort((a, b) => b.sortDate.compareTo(a.sortDate));
  return out;
}

final List<TouristSpot> allSpots = <TouristSpot>[];
final List<Municipality> municipalities = <Municipality>[
  const Municipality(
    name: 'Aloran',
    shortName: 'Aloran',
    imagePath: '',
    description: '',
    spots: [],
  ),
  const Municipality(
    name: 'Baliangao',
    shortName: 'Baliangao',
    imagePath: '',
    description: '',
    spots: [],
  ),
  const Municipality(
    name: 'Bonifacio',
    shortName: 'Bonifacio',
    imagePath: '',
    description: '',
    spots: [],
  ),
  const Municipality(
    name: 'Calamba',
    shortName: 'Calamba',
    imagePath: '',
    description: '',
    spots: [],
  ),
  const Municipality(
    name: 'Clarin',
    shortName: 'Clarin',
    imagePath: '',
    description: '',
    spots: [],
  ),
  const Municipality(
    name: 'Concepcion',
    shortName: 'Concepcion',
    imagePath: '',
    description: '',
    spots: [],
  ),
  const Municipality(
    name: 'Don Victoriano Chiongbian',
    shortName: 'Don V. Chiongbian',
    imagePath: '',
    description: '',
    spots: [],
  ),
  const Municipality(
    name: 'Jimenez',
    shortName: 'Jimenez',
    imagePath: '',
    description: '',
    spots: [],
  ),
  const Municipality(
    name: 'Lopez Jaena',
    shortName: 'Lopez Jaena',
    imagePath: '',
    description: '',
    spots: [],
  ),
  const Municipality(
    name: 'Oroquieta City (Provincial Capital)',
    shortName: 'Oroquieta City',
    imagePath: '',
    description: '',
    spots: [],
  ),
  const Municipality(
    name: 'Ozamiz City',
    shortName: 'Ozamiz City',
    imagePath: '',
    description: '',
    spots: [],
  ),
  const Municipality(
    name: 'Panaon',
    shortName: 'Panaon',
    imagePath: '',
    description: '',
    spots: [],
  ),
  const Municipality(
    name: 'Plaridel',
    shortName: 'Plaridel',
    imagePath: '',
    description: '',
    spots: [],
  ),
  const Municipality(
    name: 'Sapang Dalaga',
    shortName: 'Sapang Dalaga',
    imagePath: '',
    description: '',
    spots: [],
  ),
  const Municipality(
    name: 'Sinacaban',
    shortName: 'Sinacaban',
    imagePath: '',
    description: '',
    spots: [],
  ),
  const Municipality(
    name: 'Tangub City',
    shortName: 'Tangub City',
    imagePath: '',
    description: '',
    spots: [],
  ),
  const Municipality(
    name: 'Tudela',
    shortName: 'Tudela',
    imagePath: '',
    description: '',
    spots: [],
  ),
];

/// Municipalities sorted alphabetically by name (for display).
List<Municipality> get sortedMunicipalities {
  final list = List<Municipality>.from(municipalities);
  list.sort((a, b) => a.name.compareTo(b.name));
  return list;
}

/// Same grouping as the public municipality detail screen: if [municipality.spots] is non-empty,
/// a spot belongs when its name matches an embedded entry; otherwise [TouristSpot.location]
/// must match [Municipality.name] or [Municipality.shortName] (trimmed, case-insensitive).
bool touristSpotBelongsToMunicipality(
  TouristSpot spot,
  Municipality municipality,
) {
  if (municipality.spots.isNotEmpty) {
    return municipality.spots.any((s) => s.name == spot.name);
  }
  final loc = spot.location.toLowerCase().trim();
  if (loc.isEmpty) return false;
  final name = municipality.name.toLowerCase().trim();
  final short = municipality.shortName.toLowerCase().trim();
  if (loc == name) return true;
  if (short.isNotEmpty && loc == short) return true;
  return false;
}

/// Municipalities sorted by highest-rated spot in each (for recommendations).
List<Municipality> get recommendedMunicipalities {
  double maxRatingFor(Municipality m) {
    final spotsInM =
        allSpots.where((s) => touristSpotBelongsToMunicipality(s, m)).toList();
    if (spotsInM.isEmpty) return 0;
    return spotsInM.map((s) => s.rating).reduce((a, b) => a > b ? a : b);
  }

  final list = List<Municipality>.from(municipalities);
  list.sort((a, b) => maxRatingFor(b).compareTo(maxRatingFor(a)));
  return list;
}

/// Home "Recommended Tourist Spots": prefer rating ≥ 4.5, highest first.
/// If none meet that bar, fall back to top-rated spots so the home grid is not empty.
List<TouristSpot> get recommendedSpots {
  const minRating = 4.5;
  var list = allSpots.where((s) => s.rating >= minRating).toList();
  if (list.isEmpty && allSpots.isNotEmpty) {
    list = List<TouristSpot>.from(allSpots);
  }
  list.sort((a, b) => b.rating.compareTo(a.rating));
  return list;
}

/// Featured spots for home banner: from featuredSpots (sorted by rating) or top-rated from allSpots.
List<FeaturedSpot> get recommendedFeaturedForBanner {
  if (featuredSpots.isNotEmpty) {
    final list = featuredSpots.map((f) {
      var linked = allSpots
          .where(
            (s) => normalizeTourismNameKey(s.name) == normalizeTourismNameKey(f.name),
          )
          .toList();
      if (linked.isEmpty) {
        final fuzzy = findTouristSpotByNameFuzzy(f.name);
        if (fuzzy != null) linked = [fuzzy];
      }
      if (linked.isEmpty) return f;
      linked.sort((a, b) {
        final aHas = a.imagePath.trim().isNotEmpty ? 1 : 0;
        final bHas = b.imagePath.trim().isNotEmpty ? 1 : 0;
        return bHas.compareTo(aHas);
      });
      final spot = linked.first;
      // Left empty when neither record has one — the banner then resolves the
      // photo from Supabase by spot name.
      var mergedPath = f.imagePath.trim();
      if (mergedPath.isEmpty) mergedPath = spot.imagePath.trim();
      return FeaturedSpot(
        name: f.name,
        priceRange: f.priceRange.isNotEmpty ? f.priceRange : spot.priceRange,
        rating: f.rating > 0 ? f.rating : spot.rating,
        imagePath: mergedPath,
      );
    }).toList();
    final seen = <String>{};
    final filtered = list
        .where((f) => f.name.trim().isNotEmpty)
        .where((f) => seen.add(normalizeTourismNameKey(f.name)))
        .toList();
    filtered.sort((a, b) => b.rating.compareTo(a.rating));
    // Need 2+ slides for home auto-advance; pad with top-rated spots if admin only set one featured.
    if (filtered.length >= 2) return filtered;
    final inBanner = <String>{
      for (final f in filtered) normalizeTourismNameKey(f.name),
    };
    final ranked = List<TouristSpot>.from(allSpots)
      ..sort((a, b) => b.rating.compareTo(a.rating));
    for (final s in ranked) {
      if (filtered.length >= 6) break;
      final key = normalizeTourismNameKey(s.name);
      if (inBanner.contains(key)) continue;
      inBanner.add(key);
      filtered.add(
        FeaturedSpot(
          name: s.name,
          priceRange: s.priceRange,
          rating: s.rating,
          imagePath: s.imagePath.trim(),
        ),
      );
    }
    return filtered;
  }
  final topSpots = List<TouristSpot>.from(allSpots)
    ..sort((a, b) => b.rating.compareTo(a.rating));
  final seen = <String>{};
  return topSpots
      .where((s) => seen.add(normalizeTourismNameKey(s.name)))
      .take(8)
      .map(
        (s) => FeaturedSpot(
          name: s.name,
          priceRange: s.priceRange,
          rating: s.rating,
          imagePath: s.imagePath.trim(),
        ),
      )
      .toList();
}

final List<AppUser> users = <AppUser>[];

/// Normalized key for matching featured spot names to [TouristSpot] names.
String normalizeTourismNameKey(String s) => s
    .toLowerCase()
    .trim()
    .replaceAll(RegExp(r'[^a-z0-9\s]'), '')
    .replaceAll(RegExp(r'\s+'), '');

TouristSpot? _preferSpotWithImage(TouristSpot? current, TouristSpot candidate) {
  if (current == null) return candidate;
  final cur = current.imagePath.trim().isNotEmpty;
  final next = candidate.imagePath.trim().isNotEmpty;
  if (next && !cur) return candidate;
  return current;
}

/// Links banner/featured titles to Firestore spots (exact or partial name match).
TouristSpot? findTouristSpotByNameFuzzy(String name) {
  final want = normalizeTourismNameKey(name);
  if (want.isEmpty) return null;
  TouristSpot? exact;
  TouristSpot? partial;
  for (final s in allSpots) {
    final key = normalizeTourismNameKey(s.name);
    if (key == want) {
      exact = _preferSpotWithImage(exact, s);
    } else if (key.contains(want) || want.contains(key)) {
      partial = _preferSpotWithImage(partial, s);
    }
  }
  return exact ?? partial;
}

/// Row in [users] for the given Firebase Auth uid ([AppUser.profilePhotoLookupId] or document [id]).
AppUser? findAppUserByFirebaseUid(String? uid) {
  if (uid == null || uid.isEmpty) return null;
  for (final u in users) {
    if (u.profilePhotoLookupId == uid || u.id == uid) return u;
  }
  return null;
}
final List<SpotRating> spotRatings = <SpotRating>[];

// ─── Shared Widgets ────────────────────────────────────────────────────

class StarRating extends StatelessWidget {
  final double rating;
  final double size;
  final Color? color;
  const StarRating({
    super.key,
    required this.rating,
    this.size = 18,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(5, (i) {
        final filled = i < rating.floor();
        final half = !filled && i < rating;
        return Icon(
          half ? Icons.star_half : (filled ? Icons.star : Icons.star_border),
          color: color ?? Colors.amber,
          size: size,
        );
      }),
    );
  }
}

/// Interactive rating control matching the orange badge + stars layout.
/// Tap stars to set 1-5; the circle shows the live score.
class InteractiveRatingBadge extends StatelessWidget {
  final double rating;
  final ValueChanged<double> onChanged;
  final Color color;

  const InteractiveRatingBadge({
    super.key,
    required this.rating,
    required this.onChanged,
    this.color = AppColors.primary,
  });

  @override
  Widget build(BuildContext context) {
    final display = rating.clamp(1.0, 5.0);
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 10, 16, 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(40),
        border: Border.all(color: color, width: 1.5),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 56,
            height: 56,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
            ),
            child: Text(
              display.toStringAsFixed(1),
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w800,
                fontSize: 18,
                height: 1,
              ),
            ),
          ),
          const SizedBox(width: 14),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: List.generate(5, (i) {
                  final starValue = (i + 1).toDouble();
                  final filled = display >= starValue;
                  return GestureDetector(
                    onTap: () => onChanged(starValue),
                    behavior: HitTestBehavior.opaque,
                    child: Padding(
                      padding: const EdgeInsets.only(right: 2),
                      child: Icon(
                        filled ? Icons.star_rounded : Icons.star_border_rounded,
                        color: color,
                        size: 28,
                      ),
                    ),
                  );
                }),
              ),
              const SizedBox(height: 2),
              Text(
                'RATING',
                style: TextStyle(
                  color: color,
                  fontWeight: FontWeight.w700,
                  fontSize: 12,
                  letterSpacing: 1.2,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class AppColors {
  static const primary = Color(0xFFFF7A00); // main orange
  static const primaryLight = Color(0xFFFFA24C);
  /// Warm cream (legacy screens, event detail body).
  static const background = Color(0xFFFFF9F2);
  /// Your Plan / app-wide page background (soft grey-cream).
  static const planPageBg = Color(0xFFF4F5F7);
  /// List rows (municipalities, admin lists).
  static const listTilePeach = Color(0xFFFFF2EB);
  static const insetSurface = Color(0xFFFAFBFC);
  static const cardBg = Colors.white;
  static const textDark = Color(0xFF1C1C1C);
  static const textGrey = Color(0xFF666666);
}

/// Custom fonts from [pubspec.yaml] `assets/fonts/`.
class AppFonts {
  /// `assets/fonts/holiday-calling-non-commercial-use.noncommercialuse.ttf`
  static const holidayCalling = 'HolidayCalling';
}

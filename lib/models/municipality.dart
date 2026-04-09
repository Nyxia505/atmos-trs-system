/// A municipality or city in Misamis Occidental with map position and tourism counts.
class Municipality {
  const Municipality({
    required this.id,
    required this.name,
    required this.type,
    required this.lat,
    required this.lng,
    required this.spotCount,
    required this.vrCount,
    this.category = MunicipalityCategory.all,
  });

  final String id;
  final String name;
  final MunicipalityType type;
  final double lat;
  final double lng;
  final int spotCount;
  final int vrCount;
  final MunicipalityCategory category;

  bool get isCity => type == MunicipalityType.city;
}

enum MunicipalityType { city, municipality }

enum MunicipalityCategory { all, beaches, mountains, heritage, festivals }

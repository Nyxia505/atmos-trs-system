import 'catalog_targeting.dart';
import 'data.dart';

/// LGU Province Live / tourist feeds require these aliases on Governor catalog
/// docs. Targeting stays on the canonical announcement/event record.
Map<String, dynamic> announcementLguCompatFields({
  required TourismAnnouncement announcement,
  DateTime? now,
}) {
  final clock = now ?? DateTime.now();
  final live = !announcement.publishedAt.toUtc().isAfter(clock.toUtc());
  final provinceWide = isProvinceWideTarget(
    audienceScope: announcement.audienceScope,
    municipality: announcement.municipality,
    municipalityId: announcement.municipalityId,
  );
  final municipalityId = provinceWide
      ? 'province'
      : announcement.municipalityId.trim();
  return {
    'content': announcement.body,
    'published': live,
    'status': 'approved',
    'scheduleState': live ? 'live' : 'scheduled',
    'municipalityName': announcement.municipality.trim(),
    if (announcement.municipality.trim().isNotEmpty)
      'municipality': announcement.municipality.trim(),
    if (announcement.audienceScope.trim().isNotEmpty)
      'audienceScope': announcement.audienceScope.trim(),
    if (municipalityId.isNotEmpty) 'municipalityId': municipalityId,
  };
}

Map<String, dynamic> eventLguCompatFields({
  required TourismEvent event,
}) {
  final provinceWide = isProvinceWideTarget(
    audienceScope: event.audienceScope,
    municipality: event.municipality,
    municipalityId: event.municipalityId,
  );
  final municipalityId = provinceWide
      ? 'province'
      : event.municipalityId.trim();
  return {
    'content': event.description,
    'type': event.eventType.trim().isEmpty ? 'Event' : event.eventType.trim(),
    'published': true,
    'status': 'approved',
    'municipalityName': event.municipality.trim(),
    if (municipalityId.isNotEmpty) 'municipalityId': municipalityId,
  };
}

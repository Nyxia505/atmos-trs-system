import 'catalog_targeting.dart';
import 'data.dart';

enum CatalogPublisherKind { governor, lgu, optaca, unknown }

class CatalogActor {
  const CatalogActor({required this.uid, required this.kind});

  final String uid;
  final CatalogPublisherKind kind;

  static const empty = CatalogActor(
    uid: '',
    kind: CatalogPublisherKind.unknown,
  );
}

class CatalogPublisher {
  const CatalogPublisher({required this.kind, required this.label});

  final CatalogPublisherKind kind;
  final String label;

  static const unknown = CatalogPublisher(
    kind: CatalogPublisherKind.unknown,
    label: 'Publisher unavailable',
  );
}

class GovernorBoardItem {
  const GovernorBoardItem({
    required this.catalogKey,
    required this.isEvent,
    required this.publisher,
    required this.canManage,
    required this.item,
    required this.mutateCollection,
    required this.mutateId,
  });

  final String catalogKey;
  final bool isEvent;
  final CatalogPublisher publisher;
  final bool canManage;
  final TourismNewsFeedItem item;
  final String mutateCollection;
  final String mutateId;

  DateTime get sortDate => item.sortDate;
}

DateTime manilaCalendarDate(DateTime value) {
  if (!value.isUtc) {
    return DateTime(value.year, value.month, value.day);
  }
  final manila = value.add(const Duration(hours: 8));
  return DateTime(manila.year, manila.month, manila.day);
}

String catalogRecordKey(String source, String id) => '$source:$id';

String announcementMirrorSourceId(String eventId) {
  const prefix = 'announcement_';
  return eventId.startsWith(prefix)
      ? eventId.substring(prefix.length)
      : eventId;
}

bool isAnnouncementMirrorId(String eventId) =>
    eventId.startsWith('announcement_');

/// Forms pre-assign a Firestore id before the first write. A missing document
/// is still a create, not an edit of someone else's record.
bool catalogDocumentIsCreate({
  required String id,
  required bool documentExists,
}) {
  return id.trim().isEmpty || !documentExists;
}

CatalogPublisherKind publisherKindFromRole({
  required String role,
  required String email,
}) {
  final normalizedRole = role.trim().toLowerCase().replaceAll(
    RegExp(r'[\s-]+'),
    '_',
  );
  final normalizedEmail = email.trim().toLowerCase();
  if (normalizedRole == 'governor' ||
      normalizedEmail == 'governor.atmos@misocc-demo.ph') {
    return CatalogPublisherKind.governor;
  }
  if (normalizedRole == 'provincial_tourism' ||
      normalizedRole == 'tourism_province' ||
      normalizedEmail == 'optaca@gmail.com' ||
      normalizedEmail == 'tourism@gmail.com' ||
      normalizedEmail == 'provincial.tourism@misocc-demo.ph') {
    return CatalogPublisherKind.optaca;
  }
  if (normalizedRole == 'tourism' ||
      normalizedRole == 'tourism_office' ||
      normalizedRole == 'lgu_tourism') {
    return CatalogPublisherKind.lgu;
  }
  return CatalogPublisherKind.unknown;
}

String _norm(String? value) => (value ?? '').trim().toLowerCase();

bool _has(String? value) => (value ?? '').trim().isNotEmpty;

CatalogPublisher resolveCatalogPublisher({
  required String publisherOffice,
  required String createdBy,
  required String createdByUid,
  required String municipalityId,
  required String municipalityName,
  String actorUid = '',
  CatalogPublisherKind actorKind = CatalogPublisherKind.unknown,
}) {
  final office = _norm(publisherOffice);
  if (office == 'governor' ||
      office == 'governor_office' ||
      office == "governor's office") {
    return const CatalogPublisher(
      kind: CatalogPublisherKind.governor,
      label: "Governor's Office",
    );
  }
  if (office == 'optaca' ||
      office == 'provincial' ||
      office == 'provincial_tourism' ||
      office == 'tourism_province') {
    return const CatalogPublisher(
      kind: CatalogPublisherKind.optaca,
      label: 'OPTACA / Provincial Tourism',
    );
  }
  if (office == 'lgu' || office.startsWith('lgu')) {
    final name = municipalityName.trim();
    return CatalogPublisher(
      kind: CatalogPublisherKind.lgu,
      label: name.isEmpty ? 'LGU' : 'LGU: $name',
    );
  }

  final by = createdBy.trim();
  final byLower = by.toLowerCase();
  if (byLower == 'governor' || byLower == "governor's office") {
    return const CatalogPublisher(
      kind: CatalogPublisherKind.governor,
      label: "Governor's Office",
    );
  }
  if (byLower == 'optaca' ||
      byLower == 'provincial tourism' ||
      byLower == 'provincial_tourism') {
    return const CatalogPublisher(
      kind: CatalogPublisherKind.optaca,
      label: 'OPTACA / Provincial Tourism',
    );
  }

  if (_has(municipalityId) &&
      !isProvinceWideTarget(
        municipality: municipalityName,
        municipalityId: municipalityId,
      )) {
    final name = municipalityName.trim();
    return CatalogPublisher(
      kind: CatalogPublisherKind.lgu,
      label: name.isEmpty ? 'LGU' : 'LGU: $name',
    );
  }

  if (_has(createdByUid) && createdByUid == actorUid) {
    if (actorKind == CatalogPublisherKind.governor) {
      return const CatalogPublisher(
        kind: CatalogPublisherKind.governor,
        label: "Governor's Office",
      );
    }
    if (actorKind == CatalogPublisherKind.optaca) {
      return const CatalogPublisher(
        kind: CatalogPublisherKind.optaca,
        label: 'OPTACA / Provincial Tourism',
      );
    }
  }

  return CatalogPublisher.unknown;
}

bool catalogRecordIsEvent({
  required String source,
  required bool isMirror,
  required String type,
  required String municipalityId,
}) {
  if (source == 'events' && !isMirror) return true;
  final normalized = _norm(type);
  if (normalized == 'announcement' ||
      normalized == 'alert' ||
      normalized == 'promo') {
    return false;
  }
  if (normalized == 'event') return true;
  if (kEventTypeOptions.any((option) => option.toLowerCase() == normalized)) {
    return true;
  }
  if (_has(municipalityId) &&
      (normalized.isEmpty ||
          normalized == 'general' ||
          normalized == 'other')) {
    return true;
  }
  return false;
}

bool canManageCatalogRecord({
  required CatalogPublisher publisher,
  required CatalogActor actor,
  required bool manageOwnedOnly,
  required String createdByUid,
  required bool isMirror,
}) {
  if (isMirror) return false;
  if (!manageOwnedOnly) return true;
  if (actor.kind != CatalogPublisherKind.governor) return false;
  if (publisher.kind == CatalogPublisherKind.governor) return true;
  if (_has(createdByUid) &&
      createdByUid == actor.uid &&
      actor.kind == CatalogPublisherKind.governor) {
    return true;
  }
  return false;
}

bool announcementDocBelongsOnEventsFeed({
  required String type,
  required String municipalityId,
}) {
  return catalogRecordIsEvent(
    source: 'announcements',
    isMirror: false,
    type: type,
    municipalityId: municipalityId,
  );
}

GovernorBoardItem? _itemFromAnnouncement(
  TourismAnnouncement announcement, {
  required CatalogActor actor,
  required bool manageOwnedOnly,
}) {
  if (announcement.id.trim().isEmpty) return null;
  final publisher = resolveCatalogPublisher(
    publisherOffice: announcement.publisherOffice,
    createdBy: announcement.createdBy,
    createdByUid: announcement.createdByUid,
    municipalityId: announcement.municipalityId,
    municipalityName: announcement.municipality,
    actorUid: actor.uid,
    actorKind: actor.kind,
  );
  final isEvent = catalogRecordIsEvent(
    source: 'announcements',
    isMirror: false,
    type: announcement.type,
    municipalityId: announcement.municipalityId,
  );
  return GovernorBoardItem(
    catalogKey: catalogRecordKey('announcements', announcement.id),
    isEvent: isEvent,
    publisher: publisher,
    canManage: canManageCatalogRecord(
      publisher: publisher,
      actor: actor,
      manageOwnedOnly: manageOwnedOnly,
      createdByUid: announcement.createdByUid,
      isMirror: false,
    ),
    item: TourismNewsFeedAnnouncement(announcement),
    mutateCollection: 'announcements',
    mutateId: announcement.id,
  );
}

GovernorBoardItem? _itemFromEvent(
  TourismEvent event, {
  required CatalogActor actor,
  required bool manageOwnedOnly,
}) {
  if (event.isAnnouncementMirror || isAnnouncementMirrorId(event.id)) {
    return null;
  }
  if (event.id.trim().isEmpty) return null;
  final publisher = resolveCatalogPublisher(
    publisherOffice: event.publisherOffice,
    createdBy: event.createdBy,
    createdByUid: event.createdByUid,
    municipalityId: event.municipalityId,
    municipalityName: '',
    actorUid: actor.uid,
    actorKind: actor.kind,
  );
  return GovernorBoardItem(
    catalogKey: catalogRecordKey('events', event.id),
    isEvent: true,
    publisher: publisher,
    canManage: canManageCatalogRecord(
      publisher: publisher,
      actor: actor,
      manageOwnedOnly: manageOwnedOnly,
      createdByUid: event.createdByUid,
      isMirror: false,
    ),
    item: TourismNewsFeedEvent(event),
    mutateCollection: 'events',
    mutateId: event.id,
  );
}

/// One board row per Firestore document. Mirrors copied from `announcements`
/// into `tourismEvents` are dropped.
List<GovernorBoardItem> buildGovernorBoard({
  required List<TourismAnnouncement> announcements,
  required List<TourismEvent> events,
  required CatalogActor actor,
  required bool manageOwnedOnly,
}) {
  final out = <GovernorBoardItem>[];
  final seen = <String>{};
  for (final announcement in announcements) {
    final item = _itemFromAnnouncement(
      announcement,
      actor: actor,
      manageOwnedOnly: manageOwnedOnly,
    );
    if (item == null || !seen.add(item.catalogKey)) continue;
    out.add(item);
  }
  for (final event in events) {
    final item = _itemFromEvent(
      event,
      actor: actor,
      manageOwnedOnly: manageOwnedOnly,
    );
    if (item == null || !seen.add(item.catalogKey)) continue;
    out.add(item);
  }
  return out;
}

List<GovernorBoardItem> sortGovernorBoard(
  List<GovernorBoardItem> items,
  DateTime now,
) {
  final copy = List<GovernorBoardItem>.from(items);
  copy.sort((a, b) {
    final phaseA = governorBoardPhase(a.sortDate, now);
    final phaseB = governorBoardPhase(b.sortDate, now);
    if (phaseA != phaseB) return phaseA.index.compareTo(phaseB.index);
    if (phaseA == GovernorBoardPhase.expired) {
      return b.sortDate.compareTo(a.sortDate);
    }
    return a.sortDate.compareTo(b.sortDate);
  });
  return copy;
}

enum GovernorBoardPhase { upcoming, ongoing, expired }

GovernorBoardPhase governorBoardPhase(DateTime when, DateTime now) {
  final day = manilaCalendarDate(when);
  final today = manilaCalendarDate(now);
  if (day.isAfter(today)) return GovernorBoardPhase.upcoming;
  if (day == today) return GovernorBoardPhase.ongoing;
  return GovernorBoardPhase.expired;
}

/// Same title in the same collection with different IDs. Reported only —
/// never auto-deleted.
List<String> suspectedDuplicateCatalogTitles(List<GovernorBoardItem> items) {
  final grouped = <String, List<String>>{};
  for (final item in items) {
    final title = switch (item.item) {
      TourismNewsFeedEvent(:final event) => event.title,
      TourismNewsFeedAnnouncement(:final announcement) => announcement.title,
    }.trim().toLowerCase();
    if (title.isEmpty) continue;
    grouped
        .putIfAbsent('${item.mutateCollection}:$title', () => [])
        .add(item.mutateId);
  }
  return [
    for (final entry in grouped.entries)
      if (entry.value.toSet().length > 1) entry.key,
  ];
}

import 'package:atmos_trs_system/services/lgu_event_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final now = DateTime(2026, 11, 1, 12);

  Map<String, dynamic> governorAnnouncement({
    String title = 'this is a testing',
    DateTime? publishedAt,
    bool? published,
    String municipality = 'Province-wide – Misamis Occidental',
    String audienceScope = 'province',
    String municipalityId = '',
    String type = 'Announcement',
    String body = 'Province notice',
  }) {
    return LguEventService.normalizeAnnouncementDoc('gov-ann-1', {
      'title': title,
      'body': body,
      'type': type,
      'publishedAt': publishedAt ?? DateTime(2026, 11, 1, 8),
      if (published != null) 'published': published,
      'municipality': municipality,
      'audienceScope': audienceScope,
      if (municipalityId.isNotEmpty) 'municipalityId': municipalityId,
      'publisherOffice': 'governor',
      'createdBy': 'Governor',
      'createdByUid': 'gov-1',
    });
  }

  Map<String, dynamic> lguEvent() {
    return {
      'id': 'lgu-1',
      'title': 'City Fiesta',
      'content': 'Local',
      'type': 'Event',
      'published': true,
      'status': 'approved',
      'municipalityId': 'oroquieta',
      'municipalityName': 'Oroquieta City',
      'allDay': true,
      'startsAt': LguEventService.instantFromManilaWall(DateTime(2026, 11, 1)),
      'endsAt': LguEventService.instantFromManilaWall(DateTime(2026, 11, 2)),
    };
  }

  test('existing Governor province-wide announcement is live without published flag', () {
    final post = governorAnnouncement();
    expect(post['content'], 'Province notice');
    expect(LguEventService.isVisibleToTourists(post, now), isTrue);
    expect(
      LguEventService.isEligibleForProvinceLive(
        post,
        municipalityId: 'oroquieta',
        municipalityName: 'Oroquieta City',
        now: now,
      ),
      isTrue,
    );
    expect(
      LguEventService.isEligibleForProvinceLive(
        post,
        municipalityId: 'ozamiz',
        municipalityName: 'Ozamis City',
        now: now,
      ),
      isTrue,
    );
    expect(LguEventService.isAnnouncementType(post), isTrue);
    expect(LguEventService.lguMayManage(post, 'oroquieta'), isFalse);
  });

  test('future-dated Governor announcement stays hidden until publish time', () {
    final post = governorAnnouncement(
      publishedAt: DateTime(2026, 11, 2, 8),
    );
    expect(LguEventService.isVisibleToTourists(post, now), isFalse);
    expect(
      LguEventService.isEligibleForProvinceLive(
        post,
        municipalityId: 'oroquieta',
        now: now,
      ),
      isFalse,
    );
  });

  test('unpublished Governor announcement is hidden', () {
    final post = governorAnnouncement(published: false);
    expect(LguEventService.isVisibleToTourists(post, now), isFalse);
  });

  test('municipality-specific Governor event is only in that LGU feed', () {
    final post = LguEventService.normalizeCatalogEvent('gov-evt-1', {
      'title': 'Oroquieta Festival',
      'description': 'City event',
      'eventType': 'Festival',
      'municipality': 'Oroquieta City',
      'audienceScope': 'municipality',
      'publisherOffice': 'governor',
      'createdBy': 'Governor',
      'startAt': LguEventService.instantFromManilaWall(DateTime(2026, 11, 1, 8)),
      'published': true,
    });
    expect(
      LguEventService.isEligibleForProvinceLive(
        post,
        municipalityId: 'oroquieta',
        municipalityName: 'Oroquieta City',
        now: now,
      ),
      isTrue,
    );
    expect(
      LguEventService.isEligibleForProvinceLive(
        post,
        municipalityId: 'ozamiz',
        municipalityName: 'Ozamis City',
        now: now,
      ),
      isFalse,
    );
    expect(LguEventService.isAnnouncementType(post), isFalse);
    expect(LguEventService.lguMayManage(post, 'oroquieta'), isFalse);
  });

  test('LGU live posts still appear in every Province Live feed', () {
    final post = lguEvent();
    expect(
      LguEventService.isEligibleForProvinceLive(
        post,
        municipalityId: 'ozamiz',
        municipalityName: 'Ozamis City',
        now: now,
      ),
      isTrue,
    );
    expect(LguEventService.lguMayManage(post, 'oroquieta'), isTrue);
    expect(LguEventService.lguMayManage(post, 'ozamiz'), isFalse);
  });
}

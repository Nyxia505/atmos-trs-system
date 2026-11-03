import 'package:flutter_test/flutter_test.dart';
import 'package:trip_plan/catalog_publisher.dart';
import 'package:trip_plan/data.dart';

void main() {
  final governor = const CatalogActor(
    uid: 'gov-1',
    kind: CatalogPublisherKind.governor,
  );

  TourismAnnouncement announcement({
    required String id,
    String title = 'Sample Announcement',
    String type = 'Announcement',
    String municipalityId = '',
    String municipality = '',
    String createdBy = 'Governor',
    String createdByUid = 'gov-1',
    String publisherOffice = 'governor',
  }) {
    return TourismAnnouncement(
      id: id,
      title: title,
      body: 'Hello',
      publishedAt: DateTime(2026, 11, 1, 8),
      type: type,
      municipalityId: municipalityId,
      municipality: municipality,
      createdBy: createdBy,
      createdByUid: createdByUid,
      publisherOffice: publisherOffice,
    );
  }

  TourismEvent event({
    required String id,
    String title = 'Sample Announcement',
    bool mirror = false,
    String publisherOffice = '',
    String createdByUid = '',
    String municipalityId = '',
  }) {
    return TourismEvent(
      id: id,
      title: title,
      imagePath: '',
      venue: 'Plaza',
      dateTime: DateTime(2026, 11, 1, 8),
      eventType: mirror ? 'Announcement' : 'Festival',
      catalogSource: mirror ? 'announcements' : 'events',
      isAnnouncementMirror: mirror,
      publisherOffice: publisherOffice,
      createdByUid: createdByUid,
      municipalityId: municipalityId,
    );
  }

  test('announcement plus mirrored event appears once as Announcement', () {
    final board = buildGovernorBoard(
      announcements: [announcement(id: 'ann-1')],
      events: [event(id: 'announcement_ann-1', mirror: true)],
      actor: governor,
      manageOwnedOnly: true,
    );

    expect(board, hasLength(1));
    expect(board.single.catalogKey, 'announcements:ann-1');
    expect(board.single.isEvent, isFalse);
    expect(board.single.publisher.label, "Governor's Office");
    expect(board.single.canManage, isTrue);
  });

  test(
    'LGU event in announcements stays an Event and is read-only for Governor',
    () {
      final board = buildGovernorBoard(
        announcements: [
          announcement(
            id: 'lgu-1',
            title: 'Halloween',
            type: 'Event',
            municipalityId: 'oroquieta',
            municipality: 'Oroquieta City',
            createdBy: 'Oroquieta City',
            createdByUid: 'lgu-user',
            publisherOffice: '',
          ),
        ],
        events: [event(id: 'announcement_lgu-1', mirror: true)],
        actor: governor,
        manageOwnedOnly: true,
      );

      expect(board, hasLength(1));
      expect(board.single.isEvent, isTrue);
      expect(board.single.publisher.label, 'LGU: Oroquieta City');
      expect(board.single.canManage, isFalse);
    },
  );

  test(
    'OPTACA and unknown records stay visible and read-only for Governor',
    () {
      final board = buildGovernorBoard(
        announcements: [
          announcement(
            id: 'opt-1',
            title: 'Province notice',
            createdBy: 'optaca',
            createdByUid: 'opt-user',
            publisherOffice: 'optaca',
          ),
          announcement(
            id: 'old-1',
            title: 'Legacy post',
            createdBy: '',
            createdByUid: '',
            publisherOffice: '',
          ),
        ],
        events: const [],
        actor: governor,
        manageOwnedOnly: true,
      );

      expect(board.map((item) => item.publisher.label), [
        'OPTACA / Provincial Tourism',
        'Publisher unavailable',
      ]);
      expect(board.every((item) => item.canManage == false), isTrue);
    },
  );

  test('matching titles in different documents are not collapsed', () {
    final board = buildGovernorBoard(
      announcements: [
        announcement(id: 'a', title: 'City Fiesta'),
        announcement(id: 'b', title: 'City Fiesta', createdByUid: 'other'),
      ],
      events: const [],
      actor: governor,
      manageOwnedOnly: true,
    );

    expect(board, hasLength(2));
    expect(suspectedDuplicateCatalogTitles(board), [
      'announcements:city fiesta',
    ]);
  });

  test('governor owned catalog event can be managed', () {
    final board = buildGovernorBoard(
      announcements: const [],
      events: [
        event(
          id: 'evt-1',
          title: 'Province Festival',
          publisherOffice: 'governor',
          createdByUid: 'gov-1',
        ),
      ],
      actor: governor,
      manageOwnedOnly: true,
    );

    expect(board.single.isEvent, isTrue);
    expect(board.single.canManage, isTrue);
    expect(board.single.publisher.kind, CatalogPublisherKind.governor);
  });

  test('pre-assigned Firestore ids are still creates when the doc is missing', () {
    expect(
      catalogDocumentIsCreate(id: 'new-announcement-id', documentExists: false),
      isTrue,
    );
    expect(
      catalogDocumentIsCreate(id: 'existing-id', documentExists: true),
      isFalse,
    );
    expect(
      catalogDocumentIsCreate(id: '', documentExists: false),
      isTrue,
    );
  });
}

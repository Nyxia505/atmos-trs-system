import 'package:atmos_trs_system/services/lgu_event_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('mine + province feeds keep one card per Firestore document id', () {
    final mine = [
      {
        'id': 'evt-sample-1',
        'title': 'sample',
        'startsAt': '2026-11-03',
        'municipalityId': 'oroquieta',
      },
    ];
    final province = [
      {
        'id': 'evt-sample-1',
        'title': 'sample',
        'startsAt': '2026-11-03',
        'municipalityId': 'oroquieta',
        'published': true,
      },
      {
        'id': 'evt-other',
        'title': 'other',
        'startsAt': '2026-11-04',
        'municipalityId': 'ozamiz',
        'published': true,
      },
    ];

    final merged = LguEventService.mergeUnique([...mine, ...province]);
    expect(merged, hasLength(2));
    expect(
      merged.map((e) => e['id']).toSet(),
      {'evt-sample-1', 'evt-other'},
    );
  });

  test('same title on different document ids stays distinct', () {
    final merged = LguEventService.mergeUnique([
      {'id': 'a', 'title': 'Festival', 'startsAt': '2026-11-03'},
      {'id': 'b', 'title': 'Festival', 'startsAt': '2026-11-03'},
    ]);
    expect(merged, hasLength(2));
  });

  test('catalog and announcement sources with same id stay distinct', () {
    final merged = LguEventService.mergeUnique([
      {
        'id': 'shared',
        'title': 'Notice',
        'startsAt': '2026-11-03',
      },
      {
        'id': 'shared',
        'title': 'Notice',
        'startsAt': '2026-11-03',
        'catalogSource': LguEventService.eventsCollection,
      },
    ]);
    expect(merged, hasLength(2));
    expect(
      merged.map(LguEventService.canonicalKey).toSet(),
      {
        '${LguEventService.collection}:shared',
        '${LguEventService.eventsCollection}:shared',
      },
    );
  });
}

import 'package:flutter_test/flutter_test.dart';
import 'package:trip_plan/catalog_lgu_compat.dart';
import 'package:trip_plan/catalog_targeting.dart';
import 'package:trip_plan/data.dart';

void main() {
  test('province-wide announcement writes LGU live fields', () {
    final fields = announcementLguCompatFields(
      announcement: TourismAnnouncement(
        id: 'a1',
        title: 'this is a testing',
        body: 'Hello LGUs',
        publishedAt: DateTime.utc(2026, 11, 1, 8),
        type: 'Announcement',
        municipality: kProvinceWideDisplay,
        audienceScope: kProvinceWideScope,
      ),
      now: DateTime.utc(2026, 11, 1, 12),
    );

    expect(fields['published'], isTrue);
    expect(fields['status'], 'approved');
    expect(fields['scheduleState'], 'live');
    expect(fields['content'], 'Hello LGUs');
    expect(fields['municipalityId'], 'province');
    expect(fields['audienceScope'], kProvinceWideScope);
  });

  test('future announcement is stored as scheduled, not live', () {
    final fields = announcementLguCompatFields(
      announcement: TourismAnnouncement(
        id: 'a2',
        title: 'Later',
        body: 'Wait',
        publishedAt: DateTime.utc(2026, 11, 3, 8),
        municipality: kProvinceWideDisplay,
        audienceScope: kProvinceWideScope,
      ),
      now: DateTime.utc(2026, 11, 1, 12),
    );

    expect(fields['published'], isFalse);
    expect(fields['scheduleState'], 'scheduled');
  });

  test('municipality event keeps city targeting', () {
    final fields = eventLguCompatFields(
      event: TourismEvent(
        id: 'e1',
        title: 'City Fest',
        imagePath: '',
        venue: 'Plaza',
        municipality: 'Oroquieta City',
        dateTime: DateTime.utc(2026, 11, 1, 8),
        eventType: 'Festival',
        description: 'Parade',
        audienceScope: kMunicipalityScope,
        municipalityId: 'oroquieta',
      ),
    );

    expect(fields['published'], isTrue);
    expect(fields['type'], 'Festival');
    expect(fields['content'], 'Parade');
    expect(fields['municipalityId'], 'oroquieta');
    expect(fields['municipalityName'], 'Oroquieta City');
  });
}

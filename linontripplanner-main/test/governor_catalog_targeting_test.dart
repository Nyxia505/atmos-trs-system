import 'package:flutter_test/flutter_test.dart';
import 'package:trip_plan/catalog_targeting.dart';
import 'package:trip_plan/data.dart';
import 'package:trip_plan/services/governor_event_types_store.dart';

void main() {
  test('province-wide selection stores an explicit province target', () {
    expect(
      catalogMunicipalityForSelection(kProvinceWideValue),
      kProvinceWideDisplay,
    );
    expect(
      catalogAudienceScopeForSelection(kProvinceWideValue),
      kProvinceWideScope,
    );
    expect(
      isProvinceWideTarget(
        audienceScope: kProvinceWideScope,
        municipality: kProvinceWideDisplay,
      ),
      isTrue,
    );
    expect(
      catalogLocationLabel(
        municipality: kProvinceWideDisplay,
        audienceScope: kProvinceWideScope,
      ),
      kProvinceWideDisplay,
    );
  });

  test('municipality-specific records keep their own city name', () {
    expect(catalogMunicipalityForSelection('Oroquieta City'), 'Oroquieta City');
    expect(
      catalogAudienceScopeForSelection('Oroquieta City'),
      kMunicipalityScope,
    );
    expect(
      catalogLocationLabel(municipality: 'Oroquieta City'),
      'Oroquieta City',
    );
    expect(isProvinceWideTarget(municipality: 'Oroquieta City'), isFalse);
  });

  test('custom event types reject empty and duplicate names', () {
    expect(normalizeCatalogEventType('  Sports Event  '), 'Sports Event');
    expect(eventTypeAlreadyExists('', kEventTypeOptions), isFalse);
    expect(eventTypeAlreadyExists('festival', kEventTypeOptions), isTrue);
    expect(
      eventTypeAlreadyExists('Cultural Festival', kEventTypeOptions),
      isFalse,
    );
    expect(
      eventTypeAlreadyExists('Sports Event', ['Sports Event', 'Community']),
      isTrue,
    );
  });

  test('saved custom types stay in the dropdown with presets', () {
    governorCustomEventTypes
      ..clear()
      ..add('Tourism Promotion');
    final choices = governorEventTypeChoices(
      selected: 'Provincial Celebration',
    );
    expect(choices, containsAll(kEventTypeOptions));
    expect(choices, contains('Tourism Promotion'));
    expect(choices, contains('Provincial Celebration'));
    governorCustomEventTypes.clear();
  });
}

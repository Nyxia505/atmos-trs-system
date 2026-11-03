import 'package:atmos_trs_system/services/qr_tourist_basic_registration_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('QrTouristBasicRegistrationService.validateFiveQuestions', () {
    test('accepts a complete five-question set', () {
      expect(
        QrTouristBasicRegistrationService.validateFiveQuestions(
          fullName: 'Ana Reyes',
          nationality: 'Filipino',
          placeOfOrigin: 'Oroquieta City',
          mobileLocal: '9171234567',
          dialCode: '+63',
          email: 'ana@example.com',
        ),
        isNull,
      );
    });

    test('rejects empty full name', () {
      expect(
        QrTouristBasicRegistrationService.validateFiveQuestions(
          fullName: ' ',
          nationality: 'Filipino',
          placeOfOrigin: 'Oroquieta City',
          mobileLocal: '9171234567',
          dialCode: '+63',
          email: 'ana@example.com',
        ),
        isNotNull,
      );
    });

    test('rejects invalid email credential', () {
      expect(
        QrTouristBasicRegistrationService.validateFiveQuestions(
          fullName: 'Ana Reyes',
          nationality: 'Filipino',
          placeOfOrigin: 'Oroquieta City',
          mobileLocal: '9171234567',
          dialCode: '+63',
          email: 'not-an-email',
        ),
        contains('email'),
      );
    });
  });

  test('splitFullName keeps given and family names', () {
    final parts =
        QrTouristBasicRegistrationService.splitFullName('Maria Clara Santos');
    expect(parts.firstName, 'Maria');
    expect(parts.lastName, 'Clara Santos');
    expect(parts.fullName, 'Maria Clara Santos');
  });
}

import 'package:atmos_trs_system/services/establishment_category_service.dart';
import 'package:atmos_trs_system/services/establishment_registration_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final official = EstablishmentCategoryService.mergeOfficial();

  test('built-in establishment categories stay on the official list', () {
    for (final name in EstablishmentRegistrationService.categoryTypes) {
      expect(official, contains(name));
    }
    expect(official, contains('Hotel'));
    expect(official, contains('Food Provider'));
  });

  test('empty and blank suggestions are rejected', () {
    expect(
      EstablishmentCategoryService.validateSuggestion(
        raw: '',
        official: official,
      ),
      'Enter a category name.',
    );
    expect(
      EstablishmentCategoryService.validateSuggestion(
        raw: '   ',
        official: official,
      ),
      'Enter a category name.',
    );
  });

  test('too-short or invalid names are rejected', () {
    expect(
      EstablishmentCategoryService.validateSuggestion(
        raw: 'A',
        official: official,
      ),
      'Use 2–40 letters or numbers for the category name.',
    );
  });

  test('duplicate of an official category is rejected', () {
    expect(
      EstablishmentCategoryService.validateSuggestion(
        raw: 'hotel',
        official: official,
      ),
      contains('already on the official list'),
    );
    expect(
      EstablishmentCategoryService.validateSuggestion(
        raw: 'Food Provider',
        official: official,
      ),
      contains('already on the official list'),
    );
  });

  test('duplicate of the applicant’s current suggestion is rejected', () {
    expect(
      EstablishmentCategoryService.validateSuggestion(
        raw: 'Homestay',
        official: official,
        alreadySuggested: 'homestay',
      ),
      contains('already your suggested category'),
    );
  });

  test('a new unique category name is accepted', () {
    expect(
      EstablishmentCategoryService.validateSuggestion(
        raw: 'Homestay',
        official: official,
      ),
      isNull,
    );
    expect(EstablishmentCategoryNames.cleaned('  Homestay  '), 'Homestay');
  });

  test('merge keeps built-in first and skips duplicate extras', () {
    final merged = EstablishmentCategoryService.mergeOfficial(
      extras: ['Hotel', 'Homestay', 'homestay'],
    );
    expect(merged.first, 'Hotel');
    expect(merged.where((n) => n.toLowerCase() == 'homestay').length, 1);
  });
}

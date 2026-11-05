import 'package:atmos_trs_system/config/ae_register_schema.dart';
import 'package:atmos_trs_system/services/ae_type_suggestion_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('rejects empty, short, and official DOT names', () {
    expect(
      AeTypeSuggestionService.validateSuggestion(
        raw: '',
        official: AeTypeCatalog.types.keys,
      ),
      isNotNull,
    );
    expect(
      AeTypeSuggestionService.validateSuggestion(
        raw: 'H',
        official: AeTypeCatalog.types.keys,
      ),
      isNotNull,
    );
    expect(
      AeTypeSuggestionService.validateSuggestion(
        raw: 'hotel',
        official: AeTypeCatalog.types.keys,
      ),
      contains('official'),
    );
  });

  test('rejects duplicates case-insensitively and pending matches', () {
    expect(
      AeTypeSuggestionService.validateSuggestion(
        raw: 'Farm Stay',
        official: const ['Farm stay'],
      ),
      contains('approved'),
    );
    expect(
      AeTypeSuggestionService.validateSuggestion(
        raw: 'Glamping Site',
        official: const [],
        alreadyPending: 'glamping site',
      ),
      contains('awaiting'),
    );
  });

  test('accepts a new valid type name', () {
    expect(
      AeTypeSuggestionService.validateSuggestion(
        raw: 'Boutique Hostel',
        official: AeTypeCatalog.types.keys,
      ),
      isNull,
    );
  });
}

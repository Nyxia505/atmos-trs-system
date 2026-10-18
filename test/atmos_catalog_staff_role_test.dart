import 'package:flutter_test/flutter_test.dart';
import 'package:trip_plan/services/auth_role_claims.dart';

void main() {
  test('ATMOS staff roles may edit the trip planner catalog', () {
    expect(isAtmosCatalogStaffRole('governor'), isTrue);
    expect(isAtmosCatalogStaffRole('Governor'), isTrue);
    expect(isAtmosCatalogStaffRole('provincial tourism'), isTrue);
    expect(isAtmosCatalogStaffRole('tourism_province'), isTrue);
    expect(isAtmosCatalogStaffRole('tourism'), isTrue);
    expect(isAtmosCatalogStaffRole('tourism_office'), isTrue);
    expect(isAtmosCatalogStaffRole('lgu tourism'), isTrue);
  });

  test('tourist accounts are not catalog staff', () {
    expect(isAtmosCatalogStaffRole('tourist'), isFalse);
    expect(isAtmosCatalogStaffRole('admin'), isFalse);
    expect(isAtmosCatalogStaffRole(null), isFalse);
    expect(isAtmosCatalogStaffRole(''), isFalse);
  });
}

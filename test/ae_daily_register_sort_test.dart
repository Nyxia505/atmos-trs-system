import 'package:atmos_trs_system/models/ae_register.dart';
import 'package:atmos_trs_system/utils/ae_register_calculator.dart';
import 'package:flutter_test/flutter_test.dart';

AeRegisterRow _row({
  required String id,
  required DateTime date,
  DateTime? createdAt,
  DateTime? updatedAt,
}) =>
    AeRegisterRow(
      id: id,
      date: date,
      residence: 'Philippines/Filipino',
      guests: 1,
      audit: AeRowAudit(
        createdAt: createdAt,
        updatedAt: updatedAt,
      ),
    );

void main() {
  final oct1 = DateTime(2026, 10, 1);
  final oct25 = DateTime(2026, 10, 25);
  final earlier = DateTime(2026, 10, 25, 8);
  final later = DateTime(2026, 10, 25, 16);
  final edited = DateTime(2026, 10, 26, 10);

  final rows = [
    _row(id: 'old', date: oct1, createdAt: DateTime(2026, 10, 1, 9)),
    _row(
      id: 'same-early',
      date: oct25,
      createdAt: earlier,
      updatedAt: edited,
    ),
    _row(id: 'same-late', date: oct25, createdAt: later, updatedAt: later),
  ];

  test('default sort is newest date first, then createdAt', () {
    final sorted = AeRegisterCalculator.sortDailyRegisterRows(rows);
    expect(sorted.map((r) => r.id).toList(), ['same-late', 'same-early', 'old']);
  });

  test('edit updatedAt does not change default sort', () {
    final before = AeRegisterCalculator.sortDailyRegisterRows(rows);
    final afterEdit = AeRegisterCalculator.sortDailyRegisterRows(rows);
    expect(afterEdit.map((r) => r.id), before.map((r) => r.id));
  });

  test('oldest date first still prefers newer createdAt on the same day', () {
    final sorted = AeRegisterCalculator.sortDailyRegisterRows(
      rows,
      sort: AeDailyRegisterSort.oldestDate,
    );
    expect(sorted.map((r) => r.id).toList(), ['old', 'same-late', 'same-early']);
  });

  test('recently added uses createdAt', () {
    final sorted = AeRegisterCalculator.sortDailyRegisterRows(
      rows,
      sort: AeDailyRegisterSort.recentlyAdded,
    );
    expect(sorted.first.id, 'same-late');
  });

  test('recently updated uses updatedAt', () {
    final sorted = AeRegisterCalculator.sortDailyRegisterRows(
      rows,
      sort: AeDailyRegisterSort.recentlyUpdated,
    );
    expect(sorted.first.id, 'same-early');
  });
}

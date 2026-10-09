import 'package:flutter_test/flutter_test.dart';

import 'package:atmos_trs_system/models/ae_register.dart';
import 'package:atmos_trs_system/models/sign_off.dart';
import 'package:atmos_trs_system/services/ae_register_service.dart';
import 'package:atmos_trs_system/services/sign_off_service.dart';
import 'package:atmos_trs_system/widgets/sign_off/sign_off_history_panel.dart';

AeRegisterRow _row(String id, {double rate = 1500, int guests = 2}) => AeRegisterRow(
      id: id,
      date: DateTime(2026, 10, 3),
      roomNo: '101',
      residence: 'Japan',
      guests: guests,
      female: 1,
      male: guests - 1,
      rate: rate,
    );

void main() {
  group('SignOffService.contentHash', () {
    test('integral doubles hash like ints (web vs mobile reads)', () {
      expect(
        SignOffService.contentHash({'rate': 1500.0, 'guests': 2}),
        SignOffService.contentHash({'guests': 2, 'rate': 1500}),
      );
    });

    test('different values give different hashes', () {
      expect(
        SignOffService.contentHash({'rate': 1500}),
        isNot(SignOffService.contentHash({'rate': 1501})),
      );
    });
  });

  group('AeRegisterService.contentHashFor', () {
    test('row order and zero-day order do not matter', () {
      final a = AeRegisterService.contentHashFor([_row('a'), _row('b')], [5, 2]);
      final b = AeRegisterService.contentHashFor([_row('b'), _row('a')], [2, 5]);
      expect(a, b);
    });

    test('round-trip through Firestore map keeps the hash', () {
      final row = _row('a');
      final back = AeRegisterRow.fromMap('a', {...row.toMap(), 'rate': 1500, 'encodedBy': 'Ana'});
      expect(
        AeRegisterService.contentHashFor([back], const []),
        AeRegisterService.contentHashFor([row], const []),
      );
    });

    test('editing guests changes the hash', () {
      expect(
        AeRegisterService.contentHashFor([_row('a', guests: 3)], const []),
        isNot(AeRegisterService.contentHashFor([_row('a')], const [])),
      );
    });
  });

  test('signOffDiffLines lists only changed fields', () {
    final lines = signOffDiffLines(_row('a').toMap(), _row('a', guests: 3).toMap());
    expect(lines, contains('Guests: 2 → 3'));
    expect(lines, contains('Male: 1 → 2'));
    expect(lines.any((l) => l.startsWith('Rate')), isFalse);
  });

  test('SignOffSigner.keyFor dedupes case and spacing', () {
    expect(
      SignOffSigner.keyFor('Ana  Cruz', 'Front Desk'),
      SignOffSigner.keyFor('ana cruz', 'front desk'),
    );
  });
}

import 'package:atmos_trs_system/services/ae_room_inventory_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('fromEstablishmentMap synthesizes 1…N when roomLabels missing', () {
    final inv = AeRoomInventoryService.fromEstablishmentMap({
      'roomCount': 20,
    });
    expect(inv.roomCount, 20);
    expect(inv.options.first, '1');
    expect(inv.options.last, '20');
    expect(inv.options.length, 20);
  });

  test('suggestNext continues after highest numeric room', () {
    final inv = AeRoomInventory(
      roomCount: 20,
      roomLabels: [for (var i = 1; i <= 20; i++) '$i'],
    );
    expect(AeRoomInventoryService.suggestNext(inv), '21');
  });

  test('validateRoomId rejects empty and oversized ids', () {
    expect(AeRoomInventoryService.validateRoomId(''), isNotNull);
    expect(AeRoomInventoryService.validateRoomId('21'), isNull);
    expect(AeRoomInventoryService.validateRoomId('Penthouse-A'), isNull);
    expect(
      AeRoomInventoryService.validateRoomId('x' * 30),
      isNotNull,
    );
  });

  test('parseLabels de-duplicates case-insensitively', () {
    final labels = AeRoomInventoryService.parseLabels(
      ['1', '2', '2', 'Suite', 'suite'],
      fallbackCount: 0,
    );
    expect(labels, ['1', '2', 'Suite']);
  });
}

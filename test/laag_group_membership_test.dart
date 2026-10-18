import 'package:atmos_trs_system/models/tourist_group.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TouristGroupMember member({
    required String uid,
    String status = 'accepted',
  }) {
    return TouristGroupMember.fromMap(uid, {
      'name': uid,
      'status': status,
    });
  }

  test('older members without a status stay accepted', () {
    final parsed = TouristGroupMember.fromMap('a', {'name': 'Ana'});
    expect(parsed.isAccepted, isTrue);
    expect(parsed.isInvited, isFalse);
  });

  test('only accepted members can be checked in together', () {
    final group = TouristGroup(
      id: 'g',
      leaderUid: 'leader',
      name: 'Barkada',
      joinCode: 'AB12CD',
      status: 'active',
      memberUids: const ['leader', 'friend'],
      members: {
        'leader': member(uid: 'leader'),
        'friend': member(uid: 'friend', status: 'invited'),
      },
      pendingInvites: {
        'other': member(uid: 'other', status: 'invited'),
      },
    );

    expect(group.participatingMembers.map((m) => m.uid), ['leader']);
    expect(group.hasPendingInvite('other'), isTrue);
    expect(group.isActive, isTrue);
  });

  test('group QR payload round-trips', () {
    final parsed = TouristGroup.parseQrPayload('ATMOS-TRS-GROUP:abc:4k2p9x');
    expect(parsed?.groupId, 'abc');
    expect(parsed?.code, '4K2P9X');
  });
}

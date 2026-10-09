import 'package:atmos_trs_system/utils/checkin_visitor_expansion.dart';
import 'package:atmos_trs_system/utils/dot_var2_visitor_record_report.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> _filipinoFemale() => {
      'sex': 'Female',
      'country': 'Philippines',
      'nationality': 'Filipino',
      'province': 'Misamis Occidental',
      'city': 'Oroquieta City',
      'localOrForeign': 'Local',
    };

void main() {
  group('expandCheckInVisitors — solo scan', () {
    test('legacy check-in without party data is one person', () {
      final units = expandCheckInVisitors(
        {'userId': 'u1', 'touristProfile': _filipinoFemale()},
      );
      expect(units, hasLength(1));
      expect(units.single.uid, 'u1');
      expect(units.single.isProxy, isFalse);
    });

    test('companions get remaining sex and residency counts', () {
      final units = expandCheckInVisitors({
        'userId': 'u1',
        'touristProfile': _filipinoFemale(),
        'partySize': 4,
        'femaleCount': 2,
        'maleCount': 2,
        'filipinoCount': 3,
        'foreignCount': 1,
      });
      expect(units, hasLength(4));
      final companions = units.where((u) => u.isProxy).toList();
      expect(companions, hasLength(3));
      expect(companions.where((u) => u.sex == 'Female'), hasLength(1));
      expect(companions.where((u) => u.sex == 'Male'), hasLength(2));
      final domestic =
          companions.where((u) => isDomesticVisitorProfile(u.profile)).toList();
      expect(domestic, hasLength(2));
      // Same residence class as the lead → lead's city is the proxy.
      expect(domestic.first.profile['city'], 'Oroquieta City');
      final foreign =
          companions.where((u) => !isDomesticVisitorProfile(u.profile)).single;
      expect(foreign.residenceUnknown, isTrue);
    });

    test('old docs without Filipino/Foreign copy the lead residence', () {
      final units = expandCheckInVisitors({
        'userId': 'u1',
        'touristProfile': _filipinoFemale(),
        'partySize': 3,
        'femaleCount': 1,
        'maleCount': 2,
      });
      final companions = units.where((u) => u.isProxy).toList();
      expect(companions, hasLength(2));
      expect(companions.every((u) => u.sex == 'Male'), isTrue);
      expect(companions.every((u) => u.profile['city'] == 'Oroquieta City'),
          isTrue);
    });
  });

  group('expandCheckInVisitors — group scan', () {
    Map<String, dynamic> groupDoc() => {
          'userId': 'lead',
          'groupId': 'g1',
          'groupLeaderUid': 'lead',
          'groupMemberUids': ['lead', 'm1'],
          'groupMembers': [
            {'uid': 'lead', ..._filipinoFemale()},
            {
              'uid': 'm1',
              'sex': 'Male',
              'country': 'Japan',
              'nationality': 'Japanese',
              'localOrForeign': 'Foreign',
            },
          ],
          'companionCount': 1,
          'companionFemale': 1,
          'companionMale': 0,
          'companionFilipino': 1,
          'companionForeign': 0,
          'partySize': 3,
          'spotId': 'plaza',
          'timestamp': DateTime(2026, 10, 5, 10),
        };

    test('each member uses own profile plus companions', () {
      final units = expandCheckInVisitors(groupDoc());
      expect(units, hasLength(3));
      expect(units.where((u) => !u.isProxy).map((u) => u.uid),
          containsAll(['lead', 'm1']));
      final japanese = units.firstWhere((u) => u.uid == 'm1');
      expect(isDomesticVisitorProfile(japanese.profile), isFalse);
      final companion = units.singleWhere((u) => u.isProxy);
      expect(companion.sex, 'Female');
      expect(companion.profile['city'], 'Oroquieta City');
    });

    test('member who also scanned alone that day is counted once', () {
      final solo = {
        'userId': 'm1',
        'touristProfile': {'sex': 'Male', 'country': 'Japan'},
        'spotId': 'plaza',
        'timestamp': DateTime(2026, 10, 5, 9),
      };
      final pairs = expandCheckInsToVisitors([groupDoc(), solo]);
      expect(pairs.where((p) => p.unit.uid == 'm1'), hasLength(1));
      expect(pairs, hasLength(3));
    });
  });

  test('VAR 2 counts group members and companions', () {
    final result = buildDotVar2VisitorRecordReport(
      checkIns: [
        {
          'userId': 'lead',
          'spotId': 'plaza',
          'spot_name': 'City Plaza',
          'groupMembers': [
            {'uid': 'lead', ..._filipinoFemale()},
            {'uid': 'm1', 'sex': 'Male', 'localOrForeign': 'Foreign',
              'country': 'Japan'},
          ],
          'companionCount': 1,
          'companionFemale': 0,
          'companionMale': 1,
          'companionFilipino': 1,
          'companionForeign': 0,
          'timestamp': DateTime(2026, 10, 5),
        },
      ],
      catalogSpots: const [],
      municipalityName: 'Oroquieta City',
      startDate: DateTime(2026, 10, 1),
      endDate: DateTime(2026, 10, 31),
    );
    final f = result.footerTotals;
    expect(f.grandTotal.total, 3);
    expect(f.foreign.total, 1);
    expect(f.thisMunicipality.total, 2);
    expect(f.grandTotal.male, 2);
    expect(f.grandTotal.female, 1);
  });
}

import 'package:atmos_trs_system/services/user_activity_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  var userNumber = 0;
  late String uid;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    userNumber += 1;
    uid = 'saved-spots-test-user-$userNumber';
    await UserActivityService.bindToUser(uid);
    await UserActivityService.ensureSavedSpotsLoaded();
  });

  test('bookmark updates in memory before the save finishes persisting', () async {
    final pending = UserActivityService.toggleSaveSpot('bless_amare');
    expect(UserActivityService.isSpotSavedSync('bless_amare'), isTrue);
    expect(await pending, isTrue);
    expect(await UserActivityService.getSavedSpotIds(), ['bless_amare']);
  });

  test('unsaving removes the spot and does not keep a duplicate', () async {
    await UserActivityService.toggleSaveSpot('amorap');
    expect(await UserActivityService.getSavedSpotIds(), ['amorap']);
    expect(await UserActivityService.toggleSaveSpot('amorap'), isFalse);
    expect(UserActivityService.isSpotSavedSync('amorap'), isFalse);
    expect(await UserActivityService.getSavedSpotIds(), isEmpty);
  });

  test('rapid saves keep every destination', () async {
    final first = UserActivityService.toggleSaveSpot('aloran_viewpoint');
    final second = UserActivityService.toggleSaveSpot('jimenez_church');
    expect(UserActivityService.isSpotSavedSync('aloran_viewpoint'), isTrue);
    expect(UserActivityService.isSpotSavedSync('jimenez_church'), isTrue);
    await first;
    await second;
    final ids = await UserActivityService.getSavedSpotIds();
    expect(ids.toSet(), {'aloran_viewpoint', 'jimenez_church'});
  });

  test('saved ids stay available after the in-memory list is reloaded', () async {
    await UserActivityService.toggleSaveSpot('cotta');
    await UserActivityService.bindToUser('someone-else');
    await UserActivityService.bindToUser(uid);
    await UserActivityService.ensureSavedSpotsLoaded();
    expect(UserActivityService.isSpotSavedSync('cotta'), isTrue);
  });
}

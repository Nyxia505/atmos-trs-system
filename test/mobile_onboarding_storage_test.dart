import 'package:atmos_trs_system/services/mobile_onboarding_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('onboarding is incomplete until marked', () async {
    expect(await MobileOnboardingStorage.isComplete(), isFalse);
    await MobileOnboardingStorage.markComplete();
    expect(await MobileOnboardingStorage.isComplete(), isTrue);
  });

  test('completion survives a later prefs read (app restart)', () async {
    SharedPreferences.setMockInitialValues({
      'mobile_onboarding_completed_v2': true,
    });
    expect(await MobileOnboardingStorage.isComplete(), isTrue);
  });
}

import 'package:atmos_trs_system/services/user_directory_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('verified when either Firestore doc is verified', () {
    expect(
      UserDirectoryService.combineTouristVerification(
        localCache: false,
        usersIsVerified: false,
        touristsIsVerified: true,
      ),
      isTrue,
    );
    expect(
      UserDirectoryService.combineTouristVerification(
        localCache: false,
        usersIsVerified: true,
        touristsIsVerified: null,
      ),
      isTrue,
    );
  });

  test('keeps the local flag when both reads fail', () {
    expect(
      UserDirectoryService.combineTouristVerification(
        localCache: true,
        usersIsVerified: null,
        touristsIsVerified: null,
      ),
      isTrue,
    );
    expect(
      UserDirectoryService.combineTouristVerification(
        localCache: false,
        usersIsVerified: null,
        touristsIsVerified: null,
      ),
      isFalse,
    );
  });

  test('explicit false does not count as verified', () {
    expect(
      UserDirectoryService.combineTouristVerification(
        localCache: false,
        usersIsVerified: false,
        touristsIsVerified: false,
      ),
      isFalse,
    );
    expect(
      UserDirectoryService.combineTouristVerification(
        localCache: true,
        usersIsVerified: false,
        touristsIsVerified: null,
      ),
      isFalse,
    );
  });
}

import 'package:cloud_functions/cloud_functions.dart';

/// OPTACA account actions. Auth create / password / disable run in
/// `optacaManageAccount` so the signed-in office is not replaced.
class OptacaAccountException implements Exception {
  OptacaAccountException(this.message);
  final String message;

  @override
  String toString() => message;
}

class OptacaAccountAdminService {
  OptacaAccountAdminService._();

  static Future<void> call(Map<String, dynamic> data) async {
    try {
      final functions = FirebaseFunctions.instanceFor(region: 'asia-southeast1');
      final callable = functions.httpsCallable(
        'optacaManageAccount',
        options: HttpsCallableOptions(timeout: const Duration(seconds: 45)),
      );
      await callable.call(data);
    } on FirebaseFunctionsException catch (e) {
      final message = (e.message ?? '').trim();
      if (e.code == 'not-found' || e.code == 'unavailable') {
        throw OptacaAccountException(
          'Account tools are not deployed yet. Run firebase deploy --only functions:optacaManageAccount.',
        );
      }
      throw OptacaAccountException(
        message.isEmpty ? 'Account action failed.' : message,
      );
    } catch (e) {
      if (e is OptacaAccountException) rethrow;
      throw OptacaAccountException('Account action failed. $e');
    }
  }
}

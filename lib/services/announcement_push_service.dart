import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart' show debugPrint;

/// Sends FCM topic push to tourists who installed the app (topic
/// [kGovernorAnnouncementsTopic] in [push_notification_service.dart]).
class AnnouncementPushService {
  AnnouncementPushService._();

  static FirebaseFunctions get _functions =>
      FirebaseFunctions.instanceFor(region: 'asia-southeast1');

  /// Returns true when the Cloud Function accepted the broadcast.
  static Future<bool> broadcastToInstalledApps({
    required String title,
    required String content,
    String type = 'General',
    String? announcementId,
  }) async {
    if (Firebase.apps.isEmpty) return false;
    final trimmedTitle = title.trim();
    if (trimmedTitle.isEmpty) return false;

    try {
      await _functions.httpsCallable('broadcastGovernorAnnouncement').call({
        'title': trimmedTitle,
        'content': content.trim(),
        'type': type.trim().isEmpty ? 'General' : type.trim(),
        if (announcementId != null && announcementId.isNotEmpty)
          'announcementId': announcementId,
      });
      return true;
    } on FirebaseFunctionsException catch (e) {
      debugPrint(
        '[AnnouncementPush] ${e.code}: ${e.message} '
        '(deploy: firebase deploy --only functions)',
      );
      return false;
    } catch (e) {
      debugPrint('[AnnouncementPush] $e');
      return false;
    }
  }
}

import 'dart:convert';

import 'package:atmos_trs_system/config/supabase_storage_config.dart';
import 'package:atmos_trs_system/config/supabase_upload_config.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:http/http.dart' as http;

/// Sends one FCM topic push to installed tourist apps.
///
/// The deployed Cloud Function cannot be updated while Firebase billing is
/// closed, so the send goes through the Supabase Edge Function first. That
/// function reads the saved announcement and posts to `governor_announcements`,
/// which the installed APK already subscribes to. The callable remains as a
/// fallback for when Cloud Functions deploys again.
class AnnouncementPushService {
  AnnouncementPushService._();

  static bool _backfillStarted = false;

  static FirebaseFunctions get _functions =>
      FirebaseFunctions.instanceFor(region: 'asia-southeast1');

  static Uri? get _edgeUri {
    final base = SupabaseStorageConfig.projectUrl.trim().replaceAll(RegExp(r'/+$'), '');
    if (base.isEmpty) return null;
    return Uri.parse('$base/functions/v1/notify-lgu-event');
  }

  /// Returns true when a sender accepted the broadcast.
  static Future<bool> broadcastToInstalledApps({
    required String title,
    required String content,
    String type = 'General',
    String? announcementId,
  }) async {
    if (Firebase.apps.isEmpty) return false;
    final id = announcementId?.trim() ?? '';
    if (id.isNotEmpty) {
      final sent = await _postEdge({'announcementId': id});
      if (sent) return true;
    }
    return _postCallable(
      title: title,
      content: content,
      type: type,
      announcementId: id,
    );
  }

  /// One pass per app launch. The server skips events already claimed and
  /// does not push expired, draft, or rejected posts.
  static Future<void> backfillOnce() async {
    if (_backfillStarted) return;
    _backfillStarted = true;
    await _postEdge({'mode': 'backfill'});
  }

  static Future<bool> _postEdge(Map<String, String> body) async {
    final uri = _edgeUri;
    final anon = SupabaseUploadConfig.anonKey.trim();
    if (uri == null || anon.isEmpty || Firebase.apps.isEmpty) return false;
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return false;
    try {
      final idToken = await user.getIdToken();
      if (idToken == null || idToken.isEmpty) return false;
      final response = await http
          .post(
            uri,
            headers: {
              'Content-Type': 'application/json',
              'apikey': anon,
              'Authorization': 'Bearer $anon',
              'X-Firebase-Auth': idToken,
            },
            body: jsonEncode(body),
          )
          .timeout(const Duration(seconds: 40));
      if (response.statusCode >= 200 && response.statusCode < 300) {
        debugPrint('[AnnouncementPush] edge ok ${response.body}');
        return true;
      }
      debugPrint(
        '[AnnouncementPush] edge ${response.statusCode} ${response.body}',
      );
      return false;
    } catch (e) {
      debugPrint('[AnnouncementPush] edge failed: $e');
      return false;
    }
  }

  static Future<bool> _postCallable({
    required String title,
    required String content,
    required String type,
    required String announcementId,
  }) async {
    final trimmedTitle = title.trim();
    if (trimmedTitle.isEmpty) return false;
    try {
      await _functions.httpsCallable('broadcastGovernorAnnouncement').call({
        'title': trimmedTitle,
        'content': content.trim(),
        'type': type.trim().isEmpty ? 'General' : type.trim(),
        if (announcementId.isNotEmpty) 'announcementId': announcementId,
      });
      return true;
    } on FirebaseFunctionsException catch (e) {
      debugPrint(
        '[AnnouncementPush] ${e.code}: ${e.message} '
        '(Cloud Functions deploy is blocked until Firebase billing is open)',
      );
      return false;
    } catch (e) {
      debugPrint('[AnnouncementPush] $e');
      return false;
    }
  }
}

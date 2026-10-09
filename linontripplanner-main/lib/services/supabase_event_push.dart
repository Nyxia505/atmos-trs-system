import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:http/http.dart' as http;

import '../config/supabase_config.dart';
import '../event_datetime_format.dart';

/// Sends FCM topic push via Supabase Edge Function (no Firebase Blaze needed).
///
/// Requires secret `FIREBASE_SERVICE_ACCOUNT_JSON` on the Edge Function.
Future<void> broadcastTourismEventPushViaSupabase({
  required String eventId,
  required String title,
  required String municipality,
  required String venue,
  required String description,
  required DateTime dateTime,
}) async {
  if (!SupabaseConfig.isConfigured) {
    debugPrint('supabase event push: Supabase not configured');
    return;
  }

  final user = FirebaseAuth.instance.currentUser;
  if (user == null) {
    debugPrint('supabase event push: not signed in');
    return;
  }

  String? idToken;
  try {
    idToken = await user.getIdToken(true);
  } catch (e) {
    debugPrint('supabase event push: id token failed: $e');
    return;
  }
  if (idToken == null || idToken.isEmpty) {
    debugPrint('supabase event push: empty id token');
    return;
  }

  final uri = Uri.parse(SupabaseConfig.notifyTourismEventFunctionUrl);
  final time = formatEventDateTimeDisplay(dateTime);
  try {
    final response = await http
        .post(
          uri,
          headers: {
            'Content-Type': 'application/json',
            'apikey': SupabaseConfig.anonKey,
            'Authorization': 'Bearer ${SupabaseConfig.anonKey}',
            'X-Firebase-Auth': idToken,
          },
          body: jsonEncode({
            'eventId': eventId,
            'title': title,
            'municipality': municipality,
            'venue': venue,
            'description': description,
            'time': time,
          }),
        )
        .timeout(const Duration(seconds: 25));

    if (response.statusCode >= 200 && response.statusCode < 300) {
      debugPrint('supabase event push: ok ${response.body}');
    } else {
      debugPrint(
        'supabase event push failed: ${response.statusCode} ${response.body}',
      );
    }
  } catch (e) {
    debugPrint('supabase event push failed: $e');
  }
}

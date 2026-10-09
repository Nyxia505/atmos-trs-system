import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart' show kIsWeb;

/// Web: disable persistence to avoid rare watch-stream assertion crashes when
/// many collection reads overlap (Firebase JS SDK 11.x).
Future<void> configureFirestoreForPlatform() async {
  if (!kIsWeb) return;
  FirebaseFirestore.instance.settings = const Settings(
    persistenceEnabled: false,
  );
}

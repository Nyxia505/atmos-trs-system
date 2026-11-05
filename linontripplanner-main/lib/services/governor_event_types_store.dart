import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

import '../catalog_targeting.dart';
import '../data.dart';
import 'auth_role_claims.dart';
import 'auth_roles.dart';

const String kGovernorEventTypesCollection = 'governor_event_types';

final List<String> governorCustomEventTypes = <String>[];

String governorEventTypeDocId(String label) {
  final slug = normalizeCatalogEventType(label)
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
      .replaceAll(RegExp(r'_+'), '_')
      .replaceAll(RegExp(r'^_|_$'), '');
  return slug.isEmpty ? 'type' : slug;
}

List<String> governorEventTypeChoices({String selected = ''}) {
  final choices = <String>[];
  final seen = <String>{};
  void add(String raw) {
    final label = normalizeCatalogEventType(raw);
    if (label.isEmpty) return;
    if (!seen.add(label.toLowerCase())) return;
    choices.add(label);
  }

  for (final type in kEventTypeOptions) {
    add(type);
  }
  for (final type in governorCustomEventTypes) {
    add(type);
  }
  add(selected);
  return choices;
}

Future<void> loadGovernorEventTypesFromFirestore() async {
  try {
    final snapshot = await FirebaseFirestore.instance
        .collection(kGovernorEventTypesCollection)
        .get();
    final labels = <String>[];
    for (final doc in snapshot.docs) {
      final label = normalizeCatalogEventType(
        '${doc.data()['label'] ?? doc.id}',
      );
      if (label.isEmpty) continue;
      if (eventTypeAlreadyExists(label, labels)) continue;
      labels.add(label);
    }
    governorCustomEventTypes
      ..clear()
      ..addAll(labels);
  } catch (e) {
    debugPrint('loadGovernorEventTypesFromFirestore: $e');
  }
}

Future<String> addGovernorCustomEventType(String raw) async {
  if (!AuthRoles.isGovernorPortalUser()) {
    throw FirebaseException(
      plugin: 'cloud_firestore',
      code: 'permission-denied',
      message: 'Only the Governor\'s Office can add event types.',
    );
  }
  final label = normalizeCatalogEventType(raw);
  if (label.isEmpty) {
    throw ArgumentError('Enter an event type');
  }
  if (eventTypeAlreadyExists(label, governorEventTypeChoices())) {
    throw ArgumentError('That event type already exists');
  }
  await ensurePermanentStaffRoleForCatalogWrite();
  final user = FirebaseAuth.instance.currentUser;
  await FirebaseFirestore.instance
      .collection(kGovernorEventTypesCollection)
      .doc(governorEventTypeDocId(label))
      .set({
        'label': label,
        'labelKey': label.toLowerCase(),
        'office': 'governor',
        'createdByUid': user?.uid,
        'createdAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
  if (!eventTypeAlreadyExists(label, governorCustomEventTypes)) {
    governorCustomEventTypes.add(label);
  }
  return label;
}

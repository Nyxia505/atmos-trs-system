import 'dart:math' as math;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show debugPrint, kIsWeb;

import 'package:atmos_trs_system/services/establishment_firestore_write.dart';
import 'package:atmos_trs_system/services/establishment_registration_service.dart';
import 'package:atmos_trs_system/services/firestore_auth_gate.dart';

/// Live room inventory for a lodging establishment.
///
/// Canonical fields on `accommodation_establishments/{aeId}`:
/// - [roomCount] / [totalRooms] — total available rooms (capacity)
/// - [roomLabels] — ordered room identifiers (when empty, UI uses `1…roomCount`)
class AeRoomInventory {
  const AeRoomInventory({
    required this.roomCount,
    required this.roomLabels,
  });

  final int roomCount;
  final List<String> roomLabels;

  /// Dropdown options: explicit labels, or sequential `1…roomCount`.
  List<String> get options {
    if (roomLabels.isNotEmpty) return List<String>.unmodifiable(roomLabels);
    final n = roomCount < 0 ? 0 : roomCount;
    return [for (var i = 1; i <= n; i++) '$i'];
  }
}

/// Adds rooms from the DOT Register Add Stay / Add Single Night forms.
abstract final class AeRoomInventoryService {
  static const fieldRoomCount = 'roomCount';
  static const fieldTotalRooms = 'totalRooms';
  static const fieldRoomLabels = 'roomLabels';

  static CollectionReference<Map<String, dynamic>> get _col =>
      FirebaseFirestore.instance.collection(
        EstablishmentRegistrationService.establishmentsCollection,
      );

  static AeRoomInventory fromEstablishmentMap(Map<String, dynamic>? data) {
    final m = data ?? const <String, dynamic>{};
    final raw = m[fieldRoomCount] ?? m[fieldTotalRooms];
    final count = raw is int
        ? raw
        : int.tryParse(raw?.toString() ?? '') ?? 0;
    final labels = parseLabels(m[fieldRoomLabels], fallbackCount: count);
    return AeRoomInventory(roomCount: math.max(count, labels.length), roomLabels: labels);
  }

  /// Prefer stored labels; otherwise synthesize `1…fallbackCount`.
  static List<String> parseLabels(dynamic raw, {int fallbackCount = 0}) {
    if (raw is List && raw.isNotEmpty) {
      final seen = <String>{};
      final out = <String>[];
      for (final e in raw) {
        final t = e.toString().trim();
        if (t.isEmpty) continue;
        final key = t.toLowerCase();
        if (!seen.add(key)) continue;
        out.add(t);
      }
      return out;
    }
    final n = fallbackCount < 0 ? 0 : fallbackCount;
    return [for (var i = 1; i <= n; i++) '$i'];
  }

  static String? validateRoomId(String raw) {
    final t = raw.trim();
    if (t.isEmpty) return 'Enter a room number.';
    if (t.length > 24) return 'Room id must be 24 characters or fewer.';
    if (!RegExp(r"^[A-Za-z0-9][A-Za-z0-9\-_/ ]{0,23}$").hasMatch(t)) {
      return 'Use letters, numbers, spaces, -, _, or / only.';
    }
    return null;
  }

  /// Next unused sequential number when existing ids are mostly numeric.
  static String suggestNext(AeRoomInventory inventory) {
    final opts = inventory.options;
    var maxN = 0;
    for (final o in opts) {
      final n = int.tryParse(o);
      if (n != null && n > maxN) maxN = n;
    }
    if (maxN <= 0 && inventory.roomCount > 0) return '${inventory.roomCount + 1}';
    return '${maxN + 1}';
  }

  static Future<AeRoomInventory> load(String establishmentId) async {
    final id = establishmentId.trim();
    if (id.isEmpty) return const AeRoomInventory(roomCount: 0, roomLabels: []);
    final doc = await _col.doc(id).get();
    return fromEstablishmentMap(doc.data());
  }

  /// Permanently adds [roomId] for the signed-in establishment owner.
  /// Updates [roomCount] / [totalRooms] and [roomLabels] together.
  static Future<AeRoomInventory> addRoom({
    required String establishmentId,
    required String roomId,
  }) async {
    final id = establishmentId.trim();
    final cleaned = roomId.trim().replaceAll(RegExp(r'\s+'), ' ');
    final err = validateRoomId(cleaned);
    if (err != null) throw StateError(err);

    final authUid = FirebaseAuth.instance.currentUser?.uid ?? '';
    if (authUid.isEmpty || authUid != id) {
      throw StateError('Only this establishment can add rooms to its inventory.');
    }

    await FirestoreAuthGate.ensureFreshIdToken(forceRefresh: false);

    if (kIsWeb) {
      return _addRoomViaReadWrite(id, cleaned);
    }
    try {
      return await FirebaseFirestore.instance.runTransaction((tx) async {
        final ref = _col.doc(id);
        final snap = await tx.get(ref);
        final next = _computeNext(snap.data(), cleaned);
        tx.set(
          ref,
          {
            fieldRoomCount: next.roomCount,
            fieldTotalRooms: next.roomCount,
            fieldRoomLabels: next.roomLabels,
            'updatedAt': FieldValue.serverTimestamp(),
            'updatedBy': authUid,
          },
          SetOptions(merge: true),
        );
        return next;
      });
    } catch (e) {
      debugPrint('[AeRoomInventory] transaction failed, fallback: $e');
      return _addRoomViaReadWrite(id, cleaned);
    }
  }

  static Future<AeRoomInventory> _addRoomViaReadWrite(
    String id,
    String cleaned,
  ) async {
    final snap = await _col.doc(id).get();
    final next = _computeNext(snap.data(), cleaned);
    await EstablishmentFirestoreWrite.mergeFields(id, {
      fieldRoomCount: next.roomCount,
      fieldTotalRooms: next.roomCount,
      fieldRoomLabels: next.roomLabels,
    });
    return next;
  }

  static AeRoomInventory _computeNext(
    Map<String, dynamic>? data,
    String cleaned,
  ) {
    final current = fromEstablishmentMap(data);
    final labels = List<String>.from(current.options);
    final key = cleaned.toLowerCase();
    if (labels.any((e) => e.toLowerCase() == key)) {
      throw StateError('Room "$cleaned" already exists.');
    }

    final n = int.tryParse(cleaned);
    if (n != null && n >= 1) {
      // Expand sequential inventory through N so 20→21 adds Room 21 only
      // (1…20 already present); entering 25 fills 21…25.
      for (var i = 1; i <= n; i++) {
        final s = '$i';
        if (!labels.any((e) => e.toLowerCase() == s)) labels.add(s);
      }
    } else {
      labels.add(cleaned);
    }

    return AeRoomInventory(roomCount: labels.length, roomLabels: labels);
  }
}

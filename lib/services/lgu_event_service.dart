import 'dart:async' show unawaited;
import 'dart:convert';

import 'package:atmos_trs_system/services/announcement_push_service.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;

/// LGU-submitted events stored in the `announcements` collection.
/// New posts auto-publish immediately (no Governor approval). Visible to
/// tourists, all LGUs, and the Governor as soon as they are created.
class LguEventService {
  LguEventService({FirebaseFirestore? firestore})
      : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

  static const String collection = 'announcements';
  static const String typeEvent = 'Event';
  static const String typePromo = 'Promo';
  static const String typeAlert = 'Alert';
  static const String typeGeneral = 'General';

  /// Max base64 length for Firestore fallback (~90KB decoded JPEG).
  static const int maxImageBase64Length = 120000;

  /// Categories LGUs can pick when creating a post.
  static const List<String> postTypes = [
    typeEvent,
    typePromo,
    typeAlert,
    typeGeneral,
  ];

  static String normalizeType(String? raw) {
    final t = raw?.trim() ?? '';
    for (final option in postTypes) {
      if (option.toLowerCase() == t.toLowerCase()) return option;
    }
    return typeEvent;
  }

  static String statusOf(Map<String, dynamic> data) {
    final raw = data['status']?.toString().trim().toLowerCase() ?? '';
    if (raw == 'approved' || raw == 'pending' || raw == 'rejected') {
      return raw;
    }
    if (data['published'] == true) return 'approved';
    return 'pending';
  }

  /// Live posts tourists / province feeds may show.
  static bool isVisibleToTourists(Map<String, dynamic> data) {
    if (data['published'] != true) return false;
    final status = statusOf(data);
    // Rejected must stay hidden even if published was left true by mistake.
    return status != 'rejected';
  }

  static String displayStatus(Map<String, dynamic> data) {
    switch (statusOf(data)) {
      case 'approved':
        return data['published'] == true ? 'Live' : 'Unpublished';
      case 'rejected':
        return 'Rejected (legacy)';
      default:
        return 'Pending (legacy)';
    }
  }

  static String sourceMunicipalityLabel(Map<String, dynamic> data) {
    final name = data['municipalityName']?.toString().trim() ?? '';
    if (name.isNotEmpty) return name;
    final id = data['municipalityId']?.toString().trim() ?? '';
    return id.isEmpty ? 'LGU' : id;
  }

  /// Resolves a displayable image for tourist/LGU UI.
  /// Prefers Storage [imageUrl]; falls back to [imageBase64] as a data URI.
  static String? resolveDisplayImage(Map<String, dynamic>? data) {
    if (data == null) return null;
    for (final key in ['imageUrl', 'image_url', 'image', 'photoUrl', 'photo']) {
      final url = data[key]?.toString().trim();
      if (url != null && url.isNotEmpty) return url;
    }
    final b64 = data['imageBase64']?.toString().trim() ??
        data['image_base64']?.toString().trim();
    if (b64 == null || b64.isEmpty) return null;
    if (b64.startsWith('data:')) return b64;
    return 'data:image/jpeg;base64,$b64';
  }

  Future<List<Map<String, dynamic>>> loadForMunicipality(
    String municipalityId,
  ) async {
    if (municipalityId.trim().isEmpty || Firebase.apps.isEmpty) return [];
    final queryIds = _municipalityQueryIds(municipalityId);
    try {
      QuerySnapshot<Map<String, dynamic>> snap;
      try {
        snap = await _firestore
            .collection(collection)
            .where('municipalityId', whereIn: queryIds.take(10).toList())
            .get();
      } catch (e) {
        debugPrint('[LguEventService] whereIn fallback: $e');
        snap = await _firestore.collection(collection).limit(80).get();
      }
      final list = snap.docs
          .map((d) => {'id': d.id, ...d.data()})
          .where((e) => _matchesMunicipality(e, municipalityId))
          .toList();
      list.sort(_sortByCreatedAtDesc);
      return list;
    } catch (e) {
      debugPrint('[LguEventService] loadForMunicipality: $e');
      return [];
    }
  }

  /// Province-wide published events (all LGUs) for cross-LGU feeds.
  Future<List<Map<String, dynamic>>> loadPublishedProvinceWide({
    int limit = 120,
  }) async {
    if (Firebase.apps.isEmpty) return [];
    try {
      QuerySnapshot<Map<String, dynamic>> snap;
      try {
        snap = await _firestore
            .collection(collection)
            .where('published', isEqualTo: true)
            .limit(limit)
            .get();
      } catch (_) {
        snap = await _firestore.collection(collection).limit(limit).get();
      }
      final list = snap.docs
          .map((d) => {'id': d.id, ...d.data()})
          .where(isVisibleToTourists)
          .toList();
      list.sort(_sortByCreatedAtDesc);
      return list;
    } catch (e) {
      debugPrint('[LguEventService] loadPublishedProvinceWide: $e');
      return [];
    }
  }

  static String? _cacheMunId;
  static DateTime? _cacheAt;
  static List<Map<String, dynamic>>? _cachedMine;
  static List<Map<String, dynamic>>? _cachedProvince;
  static const Duration _cacheTtl = Duration(minutes: 2);

  static void invalidateEventsCache() {
    _cacheMunId = null;
    _cacheAt = null;
    _cachedMine = null;
    _cachedProvince = null;
  }

  static ({List<Map<String, dynamic>> mine, List<Map<String, dynamic>> province})?
      peekEventsCache(String municipalityId) {
    final mid = municipalityId.trim();
    if (mid.isEmpty ||
        _cacheMunId != mid ||
        _cacheAt == null ||
        _cachedMine == null ||
        _cachedProvince == null) {
      return null;
    }
    if (DateTime.now().difference(_cacheAt!) > _cacheTtl) return null;
    return (mine: _cachedMine!, province: _cachedProvince!);
  }

  static void _storeEventsCache({
    required String municipalityId,
    required List<Map<String, dynamic>> mine,
    required List<Map<String, dynamic>> province,
  }) {
    _cacheMunId = municipalityId.trim();
    _cacheAt = DateTime.now();
    _cachedMine = mine;
    _cachedProvince = province;
  }

  /// Parallel mine + province load with short in-memory cache (smooth Events tab).
  Future<({List<Map<String, dynamic>> mine, List<Map<String, dynamic>> province})>
      loadMineAndProvince(String municipalityId) async {
    final cached = peekEventsCache(municipalityId);
    if (cached != null) return cached;

    final results = await Future.wait<List<Map<String, dynamic>>>([
      loadForMunicipality(municipalityId),
      loadPublishedProvinceWide(),
    ]);
    final mine = results[0];
    final province = results[1];
    _storeEventsCache(
      municipalityId: municipalityId,
      mine: mine,
      province: province,
    );
    return (mine: mine, province: province);
  }

  /// Warm cache after LGU login so Events opens without a multi-second wait.
  Future<void> prefetchForLgu(String municipalityId) async {
    final mid = municipalityId.trim();
    if (mid.isEmpty) return;
    try {
      await loadMineAndProvince(mid);
    } catch (e) {
      debugPrint('[LguEventService] prefetchForLgu: $e');
    }
  }

  Future<List<Map<String, dynamic>>> loadAllForGovernor() async {
    if (Firebase.apps.isEmpty) return [];
    try {
      QuerySnapshot<Map<String, dynamic>> snap;
      try {
        snap = await _firestore
            .collection(collection)
            .orderBy('createdAt', descending: true)
            .limit(100)
            .get();
      } catch (_) {
        snap = await _firestore.collection(collection).limit(100).get();
      }
      final list = snap.docs.map((d) => {'id': d.id, ...d.data()}).toList();
      list.sort(_sortByCreatedAtDesc);
      return list;
    } catch (e) {
      debugPrint('[LguEventService] loadAllForGovernor: $e');
      return [];
    }
  }

  /// Creates and auto-publishes an LGU event, then notifies installed tourist apps.
  Future<String?> createEvent({
    required String municipalityId,
    required String municipalityName,
    required String title,
    required String content,
    String type = typeEvent,
    Uint8List? imageBytes,
    String? imageContentType,
  }) async {
    if (title.trim().isEmpty) return null;
    if (Firebase.apps.isEmpty) {
      throw StateError('Firebase is not initialized.');
    }
    final user = FirebaseAuth.instance.currentUser;
    final docRef = _firestore.collection(collection).doc();
    final normalizedType = normalizeType(type);
    final munName = municipalityName.trim().isNotEmpty
        ? municipalityName.trim()
        : (user?.email ?? 'LGU');

    final imageFields = await _resolveImageFields(
      eventId: docRef.id,
      municipalityId: municipalityId,
      bytes: imageBytes,
      contentType: imageContentType,
      requiredIfBytesPresent: true,
    );

    final data = <String, dynamic>{
      'title': title.trim(),
      'content': content.trim(),
      'type': normalizedType,
      // Auto-publish: no Governor approval required.
      'status': 'approved',
      'published': true,
      'autoPublished': true,
      'date': DateTime.now().toIso8601String().split('T').first,
      'createdAt': FieldValue.serverTimestamp(),
      'publishedAt': FieldValue.serverTimestamp(),
      'createdBy': munName,
      'createdByUid': user?.uid,
      'municipalityId': municipalityId,
      'municipalityName': munName,
      ...imageFields,
    };

    await docRef.set(data);

    // Best-effort FCM to tourists; LGUs/Governor pick up via Firestore listeners.
    final pushBody = content.trim().isEmpty
        ? 'New $normalizedType from $munName'
        : content.trim();
    unawaited(
      AnnouncementPushService.broadcastToInstalledApps(
        title: '${title.trim()} · $munName',
        content: pushBody,
        type: normalizedType,
        announcementId: docRef.id,
      ),
    );

    return docRef.id;
  }

  Future<void> updateEvent({
    required String eventId,
    required String municipalityId,
    required String title,
    required String content,
    String type = typeEvent,
    Uint8List? imageBytes,
    String? imageContentType,
    bool removeImage = false,
    /// Kept for call-site compatibility; edits no longer reset to pending.
    bool resubmitForApproval = false,
  }) async {
    final updates = <String, dynamic>{
      'title': title.trim(),
      'content': content.trim(),
      'type': normalizeType(type),
      'updatedAt': FieldValue.serverTimestamp(),
      // Stay live after edits (no re-approval).
      'status': 'approved',
      'published': true,
    };

    if (removeImage) {
      updates['imageUrl'] = FieldValue.delete();
      updates['imageBase64'] = FieldValue.delete();
    } else if (imageBytes != null && imageBytes.isNotEmpty) {
      final imageFields = await _resolveImageFields(
        eventId: eventId,
        municipalityId: municipalityId,
        bytes: imageBytes,
        contentType: imageContentType,
        requiredIfBytesPresent: true,
      );
      updates.addAll(imageFields);
      if (!imageFields.containsKey('imageUrl')) {
        updates['imageUrl'] = FieldValue.delete();
      }
      if (!imageFields.containsKey('imageBase64')) {
        updates['imageBase64'] = FieldValue.delete();
      }
    }

    await _firestore.collection(collection).doc(eventId).update(updates);
  }

  Future<void> deleteEvent(String eventId) async {
    await _firestore.collection(collection).doc(eventId).delete();
  }

  /// Legacy: keep for older pending items a Governor may still want to publish.
  Future<void> approveEvent({
    required String eventId,
    String? approvedBy,
  }) async {
    await _firestore.collection(collection).doc(eventId).update({
      'status': 'approved',
      'published': true,
      'approvedAt': FieldValue.serverTimestamp(),
      'publishedAt': FieldValue.serverTimestamp(),
      'approvedBy': approvedBy ?? 'Governor',
      'rejectedReason': FieldValue.delete(),
    });
  }

  /// Legacy reject path (new posts are not rejected).
  Future<void> rejectEvent({
    required String eventId,
    String? reason,
    String? rejectedBy,
  }) async {
    await _firestore.collection(collection).doc(eventId).update({
      'status': 'rejected',
      'published': false,
      'rejectedAt': FieldValue.serverTimestamp(),
      'rejectedBy': rejectedBy ?? 'Governor',
      if (reason != null && reason.trim().isNotEmpty)
        'rejectedReason': reason.trim(),
    });
  }

  Future<void> unpublishEvent(String eventId) async {
    await _firestore.collection(collection).doc(eventId).update({
      'published': false,
    });
  }

  /// Uploads to Storage; on failure stores compressed JPEG as [imageBase64].
  Future<Map<String, dynamic>> _resolveImageFields({
    required String eventId,
    required String municipalityId,
    Uint8List? bytes,
    String? contentType,
    required bool requiredIfBytesPresent,
  }) async {
    if (bytes == null || bytes.isEmpty) return {};

    final ct = _normalizeContentType(contentType);
    final url = await _uploadImage(
      eventId: eventId,
      municipalityId: municipalityId,
      bytes: bytes,
      contentType: ct,
    );
    if (url != null && url.isNotEmpty) {
      return {'imageUrl': url};
    }

    final b64 = _imageBase64ForFirestore(bytes);
    if (b64 != null && b64.isNotEmpty) {
      debugPrint(
        '[LguEventService] Storage upload failed; saved imageBase64 fallback '
        '(${b64.length} chars)',
      );
      return {'imageBase64': b64};
    }

    if (requiredIfBytesPresent) {
      throw StateError(
        'Could not upload the photo. Check your connection and try again.',
      );
    }
    return {};
  }

  static String _normalizeContentType(String? contentType) {
    final raw = contentType?.trim() ?? '';
    if (raw.startsWith('image/')) return raw;
    if (raw == 'png' || raw.endsWith('.png')) return 'image/png';
    if (raw == 'webp' || raw.endsWith('.webp')) return 'image/webp';
    if (raw == 'gif' || raw.endsWith('.gif')) return 'image/gif';
    return 'image/jpeg';
  }

  Future<String?> _uploadImage({
    required String eventId,
    required String municipalityId,
    required Uint8List bytes,
    required String contentType,
  }) async {
    try {
      final ext = contentType.contains('png')
          ? 'png'
          : contentType.contains('webp')
              ? 'webp'
              : 'jpg';
      final folder = municipalityId
          .trim()
          .toLowerCase()
          .replaceAll(RegExp(r'[^a-z0-9_-]+'), '_');
      final safeFolder = folder.isEmpty ? 'unknown' : folder;
      final ref = FirebaseStorage.instance.ref().child(
        'lgu_events/$safeFolder/$eventId.$ext',
      );
      final task = await ref.putData(
        bytes,
        SettableMetadata(contentType: contentType),
      );
      return await task.ref.getDownloadURL();
    } catch (e) {
      debugPrint('[LguEventService] image upload failed: $e');
      return null;
    }
  }

  static String? _imageBase64ForFirestore(Uint8List raw) {
    var bytes = _compressJpeg(raw, maxSide: 1280, quality: 75);
    var encoded = base64Encode(bytes);
    if (encoded.length <= maxImageBase64Length) return encoded;

    bytes = _compressJpeg(bytes, maxSide: 960, quality: 65);
    encoded = base64Encode(bytes);
    if (encoded.length <= maxImageBase64Length) return encoded;

    bytes = _compressJpeg(bytes, maxSide: 720, quality: 55);
    encoded = base64Encode(bytes);
    if (encoded.length <= maxImageBase64Length) return encoded;

    return null;
  }

  static Uint8List _compressJpeg(
    Uint8List raw, {
    required int maxSide,
    required int quality,
  }) {
    try {
      final decoded = img.decodeImage(raw);
      if (decoded == null) return raw;
      var work = decoded;
      if (work.width > maxSide || work.height > maxSide) {
        if (work.width >= work.height) {
          work = img.copyResize(work, width: maxSide);
        } else {
          work = img.copyResize(work, height: maxSide);
        }
      }
      return Uint8List.fromList(img.encodeJpg(work, quality: quality));
    } catch (e) {
      debugPrint('[LguEventService] compress skipped: $e');
      return raw;
    }
  }

  static int _sortByCreatedAtDesc(
    Map<String, dynamic> a,
    Map<String, dynamic> b,
  ) {
    final aTs = a['publishedAt'] ?? a['createdAt'];
    final bTs = b['publishedAt'] ?? b['createdAt'];
    if (aTs is Timestamp && bTs is Timestamp) {
      return bTs.compareTo(aTs);
    }
    return (b['date']?.toString() ?? '').compareTo(a['date']?.toString() ?? '');
  }

  static bool matchesMunicipality(
    Map<String, dynamic> event,
    String municipalityId,
  ) =>
      _matchesMunicipality(event, municipalityId);

  static List<String> municipalityQueryIds(String municipalityId) =>
      _municipalityQueryIds(municipalityId);

  static List<String> _municipalityQueryIds(String municipalityId) {
    final normalized = municipalityId.trim().toLowerCase();
    return {
      municipalityId,
      normalized,
      normalized.replaceAll(' ', '_'),
      normalized.replaceAll('_', ' '),
    }.where((s) => s.isNotEmpty).toList();
  }

  static bool _matchesMunicipality(
    Map<String, dynamic> event,
    String municipalityId,
  ) {
    final eventId =
        event['municipalityId']?.toString().trim().toLowerCase() ?? '';
    final target = municipalityId.trim().toLowerCase();
    if (eventId.isEmpty) return false;
    return eventId == target ||
        eventId.replaceAll('_', ' ') == target.replaceAll('_', ' ');
  }
}

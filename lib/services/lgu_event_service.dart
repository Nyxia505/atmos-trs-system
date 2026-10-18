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
  static const String typeOther = 'Other';

  static const List<String> postTypes = [
    typeEvent,
    typePromo,
    typeAlert,
    typeGeneral,
    typeOther,
  ];

  static const int maxGalleryImages = 6;

  static String normalizeType(String? raw) {
    final t = raw?.trim() ?? '';
    if (t.isEmpty || t.toLowerCase() == typeOther.toLowerCase()) {
      return typeEvent;
    }
    for (final option in postTypes) {
      if (option == typeOther) continue;
      if (option.toLowerCase() == t.toLowerCase()) return option;
    }
    return t.length > 40 ? t.substring(0, 40) : t;
  }

  /// Philippines has no daylight saving. Wall times are stored as this offset.
  static const Duration manilaOffset = Duration(hours: 8);
  static const int maxDurationDays = 60;

  static DateTime manilaNow() {
    final shifted = DateTime.now().toUtc().add(manilaOffset);
    return DateTime(
      shifted.year,
      shifted.month,
      shifted.day,
      shifted.hour,
      shifted.minute,
      shifted.second,
    );
  }

  static DateTime manilaWallFromInstant(DateTime instant) {
    final shifted = instant.toUtc().add(manilaOffset);
    return DateTime(
      shifted.year,
      shifted.month,
      shifted.day,
      shifted.hour,
      shifted.minute,
    );
  }

  static DateTime instantFromManilaWall(DateTime wall) {
    return DateTime.utc(
      wall.year,
      wall.month,
      wall.day,
      wall.hour,
      wall.minute,
    ).subtract(manilaOffset);
  }

  static bool isAllDay(Map<String, dynamic> data) => data['allDay'] == true;

  static bool _usesManilaClock(Map<String, dynamic> data) =>
      data['endsAt'] != null || data['allDay'] == true;

  static DateTime? _readDate(dynamic raw) {
    if (raw is Timestamp) return raw.toDate();
    if (raw is DateTime) return raw;
    final text = raw?.toString().trim() ?? '';
    if (text.isEmpty) return null;
    return DateTime.tryParse(text);
  }

  static DateTime? eventStart(Map<String, dynamic> data) {
    final raw = _readDate(data['startsAt'] ?? data['startDate'] ?? data['date']);
    if (raw == null) return null;
    if (_usesManilaClock(data)) return manilaWallFromInstant(raw);
    return raw;
  }

  static DateTime? eventEnd(Map<String, dynamic> data) {
    final explicit = _readDate(data['endsAt']);
    if (explicit != null) return manilaWallFromInstant(explicit);
    final start = eventStart(data);
    if (start == null) return null;
    final startDay = DateTime(start.year, start.month, start.day);
    return startDay.add(Duration(days: eventDurationDays(data)));
  }

  static int eventDurationDays(Map<String, dynamic> data) {
    final start = eventStart(data);
    final end = _readDate(data['endsAt']);
    if (start != null && end != null) {
      final endWall = manilaWallFromInstant(end);
      final days = durationDaysForRange(
        startDate: start,
        endDate: isAllDay(data)
            ? endWall.subtract(const Duration(days: 1))
            : endWall,
      );
      if (days > maxDurationDays) return maxDurationDays;
      return days;
    }
    final raw = data['durationDays'];
    final parsed = raw is num ? raw.toInt() : int.tryParse('$raw') ?? 1;
    if (parsed < 1) return 1;
    if (parsed > maxDurationDays) return maxDurationDays;
    return parsed;
  }

  static int durationDaysForRange({
    required DateTime startDate,
    required DateTime endDate,
  }) {
    final startDay = DateTime(startDate.year, startDate.month, startDate.day);
    final endDay = DateTime(endDate.year, endDate.month, endDate.day);
    final days = endDay.difference(startDay).inDays + 1;
    if (days < 1) return 1;
    return days;
  }

  /// Null when the range is valid. Otherwise a short message for the form.
  static String? validateSchedule({
    required DateTime startDate,
    required DateTime endDate,
    required bool allDay,
    int startHour = 0,
    int startMinute = 0,
    int endHour = 23,
    int endMinute = 59,
  }) {
    final start = DateTime(
      startDate.year,
      startDate.month,
      startDate.day,
      allDay ? 0 : startHour,
      allDay ? 0 : startMinute,
    );
    final end = DateTime(
      endDate.year,
      endDate.month,
      endDate.day,
      allDay ? 23 : endHour,
      allDay ? 59 : endMinute,
    );
    if (!end.isAfter(start)) {
      return allDay
          ? 'End date must be on or after the start date.'
          : 'End must be after the start time.';
    }
    final days = durationDaysForRange(startDate: start, endDate: end);
    if (days > maxDurationDays) {
      return 'Duration cannot be longer than $maxDurationDays days.';
    }
    return null;
  }

  static ({DateTime start, DateTime end, int days}) resolveWindow({
    required DateTime startDate,
    required DateTime endDate,
    required bool allDay,
    int startHour = 0,
    int startMinute = 0,
    int endHour = 23,
    int endMinute = 59,
  }) {
    final startWall = DateTime(
      startDate.year,
      startDate.month,
      startDate.day,
      allDay ? 0 : startHour,
      allDay ? 0 : startMinute,
    );
    final endWall = allDay
        ? DateTime(endDate.year, endDate.month, endDate.day)
            .add(const Duration(days: 1))
        : DateTime(
            endDate.year,
            endDate.month,
            endDate.day,
            endHour,
            endMinute,
          );
    return (
      start: instantFromManilaWall(startWall),
      end: instantFromManilaWall(endWall),
      days: durationDaysForRange(startDate: startWall, endDate: endDate),
    );
  }

  static DateTime _clockFor(Map<String, dynamic> data, DateTime? now) {
    if (now != null) return now;
    if (_usesManilaClock(data)) return manilaNow();
    return DateTime.now();
  }

  /// Live from the start instant until the end instant.
  /// Posts with no start date stay on the old always-live rule.
  static bool isWithinSchedule(Map<String, dynamic> data, [DateTime? now]) {
    final start = eventStart(data);
    if (start == null) return true;
    final end = eventEnd(data);
    if (end == null) return true;
    final clock = _clockFor(data, now);
    return !clock.isBefore(start) && clock.isBefore(end);
  }

  /// Upcoming, Ongoing, Scheduled, or Expired.
  static String schedulePhase(Map<String, dynamic> data, [DateTime? now]) {
    final start = eventStart(data);
    if (start == null) {
      return data['published'] == true ? 'Ongoing' : 'Scheduled';
    }
    final clock = _clockFor(data, now);
    final end = eventEnd(data);
    if (end != null && !clock.isBefore(end)) return 'Expired';
    if (!clock.isBefore(start)) return 'Ongoing';
    if (start.difference(clock).inHours <= 48) return 'Upcoming';
    return 'Scheduled';
  }

  static String _ymd(DateTime value) =>
      '${value.year}-${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')}';

  static String _hm(DateTime value) =>
      '${value.hour.toString().padLeft(2, '0')}:${value.minute.toString().padLeft(2, '0')}';

  static String scheduleLabel(Map<String, dynamic> data) {
    final start = eventStart(data);
    if (start == null) return '';
    final end = eventEnd(data);
    final days = eventDurationDays(data);
    if (isAllDay(data)) {
      final last = end == null
          ? start
          : end.subtract(const Duration(minutes: 1));
      final range = days <= 1 ? _ymd(start) : '${_ymd(start)} – ${_ymd(last)}';
      return '$range · All day · $days day${days == 1 ? '' : 's'}';
    }
    if (end == null || days <= 1 && _ymd(start) == _ymd(end)) {
      if (!_usesManilaClock(data)) return _ymd(start);
      final endText = end == null ? '' : ' – ${_hm(end)}';
      return '${_ymd(start)} ${_hm(start)}$endText';
    }
    final endShown = end;
    return '${_ymd(start)} ${_hm(start)} – ${_ymd(endShown)} ${_hm(endShown)} · $days days';
  }

  static bool occursOnDay(Map<String, dynamic> data, DateTime day) {
    final start = eventStart(data);
    if (start == null) return false;
    final end = eventEnd(data);
    final date = DateTime(day.year, day.month, day.day);
    final startDay = DateTime(start.year, start.month, start.day);
    if (end == null) return date == startDay;
    if (isAllDay(data) ||
        (end.hour == 0 && end.minute == 0 && end.second == 0)) {
      final endDay = DateTime(end.year, end.month, end.day);
      return !date.isBefore(startDay) && date.isBefore(endDay);
    }
    final endDay = DateTime(end.year, end.month, end.day);
    return !date.isBefore(startDay) && !date.isAfter(endDay);
  }

  static List<String> imageUrlsOf(Map<String, dynamic> data) {
    final urls = <String>[];
    final gallery = data['imageUrls'];
    if (gallery is List) {
      for (final item in gallery) {
        final url = item?.toString().trim() ?? '';
        if (url.isNotEmpty && !urls.contains(url)) urls.add(url);
      }
    }
    final cover = resolveDisplayImage(data);
    if (cover != null && cover.isNotEmpty && !urls.contains(cover)) {
      urls.insert(0, cover);
    }
    return urls;
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
  /// A scheduled post stays hidden until its Manila window opens, even if the
  /// backend flag has not flipped yet. Expired posts stay hidden.
  static bool isVisibleToTourists(Map<String, dynamic> data) {
    final status = statusOf(data);
    if (status == 'rejected') return false;
    if (!isWithinSchedule(data)) return false;
    if (data['published'] == true) return true;
    final state = data['scheduleState']?.toString() ?? '';
    return state == 'scheduled' || state == 'live';
  }

  static String displayStatus(Map<String, dynamic> data) {
    if (statusOf(data) == 'rejected') return 'Rejected (legacy)';
    if (eventStart(data) != null || data['scheduleState'] != null) {
      return schedulePhase(data);
    }
    switch (statusOf(data)) {
      case 'approved':
        return data['published'] == true ? 'Ongoing' : 'Scheduled';
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

  /// Reserves a Firestore id so the photo can upload before the post is saved.
  String newEventId() => _firestore.collection(collection).doc().id;

  /// Starts the photo upload right away (e.g. when the LGU picks it) so
  /// Publish only has to wait for the Firestore write.
  Future<Map<String, dynamic>> prepareImageFields({
    required String eventId,
    required String municipalityId,
    required Uint8List bytes,
    String? contentType,
  }) {
    return _resolveImageFields(
      eventId: eventId,
      municipalityId: municipalityId,
      bytes: bytes,
      contentType: contentType,
      requiredIfBytesPresent: true,
    );
  }

  /// Creates and auto-publishes an LGU event, then notifies installed tourist apps.
  Future<String?> createEvent({
    required String municipalityId,
    required String municipalityName,
    required String title,
    required String content,
    String type = typeEvent,
    String? eventId,
    Uint8List? imageBytes,
    String? imageContentType,
    Future<Map<String, dynamic>>? preparedImageFields,
    DateTime? startsAt,
    DateTime? endsAt,
    bool allDay = true,
    int durationDays = 1,
    List<Uint8List> galleryBytes = const [],
  }) async {
    if (title.trim().isEmpty) return null;
    if (Firebase.apps.isEmpty) {
      throw StateError('Firebase is not initialized.');
    }
    final user = FirebaseAuth.instance.currentUser;
    final reservedId = eventId?.trim() ?? '';
    final docRef = reservedId.isNotEmpty
        ? _firestore.collection(collection).doc(reservedId)
        : _firestore.collection(collection).doc();
    final normalizedType = normalizeType(type);
    final munName = municipalityName.trim().isNotEmpty
        ? municipalityName.trim()
        : (user?.email ?? 'LGU');

    final imageFields = preparedImageFields != null
        ? await preparedImageFields
        : await _resolveImageFields(
            eventId: docRef.id,
            municipalityId: municipalityId,
            bytes: imageBytes,
            contentType: imageContentType,
            requiredIfBytesPresent: true,
          );

    final existing = await docRef.get();
    if (existing.exists) {
      throw StateError('This post was already published.');
    }

    final gallery = await _uploadGallery(
      eventId: docRef.id,
      municipalityId: municipalityId,
      bytesList: galleryBytes,
    );
    final window = _windowForWrite(
      startsAt: startsAt,
      endsAt: endsAt,
      allDay: allDay,
      durationDays: durationDays,
    );
    final liveNow = _windowIsOpen(window);
    final data = <String, dynamic>{
      'title': title.trim(),
      'content': content.trim(),
      'type': normalizedType,
      'status': 'approved',
      'published': liveNow,
      'autoPublished': true,
      'scheduleState': liveNow ? 'live' : 'scheduled',
      'allDay': allDay,
      'startsAt': Timestamp.fromDate(window.start),
      'endsAt': Timestamp.fromDate(window.end),
      'durationDays': window.days,
      'timezone': 'Asia/Manila',
      'date': _ymd(manilaWallFromInstant(window.start)),
      'createdAt': FieldValue.serverTimestamp(),
      if (liveNow) 'publishedAt': FieldValue.serverTimestamp(),
      'createdBy': munName,
      'createdByUid': user?.uid,
      'municipalityId': municipalityId,
      'municipalityName': munName,
      ...imageFields,
      if (gallery.isNotEmpty) 'imageUrls': gallery,
      if (gallery.isNotEmpty && !imageFields.containsKey('imageUrl'))
        'imageUrl': gallery.first,
    };

    await docRef.set(data);

    if (liveNow) {
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
    }

    return docRef.id;
  }

  /// [startsAt] and [endsAt] are Asia/Manila wall-clock values from the form.
  /// All-day [endsAt] is the last inclusive calendar day.
  static ({DateTime start, DateTime end, int days}) _windowForWrite({
    DateTime? startsAt,
    DateTime? endsAt,
    required bool allDay,
    required int durationDays,
  }) {
    final seed = startsAt ?? manilaNow();
    final startWall = DateTime(
      seed.year,
      seed.month,
      seed.day,
      allDay ? 0 : seed.hour,
      allDay ? 0 : seed.minute,
    );
    final safeDays = durationDays < 1
        ? 1
        : (durationDays > maxDurationDays ? maxDurationDays : durationDays);
    final endSeed = endsAt ??
        DateTime(startWall.year, startWall.month, startWall.day).add(
          Duration(days: safeDays - 1),
        );
    final inclusiveEnd = DateTime(endSeed.year, endSeed.month, endSeed.day);
    final endWall = allDay
        ? inclusiveEnd.add(const Duration(days: 1))
        : DateTime(
            endSeed.year,
            endSeed.month,
            endSeed.day,
            endSeed.hour,
            endSeed.minute,
          );
    return (
      start: instantFromManilaWall(startWall),
      end: instantFromManilaWall(endWall),
      days: durationDaysForRange(startDate: startWall, endDate: inclusiveEnd),
    );
  }

  static bool _windowIsOpen(({DateTime start, DateTime end, int days}) window) {
    final now = DateTime.now().toUtc();
    return !now.isBefore(window.start.toUtc()) && now.isBefore(window.end.toUtc());
  }

  Future<void> updateEvent({
    required String eventId,
    required String municipalityId,
    required String title,
    required String content,
    String type = typeEvent,
    Uint8List? imageBytes,
    String? imageContentType,
    Future<Map<String, dynamic>>? preparedImageFields,
    bool removeImage = false,
    /// Kept for call-site compatibility; edits no longer reset to pending.
    bool resubmitForApproval = false,
    DateTime? startsAt,
    DateTime? endsAt,
    bool? allDay,
    int? durationDays,
    List<Uint8List> galleryBytes = const [],
  }) async {
    final ref = _firestore.collection(collection).doc(eventId);
    final snap = await ref.get();
    if (!snap.exists) {
      throw StateError('This post no longer exists.');
    }
    final current = snap.data() ?? {};
    if (!matchesMunicipality(current, municipalityId)) {
      throw StateError('You can only edit posts from your municipality.');
    }
    final wasPublished = current['published'] == true;
    final updates = <String, dynamic>{
      'title': title.trim(),
      'content': content.trim(),
      'type': normalizeType(type),
      'updatedAt': FieldValue.serverTimestamp(),
      'status': 'approved',
    };

    if (removeImage) {
      updates['imageUrl'] = FieldValue.delete();
      updates['imageBase64'] = FieldValue.delete();
    } else if (preparedImageFields != null ||
        (imageBytes != null && imageBytes.isNotEmpty)) {
      final imageFields = preparedImageFields != null
          ? await preparedImageFields
          : await _resolveImageFields(
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
    final dayLong = allDay ?? isAllDay(current);
    final window = _windowForWrite(
      startsAt: startsAt ?? eventStart(current),
      endsAt: endsAt ?? _inclusiveEndWall(current),
      allDay: dayLong,
      durationDays: durationDays ?? eventDurationDays(current),
    );
    final liveNow = _windowIsOpen(window);
    updates['allDay'] = dayLong;
    updates['startsAt'] = Timestamp.fromDate(window.start);
    updates['endsAt'] = Timestamp.fromDate(window.end);
    updates['durationDays'] = window.days;
    updates['timezone'] = 'Asia/Manila';
    updates['date'] = _ymd(manilaWallFromInstant(window.start));
    updates['published'] = liveNow;
    updates['scheduleState'] = liveNow
        ? 'live'
        : (DateTime.now().toUtc().isBefore(window.start.toUtc())
            ? 'scheduled'
            : 'expired');
    if (liveNow && !wasPublished) {
      updates['publishedAt'] = FieldValue.serverTimestamp();
    }
    if (galleryBytes.isNotEmpty) {
      final gallery = await _uploadGallery(
        eventId: eventId,
        municipalityId: municipalityId,
        bytesList: galleryBytes,
      );
      if (gallery.isNotEmpty) {
        updates['imageUrls'] = gallery;
        updates.putIfAbsent('imageUrl', () => gallery.first);
      }
    }

    await ref.update(updates);
    if (liveNow && !wasPublished) {
      final munName = current['municipalityName']?.toString().trim() ?? '';
      unawaited(
        AnnouncementPushService.broadcastToInstalledApps(
          title: '${title.trim()} · $munName',
          content: content.trim().isEmpty
              ? 'New ${normalizeType(type)} from $munName'
              : content.trim(),
          type: normalizeType(type),
          announcementId: eventId,
        ),
      );
    }
  }

  static DateTime? _inclusiveEndWall(Map<String, dynamic> data) {
    final end = eventEnd(data);
    if (end == null) return null;
    if (isAllDay(data) ||
        (end.hour == 0 && end.minute == 0 && end.second == 0)) {
      return end.subtract(const Duration(days: 1));
    }
    return end;
  }

  Future<List<String>> _uploadGallery({
    required String eventId,
    required String municipalityId,
    required List<Uint8List> bytesList,
  }) async {
    final urls = <String>[];
    for (final bytes in bytesList.take(maxGalleryImages)) {
      if (bytes.isEmpty) continue;
      final fields = await _resolveImageFields(
        eventId: eventId,
        municipalityId: municipalityId,
        bytes: bytes,
        contentType: 'image/jpeg',
        requiredIfBytesPresent: false,
      );
      final url = fields['imageUrl']?.toString() ?? fields['imageBase64']?.toString();
      if (url != null && url.isNotEmpty) urls.add(url);
    }
    return urls;
  }

  Future<void> deleteEvent(
    String eventId, {
    String? municipalityId,
  }) async {
    final ref = _firestore.collection(collection).doc(eventId);
    if (municipalityId != null && municipalityId.trim().isNotEmpty) {
      final snap = await ref.get();
      if (!snap.exists) return;
      if (!matchesMunicipality(snap.data() ?? {}, municipalityId)) {
        throw StateError('You can only delete posts from your municipality.');
      }
    }
    await ref.delete();
  }

  /// Live updates for the LGU calendar and post lists.
  Stream<List<Map<String, dynamic>>> watchAnnouncements() {
    if (Firebase.apps.isEmpty) return const Stream.empty();
    return _firestore.collection(collection).limit(200).snapshots().map(
          (snap) => snap.docs.map((d) => {'id': d.id, ...d.data()}).toList(),
        );
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
      // Unique name per upload: an abandoned pre-upload (dialog cancelled)
      // must never overwrite the photo a live post still points to.
      final stamp = DateTime.now().millisecondsSinceEpoch;
      final ref = FirebaseStorage.instance.ref().child(
        'lgu_events/$safeFolder/${eventId}_$stamp.$ext',
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

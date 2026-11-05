import 'dart:async' show unawaited;

import 'package:atmos_trs_system/data/misamis_occidental_municipalities.dart';
import 'package:atmos_trs_system/services/announcement_push_service.dart';
import 'package:atmos_trs_system/services/supabase_storage_upload.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:trip_plan/catalog_targeting.dart';

/// LGU-submitted events stored in the `announcements` collection.
/// New posts auto-publish immediately (no Governor approval). Visible to
/// tourists, all LGUs, and the Governor as soon as they are created.
class LguEventService {
  LguEventService({FirebaseFirestore? firestore})
      : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

  static const String collection = 'announcements';

  /// Trip Planner catalog already stored in Firestore. Shown on the LGU Events page.
  static const String eventsCollection = 'events';
  static const String typeEvent = 'Event';
  static const String typePromo = 'Promo';
  static const String typeAlert = 'Alert';
  static const String typeGeneral = 'General';

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
    final raw = _readDate(
      data['startsAt'] ??
          data['startAt'] ??
          data['startDate'] ??
          data['date'] ??
          data['publishedAt'],
    );
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
    final cover = resolveDisplayImage(data);
    if (cover != null && cover.isNotEmpty) urls.add(cover);
    final gallery = data['imageUrls'];
    if (gallery is List) {
      for (final item in gallery) {
        final url = item?.toString().trim() ?? '';
        if (url.isNotEmpty && !urls.contains(url)) urls.add(url);
      }
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
  /// Governor/OPTACA catalog notices use [publishedAt] (not a 1-day event window).
  static bool isVisibleToTourists(Map<String, dynamic> data, [DateTime? now]) {
    if (statusOf(data) == 'rejected') return false;
    if (_isCatalogNotice(data)) {
      if (data['published'] == false) return false;
      final release = _catalogReleaseAt(data);
      final clock = now ?? DateTime.now();
      if (release != null && clock.toUtc().isBefore(release.toUtc())) {
        return false;
      }
      return true;
    }
    if (!isWithinSchedule(data, now)) return false;
    if (data['published'] == true) return true;
    final state = data['scheduleState']?.toString() ?? '';
    return state == 'scheduled' || state == 'live';
  }

  static bool isGovernorOwned(Map<String, dynamic> data) {
    final office = _publisherOffice(data);
    if (office == 'governor' ||
        office == 'governor_office' ||
        office == "governor's office") {
      return true;
    }
    final by = data['createdBy']?.toString().trim().toLowerCase() ?? '';
    return by == 'governor' || by == "governor's office";
  }

  static bool isOptacaOwned(Map<String, dynamic> data) {
    final office = _publisherOffice(data);
    if (office == 'optaca' ||
        office == 'provincial' ||
        office == 'provincial_tourism' ||
        office == 'tourism_province') {
      return true;
    }
    final by = data['createdBy']?.toString().trim().toLowerCase() ?? '';
    return by == 'optaca' ||
        by == 'provincial tourism' ||
        by == 'provincial_tourism';
  }

  static bool lguMayManage(
    Map<String, dynamic> data,
    String municipalityId,
  ) {
    if (isGovernorOwned(data) || isOptacaOwned(data)) return false;
    return matchesMunicipality(data, municipalityId);
  }

  static bool isAnnouncementType(Map<String, dynamic> data) {
    final type = normalizeType(data['type']?.toString() ?? data['eventType']?.toString());
    final lower = type.toLowerCase();
    return lower == 'announcement' ||
        lower == typePromo.toLowerCase() ||
        lower == typeAlert.toLowerCase() ||
        lower == typeGeneral.toLowerCase();
  }

  /// Governor municipality-specific posts stay in that LGU feed only.
  /// Province-wide Governor posts and all LGU/OPTACA posts are eligible.
  static bool isTargetedAtLguFeed(
    Map<String, dynamic> data, {
    required String municipalityId,
    String municipalityName = '',
  }) {
    if (!isGovernorOwned(data)) return true;
    if (!_isGovernorMunicipalitySpecific(data)) return true;
    return matchesViewerMunicipality(
      data,
      municipalityId: municipalityId,
      municipalityName: municipalityName,
    );
  }

  /// Province Live: live posts that [isTargetedAtLguFeed] allows for this LGU.
  static bool isEligibleForProvinceLive(
    Map<String, dynamic> data, {
    required String municipalityId,
    String municipalityName = '',
    DateTime? now,
  }) {
    if (!isVisibleToTourists(data, now)) return false;
    return isTargetedAtLguFeed(
      data,
      municipalityId: municipalityId,
      municipalityName: municipalityName,
    );
  }

  static String _publisherOffice(Map<String, dynamic> data) {
    return (data['publisherOffice'] ??
            data['ownerOffice'] ??
            data['publisherRole'] ??
            data['publisher'] ??
            '')
        .toString()
        .trim()
        .toLowerCase();
  }

  /// Governor/OPTACA catalog notices: `publishedAt` is the go-live instant,
  /// not an LGU event window. Dated catalog events keep [startsAt]/[endsAt].
  static bool _isCatalogNotice(Map<String, dynamic> data) {
    if (!(isGovernorOwned(data) || isOptacaOwned(data))) return false;
    if (data['startsAt'] != null ||
        data['startAt'] != null ||
        data['endsAt'] != null) {
      return false;
    }
    return true;
  }

  static DateTime? _catalogReleaseAt(Map<String, dynamic> data) {
    return _readDate(
      data['publishedAt'] ?? data['published_at'] ?? data['createdAt'],
    );
  }

  static bool _isGovernorMunicipalitySpecific(Map<String, dynamic> data) {
    if (isProvinceWideAudience(data)) return false;
    final id = data['municipalityId']?.toString().trim() ?? '';
    final name =
        (data['municipalityName'] ?? data['municipality'] ?? '').toString().trim();
    if (id.isEmpty && name.isEmpty) return false;
    if (id.toLowerCase() == 'province' ||
        id.toLowerCase() == kProvinceWideValue) {
      return false;
    }
    return true;
  }

  static bool isProvinceWideAudience(Map<String, dynamic> data) {
    return isProvinceWideTarget(
      audienceScope:
          (data['audienceScope'] ?? data['targetScope'] ?? '').toString(),
      municipality:
          (data['municipalityName'] ?? data['municipality'] ?? '').toString(),
      municipalityId: (data['municipalityId'] ?? '').toString(),
    );
  }

  static bool matchesViewerMunicipality(
    Map<String, dynamic> data, {
    required String municipalityId,
    String municipalityName = '',
  }) {
    if (matchesMunicipality(data, municipalityId)) return true;
    final label =
        (data['municipalityName'] ?? data['municipality'] ?? '').toString();
    final fromLabel = municipalityIdForLabel(label);
    final target = municipalityId.trim().toLowerCase();
    if (fromLabel.isNotEmpty && fromLabel.toLowerCase() == target) {
      return true;
    }
    final viewerName = municipalityName.trim().toLowerCase();
    return viewerName.isNotEmpty && label.trim().toLowerCase() == viewerName;
  }

  static String displayStatus(Map<String, dynamic> data, [DateTime? now]) {
    if (statusOf(data) == 'rejected') return 'Rejected (legacy)';
    if (_isCatalogNotice(data)) {
      if (data['published'] == false) return 'Scheduled';
      final release = _catalogReleaseAt(data);
      final clock = now ?? DateTime.now();
      if (release != null && clock.toUtc().isBefore(release.toUtc())) {
        return 'Scheduled';
      }
      return 'Ongoing';
    }
    if (eventStart(data) != null || data['scheduleState'] != null) {
      return schedulePhase(data, now);
    }
    switch (statusOf(data)) {
      case 'approved':
        return data['published'] == true ? 'Ongoing' : 'Scheduled';
      default:
        return 'Pending (legacy)';
    }
  }

  static String sourceMunicipalityLabel(Map<String, dynamic> data) {
    if (isProvinceWideAudience(data) ||
        (isGovernorOwned(data) && !_isGovernorMunicipalitySpecific(data))) {
      return kProvinceWideDisplay;
    }
    final name = (data['municipalityName'] ?? data['municipality'])
            ?.toString()
            .trim() ??
        '';
    if (name.isNotEmpty) return name;
    final id = data['municipalityId']?.toString().trim() ?? '';
    if (id.isEmpty || id.toLowerCase() == 'province') {
      return isGovernorOwned(data) ? kProvinceWideDisplay : 'LGU';
    }
    return id;
  }

  /// Resolves a displayable image for tourist/LGU UI.
  /// A saved [imageUrl] wins. A saved [imageBase64] wins over leftover legacy
  /// fields (`image`, `imagePath`, …) so a replaced photo is not hidden by the
  /// previous file after reload.
  static String? resolveDisplayImage(Map<String, dynamic>? data) {
    if (data == null) return null;
    for (final key in ['imageUrl', 'image_url']) {
      final url = data[key]?.toString().trim();
      if (url != null && url.isNotEmpty) return url;
    }
    final embedded = _embeddedImage(data);
    if (embedded != null) return embedded;
    for (final key in ['image', 'imagePath', 'photoUrl', 'photo']) {
      final url = data[key]?.toString().trim();
      if (url != null && url.isNotEmpty) return url;
    }
    return null;
  }

  static String? _embeddedImage(Map<String, dynamic> data) {
    final b64 = data['imageBase64']?.toString().trim() ??
        data['image_base64']?.toString().trim();
    if (b64 == null || b64.isEmpty) return null;
    if (b64.startsWith('data:')) return b64;
    return 'data:image/jpeg;base64,$b64';
  }

  static const List<String> _legacyImageKeys = [
    'imageUrl',
    'image_url',
    'image',
    'imagePath',
    'photoUrl',
    'photo',
    'imageBase64',
    'image_base64',
  ];

  /// Fields to write when the LGU replaces or clears the cover photo.
  /// Every legacy key is updated together so reload cannot resurrect the old file.
  static Map<String, dynamic> coverImageUpdates({
    required Map<String, dynamic> current,
    required Map<String, dynamic> imageFields,
    bool remove = false,
  }) {
    final updates = <String, dynamic>{};
    if (remove) {
      for (final key in _legacyImageKeys) {
        updates[key] = FieldValue.delete();
      }
      updates['imageUrls'] = FieldValue.delete();
      return updates;
    }

    final newUrl = imageFields['imageUrl']?.toString().trim() ?? '';
    final newB64 = imageFields['imageBase64']?.toString().trim() ?? '';
    if (newUrl.isEmpty && newB64.isEmpty) return updates;

    final oldCover = resolveDisplayImage(current);
    final extras = <String>[];
    final gallery = current['imageUrls'];
    if (gallery is List) {
      for (final item in gallery) {
        final url = item?.toString().trim() ?? '';
        if (url.isEmpty || url == oldCover || url == newUrl) continue;
        if (!extras.contains(url)) extras.add(url);
      }
    }

    if (newUrl.isNotEmpty) {
      for (final key in ['imageUrl', 'image_url', 'image', 'imagePath', 'photoUrl', 'photo']) {
        updates[key] = newUrl;
      }
      updates['imageBase64'] = FieldValue.delete();
      updates['image_base64'] = FieldValue.delete();
      updates['imageUrls'] = [newUrl, ...extras];
    } else {
      for (final key in ['imageUrl', 'image_url', 'image', 'imagePath', 'photoUrl', 'photo', 'image_base64']) {
        updates[key] = FieldValue.delete();
      }
      updates['imageBase64'] = newB64;
      if (extras.isEmpty) {
        updates['imageUrls'] = FieldValue.delete();
      } else {
        updates['imageUrls'] = extras;
      }
    }
    return updates;
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
      final list = _mergeById([
        ...snap.docs.map((d) => normalizeAnnouncementDoc(d.id, d.data())),
        ...await _loadEventsCatalog(),
      ]).where((e) => _matchesMunicipality(e, municipalityId)).toList();
      list.sort(compareBySchedule);
      return list;
    } catch (e) {
      debugPrint('[LguEventService] loadForMunicipality: $e');
      final catalog = await _loadEventsCatalog();
      final list = catalog.where((event) => _matchesMunicipality(event, municipalityId)).toList();
      list.sort(compareBySchedule);
      return list;
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
            .limit(limit)
            .get();
      } catch (_) {
        snap = await _firestore.collection(collection).limit(limit).get();
      }
      final list = _mergeById([
        ...snap.docs.map((d) => normalizeAnnouncementDoc(d.id, d.data())),
        ...await _loadEventsCatalog(),
      ]).where(isVisibleToTourists).toList();
      list.sort(compareBySchedule);
      return list;
    } catch (e) {
      debugPrint('[LguEventService] loadPublishedProvinceWide: $e');
      final catalog = await _loadEventsCatalog();
      final list = catalog.where(isVisibleToTourists).toList();
      list.sort(compareBySchedule);
      return list;
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
      final list = _mergeById([
        ...snap.docs.map((d) => normalizeAnnouncementDoc(d.id, d.data())),
        ...await _loadEventsCatalog(),
      ]);
      list.sort(compareBySchedule);
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

    final wantsPhoto = preparedImageFields != null ||
        (imageBytes != null && imageBytes.isNotEmpty);
    final uploaded = <String>[];
    var wrote = false;
    late final Map<String, dynamic> imageFields;
    late final List<String> gallery;
    late final ({DateTime start, DateTime end, int days}) window;
    late final bool liveNow;
    try {
      if (wantsPhoto) {
        try {
          imageFields = await _coverFieldsFromUpload(
            eventId: docRef.id,
            municipalityId: municipalityId,
            imageBytes: imageBytes,
            imageContentType: imageContentType,
            preparedImageFields: preparedImageFields,
          );
        } catch (e) {
          throw _photoSaveError(e);
        }
        final cover = imageFields['imageUrl']?.toString().trim() ?? '';
        if (cover.isNotEmpty) uploaded.add(cover);
      } else {
        imageFields = const {};
      }

      final existing = await docRef.get();
      if (existing.exists) {
        throw StateError('This post was already published.');
      }

      gallery = await _uploadGallery(
        eventId: docRef.id,
        municipalityId: municipalityId,
        bytesList: galleryBytes,
      );
      uploaded.addAll(gallery);
      window = _windowForWrite(
        startsAt: startsAt,
        endsAt: endsAt,
        allDay: allDay,
        durationDays: durationDays,
      );
      liveNow = _windowIsOpen(window);
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
      if (imageFields['imageUrl'] is String &&
          (imageFields['imageUrl'] as String).trim().isNotEmpty)
        'imageUrls': <String>[
          (imageFields['imageUrl'] as String).trim(),
          ...gallery.where(
            (url) => url != (imageFields['imageUrl'] as String).trim(),
          ),
        ]
      else if (gallery.isNotEmpty)
        'imageUrls': gallery,
    };

      await docRef.set(data);
      wrote = true;
      if (wantsPhoto) {
        try {
          await _verifyCoverSaved(
            ref: docRef,
            eventId: docRef.id,
            catalog: false,
            imageFields: imageFields,
          );
        } catch (e) {
          debugPrint('[LguEventService] saved event is missing its photo: $e');
          await docRef.delete();
          wrote = false;
          throw StateError('Photo upload failed. Please retry.');
        }
      }
    } catch (e) {
      if (!wrote) {
        await _deleteOwnedEventPhotos(docRef.id, uploaded);
      }
      rethrow;
    }

    final saved = <String, dynamic>{
      'allDay': allDay,
      'startsAt': Timestamp.fromDate(window.start),
      'endsAt': Timestamp.fromDate(window.end),
      'published': liveNow,
    };
    if (schedulePhase(saved) != 'Expired') {
      final savedEvent = <String, dynamic>{
        'title': title.trim(),
        ...saved,
      };
      unawaited(
        AnnouncementPushService.broadcastToInstalledApps(
          title: touristNotificationTitle(savedEvent),
          content: touristNotificationBody(
            title: title.trim(),
            place: munName,
            description: content,
            schedule: savedEvent,
          ),
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
    /// `announcements` (LGU posts) or `events` (Trip Planner catalog).
    String sourceCollection = collection,
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
    final target = sourceCollection == eventsCollection
        ? eventsCollection
        : collection;
    final ref = _firestore.collection(target).doc(eventId);
    final snap = await ref.get();
    if (!snap.exists) {
      throw StateError('This post no longer exists.');
    }
    final current = snap.data() ?? {};
    final normalized = target == eventsCollection
        ? normalizeCatalogEvent(eventId, current)
        : normalizeAnnouncementDoc(eventId, current);
    if (!lguMayManage(normalized, municipalityId) &&
        !lguMayManage(current, municipalityId)) {
      throw StateError(
        isGovernorOwned(normalized) || isGovernorOwned(current)
            ? "Only the Governor's Office can edit this post."
            : 'You can only edit posts from your municipality.',
      );
    }
    final wasPublished = current['published'] == true;
    final updates = <String, dynamic>{
      'title': title.trim(),
      'content': content.trim(),
      'type': normalizeType(type),
      'updatedAt': FieldValue.serverTimestamp(),
      'status': 'approved',
    };
    if (target == eventsCollection) {
      updates['name'] = title.trim();
      updates['description'] = content.trim();
      updates['municipalityId'] = municipalityId;
    }

    final replacingPhoto = !removeImage &&
        (preparedImageFields != null ||
            (imageBytes != null && imageBytes.isNotEmpty));
    final previousUrls = imageUrlsOf(current);
    final uploaded = <String>[];
    var wrote = false;
    Map<String, dynamic> savedCover = const {};
    try {
    if (removeImage) {
      updates.addAll(coverImageUpdates(current: current, imageFields: const {}, remove: true));
    } else if (replacingPhoto) {
      try {
        savedCover = await _coverFieldsFromUpload(
          eventId: eventId,
          municipalityId: municipalityId,
          imageBytes: imageBytes,
          imageContentType: imageContentType,
          preparedImageFields: preparedImageFields,
        );
      } catch (e) {
        throw _photoSaveError(e);
      }
      final cover = savedCover['imageUrl']?.toString().trim() ?? '';
      if (cover.isNotEmpty) uploaded.add(cover);
      updates.addAll(coverImageUpdates(current: current, imageFields: savedCover));
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
      uploaded.addAll(gallery);
      if (gallery.isNotEmpty) {
        final coverUrl = updates['imageUrl'];
        final cover = coverUrl is String ? coverUrl : '';
        updates['imageUrls'] = [
          if (cover.isNotEmpty) cover,
          ...gallery.where((url) => url != cover),
        ];
        if (cover.isEmpty) {
          updates['imageUrl'] = gallery.first;
        }
      }
    }

    await ref.update(updates);
    wrote = true;
    if (replacingPhoto) {
      await _verifyCoverSaved(
        ref: ref,
        eventId: eventId,
        catalog: target == eventsCollection,
        imageFields: savedCover,
      );
    }
    if (removeImage || replacingPhoto || galleryBytes.isNotEmpty) {
      final kept = <String>{};
      final nextCover = updates['imageUrl'];
      if (nextCover is String && nextCover.trim().isNotEmpty) {
        kept.add(nextCover.trim());
      }
      final nextGallery = updates['imageUrls'];
      if (nextGallery is List) {
        for (final item in nextGallery) {
          final url = item?.toString().trim() ?? '';
          if (url.isNotEmpty) kept.add(url);
        }
      }
      await _deleteOwnedEventPhotos(
        eventId,
        previousUrls.where((url) => !kept.contains(url)),
      );
    }
    if (target == collection && liveNow && !wasPublished) {
      final place = current['municipalityName']?.toString().trim() ?? '';
      final savedEvent = <String, dynamic>{
        'title': title.trim(),
        'allDay': dayLong,
        'startsAt': updates['startsAt'],
        'endsAt': updates['endsAt'],
      };
      unawaited(
        AnnouncementPushService.broadcastToInstalledApps(
          title: touristNotificationTitle(savedEvent),
          content: touristNotificationBody(
            title: title.trim(),
            place: place,
            description: content,
            schedule: savedEvent,
          ),
          type: normalizeType(type),
          announcementId: eventId,
        ),
      );
    }
    } catch (e) {
      if (!wrote) {
        await _deleteOwnedEventPhotos(eventId, uploaded);
      }
      rethrow;
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
        requiredIfBytesPresent: true,
      );
      final url = fields['imageUrl']?.toString().trim() ?? '';
      if (url.isNotEmpty) urls.add(url);
    }
    return urls;
  }

  Future<void> deleteEvent(
    String eventId, {
    String? municipalityId,
    String sourceCollection = collection,
  }) async {
    final target = sourceCollection == eventsCollection
        ? eventsCollection
        : collection;
    final ref = _firestore.collection(target).doc(eventId);
    final snap = await ref.get();
    if (!snap.exists) return;
    final data = snap.data() ?? {};
    if (municipalityId != null && municipalityId.trim().isNotEmpty) {
      final normalized = target == eventsCollection
          ? normalizeCatalogEvent(eventId, data)
          : normalizeAnnouncementDoc(eventId, data);
      if (!lguMayManage(normalized, municipalityId) &&
          !lguMayManage(data, municipalityId)) {
        throw StateError(
          isGovernorOwned(normalized) || isGovernorOwned(data)
              ? "Only the Governor's Office can delete this post."
              : 'You can only delete posts from your municipality.',
        );
      }
    }
    final photos = imageUrlsOf(
      target == eventsCollection ? normalizeCatalogEvent(eventId, data) : data,
    );
    await ref.delete();
    await _deleteOwnedEventPhotos(eventId, photos);
  }

  /// Live updates for the LGU calendar and post lists.
  /// Includes LGU posts (`announcements`) and the Trip Planner `events` catalog.
  Stream<List<Map<String, dynamic>>> watchAnnouncements() {
    if (Firebase.apps.isEmpty) return const Stream.empty();
    return Stream.multi((controller) {
      List<Map<String, dynamic>>? posts;
      List<Map<String, dynamic>>? catalog;
      void emit() {
        if (posts == null && catalog == null) return;
        controller.add(_mergeById([
          ...?posts,
          ...?catalog,
        ]));
      }

      final postsSub = _firestore.collection(collection).limit(200).snapshots().listen(
        (snap) {
          posts = snap.docs
              .map((d) => normalizeAnnouncementDoc(d.id, d.data()))
              .toList();
          emit();
        },
        onError: (Object e) {
          debugPrint('[LguEventService] watch announcements: $e');
          posts ??= const [];
          emit();
        },
      );
      final catalogSub =
          _firestore.collection(eventsCollection).limit(200).snapshots().listen(
        (snap) {
          catalog = snap.docs
              .map((d) => normalizeCatalogEvent(d.id, d.data()))
              .where((e) => (e['title']?.toString().trim() ?? '').isNotEmpty)
              .toList();
          emit();
        },
        onError: (Object e) {
          debugPrint('[LguEventService] watch events: $e');
          catalog ??= const [];
          emit();
        },
      );
      controller.onCancel = () {
        postsSub.cancel();
        catalogSub.cancel();
      };
    });
  }

  Future<List<Map<String, dynamic>>> _loadEventsCatalog() async {
    if (Firebase.apps.isEmpty) return [];
    try {
      final snap = await _firestore.collection(eventsCollection).limit(200).get();
      return snap.docs
          .map((d) => normalizeCatalogEvent(d.id, d.data()))
          .where((e) => (e['title']?.toString().trim() ?? '').isNotEmpty)
          .toList();
    } catch (e) {
      debugPrint('[LguEventService] events catalog: $e');
      return [];
    }
  }

  /// Maps an `announcements` document (LGU or Governor catalog) onto the feed shape.
  static Map<String, dynamic> normalizeAnnouncementDoc(
    String id,
    Map<String, dynamic> data,
  ) {
    final content = (data['content'] ??
            data['body'] ??
            data['description'] ??
            data['message'] ??
            '')
        .toString();
    final municipality =
        (data['municipalityName'] ?? data['municipality'] ?? '').toString().trim();
    final storedId = data['municipalityId']?.toString().trim() ?? '';
    final provinceWide = isProvinceWideTarget(
      audienceScope:
          (data['audienceScope'] ?? data['targetScope'] ?? '').toString(),
      municipality: municipality,
      municipalityId: storedId,
    );
    final municipalityId = storedId.isNotEmpty
        ? storedId
        : (provinceWide ? 'province' : municipalityIdForLabel(municipality));
    final type = data['type'] ?? data['eventType'] ?? typeEvent;
    return {
      ...data,
      'id': id,
      'title': data['title'] ?? '',
      'content': content,
      'type': type,
      'municipalityName': municipality.isEmpty && provinceWide
          ? kProvinceWideDisplay
          : municipality,
      'municipalityId': municipalityId,
      if (provinceWide) 'audienceScope': data['audienceScope'] ?? kProvinceWideScope,
    };
  }

  /// Maps a Trip Planner `events` document onto the LGU calendar shape.
  static Map<String, dynamic> normalizeCatalogEvent(
    String id,
    Map<String, dynamic> data,
  ) {
    final municipality =
        (data['municipalityName'] ?? data['municipality'] ?? '').toString().trim();
    final storedId = data['municipalityId']?.toString().trim() ?? '';
    final municipalityId = storedId.isNotEmpty
        ? storedId
        : (isProvinceWideTarget(
            audienceScope: (data['audienceScope'] ?? data['targetScope'] ?? '').toString(),
            municipality: municipality,
          )
            ? 'province'
            : municipalityIdForLabel(municipality));
    final start = data['startsAt'] ??
        data['startAt'] ??
        data['start_at'] ??
        data['date'] ??
        data['eventDate'] ??
        data['event_date'];
    final explicitUrl = data['imageUrl']?.toString().trim() ??
        data['image_url']?.toString().trim() ??
        '';
    final hasEmbedded = _embeddedImage(data) != null;
    final legacyUrl = [
      data['imagePath'],
      data['image'],
      data['photoUrl'],
      data['photo'],
    ].map((value) => value?.toString().trim() ?? '').firstWhere(
          (value) => value.isNotEmpty,
          orElse: () => '',
        );
    final image = explicitUrl.isNotEmpty
        ? explicitUrl
        : (hasEmbedded ? '' : legacyUrl);
    final venue = data['venue']?.toString().trim() ?? '';
    final location = data['location']?.toString().trim() ?? '';
    return {
      ...data,
      'id': id,
      'title': data['title'] ?? data['name'] ?? data['eventTitle'] ?? '',
      'content': data['content'] ?? data['description'] ?? data['body'] ?? '',
      'type': data['type'] ?? data['eventType'] ?? data['event_type'] ?? typeEvent,
      'municipalityName': municipality,
      'municipalityId': municipalityId,
      'startsAt': start,
      'location': location.isNotEmpty
          ? location
          : (venue.isNotEmpty ? venue : municipality),
      if (image.isNotEmpty) 'imageUrl': image,
      'published': data['published'] ?? true,
      'status': data['status'] ?? 'approved',
      'allDay': data['allDay'] ?? true,
      'catalogSource': eventsCollection,
    };
  }

  static String municipalityIdForLabel(String raw) {
    final name = raw.trim().toLowerCase();
    if (name.isEmpty) return '';
    final list = getMisamisOccidentalMunicipalities();
    for (final m in list) {
      if (m.id.toLowerCase() == name || m.name.toLowerCase() == name) {
        return m.id;
      }
    }
    String? bestId;
    var bestLength = 0;
    for (final m in list) {
      final label = m.name.toLowerCase();
      if (name.contains(label) || label.contains(name)) {
        if (m.name.length > bestLength) {
          bestId = m.id;
          bestLength = m.name.length;
        }
      }
    }
    return bestId ?? '';
  }

  static List<Map<String, dynamic>> _mergeById(
    List<Map<String, dynamic>> items,
  ) {
    final seen = <String>{};
    final out = <Map<String, dynamic>>[];
    for (final item in items) {
      final id = item['id']?.toString() ?? '';
      final source = item['catalogSource']?.toString() ?? 'announcements';
      final key = id.isEmpty ? '$source:${item['title']}:${item['startsAt']}' : '$source:$id';
      if (!seen.add(key)) continue;
      out.add(item);
    }
    return out;
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

  Future<Map<String, dynamic>> _coverFieldsFromUpload({
    required String eventId,
    required String municipalityId,
    Uint8List? imageBytes,
    String? imageContentType,
    Future<Map<String, dynamic>>? preparedImageFields,
  }) async {
    Map<String, dynamic> fields = const {};
    if (preparedImageFields != null) {
      try {
        fields = await preparedImageFields;
      } catch (e) {
        debugPrint('[LguEventService] prepared photo failed, uploading again: $e');
      }
    }
    final url = fields['imageUrl']?.toString().trim() ?? '';
    final b64 = fields['imageBase64']?.toString().trim() ?? '';
    if (url.isEmpty && b64.isEmpty) {
      fields = await _resolveImageFields(
        eventId: eventId,
        municipalityId: municipalityId,
        bytes: imageBytes,
        contentType: imageContentType,
        requiredIfBytesPresent: true,
      );
    }
    final savedUrl = fields['imageUrl']?.toString().trim() ?? '';
    final savedB64 = fields['imageBase64']?.toString().trim() ?? '';
    if (savedUrl.isEmpty && savedB64.isEmpty) {
      throw StateError('Photo upload failed. Please retry.');
    }
    return fields;
  }

  Future<void> _verifyCoverSaved({
    required DocumentReference<Map<String, dynamic>> ref,
    required String eventId,
    required bool catalog,
    required Map<String, dynamic> imageFields,
  }) async {
    final snap = await ref.get();
    final raw = snap.data() ?? {};
    final saved = catalog ? normalizeCatalogEvent(eventId, raw) : raw;
    final newUrl = imageFields['imageUrl']?.toString().trim() ?? '';
    final newB64 = imageFields['imageBase64']?.toString().trim() ?? '';
    if (newUrl.isNotEmpty) {
      final stored = saved['imageUrl']?.toString().trim() ?? '';
      if (stored != newUrl) {
        throw StateError('The new photo was not saved on this event.');
      }
      return;
    }
    if (newB64.isEmpty || (raw['imageBase64']?.toString().trim().isEmpty ?? true)) {
      throw StateError('The new photo was not saved on this event.');
    }
    final shown = resolveDisplayImage(saved);
    if (shown == null || !shown.contains(newB64.substring(0, newB64.length.clamp(0, 24)))) {
      throw StateError('The old photo is still attached to this event.');
    }
  }

  /// Uploads the cover to Supabase Storage and returns `{imageUrl: publicUrl}`.
  /// Existing Firebase URLs stay on the event until this upload and the
  /// Firestore update both succeed.
  Future<Map<String, dynamic>> _resolveImageFields({
    required String eventId,
    required String municipalityId,
    Uint8List? bytes,
    String? contentType,
    required bool requiredIfBytesPresent,
  }) async {
    if (bytes == null || bytes.isEmpty) return {};
    try {
      final url = await SupabaseStorageUpload.uploadEventPhoto(
        eventId: eventId,
        bytes: bytes,
        contentType: contentType,
      );
      debugPrint(
        '[LguEventService] event photo stored for $municipalityId: $url',
      );
      return {'imageUrl': url};
    } catch (e, stack) {
      debugPrint('[LguEventService] event photo upload failed: $e\n$stack');
      if (requiredIfBytesPresent) rethrow;
      return {};
    }
  }

  /// User-facing save error. Storage status codes stay in the debug log.
  StateError _photoSaveError(Object error) {
    if (error is StateError) {
      final message = error.message.trim();
      if (message.isNotEmpty && !message.startsWith('Photo upload failed')) {
        return error;
      }
    }
    return StateError('Photo upload failed. Please retry.');
  }

  /// Removes Supabase files this event owns. Firebase Storage URLs are kept.
  Future<void> _deleteOwnedEventPhotos(
    String eventId,
    Iterable<String> urls,
  ) async {
    final seen = <String>{};
    for (final url in urls) {
      final trimmed = url.trim();
      if (trimmed.isEmpty || !seen.add(trimmed)) continue;
      try {
        await SupabaseStorageUpload.deleteEventPhotoIfOwned(trimmed, eventId);
      } catch (e) {
        debugPrint('[LguEventService] could not remove event photo: $e');
      }
    }
  }

  /// Drops a pre-upload when the dialog is cancelled or the photo is replaced.
  Future<void> discardPreparedUpload({
    required String eventId,
    Future<Map<String, dynamic>>? prepared,
  }) async {
    if (prepared == null) return;
    try {
      final fields = await prepared;
      final url = fields['imageUrl']?.toString().trim() ?? '';
      if (url.isEmpty) return;
      await SupabaseStorageUpload.deleteEventPhotoIfOwned(url, eventId);
    } catch (e) {
      debugPrint('[LguEventService] unused event photo left in place: $e');
    }
  }

  /// Upcoming, then ongoing, then expired. Times are Asia/Manila wall clocks.
  /// Upcoming is nearest first, ongoing ends soonest first, expired is newest first.
  static int compareBySchedule(
    Map<String, dynamic> a,
    Map<String, dynamic> b, [
    DateTime? now,
  ]) {
    final clock = now ?? manilaNow();
    final rankA = _scheduleRank(a, clock);
    final rankB = _scheduleRank(b, clock);
    if (rankA != rankB) return rankA.compareTo(rankB);
    if (rankA == 0) {
      final byStart = _compareClock(_scheduleStart(a), _scheduleStart(b));
      if (byStart != 0) return byStart;
    } else {
      final byEnd = rankA == 2
          ? _compareClock(_scheduleEnd(b), _scheduleEnd(a))
          : _compareClock(_scheduleEnd(a), _scheduleEnd(b));
      if (byEnd != 0) return byEnd;
    }
    return (a['title']?.toString() ?? '').compareTo(b['title']?.toString() ?? '');
  }

  /// Push body: date, place, and a short plain-text description.
  static String notificationSummary({
    required String when,
    required String place,
    required String description,
  }) {
    final plain = description
        .replaceAllMapped(RegExp(r'\*\*(.+?)\*\*'), (match) => match.group(1) ?? '')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    final short = plain.length > 140 ? '${plain.substring(0, 137)}...' : plain;
    return [when.trim(), place.trim(), short]
        .where((part) => part.isNotEmpty)
        .join(' · ');
  }

  static const List<String> _monthNames = [
    'January',
    'February',
    'March',
    'April',
    'May',
    'June',
    'July',
    'August',
    'September',
    'October',
    'November',
    'December',
  ];

  /// Tray title. Does not rewrite the stored event title.
  static String touristNotificationTitle(
    Map<String, dynamic> data, [
    DateTime? now,
  ]) {
    final raw = data['title']?.toString().trim() ?? '';
    final prefix =
        schedulePhase(data, now) == 'Ongoing' ? 'Ongoing Event' : 'Upcoming Event';
    return '$prefix: $raw';
  }

  /// Tray body. Uses the saved description when it exists; otherwise a short
  /// sentence with the place and Manila date. Does not rewrite the event.
  static String touristNotificationBody({
    required String title,
    required String place,
    required String description,
    required Map<String, dynamic> schedule,
  }) {
    final when = _longManilaDate(eventStart(schedule));
    final plain = description
        .replaceAllMapped(RegExp(r'\*\*(.+?)\*\*'), (match) => match.group(1) ?? '')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    final where = place.trim();
    if (plain.isEmpty) {
      if (where.isNotEmpty && when.isNotEmpty) {
        return 'Join the ${title.trim()} in $where on $when!';
      }
      return [where, when].where((part) => part.isNotEmpty).join(' · ');
    }
    var body = plain.length > 140 ? '${plain.substring(0, 137)}...' : plain;
    final extras = <String>[];
    if (where.isNotEmpty && !body.toLowerCase().contains(where.toLowerCase())) {
      extras.add(where);
    }
    if (when.isNotEmpty && !body.contains(when)) extras.add(when);
    if (extras.isNotEmpty) body = '$body — ${extras.join(' · ')}';
    return body;
  }

  static String _longManilaDate(DateTime? wall) {
    if (wall == null) return '';
    return '${_monthNames[wall.month - 1]} ${wall.day}, ${wall.year}';
  }

  static int _scheduleRank(Map<String, dynamic> data, DateTime clock) {
    final start = _scheduleStart(data);
    if (start == null) return 1;
    final end = _scheduleEnd(data);
    if (end != null && !clock.isBefore(end)) return 2;
    if (!clock.isBefore(start)) return 1;
    return 0;
  }

  static DateTime? _scheduleStart(Map<String, dynamic> data) {
    final start = eventStart(data);
    if (start == null) return null;
    if (_usesManilaClock(data)) return start;
    return DateTime(start.year, start.month, start.day);
  }

  static DateTime? _scheduleEnd(Map<String, dynamic> data) {
    if (_usesManilaClock(data)) return eventEnd(data);
    final start = _scheduleStart(data);
    if (start == null) return null;
    return start.add(Duration(days: eventDurationDays(data)));
  }

  static int _compareClock(DateTime? a, DateTime? b) {
    if (a == null && b == null) return 0;
    if (a == null) return 1;
    if (b == null) return -1;
    return a.compareTo(b);
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

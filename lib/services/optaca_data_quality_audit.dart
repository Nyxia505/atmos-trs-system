import 'package:atmos_trs_system/data/tourist_spot_image_catalog.dart';
import 'package:atmos_trs_system/models/tourist_spot_firestore.dart';
import 'package:atmos_trs_system/services/provincial_tourism_service.dart';
import 'package:atmos_trs_system/utils/municipality_helper.dart';
import 'package:atmos_trs_system/utils/spot_qr_helper.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

/// Severity for OPTACA Alerts & Quality rows.
enum OptacaIssueSeverity { critical, warning, info }

/// Summary buckets for the dashboard KPI cards.
enum OptacaIssueBucket { missingQr, missingImage, location, other }

/// One real data-quality finding (never fabricated).
class OptacaQualityIssue {
  const OptacaQualityIssue({
    required this.id,
    required this.system,
    required this.recordName,
    required this.recordId,
    required this.issueType,
    required this.issue,
    required this.severity,
    required this.bucket,
    this.municipalityId = '',
    this.municipalityName = '',
    this.status = 'Open',
  });

  final String id;
  final String system;
  final String recordName;
  final String recordId;
  final String issueType;
  final String issue;
  final OptacaIssueSeverity severity;
  final OptacaIssueBucket bucket;
  final String municipalityId;
  final String municipalityName;
  final String status;
}

class OptacaQualityAuditResult {
  const OptacaQualityAuditResult({
    required this.issues,
    required this.spotCount,
    required this.scannedAt,
    this.loadWarnings = const [],
  });

  final List<OptacaQualityIssue> issues;
  final int spotCount;
  final DateTime scannedAt;
  final List<String> loadWarnings;

  int get total => issues.length;
  int countBucket(OptacaIssueBucket b) =>
      issues.where((i) => i.bucket == b).length;
}

/// Audits live ATMOS + Trip Planner Firestore records for OPTACA monitoring.
///
/// QR checks use the same payload rules as [parseSpotCheckInPayload] /
/// LGU [ensureSpotQrMetadata] (`qrValue` + `qr_payload`). No fake alerts.
class OptacaDataQualityAudit {
  OptacaDataQualityAudit._();

  /// Approximate Misamis Occidental bounding box (deg). Spots clearly outside
  /// are flagged; near-misses at the edge are not.
  static const double _minLat = 7.70;
  static const double _maxLat = 8.95;
  static const double _minLng = 123.25;
  static const double _maxLng = 124.05;

  static Future<OptacaQualityAuditResult> run({
    FirebaseFirestore? firestore,
    List<Map<String, dynamic>>? spotsCache,
    List<Map<String, dynamic>>? checkInsCache,
    List<Map<String, dynamic>>? announcementsCache,
    String timeFilter = 'This Month',
    Set<String> acknowledgedIds = const {},
  }) async {
    final db = firestore ?? FirebaseFirestore.instance;
    final warnings = <String>[];

    var spots = spotsCache;
    if (spots == null) {
      try {
        final snap = await db.collection('tourist_spots').get();
        spots = [
          for (final d in snap.docs) {'id': d.id, ...d.data()},
        ];
      } catch (e) {
        debugPrint('[OptacaQualityAudit] tourist_spots: $e');
        warnings.add('Could not load tourist_spots.');
        spots = const [];
      }
    }

    List<Map<String, dynamic>> featured = const [];
    try {
      final snap = await db.collection('featured_spots').get();
      featured = [
        for (final d in snap.docs) {'id': d.id, ...d.data()},
      ];
    } catch (e) {
      debugPrint('[OptacaQualityAudit] featured_spots: $e');
      warnings.add('Could not load featured_spots.');
    }

    var announcements = announcementsCache;
    if (announcements == null) {
      try {
        final snap = await db.collection('announcements').get();
        announcements = [
          for (final d in snap.docs) {'id': d.id, ...d.data()},
        ];
      } catch (e) {
        debugPrint('[OptacaQualityAudit] announcements: $e');
        announcements = const [];
      }
    }

    List<Map<String, dynamic>> events = const [];
    try {
      final snap = await db.collection('events').get();
      events = [
        for (final d in snap.docs) {'id': d.id, ...d.data()},
      ];
    } catch (e) {
      debugPrint('[OptacaQualityAudit] events: $e');
    }

    final checkIns = checkInsCache ?? const <Map<String, dynamic>>[];

    final issues = <OptacaQualityIssue>[];
    issues.addAll(_auditTouristSpots(spots));
    issues.addAll(_auditFeatured(featured, spots));
    issues.addAll(_auditEvents(announcements, systemLabel: 'ATMOS TRS'));
    issues.addAll(_auditEvents(events, systemLabel: 'Trip Planner'));

    if (checkIns.isNotEmpty || spots.isNotEmpty) {
      issues.addAll(
        _auditOps(
          spots: spots,
          checkIns: checkIns,
          announcements: announcements,
          timeFilter: timeFilter,
        ),
      );
    }

    final filtered = [
      for (final i in issues)
        if (!acknowledgedIds.contains(i.id)) i,
    ];
    filtered.sort((a, b) {
      final sev = b.severity.index.compareTo(a.severity.index);
      if (sev != 0) return sev;
      return a.municipalityName.compareTo(b.municipalityName);
    });

    return OptacaQualityAuditResult(
      issues: filtered,
      spotCount: spots.length,
      scannedAt: DateTime.now(),
      loadWarnings: warnings,
    );
  }

  // ─── Tourist spots (ATMOS TRS + Trip Planner shared collection) ───────

  static List<OptacaQualityIssue> _auditTouristSpots(
    List<Map<String, dynamic>> spots,
  ) {
    final out = <OptacaQualityIssue>[];
    final byId = <String, Map<String, dynamic>>{
      for (final s in spots)
        if ((s['id']?.toString() ?? '').isNotEmpty) s['id'].toString(): s,
    };

    final qrValueOwners = <String, List<String>>{};
    final payloadOwners = <String, List<String>>{};
    final nameKeys = <String, List<String>>{};

    for (final s in spots) {
      final id = s['id']?.toString() ?? '';
      if (id.isEmpty) continue;
      final name = (s['name']?.toString() ?? '').trim();
      final mid = ProvincialTourismService.municipalityIdOf(s);
      final mname = ProvincialTourismService.municipalityNameOf(mid);
      final display = name.isEmpty ? id : name;

      void add({
        required String suffix,
        required String issueType,
        required String issue,
        required OptacaIssueSeverity severity,
        required OptacaIssueBucket bucket,
        String system = 'ATMOS TRS',
      }) {
        out.add(
          OptacaQualityIssue(
            id: '${suffix}_$id',
            system: system,
            recordName: display,
            recordId: id,
            issueType: issueType,
            issue: issue,
            severity: severity,
            bucket: bucket,
            municipalityId: mid,
            municipalityName: mname,
          ),
        );
      }

      // Name / municipality / category
      if (name.isEmpty) {
        add(
          suffix: 'name',
          issueType: 'Missing name',
          issue: 'Tourist spot document has an empty name.',
          severity: OptacaIssueSeverity.critical,
          bucket: OptacaIssueBucket.other,
        );
      }
      if (mid.isEmpty || !isMisamisOccidentalMunicipalityId(mid)) {
        add(
          suffix: 'muni',
          issueType: 'Missing municipality',
          issue: mid.isEmpty
              ? 'No municipalityId / municipality assigned.'
              : 'Municipality "$mid" is not a Misamis Occidental LGU id.',
          severity: OptacaIssueSeverity.critical,
          bucket: OptacaIssueBucket.other,
        );
      }
      final category = (s['category']?.toString() ?? '').trim();
      if (category.isEmpty) {
        add(
          suffix: 'cat',
          issueType: 'Missing category',
          issue: 'Category is empty (LGU catalog expects a spot category).',
          severity: OptacaIssueSeverity.info,
          bucket: OptacaIssueBucket.other,
        );
      }

      final nameKey =
          '${normalizeMunicipalityId(mid)}|${name.toLowerCase()}';
      if (name.isNotEmpty) {
        nameKeys.putIfAbsent(nameKey, () => []).add(id);
      }

      // Coordinates
      final lat = _asDouble(s['latitude'] ?? s['lat']);
      final lng = _asDouble(s['longitude'] ?? s['lng'] ?? s['lon']);
      final hasCoords = lat != null &&
          lng != null &&
          (lat.abs() > 1e-7 || lng.abs() > 1e-7);
      if (!hasCoords) {
        add(
          suffix: 'coords',
          issueType: 'Missing coordinates',
          issue:
              'Latitude/longitude missing or zero — QR check-in proximity cannot run.',
          severity: OptacaIssueSeverity.critical,
          bucket: OptacaIssueBucket.location,
        );
      } else if (lat < _minLat ||
          lat > _maxLat ||
          lng < _minLng ||
          lng > _maxLng) {
        add(
          suffix: 'bounds',
          issueType: 'Coordinates outside province',
          issue:
              'Lat $lat, Lng $lng fall outside the Misamis Occidental map box.',
          severity: OptacaIssueSeverity.warning,
          bucket: OptacaIssueBucket.location,
        );
      }

      // Images — only when no Firestore field AND no catalog fallback for this spot.
      final image = TouristSpotFirestore.readImageUrl(s);
      final hasExplicitImage = image != null && image.trim().isNotEmpty;
      if (!hasExplicitImage) {
        final hasCatalogHit = TouristSpotImageCatalog.byDocId[id] != null ||
            (mid.isNotEmpty &&
                TouristSpotImageCatalog.byMunicipalityId[mid] != null) ||
            (name.isNotEmpty &&
                TouristSpotImageCatalog.byDocId[_slug(name)] != null);
        if (!hasCatalogHit) {
          add(
            suffix: 'img',
            issueType: 'Missing image',
            issue:
                'No image_url/image on the document and no catalog fallback for this spot.',
            severity: OptacaIssueSeverity.warning,
            bucket: OptacaIssueBucket.missingImage,
          );
        }
      }

      // QR registration (same fields LGU writes)
      final qrValue =
          (s['qrValue'] ?? s['qr_value'] ?? '').toString().trim();
      final payload = (s['qr_payload'] ?? s['qrPayload'] ?? '')
          .toString()
          .trim();

      if (qrValue.isNotEmpty) {
        qrValueOwners.putIfAbsent(qrValue, () => []).add(id);
      }
      if (payload.isNotEmpty) {
        payloadOwners.putIfAbsent(payload, () => []).add(id);
      }

      final usable = _hasUsableCheckInQr(payload: payload, qrValue: qrValue);
      if (!usable) {
        add(
          suffix: 'qr_missing',
          issueType: 'Missing QR code',
          issue: payload.isEmpty && qrValue.isEmpty
              ? 'No qrValue or qr_payload — spot is not enrolled for check-in.'
              : payload.isEmpty
                  ? 'qrValue is set but qr_payload is missing (check-in URL required).'
                  : 'qr_payload is present but cannot be parsed by the check-in scanner.',
          severity: OptacaIssueSeverity.critical,
          bucket: OptacaIssueBucket.missingQr,
        );
      } else if (payload.isNotEmpty) {
        if (isScreenPreviewQr(payload)) {
          add(
            suffix: 'qr_preview',
            issueType: 'Invalid QR payload',
            issue:
                'Stored payload is a screen-preview QR and cannot be used for tourist check-in.',
            severity: OptacaIssueSeverity.critical,
            bucket: OptacaIssueBucket.missingQr,
          );
        }
        final parsed = parseSpotCheckInPayload(payload);
        if (parsed == null) {
          add(
            suffix: 'qr_malformed',
            issueType: 'Malformed QR payload',
            issue:
                'qr_payload is not a valid ATMOS spot check-in URL or legacy ATMOS-TRS-SPOT payload.',
            severity: OptacaIssueSeverity.critical,
            bucket: OptacaIssueBucket.missingQr,
          );
        } else {
          if (parsed.spotId != id) {
            add(
              suffix: 'qr_mismatch',
              issueType: 'QR linked to wrong spot',
              issue:
                  'Payload spot_id "${parsed.spotId}" does not match document id "$id".',
              severity: OptacaIssueSeverity.critical,
              bucket: OptacaIssueBucket.missingQr,
            );
          }
          if (parsed.municipalityId != null &&
              parsed.municipalityId!.isNotEmpty &&
              mid.isNotEmpty &&
              normalizeMunicipalityId(parsed.municipalityId) !=
                  normalizeMunicipalityId(mid)) {
            add(
              suffix: 'qr_muni',
              issueType: 'QR municipality mismatch',
              issue:
                  'Payload municipality_id "${parsed.municipalityId}" ≠ spot municipality "$mid".',
              severity: OptacaIssueSeverity.warning,
              bucket: OptacaIssueBucket.missingQr,
            );
          }
          if (parsed.spotId.isNotEmpty &&
              parsed.spotId != id &&
              !byId.containsKey(parsed.spotId)) {
            add(
              suffix: 'qr_orphan',
              issueType: 'QR references missing spot',
              issue:
                  'Payload spot_id "${parsed.spotId}" is not in tourist_spots.',
              severity: OptacaIssueSeverity.critical,
              bucket: OptacaIssueBucket.missingQr,
            );
          }
        }
      }
    }

    for (final e in qrValueOwners.entries) {
      if (e.value.length < 2) continue;
      for (final id in e.value) {
        final s = byId[id];
        if (s == null) continue;
        out.add(
          OptacaQualityIssue(
            id: 'qr_dup_val_$id',
            system: 'ATMOS TRS',
            recordName: s['name']?.toString() ?? id,
            recordId: id,
            issueType: 'Duplicate QR identifier',
            issue:
                'qrValue "${e.key}" is shared by ${e.value.length} spots: ${e.value.join(', ')}.',
            severity: OptacaIssueSeverity.critical,
            bucket: OptacaIssueBucket.missingQr,
            municipalityId: ProvincialTourismService.municipalityIdOf(s),
            municipalityName: ProvincialTourismService.municipalityNameOf(
              ProvincialTourismService.municipalityIdOf(s),
            ),
          ),
        );
      }
    }

    for (final e in payloadOwners.entries) {
      if (e.value.length < 2) continue;
      for (final id in e.value) {
        final s = byId[id];
        if (s == null) continue;
        out.add(
          OptacaQualityIssue(
            id: 'qr_dup_pay_$id',
            system: 'ATMOS TRS',
            recordName: s['name']?.toString() ?? id,
            recordId: id,
            issueType: 'Duplicate QR payload',
            issue:
                'Identical qr_payload on ${e.value.length} spots: ${e.value.join(', ')}.',
            severity: OptacaIssueSeverity.critical,
            bucket: OptacaIssueBucket.missingQr,
            municipalityId: ProvincialTourismService.municipalityIdOf(s),
            municipalityName: ProvincialTourismService.municipalityNameOf(
              ProvincialTourismService.municipalityIdOf(s),
            ),
          ),
        );
      }
    }

    for (final e in nameKeys.entries) {
      if (e.value.length < 2) continue;
      for (final id in e.value) {
        final s = byId[id];
        if (s == null) continue;
        out.add(
          OptacaQualityIssue(
            id: 'dup_name_$id',
            system: 'ATMOS TRS',
            recordName: s['name']?.toString() ?? id,
            recordId: id,
            issueType: 'Duplicate destination name',
            issue:
                'Same name appears ${e.value.length} times in this municipality.',
            severity: OptacaIssueSeverity.warning,
            bucket: OptacaIssueBucket.other,
            municipalityId: ProvincialTourismService.municipalityIdOf(s),
            municipalityName: ProvincialTourismService.municipalityNameOf(
              ProvincialTourismService.municipalityIdOf(s),
            ),
          ),
        );
      }
    }

    return out;
  }

  /// Usable for tourist check-in: parseable [qr_payload], or legacy value that
  /// already encodes a spot id matching enroll rules.
  static bool _hasUsableCheckInQr({
    required String payload,
    required String qrValue,
  }) {
    if (payload.isNotEmpty) {
      if (isScreenPreviewQr(payload)) return false;
      return parseSpotCheckInPayload(payload) != null;
    }
    // qrValue alone is an identifier, not a scannable check-in URL.
    return false;
  }

  // ─── Featured destinations (Trip Planner) ─────────────────────────────

  static List<OptacaQualityIssue> _auditFeatured(
    List<Map<String, dynamic>> featured,
    List<Map<String, dynamic>> spots,
  ) {
    final spotIds = {
      for (final s in spots)
        if ((s['id']?.toString() ?? '').isNotEmpty) s['id'].toString(),
    };
    final out = <OptacaQualityIssue>[];
    for (final f in featured) {
      final id = f['id']?.toString() ?? '';
      final name = (f['name']?.toString() ?? '').trim();
      final spotId = (f['spotId'] ?? f['spot_id'] ?? f['touristSpotId'] ?? '')
          .toString()
          .trim();
      final display = name.isEmpty ? (id.isEmpty ? 'Featured spot' : id) : name;
      final mid = ProvincialTourismService.municipalityIdOf(f);
      final mname = ProvincialTourismService.municipalityNameOf(mid);

      if (name.isEmpty) {
        out.add(
          OptacaQualityIssue(
            id: 'feat_name_$id',
            system: 'Trip Planner',
            recordName: display,
            recordId: id,
            issueType: 'Missing destination name',
            issue: 'Featured destination has no name.',
            severity: OptacaIssueSeverity.warning,
            bucket: OptacaIssueBucket.other,
            municipalityId: mid,
            municipalityName: mname,
          ),
        );
      }
      final image = TouristSpotFirestore.readImageUrl(f) ??
          f['imagePath']?.toString() ??
          f['image']?.toString();
      if (image == null || image.trim().isEmpty) {
        out.add(
          OptacaQualityIssue(
            id: 'feat_img_$id',
            system: 'Trip Planner',
            recordName: display,
            recordId: id,
            issueType: 'Missing image',
            issue: 'Featured destination has no image field.',
            severity: OptacaIssueSeverity.warning,
            bucket: OptacaIssueBucket.missingImage,
            municipalityId: mid,
            municipalityName: mname,
          ),
        );
      }
      if (spotId.isNotEmpty && !spotIds.contains(spotId)) {
        out.add(
          OptacaQualityIssue(
            id: 'feat_ref_$id',
            system: 'Trip Planner',
            recordName: display,
            recordId: id,
            issueType: 'Broken destination reference',
            issue:
                'Featured spotId "$spotId" is not found in tourist_spots.',
            severity: OptacaIssueSeverity.critical,
            bucket: OptacaIssueBucket.other,
            municipalityId: mid,
            municipalityName: mname,
          ),
        );
      }
    }
    return out;
  }

  // ─── Events / announcements ───────────────────────────────────────────

  static List<OptacaQualityIssue> _auditEvents(
    List<Map<String, dynamic>> rows, {
    required String systemLabel,
  }) {
    final out = <OptacaQualityIssue>[];
    for (final e in rows) {
      final id = e['id']?.toString() ?? '';
      final title =
          (e['title'] ?? e['name'] ?? e['eventTitle'] ?? '').toString().trim();
      final mid = ProvincialTourismService.municipalityIdOf(e);
      final mname = ProvincialTourismService.municipalityNameOf(mid);
      final display = title.isEmpty ? (id.isEmpty ? 'Event' : id) : title;

      if (title.isEmpty) {
        out.add(
          OptacaQualityIssue(
            id: 'evt_title_${systemLabel}_$id',
            system: systemLabel,
            recordName: display,
            recordId: id,
            issueType: 'Missing event title',
            issue: 'Event/announcement has no title.',
            severity: OptacaIssueSeverity.warning,
            bucket: OptacaIssueBucket.other,
            municipalityId: mid,
            municipalityName: mname,
          ),
        );
      }

      final start = _asDate(e['startDate'] ?? e['start'] ?? e['eventDate']);
      final end = _asDate(e['endDate'] ?? e['end']);
      if (start != null && end != null && end.isBefore(start)) {
        out.add(
          OptacaQualityIssue(
            id: 'evt_dates_${systemLabel}_$id',
            system: systemLabel,
            recordName: display,
            recordId: id,
            issueType: 'Invalid event dates',
            issue: 'End date is before start date.',
            severity: OptacaIssueSeverity.warning,
            bucket: OptacaIssueBucket.other,
            municipalityId: mid,
            municipalityName: mname,
          ),
        );
      }
    }
    return out;
  }

  // ─── Operational (period-based) — real check-in aggregates ────────────

  static List<OptacaQualityIssue> _auditOps({
    required List<Map<String, dynamic>> spots,
    required List<Map<String, dynamic>> checkIns,
    required List<Map<String, dynamic>> announcements,
    required String timeFilter,
  }) {
    final out = <OptacaQualityIssue>[];
    final perf = ProvincialTourismService.municipalityPerformance(
      checkIns: checkIns,
      spots: spots,
      timeFilter: timeFilter,
    );
    for (final m in perf) {
      if (m.hasZeroActivity && m.spotCount > 0) {
        out.add(
          OptacaQualityIssue(
            id: 'zero_${m.id}',
            system: 'ATMOS TRS',
            recordName: m.name,
            recordId: m.id,
            issueType: 'No check-ins',
            issue:
                'LGU has ${m.spotCount} spots but zero arrivals in $timeFilter.',
            severity: OptacaIssueSeverity.warning,
            bucket: OptacaIssueBucket.other,
            municipalityId: m.id,
            municipalityName: m.name,
          ),
        );
      } else if (m.growthPercent <= -40) {
        out.add(
          OptacaQualityIssue(
            id: 'drop_${m.id}',
            system: 'ATMOS TRS',
            recordName: m.name,
            recordId: m.id,
            issueType: 'Arrival drop',
            issue:
                'Arrivals down ${m.growthPercent.abs().toStringAsFixed(0)}% vs prior period.',
            severity: OptacaIssueSeverity.critical,
            bucket: OptacaIssueBucket.other,
            municipalityId: m.id,
            municipalityName: m.name,
          ),
        );
      }
    }

    final now = DateTime.now();
    for (final a in announcements) {
      final status = (a['status']?.toString() ?? '').toLowerCase();
      if (status != 'pending' && status != 'submitted' && status != 'review') {
        continue;
      }
      final created = _asDate(a['createdAt']) ?? _asDate(a['submittedAt']);
      if (created == null) continue;
      final days = now.difference(created).inDays;
      if (days < 3) continue;
      final id = a['id']?.toString() ?? '';
      out.add(
        OptacaQualityIssue(
          id: 'event_pending_$id',
          system: 'ATMOS TRS',
          recordName: a['title']?.toString() ?? 'LGU event',
          recordId: id,
          issueType: 'Event pending review',
          issue: 'Pending for $days day${days == 1 ? '' : 's'}.',
          severity: days >= 7
              ? OptacaIssueSeverity.critical
              : OptacaIssueSeverity.warning,
          bucket: OptacaIssueBucket.other,
          municipalityId: ProvincialTourismService.municipalityIdOf(a),
          municipalityName: ProvincialTourismService.municipalityNameOf(
            ProvincialTourismService.municipalityIdOf(a),
          ),
        ),
      );
    }
    return out;
  }

  static double? _asDouble(dynamic v) {
    if (v is num) return v.toDouble();
    if (v is String) return double.tryParse(v.trim());
    return null;
  }

  static DateTime? _asDate(dynamic value) {
    if (value is Timestamp) return value.toDate();
    if (value is DateTime) return value;
    if (value is String) return DateTime.tryParse(value);
    return null;
  }

  static String _slug(String name) {
    return name
        .toLowerCase()
        .trim()
        .replaceAll(RegExp(r'[^a-z0-9\s]'), '')
        .replaceAll(RegExp(r'\s+'), '_');
  }
}

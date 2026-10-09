import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';

/// What a sign-off is attached to. New forms add a constant here and reuse
/// the same `signoffs` collection, dialog and history panel.
abstract final class SignOffSubjects {
  /// DAE-1B monthly register — subjectId = `ae_monthly_reports` doc id.
  static const aeRegister = 'ae_register';

  /// Establishment DOT reporting profile — subjectId = establishment uid.
  static const aeProfile = 'ae_profile';

  /// CUS MICE monthly events — subjectId = `mice_monthly_reports` doc id.
  static const miceRegister = 'mice_register';
}

/// A signed action type. [requiresReason] forces a written reason.
class SignOffAction {
  const SignOffAction(this.code, this.label, {this.requiresReason = false});

  final String code;
  final String label;
  final bool requiresReason;
}

/// DAE-1B register + profile actions that need a signature.
abstract final class AeSignOffActions {
  static const addStay = SignOffAction('add_stay', 'Added stay');
  static const addNight = SignOffAction('add_night', 'Added single night');
  static const editRow = SignOffAction('edit_row', 'Edited record');
  static const deleteRow = SignOffAction('delete_row', 'Deleted record', requiresReason: true);
  static const stayAnotherNight = SignOffAction('stay_another_night', 'Guest stays another night');
  static const markNoGuests = SignOffAction('mark_no_guests', 'Marked day as no guests');
  static const unmarkNoGuests = SignOffAction('unmark_no_guests', 'Cleared "no guests" day');
  static const submitMonth = SignOffAction('submit_month', 'Submitted month to LGU');
  static const reopenMonth = SignOffAction('reopen_month', 'Moved month back to draft', requiresReason: true);
  static const reportingProfile = SignOffAction('reporting_profile', 'Updated DOT reporting profile');

  static const all = [
    addStay,
    addNight,
    editRow,
    deleteRow,
    stayAnotherNight,
    markNoGuests,
    unmarkNoGuests,
    submitMonth,
    reopenMonth,
    reportingProfile,
  ];

  /// Label for any registered action code (DAE + MICE).
  static String labelFor(String code) {
    for (final a in [...all, ...MiceSignOffActions.all]) {
      if (a.code == code) return a.label;
    }
    return code.replaceAll('_', ' ');
  }
}

/// CUS MICE event log actions that need a signature.
abstract final class MiceSignOffActions {
  static const addEvent = SignOffAction('mice_add_event', 'Added event');
  static const editEvent = SignOffAction('mice_edit_event', 'Edited event');
  static const duplicateEvent = SignOffAction('mice_duplicate_event', 'Duplicated event');
  static const deleteEvent = SignOffAction('mice_delete_event', 'Deleted event', requiresReason: true);
  static const submitMonth = SignOffAction('mice_submit_month', 'Submitted MICE month to LGU');
  static const reopenMonth =
      SignOffAction('mice_reopen_month', 'Moved MICE month back to draft', requiresReason: true);

  static const all = [addEvent, editEvent, duplicateEvent, deleteEvent, submitMonth, reopenMonth];
}

/// A remembered person (name + position) for one establishment / owner.
class SignOffSigner {
  const SignOffSigner({required this.id, required this.name, required this.position});

  final String id;
  final String name;
  final String position;

  /// Stable doc id so the same name + position is stored once.
  static String keyFor(String name, String position) {
    final k = '${name.trim()}|${position.trim()}'
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9|]+'), '-')
        .replaceAll('|', '__');
    return k.isEmpty ? 'signer' : (k.length > 120 ? k.substring(0, 120) : k);
  }

  factory SignOffSigner.fromDoc(DocumentSnapshot<Map<String, dynamic>> d) {
    final m = d.data() ?? const {};
    return SignOffSigner(
      id: d.id,
      name: (m['name'] ?? '').toString(),
      position: (m['position'] ?? '').toString(),
    );
  }
}

/// What the signer entered in the dialog (fresh signature every time).
class SignOffCapture {
  const SignOffCapture({
    required this.name,
    required this.position,
    required this.signaturePng,
    this.reason = '',
  });

  final String name;
  final String position;
  final Uint8List signaturePng;
  final String reason;
}

/// Everything needed to write a sign-off alongside a data change.
class SignOffRequest {
  const SignOffRequest({
    required this.action,
    required this.capture,
    required this.summary,
    this.details = const [],
  });

  final SignOffAction action;
  final SignOffCapture capture;
  final String summary;
  final List<String> details;
}

/// Compact copy of the latest sign-off stamped on the signed document.
class SignOffStamp {
  const SignOffStamp({
    required this.id,
    required this.action,
    required this.name,
    required this.position,
    this.at,
    this.contentHash = '',
  });

  final String id;
  final String action;
  final String name;
  final String position;
  final DateTime? at;

  /// Hash of the signed content; differs from the live hash when data
  /// changed outside a signed save.
  final String contentHash;

  String get actionLabel => AeSignOffActions.labelFor(action);

  Map<String, dynamic> toWriteMap() => {
        'id': id,
        'action': action,
        'name': name,
        'position': position,
        'at': FieldValue.serverTimestamp(),
        'contentHash': contentHash,
      };

  static SignOffStamp? fromMap(dynamic raw) {
    if (raw is! Map) return null;
    final id = (raw['id'] ?? '').toString();
    if (id.isEmpty) return null;
    final at = raw['at'];
    return SignOffStamp(
      id: id,
      action: (raw['action'] ?? '').toString(),
      name: (raw['name'] ?? '').toString(),
      position: (raw['position'] ?? '').toString(),
      at: at is Timestamp ? at.toDate() : null,
      contentHash: (raw['contentHash'] ?? '').toString(),
    );
  }
}

/// One before/after line of a signed change.
class SignOffChange {
  const SignOffChange({required this.op, required this.label, this.before, this.after});

  /// `add` · `edit` · `delete` · `set`.
  final String op;
  final String label;
  final Map<String, dynamic>? before;
  final Map<String, dynamic>? after;

  Map<String, dynamic> toMap() => {
        'op': op,
        'label': label,
        if (before != null) 'before': before,
        if (after != null) 'after': after,
      };

  factory SignOffChange.fromMap(dynamic raw) {
    final m = raw is Map ? raw : const {};
    Map<String, dynamic>? map(dynamic v) => v is Map ? Map<String, dynamic>.from(v) : null;
    return SignOffChange(
      op: (m['op'] ?? '').toString(),
      label: (m['label'] ?? '').toString(),
      before: map(m['before']),
      after: map(m['after']),
    );
  }
}

/// `signoffs/{id}` — append-only evidence record.
class SignOffRecord {
  const SignOffRecord({
    required this.id,
    required this.subjectType,
    required this.subjectId,
    required this.ownerId,
    required this.action,
    required this.signerName,
    required this.signerPosition,
    this.ownerName = '',
    this.municipalityId = '',
    this.periodKey = '',
    this.summary = '',
    this.details = const [],
    this.reason = '',
    this.signaturePng,
    this.signatureSha256 = '',
    this.contentHash = '',
    this.snapshot = const {},
    this.changes = const [],
    this.changesTruncated = 0,
    this.accountEmail = '',
    this.platform = '',
    this.createdAt,
  });

  final String id;
  final String subjectType;
  final String subjectId;
  final String ownerId;
  final String ownerName;
  final String municipalityId;
  final String periodKey;
  final String action;
  final String summary;
  final List<String> details;
  final String reason;
  final String signerName;
  final String signerPosition;
  final Uint8List? signaturePng;
  final String signatureSha256;
  final String contentHash;
  final Map<String, dynamic> snapshot;
  final List<SignOffChange> changes;
  final int changesTruncated;
  final String accountEmail;
  final String platform;
  final DateTime? createdAt;

  String get actionLabel => AeSignOffActions.labelFor(action);

  factory SignOffRecord.fromDoc(DocumentSnapshot<Map<String, dynamic>> d) {
    final m = d.data() ?? const {};
    final sig = m['signaturePng'];
    final created = m['createdAt'];
    final changes = m['changes'];
    final details = m['details'];
    return SignOffRecord(
      id: d.id,
      subjectType: (m['subjectType'] ?? '').toString(),
      subjectId: (m['subjectId'] ?? '').toString(),
      ownerId: (m['ownerId'] ?? '').toString(),
      ownerName: (m['ownerName'] ?? '').toString(),
      municipalityId: (m['municipalityId'] ?? '').toString(),
      periodKey: (m['periodKey'] ?? '').toString(),
      action: (m['action'] ?? '').toString(),
      summary: (m['summary'] ?? '').toString(),
      details: details is List ? details.map((e) => e.toString()).toList() : const [],
      reason: (m['reason'] ?? '').toString(),
      signerName: (m['signerName'] ?? '').toString(),
      signerPosition: (m['signerPosition'] ?? '').toString(),
      signaturePng: sig is Blob ? sig.bytes : null,
      signatureSha256: (m['signatureSha256'] ?? '').toString(),
      contentHash: (m['contentHash'] ?? '').toString(),
      snapshot: m['snapshot'] is Map ? Map<String, dynamic>.from(m['snapshot'] as Map) : const {},
      changes: changes is List ? changes.map(SignOffChange.fromMap).toList() : const [],
      changesTruncated: (m['changesTruncated'] as num?)?.toInt() ?? 0,
      accountEmail: (m['accountEmail'] ?? '').toString(),
      platform: (m['platform'] ?? '').toString(),
      createdAt: created is Timestamp ? created.toDate() : null,
    );
  }
}

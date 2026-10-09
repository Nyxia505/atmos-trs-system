import 'package:cloud_firestore/cloud_firestore.dart';

import 'package:atmos_trs_system/config/mice_event_types.dart';
import 'package:atmos_trs_system/models/ae_register.dart';
import 'package:atmos_trs_system/models/sign_off.dart';

/// One event line of the CUS MICE Utilization Survey (CUS BY EST row).
///
/// Multi-day events are one row ([dateStart]…[dateEnd]); [hours] is the total
/// for the whole event. The row belongs to the month of [dateStart].
class MiceEvent {
  const MiceEvent({
    required this.id,
    required this.dateStart,
    required this.eventName,
    required this.eventType,
    required this.category,
    this.dateEnd,
    this.hours = 0,
    this.foreign = 0,
    this.local = 0,
    this.male = 0,
    this.female = 0,
    this.hasExhibit = false,
    this.exhibitors = 0,
    this.exhibitVisitors = 0,
    this.organizerName = '',
    this.organizerAddress = '',
    this.contactPerson = '',
    this.contactNo = '',
    this.remarks = '',
    this.foreignCountries = const {},
    this.isDemo = false,
    this.audit = const AeRowAudit(),
  });

  final String id;
  final DateTime dateStart;

  /// Last day for multi-day events (null / same day = one-day event).
  final DateTime? dateEnd;
  final String eventName;
  final double hours;

  /// Label printed in "TYPE OF EVENT" (base suggestion or venue custom type).
  final String eventType;
  final MiceCategory category;
  final int foreign;
  final int local;
  final int male;
  final int female;
  final bool hasExhibit;
  final int exhibitors;
  final int exhibitVisitors;
  final String organizerName;
  final String organizerAddress;
  final String contactPerson;
  final String contactNo;
  final String remarks;

  /// Optional analytics-only breakdown of [foreign] (country → attendees).
  final Map<String, int> foreignCountries;
  final bool isDemo;

  /// Not part of the CUS row; never included in [toMap] or content hashes.
  final AeRowAudit audit;

  int get total => foreign + local;
  DateTime get lastDay => dateEnd != null && dateEnd!.isAfter(dateStart) ? dateEnd! : dateStart;
  int get days => lastDay.difference(dateStart).inDays + 1;
  bool get isMultiDay => days > 1;

  /// "Name and Address of Organizer, Contact Person & Tel. No." cell text.
  String get organizerCell => [
        organizerName.trim(),
        organizerAddress.trim(),
        [contactPerson.trim(), contactNo.trim()].where((s) => s.isNotEmpty).join(' · '),
      ].where((s) => s.isNotEmpty).join(', ');

  MiceEvent copyWith({
    String? id,
    DateTime? dateStart,
    DateTime? dateEnd,
    bool clearDateEnd = false,
    String? eventName,
    double? hours,
    String? eventType,
    MiceCategory? category,
    int? foreign,
    int? local,
    int? male,
    int? female,
    bool? hasExhibit,
    int? exhibitors,
    int? exhibitVisitors,
    String? organizerName,
    String? organizerAddress,
    String? contactPerson,
    String? contactNo,
    String? remarks,
    Map<String, int>? foreignCountries,
    bool? isDemo,
  }) =>
      MiceEvent(
        id: id ?? this.id,
        dateStart: dateStart ?? this.dateStart,
        dateEnd: clearDateEnd ? null : (dateEnd ?? this.dateEnd),
        eventName: eventName ?? this.eventName,
        hours: hours ?? this.hours,
        eventType: eventType ?? this.eventType,
        category: category ?? this.category,
        foreign: foreign ?? this.foreign,
        local: local ?? this.local,
        male: male ?? this.male,
        female: female ?? this.female,
        hasExhibit: hasExhibit ?? this.hasExhibit,
        exhibitors: exhibitors ?? this.exhibitors,
        exhibitVisitors: exhibitVisitors ?? this.exhibitVisitors,
        organizerName: organizerName ?? this.organizerName,
        organizerAddress: organizerAddress ?? this.organizerAddress,
        contactPerson: contactPerson ?? this.contactPerson,
        contactNo: contactNo ?? this.contactNo,
        remarks: remarks ?? this.remarks,
        foreignCountries: foreignCountries ?? this.foreignCountries,
        isDemo: isDemo ?? this.isDemo,
        audit: audit,
      );

  Map<String, dynamic> toMap() => {
        'dateStart': AeRegisterRow.dateKey(dateStart),
        if (isMultiDay) 'dateEnd': AeRegisterRow.dateKey(lastDay),
        'eventName': eventName.trim(),
        'hours': hours,
        'eventType': eventType.trim(),
        'category': category.id,
        'foreign': foreign,
        'local': local,
        'male': male,
        'female': female,
        'hasExhibit': hasExhibit,
        if (hasExhibit) ...{
          'exhibitors': exhibitors,
          'exhibitVisitors': exhibitVisitors,
        },
        'organizerName': organizerName.trim(),
        'organizerAddress': organizerAddress.trim(),
        'contactPerson': contactPerson.trim(),
        'contactNo': contactNo.trim(),
        if (remarks.trim().isNotEmpty) 'remarks': remarks.trim(),
        if (foreignCountries.isNotEmpty)
          'foreignCountries': {
            for (final e in foreignCountries.entries)
              if (e.value > 0) e.key: e.value,
          },
        if (isDemo) 'seed': 'demo',
      };

  factory MiceEvent.fromMap(String id, Map<String, dynamic> m) {
    final fc = m['foreignCountries'];
    final hasExhibit = m['hasExhibit'] == true;
    return MiceEvent(
      id: id,
      dateStart: AeRegisterRow.parseDateKey(m['dateStart']) ?? DateTime(1970),
      dateEnd: AeRegisterRow.parseDateKey(m['dateEnd']),
      eventName: (m['eventName'] ?? '').toString(),
      hours: _double(m['hours']),
      eventType: (m['eventType'] ?? '').toString(),
      category: MiceCategory.fromId(m['category']?.toString()),
      foreign: _int(m['foreign']),
      local: _int(m['local']),
      male: _int(m['male']),
      female: _int(m['female']),
      hasExhibit: hasExhibit,
      exhibitors: hasExhibit ? _int(m['exhibitors']) : 0,
      exhibitVisitors: hasExhibit ? _int(m['exhibitVisitors']) : 0,
      organizerName: (m['organizerName'] ?? '').toString(),
      organizerAddress: (m['organizerAddress'] ?? '').toString(),
      contactPerson: (m['contactPerson'] ?? '').toString(),
      contactNo: (m['contactNo'] ?? '').toString(),
      remarks: (m['remarks'] ?? '').toString(),
      foreignCountries: fc is Map
          ? {
              for (final e in fc.entries)
                if (_int(e.value) > 0) e.key.toString(): _int(e.value),
            }
          : const {},
      isDemo: (m['seed'] ?? '').toString() == 'demo',
      audit: AeRowAudit.fromMap(m),
    );
  }

  factory MiceEvent.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) =>
      MiceEvent.fromMap(doc.id, doc.data() ?? const {});
}

/// Events + attendees for one [MiceCategory].
class MiceCategoryTotals {
  const MiceCategoryTotals({this.events = 0, this.attendees = 0, this.hours = 0});

  final int events;
  final int attendees;
  final double hours;

  MiceCategoryTotals operator +(MiceCategoryTotals o) => MiceCategoryTotals(
        events: events + o.events,
        attendees: attendees + o.attendees,
        hours: hours + o.hours,
      );

  Map<String, dynamic> toMap() => {'events': events, 'attendees': attendees, 'hours': hours};

  factory MiceCategoryTotals.fromMap(dynamic m) {
    if (m is! Map) return const MiceCategoryTotals();
    return MiceCategoryTotals(
      events: _int(m['events']),
      attendees: _int(m['attendees']),
      hours: _double(m['hours']),
    );
  }
}

/// Monthly totals saved on the MICE header (CUS SUMMARY totals row).
class MiceMonthTotals {
  const MiceMonthTotals({
    this.events = 0,
    this.hours = 0,
    this.foreign = 0,
    this.local = 0,
    this.male = 0,
    this.female = 0,
    this.exhibitions = 0,
    this.exhibitors = 0,
    this.exhibitVisitors = 0,
    this.multiDayEvents = 0,
    this.byCategory = const {},
    this.byCountry = const {},
  });

  final int events;
  final double hours;
  final int foreign;
  final int local;
  final int male;
  final int female;

  /// Events with an exhibit component.
  final int exhibitions;
  final int exhibitors;
  final int exhibitVisitors;
  final int multiDayEvents;

  /// [MiceCategory.id] → totals.
  final Map<String, MiceCategoryTotals> byCategory;

  /// Foreign attendee country → count (optional breakdown).
  final Map<String, int> byCountry;

  int get attendees => foreign + local;

  Map<String, dynamic> toMap() => {
        'events': events,
        'hours': hours,
        'foreign': foreign,
        'local': local,
        'attendees': attendees,
        'male': male,
        'female': female,
        'exhibitions': exhibitions,
        'exhibitors': exhibitors,
        'exhibitVisitors': exhibitVisitors,
        'multiDayEvents': multiDayEvents,
        'byCategory': {for (final e in byCategory.entries) e.key: e.value.toMap()},
        'byCountry': {
          for (final e in byCountry.entries) _fieldKey(e.key): {'label': e.key, 'count': e.value},
        },
      };

  factory MiceMonthTotals.fromMap(dynamic raw) {
    if (raw is! Map) return const MiceMonthTotals();
    final m = Map<String, dynamic>.from(raw);
    final bc = m['byCategory'];
    final bn = m['byCountry'];
    return MiceMonthTotals(
      events: _int(m['events']),
      hours: _double(m['hours']),
      foreign: _int(m['foreign']),
      local: _int(m['local']),
      male: _int(m['male']),
      female: _int(m['female']),
      exhibitions: _int(m['exhibitions']),
      exhibitors: _int(m['exhibitors']),
      exhibitVisitors: _int(m['exhibitVisitors']),
      multiDayEvents: _int(m['multiDayEvents']),
      byCategory: bc is Map
          ? {for (final e in bc.entries) e.key.toString(): MiceCategoryTotals.fromMap(e.value)}
          : const {},
      byCountry: bn is Map
          ? {
              for (final e in bn.entries)
                (e.value is Map && (e.value['label'] ?? '').toString().isNotEmpty
                        ? e.value['label'].toString()
                        : e.key.toString()):
                    e.value is Map ? _int(e.value['count']) : _int(e.value),
            }
          : const {},
    );
  }

  static String _fieldKey(String label) {
    final k = label.trim().replaceAll(RegExp(r'[^A-Za-z0-9]+'), '_');
    return k.isEmpty ? 'unspecified' : k;
  }
}

/// `mice_monthly_reports/{aeId}_{yyyy}_{mm}` header document.
class MiceMonthlyReport {
  const MiceMonthlyReport({
    required this.id,
    required this.aeId,
    required this.year,
    required this.month,
    this.aeName = '',
    this.municipalityId = '',
    this.municipality = '',
    this.province = 'Misamis Occidental',
    this.category = '',
    this.status = AeReportStatus.draft,
    this.submittedAt,
    this.updatedAt,
    this.totals = const MiceMonthTotals(),
    this.isDemo = false,
    this.lastSignOff,
  });

  final String id;
  final String aeId;
  final int year;
  final int month;
  final String aeName;
  final String municipalityId;
  final String municipality;
  final String province;

  /// Establishment signup category (hotel, events place, …).
  final String category;
  final AeReportStatus status;
  final DateTime? submittedAt;
  final DateTime? updatedAt;
  final MiceMonthTotals totals;
  final bool isDemo;
  final SignOffStamp? lastSignOff;

  String get periodKey => AeMonthlyReport.periodKeyFor(year, month);
  bool get isSubmitted => status == AeReportStatus.submitted;

  /// Submitted with zero events = an explicit "no events this month" report.
  bool get isNilReport => isSubmitted && totals.events == 0;

  static String docIdFor(String aeId, int year, int month) => AeMonthlyReport.docIdFor(aeId, year, month);

  MiceMonthlyReport copyWith({AeReportStatus? status, MiceMonthTotals? totals}) => MiceMonthlyReport(
        id: id,
        aeId: aeId,
        year: year,
        month: month,
        aeName: aeName,
        municipalityId: municipalityId,
        municipality: municipality,
        province: province,
        category: category,
        status: status ?? this.status,
        submittedAt: submittedAt,
        updatedAt: updatedAt,
        totals: totals ?? this.totals,
        isDemo: isDemo,
        lastSignOff: lastSignOff,
      );

  Map<String, dynamic> toHeaderMap() => {
        'aeId': aeId,
        'aeName': aeName,
        'municipalityId': municipalityId,
        'municipality': municipality,
        'province': province,
        'periodKey': periodKey,
        'year': year,
        'month': month,
        'category': category,
        'status': status.name,
        if (submittedAt != null) 'submittedAt': Timestamp.fromDate(submittedAt!),
        'totals': totals.toMap(),
        if (isDemo) 'seed': 'demo',
      };

  factory MiceMonthlyReport.fromMap(String id, Map<String, dynamic> m) {
    DateTime? ts(dynamic v) => v is Timestamp ? v.toDate() : (v is DateTime ? v : null);
    return MiceMonthlyReport(
      id: id,
      aeId: (m['aeId'] ?? '').toString(),
      year: _int(m['year']),
      month: _int(m['month']),
      aeName: (m['aeName'] ?? '').toString(),
      municipalityId: (m['municipalityId'] ?? '').toString(),
      municipality: (m['municipality'] ?? '').toString(),
      province: (m['province'] ?? 'Misamis Occidental').toString(),
      category: (m['category'] ?? '').toString(),
      status: (m['status'] ?? '') == AeReportStatus.submitted.name
          ? AeReportStatus.submitted
          : AeReportStatus.draft,
      submittedAt: ts(m['submittedAt']),
      updatedAt: ts(m['updatedAt']),
      totals: MiceMonthTotals.fromMap(m['totals']),
      isDemo: (m['seed'] ?? '').toString() == 'demo',
      lastSignOff: SignOffStamp.fromMap(m['lastSignOff']),
    );
  }

  factory MiceMonthlyReport.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) =>
      MiceMonthlyReport.fromMap(doc.id, doc.data() ?? const {});
}

int _int(dynamic v) {
  if (v is int) return v;
  if (v is num) return v.toInt();
  return int.tryParse((v ?? '').toString()) ?? 0;
}

double _double(dynamic v) {
  if (v is num) return v.toDouble();
  return double.tryParse((v ?? '').toString()) ?? 0;
}

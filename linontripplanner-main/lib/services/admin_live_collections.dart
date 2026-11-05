import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import 'reports/report_check_ins.dart';

typedef AdminLiveDocs = List<QueryDocumentSnapshot<Map<String, dynamic>>>;

/// One shared `tourists` + `qr_checkins` listener for the OPTACA portal.
///
/// Overview, Tourist Monitoring, Municipality Performance,
/// check-in history, and DOT reports previously each opened their own
/// full-collection `snapshots()` when the tab was built.
class AdminLiveCollections {
  AdminLiveCollections._();

  static final AdminLiveCollections instance = AdminLiveCollections._();

  final ValueNotifier<int> revision = ValueNotifier<int>(0);

  AdminLiveDocs tourists = const [];
  AdminLiveDocs checkIns = const [];

  Object? touristsError;
  Object? checkInsError;
  bool touristsReady = false;
  bool checkInsReady = false;

  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _touristsSub;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _checkInsSub;
  Timer? _debounce;
  Timer? _initialFlushTimer;
  bool _initialFlushed = false;
  int _retainCount = 0;
  List<CheckInRecord>? _checkInRecords;

  bool get isListening => _retainCount > 0;

  /// Parsed check-ins, built once per snapshot and only when a caller needs them.
  List<CheckInRecord> get checkInRecords {
    final cached = _checkInRecords;
    if (cached != null) return cached;
    final parsed = [
      for (final doc in checkIns) CheckInRecord.fromRaw(doc.id, doc.data()),
    ];
    _checkInRecords = parsed;
    return parsed;
  }

  void retain() {
    _retainCount++;
    if (_retainCount == 1) _start();
  }

  void release() {
    if (_retainCount <= 0) return;
    _retainCount--;
    if (_retainCount == 0) _stop();
  }

  void retry() {
    _stop();
    tourists = const [];
    checkIns = const [];
    _checkInRecords = null;
    touristsError = null;
    checkInsError = null;
    touristsReady = false;
    checkInsReady = false;
    _initialFlushed = false;
    revision.value++;
    if (_retainCount > 0) _start();
  }

  void _start() {
    final db = FirebaseFirestore.instance;
    _initialFlushTimer?.cancel();
    _initialFlushTimer = Timer(const Duration(milliseconds: 700), () {
      if (_initialFlushed) return;
      _initialFlushed = true;
      revision.value++;
    });
    _touristsSub = db.collection('tourists').snapshots().listen(
      (snap) {
        tourists = snap.docs;
        touristsError = null;
        touristsReady = true;
        _bump();
      },
      onError: (Object error, StackTrace stack) {
        debugPrint('AdminLiveCollections tourists: $error\n$stack');
        touristsError = error;
        touristsReady = true;
        _bump();
      },
    );
    _checkInsSub = db.collection(kQrCheckInsCollection).snapshots().listen(
      (snap) {
        checkIns = snap.docs;
        _checkInRecords = null;
        checkInsError = null;
        checkInsReady = true;
        _bump();
      },
      onError: (Object error, StackTrace stack) {
        debugPrint('AdminLiveCollections checkIns: $error\n$stack');
        checkInsError = error;
        checkInsReady = true;
        _bump();
      },
    );
  }

  void _stop() {
    _debounce?.cancel();
    _debounce = null;
    _initialFlushTimer?.cancel();
    _initialFlushTimer = null;
    _touristsSub?.cancel();
    _checkInsSub?.cancel();
    _touristsSub = null;
    _checkInsSub = null;
  }

  void _bump() {
    if (!_initialFlushed) {
      if (!touristsReady || !checkInsReady) return;
      _initialFlushTimer?.cancel();
      _initialFlushTimer = null;
      _initialFlushed = true;
      revision.value++;
      return;
    }
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 80), () {
      revision.value++;
    });
  }
}

/// True when this portal module is the selected tab (tickers are enabled).
bool optacaTabIsActive(BuildContext context) =>
    TickerMode.valuesOf(context).enabled;

/// Retains [AdminLiveCollections] for the lifetime of the portal shell.
class AdminLiveScope extends StatefulWidget {
  const AdminLiveScope({super.key, required this.child});

  final Widget child;

  @override
  State<AdminLiveScope> createState() => _AdminLiveScopeState();
}

class _AdminLiveScopeState extends State<AdminLiveScope> {
  @override
  void initState() {
    super.initState();
    AdminLiveCollections.instance.retain();
  }

  @override
  void dispose() {
    AdminLiveCollections.instance.release();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

class AdminLiveDataBuilder extends StatefulWidget {
  const AdminLiveDataBuilder({super.key, required this.builder});

  final Widget Function(BuildContext context, AdminLiveCollections live) builder;

  @override
  State<AdminLiveDataBuilder> createState() => _AdminLiveDataBuilderState();
}

class _AdminLiveDataBuilderState extends State<AdminLiveDataBuilder> {
  @override
  void initState() {
    super.initState();
    AdminLiveCollections.instance.revision.addListener(_onLive);
  }

  @override
  void dispose() {
    AdminLiveCollections.instance.revision.removeListener(_onLive);
    super.dispose();
  }

  void _onLive() {
    if (!mounted) return;
    if (!optacaTabIsActive(context)) return;
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return widget.builder(context, AdminLiveCollections.instance);
  }
}

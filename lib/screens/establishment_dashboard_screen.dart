import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:atmos_trs_system/config/app_theme.dart';
import 'package:atmos_trs_system/config/auth_config.dart';
import 'package:atmos_trs_system/config/session_storage.dart';
import 'package:atmos_trs_system/services/establishment_gallery_service.dart';
import 'package:atmos_trs_system/services/establishment_firestore_write.dart';
import 'package:atmos_trs_system/services/establishment_map_pin_store.dart';
import 'package:atmos_trs_system/services/establishment_registration_service.dart';
import 'package:atmos_trs_system/services/establishment_stay_service.dart';
import 'package:atmos_trs_system/services/firestore_auth_gate.dart';
import 'package:atmos_trs_system/utils/establishment_capability.dart';
import 'package:atmos_trs_system/utils/establishment_dss_aggregates.dart';
import 'package:atmos_trs_system/utils/establishment_lodging_hours.dart';
import 'package:atmos_trs_system/utils/establishment_qr_export.dart';
import 'package:atmos_trs_system/utils/establishment_room_grid.dart';
import 'package:atmos_trs_system/utils/spot_qr_helper.dart';
import 'package:atmos_trs_system/widgets/establishment_dash_tokens.dart';
import 'package:atmos_trs_system/widgets/establishment_dashboard_components.dart';
import 'package:atmos_trs_system/widgets/establishment_desk_confirm_dialog.dart';
import 'package:atmos_trs_system/widgets/establishment_home_board.dart';
import 'package:atmos_trs_system/widgets/establishment_insights_board.dart';
import 'package:atmos_trs_system/widgets/establishment_profile_cards.dart';
import 'package:atmos_trs_system/widgets/establishment_reviews_board.dart';
import 'package:atmos_trs_system/widgets/establishment_rooms_panel.dart';
import 'package:atmos_trs_system/widgets/establishment_settings_panel.dart';
import 'package:atmos_trs_system/widgets/establishment_stay_tables.dart';

/// Tourism establishment ops dashboard: pack-aware shell + stay queue.
class EstablishmentDashboardScreen extends StatefulWidget {
  const EstablishmentDashboardScreen({super.key});

  @override
  State<EstablishmentDashboardScreen> createState() =>
      _EstablishmentDashboardScreenState();
}

class _EstablishmentDashboardScreenState
    extends State<EstablishmentDashboardScreen> {
  static const double _mobileBreakpoint = 900;

  bool _loading = true;
  bool _sidebarExpanded = true;
  int _selectedIndex = 0;
  String _uid = '';
  String _businessName = '';
  String _category = '';
  String _status = 'pending';
  String _municipality = '';
  String _municipalityId = '';
  int _roomCount = 0;
  String _checkInTime = EstablishmentLodgingHours.defaultCheckIn;
  String _checkOutTime = EstablishmentLodgingHours.defaultCheckOut;
  double? _latitude;
  double? _longitude;
  List<String> _galleryUrls = const [];
  List<String> _disabledRooms = const [];
  Map<String, EstablishmentRoomInfo> _roomInventory = const {};
  String? _error;
  String? _qrPayload;

  late final TextEditingController _roomCountCtrl;
  bool _savingRooms = false;
  bool _savingHours = false;
  bool _savingLocation = false;
  bool _locating = false;
  bool _galleryBusy = false;
  bool _statusBannerDismissed = false;

  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

  EstablishmentPack get _pack => EstablishmentCapability.packFor(_category);
  EstablishmentPackCopy get _copy =>
      EstablishmentCapability.copyFor(_category);
  bool get _isLodging => _pack == EstablishmentPack.lodging;
  IconData get _categoryIcon => EstablishmentCapability.iconFor(_category);

  List<_AeTab> get _tabs => _isLodging
      ? const [
          _AeTab.home,
          _AeTab.rooms,
          _AeTab.insights,
          _AeTab.reviews,
          _AeTab.qr,
          _AeTab.settings,
        ]
      : const [
          _AeTab.home,
          _AeTab.insights,
          _AeTab.reviews,
          _AeTab.qr,
          _AeTab.settings,
        ];

  _AeTab get _currentTab {
    final tabs = _tabs;
    if (_selectedIndex < 0 || _selectedIndex >= tabs.length) {
      return _AeTab.home;
    }
    return tabs[_selectedIndex];
  }

  @override
  void initState() {
    super.initState();
    _roomCountCtrl = TextEditingController(text: '0');
    _load();
  }

  // One Firestore listener per account; a new stream on every build would
  // re-subscribe (re-read + loading flash) on each setState.
  Stream<List<EstablishmentStayRequest>>? _staysStream;
  String _staysStreamUid = '';

  Stream<List<EstablishmentStayRequest>> _staysStreamFor(String uid) {
    if (uid.isEmpty) return const Stream.empty();
    if (_staysStream == null || _staysStreamUid != uid) {
      _staysStreamUid = uid;
      _staysStream = EstablishmentStayService.watchForEstablishment(uid);
    }
    return _staysStream!;
  }

  @override
  void dispose() {
    _roomCountCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final authUid = FirebaseAuth.instance.currentUser?.uid;
    final storedUid = await SessionStorage.getStoredUser();
    final uid = (authUid != null && authUid.isNotEmpty) ? authUid : storedUid;
    if (uid == null || uid.isEmpty) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Session expired. Please log in again.';
      });
      return;
    }

    final tokenOk = await FirestoreAuthGate.ensureFreshIdToken();
    if (!tokenOk && FirebaseAuth.instance.currentUser == null) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = FirestoreAuthGate.missingAuthMessage();
      });
      return;
    }

    try {
      final db = FirebaseFirestore.instance;
      Future<Map<String, dynamic>> readUser() async {
        try {
          final userDoc = await db.collection('users').doc(uid).get();
          return userDoc.data() ?? const <String, dynamic>{};
        } catch (e) {
          debugPrint('[AE Dashboard] users/$uid read: $e');
          return const <String, dynamic>{};
        }
      }

      Future<Map<String, dynamic>> readEstablishment() async {
        final estDoc = await db
            .collection(EstablishmentRegistrationService.establishmentsCollection)
            .doc(uid)
            .get();
        return estDoc.data() ?? const <String, dynamic>{};
      }

      final docs = await Future.wait([readUser(), readEstablishment()]);
      final user = docs[0];
      final est = docs[1];
      final businessName = (est['businessName'] ??
              est['name'] ??
              user['businessName'] ??
              'Your establishment')
          .toString();
      final municipalityId =
          (user['municipalityId'] ?? est['municipalityId'] ?? '').toString();
      final roomRaw = est['roomCount'] ?? user['roomCount'];
      final roomCount = roomRaw is int
          ? roomRaw
          : int.tryParse(roomRaw?.toString() ?? '') ?? 0;
      final disabledRooms = EstablishmentRoomGrid.parseDisabledRooms(
        est['disabledRooms'],
      );
      final roomInventory = EstablishmentRoomGrid.parseInventory(
        est['roomInventory'],
      );
      final checkInRaw = (est['checkInTime'] ?? user['checkInTime'] ?? '')
          .toString()
          .trim();
      final checkOutRaw = (est['checkOutTime'] ?? user['checkOutTime'] ?? '')
          .toString()
          .trim();
      double? asDouble(dynamic raw) {
        if (raw is double) return raw;
        if (raw is num) return raw.toDouble();
        return double.tryParse(raw?.toString() ?? '');
      }

      final latitude = asDouble(est['latitude'] ?? user['latitude']);
      final longitude = asDouble(est['longitude'] ?? user['longitude']);
      final galleryUrls = EstablishmentGalleryService.parseUrls(
        est[EstablishmentGalleryService.fieldGalleryUrls],
      );
      if (!mounted) return;
      final category =
          (est['category'] ?? est['type'] ?? user['category'] ?? '').toString();
      final lodging = EstablishmentCapability.isLodging(category);
      final maxTab = lodging ? 5 : 4;
      setState(() {
        _uid = uid;
        _businessName = businessName;
        _category = category;
        _status = (user['status'] ?? est['status'] ?? 'pending')
            .toString()
            .toLowerCase();
        _municipality =
            (user['municipality'] ?? est['municipality'] ?? '').toString();
        _municipalityId = municipalityId;
        _roomCount = roomCount;
        _checkInTime = EstablishmentLodgingHours.tryParse(checkInRaw) != null
            ? checkInRaw
            : EstablishmentLodgingHours.defaultCheckIn;
        _checkOutTime = EstablishmentLodgingHours.tryParse(checkOutRaw) != null
            ? checkOutRaw
            : EstablishmentLodgingHours.defaultCheckOut;
        _latitude = latitude;
        _longitude = longitude;
        _galleryUrls = galleryUrls;
        _disabledRooms = disabledRooms;
        _roomInventory = roomInventory;
        _roomCountCtrl.text = '$roomCount';
        _qrPayload = establishmentQrData(
          uid,
          municipalityId: municipalityId,
          businessName: businessName,
        );
        if (_selectedIndex > maxTab) _selectedIndex = 0;
        _loading = false;
        _error = null;
      });
      // Prefer Supabase pin (free-tier source of truth) over stale Firestore coords.
      final supabasePin = await EstablishmentMapPinStore.load(uid);
      if (!mounted || supabasePin == null) return;
      setState(() {
        _latitude = supabasePin.latitude;
        _longitude = supabasePin.longitude;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Could not load establishment profile.';
      });
    }
  }

  Future<void> _saveRoomCount({
    required List<EstablishmentStayRequest> allStays,
  }) async {
    if (_uid.isEmpty || _savingRooms) return;
    final parsed = int.tryParse(_roomCountCtrl.text.trim());
    if (parsed == null || parsed < 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Enter a valid non-negative room count.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    final slots = EstablishmentRoomGrid.buildSlots(
      roomCount: _roomCount,
      disabledRooms: _disabledRooms,
      stays: allStays,
      inventory: _roomInventory,
    );
    final stats = EstablishmentRoomGrid.statsFor(slots);
    final occupiedCount = stats.occupied;

    if (parsed < occupiedCount) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Cannot set room count below $occupiedCount currently occupied rooms.',
          ),
          backgroundColor: Colors.red.shade700,
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    final maxRef = EstablishmentRoomGrid.maxReferencedSlot(
      roomCount: _roomCount > parsed ? _roomCount : parsed,
      disabledRooms: _disabledRooms,
      stays: allStays,
    );
    final willPrune = parsed < maxRef;
    final prunedPreview = EstablishmentRoomGrid.pruneDisabled(
      _disabledRooms,
      parsed,
    );

    final message = parsed == _roomCount && !willPrune
        ? 'Room count is already $parsed. Save anyway?'
        : willPrune
            ? 'Reduce to $parsed rooms? Disabled rooms above $parsed '
                'will be removed (${_disabledRooms.length - prunedPreview.length} pruned).'
            : 'Update total rooms from $_roomCount to $parsed?';

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Confirm room count'),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(
              backgroundColor: AppTheme.brandOrange,
            ),
            child: const Text('Confirm'),
          ),
        ],
      ),
    );
    if (ok != true) return;

    setState(() => _savingRooms = true);
    final nextDisabled = EstablishmentRoomGrid.pruneDisabled(
      _disabledRooms,
      parsed,
    );
    final nextInventory = EstablishmentRoomGrid.pruneInventory(
      _roomInventory,
      parsed,
    );
    try {
      await FirebaseFirestore.instance
          .collection(
            EstablishmentRegistrationService.establishmentsCollection,
          )
          .doc(_uid)
          .set({
            'roomCount': parsed,
            'disabledRooms': nextDisabled,
            'roomInventory':
                EstablishmentRoomGrid.inventoryToFirestore(nextInventory),
          }, SetOptions(merge: true));
      if (!mounted) return;
      setState(() {
        _roomCount = parsed;
        _disabledRooms = nextDisabled;
        _roomInventory = nextInventory;
        _savingRooms = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Total rooms saved.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _savingRooms = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Save failed: $e'),
          backgroundColor: Colors.red.shade700,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<bool> _toggleRoomDisabled({
    required EstablishmentRoomSlot slot,
    required bool disable,
  }) async {
    if (_uid.isEmpty) return false;
    if (disable && slot.isOccupied) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Cannot disable an occupied room.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return false;
    }
    final next = [..._disabledRooms];
    if (disable) {
      if (!next.contains(slot.id)) next.add(slot.id);
    } else {
      next.removeWhere((e) => e == slot.id);
    }
    try {
      await FirebaseFirestore.instance
          .collection(
            EstablishmentRegistrationService.establishmentsCollection,
          )
          .doc(_uid)
          .set({'disabledRooms': next}, SetOptions(merge: true));
      if (!mounted) return false;
      setState(() => _disabledRooms = next);
      return true;
    } catch (e) {
      if (!mounted) return false;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Could not update room: $e'),
          backgroundColor: Colors.red.shade700,
          behavior: SnackBarBehavior.floating,
        ),
      );
      return false;
    }
  }

  Future<void> _logout() async {
    await SessionStorage.clearSession();
    AuthConfig.currentUserUid = null;
    try {
      await FirebaseAuth.instance.signOut();
    } catch (_) {}
    if (!mounted) return;
    Navigator.pushNamedAndRemoveUntil(context, '/login', (_) => false);
  }

  bool get _isPending => _status == 'pending' || _status.isEmpty;
  bool get _isRejected => _status == 'rejected';

  Future<void> _saveRoomInfo(String slotId, EstablishmentRoomInfo info) async {
    if (_uid.isEmpty) return;
    final next = Map<String, EstablishmentRoomInfo>.from(_roomInventory);
    next[slotId] = info;
    try {
      await FirebaseFirestore.instance
          .collection(
            EstablishmentRegistrationService.establishmentsCollection,
          )
          .doc(_uid)
          .set({
            'roomInventory': EstablishmentRoomGrid.inventoryToFirestore(next),
          }, SetOptions(merge: true));
      if (!mounted) return;
      setState(() => _roomInventory = next);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Room $slotId details saved.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Could not save room details: $e'),
          backgroundColor: Colors.red.shade700,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<void> _pickAndSaveCheckInTime() async {
    if (_uid.isEmpty || _savingHours) return;
    final current = EstablishmentLodgingHours.tryParse(_checkInTime) ??
        const TimeOfDay(hour: 14, minute: 0);
    final picked = await showTimePicker(context: context, initialTime: current);
    if (picked == null || !mounted) return;
    await _saveLodgingHours(
      checkIn: EstablishmentLodgingHours.format(picked),
      checkOut: _checkOutTime,
    );
  }

  Future<void> _pickAndSaveCheckOutTime() async {
    if (_uid.isEmpty || _savingHours) return;
    final current = EstablishmentLodgingHours.tryParse(_checkOutTime) ??
        const TimeOfDay(hour: 12, minute: 0);
    final picked = await showTimePicker(context: context, initialTime: current);
    if (picked == null || !mounted) return;
    await _saveLodgingHours(
      checkIn: _checkInTime,
      checkOut: EstablishmentLodgingHours.format(picked),
    );
  }

  Future<void> _saveLodgingHours({
    required String checkIn,
    required String checkOut,
  }) async {
    final cin = EstablishmentLodgingHours.tryParse(checkIn);
    final cout = EstablishmentLodgingHours.tryParse(checkOut);
    if (cin == null || cout == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Invalid check-in or check-out time.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }
    if (EstablishmentLodgingHours.minutesSinceMidnight(cin) ==
        EstablishmentLodgingHours.minutesSinceMidnight(cout)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Check-in and check-out times must be different.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }
    setState(() => _savingHours = true);
    try {
      await FirebaseFirestore.instance
          .collection(
            EstablishmentRegistrationService.establishmentsCollection,
          )
          .doc(_uid)
          .set({
            'checkInTime': checkIn,
            'checkOutTime': checkOut,
          }, SetOptions(merge: true));
      if (!mounted) return;
      setState(() {
        _checkInTime = checkIn;
        _checkOutTime = checkOut;
        _savingHours = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Check-in / check-out times saved.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _savingHours = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Save failed: $e'),
          backgroundColor: Colors.red.shade700,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<void> _saveMapPin({
    required double latitude,
    required double longitude,
  }) async {
    if (_uid.isEmpty || _savingLocation) return;
    if (latitude.abs() < 1e-6 && longitude.abs() < 1e-6) {
      _showGallerySnack('Invalid map coordinates.', error: true);
      return;
    }
    if (_latitude != null &&
        _longitude != null &&
        (_latitude! - latitude).abs() < 1e-7 &&
        (_longitude! - longitude).abs() < 1e-7) {
      _showGallerySnack('Map pin unchanged.');
      return;
    }

    setState(() {
      _latitude = latitude;
      _longitude = longitude;
      _savingLocation = true;
    });

    // #region agent log
    debugPrint(
      '[DBG-b96d41] pin save start lat=${latitude.toStringAsFixed(5)} lng=${longitude.toStringAsFixed(5)}',
    );
    // #endregion

    try {
      // Source of truth on free tier: Supabase (same bucket as photos).
      await EstablishmentMapPinStore.save(
        establishmentId: _uid,
        latitude: latitude,
        longitude: longitude,
      );
      // #region agent log
      debugPrint('[DBG-b96d41] pin supabase save ok');
      // #endregion

      if (!mounted) return;
      _showGallerySnack(
        'Map pin saved. Tourists will see it on Explore after OPTACA approval.',
      );

      // Best-effort Firestore mirror only ? never fail the UX on free-tier 429/hangs.
      // ignore: unawaited_futures
      EstablishmentFirestoreWrite.mergeFields(_uid, {
        'latitude': latitude,
        'longitude': longitude,
      }).then((_) {
        debugPrint('[DBG-b96d41] pin firestore mirror ok');
      }).catchError((Object e) {
        debugPrint('[DBG-b96d41] pin firestore mirror skipped: $e');
      });
    } catch (e) {
      // #region agent log
      debugPrint('[DBG-b96d41] pin save failed: $e');
      // #endregion
      if (!mounted) return;
      _showGallerySnack(
        'Could not save map pin. Check connection and try again.',
        error: true,
      );
    } finally {
      if (mounted) setState(() => _savingLocation = false);
    }
  }

  Future<void> _addGalleryPhoto() async {
    if (_uid.isEmpty || _galleryBusy) return;
    setState(() => _galleryBusy = true);
    try {
      final next = await EstablishmentGalleryService.pickAndUpload(
        establishmentId: _uid,
        currentUrls: _galleryUrls,
      );
      if (!mounted) return;
      setState(() => _galleryUrls = next);
      _showGallerySnack(
        'Photo added. Tourists will see it on your map profile.',
      );
    } catch (e) {
      if (!mounted) return;
      final msg = e.toString().replaceFirst('Bad state: ', '');
      _showGallerySnack(msg, error: true);
    } finally {
      if (mounted) setState(() => _galleryBusy = false);
    }
  }

  void _showGallerySnack(String message, {bool error = false}) {
    if (!mounted) return;
    final messenger = ScaffoldMessenger.maybeOf(context);
    if (messenger == null) return;
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: error ? Colors.red.shade700 : null,
          behavior: SnackBarBehavior.floating,
        ),
      );
  }

  Future<void> _removeGalleryPhoto(int index) async {
    if (_uid.isEmpty || _galleryBusy) return;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remove photo?'),
        content: const Text(
          'This photo will disappear from your tourist map profile.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    setState(() => _galleryBusy = true);
    try {
      final next = await EstablishmentGalleryService.removeAt(
        establishmentId: _uid,
        currentUrls: _galleryUrls,
        index: index,
      );
      if (!mounted) return;
      setState(() => _galleryUrls = next);
    } catch (e) {
      if (!mounted) return;
      _showGallerySnack('Remove failed: $e', error: true);
    } finally {
      if (mounted) setState(() => _galleryBusy = false);
    }
  }

  /// Stay ids with a confirm / reject / check-out in progress (blocks double taps).
  final Set<String> _staysInFlight = <String>{};

  Future<void> _guardStayAction(
    String stayId,
    Future<void> Function() action,
  ) async {
    if (!_staysInFlight.add(stayId)) return;
    try {
      await action();
    } finally {
      _staysInFlight.remove(stayId);
    }
  }

  Future<void> _openConfirmDialog(
    EstablishmentStayRequest stay, {
    required List<EstablishmentStayRequest> allStays,
  }) =>
      _guardStayAction(
        stay.id,
        () => _openConfirmDialogUnguarded(stay, allStays: allStays),
      );

  Future<void> _reject(EstablishmentStayRequest stay) =>
      _guardStayAction(stay.id, () => _rejectUnguarded(stay));

  Future<void> _checkOutStay(EstablishmentStayRequest stay) =>
      _guardStayAction(stay.id, () => _checkOutStayUnguarded(stay));

  Future<void> _openConfirmDialogUnguarded(
    EstablishmentStayRequest stay, {
    required List<EstablishmentStayRequest> allStays,
  }) async {
    final lodging = EstablishmentCapability.isLodging(
      stay.establishmentCategory.isNotEmpty
          ? stay.establishmentCategory
          : _category,
    );
    final slots = EstablishmentRoomGrid.buildSlots(
      roomCount: _roomCount,
      disabledRooms: _disabledRooms,
      stays: allStays,
      inventory: _roomInventory,
    );
    final result = await showDialog<DeskConfirmStayResult>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => EstablishmentDeskConfirmDialog(
        stay: stay,
        lodging: lodging,
        copy: _copy,
        establishmentCategory: _category,
        allSlots: slots,
        checkInTime: _checkInTime,
        checkOutTime: _checkOutTime,
      ),
    );
    if (result == null || !mounted) return;

    try {
      final checkInAt = DateTime.now();
      await EstablishmentStayService.confirmStay(
        stayId: stay.id,
        nightsStayed: result.nightsStayed,
        roomsOccupied: result.roomsOccupied,
        partySize: result.demographics.partySize,
        maleCount: result.demographics.maleCount,
        femaleCount: result.demographics.femaleCount,
        filipinoCount: result.demographics.filipinoCount,
        foreignCount: result.demographics.foreignCount,
        notes: result.notes,
        roomNumbers: result.roomNumbers,
        checkInAt: checkInAt,
        checkOutAt: result.checkOutAt ??
            (result.nightsStayed > 0
                ? EstablishmentLodgingHours.plannedCheckOutAt(
                    checkInAt: checkInAt,
                    nights: result.nightsStayed,
                    checkOutTime: _checkOutTime,
                  )
                : null),
        establishmentCategory: _category.isNotEmpty
            ? _category
            : stay.establishmentCategory,
        roomsAvailable: _roomCount > 0 ? _roomCount : stay.roomsAvailable,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_copy.confirmedSnack),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Confirm failed: $e'),
          backgroundColor: Colors.red.shade700,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<void> _rejectUnguarded(EstablishmentStayRequest stay) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(_copy.rejectTitle),
        content: Text('Reject request from ${stay.touristName}?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(
              backgroundColor: AeDashTokens.danger,
            ),
            child: const Text('Reject'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await EstablishmentStayService.rejectStay(stayId: stay.id);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Reject failed: $e')),
      );
    }
  }

  DateTime? _stayDay(EstablishmentStayRequest s) {
    final d = s.confirmedAt ?? s.checkInAt ?? s.createdAt;
    if (d == null) return null;
    return DateTime(d.year, d.month, d.day);
  }

  _EstablishmentKpis _computeKpis(List<EstablishmentStayRequest> all) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final monthStart = DateTime(now.year, now.month, 1);

    var pending = 0;
    var confirmedToday = 0;
    var guestsMonth = 0;
    var roomsMonth = 0;
    var confirmedMonthCount = 0;
    final dayGuests = <int, int>{};

    for (final s in all) {
      if (s.isPending) pending++;
      if (!s.countsForDae) continue;
      final day = _stayDay(s);
      if (day == null) continue;
      if (day == today) confirmedToday++;
      if (!day.isBefore(monthStart)) {
        guestsMonth += s.partySize;
        roomsMonth += s.roomsOccupied ?? 0;
        confirmedMonthCount++;
        dayGuests[day.day] = (dayGuests[day.day] ?? 0) + s.partySize;
      }
    }

    final avgParty = confirmedMonthCount == 0
        ? 0.0
        : guestsMonth / confirmedMonthCount;
    var peakDay = 0;
    var peakGuests = 0;
    dayGuests.forEach((day, guests) {
      if (guests > peakGuests) {
        peakGuests = guests;
        peakDay = day;
      }
    });

    return _EstablishmentKpis(
      pending: pending,
      confirmedToday: confirmedToday,
      guestsMonth: guestsMonth,
      roomsMonth: roomsMonth,
      avgPartySize: avgParty,
      peakDay: peakDay,
      peakDayGuests: peakGuests,
    );
  }

  void _selectTab(int index) {
    setState(() => _selectedIndex = index);
    if (_scaffoldKey.currentState?.isDrawerOpen ?? false) {
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final isMobile = width < _mobileBreakpoint;

    if (_loading) {
      return Scaffold(
        backgroundColor: AeDashTokens.background,
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    if (_error != null) {
      return Scaffold(
        backgroundColor: AeDashTokens.background,
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  _error!,
                  textAlign: TextAlign.center,
                  style: AeDashTokens.body(
                    color: AeDashTokens.text,
                  ),
                ),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: _logout,
                  style: FilledButton.styleFrom(
                    backgroundColor: AppTheme.brandOrange,
                  ),
                  child: const Text('Back to login'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return StreamBuilder<List<EstablishmentStayRequest>>(
      stream: _staysStreamFor(_uid),
      builder: (context, snap) {
        final all = snap.data ?? const <EstablishmentStayRequest>[];
        final pending = all.where((s) => s.isPending).toList();
        final kpis = _computeKpis(all);
        final dss = EstablishmentDssAggregates.build(all);
        final streamError = snap.hasError ? snap.error : null;
        final streamLoading = _uid.isNotEmpty && !snap.hasData && !snap.hasError;

        final dashboardData = _DashboardData(
          allStays: all,
          pending: pending,
          kpis: kpis,
          dss: dss,
          streamError: streamError,
          streamLoading: streamLoading,
        );

        return Scaffold(
          key: _scaffoldKey,
          backgroundColor: AeDashTokens.background,
          drawer: isMobile
              ? Drawer(
                  width: 280,
                  child: _buildSidebar(
                    expanded: true,
                    isDrawer: true,
                    pendingCount: pending.length,
                  ),
                )
              : null,
          body: Row(
            children: [
              if (!isMobile)
                _buildSidebar(
                  expanded: _sidebarExpanded,
                  isDrawer: false,
                  pendingCount: pending.length,
                ),
              Expanded(
                child: Column(
                  children: [
                    if (isMobile)
                      _buildTopHeader(
                        isMobile: isMobile,
                        pendingCount: pending.length,
                      ),
                    Expanded(
                      child: RefreshIndicator(
                        color: AppTheme.brandOrange,
                        onRefresh: _load,
                        child: AnimatedSwitcher(
                          duration: const Duration(milliseconds: 220),
                          switchInCurve: Curves.easeOut,
                          switchOutCurve: Curves.easeIn,
                          child: KeyedSubtree(
                            key: ValueKey(_selectedIndex),
                            child: _buildTabBody(dashboardData),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          bottomNavigationBar: isMobile
              ? _buildMobileBottomNav(pendingCount: pending.length)
              : null,
        );
      },
    );
  }

  Widget _buildTopHeader({required bool isMobile, required int pendingCount}) {
    final tabs = _tabs;
    final titles = [
      for (final t in tabs)
        switch (t) {
          _AeTab.home => 'Home',
          _AeTab.rooms => 'Rooms',
          _AeTab.insights => 'Insights',
          _AeTab.reviews => 'Reviews',
          _AeTab.qr => 'QR & profile',
          _AeTab.settings => 'Settings',
        },
    ];
    final title = titles[_selectedIndex.clamp(0, titles.length - 1)];

    return Container(
      width: double.infinity,
      padding: EdgeInsets.fromLTRB(
        isMobile ? 12 : 24,
        14,
        isMobile ? 12 : 20,
        14,
      ),
      decoration: const BoxDecoration(
        color: AeDashTokens.surface,
        border: Border(
          bottom: BorderSide(color: AeDashTokens.border),
        ),
      ),
      child: SafeArea(
        bottom: false,
        child: Row(
          children: [
            if (isMobile)
              IconButton(
                tooltip: 'Menu',
                onPressed: () => _scaffoldKey.currentState?.openDrawer(),
                icon: const Icon(Icons.menu_rounded, color: AeDashTokens.text),
              ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: AeDashTokens.heading(
                      size: isMobile ? 17 : 19,
                    ),
                  ),
                  Text(
                    '${_copy.packLabel}'
                    '${_category.isNotEmpty ? ' · $_category' : ''}'
                    '${pendingCount > 0 && _currentTab != _AeTab.home ? ' · $pendingCount pending' : ''}',
                    style: AeDashTokens.body(size: 12),
                  ),
                ],
              ),
            ),
            _statusPill(compact: true),
          ],
        ),
      ),
    );
  }

  Widget _buildSidebar({
    required bool expanded,
    required bool isDrawer,
    required int pendingCount,
  }) {
    final tabs = _tabs;
    return EstablishmentSidebar(
      businessName: _businessName,
      subtitle: _municipality.isNotEmpty ? _municipality : _copy.packLabel,
      expanded: expanded,
      width: isDrawer ? 280 : null,
      selectedIndex: _selectedIndex.clamp(0, tabs.length - 1),
      onSelect: _selectTab,
      onLogout: _logout,
      onToggle: isDrawer
          ? () => Navigator.of(context).maybePop()
          : () => setState(() => _sidebarExpanded = !_sidebarExpanded),
      items: [
        for (final t in tabs)
          switch (t) {
            _AeTab.home => EstablishmentNavEntry(
                icon: Icons.home_rounded,
                label: 'Home',
                badgeCount: pendingCount,
                section: 'Operations',
              ),
            _AeTab.rooms => const EstablishmentNavEntry(
                icon: Icons.bed_rounded,
                label: 'Rooms',
              ),
            _AeTab.insights => const EstablishmentNavEntry(
                icon: Icons.insights_rounded,
                label: 'Insights',
                section: 'Performance',
              ),
            _AeTab.reviews => const EstablishmentNavEntry(
                icon: Icons.star_rounded,
                label: 'Reviews',
              ),
            _AeTab.qr => const EstablishmentNavEntry(
                icon: Icons.qr_code_2_rounded,
                label: 'QR & Profile',
                section: 'Account',
              ),
            _AeTab.settings => const EstablishmentNavEntry(
                icon: Icons.settings_rounded,
                label: 'Settings',
              ),
          },
      ],
    );
  }

  /// Daily-use tabs on the phone bar; the rest sit behind "More" (drawer).
  static const _bottomBarTabs = [
    _AeTab.home,
    _AeTab.rooms,
    _AeTab.insights,
    _AeTab.reviews,
  ];

  Widget _buildMobileBottomNav({required int pendingCount}) {
    final tabs = _tabs;
    final barTabs = [
      for (final t in tabs)
        if (_bottomBarTabs.contains(t)) t,
    ];
    final current = barTabs.indexOf(_currentTab);
    return NavigationBar(
      selectedIndex: current >= 0 ? current : barTabs.length,
      onDestinationSelected: (i) {
        if (i >= barTabs.length) {
          _scaffoldKey.currentState?.openDrawer();
          return;
        }
        _selectTab(tabs.indexOf(barTabs[i]));
      },
      indicatorColor: AeDashTokens.softOrange,
      backgroundColor: Colors.white,
      destinations: [
        for (final t in barTabs)
          switch (t) {
            _AeTab.home => NavigationDestination(
                icon: Badge(
                  isLabelVisible: pendingCount > 0,
                  label: Text('$pendingCount'),
                  child: const Icon(Icons.home_outlined),
                ),
                selectedIcon: Badge(
                  isLabelVisible: pendingCount > 0,
                  label: Text('$pendingCount'),
                  child: const Icon(Icons.home_rounded),
                ),
                label: 'Home',
              ),
            _AeTab.rooms => const NavigationDestination(
                icon: Icon(Icons.meeting_room_outlined),
                selectedIcon: Icon(Icons.meeting_room_rounded),
                label: 'Rooms',
              ),
            _AeTab.insights => const NavigationDestination(
                icon: Icon(Icons.insights_outlined),
                selectedIcon: Icon(Icons.insights_rounded),
                label: 'Insights',
              ),
            _AeTab.reviews => const NavigationDestination(
                icon: Icon(Icons.star_outline_rounded),
                selectedIcon: Icon(Icons.star_rounded),
                label: 'Reviews',
              ),
            _AeTab.qr || _AeTab.settings => const NavigationDestination(
                icon: Icon(Icons.more_horiz_rounded),
                label: 'More',
              ),
          },
        const NavigationDestination(
          icon: Icon(Icons.more_horiz_rounded),
          label: 'More',
        ),
      ],
    );
  }

  Widget _buildTabBody(_DashboardData data) {
    if (_uid.isEmpty) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(24),
        children: [
          Text(
            'Sign in required.',
            style: AeDashTokens.body(
              color: AeDashTokens.text,
            ),
          ),
        ],
      );
    }
    if (data.streamError != null) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(24),
        children: [
          Text(
            'Could not load stays: ${data.streamError}',
            style: AeDashTokens.body(color: AeDashTokens.danger),
          ),
        ],
      );
    }
    if (data.streamLoading) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: const [
          SizedBox(height: 120),
          Center(child: CircularProgressIndicator()),
        ],
      );
    }

    switch (_currentTab) {
      case _AeTab.rooms:
        return _roomsTab(data);
      case _AeTab.insights:
        return _insightsTab(data);
      case _AeTab.reviews:
        return EstablishmentReviewsBoard(
          establishmentId: _uid,
          isLodging: _isLodging,
        );
      case _AeTab.qr:
        return _qrProfileTab(data);
      case _AeTab.settings:
        return _settingsTab(data);
      case _AeTab.home:
        return _homeTab(data);
    }
  }

  static double _pagePad(double width) =>
      width < 600 ? 14.0 : (width < 1000 ? 18.0 : 24.0);

  /// Page scroller; [header] is edge-to-edge (touches top + sidebar).
  Widget _scrollBody({Widget? header, required List<Widget> children}) {
    return LayoutBuilder(
      builder: (context, c) {
        final pad = _pagePad(c.maxWidth);
        return ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: EdgeInsets.only(bottom: pad + 12),
          children: [
            if (header != null) header,
            Padding(
              padding: EdgeInsets.fromLTRB(
                pad,
                header == null ? pad : (c.maxWidth < 600 ? 12 : 18),
                pad,
                0,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: children,
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _homeTab(_DashboardData data) {
    final roomSlots = _isLodging
        ? EstablishmentRoomGrid.buildSlots(
            roomCount: _roomCount,
            disabledRooms: _disabledRooms,
            stays: data.allStays,
            inventory: _roomInventory,
          )
        : const <EstablishmentRoomSlot>[];
    final roomStats = EstablishmentRoomGrid.statsFor(roomSlots);
    final roomsTabIndex = _tabs.indexOf(_AeTab.rooms);
    final insightsTabIndex = _tabs.indexOf(_AeTab.insights);

    final emptyParts = _copy.queueEmpty.split('. ');
    final emptyTitle = '${emptyParts.first.replaceAll('.', '')} yet.';
    final emptyHint = emptyParts.length > 1
        ? emptyParts.sublist(1).join('. ')
        : 'Print your QR and ask a tourist to scan it.';

    final requestsSection = EstablishmentStayRequestTable(
      title: _copy.queueTitle,
      description: _copy.queueHint,
      emptyTitle: emptyTitle,
      emptyHint: emptyHint,
      stays: data.allStays,
      onConfirm: (s) => _openConfirmDialog(s, allStays: data.allStays),
      onReject: _reject,
      onCheckOut: _checkOutStay,
    );

    return EstablishmentHomeBoard(
      businessName: _businessName,
      category: _category,
      municipality: _municipality,
      pack: _pack,
      copy: _copy,
      categoryIcon: _categoryIcon,
      statusPill: _heroStatusPill(),
      statusBanner: _statusBannerDismissed ? null : _statusBanner(),
      kpis: EstablishmentHomeKpis(
        pending: data.kpis.pending,
        confirmedToday: data.kpis.confirmedToday,
        guestsMonth: data.kpis.guestsMonth,
        roomsMonth: data.kpis.roomsMonth,
        avgPartySize: data.kpis.avgPartySize,
        peakDay: data.kpis.peakDay,
        peakDayGuests: data.kpis.peakDayGuests,
      ),
      isLodging: _isLodging,
      roomStats: _isLodging ? roomStats : null,
      requestsSection: requestsSection,
      onOpenRooms: roomsTabIndex >= 0 ? () => _selectTab(roomsTabIndex) : null,
      onOpenInsights:
          insightsTabIndex >= 0 ? () => _selectTab(insightsTabIndex) : null,
    );
  }

  Widget _heroStatusPill() {
    final color = _isRejected
        ? AeDashTokens.danger
        : _isPending
            ? AeDashTokens.warning
            : AeDashTokens.success;
    final label = _isRejected
        ? 'Rejected'
        : _isPending
            ? 'Pending'
            : 'Active';
    return Tooltip(
      message: 'Account status: $label',
      child: AeStatusPill(label: label, color: color),
    );
  }

  Widget _roomsTab(_DashboardData data) {
    final slots = EstablishmentRoomGrid.buildSlots(
      roomCount: _roomCount,
      disabledRooms: _disabledRooms,
      stays: data.allStays,
      inventory: _roomInventory,
    );
    return LayoutBuilder(
      builder: (context, c) {
        final pad = _pagePad(c.maxWidth);
        return ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: EdgeInsets.only(bottom: pad + 12),
          children: [
            EstablishmentRoomsPanel(
              slots: slots,
              onToggleDisabled: (slot, disable) => _toggleRoomDisabled(
                slot: slot,
                disable: disable,
              ),
              onSaveRoomInfo: _saveRoomInfo,
              setupCard: _roomCountSection(allStays: data.allStays),
              flushHero: true,
              contentPadding: EdgeInsets.fromLTRB(
                pad,
                c.maxWidth < 600 ? 12 : 18,
                pad,
                0,
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _insightsTab(_DashboardData data) {
    return EstablishmentInsightsBoard(
      establishmentId: _uid,
      copy: _copy,
      isLodging: _isLodging,
      dss: data.dss,
      allStays: data.allStays,
      roomCount: _isLodging ? _roomCount : 0,
      roomInventory: _isLodging ? _roomInventory : const {},
    );
  }

  Widget _settingsTab(_DashboardData data) {
    final demo = data.allStays.where((s) => s.isDemo).length;
    return LayoutBuilder(
      builder: (context, c) {
        final pad = _pagePad(c.maxWidth);
        return ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: EdgeInsets.only(bottom: pad + 12),
          children: [
            EstablishmentSettingsPanel(
              establishmentName: _businessName,
              municipality: _municipality,
              municipalityId: _municipalityId,
              category: _category,
              roomCount: _isLodging ? _roomCount : 0,
              disabledRooms: _disabledRooms,
              demoStayCount: demo,
              realStayCount: data.allStays.length - demo,
              flushHero: true,
              contentPadding: EdgeInsets.fromLTRB(
                pad,
                c.maxWidth < 600 ? 12 : 18,
                pad,
                0,
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _qrProfileTab(_DashboardData data) {
    return _scrollBody(
      header: _qrSection(),
      children: [
        _mapPinSection(),
        const SizedBox(height: 18),
        _gallerySection(),
        if (_isLodging) ...[
          const SizedBox(height: 18),
          _lodgingHoursSection(),
        ],
      ],
    );
  }

  Widget _gallerySection() {
    return EstablishmentPhotosCard(
      urls: _galleryUrls,
      maxImages: EstablishmentGalleryService.maxImages,
      busy: _galleryBusy,
      onAdd: _addGalleryPhoto,
      onRemove: _removeGalleryPhoto,
    );
  }

  Widget _mapPinSection() {
    return EstablishmentMapPinCard(
      latitude: _latitude,
      longitude: _longitude,
      locating: _locating,
      saving: _savingLocation,
      onBusyChanged: (b) {
        if (mounted) setState(() => _locating = b);
      },
      onChanged: (pin) {
        _saveMapPin(
          latitude: pin.latitude,
          longitude: pin.longitude,
        );
      },
    );
  }

  Widget _lodgingHoursSection() {
    final cin = EstablishmentLodgingHours.tryParse(_checkInTime);
    final cout = EstablishmentLodgingHours.tryParse(_checkOutTime);
    return EstablishmentHoursCard(
      checkInLabel:
          cin == null ? null : EstablishmentLodgingHours.displayLabel(cin),
      checkOutLabel:
          cout == null ? null : EstablishmentLodgingHours.displayLabel(cout),
      saving: _savingHours,
      onPickCheckIn: _pickAndSaveCheckInTime,
      onPickCheckOut: _pickAndSaveCheckOutTime,
    );
  }

  Widget _statusPill({bool compact = false, bool onOrange = false}) {
    final pillLabel = _isRejected
        ? 'Rejected'
        : _isPending
            ? 'Pending'
            : 'Active';
    final pillBg = onOrange
        ? Colors.white.withValues(alpha: 0.2)
        : (_isRejected
            ? const Color(0xFFFEE2E2)
            : _isPending
                ? const Color(0xFFFFF7ED)
                : const Color(0xFFECFDF5));
    final pillFg = onOrange
        ? Colors.white
        : (_isRejected
            ? const Color(0xFF9F1239)
            : _isPending
                ? const Color(0xFF9A3412)
                : const Color(0xFF065F46));

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 10 : 12,
        vertical: compact ? 5 : 6,
      ),
      decoration: BoxDecoration(
        color: pillBg,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: onOrange
              ? Colors.white.withValues(alpha: 0.35)
              : pillFg.withValues(alpha: 0.25),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            _isRejected
                ? Icons.cancel_rounded
                : _isPending
                    ? Icons.schedule_rounded
                    : Icons.verified_rounded,
            size: 14,
            color: pillFg,
          ),
          const SizedBox(width: 5),
          Text(
            pillLabel,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w800,
              color: pillFg,
            ),
          ),
        ],
      ),
    );
  }

  Widget _statusBanner() {
    void dismiss() => setState(() => _statusBannerDismissed = true);
    if (_isPending) {
      return AeAlertBanner(
        title: 'Pending approval',
        message: 'Registration still pending LGU / Provincial approval — '
            'you can already print your QR and confirm ${_copy.opsNoun}s for testing.',
        icon: Icons.schedule_rounded,
        color: const Color(0xFFEA580C),
        background: const Color(0xFFFFF7ED),
        borderColor: const Color(0xFFFED7AA),
        onClose: dismiss,
      );
    }
    if (_isRejected) {
      return AeAlertBanner(
        title: 'Registration rejected',
        message: 'Contact your LGU tourism office for next steps.',
        icon: Icons.error_rounded,
        color: AeDashTokens.danger,
        background: const Color(0xFFFEF2F2),
        borderColor: const Color(0xFFFECACA),
        onClose: dismiss,
      );
    }
    final approvedParts = _copy.statusApproved.split('. ');
    final approvedDetail = approvedParts.length > 1
        ? approvedParts.sublist(1).join('. ')
        : _copy.statusApproved;
    return AeAlertBanner(
      title: 'Account approved!',
      message: 'Your account is verified. $approvedDetail',
      icon: Icons.check_circle_rounded,
      color: AeDashTokens.success,
      background: const Color(0xFFECFDF5),
      borderColor: const Color(0xFFD1FAE5),
      onClose: dismiss,
    );
  }

  Widget _qrSection() {
    return EstablishmentQrHero(
      flush: true,
      payload: _qrPayload,
      hint: _copy.qrHint,
      onDownloadPng: () => downloadEstablishmentQrPng(
        establishmentId: _uid,
        businessName: _businessName,
        municipalityId: _municipalityId,
      ),
      onDownloadPdf: () => downloadEstablishmentQrPdf(
        establishmentId: _uid,
        businessName: _businessName,
        municipalityId: _municipalityId,
      ),
    );
  }

  Widget _roomCountSection({
    required List<EstablishmentStayRequest> allStays,
  }) {
    return EstablishmentRoomCountCard(
      controller: _roomCountCtrl,
      saving: _savingRooms,
      onSave: () => _saveRoomCount(allStays: allStays),
    );
  }

  Future<void> _checkOutStayUnguarded(EstablishmentStayRequest stay) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Check out guest?'),
        content: Text(
          'Mark ${stay.touristName.isNotEmpty ? stay.touristName : 'this guest'} '
          'as checked out and free their room(s)? '
          'They will be asked to leave a stay review.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(
              backgroundColor: AppTheme.brandOrange,
            ),
            child: const Text('Check out'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    try {
      await EstablishmentStayService.checkOutStay(stayId: stay.id);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Guest checked out. Rooms are free.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Check-out failed: $e'),
          backgroundColor: Colors.red.shade700,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

}

class _DashboardData {
  const _DashboardData({
    required this.allStays,
    required this.pending,
    required this.kpis,
    required this.dss,
    required this.streamError,
    required this.streamLoading,
  });

  final List<EstablishmentStayRequest> allStays;
  final List<EstablishmentStayRequest> pending;
  final _EstablishmentKpis kpis;
  final EstablishmentDssSnapshot dss;
  final Object? streamError;
  final bool streamLoading;
}

enum _AeTab { home, rooms, insights, reviews, qr, settings }

class _EstablishmentKpis {
  const _EstablishmentKpis({
    required this.pending,
    required this.confirmedToday,
    required this.guestsMonth,
    required this.roomsMonth,
    required this.avgPartySize,
    required this.peakDay,
    required this.peakDayGuests,
  });

  final int pending;
  final int confirmedToday;
  final int guestsMonth;
  final int roomsMonth;
  final double avgPartySize;
  final int peakDay;
  final int peakDayGuests;
}


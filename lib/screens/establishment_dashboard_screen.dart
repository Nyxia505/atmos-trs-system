import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';

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
import 'package:atmos_trs_system/widgets/atmos_square_logo.dart';
import 'package:atmos_trs_system/widgets/establishment_dash_tokens.dart';
import 'package:atmos_trs_system/widgets/establishment_desk_confirm_dialog.dart';
import 'package:atmos_trs_system/widgets/establishment_home_board.dart';
import 'package:atmos_trs_system/widgets/establishment_insights_board.dart';
import 'package:atmos_trs_system/widgets/establishment_location_capture.dart';
import 'package:atmos_trs_system/widgets/establishment_rooms_panel.dart';

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

  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

  EstablishmentPack get _pack => EstablishmentCapability.packFor(_category);
  EstablishmentPackCopy get _copy =>
      EstablishmentCapability.copyFor(_category);
  bool get _isLodging => _pack == EstablishmentPack.lodging;
  IconData get _categoryIcon => EstablishmentCapability.iconFor(_category);

  List<_AeTab> get _tabs => _isLodging
      ? const [_AeTab.home, _AeTab.rooms, _AeTab.insights, _AeTab.qr]
      : const [_AeTab.home, _AeTab.insights, _AeTab.qr];

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
      Map<String, dynamic> user = const <String, dynamic>{};
      try {
        final userDoc = await db.collection('users').doc(uid).get();
        user = userDoc.data() ?? const <String, dynamic>{};
      } catch (e) {
        debugPrint('[AE Dashboard] users/$uid read: $e');
      }
      final estDoc = await db
          .collection(EstablishmentRegistrationService.establishmentsCollection)
          .doc(uid)
          .get();
      final est = estDoc.data() ?? const <String, dynamic>{};
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
      final maxTab = lodging ? 3 : 2;
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

  Future<void> _openConfirmDialog(
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

  Future<void> _reject(EstablishmentStayRequest stay) async {
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
      stream: _uid.isEmpty
          ? const Stream.empty()
          : EstablishmentStayService.watchForEstablishment(_uid),
      builder: (context, snap) {
        final all = snap.data ?? const <EstablishmentStayRequest>[];
        final pending = all.where((s) => s.isPending).toList();
        final recentConfirmed = all
            .where((s) => s.countsForDae)
            .take(12)
            .toList();
        final kpis = _computeKpis(all);
        final dss = EstablishmentDssAggregates.build(all);
        final streamError = snap.hasError ? snap.error : null;
        final streamLoading = _uid.isNotEmpty && !snap.hasData && !snap.hasError;

        final dashboardData = _DashboardData(
          allStays: all,
          pending: pending,
          recentConfirmed: recentConfirmed,
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
          _AeTab.qr => 'QR & profile',
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
                    '${_category.isNotEmpty ? ' ? $_category' : ''}'
                    '${pendingCount > 0 && _currentTab != _AeTab.home ? ' ? $pendingCount pending' : ''}',
                    style: AeDashTokens.body(size: 12),
                  ),
                ],
              ),
            ),
            _statusPill(compact: true),
            const SizedBox(width: 4),
            IconButton(
              tooltip: 'Log out',
              onPressed: _logout,
              icon: const Icon(Icons.logout_rounded, color: AeDashTokens.muted),
            ),
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
    final bottomInset = MediaQuery.paddingOf(context).bottom;
    final width = expanded
        ? (isDrawer ? 280.0 : AeDashTokens.sidebarExpanded)
        : AeDashTokens.sidebarCollapsed;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      width: width,
      decoration: const BoxDecoration(
        color: AeDashTokens.sidebar,
        border: Border(
          right: BorderSide(color: Color(0xFF1E293B)),
        ),
      ),
      child: SafeArea(
        right: false,
        child: Column(
          children: [
            if (expanded)
              _sidebarProfileStrip(showCollapse: !isDrawer)
            else
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
                child: IconButton(
                  tooltip: 'Expand sidebar',
                  onPressed: () => setState(() => _sidebarExpanded = true),
                  icon: const Icon(Icons.menu_rounded, color: Colors.white70),
                ),
              ),
            Expanded(
              child: _sidebarNav(
                expanded: expanded,
                pendingCount: pendingCount,
              ),
            ),
            _sidebarLogout(expanded: expanded),
            SizedBox(height: 12 + bottomInset),
          ],
        ),
      ),
    );
  }

  Widget _sidebarProfileStrip({required bool showCollapse}) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 8, 8),
      child: Row(
        children: [
          const AtmosSquareLogo(height: 40, width: 40, padding: EdgeInsets.all(4)),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _businessName,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  _municipality.isNotEmpty
                      ? _municipality
                      : _copy.packLabel,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.82),
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          if (showCollapse)
            IconButton(
              tooltip: 'Collapse sidebar',
              onPressed: () => setState(() => _sidebarExpanded = false),
              icon: const Icon(Icons.close_rounded, color: Colors.white, size: 20),
            ),
        ],
      ),
    );
  }

  Widget _sidebarNav({
    required bool expanded,
    required int pendingCount,
  }) {
    final items = [
      for (final t in _tabs)
        switch (t) {
          _AeTab.home => _NavItem(Icons.home_rounded, 'Home'),
          _AeTab.rooms => _NavItem(Icons.meeting_room_rounded, 'Rooms'),
          _AeTab.insights => _NavItem(Icons.insights_rounded, 'Insights'),
          _AeTab.qr => _NavItem(Icons.qr_code_2_rounded, 'QR & profile'),
        },
    ];

    return ListView(
      padding: EdgeInsets.symmetric(
        horizontal: expanded ? 12 : 8,
        vertical: 8,
      ),
      children: [
        for (var i = 0; i < items.length; i++)
          _sidebarNavTile(
            item: items[i],
            index: i,
            expanded: expanded,
            badgeCount: _tabs[i] == _AeTab.home ? pendingCount : 0,
          ),
      ],
    );
  }

  Widget _sidebarNavTile({
    required _NavItem item,
    required int index,
    required bool expanded,
    int badgeCount = 0,
  }) {
    final selected = _selectedIndex == index;
    final showInlineBadge = expanded && badgeCount > 0;
    final iconColor = selected ? AeDashTokens.accent : Colors.white70;
    final iconWidget = (!expanded && badgeCount > 0)
        ? Badge(
            label: Text('$badgeCount'),
            child: Icon(item.icon, color: iconColor, size: 22),
          )
        : Icon(item.icon, color: iconColor, size: 22);

    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Material(
        color: selected ? AeDashTokens.sidebarMuted : Colors.transparent,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          onTap: () => _selectTab(index),
          borderRadius: BorderRadius.circular(12),
          child: Container(
            decoration: selected
                ? const BoxDecoration(
                    border: Border(
                      left: BorderSide(color: AeDashTokens.accent, width: 3),
                    ),
                  )
                : null,
            padding: EdgeInsets.symmetric(
              horizontal: expanded ? 14 : 10,
              vertical: 11,
            ),
            child: Row(
              mainAxisAlignment:
                  expanded ? MainAxisAlignment.start : MainAxisAlignment.center,
              children: [
                iconWidget,
                if (expanded) ...[
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      item.label,
                      style: TextStyle(
                        color: selected ? Colors.white : Colors.white70,
                        fontWeight:
                            selected ? FontWeight.w700 : FontWeight.w500,
                        fontSize: 13.5,
                      ),
                    ),
                  ),
                  if (showInlineBadge)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: AeDashTokens.accent,
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        '$badgeCount',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _sidebarLogout({required bool expanded}) {
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: expanded ? 12 : 8),
      child: Material(
        color: Colors.white.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          onTap: _logout,
          borderRadius: BorderRadius.circular(14),
          child: Padding(
            padding: EdgeInsets.symmetric(
              horizontal: expanded ? 14 : 10,
              vertical: 12,
            ),
            child: Row(
              mainAxisAlignment:
                  expanded ? MainAxisAlignment.start : MainAxisAlignment.center,
              children: [
                const Icon(Icons.logout_rounded, color: Colors.white, size: 20),
                if (expanded) ...[
                  const SizedBox(width: 12),
                  const Text(
                    'Log out',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildMobileBottomNav({required int pendingCount}) {
    final tabs = _tabs;
    return NavigationBar(
      selectedIndex: _selectedIndex.clamp(0, tabs.length - 1),
      onDestinationSelected: _selectTab,
      indicatorColor: AeDashTokens.softOrange,
      backgroundColor: Colors.white,
      destinations: [
        for (final t in tabs)
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
            _AeTab.qr => const NavigationDestination(
                icon: Icon(Icons.qr_code_2_outlined),
                selectedIcon: Icon(Icons.qr_code_2_rounded),
                label: 'QR',
              ),
          },
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
      case _AeTab.qr:
        return _qrProfileTab(data);
      case _AeTab.home:
        return _homeTab(data);
    }
  }

  Widget _scrollBody({required List<Widget> children}) {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
      children: children,
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

    final pendingSection = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(_copy.queueTitle, style: AeDashTokens.section(size: 14)),
        const SizedBox(height: 2),
        Text(_copy.queueHint, style: AeDashTokens.body(size: 12)),
        const SizedBox(height: 10),
        if (data.pending.isEmpty)
          _emptyCard(_copy.queueEmpty)
        else
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 360),
            child: ListView(
              shrinkWrap: true,
              children: [
                for (final s in data.pending)
                  _pendingCard(s, allStays: data.allStays),
              ],
            ),
          ),
      ],
    );

    final recentSection = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(_copy.recentTitle, style: AeDashTokens.section(size: 14)),
        const SizedBox(height: 10),
        if (data.recentConfirmed.isEmpty)
          _emptyCard(_copy.recentEmpty)
        else
          _card(
            child: Column(
              children: [
                for (var i = 0; i < data.recentConfirmed.length; i++) ...[
                  if (i > 0)
                    const Divider(height: 1, color: AeDashTokens.border),
                  _recentTile(data.recentConfirmed[i]),
                ],
              ],
            ),
          ),
      ],
    );

    return EstablishmentHomeBoard(
      businessName: _businessName,
      category: _category,
      municipality: _municipality,
      pack: _pack,
      copy: _copy,
      categoryIcon: _categoryIcon,
      statusPill: _statusPill(),
      statusBanner: _statusBanner(),
      kpis: EstablishmentHomeKpis(
        pending: data.kpis.pending,
        confirmedToday: data.kpis.confirmedToday,
        guestsMonth: data.kpis.guestsMonth,
        roomsMonth: data.kpis.roomsMonth,
        avgPartySize: data.kpis.avgPartySize,
        peakDay: data.kpis.peakDay,
        peakDayGuests: data.kpis.peakDayGuests,
      ),
      dss: data.dss,
      isLodging: _isLodging,
      roomStats: _isLodging ? roomStats : null,
      pendingSection: pendingSection,
      recentSection: recentSection,
      onOpenRooms: roomsTabIndex >= 0 ? () => _selectTab(roomsTabIndex) : null,
    );
  }

  Widget _roomsTab(_DashboardData data) {
    final slots = EstablishmentRoomGrid.buildSlots(
      roomCount: _roomCount,
      disabledRooms: _disabledRooms,
      stays: data.allStays,
      inventory: _roomInventory,
    );
    return _scrollBody(
      children: [
        EstablishmentRoomsPanel(
          slots: slots,
          onToggleDisabled: (slot, disable) => _toggleRoomDisabled(
            slot: slot,
            disable: disable,
          ),
          onSaveRoomInfo: _saveRoomInfo,
        ),
      ],
    );
  }

  Widget _insightsTab(_DashboardData data) {
    final roomSlots = _isLodging
        ? EstablishmentRoomGrid.buildSlots(
            roomCount: _roomCount,
            disabledRooms: _disabledRooms,
            stays: data.allStays,
            inventory: _roomInventory,
          )
        : const <EstablishmentRoomSlot>[];
    final roomStats = EstablishmentRoomGrid.statsFor(roomSlots);

    return EstablishmentInsightsBoard(
      establishmentId: _uid,
      copy: _copy,
      isLodging: _isLodging,
      dss: data.dss,
      roomStats: _isLodging ? roomStats : null,
      allStays: data.allStays,
      roomCount: _isLodging ? _roomCount : 0,
      roomInventory: _isLodging ? _roomInventory : const {},
    );
  }

  Widget _qrProfileTab(_DashboardData data) {
    return _scrollBody(
      children: [
        _qrSection(),
        const SizedBox(height: 24),
        _mapPinSection(),
        const SizedBox(height: 24),
        _gallerySection(),
        if (_isLodging) ...[
          const SizedBox(height: 24),
          _lodgingHoursSection(),
          const SizedBox(height: 24),
          _roomCountSection(allStays: data.allStays),
        ] else if (_roomCount > 0) ...[
          const SizedBox(height: 16),
          _card(
            child: Text(
              'Stored room count on profile: $_roomCount '
              '(not used for ${_copy.packLabel.toLowerCase()} ops).',
              style: AeDashTokens.body(size: 13),
            ),
          ),
        ],
      ],
    );
  }

  Widget _gallerySection() {
    final canAdd = _galleryUrls.length < EstablishmentGalleryService.maxImages;
    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Profile photos',
            style: AeDashTokens.heading(size: 16),
          ),
          const SizedBox(height: 4),
          Text(
            'Shown when tourists open your pin on Explore. '
            'Up to ${EstablishmentGalleryService.maxImages} photos.',
            style: AeDashTokens.body(size: 13),
          ),
          const SizedBox(height: 14),
          if (_galleryUrls.isEmpty)
            Text(
              'No photos yet ? add your entrance, rooms, or amenities.',
              style: AeDashTokens.body(
                size: 13,
                color: AeDashTokens.subtitle,
              ),
            )
          else
            SizedBox(
              height: 108,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: _galleryUrls.length,
                separatorBuilder: (_, __) => const SizedBox(width: 10),
                itemBuilder: (context, i) {
                  final url = _galleryUrls[i];
                  return Stack(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: Image.network(
                          url,
                          width: 108,
                          height: 108,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => Container(
                            width: 108,
                            height: 108,
                            color: const Color(0xFFE2E8F0),
                            child: const Icon(Icons.broken_image_outlined),
                          ),
                        ),
                      ),
                      Positioned(
                        top: 4,
                        right: 4,
                        child: Material(
                          color: Colors.black.withValues(alpha: 0.55),
                          shape: const CircleBorder(),
                          child: InkWell(
                            customBorder: const CircleBorder(),
                            onTap:
                                _galleryBusy ? null : () => _removeGalleryPhoto(i),
                            child: const Padding(
                              padding: EdgeInsets.all(4),
                              child: Icon(
                                Icons.close_rounded,
                                size: 16,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ),
                      ),
                      if (i == 0)
                        Positioned(
                          left: 6,
                          bottom: 6,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: 0.6),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: const Text(
                              'Cover',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ),
                    ],
                  );
                },
              ),
            ),
          const SizedBox(height: 14),
          OutlinedButton.icon(
            onPressed: (!canAdd || _galleryBusy) ? null : _addGalleryPhoto,
            icon: _galleryBusy
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.add_photo_alternate_outlined, size: 20),
            label: Text(
              _galleryBusy
                  ? 'Uploading?'
                  : canAdd
                      ? 'Add photo'
                      : 'Photo limit reached',
            ),
          ),
        ],
      ),
    );
  }

  Widget _mapPinSection() {
    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Map pin',
            style: AeDashTokens.heading(size: 16),
          ),
          const SizedBox(height: 4),
          Text(
            'Tourists see your establishment on Explore after OPTACA approval. '
            'Stand at the entrance, then tap Get location.',
            style: AeDashTokens.body(size: 13),
          ),
          const SizedBox(height: 14),
          EstablishmentLocationCapture(
            latitude: _latitude,
            longitude: _longitude,
            busy: _locating,
            required: false,
            onBusyChanged: (b) {
              if (mounted) setState(() => _locating = b);
            },
            onChanged: (pin) {
              _saveMapPin(
                latitude: pin.latitude,
                longitude: pin.longitude,
              );
            },
          ),
          if (_savingLocation) ...[
            const SizedBox(height: 12),
            const LinearProgressIndicator(minHeight: 2),
          ],
        ],
      ),
    );
  }

  Widget _lodgingHoursSection() {
    final cin = EstablishmentLodgingHours.tryParse(_checkInTime);
    final cout = EstablishmentLodgingHours.tryParse(_checkOutTime);
    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Check-in / check-out times',
            style: AeDashTokens.heading(size: 16),
          ),
          const SizedBox(height: 4),
          Text(
            'Guests arriving before check-in may be charged an extra night. '
            'Checkout is due by the check-out time on their last day.',
            style: AeDashTokens.body(size: 13),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _savingHours ? null : _pickAndSaveCheckInTime,
                  icon: const Icon(Icons.login_rounded, size: 18),
                  label: Text(
                    cin == null
                        ? 'Check-in'
                        : 'In ${EstablishmentLodgingHours.displayLabel(cin)}',
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _savingHours ? null : _pickAndSaveCheckOutTime,
                  icon: const Icon(Icons.logout_rounded, size: 18),
                  label: Text(
                    cout == null
                        ? 'Check-out'
                        : 'Out ${EstablishmentLodgingHours.displayLabel(cout)}',
                  ),
                ),
              ),
            ],
          ),
          if (_savingHours) ...[
            const SizedBox(height: 12),
            const LinearProgressIndicator(minHeight: 2),
          ],
        ],
      ),
    );
  }

  Widget _card({required Widget child, EdgeInsetsGeometry? padding}) {
    return Container(
      width: double.infinity,
      padding: padding ?? const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AeDashTokens.card,
        borderRadius: BorderRadius.circular(AeDashTokens.radiusCard),
        border: Border.all(color: AeDashTokens.border),
        boxShadow: AeDashTokens.cardShadow,
      ),
      child: child,
    );
  }

  Widget _emptyCard(String message) {
    return _card(
      child: Text(
        message,
        style: AeDashTokens.body(),
      ),
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
      child: Text(
        pillLabel,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w800,
          color: pillFg,
        ),
      ),
    );
  }

  Widget _statusBanner() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _isPending
            ? const Color(0xFFFFF7ED)
            : _isRejected
                ? const Color(0xFFFEF2F2)
                : const Color(0xFFECFDF5),
        borderRadius: BorderRadius.circular(AeDashTokens.radiusLg),
        border: Border.all(
          color: _isPending
              ? const Color(0xFFFDBA74)
              : _isRejected
                  ? const Color(0xFFFECACA)
                  : const Color(0xFF6EE7B7),
        ),
      ),
      child: Text(
        _isPending
            ? 'Registration still pending LGU / Provincial approval ? '
                'you can already print your QR and confirm ${_copy.opsNoun}s for testing.'
            : _isRejected
                ? 'Registration was rejected. Contact your LGU tourism office for next steps.'
                : _copy.statusApproved,
        style: TextStyle(
          fontSize: 13.5,
          height: 1.4,
          fontWeight: FontWeight.w600,
          color: _isPending
              ? const Color(0xFF9A3412)
              : _isRejected
                  ? const Color(0xFF9F1239)
                  : const Color(0xFF065F46),
        ),
      ),
    );
  }

  Widget _qrSection() {
    final payload = _qrPayload;
    return _card(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Your establishment QR',
            style: AeDashTokens.heading(size: 16),
          ),
          const SizedBox(height: 4),
          Text(
            _copy.qrHint,
            style: AeDashTokens.body(size: 13),
          ),
          const SizedBox(height: 16),
          if (payload != null)
            Center(
              child: QrImageView(
                data: payload,
                size: 200,
                backgroundColor: Colors.white,
              ),
            ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              OutlinedButton.icon(
                onPressed: () => downloadEstablishmentQrPng(
                  establishmentId: _uid,
                  businessName: _businessName,
                  municipalityId: _municipalityId,
                ),
                icon: const Icon(Icons.image_outlined, size: 18),
                label: const Text('Download PNG'),
              ),
              OutlinedButton.icon(
                onPressed: () => downloadEstablishmentQrPdf(
                  establishmentId: _uid,
                  businessName: _businessName,
                  municipalityId: _municipalityId,
                ),
                icon: const Icon(Icons.picture_as_pdf_outlined, size: 18),
                label: const Text('Download PDF'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _roomCountSection({
    required List<EstablishmentStayRequest> allStays,
  }) {
    return _card(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Total rooms',
            style: AeDashTokens.heading(size: 16),
          ),
          const SizedBox(height: 4),
          Text(
            'Defines Room 1?N for the Rooms grid and occupancy. '
            'Changes require confirmation and cannot drop below occupied rooms.',
            style: AeDashTokens.body(size: 13),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _roomCountCtrl,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Room count',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              FilledButton(
                onPressed: _savingRooms
                    ? null
                    : () => _saveRoomCount(allStays: allStays),
                style: FilledButton.styleFrom(
                  backgroundColor: AppTheme.brandOrange,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                ),
                child: _savingRooms
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Text('Save'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _pendingCard(
    EstablishmentStayRequest s, {
    required List<EstablishmentStayRequest> allStays,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFFFFBEB),
        borderRadius: BorderRadius.circular(AeDashTokens.radiusLg),
        border: Border.all(color: const Color(0xFFFDE68A)),
        boxShadow: AeDashTokens.cardShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            s.touristName.isNotEmpty ? s.touristName : 'Tourist',
            style: AeDashTokens.sectionTitle(size: 15),
          ),
          const SizedBox(height: 4),
          Text(
            'Party ${s.partySize}'
            '${s.touristEmail.isNotEmpty ? ' ? ${s.touristEmail}' : ''}',
            style: AeDashTokens.body(size: 12.5),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: FilledButton(
                  onPressed: () =>
                      _openConfirmDialog(s, allStays: allStays),
                  style: FilledButton.styleFrom(
                    backgroundColor: AppTheme.brandOrange,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  child: const Text('Confirm'),
                ),
              ),
              const SizedBox(width: 8),
              OutlinedButton(
                onPressed: () => _reject(s),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AeDashTokens.danger,
                  side: const BorderSide(color: Color(0xFFFECACA)),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 14,
                  ),
                ),
                child: const Text('Reject'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _checkOutStay(EstablishmentStayRequest stay) async {
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

  Widget _recentTile(EstablishmentStayRequest s) {
    final inHouse = EstablishmentRoomGrid.isInHouse(s);
    final color = s.isCheckedOut
        ? const Color(0xFF475569)
        : s.isConfirmed
            ? const Color(0xFF065F46)
            : const Color(0xFF9F1239);
    final lodgingBits = _isLodging
        ? ' ? nights ${s.nightsStayed ?? '?'} ? rooms ${s.roomsOccupied ?? '?'}'
        : ' ? party ${s.partySize}';
    final statusLabel = s.isCheckedOut
        ? 'checked out'
        : (inHouse ? 'in house' : s.status);
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      title: Text(
        s.touristName.isNotEmpty ? s.touristName : 'Tourist',
        style: AeDashTokens.sectionTitle(size: 14),
      ),
      subtitle: Text(
        '$statusLabel$lodgingBits',
        style: TextStyle(color: color, fontSize: 12.5),
      ),
      trailing: inHouse
          ? TextButton(
              onPressed: () => _checkOutStay(s),
              child: const Text('Check out'),
            )
          : null,
    );
  }
}

class _DashboardData {
  const _DashboardData({
    required this.allStays,
    required this.pending,
    required this.recentConfirmed,
    required this.kpis,
    required this.dss,
    required this.streamError,
    required this.streamLoading,
  });

  final List<EstablishmentStayRequest> allStays;
  final List<EstablishmentStayRequest> pending;
  final List<EstablishmentStayRequest> recentConfirmed;
  final _EstablishmentKpis kpis;
  final EstablishmentDssSnapshot dss;
  final Object? streamError;
  final bool streamLoading;
}

enum _AeTab { home, rooms, insights, qr }

class _NavItem {
  const _NavItem(this.icon, this.label);
  final IconData icon;
  final String label;
}

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


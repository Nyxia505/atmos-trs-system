import 'package:atmos_trs_system/navigation/pending_checkin_navigation.dart';
import 'package:atmos_trs_system/screens/qr_profile_screen.dart';
import 'package:atmos_trs_system/services/pending_registration_cache.dart';
import 'package:atmos_trs_system/services/user_directory_service.dart';
import 'package:atmos_trs_system/utils/tourist_id_helper.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

/// After successful tourist signup OTP: show personal QR success, then home /
/// pending entry resume. Does not auto check-in.
Future<void> openTouristQrSuccessThenContinue(
  BuildContext context, {
  required String defaultRoute,
}) async {
  final user = FirebaseAuth.instance.currentUser;
  final uid = user?.uid ?? '';
  if (uid.isEmpty) {
    if (!context.mounted) return;
    await openQrDestinationIfPending(context);
    if (!context.mounted) return;
    Navigator.pushNamedAndRemoveUntil(context, defaultRoute, (r) => false);
    return;
  }

  var fullName = '';
  var location = '';
  var displayId = '';

  final pending = PendingRegistrationCache.current ??
      PendingRegistrationCache.forUid(uid);
  final local = pending?.localProfile;
  if (local != null) {
    fullName = [
      local.firstName,
      if (local.middleName.trim().isNotEmpty) local.middleName,
      local.lastName,
    ].where((s) => s.trim().isNotEmpty).join(' ').trim();
    displayId = local.touristId.trim();
    location = [
      if (local.city.trim().isNotEmpty) local.city.trim(),
      if (local.province.trim().isNotEmpty) local.province.trim(),
      if (local.country.trim().isNotEmpty) local.country.trim(),
    ].join(', ');
  }

  if (fullName.isEmpty || displayId.isEmpty) {
    try {
      final profile = await UserDirectoryService.getProfileByUid(uid);
      fullName = (profile?.fullName ?? fullName).trim();
    } catch (_) {}
    try {
      final doc = await FirebaseFirestore.instance
          .collection('tourists')
          .doc(uid)
          .get();
      final data = doc.data();
      if (data != null) {
        if (displayId.isEmpty) {
          displayId = TouristIdHelper.displayForTourist(data);
          if (!TouristIdHelper.isFormattedTouristId(displayId)) {
            displayId = (data['touristId'] ?? '').toString().trim();
          }
        }
        if (fullName.isEmpty) {
          fullName = (data['fullName'] ?? '').toString().trim();
        }
        if (location.isEmpty) {
          location = [
            if ((data['city'] ?? '').toString().trim().isNotEmpty)
              data['city'].toString().trim(),
            if ((data['province'] ?? '').toString().trim().isNotEmpty)
              data['province'].toString().trim(),
          ].join(', ');
        }
      }
    } catch (_) {}
  }

  if (fullName.isEmpty) {
    fullName = user?.displayName?.trim().isNotEmpty == true
        ? user!.displayName!.trim()
        : 'Tourist';
  }
  if (location.isEmpty) location = 'Misamis Occidental';

  if (!context.mounted) return;
  await Navigator.pushNamedAndRemoveUntil(
    context,
    '/tourist-qr-success',
    (r) => false,
    arguments: <String, dynamic>{
      'firebaseUid': uid,
      'displayTouristId': displayId,
      'fullName': fullName,
      'location': location,
      'continueRoute': defaultRoute,
    },
  );
}

/// Wrapper route body for [QrProfileScreen] after registration.
class TouristQrSuccessScreen extends StatelessWidget {
  const TouristQrSuccessScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final args = ModalRoute.of(context)?.settings.arguments;
    final map = args is Map ? Map<String, dynamic>.from(args) : const {};
    final uid = (map['firebaseUid'] ?? '').toString();
    final fullName = (map['fullName'] ?? 'Tourist').toString();
    final location = (map['location'] ?? 'Misamis Occidental').toString();
    final continueRoute = (map['continueRoute'] ?? '/dashboard').toString();

    final displayId = (map['displayTouristId'] ?? '').toString();

    return QrProfileScreen(
      touristId: uid,
      fullName: fullName,
      location: location,
      isAfterRegistration: true,
      continueRoute: continueRoute,
      displayTouristId: displayId,
    );
  }
}

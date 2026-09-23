import 'package:atmos_trs_system/models/tourist_spot.dart';
import 'package:atmos_trs_system/screens/lgu_debug_data_screen.dart';
import 'package:flutter/material.dart';

/// Opens the full-screen Debug data hub (charts + seed + full purge).
///
/// Kept for call-site compatibility with older `showSeedDialog` / `showClearDialog`
/// names — both now open the same hub.
class LguDebugDataDialogs {
  LguDebugDataDialogs._();

  static Future<void> openHub({
    required BuildContext context,
    required String municipalityId,
    required String municipalityName,
    List<TouristSpot> spots = const [],
    VoidCallback? onDone,
  }) {
    return LguDebugDataScreen.open(
      context: context,
      municipalityId: municipalityId,
      municipalityName: municipalityName,
      spots: spots,
      onDone: onDone,
    );
  }

  static Future<void> showSeedDialog({
    required BuildContext context,
    required String municipalityId,
    required String municipalityName,
    required List<TouristSpot> spots,
    required VoidCallback onDone,
  }) =>
      openHub(
        context: context,
        municipalityId: municipalityId,
        municipalityName: municipalityName,
        spots: spots,
        onDone: onDone,
      );

  static Future<void> showClearDialog({
    required BuildContext context,
    required String municipalityId,
    required String municipalityName,
    required VoidCallback onDone,
  }) =>
      openHub(
        context: context,
        municipalityId: municipalityId,
        municipalityName: municipalityName,
        onDone: onDone,
      );
}

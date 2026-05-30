import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';

/// Observes admin routes inside nested TripPlan [MaterialApp].
final RouteObserver<ModalRoute<void>> tourismAdminRouteObserver =
    RouteObserver<ModalRoute<void>>();

/// Ensures Firebase is ready before TripPlan auth screens.
Future<void> bootstrapAppFirestoreOnce() async {
  if (Firebase.apps.isEmpty) {
    await Firebase.initializeApp();
  }
}

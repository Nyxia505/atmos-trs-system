import 'dart:async';

import 'package:flutter/foundation.dart' show debugPrint, kIsWeb;
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'firebase_options.dart';
import 'theme/tourism_app_theme.dart';
import 'push_messaging.dart';
import 'services/admin_session_bootstrap.dart';
import 'services/firestore_platform_config.dart';
import 'services/tourism_session.dart';
import 'services/trip_post_finish_rating.dart';
import 'auth/login_screen.dart';
import 'auth/registration_screen.dart';
import 'home_screen.dart';
import 'tourist_plan/tourist_trip_planner_screen.dart';
import 'admin_dashboard_screen.dart';
import 'data.dart';
import 'widgets/admin_access_gate.dart';
import 'maps_platform_init.dart';

/// Shows [LoginScreen] until the user signs in, then [HomeScreen].
class TourismAuthGate extends StatefulWidget {
  const TourismAuthGate({super.key});

  @override
  State<TourismAuthGate> createState() => _TourismAuthGateState();
}

class _TourismAuthGateState extends State<TourismAuthGate> {
  String? _lastLoadedUid;
  Future<bool>? _adminHomeFuture;
  String? _adminHomeFutureUid;

  Future<bool> _shouldOpenAdminHome(String uid) async {
    return resolveOpenAdminDashboardAfterLogin();
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting &&
            FirebaseAuth.instance.currentUser == null) {
          return Scaffold(
            backgroundColor: AppColors.planPageBg,
            body: const Center(
              child: CircularProgressIndicator(
                color: AppColors.primary,
              ),
            ),
          );
        }
        final user = snapshot.data ?? FirebaseAuth.instance.currentUser;
        if (user == null) {
          _lastLoadedUid = null;
          _adminHomeFuture = null;
          _adminHomeFutureUid = null;
          return const LoginScreen();
        }
        if (_lastLoadedUid != user.uid) {
          _lastLoadedUid = user.uid;
          _adminHomeFutureUid = user.uid;
          if (isLikelyAdminSession()) {
            _adminHomeFuture = Future.value(true);
            WidgetsBinding.instance.addPostFrameCallback((_) {
              unawaited(bootstrapAppFirestoreOnce());
            });
          } else {
            _adminHomeFuture = _shouldOpenAdminHome(user.uid);
            WidgetsBinding.instance.addPostFrameCallback((_) {
              unawaited(bootstrapAppFirestoreOnce());
            });
          }
        }
        final adminFuture = _adminHomeFutureUid == user.uid
            ? _adminHomeFuture
            : (_adminHomeFuture = isLikelyAdminSession()
                ? Future.value(true)
                : _shouldOpenAdminHome(user.uid));
        return FutureBuilder<bool>(
          future: adminFuture,
          builder: (context, adminSnap) {
            if (adminSnap.connectionState != ConnectionState.done) {
              return Scaffold(
                backgroundColor: AppColors.planPageBg,
                body: const Center(
                  child: CircularProgressIndicator(color: AppColors.primary),
                ),
              );
            }
            if (adminSnap.data == true) {
              return const AdminAccessGate(child: AdminDashboardScreen());
            }
            return const HomeScreen();
          },
        );
      },
    );
  }
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initMapsForPlatform();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  await configureFirestoreForPlatform();
  // Paint UI first — awaiting Firestore bootstrap here caused a blank white screen on web.
  runApp(const TourismApp());
  unawaited(_bootstrapTourismDataAfterFirstFrame());
}

Future<void> _bootstrapTourismDataAfterFirstFrame() async {
  try {
    await bootstrapAppFirestoreOnce();
  } catch (e, st) {
    debugPrint('Firebase startup load failed: $e\n$st');
  }
  if (!kIsWeb) {
    FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);
    try {
      await initPushNotifications();
    } catch (e, st) {
      debugPrint('Push init failed: $e\n$st');
    }
  }
}

class TourismApp extends StatelessWidget {
  const TourismApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      navigatorKey: tourismRootNavigatorKey,
      navigatorObservers: [tourismAdminRouteObserver],
      title: 'Tourism Trip Planner',
      theme: TourismAppTheme.light,
      home: const TourismAuthGate(),
      routes: {
        TouristTripPlannerScreen.routeName: (_) =>
            const TouristTripPlannerScreen(),
        AdminDashboardScreen.routeName: (_) => const AdminAccessGate(
              child: AdminDashboardScreen(),
            ),
        LoginScreen.routeName: (_) => const LoginScreen(),
        RegistrationScreen.routeName: (_) => const RegistrationScreen(),
      },
    );
  }
}

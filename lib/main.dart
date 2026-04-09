import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart' show kIsWeb, debugPrint;
import 'package:flutter/material.dart';
import 'package:atmos_trs_system/services/fcm_background_handler.dart';
import 'package:atmos_trs_system/config/auth_config.dart';
import 'package:atmos_trs_system/config/session_storage.dart';
import 'package:atmos_trs_system/config/app_theme.dart';
import 'package:atmos_trs_system/utils/municipality_helper.dart';
import 'package:atmos_trs_system/services/dashboard_user_service.dart';
import 'package:atmos_trs_system/services/user_directory_service.dart';
import 'package:atmos_trs_system/navigation/role_router.dart';
import 'package:atmos_trs_system/screens/onboarding_screen.dart';
import 'package:atmos_trs_system/screens/landing_page.dart';
import 'package:atmos_trs_system/screens/login_screen.dart';
import 'package:atmos_trs_system/screens/signup_screen.dart';
import 'package:atmos_trs_system/screens/governor_dashboard.dart';
import 'package:atmos_trs_system/screens/tourism_dashboard.dart';
import 'package:atmos_trs_system/screens/verify_otp_screen.dart';
import 'package:atmos_trs_system/features/navigation/main_shell.dart';
import 'package:atmos_trs_system/screens/municipality_map_and_spots_screen.dart';
import 'package:atmos_trs_system/firebase_options.dart';
import 'package:atmos_trs_system/utils/firebase_client_blocked_message.dart';
import 'package:atmos_trs_system/widgets/session_inactivity_guard.dart';

/// Root navigator for session timeout and global navigation after sign-out.
final GlobalKey<NavigatorState> rootNavigatorKey = GlobalKey<NavigatorState>();

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Chrome / web must use the Web app from Firebase (appId contains ":web:").
  // Do not rely on a single generic switch for web — forces correct SDK options.
  final FirebaseOptions firebaseOptions = kIsWeb
      ? DefaultFirebaseOptions.web
      : DefaultFirebaseOptions.currentPlatform;

  if (kIsWeb) {
    assert(
      firebaseOptions.appId.contains(':web:'),
      'firebase_options.dart: Web FirebaseOptions.appId must include ":web:". '
      'Run: dart pub global activate flutterfire_cli && flutterfire configure',
    );
  }

  try {
    if (Firebase.apps.isEmpty) {
      await Firebase.initializeApp(options: firebaseOptions);
    }
    if (kIsWeb) {
      debugPrint(
        'Firebase initialized (Web): projectId=${firebaseOptions.projectId} '
        'appId=${firebaseOptions.appId} authDomain=${firebaseOptions.authDomain}',
      );
    }
    if (!kIsWeb) {
      FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);
    }
  } catch (e, st) {
    debugPrint('Firebase initialization error: $e\n$st');
    if (kIsWeb) {
      debugPrint(
        'If you see Auth errors about "android-client-application" on Web: '
        'Google Cloud Console → APIs & Services → Credentials → open the API key '
        'used above → Application restrictions must NOT be "Android apps only" '
        'for browser requests. Use "HTTP referrers" (localhost / 127.0.0.1) or '
        '"None" for local dev. Also confirm firebase_options.dart matches '
        'Firebase Console → Project settings → Your apps → Web app.',
      );
    } else {
      debugPrint(
        'If Android Auth says "client application … blocked": add SHA-1 in '
        'Firebase → Project settings → Android (com.atmos.trs), then match API key '
        'restrictions in Google Cloud → Credentials. ',
      );
      debugPrintFirebaseClientBlockedHint();
    }
  }

  // Cold start without session: onboarding video → Explore → landing (see routes).
  String initialRoute = '/onboarding';

  final auth = FirebaseAuth.instance;
  User? firebaseUser = auth.currentUser;

  if (firebaseUser != null) {
    try {
      await firebaseUser.reload();
      firebaseUser = auth.currentUser;
    } catch (e) {
      debugPrint('Error reloading Firebase user: $e');
    }
  }

  if (firebaseUser != null) {
    AuthConfig.currentUserUid = firebaseUser.uid;
    final email = firebaseUser.email ?? '';

    // Prefer canonical `users/{uid}` profile (role + isVerified for tourists).
    final profile = await UserDirectoryService.getProfileByUid(firebaseUser.uid) ??
        await UserDirectoryService.getProfileByEmail(email);

    if (profile != null) {
      initialRoute = await RoleRouter.persistSessionAndGetRoute(
        profile: profile,
        firebaseUid: firebaseUser.uid,
      );
      debugPrint('Startup route from users profile: $initialRoute');
    } else {
      // Legacy: dashboard profile without canonical `users/{uid}` doc (email-only query).
      final dash = await DashboardUserService.getProfileByEmail(email);
      if (dash != null && dash.role == 'governor') {
        await SessionStorage.saveSession(
          firebaseUser.uid,
          role: UserRole.governor,
          email: email,
        );
        initialRoute = '/governor-dashboard';
      } else if (dash != null && dash.role == 'tourism') {
        String municipalityId = getMunicipalityIdFromName(dash.municipality);
        if (municipalityId.isEmpty) {
          municipalityId =
              SessionStorage.getMunicipalityIdFromTourismEmail(email) ?? '';
        }
        await SessionStorage.saveSession(
          firebaseUser.uid,
          role: UserRole.tourism,
          email: email,
          municipalityId: municipalityId.isNotEmpty ? municipalityId : null,
        );
        initialRoute = '/tourism-dashboard';
      } else {
        final legacyMunId =
            SessionStorage.getMunicipalityIdFromTourismEmail(email);
        if (legacyMunId != null) {
          await SessionStorage.saveSession(
            firebaseUser.uid,
            role: UserRole.tourism,
            email: email,
            municipalityId: legacyMunId,
          );
          initialRoute = '/tourism-dashboard';
        } else {
          // Tourist data only in `tourists` (migration) or unverified new user.
          final verified =
              await UserDirectoryService.getTouristIsVerifiedFromTouristsDoc(
                    firebaseUser.uid,
                  ) ??
                  false;

          await SessionStorage.saveSession(
            firebaseUser.uid,
            role: UserRole.tourist,
            email: email,
          );

          if (!verified) {
            initialRoute = '/verify-otp';
          } else {
            initialRoute = '/dashboard';
          }
        }
      }
    }
  } else {
    final storedUid = await SessionStorage.getStoredUser();
    if (storedUid != null) {
      AuthConfig.currentUserUid = storedUid;
      final storedRole = await SessionStorage.getStoredRole();

      if (storedRole == UserRole.tourist) {
        await SessionStorage.clearSession();
        initialRoute = '/login';
      } else {
        initialRoute = SessionStorage.getDashboardRoute(storedRole);
      }
    }
  }

  runApp(MyApp(initialRoute: initialRoute));
}

class MyApp extends StatelessWidget {
  const MyApp({super.key, required this.initialRoute});

  final String initialRoute;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: rootNavigatorKey,
      title: 'ATMOS TRS — Asenso Tourismo Misamis Occidental Smart Tourist Registration System',
      theme: AppTheme.asensoTheme,
      themeMode: ThemeMode.light,
      debugShowCheckedModeBanner: false,
      initialRoute: initialRoute,
      builder: (context, child) {
        return SessionInactivityGuard(
          navigatorKey: rootNavigatorKey,
          child: child ??
              const ColoredBox(
                color: Color(0xFFFFF7ED),
                child: Center(
                  child: CircularProgressIndicator(),
                ),
              ),
        );
      },
      routes: {
        '/': (context) => const LandingPage(),
        '/onboarding': (context) => const OnboardingScreen(),
        '/landing': (context) => const LandingPage(),
        '/login': (context) => const LoginScreen(),
        '/signup': (context) => const SignupScreen(),
        '/verify-otp': (context) => const VerifyOtpScreen(),
        '/dashboard': (context) => const MainShell(),
        '/municipality-map': (context) {
          final args = ModalRoute.of(context)?.settings.arguments as Map<String, dynamic>?;
          final name = args?['municipalityIdOrName'] as String? ?? '';
          return MunicipalityMapAndSpotsScreen(municipalityIdOrName: name);
        },
        '/governor-dashboard': (context) => const GovernorDashboard(),
        '/tourism-dashboard': (context) => const TourismDashboard(),
      },
    );
  }
}

import 'dart:async' show unawaited;

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart' show kIsWeb, debugPrint;
import 'package:flutter/material.dart';
import 'package:atmos_trs_system/services/fcm_background_handler.dart';
import 'package:atmos_trs_system/config/atmos_font_preloader.dart';
import 'package:atmos_trs_system/config/app_theme.dart';
import 'package:atmos_trs_system/config/app_theme_controller.dart';
import 'package:atmos_trs_system/widgets/onboarding_hero_video.dart';
import 'package:atmos_trs_system/screens/landing_page.dart';
import 'package:atmos_trs_system/screens/login_screen.dart';
import 'package:atmos_trs_system/screens/forgot_password_screen.dart';
import 'package:atmos_trs_system/screens/signup_screen.dart';
import 'package:atmos_trs_system/screens/signup_account_type_screen.dart';
import 'package:atmos_trs_system/screens/establishment_signup_screen.dart';
import 'package:atmos_trs_system/screens/lgu_signup_screen.dart';
import 'package:atmos_trs_system/screens/establishment_dashboard_screen.dart';
import 'package:atmos_trs_system/screens/governor_dashboard.dart';
import 'package:atmos_trs_system/screens/tourism_dashboard.dart';
import 'package:atmos_trs_system/screens/provincial_tourism_dashboard.dart';
import 'package:atmos_trs_system/screens/verify_otp_screen.dart';
import 'package:atmos_trs_system/features/navigation/main_shell.dart';
import 'package:atmos_trs_system/screens/municipality_map_and_spots_screen.dart';
import 'package:atmos_trs_system/firebase_options.dart';
import 'package:atmos_trs_system/utils/firebase_client_blocked_message.dart';
import 'package:atmos_trs_system/services/push_notification_service.dart';
import 'package:atmos_trs_system/widgets/session_inactivity_guard.dart';
import 'package:atmos_trs_system/services/qr_launch_bootstrap.dart';
import 'package:atmos_trs_system/services/startup_route_resolver.dart';
import 'package:atmos_trs_system/screens/qr_scan_welcome_screen.dart';
import 'package:atmos_trs_system/screens/mobile_onboarding_screen.dart';

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
    if (kIsWeb) {
      await QrLaunchBootstrap.applyPendingFromLaunchUrl();
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

  await AppThemeController.instance.load();
  await preloadAtmosBrandFonts();

  final initialRoute = await StartupRouteResolver.resolveQuickInitialRoute();

  runApp(MyApp(initialRoute: initialRoute));
}

class MyApp extends StatefulWidget {
  const MyApp({super.key, required this.initialRoute});

  final String initialRoute;

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  final OnboardingHeroVideoData _onboardingHeroVideo =
      OnboardingHeroVideoData();

  @override
  void initState() {
    super.initState();
    if (!kIsWeb) {
      // Register device for announcement pop-ups for all logged-in roles.
      unawaited(registerTouristPushNotifications());
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(
        StartupRouteResolver.refineAndNavigateIfNeeded(
          widget.initialRoute,
          navigatorKey: rootNavigatorKey,
        ),
      );
    });
  }

  @override
  void dispose() {
    _onboardingHeroVideo.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: AppThemeController.instance,
      builder: (context, _) {
        return OnboardingHeroVideo(
          notifier: _onboardingHeroVideo,
          child: MaterialApp(
            navigatorKey: rootNavigatorKey,
            title: 'ATMOS-TRS',
            theme: AppTheme.asensoTheme,
            darkTheme: AppTheme.asensoDarkTheme,
            themeMode: AppThemeController.instance.isDarkMode
                ? ThemeMode.dark
                : ThemeMode.light,
            debugShowCheckedModeBanner: false,
            initialRoute: widget.initialRoute,
            builder: (context, child) {
              final loadingBg = Theme.of(context).scaffoldBackgroundColor;
              return SessionInactivityGuard(
                navigatorKey: rootNavigatorKey,
                child:
                    child ??
                    ColoredBox(
                      color: loadingBg,
                      child: const Center(child: CircularProgressIndicator()),
                    ),
              );
            },
            routes: {
          '/': (context) => kIsWeb ? const LandingPage() : const LoginScreen(),
          '/landing': (context) => const LandingPage(),
          '/qr-welcome': (context) => const QrScanWelcomeScreen(),
          '/mobile-onboarding': (context) => const MobileOnboardingScreen(),
          '/login': (context) => const LoginScreen(),
          '/forgot-password': (context) {
            final email = ModalRoute.of(context)?.settings.arguments as String?;
            return ForgotPasswordScreen(initialEmail: email);
          },
          '/signup': (context) => const SignupAccountTypeScreen(),
          '/signup-tourist': (context) => const SignupScreen(),
          '/signup-lgu': (context) => const LguSignupScreen(),
          '/signup-lgu-info': (context) => const LguSignupScreen(),
          '/signup-establishment': (context) =>
              const EstablishmentSignupScreen(),
          '/verify-otp': (context) => const VerifyOtpScreen(),
          '/establishment-dashboard': (context) =>
              const EstablishmentDashboardScreen(),
          '/dashboard': (context) {
            final args = ModalRoute.of(context)?.settings.arguments;
            final mapArgs = args is Map ? args : null;
            final initialIndex = mapArgs?['initialIndex'];
            return MainShell(
              initialIndex: initialIndex is int ? initialIndex : 0,
            );
          },
          '/municipality-map': (context) {
            final args =
                ModalRoute.of(context)?.settings.arguments
                    as Map<String, dynamic>?;
            final name = args?['municipalityIdOrName'] as String? ?? '';
            return MunicipalityMapAndSpotsScreen(municipalityIdOrName: name);
          },
          '/governor-dashboard': (context) => const GovernorDashboard(),
          '/lgu-dashboard': (context) => const LguDashboard(),
          '/tourism-dashboard': (context) => const LguDashboard(),
          '/provincial-tourism-dashboard': (context) =>
              const ProvincialTourismDashboard(),
            },
          ),
        );
      },
    );
  }
}

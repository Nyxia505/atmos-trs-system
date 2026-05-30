import 'dart:async' show unawaited;

import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import 'package:atmos_trs_system/widgets/onboarding_hero_video.dart';
import 'package:trip_plan/data.dart';
import 'package:trip_plan/main.dart' show TourismAuthGate;
import 'package:trip_plan/maps_platform_init.dart';
import 'package:trip_plan/services/tourism_session.dart';
import 'package:trip_plan/trip_plan_fonts.dart';
import 'package:trip_plan/trip_plan_routes.dart';
import 'package:trip_plan/widgets/trip_plan_scenic_background.dart';

/// Opens TripPlan auth (login) and, after sign-in, the TripPlan user home dashboard.
class TripPlanEntryScreen extends StatefulWidget {
  const TripPlanEntryScreen({super.key, this.sharedHeroController});

  /// Landing/onboarding hero player so TripPlan login keeps the same video background.
  final VideoPlayerController? sharedHeroController;

  @override
  State<TripPlanEntryScreen> createState() => _TripPlanEntryScreenState();
}

class _TripPlanEntryScreenState extends State<TripPlanEntryScreen> {
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    unawaited(_bootstrap());
  }

  Future<void> _bootstrap() async {
    await TripPlanFonts.ensureLoaded();
    unawaited(initMapsForPlatform());
    unawaited(bootstrapAppFirestoreOnce());
    if (mounted) setState(() => _ready = true);
  }

  ThemeData _tripPlanTheme() {
    return ThemeData(
      scaffoldBackgroundColor: AppColors.background,
      colorScheme: ColorScheme.fromSeed(seedColor: AppColors.primary),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Colors.white,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: Color(0xFFE0E0E0)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: Color(0xFFE0E0E0)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: AppColors.primary, width: 1.2),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final hero = widget.sharedHeroController ??
        OnboardingHeroVideo.read(context)?.controller;

    return TripPlanSharedHeroVideo(
      controller: hero,
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: _tripPlanTheme(),
        navigatorObservers: [tourismAdminRouteObserver],
        routes: tripPlanRoutes(),
        home: _ready
            ? const TourismAuthGate()
            : const Scaffold(
                backgroundColor: Colors.black,
                body: Stack(
                  fit: StackFit.expand,
                  children: [
                    TripPlanScenicBackground(),
                    Center(
                      child: CircularProgressIndicator(
                        color: AppColors.primary,
                      ),
                    ),
                  ],
                ),
              ),
      ),
    );
  }
}

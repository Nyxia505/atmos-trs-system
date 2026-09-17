import 'dart:async' show unawaited;

import 'package:atmos_trs_system/config/app_theme.dart';
import 'package:atmos_trs_system/navigation/tripplan_entry_screen.dart';
import 'package:atmos_trs_system/screens/vr_webview_screen.dart';
import 'package:atmos_trs_system/services/landing_intent_service.dart';
import 'package:atmos_trs_system/widgets/onboarding_hero_video.dart';
import 'package:atmos_trs_system/widgets/vr_download_app_prompt.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

enum PostAuthDestination { website, itinerary, vr }

/// Routes tourists to website / VR / Trip Plan after auth when a landing intent exists.
class LandingIntentNavigation {
  LandingIntentNavigation._();

  static Future<bool> tryContinueAfterTouristAuth(BuildContext context) async {
    final intent = await LandingIntentService.consume();
    if (intent == null) return false;
    if (!context.mounted) return true;
    await executeIntent(context, intent);
    return true;
  }

  static Future<void> executeIntent(
    BuildContext context,
    LandingIntent intent,
  ) async {
    if (intent.isVr) {
      if (VrDownloadAppPrompt.blocksVrOnWeb) {
        await VrDownloadAppPrompt.show(context);
        return;
      }
      final name = intent.municipalityName;
      final title = name != null && name.isNotEmpty
          ? 'VR Tour — $name'
          : 'VR Tour';
      unawaited(openVrTour(context, title: title));
      return;
    }
    if (intent.isItinerary) {
      final heroController = OnboardingHeroVideo.read(context)?.controller;
      await Navigator.of(context).push<void>(
        MaterialPageRoute<void>(
          builder: (context) => TripPlanEntryScreen(
            sharedHeroController: heroController,
          ),
        ),
      );
    }
  }

  /// Shows the post-signup / post-login chooser, then navigates to the chosen home.
  ///
  /// Always establishes a base route so the user is never stuck on auth screens.
  static Future<void> offerPostAuthDestinationAndNavigate(
    BuildContext context, {
    required String fallbackRoute,
    bool fromQrRegistration = false,
    String? welcomeMessage,
  }) async {
    final choice = await showPostAuthDestinationSheet(
      context,
      fromQrRegistration: fromQrRegistration,
    );
    if (!context.mounted) return;

    await navigateToDestination(
      context,
      choice: choice ?? PostAuthDestination.website,
      fallbackRoute: fallbackRoute,
      fromQrRegistration: fromQrRegistration,
      welcomeMessage: welcomeMessage,
    );
  }

  /// When no pending intent, optionally ask where to go before opening dashboard.
  /// Returns `true` if a feature route was opened (caller may skip default nav).
  static Future<bool> offerPostAuthDestination(BuildContext context) async {
    final choice = await showPostAuthDestinationSheet(context);
    if (choice == null || choice == PostAuthDestination.website) {
      return false;
    }
    if (!context.mounted) return false;

    if (choice == PostAuthDestination.vr) {
      if (VrDownloadAppPrompt.blocksVrOnWeb) {
        await VrDownloadAppPrompt.show(context);
        return false;
      }
      unawaited(openVrTour(context, title: 'VR Tour'));
      return true;
    }
    if (choice == PostAuthDestination.itinerary) {
      final heroController = OnboardingHeroVideo.read(context)?.controller;
      await Navigator.of(context).push<void>(
        MaterialPageRoute<void>(
          builder: (context) => TripPlanEntryScreen(
            sharedHeroController: heroController,
          ),
        ),
      );
      return true;
    }
    return false;
  }

  static Future<void> navigateToDestination(
    BuildContext context, {
    required PostAuthDestination choice,
    required String fallbackRoute,
    bool fromQrRegistration = false,
    String? welcomeMessage,
  }) async {
    Map<String, dynamic>? landingArgs;
    if (fromQrRegistration ||
        (welcomeMessage != null && welcomeMessage.trim().isNotEmpty)) {
      landingArgs = <String, dynamic>{
        if (fromQrRegistration) 'fromQrRegistration': true,
        if (welcomeMessage != null && welcomeMessage.trim().isNotEmpty)
          'welcomeMessage': welcomeMessage.trim(),
      };
    }

    switch (choice) {
      case PostAuthDestination.website:
        final route = kIsWeb ? '/landing' : fallbackRoute;
        Navigator.pushNamedAndRemoveUntil(
          context,
          route,
          (r) => false,
          arguments: route == '/landing' ? landingArgs : null,
        );
        return;

      case PostAuthDestination.itinerary:
        Navigator.pushNamedAndRemoveUntil(
          context,
          fallbackRoute,
          (r) => false,
        );
        if (!context.mounted) return;
        final heroController = OnboardingHeroVideo.read(context)?.controller;
        await Navigator.of(context).push<void>(
          MaterialPageRoute<void>(
            builder: (context) => TripPlanEntryScreen(
              sharedHeroController: heroController,
            ),
          ),
        );
        return;

      case PostAuthDestination.vr:
        if (VrDownloadAppPrompt.blocksVrOnWeb) {
          await VrDownloadAppPrompt.show(context);
          if (!context.mounted) return;
          // Stay on website after the download prompt — VR is app-only.
          Navigator.pushNamedAndRemoveUntil(
            context,
            '/landing',
            (r) => false,
            arguments: landingArgs,
          );
          return;
        }
        Navigator.pushNamedAndRemoveUntil(
          context,
          fallbackRoute,
          (r) => false,
        );
        if (!context.mounted) return;
        unawaited(openVrTour(context, title: 'VR Tour'));
        return;
    }
  }

  static Future<PostAuthDestination?> showPostAuthDestinationSheet(
    BuildContext context, {
    bool fromQrRegistration = false,
  }) {
    final accent = AppTheme.primary;
    final title = fromQrRegistration
        ? 'You\'re checked in! What next?'
        : 'Welcome! What would you like to do?';
    final subtitle = fromQrRegistration
        ? (kIsWeb
            ? 'Try VR Tour or Trip Planner. On the website, VR needs the ATMOS app on your phone.'
            : 'Open VR Tour, plan your trip, or continue in the app.')
        : (kIsWeb
            ? 'Continue on the website, get the ATMOS app for VR, or plan your trip.'
            : 'Continue in the app, jump into VR, or plan your itinerary.');

    return showModalBottomSheet<PostAuthDestination>(
      context: context,
      isScrollControlled: true,
      isDismissible: true,
      enableDrag: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.grey.shade300,
                      borderRadius: BorderRadius.circular(99),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  title,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  subtitle,
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.grey.shade600, height: 1.4),
                ),
                const SizedBox(height: 20),
                _PostAuthTile(
                  icon: Icons.vrpano_rounded,
                  title: 'VR Tour',
                  subtitle: kIsWeb
                      ? 'Unlocks on phone — get the ATMOS app'
                      : 'Preview destinations in immersive 360°',
                  accent: accent,
                  onTap: () => Navigator.pop(ctx, PostAuthDestination.vr),
                ),
                const SizedBox(height: 10),
                _PostAuthTile(
                  icon: Icons.map_rounded,
                  title: 'Trip Planner',
                  subtitle: 'Build a trip across Misamis Occidental',
                  accent: accent,
                  onTap: () =>
                      Navigator.pop(ctx, PostAuthDestination.itinerary),
                ),
                const SizedBox(height: 10),
                _PostAuthTile(
                  icon: kIsWeb ? Icons.language_rounded : Icons.dashboard_rounded,
                  title: kIsWeb ? 'Continue on website' : 'Continue in the app',
                  subtitle: kIsWeb
                      ? 'Browse destinations and tourism info in your browser'
                      : 'Go to your home, visits, and digital tourist ID',
                  accent: accent,
                  onTap: () =>
                      Navigator.pop(ctx, PostAuthDestination.website),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _PostAuthTile extends StatelessWidget {
  const _PostAuthTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.accent,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final Color accent;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Ink(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: Colors.grey.shade200),
          ),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: accent.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(icon, color: accent, size: 22),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 15,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey.shade600,
                          height: 1.3,
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(Icons.chevron_right_rounded, color: Colors.grey.shade400),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Builds login route args from a stored landing intent, if any.
Future<Map<String, dynamic>?> loginArgsFromPendingIntent() async {
  final pending = await LandingIntentService.peek();
  if (pending == null) return null;
  return LandingIntentService.loginArgsFromPending(pending);
}

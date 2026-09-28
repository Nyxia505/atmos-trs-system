import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:atmos_trs_system/config/auth_config.dart';
import 'package:atmos_trs_system/services/app_tutorial_storage.dart';
import 'package:atmos_trs_system/widgets/app_tutorial/coach_mark_overlay.dart';

/// Widgets highlighted by the tourist first-run tour. One instance per
/// [MainShell] so two shells mounted during a route transition never share
/// a [GlobalKey].
class TouristTutorialKeys {
  final askTala = GlobalKey(debugLabel: 'tour_ask_tala');
  final statsRow = GlobalKey(debugLabel: 'tour_stats_row');
  final discover = GlobalKey(debugLabel: 'tour_discover');

  /// VR section on the spot page the tour opens from Discover.
  final vrSection = GlobalKey(debugLabel: 'tour_vr_section');

  /// Registered by Home: slides the Discover carousel to a spot with VR.
  VoidCallback? showVrCard;

  /// Registered by Home: opens a Discover spot that has a VR tour, with
  /// [vrSection] attached to its VR block.
  VoidCallback? openVrSpot;

  /// One key per nav tab (Home, Explore, Scan, Notification, Account).
  /// Bottom nav and sidebar are never mounted together, so they share these.
  final navItems = List<GlobalKey>.generate(
    5,
    (i) => GlobalKey(debugLabel: 'tour_nav_$i'),
  );
}

/// Exposes the owning shell's [TouristTutorialKeys] to tab pages.
class TouristTutorialScope extends InheritedWidget {
  const TouristTutorialScope({
    super.key,
    required this.keys,
    required super.child,
  });

  final TouristTutorialKeys keys;

  static TouristTutorialKeys? maybeOf(BuildContext context) => context
      .getInheritedWidgetOfExactType<TouristTutorialScope>()
      ?.keys;

  @override
  bool updateShouldNotify(TouristTutorialScope oldWidget) =>
      keys != oldWidget.keys;
}

class TouristTutorial {
  TouristTutorial._();

  static String? _uid() =>
      AuthConfig.currentUserUid ?? FirebaseAuth.instance.currentUser?.uid;

  /// Starts the tour once per account on this device.
  static Future<void> maybeStart(
    BuildContext context,
    TouristTutorialKeys keys,
  ) async {
    final uid = _uid();
    if (await AppTutorialStorage.isDone(AppTutorialStorage.touristTour, uid)) {
      return;
    }
    if (!context.mounted || CoachMarkOverlay.isShowing) return;
    start(context, keys);
  }

  static void start(BuildContext context, TouristTutorialKeys keys) {
    final uid = _uid();
    void markDone() =>
        AppTutorialStorage.markDone(AppTutorialStorage.touristTour, uid);
    CoachMarkOverlay.show(
      context,
      steps: _steps(keys),
      onFinish: markDone,
      onSkip: markDone,
    );
  }

  static List<CoachStep> _steps(TouristTutorialKeys keys) {
    final nav = keys.navItems;
    return [
      const CoachStep(
        title: 'Welcome to ATMOS!',
        body: 'Take a quick tour to learn what to tap and where to find '
            'things in Misamis Occidental, including VR tours.',
        primaryLabel: 'Start tour',
        icon: Icons.waving_hand_rounded,
      ),
      CoachStep(
        target: keys.askTala,
        title: 'Ask Tala',
        body: 'Have a question about tourist spots, entrance fees, or '
            'directions? Tap here to chat with Tala.',
        icon: Icons.help_outline_rounded,
      ),
      CoachStep(
        target: keys.statsRow,
        title: 'Your travel progress',
        body: 'Visited shows your check-ins, Badges are rewards you earn, and '
            'Stays holds your hotel stay receipts.',
        icon: Icons.emoji_events_rounded,
      ),
      CoachStep(
        target: keys.discover,
        title: 'Find VR Tours here',
        body: 'Want to see a place in 360° before you go? VR tours live in '
            'these Discover cards. Tap the card to open the spot.',
        requireTap: true,
        onShow: () => keys.showVrCard?.call(),
        onAdvance: () => keys.openVrSpot?.call(),
      ),
      CoachStep(
        target: keys.vrSection,
        title: 'Start the VR Tour',
        body: 'On a spot page, scroll to Virtual tour and tap Start VR Tour to '
            'look around in 360°. Swipe the Discover cards or tap See all to '
            'find more spots with VR.',
        icon: Icons.vrpano_rounded,
        waitForTarget: const Duration(milliseconds: 2500),
        onAdvance: () {
          final ctx = keys.vrSection.currentContext;
          if (ctx != null) Navigator.of(ctx).maybePop();
        },
      ),
      CoachStep(
        target: nav[1],
        title: 'Explore',
        body: 'Browse municipalities, the map, and tourist spots to plan '
            'your trip.',
        icon: Icons.explore_rounded,
      ),
      CoachStep(
        target: nav[2],
        title: 'Scan to check in',
        body: 'When you arrive at a tourist spot or your hotel, tap Scan and '
            'point your camera at their QR code. Try it: tap Scan now.',
        requireTap: true,
        padding: 4,
      ),
      CoachStep(
        target: nav[3],
        title: 'Notifications',
        body: 'Announcements, check-in results, and hotel stay confirmations '
            'show up here.',
        icon: Icons.notifications_rounded,
      ),
      CoachStep(
        target: nav[4],
        title: 'Your account',
        body: 'Edit your profile and settings here. You can replay this tour '
            'anytime from Settings > App tour.',
        icon: Icons.person_rounded,
      ),
    ];
  }
}

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'dart:async' show unawaited;
import 'package:atmos_trs_system/config/app_theme.dart';
import 'package:atmos_trs_system/config/app_theme_controller.dart';
import 'package:atmos_trs_system/config/auth_config.dart';
import 'package:atmos_trs_system/services/announcement_notification_sync.dart';
import 'package:atmos_trs_system/services/faq_chat_store.dart';
import 'package:atmos_trs_system/config/user_profile_storage.dart';
import 'package:atmos_trs_system/services/welcome_notification_service.dart';
import 'package:atmos_trs_system/services/notification_badge_notifier.dart';
import 'package:atmos_trs_system/services/push_notification_service.dart';
import 'package:atmos_trs_system/services/tourist_activity_firestore_sync.dart';
import 'package:atmos_trs_system/services/user_activity_service.dart'
    show UserActivityService;
import 'package:atmos_trs_system/features/home/home_screen.dart';
import 'package:atmos_trs_system/features/explore/explore_screen.dart';
import 'package:atmos_trs_system/features/navigation/placeholder_pages.dart';
import 'package:atmos_trs_system/features/navigation/bottom_nav.dart';
import 'package:atmos_trs_system/features/navigation/tourist_web_layout.dart';
import 'package:atmos_trs_system/widgets/theme_reactive_scope.dart';
import 'package:atmos_trs_system/screens/event_detail_screen.dart';

/// Responsive shell: Home, Explore, Scan (center elevated), Notification, Account.
/// Uses IndexedStack so each tab keeps state.
class MainShell extends StatefulWidget {
  const MainShell({super.key, this.initialIndex = 0});

  final int initialIndex;

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> with WidgetsBindingObserver {
  late int _currentIndex;
  final _badge = NotificationBadgeNotifier.instance;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _currentIndex = widget.initialIndex;
    _badge.addListener(_onBadgeChanged);
    if (!kIsWeb) {
      registerTouristPushNotifications();
    }
    final uid =
        AuthConfig.currentUserUid ?? FirebaseAuth.instance.currentUser?.uid;
    if (uid != null && uid.isNotEmpty) {
      UserActivityService.bindToUser(uid);
      TouristActivityFirestoreSync.resetMergeCache();
      TouristActivityFirestoreSync.mergeFromCloud(uid);
      AnnouncementNotificationSync.syncPublishedAnnouncementsToLocal(
        userId: uid,
      );
      unawaited(FaqChatStore.instance.bindUser(uid));
      unawaited(
        WelcomeNotificationService.ensureForUser(
          uid: uid,
          firstName: UserProfileStorage.cachedProfile?.firstName,
        ),
      );
    }
    _badge.refresh(userId: uid);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) PendingEventOpen.consumeIfAny(context);
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && mounted) {
      PendingEventOpen.consumeIfAny(context);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _badge.removeListener(_onBadgeChanged);
    super.dispose();
  }

  void _onBadgeChanged() {
    if (mounted) setState(() {});
  }

  List<Widget> _buildPages() => [
        const ThemeReactiveScope(child: HomeScreen()),
        const ThemeReactiveScope(child: ExploreScreen()),
        const ThemeReactiveScope(child: ScanTabPage()),
        const ThemeReactiveScope(child: AlertsTabPage()),
        const ThemeReactiveScope(child: ProfileTabPage()),
      ];

  void _onNavTap(int index) {
    setState(() => _currentIndex = index);
    if (index == 3) {
      _badge.refresh();
    }
  }

  Widget _tabBody(List<Widget> pages) {
    // On web, IndexedStack keeps Google Maps HtmlElementViews in the DOM and
    // they steal clicks from the bottom nav. Mount only the active tab instead.
    if (kIsWeb) {
      return pages[_currentIndex];
    }
    return IndexedStack(index: _currentIndex, children: pages);
  }

  Widget _buildBottomNav() {
    return BottomNav(
      currentIndex: _currentIndex,
      unreadNotificationCount: _badge.count,
      onTap: _onNavTap,
    );
  }

  Widget _buildMobileScaffold(List<Widget> pages, {bool includeBottomNav = true}) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: _tabBody(pages),
      bottomNavigationBar: includeBottomNav ? _buildBottomNav() : null,
    );
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    // Tourist web always stays phone-sized; native apps/tablets get sidebar at ≥768px.
    final isMobile = kIsWeb || size.width < 768;

    return ListenableBuilder(
      listenable: AppThemeController.instance,
      builder: (context, _) {
        final pages = _buildPages();
        if (isMobile) {
          if (kIsWeb) {
            // Bottom nav outside nested Navigator so taps always work on web.
            return TouristWebMobileFrame(
              bottomBar: _buildBottomNav(),
              child: _buildMobileScaffold(pages, includeBottomNav: false),
            );
          }
          return _buildMobileScaffold(pages);
        }

        return Scaffold(
          backgroundColor: Theme.of(context).scaffoldBackgroundColor,
          body: Row(
            children: [
              _SidebarNav(
                currentIndex: _currentIndex,
                unreadNotificationCount: _badge.count,
                onTap: _onNavTap,
              ),
              Expanded(
                child: ColoredBox(
                  color: Colors.white,
                  child: _tabBody(pages),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _SidebarNav extends StatelessWidget {
  const _SidebarNav({
    required this.currentIndex,
    required this.onTap,
    this.unreadNotificationCount = 0,
  });

  final int currentIndex;
  final ValueChanged<int> onTap;
  final int unreadNotificationCount;

  @override
  Widget build(BuildContext context) {
    final items = kBottomNavItems;
    return Container(
      width: 80,
      decoration: BoxDecoration(
        color: AppTheme.cardBackground,
        border: Border(right: BorderSide(color: Colors.grey.shade300)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 8,
            offset: const Offset(2, 0),
          ),
        ],
      ),
      child: SafeArea(
        child: Column(
          children: [
            const SizedBox(height: 16),
            // Simple circular accent at top for brand / app icon placeholder.
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: AppTheme.primary.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(
                Icons.travel_explore_rounded,
                color: AppTheme.primary,
                size: 24,
              ),
            ),
            const SizedBox(height: 24),
            Expanded(
              child: ListView.separated(
                itemCount: items.length,
                separatorBuilder: (_, __) => const SizedBox(height: 8),
                itemBuilder: (context, index) {
                  final item = items[index];
                  final isSelected = index == currentIndex;
                  return _SidebarItem(
                    icon: item.$1,
                    label: item.$2,
                    isSelected: isSelected,
                    badgeCount: index == 3 ? unreadNotificationCount : 0,
                    onTap: () => onTap(index),
                  );
                },
              ),
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }
}

class _SidebarItem extends StatelessWidget {
  const _SidebarItem({
    required this.icon,
    required this.label,
    required this.isSelected,
    required this.badgeCount,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool isSelected;
  final int badgeCount;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = isSelected ? AppTheme.primary : AppTheme.unselectedMuted;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 8),
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: isSelected
              ? AppTheme.primary.withValues(alpha: 0.08)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            badgeCount > 0
                ? Badge(
                    label: Text(
                      badgeCount > 99 ? '99+' : '$badgeCount',
                      style: const TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    backgroundColor: const Color(0xFFDC2626),
                    child: Icon(icon, color: color, size: 24),
                  )
                : Icon(icon, color: color, size: 24),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

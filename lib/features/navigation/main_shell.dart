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
import 'package:atmos_trs_system/widgets/theme_reactive_scope.dart';

/// Responsive shell: Home, Explore, Scan (center elevated), Notification, Account.
/// Uses IndexedStack so each tab keeps state.
class MainShell extends StatefulWidget {
  const MainShell({super.key, this.initialIndex = 0});

  final int initialIndex;

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  late int _currentIndex;
  final _badge = NotificationBadgeNotifier.instance;
  @override
  void initState() {
    super.initState();
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
  }

  @override
  void dispose() {
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

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final isMobile = size.width < 768;

    return ListenableBuilder(
      listenable: AppThemeController.instance,
      builder: (context, _) {
        final pages = _buildPages();
        if (isMobile) {
          return Scaffold(
            backgroundColor: Colors.white,
            body: IndexedStack(index: _currentIndex, children: pages),
            bottomNavigationBar: BottomNav(
              currentIndex: _currentIndex,
              unreadNotificationCount: _badge.count,
              onTap: (index) {
                setState(() => _currentIndex = index);
                if (index == 3) {
                  _badge.refresh();
                }
              },
            ),
          );
        }

        return Scaffold(
          backgroundColor: Colors.white,
          body: Row(
            children: [
              _SidebarNav(
                currentIndex: _currentIndex,
                unreadNotificationCount: _badge.count,
                onTap: (index) {
                  setState(() => _currentIndex = index);
                  if (index == 3) _badge.refresh();
                },
              ),
              Expanded(
                child: ColoredBox(
                  color: Colors.white,
                  child: IndexedStack(index: _currentIndex, children: pages),
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

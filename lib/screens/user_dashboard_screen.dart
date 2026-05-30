import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'dart:async';
import 'dart:convert';
import 'package:atmos_trs_system/config/auth_config.dart';
import 'package:atmos_trs_system/config/session_storage.dart';
import 'package:atmos_trs_system/config/user_profile_storage.dart';
import 'package:atmos_trs_system/services/profile_photo_hydration.dart';
import 'package:atmos_trs_system/services/tourist_profile_hydration.dart';
import 'package:atmos_trs_system/features/home/home_screen.dart';
import 'package:atmos_trs_system/features/explore/explore_screen.dart';
import 'package:atmos_trs_system/screens/qr_profile_screen.dart';
import 'package:atmos_trs_system/screens/municipality_map_and_spots_screen.dart';
import 'package:atmos_trs_system/data/misamis_occidental_municipalities.dart';
import 'package:atmos_trs_system/services/qr_checkin_ui.dart';
import 'package:atmos_trs_system/services/user_activity_service.dart'
    as activity;
import 'package:atmos_trs_system/services/local_qr_spot_checkin_service.dart';
import 'package:atmos_trs_system/screens/qr_spot_checkin_screen.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:atmos_trs_system/widgets/app_logout_button.dart';

/// Main User Dashboard - Container for all user navigation
/// Organized with bottom navigation for Home, Explore, Scan, Notification (announcements from Tourism & Governor), Profile
class UserDashboardScreen extends StatefulWidget {
  const UserDashboardScreen({super.key});

  @override
  State<UserDashboardScreen> createState() => _UserDashboardScreenState();
}

class _UserDashboardScreenState extends State<UserDashboardScreen>
    with WidgetsBindingObserver {
  int _currentNavIndex = 0;
  UserProfile? _userProfile;
  List<Map<String, dynamic>> _firestoreAnnouncements = [];
  bool _isLoadingAnnouncements = true;
  int _unreadNotificationCount = 0;
  Set<String> _unreadAnnouncementIds = <String>{};
  Timer? _notificationPollTimer;

  // Theme colors
  static const Color _primaryOrange = Color(0xFFF97316);
  static const Color _darkBg = Color(0xFF0D1B2A);
  static const Color _cardBg = Color(0xFF1A1A2E);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadUserProfile();
    _loadAnnouncements();
    _refreshNotificationCount();
    _startNotificationAutoRefresh();
  }

  @override
  void dispose() {
    _notificationPollTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _refreshNotificationCount();
      _startNotificationAutoRefresh();
    } else if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      _notificationPollTimer?.cancel();
      _notificationPollTimer = null;
    }
  }

  void _startNotificationAutoRefresh() {
    _notificationPollTimer?.cancel();
    _notificationPollTimer = Timer.periodic(const Duration(seconds: 6), (_) {
      if (!mounted) return;
      _refreshNotificationCount();
    });
  }

  Future<void> _refreshNotificationCount() async {
    final notifications = await activity.UserActivityService.getNotifications();
    final unread = notifications.where((n) => !n.isRead).toList();
    final unreadAnnouncementIds = unread
        .map((n) => n.id)
        .where((id) => id.startsWith('ann_'))
        .toSet();
    if (mounted) {
      setState(() {
        _unreadNotificationCount = unread.length;
        _unreadAnnouncementIds = unreadAnnouncementIds;
      });
    }
  }

  Future<void> _markAnnouncementAsRead(String announcementId) async {
    if (announcementId.isEmpty) return;
    await activity.UserActivityService.markNotificationAsRead(
      'ann_$announcementId',
    );
    _refreshNotificationCount();
  }

  Future<void> _markAllNotificationsAsRead() async {
    await activity.UserActivityService.markAllNotificationsAsRead();
    _refreshNotificationCount();
  }

  Future<void> _handleChangePassword() async {
    final email =
        FirebaseAuth.instance.currentUser?.email ?? _userProfile?.email ?? '';
    if (email.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No email found for this account.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    try {
      await FirebaseAuth.instance.sendPasswordResetEmail(email: email);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Password reset link sent to $email'),
          behavior: SnackBarBehavior.floating,
          backgroundColor: const Color(0xFF059669),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Could not send reset link: $e'),
          behavior: SnackBarBehavior.floating,
          backgroundColor: Colors.redAccent,
        ),
      );
    }
  }

  void _showPrivacySheet() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => Container(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
        decoration: const BoxDecoration(
          color: _profileCard,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 44,
                height: 4,
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: _profileMuted.withOpacity(0.3),
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
              const Row(
                children: [
                  Icon(Icons.privacy_tip_outlined, color: _primaryOrange),
                  SizedBox(width: 10),
                  Text(
                    'Privacy & Security',
                    style: TextStyle(
                      color: _profileText,
                      fontSize: 19,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Text(
                'Your profile details and tourism activities are used only to support check-ins, announcements, badges, and tourism analytics in Misamis Occidental.',
                style: TextStyle(
                  color: _profileMuted,
                  fontSize: 14,
                  height: 1.45,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                'For account security, avoid sharing your login and always sign out on shared devices.',
                style: TextStyle(
                  color: _profileMuted,
                  fontSize: 14,
                  height: 1.45,
                ),
              ),
              const SizedBox(height: 18),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: () => Navigator.pop(context),
                  style: FilledButton.styleFrom(
                    backgroundColor: _primaryOrange,
                    foregroundColor: Colors.white,
                  ),
                  child: const Text('Got it'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _loadUserProfile() async {
    final authUser = FirebaseAuth.instance.currentUser;
    var profile = await TouristProfileHydration.loadProfile(
      email: authUser?.email,
    );
    profile = await ProfilePhotoHydration.mergeFirestorePhotoUrl(profile);
    if (mounted) {
      setState(() => _userProfile = profile);
    }
  }

  Future<void> _loadAnnouncements() async {
    try {
      if (Firebase.apps.isNotEmpty) {
        QuerySnapshot<Map<String, dynamic>> snapshot;
        try {
          snapshot = await FirebaseFirestore.instance
              .collection('announcements')
              .where('published', isEqualTo: true)
              .orderBy('createdAt', descending: true)
              .limit(20)
              .get();
        } catch (_) {
          // Fallback if composite index (published, createdAt) is missing
          final all = await FirebaseFirestore.instance
              .collection('announcements')
              .where('published', isEqualTo: true)
              .limit(50)
              .get();
          final list = all.docs.map((d) => {'id': d.id, ...d.data()}).toList();
          list.sort((a, b) {
            final aAt = a['createdAt'];
            final bAt = b['createdAt'];
            if (aAt == null && bAt == null) return 0;
            if (aAt == null) return 1;
            if (bAt == null) return -1;
            final aTime = aAt is Timestamp
                ? aAt.toDate()
                : (aAt is DateTime ? aAt : null);
            final bTime = bAt is Timestamp
                ? bAt.toDate()
                : (bAt is DateTime ? bAt : null);
            if (aTime == null || bTime == null) return 0;
            return bTime.compareTo(aTime);
          });
          if (mounted) {
            setState(() {
              _firestoreAnnouncements = list.take(20).toList();
              _isLoadingAnnouncements = false;
            });
            _syncAnnouncementsToNotifications(_firestoreAnnouncements);
          }
          _refreshNotificationCount();
          return;
        }
        if (mounted) {
          setState(() {
            _firestoreAnnouncements = snapshot.docs
                .map((doc) => {'id': doc.id, ...doc.data()})
                .toList();
            _isLoadingAnnouncements = false;
          });
          _syncAnnouncementsToNotifications(_firestoreAnnouncements);
        }
        _refreshNotificationCount();
      } else {
        setState(() => _isLoadingAnnouncements = false);
      }
    } catch (e) {
      debugPrint('Error loading announcements: $e');
      if (mounted) setState(() => _isLoadingAnnouncements = false);
    }
  }

  /// Push governor/tourism announcements into local notifications so they appear in the bell.
  Future<void> _syncAnnouncementsToNotifications(
    List<Map<String, dynamic>> announcements,
  ) async {
    for (final ann in announcements) {
      final id = ann['id']?.toString();
      if (id == null || id.isEmpty) continue;
      final title = ann['title']?.toString() ?? 'Announcement';
      final content = ann['content']?.toString() ?? '';
      final typeStr = ann['type']?.toString() ?? 'General';
      activity.NotificationType type = activity.NotificationType.system;
      if (typeStr == 'Promo')
        type = activity.NotificationType.event;
      else if (typeStr == 'Event')
        type = activity.NotificationType.event;
      else if (typeStr == 'Alert')
        type = activity.NotificationType.weather;
      await activity.UserActivityService.addNotificationFromAnnouncement(
        announcementId: id,
        title: title,
        message: content.isEmpty ? title : content,
        type: type,
      );
    }
  }

  String _formatAnnouncementTime(dynamic timestamp) {
    if (timestamp == null) return 'Just now';

    DateTime date;
    if (timestamp is Timestamp) {
      date = timestamp.toDate();
    } else if (timestamp is DateTime) {
      date = timestamp;
    } else {
      return 'Recently';
    }

    final now = DateTime.now();
    final diff = now.difference(date);

    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    return '${date.day}/${date.month}/${date.year}';
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final bool isWide = constraints.maxWidth > 900;
        final current = _buildCurrentScreen();
        final Widget body = isWide
            ? Row(
                children: [
                  _buildSidebarNav(),
                  Expanded(child: current),
                ],
              )
            : current;

        return Scaffold(
          body: body,
          bottomNavigationBar: isWide ? null : _buildBottomNav(),
        );
      },
    );
  }

  Widget _buildCurrentScreen() {
    switch (_currentNavIndex) {
      case 0:
        return const HomeScreen();
      case 1:
        return const ExploreScreen();
      case 2:
        return _buildScanScreen();
      case 3:
        return _buildAlertsScreen();
      case 4:
        return _buildProfileScreen();
      default:
        return const HomeScreen();
    }
  }

  // ============================================
  // SCAN SCREEN
  // ============================================
  Widget _buildScanScreen() {
    if (kIsWeb) {
      return Scaffold(
        backgroundColor: _darkBg,
        body: SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: const [
                  Icon(
                    Icons.qr_code_scanner_rounded,
                    size: 80,
                    color: Colors.white70,
                  ),
                  SizedBox(height: 16),
                  Text(
                    'QR scanning is available on the mobile app.\nFor web, please use your phone to scan QR codes.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.white70, fontSize: 16),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    return _ScanScreen(
      primaryOrange: _primaryOrange,
      darkBg: _darkBg,
      cardBg: _cardBg,
    );
  }

  // ============================================
  // ALERTS SCREEN - Notifications, Promos & Announcements
  // ============================================
  Widget _buildAlertsScreen() {
    // Notification categories with their data
    final promos = [
      {
        'title': '50% OFF Beach Resorts!',
        'message':
            'Book any beach resort in Misamis Occidental and get 50% discount. Valid until March 31.',
        'image':
            'https://images.unsplash.com/photo-1507525428034-b723cf961d3e?w=400',
        'tag': 'LIMITED TIME',
        'tagColor': _primaryOrange,
        'date': 'Feb 24, 2026',
      },
      {
        'title': 'Free VR Tour Experience',
        'message':
            'Visit any Asenso Park and enjoy a free 360° virtual tour experience for the whole family!',
        'image':
            'https://images.unsplash.com/photo-1585320806297-9794b3e4eeae?w=400',
        'tag': 'NEW',
        'tagColor': _primaryOrange,
        'date': 'Feb 20, 2026',
      },
      {
        'title': 'Buy 1 Take 1 Eco Park Entry',
        'message':
            'Tudela Highland Resort offers Buy 1 Take 1 entrance fee this weekend only!',
        'image': 'assets/images/Tudela Village.webp',
        'tag': 'WEEKEND ONLY',
        'tagColor': _primaryOrange,
        'date': 'Feb 18, 2026',
        'location': 'Tudela',
      },
    ];

    final events = [
      {
        'title': 'Pasalamat Festival 2026',
        'message':
            'Join the biggest thanksgiving festival in Oroquieta City! Parades, food fairs, and cultural shows.',
        'icon': Icons.celebration_rounded,
        'color': _primaryOrange,
        'date': 'March 15-17, 2026',
        'location': 'Oroquieta City',
      },
      {
        'title': 'MisOcc Food & Music Fest',
        'message':
            'Experience local cuisines and live performances at the Ozamis City Plaza.',
        'icon': Icons.restaurant_rounded,
        'color': _primaryOrange,
        'date': 'March 5, 2026',
        'location': 'Ozamis City',
      },
      {
        'title': 'Beach Clean-up Drive',
        'message':
            'Volunteer for our coastal clean-up at Baliangao Beach. Free shirt for participants!',
        'icon': Icons.volunteer_activism_rounded,
        'color': _primaryOrange,
        'date': 'March 1, 2026',
        'location': 'Baliangao',
      },
    ];

    // Combine Firestore announcements with default ones
    final defaultAnnouncements = [
      {
        'title': 'New Tourist Spot Added!',
        'message': 'Lake Duminagat in Clarin is now listed. Plan your visit!',
        'icon': Icons.new_releases_rounded,
        'color': _primaryOrange,
        'time': '1d ago',
        'type': 'General',
      },
      {
        'title': 'Weather Advisory',
        'message':
            'Sunny weather expected this weekend - perfect for outdoor activities!',
        'icon': Icons.wb_sunny_rounded,
        'color': _primaryOrange,
        'time': '2d ago',
        'type': 'Alert',
      },
      {
        'title': 'App Update Available',
        'message':
            'New features including improved VR tours and faster check-ins.',
        'icon': Icons.system_update_rounded,
        'color': _primaryOrange,
        'time': '3d ago',
        'type': 'General',
      },
    ];

    // Convert Firestore announcements to display format
    final firestoreConverted = _firestoreAnnouncements.map((ann) {
      final type = ann['type']?.toString() ?? 'General';
      IconData icon;
      switch (type) {
        case 'Promo':
          icon = Icons.local_offer_rounded;
          break;
        case 'Event':
          icon = Icons.event_rounded;
          break;
        case 'Alert':
          icon = Icons.warning_rounded;
          break;
        default:
          icon = Icons.campaign_rounded;
      }
      return {
        'announcementId': ann['id']?.toString() ?? '',
        'title': ann['title'] ?? 'Announcement',
        'message': ann['content'] ?? '',
        'icon': icon,
        'color': _primaryOrange,
        'time': _formatAnnouncementTime(ann['createdAt']),
        'type': type,
        'fromFirestore': true,
      };
    }).toList();

    final announcements = [...firestoreConverted, ...defaultAnnouncements];

    return Scaffold(
      backgroundColor: _darkBg,
      body: RefreshIndicator(
        onRefresh: _loadAnnouncements,
        color: _primaryOrange,
        child: SafeArea(
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Notifications',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 24,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 4),
                            if (_unreadNotificationCount > 0)
                              Container(
                                margin: const EdgeInsets.only(bottom: 6),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 4,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.redAccent,
                                  borderRadius: BorderRadius.circular(999),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.redAccent.withOpacity(0.35),
                                      blurRadius: 12,
                                      offset: const Offset(0, 4),
                                    ),
                                  ],
                                ),
                                child: Text(
                                  _unreadNotificationCount > 99
                                      ? '99+ unread'
                                      : '${_unreadNotificationCount} unread',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                            Text(
                              'From Tourism Office & Province',
                              style: TextStyle(
                                color: Colors.white54,
                                fontSize: 14,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Row(
                        children: [
                          if (_unreadNotificationCount > 0) ...[
                            _buildAlertsHeaderIcon(
                              icon: Icons.done_all_rounded,
                              onTap: _markAllNotificationsAsRead,
                            ),
                            const SizedBox(width: 8),
                          ],
                          _buildAlertsHeaderIcon(
                            icon: Icons.search_rounded,
                            onTap: () {
                              // TODO: Optional: implement notification search/filter
                            },
                          ),
                          const SizedBox(width: 8),
                          _buildAlertsHeaderIcon(
                            icon: Icons.tune_rounded,
                            onTap: () {
                              // TODO: Optional: open filter sheet (All, Promos, Events, Alerts)
                            },
                          ),
                        ],
                      ),
                    ],
                  ),
                ),

                // Municipalities & Cities – tap to open map + spots + VR
                _buildAlertsSectionHeader(
                  'Municipalities & Cities',
                  Icons.map_rounded,
                  _primaryOrange,
                ),
                const SizedBox(height: 8),
                SizedBox(
                  height: 44,
                  child: ListView.builder(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    itemCount: getMisamisOccidentalMunicipalities().length,
                    itemBuilder: (context, index) {
                      final m = getMisamisOccidentalMunicipalities()[index];
                      return Padding(
                        padding: const EdgeInsets.only(right: 10),
                        child: Material(
                          color: _cardBg,
                          borderRadius: BorderRadius.circular(22),
                          child: InkWell(
                            onTap: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (context) =>
                                      MunicipalityMapAndSpotsScreen(
                                        municipalityIdOrName: m.name,
                                      ),
                                ),
                              );
                            },
                            borderRadius: BorderRadius.circular(22),
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 10,
                              ),
                              decoration: BoxDecoration(
                                border: Border.all(
                                  color: _primaryOrange.withOpacity(0.5),
                                ),
                                borderRadius: BorderRadius.circular(22),
                              ),
                              child: Center(
                                child: Text(
                                  m.name,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
                const SizedBox(height: 16),

                // PROMOS SECTION
                _buildAlertsSectionHeader(
                  'Special Promos',
                  Icons.local_offer_rounded,
                  _primaryOrange,
                ),
                SizedBox(
                  height: 200,
                  child: ListView.builder(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    itemCount: promos.length,
                    itemBuilder: (context, index) {
                      final promo = promos[index];
                      return _buildPromoCard(promo);
                    },
                  ),
                ),

                // EVENTS SECTION
                _buildAlertsSectionHeader(
                  'Upcoming Events',
                  Icons.event_rounded,
                  _primaryOrange,
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Column(
                    children: events
                        .map((event) => _buildEventCard(event))
                        .toList(),
                  ),
                ),

                // ANNOUNCEMENTS SECTION (from Tourism Office & Governor)
                _buildAlertsSectionHeader(
                  'Announcements',
                  Icons.campaign_rounded,
                  _primaryOrange,
                ),
                if (_isLoadingAnnouncements)
                  const Padding(
                    padding: EdgeInsets.all(20),
                    child: Center(
                      child: CircularProgressIndicator(color: _primaryOrange),
                    ),
                  )
                else
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 100),
                    child: Column(
                      children: announcements
                          .map((ann) => _buildAnnouncementCard(ann))
                          .toList(),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildAlertsHeaderIcon({required IconData icon, VoidCallback? onTap}) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: _primaryOrange.withOpacity(0.16),
            shape: BoxShape.circle,
          ),
          child: Icon(icon, color: Colors.white, size: 20),
        ),
      ),
    );
  }

  Widget _buildAlertsSectionHeader(String title, IconData icon, Color color) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 12),
      child: Row(
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(width: 8),
          Text(
            title,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          const Spacer(),
          Text(
            'See All',
            style: TextStyle(
              color: _primaryOrange,
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPromoCard(Map<String, dynamic> promo) {
    final location = promo['location'] as String?;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: location != null && location.isNotEmpty
            ? () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => MunicipalityMapAndSpotsScreen(
                      municipalityIdOrName: location,
                    ),
                  ),
                );
              }
            : null,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          width: 280,
          margin: const EdgeInsets.only(right: 12),
          decoration: BoxDecoration(
            color: _cardBg,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.white.withOpacity(0.05)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Promo Image
              Stack(
                children: [
                  ClipRRect(
                    borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(16),
                    ),
                    child: (promo['image'] as String).startsWith('http')
                        ? Image.network(
                            promo['image'] as String,
                            width: 280,
                            height: 100,
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => Container(
                              width: 280,
                              height: 100,
                              color: _primaryOrange.withOpacity(0.2),
                              child: const Icon(
                                Icons.local_offer,
                                color: _primaryOrange,
                                size: 40,
                              ),
                            ),
                          )
                        : Image.asset(
                            promo['image'] as String,
                            width: 280,
                            height: 100,
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => Container(
                              width: 280,
                              height: 100,
                              color: _primaryOrange.withOpacity(0.2),
                              child: const Icon(
                                Icons.local_offer,
                                color: _primaryOrange,
                                size: 40,
                              ),
                            ),
                          ),
                  ),
                  Positioned(
                    top: 8,
                    left: 8,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: promo['tagColor'] as Color,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        promo['tag'] as String,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              // Promo Content
              Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      promo['title'] as String,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      promo['message'] as String,
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.6),
                        fontSize: 12,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Icon(
                          Icons.calendar_today,
                          size: 12,
                          color: Colors.white.withOpacity(0.5),
                        ),
                        const SizedBox(width: 4),
                        Text(
                          promo['date'] as String,
                          style: TextStyle(
                            color: Colors.white.withOpacity(0.5),
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildEventCard(Map<String, dynamic> event) {
    final location = event['location'] as String?;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: location != null && location.isNotEmpty
            ? () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => MunicipalityMapAndSpotsScreen(
                      municipalityIdOrName: location,
                    ),
                  ),
                );
              }
            : null,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: _cardBg,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.white.withOpacity(0.05)),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: (event['color'] as Color).withOpacity(0.15),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  event['icon'] as IconData,
                  color: event['color'] as Color,
                  size: 28,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      event['title'] as String,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 15,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      event['message'] as String,
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.6),
                        fontSize: 13,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Icon(
                          Icons.calendar_today,
                          size: 12,
                          color: _primaryOrange,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          event['date'] as String,
                          style: TextStyle(
                            color: _primaryOrange,
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Icon(
                          Icons.location_on,
                          size: 12,
                          color: Colors.white.withOpacity(0.5),
                        ),
                        const SizedBox(width: 4),
                        Text(
                          event['location'] as String,
                          style: TextStyle(
                            color: Colors.white.withOpacity(0.5),
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right, color: Colors.white.withOpacity(0.3)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAnnouncementCard(Map<String, dynamic> ann) {
    final announcementId = (ann['announcementId'] as String?) ?? '';
    final isUnread =
        announcementId.isNotEmpty &&
        _unreadAnnouncementIds.contains('ann_$announcementId');

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: announcementId.isEmpty
            ? null
            : () => _markAnnouncementAsRead(announcementId),
        child: Container(
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: isUnread ? _primaryOrange.withOpacity(0.12) : _cardBg,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isUnread
                  ? _primaryOrange.withOpacity(0.45)
                  : Colors.white.withOpacity(0.05),
            ),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: (ann['color'] as Color).withOpacity(0.15),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  ann['icon'] as IconData,
                  color: ann['color'] as Color,
                  size: 22,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        if (isUnread)
                          Container(
                            width: 8,
                            height: 8,
                            margin: const EdgeInsets.only(right: 8),
                            decoration: const BoxDecoration(
                              color: Colors.redAccent,
                              shape: BoxShape.circle,
                            ),
                          ),
                        Expanded(
                          child: Text(
                            ann['title'] as String,
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: isUnread
                                  ? FontWeight.w700
                                  : FontWeight.w600,
                              fontSize: 14,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      ann['message'] as String,
                      style: TextStyle(
                        color: Colors.white.withOpacity(isUnread ? 0.78 : 0.5),
                        fontSize: 12,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              Text(
                ann['time'] as String,
                style: TextStyle(
                  color: Colors.white.withOpacity(0.4),
                  fontSize: 11,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ============================================
  // PROFILE SCREEN (Light theme – enhanced)
  // ============================================
  static const Color _profileBg = Color(0xFFFFFFFF);
  static const Color _profileCard = Color(0xFFFFFFFF);
  static const Color _profileText = Color(0xFF111827); // darker for clarity
  static const Color _profileMuted = Color(
    0xFF4B5563,
  ); // readable gray (was 6B7280)
  static const Color _profileBorder = Color(0xFFFED7AA); // soft orange border

  Widget _buildProfileScreen() {
    final hasProfilePhotoUrl =
        _userProfile?.profilePhotoUrl != null &&
        _userProfile!.profilePhotoUrl!.isNotEmpty;
    final hasProfileImageBase64 =
        _userProfile?.profileImageBase64 != null &&
        _userProfile!.profileImageBase64!.isNotEmpty;
    final hasProfileImage = hasProfilePhotoUrl || hasProfileImageBase64;
    final firstName = _userProfile?.firstName ?? 'Guest';
    final middleName = _userProfile?.middleName;
    final lastName = _userProfile?.lastName ?? '';
    final suffix = _userProfile?.suffix;

    // Build full name with middle initial
    String fullName = firstName;
    if (middleName != null && middleName.isNotEmpty) {
      fullName += ' ${middleName[0]}.';
    }
    fullName += ' $lastName';
    if (suffix != null && suffix.isNotEmpty && suffix != 'None') {
      fullName += ' $suffix';
    }

    final touristId = _userProfile?.touristId ?? 'N/A';
    final isLocal = _userProfile?.nationality == 'Filipino';

    return DefaultTabController(
      length: 2,
      child: Scaffold(
        backgroundColor: _profileBg,
        appBar: AppBar(
          backgroundColor: _profileBg,
          elevation: 0,
          scrolledUnderElevation: 0,
          title: const Text(
            'My Profile',
            style: TextStyle(
              fontWeight: FontWeight.w700,
              color: _profileText,
              fontSize: 19,
            ),
          ),
          centerTitle: true,
          bottom: TabBar(
            indicatorColor: _primaryOrange,
            indicatorWeight: 3,
            labelColor: _primaryOrange,
            unselectedLabelColor: _profileMuted,
            labelStyle: const TextStyle(
              fontWeight: FontWeight.w600,
              fontSize: 15,
            ),
            tabs: const [
              Tab(text: 'Personal Info'),
              Tab(text: 'History'),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            // PERSONAL INFO TAB
            SingleChildScrollView(
              child: Column(
                children: [
                  // Profile Header Card
                  Container(
                    margin: const EdgeInsets.fromLTRB(20, 20, 20, 16),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 24,
                      vertical: 28,
                    ),
                    decoration: BoxDecoration(
                      color: _profileCard,
                      borderRadius: BorderRadius.circular(24),
                      boxShadow: [
                        BoxShadow(
                          color: _primaryOrange.withOpacity(0.08),
                          blurRadius: 24,
                          offset: const Offset(0, 10),
                        ),
                        BoxShadow(
                          color: Colors.black.withOpacity(0.06),
                          blurRadius: 16,
                          offset: const Offset(0, 4),
                        ),
                      ],
                      border: Border.all(
                        color: _profileBorder.withOpacity(0.6),
                        width: 1.5,
                      ),
                    ),
                    child: Column(
                      children: [
                        Stack(
                          children: [
                            Container(
                              width: 108,
                              height: 108,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: _primaryOrange,
                                  width: 3,
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color: _primaryOrange.withOpacity(0.3),
                                    blurRadius: 20,
                                    offset: const Offset(0, 6),
                                  ),
                                  BoxShadow(
                                    color: Colors.black.withOpacity(0.08),
                                    blurRadius: 12,
                                    offset: const Offset(0, 2),
                                  ),
                                ],
                              ),
                              child: ClipOval(
                                child: hasProfileImage
                                    ? _buildProfileImage(
                                        hasProfilePhotoUrl,
                                        hasProfileImageBase64,
                                      )
                                    : Container(
                                        color: const Color(0xFFF3F4F6),
                                        child: Icon(
                                          Icons.person_rounded,
                                          color: _profileMuted,
                                          size: 54,
                                        ),
                                      ),
                              ),
                            ),
                            Positioned(
                              right: 0,
                              bottom: 0,
                              child: GestureDetector(
                                onTap: () {},
                                child: Container(
                                  padding: const EdgeInsets.all(10),
                                  decoration: BoxDecoration(
                                    color: _primaryOrange,
                                    shape: BoxShape.circle,
                                    border: Border.all(
                                      color: _profileCard,
                                      width: 3,
                                    ),
                                    boxShadow: [
                                      BoxShadow(
                                        color: _primaryOrange.withOpacity(0.5),
                                        blurRadius: 10,
                                        offset: const Offset(0, 3),
                                      ),
                                      BoxShadow(
                                        color: Colors.black.withOpacity(0.15),
                                        blurRadius: 6,
                                        offset: const Offset(0, 2),
                                      ),
                                    ],
                                  ),
                                  child: const Icon(
                                    Icons.camera_alt_rounded,
                                    color: Colors.white,
                                    size: 18,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 20),
                        Text(
                          fullName,
                          style: const TextStyle(
                            color: _profileText,
                            fontSize: 24,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -0.2,
                            height: 1.2,
                          ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 12),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.verified_rounded,
                              color: _primaryOrange,
                              size: 20,
                            ),
                            const SizedBox(width: 6),
                            Text(
                              'Verified Citizen',
                              style: TextStyle(
                                color: _profileText,
                                fontSize: 15,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            Text(
                              ' • ID: ',
                              style: TextStyle(
                                color: _profileMuted,
                                fontSize: 14,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            Text(
                              touristId,
                              style: TextStyle(
                                color: _profileText,
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 20),
                        Wrap(
                          alignment: WrapAlignment.center,
                          spacing: 10,
                          runSpacing: 10,
                          children: [
                            _buildProfileTag(
                              isLocal ? 'Local' : 'Foreign',
                              _primaryOrange.withOpacity(0.15),
                              _primaryOrange,
                            ),
                            _buildProfileTag(
                              'Level 1 Explorer',
                              _primaryOrange.withOpacity(0.15),
                              _primaryOrange,
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),

                  // My Tourist QR Code – tappable banner
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: Material(
                      color: Colors.transparent,
                      child: InkWell(
                        onTap: () async {
                          final uid =
                              AuthConfig.currentUserUid ??
                              await SessionStorage.getStoredUser();
                          if (!context.mounted) return;
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => QrProfileScreen(
                                touristId: uid ?? touristId,
                                fullName: fullName,
                                location:
                                    _userProfile?.city ?? 'Misamis Occidental',
                              ),
                            ),
                          );
                        },
                        borderRadius: BorderRadius.circular(16),
                        child: Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 20,
                            vertical: 18,
                          ),
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: [
                                _primaryOrange,
                                _primaryOrange.withOpacity(0.85),
                              ],
                              begin: Alignment.centerLeft,
                              end: Alignment.centerRight,
                            ),
                            borderRadius: BorderRadius.circular(16),
                            boxShadow: [
                              BoxShadow(
                                color: _primaryOrange.withOpacity(0.35),
                                blurRadius: 16,
                                offset: const Offset(0, 6),
                              ),
                            ],
                          ),
                          child: Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(10),
                                decoration: BoxDecoration(
                                  color: Colors.white.withOpacity(0.2),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: const Icon(
                                  Icons.qr_code_2_rounded,
                                  color: Colors.white,
                                  size: 28,
                                ),
                              ),
                              const SizedBox(width: 16),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text(
                                      'My Tourist QR Code',
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontSize: 18,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      'Tap to view your unique Tourist ID',
                                      style: TextStyle(
                                        color: Colors.white.withOpacity(0.95),
                                        fontSize: 14,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              Icon(
                                Icons.arrow_forward_ios_rounded,
                                color: Colors.white.withOpacity(0.9),
                                size: 18,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),

                  // Personal Details – tap to show all data (reference: orange pill, black text, chevron)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: Material(
                      color: Colors.transparent,
                      child: InkWell(
                        onTap: () => _showPersonalDetailsSheet(context),
                        borderRadius: BorderRadius.circular(28),
                        child: Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 20,
                            vertical: 16,
                          ),
                          decoration: BoxDecoration(
                            color: _primaryOrange,
                            borderRadius: BorderRadius.circular(28),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withOpacity(0.12),
                                blurRadius: 10,
                                offset: const Offset(0, 4),
                              ),
                            ],
                          ),
                          child: Row(
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Text(
                                      'PERSONAL DETAILS',
                                      style: TextStyle(
                                        color: Colors.black,
                                        fontSize: 14,
                                        fontWeight: FontWeight.w700,
                                        letterSpacing: 0.5,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      fullName,
                                      style: const TextStyle(
                                        color: Colors.black87,
                                        fontSize: 15,
                                        fontWeight: FontWeight.w400,
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ],
                                ),
                              ),
                              const Icon(
                                Icons.chevron_right_rounded,
                                color: Colors.black,
                                size: 28,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  _buildProfileSection(
                    icon: Icons.admin_panel_settings_outlined,
                    title: 'Account Security',
                    children: [
                      _buildSettingTile(
                        icon: Icons.lock_reset_rounded,
                        title: 'Change Password',
                        subtitle: 'Send reset link to your email securely',
                        onTap: _handleChangePassword,
                      ),
                      const SizedBox(height: 10),
                      _buildSettingTile(
                        icon: Icons.privacy_tip_outlined,
                        title: 'Privacy',
                        subtitle: 'View how your data is used and protected',
                        onTap: _showPrivacySheet,
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),

                  // Logout (same style as Governor / Tourism — solid orange pill)
                  AppLogoutButton(
                    style: AppLogoutStyle.solidPill,
                    expanded: true,
                    fullWidth: true,
                    margin: const EdgeInsets.symmetric(horizontal: 20),
                    onPressed: () {
                      AuthConfig.currentUserUid = null;
                      Navigator.pushReplacementNamed(context, '/login');
                    },
                  ),
                  const SizedBox(height: 32),
                ],
              ),
            ),

            // HISTORY TAB
            _buildHistoryTab(),
          ],
        ),
      ),
    );
  }

  void _showPersonalDetailsSheet(BuildContext context) {
    final p = _userProfile;
    final firstName = p?.firstName ?? 'Guest';
    final middleName = p?.middleName;
    final lastName = p?.lastName ?? '';
    final suffix = p?.suffix;

    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.7,
        minChildSize: 0.4,
        maxChildSize: 0.95,
        builder: (context, scrollController) => Container(
          decoration: const BoxDecoration(
            color: _profileCard,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: Column(
            children: [
              const SizedBox(height: 12),
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: _profileMuted.withOpacity(0.4),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 16, 24, 12),
                child: Row(
                  children: [
                    Icon(Icons.person_rounded, color: _primaryOrange, size: 24),
                    const SizedBox(width: 10),
                    const Text(
                      'Personal Details',
                      style: TextStyle(
                        color: _profileText,
                        fontSize: 21,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: ListView(
                  controller: scrollController,
                  padding: const EdgeInsets.only(bottom: 24),
                  children: [
                    _buildProfileSection(
                      icon: Icons.person_outline_rounded,
                      title: 'Personal Information',
                      children: [
                        _buildInfoField('FIRST NAME', firstName),
                        const SizedBox(height: 16),
                        Row(
                          children: [
                            Expanded(
                              child: _buildInfoField(
                                'MIDDLE NAME',
                                middleName ?? 'N/A',
                              ),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: _buildInfoField('LAST NAME', lastName),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        Row(
                          children: [
                            Expanded(
                              child: _buildInfoField(
                                'SUFFIX',
                                suffix ?? 'None',
                              ),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: _buildInfoField('SEX', p?.sex ?? 'N/A'),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        Row(
                          children: [
                            Expanded(
                              child: _buildInfoField(
                                'CIVIL STATUS',
                                p?.civilStatus ?? 'N/A',
                              ),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: _buildInfoField(
                                'NATIONALITY',
                                p?.nationality ?? 'N/A',
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        _buildInfoField(
                          'DATE OF BIRTH',
                          p?.dateOfBirth ?? 'N/A',
                        ),
                      ],
                    ),
                    _buildProfileSection(
                      icon: Icons.contact_phone_outlined,
                      title: 'Contact Information',
                      children: [
                        _buildInfoField('MOBILE NUMBER', p?.mobile ?? 'N/A'),
                      ],
                    ),
                    _buildProfileSection(
                      icon: Icons.location_on_outlined,
                      title: 'Address',
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: _buildInfoField(
                                'COUNTRY',
                                p?.country ?? 'N/A',
                              ),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: _buildInfoField(
                                'PROVINCE',
                                p?.province ?? 'N/A',
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        _buildInfoField(
                          'CITY / MUNICIPALITY',
                          p?.city ?? 'N/A',
                        ),
                        const SizedBox(height: 16),
                        Row(
                          children: [
                            Expanded(
                              child: _buildInfoField(
                                'BARANGAY',
                                p?.barangay ?? 'N/A',
                              ),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: _buildInfoField(
                                'STREET',
                                p?.street ?? 'N/A',
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildProfileTag(String text, Color bgColor, Color textColor) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: textColor.withOpacity(0.35), width: 1.5),
        boxShadow: [
          BoxShadow(
            color: textColor.withOpacity(0.08),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Text(
        text,
        style: TextStyle(
          color: textColor,
          fontSize: 14,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  Widget _buildSettingTile({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Ink(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: _profileBorder.withOpacity(0.45)),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: _primaryOrange.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, size: 20, color: _primaryOrange),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        color: _profileText,
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: TextStyle(
                        color: _profileMuted,
                        fontSize: 12.5,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(
                Icons.chevron_right_rounded,
                color: _profileMuted,
                size: 20,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHistoryTab() {
    return Container(
      color: _profileBg,
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 28),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.all(22),
            decoration: BoxDecoration(
              color: _profileCard,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: _profileBorder.withOpacity(0.4)),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.history_toggle_off_rounded,
                  color: _primaryOrange,
                  size: 40,
                ),
                const SizedBox(height: 12),
                const Text(
                  'History section simplified',
                  style: TextStyle(
                    color: _profileText,
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Visits and badges summary has been removed to keep your profile clean.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: _profileMuted,
                    fontSize: 14,
                    height: 1.45,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildProfileSection({
    required IconData icon,
    required String title,
    required List<Widget> children,
  }) {
    return Container(
      margin: const EdgeInsets.fromLTRB(20, 0, 20, 16),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: _profileCard,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: _primaryOrange.withOpacity(0.05),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
        border: Border.all(color: _profileBorder.withOpacity(0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: _primaryOrange, size: 22),
              const SizedBox(width: 10),
              Text(
                title,
                style: const TextStyle(
                  color: _profileText,
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          ...children,
        ],
      ),
    );
  }

  Widget _buildInfoField(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            color: _profileMuted,
            fontSize: 12,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.3,
          ),
        ),
        const SizedBox(height: 8),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            color: const Color(0xFFF9FAFB),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFFE5E7EB)),
          ),
          child: Text(
            value,
            style: const TextStyle(
              color: _profileText,
              fontSize: 16,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ],
    );
  }

  // ============================================
  // PROFILE IMAGE HELPER
  // ============================================
  Widget _buildProfileImage(bool hasUrl, bool hasBase64) {
    if (hasUrl) {
      return Image.network(
        _userProfile!.profilePhotoUrl!,
        width: 100,
        height: 100,
        fit: BoxFit.cover,
        loadingBuilder: (context, child, loadingProgress) {
          if (loadingProgress == null) return child;
          return Container(
            width: 100,
            height: 100,
            color: _profileMuted.withOpacity(0.2),
            child: Center(
              child: CircularProgressIndicator(
                value: loadingProgress.expectedTotalBytes != null
                    ? loadingProgress.cumulativeBytesLoaded /
                          loadingProgress.expectedTotalBytes!
                    : null,
                color: _primaryOrange,
                strokeWidth: 2,
              ),
            ),
          );
        },
        errorBuilder: (context, error, stackTrace) {
          if (hasBase64) {
            return Image.memory(
              base64Decode(_userProfile!.profileImageBase64!),
              width: 100,
              height: 100,
              fit: BoxFit.cover,
            );
          }
          return Container(
            width: 100,
            height: 100,
            color: _profileMuted.withOpacity(0.2),
            child: Icon(Icons.person, color: _profileMuted, size: 50),
          );
        },
      );
    } else if (hasBase64) {
      return Image.memory(
        base64Decode(_userProfile!.profileImageBase64!),
        width: 100,
        height: 100,
        fit: BoxFit.cover,
      );
    }
    return Container(
      width: 100,
      height: 100,
      color: _profileMuted.withOpacity(0.2),
      child: Icon(Icons.person, color: _profileMuted, size: 50),
    );
  }

  // ============================================
  // BOTTOM NAVIGATION BAR
  // ============================================
  Widget _buildBottomNav() {
    const items = [
      (icon: Icons.home_rounded, activeIcon: Icons.home, label: 'Home'),
      (
        icon: Icons.explore_outlined,
        activeIcon: Icons.explore,
        label: 'Explore',
      ),
      (
        icon: Icons.qr_code_scanner_rounded,
        activeIcon: Icons.qr_code_scanner,
        label: 'QR Scanner',
      ),
      (
        icon: Icons.notifications_outlined,
        activeIcon: Icons.notifications,
        label: 'Notification', // Announcements from Tourism Office & Governor
      ),
      (icon: Icons.person_outline, activeIcon: Icons.person, label: 'Account'),
    ];

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.08),
            blurRadius: 20,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: List.generate(items.length, (index) {
              final item = items[index];
              final isSelected = index == _currentNavIndex;
              final isNotificationTab = index == 3;
              final notificationCount = _unreadNotificationCount;
              final hasUnreadNotifications =
                  isNotificationTab && notificationCount > 0;

              return Expanded(
                child: InkWell(
                  onTap: () {
                    if (isNotificationTab) {
                      _loadAnnouncements();
                      _refreshNotificationCount();
                    }
                    setState(() => _currentNavIndex = index);
                  },
                  borderRadius: BorderRadius.circular(12),
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Stack(
                          clipBehavior: Clip.none,
                          children: [
                            AnimatedContainer(
                              duration: const Duration(milliseconds: 200),
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: hasUnreadNotifications
                                    ? _primaryOrange
                                    : (isSelected
                                          ? _primaryOrange.withOpacity(0.1)
                                          : Colors.transparent),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Icon(
                                isSelected ? item.activeIcon : item.icon,
                                size: 24,
                                color: hasUnreadNotifications
                                    ? Colors.white
                                    : (isSelected
                                          ? _primaryOrange
                                          : Colors.grey.shade500),
                              ),
                            ),
                            if (isNotificationTab && notificationCount > 0)
                              Positioned(
                                top: 0,
                                right: 0,
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 5,
                                    vertical: 2,
                                  ),
                                  decoration: BoxDecoration(
                                    color: _primaryOrange,
                                    shape: BoxShape.circle,
                                    border: Border.all(
                                      color: Colors.white,
                                      width: 2,
                                    ),
                                  ),
                                  constraints: const BoxConstraints(
                                    minWidth: 16,
                                    minHeight: 16,
                                  ),
                                  child: Center(
                                    child: Text(
                                      notificationCount > 99
                                          ? '99+'
                                          : '$notificationCount',
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 10,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          item.label,
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: isSelected
                                ? FontWeight.w600
                                : FontWeight.w500,
                            color: isSelected
                                ? _primaryOrange
                                : Colors.grey.shade500,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            }),
          ),
        ),
      ),
    );
  }

  // ============================================
  // SIDEBAR NAVIGATION (WEB / DESKTOP)
  // ============================================
  Widget _buildSidebarNav() {
    const items = [
      (icon: Icons.home_rounded, activeIcon: Icons.home, label: 'Home'),
      (
        icon: Icons.explore_outlined,
        activeIcon: Icons.explore,
        label: 'Explore',
      ),
      (
        icon: Icons.qr_code_scanner_rounded,
        activeIcon: Icons.qr_code_scanner,
        label: 'QR Scanner',
      ),
      (
        icon: Icons.notifications_outlined,
        activeIcon: Icons.notifications,
        label: 'Notification',
      ),
      (icon: Icons.person_outline, activeIcon: Icons.person, label: 'Account'),
    ];

    return Container(
      width: 220,
      color: _darkBg,
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 16),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text(
                'ATMOS TRS',
                style: TextStyle(
                  color: Colors.white.withOpacity(0.9),
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            const SizedBox(height: 24),
            Expanded(
              child: ListView.builder(
                itemCount: items.length,
                itemBuilder: (context, index) {
                  final item = items[index];
                  final isSelected = index == _currentNavIndex;
                  final isNotificationTab = index == 3;
                  final notificationCount = _unreadNotificationCount;
                  final hasUnreadNotifications =
                      isNotificationTab && notificationCount > 0;

                  return Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(12),
                      onTap: () {
                        if (isNotificationTab) {
                          _loadAnnouncements();
                          _refreshNotificationCount();
                        }
                        setState(() => _currentNavIndex = index);
                      },
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 10,
                        ),
                        decoration: BoxDecoration(
                          color: isSelected
                              ? _primaryOrange.withOpacity(0.15)
                              : Colors.transparent,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Row(
                          children: [
                            Stack(
                              clipBehavior: Clip.none,
                              children: [
                                AnimatedContainer(
                                  duration: const Duration(milliseconds: 200),
                                  padding: const EdgeInsets.all(6),
                                  decoration: BoxDecoration(
                                    color: hasUnreadNotifications
                                        ? _primaryOrange
                                        : (isSelected
                                              ? _primaryOrange.withOpacity(0.15)
                                              : Colors.transparent),
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: Icon(
                                    isSelected ? item.activeIcon : item.icon,
                                    color: hasUnreadNotifications
                                        ? Colors.white
                                        : (isSelected
                                              ? _primaryOrange
                                              : Colors.white70),
                                  ),
                                ),
                                if (isNotificationTab && notificationCount > 0)
                                  Positioned(
                                    top: -4,
                                    right: -4,
                                    child: Container(
                                      padding: const EdgeInsets.all(3),
                                      decoration: BoxDecoration(
                                        color: _primaryOrange,
                                        shape: BoxShape.circle,
                                        border: Border.all(
                                          color: _darkBg,
                                          width: 1.5,
                                        ),
                                      ),
                                      constraints: const BoxConstraints(
                                        minWidth: 16,
                                        minHeight: 16,
                                      ),
                                      child: Center(
                                        child: Text(
                                          notificationCount > 99
                                              ? '99+'
                                              : '$notificationCount',
                                          style: const TextStyle(
                                            color: Colors.white,
                                            fontSize: 9,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                item.label,
                                style: TextStyle(
                                  color: isSelected
                                      ? Colors.white
                                      : Colors.white70,
                                  fontSize: 14,
                                  fontWeight: isSelected
                                      ? FontWeight.w600
                                      : FontWeight.w500,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Full-screen QR scanner for spot check-in.
/// Parses ATMOS-TRS-SPOT:municipalityId:spotId and calls performQRCheckIn + UserActivityService.addVisit.
class _ScanScreen extends StatefulWidget {
  const _ScanScreen({
    required this.primaryOrange,
    required this.darkBg,
    required this.cardBg,
  });

  final Color primaryOrange;
  final Color darkBg;
  final Color cardBg;

  @override
  State<_ScanScreen> createState() => _ScanScreenState();
}

class _ScanScreenState extends State<_ScanScreen> with WidgetsBindingObserver {
  final MobileScannerController _controller = MobileScannerController(
    detectionSpeed: DetectionSpeed.normal,
    facing: CameraFacing.back,
    torchEnabled: false,
    autoStart: false,
  );
  bool _isProcessing = false;
  String? _lastScannedCode;
  bool _isStartingCamera = false;
  static const String _spotPrefix = 'ATMOS-TRS-SPOT:';
  static const String _deepLinkPrefix = 'https://myapp.com/checkin';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _startCamera();
  }

  Future<void> _startCamera() async {
    if (_isStartingCamera) return;
    _isStartingCamera = true;
    try {
      await _controller.stop();
      await _controller.start();
    } catch (e) {
      debugPrint('User dashboard scanner: camera restart error: $e');
      if (mounted) setState(() {});
    } finally {
      _isStartingCamera = false;
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    if (state == AppLifecycleState.resumed) {
      _startCamera();
      return;
    }
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden) {
      _controller.stop();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controller.dispose();
    super.dispose();
  }

  Future<void> _onDetect(BarcodeCapture capture) async {
    if (_isProcessing) return;
    final barcodes = capture.barcodes;
    if (barcodes.isEmpty) return;
    final raw = barcodes.first.rawValue;
    if (raw == null || raw.isEmpty) return;
    if (_lastScannedCode == raw) return;
    _lastScannedCode = raw;

    // New deep-link based QR flow: https://myapp.com/checkin?spot_id=SPOT001
    if (raw.startsWith(_deepLinkPrefix)) {
      final localService = LocalQRSpotCheckInService.instance;
      final spotId = localService.extractSpotIdFromPayload(raw);
      if (spotId == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Invalid spot QR code'),
              behavior: SnackBarBehavior.floating,
              backgroundColor: Colors.red,
            ),
          );
        }
        return;
      }

      final spot = localService.getSpotById(spotId);
      if (spot == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Unknown tourist spot'),
              behavior: SnackBarBehavior.floating,
              backgroundColor: Colors.red,
            ),
          );
        }
        return;
      }

      if (!mounted) return;
      await Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => QrSpotCheckInScreen(spot: spot)),
      );
      return;
    }

    // Existing ATMOS-TRS-SPOT:municipalityId:spotId format
    if (!raw.startsWith(_spotPrefix)) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Invalid spot QR code'),
            behavior: SnackBarBehavior.floating,
            backgroundColor: Colors.red,
          ),
        );
      }
      return;
    }

    final rest = raw.substring(_spotPrefix.length);
    final parts = rest.split(':');
    if (parts.length < 2) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Invalid spot QR code'),
            behavior: SnackBarBehavior.floating,
            backgroundColor: Colors.red,
          ),
        );
      }
      return;
    }

    final municipalityId = parts[0].trim();
    final spotId = parts.sublist(1).join(':').trim();
    if (municipalityId.isEmpty || spotId.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Invalid spot QR code'),
            behavior: SnackBarBehavior.floating,
            backgroundColor: Colors.red,
          ),
        );
      }
      return;
    }

    setState(() => _isProcessing = true);

    final saved = await performQRCheckIn(
      context,
      municipalityId: municipalityId,
      spotId: spotId,
    );

    if (saved) {
      final spotName = spotId
          .replaceAll('_', ' ')
          .split(' ')
          .map((s) {
            if (s.isEmpty) return '';
            return s.length > 1
                ? '${s[0].toUpperCase()}${s.substring(1).toLowerCase()}'
                : s.toUpperCase();
          })
          .join(' ');
      await activity.UserActivityService.addVisit(
        spotId: spotId,
        spotName: spotName,
        category: 'Spot',
      );
    }

    if (mounted) setState(() => _isProcessing = false);
    Future.delayed(const Duration(seconds: 3), () {
      _lastScannedCode = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: widget.darkBg,
      appBar: AppBar(
        backgroundColor: widget.darkBg,
        elevation: 0,
        title: const Text(
          'Scan QR Code',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        centerTitle: true,
      ),
      body: Stack(
        children: [
          MobileScanner(
            controller: _controller,
            onDetect: _onDetect,
            errorBuilder: (context, error) => _buildCameraError(error),
          ),
          Center(
            child: Container(
              width: 280,
              height: 280,
              decoration: BoxDecoration(
                border: Border.all(
                  color: widget.primaryOrange.withOpacity(0.7),
                  width: 3,
                ),
                borderRadius: BorderRadius.circular(24),
              ),
              child: const SizedBox.expand(),
            ),
          ),
          if (_isProcessing)
            Container(
              color: Colors.black54,
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircularProgressIndicator(color: widget.primaryOrange),
                    SizedBox(height: 16),
                    Text(
                      'Saving check-in...',
                      style: TextStyle(color: Colors.white, fontSize: 16),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildCameraError(MobileScannerException error) {
    final isPermission =
        error.errorCode == MobileScannerErrorCode.permissionDenied;
    return Container(
      color: widget.darkBg,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                isPermission ? Icons.camera_alt_outlined : Icons.error_outline,
                size: 64,
                color: widget.primaryOrange,
              ),
              const SizedBox(height: 14),
              Text(
                isPermission
                    ? 'Camera permission required'
                    : 'Camera unavailable',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                isPermission
                    ? 'Allow camera access in your phone settings to scan QR codes.'
                    : (error.errorDetails?.message ?? error.errorCode.name),
                style: const TextStyle(color: Colors.white70, fontSize: 14),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 18),
              FilledButton.icon(
                onPressed: _startCamera,
                icon: const Icon(Icons.refresh),
                label: const Text('Try again'),
                style: FilledButton.styleFrom(
                  backgroundColor: widget.primaryOrange,
                  foregroundColor: Colors.white,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

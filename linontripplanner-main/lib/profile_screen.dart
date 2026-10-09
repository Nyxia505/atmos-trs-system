import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'data.dart';
import 'admin_dashboard_screen.dart';
import 'firestore_loader.dart';
import 'services/auth_roles.dart';
import 'services/spot_interaction_history.dart';
import 'services/tourism_session.dart';
import 'spot_detail_screen.dart';
import 'widgets/admin_access_gate.dart';
import 'mapping_screen.dart';
import 'municipality_list_screen.dart';
import 'widgets/municipality_image.dart';
import 'services/profile_photo_service.dart';
import 'widgets/profile_header_photo.dart';
import 'widgets/tourism_plan_ui.dart';
import 'trip_plan_host_bridge.dart';
import 'auth/auth_navigation.dart';
import 'auth/login_screen.dart';
import 'auth/registration_screen.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  int _photoReloadToken = 0;

  bool get _showAdminMenu {
    final appUser =
        findAppUserByFirebaseUid(FirebaseAuth.instance.currentUser?.uid);
    return AuthRoles.canAccessAdminDashboard(appUser);
  }

  List<TouristSpot> get _favoriteSpots {
    final keys = SpotInteractionHistoryStore.instance.favoritedKeys;
    if (keys.isEmpty) return const [];
    return allSpots
        .where((s) => keys.contains(normalizeTourismNameKey(s.name)))
        .toList();
  }

  void _openFavorites(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => const FavoriteSpotsScreen(),
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    SpotInteractionHistoryStore.instance.revision.addListener(_onHistoryChanged);
    if (!tourismIsGuestSession()) {
      _reloadProfileData();
    } else {
      SpotInteractionHistoryStore.instance.load();
    }
  }

  @override
  void dispose() {
    SpotInteractionHistoryStore.instance.revision
        .removeListener(_onHistoryChanged);
    super.dispose();
  }

  void _onHistoryChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _reloadProfileData() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    await ensureCurrentUserProfileInFirestore();
    if (uid != null && uid.isNotEmpty) {
      await syncProfilePhotoUrlForUid(uid);
    }
    await loadUsersFromFirestore();
    await SpotInteractionHistoryStore.instance.load();
    if (mounted) setState(() => _photoReloadToken++);
  }

  Future<void> _pickProfilePhoto(BuildContext context) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null || uid.isEmpty) return;

    final picked = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      maxWidth: 1200,
      imageQuality: 85,
    );
    if (picked == null) return;

    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Uploading photo…')),
    );

    final bytes = await picked.readAsBytes();
    final url = await uploadAndSaveProfilePhoto(uid: uid, bytes: bytes);
    if (!context.mounted) return;

    if (url == null || url.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Upload failed. Check connection and try again.'),
        ),
      );
      return;
    }

    await loadUsersFromFirestore();
    if (!context.mounted) return;
    setState(() => _photoReloadToken++);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Profile photo saved')),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.planPageBg,
      body: TourismPlanPageBody(
        child: SingleChildScrollView(
        child: Column(
          children: [
            Container(
              width: double.infinity,
              decoration: const BoxDecoration(
                gradient: TourismPlanUi.primaryGradient,
              ),
              child: SafeArea(
                bottom: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 20, 20, 30),
                  child: StreamBuilder<User?>(
                    stream: FirebaseAuth.instance.authStateChanges(),
                    builder: (context, snapshot) {
                      final auth = snapshot.data;
                      final appUser = findAppUserByFirebaseUid(auth?.uid);
                      final displayName =
                          appUser?.name ?? auth?.displayName ?? 'Guest';
                      final email = appUser?.email ?? auth?.email ?? '';

                      return Column(
                        children: [
                          Container(
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border: Border.all(color: Colors.white, width: 3),
                            ),
                            child: ProfileHeaderPhoto(
                              key: ValueKey(
                                '${auth?.uid ?? "guest"}_$_photoReloadToken',
                              ),
                              uid: auth?.uid,
                              initialPhotoPath: appUser?.profilePhotoPath,
                              authPhotoUrl: auth?.photoURL,
                              size: 88,
                              fallbackIconColor: AppColors.primary,
                              allowUpload: auth != null,
                              onPhotoChanged: () {
                                if (mounted) {
                                  setState(() => _photoReloadToken++);
                                }
                              },
                            ),
                          ),
                          const SizedBox(height: 14),
                          Text(
                            displayName,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            email,
                            style: const TextStyle(
                              color: Colors.white70,
                              fontSize: 13,
                            ),
                          ),
                          const SizedBox(height: 16),
                          ValueListenableBuilder<int>(
                            valueListenable:
                                SpotInteractionHistoryStore.instance.revision,
                            builder: (context, _, __) {
                              final favCount = _favoriteSpots.length;
                              return Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceEvenly,
                                children: [
                                  _StatChip(
                                    value: '${municipalities.length}',
                                    label: 'Municipalities',
                                    onTap: () => Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (_) =>
                                            const MunicipalityListScreen(),
                                      ),
                                    ),
                                  ),
                                  _StatChip(
                                    value: '$favCount',
                                    label: 'Favorites',
                                    onTap: () => _openFavorites(context),
                                  ),
                                ],
                              );
                            },
                          ),
                        ],
                      );
                    },
                  ),
                ),
              ),
            ),

            const SizedBox(height: 16),
            _buildMunicipalitiesSection(context),

            const SizedBox(height: 16),
            _buildSection(context, 'Account', [
              if (tourismIsGuestSession()) ...[
                _MenuItem(
                  Icons.login,
                  'Sign in',
                  onTap: () {
                    final open = TripPlanHostBridge.openSharedLogin;
                    if (TripPlanHostBridge.embeddedInAtmos && open != null) {
                      open(context);
                      return;
                    }
                    Navigator.of(context, rootNavigator: true).push(
                      MaterialPageRoute(
                        builder: (_) => const LoginScreen(),
                      ),
                    );
                  },
                ),
                _MenuItem(
                  Icons.app_registration_outlined,
                  'Create account',
                  onTap: () {
                    final open = TripPlanHostBridge.openSharedSignup;
                    if (TripPlanHostBridge.embeddedInAtmos && open != null) {
                      open(context);
                      return;
                    }
                    Navigator.of(context, rootNavigator: true).push(
                      MaterialPageRoute(
                        builder: (_) => const RegistrationScreen(),
                      ),
                    );
                  },
                ),
              ],
              _MenuItem(
                Icons.person_outline,
                'Edit Profile Photo',
                onTap: () => _pickProfilePhoto(context),
              ),
              _MenuItem(Icons.lock_outline, 'Change Password', onTap: () {}),
              _MenuItem(
                Icons.notifications_outlined,
                'Notification Settings',
                onTap: () {},
              ),
              if (_showAdminMenu)
                _MenuItem(
                  Icons.admin_panel_settings_outlined,
                  'Admin Dashboard',
                  onTap: () {
                    Navigator.of(context, rootNavigator: true).push(
                      MaterialPageRoute(
                        builder: (_) => const AdminAccessGate(
                          child: AdminDashboardScreen(),
                        ),
                      ),
                    );
                  },
                ),
            ]),
            const SizedBox(height: 12),
            _buildSection(context, 'Trips', [
              _MenuItem(
                Icons.bookmark_border,
                'Saved Places',
                onTap: () => _openFavorites(context),
              ),
              _MenuItem(Icons.history, 'Travel History', onTap: () {}),
              _MenuItem(Icons.star_border, 'My Reviews', onTap: () {}),
              _MenuItem(
                Icons.map_outlined,
                'Map & Routes',
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const MappingScreen()),
                  );
                },
              ),
            ]),
            const SizedBox(height: 12),
            _buildSection(context, 'Support', [
              _MenuItem(Icons.help_outline, 'Help & FAQ', onTap: () {}),
              _MenuItem(Icons.info_outline, 'About the App', onTap: () {}),
            if (!tourismIsGuestSession())
              _MenuItem(
                Icons.logout,
                'Logout',
                color: Colors.red.shade400,
                onTap: () => performTourismLogout(context),
              ),
            ]),
            const SizedBox(height: 24),
            const Text(
              'Misamis Occidental Tourism App v1.0',
              style: TextStyle(color: Color(0xFFAAAAAA), fontSize: 12),
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
      ),
    );
  }

  Widget _buildMunicipalitiesSection(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: [
              Expanded(
                child: TourismPlanUi.sectionTitleBar(title: 'Explore municipalities'),
              ),
              TextButton(
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const MunicipalityListScreen(),
                  ),
                ),
                child: const Text('See all'),
              ),
            ],
          ),
        ),
        const SizedBox(height: 4),
        SizedBox(
          height: 118,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: sortedMunicipalities.length,
            separatorBuilder: (_, __) => const SizedBox(width: 16),
            itemBuilder: (context, index) {
              final m = sortedMunicipalities[index];
              return TourismMunicipalityAvatar(
                label: m.shortName,
                size: 68,
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) =>
                        MunicipalityListScreen(selectedIndex: index),
                  ),
                ),
                image: buildMunicipalityImageForMunicipality(
                  m,
                  fallback: const Center(
                    child: Icon(
                      Icons.location_city_rounded,
                      color: AppColors.primary,
                      size: 28,
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildSection(
    BuildContext context,
    String title,
    List<_MenuItem> items,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: TourismPlanUi.sectionTitleBar(title: title),
        ),
        const SizedBox(height: 8),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: TourismPlanCard(
            padding: EdgeInsets.zero,
            child: Column(
              children: items.asMap().entries.map((entry) {
                final item = entry.value;
                final isLast = entry.key == items.length - 1;
                return Column(
                  children: [
                ListTile(
                  leading: Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: (item.color ?? AppColors.primary)
                          .withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(
                      item.icon,
                      color: item.color ?? AppColors.primary,
                      size: 22,
                    ),
                  ),
                  title: Text(
                    item.label,
                    style: TextStyle(
                      fontSize: 15,
                      color: item.color ?? AppColors.textDark,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  trailing: const Icon(
                    Icons.chevron_right_rounded,
                    color: AppColors.textGrey,
                    size: 22,
                  ),
                  onTap: item.onTap,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                if (!isLast)
                  Divider(
                    height: 1,
                    indent: 68,
                    endIndent: 16,
                    color: Colors.black.withValues(alpha: 0.06),
                  ),
                  ],
                );
              }).toList(),
            ),
          ),
        ),
      ],
    );
  }
}

class _StatChip extends StatelessWidget {
  final String value;
  final String label;
  final VoidCallback? onTap;
  const _StatChip({
    required this.value,
    required this.label,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final chip = Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withValues(alpha: 0.35)),
      ),
      child: Column(
        children: [
          Text(
            value,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 20,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.85),
              fontSize: 11,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
    if (onTap == null) return chip;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: chip,
      ),
    );
  }
}

/// Lists tourist spots the signed-in user favorited.
class FavoriteSpotsScreen extends StatefulWidget {
  const FavoriteSpotsScreen({super.key});

  @override
  State<FavoriteSpotsScreen> createState() => _FavoriteSpotsScreenState();
}

class _FavoriteSpotsScreenState extends State<FavoriteSpotsScreen> {
  List<TouristSpot> get _spots {
    final keys = SpotInteractionHistoryStore.instance.favoritedKeys;
    if (keys.isEmpty) return const [];
    return allSpots
        .where((s) => keys.contains(normalizeTourismNameKey(s.name)))
        .toList();
  }

  @override
  void initState() {
    super.initState();
    SpotInteractionHistoryStore.instance.revision.addListener(_onChanged);
  }

  @override
  void dispose() {
    SpotInteractionHistoryStore.instance.revision.removeListener(_onChanged);
    super.dispose();
  }

  void _onChanged() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final spots = _spots;
    return Scaffold(
      backgroundColor: AppColors.planPageBg,
      appBar: AppBar(
        title: const Text('My Favorites'),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
      ),
      body: spots.isEmpty
          ? const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'No favorites yet.\nOpen a spot and tap the heart to save it here.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: AppColors.textGrey,
                    fontSize: 15,
                    height: 1.4,
                  ),
                ),
              ),
            )
          : ListView.separated(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
              itemCount: spots.length,
              separatorBuilder: (_, __) => const SizedBox(height: 10),
              itemBuilder: (context, index) {
                final spot = spots[index];
                return TourismPlanCard(
                  padding: EdgeInsets.zero,
                  child: ListTile(
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    leading: ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: SizedBox(
                        width: 52,
                        height: 52,
                        child: buildTouristSpotProfileImage(
                          spot,
                          fallback: Container(
                            color: AppColors.primary.withValues(alpha: 0.12),
                            child: const Icon(
                              Icons.place_outlined,
                              color: AppColors.primary,
                            ),
                          ),
                        ),
                      ),
                    ),
                    title: Text(
                      spot.displayName,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        color: AppColors.textDark,
                      ),
                    ),
                    subtitle: Text(
                      spot.location,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: AppColors.textGrey,
                        fontSize: 13,
                      ),
                    ),
                    trailing: const Icon(
                      Icons.chevron_right_rounded,
                      color: AppColors.textGrey,
                    ),
                    onTap: () {
                      Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => SpotDetailScreen(spot: spot),
                        ),
                      );
                    },
                  ),
                );
              },
            ),
    );
  }
}

class _MenuItem {
  final IconData icon;
  final String label;
  final Color? color;
  final VoidCallback onTap;
  const _MenuItem(this.icon, this.label, {this.color, required this.onTap});
}

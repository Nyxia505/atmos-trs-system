import 'dart:convert';

import 'package:atmos_trs_system/config/app_theme.dart';
import 'package:atmos_trs_system/config/app_theme_controller.dart';
import 'package:atmos_trs_system/config/auth_config.dart';
import 'package:atmos_trs_system/config/session_storage.dart';
import 'package:atmos_trs_system/config/user_profile_storage.dart';
import 'package:atmos_trs_system/features/profile/widgets/profile_avatar.dart';
import 'package:atmos_trs_system/features/profile/widgets/profile_info_row.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:atmos_trs_system/services/profile_photo_hydration.dart';
import 'package:atmos_trs_system/services/tourist_profile_hydration.dart';
import 'package:atmos_trs_system/services/tourist_activity_firestore_sync.dart';
import 'package:atmos_trs_system/services/user_directory_service.dart';
import 'package:atmos_trs_system/services/push_notification_service.dart';
import 'package:atmos_trs_system/widgets/app_logout_button.dart';
import 'package:atmos_trs_system/features/profile/widgets/theme_color_picker_sheet.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Account tab — tourist profile.
class ProfileTabPage extends StatefulWidget {
  const ProfileTabPage({super.key});

  @override
  State<ProfileTabPage> createState() => _ProfileTabPageState();
}

class _ProfileTabPageState extends State<ProfileTabPage> {
  UserProfile? _userProfile = UserProfileStorage.cachedProfile;
  String? _touristId;
  bool _isRefreshing = UserProfileStorage.cachedProfile == null;
  bool _personalExpanded = false;
  bool _addressExpanded = false;
  bool _otpVerified = false;

  static const _textPrimary = Color(0xFF111827);
  static const _textMuted = Color(0xFF6B7280);
  static const _border = Color(0xFFE5E7EB);

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  Future<void> _loadProfile() async {
    final authUser = FirebaseAuth.instance.currentUser;
    var profile = await TouristProfileHydration.loadProfile(
      uid: AuthConfig.currentUserUid ?? authUser?.uid,
      email: authUser?.email,
    );
    profile = await ProfilePhotoHydration.mergeFirestorePhotoUrl(profile);
    final uid =
        AuthConfig.currentUserUid ??
        authUser?.uid ??
        await SessionStorage.getStoredUser();
    var otpVerified = false;
    if (uid != null && uid.isNotEmpty) {
      otpVerified = await UserDirectoryService.touristEmailVerificationComplete(
        uid,
      );
    }
    if (!mounted) return;
    setState(() {
      _userProfile = profile ?? UserProfileStorage.cachedProfile;
      final storedTouristId = _userProfile?.touristId.trim();
      _touristId = (storedTouristId != null && storedTouristId.isNotEmpty)
          ? storedTouristId
          : uid;
      _otpVerified = otpVerified;
      _isRefreshing = false;
    });
  }

  double _horizontalPadding(BuildContext context) {
    final w = MediaQuery.sizeOf(context).width;
    if (w >= 1100) return 48;
    if (w >= 600) return 28;
    return 20;
  }

  Future<bool> _confirmLogout(BuildContext context) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Log out?'),
        content: const Text('Are you sure you want to log out?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Log out'),
          ),
        ],
      ),
    );
    return result == true;
  }

  Future<void> _logout(BuildContext context) async {
    final confirmed = await _confirmLogout(context);
    if (!confirmed) return;
    await unregisterTouristPushTopic();
    await SessionStorage.clearSession();
    await UserProfileStorage.clearUserProfile();
    TouristActivityFirestoreSync.resetMergeCache();
    AuthConfig.currentUserUid = null;
    if (!context.mounted) return;
    Navigator.pushReplacementNamed(context, '/login');
  }

  void _openResetPassword(BuildContext context) {
    final email =
        FirebaseAuth.instance.currentUser?.email?.trim() ??
        _userProfile?.email.trim();
    Navigator.pushNamed(context, '/forgot-password', arguments: email ?? '');
  }

  void _showAboutDialog(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            Icon(
              Icons.info_outline_rounded,
              color: Theme.of(ctx).colorScheme.primary,
            ),
            const SizedBox(width: 10),
            const Text('About ATMOS-TRS'),
          ],
        ),
        content: const Text(
          'ATMOS-TRS - Asenso Tourismo Misamis Occidental Smart Tourist Registration System.\n\n'
          'Register as a tourist, explore destinations, scan QR at LGU checkpoints, '
          'and manage your digital tourist ID.',
          style: TextStyle(height: 1.45),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  void _showPrivacyInfo(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            Icon(
              Icons.shield_outlined,
              color: Theme.of(ctx).colorScheme.primary,
            ),
            const SizedBox(width: 10),
            const Text('Privacy'),
          ],
        ),
        content: const Text(
          'Your profile powers your tourist ID, QR check-ins, and account '
          'verification. Data is stored securely with your Firebase account.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final profile = _userProfile;
    final pad = _horizontalPadding(context);
    final touristId = _touristId ?? profile?.touristId ?? '—';
    final isLocal = profile?.nationality == 'Filipino';
    final email =
        FirebaseAuth.instance.currentUser?.email?.trim() ??
        profile?.email ??
        '—';

    return ListenableBuilder(
      listenable: AppThemeController.instance,
      builder: (context, _) {
        return Scaffold(
          backgroundColor: Colors.white,
          body: SafeArea(
            child: Column(
              children: [
                Padding(
                  padding: EdgeInsets.fromLTRB(pad, 12, pad, 4),
                  child: _buildPageHeader(context),
                ),
                Expanded(
                  child: RefreshIndicator(
                    color: AppTheme.primary,
                    onRefresh: _loadProfile,
                    child: SingleChildScrollView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: EdgeInsets.fromLTRB(pad, 12, pad, 24),
                      child: Column(
                        children: [
                          _buildTouristIdentityCard(
                            profile,
                            touristId,
                            isLocal,
                            _otpVerified,
                          ),
                          const SizedBox(height: 20),
                          ProfileSectionCard(
                            title: 'Contact',
                            subtitle: 'Reach you for account & travel updates',
                            icon: Icons.contact_phone_outlined,
                            children: [
                              ProfileInfoRow(
                                label: 'Mobile number',
                                value: profile?.mobile ?? '—',
                                icon: Icons.phone_outlined,
                              ),
                              ProfileInfoRow(
                                label: 'Email address',
                                value: email,
                                icon: Icons.email_outlined,
                              ),
                            ],
                          ),
                          const SizedBox(height: 20),
                          _buildExpandableSection(
                            icon: Icons.badge_outlined,
                            title: 'Personal info',
                            subtitle: 'Registration details on your tourist ID',
                            expanded: _personalExpanded,
                            onToggle: () => setState(
                              () => _personalExpanded = !_personalExpanded,
                            ),
                            children: [
                              ProfileInfoRow(
                                label: 'First name',
                                value: profile?.firstName ?? '—',
                                dense: true,
                              ),
                              ProfileInfoRow(
                                label: 'Middle name',
                                value: profile?.middleName ?? '—',
                                dense: true,
                              ),
                              ProfileInfoRow(
                                label: 'Last name',
                                value: profile?.lastName ?? '—',
                                dense: true,
                              ),
                              ProfileInfoRow(
                                label: 'Sex',
                                value: profile?.sex ?? '—',
                                dense: true,
                              ),
                              ProfileInfoRow(
                                label: 'Civil status',
                                value: profile?.civilStatus ?? '—',
                                dense: true,
                              ),
                              ProfileInfoRow(
                                label: 'Nationality',
                                value: profile?.nationality ?? '—',
                                dense: true,
                              ),
                              ProfileInfoRow(
                                label: 'Date of birth',
                                value: profile?.dateOfBirth ?? '—',
                                dense: true,
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          _buildExpandableSection(
                            icon: Icons.location_on_outlined,
                            title: 'Address',
                            subtitle: 'Home or stay address on file',
                            expanded: _addressExpanded,
                            onToggle: () => setState(
                              () => _addressExpanded = !_addressExpanded,
                            ),
                            children: [
                              if (profile?.fullAddress.isNotEmpty == true)
                                ProfileInfoRow(
                                  label: 'Full address',
                                  value: profile!.fullAddress,
                                  maxLines: 4,
                                  dense: true,
                                )
                              else ...[
                                ProfileInfoRow(
                                  label: 'Street',
                                  value: profile?.street ?? '—',
                                  dense: true,
                                ),
                                ProfileInfoRow(
                                  label: 'Barangay',
                                  value: profile?.barangay ?? '—',
                                  dense: true,
                                ),
                                ProfileInfoRow(
                                  label: 'City / municipality',
                                  value: profile?.city ?? '—',
                                  dense: true,
                                ),
                                ProfileInfoRow(
                                  label: 'Province',
                                  value: profile?.province ?? '—',
                                  dense: true,
                                ),
                                ProfileInfoRow(
                                  label: 'Country',
                                  value: profile?.country ?? '—',
                                  dense: true,
                                ),
                              ],
                            ],
                          ),
                          const SizedBox(height: 24),
                          AppLogoutButton(
                            style: AppLogoutStyle.solidPill,
                            expanded: true,
                            fullWidth: true,
                            onPressed: () => _logout(context),
                          ),
                          SizedBox(
                            height: MediaQuery.paddingOf(context).bottom + 16,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildPageHeader(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: accent.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Icon(Icons.person_rounded, color: accent, size: 26),
        ),
        const SizedBox(width: 12),
        const Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'My Account',
                style: TextStyle(
                  color: _textPrimary,
                  fontSize: 24,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.4,
                  height: 1.15,
                ),
              ),
              SizedBox(height: 2),
              Text(
                'Profile & tourist ID',
                style: TextStyle(color: _textMuted, fontSize: 13, height: 1.35),
              ),
            ],
          ),
        ),
        _buildSettingsMenu(context),
      ],
    );
  }

  Widget _buildSettingsMenu(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;

    return Tooltip(
      message: 'Settings',
      child: Material(
        color: accent.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        child: PopupMenuButton<String>(
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(minWidth: 42, minHeight: 42),
          icon: Icon(Icons.settings_outlined, color: accent, size: 22),
          iconSize: 22,
          offset: const Offset(0, 44),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          onSelected: (value) {
            switch (value) {
              case 'theme':
                ThemeColorPickerSheet.show(context);
              case 'reset_password':
                _openResetPassword(context);
              case 'privacy':
                _showPrivacyInfo(context);
              case 'about':
                _showAboutDialog(context);
            }
          },
          itemBuilder: (menuContext) {
            final menuAccent = Theme.of(menuContext).colorScheme.primary;
            return [
              _settingsMenuRow(
                value: 'theme',
                icon: Icons.palette_outlined,
                title: 'Theme color',
                subtitle: 'Change app accent color',
                accent: menuAccent,
              ),
              const PopupMenuDivider(),
              _settingsMenuRow(
                value: 'reset_password',
                icon: Icons.lock_outline_rounded,
                title: 'Reset password',
                subtitle: 'Change your sign-in password',
                accent: menuAccent,
              ),
              _settingsMenuRow(
                value: 'privacy',
                icon: Icons.shield_outlined,
                title: 'Privacy',
                subtitle: 'How your data is used',
                accent: menuAccent,
              ),
              _settingsMenuRow(
                value: 'about',
                icon: Icons.info_outline_rounded,
                title: 'About ATMOS-TRS',
                subtitle: 'App information',
                accent: menuAccent,
              ),
            ];
          },
        ),
      ),
    );
  }

  PopupMenuItem<String> _settingsMenuRow({
    required String value,
    required IconData icon,
    required String title,
    required String subtitle,
    required Color accent,
  }) {
    return PopupMenuItem<String>(
      value: value,
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: accent.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: accent, size: 20),
          ),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  color: _textPrimary,
                ),
              ),
              Text(
                subtitle,
                style: const TextStyle(fontSize: 12, color: _textMuted),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildTouristIdentityCard(
    UserProfile? profile,
    String touristId,
    bool isLocal,
    bool otpVerified,
  ) {
    final accent = AppTheme.primary;
    final onHeader = AppTheme.onPrimary;

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: accent.withValues(alpha: 0.35)),
        boxShadow: [
          BoxShadow(
            color: accent.withValues(alpha: 0.1),
            blurRadius: 14,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
            color: accent,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                ProfileAvatar(
                  profile: profile,
                  size: 64,
                  ringWidth: 2.5,
                  ringColor: onHeader,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        profile?.fullName ?? 'Guest',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w800,
                          color: onHeader,
                          height: 1.2,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          _statusChipOnAccent(
                            isLocal ? 'Local tourist' : 'Foreign tourist',
                            Icons.public_rounded,
                            onHeader: onHeader,
                          ),
                          if (otpVerified)
                            _statusChipOnAccent(
                              'Email verified',
                              Icons.verified_rounded,
                              onHeader: onHeader,
                              success: true,
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildTouristIdTile(touristId, dense: true),
                const SizedBox(height: 12),
                Center(child: _buildCompactQr(touristId, profile)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCompactQr(String touristId, UserProfile? profile) {
    final accent = AppTheme.primary;
    final id = touristId.trim().isNotEmpty
        ? touristId.trim()
        : (profile?.touristId ?? '').trim();
    if (id.isEmpty) {
      return SizedBox(
        width: 96,
        child: Text(
          'QR pending',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 11, color: accent.withValues(alpha: 0.6)),
        ),
      );
    }
    final payload = jsonEncode(<String, String>{
      'type': 'tourist',
      'tourist_id': id,
    });
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          'Scan QR',
          style: TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w700,
            color: accent,
          ),
        ),
        const SizedBox(height: 4),
        Container(
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: const Color(0xFFE5E7EB)),
          ),
          child: QrImageView(
            data: payload,
            version: QrVersions.auto,
            size: 96,
            backgroundColor: Colors.white,
            errorCorrectionLevel: QrErrorCorrectLevel.H,
          ),
        ),
      ],
    );
  }

  Widget _statusChipOnAccent(
    String label,
    IconData icon, {
    required Color onHeader,
    bool success = false,
  }) {
    final fg = success ? const Color(0xFFD1FAE5) : onHeader;
    final bg = success
        ? const Color(0xFF059669).withValues(alpha: 0.35)
        : onHeader.withValues(alpha: 0.18);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: fg.withValues(alpha: 0.45)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: fg),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              color: fg,
              fontSize: 11,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTouristIdTile(String touristId, {bool dense = false}) {
    final accent = AppTheme.primary;
    return Container(
      width: double.infinity,
      padding: EdgeInsets.symmetric(
        horizontal: dense ? 10 : 14,
        vertical: dense ? 8 : 12,
      ),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(dense ? 12 : 14),
        border: Border.all(color: accent.withValues(alpha: 0.28)),
      ),
      child: Row(
        children: [
          Container(
            padding: EdgeInsets.all(dense ? 6 : 8),
            decoration: BoxDecoration(
              color: accent.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(
              Icons.badge_outlined,
              size: dense ? 18 : 20,
              color: accent,
            ),
          ),
          SizedBox(width: dense ? 10 : 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Tourist ID',
                  style: TextStyle(
                    fontSize: dense ? 10 : 11,
                    fontWeight: FontWeight.w600,
                    color: _textMuted,
                  ),
                ),
                const SizedBox(height: 1),
                Text(
                  touristId,
                  style: TextStyle(
                    fontSize: dense ? 13 : 14,
                    fontWeight: FontWeight.w700,
                    color: _textPrimary,
                    letterSpacing: 0.15,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          if (touristId != '—')
            Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: () {
                  Clipboard.setData(ClipboardData(text: touristId));
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Tourist ID copied'),
                      behavior: SnackBarBehavior.floating,
                    ),
                  );
                },
                borderRadius: BorderRadius.circular(8),
                child: Padding(
                  padding: EdgeInsets.symmetric(
                    horizontal: dense ? 8 : 10,
                    vertical: dense ? 6 : 8,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.copy_rounded, size: 15, color: accent),
                      const SizedBox(width: 4),
                      Text(
                        'Copy',
                        style: TextStyle(
                          color: accent,
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildExpandableSection({
    required IconData icon,
    required String title,
    String? subtitle,
    required bool expanded,
    required VoidCallback onToggle,
    required List<Widget> children,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Material(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onToggle,
            child: Container(
              decoration: BoxDecoration(
                border: Border.all(
                  color: expanded ? AppTheme.primary : _border,
                  width: expanded ? 1.5 : 1,
                ),
                borderRadius: BorderRadius.circular(18),
                boxShadow: expanded
                    ? [
                        BoxShadow(
                          color: AppTheme.primary.withValues(alpha: 0.08),
                          blurRadius: 12,
                          offset: const Offset(0, 4),
                        ),
                      ]
                    : [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.03),
                          blurRadius: 8,
                          offset: const Offset(0, 2),
                        ),
                      ],
              ),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: AppTheme.primary.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(icon, size: 20, color: AppTheme.primary),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: _textPrimary,
                          ),
                        ),
                        if (subtitle != null) ...[
                          const SizedBox(height: 2),
                          Text(
                            subtitle,
                            style: const TextStyle(
                              fontSize: 12,
                              color: _textMuted,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  AnimatedRotation(
                    turns: expanded ? 0.5 : 0,
                    duration: const Duration(milliseconds: 200),
                    child: Icon(
                      Icons.keyboard_arrow_down_rounded,
                      color: Theme.of(context).colorScheme.primary,
                      size: 28,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        AnimatedCrossFade(
          firstChild: const SizedBox.shrink(),
          secondChild: Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: _border),
              ),
              clipBehavior: Clip.antiAlias,
              child: Column(
                children: [
                  for (var i = 0; i < children.length; i++) ...[
                    if (i > 0)
                      const Divider(
                        height: 1,
                        thickness: 1,
                        color: Color(0xFFF3F4F6),
                      ),
                    children[i],
                  ],
                ],
              ),
            ),
          ),
          crossFadeState: expanded
              ? CrossFadeState.showSecond
              : CrossFadeState.showFirst,
          duration: const Duration(milliseconds: 220),
          sizeCurve: Curves.easeOut,
        ),
      ],
    );
  }
}

import 'dart:convert';

import 'package:atmos_trs_system/config/app_theme.dart';
import 'package:atmos_trs_system/services/push_notification_service.dart';
import 'package:atmos_trs_system/widgets/app_logout_button.dart';
import 'package:atmos_trs_system/config/auth_config.dart';
import 'package:atmos_trs_system/config/session_storage.dart';
import 'package:atmos_trs_system/config/user_profile_storage.dart';
import 'package:atmos_trs_system/screens/qr_profile_screen.dart';
import 'package:atmos_trs_system/services/profile_photo_hydration.dart';
import 'package:atmos_trs_system/services/user_activity_service.dart' as activity;
import 'package:atmos_trs_system/utils/email_utils.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

/// Account tab: tourist profile — Asenso orange + cream, card-based layout.
class ProfileTabPage extends StatefulWidget {
  const ProfileTabPage({super.key});

  @override
  State<ProfileTabPage> createState() => _ProfileTabPageState();
}

class _ProfileTabPageState extends State<ProfileTabPage> {
  UserProfile? _userProfile;
  bool _isLoading = true;
  List<activity.VisitRecord> _visits = [];
  List<activity.Badge> _badges = [];

  static const Color _textPrimary = Color(0xFF111827);
  static const Color _textMuted = Color(0xFF6B7280);

  @override
  void initState() {
    super.initState();
    _loadAllProfileData();
  }

  Future<void> _loadAllProfileData() async {
    var profile = await UserProfileStorage.getUserProfile();
    profile = await ProfilePhotoHydration.mergeFirestorePhotoUrl(profile);
    final visits = await activity.UserActivityService.getVisitedSpots();
    final badges = await activity.UserActivityService.getEarnedBadges();
    if (mounted) {
      setState(() {
        _userProfile = profile;
        _visits = visits;
        _badges = badges;
        _isLoading = false;
      });
    }
  }

  double _horizontalPadding(BuildContext context) {
    final w = MediaQuery.sizeOf(context).width;
    if (w >= 1100) return 48;
    if (w >= 600) return 28;
    return 20;
  }

  Future<void> _logout(BuildContext context) async {
    await unregisterTouristPushTopic();
    await SessionStorage.clearSession();
    await UserProfileStorage.clearUserProfile();
    AuthConfig.currentUserUid = null;
    if (!context.mounted) return;
    Navigator.pushReplacementNamed(context, '/login');
  }

  @override
  Widget build(BuildContext context) {
    final pad = _horizontalPadding(context);

    if (_isLoading) {
      return Scaffold(
        backgroundColor: AppTheme.scaffoldBackground,
        body: const Center(
          child: CircularProgressIndicator(color: AppTheme.primary),
        ),
      );
    }

    final profile = _userProfile;

    return Scaffold(
      backgroundColor: AppTheme.scaffoldBackground,
      body: RefreshIndicator(
        color: AppTheme.primary,
        edgeOffset: 120,
        onRefresh: () async {
          var p = await UserProfileStorage.getUserProfile();
          p = await ProfilePhotoHydration.mergeFirestorePhotoUrl(p);
          final visits = await activity.UserActivityService.getVisitedSpots();
          final badges = await activity.UserActivityService.getEarnedBadges();
          if (mounted) {
            setState(() {
              _userProfile = p;
              _visits = visits;
              _badges = badges;
            });
          }
        },
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            SliverToBoxAdapter(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _buildGradientHeader(context),
                  Transform.translate(
                    offset: const Offset(0, -52),
                    child: Padding(
                      padding: EdgeInsets.symmetric(horizontal: pad),
                      child: _buildIdentityCard(profile),
                    ),
                  ),
                  Padding(
                    padding: EdgeInsets.fromLTRB(pad, 0, pad, 24),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _buildQrCard(context, profile),
                        const SizedBox(height: 20),
                        _buildStatsRow(),
                        const SizedBox(height: 24),
                        _sectionLabel('My visits'),
                        const SizedBox(height: 10),
                        _buildVisitsCard(),
                        const SizedBox(height: 24),
                        _sectionLabel('Badges'),
                        const SizedBox(height: 10),
                        _buildBadgesSection(),
                        const SizedBox(height: 24),
                        _sectionLabel('Account'),
                        const SizedBox(height: 10),
                        _buildSettingsCard(context),
                        const SizedBox(height: 20),
                        _buildLogoutButton(context),
                        SizedBox(height: MediaQuery.paddingOf(context).bottom + 24),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildGradientHeader(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.fromLTRB(
        20,
        MediaQuery.paddingOf(context).top + 8,
        20,
        72,
      ),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [AppTheme.primary, AppTheme.primaryDark],
        ),
        borderRadius: BorderRadius.vertical(bottom: Radius.circular(28)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'My profile',
            style: TextStyle(
              color: Colors.white,
              fontSize: 28,
              fontWeight: FontWeight.w800,
              height: 1.1,
              letterSpacing: -0.5,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Your tourist ID, visits, and rewards',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.88),
              fontSize: 14,
              height: 1.35,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildIdentityCard(UserProfile? profile) {
    return Material(
      elevation: 0,
      color: Colors.white,
      shadowColor: Colors.black26,
      borderRadius: BorderRadius.circular(22),
      child: Container(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 20),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(22),
          boxShadow: [
            BoxShadow(
              color: AppTheme.primary.withValues(alpha: 0.12),
              blurRadius: 24,
              offset: const Offset(0, 10),
            ),
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.06),
              blurRadius: 16,
              offset: const Offset(0, 4),
            ),
          ],
          border: Border.all(color: AppTheme.primary.withValues(alpha: 0.08)),
        ),
        child: Column(
          children: [
            _buildAvatar(profile, size: 88),
            const SizedBox(height: 14),
            Text(
              profile?.fullName ?? 'Guest',
              style: const TextStyle(
                color: _textPrimary,
                fontSize: 22,
                fontWeight: FontWeight.w800,
                height: 1.15,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 6),
            Text(
              _maskedEmailLine(profile?.email),
              style: const TextStyle(color: _textMuted, fontSize: 14),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 14),
            Wrap(
              alignment: WrapAlignment.center,
              spacing: 8,
              runSpacing: 8,
              children: [
                _chip(
                  profile?.nationality == 'Filipino' ? 'Local' : 'Tourist',
                ),
                _chip('Explorer'),
              ],
            ),
            const SizedBox(height: 18),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () => _showPersonalDetailsSheet(context),
                icon: const Icon(Icons.edit_outlined, size: 18),
                label: const Text('View & edit details'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppTheme.primary,
                  side: BorderSide(color: AppTheme.primary.withValues(alpha: 0.5)),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _chip(String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: AppTheme.primary.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppTheme.primary.withValues(alpha: 0.25)),
      ),
      child: Text(
        label,
        style: const TextStyle(
          color: AppTheme.primary,
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  Widget _buildAvatar(UserProfile? profile, {double size = 88}) {
    final url = profile?.profilePhotoUrl?.trim();
    Widget child;
    if (url != null && url.isNotEmpty) {
      child = ClipOval(
        child: Image.network(
          url,
          width: size,
          height: size,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => _avatarFallback(profile, size),
        ),
      );
    } else {
      child = _avatarFallback(profile, size);
    }
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          colors: [AppTheme.primary, AppTheme.primary.withValues(alpha: 0.75)],
        ),
      ),
      child: Container(
        padding: const EdgeInsets.all(2),
        decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
        child: ClipOval(child: child),
      ),
    );
  }

  Widget _avatarFallback(UserProfile? profile, double size) {
    final b64 = profile?.profileImageBase64;
    if (b64 != null && b64.isNotEmpty) {
      return Image.memory(
        base64Decode(b64),
        width: size,
        height: size,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => _placeholderAvatar(size),
      );
    }
    return _placeholderAvatar(size);
  }

  Widget _placeholderAvatar(double size) {
    return Container(
      width: size,
      height: size,
      color: const Color(0xFFFFFBEB),
      child: Icon(Icons.person_rounded, size: size * 0.5, color: AppTheme.unselectedMuted),
    );
  }

  Widget _buildQrCard(BuildContext context, UserProfile? profile) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () async {
          final uid = AuthConfig.currentUserUid ?? await SessionStorage.getStoredUser();
          if (!context.mounted) return;
          await Navigator.push<void>(
            context,
            MaterialPageRoute<void>(
              builder: (context) => QrProfileScreen(
                touristId: uid ?? profile?.touristId ?? 'N/A',
                fullName: profile?.fullName ?? 'Guest',
                location: profile?.fullAddress ?? 'Philippines',
                isAfterRegistration: false,
              ),
            ),
          );
        },
        borderRadius: BorderRadius.circular(18),
        child: Ink(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [AppTheme.primary, AppTheme.primary.withValues(alpha: 0.88)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(18),
            boxShadow: [
              BoxShadow(
                color: AppTheme.primary.withValues(alpha: 0.35),
                blurRadius: 16,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Icon(Icons.qr_code_2_rounded, color: Colors.white, size: 30),
              ),
              const SizedBox(width: 16),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'My tourist QR',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    SizedBox(height: 4),
                    Text(
                      'Show your ID at checkpoints & attractions',
                      style: TextStyle(color: Colors.white70, fontSize: 13, height: 1.3),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right_rounded, color: Colors.white.withValues(alpha: 0.9), size: 28),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStatsRow() {
    return Row(
      children: [
        Expanded(
          child: _statTile(
            Icons.route_rounded,
            '${_visits.length}',
            'Visits',
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _statTile(
            Icons.emoji_events_rounded,
            '${_badges.length}',
            'Badges',
          ),
        ),
      ],
    );
  }

  Widget _statTile(IconData icon, String value, String label) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade200),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          Icon(icon, color: AppTheme.primary, size: 26),
          const SizedBox(height: 8),
          Text(
            value,
            style: const TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w800,
              color: _textPrimary,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: TextStyle(fontSize: 12, color: Colors.grey.shade600, fontWeight: FontWeight.w500),
          ),
        ],
      ),
    );
  }

  Widget _sectionLabel(String title) {
    return Row(
      children: [
        Container(
          width: 4,
          height: 18,
          decoration: BoxDecoration(
            color: AppTheme.primary,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 10),
        Text(
          title,
          style: const TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w800,
            color: _textPrimary,
            letterSpacing: -0.2,
          ),
        ),
      ],
    );
  }

  Widget _buildVisitsCard() {
    final dateFormat = DateFormat('MMM d, yyyy');
    if (_visits.isEmpty) {
      return _emptyCard(
        icon: Icons.map_outlined,
        title: 'No visits yet',
        subtitle: 'Scan spot QR codes across Misamis Occidental to build your travel history.',
      );
    }
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade200),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: ListView.separated(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        itemCount: _visits.length > 5 ? 5 : _visits.length,
        separatorBuilder: (_, __) => Divider(height: 1, color: Colors.grey.shade100),
        itemBuilder: (context, index) {
          final v = _visits[index];
          return ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            leading: CircleAvatar(
              backgroundColor: AppTheme.primary.withValues(alpha: 0.12),
              child: const Icon(Icons.place_rounded, color: AppTheme.primary, size: 22),
            ),
            title: Text(
              v.spotName,
              style: const TextStyle(
                fontWeight: FontWeight.w600,
                fontSize: 15,
                color: _textPrimary,
              ),
            ),
            subtitle: Text(
              '${v.category} · ${dateFormat.format(v.visitedAt)}',
              style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
            ),
          );
        },
      ),
    );
  }

  Widget _buildBadgesSection() {
    if (_badges.isEmpty) {
      return _emptyCard(
        icon: Icons.military_tech_outlined,
        title: 'No badges yet',
        subtitle: 'Check in at more destinations to unlock achievements.',
      );
    }
    return SizedBox(
      height: 118,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: _badges.length,
        separatorBuilder: (_, __) => const SizedBox(width: 12),
        itemBuilder: (context, index) {
          final b = _badges[index];
          return Container(
            width: 156,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.grey.shade200),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.04),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(_mapBadgeIcon(b.icon), color: AppTheme.primary, size: 22),
                const SizedBox(height: 8),
                Text(
                  b.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                    color: _textPrimary,
                  ),
                ),
                const SizedBox(height: 4),
                Expanded(
                  child: Text(
                    b.description,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 11, color: Colors.grey.shade600, height: 1.25),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _emptyCard({
    required IconData icon,
    required String title,
    required String subtitle,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Row(
        children: [
          Icon(icon, size: 36, color: AppTheme.unselectedMuted),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 15,
                    color: _textPrimary,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: TextStyle(fontSize: 13, color: Colors.grey.shade600, height: 1.35),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  IconData _mapBadgeIcon(String icon) {
    switch (icon) {
      case 'explore':
        return Icons.explore_rounded;
      case 'emoji_events':
        return Icons.emoji_events_rounded;
      case 'military_tech':
        return Icons.military_tech_rounded;
      case 'workspace_premium':
        return Icons.workspace_premium_rounded;
      default:
        return Icons.star_rounded;
    }
  }

  Widget _buildSettingsCard(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        children: [
          _tile(
            icon: Icons.shield_outlined,
            title: 'Privacy',
            subtitle: 'Data & account security',
            onTap: () {},
          ),
          Divider(height: 1, color: Colors.grey.shade100),
          _tile(
            icon: Icons.lock_outline_rounded,
            title: 'Password',
            subtitle: 'Change password in Firebase / reset email',
            onTap: () {},
          ),
        ],
      ),
    );
  }

  Widget _tile({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return ListTile(
      onTap: onTap,
      leading: CircleAvatar(
        backgroundColor: AppTheme.primary.withValues(alpha: 0.1),
        child: Icon(icon, color: AppTheme.primary, size: 22),
      ),
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600, color: _textPrimary)),
      subtitle: Text(subtitle, style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
      trailing: Icon(Icons.chevron_right_rounded, color: Colors.grey.shade400),
    );
  }

  Widget _buildLogoutButton(BuildContext context) {
    return AppLogoutButton(
      style: AppLogoutStyle.solidPill,
      expanded: true,
      fullWidth: true,
      onPressed: () => _logout(context),
    );
  }

  void _showPersonalDetailsSheet(BuildContext context) {
    final profile = _userProfile;
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.72,
        minChildSize: 0.45,
        maxChildSize: 0.95,
        builder: (context, scrollController) => Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
          ),
          child: Column(
            children: [
              const SizedBox(height: 10),
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
                child: Row(
                  children: [
                    Icon(Icons.person_rounded, color: AppTheme.primary, size: 26),
                    const SizedBox(width: 10),
                    const Text(
                      'Your details',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                        color: _textPrimary,
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: ListView(
                  controller: scrollController,
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
                  children: [
                    _sheetSection('Personal', Icons.badge_outlined),
                    const SizedBox(height: 12),
                    _buildPersonalInfoSection(profile),
                    const SizedBox(height: 22),
                    _sheetSection('Contact & address', Icons.contact_mail_outlined),
                    const SizedBox(height: 12),
                    _buildContactSection(profile),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _sheetSection(String title, IconData icon) {
    return Row(
      children: [
        Icon(icon, size: 18, color: AppTheme.unselectedMuted),
        const SizedBox(width: 8),
        Text(
          title,
          style: const TextStyle(
            fontWeight: FontWeight.w700,
            fontSize: 14,
            color: _textMuted,
          ),
        ),
      ],
    );
  }

  Widget _buildPersonalInfoSection(UserProfile? profile) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Shown on your tourist ID and travel records.',
          style: TextStyle(fontSize: 12, color: _textMuted, height: 1.35),
        ),
        const SizedBox(height: 14),
        _field('First name', profile?.firstName ?? '—'),
        _field('Middle name', profile?.middleName ?? '—'),
        _field('Last name', profile?.lastName ?? '—'),
        Row(
          children: [
            Expanded(child: _field('Sex', profile?.sex ?? '—')),
            const SizedBox(width: 12),
            Expanded(child: _field('Civil status', profile?.civilStatus ?? '—')),
          ],
        ),
        _field('Nationality', profile?.nationality ?? '—'),
        _field('Date of birth', profile?.dateOfBirth ?? '—'),
      ],
    );
  }

  Widget _buildContactSection(UserProfile? profile) {
    return Column(
      children: [
        _field('Mobile', profile?.mobile ?? '—', icon: Icons.phone_outlined),
        _field('Email', _maskedEmailLine(profile?.email), icon: Icons.email_outlined),
        _field(
          'Address',
          profile?.fullAddress.isNotEmpty == true ? profile!.fullAddress : '—',
          icon: Icons.location_on_outlined,
          maxLines: 3,
        ),
      ],
    );
  }

  Widget _field(String label, String value, {IconData? icon, int maxLines = 1}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label.toUpperCase(),
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.6,
              color: Colors.grey.shade500,
            ),
          ),
          const SizedBox(height: 6),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: const Color(0xFFFFFBEB),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFFFE0B2)),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (icon != null) ...[
                  Icon(icon, size: 18, color: AppTheme.unselectedMuted),
                  const SizedBox(width: 8),
                ],
                Expanded(
                  child: Text(
                    value,
                    style: const TextStyle(
                      color: _textPrimary,
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                    ),
                    maxLines: maxLines,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _maskedEmailLine(String? email) {
    final e = email?.trim();
    if (e == null || e.isEmpty) return '—';
    return maskEmailForDisplay(e);
  }
}

import 'package:atmos_trs_system/config/app_theme.dart';
import 'package:atmos_trs_system/models/tourist_group.dart';
import 'package:atmos_trs_system/services/tourist_group_service.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';

/// "Laag with Friends": travel as a barkada / family and check in with one scan.
class LaagWithFriendsScreen extends StatefulWidget {
  const LaagWithFriendsScreen({super.key});

  @override
  State<LaagWithFriendsScreen> createState() => _LaagWithFriendsScreenState();
}

class _LaagWithFriendsScreenState extends State<LaagWithFriendsScreen> {
  static const Color _textDark = Color(0xFF111827);
  final _codeCtrl = TextEditingController();
  late final Stream<TouristGroup?> _groupStream;
  bool _busy = false;

  String get _uid => FirebaseAuth.instance.currentUser?.uid ?? '';

  @override
  void initState() {
    super.initState();
    _groupStream = TouristGroupService.watchMyActiveGroup();
    // Ends / leaves expired groups so the live query stays clean.
    TouristGroupService.myActiveGroup();
  }

  @override
  void dispose() {
    _codeCtrl.dispose();
    super.dispose();
  }

  void _snack(String msg, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        behavior: SnackBarBehavior.floating,
        backgroundColor: error ? Colors.red.shade700 : null,
      ),
    );
  }

  Future<void> _run(Future<void> Function() action) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action();
    } on TouristGroupException catch (e) {
      _snack(e.message, error: true);
    } catch (e) {
      _snack('Something went wrong. Check your connection and try again.',
          error: true);
      debugPrint('[LaagWithFriends] $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _createGroup() async {
    final nameCtrl = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Create a group'),
        content: TextField(
          controller: nameCtrl,
          autofocus: true,
          maxLength: 60,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(
            labelText: 'Group name',
            hintText: 'e.g. Barkada Oroquieta Trip',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, nameCtrl.text),
            child: const Text('Create'),
          ),
        ],
      ),
    );
    nameCtrl.dispose();
    if (name == null) return;
    await _run(() async {
      await TouristGroupService.createGroup(name);
      _snack('Group created! Let your friends scan your group QR.');
    });
  }

  Future<void> _joinWithCode() async {
    final code = TouristGroupService.normalizeCode(_codeCtrl.text);
    if (code.length != 6) {
      _snack('Enter the 6-character group code.', error: true);
      return;
    }
    await _run(() async {
      final group = await TouristGroupService.findByCode(code);
      if (group == null) {
        throw const TouristGroupException(
          'No active group with that code. Check the code with your friend.',
        );
      }
      if (!mounted) return;
      final ok = await confirmJoinTouristGroup(context, group, joinNow: false);
      if (!ok) return;
      await TouristGroupService.join(group);
      _codeCtrl.clear();
      _snack('You joined ${group.name}!');
    });
  }

  Future<void> _leaveOrEnd(TouristGroup group) async {
    final leader = group.isLeader(_uid);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(leader ? 'End this group?' : 'Leave this group?'),
        content: Text(
          leader
              ? 'Everyone will be removed from ${group.name}.'
              : 'You will no longer be checked in with ${group.name}.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red.shade700),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(leader ? 'End group' : 'Leave'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await _run(() => TouristGroupService.leave(group));
  }

  Future<void> _removeMember(TouristGroup group, TouristGroupMember m) async {
    await _run(() => TouristGroupService.removeMember(group, m.uid));
  }

  @override
  Widget build(BuildContext context) {
    final barBg = AppTheme.cardBackground;
    final barFg = ThemeData.estimateBrightnessForColor(barBg) == Brightness.dark
        ? Colors.white
        : _textDark;
    return Scaffold(
      backgroundColor: AppTheme.scaffoldBackground,
      appBar: AppBar(
        title: const Text('Laag with Friends'),
        backgroundColor: barBg,
        foregroundColor: barFg,
      ),
      body: StreamBuilder<TouristGroup?>(
        stream: _groupStream,
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting &&
              !snap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final group = snap.data;
          return Stack(
            children: [
              ListView(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
                children: group == null
                    ? _buildNoGroup()
                    : _buildGroup(group),
              ),
              if (_busy)
                const Positioned.fill(
                  child: ColoredBox(
                    color: Color(0x33000000),
                    child: Center(child: CircularProgressIndicator()),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }

  Widget _card({required Widget child}) => Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppTheme.cardBackground,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFFE5E7EB)),
        ),
        child: child,
      );

  List<Widget> _buildNoGroup() {
    final accent = AppTheme.primary;
    return [
      _card(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.groups_rounded, color: accent, size: 32),
                const SizedBox(width: 10),
                const Expanded(
                  child: Text(
                    'Travel together, scan once',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      color: _textDark,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              'Create a group for your barkada or family. Friends join by '
              'scanning your group QR or typing your code. At a tourist spot, '
              'the group leader scans the spot QR once and everyone is '
              'checked in.',
              style: TextStyle(color: AppTheme.unselectedMuted, height: 1.45),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _busy ? null : _createGroup,
                icon: const Icon(Icons.add_rounded),
                label: const Text('Create a group'),
                style: FilledButton.styleFrom(
                  backgroundColor: accent,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
              ),
            ),
          ],
        ),
      ),
      const SizedBox(height: 16),
      _card(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Join a friend\'s group',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w800,
                color: _textDark,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Scan their group QR in the Scan tab, or type the code below.',
              style: TextStyle(color: AppTheme.unselectedMuted, fontSize: 13),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _codeCtrl,
                    textCapitalization: TextCapitalization.characters,
                    decoration: const InputDecoration(
                      labelText: 'Group code',
                      hintText: 'e.g. 4K2P9X',
                      prefixText: 'LAAG-',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    onSubmitted: (_) => _joinWithCode(),
                  ),
                ),
                const SizedBox(width: 10),
                FilledButton(
                  onPressed: _busy ? null : _joinWithCode,
                  child: const Text('Join'),
                ),
              ],
            ),
          ],
        ),
      ),
      const SizedBox(height: 16),
      Text(
        'Members share only what DOT tourism forms need: sex, nationality and '
        'residence. Groups end automatically after 12 hours.',
        style: TextStyle(color: AppTheme.unselectedMuted, fontSize: 12),
        textAlign: TextAlign.center,
      ),
    ];
  }

  String _expiresLabel(TouristGroup g) {
    final e = g.expiresAt;
    if (e == null) return '';
    final left = e.difference(DateTime.now());
    if (left.inMinutes <= 0) return 'Ending now';
    final h = left.inHours;
    final m = left.inMinutes % 60;
    return h > 0 ? 'Ends in ${h}h ${m}m' : 'Ends in ${m}m';
  }

  List<Widget> _buildGroup(TouristGroup group) {
    final accent = AppTheme.primary;
    final leader = group.isLeader(_uid);
    return [
      _card(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.groups_rounded, color: accent, size: 28),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    group.name,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      color: _textDark,
                    ),
                  ),
                ),
                Chip(
                  label: Text(leader ? 'Leader' : 'Member'),
                  visualDensity: VisualDensity.compact,
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              '${group.memberCount} member${group.memberCount == 1 ? '' : 's'}'
              ' · ${_expiresLabel(group)}',
              style: TextStyle(color: AppTheme.unselectedMuted, fontSize: 13),
            ),
            const SizedBox(height: 12),
            Text(
              leader
                  ? 'At a tourist spot, scan the spot QR as usual and choose '
                      '"Check in with ${group.name}" to check in everyone.'
                  : 'Your group leader checks you in when they scan a spot QR. '
                      'The visit will appear in your history.',
              style: const TextStyle(color: _textDark, height: 1.4),
            ),
          ],
        ),
      ),
      const SizedBox(height: 16),
      _card(
        child: Column(
          children: [
            const Text(
              'Friends scan this in the ATMOS app',
              style: TextStyle(fontWeight: FontWeight.w700, color: _textDark),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(10),
              color: Colors.white,
              child: QrImageView(
                data: group.qrPayload,
                size: 200,
                backgroundColor: Colors.white,
              ),
            ),
            const SizedBox(height: 10),
            SelectableText(
              'LAAG-${group.joinCode}',
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w800,
                letterSpacing: 2,
                color: accent,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Or type this code in Laag with Friends → Join',
              style: TextStyle(color: AppTheme.unselectedMuted, fontSize: 12),
            ),
          ],
        ),
      ),
      const SizedBox(height: 16),
      _card(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Members',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w800,
                color: _textDark,
              ),
            ),
            const SizedBox(height: 6),
            for (final m in group.orderedMembers)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: CircleAvatar(
                  backgroundColor: accent.withValues(alpha: 0.12),
                  child: Text(
                    m.name.isNotEmpty ? m.name[0].toUpperCase() : '?',
                    style: TextStyle(color: accent, fontWeight: FontWeight.w800),
                  ),
                ),
                title: Text(
                  m.name.isNotEmpty ? m.name : 'Tourist',
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                subtitle: Text(
                  [
                    if (m.uid == group.leaderUid) 'Leader',
                    if (m.uid == _uid) 'You',
                    if (m.sex.isNotEmpty) m.sex,
                    if (m.nationality.isNotEmpty) m.nationality,
                  ].join(' · '),
                ),
                trailing: leader && m.uid != _uid
                    ? IconButton(
                        tooltip: 'Remove',
                        icon: const Icon(Icons.person_remove_alt_1_rounded),
                        onPressed: _busy ? null : () => _removeMember(group, m),
                      )
                    : null,
              ),
          ],
        ),
      ),
      const SizedBox(height: 16),
      OutlinedButton.icon(
        onPressed: _busy ? null : () => _leaveOrEnd(group),
        icon: Icon(
          leader ? Icons.stop_circle_outlined : Icons.logout_rounded,
          color: Colors.red.shade700,
        ),
        label: Text(
          leader ? 'End group' : 'Leave group',
          style: TextStyle(color: Colors.red.shade700),
        ),
        style: OutlinedButton.styleFrom(
          padding: const EdgeInsets.symmetric(vertical: 14),
          side: BorderSide(color: Colors.red.shade200),
        ),
      ),
    ];
  }
}

/// Confirms joining [group]. With [joinNow] the join is performed here
/// (used by the Scan tab after a group QR scan). Returns true on success.
Future<bool> confirmJoinTouristGroup(
  BuildContext context,
  TouristGroup group, {
  bool joinNow = true,
}) async {
  final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
  if (group.hasMember(uid)) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('You are already in ${group.name}.'),
        behavior: SnackBarBehavior.floating,
      ),
    );
    return false;
  }
  final leaderName = group.members[group.leaderUid]?.name ?? 'Your friend';
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      icon: Icon(Icons.groups_rounded, color: AppTheme.primary, size: 36),
      title: Text('Join ${group.name}?'),
      content: Text(
        '$leaderName is inviting you to Laag with Friends '
        '(${group.memberCount} member${group.memberCount == 1 ? '' : 's'}).\n\n'
        'Your sex, nationality and residence will be shared with the group '
        'so tourism offices can count you when the leader checks in.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: const Text('Not now'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(ctx, true),
          child: const Text('Join group'),
        ),
      ],
    ),
  );
  if (ok != true) return false;
  if (!joinNow) return true;
  if (!context.mounted) return false;
  try {
    await TouristGroupService.join(group);
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('You joined ${group.name}!'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
    return true;
  } on TouristGroupException catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e.message),
          behavior: SnackBarBehavior.floating,
          backgroundColor: Colors.red.shade700,
        ),
      );
    }
    return false;
  }
}

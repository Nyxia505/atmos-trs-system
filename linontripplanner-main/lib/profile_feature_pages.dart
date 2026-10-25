import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';

import 'data.dart';
import 'services/notification_prefs.dart';
import 'services/saved_trip_store.dart';
import 'services/spot_ratings_store.dart';

class ChangePasswordScreen extends StatefulWidget {
  const ChangePasswordScreen({super.key});

  @override
  State<ChangePasswordScreen> createState() => _ChangePasswordScreenState();
}

class _ChangePasswordScreenState extends State<ChangePasswordScreen> {
  final _current = TextEditingController();
  final _next = TextEditingController();
  final _confirm = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _current.dispose();
    _next.dispose();
    _confirm.dispose();
    super.dispose();
  }

  bool get _usesPassword {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return false;
    return user.providerData.any((p) => p.providerId == 'password');
  }

  Future<void> _submit() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      setState(() => _error = 'Sign in to change your password.');
      return;
    }
    if (!_usesPassword) {
      setState(() => _error =
          'This account signs in with ${user.providerData.map((p) => p.providerId).join(', ')}. Change that password with the provider.');
      return;
    }
    final email = user.email ?? '';
    if (_next.text.length < 6) {
      setState(() => _error = 'New password must be at least 6 characters.');
      return;
    }
    if (_next.text != _confirm.text) {
      setState(() => _error = 'New password and confirmation do not match.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final cred = EmailAuthProvider.credential(
        email: email,
        password: _current.text,
      );
      await user.reauthenticateWithCredential(cred);
      await user.updatePassword(_next.text);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Password updated.')),
      );
      Navigator.of(context).pop();
    } on FirebaseAuthException catch (e) {
      setState(() => _error = e.message ?? 'Could not change password.');
    } catch (e) {
      setState(() => _error = 'Could not change password.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.planPageBg,
      appBar: AppBar(
        title: const Text('Change Password'),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          if (!_usesPassword)
            const Text(
              'Password change is available for email and password accounts.',
            )
          else ...[
            TextField(
              controller: _current,
              obscureText: true,
              decoration: const InputDecoration(labelText: 'Current password'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _next,
              obscureText: true,
              decoration: const InputDecoration(labelText: 'New password'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _confirm,
              obscureText: true,
              decoration: const InputDecoration(labelText: 'Confirm new password'),
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(_error!, style: const TextStyle(color: Colors.red)),
            ],
            const SizedBox(height: 20),
            FilledButton(
              onPressed: _busy ? null : _submit,
              child: _busy
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Update password'),
            ),
          ],
        ],
      ),
    );
  }
}

class NotificationSettingsScreen extends StatefulWidget {
  const NotificationSettingsScreen({super.key});

  @override
  State<NotificationSettingsScreen> createState() =>
      _NotificationSettingsScreenState();
}

class _NotificationSettingsScreenState extends State<NotificationSettingsScreen> {
  NotificationPrefs _prefs = const NotificationPrefs();
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final prefs = await NotificationPrefs.load();
      if (!mounted) return;
      setState(() {
        _prefs = prefs;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Could not load notification settings.';
        _loading = false;
      });
    }
  }

  Future<void> _save(NotificationPrefs next) async {
    setState(() => _prefs = next);
    try {
      await NotificationPrefs.save(next);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Notification settings saved.')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.planPageBg,
      appBar: AppBar(
        title: const Text('Notification Settings'),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text(_error!))
              : ListView(
                  children: [
                    SwitchListTile(
                      title: const Text('Trip reminders'),
                      subtitle: const Text('Alerts about your saved plans'),
                      value: _prefs.tripReminders,
                      onChanged: (v) => _save(NotificationPrefs(
                        tripReminders: v,
                        spotUpdates: _prefs.spotUpdates,
                        events: _prefs.events,
                      )),
                    ),
                    SwitchListTile(
                      title: const Text('Spot updates'),
                      subtitle: const Text('Changes to places you saved'),
                      value: _prefs.spotUpdates,
                      onChanged: (v) => _save(NotificationPrefs(
                        tripReminders: _prefs.tripReminders,
                        spotUpdates: v,
                        events: _prefs.events,
                      )),
                    ),
                    SwitchListTile(
                      title: const Text('Events'),
                      subtitle: const Text(
                        'Tourism event alerts. Turning this off unsubscribes this device.',
                      ),
                      value: _prefs.events,
                      onChanged: (v) => _save(NotificationPrefs(
                        tripReminders: _prefs.tripReminders,
                        spotUpdates: _prefs.spotUpdates,
                        events: v,
                      )),
                    ),
                  ],
                ),
    );
  }
}

class TravelHistoryScreen extends StatefulWidget {
  const TravelHistoryScreen({super.key});

  @override
  State<TravelHistoryScreen> createState() => _TravelHistoryScreenState();
}

class _TravelHistoryScreenState extends State<TravelHistoryScreen> {
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      await SavedTripStore.instance.refresh();
    } catch (_) {
      _error = 'Could not load travel history.';
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  bool _isPast(SavedTripPlan trip) {
    final end = trip.departureDate ?? trip.arrivalDate;
    if (end == null) return false;
    final today = DateTime.now();
    final startOfToday = DateTime(today.year, today.month, today.day);
    return end.isBefore(startOfToday);
  }

  @override
  Widget build(BuildContext context) {
    final past = SavedTripStore.instance.trips.where(_isPast).toList();
    return Scaffold(
      backgroundColor: AppColors.planPageBg,
      appBar: AppBar(
        title: const Text('Travel History'),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text(_error!))
              : past.isEmpty
                  ? const Center(
                      child: Padding(
                        padding: EdgeInsets.all(24),
                        child: Text(
                          'No completed trips yet. Plans with a departure date still in the future stay in My Trips.',
                          textAlign: TextAlign.center,
                        ),
                      ),
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.all(16),
                      itemCount: past.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 10),
                      itemBuilder: (context, i) {
                        final trip = past[i];
                        final when = trip.departureDate ?? trip.arrivalDate;
                        return Card(
                          child: ListTile(
                            title: Text('${trip.startName} to ${trip.endName}'),
                            subtitle: Text(
                              '${when == null ? '' : '${when.year}-${when.month.toString().padLeft(2, '0')}-${when.day.toString().padLeft(2, '0')}'}'
                              ' · ${trip.tripDays} day(s) · ${trip.spotCount} spots',
                            ),
                          ),
                        );
                      },
                    ),
    );
  }
}

class MyReviewsScreen extends StatefulWidget {
  const MyReviewsScreen({super.key});

  @override
  State<MyReviewsScreen> createState() => _MyReviewsScreenState();
}

class _MyReviewsScreenState extends State<MyReviewsScreen> {
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    SpotRatingsStore.instance.revision.addListener(_onRev);
    _load();
  }

  @override
  void dispose() {
    SpotRatingsStore.instance.revision.removeListener(_onRev);
    super.dispose();
  }

  void _onRev() {
    if (mounted) setState(() {});
  }

  Future<void> _load() async {
    await SpotRatingsStore.instance.ensureLoaded();
    await SpotRatingsStore.instance.refreshFromFirestore();
    if (mounted) setState(() => _loading = false);
  }

  List<SpotRating> get _mine {
    final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
    if (uid.isEmpty) return const [];
    return spotRatings.where((r) => r.userId == uid).toList().reversed.toList();
  }

  Future<void> _edit(SpotRating rating) async {
    final comment = TextEditingController(text: rating.description);
    var stars = rating.rating;
    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(rating.spotName),
        content: StatefulBuilder(
          builder: (ctx, setLocal) => Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Slider(
                value: stars.clamp(1, 5),
                min: 1,
                max: 5,
                divisions: 4,
                label: stars.toStringAsFixed(0),
                onChanged: (v) => setLocal(() => stars = v),
              ),
              TextField(
                controller: comment,
                maxLines: 3,
                decoration: const InputDecoration(labelText: 'Comment'),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (saved != true) {
      comment.dispose();
      return;
    }
    await SpotRatingsStore.instance.add(
      rating.copyWith(rating: stars, description: comment.text.trim()),
    );
    comment.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final items = _mine;
    return Scaffold(
      backgroundColor: AppColors.planPageBg,
      appBar: AppBar(
        title: const Text('My Reviews'),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : items.isEmpty
              ? const Center(
                  child: Padding(
                    padding: EdgeInsets.all(24),
                    child: Text(
                      'You have not written a review yet.',
                      textAlign: TextAlign.center,
                    ),
                  ),
                )
              : ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: items.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 8),
                  itemBuilder: (context, i) {
                    final r = items[i];
                    final when = r.createdAt;
                    return Card(
                      child: ListTile(
                        title: Text(r.spotName),
                        subtitle: Text(
                          '${r.rating.toStringAsFixed(1)} · ${r.description}'
                          '${when == null ? '' : '\n${when.year}-${when.month}-${when.day}'}',
                        ),
                        isThreeLine: true,
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              tooltip: 'Edit',
                              onPressed: () => _edit(r),
                              icon: const Icon(Icons.edit_outlined),
                            ),
                            IconButton(
                              tooltip: 'Delete',
                              onPressed: () async {
                                try {
                                  await SpotRatingsStore.instance.remove(r);
                                } catch (_) {
                                  if (!context.mounted) return;
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text('Could not delete this review.'),
                                    ),
                                  );
                                }
                              },
                              icon: const Icon(Icons.delete_outline),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
    );
  }
}

class HelpFaqScreen extends StatelessWidget {
  const HelpFaqScreen({super.key});

  static const _groups = <(String, List<(String, String)>)>[
    (
      'Creating trips',
      [
        (
          'How do I plan a trip?',
          'Open My Trips and tap Plan a new trip. Choose a start, an end, dates, and spots, then finish the plan to save it.',
        ),
        (
          'Where do saved trips appear?',
          'Finished plans are stored for your account and listed on My Trips.',
        ),
      ],
    ),
    (
      'Saving places',
      [
        (
          'How do I save a destination?',
          'Open a spot and tap the heart. Saved places are listed under Profile → Saved Places.',
        ),
      ],
    ),
    (
      'Maps',
      [
        (
          'How do I see a route?',
          'Open Map & Routes, or open a saved trip and tap View route on map. Location permission is needed for your position.',
        ),
      ],
    ),
    (
      'Account',
      [
        (
          'How do I change my photo or password?',
          'Use Edit Profile Photo and Change Password under Account. Password changes need your current password for email accounts.',
        ),
      ],
    ),
    (
      'Troubleshooting',
      [
        (
          'A list is empty or failed to load.',
          'Check that you are signed in and online, then reopen the screen. Trips, reviews, and settings belong to the signed-in account.',
        ),
      ],
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.planPageBg,
      appBar: AppBar(
        title: const Text('Help & FAQ'),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
      ),
      body: ListView(
        children: [
          for (final group in _groups) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
              child: Text(
                group.$1,
                style: const TextStyle(
                  fontWeight: FontWeight.w800,
                  color: AppColors.primary,
                ),
              ),
            ),
            for (final item in group.$2)
              ExpansionTile(
                title: Text(item.$1),
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                    child: Text(item.$2),
                  ),
                ],
              ),
          ],
        ],
      ),
    );
  }
}

class AboutAppScreen extends StatelessWidget {
  const AboutAppScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.planPageBg,
      appBar: AppBar(
        title: const Text('About the App'),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
      ),
      body: FutureBuilder<PackageInfo>(
        future: PackageInfo.fromPlatform(),
        builder: (context, snap) {
          final version = snap.hasData
              ? '${snap.data!.version}+${snap.data!.buildNumber}'
              : '…';
          return ListView(
            padding: const EdgeInsets.all(20),
            children: [
              const Text(
                'Trip Plan',
                style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.w800,
                  color: AppColors.primary,
                ),
              ),
              Text('Version $version'),
              const SizedBox(height: 12),
              const Text(
                'Trip Plan is the trip planner module of ATMOS TRS for Misamis Occidental. '
                'It helps visitors plan routes, save places, and review destinations. '
                'Municipal tourism records, check-ins, and official reports stay in ATMOS TRS.',
              ),
              const SizedBox(height: 12),
              const Text(
                'Features: plan a trip, save destinations, view maps and routes, '
                'keep travel history, and manage your profile.',
              ),
            ],
          );
        },
      ),
    );
  }
}

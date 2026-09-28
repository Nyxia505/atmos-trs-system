import 'package:flutter/material.dart';

import 'package:atmos_trs_system/services/establishment_demo_seed_service.dart';
import 'package:atmos_trs_system/utils/establishment_room_grid.dart';
import 'package:atmos_trs_system/widgets/establishment_dash_tokens.dart';
import 'package:atmos_trs_system/widgets/establishment_dashboard_components.dart';

/// Settings tab: demo data seeding (preview) + removal back to real data.
class EstablishmentSettingsPanel extends StatefulWidget {
  const EstablishmentSettingsPanel({
    super.key,
    required this.establishmentName,
    required this.municipality,
    required this.municipalityId,
    required this.category,
    required this.roomCount,
    required this.disabledRooms,
    required this.demoStayCount,
    required this.realStayCount,
    this.flushHero = false,
    this.contentPadding = const EdgeInsets.only(top: 18),
  });

  final String establishmentName;
  final String municipality;
  final String municipalityId;
  final String category;
  final int roomCount;
  final List<String> disabledRooms;

  /// Live counts from the stays stream.
  final int demoStayCount;
  final int realStayCount;

  final bool flushHero;
  final EdgeInsetsGeometry contentPadding;

  @override
  State<EstablishmentSettingsPanel> createState() =>
      _EstablishmentSettingsPanelState();
}

class _EstablishmentSettingsPanelState
    extends State<EstablishmentSettingsPanel> {
  static const _presets = [10, 25, 50, 100];

  int _count = 25;
  bool _busy = false;
  String? _busyLabel;

  int get _enabledRooms {
    if (widget.roomCount < 1) return 0;
    final disabled = {
      for (final d in widget.disabledRooms)
        EstablishmentRoomGrid.normalizeSlotId(d, widget.roomCount),
    }..remove(null);
    return widget.roomCount - disabled.length;
  }

  Future<bool> _confirm({
    required String title,
    required String message,
    required String action,
    Color color = AeDashTokens.accent,
  }) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title, style: AeDashTokens.heading(size: 17)),
        content: Text(message, style: AeDashTokens.body(size: 13)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: color),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(action),
          ),
        ],
      ),
    );
    return ok == true;
  }

  void _toast(String msg, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: error ? AeDashTokens.danger : null,
      ),
    );
  }

  Future<void> _seed() async {
    if (widget.demoStayCount > 0) {
      final ok = await _confirm(
        title: 'Replace demo data?',
        message: 'This removes the current ${widget.demoStayCount} demo stays '
            'and seeds $_count new ones. Real guest data is not touched.',
        action: 'Replace',
      );
      if (!ok) return;
    }
    setState(() {
      _busy = true;
      _busyLabel = 'Seeding $_count demo stays…';
    });
    try {
      final r = await EstablishmentDemoSeedService.seed(
        count: _count,
        establishmentName: widget.establishmentName,
        municipality: widget.municipality,
        municipalityId: widget.municipalityId,
        category: widget.category,
        roomCount: widget.roomCount,
        disabledRooms: widget.disabledRooms,
      );
      _toast('Seeded ${r.total} demo stays and ${r.reviews} reviews.');
    } catch (e) {
      _toast('Could not seed demo data: $e', error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _clear() async {
    final ok = await _confirm(
      title: 'Remove demo data?',
      message: 'Deletes all ${widget.demoStayCount} demo stays and their '
          'reviews. Your dashboard goes back to real guest data only.',
      action: 'Remove',
      color: AeDashTokens.danger,
    );
    if (!ok) return;
    setState(() {
      _busy = true;
      _busyLabel = 'Removing demo data…';
    });
    try {
      final r = await EstablishmentDemoSeedService.clear();
      _toast(
        'Removed ${r.removedStays} demo stays and ${r.removedReviews} reviews.'
        '${r.skippedReviews > 0 ? ' ${r.skippedReviews} review(s) came from '
            'another account and were left.' : ''}',
      );
    } catch (e) {
      _toast('Could not remove demo data: $e', error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AePageHero(
          icon: Icons.settings_rounded,
          title: 'Settings',
          subtitle: 'Manage dashboard preferences and demo data.',
          flush: widget.flushHero,
        ),
        Padding(
          padding: widget.contentPadding,
          child: _demoCard(),
        ),
      ],
    );
  }

  Widget _demoCard() {
    final active = widget.demoStayCount > 0;
    final mix = EstablishmentDemoSeedService.plan(_count, _enabledRooms);
    return AePanelCard(
      title: 'Demo data',
      subtitle: 'Preview the dashboard with sample guests',
      icon: Icons.science_rounded,
      trailing: AeStatusPill(
        label: active ? '${widget.demoStayCount} demo stays' : 'Real data only',
        color: active ? AeDashTokens.warning : AeDashTokens.success,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Fill Home, Rooms and Insights with sample stays and reviews to '
            'see how your dashboard looks. Demo records are tagged and can be '
            'removed anytime — your ${widget.realStayCount} real guest '
            'stay${widget.realStayCount == 1 ? '' : 's'} are never changed.',
            style: AeDashTokens.body(size: 13),
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              Expanded(
                child: Text(
                  'Number of stays',
                  style: AeDashTokens.body(
                    size: 13,
                    color: AeDashTokens.text,
                    weight: FontWeight.w600,
                  ),
                ),
              ),
              Text('$_count', style: AeDashTokens.number(size: 20)),
            ],
          ),
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              activeTrackColor: AeDashTokens.accent,
              inactiveTrackColor: AeDashTokens.softAccent,
              thumbColor: AeDashTokens.accent,
              overlayColor: AeDashTokens.accent.withValues(alpha: 0.12),
              valueIndicatorColor: AeDashTokens.accent,
            ),
            child: Slider(
              min: EstablishmentDemoSeedService.minCount.toDouble(),
              max: EstablishmentDemoSeedService.maxCount.toDouble(),
              divisions: (EstablishmentDemoSeedService.maxCount -
                      EstablishmentDemoSeedService.minCount) ~/
                  5,
              value: _count.toDouble(),
              label: '$_count',
              onChanged: _busy
                  ? null
                  : (v) => setState(() => _count = v.round()),
            ),
          ),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final p in _presets)
                AeFilterPill(
                  label: '$p',
                  selected: _count == p,
                  onTap: () {
                    if (!_busy) setState(() => _count = p);
                  },
                ),
            ],
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 14,
            runSpacing: 6,
            children: [
              AeLegendDot(
                color: AeDashTokens.accent,
                label: '${mix.inHouse} in-house',
              ),
              AeLegendDot(
                color: AeDashTokens.success,
                label: '${mix.checkedOut} checked out',
              ),
              AeLegendDot(
                color: AeDashTokens.warning,
                label: '${mix.pending} pending',
              ),
              AeLegendDot(
                color: AeDashTokens.danger,
                label: '${mix.rejected} rejected',
              ),
            ],
          ),
          if (widget.roomCount < 1) ...[
            const SizedBox(height: 8),
            Text(
              'Set your room count in Rooms to see occupied rooms.',
              style: AeDashTokens.body(size: 12),
            ),
          ],
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFFFFFBEB),
              borderRadius: BorderRadius.circular(AeDashTokens.radiusSm),
              border: Border.all(color: const Color(0xFFFDE68A)),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.info_outline_rounded,
                    size: 18, color: Color(0xFFB45309)),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Demo stays count toward LGU / DOT reports for '
                    '${widget.municipality.isNotEmpty ? widget.municipality : 'your municipality'} '
                    'while they exist. Remove them before real reporting.',
                    style: AeDashTokens.body(
                      size: 12,
                      color: const Color(0xFF92400E),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          if (_busy)
            Row(
              children: [
                const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.2,
                    color: AeDashTokens.accent,
                  ),
                ),
                const SizedBox(width: 12),
                Text(_busyLabel ?? '', style: AeDashTokens.body(size: 13)),
              ],
            )
          else
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                FilledButton.icon(
                  onPressed: _seed,
                  icon: const Icon(Icons.auto_awesome_rounded, size: 18),
                  label: Text(
                    active ? 'Reseed $_count stays' : 'Seed $_count demo stays',
                  ),
                  style: FilledButton.styleFrom(
                    backgroundColor: AeDashTokens.accent,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 18,
                      vertical: 14,
                    ),
                  ),
                ),
                OutlinedButton.icon(
                  onPressed: active ? _clear : null,
                  icon: const Icon(Icons.restart_alt_rounded, size: 18),
                  label: const Text('Remove demo data'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AeDashTokens.danger,
                    side: BorderSide(
                      color: active
                          ? AeDashTokens.danger.withValues(alpha: 0.5)
                          : AeDashTokens.border,
                    ),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 18,
                      vertical: 14,
                    ),
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }
}

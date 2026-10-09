import 'package:flutter/material.dart';

import 'package:atmos_trs_system/config/ae_register_schema.dart';
import 'package:atmos_trs_system/models/ae_register.dart';
import 'package:atmos_trs_system/services/ae_register_service.dart';
import 'package:atmos_trs_system/services/establishment_demo_seed_service.dart';
import 'package:atmos_trs_system/widgets/establishment_dash_tokens.dart';
import 'package:atmos_trs_system/widgets/establishment_dashboard_components.dart';

/// Settings tab: demo register data (preview) + removal back to real data.
class EstablishmentSettingsPanel extends StatefulWidget {
  const EstablishmentSettingsPanel({
    super.key,
    required this.profile,
    required this.schema,
    this.hostsMice = false,
    this.flushHero = false,
    this.contentPadding = const EdgeInsets.only(top: 18),
  });

  final AeRegisterProfile profile;
  final AeRegisterSchema schema;

  /// Also seeds / clears demo MICE events.
  final bool hostsMice;
  final bool flushHero;
  final EdgeInsetsGeometry contentPadding;

  @override
  State<EstablishmentSettingsPanel> createState() => _EstablishmentSettingsPanelState();
}

class _EstablishmentSettingsPanelState extends State<EstablishmentSettingsPanel> {
  int _months = 3;
  bool _busy = false;
  String? _busyLabel;
  late Stream<List<AeMonthlyReport>> _reports;

  @override
  void initState() {
    super.initState();
    _reports = AeRegisterService.watchForAe(widget.profile.aeId);
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
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
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
      SnackBar(content: Text(msg), backgroundColor: error ? AeDashTokens.danger : null),
    );
  }

  Future<void> _seed(int demoMonths) async {
    if (demoMonths > 0) {
      final ok = await _confirm(
        title: 'Replace demo data?',
        message: 'Removes the current demo rows ($demoMonths month(s)) and seeds '
            '$_months new month(s). Rows you entered yourself are not touched.',
        action: 'Replace',
      );
      if (!ok) return;
    }
    setState(() {
      _busy = true;
      _busyLabel = 'Seeding $_months month(s) of register data…';
    });
    try {
      final r = await EstablishmentDemoSeedService.seed(
        profile: widget.profile,
        schema: widget.schema,
        months: _months,
        hostsMice: widget.hostsMice,
      );
      _toast('Seeded ${r.rows} demo rows across ${r.months} month(s)'
          '${r.events > 0 ? ' and ${r.events} demo event(s)' : ''}.');
    } catch (e) {
      _toast('Could not seed demo data: $e', error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _clear(int demoMonths) async {
    final ok = await _confirm(
      title: 'Remove demo data?',
      message: 'Deletes demo rows in $demoMonths month(s). Months you filled yourself keep your rows.',
      action: 'Remove',
      color: AeDashTokens.danger,
    );
    if (!ok) return;
    setState(() {
      _busy = true;
      _busyLabel = 'Removing demo data…';
    });
    try {
      final n = await EstablishmentDemoSeedService.clear(widget.profile.aeId);
      _toast('Removed demo data from $n month(s).');
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
          child: StreamBuilder<List<AeMonthlyReport>>(
            stream: _reports,
            builder: (context, snap) {
              final reports = snap.data ?? const <AeMonthlyReport>[];
              final demo = reports.where((r) => r.isDemo).length;
              final real = reports.where((r) => !r.isDemo).length;
              return _demoCard(demo, real);
            },
          ),
        ),
      ],
    );
  }

  Widget _demoCard(int demoMonths, int realMonths) {
    final active = demoMonths > 0;
    return AePanelCard(
      title: 'Demo data',
      subtitle: 'Preview the register and Insights with sample guests',
      icon: Icons.science_rounded,
      trailing: AeStatusPill(
        label: active ? '$demoMonths demo month(s)' : 'Real data only',
        color: active ? AeDashTokens.warning : AeDashTokens.success,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Fills the Daily Register with realistic sample rows (residence mix, '
            'multi-night stays, weekends busier) so Monthly Record, DAE-2, By Country '
            'and Insights light up.${widget.hostsMice ? ' Also adds sample MICE events (CUS) to the Events tab.' : ''} '
            'Demo rows are tagged and removable — your '
            '$realMonths month(s) of real entries are never changed.',
            style: AeDashTokens.body(size: 13),
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              Expanded(
                child: Text(
                  'Months to seed (ending this month)',
                  style: AeDashTokens.body(size: 13, color: AeDashTokens.text, weight: FontWeight.w600),
                ),
              ),
              Text('$_months', style: AeDashTokens.number(size: 20)),
            ],
          ),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (var m = EstablishmentDemoSeedService.minMonths; m <= EstablishmentDemoSeedService.maxMonths; m++)
                AeFilterPill(
                  label: '$m',
                  selected: _months == m,
                  onTap: () {
                    if (!_busy) setState(() => _months = m);
                  },
                ),
            ],
          ),
          if (widget.schema.tracksRooms && widget.profile.totalRooms < 1) ...[
            const SizedBox(height: 8),
            Text(
              'Total rooms is not set — demo uses ${EstablishmentDemoSeedService.fallbackRooms} rooms. '
              'Set your real room count in Profile.',
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
                const Icon(Icons.info_outline_rounded, size: 18, color: Color(0xFFB45309)),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Demo rows count toward LGU / DOT reports for '
                    '${widget.profile.municipality.isNotEmpty ? widget.profile.municipality : 'your municipality'} '
                    'while they exist. Remove them before real reporting.',
                    style: AeDashTokens.body(size: 12, color: const Color(0xFF92400E)),
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
                  child: CircularProgressIndicator(strokeWidth: 2.2, color: AeDashTokens.accent),
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
                  onPressed: () => _seed(demoMonths),
                  icon: const Icon(Icons.auto_awesome_rounded, size: 18),
                  label: Text(active ? 'Reseed $_months month(s)' : 'Seed $_months month(s)'),
                  style: FilledButton.styleFrom(
                    backgroundColor: AeDashTokens.accent,
                    padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
                  ),
                ),
                OutlinedButton.icon(
                  onPressed: active ? () => _clear(demoMonths) : null,
                  icon: const Icon(Icons.restart_alt_rounded, size: 18),
                  label: const Text('Remove demo data'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AeDashTokens.danger,
                    side: BorderSide(
                      color: active ? AeDashTokens.danger.withValues(alpha: 0.5) : AeDashTokens.border,
                    ),
                    padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }
}

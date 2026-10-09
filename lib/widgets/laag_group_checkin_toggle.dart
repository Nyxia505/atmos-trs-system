import 'package:atmos_trs_system/config/app_theme.dart';
import 'package:atmos_trs_system/models/tourist_group.dart';
import 'package:atmos_trs_system/widgets/party_demographic_fields.dart';
import 'package:flutter/material.dart';

/// Default party for a solo scan (the tourist only).
const PartyDemographicValue kSoloParty = PartyDemographicValue(
  partySize: 1,
  maleCount: 0,
  femaleCount: 1,
  filipinoCount: 1,
  foreignCount: 0,
);

/// Default companions for a group scan (members are counted from profiles).
const PartyDemographicValue kNoCompanions = PartyDemographicValue(
  partySize: 0,
  maleCount: 0,
  femaleCount: 0,
  filipinoCount: 0,
  foreignCount: 0,
  minPartySize: 0,
);

const String kCompanionsHelpText =
    'Group members are counted from their own profiles. Add only people with '
    'you who don\'t have the app (kids, elders, friends) — 0 if none.';

/// "Check in with my group" switch on the spot / LGU check-in screens.
///
/// Shown to the leader of an active Laag with Friends group. For a member it
/// shows a note that the leader can check them in.
class LaagGroupCheckInToggle extends StatelessWidget {
  const LaagGroupCheckInToggle({
    super.key,
    required this.group,
    required this.isLeader,
    required this.enabled,
    required this.onChanged,
  });

  final TouristGroup group;
  final bool isLeader;
  final bool enabled;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final accent = AppTheme.primary;
    final n = group.memberCount;
    return Container(
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: accent.withValues(alpha: 0.25)),
      ),
      padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
      child: isLeader
          ? SwitchListTile.adaptive(
              contentPadding: EdgeInsets.zero,
              value: enabled,
              onChanged: onChanged,
              secondary: Icon(Icons.groups_rounded, color: accent),
              title: Text(
                'Check in with ${group.name}',
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              subtitle: Text(
                '$n member${n == 1 ? '' : 's'} with the app — each is counted '
                'with their own profile.',
              ),
            )
          : ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(Icons.groups_rounded, color: accent),
              title: Text('You are in ${group.name}'),
              subtitle: const Text(
                'Your group leader can check everyone in with one scan. '
                'You can still register your own visit here.',
              ),
            ),
    );
  }
}

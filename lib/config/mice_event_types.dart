import 'package:flutter/material.dart';

/// MICE event categories (CUS MICE survey). Reports and filters group by
/// category so venue-specific custom labels never fragment analytics.
enum MiceCategory {
  meeting('meeting', 'Meeting', Icons.groups_rounded),
  incentive('incentive', 'Incentive', Icons.emoji_events_rounded),
  convention('convention', 'Convention / Conference', Icons.record_voice_over_rounded),
  exhibition('exhibition', 'Exhibition / Trade fair', Icons.storefront_rounded),
  social('social', 'Social event', Icons.celebration_rounded),
  sports('sports', 'Sports', Icons.sports_basketball_rounded),
  cultural('cultural', 'Cultural / Concert', Icons.music_note_rounded),
  government('government', 'Government / Official', Icons.account_balance_rounded),
  religious('religious', 'Religious', Icons.church_rounded),
  other('other', 'Other', Icons.event_rounded);

  const MiceCategory(this.id, this.label, this.icon);

  final String id;
  final String label;
  final IconData icon;

  static MiceCategory fromId(String? id) {
    final s = (id ?? '').trim().toLowerCase();
    for (final c in values) {
      if (c.id == s) return c;
    }
    return MiceCategory.other;
  }
}

/// One selectable event type (label printed on the CUS form "TYPE OF EVENT").
@immutable
class MiceEventType {
  const MiceEventType(this.label, this.category, {this.custom = false});

  final String label;
  final MiceCategory category;

  /// Added by this venue (stored in `mice_venue_settings/{aeId}.customTypes`).
  final bool custom;

  String get key => MiceEventTypes.normalize(label);

  Map<String, dynamic> toMap() => {'label': label, 'category': category.id};

  static MiceEventType? fromMap(Object? raw) {
    if (raw is! Map) return null;
    final label = (raw['label'] ?? '').toString().trim();
    if (label.isEmpty) return null;
    return MiceEventType(label, MiceCategory.fromId(raw['category']?.toString()), custom: true);
  }

  @override
  bool operator ==(Object other) => other is MiceEventType && other.key == key;

  @override
  int get hashCode => key.hashCode;
}

abstract final class MiceEventTypes {
  static const base = <MiceEventType>[
    MiceEventType('Seminar', MiceCategory.meeting),
    MiceEventType('Training / Workshop', MiceCategory.meeting),
    MiceEventType('Business meeting', MiceCategory.meeting),
    MiceEventType('Board / Planning meeting', MiceCategory.meeting),
    MiceEventType('Forum / Orientation', MiceCategory.meeting),
    MiceEventType('Team building', MiceCategory.incentive),
    MiceEventType('Company outing', MiceCategory.incentive),
    MiceEventType('Incentive trip', MiceCategory.incentive),
    MiceEventType('Awards night', MiceCategory.incentive),
    MiceEventType('Convention', MiceCategory.convention),
    MiceEventType('Conference', MiceCategory.convention),
    MiceEventType('Summit / Congress', MiceCategory.convention),
    MiceEventType('Assembly', MiceCategory.convention),
    MiceEventType('Exhibition', MiceCategory.exhibition),
    MiceEventType('Trade fair', MiceCategory.exhibition),
    MiceEventType('Product launch', MiceCategory.exhibition),
    MiceEventType('Bazaar / Expo', MiceCategory.exhibition),
    MiceEventType('Wedding reception', MiceCategory.social),
    MiceEventType('Debut', MiceCategory.social),
    MiceEventType('Birthday party', MiceCategory.social),
    MiceEventType('Reunion', MiceCategory.social),
    MiceEventType('Christmas party', MiceCategory.social),
    MiceEventType('Baptismal / Christening', MiceCategory.social),
    MiceEventType('Anniversary', MiceCategory.social),
    MiceEventType('Graduation / Prom', MiceCategory.social),
    MiceEventType('Sports tournament', MiceCategory.sports),
    MiceEventType('Fun run / Marathon', MiceCategory.sports),
    MiceEventType('Concert', MiceCategory.cultural),
    MiceEventType('Pageant', MiceCategory.cultural),
    MiceEventType('Festival / Cultural show', MiceCategory.cultural),
    MiceEventType('Government event', MiceCategory.government),
    MiceEventType('Press conference', MiceCategory.government),
    MiceEventType('Religious gathering / Retreat', MiceCategory.religious),
  ];

  static String normalize(String label) =>
      label.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');

  /// Base suggestions plus the venue's custom types (custom wins on clash).
  static List<MiceEventType> merged(Iterable<MiceEventType> custom) {
    final byKey = <String, MiceEventType>{for (final t in base) t.key: t};
    for (final t in custom) {
      if (t.label.trim().isNotEmpty) byKey[t.key] = t;
    }
    return byKey.values.toList();
  }

  static MiceEventType? find(String label, Iterable<MiceEventType> types) {
    final k = normalize(label);
    if (k.isEmpty) return null;
    for (final t in types) {
      if (t.key == k) return t;
    }
    return null;
  }

  /// Suggestions for the typed text: prefix matches first, then contains,
  /// also matching the category label (typing "social" lists social types).
  static List<MiceEventType> search(String query, Iterable<MiceEventType> types, {int limit = 12}) {
    final q = normalize(query);
    final all = types.toList();
    if (q.isEmpty) return all.take(limit).toList();
    final prefix = <MiceEventType>[];
    final rest = <MiceEventType>[];
    for (final t in all) {
      if (t.key.startsWith(q)) {
        prefix.add(t);
      } else if (t.key.contains(q) || t.category.label.toLowerCase().contains(q)) {
        rest.add(t);
      }
    }
    return [...prefix, ...rest].take(limit).toList();
  }

  /// Best-guess category for a new custom label (pre-selected in the picker).
  static MiceCategory guessCategory(String label) {
    final k = normalize(label);
    if (k.isEmpty) return MiceCategory.other;
    for (final t in base) {
      if (k.contains(t.key) || t.key.contains(k)) return t.category;
    }
    const hints = <String, MiceCategory>{
      'meeting': MiceCategory.meeting,
      'seminar': MiceCategory.meeting,
      'training': MiceCategory.meeting,
      'workshop': MiceCategory.meeting,
      'webinar': MiceCategory.meeting,
      'outing': MiceCategory.incentive,
      'incentive': MiceCategory.incentive,
      'convention': MiceCategory.convention,
      'conference': MiceCategory.convention,
      'congress': MiceCategory.convention,
      'expo': MiceCategory.exhibition,
      'fair': MiceCategory.exhibition,
      'exhibit': MiceCategory.exhibition,
      'launch': MiceCategory.exhibition,
      'wedding': MiceCategory.social,
      'party': MiceCategory.social,
      'birthday': MiceCategory.social,
      'debut': MiceCategory.social,
      'reunion': MiceCategory.social,
      'tournament': MiceCategory.sports,
      'league': MiceCategory.sports,
      'run': MiceCategory.sports,
      'concert': MiceCategory.cultural,
      'festival': MiceCategory.cultural,
      'pageant': MiceCategory.cultural,
      'show': MiceCategory.cultural,
      'lgu': MiceCategory.government,
      'government': MiceCategory.government,
      'mass': MiceCategory.religious,
      'retreat': MiceCategory.religious,
      'prayer': MiceCategory.religious,
    };
    for (final e in hints.entries) {
      if (k.contains(e.key)) return e.value;
    }
    return MiceCategory.other;
  }
}

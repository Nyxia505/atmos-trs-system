import 'package:flutter/material.dart';

/// Capability packs for tourism establishments (drive confirm UI + DAE fields).
enum EstablishmentPack {
  lodging,
  dining,
  venue,
}

/// UI copy / labels for an [EstablishmentPack].
class EstablishmentPackCopy {
  const EstablishmentPackCopy({
    required this.packLabel,
    required this.opsNoun,
    required this.queueTitle,
    required this.queueHint,
    required this.queueEmpty,
    required this.recentTitle,
    required this.recentEmpty,
    required this.chartTitle,
    required this.chartSubtitle,
    required this.calendarSubtitle,
    required this.qrHint,
    required this.confirmTitle,
    required this.confirmHint,
    required this.confirmNonLodgingNote,
    required this.confirmedSnack,
    required this.rejectTitle,
    required this.statusApproved,
    required this.kpiGuestsLabel,
    required this.kpiFourthLabel,
    required this.kpiFourthIcon,
  });

  final String packLabel;
  final String opsNoun;
  final String queueTitle;
  final String queueHint;
  final String queueEmpty;
  final String recentTitle;
  final String recentEmpty;
  final String chartTitle;
  final String chartSubtitle;
  final String calendarSubtitle;
  final String qrHint;
  final String confirmTitle;
  final String confirmHint;
  final String confirmNonLodgingNote;
  final String confirmedSnack;
  final String rejectTitle;
  final String statusApproved;
  final String kpiGuestsLabel;
  final String kpiFourthLabel;
  final IconData kpiFourthIcon;
}

abstract final class EstablishmentCapability {
  static const lodgingCategories = {
    'hotel',
    'resort',
    'glamping',
    'camping',
  };

  static const diningCategories = {
    'restaurant',
    'food provider',
  };

  static bool isLodging(String? category) {
    return packFor(category) == EstablishmentPack.lodging;
  }

  static bool isDining(String? category) {
    return packFor(category) == EstablishmentPack.dining;
  }

  static bool isVenue(String? category) {
    return packFor(category) == EstablishmentPack.venue;
  }

  static bool showsRooms(String? category) => isLodging(category);

  /// DOT-ish type/class label for DAE-3 (best-effort from signup category).
  static String typeClassFor(String? category) {
    final raw = (category ?? '').trim();
    if (raw.isEmpty) return '';
    return raw;
  }

  static String _norm(String? category) =>
      (category ?? '').trim().toLowerCase();

  static EstablishmentPack packFor(String? category) {
    final c = _norm(category);
    if (lodgingCategories.contains(c)) return EstablishmentPack.lodging;
    if (diningCategories.contains(c)) return EstablishmentPack.dining;
    return EstablishmentPack.venue;
  }

  static IconData iconFor(String? category) {
    switch (_norm(category)) {
      case 'hotel':
        return Icons.hotel_rounded;
      case 'resort':
        return Icons.beach_access_rounded;
      case 'glamping':
        return Icons.cabin_rounded;
      case 'camping':
        return Icons.park_rounded;
      case 'restaurant':
        return Icons.restaurant_rounded;
      case 'food provider':
        return Icons.storefront_rounded;
      case 'swimming pool':
        return Icons.pool_rounded;
      case 'museum/gallery':
      case 'museum':
      case 'gallery':
        return Icons.museum_rounded;
      case 'events place':
        return Icons.event_rounded;
      case 'attraction':
        return Icons.attractions_rounded;
      case 'health & wellness':
      case 'health and wellness':
        return Icons.spa_rounded;
      default:
        switch (packFor(category)) {
          case EstablishmentPack.lodging:
            return Icons.hotel_rounded;
          case EstablishmentPack.dining:
            return Icons.restaurant_rounded;
          case EstablishmentPack.venue:
            return Icons.place_rounded;
        }
    }
  }

  static EstablishmentPackCopy copyFor(String? category) {
    switch (packFor(category)) {
      case EstablishmentPack.lodging:
        return const EstablishmentPackCopy(
          packLabel: 'Lodging',
          opsNoun: 'stay',
          queueTitle: 'Stay requests',
          queueHint:
              'When a tourist scans your QR, the request appears here. '
              'Enter guest counts (Male/Female, Filipino/Foreign) '
              'plus nights/rooms, then confirm — they get a receipt.',
          queueEmpty:
              'No pending requests. Print your QR and ask a tourist to scan it.',
          recentTitle: 'Recent confirmed',
          recentEmpty: 'No confirmed stays yet.',
          chartTitle: 'Bookings · last 14 days',
          chartSubtitle: 'Confirmed stays per day',
          calendarSubtitle: 'Days with confirmed stays',
          qrHint:
              'Tourists scan this to start a stay request for your front desk.',
          confirmTitle: 'Confirm stay',
          confirmHint:
              'Guest counts feed DAE forms. Type one side — the other '
              'auto-fills from party size.',
          confirmNonLodgingNote: '',
          confirmedSnack: 'Stay confirmed — tourist receipt updated.',
          rejectTitle: 'Reject stay?',
          statusApproved:
              'Account approved. Use your QR for tourist stay confirmation.',
          kpiGuestsLabel: 'Guests (month)',
          kpiFourthLabel: 'Rooms occupied',
          kpiFourthIcon: Icons.meeting_room_outlined,
        );
      case EstablishmentPack.dining:
        return const EstablishmentPackCopy(
          packLabel: 'Dining',
          opsNoun: 'visit',
          queueTitle: 'Guest visits',
          queueHint:
              'When a tourist scans your QR, the visit appears here. '
              'Enter guest counts (Male/Female, Filipino/Foreign), '
              'then confirm — they get a receipt.',
          queueEmpty:
              'No pending visits. Print your QR and ask guests to scan it.',
          recentTitle: 'Recent confirmed',
          recentEmpty: 'No confirmed visits yet.',
          chartTitle: 'Visits · last 14 days',
          chartSubtitle: 'Confirmed guest visits per day',
          calendarSubtitle: 'Days with confirmed visits',
          qrHint:
              'Tourists scan this to start a visit request for your staff.',
          confirmTitle: 'Confirm visit',
          confirmHint:
              'Guest counts feed DAE forms. Type one side — the other '
              'auto-fills from party size.',
          confirmNonLodgingNote:
              'Dining visit: nights/rooms are not required.',
          confirmedSnack: 'Visit confirmed — tourist receipt updated.',
          rejectTitle: 'Reject visit?',
          statusApproved:
              'Account approved. Use your QR for guest visit confirmation.',
          kpiGuestsLabel: 'Guests (month)',
          kpiFourthLabel: 'Avg party size',
          kpiFourthIcon: Icons.dining_outlined,
        );
      case EstablishmentPack.venue:
        return const EstablishmentPackCopy(
          packLabel: 'Venue',
          opsNoun: 'visit',
          queueTitle: 'Visitor check-ins',
          queueHint:
              'When a tourist scans your QR, the check-in appears here. '
              'Enter visitor counts (Male/Female, Filipino/Foreign), '
              'then confirm — they get a receipt.',
          queueEmpty:
              'No pending check-ins. Print your QR and ask visitors to scan it.',
          recentTitle: 'Recent confirmed',
          recentEmpty: 'No confirmed visits yet.',
          chartTitle: 'Visits · last 14 days',
          chartSubtitle: 'Confirmed visits per day',
          calendarSubtitle: 'Days with confirmed visits',
          qrHint:
              'Tourists scan this to start a visitor check-in for your staff.',
          confirmTitle: 'Confirm visit',
          confirmHint:
              'Visitor counts feed DAE forms. Type one side — the other '
              'auto-fills from party size.',
          confirmNonLodgingNote:
              'Venue visit: nights/rooms are not required.',
          confirmedSnack: 'Visit confirmed — tourist receipt updated.',
          rejectTitle: 'Reject visit?',
          statusApproved:
              'Account approved. Use your QR for visitor check-in confirmation.',
          kpiGuestsLabel: 'Visitors (month)',
          kpiFourthLabel: 'Peak day',
          kpiFourthIcon: Icons.trending_up_rounded,
        );
    }
  }
}

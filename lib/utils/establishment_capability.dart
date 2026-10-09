import 'package:flutter/material.dart';

/// Capability packs for tourism establishments (drive register columns + DAE fields).
enum EstablishmentPack {
  lodging,
  dining,
  venue,
}

/// UI labels for an [EstablishmentPack].
class EstablishmentPackCopy {
  const EstablishmentPackCopy({required this.packLabel});

  final String packLabel;
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

  /// Categories that host MICE events by default (others opt in on Profile).
  static const miceDefaultCategories = {'events place'};

  static bool defaultHostsMice(String? category) =>
      miceDefaultCategories.contains(_norm(category));

  /// Establishment field `hostsMice`; unset → category default.
  static bool hostsMice(String? category, Object? hostsMiceField) =>
      hostsMiceField is bool ? hostsMiceField : defaultHostsMice(category);

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

  static EstablishmentPackCopy copyFor(String? category) => EstablishmentPackCopy(
        packLabel: switch (packFor(category)) {
          EstablishmentPack.lodging => 'Lodging',
          EstablishmentPack.dining => 'Dining',
          EstablishmentPack.venue => 'Venue',
        },
      );
}

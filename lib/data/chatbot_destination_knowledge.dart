import 'package:atmos_trs_system/data/featured_destinations.dart';

/// Answers tourist-spot questions using the same data shown in Home / Discover.
class ChatbotDestinationKnowledge {
  ChatbotDestinationKnowledge._();

  static const _aliases = <String, List<String>>{
    'bless_amare_sunrise_beach': [
      'bless amare',
      'sunrise beach',
      'baliangao beach',
      'baliangao',
      'cabgan',
      'tugas',
    ],
    'piduan_falls': ['piduan', 'curtain falls', 'don victoriano', 'donvic'],
    'ozamiz_asenso_wellness_park': [
      'ozamiz wellness',
      'wellness park',
      'asenso ozamiz',
      'baybay triunfo',
    ],
    'ozamiz_cotta_fort_shrine': [
      'cotta',
      'cotta fort',
      'cotta shrine',
      'fort and shrine',
      'fuerte',
    ],
    'ozamiz_immaculate_conception_cathedral': [
      'immaculate conception',
      'cathedral',
      'ozamiz cathedral',
      'ozamiz church',
    ],
    'ozamiz_cotta_beach': [
      'cotta beach',
      'ozamiz beach',
      'panguil bay',
    ],
    'ozamiz_cotta_fort_wellness_park': [
      'ozamiz wellness park cotta',
    ],
    'tangub_asenso_global_gardens': [
      'global garden',
      'global gardens',
      'asenso global',
      'hoyohoy',
      'tangub',
    ],
    'jimenez_st_john_the_baptist_church': [
      'jimenez church',
      'jimenez',
      'st john',
      'saint john the baptist',
      'john the baptist',
    ],
    'oroquieta_city_boulevard_and_peoples_park': [
      'oroquieta plaza',
      'city plaza',
      'oroquieta city',
      'peoples park',
      "people's park",
    ],
    'sinacaban_asenso_aquamarine_park': [
      'amorap',
      'aquamarine',
      'aquamarine park',
      'sinacaban',
      'libertad bajo',
    ],
  };

  /// Returns a spot-specific answer from in-app destination data, or null.
  static String? reply(String normalizedInput, String lang) {
    if (_isListAllQuery(normalizedInput)) {
      return _listAllSpots(lang);
    }

    final intent = _detectIntent(normalizedInput);
    final spot = _findBestSpot(normalizedInput);
    if (spot == null) {
      if (intent != _SpotIntent.unknown) {
        return _whichSpotPrompt(lang, intent);
      }
      return null;
    }

    return _formatAnswer(spot, intent, lang);
  }

  static bool _isListAllQuery(String input) {
    return _containsAny(input, [
      'list of destination',
      'list of spot',
      'all destination',
      'all spot',
      'tanan nga destination',
      'lista ng destination',
      'what destination',
      'unsa nga destination',
      'ano ang mga destination',
      'featured destination',
    ]);
  }

  static String _listAllSpots(String lang) {
    final names = kFeaturedDestinations
        .map((d) => d['name']?.toString().trim() ?? '')
        .where((n) => n.isNotEmpty)
        .toList();
    final bulletList = names.map((n) => '• $n').join('\n');
    return _localized(
      lang: lang,
      en:
          'Featured destinations in ATMOS-TRS:\n$bulletList\n\n'
          'Open Home → Discover or Explore for photos and full details. '
          'Ask me about opening hours, entrance fee, address, or nearby places for any spot above!',
      fil:
          'Featured destinations sa ATMOS-TRS:\n$bulletList\n\n'
          'Buksan ang Home → Discover o Explore para sa photos at full details. '
          'Tanungin ako tungkol sa opening hours, entrance fee, address, o nearby places para sa alinmang spot!',
      ceb:
          'Featured destinations sa ATMOS-TRS:\n$bulletList\n\n'
          'Ablihi ang Home → Discover o Explore para sa photos ug full details. '
          'Pangutana ko bahin sa opening hours, entrance fee, address, o nearby places para sa bisan unsang spot!',
    );
  }

  static String _whichSpotPrompt(String lang, _SpotIntent intent) {
    final topicEn = switch (intent) {
      _SpotIntent.openingHours => 'opening hours',
      _SpotIntent.entranceFee => 'entrance fee',
      _SpotIntent.address => 'address',
      _SpotIntent.nearbyRestaurants => 'nearby restaurants',
      _SpotIntent.nearbyHotels => 'nearby hotels',
      _SpotIntent.nearbyCafes => 'nearby cafés',
      _SpotIntent.nearbyAttractions => 'nearby attractions',
      _SpotIntent.cottageRates => 'cottage rates',
      _ => 'spot info',
    };
    final topicFil = topicEn;
    final topicCeb = topicEn;
    final names = kFeaturedDestinations
        .take(5)
        .map((d) => d['name']?.toString() ?? '')
        .join(', ');
    return _localized(
      lang: lang,
      en:
          'Which destination do you mean? I have verified $topicEn for spots like $names, and more. '
          'Try: "Bless Amare opening hours" or "AMORAP entrance fee".',
      fil:
          'Aling destination ang tinutukoy mo? May verified $topicFil ako para sa spots tulad ng $names, at iba pa. '
          'Halimbawa: "Bless Amare opening hours" o "AMORAP entrance fee".',
      ceb:
          'Unsang destination imong gipasabot? Naay verified $topicCeb ko para sa spots sama sa $names, ug uban pa. '
          'Pananglitan: "Bless Amare opening hours" o "AMORAP entrance fee".',
    );
  }

  static Map<String, dynamic>? _findBestSpot(String input) {
    Map<String, dynamic>? best;
    var bestScore = 0;

    for (final spot in kFeaturedDestinations) {
      final score = _scoreSpot(input, spot);
      if (score > bestScore) {
        bestScore = score;
        best = spot;
      }
    }

    return bestScore >= 4 ? best : null;
  }

  static int _scoreSpot(String input, Map<String, dynamic> spot) {
    var score = 0;
    final name = _normalize(spot['name']?.toString() ?? '');
    final spotId = _normalize(spot['spotId']?.toString() ?? '');
    final location = _normalize(spot['location']?.toString() ?? '');

    for (final token in _tokens(name)) {
      if (token.length < 3) continue;
      if (input.contains(token)) score += 3;
    }

    if (spotId.isNotEmpty && input.contains(spotId.replaceAll('_', ' '))) {
      score += 5;
    }
    if (spotId.isNotEmpty && input.contains(spotId.replaceAll('_', ''))) {
      score += 3;
    }

    for (final token in _tokens(location)) {
      if (token.length < 4) continue;
      if (input.contains(token)) score += 1;
    }

    final aliases = _aliases[spot['spotId']?.toString() ?? ''] ?? const [];
    for (final alias in aliases) {
      if (input.contains(_normalize(alias))) score += 5;
    }

    return score;
  }

  static _SpotIntent _detectIntent(String input) {
    if (_containsAny(input, [
      'opening hour',
      'open time',
      'oras',
      'bukas',
      'open ba',
      'kanus a bukas',
      'what time',
      'kailan bukas',
      'hours',
    ])) {
      return _SpotIntent.openingHours;
    }
    if (_containsAny(input, [
      'entrance fee',
      'entrance',
      'fee',
      'bayad',
      'presyo',
      'pila',
      'tagpila',
      'magkano',
      'how much',
      'libre',
      'free ba',
    ])) {
      return _SpotIntent.entranceFee;
    }
    if (_containsAny(input, [
      'cottage',
      'table rate',
      'umbrella',
      'rental',
    ])) {
      return _SpotIntent.cottageRates;
    }
    if (_containsAny(input, [
      'address',
      'location',
      'asa',
      'asa dapit',
      'where is',
      'where s',
      'saan',
      'nasaang',
      'barangay',
    ])) {
      return _SpotIntent.address;
    }
    if (_containsAny(input, [
      'nearby restaurant',
      'restaurant',
      'kainan',
      'food',
      'eat',
      'pang eat',
      'dining',
      'camp sawi',
      'nami',
    ])) {
      return _SpotIntent.nearbyRestaurants;
    }
    if (_containsAny(input, [
      'nearby hotel',
      'hotel',
      'tulugan',
      'pang stay',
      'accommodation',
      'stay',
      'inn',
      'lodge',
    ])) {
      return _SpotIntent.nearbyHotels;
    }
    if (_containsAny(input, [
      'nearby cafe',
      'café',
      'cafe',
      'coffee',
      'kape',
      'kapehan',
    ])) {
      return _SpotIntent.nearbyCafes;
    }
    if (_containsAny(input, [
      'nearby attraction',
      'attraction',
      'attractions',
      'nearby place',
      'what else',
      'duol',
      'malapit',
    ])) {
      return _SpotIntent.nearbyAttractions;
    }
    if (_containsAny(input, [
      'about',
      'tell me',
      'info',
      'impormasyon',
      'details',
      'describe',
    ])) {
      return _SpotIntent.overview;
    }
    return _SpotIntent.unknown;
  }

  static String _formatAnswer(
    Map<String, dynamic> spot,
    _SpotIntent intent,
    String lang,
  ) {
    final name = spot['name']?.toString() ?? 'Destination';
    final resolvedIntent =
        intent == _SpotIntent.unknown ? _SpotIntent.overview : intent;

    return switch (resolvedIntent) {
      _SpotIntent.openingHours => _openingHours(name, spot, lang),
      _SpotIntent.entranceFee => _entranceFee(name, spot, lang),
      _SpotIntent.cottageRates => _cottageRates(name, spot, lang),
      _SpotIntent.address => _address(name, spot, lang),
      _SpotIntent.nearbyRestaurants =>
        _nearbyList(name, spot, 'nearbyRestaurants', 'Restaurants', lang),
      _SpotIntent.nearbyHotels =>
        _nearbyList(name, spot, 'nearbyHotels', 'Hotels', lang),
      _SpotIntent.nearbyCafes =>
        _nearbyList(name, spot, 'nearbyCafes', 'Cafés', lang),
      _SpotIntent.nearbyAttractions =>
        _nearbyList(name, spot, 'nearbyAttractions', 'Attractions', lang),
      _SpotIntent.overview => _overview(name, spot, lang),
      _SpotIntent.unknown => _overview(name, spot, lang),
    };
  }

  static String _openingHours(
    String name,
    Map<String, dynamic> spot,
    String lang,
  ) {
    final hours = spot['openingHours']?.toString().trim() ?? '';
    if (hours.isEmpty) {
      return _missingField(name, 'opening hours', lang);
    }
    return _localized(
      lang: lang,
      en: '🕐 **$name** opening hours (from ATMOS-TRS):\n$hours',
      fil: '🕐 **$name** opening hours (mula sa ATMOS-TRS):\n$hours',
      ceb: '🕐 **$name** opening hours (gikan sa ATMOS-TRS):\n$hours',
    ).replaceAll('**', '');
  }

  static String _entranceFee(
    String name,
    Map<String, dynamic> spot,
    String lang,
  ) {
    final fee = spot['entranceFee']?.toString().trim() ?? '';
    if (fee.isEmpty) {
      return _missingField(name, 'entrance fee', lang);
    }
    return _localized(
      lang: lang,
      en: '💰 **$name** entrance fee (from ATMOS-TRS):\n$fee',
      fil: '💰 **$name** entrance fee (mula sa ATMOS-TRS):\n$fee',
      ceb: '💰 **$name** entrance fee (gikan sa ATMOS-TRS):\n$fee',
    ).replaceAll('**', '');
  }

  static String _cottageRates(
    String name,
    Map<String, dynamic> spot,
    String lang,
  ) {
    final rates = spot['cottageRates']?.toString().trim() ?? '';
    if (rates.isEmpty) {
      return _localized(
        lang: lang,
        en:
            'No cottage/table rates are listed for $name in the app yet. '
            'Check the destination detail page on Home → Discover for the latest fees.',
        fil:
            'Wala pang nakalistang cottage/table rates para sa $name sa app. '
            'Tingnan ang destination detail sa Home → Discover.',
        ceb:
            'Wala pay nakalistang cottage/table rates para sa $name sa app. '
            'Tan-awa ang destination detail sa Home → Discover.',
      );
    }
    return _localized(
      lang: lang,
      en: '🏕️ **$name** cottages & tables (from ATMOS-TRS):\n$rates',
      fil: '🏕️ **$name** cottages & tables (mula sa ATMOS-TRS):\n$rates',
      ceb: '🏕️ **$name** cottages & tables (gikan sa ATMOS-TRS):\n$rates',
    ).replaceAll('**', '');
  }

  static String _address(
    String name,
    Map<String, dynamic> spot,
    String lang,
  ) {
    final location = spot['location']?.toString().trim() ?? '';
    if (location.isEmpty) {
      return _missingField(name, 'address', lang);
    }
    return _localized(
      lang: lang,
      en:
          '📍 **$name** address (from ATMOS-TRS):\n$location\n\n'
          'Tip: Tap Get Directions on the destination page for Google Maps routing.',
      fil:
          '📍 **$name** address (mula sa ATMOS-TRS):\n$location\n\n'
          'Tip: I-tap ang Get Directions sa destination page para sa Google Maps.',
      ceb:
          '📍 **$name** address (gikan sa ATMOS-TRS):\n$location\n\n'
          'Tip: I-tap ang Get Directions sa destination page para sa Google Maps.',
    ).replaceAll('**', '');
  }

  static String _nearbyList(
    String name,
    Map<String, dynamic> spot,
    String key,
    String labelEn,
    String lang,
  ) {
    final items = _nearbyEntries(spot[key]);
    if (items.isEmpty) {
      return _localized(
        lang: lang,
        en:
            'No nearby ${labelEn.toLowerCase()} are listed for $name in the app yet. '
            'Open Home → Discover → $name for updates.',
        fil:
            'Wala pang nearby ${labelEn.toLowerCase()} na nakalista para sa $name. '
            'Buksan ang Home → Discover → $name.',
        ceb:
            'Wala pay nearby ${labelEn.toLowerCase()} nga nakalista para sa $name. '
            'Ablihi ang Home → Discover → $name.',
      );
    }

    final noteKey = switch (key) {
      'nearbyHotels' => 'nearbyHotelsNote',
      'nearbyRestaurants' => 'nearbyRestaurantsNote',
      _ => null,
    };
    final note = noteKey != null ? spot[noteKey]?.toString().trim() ?? '' : '';

    final list = items.map(_formatNearbyLine).join('\n');
    final header = note.isNotEmpty ? '$note\n\n' : '';
    return _localized(
      lang: lang,
      en: 'Nearby ${labelEn.toLowerCase()} for **$name** (from ATMOS-TRS):\n$header$list',
      fil: 'Nearby ${labelEn.toLowerCase()} para sa **$name** (mula sa ATMOS-TRS):\n$header$list',
      ceb: 'Nearby ${labelEn.toLowerCase()} para sa **$name** (gikan sa ATMOS-TRS):\n$header$list',
    ).replaceAll('**', '');
  }

  static String _formatNearbyLine(_NearbyEntry entry) {
    final parts = <String>[entry.name];
    if (entry.category.isNotEmpty) parts.add(entry.category);
    if (entry.rating != null) {
      parts.add('${entry.rating!.toStringAsFixed(1)}★');
    }
    if (entry.priceRange.isNotEmpty) parts.add(entry.priceRange);
    var line = '• ${parts.join(' · ')}';
    if (entry.location.isNotEmpty) line += '\n  📍 ${entry.location}';
    if (entry.driveMinutes != null) {
      line += '\n  🚗 ~${entry.driveMinutes!.round()} min drive';
    }
    if (entry.description.isNotEmpty) line += '\n  ${entry.description}';
    return line;
  }

  static List<_NearbyEntry> _nearbyEntries(dynamic raw) {
    if (raw is! List) return const [];
    return raw
        .map((e) {
          if (e is Map) {
            final name = e['name']?.toString().trim() ?? '';
            if (name.isEmpty) return null;
            return _NearbyEntry(
              name: name,
              category: e['category']?.toString().trim() ?? '',
              rating: (e['rating'] as num?)?.toDouble(),
              priceRange: e['priceRange']?.toString().trim() ?? '',
              location: e['location']?.toString().trim() ??
                  e['address']?.toString().trim() ??
                  '',
              driveMinutes: (e['driveMinutes'] as num?)?.toDouble(),
              description: e['description']?.toString().trim() ?? '',
            );
          }
          final name = e.toString().trim();
          if (name.isEmpty) return null;
          return _NearbyEntry(name: name);
        })
        .whereType<_NearbyEntry>()
        .toList();
  }

  static List<String> _nearbyNames(dynamic raw) {
    return _nearbyEntries(raw).map((e) => e.name).toList();
  }

  static String _overview(
    String name,
    Map<String, dynamic> spot,
    String lang,
  ) {
    final description = spot['description']?.toString().trim() ?? '';
    final location = spot['location']?.toString().trim() ?? '';
    final hours = spot['openingHours']?.toString().trim() ?? '';
    final fee = spot['entranceFee']?.toString().trim() ?? '';
    final category = spot['category']?.toString().trim() ?? '';

    final buffer = StringBuffer();
    buffer.writeln(_localized(
      lang: lang,
      en: 'Here\'s what ATMOS-TRS shows for **$name**:',
      fil: 'Ito ang nakalista sa ATMOS-TRS para sa **$name**:',
      ceb: 'Mao ni ang nakalista sa ATMOS-TRS para sa **$name**:',
    ).replaceAll('**', ''));
    if (category.isNotEmpty) {
      buffer.writeln(_localized(
        lang: lang,
        en: 'Category: $category',
        fil: 'Category: $category',
        ceb: 'Category: $category',
      ));
    }
    if (description.isNotEmpty) buffer.writeln(description);
    if (location.isNotEmpty) {
      buffer.writeln(_localized(
        lang: lang,
        en: '📍 $location',
        fil: '📍 $location',
        ceb: '📍 $location',
      ));
    }
    if (hours.isNotEmpty) {
      buffer.writeln(_localized(
        lang: lang,
        en: '🕐 $hours',
        fil: '🕐 $hours',
        ceb: '🕐 $hours',
      ));
    }
    if (fee.isNotEmpty) {
      buffer.writeln(_localized(
        lang: lang,
        en: '💰 $fee',
        fil: '💰 $fee',
        ceb: '💰 $fee',
      ));
    }

    final restaurants = _nearbyNames(spot['nearbyRestaurants']);
    if (restaurants.isNotEmpty) {
      buffer.writeln(_localized(
        lang: lang,
        en: '🍽️ Nearby restaurants: ${restaurants.take(3).join(', ')}',
        fil: '🍽️ Nearby restaurants: ${restaurants.take(3).join(', ')}',
        ceb: '🍽️ Nearby restaurants: ${restaurants.take(3).join(', ')}',
      ));
    }
    final hotels = _nearbyNames(spot['nearbyHotels']);
    if (hotels.isNotEmpty) {
      buffer.writeln(_localized(
        lang: lang,
        en: '🏨 Nearby hotels: ${hotels.take(3).join(', ')}',
        fil: '🏨 Nearby hotels: ${hotels.take(3).join(', ')}',
        ceb: '🏨 Nearby hotels: ${hotels.take(3).join(', ')}',
      ));
    }

    buffer.writeln(_localized(
      lang: lang,
      en: 'Open Home → Discover for photos, nearby cafés, and Get Directions.',
      fil: 'Buksan ang Home → Discover para sa photos, nearby cafés, at Get Directions.',
      ceb: 'Ablihi ang Home → Discover para sa photos, nearby cafés, ug Get Directions.',
    ));

    return buffer.toString().trim();
  }

  static String _missingField(
    String name,
    String field,
    String lang,
  ) {
    return _localized(
      lang: lang,
      en:
          'I don\'t have $field listed for $name in the app yet. '
          'Open Home → Discover → $name for the latest details.',
      fil:
          'Wala pang $field na nakalista para sa $name sa app. '
          'Buksan ang Home → Discover → $name.',
      ceb:
          'Wala pay $field nga nakalista para sa $name sa app. '
          'Ablihi ang Home → Discover → $name.',
    );
  }

  static String _localized({
    required String lang,
    required String en,
    required String fil,
    required String ceb,
  }) {
    return switch (lang) {
      'fil' => fil,
      'ceb' => ceb,
      _ => en,
    };
  }

  static bool _containsAny(String input, List<String> terms) {
    return terms.any(input.contains);
  }

  static String _normalize(String value) {
    return value
        .toLowerCase()
        .replaceAll(RegExp(r'[^\w\s]'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  static List<String> _tokens(String value) {
    return _normalize(value).split(' ').where((t) => t.isNotEmpty).toList();
  }
}

enum _SpotIntent {
  openingHours,
  entranceFee,
  cottageRates,
  address,
  nearbyRestaurants,
  nearbyHotels,
  nearbyCafes,
  nearbyAttractions,
  overview,
  unknown,
}

class _NearbyEntry {
  const _NearbyEntry({
    required this.name,
    this.category = '',
    this.rating,
    this.priceRange = '',
    this.location = '',
    this.driveMinutes,
    this.description = '',
  });

  final String name;
  final String category;
  final double? rating;
  final String priceRange;
  final String location;
  final double? driveMinutes;
  final String description;
}

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
      'cotta fort',
      'cotta shrine',
      'fort and shrine',
      'fuerte',
      'ozamiz wellness park cotta',
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
      'oroquieta city plaza',
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
  static String? reply(
    String normalizedInput,
    String lang, {
    String? followUpSpotId,
    void Function(String spotId)? rememberSpot,
  }) {
    final intent = _detectIntent(normalizedInput);
    if (_isNearbyIntent(intent)) {
      final cityReply = _cityNearbyReply(
        normalizedInput,
        lang,
        intent,
        rememberSpot,
      );
      if (cityReply != null) return cityReply;
    }

    if (_isListAllQuery(normalizedInput) && !_isNearbyIntent(intent)) {
      return _listAllSpots(lang);
    }

    var spot = _findBestSpot(normalizedInput);
    if (spot == null &&
        followUpSpotId != null &&
        followUpSpotId.isNotEmpty &&
        intent != _SpotIntent.unknown) {
      spot = _spotById(followUpSpotId);
    }
    if (spot == null) {
      if (_isNearbyIntent(intent)) {
        return _whichCityPrompt(lang, intent);
      }
      if (intent != _SpotIntent.unknown) {
        return _whichSpotPrompt(lang, intent);
      }
      return null;
    }

    final spotId = spot['spotId']?.toString() ?? '';
    if (spotId.isNotEmpty) rememberSpot?.call(spotId);
    return _formatAnswer(spot, intent, lang);
  }

  static Map<String, dynamic>? _spotById(String spotId) {
    for (final spot in kFeaturedDestinations) {
      if (spot['spotId']?.toString() == spotId) return spot;
    }
    return null;
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
      'pasyalan',
      'tourist attraction',
      'attractions can i visit',
      'what tourist',
      'what tourist attraction',
      'mga pasyalan',
      'lugar nga bisitahan',
    ]);
  }

  static bool _isNearbyIntent(_SpotIntent intent) {
    return intent == _SpotIntent.nearbyRestaurants ||
        intent == _SpotIntent.nearbyHotels ||
        intent == _SpotIntent.nearbyCafes ||
        intent == _SpotIntent.nearbyAttractions;
  }

  static String _listAllSpots(String lang) {
    final names = kFeaturedDestinations
        .map((d) => d['name']?.toString().trim() ?? '')
        .where((n) => n.isNotEmpty)
        .toList();
    final numbered = [
      for (var i = 0; i < names.length; i++) '**${i + 1}. ${names[i]}**',
    ].join('\n');
    return _localized(
      lang: lang,
      en:
          'Here are featured spots you can visit in Misamis Occidental! 😊\n\n'
          '$numbered\n\n'
          'Ask me the entrance fee, hours, or address of any spot. Open **Home → Discover** for photos.',
      fil:
          'Narito ang mga featured pasyalan sa Misamis Occidental! 😊\n\n'
          '$numbered\n\n'
          'Tanungin mo ako ng entrance fee, oras, o address ng kahit alin. Buksan ang **Home → Discover** para sa photos.',
      ceb:
          'Ania ang featured nga pasyalan sa Misamis Occidental! 😊\n\n'
          '$numbered\n\n'
          'Pangutana ko kung pila ang entrance, unsa ang hours, o asa dapit. Ablihi ang **Home → Discover** para sa photos.',
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
      'nearby restaurant',
      'restaurant',
      'kainan',
      'kaon',
      'food',
      'eat',
      'pang eat',
      'dining',
      'resto',
      'camp sawi',
      'nami',
      'malapit na kainan',
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
      'nearby place',
      'what else',
      'duol sa',
      'malapit na lugar',
    ])) {
      return _SpotIntent.nearbyAttractions;
    }
    if (_containsAny(input, [
      'address',
      'location',
      'asa dapit',
      'asa',
      'where is',
      'where s',
      'saan',
      'nasaang',
      'barangay',
    ])) {
      return _SpotIntent.address;
    }
    if (_containsAny(input, [
      'about',
      'tell me',
      'info',
      'impormasyon',
      'details',
      'describe',
      'virtual tour',
      'vr tour',
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
      en: '🕘 **$name** opening hours\n\n$hours\n\n'
          'Hours can change — check the spot page on **Home → Discover** if you need the latest.',
      fil: '🕘 Oras ng **$name**\n\n$hours\n\n'
          'Puwedeng magbago ang oras — tingnan ang spot page sa **Home → Discover** para sa latest.',
      ceb: '🕘 Oras sa **$name**\n\n$hours\n\n'
          'Pwede mag-usab ang oras — tan-awa ang spot page sa **Home → Discover** kung kinahanglan nimo ang latest.',
    );
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
    if (!_hasListedAmount(fee)) {
      return _localized(
        lang: lang,
        en: 'I don\'t have an exact peso amount for **$name** yet.\n\n'
            'ATMOS-TRS currently lists:\n$fee\n\n'
            'Please check the official contact or page — I won\'t invent a price. 😊',
        fil: 'Wala pa akong exact na peso amount para sa **$name**.\n\n'
            'Nakasulat sa ATMOS-TRS:\n$fee\n\n'
            'I-check ang official contact o page — hindi ako mag-iimbento ng presyo. 😊',
        ceb: 'Wala koy exact nga peso amount para sa **$name**.\n\n'
            'Ang naka-list sa ATMOS-TRS:\n$fee\n\n'
            'I-check ang official contact o page — dili ko mag-imbento og presyo. 😊',
      );
    }
    return _localized(
      lang: lang,
      en: 'The listed entrance fee for **$name**:\n\n$fee\n\n'
          'This can change — confirm with the official page if you need the latest. 😊',
      fil: 'Ang naka-list na entrance fee sa **$name**:\n\n$fee\n\n'
          'Puwedeng magbago — i-check ang official page kung kailangan mo ang latest. 😊',
      ceb: 'Ang naka-list nga entrance fee sa **$name**:\n\n$fee\n\n'
          'Pwede mag-usab — tan-awa ang official page kung kinahanglan nimo ang latest. 😊',
    );
  }

  static bool _hasListedAmount(String fee) {
    final lower = fee.toLowerCase();
    if (RegExp(r'vary|check the|see .+official|contact info').hasMatch(lower)) {
      return false;
    }
    return fee.contains('₱') ||
        lower.contains('php') ||
        lower.contains('free') ||
        lower.contains('libre');
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
      en: '🏕️ Cottages & tables — $name\n\n$rates\n\n'
          'Open Home → Discover → $name for full details.',
      fil: '🏕️ Cottages & tables — $name\n\n$rates\n\n'
          'Buksan ang Home → Discover → $name para sa full details.',
      ceb: '🏕️ Cottages & tables — $name\n\n$rates\n\n'
          'Ablihi ang Home → Discover → $name para sa full details.',
    );
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
      en: '**$name** is in:\n\n$location\n\n'
          'Open **Home → Discover** and tap Get Directions for the map. 😊',
      fil: 'Nasa **$name**:\n\n$location\n\n'
          'Buksan ang **Home → Discover** at i-tap ang Get Directions para sa mapa. 😊',
      ceb: 'Naa ang **$name** sa:\n\n$location\n\n'
          'Ablihi ang **Home → Discover** ug i-tap ang Get Directions para sa mapa. 😊',
    );
  }

  static const _maxNearbyShown = 6;

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
            'No nearby ${labelEn.toLowerCase()} are listed for $name in ATMOS-TRS yet. '
            'Open **Home → Discover → $name** for updates.',
        fil:
            'Wala pang nearby ${labelEn.toLowerCase()} na naka-list para sa $name sa ATMOS-TRS. '
            'Buksan ang **Home → Discover → $name**.',
        ceb:
            'Wala pay nearby ${labelEn.toLowerCase()} nga naka-list para sa $name sa ATMOS-TRS. '
            'Ablihi ang **Home → Discover → $name**.',
      );
    }

    final noteKey = switch (key) {
      'nearbyHotels' => 'nearbyHotelsNote',
      'nearbyRestaurants' => 'nearbyRestaurantsNote',
      _ => null,
    };
    final note = noteKey != null ? spot[noteKey]?.toString().trim() ?? '' : '';
    return _composeNearbyAnswer(
      lang: lang,
      key: key,
      placeLabel: name,
      items: items,
      note: note,
    );
  }

  static String? _cityNearbyReply(
    String input,
    String lang,
    _SpotIntent intent,
    void Function(String spotId)? rememberSpot,
  ) {
    final city = _cityInInput(input);
    if (city == null) return null;

    final key = switch (intent) {
      _SpotIntent.nearbyRestaurants => 'nearbyRestaurants',
      _SpotIntent.nearbyHotels => 'nearbyHotels',
      _SpotIntent.nearbyCafes => 'nearbyCafes',
      _SpotIntent.nearbyAttractions => 'nearbyAttractions',
      _ => '',
    };
    if (key.isEmpty) return null;

    final seen = <String>{};
    final items = <_NearbyEntry>[];
    String? rememberId;
    for (final spot in kFeaturedDestinations) {
      final haystack =
          '${spot['name'] ?? ''} ${spot['location'] ?? ''} ${spot['spotId'] ?? ''}'
              .toLowerCase();
      if (!haystack.contains(city.match)) continue;
      rememberId ??= spot['spotId']?.toString();
      for (final entry in _nearbyEntries(spot[key])) {
        final id = entry.name.toLowerCase();
        if (!seen.add(id)) continue;
        items.add(entry);
      }
    }
    if (items.isEmpty) return null;
    if (rememberId != null && rememberId.isNotEmpty) {
      rememberSpot?.call(rememberId);
    }
    return _composeNearbyAnswer(
      lang: lang,
      key: key,
      placeLabel: city.label,
      items: items,
      note: '',
    );
  }

  static String _composeNearbyAnswer({
    required String lang,
    required String key,
    required String placeLabel,
    required List<_NearbyEntry> items,
    required String note,
  }) {
    final shown = items.take(_maxNearbyShown).toList();
    final extra = items.length - shown.length;
    final numbered = [
      for (var i = 0; i < shown.length; i++)
        _formatNearbyBlock(shown[i], index: i + 1, lang: lang),
    ].join('\n\n');
    final noteBlock = note.isNotEmpty ? '$note\n\n' : '';
    final moreLine = extra <= 0
        ? ''
        : _localized(
            lang: lang,
            en: '\n\n+$extra more in **Home → Discover**.',
            fil: '\n\n+$extra pa sa **Home → Discover**.',
            ceb: '\n\n+$extra pa sa **Home → Discover**.',
          );
    final intro = _nearbyIntro(lang, key, placeLabel);
    final footer = _localized(
      lang: lang,
      en:
          'Details above are from ATMOS-TRS. Missing numbers are left out on purpose — confirm with the place if you need the latest.',
      fil:
          'Galing sa ATMOS-TRS ang details sa itaas. Hindi ako mag-iimbento ng missing numbers — i-check ang establishment kung kailangan mo ang latest.',
      ceb:
          'Gikan sa ATMOS-TRS ang details sa ibabaw. Dili ko mag-imbento og missing numbers — tan-awa ang establishment kung kinahanglan nimo ang latest.',
    );
    return '$intro\n\n$noteBlock$numbered$moreLine\n\n$footer';
  }

  static String _nearbyIntro(String lang, String key, String place) {
    return switch (key) {
      'nearbyRestaurants' => _localized(
          lang: lang,
          en: 'Here are some restaurants you can check out in $place! 😊',
          fil: 'Narito ang ilang restaurant na maaari mong puntahan sa $place! 😊',
          ceb: 'Naa koy pipila ka restaurant nga pwede nimo tan-awon sa $place! 😊',
        ),
      'nearbyHotels' => _localized(
          lang: lang,
          en: 'Here are places to stay near $place! 😊',
          fil: 'Narito ang ilang tuluyan malapit sa $place! 😊',
          ceb: 'Ania ang pipila ka tulugan duol sa $place! 😊',
        ),
      'nearbyCafes' => _localized(
          lang: lang,
          en: 'Here are cafés near $place! 😊',
          fil: 'Narito ang ilang café malapit sa $place! 😊',
          ceb: 'Ania ang pipila ka café duol sa $place! 😊',
        ),
      _ => _localized(
          lang: lang,
          en: 'Here are nearby places around $place! 😊',
          fil: 'Narito ang mga malapit na lugar sa $place! 😊',
          ceb: 'Ania ang duol nga mga lugar sa $place! 😊',
        ),
    };
  }

  static String _whichCityPrompt(String lang, _SpotIntent intent) {
    final topic = switch (intent) {
      _SpotIntent.nearbyRestaurants => _localized(
          lang: lang,
          en: 'restaurants',
          fil: 'mga kainan',
          ceb: 'mga restaurant',
        ),
      _SpotIntent.nearbyHotels => _localized(
          lang: lang,
          en: 'hotels',
          fil: 'mga hotel',
          ceb: 'mga hotel',
        ),
      _SpotIntent.nearbyCafes => _localized(
          lang: lang,
          en: 'cafés',
          fil: 'mga café',
          ceb: 'mga café',
        ),
      _ => _localized(
          lang: lang,
          en: 'nearby places',
          fil: 'malapit na lugar',
          ceb: 'duol nga lugar',
        ),
    };
    return _localized(
      lang: lang,
      en:
          'Which city or spot? Try "restaurants in Oroquieta" or "AMORAP nearby $topic".',
      fil:
          'Aling city o spot? Halimbawa: "kainan sa Oroquieta" o "AMORAP nearby $topic".',
      ceb:
          'Asa nimo dapit? Pananglitan: "restaurant sa Oroquieta" o "AMORAP nearby $topic".',
    );
  }

  static ({String match, String label})? _cityInInput(String input) {
    const cities = <String, String>{
      'oroquieta': 'Oroquieta City',
      'ozamiz': 'Ozamiz City',
      'ozamis': 'Ozamiz City',
      'tangub': 'Tangub City',
      'jimenez': 'Jimenez',
      'sinacaban': 'Sinacaban',
      'baliangao': 'Baliangao',
      'plaridel': 'Plaridel',
      'clarin': 'Clarin',
      'tudela': 'Tudela',
      'aloran': 'Aloran',
      'lopez jaena': 'Lopez Jaena',
      'panoan': 'Panaon',
      'panaon': 'Panaon',
      'calamba': 'Calamba',
      'concepcion': 'Concepcion',
      'sapang dalaga': 'Sapang Dalaga',
      'don victoriano': 'Don Victoriano',
    };
    for (final entry in cities.entries) {
      if (input.contains(entry.key)) {
        return (match: entry.key, label: entry.value);
      }
    }
    return null;
  }

  static String _formatNearbyBlock(
    _NearbyEntry entry, {
    required int index,
    required String lang,
  }) {
    final lines = <String>['**$index. ${entry.name}**'];
    if (entry.category.isNotEmpty) {
      lines.add('• ${_label(lang, en: 'Type', fil: 'Uri', ceb: 'Klase')}: ${entry.category}');
    }
    if (entry.location.isNotEmpty) {
      lines.add('• ${_label(lang, en: 'Address', fil: 'Address', ceb: 'Address')}: ${entry.location}');
    }
    if (entry.contact.isNotEmpty) {
      lines.add('• ${_label(lang, en: 'Contact', fil: 'Contact', ceb: 'Contact')}: ${entry.contact}');
    }
    if (entry.openingHours.isNotEmpty) {
      lines.add('• ${_label(lang, en: 'Hours', fil: 'Oras', ceb: 'Oras')}: ${entry.openingHours}');
    }
    if (entry.rating != null && entry.rating! > 0) {
      lines.add('• ${_label(lang, en: 'Rating', fil: 'Rating', ceb: 'Rating')}: ${entry.rating!.toStringAsFixed(1)}★');
    }
    if (entry.driveMinutes != null) {
      lines.add(
        '• ${_label(lang, en: 'Drive', fil: 'Byahe', ceb: 'Byahe')}: ~${entry.driveMinutes!.round()} min',
      );
    }
    if (entry.description.isNotEmpty) {
      lines.add(entry.description);
    }
    return lines.join('\n');
  }

  static String _label(
    String lang, {
    required String en,
    required String fil,
    required String ceb,
  }) {
    return _localized(lang: lang, en: en, fil: fil, ceb: ceb);
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
              contact: e['contact']?.toString().trim() ??
                  e['contactNumber']?.toString().trim() ??
                  '',
              location: e['location']?.toString().trim() ??
                  e['address']?.toString().trim() ??
                  '',
              openingHours: e['openingHours']?.toString().trim() ??
                  e['hours']?.toString().trim() ??
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
      fil: 'Ito ang naka-list sa ATMOS-TRS para sa **$name**:',
      ceb: 'Mao ni ang naka-list sa ATMOS-TRS para sa **$name**:',
    ));
    buffer.writeln();

    if (category.isNotEmpty) {
      buffer.writeln('• ${_label(lang, en: 'Category', fil: 'Kategorya', ceb: 'Kategorya')}: $category');
      buffer.writeln();
    }
    if (description.isNotEmpty) {
      buffer.writeln(description);
      buffer.writeln();
    }
    if (location.isNotEmpty) {
      buffer.writeln('📍 $location');
      buffer.writeln();
    }
    if (hours.isNotEmpty) {
      buffer.writeln('🕘 $hours');
      buffer.writeln();
    }
    if (fee.isNotEmpty) {
      buffer.writeln('💰 $fee');
      buffer.writeln();
    }
    final vr = spot['vrLink']?.toString().trim() ?? '';
    if (vr.isNotEmpty) {
      buffer.writeln(_localized(
        lang: lang,
        en: '🥽 This spot has a Virtual Tour in the app.',
        fil: '🥽 May Virtual Tour ang spot na ito sa app.',
        ceb: '🥽 Naa\'y Virtual Tour kining spot sa app.',
      ));
      buffer.writeln();
    }

    final restaurants = _nearbyNames(spot['nearbyRestaurants']);
    if (restaurants.isNotEmpty) {
      buffer.writeln(_localized(
        lang: lang,
        en: '🍽️ Nearby restaurants:',
        fil: '🍽️ Nearby restaurants:',
        ceb: '🍽️ Nearby restaurants:',
      ));
      for (final r in restaurants.take(3)) {
        buffer.writeln('• $r');
      }
      buffer.writeln();
    }
    final hotels = _nearbyNames(spot['nearbyHotels']);
    if (hotels.isNotEmpty) {
      buffer.writeln(_localized(
        lang: lang,
        en: '🏨 Nearby hotels:',
        fil: '🏨 Nearby hotels:',
        ceb: '🏨 Nearby hotels:',
      ));
      for (final h in hotels.take(3)) {
        buffer.writeln('• $h');
      }
      buffer.writeln();
    }
    final cafes = _nearbyNames(spot['nearbyCafes']);
    if (cafes.isNotEmpty) {
      buffer.writeln(_localized(
        lang: lang,
        en: '☕ Nearby cafés:',
        fil: '☕ Nearby cafés:',
        ceb: '☕ Nearby cafés:',
      ));
      for (final c in cafes.take(3)) {
        buffer.writeln('• $c');
      }
      buffer.writeln();
    }

    buffer.writeln(_localized(
      lang: lang,
      en: '➡️ Open Home → Discover for photos, nearby places, and Get Directions.',
      fil: '➡️ Buksan ang Home → Discover para sa photos, nearby places, at Get Directions.',
      ceb: '➡️ Ablihi ang Home → Discover para sa photos, nearby places, ug Get Directions.',
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
    this.contact = '',
    this.location = '',
    this.openingHours = '',
    this.driveMinutes,
    this.description = '',
  });

  final String name;
  final String category;
  final double? rating;
  final String contact;
  final String location;
  final String openingHours;
  final double? driveMinutes;
  final String description;
}

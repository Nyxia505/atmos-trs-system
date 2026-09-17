import 'package:atmos_trs_system/data/app_faq_content.dart';
import 'package:atmos_trs_system/data/chatbot_destination_knowledge.dart';

enum AtmosLanguage { en, fil, ceb }

class FaqChatMessage {
  const FaqChatMessage({
    required this.text,
    required this.isUser,
    required this.timestamp,
  });

  final String text;
  final bool isUser;
  final DateTime timestamp;
}

/// Tala AI — official tourism assistant for the ATMOS-TRS mobile app.
class FaqChatbotService {
  FaqChatbotService._();

  static final FaqChatbotService instance = FaqChatbotService._();

  factory FaqChatbotService() => instance;

  static const botName = 'Tala AI';

  /// Remembers the user's language for the current chat session.
  AtmosLanguage _sessionLanguage = AtmosLanguage.en;

  /// After a helpful tourism/app answer, a short "ok/thanks" should get a warm reply.
  bool _awaitingAcknowledgement = false;

  AtmosLanguage get sessionLanguage => _sessionLanguage;

  void resetSession() {
    _sessionLanguage = AtmosLanguage.en;
    _awaitingAcknowledgement = false;
  }

  void restoreSessionLanguage(AtmosLanguage lang) {
    _sessionLanguage = lang;
  }

  static const welcomeEn =
      'Hey! 👋 I\'m Tala AI, your tourism assistant for Misamis Occidental.\n\n'
      'Chat with me like a friend — ask how I am, or get help with the app, '
      'destinations, QR check-in, and more. English, Filipino, or Bisaya is fine!';

  static const welcomeFil =
      'Kumusta! 👋 Ako si Tala AI, ang tourism assistant mo para sa Misamis Occidental.\n\n'
      'Puwede tayong mag-usap ng natural — tanungin mo kung kumusta ako, o humingi ng tulong '
      'sa app, destinations, QR check-in, at iba pa. English, Filipino, o Bisaya — okay lang!';

  static const welcomeCeb =
      'Kumusta! 👋 Ako si Tala AI, ang imong tourism assistant sa Misamis Occidental.\n\n'
      'Puwede ta mag-storya nga natural — pangutan-a ko kung kumusta ko, o pangayo og tabang '
      'sa app, destinations, QR check-in, ug uban pa. English, Filipino, o Bisaya — okay ra!';

  static List<String> get suggestedQuestions => [
        'Bless Amare entrance fee',
        'AMORAP opening hours',
        'Jimenez Church address',
        'Paano mag-register?',
        'Unsaon pag-check in?',
        'Nearby hotels sa Bless Amare',
      ];

  String replyTo(String rawInput) {
    final input = rawInput.trim();
    final lang = input.isEmpty
        ? _sessionLanguage
        : _resolveLanguage(input, _scoreLanguage(input));

    if (input.isEmpty) {
      return _localized(
        en: 'Type something and I\'ll reply — even a simple "hi" works! 😊',
        fil: 'Mag-type lang — kahit "hi" okay! 😊',
        ceb: 'I-type lang — bisan "hi" okay! 😊',
        lang: lang,
      );
    }

    final normalized = _normalize(input);

    if (_isHowAreYou(normalized)) {
      _awaitingAcknowledgement = false;
      return _howAreYou(lang);
    }
    if (_isWhoAreYou(normalized)) {
      _awaitingAcknowledgement = false;
      return _whoAreYou(lang);
    }
    if (_isGoodbye(normalized)) {
      _awaitingAcknowledgement = false;
      return _goodbye(lang);
    }
    if (_isGreeting(normalized)) {
      _awaitingAcknowledgement = false;
      return _greeting(lang);
    }
    if (_isThanks(normalized) ||
        (_awaitingAcknowledgement && _isSoftAcknowledgement(normalized))) {
      _awaitingAcknowledgement = false;
      return _thanks(lang);
    }

    if (_isOutOfScope(normalized)) {
      _awaitingAcknowledgement = false;
      return _outOfScope(lang);
    }

    final spotReply =
        ChatbotDestinationKnowledge.reply(normalized, _langCode(lang));
    if (spotReply != null) {
      _awaitingAcknowledgement = true;
      return _limitWords(spotReply);
    }

    final tourismReply = _tourismReply(normalized, lang);
    if (tourismReply != null) {
      _awaitingAcknowledgement = true;
      return _limitWords(tourismReply);
    }

    final best = _bestMatch(normalized);
    if (best != null) {
      _awaitingAcknowledgement = true;
      return _limitWords(_answerFor(best, lang));
    }

    _awaitingAcknowledgement = false;
    return _limitWords(_fallback(lang));
  }

  String welcomeFor(String? seed) {
    final lang = seed == null || seed.trim().isEmpty
        ? _sessionLanguage
        : _resolveLanguage(seed, _scoreLanguage(seed));
    return switch (lang) {
      AtmosLanguage.fil => welcomeFil,
      AtmosLanguage.ceb => welcomeCeb,
      AtmosLanguage.en => welcomeEn,
    };
  }

  /// Detects and remembers the language for [input] without generating a reply.
  AtmosLanguage languageFor(String input) {
    final trimmed = input.trim();
    if (trimmed.isEmpty) return _sessionLanguage;
    return _resolveLanguage(trimmed, _scoreLanguage(trimmed));
  }

  /// Picks reply language: explicit markers in the message win; otherwise
  /// keep the language already used in this chat session.
  AtmosLanguage _resolveLanguage(String input, LanguageScores scores) {
    if (scores.hasStrongSignal) {
      _sessionLanguage = scores.dominant;
      return scores.dominant;
    }

    if (scores.dominant != AtmosLanguage.en) {
      _sessionLanguage = scores.dominant;
      return scores.dominant;
    }

    if (_sessionLanguage != AtmosLanguage.en) {
      return _sessionLanguage;
    }

    return AtmosLanguage.en;
  }

  String _answerFor(AppFaqItem item, AtmosLanguage lang) {
    return switch (lang) {
      AtmosLanguage.fil => item.answerFil ?? item.answer,
      AtmosLanguage.ceb => item.answerCeb ?? item.answer,
      AtmosLanguage.en => item.answer,
    };
  }

  AppFaqItem? _bestMatch(String normalized) {
    AppFaqItem? best;
    var bestScore = 0;

    for (final item in kAppFaqItems) {
      final score = _scoreItem(normalized, item);
      if (score > bestScore) {
        bestScore = score;
        best = item;
      }
    }

    return bestScore >= 3 ? best : null;
  }

  int _scoreItem(String input, AppFaqItem item) {
    var score = 0;
    final question = _normalize(item.question);

    for (final token in _tokens(input)) {
      if (token.length < 3) continue;
      if (question.contains(token)) score += 3;
      if (_normalize(item.answer).contains(token)) score += 1;
      if (item.answerFil != null &&
          _normalize(item.answerFil!).contains(token)) {
        score += 2;
      }
      if (item.answerCeb != null &&
          _normalize(item.answerCeb!).contains(token)) {
        score += 2;
      }
    }

    for (final keyword in item.keywords) {
      if (input.contains(_normalize(keyword))) score += 4;
    }

    if (_containsAny(input, ['paano', 'how', 'unsaon', 'giunsa'])) {
      if (question.contains('how') || item.keywords.contains('check in')) {
        score += 2;
      }
    }
    if (_containsAny(input, ['ano', 'what', 'unsa'])) {
      if (question.contains('what') || question.contains('atmos')) score += 2;
    }
    if (_containsAny(input, ['saan', 'asa', 'where'])) {
      if (item.keywords.contains('explore') ||
          item.keywords.contains('contact')) {
        score += 2;
      }
    }

    return score;
  }

  String _langCode(AtmosLanguage lang) {
    return switch (lang) {
      AtmosLanguage.fil => 'fil',
      AtmosLanguage.ceb => 'ceb',
      AtmosLanguage.en => 'en',
    };
  }

  String? _tourismReply(String input, AtmosLanguage lang) {
    if (_containsAny(input, [
      'festival',
      'fiesta',
      'pista',
      'celebration',
    ])) {
      return _unverifiedTourism(
        lang,
        topicEn: 'festivals and events',
        topicFil: 'festivals at events',
        topicCeb: 'festivals ug events',
        tipEn: 'Check Notifications for official LGU announcements.',
        tipFil: 'Tingnan ang Notifications para sa opisyal na LGU announcements.',
        tipCeb: 'Tan-awa ang Notifications para sa opisyal nga LGU announcements.',
      );
    }

    if (_containsAny(input, [
      'transport',
      'jeepney',
      'bus',
      'sakay',
      'byahe',
      'transportasyon',
    ])) {
      return _unverifiedTourism(
        lang,
        topicEn: 'transportation',
        topicFil: 'transportasyon',
        topicCeb: 'transportasyon',
        tipEn: 'Ask your LGU tourism office or spot staff for local routes.',
        tipFil: 'Magtanong sa LGU tourism office o spot staff para sa local routes.',
        tipCeb: 'Pangutana sa LGU tourism office o spot staff para sa local routes.',
      );
    }

    if (_containsAny(input, ['weather', 'ulan', 'init', 'panahon', 'bagyo'])) {
      return _unverifiedTourism(
        lang,
        topicEn: 'weather',
        topicFil: 'panahon',
        topicCeb: 'panahon',
        tipEn: 'Check a trusted weather service before traveling.',
        tipFil: 'Tingnan ang trusted weather service bago magbyahe.',
        tipCeb: 'Tan-awa ang trusted weather service sa dili pa mobiyahe.',
      );
    }

    if (_containsAny(input, [
      'attraction',
      'destination',
      'place to visit',
      'turista',
      'dapit',
      'puntahan',
      'lugar',
      'spot',
    ])) {
      return _localized(
        lang: lang,
        en:
            'Misamis Occidental has beaches, heritage sites, resorts, and municipalities '
            'to explore. Open Home → Discover in ATMOS-TRS for featured destinations with '
            'opening hours, fees, addresses, and nearby hotels & restaurants. '
            'Ask me something specific like "Bless Amare entrance fee" or "AMORAP address".',
        fil:
            'May beaches, heritage sites, resorts, at municipalities ang Misamis Occidental. '
            'Buksan ang Home → Discover sa ATMOS-TRS para sa featured destinations na may '
            'opening hours, fees, address, at nearby hotels & restaurants. '
            'Tanungin ako tulad ng "Bless Amare entrance fee" o "AMORAP address".',
        ceb:
            'Naay beaches, heritage sites, resorts, ug municipalities ang Misamis Occidental. '
            'Ablihi ang Home → Discover sa ATMOS-TRS para sa featured destinations nga naay '
            'opening hours, fees, address, ug nearby hotels & restaurants. '
            'Pangutana ko sama sa "Bless Amare entrance fee" o "AMORAP address".',
      );
    }

    if (_containsAny(input, [
      'travel tip',
      'safety',
      'reminder',
      'tips',
      'ligtas',
      'safe',
      'mag ingat',
    ])) {
      return _localized(
        lang: lang,
        en:
            'General travel tips for Misamis Occidental:\n'
            '• Register in ATMOS-TRS and keep your QR ready\n'
            '• Check Explore before visiting a spot\n'
            '• Follow local rules and LGU advisories\n'
            '• Keep location enabled for check-in\n'
            '• Contact the tourism office for spot-specific safety info',
        fil:
            'General travel tips sa Misamis Occidental:\n'
            '• Mag-register sa ATMOS-TRS at ihanda ang QR\n'
            '• Tingnan ang Explore bago bumisita\n'
            '• Sundin ang local rules at LGU advisories\n'
            '• I-on ang location para sa check-in\n'
            '• Kontakin ang tourism office para sa spot-specific safety info',
        ceb:
            'General travel tips sa Misamis Occidental:\n'
            '• Magparehistro sa ATMOS-TRS ug andam ang QR\n'
            '• Tan-awa ang Explore sa dili pa mobisita\n'
            '• Sunda ang local rules ug LGU advisories\n'
            '• I-on ang location para sa check-in\n'
            '• Kontaka ang tourism office para sa spot-specific safety info',
      );
    }

    if (_containsAny(input, ['culture', 'kultura', 'tradition', 'tradisyon'])) {
      return _localized(
        lang: lang,
        en:
            'Misamis Occidental has rich local culture and community traditions. For verified '
            'cultural information about a specific municipality or festival, please contact '
            'the local tourism office or check official LGU announcements in Notifications.',
        fil:
            'Mayaman ang kultura at tradisyon ng Misamis Occidental. Para sa verified na '
            'impormasyon tungkol sa partikular na municipality o festival, kontakin ang local '
            'tourism office o tingnan ang opisyal na LGU announcements sa Notifications.',
        ceb:
            'Hataas ang kultura ug tradisyon sa Misamis Occidental. Para sa verified nga '
            'impormasyon bahin sa partikular nga municipality o festival, kontaka ang local '
            'tourism office o tan-awa ang opisyal nga LGU announcements sa Notifications.',
      );
    }

    return null;
  }

  String _unverifiedTourism(
    AtmosLanguage lang, {
    required String topicEn,
    required String topicFil,
    required String topicCeb,
    required String tipEn,
    required String tipFil,
    required String tipCeb,
  }) {
    return _localized(
      lang: lang,
      en:
          'I don\'t have verified $topicEn for that request right now. '
          '$tipEn You may also contact the local tourism office in Misamis Occidental.',
      fil:
          'Wala akong verified na $topicFil para sa tanong na ito ngayon. '
          '$tipFil Puwede mo ring kontakin ang local tourism office sa Misamis Occidental.',
      ceb:
          'Wala koy verified nga $topicCeb para ani nga pangutana karon. '
          '$tipCeb Puwede usab nimo kontakon ang local tourism office sa Misamis Occidental.',
    );
  }

  String _outOfScope(AtmosLanguage lang) {
    return _localized(
      lang: lang,
      en:
          'Sorry — I\'m only here to help with the ATMOS-TRS system and '
          'Misamis Occidental tourism 😊 Ask me about registration, login, '
          'QR check-in, Explore, VR Tour, destinations, fees, or hotels!',
      fil:
          'Pasensya na — nandito lang ako para tumulong sa ATMOS-TRS system at '
          'tourism ng Misamis Occidental 😊 Magtanong ka tungkol sa registration, login, '
          'QR check-in, Explore, VR Tour, destinations, fees, o hotels!',
      ceb:
          'Pasayloa ko — ania lang ko aron motabang sa ATMOS-TRS system ug '
          'tourism sa Misamis Occidental 😊 Pangutana bahin sa registration, login, '
          'QR check-in, Explore, VR Tour, destinations, fees, o hotels!',
    );
  }

  String _greeting(AtmosLanguage lang) {
    return _localized(
      lang: lang,
      en:
          'Hey! 👋 Good to hear from you. I\'m Tala AI — your guide for the app '
          'and Misamis Occidental tourism. What would you like to know?',
      fil:
          'Kumusta! 👋 Masaya akong makipag-usap sa\'yo. Ako si Tala AI — guide mo '
          'sa app at tourism sa Misamis Occidental. Ano ang gusto mong malaman?',
      ceb:
          'Kumusta! 👋 Nalipay ko nga naka-chat nimo. Ako si Tala AI — imong guide '
          'sa app ug tourism sa Misamis Occidental. Unsa ang gusto nimong mahibaloan?',
    );
  }

  String _howAreYou(AtmosLanguage lang) {
    return _localized(
      lang: lang,
      en:
          'I\'m doing great, thanks for asking! 😊 HBU? Hope your day\'s going well. '
          'If you need help with ATMOS-TRS or planning a trip, just ask!',
      fil:
          'Mabuti naman ako, salamat sa pagtanong! 😊 Ikaw, kumusta? Sana maganda ang araw mo. '
          'Kung kailangan mo ng tulong sa ATMOS-TRS o sa trip, tanungin mo lang ako!',
      ceb:
          'Maayo man ko, salamat sa pangutana! 😊 Ikaw, kumusta? Sana nindot ang imong adlaw. '
          'Kung kinahanglan nimo og tabang sa ATMOS-TRS o sa trip, pangutana lang ko!',
    );
  }

  String _whoAreYou(AtmosLanguage lang) {
    return _localized(
      lang: lang,
      en:
          'I\'m Tala AI — the official assistant inside the ATMOS-TRS app '
          '(Asenso Tourismo Misamis Occidental Smart Tourist Registration System). '
          'I help with registration, QR check-in, Explore, and tourism questions. 😊',
      fil:
          'Ako si Tala AI — ang opisyal na assistant sa ATMOS-TRS app '
          '(Asenso Tourismo Misamis Occidental Smart Tourist Registration System). '
          'Tumutulong ako sa registration, QR check-in, Explore, at tourism questions. 😊',
      ceb:
          'Ako si Tala AI — ang opisyal nga assistant sa ATMOS-TRS app '
          '(Asenso Tourismo Misamis Occidental Smart Tourist Registration System). '
          'Motabang ko sa registration, QR check-in, Explore, ug tourism questions. 😊',
    );
  }

  String _goodbye(AtmosLanguage lang) {
    return _localized(
      lang: lang,
      en:
          'Bye for now! 👋 Come back anytime — enjoy exploring Misamis Occidental!',
      fil:
          'Paalam muna! 👋 Balik ka lang anytime — enjoy sa pag-explore ng Misamis Occidental!',
      ceb:
          'Paalam una! 👋 Balik lang anytime — enjoy sa pag-explore sa Misamis Occidental!',
    );
  }

  String _thanks(AtmosLanguage lang) {
    return _localized(
      lang: lang,
      en:
          'You\'re welcome! 😊 Happy to help. Ask me anything else about ATMOS-TRS or your trip anytime.',
      fil:
          'Walang anuman! 😊 Masaya akong tumulong. Magtanong ka lang ulit tungkol sa ATMOS-TRS o sa trip mo.',
      ceb:
          'Walay sapayan! 😊 Nalipay ko motabang. Pangutana lang usab bahin sa ATMOS-TRS o sa imong trip.',
    );
  }

  bool _isThanks(String input) {
    final compacted = input.replaceAll(' ', '');
    const phrases = [
      'thanks',
      'thank you',
      'thankyou',
      'thnkyou',
      'thnk you',
      'thank u',
      'thankyu',
      'thx',
      'thnx',
      'tnx',
      'ty',
      'tysm',
      'tyvm',
      'salamat',
      'salamat kaayo',
      'daghang salamat',
      'salamat po',
      'maraming salamat',
      'much appreciated',
      'appreciate it',
      'appreciated',
    ];
    if (_containsAny(input, phrases)) return true;
    if (_containsAny(compacted, [
      'thankyou',
      'thnkyou',
      'thanku',
      'thanks',
      'salamat',
    ])) {
      return true;
    }
    // "ok thank you", "ok thnkyou", "okay thanks"
    final withoutFiller = input
        .replaceAll(RegExp(r'\b(ok|okay|alright|sure|yes|yeah|yup|sige)\b'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    if (withoutFiller.isNotEmpty && withoutFiller != input) {
      return _isThanks(withoutFiller);
    }
    return false;
  }

  /// Short follow-ups after a helpful answer (conversation context).
  bool _isSoftAcknowledgement(String input) {
    const acks = [
      'ok',
      'okay',
      'okk',
      'oks',
      'alright',
      'all right',
      'got it',
      'gotcha',
      'noted',
      'cool',
      'nice',
      'great',
      'perfect',
      'awesome',
      'awsome',
      'copy',
      'understood',
      'sige',
      'sige ok',
      'okay ra',
      'ok ra',
      'ok lang',
      'okay lang',
      'ayos',
      'ayos lang',
      'good',
      'fine',
      'k',
      'kk',
    ];
    if (acks.contains(input)) return true;
    // Very short messages that are only acknowledgements + filler.
    final tokens = _tokens(input);
    if (tokens.isEmpty || tokens.length > 4) return false;
    return tokens.every(
      (t) => acks.contains(t) || t == 'po' || t == 'lang' || t == 'ra',
    );
  }

  String _fallback(AtmosLanguage lang) {
    return _localized(
      lang: lang,
      en:
          'Sorry — I only assist with the ATMOS-TRS system and tourism-related '
          'questions 😊 Try asking about registration, login, QR check-in, Explore, '
          'VR Tour, destinations, entrance fees, or nearby hotels.',
      fil:
          'Pasensya na — tumutulong lang ako sa ATMOS-TRS system at mga tanong tungkol '
          'sa tourism 😊 Subukang magtanong tungkol sa registration, login, QR check-in, '
          'Explore, VR Tour, destinations, entrance fees, o nearby hotels.',
      ceb:
          'Pasayloa ko — motabang lang ko sa ATMOS-TRS system ug mga pangutana bahin '
          'sa tourism 😊 Sulayi pangutana bahin sa registration, login, QR check-in, '
          'Explore, VR Tour, destinations, entrance fees, o nearby hotels.',
    );
  }

  bool _isHowAreYou(String input) {
    const patterns = [
      'how are you',
      'how r u',
      'how are u',
      'how have you been',
      'how s it going',
      'how is it going',
      'how do you do',
      'kumusta ka',
      'kamusta ka',
      'musta ka',
      'musta na',
      'okay ra ka',
      'okay ka',
      'are you okay',
      'you okay',
    ];
    return _containsAny(input, patterns);
  }

  bool _isWhoAreYou(String input) {
    const patterns = [
      'who are you',
      'what are you',
      'kinsa ka',
      'sino ka',
      'your name',
      'what is your name',
      'ano pangalan mo',
      'unsa imong ngalan',
    ];
    return _containsAny(input, patterns);
  }

  bool _isGoodbye(String input) {
    const patterns = [
      'goodbye',
      'good bye',
      'bye bye',
      'see you',
      'see ya',
      'ingat',
      'paalam',
      'babay',
    ];
    if (input == 'bye' || input.endsWith(' bye') || input.startsWith('bye ')) {
      return true;
    }
    return _containsAny(input, patterns);
  }

  bool _isOutOfScope(String input) {
    const patterns = [
      // Romance / personal
      'boyfriend',
      'girlfriend',
      'love me',
      'do you love',
      'i love you',
      'iloveyou',
      'love you',
      'marry me',
      'date me',
      'crush',
      'kiss me',
      // School / random trivia
      'classroom',
      'class president',
      'president of your class',
      'who is the president',
      'who s the president',
      'homework',
      'solve this equation',
      'math problem',
      // Politics / finance / gambling
      'politics',
      'election',
      'senator',
      'president',
      'bitcoin',
      'crypto',
      'stock market',
      'gambling',
      'casino',
      // Unrelated lifestyle
      'recipe',
      'cook for me',
      'tell me a joke',
      'sing a song',
      'write a poem',
      'horoscope',
      'astrology',
    ];
    return _containsAny(input, patterns);
  }

  bool _isGreeting(String input) {
    const greetings = [
      'hi',
      'hello',
      'hey',
      'good morning',
      'good afternoon',
      'good evening',
      'kumusta',
      'musta',
      'magandang umaga',
      'magandang hapon',
      'maayong buntag',
      'maayong hapon',
      'whats up',
      'what s up',
      'sup',
    ];
    return greetings.any(
      (g) => input == g || input.startsWith('$g ') || input.endsWith(' $g'),
    );
  }

  LanguageScores _scoreLanguage(String input) {
    final n = _normalize(input);
    final tokens = _tokens(n);
    var cebScore = 0;
    var filScore = 0;
    var enScore = 0;

    // Strong Cebuano markers (word-level).
    const cebStrong = {
      'unsa': 4,
      'unsaon': 5,
      'giunsa': 5,
      'asa': 4,
      'kinsa': 4,
      'nimo': 4,
      'nako': 4,
      'niya': 3,
      'nila': 3,
      'tagpila': 5,
      'pila': 3,
      'maayong': 5,
      'palihug': 4,
      'salamat kaayo': 5,
      'dili': 4,
      'bitaw': 3,
      'kaayo': 4,
      'kanus': 4,
      'kanus a': 4,
      'gikan': 3,
      'padulong': 3,
      'lang': 2,
      'ra': 2,
      'ug': 2,
      'og': 2,
    };

    // Strong Tagalog/Filipino markers (word-level).
    const filStrong = {
      'paano': 5,
      'bakit': 5,
      'kailan': 5,
      'saan': 4,
      'sino': 4,
      'ano': 3,
      'magandang': 5,
      'po': 4,
      'opo': 5,
      'hindi': 4,
      'oo': 2,
      'ng': 3,
      'mga': 3,
      'natin': 4,
      'atin': 3,
      'nyo': 3,
      'ninyo': 4,
      'tayo': 3,
      'kami': 2,
      'kayo': 3,
      'gusto': 2,
      'pwede': 2,
      'mag': 3,
      'ang': 3,
      'ko': 2,
      'mo': 2,
    };

    // English markers.
    const enStrong = {
      'how': 3,
      'what': 3,
      'where': 3,
      'when': 3,
      'why': 3,
      'please': 3,
      'help': 2,
      'the': 2,
      'can': 2,
      'you': 2,
      'your': 2,
      'register': 2,
      'login': 2,
      'check': 2,
      'explore': 2,
    };

    for (final entry in cebStrong.entries) {
      if (_containsPhrase(n, entry.key)) cebScore += entry.value;
    }
    for (final entry in filStrong.entries) {
      if (_containsPhrase(n, entry.key)) filScore += entry.value;
    }
    for (final entry in enStrong.entries) {
      if (_containsPhrase(n, entry.key)) enScore += entry.value;
    }

    // Phrase patterns that disambiguate mixed "kumusta" greetings.
    if (_containsPhrase(n, 'kumusta ka po') || _containsPhrase(n, 'kamusta po')) {
      filScore += 5;
    }
    if (_containsPhrase(n, 'okay ra ka') || _containsPhrase(n, 'musta na')) {
      cebScore += 5;
    }
    if (_containsPhrase(n, 'ano ang')) filScore += 4;
    if (_containsPhrase(n, 'unsa ang')) cebScore += 4;
    if (_containsPhrase(n, 'paano mag') || _containsPhrase(n, 'paano ako')) {
      filScore += 5;
    }
    if (_containsPhrase(n, 'unsaon pag') || _containsPhrase(n, 'unsaon ko')) {
      cebScore += 5;
    }

    // Shared greetings lean slightly by surrounding words.
    if (_containsPhrase(n, 'kumusta') || _containsPhrase(n, 'musta')) {
      if (filScore == cebScore) {
        if (_containsPhrase(n, 'po')) {
          filScore += 2;
        } else if (_containsPhrase(n, 'ra')) {
          cebScore += 2;
        }
      }
    }

    // Token overlap for FAQ-style questions.
    for (final token in tokens) {
      if (token.length < 3) continue;
      if (['unsaon', 'giunsa', 'kinsa', 'tagpila', 'dili'].contains(token)) {
        cebScore += 2;
      }
      if (['paano', 'bakit', 'kailan', 'magregister', 'magparehistro'].contains(token)) {
        filScore += token.startsWith('mag') && token.contains('parehistro') ? 0 : 2;
      }
      if (token == 'magparehistro') cebScore += 3;
      if (token == 'magregister') filScore += 3;
    }

    AtmosLanguage dominant;
    if (cebScore > filScore && cebScore > enScore && cebScore > 0) {
      dominant = AtmosLanguage.ceb;
    } else if (filScore > enScore && filScore > 0) {
      dominant = AtmosLanguage.fil;
    } else if (enScore > 0 &&
        enScore >= filScore &&
        enScore >= cebScore) {
      dominant = AtmosLanguage.en;
    } else if (cebScore > 0 && cebScore >= filScore) {
      dominant = AtmosLanguage.ceb;
    } else if (filScore > 0) {
      dominant = AtmosLanguage.fil;
    } else {
      dominant = AtmosLanguage.en;
    }

    final strongThreshold = 4;
    final hasStrongSignal = cebScore >= strongThreshold ||
        filScore >= strongThreshold ||
        enScore >= strongThreshold;

    return LanguageScores(
      ceb: cebScore,
      fil: filScore,
      en: enScore,
      dominant: dominant,
      hasStrongSignal: hasStrongSignal,
    );
  }

  bool _containsPhrase(String normalized, String phrase) {
    if (phrase.contains(' ')) return normalized.contains(phrase);
    return normalized == phrase ||
        normalized.startsWith('$phrase ') ||
        normalized.endsWith(' $phrase') ||
        normalized.contains(' $phrase ');
  }

  String _localized({
    required AtmosLanguage lang,
    required String en,
    required String fil,
    required String ceb,
  }) {
    return switch (lang) {
      AtmosLanguage.fil => fil,
      AtmosLanguage.ceb => ceb,
      AtmosLanguage.en => en,
    };
  }

  String _limitWords(String text, {int maxWords = 150}) {
    final words = text.split(RegExp(r'\s+'));
    if (words.length <= maxWords) return text;
    return '${words.take(maxWords).join(' ')}…';
  }

  bool _containsAny(String input, List<String> terms) {
    return terms.any(input.contains);
  }

  String _normalize(String value) {
    return value
        .toLowerCase()
        .replaceAll(RegExp(r'[^\w\s]'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  List<String> _tokens(String value) {
    return value.split(' ').where((t) => t.isNotEmpty).toList();
  }
}

class LanguageScores {
  const LanguageScores({
    required this.ceb,
    required this.fil,
    required this.en,
    required this.dominant,
    required this.hasStrongSignal,
  });

  final int ceb;
  final int fil;
  final int en;
  final AtmosLanguage dominant;
  final bool hasStrongSignal;
}

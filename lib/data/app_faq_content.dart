import 'package:flutter/material.dart';

class AppFaqItem {
  const AppFaqItem({
    required this.question,
    required this.answer,
    this.answerFil,
    this.answerCeb,
    required this.icon,
    this.keywords = const [],
  });

  final String question;
  final String answer;
  final String? answerFil;
  final String? answerCeb;
  final IconData icon;
  final List<String> keywords;
}

/// Knowledge base for ATMOS-TRS AI — app help and tourism guidance.
const List<AppFaqItem> kAppFaqItems = [
  AppFaqItem(
    icon: Icons.travel_explore_rounded,
    question: 'What is ATMOS-TRS?',
    keywords: ['atmos', 'atmos-trs', 'atmos trs', 'meaning', 'purpose', 'app', 'system'],
    answer:
        'ATMOS-TRS (Asenso Tourismo Misamis Occidental Smart Tourist Registration System) is the '
        'official tourism mobile app for Misamis Occidental. It helps you register as a '
        'tourist, explore destinations, check in with QR codes, and track your travel '
        'experience.',
    answerFil:
        'Ang ATMOS-TRS (Asenso Tourismo Misamis Occidental Smart Tourist Registration System) ay '
        'ang opisyal na tourism app para sa Misamis Occidental. Makakatulong ito sa '
        'pagre-register, pag-explore ng destinations, QR check-in, at pag-track ng '
        'iyong travel experience.',
    answerCeb:
        'Ang ATMOS-TRS (Asenso Tourismo Misamis Occidental Smart Tourist Registration System) '
        'mao ang opisyal nga tourism app sa Misamis Occidental. Makatabang kini sa '
        'pagparehistro, pag-explore sa destinations, QR check-in, ug pag-track sa imong '
        'travel experience.',
  ),
  AppFaqItem(
    icon: Icons.person_add_alt_1_rounded,
    question: 'How do I register?',
    keywords: ['register', 'signup', 'sign up', 'create account', 'mag register'],
    answer:
        'To register:\n'
        '1. Open the app and tap Sign Up\n'
        '2. Enter your email or phone number\n'
        '3. Complete your tourist profile\n'
        '4. Verify your account if prompted\n'
        'Your digital tourist ID and QR code are created after registration.',
    answerFil:
        'Para mag-register:\n'
        '1. Buksan ang app at pindutin ang Sign Up\n'
        '2. Ilagay ang email o phone number\n'
        '3. Kumpletuhin ang tourist profile\n'
        '4. I-verify ang account kung hihingin\n'
        'Gagawa ang digital tourist ID at QR code pagkatapos mag-register.',
    answerCeb:
        'Para magparehistro:\n'
        '1. Ablihi ang app ug i-tap ang Sign Up\n'
        '2. Ibutang ang email o phone number\n'
        '3. Kompletoha ang tourist profile\n'
        '4. I-verify ang account kung gikinahanglan\n'
        'Maghimo ang digital tourist ID ug QR code human sa pagparehistro.',
  ),
  AppFaqItem(
    icon: Icons.login_rounded,
    question: 'How do I log in?',
    keywords: ['login', 'log in', 'sign in', 'mag login'],
    answer:
        'To log in:\n'
        '1. Open ATMOS-TRS and tap Log In\n'
        '2. Enter your registered email or phone\n'
        '3. Enter your password\n'
        '4. Tap Log In to access Home, Explore, and your profile',
    answerFil:
        'Para mag-log in:\n'
        '1. Buksan ang ATMOS-TRS at pindutin ang Log In\n'
        '2. Ilagay ang registered email o phone\n'
        '3. Ilagay ang password\n'
        '4. Pindutin ang Log In para ma-access ang Home, Explore, at profile',
    answerCeb:
        'Para mag-log in:\n'
        '1. Ablihi ang ATMOS-TRS ug i-tap ang Log In\n'
        '2. Ibutang ang registered email o phone\n'
        '3. Ibutang ang password\n'
        '4. I-tap ang Log In aron ma-access ang Home, Explore, ug profile',
  ),
  AppFaqItem(
    icon: Icons.qr_code_2_rounded,
    question: 'What is my Tourist QR code?',
    keywords: ['qr', 'qr code', 'tourist id', 'digital id'],
    answer:
        'Your Tourist QR code is your unique digital ID in ATMOS-TRS. Open Account (Profile) '
        'to view or show it at check-in. Staff or spot scanners use it to record your visit.',
    answerFil:
        'Ang Tourist QR code ay iyong unique digital ID sa ATMOS-TRS. Buksan ang Account '
        '(Profile) para makita o ipakita sa check-in. Ginagamit ito ng staff o scanner '
        'para i-record ang visit mo.',
    answerCeb:
        'Ang Tourist QR code mao ang imong unique digital ID sa ATMOS-TRS. Ablihi ang Account '
        '(Profile) aron makita o ipakita sa check-in. Gigamit kini sa staff o scanner aron '
        'i-record ang imong visit.',
  ),
  AppFaqItem(
    icon: Icons.qr_code_scanner_rounded,
    question: 'How do I check in at a tourist spot?',
    keywords: ['check in', 'checkin', 'check-in', 'scan', 'mag check in'],
    answer:
        'To check in:\n'
        '1. Go to the tourist spot or LGU checkpoint\n'
        '2. Either show your personal QR (Profile) OR scan the spot QR via the Scan tab\n'
        '3. Allow location if asked\n'
        '4. Follow on-screen steps — your visit is saved automatically',
    answerFil:
        'Para mag-check in:\n'
        '1. Pumunta sa tourist spot o LGU checkpoint\n'
        '2. Ipakita ang personal QR (Profile) O i-scan ang spot QR sa Scan tab\n'
        '3. Payagan ang location kung hihingin\n'
        '4. Sundin ang steps — awtomatikong mase-save ang visit',
    answerCeb:
        'Para mag-check in:\n'
        '1. Adto sa tourist spot o LGU checkpoint\n'
        '2. Ipakita ang personal QR (Profile) O i-scan ang spot QR sa Scan tab\n'
        '3. Tugoti ang location kung gikinahanglan\n'
        '4. Sunda ang steps — automatic nga ma-save ang visit',
  ),
  AppFaqItem(
    icon: Icons.logout_rounded,
    question: 'How do I check out?',
    keywords: ['check out', 'checkout', 'check-out', 'umalis', 'leave'],
    answer:
        'Check-out depends on the location. Some spots record check-out automatically; '
        'others may ask you to scan again when leaving. If unsure, ask staff at the '
        'entrance or contact the local tourism office.',
    answerFil:
        'Depende sa lugar ang check-out. May mga spot na automatic ang check-out; iba naman '
        'ay kailangan mag-scan ulit pag aalis. Kung hindi sigurado, magtanong sa staff sa '
        'entrance o sa local tourism office.',
    answerCeb:
        'Depende sa lugar ang check-out. Naay mga spot nga automatic; uban kinahanglan '
        'mag-scan pag migawas. Kung dili sigurado, pangutana sa staff sa entrance o sa '
        'local tourism office.',
  ),
  AppFaqItem(
    icon: Icons.map_rounded,
    question: 'How does Explore work?',
    keywords: ['explore', 'map', 'destinations', 'places', 'spots'],
    answer:
        'Explore shows tourist spots across Misamis Occidental on a map and in lists. '
        'Tap a destination for details, photos, and location. Use it to discover beaches, '
        'heritage sites, resorts, and municipalities.',
    answerFil:
        'Sa Explore, makikita ang tourist spots sa Misamis Occidental sa mapa at listahan. '
        'I-tap ang destination para sa details, photos, at location. Gamitin ito para '
        'matuklasan ang beaches, heritage sites, resorts, at municipalities.',
    answerCeb:
        'Sa Explore, makita ang tourist spots sa Misamis Occidental sa mapa ug lista. '
        'I-tap ang destination para sa details, photos, ug location. Gamita kini aron '
        'madiskubre ang beaches, heritage sites, resorts, ug municipalities.',
  ),
  AppFaqItem(
    icon: Icons.home_rounded,
    question: 'What can I do on the Home screen?',
    keywords: ['home', 'dashboard', 'main screen'],
    answer:
        'Home is your dashboard. Browse featured destinations, search places, view stats '
        '(Visited, Badges, Days), open saved spots, see recent visits, and chat with '
        'ATMOS-TRS AI for help.',
    answerFil:
        'Ang Home ay dashboard mo. Puwede mong i-browse ang featured destinations, mag-search, '
        'tingnan ang stats (Visited, Badges, Days), buksan ang saved spots, at makipag-chat '
        'sa ATMOS-TRS AI para sa tulong.',
    answerCeb:
        'Ang Home mao ang imong dashboard. Puwede nimong i-browse ang featured destinations, '
        'mag-search, tan-awon ang stats (Visited, Badges, Days), ablihan ang saved spots, '
        'ug makig-chat sa ATMOS-TRS AI para sa tabang.',
  ),
  AppFaqItem(
    icon: Icons.view_in_ar_rounded,
    question: 'What is a VR Tour?',
    keywords: ['vr', 'virtual', '360'],
    answer:
        'VR Tour lets you preview some destinations in 360° before visiting. Look for the '
        'VR option on supported spot detail pages in Explore.',
    answerFil:
        'Sa VR Tour, puwede mong i-preview ang ilang destinations sa 360° bago bumisita. '
        'Hanapin ang VR option sa supported spot detail pages sa Explore.',
    answerCeb:
        'Sa VR Tour, puwede nimong i-preview ang ubang destinations sa 360° sa dili pa '
        'mobisita. Pangitaa ang VR option sa supported spot detail pages sa Explore.',
  ),
  AppFaqItem(
    icon: Icons.route_rounded,
    question: 'Is there a Trip Planner?',
    keywords: ['trip', 'planner', 'itinerary', 'plan'],
    answer:
        'Yes. Trip Planner helps you build itineraries and get destination recommendations '
        'for Misamis Occidental. Access it from the landing page or tourism links when '
        'available in your app version.',
    answerFil:
        'Oo. Ang Trip Planner ay tumutulong mag-build ng itinerary at makakuha ng destination '
        'recommendations sa Misamis Occidental. I-access ito sa landing page o tourism links '
        'kung available sa app mo.',
    answerCeb:
        'Oo. Ang Trip Planner makatabang sa paghimo og itinerary ug makakuha og destination '
        'recommendations sa Misamis Occidental. I-access kini sa landing page o tourism '
        'links kung available sa imong app.',
  ),
  AppFaqItem(
    icon: Icons.bookmark_rounded,
    question: 'Can I save favorite places?',
    keywords: ['save', 'saved', 'favorite', 'bookmark'],
    answer:
        'Yes. Tap the bookmark icon on a destination to save it. Open Saved from Home to '
        'quickly return to places you want to visit later.',
    answerFil:
        'Oo. I-tap ang bookmark icon sa destination para i-save. Buksan ang Saved sa Home '
        'para mabilis na balikan ang mga gustong puntahan.',
    answerCeb:
        'Oo. I-tap ang bookmark icon sa destination aron i-save. Ablihi ang Saved sa Home '
        'aron dali nimo mabalikan ang gustong adtoan.',
  ),
  AppFaqItem(
    icon: Icons.notifications_rounded,
    question: 'What are Notifications for?',
    keywords: ['notification', 'alert', 'announcement', 'promo', 'event'],
    answer:
        'Notifications show tourism updates — announcements, events, promos, and check-in '
        'confirmations. Check this tab for advisories and messages from LGU tourism offices.',
    answerFil:
        'Ang Notifications ay nagpapakita ng tourism updates — announcements, events, promos, '
        'at check-in confirmations. Tingnan ito para sa advisories at mensahe mula sa LGU '
        'tourism offices.',
    answerCeb:
        'Ang Notifications nagpakita og tourism updates — announcements, events, promos, ug '
        'check-in confirmations. Tan-awa kini para sa advisories ug mensahe gikan sa LGU '
        'tourism offices.',
  ),
  AppFaqItem(
    icon: Icons.person_rounded,
    question: 'What is in my Tourist Profile?',
    keywords: ['profile', 'account', 'tourist profile', 'personal'],
    answer:
        'Your profile includes your name, tourist ID, QR code, visit history, badges, and '
        'account settings. Update your details and manage preferences in the Account tab.',
    answerFil:
        'Kasama sa profile ang pangalan, tourist ID, QR code, visit history, badges, at account '
        'settings. I-update ang details at i-manage ang preferences sa Account tab.',
    answerCeb:
        'Apil sa profile ang ngalan, tourist ID, QR code, visit history, badges, ug account '
        'settings. I-update ang details ug i-manage ang preferences sa Account tab.',
  ),
  AppFaqItem(
    icon: Icons.emoji_events_rounded,
    question: 'What are Visited, Badges, and Days?',
    keywords: ['badge', 'visited', 'stats', 'days', 'achievement'],
    answer:
        'Visited = places you checked in to. Badges = achievements as you explore Misamis '
        'Occidental. Days = how long you have been registered as a tourist.',
    answerFil:
        'Visited = bilang ng napuntahan. Badges = achievements habang nag-e-explore. Days = '
        'gaano ka na katagal na registered na tourist.',
    answerCeb:
        'Visited = mga lugar nga na-check in. Badges = achievements samtang nag-explore. Days '
        '= unsa ka kadugay naka-register isip tourist.',
  ),
  AppFaqItem(
    icon: Icons.settings_rounded,
    question: 'How do I change Account Settings?',
    keywords: ['settings', 'theme', 'password', 'privacy', 'account settings'],
    answer:
        'Open Account (Profile) and look for Settings. You can update profile details, '
        'change theme color, and manage account options linked to your login.',
    answerFil:
        'Buksan ang Account (Profile) at hanapin ang Settings. Puwede mong i-update ang profile, '
        'palitan ang theme color, at i-manage ang account options.',
    answerCeb:
        'Ablihi ang Account (Profile) ug pangitaa ang Settings. Puwede nimong i-update ang '
        'profile, usbon ang theme color, ug i-manage ang account options.',
  ),
  AppFaqItem(
    icon: Icons.location_on_rounded,
    question: 'Why does the app need my location?',
    keywords: ['location', 'gps', 'permission'],
    answer:
        'Location confirms you are at the correct tourist spot or LGU checkpoint during '
        'check-in. Turn on location for ATMOS-TRS in device settings if a scan fails.',
    answerFil:
        'Kailangan ang location para kumpirmahin na nasa tamang tourist spot o LGU checkpoint '
        'ka sa check-in. I-on ang location para sa ATMOS-TRS sa device settings kung may scan error.',
    answerCeb:
        'Gikinahanglan ang location aron makumpirma nga naa ka sa husto nga tourist spot o LGU '
        'checkpoint sa check-in. I-on ang location para sa ATMOS-TRS sa device settings kung naay '
        'scan error.',
  ),
  AppFaqItem(
    icon: Icons.support_agent_rounded,
    question: 'Who can I contact for help?',
    keywords: ['help', 'contact', 'support', 'office', 'tourism office', 'tulong'],
    answer:
        'Visit your municipal or provincial tourism office in Misamis Occidental, or ask '
        'staff at a tourist spot entrance. They can help with registration, QR check-in, '
        'and travel information.',
    answerFil:
        'Bisitahin ang municipal o provincial tourism office sa Misamis Occidental, o magtanong '
        'sa staff sa entrance ng tourist spot. Makakatulong sila sa registration, QR check-in, '
        'at travel information.',
    answerCeb:
        'Bisitaha ang municipal o provincial tourism office sa Misamis Occidental, o pangutana '
        'sa staff sa entrance sa tourist spot. Makatabang sila sa registration, QR check-in, ug '
        'travel information.',
  ),
];

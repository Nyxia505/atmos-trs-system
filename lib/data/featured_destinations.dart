import 'package:atmos_trs_system/config/vr_tour_config.dart';

/// Featured destinations on Home Discover — single source for UI and chatbot.
const List<Map<String, dynamic>> kFeaturedDestinations = [
  {
    'name': 'Bless Amare Sunrise Beach',
    'description': 'Baliangao Beach — pristine sunrise views in Barangay Tugas',
    'detail':
        'Bless Amare Sunrise Beach is Baliangao\'s premier coastal destination in Barangay Tugas. '
        'Enjoy day-use swimming, cottage rentals, and table seating by the shore. '
        'Overnight accommodations remain accessible 24 hours for guests who book a stay.',
    'image': 'assets/images/Baliangao - Cabgan Island.jpg',
    'rating': 4.8,
    'category': 'Beach',
    'spotId': 'bless_amare_sunrise_beach',
    'location': 'Barangay Tugas, Baliangao, Misamis Occidental',
    'openingHours': 'Day use: 6:00 AM – 5:00 PM\nOvernight accommodations: 24 hours',
    'entranceFee': 'Adults ₱80 · Seniors ₱60 · Kids ₱30 (day use)',
    'cottageRates':
        'Small cottage (4–6 pax) ₱450 · Medium cottage (10 pax) ₱600 · Large cottage (12 pax) ₱800 · Tables available',
    'latitude': 8.6167,
    'longitude': 123.5667,
    'nearbyRestaurants': [
      {
        'name': 'Camp Sawi Restaurant - Calamba',
        'image': 'assets/images/Camp Sawi.jpg',
        'rating': 4.5,
        'priceRange': '₱200–400',
        'distanceKm': 5.5,
        'location': 'Baliangao–Calamba Road',
        'description':
            'Comfort food, rice meals like daing na bangus, and burgers (~11 min drive).',
      },
      {
        'name': "Nami's",
        'image': "assets/images/Nami's.jpg",
        'rating': 4.4,
        'priceRange': '₱₱',
        'distanceKm': 5.5,
        'location': 'Calamba Road, Baliangao',
        'description':
            'Casual local dining with small plates and seafood (~11 min from the coast).',
      },
    ],
    'nearbyHotels': [
      {
        'name': 'Antelmi Travelers Inn',
        'image': "assets/Nearby Hotel's in Sunrise Beach/ANTELMI TRAVELERS INN.webp",
        'category': 'Lodge',
        'rating': 4.9,
        'priceRange': 'from ₱919',
        'location': 'Dipolog-Oroquieta National Road, Eastern Looc, Plaridel',
        'driveMinutes': 43,
        'description':
            'Lodge along the national highway. Rates start around ₱1,100 per night (~43 min drive).',
      },
      {
        'name': 'Hotel Bijoux',
        'image': "assets/Nearby Hotel's in Sunrise Beach/Hotel Bijoux.webp",
        'category': 'Hotel',
        'rating': 4.6,
        'priceRange': 'from ₱2,020',
        'location': 'Interco Extension, Eastern Looc, Plaridel',
        'driveMinutes': 45,
        'description':
            'Aesthetic, modern, air-conditioned rooms. Rates around ₱2,300 per night (~45 min drive).',
      },
      {
        'name': 'D&M Travellers Inn',
        'image': "assets/Nearby Hotel's in Sunrise Beach/D&M Travellers Inn.jpg",
        'category': 'Hotel',
        'rating': 4.4,
        'priceRange': 'from ₱2,173',
        'location': 'Looc Proper, Plaridel',
        'driveMinutes': 45,
        'description':
            'Clean, comfortable rooms with free Wi-Fi. Starting around ₱2,500 per night (~45 min drive).',
      },
      {
        'name': 'Daydream Ranch Resort',
        'image': "assets/Nearby Hotel's in Sunrise Beach/Daydream Ranch Resort.jpg",
        'category': 'Resort',
        'rating': 4.2,
        'priceRange': 'Resort rates',
        'location': 'Barangay Calacaan, Plaridel',
        'driveMinutes': 46,
        'description':
            'Resort hotel with swimming pool, restaurant, and free breakfast (~46 min drive).',
      },
    ],
    'nearbyHotelsNote':
        'Nearby accommodations in Plaridel (~43–46 min drive from Bless Amare)',
    'nearbyAttractions': [
      {
        'name': 'Bless Amare Sunrise Beach',
        'image': 'assets/images/Baliangao - Cabgan Island.jpg',
      },
      {
        'name': 'Baliangao Protected Landscape and Seascape',
        'image': 'assets/images/baliangao_protected_landscape_seascape.png',
      },
      {
        'name': "Jabien's Integrated Farm",
        'image': 'assets/images/jabiens_integrated_farm.png',
      },
      {
        'name': 'Casa Antonio Resort',
        'image': 'assets/images/casa_antonio_resort.png',
      },
      {
        'name': 'Bito-on Beach Resort',
        'image': 'assets/images/bito_on_beach_resort.png',
      },
    ],
    'nearbyCafes': [
      {
        'name': 'Cup of Grace',
        'image': 'assets/images/cup_of_grace.png',
      },
      {
        'name': 'Lei Brew',
        'image': 'assets/images/lei_brew.png',
      },
      {
        'name': "Trina's KAPEHAN",
        'image': 'assets/images/trinas_kapehan.png',
      },
    ],
  },
  {
    'name': 'Piduan Falls',
    'description': 'Curtain Falls — majestic multi-layered waterfall at Mount Malindang',
    'detail':
        'Piduan Falls (also known as Curtain Falls) is a majestic, multi-layered curtain-like waterfall '
        'with cold, crystal-clear water in Sitio Piduan, Barangay Napangan, Don Victoriano Chiongbian. '
        'Nestled at the foot of Mount Malindang in the regional highlands, it is reached via an '
        'adventurous trek through Malindang forests. Private vehicles park at the designated area; '
        'LGU-managed shuttle takes visitors to the waterfall site. Expect winding mountain roads — '
        'daytime visits are strongly recommended.',
    'image': 'assets/images/Piduan Falls Donvic.jpg',
    'rating': 4.7,
    'category': 'Falls',
    'spotId': 'piduan_falls',
    'location':
        'Sitio Piduan, Barangay Napangan, Don Victoriano Chiongbian, Misamis Occidental',
    'openingHours': 'Daily — daytime visits recommended (mountain terrain & weather)',
    'entranceFee': '₱100 per person (includes shuttle transfer & swimming pool access)',
    'cottageRates': 'Umbrellas / basic cottages ~₱300',
    'latitude': 8.2542,
    'longitude': 123.5642,
    'nearbyRestaurants': [
      'Malindang Trail Kitchen',
      'Strawberry Farm Eatery',
      'Napangan Mountain Eatery',
    ],
    'nearbyHotels': [
      'Don Victoriano View Inn',
      'Cool Breeze Lodging',
      'Malindang Highland Stay',
    ],
    'nearbyAttractions': [
      {
        'name': 'Piduan Falls',
        'image': 'assets/images/Piduan Falls Donvic.jpg',
      },
      {
        'name': 'Mount Malindang Range Natural Park',
        'image': 'assets/images/Piduan Falls Donvic.jpg',
      },
      {
        'name': 'Lake Duminagat',
        'image': 'assets/images/lake_duminagat.webp',
      },
    ],
  },
  {
    'name': 'Asenso Ozamiz Wellness Park',
    'description':
        'Wellness park on Port Road — across Cotta Shrine, near Ozamiz Port Complex',
    'detail':
        'Asenso Ozamiz Wellness Park sits on Port Road in Barangay Baybay Triunfo, Ozamiz City — '
        'outside the Ozamiz Port Complex with bayside views toward Panguil Bay. '
        'Enjoy open park grounds, a kids\' playground, adult mini-gym, food park, weekend markets, '
        'and night cafés in one family-friendly destination.',
    'image': 'assets/images/ozamis city.webp',
    'rating': 4.9,
    'category': 'Park',
    'spotId': 'ozamiz_asenso_wellness_park',
    'location':
        'Port Road, Barangay Baybay Triunfo, Ozamiz City, Misamis Occidental',
    'openingHours':
        'Park grounds: open daily\nFood park, weekend markets & night cafés: Fri–Sun, 5:00 PM – 11:30 PM',
    'entranceFee':
        'Free general admission · Kids playground ₱20 · Adult mini-gym ₱50 (each valid 6 hours)',
    'latitude': 8.1486,
    'longitude': 123.8414,
    'nearbyRestaurants': [
      'Wellness Park Food Court',
      'Baybay Triunfo Night Cafés',
      'Port Road Weekend Market Eateries',
    ],
    'nearbyHotels': [
      'Ozamiz City Suites',
      'Bayview Hotel & Stay',
    ],
    'nearbyAttractions': [
      {
        'name': 'Cotta Fort & Shrine',
        'image': "assets/images/Cotta Fort & Shrine.jpg",
      },
      {
        'name': 'Immaculate Conception Cathedral',
        'image': 'assets/images/Immaculate Conception Cathedral.webp',
      },
      {
        'name': 'Cotta Beach',
        'image': 'assets/images/Cotta Beach.jpg',
      },
    ],
  },
  {
    'name': 'Cotta Fort & Shrine',
    'description':
        'Historic stone fort and shrine overlooking Panguil Bay — Barangay Baybay Triunfo',
    'detail':
        'Cotta Fort (Fuerte de la Concepción y del Triunfo) is an 18th-century Spanish stone fort '
        'built in 1755 in Barangay Baybay Triunfo, Ozamiz City. It guards the entrance to Panguil Bay '
        'and sits beside the Cotta Shrine dedicated to Our Lady of Triumph of the Cross — a beloved '
        'pilgrimage site and National Cultural Treasure. Walk the ramparts, visit the shrine, and '
        'enjoy panoramic bay views steps from Port Road.',
    'image': "assets/images/Cotta Fort & Shrine.jpg",
    'rating': 4.8,
    'category': 'Historical',
    'spotId': 'ozamiz_cotta_fort_shrine',
    'location':
        'Cotta Fort area, Barangay Baybay Triunfo, Ozamiz City, Misamis Occidental',
    'openingHours':
        'Typically open daily, 8:00 AM – 5:00 PM (active shrine — dress modestly)',
    'entranceFee': 'Free',
    'latitude': 8.1472,
    'longitude': 123.8408,
    'nearbyRestaurants': [
      'Wellness Park Food Court',
      'Baybay Triunfo Night Cafés',
      'Port Road Weekend Market Eateries',
    ],
    'nearbyHotels': [
      'Ozamiz City Suites',
      'Bayview Hotel & Stay',
    ],
    'nearbyAttractions': [
      {
        'name': 'Asenso Ozamiz Wellness Park',
        'image': 'assets/images/ozamis city.webp',
      },
      {
        'name': 'Immaculate Conception Cathedral',
        'image': 'assets/images/Immaculate Conception Cathedral.webp',
      },
      {
        'name': 'Cotta Beach',
        'image': 'assets/images/Cotta Beach.jpg',
      },
    ],
  },
  {
    'name': 'Asenso Global Gardens',
    'description':
        '191-hectare highland eco-tourism park with themed international gardens and Panguil Bay views',
    'detail':
        'Asenso Global Gardens is a 191-hectare highland eco-tourism park in Barangay Hoyohoy, Tangub City. '
        'Explore themed international gardens, scenic walkways, and panoramic views of Panguil Bay and '
        'the surrounding highlands. A favorite destination for nature lovers, families, and visitors '
        'exploring Tangub — the Christmas Symbols Capital of the Philippines.',
    'image': 'assets/images/Asenso Global Garden 1.png',
    'rating': 4.8,
    'category': 'Park',
    'spotId': 'tangub_asenso_global_gardens',
    'location': 'Barangay Hoyohoy, Tangub City, Misamis Occidental',
    'openingHours': 'Daily, 6:00 AM – 6:00 PM',
    'entranceFee': 'Weekdays (Mon–Fri) ₱50 · Weekends (Sat–Sun) ₱100 per person',
    'latitude': 8.0656,
    'longitude': 123.7564,
    'nearbyRestaurants': [
      'Global Gardens Café',
      'Tangub Family Kainan',
      'Hoyohoy Highland Eatery',
    ],
    'nearbyHotels': [
      'Tangub Central Inn',
      'Asenso Stay Options',
    ],
    'nearbyAttractions': [
      {
        'name': 'Hoyohoy Highland Stone Chapel',
        'image': 'assets/images/Asenso Global Garden 1.png',
      },
    ],
  },
  {
    'name': 'Jimenez Church',
    'description':
        'National Cultural Treasure — Church of St. John the Baptist in Barangay Poblacion',
    'detail':
        'The Church of St. John the Baptist (commonly known as Jimenez Church) is a late-19th century '
        'Baroque Roman Catholic parish church in Barangay Poblacion, Jimenez, Misamis Occidental. '
        'Under the patronage of Saint John the Baptist and the Archdiocese of Ozamiz, it was declared '
        'a National Cultural Treasure of the Philippines in 2001. Look up at the stunning, well-preserved '
        'painted wooden ceilings dating to the 19th century and the historic coral stone facade. '
        'As an active parish, visitors are asked to dress modestly (no shorts, sleeveless shirts, or '
        'revealing attire). For Mass times, check the local Mass Times Philippines directory.',
    'image': 'assets/images/Jimenez - St. John the Baptist Church.jpg',
    'rating': 4.9,
    'category': 'Historical',
    'spotId': 'jimenez_st_john_the_baptist_church',
    'location': 'Barangay Poblacion, Jimenez, Misamis Occidental',
    'openingHours':
        'Typically daily 6:00 AM – 5:00 PM for prayer (standard parish schedule; hours may vary)',
    'entranceFee': 'Free',
    'latitude': 8.3347,
    'longitude': 123.8408,
    'nearbyRestaurants': [
      'Jimenez Plaza Snacks',
      'Heritage Street Eatery',
    ],
    'nearbyHotels': [
      'Jimenez Heritage Lodge',
      'Poblacion Stay Rooms',
    ],
  },
  {
    'name': 'Oroquieta City Plaza',
    'description':
        'Public open space with Iligan Bay seaside views, playground, bandstand, and Rizal monument',
    'detail':
        'Oroquieta City Plaza is a public open space in Misamis Occidental\'s provincial capital, '
        'offering seaside views of Iligan Bay. The plaza features a children\'s playground, a bandstand '
        'for community events, and a Rizal monument — a favorite gathering spot for locals and visitors '
        'enjoying walks along the waterfront promenade.',
    'image': 'assets/images/oroquieta City plaza.jpeg',
    'rating': 4.8,
    'category': 'Park',
    'spotId': 'oroquieta_city_boulevard_and_peoples_park',
    'vrLink': kOroquietaCityPlazaVrUrl,
    'location': 'Oroquieta City, Misamis Occidental',
    'openingHours': 'Open 24 hours daily',
    'entranceFee': 'Free',
    'latitude': 8.4845,
    'longitude': 123.8038,
    'nearbyRestaurants': [
      'City Plaza Food Hub',
      'Oroquieta Night Markets',
    ],
    'nearbyHotels': [
      'Oroquieta City Hotel',
      'Good Life Stay',
    ],
  },
  {
    'name': 'AMORAP',
    'description':
        'Asenso Misamis Occidental Resort and Aquamarine Park — eco-luxury destination in Sinacaban',
    'detail':
        'The Asenso Misamis Occidental Resort and Aquamarine Park (AMORAP) is a Maldives-inspired '
        'eco-luxury destination in Barangay Libertad Bajo, Sinacaban, Misamis Occidental. '
        'Resort grounds and all-day dining are generally accessible daily. Features include coastal '
        'overwater villas, lagoons, water attractions, and leisure facilities — about 30 minutes '
        'from Ozamiz City Airport. Entrance fees and activity rates vary by tier; check the '
        'AMORAP Official Page or AMORAP contact info for current pricing and schedules.',
    'image': 'assets/images/AMORAP.jpg',
    'rating': 4.8,
    'category': 'Park',
    'spotId': 'sinacaban_asenso_aquamarine_park',
    'location': 'Barangay Libertad Bajo, Sinacaban, Misamis Occidental',
    'openingHours':
        'Resort grounds & all-day dining: generally open daily (hours may vary by activity)',
    'entranceFee':
        'Rates vary by activity or accommodation — see AMORAP Official Page for current tiers',
    'latitude': 8.2847,
    'longitude': 123.8456,
    'nearbyRestaurants': [
      'AMORAP All-Day Dining',
      'Overwater Bites',
      'Eco-Lux Café',
    ],
    'nearbyHotels': [
      'AMORAP Overwater Villas',
      'Sinacaban Resort Stays',
    ],
  },
];

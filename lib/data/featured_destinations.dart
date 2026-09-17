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
    'image': 'assets/images/Baliangao.png',
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
        'contact': '09685687575',
        'image': 'assets/municipalities/baliangao/nearby/restaurants/camp_sawi.jpg',
        'rating': 4.5,
        'distanceKm': 5.5,
        'location': 'Baliangao–Calamba Road',
        'description':
            'Comfort food, rice meals like daing na bangus, and burgers (~11 min drive).',
      },
      {
        'name': "Nami's",
        'image': "assets/municipalities/baliangao/nearby/restaurants/namis.jpg",
        'distanceKm': 5.5,
        'location': 'Calamba Road, Baliangao',
        'description':
            'Casual local roadside eatery along Calamba Road. No published menu online—'
            'typical local meal rates are budget-friendly (often under ₱100 to a few hundred pesos); '
            'visit or contact for exact dish prices (~11 min from the coast).',
      },
    ],
    'nearbyHotels': [
      {
        'name': 'Antelmi Travelers Inn',
        'contact': '09157338908',
        'image': "assets/municipalities/baliangao/nearby/hotels/antelmi_travelers_inn.webp",
        'category': 'Lodge',
        'rating': 4.9,
        'location': 'Dipolog-Oroquieta National Road, Eastern Looc, Plaridel',
        'driveMinutes': 43,
        'description':
            'Lodge along the national highway. Rates start around ₱1,100 per night (~43 min drive).',
      },
      {
        'name': 'Hotel Bijoux',
        'contact': '09663684488',
        'image': "assets/municipalities/baliangao/nearby/hotels/hotel_bijoux.webp",
        'category': 'Hotel',
        'rating': 4.6,
        'location': 'Interco Extension, Eastern Looc, Plaridel',
        'driveMinutes': 45,
        'description':
            'Aesthetic, modern, air-conditioned rooms. Rates around ₱2,300 per night (~45 min drive).',
      },
      {
        'name': 'D&M Travellers Inn',
        'contact': '09518683018',
        'image': "assets/municipalities/baliangao/nearby/hotels/dm_travellers_inn.jpg",
        'category': 'Hotel',
        'rating': 4.4,
        'location': 'Looc Proper, Plaridel',
        'driveMinutes': 45,
        'description':
            'Clean, comfortable rooms with free Wi-Fi. Starting around ₱2,500 per night (~45 min drive).',
      },
      {
        'name': 'Daydream Ranch Resort',
        'contact': '09082440119',
        'image': "assets/municipalities/baliangao/nearby/hotels/daydream_ranch_resort.jpg",
        'category': 'Resort',
        'rating': 4.2,
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
        'contact': '09068244031',
        'image': 'assets/municipalities/baliangao/nearby/attractions/cabgan_island.jpg',
      },
      {
        'name': 'Baliangao Protected Landscape and Seascape',
        'image': 'assets/municipalities/baliangao/nearby/attractions/protected_landscape_seascape.png',
      },
      {
        'name': "Jabien's Integrated Farm",
        'contact': '09271167768',
        'image': 'assets/municipalities/baliangao/nearby/attractions/jabiens_integrated_farm.png',
      },
      {
        'name': 'Casa Antonio Resort',
        'contact': '08209007687',
        'image': 'assets/municipalities/baliangao/nearby/attractions/casa_antonio_resort.png',
      },
      {
        'name': 'Bito-on Beach Resort',
        'contact': '09998163808',
        'image': 'assets/municipalities/baliangao/nearby/attractions/bito_on_beach_resort.png',
      },
    ],
    'nearbyCafes': [
      {
        'name': 'Cup of Grace',
        'contact': '09108756735',
        'image': 'assets/municipalities/baliangao/nearby/cafes/cup_of_grace.png',
        'location': 'Baliangao, Misamis Occidental',
        'distanceKm': 0.4,
        'description':
            'Budget-friendly snacks and drinks; items start around ₱35.',
      },
      {
        'name': 'Lei Brew',
        'contact': '09302108191',
        'image': 'assets/municipalities/baliangao/nearby/cafes/lei_brew.png',
        'location': 'Eastern Looc, Plaridel',
        'driveMinutes': 43,
        'description':
            'Affordable coffee and bites (about ₱1–500 per person); serves Baliangao and nearby areas.',
      },
      {
        'name': "Trina's KAPEHAN",
        'contact': '09488737261',
        'image': 'assets/municipalities/baliangao/nearby/cafes/trinas_kapehan.png',
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
      {'name': 'Cribs Diner', 'contact': '09196388932', 'image': "assets/municipalities/ozamiz/nearby/restaurants/cribs_diner.jpg", 'location': 'Laurel Street, 50th Barangay, Ozamiz City', 'openingHours': 'Mon–Wed & Thu–Fri 11 AM–9 PM · Sat–Sun 11 AM–10 PM'},
      {'name': 'Rodolfo\'s Ozamiz', 'contact': '09753041909', 'image': "assets/municipalities/ozamiz/nearby/restaurants/rodolfos.jpg", 'openingHours': 'Daily 8 AM–10 PM'},
      {'name': 'Banyan Resto', 'contact': '(088) 5452381', 'image': "assets/municipalities/ozamiz/nearby/restaurants/banyan_resto.jpg", 'openingHours': 'Daily 8 AM–10 PM'},
      {'name': 'Isla Cafe and Restaurant', 'contact': '09688516607', 'image': "assets/municipalities/ozamiz/nearby/restaurants/isla_cafe_and_restaurant.jpg", 'openingHours': 'Daily 10 AM–9 PM'},
      {'name': 'Puesto', 'contact': '(088) 5452862', 'image': "assets/municipalities/ozamiz/nearby/restaurants/puesto.jpg", 'openingHours': 'Daily 8 AM–9 PM'},
      {'name': "Gat's Bar", 'contact': '(088) 5214075', 'image': "assets/municipalities/ozamiz/nearby/restaurants/gats_bar.jpg", 'openingHours': 'Mon–Sat & Thu 9 AM–3 AM · Sun Closed'},
      {'name': 'Villatuna - Ozamiz City', 'contact': '09669630582', 'image': "assets/municipalities/ozamiz/nearby/restaurants/villatuna.jpg", 'openingHours': 'Daily 10 AM–9 PM'},
      {'name': 'Blue Note Music Lounge', 'contact': '09465830068', 'image': "assets/municipalities/ozamiz/nearby/restaurants/blue_note_music_lounge.jpg", 'openingHours': 'Tue–Sun 10 AM–11 PM · Mon Closed'},
      {'name': 'Kinuman Restaurant', 'contact': '09177701563', 'image': "assets/municipalities/ozamiz/nearby/restaurants/kinuman_restaurant.webp", 'openingHours': 'Fri–Sun 11 AM–9 PM · Mon, Thu & Wed Closed'},
      {'name': 'PANTAWAN RESTAURANT', 'contact': '09165319907', 'image': "assets/municipalities/ozamiz/nearby/restaurants/pantawan_restaurant.jpg"},
      {'name': 'Très Coffee Company', 'contact': '09955197190', 'image': "assets/municipalities/ozamiz/nearby/restaurants/tres_coffee_company.jpg", 'openingHours': 'Daily 8 AM–9 PM'},
      {'name': 'Better Brews - Ozamiz City', 'contact': '09559737743', 'image': "assets/municipalities/ozamiz/nearby/restaurants/better_brews.jpg", 'openingHours': 'Daily 8 AM–10 PM'},
      {'name': 'Grill Champ', 'image': "assets/municipalities/ozamiz/nearby/restaurants/grill_champ.jpg", 'openingHours': 'Daily 10 AM–7:30 PM'},
      {'name': 'Gee Grill', 'contact': '09177129602', 'image': "assets/municipalities/ozamiz/nearby/restaurants/gee_grill.jpg", 'openingHours': 'Daily 11 AM–8 PM'},
      {'name': 'Raan•Day•Vu Cafe', 'contact': '09463401239', 'image': "assets/municipalities/ozamiz/nearby/restaurants/raan_day_vu_cafe.jpg", 'openingHours': 'Daily 7 AM–8:45 PM'},
      {'name': 'Le Bistro', 'image': "assets/municipalities/ozamiz/nearby/restaurants/le_bistro.jpg", 'openingHours': 'Mon–Tue 6 AM–9 PM · Wed–Sun 6 AM–10 PM'},
      {"name": "Foodie's Corner", 'image': "assets/municipalities/ozamiz/nearby/restaurants/foodies_corner.jpg", 'openingHours': 'Daily 7 AM–9 PM'},
      {'name': 'Conrads Restobar', 'image': "assets/municipalities/ozamiz/nearby/restaurants/conrads_restobar.jpg"},
      {'name': 'Chicken Ati-Atihan', 'contact': '09302929443', 'image': "assets/municipalities/ozamiz/nearby/restaurants/chicken_ati_atihan.jpg"},
      {'name': 'NM Gohantoboru Japanese Restaurant', 'contact': '09190951671', 'image': "assets/municipalities/ozamiz/nearby/restaurants/nm_gohantoboru.webp", 'openingHours': 'Daily 10:30 AM–9 PM'},
    ],
    'nearbyHotels': [
      {
        'name': 'Royal Garden Hotel',
        'contact': '(088) 5212888',
        'image': "assets/municipalities/ozamiz/nearby/hotels/royal_garden_hotel.jpeg",
        'gallery': [
          "assets/municipalities/ozamiz/nearby/hotels/royal_garden_hotel.jpeg",
          "assets/municipalities/ozamiz/nearby/hotels/royal_garden_hotel_02.jpg",
          "assets/municipalities/ozamiz/nearby/hotels/royal_garden_hotel_03.jpg",
          "assets/municipalities/ozamiz/nearby/hotels/royal_garden_hotel_04.jpg",
          "assets/municipalities/ozamiz/nearby/hotels/royal_garden_hotel_05.jpg",
          "assets/municipalities/ozamiz/nearby/hotels/royal_garden_hotel_06.webp",
          "assets/municipalities/ozamiz/nearby/hotels/royal_garden_hotel_07.webp",
          "assets/municipalities/ozamiz/nearby/hotels/royal_garden_hotel_08.webp",
          "assets/municipalities/ozamiz/nearby/hotels/royal_garden_hotel_09.webp",
        ],
      },
      {'name': 'AVISHA HOTEL', 'contact': '09770553625', 'image': "assets/municipalities/ozamiz/nearby/hotels/avisha_hotel.jpg"},
      {'name': 'Boutique Hotel', 'contact': '(02) 89225384', 'image': "assets/municipalities/ozamiz/nearby/hotels/boutique_hotel.jpg"},
      {'name': 'Executive Hotel', 'contact': '(088) 5210360', 'image': "assets/municipalities/ozamiz/nearby/hotels/executive_hotel.jpg"},
      {'name': 'GV Hotel Ozamiz', 'contact': '(088) 3190375', 'image': "assets/municipalities/ozamiz/nearby/hotels/gv_hotel.jpg"},
      {'name': 'Mt. Moriah Inn', 'contact': '09362417528', 'image': "assets/municipalities/ozamiz/nearby/hotels/mt_moriah_inn.jpg"},
      {'name': 'Oakhill Inn', 'contact': '09338650535', 'image': "assets/municipalities/ozamiz/nearby/hotels/oakhill_inn.webp"},
    ],
    'nearbyCafes': [
      {'name': '813 – Eight Thirteen Café', 'image': "assets/municipalities/ozamiz/nearby/cafes/eight_thirteen_cafe.png", 'openingHours': 'Varies'},
      {'name': 'iKao Café', 'contact': '09668118134', 'image': "assets/municipalities/ozamiz/nearby/cafes/ikao_cafe.webp"},
      {'name': 'Occidental Kape and Pan', 'contact': '09622026025', 'image': "assets/municipalities/ozamiz/nearby/cafes/occidental_kape_and_pan.jpg"},
      {'name': 'Raan•Day•Vu – Ablaze 2.0', 'image': "assets/municipalities/ozamiz/nearby/cafes/raan_day_vu_ablaze.webp"},
      {'name': 'Raan•Day•Vu Cafe', 'contact': '09463401239', 'image': "assets/municipalities/ozamiz/nearby/cafes/raan_day_vu_cafe.jpg", 'openingHours': 'Daily 7 AM–8:45 PM'},
      {'name': 'Terry & Perry Coffee', 'image': "assets/municipalities/ozamiz/nearby/cafes/terry_and_perry_coffee.webp"},
    ],
    'nearbyAttractions': [
      {
        'name': 'Cotta Fort & Shrine',
        'image': "assets/municipalities/ozamiz/nearby/attractions/cotta_fort_shrine.jpg",
      },
      {
        'name': 'Immaculate Conception Cathedral',
        'contact': '(088) 5210011',
        'image': 'assets/municipalities/ozamiz/nearby/attractions/immaculate_conception_cathedral.webp',
      },
      {
        'name': 'Cotta Beach',
        'image': 'assets/municipalities/ozamiz/nearby/attractions/cotta_beach.jpg',
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
      {
        'name': 'Domings Restaurant and Coffee Shop',
        'contact': '09759285611',
        'image': 'assets/municipalities/tangub/nearby/restaurants/domings_restaurant.png',
        'category': 'Restaurant & Café',
        'location': 'Tangub City',
        'distanceKm': 2.1,
      },
      {
        'name': "D' Hermanos",
        'image': 'assets/municipalities/tangub/nearby/restaurants/d_hermanos.png',
        'category': 'Restaurant',
        'location': 'Tangub City',
        'distanceKm': 2.4,
      },
      {
        'name': 'Purple Haus',
        'contact': '09989702598',
        'image': 'assets/municipalities/tangub/nearby/restaurants/purple_haus.png',
        'category': 'Restaurant',
        'location': 'Tangub City',
        'distanceKm': 2.6,
      },
      {
        'name': 'Sordillas Meals 2 Go',
        'image': 'assets/municipalities/tangub/nearby/restaurants/sordillas.png',
        'category': 'Fast food',
        'location': 'Tangub City',
        'distanceKm': 2.8,
      },
      {
        'name': "Doming's",
        'image': 'assets/municipalities/tangub/nearby/restaurants/domings.png',
        'category': 'Eatery',
        'location': 'Tangub City',
        'distanceKm': 2.2,
      },
    ],
    'nearbyHotels': [
      {
        'name': "Elva's House",
        'contact': '09949002239',
        'image': 'assets/municipalities/tangub/nearby/hotels/elvas_house.png',
        'category': 'Homestay',
        'location': 'Tangub City',
        'distanceKm': 3.0,
      },
    ],
    'nearbyAttractions': [
      {
        'name': 'Hoyohoy Highland Stone Chapel',
        'contact': '09173267878',
        'image': 'assets/municipalities/tangub/nearby/attractions/asenso_global_garden.png',
      },
      {
        'name': 'Camp Sawi',
        'image': 'assets/municipalities/tangub/nearby/attractions/camp_sawi.png',
      },
      {
        'name': 'Asenso Global Gardens',
        'image': 'assets/municipalities/tangub/nearby/attractions/asenso_global_garden.png',
      },
    ],
    'nearbyCafes': [],
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
    'image': 'assets/images/Jimenez.png',
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
      {
        'name': 'Alfredo Seafood House',
        'contact': '09177111346',
        'image': 'assets/municipalities/jimenez/nearby/restaurants/alfredo_seafood.png',
        'category': 'Seafood',
        'location': 'Jimenez',
        'distanceKm': 0.5,
      },
      {
        'name': 'Casa Bacarro Museum and Heritage Restaurant',
        'image': 'assets/municipalities/jimenez/nearby/restaurants/casa_bacarro.png',
        'category': 'Heritage Restaurant',
        'location': 'Jimenez',
        'distanceKm': 0.6,
        'gallery': [
          'assets/municipalities/jimenez/nearby/restaurants/casa_bacarro.png',
          'assets/municipalities/jimenez/nearby/restaurants/casa_bacarro_2.png',
        ],
      },
      {
        'name': 'Lil Cezar Restaurant',
        'contact': '09383023676',
        'image': 'assets/municipalities/jimenez/nearby/restaurants/lil_cezar.png',
        'category': 'Restaurant',
        'location': 'Jimenez',
        'distanceKm': 0.7,
      },
      {
        'name': 'Shanghai Noodle House',
        'contact': '(088) 2723239',
        'image': 'assets/municipalities/jimenez/nearby/restaurants/shanghai_noodle.png',
        'category': 'Chinese',
        'location': 'Jimenez',
        'distanceKm': 0.8,
      },
      {
        'name': 'Sidewok',
        'contact': '09672395779',
        'image': 'assets/municipalities/jimenez/nearby/restaurants/sidewok.png',
        'category': 'Asian',
        'location': 'Jimenez',
        'distanceKm': 0.9,
      },
    ],
    'nearbyHotels': [
      {
        'name': 'Baroto Food Park and Glampgrounds',
        'image': 'assets/municipalities/jimenez/nearby/hotels/baroto_glampgrounds.png',
        'category': 'Glamping',
        'location': 'Jimenez',
        'distanceKm': 1.2,
      },
    ],
    'nearbyAttractions': [],
    'nearbyCafes': [],
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
      {
        'name': "Mon's Grill",
        'image': 'assets/municipalities/oroquieta/nearby/restaurants/mons_grill.webp',
        'category': 'Grill',
        'location': 'Langcangan, Oroquieta City',
        'distanceKm': 1.2,
      },
      {
        'name': 'Better Brews',
        'contact': '09754094858',
        'image': 'assets/municipalities/oroquieta/nearby/restaurants/better_brews.webp',
        'category': 'Restaurant & Café',
        'location': 'Barrientos St, Oroquieta City',
        'distanceKm': 0.7,
      },
      {
        'name': "Bella's Cafe",
        'image': 'assets/municipalities/oroquieta/nearby/restaurants/bellas_cafe.webp',
        'category': 'Café',
        'location': '112 Barrientos St, Oroquieta City',
        'distanceKm': 0.7,
      },
      {
        'name': 'Cucina Luciano',
        'image': 'assets/municipalities/oroquieta/nearby/restaurants/cucina_luciano.webp',
        'category': 'Filipino',
        'location': 'Oroquieta City',
        'distanceKm': 1.1,
      },
      {
        'name': 'Gorg Cafe',
        'image': 'assets/municipalities/oroquieta/nearby/restaurants/gorge_cafe.webp',
        'category': 'Café & Diner',
        'location': 'Lower Langcangan, Oroquieta City',
        'distanceKm': 1.3,
      },
      {
        'name': 'The Waisted Chef',
        'image': 'assets/municipalities/oroquieta/nearby/restaurants/the_waisted_chef.webp',
        'category': 'Restaurant',
        'location': 'Osilao St, Oroquieta City',
        'distanceKm': 0.9,
      },
      {
        'name': 'Chopstick Restobar',
        'contact': '09362553971',
        'image': 'assets/municipalities/oroquieta/nearby/restaurants/chopsticks.webp',
        'category': 'Restobar',
        'location': 'Independence St, Oroquieta City',
        'distanceKm': 0.8,
      },
      {
        'name': 'A+ Coffee Corner',
        'contact': '09614816835',
        'image': 'assets/municipalities/oroquieta/nearby/restaurants/a_plus_coffee_corner.webp',
        'category': 'Coffee shop',
        'location': '79 Dr Jose Rizal St, Oroquieta City',
        'distanceKm': 0.4,
      },
      {
        'name': 'Penny Lane Café',
        'contact': '09171695551',
        'image': 'assets/municipalities/oroquieta/nearby/restaurants/penny_lane_cafe.webp',
        'category': 'Café',
        'location': 'Oroquieta City',
        'distanceKm': 1.0,
      },
      {
        'name': 'Cafe Yek',
        'image': 'assets/municipalities/oroquieta/nearby/restaurants/cafe_yek.jpg',
        'category': 'Coffee shop',
        'location': 'Oroquieta City center',
        'distanceKm': 0.6,
      },
      {
        'name': 'Uma Cafe',
        'image': 'assets/municipalities/oroquieta/nearby/restaurants/uma_cafe.jpg',
        'category': 'Café',
        'location': 'Oroquieta City',
        'distanceKm': 0.8,
      },
    ],
    'nearbyHotels': [
      {
        'name': 'Agricio Farm and Resort',
        'contact': '09681511640',
        'image':
            'assets/municipalities/oroquieta/nearby/hotels/agricio_farm_and_resort.webp',
        'category': 'Resort',
        'location': 'Oroquieta City',
        'distanceKm': 2.5,
        'description':
            'Farm resort with swimming pool and free parking — good for family outings.',
      },
      {
        'name': 'Kenjelo Recreation',
        'contact': '09189676052',
        'image': 'assets/municipalities/oroquieta/nearby/hotels/kenjelo.webp',
        'category': 'Resort',
        'location': 'Oroquieta City',
        'distanceKm': 2.8,
        'description':
            'Recreation resort with a large pool — suited for groups and events.',
      },
      {
        'name': 'Almar Suites',
        'contact': '09171695551',
        'image': 'assets/municipalities/oroquieta/nearby/hotels/almar_suites.webp',
        'category': 'Hotel',
        'location': 'Oroquieta City',
        'distanceKm': 1.0,
        'description':
            'Local suites stay — comfortable rooms near Oroquieta City attractions.',
      },
      {
        'name': 'Costa Del Sol',
        'contact': '09202377777',
        'image': 'assets/municipalities/oroquieta/nearby/hotels/costa_del_sol.webp',
        'category': 'Hotel',
        'location': 'Oroquieta City',
        'distanceKm': 1.4,
        'description':
            'Hotel stay with a coastal feel — good base for exploring the city.',
      },
      {
        'name': "Sheena's Hotel",
        'contact': '(08853) 11158',
        'image': 'assets/municipalities/oroquieta/nearby/hotels/sheenas_hotel.webp',
        'category': 'Hotel',
        'location': 'Oroquieta City',
        'distanceKm': 0.9,
        'description': 'Local hotel option within easy reach of downtown.',
      },
      {
        'name': 'Daminar Riverside Garden',
        'contact': '(08853) 11998',
        'image':
            'assets/municipalities/oroquieta/nearby/hotels/daminar_riverside_garden.webp',
        'category': 'Resort',
        'location': 'Oroquieta City',
        'distanceKm': 2.1,
        'description':
            'Riverside garden resort with greenery — scenic and relaxed overnight stay.',
      },
      {
        'name': 'Novo Hotel',
        'contact': '(088) 5450339',
        'image': 'assets/municipalities/oroquieta/nearby/hotels/novo_hotel.webp',
        'category': 'Hotel',
        'location': 'Oroquieta City center',
        'distanceKm': 0.6,
        'description': 'City hotel within easy reach of the plaza and downtown.',
      },
    ],
    'nearbyCafes': [
      {
        'name': 'A+ Coffee Corner',
        'contact': '09614816835',
        'image': 'assets/municipalities/oroquieta/nearby/cafes/a_plus_coffee_corner.webp',
        'category': 'Coffee shop',
        'location': '79 Dr Jose Rizal St, Oroquieta City',
        'distanceKm': 0.4,
      },
      {
        'name': "Bella's Cafe",
        'image': 'assets/municipalities/oroquieta/nearby/cafes/bellas_cafe.webp',
        'category': 'Café',
        'location': '112 Barrientos St, Oroquieta City',
        'distanceKm': 0.7,
      },
      {
        'name': 'Better Brews',
        'contact': '09754094858',
        'image': 'assets/municipalities/oroquieta/nearby/cafes/better_brews.webp',
        'category': 'Coffee shop',
        'location': 'Barrientos St, Oroquieta City',
        'distanceKm': 0.7,
      },
      {
        'name': 'Cafe Yek',
        'image': 'assets/municipalities/oroquieta/nearby/cafes/cafe_yek.jpg',
        'category': 'Coffee shop',
        'location': 'Oroquieta City center',
        'distanceKm': 0.6,
      },
      {
        'name': 'Chopstick Restobar',
        'contact': '09362553971',
        'image': 'assets/municipalities/oroquieta/nearby/cafes/chopsticks.webp',
        'category': 'Restobar',
        'location': 'Independence St, Oroquieta City',
        'distanceKm': 0.8,
      },
      {
        'name': 'Cucina Luciano',
        'image': 'assets/municipalities/oroquieta/nearby/cafes/cucina_luciano.webp',
        'category': 'Filipino',
        'location': 'Oroquieta City',
        'distanceKm': 1.1,
      },
      {
        'name': 'Gorg Cafe',
        'image': 'assets/municipalities/oroquieta/nearby/cafes/gorge_cafe.webp',
        'category': 'Café & Diner',
        'location': 'Lower Langcangan, Oroquieta City',
        'distanceKm': 1.3,
      },
      {
        'name': "Mon's Grill",
        'image': 'assets/municipalities/oroquieta/nearby/cafes/mons_grill.webp',
        'category': 'Grill',
        'location': 'Langcangan, Oroquieta City',
        'distanceKm': 1.2,
      },
      {
        'name': 'Penny Lane Café',
        'contact': '09171695551',
        'image': 'assets/municipalities/oroquieta/nearby/cafes/penny_lane_cafe.webp',
        'category': 'Café',
        'location': 'Oroquieta City',
        'distanceKm': 1.0,
      },
      {
        'name': 'The Waisted Chef',
        'image': 'assets/municipalities/oroquieta/nearby/cafes/the_waisted_chef.webp',
        'category': 'Restaurant',
        'location': 'Osilao St, Oroquieta City',
        'distanceKm': 0.9,
      },
      {
        'name': 'Uma Cafe',
        'image': 'assets/municipalities/oroquieta/nearby/cafes/uma_cafe.jpg',
        'category': 'Café',
        'location': 'Oroquieta City',
        'distanceKm': 0.8,
      },
    ],
    'nearbyAttractions': [
      {
        'name': 'Ambak-Ambak Falls',
        'image':
            'assets/municipalities/oroquieta/nearby/attractions/ambak_ambak_falls.jpeg',
        'category': 'Falls',
        'location': 'Oroquieta City',
        'distanceKm': 4.5,
        'description':
            'Local waterfall destination — short trek and nature scenery near Oroquieta.',
      },
      {
        'name': 'Ciriaco Pastrano Hanging Footbridge',
        'image':
            'assets/municipalities/oroquieta/nearby/attractions/ciriaco_pastrano_hanging_footbridge.jpeg',
        'category': 'Tourist attraction',
        'location': 'Oroquieta City',
        'distanceKm': 2.2,
        'description':
            'Scenic hanging footbridge — popular for photos and riverside views.',
      },
      {
        'name': 'Isko Resort',
        'image':
            'assets/municipalities/oroquieta/nearby/attractions/isko_resort.jpeg',
        'category': 'Resort',
        'location': 'Oroquieta City',
        'distanceKm': 3.5,
        'description':
            'Local resort stop for swimming, rest, and weekend outings.',
      },
      {
        'name': 'Libadatama Dam / Layawan River',
        'image':
            'assets/municipalities/oroquieta/nearby/attractions/libadatama_dam_layawan_river.jpeg',
        'category': 'Tourist attraction',
        'location': 'Oroquieta City',
        'distanceKm': 2.8,
        'description':
            'City dam and Layawan River area — peaceful water views and open space.',
      },
      {
        'name': 'Mobod Fish Sanctuary',
        'image':
            'assets/municipalities/oroquieta/nearby/attractions/mobod_fish_sanctuary.jpeg',
        'category': 'Tourist attraction',
        'location': 'Mobod, Oroquieta City',
        'distanceKm': 3.0,
        'description':
            'Protected fish sanctuary — good for nature walks and coastal scenery.',
      },
      {
        'name': 'Oro Zipline – Oroquieta City',
        'contact': '(08853) 11213',
        'image':
            'assets/municipalities/oroquieta/nearby/attractions/oro_zipline.jpeg',
        'category': 'Adventure',
        'location': 'Oroquieta City',
        'distanceKm': 4.0,
        'description':
            'Zipline adventure with scenic views — thrill activity near the city.',
      },
      {
        'name': 'Pamana Nature Camping Resort',
        'contact': '09074647482',
        'image':
            'assets/municipalities/oroquieta/nearby/attractions/pamana_nature_camping_resort.webp',
        'category': 'Camping resort',
        'location': 'Oroquieta City',
        'distanceKm': 5.0,
        'description':
            'Nature camping resort — outdoor stays, greenery, and group-friendly grounds.',
      },
      {
        'name': 'Sibucal Hot Springs',
        'image':
            'assets/municipalities/oroquieta/nearby/attractions/sibucal_hot_springs.webp',
        'category': 'Hot springs',
        'location': 'Sibucal, Oroquieta City',
        'distanceKm': 5.5,
        'description':
            'Natural hot springs — relaxing soak after exploring Oroquieta.',
      },
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
    'image': 'assets/images/Amorap.png',
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
      {
        'name': "Palayan Seafood's Restaurant",
        'contact': '09198458311',
        'image': 'assets/municipalities/sinacaban/nearby/restaurants/palayan_seafood.webp',
        'category': 'Seafood',
        'location': 'Sinacaban',
        'distanceKm': 1.5,
      },
      {
        'name': 'Yobab Konam',
        'image': 'assets/municipalities/sinacaban/nearby/restaurants/yobab_konam.png',
        'category': 'Restaurant',
        'location': 'Sinacaban',
        'distanceKm': 1.8,
      },
      {
        'name': 'La Elena Fishyalan Aquapark',
        'contact': '09308290822',
        'image': 'assets/municipalities/sinacaban/nearby/restaurants/la_elena_aquapark.webp',
        'category': 'Restaurant',
        'location': 'Sinacaban',
        'distanceKm': 2.0,
      },
    ],
    'nearbyHotels': [
      {
        'name': 'HG Glomax Inn',
        'contact': '09629891693',
        'image': 'assets/municipalities/sinacaban/nearby/hotels/hg_glomax_inn.webp',
        'category': 'Inn',
        'location': 'Sinacaban',
        'distanceKm': 2.0,
      },
      {
        'name': 'Sinacaban Beach Resort',
        'image': 'assets/municipalities/sinacaban/nearby/hotels/beach_resort.webp',
        'category': 'Beach Resort',
        'location': 'Sinacaban',
        'distanceKm': 2.5,
      },
      {
        'name': 'Sungan Mountain Resort',
        'image': 'assets/municipalities/sinacaban/nearby/hotels/sungan_mountain.webp',
        'category': 'Mountain Resort',
        'location': 'Sinacaban',
        'distanceKm': 3.2,
      },
      {
        'name': 'Pavilion',
        'image': 'assets/municipalities/sinacaban/nearby/hotels/pavilion.webp',
        'category': 'Resort',
        'location': 'Sinacaban',
        'distanceKm': 1.2,
      },
    ],
    'nearbyAttractions': [
      {
        'name': 'Busay Tipan Falls',
        'image': 'assets/municipalities/sinacaban/nearby/attractions/busay_tipan_falls.webp',
      },
      {
        'name': 'Sinacaban Beach Resort',
        'image': 'assets/municipalities/sinacaban/nearby/hotels/beach_resort.webp',
      },
      {
        'name': 'Sungan Mountain Resort',
        'image': 'assets/municipalities/sinacaban/nearby/hotels/sungan_mountain.webp',
      },
    ],
    'nearbyCafes': [],
  },
];

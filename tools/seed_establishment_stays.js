// Seeds demo guest stays + reviews for one establishment so the dashboard
// (Home / Rooms / Insights) has something to show. Follows the real flow
// under the deployed Firestore rules:
//   demo tourist creates pending requests → hotel confirms / rejects /
//   checks out → demo tourist reviews checked-out stays.
// Every doc is tagged seed: 'demo'. Re-running replaces the previous demo set.
// Remove with tools/cleanup_establishment_stays.js.
//
// NOTE: confirmed / checked-out stays count toward DAE for the hotel's
// municipality (LGU DOT preview) until cleaned up.
//
// Usage:
//   node tools/seed_establishment_stays.js <hotelEmail> <hotelPassword> [touristEmail] [touristPassword]
// Example:
//   node tools/seed_establishment_stays.js "melane'shotel@gmail.com" melane123

const {initializeApp} = require('firebase/app');
const {
  getAuth,
  signInWithEmailAndPassword,
  createUserWithEmailAndPassword,
} = require('firebase/auth');
const {
  getFirestore,
  collection,
  doc,
  getDoc,
  setDoc,
  updateDoc,
  Timestamp,
} = require('firebase/firestore/lite');
const {
  FIREBASE_CONFIG,
  STAYS,
  REVIEWS,
  ESTABLISHMENTS,
  DEFAULT_TOURIST_EMAIL,
  DEFAULT_TOURIST_PASSWORD,
  deleteSeededStays,
  deleteSeededReviews,
} = require('./cleanup_establishment_stays');

const DEMO_ROOM_COUNT = 20;

const PH = (province, city) => ({
  nationality: 'Filipino', country: 'Philippines', province, city,
  isLocal: true, localOrForeign: 'Local',
});
const FX = (nationality, country) => ({
  nationality, country, province: '', city: '',
  isLocal: false, localOrForeign: 'Foreign',
});

// status: in (confirmed, in-house) · out (checked_out) · pending · rejected
// daysAgo = check-in day relative to today; rooms = Room 1…N slot numbers.
const GUESTS = [
  {name: 'Maria Santos', sex: 'Female', o: PH('Cebu', 'Cebu City'), party: 2, male: 1, daysAgo: 0, nights: 2, rooms: [3], status: 'in'},
  {name: 'Juan Dela Cruz', sex: 'Male', o: PH('Metro Manila', 'Quezon City'), party: 4, male: 2, daysAgo: 1, nights: 3, rooms: [7, 8], status: 'in'},
  {name: 'Emily Carter', sex: 'Female', o: FX('American', 'United States'), party: 2, male: 1, daysAgo: 2, nights: 4, rooms: [12], status: 'in'},
  {name: 'Hiro Tanaka', sex: 'Male', o: FX('Japanese', 'Japan'), party: 1, male: 1, daysAgo: 0, nights: 1, rooms: [15], status: 'in'},
  {name: 'Ana Reyes', sex: 'Female', o: PH('Misamis Occidental', 'Ozamiz City'), party: 3, male: 1, daysAgo: 1, nights: 2, rooms: [5], status: 'in'},

  {name: 'Carlo Mendoza', sex: 'Male', o: PH('Davao del Sur', 'Davao City'), party: 2, male: 2, daysAgo: 3, nights: 2, rooms: [1], status: 'out', review: [5, 5, 'Clean room and very friendly front desk. Will be back!']},
  {name: 'Grace Lim', sex: 'Female', o: PH('Lanao del Norte', 'Iligan City'), party: 2, male: 0, daysAgo: 4, nights: 1, rooms: [2], status: 'out', review: [4, 4, 'Comfortable bed, quick check-in.']},
  {name: "Liam O'Brien", sex: 'Male', o: FX('Irish', 'Ireland'), party: 2, male: 1, daysAgo: 5, nights: 3, rooms: [12], status: 'out', review: [5, 4, 'Great location near the plaza. Aircon a bit noisy.']},
  {name: 'Joy Villanueva', sex: 'Female', o: PH('Misamis Oriental', 'Cagayan de Oro City'), party: 5, male: 2, daysAgo: 6, nights: 2, rooms: [7, 8], status: 'out', review: [4, 5, 'Family rooms were spacious for the kids.']},
  {name: 'Mark Bautista', sex: 'Male', o: PH('Zamboanga del Norte', 'Dipolog City'), party: 1, male: 1, daysAgo: 7, nights: 1, rooms: [3], status: 'out'},
  {name: 'Sofia Garcia', sex: 'Female', o: FX('Spanish', 'Spain'), party: 2, male: 1, daysAgo: 8, nights: 2, rooms: [4], status: 'out', review: [5, 5, 'Lovely staff, breakfast was excellent.']},
  {name: 'Paolo Ramos', sex: 'Male', o: PH('Misamis Occidental', 'Oroquieta City'), party: 3, male: 2, daysAgo: 9, nights: 1, rooms: [1], status: 'out'},
  {name: 'Kim Ji-woo', sex: 'Female', o: FX('Korean', 'South Korea'), party: 2, male: 0, daysAgo: 10, nights: 3, rooms: [9], status: 'out', review: [3, 4, 'Room was nice but WiFi was slow in the evening.']},
  {name: 'Rhea Fernandez', sex: 'Female', o: PH('Misamis Occidental', 'Tangub City'), party: 4, male: 2, daysAgo: 11, nights: 2, rooms: [5, 6], status: 'out'},
  {name: 'Daniel Cruz', sex: 'Male', o: PH('Bohol', 'Tagbilaran City'), party: 2, male: 1, daysAgo: 12, nights: 1, rooms: [2], status: 'out', review: [4, 3, 'Good value for the price.']},
  {name: 'Noah Schmidt', sex: 'Male', o: FX('German', 'Germany'), party: 1, male: 1, daysAgo: 13, nights: 2, rooms: [10], status: 'out'},
  {name: 'Bea Aquino', sex: 'Female', o: PH('Metro Manila', 'Makati City'), party: 2, male: 1, daysAgo: 15, nights: 2, rooms: [3], status: 'out'},
  {name: 'Jose Tan', sex: 'Male', o: PH('Cebu', 'Mandaue City'), party: 3, male: 2, daysAgo: 17, nights: 1, rooms: [1], status: 'out'},
  {name: 'Chloe Martin', sex: 'Female', o: FX('French', 'France'), party: 2, male: 1, daysAgo: 19, nights: 3, rooms: [11], status: 'out', review: [5, 5, 'Quiet, spotless and the view was beautiful.']},
  {name: 'Ramon Castillo', sex: 'Male', o: PH('Iloilo', 'Iloilo City'), party: 2, male: 1, daysAgo: 21, nights: 2, rooms: [4], status: 'out'},
  {name: 'Lea Navarro', sex: 'Female', o: PH('Zamboanga del Sur', 'Pagadian City'), party: 1, male: 0, daysAgo: 24, nights: 1, rooms: [2], status: 'out'},
  {name: 'Ethan Brown', sex: 'Male', o: FX('Australian', 'Australia'), party: 2, male: 2, daysAgo: 27, nights: 2, rooms: [6], status: 'out'},

  {name: 'Mika Torres', sex: 'Female', o: PH('Metro Manila', 'Pasig City'), party: 2, male: 0, daysAgo: 0, status: 'pending', minutesAgo: 20},
  {name: 'Arnel Gomez', sex: 'Male', o: PH('Misamis Occidental', 'Ozamiz City'), party: 3, male: 0, daysAgo: 0, status: 'pending', minutesAgo: 120},
  {name: 'Olivia Wilson', sex: 'Female', o: FX('British', 'United Kingdom'), party: 1, male: 0, daysAgo: 0, status: 'pending', minutesAgo: 45},

  {name: 'Kevin Uy', sex: 'Male', o: PH('Misamis Occidental', 'Clarin'), party: 2, male: 1, daysAgo: 3, status: 'rejected', note: 'Fully booked for requested date.'},
  {name: 'Tessa Lopez', sex: 'Female', o: PH('Lanao del Norte', 'Iligan City'), party: 1, male: 0, daysAgo: 9, status: 'rejected', note: 'Guest cancelled at the desk.'},
];

function demoInventory(roomCount) {
  const inv = {};
  for (let i = 1; i <= roomCount; i++) {
    let info;
    if (i <= 6) {
      info = {type: 'Standard', capacityMin: 1, capacityMax: 2, pricePerNight: 1500,
        inclusions: ['Air conditioning', 'WiFi', 'Private bathroom', 'Hot water']};
    } else if (i <= 10) {
      info = {type: 'Family', capacityMin: 4, capacityMax: 6, pricePerNight: 3200,
        inclusions: ['Air conditioning', 'WiFi', 'TV', 'Fridge', 'Private bathroom']};
    } else if (i <= 16) {
      info = {type: 'Deluxe', capacityMin: 2, capacityMax: 3, pricePerNight: 2400,
        inclusions: ['Air conditioning', 'WiFi', 'TV', 'Breakfast', 'Hot water']};
    } else {
      info = {type: 'Suite', capacityMin: 2, capacityMax: 4, pricePerNight: 4500,
        inclusions: ['Air conditioning', 'WiFi', 'TV', 'Kitchen', 'Balcony', 'Breakfast']};
    }
    inv[String(i)] = {...info, notes: ''};
  }
  return inv;
}

async function signInOrCreate(auth, email, password) {
  try {
    return await signInWithEmailAndPassword(auth, email, password);
  } catch (e) {
    const code = e && e.code ? e.code : '';
    if (code === 'auth/user-not-found' ||
        code === 'auth/invalid-credential' ||
        code === 'auth/invalid-login-credentials') {
      try {
        return await createUserWithEmailAndPassword(auth, email, password);
      } catch (createErr) {
        if (createErr && createErr.code === 'auth/email-already-in-use') {
          throw new Error(`${email} exists but the password does not match.`);
        }
        throw createErr;
      }
    }
    throw e;
  }
}

function atDay(daysAgo, hour, minute = 0) {
  const now = new Date();
  return new Date(now.getFullYear(), now.getMonth(), now.getDate() - daysAgo,
      hour, minute);
}

function addMinutes(d, m) {
  return new Date(d.getTime() + m * 60000);
}

function addDays(d, n) {
  return new Date(d.getFullYear(), d.getMonth(), d.getDate() + n,
      d.getHours(), d.getMinutes());
}

const ts = (d) => Timestamp.fromDate(d);

async function main() {
  const [hotelEmailArg, hotelPassword, touristEmailArg, touristPasswordArg] =
      process.argv.slice(2);
  if (!hotelEmailArg || !hotelPassword) {
    console.error('Usage: node tools/seed_establishment_stays.js ' +
        '<hotelEmail> <hotelPassword> [touristEmail] [touristPassword]');
    process.exit(1);
  }
  const hotelEmail = hotelEmailArg.trim().toLowerCase();
  const touristEmail =
      (touristEmailArg || DEFAULT_TOURIST_EMAIL).trim().toLowerCase();
  const touristPassword = touristPasswordArg || DEFAULT_TOURIST_PASSWORD;

  const app = initializeApp(FIREBASE_CONFIG);
  const auth = getAuth(app);
  const db = getFirestore(app);

  // 1) Hotel: read profile, clear old demo stays, ensure rooms exist.
  console.log(`Signing in as hotel ${hotelEmail}...`);
  const hotelUid =
      (await signInWithEmailAndPassword(auth, hotelEmail, hotelPassword)).user.uid;
  const estRef = doc(db, ESTABLISHMENTS, hotelUid);
  const estSnap = await getDoc(estRef);
  if (!estSnap.exists()) {
    throw new Error(`No ${ESTABLISHMENTS}/${hotelUid} doc. ` +
        'Run tools/seed_establishment_account.js first.');
  }
  const est = estSnap.data();
  const establishmentName = String(est.businessName || est.name || 'Establishment').trim();
  const municipality = String(est.municipality || '').trim();
  const municipalityId = String(est.municipalityId || '').trim();
  const category = String(est.category || est.type || '').trim();
  console.log(`Establishment: ${establishmentName} (${municipality}) uid=${hotelUid}`);

  const removedStays = await deleteSeededStays(db, hotelUid);
  if (removedStays) console.log(`Removed ${removedStays} previous demo stay(s).`);

  let roomCount = parseInt(est.roomCount, 10);
  const seededRooms = !Number.isFinite(roomCount) || roomCount < 1;
  if (seededRooms) {
    roomCount = DEMO_ROOM_COUNT;
    await setDoc(estRef, {
      roomCount,
      roomInventory: demoInventory(roomCount),
      disabledRooms: ['19'],
      seedDemoRooms: true,
    }, {merge: true});
    console.log(`Set up ${roomCount} demo rooms (Room 19 disabled for maintenance).`);
  } else {
    console.log(`Keeping existing room setup (${roomCount} rooms).`);
  }
  const slot = (n) => String(((n - 1) % roomCount) + 1);
  // In-house guests need distinct, enabled rooms even on small room counts.
  const blocked = new Set((Array.isArray(est.disabledRooms) ? est.disabledRooms : [])
      .map((r) => String(r).trim()));
  if (seededRooms) blocked.add('19');
  const inHouseSlot = (n) => {
    let i = ((n - 1) % roomCount) + 1;
    for (let tries = 0; tries < roomCount; tries++) {
      const id = String(i);
      if (!blocked.has(id)) {
        blocked.add(id);
        return id;
      }
      i = (i % roomCount) + 1;
    }
    return null;
  };

  // 2) Demo tourist: clear old demo reviews, create pending requests.
  console.log(`Signing in as demo tourist ${touristEmail}...`);
  const touristUid =
      (await signInOrCreate(auth, touristEmail, touristPassword)).user.uid;
  const removedReviews = await deleteSeededReviews(db, hotelUid, touristUid);
  if (removedReviews) console.log(`Removed ${removedReviews} previous demo review(s).`);

  const now = new Date();
  const plans = [];
  for (const g of GUESTS) {
    const checkIn = g.daysAgo === 0 ?
      addMinutes(now, -(g.minutesAgo != null ? g.minutesAgo : 90)) :
      atDay(g.daysAgo, 14, (g.name.length * 7) % 50);
    const createdAt = g.status === 'pending' ? checkIn : addMinutes(checkIn, -20);
    const fil = g.o.isLocal ? g.party : 0;
    // Party of 1 prefills from profile; larger pending parties stay 0 (staff fills).
    const prefill = g.party === 1 || g.status !== 'pending';
    const ref = doc(collection(db, STAYS));
    await setDoc(ref, {
      establishmentId: hotelUid,
      establishmentName,
      establishmentCategory: category,
      roomsAvailable: roomCount,
      municipalityId,
      municipality,
      touristId: touristUid,
      touristName: g.name,
      touristEmail,
      touristSex: g.sex,
      touristNationality: g.o.nationality,
      touristCountry: g.o.country,
      touristProvince: g.o.province,
      touristCity: g.o.city,
      touristIsLocal: g.o.isLocal,
      touristLocalOrForeign: g.o.localOrForeign,
      status: 'pending',
      partySize: g.party,
      maleCount: prefill ? g.male : 0,
      femaleCount: prefill ? g.party - g.male : 0,
      filipinoCount: prefill ? fil : 0,
      foreignCount: prefill ? g.party - fil : 0,
      qrType: 'establishment',
      createdAt: ts(createdAt),
      clientCreatedAt: createdAt.toISOString(),
      seed: 'demo',
    });
    plans.push({g, ref, checkIn, fil});
  }
  console.log(`Created ${plans.length} pending stay request(s).`);

  // 3) Hotel: confirm / check out / reject like the desk would.
  await signInWithEmailAndPassword(auth, hotelEmail, hotelPassword);
  const counts = {in: 0, out: 0, pending: 0, rejected: 0};
  let roomNights = 0;
  for (const p of plans) {
    const {g, ref, checkIn, fil} = p;
    counts[g.status]++;
    if (g.status === 'pending') continue;
    const confirmedAt = addMinutes(checkIn, 10);
    if (g.status === 'rejected') {
      await updateDoc(ref, {
        status: 'rejected',
        notes: g.note || '',
        confirmedAt: ts(confirmedAt),
        clientConfirmedAt: confirmedAt.toISOString(),
        confirmedByStaffUid: hotelUid,
      });
      continue;
    }
    const rooms = g.status === 'in' ?
      g.rooms.map(inHouseSlot).filter(Boolean) :
      [...new Set(g.rooms.map(slot))];
    if (rooms.length === 0) rooms.push(slot(g.rooms[0]));
    const checkOut = addDays(checkIn, g.nights);
    roomNights += rooms.length * g.nights;
    const patch = {
      status: 'confirmed',
      nightsStayed: g.nights,
      roomsOccupied: rooms.length,
      partySize: g.party,
      maleCount: g.male,
      femaleCount: g.party - g.male,
      filipinoCount: fil,
      foreignCount: g.party - fil,
      roomNumbers: rooms,
      notes: '',
      confirmedAt: ts(confirmedAt),
      clientConfirmedAt: confirmedAt.toISOString(),
      confirmedByStaffUid: hotelUid,
      checkInAt: ts(checkIn),
      checkOutAt: ts(checkOut),
      establishmentCategory: category,
      roomsAvailable: roomCount,
    };
    if (g.status === 'out') {
      const outAt = new Date(checkOut.getFullYear(), checkOut.getMonth(),
          checkOut.getDate(), 11, 0);
      Object.assign(patch, {
        status: 'checked_out',
        checkedOutAt: ts(outAt),
        clientCheckedOutAt: outAt.toISOString(),
        checkedOutByUid: hotelUid,
      });
      p.outAt = outAt;
      p.rooms = rooms;
    }
    await updateDoc(ref, patch);
    if (g.status === 'in') {
      console.log(`  In-house: ${g.name} → Room ${rooms.join(', ')}`);
    }
  }
  console.log(`Hotel desk: ${counts.in} in-house, ${counts.out} checked out, ` +
      `${counts.rejected} rejected, ${counts.pending} left pending ` +
      `(${roomNights} room-nights).`);

  // 4) Demo tourist: reviews for some checked-out stays.
  await signInWithEmailAndPassword(auth, touristEmail, touristPassword);
  let reviews = 0;
  for (const p of plans) {
    if (p.g.status !== 'out' || !p.g.review) continue;
    const [hotelRating, roomRating, comment] = p.g.review;
    const at = addMinutes(p.outAt, 90);
    await setDoc(doc(collection(db, REVIEWS)), {
      stayRequestId: p.ref.id,
      establishmentId: hotelUid,
      touristId: touristUid,
      userId: touristUid,
      authorName: p.g.name,
      establishmentName,
      roomNumbers: p.rooms,
      hotelRating,
      roomRating,
      comment,
      createdAt: ts(at),
      seed: 'demo',
    });
    reviews++;
  }
  console.log(`Created ${reviews} review(s).`);

  console.log('\nDone. Hot restart the app and open the establishment dashboard.');
  console.log(`Remove later: node tools/cleanup_establishment_stays.js "${hotelEmail}" <password>`);
  process.exit(0);
}

main().catch((e) => {
  console.error('Seeding failed:', e && e.message ? e.message : e);
  process.exit(1);
});

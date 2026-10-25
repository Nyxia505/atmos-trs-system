const {initializeApp} = require('firebase/app');
const {getAuth, signInWithEmailAndPassword} = require('firebase/auth');
const {getFunctions, httpsCallable} = require('firebase/functions');
const {
  getFirestore,
  collection,
  doc,
  getDocs,
  query,
  where,
  limit,
  writeBatch,
  serverTimestamp,
  Timestamp,
} = require('firebase/firestore/lite');

const DEMO_GOVERNOR_EMAIL = 'governor.atmos@misocc-demo.ph';
const DEMO_GOVERNOR_PASSWORD = 'Admin123@';

const MUNICIPALITIES = [
  ['oroquieta', 'Oroquieta City'],
  ['ozamiz', 'Ozamis City'],
  ['tangub', 'Tangub City'],
  ['aloran', 'Aloran'],
  ['baliangao', 'Baliangao'],
  ['bonifacio', 'Bonifacio'],
  ['calamba', 'Calamba'],
  ['clarin', 'Clarin'],
  ['concepcion', 'Concepcion'],
  ['dvc', 'Don Victoriano Chiongbian'],
  ['jimenez', 'Jimenez'],
  ['lopezjaena', 'Lopez Jaena'],
  ['panaon', 'Panaon'],
  ['plaridel', 'Plaridel'],
  ['sapangdalaga', 'Sapang Dalaga'],
  ['sinacaban', 'Sinacaban'],
  ['tudela', 'Tudela'],
];

const FIRST = [
  'Ana', 'Ben', 'Carla', 'David', 'Erika', 'Francis', 'Grace',
  'Hector', 'Ivy', 'John', 'Karen', 'Leo', 'Mara', 'Nico', 'Olive',
  'Paolo', 'Queenie', 'Ramon', 'Sarah', 'Troy',
];
const LAST = [
  'Santos', 'Reyes', 'Cruz', 'Lopez', 'Garcia', 'Mendoza',
  'Ramos', 'Aquino', 'Dela Cruz', 'Torres',
];
const FOREIGN = [
  ['American', 'United States', 'California', 'San Francisco'],
  ['Japanese', 'Japan', '', 'Tokyo'],
  ['Korean', 'South Korea', '', 'Seoul'],
  ['Australian', 'Australia', 'NSW', 'Sydney'],
  ['Chinese', 'China', '', 'Beijing'],
];

function displayId(uid) {
  let hash = 0;
  for (const unit of uid) {
    hash = (hash * 33 + unit.charCodeAt(0)) >>> 0;
  }
  const hex = hash.toString(16).padStart(8, '0');
  return `MO-${hex.slice(-8).toUpperCase()}`;
}

function dateOfBirth(index, now) {
  const ages = [16, 21, 28, 33, 41, 52, 61];
  const age = ages[index % ages.length];
  const birth = new Date(now.getFullYear() - age, index % 12, (index % 27) + 1);
  const month = String(birth.getMonth() + 1).padStart(2, '0');
  const day = String(birth.getDate()).padStart(2, '0');
  return `${birth.getFullYear()}-${month}-${day}`;
}

function lastNDays(now, n) {
  const today = new Date(now.getFullYear(), now.getMonth(), now.getDate());
  const days = [];
  for (let i = n - 1; i >= 0; i--) {
    days.push(new Date(today.getFullYear(), today.getMonth(), today.getDate() - i));
  }
  return days;
}

async function seedOnClient(authApp, {
  municipalityId,
  seedAll,
  localCount,
  foreignCount,
  checkInsPerTourist,
}) {
  const db = getFirestore(authApp);
  const targets = seedAll
    ? MUNICIPALITIES
    : MUNICIPALITIES.filter(([id]) => id === municipalityId);
  const chosen = targets.length ? targets : [[municipalityId, municipalityId]];
  const now = new Date();
  const recentDays = lastNDays(now, 7);
  const touristTotal = localCount + foreignCount;
  let seededTourists = 0;
  let seededCheckIns = 0;
  let batch = writeBatch(db);
  let ops = 0;

  async function flush(force = false) {
    if (ops === 0) return;
    if (!force && ops < 400) return;
    await batch.commit();
    batch = writeBatch(db);
    ops = 0;
  }

  function enqueue(ref, data) {
    batch.set(ref, data, {merge: true});
    ops += 1;
  }

  for (const [munId, munName] of chosen) {
    const spotSnap = await getDocs(query(
      collection(db, 'tourist_spots'),
      where('municipalityId', '==', munId),
      limit(30),
    ));
    let spots = spotSnap.docs.map((d) => ({
      id: d.id,
      name: (d.data().name || d.id).toString(),
    }));
    if (spots.length === 0) {
      const hubId = `${munId}_visitor_hub`;
      const hub = writeBatch(db);
      hub.set(doc(db, 'tourist_spots', hubId), {
        name: `${munName} Visitor Hub`,
        category: 'Resort',
        municipalityId: munId,
        municipality: munName,
        status: 'Active',
        updatedAt: serverTimestamp(),
      }, {merge: true});
      await hub.commit();
      spots = [{id: hubId, name: `${munName} Visitor Hub`}];
    }

    for (let i = 0; i < touristTotal; i++) {
      const isLocal = i < localCount;
      const fn = FIRST[i % FIRST.length];
      const ln = LAST[i % LAST.length];
      const uid = `seed_tourist_${munId}_${String(i + 1).padStart(3, '0')}`;
      const email = `seed.${munId}.${i + 1}@misocc-seed.ph`;
      const sex = i % 2 === 0 ? 'Female' : 'Male';
      const foreign = FOREIGN[i % FOREIGN.length];
      const nationality = isLocal ? 'Filipino' : foreign[0];
      const country = isLocal ? 'Philippines' : foreign[1];
      const province = isLocal ? 'Misamis Occidental' : foreign[2];
      const city = isLocal ? munName : foreign[3];
      const touristId = displayId(uid);
      const dob = dateOfBirth(i, now);
      const registeredAt = Timestamp.fromDate(
        new Date(now.getTime() - (30 - (i % 28)) * 86400000),
      );

      enqueue(doc(db, 'tourists', uid), {
        firebaseUid: uid,
        touristId,
        firstName: fn,
        lastName: ln,
        fullName: `${fn} ${ln}`,
        email,
        authEmail: email,
        sex,
        dateOfBirth: dob,
        nationality,
        country,
        province,
        city,
        barangay: isLocal ? 'Poblacion' : '',
        isLocal,
        localOrForeign: isLocal ? 'Local' : 'Foreign',
        partyHeadcount: 1,
        status: 'Active',
        isVerified: true,
        ...(isLocal ? {registrationMunicipalityId: munId} : {}),
        totalVisits: checkInsPerTourist,
        source: 'lgu_debug_seed',
        seedTag: 'lgu_analytics_debug_v2_address',
        updatedAt: serverTimestamp(),
        createdAt: registeredAt,
        registeredAt,
      });
      enqueue(doc(db, 'users', uid), {
        firebaseUid: uid,
        email,
        role: 'tourist',
        fullName: `${fn} ${ln}`,
        dateOfBirth: dob,
        ...(isLocal ? {municipalityId: munId, municipality: munName} : {}),
        isVerified: true,
        source: 'lgu_debug_seed',
        seedTag: 'lgu_analytics_debug_v2_address',
        updatedAt: serverTimestamp(),
      });
      seededTourists += 1;

      for (let j = 0; j < checkInsPerTourist; j++) {
        const dayDate = recentDays[j % recentDays.length];
        const spot = spots[(i + j) % spots.length];
        const eventDate = new Date(
          dayDate.getFullYear(),
          dayDate.getMonth(),
          dayDate.getDate(),
          9 + ((i + j) % 9),
          (i * 7 + j * 11) % 60,
        );
        const checkinId =
          `${uid}_${spot.id}_${dayDate.getFullYear()}_m${dayDate.getMonth() + 1}_d${dayDate.getDate()}_v${j + 1}`;
        const ts = Timestamp.fromDate(eventDate);
        const femaleCount = sex === 'Female' ? 1 : 0;
        const maleCount = sex === 'Male' ? 1 : 0;
        enqueue(doc(db, 'qr_checkins', checkinId), {
          userId: uid,
          user_id: uid,
          tourist_id: uid,
          touristId,
          touristName: `${fn} ${ln}`,
          tourist_name: `${fn} ${ln}`,
          touristEmail: email,
          touristNationality: nationality,
          municipalityId: munId,
          lguId: munId,
          municipality: munName,
          spotId: spot.id,
          spot_id: spot.id,
          touristSpotId: spot.id,
          spot_name: spot.name,
          spotName: spot.name,
          location: spot.name,
          status: 'Verified',
          source: 'qr_scan',
          seedTag: 'lgu_analytics_debug_v1',
          partySize: 1,
          visitorCount: 1,
          femaleCount,
          maleCount,
          filipinoCount: isLocal ? 1 : 0,
          foreignCount: isLocal ? 0 : 1,
          touristSex: sex,
          touristDateOfBirth: dob,
          touristCountry: country,
          touristProvince: province,
          touristCity: city,
          touristIsLocal: isLocal,
          touristLocalOrForeign: isLocal ? 'Local' : 'Foreign',
          timestamp: ts,
          createdAt: ts,
        });
        seededCheckIns += 1;
        if (ops >= 400) await flush(true);
      }
    }
    await flush(true);
    console.log(`  ${munName}: ${touristTotal} tourists, spots ${spots.length}`);
  }

  return {seededTourists, seededCheckIns, via: 'client_batch'};
}

async function main() {
  const municipalityId = (process.argv[2] || 'oroquieta').trim().toLowerCase();
  const localCount = Number(process.argv[3] || 8);
  const foreignCount = Number(process.argv[4] || 4);
  const seedAll = process.argv.includes('--all') || municipalityId === '--all';

  const app = initializeApp({
    apiKey: 'AIzaSyAQcksY7LOLTeGKx_OwhDQ2wNLJ4o_OgtU',
    authDomain: 'atmos-trs-system.firebaseapp.com',
    projectId: 'atmos-trs-system',
    appId: '1:760231001760:web:609c5e6783594773cf13c5',
  });

  const auth = getAuth(app);
  console.log(`Signing in as ${DEMO_GOVERNOR_EMAIL}...`);
  await signInWithEmailAndPassword(auth, DEMO_GOVERNOR_EMAIL, DEMO_GOVERNOR_PASSWORD);

  const functions = getFunctions(app, 'asia-southeast1');
  const callSeed = httpsCallable(functions, 'seedLguAnalyticsData');
  console.log(
    seedAll
      ? `Seeding ALL municipalities (${localCount} Filipino + ${foreignCount} foreign each)`
      : `Seeding ${municipalityId} (${localCount} Filipino + ${foreignCount} foreign)`,
  );
  try {
    const response = await callSeed({
      municipalityId: seedAll ? 'oroquieta' : municipalityId,
      seedAllMunicipalities: seedAll,
      localCount,
      foreignCount,
      checkInsPerTourist: 2,
    });
    console.log('seedLguAnalyticsData:', JSON.stringify(response.data, null, 2));
  } catch (error) {
    const code = error.code || '';
    if (code !== 'functions/not-found' && code !== 'functions/unavailable') {
      throw error;
    }
    console.log('Cloud function unavailable. Writing check-ins directly...');
    const result = await seedOnClient(app, {
      municipalityId: seedAll ? 'oroquieta' : municipalityId,
      seedAll,
      localCount,
      foreignCount,
      checkInsPerTourist: 2,
    });
    console.log('client seed:', JSON.stringify(result, null, 2));
  }
}

main().catch((e) => {
  console.error('Seeding failed:', e);
  process.exit(1);
});

/**
 * Seed `hub_spot_transport_fees` — bus terminal/stop → tourist spot fares.
 *
 *   node seed-hub-spot-transport-fees-once.js
 */
const admin = require("firebase-admin");

if (!admin.apps.length) {
  admin.initializeApp({ projectId: "atmos-trs-system" });
}

const db = admin.firestore();
const FieldValue = admin.firestore.FieldValue;

const HUBS = {
  Aloran: { name: "Aloran bus stop", kind: "stop" },
  Baliangao: { name: "Calamba and Baliangao bus terminal", kind: "terminal" },
  Calamba: { name: "Calamba and Baliangao bus terminal", kind: "terminal" },
  Clarin: { name: "Clarin bus terminal", kind: "terminal" },
  Jimenez: { name: "Jimenez bus terminal", kind: "terminal" },
  "Lopez Jaena": { name: "Lopez Jaena bus stop", kind: "stop" },
  "Oroquieta City (Provincial Capital)": {
    name: "Oroquieta bus terminal",
    kind: "terminal",
  },
  "Ozamiz City": { name: "Ozamiz bus terminal", kind: "terminal" },
  Panaon: { name: "Panaon bus stop", kind: "stop" },
  Plaridel: { name: "Plaridel bus terminal", kind: "terminal" },
  "Sapang Dalaga": { name: "Sapang Dalaga bus stop", kind: "stop" },
  Sinacaban: { name: "Sinacaban bus terminal", kind: "terminal" },
  "Tangub City": { name: "Tangub bus terminal", kind: "terminal" },
  Tudela: { name: "Tudela bus stop", kind: "stop" },
};

const MATRIX = [
  {
    municipality: "Aloran",
    spotSlug: "aloran_viewpoint",
    spotName: "Aloran Viewpoint",
    fareMin: 20,
    fareMax: 40,
  },
  {
    municipality: "Baliangao",
    spotSlug: "baliangao_protected_landscape",
    spotName: "Baliangao Protected Landscape",
    fareMin: 50,
    fareMax: 80,
  },
  {
    municipality: "Calamba",
    spotSlug: "calamba_green_hills",
    spotName: "Calamba Green Hills",
    fareMin: 15,
    fareMax: 30,
  },
  {
    municipality: "Clarin",
    spotSlug: "clarin_lake_duminagat",
    spotName: "Clarin Lake Duminagat",
    fareMin: 80,
    fareMax: 150,
  },
  {
    municipality: "Jimenez",
    spotSlug: "jimenez_st_john_the_baptist_church",
    spotName: "Jimenez St. John the Baptist Church",
    fareMin: 10,
    fareMax: 20,
  },
  {
    municipality: "Lopez Jaena",
    spotSlug: "lopez_jaena_beachfront",
    spotName: "Lopez Jaena Beachfront",
    fareMin: 15,
    fareMax: 30,
  },
  {
    municipality: "Oroquieta City (Provincial Capital)",
    spotSlug: "oroquieta_city_boulevard_and_peoples_park",
    spotName: "Oroquieta City Boulevard and People's Park",
    fareMin: 10,
    fareMax: 20,
  },
  {
    municipality: "Ozamiz City",
    spotSlug: "ozamiz_cotta_fort_wellness_park",
    spotName: "Ozamiz Cotta Fort Wellness Park",
    fareMin: 15,
    fareMax: 25,
  },
  {
    municipality: "Panaon",
    spotSlug: "panaon_seaside",
    spotName: "Panaon Seaside",
    fareMin: 15,
    fareMax: 35,
  },
  {
    municipality: "Plaridel",
    spotSlug: "plaridel_resort",
    spotName: "Plaridel Resort",
    fareMin: 20,
    fareMax: 40,
  },
  {
    municipality: "Sapang Dalaga",
    spotSlug: "sapang_dalaga_floating_cottages",
    spotName: "Sapang Dalaga Floating Cottages",
    fareMin: 30,
    fareMax: 60,
  },
  {
    municipality: "Sinacaban",
    spotSlug: "sinacaban_asenso_aquamarine_park",
    spotName: "Sinacaban Asenso Aquamarine Park",
    fareMin: 20,
    fareMax: 40,
  },
  {
    municipality: "Tangub City",
    spotSlug: "tangub_asenso_global_gardens",
    spotName: "Tangub Asenso Global Gardens",
    fareMin: 30,
    fareMax: 50,
  },
  {
    municipality: "Tudela",
    spotSlug: "tudela_highland_resort_eco_park",
    spotName: "Tudela Highland Resort Eco Park",
    fareMin: 40,
    fareMax: 80,
  },
];

function slugify(s) {
  return String(s)
    .toLowerCase()
    .replace(/provincial capital/gi, "")
    .replace(/[^a-z0-9]+/g, "_")
    .replace(/^_|_$/g, "");
}

function buildFees() {
  const fees = [];
  for (const row of MATRIX) {
    const hub = HUBS[row.municipality];
    if (!hub) {
      console.warn("No hub for", row.municipality);
      continue;
    }
    const endpointSlug = slugify(hub.name);
    const muniSlug = slugify(row.municipality);
    const fare = Math.round((row.fareMin + row.fareMax) / 2);
    const base = {
      fromEndpointName: hub.name,
      fromEndpointType: hub.kind,
      municipality: row.municipality,
      municipalitySlug: muniSlug,
      toTouristSpotSlug: row.spotSlug,
      toTouristSpotName: row.spotName,
      fareMin: row.fareMin,
      fareMax: row.fareMax,
      fare,
      currency: "PHP",
      routeType: "tricycle",
      createdAt: FieldValue.serverTimestamp(),
      updatedAt: FieldValue.serverTimestamp(),
    };
    for (const direction of ["hub_to_spot", "spot_to_hub"]) {
      fees.push({
        id: `${endpointSlug}__${row.spotSlug}__${direction}`,
        data: { ...base, direction },
      });
    }
  }
  return fees;
}

async function uploadHubSpotTransportFees() {
  const fees = buildFees();
  const col = db.collection("hub_spot_transport_fees");
  const batchSize = 450;
  let uploaded = 0;

  for (let i = 0; i < fees.length; i += batchSize) {
    const chunk = fees.slice(i, i + batchSize);
    const batch = db.batch();
    for (const fee of chunk) {
      batch.set(col.doc(fee.id), fee.data, { merge: true });
    }
    await batch.commit();
    uploaded += chunk.length;
    console.log(`Committed ${uploaded}/${fees.length}`);
  }

  return uploaded;
}

async function main() {
  console.log("Seeding hub_spot_transport_fees...");
  const count = await uploadHubSpotTransportFees();
  console.log(`Done. Uploaded ${count} documents.`);
}

if (require.main === module) {
  main().catch((err) => {
    console.error(err);
    process.exit(1);
  });
}

module.exports = { uploadHubSpotTransportFees, buildFees };

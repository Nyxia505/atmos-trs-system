/**
 * One-time seed: creates Firestore collection `transportation_fees` (272 docs).
 *
 * Run from main/functions (requires Firebase/GCP credentials):
 *   node seed-transportation-fees-once.js
 *
 * Or after deploy, call Cloud Function seedTransportationFees as admin.
 */
const admin = require("firebase-admin");

if (!admin.apps.length) {
  admin.initializeApp({ projectId: "atmos-trs-system" });
}

const db = admin.firestore();
const FieldValue = admin.firestore.FieldValue;

const MATRIX_KEYS = [
  "Aloran",
  "Baliangao",
  "Bonifacio",
  "Calamba",
  "Clarin",
  "Concepcion",
  "Don Victoriano Chiongbian",
  "Jimenez",
  "Lopez Jaena",
  "Oroquieta City",
  "Ozamiz City",
  "Panaon",
  "Plaridel",
  "Sapang Dalaga",
  "Sinacaban",
  "Tangub City",
  "Tudela",
];

const CANONICAL_NAME = {
  "Oroquieta City": "Oroquieta City (Provincial Capital)",
};

const MATRIX = [
  [0, 140, 80, 100, 50, 120, 220, 40, 110, 90, 50, 130, 70, 100, 40, 60, 30],
  [140, 0, 70, 40, 120, 30, 180, 130, 40, 60, 140, 20, 90, 50, 130, 120, 135],
  [80, 70, 0, 40, 60, 80, 150, 70, 60, 50, 90, 75, 40, 70, 85, 70, 75],
  [100, 40, 40, 0, 80, 50, 170, 90, 30, 40, 110, 40, 60, 40, 100, 90, 95],
  [50, 120, 60, 80, 0, 100, 200, 35, 90, 70, 25, 110, 50, 80, 30, 45, 20],
  [120, 30, 80, 50, 100, 0, 190, 110, 35, 50, 120, 25, 80, 45, 115, 100, 110],
  [220, 180, 150, 170, 200, 190, 0, 190, 170, 160, 210, 185, 170, 180, 205, 190, 195],
  [40, 130, 70, 90, 35, 110, 190, 0, 100, 80, 40, 120, 60, 90, 35, 50, 25],
  [110, 40, 60, 30, 90, 35, 170, 100, 0, 30, 100, 35, 70, 30, 95, 85, 90],
  [90, 60, 50, 40, 70, 50, 160, 80, 30, 0, 80, 55, 50, 40, 75, 65, 70],
  [50, 140, 90, 110, 25, 120, 210, 40, 100, 80, 0, 130, 70, 100, 30, 60, 25],
  [130, 20, 75, 40, 110, 25, 185, 120, 35, 55, 130, 0, 85, 40, 120, 110, 120],
  [70, 90, 40, 60, 50, 80, 170, 60, 70, 50, 70, 85, 0, 60, 65, 55, 60],
  [100, 50, 70, 40, 80, 45, 180, 90, 30, 40, 100, 40, 60, 0, 90, 80, 85],
  [40, 130, 85, 100, 30, 115, 205, 35, 95, 75, 30, 120, 65, 90, 0, 40, 20],
  [60, 120, 70, 90, 45, 100, 190, 50, 85, 65, 60, 110, 55, 80, 40, 0, 45],
  [30, 135, 75, 95, 20, 110, 195, 25, 90, 70, 25, 120, 60, 85, 20, 45, 0],
];

/** @type {Record<string, {name: string, lat: number, lng: number, kind: string}>} */
const HUBS = {
  "Oroquieta City (Provincial Capital)": {
    name: "Oroquieta bus terminal",
    lat: 8.493037148800576,
    lng: 123.79814266814685,
    kind: "terminal",
  },
  Plaridel: {
    name: "Plaridel bus terminal",
    lat: 8.620136282529488,
    lng: 123.70950131047762,
    kind: "terminal",
  },
  Aloran: {
    name: "Aloran bus stop",
    lat: 8.412249537859656,
    lng: 123.82317045284562,
    kind: "stop",
  },
  "Lopez Jaena": {
    name: "Lopez Jaena bus stop",
    lat: 8.5525828978222,
    lng: 123.7690860488779,
    kind: "stop",
  },
  Calamba: {
    name: "Calamba and Baliangao bus terminal",
    lat: 8.5598630610656,
    lng: 123.64246380406652,
    kind: "terminal",
  },
  Baliangao: {
    name: "Calamba and Baliangao bus terminal",
    lat: 8.5598630610656,
    lng: 123.64246380406652,
    kind: "terminal",
  },
  Panaon: {
    name: "Panaon bus stop",
    lat: 8.374298443375187,
    lng: 123.84065433688431,
    kind: "stop",
  },
  "Sapang Dalaga": {
    name: "Sapang Dalaga bus stop",
    lat: 8.54532085508384,
    lng: 123.5682212764322,
    kind: "stop",
  },
  Jimenez: {
    name: "Jimenez bus terminal",
    lat: 8.33713480807977,
    lng: 123.84553724513275,
    kind: "terminal",
  },
  Sinacaban: {
    name: "Sinacaban bus terminal",
    lat: 8.28564823872101,
    lng: 123.84346050720977,
    kind: "terminal",
  },
  Tudela: {
    name: "Tudela bus stop",
    lat: 8.240302600302313,
    lng: 123.84643162121777,
    kind: "stop",
  },
  Clarin: {
    name: "Clarin bus terminal",
    lat: 8.195384812228278,
    lng: 123.85786167978975,
    kind: "terminal",
  },
  "Ozamiz City": {
    name: "Ozamiz bus terminal",
    lat: 8.157382755562983,
    lng: 123.83988623746002,
    kind: "terminal",
  },
  "Tangub City": {
    name: "Tangub bus terminal",
    lat: 8.073984530739589,
    lng: 123.75062495439016,
    kind: "terminal",
  },
};

const CENTERS = {
  Bonifacio: { lat: 8.4667, lng: 123.7667, short: "Bonifacio" },
  Concepcion: { lat: 8.3333, lng: 123.6167, short: "Concepcion" },
  "Don Victoriano Chiongbian": {
    lat: 8.3167,
    lng: 123.7833,
    short: "Don V. Chiongbian",
  },
};

function slug(name) {
  return name
    .toLowerCase()
    .trim()
    .replace(/[^a-z0-9\s]/g, "")
    .replace(/\s+/g, "_");
}

function canonical(matrixKey) {
  return CANONICAL_NAME[matrixKey] || matrixKey;
}

function haversineKm(lat1, lon1, lat2, lon2) {
  const R = 6371;
  const dLat = ((lat2 - lat1) * Math.PI) / 180;
  const dLon = ((lon2 - lon1) * Math.PI) / 180;
  const a =
    Math.sin(dLat / 2) ** 2 +
    Math.cos((lat1 * Math.PI) / 180) *
      Math.cos((lat2 * Math.PI) / 180) *
      Math.sin(dLon / 2) ** 2;
  return R * 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
}

function routeType(km) {
  if (km >= 55) return "provincial";
  if (km >= 28) return "bus";
  return "jeepney";
}

function hubFor(canonicalName) {
  if (HUBS[canonicalName]) return HUBS[canonicalName];

  const center = CENTERS[canonicalName];
  if (!center) {
    return {
      name: `${canonicalName} bus stop`,
      lat: 8.45,
      lng: 123.75,
      kind: "stop",
    };
  }

  let best = null;
  let bestKm = Infinity;
  for (const h of Object.values(HUBS)) {
    const km = haversineKm(center.lat, center.lng, h.lat, h.lng);
    if (km < bestKm) {
      bestKm = km;
      best = h;
    }
  }
  return {
    name: `${center.short} bus stop (nearest: ${best?.name || "hub"})`,
    lat: center.lat,
    lng: center.lng,
    kind: "stop",
  };
}

function buildFees() {
  const fees = [];
  for (let fromIdx = 0; fromIdx < MATRIX_KEYS.length; fromIdx++) {
    for (let toIdx = 0; toIdx < MATRIX_KEYS.length; toIdx++) {
      if (fromIdx === toIdx) continue;

      const fromKey = MATRIX_KEYS[fromIdx];
      const toKey = MATRIX_KEYS[toIdx];
      const fromName = canonical(fromKey);
      const toName = canonical(toKey);
      const fare = MATRIX[fromIdx][toIdx];

      const fromHub = hubFor(fromName);
      const toHub = hubFor(toName);
      const straightKm = haversineKm(
        fromHub.lat,
        fromHub.lng,
        toHub.lat,
        toHub.lng,
      );
      const estimatedKm = Math.round(straightKm * 1.25 * 10) / 10;

      const id = `${slug(fromName)}__${slug(toName)}`;
      fees.push({
        id,
        data: {
          fromMunicipality: fromName,
          toMunicipality: toName,
          fromMunicipalitySlug: slug(fromName),
          toMunicipalitySlug: slug(toName),
          fare,
          currency: "PHP",
          endpointType: toHub.kind,
          endpointName: toHub.name,
          routeType: routeType(estimatedKm),
          estimatedDistance: estimatedKm,
          createdAt: FieldValue.serverTimestamp(),
          updatedAt: FieldValue.serverTimestamp(),
        },
      });
    }
  }
  return fees;
}

async function uploadTransportationFees() {
  const fees = buildFees();
  const col = db.collection("transportation_fees");
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
  console.log("Seeding transportation_fees to atmos-trs-system...");
  const count = await uploadTransportationFees();
  console.log(`Done. Uploaded ${count} documents to transportation_fees.`);
}

if (require.main === module) {
  main().catch((err) => {
    console.error(err);
    process.exit(1);
  });
}

module.exports = { uploadTransportationFees, buildFees };

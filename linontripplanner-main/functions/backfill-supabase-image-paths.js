/**
 * Writes the Supabase Storage URL of each municipality / tourist-spot photo into
 * that record's Firestore `imagePath`.
 *
 * The app matches records to photos by name at runtime, which needs permission
 * to list the public buckets. Where that permission is not granted, this script
 * does the same matching offline with the service key and stores the resulting
 * URL, so the app only ever has to follow a link.
 *
 * Re-run it after adding or renaming photos in Supabase.
 *
 * Requires:
 *   SUPABASE_SERVICE_KEY   service_role key (server-side only, never shipped)
 *   Google credentials     `gcloud auth application-default login`
 *                          or GOOGLE_APPLICATION_CREDENTIALS
 *
 * Usage:
 *   node backfill-supabase-image-paths.js              # report only
 *   node backfill-supabase-image-paths.js --apply      # write to Firestore
 *   node backfill-supabase-image-paths.js --apply --overwrite
 */

const admin = require("firebase-admin");

const SUPABASE_URL = "https://cgpjqkbbmyxvitwpkikn.supabase.co";
const UPLOAD_BUCKET = "tourism-images";
const LIBRARY_BUCKET = "tourist-images";

const SERVICE_KEY = process.env.SUPABASE_SERVICE_KEY || "";
const APPLY = process.argv.includes("--apply");
const OVERWRITE = process.argv.includes("--overwrite");

const IMAGE_EXTENSIONS = new Set([
  "jpg", "jpeg", "png", "webp", "gif", "bmp", "heic",
]);

// Folders scanned when resolving a photo by name, mirroring the app's index.
const INDEX_ROOTS = [
  { bucket: UPLOAD_BUCKET, prefix: "municipalities", scope: "municipality", depth: 2 },
  { bucket: UPLOAD_BUCKET, prefix: "tourist-spots", scope: "touristSpot", depth: 2 },
  { bucket: LIBRARY_BUCKET, prefix: "", scope: "any", depth: 3 },
];

// ---------------------------------------------------------------------------
// Supabase Storage
// ---------------------------------------------------------------------------

function publicObjectUrl(bucket, objectPath) {
  const segments = objectPath
    .split("/")
    .filter(Boolean)
    .map(encodeURIComponent)
    .join("/");
  return `${SUPABASE_URL}/storage/v1/object/public/${bucket}/${segments}`;
}

async function listFolder(bucket, prefix) {
  const res = await fetch(`${SUPABASE_URL}/storage/v1/object/list/${bucket}`, {
    method: "POST",
    headers: {
      apikey: SERVICE_KEY,
      Authorization: `Bearer ${SERVICE_KEY}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify({
      prefix,
      limit: 1000,
      offset: 0,
      sortBy: { column: "name", order: "asc" },
    }),
  });
  if (!res.ok) {
    throw new Error(`list ${bucket}/${prefix} failed (${res.status}): ${await res.text()}`);
  }
  const rows = await res.json();
  return Array.isArray(rows) ? rows : [];
}

async function listTree(bucket, prefix, scope, depth) {
  const out = [];
  const subfolders = [];

  for (const row of await listFolder(bucket, prefix)) {
    const name = (row.name || "").trim();
    if (!name || name === ".emptyFolderPlaceholder") continue;
    const path = prefix ? `${prefix}/${name}` : name;
    // Supabase returns a null id for synthetic folder rows.
    if (row.id === null || row.id === undefined) {
      subfolders.push(path);
      continue;
    }
    if (!looksLikeImage(name)) continue;
    const folder = lastSegment(prefix);
    const base = stripExtension(name);
    const fileTokens = nameTokens(base);
    out.push({
      bucket,
      path,
      scope,
      folderKey: normalizeKey(folder),
      fileKey: normalizeKey(base),
      // Admin uploads are named by timestamp, so fall back to the folder.
      tokens: fileTokens.length ? fileTokens : nameTokens(folder),
    });
  }

  if (depth > 0 && subfolders.length) {
    const nested = await Promise.all(
      subfolders.map((p) => listTree(bucket, p, scope, depth - 1)),
    );
    for (const batch of nested) out.push(...batch);
  }
  return out;
}

async function buildIndex() {
  const batches = await Promise.all(
    INDEX_ROOTS.map((r) =>
      listTree(r.bucket, r.prefix, r.scope, r.depth).catch((e) => {
        console.warn(`  ! ${e.message}`);
        return [];
      }),
    ),
  );
  return batches.flat();
}

function looksLikeImage(fileName) {
  const dot = fileName.lastIndexOf(".");
  if (dot < 0 || dot === fileName.length - 1) return false;
  return IMAGE_EXTENSIONS.has(fileName.slice(dot + 1).toLowerCase());
}

function stripExtension(fileName) {
  const dot = fileName.lastIndexOf(".");
  return dot <= 0 ? fileName : fileName.slice(0, dot);
}

function lastSegment(path) {
  if (!path) return "";
  const i = path.lastIndexOf("/");
  return i < 0 ? path : path.slice(i + 1);
}

// ---------------------------------------------------------------------------
// Name matching — kept in step with lib/services/supabase_image_library.dart
// ---------------------------------------------------------------------------

/** Comparison key: lowercase alphanumerics only, `&` spelled out. */
function normalizeKey(s) {
  let t = (s || "").toLowerCase().trim();
  if (!t) return "";
  t = t.replace(/&/g, " and ");
  return t.replace(/[^a-z0-9]+/g, "");
}

/** Words too common in this catalog to identify a subject on their own. */
const STOP_WORDS = new Set([
  "the", "and", "for", "with", "city", "misamis", "occidental", "nearby",
  "image", "images", "photo", "new", "old",
]);

/** Significant lowercase words in a name, de-pluralized. */
function nameTokens(s) {
  const out = [];
  for (let t of (s || "").toLowerCase().replace(/&/g, " and ").split(/[^a-z0-9]+/)) {
    if (t.length < 3 || STOP_WORDS.has(t)) continue;
    if (t.length > 4 && t.endsWith("s") && !t.endsWith("ss")) t = t.slice(0, -1);
    if (!out.includes(t)) out.push(t);
  }
  return out;
}

/** Names to try for a record, best first. */
function nameVariants(names) {
  const out = [];
  const add = (s) => {
    const t = (s || "").replace(/\s+/g, " ").trim();
    if (!t) return;
    if (out.some((o) => o.toLowerCase() === t.toLowerCase())) return;
    out.push(t);
  };
  names.forEach(add);
  [...out].forEach((n) => add(n.replace(/\s*\([^)]*\)/g, "")));
  [...out].forEach((n) => add(n.split(/\s[\u2013\u2014-]\s/)[0]));
  [...out].forEach((n) => add(n.replace(/\s+city$/i, "")));
  return out;
}

/** Levenshtein distance capped at `max`. */
function editDistanceWithin(a, b, max) {
  if (a === b) return true;
  if (Math.abs(a.length - b.length) > max) return false;
  let prev = Array.from({ length: b.length + 1 }, (_, i) => i);
  let curr = new Array(b.length + 1).fill(0);
  for (let i = 1; i <= a.length; i++) {
    curr[0] = i;
    let rowMin = curr[0];
    for (let j = 1; j <= b.length; j++) {
      const cost = a.charCodeAt(i - 1) === b.charCodeAt(j - 1) ? 0 : 1;
      curr[j] = Math.min(curr[j - 1] + 1, prev[j] + 1, prev[j - 1] + cost);
      if (curr[j] < rowMin) rowMin = curr[j];
    }
    if (rowMin > max) return false;
    [prev, curr] = [curr, prev];
  }
  return prev[b.length] <= max;
}

/** Two shared significant words required, so a lone generic word never matches. */
function tokenOverlapScore(fileTokens, wantTokens) {
  if (fileTokens.length < 2 || wantTokens.length < 2) return 0;
  let shared = 0;
  for (const t of fileTokens) if (wantTokens.includes(t)) shared++;
  if (shared < 2) return 0;
  const coverage = Math.max(shared / fileTokens.length, shared / wantTokens.length);
  if (coverage < 0.6) return 0;
  return 400 + shared * 10 + Math.round(coverage * 100);
}

/** 0 = no usable match. Exact beats prefix beats near-spelling beats overlap. */
function scoreKey(entry, want, wantTokens) {
  if (want.length < 3) return 0;
  if (entry.folderKey === want) return 1000;
  if (entry.fileKey === want) return 900;
  if (want.length >= 5 && entry.fileKey.startsWith(want)) return 700 + want.length;
  if (want.length >= 6 && entry.fileKey.includes(want)) return 500 + want.length;
  const tolerance = want.length >= 10 ? 2 : 1;
  if (
    want.length >= 6 &&
    Math.abs(entry.fileKey.length - want.length) <= tolerance &&
    editDistanceWithin(entry.fileKey, want, tolerance)
  ) {
    return 600;
  }
  return tokenOverlapScore(entry.tokens, wantTokens);
}

function bestMatch(index, names, scope) {
  const candidates = nameVariants(names);
  if (!candidates.length) return null;
  const keys = candidates.map(normalizeKey);
  const tokenSets = candidates.map(nameTokens);

  let best = null;
  let bestScore = 0;
  for (const entry of index) {
    if (entry.scope !== "any" && entry.scope !== scope) continue;
    let score = 0;
    for (let i = 0; i < keys.length; i++) {
      // Later variants are weaker signals.
      const raw = scoreKey(entry, keys[i], tokenSets[i]);
      if (raw > 0 && raw - i * 20 > score) score = raw - i * 20;
    }
    if (score > bestScore) {
      bestScore = score;
      best = entry;
    }
  }
  return best;
}

// ---------------------------------------------------------------------------

async function urlServesImage(url) {
  try {
    const res = await fetch(url, { method: "HEAD" });
    return res.ok && (res.headers.get("content-type") || "").startsWith("image/");
  } catch {
    return false;
  }
}

async function planCollection(db, collection, index, scope, namesOf) {
  const snapshot = await db.collection(collection).get();
  const rows = [];
  for (const doc of snapshot.docs) {
    const data = doc.data();
    const existing = (data.imagePath || data.image_path || "").trim();
    const match = bestMatch(index, namesOf(data, doc.id), scope);
    rows.push({
      id: doc.id,
      label: (data.name || doc.id).trim(),
      existing,
      match,
      url: match ? publicObjectUrl(match.bucket, match.path) : null,
    });
  }
  rows.sort((a, b) => a.label.localeCompare(b.label));
  return rows;
}

async function main() {
  if (!SERVICE_KEY) {
    console.error("SUPABASE_SERVICE_KEY is not set.");
    process.exit(1);
  }

  console.log("Indexing Supabase buckets…");
  const index = await buildIndex();
  console.log(`  ${index.length} images found\n`);
  if (!index.length) {
    console.error("No images indexed — check the service key.");
    process.exit(1);
  }

  if (!admin.apps.length) admin.initializeApp({ projectId: "atmos-trs-system" });
  const db = admin.firestore();

  const groups = [
    {
      collection: "municipalities",
      scope: "municipality",
      namesOf: (d, id) => [d.name || id, d.shortName || ""],
    },
    {
      collection: "tourist_spots",
      scope: "touristSpot",
      namesOf: (d, id) => [d.name || id],
    },
  ];

  let written = 0;
  let skipped = 0;
  let unmatched = 0;

  for (const g of groups) {
    const rows = await planCollection(db, g.collection, index, g.scope, g.namesOf);
    console.log(`=== ${g.collection} (${rows.length}) ===`);

    const batch = db.batch();
    let queued = 0;

    for (const row of rows) {
      const keepExisting = row.existing && !OVERWRITE;
      if (keepExisting) {
        skipped++;
        console.log(`  = ${row.label.padEnd(44)} keeps existing imagePath`);
        continue;
      }
      if (!row.match) {
        unmatched++;
        console.log(`  · ${row.label.padEnd(44)} no photo in Supabase → placeholder`);
        continue;
      }
      if (!(await urlServesImage(row.url))) {
        unmatched++;
        console.log(`  ! ${row.label.padEnd(44)} URL did not serve an image, skipped`);
        continue;
      }
      console.log(`  → ${row.label.padEnd(44)} ${row.match.bucket}/${row.match.path}`);
      if (APPLY) {
        batch.set(
          db.collection(g.collection).doc(row.id),
          {
            imagePath: row.url,
            updatedAt: admin.firestore.FieldValue.serverTimestamp(),
          },
          { merge: true },
        );
        queued++;
      }
      written++;
    }

    if (APPLY && queued) await batch.commit();
    console.log("");
  }

  console.log(
    APPLY
      ? `Wrote ${written} imagePath values. ${skipped} kept, ${unmatched} left for the placeholder.`
      : `Would write ${written}. ${skipped} kept, ${unmatched} left for the placeholder.\nRe-run with --apply to save.`,
  );
  process.exit(0);
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});

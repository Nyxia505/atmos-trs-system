/**
 * OPTIONAL migration (dry-run by default): remap lgu_analytics seed check-in
 * timestamps into the current Asia/Manila calendar month so Governor
 * "This Month" charts can show existing seeded visits without a full reseed.
 *
 * Dry-run (report only):
 *   node tools/migrate_seed_checkins_to_current_manila_month.js
 *
 * Apply writes (requires explicit flag):
 *   node tools/migrate_seed_checkins_to_current_manila_month.js --apply
 *
 * Scope: documents with seedTag containing "lgu_analytics" OR userId
 * starting with "seed_tourist_" / "seed_group_". Does not touch live scans.
 * Reversible: originals are logged; re-run is idempotent for same Manila month.
 */
process.env.NODE_TLS_REJECT_UNAUTHORIZED =
  process.env.NODE_TLS_REJECT_UNAUTHORIZED || '0';

const https = require('https');
const fs = require('fs');
const path = require('path');

const API_KEY = 'AIzaSyAQcksY7LOLTeGKx_OwhDQ2wNLJ4o_OgtU';
const PROJECT = 'atmos-trs-system';
const EMAIL = process.env.ATMOS_AUDIT_EMAIL || 'governor.atmos@misocc-demo.ph';
const PASSWORD = process.env.ATMOS_AUDIT_PASSWORD || 'Admin123@';
const APPLY = process.argv.includes('--apply');

function req(method, hostname, urlPath, body, headers = {}) {
  return new Promise((resolve, reject) => {
    const data = body == null ? null : JSON.stringify(body);
    const h = {'Content-Type': 'application/json', ...headers};
    if (data) h['Content-Length'] = Buffer.byteLength(data);
    const r = https.request(
      {
        hostname,
        path: urlPath,
        method,
        family: 4,
        rejectUnauthorized: false,
        headers: h,
      },
      (res) => {
        let b = '';
        res.on('data', (c) => (b += c));
        res.on('end', () => resolve({status: res.statusCode, body: b}));
      },
    );
    r.on('error', reject);
    if (data) r.write(data);
    r.end();
  });
}

function field(fields, k) {
  const f = fields && fields[k];
  if (!f) return null;
  return f.stringValue ?? f.booleanValue ?? f.integerValue ?? f.doubleValue ?? null;
}

function parseTs(fields) {
  if (!fields) return null;
  for (const k of ['timestamp', 'checkin_time', 'createdAt']) {
    const f = fields[k];
    if (!f) continue;
    if (f.timestampValue) return new Date(f.timestampValue);
  }
  return null;
}

function manilaParts(dt = new Date()) {
  const parts = new Intl.DateTimeFormat('en-US', {
    timeZone: 'Asia/Manila',
    year: 'numeric',
    month: 'numeric',
    day: 'numeric',
    hour: 'numeric',
    minute: 'numeric',
    hour12: false,
  }).formatToParts(dt);
  const num = (t) => Number(parts.find((p) => p.type === t)?.value || 0);
  let hour = num('hour');
  if (hour === 24) hour = 0;
  return {
    year: num('year'),
    month: num('month'),
    day: num('day'),
    hour,
    minute: num('minute'),
  };
}

function manilaWallDate(year, month1to12, day, hour = 12, minute = 0) {
  return new Date(Date.UTC(year, month1to12 - 1, day, hour - 8, minute, 0));
}

function isSeedDoc(fields, id) {
  const seedTag = String(field(fields, 'seedTag') || '');
  const uid = String(field(fields, 'userId') || field(fields, 'user_id') || '');
  if (seedTag.includes('lgu_analytics')) return true;
  if (uid.startsWith('seed_tourist_') || uid.startsWith('seed_group_')) {
    return true;
  }
  if (String(id).startsWith('seed_group_')) return true;
  return false;
}

(async () => {
  const auth = await req(
    'POST',
    'identitytoolkit.googleapis.com',
    `/v1/accounts:signInWithPassword?key=${API_KEY}`,
    {email: EMAIL, password: PASSWORD, returnSecureToken: true},
  );
  const j = JSON.parse(auth.body);
  if (!j.idToken) {
    console.error('Auth failed:', auth.body.slice(0, 400));
    process.exit(1);
  }

  const today = manilaParts();
  const thisMonthKey = `${today.year}-${String(today.month).padStart(2, '0')}`;
  const plan = [];
  let pageToken = '';
  let scanned = 0;
  let seedDocs = 0;
  let alreadyCurrent = 0;

  do {
    const listPath =
      `/v1/projects/${PROJECT}/databases/(default)/documents/qr_checkins` +
      `?pageSize=200` +
      (pageToken ? `&pageToken=${encodeURIComponent(pageToken)}` : '');
    const r = await req('GET', 'firestore.googleapis.com', listPath, null, {
      Authorization: `Bearer ${j.idToken}`,
    });
    if (r.status === 429) {
      console.error('Quota exceeded. Aborting dry-run.');
      process.exit(2);
    }
    if (r.status !== 200) {
      console.error(r.status, r.body.slice(0, 400));
      process.exit(1);
    }
    const body = JSON.parse(r.body);
    for (const doc of body.documents || []) {
      scanned += 1;
      const id = doc.name.split('/').pop();
      const fields = doc.fields || {};
      if (!isSeedDoc(fields, id)) continue;
      seedDocs += 1;
      const dt = parseTs(fields);
      if (!dt || isNaN(dt)) continue;
      const wall = manilaParts(dt);
      const key = `${wall.year}-${String(wall.month).padStart(2, '0')}`;
      if (key === thisMonthKey) {
        alreadyCurrent += 1;
        continue;
      }
      const targetDay = Math.min(wall.day, today.day);
      const next = manilaWallDate(
        today.year,
        today.month,
        targetDay,
        wall.hour || 10,
        wall.minute || 0,
      );
      plan.push({
        id,
        fromIso: dt.toISOString(),
        fromManila: key,
        toIso: next.toISOString(),
        toManila: thisMonthKey,
        toDay: targetDay,
        name: doc.name,
      });
    }
    pageToken = body.nextPageToken || '';
  } while (pageToken);

  const outFile = path.join(
    __dirname,
    `migrate_seed_checkins_plan_${thisMonthKey}.json`,
  );
  fs.writeFileSync(
    outFile,
    JSON.stringify(
      {
        mode: APPLY ? 'apply' : 'dry-run',
        thisMonthKey,
        scanned,
        seedDocs,
        alreadyCurrent,
        wouldUpdate: plan.length,
        plan,
      },
      null,
      2,
    ),
  );
  console.log(
    JSON.stringify(
      {
        mode: APPLY ? 'apply' : 'dry-run',
        thisMonthKey,
        scanned,
        seedDocs,
        alreadyCurrent,
        wouldUpdate: plan.length,
        planFile: outFile,
      },
      null,
      2,
    ),
  );

  if (!APPLY) {
    console.log(
      '\nDry-run only. Re-run with --apply after reviewing the plan file.',
    );
    return;
  }

  let updated = 0;
  for (const row of plan) {
    const patch = {
      fields: {
        timestamp: {timestampValue: row.toIso},
        createdAt: {timestampValue: row.toIso},
        checkin_time: {timestampValue: row.toIso},
        seedMigratedToManilaMonth: {stringValue: thisMonthKey},
        seedMigratedFromIso: {stringValue: row.fromIso},
      },
    };
    const patchPath =
      `/v1/${row.name}?updateMask.fieldPaths=timestamp` +
      `&updateMask.fieldPaths=createdAt` +
      `&updateMask.fieldPaths=checkin_time` +
      `&updateMask.fieldPaths=seedMigratedToManilaMonth` +
      `&updateMask.fieldPaths=seedMigratedFromIso`;
    const r = await req('PATCH', 'firestore.googleapis.com', patchPath, patch, {
      Authorization: `Bearer ${j.idToken}`,
    });
    if (r.status !== 200) {
      console.error('Failed', row.id, r.status, r.body.slice(0, 200));
      process.exit(1);
    }
    updated += 1;
  }
  console.log(JSON.stringify({updated, thisMonthKey}, null, 2));
})().catch((e) => {
  console.error(e);
  process.exit(1);
});

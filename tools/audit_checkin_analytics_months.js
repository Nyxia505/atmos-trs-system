/**
 * Dry-run audit: qr_checkins month distribution vs Governor analytics filters.
 *
 * Usage (from repo root):
 *   node tools/audit_checkin_analytics_months.js
 *
 * Does NOT write. Signs in as demo governor. Uses Asia/Manila wall months.
 *
 * If Firestore returns 429 RESOURCE_EXHAUSTED, wait and retry — free-tier quota.
 */
process.env.NODE_TLS_REJECT_UNAUTHORIZED =
  process.env.NODE_TLS_REJECT_UNAUTHORIZED || '0';

const https = require('https');

const API_KEY = 'AIzaSyAQcksY7LOLTeGKx_OwhDQ2wNLJ4o_OgtU';
const PROJECT = 'atmos-trs-system';
const EMAIL = process.env.ATMOS_AUDIT_EMAIL || 'governor.atmos@misocc-demo.ph';
const PASSWORD = process.env.ATMOS_AUDIT_PASSWORD || 'Admin123@';

function req(method, hostname, path, body, headers = {}) {
  return new Promise((resolve, reject) => {
    const data = body == null ? null : JSON.stringify(body);
    const h = {'Content-Type': 'application/json', ...headers};
    if (data) h['Content-Length'] = Buffer.byteLength(data);
    const r = https.request(
      {
        hostname,
        path,
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
  for (const k of [
    'timestamp',
    'checkin_time',
    'checkedInAt',
    'createdAt',
    'visitDate',
  ]) {
    const f = fields[k];
    if (!f) continue;
    if (f.timestampValue) return new Date(f.timestampValue);
    if (f.stringValue) {
      const d = new Date(f.stringValue);
      if (!isNaN(d)) return d;
    }
  }
  return null;
}

function manilaKey(dt) {
  const manila = new Date(dt.getTime() + 8 * 3600 * 1000);
  return (
    manila.getUTCFullYear() +
    '-' +
    String(manila.getUTCMonth() + 1).padStart(2, '0')
  );
}

function manilaNowParts() {
  const parts = new Intl.DateTimeFormat('en-US', {
    timeZone: 'Asia/Manila',
    year: 'numeric',
    month: 'numeric',
    day: 'numeric',
  }).formatToParts(new Date());
  const num = (t) => Number(parts.find((p) => p.type === t)?.value || 0);
  return {year: num('year'), month: num('month'), day: num('day')};
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

  const manila = manilaNowParts();
  const thisMonthKey = `${manila.year}-${String(manila.month).padStart(2, '0')}`;

  let pageToken = '';
  let total = 0;
  let parsed = 0;
  let unparsed = 0;
  let seed = 0;
  let missingMun = 0;
  let missingSex = 0;
  let missingLocal = 0;
  let partyVisitors = 0;
  let thisMonthDocs = 0;
  let thisMonthVisitors = 0;
  const months = {};
  const samples = [];
  let pages = 0;

  do {
    const path =
      `/v1/projects/${PROJECT}/databases/(default)/documents/qr_checkins` +
      `?pageSize=200` +
      (pageToken ? `&pageToken=${encodeURIComponent(pageToken)}` : '');
    const r = await req('GET', 'firestore.googleapis.com', path, null, {
      Authorization: `Bearer ${j.idToken}`,
    });
    if (r.status === 429) {
      console.error('Quota exceeded (429). Retry later.');
      process.exit(2);
    }
    if (r.status !== 200) {
      console.error('List failed', r.status, r.body.slice(0, 500));
      process.exit(1);
    }
    const body = JSON.parse(r.body);
    const docs = body.documents || [];
    pages += 1;
    for (const doc of docs) {
      total += 1;
      const fields = doc.fields || {};
      const uid = field(fields, 'userId') || field(fields, 'user_id') || '';
      const seedTag = field(fields, 'seedTag') || '';
      if (
        String(seedTag).includes('lgu_analytics') ||
        String(uid).startsWith('seed_tourist_')
      ) {
        seed += 1;
      }
      const visitors =
        Number(field(fields, 'visitorCount') || field(fields, 'partySize') || 1) ||
        1;
      partyVisitors += visitors;
      if (!field(fields, 'touristSex')) missingSex += 1;
      if (
        field(fields, 'touristIsLocal') == null &&
        !field(fields, 'touristLocalOrForeign')
      ) {
        missingLocal += 1;
      }
      if (
        !(field(fields, 'municipalityId') || field(fields, 'municipality') || '')
          .toString()
          .trim()
      ) {
        missingMun += 1;
      }
      const dt = parseTs(fields);
      if (!dt || isNaN(dt)) {
        unparsed += 1;
        continue;
      }
      parsed += 1;
      const key = manilaKey(dt);
      months[key] = (months[key] || 0) + 1;
      if (key === thisMonthKey) {
        thisMonthDocs += 1;
        thisMonthVisitors += visitors;
      }
      if (samples.length < 12) {
        samples.push({
          id: doc.name.split('/').pop(),
          manilaMonth: key,
          iso: dt.toISOString(),
          visitors,
          seedTag,
          sex: field(fields, 'touristSex'),
        });
      }
    }
    pageToken = body.nextPageToken || '';
    if (pages > 100) break;
  } while (pageToken);

  console.log(
    JSON.stringify(
      {
        manilaToday: manila,
        thisMonthKey,
        pages,
        totalDocs: total,
        parsedTimestamps: parsed,
        unparsedTimestamps: unparsed,
        seedTaggedApprox: seed,
        partyVisitorsAllTime: partyVisitors,
        thisMonthDocs,
        thisMonthVisitors,
        missingMunicipality: missingMun,
        missingTouristSexOnDoc: missingSex,
        missingLocalFlagsOnDoc: missingLocal,
        monthsManila: months,
        samples,
        note:
          thisMonthDocs === 0 && total > 0
            ? 'Cards can show all-time visitors while This Month charts are empty — seed timestamps fall outside the Manila current month.'
            : 'This Month has eligible check-ins for Governor charts.',
      },
      null,
      2,
    ),
  );
})().catch((e) => {
  console.error(e);
  process.exit(1);
});

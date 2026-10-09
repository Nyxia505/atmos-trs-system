/**
 * Resets Firestore before a live test: wipes all tourist activity, seeded /
 * debug data, reports and tourist login accounts. Keeps staff (LGU, OPTACA,
 * Governor) and establishment accounts, real tourist spots and config.
 *
 * Usage (from repo root; firebase-admin is loaded from functions/node_modules).
 * Credentials: GOOGLE_APPLICATION_CREDENTIALS service-account key if set,
 * otherwise the local `firebase login` session.
 *   node tools/reset_firestore_for_live_test.js            # dry run (counts only)
 *   node tools/reset_firestore_for_live_test.js --apply    # delete
 *
 * Flags:
 *   --apply                Actually delete (default is a dry run).
 *   --keep-auth            Do not delete tourist Firebase Auth accounts.
 *   --delete-orphan-auth   Also delete Auth accounts that have no users/ or
 *                          tourists/ doc (failed / half-finished signups).
 *   --wipe-campaigns       Also wipe provincial_campaigns.
 *   --verbose              List kept accounts and orphan Auth accounts.
 *
 * Collections not listed below are reported as UNKNOWN and kept.
 */

const {initAdmin, PROJECT_ID} = require('./lib/admin_cli_credential');

const args = new Set(process.argv.slice(2));
const apply = args.has('--apply');
const keepAuth = args.has('--keep-auth');
const deleteOrphanAuth = args.has('--delete-orphan-auth');
const wipeCampaigns = args.has('--wipe-campaigns');
const verbose = args.has('--verbose');

const WIPE = new Set([
  'tourists',
  'qr_checkins',
  'checkins',
  'check_ins',
  'tourist_activity',
  'tourist_groups',
  'tourist_qr_codes',
  'spot_reviews',
  'spot_ratings',
  'notifications',
  'announcements',
  'lgu_report_submissions',
  'ae_monthly_reports',
  'mice_monthly_reports',
  'signoffs',
  'establishment_stay_requests',
  'establishment_stay_reviews',
  'email_otps',
  'password_reset_otps',
]);
if (wipeCampaigns) WIPE.add('provincial_campaigns');

const PARTIAL = new Set(['users', 'usernames', 'tourist_spots']);

const KEEP = new Set([
  'accommodation_establishments',
  'vr_tours',
  'mice_venue_settings',
  'signoff_signers',
]);
if (!wipeCampaigns) KEEP.add('provincial_campaigns');

const STAFF_ROLES = new Set([
  'governor',
  'tourism',
  'tourism_office',
  'provincial',
  'provincial_tourism',
  'provincialtourism',
  'tourism_province',
  'tourism_establishment',
  'establishment',
  'admin',
]);

const SEED_ID_PREFIXES = ['seed_', 'dummy_tourist_', 'demo_analytics_'];
const SEED_EMAIL_DOMAINS = [
  '@misocc-seed.ph',
  '@dummy-tourist.test',
  '@misocc-demo-analytics.ph',
];

function str(v) {
  return (v === undefined || v === null ? '' : String(v)).trim();
}

function hasSeedMarker(data) {
  const source = str(data.source).toLowerCase();
  return (
    str(data.seedTag) !== '' ||
    data.demoAnalytics === true ||
    source.includes('seed')
  );
}

function isStaffOrEstablishment(data) {
  return STAFF_ROLES.has(str(data.role).toLowerCase());
}

function isTouristUser(id, data) {
  if (isStaffOrEstablishment(data)) return false;
  if (str(data.role).toLowerCase() === 'tourist') return true;
  if (SEED_ID_PREFIXES.some((p) => id.startsWith(p))) return true;
  const email = str(data.email).toLowerCase();
  if (SEED_EMAIL_DOMAINS.some((d) => email.includes(d))) return true;
  return hasSeedMarker(data);
}

function isSeededSpot(id, data) {
  return id.endsWith('_visitor_hub') || hasSeedMarker(data);
}

async function countCollection(ref) {
  const agg = await ref.count().get();
  return agg.data().count;
}

async function main() {
  const admin = initAdmin();
  const db = admin.firestore();
  const auth = admin.auth();

  console.log(`Project: ${PROJECT_ID}`);
  console.log(apply ? 'APPLY mode — deleting data\n' : 'DRY RUN — nothing is deleted\n');

  const collections = await db.listCollections();
  collections.sort((a, b) => a.id.localeCompare(b.id));

  const plan = [];
  for (const col of collections) {
    const label = WIPE.has(col.id)
      ? 'WIPE'
      : PARTIAL.has(col.id)
        ? 'PARTIAL'
        : KEEP.has(col.id)
          ? 'KEEP'
          : 'UNKNOWN';
    plan.push({col, label, total: await countCollection(col)});
  }

  // users: tourist / seed docs go, staff + establishments stay.
  const usersSnap = await db.collection('users').get();
  const staffUids = new Set();
  const touristUids = new Set();
  const userDocsToDelete = [];
  for (const doc of usersSnap.docs) {
    const data = doc.data() || {};
    if (isTouristUser(doc.id, data)) {
      touristUids.add(doc.id);
      userDocsToDelete.push(doc.ref);
    } else {
      staffUids.add(doc.id);
    }
  }

  // Every tourists/ doc id is a tourist uid (never a staff uid).
  const touristsSnap = await db.collection('tourists').select().get();
  for (const doc of touristsSnap.docs) {
    if (!staffUids.has(doc.id)) touristUids.add(doc.id);
  }

  // usernames pointing at a tourist uid.
  const usernamesSnap = await db.collection('usernames').get();
  const usernameDocsToDelete = usernamesSnap.docs
    .filter((d) => touristUids.has(str((d.data() || {}).uid)))
    .map((d) => d.ref);

  // Seeded spots only.
  const spotsSnap = await db.collection('tourist_spots').get();
  const spotDocsToDelete = spotsSnap.docs
    .filter((d) => isSeededSpot(d.id, d.data() || {}))
    .map((d) => d.ref);

  const partialCounts = {
    users: userDocsToDelete.length,
    usernames: usernameDocsToDelete.length,
    tourist_spots: spotDocsToDelete.length,
  };

  // Auth accounts.
  const authToDelete = [];
  const orphanEmails = [];
  let orphanAuth = 0;
  let pageToken;
  do {
    const page = await auth.listUsers(1000, pageToken);
    for (const u of page.users) {
      if (staffUids.has(u.uid)) continue;
      if (touristUids.has(u.uid)) {
        authToDelete.push(u.uid);
      } else {
        orphanAuth += 1;
        orphanEmails.push(u.email || u.phoneNumber || u.uid);
        if (deleteOrphanAuth) authToDelete.push(u.uid);
      }
    }
    pageToken = page.pageToken;
  } while (pageToken);

  console.log('Collection                        Label     Docs   To delete');
  console.log('--------------------------------  -------  -----   ---------');
  for (const {col, label, total} of plan) {
    const toDelete =
      label === 'WIPE' ? total : label === 'PARTIAL' ? partialCounts[col.id] || 0 : 0;
    console.log(
      `${col.id.padEnd(32)}  ${label.padEnd(7)}  ${String(total).padStart(5)}   ${String(toDelete).padStart(9)}`,
    );
  }
  console.log('');
  console.log(`Staff / establishment accounts kept: ${staffUids.size}`);
  console.log(
    `Auth accounts to delete: ${keepAuth ? 0 : authToDelete.length}` +
    (keepAuth ? ' (--keep-auth)' : ''),
  );
  console.log(
    `Orphan Auth accounts (no users/ or tourists/ doc): ${orphanAuth}` +
    (deleteOrphanAuth ? ' — included above' : ' — kept (use --delete-orphan-auth)'),
  );
  const unknown = plan.filter((p) => p.label === 'UNKNOWN').map((p) => p.col.id);
  if (unknown.length) console.log(`UNKNOWN collections kept: ${unknown.join(', ')}`);

  if (verbose) {
    console.log('\nKept accounts (users/):');
    for (const doc of usersSnap.docs) {
      if (!staffUids.has(doc.id)) continue;
      const d = doc.data() || {};
      const role = str(d.role);
      console.log(
        `  ${role || '(no role)'}  ${str(d.email) || doc.id}` +
        (role ? '' : `  fields: ${Object.keys(d).sort().join(', ')}`),
      );
    }
    console.log('\nOrphan Auth accounts:');
    orphanEmails.forEach((e) => console.log(`  ${e}`));
  }

  if (!apply) {
    console.log('\nRe-run with --apply to delete.');
    return;
  }

  console.log('\nDeleting...');
  for (const {col, label, total} of plan) {
    if (label !== 'WIPE' || total === 0) continue;
    await db.recursiveDelete(col);
    console.log(`  wiped ${col.id} (${total})`);
  }
  for (const [name, refs] of [
    ['users', userDocsToDelete],
    ['usernames', usernameDocsToDelete],
    ['tourist_spots', spotDocsToDelete],
  ]) {
    for (const ref of refs) await db.recursiveDelete(ref);
    if (refs.length) console.log(`  deleted ${refs.length} from ${name}`);
  }
  if (!keepAuth && authToDelete.length) {
    let ok = 0;
    let failed = 0;
    for (let i = 0; i < authToDelete.length; i += 1000) {
      const res = await auth.deleteUsers(authToDelete.slice(i, i + 1000));
      ok += res.successCount;
      failed += res.failureCount;
      res.errors.forEach((e) => console.warn(`  auth ${e.index}: ${e.error.message}`));
    }
    console.log(`  deleted ${ok} Auth account(s)${failed ? `, ${failed} failed` : ''}`);
  }
  console.log('\nReset complete. Run again without --apply to confirm zeros.');
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});

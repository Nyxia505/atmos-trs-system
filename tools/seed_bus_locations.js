/**
 * Writes bus stops and terminals into Firestore `bus_locations`.
 * The app reads this collection and does not keep coordinates in source.
 *
 *   node tools/seed_bus_locations.js           # dry run
 *   node tools/seed_bus_locations.js --apply   # create / update
 */

const {initAdmin} = require('./lib/admin_cli_credential');

const admin = initAdmin();
const db = admin.firestore();

const apply = process.argv.includes('--apply');

/** Existing stops, moved out of the app. routeType: coastal | highland | both */
const STOPS = [
  {id: 'oroquieta_bus_terminal', name: 'Oroquieta bus terminal', municipality: 'Oroquieta City (Provincial Capital)', routeType: 'coastal', locationType: 'terminal', latitude: 8.493037148800576, longitude: 123.79814266814685, sortOrder: 10},
  {id: 'plaridel_bus_terminal', name: 'Plaridel bus terminal', municipality: 'Plaridel', routeType: 'coastal', locationType: 'terminal', latitude: 8.620136282529488, longitude: 123.70950131047762, sortOrder: 20},
  {id: 'aloran_bus_stop', name: 'Aloran bus stop', municipality: 'Aloran', routeType: 'coastal', locationType: 'stop', latitude: 8.412249537859656, longitude: 123.82317045284562, sortOrder: 30},
  {id: 'lopez_jaena_bus_stop', name: 'Lopez Jaena bus stop', municipality: 'Lopez Jaena', routeType: 'coastal', locationType: 'stop', latitude: 8.5525828978222, longitude: 123.7690860488779, sortOrder: 40},
  {id: 'calamba_baliangao_terminal_calamba', name: 'Calamba and Baliangao bus terminal', municipality: 'Calamba', routeType: 'coastal', locationType: 'terminal', latitude: 8.5598630610656, longitude: 123.64246380406652, sortOrder: 50},
  {id: 'calamba_baliangao_terminal_baliangao', name: 'Calamba and Baliangao bus terminal', municipality: 'Baliangao', routeType: 'coastal', locationType: 'terminal', latitude: 8.5598630610656, longitude: 123.64246380406652, sortOrder: 60},
  {id: 'bonifacio_bus_stop', name: 'Bonifacio bus stop', municipality: 'Bonifacio', routeType: 'both', locationType: 'stop', latitude: 8.052068, longitude: 123.613190, sortOrder: 70},
  {id: 'panaon_bus_stop', name: 'Panaon bus stop', municipality: 'Panaon', routeType: 'coastal', locationType: 'stop', latitude: 8.374298443375187, longitude: 123.84065433688431, sortOrder: 80},
  {id: 'sapang_dalaga_bus_stop', name: 'Sapang Dalaga bus stop', municipality: 'Sapang Dalaga', routeType: 'coastal', locationType: 'stop', latitude: 8.54532085508384, longitude: 123.5682212764322, sortOrder: 90},
  {id: 'jimenez_bus_terminal', name: 'Jimenez bus terminal', municipality: 'Jimenez', routeType: 'coastal', locationType: 'terminal', latitude: 8.33713480807977, longitude: 123.84553724513275, sortOrder: 100},
  {id: 'sinacaban_bus_terminal', name: 'Sinacaban bus terminal', municipality: 'Sinacaban', routeType: 'coastal', locationType: 'terminal', latitude: 8.28564823872101, longitude: 123.84346050720977, sortOrder: 110},
  {id: 'tudela_bus_stop', name: 'Tudela bus stop', municipality: 'Tudela', routeType: 'coastal', locationType: 'stop', latitude: 8.240302600302313, longitude: 123.84643162121777, sortOrder: 120},
  {id: 'clarin_bus_terminal', name: 'Clarin bus terminal', municipality: 'Clarin', routeType: 'coastal', locationType: 'terminal', latitude: 8.195384812228278, longitude: 123.85786167978975, sortOrder: 130},
  {id: 'ozamiz_bus_terminal', name: 'Ozamiz bus terminal', municipality: 'Ozamiz City', routeType: 'coastal', locationType: 'terminal', latitude: 8.157382755562983, longitude: 123.83988623746002, sortOrder: 140},
  {id: 'tangub_bus_terminal', name: 'Tangub bus terminal', municipality: 'Tangub City', routeType: 'both', locationType: 'terminal', latitude: 8.073984530739589, longitude: 123.75062495439016, sortOrder: 150},
];

async function main() {
  console.log(`${apply ? 'Writing' : 'Dry run for'} ${STOPS.length} bus locations`);
  if (!apply) {
    for (const stop of STOPS) console.log(`  ${stop.id}  ${stop.latitude}, ${stop.longitude}`);
    console.log('Re-run with --apply to save.');
    return;
  }
  const batch = db.batch();
  for (const stop of STOPS) {
    const {id, ...data} = stop;
    batch.set(db.collection('bus_locations').doc(id), {
      ...data,
      status: 'active',
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    }, {merge: true});
  }
  await batch.commit();
  console.log('Saved bus_locations.');
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});

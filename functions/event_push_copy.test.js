const assert = require('assert');
const {
  classifyEventPhase,
  eventPushCopy,
  announcementPushCopy,
  isTourismEvent,
} = require('./event_push_copy');

const now = new Date(Date.UTC(2026, 9, 30, 4, 0, 0));

function manilaMidnight(year, month, day) {
  return new Date(Date.UTC(year, month - 1, day, 0, 0, 0) - 8 * 60 * 60 * 1000);
}

const halloween = {
  title: 'Halloween',
  status: 'approved',
  published: false,
  scheduleState: 'scheduled',
  allDay: true,
  municipalityName: 'Oroquieta City',
  startsAt: manilaMidnight(2026, 10, 31),
  endsAt: manilaMidnight(2026, 11, 1),
  imageUrl: 'https://example.com/halloween.jpg',
};

const drum = {
  title: 'Drum Corps Competition',
  status: 'approved',
  scheduleState: 'expired',
  municipalityName: 'Oroquieta City',
  startsAt: manilaMidnight(2026, 10, 7),
  endsAt: manilaMidnight(2026, 10, 8),
};

assert.strictEqual(classifyEventPhase(halloween, now), 'upcoming');
const copy = eventPushCopy(halloween, 'upcoming', now);
assert.strictEqual(copy.title, 'Upcoming Event: Halloween');
assert.strictEqual(
  copy.body,
  'Join the Halloween in Oroquieta City on October 31, 2026!',
);
assert.strictEqual(copy.imageUrl, 'https://example.com/halloween.jpg');
assert.strictEqual(copy.location, 'Oroquieta City');
assert.strictEqual(copy.eventDate, 'October 31, 2026');
assert.strictEqual(copy.type, 'Event');

assert.strictEqual(classifyEventPhase(drum, now), 'expired');
assert.strictEqual(
  classifyEventPhase({title: 'Draft fair', status: 'draft', startsAt: halloween.startsAt}, now),
  'skip',
);

const described = eventPushCopy(
  {
    title: 'Halloween',
    content: 'Join the **Halloween** celebration',
    status: 'approved',
    municipalityName: 'Oroquieta City',
    startsAt: halloween.startsAt,
    endsAt: halloween.endsAt,
  },
  'upcoming',
  now,
);
assert.strictEqual(
  described.body,
  'Join the Halloween celebration — Oroquieta City · October 31, 2026',
);
assert.ok(!described.body.includes('**'));

const ongoing = {
  title: 'Night Market',
  status: 'approved',
  published: true,
  scheduleState: 'live',
  municipalityName: 'Oroquieta City',
  startsAt: manilaMidnight(2026, 10, 30),
  endsAt: manilaMidnight(2026, 11, 2),
};
assert.strictEqual(classifyEventPhase(ongoing, now), 'ongoing');
assert.strictEqual(
  eventPushCopy(ongoing, 'ongoing', now).title,
  'Ongoing Event: Night Market',
);

const alert = announcementPushCopy(
  {
    title: 'Storm warning',
    content: 'Stay indoors tonight.',
    type: 'Alert',
    published: true,
    status: 'approved',
  },
  now,
);
assert.strictEqual(isTourismEvent({
  title: 'Storm warning',
  type: 'Alert',
  published: true,
}), false);
assert.strictEqual(alert.title, 'Storm warning');
assert.strictEqual(alert.eligible, true);
assert.strictEqual(alert.notificationType, 'Alert');

const expiredCopy = announcementPushCopy(drum, now);
assert.strictEqual(expiredCopy.eligible, false);
assert.strictEqual(announcementPushCopy(halloween, now).notificationType, 'tourism_event');

console.log('event_push_copy tests passed');

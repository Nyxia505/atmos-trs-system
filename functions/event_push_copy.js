/**
 * Pure copy + schedule classification for tourist event pushes.
 * Kept out of index.js so it can be tested without Firebase Admin.
 *
 * Payload text is derived here and is never written back onto the event.
 */

function normalizeField(value) {
  return String(value == null ? '' : value).trim();
}

function plainEventText(value) {
  return normalizeField(value)
    .replace(/\*\*(.+?)\*\*/g, '$1')
    .replace(/\s+/g, ' ')
    .trim();
}

function timestampMillis(value) {
  if (value == null || value === '') return null;
  if (typeof value.toDate === 'function') {
    const date = value.toDate();
    const ms = date instanceof Date ? date.getTime() : NaN;
    return Number.isFinite(ms) ? ms : null;
  }
  if (value instanceof Date) {
    const ms = value.getTime();
    return Number.isFinite(ms) ? ms : null;
  }
  if (typeof value === 'number' && Number.isFinite(value)) return value;
  if (typeof value === 'object' && typeof value._seconds === 'number') {
    const nanos = typeof value._nanoseconds === 'number' ? value._nanoseconds : 0;
    return value._seconds * 1000 + Math.floor(nanos / 1e6);
  }
  if (typeof value === 'string') {
    const match = /^(\d{4})-(\d{2})-(\d{2})$/.exec(value.trim());
    if (match) {
      const year = Number(match[1]);
      const month = Number(match[2]);
      const day = Number(match[3]);
      return Date.UTC(year, month - 1, day, 0, 0, 0) - 8 * 60 * 60 * 1000;
    }
    const parsed = Date.parse(value);
    return Number.isFinite(parsed) ? parsed : null;
  }
  return null;
}

function eventWindow(data) {
  const src = data || {};
  const start = timestampMillis(src.startsAt ?? src.startDate ?? src.eventStart);
  const dateOnly = timestampMillis(typeof src.date === 'string' ? src.date : null);
  const startMs = start != null ? start : dateOnly;
  let endMs = timestampMillis(src.endsAt ?? src.endDate ?? src.eventEnd);
  if (endMs == null && startMs != null) {
    const days = Number(src.durationDays);
    const span = Number.isFinite(days) && days >= 1 ? Math.min(days, 60) : 1;
    endMs = startMs + span * 24 * 60 * 60 * 1000;
  }
  return {startMs, endMs};
}

/**
 * upcoming | ongoing | expired | skip
 * Drafts, rejected posts, and events with no title are skip.
 * Expired events must not be pushed.
 */
function classifyEventPhase(data, now = new Date()) {
  const src = data || {};
  const status = normalizeField(src.status).toLowerCase();
  if (status === 'rejected' || status === 'draft' || status === 'pending') {
    return 'skip';
  }
  if (!plainEventText(src.title)) return 'skip';
  const state = normalizeField(src.scheduleState).toLowerCase();
  if (state === 'expired') return 'expired';
  const nowMs = now instanceof Date ? now.getTime() : Number(now);
  const {startMs, endMs} = eventWindow(src);
  if (endMs != null && nowMs >= endMs) return 'expired';
  if (startMs != null && nowMs < startMs) return 'upcoming';
  if (startMs != null) return 'ongoing';
  if (src.published === true || state === 'live') return 'ongoing';
  return 'skip';
}

function manilaLongDate(ms) {
  if (ms == null || !Number.isFinite(ms)) return '';
  try {
    return new Intl.DateTimeFormat('en-US', {
      timeZone: 'Asia/Manila',
      month: 'long',
      day: 'numeric',
      year: 'numeric',
    }).format(new Date(ms));
  } catch (_) {
    return '';
  }
}

function httpsImageUrl(data) {
  const candidates = [];
  if (data && data.imageUrl) candidates.push(data.imageUrl);
  if (data && Array.isArray(data.imageUrls)) candidates.push(...data.imageUrls);
  if (data && data.coverImageUrl) candidates.push(data.coverImageUrl);
  for (const raw of candidates) {
    const url = normalizeField(raw);
    if (url.startsWith('https://') || url.startsWith('http://')) {
      return url.slice(0, 500);
    }
  }
  return '';
}

function eventPushCopy(data, phase, now) {
  const resolved = phase || classifyEventPhase(data, now);
  const rawTitle = plainEventText(data && data.title) || 'Event';
  const prefix = resolved === 'ongoing' ? 'Ongoing Event' : 'Upcoming Event';
  let title = `${prefix}: ${rawTitle}`;
  if (title.length > 120) title = `${title.slice(0, 117)}...`;

  const place =
    normalizeField(data && data.location) ||
    normalizeField(data && data.municipalityName);
  const {startMs, endMs} = eventWindow(data || {});
  const when = startMs != null ? manilaLongDate(startMs) : normalizeField(data && data.date);
  const desc = plainEventText((data && (data.content || data.message)) || '');

  let body;
  if (desc) {
    body = desc.length > 140 ? `${desc.slice(0, 137)}...` : desc;
    const extras = [];
    if (place && !body.toLowerCase().includes(place.toLowerCase())) extras.push(place);
    if (when && !body.includes(when)) extras.push(when);
    if (extras.length) body = `${body} — ${extras.join(' · ')}`;
  } else if (place && when) {
    body = `Join the ${rawTitle} in ${place} on ${when}!`;
  } else {
    body = [place, when].filter(Boolean).join(' · ') || rawTitle;
  }
  if (body.length > 200) body = `${body.slice(0, 197)}...`;

  return {
    phase: resolved,
    title,
    body,
    type: normalizeField(data && data.type) || 'Event',
    imageUrl: httpsImageUrl(data),
    location: place.slice(0, 120),
    eventDate: when.slice(0, 80),
    startMs,
    endMs,
  };
}

function shouldPushEvent(data, now) {
  const phase = classifyEventPhase(data, now);
  return phase === 'upcoming' || phase === 'ongoing';
}

/** LGU event posts and anything stored with a schedule window. */
function isTourismEvent(data) {
  const type = normalizeField(data && data.type).toLowerCase();
  if (type === 'event') return true;
  const src = data || {};
  return !!(src.startsAt || src.endsAt || src.scheduleState);
}

/**
 * Event posts use the tourist event sentence. Other published announcements
 * keep their own title and body so alerts are not labeled as events.
 */
function announcementPushCopy(data, now) {
  if (isTourismEvent(data)) {
    const phase = classifyEventPhase(data, now);
    const copy = eventPushCopy(data, phase, now);
    return {
      ...copy,
      notificationType: 'tourism_event',
      eligible: phase === 'upcoming' || phase === 'ongoing',
    };
  }
  const title = plainEventText(data && data.title) || 'ATMOS-TRS';
  const desc = plainEventText((data && (data.content || data.message)) || '');
  const body = desc || 'New announcement';
  return {
    phase: 'ongoing',
    title: title.slice(0, 120),
    body: body.length > 200 ? `${body.slice(0, 197)}...` : body,
    type: normalizeField(data && data.type) || 'General',
    imageUrl: httpsImageUrl(data),
    location: '',
    eventDate: '',
    startMs: null,
    endMs: null,
    notificationType: normalizeField(data && data.type) || 'General',
    eligible: !!(data && data.published),
  };
}

module.exports = {
  classifyEventPhase,
  eventPushCopy,
  eventWindow,
  shouldPushEvent,
  isTourismEvent,
  announcementPushCopy,
  httpsImageUrl,
  plainEventText,
};

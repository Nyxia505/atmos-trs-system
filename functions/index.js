/**
 * When a document in `announcements` is published (new publish or draft → published),
 * sends a topic push to `governor_announcements` (same topic the Flutter app subscribes to).
 *
 * Deploy: firebase deploy --only functions
 * Requires Blaze plan for Cloud Functions (or use Firebase free tier limits).
 */
const {onDocumentWritten} = require('firebase-functions/v2/firestore');
const {initializeApp} = require('firebase-admin/app');
const {getMessaging} = require('firebase-admin/messaging');

initializeApp();

const TOPIC = 'governor_announcements';

exports.sendGovernorAnnouncementPush = onDocumentWritten(
  {
    document: 'announcements/{announcementId}',
    region: 'asia-southeast1',
  },
  async (event) => {
    const after = event.data.after;
    if (!after.exists) {
      return null;
    }
    const data = after.data();
    if (!data || !data.published) {
      return null;
    }
    const before = event.data.before;
    if (before.exists && before.data().published === true) {
      return null;
    }

    const title = String(data.title || 'ATMOS TRS').substring(0, 200);
    const raw = String(data.content || data.message || '').trim();
    const body =
      raw.length > 200 ? `${raw.substring(0, 197)}...` : raw || 'New announcement';

    await getMessaging().send({
      topic: TOPIC,
      notification: {
        title,
        body,
      },
      data: {
        type: String(data.type || 'General'),
        announcementId: event.params.announcementId,
      },
    });
    return null;
  },
);

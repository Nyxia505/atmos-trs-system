/**
 * Sends topic push notifications for announcements when:
 * 1) a draft becomes published, OR
 * 2) a published announcement is edited (title/content/type changed).
 *
 * Deploy: firebase deploy --only functions
 * Requires Blaze plan for Cloud Functions (or use Firebase free tier limits).
 */
const {onDocumentWritten} = require('firebase-functions/v2/firestore');
const {onCall, HttpsError} = require('firebase-functions/v2/https');
const {initializeApp} = require('firebase-admin/app');
const {getAuth} = require('firebase-admin/auth');
const {getFirestore, FieldValue, Timestamp} = require('firebase-admin/firestore');
const {getMessaging} = require('firebase-admin/messaging');

initializeApp();

const db = getFirestore();
const PASSWORD_RESET_OTP_COLLECTION = 'password_reset_otps';
const PASSWORD_RESET_COOLDOWN_MS = 60 * 1000;
const PASSWORD_RESET_OTP_MINUTES = 5;

/**
 * Saves tourist signup profile when client Firestore rules block the write.
 * Caller must be authenticated; profile is always written to tourists/{uid}.
 */
exports.saveTouristRegistration = onCall(
  {region: 'asia-southeast1'},
  async (request) => {
    if (!request.auth) {
      throw new HttpsError('unauthenticated', 'Must be signed in to register.');
    }
    const uid = request.auth.uid;
    const profile = request.data && request.data.profile;
    if (!profile || typeof profile !== 'object' || Array.isArray(profile)) {
      throw new HttpsError('invalid-argument', 'Missing profile payload.');
    }

    const safe = {...profile, firebaseUid: uid};
    delete safe.uid;
    safe.registeredAt = FieldValue.serverTimestamp();

    await db.collection('tourists').doc(uid).set(safe, {merge: true});

    const userRow = request.data && request.data.user;
    if (userRow && typeof userRow === 'object' && !Array.isArray(userRow)) {
      const userDoc = {
        ...userRow,
        firebaseUid: uid,
        createdAt: FieldValue.serverTimestamp(),
      };
      delete userDoc.uid;
      await db.collection('users').doc(uid).set(userDoc, {merge: true});
    }

    return {ok: true, uid};
  },
);

/** EmailJS defaults — override with Firebase env vars (see lib/config/emailjs_config.dart). */
const EMAILJS_DEFAULTS = {
  serviceId: 'service_au0q98k',
  templateId: 'template_fk8jzbr',
  publicKey: '8JZA_nboZm39-Rihv',
  privateKey: 'axQ3F4ykxyBz1GTozodYe',
};

function generateSixDigitOtp() {
  return String(100000 + Math.floor(Math.random() * 900000));
}

/**
 * Sends OTP via EmailJS (inbox — same path as signup verification).
 */
async function sendEmailJsOtp({toEmail, toName, otp, purpose}) {
  const serviceId =
    process.env.EMAILJS_SERVICE_ID || EMAILJS_DEFAULTS.serviceId;
  const templateId =
    process.env.EMAILJS_TEMPLATE_ID || EMAILJS_DEFAULTS.templateId;
  const userId = process.env.EMAILJS_PUBLIC_KEY || EMAILJS_DEFAULTS.publicKey;
  const accessToken =
    process.env.EMAILJS_PRIVATE_KEY || EMAILJS_DEFAULTS.privateKey || '';

  const displayName = toName || toEmail.split('@')[0];
  const payload = {
    service_id: serviceId,
    template_id: templateId,
    user_id: userId,
    template_params: {
      to_email: toEmail,
      to_name: displayName,
      otp,
      name: displayName,
      email: toEmail,
      user_email: toEmail,
      purpose: purpose || 'verification',
      subject: purpose === 'password_reset'
        ? 'ATMOS-TRS password reset code'
        : 'ATMOS-TRS verification code',
    },
  };
  if (accessToken) {
    payload.accessToken = accessToken;
  }

  const res = await fetch('https://api.emailjs.com/api/v1.0/email/send', {
    method: 'POST',
    headers: {'Content-Type': 'application/json'},
    body: JSON.stringify(payload),
  });
  const body = await res.text();
  if (!res.ok) {
    console.error('[sendEmailJsOtp]', res.status, body);
    throw new Error(`EmailJS ${res.status}: ${body}`);
  }
}

async function readFcmTokenForUid(uid) {
  const userSnap = await db.collection('users').doc(uid).get();
  const fromUser = userSnap.exists ? userSnap.data()?.fcmToken : null;
  if (fromUser && String(fromUser).trim()) {
    return String(fromUser).trim();
  }
  const touristSnap = await db.collection('tourists').doc(uid).get();
  const fromTourist = touristSnap.exists ? touristSnap.data()?.fcmToken : null;
  if (fromTourist && String(fromTourist).trim()) {
    return String(fromTourist).trim();
  }
  return null;
}

async function readDisplayNameForUid(uid, fallbackEmail) {
  const userSnap = await db.collection('users').doc(uid).get();
  if (userSnap.exists) {
    const name = normalizeField(userSnap.data()?.fullName);
    if (name) return name;
  }
  const touristSnap = await db.collection('tourists').doc(uid).get();
  if (touristSnap.exists) {
    const t = touristSnap.data() || {};
    const parts = [
      normalizeField(t.firstName),
      normalizeField(t.lastName),
    ].filter(Boolean);
    if (parts.length) return parts.join(' ');
  }
  return fallbackEmail.split('@')[0];
}

/**
 * High-priority FCM so the code appears as a phone notification (no Gmail app).
 */
async function sendPasswordResetOtpPush({token, otp, displayName}) {
  const collapsed =
    `Your ATMOS password reset code is ${otp}. Expires in ${PASSWORD_RESET_OTP_MINUTES} minutes.`;
  await getMessaging().send({
    token,
    notification: {
      title: 'ATMOS-TRS password reset',
      body: collapsed,
    },
    data: {
      type: 'password_reset_otp',
      otp: String(otp),
      displayName: displayName || '',
    },
    android: {
      priority: 'high',
      notification: {
        channelId: 'atmos_otp_email_style',
        sound: 'default',
      },
    },
    apns: {
      payload: {
        aps: {
          sound: 'default',
          badge: 1,
        },
      },
    },
  });
}

/**
 * Password reset step 1 (no sign-in): OTP via push + EmailJS inbox.
 * Does not reveal whether the email exists.
 */
exports.requestPasswordResetOtp = onCall(
  {region: 'asia-southeast1'},
  async (request) => {
    const email = normalizeField(request.data && request.data.email).toLowerCase();
    if (!email || !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email)) {
      throw new HttpsError('invalid-argument', 'Valid email is required.');
    }

    let uid;
    try {
      const userRecord = await getAuth().getUserByEmail(email);
      uid = userRecord.uid;
    } catch (e) {
      return {ok: true, accountFound: false, pushSent: false, emailSent: false};
    }

    const otpRef = db.collection(PASSWORD_RESET_OTP_COLLECTION).doc(uid);
    const existing = await otpRef.get();
    if (existing.exists) {
      const lastAt = existing.data()?.lastRequestedAt;
      let lastMs = 0;
      if (lastAt && typeof lastAt.toMillis === 'function') {
        lastMs = lastAt.toMillis();
      }
      if (lastMs && Date.now() - lastMs < PASSWORD_RESET_COOLDOWN_MS) {
        throw new HttpsError(
          'resource-exhausted',
          'Please wait a minute before requesting another code.',
        );
      }
    }

    const otp = generateSixDigitOtp();
    const expiresAt = new Date(
      Date.now() + PASSWORD_RESET_OTP_MINUTES * 60 * 1000,
    );
    await otpRef.set({
      email,
      otp,
      expiresAt: Timestamp.fromDate(expiresAt),
      lastRequestedAt: FieldValue.serverTimestamp(),
      createdAt: FieldValue.serverTimestamp(),
    });

    const displayName = await readDisplayNameForUid(uid, email);
    let emailSent = false;
    let pushSent = false;

    try {
      await sendEmailJsOtp({
        toEmail: email,
        toName: displayName,
        otp,
        purpose: 'password_reset',
      });
      emailSent = true;
    } catch (err) {
      console.error('[requestPasswordResetOtp] EmailJS', err);
    }

    const fcmToken = await readFcmTokenForUid(uid);
    if (fcmToken) {
      try {
        await sendPasswordResetOtpPush({token: fcmToken, otp, displayName});
        pushSent = true;
      } catch (err) {
        console.error('[requestPasswordResetOtp] FCM', err);
      }
    }

    return {ok: true, accountFound: true, pushSent, emailSent};
  },
);

/**
 * Password reset step 2: verify OTP and set a new Firebase Auth password.
 */
exports.completePasswordResetWithOtp = onCall(
  {region: 'asia-southeast1'},
  async (request) => {
    const email = normalizeField(request.data && request.data.email).toLowerCase();
    const otp = normalizeField(request.data && request.data.otp).replace(/\D/g, '');
    const newPassword = normalizeField(request.data && request.data.newPassword);

    if (!email || !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email)) {
      throw new HttpsError('invalid-argument', 'Valid email is required.');
    }
    if (!/^\d{6}$/.test(otp)) {
      throw new HttpsError('invalid-argument', 'Enter the 6-digit code.');
    }
    if (!newPassword || newPassword.length < 6) {
      throw new HttpsError(
        'invalid-argument',
        'Password must be at least 6 characters.',
      );
    }

    let uid;
    try {
      const userRecord = await getAuth().getUserByEmail(email);
      uid = userRecord.uid;
    } catch (e) {
      throw new HttpsError('not-found', 'Invalid email or code.');
    }

    const otpRef = db.collection(PASSWORD_RESET_OTP_COLLECTION).doc(uid);
    const snap = await otpRef.get();
    if (!snap.exists) {
      throw new HttpsError('not-found', 'No reset code found. Request a new one.');
    }

    const data = snap.data() || {};
    const storedOtp = String(data.otp || '').replace(/\D/g, '');
    const expiresAt = data.expiresAt;
    if (!storedOtp || storedOtp !== otp) {
      throw new HttpsError('invalid-argument', 'Invalid verification code.');
    }
    if (expiresAt && typeof expiresAt.toMillis === 'function') {
      if (Date.now() > expiresAt.toMillis()) {
        await otpRef.delete();
        throw new HttpsError(
          'deadline-exceeded',
          'This code has expired. Request a new one.',
        );
      }
    }

    await getAuth().updateUser(uid, {password: newPassword});
    await otpRef.delete();

    return {ok: true};
  },
);

/**
 * Sends OTP to the user's inbox via EmailJS (server-side, supports private accessToken).
 * Optional: firebase functions:secrets:set EMAILJS_PRIVATE_KEY (Private Key from EmailJS).
 */
exports.sendOtpEmail = onCall({region: 'asia-southeast1'}, async (request) => {
  if (!request.auth) {
    throw new HttpsError('unauthenticated', 'Must be signed in.');
  }

  const toEmail = normalizeField(request.data && request.data.toEmail).toLowerCase();
  const toName = normalizeField(request.data && request.data.toName);
  const otp = normalizeField(request.data && request.data.otp);

  if (!toEmail || !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(toEmail)) {
    throw new HttpsError('invalid-argument', 'Valid toEmail is required.');
  }
  if (!/^\d{6}$/.test(otp)) {
    throw new HttpsError('invalid-argument', 'OTP must be 6 digits.');
  }

  const authEmail = normalizeField(request.auth.token && request.auth.token.email)
    .toLowerCase();
  if (authEmail && authEmail !== toEmail) {
    throw new HttpsError(
      'permission-denied',
      'Email must match the signed-in account.',
    );
  }

  try {
    await sendEmailJsOtp({
      toEmail,
      toName,
      otp,
      purpose: 'verification',
    });
  } catch (err) {
    throw new HttpsError(
      'internal',
      'Email could not be sent. Check EmailJS keys in Firebase Functions config.',
    );
  }
  return {ok: true};
});

const TOPIC = 'governor_announcements';

const STAFF_ROLES = new Set([
  'governor',
  'Governor',
  'tourism',
  'Tourism',
  'tourism_office',
  'Tourism_Office',
]);

function normalizeField(value) {
  return String(value || '').trim();
}

async function assertProvincialStaff(uid) {
  const snap = await db.collection('users').doc(uid).get();
  if (!snap.exists) {
    throw new HttpsError('permission-denied', 'Staff profile required.');
  }
  const role = normalizeField(snap.data()?.role);
  if (!STAFF_ROLES.has(role)) {
    throw new HttpsError(
      'permission-denied',
      'Only governor or tourism staff can send announcement pushes.',
    );
  }
}

async function sendAnnouncementTopicPush({
  title,
  body,
  type,
  announcementId,
  eventType,
}) {
  const safeTitle = String(title || 'ATMOS TRS').substring(0, 200);
  const raw = normalizeField(body);
  const safeBody =
    raw.length > 200 ? `${raw.substring(0, 197)}...` : raw || 'New announcement';

  await getMessaging().send({
    topic: TOPIC,
    notification: {
      title: safeTitle,
      body: safeBody,
    },
    data: {
      type: String(type || 'General'),
      announcementId: String(announcementId || ''),
      eventType: String(eventType || 'published'),
    },
    android: {
      priority: 'high',
      notification: {
        channelId: 'atmos_announcement_heads_up',
        sound: 'default',
      },
    },
    apns: {
      payload: {
        aps: {
          sound: 'default',
        },
      },
    },
  });
}

/**
 * Callable backup when Firestore trigger is delayed or not deployed.
 * Governor / tourism staff only.
 */
exports.broadcastGovernorAnnouncement = onCall(
  {region: 'asia-southeast1'},
  async (request) => {
    if (!request.auth) {
      throw new HttpsError('unauthenticated', 'Must be signed in.');
    }
    await assertProvincialStaff(request.auth.uid);

    const title = normalizeField(request.data && request.data.title);
    const content = normalizeField(
      request.data && (request.data.content || request.data.message),
    );
    const type = normalizeField(request.data && request.data.type) || 'General';
    const announcementId = normalizeField(
      request.data && request.data.announcementId,
    );

    if (!title) {
      throw new HttpsError('invalid-argument', 'Title is required.');
    }

    await sendAnnouncementTopicPush({
      title,
      body: content,
      type,
      announcementId,
      eventType: 'published',
    });

    return {ok: true, topic: TOPIC};
  },
);

const STAFF_CLAIM_ROLES = new Set(['governor', 'tourism_office']);

function normalizeStaffClaimRole(role) {
  const raw = normalizeField(role).toLowerCase();
  if (raw === 'governor') return 'governor';
  if (raw === 'tourism' || raw === 'tourism_office') return 'tourism_office';
  return '';
}

/**
 * Sets Auth custom claims (`staff`, `role`) from `users/{uid}` so Firestore rules
 * grant provincial dashboards access to qr_checkins / checkins list queries.
 * Call after login, then refresh ID token (`getIdToken(true)`).
 */
exports.ensureStaffAccess = onCall(
  {region: 'asia-southeast1'},
  async (request) => {
    if (!request.auth) {
      throw new HttpsError('unauthenticated', 'Must be signed in.');
    }
    const uid = request.auth.uid;
    const snap = await db.collection('users').doc(uid).get();
    if (!snap.exists) {
      throw new HttpsError(
        'failed-precondition',
        'Create users/{uid} with role governor or tourism first.',
      );
    }
    const claimRole = normalizeStaffClaimRole(snap.data()?.role);
    if (!STAFF_CLAIM_ROLES.has(claimRole)) {
      throw new HttpsError(
        'permission-denied',
        'Only governor or tourism staff can use provincial dashboards.',
      );
    }
    const existing = (await getAuth().getUser(uid)).customClaims || {};
    await getAuth().setCustomUserClaims(uid, {
      ...existing,
      staff: true,
      role: claimRole,
    });
    return {ok: true, role: claimRole};
  },
);

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
    const afterData = after.data();
    if (!afterData || !afterData.published) {
      return null;
    }

    const before = event.data.before;
    const beforeData = before.exists ? before.data() : null;

    const isNewlyPublished = !before.exists || beforeData?.published !== true;
    const isPublishedEdit =
      before.exists &&
      beforeData?.published === true &&
      (normalizeField(beforeData?.title) !== normalizeField(afterData?.title) ||
        normalizeField(beforeData?.content || beforeData?.message) !==
          normalizeField(afterData?.content || afterData?.message) ||
        normalizeField(beforeData?.type) !== normalizeField(afterData?.type));

    if (!isNewlyPublished && !isPublishedEdit) {
      return null;
    }

    await sendAnnouncementTopicPush({
      title: afterData.title,
      body: afterData.content || afterData.message,
      type: afterData.type,
      announcementId: event.params.announcementId,
      eventType: isNewlyPublished ? 'published' : 'updated',
    });
    return null;
  },
);

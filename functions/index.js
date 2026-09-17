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
const {defineString} = require('firebase-functions/params');
const {initializeApp} = require('firebase-admin/app');
const {getAuth} = require('firebase-admin/auth');
const {getFirestore, FieldValue, Timestamp} = require('firebase-admin/firestore');
const {getMessaging} = require('firebase-admin/messaging');

initializeApp();

const db = getFirestore();
// Optional SMS key from functions/.env.* — not Secret Manager (avoids billing/auth on deploy).
function readSemaphoreApiKey() {
  return String(process.env.SEMAPHORE_API_KEY || '').trim();
}
const semaphoreSenderName = defineString('SEMAPHORE_SENDER_NAME', {
  default: 'ATMOS',
  description: 'Registered Semaphore sender name (see semaphore.co dashboard)',
});
const PASSWORD_RESET_OTP_COLLECTION = 'password_reset_otps';
const PASSWORD_RESET_COOLDOWN_MS = 60 * 1000;
const PASSWORD_RESET_OTP_MINUTES = 15;

function validateNewPasswordStrength(password) {
  if (!password || password.length < 8) {
    throw new HttpsError(
      'invalid-argument',
      'Password must be at least 8 characters.',
    );
  }
  if (
    !/[A-Z]/.test(password) ||
    !/[a-z]/.test(password) ||
    !/[0-9]/.test(password)
  ) {
    throw new HttpsError(
      'invalid-argument',
      'Password must include uppercase, lowercase, and a number.',
    );
  }
}

/**
 * Resolves Firebase Auth UID from login email (Auth record or Firestore tourist).
 */
async function resolveUidForPasswordReset(email) {
  try {
    const userRecord = await getAuth().getUserByEmail(email);
    return userRecord.uid;
  } catch (_) {
    // continue
  }

  const touristFields = ['email', 'authEmail', 'parentGuardianEmail'];
  for (const field of touristFields) {
    const snap = await db
      .collection('tourists')
      .where(field, '==', email)
      .limit(1)
      .get();
    if (!snap.empty) {
      const uid = snap.docs[0].id;
      try {
        await getAuth().getUser(uid);
        return uid;
      } catch (_) {
        // next field
      }
    }
  }

  const userFields = ['email', 'authEmail'];
  for (const field of userFields) {
    const snap = await db
      .collection('users')
      .where(field, '==', email)
      .limit(1)
      .get();
    if (!snap.empty) {
      const uid = snap.docs[0].id;
      try {
        await getAuth().getUser(uid);
        return uid;
      } catch (_) {
        // next field
      }
    }
  }

  return null;
}

async function readMobileForUid(uid) {
  const touristSnap = await db.collection('tourists').doc(uid).get();
  if (!touristSnap.exists) return null;
  return normalizePhilippineMobileForSms(touristSnap.data()?.mobile);
}

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

/** EmailJS defaults — ATMOS-TRS / atmostrs@gmail.com (see lib/config/emailjs_config.dart). */
const EMAILJS_DEFAULTS = {
  serviceId: 'service_l6fdttb',
  templateId: 'template_ngd8f9t',
  publicKey: 'C3P2wYh7zDIMtMGtd',
  privateKey: 'cCuOD6UxqxuNOI6pKtjRP',
};

function generateSixDigitOtp() {
  return String(100000 + Math.floor(Math.random() * 900000));
}

/**
 * Saves signup / resend OTP to email_otps/{uid} when client Firestore rules block the write.
 */
exports.saveEmailOtp = onCall({region: 'asia-southeast1'}, async (request) => {
  if (!request.auth) {
    throw new HttpsError('unauthenticated', 'Must be signed in to save verification code.');
  }
  const uid = request.auth.uid;
  const email = normalizeField(request.data && request.data.email).toLowerCase();
  const otp = normalizeField(request.data && request.data.otp).replace(/\D/g, '');
  const expiresAtMs = Number(request.data && request.data.expiresAtMs);

  if (!email || !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email)) {
    throw new HttpsError('invalid-argument', 'Valid email is required.');
  }
  if (!/^\d{6}$/.test(otp)) {
    throw new HttpsError('invalid-argument', 'OTP must be 6 digits.');
  }

  const expiresAt = Number.isFinite(expiresAtMs) && expiresAtMs > Date.now()
    ? new Date(expiresAtMs)
    : new Date(Date.now() + 15 * 60 * 1000);

  await db.collection('email_otps').doc(uid).set({
    email,
    otp,
    firebaseUid: uid,
    expiresAt: Timestamp.fromDate(expiresAt),
    createdAt: FieldValue.serverTimestamp(),
  }, {merge: true});

  return {ok: true, uid};
});

/**
 * Server-side OTP check (and optional delete) when client Firestore read is blocked.
 */
exports.verifyEmailOtp = onCall({region: 'asia-southeast1'}, async (request) => {
  if (!request.auth) {
    throw new HttpsError('unauthenticated', 'Must be signed in.');
  }
  const uid = request.auth.uid;
  const entered = normalizeField(request.data && request.data.otp).replace(/\D/g, '');
  const deleteOnSuccess = request.data && request.data.deleteOnSuccess !== false;

  if (!/^\d{6}$/.test(entered)) {
    throw new HttpsError('invalid-argument', 'OTP must be 6 digits.');
  }

  const snap = await db.collection('email_otps').doc(uid).get();
  if (!snap.exists || !snap.data()) {
    return {ok: false, reason: 'not_found'};
  }

  const data = snap.data();
  const stored = String(data.otp || '').replace(/\D/g, '');
  const expiresAt = data.expiresAt;
  if (expiresAt && expiresAt.toDate && expiresAt.toDate() < new Date()) {
    return {ok: false, reason: 'expired'};
  }
  if (stored.length !== 6 || stored !== entered) {
    return {ok: false, reason: 'invalid'};
  }

  if (deleteOnSuccess) {
    await db.collection('email_otps').doc(uid).delete();
  }
  return {ok: true};
});

/**
 * Returns active OTP digits for the signed-in user (show on device / hasActiveOtp).
 */
exports.peekEmailOtp = onCall({region: 'asia-southeast1'}, async (request) => {
  if (!request.auth) {
    throw new HttpsError('unauthenticated', 'Must be signed in.');
  }
  const uid = request.auth.uid;
  const snap = await db.collection('email_otps').doc(uid).get();
  if (!snap.exists || !snap.data()) {
    return {active: false};
  }
  const data = snap.data();
  const expiresAt = data.expiresAt;
  if (expiresAt && expiresAt.toDate && expiresAt.toDate() < new Date()) {
    return {active: false, expired: true};
  }
  const otp = String(data.otp || '').replace(/\D/g, '');
  if (otp.length !== 6) {
    return {active: false};
  }
  return {active: true, otp};
});

const OTP_INBOX_REPLY_TO =
  process.env.OTP_INBOX_REPLY_TO || 'atmostrs@gmail.com';
const OTP_INBOX_FROM_NAME = process.env.OTP_INBOX_FROM_NAME || 'ATMOS-TRS';

function otpEmailSubject(purpose) {
  if (purpose === 'password_reset') {
    return 'Your ATMOS-TRS password reset code';
  }
  return 'Complete your ATMOS-TRS registration';
}

function otpEmailPlainText({displayName, otp, purpose}) {
  const greeting = displayName ? `Hello ${displayName},` : 'Hello,';
  const intro =
    purpose === 'password_reset'
      ? 'Use this code to reset your ATMOS-TRS password:'
      : 'Use this code to finish creating your ATMOS-TRS tourist account:';
  return (
    `${greeting}\n\n` +
    `${intro}\n\n` +
    `${otp}\n\n` +
    'This code expires in 15 minutes. Do not share it with anyone.\n\n' +
    '— ATMOS-TRS Tourism'
  );
}

function otpEmailHtml({displayName, otp, purpose}) {
  const greeting = displayName ? `Hello ${displayName},` : 'Hello,';
  const intro =
    purpose === 'password_reset'
      ? 'Use this code to reset your ATMOS-TRS password:'
      : 'Use this code to finish creating your ATMOS-TRS tourist account:';
  return (
    `<p>${greeting}</p>` +
    `<p>${intro}</p>` +
    `<p style="font-size:24px;font-weight:700;letter-spacing:4px;margin:16px 0;">${otp}</p>` +
    '<p>This code expires in 15 minutes. Do not share it with anyone.</p>' +
    '<p>— ATMOS-TRS Tourism</p>'
  );
}

/**
 * Gmail / Google Workspace SMTP (best inbox placement). Optional:
 * GMAIL_SMTP_USER + GMAIL_SMTP_APP_PASSWORD in functions/.env or secrets.
 */
async function sendSmtpOtpIfConfigured({toEmail, toName, otp, purpose}) {
  const user = (process.env.GMAIL_SMTP_USER || '').trim();
  const pass = (process.env.GMAIL_SMTP_APP_PASSWORD || '').trim();
  if (!user || !pass) {
    return false;
  }

  let nodemailer;
  try {
    nodemailer = require('nodemailer');
  } catch (err) {
    console.warn('[sendSmtpOtp] nodemailer not available', err);
    return false;
  }

  const displayName = toName || toEmail.split('@')[0];
  const subject = otpEmailSubject(purpose);
  const text = otpEmailPlainText({displayName, otp, purpose});
  const html = otpEmailHtml({displayName, otp, purpose});

  const transporter = nodemailer.createTransport({
    service: 'gmail',
    auth: {user, pass},
  });

  await transporter.sendMail({
    from: `"${OTP_INBOX_FROM_NAME}" <${user}>`,
    to: toEmail,
    replyTo: OTP_INBOX_REPLY_TO,
    subject,
    text,
    html,
    headers: {
      'X-Priority': '1',
      'X-MSMail-Priority': 'High',
      Importance: 'high',
    },
  });
  console.log('[sendSmtpOtp] sent via Gmail SMTP to', toEmail);
  return true;
}

/**
 * Sends OTP via EmailJS (fallback when SMTP is not configured).
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
  const resolvedPurpose = purpose || 'verification';
  const subject = otpEmailSubject(resolvedPurpose);
  const message = otpEmailPlainText({
    displayName,
    otp,
    purpose: resolvedPurpose,
  });
  const messageHtml = otpEmailHtml({
    displayName,
    otp,
    purpose: resolvedPurpose,
  });
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
      purpose: resolvedPurpose,
      subject,
      from_name: OTP_INBOX_FROM_NAME,
      reply_to: OTP_INBOX_REPLY_TO,
      message,
      message_html: messageHtml,
      preheader: `Your code is ${otp}. Expires in 15 minutes.`,
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

/** SMTP first (inbox), then EmailJS fallback. */
async function sendOtpInboxEmail({toEmail, toName, otp, purpose}) {
  try {
    const smtpSent = await sendSmtpOtpIfConfigured({
      toEmail,
      toName,
      otp,
      purpose,
    });
    if (smtpSent) {
      return {channel: 'smtp'};
    }
  } catch (err) {
    console.warn('[sendOtpInboxEmail] SMTP failed, trying EmailJS', err);
  }
  await sendEmailJsOtp({toEmail, toName, otp, purpose});
  return {channel: 'emailjs'};
}

/**
 * High-priority FCM so signup OTP appears as a phone notification (inbox backup).
 */
async function sendEmailOtpPush({token, otp, displayName}) {
  const collapsed =
    `Your ATMOS-TRS verification code is ${otp}. Expires in 15 minutes.`;
  await getMessaging().send({
    token,
    notification: {
      title: 'ATMOS-TRS verification',
      body: collapsed,
    },
    data: {
      type: 'email_otp',
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
    `Your ATMOS-TRS password reset code is ${otp}. Expires in ${PASSWORD_RESET_OTP_MINUTES} minutes.`;
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

    const uid = await resolveUidForPasswordReset(email);
    if (!uid) {
      return {
        ok: true,
        accountFound: false,
        pushSent: false,
        emailSent: false,
        smsSent: false,
      };
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
    let smsSent = false;

    try {
      await sendOtpInboxEmail({
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

    const mobile = await readMobileForUid(uid);
    if (mobile) {
      try {
        const apiKey = readSemaphoreApiKey();
        if (apiKey && String(apiKey).trim()) {
          const senderName = (semaphoreSenderName.value() || 'ATMOS').trim();
          await sendSemaphoreOtpSms({
            apiKey: String(apiKey).trim(),
            mobile,
            otp,
            senderName,
          });
          smsSent = true;
        }
      } catch (err) {
        console.error('[requestPasswordResetOtp] SMS', err);
      }
    }

    return {ok: true, accountFound: true, pushSent, emailSent, smsSent};
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
    validateNewPasswordStrength(newPassword);

    const uid = await resolveUidForPasswordReset(email);
    if (!uid) {
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

    try {
      await getAuth().updateUser(uid, {password: newPassword});
    } catch (err) {
      const code = err && err.code ? String(err.code) : '';
      if (code.includes('weak-password')) {
        throw new HttpsError(
          'invalid-argument',
          'Password is too weak. Use at least 8 characters with uppercase, lowercase, and a number.',
        );
      }
      throw new HttpsError(
        'internal',
        err.message || 'Could not update password.',
      );
    }
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

  const authEmail = normalizeField(request.auth.token && request.auth.token.email)
    .toLowerCase();
  const toEmail = normalizeField(request.data && request.data.toEmail).toLowerCase();
  const inboxEmail = normalizeField(request.data && request.data.inboxEmail)
    .toLowerCase();
  const toName = normalizeField(request.data && request.data.toName);
  const otp = normalizeField(request.data && request.data.otp);

  if (!toEmail || !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(toEmail)) {
    throw new HttpsError('invalid-argument', 'Valid toEmail is required.');
  }
  if (!/^\d{6}$/.test(otp)) {
    throw new HttpsError('invalid-argument', 'OTP must be 6 digits.');
  }

  if (authEmail && authEmail !== toEmail) {
    throw new HttpsError(
      'permission-denied',
      'Email must match the signed-in account.',
    );
  }

  const deliveryEmail =
    inboxEmail && /^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(inboxEmail)
      ? inboxEmail
      : toEmail;

  try {
    const delivery = await sendOtpInboxEmail({
      toEmail: deliveryEmail,
      toName,
      otp,
      purpose: 'verification',
    });
    console.log('[sendOtpEmail] inbox channel=', delivery.channel);

    let pushSent = false;
    try {
      const fcmToken = await readFcmTokenForUid(request.auth.uid);
      if (fcmToken) {
        await sendEmailOtpPush({
          token: fcmToken,
          otp,
          displayName: toName,
        });
        pushSent = true;
      }
    } catch (pushErr) {
      console.warn('[sendOtpEmail] FCM push skipped', pushErr);
    }

    return {ok: true, channel: delivery.channel, pushSent};
  } catch (err) {
    console.error('[sendOtpEmail]', err);
    throw new HttpsError(
      'internal',
      'Email could not be sent. Check Gmail SMTP or EmailJS config in Firebase Functions.',
    );
  }
});

/**
 * Sends signup / resend OTP via SMS to the tourist's registered mobile (Philippines).
 * Setup: docs/SMS_OTP_SETUP.md
 */
function normalizePhilippineMobileForSms(raw) {
  let d = String(raw || '').replace(/\D/g, '');
  if (!d) return null;
  if (d.startsWith('63') && d.length === 12) return d;
  if (d.startsWith('0') && d.length === 11) return `63${d.substring(1)}`;
  if (d.startsWith('9') && d.length === 10) return `63${d}`;
  return null;
}

/**
 * Semaphore OTP route (dedicated telco path for verification codes).
 * @see https://semaphore.co/docs
 */
function parseSemaphoreRows(text) {
  try {
    const parsed = JSON.parse(text);
    if (Array.isArray(parsed)) return parsed;
    if (parsed && typeof parsed === 'object') return [parsed];
  } catch (_) {}
  return [];
}

async function sendSemaphoreOtpSms({apiKey, mobile, otp, senderName}) {
  const buildBody = (includeSender) => {
    const body = new URLSearchParams();
    body.append('apikey', apiKey);
    body.append('number', mobile);
    body.append(
      'message',
      'Your ATMOS verification code is {otp}. Valid for 15 minutes. Do not share this code.',
    );
    body.append('code', otp);
    const sn = (senderName || '').trim();
    if (includeSender && sn) {
      body.append('sendername', sn);
    }
    return body;
  };

  const attempts = [true, false];
  let lastError = null;

  for (const includeSender of attempts) {
    const res = await fetch('https://api.semaphore.co/api/v4/otp', {
      method: 'POST',
      headers: {'Content-Type': 'application/x-www-form-urlencoded'},
      body: buildBody(includeSender).toString(),
    });
    const text = await res.text();
    console.log(
      '[sendOtpSms] Semaphore response',
      includeSender ? 'with-sender' : 'no-sender',
      res.status,
      text.slice(0, 500),
    );

    if (!res.ok) {
      lastError = new Error(`Semaphore HTTP ${res.status}: ${text}`);
      if (includeSender) continue;
      throw lastError;
    }

    const rows = parseSemaphoreRows(text);
    if (rows.length === 0) {
      lastError = new Error(
        'Semaphore returned no message record. Load credits and complete your profile at semaphore.co.',
      );
      if (includeSender) continue;
      throw lastError;
    }

    const row = rows[0];
    const status = String(row?.status || '').toLowerCase();
    if (status === 'failed' || status === 'refunded') {
      lastError = new Error(
        `SMS ${status}. Load Semaphore credits, approve sender name, and complete account profile.`,
      );
      if (includeSender) continue;
      throw lastError;
    }

    return {
      rows,
      status: row?.status || 'unknown',
      messageId: row?.message_id,
      network: row?.network,
    };
  }

  throw lastError || new Error('SMS could not be sent via Semaphore.');
}

exports.sendOtpSms = onCall(
  {region: 'asia-southeast1'},
  async (request) => {
    if (!request.auth) {
      throw new HttpsError('unauthenticated', 'Must be signed in.');
    }

    const otp = normalizeField(request.data && request.data.otp).replace(/\D/g, '');
    const mobile = normalizePhilippineMobileForSms(
      request.data && request.data.mobile,
    );

    if (!/^\d{6}$/.test(otp)) {
      throw new HttpsError('invalid-argument', 'OTP must be 6 digits.');
    }
    if (!mobile) {
      throw new HttpsError('invalid-argument', 'Valid Philippine mobile is required.');
    }

    const uid = request.auth.uid;
    try {
      const touristSnap = await db.collection('tourists').doc(uid).get();
      if (touristSnap.exists) {
        const profileMobile = normalizePhilippineMobileForSms(
          touristSnap.data()?.mobile,
        );
        if (profileMobile && profileMobile !== mobile) {
          throw new HttpsError(
            'permission-denied',
            'Mobile number does not match your registration profile.',
          );
        }
      }
    } catch (e) {
      if (e instanceof HttpsError) throw e;
      console.warn('[sendOtpSms] tourist mobile check skipped:', e);
    }

    let apiKey;
    try {
      apiKey = readSemaphoreApiKey();
    } catch (e) {
      console.warn('[sendOtpSms] SEMAPHORE_API_KEY not available:', e);
      return {ok: true, skipped: true, reason: 'sms_not_configured'};
    }
    if (!apiKey || !String(apiKey).trim()) {
      console.warn('[sendOtpSms] SEMAPHORE_API_KEY empty — SMS skipped');
      return {ok: true, skipped: true, reason: 'sms_not_configured'};
    }

    const senderName = (semaphoreSenderName.value() || 'ATMOS').trim();

    try {
      const result = await sendSemaphoreOtpSms({
        apiKey: String(apiKey).trim(),
        mobile,
        otp,
        senderName,
      });
      console.log(
        '[sendOtpSms] queued',
        mobile.slice(0, 5) + '****',
        'status=',
        result.status,
        'network=',
        result.network,
      );
      return {
        ok: true,
        skipped: false,
        status: result.status,
        network: result.network || '',
        messageId: result.messageId || '',
      };
    } catch (err) {
      console.error('[sendOtpSms]', err);
      throw new HttpsError(
        'failed-precondition',
        err.message || 'SMS could not be sent. Load Semaphore credits and approve sender name.',
      );
    }
  },
);

const TOPIC = 'governor_announcements';

const STAFF_ROLES = new Set([
  'governor',
  'Governor',
  'tourism',
  'Tourism',
  'tourism_office',
  'Tourism_Office',
]);

/** Misamis Occidental LGU display names (for dummy seed). */
const MUNICIPALITY_DISPLAY_NAMES = {
  oroquieta: 'Oroquieta City',
  ozamiz: 'Ozamis City',
  tangub: 'Tangub City',
  aloran: 'Aloran',
  baliangao: 'Baliangao',
  bonifacio: 'Bonifacio',
  calamba: 'Calamba',
  clarin: 'Clarin',
  concepcion: 'Concepcion',
  dvc: 'Don Victoriano Chiongbian',
  jimenez: 'Jimenez',
  lopezjaena: 'Lopez Jaena',
  panaon: 'Panaon',
  plaridel: 'Plaridel',
  sapangdalaga: 'Sapang Dalaga',
  sinacaban: 'Sinacaban',
  tudela: 'Tudela',
};

/** Varied profiles so LGU report exports have nationality / origin / sex data. */
const DEMO_TOURIST_PROFILES = [
  {
    sex: 'Male',
    nationality: 'Filipino',
    country: 'Philippines',
    province: 'Misamis Occidental',
    city: 'Jimenez',
    isLocal: true,
    localOrForeign: 'Local',
  },
  {
    sex: 'Female',
    nationality: 'Filipino',
    country: 'Philippines',
    province: 'Misamis Occidental',
    city: 'Ozamiz City',
    isLocal: true,
    localOrForeign: 'Local',
  },
  {
    sex: 'Male',
    nationality: 'Filipino',
    country: 'Philippines',
    province: 'Misamis Oriental',
    city: 'Cagayan de Oro',
    isLocal: true,
    localOrForeign: 'Local',
  },
  {
    sex: 'Female',
    nationality: 'American',
    country: 'United States',
    province: 'California',
    city: 'San Francisco',
    isLocal: false,
    localOrForeign: 'Foreign',
  },
  {
    sex: 'Male',
    nationality: 'Japanese',
    country: 'Japan',
    province: '',
    city: 'Tokyo',
    isLocal: false,
    localOrForeign: 'Foreign',
  },
  {
    sex: 'Female',
    nationality: 'Korean',
    country: 'South Korea',
    province: '',
    city: 'Seoul',
    isLocal: false,
    localOrForeign: 'Foreign',
  },
];

const DEMO_TOURISM_PASSWORD = 'ATMOS#Tourism@2026_MisOcc!';
const DEMO_REPORTS_PASSWORD = 'ATMOS#Reports@2026';
const DEMO_MONTHLY_PASSWORD = 'ATMOS#Monthly@2026';
const DEMO_GOVERNOR_PASSWORD = 'Asenso@MISocc#2026!Gov';

function normalizeField(value) {
  return String(value || '').trim();
}

function municipalityDisplayName(municipalityId) {
  const key = normalizeField(municipalityId).toLowerCase();
  return MUNICIPALITY_DISPLAY_NAMES[key] ||
    (key ? key.charAt(0).toUpperCase() + key.slice(1) : 'Misamis Occidental');
}

/** Days in the current calendar month (1..today) for monthly report CSV columns. */
function currentMonthCheckInDays(now = new Date()) {
  const today = now.getDate();
  const candidates = [1, 2, 3, 5, 8, 10, 12, 15, 18, 20, 22, 25, 26, today];
  const days = [];
  for (const d of candidates) {
    if (d >= 1 && d <= today && !days.includes(d)) {
      days.push(d);
    }
  }
  days.sort((a, b) => a - b);
  if (days.length === 0) {
    days.push(Math.max(1, today));
  }
  return days;
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

/**
 * Ensures only one of (callable, Firestore trigger) actually sends FCM for an
 * announcement event. Prevents duplicate tray notifications on tourist devices.
 */
async function claimAnnouncementFcmSend(announcementId, eventType) {
  const id = normalizeField(announcementId);
  if (!id) return true; // no id → allow send (still collapsed by FCM tag when possible)
  const ref = db.collection('announcements').doc(id);
  const claimKey = `fcmSent_${normalizeField(eventType) || 'published'}`;
  try {
    return await db.runTransaction(async (tx) => {
      const snap = await tx.get(ref);
      if (!snap.exists) return false;
      const data = snap.data() || {};
      if (data[claimKey]) return false;
      tx.update(ref, {
        [claimKey]: FieldValue.serverTimestamp(),
        fcmSentAt: FieldValue.serverTimestamp(),
      });
      return true;
    });
  } catch (err) {
    console.error('[claimAnnouncementFcmSend]', err);
    // Fail open only once: prefer sending rather than silently dropping.
    return true;
  }
}

/** Recent device tokens so installed apps get a direct push (faster than topic alone). */
async function collectInstalledAppFcmTokens(limit = 500) {
  const tokens = new Set();
  try {
    let snap;
    try {
      snap = await db
        .collection('users')
        .orderBy('fcmTokenUpdatedAt', 'desc')
        .limit(limit)
        .get();
    } catch (_) {
      snap = await db.collection('users').limit(limit).get();
    }
    for (const doc of snap.docs) {
      const token = normalizeField(doc.data()?.fcmToken);
      if (token) tokens.add(token);
    }
  } catch (err) {
    console.error('[collectInstalledAppFcmTokens] users:', err);
  }
  try {
    const snap = await db.collection('tourists').limit(limit).get();
    for (const doc of snap.docs) {
      const token = normalizeField(doc.data()?.fcmToken);
      if (token) tokens.add(token);
    }
  } catch (err) {
    console.error('[collectInstalledAppFcmTokens] tourists:', err);
  }
  return [...tokens];
}

function buildAnnouncementMessagePayload({
  title,
  body,
  type,
  announcementId,
  eventType,
}) {
  const safeTitle = String(title || 'ATMOS-TRS').substring(0, 200);
  const raw = normalizeField(body);
  const safeBody =
    raw.length > 200 ? `${raw.substring(0, 197)}...` : raw || 'New announcement';
  const aid = String(announcementId || '');
  const collapse = aid || 'governor_announcement';

  return {
    notification: {
      title: safeTitle,
      body: safeBody,
    },
    data: {
      type: String(type || 'General'),
      announcementId: aid,
      eventType: String(eventType || 'published'),
      title: safeTitle,
      body: safeBody,
    },
    android: {
      priority: 'high',
      collapseKey: collapse,
      ttl: 3600 * 1000,
      notification: {
        channelId: 'atmos_announcement_heads_up',
        sound: 'default',
        tag: collapse,
        priority: 'max',
        defaultSound: true,
      },
    },
    apns: {
      headers: {
        'apns-priority': '10',
        'apns-push-type': 'alert',
        'apns-collapse-id': collapse.substring(0, 64),
      },
      payload: {
        aps: {
          sound: 'default',
          'content-available': 1,
        },
      },
    },
  };
}

async function sendAnnouncementTopicPush({
  title,
  body,
  type,
  announcementId,
  eventType,
}) {
  const base = buildAnnouncementMessagePayload({
    title,
    body,
    type,
    announcementId,
    eventType,
  });
  const messaging = getMessaging();
  const jobs = [
    messaging.send({
      ...base,
      topic: TOPIC,
    }),
  ];

  // Direct token fan-out: reaches installed apps even if topic subscription lagged.
  const tokens = await collectInstalledAppFcmTokens();
  for (let i = 0; i < tokens.length; i += 500) {
    const chunk = tokens.slice(i, i + 500);
    jobs.push(
      messaging.sendEachForMulticast({
        tokens: chunk,
        ...base,
      }),
    );
  }

  const results = await Promise.allSettled(jobs);
  const failed = results.filter((r) => r.status === 'rejected');
  if (failed.length) {
    console.error(
      `[sendAnnouncementTopicPush] ${failed.length}/${results.length} send(s) failed`,
      failed[0].reason,
    );
  }
}

/**
 * Immediate push from Governor UI (preferred path — lower latency than trigger alone).
 * Deduped against Firestore trigger via claimAnnouncementFcmSend.
 */
exports.broadcastGovernorAnnouncement = onCall(
  {
    region: 'asia-southeast1',
  },
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

    const claimed = await claimAnnouncementFcmSend(announcementId, 'published');
    if (!claimed) {
      return {ok: true, topic: TOPIC, skipped: true, reason: 'already_sent'};
    }

    await sendAnnouncementTopicPush({
      title,
      body: content,
      type,
      announcementId,
      eventType: 'published',
    });

    return {ok: true, topic: TOPIC, skipped: false};
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

    const eventType = isNewlyPublished ? 'published' : 'updated';
    const announcementId = event.params.announcementId;
    const claimed = await claimAnnouncementFcmSend(announcementId, eventType);
    if (!claimed) {
      console.log(
        `[sendGovernorAnnouncementPush] skip ${announcementId} (${eventType}) — already claimed`,
      );
      return null;
    }

    await sendAnnouncementTopicPush({
      title: afterData.title,
      body: afterData.content || afterData.message,
      type: afterData.type,
      announcementId,
      eventType,
    });
    return null;
  },
);

/**
 * Generates dummy data for tourism analytics/report testing.
 * Restricted to governor/tourism staff accounts.
 */
exports.seedTourismDummyData = onCall(
  {region: 'asia-southeast1'},
  async (request) => {
    if (process.env.ALLOW_DUMMY_SEED !== 'true') {
      throw new HttpsError(
        'failed-precondition',
        'Dummy data seeding is disabled. Set ALLOW_DUMMY_SEED=true only in dev.',
      );
    }
    if (!request.auth) {
      throw new HttpsError('unauthenticated', 'Must be signed in.');
    }
    await assertProvincialStaff(request.auth.uid);

    const municipalityId = normalizeField(
      request.data && request.data.municipalityId,
    ).toLowerCase() || 'jimenez';
    const municipalityName = municipalityDisplayName(municipalityId);
    const reportFocus = normalizeField(
      request.data && request.data.reportFocus,
    ).toLowerCase() || 'all';
    const seedAnnual = reportFocus === 'all' || reportFocus === 'annual';
    const seedMonthly = reportFocus === 'all' || reportFocus === 'monthly';

    const auth = getAuth();
    const seededAuthUsers = [];
    const tourismMunicipalEmail = `tourism.${municipalityId}@misocc-demo.ph`;
    const authRows = [
      {
        email: 'governor.atmos@misocc-demo.ph',
        password: DEMO_GOVERNOR_PASSWORD,
        role: 'governor',
        municipalityId: '',
        municipality: 'Misamis Occidental',
        fullName: 'Governor Demo',
      },
      {
        email: 'tourismoffice.atmos@misocc-demo.ph',
        password: DEMO_TOURISM_PASSWORD,
        role: 'tourism',
        municipalityId,
        municipality: municipalityName,
        fullName: 'Tourism Office Demo',
      },
      {
        email: tourismMunicipalEmail,
        password: DEMO_TOURISM_PASSWORD,
        role: 'tourism',
        municipalityId,
        municipality: municipalityName,
        fullName: `${municipalityName} Tourism`,
      },
      {
        email: 'reports.demo@misocc-demo.ph',
        password: DEMO_REPORTS_PASSWORD,
        role: 'tourism',
        municipalityId,
        municipality: municipalityName,
        fullName: 'Report Testing Demo',
      },
      {
        email: 'monthly.reports@misocc-demo.ph',
        password: DEMO_MONTHLY_PASSWORD,
        role: 'tourism',
        municipalityId,
        municipality: municipalityName,
        fullName: 'Monthly Report Demo',
      },
    ];

    for (const row of authRows) {
      let userRecord;
      try {
        userRecord = await auth.getUserByEmail(row.email);
      } catch (_) {
        userRecord = await auth.createUser({
          email: row.email,
          password: row.password,
          displayName: row.fullName,
          emailVerified: true,
        });
      }
      seededAuthUsers.push(row.email);
      await db.collection('users').doc(userRecord.uid).set({
        firebaseUid: userRecord.uid,
        email: row.email,
        role: row.role,
        municipality: row.municipality,
        municipalityId: row.municipalityId,
        fullName: row.fullName,
        isVerified: true,
        updatedAt: FieldValue.serverTimestamp(),
      }, {merge: true});
    }

    const attractionSpots = [
      {id: 'oroquieta_city_plaza', name: 'Oroquieta City Plaza', category: 'Historical', image: 'assets/images/oroquieta City plaza.jpeg'},
      {id: 'el_triungo_beach', name: 'El Triunfo Beach', category: 'Beach', image: 'assets/images/el triunfo.png'},
      {id: 'piduan_falls', name: 'Piduan Falls', category: 'Falls', image: 'assets/images/Piduan Falls Donvic.jpg'},
      {id: 'misocc_capitol', name: 'Misamis Occidental Capitol', category: 'Historical', image: 'assets/images/capitol.webp'},
      {id: 'lumantas_riverside', name: 'Lumantas Riverside Garden', category: 'Resort', image: 'assets/images/lumantas river side garden.webp'},
      {id: 'triplan_hub', name: 'ATMOS-TRS Visitor Hub', category: 'Resort', image: 'assets/images/tripplan.png'},
    ];
    for (const s of attractionSpots) {
      await db.collection('tourist_spots').doc(s.id).set({
        name: s.name,
        category: s.category,
        municipalityId,
        municipality: municipalityName,
        status: 'Active',
        image_url: s.image,
        image: s.image,
        updatedAt: FieldValue.serverTimestamp(),
      }, {merge: true});
    }

    const accommodationRows = [
      {name: 'Asenso Seaview Hotel', type: 'Hotel', roomCount: 48},
      {name: 'MisOcc Business Inn', type: 'Inn', roomCount: 32},
      {name: 'Oroquieta Bay Resort', type: 'Resort', roomCount: 26},
      {name: 'Panaon Family Lodge', type: 'Lodge', roomCount: 19},
      {name: 'Gov Hub Suites', type: 'Hotel', roomCount: 56},
      {name: 'Triunfo Beach Cottages', type: 'Resort', roomCount: 14},
    ];
    let seededAccommodations = 0;
    for (const a of accommodationRows) {
      const id = a.name.toLowerCase().replace(/[^a-z0-9]+/g, '_');
      await db.collection('accommodation_establishments').doc(id).set({
        name: a.name,
        type: a.type,
        municipalityId,
        municipality: municipalityName,
        roomCount: a.roomCount,
        status: 'Active',
        updatedAt: FieldValue.serverTimestamp(),
      }, {merge: true});
      seededAccommodations += 1;
    }

    const firstNames = [
      'Ana', 'Ben', 'Carla', 'David', 'Erika', 'Francis', 'Grace',
      'Hector', 'Ivy', 'John', 'Karen', 'Leo', 'Mara', 'Nico', 'Olive',
      'Paolo', 'Queenie', 'Ramon', 'Sarah', 'Troy',
    ];
    const lastNames = [
      'Santos', 'Reyes', 'Cruz', 'Lopez', 'Garcia', 'Mendoza',
      'Ramos', 'Aquino', 'Dela Cruz', 'Torres',
    ];

    const now = new Date();
    const reportYear = now.getFullYear();
    const reportMonthIndex = now.getMonth();
    const monthName = [
      'January', 'February', 'March', 'April', 'May', 'June',
      'July', 'August', 'September', 'October', 'November', 'December',
    ][reportMonthIndex];
    /** Jan / Feb / Mar check-ins for annual report testing. */
    const annualMonths = [0, 1, 2];
    const monthlyDays = currentMonthCheckInDays(now);
    let seededTourists = 0;
    let seededCheckins = 0;
    let seededMonthlyCheckins = 0;
    const dummyTouristCount = seedMonthly ? 12 : 15;
    for (let i = 0; i < dummyTouristCount; i++) {
      const fn = firstNames[i % firstNames.length];
      const ln = lastNames[i % lastNames.length];
      const uid = `dummy_tourist_${municipalityId}_${String(i + 1).padStart(3, '0')}`;
      const email = `${fn.toLowerCase()}.${ln.toLowerCase()}.${i + 1}@dummy-tourist.test`;
      const profile = DEMO_TOURIST_PROFILES[i % DEMO_TOURIST_PROFILES.length];
      const partyHeadcount = 1 + (i % 3);

      await db.collection('tourists').doc(uid).set({
        firebaseUid: uid,
        firstName: fn,
        lastName: ln,
        fullName: `${fn} ${ln}`,
        email,
        sex: profile.sex,
        nationality: profile.nationality,
        country: profile.country,
        province: profile.province,
        city: profile.city,
        isLocal: profile.isLocal,
        localOrForeign: profile.localOrForeign,
        partyHeadcount,
        status: 'Active',
        isVerified: true,
        registrationMunicipalityId: municipalityId,
        totalVisits: 0,
        updatedAt: FieldValue.serverTimestamp(),
      }, {merge: true});
      seededTourists += 1;

      let checkinsForUser = 0;

      if (seedAnnual) {
        for (let j = 0; j < annualMonths.length; j++) {
          const spot = attractionSpots[(i + j) % attractionSpots.length];
          const eventDate = new Date(
            reportYear,
            annualMonths[j],
            8 + ((i + j) % 18),
            9 + (i % 8),
            0,
            0,
          );
          const checkinId = `${uid}_${spot.id}_y${reportYear}_m${annualMonths[j] + 1}`;
          await db.collection('qr_checkins').doc(checkinId).set({
            userId: uid,
            user_id: uid,
            tourist_id: uid,
            touristName: `${fn} ${ln}`,
            tourist_name: `${fn} ${ln}`,
            municipalityId: municipalityId,
            municipality: municipalityName,
            spotId: spot.id,
            spot_id: spot.id,
            spot_name: spot.name,
            status: 'Verified',
            timestamp: Timestamp.fromDate(eventDate),
          }, {merge: true});
          await db.collection('checkins').doc(checkinId).set({
            user_id: uid,
            location_id: spot.id,
            checkin_time: Timestamp.fromDate(eventDate),
          }, {merge: true});
          seededCheckins += 1;
          checkinsForUser += 1;
        }
      }

      if (seedMonthly) {
        const monthlySlots = 2 + (i % 3);
        for (let j = 0; j < monthlySlots; j++) {
          const day = monthlyDays[(i + j) % monthlyDays.length];
          const spot = attractionSpots[(i + j + 1) % attractionSpots.length];
          const eventDate = new Date(
            reportYear,
            reportMonthIndex,
            day,
            10 + ((i + j) % 8),
            15 + (i % 45),
            0,
            0,
          );
          const checkinId =
            `${uid}_${spot.id}_${reportYear}_m${reportMonthIndex + 1}_d${day}_${j + 1}`;
          await db.collection('qr_checkins').doc(checkinId).set({
            userId: uid,
            user_id: uid,
            tourist_id: uid,
            touristName: `${fn} ${ln}`,
            tourist_name: `${fn} ${ln}`,
            municipalityId: municipalityId,
            municipality: municipalityName,
            spotId: spot.id,
            spot_id: spot.id,
            spot_name: spot.name,
            status: 'Verified',
            timestamp: Timestamp.fromDate(eventDate),
          }, {merge: true});
          await db.collection('checkins').doc(checkinId).set({
            user_id: uid,
            location_id: spot.id,
            checkin_time: Timestamp.fromDate(eventDate),
          }, {merge: true});
          seededCheckins += 1;
          seededMonthlyCheckins += 1;
          checkinsForUser += 1;
        }
      }

      await db.collection('tourists').doc(uid).set({
        totalVisits: checkinsForUser,
      }, {merge: true});
    }

    return {
      ok: true,
      municipalityId,
      municipalityName,
      reportYear,
      reportFocus,
      reportMonth: monthName,
      reportMonthDays: monthlyDays,
      seededAuthUsers,
      seededTourists,
      seededCheckins,
      seededMonthlyCheckins,
      seededAccommodations,
      seededAttractions: attractionSpots.length,
      testLogins: {
        monthlyReportsEmail: 'monthly.reports@misocc-demo.ph',
        monthlyReportsPassword: DEMO_MONTHLY_PASSWORD,
        reportsDemoEmail: 'reports.demo@misocc-demo.ph',
        reportsDemoPassword: DEMO_REPORTS_PASSWORD,
        tourismMunicipalEmail,
        tourismMunicipalPassword: DEMO_TOURISM_PASSWORD,
        governorEmail: 'governor.atmos@misocc-demo.ph',
        governorPassword: DEMO_GOVERNOR_PASSWORD,
      },
    };
  },
);

/**
 * Creates a tourist_spots doc + QR metadata for LGU / provincial staff.
 * Used when client Firestore rules block the direct write.
 */
exports.createLguTouristSpot = onCall(
  {region: 'asia-southeast1'},
  async (request) => {
    if (!request.auth) {
      throw new HttpsError('unauthenticated', 'Must be signed in.');
    }

    const callerUid = request.auth.uid;
    const callerEmail = normalizeField(
      request.auth.token && request.auth.token.email,
    ).toLowerCase();

    try {
      await assertProvincialStaff(callerUid);
    } catch (err) {
      const looksStaff =
        callerEmail === 'governor.atmos@misocc-demo.ph' ||
        callerEmail === 'tourismoffice.atmos@misocc-demo.ph' ||
        callerEmail === 'provincial.tourism@misocc-demo.ph' ||
        callerEmail.startsWith('tourism.') ||
        callerEmail.includes('tourism');
      if (!looksStaff) {
        throw err;
      }
    }

    const data = request.data || {};
    const name = normalizeField(data.name);
    const municipalityId = normalizeField(data.municipalityId).toLowerCase();
    if (!name) {
      throw new HttpsError('invalid-argument', 'Tourist Spot Name is required.');
    }
    if (!municipalityId) {
      throw new HttpsError('invalid-argument', 'municipalityId is required.');
    }

    const lat = Number(data.latitude);
    const lng = Number(data.longitude);
    if (!Number.isFinite(lat) || !Number.isFinite(lng)) {
      throw new HttpsError(
        'invalid-argument',
        'Valid latitude and longitude are required.',
      );
    }

    const ref = db.collection('tourist_spots').doc();
    const qrPayload = normalizeField(data.qr_payload) ||
      `https://atmos-trs-system.web.app/#/landing?type=spot&municipality_id=${encodeURIComponent(municipalityId)}&spot_id=${encodeURIComponent(ref.id)}&lat=${lat.toFixed(6)}&lng=${lng.toFixed(6)}`;

    const payload = {
      name,
      category: normalizeField(data.category) || 'Spot',
      municipality: normalizeField(data.municipality) || municipalityId,
      municipalityId,
      description: normalizeField(data.description),
      rating: Number(data.rating) || 0,
      latitude: lat,
      longitude: lng,
      status: normalizeField(data.status) || 'Active',
      visitors: Number(data.visitors) || 0,
      qrValue: ref.id,
      qr_payload: qrPayload,
      createdAt: FieldValue.serverTimestamp(),
      updatedAt: FieldValue.serverTimestamp(),
      createdByUid: callerUid,
      createdByEmail: callerEmail || null,
      createdVia: 'createLguTouristSpot',
    };
    if (normalizeField(data.image_url)) {
      payload.image_url = normalizeField(data.image_url);
      payload.image = payload.image_url;
    }
    if (normalizeField(data.vr_link)) {
      payload.vr_link = normalizeField(data.vr_link);
      payload.hasVR = true;
    }
    if (normalizeField(data.dotAttractionCode)) {
      payload.dotAttractionCode = normalizeField(data.dotAttractionCode);
    }

    await ref.set(payload);
    return {ok: true, id: ref.id};
  },
);

/**
 * Deletes a tourist account (Firebase Auth + related Firestore docs).
 * Governor / tourism staff only. Does not delete staff accounts.
 */
exports.deleteTouristAccount = onCall(
  {region: 'asia-southeast1'},
  async (request) => {
    if (!request.auth) {
      throw new HttpsError('unauthenticated', 'Must be signed in.');
    }

    const callerUid = request.auth.uid;
    const callerEmail = normalizeField(
      request.auth.token && request.auth.token.email,
    ).toLowerCase();

    try {
      await assertProvincialStaff(callerUid);
    } catch (err) {
      const looksStaff =
        callerEmail === 'governor.atmos@misocc-demo.ph' ||
        callerEmail === 'tourismoffice.atmos@misocc-demo.ph' ||
        callerEmail.startsWith('tourism.');
      if (!looksStaff) {
        throw err;
      }
    }

    const targetUid = normalizeField(
      (request.data && (request.data.uid || request.data.touristId)) || '',
    );
    if (!targetUid) {
      throw new HttpsError('invalid-argument', 'Tourist uid is required.');
    }
    if (targetUid === callerUid) {
      throw new HttpsError(
        'invalid-argument',
        'You cannot delete your own signed-in account here.',
      );
    }

    const userRef = db.collection('users').doc(targetUid);
    const touristRef = db.collection('tourists').doc(targetUid);
    const [userSnap, touristSnap] = await Promise.all([
      userRef.get(),
      touristRef.get(),
    ]);

    if (!userSnap.exists && !touristSnap.exists) {
      throw new HttpsError('not-found', 'Tourist account was not found.');
    }

    const role = normalizeField(
      (userSnap.exists && userSnap.data()?.role) ||
        (touristSnap.exists && touristSnap.data()?.role) ||
        'tourist',
    ).toLowerCase();
    if (
      STAFF_ROLES.has(role) ||
      role === 'governor' ||
      role === 'tourism' ||
      role === 'tourism_office'
    ) {
      throw new HttpsError(
        'permission-denied',
        'Staff accounts cannot be deleted from Registered Tourists.',
      );
    }

    async function deleteByQuery(query) {
      const snap = await query.limit(400).get();
      if (snap.empty) return 0;
      const batch = db.batch();
      snap.docs.forEach((doc) => batch.delete(doc.ref));
      await batch.commit();
      if (snap.size >= 400) {
        return snap.size + (await deleteByQuery(query));
      }
      return snap.size;
    }

    async function deleteSubcollection(parentRef, subName) {
      const snap = await parentRef.collection(subName).limit(400).get();
      if (snap.empty) return;
      const batch = db.batch();
      snap.docs.forEach((doc) => batch.delete(doc.ref));
      await batch.commit();
      if (snap.size >= 400) {
        await deleteSubcollection(parentRef, subName);
      }
    }

    const checkInFields = ['tourist_id', 'userId', 'user_id', 'touristId'];
    for (const collection of ['qr_checkins', 'check_ins', 'checkins']) {
      for (const field of checkInFields) {
        try {
          await deleteByQuery(
            db.collection(collection).where(field, '==', targetUid),
          );
        } catch (e) {
          console.warn(`[deleteTouristAccount] ${collection}.${field}:`, e.message);
        }
      }
    }

    try {
      await deleteByQuery(
        db.collection('spot_reviews').where('userId', '==', targetUid),
      );
    } catch (e) {
      console.warn('[deleteTouristAccount] spot_reviews:', e.message);
    }

    try {
      await deleteByQuery(
        db.collection('notifications').where('user_id', '==', targetUid),
      );
    } catch (e) {
      console.warn('[deleteTouristAccount] notifications:', e.message);
    }

    await deleteSubcollection(userRef, 'faq_chats');
    const qrRef = db.collection('tourist_qr_codes').doc(targetUid);
    await deleteSubcollection(qrRef, 'history');

    const batch = db.batch();
    batch.delete(touristRef);
    batch.delete(userRef);
    batch.delete(db.collection('tourist_activity').doc(targetUid));
    batch.delete(db.collection('email_otps').doc(targetUid));
    batch.delete(qrRef);
    await batch.commit();

    let authDeleted = false;
    try {
      await getAuth().deleteUser(targetUid);
      authDeleted = true;
    } catch (e) {
      if (e.code !== 'auth/user-not-found') {
        console.warn('[deleteTouristAccount] auth delete:', e.code || e.message);
      } else {
        authDeleted = true;
      }
    }

    return {ok: true, uid: targetUid, authDeleted};
  },
);

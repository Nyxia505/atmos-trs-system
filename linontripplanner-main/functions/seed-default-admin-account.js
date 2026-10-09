/**
 * Seeds default admin: OPTACA@gmail.com / admin123
 * - Firebase Auth user
 * - admin_accounts/{docId}
 * - users/{uid} with role admin + custom claims
 */
const admin = require("firebase-admin");

const DEFAULT_ADMIN = {
  email: "OPTACA@gmail.com",
  emailLower: "optaca@gmail.com",
  password: "admin123",
  role: "admin",
  active: true,
};

function adminAccountDocId(email) {
  return String(email || "")
    .trim()
    .toLowerCase()
    .replace(/@/g, "_at_")
    .replace(/\./g, "_")
    .replace(/[^a-z0-9_]+/g, "");
}

async function seedDefaultAdminAccount() {
  const db = admin.firestore();
  const docId = adminAccountDocId(DEFAULT_ADMIN.emailLower);
  const authEmail = DEFAULT_ADMIN.emailLower;

  let userRecord;
  try {
    userRecord = await admin.auth().getUserByEmail(authEmail);
    await admin.auth().updateUser(userRecord.uid, {
      password: DEFAULT_ADMIN.password,
      emailVerified: true,
      displayName: userRecord.displayName || "Admin",
    });
  } catch (e) {
    if (e.code === "auth/user-not-found") {
      userRecord = await admin.auth().createUser({
        email: authEmail,
        password: DEFAULT_ADMIN.password,
        emailVerified: true,
        displayName: "Admin",
      });
    } else {
      throw e;
    }
  }

  const uid = userRecord.uid;
  const now = admin.firestore.FieldValue.serverTimestamp();

  await db
    .collection("admin_accounts")
    .doc(docId)
    .set(
      {
        email: DEFAULT_ADMIN.email,
        emailLower: DEFAULT_ADMIN.emailLower,
        password: DEFAULT_ADMIN.password,
        role: DEFAULT_ADMIN.role,
        active: DEFAULT_ADMIN.active,
        firebaseUid: uid,
        updatedAt: now,
        createdAt: now,
      },
      { merge: true },
    );

  await db
    .collection("users")
    .doc(uid)
    .set(
      {
        email: DEFAULT_ADMIN.email,
        emailLower: DEFAULT_ADMIN.emailLower,
        role: "admin",
        rolePermanent: true,
        firebaseUid: uid,
        fullName: "Admin",
        name: "Admin",
        updatedAt: now,
      },
      { merge: true },
    );

  await admin.auth().setCustomUserClaims(uid, {
    role: "admin",
    admin: true,
    municipal_manager: false,
    staff: true,
  });

  return {
    uid,
    email: DEFAULT_ADMIN.email,
    adminAccountDocId: docId,
    collection: "admin_accounts",
  };
}

module.exports = { seedDefaultAdminAccount, DEFAULT_ADMIN, adminAccountDocId };

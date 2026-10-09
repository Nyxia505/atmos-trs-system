/**
 * Run locally (Admin SDK): node run-seed-admin-account.js
 * Requires: firebase login OR GOOGLE_APPLICATION_CREDENTIALS
 */
const admin = require("firebase-admin");
const { seedDefaultAdminAccount } = require("./seed-default-admin-account");

if (!admin.apps.length) {
  admin.initializeApp({
    projectId: process.env.GCLOUD_PROJECT || "atmos-trs-system",
  });
}

seedDefaultAdminAccount()
  .then((r) => {
    console.log("Admin seeded:", JSON.stringify(r, null, 2));
    process.exit(0);
  })
  .catch((e) => {
    console.error(e);
    process.exit(1);
  });

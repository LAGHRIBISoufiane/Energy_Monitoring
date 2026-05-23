/**
 * One-time migration: copy Firebase Auth displayName → Firestore users/{uid}.displayName
 *
 * Prerequisites:
 *   1. Download a service account key from:
 *      Firebase Console → Project Settings → Service accounts → Generate new private key
 *      Save it as: Energy_Monitoring/scripts/serviceAccountKey.json
 *
 *   2. npm install firebase-admin   (run once in this folder)
 *
 * Run:
 *   node scripts/migrate_displaynames.js
 */

const admin = require('firebase-admin');
const path  = require('path');

const KEY_PATH = path.join(__dirname, 'serviceAccountKey.json');

admin.initializeApp({
  credential: admin.credential.cert(require(KEY_PATH)),
});

const auth      = admin.auth();
const firestore = admin.firestore();

async function migrateAll() {
  let pageToken;
  let updated = 0;
  let skipped = 0;

  console.log('Starting displayName migration…');

  do {
    const listResult = await auth.listUsers(1000, pageToken);
    pageToken = listResult.pageToken;

    const batch = firestore.batch();
    let batchSize = 0;

    for (const user of listResult.users) {
      const authDisplayName = (user.displayName || '').trim();
      if (!authDisplayName) {
        skipped++;
        continue; // no name in Auth either — nothing to migrate
      }

      const ref = firestore.collection('users').doc(user.uid);
      const snap = await ref.get();

      const existingDisplayName = snap.exists
        ? ((snap.data().displayName || '').trim())
        : '';

      // Only write if Firestore doesn't already have a non-empty displayName
      if (!existingDisplayName) {
        console.log(`  Updating ${user.email || user.uid}  →  "${authDisplayName}"`);
        batch.set(
          ref,
          { displayName: authDisplayName },
          { merge: true } // don't overwrite other fields
        );
        batchSize++;
        updated++;
      } else {
        skipped++;
      }
    }

    if (batchSize > 0) await batch.commit();

  } while (pageToken);

  console.log(`\nDone. Updated: ${updated}  Skipped (already set or no name): ${skipped}`);
}

migrateAll().catch(err => {
  console.error('Migration failed:', err.message);
  process.exit(1);
});

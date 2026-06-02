/**
 * One-time migration: move resolution attachments to their own Firestore fields.
 *
 * OLD behaviour: when resolving a task, the attachment was saved as
 *   attachmentBase64 / attachmentName  (same keys as the creation attachment,
 *   overwriting it).
 *
 * NEW behaviour:
 *   Creation attachment  → attachmentBase64        / attachmentName
 *   Resolution attachment → resolvedAttachmentBase64 / resolvedAttachmentName
 *
 * This script targets documents that are "resolved" and have attachmentBase64
 * but do NOT yet have resolvedAttachmentBase64. For those, the stored
 * attachmentBase64 is the resolution file (the last write won), so we:
 *   1. Copy  attachmentBase64  → resolvedAttachmentBase64
 *   2. Copy  attachmentName    → resolvedAttachmentName
 *   3. Delete the old fields (attachmentBase64 / attachmentName) so they
 *      don't appear as a creation attachment on these old records.
 *
 * Prerequisites:
 *   1. Place your service account key at:
 *        Energy_Monitoring/scripts/serviceAccountKey.json
 *   2. npm install firebase-admin   (run once in this folder)
 *
 * Run (from the Energy_Monitoring/scripts folder):
 *   node migrate_attachments.js
 */

const admin = require('firebase-admin');
const path  = require('path');

const KEY_PATH = path.join(__dirname, 'serviceAccountKey.json');

admin.initializeApp({
  credential: admin.credential.cert(require(KEY_PATH)),
});

const db = admin.firestore();

async function migrate() {
  console.log('Querying resolved maintenance_logs with old attachment fields…');

  // Fetch all resolved docs that have attachmentBase64 but NOT resolvedAttachmentBase64
  const snapshot = await db.collection('maintenance_logs')
    .where('status', '==', 'resolved')
    .get();

  let migrated = 0;
  let skipped  = 0;

  const BATCH_LIMIT = 400; // Firestore batch max is 500
  let batch     = db.batch();
  let batchSize = 0;

  for (const doc of snapshot.docs) {
    const data = doc.data();

    // Skip if already migrated or has no old attachment
    if (!data.attachmentBase64 || data.resolvedAttachmentBase64) {
      skipped++;
      continue;
    }

    const ref = doc.ref;
    batch.update(ref, {
      resolvedAttachmentBase64: data.attachmentBase64,
      resolvedAttachmentName:   data.attachmentName ?? null,
      attachmentBase64:         admin.firestore.FieldValue.delete(),
      attachmentName:           admin.firestore.FieldValue.delete(),
    });

    migrated++;
    batchSize++;

    if (batchSize >= BATCH_LIMIT) {
      await batch.commit();
      console.log(`  Committed batch of ${batchSize}`);
      batch     = db.batch();
      batchSize = 0;
    }
  }

  if (batchSize > 0) {
    await batch.commit();
    console.log(`  Committed final batch of ${batchSize}`);
  }

  console.log(`\nDone. Migrated: ${migrated}  Skipped (no attachment / already done): ${skipped}`);
}

migrate().catch(err => {
  console.error('Migration failed:', err);
  process.exit(1);
});

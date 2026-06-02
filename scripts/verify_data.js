// verify_data.js -- Use Firebase Admin SDK to count sensor_readings documents
'use strict';

// Firebase Admin needs service account credentials, but we can try with app default credentials
// or use the token-based approach
const admin = require('firebase-admin');

// Try to use Application Default Credentials (if they exist)
// Or fall back to checking environment
try {
  admin.initializeApp({
    credential: admin.credential.applicationDefault(),
    projectId: 'ocp-energy-monitor',
  });
} catch (e) {
  console.error('Failed to init with ADC:', e.message.substring(0, 100));
  // Try with no credentials (might work for admin operations with owner token)
  process.exit(1);
}

async function main() {
  const db = admin.firestore();
  
  console.log('Counting documents in sensor_readings...');
  
  // Count by unit
  for (const unitId of ['KOFERT_Unit_1', 'KOFERT_Unit_2', 'KOFERT_Unit_3']) {
    try {
      const snapshot = await db.collection('sensor_readings')
        .where('unitId', '==', unitId)
        .count()
        .get();
      console.log(`  ${unitId}: ${snapshot.data().count} documents`);
    } catch (e) {
      console.log(`  ${unitId}: ERROR - ${e.message.substring(0, 100)}`);
    }
  }
  
  // Check a specific date range (last 30 days)
  console.log('\nQuerying last 30 days for KOFERT_Unit_1...');
  const since = new Date(Date.now() - 30 * 24 * 60 * 60 * 1000);
  try {
    const snap = await db.collection('sensor_readings')
      .where('unitId', '==', 'KOFERT_Unit_1')
      .where('timestamp', '>', admin.firestore.Timestamp.fromDate(since))
      .orderBy('timestamp')
      .limit(3)
      .get();
    console.log(`  Found ${snap.size} docs (showing first 3)`);
    for (const doc of snap.docs) {
      const d = doc.data();
      console.log(`  - ${d.unitId} at ${d.timestamp?.toDate()?.toISOString()}`);
    }
  } catch (e) {
    console.log('  ERROR:', e.message.substring(0, 200));
  }
}

main().then(() => process.exit(0)).catch(e => { console.error(e); process.exit(1); });

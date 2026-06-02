// create_indexes.js -- Create composite Firestore indexes via REST API
'use strict';

const https = require('https');
const fs    = require('fs');
const path  = require('path');

const PROJECT_ID = 'ocp-energy-monitor';
const CRED_FILE  = path.join(process.env.USERPROFILE, '.config', 'configstore', 'firebase-tools.json');

function getOAuthToken() {
  const tokens = JSON.parse(fs.readFileSync(CRED_FILE, 'utf8')).tokens || {};
  if (!tokens.access_token) { console.error('No access_token. Run: npx firebase login'); process.exit(1); }
  const exp = new Date(tokens.expires_at);
  if (exp < new Date()) { console.error('Token expired at ' + exp.toISOString()); process.exit(1); }
  console.log('Token valid until ' + exp.toISOString());
  return tokens.access_token;
}

function request(method, hostname, urlPath, body, token) {
  return new Promise((resolve, reject) => {
    const bodyStr = body ? JSON.stringify(body) : '';
    const headers = { 'Content-Type': 'application/json' };
    if (bodyStr) headers['Content-Length'] = Buffer.byteLength(bodyStr);
    if (token) headers['Authorization'] = 'Bearer ' + token;
    const req = https.request({ hostname, path: urlPath, method, headers }, (res) => {
      let data = '';
      res.on('data', c => data += c);
      res.on('end', () => {
        try { resolve({ status: res.statusCode, body: JSON.parse(data) }); }
        catch { resolve({ status: res.statusCode, body: data }); }
      });
    });
    req.on('error', reject);
    if (bodyStr) req.write(bodyStr);
    req.end();
  });
}

// Index definitions matching firestore.indexes.json
const INDEXES = [
  {
    collection: 'sensor_readings',
    fields: [
      { fieldPath: 'unitId',    order: 'ASCENDING' },
      { fieldPath: 'timestamp', order: 'ASCENDING' },
    ],
  },
  {
    collection: 'sensor_readings',
    fields: [
      { fieldPath: 'unitId',    order: 'ASCENDING' },
      { fieldPath: 'timestamp', order: 'DESCENDING' },
    ],
  },
  {
    collection: 'maintenance_logs',
    fields: [
      { fieldPath: 'unitId',    order: 'ASCENDING' },
      { fieldPath: 'timestamp', order: 'DESCENDING' },
    ],
  },
  {
    collection: 'maintenance_logs',
    fields: [
      { fieldPath: 'assignedToUid', order: 'ASCENDING' },
      { fieldPath: 'resolved',      order: 'ASCENDING' },
    ],
  },
  {
    collection: 'alerts',
    fields: [
      { fieldPath: 'unitId',    order: 'ASCENDING' },
      { fieldPath: 'timestamp', order: 'DESCENDING' },
    ],
  },
  {
    collection: 'alerts',
    fields: [
      { fieldPath: 'type',      order: 'ASCENDING' },
      { fieldPath: 'timestamp', order: 'DESCENDING' },
    ],
  },
  {
    collection: 'invitations',
    fields: [
      { fieldPath: 'email',  order: 'ASCENDING' },
      { fieldPath: 'status', order: 'ASCENDING' },
    ],
  },
];

async function main() {
  const token = getOAuthToken();

  for (const idx of INDEXES) {
    const body = {
      queryScope: 'COLLECTION',
      fields: idx.fields,
    };
    const urlPath = `/v1/projects/${PROJECT_ID}/databases/(default)/collectionGroups/${idx.collection}/indexes`;
    const fieldsDesc = idx.fields.map(f => `${f.fieldPath}:${f.order}`).join(', ');
    process.stdout.write(`Creating index on ${idx.collection} [${fieldsDesc}]... `);
    try {
      const res = await request('POST', 'firestore.googleapis.com', urlPath, body, token);
      if (res.status === 200 || res.status === 201) {
        const state = res.body.state || 'CREATING';
        console.log(`${state} (${res.body.name?.split('/').pop()?.substring(0, 20)}...)`);
      } else if (res.status === 409) {
        // 409 = already exists
        console.log('already exists ✅');
      } else {
        console.log(`ERROR ${res.status}: ${JSON.stringify(res.body).slice(0, 200)}`);
      }
    } catch (e) {
      console.log(`FAILED: ${e.message}`);
    }
    await new Promise(r => setTimeout(r, 500));
  }

  // Also list existing indexes on sensor_readings to confirm
  console.log('\nCurrent sensor_readings indexes:');
  const listRes = await request('GET', 'firestore.googleapis.com',
    `/v1/projects/${PROJECT_ID}/databases/(default)/collectionGroups/sensor_readings/indexes`,
    null, token);
  if (listRes.status === 200) {
    const indexes = listRes.body.indexes || [];
    for (const ix of indexes) {
      const fields = (ix.fields || []).map(f => `${f.fieldPath}:${f.order}`).join(', ');
      console.log(`  [${ix.state}] ${fields}`);
    }
  } else {
    console.log('  Error listing indexes:', JSON.stringify(listRes.body).slice(0, 200));
  }
}

main().catch(console.error);

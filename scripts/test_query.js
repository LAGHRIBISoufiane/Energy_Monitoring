// test_query.js -- verify sensor_readings data exists in Firestore
// and check if the composite index is working
'use strict';

const https = require('https');
const fs    = require('fs');
const path  = require('path');

const PROJECT_ID = 'ocp-energy-monitor';
const CRED_FILE  = path.join(process.env.USERPROFILE, '.config', 'configstore', 'firebase-tools.json');

function getOAuthToken() {
  const tokens = JSON.parse(fs.readFileSync(CRED_FILE, 'utf8')).tokens || {};
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

async function main() {
  const token = getOAuthToken();

  // 1. Count documents in sensor_readings by listing a few
  console.log('1. Checking sensor_readings collection...');
  const listRes = await request('GET', 'firestore.googleapis.com',
    `/v1/projects/${PROJECT_ID}/databases/(default)/documents/sensor_readings?pageSize=5`,
    null, token);
  if (listRes.status !== 200) {
    console.error('   ERROR listing docs:', JSON.stringify(listRes.body).slice(0, 300));
    return;
  }
  const docs = listRes.body.documents || [];
  console.log(`   Found ${docs.length} docs (first page). First doc: ${docs[0]?.name?.split('/').pop()}`);

  // 2. Run a structured query with the composite filter (same as Summary screen)
  console.log('\n2. Testing composite query (unitId + timestamp range)...');
  const since30days = new Date(Date.now() - 30 * 24 * 60 * 60 * 1000).toISOString();
  const queryBody = {
    structuredQuery: {
      from: [{ collectionId: 'sensor_readings' }],
      where: {
        compositeFilter: {
          op: 'AND',
          filters: [
            { fieldFilter: { field: { fieldPath: 'unitId' }, op: 'EQUAL', value: { stringValue: 'KOFERT_Unit_1' } } },
            { fieldFilter: { field: { fieldPath: 'timestamp' }, op: 'GREATER_THAN', value: { timestampValue: since30days } } }
          ]
        }
      },
      orderBy: [{ field: { fieldPath: 'timestamp' }, direction: 'ASCENDING' }],
      limit: 10
    }
  };
  const queryRes = await request('POST', 'firestore.googleapis.com',
    `/v1/projects/${PROJECT_ID}/databases/(default)/documents:runQuery`,
    queryBody, token);
  if (queryRes.status !== 200) {
    console.error('   Query ERROR:', JSON.stringify(queryRes.body).slice(0, 500));
    return;
  }
  const results = Array.isArray(queryRes.body) ? queryRes.body.filter(r => r.document) : [];
  console.log(`   Query returned ${results.length} results`);
  if (results.length > 0) {
    const firstDoc = results[0].document;
    const ts = firstDoc.fields?.timestamp?.timestampValue || 'N/A';
    const u  = firstDoc.fields?.unitId?.stringValue || 'N/A';
    const e  = firstDoc.fields?.energy?.doubleValue || 'N/A';
    console.log(`   First: unitId=${u}, timestamp=${ts}, energy=${e}`);
    console.log('   ✅  Query WORKS - data exists and index is functional!');
  } else {
    console.log('   ⚠️  Query returned 0 results');
  }

  // 3. Check indexes
  console.log('\n3. Listing Firestore composite indexes...');
  const idxRes = await request('GET', 'firestore.googleapis.com',
    `/v1/projects/${PROJECT_ID}/databases/(default)/collectionGroups/sensor_readings/indexes`,
    null, token);
  if (idxRes.status !== 200) {
    console.error('   ERROR listing indexes:', JSON.stringify(idxRes.body).slice(0, 300));
    return;
  }
  const indexes = idxRes.body.indexes || [];
  console.log(`   Found ${indexes.length} composite indexes on sensor_readings:`);
  for (const idx of indexes) {
    const fields = (idx.fields || []).map(f => `${f.fieldPath}:${f.order}`).join(', ');
    console.log(`   - [${idx.state}] ${fields}`);
  }
}

main().catch(console.error);

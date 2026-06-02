// import_csv_to_firestore.js
// Uses Firebase CLI stored OAuth2 token (rioshow7@gmail.com, project owner).
// Bypasses Firestore security rules entirely.
// Usage: node import_csv_to_firestore.js

"use strict";

const https = require("https");
const fs    = require("fs");
const path  = require("path");

const PROJECT_ID = "ocp-energy-monitor";
const CSV_FILE   = path.join(__dirname, "seed_sensor_readings.csv");
const CRED_FILE  = path.join(process.env.USERPROFILE, ".config", "configstore", "firebase-tools.json");
const BATCH_SIZE = 400;

function getOAuthToken() {
  if (!fs.existsSync(CRED_FILE)) { console.error("Cred file not found: " + CRED_FILE); process.exit(1); }
  const tokens = JSON.parse(fs.readFileSync(CRED_FILE, "utf8")).tokens || {};
  if (!tokens.access_token) { console.error("No access_token. Run: npx firebase-tools login"); process.exit(1); }
  const exp = new Date(tokens.expires_at);
  if (exp < new Date()) { console.error("Token expired at " + exp.toISOString() + ". Run: npx firebase-tools login"); process.exit(1); }
  console.log("OAuth token valid until " + exp.toISOString());
  return tokens.access_token;
}

function postJson(hostname, urlPath, body, token) {
  return new Promise((resolve, reject) => {
    const bodyStr = JSON.stringify(body);
    const headers = { "Content-Type": "application/json", "Content-Length": Buffer.byteLength(bodyStr) };
    if (token) headers["Authorization"] = "Bearer " + token;
    const req = https.request({ hostname, path: urlPath, method: "POST", headers }, (res) => {
      let data = "";
      res.on("data", c => data += c);
      res.on("end", () => {
        try {
          const parsed = JSON.parse(data);
          if (res.statusCode >= 400) reject(new Error("HTTP " + res.statusCode + ": " + JSON.stringify(parsed).slice(0, 400)));
          else resolve(parsed);
        } catch { reject(new Error("Parse error HTTP " + res.statusCode + ": " + data.slice(0, 200))); }
      });
    });
    req.on("error", reject);
    req.write(bodyStr);
    req.end();
  });
}

function parseCSV(content) {
  const lines   = content.trim().split("\n");
  const headers = lines[0].split(",").map(h => h.trim());
  return lines.slice(1).map(line => {
    const vals = line.split(",");
    const obj  = {};
    headers.forEach((h, i) => { obj[h] = (vals[i] || "").trim(); });
    return obj;
  });
}

const NUMERIC = ["voltage","current","powerFactor","power","energy","frequency","apparentPower","reactivePower","fanSpeed","waterLevel"];

function toFields(row) {
  const tsIso = row.timestamp.replace(" ", "T") + ".000Z";
  const fields = {
    unitId:    { stringValue:    row.unitId },
    timestamp: { timestampValue: tsIso },
    loggedAt:  { timestampValue: new Date().toISOString() },
  };
  for (const f of NUMERIC) {
    if (row[f] !== "" && row[f] != null) fields[f] = { doubleValue: parseFloat(row[f]) };
  }
  return fields;
}

async function main() {
  process.stdout.write("Loading OAuth token... ");
  const token = getOAuthToken();
  console.log("OK");

  process.stdout.write("Reading CSV... ");
  const rows = parseCSV(fs.readFileSync(CSV_FILE, "utf8"));
  console.log("OK  " + rows.length + " rows");

  const START_OFFSET = 19600;  // Resume from row 19600 (Unit 3 remaining)
  const total        = rows.length;
  const totalBatches = Math.ceil((total - START_OFFSET) / BATCH_SIZE);
  let written = 0;
  console.log("Resuming from row " + START_OFFSET + ", " + (total - START_OFFSET) + " rows remaining (" + totalBatches + " batches)...\n");

  for (let i = START_OFFSET; i < total; i += BATCH_SIZE) {
    const chunk  = rows.slice(i, i + BATCH_SIZE);
    const batchN = Math.floor(i / BATCH_SIZE) + 1;
    const writes = chunk.map(row => ({
      update: {
        name:   "projects/" + PROJECT_ID + "/databases/(default)/documents/sensor_readings/" + row.unitId + "_" + row.timestamp.replace(/[\s:]/g, "-"),
        fields: toFields(row),
      }
    }));
    try {
      await postJson("firestore.googleapis.com", "/v1/projects/" + PROJECT_ID + "/databases/(default)/documents:batchWrite", { writes }, token);
      written += chunk.length;
      process.stdout.write("\r  Batch " + batchN + "/" + totalBatches + " -- " + written + "/" + total + " (" + Math.round(written/total*100) + "%)");
    } catch (e) {
      console.error("\n  Batch " + batchN + " failed: " + e.message);
      process.exit(1);
    }
    await new Promise(r => setTimeout(r, 500));
  }
  console.log("\n\nDone -- " + written + " documents written to Firestore!");
}

main();

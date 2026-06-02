/**
 * Generate seed_sensor_readings.csv — 30 days of realistic data for all 3 units.
 * No Firebase dependency — pure Node.js.
 *
 * Run:
 *   node scripts/generate_seed_csv.js
 *
 * Output:
 *   scripts/seed_sensor_readings.csv
 */

'use strict';

const fs   = require('fs');
const path = require('path');

const DAYS_BACK    = 30;
const INTERVAL_MIN = 5;

// ── Unit profiles ──────────────────────────────────────────────────────────────
const UNITS = {
  KOFERT_Unit_1: {
    type: 'AC',
    voltageBase: 220,  voltageNoise: 6,
    currentBase: 0.22, currentVariance: 0.08,   // Realistic: ~40-50W lamp at 220V AC
    pfBase: 0.92,      pfNoise: 0.05,
    freqBase: 50.0,    freqNoise: 0.08,
    energyStartMwh: 52000,
  },
  KOFERT_Unit_2: {
    type: 'DC_FAN',
    voltageBase: 5.0,  voltageNoise: 0.18,
    currentBase: 0.15, currentVariance: 0.10,
    pfBase: 0.98,      pfNoise: 0.01,
    fanSpeedBase: 55,  fanSpeedVariance: 30,
  },
  KOFERT_Unit_3: {
    type: 'DC_PUMP',
    voltageBase: 5.0,  voltageNoise: 0.15,
    currentBase: 0.22, currentVariance: 0.12,
    pfBase: 0.97,      pfNoise: 0.01,
    waterLevelBase: 65, waterLevelVariance: 28,
  },
};

function noise(base, amount) { return base + (Math.random() - 0.5) * 2 * amount; }

function loadFactor(dt) {
  const h = dt.getHours(), dow = dt.getDay();
  const isWeekday = dow >= 1 && dow <= 5;
  if (!isWeekday) return 0.20 + Math.random() * 0.25;
  if (h >= 8  && h < 12) return 0.70 + Math.random() * 0.30;
  if (h >= 12 && h < 14) return 0.50 + Math.random() * 0.25;
  if (h >= 14 && h < 18) return 0.65 + Math.random() * 0.30;
  if (h >= 6  && h < 8 ) return 0.30 + Math.random() * 0.25;
  if (h >= 18 && h < 21) return 0.25 + Math.random() * 0.25;
  return 0.05 + Math.random() * 0.15;
}

function generateRow(unitId, profile, ts, energyAcc) {
  const lf = loadFactor(ts);
  const isoTs = ts.toISOString().replace('T', ' ').substring(0, 19);

  if (profile.type === 'AC') {
    const v  = +noise(profile.voltageBase, profile.voltageNoise).toFixed(2);
    const i  = +Math.max(0.08, profile.currentBase * lf + noise(0, profile.currentVariance * 0.25)).toFixed(4);
    const pf = +Math.min(0.995, Math.max(0.74, noise(profile.pfBase, profile.pfNoise))).toFixed(4);
    const p  = +(v * i * pf).toFixed(2);
    const ap = +(v * i).toFixed(2);
    const rp = +Math.sqrt(Math.max(0, ap * ap - p * p)).toFixed(2);
    const incMwh = p * (INTERVAL_MIN / 60) * 1000;
    const newAcc = +(energyAcc + incMwh).toFixed(2);
    const freq = +noise(profile.freqBase, profile.freqNoise).toFixed(2);
    return {
      row: [unitId, isoTs, v, i, pf, p, newAcc, freq, ap, rp, '', ''],
      nextEnergy: newAcc,
    };
  } else {
    const v  = +Math.max(0.5, noise(profile.voltageBase, profile.voltageNoise)).toFixed(4);
    const i  = +Math.max(0.001, profile.currentBase * lf + noise(0, profile.currentVariance * 0.3)).toFixed(5);
    const pf = +Math.min(1.0, Math.max(0.90, noise(profile.pfBase, profile.pfNoise))).toFixed(4);
    const p  = +(v * i).toFixed(5);
    const ap = p;
    const fanSpeed   = profile.type === 'DC_FAN'
      ? +Math.min(100, Math.max(0, profile.fanSpeedBase + noise(0, profile.fanSpeedVariance) * lf)).toFixed(1)
      : '';
    const waterLevel = profile.type === 'DC_PUMP'
      ? Math.round(Math.min(100, Math.max(0, profile.waterLevelBase + noise(0, profile.waterLevelVariance) * (1 - lf * 0.5))))
      : '';
    return {
      row: [unitId, isoTs, v, i, pf, p, '', '', ap, 0, fanSpeed, waterLevel],
      nextEnergy: 0,
    };
  }
}

// ── Main ───────────────────────────────────────────────────────────────────────
const nowMs      = Date.now();
const startMs    = nowMs - DAYS_BACK * 24 * 60 * 60 * 1000;
const intervalMs = INTERVAL_MIN * 60 * 1000;
const stepsPerUnit = Math.floor((nowMs - startMs) / intervalMs);
const totalRows    = Object.keys(UNITS).length * stepsPerUnit;

console.log(`Generating ~${totalRows.toLocaleString()} rows…`);

const header = 'unitId,timestamp,voltage,current,powerFactor,power,energy,frequency,apparentPower,reactivePower,fanSpeed,waterLevel';
const lines  = [header];

for (const [unitId, profile] of Object.entries(UNITS)) {
  let energyAcc = profile.energyStartMwh || 0;
  let count = 0;
  for (let t = startMs; t < nowMs; t += intervalMs) {
    const { row, nextEnergy } = generateRow(unitId, profile, new Date(t), energyAcc);
    energyAcc = nextEnergy;
    lines.push(row.join(','));
    count++;
  }
  console.log(`  ✓  ${unitId}: ${count} rows`);
}

const outPath = path.join(__dirname, 'seed_sensor_readings.csv');
fs.writeFileSync(outPath, lines.join('\n'), 'utf8');
const sizeMb = (fs.statSync(outPath).size / 1048576).toFixed(1);
console.log(`\n✅  Written: ${outPath}  (${sizeMb} MB, ${lines.length - 1} data rows)`);

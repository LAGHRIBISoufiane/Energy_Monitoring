// Scheduled Energy Reports — Firebase Cloud Functions
//
// Three scheduled functions:
//   1. scheduledDailyReport   — every day at 06:00 Casablanca (if frequency='daily')
//   2. scheduledWeeklyReport  — every Monday at 06:00 Casablanca (if frequency='weekly')
//   3. scheduledMonthlyReport — 1st of every month at 07:00 Casablanca (always on)
//
// Setup (one-time, requires Blaze plan):
//   firebase functions:secrets:set EMAILJS_PRIVATE_KEY
//   (paste your EmailJS private key from Dashboard → Account → Security)

const { onSchedule } = require('firebase-functions/v2/scheduler');
const { defineSecret } = require('firebase-functions/params');
const { initializeApp } = require('firebase-admin/app');
const { getFirestore, Timestamp } = require('firebase-admin/firestore');

initializeApp();

const emailjsPrivateKey = defineSecret('EMAILJS_PRIVATE_KEY');

const EMAILJS_SERVICE_ID  = 'service_1tovyp1';
const EMAILJS_TEMPLATE_ID = 'template_9cy6uou';
const EMAILJS_PUBLIC_KEY  = 'mD7lZMFFUPuDZlNRf';

const UNITS    = ['KOFERT_Unit_1', 'KOFERT_Unit_2', 'KOFERT_Unit_3'];
const REGION   = 'us-central1';
const TIMEZONE = 'Africa/Casablanca';

// ─────────────────────────────────────────────────────────────────────────────
// 1. Daily report — fires every day at 06:00, sends only if frequency='daily'
// ─────────────────────────────────────────────────────────────────────────────
exports.scheduledDailyReport = onSchedule(
  { schedule: '0 6 * * *', timeZone: TIMEZONE, secrets: [emailjsPrivateKey], region: REGION },
  async (_event) => {
    const db     = getFirestore();
    const config = await readConfig(db);
    if (!config || !config.enabled || config.frequency !== 'daily') return;

    const now    = new Date();
    const cutoff = new Date(now.getTime() - 24 * 60 * 60 * 1000);
    await sendReport(db, config, now, cutoff, 'Rapport Quotidien (24h)', emailjsPrivateKey.value());
  }
);

// ─────────────────────────────────────────────────────────────────────────────
// 2. Weekly report — fires every Monday at 06:00, sends only if frequency='weekly'
// ─────────────────────────────────────────────────────────────────────────────
exports.scheduledWeeklyReport = onSchedule(
  { schedule: '0 6 * * 1', timeZone: TIMEZONE, secrets: [emailjsPrivateKey], region: REGION },
  async (_event) => {
    const db     = getFirestore();
    const config = await readConfig(db);
    if (!config || !config.enabled || config.frequency !== 'weekly') return;

    const now    = new Date();
    const cutoff = new Date(now.getTime() - 7 * 24 * 60 * 60 * 1000);
    await sendReport(db, config, now, cutoff, 'Rapport Hebdomadaire (7j)', emailjsPrivateKey.value());
  }
);

// ─────────────────────────────────────────────────────────────────────────────
// 3. Monthly report — fires on the 1st of every month at 07:00 (always on)
// ─────────────────────────────────────────────────────────────────────────────
exports.scheduledMonthlyReport = onSchedule(
  { schedule: '0 7 1 * *', timeZone: TIMEZONE, secrets: [emailjsPrivateKey], region: REGION },
  async (_event) => {
    const db     = getFirestore();
    const config = await readConfig(db);
    // Respects only the global enabled toggle — independent of frequency setting.
    if (!config || !config.enabled) return;

    const now              = new Date();
    const firstOfThisMonth = new Date(now.getFullYear(), now.getMonth(), 1);
    const firstOfLastMonth = new Date(now.getFullYear(), now.getMonth() - 1, 1);
    const MONTH_NAMES      = [
      'Janvier','Février','Mars','Avril','Mai','Juin',
      'Juillet','Août','Septembre','Octobre','Novembre','Décembre',
    ];
    const monthLabel = `${MONTH_NAMES[firstOfLastMonth.getMonth()]} ${firstOfLastMonth.getFullYear()}`;

    await sendReport(
      db, config,
      firstOfThisMonth, firstOfLastMonth,
      `Rapport Mensuel — ${monthLabel}`,
      emailjsPrivateKey.value(),
      /* isMonthly */ true,
    );
  }
);

// ─────────────────────────────────────────────────────────────────────────────
// Shared helpers
// ─────────────────────────────────────────────────────────────────────────────

/** Read config/autoReport; returns null if missing. */
async function readConfig(db) {
  const snap = await db.collection('config').doc('autoReport').get();
  if (!snap.exists) {
    console.log('config/autoReport not found — skipping.');
    return null;
  }
  return snap.data();
}

/** Collect all registered user emails from Firestore. */
async function collectEmails(db) {
  const snap   = await db.collection('users').get();
  const emails = new Set();
  snap.forEach((doc) => {
    const email = (doc.data().email || '').trim();
    if (email.includes('@')) emails.add(email);
  });
  return emails;
}

const dateStr = (d) =>
  `${String(d.getDate()).padStart(2,'0')}/${String(d.getMonth()+1).padStart(2,'0')}/${d.getFullYear()}`;

const timeStr = (d) =>
  `${dateStr(d)} ${String(d.getHours()).padStart(2,'0')}:${String(d.getMinutes()).padStart(2,'0')}`;

/**
 * Build report HTML and email all registered users.
 * @param {boolean} isMonthly  Skip updating lastSentMs (monthly has its own fixed schedule).
 */
async function sendReport(db, config, now, cutoff, periodLabel, privateKey, isMonthly = false) {
  const tariffRate = config.tariffRate || 1.15;

  const emails = await collectEmails(db);
  if (emails.size === 0) {
    console.log(`[${periodLabel}] No registered emails — skipping.`);
    return;
  }
  console.log(`[${periodLabel}] Sending to ${emails.size} recipient(s): ${[...emails].join(', ')}`);

  const sections = await Promise.all(
    UNITS.map((unit) => buildUnitReport(db, unit, cutoff, now, tariffRate))
  );
  const filled = sections.filter(Boolean);
  if (filled.length === 0) {
    console.log(`[${periodLabel}] No sensor data found — skipping.`);
    return;
  }

  const subject = `${periodLabel} — ${dateStr(cutoff)} → ${dateStr(now)}`;
  const reportBody = filled.join('<hr style="border:none;border-top:1px solid #dde3f0;margin:20px 0">');
  const message =
    '<div style="font-family:Arial,Helvetica,sans-serif;max-width:620px">'
    + '<table cellpadding="0" cellspacing="0" width="100%" style="background:#0D47A1;border-radius:8px 8px 0 0">'
    + '<tr>'
    + '<td style="padding:18px 20px;vertical-align:middle;width:44px"><span style="font-size:22px;line-height:1">&#128202;</span></td>'
    + '<td style="padding:18px 4px 18px 0;vertical-align:middle">'
    + '<div style="color:#fff;font-size:17px;font-weight:700;letter-spacing:0.2px">Rapport \u00c9nerg\u00e9tique KOFERT</div>'
    + `<div style="color:rgba(255,255,255,.75);font-size:11px;margin-top:3px">${periodLabel} &middot; KOFERT JFC3</div>`
    + '</td>'
    + '<td align="right" style="padding:18px 20px 18px 0;vertical-align:middle">'
    + '<div style="color:rgba(255,255,255,.5);font-size:10px;white-space:nowrap">&#9889; KOFERT JFC3</div>'
    + '</td></tr></table>'
    + `<div style="border:1px solid #c5d9f5;border-top:none;padding:20px 16px">${reportBody}</div>`
    + '<div style="background:#e8f0fe;border:1px solid #c5d9f5;border-top:none;border-radius:0 0 8px 8px;'
    + 'padding:12px 16px;font-size:11px;color:#444;text-align:center">'
    + 'Ce rapport a \u00e9t\u00e9 g\u00e9n\u00e9r\u00e9 automatiquement par KOFERT JFC3 Energy Monitor. '
    + '<a href="https://ocp-energy-monitor.web.app" style="color:#0D47A1">ocp-energy-monitor.web.app</a>'
    + '</div></div>';

  let anySent = false;
  for (const toEmail of emails) {
    try {
      const resp = await fetch('https://api.emailjs.com/api/v1.0/email/send', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          service_id:  EMAILJS_SERVICE_ID,
          template_id: EMAILJS_TEMPLATE_ID,
          user_id:     EMAILJS_PUBLIC_KEY,
          accessToken: privateKey,
          template_params: {
            name:     periodLabel,
            time:     timeStr(now),
            to_email: toEmail,
            subject,
            message,
          },
        }),
      });
      if (resp.ok) {
        console.log(`✓ Sent to ${toEmail}`);
        anySent = true;
      } else {
        const body = await resp.text();
        console.warn(`✗ EmailJS error for ${toEmail}: ${resp.status} — ${body}`);
      }
    } catch (err) {
      console.error(`✗ Network error for ${toEmail}:`, err.message);
    }
  }

  if (anySent && !isMonthly) {
    await getFirestore().collection('config').doc('autoReport')
      .update({ lastSentMs: now.getTime() });
    console.log('lastSentMs updated.');
  }
}

/** Build an HTML stats table for one unit between cutoff and now. */
async function buildUnitReport(db, unitId, cutoff, now, tariffRate) {
  const snap = await db
    .collection('sensor_readings')
    .where('unitId', '==', unitId)
    .where('timestamp', '>=', Timestamp.fromDate(cutoff))
    .where('timestamp', '<=', Timestamp.fromDate(now))
    .orderBy('timestamp', 'desc')
    .limit(4464) // ~31 days × 24 h × 6 readings/h
    .get();

  if (snap.empty) return null;

  const docs = snap.docs.map((d) => d.data());
  const n    = docs.length;

  const avg  = (f) => docs.reduce((s, d) => s + (d[f] || 0), 0) / n;
  const sum  = (f) => docs.reduce((s, d) => s + (d[f] || 0), 0);
  const maxV = (f) => docs.reduce((m, d) => Math.max(m, d[f] || 0), 0);

  const avgVoltage     = avg('voltage');
  const avgCurrent     = avg('current');
  const avgPower       = avg('power');
  const maxPower       = maxV('power');
  const avgPf          = avg('powerFactor');
  const totalEnergyMWh = sum('energy');
  const estimatedCost  = (totalEnergyMWh / 1_000_000) * tariffRate;

  const fmtEnergy = (v) =>
    v >= 1e6 ? `${(v / 1e6).toFixed(3)} kWh`
    : v >= 1e3 ? `${(v / 1e3).toFixed(3)} Wh`
    : `${v.toFixed(2)} mWh`;

  const row = (label, value, alt, color = '') =>
    `<tr style="${alt ? 'background:#f0f5ff;' : ''}">` +
    `<td style="padding:10px 14px;border:1px solid #c5d9f5;color:#888;width:44%">${label}</td>` +
    `<td style="padding:10px 14px;border:1px solid #c5d9f5;font-weight:${color ? '600' : 'normal'};color:${color || 'inherit'}">${value}</td>` +
    `</tr>`;

  return (
    `<h3 style="margin:0 0 10px;color:#0D47A1;font-family:Arial,sans-serif;font-size:14px;border-bottom:2px solid #c5d9f5;padding-bottom:6px">${unitId}</h3>` +
    `<table style="width:100%;border-collapse:collapse;font-size:13px;font-family:Arial,sans-serif;border:1px solid #c5d9f5">` +
    row('Nombre de mesures', n,                               false) +
    row('Tension moyenne',   `${avgVoltage.toFixed(2)} V`,    true) +
    row('Courant moyen',     `${avgCurrent.toFixed(3)} A`,    false) +
    row('Puissance moyenne', `${avgPower.toFixed(2)} W`,      true,  '#1a73e8') +
    row('Puissance max',     `${maxPower.toFixed(2)} W`,      false) +
    row('FP moyen',          avgPf.toFixed(3),                true) +
    row('Énergie totale',    fmtEnergy(totalEnergyMWh),       false, '#27ae60') +
    row('Coût estimé',       `${estimatedCost.toFixed(2)} MAD`, true, '#e67e22') +
    `</table>`
  );
}

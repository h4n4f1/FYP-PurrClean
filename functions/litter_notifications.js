// functions/litter_notifications.js
//
// Two push notifications for PurrClean:
//   1. notifyCatVisit      - every time the cat visits the box and does their business
//   2. cleanOverdueCheck   - litter box not cleaned for 14 days
//
// Used from functions/index.js with:
//   Object.assign(exports, require("./litter_notifications"));

const admin = require("firebase-admin");
const { onValueCreated } = require("firebase-functions/v2/database");
const { onSchedule } = require("firebase-functions/v2/scheduler");

if (!admin.apps.length) admin.initializeApp();

const REGION = "asia-southeast1"; // same region as your Realtime Database
const DB_INSTANCE = "purrclean-124-default-rtdb";
const CHANNEL_ID = "care_reminders"; // must match the Flutter channel id

const CLEAN_AFTER_MS = 14 * 24 * 60 * 60 * 1000; // 2 weeks
const REPEAT_EVERY_MS = 24 * 60 * 60 * 1000; // re-remind daily until cleaned
const MAX_EVENT_AGE_MS = 30 * 60 * 1000; // ignore old/back-filled events

function toMs(raw) {
  if (typeof raw === "number") return raw < 1e12 ? raw * 1000 : raw;
  if (typeof raw === "string") {
    const n = Number(raw);
    if (!Number.isNaN(n)) return toMs(n);
    const d = Date.parse(raw);
    return Number.isNaN(d) ? null : d;
  }
  return null;
}

// 'urine' | 'feces' | 'both' | 'none' | 'unknown'
function outputKind(visit) {
  const raw = visit.estimatedOutputType;
  let code = null;
  if (typeof raw === "number") code = raw;
  else if (typeof raw === "string") {
    const n = Number(raw);
    if (!Number.isNaN(n)) code = n;
    else {
      const s = raw.trim().toLowerCase();
      if (s === "urine") code = 1;
      else if (s === "feces" || s === "faeces") code = 2;
      else if (s === "both") code = 3;
      else if (s === "none") code = 0;
    }
  }
  if (code === 1) return "urine";
  if (code === 2) return "feces";
  if (code === 3) return "both";
  if (code === 0) return Number(visit.depositMassGrams) > 0 ? "unknown" : "none";
  return "unknown";
}

async function pushToDevice(deviceId, prefField, { title, body, type }) {
  const db = admin.database();
  const snap = await db.ref(`devices/${deviceId}/fcmTokens`).get();
  const tokens = snap.val() || {};
  // a switch that is missing counts as ON; only an explicit false mutes it
  const list = Object.entries(tokens)
    .filter(([, v]) => v && v[prefField] !== false)
    .map(([t]) => t);
  if (!list.length) return 0;

  const res = await admin.messaging().sendEachForMulticast({
    tokens: list,
    notification: { title, body },
    data: { type },
    android: { priority: "high", notification: { channelId: CHANNEL_ID } },
  });

  const dead = [];
  res.responses.forEach((r, i) => {
    const code = r.error && r.error.code;
    if (
      code === "messaging/registration-token-not-registered" ||
      code === "messaging/invalid-registration-token"
    ) {
      dead.push(list[i]);
    }
  });
  await Promise.all(
    dead.map((t) => db.ref(`devices/${deviceId}/fcmTokens/${t}`).remove())
  );
  return res.successCount;
}

// 1) Cat visited the litter box and did their business ----------------------
exports.notifyCatVisit = onValueCreated(
  {
    ref: "/devices/{deviceId}/events/{eventId}",
    instance: DB_INSTANCE,
    region: REGION,
  },
  async (event) => {
    const { deviceId, eventId } = event.params;
    const visit = event.data.val() || {};

    const ts = toMs(visit.timestamp) ?? toMs(eventId);
    if (ts && Date.now() - ts > MAX_EVENT_AGE_MS) return; // old event

    const kind = outputKind(visit);
    if (kind === "none") return; // visited but did nothing -> no alert

    const body = {
      urine: "Your cat just peed in the litter box.",
      feces: "Your cat just pooped in the litter box.",
      both: "Your cat just peed and pooped in the litter box.",
      unknown: "Your cat just used the litter box.",
    }[kind];

    await pushToDevice(deviceId, "visit", {
      title: "Litter box visit",
      body,
      type: "visit",
    });
  }
);

// 2) Litter box not cleaned for 2 weeks ---------------------------------------
exports.cleanOverdueCheck = onSchedule(
  { schedule: "every 6 hours", region: REGION, timeZone: "Asia/Kuala_Lumpur" },
  async () => {
    const db = admin.database();
    const ids = Object.keys((await db.ref("careDevices").get()).val() || {});
    const now = Date.now();

    for (const id of ids) {
      const care = (await db.ref(`devices/${id}/care`).get()).val() || {};
      const lastClean = Number(care.last_clean);
      if (!lastClean) continue; // owner / app has not set a date yet
      if (now - lastClean < CLEAN_AFTER_MS) continue;

      const lastNotified = Number(care.notified_clean) || 0;
      if (now - lastNotified < REPEAT_EVERY_MS) continue;

      const days = Math.floor((now - lastClean) / 86400000);
      const sent = await pushToDevice(id, "clean", {
        title: "Time to clean the litter box",
        body: `The litter box hasn't been cleaned for ${days} days. Give it a good clean and tap "I cleaned it" in the app.`,
        type: "clean_overdue",
      });
      if (sent > 0) await db.ref(`devices/${id}/care/notified_clean`).set(now);
    }
  }
);
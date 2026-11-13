const { onValueCreated } = require("firebase-functions/v2/database");
const { onSchedule } = require("firebase-functions/v2/scheduler");
const admin = require("firebase-admin");
const {
  T, parseEvents, toMs, computeCareReminders, computeHealthAlerts,
} = require("./care");

// Same URL as SensorService.databaseUrl in the app.
admin.initializeApp({
  databaseURL:
    "https://purrclean-124-default-rtdb.asia-southeast1.firebasedatabase.app",
});

const REGION = "asia-southeast1"; // must match the database region
const DB_INSTANCE = "purrclean-124-default-rtdb";

/** Sends one notification to every phone that has this switch on. */
async function pushToPhones(ctx, { key, title, body, urgent, prefKey }) {
  const targets = Object.entries(ctx.tokens)
    .filter(([, info]) => !info || info[prefKey] !== false)
    .map(([token]) => token);
  if (targets.length === 0) return false;

  const res = await admin.messaging().sendEach(
    targets.map((token) => ({
      token,
      notification: { title, body },
      data: { task: key, urgent: String(!!urgent) },
      android: {
        priority: "high",
        notification: { channelId: "care_reminders", tag: key },
      },
    }))
  );

  // Drop tokens of phones that uninstalled the app.
  await Promise.all(
    res.responses.map((resp, i) => {
      const code = resp.error && resp.error.code;
      if (
        code === "messaging/registration-token-not-registered" ||
        code === "messaging/invalid-registration-token"
      ) {
        return ctx.db.ref(`${ctx.base}/fcmTokens/${targets[i]}`).remove();
      }
      return null;
    })
  );
  return true;
}

/** Litter care: clean box / waste drawer / refill. */
async function sendCareReminders(ctx) {
  for (const r of computeCareReminders(ctx.events, ctx.care, ctx.now)) {
    const last = toMs(ctx.care[`notified_${r.task}`]);
    const gap = r.urgent ? T.renotifyUrgentMs : T.renotifyMs;
    if (last !== null && ctx.now - last < gap) continue;

    const sent = await pushToPhones(ctx, {
      key: r.task, title: r.title, body: r.body, urgent: r.urgent, prefKey: r.prefKey,
    });
    if (sent) {
      await ctx.db.ref(`${ctx.base}/care/notified_${r.task}`).set(ctx.now);
    }
  }
}

/** Cat health: each alert is sent once per "sig" (what it is about). */
async function sendHealthAlerts(ctx) {
  for (const a of computeHealthAlerts(ctx.events, ctx.now)) {
    const state = ctx.healthState[a.key] || {};
    if (state.sig === a.sig) continue;
    if (state.at && ctx.now - state.at < a.minGapMs) continue;

    const sent = await pushToPhones(ctx, {
      key: a.key, title: a.title, body: a.body, urgent: a.urgent, prefKey: "health",
    });
    if (sent) {
      const rec = { sig: a.sig, at: ctx.now };
      ctx.healthState[a.key] = rec;
      await ctx.db.ref(`${ctx.base}/healthState/${a.key}`).set(rec);
    }
  }
}

async function evaluateDevice(deviceId) {
  const db = admin.database();
  const base = `devices/${deviceId}`;

  const tokensSnap = await db.ref(`${base}/fcmTokens`).get();
  const tokens = tokensSnap.val() || {};
  if (Object.keys(tokens).length === 0) return;

  const [careSnap, healthSnap, eventsSnap] = await Promise.all([
    db.ref(`${base}/care`).get(),
    db.ref(`${base}/healthState`).get(),
    db.ref(`${base}/events`).orderByKey().limitToLast(600).get(),
  ]);

  const entries = [];
  eventsSnap.forEach((child) => {
    entries.push({ key: child.key, val: child.val() });
  });

  const ctx = {
    db,
    base,
    tokens,
    care: careSnap.val() || {},
    healthState: healthSnap.val() || {},
    events: parseEvents(entries),
    now: Date.now(),
  };

  await sendCareReminders(ctx);
  await sendHealthAlerts(ctx);
}

// 1) Right after every litter box visit.
exports.onNewVisit = onValueCreated(
  {
    ref: "/devices/{deviceId}/events/{eventId}",
    instance: DB_INSTANCE,
    region: REGION,
  },
  (event) => evaluateDevice(event.params.deviceId)
);

// 2) Every hour, for the time-based rules (24 h since cleaning, litter refill,
//    low visits in the evening, no visits for 18 h).
exports.hourlyCareCheck = onSchedule(
  { schedule: "every 60 minutes", region: REGION },
  async () => {
    const snap = await admin.database().ref("careDevices").get();
    const ids = Object.keys(snap.val() || {});
    for (const id of ids) {
      try {
        await evaluateDevice(id);
      } catch (e) {
        console.error(`check failed for ${id}`, e);
      }
    }
  }
);
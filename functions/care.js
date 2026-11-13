// Pure rules (no Firebase calls) so they can be tested on their own.

const HOUR = 3600 * 1000;
const DAY = 24 * HOUR;
const UTC_OFFSET_HOURS = 8; // Malaysia. "Today" and "night" use this clock.

// Litter care: keep in sync with CareThresholds in care_reminder_service.dart
const T = {
  wasteCapacityGrams: 500,
  wasteWarnPct: 80,
  cleanAfterVisits: 6,
  cleanAfterHours: 24,
  ammoniaCleanPpm: 30,
  refillEveryDays: 7,
  renotifyMs: 6 * HOUR,
  renotifyUrgentMs: 2 * HOUR,
};

// Cat health: same numbers as behavior_insights_service.dart
const H = {
  minNormalVisits: 3,
  maxNormalVisits: 8,
  lowVisitsAfterHour: 20,
  strainingSeconds: 180,
  dangerAmmoniaPpm: 30,
  dangerOdorPercent: 80,
  heavyDepositGrams: 60,
  nightFromHour: 1,
  nightToHour: 5, // 01:00 - 04:59
  // new real-time checks
  burst1hVisits: 3,
  burst2hVisits: 4,
  noOutputVisits: 2,
  noOutputWindowMs: 3 * HOUR,
  veryLongVisitSeconds: 600,
  noVisitHours: 18,
  minEventsForPattern: 10, // in the last 7 days, before "no visits" can fire
};

/** Accepts epoch ms, epoch seconds, numeric strings or ISO-8601. */
function toMs(raw) {
  if (typeof raw === "string" && /^\d+$/.test(raw.trim())) raw = Number(raw);
  if (typeof raw === "number") {
    if (raw <= 0) return null;
    return raw < 1e11 ? raw * 1000 : raw;
  }
  if (typeof raw === "string") {
    const t = Date.parse(raw);
    return Number.isNaN(t) ? null : t;
  }
  return null;
}

function startOfTodayMs(now) {
  const shifted = new Date(now + UTC_OFFSET_HOURS * HOUR);
  shifted.setUTCHours(0, 0, 0, 0);
  return shifted.getTime() - UTC_OFFSET_HOURS * HOUR;
}

function localHour(ms) {
  return new Date(ms + UTC_OFFSET_HOURS * HOUR).getUTCHours();
}

function fmtTime(ms) {
  const d = new Date(ms + UTC_OFFSET_HOURS * HOUR);
  const hh = String(d.getUTCHours()).padStart(2, "0");
  const mm = String(d.getUTCMinutes()).padStart(2, "0");
  return `${hh}:${mm}`;
}

function plural(n, word) {
  return `${n} ${word}${n === 1 ? "" : "s"}`;
}

/** 0 none, 1 urine, 2 feces, 3 both. null when the field is missing. */
function parseOutput(raw) {
  if (raw === undefined || raw === null) return null;
  if (typeof raw === "number") return raw;
  if (typeof raw === "string") {
    if (/^\d+$/.test(raw.trim())) return Number(raw);
    switch (raw.trim().toLowerCase()) {
      case "none": return 0;
      case "urine": return 1;
      case "feces":
      case "faeces": return 2;
      case "both": return 3;
    }
  }
  return null;
}

/** entries: [{ key, val }] straight from the events node. */
function parseEvents(entries) {
  const out = [];
  for (const { key, val } of entries) {
    const v = val || {};
    const ts = toMs(v.timestamp) ?? toMs(key);
    if (ts === null) continue;
    out.push({
      id: key,
      ts,
      dwell: Number(v.dwellTimeSeconds) || 0,
      deposit: Number(v.depositMassGrams) || 0,
      nh3: Number(v.peakAmmoniaPpm) || 0,
      odor: Number(v.peakOdorIndexPct) || 0,
      output: parseOutput(v.estimatedOutputType),
    });
  }
  out.sort((a, b) => a.ts - b.ts);
  return out;
}

// ------------------------------------------------------------------------
// Litter care reminders (clean box / waste drawer / refill)
// ------------------------------------------------------------------------
function computeCareReminders(events, care, now) {
  care = care || {};
  const lastClean = toMs(care.last_clean) ?? startOfTodayMs(now);
  const lastWaste = toMs(care.last_waste) ?? startOfTodayMs(now);
  const lastRefill = toMs(care.last_refill) ?? now;

  let visits = 0;
  let highAmmonia = false;
  let wasteGrams = 0;
  for (const e of events) {
    if (e.ts > lastClean) {
      visits++;
      if (e.nh3 >= T.ammoniaCleanPpm) highAmmonia = true;
    }
    if (e.ts > lastWaste) wasteGrams += e.deposit;
  }

  const wastePct = Math.min(100, Math.round((wasteGrams / T.wasteCapacityGrams) * 100));
  const hoursSinceClean = Math.floor((now - lastClean) / HOUR);
  const daysSinceRefill = Math.floor((now - lastRefill) / DAY);
  const reminders = [];

  if (
    visits >= T.cleanAfterVisits ||
    highAmmonia ||
    (visits > 0 && hoursSinceClean >= T.cleanAfterHours)
  ) {
    let body;
    if (highAmmonia) {
      body = "Ammonia is high in the litter box. A quick scoop will freshen it up.";
    } else if (visits >= T.cleanAfterVisits) {
      body = `Your cat has used the box ${visits} times since it was last cleaned. Time for a scoop!`;
    } else {
      const since =
        hoursSinceClean < 48
          ? plural(hoursSinceClean, "hour")
          : plural(Math.floor(hoursSinceClean / 24), "day");
      body = `It's been ${since} since the litter box was last cleaned.`;
    }
    reminders.push({
      task: "cleanBox", prefKey: "clean", title: "Clean the litter box", body, urgent: false,
    });
  }

  if (wastePct >= T.wasteWarnPct) {
    const full = wastePct >= 100;
    reminders.push({
      task: "wasteDisposal",
      prefKey: "waste",
      title: full ? "Waste drawer is full" : "Waste drawer is almost full",
      body: full
        ? "Empty the drawer now to keep the box clean and odor-free."
        : `The drawer is about ${wastePct}% full. Please empty it into a sealed bag soon.`,
      urgent: full,
    });
  }

  if (daysSinceRefill >= T.refillEveryDays) {
    reminders.push({
      task: "refillLitter",
      prefKey: "refill",
      title: "Refill the litter",
      body: `The litter was last topped up ${plural(daysSinceRefill, "day")} ago. Add fresh litter so clumping and odor control keep working.`,
      urgent: daysSinceRefill >= T.refillEveryDays * 2,
    });
  }
  return reminders;
}

// ------------------------------------------------------------------------
// Cat health alerts
//   key        one slot per alert type (a new one replaces the old notification)
//   sig        what the alert is about; the same sig is never sent twice
//   minGapMs   extra wait between two sends of the same alert type
// ------------------------------------------------------------------------
function computeHealthAlerts(events, now) {
  if (events.length === 0) return [];
  const alerts = [];
  const dayStart = startOfTodayMs(now);
  const day = String(dayStart);
  const today = events.filter((e) => e.ts >= dayStart && e.ts <= now + HOUR);
  const latest = events[events.length - 1];
  const add = (a) => alerts.push({ minGapMs: 0, urgent: false, ...a });

  if (today.length > 0) {
    // 1. High visit frequency
    if (today.length > H.maxNormalVisits) {
      add({
        key: "health_visits_high", sig: day, minGapMs: 6 * HOUR,
        title: "High Visit Frequency",
        body: `${today.length} visits today (normal ${H.minNormalVisits}–${H.maxNormalVisits}). Frequent small visits can point to urinary discomfort or a UTI. Consider a vet check.`,
      });
    }

    // 2. Low visit frequency (evening check)
    if (today.length < H.minNormalVisits && localHour(now) >= H.lowVisitsAfterHour) {
      add({
        key: "health_visits_low", sig: day,
        title: "Low Visit Frequency",
        body: `Only ${plural(today.length, "visit")} today (normal ${H.minNormalVisits}–${H.maxNormalVisits}). Could mean dehydration, constipation or stress. Check your cat is eating and drinking.`,
      });
    }

    // 3 / 4. Long visits
    const longs = today.filter((e) => e.dwell >= H.strainingSeconds);
    if (longs.length >= 2) {
      const longest = Math.max(...longs.map((e) => e.dwell));
      add({
        key: "health_straining", sig: day, urgent: true, minGapMs: 6 * HOUR,
        title: "Repeated Straining",
        body: `${longs.length} long visits today (longest ${(longest / 60).toFixed(1)} min). Straining can point to constipation or a urinary problem. Call your vet if it continues.`,
      });
    } else if (longs.length === 1) {
      const e = longs[0];
      add({
        key: "health_dwell", sig: e.id,
        title: "Extended Dwell Time",
        body: `A visit lasted ${(e.dwell / 60).toFixed(1)} min at ${fmtTime(e.ts)}. Possible straining from constipation or urinary discomfort. Keep watching.`,
      });
    }

    // 6. Gas
    const gas = today.filter(
      (e) => e.nh3 >= H.dangerAmmoniaPpm || e.odor >= H.dangerOdorPercent
    );
    if (gas.length > 0) {
      const e = gas[gas.length - 1];
      add({
        key: "health_gas", sig: e.id, urgent: true,
        title: "High Ammonia / Odor Levels",
        body: `NH₃ ${e.nh3.toFixed(0)} ppm, odor ${e.odor.toFixed(0)}% at ${fmtTime(e.ts)}. Strong ammonia can mean concentrated urine (possible dehydration or kidney issue) or a dirty box. Scoop and check.`,
      });
    }

    // 7. Heavy deposit
    const heavy = today.filter((e) => e.deposit >= H.heavyDepositGrams);
    if (heavy.length > 0) {
      const e = heavy[heavy.length - 1];
      add({
        key: "health_deposit", sig: e.id,
        title: "Heavy Deposit Detected",
        body: `A ${e.deposit.toFixed(0)} g deposit at ${fmtTime(e.ts)}. Very large output can mean heavy drinking or a urinary issue. Keep an eye on it.`,
      });
    }

    // 8. Night-time elimination
    const night = today.filter((e) => {
      const h = localHour(e.ts);
      return h >= H.nightFromHour && h < H.nightToHour;
    });
    if (night.length >= 2) {
      add({
        key: "health_night", sig: day,
        title: "Night-time Elimination",
        body: `${night.length} visits between 01:00 and 05:00. Repeated night visits can be an early sign of kidney, thyroid or urinary problems.`,
      });
    }
  }

  // 23. Frequent visits in a short time
  if (now - latest.ts <= 2 * HOUR) {
    const within = (ms) => events.filter((e) => e.ts > latest.ts - ms && e.ts <= latest.ts).length;
    const n1 = within(HOUR);
    const n2 = within(2 * HOUR);
    let n = 0;
    let hours = 0;
    if (n1 >= H.burst1hVisits) { n = n1; hours = 1; }
    else if (n2 >= H.burst2hVisits) { n = n2; hours = 2; }
    if (n > 0) {
      add({
        key: "health_burst", sig: latest.id, urgent: true, minGapMs: 2 * HOUR,
        title: "Frequent Visits in a Short Time",
        body: `${n} visits in ${plural(hours, "hour")}. Constant visiting can point to a UTI or bladder irritation. Call your vet if it continues.`,
      });
    }
  }

  // 24. Visits with no output (only when the box reports the output type)
  const noOutput = events.filter(
    (e) => e.ts >= now - H.noOutputWindowMs && e.output === 0
  );
  if (noOutput.length >= H.noOutputVisits) {
    const e = noOutput[noOutput.length - 1];
    add({
      key: "health_no_output", sig: e.id, urgent: true, minGapMs: 2 * HOUR,
      title: "Visits With No Output",
      body: `${noOutput.length} visits with no output in 3 hours. This can mean a urinary blockage, which is an emergency, especially in male cats. Contact a vet now.`,
    });
  }

  // 25. Very long single visit
  const veryLong = events.filter(
    (e) => e.ts >= now - 3 * HOUR && e.dwell >= H.veryLongVisitSeconds
  );
  if (veryLong.length > 0) {
    const e = veryLong[veryLong.length - 1];
    add({
      key: "health_very_long", sig: e.id, urgent: true,
      title: "Very Long Visit",
      body: `A visit lasted ${Math.round(e.dwell / 60)} min at ${fmtTime(e.ts)}. Possible severe straining or a blockage. Check on your cat now.`,
    });
  }

  // 26. No visits for a long time (only once there is a normal pattern)
  const hoursAway = (now - latest.ts) / HOUR;
  const recentCount = events.filter((e) => e.ts >= now - 7 * DAY).length;
  if (hoursAway >= H.noVisitHours && recentCount >= H.minEventsForPattern) {
    add({
      key: "health_no_visit", sig: latest.id, urgent: true,
      title: "No Visits for a Long Time",
      body: `No litter visit for ${Math.floor(hoursAway)} hours. Possible dehydration, a blockage, or your cat avoiding the box. Check on your cat.`,
    });
  }

  return alerts;
}

module.exports = {
  T, H, HOUR, DAY, toMs, parseEvents, computeCareReminders, computeHealthAlerts,
};
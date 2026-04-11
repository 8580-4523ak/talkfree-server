"use strict";

const fs = require("fs");
const path = require("path");

const envPath = path.join(__dirname, ".env");
require("dotenv").config({ path: envPath });

const express = require("express");
const cors = require("cors");
const twilio = require("twilio");

const {
  TWILIO_ACCOUNT_SID,
  TWILIO_AUTH_TOKEN,
  TWILIO_API_KEY_SID,
  TWILIO_API_KEY_SECRET,
  TWILIO_TWIML_APP_SID,
  TWILIO_APP_SID,
  TWILIO_CALLER_ID,
  PORT = 3000,
  PUBLIC_BASE_URL = "https://talkfree-server.onrender.com",
} = process.env;

const OUTGOING_APP_SID = String(
  TWILIO_TWIML_APP_SID || TWILIO_APP_SID || "",
).trim();

const app = express();
app.use((req, res, next) => {
  console.log("Incoming:", req.method, req.url);
  next();
});
app.use(cors());
app.use(express.json());
app.use(express.urlencoded({ extended: false }));

app.get("/", (req, res) => {
  res.send("Server is alive");
});

function requireEnv(name, val) {
  if (!val || String(val).trim() === "") {
    throw new Error(`Missing env: ${name}`);
  }
}

try {
  requireEnv("TWILIO_ACCOUNT_SID", TWILIO_ACCOUNT_SID);
  requireEnv("TWILIO_AUTH_TOKEN", TWILIO_AUTH_TOKEN);
  requireEnv("TWILIO_CALLER_ID", TWILIO_CALLER_ID);
  requireEnv("TWILIO_API_KEY_SID", TWILIO_API_KEY_SID);
  requireEnv("TWILIO_API_KEY_SECRET", TWILIO_API_KEY_SECRET);
  requireEnv("TWILIO_TWIML_APP_SID or TWILIO_APP_SID", OUTGOING_APP_SID);
} catch (e) {
  console.error(e.message);
  const examplePath = path.join(__dirname, ".env.example");
  if (!fs.existsSync(envPath)) {
    console.error(`\nNo file at: ${envPath}`);
    console.error(`Copy .env.example to .env in this folder, then fill in your Twilio values.`);
  } else {
    console.error(`\nEdit ${envPath} — one or more required variables are empty.`);
  }
  if (fs.existsSync(examplePath)) {
    console.error(`Template: ${examplePath}`);
  }
  process.exit(1);
}

const twilioClient = twilio(TWILIO_ACCOUNT_SID, TWILIO_AUTH_TOKEN);

/** Optional — enables POST /grant-reward (secured credits). Set FIREBASE_SERVICE_ACCOUNT_JSON in .env */
let firebaseAdmin = null;
try {
  const faJson = process.env.FIREBASE_SERVICE_ACCOUNT_JSON;
  if (faJson) {
    const admin = require("firebase-admin");
    if (!admin.apps.length) {
      admin.initializeApp({
        credential: admin.credential.cert(JSON.parse(faJson)),
      });
    }
    firebaseAdmin = admin;
    console.log("Firebase Admin: /grant-reward enabled");
  } else {
    console.warn("FIREBASE_SERVICE_ACCOUNT_JSON unset — /grant-reward returns 503");
  }
} catch (e) {
  console.warn("Firebase Admin init failed — /grant-reward disabled:", e.message);
}

const voiceCallbackUrl = `${String(PUBLIC_BASE_URL).replace(/\/$/, "")}/voice`;

const AccessToken = twilio.jwt.AccessToken;
const VoiceGrant = AccessToken.VoiceGrant;

app.all("/voice", (req, res) => {
  console.log("🔥 Twilio hit /voice endpoint");

  res.type("text/xml");
  res.send(`     <Response>       <Say voice="alice">Hello Akash, your TalkFree server is working!</Say>     </Response>
  `);
});

app.get("/call", async (req, res) => {
  try {
    const to = req.query.to;

    if (!to) {
      return res.send("Missing ?to= number");
    }

    await twilioClient.calls.create({
      to: String(to).trim(),
      from: process.env.TWILIO_CALLER_ID,
      url: voiceCallbackUrl,
    });

    res.send("Call triggered successfully");
  } catch (err) {
    console.error(err);
    res.send("Error: " + err.message);
  }
});

app.get("/token", (req, res) => {
  const identity = String(req.query.identity || "anonymous").slice(0, 128);
  const token = new AccessToken(
    TWILIO_ACCOUNT_SID,
    TWILIO_API_KEY_SID,
    TWILIO_API_KEY_SECRET,
    { identity },
  );
  const grant = new VoiceGrant({
    outgoingApplicationSid: OUTGOING_APP_SID,
    incomingAllow: true,
  });
  token.addGrant(grant);
  res.json({ identity, token: token.toJwt() });
});

app.post("/call", async (req, res) => {
  // Mobile app: JSON `{ "to": "+..." }` + `Authorization: Bearer <Firebase ID token>` (verify on server when ready).
  if (req.is("application/json")) {
    const toRaw = req.body && (req.body.to ?? req.body.To);
    if (toRaw == null || String(toRaw).trim() === "") {
      return res.status(400).json({ error: "Missing JSON field: to" });
    }
    const to = String(toRaw).trim();
    try {
      await twilioClient.calls.create({
        to,
        from: TWILIO_CALLER_ID,
        url: voiceCallbackUrl,
      });
      return res.status(200).json({ ok: true, message: "Call triggered successfully" });
    } catch (err) {
      console.error(err);
      return res.status(500).json({ error: String(err.message || err) });
    }
  }

  // Twilio webhook (form-encoded): return TwiML to dial.
  const to = req.body.To || req.body.to;
  const vr = new twilio.twiml.VoiceResponse();
  if (!to) {
    vr.say({ voice: "alice" }, "No destination number.");
  } else {
    const dial = vr.dial({ callerId: TWILIO_CALLER_ID });
    dial.number(to);
  }
  res.type("text/xml");
  res.send(vr.toString());
});

const REWARD_GRANT_CREDITS = Number(process.env.REWARD_GRANT_CREDITS || 10);
const MAX_ADS_PER_DAY = 24;
const AD_GAP_SECONDS = 20;

function utcDayKey(d = new Date()) {
  return `${d.getUTCFullYear()}-${String(d.getUTCMonth() + 1).padStart(2, "0")}-${String(d.getUTCDate()).padStart(2, "0")}`;
}

function readAdsWatchedToday(d, dayKey) {
  const reset = d.last_reset_date || d.adRewardsDayKey || "";
  if (reset !== dayKey) return 0;
  if (d.ads_watched_today !== undefined && d.ads_watched_today !== null) {
    return Number(d.ads_watched_today);
  }
  return Number(d.adRewardsCount || 0);
}

function readAdProgress(d) {
  if (d.ad_progress !== undefined && d.ad_progress !== null) {
    return Number(d.ad_progress);
  }
  return Number(d.adRewardCycleCount || 0);
}

/** Prefer `ad_sub_counter`; else legacy `ad_progress` mod 4 (values 0–3). */
function readAdSubCounter(d) {
  let n;
  if (d.ad_sub_counter !== undefined && d.ad_sub_counter !== null) {
    n = Number(d.ad_sub_counter);
  } else {
    n = readAdProgress(d);
  }
  if (!Number.isFinite(n)) return 0;
  return ((n % 4) + 4) % 4;
}

function readLastAdTimestamp(d) {
  const a = d.last_ad_timestamp;
  if (a && typeof a.toDate === "function") return a.toDate();
  const b = d.lastAdRewardAt;
  if (b && typeof b.toDate === "function") return b.toDate();
  return null;
}

function readFirestoreDate(d, keys) {
  for (const k of keys) {
    const v = d[k];
    if (v && typeof v.toDate === "function") return v.toDate();
  }
  return null;
}

/** Wrong HTTP method → not a silent 404 (helps debug mobile / proxies). */
app.get("/grant-reward", (_req, res) => {
  res.set("Allow", "POST");
  return res.status(405).json({
    error: "Method not allowed",
    message: "Use POST /grant-reward with header Authorization: Bearer <Firebase ID token>",
  });
});

/**
 * POST /grant-reward — secured ad rewards (Flutter: GrantRewardService).
 * - Verifies Firebase ID token → uid.
 * - Updates `ad_progress` (and mirrors `ad_sub_counter` / `adRewardCycleCount`): +1 per ad; at 4 → reset to 0 and +10 reward credits.
 * - Daily cap: max 24 ads / UTC day (`ads_watched_today`).
 * - Cooldown: must be ≥20s since `last_ad_timestamp` / `lastAdRewardAt` or returns **Wait** (429).
 */
app.post("/grant-reward", async (req, res) => {
  if (!firebaseAdmin) {
    return res.status(503).json({
      error: "Grant reward not configured (set FIREBASE_SERVICE_ACCOUNT_JSON on the server)",
    });
  }
  const auth = req.headers.authorization || "";
  const m = /^Bearer\s+(.+)$/i.exec(auth);
  if (!m) {
    return res.status(401).json({ error: "Missing Authorization: Bearer <Firebase ID token>" });
  }
  let uid;
  try {
    const dec = await firebaseAdmin.auth().verifyIdToken(m[1]);
    uid = dec.uid;
  } catch (e) {
    console.error("verifyIdToken:", e.message);
    return res.status(401).json({ error: "Invalid or expired token" });
  }

  const { FieldValue, Timestamp } = firebaseAdmin.firestore;
  const db = firebaseAdmin.firestore();

  let out = { ok: true, creditsAdded: 0, adSubCounter: 0, adsWatchedToday: 0 };

  try {
    await db.runTransaction(async (t) => {
      const ref = db.collection("users").doc(uid);
      const doc = await t.get(ref);
      const now = new Date();
      const dayKey = utcDayKey(now);

      const d = doc.exists ? doc.data() : {};

      let adsToday = readAdsWatchedToday(d, dayKey);
      let storedDay = d.last_reset_date || d.adRewardsDayKey || "";
      if (storedDay !== dayKey) {
        adsToday = 0;
        storedDay = dayKey;
      }

      if (adsToday >= MAX_ADS_PER_DAY) {
        throw Object.assign(new Error("Limit Reached"), { http: 403 });
      }

      const lastAd = readLastAdTimestamp(d);
      if (lastAd) {
        const elapsedSec = (now - lastAd) / 1000;
        if (elapsedSec < AD_GAP_SECONDS) {
          const waitSeconds = Math.ceil(AD_GAP_SECONDS - elapsedSec);
          throw Object.assign(new Error("Wait"), { http: 429, waitSeconds });
        }
      }

      let sub = readAdSubCounter(d);
      sub += 1;
      let creditsAdded = 0;
      if (sub === 4) {
        sub = 0;
        creditsAdded = REWARD_GRANT_CREDITS;
      }

      const adsTodayNew = adsToday + 1;

      let paid = Number(d.paidCredits ?? 0);
      let reward = Number(d.rewardCredits ?? 0);
      if (d.paidCredits === undefined && d.credits != null) {
        paid = Number(d.credits);
        reward = 0;
      }
      const expTs = d.rewardCreditsExpiresAt;
      if (reward > 0 && expTs && expTs.toDate && expTs.toDate() < now) {
        paid += reward;
        reward = 0;
      }

      if (creditsAdded > 0) {
        reward += creditsAdded;
      }

      let rewardExp = null;
      if (reward > 0) {
        if (creditsAdded > 0) {
          rewardExp = Timestamp.fromDate(new Date(now.getTime() + 24 * 60 * 60 * 1000));
        } else if (expTs && expTs.toDate && expTs.toDate() >= now) {
          rewardExp = expTs;
        } else {
          rewardExp = Timestamp.fromDate(new Date(now.getTime() + 24 * 60 * 60 * 1000));
        }
      }

      const patch = {
        ad_sub_counter: sub,
        ad_progress: sub,
        adRewardCycleCount: sub,
        ads_watched_today: adsTodayNew,
        adRewardsCount: adsTodayNew,
        last_reset_date: storedDay,
        adRewardsDayKey: storedDay,
        last_ad_timestamp: FieldValue.serverTimestamp(),
        lastAdRewardAt: FieldValue.serverTimestamp(),
        paidCredits: paid,
        rewardCredits: reward,
        rewardCreditsExpiresAt: rewardExp,
        credits: paid + reward,
      };

      if (creditsAdded > 0) {
        patch.last_grant_reward_at = FieldValue.serverTimestamp();
        patch.last_grant_at_ads_watched_today = adsTodayNew;
      }

      if (doc.exists) {
        t.update(ref, patch);
      } else {
        t.set(ref, patch, { merge: true });
      }
      out = {
        ok: true,
        creditsAdded,
        adSubCounter: sub,
        adsWatchedToday: adsTodayNew,
      };
    });
  } catch (e) {
    const code = e.http || 500;
    if (code === 429 && e.waitSeconds != null) {
      return res.status(429).json({
        error: "Wait",
        message: `Please wait ${e.waitSeconds} second(s) since the last ad.`,
        waitSeconds: e.waitSeconds,
      });
    }
    if (code >= 400 && code < 500) {
      return res.status(code).json({ error: String(e.message || e) });
    }
    console.error("grant-reward tx:", e);
    return res.status(500).json({ error: String(e.message || e) });
  }
  return res.status(200).json(out);
});

const CALL_CREDITS_PER_MINUTE = Number(process.env.CALL_CREDITS_PER_MINUTE || 10);

function parseTwilioDurationSeconds(body) {
  const raw =
    body.Duration ??
    body.CallDuration ??
    body.duration ??
    body.callDuration ??
    "0";
  const n = Number.parseInt(String(raw), 10);
  return Number.isFinite(n) && n >= 0 ? n : 0;
}

/** Outbound Voice SDK: `From` is `client:<identity>`; identity is Firebase UID from `/token`. */
function resolveUidFromTwilioStatus(body, query) {
  const q = query && (query.uid || query.userId);
  if (q && String(q).trim()) return String(q).trim();
  const from = String(body.From || "");
  const m = /^client:(.+)$/i.exec(from);
  if (m) return m[1].trim();
  return null;
}

/**
 * Twilio StatusCallback — set in Twilio Console (Voice app / number) to:
 * `https://<PUBLIC_BASE_URL>/call-status`
 */
app.post("/call-status", async (req, res) => {
  const canonicalUrl = `${String(PUBLIC_BASE_URL).replace(/\/$/, "")}/call-status`;
  const sig = req.get("X-Twilio-Signature") || "";
  if (process.env.SKIP_TWILIO_SIGNATURE !== "1" && TWILIO_AUTH_TOKEN) {
    const ok = twilio.validateRequest(TWILIO_AUTH_TOKEN, sig, canonicalUrl, req.body);
    if (!ok) {
      console.warn("/call-status: invalid Twilio signature");
      return res.status(403).send("Forbidden");
    }
  }

  const body = req.body || {};
  const status = String(body.CallStatus || body.Callstatus || "").toLowerCase();
  if (status !== "completed") {
    return res.status(200).type("text/plain").send("OK");
  }

  if (!firebaseAdmin) {
    console.warn("/call-status: FIREBASE_SERVICE_ACCOUNT_JSON unset — cannot bill");
    return res.status(503).type("text/plain").send("Firebase not configured");
  }

  const callSid = String(body.CallSid || "").trim();
  if (!callSid) {
    return res.status(400).type("text/plain").send("Missing CallSid");
  }

  const uid = resolveUidFromTwilioStatus(body, req.query);
  if (!uid) {
    console.warn("/call-status: could not resolve user (need client: identity or ?uid=)");
    return res.status(200).type("text/plain").send("OK");
  }

  const durationSec = parseTwilioDurationSeconds(body);
  /** Full minutes billed (Twilio duration is seconds). */
  const billedMinutes = Math.ceil(durationSec / 60);
  /** Strict: at least one minute rate even for sub-minute / zero-duration completions. */
  const finalCharge = Math.max(
    CALL_CREDITS_PER_MINUTE,
    billedMinutes * CALL_CREDITS_PER_MINUTE,
  );
  const creditsAttempted = finalCharge;
  const from = String(body.From || "");
  const to = String(body.To || "");

  const { FieldValue } = firebaseAdmin.firestore;
  const db = firebaseAdmin.firestore();

  try {
    await db.runTransaction(async (t) => {
      const userRef = db.collection("users").doc(uid);
      const historyRef = userRef.collection("call_history").doc(callSid);

      const existing = await t.get(historyRef);
      if (existing.exists && existing.data()?.settled === true) {
        return;
      }

      const userSnap = await t.get(userRef);
      if (!userSnap.exists) {
        throw Object.assign(new Error("User document missing"), { http: 404 });
      }

      const d = userSnap.data();
      let paid = Number(d.paidCredits ?? 0);
      let reward = Number(d.rewardCredits ?? 0);
      const now = new Date();
      const expTs = d.rewardCreditsExpiresAt;
      if (reward > 0 && expTs && typeof expTs.toDate === "function" && expTs.toDate() < now) {
        paid += reward;
        reward = 0;
      }
      if (d.paidCredits === undefined && d.credits != null) {
        paid = Number(d.credits);
        reward = 0;
      }

      let usable = paid + reward;
      const charge = finalCharge;
      let creditsCharged = 0;
      if (charge > 0 && usable > 0) {
        creditsCharged = usable < charge ? usable : charge;
        let left = creditsCharged;
        const takeReward = left < reward ? left : reward;
        reward -= takeReward;
        left -= takeReward;
        paid -= left;
        usable = paid + reward;
      }

      let rewardExpOut = null;
      if (reward > 0) {
        rewardExpOut = expTs && expTs.toDate && expTs.toDate() >= now ? expTs : null;
      }

      t.update(userRef, {
        paidCredits: paid,
        rewardCredits: reward,
        rewardCreditsExpiresAt: rewardExpOut,
        credits: paid + reward,
      });

      t.set(
        historyRef,
        {
          callSid,
          twilioCallStatus: String(body.CallStatus || "completed"),
          durationSeconds: durationSec,
          billedMinutes,
          creditsPerMinute: CALL_CREDITS_PER_MINUTE,
          finalCharge,
          creditsAttempted: charge,
          creditsCharged,
          partialDeduction: charge > 0 && creditsCharged < charge,
          from,
          to,
          settled: true,
          settledAt: FieldValue.serverTimestamp(),
          source: "twilio_status_callback",
        },
        { merge: true },
      );
    });
  } catch (e) {
    const code = e.http || 500;
    if (code === 404) {
      return res.status(200).type("text/plain").send("OK");
    }
    console.error("/call-status:", e);
    return res.status(500).type("text/plain").send("Error");
  }

  return res.status(200).type("text/plain").send("OK");
});

/**
 * POST /terminate-call — Firebase Bearer token; JSON `{ "callSid": "CA..." }`.
 * Ends an in-progress Twilio call (same account as Voice SDK). Verifies `From` is `client:<uid>`.
 */
app.post("/terminate-call", async (req, res) => {
  if (!firebaseAdmin) {
    return res.status(503).json({ error: "Firebase not configured" });
  }
  const auth = req.headers.authorization || "";
  const m = /^Bearer\s+(.+)$/i.exec(auth);
  if (!m) {
    return res.status(401).json({ error: "Missing Authorization: Bearer <Firebase ID token>" });
  }
  let uid;
  try {
    uid = (await firebaseAdmin.auth().verifyIdToken(m[1])).uid;
  } catch (e) {
    return res.status(401).json({ error: "Invalid or expired token" });
  }

  const callSid = String(req.body?.callSid || req.body?.CallSid || "").trim();
  if (!callSid) {
    return res.status(400).json({ error: "Missing callSid" });
  }

  try {
    const call = await twilioClient.calls(callSid).fetch();
    const from = String(call.from || "");
    const cm = /^client:(.+)$/i.exec(from);
    if (!cm || cm[1].trim() !== uid) {
      console.warn("/terminate-call: From mismatch", from, uid);
      return res.status(403).json({ error: "Call does not belong to this user" });
    }
    await twilioClient.calls(callSid).update({ status: "completed" });
  } catch (e) {
    console.error("/terminate-call:", e);
    return res.status(500).json({ error: String(e.message || e) });
  }
  return res.status(200).json({ ok: true });
});

// After API routes — avoids any edge case where static assets shadow POST handlers on some hosts.
app.use(express.static(path.join(__dirname, "public")));

const server = app.listen(Number(PORT), () => {
  console.log(`TalkFree voice server listening on port ${PORT}`);
});
server.on("error", (err) => {
  if (err.code === "EADDRINUSE") {
    console.error(`Port ${PORT} is already in use. Change PORT in .env or stop the other process.`);
    if (String(PORT) === "3000") {
      console.error("From server folder try: npm run free-port   then   npm start");
    }
    console.error(
      "PowerShell: Get-NetTCPConnection -LocalPort " +
        PORT +
        " -ErrorAction SilentlyContinue | ForEach-Object { Stop-Process -Id $_.OwningProcess -Force }",
    );
    process.exit(1);
  }
  throw err;
});

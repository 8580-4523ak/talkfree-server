"use strict";

const fs = require("fs");
const path = require("path");

const envPath = path.join(__dirname, ".env");
require("dotenv").config({ path: envPath });

const crypto = require("crypto");
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
    console.log("Firebase Admin: /grant-reward, /assign-number, /send-sms, /admin/upgrade-user enabled");
  } else {
    console.warn("FIREBASE_SERVICE_ACCOUNT_JSON unset — /grant-reward, /assign-number, /send-sms, /admin/upgrade-user return 503");
  }
} catch (e) {
  console.warn("Firebase Admin init failed — /grant-reward disabled:", e.message);
}

/** Twilio webhooks use `${publicBase}/…` — must NOT end with `/` or you get `…//sms-webhook`. */
function normalizePublicBase(raw) {
  return String(raw ?? "").trim().replace(/\/+$/, "");
}

const publicBase = normalizePublicBase(PUBLIC_BASE_URL);
if (publicBase && !/^https:\/\//i.test(publicBase)) {
  console.warn("PUBLIC_BASE_URL should normally start with https:// for Twilio webhooks.");
}

/** Re-read at request time so Render env sync issues surface in logs (not only at boot). */
function getTwilioCallerIdOrThrow(stepLabel) {
  const raw = process.env.TWILIO_CALLER_ID;
  const v = raw != null ? String(raw).trim() : "";
  if (!v) {
    const msg = `${stepLabel}: TWILIO_CALLER_ID is missing or empty in process.env — set it in Render → Environment (E.164, e.g. +15551234567) and redeploy.`;
    console.error("[send-sms]", msg, {
      envKeyDefined: raw !== undefined,
      rawLength: raw == null ? null : String(raw).length,
    });
    const err = new Error(msg);
    err.http = 500;
    err.code = "MISSING_TWILIO_CALLER_ID";
    throw err;
  }
  return v;
}

/**
 * Normalize phone strings toward E.164: strip non-digits, prepend +.
 * US 10-digit national → +1…
 */
function toE164(input) {
  const s = String(input ?? "").trim();
  if (!s) return "";
  const digits = s.replace(/\D/g, "");
  if (digits.length < 10) return "";
  if (digits.length === 10) return `+1${digits}`;
  return `+${digits}`;
}

function readAssignedNumberFromUserDoc(d) {
  if (!d || typeof d !== "object") return "";
  const keys = ["assigned_number", "virtual_number", "allocatedNumber", "number"];
  for (const k of keys) {
    const v = d[k];
    if (v == null) continue;
    const t = String(v).trim();
    if (t !== "" && t.toLowerCase() !== "none") return t;
  }
  return "";
}

/**
 * Prefer Firestore `assigned_number` (user's Twilio line); else `TWILIO_CALLER_ID`.
 */
function resolveOutgoingSmsFrom(userDoc, fallbackCallerRaw) {
  const assignedRaw = readAssignedNumberFromUserDoc(userDoc);
  const assignedE164 = toE164(assignedRaw);
  if (assignedE164 && /^\+[1-9]\d{8,14}$/.test(assignedE164)) {
    return { from: assignedE164, source: "firestore:assigned_number" };
  }
  const fb = String(fallbackCallerRaw ?? "").trim();
  const fbE164 = toE164(fb) || (fb.startsWith("+") ? fb : toE164("+" + fb.replace(/\D/g, "")));
  return { from: fbE164 || fb, source: "env:TWILIO_CALLER_ID" };
}

/**
 * TwiML for PSTN outbound: dial `to` with caller ID. Used by:
 * - Twilio Voice SDK (TwiML App Voice URL should be POST {PUBLIC_BASE_URL}/call)
 * - REST twilioClient.calls.create `url` → use /twiml/voice so the callee leg gets real Dial, not /voice Say test.
 */
function voiceResponseDialPstn(toRaw) {
  const vr = new twilio.twiml.VoiceResponse();
  const to = toRaw != null ? String(toRaw).trim() : "";
  if (!to) {
    vr.say({ voice: "alice" }, "No destination number.");
  } else {
    const dial = vr.dial({ callerId: TWILIO_CALLER_ID });
    dial.number(to);
  }
  return vr;
}

/** Optional test: GET /voice — Say only (do not use as calls.create `url` for real PSTN). */
app.all("/voice", (req, res) => {
  console.log("Twilio hit /voice (test Say)");
  res.type("text/xml");
  res.send(
    new twilio.twiml.VoiceResponse()
      .say({ voice: "alice" }, "TalkFree server voice test — use /twiml/voice or POST /call for Dial.")
      .toString(),
  );
});

/**
 * TwiML Dial — for REST `calls.create({ url })` callbacks. Twilio sends To in query or body.
 * GET /twiml/voice?To=+1... or POST with form field To.
 */
app.all("/twiml/voice", (req, res) => {
  const to =
    (req.body && (req.body.To || req.body.to)) ||
    (req.query && (req.query.To || req.query.to)) ||
    "";
  res.type("text/xml");
  res.send(voiceResponseDialPstn(to).toString());
});

const twimlDialUrl = `${publicBase}/twiml/voice`;

const AccessToken = twilio.jwt.AccessToken;
const VoiceGrant = AccessToken.VoiceGrant;

/** Legacy browser/test: GET /call?to= — triggers PSTN; TwiML URL must Dial (see /twiml/voice). */
app.get("/call", async (req, res) => {
  try {
    const to = req.query.to;

    if (!to) {
      return res.send("Missing ?to= number");
    }

    await twilioClient.calls.create({
      to: String(to).trim(),
      from: process.env.TWILIO_CALLER_ID,
      url: twimlDialUrl,
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
  // Mobile app: JSON `{ "to": "+..." }` — server-initiated PSTN (optional; Voice SDK uses TwiML App POST below).
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
        url: twimlDialUrl,
      });
      return res.status(200).json({ ok: true, message: "Call triggered successfully" });
    } catch (err) {
      console.error(err);
      return res.status(500).json({ error: String(err.message || err) });
    }
  }

  // Twilio Voice SDK / TwiML App webhook (application/x-www-form-urlencoded): return TwiML to <Dial> PSTN.
  const to = req.body.To || req.body.to;
  res.type("text/xml");
  res.send(voiceResponseDialPstn(to).toString());
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
 * - Increments progress each successful request: internal counter 1→2→3→4; on the 4th ad
 *   (`ad_progress` / `ad_sub_counter` cycle completes), adds REWARD_GRANT_CREDITS (default 10) and resets progress to 0.
 * - Mirrors legacy fields: `adRewardCycleCount`, `adRewardsCount`, etc.
 * - Daily cap: max 24 ads / UTC day (`ads_watched_today`).
 * - Lifetime rewarded views: `ads_watched_count` += 1 each successful grant (Flutter unlock US number).
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
        /** Lifetime total — Flutter reads `ads_watched_count` for US number unlock (50 ads). */
        ads_watched_count: FieldValue.increment(1),
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

/** Constant-time compare for [ADMIN_SECRET_KEY] (mitigate timing leaks on guessable lengths). */
function adminSecretMatches(provided, expected) {
  const a = Buffer.from(String(provided ?? ""), "utf8");
  const b = Buffer.from(String(expected ?? ""), "utf8");
  if (a.length !== b.length) {
    return false;
  }
  return crypto.timingSafeEqual(a, b);
}

const ADMIN_UPGRADE_BONUS_CREDITS = Number(process.env.ADMIN_UPGRADE_BONUS_CREDITS || 1000);

/**
 * POST /admin/upgrade-user — Admin-only: set `isPremium: true`, grant bonus credits, align tier fields.
 * **Auth:** `X-Admin-Secret: <ADMIN_SECRET_KEY>` or `Authorization: Bearer <ADMIN_SECRET_KEY>`
 * (or JSON body `secret` for quick curl — prefer headers in production).
 * **Body:** `{ "targetUid": "<Firebase Auth uid>" }`
 * Later: call from Razorpay/Stripe webhook with the same secret (or move to signed JWT).
 */
app.post("/admin/upgrade-user", async (req, res) => {
  if (!firebaseAdmin) {
    return res.status(503).json({ error: "Firebase Admin not configured (set FIREBASE_SERVICE_ACCOUNT_JSON)" });
  }
  const envSecret = process.env.ADMIN_SECRET_KEY;
  if (!envSecret || String(envSecret).trim() === "") {
    console.error("ADMIN_SECRET_KEY is empty — refusing POST /admin/upgrade-user");
    return res.status(503).json({ error: "Admin upgrade not configured (set ADMIN_SECRET_KEY)" });
  }
  const headerSecret = req.headers["x-admin-secret"];
  const bearer =
    typeof req.headers.authorization === "string"
      ? /^Bearer\s+(.+)$/i.exec(req.headers.authorization)
      : null;
  const provided =
    (headerSecret != null && String(headerSecret)) ||
    (bearer ? bearer[1].trim() : "") ||
    (req.body && req.body.secret != null ? String(req.body.secret) : "");
  if (!provided || !adminSecretMatches(provided, envSecret)) {
    return res.status(401).json({ error: "Unauthorized" });
  }

  const targetUid = String(req.body?.targetUid ?? "").trim();
  if (!targetUid) {
    return res.status(400).json({ error: "Missing targetUid" });
  }

  const bonus = Number.isFinite(ADMIN_UPGRADE_BONUS_CREDITS) && ADMIN_UPGRADE_BONUS_CREDITS > 0
    ? Math.floor(ADMIN_UPGRADE_BONUS_CREDITS)
    : 1000;

  const db = firebaseAdmin.firestore();
  const ref = db.collection("users").doc(targetUid);

  try {
    const out = await db.runTransaction(async (t) => {
      const snap = await t.get(ref);
      if (!snap.exists) {
        throw Object.assign(new Error("User document not found"), { http: 404 });
      }
      const d = snap.data();
      let paid = Number(d.paidCredits ?? 0);
      let reward = Number(d.rewardCredits ?? 0);
      if (d.paidCredits === undefined && d.credits != null) {
        paid = Number(d.credits);
        reward = 0;
      }
      const now = new Date();
      const expTs = d.rewardCreditsExpiresAt;
      if (reward > 0 && expTs && typeof expTs.toDate === "function" && expTs.toDate() < now) {
        paid += reward;
        reward = 0;
      }
      paid += bonus;
      const total = paid + reward;
      t.update(ref, {
        isPremium: true,
        subscription_tier: "pro",
        paidCredits: paid,
        credits: total,
        premiumWelcomeBonusGranted: true,
      });
      return { ok: true, targetUid, creditsAdded: bonus, newBalance: total, isPremium: true };
    });
    return res.status(200).json(out);
  } catch (e) {
    const code = e.http || 500;
    if (code === 404) {
      return res.status(404).json({ error: String(e.message || e) });
    }
    console.error("POST /admin/upgrade-user:", e);
    return res.status(code >= 400 && code < 600 ? code : 500).json({
      error: String(e.message || e),
    });
  }
});

/** Usable balance from Firestore `users/{uid}` (aligned with POST /grant-reward). */
function usableCreditsFromUserDoc(d) {
  let paid = Number(d.paidCredits ?? 0);
  let reward = Number(d.rewardCredits ?? 0);
  if (d.paidCredits === undefined && d.credits != null) {
    paid = Number(d.credits);
    reward = 0;
  }
  const now = new Date();
  const expTs = d.rewardCreditsExpiresAt;
  if (reward > 0 && expTs && typeof expTs.toDate === "function" && expTs.toDate() < now) {
    paid += reward;
    reward = 0;
  }
  return paid + reward;
}

/** Lifetime rewarded-ad views (`ads_watched_count`, incremented each POST /grant-reward). */
function readLifetimeAdsWatched(d) {
  const n = d.ads_watched_count;
  if (n === undefined || n === null || n === "") return 0;
  const x = Number(n);
  return Number.isFinite(x) ? x : 0;
}

const ASSIGN_NUMBER_MIN_CREDITS = Number(process.env.ASSIGN_NUMBER_MIN_CREDITS || 100);
const ASSIGN_NUMBER_MIN_ADS_WATCHED = Number(process.env.ASSIGN_NUMBER_MIN_ADS_WATCHED || 50);
const ASSIGN_NUMBER_AREA_CODE = process.env.ASSIGN_NUMBER_AREA_CODE
  ? Number.parseInt(String(process.env.ASSIGN_NUMBER_AREA_CODE).trim(), 10)
  : null;

/**
 * Search for a US local number and purchase it (Twilio billed to your account).
 * If ASSIGN_NUMBER_AREA_CODE is set, search is restricted to that NPA; otherwise any US local match.
 * Voice URL → /voice-inbound-number; SMS → /sms-webhook. US A2P/10DLC registration may be required
 * in Twilio Console before inbound SMS actually delivers.
 */
async function searchAndBuySmsCapableUsLocal(uid) {
  const params = { limit: 5 };
  if (Number.isFinite(ASSIGN_NUMBER_AREA_CODE)) {
    params.areaCode = ASSIGN_NUMBER_AREA_CODE;
  }

  const candidates = await twilioClient.availablePhoneNumbers("US").local.list(params);
  if (!candidates.length) {
    const err = new Error(
      "No SMS-capable US local numbers available (try another area code or try again later)",
    );
    err.http = 503;
    throw err;
  }
  const picked = candidates[0];
  const incoming = await twilioClient.incomingPhoneNumbers.create({
    phoneNumber: picked.phoneNumber,
    friendlyName: `TalkFree ${String(uid).slice(0, 12)}`,
    smsUrl: `${publicBase}/sms-webhook`,
    smsMethod: "POST",
    voiceUrl: `${publicBase}/voice-inbound-number`,
    voiceMethod: "POST",
  });
  return incoming;
}

/** Inbound PSTN call to a purchased TalkFree number — simple placeholder TwiML. */
app.all("/voice-inbound-number", (req, res) => {
  const vr = new twilio.twiml.VoiceResponse();
  vr.say(
    { voice: "alice" },
    "Thanks for calling. This TalkFree number does not accept voice mail. Please reach the user in the TalkFree app.",
  );
  vr.hangup();
  res.type("text/xml");
  res.send(vr.toString());
});

/**
 * Pick which `users/{uid}` owns this Twilio number if multiple docs match (recycle edge case).
 * Prefer latest `twilioNumberAssignedAt`, then `created_at` / `createdAt`, then uid lexicographic.
 */
function pickUidForAssignedNumber(docs) {
  if (!docs.length) return null;
  if (docs.length === 1) return docs[0].id;

  function docTimeMs(doc) {
    const d = doc.data() || {};
    const a = d.twilioNumberAssignedAt;
    if (a && typeof a.toMillis === "function") return a.toMillis();
    const c = d.created_at || d.createdAt;
    if (c && typeof c.toMillis === "function") return c.toMillis();
    return 0;
  }

  const ranked = docs
    .map((doc) => ({ id: doc.id, ms: docTimeMs(doc) }))
    .sort((x, y) => {
      if (y.ms !== x.ms) return y.ms - x.ms;
      return x.id.localeCompare(y.id);
    });

  if (ranked[0].ms === 0) {
    console.warn(
      `sms-webhook: ${docs.length} users share assigned_number; tie-break by uid (set twilioNumberAssignedAt on provision)`,
    );
  }
  return ranked[0].id;
}

/**
 * Twilio inbound SMS — POST to a provisioned number → `users/{uid}/messages/{autoId}`.
 * `createdAt` uses server timestamps for correct inbox ordering. Always respond 200 with empty TwiML.
 */
app.post("/sms-webhook", async (req, res) => {
  const To = String(req.body.To || "").trim();
  const From = String(req.body.From || "").trim();
  const Body = String(req.body.Body || "");
  const mr = new twilio.twiml.MessagingResponse();

  if (!firebaseAdmin) {
    console.warn("sms-webhook: Firebase Admin not configured — message not stored");
    res.type("text/xml");
    return res.status(200).send(mr.toString());
  }

  try {
    const db = firebaseAdmin.firestore();
    const { FieldValue } = firebaseAdmin.firestore;
    const q = await db.collection("users").where("assigned_number", "==", To).get();
    if (q.empty) {
      console.warn("sms-webhook: no user with assigned_number=", To);
    } else {
      const uid = pickUidForAssignedNumber(q.docs);
      if (uid) {
        await db
          .collection("users")
          .doc(uid)
          .collection("messages")
          .add({
            from: From,
            to: To,
            body: Body,
            direction: "inbound",
            createdAt: FieldValue.serverTimestamp(),
          });
        console.log(
          `sms-webhook: users/${uid}/messages (new doc) inbound from=${From} matches=${q.docs.length}`,
        );
      }
    }
  } catch (e) {
    console.error("sms-webhook:", e);
  }
  res.type("text/xml");
  return res.status(200).send(mr.toString());
});

app.get("/assign-number", (_req, res) => {
  res.set("Allow", "POST");
  return res.status(405).json({
    error: "Method not allowed",
    message: "Use POST /assign-number with header Authorization: Bearer <Firebase ID token>",
  });
});

/**
 * POST /assign-number — provision a real US local Twilio number (secured).
 * - Verifies Firebase ID token → uid (optional JSON body `uid` must match).
 * - Eligible if usable credits ≥ ASSIGN_NUMBER_MIN_CREDITS (default 100) OR
 *   lifetime `ads_watched_count` ≥ ASSIGN_NUMBER_MIN_ADS_WATCHED (default 50).
 * - Searches & purchases via Twilio API, then writes `assigned_number`, `twilioIncomingPhoneSid`, etc.
 */
app.post("/assign-number", async (req, res) => {
  if (!firebaseAdmin) {
    return res.status(503).json({
      error: "Assign number not configured (set FIREBASE_SERVICE_ACCOUNT_JSON on the server)",
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
    console.error("verifyIdToken (assign-number):", e.message);
    return res.status(401).json({ error: "Invalid or expired token" });
  }

  const bodyUid =
    req.body && req.body.uid != null ? String(req.body.uid).trim() : "";
  if (bodyUid && bodyUid !== uid) {
    return res.status(403).json({ error: "uid does not match authenticated user" });
  }

  const db = firebaseAdmin.firestore();
  const ref = db.collection("users").doc(uid);

  let snap;
  try {
    snap = await ref.get();
  } catch (e) {
    console.error("assign-number get:", e);
    return res.status(500).json({ error: String(e.message || e) });
  }

  if (!snap.exists) {
    return res.status(404).json({ error: "User document not found" });
  }

  const d = snap.data() || {};
  const existingAssigned = String(d.assigned_number ?? "").trim();
  if (existingAssigned && existingAssigned.toLowerCase() !== "none") {
    return res.status(200).json({
      ok: true,
      alreadyAssigned: true,
      assigned_number: existingAssigned,
      twilioIncomingPhoneSid: d.twilioIncomingPhoneSid || d.twilioPhoneNumberSid || null,
    });
  }

  const usable = usableCreditsFromUserDoc(d);
  const adsLifetime = readLifetimeAdsWatched(d);
  const enoughCredits = usable >= ASSIGN_NUMBER_MIN_CREDITS;
  const enoughAds = adsLifetime >= ASSIGN_NUMBER_MIN_ADS_WATCHED;
  const premium = readIsPremium(d);

  if (!enoughCredits && !enoughAds && !premium) {
    return res.status(403).json({
      error: "Not eligible to assign a number",
      usableCredits: usable,
      adsWatchedLifetime: adsLifetime,
      minCredits: ASSIGN_NUMBER_MIN_CREDITS,
      minAdsWatched: ASSIGN_NUMBER_MIN_ADS_WATCHED,
      isPremium: false,
    });
  }

  let incoming;
  try {
    incoming = await searchAndBuySmsCapableUsLocal(uid);
  } catch (e) {
    const code = e.http || 502;
    console.error("assign-number Twilio:", e);
    return res.status(code >= 400 && code < 600 ? code : 502).json({
      error: String(e.message || e),
    });
  }

  const e164 = String(incoming.phoneNumber || "").trim();
  if (!e164) {
    return res.status(500).json({ error: "Twilio returned empty phone number" });
  }

  try {
    const { FieldValue } = firebaseAdmin.firestore;
    await ref.update({
      assigned_number: e164,
      virtual_number: e164,
      allocatedNumber: e164,
      number: e164,
      twilioIncomingPhoneSid: incoming.sid,
      twilioPhoneNumberSid: incoming.sid,
      twilioNumberAssignedAt: FieldValue.serverTimestamp(),
    });
  } catch (e) {
    console.error("assign-number Firestore update:", e);
    return res.status(500).json({
      error: String(e.message || e),
      warning:
        "Twilio number was purchased but profile update failed — check Twilio Console and Firestore manually.",
      twilioIncomingPhoneSid: incoming.sid,
      phoneNumber: e164,
    });
  }

  return res.status(200).json({
    ok: true,
    assigned_number: e164,
    twilioIncomingPhoneSid: incoming.sid,
    usableCredits: usable,
    adsWatchedLifetime: adsLifetime,
    viaCredits: enoughCredits,
    viaAds: enoughAds,
    viaPremium: premium,
  });
});

const CALL_CREDITS_PER_MINUTE = Number(process.env.CALL_CREDITS_PER_MINUTE || 10);
const CALL_CREDITS_PER_MINUTE_PREMIUM = Number(process.env.CALL_CREDITS_PER_MINUTE_PREMIUM || 7);

/** Matches Flutter [FirestoreUserService.isPremiumFromUserData]. */
function readIsPremium(d) {
  if (!d) return false;
  if (d.isPremium === true) return true;
  const t = String(d.subscription_tier ?? d.subscriptionTier ?? d.plan ?? "").toLowerCase();
  return t === "pro" || t === "premium";
}

/** Non-empty Firebase Auth uid — all billing writes use `users/{uid}`. */
function requireFirebaseUid(uid) {
  const u = String(uid || "").trim();
  if (!u) {
    throw Object.assign(new Error("Missing or empty user id for billing"), { http: 400 });
  }
  return u;
}

function parseTwilioDurationSeconds(body) {
  const raw =
    body.Duration ??
    body.CallDuration ??
    body.DialCallDuration ??
    body.RecordingDuration ??
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

/** Matches Flutter [CreditsPolicy] live tick amounts (10 = connect pulse, 1 = periodic). */
const ALLOWED_LIVE_TICK_AMOUNTS = new Set([1, 10]);

/**
 * TalkFree Tier-2 settlement (server truth; backup: Twilio POST /call-status if app offline).
 *
 * Math (1 live tick = 6s = 1 credit):
 * - finalCharge = ceil(durationSec / 6)  e.g. 12s → 2, 0s → 0
 * - prepaid = liveDeductedCredits from POST /call-live-tick (every 6s × 1)
 * - remainder = finalCharge - prepaid → deduct from user; if prepaid > finalCharge, refund to paidCredits
 *
 * Firestore: `users/{uid}` fields paidCredits, rewardCredits, credits; history in `call_history/{callSid}`.
 */
async function settleOutboundCallBill({
  uid: uidIn,
  callSid,
  durationSec,
  from,
  to,
  twilioCallStatus,
  source,
}) {
  if (!firebaseAdmin) {
    throw new Error("Firebase not configured");
  }
  const uid = requireFirebaseUid(uidIn);
  const db = firebaseAdmin.firestore();
  const { FieldValue } = firebaseAdmin.firestore;

  const ds = Number(durationSec) || 0;

  await db.runTransaction(async (t) => {
    const userRef = db.collection("users").doc(uid);
    const historyRef = userRef.collection("call_history").doc(callSid);
    const liveRef = userRef.collection("voice_active_calls").doc(callSid);

    const existing = await t.get(historyRef);
    if (existing.exists && existing.data()?.settled === true) {
      return;
    }

    const userSnap = await t.get(userRef);
    if (!userSnap.exists) {
      throw Object.assign(new Error("User document missing"), { http: 404 });
    }

    const liveSnap = await t.get(liveRef);
    const prepaid = Number(liveSnap.exists ? liveSnap.data()?.liveDeductedCredits || 0 : 0);

    const d = userSnap.data();
    const tickUnits = Math.ceil(ds / 6);
    const premium = readIsPremium(d);
    const billCredits = premium
      ? Math.max(0, Math.ceil((tickUnits * CALL_CREDITS_PER_MINUTE_PREMIUM) / CALL_CREDITS_PER_MINUTE))
      : tickUnits;
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

    let remainder = billCredits - prepaid;

    /** Credits returned to **paidCredits** only (audit: rewards vs purchased). */
    let refundToPaidCredits = 0;
    if (remainder < 0) {
      const refund = -remainder;
      paid += refund;
      refundToPaidCredits = refund;
      remainder = 0;
    }

    let usable = paid + reward;
    const charge = remainder;
    let creditsChargedThisSettle = 0;
    if (charge > 0 && usable > 0) {
      creditsChargedThisSettle = usable < charge ? usable : charge;
      let left = creditsChargedThisSettle;
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

    const totalCreditsOut = paid + reward;
    console.log(
      `[billing] settle user=${uid} callSid=${callSid} source=${source} durationSec=${ds} ` +
        `premium=${premium} tickUnits=${tickUnits} billCredits=${billCredits} prepaid=${prepaid} refundToPaidCredits=${refundToPaidCredits} ` +
        `remainderCharge=${charge} creditsAppliedThisSettle=${creditsChargedThisSettle} balanceAfter=${totalCreditsOut}`,
    );

    t.update(userRef, {
      paidCredits: paid,
      rewardCredits: reward,
      rewardCreditsExpiresAt: rewardExpOut,
      credits: totalCreditsOut,
    });

    t.set(
      historyRef,
      {
        firebaseUid: uid,
        callSid,
        twilioCallStatus: String(twilioCallStatus || "completed"),
        durationSeconds: ds,
        billedSixSecondTicks: tickUnits,
        creditsPerMinute: premium ? CALL_CREDITS_PER_MINUTE_PREMIUM : CALL_CREDITS_PER_MINUTE,
        finalCharge: billCredits,
        isPremium: premium,
        prepaidAppliedFromLiveTicks: prepaid,
        refundToPaidCredits,
        creditsCharged: creditsChargedThisSettle,
        creditsAttempted: charge,
        partialDeduction: charge > 0 && creditsChargedThisSettle < charge,
        from,
        to,
        settled: true,
        settledAt: FieldValue.serverTimestamp(),
        source: source || "unknown",
      },
      { merge: true },
    );

    t.delete(liveRef);
  });
}

/**
 * POST /call-live-tick — Firebase Bearer; JSON `{ "callSid": "CA...", "amount": 1|10 }`.
 * Deducts credits on the server and increments live session total (reconciled at call end).
 */
app.post("/call-live-tick", async (req, res) => {
  if (!firebaseAdmin) {
    return res.status(503).json({ error: "Firebase not configured" });
  }
  const auth = req.headers.authorization || "";
  const bm = /^Bearer\s+(.+)$/i.exec(auth);
  if (!bm) {
    return res.status(401).json({ error: "Missing Authorization: Bearer <Firebase ID token>" });
  }
  let uid;
  try {
    uid = requireFirebaseUid((await firebaseAdmin.auth().verifyIdToken(bm[1])).uid);
  } catch (e) {
    return res.status(401).json({ error: "Invalid or expired token" });
  }

  const callSid = String(req.body?.callSid || req.body?.CallSid || "").trim();
  const amount = Number(req.body?.amount);
  if (!callSid) {
    return res.status(400).json({ error: "Missing callSid" });
  }
  if (!Number.isFinite(amount) || !ALLOWED_LIVE_TICK_AMOUNTS.has(amount)) {
    return res.status(400).json({ error: "Invalid amount (allowed: 1 or 10)" });
  }

  let call;
  try {
    call = await twilioClient.calls(callSid).fetch();
  } catch (e) {
    console.warn("/call-live-tick: Twilio fetch failed", e.message);
    return res.status(400).json({ error: "Could not fetch call" });
  }
  const from = String(call.from || "");
  const cm = /^client:(.+)$/i.exec(from);
  if (!cm || cm[1].trim() !== uid) {
    return res.status(403).json({ error: "Call does not belong to this user" });
  }

  const db = firebaseAdmin.firestore();
  const { FieldValue } = firebaseAdmin.firestore;

  try {
    await db.runTransaction(async (t) => {
      const userRef = db.collection("users").doc(uid);
      const liveRef = userRef.collection("voice_active_calls").doc(callSid);
      const userSnap = await t.get(userRef);
      if (!userSnap.exists) {
        throw Object.assign(new Error("User document missing"), { http: 404 });
      }

      const d = userSnap.data();
      const premium = readIsPremium(d);
      const debit = premium
        ? Math.max(0, Math.ceil((amount * CALL_CREDITS_PER_MINUTE_PREMIUM) / CALL_CREDITS_PER_MINUTE))
        : amount;
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
      if (usable < debit) {
        throw Object.assign(new Error("Insufficient credits"), { http: 402 });
      }

      let left = debit;
      const takeReward = left < reward ? left : reward;
      reward -= takeReward;
      left -= takeReward;
      paid -= left;
      usable = paid + reward;

      let rewardExpOut = null;
      if (reward > 0) {
        rewardExpOut = expTs && expTs.toDate && expTs.toDate() >= now ? expTs : null;
      }

      const bal = paid + reward;
      console.log(
        `[billing] call-live-tick user=${uid} callSid=${callSid} amount=${amount} debit=${debit} premium=${premium} balanceAfter=${bal}`,
      );
      t.update(userRef, {
        paidCredits: paid,
        rewardCredits: reward,
        rewardCreditsExpiresAt: rewardExpOut,
        credits: bal,
      });
      t.set(
        liveRef,
        {
          firebaseUid: uid,
          liveDeductedCredits: FieldValue.increment(debit),
          updatedAt: FieldValue.serverTimestamp(),
        },
        { merge: true },
      );
    });
  } catch (e) {
    const code = e.http || 500;
    if (code === 402) {
      return res.status(402).json({ error: "Insufficient credits" });
    }
    if (code === 404) {
      return res.status(404).json({ error: "User not found" });
    }
    console.error("/call-live-tick:", e);
    return res.status(500).json({ error: String(e.message || e) });
  }
  return res.status(200).json({ ok: true });
});

/**
 * POST /sync-call-billing — Firebase Bearer; JSON `{ "callSid": "CA..." }`.
 * Fetches Twilio call duration and runs the same settlement as Twilio `/call-status` (idempotent).
 */
app.post("/sync-call-billing", async (req, res) => {
  if (!firebaseAdmin) {
    return res.status(503).json({ error: "Firebase not configured" });
  }
  const auth = req.headers.authorization || "";
  const bm = /^Bearer\s+(.+)$/i.exec(auth);
  if (!bm) {
    return res.status(401).json({ error: "Missing Authorization: Bearer <Firebase ID token>" });
  }
  let uid;
  try {
    uid = requireFirebaseUid((await firebaseAdmin.auth().verifyIdToken(bm[1])).uid);
  } catch (e) {
    return res.status(401).json({ error: "Invalid or expired token" });
  }

  const callSid = String(req.body?.callSid || req.body?.CallSid || "").trim();
  if (!callSid) {
    return res.status(400).json({ error: "Missing callSid" });
  }

  let call;
  let durationSec = 0;
  try {
    for (let attempt = 0; attempt < 8; attempt++) {
      call = await twilioClient.calls(callSid).fetch();
      const durationRaw = Number.parseInt(String(call.duration != null ? call.duration : "0"), 10);
      durationSec = Number.isFinite(durationRaw) ? durationRaw : 0;
      const st = String(call.status || "");
      if (durationSec > 0 || st === "completed" || st === "canceled" || st === "failed") {
        break;
      }
      await new Promise((r) => setTimeout(r, 600));
    }
  } catch (e) {
    console.warn("/sync-call-billing: Twilio fetch failed", e.message);
    return res.status(400).json({ error: "Could not fetch call" });
  }
  const from = String(call.from || "");
  const cm = /^client:(.+)$/i.exec(from);
  if (!cm || cm[1].trim() !== uid) {
    return res.status(403).json({ error: "Call does not belong to this user" });
  }

  const to = String(call.to || "");
  console.log(
    `[billing] sync-call-billing user=${uid} callSid=${callSid} twilioStatus=${call.status} durationSec=${durationSec}`,
  );

  try {
    await settleOutboundCallBill({
      uid,
      callSid,
      durationSec,
      from,
      to,
      twilioCallStatus: String(call.status || "completed"),
      source: "sync_call_billing",
    });
  } catch (e) {
    const code = e.http || 500;
    if (code === 404) {
      return res.status(200).json({ ok: true, skipped: true });
    }
    console.error("/sync-call-billing:", e);
    return res.status(500).json({ error: String(e.message || e) });
  }
  return res.status(200).json({ ok: true });
});

/**
 * Twilio StatusCallback — set in Twilio Console (Voice app / number) to:
 * `https://<PUBLIC_BASE_URL>/call-status`
 */
app.post("/call-status", async (req, res) => {
  const canonicalUrl = `${publicBase}/call-status`;
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

  const uidRaw = resolveUidFromTwilioStatus(body, req.query);
  if (!uidRaw) {
    console.warn(
      "/call-status: could not resolve user (need From=client:<firebaseUid> on Voice SDK calls)",
      "From=",
      body.From,
      "keys=",
      Object.keys(body || {}),
    );
    return res.status(200).type("text/plain").send("OK");
  }

  let uid;
  try {
    uid = requireFirebaseUid(uidRaw);
  } catch (e) {
    console.warn("/call-status: invalid uid", uidRaw);
    return res.status(200).type("text/plain").send("OK");
  }

  const durationSec = parseTwilioDurationSeconds(body);
  const from = String(body.From || "");
  const to = String(body.To || "");

  console.log(
    `[billing] call-status webhook user=${uid} callSid=${callSid} durationSec=${durationSec} CallStatus=${body.CallStatus}`,
  );

  try {
    await settleOutboundCallBill({
      uid,
      callSid,
      durationSec,
      from,
      to,
      twilioCallStatus: String(body.CallStatus || "completed"),
      source: "twilio_status_callback",
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

app.get("/send-sms", (_req, res) => {
  res.set("Allow", "POST");
  return res.status(405).json({
    error: "Method not allowed",
    message: "Use POST /send-sms with Authorization: Bearer <Firebase ID token> and JSON { \"to\", \"body\" }",
  });
});

/**
 * POST /send-sms — Firebase Bearer token; JSON `{ "to": "+...", "body": "..." }`.
 * - `From`: user's `assigned_number` in Firestore if valid E.164, else `TWILIO_CALLER_ID`.
 * - Logs each step for Render logs (URL, From, To, payload size).
 * - Twilio errors: logs exact code + message (e.g. 21608 unverified trial destination).
 */
app.post("/send-sms", async (req, res) => {
  const routeUrl = `${publicBase}/send-sms`;
  console.log("[send-sms] step 1: request URL (PUBLIC_BASE_URL)", routeUrl);

  if (!firebaseAdmin) {
    console.error("[send-sms] Firebase Admin not configured — cannot verify caller");
    return res.status(503).json({
      error: "SMS API not configured (set FIREBASE_SERVICE_ACCOUNT_JSON on the server)",
    });
  }

  let fallbackCaller;
  try {
    fallbackCaller = getTwilioCallerIdOrThrow("POST /send-sms");
  } catch (e) {
    return res.status(500).json({
      error: String(e.message || e),
      code: e.code || "MISSING_TWILIO_CALLER_ID",
    });
  }
  console.log("[send-sms] step 2: TWILIO_CALLER_ID from env (fallback) present, length=", String(fallbackCaller).length);

  const auth = req.headers.authorization || "";
  const m = /^Bearer\s+(.+)$/i.exec(auth);
  if (!m) {
    console.warn("[send-sms] missing Authorization Bearer");
    return res.status(401).json({ error: "Missing Authorization: Bearer <Firebase ID token>" });
  }

  let uid;
  try {
    const dec = await firebaseAdmin.auth().verifyIdToken(m[1]);
    uid = dec.uid;
  } catch (e) {
    console.error("[send-sms] verifyIdToken:", e.message);
    return res.status(401).json({ error: "Invalid or expired token" });
  }
  console.log("[send-sms] step 3: Firebase uid", uid);

  const toRaw = req.body && (req.body.to ?? req.body.To);
  const bodyText = req.body && (req.body.body ?? req.body.Body ?? req.body.message ?? "");
  const payloadPreview = {
    toRaw: toRaw != null ? String(toRaw).slice(0, 32) : null,
    bodyLength: String(bodyText).length,
  };
  console.log("[send-sms] step 4: payload (preview)", payloadPreview);

  const to = toE164(toRaw);
  const body = String(bodyText).trim();

  if (!to || !/^\+[1-9]\d{8,14}$/.test(to)) {
    console.error("[send-sms] invalid To after E.164 normalize:", { toRaw, to });
    return res.status(400).json({
      error: "Invalid or missing `to` — use E.164 (e.g. +15551234567)",
      toNormalized: to || null,
    });
  }
  if (!body) {
    console.error("[send-sms] empty body");
    return res.status(400).json({ error: "Missing `body` (message text)" });
  }

  const db = firebaseAdmin.firestore();
  let userData = {};
  try {
    const snap = await db.collection("users").doc(uid).get();
    userData = snap.exists ? snap.data() : {};
  } catch (e) {
    console.error("[send-sms] Firestore read users/" + uid + ":", e.message);
    return res.status(500).json({ error: "Could not load user profile" });
  }

  const resolved = resolveOutgoingSmsFrom(userData, fallbackCaller);
  const from = resolved.from;
  console.log("[send-sms] step 5: From number (E.164)", from, "| source:", resolved.source);
  console.log("[send-sms] step 6: To number (E.164)", to);
  console.log("[send-sms] step 7: Body chars", body.length);

  if (!from || !/^\+[1-9]\d{8,14}$/.test(from)) {
    console.error("[send-sms] invalid From after resolve:", { from, resolved });
    return res.status(500).json({
      error: "Could not resolve a valid From number — check assigned_number or TWILIO_CALLER_ID",
    });
  }

  try {
    const msg = await twilioClient.messages.create({
      from,
      to,
      body,
    });
    console.log("[send-sms] step 8: Twilio OK sid=", msg.sid, "status=", msg.status);
    return res.status(200).json({
      ok: true,
      sid: msg.sid,
      status: msg.status,
      from,
      to,
      fromSource: resolved.source,
    });
  } catch (err) {
    const code = err.code;
    const message = err.message;
    const status = err.status;
    const moreInfo = err.moreInfo;
    console.error("[send-sms] Twilio messages.create FAILED:", {
      code,
      message,
      status,
      moreInfo,
      from,
      to,
    });
    return res.status(502).json({
      error: message || String(err),
      twilioCode: code != null ? String(code) : undefined,
      twilioStatus: status,
      moreInfo: moreInfo || undefined,
      from,
      to,
    });
  }
});

// After API routes — avoids any edge case where static assets shadow POST handlers on some hosts.
app.use(express.static(path.join(__dirname, "public")));

const server = app.listen(Number(PORT), () => {
  console.log(`TalkFree voice server listening on port ${PORT}`);
  console.log(`PUBLIC_BASE_URL (normalized): ${publicBase}`);
  console.log(`Outbound SMS (app → Twilio): POST ${publicBase}/send-sms`);
  console.log(`Inbound SMS webhook (Twilio): ${publicBase}/sms-webhook`);
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

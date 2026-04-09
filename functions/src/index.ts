import * as admin from "firebase-admin";
import {HttpsError, onCall} from "firebase-functions/v2/https";

admin.initializeApp();

const COOLDOWN_SEC = 90;
const MAX_DAILY = 20;
const REWARD = 4;
const DAY_MS = 24 * 60 * 60 * 1000;

function toInt(v: unknown, d: number): number {
  if (typeof v === "number" && !Number.isNaN(v)) return Math.trunc(v);
  if (typeof v === "string" && v.trim() !== "") {
    const n = parseInt(v, 10);
    return Number.isNaN(n) ? d : n;
  }
  return d;
}

export const grantRewardedAdCredits = onCall(
  {region: "us-central1"},
  async (request) => {
  const uid = request.auth?.uid;
  if (!uid) {
    throw new HttpsError("unauthenticated", "AUTH_REQUIRED");
  }

  const db = admin.firestore();
  const userRef = db.collection("users").doc(uid);

  await db.runTransaction(async (tx) => {
    const snap = await tx.get(userRef);
    if (!snap.exists) {
      throw new HttpsError("failed-precondition", "USER_NOT_FOUND");
    }
    const d = snap.data()!;
    const now = admin.firestore.Timestamp.now();
    const nowMillis = now.toMillis();

    let credits = toInt(d.credits, 0);
    const legacy =
      toInt(d.paidCredits, 0) + toInt(d.rewardCredits, 0);
    if (legacy > credits) {
      credits = legacy;
    }

    const lastAdRaw = d.lastAdTime ?? d.lastAdRewardAt;
    if (lastAdRaw instanceof admin.firestore.Timestamp) {
      const elapsedSec = (nowMillis - lastAdRaw.toMillis()) / 1000;
      if (elapsedSec < COOLDOWN_SEC) {
        throw new HttpsError("failed-precondition", "COOLDOWN");
      }
    }

    let daily = toInt(d.dailyAdsWatched, 0);
    const legacyCount = toInt(d.adRewardsCount, 0);
    if (legacyCount > daily) {
      daily = legacyCount;
    }

    const windowRaw = d.dailyAdsWindowStart;
    let windowStart =
      windowRaw instanceof admin.firestore.Timestamp ? windowRaw : null;

    if (!windowStart || nowMillis - windowStart.toMillis() >= DAY_MS) {
      daily = 0;
      windowStart = now;
    }

    if (daily >= MAX_DAILY) {
      throw new HttpsError("failed-precondition", "DAILY_CAP");
    }

    credits += REWARD;
    daily += 1;

    tx.update(userRef, {
      credits,
      lastAdTime: admin.firestore.FieldValue.serverTimestamp(),
      dailyAdsWatched: daily,
      dailyAdsWindowStart: windowStart,
    });
  });
  },
);

/// TalkFree credit / ad reward rules (single source of truth).
///
/// **Outbound call billing (VoIP)** — two-tier sync (see `calling_screen` + server `settleOutboundCallBill`):
/// - **Base:** 10 credits = 1 full minute (60s), same as server `CALL_CREDITS_PER_MINUTE`.
/// - **Micro-pulse:** 1 credit every 6s while connected (`/call-live-tick`).
/// - **Minimum on connect (T≈0):** 10 credits (`creditsPerCallTick`).
/// - **Final settlement:** `ceil(durationSeconds / 60) × 10`, min 10, minus prepaid from live ticks;
///   over-deduction is refunded to `paidCredits` on the server.
abstract final class CreditsPolicy {
  CreditsPolicy._();

  /// Default usable balance for a **new** Firestore `users/{uid}` document (strict zero — earn via ads / purchase).
  static const int initialCreditsForNewUser = 0;

  /// Watch this many rewarded ads to earn [creditsPerMinuteGrant] credits (1 min of talk).
  static const int adsRequiredForMinuteGrant = 4;

  /// Credits granted by the server after every [adsRequiredForMinuteGrant] ads (secured).
  static const int creditsPerMinuteGrant = 10;

  /// Credits charged per **full minute** of billed talk — **free** users (matches server default).
  static const int creditsPerMinute = 10;

  /// Per-minute rate for **premium** subscribers (matches server `CALL_CREDITS_PER_MINUTE_PREMIUM`).
  static const int creditsPerMinutePremium = 7;

  /// One-time credits when `isPremium` becomes true (client transaction; payment backend should set `isPremium`).
  static const int premiumWelcomeBonusCredits = 1000;

  /// Optional monthly bundle copy / server cron (not auto-applied in app yet).
  static const int premiumMonthlyBundleCredits = 2000;

  static int creditsPerMinuteForUser(bool isPremium) =>
      isPremium ? creditsPerMinutePremium : creditsPerMinute;

  /// First server pulse when the call becomes **Connected** (minimum charge bucket).
  static const int creditsPerCallTick = 10;

  /// Each `/call-live-tick` pulse while in call (every [connectedLiveCreditIntervalSec]).
  static const int connectedLiveCreditPerTick = 1;

  static const int connectedLiveCreditIntervalSec = 6;

  /// Must match server `CALL_CREDITS_PER_MINUTE` — settlement: max(10, ceil(durationMin) × 10) minus prepaid ticks.
  static const int callCreditsPerBilledMinute = 10;

  /// In-call balance check vs estimated charge (ceil(elapsed/60) × [callCreditsPerBilledMinute]).
  static const Duration callBalanceCheckInterval = Duration(seconds: 4);

  /// Max rewarded ad **views** per calendar day (Firestore `adRewardsCount`).
  static const int maxRewardedAdsPerDay = 24;

  /// Minimum seconds between watching rewarded ads.
  static const int adRewardCooldownSeconds = 20;

  static const Duration freeRewardCreditTtl = Duration(hours: 24);

  static const int minCreditsToStartCall = callCreditsPerBilledMinute;

  /// Minimum balance to start a call — lower for premium ([creditsPerMinutePremium] connect pulse).
  static int minCreditsToStartCallFor(bool isPremium) =>
      isPremium ? creditsPerMinutePremium : minCreditsToStartCall;

  /// Must match server `ASSIGN_NUMBER_MIN_CREDITS` (POST `/assign-number`).
  static const int assignNumberMinCredits = 100;

  /// Must match server `ASSIGN_NUMBER_MIN_ADS_WATCHED` (lifetime `ads_watched_count`).
  static const int assignNumberMinAdsWatched = 50;

  /// Kept for copy: 4 ads → 10 credits (server grant).
  static int get adsPerMinute => adsRequiredForMinuteGrant;
}

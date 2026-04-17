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

  /// Credits added per rewarded ad (must match server `REWARD_GRANT_CREDITS`, default 2).
  static const int creditsPerRewardedAd = 2;

  /// In-call UI: [CallingScreen] uses this balance value to show "Unlimited calling (Pro)" (not a real balance).
  static const int unlimitedBalanceUiSentinel = -900001;

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

  /// Free tier per-minute rate minus Pro rate (for “savings” copy on Pro home).
  static int get creditsSavedPerMinuteVsFree =>
      creditsPerMinute - creditsPerMinutePremium;

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

  /// Minimum balance to start a call — **Pro** users have unlimited calling (no minimum).
  static int minCreditsToStartCallFor(bool isPremium) =>
      isPremium ? 0 : minCreditsToStartCall;

  /// Show low-balance nudges when usable credits fall below this (free tier).
  static const int lowCreditWarningThreshold = 5;

  /// Consecutive calendar days with ≥1 rewarded ad — milestone bonuses (server `POST /grant-reward`).
  static const List<int> adStreakMilestoneDays = [3, 7, 14, 30];

  /// Must match server `ASSIGN_NUMBER_MIN_CREDITS` (POST `/assign-number`).
  static const int assignNumberMinCredits = 100;

  /// Must match server `NUMBER_RENEW_ADS_REQUIRED` (POST `/renew-number` mode `ads`).
  static const int numberRenewAdsRequired = 5;

  /// Must match server `NUMBER_RENEW_CREDITS` (POST `/renew-number` mode `credits`).
  static const int numberRenewCredits = 100;

  /// Must match server `MAX_RENEWALS_PER_DAY` (POST `/renew-number`).
  static const int maxRenewalsPerDay = 2;

  /// Must match server `SMS_OUTBOUND_CREDIT_COST` (POST `/send-sms`).
  static const int smsOutboundCreditCost = 3;

  /// Must match server `ASSIGN_NUMBER_MIN_ADS_WATCHED` (lifetime `ads_watched_count`).
  static const int assignNumberMinAdsWatched = 50;

  /// Must match server `PLAN_*_MS` defaults in `server/index.js` (assign-number lease).
  static int leaseDurationMsForPlanType(String? planType) {
    switch (planType?.toLowerCase().trim()) {
      case 'daily':
        return const Duration(days: 1).inMilliseconds;
      case 'weekly':
        return const Duration(days: 7).inMilliseconds;
      case 'monthly':
        return 2592000000; // 30d — server PLAN_MONTHLY_MS default
      case 'yearly':
        return 31536000000; // 365d — server PLAN_YEARLY_MS default
      default:
        return 2592000000;
    }
  }
}

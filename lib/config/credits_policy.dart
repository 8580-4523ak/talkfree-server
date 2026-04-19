/// TalkFree credit / ad reward rules (single source of truth).
///
/// **Outbound call billing (VoIP)** — server `POST /call-live-tick` + `settleOutboundCallBill`:
/// - **Free:** 1 credit every 6s while connected (10 credits / billed minute).
/// - **Premium:** 1 credit every ~8571ms (7 credits / billed minute).
/// - **Settlement** reconciles Twilio duration vs prepaid live ticks (see `server/index.js`).
abstract final class CreditsPolicy {
  CreditsPolicy._();

  /// Default usable balance for a **new** Firestore `users/{uid}` document.
  static const int initialCreditsForNewUser = 0;

  /// Credits per rewarded ad (after first lifetime ad on server).
  static int creditsPerRewardedAdForUser(bool isPremium) =>
      isPremium ? 20 : 10;

  /// Max rewarded ad grants per UTC day (server-enforced).
  static int maxRewardedAdsForUser(bool isPremium) =>
      isPremium ? 25 : 10;

  /// Minimum seconds between ad grants (server + UI cooldown).
  static int adRewardCooldownSecondsForUser(bool isPremium) =>
      isPremium ? 10 : 45;

  /// Legacy single-tier constant (free tier cap) — prefer [maxRewardedAdsForUser].
  static const int maxRewardedAdsPerDay = 10;

  /// Legacy free-tier cooldown — prefer [adRewardCooldownSecondsForUser].
  static const int adRewardCooldownSeconds = 45;

  /// Credits charged per **full minute** of billed talk — **free** users.
  static const int creditsPerMinute = 10;

  /// Per-minute rate for **premium** (server `CALL_CREDITS_PER_MINUTE_PREMIUM`).
  static const int creditsPerMinutePremium = 7;

  /// One-time welcome credits when premium is first activated (server `PREMIUM_WELCOME_BONUS`).
  static const int premiumWelcomeBonusCredits = 500;

  /// Monthly bonus range midpoint (server `POST /claim-premium-monthly-bonus`).
  static const int premiumMonthlyBundleCredits = 400;

  /// After balance hits 0 on a premium call, keep the line open this many seconds (once per call; UI + no extra ticks).
  static const int premiumCallGraceSeconds = 20;

  /// Starter pack: credits added on successful `starter_credits` purchase.
  static const int starterPackCredits = 135;

  static int creditsPerMinuteForUser(bool isPremium) =>
      isPremium ? creditsPerMinutePremium : creditsPerMinute;

  /// Free tier per-minute rate minus Pro rate (for “savings” copy on Pro home).
  static int get creditsSavedPerMinuteVsFree =>
      creditsPerMinute - creditsPerMinutePremium;

  /// Legacy: first connect bucket in older docs; live ticks use [connectedLiveCreditPerTick].
  static const int creditsPerCallTick = 10;

  /// Each `/call-live-tick` pulse while in call (**free:** every [connectedLiveCreditIntervalSec]).
  static const int connectedLiveCreditPerTick = 1;

  static const int connectedLiveCreditIntervalSec = 6;

  /// Premium live tick period (ms): ~`60000 / creditsPerMinutePremium` → 7 credits / minute.
  static const int premiumLiveTickPeriodMs =
      8571; // round(60000 / 7); keep in sync with server settlement

  static Duration get premiumLiveTickPeriod =>
      const Duration(milliseconds: premiumLiveTickPeriodMs);

  /// Settlement alignment for free tier (ceil(seconds / 6) tick units).
  static const int callCreditsPerBilledMinute = 10;

  static const int callCreditsPerBilledMinutePremium = 7;

  static int callCreditsPerBilledMinuteForUser(bool isPremium) =>
      isPremium ? callCreditsPerBilledMinutePremium : callCreditsPerBilledMinute;

  static const Duration callBalanceCheckInterval = Duration(seconds: 4);

  static const Duration freeRewardCreditTtl = Duration(hours: 24);

  /// Minimum balance to start a call (both tiers — credit-based calling).
  static const int minCreditsToStartCall = callCreditsPerBilledMinute;

  static int minCreditsToStartCallFor(bool isPremium) => minCreditsToStartCall;

  /// Show low-balance nudges when usable credits fall below this.
  static const int lowCreditWarningThreshold = 10;

  /// Consecutive UTC days with ≥1 rewarded ad — milestone bonuses (server `POST /grant-reward`).
  static const List<int> adStreakMilestoneDays = [3, 7, 14, 30];

  static int streakBonusCreditsAtMilestoneDay(int day) {
    switch (day) {
      case 3:
        return 5;
      case 7:
        return 10;
      case 14:
        return 25;
      case 30:
        return 50;
      default:
        return 0;
    }
  }

  static ({int day, int bonusCredits})? nextStreakMilestoneAfter(int currentStreakDays) {
    for (final d in adStreakMilestoneDays) {
      if (currentStreakDays < d) {
        final b = streakBonusCreditsAtMilestoneDay(d);
        if (b > 0) return (day: d, bonusCredits: b);
      }
    }
    return null;
  }

  static const int assignNumberMinCredits = 100;
  static const int numberRenewAdsRequired = 5;
  static const int numberRenewCredits = 100;
  static const int maxRenewalsPerDay = 2;
  static const int smsOutboundCreditCost = 3;
  static const int assignNumberMinAdsWatched = 50;

  static int leaseDurationMsForPlanType(String? planType) {
    switch (planType?.toLowerCase().trim()) {
      case 'daily':
        return const Duration(days: 1).inMilliseconds;
      case 'weekly':
        return const Duration(days: 7).inMilliseconds;
      case 'monthly':
        return 2592000000;
      case 'yearly':
        return 31536000000;
      default:
        return 2592000000;
    }
  }
}

/// TalkFree credit / ad reward rules (single source of truth).
abstract final class CreditsPolicy {
  CreditsPolicy._();

  /// Watch this many rewarded ads to earn [creditsPerMinuteGrant] credits (1 min of talk).
  static const int adsRequiredForMinuteGrant = 4;

  /// Credits granted by the server after every [adsRequiredForMinuteGrant] ads (secured).
  static const int creditsPerMinuteGrant = 10;

  static const int creditsPerMinute = 20;
  static const int creditsPerCallTick = 10;

  /// In-call UI: after the first full minute of connected time, deduct this many credits every [connectedLiveCreditIntervalSec].
  static const int connectedLiveCreditPerTick = 1;

  static const int connectedLiveCreditIntervalSec = 6;

  /// Must match server `CALL_CREDITS_PER_MINUTE` — billed as ceil(callMinutes) × this at call end.
  static const int callCreditsPerBilledMinute = 10;

  /// In-call balance check vs estimated charge (ceil(elapsed/60) × [callCreditsPerBilledMinute]).
  static const Duration callBalanceCheckInterval = Duration(seconds: 4);

  /// Max rewarded ad **views** per calendar day (Firestore `adRewardsCount`).
  static const int maxRewardedAdsPerDay = 24;

  /// Minimum seconds between watching rewarded ads.
  static const int adRewardCooldownSeconds = 20;

  static const Duration freeRewardCreditTtl = Duration(hours: 24);

  static const int minCreditsToStartCall = callCreditsPerBilledMinute;

  /// Kept for copy: 4 ads → 10 credits (server grant).
  static int get adsPerMinute => adsRequiredForMinuteGrant;
}

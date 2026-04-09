/// TalkFree credit / ad reward rules (single source of truth).
abstract final class CreditsPolicy {
  CreditsPolicy._();

  static const int creditsPerRewardedAd = 4;
  static const int creditsPerMinute = 20;
  static const int creditsPerCallTick = 10;
  static const Duration callTickInterval = Duration(seconds: 30);

  static const int maxRewardedAdsPerDay = 20;
  static const int adRewardCooldownSeconds = 90;
  static const Duration freeRewardCreditTtl = Duration(hours: 24);

  static const int minCreditsToStartCall = creditsPerCallTick;

  /// 5 × 4 = 20 credits = 1 minute.
  static int get adsPerMinute => creditsPerMinute ~/ creditsPerRewardedAd;
}

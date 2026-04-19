/// Psychology / conversion strings (keep concise; avoid overuse in one screen).
abstract final class MonetizationCopy {
  MonetizationCopy._();

  /// Trust row — headline (number) + subtitle line below.
  static const String socialProofUpgradesTitle = '8,000+';
  static const String socialProofUpgradesSubtitle = 'in the last 24 hours';

  static const String proWithinTwoDays =
      '⚡ Most users go Pro within 2 days';

  /// Shown under the ad cooldown bar (free tier).
  static const String cooldownGoProHint =
      'Short wait — Pro skips this cooldown';
  static const String limitedTimeBonus = 'Limited time bonus';

  static const String watchAdEarn = 'Watch Ad to Earn Credits';
  static const String needCreditsToCall = 'You need credits to call';

  static const String outOfCreditsTitle = "You're out of credits";
  static const String tiredOfAdsTitle = 'Tired of watching ads?';
  static const String tiredOfAdsBody = 'Upgrade and call instantly ⚡';
  static const String dailyLimitTitle = 'Daily limit reached';
  static const String dailyLimitBody = 'Upgrade to continue now';

  /// One-shot hint while on a call (free tier, low balance).
  static String inCallLowCreditsProBenefit({required int premiumCreditsPerMin}) =>
      'Balance is low. Pro uses $premiumCreditsPerMin credits/min with steadier routing — optional upgrade.';

  static const String premiumInstantHeadline = 'Start Calling Instantly ⚡';
  static const String premiumInstantSub = '⚡ Instant access enabled';
}

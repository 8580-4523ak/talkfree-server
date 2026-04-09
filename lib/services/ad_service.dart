import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

/// Loads and shows Google [RewardedAd] (Google test unit IDs by default).
class AdService {
  AdService._();
  static final AdService instance = AdService._();

  /// Google sample rewarded ad — Android.
  static const String rewardedTestUnitIdAndroid =
      'ca-app-pub-3940256099942544/5224354917';

  /// Google sample rewarded ad — iOS.
  static const String rewardedTestUnitIdIos =
      'ca-app-pub-3940256099942544/1712485313';

  static String get _rewardedUnitId {
    switch (defaultTargetPlatform) {
      case TargetPlatform.iOS:
        return rewardedTestUnitIdIos;
      default:
        return rewardedTestUnitIdAndroid;
    }
  }

  /// Loads a rewarded ad, shows it, and completes with `true` if the user earned the reward.
  ///
  /// Returns `false` if load/show failed or the user closed the ad without earning.
  Future<bool> loadAndShowRewardedAd() async {
    try {
      await MobileAds.instance.initialize();
    } catch (e, st) {
      debugPrint('MobileAds.initialize (lazy): $e\n$st');
    }

    final completer = Completer<bool>();
    var userEarnedReward = false;

    try {
      await RewardedAd.load(
        adUnitId: _rewardedUnitId,
        request: const AdRequest(),
        rewardedAdLoadCallback: RewardedAdLoadCallback(
          onAdLoaded: (RewardedAd ad) {
            ad.fullScreenContentCallback = FullScreenContentCallback(
              onAdDismissedFullScreenContent: (RewardedAd ad) {
                ad.dispose();
                if (!completer.isCompleted) {
                  completer.complete(userEarnedReward);
                }
              },
              onAdFailedToShowFullScreenContent: (RewardedAd ad, AdError error) {
                ad.dispose();
                if (!completer.isCompleted) {
                  completer.complete(false);
                }
              },
            );
            ad.show(
              onUserEarnedReward: (AdWithoutView ad, RewardItem reward) {
                userEarnedReward = true;
              },
            );
          },
          onAdFailedToLoad: (LoadAdError error) {
            if (!completer.isCompleted) {
              completer.complete(false);
            }
          },
        ),
      );
    } catch (e, st) {
      debugPrint('RewardedAd.load error: $e\n$st');
      return false;
    }

    return completer.future;
  }
}

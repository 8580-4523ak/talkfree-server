import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

/// AdMob **Rewarded** ads — load/show only.
///
/// [loadAndShowRewardedAd] completes with **`true` only if** the user earned the
/// reward ([RewardedAd] `onUserEarnedReward`). If they close the ad early or
/// the load/show fails, it returns **`false`**.
///
/// **Call `POST /grant-reward` only after `true`** — the UI starts a
/// client cooldown when an ad completes with reward; the server also enforces
/// the same gap via `last_ad_timestamp`.
class AdService {
  AdService._();
  static final AdService instance = AdService._();

  /// Holds the in-flight [RewardedAd] after load until [dispose] runs on fullscreen exit.
  /// `null` means no ad instance is retained — the next [loadAndShowRewardedAd] always loads fresh.
  RewardedAd? _activeRewardedAd;

  void _disposeRewardedAd(RewardedAd ad) {
    try {
      ad.dispose();
    } finally {
      if (identical(_activeRewardedAd, ad)) {
        _activeRewardedAd = null;
      }
    }
  }

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
    final stale = _activeRewardedAd;
    if (stale != null) {
      if (kDebugMode) {
        debugPrint('AdService: disposing stale RewardedAd before load');
      }
      _disposeRewardedAd(stale);
    }

    try {
      await MobileAds.instance.initialize();
    } catch (e, st) {
      if (kDebugMode) {
        debugPrint('MobileAds.initialize (lazy): $e\n$st');
      }
    }

    final completer = Completer<bool>();
    var userEarnedReward = false;

    try {
      await RewardedAd.load(
        adUnitId: _rewardedUnitId,
        request: const AdRequest(),
        rewardedAdLoadCallback: RewardedAdLoadCallback(
          onAdLoaded: (RewardedAd ad) {
            _activeRewardedAd = ad;
            ad.fullScreenContentCallback = FullScreenContentCallback(
              // Dispose when fullscreen closes — do not dispose in [onUserEarnedReward]
              // (reward fires while the ad is still visible; [RewardedAd] is this `ad`).
              onAdDismissedFullScreenContent: (RewardedAd ad) {
                _disposeRewardedAd(ad);
                if (!completer.isCompleted) {
                  completer.complete(userEarnedReward);
                }
              },
              onAdFailedToShowFullScreenContent: (RewardedAd ad, AdError error) {
                _disposeRewardedAd(ad);
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
      if (kDebugMode) {
        debugPrint('RewardedAd.load error: $e\n$st');
      }
      return false;
    }

    return completer.future;
  }
}

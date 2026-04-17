import 'dart:async' show unawaited;

import 'package:flutter/material.dart';

import '../services/ad_service.dart';
import '../services/grant_reward_service.dart' show GrantRewardException, GrantRewardService;
import '../services/reward_sound_service.dart';
import '../widgets/engagement_overlays.dart';

/// Plays a rewarded ad then POSTs `/grant-reward`. Use from any screen (server enforces limits).
Future<bool> runRewardedAdGrantFlow(BuildContext context) async {
  final earned = await AdService.instance.loadAndShowRewardedAd();
  if (!context.mounted) return false;
  if (!earned) return false;
  try {
    final result = await GrantRewardService.instance.requestMinuteGrant();
    if (!context.mounted) return true;
    if (result.creditsAdded > 0) {
      unawaited(RewardSoundService.playCoin());
      EngagementOverlays.showAdRewardFanfare(
        context,
        creditsAdded: result.creditsAdded,
        streakBonus: result.streakBonus,
        streakDays: result.streakCount,
        welcomeFirstAd: result.firstLifetimeAd,
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Reward recorded — credits will sync shortly.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
    return true;
  } on GrantRewardException catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e.message),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
    return false;
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Could not apply reward: $e'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
    return false;
  }
}

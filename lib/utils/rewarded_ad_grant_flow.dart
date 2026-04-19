import 'dart:async' show unawaited;

import 'package:flutter/material.dart';

import '../services/ad_service.dart';
import '../services/grant_reward_service.dart' show GrantRewardException, GrantRewardService;
import '../services/reward_sound_service.dart';
import '../theme/app_theme.dart';
import 'app_snackbar.dart';
import '../widgets/engagement_overlays.dart';

/// Plays a rewarded ad then POSTs `/grant-reward`. Use from any screen (server enforces limits).
Future<bool> runRewardedAdGrantFlow(
  BuildContext context, {
  required bool isPremium,
}) async {
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
        isPremium: isPremium,
      );
    } else {
      AppSnackBar.show(context,
        SnackBar(
          content: const Text('Reward recorded — credits will sync shortly.'),
          behavior: SnackBarBehavior.floating,
          margin: AppTheme.snackBarFloatingMargin(context),
          duration: AppTheme.snackBarCalmDuration,
        ),
      );
    }
    return true;
  } on GrantRewardException catch (e) {
    if (context.mounted) {
      AppSnackBar.show(context,
        SnackBar(
          content: Text(e.message),
          behavior: SnackBarBehavior.floating,
          margin: AppTheme.snackBarFloatingMargin(context),
          duration: AppTheme.snackBarCalmDuration,
        ),
      );
    }
    return false;
  } catch (e) {
    if (context.mounted) {
      AppSnackBar.show(context,
        SnackBar(
          content: Text('Could not apply reward: $e'),
          behavior: SnackBarBehavior.floating,
          margin: AppTheme.snackBarFloatingMargin(context),
          duration: AppTheme.snackBarCalmDuration,
        ),
      );
    }
    return false;
  }
}

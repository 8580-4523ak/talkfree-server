import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../config/credits_policy.dart';
import '../services/grant_reward_service.dart' show GrantRewardPurpose;
import '../theme/app_colors.dart';
import '../utils/monetization_copy.dart';
import 'cooldown_reward_progress_bar.dart';
import 'recommended_ad_badge.dart';

/// Three rewarded-ad CTAs (call / number / OTP) — same behavior as Home strip.
class PurposeRewardedAdStrip extends StatelessWidget {
  const PurposeRewardedAdStrip({
    super.key,
    required this.canTapAd,
    required this.grantRewardPending,
    required this.rewardedAdBusy,
    required this.cooldownRemaining,
    required this.dailyLimitReached,
    required this.emphasizePurpose,
    required this.showRewardRecommendedBadge,
    required this.cooldownPolicySeconds,
    required this.onPurposeAd,
    this.subtitleCallIsPremium = false,
  });

  final bool canTapAd;
  final bool grantRewardPending;
  final bool rewardedAdBusy;
  final int cooldownRemaining;
  final bool dailyLimitReached;
  final GrantRewardPurpose emphasizePurpose;
  final bool showRewardRecommendedBadge;
  final int cooldownPolicySeconds;
  final Future<void> Function(GrantRewardPurpose purpose) onPurposeAd;

  /// Call-row subtitle uses [CreditsPolicy.rewardAdEmotionalSubtitleCall] with this tier.
  final bool subtitleCallIsPremium;

  bool get _cooldownGate =>
      cooldownRemaining > 0 && !dailyLimitReached && !rewardedAdBusy;

  @override
  Widget build(BuildContext context) {
    final tapEnabled =
        canTapAd && !grantRewardPending && !rewardedAdBusy && !dailyLimitReached;
    final showBusy = grantRewardPending || rewardedAdBusy;

    if (dailyLimitReached) {
      return Container(
        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 14),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          color: AppColors.surfaceDark.withValues(alpha: 0.92),
          border: Border.all(color: AppColors.cardBorderSubtle),
        ),
        child: Text(
          'Daily ad limit reached — back tomorrow.',
          textAlign: TextAlign.center,
          style: GoogleFonts.inter(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: AppColors.textMutedOnDark,
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_cooldownGate) ...[
          Text(
            'Wait ${cooldownRemaining}s to watch next ad',
            textAlign: TextAlign.center,
            style: GoogleFonts.inter(
              fontSize: 13,
              fontWeight: FontWeight.w800,
              color: AppColors.primary,
            ),
          ),
          const SizedBox(height: 8),
          CooldownRewardProgressBar(
            remainingSeconds: cooldownRemaining,
            totalCooldownSeconds: cooldownPolicySeconds,
          ),
          const SizedBox(height: 6),
          Text(
            MonetizationCopy.cooldownGoProHint,
            textAlign: TextAlign.center,
            style: GoogleFonts.inter(
              fontSize: 10,
              fontWeight: FontWeight.w500,
              height: 1.4,
              letterSpacing: 0.02,
              color: AppColors.textMutedOnDark.withValues(alpha: 0.58),
            ),
          ),
          const SizedBox(height: 14),
        ],
        _PurposeRewardButton(
          tapEnabled: tapEnabled,
          showBusy: showBusy,
          purpose: GrantRewardPurpose.call,
          isPrimary: emphasizePurpose == GrantRewardPurpose.call,
          showRewardRecommendedBadge: showRewardRecommendedBadge,
          icon: Icons.bolt_rounded,
          label: 'Watch ad → Get call credits',
          subtitle: CreditsPolicy.rewardAdEmotionalSubtitleCall(
            subtitleCallIsPremium,
          ),
          onPurposeAd: onPurposeAd,
        ),
        const SizedBox(height: 10),
        _PurposeRewardButton(
          tapEnabled: tapEnabled,
          showBusy: showBusy,
          purpose: GrantRewardPurpose.number,
          isPrimary: emphasizePurpose == GrantRewardPurpose.number,
          showRewardRecommendedBadge: showRewardRecommendedBadge,
          icon: Icons.phone_android_rounded,
          label: 'Watch ad → Unlock number',
          subtitle: CreditsPolicy.rewardAdEmotionalSubtitleNumber(),
          onPurposeAd: onPurposeAd,
        ),
        const SizedBox(height: 10),
        _PurposeRewardButton(
          tapEnabled: tapEnabled,
          showBusy: showBusy,
          purpose: GrantRewardPurpose.otp,
          isPrimary: emphasizePurpose == GrantRewardPurpose.otp,
          showRewardRecommendedBadge: showRewardRecommendedBadge,
          icon: Icons.sms_outlined,
          label: 'Watch ad → Send SMS',
          subtitle: CreditsPolicy.rewardAdEmotionalSubtitleOtp(),
          onPurposeAd: onPurposeAd,
        ),
      ],
    );
  }
}

class _PurposeRewardButton extends StatelessWidget {
  const _PurposeRewardButton({
    required this.tapEnabled,
    required this.showBusy,
    required this.purpose,
    required this.isPrimary,
    required this.showRewardRecommendedBadge,
    required this.icon,
    required this.label,
    required this.subtitle,
    required this.onPurposeAd,
  });

  final bool tapEnabled;
  final bool showBusy;
  final GrantRewardPurpose purpose;
  final bool isPrimary;
  final bool showRewardRecommendedBadge;
  final IconData icon;
  final String label;
  final String subtitle;
  final Future<void> Function(GrantRewardPurpose purpose) onPurposeAd;

  @override
  Widget build(BuildContext context) {
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(14),
    );
    final busy = showBusy && tapEnabled;
    final Color iconColor;
    final Color titleColor;
    final Color subtitleColor;
    if (!tapEnabled) {
      iconColor = AppColors.textMutedOnDark;
      titleColor = AppColors.textMutedOnDark;
      subtitleColor = AppColors.textMutedOnDark.withValues(alpha: 0.88);
    } else if (isPrimary) {
      iconColor = AppColors.onPrimaryButton;
      titleColor = AppColors.onPrimaryButton;
      subtitleColor = AppColors.onPrimaryButton.withValues(alpha: 0.88);
    } else {
      iconColor = AppColors.primary;
      titleColor = AppColors.textOnDark;
      subtitleColor = AppColors.textMutedOnDark;
    }
    final content = Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: iconColor, size: 22),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: GoogleFonts.inter(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    color: titleColor,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  subtitle,
                  style: GoogleFonts.inter(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w600,
                    height: 1.25,
                    color: subtitleColor,
                  ),
                ),
              ],
            ),
          ),
          if (busy)
            Padding(
              padding: const EdgeInsets.only(left: 6, top: 2),
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2.2,
                  color: iconColor.withValues(alpha: 0.95),
                ),
              ),
            ),
        ],
      ),
    );

    Widget withRecommended(Widget inner) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (isPrimary && showRewardRecommendedBadge) ...[
            const Center(child: RecommendedAdBadge()),
            const SizedBox(height: 6),
          ] else if (isPrimary) ...[
            const SizedBox(height: 4),
          ],
          inner,
        ],
      );
    }

    if (!tapEnabled) {
      return withRecommended(
        FilledButton(
          onPressed: null,
          style: FilledButton.styleFrom(
            foregroundColor: AppColors.textMutedOnDark,
            disabledForegroundColor: AppColors.textMutedOnDark,
            backgroundColor: AppColors.surfaceDark.withValues(alpha: 0.4),
            disabledBackgroundColor:
                AppColors.surfaceDark.withValues(alpha: 0.4),
            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 12),
            minimumSize: const Size.fromHeight(52),
            shape: shape,
            elevation: 0,
            splashFactory: NoSplash.splashFactory,
          ),
          child: content,
        ),
      );
    }

    if (isPrimary) {
      return withRecommended(
        FilledButton(
          onPressed: () => onPurposeAd(purpose),
          style: FilledButton.styleFrom(
            foregroundColor: AppColors.onPrimaryButton,
            backgroundColor: AppColors.primary,
            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 12),
            minimumSize: const Size.fromHeight(52),
            shape: shape,
            elevation: 0,
          ),
          child: content,
        ),
      );
    }

    return withRecommended(
      FilledButton.tonal(
        onPressed: () => onPurposeAd(purpose),
        style: FilledButton.styleFrom(
          foregroundColor: AppColors.textOnDark,
          backgroundColor: AppColors.surfaceDark.withValues(alpha: 0.94),
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 12),
          minimumSize: const Size.fromHeight(52),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
            side: BorderSide(color: AppColors.primary.withValues(alpha: 0.4)),
          ),
        ),
        child: content,
      ),
    );
  }
}

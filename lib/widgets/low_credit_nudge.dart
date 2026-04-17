import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../config/credits_policy.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import '../screens/subscription_screen.dart';

/// When balance is critically low on the free tier — watch ad or upgrade.
class LowCreditNudge extends StatelessWidget {
  const LowCreditNudge({
    super.key,
    required this.credits,
    required this.isPremium,
    required this.onWatchAd,
  });

  final int credits;
  final bool isPremium;
  final VoidCallback onWatchAd;

  @override
  Widget build(BuildContext context) {
    if (isPremium || credits >= CreditsPolicy.lowCreditWarningThreshold) {
      return const SizedBox.shrink();
    }
    return Material(
      color: AppColors.cardDark.withValues(alpha: 0.94),
      borderRadius: BorderRadius.circular(14),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.timer_outlined,
                  color: AppTheme.neonGreen.withValues(alpha: 0.95),
                  size: 22,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Only few minutes left',
                    style: GoogleFonts.inter(
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                      height: 1.3,
                      color: Theme.of(context).colorScheme.onSurface,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: onWatchAd,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppTheme.neonGreen,
                      side: BorderSide(
                        color: AppTheme.neonGreen.withValues(alpha: 0.65),
                      ),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: Text(
                      'Watch ad',
                      style: GoogleFonts.inter(fontWeight: FontWeight.w700),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: FilledButton(
                    onPressed: () {
                      Navigator.of(context).push<void>(
                        SubscriptionScreen.createRoute(),
                      );
                    },
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: AppColors.onPrimary,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: Text(
                      'Go Pro',
                      style: GoogleFonts.inter(fontWeight: FontWeight.w800),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

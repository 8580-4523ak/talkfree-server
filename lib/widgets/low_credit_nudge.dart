import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../config/credits_policy.dart';
import '../theme/app_colors.dart';
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
      color: AppColors.cardDark.withValues(alpha: 0.98),
      borderRadius: BorderRadius.circular(14),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.timer_outlined,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                  size: 20,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'You need credits to call',
                    style: GoogleFonts.inter(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
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
                      foregroundColor: Theme.of(context).colorScheme.onSurface,
                      side: BorderSide(
                        color: Colors.white.withValues(alpha: 0.18),
                      ),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: Text(
                      'WATCH AD',
                      style: GoogleFonts.inter(
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.4,
                      ),
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
                      elevation: 0,
                      shadowColor: Colors.transparent,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: Text(
                      'GO PRO',
                      style: GoogleFonts.inter(
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.45,
                      ),
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

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../config/credits_policy.dart';
import '../services/assign_number_service.dart';
import '../services/firestore_user_service.dart';
import '../theme/app_colors.dart';
import '../theme/talkfree_colors.dart';
import 'number_selection_screen.dart';

/// Ads required to unlock a free US number (progress task).
const int kAdsRequiredForFreeUsNumber = 50;

/// Route args for [VirtualNumberScreen].
class VirtualNumberRouteArgs {
  const VirtualNumberRouteArgs({
    required this.userUid,
    required this.userCredits,
  });

  final String userUid;
  final int userCredits;
}

/// "The Store" — unlock 2nd line, ad progress, subscription plans (buy = UI only).
class VirtualNumberScreen extends StatefulWidget {
  const VirtualNumberScreen({
    super.key,
    required this.userUid,
    required this.userCredits,
  });

  static const String routeName = '/virtual-number';

  static Route<void> createRoute(RouteSettings settings) {
    final args = settings.arguments;
    final uid = args is VirtualNumberRouteArgs ? args.userUid : '';
    final credits = args is VirtualNumberRouteArgs ? args.userCredits : 0;
    return MaterialPageRoute<void>(
      settings: settings,
      builder: (_) => VirtualNumberScreen(
        userUid: uid,
        userCredits: credits,
      ),
    );
  }

  final String userUid;
  final int userCredits;

  @override
  State<VirtualNumberScreen> createState() => _VirtualNumberScreenState();

  static String? _readAssigned(Map<String, dynamic>? data) {
    if (data == null) return null;
    for (final key in ['assigned_number', 'virtual_number', 'allocatedNumber', 'number']) {
      final v = data[key];
      if (v is String) {
        final t = v.trim();
        if (t.isNotEmpty && t != 'none') return t;
      }
    }
    return null;
  }

  /// Lifetime rewarded-ad views only (`ads_watched_count`). No fallback to daily fields.
  static int _readAdsWatched(Map<String, dynamic>? data) {
    if (data == null) return 0;
    final v = data['ads_watched_count'];
    if (v is int) return v;
    if (v is num) return v.toInt();
    return 0;
  }
}

class _VirtualNumberScreenState extends State<VirtualNumberScreen> {
  bool _claiming = false;

  Future<void> _claimUsNumber(
    BuildContext context,
    int adsWatched,
    int usableCredits,
    bool isPremium,
  ) async {
    final eligible = isPremium ||
        adsWatched >= CreditsPolicy.assignNumberMinAdsWatched ||
        usableCredits >= CreditsPolicy.assignNumberMinCredits;
    if (!eligible || _claiming) return;
    setState(() => _claiming = true);
    try {
      final r = await AssignNumberService.instance.requestAssignNumber();
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            r.alreadyAssigned
                ? 'Your line: ${r.assignedNumber}'
                : 'Your new US number: ${r.assignedNumber}',
            style: GoogleFonts.inter(),
          ),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } on AssignNumberException catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(e.message, style: GoogleFonts.inter()),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Could not provision number: $e', style: GoogleFonts.inter()),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _claiming = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bg = Color.lerp(TalkFreeColors.deepBlack, TalkFreeColors.cardBg, 0.35)!;

    return Scaffold(
      backgroundColor: bg,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Text(
          'My Number',
          style: GoogleFonts.poppins(
            fontWeight: FontWeight.w700,
            fontSize: 20,
            color: TalkFreeColors.offWhite,
          ),
        ),
        iconTheme: const IconThemeData(color: TalkFreeColors.offWhite),
      ),
      body: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        stream: FirestoreUserService.watchUserDocument(widget.userUid),
        builder: (context, snap) {
          final data = snap.data?.data();
          final assigned = VirtualNumberScreen._readAssigned(data);
          final adsWatched = VirtualNumberScreen._readAdsWatched(data);
          final usable = FirestoreUserService.computeUsableCredits(data);
          final isPremium = FirestoreUserService.isPremiumFromUserData(data);
          final canClaim = isPremium ||
              adsWatched >= CreditsPolicy.assignNumberMinAdsWatched ||
              usable >= CreditsPolicy.assignNumberMinCredits;

          if (snap.hasError) {
            return Center(
              child: Text(
                'Could not load profile.\n${snap.error}',
                textAlign: TextAlign.center,
                style: GoogleFonts.inter(color: TalkFreeColors.mutedWhite),
              ),
            );
          }

          return SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (assigned != null) ...[
                  _AssignedNumberCard(number: assigned),
                  const SizedBox(height: 24),
                  OutlinedButton.icon(
                    onPressed: () {
                      Navigator.of(context).pushNamed(
                        NumberSelectionScreen.routeName,
                        arguments: NumberSelectionRouteArgs(
                          userUid: widget.userUid,
                          userCredits: widget.userCredits,
                        ),
                      );
                    },
                    icon: const Icon(Icons.search_rounded, color: AppColors.primary),
                    label: Text(
                      'Change / browse numbers',
                      style: GoogleFonts.montserrat(
                        fontWeight: FontWeight.w700,
                        color: AppColors.primary,
                      ),
                    ),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      side: BorderSide(color: AppColors.primary.withValues(alpha: 0.65)),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                  ),
                ] else ...[
                  const _UnlockHeroCard(),
                  const SizedBox(height: 24),
                  _ProgressTaskCard(adsWatched: adsWatched),
                  const SizedBox(height: 20),
                  FilledButton.icon(
                    onPressed: (!canClaim || _claiming)
                        ? null
                        : () => _claimUsNumber(context, adsWatched, usable, isPremium),
                    icon: _claiming
                        ? const SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(
                              strokeWidth: 2.2,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(Icons.rocket_launch_rounded),
                    label: Text(
                      _claiming
                          ? 'Provisioning…'
                          : 'Claim free US number',
                      style: GoogleFonts.montserrat(
                        fontWeight: FontWeight.w800,
                        fontSize: 15,
                      ),
                    ),
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      backgroundColor: AppColors.primary,
                      foregroundColor: Colors.white,
                      disabledBackgroundColor:
                          AppColors.primary.withValues(alpha: 0.35),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                  ),
                  if (!canClaim)
                    Padding(
                      padding: const EdgeInsets.only(top: 10),
                      child: Text(
                        'Watch ${CreditsPolicy.assignNumberMinAdsWatched} ads '
                        'or reach ${CreditsPolicy.assignNumberMinCredits} credits to unlock.',
                        textAlign: TextAlign.center,
                        style: GoogleFonts.inter(
                          fontSize: 12,
                          height: 1.35,
                          color: TalkFreeColors.mutedWhite,
                        ),
                      ),
                    ),
                  const SizedBox(height: 28),
                  _SubscriptionSection(
                    onBuy: (String plan) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                            '$plan — coming soon',
                            style: GoogleFonts.inter(),
                          ),
                          behavior: SnackBarBehavior.floating,
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: 20),
                  TextButton.icon(
                    onPressed: () {
                      Navigator.of(context).pushNamed(
                        NumberSelectionScreen.routeName,
                        arguments: NumberSelectionRouteArgs(
                          userUid: widget.userUid,
                          userCredits: widget.userCredits,
                        ),
                      );
                    },
                    icon: Icon(
                      Icons.phone_in_talk_outlined,
                      size: 20,
                      color: AppColors.primary.withValues(alpha: 0.9),
                    ),
                    label: Text(
                      'Browse available numbers',
                      style: GoogleFonts.montserrat(
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                        color: TalkFreeColors.mutedWhite,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          );
        },
      ),
    );
  }
}

class _AssignedNumberCard extends StatelessWidget {
  const _AssignedNumberCard({required this.number});

  final String number;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            AppColors.primary.withValues(alpha: 0.35),
            TalkFreeColors.cardBg,
          ],
        ),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.35)),
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withValues(alpha: 0.18),
            blurRadius: 24,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.verified_rounded, color: AppColors.primary, size: 28),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Your 2nd line',
                  style: GoogleFonts.poppins(
                    fontWeight: FontWeight.w700,
                    fontSize: 18,
                    color: TalkFreeColors.offWhite,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          SelectableText(
            number,
            style: GoogleFonts.jetBrainsMono(
              fontSize: 22,
              fontWeight: FontWeight.w600,
              color: AppColors.primary,
              letterSpacing: 0.5,
            ),
          ),
        ],
      ),
    );
  }
}

class _UnlockHeroCard extends StatelessWidget {
  const _UnlockHeroCard();

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: Container(
        padding: const EdgeInsets.fromLTRB(22, 26, 22, 26),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(22),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              const Color(0xFF0F172A),
              const Color(0xFF1E293B),
              AppColors.primary.withValues(alpha: 0.22),
            ],
            stops: const [0.0, 0.55, 1.0],
          ),
          border: Border.all(
            color: AppColors.primary.withValues(alpha: 0.45),
            width: 1.2,
          ),
          boxShadow: [
            BoxShadow(
              color: AppColors.primary.withValues(alpha: 0.25),
              blurRadius: 28,
              spreadRadius: 0,
              offset: const Offset(0, 14),
            ),
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.45),
              blurRadius: 20,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: AppColors.primary.withValues(alpha: 0.15),
                    border: Border.all(
                      color: AppColors.primary.withValues(alpha: 0.4),
                    ),
                  ),
                  child: Icon(
                    Icons.sim_card_rounded,
                    color: AppColors.primary.withValues(alpha: 0.95),
                    size: 28,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Text(
                    'Unlock Your Private 2nd Line',
                    style: GoogleFonts.poppins(
                      fontWeight: FontWeight.w800,
                      fontSize: 22,
                      height: 1.2,
                      color: TalkFreeColors.offWhite,
                      letterSpacing: -0.3,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Text(
              'A dedicated US number for calls & texts — separate from your personal SIM.',
              style: GoogleFonts.inter(
                fontSize: 14,
                height: 1.45,
                color: TalkFreeColors.mutedWhite,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ProgressTaskCard extends StatelessWidget {
  const _ProgressTaskCard({required this.adsWatched});

  final int adsWatched;

  @override
  Widget build(BuildContext context) {
    final progress = (adsWatched / kAdsRequiredForFreeUsNumber).clamp(0.0, 1.0);

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: TalkFreeColors.cardBg,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: AppColors.primary.withValues(alpha: 0.22),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.25),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.task_alt_rounded,
                color: AppColors.primary.withValues(alpha: 0.9),
                size: 22,
              ),
              const SizedBox(width: 8),
              Text(
                'Progress task',
                style: GoogleFonts.poppins(
                  fontWeight: FontWeight.w700,
                  fontSize: 15,
                  color: TalkFreeColors.offWhite,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            'Watch $kAdsRequiredForFreeUsNumber ads to get a free US number',
            style: GoogleFonts.inter(
              fontSize: 14,
              height: 1.4,
              color: TalkFreeColors.mutedWhite,
            ),
          ),
          const SizedBox(height: 16),
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 10,
              backgroundColor: Colors.white.withValues(alpha: 0.08),
              color: AppColors.primary,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            '$adsWatched / $kAdsRequiredForFreeUsNumber ads watched',
            style: GoogleFonts.jetBrainsMono(
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: TalkFreeColors.beigeGold.withValues(alpha: 0.95),
            ),
          ),
        ],
      ),
    );
  }
}

class _SubscriptionSection extends StatelessWidget {
  const _SubscriptionSection({required this.onBuy});

  final void Function(String planLabel) onBuy;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Subscription',
          style: GoogleFonts.poppins(
            fontWeight: FontWeight.w700,
            fontSize: 18,
            color: TalkFreeColors.offWhite,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          'Premium 2nd line — faster unlock & extras',
          style: GoogleFonts.inter(
            fontSize: 13,
            color: TalkFreeColors.mutedWhite,
          ),
        ),
        const SizedBox(height: 16),
        _PlanRow(
          title: 'Daily',
          subtitle: '24h access',
          price: r'$0.99',
          onBuy: () => onBuy('Daily'),
        ),
        const SizedBox(height: 12),
        _PlanRow(
          title: 'Weekly',
          subtitle: 'Best for short trips',
          price: r'$4.99',
          onBuy: () => onBuy('Weekly'),
        ),
        const SizedBox(height: 12),
        _PlanRow(
          title: 'Monthly',
          subtitle: 'Full month · best value',
          price: r'$14.99',
          highlight: true,
          onBuy: () => onBuy('Monthly'),
        ),
      ],
    );
  }
}

class _PlanRow extends StatelessWidget {
  const _PlanRow({
    required this.title,
    required this.subtitle,
    required this.price,
    required this.onBuy,
    this.highlight = false,
  });

  final String title;
  final String subtitle;
  final String price;
  final VoidCallback onBuy;
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    final border = highlight
        ? Border.all(color: AppColors.primary.withValues(alpha: 0.55), width: 1.5)
        : Border.all(color: Colors.white.withValues(alpha: 0.08));

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: highlight
            ? AppColors.primary.withValues(alpha: 0.08)
            : TalkFreeColors.cardBg,
        borderRadius: BorderRadius.circular(16),
        border: border,
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: GoogleFonts.poppins(
                    fontWeight: FontWeight.w700,
                    fontSize: 16,
                    color: TalkFreeColors.offWhite,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: GoogleFonts.inter(
                    fontSize: 12,
                    color: TalkFreeColors.mutedWhite,
                  ),
                ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                price,
                style: GoogleFonts.jetBrainsMono(
                  fontWeight: FontWeight.w700,
                  fontSize: 16,
                  color: AppColors.primary,
                ),
              ),
              const SizedBox(height: 8),
              FilledButton(
                onPressed: onBuy,
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: TalkFreeColors.onPrimary,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                child: Text(
                  'Buy Now',
                  style: GoogleFonts.montserrat(
                    fontWeight: FontWeight.w800,
                    fontSize: 12,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

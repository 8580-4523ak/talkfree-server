import 'dart:async' show Timer;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lottie/lottie.dart';

import '../config/credits_policy.dart';
import '../services/firestore_user_service.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import '../utils/us_phone_format.dart';
import '../widgets/assign_us_number_flow.dart';
import '../widgets/glass_panel.dart';
import '../widgets/lease_ring_painter.dart';
import 'number_selection_screen.dart';
import 'subscription_screen.dart';

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
///
/// Browse / claim from the list: opens [NumberSelectionScreen]; confirm + premium
/// provision live in [VirtualNumberClaimFlow].
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

/// Animated handset + copy — “My Number” screen header.
class _MyNumberHeroBanner extends StatelessWidget {
  const _MyNumberHeroBanner();

  @override
  Widget build(BuildContext context) {
    final onSurface = Theme.of(context).colorScheme.onSurface;
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    return Container(
      height: 120,
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        gradient: LinearGradient(
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
          colors: [
            AppColors.primary.withValues(alpha: 0.55),
            AppTheme.neonGreen.withValues(alpha: 0.22),
            AppColors.primary.withValues(alpha: 0.38),
          ],
        ),
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withValues(alpha: 0.22),
            blurRadius: 22,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(19),
        child: ColoredBox(
          color: AppTheme.darkBg.withValues(alpha: 0.93),
          child: Row(
            children: [
              Expanded(
                flex: 5,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(6, 4, 4, 4),
                  child: Lottie.asset(
                    AppTheme.lottiePhoneCall,
                    fit: BoxFit.contain,
                    repeat: true,
                  ),
                ),
              ),
              Expanded(
                flex: 6,
                child: Padding(
                  padding:
                      const EdgeInsets.only(right: 14, top: 10, bottom: 10),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Your second line',
                        style: GoogleFonts.inter(
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                          color: onSurface,
                          height: 1.2,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'US number · SMS, calls & inbox',
                        style: GoogleFonts.inter(
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                          height: 1.35,
                          color: muted,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _VirtualNumberScreenState extends State<VirtualNumberScreen> {
  bool _claiming = false;
  Timer? _leaseTicker;

  void _syncLeaseTicker(String? assigned, DateTime? leaseExp) {
    final has = assigned != null && assigned.trim().isNotEmpty;
    final need = has && leaseExp != null;
    if (need) {
      _leaseTicker ??= Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted) setState(() {});
      });
    } else {
      _leaseTicker?.cancel();
      _leaseTicker = null;
    }
  }

  @override
  void dispose() {
    _leaseTicker?.cancel();
    super.dispose();
  }

  Future<void> _claimUsNumber(
    BuildContext context,
    int adsWatched,
    bool isPremium,
  ) async {
    final eligible = isPremium ||
        adsWatched >= CreditsPolicy.assignNumberMinAdsWatched;
    if (!eligible || _claiming) return;
    setState(() => _claiming = true);
    try {
      await runAssignUsNumberFlow(
        context,
        autoPickFirstNumber: isPremium,
        onSuccess: (r) {
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
        },
        onError: (msg) {
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(msg, style: GoogleFonts.inter()),
                behavior: SnackBarBehavior.floating,
              ),
            );
          }
        },
      );
    } finally {
      if (mounted) setState(() => _claiming = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.darkBg,
      appBar: AppBar(
        backgroundColor: AppTheme.darkBg,
        elevation: 0,
        title: Text(
          'My Number',
          style: GoogleFonts.inter(
            fontWeight: FontWeight.w800,
            fontSize: 20,
            color: Theme.of(context).colorScheme.onSurface,
          ),
        ),
        iconTheme: IconThemeData(
          color: Theme.of(context).colorScheme.onSurface,
        ),
      ),
      body: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        stream: FirestoreUserService.watchUserDocument(widget.userUid),
        builder: (context, snap) {
          final data = snap.data?.data();
          final assigned = VirtualNumberScreen._readAssigned(data);
          final adsWatched = VirtualNumberScreen._readAdsWatched(data);
          final isPremium = FirestoreUserService.isPremiumFromUserData(data);
          final leaseExp = FirestoreUserService.numberLeaseExpiryFromUserData(data);
          final planType = FirestoreUserService.numberPlanTypeFromUserData(data);
          final canClaim = isPremium ||
              adsWatched >= CreditsPolicy.assignNumberMinAdsWatched;

          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!context.mounted) return;
            _syncLeaseTicker(assigned, leaseExp);
          });

          if (snap.hasError) {
            return Center(
              child: Text(
                'Could not load profile.\n${snap.error}',
                textAlign: TextAlign.center,
                style: GoogleFonts.inter(color: Theme.of(context).colorScheme.onSurfaceVariant),
              ),
            );
          }

          return Stack(
            children: [
              Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        AppTheme.darkBg,
                        AppColors.darkBackgroundDeep,
                      ],
                    ),
                  ),
                ),
              ),
              SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const _MyNumberHeroBanner(),
                const SizedBox(height: 14),
                if (assigned != null) ...[
                  _AssignedLineGlassCard(
                    number: assigned,
                    leaseExpiry: leaseExp,
                    planType: planType,
                  ),
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
                      style: GoogleFonts.inter(
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
                  if (!isPremium) ...[
                    const SizedBox(height: 24),
                    _ProgressTaskCard(adsWatched: adsWatched),
                  ] else
                    const SizedBox(height: 20),
                  const SizedBox(height: 20),
                  FilledButton.icon(
                    onPressed: (!canClaim || _claiming)
                        ? null
                        : () => _claimUsNumber(context, adsWatched, isPremium),
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
                          : isPremium
                              ? 'Claim your US number'
                              : 'Claim free US number',
                      style: GoogleFonts.inter(
                        fontWeight: FontWeight.w800,
                        fontSize: 15,
                      ),
                    ),
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      backgroundColor: AppColors.primary,
                      foregroundColor: Colors.white,
                      disabledBackgroundColor: const Color(0xFF2C3238),
                      disabledForegroundColor:
                          Theme.of(context).colorScheme.onSurfaceVariant.withValues(alpha: 0.45),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                  ),
                  if (!canClaim && !isPremium)
                    Padding(
                      padding: const EdgeInsets.only(top: 10),
                      child: Text(
                        'Watch ${CreditsPolicy.assignNumberMinAdsWatched} rewarded '
                        'ads (lifetime) to unlock your free US number.',
                        textAlign: TextAlign.center,
                        style: GoogleFonts.inter(
                          fontSize: 12,
                          height: 1.35,
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  if (!isPremium) ...[
                    const SizedBox(height: 28),
                    OutlinedButton.icon(
                      onPressed: () {
                        Navigator.of(context).push<void>(
                          SubscriptionScreen.createRoute(),
                        );
                      },
                      icon: SizedBox(
                        width: 26,
                        height: 26,
                        child: Lottie.asset(
                          AppTheme.lottieFlyingMoney,
                          fit: BoxFit.contain,
                          repeat: true,
                        ),
                      ),
                      label: Text(
                        'TalkFree Pro — Daily to Yearly',
                        style: GoogleFonts.inter(
                          fontWeight: FontWeight.w700,
                          fontSize: 14,
                          color: AppColors.primary,
                        ),
                      ),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        side: BorderSide(
                          color: AppColors.primary.withValues(alpha: 0.65),
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),
                  ] else
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
                    icon: SizedBox(
                      width: 22,
                      height: 22,
                      child: Lottie.asset(
                        AppTheme.lottiePhoneCall,
                        fit: BoxFit.contain,
                        repeat: true,
                      ),
                    ),
                    label: Text(
                      'Browse available numbers',
                      style: GoogleFonts.inter(
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
            ],
          );
        },
      ),
    );
  }
}

double _leaseFracVm(DateTime now, DateTime expiry, String? planType) {
  final leaseMs = CreditsPolicy.leaseDurationMsForPlanType(planType);
  final leftMs = expiry.difference(now).inMilliseconds;
  if (leftMs <= 0) return 0;
  return (leftMs / leaseMs).clamp(0.0, 1.0);
}

String _leaseCaptionVm(DateTime now, DateTime? expiry) {
  if (expiry == null) return 'No expiry set';
  final left = expiry.difference(now);
  if (left.inSeconds <= 0) return 'Expired';
  if (left.inDays >= 1) return '${left.inDays}d left';
  if (left.inHours >= 1) return '${left.inHours}h left';
  return '${left.inMinutes}m left';
}

class _AssignedLineGlassCard extends StatelessWidget {
  const _AssignedLineGlassCard({
    required this.number,
    required this.leaseExpiry,
    required this.planType,
  });

  final String number;
  final DateTime? leaseExpiry;
  final String? planType;

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final exp = leaseExpiry;
    final frac = (exp != null) ? _leaseFracVm(now, exp, planType) : 1.0;
    final arcColor = leaseRingForegroundColor(now, exp);

    return GlassPanel(
      borderRadius: AppTheme.radiusLg,
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.verified_rounded, color: AppColors.primary, size: 26),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Your 2nd line',
                  style: GoogleFonts.inter(
                    fontWeight: FontWeight.w800,
                    fontSize: 17,
                    color: Theme.of(context).colorScheme.onSurface,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Center(
            child: SizedBox(
              width: 200,
              height: 200,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  CustomPaint(
                    size: const Size(200, 200),
                    painter: LeaseRingPainter(
                      progress: frac,
                      trackColor: Colors.white.withValues(alpha: 0.12),
                      foregroundColor: arcColor,
                    ),
                  ),
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SelectableText(
                        formatUsPhoneForDisplay(number),
                        textAlign: TextAlign.center,
                        style: GoogleFonts.jetBrainsMono(
                          fontSize: 20,
                          fontWeight: FontWeight.w700,
                          color: Theme.of(context).colorScheme.onSurface,
                          letterSpacing: 0.4,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        _leaseCaptionVm(now, exp),
                        style: GoogleFonts.poppins(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: arcColor,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
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
      child: GlassPanel(
        borderRadius: 22,
        padding: const EdgeInsets.fromLTRB(22, 26, 22, 26),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 52,
                  height: 52,
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: AppColors.primary.withValues(alpha: 0.15),
                    border: Border.all(
                      color: AppColors.primary.withValues(alpha: 0.4),
                      width: 0.5,
                    ),
                  ),
                  child: Lottie.asset(
                    AppTheme.lottiePhoneCall,
                    fit: BoxFit.contain,
                    repeat: true,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Text(
                    'Unlock Your Private 2nd Line',
                    style: GoogleFonts.inter(
                      fontWeight: FontWeight.w800,
                      fontSize: 21,
                      height: 1.2,
                      color: Theme.of(context).colorScheme.onSurface,
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
                color: Theme.of(context).colorScheme.onSurfaceVariant,
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

    return GlassPanel(
      borderRadius: 18,
      padding: const EdgeInsets.all(20),
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
                style: GoogleFonts.inter(
                  fontWeight: FontWeight.w800,
                  fontSize: 15,
                  color: Theme.of(context).colorScheme.onSurface,
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
              color: Theme.of(context).colorScheme.onSurfaceVariant,
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
            style: GoogleFonts.poppins(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: AppTheme.neonGreen.withValues(alpha: 0.95),
            ),
          ),
        ],
      ),
    );
  }
}


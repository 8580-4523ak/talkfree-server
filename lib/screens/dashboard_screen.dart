import 'dart:async';
import 'dart:math' show max;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../auth_service.dart';
import '../config/credits_policy.dart';
import '../theme/app_colors.dart';
import '../theme/talkfree_colors.dart';
import '../services/ad_service.dart';
import '../services/firestore_user_service.dart';
import '../services/grant_reward_service.dart';
import 'call_history_screen.dart';
import 'dialer_screen.dart';
import 'number_selection_screen.dart';
import 'sms_test_screen.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({
    super.key,
    required this.user,
    this.initialNavIndex = 0,
  }) : assert(
          initialNavIndex >= 0 && initialNavIndex < 2,
          'initialNavIndex must be 0 (home) or 1 (dialer)',
        );

  final User user;

  /// `0` = home, `1` = dialer (e.g. after value intro).
  final int initialNavIndex;

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  bool _rewardedAdBusy = false;
  late int _navIndex;

  /// Client-side cooldown after a rewarded ad finishes (sync with [CreditsPolicy.adRewardCooldownSeconds]).
  Timer? _localAdCooldownTimer;
  int _localAdCooldownSeconds = 0;

  @override
  void initState() {
    super.initState();
    _navIndex = widget.initialNavIndex;
  }

  @override
  void dispose() {
    _localAdCooldownTimer?.cancel();
    super.dispose();
  }

  /// Fires when the user earned reward — before `/grant-reward` — so the button locks immediately.
  void _startPostAdCooldown() {
    _localAdCooldownTimer?.cancel();
    setState(() => _localAdCooldownSeconds = CreditsPolicy.adRewardCooldownSeconds);
    _localAdCooldownTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() {
        _localAdCooldownSeconds -= 1;
        if (_localAdCooldownSeconds <= 0) {
          _localAdCooldownSeconds = 0;
          _localAdCooldownTimer?.cancel();
          _localAdCooldownTimer = null;
        }
      });
    });
  }

  int _effectiveCooldown(int firestoreCooldown) =>
      max(firestoreCooldown, _localAdCooldownSeconds);

  Future<void> _onWatchRewardedAd(
    int cooldownRemaining,
    bool dailyLimitReached,
  ) async {
    if (_rewardedAdBusy) return;
    if (dailyLimitReached) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Limit Reached')),
      );
      return;
    }
    if (cooldownRemaining > 0) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Please wait $cooldownRemaining seconds',
          ),
        ),
      );
      return;
    }
    setState(() => _rewardedAdBusy = true);
    try {
      final earned = await AdService.instance.loadAndShowRewardedAd();
      if (!mounted) return;
      if (earned) {
        _startPostAdCooldown();
        try {
          final result = await GrantRewardService.instance.requestMinuteGrant();
          if (!mounted) return;
          if (result.creditsAdded > 0) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  'Great! +${result.creditsAdded} credits added.',
                ),
              ),
            );
          } else {
            final more = CreditsPolicy.adsRequiredForMinuteGrant - result.adSubCounter;
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  'Ad ${result.adSubCounter}/${CreditsPolicy.adsRequiredForMinuteGrant} logged. '
                  '$more more for +${CreditsPolicy.creditsPerMinuteGrant} credits!',
                ),
              ),
            );
          }
        } on GrantRewardException catch (e) {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(e.message)),
          );
        } catch (e) {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Could not sync reward. Pull to refresh or try again. ($e)',
              ),
            ),
          );
        }
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('No credits — finish watching the ad to earn rewards.'),
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Ad error: $e')),
      );
    } finally {
      if (mounted) setState(() => _rewardedAdBusy = false);
    }
  }

  Future<void> _debugAddCredits() async {
    if (!kDebugMode) return;
    try {
      await FirestoreUserService.addPaidCredits(widget.user.uid, 100);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('[Debug] +100 credits added.')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('[Debug] Failed: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final name = widget.user.displayName?.trim();
    final displayName =
        name != null && name.isNotEmpty ? name : 'TalkFree user';

    return StreamBuilder<
        ({
          int adsToday,
          int cooldownRemaining,
          int cycleProgress,
          bool dailyLimitReached,
        })>(
      stream: FirestoreUserService.watchAdRewardStatus(widget.user.uid),
      builder: (context, coolSnap) {
        final ad = coolSnap.data;
        final firestoreCooldown = ad?.cooldownRemaining ?? 0;
        final cooldownRemaining = _effectiveCooldown(firestoreCooldown);
        final adsToday = ad?.adsToday ?? 0;
        final cycleProgress = ad?.cycleProgress ?? 0;
        final dailyLimitReached = ad?.dailyLimitReached ?? false;

        // One body subtree at a time — no IndexedStack (avoids touch bugs on some
        // OEM builds where an invisible sibling still wins hit testing).
        final Widget tabBody = _navIndex == 0
            ? _DashboardHomeTab(
                user: widget.user,
                displayName: displayName,
                theme: theme,
                rewardedAdBusy: _rewardedAdBusy,
                cooldownRemaining: cooldownRemaining,
                adsToday: adsToday,
                cycleProgress: cycleProgress,
                dailyLimitReached: dailyLimitReached,
                onWatchRewardedAd: () => _onWatchRewardedAd(
                  cooldownRemaining,
                  dailyLimitReached,
                ),
                onGoToDialer: () => setState(() => _navIndex = 1),
              )
            : DialerScreen(
                key: const ValueKey<Object>('talkfree_dialer'),
                user: widget.user,
                onEarnMinutes: () => _onWatchRewardedAd(
                  cooldownRemaining,
                  dailyLimitReached,
                ),
                rewardedAdBusy: _rewardedAdBusy,
                cooldownRemaining: cooldownRemaining,
                rewardCycleProgress: cycleProgress,
                rewardDailyLimitReached: dailyLimitReached,
              );

        return Scaffold(
      // Opaque material layer — avoids “ghost” hit targets on some GPUs.
      backgroundColor: theme.colorScheme.surface,
      appBar: AppBar(
        title: Text(_navIndex == 0 ? 'Dashboard' : 'Dialer'),
        actions: [
          IconButton(
            tooltip: 'Call history',
            icon: const Icon(Icons.history_rounded),
            onPressed: () {
              Navigator.of(context).push<void>(
                MaterialPageRoute<void>(
                  builder: (_) => CallHistoryScreen(user: widget.user),
                ),
              );
            },
          ),
          IconButton(
            tooltip: 'Chat',
            icon: const Icon(Icons.chat_bubble_outline_rounded),
            onPressed: () {
              Navigator.of(context).push<void>(
                MaterialPageRoute<void>(
                  builder: (_) => const SmsTestScreen(),
                ),
              );
            },
          ),
          IconButton(
            tooltip: 'Settings',
            icon: const Icon(Icons.settings_outlined),
            onPressed: () {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Settings — coming soon.')),
              );
            },
          ),
          IconButton(
            tooltip: 'Sign out',
            icon: const Icon(Icons.logout_outlined),
            onPressed: () => AuthService().signOut(),
          ),
        ],
      ),
          floatingActionButton: _navIndex == 0
              ? Padding(
                  padding: const EdgeInsets.only(bottom: 20),
                  child: _EarnCreditsFloatingAction(
                    busy: _rewardedAdBusy,
                    cooldownRemaining: cooldownRemaining,
                    cycleProgress: cycleProgress,
                    dailyLimitReached: dailyLimitReached,
                    onPressed: () => _onWatchRewardedAd(
                      cooldownRemaining,
                      dailyLimitReached,
                    ),
                    onDebugLongPress: kDebugMode ? _debugAddCredits : null,
                  ),
                )
              : null,
          body: Material(
            color: theme.colorScheme.surface,
            child: tabBody,
          ),
          bottomNavigationBar: BottomNavigationBar(
            currentIndex: _navIndex,
            onTap: (i) => setState(() => _navIndex = i),
            type: BottomNavigationBarType.fixed,
            items: const [
              BottomNavigationBarItem(
                icon: Icon(Icons.home_outlined),
                activeIcon: Icon(Icons.home_rounded),
                label: 'Home',
              ),
              BottomNavigationBarItem(
                icon: Icon(Icons.dialpad_outlined),
                activeIcon: Icon(Icons.dialpad_rounded),
                label: 'Dialer',
              ),
            ],
          ),
        );
      },
    );
  }
}

class _DashboardHomeTab extends StatefulWidget {
  const _DashboardHomeTab({
    required this.user,
    required this.displayName,
    required this.theme,
    required this.rewardedAdBusy,
    required this.cooldownRemaining,
    required this.adsToday,
    required this.cycleProgress,
    required this.dailyLimitReached,
    required this.onWatchRewardedAd,
    required this.onGoToDialer,
  });

  final User user;
  final String displayName;
  final ThemeData theme;
  final bool rewardedAdBusy;
  final int cooldownRemaining;
  final int adsToday;
  final int cycleProgress;
  final bool dailyLimitReached;
  final Future<void> Function() onWatchRewardedAd;
  final VoidCallback onGoToDialer;

  @override
  State<_DashboardHomeTab> createState() => _DashboardHomeTabState();
}

class _DashboardHomeTabState extends State<_DashboardHomeTab> {
  late Future<void> _ensureFuture;

  @override
  void initState() {
    super.initState();
    _ensureFuture =
        FirestoreUserService.ensureUserDocument(widget.user.uid);
  }

  void _retry() {
    setState(() {
      _ensureFuture =
          FirestoreUserService.ensureUserDocument(widget.user.uid);
    });
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<void>(
      future: _ensureFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.cloud_off_rounded,
                    size: 48,
                    color: widget.theme.colorScheme.error,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Could not load your profile.',
                    style: widget.theme.textTheme.titleMedium,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '${snapshot.error}',
                    style: widget.theme.textTheme.bodySmall?.copyWith(
                      color: widget.theme.colorScheme.onSurfaceVariant,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 24),
                  FilledButton(
                    onPressed: _retry,
                    child: const Text('Retry'),
                  ),
                ],
              ),
            ),
          );
        }

        return ListView(
          padding: EdgeInsets.fromLTRB(
            20,
            12,
            20,
            kDebugMode ? 108 : 32,
          ),
          children: [
            Row(
              children: [
                if (widget.user.photoURL != null)
                  CircleAvatar(
                    radius: 24,
                    backgroundImage: NetworkImage(widget.user.photoURL!),
                  )
                else
                  CircleAvatar(
                    radius: 24,
                    backgroundColor: TalkFreeColors.cardBg,
                    foregroundColor: TalkFreeColors.beigeGold,
                    child: Text(
                      widget.displayName.isNotEmpty
                          ? widget.displayName[0].toUpperCase()
                          : '?',
                      style: GoogleFonts.montserrat(fontWeight: FontWeight.w700),
                    ),
                  ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.displayName,
                        style: GoogleFonts.montserrat(
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                          color: TalkFreeColors.beigeGold,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (widget.user.email != null &&
                          widget.user.email!.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(
                          widget.user.email!,
                          style: GoogleFonts.montserrat(
                            fontSize: 13,
                            color: TalkFreeColors.mutedWhite,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 28),
            _WalletCard(uid: widget.user.uid),
            const SizedBox(height: 20),
            _WatchAdCtaButton(
              busy: widget.rewardedAdBusy,
              cooldownRemaining: widget.cooldownRemaining,
              cycleProgress: widget.cycleProgress,
              dailyLimitReached: widget.dailyLimitReached,
              onPressed: () {
                widget.onWatchRewardedAd();
              },
            ),
            const SizedBox(height: 10),
            Text(
              'Watch ${CreditsPolicy.adsRequiredForMinuteGrant} ads = 1 minute (${CreditsPolicy.creditsPerMinuteGrant} credits)',
              textAlign: TextAlign.center,
              style: GoogleFonts.montserrat(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                height: 1.35,
                color: TalkFreeColors.offWhite,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              '${widget.adsToday} / ${CreditsPolicy.maxRewardedAdsPerDay} ads this period',
              textAlign: TextAlign.center,
              style: GoogleFonts.montserrat(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                height: 1.35,
                color: widget.theme.colorScheme.onSurfaceVariant,
              ),
            ),
            if (widget.cooldownRemaining > 0) ...[
              const SizedBox(height: 6),
              Text(
                'Next ad in ${widget.cooldownRemaining}s',
                textAlign: TextAlign.center,
                style: GoogleFonts.montserrat(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  height: 1.35,
                  color: TalkFreeColors.beigeGold,
                ),
              ),
            ],
            const SizedBox(height: 28),
            StreamBuilder<int>(
              stream: FirestoreUserService.watchCredits(widget.user.uid),
              builder: (context, snap) {
                final credits = snap.data ?? 0;
                final estMinutes =
                    (credits / CreditsPolicy.creditsPerMinute).toStringAsFixed(1);
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: _DashboardStatCard(
                        icon: Icons.call_made_rounded,
                        label: 'Calls made',
                        value: '0',
                        caption: 'All time',
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: _DashboardStatCard(
                        icon: Icons.timer_outlined,
                        label: 'Minutes',
                        value: estMinutes,
                        caption: 'Est. from balance',
                      ),
                    ),
                  ],
                );
              },
            ),
            const SizedBox(height: 28),
            _RecentActivitySection(
              onOpenDialer: widget.onGoToDialer,
            ),
            const SizedBox(height: 32),
            StreamBuilder<int>(
              stream: FirestoreUserService.watchCredits(widget.user.uid),
              builder: (context, creditSnap) {
                final credits = creditSnap.data ?? 0;
                return FilledButton.icon(
                  onPressed: () {
                    Navigator.of(context).pushNamed(
                      NumberSelectionScreen.routeName,
                      arguments: NumberSelectionRouteArgs(
                        userUid: widget.user.uid,
                        userCredits: credits,
                      ),
                    );
                  },
                  icon: const Icon(
                    Icons.phone_android_rounded,
                    color: Colors.white,
                  ),
                  label: Text(
                    'Get Your Number',
                    style: GoogleFonts.montserrat(
                      fontWeight: FontWeight.w700,
                      color: TalkFreeColors.onPrimary,
                    ),
                  ),
                  style: FilledButton.styleFrom(
                    backgroundColor: TalkFreeColors.beigeGold,
                    foregroundColor: TalkFreeColors.onPrimary,
                    minimumSize: const Size.fromHeight(54),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                );
              },
            ),
            const SizedBox(height: 8),
          ],
        );
      },
    );
  }
}

class _DashboardStatCard extends StatelessWidget {
  const _DashboardStatCard({
    required this.icon,
    required this.label,
    required this.value,
    required this.caption,
  });

  final IconData icon;
  final String label;
  final String value;
  final String caption;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 16),
      decoration: BoxDecoration(
        color: TalkFreeColors.cardBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: AppColors.primary.withValues(alpha: 0.28),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.2),
            blurRadius: 10,
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
                icon,
                size: 18,
                color: AppColors.primary.withValues(alpha: 0.9),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  label,
                  style: GoogleFonts.montserrat(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: TalkFreeColors.mutedWhite,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            value,
            style: GoogleFonts.montserrat(
              fontSize: 26,
              fontWeight: FontWeight.w800,
              height: 1.05,
              color: TalkFreeColors.offWhite,
              letterSpacing: -0.5,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            caption,
            style: GoogleFonts.montserrat(
              fontSize: 11,
              fontWeight: FontWeight.w500,
              color: TalkFreeColors.mutedWhite.withValues(alpha: 0.85),
            ),
          ),
        ],
      ),
    );
  }
}

class _RecentActivitySection extends StatelessWidget {
  const _RecentActivitySection({required this.onOpenDialer});

  final VoidCallback onOpenDialer;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Recent activity',
              style: GoogleFonts.montserrat(
                fontSize: 17,
                fontWeight: FontWeight.w700,
                color: TalkFreeColors.offWhite,
              ),
            ),
            TextButton(
              onPressed: () {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Full history — coming soon.'),
                  ),
                );
              },
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: Text(
                'See all',
                style: GoogleFonts.montserrat(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: AppColors.primary,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
          decoration: BoxDecoration(
            color: TalkFreeColors.cardBg,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: AppColors.primary.withValues(alpha: 0.2),
            ),
          ),
          child: Column(
            children: [
              Icon(
                Icons.history_rounded,
                size: 40,
                color: TalkFreeColors.mutedWhite.withValues(alpha: 0.45),
              ),
              const SizedBox(height: 14),
              Text(
                'No calls yet',
                textAlign: TextAlign.center,
                style: GoogleFonts.montserrat(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: TalkFreeColors.offWhite,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Your outgoing calls will show up here. Start from the dialer.',
                textAlign: TextAlign.center,
                style: GoogleFonts.montserrat(
                  fontSize: 13,
                  height: 1.4,
                  color: TalkFreeColors.mutedWhite,
                ),
              ),
              const SizedBox(height: 18),
              OutlinedButton.icon(
                onPressed: onOpenDialer,
                icon: Icon(
                  Icons.dialpad_rounded,
                  size: 20,
                  color: AppColors.primary,
                ),
                label: Text(
                  'Open dialer',
                  style: GoogleFonts.montserrat(
                    fontWeight: FontWeight.w700,
                    color: AppColors.primary,
                  ),
                ),
                style: OutlinedButton.styleFrom(
                  side: BorderSide(
                    color: AppColors.primary.withValues(alpha: 0.65),
                  ),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 12,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 4),
        Padding(
          padding: const EdgeInsets.only(left: 4, top: 6),
          child: Text(
            'Preview: call history syncs when available.',
            style: GoogleFonts.montserrat(
              fontSize: 11,
              color: TalkFreeColors.mutedWhite.withValues(alpha: 0.65),
            ),
          ),
        ),
      ],
    );
  }
}

class _AnimatedWalletIcon extends StatefulWidget {
  const _AnimatedWalletIcon();

  @override
  State<_AnimatedWalletIcon> createState() => _AnimatedWalletIconState();
}

class _AnimatedWalletIconState extends State<_AnimatedWalletIcon>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2200),
  )..repeat(reverse: true);

  late final Animation<double> _scale = Tween<double>(begin: 1.0, end: 1.09)
      .animate(CurvedAnimation(parent: _c, curve: Curves.easeInOutCubic));

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ScaleTransition(
      scale: _scale,
      child: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: AppColors.primary.withValues(alpha: 0.12),
          border: Border.all(
            color: AppColors.primary.withValues(alpha: 0.35),
          ),
        ),
        child: Icon(
          Icons.account_balance_wallet_outlined,
          color: AppColors.primary.withValues(alpha: 0.95),
          size: 20,
        ),
      ),
    );
  }
}

const LinearGradient _earnCreditsCtaGradient = LinearGradient(
  begin: Alignment.topLeft,
  end: Alignment.bottomRight,
  colors: [
    Color(0xFF00F5B8),
    AppColors.primary,
    Color(0xFF00B875),
    Color(0xFF00995C),
  ],
  stops: [0.0, 0.35, 0.72, 1.0],
);

BoxDecoration _earnCreditsCtaOuterShadow(BorderRadiusGeometry r) {
  return BoxDecoration(
    borderRadius: r,
    boxShadow: [
      BoxShadow(
        color: AppColors.primary.withValues(alpha: 0.5),
        blurRadius: 24,
        spreadRadius: 0,
        offset: const Offset(0, 10),
      ),
      BoxShadow(
        color: AppColors.primary.withValues(alpha: 0.22),
        blurRadius: 40,
        spreadRadius: 4,
        offset: Offset.zero,
      ),
      BoxShadow(
        color: Colors.black.withValues(alpha: 0.32),
        blurRadius: 14,
        offset: const Offset(0, 6),
      ),
    ],
  );
}

BoxDecoration _earnCreditsFabOuterShadow(BorderRadiusGeometry r) {
  return BoxDecoration(
    borderRadius: r,
    boxShadow: [
      BoxShadow(
        color: Colors.black.withValues(alpha: 0.42),
        blurRadius: 22,
        spreadRadius: 0,
        offset: const Offset(0, 10),
      ),
      BoxShadow(
        color: Colors.black.withValues(alpha: 0.2),
        blurRadius: 36,
        spreadRadius: 2,
        offset: const Offset(0, 14),
      ),
      BoxShadow(
        color: AppColors.primary.withValues(alpha: 0.48),
        blurRadius: 26,
        spreadRadius: 0,
        offset: const Offset(0, 10),
      ),
      BoxShadow(
        color: AppColors.primary.withValues(alpha: 0.2),
        blurRadius: 44,
        spreadRadius: 4,
        offset: Offset.zero,
      ),
      BoxShadow(
        color: Colors.black.withValues(alpha: 0.28),
        blurRadius: 12,
        offset: const Offset(0, 6),
      ),
    ],
  );
}

BoxDecoration _earnCreditsInnerGradient(BorderRadiusGeometry r) {
  return BoxDecoration(
    borderRadius: r,
    gradient: _earnCreditsCtaGradient,
  );
}

class _EarnCreditsFloatingAction extends StatelessWidget {
  const _EarnCreditsFloatingAction({
    required this.busy,
    required this.cooldownRemaining,
    required this.cycleProgress,
    required this.dailyLimitReached,
    required this.onPressed,
    this.onDebugLongPress,
  });

  final bool busy;
  final int cooldownRemaining;
  final int cycleProgress;
  final bool dailyLimitReached;
  final VoidCallback onPressed;
  final Future<void> Function()? onDebugLongPress;

  static const double _radius = 30;

  @override
  Widget build(BuildContext context) {
    final borderRadius = BorderRadius.circular(_radius);
    final p = cycleProgress.clamp(0, CreditsPolicy.adsRequiredForMinuteGrant);
    return Material(
      color: Colors.transparent,
      elevation: 0,
      shadowColor: Colors.transparent,
      child: InkWell(
        onTap: (busy || dailyLimitReached || cooldownRemaining > 0) ? null : onPressed,
        onLongPress: (onDebugLongPress != null && !busy)
            ? () {
                onDebugLongPress!();
              }
            : null,
        borderRadius: borderRadius,
        splashColor: Colors.white.withValues(alpha: 0.22),
        highlightColor: Colors.white.withValues(alpha: 0.1),
        child: Container(
          decoration: _earnCreditsFabOuterShadow(borderRadius),
          child: ClipRRect(
            borderRadius: borderRadius,
            child: Ink(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
              decoration: _earnCreditsInnerGradient(borderRadius),
              child: busy
                  ? Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.5,
                            color: Colors.white.withValues(alpha: 0.95),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Text(
                          'Loading…',
                          style: GoogleFonts.montserrat(
                            fontSize: 15,
                            fontWeight: FontWeight.w800,
                            color: Colors.white,
                          ),
                        ),
                      ],
                    )
                  : dailyLimitReached
                      ? Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.block_rounded,
                              color: Colors.white.withValues(alpha: 0.8),
                              size: 22,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              'Limit Reached',
                              style: GoogleFonts.montserrat(
                                fontSize: 13,
                                fontWeight: FontWeight.w800,
                                color: Colors.white.withValues(alpha: 0.9),
                              ),
                            ),
                          ],
                        )
                  : cooldownRemaining > 0
                      ? Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.timer_outlined,
                                  color: Colors.white.withValues(alpha: 0.85),
                                  size: 26,
                                ),
                                const SizedBox(width: 10),
                                Text(
                                  'Next ad in ${cooldownRemaining}s',
                                  style: GoogleFonts.montserrat(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w800,
                                    letterSpacing: 0.12,
                                    color: Colors.white.withValues(alpha: 0.92),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 6),
                            Text(
                              'Ad $p/${CreditsPolicy.adsRequiredForMinuteGrant} watched',
                              style: GoogleFonts.montserrat(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: Colors.white.withValues(alpha: 0.75),
                              ),
                            ),
                          ],
                        )
                      : Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.play_circle_filled_rounded,
                                  color: Colors.white.withValues(alpha: 0.98),
                                  size: 28,
                                  shadows: [
                                    Shadow(
                                      color: Colors.black.withValues(alpha: 0.25),
                                      blurRadius: 5,
                                      offset: const Offset(0, 2),
                                    ),
                                  ],
                                ),
                                const SizedBox(width: 10),
                                Text(
                                  'Earn Credits 🎁',
                                  style: GoogleFonts.montserrat(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w800,
                                    letterSpacing: 0.12,
                                    color: Colors.white,
                                    shadows: [
                                      Shadow(
                                        color: Colors.black.withValues(alpha: 0.28),
                                        blurRadius: 7,
                                        offset: const Offset(0, 2),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 6),
                            SizedBox(
                              width: 200,
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(3),
                                child: LinearProgressIndicator(
                                  value: p /
                                      CreditsPolicy.adsRequiredForMinuteGrant,
                                  minHeight: 4,
                                  backgroundColor:
                                      Colors.white.withValues(alpha: 0.2),
                                  color: Colors.white.withValues(alpha: 0.9),
                                ),
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Ad $p/${CreditsPolicy.adsRequiredForMinuteGrant} watched',
                              textAlign: TextAlign.center,
                              style: GoogleFonts.montserrat(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: Colors.white.withValues(alpha: 0.8),
                              ),
                            ),
                          ],
                        ),
            ),
          ),
        ),
      ),
    );
  }
}

class _WatchAdCtaButton extends StatefulWidget {
  const _WatchAdCtaButton({
    required this.busy,
    required this.cooldownRemaining,
    required this.cycleProgress,
    required this.dailyLimitReached,
    required this.onPressed,
  });

  final bool busy;
  final int cooldownRemaining;
  final int cycleProgress;
  final bool dailyLimitReached;
  final VoidCallback onPressed;

  @override
  State<_WatchAdCtaButton> createState() => _WatchAdCtaButtonState();
}

class _WatchAdCtaButtonState extends State<_WatchAdCtaButton>
    with TickerProviderStateMixin {
  static const double _radius = 30;

  late final AnimationController _pulseCtrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2400),
  );
  late final Animation<double> _pulseScale = Tween<double>(begin: 1.0, end: 1.022)
      .animate(CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOutCubic));

  late final AnimationController _iconCtrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 720),
  );
  late final Animation<double> _iconScale = Tween<double>(begin: 1.0, end: 1.14)
      .animate(CurvedAnimation(parent: _iconCtrl, curve: Curves.easeInOutCubic));

  bool get _idle =>
      !widget.busy &&
      widget.cooldownRemaining <= 0 &&
      !widget.dailyLimitReached;

  @override
  void initState() {
    super.initState();
    if (_idle) {
      _pulseCtrl.repeat(reverse: true);
      _iconCtrl.repeat(reverse: true);
    }
  }

  @override
  void didUpdateWidget(covariant _WatchAdCtaButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.busy != oldWidget.busy ||
        widget.cooldownRemaining != oldWidget.cooldownRemaining ||
        widget.dailyLimitReached != oldWidget.dailyLimitReached) {
      if (_idle) {
        _pulseCtrl.repeat(reverse: true);
        _iconCtrl.repeat(reverse: true);
      } else {
        _pulseCtrl.stop();
        _iconCtrl.stop();
        _pulseCtrl.value = 0;
        _iconCtrl.value = 0;
      }
    }
  }

  @override
  void dispose() {
    _pulseCtrl.dispose();
    _iconCtrl.dispose();
    super.dispose();
  }

  static const List<Shadow> _ctaTextShadows = [
    Shadow(
      color: Color(0x8C000000),
      blurRadius: 14,
      offset: Offset(0, 2),
    ),
    Shadow(
      color: Color(0x66000000),
      blurRadius: 5,
      offset: Offset(0, 1),
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final br = BorderRadius.circular(_radius);
    final progress = widget.cycleProgress.clamp(
          0,
          CreditsPolicy.adsRequiredForMinuteGrant,
        ) /
        CreditsPolicy.adsRequiredForMinuteGrant;
    return Material(
      color: Colors.transparent,
      elevation: 0,
      shadowColor: Colors.transparent,
      child: InkWell(
        onTap: (widget.busy ||
                widget.dailyLimitReached ||
                widget.cooldownRemaining > 0)
            ? null
            : widget.onPressed,
        borderRadius: br,
        splashColor: Colors.white.withValues(alpha: 0.22),
        highlightColor: Colors.white.withValues(alpha: 0.1),
        child: AnimatedBuilder(
          animation: Listenable.merge([_pulseCtrl, _iconCtrl]),
          builder: (context, child) {
            final pulse = _idle ? _pulseScale.value : 1.0;
            return Transform.scale(
              scale: pulse,
              alignment: Alignment.center,
              child: child,
            );
          },
          child: Container(
            width: double.infinity,
            decoration: _earnCreditsCtaOuterShadow(br),
            child: ClipRRect(
              borderRadius: br,
              child: Ink(
                width: double.infinity,
                padding:
                    const EdgeInsets.symmetric(horizontal: 22, vertical: 20),
                decoration: _earnCreditsInnerGradient(br),
                child: widget.busy
                    ? Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          SizedBox(
                            width: 26,
                            height: 26,
                            child: CircularProgressIndicator(
                              strokeWidth: 2.8,
                              color: Colors.white.withValues(alpha: 0.95),
                            ),
                          ),
                          const SizedBox(width: 14),
                          Text(
                            'Loading ad…',
                            style: GoogleFonts.montserrat(
                              fontSize: 16,
                              fontWeight: FontWeight.w800,
                              color: Colors.white,
                              shadows: _ctaTextShadows,
                            ),
                          ),
                        ],
                      )
                    : widget.dailyLimitReached
                        ? Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.block_rounded,
                                color: Colors.white.withValues(alpha: 0.75),
                                size: 28,
                              ),
                              const SizedBox(width: 10),
                              Flexible(
                                child: Text(
                                  'Limit Reached',
                                  textAlign: TextAlign.center,
                                  style: GoogleFonts.montserrat(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w800,
                                    color: Colors.white.withValues(alpha: 0.85),
                                  ),
                                ),
                              ),
                            ],
                          )
                    : widget.cooldownRemaining > 0
                        ? Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.timer_outlined,
                                color: Colors.white.withValues(alpha: 0.9),
                                size: 30,
                              ),
                              const SizedBox(width: 12),
                              Flexible(
                                child: Text(
                                  'Next ad in ${widget.cooldownRemaining}s',
                                  textAlign: TextAlign.center,
                                  maxLines: 2,
                                  style: GoogleFonts.montserrat(
                                    fontSize: 17,
                                    fontWeight: FontWeight.w900,
                                    height: 1.25,
                                    letterSpacing: 0.2,
                                    color: Colors.white,
                                    shadows: _ctaTextShadows,
                                  ),
                                ),
                              ),
                            ],
                          )
                        : Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              ClipRRect(
                                borderRadius: BorderRadius.circular(4),
                                child: LinearProgressIndicator(
                                  value: progress,
                                  minHeight: 5,
                                  backgroundColor:
                                      Colors.white.withValues(alpha: 0.2),
                                  color: Colors.white.withValues(alpha: 0.92),
                                ),
                              ),
                              const SizedBox(height: 12),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  ScaleTransition(
                                    scale: _iconScale,
                                    child: Icon(
                                      Icons.play_circle_filled_rounded,
                                      color: Colors.white,
                                      size: 32,
                                      shadows: const [
                                        Shadow(
                                          color: Color(0x73000000),
                                          blurRadius: 8,
                                          offset: Offset(0, 2),
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Flexible(
                                    child: Text(
                                      'Watch Ad → Get Free Credits 🎁',
                                      textAlign: TextAlign.center,
                                      maxLines: 2,
                                      style: GoogleFonts.montserrat(
                                        fontSize: 17,
                                        fontWeight: FontWeight.w900,
                                        height: 1.25,
                                        letterSpacing: 0.2,
                                        color: Colors.white,
                                        shadows: _ctaTextShadows,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              Text(
                                'Ad ${widget.cycleProgress}/${CreditsPolicy.adsRequiredForMinuteGrant} watched. ${CreditsPolicy.adsRequiredForMinuteGrant - widget.cycleProgress} more for 1 min!',
                                textAlign: TextAlign.center,
                                maxLines: 2,
                                style: GoogleFonts.montserrat(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  height: 1.3,
                                  color: Colors.white.withValues(alpha: 0.88),
                                ),
                              ),
                            ],
                          ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _WalletCard extends StatelessWidget {
  const _WalletCard({required this.uid});

  final String uid;

  static const double _outerR = 18;
  static const double _innerR = 16.5;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: FirestoreUserService.watchUserDocument(uid),
      builder: (context, snapshot) {
        final credits = snapshot.hasData
            ? FirestoreUserService.usableCreditsFromSnapshot(snapshot.data!)
            : 0;

        return Container(
          width: double.infinity,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(_outerR),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                AppColors.primary.withValues(alpha: 0.55),
                AppColors.primary.withValues(alpha: 0.35),
                const Color(0xFF00A86B).withValues(alpha: 0.45),
              ],
              stops: const [0.0, 0.55, 1.0],
            ),
            boxShadow: [
              BoxShadow(
                color: AppColors.primary.withValues(alpha: 0.2),
                blurRadius: 18,
                offset: const Offset(0, 8),
              ),
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.35),
                blurRadius: 14,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          padding: const EdgeInsets.all(1.5),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(_innerR),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 22),
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    Color(0xFF0F172A),
                    Color(0xFF1E293B),
                    Color(0xFF0C1222),
                  ],
                  stops: [0.0, 0.5, 1.0],
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const _AnimatedWalletIcon(),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'WALLET',
                          style: GoogleFonts.montserrat(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 2,
                            color: TalkFreeColors.mutedWhite,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  Text(
                    'Current balance',
                    style: GoogleFonts.montserrat(
                      fontSize: 11,
                      fontWeight: FontWeight.w500,
                      letterSpacing: 0.6,
                      color: TalkFreeColors.mutedWhite.withValues(alpha: 0.88),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '$credits',
                    style: GoogleFonts.montserrat(
                      fontSize: 46,
                      height: 1.02,
                      fontWeight: FontWeight.w800,
                      color: AppColors.textOnDark,
                      letterSpacing: -1,
                      shadows: [
                        Shadow(
                          color: AppColors.primary.withValues(alpha: 0.25),
                          blurRadius: 12,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'credits available',
                    style: GoogleFonts.montserrat(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: AppColors.primary.withValues(alpha: 0.88),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

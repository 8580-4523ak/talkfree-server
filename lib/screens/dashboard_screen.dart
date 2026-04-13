import 'dart:async' show StreamSubscription, Timer, unawaited;
import 'dart:math' show max, min, pi;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show immutable, kDebugMode;
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../auth_service.dart';
import '../config/credits_policy.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import '../theme/talkfree_colors.dart';
import '../services/ad_service.dart';
import '../utils/us_phone_format.dart';
import '../widgets/assign_us_number_flow.dart';
import '../widgets/glass_panel.dart';
import '../widgets/lease_ring_painter.dart';
import '../services/firestore_user_service.dart';
import '../services/grant_reward_service.dart';
import 'call_history_screen.dart';
import 'dialer_screen.dart';
import 'inbox_screen.dart';
import 'sms_test_screen.dart';
import 'subscription_screen.dart';

/// Immutable rewarded-ad row for ValueNotifier (equality avoids redundant notifies).
@immutable
class _AdRewardView {
  const _AdRewardView({
    required this.adsToday,
    required this.cycleProgress,
    required this.cooldownRemaining,
    required this.dailyLimitReached,
  });

  final int adsToday;
  final int cycleProgress;
  final int cooldownRemaining;
  final bool dailyLimitReached;

  _AdRewardView copyWith({
    int? adsToday,
    int? cycleProgress,
    int? cooldownRemaining,
    bool? dailyLimitReached,
  }) {
    return _AdRewardView(
      adsToday: adsToday ?? this.adsToday,
      cycleProgress: cycleProgress ?? this.cycleProgress,
      cooldownRemaining: cooldownRemaining ?? this.cooldownRemaining,
      dailyLimitReached: dailyLimitReached ?? this.dailyLimitReached,
    );
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is _AdRewardView &&
            other.adsToday == adsToday &&
            other.cycleProgress == cycleProgress &&
            other.cooldownRemaining == cooldownRemaining &&
            other.dailyLimitReached == dailyLimitReached;
  }

  @override
  int get hashCode => Object.hash(adsToday, cycleProgress, cooldownRemaining, dailyLimitReached);
}

/// Smooth numeric change for wallet / stats (no logic — display only).
class _AnimatedIntText extends StatefulWidget {
  const _AnimatedIntText({
    required this.value,
    required this.style,
  });

  final int value;
  final TextStyle style;

  @override
  State<_AnimatedIntText> createState() => _AnimatedIntTextState();
}

class _AnimatedIntTextState extends State<_AnimatedIntText> {
  late int _from;

  @override
  void initState() {
    super.initState();
    _from = widget.value;
  }

  @override
  void didUpdateWidget(covariant _AnimatedIntText oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.value != widget.value) {
      _from = oldWidget.value;
    }
  }

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<int>(
      tween: IntTween(begin: _from, end: widget.value),
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOutCubic,
      builder: (context, v, _) {
        return Text(
          '$v',
          style: widget.style,
        );
      },
    );
  }
}

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({
    super.key,
    required this.user,
    this.initialNavIndex = 0,
  }) : assert(
          initialNavIndex >= 0 && initialNavIndex < 3,
          'initialNavIndex must be 0 (home), 1 (dialer), or 2 (inbox)',
        );

  final User user;

  /// `0` = home, `1` = dialer, `2` = inbox (OTP/SMS).
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

  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _userDocSub;
  Timer? _cooldownWallClock;
  DocumentSnapshot<Map<String, dynamic>>? _latestUserDoc;

  /// Avoid spamming SnackBars if the user document stream errors repeatedly.
  bool _userDocStreamErrorNotified = false;

  final ValueNotifier<int> _credits = ValueNotifier<int>(0);
  final ValueNotifier<String?> _assignedNumber = ValueNotifier<String?>(null);
  final ValueNotifier<int> _lifetimeAdsWatched = ValueNotifier<int>(0);
  /// `'free'` | `'pro'` from Firestore ([FirestoreUserService.subscriptionTierFromUserData]).
  final ValueNotifier<String> _subscriptionTier = ValueNotifier<String>('free');
  /// Twilio line lease (for dashboard ring); `null` if unset / legacy.
  final ValueNotifier<DateTime?> _numberLeaseExpiry =
      ValueNotifier<DateTime?>(null);
  final ValueNotifier<String?> _numberPlanType = ValueNotifier<String?>(null);
  final ValueNotifier<_AdRewardView> _adView = ValueNotifier<_AdRewardView>(
    const _AdRewardView(
      adsToday: 0,
      cycleProgress: 0,
      cooldownRemaining: 0,
      dailyLimitReached: false,
    ),
  );

  void _setAdViewIfChanged(_AdRewardView next) {
    if (_adView.value == next) return;
    _adView.value = next;
  }

  /// Single source of truth from cached snapshot + local post-ad cooldown (no full Scaffold rebuild).
  void _refreshFromLatestSnapshot() {
    final snap = _latestUserDoc;
    if (snap == null) return;
    final t = FirestoreUserService.adRewardStatusFromSnapshot(snap);
    final cool = max(t.cooldownRemaining, _localAdCooldownSeconds);
    _setAdViewIfChanged(
      _AdRewardView(
        adsToday: t.adsToday,
        cycleProgress: t.cycleProgress,
        cooldownRemaining: cool,
        dailyLimitReached: t.dailyLimitReached,
      ),
    );
    final cr = FirestoreUserService.usableCreditsFromSnapshot(snap);
    if (_credits.value != cr) {
      _credits.value = cr;
    }
    final d = snap.data();
    final assigned = FirestoreUserService.assignedNumberFromUserData(d);
    if (_assignedNumber.value != assigned) {
      _assignedNumber.value = assigned;
    }
    final lw = FirestoreUserService.lifetimeAdsWatchedFromUserData(d);
    if (_lifetimeAdsWatched.value != lw) {
      _lifetimeAdsWatched.value = lw;
    }
    final tier = FirestoreUserService.subscriptionTierFromUserData(d);
    if (_subscriptionTier.value != tier) {
      _subscriptionTier.value = tier;
    }
    final leaseExp = FirestoreUserService.numberLeaseExpiryFromUserData(d);
    if (_numberLeaseExpiry.value?.millisecondsSinceEpoch !=
        leaseExp?.millisecondsSinceEpoch) {
      _numberLeaseExpiry.value = leaseExp;
    }
    final planT = FirestoreUserService.numberPlanTypeFromUserData(d);
    if (_numberPlanType.value != planT) {
      _numberPlanType.value = planT;
    }
    unawaited(
      FirestoreUserService.claimPremiumWelcomeBonusIfEligible(widget.user.uid),
    );
  }

  void _applyOptimisticAdWatched() {
    final v = _adView.value;
    final nextCycle =
        (v.cycleProgress + 1) >= CreditsPolicy.adsRequiredForMinuteGrant
            ? 0
            : v.cycleProgress + 1;
    _setAdViewIfChanged(
      v.copyWith(
        adsToday: v.adsToday + 1,
        cycleProgress: nextCycle,
        dailyLimitReached:
            v.adsToday + 1 >= CreditsPolicy.maxRewardedAdsPerDay,
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    _navIndex = widget.initialNavIndex;
    _userDocSub =
        FirestoreUserService.watchUserDocument(widget.user.uid).listen(
      (snap) {
        _userDocStreamErrorNotified = false;
        _latestUserDoc = snap;
        _refreshFromLatestSnapshot();
      },
      onError: (Object e, StackTrace st) {
        if (kDebugMode) {
          debugPrint('watchUserDocument error: $e\n$st');
        }
        if (!mounted) return;
        if (_userDocStreamErrorNotified) return;
        _userDocStreamErrorNotified = true;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Could not load your credits. Check your connection and try again.',
            ),
            behavior: SnackBarBehavior.floating,
            duration: Duration(seconds: 5),
          ),
        );
      },
    );
    _cooldownWallClock = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      _refreshFromLatestSnapshot();
    });
  }

  @override
  void dispose() {
    _userDocSub?.cancel();
    _cooldownWallClock?.cancel();
    _localAdCooldownTimer?.cancel();
    _credits.dispose();
    _assignedNumber.dispose();
    _lifetimeAdsWatched.dispose();
    _subscriptionTier.dispose();
    _numberLeaseExpiry.dispose();
    _numberPlanType.dispose();
    _adView.dispose();
    super.dispose();
  }

  /// Fires when the user earned reward — before `/grant-reward` — so the button locks immediately.
  void _startPostAdCooldown() {
    _localAdCooldownTimer?.cancel();
    _localAdCooldownSeconds = CreditsPolicy.adRewardCooldownSeconds;
    _refreshFromLatestSnapshot();
    _localAdCooldownTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      _localAdCooldownSeconds -= 1;
      if (_localAdCooldownSeconds <= 0) {
        _localAdCooldownSeconds = 0;
        _localAdCooldownTimer?.cancel();
        _localAdCooldownTimer = null;
      }
      _refreshFromLatestSnapshot();
    });
  }

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
        _applyOptimisticAdWatched();
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

    // Credits outer so balance-only updates don't rebuild rewarded-ad UI (and vice versa).
    return ValueListenableBuilder<int>(
      valueListenable: _credits,
      builder: (context, credits, _) {
        return ValueListenableBuilder<_AdRewardView>(
          valueListenable: _adView,
          builder: (context, ad, _) {
            final cooldownRemaining = ad.cooldownRemaining;
            final adsToday = ad.adsToday;
            final cycleProgress = ad.cycleProgress;
            final dailyLimitReached = ad.dailyLimitReached;

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
                    credits: credits,
                    assignedNumber: _assignedNumber,
                    numberLeaseExpiry: _numberLeaseExpiry,
                    numberPlanType: _numberPlanType,
                    lifetimeAdsWatched: _lifetimeAdsWatched,
                    subscriptionTier: _subscriptionTier,
                    onDebugAddCredits:
                        kDebugMode ? _debugAddCredits : null,
                    onWatchRewardedAd: () => _onWatchRewardedAd(
                      cooldownRemaining,
                      dailyLimitReached,
                    ),
                    onGoToDialer: () => setState(() => _navIndex = 1),
                  )
                : _navIndex == 1
                    ? ValueListenableBuilder<String>(
                        valueListenable: _subscriptionTier,
                        builder: (context, tier, _) {
                          final isPro = tier == 'pro';
                          return DialerScreen(
                            key: const ValueKey<Object>('talkfree_dialer'),
                            user: widget.user,
                            isPremium: isPro,
                            onEarnMinutes: isPro
                                ? null
                                : () => _onWatchRewardedAd(
                                      cooldownRemaining,
                                      dailyLimitReached,
                                    ),
                            rewardedAdBusy: _rewardedAdBusy,
                            cooldownRemaining: cooldownRemaining,
                            rewardCycleProgress: cycleProgress,
                            rewardDailyLimitReached: dailyLimitReached,
                          );
                        },
                      )
                    : InboxScreen(
                        key: const ValueKey<String>('talkfree_inbox'),
                        user: widget.user,
                      );

            return Scaffold(
              backgroundColor: _navIndex == 0
                  ? const Color(0xFF020814)
                  : AppColors.darkBackground,
              appBar: AppBar(
                title: Text(
                  _navIndex == 0
                      ? 'Home'
                      : _navIndex == 1
                          ? 'Dialer'
                          : 'Inbox',
                ),
                actions: [
                  if (_navIndex == 0)
                    IconButton(
                      tooltip: 'Subscription plans',
                      icon: const Icon(Icons.workspace_premium_outlined),
                      onPressed: () {
                        Navigator.of(context).push<void>(
                          SubscriptionScreen.createRoute(),
                        );
                      },
                    ),
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
              body: Material(
                color: _navIndex == 0 ? Colors.transparent : AppColors.darkBackground,
                child: tabBody,
              ),
              bottomNavigationBar: BottomNavigationBar(
                currentIndex: _navIndex,
                onTap: (i) => setState(() => _navIndex = i),
                type: BottomNavigationBarType.fixed,
                backgroundColor: AppColors.darkBackground,
                selectedItemColor: AppColors.primary,
                unselectedItemColor:
                    TalkFreeColors.mutedWhite.withValues(alpha: 0.5),
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
                  BottomNavigationBarItem(
                    icon: Icon(Icons.inbox_outlined),
                    activeIcon: Icon(Icons.inbox_rounded),
                    label: 'Inbox',
                  ),
                ],
              ),
            );
          },
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
    required this.credits,
    required this.assignedNumber,
    required this.numberLeaseExpiry,
    required this.numberPlanType,
    required this.lifetimeAdsWatched,
    required this.subscriptionTier,
    this.onDebugAddCredits,
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
  /// Balance from parent [ValueNotifier] (single Firestore listener).
  final int credits;
  final ValueNotifier<String?> assignedNumber;
  final ValueNotifier<DateTime?> numberLeaseExpiry;
  final ValueNotifier<String?> numberPlanType;
  final ValueNotifier<int> lifetimeAdsWatched;
  final ValueNotifier<String> subscriptionTier;
  final Future<void> Function()? onDebugAddCredits;
  final Future<void> Function() onWatchRewardedAd;
  final VoidCallback onGoToDialer;

  @override
  State<_DashboardHomeTab> createState() => _DashboardHomeTabState();
}

class _DashboardHomeTabState extends State<_DashboardHomeTab> {
  late Future<void> _ensureFuture;
  bool _assignNumberBusy = false;

  @override
  void initState() {
    super.initState();
    _ensureFuture =
        FirestoreUserService.ensureUserDocument(widget.user.uid);
  }

  Future<void> _onUnlockUsNumber() async {
    if (_assignNumberBusy) return;
    final isPro = widget.subscriptionTier.value == 'pro';
    // Free tier: only lifetime ads gate (50). Premium: no ad requirement.
    if (!isPro) {
      if (widget.lifetimeAdsWatched.value <
          CreditsPolicy.assignNumberMinAdsWatched) {
        return;
      }
    }
    setState(() => _assignNumberBusy = true);
    try {
      await runAssignUsNumberFlow(
        context,
        autoPickFirstNumber: isPro,
        onSuccess: (r) {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                r.alreadyAssigned
                    ? 'Your line: ${r.assignedNumber}'
                    : 'Your US number: ${r.assignedNumber}',
                style: GoogleFonts.montserrat(fontWeight: FontWeight.w600),
              ),
              behavior: SnackBarBehavior.floating,
            ),
          );
        },
        onError: (msg) {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(msg, style: GoogleFonts.montserrat()),
              behavior: SnackBarBehavior.floating,
            ),
          );
        },
      );
    } finally {
      if (mounted) setState(() => _assignNumberBusy = false);
    }
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

        return Stack(
          children: [
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Color(0xFF0A1628),
                      Color(0xFF050A12),
                    ],
                  ),
                ),
              ),
            ),
            ListView(
          padding: EdgeInsets.fromLTRB(
            16,
            16,
            16,
            kDebugMode ? 100 : 28,
          ),
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                if (widget.user.photoURL != null)
                  CircleAvatar(
                    radius: 28,
                    backgroundImage: NetworkImage(widget.user.photoURL!),
                  )
                else
                  CircleAvatar(
                    radius: 28,
                    backgroundColor: TalkFreeColors.cardBg,
                    foregroundColor: AppColors.primary,
                    child: Text(
                      widget.displayName.isNotEmpty
                          ? widget.displayName[0].toUpperCase()
                          : '?',
                      style: GoogleFonts.inter(
                        fontWeight: FontWeight.w800,
                        fontSize: 22,
                      ),
                    ),
                  ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.displayName,
                        style: GoogleFonts.inter(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                          letterSpacing: -0.3,
                          color: TalkFreeColors.offWhite,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (widget.user.email != null &&
                          widget.user.email!.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(
                          widget.user.email!,
                          style: GoogleFonts.inter(
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                            color: TalkFreeColors.mutedWhite,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ],
                  ),
                ),
                _LightningWalletPill(
                  credits: widget.credits,
                  onDebugLongPress: widget.onDebugAddCredits,
                ),
              ],
            ),
            const SizedBox(height: 14),
            ValueListenableBuilder<String>(
              valueListenable: widget.subscriptionTier,
              builder: (context, tier, _) {
                final isPro = tier.toLowerCase() == 'pro';
                return Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 7,
                      ),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(999),
                        gradient: isPro
                            ? const LinearGradient(
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                                colors: [
                                  Color(0xFFE8C547),
                                  Color(0xFF9333EA),
                                  Color(0xFF581C87),
                                ],
                                stops: [0.0, 0.55, 1.0],
                              )
                            : null,
                        color: isPro ? null : TalkFreeColors.cardBg,
                        border: Border.all(
                          color: isPro
                              ? Colors.transparent
                              : TalkFreeColors.mutedWhite.withValues(alpha: 0.2),
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            isPro
                                ? Icons.verified_rounded
                                : Icons.lock_open_rounded,
                            size: 16,
                            color: isPro
                                ? Colors.white.withValues(alpha: 0.95)
                                : TalkFreeColors.mutedWhite,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            'Current plan: ${isPro ? 'Pro' : 'Free'}',
                            style: GoogleFonts.inter(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: isPro
                                  ? Colors.white
                                  : TalkFreeColors.offWhite,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const Spacer(),
                    TextButton(
                      onPressed: () {
                        Navigator.of(context).push<void>(
                          SubscriptionScreen.createRoute(),
                        );
                      },
                      child: Text(
                        'View plans',
                        style: GoogleFonts.inter(
                          fontWeight: FontWeight.w700,
                          fontSize: 14,
                          color: AppColors.primary,
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
            ValueListenableBuilder<String>(
              valueListenable: widget.subscriptionTier,
              builder: (context, tier, _) {
                final isPro = tier == 'pro';
                if (isPro) return const SizedBox.shrink();
                return Column(
                  children: [
                    const SizedBox(height: 12),
                    _GetPremiumHeroButton(
                      onPressed: () {
                        Navigator.of(context).push<void>(
                          SubscriptionScreen.createRoute(),
                        );
                      },
                    ),
                    const SizedBox(height: 12),
                  ],
                );
              },
            ),
            const SizedBox(height: 12),
            RepaintBoundary(
              child: ValueListenableBuilder<String>(
                valueListenable: widget.subscriptionTier,
                builder: (context, tier, _) {
                  final isPro = tier == 'pro';
                  if (isPro) {
                    return const _ProBenefitsCard();
                  }
                  return _AdsPowerCard(
                    rewardedAdBusy: widget.rewardedAdBusy,
                    cooldownRemaining: widget.cooldownRemaining,
                    cycleProgress: widget.cycleProgress,
                    dailyLimitReached: widget.dailyLimitReached,
                    adsToday: widget.adsToday,
                    credits: widget.credits,
                    onEarn: widget.onWatchRewardedAd,
                  );
                },
              ),
            ),
            const SizedBox(height: 20),
            RepaintBoundary(
              child: ValueListenableBuilder<String?>(
                valueListenable: widget.assignedNumber,
                builder: (context, assigned, _) {
                  return ValueListenableBuilder<int>(
                    valueListenable: widget.lifetimeAdsWatched,
                    builder: (context, adsWatched, _) {
                      return ValueListenableBuilder<DateTime?>(
                        valueListenable: widget.numberLeaseExpiry,
                        builder: (context, leaseExp, _) {
                          return ValueListenableBuilder<String?>(
                            valueListenable: widget.numberPlanType,
                            builder: (context, planType, _) {
                              return ValueListenableBuilder<String>(
                                valueListenable: widget.subscriptionTier,
                                builder: (context, tier, _) {
                                  return _VirtualNumberCard(
                                    assignedNumber: assigned,
                                    leaseExpiry: leaseExp,
                                    planType: planType,
                                    adsWatchedCount: adsWatched,
                                    credits: widget.credits,
                                    isPremium: tier == 'pro',
                                    assigning: _assignNumberBusy,
                                    onUnlock: _onUnlockUsNumber,
                                    onGetPremium: () {
                                      Navigator.of(context).push<void>(
                                        SubscriptionScreen.createRoute(),
                                      );
                                    },
                                  );
                                },
                              );
                            },
                          );
                        },
                      );
                    },
                  );
                },
              ),
            ),
            const SizedBox(height: 22),
            ValueListenableBuilder<String>(
              valueListenable: widget.subscriptionTier,
              builder: (context, tier, _) {
                final isPro = tier == 'pro';
                final cpm = CreditsPolicy.creditsPerMinuteForUser(isPro);
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
                    const SizedBox(width: 16),
                    Expanded(
                      child: _DashboardStatCard(
                        icon: Icons.timer_outlined,
                        label: 'Minutes',
                        value: (widget.credits / cpm).toStringAsFixed(1),
                        caption: 'Est. @ $cpm⚡/min',
                        animatedValue: true,
                      ),
                    ),
                  ],
                );
              },
            ),
            const SizedBox(height: 22),
            _RecentActivitySection(
              onOpenDialer: widget.onGoToDialer,
            ),
          ],
            ),
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
    this.animatedValue = false,
  });

  final IconData icon;
  final String label;
  final String value;
  final String caption;
  final bool animatedValue;

  @override
  Widget build(BuildContext context) {
    return GlassPanel(
      borderRadius: AppTheme.radiusLg,
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 16),
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
                  style: GoogleFonts.inter(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: TalkFreeColors.mutedWhite,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          animatedValue
              ? AnimatedSwitcher(
                  duration: const Duration(milliseconds: 240),
                  switchInCurve: Curves.easeOutCubic,
                  switchOutCurve: Curves.easeInCubic,
                  transitionBuilder: (child, anim) => FadeTransition(
                    opacity: anim,
                    child: SlideTransition(
                      position: Tween<Offset>(
                        begin: const Offset(0, 0.06),
                        end: Offset.zero,
                      ).animate(anim),
                      child: child,
                    ),
                  ),
                  child: Text(
                    value,
                    key: ValueKey<String>(value),
                    style: GoogleFonts.poppins(
                      fontSize: 26,
                      fontWeight: FontWeight.w700,
                      height: 1.05,
                      color: TalkFreeColors.offWhite,
                      letterSpacing: -0.5,
                    ),
                  ),
                )
              : Text(
                  value,
                  style: GoogleFonts.poppins(
                    fontSize: 26,
                    fontWeight: FontWeight.w700,
                    height: 1.05,
                    color: TalkFreeColors.offWhite,
                    letterSpacing: -0.5,
                  ),
                ),
          const SizedBox(height: 6),
          Text(
            caption,
            style: GoogleFonts.inter(
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
            color: TalkFreeColors.cardBg.withValues(alpha: 0.88),
            borderRadius: BorderRadius.circular(AppTheme.radiusLg),
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.06),
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
                    borderRadius: BorderRadius.circular(AppTheme.radiusLg),
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

/// Glowing credits badge — balance (debug long-press adds credits).
class _LightningWalletPill extends StatelessWidget {
  const _LightningWalletPill({
    required this.credits,
    this.onDebugLongPress,
  });

  final int credits;
  final Future<void> Function()? onDebugLongPress;

  @override
  Widget build(BuildContext context) {
    final amber = AppColors.accentAmber;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onLongPress: onDebugLongPress == null
            ? null
            : () {
                onDebugLongPress!();
              },
        borderRadius: BorderRadius.circular(999),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(999),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                const Color(0xFF1A1528).withValues(alpha: 0.95),
                const Color(0xFF0D0B14).withValues(alpha: 0.98),
              ],
            ),
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.22),
              width: 0.5,
            ),
            boxShadow: [
              BoxShadow(
                color: amber.withValues(alpha: 0.45),
                blurRadius: 8,
                spreadRadius: 2,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.bolt_rounded,
                color: amber.withValues(alpha: 0.98),
                size: 20,
              ),
              const SizedBox(width: 6),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'CREDITS',
                    style: GoogleFonts.inter(
                      fontSize: 9,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1.2,
                      color: TalkFreeColors.mutedWhite.withValues(alpha: 0.85),
                    ),
                  ),
                  _AnimatedIntText(
                    value: credits,
                    style: GoogleFonts.poppins(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      height: 1.05,
                      color: TalkFreeColors.offWhite,
                      letterSpacing: -0.4,
                      shadows: [
                        Shadow(
                          color: amber.withValues(alpha: 0.35),
                          blurRadius: 10,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AdsRingPainter extends CustomPainter {
  _AdsRingPainter({required this.progress});
  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    final c = Offset(size.width / 2, size.height / 2);
    final r = size.shortestSide / 2 - 12;
    final bg = Paint()
      ..color = Colors.white.withValues(alpha: 0.08)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 11;
    final fg = Paint()
      ..color = AppColors.primary
      ..style = PaintingStyle.stroke
      ..strokeWidth = 11
      ..strokeCap = StrokeCap.round;
    canvas.drawCircle(c, r, bg);
    final sweep = 2 * pi * progress.clamp(0.0, 1.0);
    canvas.drawArc(
      Rect.fromCircle(center: c, radius: r),
      -pi / 2,
      sweep,
      false,
      fg,
    );
  }

  @override
  bool shouldRepaint(covariant _AdsRingPainter oldDelegate) =>
      oldDelegate.progress != progress;
}

/// Large glass “Power Card” — circular progress for ads toward the minute grant.
class _AdsPowerCard extends StatelessWidget {
  const _AdsPowerCard({
    required this.rewardedAdBusy,
    required this.cooldownRemaining,
    required this.cycleProgress,
    required this.dailyLimitReached,
    required this.adsToday,
    required this.credits,
    required this.onEarn,
  });

  final bool rewardedAdBusy;
  final int cooldownRemaining;
  final int cycleProgress;
  final bool dailyLimitReached;
  final int adsToday;
  final int credits;
  final Future<void> Function() onEarn;

  @override
  Widget build(BuildContext context) {
    final need = CreditsPolicy.adsRequiredForMinuteGrant;
    final p = cycleProgress.clamp(0, need);
    final ringProgress = p / need;
    final canTap =
        !rewardedAdBusy && !dailyLimitReached && cooldownRemaining <= 0;

    return Material(
      color: Colors.transparent,
      child: GlassPanel(
        borderRadius: AppTheme.radiusLg,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: canTap
                ? () {
                    onEarn();
                  }
                : null,
            borderRadius: BorderRadius.circular(AppTheme.radiusLg),
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
            children: [
              Row(
                children: [
                  Icon(
                    Icons.auto_awesome_rounded,
                    color: AppColors.primary.withValues(alpha: 0.95),
                    size: 22,
                  ),
                  const SizedBox(width: 10),
                  Text(
                    'Earn credits',
                    style: GoogleFonts.inter(
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1.4,
                      color: TalkFreeColors.mutedWhite,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              SizedBox(
                height: 168,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    CustomPaint(
                      size: const Size(168, 168),
                      painter: _AdsRingPainter(progress: ringProgress),
                    ),
                    if (rewardedAdBusy)
                      const SizedBox(
                        width: 36,
                        height: 36,
                        child: CircularProgressIndicator(
                          strokeWidth: 3,
                          color: AppColors.primary,
                        ),
                      )
                    else if (dailyLimitReached)
                      Icon(
                        Icons.block_rounded,
                        size: 40,
                        color: TalkFreeColors.mutedWhite.withValues(alpha: 0.6),
                      )
                    else if (cooldownRemaining > 0)
                      Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.timer_outlined,
                            color: AppColors.primary.withValues(alpha: 0.95),
                            size: 32,
                          ),
                          const SizedBox(height: 6),
                          Text(
                            '${cooldownRemaining}s',
                            style: GoogleFonts.poppins(
                              fontSize: 22,
                              fontWeight: FontWeight.w700,
                              color: TalkFreeColors.offWhite,
                            ),
                          ),
                        ],
                      )
                    else
                      Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            'Ads watched',
                            style: GoogleFonts.inter(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: TalkFreeColors.mutedWhite,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '$p / $need',
                            style: GoogleFonts.poppins(
                              fontSize: 28,
                              fontWeight: FontWeight.w700,
                              color: TalkFreeColors.offWhite,
                              letterSpacing: -1,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Tap to watch',
                            style: GoogleFonts.inter(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: AppColors.primary,
                            ),
                          ),
                        ],
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              Text(
                '${CreditsPolicy.adsRequiredForMinuteGrant} ads = '
                '${CreditsPolicy.creditsPerMinuteGrant} credits (1 min)',
                textAlign: TextAlign.center,
                style: GoogleFonts.inter(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  height: 1.35,
                  color: TalkFreeColors.mutedWhite,
                ),
              ),
              const SizedBox(height: 6),
              Text.rich(
                TextSpan(
                  style: GoogleFonts.inter(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: TalkFreeColors.mutedWhite.withValues(alpha: 0.75),
                  ),
                  children: [
                    TextSpan(
                      text: '$adsToday / ${CreditsPolicy.maxRewardedAdsPerDay}',
                      style: GoogleFonts.poppins(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: TalkFreeColors.mutedWhite.withValues(alpha: 0.85),
                      ),
                    ),
                    const TextSpan(text: ' ads today'),
                  ],
                ),
                textAlign: TextAlign.center,
              ),
              if (credits == 0 && canTap) ...[
                const SizedBox(height: 10),
                Text(
                  'Start here — your balance is 0',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.inter(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: AppColors.accentAmber.withValues(alpha: 0.95),
                  ),
                ),
              ],
            ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Full-width CTA — shimmer + gold crown; opens [SubscriptionScreen].
class _GetPremiumHeroButton extends StatefulWidget {
  const _GetPremiumHeroButton({required this.onPressed});

  final VoidCallback onPressed;

  @override
  State<_GetPremiumHeroButton> createState() => _GetPremiumHeroButtonState();
}

class _GetPremiumHeroButtonState extends State<_GetPremiumHeroButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _shimmer;

  @override
  void initState() {
    super.initState();
    _shimmer = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2600),
    )..repeat();
  }

  @override
  void dispose() {
    _shimmer.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: widget.onPressed,
        borderRadius: BorderRadius.circular(18),
        child: Ink(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Color(0xFFFFD54F),
                Color(0xFFE8C547),
                Color(0xFF9333EA),
                Color(0xFF4C1D95),
              ],
              stops: [0.0, 0.25, 0.55, 1.0],
            ),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFFE8C547).withValues(alpha: 0.4),
                blurRadius: 22,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(18),
            child: Stack(
              children: [
                AnimatedBuilder(
                  animation: _shimmer,
                  builder: (context, _) {
                    final t = _shimmer.value;
                    return Positioned.fill(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment(-1.2 + 2.4 * t, -0.5),
                            end: Alignment(0.2 + 2.4 * t, 1),
                            colors: [
                              Colors.transparent,
                              Colors.white.withValues(alpha: 0.22),
                              Colors.transparent,
                            ],
                            stops: const [0.4, 0.5, 0.6],
                          ),
                        ),
                      ),
                    );
                  },
                ),
                Padding(
                  padding:
                      const EdgeInsets.symmetric(vertical: 16, horizontal: 20),
                  child: Row(
                    children: [
                      Icon(
                        Icons.emoji_events_rounded,
                        color: const Color(0xFFFFD700),
                        size: 28,
                        shadows: const [
                          Shadow(
                            color: Color(0x66FFD700),
                            blurRadius: 12,
                          ),
                        ],
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Get Premium',
                              style: GoogleFonts.inter(
                                fontSize: 17,
                                fontWeight: FontWeight.w800,
                                color: Colors.white,
                                letterSpacing: -0.3,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              'Instant US number · No ads · Bonus credits',
                              style: GoogleFonts.inter(
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
                                color: Colors.white.withValues(alpha: 0.92),
                              ),
                            ),
                          ],
                        ),
                      ),
                      Icon(
                        Icons.chevron_right_rounded,
                        color: Colors.white.withValues(alpha: 0.95),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Replaces the “Earn credits” power card for Pro users.
class _ProBenefitsCard extends StatelessWidget {
  const _ProBenefitsCard();

  @override
  Widget build(BuildContext context) {
    return GlassPanel(
      borderRadius: AppTheme.radiusLg,
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.verified_rounded,
                color: const Color(0xFFE8C547).withValues(alpha: 0.95),
                size: 22,
              ),
              const SizedBox(width: 10),
              Text(
                'You’re on TalkFree Pro',
                style: GoogleFonts.inter(
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                  color: TalkFreeColors.offWhite,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _proLine('Ad-free experience'),
          _proLine('Bonus credits & lower call rates'),
          _proLine('Priority line quality'),
        ],
      ),
    );
  }

  static Widget _proLine(String t) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.check_circle_rounded,
            size: 18,
            color: AppColors.primary.withValues(alpha: 0.95),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              t,
              style: GoogleFonts.inter(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                height: 1.35,
                color: TalkFreeColors.offWhite.withValues(alpha: 0.92),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Fraction of lease time remaining (vs plan length from server).
double _leaseRemainingFraction(
  DateTime now,
  DateTime expiry,
  String? planType,
) {
  final leaseMs = CreditsPolicy.leaseDurationMsForPlanType(planType);
  final leftMs = expiry.difference(now).inMilliseconds;
  if (leftMs <= 0) return 0;
  return (leftMs / leaseMs).clamp(0.0, 1.0);
}

String _leaseShortLabel(DateTime now, DateTime? expiry) {
  if (expiry == null) return 'No expiry set';
  final left = expiry.difference(now);
  if (left.inSeconds <= 0) return 'Expired';
  if (left.inDays >= 1) return '${left.inDays}d left';
  if (left.inHours >= 1) return '${left.inHours}h left';
  return '${left.inMinutes}m left';
}

/// Glass number block + lease ring; locked state keeps prior card actions.
class _VirtualNumberCard extends StatefulWidget {
  const _VirtualNumberCard({
    required this.assignedNumber,
    required this.leaseExpiry,
    required this.planType,
    required this.adsWatchedCount,
    required this.credits,
    required this.isPremium,
    required this.assigning,
    required this.onUnlock,
    required this.onGetPremium,
  });

  final String? assignedNumber;
  final DateTime? leaseExpiry;
  final String? planType;
  final int adsWatchedCount;
  final int credits;
  final bool isPremium;
  final bool assigning;
  final Future<void> Function() onUnlock;
  final VoidCallback onGetPremium;

  @override
  State<_VirtualNumberCard> createState() => _VirtualNumberCardState();
}

class _VirtualNumberCardState extends State<_VirtualNumberCard>
    with SingleTickerProviderStateMixin {
  /// Drives lease countdown + ring; only runs while a line + expiry exist.
  Timer? _tick;
  /// Breathing scale on the “+” in the no-number glass state; stopped when a line exists.
  late final AnimationController _plusPulse;

  @override
  void initState() {
    super.initState();
    _plusPulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1600),
    );
    _syncTicker();
    _syncPlusPulse();
  }

  @override
  void didUpdateWidget(covariant _VirtualNumberCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncTicker();
    _syncPlusPulse();
  }

  void _syncTicker() {
    final has = widget.assignedNumber?.trim().isNotEmpty == true;
    final exp = widget.leaseExpiry;
    if (has && exp != null) {
      _tick ??= Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted) setState(() {});
      });
    } else {
      _tick?.cancel();
      _tick = null;
    }
  }

  void _syncPlusPulse() {
    final has = widget.assignedNumber?.trim().isNotEmpty == true;
    if (has) {
      _plusPulse.stop();
    } else {
      if (!_plusPulse.isAnimating) {
        _plusPulse.repeat(reverse: true);
      }
    }
  }

  @override
  void dispose() {
    _tick?.cancel();
    _plusPulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final numberRaw = widget.assignedNumber?.trim();
    final hasNumber = numberRaw != null && numberRaw.isNotEmpty;
    final minAds = CreditsPolicy.assignNumberMinAdsWatched;
    final canUnlock =
        widget.isPremium || widget.adsWatchedCount >= minAds;

    final br = BorderRadius.circular(AppTheme.radiusLg);
    final now = DateTime.now();
    final expiry = widget.leaseExpiry;
    final leaseFrac = (hasNumber && expiry != null)
        ? _leaseRemainingFraction(now, expiry, widget.planType)
        : 1.0;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 420),
      curve: Curves.easeOutCubic,
      width: double.infinity,
      decoration: BoxDecoration(
        borderRadius: br,
        boxShadow: [
          if (!hasNumber)
            BoxShadow(
              color: AppColors.primary.withValues(alpha: 0.22),
              blurRadius: 28,
              spreadRadius: 2,
              offset: const Offset(0, 10),
            ),
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.4),
            blurRadius: 22,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: GlassPanel(
        borderRadius: AppTheme.radiusLg,
        padding: const EdgeInsets.all(20),
        child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    hasNumber ? Icons.verified_user_rounded : Icons.lock_rounded,
                    color: hasNumber
                        ? AppColors.primary
                        : TalkFreeColors.mutedWhite.withValues(alpha: 0.75),
                    size: 22,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'VIRTUAL NUMBER',
                      style: GoogleFonts.inter(
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 2,
                        color: TalkFreeColors.mutedWhite,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              if (hasNumber) ...[
                Text(
                  'Your US line',
                  style: GoogleFonts.inter(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: TalkFreeColors.mutedWhite,
                  ),
                ),
                const SizedBox(height: 12),
                GlassPanel(
                  borderRadius: 24,
                  padding: const EdgeInsets.symmetric(
                    vertical: 20,
                    horizontal: 12,
                  ),
                  child: Column(
                        children: [
                          SizedBox(
                            height: 196,
                            width: 196,
                            child: Stack(
                              alignment: Alignment.center,
                              children: [
                                CustomPaint(
                                  size: const Size(196, 196),
                                  painter: LeaseRingPainter(
                                    progress: leaseFrac,
                                    trackColor: Colors.white.withValues(
                                      alpha: 0.14,
                                    ),
                                    foregroundColor: leaseRingForegroundColor(
                                      now,
                                      expiry,
                                    ),
                                  ),
                                ),
                                Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    SelectableText(
                                      formatUsPhoneForDisplay(numberRaw),
                                      textAlign: TextAlign.center,
                                      style: GoogleFonts.jetBrainsMono(
                                        fontSize: 20,
                                        fontWeight: FontWeight.w700,
                                        letterSpacing: 0.4,
                                        color: TalkFreeColors.offWhite,
                                      ),
                                    ),
                                    const SizedBox(height: 6),
                                    Text(
                                      _leaseShortLabel(now, expiry),
                                      style: GoogleFonts.poppins(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w600,
                                        color: leaseRingForegroundColor(
                                          now,
                                          expiry,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 14),
                          Wrap(
                            crossAxisAlignment: WrapCrossAlignment.center,
                            spacing: 10,
                            runSpacing: 8,
                            alignment: WrapAlignment.center,
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 5,
                                ),
                                decoration: BoxDecoration(
                                  color: AppColors.primary.withValues(alpha: 0.18),
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(
                                    color:
                                        AppColors.primary.withValues(alpha: 0.45),
                                  ),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      Icons.verified_rounded,
                                      size: 15,
                                      color: AppColors.primary,
                                    ),
                                    const SizedBox(width: 4),
                                    Text(
                                      'Verified',
                                      style: GoogleFonts.inter(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w800,
                                        letterSpacing: 0.3,
                                        color: AppColors.primary,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                ),
                const SizedBox(height: 10),
                Text(
                  'SMS and calls route to your Inbox.',
                  style: GoogleFonts.inter(
                    fontSize: 12,
                    height: 1.35,
                    color: TalkFreeColors.mutedWhite.withValues(alpha: 0.88),
                  ),
                ),
              ] else ...[
                GlassPanel(
                  borderRadius: 24,
                  padding: const EdgeInsets.symmetric(
                    vertical: 22,
                    horizontal: 16,
                  ),
                  child: Column(
                        children: [
                          Text(
                            'Unlock Your Global Identity',
                            textAlign: TextAlign.center,
                            style: GoogleFonts.inter(
                              fontSize: 17,
                              fontWeight: FontWeight.w800,
                              height: 1.25,
                              letterSpacing: -0.2,
                              color: TalkFreeColors.offWhite,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Add a dedicated US line — SMS, calls & inbox in one place.',
                            textAlign: TextAlign.center,
                            style: GoogleFonts.inter(
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                              height: 1.4,
                              color: TalkFreeColors.mutedWhite.withValues(
                                alpha: 0.92,
                              ),
                            ),
                          ),
                          const SizedBox(height: 18),
                          ScaleTransition(
                            scale: Tween<double>(begin: 0.92, end: 1.0).animate(
                              CurvedAnimation(
                                parent: _plusPulse,
                                curve: Curves.easeInOut,
                              ),
                            ),
                            child: Container(
                              width: 56,
                              height: 56,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: AppColors.primary.withValues(alpha: 0.2),
                                border: Border.all(
                                  color: AppColors.primary.withValues(
                                    alpha: 0.55,
                                  ),
                                  width: 1.5,
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color: AppColors.primary.withValues(
                                      alpha: 0.35,
                                    ),
                                    blurRadius: 18,
                                    spreadRadius: 0,
                                  ),
                                ],
                              ),
                              child: Icon(
                                Icons.add_rounded,
                                size: 32,
                                color: AppColors.primary.withValues(alpha: 0.98),
                              ),
                            ),
                          ),
                        ],
                      ),
                ),
                const SizedBox(height: 14),
                Text(
                  widget.isPremium
                      ? 'Your subscription includes an instant US line — claim it below.'
                      : canUnlock
                          ? 'Claim your Twilio US line — it appears in Inbox instantly.'
                          : 'Watch $minAds ads to unlock — your progress:',
                  style: GoogleFonts.inter(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    height: 1.45,
                    color: TalkFreeColors.mutedWhite,
                  ),
                ),
                if (!widget.isPremium && !canUnlock) ...[
                  const SizedBox(height: 12),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: LinearProgressIndicator(
                      value: min(1, widget.adsWatchedCount / minAds),
                      minHeight: 8,
                      backgroundColor: Colors.white.withValues(alpha: 0.08),
                      color: AppColors.primary,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          '${widget.adsWatchedCount.clamp(0, minAds)} / $minAds ads',
                          style: GoogleFonts.poppins(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: AppColors.accentAmber.withValues(alpha: 0.95),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton(
                      onPressed: widget.onGetPremium,
                      child: Text(
                        'Don’t want to wait? Get Premium to unlock instantly!',
                        style: GoogleFonts.inter(
                          fontWeight: FontWeight.w700,
                          fontSize: 13,
                          color: const Color(0xFFE8C547),
                        ),
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: (!canUnlock || widget.assigning)
                        ? null
                        : () => widget.onUnlock(),
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      disabledBackgroundColor:
                          TalkFreeColors.cardBg.withValues(alpha: 0.65),
                      foregroundColor: AppColors.onPrimary,
                      disabledForegroundColor:
                          TalkFreeColors.mutedWhite.withValues(alpha: 0.55),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                    child: widget.assigning
                        ? Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              SizedBox(
                                width: 22,
                                height: 22,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2.5,
                                  color: AppColors.onPrimary.withValues(
                                    alpha: 0.95,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Text(
                                'Claiming…',
                                style: GoogleFonts.inter(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ],
                          )
                        : Text(
                            'Unlock US Number',
                            style: GoogleFonts.inter(
                              fontSize: 15,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                  ),
                ),
              ],
            ],
          ),
        ),
    );
  }
}

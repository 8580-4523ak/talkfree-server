import 'dart:async' show StreamSubscription, Timer, unawaited;
import 'dart:math' show max, min;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show immutable, kDebugMode;
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lottie/lottie.dart';

import '../config/credits_policy.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import '../theme/system_ui.dart';
import '../services/ad_service.dart';
import '../utils/call_log_format.dart';
import '../utils/reward_ad_feedback.dart';
import '../utils/us_phone_format.dart';
import '../services/assign_free_number_service.dart';
import '../services/assign_number_service.dart';
import '../widgets/assign_us_number_flow.dart';
import '../widgets/engagement_overlays.dart';
import '../widgets/glass_panel.dart';
import '../widgets/low_credit_nudge.dart';
import '../widgets/lease_ring_painter.dart';
import '../services/firestore_user_service.dart';
import '../services/grant_reward_service.dart';
import '../services/reward_sound_service.dart';
import 'call_history_screen.dart';
import 'dialer_screen.dart';
import 'inbox_screen.dart';
import 'settings_screen.dart';
import 'number_selection_screen.dart';
import 'subscription_screen.dart';
import 'virtual_number_screen.dart';

/// Immutable rewarded-ad row for ValueNotifier (equality avoids redundant notifies).
@immutable
class _AdRewardView {
  const _AdRewardView({
    required this.adsToday,
    required this.cooldownRemaining,
    required this.dailyLimitReached,
  });

  final int adsToday;
  final int cooldownRemaining;
  final bool dailyLimitReached;

  _AdRewardView copyWith({
    int? adsToday,
    int? cooldownRemaining,
    bool? dailyLimitReached,
  }) {
    return _AdRewardView(
      adsToday: adsToday ?? this.adsToday,
      cooldownRemaining: cooldownRemaining ?? this.cooldownRemaining,
      dailyLimitReached: dailyLimitReached ?? this.dailyLimitReached,
    );
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is _AdRewardView &&
            other.adsToday == adsToday &&
            other.cooldownRemaining == cooldownRemaining &&
            other.dailyLimitReached == dailyLimitReached;
  }

  @override
  int get hashCode => Object.hash(adsToday, cooldownRemaining, dailyLimitReached);
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

class _DashboardScreenState extends State<DashboardScreen>
    with TickerProviderStateMixin {
  bool _rewardedAdBusy = false;
  /// True while `POST /grant-reward` is in flight (after ad earned reward).
  bool _grantRewardPending = false;
  late int _navIndex;

  /// Client-side cooldown after a rewarded ad finishes (sync with [CreditsPolicy.adRewardCooldownSeconds]).
  Timer? _localAdCooldownTimer;
  int _localAdCooldownSeconds = 0;

  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _userDocSub;
  Timer? _cooldownWallClock;
  DocumentSnapshot<Map<String, dynamic>>? _latestUserDoc;

  /// Avoid spamming SnackBars if the user document stream errors repeatedly.
  bool _userDocStreamErrorNotified = false;
  late final AnimationController _walletGlowController;
  late final Animation<double> _walletGlowAnim;

  final ValueNotifier<int> _credits = ValueNotifier<int>(0);
  /// US line from Firestore (`assigned_number` / mirrors) — updated live from [FirestoreUserService.watchUserDocument]
  /// while this screen stays mounted (including when other routes are pushed on top). No manual refresh needed after
  /// `Navigator.popUntil` from number provisioning; the next snapshot updates Home (Virtual Number card) automatically.
  final ValueNotifier<String?> _assignedNumber = ValueNotifier<String?>(null);
  final ValueNotifier<int> _lifetimeAdsWatched = ValueNotifier<int>(0);
  /// `'free'` | `'pro'` from Firestore ([FirestoreUserService.subscriptionTierFromUserData]).
  final ValueNotifier<String> _subscriptionTier = ValueNotifier<String>('free');
  /// Twilio line lease (for dashboard ring); `null` if unset / legacy.
  final ValueNotifier<DateTime?> _numberLeaseExpiry =
      ValueNotifier<DateTime?>(null);
  final ValueNotifier<String?> _numberPlanType = ValueNotifier<String?>(null);
  /// Server-maintained totals (Twilio settlement); see [FirestoreUserService.totalOutboundCallsFromUserData].
  final ValueNotifier<int> _outboundCallsTotal = ValueNotifier<int>(0);
  final ValueNotifier<int> _totalCallTalkSeconds = ValueNotifier<int>(0);
  /// Server-maintained `ad_streak_count` (UTC consecutive ad days).
  final ValueNotifier<int> _adStreakCount = ValueNotifier<int>(0);
  final ValueNotifier<_AdRewardView> _adView = ValueNotifier<_AdRewardView>(
    const _AdRewardView(
      adsToday: 0,
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
    final calls = FirestoreUserService.totalOutboundCallsFromUserData(d);
    if (_outboundCallsTotal.value != calls) {
      _outboundCallsTotal.value = calls;
    }
    final talk = FirestoreUserService.totalCallTalkSecondsFromUserData(d);
    if (_totalCallTalkSeconds.value != talk) {
      _totalCallTalkSeconds.value = talk;
    }
    final streak = FirestoreUserService.adStreakCountFromUserData(d);
    if (_adStreakCount.value != streak) {
      _adStreakCount.value = streak;
    }
  }

  void _applyOptimisticAdWatched() {
    final v = _adView.value;
    _setAdViewIfChanged(
      v.copyWith(
        adsToday: v.adsToday + 1,
        dailyLimitReached:
            v.adsToday + 1 >= CreditsPolicy.maxRewardedAdsPerDay,
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    _walletGlowController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 420),
    );
    _walletGlowAnim = CurvedAnimation(
      parent: _walletGlowController,
      curve: Curves.easeInOut,
    );
    applyTalkFreeDarkNavigationChrome();
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
    _outboundCallsTotal.dispose();
    _totalCallTalkSeconds.dispose();
    _adStreakCount.dispose();
    _adView.dispose();
    _walletGlowController.dispose();
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
        SnackBar(
          content: Text(RewardAdFeedback.dailyLimit),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }
    if (cooldownRemaining > 0) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(RewardAdFeedback.cooldownBeforeNextAd()),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }
    setState(() {
      _rewardedAdBusy = true;
      _grantRewardPending = false;
    });
    try {
      final earned = await AdService.instance.loadAndShowRewardedAd();
      if (!mounted) return;
      if (earned) {
        _applyOptimisticAdWatched();
        _startPostAdCooldown();
        setState(() => _grantRewardPending = true);
        try {
          final result = await GrantRewardService.instance.requestMinuteGrant();
          if (!mounted) return;
          if (result.creditsAdded > 0) {
            _credits.value = _credits.value + result.creditsAdded;
            unawaited(RewardSoundService.playCoin());
            EngagementOverlays.showAdRewardFanfare(
              context,
              creditsAdded: result.creditsAdded,
              streakBonus: result.streakBonus,
              streakDays: result.streakCount,
            );
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  RewardAdFeedback.successCreditsAdded(result.creditsAdded),
                ),
                behavior: SnackBarBehavior.floating,
                duration: const Duration(seconds: 4),
              ),
            );
          } else {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text(
                  'Reward recorded — credits will sync shortly.',
                ),
                behavior: SnackBarBehavior.floating,
              ),
            );
          }
        } on GrantRewardException catch (e) {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(RewardAdFeedback.forGrantError(e)),
              behavior: SnackBarBehavior.floating,
              duration: const Duration(seconds: 5),
            ),
          );
        } catch (e) {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(RewardAdFeedback.forGrantError(e)),
              behavior: SnackBarBehavior.floating,
              duration: const Duration(seconds: 5),
            ),
          );
        } finally {
          if (mounted) {
            setState(() => _grantRewardPending = false);
          }
        }
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(RewardAdFeedback.incompleteAd),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(RewardAdFeedback.forAdPlaybackError(e)),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _rewardedAdBusy = false;
          _grantRewardPending = false;
        });
      }
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
            final dailyLimitReached = ad.dailyLimitReached;

            // One body subtree at a time — no IndexedStack (avoids touch bugs on some
            // OEM builds where an invisible sibling still wins hit testing).
            final Widget tabBody = _navIndex == 0
                ? _DashboardHomeTab(
                    user: widget.user,
                    displayName: displayName,
                    theme: theme,
                    rewardedAdBusy: _rewardedAdBusy,
                    grantRewardPending: _grantRewardPending,
                    cooldownRemaining: cooldownRemaining,
                    adsToday: adsToday,
                    dailyLimitReached: dailyLimitReached,
                    credits: credits,
                    assignedNumber: _assignedNumber,
                    numberLeaseExpiry: _numberLeaseExpiry,
                    numberPlanType: _numberPlanType,
                    lifetimeAdsWatched: _lifetimeAdsWatched,
                    subscriptionTier: _subscriptionTier,
                    outboundCallsTotal: _outboundCallsTotal,
                    totalCallTalkSeconds: _totalCallTalkSeconds,
                    adStreakCount: _adStreakCount,
                    onDebugAddCredits:
                        kDebugMode ? _debugAddCredits : null,
                    onWatchRewardedAd: () => _onWatchRewardedAd(
                      cooldownRemaining,
                      dailyLimitReached,
                    ),
                    onGoToDialer: () => setState(() => _navIndex = 1),
                    onOpenCallHistory: () {
                      Navigator.of(context).push<void>(
                        MaterialPageRoute<void>(
                          builder: (_) => CallHistoryScreen(
                            user: widget.user,
                            onStartCalling: () {
                              setState(() => _navIndex = 1);
                            },
                          ),
                        ),
                      );
                    },
                    walletGlow: _walletGlowAnim,
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
                            rewardDailyLimitReached: dailyLimitReached,
                            outboundCallsTotal: _outboundCallsTotal,
                          );
                        },
                      )
                    : InboxScreen(
                        key: const ValueKey<String>('talkfree_inbox'),
                        user: widget.user,
                      );

            return Scaffold(
              backgroundColor: AppTheme.darkBg,
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
                  if (_navIndex == 0)
                    IconButton(
                      tooltip: 'My US number',
                      icon: const Icon(Icons.contact_phone_outlined),
                      onPressed: () {
                        Navigator.of(context).pushNamed(
                          VirtualNumberScreen.routeName,
                          arguments: VirtualNumberRouteArgs(
                            userUid: widget.user.uid,
                            userCredits: credits,
                          ),
                        );
                      },
                    ),
                  IconButton(
                    tooltip: 'Recents',
                    icon: const Icon(Icons.history_rounded),
                    onPressed: () {
                      Navigator.of(context).push<void>(
                        MaterialPageRoute<void>(
                          builder: (_) => CallHistoryScreen(
                            user: widget.user,
                            onStartCalling: () {
                              setState(() => _navIndex = 1);
                            },
                          ),
                        ),
                      );
                    },
                  ),
                  IconButton(
                    tooltip: 'Settings',
                    icon: const Icon(Icons.settings_outlined),
                    onPressed: () {
                      Navigator.of(context).push<void>(
                        MaterialPageRoute<void>(
                          builder: (_) => SettingsScreen(
                            user: widget.user,
                            credits: credits,
                          ),
                        ),
                      );
                    },
                  ),
                ],
              ),
              body: Material(
                color: _navIndex == 0 ? Colors.transparent : AppTheme.darkBg,
                child: tabBody,
              ),
              bottomNavigationBar: BottomNavigationBar(
                currentIndex: _navIndex,
                onTap: (i) => setState(() => _navIndex = i),
                type: BottomNavigationBarType.fixed,
                backgroundColor: AppTheme.darkBg,
                selectedItemColor: AppColors.primary,
                unselectedItemColor:
                    Theme.of(context).colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
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

/// Premium promo strip with a looping 5:00 urgency countdown (visual retention hook).
class _ProOfferCountdownStrip extends StatefulWidget {
  const _ProOfferCountdownStrip({required this.onTap});

  final VoidCallback onTap;

  @override
  State<_ProOfferCountdownStrip> createState() =>
      _ProOfferCountdownStripState();
}

class _ProOfferCountdownStripState extends State<_ProOfferCountdownStrip> {
  Timer? _timer;
  static const int _loopSeconds = 5 * 60;
  late int _remainingSec;

  @override
  void initState() {
    super.initState();
    _remainingSec = _loopSeconds;
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() {
        if (_remainingSec <= 1) {
          _remainingSec = _loopSeconds;
        } else {
          _remainingSec -= 1;
        }
      });
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  String get _mmss {
    final m = _remainingSec ~/ 60;
    final s = _remainingSec % 60;
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: widget.onTap,
          child: Ink(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: const Color(0xFFFF7043).withValues(alpha: 0.5),
              ),
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  const Color(0xFFFF6B35).withValues(alpha: 0.22),
                  const Color(0xFFFF4500).withValues(alpha: 0.08),
                ],
              ),
            ),
            padding: const EdgeInsets.symmetric(
              horizontal: 14,
              vertical: 10,
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '🔥 Limited time offer on Pro',
                        style: GoogleFonts.inter(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          letterSpacing: -0.2,
                          color: Theme.of(context).colorScheme.onSurface,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Offer ends in $_mmss',
                        style: GoogleFonts.inter(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.2,
                          color: const Color(0xFFFF7043),
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(
                  Icons.chevron_right_rounded,
                  color: AppColors.primary.withValues(alpha: 0.95),
                  size: 22,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _DashboardHomeTab extends StatefulWidget {
  const _DashboardHomeTab({
    required this.user,
    required this.displayName,
    required this.theme,
    required this.rewardedAdBusy,
    required this.grantRewardPending,
    required this.cooldownRemaining,
    required this.adsToday,
    required this.dailyLimitReached,
    required this.credits,
    required this.assignedNumber,
    required this.numberLeaseExpiry,
    required this.numberPlanType,
    required this.lifetimeAdsWatched,
    required this.subscriptionTier,
    required this.outboundCallsTotal,
    required this.totalCallTalkSeconds,
    required this.adStreakCount,
    this.onDebugAddCredits,
    required this.onWatchRewardedAd,
    required this.onGoToDialer,
    required this.onOpenCallHistory,
    required this.walletGlow,
  });

  final User user;
  final String displayName;
  final ThemeData theme;
  final bool rewardedAdBusy;
  final bool grantRewardPending;
  final int cooldownRemaining;
  final int adsToday;
  final bool dailyLimitReached;
  /// Balance from parent [ValueNotifier] (single Firestore listener).
  final int credits;
  final ValueNotifier<String?> assignedNumber;
  final ValueNotifier<DateTime?> numberLeaseExpiry;
  final ValueNotifier<String?> numberPlanType;
  final ValueNotifier<int> lifetimeAdsWatched;
  final ValueNotifier<String> subscriptionTier;
  final ValueNotifier<int> outboundCallsTotal;
  final ValueNotifier<int> totalCallTalkSeconds;
  final ValueNotifier<int> adStreakCount;
  final Future<void> Function()? onDebugAddCredits;
  final Future<void> Function() onWatchRewardedAd;
  final VoidCallback onGoToDialer;
  final VoidCallback onOpenCallHistory;
  final Animation<double> walletGlow;

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
    if (isPro) {
      await Navigator.of(context).pushNamed<void>(
        NumberSelectionScreen.routeName,
        arguments: NumberSelectionRouteArgs(
          userUid: widget.user.uid,
          userCredits: widget.credits,
        ),
      );
      return;
    }
    final minAds = CreditsPolicy.assignNumberMinAdsWatched;
    final minCr = CreditsPolicy.assignNumberMinCredits;
    if (widget.lifetimeAdsWatched.value < minAds &&
        widget.credits < minCr) {
      return;
    }
    setState(() => _assignNumberBusy = true);
    try {
      await runAssignUsNumberFlow(
        context,
        autoPickFirstNumber: false,
        onSuccess: (r) {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                r.alreadyAssigned
                    ? 'Your line: ${r.assignedNumber}'
                    : 'Your number is ready! ${r.assignedNumber}',
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

  Future<void> _onGetFreeNumber() async {
    if (_assignNumberBusy) return;
    if (widget.subscriptionTier.value == 'pro') return;
    final minAds = CreditsPolicy.assignNumberMinAdsWatched;
    final minCr = CreditsPolicy.assignNumberMinCredits;
    if (widget.lifetimeAdsWatched.value < minAds && widget.credits < minCr) {
      return;
    }
    setState(() => _assignNumberBusy = true);
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => PopScope(
        canPop: false,
        child: AlertDialog(
          content: Row(
            children: [
              const SizedBox(
                width: 28,
                height: 28,
                child: CircularProgressIndicator(strokeWidth: 2.5),
              ),
              const SizedBox(width: 20),
              Expanded(
                child: Text(
                  'Assigning your number…',
                  style: GoogleFonts.inter(fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    try {
      final r = await AssignFreeNumberService.instance.requestAssignFreeNumber();
      if (mounted) Navigator.of(context, rootNavigator: true).pop();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            r.alreadyAssigned
                ? 'Your line: ${r.assignedNumber}'
                : 'Your number is ready! ${r.assignedNumber}',
            style: GoogleFonts.inter(fontWeight: FontWeight.w600),
          ),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } on AssignNumberException catch (e) {
      if (mounted) Navigator.of(context, rootNavigator: true).pop();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e.message, style: GoogleFonts.inter()),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (e) {
      if (mounted) Navigator.of(context, rootNavigator: true).pop();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('$e', style: GoogleFonts.inter()),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } finally {
      if (mounted) setState(() => _assignNumberBusy = false);
    }
  }

  void _onChangeNumberComingSoon() {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Number changes are coming soon.',
          style: GoogleFonts.inter(fontWeight: FontWeight.w600),
        ),
        behavior: SnackBarBehavior.floating,
      ),
    );
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
            ListView(
          padding: EdgeInsets.fromLTRB(
            16,
            16,
            16,
            kDebugMode ? 100 : 28,
          ),
          children: [
            ValueListenableBuilder<String>(
              valueListenable: widget.subscriptionTier,
              builder: (context, tier, _) {
                final low = tier != 'pro' &&
                    widget.credits <
                        CreditsPolicy.lowCreditWarningThreshold;
                return Padding(
                  padding: EdgeInsets.only(bottom: low ? 14 : 0),
                  child: LowCreditNudge(
                    credits: widget.credits,
                    isPremium: tier == 'pro',
                    onWatchAd: widget.onWatchRewardedAd,
                  ),
                );
              },
            ),
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
                    backgroundColor: (Theme.of(context).cardTheme.color ?? Theme.of(context).colorScheme.surface),
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
                          color: Theme.of(context).colorScheme.onSurface,
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
                            color: Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ],
                  ),
                ),
                ValueListenableBuilder<String>(
                  valueListenable: widget.subscriptionTier,
                  builder: (context, tier, _) {
                    final isPro = tier.toLowerCase() == 'pro';
                    return _LightningWalletPill(
                      credits: widget.credits,
                      isPro: isPro,
                      onDebugLongPress: widget.onDebugAddCredits,
                      walletGlow: widget.walletGlow,
                    );
                  },
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
                            ? LinearGradient(
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                                colors: [
                                  AppTheme.neonGreen,
                                  AppColors.darkBackgroundDeep,
                                  AppTheme.darkBg,
                                ],
                                stops: const [0.0, 0.55, 1.0],
                              )
                            : null,
                        color: isPro ? null : (Theme.of(context).cardTheme.color ?? Theme.of(context).colorScheme.surface),
                        border: Border.all(
                          color: isPro
                              ? Colors.transparent
                              : Theme.of(context).colorScheme.onSurfaceVariant.withValues(alpha: 0.2),
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
                                : Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            'Current plan: ${isPro ? 'Pro' : 'Free'}',
                            style: GoogleFonts.inter(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: isPro
                                  ? Colors.white
                                  : Theme.of(context).colorScheme.onSurface,
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
                if (tier == 'pro') return const SizedBox.shrink();
                return _ProOfferCountdownStrip(
                  onTap: () {
                    Navigator.of(context).push<void>(
                      SubscriptionScreen.createRoute(),
                    );
                  },
                );
              },
            ),
            ValueListenableBuilder<String>(
              valueListenable: widget.subscriptionTier,
              builder: (context, tier, _) {
                if (tier == 'pro') return const SizedBox.shrink();
                return Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: AppColors.primary.withValues(alpha: 0.28),
                      ),
                      color: AppColors.primary.withValues(alpha: 0.07),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 12,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '🎁 Watch Ad → Get FREE Calling Time',
                            style: GoogleFonts.inter(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              height: 1.4,
                              color: Theme.of(context).colorScheme.onSurface,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            '🚀 Go Pro → Call ANYONE Unlimited (No Ads)',
                            style: GoogleFonts.inter(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              height: 1.4,
                              color: Theme.of(context).colorScheme.onSurface,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
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
                  return ValueListenableBuilder<int>(
                    valueListenable: widget.adStreakCount,
                    builder: (context, streak, _) {
                      return _SimpleAdRewardCard(
                        rewardedAdBusy: widget.rewardedAdBusy,
                        grantRewardPending: widget.grantRewardPending,
                        cooldownRemaining: widget.cooldownRemaining,
                        dailyLimitReached: widget.dailyLimitReached,
                        adsToday: widget.adsToday,
                        credits: widget.credits,
                        adStreakDays: streak,
                        onEarn: widget.onWatchRewardedAd,
                      );
                    },
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
                                    onGetFreeNumber:
                                        tier == 'pro' ? null : _onGetFreeNumber,
                                    onChangeNumber: tier == 'pro'
                                        ? _onChangeNumberComingSoon
                                        : null,
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
                return ValueListenableBuilder<int>(
                  valueListenable: widget.outboundCallsTotal,
                  builder: (context, callsMade, _) {
                    return ValueListenableBuilder<int>(
                      valueListenable: widget.totalCallTalkSeconds,
                      builder: (context, talkSec, _) {
                        final talkMin = talkSec / 60.0;
                        return Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: _DashboardStatCard(
                                icon: Icons.call_made_rounded,
                                label: 'Calls made',
                                value: '$callsMade',
                                caption: 'All time',
                                animatedValue: true,
                              ),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: _DashboardStatCard(
                                icon: Icons.timer_outlined,
                                label: 'Minutes',
                                value: isPro
                                    ? 'Unlimited'
                                    : talkMin.toStringAsFixed(1),
                                caption: isPro
                                    ? 'Unlimited calling (Pro)'
                                    : 'Talk time (completed)',
                                animatedValue: !isPro,
                              ),
                            ),
                          ],
                        );
                      },
                    );
                  },
                );
              },
            ),
            const SizedBox(height: 22),
            _RecentActivitySection(
              user: widget.user,
              onOpenDialer: widget.onGoToDialer,
              onSeeAllHistory: widget.onOpenCallHistory,
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
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
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
                      color: Theme.of(context).colorScheme.onSurface,
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
                    color: Theme.of(context).colorScheme.onSurface,
                    letterSpacing: -0.5,
                  ),
                ),
          const SizedBox(height: 6),
          Text(
            caption,
            style: GoogleFonts.inter(
              fontSize: 11,
              fontWeight: FontWeight.w500,
              color: Theme.of(context).colorScheme.onSurfaceVariant.withValues(alpha: 0.85),
            ),
          ),
        ],
      ),
    );
  }
}

class _RecentActivitySection extends StatelessWidget {
  const _RecentActivitySection({
    required this.user,
    required this.onOpenDialer,
    required this.onSeeAllHistory,
  });

  final User user;
  final VoidCallback onOpenDialer;
  final VoidCallback onSeeAllHistory;

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
                color: Theme.of(context).colorScheme.onSurface,
              ),
            ),
            TextButton(
              onPressed: onSeeAllHistory,
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
        StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: FirestoreUserService.watchCallHistory(user.uid, limit: 5),
          builder: (context, snap) {
            if (snap.hasError) {
              return _RecentActivityShell(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(
                    'Could not load recents.',
                    style: GoogleFonts.inter(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              );
            }
            if (snap.connectionState == ConnectionState.waiting && !snap.hasData) {
              return const _RecentActivityShell(
                child: Padding(
                  padding: EdgeInsets.all(24),
                  child: Center(
                    child: SizedBox(
                      width: 28,
                      height: 28,
                      child: CircularProgressIndicator(strokeWidth: 2.5),
                    ),
                  ),
                ),
              );
            }
            final docs = snap.data?.docs ?? [];
            if (docs.isEmpty) {
              return _RecentActivityShell(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
                  child: Column(
                    children: [
                      Icon(
                        Icons.history_rounded,
                        size: 40,
                        color: Theme.of(context)
                            .colorScheme
                            .onSurfaceVariant
                            .withValues(alpha: 0.45),
                      ),
                      const SizedBox(height: 14),
                      Text(
                        'No calls yet',
                        textAlign: TextAlign.center,
                        style: GoogleFonts.montserrat(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: Theme.of(context).colorScheme.onSurface,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Completed calls appear here after each call ends.',
                        textAlign: TextAlign.center,
                        style: GoogleFonts.montserrat(
                          fontSize: 13,
                          height: 1.4,
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
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
              );
            }

            return _RecentActivityShell(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
                child: Column(
                  children: [
                    for (var i = 0; i < docs.length; i++) ...[
                      if (i > 0) const SizedBox(height: 4),
                      _DashboardRecentCallTile(data: docs[i].data()),
                    ],
                  ],
                ),
              ),
            );
          },
        ),
      ],
    );
  }
}

class _RecentActivityShell extends StatelessWidget {
  const _RecentActivityShell({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: (Theme.of(context).cardTheme.color ?? Theme.of(context).colorScheme.surface)
            .withValues(alpha: 0.88),
        borderRadius: BorderRadius.circular(AppTheme.radiusLg),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.06),
        ),
      ),
      child: child,
    );
  }
}

class _DashboardRecentCallTile extends StatelessWidget {
  const _DashboardRecentCallTile({required this.data});

  final Map<String, dynamic> data;

  @override
  Widget build(BuildContext context) {
    final durationSec = data['durationSeconds'];
    final sec = durationSec is num ? durationSec.toInt() : 0;
    final settled = data['settledAt'] is Timestamp
        ? data['settledAt'] as Timestamp
        : null;
    final outgoing = CallLogFormat.isOutgoingFromDocument(data);
    final labels = CallLogFormat.callHistoryLabels(data, outgoing);
    final display = CallLogFormat.prettyDisplayNumber(labels.primary);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
      child: Row(
        children: [
          Icon(
            Icons.call_made_rounded,
            size: 20,
            color: AppColors.primary.withValues(alpha: 0.9),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  display,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.inter(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: Theme.of(context).colorScheme.onSurface,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '${CallLogFormat.formatSettledDate(settled)} · ${CallLogFormat.formatClockTime(settled)}',
                  style: GoogleFonts.inter(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          Text(
            CallLogFormat.formatDurationMmSs(sec),
            style: GoogleFonts.jetBrainsMono(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: Theme.of(context).colorScheme.onSurface,
            ),
          ),
        ],
      ),
    );
  }
}

/// Glowing credits badge — balance (debug long-press adds credits).
class _LightningWalletPill extends StatelessWidget {
  const _LightningWalletPill({
    required this.credits,
    this.isPro = false,
    this.onDebugLongPress,
    required this.walletGlow,
  });

  final int credits;
  final bool isPro;
  final Future<void> Function()? onDebugLongPress;
  final Animation<double> walletGlow;

  @override
  Widget build(BuildContext context) {
    final neon = AppColors.primary;
    final creditStyle = GoogleFonts.poppins(
      fontSize: 18,
      fontWeight: FontWeight.w700,
      height: 1.05,
      color: Theme.of(context).colorScheme.onSurface,
      letterSpacing: -0.4,
      shadows: [
        Shadow(
          color: neon.withValues(alpha: 0.35),
          blurRadius: 10,
        ),
      ],
    );
    final Widget creditValue = isPro
        ? Text('Unlimited', style: creditStyle)
        : _AnimatedIntText(
            value: credits,
            style: creditStyle,
          );
    return AnimatedBuilder(
      animation: walletGlow,
      builder: (context, child) {
        final g = walletGlow.value.clamp(0.0, 1.0);
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
                  color: Color.lerp(
                        Colors.white.withValues(alpha: 0.22),
                        AppTheme.neonGreen.withValues(alpha: 0.85),
                        g,
                      ) ??
                      Colors.white.withValues(alpha: 0.22),
                  width: 0.5 + g * 1.2,
                ),
                boxShadow: [
                  BoxShadow(
                    color: neon.withValues(alpha: 0.45),
                    blurRadius: 8,
                    spreadRadius: 2,
                    offset: const Offset(0, 2),
                  ),
                  BoxShadow(
                    color: AppTheme.neonGreen.withValues(alpha: 0.35 * g),
                    blurRadius: 8 + 20 * g,
                    spreadRadius: 2 * g,
                  ),
                ],
              ),
              child: child,
            ),
          ),
        );
      },
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.bolt_rounded,
            color: neon.withValues(alpha: 0.98),
            size: 20,
          ),
          const SizedBox(width: 6),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                isPro ? 'CALLING' : 'CREDITS',
                style: GoogleFonts.inter(
                  fontSize: 9,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.2,
                  color: Theme.of(context)
                      .colorScheme
                      .onSurfaceVariant
                      .withValues(alpha: 0.85),
                ),
              ),
              creditValue,
            ],
          ),
        ],
      ),
    );
  }
}

/// Rewarded ads: one tap → server grants [CreditsPolicy.creditsPerRewardedAd] credits each time.
class _SimpleAdRewardCard extends StatelessWidget {
  const _SimpleAdRewardCard({
    required this.rewardedAdBusy,
    required this.grantRewardPending,
    required this.cooldownRemaining,
    required this.dailyLimitReached,
    required this.adsToday,
    required this.credits,
    required this.adStreakDays,
    required this.onEarn,
  });

  final bool rewardedAdBusy;
  final bool grantRewardPending;
  final int cooldownRemaining;
  final bool dailyLimitReached;
  final int adsToday;
  final int credits;
  final int adStreakDays;
  final Future<void> Function() onEarn;

  @override
  Widget build(BuildContext context) {
    final maxPerDay = CreditsPolicy.maxRewardedAdsPerDay;
    final remaining = max(0, maxPerDay - adsToday);
    final canTap =
        !rewardedAdBusy && !dailyLimitReached && cooldownRemaining <= 0;

    return GlassPanel(
      borderRadius: AppTheme.radiusLg,
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(
                Icons.play_circle_outline_rounded,
                color: AppColors.primary.withValues(alpha: 0.95),
                size: 26,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Earn credits',
                  style: GoogleFonts.inter(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.8,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Each rewarded ad adds +${CreditsPolicy.creditsPerRewardedAd} credits.',
            style: GoogleFonts.inter(
              fontSize: 13,
              fontWeight: FontWeight.w500,
              height: 1.35,
              color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.92),
            ),
          ),
          if (adStreakDays > 0) ...[
            const SizedBox(height: 8),
            Text(
              'Day streak: $adStreakDays — bonuses at ${CreditsPolicy.adStreakMilestoneDays.join(', ')} days',
              style: GoogleFonts.inter(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                height: 1.35,
                color: AppTheme.neonGreen.withValues(alpha: 0.88),
              ),
            ),
          ],
          if (cooldownRemaining > 0 && !dailyLimitReached) ...[
            const SizedBox(height: 8),
            Text(
              'Wait ${cooldownRemaining}s before the next ad.',
              style: GoogleFonts.inter(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: AppColors.primary.withValues(alpha: 0.9),
              ),
            ),
          ],
          if (credits == 0 && canTap) ...[
            const SizedBox(height: 10),
            Text(
              'Start here — your balance is 0',
              style: GoogleFonts.inter(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: AppTheme.neonGreen.withValues(alpha: 0.95),
              ),
            ),
          ],
          const SizedBox(height: 16),
          FilledButton(
            onPressed: canTap ? () => onEarn() : null,
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: AppColors.onPrimary,
              disabledBackgroundColor:
                  (Theme.of(context).cardTheme.color ?? Theme.of(context).colorScheme.surface)
                      .withValues(alpha: 0.7),
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
            child: rewardedAdBusy
                ? SizedBox(
                    height: 22,
                    width: 22,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.5,
                      color: AppColors.onPrimary.withValues(alpha: 0.95),
                    ),
                  )
                : Text(
                    'Watch Ad → Earn Credits',
                    style: GoogleFonts.inter(
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
          ),
          const SizedBox(height: 10),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 200),
            child: grantRewardPending
                ? Row(
                    key: const ValueKey<String>('grant'),
                    children: [
                      SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: AppTheme.neonGreen.withValues(alpha: 0.95),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          RewardAdFeedback.processingReward,
                          style: GoogleFonts.inter(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            height: 1.3,
                            color: AppTheme.neonGreen.withValues(alpha: 0.95),
                          ),
                        ),
                      ),
                    ],
                  )
                : Text(
                    key: const ValueKey<String>('remaining'),
                    RewardAdFeedback.adsRemainingToday(remaining),
                    style: GoogleFonts.inter(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      height: 1.35,
                      color: Theme.of(context)
                          .colorScheme
                          .onSurfaceVariant
                          .withValues(alpha: 0.9),
                    ),
                  ),
          ),
        ],
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
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                AppTheme.neonGreen.withValues(alpha: 0.92),
                AppTheme.neonGreen,
                AppColors.darkBackgroundDeep,
                AppTheme.darkBg,
              ],
              stops: const [0.0, 0.25, 0.55, 1.0],
            ),
            boxShadow: [
              BoxShadow(
                color: AppTheme.neonGreen.withValues(alpha: 0.4),
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
                      DecoratedBox(
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: Colors.white.withValues(alpha: 0.2),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.2),
                              blurRadius: 8,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(4),
                          child: SizedBox(
                            width: 40,
                            height: 40,
                            child: Lottie.asset(
                              AppTheme.lottieMoney,
                              fit: BoxFit.contain,
                              repeat: true,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Go Pro',
                              style: GoogleFonts.inter(
                                fontSize: 17,
                                fontWeight: FontWeight.w800,
                                color: Colors.white,
                                letterSpacing: -0.3,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              'Unlimited calling · No ads · US number · Bonus credits',
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
                color: AppTheme.neonGreen.withValues(alpha: 0.95),
                size: 22,
              ),
              const SizedBox(width: 10),
              Text(
                'You’re on TalkFree Pro',
                style: GoogleFonts.inter(
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                  color: Theme.of(context).colorScheme.onSurface,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            'You are saving ${CreditsPolicy.creditsSavedPerMinuteVsFree} credits per minute',
            style: GoogleFonts.inter(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              height: 1.35,
              color: AppTheme.neonGreen.withValues(alpha: 0.95),
            ),
          ),
          const SizedBox(height: 12),
          _proLine(context, 'Ad-free experience'),
          _proLine(context, 'Bonus credits & lower call rates'),
          _proLine(context, 'Priority line quality'),
        ],
      ),
    );
  }

  static Widget _proLine(BuildContext context, String t) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.check_circle_rounded,
            size: 18,
            color: AppTheme.neonGreen.withValues(alpha: 0.95),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              t,
              style: GoogleFonts.inter(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                height: 1.35,
                color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.92),
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

/// Animated handset for the virtual-number row; lock / ready badges when no line yet.
class _VirtualNumberLottieBadge extends StatelessWidget {
  const _VirtualNumberLottieBadge({
    required this.hasNumber,
    required this.isPremium,
  });

  final bool hasNumber;
  final bool isPremium;

  @override
  Widget build(BuildContext context) {
    final locked = !hasNumber && !isPremium;
    final dim = Theme.of(context)
        .colorScheme
        .onSurfaceVariant
        .withValues(alpha: 0.78);

    return SizedBox(
      width: 48,
      height: 48,
      child: Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.center,
        children: [
          Opacity(
            opacity: locked ? 0.48 : 1,
            child: Lottie.asset(
              AppTheme.lottiePhoneCall,
              fit: BoxFit.contain,
              repeat: true,
            ),
          ),
          if (locked)
            Positioned(
              right: -2,
              bottom: -2,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: AppTheme.darkBg.withValues(alpha: 0.94),
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: dim.withValues(alpha: 0.45),
                  ),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(2),
                  child: Icon(Icons.lock_rounded, size: 13, color: dim),
                ),
              ),
            )
          else if (!hasNumber && isPremium)
            Positioned(
              right: -2,
              bottom: -2,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: AppTheme.darkBg.withValues(alpha: 0.94),
                  shape: BoxShape.circle,
                ),
                child: Padding(
                  padding: const EdgeInsets.all(2),
                  child: Icon(
                    Icons.check_circle_outline_rounded,
                    size: 14,
                    color: AppColors.primary,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
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
    this.onGetFreeNumber,
    this.onChangeNumber,
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
  /// Free tier: auto-assign first US number (server POST `/assign-free-number`).
  final Future<void> Function()? onGetFreeNumber;
  /// Premium: optional “change number” (stub until server supports swap).
  final VoidCallback? onChangeNumber;
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
    final minCredits = CreditsPolicy.assignNumberMinCredits;
    final canUnlock = widget.isPremium ||
        widget.adsWatchedCount >= minAds ||
        widget.credits >= minCredits;

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
                  _VirtualNumberLottieBadge(
                    hasNumber: hasNumber,
                    isPremium: widget.isPremium,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'VIRTUAL NUMBER',
                      style: GoogleFonts.inter(
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 2,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
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
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
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
                                        color: Theme.of(context).colorScheme.onSurface,
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
                                      Icons.check_circle_rounded,
                                      size: 15,
                                      color: AppColors.primary,
                                    ),
                                    const SizedBox(width: 4),
                                    Text(
                                      'Active',
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
                          if (widget.onChangeNumber != null) ...[
                            const SizedBox(height: 10),
                            Center(
                              child: TextButton(
                                onPressed: widget.onChangeNumber,
                                child: Text(
                                  'Change Number',
                                  style: GoogleFonts.inter(
                                    fontWeight: FontWeight.w700,
                                    fontSize: 13,
                                    color: AppTheme.neonGreen,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                ),
                const SizedBox(height: 10),
                Text(
                  'SMS and calls route to your Inbox.',
                  style: GoogleFonts.inter(
                    fontSize: 12,
                    height: 1.35,
                    color: Theme.of(context).colorScheme.onSurfaceVariant.withValues(alpha: 0.88),
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
                              color: Theme.of(context).colorScheme.onSurface,
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
                              color: Theme.of(context).colorScheme.onSurfaceVariant.withValues(
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
                      ? 'Choose your number below — included with Pro.'
                      : canUnlock
                          ? 'Get an auto-picked line free, choose one with credits, or go Pro.'
                          : 'Watch $minAds ads or reach $minCredits credits — your progress:',
                  style: GoogleFonts.inter(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    height: 1.45,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
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
                            color: AppTheme.neonGreen.withValues(alpha: 0.95),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: LinearProgressIndicator(
                      value: min(1, widget.credits / minCredits),
                      minHeight: 8,
                      backgroundColor: Colors.white.withValues(alpha: 0.08),
                      color: AppTheme.neonGreen.withValues(alpha: 0.55),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '${widget.credits.clamp(0, minCredits)} / $minCredits credits',
                    style: GoogleFonts.poppins(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: AppTheme.neonGreen.withValues(alpha: 0.85),
                    ),
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
                          color: AppTheme.neonGreen,
                        ),
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 16),
                if (!widget.isPremium &&
                    canUnlock &&
                    widget.onGetFreeNumber != null) ...[
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton(
                      onPressed: widget.assigning
                          ? null
                          : () => unawaited(widget.onGetFreeNumber!()),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.primary,
                        side: BorderSide(
                          color: AppColors.primary.withValues(alpha: 0.65),
                        ),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ),
                      child: Text(
                        '🎁 Get Free Number',
                        style: GoogleFonts.inter(
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                ],
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: (!canUnlock || widget.assigning)
                        ? null
                        : () => unawaited(widget.onUnlock()),
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      disabledBackgroundColor:
                          (Theme.of(context).cardTheme.color ?? Theme.of(context).colorScheme.surface).withValues(alpha: 0.65),
                      foregroundColor: AppColors.onPrimary,
                      disabledForegroundColor:
                          Theme.of(context).colorScheme.onSurfaceVariant.withValues(alpha: 0.55),
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
                                'Please wait…',
                                style: GoogleFonts.inter(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ],
                          )
                        : Text(
                            widget.isPremium
                                ? 'Choose your number'
                                : 'Choose number (credits)',
                            style: GoogleFonts.inter(
                              fontSize: 15,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                  ),
                ),
                if (!widget.isPremium && canUnlock) ...[
                  const SizedBox(height: 6),
                  Align(
                    alignment: Alignment.center,
                    child: TextButton(
                      onPressed: widget.onGetPremium,
                      child: Text(
                        'Get Premium — instant number',
                        style: GoogleFonts.inter(
                          fontWeight: FontWeight.w700,
                          fontSize: 13,
                          color: AppTheme.neonGreen,
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ],
          ),
        ),
    );
  }
}

import 'dart:async' show StreamSubscription, Timer, unawaited;
import 'dart:math' as math;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show immutable, kDebugMode;
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../config/credits_policy.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import '../theme/neon_tokens.dart';
import '../theme/system_ui.dart';
import '../services/ad_service.dart';
import '../utils/reward_ad_feedback.dart';
import '../widgets/engagement_overlays.dart';
import '../widgets/soft_pulse.dart';
import '../services/firestore_user_service.dart';
import '../services/grant_reward_service.dart';
import '../services/reward_sound_service.dart';
import 'call_history_screen.dart';
import 'dialer_screen.dart';
import 'inbox_screen.dart';
import 'settings_screen.dart';
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

String _firstName(String displayName) {
  final t = displayName.trim();
  if (t.isEmpty) return 'there';
  return t.split(RegExp(r'\s+')).first;
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
      duration: const Duration(milliseconds: 420),
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
  /// Server line status (`active` | `expired`); see [FirestoreUserService.numberLineStatusFromUserData].
  final ValueNotifier<String?> _numberLineStatus =
      ValueNotifier<String?>(null);
  /// Server `number_tier`: `normal` | `vip` | `premium`.
  final ValueNotifier<String?> _numberTier =
      ValueNotifier<String?>(null);
  final ValueNotifier<String?> _numberPlanType = ValueNotifier<String?>(null);
  /// Banked rewarded ads toward POST `/renew-number` (mode `ads`).
  final ValueNotifier<int> _numberRenewAdProgress = ValueNotifier<int>(0);
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
    final cool = math.max(t.cooldownRemaining, _localAdCooldownSeconds);
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
    final lineSt = FirestoreUserService.numberLineStatusFromUserData(d);
    if (_numberLineStatus.value != lineSt) {
      _numberLineStatus.value = lineSt;
    }
    final nt = FirestoreUserService.numberTierFromUserData(d);
    if (_numberTier.value != nt) {
      _numberTier.value = nt;
    }
    final planT = FirestoreUserService.numberPlanTypeFromUserData(d);
    if (_numberPlanType.value != planT) {
      _numberPlanType.value = planT;
    }
    final renewP = FirestoreUserService.numberRenewAdProgressFromUserData(d);
    if (_numberRenewAdProgress.value != renewP) {
      _numberRenewAdProgress.value = renewP;
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
    _numberLineStatus.dispose();
    _numberTier.dispose();
    _numberPlanType.dispose();
    _numberRenewAdProgress.dispose();
    _outboundCallsTotal.dispose();
    _totalCallTalkSeconds.dispose();
    _adStreakCount.dispose();
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
              welcomeFirstAd: result.firstLifetimeAd,
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
                    numberLineStatus: _numberLineStatus,
                    numberTier: _numberTier,
                    numberPlanType: _numberPlanType,
                    numberRenewAdProgress: _numberRenewAdProgress,
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
                            onWatchAd: () => _onWatchRewardedAd(
                              cooldownRemaining,
                              dailyLimitReached,
                            ),
                          ),
                        ),
                      );
                    },
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
                        Navigator.of(context).push<void>(
                          MaterialPageRoute<void>(
                            builder: (_) => VirtualNumberScreen(
                              userUid: widget.user.uid,
                              userCredits: credits,
                              onWatchRewardedAd: () => _onWatchRewardedAd(
                                cooldownRemaining,
                                dailyLimitReached,
                              ),
                            ),
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
                            onWatchAd: () => _onWatchRewardedAd(
                              cooldownRemaining,
                              dailyLimitReached,
                            ),
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
                            isPremium:
                                _subscriptionTier.value.toLowerCase() == 'pro',
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
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.1),
              ),
              color: AppColors.cardDark,
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
                        'Limited time offer',
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
                          fontWeight: FontWeight.w600,
                          letterSpacing: 0.1,
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(
                  Icons.chevron_right_rounded,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
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
    required this.numberLineStatus,
    required this.numberTier,
    required this.numberPlanType,
    required this.numberRenewAdProgress,
    required this.lifetimeAdsWatched,
    required this.subscriptionTier,
    required this.outboundCallsTotal,
    required this.totalCallTalkSeconds,
    required this.adStreakCount,
    this.onDebugAddCredits,
    required this.onWatchRewardedAd,
    required this.onGoToDialer,
    required this.onOpenCallHistory,
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
  final ValueNotifier<String?> numberLineStatus;
  final ValueNotifier<String?> numberTier;
  final ValueNotifier<String?> numberPlanType;
  final ValueNotifier<int> numberRenewAdProgress;
  final ValueNotifier<int> lifetimeAdsWatched;
  final ValueNotifier<String> subscriptionTier;
  final ValueNotifier<int> outboundCallsTotal;
  final ValueNotifier<int> totalCallTalkSeconds;
  final ValueNotifier<int> adStreakCount;
  final Future<void> Function()? onDebugAddCredits;
  final Future<void> Function() onWatchRewardedAd;
  final VoidCallback onGoToDialer;
  final VoidCallback onOpenCallHistory;

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
            Positioned.fill(child: DecoratedBox(decoration: NeonTokens.scaffoldAmbient())),
            ListView(
          padding: EdgeInsets.fromLTRB(
            16,
            16,
            16,
            kDebugMode ? 100 : 28,
          ),
          children: [
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  if (widget.user.photoURL != null)
                    CircleAvatar(
                      radius: 26,
                      backgroundImage: NetworkImage(widget.user.photoURL!),
                    )
                  else
                    CircleAvatar(
                      radius: 26,
                      backgroundColor: AppColors.surfaceDark,
                      foregroundColor: AppColors.primary,
                      child: Text(
                        widget.displayName.isNotEmpty
                            ? widget.displayName[0].toUpperCase()
                            : '?',
                        style: GoogleFonts.inter(
                          fontWeight: FontWeight.w800,
                          fontSize: 20,
                        ),
                      ),
                    ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Hey ${_firstName(widget.displayName)}',
                      style: GoogleFonts.inter(
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.35,
                        color: Theme.of(context).colorScheme.onSurface,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
            ValueListenableBuilder<String>(
              valueListenable: widget.subscriptionTier,
              builder: (context, tier, _) {
                final isPro = tier.toLowerCase() == 'pro';
                final canTapAd = !widget.rewardedAdBusy &&
                    !widget.dailyLimitReached &&
                    widget.cooldownRemaining <= 0;
                final remaining =
                    math.max(0, CreditsPolicy.maxRewardedAdsPerDay - widget.adsToday);
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _HomeCreditHero(
                      credits: widget.credits,
                      isPro: isPro,
                      onDebugLongPress: widget.onDebugAddCredits,
                    ),
                    if (!isPro) ...[
                      const SizedBox(height: 12),
                      SoftPulse(
                        enabled: canTapAd &&
                            !widget.grantRewardPending &&
                            !widget.rewardedAdBusy,
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(16),
                            boxShadow: canTapAd && !widget.grantRewardPending
                                ? NeonTokens.glowPrimary(0.85)
                                : null,
                          ),
                          child: FilledButton(
                            onPressed: canTapAd && !widget.grantRewardPending
                                ? widget.onWatchRewardedAd
                                : null,
                            style: FilledButton.styleFrom(
                              backgroundColor: AppColors.primary,
                              foregroundColor: AppColors.onPrimary,
                              disabledBackgroundColor: (Theme.of(context)
                                          .cardTheme
                                          .color ??
                                      Theme.of(context).colorScheme.surface)
                                  .withValues(alpha: 0.65),
                              padding: const EdgeInsets.symmetric(
                                vertical: 14,
                                horizontal: 16,
                              ),
                              minimumSize: const Size.fromHeight(56),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16),
                              ),
                              elevation: 0,
                            ),
                            child: widget.rewardedAdBusy
                                ? SizedBox(
                                    height: 22,
                                    width: 22,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2.5,
                                      color: AppColors.onPrimary
                                          .withValues(alpha: 0.95),
                                    ),
                                  )
                                : Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Text(
                                        '🎁 Get FREE Calling Time',
                                        textAlign: TextAlign.center,
                                        style: GoogleFonts.inter(
                                          fontSize: 16,
                                          fontWeight: FontWeight.w800,
                                          height: 1.2,
                                          letterSpacing: 0.2,
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        '+${CreditsPolicy.creditsPerRewardedAd} credits',
                                        textAlign: TextAlign.center,
                                        style: GoogleFonts.inter(
                                          fontSize: 12,
                                          fontWeight: FontWeight.w600,
                                          color: AppColors.onPrimary
                                              .withValues(alpha: 0.88),
                                        ),
                                      ),
                                    ],
                                  ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        '🚀 10,000+ users upgraded today',
                        textAlign: TextAlign.center,
                        style: GoogleFonts.inter(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          height: 1.35,
                          color: Theme.of(context)
                              .colorScheme
                              .onSurfaceVariant
                              .withValues(alpha: 0.85),
                        ),
                      ),
                      const SizedBox(height: 12),
                      _ProOfferCountdownStrip(
                        onTap: () {
                          Navigator.of(context).push<void>(
                            SubscriptionScreen.createRoute(),
                          );
                        },
                      ),
                      if (widget.grantRewardPending) ...[
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: AppColors.primary.withValues(alpha: 0.9),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                RewardAdFeedback.processingReward,
                                style: GoogleFonts.inter(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  color: Theme.of(context)
                                      .colorScheme
                                      .onSurfaceVariant,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                      if (widget.cooldownRemaining > 0 &&
                          !widget.dailyLimitReached) ...[
                        const SizedBox(height: 6),
                        Text(
                          'Wait ${widget.cooldownRemaining}s for next ad',
                          style: GoogleFonts.inter(
                            fontSize: 12,
                            color: Theme.of(context)
                                .colorScheme
                                .onSurfaceVariant,
                          ),
                        ),
                      ],
                      const SizedBox(height: 10),
                      OutlinedButton(
                        onPressed: () {
                          Navigator.of(context).push<void>(
                            SubscriptionScreen.createRoute(),
                          );
                        },
                        style: OutlinedButton.styleFrom(
                          foregroundColor:
                              Theme.of(context).colorScheme.onSurface,
                          side: BorderSide(
                            color: Colors.white.withValues(alpha: 0.2),
                          ),
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                        ),
                        child: Text(
                          'GO PRO → UNLIMITED',
                          style: GoogleFonts.inter(
                            fontWeight: FontWeight.w800,
                            fontSize: 15,
                            letterSpacing: 0.35,
                          ),
                        ),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        'You can watch ${CreditsPolicy.maxRewardedAdsPerDay} ads today · $remaining left',
                        textAlign: TextAlign.center,
                        style: GoogleFonts.inter(
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                          color: Theme.of(context)
                              .colorScheme
                              .onSurfaceVariant,
                        ),
                      ),
                      ValueListenableBuilder<int>(
                        valueListenable: widget.adStreakCount,
                        builder: (context, streak, _) {
                          if (streak <= 0) {
                            return const SizedBox.shrink();
                          }
                          final next = CreditsPolicy.nextStreakMilestoneAfter(streak);
                          final line = next == null
                              ? '🔥 Day $streak streak'
                              : '🔥 Day $streak streak → +${next.bonusCredits} bonus at day ${next.day}';
                          return Padding(
                            padding: const EdgeInsets.only(top: 10),
                            child: Text(
                              line,
                              textAlign: TextAlign.center,
                              style: GoogleFonts.inter(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                height: 1.35,
                                color: Theme.of(context).colorScheme.onSurface,
                              ),
                            ),
                          );
                        },
                      ),
                    ] else ...[
                      const SizedBox(height: 12),
                      Text(
                        'Pro active · unlimited calling',
                        style: GoogleFonts.inter(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ],
                );
              },
            ),
          ],
            ),
          ],
        );
      },
    );
  }
}

/// Large balance — biggest number on screen; glow reserved for CTAs (debug long-press adds credits).
class _HomeCreditHero extends StatelessWidget {
  const _HomeCreditHero({
    required this.credits,
    required this.isPro,
    this.onDebugLongPress,
  });

  final int credits;
  final bool isPro;
  final Future<void> Function()? onDebugLongPress;

  @override
  Widget build(BuildContext context) {
    final valueStyle = GoogleFonts.poppins(
      fontSize: isPro ? 40 : 64,
      fontWeight: FontWeight.w700,
      height: 1.0,
      letterSpacing: -2,
      color: AppColors.textOnDark,
    );
    final creditsWord = GoogleFonts.inter(
      fontSize: 17,
      fontWeight: FontWeight.w600,
      height: 1.2,
      color: Theme.of(context).colorScheme.onSurfaceVariant,
    );
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onLongPress:
            onDebugLongPress == null ? null : () => onDebugLongPress!(),
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.only(top: 4, bottom: 4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              if (isPro)
                Text('Unlimited', style: valueStyle)
              else ...[
                _AnimatedIntText(
                  value: credits,
                  style: valueStyle,
                ),
                const SizedBox(height: 4),
                Text('credits', style: creditsWord),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

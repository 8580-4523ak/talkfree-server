import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'dashboard_screen.dart';
import 'intro_screen.dart';
import 'login_screen.dart';

/// Persists after the first-launch value intro is completed.
const String kFirstLaunchIntroCompleteKey = 'talkfree_first_launch_intro_complete';

/// Root navigator: first launch → [TalkFreeValueIntroScreen] → [LoginScreen];
/// signed-in users → [DashboardScreen] on the dialer tab (no duplicate intro).
class TalkFreeRoot extends StatefulWidget {
  const TalkFreeRoot({super.key});

  @override
  State<TalkFreeRoot> createState() => _TalkFreeRootState();
}

class _TalkFreeRootState extends State<TalkFreeRoot> {
  bool _prefsReady = false;
  bool _firstIntroCompleted = false;
  StreamSubscription<User?>? _authSub;

  @override
  void initState() {
    super.initState();
    _authSub = FirebaseAuth.instance.authStateChanges().listen((_) {
      if (mounted) setState(() {});
    });
    unawaited(_loadPrefs());
  }

  @override
  void dispose() {
    _authSub?.cancel();
    super.dispose();
  }

  Future<void> _loadPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    var done = prefs.getBool(kFirstLaunchIntroCompleteKey) ?? false;
    if (!done) {
      final oldOnboarding = prefs.getBool('talkfree_onboarding_complete') ?? false;
      final oldValueIntro = prefs.getBool('talkfree_value_intro_complete') ?? false;
      done = oldOnboarding || oldValueIntro;
    }
    if (!mounted) return;
    setState(() {
      _firstIntroCompleted = done;
      _prefsReady = true;
    });
  }

  Future<void> _onIntroFinished() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(kFirstLaunchIntroCompleteKey, true);
    if (!mounted) return;
    setState(() => _firstIntroCompleted = true);
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;

    if (user != null) {
      return DashboardScreen(
        key: ValueKey<String>('dash_${user.uid}'),
        user: user,
        initialNavIndex: 1,
      );
    }

    if (!_prefsReady) {
      return const _RootSplash();
    }

    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 380),
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeInCubic,
      transitionBuilder: (Widget child, Animation<double> animation) {
        final curved = CurvedAnimation(
          parent: animation,
          curve: Curves.easeOutCubic,
          reverseCurve: Curves.easeInCubic,
        );
        return FadeTransition(
          opacity: curved,
          child: SlideTransition(
            position: Tween<Offset>(
              begin: const Offset(0, 0.028),
              end: Offset.zero,
            ).animate(curved),
            child: child,
          ),
        );
      },
      child: _firstIntroCompleted
          ? const KeyedSubtree(
              key: ValueKey<String>('route_login'),
              child: LoginScreen(),
            )
          : KeyedSubtree(
              key: const ValueKey<String>('route_intro'),
              child: TalkFreeValueIntroScreen(
                onDone: _onIntroFinished,
              ),
            ),
    );
  }
}

class _RootSplash extends StatelessWidget {
  const _RootSplash();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      backgroundColor: Color(0xFF040608),
      body: Center(
        child: SizedBox(
          width: 28,
          height: 28,
          child: CircularProgressIndicator(
            strokeWidth: 2.5,
            color: Color(0xFF00D084),
          ),
        ),
      ),
    );
  }
}

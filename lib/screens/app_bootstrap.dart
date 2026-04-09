import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'choose_plan_screen.dart';
import 'onboarding_screen.dart';
import 'splash/splash_screen.dart';
import '../auth_gate.dart';

enum _BootstrapStage { splash, onboarding, choosePlan, auth }

/// Splash → onboarding (first launch) → [AuthGate].
class AppBootstrap extends StatefulWidget {
  const AppBootstrap({super.key});

  @override
  State<AppBootstrap> createState() => _AppBootstrapState();
}

class _AppBootstrapState extends State<AppBootstrap> {
  _BootstrapStage _stage = _BootstrapStage.splash;

  @override
  void initState() {
    super.initState();
    _afterSplashDelay();
  }

  Future<void> _afterSplashDelay() async {
    await Future<void>.delayed(const Duration(milliseconds: 1500));
    if (!mounted) return;
    final prefs = await SharedPreferences.getInstance();
    final done = prefs.getBool('talkfree_onboarding_complete') ?? false;
    if (!mounted) return;
    setState(() {
      _stage = done ? _BootstrapStage.auth : _BootstrapStage.onboarding;
    });
  }

  void _onOnboardingCarouselComplete() {
    setState(() => _stage = _BootstrapStage.choosePlan);
  }

  Future<void> _onChoosePlanFinished(String useCaseKey) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('talkfree_use_case', useCaseKey);
    await prefs.setBool('talkfree_onboarding_complete', true);
    if (!mounted) return;
    setState(() => _stage = _BootstrapStage.auth);
  }

  @override
  Widget build(BuildContext context) {
    return switch (_stage) {
      _BootstrapStage.splash => const SplashScreen(showLoader: true),
      _BootstrapStage.onboarding => OnboardingScreen(
          onCarouselComplete: _onOnboardingCarouselComplete,
        ),
      _BootstrapStage.choosePlan => ChoosePlanScreen(
          onFinished: _onChoosePlanFinished,
        ),
      _BootstrapStage.auth => const AuthGate(),
    };
  }
}

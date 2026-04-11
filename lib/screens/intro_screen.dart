import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lottie/lottie.dart';

import '../widgets/premium_ios_dial_pad.dart';

/// Premium first-launch value intro (before login). Driven by [TalkFreeRoot].
const Color _neon = premiumDialCallGreen;

BoxDecoration _introSoftPanelDecoration() {
  return BoxDecoration(
    borderRadius: BorderRadius.circular(28),
    border: Border.all(
      color: _neon.withValues(alpha: 0.12),
    ),
    boxShadow: [
      BoxShadow(
        color: _neon.withValues(alpha: 0.11),
        blurRadius: 22,
        spreadRadius: -3,
      ),
      BoxShadow(
        color: Colors.black.withValues(alpha: 0.24),
        blurRadius: 20,
        offset: const Offset(0, 12),
      ),
    ],
    gradient: LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [
        Colors.white.withValues(alpha: 0.08),
        _neon.withValues(alpha: 0.035),
        Colors.white.withValues(alpha: 0.03),
      ],
    ),
  );
}

/// Bundled Lottie animations (calling / wallet / global map).
const String _lottieCalling = 'assets/lottie/intro_calling.json';
const String _lottieWallet = 'assets/lottie/intro_wallet.json';
const String _lottieGlobe = 'assets/lottie/intro_globe.json';

class TalkFreeValueIntroScreen extends StatefulWidget {
  const TalkFreeValueIntroScreen({
    super.key,
    required this.onDone,
  });

  final Future<void> Function() onDone;

  @override
  State<TalkFreeValueIntroScreen> createState() =>
      _TalkFreeValueIntroScreenState();
}

class _TalkFreeValueIntroScreenState extends State<TalkFreeValueIntroScreen>
    with TickerProviderStateMixin {
  final PageController _pageController = PageController();
  int _page = 0;

  late final AnimationController _ambient = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 14),
  )..repeat();

  late final AnimationController _gotItPulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1800),
  );

  late final Animation<double> _gotItScale = Tween<double>(
    begin: 1.0,
    end: 1.06,
  ).animate(CurvedAnimation(parent: _gotItPulse, curve: Curves.easeInOut));

  bool _finishing = false;

  @override
  void dispose() {
    _ambient.dispose();
    _gotItPulse.dispose();
    _pageController.dispose();
    super.dispose();
  }

  void _syncPulseWithPage() {
    if (_page == 2 && !_finishing) {
      if (!_gotItPulse.isAnimating) {
        _gotItPulse.repeat(reverse: true);
      }
    } else {
      _gotItPulse.stop();
    }
  }

  Future<void> _onStartCalling() async {
    if (_finishing) return;
    _gotItPulse.stop();
    setState(() => _finishing = true);
    await widget.onDone();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: AnimatedBuilder(
        animation: _ambient,
        builder: (context, child) {
          final t = _ambient.value;
          final blue = const Color(0xFF040A18);
          final blueMid = const Color(0xFF081424);
          final green = const Color(0xFF051210);
          final greenMid = const Color(0xFF061814);
          return Container(
            width: double.infinity,
            height: double.infinity,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment(
                  math.cos(t * math.pi * 2) * 0.35,
                  math.sin(t * math.pi * 2) * 0.25,
                ),
                end: Alignment(
                  -math.cos(t * math.pi * 2) * 0.4,
                  1.0 + math.sin(t * math.pi * 2) * 0.1,
                ),
                colors: [
                  Color.lerp(blue, green, (math.sin(t * math.pi * 2) * 0.5 + 0.5))!,
                  Color.lerp(blueMid, greenMid, (math.cos(t * math.pi * 2) * 0.5 + 0.5))!,
                  Color.lerp(const Color(0xFF050812), const Color(0xFF040E0C),
                      (math.sin(t * math.pi * 2 + 1.2) * 0.5 + 0.5))!,
                  Color.lerp(blue, green, (math.cos(t * math.pi * 2 + 0.7) * 0.5 + 0.5))!,
                ],
                stops: const [0.0, 0.38, 0.68, 1.0],
              ),
            ),
            child: child,
          );
        },
        child: Stack(
          children: [
            Positioned(
              top: -120,
              right: -80,
              child: _GlowBlob(
                color: _neon.withValues(alpha: 0.1),
                size: 280,
              ),
            ),
            Positioned(
              bottom: -60,
              left: -40,
              child: _GlowBlob(
                color: _neon.withValues(alpha: 0.06),
                size: 220,
              ),
            ),
            SafeArea(
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'TalkFree',
                          style: GoogleFonts.inter(
                            fontSize: 22,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.6,
                            color: Colors.white.withValues(alpha: 0.95),
                          ),
                        ),
                        Text(
                          '${_page + 1}/3',
                          style: GoogleFonts.inter(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: _neon.withValues(alpha: 0.85),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: PageView(
                      controller: _pageController,
                      physics: const BouncingScrollPhysics(),
                      onPageChanged: (i) {
                        setState(() => _page = i);
                        _syncPulseWithPage();
                      },
                      children: [
                        const _IntroPageCalling(),
                        const _IntroPageWallet(),
                        const _IntroPageMap(),
                      ],
                    ),
                  ),
                  const SizedBox(height: 10),
                  _PageDots(current: _page),
                  const SizedBox(height: 20),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
                    child: _page < 2
                        ? _NextButton(
                            onPressed: () {
                              _pageController.nextPage(
                                duration: const Duration(milliseconds: 420),
                                curve: Curves.easeOutCubic,
                              );
                            },
                          )
                        : AnimatedBuilder(
                            animation: _gotItPulse,
                            builder: (context, child) {
                              final s = _finishing ? 1.0 : _gotItScale.value;
                              return Transform.scale(scale: s, child: child);
                            },
                            child: Material(
                              color: Colors.transparent,
                              child: InkWell(
                                onTap: _finishing ? null : _onStartCalling,
                                borderRadius: BorderRadius.circular(28),
                                child: Ink(
                                  height: 56,
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(28),
                                    gradient: LinearGradient(
                                      begin: Alignment.topLeft,
                                      end: Alignment.bottomRight,
                                      colors: [
                                        _neon.withValues(alpha: 0.98),
                                        const Color(0xFF00B875),
                                        const Color(0xFF009A62),
                                      ],
                                    ),
                                    boxShadow: [
                                      BoxShadow(
                                        color: _neon.withValues(alpha: 0.16),
                                        blurRadius: 24,
                                        spreadRadius: -2,
                                        offset: const Offset(0, 10),
                                      ),
                                      BoxShadow(
                                        color: _neon.withValues(alpha: 0.12),
                                        blurRadius: 18,
                                        spreadRadius: -4,
                                        offset: const Offset(0, 8),
                                      ),
                                      BoxShadow(
                                        color: Colors.black.withValues(alpha: 0.28),
                                        blurRadius: 16,
                                        offset: const Offset(0, 6),
                                      ),
                                    ],
                                  ),
                                  child: Center(
                                    child: _finishing
                                        ? SizedBox(
                                            width: 24,
                                            height: 24,
                                            child: CircularProgressIndicator(
                                              strokeWidth: 2.4,
                                              color: Colors.white
                                                  .withValues(alpha: 0.95),
                                            ),
                                          )
                                        : Text(
                                            'Start Calling',
                                            style: GoogleFonts.inter(
                                              fontSize: 17,
                                              fontWeight: FontWeight.w800,
                                              letterSpacing: 0.4,
                                              color: Colors.white,
                                            ),
                                          ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PageDots extends StatelessWidget {
  const _PageDots({required this.current});

  final int current;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(3, (i) {
        final done = i < current;
        final active = i == current;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 320),
          curve: Curves.easeOutCubic,
          margin: const EdgeInsets.symmetric(horizontal: 5),
          width: active ? 28 : (done ? 11 : 8),
          height: active ? 11 : 8,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(6),
            color: done || active
                ? _neon.withValues(alpha: active ? 1.0 : 0.55)
                : Colors.white.withValues(alpha: 0.18),
            boxShadow: active
                ? [
                    BoxShadow(
                      color: _neon.withValues(alpha: 0.55),
                      blurRadius: 12,
                      spreadRadius: 1,
                    ),
                  ]
                : done
                    ? [
                        BoxShadow(
                          color: _neon.withValues(alpha: 0.2),
                          blurRadius: 6,
                        ),
                      ]
                    : null,
          ),
        );
      }),
    );
  }
}

class _GlowBlob extends StatelessWidget {
  const _GlowBlob({required this.color, required this.size});

  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(
          colors: [
            color,
            color.withValues(alpha: 0),
          ],
        ),
      ),
    );
  }
}

class _NextButton extends StatelessWidget {
  const _NextButton({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton(
      onPressed: onPressed,
      style: OutlinedButton.styleFrom(
        foregroundColor: _neon,
        side: BorderSide(color: _neon.withValues(alpha: 0.14)),
        padding: const EdgeInsets.symmetric(vertical: 16),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(28),
        ),
        shadowColor: _neon.withValues(alpha: 0.12),
        elevation: 0,
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            'Next',
            style: GoogleFonts.inter(
              fontSize: 16,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(width: 8),
          Icon(Icons.arrow_forward_rounded, color: _neon, size: 22),
        ],
      ),
    );
  }
}

class _IntroLottie extends StatelessWidget {
  const _IntroLottie({
    required this.asset,
    required this.semanticLabel,
  });

  final String asset;
  final String semanticLabel;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: semanticLabel,
      child: Lottie.asset(
        asset,
        fit: BoxFit.contain,
        repeat: true,
        frameRate: FrameRate.max,
        errorBuilder: (context, error, _) => Icon(
          Icons.auto_awesome_rounded,
          size: 88,
          color: _neon.withValues(alpha: 0.85),
        ),
      ),
    );
  }
}

/// Page 1 — calling Lottie + PRD lines (stagger slide-up).
class _IntroPageCalling extends StatefulWidget {
  const _IntroPageCalling();

  @override
  State<_IntroPageCalling> createState() => _IntroPageCallingState();
}

class _IntroPageCallingState extends State<_IntroPageCalling>
    with SingleTickerProviderStateMixin {
  late final AnimationController _stagger = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2000),
  );

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _stagger.forward();
    });
  }

  @override
  void dispose() {
    _stagger.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const lines = [
      'No SIM?',
      'No Bill.',
      'Just reliable international calls.',
    ];
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 28),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(28),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(16, 20, 16, 24),
              decoration: _introSoftPanelDecoration(),
              child: Column(
                children: [
                  SizedBox(
                    height: 200,
                    child: _IntroLottie(
                      asset: _lottieCalling,
                      semanticLabel: 'Calling animation',
                    ),
                  ),
                  const SizedBox(height: 8),
                  ...List.generate(lines.length, (i) {
                    final start = i * 0.22;
                    final end = (start + 0.38).clamp(0.0, 1.0);
                    final anim = CurvedAnimation(
                      parent: _stagger,
                      curve: Interval(
                        start,
                        end,
                        curve: Curves.easeOutCubic,
                      ),
                    );
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: AnimatedBuilder(
                        animation: anim,
                        builder: (context, child) {
                          return SlideTransition(
                            position: Tween<Offset>(
                              begin: const Offset(0, 0.22),
                              end: Offset.zero,
                            ).animate(anim),
                            child: FadeTransition(
                              opacity: anim,
                              child: child,
                            ),
                          );
                        },
                        child: Text(
                          lines[i],
                          textAlign: TextAlign.center,
                          style: GoogleFonts.inter(
                            fontSize: i == 2 ? 16.5 : 18,
                            fontWeight:
                                i == 2 ? FontWeight.w500 : FontWeight.w700,
                            height: 1.45,
                            letterSpacing: -0.2,
                            color: Colors.white.withValues(alpha: 0.94),
                          ),
                        ),
                      ),
                    );
                  }),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Page 2 — wallet / credits Lottie + staggered lines.
class _IntroPageWallet extends StatefulWidget {
  const _IntroPageWallet();

  @override
  State<_IntroPageWallet> createState() => _IntroPageWalletState();
}

class _IntroPageWalletState extends State<_IntroPageWallet>
    with SingleTickerProviderStateMixin {
  late final AnimationController _stagger = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2000),
  );

  static const _lines = [
    'Earn Credits.',
    'Watch 30 seconds of Ads,',
    'get 2 Minutes for FREE.',
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _stagger.forward();
    });
  }

  @override
  void dispose() {
    _stagger.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 28),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(28),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(16, 20, 16, 24),
              decoration: _introSoftPanelDecoration(),
              child: Column(
                children: [
                  SizedBox(
                    height: 200,
                    child: _IntroLottie(
                      asset: _lottieWallet,
                      semanticLabel: 'Wallet and credits',
                    ),
                  ),
                  const SizedBox(height: 8),
                  ...List.generate(_lines.length, (i) {
                    final start = i * 0.2;
                    final end = (start + 0.4).clamp(0.0, 1.0);
                    final anim = CurvedAnimation(
                      parent: _stagger,
                      curve: Interval(
                        start,
                        end,
                        curve: Curves.easeOutCubic,
                      ),
                    );
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: AnimatedBuilder(
                        animation: anim,
                        builder: (context, child) {
                          return SlideTransition(
                            position: Tween<Offset>(
                              begin: const Offset(0, 0.2),
                              end: Offset.zero,
                            ).animate(anim),
                            child: FadeTransition(
                              opacity: anim,
                              child: child,
                            ),
                          );
                        },
                        child: Text(
                          _lines[i],
                          textAlign: TextAlign.center,
                          style: GoogleFonts.inter(
                            fontSize: i == 0 ? 18 : 16.5,
                            fontWeight:
                                i == 0 ? FontWeight.w700 : FontWeight.w500,
                            height: 1.45,
                            letterSpacing: -0.2,
                            color: Colors.white.withValues(alpha: 0.94),
                          ),
                        ),
                      ),
                    );
                  }),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Page 3 — map / global Lottie + staggered lines.
class _IntroPageMap extends StatefulWidget {
  const _IntroPageMap();

  @override
  State<_IntroPageMap> createState() => _IntroPageMapState();
}

class _IntroPageMapState extends State<_IntroPageMap>
    with SingleTickerProviderStateMixin {
  late final AnimationController _stagger = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1800),
  );

  static const _lines = [
    'Any Country, Any Time.',
    'Just TalkFree.',
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _stagger.forward();
    });
  }

  @override
  void dispose() {
    _stagger.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 28),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(28),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(16, 20, 16, 24),
              decoration: _introSoftPanelDecoration(),
              child: Column(
                children: [
                  SizedBox(
                    height: 200,
                    child: _IntroLottie(
                      asset: _lottieGlobe,
                      semanticLabel: 'Global map',
                    ),
                  ),
                  const SizedBox(height: 8),
                  ...List.generate(_lines.length, (i) {
                    final start = i * 0.28;
                    final end = (start + 0.45).clamp(0.0, 1.0);
                    final anim = CurvedAnimation(
                      parent: _stagger,
                      curve: Interval(
                        start,
                        end,
                        curve: Curves.easeOutCubic,
                      ),
                    );
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: AnimatedBuilder(
                        animation: anim,
                        builder: (context, child) {
                          return SlideTransition(
                            position: Tween<Offset>(
                              begin: const Offset(0, 0.2),
                              end: Offset.zero,
                            ).animate(anim),
                            child: FadeTransition(
                              opacity: anim,
                              child: child,
                            ),
                          );
                        },
                        child: Text(
                          _lines[i],
                          textAlign: TextAlign.center,
                          style: GoogleFonts.inter(
                            fontSize: i == 0 ? 18 : 17,
                            fontWeight:
                                i == 0 ? FontWeight.w700 : FontWeight.w600,
                            height: 1.45,
                            letterSpacing: -0.2,
                            color: Colors.white.withValues(alpha: 0.94),
                          ),
                        ),
                      ),
                    );
                  }),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../config/credits_policy.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';

/// Short-lived monetization visuals: floating +N and ad-reward fanfare (no new packages).
abstract final class EngagementOverlays {
  EngagementOverlays._();

  /// Top-right style float for credit deltas (optional reuse).
  static void showFloatingCreditDelta(
    BuildContext context, {
    required int delta,
    Duration hold = const Duration(milliseconds: 2200),
  }) {
    final overlay = Overlay.of(context);
    late OverlayEntry entry;
    entry = OverlayEntry(
      builder: (ctx) => _FloatingDeltaLayer(
        delta: delta,
        onDone: () {
          entry.remove();
        },
        hold: hold,
      ),
    );
    overlay.insert(entry);
  }

  /// Center burst + confetti-ish dots after a rewarded ad.
  static void showAdRewardFanfare(
    BuildContext context, {
    required int creditsAdded,
    int streakBonus = 0,
    int streakDays = 0,
    bool welcomeFirstAd = false,
    Duration total = const Duration(milliseconds: 400),
  }) {
    final overlay = Overlay.of(context);
    late OverlayEntry entry;
    final duration = welcomeFirstAd
        ? const Duration(milliseconds: 520)
        : total;
    entry = OverlayEntry(
      builder: (ctx) => _AdFanfareLayer(
        creditsAdded: creditsAdded,
        streakBonus: streakBonus,
        streakDays: streakDays,
        welcomeFirstAd: welcomeFirstAd,
        onDone: () => entry.remove(),
        introDuration: duration,
      ),
    );
    overlay.insert(entry);
  }
}

class _FloatingDeltaLayer extends StatefulWidget {
  const _FloatingDeltaLayer({
    required this.delta,
    required this.onDone,
    required this.hold,
  });

  final int delta;
  final VoidCallback onDone;
  final Duration hold;

  @override
  State<_FloatingDeltaLayer> createState() => _FloatingDeltaLayerState();
}

class _FloatingDeltaLayerState extends State<_FloatingDeltaLayer>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 700),
  );
  late final Animation<double> _y = Tween<double>(begin: 12, end: 0).animate(
    CurvedAnimation(parent: _c, curve: Curves.easeOutCubic),
  );
  late final Animation<double> _o = CurvedAnimation(
    parent: _c,
    curve: const Interval(0.0, 0.45, curve: Curves.easeIn),
  );

  @override
  void initState() {
    super.initState();
    _c.forward();
    Future<void>.delayed(widget.hold, () {
      if (!mounted) return;
      widget.onDone();
    });
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.paddingOf(context).top + 56;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Positioned(
          top: top,
          right: 20,
          child: IgnorePointer(
            child: AnimatedBuilder(
              animation: _c,
              builder: (context, _) {
                return Transform.translate(
                  offset: Offset(0, _y.value),
                  child: Opacity(
                    opacity: _o.value.clamp(0.0, 1.0),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(999),
                        color: AppTheme.neonGreen.withValues(alpha: 0.22),
                        border: Border.all(
                          color: AppTheme.neonGreen.withValues(alpha: 0.55),
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: AppTheme.neonGreen.withValues(alpha: 0.35),
                            blurRadius: 18,
                            spreadRadius: 0,
                          ),
                        ],
                      ),
                      child: Text(
                        '+${widget.delta}',
                        style: GoogleFonts.poppins(
                          fontSize: 22,
                          fontWeight: FontWeight.w800,
                          color: Colors.white,
                          letterSpacing: -0.5,
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      ],
    );
  }
}

class _AdFanfareLayer extends StatefulWidget {
  const _AdFanfareLayer({
    required this.creditsAdded,
    required this.streakBonus,
    required this.streakDays,
    required this.welcomeFirstAd,
    required this.onDone,
    required this.introDuration,
  });

  final int creditsAdded;
  final int streakBonus;
  final int streakDays;
  final bool welcomeFirstAd;
  final VoidCallback onDone;
  final Duration introDuration;

  @override
  State<_AdFanfareLayer> createState() => _AdFanfareLayerState();
}

class _AdFanfareLayerState extends State<_AdFanfareLayer>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: widget.introDuration,
  );

  @override
  void initState() {
    super.initState();
    _c.forward();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  void _dismiss() => widget.onDone();

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final rnd = math.Random(42);
    const n = 9;
    final particles = List.generate(n, (i) {
      final ang = rnd.nextDouble() * math.pi * 2;
      final dist = 40.0 + rnd.nextDouble() * 100;
      return (dx: math.cos(ang) * dist, dy: math.sin(ang) * dist, c: i);
    });

    final streakLine = widget.streakDays > 0
        ? '🔥 Streak Day ${widget.streakDays}'
        : '🔥 Keep your streak';
    final bonusLine = widget.streakBonus > 0
        ? '+${widget.streakBonus} bonus'
        : 'Next milestone: day ${CreditsPolicy.adStreakMilestoneDays.first}';

    return Material(
      color: Colors.transparent,
      child: SizedBox.expand(
        child: Stack(
          children: [
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: _dismiss,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.45),
                  ),
                ),
              ),
            ),
            Center(
              child: AnimatedBuilder(
                animation: _c,
                builder: (context, _) {
                  final t = _c.value;
                  final pop = Curves.elasticOut.transform((t * 1.2).clamp(0.0, 1.0));
                  return Transform.scale(
                    scale: 0.92 + 0.08 * pop,
                    child: Container(
                      margin: const EdgeInsets.symmetric(horizontal: 28),
                      padding: const EdgeInsets.fromLTRB(24, 22, 24, 18),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(20),
                        color: AppColors.cardDark,
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.06),
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.35),
                            blurRadius: 24,
                            offset: const Offset(0, 12),
                          ),
                        ],
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (widget.welcomeFirstAd) ...[
                            Text(
                              '🎉 Welcome!',
                              textAlign: TextAlign.center,
                              style: GoogleFonts.poppins(
                                fontSize: 22,
                                fontWeight: FontWeight.w800,
                                color: Colors.white,
                                letterSpacing: -0.3,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              '+${widget.creditsAdded} FREE Credits',
                              textAlign: TextAlign.center,
                              style: GoogleFonts.poppins(
                                fontSize: 28,
                                fontWeight: FontWeight.w800,
                                color: AppColors.primary,
                                letterSpacing: -0.5,
                              ),
                            ),
                          ] else
                            Text(
                              '+${widget.creditsAdded} Credits 🎉',
                              textAlign: TextAlign.center,
                              style: GoogleFonts.poppins(
                                fontSize: 26,
                                fontWeight: FontWeight.w800,
                                color: Colors.white,
                                letterSpacing: -0.5,
                              ),
                            ),
                          const SizedBox(height: 12),
                          Text(
                            streakLine,
                            textAlign: TextAlign.center,
                            style: GoogleFonts.inter(
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                              color: Colors.white.withValues(alpha: 0.95),
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            bonusLine,
                            textAlign: TextAlign.center,
                            style: GoogleFonts.inter(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              height: 1.35,
                              color: Theme.of(context).colorScheme.onSurfaceVariant,
                            ),
                          ),
                          const SizedBox(height: 18),
                          SizedBox(
                            width: double.infinity,
                            child: FilledButton(
                              onPressed: _dismiss,
                              style: FilledButton.styleFrom(
                                backgroundColor: AppColors.primary,
                                foregroundColor: AppColors.onPrimary,
                                padding: const EdgeInsets.symmetric(vertical: 14),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(14),
                                ),
                                elevation: 0,
                              ),
                              child: Text(
                                'CONTINUE',
                                style: GoogleFonts.inter(
                                  fontWeight: FontWeight.w800,
                                  fontSize: 14,
                                  letterSpacing: 0.8,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
            ...particles.map((p) {
              return Positioned(
                left: size.width / 2 +
                    p.dx * _c.value -
                    4 +
                    (p.c % 3) * 2.0 * (1 - _c.value),
                top: size.height / 2 + p.dy * _c.value - 4,
                child: IgnorePointer(
                  child: Opacity(
                    opacity: (1.0 - _c.value).clamp(0.0, 1.0),
                    child: Container(
                      width: 5 + (p.c % 3).toDouble(),
                      height: 5 + (p.c % 2).toDouble(),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: [
                          AppColors.primary,
                          AppColors.primary,
                          Colors.amber.shade200,
                        ][p.c % 3].withValues(alpha: 0.65),
                      ),
                    ),
                  ),
                ),
              );
            }),
          ],
        ),
      ),
    );
  }
}

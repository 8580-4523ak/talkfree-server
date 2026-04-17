import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

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
    Duration total = const Duration(milliseconds: 2600),
  }) {
    final overlay = Overlay.of(context);
    late OverlayEntry entry;
    entry = OverlayEntry(
      builder: (ctx) => _AdFanfareLayer(
        creditsAdded: creditsAdded,
        streakBonus: streakBonus,
        streakDays: streakDays,
        onDone: () => entry.remove(),
        total: total,
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
    required this.onDone,
    required this.total,
  });

  final int creditsAdded;
  final int streakBonus;
  final int streakDays;
  final VoidCallback onDone;
  final Duration total;

  @override
  State<_AdFanfareLayer> createState() => _AdFanfareLayerState();
}

class _AdFanfareLayerState extends State<_AdFanfareLayer>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: widget.total,
  );

  @override
  void initState() {
    super.initState();
    _c.forward();
    _c.addStatusListener((s) {
      if (s == AnimationStatus.completed) {
        widget.onDone();
      }
    });
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final rnd = math.Random(42);
    const n = 18;
    final particles = List.generate(n, (i) {
      final ang = rnd.nextDouble() * math.pi * 2;
      final dist = 40.0 + rnd.nextDouble() * 120;
      return (dx: math.cos(ang) * dist, dy: math.sin(ang) * dist, c: i);
    });

    return Material(
      color: Colors.transparent,
      child: SizedBox.expand(
        child: Stack(
        children: [
          Positioned.fill(
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.08),
                ),
              ),
            ),
          ),
          Center(
            child: AnimatedBuilder(
              animation: _c,
              builder: (context, _) {
                final t = _c.value;
                final pop = Curves.elasticOut.transform(
                  (t * 1.4).clamp(0.0, 1.0),
                );
                return Transform.scale(
                  scale: 0.85 + 0.2 * pop,
                  child: Opacity(
                    opacity: (1.0 - (t - 0.85).clamp(0.0, 0.15) / 0.15)
                        .clamp(0.0, 1.0),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 28,
                        vertical: 20,
                      ),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(22),
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [
                            AppTheme.neonGreen.withValues(alpha: 0.35),
                            AppColors.darkBackgroundDeep.withValues(alpha: 0.92),
                          ],
                        ),
                        border: Border.all(
                          color: AppTheme.neonGreen.withValues(alpha: 0.5),
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: AppTheme.neonGreen.withValues(alpha: 0.45),
                            blurRadius: 28,
                            spreadRadius: 2,
                          ),
                        ],
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            '+${widget.creditsAdded} credits 🎉',
                            textAlign: TextAlign.center,
                            style: GoogleFonts.poppins(
                              fontSize: 24,
                              fontWeight: FontWeight.w800,
                              color: Colors.white,
                              letterSpacing: -0.5,
                            ),
                          ),
                          if (widget.streakBonus > 0 && widget.streakDays > 0) ...[
                            const SizedBox(height: 8),
                            Text(
                              'Streak day ${widget.streakDays} · +${widget.streakBonus} bonus',
                              textAlign: TextAlign.center,
                              style: GoogleFonts.inter(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                color: Colors.amber.shade200,
                              ),
                            ),
                          ],
                        ],
                      ),
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
                    width: 6 + (p.c % 4).toDouble(),
                    height: 6 + (p.c % 3).toDouble(),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: [
                        AppTheme.neonGreen,
                        AppColors.primary,
                        Colors.amber.shade300,
                      ][p.c % 3].withValues(alpha: 0.85),
                      boxShadow: [
                        BoxShadow(
                          color: AppTheme.neonGreen.withValues(alpha: 0.6),
                          blurRadius: 6,
                        ),
                      ],
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

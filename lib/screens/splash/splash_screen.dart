import 'dart:math' as math;
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../theme/app_colors.dart';
import '../../theme/app_theme.dart';
import '../../theme/system_ui.dart';
import '../../utils/app_strings.dart';

/// Transparent mark (no launcher plate) — avoids “black box” on dark splash.
const String _kSplashMarkAsset = 'assets/splash_mark.png';

/// Premium TalkFree splash — balanced layout, strong logo glow, ambient waves.
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key, this.showLoader = true});

  final bool showLoader;

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with TickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _fade;
  late final Animation<double> _slide;
  late final AnimationController _pulseController;
  late final Animation<double> _pulseScale;
  late final AnimationController _waveController;

  @override
  void initState() {
    super.initState();
    applyTalkFreeSplashNavigationChrome();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 880),
    );
    _fade = CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic);
    _slide = Tween<double>(begin: 18, end: 0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic),
    );
    _controller.forward();

    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2600),
    )..repeat(reverse: true);
    _pulseScale = Tween<double>(begin: 1.0, end: 1.035).animate(
      CurvedAnimation(
        parent: _pulseController,
        curve: Curves.easeInOutCubic,
      ),
    );

    _waveController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 14),
    )..repeat();
  }

  @override
  void dispose() {
    applyTalkFreeDarkNavigationChrome();
    _waveController.dispose();
    _pulseController.dispose();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final logoSize = (size.shortestSide * 0.44).clamp(200.0, 260.0);

    return Scaffold(
      backgroundColor: AppTheme.darkBg,
      body: Stack(
        fit: StackFit.expand,
        children: [
          // No full-bleed splash.png here — marketing PNGs often embed logo + copy and
          // duplicate what we paint below (TalkFree + tagline + hero mark).
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    AppTheme.darkBg,
                    AppColors.darkBackgroundDeep,
                    AppTheme.darkBg,
                  ],
                  stops: const [0.0, 0.5, 1.0],
                ),
              ),
            ),
          ),
          Positioned.fill(
            child: AnimatedBuilder(
              animation: _waveController,
              builder: (context, _) {
                return CustomPaint(
                  painter: _BackgroundRingsPainter(
                    phase: _waveController.value * math.pi * 2,
                    color: AppColors.primary,
                  ),
                );
              },
            ),
          ),
          Positioned.fill(
            child: AnimatedBuilder(
              animation: _waveController,
              builder: (context, _) {
                return CustomPaint(
                  painter: _AuroraWavePainter(
                    phase: _waveController.value * math.pi * 2,
                    color: AppColors.primary,
                  ),
                );
              },
            ),
          ),
          SafeArea(
            child: AnimatedBuilder(
              animation: _controller,
              builder: (context, child) {
                return Opacity(
                  opacity: _fade.value,
                  child: Transform.translate(
                    offset: Offset(0, _slide.value),
                    child: child,
                  ),
                );
              },
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 32),
                child: Column(
                  children: [
                    const Spacer(flex: 22),
                    RepaintBoundary(
                      child: AnimatedBuilder(
                        animation: _pulseController,
                        builder: (context, child) {
                          return Transform.scale(
                            scale: _pulseScale.value,
                            child: child,
                          );
                        },
                        child: _GlowingLogo(size: logoSize),
                      ),
                    ),
                    const SizedBox(height: 40),
                    Text(
                      AppStrings.appName,
                      textAlign: TextAlign.center,
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 36,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.8,
                        height: 1.05,
                        color: Colors.white,
                        shadows: [
                          Shadow(
                            color: AppColors.primary.withValues(alpha: 0.32),
                            blurRadius: 16,
                            offset: Offset.zero,
                          ),
                          Shadow(
                            color: AppColors.primary.withValues(alpha: 0.14),
                            blurRadius: 32,
                            offset: Offset.zero,
                          ),
                          Shadow(
                            color: Colors.black.withValues(alpha: 0.55),
                            blurRadius: 14,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 14),
                    Text(
                      AppStrings.splashTagline,
                      textAlign: TextAlign.center,
                      style: GoogleFonts.inter(
                        fontSize: 16,
                        height: 1.5,
                        letterSpacing: 0.35,
                        fontWeight: FontWeight.w500,
                        color: Colors.white.withValues(alpha: 0.82),
                      ),
                    ),
                    const Spacer(flex: 26),
                    if (widget.showLoader)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 28),
                        child: SizedBox(
                          width: 32,
                          height: 32,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.5,
                            color: AppColors.primary,
                            backgroundColor:
                                AppColors.primary.withValues(alpha: 0.1),
                          ),
                        ),
                      )
                    else
                      const SizedBox(height: 60),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _GlowingLogo extends StatelessWidget {
  const _GlowingLogo({required this.size});

  final double size;

  @override
  Widget build(BuildContext context) {
    final halo = size * 1.35;
    return SizedBox(
      width: halo,
      height: halo,
      child: Stack(
        alignment: Alignment.center,
        clipBehavior: Clip.none,
        children: [
          Positioned.fill(
            child: ImageFiltered(
              imageFilter: ImageFilter.blur(sigmaX: 28, sigmaY: 28),
              child: Container(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [
                      AppColors.primary.withValues(alpha: 0.38),
                      AppColors.primary.withValues(alpha: 0.06),
                      Colors.transparent,
                    ],
                    stops: const [0.0, 0.38, 1.0],
                  ),
                ),
              ),
            ),
          ),
          SizedBox(
            width: size,
            height: size,
            child: ClipOval(
              child: Image.asset(
                _kSplashMarkAsset,
                fit: BoxFit.cover,
                alignment: Alignment.center,
                filterQuality: FilterQuality.high,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Large soft mint rings (mockup-style depth behind logo).
class _BackgroundRingsPainter extends CustomPainter {
  _BackgroundRingsPainter({required this.phase, required this.color});

  final double phase;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final ss = math.min(size.width, size.height);
    final c = Offset(size.width / 2, size.height * 0.38);
    for (var i = 0; i < 3; i++) {
      final r = ss * (0.28 + i * 0.14) + math.sin(phase + i * 0.4) * 6;
      final paint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2
        ..color = color.withValues(alpha: 0.045 + i * 0.025);
      canvas.drawCircle(c, r, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _BackgroundRingsPainter oldDelegate) {
    return oldDelegate.phase != phase || oldDelegate.color != color;
  }
}

/// Soft animated waves + sparse particles (premium, not noisy).
class _AuroraWavePainter extends CustomPainter {
  _AuroraWavePainter({required this.phase, required this.color});

  final double phase;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final rnd = math.Random(7);
    for (var i = 0; i < 36; i++) {
      final x = rnd.nextDouble() * w;
      final base = rnd.nextDouble() * h * 0.55;
      final y = (base + math.sin(phase * 0.6 + x * 0.008) * 14) % (h * 0.65);
      final pr = 1.0 + rnd.nextDouble() * 1.5;
      final op = 0.03 + rnd.nextDouble() * 0.1;
      canvas.drawCircle(
        Offset(x, y),
        pr,
        Paint()
          ..color = color.withValues(alpha: op)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 1),
      );
    }
    // Flowing wave lines (upper / mid screen)
    for (var band = 0; band < 5; band++) {
      final t = band / 4.0;
      final baseY = h * (0.18 + t * 0.22);
      final path = Path();
      const seg = 48;
      for (var i = 0; i <= seg; i++) {
        final px = w * (i / seg);
        final wave = math.sin(px * 0.014 + phase * 1.1 + band * 0.9) * 10 +
            math.sin(px * 0.007 + phase * 0.45) * 16;
        final py = baseY + wave;
        if (i == 0) {
          path.moveTo(px, py);
        } else {
          path.lineTo(px, py);
        }
      }
      final paint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2
        ..color = color.withValues(alpha: 0.035 + t * 0.04)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 1.5);
      canvas.drawPath(path, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _AuroraWavePainter oldDelegate) {
    return oldDelegate.phase != phase || oldDelegate.color != color;
  }
}

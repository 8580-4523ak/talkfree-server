import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import '../theme/app_colors.dart';
import '../theme/app_theme.dart';

/// Elite dark shell + neon accent (TalkFree premium dialer).
const Color premiumDialBackground = AppTheme.darkBg;
const Color premiumDialKeyFill = AppColors.cardDark;
Color get premiumDialCallGreen => AppColors.primary;

TextStyle eliteDialDigitStyle(double fontSize) => GoogleFonts.inter(
      fontSize: fontSize,
      fontWeight: FontWeight.w300,
      color: Colors.white,
      height: 1.0,
      letterSpacing: 0.5,
    );

TextStyle eliteDialLettersStyle(double fontSize) => GoogleFonts.inter(
      fontSize: fontSize,
      fontWeight: FontWeight.w600,
      letterSpacing: 1.15,
      color: Colors.white.withValues(alpha: 0.42),
      height: 1.0,
    );

class PremiumDialKeyData {
  const PremiumDialKeyData(this.digit, this.letters);
  final String digit;
  final String letters;
}

class PremiumIosDialKey extends StatefulWidget {
  const PremiumIosDialKey({
    super.key,
    required this.data,
    required this.onPressed,
    this.onLongPress,
    this.height = 56,
  });

  final PremiumDialKeyData data;
  final VoidCallback onPressed;
  final VoidCallback? onLongPress;
  final double height;

  @override
  State<PremiumIosDialKey> createState() => _PremiumIosDialKeyState();
}

class _PremiumIosDialKeyState extends State<PremiumIosDialKey>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 100),
  );
  late final Animation<double> _scale = Tween<double>(begin: 1.0, end: 0.94)
      .animate(CurvedAnimation(parent: _c, curve: Curves.easeOutCubic));

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  Future<void> _tap() async {
    HapticFeedback.selectionClick();
    await _c.forward();
    await _c.reverse();
    widget.onPressed();
  }

  Future<void> _longPress() async {
    if (widget.onLongPress == null) return;
    HapticFeedback.mediumImpact();
    await _c.forward();
    await _c.reverse();
    widget.onLongPress!();
  }

  @override
  Widget build(BuildContext context) {
    final r = widget.height * 0.5;
    return ScaleTransition(
      scale: _scale,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: _tap,
          onLongPress:
              widget.onLongPress == null ? null : () => _longPress(),
          borderRadius: BorderRadius.circular(r),
          splashColor: premiumDialCallGreen.withValues(alpha: 0.18),
          highlightColor: premiumDialCallGreen.withValues(alpha: 0.08),
          child: AnimatedBuilder(
            animation: _c,
            builder: (context, child) {
              final p = CurvedAnimation(
                parent: _c,
                curve: Curves.easeOutCubic,
              ).value;
              final innerA = 0.035 + p * 0.38;
              final borderA = 0.06 + p * 0.42;
              return Ink(
                height: widget.height,
                decoration: BoxDecoration(
                  color: premiumDialKeyFill,
                  borderRadius: BorderRadius.circular(r),
                  border: Border.all(
                    color: premiumDialCallGreen.withValues(alpha: borderA),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.42),
                      blurRadius: 10,
                      offset: const Offset(0, 5),
                    ),
                    BoxShadow(
                      color: premiumDialCallGreen.withValues(alpha: 0.05 + p * 0.35),
                      blurRadius: 14 + p * 8,
                      spreadRadius: p * 1.2,
                      offset: Offset(0, 4 - p * 2),
                    ),
                  ],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(r),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: RadialGradient(
                            center: const Alignment(-0.35, -0.45),
                            radius: 1.05,
                            colors: [
                              premiumDialCallGreen.withValues(alpha: innerA),
                              premiumDialCallGreen.withValues(alpha: innerA * 0.25),
                              Colors.transparent,
                            ],
                            stops: const [0.0, 0.42, 1.0],
                          ),
                        ),
                      ),
                      DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: RadialGradient(
                            center: Alignment.bottomRight,
                            radius: 1.2,
                            colors: [
                              Colors.white.withValues(alpha: 0.03 + p * 0.06),
                              Colors.transparent,
                            ],
                            stops: const [0.0, 0.55],
                          ),
                        ),
                      ),
                      Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              widget.data.digit,
                              style: eliteDialDigitStyle(30),
                            ),
                            if (widget.data.letters.isNotEmpty) ...[
                              const SizedBox(height: 2),
                              Text(
                                widget.data.letters,
                                style: eliteDialLettersStyle(9),
                              ),
                            ] else
                              const SizedBox(height: 11),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

class PremiumIosDialPad extends StatelessWidget {
  const PremiumIosDialPad({
    super.key,
    required this.onDigit,
    this.horizontalPadding = 20,
    this.gap = 14,
    this.keyHeight = 56,
  });

  final ValueChanged<String> onDigit;
  final double horizontalPadding;
  final double gap;
  final double keyHeight;

  static const List<List<PremiumDialKeyData>> _rows = [
    [
      PremiumDialKeyData('1', ''),
      PremiumDialKeyData('2', 'ABC'),
      PremiumDialKeyData('3', 'DEF'),
    ],
    [
      PremiumDialKeyData('4', 'GHI'),
      PremiumDialKeyData('5', 'JKL'),
      PremiumDialKeyData('6', 'MNO'),
    ],
    [
      PremiumDialKeyData('7', 'PQRS'),
      PremiumDialKeyData('8', 'TUV'),
      PremiumDialKeyData('9', 'WXYZ'),
    ],
    [
      PremiumDialKeyData('*', ''),
      PremiumDialKeyData('0', '+'),
      PremiumDialKeyData('#', ''),
    ],
  ];

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final innerW = constraints.maxWidth - horizontalPadding * 2;
        final keyW = (innerW - gap * 2) / 3;
        return Padding(
          padding: EdgeInsets.symmetric(horizontal: horizontalPadding),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (var ri = 0; ri < _rows.length; ri++) ...[
                if (ri > 0) SizedBox(height: gap),
                Row(
                  children: [
                    for (var ci = 0; ci < 3; ci++) ...[
                      if (ci > 0) SizedBox(width: gap),
                      SizedBox(
                        width: keyW,
                        height: keyHeight,
                        child: PremiumIosDialKey(
                          height: keyHeight,
                          data: _rows[ri][ci],
                          onPressed: () => onDigit(_rows[ri][ci].digit),
                          onLongPress: _rows[ri][ci].digit == '0'
                              ? () => onDigit('+')
                              : null,
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}

class PremiumIosCallButton extends StatefulWidget {
  const PremiumIosCallButton({
    super.key,
    required this.onPressed,
    this.busy = false,
    this.horizontalMargin = 24,
  });

  final VoidCallback? onPressed;
  final bool busy;
  final double horizontalMargin;

  @override
  State<PremiumIosCallButton> createState() => _PremiumIosCallButtonState();
}

class _PremiumIosCallButtonState extends State<PremiumIosCallButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 100),
  );
  late final Animation<double> _scale = Tween<double>(begin: 1.0, end: 0.97)
      .animate(CurvedAnimation(parent: _c, curve: Curves.easeOutCubic));

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  Future<void> _tap() async {
    if (widget.busy || widget.onPressed == null) return;
    HapticFeedback.mediumImpact();
    await _c.forward();
    await _c.reverse();
    widget.onPressed!();
  }

  @override
  Widget build(BuildContext context) {
    final enabled = !widget.busy && widget.onPressed != null;
    const diameter = 76.0;
    final outerShadow = BoxDecoration(
      shape: BoxShape.circle,
      boxShadow: [
        BoxShadow(
          color: Colors.black.withValues(alpha: 0.38),
          blurRadius: 18,
          spreadRadius: 0,
          offset: const Offset(0, 8),
        ),
        BoxShadow(
          color: premiumDialCallGreen.withValues(alpha: 0.35),
          blurRadius: 24,
          spreadRadius: -4,
          offset: const Offset(0, 10),
        ),
      ],
    );

    return Center(
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: widget.horizontalMargin),
        child: ScaleTransition(
          scale: _scale,
          child: Material(
            color: Colors.transparent,
            elevation: 0,
            shadowColor: Colors.transparent,
            child: InkWell(
              onTap: enabled ? _tap : null,
              customBorder: const CircleBorder(),
              splashColor: Colors.white.withValues(alpha: 0.28),
              highlightColor: Colors.white.withValues(alpha: 0.12),
              child: Container(
                width: diameter,
                height: diameter,
                decoration: outerShadow,
                child: ClipOval(
                  child: Ink(
                    width: diameter,
                    height: diameter,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          Color(0xFF34D399),
                          premiumDialCallGreen,
                          Color(0xFF059669),
                        ],
                        stops: [0.0, 0.45, 1.0],
                      ),
                    ),
                    child: Center(
                      child: widget.busy
                          ? const SizedBox(
                              width: 28,
                              height: 28,
                              child: CircularProgressIndicator(
                                strokeWidth: 2.5,
                                color: Colors.white,
                              ),
                            )
                          : Icon(
                              Icons.call_rounded,
                              color: Colors.white.withValues(alpha: 0.98),
                              size: 34,
                            ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

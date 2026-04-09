import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

const Color premiumDialBackground = Color(0xFF0F172A);
const Color premiumDialKeyFill = Color(0xFF1E293B);
const Color premiumDialCallGreen = Color(0xFF00D084);

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
    HapticFeedback.lightImpact();
    SystemSound.play(SystemSoundType.click);
    await _c.forward();
    await _c.reverse();
    widget.onPressed();
  }

  Future<void> _longPress() async {
    if (widget.onLongPress == null) return;
    HapticFeedback.lightImpact();
    SystemSound.play(SystemSoundType.click);
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
          splashColor: Colors.white.withValues(alpha: 0.08),
          highlightColor: Colors.white.withValues(alpha: 0.04),
          child: Ink(
            height: widget.height,
            decoration: BoxDecoration(
              color: premiumDialKeyFill,
              borderRadius: BorderRadius.circular(r),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.45),
                  blurRadius: 8,
                  offset: const Offset(0, 4),
                ),
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.2),
                  blurRadius: 2,
                  offset: const Offset(0, 1),
                ),
              ],
            ),
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    widget.data.digit,
                    style: const TextStyle(
                      fontSize: 26,
                      fontWeight: FontWeight.w300,
                      color: Colors.white,
                      height: 1.0,
                    ),
                  ),
                  if (widget.data.letters.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      widget.data.letters,
                      style: TextStyle(
                        fontSize: 9,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 1.2,
                        color: Colors.white.withValues(alpha: 0.45),
                        height: 1.0,
                      ),
                    ),
                  ] else
                    const SizedBox(height: 11),
                ],
              ),
            ),
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
    const r = 32.0;
    final br = BorderRadius.circular(r);
    final outerShadow = BoxDecoration(
      borderRadius: br,
      boxShadow: [
        BoxShadow(
          color: Colors.black.withValues(alpha: 0.38),
          blurRadius: 14,
          spreadRadius: 0,
          offset: const Offset(0, 6),
        ),
        BoxShadow(
          color: premiumDialCallGreen.withValues(alpha: 0.32),
          blurRadius: 20,
          spreadRadius: 0,
          offset: const Offset(0, 8),
        ),
        BoxShadow(
          color: Colors.black.withValues(alpha: 0.12),
          blurRadius: 6,
          offset: const Offset(0, 2),
        ),
      ],
    );

    return Padding(
      padding: EdgeInsets.symmetric(horizontal: widget.horizontalMargin),
      child: ScaleTransition(
        scale: _scale,
        child: Material(
          color: Colors.transparent,
          elevation: 0,
          shadowColor: Colors.transparent,
          child: InkWell(
            onTap: enabled ? _tap : null,
            borderRadius: br,
            splashFactory: InkRipple.splashFactory,
            splashColor: Colors.white.withValues(alpha: 0.38),
            highlightColor: Colors.white.withValues(alpha: 0.14),
            child: Container(
              decoration: outerShadow,
              child: ClipRRect(
                borderRadius: br,
                child: Ink(
                  height: 56,
                  width: double.infinity,
                  decoration: BoxDecoration(
                    borderRadius: br,
                    gradient: const LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        Color(0xFF00F0B0),
                        premiumDialCallGreen,
                        Color(0xFF00C078),
                        Color(0xFF009A5C),
                      ],
                      stops: [0.0, 0.32, 0.62, 1.0],
                    ),
                  ),
                  child: Center(
                    child: widget.busy
                        ? const SizedBox(
                            width: 26,
                            height: 26,
                            child: CircularProgressIndicator(
                              strokeWidth: 2.5,
                              color: Colors.white,
                            ),
                          )
                        : Row(
                            mainAxisSize: MainAxisSize.min,
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.call_rounded,
                                color: Colors.white.withValues(alpha: 0.98),
                                size: 24,
                              ),
                              const SizedBox(width: 10),
                              Text(
                                'Call',
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w600,
                                  letterSpacing: 0.3,
                                  color: Colors.white.withValues(alpha: 0.98),
                                ),
                              ),
                            ],
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

import 'package:flutter/material.dart';

/// Very subtle breathing scale — primary CTAs only; disable while loading.
class SoftPulse extends StatefulWidget {
  const SoftPulse({
    super.key,
    required this.child,
    this.enabled = true,
  });

  final Widget child;
  final bool enabled;

  @override
  State<SoftPulse> createState() => _SoftPulseState();
}

class _SoftPulseState extends State<SoftPulse> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2400),
  );

  @override
  void initState() {
    super.initState();
    if (widget.enabled) {
      _c.repeat(reverse: true);
    }
  }

  @override
  void didUpdateWidget(covariant SoftPulse oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.enabled && !oldWidget.enabled) {
      _c.repeat(reverse: true);
    } else if (!widget.enabled && oldWidget.enabled) {
      _c.stop();
      _c.value = 0;
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.enabled) return widget.child;
    return AnimatedBuilder(
      animation: _c,
      builder: (context, child) {
        final t = Curves.easeInOut.transform(_c.value);
        final s = 1.0 + 0.014 * t;
        return Transform.scale(scale: s, alignment: Alignment.center, child: child);
      },
      child: widget.child,
    );
  }
}

import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// Frosted glass: blur + translucent fill + soft border (premium fintech shell).
class GlassPanel extends StatelessWidget {
  const GlassPanel({
    super.key,
    required this.child,
    this.borderRadius = 18,
    this.padding,
    /// Stronger neon rim + glow (hero cards, rewards).
    this.accentNeon = false,
  });

  final Widget child;
  final double borderRadius;
  final EdgeInsetsGeometry? padding;
  final bool accentNeon;

  @override
  Widget build(BuildContext context) {
    final borderColor = accentNeon
        ? AppColors.primary.withValues(alpha: 0.22)
        : Colors.white.withValues(alpha: 0.08);
    return ClipRRect(
      borderRadius: BorderRadius.circular(borderRadius),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
        child: Container(
          padding: padding,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(borderRadius),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                AppColors.cardDark.withValues(alpha: 0.98),
                AppColors.darkBackgroundDeep.withValues(alpha: 0.98),
              ],
            ),
            border: Border.all(color: borderColor, width: accentNeon ? 0.5 : 0.5),
          ),
          child: child,
        ),
      ),
    );
  }
}

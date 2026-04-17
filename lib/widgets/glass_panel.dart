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
        ? AppColors.primary.withValues(alpha: 0.42)
        : Colors.white.withValues(alpha: 0.22);
    return ClipRRect(
      borderRadius: BorderRadius.circular(borderRadius),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
        child: Container(
          padding: padding,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(borderRadius),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Colors.white.withValues(alpha: accentNeon ? 0.1 : 0.07),
                Colors.white.withValues(alpha: 0.02),
                AppColors.primary.withValues(alpha: accentNeon ? 0.06 : 0.02),
              ],
            ),
            border: Border.all(color: borderColor, width: accentNeon ? 1 : 0.5),
            boxShadow: accentNeon
                ? [
                    BoxShadow(
                      color: AppColors.primary.withValues(alpha: 0.18),
                      blurRadius: 24,
                      spreadRadius: -4,
                      offset: const Offset(0, 12),
                    ),
                  ]
                : null,
          ),
          child: child,
        ),
      ),
    );
  }
}

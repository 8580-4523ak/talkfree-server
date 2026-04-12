import 'package:flutter/material.dart';

/// TalkFree design tokens — single source of truth for colors.
abstract final class AppColors {
  AppColors._();

  /// Emerald — primary accent (calls, earn, positive actions).
  static const Color primary = Color(0xFF10B981);

  /// Soft amber — wallet / credits highlights (secondary accent).
  static const Color accentAmber = Color(0xFFF59E0B);

  static const Color darkBackground = Color(0xFF0F172A);
  static const Color darkBackgroundDeep = Color(0xFF020617);
  static const Color surfaceDark = Color(0xFF1E293B);
  static const Color cardDark = Color(0xFF1E293B);

  static const Color textOnDark = Color(0xFFF8FAFC);
  static const Color textMutedOnDark = Color(0xFF94A3B8);

  static const Color lightBackground = Color(0xFFF8FAFC);
  static const Color textOnLight = Color(0xFF0F172A);
  static const Color textMutedOnLight = Color(0xFF64748B);

  static const Color accentGold = Color(0xFFFFD700);
  static const Color danger = Color(0xFFEF4444);

  static const Color onPrimary = Color(0xFFFFFFFF);
}

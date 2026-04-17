import 'package:flutter/material.dart';

/// TalkFree design tokens — single source of truth for colors.
///
/// **TalkFree Pro — Neon-Black Shield:** accent `#00FF9C`, shell `#020814`.
abstract final class AppColors {
  AppColors._();

  /// Neon green — primary brand / VoIP accent (**#00FF9C**).
  static const Color primary = Color(0xFF00FF9C);

  /// Blue — splash accents (icons, links).
  static const Color splashAccent = Color(0xFF2563EB);

  /// Legacy neon slot — matches [primary] for cyberpunk badges.
  static const Color splashNeon = Color(0xFF00FF9C);

  /// Splash — black / dark grey; logo tiles + native chrome.
  static const Color splashMidnight = Color(0xFF000000);
  static const Color splashHorizonDeep = Color(0xFF0C0E12);
  static const Color splashGradientTop = splashMidnight;
  static const Color splashGradientBottom = splashHorizonDeep;
  static const Color splashStage = Color(0xFF16181D);
  static const Color splashStageTop = splashMidnight;
  static const Color splashStageBottom = splashHorizonDeep;

  /// Deep black scaffold / shell (**#020814**).
  static const Color darkBackground = Color(0xFF020814);
  static const Color darkBackgroundDeep = Color(0xFF01050C);
  /// Cards, inputs, elevated surfaces (Master `surfaceCard`).
  static const Color surfaceDark = Color(0xFF0F1728);
  static const Color cardDark = Color(0xFF0A1220);

  static const Color textOnDark = Color(0xFFFFFFFF);
  /// Master muted body / secondary text.
  static const Color textMutedOnDark = Color(0xFF8F9BB3);

  static const Color lightBackground = Color(0xFFF8FAFC);
  static const Color textOnLight = Color(0xFF0F172A);
  static const Color textMutedOnLight = Color(0xFF64748B);

  static const Color accentGold = Color(0xFFFFD700);
  static const Color danger = Color(0xFFEF4444);

  static const Color onPrimary = Color(0xFFFFFFFF);
}

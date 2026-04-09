import 'package:flutter/material.dart';

import 'app_colors.dart';

/// App-wide colors. Legacy names map to [AppColors] so older screens stay valid.
abstract final class TalkFreeColors {
  TalkFreeColors._();

  static const Color primary = AppColors.primary;

  /// Legacy: was beige; now primary green.
  static const Color beigeGold = AppColors.primary;

  static const Color cardBg = AppColors.cardDark;
  static const Color deepBlack = AppColors.darkBackgroundDeep;
  static const Color charcoal = AppColors.surfaceDark;

  static const Color backgroundTop = AppColors.darkBackground;
  static const Color backgroundMid = AppColors.surfaceDark;
  static const Color backgroundBottom = AppColors.darkBackgroundDeep;

  static const Color offWhite = AppColors.textOnDark;
  static const Color mutedWhite = AppColors.textMutedOnDark;

  static const Color accentGold = AppColors.accentGold;

  /// Text/icons on primary (green) buttons.
  static const Color onPrimary = AppColors.onPrimary;
}

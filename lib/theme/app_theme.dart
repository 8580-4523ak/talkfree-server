import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'app_colors.dart';
import 'talkfree_colors.dart';

abstract final class AppTheme {
  AppTheme._();

  static const double radiusMd = 16;
  static const double radiusLg = 20;

  /// Dark theme — primary green, slate surfaces, Poppins headings + Inter body.
  static ThemeData dark() {
    const colorScheme = ColorScheme.dark(
      primary: AppColors.primary,
      onPrimary: AppColors.onPrimary,
      secondary: AppColors.accentAmber,
      onSecondary: Color(0xFF0F172A),
      surface: AppColors.darkBackground,
      onSurface: TalkFreeColors.offWhite,
      onSurfaceVariant: TalkFreeColors.mutedWhite,
      outline: AppColors.primary,
      outlineVariant: Color(0xFF334155),
      error: AppColors.danger,
      onError: AppColors.onPrimary,
    );

    final interBase = GoogleFonts.interTextTheme();
    final poppins = GoogleFonts.poppinsTextTheme();

    final textTheme = TextTheme(
      displayLarge: poppins.displayLarge?.copyWith(
        color: AppColors.primary,
        fontWeight: FontWeight.w700,
      ),
      displayMedium: poppins.displayMedium?.copyWith(
        color: AppColors.primary,
        fontWeight: FontWeight.w700,
      ),
      displaySmall: poppins.displaySmall?.copyWith(
        color: AppColors.primary,
        fontWeight: FontWeight.w700,
      ),
      headlineLarge: poppins.headlineLarge?.copyWith(
        color: AppColors.primary,
        fontWeight: FontWeight.w700,
      ),
      headlineMedium: poppins.headlineMedium?.copyWith(
        color: AppColors.primary,
        fontWeight: FontWeight.w700,
      ),
      headlineSmall: poppins.headlineSmall?.copyWith(
        color: AppColors.primary,
        fontWeight: FontWeight.w600,
      ),
      titleLarge: poppins.titleLarge?.copyWith(
        color: TalkFreeColors.offWhite,
        fontWeight: FontWeight.w700,
      ),
      titleMedium: poppins.titleMedium?.copyWith(
        color: TalkFreeColors.offWhite,
        fontWeight: FontWeight.w600,
      ),
      titleSmall: poppins.titleSmall?.copyWith(
        color: TalkFreeColors.offWhite,
        fontWeight: FontWeight.w600,
      ),
      bodyLarge: interBase.bodyLarge?.copyWith(color: TalkFreeColors.offWhite),
      bodyMedium:
          interBase.bodyMedium?.copyWith(color: TalkFreeColors.offWhite),
      bodySmall: interBase.bodySmall?.copyWith(color: TalkFreeColors.mutedWhite),
      labelLarge: interBase.labelLarge?.copyWith(
        color: AppColors.primary,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.4,
      ),
      labelMedium:
          interBase.labelMedium?.copyWith(color: TalkFreeColors.mutedWhite),
      labelSmall:
          interBase.labelSmall?.copyWith(color: TalkFreeColors.mutedWhite),
    );

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: AppColors.darkBackground,
      textTheme: textTheme,
      primaryColor: AppColors.primary,
      dividerColor: const Color(0xFF334155),
      appBarTheme: AppBarTheme(
        elevation: 0,
        scrolledUnderElevation: 0,
        backgroundColor: AppColors.darkBackground,
        foregroundColor: TalkFreeColors.offWhite,
        iconTheme: const IconThemeData(color: TalkFreeColors.offWhite),
        titleTextStyle: GoogleFonts.poppins(
          fontSize: 20,
          fontWeight: FontWeight.w600,
          color: TalkFreeColors.offWhite,
        ),
      ),
      cardTheme: CardThemeData(
        color: TalkFreeColors.cardBg.withValues(alpha: 0.92),
        elevation: 0,
        shadowColor: Colors.black.withValues(alpha: 0.45),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusLg),
          side: BorderSide(
            color: Colors.white.withValues(alpha: 0.06),
            width: 1,
          ),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: AppColors.primary,
          foregroundColor: AppColors.onPrimary,
          disabledBackgroundColor: AppColors.primary.withValues(alpha: 0.35),
          disabledForegroundColor: AppColors.onPrimary.withValues(alpha: 0.5),
          padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(radiusLg),
          ),
          minimumSize: const Size.fromHeight(52),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.primary,
          side: const BorderSide(color: AppColors.primary, width: 1.5),
          padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(radiusLg),
          ),
          minimumSize: const Size.fromHeight(52),
        ),
      ),
      bottomNavigationBarTheme: BottomNavigationBarThemeData(
        backgroundColor: AppColors.darkBackground,
        selectedItemColor: AppColors.primary,
        unselectedItemColor: TalkFreeColors.mutedWhite.withValues(alpha: 0.55),
        type: BottomNavigationBarType.fixed,
        elevation: 0,
        showUnselectedLabels: true,
        selectedLabelStyle: GoogleFonts.inter(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.2,
        ),
        unselectedLabelStyle: GoogleFonts.inter(
          fontSize: 12,
          fontWeight: FontWeight.w500,
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: TalkFreeColors.cardBg,
        contentTextStyle: GoogleFonts.inter(
          color: TalkFreeColors.offWhite,
          fontSize: 14,
        ),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusLg),
        ),
      ),
      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: AppColors.primary,
      ),
      iconTheme: const IconThemeData(color: TalkFreeColors.offWhite),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: TalkFreeColors.cardBg,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusLg),
          borderSide: BorderSide(
            color: AppColors.primary.withValues(alpha: 0.35),
          ),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusLg),
          borderSide: BorderSide(
            color: AppColors.primary.withValues(alpha: 0.35),
          ),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusLg),
          borderSide: const BorderSide(
            color: AppColors.primary,
            width: 1.4,
          ),
        ),
        labelStyle: GoogleFonts.inter(color: TalkFreeColors.mutedWhite),
        hintStyle: GoogleFonts.inter(color: TalkFreeColors.mutedWhite),
      ),
    );
  }

  /// Light theme (future / system mode). Same primary green.
  static ThemeData light() {
    const colorScheme = ColorScheme.light(
      primary: AppColors.primary,
      onPrimary: AppColors.onPrimary,
      secondary: AppColors.lightBackground,
      onSecondary: AppColors.textOnLight,
      surface: Colors.white,
      onSurface: AppColors.textOnLight,
      onSurfaceVariant: AppColors.textMutedOnLight,
      outline: AppColors.primary,
      outlineVariant: Color(0xFFE2E8F0),
      error: AppColors.danger,
      onError: AppColors.onPrimary,
    );

    final interBase = GoogleFonts.interTextTheme(ThemeData.light().textTheme);
    final poppins = GoogleFonts.poppinsTextTheme(ThemeData.light().textTheme);

    final textTheme = TextTheme(
      displayLarge: poppins.displayLarge?.copyWith(
        color: AppColors.primary,
        fontWeight: FontWeight.w700,
      ),
      headlineSmall: poppins.headlineSmall?.copyWith(
        color: AppColors.textOnLight,
        fontWeight: FontWeight.w600,
      ),
      titleLarge: poppins.titleLarge?.copyWith(
        color: AppColors.textOnLight,
        fontWeight: FontWeight.w700,
      ),
      bodyLarge: interBase.bodyLarge?.copyWith(color: AppColors.textOnLight),
      bodyMedium: interBase.bodyMedium?.copyWith(color: AppColors.textOnLight),
      bodySmall:
          interBase.bodySmall?.copyWith(color: AppColors.textMutedOnLight),
    );

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: AppColors.lightBackground,
      textTheme: textTheme,
      primaryColor: AppColors.primary,
      appBarTheme: AppBarTheme(
        elevation: 0,
        backgroundColor: AppColors.lightBackground,
        foregroundColor: AppColors.textOnLight,
        titleTextStyle: GoogleFonts.poppins(
          fontSize: 20,
          fontWeight: FontWeight.w600,
          color: AppColors.textOnLight,
        ),
      ),
      cardTheme: CardThemeData(
        color: Colors.white,
        elevation: 2,
        shadowColor: Colors.black.withValues(alpha: 0.08),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusMd),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: AppColors.primary,
          foregroundColor: AppColors.onPrimary,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(radiusMd),
          ),
          minimumSize: const Size.fromHeight(52),
        ),
      ),
    );
  }
}

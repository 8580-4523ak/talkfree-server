import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'app_colors.dart';

abstract final class AppTheme {
  AppTheme._();

  static const double radiusMd = 18;
  static const double radiusLg = 22;

  /// Global neon accent — same as [ColorScheme.primary] in [darkTheme].
  static const Color neonGreen = AppColors.primary;

  /// Master scaffold / shell (premium dark #0B0B0F).
  static const Color darkBg = AppColors.darkBackground;

  /// Elevated list rows / cards (matches [ColorScheme.surface] in [darkTheme]).
  static const Color surfaceCard = AppColors.cardDark;

  /// Phone / VoIP — intro “calling” page, onboarding slide 2, empty recents.
  static const String lottiePhoneCall = 'assets/lottie/phone_call.json';

  /// World / coverage — onboarding “private lines”, intro map slide.
  static const String lottieGlobalMap = 'assets/lottie/global_map.json';

  /// Globe — onboarding “worldwide” hero.
  static const String lottieIntroGlobe = 'assets/lottie/intro_globe.json';

  /// Alerts / inbox empty state.
  static const String lottieAlertsBell = 'assets/lottie/alerts_notifications_bell.json';

  /// Success / verification (e.g. number claimed).
  static const String lottieGreenCheck = 'assets/lottie/green_check.json';

  /// Credits / Pro value (intro wallet slide, etc.).
  static const String lottieMoney = 'assets/lottie/money.json';

  /// Premium / rewards accent.
  static const String lottieFlyingMoney = 'assets/lottie/flying_money.json';

  /// TalkFree Pro subscription page — credits / value (clear on dark card).
  static const String lottieSubscriptionHero = 'assets/lottie/money.json';

  /// Onboarding SMS slide (slide 2) — same asset as [lottiePhoneCall].
  static const String lottieOnboardingNeon = 'assets/lottie/phone_call.json';

  /// Inbox empty — bell / notifications.
  static const String lottieInboxEmptyNeon =
      'assets/lottie/alerts_notifications_bell.json';

  /// Dark theme — neon green + deep black, Poppins headings + Inter body.
  static ThemeData dark() {
    const colorScheme = ColorScheme.dark(
      primary: AppColors.primary,
      onPrimary: AppColors.onPrimary,
      secondary: AppColors.primary,
      onSecondary: AppColors.darkBackground,
      surface: AppColors.cardDark,
      onSurface: AppColors.textOnDark,
      onSurfaceVariant: AppColors.textMutedOnDark,
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
        color: AppColors.textOnDark,
        fontWeight: FontWeight.w700,
      ),
      titleMedium: poppins.titleMedium?.copyWith(
        color: AppColors.textOnDark,
        fontWeight: FontWeight.w600,
      ),
      titleSmall: poppins.titleSmall?.copyWith(
        color: AppColors.textOnDark,
        fontWeight: FontWeight.w600,
      ),
      bodyLarge: interBase.bodyLarge?.copyWith(color: AppColors.textOnDark),
      bodyMedium:
          interBase.bodyMedium?.copyWith(color: AppColors.textOnDark),
      bodySmall: interBase.bodySmall?.copyWith(color: AppColors.textMutedOnDark),
      labelLarge: interBase.labelLarge?.copyWith(
        color: AppColors.primary,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.4,
      ),
      labelMedium:
          interBase.labelMedium?.copyWith(color: AppColors.textMutedOnDark),
      labelSmall:
          interBase.labelSmall?.copyWith(color: AppColors.textMutedOnDark),
    );

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: AppTheme.darkBg,
      textTheme: textTheme,
      primaryColor: AppColors.primary,
      dividerColor: AppColors.primary.withValues(alpha: 0.14),
      appBarTheme: AppBarTheme(
        elevation: 0,
        scrolledUnderElevation: 0,
        backgroundColor: AppTheme.darkBg,
        foregroundColor: AppColors.textOnDark,
        iconTheme: const IconThemeData(color: AppColors.textOnDark),
        titleTextStyle: GoogleFonts.poppins(
          fontSize: 20,
          fontWeight: FontWeight.w600,
          color: AppColors.textOnDark,
        ),
      ),
      cardTheme: CardThemeData(
        color: AppColors.cardDark,
        elevation: 0,
        shadowColor: Colors.black.withValues(alpha: 0.45),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusMd),
          side: BorderSide(
            color: Colors.white.withValues(alpha: 0.06),
            width: 1,
          ),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: AppColors.primary,
          foregroundColor: AppColors.darkBackground,
          disabledBackgroundColor: AppColors.primary.withValues(alpha: 0.35),
          disabledForegroundColor: AppColors.darkBackground.withValues(alpha: 0.5),
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
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.primary,
          foregroundColor: AppColors.darkBackground,
          textStyle: GoogleFonts.inter(
            fontWeight: FontWeight.w700,
            fontSize: 16,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 20),
        ),
      ),
      bottomNavigationBarTheme: BottomNavigationBarThemeData(
        backgroundColor: AppTheme.darkBg,
        selectedItemColor: AppColors.primary,
        unselectedItemColor: AppColors.textMutedOnDark.withValues(alpha: 0.55),
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
        backgroundColor: AppColors.cardDark,
        contentTextStyle: GoogleFonts.inter(
          color: AppColors.textOnDark,
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
      iconTheme: const IconThemeData(color: AppColors.textOnDark),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.cardDark,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(
            color: AppColors.primary,
            width: 1.5,
          ),
        ),
        labelStyle: GoogleFonts.inter(color: AppColors.textMutedOnDark),
        hintStyle: GoogleFonts.inter(color: AppColors.textMutedOnDark),
      ),
    );
  }

  /// Same as [dark] — use with [MaterialApp.darkTheme].
  static ThemeData get darkTheme => dark();

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

import 'package:flutter/material.dart';

import 'app_colors.dart';

/// Светлая и тёмная темы Material 3 в палитре Japandi.
class AppTheme {
  AppTheme._();

  // Раздел 5 ТЗ: 24/18/16/12, sans-serif
  static const String fontFamily = 'Roboto';

  static ThemeData light() {
    const scheme = ColorScheme(
      brightness: Brightness.light,
      primary: AppColors.gold,
      onPrimary: Colors.white,
      secondary: AppColors.goldAlt,
      onSecondary: Colors.white,
      error: AppColors.danger,
      onError: Colors.white,
      surface: AppColors.lightCard,
      onSurface: AppColors.lightText,
    );

    return _base(scheme, AppColors.lightBackground, AppColors.lightText,
        AppColors.lightSecondaryText);
  }

  static ThemeData dark() {
    const scheme = ColorScheme(
      brightness: Brightness.dark,
      primary: AppColors.goldAlt,
      onPrimary: Color(0xFF1F1B12),
      secondary: AppColors.gold,
      onSecondary: Color(0xFF1F1B12),
      error: AppColors.danger,
      onError: Colors.white,
      surface: AppColors.darkCard,
      onSurface: AppColors.darkText,
    );

    return _base(scheme, AppColors.darkBackground, AppColors.darkText,
        AppColors.darkSecondaryText);
  }

  static ThemeData _base(
    ColorScheme scheme,
    Color background,
    Color textColor,
    Color secondaryText,
  ) {
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: background,
      fontFamily: fontFamily,
      shadowColor: AppColors.shadow,
      appBarTheme: AppBarTheme(
        backgroundColor: background,
        foregroundColor: textColor,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(
          color: textColor,
          fontSize: 24,
          fontWeight: FontWeight.bold,
          fontFamily: fontFamily,
        ),
      ),
      // CardThemeData — начиная с Flutter 3.27 (раньше был CardTheme).
      cardTheme: CardThemeData(
        color: scheme.surface,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppColors.radiusCard),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: scheme.primary,
          foregroundColor: scheme.onPrimary,
          elevation: 1,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppColors.radiusButton),
          ),
          textStyle: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            fontFamily: fontFamily,
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(foregroundColor: scheme.primary),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: scheme.surface,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppColors.radiusCard),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppColors.radiusCard),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppColors.radiusCard),
          borderSide: const BorderSide(color: AppColors.gold, width: 1.5),
        ),
        hintStyle: TextStyle(color: secondaryText, fontSize: 16),
      ),
      dividerTheme: DividerThemeData(
        color: secondaryText.withValues(alpha: 0.15),
        thickness: 1,
        space: 1,
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: scheme.surface,
        indicatorColor: AppColors.goldSoft,
        labelTextStyle: WidgetStatePropertyAll(
          TextStyle(fontSize: 12, fontFamily: fontFamily),
        ),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith(
          (states) =>
              states.contains(WidgetState.selected) ? scheme.primary : null,
        ),
        trackColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? scheme.primary.withValues(alpha: 0.35)
              : null,
        ),
      ),
      textTheme: TextTheme(
        headlineMedium: TextStyle(
            fontSize: 24, fontWeight: FontWeight.bold, color: textColor),
        titleLarge: TextStyle(
            fontSize: 18, fontWeight: FontWeight.w500, color: textColor),
        bodyLarge: TextStyle(fontSize: 16, color: textColor),
        bodyMedium: TextStyle(fontSize: 14, color: textColor),
        bodySmall: TextStyle(fontSize: 12, color: secondaryText),
      ),
    );
  }
}

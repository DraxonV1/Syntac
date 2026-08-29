import 'package:flutter/material.dart';

import 'app_colors.dart';

/// Typography scale for the mobile coding environment.
/// Uses bundled Flutter/platform fonts only; no network font fetch at runtime.
abstract class AppTypography {
  static const _sansFamily = 'Roboto';
  static const _monoFamily = 'monospace';

  static TextStyle _sans({
    required double fontSize,
    required FontWeight fontWeight,
    required Color color,
    double? letterSpacing,
    required double height,
  }) => TextStyle(
    fontFamily: _sansFamily,
    fontSize: fontSize,
    fontWeight: fontWeight,
    color: color,
    letterSpacing: letterSpacing,
    height: height,
  );

  static TextStyle _monoText({
    required double fontSize,
    required FontWeight fontWeight,
    required Color color,
    required double height,
  }) => TextStyle(
    fontFamily: _monoFamily,
    fontSize: fontSize,
    fontWeight: fontWeight,
    color: color,
    height: height,
  );

  // Headings
  static TextStyle display = _sans(
    fontSize: 26,
    fontWeight: FontWeight.w700,
    color: AppColors.textPrimary,
    letterSpacing: -0.5,
    height: 1.25,
  );

  static TextStyle titleLarge = _sans(
    fontSize: 20,
    fontWeight: FontWeight.w600,
    color: AppColors.textPrimary,
    letterSpacing: -0.3,
    height: 1.3,
  );

  static TextStyle titleMedium = _sans(
    fontSize: 16,
    fontWeight: FontWeight.w600,
    color: AppColors.textPrimary,
    letterSpacing: -0.2,
    height: 1.35,
  );

  static TextStyle titleSmall = _sans(
    fontSize: 14,
    fontWeight: FontWeight.w600,
    color: AppColors.textPrimary,
    letterSpacing: -0.1,
    height: 1.4,
  );

  // Body Styles (400 regular)
  static TextStyle bodyLarge = _sans(
    fontSize: 15,
    fontWeight: FontWeight.w400,
    color: AppColors.textPrimary,
    height: 1.5,
  );

  static TextStyle bodyMedium = _sans(
    fontSize: 13.5,
    fontWeight: FontWeight.w400,
    color: AppColors.textPrimary,
    height: 1.45,
  );

  static TextStyle bodySmall = _sans(
    fontSize: 12,
    fontWeight: FontWeight.w400,
    color: AppColors.textSecondary,
    height: 1.4,
  );

  // Controls & Labels (500 medium)
  static TextStyle button = _sans(
    fontSize: 13.5,
    fontWeight: FontWeight.w500,
    color: AppColors.textPrimary,
    letterSpacing: 0.1,
    height: 1.3,
  );

  static TextStyle buttonSmall = _sans(
    fontSize: 12,
    fontWeight: FontWeight.w500,
    color: AppColors.textPrimary,
    letterSpacing: 0.1,
    height: 1.3,
  );

  static TextStyle label = _sans(
    fontSize: 11,
    fontWeight: FontWeight.w600,
    color: AppColors.textMuted,
    letterSpacing: 0.6,
    height: 1.25,
  );

  static TextStyle labelMedium = _sans(
    fontSize: 12,
    fontWeight: FontWeight.w500,
    color: AppColors.textSecondary,
    letterSpacing: 0.2,
    height: 1.25,
  );

  // Code & Terminal Styles
  static TextStyle code = _monoText(
    fontSize: 12.5,
    fontWeight: FontWeight.w400,
    color: AppColors.textPrimary,
    height: 1.45,
  );
  static TextStyle caption = bodySmall;
  static TextStyle mono = code;
  static TextStyle monoSmall = codeSmall;
  static TextStyle codeInline = codeSmall.copyWith(
    color: AppColors.primaryBright,
    backgroundColor: AppColors.surfaceFloating,
  );
  static TextStyle displayMedium = display.copyWith(fontSize: 22);

  static TextStyle codeSmall = _monoText(
    fontSize: 11,
    fontWeight: FontWeight.w400,
    color: AppColors.textSecondary,
    height: 1.4,
  );

  static TextStyle terminal = _monoText(
    fontSize: 11.5,
    fontWeight: FontWeight.w400,
    color: AppColors.textPrimary,
    height: 1.35,
  );

  /// Builds a complete TextTheme backed by offline platform fonts.
  static TextTheme textTheme() {
    return TextTheme(
      displayLarge: display,
      displayMedium: display.copyWith(fontSize: 22),
      displaySmall: titleLarge,
      headlineLarge: titleLarge,
      headlineMedium: titleMedium,
      headlineSmall: titleSmall,
      titleLarge: titleLarge,
      titleMedium: titleMedium,
      titleSmall: titleSmall,
      bodyLarge: bodyLarge,
      bodyMedium: bodyMedium,
      bodySmall: bodySmall,
      labelLarge: button,
      labelMedium: labelMedium,
      labelSmall: label,
    );
  }
}

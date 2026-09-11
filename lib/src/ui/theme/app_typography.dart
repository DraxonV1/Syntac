import 'package:flutter/material.dart';

import 'app_colors.dart';

/// Shared Jost typography scale for every Syntac surface.
abstract class AppTypography {
  static const _sansFamily = 'Jost';
  static const _monoFamily = 'Jost';

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

  // Getters keep text colors synchronized with active light/dark palette.
  static TextStyle get display => _sans(
    fontSize: 26,
    fontWeight: FontWeight.w700,
    color: AppColors.textPrimary,
    letterSpacing: -0.5,
    height: 1.25,
  );

  static TextStyle get titleLarge => _sans(
    fontSize: 20,
    fontWeight: FontWeight.w600,
    color: AppColors.textPrimary,
    letterSpacing: -0.3,
    height: 1.3,
  );

  static TextStyle get titleMedium => _sans(
    fontSize: 16,
    fontWeight: FontWeight.w600,
    color: AppColors.textPrimary,
    letterSpacing: -0.2,
    height: 1.35,
  );

  static TextStyle get titleSmall => _sans(
    fontSize: 14,
    fontWeight: FontWeight.w600,
    color: AppColors.textPrimary,
    letterSpacing: -0.1,
    height: 1.4,
  );

  static TextStyle get bodyLarge => _sans(
    fontSize: 15,
    fontWeight: FontWeight.w400,
    color: AppColors.textPrimary,
    height: 1.5,
  );

  static TextStyle get bodyMedium => _sans(
    fontSize: 13.5,
    fontWeight: FontWeight.w400,
    color: AppColors.textPrimary,
    height: 1.45,
  );

  static TextStyle get bodySmall => _sans(
    fontSize: 12,
    fontWeight: FontWeight.w400,
    color: AppColors.textSecondary,
    height: 1.4,
  );

  static TextStyle get button => _sans(
    fontSize: 13.5,
    fontWeight: FontWeight.w500,
    color: AppColors.textPrimary,
    letterSpacing: 0.1,
    height: 1.3,
  );

  static TextStyle get buttonSmall => _sans(
    fontSize: 12,
    fontWeight: FontWeight.w500,
    color: AppColors.textPrimary,
    letterSpacing: 0.1,
    height: 1.3,
  );

  static TextStyle get label => _sans(
    fontSize: 11,
    fontWeight: FontWeight.w600,
    color: AppColors.textMuted,
    letterSpacing: 0.6,
    height: 1.25,
  );

  static TextStyle get labelMedium => _sans(
    fontSize: 12,
    fontWeight: FontWeight.w500,
    color: AppColors.textSecondary,
    letterSpacing: 0.2,
    height: 1.25,
  );

  static TextStyle get code => _monoText(
    fontSize: 12.5,
    fontWeight: FontWeight.w400,
    color: AppColors.textPrimary,
    height: 1.45,
  );

  static TextStyle get caption => bodySmall;
  static TextStyle get mono => code;
  static TextStyle get monoSmall => codeSmall;
  static TextStyle get codeInline => codeSmall.copyWith(
    color: AppColors.primaryBright,
    backgroundColor: AppColors.surfaceFloating,
  );
  static TextStyle get displayMedium => display.copyWith(fontSize: 22);

  static TextStyle get codeSmall => _monoText(
    fontSize: 11,
    fontWeight: FontWeight.w400,
    color: AppColors.textSecondary,
    height: 1.4,
  );

  static TextStyle get terminal => _monoText(
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

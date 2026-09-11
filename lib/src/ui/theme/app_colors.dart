// Dynamic semantic palette shared by dark and light Material themes.

import 'package:flutter/material.dart';

abstract class AppColors {
  static bool lightMode = false;

  static Color get background => lightMode ? _lightBackground : _darkBackground;
  static Color get surface => lightMode ? _lightSurface : _darkSurface;
  static Color get surfaceStrong =>
      lightMode ? _lightSurfaceStrong : _darkSurfaceStrong;
  static Color get surfaceElevated =>
      lightMode ? _lightSurfaceElevated : _darkSurfaceElevated;
  static Color get surfaceFloating =>
      lightMode ? _lightSurfaceFloating : _darkSurfaceFloating;
  static Color get surfaceHighlight =>
      lightMode ? _lightSurfaceHighlight : _darkSurfaceHighlight;
  static Color get surfaceHigh =>
      lightMode ? _lightSurfaceHigh : _darkSurfaceHigh;

  static Color get glass => lightMode ? _lightGlass : _darkGlass;
  static Color get glassStrong =>
      lightMode ? _lightGlassStrong : _darkGlassStrong;
  static Color get glassCard => lightMode ? _lightGlassCard : _darkGlassCard;

  static const primary = Color(0xFF536DDA);
  static const primaryBright = Color(0xFF405CC8);
  static const primarySoft = Color(0xFF334AA5);
  static const accent = Color(0xFF536DDA);
  static const accentHover = Color(0xFF405CC8);
  static const accentSubtle = Color(0x28536DDA);
  static const accentText = Color(0xFF334AA5);

  static Color get borderSubtle =>
      lightMode ? const Color(0x24808CA8) : const Color(0x128296DC);
  static Color get textPrimary =>
      lightMode ? const Color(0xFF172033) : const Color(0xFFF8FAFF);
  static Color get textSecondary =>
      lightMode ? const Color(0xFF45546D) : const Color(0xFF9EA8B8);
  static Color get textMuted =>
      lightMode ? const Color(0xFF6D7890) : const Color(0xFF667085);
  static Color get textDisabled =>
      lightMode ? const Color(0xFFA3ACBC) : const Color(0xFF3B4455);

  static Color get border =>
      lightMode ? const Color(0x338296B2) : const Color(0x1F8296DC);
  static Color get borderSoft =>
      lightMode ? const Color(0x248296B2) : const Color(0x128296DC);
  static Color get borderActive =>
      lightMode ? const Color(0x99536DDA) : const Color(0x736E8CFF);
  static const borderFocus = Color(0xFF536DDA);

  static const success = Color(0xFF059669);
  static const successSubtle = Color(0x24059669);
  static const successText = Color(0xFF047857);
  static const warning = Color(0xFFD97706);
  static const warningSubtle = Color(0x24D97706);
  static const warningText = Color(0xFFB45309);
  static const error = Color(0xFFDC2626);
  static const errorSubtle = Color(0x24DC2626);
  static const errorText = Color(0xFFB91C1C);

  static Color get codeBackground =>
      lightMode ? const Color(0xFFF2F4F8) : const Color(0xFF030509);
  static Color get codeSurface =>
      lightMode ? const Color(0xFFFFFFFF) : const Color(0xFF080C14);
  static Color get codeBorder =>
      lightMode ? const Color(0x338296B2) : const Color(0x1F8296DC);
  static Color get codeHeader =>
      lightMode ? const Color(0xFFE8ECF3) : const Color(0xFF0B101A);
  static Color get codeKeyword =>
      lightMode ? const Color(0xFFA21CAF) : const Color(0xFFF472B6);
  static Color get codeString =>
      lightMode ? const Color(0xFF047857) : const Color(0xFF059669);
  static Color get codeNumber =>
      lightMode ? const Color(0xFFB45309) : const Color(0xFFD97706);
  static Color get codeComment => textMuted;
  static Color get codeVariable =>
      lightMode ? const Color(0xFF334AA5) : const Color(0xFF405CC8);

  static const _darkBackground = Color(0xFF05070C);
  static const _darkSurface = Color(0xFF080C14);
  static const _darkSurfaceStrong = Color(0xFF0D1420);
  static const _darkSurfaceElevated = Color(0xFF0F1726);
  static const _darkSurfaceFloating = Color(0xFF141F33);
  static const _darkSurfaceHighlight = Color(0xFF1B2842);
  static const _darkSurfaceHigh = Color(0xFF18243C);
  static const _darkGlass = Color(0x940E1524);
  static const _darkGlassStrong = Color(0xD10E1524);
  static const _darkGlassCard = Color(0x700E172A);

  static const _lightBackground = Color(0xFFF7F9FC);
  static const _lightSurface = Color(0xFFFFFFFF);
  static const _lightSurfaceStrong = Color(0xFFF0F3F8);
  static const _lightSurfaceElevated = Color(0xFFFFFFFF);
  static const _lightSurfaceFloating = Color(0xFFE7ECF7);
  static const _lightSurfaceHighlight = Color(0xFFDCE5FA);
  static const _lightSurfaceHigh = Color(0xFFE9EEF7);
  static const _lightGlass = Color(0xD9FFFFFF);
  static const _lightGlassStrong = Color(0xF2FFFFFF);
  static const _lightGlassCard = Color(0xCFFFFFFF);
}

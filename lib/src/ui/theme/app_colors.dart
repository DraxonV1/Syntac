import 'package:flutter/material.dart';

/// Semantic design tokens and palette for the premium mobile coding environment.
/// Almost-black background with layered glass surfaces and luminous blue accents.
abstract class AppColors {
  // Base Backgrounds & Surfaces
  static const Color background = Color(0xFF05070C);
  static const Color surface = Color(0xFF080C14);
  static const Color surfaceStrong = Color(0xFF0D1420);
  static const Color surfaceElevated = Color(0xFF0F1726);
  static const Color surfaceFloating = Color(0xFF141F33);
  static const Color surfaceHighlight = Color(0xFF1B2842);
  static const Color surfaceHigh = Color(0xFF18243C);

  // Glass Surfaces
  static const Color glass = Color(0x940E1524); // rgba(14, 21, 36, 0.58)
  static const Color glassStrong = Color(0xD10E1524); // rgba(14, 21, 36, 0.82)
  static const Color glassCard = Color(0x700E172A);

  // Primary & Accent Family
  static const Color primary = Color(0xFF6684FF);
  static const Color primaryBright = Color(0xFF91A7FF);
  static const Color primarySoft = Color(0xFFB8C5FF);
  static const Color accent = Color(0xFF6684FF);
  static const Color accentHover = Color(0xFF91A7FF);
  static const Color accentSubtle = Color(0x286684FF);
  static const Color accentText = Color(0xFFB8C5FF);

  static const Color borderSubtle = Color(0x128296DC);
  // Typography
  static const Color textPrimary = Color(0xFFF8FAFF);
  static const Color textSecondary = Color(0xFF9EA8B8);
  static const Color textMuted = Color(0xFF667085);
  static const Color textDisabled = Color(0xFF3B4455);

  // Borders & Dividers
  static const Color border = Color(0x1F8296DC); // rgba(130, 150, 220, 0.12)
  static const Color borderSoft = Color(0x128296DC);
  static const Color borderActive = Color(
    0x736E8CFF,
  ); // rgba(110, 140, 255, 0.45)
  static const Color borderFocus = Color(0xFF6684FF);

  // Status & Feedback Tokens (Restrained & Accessible)
  static const Color success = Color(0xFF10B981);
  static const Color successSubtle = Color(0x2410B981);
  static const Color successText = Color(0xFF6EE7B7);

  static const Color warning = Color(0xFFF59E0B);
  static const Color warningSubtle = Color(0x24F59E0B);
  static const Color warningText = Color(0xFFFCD34D);

  static const Color error = Color(0xFFEF4444);
  static const Color errorSubtle = Color(0x24EF4444);
  static const Color errorText = Color(0xFFFCA5A5);

  // Code & Terminal
  static const Color codeBackground = Color(0xFF030509);
  static const Color codeSurface = Color(0xFF080C14);
  static const Color codeBorder = Color(0x1F8296DC);
  static const Color codeHeader = Color(0xFF0B101A);
  static const Color codeKeyword = Color(0xFFF472B6);
  static const Color codeString = Color(0xFF34D399);
  static const Color codeNumber = Color(0xFFFBBF24);
  static const Color codeComment = Color(0xFF667085);
  static const Color codeVariable = Color(0xFF91A7FF);
}

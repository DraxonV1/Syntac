import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_typography.dart';

/// Renders terminal SGR colors and common text attributes without exposing
/// escape sequences in selectable chat output.
class AnsiText extends StatelessWidget {
  const AnsiText({super.key, required this.text, this.style});

  final String text;
  final TextStyle? style;

  static bool containsAnsi(String value) =>
      value.contains('\u001b[') || value.contains('\u001b]');

  @override
  Widget build(BuildContext context) {
    final baseStyle = style ?? AppTypography.monoSmall;
    return SelectableText.rich(
      TextSpan(style: baseStyle, children: _parse(text, baseStyle)),
    );
  }

  List<InlineSpan> _parse(String value, TextStyle baseStyle) {
    final spans = <InlineSpan>[];
    final buffer = StringBuffer();
    var foreground = baseStyle.color ?? AppColors.textPrimary;
    Color? background;
    var bold = baseStyle.fontWeight == FontWeight.bold;
    var italic = baseStyle.fontStyle == FontStyle.italic;
    var underline =
        baseStyle.decoration?.contains(TextDecoration.underline) ?? false;
    var inverse = false;

    void flush() {
      if (buffer.isEmpty) return;
      var spanForeground = foreground;
      var spanBackground = background;
      if (inverse) {
        spanForeground =
            spanBackground ?? baseStyle.color ?? AppColors.textPrimary;
        spanBackground = foreground;
      }
      spans.add(
        TextSpan(
          text: buffer.toString(),
          style: baseStyle.copyWith(
            color: spanForeground,
            backgroundColor: spanBackground,
            fontWeight: bold ? FontWeight.bold : baseStyle.fontWeight,
            fontStyle: italic ? FontStyle.italic : baseStyle.fontStyle,
            decoration: underline
                ? TextDecoration.underline
                : baseStyle.decoration,
          ),
        ),
      );
      buffer.clear();
    }

    void reset() {
      foreground = baseStyle.color ?? AppColors.textPrimary;
      background = null;
      bold = baseStyle.fontWeight == FontWeight.bold;
      italic = baseStyle.fontStyle == FontStyle.italic;
      underline =
          baseStyle.decoration?.contains(TextDecoration.underline) ?? false;
      inverse = false;
    }

    var index = 0;
    while (index < value.length) {
      final codeUnit = value.codeUnitAt(index);
      if (codeUnit != 0x1B) {
        if (codeUnit == 0x0D) {
          if (index + 1 >= value.length ||
              value.codeUnitAt(index + 1) != 0x0A) {
            index++;
            continue;
          }
        }
        if (codeUnit < 0x20 && codeUnit != 0x09 && codeUnit != 0x0A) {
          index++;
          continue;
        }
        buffer.writeCharCode(codeUnit);
        index++;
        continue;
      }

      if (index + 1 >= value.length) break;
      final next = value.codeUnitAt(index + 1);
      if (next == 0x5B) {
        final end = _csiEnd(value, index + 2);
        if (end == null) {
          index++;
          continue;
        }
        flush();
        final finalByte = value.codeUnitAt(end);
        if (finalByte == 0x6D) {
          _applySgr(
            value.substring(index + 2, end),
            onReset: reset,
            onForeground: (color) => foreground = color,
            onForegroundDefault: () =>
                foreground = baseStyle.color ?? AppColors.textPrimary,
            onBackground: (color) => background = color,
            onBold: (enabled) => bold = enabled,
            onItalic: (enabled) => italic = enabled,
            onUnderline: (enabled) => underline = enabled,
            onInverse: (enabled) => inverse = enabled,
          );
        }
        index = end + 1;
        continue;
      }
      if (next == 0x5D) {
        final end = _oscEnd(value, index + 2);
        if (end == null) {
          index++;
        } else {
          index = end;
        }
        continue;
      }
      index += 2;
    }
    flush();
    return spans;
  }

  int? _csiEnd(String value, int start) {
    for (var index = start; index < value.length; index++) {
      final codeUnit = value.codeUnitAt(index);
      if (codeUnit >= 0x40 && codeUnit <= 0x7E) return index;
    }
    return null;
  }

  int? _oscEnd(String value, int start) {
    for (var index = start; index < value.length; index++) {
      if (value.codeUnitAt(index) == 0x07) return index + 1;
      if (value.codeUnitAt(index) == 0x1B &&
          index + 1 < value.length &&
          value.codeUnitAt(index + 1) == 0x5C) {
        return index + 2;
      }
    }
    return null;
  }

  void _applySgr(
    String raw, {
    required VoidCallback onReset,
    required ValueChanged<Color> onForeground,
    required VoidCallback onForegroundDefault,
    required ValueChanged<Color?> onBackground,
    required ValueChanged<bool> onBold,
    required ValueChanged<bool> onItalic,
    required ValueChanged<bool> onUnderline,
    required ValueChanged<bool> onInverse,
  }) {
    final params = raw.isEmpty
        ? const <int>[0]
        : raw.split(';').map((part) => int.tryParse(part) ?? 0).toList();
    var index = 0;
    while (index < params.length) {
      final code = params[index++];
      switch (code) {
        case 0:
          onReset();
        case 1:
          onBold(true);
        case 3:
          onItalic(true);
        case 4:
          onUnderline(true);
        case 7:
          onInverse(true);
        case 22:
          onBold(false);
        case 23:
          onItalic(false);
        case 24:
          onUnderline(false);
        case 27:
          onInverse(false);
        case 39:
          onForegroundDefault();
        case 49:
          onBackground(null);
        case >= 30 && <= 37:
          onForeground(_ansiColor(code - 30, bright: false));
        case >= 40 && <= 47:
          onBackground(_ansiColor(code - 40, bright: false));
        case >= 90 && <= 97:
          onForeground(_ansiColor(code - 90, bright: true));
        case >= 100 && <= 107:
          onBackground(_ansiColor(code - 100, bright: true));
        case 38:
          final result = _extendedColor(params, index);
          if (result != null) {
            onForeground(result.color);
            index = result.nextIndex;
          }
        case 48:
          final result = _extendedColor(params, index);
          if (result != null) {
            onBackground(result.color);
            index = result.nextIndex;
          }
      }
    }
  }

  _AnsiColor? _extendedColor(List<int> params, int index) {
    if (index >= params.length) return null;
    final mode = params[index];
    if (mode == 5 && index + 1 < params.length) {
      return _AnsiColor(_paletteColor(params[index + 1]), index + 2);
    }
    if (mode == 2 && index + 3 < params.length) {
      return _AnsiColor(
        Color.fromARGB(
          0xFF,
          params[index + 1].clamp(0, 255).toInt(),
          params[index + 2].clamp(0, 255).toInt(),
          params[index + 3].clamp(0, 255).toInt(),
        ),
        index + 4,
      );
    }
    return null;
  }

  Color _ansiColor(int index, {required bool bright}) {
    const dark = <Color>[
      Color(0xFF5C6370),
      Color(0xFFE06C75),
      Color(0xFF98C379),
      Color(0xFFE5C07B),
      Color(0xFF61AFEF),
      Color(0xFFC678DD),
      Color(0xFF56B6C2),
      Color(0xFFABB2BF),
    ];
    const light = <Color>[
      Color(0xFF000000),
      Color(0xFFB91C1C),
      Color(0xFF047857),
      Color(0xFFB45309),
      Color(0xFF1D4ED8),
      Color(0xFF86198F),
      Color(0xFF0E7490),
      Color(0xFF374151),
    ];
    final palette = AppColors.lightMode ? light : dark;
    final brightPalette = AppColors.lightMode
        ? const <Color>[
            Color(0xFF4B5563),
            Color(0xFFDC2626),
            Color(0xFF059669),
            Color(0xFFD97706),
            Color(0xFF2563EB),
            Color(0xFFA21CAF),
            Color(0xFF0891B2),
            Color(0xFF111827),
          ]
        : const <Color>[
            Color(0xFF9CA3AF),
            Color(0xFFFF7B86),
            Color(0xFFB5F4A2),
            Color(0xFFFFD68A),
            Color(0xFF8CC7FF),
            Color(0xFFE2A7F4),
            Color(0xFF8DE8F2),
            Color(0xFFF3F4F6),
          ];
    return (bright ? brightPalette : palette)[index.clamp(0, 7).toInt()];
  }

  Color _paletteColor(int index) {
    if (index < 16) {
      return _ansiColor(index % 8, bright: index >= 8);
    }
    if (index >= 232) {
      final value = 8 + (index - 232) * 10;
      return Color.fromARGB(0xFF, value, value, value);
    }
    final adjusted = index - 16;
    final red = adjusted ~/ 36;
    final green = (adjusted % 36) ~/ 6;
    final blue = adjusted % 6;
    int channel(int value) => value == 0 ? 0 : 55 + value * 40;
    return Color.fromARGB(0xFF, channel(red), channel(green), channel(blue));
  }
}

class _AnsiColor {
  const _AnsiColor(this.color, this.nextIndex);

  final Color color;
  final int nextIndex;
}

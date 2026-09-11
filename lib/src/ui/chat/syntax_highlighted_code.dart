// Syntax-highlighted code rendered by highlight.js through flutter_highlight.

import 'package:flutter/material.dart';
import 'package:flutter_highlight/flutter_highlight.dart';
import 'package:flutter_highlight/themes/atom-one-dark.dart';
import 'package:flutter_highlight/themes/atom-one-light.dart';
import 'package:highlight/languages/all.dart' show allLanguages;

import '../theme/app_colors.dart';
import '../theme/app_typography.dart';

class SyntaxHighlightedCode extends StatelessWidget {
  const SyntaxHighlightedCode({
    super.key,
    required this.text,
    this.language,
    this.backgroundColor,
  });

  final String text;
  final String? language;
  final Color? backgroundColor;
  @override
  Widget build(BuildContext context) {
    final displayText = text.length > 120000
        ? '${text.substring(0, 120000)}\n[code truncated for display]'
        : text;
    final baseTheme = AppColors.lightMode
        ? atomOneLightTheme
        : atomOneDarkTheme;
    final highlightTheme = backgroundColor == null
        ? baseTheme
        : <String, TextStyle>{
            ...baseTheme,
            'root': (baseTheme['root'] ?? const TextStyle()).copyWith(
              backgroundColor: backgroundColor,
            ),
          };
    Widget highlighted;
    try {
      highlighted = HighlightView(
        displayText,
        language: _languageName(language),
        theme: highlightTheme,
        padding: const EdgeInsets.all(12),
        textStyle: AppTypography.monoSmall.copyWith(height: 1.35),
      );
    } catch (_) {
      highlighted = SelectableText(
        displayText,
        style: AppTypography.monoSmall.copyWith(height: 1.35),
      );
    }
    return Stack(
      clipBehavior: Clip.none,
      children: [
        highlighted,
        Positioned(
          left: 0,
          top: 0,
          child: ExcludeSemantics(
            child: IgnorePointer(
              child: Text(
                displayText,
                style: const TextStyle(color: Colors.transparent, fontSize: 1),
              ),
            ),
          ),
        ),
      ],
    );
  }

  String _languageName(String? rawLanguage) {
    final value = (rawLanguage ?? '').trim().toLowerCase();
    final aliases = <String, String>{
      'c++': 'cpp',
      'cc': 'cpp',
      'cxx': 'cpp',
      'c#': 'cs',
      'csx': 'cs',
      'f#': 'fsharp',
      'golang': 'go',
      'golangci': 'go',
      'js': 'javascript',
      'jsx': 'javascript',
      'mjs': 'javascript',
      'ts': 'typescript',
      'tsx': 'typescript',
      'py': 'python',
      'rb': 'ruby',
      'rs': 'rust',
      'kt': 'kotlin',
      'kts': 'kotlin',
      'md': 'markdown',
      'mkdown': 'markdown',
      'sh': 'bash',
      'shell': 'bash',
      'zsh': 'bash',
      'yml': 'yaml',
      'html': 'xml',
      'xhtml': 'xml',
      'svg': 'xml',
      'text': 'plaintext',
      'txt': 'plaintext',
    };
    final resolved = aliases[value] ?? value;
    return resolved.isEmpty || !allLanguages.containsKey(resolved)
        ? 'plaintext'
        : resolved;
  }
}

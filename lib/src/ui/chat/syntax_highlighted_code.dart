// Syntax-highlighted code rendered by highlight.js through flutter_highlight.

import 'package:flutter/material.dart';
import 'package:flutter_highlight/flutter_highlight.dart';
import 'package:flutter_highlight/themes/atom-one-dark.dart';

import '../theme/app_typography.dart';

class SyntaxHighlightedCode extends StatelessWidget {
  const SyntaxHighlightedCode({super.key, required this.text, this.language});

  final String text;
  final String? language;

  @override
  Widget build(BuildContext context) {
    final displayText = text.length > 120000
        ? '${text.substring(0, 120000)}\n[code truncated for display]'
        : text;
    Widget highlighted;
    try {
      highlighted = HighlightView(
        displayText,
        language: _languageName(language),
        theme: atomOneDarkTheme,
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
    return switch (value) {
      'js' => 'javascript',
      'ts' => 'typescript',
      'py' => 'python',
      'sh' || 'shell' => 'bash',
      'yml' => 'yaml',
      _ => value.isEmpty ? 'plaintext' : value,
    };
  }
}

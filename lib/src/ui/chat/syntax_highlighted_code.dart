// Fast, dependency-free syntax colors for common code and shell languages.

import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_typography.dart';

class SyntaxHighlightedCode extends StatelessWidget {
  const SyntaxHighlightedCode({super.key, required this.text, this.language});

  final String text;
  final String? language;

  @override
  Widget build(BuildContext context) {
    final base = AppTypography.monoSmall.copyWith(
      color: AppColors.textPrimary,
      height: 1.35,
    );
    return SelectableText.rich(TextSpan(style: base, children: _spans(base)));
  }

  List<TextSpan> _spans(TextStyle base) {
    if (text.length > 120000) return [TextSpan(text: text)];
    final keywords = _keywordsFor(language);
    final pattern = RegExp(
      r'''(//[^\n]*|#[^\n]*|--[^\n]*|/\*[\s\S]*?\*/|"(?:\\.|[^"\\])*"|'(?:\\.|[^'\\])*'|\b\d+(?:\.\d+)?\b|\b[A-Za-z_][A-Za-z0-9_]*\b)''',
      multiLine: true,
    );
    final spans = <TextSpan>[];
    var cursor = 0;
    for (final match in pattern.allMatches(text)) {
      if (match.start > cursor) {
        spans.add(TextSpan(text: text.substring(cursor, match.start)));
      }
      final token = match.group(0)!;
      final color =
          token.startsWith('//') ||
              token.startsWith('#') ||
              token.startsWith('--') ||
              token.startsWith('/*')
          ? AppColors.textMuted
          : token.startsWith('"') || token.startsWith("'")
          ? AppColors.warningText
          : RegExp(r'^\d').hasMatch(token)
          ? AppColors.accentText
          : keywords.contains(token)
          ? AppColors.accentText
          : null;
      spans.add(
        TextSpan(
          text: token,
          style: color == null ? null : base.copyWith(color: color),
        ),
      );
      cursor = match.end;
    }
    if (cursor < text.length) spans.add(TextSpan(text: text.substring(cursor)));
    return spans;
  }

  Set<String> _keywordsFor(String? rawLanguage) {
    final language = (rawLanguage ?? '')
        .toLowerCase()
        .split(RegExp(r'[^a-z0-9+#-]'))
        .first;
    return switch (language) {
      'dart' ||
      'java' ||
      'kotlin' ||
      'swift' ||
      'c' ||
      'cpp' ||
      'rust' => _commonKeywords,
      'js' || 'javascript' || 'ts' || 'typescript' => _commonKeywords,
      'python' || 'py' || 'bash' || 'sh' || 'shell' || 'zsh' => _scriptKeywords,
      'json' || 'yaml' || 'yml' || 'toml' => <String>{'true', 'false', 'null'},
      _ => <String>{},
    };
  }

  static const _commonKeywords = <String>{
    'abstract',
    'as',
    'async',
    'await',
    'break',
    'case',
    'catch',
    'class',
    'const',
    'continue',
    'default',
    'do',
    'else',
    'enum',
    'extends',
    'final',
    'finally',
    'for',
    'from',
    'fun',
    'if',
    'implements',
    'import',
    'in',
    'interface',
    'is',
    'late',
    'let',
    'new',
    'null',
    'override',
    'private',
    'protected',
    'public',
    'return',
    'static',
    'super',
    'switch',
    'this',
    'throw',
    'try',
    'var',
    'void',
    'while',
    'with',
    'yield',
    'true',
    'false',
  };

  static const _scriptKeywords = <String>{
    'case',
    'do',
    'elif',
    'else',
    'esac',
    'fi',
    'for',
    'function',
    'if',
    'in',
    'import',
    'def',
    'from',
    'None',
    'not',
    'or',
    'return',
    'then',
    'True',
    'False',
    'try',
    'while',
    'with',
    'until',
    'done',
  };
}

// Lightweight markdown renderer for code blocks, images, Unicode, and inline math.

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_math_fork/flutter_math.dart';
import 'package:flutter/services.dart';
import '../theme/app_colors.dart';
import '../theme/app_typography.dart';
import 'syntax_highlighted_code.dart';

/// Renders bounded agent markdown with code, image, and math support.
class MarkdownContent extends StatelessWidget {
  const MarkdownContent({
    super.key,
    required this.content,
    this.textStyle,
    this.monochrome = false,
    this.streaming = false,
  });

  final String content;
  final TextStyle? textStyle;
  final bool monochrome;
  final bool streaming;
  static final _blockCache = <String, List<_MarkdownBlock>>{};
  static const maxRichCharacters = 100000;
  static const maxBlocks = 400;

  @override
  Widget build(BuildContext context) {
    if (content.isEmpty) return const SizedBox.shrink();
    final displayContent = content.length <= maxRichCharacters
        ? content
        : '${content.substring(0, maxRichCharacters)}\n\n'
              '[content truncated for display; full message remains available]';
    final baseStyle = textStyle ?? AppTypography.bodyMedium;
    if (streaming || content.length > maxRichCharacters) {
      return SelectableText(displayContent, style: baseStyle);
    }

    final blocks = _blockCache[displayContent] ??= _parseBlocks(displayContent);
    if (_blockCache.length > 32) {
      _blockCache.remove(_blockCache.keys.first);
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < blocks.length; i++) ...[
          if (i > 0) const SizedBox(height: 10),
          _renderBlock(context, blocks[i]),
        ],
      ],
    );
  }

  Widget _renderBlock(BuildContext context, _MarkdownBlock block) {
    return switch (block) {
      _CodeBlock(:final language, :final code) => _CodeBlockWidget(
        language: language,
        code: code,
        monochrome: monochrome,
      ),
      _HeadingBlock(:final level, :final text) => _renderHeading(level, text),
      _ListBlock(:final items, :final isOrdered) => _renderList(
        items,
        isOrdered,
      ),
      _QuoteBlock(:final text) => _renderQuote(text),
      _ParagraphBlock(:final text) => _renderParagraph(text),
    };
  }

  Widget _renderHeading(int level, String text) {
    final style = switch (level) {
      1 => AppTypography.displayMedium.copyWith(fontSize: 18),
      2 => AppTypography.titleLarge.copyWith(fontSize: 16),
      3 => AppTypography.titleMedium.copyWith(fontSize: 14),
      _ => AppTypography.titleSmall,
    };
    return Padding(
      padding: const EdgeInsets.only(top: 6, bottom: 2),
      child: _InlineMarkdownText(
        text: text,
        baseStyle: style.copyWith(
          color: monochrome ? AppColors.textMuted : AppColors.textPrimary,
        ),
        monochrome: monochrome,
      ),
    );
  }

  Widget _renderList(List<String> items, bool isOrdered) {
    return Padding(
      padding: const EdgeInsets.only(left: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (var i = 0; i < items.length; i++) ...[
            if (i > 0) const SizedBox(height: 4),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: isOrdered ? 20 : 14,
                  child: Text(
                    isOrdered ? '${i + 1}.' : '•',
                    style: AppTypography.bodyMedium.copyWith(
                      color: AppColors.textMuted,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                Expanded(
                  child: _InlineMarkdownText(
                    text: items[i],
                    baseStyle: textStyle ?? AppTypography.bodyMedium,
                    monochrome: monochrome,
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _renderQuote(String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: const BorderRadius.only(
          topRight: Radius.circular(6),
          bottomRight: Radius.circular(6),
        ),
        border: Border(left: BorderSide(color: AppColors.accent, width: 3)),
      ),
      child: _InlineMarkdownText(
        text: text,
        baseStyle: (textStyle ?? AppTypography.bodyMedium).copyWith(
          color: monochrome ? AppColors.textMuted : AppColors.textSecondary,
          fontStyle: FontStyle.italic,
        ),
        monochrome: monochrome,
      ),
    );
  }

  Widget _renderParagraph(String text) {
    return _InlineMarkdownText(
      text: text,
      baseStyle: textStyle ?? AppTypography.bodyMedium,
      monochrome: monochrome,
    );
  }

  List<_MarkdownBlock> _parseBlocks(String input) {
    final blocks = <_MarkdownBlock>[];
    final lines = input.split('\n');
    var i = 0;

    while (i < lines.length) {
      if (blocks.length >= maxBlocks) {
        return [_ParagraphBlock(text: input)];
      }
      final line = lines[i];

      // Code Block start
      if (line.trim().startsWith('```')) {
        final language = line.trim().substring(3).trim();
        final codeLines = <String>[];
        i++;
        while (i < lines.length && !lines[i].trim().startsWith('```')) {
          codeLines.add(lines[i]);
          i++;
        }
        if (i < lines.length) i++; // skip closing ```
        blocks.add(_CodeBlock(language: language, code: codeLines.join('\n')));
        continue;
      }

      // Headings
      if (line.startsWith('#')) {
        final match = RegExp(r'^(#{1,6})\s+(.*)$').firstMatch(line);
        if (match != null) {
          final level = match.group(1)!.length;
          final text = match.group(2)!.trim();
          blocks.add(_HeadingBlock(level: level, text: text));
          i++;
          continue;
        }
      }

      // Blockquotes
      if (line.startsWith('>')) {
        final quoteLines = <String>[];
        while (i < lines.length &&
            lines[i].startsWith('>') &&
            quoteLines.length < 100) {
          quoteLines.add(lines[i].substring(1).trim());
          i++;
        }
        while (i < lines.length && lines[i].startsWith('>')) {
          i++;
        }
        blocks.add(_QuoteBlock(text: quoteLines.join('\n')));
        continue;
      }

      // Unordered list items (- or * or +)
      if (RegExp(r'^\s*[-*+]\s+').hasMatch(line)) {
        final listItems = <String>[];
        while (i < lines.length &&
            RegExp(r'^\s*[-*+]\s+').hasMatch(lines[i]) &&
            listItems.length < 200) {
          final clean = lines[i].replaceFirst(RegExp(r'^\s*[-*+]\s+'), '');
          listItems.add(clean);
          i++;
        }
        while (i < lines.length && RegExp(r'^\s*[-*+]\s+').hasMatch(lines[i])) {
          i++;
        }
        blocks.add(_ListBlock(items: listItems, isOrdered: false));
        continue;
      }

      // Ordered list items (1. 2. etc)
      if (RegExp(r'^\s*\d+\.\s+').hasMatch(line)) {
        final listItems = <String>[];
        while (i < lines.length &&
            RegExp(r'^\s*\d+\.\s+').hasMatch(lines[i]) &&
            listItems.length < 200) {
          final clean = lines[i].replaceFirst(RegExp(r'^\s*\d+\.\s+'), '');
          listItems.add(clean);
          i++;
        }
        while (i < lines.length && RegExp(r'^\s*\d+\.\s+').hasMatch(lines[i])) {
          i++;
        }
        blocks.add(_ListBlock(items: listItems, isOrdered: true));
        continue;
      }

      // Paragraph / Plain text
      if (line.trim().isNotEmpty) {
        final paragraphLines = <String>[];
        while (i < lines.length &&
            lines[i].trim().isNotEmpty &&
            !lines[i].trim().startsWith('```') &&
            !lines[i].startsWith('#') &&
            !lines[i].startsWith('>') &&
            !RegExp(r'^\s*[-*+]\s+').hasMatch(lines[i]) &&
            !RegExp(r'^\s*\d+\.\s+').hasMatch(lines[i])) {
          paragraphLines.add(lines[i]);
          i++;
        }
        blocks.add(_ParagraphBlock(text: paragraphLines.join('\n')));
        continue;
      }

      i++;
    }

    return blocks;
  }
}

class _CodeBlockWidget extends StatelessWidget {
  const _CodeBlockWidget({
    required this.language,
    required this.code,
    required this.monochrome,
  });

  final String language;
  final String code;
  final bool monochrome;

  @override
  Widget build(BuildContext context) {
    final langLabel = language.trim().isEmpty ? 'text' : language.trim();

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.codeBackground,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.codeBorder, width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Code Header Bar
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: AppColors.codeHeader,
              borderRadius: BorderRadius.vertical(top: Radius.circular(7)),
              border: Border(
                bottom: BorderSide(color: AppColors.codeBorder, width: 1),
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  langLabel,
                  style: AppTypography.monoSmall.copyWith(
                    color: AppColors.textMuted,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                InkWell(
                  onTap: () {
                    Clipboard.setData(ClipboardData(text: code));
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Code copied to clipboard'),
                        duration: Duration(seconds: 1),
                      ),
                    );
                  },
                  borderRadius: BorderRadius.circular(4),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 2,
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.copy_rounded,
                          size: 12,
                          color: AppColors.textMuted,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          'Copy',
                          style: AppTypography.monoSmall.copyWith(
                            color: AppColors.textMuted,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          // Code Content
          SingleChildScrollView(
            scrollDirection: Axis.vertical,
            padding: const EdgeInsets.all(12),
            child: monochrome
                ? SelectableText(
                    code,
                    style: AppTypography.monoSmall.copyWith(
                      color: AppColors.textMuted,
                      height: 1.35,
                    ),
                  )
                : SyntaxHighlightedCode(text: code, language: langLabel),
          ),
        ],
      ),
    );
  }
}

/// Renders inline markdown formatting: bold, italic, inline `code`.
class _InlineMarkdownText extends StatelessWidget {
  const _InlineMarkdownText({
    required this.text,
    required this.baseStyle,
    required this.monochrome,
  });

  final String text;
  final TextStyle baseStyle;
  final bool monochrome;
  @override
  Widget build(BuildContext context) {
    final spans = _parseInlineSpans(text, baseStyle);
    return SelectableText.rich(TextSpan(children: spans));
  }

  List<InlineSpan> _parseInlineSpans(String text, TextStyle base) {
    if (text.length > 12000) {
      return [TextSpan(text: text, style: base)];
    }
    final spans = <InlineSpan>[];
    final pattern = RegExp(
      r'(!\[[^\]]*\]\([^)]+\)|(?:https?://|data:image/)[^\s]+|\$[^$\n]+\$|\\\([^)]+\)|`[^`]+`|\*\*[^*]+\*\*|\*[^*]+\*)',
    );
    var lastIndex = 0;
    var matchCount = 0;

    for (final match in pattern.allMatches(text)) {
      matchCount++;
      if (matchCount > 200) {
        return [TextSpan(text: text, style: base)];
      }
      if (match.start > lastIndex) {
        spans.add(
          TextSpan(text: text.substring(lastIndex, match.start), style: base),
        );
      }

      final matchedText = match.group(0)!;
      final imageUrl = _imageUrlFromMarkdown(matchedText);
      if (imageUrl != null) {
        spans.add(
          WidgetSpan(
            alignment: PlaceholderAlignment.middle,
            child: _buildInlineImage(imageUrl),
          ),
        );
      } else if (matchedText.startsWith('\$') ||
          matchedText.startsWith(r'\(')) {
        final math = matchedText.startsWith('\$')
            ? matchedText.substring(1, matchedText.length - 1)
            : matchedText.substring(2, matchedText.length - 2);
        spans.add(
          WidgetSpan(
            alignment: PlaceholderAlignment.middle,
            child: _SafeMath(expression: math, style: base),
          ),
        );
      } else if (matchedText.startsWith('`') && matchedText.endsWith('`')) {
        final code = matchedText.substring(1, matchedText.length - 1);
        spans.add(
          WidgetSpan(
            alignment: PlaceholderAlignment.middle,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
              margin: const EdgeInsets.symmetric(horizontal: 2),
              decoration: BoxDecoration(
                color: AppColors.surfaceHigh,
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: AppColors.border, width: 0.8),
              ),
              child: Text(
                code,
                style: AppTypography.codeInline.copyWith(
                  color: monochrome
                      ? (base.color ?? AppColors.textMuted)
                      : null,
                ),
              ),
            ),
          ),
        );
      } else if (matchedText.startsWith('**') && matchedText.endsWith('**')) {
        spans.add(
          TextSpan(
            text: matchedText.substring(2, matchedText.length - 2),
            style: base.copyWith(
              fontWeight: FontWeight.w600,
              color: monochrome
                  ? (base.color ?? AppColors.textMuted)
                  : AppColors.textPrimary,
            ),
          ),
        );
      } else if (matchedText.startsWith('*') && matchedText.endsWith('*')) {
        spans.add(
          TextSpan(
            text: matchedText.substring(1, matchedText.length - 1),
            style: base.copyWith(fontStyle: FontStyle.italic),
          ),
        );
      } else {
        spans.add(TextSpan(text: matchedText, style: base));
      }
      lastIndex = match.end;
    }

    if (lastIndex < text.length) {
      spans.add(TextSpan(text: text.substring(lastIndex), style: base));
    }
    return spans;
  }

  String? _imageUrlFromMarkdown(String value) {
    if (value.startsWith('![')) {
      final match = RegExp(r'^!\[[^\]]*\]\(([^)]+)\)$').firstMatch(value);
      return match?.group(1);
    }
    if (value.startsWith('data:image/')) return value;
    if (RegExp(
      r'^https?://[^\s?#]+\.(?:png|jpe?g|gif|webp|bmp|svg|avif|heic|heif|tiff?|ico)(?:[?#].*)?$',
      caseSensitive: false,
    ).hasMatch(value)) {
      return value;
    }
    return null;
  }

  Widget _buildInlineImage(String source) {
    if (source.length > 4_200_000) {
      return _imageFallback('Image too large to preview');
    }
    try {
      final image = source.startsWith('data:image/')
          ? _decodeDataImage(source)
          : Image.network(
              source,
              fit: BoxFit.contain,
              errorBuilder: (context, error, stackTrace) =>
                  _imageFallback(source),
            );
      return Container(
        constraints: const BoxConstraints(maxWidth: 260, maxHeight: 200),
        margin: const EdgeInsets.symmetric(horizontal: 3, vertical: 4),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: AppColors.border),
        ),
        clipBehavior: Clip.antiAlias,
        child: image,
      );
    } catch (_) {
      return _imageFallback('Invalid image');
    }
  }

  Widget _decodeDataImage(String source) {
    try {
      final comma = source.indexOf(',');
      if (comma < 0) return _imageFallback('Invalid image data');
      final header = source.substring(0, comma);
      final payload = source.substring(comma + 1);
      if (!header.endsWith(';base64')) {
        return _imageFallback('Unsupported image data');
      }
      if (payload.length > 4_200_000) {
        return _imageFallback('Image too large to preview');
      }
      return Image.memory(
        base64Decode(payload),
        fit: BoxFit.contain,
        errorBuilder: (context, error, stackTrace) =>
            _imageFallback('Invalid image data'),
      );
    } catch (_) {
      return _imageFallback('Invalid image data');
    }
  }

  Widget _imageFallback(String label) => Padding(
    padding: const EdgeInsets.all(8),
    child: Text(
      label,
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
      style: AppTypography.caption.copyWith(color: AppColors.textMuted),
    ),
  );
}

class _SafeMath extends StatelessWidget {
  const _SafeMath({required this.expression, required this.style});

  final String expression;
  final TextStyle style;

  @override
  Widget build(BuildContext context) {
    if (expression.length > 4096) {
      return Text(expression, style: style);
    }
    try {
      return Math.tex(
        expression,
        mathStyle: MathStyle.text,
        textStyle: style,
        onErrorFallback: (_) => Text(expression, style: style),
      );
    } catch (_) {
      return Text(expression, style: style);
    }
  }
}

// Data classes for markdown blocks
sealed class _MarkdownBlock {}

class _CodeBlock extends _MarkdownBlock {
  _CodeBlock({required this.language, required this.code});
  final String language;
  final String code;
}

class _HeadingBlock extends _MarkdownBlock {
  _HeadingBlock({required this.level, required this.text});
  final int level;
  final String text;
}

class _ListBlock extends _MarkdownBlock {
  _ListBlock({required this.items, required this.isOrdered});
  final List<String> items;
  final bool isOrdered;
}

class _QuoteBlock extends _MarkdownBlock {
  _QuoteBlock({required this.text});
  final String text;
}

class _ParagraphBlock extends _MarkdownBlock {
  _ParagraphBlock({required this.text});
  final String text;
}

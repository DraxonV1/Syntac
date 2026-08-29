import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../theme/app_colors.dart';
import '../theme/app_typography.dart';

/// Clean, high-performance markdown renderer tailored for coding agent outputs.
class MarkdownContent extends StatelessWidget {
  const MarkdownContent({super.key, required this.content, this.textStyle});

  final String content;
  final TextStyle? textStyle;

  @override
  Widget build(BuildContext context) {
    if (content.isEmpty) return const SizedBox.shrink();

    final blocks = _parseBlocks(content);
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
      child: Text(text, style: style),
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
      decoration: const BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.only(
          topRight: Radius.circular(6),
          bottomRight: Radius.circular(6),
        ),
        border: Border(left: BorderSide(color: AppColors.accent, width: 3)),
      ),
      child: _InlineMarkdownText(
        text: text,
        baseStyle: (textStyle ?? AppTypography.bodyMedium).copyWith(
          color: AppColors.textSecondary,
          fontStyle: FontStyle.italic,
        ),
      ),
    );
  }

  Widget _renderParagraph(String text) {
    return _InlineMarkdownText(
      text: text,
      baseStyle: textStyle ?? AppTypography.bodyMedium,
    );
  }

  List<_MarkdownBlock> _parseBlocks(String input) {
    final blocks = <_MarkdownBlock>[];
    final lines = input.split('\n');
    var i = 0;

    while (i < lines.length) {
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
        while (i < lines.length && lines[i].startsWith('>')) {
          quoteLines.add(lines[i].substring(1).trim());
          i++;
        }
        blocks.add(_QuoteBlock(text: quoteLines.join('\n')));
        continue;
      }

      // Unordered list items (- or * or +)
      if (RegExp(r'^\s*[-*+]\s+').hasMatch(line)) {
        final listItems = <String>[];
        while (i < lines.length && RegExp(r'^\s*[-*+]\s+').hasMatch(lines[i])) {
          final clean = lines[i].replaceFirst(RegExp(r'^\s*[-*+]\s+'), '');
          listItems.add(clean);
          i++;
        }
        blocks.add(_ListBlock(items: listItems, isOrdered: false));
        continue;
      }

      // Ordered list items (1. 2. etc)
      if (RegExp(r'^\s*\d+\.\s+').hasMatch(line)) {
        final listItems = <String>[];
        while (i < lines.length && RegExp(r'^\s*\d+\.\s+').hasMatch(lines[i])) {
          final clean = lines[i].replaceFirst(RegExp(r'^\s*\d+\.\s+'), '');
          listItems.add(clean);
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

/// Standalone code block with syntax badge and copy action.
class _CodeBlockWidget extends StatelessWidget {
  const _CodeBlockWidget({required this.language, required this.code});

  final String language;
  final String code;

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
            decoration: const BoxDecoration(
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
                        const Icon(
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
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.all(12),
            child: SelectableText(
              code,
              style: AppTypography.mono.copyWith(fontSize: 12.5, height: 1.45),
            ),
          ),
        ],
      ),
    );
  }
}

/// Renders inline markdown formatting: bold, italic, inline `code`.
class _InlineMarkdownText extends StatelessWidget {
  const _InlineMarkdownText({required this.text, required this.baseStyle});

  final String text;
  final TextStyle baseStyle;

  @override
  Widget build(BuildContext context) {
    final spans = _parseInlineSpans(text, baseStyle);
    return SelectableText.rich(TextSpan(children: spans));
  }

  List<InlineSpan> _parseInlineSpans(String text, TextStyle base) {
    final spans = <InlineSpan>[];
    // Regex for inline code `...`, bold **...**, italic *...*
    final pattern = RegExp(r'(`[^`]+`|\*\*[^*]+\*\*|\*[^*]+\*)');
    var lastIndex = 0;

    for (final match in pattern.allMatches(text)) {
      if (match.start > lastIndex) {
        spans.add(
          TextSpan(text: text.substring(lastIndex, match.start), style: base),
        );
      }

      final matchedText = match.group(0)!;
      if (matchedText.startsWith('`') && matchedText.endsWith('`')) {
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
              child: Text(code, style: AppTypography.codeInline),
            ),
          ),
        );
      } else if (matchedText.startsWith('**') && matchedText.endsWith('**')) {
        final bold = matchedText.substring(2, matchedText.length - 2);
        spans.add(
          TextSpan(
            text: bold,
            style: base.copyWith(
              fontWeight: FontWeight.w600,
              color: AppColors.textPrimary,
            ),
          ),
        );
      } else if (matchedText.startsWith('*') && matchedText.endsWith('*')) {
        final italic = matchedText.substring(1, matchedText.length - 1);
        spans.add(
          TextSpan(
            text: italic,
            style: base.copyWith(fontStyle: FontStyle.italic),
          ),
        );
      }

      lastIndex = match.end;
    }

    if (lastIndex < text.length) {
      spans.add(TextSpan(text: text.substring(lastIndex), style: base));
    }

    return spans;
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

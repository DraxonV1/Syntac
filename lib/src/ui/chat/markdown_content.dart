// Bounded GitHub-flavored Markdown with code, links, images, and real TeX.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:flutter_markdown_plus_latex/flutter_markdown_plus_latex.dart';
import 'package:flutter_math_fork/flutter_math.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:markdown/markdown.dart' as md;

import '../theme/app_colors.dart';
import '../theme/app_typography.dart';
import 'syntax_highlighted_code.dart';

/// Renders bounded agent Markdown with GFM, code, link, image, and TeX support.
class MarkdownContent extends StatelessWidget {
  const MarkdownContent({
    super.key,
    required this.content,
    this.textStyle,
    this.monochrome = false,
    this.streaming = false,
    this.onOpenLink,
  });

  final String content;
  final TextStyle? textStyle;
  final bool monochrome;
  final bool streaming;
  final ValueChanged<String>? onOpenLink;

  static const maxRichCharacters = 100000;
  static const maxBlocks = 400;
  static const _maxImageSourceCharacters = 4200000;
  static final _blockMarker = RegExp(
    r'^(?:\s{0,3}(?:#{1,6}\s|>|[-+*]\s|\d+[.)]\s|```|~~~|\|)|\s*$)',
    multiLine: true,
  );
  static final _extensionSet = md.ExtensionSet(
    <md.BlockSyntax>[
      LatexBlockSyntax(),
      ...md.ExtensionSet.gitHubWeb.blockSyntaxes,
    ],
    <md.InlineSyntax>[
      LatexInlineSyntax(),
      ...md.ExtensionSet.gitHubWeb.inlineSyntaxes,
    ],
  );

  @override
  Widget build(BuildContext context) {
    if (content.isEmpty) return const SizedBox.shrink();
    final wasTruncated = content.length > maxRichCharacters;
    final displayContent = wasTruncated
        ? '${content.substring(0, maxRichCharacters)}\n\n'
              '[content truncated for display; full message remains available]'
        : content;
    final baseStyle = (textStyle ?? AppTypography.bodyMedium).copyWith(
      color: monochrome
          ? AppColors.textMuted
          : textStyle?.color ?? AppColors.textPrimary,
    );
    if (wasTruncated || _exceedsBlockLimit(displayContent)) {
      return SelectableText(displayContent, style: baseStyle);
    }

    final headingColor = monochrome
        ? AppColors.textMuted
        : AppColors.textPrimary;
    final secondaryColor = monochrome
        ? AppColors.textMuted
        : AppColors.textSecondary;
    final styleSheet = MarkdownStyleSheet.fromTheme(Theme.of(context)).copyWith(
      a: baseStyle.copyWith(
        color: monochrome ? AppColors.textMuted : AppColors.accentText,
        decoration: TextDecoration.underline,
        decorationColor: monochrome
            ? AppColors.textMuted
            : AppColors.accentText,
      ),
      p: baseStyle,
      pPadding: EdgeInsets.zero,
      code: AppTypography.codeInline.copyWith(
        color: monochrome ? AppColors.textMuted : AppColors.textPrimary,
        backgroundColor: AppColors.surfaceHigh,
      ),
      h1: AppTypography.displayMedium.copyWith(
        color: headingColor,
        fontSize: 20,
      ),
      h2: AppTypography.titleLarge.copyWith(color: headingColor, fontSize: 17),
      h3: AppTypography.titleMedium.copyWith(color: headingColor, fontSize: 15),
      h4: AppTypography.titleSmall.copyWith(color: headingColor),
      h5: AppTypography.titleSmall.copyWith(color: headingColor),
      h6: AppTypography.label.copyWith(color: headingColor),
      h1Padding: const EdgeInsets.only(top: 6, bottom: 2),
      h2Padding: const EdgeInsets.only(top: 5, bottom: 2),
      h3Padding: const EdgeInsets.only(top: 4, bottom: 1),
      strong: baseStyle.copyWith(
        color: headingColor,
        fontWeight: FontWeight.w700,
      ),
      em: baseStyle.copyWith(fontStyle: FontStyle.italic),
      del: baseStyle.copyWith(
        color: secondaryColor,
        decoration: TextDecoration.lineThrough,
      ),
      blockquote: baseStyle.copyWith(
        color: secondaryColor,
        fontStyle: FontStyle.italic,
      ),
      blockquotePadding: const EdgeInsets.symmetric(
        horizontal: 12,
        vertical: 8,
      ),
      blockquoteDecoration: BoxDecoration(
        color: AppColors.surface.withValues(alpha: 0.55),
        borderRadius: const BorderRadius.only(
          topRight: Radius.circular(6),
          bottomRight: Radius.circular(6),
        ),
        border: Border(left: BorderSide(color: AppColors.accent, width: 3)),
      ),
      blockSpacing: 10,
      listIndent: 24,
      listBullet: baseStyle.copyWith(
        color: AppColors.textMuted,
        fontWeight: FontWeight.w600,
      ),
      checkbox: baseStyle.copyWith(color: AppColors.accentText),
      tableHead: AppTypography.label.copyWith(color: headingColor),
      tableBody: baseStyle,
      tableBorder: TableBorder.all(color: AppColors.border, width: 1),
      tableColumnWidth: const IntrinsicColumnWidth(),
      tableCellsPadding: const EdgeInsets.symmetric(
        horizontal: 10,
        vertical: 7,
      ),
      tableHeadCellsPadding: const EdgeInsets.symmetric(
        horizontal: 10,
        vertical: 8,
      ),
      tableHeadCellsDecoration: BoxDecoration(color: AppColors.surfaceElevated),
      codeblockPadding: EdgeInsets.zero,
      codeblockDecoration: const BoxDecoration(color: Colors.transparent),
      horizontalRuleDecoration: BoxDecoration(
        border: Border(top: BorderSide(color: AppColors.borderSoft)),
      ),
    );

    return MarkdownBody(
      data: displayContent,
      selectable: true,
      fitContent: false,
      softLineBreak: true,
      extensionSet: _extensionSet,
      styleSheet: styleSheet,
      listItemCrossAxisAlignment: MarkdownListItemCrossAxisAlignment.start,
      builders: <String, MarkdownElementBuilder>{
        'pre': _CodeElementBuilder(monochrome: monochrome),
        'latex': _SafeLatexElementBuilder(textStyle: baseStyle),
      },
      checkboxBuilder: _buildCheckbox,
      imageBuilder: _buildImage,
      onTapLink: onOpenLink == null
          ? null
          : (text, href, title) {
              if (href == null) return;
              final uri = Uri.tryParse(href);
              if (uri == null ||
                  (uri.scheme != 'http' && uri.scheme != 'https')) {
                return;
              }
              onOpenLink!(uri.toString());
            },
    );
  }

  bool _exceedsBlockLimit(String value) {
    var count = 0;
    for (final _ in _blockMarker.allMatches(value)) {
      count++;
      if (count > maxBlocks) return true;
    }
    return false;
  }

  Widget _buildCheckbox(bool checked) => Padding(
    padding: const EdgeInsets.only(right: 5, top: 1),
    child: Icon(
      checked ? Icons.check_box_rounded : Icons.check_box_outline_blank_rounded,
      size: 16,
      color: checked ? AppColors.accentText : AppColors.textMuted,
    ),
  );

  Widget _buildImage(Uri uri, String? title, String? alt) {
    final source = uri.toString();
    if (source.length > _maxImageSourceCharacters) {
      return _imageFallback('Image too large to preview');
    }

    try {
      final scheme = uri.scheme.toLowerCase();
      final isSvg =
          uri.path.toLowerCase().endsWith('.svg') ||
          (uri.data?.mimeType.toLowerCase().contains('svg') ?? false);
      final label = (alt?.trim().isNotEmpty ?? false)
          ? alt!.trim()
          : title?.trim();
      late final Widget image;
      if (scheme == 'data' && uri.data != null) {
        final bytes = uri.data!.contentAsBytes();
        image = isSvg
            ? SvgPicture.memory(
                bytes,
                fit: BoxFit.contain,
                semanticsLabel: label,
              )
            : Image.memory(
                bytes,
                fit: BoxFit.contain,
                semanticLabel: label,
                gaplessPlayback: true,
                errorBuilder: (context, error, stackTrace) =>
                    _imageFallback('Invalid image data'),
              );
      } else if (scheme == 'http' || scheme == 'https') {
        image = isSvg
            ? SvgPicture.network(
                source,
                fit: BoxFit.contain,
                semanticsLabel: label,
                placeholderBuilder: (context) => const SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              )
            : Image.network(
                source,
                fit: BoxFit.contain,
                semanticLabel: label,
                gaplessPlayback: true,
                errorBuilder: (context, error, stackTrace) =>
                    _imageFallback(source),
              );
      } else {
        return _imageFallback(source);
      }

      return Container(
        constraints: const BoxConstraints(maxWidth: 520, maxHeight: 360),
        margin: const EdgeInsets.symmetric(vertical: 4),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: AppColors.border),
        ),
        clipBehavior: Clip.antiAlias,
        child: image,
      );
    } catch (_) {
      return _imageFallback('Invalid image');
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

class _CodeElementBuilder extends MarkdownElementBuilder {
  _CodeElementBuilder({required this.monochrome});

  final bool monochrome;

  @override
  bool isBlockElement() => true;

  @override
  Widget visitElementAfterWithContext(
    BuildContext context,
    md.Element element,
    TextStyle? preferredStyle,
    TextStyle? parentStyle,
  ) {
    var language = 'text';
    final children = element.children;
    if (children != null &&
        children.isNotEmpty &&
        children.first is md.Element) {
      final codeElement = children.first as md.Element;
      final className = codeElement.attributes['class'] ?? '';
      if (className.startsWith('language-')) {
        language = className.substring('language-'.length).trim();
      }
    }
    final code = element.textContent.replaceFirst(RegExp(r'\n$'), '');
    return _CodeBlockWidget(
      language: language,
      code: code,
      monochrome: monochrome,
    );
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
    final label = language.isEmpty ? 'text' : language;
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.codeBackground,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.codeBorder),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: AppColors.codeHeader,
              border: Border(bottom: BorderSide(color: AppColors.codeBorder)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  label,
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
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: monochrome
                  ? SelectableText(
                      code,
                      style: AppTypography.monoSmall.copyWith(
                        color: AppColors.textMuted,
                        height: 1.35,
                      ),
                    )
                  : SyntaxHighlightedCode(text: code, language: label),
            ),
          ),
        ],
      ),
    );
  }
}

class _SafeLatexElementBuilder extends MarkdownElementBuilder {
  _SafeLatexElementBuilder({required this.textStyle});

  final TextStyle textStyle;

  @override
  Widget visitElementAfterWithContext(
    BuildContext context,
    md.Element element,
    TextStyle? preferredStyle,
    TextStyle? parentStyle,
  ) {
    final expression = element.textContent;
    if (expression.isEmpty) return const SizedBox.shrink();
    if (expression.length > 4096) return Text(expression, style: textStyle);
    final mathStyle = element.attributes['MathStyle'] == 'display'
        ? MathStyle.display
        : MathStyle.text;
    try {
      return SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Math.tex(
          expression,
          mathStyle: mathStyle,
          textStyle: textStyle,
          onErrorFallback: (_) => Text(expression, style: textStyle),
        ),
      );
    } catch (_) {
      return Text(expression, style: textStyle);
    }
  }
}

// Renders one chat message, including collapsible reasoning and rich markdown.

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../models.dart';
import '../theme/app_colors.dart';
import '../theme/app_typography.dart';
import '../widgets/badge_chip.dart';
import '../theme/app_icons.dart';
import 'markdown_content.dart';

/// Renders user, assistant, and system/internal messages cleanly.
class ChatMessageView extends StatelessWidget {
  const ChatMessageView({
    super.key,
    required this.message,
    this.attachments = const <Attachment>[],
    this.onAttachmentTap,
    this.autoExpandThinking = true,
  });

  final ChatMessage message;
  final List<Attachment> attachments;
  final ValueChanged<Attachment>? onAttachmentTap;
  final bool autoExpandThinking;
  @override
  Widget build(BuildContext context) {
    return switch (message.role) {
      MessageRole.user => _buildUserMessage(context),
      MessageRole.assistant => _buildAssistantMessage(context),
      MessageRole.internal ||
      MessageRole.system => _buildInternalMessage(context),
      MessageRole.tool =>
        const SizedBox.shrink(), // Handled via ToolExecution cards
    };
  }

  Widget _buildUserMessage(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Align(
        alignment: Alignment.centerRight,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: MediaQuery.of(context).size.width * 0.85,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (attachments.isNotEmpty) ...[
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  alignment: WrapAlignment.end,
                  children: [
                    for (final attachment in attachments)
                      _buildAttachment(context, attachment),
                  ],
                ),
                const SizedBox(height: 6),
              ],
              Container(
                decoration: BoxDecoration(
                  color: AppColors.surfaceElevated,
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(14),
                    topRight: Radius.circular(14),
                    bottomLeft: Radius.circular(14),
                    bottomRight: Radius.circular(4),
                  ),
                  border: Border.all(color: AppColors.border, width: 1),
                ),
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 10,
                ),
                child: SelectableText(
                  message.content,
                  style: AppTypography.bodyMedium.copyWith(
                    color: AppColors.textPrimary,
                    height: 1.45,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAttachment(BuildContext context, Attachment attachment) {
    if (attachment.kind != AttachmentKind.image) {
      return BadgeChip.neutral(
        label: attachment.name,
        icon: Icons.insert_drive_file_outlined,
        onTap: onAttachmentTap == null
            ? null
            : () => onAttachmentTap!(attachment),
      );
    }
    final image = ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: Image.file(
        File(attachment.path),
        fit: BoxFit.contain,
        errorBuilder: (context, error, stackTrace) =>
            _unreadableAttachment(attachment.name),
      ),
    );
    final preview = ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 260, maxHeight: 220),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: AppColors.borderSubtle),
        ),
        child: image,
      ),
    );
    return GestureDetector(
      onTap: onAttachmentTap == null
          ? null
          : () => onAttachmentTap!(attachment),
      child: preview,
    );
  }

  Widget _unreadableAttachment(String name) {
    return Padding(
      padding: const EdgeInsets.all(10),
      child: Text(
        'Not Readable\n$name',
        maxLines: 3,
        overflow: TextOverflow.ellipsis,
        style: AppTypography.caption.copyWith(color: AppColors.textMuted),
      ),
    );
  }

  Widget _buildAssistantMessage(BuildContext context) {
    final thinking = _thinkingText();
    if (message.content.trim().isEmpty && thinking.trim().isEmpty) {
      return const SizedBox.shrink();
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (thinking.trim().isNotEmpty)
            Container(
              margin: const EdgeInsets.only(bottom: 8),
              decoration: BoxDecoration(
                color: AppColors.surface.withValues(alpha: 0.55),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AppColors.borderSubtle),
              ),
              child: Theme(
                data: Theme.of(context).copyWith(
                  dividerColor: Colors.transparent,
                  listTileTheme: const ListTileThemeData(
                    dense: true,
                    contentPadding: EdgeInsets.symmetric(horizontal: 10),
                  ),
                ),
                child: ExpansionTile(
                  initiallyExpanded: autoExpandThinking,
                  tilePadding: const EdgeInsets.symmetric(horizontal: 10),
                  childrenPadding: const EdgeInsets.fromLTRB(10, 0, 10, 10),
                  title: Text(
                    'Thinking',
                    style: AppTypography.caption.copyWith(
                      color: AppColors.textMuted,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  iconColor: AppColors.textMuted,
                  collapsedIconColor: AppColors.textMuted,
                  children: [
                    Align(
                      alignment: Alignment.centerLeft,
                      child: MarkdownContent(
                        content: thinking,
                        textStyle: AppTypography.monoSmall.copyWith(
                          color: AppColors.textMuted,
                          height: 1.4,
                        ),
                        monochrome: true,
                        streaming: _isStreaming(),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          if (message.content.trim().isNotEmpty)
            MarkdownContent(
              content: message.content,
              textStyle: AppTypography.bodyLarge.copyWith(
                color: AppColors.textPrimary,
                height: 1.55,
              ),
              streaming: _isStreaming(),
            ),
          if (message.content.trim().isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  InkWell(
                    onTap: () {
                      Clipboard.setData(ClipboardData(text: message.content));
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Message copied to clipboard'),
                          duration: Duration(seconds: 1),
                        ),
                      );
                    },
                    borderRadius: BorderRadius.circular(4),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 4,
                        vertical: 2,
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            AppIcons.copy,
                            size: 13,
                            color: AppColors.textMuted,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            'Copy response',
                            style: AppTypography.caption.copyWith(
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
        ],
      ),
    );
  }

  bool _isStreaming() {
    final raw = message.metadataJson;
    if (raw == null || raw.isEmpty) return false;
    try {
      final decoded = jsonDecode(raw);
      return decoded is Map && decoded['streaming'] == true;
    } catch (_) {
      return false;
    }
  }

  String _thinkingText() {
    final raw = message.metadataJson;
    if (raw == null || raw.isEmpty) return '';
    try {
      final decoded = jsonDecode(raw);
      return decoded is Map ? decoded['thinking']?.toString() ?? '' : '';
    } catch (_) {
      return '';
    }
  }

  Widget _buildInternalMessage(BuildContext context) {
    final isError = message.content.toLowerCase().contains('error');

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: isError ? AppColors.errorSubtle : AppColors.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: isError
              ? AppColors.error.withValues(alpha: 0.3)
              : AppColors.border,
          width: 1,
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            isError ? Icons.error_outline : Icons.info_outline,
            size: 15,
            color: isError ? AppColors.errorText : AppColors.textMuted,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: SelectableText(
              message.content,
              style: AppTypography.monoSmall.copyWith(
                color: isError ? AppColors.errorText : AppColors.textSecondary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

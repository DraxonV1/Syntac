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
  });

  final ChatMessage message;
  final List<Attachment> attachments;

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
        child: Container(
          constraints: BoxConstraints(
            maxWidth: MediaQuery.of(context).size.width * 0.85,
          ),
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
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (attachments.isNotEmpty) ...[
                Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  alignment: WrapAlignment.end,
                  children: [
                    for (final attachment in attachments)
                      BadgeChip.neutral(
                        label: attachment.name,
                        icon: attachment.kind == AttachmentKind.image
                            ? Icons.image_outlined
                            : Icons.insert_drive_file_outlined,
                      ),
                  ],
                ),
                const SizedBox(height: 8),
              ],
              SelectableText(
                message.content,
                style: AppTypography.bodyMedium.copyWith(
                  color: AppColors.textPrimary,
                  height: 1.45,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAssistantMessage(BuildContext context) {
    if (message.content.trim().isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Content flows naturally against dark background
          MarkdownContent(
            content: message.content,
            textStyle: AppTypography.bodyLarge.copyWith(
              color: AppColors.textPrimary,
              height: 1.55,
            ),
          ),

          // Message Bottom Action Bar
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
                        const Icon(
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

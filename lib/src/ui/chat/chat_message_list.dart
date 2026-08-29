import 'package:flutter/material.dart';
import '../../models.dart';
import '../theme/app_colors.dart';
import '../theme/app_typography.dart';
import 'chat_message_view.dart';
import 'tool_call_card.dart';

/// Chronological message item in the chat timeline.
sealed class TimelineItem {
  DateTime get timestamp;
}

class MessageTimelineItem extends TimelineItem {
  MessageTimelineItem(this.message);
  final ChatMessage message;
  @override
  DateTime get timestamp => message.createdAt;
}

class ToolTimelineItem extends TimelineItem {
  ToolTimelineItem(this.execution);
  final ToolExecution execution;
  @override
  DateTime get timestamp => execution.startedAt;
}

/// Smart auto-scrolling message list with jump-to-bottom control.
class ChatMessageList extends StatefulWidget {
  const ChatMessageList({
    super.key,
    required this.messages,
    required this.toolExecutions,
    this.attachments = const <Attachment>[],
    this.padding = const EdgeInsets.fromLTRB(16, 12, 16, 12),
  });

  final List<ChatMessage> messages;
  final List<ToolExecution> toolExecutions;
  final List<Attachment> attachments;
  final EdgeInsetsGeometry padding;

  @override
  State<ChatMessageList> createState() => ChatMessageListState();
}

class ChatMessageListState extends State<ChatMessageList> {
  final ScrollController _scrollController = ScrollController();
  bool _isNearBottom = true;
  bool _showJumpToBottom = false;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    final maxScroll = _scrollController.position.maxScrollExtent;
    final currentScroll = _scrollController.position.pixels;
    final distanceToBottom = maxScroll - currentScroll;

    final isNearBottom = distanceToBottom <= 120;
    final showJump = distanceToBottom > 240;

    if (isNearBottom != _isNearBottom || showJump != _showJumpToBottom) {
      setState(() {
        _isNearBottom = isNearBottom;
        _showJumpToBottom = showJump;
      });
    }
  }

  @override
  void didUpdateWidget(ChatMessageList oldWidget) {
    super.didUpdateWidget(oldWidget);
    final hasNewItems =
        widget.messages.length != oldWidget.messages.length ||
        widget.toolExecutions.length != oldWidget.toolExecutions.length;

    if (hasNewItems && _isNearBottom) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        scrollToBottom(animate: false);
      });
    }
  }

  void scrollToBottom({bool animate = true}) {
    if (!_scrollController.hasClients) return;
    final target = _scrollController.position.maxScrollExtent;
    if (animate) {
      _scrollController.animateTo(
        target,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOutCubic,
      );
    } else {
      _scrollController.jumpTo(target);
    }
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  List<TimelineItem> _buildTimeline() {
    final items = <TimelineItem>[
      for (final msg in widget.messages) MessageTimelineItem(msg),
      for (final tool in widget.toolExecutions) ToolTimelineItem(tool),
    ];
    items.sort((a, b) => a.timestamp.compareTo(b.timestamp));
    return items;
  }

  @override
  Widget build(BuildContext context) {
    final timeline = _buildTimeline();

    return Stack(
      children: [
        ListView.builder(
          controller: _scrollController,
          padding: widget.padding,
          itemCount: timeline.length,
          itemBuilder: (context, index) {
            final item = timeline[index];
            return switch (item) {
              MessageTimelineItem(:final message) => ChatMessageView(
                message: message,
                attachments: widget.attachments
                    .where((a) => a.messageId == message.id)
                    .toList(),
              ),
              ToolTimelineItem(:final execution) => ToolCallCard(
                execution: execution,
              ),
            };
          },
        ),

        // Floating "Jump to bottom" Button
        if (_showJumpToBottom)
          Positioned(
            right: 16,
            bottom: 12,
            child: AnimatedOpacity(
              opacity: _showJumpToBottom ? 1.0 : 0.0,
              duration: const Duration(milliseconds: 200),
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: () => scrollToBottom(animate: true),
                  borderRadius: BorderRadius.circular(20),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.surfaceElevated,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: AppColors.border, width: 1),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.35),
                          blurRadius: 8,
                          offset: const Offset(0, 3),
                        ),
                      ],
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.arrow_downward_rounded,
                          size: 14,
                          color: AppColors.accentText,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          'Jump to bottom',
                          style: AppTypography.monoSmall.copyWith(
                            color: AppColors.textPrimary,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

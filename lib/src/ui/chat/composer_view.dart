// Message composer with attachments, model, effort, thinking, and send controls.

import 'package:flutter/material.dart';
import '../../ai/ai_provider.dart';
import '../../models.dart';
import '../theme/app_colors.dart';
import '../theme/app_typography.dart';
import '../widgets/badge_chip.dart';

/// Primary dark rounded composer matching modern mobile coding interfaces.
class ComposerView extends StatefulWidget {
  const ComposerView({
    super.key,
    required this.onSend,
    required this.onStop,
    required this.onPickAttachment,
    required this.onSelectModel,
    this.onSelectEffort,
    this.onToggleThinking,
    required this.isRunning,
    this.reasoningEffort = AIReasoningEffort.medium,
    this.thinkingEnabled = true,
    this.selectedModelName,
    this.attachments = const <Attachment>[],
    this.onRemoveAttachment,
  });

  final Future<bool> Function(String text) onSend;
  final VoidCallback onStop;
  final VoidCallback onPickAttachment;
  final VoidCallback onSelectModel;
  final ValueChanged<AIReasoningEffort>? onSelectEffort;
  final VoidCallback? onToggleThinking;
  final bool isRunning;
  final AIReasoningEffort reasoningEffort;
  final bool thinkingEnabled;
  final String? selectedModelName;
  final List<Attachment> attachments;
  final ValueChanged<Attachment>? onRemoveAttachment;

  @override
  State<ComposerView> createState() => ComposerViewState();
}

class ComposerViewState extends State<ComposerView> {
  final TextEditingController _controller = TextEditingController();
  final FocusNode _focusNode = FocusNode();
  bool _hasText = false;
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onTextChanged);
  }

  void _onTextChanged() {
    final hasText = _controller.text.trim().isNotEmpty;
    if (hasText != _hasText) {
      setState(() => _hasText = hasText);
    }
  }

  void setText(String text) {
    _controller.text = text;
    _controller.selection = TextSelection.fromPosition(
      TextPosition(offset: _controller.text.length),
    );
  }

  Widget _compactControl(IconData icon, String label, {required bool enabled}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 5),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.border, width: 0.8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            size: 14,
            color: enabled ? AppColors.textSecondary : AppColors.textMuted,
          ),
          const SizedBox(width: 4),
          Text(
            label,
            style: AppTypography.monoSmall.copyWith(
              fontSize: 10.5,
              color: enabled ? AppColors.textSecondary : AppColors.textMuted,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _handleSubmit() async {
    final text = _controller.text.trim();
    if (_submitting || (text.isEmpty && widget.attachments.isEmpty)) return;
    setState(() => _submitting = true);
    try {
      final accepted = await widget.onSend(text);
      if (mounted && accepted) _controller.clear();
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Widget _buildAttachmentButton() {
    return Tooltip(
      message: 'Add attachment',
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: widget.onPickAttachment,
          borderRadius: BorderRadius.circular(8),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
            child: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AppColors.border, width: 0.8),
              ),
              child: Icon(Icons.add, size: 16, color: AppColors.textSecondary),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildModelButton(String modelLabel) {
    return Tooltip(
      message: 'Select model',
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: widget.onSelectModel,
          borderRadius: BorderRadius.circular(8),
          child: Container(
            constraints: const BoxConstraints(minHeight: 40),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AppColors.border, width: 0.8),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.memory_outlined,
                  size: 14,
                  color: AppColors.textMuted,
                ),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    modelLabel,
                    overflow: TextOverflow.ellipsis,
                    style: AppTypography.monoSmall.copyWith(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w500,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ),
                const SizedBox(width: 4),
                Icon(
                  Icons.keyboard_arrow_down,
                  size: 14,
                  color: AppColors.textMuted,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildEffortButton() {
    return PopupMenuButton<AIReasoningEffort>(
      enabled: !widget.isRunning,
      tooltip: 'Reasoning effort',
      initialValue: widget.reasoningEffort,
      onSelected: widget.onSelectEffort,
      color: AppColors.surfaceElevated,
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
      itemBuilder: (context) => [
        for (final effort in AIReasoningEffort.values)
          PopupMenuItem(
            value: effort,
            child: Text(effort.label, style: AppTypography.monoSmall),
          ),
      ],
      child: _compactControl(
        Icons.tune,
        widget.reasoningEffort.label,
        enabled: !widget.isRunning,
      ),
    );
  }

  Widget _buildThinkingButton() {
    return Tooltip(
      message: widget.thinkingEnabled
          ? 'Disable model thinking'
          : 'Enable model thinking',
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: widget.isRunning ? null : widget.onToggleThinking,
          borderRadius: BorderRadius.circular(8),
          child: _compactControl(
            widget.thinkingEnabled
                ? Icons.psychology
                : Icons.psychology_outlined,
            widget.thinkingEnabled ? 'Think' : 'No think',
            enabled: !widget.isRunning,
          ),
        ),
      ),
    );
  }

  Widget _buildStopButton() {
    return Tooltip(
      message: 'Stop',
      child: Semantics(
        button: true,
        label: 'Stop current operation',
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: widget.onStop,
            borderRadius: BorderRadius.circular(8),
            child: Container(
              constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
              decoration: BoxDecoration(
                color: AppColors.errorSubtle,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: AppColors.error.withValues(alpha: 0.4),
                ),
              ),
              child: const Icon(
                Icons.stop_rounded,
                size: 20,
                color: AppColors.errorText,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSendButton(bool canSend) {
    return Tooltip(
      message: canSend ? 'Send message' : 'Enter a message',
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: canSend ? _handleSubmit : null,
          borderRadius: BorderRadius.circular(8),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
            decoration: BoxDecoration(
              color: canSend ? AppColors.accent : AppColors.surface,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: canSend ? AppColors.accent : AppColors.border,
              ),
            ),
            child: Center(
              child: Icon(
                Icons.arrow_upward_rounded,
                size: 18,
                color: canSend ? Colors.white : AppColors.textMuted,
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _controller.removeListener(_onTextChanged);
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final canSend = (_hasText || widget.attachments.isNotEmpty) && !_submitting;
    final modelLabel = widget.selectedModelName ?? 'Select Model';

    return Container(
      decoration: BoxDecoration(
        color: AppColors.background,
        border: Border(
          top: BorderSide(color: AppColors.borderSubtle, width: 1),
        ),
      ),
      padding: const EdgeInsets.fromLTRB(12, 6, 12, 12),
      child: SafeArea(
        top: false,
        child: Container(
          decoration: BoxDecoration(
            color: AppColors.surfaceElevated,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: _focusNode.hasFocus
                  ? AppColors.borderFocus.withValues(alpha: 0.6)
                  : AppColors.border,
              width: 1,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.25),
                blurRadius: 10,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Attachment Chips Row
              if (widget.attachments.isNotEmpty) ...[
                Padding(
                  padding: const EdgeInsets.fromLTRB(10, 10, 10, 0),
                  child: Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      for (final attachment in widget.attachments)
                        BadgeChip.neutral(
                          label: attachment.name,
                          icon: attachment.kind == AttachmentKind.image
                              ? Icons.image_outlined
                              : Icons.insert_drive_file_outlined,
                          onDelete: widget.onRemoveAttachment != null
                              ? () => widget.onRemoveAttachment!(attachment)
                              : null,
                        ),
                    ],
                  ),
                ),
              ],

              // Thinking and effort stay above message input on every screen size.
              Padding(
                padding: const EdgeInsets.fromLTRB(10, 8, 10, 0),
                child: Row(
                  children: [
                    _buildThinkingButton(),
                    const Spacer(),
                    _buildEffortButton(),
                  ],
                ),
              ),

              // Multiline Text Input
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
                child: TextField(
                  controller: _controller,
                  focusNode: _focusNode,
                  minLines: 1,
                  maxLines: 6,
                  textInputAction: TextInputAction.newline,
                  keyboardType: TextInputType.multiline,
                  style: AppTypography.bodyMedium.copyWith(
                    color: AppColors.textPrimary,
                    height: 1.45,
                  ),
                  decoration: InputDecoration(
                    hintText: 'Send a message',
                    hintStyle: AppTypography.bodyMedium.copyWith(
                      color: AppColors.textMuted,
                    ),
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    filled: false,
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(vertical: 4),
                  ),
                ),
              ),

              // Attachment, model, and send controls stay on lower action row.
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
                child: Row(
                  children: [
                    _buildAttachmentButton(),
                    const SizedBox(width: 8),
                    Expanded(child: _buildModelButton(modelLabel)),
                    const SizedBox(width: 8),
                    if (widget.isRunning) ...[
                      _buildStopButton(),
                      const SizedBox(width: 8),
                    ],
                    _buildSendButton(canSend),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

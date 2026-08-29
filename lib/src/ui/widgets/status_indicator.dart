import 'package:flutter/material.dart';
import '../../models.dart';
import '../theme/app_colors.dart';

/// Refined status indicator dot or icon with subtle animation for running state.
class StatusIndicator extends StatefulWidget {
  const StatusIndicator({
    super.key,
    required this.status,
    this.size = 8.0,
    this.showIcon = false,
  });

  factory StatusIndicator.fromChat(
    ChatStatus status, {
    double size = 8.0,
    bool showIcon = false,
  }) {
    return StatusIndicator(status: status, size: size, showIcon: showIcon);
  }

  factory StatusIndicator.fromTool(
    ToolExecutionStatus status, {
    double size = 8.0,
    bool showIcon = false,
  }) {
    final chatStatus = switch (status) {
      ToolExecutionStatus.running => ChatStatus.running,
      ToolExecutionStatus.success => ChatStatus.completed,
      ToolExecutionStatus.error => ChatStatus.error,
      ToolExecutionStatus.cancelled => ChatStatus.interrupted,
    };
    return StatusIndicator(status: chatStatus, size: size, showIcon: showIcon);
  }

  final ChatStatus status;
  final double size;
  final bool showIcon;

  @override
  State<StatusIndicator> createState() => _StatusIndicatorState();
}

class _StatusIndicatorState extends State<StatusIndicator>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    );
    _pulseAnimation = Tween<double>(
      begin: 0.65,
      end: 1.0,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeInOut));
    if (widget.status == ChatStatus.running) {
      _controller.repeat(reverse: true);
    }
  }

  @override
  void didUpdateWidget(StatusIndicator oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.status == ChatStatus.running && !_controller.isAnimating) {
      _controller.repeat(reverse: true);
    } else if (widget.status != ChatStatus.running && _controller.isAnimating) {
      _controller.stop();
      _controller.reset();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = switch (widget.status) {
      ChatStatus.running => AppColors.warning,
      ChatStatus.completed => AppColors.success,
      ChatStatus.error || ChatStatus.interrupted => AppColors.error,
      ChatStatus.idle => AppColors.textMuted,
    };

    if (widget.showIcon) {
      return switch (widget.status) {
        ChatStatus.running => AnimatedBuilder(
          animation: _pulseAnimation,
          builder: (context, _) => Transform.scale(
            scale: _pulseAnimation.value,
            child: Icon(
              Icons.radio_button_checked,
              color: AppColors.warning,
              size: widget.size * 1.8,
            ),
          ),
        ),
        ChatStatus.completed => Icon(
          Icons.check_circle_outline,
          color: AppColors.success,
          size: widget.size * 1.8,
        ),
        ChatStatus.error || ChatStatus.interrupted => Icon(
          Icons.error_outline,
          color: AppColors.error,
          size: widget.size * 1.8,
        ),
        ChatStatus.idle => Icon(
          Icons.radio_button_unchecked,
          color: AppColors.textMuted,
          size: widget.size * 1.8,
        ),
      };
    }

    if (widget.status == ChatStatus.running) {
      return AnimatedBuilder(
        animation: _pulseAnimation,
        builder: (context, _) {
          return Container(
            width: widget.size,
            height: widget.size,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: color.withValues(alpha: _pulseAnimation.value),
              boxShadow: [
                BoxShadow(
                  color: color.withValues(alpha: 0.4 * _pulseAnimation.value),
                  blurRadius: 4,
                  spreadRadius: 1,
                ),
              ],
            ),
          );
        },
      );
    }

    return Container(
      width: widget.size,
      height: widget.size,
      decoration: BoxDecoration(shape: BoxShape.circle, color: color),
    );
  }
}

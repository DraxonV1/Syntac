import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import '../theme/app_typography.dart';
import '../widgets/status_indicator.dart';
import '../../models.dart';

/// Clean, quiet running state indicator showing the agent's current action.
class AgentRunningIndicator extends StatelessWidget {
  const AgentRunningIndicator({super.key, required this.action, this.onStop});

  final String action;
  final VoidCallback? onStop;

  @override
  Widget build(BuildContext context) {
    final displayAction = action.trim().isEmpty ? 'Thinking...' : action.trim();

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: AppColors.warning.withValues(alpha: 0.35),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.2),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const StatusIndicator(status: ChatStatus.running, size: 7),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              displayAction,
              overflow: TextOverflow.ellipsis,
              style: AppTypography.monoSmall.copyWith(
                color: AppColors.textPrimary,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          if (onStop != null) ...[
            const SizedBox(width: 10),
            InkWell(
              onTap: onStop,
              borderRadius: BorderRadius.circular(4),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 7,
                      height: 7,
                      decoration: const BoxDecoration(
                        color: AppColors.error,
                        borderRadius: BorderRadius.all(Radius.circular(1.5)),
                      ),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      'Stop',
                      style: AppTypography.monoSmall.copyWith(
                        color: AppColors.errorText,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

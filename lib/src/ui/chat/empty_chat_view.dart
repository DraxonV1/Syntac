import 'package:flutter/material.dart';
import '../../models.dart';
import '../theme/app_colors.dart';
import '../theme/app_typography.dart';
import '../theme/app_icons.dart';

/// Quiet, minimal empty state when a chat has no messages.
class EmptyChatView extends StatelessWidget {
  const EmptyChatView({super.key, required this.project, this.onSuggestionTap});

  final Project? project;
  final void Function(String prompt)? onSuggestionTap;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            // Subtle folder / terminal icon
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: AppColors.surfaceElevated,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.border, width: 1),
              ),
              child: const Center(
                child: Icon(
                  AppIcons.terminal,
                  size: 22,
                  color: AppColors.primaryBright,
                ),
              ),
            ),
            const SizedBox(height: 16),
            if (project != null) ...[
              Text(
                project!.name,
                style: AppTypography.titleMedium.copyWith(
                  color: AppColors.textSecondary,
                  letterSpacing: -0.2,
                ),
              ),
              const SizedBox(height: 4),
            ],
            Text(
              'What do you want to build?',
              style: AppTypography.titleLarge.copyWith(
                color: AppColors.textPrimary,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 24),
            // Subtle starter suggestion chips (optional quick actions)
            if (onSuggestionTap != null) ...[
              Wrap(
                spacing: 8,
                runSpacing: 8,
                alignment: WrapAlignment.center,
                children: [
                  _SuggestionChip(
                    label: 'Read project structure',
                    icon: AppIcons.folderOpen,
                    onTap: () => onSuggestionTap!(
                      'Read the project structure and summarize entry points.',
                    ),
                  ),
                  _SuggestionChip(
                    label: 'Run tests',
                    icon: AppIcons.terminal,
                    onTap: () => onSuggestionTap!(
                      'Run the test suite and report any failures.',
                    ),
                  ),
                  _SuggestionChip(
                    label: 'Fix issue',
                    icon: AppIcons.edit,
                    onTap: () => onSuggestionTap!(
                      'Help me inspect and fix an issue in the project.',
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _SuggestionChip extends StatelessWidget {
  const _SuggestionChip({
    required this.label,
    required this.icon,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: AppColors.border, width: 1),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 13, color: AppColors.textMuted),
              const SizedBox(width: 6),
              Text(
                label,
                style: AppTypography.bodySmall.copyWith(
                  color: AppColors.textSecondary,
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

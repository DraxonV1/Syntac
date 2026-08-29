import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import '../theme/app_typography.dart';

enum AppButtonVariant { primary, secondary, ghost, danger }

/// Reusable button matching the dark developer aesthetics.
class AppButton extends StatelessWidget {
  const AppButton({
    super.key,
    required this.label,
    this.icon,
    this.onPressed,
    this.variant = AppButtonVariant.primary,
    this.loading = false,
    this.compact = false,
  });

  final String label;
  final IconData? icon;
  final VoidCallback? onPressed;
  final AppButtonVariant variant;
  final bool loading;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final (bg, fg, border) = switch (variant) {
      AppButtonVariant.primary => (
        AppColors.accent,
        Colors.white,
        Colors.transparent,
      ),
      AppButtonVariant.secondary => (
        AppColors.surfaceElevated,
        AppColors.textPrimary,
        AppColors.border,
      ),
      AppButtonVariant.ghost => (
        Colors.transparent,
        AppColors.textSecondary,
        Colors.transparent,
      ),
      AppButtonVariant.danger => (
        AppColors.errorSubtle,
        AppColors.errorText,
        AppColors.error.withValues(alpha: 0.3),
      ),
    };

    final isEnabled = onPressed != null && !loading;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: isEnabled ? onPressed : null,
        borderRadius: BorderRadius.circular(8),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: EdgeInsets.symmetric(
            horizontal: compact ? 10 : 14,
            vertical: compact ? 6 : 10,
          ),
          decoration: BoxDecoration(
            color: isEnabled ? bg : bg.withValues(alpha: 0.5),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: border, width: 1),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (loading) ...[
                SizedBox(
                  width: compact ? 12 : 14,
                  height: compact ? 12 : 14,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation<Color>(fg),
                  ),
                ),
                const SizedBox(width: 8),
              ] else if (icon != null) ...[
                Icon(
                  icon,
                  size: compact ? 14 : 16,
                  color: isEnabled ? fg : fg.withValues(alpha: 0.4),
                ),
                const SizedBox(width: 6),
              ],
              Text(
                label,
                style: (compact ? AppTypography.label : AppTypography.label)
                    .copyWith(
                      color: isEnabled ? fg : fg.withValues(alpha: 0.4),
                      fontSize: compact ? 12 : 13,
                    ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Compact rounded icon button.
class AppIconButton extends StatelessWidget {
  const AppIconButton({
    super.key,
    required this.icon,
    this.onPressed,
    this.tooltip,
    this.color,
    this.backgroundColor,
    this.size = 36.0,
    this.iconSize = 18.0,
    this.borderColor,
  });

  final IconData icon;
  final VoidCallback? onPressed;
  final String? tooltip;
  final Color? color;
  final Color? backgroundColor;
  final double size;
  final double iconSize;
  final Color? borderColor;

  @override
  Widget build(BuildContext context) {
    final fg = color ?? AppColors.textSecondary;
    final isEnabled = onPressed != null;

    Widget button = Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: isEnabled ? onPressed : null,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            color: backgroundColor ?? Colors.transparent,
            borderRadius: BorderRadius.circular(8),
            border: borderColor != null
                ? Border.all(color: borderColor!, width: 1)
                : null,
          ),
          child: Center(
            child: Icon(
              icon,
              size: iconSize,
              color: isEnabled ? fg : fg.withValues(alpha: 0.3),
            ),
          ),
        ),
      ),
    );

    if (tooltip != null) {
      button = Tooltip(message: tooltip!, child: button);
    }
    return button;
  }
}

/// Dedicated Stop button with soft amber/red accent while agent is running.
class StopButton extends StatelessWidget {
  const StopButton({super.key, required this.onPressed, this.compact = false});

  final VoidCallback onPressed;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: EdgeInsets.symmetric(
            horizontal: compact ? 10 : 12,
            vertical: compact ? 6 : 8,
          ),
          decoration: BoxDecoration(
            color: AppColors.errorSubtle,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: AppColors.error.withValues(alpha: 0.4),
              width: 1,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: const BoxDecoration(
                  color: AppColors.error,
                  borderRadius: BorderRadius.all(Radius.circular(1.5)),
                ),
              ),
              const SizedBox(width: 6),
              Text(
                'Stop',
                style: AppTypography.label.copyWith(
                  color: AppColors.errorText,
                  fontSize: compact ? 12 : 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

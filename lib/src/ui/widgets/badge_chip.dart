import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import '../theme/app_typography.dart';

enum BadgeVariant { primary, success, warning, error, neutral }

/// Clean compact badge pill for status, counts, diffs, and tool metadata.
class BadgeChip extends StatelessWidget {
  const BadgeChip({
    super.key,
    required this.label,
    this.icon,
    this.backgroundColor,
    this.textColor,
    this.borderColor,
    this.onTap,
    this.onDelete,
    this.padding,
    BadgeVariant? variant,
  }) : _variant = variant;

  final BadgeVariant? _variant;

  factory BadgeChip.primary({
    Key? key,
    required String label,
    IconData? icon,
  }) => BadgeChip(
    key: key,
    label: label,
    icon: icon,
    backgroundColor: AppColors.accentSubtle,
    textColor: AppColors.accentText,
    borderColor: AppColors.primary.withValues(alpha: 0.3),
  );

  factory BadgeChip.success({
    Key? key,
    required String label,
    IconData? icon,
  }) => BadgeChip(
    key: key,
    label: label,
    icon: icon,
    backgroundColor: AppColors.successSubtle,
    textColor: AppColors.successText,
    borderColor: AppColors.success.withValues(alpha: 0.3),
  );

  factory BadgeChip.warning({
    Key? key,
    required String label,
    IconData? icon,
  }) => BadgeChip(
    key: key,
    label: label,
    icon: icon,
    backgroundColor: AppColors.warningSubtle,
    textColor: AppColors.warningText,
    borderColor: AppColors.warning.withValues(alpha: 0.3),
  );

  factory BadgeChip.error({Key? key, required String label, IconData? icon}) =>
      BadgeChip(
        key: key,
        label: label,
        icon: icon,
        backgroundColor: AppColors.errorSubtle,
        textColor: AppColors.errorText,
        borderColor: AppColors.error.withValues(alpha: 0.3),
      );

  factory BadgeChip.neutral({
    Key? key,
    required String label,
    IconData? icon,
    VoidCallback? onTap,
    VoidCallback? onDelete,
  }) => BadgeChip(
    key: key,
    label: label,
    icon: icon,
    backgroundColor: AppColors.surfaceHigh,
    textColor: AppColors.textSecondary,
    borderColor: AppColors.border,
    onTap: onTap,
    onDelete: onDelete,
  );

  factory BadgeChip.accent({
    Key? key,
    required String label,
    IconData? icon,
    VoidCallback? onTap,
  }) => BadgeChip(
    key: key,
    label: label,
    icon: icon,
    backgroundColor: AppColors.accentSubtle,
    textColor: AppColors.accentText,
    borderColor: AppColors.accent.withValues(alpha: 0.4),
    onTap: onTap,
  );

  factory BadgeChip.diff({
    Key? key,
    required int added,
    required int removed,
  }) => BadgeChip(
    key: key,
    label: '+$added -$removed',
    backgroundColor: AppColors.surfaceHigh,
    textColor: AppColors.successText,
    borderColor: AppColors.border,
  );

  final String label;
  final IconData? icon;
  final Color? backgroundColor;
  final Color? textColor;
  final Color? borderColor;
  final VoidCallback? onTap;
  final VoidCallback? onDelete;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) {
    final variantBg = switch (_variant) {
      BadgeVariant.primary => AppColors.accentSubtle,
      BadgeVariant.success => AppColors.successSubtle,
      BadgeVariant.warning => AppColors.warningSubtle,
      BadgeVariant.error => AppColors.errorSubtle,
      BadgeVariant.neutral => AppColors.surfaceElevated,
      null => null,
    };
    final variantFg = switch (_variant) {
      BadgeVariant.primary => AppColors.accentText,
      BadgeVariant.success => AppColors.successText,
      BadgeVariant.warning => AppColors.warningText,
      BadgeVariant.error => AppColors.errorText,
      BadgeVariant.neutral => AppColors.textSecondary,
      null => null,
    };
    final variantBorder = switch (_variant) {
      BadgeVariant.primary => AppColors.primary.withAlpha(80),
      BadgeVariant.success => AppColors.success.withAlpha(80),
      BadgeVariant.warning => AppColors.warning.withAlpha(80),
      BadgeVariant.error => AppColors.error.withAlpha(80),
      BadgeVariant.neutral => AppColors.border,
      null => null,
    };

    final bg = backgroundColor ?? variantBg ?? AppColors.surfaceElevated;
    final fg = textColor ?? variantFg ?? AppColors.textSecondary;
    final border = borderColor ?? variantBorder ?? AppColors.border;
    Widget content = Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        if (icon != null) ...[
          Icon(icon, size: 12, color: fg),
          const SizedBox(width: 4),
        ],
        Text(
          label,
          style: AppTypography.monoSmall.copyWith(
            color: fg,
            fontWeight: FontWeight.w500,
          ),
        ),
        if (onDelete != null) ...[
          const SizedBox(width: 4),
          GestureDetector(
            onTap: onDelete,
            behavior: HitTestBehavior.opaque,
            child: Icon(
              Icons.close,
              size: 12,
              color: fg.withValues(alpha: 0.7),
            ),
          ),
        ],
      ],
    );

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(6),
        child: Container(
          padding:
              padding ?? const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: border, width: 0.8),
          ),
          child: content,
        ),
      ),
    );
  }
}

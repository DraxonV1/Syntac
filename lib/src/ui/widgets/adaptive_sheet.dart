import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import '../theme/app_icons.dart';
import '../theme/app_typography.dart';
import 'app_buttons.dart';

/// Modal bottom sheet wrapper with grab handle, title bar, and responsive layout.
class AdaptiveSheet extends StatelessWidget {
  const AdaptiveSheet({
    super.key,
    required this.title,
    required this.child,
    this.subtitle,
    this.leading,
    this.actions,
    this.maxHeightFraction = 0.85,
    this.showClose = true,
    this.padding = const EdgeInsets.fromLTRB(16, 0, 16, 24),
  });

  final String title;
  final String? subtitle;
  final Widget? leading;
  final List<Widget>? actions;
  final Widget child;
  final double maxHeightFraction;
  final bool showClose;
  final EdgeInsetsGeometry padding;

  /// Helper to show this sheet
  static Future<T?> show<T>({
    required BuildContext context,
    required String title,
    required Widget child,
    String? subtitle,
    Widget? leading,
    List<Widget>? actions,
    double maxHeightFraction = 0.85,
    bool isScrollControlled = true,
  }) {
    return showModalBottomSheet<T>(
      context: context,
      isScrollControlled: isScrollControlled,
      backgroundColor: Colors.transparent,
      builder: (context) => AdaptiveSheet(
        title: title,
        subtitle: subtitle,
        leading: leading,
        actions: actions,
        maxHeightFraction: maxHeightFraction,
        child: child,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final maxH = media.size.height * maxHeightFraction;

    return Container(
      constraints: BoxConstraints(maxHeight: maxH),
      decoration: const BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
        border: Border(
          top: BorderSide(color: AppColors.border, width: 1),
          left: BorderSide(color: AppColors.border, width: 1),
          right: BorderSide(color: AppColors.border, width: 1),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Drag handle
          Container(
            width: 36,
            height: 4,
            margin: const EdgeInsets.only(top: 8, bottom: 8),
            decoration: BoxDecoration(
              color: AppColors.border,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          // Header
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 12, 12),
            child: Row(
              children: [
                if (leading != null) ...[leading!, const SizedBox(width: 10)],
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(title, style: AppTypography.titleMedium),
                      if (subtitle != null) ...[
                        const SizedBox(height: 2),
                        Text(subtitle!, style: AppTypography.bodySmall),
                      ],
                    ],
                  ),
                ),
                if (actions != null) ...actions!,
                if (showClose)
                  AppIconButton(
                    icon: AppIcons.close,
                    tooltip: 'Close',
                    size: 32,
                    iconSize: 18,
                    onPressed: () => Navigator.of(context).pop(),
                  ),
              ],
            ),
          ),
          const Divider(height: 1, color: AppColors.borderSoft),
          // Scrollable Content
          Flexible(
            child: SingleChildScrollView(padding: padding, child: child),
          ),
        ],
      ),
    );
  }
}

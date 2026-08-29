import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import '../theme/app_icons.dart';
import '../theme/app_typography.dart';
import 'app_buttons.dart';

/// Interactive surface supporting Collapsed, Expanded, and Maximized full-screen overlay states.
class MaximizableSurface extends StatefulWidget {
  const MaximizableSurface({
    super.key,
    required this.title,
    required this.child,
    this.icon,
    this.subtitle,
    this.actions,
    this.initialExpanded = false,
    this.canMaximize = true,
    this.onMaximizeChanged,
    this.headerTrailing,
    this.backgroundColor,
    this.borderColor,
    this.borderRadius,
  });

  final String title;
  final Widget child;
  final IconData? icon;
  final String? subtitle;
  final List<Widget>? actions;
  final bool initialExpanded;
  final bool canMaximize;
  final ValueChanged<bool>? onMaximizeChanged;
  final Widget? headerTrailing;
  final Color? backgroundColor;
  final Color? borderColor;
  final BorderRadius? borderRadius;

  @override
  State<MaximizableSurface> createState() => _MaximizableSurfaceState();
}

class _MaximizableSurfaceState extends State<MaximizableSurface> {
  late bool _expanded;

  @override
  void initState() {
    super.initState();
    _expanded = widget.initialExpanded;
  }

  void _toggleExpanded() {
    setState(() {
      _expanded = !_expanded;
    });
  }

  void _openMaximized(BuildContext context) {
    widget.onMaximizeChanged?.call(true);
    Navigator.of(context)
        .push(
          PageRouteBuilder<void>(
            opaque: false,
            pageBuilder: (context, animation, secondaryAnimation) {
              return _MaximizedOverlay(
                title: widget.title,
                icon: widget.icon,
                actions: widget.actions,
                child: widget.child,
              );
            },
            transitionsBuilder:
                (context, animation, secondaryAnimation, child) {
                  final curved = CurvedAnimation(
                    parent: animation,
                    curve: Curves.easeOutCubic,
                  );
                  return FadeTransition(
                    opacity: curved,
                    child: ScaleTransition(
                      scale: Tween<double>(
                        begin: 0.95,
                        end: 1.0,
                      ).animate(curved),
                      child: child,
                    ),
                  );
                },
          ),
        )
        .then((_) {
          widget.onMaximizeChanged?.call(false);
        });
  }

  @override
  Widget build(BuildContext context) {
    final radius = widget.borderRadius ?? BorderRadius.circular(10);

    return Container(
      decoration: BoxDecoration(
        color: widget.backgroundColor ?? AppColors.surfaceElevated,
        borderRadius: radius,
        border: Border.all(
          color: widget.borderColor ?? AppColors.border,
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          // Header Bar
          Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: _expanded
                  ? BorderRadius.vertical(top: radius.topLeft)
                  : radius,
              onTap: _toggleExpanded,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
                child: Row(
                  children: [
                    if (widget.icon != null) ...[
                      Icon(
                        widget.icon,
                        size: 16,
                        color: AppColors.primaryBright,
                      ),
                      const SizedBox(width: 8),
                    ],
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(widget.title, style: AppTypography.titleSmall),
                          if (widget.subtitle != null) ...[
                            const SizedBox(height: 2),
                            Text(
                              widget.subtitle!,
                              style: AppTypography.bodySmall,
                            ),
                          ],
                        ],
                      ),
                    ),
                    if (widget.headerTrailing != null) widget.headerTrailing!,
                    if (widget.canMaximize) ...[
                      AppIconButton(
                        icon: AppIcons.maximize,
                        tooltip: 'Maximize',
                        size: 28,
                        iconSize: 15,
                        onPressed: () => _openMaximized(context),
                      ),
                      const SizedBox(width: 4),
                    ],
                    Icon(
                      _expanded ? AppIcons.chevronUp : AppIcons.chevronDown,
                      size: 18,
                      color: AppColors.textSecondary,
                    ),
                  ],
                ),
              ),
            ),
          ),
          // Body content when expanded
          if (_expanded) ...[
            const Divider(height: 1, color: AppColors.borderSoft),
            Padding(padding: const EdgeInsets.all(12), child: widget.child),
          ],
        ],
      ),
    );
  }
}

class _MaximizedOverlay extends StatelessWidget {
  const _MaximizedOverlay({
    required this.title,
    required this.child,
    this.icon,
    this.actions,
  });

  final String title;
  final Widget child;
  final IconData? icon;
  final List<Widget>? actions;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        leading: AppIconButton(
          icon: AppIcons.minimize,
          tooltip: 'Minimize',
          size: 32,
          iconSize: 18,
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Row(
          children: [
            if (icon != null) ...[
              Icon(icon, size: 18, color: AppColors.primaryBright),
              const SizedBox(width: 8),
            ],
            Expanded(child: Text(title, style: AppTypography.titleMedium)),
          ],
        ),
        actions: [
          if (actions != null) ...actions!,
          AppIconButton(
            icon: AppIcons.close,
            tooltip: 'Close',
            size: 32,
            iconSize: 18,
            onPressed: () => Navigator.of(context).pop(),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: SafeArea(
        child: Padding(padding: const EdgeInsets.all(16), child: child),
      ),
    );
  }
}

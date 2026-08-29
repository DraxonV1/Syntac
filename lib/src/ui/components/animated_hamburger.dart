import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import '../theme/app_icons.dart';

/// Floating glass hamburger button with glow, tactile spring, and clean touch target.
class AnimatedHamburger extends StatefulWidget {
  const AnimatedHamburger({
    super.key,
    required this.onTap,
    this.size = 48.0,
    this.iconSize = 22.0,
    this.showGlow = true,
    this.isCenter = false,
  });

  final VoidCallback onTap;
  final double size;
  final double iconSize;
  final bool showGlow;
  final bool isCenter;

  @override
  State<AnimatedHamburger> createState() => _AnimatedHamburgerState();
}

class _AnimatedHamburgerState extends State<AnimatedHamburger>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pressController;
  late final Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _pressController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 120),
    );
    _scaleAnimation = Tween<double>(begin: 1.0, end: 0.92).animate(
      CurvedAnimation(parent: _pressController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _pressController.dispose();
    super.dispose();
  }

  void _onTapDown(TapDownDetails details) => _pressController.forward();
  void _onTapUp(TapUpDetails details) => _pressController.reverse();
  void _onTapCancel() => _pressController.reverse();

  @override
  Widget build(BuildContext context) {
    final effectiveSize = widget.isCenter ? 64.0 : widget.size;
    final effectiveIconSize = widget.isCenter ? 28.0 : widget.iconSize;

    return AnimatedBuilder(
      animation: _scaleAnimation,
      builder: (context, child) {
        return Transform.scale(
          scale: _scaleAnimation.value,
          child: GestureDetector(
            onTapDown: _onTapDown,
            onTapUp: _onTapUp,
            onTapCancel: _onTapCancel,
            onTap: widget.onTap,
            behavior: HitTestBehavior.opaque,
            child: Container(
              width: effectiveSize,
              height: effectiveSize,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: widget.isCenter
                    ? AppColors.surfaceFloating
                    : AppColors.surfaceElevated,
                borderRadius: BorderRadius.circular(widget.isCenter ? 20 : 12),
                border: Border.all(
                  color: widget.isCenter
                      ? AppColors.borderActive
                      : AppColors.border,
                  width: widget.isCenter ? 1.5 : 1.0,
                ),
                boxShadow: widget.showGlow
                    ? [
                        BoxShadow(
                          color: AppColors.primary.withAlpha(
                            widget.isCenter ? 60 : 30,
                          ),
                          blurRadius: widget.isCenter ? 24 : 12,
                          offset: const Offset(0, 4),
                        ),
                      ]
                    : null,
              ),
              child: Icon(
                AppIcons.menu,
                size: effectiveIconSize,
                color: AppColors.textPrimary,
              ),
            ),
          ),
        );
      },
    );
  }
}

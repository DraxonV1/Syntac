// Reusable animated light sweep for branded surfaces and loading states.

import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

class AnimatedShine extends StatefulWidget {
  const AnimatedShine({super.key, required this.child, this.enabled = true});

  final Widget child;
  final bool enabled;

  @override
  State<AnimatedShine> createState() => _AnimatedShineState();
}

class _AnimatedShineState extends State<AnimatedShine>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1900),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.enabled) return widget.child;
    return AnimatedBuilder(
      animation: _controller,
      child: widget.child,
      builder: (context, child) {
        final progress = _controller.value;
        return ShaderMask(
          blendMode: BlendMode.srcATop,
          shaderCallback: (bounds) => LinearGradient(
            begin: Alignment(-2.2 + progress * 4.4, -1),
            end: Alignment(-1.2 + progress * 4.4, 1),
            colors: [
              Colors.transparent,
              AppColors.primaryBright.withAlpha(90),
              Colors.transparent,
            ],
            stops: const [0.35, 0.5, 0.65],
          ).createShader(bounds),
          child: child,
        );
      },
    );
  }
}

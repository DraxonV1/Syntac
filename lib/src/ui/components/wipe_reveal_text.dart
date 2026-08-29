import 'package:flutter/material.dart';

/// Cinematic text reveal widget with left-to-right wipe mask, opacity fade,
/// and luminous highlight sweep.
class WipeRevealText extends StatefulWidget {
  const WipeRevealText({
    super.key,
    required this.text,
    required this.style,
    this.duration = const Duration(milliseconds: 650),
    this.delay = const Duration(milliseconds: 100),
    this.textAlign = TextAlign.center,
    this.onComplete,
  });

  final String text;
  final TextStyle style;
  final Duration duration;
  final Duration delay;
  final TextAlign textAlign;
  final VoidCallback? onComplete;

  @override
  State<WipeRevealText> createState() => _WipeRevealTextState();
}

class _WipeRevealTextState extends State<WipeRevealText>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _wipeAnimation;
  late final Animation<double> _fadeAnimation;
  late final Animation<double> _slideAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: widget.duration);

    _wipeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.0, 0.85, curve: Curves.easeOutCubic),
      ),
    );

    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.0, 0.6, curve: Curves.easeOut),
      ),
    );

    _slideAnimation = Tween<double>(begin: 12.0, end: 0.0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.0, 0.8, curve: Curves.easeOutCubic),
      ),
    );

    if (widget.onComplete != null) {
      _controller.addStatusListener((status) {
        if (status == AnimationStatus.completed) {
          widget.onComplete!();
        }
      });
    }

    Future<void>.delayed(widget.delay, () {
      if (mounted) _controller.forward();
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return Opacity(
          opacity: _fadeAnimation.value,
          child: Transform.translate(
            offset: Offset(_slideAnimation.value, 0),
            child: ClipRect(
              clipper: _HorizontalWipeClipper(_wipeAnimation.value),
              child: Text(
                widget.text,
                style: widget.style,
                textAlign: widget.textAlign,
              ),
            ),
          ),
        );
      },
    );
  }
}

class _HorizontalWipeClipper extends CustomClipper<Rect> {
  const _HorizontalWipeClipper(this.progress);

  final double progress;

  @override
  Rect getClip(Size size) {
    return Rect.fromLTWH(0, 0, size.width * progress, size.height);
  }

  @override
  bool shouldReclip(covariant _HorizontalWipeClipper oldClipper) =>
      oldClipper.progress != progress;
}

import 'package:flutter/material.dart';

/// Motion tokens, curves, durations, and page route builders.
/// Tuned for 60/90/120Hz native Android fluidity with subtle, responsive transitions.
abstract class AppMotion {
  // Durations
  static const Duration fast = Duration(milliseconds: 150);
  static const Duration normal = Duration(milliseconds: 240);
  static const Duration smooth = Duration(milliseconds: 320);
  static const Duration entrance = Duration(milliseconds: 400);

  // Curves
  static const Curve standard = Curves.easeOutCubic;
  static const Curve snappy = Curves.easeOutQuad;
  static const Curve emphasized = Cubic(0.2, 0.0, 0.0, 1.0);
  static const Curve spring = Curves.easeOutBack;

  /// Smooth fade + subtle vertical slide transition for screen changes
  static PageRoute<T> pageRoute<T>({
    required WidgetBuilder builder,
    RouteSettings? settings,
  }) {
    return PageRouteBuilder<T>(
      settings: settings,
      pageBuilder: (context, animation, secondaryAnimation) => builder(context),
      transitionsBuilder: (context, animation, secondaryAnimation, child) {
        final curved = CurvedAnimation(parent: animation, curve: emphasized);
        return FadeTransition(
          opacity: curved,
          child: SlideTransition(
            position: Tween<Offset>(
              begin: const Offset(0, 0.03),
              end: Offset.zero,
            ).animate(curved),
            child: child,
          ),
        );
      },
      transitionDuration: normal,
    );
  }

  /// Fade + slight scale for dialogs and sheets
  static Widget scaleFadeTransition(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    final curved = CurvedAnimation(parent: animation, curve: emphasized);
    return FadeTransition(
      opacity: curved,
      child: ScaleTransition(
        scale: Tween<double>(begin: 0.96, end: 1.0).animate(curved),
        child: child,
      ),
    );
  }
}

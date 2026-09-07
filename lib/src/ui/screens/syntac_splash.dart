// Animated startup surface shown while local app state initializes.

import 'package:flutter/material.dart';

import '../../core/app_identity.dart';
import '../components/animated_shine.dart';
import '../theme/app_colors.dart';
import '../theme/app_typography.dart';

class SyntacSplash extends StatefulWidget {
  const SyntacSplash({super.key});

  @override
  State<SyntacSplash> createState() => _SyntacSplashState();
}

class _SyntacSplashState extends State<SyntacSplash>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse;

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final app = AppIdentity.instance;
    return Scaffold(
      backgroundColor: AppColors.background,
      body: Center(
        child: AnimatedBuilder(
          animation: _pulse,
          builder: (context, child) =>
              Transform.scale(scale: 0.98 + _pulse.value * 0.025, child: child),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              AnimatedShine(
                child: Container(
                  width: 96,
                  height: 96,
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: AppColors.surfaceElevated,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: AppColors.primary.withAlpha(60),
                        blurRadius: 30,
                        spreadRadius: 4,
                      ),
                    ],
                  ),
                  child: Image.asset(
                    'assets/branding/syntac-logo.png',
                    fit: BoxFit.contain,
                    errorBuilder: (_, error, stackTrace) => const Icon(
                      Icons.auto_awesome,
                      size: 48,
                      color: AppColors.primaryBright,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              Text(app.appName, style: AppTypography.display),
              const SizedBox(height: 6),
              Text(
                app.tagline,
                style: AppTypography.bodySmall.copyWith(
                  color: AppColors.textMuted,
                ),
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: 96,
                child: LinearProgressIndicator(
                  minHeight: 2,
                  backgroundColor: AppColors.surfaceFloating,
                  valueColor: const AlwaysStoppedAnimation<Color>(
                    AppColors.primary,
                  ),
                ),
              ),
              const SizedBox(height: 12),
              const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

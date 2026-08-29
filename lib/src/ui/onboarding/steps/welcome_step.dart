import 'package:flutter/material.dart';
import 'dart:async';
import '../../../core/app_identity.dart';
import '../../components/wipe_reveal_text.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_icons.dart';
import '../../theme/app_typography.dart';
import '../../widgets/app_buttons.dart';

/// Step 1 — Cinematic Welcome Screen
/// Starts dark and reveals title with left->right wipe mask, soft subtitle fade,
/// and smooth button entrance.
class WelcomeStep extends StatefulWidget {
  const WelcomeStep({super.key, required this.onContinue, this.identity});

  final VoidCallback onContinue;
  final AppIdentity? identity;

  @override
  State<WelcomeStep> createState() => _WelcomeStepState();
}

class _WelcomeStepState extends State<WelcomeStep>
    with SingleTickerProviderStateMixin {
  bool _subtitleRevealed = false;
  bool _buttonRevealed = false;
  Timer? _t1;
  Timer? _t2;

  @override
  void initState() {
    super.initState();
    _t1 = Timer(const Duration(milliseconds: 200), () {
      if (mounted) setState(() => _subtitleRevealed = true);
    });
    _t2 = Timer(const Duration(milliseconds: 400), () {
      if (mounted) setState(() => _buttonRevealed = true);
    });
  }

  @override
  void dispose() {
    _t1?.cancel();
    _t2?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final app = widget.identity ?? AppIdentity.instance;
    final media = MediaQuery.of(context);
    final isLandscape = media.orientation == Orientation.landscape;

    return Center(
      child: SingleChildScrollView(
        padding: EdgeInsets.symmetric(
          horizontal: isLandscape ? 48 : 24,
          vertical: 32,
        ),
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: isLandscape ? 600 : 380),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // Logo with soft luminous glow
              AnimatedOpacity(
                opacity: _subtitleRevealed ? 1.0 : 0.0,
                duration: const Duration(milliseconds: 400),
                child: Container(
                  width: 64,
                  height: 64,
                  decoration: BoxDecoration(
                    color: AppColors.surfaceFloating,
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(
                      color: AppColors.borderActive,
                      width: 1.5,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: AppColors.primary.withAlpha(50),
                        blurRadius: 28,
                        offset: const Offset(0, 6),
                      ),
                    ],
                  ),
                  child: const Icon(
                    AppIcons.prompt,
                    size: 30,
                    color: AppColors.primaryBright,
                  ),
                ),
              ),
              const SizedBox(height: 28),

              // Title with Wipe Reveal Mask
              WipeRevealText(
                text: app.welcomeTitle,
                style: AppTypography.display.copyWith(
                  fontSize: isLandscape ? 32 : 28,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.6,
                ),
                duration: const Duration(milliseconds: 700),
              ),
              const SizedBox(height: 12),

              // Subtitle soft fade
              AnimatedOpacity(
                opacity: _subtitleRevealed ? 1.0 : 0.0,
                duration: const Duration(milliseconds: 500),
                child: Text(
                  app.tagline,
                  style: AppTypography.bodyLarge.copyWith(
                    color: AppColors.textSecondary,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
              const SizedBox(height: 36),

              // Feature Badges
              AnimatedOpacity(
                opacity: _subtitleRevealed ? 1.0 : 0.0,
                duration: const Duration(milliseconds: 500),
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  alignment: WrapAlignment.center,
                  children: [
                    _buildFeaturePill(AppIcons.code, 'Local-first'),
                    _buildFeaturePill(AppIcons.terminal, 'Isolated Shell'),
                    _buildFeaturePill(AppIcons.model, 'Multi-model'),
                  ],
                ),
              ),
              const SizedBox(height: 48),

              // Continue Button
              AnimatedSlide(
                offset: _buttonRevealed ? Offset.zero : const Offset(0, 0.2),
                duration: const Duration(milliseconds: 400),
                curve: Curves.easeOutCubic,
                child: AnimatedOpacity(
                  opacity: _buttonRevealed ? 1.0 : 0.0,
                  duration: const Duration(milliseconds: 300),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 320),
                    child: SizedBox(
                      width: double.infinity,
                      child: AppButton(
                        label: 'Get Started',
                        icon: AppIcons.forward,
                        onPressed: widget.onContinue,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFeaturePill(IconData icon, String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.surfaceElevated,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.border, width: 1),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: AppColors.primaryBright),
          const SizedBox(width: 6),
          Text(
            label,
            style: AppTypography.labelMedium.copyWith(
              color: AppColors.textPrimary,
            ),
          ),
        ],
      ),
    );
  }
}

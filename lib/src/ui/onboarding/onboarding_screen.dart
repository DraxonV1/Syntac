import 'dart:async';
import 'package:flutter/material.dart';

import '../../app.dart';
import '../../core/app_identity.dart';
import '../../models.dart';
import '../theme/app_colors.dart';
import '../theme/app_icons.dart';
import '../theme/app_typography.dart';
import '../widgets/app_buttons.dart';
import 'steps/project_step.dart';
import 'steps/prompt_step.dart';
import 'steps/provider_step.dart';
import 'steps/review_step.dart';
import 'steps/runtime_step.dart';
import 'steps/welcome_step.dart';

/// Sequential 6-step onboarding wizard for first-launch and setup flows.
class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({
    super.key,
    required this.controller,
    required this.onComplete,
    this.initialStep = 0,
    this.identity,
  });

  final AppController controller;
  final VoidCallback onComplete;
  final int initialStep;
  final AppIdentity? identity;

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  late final PageController _pageController;
  int _currentStep = 0;
  final int _totalSteps = 6;

  @override
  void initState() {
    super.initState();
    _currentStep = widget.initialStep.clamp(0, _totalSteps - 1);
    _pageController = PageController(initialPage: _currentStep);
    _restoreStep();
  }

  Future<void> _restoreStep() async {
    try {
      final state = await widget.controller.repository.readOnboardingState();
      if (!state.completed &&
          state.step > 0 &&
          state.step < _totalSteps &&
          mounted) {
        setState(() {
          _currentStep = state.step;
        });
        _pageController.jumpToPage(_currentStep);
      }
    } catch (_) {}
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  Future<void> _goToStep(int step) async {
    if (step < 0 || step >= _totalSteps) return;
    setState(() {
      _currentStep = step;
    });
    await _pageController.animateToPage(
      step,
      duration: const Duration(milliseconds: 320),
      curve: Curves.easeOutCubic,
    );
    unawaited(
      widget.controller.repository.saveOnboardingState(
        OnboardingState(completed: false, step: step),
      ),
    );
  }

  void _handleBack() {
    if (_currentStep > 0) {
      _goToStep(_currentStep - 1);
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = widget.identity ?? AppIdentity.instance;

    return PopScope(
      canPop: _currentStep == 0,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && _currentStep > 0) {
          _handleBack();
        }
      },
      child: Scaffold(
        backgroundColor: AppColors.background,
        appBar: AppBar(
          leading: _currentStep > 0
              ? AppIconButton(
                  icon: AppIcons.back,
                  tooltip: 'Previous Step',
                  size: 32,
                  iconSize: 18,
                  onPressed: _handleBack,
                )
              : null,
          title: Text(app.appName, style: AppTypography.titleMedium),
          actions: [
            if (_currentStep > 0) ...[
              Padding(
                padding: const EdgeInsets.only(right: 16),
                child: Center(
                  child: Text(
                    'Step ${_currentStep + 1} of $_totalSteps',
                    style: AppTypography.label,
                  ),
                ),
              ),
            ],
          ],
          bottom: PreferredSize(
            preferredSize: const Size.fromHeight(3),
            child: LinearProgressIndicator(
              value: (_currentStep + 1) / _totalSteps,
              backgroundColor: AppColors.surfaceFloating,
              valueColor: const AlwaysStoppedAnimation<Color>(
                AppColors.primary,
              ),
              minHeight: 3,
            ),
          ),
        ),
        body: SafeArea(
          child: PageView(
            controller: _pageController,
            physics: const NeverScrollableScrollPhysics(),
            children: [
              WelcomeStep(identity: app, onContinue: () => _goToStep(1)),
              ProviderStep(
                controller: widget.controller,
                identity: app,
                onNext: () => _goToStep(2),
              ),
              PromptStep(
                controller: widget.controller,
                onNext: () => _goToStep(3),
              ),
              ReviewStep(
                controller: widget.controller,
                identity: app,
                onNext: () => _goToStep(4),
              ),
              RuntimeStep(
                controller: widget.controller,
                identity: app,
                onNext: () => _goToStep(5),
              ),
              ProjectStep(
                controller: widget.controller,
                identity: app,
                onFinish: widget.onComplete,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

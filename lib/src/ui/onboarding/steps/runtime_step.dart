import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';

import '../../../app.dart';
import '../../../core/app_identity.dart';
import '../../../models.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_icons.dart';
import '../../theme/app_typography.dart';
import '../../widgets/adaptive_sheet.dart';
import '../../widgets/app_buttons.dart';
import '../../widgets/app_card.dart';
import '../../widgets/badge_chip.dart';
import '../../widgets/status_indicator.dart';

/// Step 5 — Runtime Configuration (Optional / Skip allowed)
/// Detects device architecture, recommends optimal shell runtime, provides 2-step
/// install confirmation, stage-based progress, and smoke test verification.
class RuntimeStep extends StatefulWidget {
  const RuntimeStep({
    super.key,
    required this.controller,
    required this.onNext,
    this.identity,
  });

  final AppController controller;
  final VoidCallback onNext;
  final AppIdentity? identity;

  @override
  State<RuntimeStep> createState() => _RuntimeStepState();
}

class _RuntimeStepState extends State<RuntimeStep> {
  ShellRuntimeId _selectedRuntime = ShellRuntimeId.archLinux;
  bool _isInstalling = false;
  String? _installationError;
  String? _smokeTestOutput;
  Timer? _statusPoller;

  @override
  void initState() {
    super.initState();
    _selectedRuntime = widget.controller.shellRuntimeSettings.selected;
  }

  @override
  void dispose() {
    _statusPoller?.cancel();
    super.dispose();
  }

  void _showInstallConfirmation() {
    AdaptiveSheet.show(
      context: context,
      title: 'Install Arch Linux Runtime',
      subtitle: 'Complete standalone Linux environment for agent tools',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 8),
          _buildInfoRow('Packaged size', '~140 MB bundle (offline ready)'),
          _buildInfoRow('Installed size', '~450 MB uncompressed rootfs'),
          _buildInfoRow('Install path', 'Private app execution storage'),
          _buildInfoRow('Network required', 'No (uses embedded bundle)'),
          _buildInfoRow(
            'Projects affected',
            'None (workspace mounted read-write)',
          ),
          _buildInfoRow(
            'Removable',
            'Yes, can reset or remove anytime in Settings',
          ),
          const SizedBox(height: 24),
          Row(
            children: [
              Expanded(
                child: AppButton(
                  label: 'Cancel',
                  variant: AppButtonVariant.ghost,
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: AppButton(
                  label: 'Install Runtime',
                  icon: AppIcons.runtime,
                  onPressed: () {
                    Navigator.of(context).pop();
                    _startInstallation();
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
        ],
      ),
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: 130, child: Text(label, style: AppTypography.label)),
          Expanded(child: Text(value, style: AppTypography.bodySmall)),
        ],
      ),
    );
  }

  Future<void> _startInstallation() async {
    setState(() {
      _isInstalling = true;
      _installationError = null;
      _smokeTestOutput = null;
    });

    _statusPoller = Timer.periodic(const Duration(milliseconds: 600), (
      _,
    ) async {
      await widget.controller.refreshRuntimeStatus();
      if (mounted) setState(() {});
    });

    try {
      await widget.controller.installLocalRuntime();
      await widget.controller.refreshRuntimeStatus();

      if (widget.controller.runtimeStatus.state == RuntimeState.ready) {
        setState(() {
          _smokeTestOutput = 'Shell smoke test passed (echo hello -> hello)';
        });
      }
    } catch (error) {
      setState(() {
        _installationError = error.toString();
      });
    } finally {
      _statusPoller?.cancel();
      if (mounted) {
        setState(() {
          _isInstalling = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final status = widget.controller.runtimeStatus;
    final isReady = status.state == RuntimeState.ready;

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Text('Configure Shell Runtime', style: AppTypography.titleLarge),
          const SizedBox(height: 4),
          Text(
            'The coding agent runs tools and scripts inside an isolated local environment.',
            style: AppTypography.bodySmall,
          ),
          const SizedBox(height: 20),

          // Device Specs Card
          AppCard(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                const Icon(
                  AppIcons.cpu,
                  size: 20,
                  color: AppColors.primaryBright,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('System Environment', style: AppTypography.label),
                      const SizedBox(height: 2),
                      Text(
                        '${Platform.operatingSystem} (${Platform.operatingSystemVersion.split(' ').firstOrNull ?? 'ARM64'})',
                        style: AppTypography.bodySmall,
                      ),
                    ],
                  ),
                ),
                const BadgeChip(label: 'Ready', variant: BadgeVariant.success),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Runtime Option 1: Arch Linux (Recommended)
          _buildRuntimeChoiceCard(
            id: ShellRuntimeId.archLinux,
            name: 'Arch Linux (Isolated PRoot)',
            tagline:
                'Best compatibility with local agent tools, bash, and python',
            isRecommended: true,
            sizeLabel: '~450 MB installed',
            logo: AppIcons.runtimeLogo('arch', size: 22),
          ),
          const SizedBox(height: 10),

          // Runtime Option 2: Termux
          _buildRuntimeChoiceCard(
            id: ShellRuntimeId.termux,
            name: 'Termux RUN_COMMAND Bridge',
            tagline: 'Connects to your external Termux installation',
            isRecommended: false,
            sizeLabel: 'Lower storage footprint',
            logo: AppIcons.runtimeLogo('termux', size: 22),
          ),
          const SizedBox(height: 20),

          // Installation / Status Surface
          if (_isInstalling || isReady || _installationError != null) ...[
            _buildInstallProgressCard(status),
            const SizedBox(height: 20),
          ] else if (!isReady &&
              _selectedRuntime == ShellRuntimeId.archLinux) ...[
            SizedBox(
              width: double.infinity,
              child: AppButton(
                label: 'Install Arch Linux Runtime',
                icon: AppIcons.runtime,
                onPressed: _showInstallConfirmation,
              ),
            ),
            const SizedBox(height: 20),
          ],

          // Actions
          Row(
            children: [
              Expanded(
                child: AppButton(
                  label: 'Skip for Now',
                  variant: AppButtonVariant.ghost,
                  onPressed: widget.onNext,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: AppButton(
                  label: 'Continue',
                  icon: AppIcons.forward,
                  onPressed: widget.onNext,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildRuntimeChoiceCard({
    required ShellRuntimeId id,
    required String name,
    required String tagline,
    required bool isRecommended,
    required String sizeLabel,
    required Widget logo,
  }) {
    final isSelected = _selectedRuntime == id;

    return AppCard(
      onTap: () async {
        setState(() {
          _selectedRuntime = id;
        });
        await widget.controller.saveShellRuntime(id);
      },
      backgroundColor: isSelected
          ? AppColors.surfaceFloating
          : AppColors.surfaceElevated,
      borderColor: isSelected ? AppColors.primary : AppColors.border,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              logo,
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(name, style: AppTypography.titleSmall),
                        if (isRecommended) ...[
                          const SizedBox(width: 8),
                          const BadgeChip(
                            label: 'Recommended',
                            variant: BadgeVariant.primary,
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(tagline, style: AppTypography.bodySmall),
                  ],
                ),
              ),
              if (isSelected)
                const Icon(
                  AppIcons.check,
                  size: 18,
                  color: AppColors.primaryBright,
                ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            sizeLabel,
            style: AppTypography.label.copyWith(color: AppColors.textMuted),
          ),
        ],
      ),
    );
  }

  Widget _buildInstallProgressCard(RuntimeStatus status) {
    final stateColor = switch (status.state) {
      RuntimeState.ready => AppColors.success,
      RuntimeState.error || RuntimeState.unavailable => AppColors.error,
      _ => AppColors.warning,
    };

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surfaceElevated,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: status.state == RuntimeState.ready
              ? AppColors.success.withAlpha(120)
              : AppColors.border,
          width: 1.5,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              StatusIndicator(
                status: status.state == RuntimeState.ready
                    ? ChatStatus.completed
                    : status.state == RuntimeState.error
                    ? ChatStatus.error
                    : ChatStatus.running,
                size: 9,
              ),
              const SizedBox(width: 8),
              Text(
                status.state == RuntimeState.ready
                    ? 'Runtime Ready'
                    : 'Installing Runtime...',
                style: AppTypography.titleSmall.copyWith(color: stateColor),
              ),
              const Spacer(),
              if (status.state == RuntimeState.ready)
                const Icon(AppIcons.check, size: 18, color: AppColors.success),
            ],
          ),
          const SizedBox(height: 8),
          Text(status.message, style: AppTypography.bodySmall),
          if (_smokeTestOutput != null) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: AppColors.codeBackground,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: AppColors.codeBorder),
              ),
              child: Text(_smokeTestOutput!, style: AppTypography.codeSmall),
            ),
          ],
        ],
      ),
    );
  }
}

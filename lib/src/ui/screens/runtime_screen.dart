import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app.dart';
import '../../models.dart';
import '../theme/app_colors.dart';
import '../theme/app_icons.dart';
import '../theme/app_typography.dart';
import '../widgets/adaptive_sheet.dart';
import '../widgets/app_buttons.dart';
import '../widgets/app_card.dart';
import '../widgets/app_modal.dart';
import '../widgets/badge_chip.dart';
import '../widgets/maximizable_surface.dart';
import '../widgets/status_indicator.dart';

/// Standalone top-level screen for managing shell runtimes, rootfs installation,
/// environment diagnostics, and terminal tests.
class RuntimeScreen extends StatefulWidget {
  const RuntimeScreen({super.key, required this.controller});

  final AppController controller;

  @override
  State<RuntimeScreen> createState() => _RuntimeScreenState();
}

class _RuntimeScreenState extends State<RuntimeScreen> {
  bool _isInstalling = false;
  Timer? _statusPoller;

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
    setState(() => _isInstalling = true);

    _statusPoller = Timer.periodic(const Duration(milliseconds: 600), (
      _,
    ) async {
      await widget.controller.refreshRuntimeStatus();
      if (mounted) setState(() {});
    });

    try {
      await widget.controller.installLocalRuntime();
      await widget.controller.refreshRuntimeStatus();
    } finally {
      _statusPoller?.cancel();
      if (mounted) setState(() => _isInstalling = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final status = widget.controller.runtimeStatus;
    final selectedRuntime = widget.controller.shellRuntimeSettings.selected;
    final media = MediaQuery.of(context);
    final isLandscape = media.orientation == Orientation.landscape;
    final needsStorageAccess =
        Platform.isAndroid &&
        (status.details?.contains('All files access: no') ?? false);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Shell Runtime'),
        actions: [
          AppIconButton(
            icon: AppIcons.refresh,
            tooltip: 'Refresh Status',
            size: 32,
            iconSize: 18,
            onPressed: () => widget.controller.refreshRuntimeStatus(),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          // Runtime Status Card
          AppCard(
            padding: const EdgeInsets.all(16),
            backgroundColor: AppColors.surfaceElevated,
            child: Row(
              children: [
                AppIcons.runtimeLogo(selectedRuntime.name, size: 28),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        selectedRuntime.label,
                        style: AppTypography.titleMedium,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        status.message,
                        style: AppTypography.bodySmall.copyWith(
                          color: status.state == RuntimeState.ready
                              ? AppColors.successText
                              : AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
                StatusIndicator(
                  status: status.state == RuntimeState.ready
                      ? ChatStatus.completed
                      : ChatStatus.error,
                  size: 10,
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Environment Details
          _buildEnvironmentCard(isLandscape),
          const SizedBox(height: 16),

          // Runtime Selection
          Text('SELECT ACTIVE RUNTIME', style: AppTypography.label),
          const SizedBox(height: 8),
          _buildChoiceTile(
            id: ShellRuntimeId.archLinux,
            name: 'Arch Linux (Isolated PRoot)',
            tagline:
                'Full local package ecosystem with python, bash, and tools',
            logo: AppIcons.runtimeLogo('arch', size: 22),
            isRecommended: true,
          ),
          const SizedBox(height: 8),
          _buildChoiceTile(
            id: ShellRuntimeId.termux,
            name: 'Termux RUN_COMMAND Bridge',
            tagline: 'Runs commands through external Termux app service',
            logo: AppIcons.runtimeLogo('termux', size: 22),
            isRecommended: false,
          ),
          const SizedBox(height: 20),

          // Actions for Arch Linux
          if (selectedRuntime == ShellRuntimeId.archLinux) ...[
            Text('RUNTIME MANAGEMENT', style: AppTypography.label),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                AppButton(
                  label: status.state == RuntimeState.ready
                      ? 'Reinstall / Repair'
                      : 'Install Arch Linux',
                  icon: AppIcons.runtime,
                  loading: _isInstalling,
                  compact: true,
                  onPressed: _showInstallConfirmation,
                ),
                AppButton(
                  label: 'Run Shell Test',
                  icon: AppIcons.terminal,
                  compact: true,
                  variant: AppButtonVariant.secondary,
                  onPressed: () => widget.controller.retryLocalRuntimeTest(),
                ),
                if (needsStorageAccess)
                  AppButton(
                    label: 'Grant Storage Access',
                    icon: AppIcons.folder,
                    compact: true,
                    variant: AppButtonVariant.secondary,
                    onPressed: () =>
                        widget.controller.openAndroidStorageSettings(),
                  ),
                AppButton(
                  label: 'Remove Rootfs',
                  compact: true,
                  variant: AppButtonVariant.danger,
                  onPressed: () async {
                    final confirmed = await showConfirmDialog(
                      context,
                      title: 'Remove Arch Linux Runtime',
                      message:
                          'Delete private Arch Linux rootfs files? Workspace projects will not be touched.',
                      confirmLabel: 'Remove',
                      isDestructive: true,
                    );
                    if (confirmed) {
                      await widget.controller.removeLocalRuntime();
                    }
                  },
                ),
              ],
            ),
            const SizedBox(height: 20),
          ],

          // Diagnostics
          MaximizableSurface(
            title: 'Environment Diagnostics',
            subtitle: 'Self-test & system inspection output',
            icon: AppIcons.terminal,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    AppButton(
                      label: 'Run Diagnostics Probe',
                      icon: AppIcons.terminal,
                      compact: true,
                      loading: widget.controller.diagnosticsRunning,
                      onPressed: () =>
                          widget.controller.runRuntimeDiagnostics(),
                    ),
                    const SizedBox(width: 8),
                    if (widget.controller.diagnosticsText != null)
                      AppIconButton(
                        icon: AppIcons.copy,
                        tooltip: 'Copy',
                        size: 32,
                        iconSize: 16,
                        onPressed: () {
                          Clipboard.setData(
                            ClipboardData(
                              text: widget.controller.diagnosticsText!,
                            ),
                          );
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Diagnostics copied')),
                          );
                        },
                      ),
                  ],
                ),
                if (widget.controller.diagnosticsText != null) ...[
                  const SizedBox(height: 10),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: AppColors.codeBackground,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: AppColors.codeBorder),
                    ),
                    child: SelectableText(
                      widget.controller.diagnosticsText!,
                      style: AppTypography.codeSmall,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEnvironmentCard(bool isLandscape) {
    return AppCard(
      padding: const EdgeInsets.all(14),
      backgroundColor: AppColors.surfaceElevated,
      child: Row(
        children: [
          Expanded(child: _buildMetric('Platform', Platform.operatingSystem)),
          Expanded(
            child: _buildMetric(
              'Architecture',
              Platform.operatingSystemVersion.split(' ').firstOrNull ?? 'ARM64',
            ),
          ),
          Expanded(child: _buildMetric('Isolated PRoot', 'Enabled')),
        ],
      ),
    );
  }

  Widget _buildMetric(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: AppTypography.label),
        const SizedBox(height: 2),
        Text(
          value,
          style: AppTypography.titleSmall.copyWith(fontSize: 13),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ],
    );
  }

  Widget _buildChoiceTile({
    required ShellRuntimeId id,
    required String name,
    required String tagline,
    required Widget logo,
    required bool isRecommended,
  }) {
    final isSelected = widget.controller.shellRuntimeSettings.selected == id;

    return AppCard(
      onTap: () => widget.controller.saveShellRuntime(id),
      padding: const EdgeInsets.all(14),
      backgroundColor: isSelected
          ? AppColors.surfaceFloating
          : AppColors.surfaceElevated,
      borderColor: isSelected ? AppColors.primary : AppColors.border,
      child: Row(
        children: [
          logo,
          const SizedBox(width: 12),
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
    );
  }
}

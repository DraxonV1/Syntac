import 'dart:async';
import 'package:flutter/material.dart';

import '../../agent/system_prompt.dart';
import '../../app.dart';
import '../../core/app_identity.dart';
import '../../models.dart';
import '../../storage/storage_stats.dart';
import '../onboarding/onboarding_screen.dart';
import '../theme/app_colors.dart';
import '../theme/app_icons.dart';
import '../theme/app_motion.dart';
import '../theme/app_typography.dart';
import '../widgets/app_buttons.dart';
import '../widgets/app_card.dart';
import '../widgets/badge_chip.dart';
import '../widgets/maximizable_surface.dart';
import '../widgets/status_indicator.dart';
import 'provider_dialog.dart';
import 'runtime_screen.dart';

enum SettingsCategory {
  general,
  appearance,
  agent,
  providers,
  runtime,
  storage,
  developer,
  system,
}

/// Comprehensive Settings screen supporting portrait drill-down categories
/// and responsive desktop/tablet two-pane landscape layout.
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({
    super.key,
    required this.controller,
    this.initialCategory = SettingsCategory.general,
  });

  final AppController controller;
  final SettingsCategory initialCategory;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late SettingsCategory _selectedCategory;
  late final TextEditingController _iterationsController;
  late final TextEditingController _timeoutController;
  late final TextEditingController _contextCharsController;
  late final TextEditingController _promptController;

  bool _isSavingLimits = false;
  String? _limitsFeedback;
  StorageStatsResult? _storageStats;
  bool _isLoadingStorage = false;

  @override
  void initState() {
    super.initState();
    _selectedCategory = widget.initialCategory;
    final limits = widget.controller.limits;
    _iterationsController = TextEditingController(
      text: limits.maxIterations.toString(),
    );
    _timeoutController = TextEditingController(
      text: limits.commandTimeoutSeconds.toString(),
    );
    _contextCharsController = TextEditingController(
      text: limits.maxContextCharacters.toString(),
    );
    _promptController = TextEditingController(text: codingAgentSystemPrompt);
    _loadGlobalPrompt();
    _loadStorageStats();
  }

  Future<void> _loadGlobalPrompt() async {
    final prompt = await widget.controller.repository.readGlobalSystemPrompt();
    if (prompt != null && prompt.trim().isNotEmpty && mounted) {
      setState(() {
        _promptController.text = prompt;
      });
    }
  }

  Future<void> _loadStorageStats() async {
    setState(() => _isLoadingStorage = true);
    try {
      final stats = await StorageStatsService.computeStats(
        widget.controller.repository,
      );
      if (mounted) {
        setState(() => _storageStats = stats);
      }
    } finally {
      if (mounted) setState(() => _isLoadingStorage = false);
    }
  }

  @override
  void dispose() {
    _iterationsController.dispose();
    _timeoutController.dispose();
    _contextCharsController.dispose();
    _promptController.dispose();
    super.dispose();
  }

  Future<void> _saveLimits() async {
    setState(() {
      _isSavingLimits = true;
      _limitsFeedback = null;
    });

    final iters = int.tryParse(_iterationsController.text.trim()) ?? 12;
    final timeout = int.tryParse(_timeoutController.text.trim()) ?? 120;
    final contextChars =
        int.tryParse(_contextCharsController.text.trim()) ?? 64000;

    await widget.controller.saveLimits(
      AgentLimits(
        maxIterations: iters.clamp(1, 100),
        commandTimeoutSeconds: timeout.clamp(10, 1800),
        maxContextCharacters: contextChars.clamp(4000, 500000),
      ),
    );

    if (mounted) {
      setState(() {
        _isSavingLimits = false;
        _limitsFeedback = 'Saved';
      });
    }
  }

  Future<void> _savePrompt() async {
    final prompt = _promptController.text.trim();
    await widget.controller.repository.saveGlobalSystemPrompt(
      prompt.isEmpty ? codingAgentSystemPrompt : prompt,
    );
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('System prompt instructions saved'),
          duration: Duration(seconds: 2),
        ),
      );
    }
  }

  void _rerunOnboarding() {
    Navigator.of(context).push(
      AppMotion.pageRoute(
        builder: (context) => OnboardingScreen(
          controller: widget.controller,
          onComplete: () {
            Navigator.of(context).pop();
            widget.controller.refreshAll();
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth >= 720;

        if (isWide) {
          return _buildWideLayout(context);
        }
        return _buildNarrowLayout(context);
      },
    );
  }

  Widget _buildWideLayout(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Settings'),
        leading: AppIconButton(
          icon: AppIcons.back,
          tooltip: 'Back',
          size: 32,
          iconSize: 18,
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: Row(
        children: [
          // Left Sidebar Navigation
          Container(
            width: 240,
            decoration: const BoxDecoration(
              color: AppColors.surface,
              border: Border(
                right: BorderSide(color: AppColors.borderSoft, width: 1),
              ),
            ),
            child: ListView(
              padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
              children: [
                _buildCategoryItem(
                  SettingsCategory.general,
                  'General',
                  AppIcons.settings,
                ),
                _buildCategoryItem(
                  SettingsCategory.appearance,
                  'Appearance',
                  AppIcons.model,
                ),
                _buildCategoryItem(
                  SettingsCategory.agent,
                  'Agent Limits',
                  AppIcons.prompt,
                ),
                _buildCategoryItem(
                  SettingsCategory.providers,
                  'AI Providers',
                  AppIcons.key,
                ),
                _buildCategoryItem(
                  SettingsCategory.runtime,
                  'Shell Runtime',
                  AppIcons.runtime,
                ),
                _buildCategoryItem(
                  SettingsCategory.storage,
                  'Storage',
                  AppIcons.storage,
                ),
                const Divider(height: 20, color: AppColors.borderSoft),
                Padding(
                  padding: const EdgeInsets.only(left: 8, bottom: 4),
                  child: Text(
                    'TECHNICAL',
                    style: AppTypography.label.copyWith(
                      color: AppColors.textMuted,
                    ),
                  ),
                ),
                _buildCategoryItem(
                  SettingsCategory.developer,
                  'Developer',
                  AppIcons.terminal,
                ),
                _buildCategoryItem(
                  SettingsCategory.system,
                  'System Info',
                  AppIcons.info,
                ),
              ],
            ),
          ),

          // Right Pane Content
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 680),
                child: _buildCategoryContent(_selectedCategory),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNarrowLayout(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          _buildNarrowCategoryTile(
            SettingsCategory.general,
            'General',
            'App preferences and workspace defaults',
            AppIcons.settings,
          ),
          _buildNarrowCategoryTile(
            SettingsCategory.appearance,
            'Appearance',
            'Theme mode and design tokens',
            AppIcons.model,
          ),
          _buildNarrowCategoryTile(
            SettingsCategory.agent,
            'Agent & System Prompt',
            'Iteration limits, timeouts, and system instructions',
            AppIcons.prompt,
          ),
          _buildNarrowCategoryTile(
            SettingsCategory.providers,
            'AI Providers',
            '${widget.controller.providers.length} configured endpoints',
            AppIcons.key,
          ),
          _buildNarrowCategoryTile(
            SettingsCategory.runtime,
            'Shell Runtime',
            widget.controller.shellRuntimeSettings.selected.label,
            AppIcons.runtime,
          ),
          _buildNarrowCategoryTile(
            SettingsCategory.storage,
            'Storage & Data',
            'App data and transcript size breakdown',
            AppIcons.storage,
          ),
          const SizedBox(height: 20),
          Text(
            'TECHNICAL',
            style: AppTypography.label.copyWith(color: AppColors.textMuted),
          ),
          const SizedBox(height: 8),
          _buildNarrowCategoryTile(
            SettingsCategory.developer,
            'Developer Diagnostics',
            'Probes, test runners, and diagnostic logs',
            AppIcons.terminal,
          ),
          _buildNarrowCategoryTile(
            SettingsCategory.system,
            'System & About',
            'App identity, version, and setup wizard',
            AppIcons.info,
          ),
        ],
      ),
    );
  }

  Widget _buildCategoryItem(
    SettingsCategory category,
    String title,
    IconData icon,
  ) {
    final isSelected = _selectedCategory == category;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Material(
        color: isSelected ? AppColors.surfaceFloating : Colors.transparent,
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: () => setState(() => _selectedCategory = category),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(
              children: [
                Icon(
                  icon,
                  size: 18,
                  color: isSelected
                      ? AppColors.primaryBright
                      : AppColors.textSecondary,
                ),
                const SizedBox(width: 10),
                Text(
                  title,
                  style: AppTypography.bodyMedium.copyWith(
                    color: isSelected
                        ? AppColors.textPrimary
                        : AppColors.textSecondary,
                    fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildNarrowCategoryTile(
    SettingsCategory category,
    String title,
    String subtitle,
    IconData icon,
  ) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: AppCard(
        onTap: () {
          Navigator.of(context).push(
            AppMotion.pageRoute(
              builder: (ctx) => Scaffold(
                backgroundColor: AppColors.background,
                appBar: AppBar(title: Text(title)),
                body: SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: _buildCategoryContent(category),
                ),
              ),
            ),
          );
        },
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        backgroundColor: AppColors.surfaceElevated,
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: AppColors.surfaceFloating,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(icon, size: 18, color: AppColors.primaryBright),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: AppTypography.titleSmall),
                  const SizedBox(height: 2),
                  Text(subtitle, style: AppTypography.bodySmall),
                ],
              ),
            ),
            const Icon(
              AppIcons.chevronRight,
              size: 16,
              color: AppColors.textSecondary,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCategoryContent(SettingsCategory category) {
    return switch (category) {
      SettingsCategory.general => _buildGeneralPane(),
      SettingsCategory.appearance => _buildAppearancePane(),
      SettingsCategory.agent => _buildAgentPane(),
      SettingsCategory.providers => _buildProvidersPane(),
      SettingsCategory.runtime => _buildRuntimePane(),
      SettingsCategory.storage => _buildStoragePane(),
      SettingsCategory.developer => _buildDeveloperPane(),
      SettingsCategory.system => _buildSystemPane(),
    };
  }

  Widget _buildGeneralPane() {
    final app = AppIdentity.instance;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('General Settings', style: AppTypography.titleMedium),
        const SizedBox(height: 12),
        AppCard(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('WORKSPACE ROOT', style: AppTypography.label),
              const SizedBox(height: 4),
              Text(
                app.defaultSharedStoragePath,
                style: AppTypography.codeSmall,
              ),
              const SizedBox(height: 14),
              Text('URI SCHEME', style: AppTypography.label),
              const SizedBox(height: 4),
              Text(
                '${app.appScheme}://auth/callback',
                style: AppTypography.codeSmall,
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildAppearancePane() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Appearance', style: AppTypography.titleMedium),
        const SizedBox(height: 12),
        AppCard(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              const Icon(
                AppIcons.model,
                size: 20,
                color: AppColors.primaryBright,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Dark Blue System Theme',
                      style: AppTypography.titleSmall,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Optimized for mobile OLED and developer coding environments',
                      style: AppTypography.bodySmall,
                    ),
                  ],
                ),
              ),
              const BadgeChip(label: 'Active', variant: BadgeVariant.primary),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildAgentPane() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Agent & System Prompt', style: AppTypography.titleMedium),
        const SizedBox(height: 12),

        // Limits Card
        AppCard(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('BEHAVIOR LIMITS', style: AppTypography.label),
              const SizedBox(height: 10),
              TextField(
                controller: _iterationsController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Max Iterations per Turn',
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _timeoutController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Command Timeout (seconds)',
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _contextCharsController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Max Context Characters',
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  AppButton(
                    label: 'Save Limits',
                    compact: true,
                    loading: _isSavingLimits,
                    onPressed: _saveLimits,
                  ),
                  if (_limitsFeedback != null) ...[
                    const SizedBox(width: 8),
                    Text(
                      _limitsFeedback!,
                      style: AppTypography.bodySmall.copyWith(
                        color: AppColors.success,
                      ),
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),

        // Global Prompt Card
        AppCard(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(
                    AppIcons.prompt,
                    size: 16,
                    color: AppColors.primaryBright,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Global Instructions (AGENTS.md)',
                    style: AppTypography.titleSmall,
                  ),
                ],
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _promptController,
                maxLines: 6,
                minLines: 3,
                style: AppTypography.codeSmall,
                decoration: const InputDecoration(
                  hintText: 'Custom instructions...',
                ),
              ),
              const SizedBox(height: 10),
              AppButton(
                label: 'Save Instructions',
                compact: true,
                onPressed: _savePrompt,
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildProvidersPane() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text('AI Providers', style: AppTypography.titleMedium),
            const Spacer(),
            AppButton(
              label: 'Add Provider',
              icon: AppIcons.add,
              compact: true,
              onPressed: () =>
                  showProviderConfigDialog(context, widget.controller),
            ),
          ],
        ),
        const SizedBox(height: 12),
        if (widget.controller.providers.isEmpty)
          AppCard(
            padding: const EdgeInsets.all(20),
            child: Center(
              child: Text(
                'No providers configured',
                style: AppTypography.bodySmall,
              ),
            ),
          )
        else
          for (final provider in widget.controller.providers)
            _buildProviderCard(provider),
      ],
    );
  }

  Widget _buildProviderCard(ProviderConfig provider) {
    final models = widget.controller.providerModels[provider.id] ?? const [];

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: AppCard(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            AppIcons.providerLogo(provider.providerKey, size: 22),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(provider.name, style: AppTypography.titleSmall),
                  const SizedBox(height: 2),
                  Text(
                    '${models.length} models: ${provider.baseUrl}',
                    style: AppTypography.codeSmall.copyWith(fontSize: 10.5),
                  ),
                ],
              ),
            ),
            AppIconButton(
              icon: AppIcons.refresh,
              tooltip: 'Refresh Models',
              size: 30,
              iconSize: 15,
              onPressed: () async {
                final msg = await widget.controller.refreshProviderModels(
                  provider.id,
                );
                if (mounted) {
                  ScaffoldMessenger.of(
                    context,
                  ).showSnackBar(SnackBar(content: Text(msg)));
                }
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRuntimePane() {
    final status = widget.controller.runtimeStatus;
    final selected = widget.controller.shellRuntimeSettings.selected;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text('Shell Runtime', style: AppTypography.titleMedium),
            const Spacer(),
            AppButton(
              label: 'Open Runtime Screen',
              icon: AppIcons.externalLink,
              compact: true,
              variant: AppButtonVariant.ghost,
              onPressed: () => Navigator.of(context).push(
                AppMotion.pageRoute(
                  builder: (_) => RuntimeScreen(controller: widget.controller),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        AppCard(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  AppIcons.runtimeLogo(selected.name, size: 22),
                  const SizedBox(width: 10),
                  Text(selected.label, style: AppTypography.titleSmall),
                  const Spacer(),
                  StatusIndicator(
                    status: status.state == RuntimeState.ready
                        ? ChatStatus.completed
                        : ChatStatus.error,
                    size: 8,
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(status.message, style: AppTypography.bodySmall),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildStoragePane() {
    final stats = _storageStats;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text('Storage Usage', style: AppTypography.titleMedium),
            const Spacer(),
            if (_isLoadingStorage)
              const Padding(
                padding: EdgeInsets.only(right: 8),
                child: SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            AppIconButton(
              icon: AppIcons.refresh,
              tooltip: 'Refresh Storage Stats',
              size: 28,
              iconSize: 14,
              onPressed: _loadStorageStats,
            ),
          ],
        ),
        const SizedBox(height: 12),
        AppCard(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              if (stats != null) ...[
                for (final cat in stats.categories) ...[
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(
                      children: [
                        Text(cat.label, style: AppTypography.bodySmall),
                        const Spacer(),
                        Text(cat.formattedSize, style: AppTypography.codeSmall),
                      ],
                    ),
                  ),
                ],
              ] else ...[
                const Text('Computing storage breakdown...'),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildDeveloperPane() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Developer Diagnostics', style: AppTypography.titleMedium),
        const SizedBox(height: 12),
        MaximizableSurface(
          title: 'Diagnostics Runner',
          icon: AppIcons.terminal,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AppButton(
                label: 'Run System Diagnostics',
                compact: true,
                loading: widget.controller.diagnosticsRunning,
                onPressed: () => widget.controller.runRuntimeDiagnostics(),
              ),
              if (widget.controller.diagnosticsText != null) ...[
                const SizedBox(height: 10),
                SelectableText(
                  widget.controller.diagnosticsText!,
                  style: AppTypography.codeSmall,
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildSystemPane() {
    final app = AppIdentity.instance;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('System Information', style: AppTypography.titleMedium),
        const SizedBox(height: 12),
        AppCard(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('APP DISPLAY NAME', style: AppTypography.label),
              const SizedBox(height: 2),
              Text(app.appDisplayName, style: AppTypography.bodyMedium),
              const SizedBox(height: 12),
              Text('VERSION', style: AppTypography.label),
              const SizedBox(height: 2),
              Text(
                '${app.version} (${app.versionCode}) · ${app.updateChannel}',
                style: AppTypography.bodyMedium,
              ),
              const SizedBox(height: 12),
              Text('DEVELOPER', style: AppTypography.label),
              const SizedBox(height: 2),
              Text(app.developerName, style: AppTypography.bodyMedium),
              const SizedBox(height: 12),
              Text('REPOSITORY', style: AppTypography.label),
              const SizedBox(height: 2),
              SelectableText(app.repositoryUrl, style: AppTypography.codeSmall),
              const SizedBox(height: 12),
              Text('STORAGE IDENTIFIER', style: AppTypography.label),
              const SizedBox(height: 2),
              Text(app.storageFolder, style: AppTypography.codeSmall),
              const SizedBox(height: 16),
              AppButton(
                label: 'Rerun Onboarding Wizard',
                icon: AppIcons.refresh,
                compact: true,
                variant: AppButtonVariant.secondary,
                onPressed: _rerunOnboarding,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

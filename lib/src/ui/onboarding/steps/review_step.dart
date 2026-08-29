import 'package:flutter/material.dart';

import '../../../agent/system_prompt.dart';
import '../../../app.dart';
import '../../../core/app_identity.dart';
import '../../../models.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_icons.dart';
import '../../theme/app_typography.dart';
import '../../widgets/adaptive_sheet.dart';
import '../../widgets/app_buttons.dart';
import '../../widgets/app_card.dart';

/// Step 4 — Review Configuration
/// Groups configuration into Provider, Model, Generation, System Prompt, and Storage cards.
/// Each card supports inline editing without restarting onboarding.
class ReviewStep extends StatefulWidget {
  const ReviewStep({
    super.key,
    required this.controller,
    required this.onNext,
    this.identity,
  });

  final AppController controller;
  final VoidCallback onNext;
  final AppIdentity? identity;

  @override
  State<ReviewStep> createState() => _ReviewStepState();
}

class _ReviewStepState extends State<ReviewStep> {
  String? _systemPrompt;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _loadPrompt();
  }

  Future<void> _loadPrompt() async {
    final prompt = await widget.controller.repository.readGlobalSystemPrompt();
    if (mounted) {
      setState(() {
        _systemPrompt = prompt ?? codingAgentSystemPrompt;
      });
    }
  }

  void _editModelSheet(ProviderConfig provider, List<ProviderModel> models) {
    AdaptiveSheet.show(
      context: context,
      title: 'Select Default Model',
      subtitle: provider.name,
      child: Column(
        children: [
          for (final model in models)
            ListTile(
              title: Text(model.model, style: AppTypography.bodyMedium),
              trailing: const Icon(AppIcons.chevronRight, size: 16),
              onTap: () async {
                Navigator.of(context).pop();
                await widget.controller.refreshAll();
              },
            ),
        ],
      ),
    );
  }

  void _editLimitsSheet() {
    final limits = widget.controller.limits;
    final iterController = TextEditingController(
      text: limits.maxIterations.toString(),
    );
    final timeoutController = TextEditingController(
      text: limits.commandTimeoutSeconds.toString(),
    );

    AdaptiveSheet.show(
      context: context,
      title: 'Edit Generation Limits',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 8),
          TextField(
            controller: iterController,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(labelText: 'Max Iterations'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: timeoutController,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              labelText: 'Command Timeout (seconds)',
            ),
          ),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            child: AppButton(
              label: 'Save Limits',
              onPressed: () async {
                final iters = int.tryParse(iterController.text) ?? 12;
                final timeout = int.tryParse(timeoutController.text) ?? 120;
                await widget.controller.saveLimits(
                  AgentLimits(
                    maxIterations: iters,
                    commandTimeoutSeconds: timeout,
                    maxContextCharacters: limits.maxContextCharacters,
                  ),
                );
                if (mounted) {
                  Navigator.of(context).pop();
                  setState(() {});
                }
              },
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _handleSaveAndContinue() async {
    setState(() {
      _isSaving = true;
    });
    try {
      await widget.controller.refreshAll();
      widget.onNext();
    } finally {
      if (mounted) {
        setState(() {
          _isSaving = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = widget.identity ?? AppIdentity.instance;
    final provider = widget.controller.providers.firstOrNull;
    final models = provider != null
        ? (widget.controller.providerModels[provider.id] ?? const [])
        : const <ProviderModel>[];
    final defaultModelName = models.firstOrNull?.model ?? 'Not selected';
    final limits = widget.controller.limits;

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Text('Review Configuration', style: AppTypography.titleLarge),
          const SizedBox(height: 4),
          Text(
            'Confirm your environment settings before runtime and project setup.',
            style: AppTypography.bodySmall,
          ),
          const SizedBox(height: 20),

          // Provider Card
          _buildReviewCard(
            title: 'Provider',
            icon: AppIcons.model,
            content: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  provider?.name ?? 'No provider configured',
                  style: AppTypography.titleSmall,
                ),
                const SizedBox(height: 2),
                Text(
                  provider?.baseUrl ?? '',
                  style: AppTypography.bodySmall.copyWith(
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),

          // Model Card
          _buildReviewCard(
            title: 'Model',
            icon: AppIcons.code,
            trailingAction: models.isNotEmpty
                ? AppButton(
                    label: 'Change',
                    compact: true,
                    variant: AppButtonVariant.ghost,
                    onPressed: () => _editModelSheet(provider!, models),
                  )
                : null,
            content: Text(
              defaultModelName,
              style: AppTypography.titleSmall.copyWith(
                color: AppColors.primaryBright,
              ),
            ),
          ),
          const SizedBox(height: 12),

          // Generation Limits Card
          _buildReviewCard(
            title: 'Generation & Limits',
            icon: AppIcons.settings,
            trailingAction: AppButton(
              label: 'Edit',
              compact: true,
              variant: AppButtonVariant.ghost,
              onPressed: _editLimitsSheet,
            ),
            content: Row(
              children: [
                _buildMetric('Iterations', '${limits.maxIterations}'),
                const SizedBox(width: 24),
                _buildMetric('Timeout', '${limits.commandTimeoutSeconds}s'),
                const SizedBox(width: 24),
                _buildMetric(
                  'Context',
                  '${(limits.maxContextCharacters / 1000).toStringAsFixed(0)}k',
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),

          // System Prompt Card
          _buildReviewCard(
            title: 'System Prompt',
            icon: AppIcons.prompt,
            content: Text(
              _systemPrompt != null && _systemPrompt!.length > 120
                  ? '${_systemPrompt!.substring(0, 120)}...'
                  : _systemPrompt ?? 'Default instructions',
              style: AppTypography.codeSmall,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(height: 12),

          // Storage Card
          _buildReviewCard(
            title: 'Storage & Application Data',
            icon: AppIcons.storage,
            content: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  app.defaultSharedStoragePath,
                  style: AppTypography.codeSmall,
                ),
                const SizedBox(height: 2),
                Text(
                  'Encrypted credential store & JSONL transcripts',
                  style: AppTypography.bodySmall.copyWith(
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 28),

          // Continue CTA
          SizedBox(
            width: double.infinity,
            child: AppButton(
              label: 'Save & Continue',
              icon: AppIcons.forward,
              loading: _isSaving,
              onPressed: _handleSaveAndContinue,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildReviewCard({
    required String title,
    required IconData icon,
    required Widget content,
    Widget? trailingAction,
  }) {
    return AppCard(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 16, color: AppColors.primaryBright),
              const SizedBox(width: 8),
              Text(title, style: AppTypography.label),
              const Spacer(),
              ?trailingAction,
            ],
          ),
          const SizedBox(height: 8),
          content,
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
        Text(value, style: AppTypography.titleSmall),
      ],
    );
  }
}

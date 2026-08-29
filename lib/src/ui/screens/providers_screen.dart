import 'package:flutter/material.dart';

import '../../app.dart';
import '../../models.dart';
import '../theme/app_colors.dart';
import '../theme/app_icons.dart';
import '../theme/app_typography.dart';
import '../widgets/app_buttons.dart';
import '../widgets/app_card.dart';
import '../widgets/app_modal.dart';
import '../widgets/empty_state.dart';
import '../widgets/status_indicator.dart';
import 'provider_dialog.dart';

/// Standalone top-level screen for managing AI providers and live model lists.
class ProvidersScreen extends StatefulWidget {
  const ProvidersScreen({super.key, required this.controller});

  final AppController controller;

  @override
  State<ProvidersScreen> createState() => _ProvidersScreenState();
}

class _ProvidersScreenState extends State<ProvidersScreen> {
  @override
  Widget build(BuildContext context) {
    final providers = widget.controller.providers;
    final media = MediaQuery.of(context);
    final isLandscape = media.orientation == Orientation.landscape;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('AI Providers'),
        actions: [
          AppButton(
            label: 'Add Provider',
            icon: AppIcons.add,
            compact: true,
            onPressed: () =>
                showProviderConfigDialog(context, widget.controller),
          ),
          const SizedBox(width: 12),
        ],
      ),
      body: providers.isEmpty
          ? EmptyState(
              icon: AppIcons.model,
              title: 'No providers configured',
              description:
                  'Connect Google Antigravity or a supported OpenAI-compatible LLM endpoint.',
              actionLabel: 'Connect Provider',
              actionIcon: AppIcons.add,
              onAction: () =>
                  showProviderConfigDialog(context, widget.controller),
            )
          : GridView.builder(
              padding: const EdgeInsets.all(16),
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: isLandscape ? 3 : 1,
                mainAxisSpacing: 12,
                crossAxisSpacing: 12,
                childAspectRatio: isLandscape ? 1.6 : 2.4,
              ),
              itemCount: providers.length,
              itemBuilder: (context, index) =>
                  _buildProviderTile(providers[index]),
            ),
    );
  }

  Widget _buildProviderTile(ProviderConfig provider) {
    final models = widget.controller.providerModels[provider.id] ?? const [];

    return AppCard(
      padding: const EdgeInsets.all(16),
      backgroundColor: AppColors.surfaceElevated,
      borderColor: AppColors.border,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              AppIcons.providerLogo(provider.providerKey, size: 24),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(provider.name, style: AppTypography.titleSmall),
                    const SizedBox(height: 2),
                    Text(
                      provider.baseUrl,
                      style: AppTypography.codeSmall.copyWith(
                        color: AppColors.textSecondary,
                        fontSize: 11,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              PopupMenuButton<String>(
                icon: const Icon(Icons.more_vert_rounded, size: 18),
                color: AppColors.surfaceFloating,
                onSelected: (action) async {
                  if (action == 'test') {
                    final res = await widget.controller.testProvider(
                      provider.id,
                    );
                    if (mounted) {
                      ScaffoldMessenger.of(
                        context,
                      ).showSnackBar(SnackBar(content: Text(res)));
                    }
                  } else if (action == 'refresh') {
                    final res = await widget.controller.refreshProviderModels(
                      provider.id,
                    );
                    if (mounted) {
                      ScaffoldMessenger.of(
                        context,
                      ).showSnackBar(SnackBar(content: Text(res)));
                    }
                  } else if (action == 'edit') {
                    showProviderConfigDialog(
                      context,
                      widget.controller,
                      provider: provider,
                    );
                  } else if (action == 'delete') {
                    final confirmed = await showConfirmDialog(
                      context,
                      title: 'Delete Provider',
                      message:
                          'Remove ${provider.name} and associated credentials?',
                      confirmLabel: 'Delete',
                      isDestructive: true,
                    );
                    if (confirmed) {
                      await widget.controller.deleteProvider(provider.id);
                    }
                  }
                },
                itemBuilder: (context) => [
                  const PopupMenuItem(
                    value: 'test',
                    child: Text('Test Connection'),
                  ),
                  const PopupMenuItem(
                    value: 'refresh',
                    child: Text('Refresh Models'),
                  ),
                  const PopupMenuItem(value: 'edit', child: Text('Edit')),
                  const PopupMenuItem(
                    value: 'delete',
                    child: Text(
                      'Delete',
                      style: TextStyle(color: AppColors.error),
                    ),
                  ),
                ],
              ),
            ],
          ),
          const Spacer(),
          Row(
            children: [
              const StatusIndicator(status: ChatStatus.completed, size: 7),
              const SizedBox(width: 6),
              Text(
                '${models.length} models discovered',
                style: AppTypography.bodySmall.copyWith(
                  color: AppColors.textMuted,
                ),
              ),
              const Spacer(),
              GestureDetector(
                onTap: () async {
                  final res = await widget.controller.refreshProviderModels(
                    provider.id,
                  );
                  if (mounted) {
                    ScaffoldMessenger.of(
                      context,
                    ).showSnackBar(SnackBar(content: Text(res)));
                  }
                },
                child: const Icon(
                  AppIcons.refresh,
                  size: 14,
                  color: AppColors.primaryBright,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

import 'package:flutter/material.dart';

import '../../models.dart';
import '../theme/app_colors.dart';
import '../theme/app_icons.dart';
import '../theme/app_typography.dart';
import '../widgets/adaptive_sheet.dart';
import '../widgets/app_buttons.dart';
import '../widgets/badge_chip.dart';

/// Searchable floating model selector sheet grouped by provider.
class ModelSelectorSheet extends StatefulWidget {
  const ModelSelectorSheet({
    super.key,
    required this.providers,
    required this.providerModels,
    required this.selectedModelId,
    required this.onModelSelected,
    this.onConfigureProviders,
    this.onRefreshModels,
  });

  final List<ProviderConfig> providers;
  final Map<String, List<ProviderModel>> providerModels;
  final String? selectedModelId;
  final ValueChanged<ProviderModel> onModelSelected;
  final VoidCallback? onConfigureProviders;
  final Future<void> Function(String providerId)? onRefreshModels;

  static Future<void> show({
    required BuildContext context,
    required List<ProviderConfig> providers,
    required Map<String, List<ProviderModel>> providerModels,
    required String? selectedModelId,
    required ValueChanged<ProviderModel> onModelSelected,
    VoidCallback? onConfigureProviders,
    Future<void> Function(String providerId)? onRefreshModels,
  }) {
    return AdaptiveSheet.show(
      context: context,
      title: 'Select Model',
      subtitle: 'Models discovered from connected providers',
      child: ModelSelectorSheet(
        providers: providers,
        providerModels: providerModels,
        selectedModelId: selectedModelId,
        onModelSelected: onModelSelected,
        onConfigureProviders: onConfigureProviders,
        onRefreshModels: onRefreshModels,
      ),
    );
  }

  @override
  State<ModelSelectorSheet> createState() => _ModelSelectorSheetState();
}

class _ModelSelectorSheetState extends State<ModelSelectorSheet> {
  final TextEditingController _searchController = TextEditingController();
  String _filter = '';
  bool _isRefreshing = false;

  @override
  void initState() {
    super.initState();
    _searchController.addListener(() {
      setState(() {
        _filter = _searchController.text.trim().toLowerCase();
      });
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.providers.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 24),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                AppIcons.model,
                size: 32,
                color: AppColors.primaryBright,
              ),
              const SizedBox(height: 12),
              Text('No providers configured', style: AppTypography.titleSmall),
              const SizedBox(height: 4),
              Text(
                'Configure an AI provider to enable models',
                style: AppTypography.bodySmall,
              ),
              if (widget.onConfigureProviders != null) ...[
                const SizedBox(height: 16),
                AppButton(
                  label: 'Add Provider',
                  icon: AppIcons.add,
                  onPressed: () {
                    Navigator.of(context).pop();
                    widget.onConfigureProviders!();
                  },
                ),
              ],
            ],
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        // Search bar
        TextField(
          controller: _searchController,
          style: AppTypography.bodySmall,
          decoration: InputDecoration(
            hintText: 'Search models...',
            prefixIcon: const Icon(
              AppIcons.search,
              size: 16,
              color: AppColors.textMuted,
            ),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 12,
              vertical: 10,
            ),
          ),
        ),
        const SizedBox(height: 12),

        // Provider Model Groups
        for (final provider in widget.providers) ...[
          _buildProviderGroup(provider),
          const SizedBox(height: 12),
        ],
      ],
    );
  }

  Widget _buildProviderGroup(ProviderConfig provider) {
    final allModels = widget.providerModels[provider.id] ?? const [];
    final filtered = allModels.where((m) {
      if (_filter.isEmpty) return true;
      return m.model.toLowerCase().contains(_filter) ||
          provider.name.toLowerCase().contains(_filter);
    }).toList();

    if (filtered.isEmpty && _filter.isNotEmpty) {
      return const SizedBox.shrink();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
          child: Row(
            children: [
              AppIcons.providerLogo(provider.providerKey, size: 16),
              const SizedBox(width: 8),
              Text(
                provider.name.toUpperCase(),
                style: AppTypography.label.copyWith(color: AppColors.textMuted),
              ),
              const Spacer(),
              if (widget.onRefreshModels != null)
                GestureDetector(
                  onTap: _isRefreshing
                      ? null
                      : () async {
                          setState(() => _isRefreshing = true);
                          try {
                            await widget.onRefreshModels!(provider.id);
                          } finally {
                            if (mounted) setState(() => _isRefreshing = false);
                          }
                        },
                  child: Padding(
                    padding: const EdgeInsets.all(4),
                    child: Icon(
                      AppIcons.refresh,
                      size: 14,
                      color: _isRefreshing
                          ? AppColors.primary
                          : AppColors.textMuted,
                    ),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 4),
        if (filtered.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            child: Text(
              'No models found for ${provider.name}',
              style: AppTypography.bodySmall.copyWith(
                color: AppColors.textMuted,
              ),
            ),
          )
        else
          for (final model in filtered) _buildModelRow(provider, model),
      ],
    );
  }

  Widget _buildModelRow(ProviderConfig provider, ProviderModel model) {
    final isSelected =
        widget.selectedModelId == model.id ||
        widget.selectedModelId == model.model;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Material(
        color: isSelected ? AppColors.surfaceFloating : Colors.transparent,
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: () {
            widget.onModelSelected(model);
            Navigator.of(context).pop();
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        model.model,
                        style: AppTypography.bodyMedium.copyWith(
                          color: isSelected
                              ? AppColors.textPrimary
                              : AppColors.textSecondary,
                          fontWeight: isSelected
                              ? FontWeight.w600
                              : FontWeight.w400,
                        ),
                      ),
                      if (_modelTags(model.model).isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Wrap(
                          spacing: 4,
                          children: [
                            for (final tag in _modelTags(model.model))
                              BadgeChip(
                                label: tag,
                                variant: isSelected
                                    ? BadgeVariant.primary
                                    : BadgeVariant.neutral,
                              ),
                          ],
                        ),
                      ],
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
          ),
        ),
      ),
    );
  }

  List<String> _modelTags(String modelName) {
    final lower = modelName.toLowerCase();
    final tags = <String>[];
    if (lower.contains('flash') || lower.contains('mini')) {
      tags.add('Fast');
    }
    if (lower.contains('pro') ||
        lower.contains('reasoner') ||
        lower.contains('o1') ||
        lower.contains('o3')) {
      tags.add('Reasoning');
    }
    if (lower.contains('codex') || lower.contains('code')) {
      tags.add('Coding');
    }
    return tags;
  }
}

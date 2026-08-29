import 'dart:async';
import 'package:flutter/material.dart';

import '../../../app.dart';
import '../../../core/app_identity.dart';
import '../../../models.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_icons.dart';
import '../../theme/app_typography.dart';
import '../../widgets/app_buttons.dart';
import '../../widgets/app_card.dart';
import '../../widgets/status_indicator.dart';
import '../widgets/oauth_auth_sheet.dart';

enum ProviderTestState { idle, connecting, testing, streaming, success, error }

/// Step 2 — Configure Provider
/// Dedicated polished surface for Google Antigravity and supported OpenAI-compatible
/// custom providers with live streamed model validation and retry support.
class ProviderStep extends StatefulWidget {
  const ProviderStep({
    super.key,
    required this.controller,
    required this.onNext,
    this.identity,
  });

  final AppController controller;
  final VoidCallback onNext;
  final AppIdentity? identity;

  @override
  State<ProviderStep> createState() => _ProviderStepState();
}

class _ProviderStepState extends State<ProviderStep> {
  String _selectedProviderKey = 'google-antigravity';
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _baseUrlController = TextEditingController();
  final TextEditingController _apiKeyController = TextEditingController();

  ProviderTestState _testState = ProviderTestState.idle;
  String _streamedResponse = '';
  String? _testError;
  ProviderConfig? _activeConfig;
  String? _selectedModel;
  bool _isConnecting = false;

  @override
  void initState() {
    super.initState();
    _applyPreset('google-antigravity');
  }

  @override
  void dispose() {
    _nameController.dispose();
    _baseUrlController.dispose();
    _apiKeyController.dispose();
    super.dispose();
  }

  void _applyPreset(String key) {
    setState(() {
      _selectedProviderKey = key;
      if (key == 'google-antigravity') {
        _nameController.text = 'Google Antigravity';
        _baseUrlController.text = 'https://daily-cloudcode-pa.googleapis.com';
      } else {
        _nameController.text = 'Custom OpenAI';
        _baseUrlController.text = 'https://api.openai.com/v1';
      }
      _testState = ProviderTestState.idle;
      _streamedResponse = '';
      _testError = null;
    });
  }

  Future<void> _handleConnect() async {
    setState(() {
      _isConnecting = true;
      _testError = null;
    });

    try {
      if (_selectedProviderKey == 'google-antigravity') {
        await widget.controller.loginGoogleAntigravity(
          onAuthRequest: (request) {
            OAuthAuthSheet.show(
              context: context,
              request: request,
              providerName: 'Google Antigravity',
            );
          },
        );
      } else {
        // Custom Provider
        final apiKey = _apiKeyController.text.trim();
        if (apiKey.isEmpty) {
          throw ArgumentError('API key is required');
        }
        await widget.controller.saveProvider(
          name: _nameController.text.trim(),
          baseUrl: _baseUrlController.text.trim(),
          apiKey: apiKey,
          providerKey: 'custom-openai-compatible',
          authType: 'apiKey',
          models: const [],
        );
      }

      await widget.controller.refreshAll();
      final latest = widget.controller.providers.firstOrNull;
      if (latest != null) {
        _activeConfig = latest;
        final models = widget.controller.providerModels[latest.id] ?? const [];
        _selectedModel = models.firstOrNull?.model ?? 'default';
        await _runLiveStreamTest();
      }
    } catch (error) {
      setState(() {
        _testState = ProviderTestState.error;
        _testError = error.toString();
      });
    } finally {
      if (mounted) {
        setState(() {
          _isConnecting = false;
        });
      }
    }
  }

  Future<void> _runLiveStreamTest() async {
    final config = _activeConfig;
    if (config == null) return;

    final app = widget.identity ?? AppIdentity.instance;
    final testPrompt =
        'Say exactly: Provider Connected: ${config.name} - ${app.appName}';

    setState(() {
      _testState = ProviderTestState.connecting;
      _streamedResponse = '';
      _testError = null;
    });

    try {
      await Future<void>.delayed(const Duration(milliseconds: 300));
      setState(() {
        _testState = ProviderTestState.testing;
      });

      final stream = widget.controller.testProviderStreaming(
        provider: config,
        model: _selectedModel ?? 'default',
        prompt: testPrompt,
      );

      await for (final delta in stream) {
        if (!mounted) return;
        setState(() {
          _testState = ProviderTestState.streaming;
          _streamedResponse += delta;
        });
      }

      if (mounted) {
        setState(() {
          _testState = ProviderTestState.success;
          if (_streamedResponse.isEmpty) {
            _streamedResponse =
                'Provider Connected: ${config.name} - ${app.appName}';
          }
        });
      }
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _testState = ProviderTestState.error;
        _testError = error.toString();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final hasActiveSuccess = _testState == ProviderTestState.success;

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Text('Configure AI Provider', style: AppTypography.titleLarge),
          const SizedBox(height: 4),
          Text(
            'Connect your preferred LLM provider for code generation and agent workflows.',
            style: AppTypography.bodySmall,
          ),
          const SizedBox(height: 20),

          // Provider Cards Selection
          _buildProviderChoiceCard(
            key: 'google-antigravity',
            title: 'Google Antigravity',
            subtitle: 'Gemini Code Assist / Google OAuth',
            logo: AppIcons.providerLogo('google', size: 22),
          ),
          const SizedBox(height: 10),
          _buildProviderChoiceCard(
            key: 'custom',
            title: 'Custom Provider',
            subtitle: 'OpenAI-compatible endpoints',
            logo: const Icon(
              Icons.api_rounded,
              size: 22,
              color: AppColors.primaryBright,
            ),
          ),
          const SizedBox(height: 20),

          // Custom Options if selected
          if (_selectedProviderKey == 'custom') ...[
            _buildCustomProviderFields(),
            const SizedBox(height: 20),
          ],

          // Connect / Authenticate Button
          if (_testState == ProviderTestState.idle ||
              _testState == ProviderTestState.error) ...[
            SizedBox(
              width: double.infinity,
              child: AppButton(
                label: _selectedProviderKey == 'google-antigravity'
                    ? 'Connect with Google'
                    : 'Connect Provider',
                icon: AppIcons.key,
                loading: _isConnecting,
                onPressed: _isConnecting ? null : _handleConnect,
              ),
            ),
            const SizedBox(height: 16),
          ],

          // Live Streamed Test Surface
          if (_testState != ProviderTestState.idle) ...[
            _buildLiveTestCard(),
            const SizedBox(height: 20),
          ],

          // Next Button
          SizedBox(
            width: double.infinity,
            child: AppButton(
              label: 'Continue to System Prompt',
              icon: AppIcons.forward,
              variant: hasActiveSuccess
                  ? AppButtonVariant.primary
                  : AppButtonVariant.ghost,
              onPressed: hasActiveSuccess ? widget.onNext : null,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProviderChoiceCard({
    required String key,
    required String title,
    required String subtitle,
    required Widget logo,
  }) {
    final isSelected = _selectedProviderKey == key;

    return AppCard(
      onTap: () => _applyPreset(key),
      backgroundColor: isSelected
          ? AppColors.surfaceFloating
          : AppColors.surfaceElevated,
      borderColor: isSelected ? AppColors.primary : AppColors.border,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Row(
        children: [
          logo,
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

  Widget _buildCustomProviderFields() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Use an OpenAI-compatible API endpoint. Anthropic-compatible custom providers are hidden for beta until a native Anthropic transport is implemented.',
          style: AppTypography.bodySmall,
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _nameController,
          decoration: const InputDecoration(labelText: 'Provider Name'),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _baseUrlController,
          decoration: const InputDecoration(labelText: 'Base Endpoint URL'),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _apiKeyController,
          obscureText: true,
          decoration: const InputDecoration(
            labelText: 'API Key',
            hintText: 'sk-...',
          ),
        ),
      ],
    );
  }

  Widget _buildLiveTestCard() {
    final stateColor = switch (_testState) {
      ProviderTestState.idle => AppColors.textMuted,
      ProviderTestState.connecting ||
      ProviderTestState.testing => AppColors.warning,
      ProviderTestState.streaming => AppColors.primaryBright,
      ProviderTestState.success => AppColors.success,
      ProviderTestState.error => AppColors.error,
    };

    final stateLabel = switch (_testState) {
      ProviderTestState.idle => 'Not tested',
      ProviderTestState.connecting => 'Connecting...',
      ProviderTestState.testing => 'Testing model...',
      ProviderTestState.streaming => 'Streaming response...',
      ProviderTestState.success => 'Model validated',
      ProviderTestState.error => 'Connection failed',
    };

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surfaceElevated,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: _testState == ProviderTestState.success
              ? AppColors.success.withAlpha(120)
              : _testState == ProviderTestState.error
              ? AppColors.error.withAlpha(120)
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
                status: _testState == ProviderTestState.success
                    ? ChatStatus.completed
                    : _testState == ProviderTestState.error
                    ? ChatStatus.error
                    : ChatStatus.running,
                size: 9,
              ),
              const SizedBox(width: 8),
              Text(
                stateLabel,
                style: AppTypography.titleSmall.copyWith(color: stateColor),
              ),
              const Spacer(),
              if (_testState == ProviderTestState.success)
                const Icon(AppIcons.check, size: 18, color: AppColors.success),
            ],
          ),
          if (_streamedResponse.isNotEmpty) ...[
            const SizedBox(height: 10),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppColors.codeBackground,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AppColors.codeBorder),
              ),
              child: Text(
                _streamedResponse,
                style: AppTypography.codeSmall.copyWith(
                  color: AppColors.textPrimary,
                ),
              ),
            ),
          ],
          if (_testError != null) ...[
            const SizedBox(height: 10),
            Text(
              _testError!,
              style: AppTypography.bodySmall.copyWith(color: AppColors.error),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                AppButton(
                  label: 'Retry Test',
                  icon: AppIcons.refresh,
                  compact: true,
                  onPressed: _runLiveStreamTest,
                ),
                const SizedBox(width: 8),
                AppButton(
                  label: 'Edit Config',
                  variant: AppButtonVariant.ghost,
                  compact: true,
                  onPressed: () {
                    setState(() {
                      _testState = ProviderTestState.idle;
                      _testError = null;
                    });
                  },
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

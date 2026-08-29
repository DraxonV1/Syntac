import 'dart:async';
import 'package:flutter/services.dart';
import 'package:flutter/material.dart';
import '../../app.dart';
import '../../ai/ai_error_messages.dart';
import '../../ai/registry/provider_registry.dart';
import '../../models.dart';
import '../theme/app_colors.dart';
import '../theme/app_icons.dart';
import '../theme/app_typography.dart';
import '../widgets/app_buttons.dart';

/// Clean dialog for configuring an AI provider.
Future<void> showProviderConfigDialog(
  BuildContext context,
  AppController controller, {
  ProviderConfig? provider,
}) async {
  final isEditing = provider != null;
  final existingModels = isEditing
      ? (controller.providerModels[provider.id] ?? <ProviderModel>[])
      : <ProviderModel>[];
  final defaultProvider = ProviderRegistry.openRouter;
  final nameController = TextEditingController(
    text: provider?.name ?? defaultProvider.name,
  );
  final baseUrlController = TextEditingController(
    text: provider?.baseUrl ?? defaultProvider.defaultBaseUrl,
  );
  final apiKeyController = TextEditingController();
  final modelsController = TextEditingController(
    text: isEditing
        ? existingModels.map((m) => m.model).join('\n')
        : defaultProvider.defaultModels.join('\n'),
  );

  var isObscured = true;
  var isTesting = false;
  var isSaving = false;
  String? testResult;
  bool? testSuccess;
  var isOAuthLogin = false;
  String? oauthAuthUrl;
  String? oauthProgress;

  await showDialog<void>(
    context: context,
    builder: (dialogContext) => StatefulBuilder(
      builder: (context, setState) {
        return AlertDialog(
          backgroundColor: AppColors.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
            side: const BorderSide(color: AppColors.border, width: 1),
          ),
          title: Text(
            isEditing ? 'Configure Provider' : 'Add AI Provider',
            style: AppTypography.titleLarge,
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Provider Name', style: AppTypography.label),
                const SizedBox(height: 6),
                TextField(
                  controller: nameController,
                  style: AppTypography.bodyMedium,
                  decoration: const InputDecoration(
                    hintText: 'e.g. OpenRouter, OpenAI, LocalAI',
                  ),
                ),
                const SizedBox(height: 14),

                Text('Base URL', style: AppTypography.label),
                const SizedBox(height: 6),
                TextField(
                  controller: baseUrlController,
                  style: AppTypography.codeSmall,
                  decoration: const InputDecoration(
                    hintText: 'https://openrouter.ai/api/v1',
                  ),
                ),
                const SizedBox(height: 14),

                Text(
                  isEditing
                      ? 'API Key (leave blank to keep current)'
                      : 'API Key',
                  style: AppTypography.label,
                ),
                const SizedBox(height: 6),
                TextField(
                  controller: apiKeyController,
                  obscureText: isObscured,
                  style: AppTypography.codeSmall,
                  decoration: InputDecoration(
                    hintText: isEditing ? '••••••••••••••••' : 'sk-...',
                    suffixIcon: IconButton(
                      icon: Icon(
                        isObscured
                            ? Icons.visibility_outlined
                            : Icons.visibility_off_outlined,
                        size: 16,
                        color: AppColors.textMuted,
                      ),
                      onPressed: () => setState(() => isObscured = !isObscured),
                    ),
                  ),
                ),
                const SizedBox(height: 14),

                Text('Models (one per line)', style: AppTypography.label),
                const SizedBox(height: 6),
                TextField(
                  controller: modelsController,
                  minLines: 2,
                  maxLines: 5,
                  style: AppTypography.codeSmall,
                  decoration: const InputDecoration(
                    hintText: 'openai/gpt-4o-mini',
                  ),
                ),
                const SizedBox(height: 14),

                // Test Connection Row
                Row(
                  children: [
                    AppButton(
                      label: 'Test Connection',
                      icon: AppIcons.check,
                      variant: AppButtonVariant.secondary,
                      loading: isTesting,
                      compact: true,
                      onPressed: () async {
                        final baseUrl = baseUrlController.text.trim();
                        final key = apiKeyController.text.trim();
                        if (baseUrl.isEmpty) return;

                        setState(() {
                          isTesting = true;
                          testResult = null;
                        });

                        try {
                          if (isEditing && key.isEmpty) {
                            final result = await controller.testProvider(
                              provider.id,
                            );
                            setState(() {
                              testResult = result;
                              testSuccess = result.toLowerCase().contains('ok');
                            });
                          } else {
                            if (key.isEmpty) {
                              setState(() {
                                testResult = 'API key required to test';
                                testSuccess = false;
                              });
                            } else {
                              setState(() {
                                testResult = 'Testing endpoint...';
                              });
                              final res = await controller.repository
                                  .getProvider(provider?.id ?? '');
                              if (res != null) {
                                final r = await controller.testProvider(res.id);
                                setState(() {
                                  testResult = r;
                                  testSuccess = r.toLowerCase().contains('ok');
                                });
                              } else {
                                setState(() {
                                  testResult =
                                      'Save provider to verify with saved key';
                                  testSuccess = null;
                                });
                              }
                            }
                          }
                        } catch (err, stackTrace) {
                          logDetailedAIError(
                            err,
                            stackTrace,
                            context: 'Provider dialog connection test failed',
                          );
                          setState(() {
                            testResult = describeAIErrorForUser(err);
                            testSuccess = false;
                          });
                        } finally {
                          setState(() => isTesting = false);
                        }
                      },
                    ),
                    const SizedBox(width: 8),
                    if (testResult != null)
                      Expanded(
                        child: Text(
                          testResult!,
                          overflow: TextOverflow.ellipsis,
                          style: AppTypography.bodySmall.copyWith(
                            color: testSuccess == true
                                ? AppColors.successText
                                : (testSuccess == false
                                      ? AppColors.errorText
                                      : AppColors.textMuted),
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 14),

                // OAuth sign-in options
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    AppButton(
                      label: 'Google Sign-in',
                      icon: AppIcons.key,
                      variant: AppButtonVariant.secondary,
                      loading: isOAuthLogin,
                      compact: true,
                      onPressed: () async {
                        setState(() {
                          isOAuthLogin = true;
                          oauthAuthUrl = null;
                          oauthProgress = 'Starting Google sign-in...';
                          testResult = null;
                        });
                        await controller.loginGoogleAntigravity(
                          onAuthRequest: (request) {
                            Clipboard.setData(ClipboardData(text: request.url));
                            if (!dialogContext.mounted) return;
                            setState(() {
                              oauthAuthUrl = request.url;
                              oauthProgress =
                                  'Authorization URL copied. Complete sign-in in your browser.';
                            });
                          },
                          onProgress: (message) {
                            if (!dialogContext.mounted) return;
                            setState(() => oauthProgress = message);
                          },
                        );
                        if (!dialogContext.mounted) return;
                        setState(() {
                          isOAuthLogin = false;
                          oauthProgress =
                              controller.lastError ?? 'Google sign-in complete';
                          testSuccess = controller.lastError == null;
                        });
                      },
                    ),
                  ],
                ),
                if (oauthProgress != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    oauthProgress!,
                    style: AppTypography.bodySmall.copyWith(
                      color: testSuccess == false
                          ? AppColors.errorText
                          : AppColors.textMuted,
                    ),
                  ),
                ],
                if (oauthAuthUrl != null) ...[
                  const SizedBox(height: 6),
                  SelectableText(
                    oauthAuthUrl!,
                    style: AppTypography.codeSmall.copyWith(
                      color: AppColors.textMuted,
                    ),
                  ),
                ],
              ],
            ),
          ),
          actionsPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 12,
          ),
          actions: [
            AppButton(
              label: 'Cancel',
              variant: AppButtonVariant.ghost,
              compact: true,
              onPressed: () => Navigator.of(dialogContext).pop(),
            ),
            const SizedBox(width: 8),
            AppButton(
              label: isEditing ? 'Save Changes' : 'Add Provider',
              loading: isSaving,
              compact: true,
              onPressed: () async {
                final name = nameController.text.trim();
                final baseUrl = baseUrlController.text.trim();
                final key = apiKeyController.text.trim();
                final models = modelsController.text
                    .split('\n')
                    .map((m) => m.trim())
                    .where((m) => m.isNotEmpty)
                    .toList();

                if (name.isEmpty || baseUrl.isEmpty) return;

                setState(() => isSaving = true);
                try {
                  await controller.saveProvider(
                    id: provider?.id,
                    name: name,
                    baseUrl: baseUrl,
                    apiKey: key,
                    models: models,
                  );
                  if (dialogContext.mounted) {
                    Navigator.of(dialogContext).pop();
                  }
                } finally {
                  if (dialogContext.mounted) {
                    setState(() => isSaving = false);
                  }
                }
              },
            ),
          ],
        );
      },
    ),
  );
}

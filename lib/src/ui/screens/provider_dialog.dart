import 'dart:async';
import 'package:flutter/services.dart';
import 'package:flutter/material.dart';
import '../../app.dart';
import '../../ai/ai_error_messages.dart';
import '../../ai/registry/provider_registry.dart';
import '../../models.dart';
import '../onboarding/steps/provider_step.dart';
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
  if (provider == null) {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      builder: (sheetContext) => SafeArea(
        child: FractionallySizedBox(
          heightFactor: 0.92,
          child: ProviderStep(
            controller: controller,
            settingsMode: true,
            continueLabel: 'Done',
            onNext: () => Navigator.of(sheetContext).pop(),
          ),
        ),
      ),
    );
    return;
  }
  final definition = const ProviderRegistry().byId(provider.providerKey);
  final isBuiltin = ProviderRegistry.isBuiltin(provider.providerKey);
  final isOAuth = definition.authType != ProviderAuthType.apiKey;
  final existingModels =
      controller.providerModels[provider.id] ?? <ProviderModel>[];
  final nameController = TextEditingController(text: provider.name);
  final baseUrlController = TextEditingController(text: provider.baseUrl);
  final apiKeyController = TextEditingController();
  final modelsController = TextEditingController(
    text: existingModels.map((m) => m.model).join('\n'),
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
          title: Text('Configure Provider', style: AppTypography.titleLarge),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Provider Name', style: AppTypography.label),
                const SizedBox(height: 6),
                TextField(
                  controller: nameController,
                  readOnly: isBuiltin,
                  style: AppTypography.bodyMedium,
                  decoration: const InputDecoration(hintText: 'Provider name'),
                ),
                const SizedBox(height: 14),

                Text('Base URL', style: AppTypography.label),
                const SizedBox(height: 6),
                TextField(
                  controller: baseUrlController,
                  readOnly: isBuiltin,
                  style: AppTypography.codeSmall,
                  decoration: const InputDecoration(
                    hintText: 'https://provider.example/v1',
                  ),
                ),

                if (!isOAuth) ...[
                  Text(
                    'API Key (leave blank to keep current)',
                    style: AppTypography.label,
                  ),
                  const SizedBox(height: 6),
                  TextField(
                    controller: apiKeyController,
                    obscureText: isObscured,
                    style: AppTypography.codeSmall,
                    decoration: InputDecoration(
                      hintText: '••••••••••••••••',
                      suffixIcon: IconButton(
                        icon: Icon(
                          isObscured
                              ? Icons.visibility_outlined
                              : Icons.visibility_off_outlined,
                          size: 16,
                          color: AppColors.textMuted,
                        ),
                        onPressed: () =>
                            setState(() => isObscured = !isObscured),
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                ],

                if (isBuiltin) ...[
                  Text(
                    'Models discovered from provider',
                    style: AppTypography.label,
                  ),
                  const SizedBox(height: 6),
                  if (existingModels.isEmpty)
                    Text(
                      'No live models yet. Refresh after sign-in.',
                      style: AppTypography.bodySmall,
                    )
                  else
                    for (final model in existingModels)
                      ListTile(
                        dense: true,
                        leading: AppIcons.providerLogo(definition.id, size: 18),
                        title: Text(
                          model.model,
                          style: AppTypography.codeSmall,
                        ),
                      ),
                  const SizedBox(height: 14),
                ] else ...[
                  Text('Models (one per line)', style: AppTypography.label),
                  const SizedBox(height: 6),
                  TextField(
                    controller: modelsController,
                    minLines: 2,
                    maxLines: 5,
                    style: AppTypography.codeSmall,
                    decoration: const InputDecoration(
                      hintText: 'Model ID from provider /models',
                    ),
                  ),
                  const SizedBox(height: 14),
                ],

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
                          if (key.isEmpty) {
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
                                  .getProvider(provider.id);
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
                    AppButton(
                      label: 'ChatGPT Sign-in',
                      icon: AppIcons.key,
                      variant: AppButtonVariant.secondary,
                      loading: isOAuthLogin,
                      compact: true,
                      onPressed: () async {
                        setState(() {
                          isOAuthLogin = true;
                          oauthAuthUrl = null;
                          oauthProgress = 'Starting ChatGPT sign-in...';
                          testResult = null;
                        });
                        await controller.loginOpenAICodex(
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
                              controller.lastError ??
                              'ChatGPT sign-in complete';
                          testSuccess = controller.lastError == null;
                        });
                      },
                    ),
                    AppButton(
                      label: 'Grok OAuth',
                      icon: AppIcons.key,
                      variant: AppButtonVariant.secondary,
                      loading: isOAuthLogin,
                      compact: true,
                      onPressed: () async {
                        setState(() {
                          isOAuthLogin = true;
                          oauthAuthUrl = null;
                          oauthProgress = 'Starting Grok sign-in...';
                          testResult = null;
                        });
                        await controller.loginXAIOAuth(
                          onAuthRequest: (request) {
                            Clipboard.setData(ClipboardData(text: request.url));
                            if (!dialogContext.mounted) return;
                            setState(() {
                              oauthAuthUrl = request.launchUrl ?? request.url;
                              oauthProgress =
                                  'Authorization URL copied. Enter device code in browser.';
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
                              controller.lastError ?? 'Grok sign-in complete';
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
            if (!isBuiltin)
              AppButton(
                label: 'Save Changes',
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
                      id: provider.id,
                      name: name,
                      baseUrl: baseUrl,
                      apiKey: key,
                      providerKey: definition.id,
                      authType: definition.authType.name,
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

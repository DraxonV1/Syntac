import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'agent/agent_loop.dart';
import 'ai/auth/credential_store.dart';
import 'ai/ai_provider.dart';
import 'ai/ai_error_messages.dart';
import 'ai/google_cloud_code_assist_provider.dart';
import 'ai/oauth/google_antigravity_oauth.dart';
import 'ai/oauth/openai_codex_oauth.dart';
import 'ai/oauth/xai_oauth.dart';
import 'ai/openai_codex_provider.dart';
import 'ai/openai_provider.dart';
import 'ai/registry/provider_registry.dart';
import 'ai/models_dev_catalog.dart';
import 'core/app_identity.dart';
import 'core/update_service.dart';
import 'models.dart';
import 'tools/agent_tools.dart';
import 'runtime/shell_executor.dart';
import 'security/secret_store.dart';
import 'storage/app_repository.dart';
import 'storage/local_database.dart';
import 'ui/screens/home_screen.dart';
import 'ui/theme/app_theme.dart';

class SyntacApp extends StatefulWidget {
  const SyntacApp({super.key});

  @override
  State<SyntacApp> createState() => _SyntacAppState();
}

class _SyntacAppState extends State<SyntacApp> {
  late final AppController controller;

  @override
  void initState() {
    super.initState();
    controller = AppController();
    unawaited(controller.initialize());
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) => MaterialApp(
        title: AppIdentity.instance.appDisplayName,
        debugShowCheckedModeBanner: false,
        theme: AppTheme.darkTheme,
        darkTheme: AppTheme.darkTheme,
        themeMode: ThemeMode.dark,
        home: HomeScreen(controller: controller),
      ),
    );
  }
}

class AppController extends ChangeNotifier {
  AppController({
    Future<LocalDatabase> Function()? openDatabase,
    SecretStore? secretStore,
    Directory? chatStorageDirectory,
    ShellExecutor? initialRuntime,
    UpdateService? updateService,
  }) : _openDatabase = openDatabase ?? LocalDatabase.open,
       _secretStore = secretStore ?? FlutterSecureSecretStore(),
       _chatStorageDirectory = chatStorageDirectory,
       _updateService = updateService ?? UpdateService(),
       runtime = initialRuntime ?? TermuxRuntime();

  final Future<LocalDatabase> Function() _openDatabase;
  final SecretStore _secretStore;
  final Directory? _chatStorageDirectory;
  final UpdateService _updateService;
  AppRepository? _repository;
  AgentLoop? _agentLoop;
  ModelsDevCatalog modelsDevCatalog = ModelsDevCatalog.empty();
  ShellRuntimeSettings shellRuntimeSettings = const ShellRuntimeSettings();
  ShellExecutor runtime;
  bool loading = true;
  String? lastError;
  List<ProjectSummary> projects = <ProjectSummary>[];
  List<Chat> chats = <Chat>[];
  List<ChatMessage> messages = <ChatMessage>[];
  List<ToolExecution> toolExecutions = <ToolExecution>[];
  List<ProviderConfig> providers = <ProviderConfig>[];
  Map<String, List<ProviderModel>> providerModels =
      <String, List<ProviderModel>>{};
  RuntimeStatus runtimeStatus = const RuntimeStatus(
    state: RuntimeState.unavailable,
    message: 'Not checked yet',
  );
  Project? selectedProject;
  Chat? selectedChat;
  AgentLimits limits = const AgentLimits();
  bool diagnosticsRunning = false;
  String? diagnosticsText;
  bool updateChecking = false;
  UpdateManifest? availableUpdate;
  String? updateMessage;

  AppRepository get repository => _repository!;
  AgentLoop get agentLoop => _agentLoop!;

  Future<void> initialize() async {
    loading = true;
    lastError = null;
    try {
      final db = await _openDatabase();
      _repository = AppRepository(
        localDatabase: db,
        secretStore: _secretStore,
        chatStorageDirectory: _chatStorageDirectory,
      );
      modelsDevCatalog = await ModelsDevCatalog.load();
      _agentLoop = AgentLoop(
        repository: repository,
        modelsDevCatalog: modelsDevCatalog,
        shellExecutorFactory: _runtimeExecutorForProject,
        onMessagesChanged: _refreshChatMessages,
      );
      await repository.reconcileStaleRunningJobs();
      await refreshAll();
      if (Platform.isAndroid) unawaited(checkForUpdates());
    } catch (error, stackTrace) {
      logDetailedAIError(
        error,
        stackTrace,
        context: 'App initialization failed',
      );
      lastError = 'App failed to start. Check development logs for details.';
    } finally {
      loading = false;
      notifyListeners();
    }
  }

  Future<void> retryInitialize() => initialize();

  void reportStartupError(
    Object error,
    StackTrace stackTrace, {
    required String context,
    String message = 'App startup check failed. Try again.',
  }) {
    logDetailedAIError(error, stackTrace, context: context);
    lastError = message;
    loading = false;
    notifyListeners();
  }

  void refreshVisibleState() => notifyListeners();
  Future<void> _refreshChatMessages(String chatId) async {
    if (selectedChat?.id != chatId) return;
    selectedChat = await repository.getChat(chatId);
    messages = await repository.listMessages(chatId);
    toolExecutions = await repository.listToolExecutions(chatId);
    notifyListeners();
  }

  Future<void> refreshAll() async {
    projects = await repository.listProjectSummaries();
    providers = (await repository.listProviders())
        .where(
          (provider) => ProviderRegistry.isVisibleForBeta(provider.providerKey),
        )
        .toList(growable: false);
    providerModels = <String, List<ProviderModel>>{};
    for (final provider in providers) {
      providerModels[provider.id] = await repository.listProviderModels(
        provider.id,
      );
    }
    limits = await repository.readAgentLimits();
    shellRuntimeSettings = await repository.readShellRuntimeSettings();
    runtime = _executorForRuntime(shellRuntimeSettings.selected);
    runtimeStatus = RuntimeStatus(
      state: RuntimeState.notInstalled,
      message: '${shellRuntimeSettings.selected.label} status not checked yet.',
    );
    unawaited(refreshRuntimeStatus());
    if (selectedProject != null) {
      selectedProject = await repository.getProject(selectedProject!.id);
      if (selectedProject != null) {
        chats = await repository.listChats(selectedProject!.id);
      }
    }
    if (selectedChat != null) {
      selectedChat = await repository.getChat(selectedChat!.id);
      if (selectedChat != null) {
        messages = await repository.listMessages(selectedChat!.id);
        toolExecutions = await repository.listToolExecutions(selectedChat!.id);
      }
    }
    notifyListeners();
  }

  Future<void> checkForUpdates() async {
    updateChecking = true;
    updateMessage = null;
    notifyListeners();
    final update = await _updateService.check(
      channel: defaultUpdateChannel,
      currentVersionCode: AppIdentity.instance.versionCode,
    );
    availableUpdate = update;
    updateChecking = false;
    notifyListeners();
  }

  Future<void> openAvailableUpdate() async {
    final update = availableUpdate;
    if (update == null) return;
    await openExternalUrl(update.downloadUrl);
  }

  Future<void> openExternalUrl(String url) async {
    if (!Platform.isAndroid) return;
    await const MethodChannel(
      'syntac/runtime',
    ).invokeMethod<void>('openUrl', <String, Object?>{'url': url});
  }

  Future<void> refreshRuntimeStatus() async {
    try {
      runtimeStatus = await runtime.status();
    } catch (error) {
      runtimeStatus = RuntimeStatus(
        state: RuntimeState.unavailable,
        message: error.toString(),
      );
    }
    notifyListeners();
  }

  Future<void> createProject(String name, String folderPath) async {
    lastError = null;
    try {
      final cleanPath = _canonicalProjectPath(folderPath);
      await Directory(cleanPath).create(recursive: true);
      final project = await repository.createProject(
        name: name,
        folderPath: cleanPath,
      );
      selectedProject = project;
      chats = await repository.listChats(project.id);
      await refreshAll();
    } catch (error, stackTrace) {
      logDetailedAIError(error, stackTrace, context: 'Project creation failed');
      lastError =
          'Could not create the project folder. Use a real shared-storage path such as ${AppIdentity.instance.defaultSharedStoragePath}/<project>.';
      notifyListeners();
    }
  }

  Future<void> removeSelectedProject() async {
    final project = selectedProject;
    if (project == null) return;
    await repository.removeProjectFromApp(project.id);
    selectedProject = null;
    selectedChat = null;
    chats = <Chat>[];
    messages = <ChatMessage>[];
    await refreshAll();
  }

  Future<void> openProject(Project project) async {
    selectedProject = project;
    selectedChat = null;
    messages = <ChatMessage>[];
    toolExecutions = <ToolExecution>[];
    chats = await repository.listChats(project.id);
    notifyListeners();
  }

  Future<void> openChat(Chat chat) async {
    selectedChat = chat;
    messages = await repository.listMessages(chat.id);
    toolExecutions = await repository.listToolExecutions(chat.id);
    notifyListeners();
  }

  Future<void> newChat() async {
    final project = selectedProject;
    if (project == null) return;
    final provider = _defaultProvider();
    final model = _firstModelForProvider(provider);
    final chat = await repository.createChat(
      projectId: project.id,
      title: 'New chat',
      providerId: provider?.id,
      modelId: model?.id,
    );
    await openChat(chat);
    await refreshAll();
  }

  Future<void> deleteChat(String chatId) async {
    await repository.deleteChat(chatId);
    if (selectedChat?.id == chatId) {
      selectedChat = null;
      messages = <ChatMessage>[];
      toolExecutions = <ToolExecution>[];
    }
    await refreshAll();
  }

  Future<void> renameChat(String chatId, String newTitle) async {
    final chat = await repository.getChat(chatId);
    if (chat != null) {
      await repository.updateChat(chat.copyWith(title: newTitle.trim()));
      await refreshAll();
    }
  }

  Future<void> sendMessage(String text, List<Attachment> attachments) async {
    final project = selectedProject;
    var chat = selectedChat;
    if (project == null) return;
    if (chat == null) {
      final provider = _defaultProvider();
      final model = _firstModelForProvider(provider);
      chat = await repository.createChat(
        projectId: project.id,
        title: titleFromPrompt(text),
        providerId: provider?.id,
        modelId: model?.id,
      );
      selectedChat = chat;
    } else if (chat.providerId == null || chat.modelId == null) {
      final provider = chat.providerId == null
          ? _defaultProvider()
          : providers
                .where((provider) => provider.id == chat!.providerId)
                .firstOrNull;
      final model = chat.modelId == null
          ? _firstModelForProvider(provider)
          : null;
      if (provider != null || model != null) {
        chat = chat.copyWith(
          providerId: chat.providerId ?? provider?.id,
          modelId: chat.modelId ?? model?.id,
        );
        await repository.updateChat(chat);
        selectedChat = chat;
      }
    }
    lastError = null;
    final prompt = await _promptWithTextAttachments(text, attachments);
    unawaited(
      agentLoop
          .send(
            project: project,
            chat: chat,
            userText: prompt,
            attachments: attachments,
          )
          .catchError((Object error, StackTrace stackTrace) {
            logDetailedAIError(error, stackTrace, context: 'Agent run failed');
            var providerName = 'provider';
            final providerId = selectedChat?.providerId;
            if (providerId != null) {
              for (final provider in providers) {
                if (provider.id == providerId) {
                  providerName = provider.name;
                  break;
                }
              }
            }
            lastError = describeAIErrorForUser(
              error,
              providerName: providerName,
            );
          })
          .whenComplete(refreshAll),
    );
    await refreshAll();
  }

  ProviderConfig? _defaultProvider() =>
      providers.isEmpty ? null : providers.first;

  ProviderModel? _firstModelForProvider(ProviderConfig? provider) {
    if (provider == null) return null;
    final models = providerModels[provider.id] ?? <ProviderModel>[];
    return models.isEmpty ? null : models.first;
  }

  static List<String> _mergeModels(Iterable<Iterable<String>> groups) {
    final seen = <String>{};
    final merged = <String>[];
    for (final group in groups) {
      for (final model in group) {
        final clean = model.trim();
        if (clean.isEmpty || !seen.add(clean)) continue;
        merged.add(clean);
      }
    }
    return merged;
  }

  Future<void> stopCurrentChat() async {
    final chat = selectedChat;
    if (chat == null) return;
    await agentLoop.stop(chat.id);
    await refreshAll();
  }

  Future<void> saveProvider({
    String? id,
    required String name,
    required String baseUrl,
    required String apiKey,
    String providerKey = 'custom-openai-compatible',
    String authType = 'apiKey',
    required List<String> models,
  }) async {
    lastError = null;
    try {
      await repository.saveProvider(
        id: id,
        name: name,
        baseUrl: baseUrl,
        apiKey: apiKey,
        providerKey: providerKey,
        authType: authType,
        models: models,
      );
      await refreshAll();
    } catch (error, stackTrace) {
      logDetailedAIError(error, stackTrace, context: 'Provider save failed');
      lastError =
          'Failed to save provider settings. Check values and try again.';
      notifyListeners();
    }
  }

  Future<void> deleteProvider(String id) async {
    await repository.deleteProvider(id);
    await refreshAll();
  }

  Future<String> testProvider(String providerId) async {
    final provider = await repository.getProvider(providerId);
    if (provider == null) return 'Provider missing';
    try {
      if (provider.authType == ProviderAuthType.googleAntigravityOAuth.name) {
        var credential = await repository.readOAuthCredential(providerId);
        if (credential == null) return 'Google sign-in required';
        if (credential.expiresWithin(const Duration(minutes: 1))) {
          credential = await GoogleAntigravityOAuthFlow().refreshToken(
            credential,
          );
          await repository.saveOAuthCredential(providerId, credential);
        }
        return 'OAuth ok${credential.email == null ? '' : ' for ${credential.email}'}';
      }
      if (provider.authType == ProviderAuthType.openAICodexOAuth.name) {
        var credential = await repository.readOAuthCredential(providerId);
        if (credential == null) return 'ChatGPT sign-in required';
        if (credential.expiresWithin(const Duration(minutes: 1))) {
          credential = await OpenAICodexOAuthFlow().refreshToken(credential);
          await repository.saveOAuthCredential(providerId, credential);
        }
        return 'OAuth ok${credential.email == null ? '' : ' for ${credential.email}'}';
      }
      if (provider.authType == ProviderAuthType.xaiOAuth.name) {
        var credential = await repository.readOAuthCredential(providerId);
        if (credential == null) return 'xAI sign-in required';
        if (credential.expiresWithin(const Duration(minutes: 1))) {
          credential = await XAIOAuthFlow().refreshToken(credential);
          await repository.saveOAuthCredential(providerId, credential);
        }
        return 'OAuth ok${credential.email == null ? '' : ' for ${credential.email}'}';
      }
      final apiKey = await repository.readProviderApiKey(providerId);
      if (apiKey == null || apiKey.isEmpty) {
        return 'Provider or API key missing';
      }
      if (provider.providerKey == ProviderRegistry.grok.id) {
        await OpenAIResponsesProvider(
          baseUrl: provider.baseUrl,
          providerName: provider.name,
        ).discoverModels(apiKey: apiKey);
      } else {
        await OpenAICompatibleProvider(
          baseUrl: provider.baseUrl,
          providerName: provider.name,
        ).testConnection(apiKey: apiKey);
      }
      return 'Connection ok';
    } catch (error, stackTrace) {
      logDetailedAIError(
        error,
        stackTrace,
        context: 'Provider connection test failed',
      );
      return describeAIErrorForUser(error, providerName: provider.name);
    }
  }

  Future<String> refreshProviderModels(String providerId) async {
    final provider = await repository.getProvider(providerId);
    if (provider == null) return 'Provider missing';
    try {
      List<String> discovered = [];
      var authoritativeDiscovery = false;
      if (provider.providerKey == ProviderRegistry.googleAntigravity.id) {
        var credential = await repository.readOAuthCredential(providerId);
        if (credential == null) return 'Google sign-in required';
        final flow = GoogleAntigravityOAuthFlow();
        if (credential.expiresWithin(const Duration(minutes: 1))) {
          credential = await flow.refreshToken(credential);
          await repository.saveOAuthCredential(providerId, credential);
        }
        discovered = await flow.discoverModels(credential.accessToken);
        authoritativeDiscovery = discovered.isNotEmpty;
      } else if (provider.providerKey == ProviderRegistry.openAICodex.id) {
        var credential = await repository.readOAuthCredential(providerId);
        if (credential == null) return 'ChatGPT sign-in required';
        if (credential.expiresWithin(const Duration(minutes: 1))) {
          credential = await OpenAICodexOAuthFlow().refreshToken(credential);
          await repository.saveOAuthCredential(providerId, credential);
        }
        final result = await OpenAICodexProvider(
          baseUrl: provider.baseUrl,
          providerName: provider.name,
        ).discoverCodexModels(credential: credential);
        if (result != null) {
          discovered = result;
          authoritativeDiscovery = true;
        }
      } else if (provider.providerKey == ProviderRegistry.grokOAuth.id) {
        var credential = await repository.readOAuthCredential(providerId);
        if (credential == null) return 'xAI sign-in required';
        if (credential.expiresWithin(const Duration(minutes: 1))) {
          credential = await XAIOAuthFlow().refreshToken(credential);
          await repository.saveOAuthCredential(providerId, credential);
        }
        discovered = await OpenAIResponsesProvider(
          baseUrl: provider.baseUrl,
          providerName: provider.name,
        ).discoverModels(apiKey: credential.toStructuredApiKey());
        discovered = discovered
            .where(
              (model) =>
                  !model.startsWith('grok-imagine-') &&
                  !model.startsWith('grok-stt-') &&
                  !model.startsWith('grok-voice-'),
            )
            .toList(growable: false);
        authoritativeDiscovery = discovered.isNotEmpty;
      } else if (provider.providerKey == ProviderRegistry.grok.id) {
        final apiKey = await repository.readProviderApiKey(providerId) ?? '';
        discovered = await OpenAIResponsesProvider(
          baseUrl: provider.baseUrl,
          providerName: provider.name,
        ).discoverModels(apiKey: apiKey);
        authoritativeDiscovery = discovered.isNotEmpty;
      } else {
        final apiKey = await repository.readProviderApiKey(providerId) ?? '';
        final openAIProvider = OpenAICompatibleProvider(
          baseUrl: provider.baseUrl,
          providerName: provider.name,
        );
        discovered = await openAIProvider.discoverModels(apiKey: apiKey);
        authoritativeDiscovery = discovered.isNotEmpty;
      }

      final existing = providerModels[providerId] ?? const <ProviderModel>[];
      final definition = const ProviderRegistry().byId(provider.providerKey);
      final merged = _mergeModels([
        discovered,
        if (!authoritativeDiscovery) existing.map((model) => model.model),
        if (!authoritativeDiscovery)
          modelsDevCatalog.modelIdsForProvider(definition.modelsDevProvider),
      ]);
      await repository.saveProvider(
        id: provider.id,
        name: provider.name,
        baseUrl: provider.baseUrl,
        providerKey: provider.providerKey,
        authType: provider.authType,
        apiKey: '',
        models: merged,
      );
      await refreshAll();
      return authoritativeDiscovery
          ? 'Discovered ${discovered.length} live models from API'
          : 'Kept existing models (${merged.length} available)';
    } catch (error, stackTrace) {
      logDetailedAIError(
        error,
        stackTrace,
        context: 'Provider model refresh failed',
      );
      return describeAIErrorForUser(error, providerName: provider.name);
    }
  }

  Future<String> refreshGoogleAntigravityModels(String providerId) =>
      refreshProviderModels(providerId);

  Future<void> loginGoogleAntigravity({
    required void Function(OAuthAuthRequest request) onAuthRequest,
    void Function(String message)? onProgress,
  }) async {
    lastError = null;
    try {
      final definition = ProviderRegistry.googleAntigravity;
      final flow = GoogleAntigravityOAuthFlow();
      final credential = await flow.login(
        onAuthRequest: onAuthRequest,
        onProgress: onProgress,
      );
      final existing = providers
          .where((provider) => provider.providerKey == definition.id)
          .firstOrNull;
      final discoveredModels = await flow.discoverModels(
        credential.accessToken,
      );
      final existingModels = existing == null
          ? const <String>[]
          : (providerModels[existing.id] ?? const <ProviderModel>[]).map(
              (model) => model.model,
            );
      final provider = await repository.saveProvider(
        id: existing?.id,
        name: definition.name,
        baseUrl: definition.defaultBaseUrl,
        providerKey: definition.id,
        authType: definition.authType.name,
        apiKey: '',
        models: _mergeModels([
          discoveredModels,
          if (discoveredModels.isEmpty) existingModels,
          if (discoveredModels.isEmpty)
            modelsDevCatalog.modelIdsForProvider(definition.modelsDevProvider),
        ]),
      );
      await repository.saveOAuthCredential(provider.id, credential);
      await refreshAll();
    } catch (error, stackTrace) {
      logDetailedAIError(
        error,
        stackTrace,
        context: 'Google Antigravity login failed',
      );
      lastError = describeAIErrorForUser(
        error,
        providerName: 'Google Antigravity',
      );
      notifyListeners();
    }
  }

  Future<void> loginOpenAICodex({
    required void Function(OAuthAuthRequest request) onAuthRequest,
    void Function(String message)? onProgress,
  }) async {
    lastError = null;
    try {
      final definition = ProviderRegistry.openAICodex;
      final credential = await OpenAICodexOAuthFlow().login(
        onAuthRequest: onAuthRequest,
        onProgress: onProgress,
      );
      final existing = providers
          .where((provider) => provider.providerKey == definition.id)
          .firstOrNull;
      final discovered = await OpenAICodexProvider(
        baseUrl: definition.defaultBaseUrl,
        providerName: definition.name,
      ).discoverCodexModels(credential: credential);
      final existingModels = existing == null
          ? const <String>[]
          : (providerModels[existing.id] ?? const <ProviderModel>[]).map(
              (model) => model.model,
            );
      final provider = await repository.saveProvider(
        id: existing?.id,
        name: definition.name,
        baseUrl: definition.defaultBaseUrl,
        providerKey: definition.id,
        authType: definition.authType.name,
        apiKey: '',
        models: _mergeModels(switch (discovered) {
          final models? => [models],
          _ => [
            existingModels,
            modelsDevCatalog.modelIdsForProvider(definition.modelsDevProvider),
          ],
        }),
      );
      await repository.saveOAuthCredential(provider.id, credential);
      await refreshAll();
    } catch (error, stackTrace) {
      logDetailedAIError(
        error,
        stackTrace,
        context: 'ChatGPT Codex login failed',
      );
      lastError = describeAIErrorForUser(
        error,
        providerName: 'ChatGPT (Codex)',
      );
      notifyListeners();
    }
  }

  Future<void> loginXAIOAuth({
    required void Function(OAuthAuthRequest request) onAuthRequest,
    void Function(String message)? onProgress,
  }) async {
    lastError = null;
    try {
      final definition = ProviderRegistry.grokOAuth;
      final credential = await XAIOAuthFlow().login(
        onAuthRequest: onAuthRequest,
        onProgress: onProgress,
      );
      final existing = providers
          .where((provider) => provider.providerKey == definition.id)
          .firstOrNull;
      final discovered = await OpenAIResponsesProvider(
        baseUrl: definition.defaultBaseUrl,
        providerName: definition.name,
      ).discoverModels(apiKey: credential.toStructuredApiKey());
      final existingModels = existing == null
          ? const <String>[]
          : (providerModels[existing.id] ?? const <ProviderModel>[]).map(
              (model) => model.model,
            );
      final provider = await repository.saveProvider(
        id: existing?.id,
        name: definition.name,
        baseUrl: definition.defaultBaseUrl,
        providerKey: definition.id,
        authType: definition.authType.name,
        apiKey: '',
        models: _mergeModels([
          discovered,
          if (discovered.isEmpty) existingModels,
          if (discovered.isEmpty)
            modelsDevCatalog.modelIdsForProvider(definition.modelsDevProvider),
        ]),
      );
      await repository.saveOAuthCredential(provider.id, credential);
      await refreshAll();
    } catch (error, stackTrace) {
      logDetailedAIError(error, stackTrace, context: 'xAI OAuth login failed');
      lastError = describeAIErrorForUser(error, providerName: 'xAI Grok OAuth');
      notifyListeners();
    }
  }

  Stream<String> testProviderStreaming({
    required ProviderConfig provider,
    required String model,
    required String prompt,
  }) async* {
    final credential = await repository.resolveProviderCredential(provider);
    if (credential == null) {
      throw AIProviderException(
        'Authentication credentials missing for ${provider.name}',
        kind: 'unauthorized',
      );
    }

    final String apiKey = switch (credential) {
      ApiKeyProviderCredential(:final apiKey) => apiKey,
      OAuthProviderCredential(:final credential) =>
        credential.toStructuredApiKey(),
    };

    final AIProvider aiProvider = switch (provider.providerKey) {
      'google-antigravity' => GoogleCloudCodeAssistProvider(
        baseUrl: provider.baseUrl,
        providerName: provider.name,
      ),
      'openai-codex' => OpenAICodexProvider(
        baseUrl: provider.baseUrl,
        providerName: provider.name,
      ),
      'xai' || 'xai-oauth' => OpenAIResponsesProvider(
        baseUrl: provider.baseUrl,
        providerName: provider.name,
      ),
      _ => OpenAICompatibleProvider(
        baseUrl: provider.baseUrl,
        providerName: provider.name,
      ),
    };

    final request = AIChatRequest(
      model: model,
      messages: [AIChatMessage(role: 'user', content: prompt)],
      tools: const [],
    );

    final stream = aiProvider.streamChat(request, apiKey: apiKey);

    await for (final event in stream) {
      if (!event.done && event.textDelta.isNotEmpty) {
        yield event.textDelta;
      }
    }
  }

  Future<void> runRuntimeDiagnostics() async {
    final project = selectedProject;
    diagnosticsRunning = true;
    diagnosticsText = 'Running diagnostics...';
    notifyListeners();
    final lines = <String>[
      'APP',
      'platform: ${Platform.operatingSystem}',
      '',
      'RUNTIME SELECTION',
      'selectedRuntime: ${shellRuntimeSettings.selected.name}',
      'selectedRuntimeLabel: ${shellRuntimeSettings.selected.label}',
      '',
      'CURRENT PROJECT',
      'projectId: ${project?.id ?? 'none'}',
      'storedPath: ${project?.folderPath ?? 'none'}',
      'fileToolRoot: ${project?.folderPath ?? 'none'}',
      'bashWorkingDirectory: ${project?.folderPath ?? 'none'}',
    ];
    if (project == null) {
      diagnosticsText = [...lines, 'error: no project selected'].join('\n');
      diagnosticsRunning = false;
      notifyListeners();
      return;
    }
    final root = Directory(project.folderPath);
    lines.add('rootExists: ${await root.exists()}');
    try {
      await root.create(recursive: true);
      final shellExecutor = await _runtimeExecutorForProject(project);
      final tools = ProjectTools(
        projectRoot: project.folderPath,
        shellExecutor: shellExecutor,
      );
      await tools.writeFile('.syntac_diag.txt', 'one');
      final readOne = await tools.readFile('.syntac_diag.txt');
      await tools.editFile('.syntac_diag.txt', 'one', 'two');
      final readTwo = await tools.readFile('.syntac_diag.txt');
      await tools.deletePath('.syntac_diag.txt');
      final diagPath =
          '${project.folderPath}${Platform.pathSeparator}.syntac_diag.txt';
      lines.add('write/read: ${readOne['content'] == 'one'}');
      lines.add('edit/read: ${readTwo['content'] == 'two'}');
      lines.add('delete: ${!await File(diagPath).exists()}');
      lines.add('');
      lines.add('RUNTIME');
      final status = await shellExecutor.status();
      lines.add('runtime: ${shellExecutor.runtimeId}');
      lines.add('state: ${status.state.name}');
      lines.add('message: ${status.message}');
      if (status.details != null) lines.add('details: ${status.details}');
      if (shellExecutor is ShellRuntime) {
        lines.add('');
        lines.add(
          await shellExecutor.diagnostics(projectRoot: project.folderPath),
        );
      }
      final echo = await tools.runBash(
        'echo hello',
        timeout: const Duration(seconds: 10),
      );
      lines.add('echo stdout: ${echo['stdout']}');
      lines.add('echo exitCode: ${echo['exitCode']}');
      final pwd = await tools.runBash(
        'pwd',
        timeout: const Duration(seconds: 10),
      );
      lines.add('pwd stdout: ${pwd['stdout']}');
      final expectedPwd =
          shellRuntimeSettings.selected == ShellRuntimeId.archLinux
          ? '/workspace/${project.mountName}'
          : project.folderPath;
      lines.add(
        'pwd matches project: ${pwd['stdout'].toString().trim() == expectedPwd}',
      );
      final list = await tools.runBash(
        'ls -la',
        timeout: const Duration(seconds: 10),
      );
      lines.add('ls exitCode: ${list['exitCode']}');
      if (echo['success'] != true) {
        lines.add('last safe error: ${echo['stderr']}');
      }
    } catch (error, stackTrace) {
      logDetailedAIError(
        error,
        stackTrace,
        context: 'Runtime diagnostics failed',
      );
      lines.add('diagnostic error: ${error.toString()}');
    }
    diagnosticsText = lines.join('\n');
    diagnosticsRunning = false;
    notifyListeners();
  }

  String _canonicalProjectPath(String input) {
    final clean = input.trim();
    if (clean.isEmpty) {
      throw ArgumentError.value(
        input,
        'folderPath',
        'Project path is required',
      );
    }
    if (Uri.tryParse(clean)?.hasScheme ?? false) {
      throw ArgumentError.value(
        input,
        'folderPath',
        'Project path must be a real filesystem path, not a URI',
      );
    }
    if (Platform.isAndroid &&
        !clean.startsWith('/storage/emulated/0/') &&
        clean != '/storage/emulated/0') {
      throw ArgumentError.value(
        input,
        'folderPath',
        'Android project path must be in shared storage',
      );
    }
    return Directory(clean).absolute.path;
  }

  Future<void> saveLimits(AgentLimits next) async {
    await repository.saveAgentLimits(next);
    limits = next;
    notifyListeners();
  }

  Future<void> saveShellRuntime(ShellRuntimeId selected) async {
    shellRuntimeSettings = ShellRuntimeSettings(selected: selected);
    await repository.saveShellRuntimeSettings(shellRuntimeSettings);
    runtime = _executorForRuntime(selected);
    runtimeStatus = await runtime.status();
    notifyListeners();
  }

  Future<void> installLocalRuntime() async {
    final selected = ShellRuntimeId.archLinux;
    await saveShellRuntime(selected);
    final executor = runtime;
    if (executor is ShellRuntime) {
      runtimeStatus = await executor.install();
      notifyListeners();
    }
  }

  Future<void> retryLocalRuntimeTest() async {
    final selected = ShellRuntimeId.archLinux;
    await saveShellRuntime(selected);
    final executor = runtime;
    if (executor is ArchLinuxRuntime) {
      runtimeStatus = await executor.retrySelfTest();
      notifyListeners();
    }
  }

  Future<void> removeLocalRuntime() async {
    final executor = ArchLinuxRuntime();
    runtimeStatus = await executor.remove();
    notifyListeners();
  }

  Future<void> openAndroidStorageSettings() async {
    if (!Platform.isAndroid) return;
    await const MethodChannel(
      'syntac/runtime',
    ).invokeMethod<void>('openStorageSettings');
    await refreshRuntimeStatus();
  }

  Future<ShellExecutor> _runtimeExecutorForProject(Project project) async {
    if (shellRuntimeSettings.selected != ShellRuntimeId.archLinux) {
      return runtime;
    }
    return ArchLinuxRuntime(
      activeProject: project,
      availableProjects: await repository.listProjects(),
    );
  }

  Future<void> resetLocalRuntime() async {
    await removeLocalRuntime();
    await installLocalRuntime();
  }

  ShellExecutor _executorForRuntime(ShellRuntimeId id) => switch (id) {
    ShellRuntimeId.termux => TermuxRuntime(),
    ShellRuntimeId.archLinux => ArchLinuxRuntime(),
  };

  Future<String> _promptWithTextAttachments(
    String text,
    List<Attachment> attachments,
  ) async {
    final buffer = StringBuffer(text.trim());
    for (final attachment in attachments.where(
      (item) => item.kind == AttachmentKind.text,
    )) {
      try {
        final file = File(attachment.path);
        if (await file.length() > 120000) {
          buffer.write(
            '\n\nAttached text file skipped because it is too large: ${attachment.name}',
          );
          continue;
        }
        buffer.write(
          '\n\nAttached file: ${attachment.name}\n```\n${await file.readAsString()}\n```',
        );
      } catch (error) {
        buffer.write(
          '\n\nAttached file unavailable: ${attachment.name}: $error',
        );
      }
    }
    for (final attachment in attachments.where(
      (item) => item.kind != AttachmentKind.text,
    )) {
      buffer.write(
        '\n\nAttached ${attachment.kind.name} file: ${attachment.name}. Use a multimodal-capable provider when supported.',
      );
    }
    return buffer.toString();
  }
}

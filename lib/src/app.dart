// App controller: startup, projects, chats, providers, runtime, and settings.

import 'dart:async';
import 'dart:convert';
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
import 'core/cancellation.dart';
import 'core/update_service.dart';
import 'models.dart';
import 'tools/agent_tools.dart';
import 'tools/tool_context.dart';
import 'runtime/shell_executor.dart';
import 'security/secret_store.dart';
import 'storage/app_repository.dart';
import 'storage/local_database.dart';
import 'ui/screens/home_screen.dart';
import 'ui/theme/app_colors.dart';
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
    ErrorWidget.builder = (details) => const ColoredBox(
      color: Color(0xFF05070C),
      child: Center(
        child: Text(
          'Unable to render content',
          style: TextStyle(color: Colors.white70),
        ),
      ),
    );
    controller = AppController();
    unawaited(controller.initialize());
  }

  @override
  Widget build(BuildContext context) {
    AppColors.lightMode = controller.lightThemeEnabled;
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        AppColors.lightMode = controller.lightThemeEnabled;
        return MaterialApp(
          title: AppIdentity.instance.appDisplayName,
          debugShowCheckedModeBanner: false,
          theme: AppTheme.lightTheme,
          darkTheme: AppTheme.darkTheme,
          themeMode: controller.lightThemeEnabled
              ? ThemeMode.light
              : ThemeMode.dark,
          home: HomeScreen(controller: controller),
        );
      },
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
  final Set<String> _directCommandChats = <String>{};
  final Map<String, CancellationToken> _directCommandTokens =
      <String, CancellationToken>{};
  ModelsDevCatalog modelsDevCatalog = ModelsDevCatalog.empty();
  ShellRuntimeSettings shellRuntimeSettings = const ShellRuntimeSettings();
  CommandApprovalHandler? _commandApprovalHandler;
  ShellExecutor runtime;
  RuntimeStatus runtimeStatus = const RuntimeStatus(
    state: RuntimeState.notInstalled,
    message: 'Runtime status not checked yet.',
  );
  bool backgroundWorkAllowed = !Platform.isAndroid;
  String? backgroundWorkDetails;
  bool loading = true;
  String? lastError;
  String? startupError;
  List<ProjectSummary> projects = <ProjectSummary>[];
  List<Chat> chats = <Chat>[];
  List<ChatMessage> messages = <ChatMessage>[];
  List<Attachment> attachments = <Attachment>[];
  List<ToolExecution> toolExecutions = <ToolExecution>[];
  Map<String, Object?> chatTodo = const <String, Object?>{};
  List<ProviderConfig> providers = <ProviderConfig>[];
  Map<String, List<ProviderModel>> providerModels =
      <String, List<ProviderModel>>{};
  String? defaultProviderId;
  String? defaultModelName;
  bool diagnosticsRunning = false;
  String? diagnosticsText;
  bool lightThemeEnabled = false;
  bool updateChecking = false;
  UpdateManifest? availableUpdate;
  Project? selectedProject;
  Chat? selectedChat;
  AgentLimits limits = const AgentLimits();
  String? updateMessage;

  void setCommandApprovalHandler(CommandApprovalHandler? handler) {
    _commandApprovalHandler = handler;
    _agentLoop?.setCommandApprovalHandler(handler);
  }

  AppRepository get repository => _repository!;
  AgentLoop get agentLoop => _agentLoop!;

  Future<void> initialize() async {
    loading = true;
    lastError = null;
    startupError = null;
    try {
      final db = await _openDatabase();
      _repository = AppRepository(
        localDatabase: db,
        secretStore: _secretStore,
        chatStorageDirectory: _chatStorageDirectory,
      );
      await repository.migrateSettingsToOmp();
      modelsDevCatalog = await ModelsDevCatalog.load();
      _agentLoop = AgentLoop(
        repository: repository,
        modelsDevCatalog: modelsDevCatalog,
        shellExecutorFactory: _runtimeExecutorForProject,
        commandApproval: _commandApprovalHandler,
        onMessagesChanged: _refreshChatMessages,
        onStreamingMessageChanged: _updateStreamingMessage,
        onToolExecutionChanged: _updateToolExecution,
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
      startupError = 'App failed to start. Check development logs for details.';
      lastError = startupError;
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
    startupError = message;
    loading = false;
    notifyListeners();
  }

  void refreshVisibleState() => notifyListeners();
  Future<void> _refreshChatMessages(String chatId) async {
    if (selectedChat?.id != chatId) return;
    selectedChat = await repository.getChat(chatId);
    messages = await repository.listMessages(chatId);
    attachments = await _attachmentsForMessages(messages);
    toolExecutions = await repository.listToolExecutions(chatId);
    chatTodo = await repository.executeTodo(chatId, const {'op': 'view'});
    notifyListeners();
  }

  void _updateStreamingMessage(ChatMessage message) {
    if (selectedChat?.id != message.chatId) return;
    final index = messages.indexWhere((item) => item.id == message.id);
    if (index < 0) return;
    final updated = List<ChatMessage>.of(messages);
    updated[index] = message;
    messages = updated;
    notifyListeners();
  }

  void _updateToolExecution(ToolExecution execution) {
    if (selectedChat?.id != execution.chatId) return;
    final index = toolExecutions.indexWhere((item) => item.id == execution.id);
    if (index < 0) return;
    final updated = List<ToolExecution>.of(toolExecutions);
    updated[index] = execution;
    toolExecutions = updated;
    notifyListeners();
  }

  Future<List<Attachment>> _attachmentsForMessages(
    List<ChatMessage> chatMessages,
  ) async {
    final messageIds = chatMessages.map((message) => message.id).toSet();
    if (messageIds.isEmpty) return <Attachment>[];
    return (await repository.listAllAttachments())
        .where((attachment) => messageIds.contains(attachment.messageId))
        .toList(growable: false);
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
    final defaultSelection = await repository.readDefaultModelSelection();
    defaultProviderId = defaultSelection?['providerId'];
    defaultModelName = defaultSelection?['model'];
    limits = await repository.readAgentLimits();
    lightThemeEnabled = await repository.readLightTheme();
    shellRuntimeSettings = await repository.readShellRuntimeSettings();
    runtime = _executorForRuntime(shellRuntimeSettings.selected);
    runtimeStatus = RuntimeStatus(
      state: RuntimeState.notInstalled,
      message: '${shellRuntimeSettings.selected.label} status not checked yet.',
    );
    unawaited(refreshRuntimeStatus());
    unawaited(refreshBackgroundExecutionStatus());
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
        attachments = await _attachmentsForMessages(messages);
        toolExecutions = await repository.listToolExecutions(selectedChat!.id);
        chatTodo = await repository.executeTodo(selectedChat!.id, const {
          'op': 'view',
        });
      } else {
        messages = <ChatMessage>[];
        attachments = <Attachment>[];
        toolExecutions = <ToolExecution>[];
        chatTodo = const <String, Object?>{};
      }
    } else {
      messages = <ChatMessage>[];
      attachments = <Attachment>[];
      toolExecutions = <ToolExecution>[];
      chatTodo = const <String, Object?>{};
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

  bool isChatRunning(String chatId) =>
      _directCommandChats.contains(chatId) ||
      (_agentLoop?.isChatRunning(chatId) ?? false);

  Future<List<Map<String, Object?>>> listLocalRuntimeJobs() async {
    final executor = runtime;
    if (executor is! RuntimeJobExecutor) {
      return const <Map<String, Object?>>[];
    }
    final jobs = await (executor as RuntimeJobExecutor).listJobs();
    return jobs
        .whereType<Map<Object?, Object?>>()
        .map((job) => job.map((key, value) => MapEntry(key.toString(), value)))
        .toList(growable: false);
  }

  Future<void> cancelLocalRuntimeJob(String jobId) async {
    final executor = runtime;
    if (executor is! RuntimeJobExecutor) return;
    await (executor as RuntimeJobExecutor).cancelJob(jobId);
    await refreshRuntimeStatus();
  }

  Future<void> stopLocalRuntimeJob(String jobId) async {
    await cancelLocalRuntimeJob(jobId);
  }

  Future<void> restartLocalRuntimeJob(String jobId) async {
    final executor = runtime;
    if (executor is! ArchLinuxRuntime) return;
    await executor.restartJob(jobId);
    await refreshRuntimeStatus();
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
      lastError = Platform.isAndroid
          ? 'Could not create project. Check selected folder permissions.'
          : error.toString();
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
    attachments = <Attachment>[];
    toolExecutions = <ToolExecution>[];
    chatTodo = const <String, Object?>{};
    await refreshAll();
  }

  Future<void> openProject(Project project) async {
    selectedProject = project;
    selectedChat = null;
    messages = <ChatMessage>[];
    attachments = <Attachment>[];
    toolExecutions = <ToolExecution>[];
    chatTodo = const <String, Object?>{};
    chats = await repository.listChats(project.id);
    notifyListeners();
  }

  Future<void> openChat(Chat chat) async {
    selectedChat = chat;
    messages = await repository.listMessages(chat.id);
    attachments = await _attachmentsForMessages(messages);
    toolExecutions = await repository.listToolExecutions(chat.id);
    chatTodo = await repository.executeTodo(chat.id, const {'op': 'view'});
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
      attachments = <Attachment>[];
      toolExecutions = <ToolExecution>[];
      chatTodo = const <String, Object?>{};
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

  Future<void> sendMessage(
    String text,
    List<Attachment> attachments, {
    AIReasoningEffort? reasoningEffort = AIReasoningEffort.medium,
    bool includeThinking = true,
  }) async {
    final project = selectedProject;
    var chat = selectedChat;
    if (project == null) return;
    final directCommand = _directBashCommand(text);
    if (directCommand != null) {
      unawaited(
        _runDirectBash(
          project: project,
          chat: chat,
          userText: text,
          command: directCommand,
          attachments: attachments,
        ),
      );
      await refreshAll();
      return;
    }
    final prompt = await _prepareUserText(text, project.folderPath);
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
    unawaited(
      agentLoop
          .send(
            project: project,
            chat: chat,
            userText: prompt,
            attachments: attachments,
            reasoningEffort: reasoningEffort,
            includeThinking: includeThinking,
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

  ProviderConfig? get defaultProvider {
    for (final provider in providers) {
      if (provider.id == defaultProviderId) return provider;
    }
    return providers.firstOrNull;
  }

  ProviderConfig? _defaultProvider() => defaultProvider;

  ProviderModel? _firstModelForProvider(ProviderConfig? provider) {
    if (provider == null) return null;
    final models = providerModels[provider.id] ?? <ProviderModel>[];
    for (final model in models) {
      if (model.model == defaultModelName) return model;
    }
    return models.firstOrNull;
  }

  ProviderModel? get defaultModel {
    final provider = defaultProvider;
    if (provider == null) return null;
    return _firstModelForProvider(provider);
  }

  Future<void> saveDefaultModelSelection(ProviderModel model) async {
    await repository.saveDefaultModelSelection(
      providerId: model.providerId,
      model: model.model,
    );
    defaultProviderId = model.providerId;
    defaultModelName = model.model;
    notifyListeners();
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
    final directToken = _directCommandTokens[chat.id];
    if (directToken != null) {
      directToken.cancel();
      return;
    }
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
          providerKey: provider.providerKey,
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
          providerKey: provider.providerKey,
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
        providerKey: provider.providerKey,
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
      await tools.applyPatch(
        '''*** Begin Patch
*** Update File: .syntac_diag.txt
@@
-one
+two
*** End Patch''',
        expectedSnapshots: {'.syntac_diag.txt': readOne['snapshot']!},
      );
      final readTwo = await tools.readFile('.syntac_diag.txt');
      await tools.deletePath('.syntac_diag.txt');
      final diagPath =
          '${project.folderPath}${Platform.pathSeparator}.syntac_diag.txt';
      lines.add('write/read: ${readOne['content'] == 'one'}');
      lines.add('apply_patch/read: ${readTwo['content'] == 'two'}');
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

  Future<void> setLightTheme(bool enabled) async {
    lightThemeEnabled = enabled;
    AppColors.lightMode = enabled;
    await repository.saveLightTheme(enabled);
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
    if (Platform.isAndroid) {
      await const MethodChannel(
        'syntac/runtime',
      ).invokeMethod<void>('requestBackgroundExecution');
    }
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

  Future<bool> hasAndroidStorageAccess() async {
    if (!Platform.isAndroid) return true;
    try {
      final status = await const MethodChannel(
        'syntac/runtime',
      ).invokeMethod<Map<Object?, Object?>>('storageAccessStatus');
      return status?['granted'] == true;
    } catch (_) {
      return false;
    }
  }

  Future<void> openAndroidStorageSettings() async {
    if (!Platform.isAndroid) return;
    await const MethodChannel(
      'syntac/runtime',
    ).invokeMethod<void>('openStorageSettings');
    await refreshRuntimeStatus();
  }

  Future<void> refreshBackgroundExecutionStatus() async {
    if (!Platform.isAndroid) {
      backgroundWorkAllowed = true;
      backgroundWorkDetails = 'Background work is available on this platform.';
      notifyListeners();
      return;
    }
    try {
      final status = await const MethodChannel(
        'syntac/runtime',
      ).invokeMethod<Map<Object?, Object?>>('backgroundExecutionStatus');
      final battery = status?['batteryUnrestricted'] == true;
      final notifications = status?['notificationsGranted'] == true;
      backgroundWorkAllowed = battery && notifications;
      backgroundWorkDetails =
          status?['details']?.toString() ??
          'Battery unrestricted: ${battery ? 'yes' : 'no'}\n'
              'Runtime notification: ${notifications ? 'yes' : 'no'}';
    } catch (error) {
      backgroundWorkAllowed = false;
      backgroundWorkDetails = 'Background work status unavailable: $error';
    }
    notifyListeners();
  }

  Future<void> requestAndroidBackgroundExecution() async {
    if (!Platform.isAndroid) return;
    try {
      await const MethodChannel(
        'syntac/runtime',
      ).invokeMethod<void>('requestBackgroundExecution');
    } finally {
      await refreshBackgroundExecutionStatus();
    }
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

  String? _directBashCommand(String text) {
    final trimmed = text.trimLeft();
    if (!trimmed.startsWith('!')) return null;
    final command = trimmed.substring(1).trim();
    return command.isEmpty ? null : command;
  }

  Future<void> _runDirectBash({
    required Project project,
    required Chat? chat,
    required String userText,
    required String command,
    required List<Attachment> attachments,
  }) async {
    final initialRuntime = runtime;
    if (chat != null) chat = await repository.getChat(chat.id);
    if (chat == null) {
      final provider = _defaultProvider();
      final model = _firstModelForProvider(provider);
      chat = await repository.createChat(
        projectId: project.id,
        title: titleFromPrompt(command),
        providerId: provider?.id,
        modelId: model?.id,
      );
      selectedChat = chat;
    }
    if (isChatRunning(chat.id)) {
      lastError = 'This chat already has a running operation.';
      notifyListeners();
      return;
    }

    final directToken = CancellationToken();
    _directCommandChats.add(chat.id);
    _directCommandTokens[chat.id] = directToken;
    lastError = null;
    notifyListeners();
    ToolExecution? execution;
    try {
      final firstMessage = ChatMessage.create(
        chatId: chat.id,
        role: MessageRole.user,
        content: userText,
        metadata: attachments
            .map((attachment) => attachment.toMap())
            .toList(growable: false),
      );
      await repository.addMessage(firstMessage);
      for (final attachment in attachments) {
        await repository.addAttachment(
          Attachment.create(
            messageId: firstMessage.id,
            path: attachment.path,
            kind: attachment.kind,
            name: attachment.name,
            mimeType: attachment.mimeType,
          ),
        );
      }
      execution = ToolExecution.start(
        chatId: chat.id,
        name: 'bash',
        arguments: <String, Object?>{'command': command, 'source': 'user'},
      );
      await repository.addToolExecution(execution);
      await repository.setChatStatus(chat.id, ChatStatus.running);
      await _refreshChatMessages(chat.id);

      final shellExecutor =
          shellRuntimeSettings.selected == ShellRuntimeId.termux
          ? initialRuntime
          : await _runtimeExecutorForProject(project);
      final tools = ProjectTools(
        projectRoot: project.folderPath,
        shellExecutor: shellExecutor,
        commandApproval: _commandApprovalHandler,
        attachments: attachments,
      );
      var lastPreview = DateTime.fromMillisecondsSinceEpoch(0);
      final result = await tools.execute(
        'bash',
        <String, Object?>{'command': command},
        cancellationToken: directToken,
        commandTimeout: Duration(seconds: limits.commandTimeoutSeconds),
        onUpdate: (partialResult) async {
          final now = DateTime.now();
          if (now.difference(lastPreview).inMilliseconds < 250) return;
          lastPreview = now;
          final updated = execution!.runningResult({
            'ok': true,
            'result': partialResult,
          });
          await repository.updateToolExecution(updated);
          await _refreshChatMessages(chat!.id);
        },
      );
      final status = _directToolStatus(result);
      final completed = execution.finish(
        status: status,
        result: result,
        error: _directToolError(result, status),
      );
      await repository.updateToolExecution(completed);
      await repository.addMessage(
        ChatMessage.create(
          chatId: chat.id,
          role: MessageRole.tool,
          toolCallId: execution.id,
          content: jsonEncode(result),
          metadata: const {'source': 'user'},
        ),
      );
      await repository.setChatStatus(
        chat.id,
        status == ToolExecutionStatus.success
            ? ChatStatus.completed
            : status == ToolExecutionStatus.cancelled
            ? ChatStatus.interrupted
            : ChatStatus.error,
        error: _directToolError(result, status),
      );
      await _refreshChatMessages(chat.id);
    } catch (error, stackTrace) {
      logDetailedAIError(error, stackTrace, context: 'Direct bash failed');
      if (execution != null) {
        final errorResult = <String, Object?>{
          'ok': false,
          'category': 'direct_bash_error',
          'error': error.toString(),
        };
        await repository.updateToolExecution(
          execution.finish(
            status: ToolExecutionStatus.error,
            result: errorResult,
            error: error.toString(),
          ),
        );
        await repository.addMessage(
          ChatMessage.create(
            chatId: chat.id,
            role: MessageRole.tool,
            toolCallId: execution.id,
            content: jsonEncode(errorResult),
            metadata: const {'source': 'user'},
          ),
        );
        await repository.setChatStatus(
          chat.id,
          ChatStatus.error,
          error: error.toString(),
        );
        await _refreshChatMessages(chat.id);
      }
      lastError = error.toString();
      notifyListeners();
    } finally {
      _directCommandChats.remove(chat.id);
      _directCommandTokens.remove(chat.id);
      notifyListeners();
    }
  }

  ToolExecutionStatus _directToolStatus(Map<String, Object?> result) {
    if (result['cancelled'] == true) return ToolExecutionStatus.cancelled;
    final nested = result['result'];
    if (nested is Map && nested['cancelled'] == true) {
      return ToolExecutionStatus.cancelled;
    }
    if (result['ok'] != true) return ToolExecutionStatus.error;
    if (nested is Map && nested['success'] == false) {
      return ToolExecutionStatus.error;
    }
    return ToolExecutionStatus.success;
  }

  String? _directToolError(
    Map<String, Object?> result,
    ToolExecutionStatus status,
  ) {
    if (status == ToolExecutionStatus.success) return null;
    final nested = result['result'];
    if (nested is Map && nested['error'] != null) {
      return nested['error'].toString();
    }
    return result['error']?.toString() ?? result['category']?.toString();
  }

  Future<String> _prepareUserText(String text, String projectRoot) async {
    final trimmed = text.trim();
    if (utf8.encode(text).length <= 2048) return trimmed;
    return repository.saveLongPaste(text, projectRoot: projectRoot);
  }
}

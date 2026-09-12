// Runs agent turns, provider streaming, tools, persistence, and cancellation.

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'system_prompt.dart';

import '../ai/ai_error_messages.dart';
import '../ai/ai_provider.dart';
import '../ai/provider_error_store.dart';
import '../ai/auth/credential_store.dart';
import '../ai/google_cloud_code_assist_provider.dart';
import '../ai/oauth/google_antigravity_oauth.dart';
import '../ai/oauth/openai_codex_oauth.dart';
import '../ai/oauth/oauth_credential.dart';
import '../ai/oauth/xai_oauth.dart';
import '../ai/openai_provider.dart';
import '../ai/openai_codex_provider.dart';
import '../ai/models_dev_catalog.dart';
import '../ai/registry/provider_registry.dart';
import '../core/cancellation.dart';
import '../models.dart';
import '../runtime/shell_executor.dart';
import '../storage/app_repository.dart';
import '../tools/agent_tools.dart';
import '../tools/tool_context.dart';
import 'context_builder.dart';

class AgentLoop {
  AgentLoop({
    required AppRepository repository,
    ModelsDevCatalog? modelsDevCatalog,
    AIProvider Function(ProviderConfig provider)? providerFactory,
    Future<OAuthCredential> Function(OAuthCredential credential)?
    googleOAuthRefresh,
    Future<OAuthCredential> Function(OAuthCredential credential)?
    openAICodexOAuthRefresh,
    Future<OAuthCredential> Function(OAuthCredential credential)?
    xaiOAuthRefresh,
    Future<ShellExecutor> Function(Project project)? shellExecutorFactory,
    CommandApprovalHandler? commandApproval,
    Future<void> Function(String chatId)? onMessagesChanged,
    FutureOr<void> Function(ChatMessage message)? onStreamingMessageChanged,
    FutureOr<void> Function(ToolExecution execution)? onToolExecutionChanged,
  }) : _modelsDevCatalog = modelsDevCatalog ?? ModelsDevCatalog.empty(),
       _googleOAuthRefresh =
           googleOAuthRefresh ??
           ((credential) =>
               GoogleAntigravityOAuthFlow().refreshToken(credential)),
       _openAICodexOAuthRefresh =
           openAICodexOAuthRefresh ??
           ((credential) => OpenAICodexOAuthFlow().refreshToken(credential)),
       _xaiOAuthRefresh =
           xaiOAuthRefresh ??
           ((credential) => XAIOAuthFlow().refreshToken(credential)),
       _repository = repository,
       _onMessagesChanged = onMessagesChanged,
       _onStreamingMessageChanged = onStreamingMessageChanged,
       _onToolExecutionChanged = onToolExecutionChanged,
       _shellExecutorFactory =
           shellExecutorFactory ??
           ((project) async => ProjectToolsShellExecutor()),
       _commandApproval = commandApproval,
       _providerFactory =
           providerFactory ??
           ((provider) =>
               provider.providerKey == ProviderRegistry.googleAntigravity.id
               ? GoogleCloudCodeAssistProvider(
                   baseUrl: provider.baseUrl,
                   providerName: provider.name,
                 )
               : provider.providerKey == ProviderRegistry.openAICodex.id
               ? OpenAICodexProvider(
                   baseUrl: provider.baseUrl,
                   providerName: provider.name,
                 )
               : provider.providerKey == ProviderRegistry.grok.id ||
                     provider.providerKey == ProviderRegistry.grokOAuth.id
               ? OpenAIResponsesProvider(
                   baseUrl: provider.baseUrl,
                   providerName: provider.name,
                 )
               : OpenAICompatibleProvider(
                   baseUrl: provider.baseUrl,
                   providerName: provider.name,
                   providerKey: provider.providerKey,
                 ));

  final AppRepository _repository;
  final ModelsDevCatalog _modelsDevCatalog;
  final AIProvider Function(ProviderConfig provider) _providerFactory;
  CommandApprovalHandler? _commandApproval;
  final Future<ShellExecutor> Function(Project project) _shellExecutorFactory;
  final Future<void> Function(String chatId)? _onMessagesChanged;
  final FutureOr<void> Function(ChatMessage message)?
  _onStreamingMessageChanged;
  final FutureOr<void> Function(ToolExecution execution)?
  _onToolExecutionChanged;
  final Future<OAuthCredential> Function(OAuthCredential credential)
  _googleOAuthRefresh;
  final Future<OAuthCredential> Function(OAuthCredential credential)
  _openAICodexOAuthRefresh;
  final Future<OAuthCredential> Function(OAuthCredential credential)
  _xaiOAuthRefresh;
  final Map<String, CancellationToken> _activeRuns =
      <String, CancellationToken>{};

  bool isChatRunning(String chatId) => _activeRuns.containsKey(chatId);
  void setCommandApprovalHandler(CommandApprovalHandler? handler) {
    _commandApproval = handler;
  }

  Future<void> stop(String chatId) async {
    final token = _activeRuns[chatId];
    if (token == null) return;
    token.cancel();
    await _repository.setChatStatus(
      chatId,
      ChatStatus.interrupted,
      error: 'Stopped by user',
    );
  }

  Future<void> send({
    required Project project,
    required Chat chat,
    required String userText,
    List<Attachment> attachments = const <Attachment>[],
    AIReasoningEffort? reasoningEffort = AIReasoningEffort.medium,
    bool includeThinking = true,
  }) async {
    if (_activeRuns.containsKey(chat.id) ||
        await _repository.hasRunningJobForChat(chat.id)) {
      throw StateError('This chat already has a running agent job');
    }
    final token = CancellationToken();
    _activeRuns[chat.id] = token;
    var job = AgentJob.start(projectId: project.id, chatId: chat.id);
    String providerName = 'provider';
    AIChatRequest? lastRequest;
    try {
      await _repository.addAgentJob(job);
      await _repository.setChatStatus(chat.id, ChatStatus.running);
      final limits = await _repository.readAgentLimits();

      final firstMessage = ChatMessage.create(
        chatId: chat.id,
        role: MessageRole.user,
        content: userText,
        metadata: attachments.map((attachment) => attachment.toMap()).toList(),
      );
      await _repository.addMessage(firstMessage);
      for (final attachment in attachments) {
        await _repository.addAttachment(
          Attachment.create(
            messageId: firstMessage.id,
            path: attachment.path,
            kind: attachment.kind,
            name: attachment.name,
            mimeType: attachment.mimeType,
          ),
        );
      }
      if (chat.title == 'New chat' || chat.title.trim().isEmpty) {
        await _repository.updateChat(
          chat.copyWith(title: titleFromPrompt(userText)),
        );
      }
      final provider = await _selectProvider(chat.providerId);
      providerName = provider.name;
      final model = await _selectModel(provider, chat.modelId);
      final credential = await _repository.resolveProviderCredential(provider);
      OAuthCredential? refreshableOAuthCredential;
      var apiKey = switch (credential) {
        ApiKeyProviderCredential(:final apiKey) => apiKey,
        OAuthProviderCredential(:final credential) => () {
          refreshableOAuthCredential = credential;
          return credential.toStructuredApiKey();
        }(),
        null => '',
      };
      Future<String?> refreshOAuthCredential() async {
        final current = refreshableOAuthCredential;
        if (current == null) return null;
        final refreshed = switch (current.provider) {
          OAuthProviderId.openAICodex => await _openAICodexOAuthRefresh(
            current,
          ),
          OAuthProviderId.xaiOAuth => await _xaiOAuthRefresh(current),
          OAuthProviderId.googleAntigravity => await _googleOAuthRefresh(
            current,
          ),
        };
        refreshableOAuthCredential = refreshed;
        await _repository.saveOAuthCredential(provider.id, refreshed);
        apiKey = refreshed.toStructuredApiKey();
        return apiKey;
      }

      final currentOAuthCredential = refreshableOAuthCredential;
      if (currentOAuthCredential != null &&
          currentOAuthCredential.expiresWithin(const Duration(minutes: 5))) {
        apiKey = await refreshOAuthCredential() ?? apiKey;
      }
      if (apiKey.isEmpty) {
        throw StateError('Missing credentials for provider ${provider.name}');
      }

      final tools = ProjectTools(
        projectRoot: project.folderPath,
        shellExecutor: await _runtimeExecutorForProject(project),
        commandApproval: _commandApproval,
        attachments: attachments,
        todoHandler: (arguments) => _repository.executeTodo(chat.id, arguments),
      );
      final ai = _providerFactory(provider);
      final globalPrompt = await _repository.readGlobalSystemPrompt();
      final projectInstructions = await _readProjectInstructions(project);
      final effectivePrompt =
          projectInstructions != null && projectInstructions.trim().isNotEmpty
          ? projectInstructions
          : (globalPrompt ?? codingAgentSystemPrompt);
      final modelMetadata = _modelsDevCatalog.lookup(
        providerKey: provider.providerKey,
        modelId: model.model,
      );
      final contextCharacters =
          (_modelsDevCatalog.contextWindowFor(
                providerKey: provider.providerKey,
                modelId: model.model,
              ) ??
              0) *
          4;
      final contextBuilder = ContextBuilder(maxCharacters: contextCharacters);
      final imagePartsByMessageId = <String, List<AIImagePart>>{};
      for (var iteration = 0; iteration < limits.maxIterations; iteration++) {
        token.throwIfCancelled();
        job = job.update(currentAction: 'Thinking');
        await _repository.updateAgentJob(job);
        final history = await _repository.listMessages(chat.id);
        if (modelMetadata?.supportsImages == true) {
          await _loadImageParts(
            history,
            firstMessage: firstMessage,
            currentAttachments: attachments,
            cache: imagePartsByMessageId,
          );
        }
        final request = AIChatRequest(
          model: model.model,
          messages: contextBuilder.build(
            history: history,
            customSystemPrompt: effectivePrompt,
            imagePartsByMessageId: imagePartsByMessageId,
          ),
          tools: tools.specs,
          maxOutputTokens: modelMetadata?.outputLimit,
          reasoningEffort: reasoningEffort,
          includeThinking: includeThinking,
          supportsReasoning: modelMetadata?.reasoning == true,
          timeout: const Duration(seconds: 90),
        );
        lastRequest = request;
        final previewExecutions = <String, ToolExecution>{};
        final response = await _streamAssistantMessage(
          ai,
          request,
          apiKey: apiKey,
          refreshApiKey: refreshOAuthCredential,
          chatId: chat.id,
          cancellationToken: token,
          previewExecutions: previewExecutions,
        );
        if (response.toolCalls.isEmpty) {
          await _finish(
            job,
            chat.id,
            AgentJobState.completed,
            ChatStatus.completed,
          );
          return;
        }

        job = job.update(
          currentAction: response.toolCalls.length == 1
              ? _actionForTool(response.toolCalls.single)
              : 'Running ${response.toolCalls.length} tools',
        );
        await _repository.updateAgentJob(job);
        final startedToolCalls =
            <
              ({
                AIToolCall call,
                Map<String, Object?> args,
                ToolExecution execution,
              })
            >[];
        for (final call in response.toolCalls) {
          token.throwIfCancelled();
          final args = _decodeToolArguments(call);
          final preview = previewExecutions.remove(call.id);
          final execution =
              preview?.updateArguments(args) ??
              ToolExecution.start(
                chatId: chat.id,
                name: call.name,
                arguments: args,
              );
          if (preview == null) {
            await _repository.addToolExecution(execution);
          } else {
            await _repository.updateToolExecution(execution);
          }
          startedToolCalls.add((call: call, args: args, execution: execution));
        }
        await _onMessagesChanged?.call(chat.id);
        final completedToolCalls = await Future.wait(
          startedToolCalls.map((started) async {
            token.throwIfCancelled();
            var lastPreview = DateTime.fromMillisecondsSinceEpoch(0);
            var lastUiPreview = DateTime.fromMillisecondsSinceEpoch(0);
            final toolResult = await tools.execute(
              started.call.name,
              started.args,
              cancellationToken: token,
              commandTimeout: Duration(seconds: limits.commandTimeoutSeconds),
              onUpdate: (partialResult) async {
                final now = DateTime.now();
                final updated = started.execution.runningResult({
                  'ok': true,
                  'result': partialResult,
                });
                if (now.difference(lastUiPreview).inMilliseconds >= 33) {
                  lastUiPreview = now;
                  await _onToolExecutionChanged?.call(updated);
                }
                if (now.difference(lastPreview).inMilliseconds < 250) return;
                lastPreview = now;
                await _repository.updateToolExecution(updated);
              },
            );
            return (started: started, toolResult: toolResult);
          }),
        );
        for (final completed in completedToolCalls) {
          final status = _statusForToolResult(completed.toolResult);
          final execution = completed.started.execution.finish(
            status: status,
            result: completed.toolResult,
            error: _toolResultError(completed.toolResult, status),
          );
          await _repository.updateToolExecution(execution);
          if (!token.isCancelled) {
            await _repository.addMessage(
              ChatMessage.create(
                chatId: chat.id,
                role: MessageRole.tool,
                toolCallId: completed.started.call.id,
                content: jsonEncode(completed.toolResult),
              ),
            );
          }
          if (_isTermuxBackgroundRestricted(completed.toolResult)) {
            const message =
                'Android blocked Termux execution while Syntac was in the background. Keep Syntac open while commands are running.';
            await _repository.addMessage(
              ChatMessage.create(
                chatId: chat.id,
                role: MessageRole.internal,
                content: message,
              ),
            );
            await _finish(
              job,
              chat.id,
              AgentJobState.interrupted,
              ChatStatus.interrupted,
              error: message,
            );
            await _onMessagesChanged?.call(chat.id);
            return;
          }
          token.throwIfCancelled();
        }
        await _onMessagesChanged?.call(chat.id);
        token.throwIfCancelled();
      }
      throw StateError(
        'Agent stopped after ${limits.maxIterations} iterations to prevent an infinite loop',
      );
    } on OperationCancelledException {
      await _finish(
        job,
        chat.id,
        AgentJobState.interrupted,
        ChatStatus.interrupted,
        error: 'Stopped by user',
      );
    } catch (error, stackTrace) {
      logDetailedAIError(error, stackTrace, context: 'Agent loop failed');
      await persistProviderError(
        projectRoot: project.folderPath,
        chatId: chat.id,
        error: error,
        request: lastRequest,
      );
      final userMessage = describeAIErrorForUser(
        error,
        providerName: providerName,
      );
      await _repository.addMessage(
        ChatMessage.create(
          chatId: chat.id,
          role: MessageRole.internal,
          content: userMessage,
        ),
      );
      await _finish(
        job,
        chat.id,
        AgentJobState.error,
        ChatStatus.error,
        error: userMessage,
      );
      rethrow;
    } finally {
      _activeRuns.remove(chat.id);
    }
  }

  Future<void> _loadImageParts(
    List<ChatMessage> history, {
    required ChatMessage firstMessage,
    required List<Attachment> currentAttachments,
    required Map<String, List<AIImagePart>> cache,
  }) async {
    for (final message in history) {
      if (message.role != MessageRole.user || cache.containsKey(message.id)) {
        continue;
      }
      final messageAttachments = message.id == firstMessage.id
          ? currentAttachments
          : await _repository.listAttachments(message.id);
      final images = <AIImagePart>[];
      for (final attachment in messageAttachments) {
        if (attachment.kind != AttachmentKind.image) continue;
        final file = File(attachment.path);
        try {
          final length = await file.length();
          if (length <= 0 || length > 3 * 1024 * 1024) continue;
          final mimeType =
              attachment.mimeType ?? _imageMimeType(attachment.path);
          if (mimeType == null) continue;
          images.add(
            AIImagePart(
              mimeType: mimeType,
              base64Data: base64Encode(await file.readAsBytes()),
            ),
          );
        } catch (_) {
          // Missing or unreadable attachment remains visible as a fallback.
        }
      }
      cache[message.id] = images;
    }
  }

  String? _imageMimeType(String path) {
    final lower = path.toLowerCase();
    if (lower.endsWith('.png')) return 'image/png';
    if (lower.endsWith('.jpg') || lower.endsWith('.jpeg')) return 'image/jpeg';
    if (lower.endsWith('.gif')) return 'image/gif';
    if (lower.endsWith('.webp')) return 'image/webp';
    if (lower.endsWith('.bmp')) return 'image/bmp';
    if (lower.endsWith('.tif') || lower.endsWith('.tiff')) return 'image/tiff';
    return null;
  }

  Future<AIChatResponse> _streamAssistantMessage(
    AIProvider ai,
    AIChatRequest request, {
    required String apiKey,
    required Future<String?> Function() refreshApiKey,
    required String chatId,
    required CancellationToken cancellationToken,
    required Map<String, ToolExecution> previewExecutions,
  }) async {
    final requestStartedAt = DateTime.now();
    final buffer = StringBuffer();
    final thinkingBuffer = StringBuffer();
    var calls = const <AIToolCall>[];
    String? finishReason;
    var responseProviderMetadata = const <String, Object?>{};
    var streamSawDone = false;
    DateTime? firstNetworkChunkAt;
    DateTime? firstProviderEventAt;
    DateTime? firstTextDeltaAt;
    DateTime? firstUiDeltaAt;
    var assistant = ChatMessage.create(
      chatId: chatId,
      role: MessageRole.assistant,
      content: '',
      metadata: const {'streaming': true},
    );
    await _repository.addMessage(assistant);
    await _onMessagesChanged?.call(chatId);
    var lastPersistedLength = 0;
    var lastPersistedThinkingLength = 0;
    var lastPersistedAt = DateTime.now();
    var lastUiAt = DateTime.fromMillisecondsSinceEpoch(0);

    Future<void> persist({bool force = false}) async {
      final now = DateTime.now();
      final shouldPersist =
          force ||
          buffer.length - lastPersistedLength >= 24 ||
          thinkingBuffer.length - lastPersistedThinkingLength >= 24 ||
          now.difference(lastPersistedAt) >= const Duration(milliseconds: 120);
      final shouldRefreshUi =
          force || now.difference(lastUiAt) >= const Duration(milliseconds: 33);
      if (!shouldPersist && !shouldRefreshUi) return;
      assistant = assistant.copyWith(
        content: buffer.toString(),
        metadataJson: jsonEncode(<String, Object?>{
          'streaming': true,
          if (thinkingBuffer.isNotEmpty) 'thinking': thinkingBuffer.toString(),
        }),
      );
      final streamingCallback = _onStreamingMessageChanged;
      if (streamingCallback != null && shouldRefreshUi) {
        await streamingCallback(assistant);
        lastUiAt = now;
        if (buffer.isNotEmpty && firstUiDeltaAt == null) {
          firstUiDeltaAt = DateTime.now();
        }
      }
      if (!shouldPersist) return;
      await _repository.updateMessage(assistant);
      lastPersistedLength = buffer.length;
      lastPersistedThinkingLength = thinkingBuffer.length;
      lastPersistedAt = now;
      if (streamingCallback == null) {
        await _onMessagesChanged?.call(chatId);
        if (buffer.isNotEmpty && firstUiDeltaAt == null) {
          firstUiDeltaAt = DateTime.now();
        }
      }
    }

    var lastToolPreviewAt = DateTime.fromMillisecondsSinceEpoch(0);
    Future<void> updateToolPreviews(
      List<AIToolCall> previews, {
      bool force = false,
    }) async {
      final now = DateTime.now();
      if (!force &&
          now.difference(lastToolPreviewAt).inMilliseconds < 33 &&
          previewExecutions.isNotEmpty) {
        return;
      }
      lastToolPreviewAt = now;
      var added = false;
      for (final call in previews) {
        if (call.name.isEmpty) continue;
        final arguments = _decodePartialToolArguments(call.argumentsJson);
        final previous = previewExecutions[call.id];
        if (previous == null) {
          final execution = ToolExecution.start(
            chatId: chatId,
            name: call.name,
            arguments: arguments,
          );
          previewExecutions[call.id] = execution;
          await _repository.addToolExecution(execution);
          added = true;
        } else {
          final execution = previous.updateArguments(arguments);
          previewExecutions[call.id] = execution;
          await _onToolExecutionChanged?.call(execution);
        }
      }
      if (added) await _onMessagesChanged?.call(chatId);
    }

    var currentApiKey = apiKey;
    var retriedAfterRefresh = false;
    while (true) {
      try {
        await for (final event in ai.streamChat(
          request,
          apiKey: currentApiKey,
          cancellationToken: cancellationToken,
        )) {
          cancellationToken.throwIfCancelled();
          firstNetworkChunkAt ??= event.networkChunkAt;
          firstProviderEventAt ??= event.providerEventAt;
          if (event.done) {
            streamSawDone = true;
            calls = event.toolCalls;
            finishReason = event.finishReason;
            responseProviderMetadata = event.providerMetadata;
            await updateToolPreviews(calls, force: true);
          } else {
            if (event.toolCalls.isNotEmpty) {
              await updateToolPreviews(event.toolCalls);
            }
            if (event.thinkingDelta.isNotEmpty) {
              thinkingBuffer.write(event.thinkingDelta);
            }
            if (event.textDelta.isNotEmpty) {
              firstTextDeltaAt ??= DateTime.now();
              buffer.write(event.textDelta);
            }
            await persist();
          }
        }
        break;
      } on AIProviderException catch (error) {
        if (retriedAfterRefresh ||
            buffer.isNotEmpty ||
            thinkingBuffer.isNotEmpty ||
            calls.isNotEmpty ||
            !_isRefreshableAuthError(error)) {
          await persist(force: true);
          rethrow;
        }
        final refreshedApiKey = await refreshApiKey();
        if (refreshedApiKey == null || refreshedApiKey.isEmpty) rethrow;
        currentApiKey = refreshedApiKey;
        retriedAfterRefresh = true;
      }
    }
    if (!streamSawDone) {
      await persist(force: true);
      throw const AIProviderException(
        'Provider stream ended before completion marker',
        kind: 'incomplete_stream',
      );
    }
    await persist(force: true);
    final streamCompletedAt = DateTime.now();
    final firstUiDeltaAtValue = firstUiDeltaAt;
    assistant = assistant.copyWith(
      content: buffer.toString(),
      metadataJson: jsonEncode({
        'streaming': false,
        'finishReason': finishReason,
        if (thinkingBuffer.isNotEmpty) 'thinking': thinkingBuffer.toString(),
        'streamDiagnostics': {
          'requestStartedAt': requestStartedAt.toIso8601String(),
          if (firstNetworkChunkAt != null)
            'firstNetworkChunkAt': firstNetworkChunkAt.toIso8601String(),
          if (firstProviderEventAt != null)
            'firstProviderEventAt': firstProviderEventAt.toIso8601String(),
          if (firstTextDeltaAt != null)
            'firstTextDeltaAt': firstTextDeltaAt.toIso8601String(),
          if (firstUiDeltaAtValue != null)
            'firstUiDeltaAt': firstUiDeltaAtValue.toIso8601String(),
          'streamCompletedAt': streamCompletedAt.toIso8601String(),
          'realStreamingObserved':
              firstUiDeltaAtValue?.isBefore(streamCompletedAt) ?? false,
        },
        if (calls.isNotEmpty)
          'toolCalls': calls
              .map((call) => call.toOpenAIJson(includeProviderMetadata: true))
              .toList(),
        if (responseProviderMetadata.isNotEmpty)
          'providerNativeData': responseProviderMetadata,
        if (calls.any((call) => call.providerMetadata.isNotEmpty))
          'providerToolContinuity': calls
              .map(
                (call) => {
                  'toolCallId': call.id,
                  'thoughtSignatureReceived':
                      call.providerMetadata['thoughtSignatureReceived'] == true,
                  'thoughtSignaturePersisted':
                      call.providerMetadata['thoughtSignature'] is String,
                },
              )
              .toList(),
      }),
    );
    await _repository.updateMessage(assistant);
    await _onMessagesChanged?.call(chatId);
    if (buffer.isNotEmpty && firstUiDeltaAt == null) {
      firstUiDeltaAt = DateTime.now();
    }
    return AIChatResponse(
      text: buffer.toString(),
      toolCalls: calls,
      finishReason: finishReason,
    );
  }

  Future<ShellExecutor> _runtimeExecutorForProject(Project project) =>
      _shellExecutorFactory(project);

  Future<ProviderConfig> _selectProvider(String? providerId) async {
    if (providerId != null) {
      final provider = await _repository.getProvider(providerId);
      if (provider != null &&
          ProviderRegistry.isVisibleForBeta(provider.providerKey)) {
        return provider;
      }
    }
    final providers = (await _repository.listProviders())
        .where(
          (provider) => ProviderRegistry.isVisibleForBeta(provider.providerKey),
        )
        .toList(growable: false);
    if (providers.isEmpty) {
      throw StateError(
        'Configure an OpenAI-compatible provider before running the agent',
      );
    }
    return providers.first;
  }

  Future<ProviderModel> _selectModel(
    ProviderConfig provider,
    String? modelId,
  ) async {
    final models = await _repository.listProviderModels(provider.id);
    if (models.isEmpty) {
      throw StateError('Provider ${provider.name} has no configured models');
    }
    if (modelId != null) {
      for (final model in models) {
        if (model.id == modelId || model.model == modelId) return model;
      }
    }
    return models.first;
  }

  ToolExecutionStatus _statusForToolResult(Map<String, Object?> toolResult) {
    if (toolResult['cancelled'] == true) return ToolExecutionStatus.cancelled;
    final result = toolResult['result'];
    if (result is Map) {
      if (result['cancelled'] == true) return ToolExecutionStatus.cancelled;
      if (result['success'] == false) return ToolExecutionStatus.error;
      final category = result['category']?.toString();
      if (category == 'command_exit_error' ||
          category == 'timeout' ||
          category == 'runtime_failure' ||
          category == 'termux_background_restricted') {
        return ToolExecutionStatus.error;
      }
    }
    return toolResult['ok'] == true
        ? ToolExecutionStatus.success
        : ToolExecutionStatus.error;
  }

  String? _toolResultError(
    Map<String, Object?> toolResult,
    ToolExecutionStatus status,
  ) {
    if (status == ToolExecutionStatus.success) return null;
    if (toolResult['error'] != null) return toolResult['error']!.toString();
    final result = toolResult['result'];
    if (result is Map) {
      return result['message']?.toString() ??
          result['stderr']?.toString() ??
          result['category']?.toString();
    }
    return null;
  }

  bool _isTermuxBackgroundRestricted(Map<String, Object?> toolResult) {
    final result = toolResult['result'];
    if (result is Map) {
      return result['category'] == 'termux_background_restricted' ||
          result['failureKind'] == 'TermuxBackgroundRestricted';
    }
    return toolResult['category'] == 'termux_background_restricted';
  }

  bool _isRefreshableAuthError(AIProviderException error) =>
      error.statusCode == 401 || error.details?.httpStatus == 401;

  Map<String, Object?> _decodeToolArguments(AIToolCall call) {
    try {
      final decoded = jsonDecode(call.argumentsJson);
      if (decoded is Map) return decoded.cast<String, Object?>();
      return <String, Object?>{
        '_error': 'Tool arguments were not an object',
        'raw': call.argumentsJson,
      };
    } catch (error) {
      return <String, Object?>{
        '_error': 'Malformed tool arguments: $error',
        'raw': call.argumentsJson,
      };
    }
  }

  String _actionForTool(AIToolCall call) => switch (call.name) {
    'read' => 'Reading ${_pathFromArgs(call.argumentsJson)}',
    'write' => 'Writing ${_pathFromArgs(call.argumentsJson)}',
    'apply_patch' => 'Applying patch',
    'delete' => 'Deleting ${_pathFromArgs(call.argumentsJson)}',
    'list' => 'Listing ${_pathFromArgs(call.argumentsJson)}',
    'glob' => 'Matching project paths',
    'search' => 'Searching project',
    'bash' => 'Running command',
    'jobs.list' || 'jobs_list' => 'Listing runtime jobs',
    'jobs.status' || 'jobs_status' => 'Reading job status',
    'jobs.logs' || 'jobs_logs' => 'Reading job logs',
    'jobs.wait' || 'jobs_wait' => 'Waiting for job',
    'jobs.cancel' || 'jobs_cancel' => 'Cancelling job',
    _ => 'Running ${call.name}',
  };

  String _pathFromArgs(String raw) {
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map && decoded['path'] != null) {
        return decoded['path'].toString();
      }
    } catch (_) {}
    return 'project';
  }

  Future<void> _finish(
    AgentJob job,
    String chatId,
    AgentJobState jobState,
    ChatStatus chatStatus, {
    String? error,
  }) async {
    await _repository.updateAgentJob(
      job.update(
        state: jobState,
        currentAction: jobState == AgentJobState.completed
            ? 'Completed'
            : 'Stopped',
        error: error,
        complete: true,
      ),
    );
    await _repository.setChatStatus(chatId, chatStatus, error: error);
  }

  Future<String?> _readProjectInstructions(Project project) async {
    final candidatePaths = [
      '${project.folderPath}${Platform.pathSeparator}.syntac${Platform.pathSeparator}agent${Platform.pathSeparator}SYSTEM.md',
      '${project.folderPath}${Platform.pathSeparator}AGENTS.md',
    ];
    for (final path in candidatePaths) {
      try {
        final file = File(path);
        if (!await file.exists()) continue;
        final bytes = <int>[];
        await for (final chunk in file.openRead(0, 480000)) {
          final remaining = 480000 - bytes.length;
          bytes.addAll(
            chunk.length <= remaining ? chunk : chunk.sublist(0, remaining),
          );
          if (bytes.length >= 480000) break;
        }
        final content = utf8.decode(bytes, allowMalformed: true).trim();
        if (content.isNotEmpty) return content;
      } catch (_) {
        // Missing or unreadable instructions do not block agent startup.
      }
    }
    return null;
  }
}

Map<String, Object?> _decodePartialToolArguments(String raw) {
  if (raw.trim().isEmpty) return <String, Object?>{};
  try {
    final decoded = jsonDecode(raw);
    if (decoded is Map) return Map<String, Object?>.from(decoded);
  } catch (_) {}

  final result = <String, Object?>{};
  final keyPattern = RegExp(r'"((?:\\.|[^"\\])*)"\s*:\s*');
  final matches = keyPattern.allMatches(raw).toList(growable: false);
  for (var index = 0; index < matches.length; index++) {
    final match = matches[index];
    final key = _decodePartialJsonString('"${match.group(1)!}"');
    if (key == null) continue;
    final valueStart = match.end;
    if (valueStart >= raw.length || raw.codeUnitAt(valueStart) != 0x22) {
      continue;
    }
    var escaped = false;
    var valueEnd = valueStart + 1;
    for (; valueEnd < raw.length; valueEnd++) {
      final code = raw.codeUnitAt(valueEnd);
      if (escaped) {
        escaped = false;
      } else if (code == 0x5c) {
        escaped = true;
      } else if (code == 0x22) {
        valueEnd += 1;
        break;
      }
    }
    final encoded = valueEnd <= raw.length
        ? raw.substring(valueStart, valueEnd)
        : raw.substring(valueStart);
    final value = _decodePartialJsonString(encoded);
    if (value != null) result[key] = value;
  }
  return result;
}

String? _decodePartialJsonString(String encoded) {
  var candidate = encoded;
  var escaped = false;
  var closed = false;
  for (var index = 1; index < candidate.length; index++) {
    final code = candidate.codeUnitAt(index);
    if (escaped) {
      escaped = false;
    } else if (code == 0x5c) {
      escaped = true;
    } else if (code == 0x22) {
      closed = true;
      break;
    }
  }
  if (!closed) {
    if (escaped) candidate = candidate.substring(0, candidate.length - 1);
    candidate = '$candidate"';
  }
  try {
    final decoded = jsonDecode(candidate);
    return decoded is String ? decoded : null;
  } catch (_) {
    return null;
  }
}

String titleFromPrompt(String prompt) {
  final compact = prompt.trim().replaceAll(RegExp(r'\s+'), ' ');
  if (compact.isEmpty) return 'New chat';
  return compact.length <= 48 ? compact : '${compact.substring(0, 45)}...';
}

class ProjectToolsShellExecutor extends PlatformShellExecutor {}

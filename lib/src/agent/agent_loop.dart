import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'system_prompt.dart';

import '../ai/ai_error_messages.dart';
import '../ai/ai_provider.dart';
import '../ai/auth/credential_store.dart';
import '../ai/google_cloud_code_assist_provider.dart';
import '../ai/oauth/google_antigravity_oauth.dart';
import '../ai/oauth/oauth_credential.dart';
import '../ai/openai_provider.dart';
import '../ai/registry/provider_registry.dart';
import '../core/cancellation.dart';
import '../models.dart';
import '../runtime/shell_executor.dart';
import '../storage/app_repository.dart';
import '../tools/agent_tools.dart';
import 'context_builder.dart';

class AgentLoop {
  AgentLoop({
    required AppRepository repository,
    AIProvider Function(ProviderConfig provider)? providerFactory,
    Future<OAuthCredential> Function(OAuthCredential credential)?
    googleOAuthRefresh,
    Future<ShellExecutor> Function(Project project)? shellExecutorFactory,
    Future<void> Function(String chatId)? onMessagesChanged,
  }) : _googleOAuthRefresh =
           googleOAuthRefresh ??
           ((credential) =>
               GoogleAntigravityOAuthFlow().refreshToken(credential)),
       _repository = repository,
       _onMessagesChanged = onMessagesChanged,
       _shellExecutorFactory =
           shellExecutorFactory ??
           ((project) async => ProjectToolsShellExecutor()),
       _providerFactory =
           providerFactory ??
           ((provider) =>
               provider.providerKey == ProviderRegistry.googleAntigravity.id
               ? GoogleCloudCodeAssistProvider(
                   baseUrl: provider.baseUrl,
                   providerName: provider.name,
                 )
               : OpenAICompatibleProvider(
                   baseUrl: provider.baseUrl,
                   providerName: provider.name,
                 ));

  final AppRepository _repository;
  final AIProvider Function(ProviderConfig provider) _providerFactory;
  final Future<ShellExecutor> Function(Project project) _shellExecutorFactory;
  final Future<void> Function(String chatId)? _onMessagesChanged;
  final Future<OAuthCredential> Function(OAuthCredential credential)
  _googleOAuthRefresh;
  final Map<String, CancellationToken> _activeRuns =
      <String, CancellationToken>{};

  bool isChatRunning(String chatId) => _activeRuns.containsKey(chatId);

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
  }) async {
    if (_activeRuns.containsKey(chat.id) ||
        await _repository.hasRunningJobForChat(chat.id)) {
      throw StateError('This chat already has a running agent job');
    }
    final token = CancellationToken();
    _activeRuns[chat.id] = token;
    var job = AgentJob.start(projectId: project.id, chatId: chat.id);
    String providerName = 'provider';

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
      OAuthCredential? refreshableGoogleCredential;
      var apiKey = switch (credential) {
        ApiKeyProviderCredential(:final apiKey) => apiKey,
        OAuthProviderCredential(:final credential) => () {
          if (credential.provider == OAuthProviderId.googleAntigravity) {
            refreshableGoogleCredential = credential;
          }
          return credential.toStructuredApiKey();
        }(),
        null => '',
      };
      Future<String?> refreshGoogleCredential() async {
        final current = refreshableGoogleCredential;
        if (current == null) return null;
        final refreshed = await _googleOAuthRefresh(current);
        refreshableGoogleCredential = refreshed;
        await _repository.saveOAuthCredential(provider.id, refreshed);
        apiKey = refreshed.toStructuredApiKey();
        return apiKey;
      }

      final currentGoogleCredential = refreshableGoogleCredential;
      if (currentGoogleCredential != null &&
          currentGoogleCredential.expiresWithin(const Duration(minutes: 5))) {
        apiKey = await refreshGoogleCredential() ?? apiKey;
      }
      if (apiKey.isEmpty) {
        throw StateError('Missing credentials for provider ${provider.name}');
      }

      final tools = ProjectTools(
        projectRoot: project.folderPath,
        shellExecutor: await _runtimeExecutorForProject(project),
      );
      final ai = _providerFactory(provider);
      final globalPrompt = await _repository.readGlobalSystemPrompt();
      final projectInstructions = await _readProjectInstructions(project);
      final effectivePrompt =
          projectInstructions != null && projectInstructions.isNotEmpty
          ? '${globalPrompt ?? codingAgentSystemPrompt}\n\n# Project Instructions\n$projectInstructions'
          : (globalPrompt ?? codingAgentSystemPrompt);
      final contextBuilder = ContextBuilder(
        maxCharacters: limits.maxContextCharacters,
      );

      for (var iteration = 0; iteration < limits.maxIterations; iteration++) {
        token.throwIfCancelled();
        job = job.update(currentAction: 'Thinking');
        await _repository.updateAgentJob(job);
        final history = await _repository.listMessages(chat.id);
        final request = AIChatRequest(
          model: model.model,
          messages: contextBuilder.build(
            history: history,
            customSystemPrompt: effectivePrompt,
          ),
          tools: tools.specs,
          timeout: const Duration(seconds: 90),
        );
        final response = await _streamAssistantMessage(
          ai,
          request,
          apiKey: apiKey,
          refreshApiKey: refreshGoogleCredential,
          chatId: chat.id,
          cancellationToken: token,
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
          final execution = ToolExecution.start(
            chatId: chat.id,
            name: call.name,
            arguments: args,
          );
          await _repository.addToolExecution(execution);
          startedToolCalls.add((call: call, args: args, execution: execution));
        }
        await _onMessagesChanged?.call(chat.id);
        final completedToolCalls = await Future.wait(
          startedToolCalls.map((started) async {
            token.throwIfCancelled();
            var lastPreview = DateTime.fromMillisecondsSinceEpoch(0);
            final toolResult = await tools.execute(
              started.call.name,
              started.args,
              cancellationToken: token,
              commandTimeout: Duration(seconds: limits.commandTimeoutSeconds),
              onUpdate: (partialResult) async {
                final now = DateTime.now();
                if (now.difference(lastPreview).inMilliseconds < 250) return;
                lastPreview = now;
                await _repository.updateToolExecution(
                  started.execution.runningResult({
                    'ok': true,
                    'result': partialResult,
                  }),
                );
                await _onMessagesChanged?.call(chat.id);
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
      final userMessage = describeAIErrorForUser(
        error,
        providerName: providerName,
      );
      await _repository.addMessage(
        ChatMessage.create(
          chatId: chat.id,
          role: MessageRole.internal,
          content: 'Agent error: $userMessage',
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

  Future<AIChatResponse> _streamAssistantMessage(
    AIProvider ai,
    AIChatRequest request, {
    required String apiKey,
    required Future<String?> Function() refreshApiKey,
    required String chatId,
    required CancellationToken cancellationToken,
  }) async {
    final requestStartedAt = DateTime.now();
    final buffer = StringBuffer();
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
    );
    await _repository.addMessage(assistant);
    await _onMessagesChanged?.call(chatId);
    var lastPersistedLength = 0;
    var lastPersistedAt = DateTime.now();

    Future<void> persist({bool force = false}) async {
      final now = DateTime.now();
      if (!force &&
          buffer.length - lastPersistedLength < 24 &&
          now.difference(lastPersistedAt) < const Duration(milliseconds: 120)) {
        return;
      }
      assistant = assistant.copyWith(content: buffer.toString());
      await _repository.updateMessage(assistant);
      lastPersistedLength = buffer.length;
      lastPersistedAt = now;
      await _onMessagesChanged?.call(chatId);
      if (buffer.isNotEmpty && firstUiDeltaAt == null) {
        firstUiDeltaAt = DateTime.now();
      }
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
          } else {
            firstTextDeltaAt ??= DateTime.now();
            buffer.write(event.textDelta);
            await persist();
          }
        }
        break;
      } on AIProviderException catch (error) {
        if (retriedAfterRefresh ||
            buffer.isNotEmpty ||
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
        'finishReason': finishReason,
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
    'edit' => 'Editing ${_pathFromArgs(call.argumentsJson)}',
    'delete' => 'Deleting ${_pathFromArgs(call.argumentsJson)}',
    'list' => 'Listing ${_pathFromArgs(call.argumentsJson)}',
    'search' => 'Searching project',
    'bash' => 'Running command',
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
      '${project.folderPath}${Platform.pathSeparator}.syntac${Platform.pathSeparator}agent${Platform.pathSeparator}AGENTS.md',
      '${project.folderPath}${Platform.pathSeparator}AGENTS.md',
    ];
    for (final path in candidatePaths) {
      try {
        final file = File(path);
        if (await file.exists()) {
          final content = await file.readAsString();
          if (content.trim().isNotEmpty) return content.trim();
        }
      } catch (_) {}
    }
    return null;
  }
}

String titleFromPrompt(String prompt) {
  final compact = prompt.trim().replaceAll(RegExp(r'\s+'), ' ');
  if (compact.isEmpty) return 'New chat';
  return compact.length <= 48 ? compact : '${compact.substring(0, 45)}...';
}

class ProjectToolsShellExecutor extends PlatformShellExecutor {}
